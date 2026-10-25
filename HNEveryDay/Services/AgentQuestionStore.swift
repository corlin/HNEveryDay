//
//  AgentQuestionStore.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import Foundation

/// Runs `operation`, giving up after `seconds`.
nonisolated func withTimeout<T: Sendable>(
  seconds: Double,
  _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      throw URLError(.timedOut)
    }
    defer { group.cancelAll() }
    guard let result = try await group.next() else { throw CancellationError() }
    return result
  }
}

/// Suggested Agent questions per story and language. Keeps a small disk cache, shares in-flight loads,
/// and prefetches from the backend when a story opens, so the Agent sheet usually opens with them ready.
final class AgentQuestionStore {
  static let shared = AgentQuestionStore()

  private static let defaultsKey = "agent_questions_cache"
  private static let maxEntries = 200
  private static let timeoutSeconds = 8.0

  private struct Stored: Codable {
    var order: [String] = []
    var items: [String: [AgentQuestion]] = [:]
  }

  private var stored: Stored
  private var inFlight: [String: Task<[AgentQuestion], Never>] = [:]

  init() {
    stored =
      UserDefaults.standard.data(forKey: Self.defaultsKey)
      .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
  }

  private static func key(_ context: AgentContext) -> String {
    "\(context.storyId)|\(AgentService.currentLanguage)"
  }

  func cached(for context: AgentContext) -> [AgentQuestion]? {
    stored.items[Self.key(context)]
  }

  /// Backend only (free and shared); never spends the user's own key on a story they may not ask about.
  func prefetch(_ context: AgentContext) {
    let key = Self.key(context)
    guard stored.items[key] == nil, inFlight[key] == nil else { return }
    _ = start(context, key: key, allowLocalFallback: false)
  }

  /// Cached questions, or waits (at most a few seconds) for them. Empty means "use the generic ones".
  func questions(for context: AgentContext) async -> [AgentQuestion] {
    let key = Self.key(context)
    if let cached = stored.items[key] { return cached }
    if let pending = inFlight[key] {
      let result = await pending.value
      if !result.isEmpty || AIMode.current == .hosted { return result }
    }
    return await start(context, key: key, allowLocalFallback: true).value
  }

  private func start(_ context: AgentContext, key: String, allowLocalFallback: Bool) -> Task<[AgentQuestion], Never> {
    let task = Task { [weak self] () -> [AgentQuestion] in
      let questions =
        (try? await withTimeout(seconds: Self.timeoutSeconds) {
          try await AgentService.questions(context: context, allowLocalFallback: allowLocalFallback)
        }) ?? []
      self?.finish(key, questions)
      return questions
    }
    inFlight[key] = task
    return task
  }

  private func finish(_ key: String, _ questions: [AgentQuestion]) {
    inFlight[key] = nil
    guard !questions.isEmpty else { return }
    stored.items[key] = questions
    stored.order.removeAll { $0 == key }
    stored.order.append(key)
    while stored.order.count > Self.maxEntries {
      stored.items[stored.order.removeFirst()] = nil
    }
    if let data = try? JSONEncoder().encode(stored) {
      UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
  }
}
