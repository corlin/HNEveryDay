//
//  HNClientTests.swift
//  HNEveryDayTests
//
//  Created by AI on 06/08/2026.
//

import Foundation
import XCTest
@testable import HNEveryDay

final class HNClientTests: XCTestCase {
  func testFetchStoryIdsBuildsEndpointAndDecodesIds() async throws {
    let baseURL = URL(string: "https://example.test/v0")!
    let expectedURL = baseURL.appendingPathComponent("topstories.json")
    let client = HNClient(
      baseURL: baseURL,
      session: StubSession { url in
        guard url == expectedURL else {
          throw StubError.unexpectedURL(url)
        }
        return httpResponse(url: url, statusCode: 200, body: "[1,2,3]")
      }
    )

    let ids = try await client.fetchStoryIds(type: .top)

    XCTAssertEqual(ids, [1, 2, 3])
  }

  func testFetchItemDecodesStoryDatesFromUnixSeconds() async throws {
    let baseURL = URL(string: "https://example.test/v0")!
    let client = HNClient(
      baseURL: baseURL,
      session: StubSession { url in
        return httpResponse(
          url: url,
          statusCode: 200,
          body: """
            {
              "id": 42,
              "type": "story",
              "by": "pg",
              "time": 1700000000,
              "title": "A story",
              "url": "https://example.com",
              "score": 12,
              "kids": [100, 101]
            }
            """
        )
      }
    )

    let item = try await client.fetchItem(id: 42)

    XCTAssertEqual(item.id, 42)
    XCTAssertEqual(item.title, "A story")
    XCTAssertEqual(item.time, Date(timeIntervalSince1970: 1_700_000_000))
    XCTAssertEqual(item.kids, [100, 101])
  }

  func testFetchThrowsHTTPStatusForNonSuccessResponse() async throws {
    let client = HNClient(
      baseURL: URL(string: "https://example.test/v0")!,
      session: StubSession { url in
        return httpResponse(url: url, statusCode: 503, body: "Service unavailable")
      }
    )

    do {
      _ = try await client.fetchItem(id: 1)
      XCTFail("Expected HTTP status error.")
    } catch HNClientError.httpStatus(let statusCode) {
      XCTAssertEqual(statusCode, 503)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testFetchThrowsEmptyResponseForNullPayload() async throws {
    let client = HNClient(
      baseURL: URL(string: "https://example.test/v0")!,
      session: StubSession { url in
        return httpResponse(url: url, statusCode: 200, body: "null\n")
      }
    )

    do {
      _ = try await client.fetchItem(id: 1)
      XCTFail("Expected empty response error.")
    } catch HNClientError.emptyResponse {
      XCTAssertTrue(true)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testFetchWrapsUnderlyingNetworkError() async throws {
    let underlying = NSError(domain: "HNClientTests", code: 42)
    let client = HNClient(
      baseURL: URL(string: "https://example.test/v0")!,
      session: StubSession { _ in
        throw underlying
      }
    )

    do {
      _ = try await client.fetchItem(id: 1)
      XCTFail("Expected network error.")
    } catch HNClientError.networkError(let error) {
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, underlying.domain)
      XCTAssertEqual(nsError.code, underlying.code)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}

private struct StubSession: HNClientSession {
  let handler: @Sendable (URL) async throws -> (Data, URLResponse)

  func data(from url: URL) async throws -> (Data, URLResponse) {
    try await handler(url)
  }
}

private enum StubError: Error {
  case unexpectedURL(URL)
}

private func httpResponse(
  url: URL,
  statusCode: Int,
  body: String
) -> (Data, URLResponse) {
  let response = HTTPURLResponse(
    url: url,
    statusCode: statusCode,
    httpVersion: nil,
    headerFields: nil
  )!
  return (Data(body.utf8), response)
}
