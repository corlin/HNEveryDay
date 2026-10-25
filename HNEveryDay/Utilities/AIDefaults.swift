//
//  AIDefaults.swift
//  HNEveryDay
//
//  Created by AI on 10/06/2026.
//

enum AIDefaults: Sendable {
  nonisolated static let baseURL = "https://api.deepseek.com"
  nonisolated static let model = "deepseek-flash"
  /// A full article is several thousand output tokens; that can take well over a minute.
  nonisolated static let articleTranslationTimeout: TimeInterval = 180
}
