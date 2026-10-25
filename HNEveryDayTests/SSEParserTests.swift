//
//  SSEParserTests.swift
//  HNEveryDayTests
//
//  Created by AI on 25/10/2026.
//

import XCTest
@testable import HNEveryDay

final class SSEParserTests: XCTestCase {
  func testParsesBackendEventsWithoutBlankLines() throws {
    var parser = SSEParser()
    let lines = [
      "event: meta", #"data: {"tier":"free","remaining":2,"limit":3}"#,
      "event: delta", #"data: {"text":"Hello"}"#,
      "event: delta", #"data: {"text":" world"}"#,
      "event: done", #"data: {"finish_reason":"stop"}"#,
    ]
    let events = try lines.compactMap { parser.consume(line: $0) }.compactMap { try AgentStreamDecoder.hosted($0) }
    XCTAssertEqual(events, [.meta(remaining: 2, limit: 3), .delta("Hello"), .delta(" world"), .done])
  }

  func testBackendErrorEventThrows() {
    var parser = SSEParser()
    _ = parser.consume(line: "event: error")
    let event = parser.consume(line: #"data: {"code":"upstream_error","message":"boom"}"#)!
    XCTAssertThrowsError(try AgentStreamDecoder.hosted(event))
  }

  func testParsesOpenAIChunks() {
    var parser = SSEParser()
    let lines = [
      #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
      #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#,
      ": keep-alive",
      #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
      "data: [DONE]",
    ]
    let events = lines.compactMap { parser.consume(line: $0) }.compactMap(AgentStreamDecoder.openAI)
    XCTAssertEqual(events, [.delta("Hi"), .done, .done])
  }
}
