//
//  ArticleImagesTests.swift
//  HNEveryDayTests
//

import XCTest
@testable import HNEveryDay

final class ArticleImagesTests: XCTestCase {
  private let html = """
    <div><h2>Intro</h2><p>First paragraph.</p>\
    <figure><img src="https://example.com/a.png?w=1&amp;h=2" alt="A"></figure>\
    <p>Second <img src="https://t.example.com/pixel.gif" width="1" height="1"> paragraph.</p>\
    <img src='data:image/png;base64,AAAA'><img src="https://example.com/logo.svg">\
    <p><img src="/relative.png"><img class="x" src="http://example.com/b.jpg"></p></div>
    """

  func testMarkedTextNumbersUsableImagesInOrder() {
    let (text, urls) = ArticleImages.markedText(html: html)

    XCTAssertEqual(urls.map(\.absoluteString), ["https://example.com/a.png?w=1&h=2", "http://example.com/b.jpg"])
    XCTAssertTrue(text.contains("Intro\n\nFirst paragraph."))
    XCTAssertTrue(text.contains("[IMG:1]"))
    XCTAssertTrue(text.contains("[IMG:2]"))
    XCTAssertFalse(text.contains("[IMG:3]"))
    XCTAssertFalse(text.contains("<"))
  }

  func testUrlsMatchMarkedTextNumbering() {
    XCTAssertEqual(ArticleImages.urls(in: html), ArticleImages.markedText(html: html).urls)
  }

  func testMarkerIndexToleratesModelFormatting() {
    XCTAssertEqual(ArticleImages.markerIndex("[IMG:3]"), 3)
    XCTAssertEqual(ArticleImages.markerIndex("\\[IMG:12\\]"), 12)
    XCTAssertEqual(ArticleImages.markerIndex("**[img: 2]**"), 2)
    XCTAssertNil(ArticleImages.markerIndex("See [IMG:2] above"))
    XCTAssertNil(ArticleImages.markerIndex("Plain text"))
  }

  func testStripInlineMarkers() {
    XCTAssertEqual(ArticleImages.stripInlineMarkers("Before [IMG:2]after"), "Before after")
  }

  func testCapsImageCount() {
    let many = (1...30).map { "<img src=\"https://example.com/\($0).png\">" }.joined()
    XCTAssertEqual(ArticleImages.urls(in: many).count, ArticleImages.maxImages)
  }
}
