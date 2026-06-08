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
}
