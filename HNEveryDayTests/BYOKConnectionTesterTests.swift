//
//  BYOKConnectionTesterTests.swift
//  HNEveryDayTests
//
//  Created by AI on 25/10/2026.
//

import XCTest
@testable import HNEveryDay

final class BYOKConnectionTesterTests: XCTestCase {
  private func classify(_ status: Int, _ body: String) -> BYOKConnectionFailure? {
    BYOKConnectionTester.classify(status: status, body: Data(body.utf8))
  }

  func testValidCompletionPasses() {
    XCTAssertNil(classify(200, #"{"choices":[{"message":{"role":"assistant","content":"p"}}]}"#))
    XCTAssertEqual(classify(200, "<html>hello</html>"), .unexpectedResponse)
  }

  func testMapsProviderErrors() {
    XCTAssertEqual(classify(401, #"{"error":{"message":"Authentication Fails"}}"#), .unauthorized)
    XCTAssertEqual(classify(402, #"{"error":{"message":"Insufficient Balance"}}"#), .insufficientBalance)
    XCTAssertEqual(classify(400, #"{"error":{"message":"Model Not Exist"}}"#), .modelNotFound)
    XCTAssertEqual(classify(404, #"{"error":{"message":"The model `gpt-9` does not exist"}}"#), .modelNotFound)
    XCTAssertEqual(classify(404, "Not Found"), .endpointNotFound)
    XCTAssertEqual(classify(429, #"{"error":{"type":"insufficient_quota"}}"#), .insufficientBalance)
    XCTAssertEqual(classify(429, "slow down"), .rateLimited)
    XCTAssertEqual(classify(503, ""), .serverError(503))
  }

  func testMapsNetworkErrors() {
    XCTAssertEqual(BYOKConnectionTester.classify(URLError(.timedOut)), .timeout)
    XCTAssertEqual(BYOKConnectionTester.classify(URLError(.cannotFindHost)), .cannotConnect)
    XCTAssertEqual(BYOKConnectionTester.classify(URLError(.notConnectedToInternet)), .offline)
  }

  func testRejectsBadInputBeforeNetwork() async {
    let missingKey = await BYOKConnectionTester.test(apiKey: " ", baseURL: "https://api.deepseek.com", model: "m")
    XCTAssertEqual(missingKey, .failure(BYOKConnectionTestError(.missingKey)))
    let badURL = await BYOKConnectionTester.test(apiKey: "sk", baseURL: "api.deepseek.com", model: "m")
    XCTAssertEqual(badURL, .failure(BYOKConnectionTestError(.invalidURL)))
  }

  func testExtractsProviderMessage() {
    XCTAssertEqual(
      BYOKConnectionTester.providerMessage(Data(#"{"error":{"message":"Model Not Exist"}}"#.utf8)), "Model Not Exist")
  }
}
