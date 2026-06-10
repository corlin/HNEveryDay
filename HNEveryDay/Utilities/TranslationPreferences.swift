//
//  TranslationPreferences.swift
//  HNEveryDay
//
//  Created by AI on 08/06/2026.
//

import Foundation
import NaturalLanguage

struct ReadingLanguageOption: Identifiable, Hashable {
  let code: String
  let label: String
  let instructionName: String
  let coreHeading: String
  let discussionHeading: String
  let takeawayHeading: String
  let corePlaceholder: String
  let keyPointLabel: String
  let takeawayPlaceholder: String

  var id: String { code }
}

enum TranslationMode: String, CaseIterable, Identifiable {
  case off
  case onDemand = "on_demand"
  case auto

  var id: String { rawValue }
}

enum ReadingLanguage {
  static let systemCode = "system"

  static let supportedOptions: [ReadingLanguageOption] = [
    ReadingLanguageOption(
      code: "en",
      label: "English",
      instructionName: "English",
      coreHeading: "Core Idea",
      discussionHeading: "Discussion Focus",
      takeawayHeading: "Takeaway",
      corePlaceholder: "2-3 sentences summarizing the article's core value proposition",
      keyPointLabel: "Key Point",
      takeawayPlaceholder: "1-2 sentences with your synthesis"
    ),
    ReadingLanguageOption(
      code: "zh-Hans",
      label: "简体中文",
      instructionName: "Simplified Chinese (简体中文)",
      coreHeading: "文章核心",
      discussionHeading: "讨论焦点",
      takeawayHeading: "结论",
      corePlaceholder: "用 2-3 句话总结文章核心价值",
      keyPointLabel: "要点",
      takeawayPlaceholder: "用 1-2 句话给出综合判断"
    ),
    ReadingLanguageOption(
      code: "zh-Hant",
      label: "繁體中文",
      instructionName: "Traditional Chinese (繁體中文)",
      coreHeading: "文章核心",
      discussionHeading: "討論焦點",
      takeawayHeading: "結論",
      corePlaceholder: "用 2-3 句話總結文章核心價值",
      keyPointLabel: "要點",
      takeawayPlaceholder: "用 1-2 句話給出綜合判斷"
    ),
    ReadingLanguageOption(
      code: "ja",
      label: "日本語",
      instructionName: "Japanese (日本語)",
      coreHeading: "記事の要点",
      discussionHeading: "議論の焦点",
      takeawayHeading: "まとめ",
      corePlaceholder: "記事の中核的な価値を 2-3 文で要約",
      keyPointLabel: "ポイント",
      takeawayPlaceholder: "総合的な判断を 1-2 文で記述"
    ),
    ReadingLanguageOption(
      code: "ko",
      label: "한국어",
      instructionName: "Korean (한국어)",
      coreHeading: "핵심 내용",
      discussionHeading: "토론 초점",
      takeawayHeading: "결론",
      corePlaceholder: "글의 핵심 가치를 2-3문장으로 요약",
      keyPointLabel: "요점",
      takeawayPlaceholder: "종합 판단을 1-2문장으로 제시"
    ),
    ReadingLanguageOption(
      code: "es",
      label: "Español",
      instructionName: "Spanish (Español)",
      coreHeading: "Idea central",
      discussionHeading: "Foco de la discusión",
      takeawayHeading: "Conclusión",
      corePlaceholder: "resume en 2-3 frases el valor central del artículo",
      keyPointLabel: "Punto clave",
      takeawayPlaceholder: "síntesis en 1-2 frases"
    ),
    ReadingLanguageOption(
      code: "fr",
      label: "Français",
      instructionName: "French (Français)",
      coreHeading: "Idée principale",
      discussionHeading: "Points de discussion",
      takeawayHeading: "Conclusion",
      corePlaceholder: "résume en 2-3 phrases la valeur centrale de l'article",
      keyPointLabel: "Point clé",
      takeawayPlaceholder: "synthèse en 1-2 phrases"
    ),
    ReadingLanguageOption(
      code: "de",
      label: "Deutsch",
      instructionName: "German (Deutsch)",
      coreHeading: "Kernidee",
      discussionHeading: "Diskussionsfokus",
      takeawayHeading: "Fazit",
      corePlaceholder: "fasse den Kernwert des Artikels in 2-3 Sätzen zusammen",
      keyPointLabel: "Kernpunkt",
      takeawayPlaceholder: "Synthese in 1-2 Sätzen"
    ),
    ReadingLanguageOption(
      code: "pt-BR",
      label: "Português",
      instructionName: "Brazilian Portuguese (Português do Brasil)",
      coreHeading: "Ideia central",
      discussionHeading: "Foco da discussão",
      takeawayHeading: "Conclusão",
      corePlaceholder: "resuma em 2-3 frases o valor central do artigo",
      keyPointLabel: "Ponto-chave",
      takeawayPlaceholder: "síntese em 1-2 frases"
    ),
    ReadingLanguageOption(
      code: "ru",
      label: "Русский",
      instructionName: "Russian (Русский)",
      coreHeading: "Главная идея",
      discussionHeading: "Фокус обсуждения",
      takeawayHeading: "Вывод",
      corePlaceholder: "кратко изложите основную ценность статьи в 2-3 предложениях",
      keyPointLabel: "Ключевой пункт",
      takeawayPlaceholder: "синтез в 1-2 предложениях"
    ),
  ]

  static func resolvedCode(
    preferredLanguage: String,
    localeIdentifier: String = Locale.current.identifier
  ) -> String {
    if preferredLanguage == systemCode {
      return resolvedSystemCode(localeIdentifier: localeIdentifier)
    }
    return option(for: preferredLanguage).code
  }

  static func displayName(for code: String) -> String {
    option(for: code).instructionName
  }

  static func shortLabel(for code: String) -> String {
    option(for: code).label
  }

  static func option(for code: String) -> ReadingLanguageOption {
    supportedOptions.first { $0.code == code } ?? supportedOptions[0]
  }

  static func summaryFormat(for code: String) -> String {
    let option = option(for: code)
    return """
      ## 📝 \(option.coreHeading)
      [\(option.corePlaceholder)]

      ## 💬 \(option.discussionHeading)
      - **[\(option.keyPointLabel) 1]**: [brief explanation]
      - **[\(option.keyPointLabel) 2]**: [brief explanation]
      - **[\(option.keyPointLabel) 3]**: [brief explanation]

      ## 🎯 \(option.takeawayHeading)
      [\(option.takeawayPlaceholder)]
      """
  }

  static func likelyLanguageCode(for text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 12 else { return nil }

    let recognizer = NLLanguageRecognizer()
    recognizer.processString(String(trimmed.prefix(4_000)))
    guard let language = recognizer.dominantLanguage else { return nil }

    switch language {
    case .simplifiedChinese, .traditionalChinese:
      return language == .traditionalChinese ? "zh-Hant" : "zh-Hans"
    case .english:
      return "en"
    default:
      return normalizeLanguageCode(language.rawValue)
    }
  }

  static func shouldTranslate(sourceText: String, targetLanguage: String) -> Bool {
    guard let sourceLanguage = likelyLanguageCode(for: sourceText) else {
      return targetLanguage != "en"
    }
    return languageFamily(sourceLanguage) != languageFamily(targetLanguage)
  }

  private static func resolvedSystemCode(localeIdentifier: String) -> String {
    let lowered = localeIdentifier.lowercased()
    if lowered.starts(with: "zh") {
      return lowered.contains("hant") || lowered.contains("_tw") || lowered.contains("_hk")
        || lowered.contains("_mo") ? "zh-Hant" : "zh-Hans"
    }

    let languageCode = lowered.split(separator: "_").first?.split(separator: "-").first.map(String.init)
    return normalizeLanguageCode(languageCode ?? "en")
  }

  private static func normalizeLanguageCode(_ code: String) -> String {
    let lowered = code.lowercased()
    if lowered.starts(with: "zh") { return "zh-Hans" }
    if lowered.starts(with: "pt") { return "pt-BR" }
    let base = lowered.split(separator: "-").first.map(String.init) ?? lowered
    return supportedOptions.contains { $0.code == base } ? base : "en"
  }

  private static func languageFamily(_ code: String) -> String {
    if code.starts(with: "zh") { return "zh" }
    if code.starts(with: "pt") { return "pt" }
    return code
  }
}
