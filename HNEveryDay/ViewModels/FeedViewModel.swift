//
//  FeedViewModel.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import Foundation
import Observation

@Observable
final class FeedViewModel {
  var stories: [HNItem] = []
  var isLoading = false
  var selectedFeedType: HNClient.StoryType = .top
  /// Set when the last load failed, so the feed can show an error with Retry instead of "no stories".
  var loadError: String?
  /// Bumped after background title translations are saved, so visible rows pick them up.
  var titleTranslationsVersion = 0

  // Pagination State
  private var allStoryIds: [Int] = []
  private var currentPage = 0
  private let pageSize = 40
  private var isFetchingPage = false
  private var isPrefetchingMultiFeeds = false

  var hasMoreStories: Bool {
    return stories.count < allStoryIds.count
  }

  // MARK: - Actions

  @MainActor
  func updateFeedType(_ type: HNClient.StoryType) async {
    guard selectedFeedType != type else { return }
    selectedFeedType = type
    await refresh()
  }

  @MainActor
  func refresh() async {
    guard !isLoading else { return }
    isLoading = true
    loadError = nil
    stories = []
    allStoryIds = []
    currentPage = 0

    do {
      allStoryIds = try await HNClient.shared.fetchStoryIds(type: selectedFeedType)
      await loadNextPage()
      
      // Kick off background multi-feed prefetch for top/new/best if current feed is top
      if selectedFeedType == .top && !isPrefetchingMultiFeeds {
        Task.detached(priority: .utility) { [weak self] in
          await self?.prefetchPrimaryFeeds()
        }
      }
    } catch {
      print("Failed to fetch IDs: \(error)")
      loadError = error.localizedDescription
    }

    isLoading = false
  }

  @MainActor
  func loadNextPage() async {
    guard !isFetchingPage && hasMoreStories else { return }
    isFetchingPage = true

    let startIndex = currentPage * pageSize
    let endIndex = min(startIndex + pageSize, allStoryIds.count)

    guard startIndex < endIndex else {
      isFetchingPage = false
      return
    }

    let pageIds = Array(allStoryIds[startIndex..<endIndex])

    do {
      let newStories = try await HNClient.shared.fetchItems(ids: pageIds)
      let validStories = newStories.filter { $0.title != nil }

      self.stories.append(contentsOf: validStories)
      self.currentPage += 1

      // Data-driven background title translation batch pipeline
      scheduleBackgroundTitleTranslations(for: validStories)
    } catch {
      print("Failed to load page: \(error)")
      if stories.isEmpty {
        loadError = error.localizedDescription
      }
    }

    isFetchingPage = false
  }

  // MARK: - Multi-Feed Prefetch & AI Batch Pipeline

  private func prefetchPrimaryFeeds() async {
    isPrefetchingMultiFeeds = true
    defer { isPrefetchingMultiFeeds = false }

    do {
      let primaryTypes: [HNClient.StoryType] = [.top, .new, .best]
      let uniqueIds = try await HNClient.shared.fetchMultiFeedIds(types: primaryTypes, limitPerFeed: 40)
      let prefetchedStories = try await HNClient.shared.fetchItems(ids: uniqueIds)
      let validStories = prefetchedStories.filter { $0.title != nil }

      // Schedule background large-batch AI translation for prefetched items
      scheduleBackgroundTitleTranslations(for: validStories)
    } catch {
      print("Multi-feed prefetch error: \(error)")
    }
  }

  private func scheduleBackgroundTitleTranslations(for items: [HNItem]) {
    // Same keys as Settings: translation on (on demand or auto) translates titles into the reading language.
    let modeRaw = UserDefaults.standard.string(forKey: "translation_mode") ?? TranslationMode.defaultRawValue
    guard (TranslationMode(rawValue: modeRaw) ?? .off) != .off else { return }

    let targetLanguage = ReadingLanguage.resolvedCode(
      preferredLanguage: UserDefaults.standard.string(forKey: "preferred_language") ?? ReadingLanguage.systemCode)

    Task.detached(priority: .background) { [weak self] in
      var inputs: [AIService.TitleTranslationInput] = []

      for item in items {
        guard let title = item.title, !title.isEmpty else { continue }
        // Skip if already translated in cache
        if await DataService.shared.fetchTitleTranslation(id: item.id, targetLanguage: targetLanguage) != nil {
          continue
        }
        // Skip if language matching source
        if !ReadingLanguage.shouldTranslate(sourceText: title, targetLanguage: targetLanguage) {
          continue
        }
        inputs.append(AIService.TitleTranslationInput(id: item.id, title: title))
      }

      guard !inputs.isEmpty else { return }

      // Chunk into super batches (50 items per request)
      let batchSize = 50
      let chunks = stride(from: 0, to: inputs.count, by: batchSize).map {
        Array(inputs[$0..<min($0 + batchSize, inputs.count)])
      }

      for chunk in chunks {
        do {
          let translations = try await AIService.shared.translateTitles(chunk, targetLanguage: targetLanguage)
          for input in chunk {
            if let translated = translations[input.id], !translated.isEmpty {
              await DataService.shared.saveTitleTranslation(
                id: input.id,
                title: input.title,
                url: nil,
                targetLanguage: targetLanguage,
                translatedTitle: translated
              )
            }
          }
          await self?.titleTranslationsDidChange()
        } catch {
          print("Batch AI translation failed for chunk of \(chunk.count): \(error)")
        }
      }
    }
  }

  private func titleTranslationsDidChange() {
    titleTranslationsVersion += 1
  }
}
