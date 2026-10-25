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
    var max_tokens: Int? = nil
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
    stream: Bool = false,
    maxTokens: Int? = nil
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
        stream: stream ? true : nil,
        max_tokens: maxTokens
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

// MARK: - Connection test

/// Why a BYOK connection test failed, in terms the user can act on.
nonisolated enum BYOKConnectionFailure: Equatable, Sendable {
  case missingKey
  case invalidURL
  case unauthorized
  case insufficientBalance
  case modelNotFound
  /// Usually a Base URL missing its path (e.g. "/v1").
  case endpointNotFound
  case rateLimited
  case timeout
  case offline
  case cannotConnect
  case insecureConnection
  case serverError(Int)
  /// The server answered 200 but not in the OpenAI chat-completions format.
  case unexpectedResponse
  case other(Int)

  var message: String {
    switch self {
    case .missingKey: return String(localized: "Enter your API key first.")
    case .invalidURL: return String(localized: "The Base URL is not a valid http(s) address.")
    case .unauthorized: return String(localized: "The API key was rejected. Check that it is correct and still active.")
    case .insufficientBalance: return String(localized: "The provider reports insufficient balance on this account.")
    case .modelNotFound: return String(localized: "The model name was not found at this provider.")
    case .endpointNotFound:
      return String(localized: "The Base URL was reached but has no chat completions endpoint. It often needs to end with /v1.")
    case .rateLimited: return String(localized: "The provider is rate limiting this key. Try again shortly.")
    case .timeout: return String(localized: "The request timed out.")
    case .offline: return String(localized: "This device appears to be offline.")
    case .cannotConnect: return String(localized: "Could not reach the server. Check the Base URL.")
    case .insecureConnection: return String(localized: "Secure connection failed. Use an https address.")
    case .serverError(let status): return String(localized: "The provider returned a server error (\(status)).")
    case .unexpectedResponse:
      return String(localized: "The server responded, but not like an OpenAI-compatible API. Check the Base URL.")
    case .other(let status): return String(localized: "The request failed (\(status)).")
    }
  }
}

nonisolated struct BYOKConnectionSuccess: Equatable, Sendable {
  let latencyMs: Int
}

nonisolated private struct CompletionProbe: Decodable, Sendable {
  nonisolated struct Choice: Decodable, Sendable {}
  let choices: [Choice]
}

nonisolated private struct ProviderErrorEnvelope: Decodable, Sendable {
  nonisolated struct Body: Decodable, Sendable { let message: String? }
  let error: Body?
  let message: String?
}

nonisolated enum BYOKConnectionTester {
  /// Sends a one-token completion with the given settings.
  static func test(apiKey: String, baseURL: String, model: String) async -> Result<BYOKConnectionSuccess, BYOKConnectionTestError> {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return .failure(BYOKConnectionTestError(.missingKey)) }
    let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmedURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      url.host?.isEmpty == false
    else { return .failure(BYOKConnectionTestError(.invalidURL)) }

    var request: URLRequest
    do {
      request = try BYOKAIProvider.makeRequest(
        credentials: .init(apiKey: key, baseURL: trimmedURL, model: model.trimmingCharacters(in: .whitespacesAndNewlines)),
        messages: [.init(role: "user", content: "ping")],
        temperature: 0,
        maxTokens: 1
      )
    } catch {
      return .failure(BYOKConnectionTestError(.invalidURL))
    }
    request.timeoutInterval = 20

    let started = Date()
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      if let failure = classify(status: status, body: data) {
        return .failure(BYOKConnectionTestError(failure, detail: providerMessage(data)))
      }
      return .success(BYOKConnectionSuccess(latencyMs: Int(Date().timeIntervalSince(started) * 1000)))
    } catch let error as URLError {
      return .failure(BYOKConnectionTestError(classify(error)))
    } catch {
      return .failure(BYOKConnectionTestError(.cannotConnect, detail: error.localizedDescription))
    }
  }

  /// nil means the response is a valid chat completion.
  static func classify(status: Int, body: Data) -> BYOKConnectionFailure? {
    let text = (String(data: body, encoding: .utf8) ?? "").lowercased()
    let mentionsModel = text.contains("model")
    switch status {
    case 200:
      return (try? JSONDecoder().decode(CompletionProbe.self, from: body)) == nil ? .unexpectedResponse : nil
    case 401, 403:
      return .unauthorized
    case 402:
      return .insufficientBalance
    case 404:
      return mentionsModel ? .modelNotFound : .endpointNotFound
    case 400, 422:
      if text.contains("balance") || text.contains("quota") { return .insufficientBalance }
      if mentionsModel && (text.contains("not exist") || text.contains("not found") || text.contains("invalid")
        || text.contains("does not") || text.contains("unknown"))
      {
        return .modelNotFound
      }
      if text.contains("api key") || text.contains("api_key") || text.contains("authentication") { return .unauthorized }
      return .other(status)
    case 405:
      return .endpointNotFound
    case 429:
      return text.contains("balance") || text.contains("insufficient_quota") ? .insufficientBalance : .rateLimited
    case 500...599:
      return .serverError(status)
    default:
      return .other(status)
    }
  }

  static func classify(_ error: URLError) -> BYOKConnectionFailure {
    switch error.code {
    case .timedOut: return .timeout
    case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offline
    case .appTransportSecurityRequiresSecureConnection, .secureConnectionFailed, .serverCertificateUntrusted,
      .serverCertificateHasBadDate, .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
      return .insecureConnection
    case .unsupportedURL, .badURL: return .invalidURL
    default: return .cannotConnect
    }
  }

  /// The provider's own error text ({"error": {"message": ...}}), shown as a secondary detail.
  static func providerMessage(_ data: Data) -> String? {
    guard let envelope = try? JSONDecoder().decode(ProviderErrorEnvelope.self, from: data) else { return nil }
    let message = envelope.error?.message ?? envelope.message
    return message.map { String($0.prefix(200)) }
  }
}

nonisolated struct BYOKConnectionTestError: Error, Equatable, Sendable {
  let failure: BYOKConnectionFailure
  let detail: String?

  init(_ failure: BYOKConnectionFailure, detail: String? = nil) {
    self.failure = failure
    self.detail = detail
  }
}
