//
//  CommentLoader.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import Foundation

protocol HNCommentFetching: Sendable {
  func fetchItems(ids: [Int]) async throws -> [HNItem]
}

extension HNClient: HNCommentFetching {}

actor CommentLoader {
  // Cache to prevent re-fetching
  private var cache: [Int: HNItem] = [:]
  private let client: any HNCommentFetching

  init(client: any HNCommentFetching = HNClient.shared) {
    self.client = client
  }

  /// Recursively fetches comments up to a certain depth or limit.
  /// Returns the root node populated with children.
  func loadComments(for storyIds: [Int]) async throws -> [CommentNode] {
    return try await fetchChildren(ids: storyIds, depth: 0)
  }

  private func fetchChildren(ids: [Int], depth: Int) async throws -> [CommentNode] {
    // Limit depth to avoid infinite recursion on very deep threads for V1
    guard depth < 10 else { return [] }

    // Parallel fetch of items at this level
    let items = try await fetchItems(ids: ids)

    // We need to fetch children's children *in parallel* but preserve order?
    // Actually, let's do it simply first: fetch this level, and map to nodes.
    // For V1, we might only fetch the top level fully, and lazy load deeper?
    // Or fetch 2-3 levels?
    // Geeker perspective replacement: "I want to see the thread."
    // Let's implement a recursive fetch with `TaskGroup`.

    return try await withThrowingTaskGroup(of: CommentNode?.self) { group in
      for item in items {
        // Skip deleted/dead
        if (item.deleted ?? false) || (item.dead ?? false) { continue }

        group.addTask {
          var node = CommentNode(id: item.id, item: item, depth: depth)
          if let kids = item.kids, !kids.isEmpty {
            // Recursively fetch children
            // Note: In a real app, maybe limit concurrency or demand-load
            let children = try await self.fetchChildren(ids: kids, depth: depth + 1)
            node.children = children
          }
          return node
        }
      }

      var results: [CommentNode] = []
      for try await node in group {
        if let node = node {
          results.append(node)
        }
      }

      // Re-sort results to match input order (HNClient.fetchItems also re-sorts, but we need to match original `ids` order)
      // Ideally HNClient guarantees order, but let's double check.
      // HNClient.fetchItems returns sorted by input IDs.
      // But here we are processing in parallel group, results come out of order.

      let nodeMap = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
      return ids.compactMap { nodeMap[$0] }
    }
  }

  private func fetchItems(ids: [Int]) async throws -> [HNItem] {
    var seenMissingIds: Set<Int> = []
    let missingIds = ids.filter { id in
      guard !cache.keys.contains(id), !seenMissingIds.contains(id) else {
        return false
      }
      seenMissingIds.insert(id)
      return true
    }
    if !missingIds.isEmpty {
      let fetchedItems = try await client.fetchItems(ids: missingIds)
      for item in fetchedItems {
        cache[item.id] = item
      }
    }
    return ids.compactMap { cache[$0] }
  }
}
