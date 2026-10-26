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
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 10) {
          Text(title)
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

          HStack(spacing: 7) {
            Text(byline ?? String(localized: "Unknown Source"))
              .lineLimit(1)
            Circle()
              .fill(Color.secondary.opacity(0.45))
              .frame(width: 3, height: 3)
            Text(ReadingLanguage.displayName(for: targetLanguage))
            Circle()
              .fill(Color.secondary.opacity(0.45))
              .frame(width: 3, height: 3)
            Text("AI translation", comment: "Explicit label on machine-translated articles")
          }
          .font(.caption2.weight(.medium))
          .fontDesign(.monospaced)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color.primary.opacity(0.055))
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()

        MarkdownContentView(content: markdown)
          .padding(.horizontal, 2)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Color(.systemGroupedBackground))
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
