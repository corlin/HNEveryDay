//
//  ItemDetailView.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import SwiftUI

struct ItemDetailView: View {
  let item: HNItem

  @State private var hydratedItem: HNItem?
  @AppStorage("preferred_language") private var preferredLanguage: String = "system"
  @AppStorage("translation_mode") private var translationModeRaw: String = TranslationMode.off.rawValue
  @State private var selectedMode = 0  // 0 = Article, 1 = Comments
  @State private var comments: [CommentNode] = []
  @State private var flattenedComments: [CommentNode] = []
  @State private var isLoadingComments = false
  @State private var showSummary = false
  @State private var isPreparingSummary = false
  @State private var collapsedCommentIds: Set<Int> = []

  // Reader Mode State
  @State private var parsedArticle: ParsedArticle?
  @State private var isParsingArticle = false
  @State private var showReaderMode = true  // Default to true
  @State private var translatedArticleTitle: String?
  @State private var translatedArticleMarkdown: String?
  @State private var isTranslatingArticle = false
  @State private var translationError: String?
  @State private var showTranslatedArticle = false

  // Export State
  struct ExportData: Identifiable {
    let id = UUID()
    let text: String
  }
  @State private var exportData: ExportData?
  @State private var summaryTextForExport: String?

  private var currentItem: HNItem {
    hydratedItem ?? item
  }

  private var translationMode: TranslationMode {
    TranslationMode(rawValue: translationModeRaw) ?? .off
  }

  private var targetLanguage: String {
    ReadingLanguage.resolvedCode(preferredLanguage: preferredLanguage)
  }

  var body: some View {
    VStack(spacing: 0) {
      // MARK: - Picker
      modePickerBar

      // MARK: - Content
      TabView(selection: $selectedMode) {
        // MODIFIED: Article View with Smart Reader
        Group {
          if let url = currentItem.urlObj {
            if showReaderMode, let article = parsedArticle {
              VStack(spacing: 0) {
                articleStatusBanner

                if showTranslatedArticle, let translatedArticleMarkdown {
                  TranslatedReaderView(
                    title: translatedArticleTitle ?? article.title ?? currentItem.title ?? "Untitled",
                    byline: article.byline ?? article.siteName,
                    markdown: translatedArticleMarkdown,
                    targetLanguage: targetLanguage
                  )
                  .transition(.opacity)
                } else {
                  ReaderView(article: article)
                    .transition(.opacity)
                }
              }
            } else if showReaderMode && isParsingArticle {
              VStack {
                ProgressView {
                  Text("Optimizing for Reader...", comment: "Reader loading state")
                }
                .padding()
                Text(
                  "Parsing content locally to remove ads and clutter.",
                  comment: "Reader explanation"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(Color(.systemGroupedBackground))
            } else {
              // Fallback to Webview
              WebView(url: url)
                .transition(.opacity)
            }
          } else if currentItem.text != nil {
            ScrollView {
              Text(HTMLHelper.parse(currentItem.text ?? ""))
                .padding()
            }
            .background(Color(.systemGroupedBackground))
          } else {
            ContentUnavailableView("No URL", systemImage: "link.badge.plus")
              .background(Color(.systemGroupedBackground))
          }
        }
        .tag(0)

        // Comments View (Unchanged)
        Group {
          if isLoadingComments {
            ProgressView("Loading Thread...")
          } else if flattenedComments.isEmpty {
            ContentUnavailableView("No Comments", systemImage: "bubble.left.and.bubble.right")
          } else {
            List {
              // Header Info
              VStack(alignment: .leading, spacing: 8) {
                Text(currentItem.title ?? "")
                  .font(.headline)
                  .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                  Text("\(currentItem.score ?? 0) points")
                  Text("by \(currentItem.by ?? "")")  // 'by' is hard to localize elegantly in concatenation, will leave as is or use a format string
                  Text(currentItem.time.shortTimeAgo)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 12)
              .background(Color(.secondarySystemGroupedBackground))
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
              )
              .listRowSeparator(.hidden)
              .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 6, trailing: 12))
              .listRowBackground(Color.clear)

              ForEach(flattenedComments) { node in
                CommentRowView(node: node, isCollapsed: collapsedCommentIds.contains(node.id))
                  .listRowSeparator(.hidden)
                  .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                  .listRowBackground(Color.clear)
                  .onTapGesture {
                    toggleCollapse(node.id)
                  }
              }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
          }
        }
        .tag(1)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))  // Swipe left/right
      .background(Color(.systemGroupedBackground))
    }
    .background(Color(.systemGroupedBackground))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      // Reader Toggle
      if selectedMode == 0 && currentItem.urlObj != nil {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            withAnimation {
              showReaderMode.toggle()
              if !showReaderMode {
                showTranslatedArticle = false
              }
            }
          } label: {
            Image(systemName: showReaderMode ? "doc.plaintext.fill" : "globe")
              .foregroundStyle(showReaderMode ? .orange : .primary)
          }
          .accessibilityLabel(showReaderMode ? "Show Web Article" : "Show Reader")
        }
      }

      if selectedMode == 0 && showReaderMode && parsedArticle != nil && translationMode != .off {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await toggleArticleTranslation() }
          } label: {
            Image(systemName: showTranslatedArticle ? "doc.plaintext" : "translate")
              .foregroundStyle(showTranslatedArticle ? .orange : .primary)
          }
          .disabled(isTranslatingArticle)
          .accessibilityLabel(showTranslatedArticle ? "Show Original Article" : "Translate Article")
        }
      }

      // Export Button
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          generateExport()
        } label: {
          Image(systemName: "square.and.arrow.up")
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await presentSummary() }
        } label: {
          if isPreparingSummary {
            ProgressView()
              .controlSize(.mini)
          } else {
            Image(systemName: "sparkles")
          }
        }
        .disabled(isPreparingSummary)
        .accessibilityLabel("Summarize Discussion")
      }
    }
    // Share Sheet
    .sheet(item: $exportData) { data in
      ShareSheet(activityItems: [data.text])
        .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $showSummary) {
      SummaryView(
        item: currentItem, comments: comments, article: parsedArticle,
        requiresComments: storyHasComments,
        initialSummary: storyHasComments ? nil : summaryTextForExport,
        onSummaryGenerated: { summary in
          self.summaryTextForExport = summary
        }
      )
      .presentationDetents([.medium, .large])
    }
    .task {
      await hydrateItemIfNeeded()
      // Parallel load: Comments AND Reader Parsing
      await withTaskGroup(of: Void.self) { group in
        group.addTask { await loadComments() }
        group.addTask { await loadArticleContent() }
      }
    }
    // Force comments mode if no URL
    .onAppear {
      DataService.shared.markAsRead(item: currentItem)
      summaryTextForExport = DataService.shared.fetchCachedStory(id: currentItem.id)?.summary
      if currentItem.url == nil {
        selectedMode = 1
      }
    }
  }

  private var modePickerBar: some View {
    VStack(spacing: 0) {
      Picker("Mode", selection: $selectedMode) {
        Text("Article", comment: "Read mode").tag(0)
        Text("Comments", comment: "Discussion mode").tag(1)
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 16)
      .padding(.top, 10)
      .padding(.bottom, 8)
    }
    .background(Color(.systemGroupedBackground))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.primary.opacity(0.06))
        .frame(height: 1)
    }
    .zIndex(1)
  }

  @ViewBuilder
  private var articleStatusBanner: some View {
    if isTranslatingArticle {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.mini)
        Text("Translating article...")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .padding(.bottom, 4)
    } else if let translationError {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .padding(.top, 1)

        Text(translationError)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(Color.orange.opacity(0.22), lineWidth: 1)
      )
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .padding(.bottom, 4)
    }
  }

  private var storyHasComments: Bool {
    currentItem.kids?.isEmpty == false
  }

  private func presentSummary() async {
    await MainActor.run {
      isPreparingSummary = true
    }

    await hydrateItemIfNeeded()

    if storyHasComments && comments.isEmpty {
      if isLoadingComments {
        await waitForCommentsToFinishLoading()
      } else {
        await loadComments()
      }
    }

    await MainActor.run {
      isPreparingSummary = false
      showSummary = true
    }
  }

  private func waitForCommentsToFinishLoading() async {
    while isLoadingComments {
      try? await Task.sleep(nanoseconds: 150_000_000)
    }
  }

  private func hydrateItemIfNeeded() async {
    guard hydratedItem == nil else { return }
    guard item.kids == nil || item.score == nil || item.by == nil else { return }

    do {
      let freshItem = try await HNClient.shared.fetchItem(id: item.id)
      await MainActor.run {
        self.hydratedItem = freshItem
        DataService.shared.markAsRead(item: freshItem)
        if freshItem.url == nil {
          self.selectedMode = 1
        }
      }
    } catch {
      print("Failed to hydrate story: \(error)")
    }
  }

  private func loadArticleContent() async {
    let item = currentItem
    guard let url = item.urlObj else { return }
    guard parsedArticle == nil else { return }

    if let cachedContent = await MainActor.run(body: {
      DataService.shared.fetchCachedStory(id: item.id)?.contentHTML
    }) {
      let article = ParsedArticle(
        title: item.title,
        byline: item.by,
        contentHTML: cachedContent,
        textContent: HTMLHelper.stripTags(cachedContent),
        excerpt: nil,
        siteName: url.host
      )
      await MainActor.run {
        self.parsedArticle = article
      }
      await prepareArticleTranslationIfNeeded(for: article, item: item)
      return
    }

    isParsingArticle = true
    do {
      // Attempt to parse
      let article = try await WebParser.shared.parse(url: url)
      await MainActor.run {
        self.parsedArticle = article
        // Save to Persistence
        if let html = article.contentHTML {
          DataService.shared.saveContent(
            id: item.id,
            title: item.title ?? article.title ?? "Untitled",
            url: item.url,
            content: html
          )
        }
      }
      await prepareArticleTranslationIfNeeded(for: article, item: item)
    } catch {
      print("Reader Parsing failed: \(error). Falling back to Web.")
      await MainActor.run {
        // If parsing fails, auto-switch to Web
        self.showReaderMode = false
      }
    }
    await MainActor.run {
      self.isParsingArticle = false
    }
  }

  private func prepareArticleTranslationIfNeeded(for article: ParsedArticle, item: HNItem) async {
    guard translationMode != .off else { return }
    let targetLanguage = targetLanguage

    if let cached = await MainActor.run(body: {
      DataService.shared.fetchArticleTranslation(id: item.id, targetLanguage: targetLanguage)
    }) {
      await MainActor.run {
        self.translatedArticleTitle = cached.title
        self.translatedArticleMarkdown = cached.markdown
        if translationMode == .auto {
          self.showTranslatedArticle = true
        }
      }
      return
    }

    guard translationMode == .auto else { return }
    let sourceText = article.textContent ?? HTMLHelper.stripTags(article.contentHTML ?? "")
    guard ReadingLanguage.shouldTranslate(sourceText: sourceText, targetLanguage: targetLanguage) else {
      return
    }
    await generateArticleTranslation(for: article, item: item)
  }

  private func toggleArticleTranslation() async {
    if showTranslatedArticle {
      await MainActor.run {
        withAnimation { showTranslatedArticle = false }
      }
      return
    }

    if translatedArticleMarkdown != nil {
      await MainActor.run {
        withAnimation { showTranslatedArticle = true }
      }
      return
    }

    guard let article = parsedArticle else { return }
    await generateArticleTranslation(for: article, item: currentItem)
  }

  private func generateArticleTranslation(for article: ParsedArticle, item: HNItem) async {
    let articleText = article.textContent ?? HTMLHelper.stripTags(article.contentHTML ?? "")
    guard !articleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    await MainActor.run {
      isTranslatingArticle = true
      translationError = nil
    }

    do {
      let result = try await AIService.shared.translateArticle(
        storyId: item.id,
        title: article.title ?? item.title ?? "Untitled",
        articleText: articleText,
        targetLanguage: targetLanguage
      )
      await MainActor.run {
        translatedArticleTitle = result.title
        translatedArticleMarkdown = result.markdown
        showTranslatedArticle = true
        DataService.shared.saveArticleTranslation(
          id: item.id,
          title: item.title ?? article.title ?? "Untitled",
          url: item.url,
          targetLanguage: targetLanguage,
          translatedTitle: result.title,
          translatedContentMarkdown: result.markdown
        )
      }
    } catch {
      await MainActor.run {
        translationError = error.localizedDescription
      }
    }

    await MainActor.run {
      isTranslatingArticle = false
    }
  }

  private func generateExport() {
    let md = MarkdownGenerator.generate(
      item: currentItem,
      summary: summaryTextForExport,
      article: parsedArticle,
      comments: comments
    )
    self.exportData = ExportData(text: md)
  }

  private func toggleCollapse(_ id: Int) {
    AppTheme.Haptics.playLightImpact()

    if collapsedCommentIds.contains(id) {
      collapsedCommentIds.remove(id)
    } else {
      collapsedCommentIds.insert(id)
    }
    // Re-calculate flattened list
    self.flattenedComments = CommentNode.flattened(comments, collapsedIds: collapsedCommentIds)
  }

  private func loadComments() async {
    guard let kids = currentItem.kids, !kids.isEmpty else { return }
    guard comments.isEmpty else { return }  // already loaded
    guard !isLoadingComments else { return }

    await MainActor.run { isLoadingComments = true }
    do {
      let loader = CommentLoader()
      let rootNodes = try await loader.loadComments(for: kids)
      await MainActor.run {
        self.comments = rootNodes
        // Flatten logic
        self.flattenedComments = CommentNode.flattened(
          rootNodes,
          collapsedIds: collapsedCommentIds
        )
      }
    } catch {
      print("Failed to load comments: \(error)")
    }
    await MainActor.run { isLoadingComments = false }
  }
}

#Preview {
  NavigationStack {
    ItemDetailView(
      item: HNItem(
        id: 123,
        type: .story,
        by: "pg",
        time: Date(),
        text: nil,
        url: "https://google.com",
        score: 100,
        title: "Test Story",
        descendants: 5,
        kids: [1],
        parent: nil,
        deleted: nil,
        dead: nil
      ))
  }
}
