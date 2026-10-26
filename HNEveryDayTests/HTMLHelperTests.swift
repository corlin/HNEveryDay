//
//  HTMLHelperTests.swift
//  HNEveryDayTests
//
//  Created by AI on 08/06/2026.
//

import XCTest
@testable import HNEveryDay

final class HTMLHelperTests: XCTestCase {
  func testStripTagsDecodesCommonEntitiesAndParagraphs() {
    let html = "<p>Hello &amp; welcome</p><p>&quot;Swift&quot; &#x27;HN&#x27;</p>"

    let text = HTMLHelper.stripTags(html)

    XCTAssertEqual(text, "Hello & welcome\n\n\"Swift\" 'HN'")
  }

  func testStripTagsCollapsesExcessiveNewlines() {
    let html = "<p>First</p><br><br><p>Second</p>"

    let text = HTMLHelper.stripTags(html)

    XCTAssertFalse(text.contains("\n\n\n"))
    XCTAssertEqual(text, "First\n\nSecond")
  }

  func testStripTagsHandlesEmptyInput() {
    XCTAssertEqual(HTMLHelper.stripTags(""), "")
  }

  func testAttributedKeepsLinksParagraphsAndEmphasis() {
    let html = "First &amp; <i>best</i><p>See <a href=\"https:&#x2F;&#x2F;example.com&#x2F;a\" rel=\"nofollow\">example</a>"

    let text = HTMLHelper.attributed(html)

    XCTAssertEqual(String(text.characters), "First & best\n\nSee example")
    let linkRuns = text.runs.compactMap { $0.link }
    XCTAssertEqual(linkRuns, [URL(string: "https://example.com/a")!])
    let emphasized = text.runs.filter { $0.inlinePresentationIntent?.contains(.emphasized) == true }
    XCTAssertEqual(emphasized.count, 1)
  }

  func testAttributedPreservesCodeBlockNewlines() {
    let html = "Try:<p><pre><code>  let a = 1\n  let b = 2\n</code></pre>"

    let text = HTMLHelper.attributed(html)

    XCTAssertEqual(String(text.characters), "Try:\n\n  let a = 1\n  let b = 2")
    XCTAssertTrue(text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
  }

  func testEscapeHandlesMarkup() {
    XCTAssertEqual(HTMLHelper.escape("<b>\"A&B\"</b>"), "&lt;b&gt;&quot;A&amp;B&quot;&lt;/b&gt;")
  }
}
