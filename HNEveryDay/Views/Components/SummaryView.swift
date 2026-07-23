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
  let requiresComments: Bool
  let initialSummary: String?
  var onSummaryGenerated: ((String) -> Void)?

  @State private var summaryText: String = ""
  @State private var isLoading = true
  @State private var errorMsg: String?

  init(
    item: HNItem,
    comments: [CommentNode],
    article: ParsedArticle?,
    requiresComments: Bool = false,
    initialSummary: String? = nil,
    onSummaryGenerated: ((String) -> Void)? = nil
  ) {
    let cachedSummary = initialSummary?.isEmpty == false ? initialSummary : nil
    self.item = item
    self.comments = comments
    self.article = article
    self.requiresComments = requiresComments
    self.initialSummary = cachedSummary
    self.onSummaryGenerated = onSummaryGenerated
    _summaryText = State(initialValue: cachedSummary ?? "")
    _isLoading = State(initialValue: cachedSummary == nil)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          summaryHeader

          if isLoading {
            loadingCard
          } else if let error = errorMsg {
            errorCard(error)
          } else {
            summaryCard
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
      }
      .background(Color(.systemGroupedBackground))
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
    .background(Color(.systemGroupedBackground))
    .task {
      if initialSummary == nil {
        await generateSummary()
      }
    }
  }

  private var summaryHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "sparkles")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.orange)

        Text(item.title ?? "Untitled")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.primary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: 8) {
        if let host = item.url?.hostDomain {
          Text(host)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }

        Text("\(summaryComments.count) comments")
          .fontDesign(.monospaced)

        if article != nil {
          Text("article")
            .fontDesign(.monospaced)
        }
      }
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
    )
  }

  private var loadingCard: some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.large)
      Text("Analyzing discussion...", comment: "AI loading state")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 190)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
    )
  }

  private func errorCard(_ error: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.orange)

        Text("AI Service Connection Failed", comment: "Error title")
          .font(.headline)
      }

      Text(error)
        .foregroundStyle(.secondary)
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)

      Text("Please check your API Key and Network settings.", comment: "Error suggestion")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(Color.orange.opacity(0.24), lineWidth: 1)
    )
  }

  private var summaryCard: some View {
    MarkdownContentView(content: summaryText)
      .padding(.horizontal, 14)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
      )
  }

  private func generateSummary() async {
    let commentTexts = summaryComments.compactMap { node -> String? in
      guard let text = node.item.text else { return nil }
      let cleanText = HTMLHelper.stripTags(text)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return cleanText.isEmpty ? nil : cleanText
    }

    guard !requiresComments || !commentTexts.isEmpty else {
      await MainActor.run {
        self.errorMsg =
          "Comments are not ready yet. Please open the Comments tab once, wait for the thread to load, then try Magic Summary again."
        self.isLoading = false
      }
      return
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

  private var summaryComments: [CommentNode] {
    Self.flattenAll(comments)
  }

  private static func flattenAll(_ nodes: [CommentNode]) -> [CommentNode] {
    nodes.flatMap { node in
      [node] + flattenAll(node.children)
    }
  }
}
