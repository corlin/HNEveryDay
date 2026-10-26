//
//  ReaderView.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import SwiftUI
import WebKit

struct ReaderView: UIViewRepresentable {
  let article: ParsedArticle

  // Follows the system appearance and Dynamic Type (-apple-system-body) so it matches the rest of the app.
  private var htmlContent: String {
    let title = HTMLHelper.escape(article.title ?? String(localized: "Untitled"))
    let byline = HTMLHelper.escape(article.byline ?? article.siteName ?? String(localized: "Unknown Source"))
    return """
      <!DOCTYPE html>
      <html>
      <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
      <style>
          :root {
              color-scheme: light dark;
              --text: #1c1c1e;
              --heading: #000000;
              --muted: #6c6c70;
              --surface: #ffffff;
              --border: #e0e0e5;
              --code: #c2410c;
              --accent: #c45000;
          }
          @media (prefers-color-scheme: dark) {
              :root {
                  --text: #e5e5ea;
                  --heading: #ffffff;
                  --muted: #98989f;
                  --surface: #1c1c1e;
                  --border: #38383a;
                  --code: #ff9f43;
                  --accent: #ff9f0a;
              }
          }
          body {
              font: -apple-system-body;
              line-height: 1.6;
              color: var(--text);
              background-color: transparent;
              padding: 20px 16px 96px;
              margin: 0;
              -webkit-text-size-adjust: 100%;
              overflow-wrap: break-word;
          }
          h1 { font-size: 1.6em; line-height: 1.25; font-weight: 800; margin: 0 0 8px; color: var(--heading); }
          h2, h3, h4 { line-height: 1.3; color: var(--heading); }
          .byline { font-size: 0.8em; color: var(--muted); margin-bottom: 24px; font-family: ui-monospace, Menlo, monospace; }

          p { margin: 0 0 1.1em; }

          img { max-width: 100%; height: auto; border-radius: 8px; margin: 12px 0; }
          figure { margin: 0; }
          figcaption { font-size: 0.75em; color: var(--muted); text-align: center; margin-top: 4px; }

          pre {
              background: var(--surface);
              padding: 14px;
              overflow-x: auto;
              border-radius: 8px;
              border: 1px solid var(--border);
              margin: 20px 0;
          }
          code {
              font-family: ui-monospace, Menlo, monospace;
              font-size: 0.82em;
              color: var(--code);
          }
          p code, li code {
              background: var(--surface);
              border: 1px solid var(--border);
              padding: 1px 4px;
              border-radius: 4px;
          }

          blockquote {
              border-left: 3px solid var(--accent);
              margin: 20px 0;
              padding-left: 14px;
              color: var(--muted);
              font-style: italic;
          }

          a { color: var(--accent); text-decoration: none; border-bottom: 1px dotted var(--accent); }
      </style>
      </head>
      <body>
          <h1>\(title)</h1>
          <div class="byline">\(byline)</div>
          <div class="content">
              \(article.contentHTML ?? "<p>No content extracted.</p>")
          </div>
      </body>
      </html>
      """
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.navigationDelegate = context.coordinator
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {
    // Reload only when the article changes; reloading on every SwiftUI update resets the scroll position.
    let html = htmlContent
    guard context.coordinator.loadedHTML != html else { return }
    context.coordinator.loadedHTML = html
    uiView.loadHTMLString(html, baseURL: nil)
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    var loadedHTML: String?

    /// Links in the article open in Safari instead of replacing the reader.
    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
      if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
        url.scheme == "http" || url.scheme == "https"
      {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return .cancel
      }
      return .allow
    }
  }
}
