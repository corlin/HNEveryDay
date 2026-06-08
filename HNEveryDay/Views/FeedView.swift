//
//  FeedView.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import SwiftUI

struct FeedView: View {
  @State private var viewModel = FeedViewModel()
  @ObservedObject private var dataService = DataService.shared
  @State private var showSettings = false
  @State private var showingSavedOnly = false

  var body: some View {
    NavigationStack {
      List {
        // Show saved stories from cache or live feed
        if showingSavedOnly {
          let savedStories = dataService.fetchSavedStories()
          if savedStories.isEmpty {
            ContentUnavailableView(
              "No Saved Stories", systemImage: "bookmark.slash",
              description: Text("Swipe left on a story to save it."))
          } else {
            ForEach(savedStories, id: \.id) { cached in
              let savedItem = item(from: cached)
              NavigationLink(destination: ItemDetailView(item: savedItem)) {
                HStack(alignment: .top, spacing: 12) {
                  Image(systemName: "bookmark.fill")
                    .foregroundStyle(.orange)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(cached.title)
                      .font(.headline)
                    if let url = cached.url {
                      Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                  }
                }
              }
              .padding(.vertical, 4)
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                  dataService.toggleSave(item: savedItem)
                } label: {
                  Label("Remove", systemImage: "trash")
                }
              }
            }
          }
        } else {
          ForEach(viewModel.stories) { story in
            NavigationLink(destination: ItemDetailView(item: story)) {
              StoryRowView(
                item: story,
                isRead: dataService.readStoryIds.contains(story.id),
                isSaved: dataService.savedStoryIds.contains(story.id)
              )
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              Button {
                dataService.toggleSave(item: story)
              } label: {
                let isSaved = dataService.savedStoryIds.contains(story.id)
                Label(
                  isSaved ? "Unsave" : "Save", systemImage: isSaved ? "bookmark.slash" : "bookmark")
              }
              .tint(.orange)
            }
            .onAppear {
              if story.id == viewModel.stories.last?.id {
                Task { await viewModel.loadNextPage() }
              }
            }
          }

          if viewModel.isLoading && viewModel.stories.isEmpty {
            SkeletonView()
          }

          if viewModel.stories.isEmpty && !viewModel.isLoading {
            ContentUnavailableView(
              "No Stories Found", systemImage: "wifi.slash",
              description: Text("Check your connection or try again."))
          }
        }
      }
      .listStyle(.plain)
      .navigationTitle(showingSavedOnly ? "Saved" : "Hacker News")
      .refreshable {
        if !showingSavedOnly {
          await viewModel.refresh()
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            showSettings = true
          } label: {
            Image(systemName: "gearshape")
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            // Saved Filter Toggle
            Button {
              showingSavedOnly.toggle()
            } label: {
              Label(
                showingSavedOnly ? "Show Feed" : "Saved",
                systemImage: showingSavedOnly ? "list.bullet" : "bookmark.fill")
            }

            Divider()

            Picker(
              "Category",
              selection: Binding(
                get: { viewModel.selectedFeedType },
                set: { type in
                  showingSavedOnly = false
                  Task { await viewModel.updateFeedType(type) }
                }
              )
            ) {
              Label("Top", systemImage: "flame").tag(HNClient.StoryType.top)
              Label("New", systemImage: "clock").tag(HNClient.StoryType.new)
              Label("Best", systemImage: "star").tag(HNClient.StoryType.best)
              Label("Show", systemImage: "eye").tag(HNClient.StoryType.show)
              Label("Ask", systemImage: "questionmark.circle").tag(HNClient.StoryType.ask)
              Label("Jobs", systemImage: "briefcase").tag(HNClient.StoryType.job)
            }
          } label: {
            Label(
              "Filter",
              systemImage: showingSavedOnly ? "bookmark.fill" : "line.3.horizontal.decrease.circle")
          }
        }
      }
      .sheet(isPresented: $showSettings) {
        SettingsView()
      }
    }
    .task {
      // Initial load
      if viewModel.stories.isEmpty {
        await viewModel.refresh()
      }
      // Refresh saved IDs
      dataService.refreshSavedIds()
      // Housekeeping
      dataService.cleanupOldEntries()
    }
  }

  private func item(from cached: CachedStory) -> HNItem {
    HNItem(
      id: cached.id,
      type: .story,
      by: nil,
      time: cached.lastOpened,
      text: nil,
      url: cached.url,
      score: nil,
      title: cached.title,
      descendants: nil,
      kids: nil,
      parent: nil,
      deleted: nil,
      dead: nil
    )
  }
}

#Preview {
  FeedView()
}
