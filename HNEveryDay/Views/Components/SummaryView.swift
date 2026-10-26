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
  @State private var quotaKind: String?
  @State private var quotaResetAt: Date?
  @State private var showPaywall = false
  @State private var reported = false
  @State private var loadingStartedAt = Date()

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
          } else if let quotaKind {
            QuotaLimitCard(kind: quotaKind, resetAt: quotaResetAt) {
              showPaywall = true
            }
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
            ShareLink(item: AIContentLabel.labeled(summaryText))
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
    .sheet(isPresented: $showPaywall) {
      PaywallView(reason: .quota(kind: quotaKind ?? "summary"))
    }
  }

  private var summaryHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "list.bullet.clipboard")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(AppTheme.Palette.brand)

        Text(item.title ?? "Untitled")
          .font(.headline)
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
      .font(.caption2.weight(.medium))
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(radius: AppTheme.Radius.card)
  }

  private var loadingCard: some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.large)
      Text("Analyzing discussion...", comment: "AI loading state")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      TimelineView(.periodic(from: loadingStartedAt, by: 1)) { timeline in
        let seconds = Int(timeline.date.timeIntervalSince(loadingStartedAt))
        if seconds >= 5 {
          Text("Long discussions take a little longer… \(seconds)s")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 190)
    .cardSurface(radius: AppTheme.Radius.card)
  }

  private func errorCard(_ error: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(AppTheme.Palette.brand)

        Text("AI Service Connection Failed")
          .font(.headline)
      }

      Text(error)
        .foregroundStyle(.secondary)
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)

      Text(errorSuggestion)
        .font(.caption2)
        .foregroundStyle(.secondary)

      Button {
        Task { await retry() }
      } label: {
        Label("Try Again", systemImage: "arrow.clockwise")
          .font(.subheadline.weight(.semibold))
      }
      .buttonStyle(.bordered)
      .tint(AppTheme.Palette.brand)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(stroke: AppTheme.Palette.brand.opacity(0.24))
  }

  private var errorSuggestion: LocalizedStringKey {
    AIMode.current == .byok
      ? "Please check your API Key and Network settings."
      : "Please check your network connection and try again."
  }

  private var summaryCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      MarkdownContentView(content: summaryText)
      HStack(spacing: 12) {
        AIContentLabel()
        if AIMode.current == .hosted {
          Button(reported ? "Reported" : "Report") {
            reported = true
            Task { await BackendClient.shared.report(storyId: item.id, kind: "summary", reason: summaryText) }
          }
          .disabled(reported)
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
      .padding(.horizontal, 14)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
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
        storyId: item.id,
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
        AppTheme.Haptics.playSuccessNotification()
      }
    } catch {
      await MainActor.run {
        if case .quotaExceeded(let kind, _, let resetAt) = error as? AIServiceError {
          self.quotaKind = kind.isEmpty ? "summary" : kind
          self.quotaResetAt = resetAt
        }
        self.errorMsg = error.localizedDescription
        self.isLoading = false
      }
    }
  }

  private func retry() async {
    errorMsg = nil
    quotaKind = nil
    isLoading = true
    loadingStartedAt = Date()
    await generateSummary()
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
