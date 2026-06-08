//
//  TranslatedReaderView.swift
//  HNEveryDay
//
//  Created by AI on 08/06/2026.
//

import SwiftUI

struct TranslatedReaderView: View {
  let title: String
  let byline: String?
  let markdown: String
  let targetLanguage: String

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          Text(title)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

          HStack(spacing: 8) {
            Text(byline ?? String(localized: "Unknown Source"))
            Text("|")
            Text(ReadingLanguage.displayName(for: targetLanguage))
          }
          .font(.caption)
          .fontDesign(.monospaced)
          .foregroundStyle(.secondary)
        }

        Divider()
          .overlay(Color.secondary.opacity(0.25))

        MarkdownContentView(content: markdown)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Color(.systemBackground))
  }
}

#Preview {
  TranslatedReaderView(
    title: "Swift Concurrency Migration Guide",
    byline: "example.com",
    markdown: """
      ## Core idea

      This article explains how to migrate toward Swift concurrency.

      - Preserve API names
      - Preserve `Task` and `async/await`
      """,
    targetLanguage: "en"
  )
}
