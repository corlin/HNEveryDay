//
//  AIProvider.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import Foundation

/// Where AI requests go. Hosted is the zero-config default; BYOK talks to the user's own provider.
nonisolated enum AIMode: String, CaseIterable, Identifiable, Sendable {
  case hosted
  case byok

  var id: String { rawValue }

  static let defaultsKey = "ai_mode"

  /// Users who already saved an API key keep using it; everyone else starts on the hosted service.
  static var current: AIMode {
    if let stored = UserDefaults.standard.string(forKey: defaultsKey), let mode = AIMode(rawValue: stored) {
      return mode
    }
    let hasKey = !(KeychainHelper.read(key: BYOKAIProvider.apiKeyAccount) ?? "").isEmpty
    let mode: AIMode = hasKey ? .byok : .hosted
    UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
    return mode
  }
}

nonisolated enum AIServiceError: LocalizedError, Sendable {
  case missingAPIKey
  /// The daily allowance for `kind` ("summary", "article", "agent") is used up.
  case quotaExceeded(kind: String, limit: Int, resetAt: Date?)
  /// Fair-use slow down; retry after the given number of seconds.
  case slowDown(retryAfter: Int)
  /// The hosted service is switched off, over budget, unavailable in this region, or needs an app update.
  case unavailable(code: String, message: String)
  case requestFailed(status: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return String(localized: "API Key is missing. Please configure it in Settings.")
    case .quotaExceeded:
      return String(localized: "You've reached today's free limit. Upgrade to Pro or try again tomorrow.")
    case .slowDown(let seconds):
      return String(localized: "You're going fast. Please wait \(seconds) seconds and try again.")
    case .unavailable(let code, _):
      switch code {
      case "upgrade_required":
        return String(localized: "Please update the app to keep using AI features.")
      case "region_unavailable":
        return String(localized: "Hosted AI is not available in your region. You can use your own API key in Settings.")
      default:
        return String(localized: "AI is temporarily unavailable. Showing the original text.")
      }
    case .requestFailed(_, let message):
      return message
    }
  }

  var isQuotaExceeded: Bool {
    if case .quotaExceeded = self { return true }
    return false
  }

  /// Errors after which falling back to the user's own key (if any) makes sense.
  var allowsBYOKFallback: Bool {
    switch self {
    case .unavailable: return true
    case .requestFailed(let status, _): return status >= 500 || status == 0
    default: return false
    }
  }
}

nonisolated protocol AIProvider: Sendable {
  func summarize(
    storyId: Int?,
    title: String,
    url: String?,
    articleContent: String?,
    comments: [String],
    preferredLanguage: String
  ) async throws -> String

  func translateArticle(
    storyId: Int?,
    title: String,
    articleText: String,
    targetLanguage: String
  ) async throws -> AIArticleTranslation

  func translateTitles(
    _ titles: [AITitleTranslationInput],
    targetLanguage: String
  ) async throws -> [Int: String]
}
