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

  struct ArticleTranslation: Codable, Equatable {
    let title: String
    let markdown: String

    enum CodingKeys: String, CodingKey {
      case title = "translated_title"
      case markdown = "translated_markdown"
    }
  }

  // Core Logic
  func summarize(title: String, url: String?, articleContent: String?, comments: [String])
    async throws -> String
  {
    // Read API key from Keychain (secure storage)
    let apiKey = KeychainHelper.read(key: "ai_api_key") ?? ""
    let baseUrl = UserDefaults.standard.string(forKey: "ai_base_url") ?? AIDefaults.baseURL
    let model = UserDefaults.standard.string(forKey: "ai_model") ?? AIDefaults.model

    guard !apiKey.isEmpty else {
      throw NSError(
        domain: "AIService", code: 401,
        userInfo: [
          NSLocalizedDescriptionKey: "API Key is missing. Please configure it in Settings."
        ])
    }

    // Construct Prompt
    let preferredLang = UserDefaults.standard.string(forKey: "preferred_language") ?? "system"
    let prompt = Self.buildSummaryPrompt(
      title: title,
      url: url,
      articleContent: articleContent,
      comments: comments,
      preferredLanguage: preferredLang
    )

    return try await sendChatCompletion(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      systemMessage: "You are a helpful assistant.",
      userPrompt: prompt,
      temperature: 0.7
    )
  }

  func translateArticle(
    title: String,
    articleText: String,
    targetLanguage: String
  ) async throws -> ArticleTranslation {
    let apiKey = KeychainHelper.read(key: "ai_api_key") ?? ""
    let baseUrl = UserDefaults.standard.string(forKey: "ai_base_url") ?? AIDefaults.baseURL
    let model = UserDefaults.standard.string(forKey: "ai_model") ?? AIDefaults.model

    guard !apiKey.isEmpty else {
      throw NSError(
        domain: "AIService", code: 401,
        userInfo: [
          NSLocalizedDescriptionKey: "API Key is missing. Please configure it in Settings."
        ])
    }

    let prompt = Self.buildArticleTranslationPrompt(
      title: title,
      articleText: articleText,
      targetLanguage: targetLanguage
    )
    let response = try await sendChatCompletion(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      systemMessage: "You translate technical articles faithfully for Hacker News readers.",
      userPrompt: prompt,
      temperature: 0.2
    )

    return try Self.decodeArticleTranslation(response)
  }

  func translateTitle(
    _ title: String,
    targetLanguage: String
  ) async throws -> String {
    let apiKey = KeychainHelper.read(key: "ai_api_key") ?? ""
    let baseUrl = UserDefaults.standard.string(forKey: "ai_base_url") ?? AIDefaults.baseURL
    let model = UserDefaults.standard.string(forKey: "ai_model") ?? AIDefaults.model

    guard !apiKey.isEmpty else {
      throw NSError(
        domain: "AIService", code: 401,
        userInfo: [
          NSLocalizedDescriptionKey: "API Key is missing. Please configure it in Settings."
        ])
    }

    let response = try await sendChatCompletion(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      systemMessage: "You translate Hacker News story titles faithfully.",
      userPrompt: Self.buildTitleTranslationPrompt(title: title, targetLanguage: targetLanguage),
      temperature: 0.1
    )

    return Self.cleanTranslatedTitle(response)
  }

  private func sendChatCompletion(
    apiKey: String,
    baseUrl: String,
    model: String,
    systemMessage: String,
    userPrompt: String,
    temperature: Double
  ) async throws -> String {
    let requestBody = ChatRequest(
      model: model,
      messages: [
        ChatMessage(role: "system", content: systemMessage),
        ChatMessage(role: "user", content: userPrompt),
      ],
      temperature: temperature
    )

    let endpoint =
      URL(string: baseUrl)?.appendingPathComponent("chat/completions") ?? URL(
        string: "\(AIDefaults.baseURL)/chat/completions")!

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

  static func buildArticleTranslationPrompt(
    title: String,
    articleText: String,
    targetLanguage: String
  ) -> String {
    let languageName = ReadingLanguage.displayName(for: targetLanguage)
    let clippedArticle = String(articleText.prefix(8_000))

    return """
      Translate this Hacker News article for a technical reader.

      Target language: \(languageName)

      Rules:
      - Preserve the author's meaning and uncertainty. Do not add new opinions.
      - Keep product names, code, API names, commands, URLs, and library names unchanged.
      - Use natural technical wording in the target language.
      - Convert the article body to clean Markdown.
      - Return JSON only, with no code fence and no extra commentary.

      JSON schema:
      {
        "translated_title": "translated title",
        "translated_markdown": "translated article body in Markdown"
      }

      Original title:
      \(title)

      Original article excerpt:
      \(clippedArticle)
      """
  }

  static func buildTitleTranslationPrompt(title: String, targetLanguage: String) -> String {
    let languageName = ReadingLanguage.displayName(for: targetLanguage)

    return """
      Translate this Hacker News story title to \(languageName).

      Rules:
      - Return only the translated title.
      - Preserve product names, project names, code names, API names, and version numbers.
      - Keep the title concise and natural for technical readers.
      - Do not add commentary, quotes, bullets, or markdown.

      Title:
      \(title)
      """
  }

  static func cleanTranslatedTitle(_ response: String) -> String {
    response
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func decodeArticleTranslation(_ response: String) throws -> ArticleTranslation {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    let jsonText: String

    if trimmed.hasPrefix("```") {
      jsonText =
        trimmed
        .replacingOccurrences(of: "```json", with: "")
        .replacingOccurrences(of: "```JSON", with: "")
        .replacingOccurrences(of: "```", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let start = trimmed.firstIndex(of: "{"),
      let end = trimmed.lastIndex(of: "}")
    {
      jsonText = String(trimmed[start...end])
    } else {
      jsonText = trimmed
    }

    let data = Data(jsonText.utf8)
    return try JSONDecoder().decode(ArticleTranslation.self, from: data)
  }

  static func buildSummaryPrompt(
    title: String,
    url: String?,
    articleContent: String?,
    comments: [String],
    preferredLanguage: String,
    localeIdentifier: String = Locale.current.identifier
  ) -> String {
    var prompt = "You are a tech-savvy summarizer for Hacker News users. \n"
    prompt += "Story Title: \(title)\n"
    if let url = url {
      prompt += "URL: \(url)\n"
    }

    let targetLanguage = ReadingLanguage.resolvedCode(
      preferredLanguage: preferredLanguage,
      localeIdentifier: localeIdentifier
    )
    let languageName = ReadingLanguage.displayName(for: targetLanguage)
    let summaryFormat = ReadingLanguage.summaryFormat(for: targetLanguage)
    let langInstruction = "Answer in \(languageName)."

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

    return prompt
  }

  static func shouldUseChineseSummary(
    preferredLanguage: String,
    localeIdentifier: String = Locale.current.identifier
  ) -> Bool {
    let code = ReadingLanguage.resolvedCode(
      preferredLanguage: preferredLanguage,
      localeIdentifier: localeIdentifier
    )
    return code.starts(with: "zh")
  }
}
