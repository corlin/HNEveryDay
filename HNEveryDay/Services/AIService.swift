//
//  AIService.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import Foundation

actor TaskCoalescer {
  static let shared = TaskCoalescer()
  private var inFlight: [String: Task<Any, Error>] = [:]

  func runOrCoalesce<T: Sendable>(key: String, operation: @Sendable @escaping () async throws -> T) async throws -> T {
    if let existingTask = inFlight[key] {
      return try await existingTask.value as! T
    }

    let task = Task {
      try await operation()
    }

    inFlight[key] = Task { try await task.value as Any }

    defer {
      inFlight.removeValue(forKey: key)
    }

    return try await task.value
  }
}

struct AIChatMessage: Codable, Sendable {
  let role: String
  let content: String

  nonisolated init(role: String, content: String) {
    self.role = role
    self.content = content
  }
}

struct AIChatRequest: Codable, Sendable {
  let model: String
  let messages: [AIChatMessage]
  let temperature: Double

  nonisolated init(model: String, messages: [AIChatMessage], temperature: Double) {
    self.model = model
    self.messages = messages
    self.temperature = temperature
  }
}

struct AIChatResponse: Codable, Sendable {
  struct Choice: Codable, Sendable {
    let message: AIChatMessage

    nonisolated init(message: AIChatMessage) {
      self.message = message
    }
  }
  let choices: [Choice]

  nonisolated init(choices: [Choice]) {
    self.choices = choices
  }
}

struct AIArticleTranslation: Codable, Equatable, Sendable {
  let title: String
  let markdown: String

  enum CodingKeys: String, CodingKey {
    case title = "translated_title"
    case markdown = "translated_markdown"
  }

  nonisolated init(title: String, markdown: String) {
    self.title = title
    self.markdown = markdown
  }

  nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.title = try container.decode(String.self, forKey: .title)
    self.markdown = try container.decode(String.self, forKey: .markdown)
  }
}

struct AITitleTranslationInput: Codable, Equatable, Sendable {
  let id: Int
  let title: String
}

struct AITitleTranslationBatchResponse: Codable, Equatable, Sendable {
  struct Translation: Codable, Equatable, Sendable {
    let id: Int
    let title: String

    enum CodingKeys: String, CodingKey {
      case id
      case title = "translated_title"
    }

    nonisolated init(id: Int, title: String) {
      self.id = id
      self.title = title
    }

    nonisolated init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.id = try container.decode(Int.self, forKey: .id)
      self.title = try container.decode(String.self, forKey: .title)
    }
  }

  let translations: [Translation]

  enum CodingKeys: String, CodingKey {
    case translations
  }

  nonisolated init(translations: [Translation]) {
    self.translations = translations
  }

  nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.translations = try container.decode([Translation].self, forKey: .translations)
  }
}

final class AIService: Sendable {
  static let shared = AIService()

  // Request Models
  typealias ChatMessage = AIChatMessage
  typealias ChatRequest = AIChatRequest
  typealias ChatResponse = AIChatResponse
  typealias ArticleTranslation = AIArticleTranslation
  typealias TitleTranslationInput = AITitleTranslationInput
  typealias TitleTranslationBatchResponse = AITitleTranslationBatchResponse

  private let hosted = HostedAIProvider()
  private let byok = BYOKAIProvider()

  /// Routes to the hosted backend or the user's own provider. When the hosted service is switched
  /// off or unreachable and the user has saved their own key, that key is used as an escape hatch.
  private func run<T: Sendable>(_ operation: @Sendable (any AIProvider) async throws -> T) async throws -> T {
    guard AIMode.current == .hosted else {
      return try await operation(byok)
    }
    do {
      return try await operation(hosted)
    } catch let error as AIServiceError where error.allowsBYOKFallback && BYOKAIProvider.hasAPIKey {
      print("⚠️ Hosted AI unavailable (\(error)); falling back to the user's own key.")
      return try await operation(byok)
    }
  }

  func summarize(
    storyId: Int? = nil,
    title: String,
    url: String?,
    articleContent: String?,
    comments: [String]
  ) async throws -> String {
    let preferredLang = UserDefaults.standard.string(forKey: "preferred_language") ?? "system"
    let key = "summary-\(storyId.map(String.init) ?? title)-\(preferredLang)"
    return try await TaskCoalescer.shared.runOrCoalesce(key: key) {
      try await self.run { provider in
        try await provider.summarize(
          storyId: storyId,
          title: title,
          url: url,
          articleContent: articleContent,
          comments: comments,
          preferredLanguage: preferredLang
        )
      }
    }
  }

  func translateArticle(
    storyId: Int? = nil,
    title: String,
    articleText: String,
    targetLanguage: String
  ) async throws -> ArticleTranslation {
    let key = "article-\(targetLanguage)-\(title)"
    return try await TaskCoalescer.shared.runOrCoalesce(key: key) {
      try await self.run { provider in
        try await provider.translateArticle(
          storyId: storyId,
          title: title,
          articleText: articleText,
          targetLanguage: targetLanguage
        )
      }
    }
  }

  func translateTitle(
    _ title: String,
    targetLanguage: String
  ) async throws -> String {
    let translations = try await translateTitles(
      [TitleTranslationInput(id: 0, title: title)],
      targetLanguage: targetLanguage
    )
    return translations[0] ?? ""
  }

  func translateTitles(
    _ titles: [TitleTranslationInput],
    targetLanguage: String
  ) async throws -> [Int: String] {
    let sortedIds = titles.map(\.id).sorted().map(String.init).joined(separator: "-")
    let key = "batch-\(targetLanguage)-\(sortedIds)"
    return try await TaskCoalescer.shared.runOrCoalesce(key: key) {
      try await self.run { provider in
        try await provider.translateTitles(titles, targetLanguage: targetLanguage)
      }
    }
  }

  nonisolated static func buildArticleTranslationPrompt(
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
      - Lines like [IMG:3] mark where images go: keep each one unchanged, on its own line, in the same place.
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

  nonisolated static func buildTitleTranslationPrompt(title: String, targetLanguage: String) -> String {
    buildBatchTitleTranslationPrompt(
      titles: [TitleTranslationInput(id: 0, title: title)],
      targetLanguage: targetLanguage
    )
  }

  nonisolated static func buildBatchTitleTranslationPrompt(
    titles: [TitleTranslationInput],
    targetLanguage: String
  ) -> String {
    let languageName = ReadingLanguage.displayName(for: targetLanguage)
    let encodedTitles =
      (try? String(data: JSONEncoder().encode(titles), encoding: .utf8)) ?? "[]"

    return """
      Translate these Hacker News story titles to \(languageName).

      Rules:
      - Return JSON only, with no code fence and no extra commentary.
      - Preserve product names, project names, code names, API names, and version numbers.
      - Keep each title concise and natural for technical readers.
      - Keep every input id unchanged.
      - Do not add commentary, quotes, bullets, or markdown inside translated titles.

      JSON schema:
      {
        "translations": [
          { "id": 123, "translated_title": "translated title" }
        ]
      }

      Titles:
      \(encodedTitles)
      """
  }

  nonisolated static func cleanTranslatedTitle(_ response: String) -> String {
    response
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  nonisolated static func decodeTitleTranslationBatch(_ response: String) throws -> [Int: String] {
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
    let decoded = try JSONDecoder().decode(TitleTranslationBatchResponse.self, from: data)
    return Dictionary(
      uniqueKeysWithValues: decoded.translations.map {
        ($0.id, cleanTranslatedTitle($0.title))
      }
    )
  }

  nonisolated static func decodeArticleTranslation(_ response: String) throws -> ArticleTranslation {
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

  nonisolated static func buildSummaryPrompt(
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
