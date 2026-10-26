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

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {
    // Load once per URL; comparing with uiView.url would yank the reader back after following a link.
    if context.coordinator.loadedURL != url {
      context.coordinator.loadedURL = url
      if url.isFileURL {
        uiView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
      } else {
        uiView.load(URLRequest(url: url))
      }
    }
  }

  final class Coordinator {
    var loadedURL: URL?
  }
}
