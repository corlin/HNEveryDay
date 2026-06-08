//
//  AIService.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import Foundation

final class AIService: Sendable {
  static let shared = AIService()

  // Request Models
  struct ChatMessage: Codable {
    let role: String
    let content: String
  }

  struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
  }

  struct ChatResponse: Codable {
    struct Choice: Codable {
      let message: ChatMessage
    }
    let choices: [Choice]
  }

  // Core Logic
  func summarize(title: String, url: String?, articleContent: String?, comments: [String])
    async throws -> String
  {
    // Read API key from Keychain (secure storage)
    let apiKey = KeychainHelper.read(key: "ai_api_key") ?? ""
    let baseUrl = UserDefaults.standard.string(forKey: "ai_base_url") ?? "https://api.openai.com/v1"
    let model = UserDefaults.standard.string(forKey: "ai_model") ?? "gpt-3.5-turbo"

    guard !apiKey.isEmpty else {
      throw NSError(
        domain: "AIService", code: 401,
        userInfo: [
          NSLocalizedDescriptionKey: "API Key is missing. Please configure it in Settings."
        ])
    }

    // Construct Prompt
    var prompt = "You are a tech-savvy summarizer for Hacker News users. \n"
    prompt += "Story Title: \(title)\n"
    if let url = url {
      prompt += "URL: \(url)\n"
    }

    // Localization Check - Respect user preference
    let preferredLang = UserDefaults.standard.string(forKey: "preferred_language") ?? "system"
    let isChinese: Bool
    if preferredLang == "system" {
      isChinese = Locale.current.identifier.lowercased().starts(with: "zh")
    } else {
      isChinese = preferredLang == "zh-Hans"
    }
    let summaryFormat: String
    if isChinese {
      summaryFormat = """
        ## 📝 文章核心
        [用 2-3 句话总结文章核心价值]

        ## 💬 讨论焦点
        - **[要点 1]**: [简要说明]
        - **[要点 2]**: [简要说明]
        - **[要点 3]**: [简要说明]

        ## 🎯 结论
        [用 1-2 句话给出综合判断]
        """
    } else {
      summaryFormat = """
        ## 📝 Core Idea
        [2-3 sentences summarizing the article's core value proposition]

        ## 💬 Discussion Focus
        - **[Key Point 1]**: [Brief explanation]
        - **[Key Point 2]**: [Brief explanation]
        - **[Key Point 3]**: [Brief explanation]

        ## 🎯 Takeaway
        [1-2 sentences with your synthesis]
        """
    }
    let langInstruction =
      isChinese
      ? "Answer in Simplified Chinese (简体中文)."
      : "Answer in English."

    if let content = articleContent, !content.isEmpty {
      prompt += "\nArticle Content (Excerpt):\n"
      // Limit article content to avoid context overflow (approx 1000 chars or reasonable limit)
      prompt += "\(content.prefix(2000))...\n"
    }

    prompt += "\nTop Comments:\n"
    for comment in comments.prefix(20) {  // Limit to top 20 comments to fit context window
      // Strip excessive newlines and HTML tags roughly
      let cleanComment = comment.replacingOccurrences(
        of: "<[^>]+>", with: "", options: .regularExpression)
      prompt += "- \(cleanComment.prefix(300))...\n"  // Truncate individual comments
    }

    prompt +=
      """

      Task: Provide a well-structured summary using the following format:

      \(summaryFormat)

      Keep it concise (under 250 words). Use bullet points for clarity. \(langInstruction)
      """

    // Build Request
    let requestBody = ChatRequest(
      model: model,
      messages: [
        ChatMessage(role: "system", content: "You are a helpful assistant."),
        ChatMessage(role: "user", content: prompt),
      ],
      temperature: 0.7
    )

    let endpoint =
      URL(string: baseUrl)?.appendingPathComponent("chat/completions") ?? URL(
        string: "https://api.openai.com/v1/chat/completions")!

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(requestBody)

    // Retry Logic: 3 attempts
    var lastError: Error?
    for attempt in 1...3 {
      do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
          throw NSError(
            domain: "AIService", code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Invalid Response"])
        }

        // Success
        if httpResponse.statusCode == 200 {
          let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
          return chatResponse.choices.first?.message.content ?? "No response content."
        }

        // Server Error (Rate Limit / 5xx) -> Retry
        // Client Error (401/400) -> Fail immediately (don't retry authentication errors)
        if (500...599).contains(httpResponse.statusCode) || httpResponse.statusCode == 429 {
          let errorMsg = String(data: data, encoding: .utf8) ?? "Server Error"
          throw NSError(
            domain: "AIService", code: httpResponse.statusCode,
            userInfo: [NSLocalizedDescriptionKey: errorMsg])
        } else {
          // 4xx Errors (except 429) - Fatal
          let errorMsg = String(data: data, encoding: .utf8) ?? "Client Error"
          throw NSError(
            domain: "AIService", code: httpResponse.statusCode,
            userInfo: [NSLocalizedDescriptionKey: "API Request Failed: \(errorMsg)"])
        }

      } catch {
        print("⚠️ Attempt \(attempt) failed: \(error.localizedDescription)")
        lastError = error

        // Check if we should retry (don't retry 401/403/400)
        let nsError = error as NSError
        if [400, 401, 403].contains(nsError.code) {
          throw error
        }

        // Wait before retry (exponential backoff-ish)
        if attempt < 3 {
          try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
        }
      }
    }

    // If we're here, all retries failed
    throw lastError
      ?? NSError(
        domain: "AIService", code: 500,
        userInfo: [NSLocalizedDescriptionKey: "Failed after 3 retries."])
  }
}
