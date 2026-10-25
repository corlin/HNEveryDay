//
//  BYOKAIProvider.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import Foundation

/// Advanced mode: talks directly to the user's own OpenAI-compatible provider with their API key.
/// Requests never pass through the HNEveryDay backend and are not metered.
nonisolated final class BYOKAIProvider: AIProvider {
  static let apiKeyAccount = "ai_api_key"

  nonisolated struct Credentials: Sendable {
    let apiKey: String
    let baseURL: String
    let model: String
  }

  static var hasAPIKey: Bool {
    !(KeychainHelper.read(key: apiKeyAccount) ?? "").isEmpty
  }

  static func credentials() throws -> Credentials {
    let apiKey = KeychainHelper.read(key: apiKeyAccount) ?? ""
    guard !apiKey.isEmpty else { throw AIServiceError.missingAPIKey }
    return Credentials(
      apiKey: apiKey,
      baseURL: UserDefaults.standard.string(forKey: "ai_base_url") ?? AIDefaults.baseURL,
      model: UserDefaults.standard.string(forKey: "ai_model") ?? AIDefaults.model
    )
  }

  func summarize(
    storyId: Int?,
    title: String,
    url: String?,
    articleContent: String?,
    comments: [String],
    preferredLanguage: String
  ) async throws -> String {
    let credentials = try Self.credentials()
    let prompt = AIService.buildSummaryPrompt(
      title: title,
      url: url,
      articleContent: articleContent,
      comments: comments,
      preferredLanguage: preferredLanguage
    )
    return try await Self.sendChatCompletion(
      credentials: credentials,
      messages: [
        ChatMessage(role: "system", content: "You are a helpful assistant."),
        ChatMessage(role: "user", content: prompt),
      ],
      temperature: 0.7
    )
  }

  func translateArticle(
    storyId: Int?,
    title: String,
    articleText: String,
    targetLanguage: String
  ) async throws -> AIArticleTranslation {
    let credentials = try Self.credentials()
    let prompt = AIService.buildArticleTranslationPrompt(
      title: title,
      articleText: articleText,
      targetLanguage: targetLanguage
    )
    let response = try await Self.sendChatCompletion(
      credentials: credentials,
      messages: [
        ChatMessage(role: "system", content: "You translate technical articles faithfully for Hacker News readers."),
        ChatMessage(role: "user", content: prompt),
      ],
      temperature: 0.2
    )
    return try AIService.decodeArticleTranslation(response)
  }

  func translateTitles(
    _ titles: [AITitleTranslationInput],
    targetLanguage: String
  ) async throws -> [Int: String] {
    let credentials = try Self.credentials()
    let response = try await Self.sendChatCompletion(
      credentials: credentials,
      messages: [
        ChatMessage(role: "system", content: "You translate Hacker News story titles faithfully."),
        ChatMessage(
          role: "user",
          content: AIService.buildBatchTitleTranslationPrompt(titles: titles, targetLanguage: targetLanguage)),
      ],
      temperature: 0.1
    )
    return try AIService.decodeTitleTranslationBatch(response)
  }

  // MARK: - Wire format

  nonisolated struct ChatMessage: Codable, Sendable {
    let role: String
    let content: String
  }

  nonisolated private struct ChatRequest: Encodable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    var stream: Bool? = nil
  }

  nonisolated private struct ChatResponse: Decodable, Sendable {
    nonisolated struct Choice: Decodable, Sendable {
      let message: ChatMessage
    }
    let choices: [Choice]
  }

  static func makeRequest(
    credentials: Credentials,
    messages: [ChatMessage],
    temperature: Double,
    stream: Bool = false
  ) throws -> URLRequest {
    let endpoint =
      URL(string: credentials.baseURL)?.appendingPathComponent("chat/completions")
      ?? URL(string: "\(AIDefaults.baseURL)/chat/completions")!
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.addValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      ChatRequest(
        model: credentials.model,
        messages: messages,
        temperature: temperature,
        stream: stream ? true : nil
      ))
    return request
  }

  /// Non-streaming completion with 3 attempts; 4xx errors other than 429 fail immediately.
  static func sendChatCompletion(
    credentials: Credentials,
    messages: [ChatMessage],
    temperature: Double
  ) async throws -> String {
    let request = try makeRequest(credentials: credentials, messages: messages, temperature: temperature)

    var lastError: Error?
    for attempt in 1...3 {
      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
          throw AIServiceError.requestFailed(status: 0, message: "Invalid Response")
        }
        if httpResponse.statusCode == 200 {
          let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
          return chatResponse.choices.first?.message.content ?? "No response content."
        }
        let errorMessage = String(data: data, encoding: .utf8) ?? "Request failed"
        let error = AIServiceError.requestFailed(
          status: httpResponse.statusCode, message: "API Request Failed: \(errorMessage)")
        if (500...599).contains(httpResponse.statusCode) || httpResponse.statusCode == 429 {
          throw error
        }
        // Authentication and other client errors are not retried.
        lastError = error
        break
      } catch {
        if Task.isCancelled || (error as NSError).code == NSURLErrorCancelled {
          throw error
        }
        print("⚠️ Attempt \(attempt) failed: \(error.localizedDescription)")
        lastError = error
        if attempt < 3 {
          try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
        }
      }
    }
    throw lastError ?? AIServiceError.requestFailed(status: 500, message: "Failed after 3 retries.")
  }
}
