//
//  WebParser.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import Foundation
import WebKit

struct ParsedArticle: Sendable {
  let title: String?
  let byline: String?
  let contentHTML: String?
  let textContent: String?
  let excerpt: String?
  let siteName: String?
}

@MainActor
class WebParser: NSObject, WKNavigationDelegate {
  static let shared = WebParser()

  private let webView: WKWebView
  private var continuation: CheckedContinuation<ParsedArticle, Error>?
  private var readabilityJS: String?

  override init() {
    let config = WKWebViewConfiguration()
    self.webView = WKWebView(frame: .zero, configuration: config)
    super.init()
    self.webView.navigationDelegate = self

    if let url = Bundle.main.url(forResource: "Readability", withExtension: "js") {
      do {
        self.readabilityJS = try String(contentsOf: url, encoding: .utf8)
      } catch {
        print("Failed to load Readability.js: \(error)")
      }
    }
  }

  private func loadJS() -> String? {
    readabilityJS
  }

  func parse(url: URL) async throws -> ParsedArticle {
    // Cancel any existing task
    if self.continuation != nil {
      self.continuation?.resume(throwing: CancellationError())
      self.continuation = nil
    }

    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let request = URLRequest(url: url, timeoutInterval: 30)  // 30s timeout
      self.webView.load(request)
    }
  }

  // WKNavigationDelegate

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let jsCode = loadJS() else {
      continuation?.resume(
        throwing: NSError(
          domain: "WebParser", code: 404,
          userInfo: [NSLocalizedDescriptionKey: "Readability.js not found"]))
      continuation = nil
      return
    }

    let extractionScript = """
      \(jsCode)
      function extract() {
          var article = new Readability(document.cloneNode(true)).parse();
          return article;
      }
      extract();
      """

    webView.evaluateJavaScript(extractionScript) { result, error in
      if let error = error {
        self.continuation?.resume(throwing: error)
      } else if let dict = result as? [String: Any] {
        let article = ParsedArticle(
          title: dict["title"] as? String,
          byline: dict["byline"] as? String,
          contentHTML: dict["content"] as? String,
          textContent: dict["textContent"] as? String,
          excerpt: dict["excerpt"] as? String,
          siteName: dict["siteName"] as? String
        )
        self.continuation?.resume(returning: article)
      } else {
        self.continuation?.resume(
          throwing: NSError(
            domain: "WebParser", code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Failed to parse article"]))
      }
      self.continuation = nil
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    continuation?.resume(throwing: error)
    continuation = nil
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    continuation?.resume(throwing: error)
    continuation = nil
  }
}
