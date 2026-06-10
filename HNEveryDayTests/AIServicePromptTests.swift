//
//  AIServicePromptTests.swift
//  HNEveryDayTests
//
//  Created by AI on 06/08/2026.
//

import XCTest
@testable import HNEveryDay

final class AIServicePromptTests: XCTestCase {
  func testPromptUsesEnglishTemplateForExplicitEnglishPreference() {
    let prompt = AIService.buildSummaryPrompt(
      title: "A useful story",
      url: "https://example.com/story",
      articleContent: "Article body",
      comments: ["<p>Great comment</p>"],
      preferredLanguage: "en",
      localeIdentifier: "zh-Hans_CN"
    )

    XCTAssertTrue(prompt.contains("## 📝 Core Idea"))
    XCTAssertTrue(prompt.contains("## 💬 Discussion Focus"))
    XCTAssertTrue(prompt.contains("## 🎯 Takeaway"))
    XCTAssertTrue(prompt.contains("Answer in English."))
    XCTAssertTrue(prompt.contains("- Great comment..."))
    XCTAssertFalse(prompt.contains("文章核心"))
    XCTAssertFalse(prompt.contains("Answer in Simplified Chinese"))
  }

  func testPromptUsesChineseTemplateForExplicitChinesePreference() {
    let prompt = AIService.buildSummaryPrompt(
      title: "A useful story",
      url: nil,
      articleContent: nil,
      comments: [],
      preferredLanguage: "zh-Hans",
      localeIdentifier: "en_US"
    )

    XCTAssertTrue(prompt.contains("## 📝 文章核心"))
    XCTAssertTrue(prompt.contains("## 💬 讨论焦点"))
    XCTAssertTrue(prompt.contains("## 🎯 结论"))
    XCTAssertTrue(prompt.contains("Answer in Simplified Chinese"))
    XCTAssertFalse(prompt.contains("## 📝 Core Idea"))
    XCTAssertFalse(prompt.contains("Answer in English."))
  }

  func testSystemLanguagePreferenceFollowsLocaleIdentifier() {
    XCTAssertTrue(
      AIService.shouldUseChineseSummary(
        preferredLanguage: "system",
        localeIdentifier: "zh-Hans_CN"
      )
    )
    XCTAssertFalse(
      AIService.shouldUseChineseSummary(
        preferredLanguage: "system",
        localeIdentifier: "en_US"
      )
    )
  }

  func testSystemLanguagePreferenceMapsTraditionalChineseLocale() {
    XCTAssertEqual(
      ReadingLanguage.resolvedCode(
        preferredLanguage: "system",
        localeIdentifier: "zh-Hant_TW"
      ),
      "zh-Hant"
    )
  }

  func testPromptSupportsJapanesePreference() {
    let prompt = AIService.buildSummaryPrompt(
      title: "A useful story",
      url: nil,
      articleContent: nil,
      comments: [],
      preferredLanguage: "ja",
      localeIdentifier: "en_US"
    )

    XCTAssertTrue(prompt.contains("## 📝 記事の要点"))
    XCTAssertTrue(prompt.contains("## 💬 議論の焦点"))
    XCTAssertTrue(prompt.contains("Answer in Japanese"))
    XCTAssertFalse(prompt.contains("Answer in English."))
  }

  func testPromptLimitsArticleContentAndTopComments() {
    let longArticle = String(repeating: "A", count: 2_010)
    let comments = (1...25).map { "<p>Comment \($0)</p>" }

    let prompt = AIService.buildSummaryPrompt(
      title: "A useful story",
      url: nil,
      articleContent: longArticle,
      comments: comments,
      preferredLanguage: "en",
      localeIdentifier: "en_US"
    )

    XCTAssertTrue(prompt.contains(String(repeating: "A", count: 2_000) + "..."))
    XCTAssertFalse(prompt.contains(String(repeating: "A", count: 2_010)))
    XCTAssertTrue(prompt.contains("- Comment 20..."))
    XCTAssertFalse(prompt.contains("- Comment 21..."))
  }

  func testArticleTranslationPromptRequestsJsonOnly() {
    let prompt = AIService.buildArticleTranslationPrompt(
      title: "A useful story",
      articleText: "This article explains a technical idea.",
      targetLanguage: "zh-Hans"
    )

    XCTAssertTrue(prompt.contains("Target language: Simplified Chinese"))
    XCTAssertTrue(prompt.contains("\"translated_title\""))
    XCTAssertTrue(prompt.contains("\"translated_markdown\""))
    XCTAssertTrue(prompt.contains("Return JSON only"))
  }

  func testArticleTranslationPromptUsesExpandedLanguageName() {
    let prompt = AIService.buildArticleTranslationPrompt(
      title: "A useful story",
      articleText: "This article explains a technical idea.",
      targetLanguage: "pt-BR"
    )

    XCTAssertTrue(prompt.contains("Target language: Brazilian Portuguese"))
  }

  func testDecodeArticleTranslationHandlesJsonFence() throws {
    let response = """
      ```json
      {
        "translated_title": "Translated title",
        "translated_markdown": "Translated body"
      }
      ```
      """

    let translation = try AIService.decodeArticleTranslation(response)

    XCTAssertEqual(translation.title, "Translated title")
    XCTAssertEqual(translation.markdown, "Translated body")
  }

  func testTitleTranslationPromptKeepsResponseMinimal() {
    let prompt = AIService.buildTitleTranslationPrompt(
      title: "Show HN: A tiny SQLite-backed queue for Swift",
      targetLanguage: "ko"
    )

    XCTAssertTrue(prompt.contains("Return only the translated title."))
    XCTAssertTrue(prompt.contains("Preserve product names"))
    XCTAssertTrue(prompt.contains("Korean"))
  }

  func testCleanTranslatedTitleRemovesWrappingQuotes() {
    let title = AIService.cleanTranslatedTitle("  `\"一个翻译后的标题\"`  ")

    XCTAssertEqual(title, "一个翻译后的标题")
  }
}
