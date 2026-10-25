//
//  WebView.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
  let url: URL

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    // Enable generic mobile friendly settings
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.allowsBackForwardNavigationGestures = true
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {
    if uiView.url != url {
      if url.isFileURL {
        uiView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
      } else {
        uiView.load(URLRequest(url: url))
      }
    }
  }
}
