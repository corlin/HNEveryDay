//
//  DataService.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import Combine
import Foundation
import SwiftData
import UIKit

@MainActor
class DataService: ObservableObject {
  static let shared = DataService()

  let container: ModelContainer

  @Published var readStoryIds: Set<Int> = []

  init() {
    do {
      let schema = Schema([CachedStory.self])
      let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
      self.container = try ModelContainer(for: schema, configurations: [modelConfiguration])
      // Initial fetch of read IDs
      self.refreshReadIds()
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }

  func refreshReadIds() {
    let context = container.mainContext
    // Fetch only IDs of read stories for performance
    // Note: SwiftData currently doesn't support fetching strictly IDs easily with Predicate alone without loading models,
    // but we can fetch models with a lightweight descriptor.
    // Optimization: We could use a specific Model for just ID/isRead if needed, but for now fetching CachedStory is okay as long as we don't load Content.
    // Actually, let's just fetch all where isRead == true.
    let descriptor = FetchDescriptor<CachedStory>(predicate: #Predicate { $0.isRead })
    do {
      let stories = try context.fetch(descriptor)
      self.readStoryIds = Set(stories.map { $0.id })
    } catch {
      print("Failed to fetch read IDs: \(error)")
    }
  }

  func cleanupOldEntries() {
    Task {  // Run on background
      let context = ModelContext(container)
      // Read user preference, default to 30 days
      let storedDays = UserDefaults.standard.integer(forKey: "cache_retention_days")
      let days = storedDays > 0 ? storedDays : 30
      let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

      print("🧹 Housekeeping: Cleaning entries older than \(days) days.")

      let descriptor = FetchDescriptor<CachedStory>(
        predicate: #Predicate {
          $0.lastOpened < cutoffDate && !$0.isSaved
        })

      do {
        let oldStories = try context.fetch(descriptor)
        if !oldStories.isEmpty {
          print("🧹 Housekeeping: Deleting \(oldStories.count) old stories.")
          for story in oldStories {
            context.delete(story)
          }
          try context.save()
        }
      } catch {
        print("Housekeeping failed: \(error)")
      }
    }
  }

  func markAsRead(item: HNItem) {
    let context = container.mainContext
    let id = item.id

    let descriptor = FetchDescriptor<CachedStory>(predicate: #Predicate { $0.id == id })

    do {
      let results = try context.fetch(descriptor)
      if let existing = results.first {
        existing.isRead = true
        existing.lastOpened = Date()
      } else {
        let newStory = CachedStory(
          id: item.id,
          title: item.title ?? "Untitled",
          url: item.url,
          isRead: true,
          lastOpened: Date()
        )
        context.insert(newStory)
      }
      try context.save()

      // Update local set
      self.readStoryIds.insert(id)
    } catch {
      print("Failed to mark as read: \(error)")
    }
  }

  func fetchCachedStory(id: Int) -> CachedStory? {
    let context = container.mainContext
    let descriptor = FetchDescriptor<CachedStory>(predicate: #Predicate { $0.id == id })
    do {
      return try context.fetch(descriptor).first
    } catch {
      print("Failed to fetch cached story: \(error)")
      return nil
    }
  }

  func saveContent(id: Int, title: String, url: String?, content: String) {
    let context = container.mainContext
    let descriptor = FetchDescriptor<CachedStory>(predicate: #Predicate { $0.id == id })
    do {
      let story: CachedStory
      if let existing = try context.fetch(descriptor).first {
        story = existing
      } else {
        story = CachedStory(id: id, title: title, url: url)
        context.insert(story)
      }
      story.contentHTML = content
      story.lastOpened = Date()
      try context.save()
    } catch {
      print("Failed to save content: \(error)")
    }
  }

  func saveSummary(id: Int, title: String, url: String?, summary: String) {
    let context = container.mainContext
    let descriptor = FetchDescriptor<CachedStory>(predicate: #Predicate { $0.id == id })
    do {
      let story: CachedStory
      if let existing = try context.fetch(descriptor).first {
        story = existing
      } else {
        story = CachedStory(id: id, title: title, url: url)
        context.insert(story)
      }
      story.summary = summary
      story.lastOpened = Date()
      try context.save()
    } catch {
      print("Failed to save summary: \(error)")
    }
  }

  // MARK: - Bookmarks
  @Published var savedStoryIds: Set<Int> = []

  func refreshSavedIds() {
    let context = container.mainContext
    let descriptor = FetchDescriptor<CachedStory>(predicate: #Predicate { $0.isSaved })
    do {
      let stories = try context.fetch(descriptor)
      self.savedStoryIds = Set(stories.map { $0.id })
    } catch {
      print("Failed to fetch saved IDs: \(error)")
    }
  }

  func toggleSave(item: HNItem) {
    let context = container.mainContext
    let id = item.id
    let descriptor = FetchDescriptor<CachedStory>(predicate: #Predicate { $0.id == id })

    do {
      if let existing = try context.fetch(descriptor).first {
        existing.isSaved.toggle()
        try context.save()
        // Update local set
        if existing.isSaved {
          savedStoryIds.insert(id)
        } else {
          savedStoryIds.remove(id)
        }
      } else {
        // Create new entry if not exists
        let newStory = CachedStory(
          id: item.id,
          title: item.title ?? "Untitled",
          url: item.url,
          isSaved: true
        )
        context.insert(newStory)
        try context.save()
        savedStoryIds.insert(id)
      }
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    } catch {
      print("Failed to toggle save: \(error)")
    }
  }

  func fetchSavedStories() -> [CachedStory] {
    let context = container.mainContext
    let descriptor = FetchDescriptor<CachedStory>(predicate: #Predicate { $0.isSaved })
    do {
      return try context.fetch(descriptor)
    } catch {
      print("Failed to fetch saved stories: \(error)")
      return []
    }
  }
}
