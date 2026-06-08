//
//  TranslationPreferences.swift
//  HNEveryDay
//
//  Created by AI on 08/06/2026.
//

import Foundation
import NaturalLanguage

enum TranslationMode: String, CaseIterable, Identifiable {
  case off
  case onDemand = "on_demand"
  case auto

  var id: String { rawValue }
}

enum ReadingLanguage {
  static func resolvedCode(
    preferredLanguage: String,
    localeIdentifier: String = Locale.current.identifier
  ) -> String {
    if preferredLanguage == "system" {
      return localeIdentifier.lowercased().starts(with: "zh") ? "zh-Hans" : "en"
    }
    return preferredLanguage
  }

  static func displayName(for code: String) -> String {
    switch code {
    case "zh-Hans":
      return "Simplified Chinese"
    case "en":
      return "English"
    default:
      return code
    }
  }

  static func likelyLanguageCode(for text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 12 else { return nil }

    let recognizer = NLLanguageRecognizer()
    recognizer.processString(String(trimmed.prefix(4_000)))
    guard let language = recognizer.dominantLanguage else { return nil }

    switch language {
    case .simplifiedChinese, .traditionalChinese:
      return "zh-Hans"
    case .english:
      return "en"
    default:
      return language.rawValue
    }
  }

  static func shouldTranslate(sourceText: String, targetLanguage: String) -> Bool {
    guard let sourceLanguage = likelyLanguageCode(for: sourceText) else {
      return targetLanguage != "en"
    }
    return sourceLanguage != targetLanguage
  }
}
