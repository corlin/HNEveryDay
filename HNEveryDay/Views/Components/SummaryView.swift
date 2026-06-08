//
//  SummaryView.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import SwiftUI

struct SummaryView: View {
  let item: HNItem
  let comments: [CommentNode]
  let article: ParsedArticle?
  let initialSummary: String?
  var onSummaryGenerated: ((String) -> Void)?

  @State private var summaryText: String = ""
  @State private var isLoading = true
  @State private var errorMsg: String?

  init(
    item: HNItem,
    comments: [CommentNode],
    article: ParsedArticle?,
    initialSummary: String? = nil,
    onSummaryGenerated: ((String) -> Void)? = nil
  ) {
    let cachedSummary = initialSummary?.isEmpty == false ? initialSummary : nil
    self.item = item
    self.comments = comments
    self.article = article
    self.initialSummary = cachedSummary
    self.onSummaryGenerated = onSummaryGenerated
    _summaryText = State(initialValue: cachedSummary ?? "")
    _isLoading = State(initialValue: cachedSummary == nil)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if isLoading {
            VStack(spacing: 12) {
              ProgressView()
                .controlSize(.large)
              Text("Analyzing discussion...", comment: "AI loading state")
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
          } else if let error = errorMsg {
            VStack(spacing: 12) {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
              Text("AI Service Connection Failed", comment: "Error title")
                .font(.headline)
              Text(error)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.caption)

              Text("Please check your API Key and Network settings.", comment: "Error suggestion")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(12)
          } else {
            // Success State - Custom Markdown Rendering
            MarkdownContentView(content: summaryText)
          }
        }
        .padding()
      }
      .navigationTitle(Text("Magic Summary", comment: "Page title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if !isLoading {
            ShareLink(item: summaryText)
          }
        }
      }
    }
    .task {
      if initialSummary == nil {
        await generateSummary()
      }
    }
  }

  private func generateSummary() async {
    // Collect comment texts
    // Flatten first level only for now, or traverse a bit?
    // AIService prompt only takes list of strings.
    var commentTexts: [String] = []
    for node in comments {
      if let text = node.item.text {
        commentTexts.append(text)
      }
    }

    do {
      let result = try await AIService.shared.summarize(
        title: item.title ?? "Unknown",
        url: item.url,
        articleContent: article?.textContent,
        comments: commentTexts
      )
      await MainActor.run {
        self.summaryText = result
        self.isLoading = false
        DataService.shared.saveSummary(
          id: item.id,
          title: item.title ?? "Untitled",
          url: item.url,
          summary: result
        )
        self.onSummaryGenerated?(result)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      }
    } catch {
      await MainActor.run {
        self.errorMsg = error.localizedDescription
        self.isLoading = false
      }
    }
  }
}
