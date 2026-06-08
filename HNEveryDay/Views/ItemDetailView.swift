//
//  ItemDetailView.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import SwiftUI

struct ItemDetailView: View {
  let item: HNItem

  @State private var selectedMode = 0  // 0 = Article, 1 = Comments
  @State private var comments: [CommentNode] = []
  @State private var flattenedComments: [CommentNode] = []
  @State private var isLoadingComments = false
  @State private var showSummary = false
  @State private var collapsedCommentIds: Set<Int> = []

  // Reader Mode State
  @State private var parsedArticle: ParsedArticle?
  @State private var isParsingArticle = false
  @State private var showReaderMode = true  // Default to true

  // Export State
  struct ExportData: Identifiable {
    let id = UUID()
    let text: String
  }
  @State private var exportData: ExportData?
  @State private var summaryTextForExport: String?

  var body: some View {
    VStack(spacing: 0) {
      // MARK: - Picker
      Picker("Mode", selection: $selectedMode) {
        Text("Article", comment: "Read mode").tag(0)
        Text("Comments", comment: "Discussion mode").tag(1)
      }
      .pickerStyle(.segmented)
      .padding()
      .background(Color(.systemBackground))
      .zIndex(1)

      // MARK: - Content
      TabView(selection: $selectedMode) {
        // MODIFIED: Article View with Smart Reader
        Group {
          if let url = item.urlObj {
            if showReaderMode, let article = parsedArticle {
              ReaderView(article: article)
                .transition(.opacity)
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
            } else {
              // Fallback to Webview
              WebView(url: url)
                .transition(.opacity)
            }
          } else if item.text != nil {
            ScrollView {
              Text(HTMLHelper.parse(item.text ?? ""))
                .padding()
            }
          } else {
            ContentUnavailableView("No URL", systemImage: "link.badge.plus")
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
                Text(item.title ?? "")
                  .font(.headline)
                HStack {
                  Text("\(item.score ?? 0) points")
                  Text("by \(item.by ?? "")")  // 'by' is hard to localize elegantly in concatenation, will leave as is or use a format string
                  Text(item.time.shortTimeAgo)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              .listRowSeparator(.hidden)

              ForEach(flattenedComments) { node in
                CommentRowView(node: node, isCollapsed: collapsedCommentIds.contains(node.id))
                  .listRowSeparator(.hidden)
                  .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                  .onTapGesture {
                    toggleCollapse(node.id)
                  }
              }
            }
            .listStyle(.plain)
          }
        }
        .tag(1)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))  // Swipe left/right
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      // Reader Toggle
      if selectedMode == 0 && item.urlObj != nil {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            withAnimation {
              showReaderMode.toggle()
            }
          } label: {
            Image(systemName: showReaderMode ? "doc.plaintext.fill" : "globe")
              .foregroundStyle(showReaderMode ? .orange : .primary)
          }
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
          showSummary = true
        } label: {
          Image(systemName: "sparkles")
        }
      }
    }
    // Share Sheet
    .sheet(item: $exportData) { data in
      ShareSheet(activityItems: [data.text])
        .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $showSummary) {
      SummaryView(
        item: item, comments: flattenedComments, article: parsedArticle,
        initialSummary: summaryTextForExport,
        onSummaryGenerated: { summary in
          self.summaryTextForExport = summary
        }
      )
      .presentationDetents([.medium, .large])
    }
    .task {
      // Parallel load: Comments AND Reader Parsing
      await withTaskGroup(of: Void.self) { group in
        group.addTask { await loadComments() }
        group.addTask { await loadArticleContent() }
      }
    }
    // Force comments mode if no URL
    .onAppear {
      DataService.shared.markAsRead(item: item)
      summaryTextForExport = DataService.shared.fetchCachedStory(id: item.id)?.summary
      if item.url == nil {
        selectedMode = 1
      }
    }
  }

  private func loadArticleContent() async {
    guard let url = item.urlObj else { return }
    guard parsedArticle == nil else { return }

    if let cachedContent = await MainActor.run(body: {
      DataService.shared.fetchCachedStory(id: item.id)?.contentHTML
    }) {
      await MainActor.run {
        self.parsedArticle = ParsedArticle(
          title: item.title,
          byline: item.by,
          contentHTML: cachedContent,
          textContent: HTMLHelper.stripTags(cachedContent),
          excerpt: nil,
          siteName: url.host
        )
      }
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

  private func generateExport() {
    let md = MarkdownGenerator.generate(
      item: item,
      summary: summaryTextForExport,
      article: parsedArticle,
      comments: comments
    )
    self.exportData = ExportData(text: md)
  }

  private func toggleCollapse(_ id: Int) {
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()

    if collapsedCommentIds.contains(id) {
      collapsedCommentIds.remove(id)
    } else {
      collapsedCommentIds.insert(id)
    }
    // Re-calculate flattened list
    self.flattenedComments = flatten(nodes: comments)
  }

  private func loadComments() async {
    guard let kids = item.kids, !kids.isEmpty else { return }
    guard comments.isEmpty else { return }  // already loaded

    await MainActor.run { isLoadingComments = true }
    do {
      let loader = CommentLoader()
      let rootNodes = try await loader.loadComments(for: kids)
      await MainActor.run {
        self.comments = rootNodes
        // Flatten logic
        self.flattenedComments = flatten(nodes: rootNodes)
      }
    } catch {
      print("Failed to load comments: \(error)")
    }
    await MainActor.run { isLoadingComments = false }
  }

  // DFS flattening with Collapse check
  private func flatten(nodes: [CommentNode]) -> [CommentNode] {
    var result: [CommentNode] = []
    for node in nodes {
      result.append(node)
      // If NOT collapsed, include children
      if !collapsedCommentIds.contains(node.id) && !node.children.isEmpty {
        result.append(contentsOf: flatten(nodes: node.children))
      }
    }
    return result
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
