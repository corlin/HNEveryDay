//
//  HostedAIProvider.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import Foundation

/// Default mode: AI requests go to the HNEveryDay backend, which caches shared results
/// (titles, summaries) and applies daily quotas.
nonisolated final class HostedAIProvider: AIProvider {
  nonisolated private struct TitlesRequest: Encodable, Sendable {
    let lang: String
    let ids: [Int]
  }

  nonisolated private struct TitlesResponse: Decodable, Sendable {
    let translations: [String: String]
  }

  nonisolated private struct SummaryRequest: Encodable, Sendable {
    let story_id: Int
    let lang: String
    let article_text: String?
  }

  nonisolated private struct SummaryResponse: Decodable, Sendable {
    let summary: String
  }

  nonisolated private struct ArticleRequest: Encodable, Sendable {
    let story_id: Int?
    let title: String
    let lang: String
    let article_text: String
  }

  nonisolated private struct ArticleResponse: Decodable, Sendable {
    let title: String
    let markdown: String
  }

  func summarize(
    storyId: Int?,
    title: String,
    url: String?,
    articleContent: String?,
    comments: [String],
    preferredLanguage: String
  ) async throws -> String {
    guard let storyId else {
      throw AIServiceError.requestFailed(status: 400, message: "Missing story id")
    }
    // The backend reads the title and comments from Hacker News itself; only the article
    // excerpt (which it cannot fetch) is uploaded.
    let response: SummaryResponse = try await BackendClient.shared.post(
      "/api/v1/summary",
      body: SummaryRequest(
        story_id: storyId,
        lang: ReadingLanguage.resolvedCode(preferredLanguage: preferredLanguage),
        article_text: articleContent.map { String($0.prefix(12_000)) }
      )
    )
    return response.summary
  }

  func translateArticle(
    storyId: Int?,
    title: String,
    articleText: String,
    targetLanguage: String
  ) async throws -> AIArticleTranslation {
    let response: ArticleResponse = try await BackendClient.shared.post(
      "/api/v1/translate/article",
      body: ArticleRequest(
        story_id: storyId,
        title: String(title.prefix(500)),
        lang: targetLanguage,
        article_text: String(articleText.prefix(8_000))
      ),
      timeout: AIDefaults.articleTranslationTimeout,
      retryOnNetworkError: false
    )
    return AIArticleTranslation(title: response.title, markdown: response.markdown)
  }

  func translateTitles(
    _ titles: [AITitleTranslationInput],
    targetLanguage: String
  ) async throws -> [Int: String] {
    var result: [Int: String] = [:]
    // The backend accepts at most 50 ids per request.
    for start in stride(from: 0, to: titles.count, by: 50) {
      let chunk = titles[start..<min(start + 50, titles.count)]
      let response: TitlesResponse = try await BackendClient.shared.post(
        "/api/v1/translate/titles",
        body: TitlesRequest(lang: targetLanguage, ids: chunk.map(\.id))
      )
      for (key, value) in response.translations {
        if let id = Int(key) { result[id] = value }
      }
    }
    return result
  }
}
