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
  @AppStorage("translation_mode") private var translationModeRaw: String = TranslationMode.defaultRawValue
  @State private var selectedMode = 0  // 0 = Article, 1 = Comments

  struct QuotaInfo {
    let resetAt: Date?
  }
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
  @State private var translationStartedAt = Date()
  @State private var translationError: String?
  @State private var translationQuota: QuotaInfo?
  @State private var commentsError: String?
  @State private var showPaywall = false
  @State private var showAgent = false
  @State private var isAgentEnabled = true
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

  private var agentContext: AgentContext {
    let article = parsedArticle.flatMap { $0.textContent ?? HTMLHelper.stripTags($0.contentHTML ?? "") }
    let selfText = currentItem.text.map { HTMLHelper.stripTags($0) }
    return AgentContext(
      storyId: currentItem.id,
      title: currentItem.title ?? "Untitled",
      url: currentItem.url,
      score: currentItem.score ?? 0,
      commentCount: currentItem.descendants ?? 0,
      articleText: article ?? selfText,
      comments: CommentNode.flattened(comments).compactMap { node in
        guard let text = node.item.text else { return nil }
        return AgentComment(depth: node.depth, author: node.item.by ?? "unknown", text: HTMLHelper.stripTags(text))
      }
    )
  }

  private var targetLanguage: String {
    ReadingLanguage.resolvedCode(preferredLanguage: preferredLanguage)
  }

  var body: some View {
    VStack(spacing: 0) {
      modePickerBar

      // Both panes stay alive so switching keeps the reader's scroll position and the loaded web page.
      ZStack {
        articlePane
          .opacity(selectedMode == 0 ? 1 : 0)
          .allowsHitTesting(selectedMode == 0)
          .accessibilityHidden(selectedMode != 0)

        commentsPane
          .opacity(selectedMode == 1 ? 1 : 0)
          .allowsHitTesting(selectedMode == 1)
          .accessibilityHidden(selectedMode != 1)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        aiActionBar
      }
      .background(Color(.systemGroupedBackground))
    }
    .background(Color(.systemGroupedBackground))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if selectedMode == 0 && showReaderMode && parsedArticle != nil && translationMode != .off {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await toggleArticleTranslation() }
          } label: {
            if isTranslatingArticle {
              ProgressView()
                .controlSize(.mini)
            } else {
              Image(systemName: "translate")
                .foregroundStyle(showTranslatedArticle ? AppTheme.Palette.brand : Color.primary)
            }
          }
          .disabled(isTranslatingArticle)
          .accessibilityLabel(showTranslatedArticle ? Text("Show Original Article") : Text("Translate Article"))
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        moreMenu
      }
    }
    .sheet(isPresented: $showPaywall) {
      PaywallView(reason: .quota(kind: "article"))
    }
    .sheet(isPresented: $showAgent) {
      AgentSheetView(context: agentContext)
    }
    .task {
      if AIMode.current == .hosted {
        isAgentEnabled = await RemoteConfigStore.shared.current().features.agent
      }
    }
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
      // Warm the Agent's suggested questions while the user reads.
      if isAgentEnabled {
        AgentQuestionStore.shared.prefetch(agentContext)
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

  // MARK: - Panes

  @ViewBuilder
  private var articlePane: some View {
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
    } else if let text = currentItem.text {
      ScrollView {
        Text(HTMLHelper.parse(text))
          .font(.body)
          .tint(AppTheme.Palette.brand)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
      }
      .background(Color(.systemGroupedBackground))
    } else {
      ContentUnavailableView("No URL", systemImage: "link.badge.plus")
        .background(Color(.systemGroupedBackground))
    }
  }

  @ViewBuilder
  private var commentsPane: some View {
    if isLoadingComments {
      ProgressView("Loading Thread...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let commentsError, flattenedComments.isEmpty {
      ContentUnavailableView {
        Label("Couldn't Load Comments", systemImage: "wifi.slash")
      } description: {
        Text(commentsError)
      } actions: {
        Button("Try Again") {
          Task { await loadComments() }
        }
        .buttonStyle(.borderedProminent)
      }
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
            Text("by \(currentItem.by ?? "")")
            Text(currentItem.time.shortTimeAgo)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)

        ForEach(flattenedComments) { node in
          CommentRowView(
            node: node,
            isCollapsed: collapsedCommentIds.contains(node.id),
            onToggleCollapse: { toggleCollapse(node.id) }
          )
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          .listRowBackground(Color.clear)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(Color(.systemGroupedBackground))
    }
  }

  // MARK: - Actions

  /// Summary and Ask Agent sit in a bar under the content instead of floating over it.
  private var aiActionBar: some View {
    HStack(spacing: 10) {
      Button {
        Task { await presentSummary() }
      } label: {
        HStack(spacing: 6) {
          if isPreparingSummary {
            ProgressView()
              .controlSize(.small)
          } else {
            Image(systemName: "list.bullet.clipboard")
          }
          Text("Summary", comment: "Button that opens the AI summary of the article and discussion")
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(.bordered)
      .disabled(isPreparingSummary)
      .accessibilityLabel("Summarize Discussion")

      if isAgentEnabled {
        Button {
          showAgent = true
        } label: {
          Label("Ask Agent", systemImage: "bubble.left.and.text.bubble.right")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .tint(AppTheme.Palette.brand)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.bar)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(AppTheme.Palette.hairline)
        .frame(height: 1)
    }
  }

  /// Less frequent actions, so the navigation bar keeps at most two buttons.
  private var moreMenu: some View {
    Menu {
      if let url = currentItem.urlObj {
        Button {
          withAnimation {
            showReaderMode.toggle()
            if !showReaderMode {
              showTranslatedArticle = false
            }
          }
          selectedMode = 0
        } label: {
          if showReaderMode {
            Label("Show Original Web Page", systemImage: "globe")
          } else {
            Label("Show Reader", systemImage: "doc.plaintext")
          }
        }

        Link(destination: url) {
          Label("Open in Safari", systemImage: "safari")
        }

        ShareLink(item: url) {
          Label("Share Link", systemImage: "square.and.arrow.up")
        }
      }

      Button {
        generateExport()
      } label: {
        Label("Export as Markdown", systemImage: "arrow.down.doc")
      }

      if let hnURL = URL(string: "https://news.ycombinator.com/item?id=\(currentItem.id)") {
        ShareLink(item: hnURL) {
          Label("Share HN Discussion", systemImage: "bubble.left.and.bubble.right")
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .accessibilityLabel("More")
  }

  private var modePickerBar: some View {
    VStack(spacing: 0) {
      Picker("Mode", selection: $selectedMode) {
        Text("Article", comment: "Read mode").tag(0)
        Text(commentsTabTitle).tag(1)
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 16)
      .padding(.top, 10)
      .padding(.bottom, 8)
    }
    .background(Color(.systemGroupedBackground))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(AppTheme.Palette.hairline)
        .frame(height: 1)
    }
    .zIndex(1)
  }

  private var commentsTabTitle: String {
    if let count = currentItem.descendants, count > 0 {
      return String(localized: "Comments (\(count))")
    }
    return String(localized: "Comments")
  }

  @ViewBuilder
  private var articleStatusBanner: some View {
    if isTranslatingArticle {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.mini)
        TimelineView(.periodic(from: translationStartedAt, by: 1)) { timeline in
          let seconds = Int(timeline.date.timeIntervalSince(translationStartedAt))
          Group {
            if seconds >= 10 {
              Text("Translating article… \(seconds)s, long articles can take a minute")
            } else {
              Text("Translating article...")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .cardSurface()
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .padding(.bottom, 4)
    } else if let translationQuota {
      QuotaLimitCard(kind: "article", resetAt: translationQuota.resetAt) {
        showPaywall = true
      }
      .overlay(alignment: .topTrailing) {
        Button {
          withAnimation { self.translationQuota = nil }
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text("Close"))
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .padding(.bottom, 4)
    } else if let translationError {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(AppTheme.Palette.brand)
          .padding(.top, 1)

        Text(translationError)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 0)

        Button("Try Again") {
          Task { await toggleArticleTranslation() }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.Palette.brand)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .cardSurface(stroke: AppTheme.Palette.brand.opacity(0.22))
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
      withAnimation { showTranslatedArticle = false }
      return
    }

    if translatedArticleMarkdown == nil,
      let cached = DataService.shared.fetchArticleTranslation(id: currentItem.id, targetLanguage: targetLanguage)
    {
      translatedArticleTitle = cached.title
      translatedArticleMarkdown = cached.markdown
    }

    if translatedArticleMarkdown != nil {
      withAnimation { showTranslatedArticle = true }
      return
    }

    guard let article = parsedArticle else { return }
    await generateArticleTranslation(for: article, item: currentItem)
  }

  private func generateArticleTranslation(for article: ParsedArticle, item: HNItem) async {
    // One translation at a time: repeated taps (or auto mode plus a tap) must not start, and pay for, another.
    guard !isTranslatingArticle else { return }
    let articleText = article.textContent ?? HTMLHelper.stripTags(article.contentHTML ?? "")
    guard !articleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    isTranslatingArticle = true
    translationError = nil
    translationQuota = nil
    translationStartedAt = Date()

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
        if case .quotaExceeded(_, _, let resetAt)? = error as? AIServiceError {
          translationQuota = QuotaInfo(resetAt: resetAt)
        } else {
          translationError = error.localizedDescription
        }
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

    await MainActor.run {
      isLoadingComments = true
      commentsError = nil
    }
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
      await MainActor.run { commentsError = error.localizedDescription }
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
