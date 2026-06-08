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
}
