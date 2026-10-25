//
//  AgentViewModel.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import Foundation
import Observation
import SwiftUI

struct AgentMessage: Identifiable, Equatable {
  enum Role: String { case user, assistant }

  let id = UUID()
  let role: Role
  /// Raw text; for answers this includes the trailing `<followups>` block.
  var text: String

  /// What the reader sees (and what is sent back as history, copied or reported).
  var visibleText: String {
    role == .assistant ? AgentFollowUps.visibleText(text) : text
  }

  var followUps: [String] {
    role == .assistant ? AgentFollowUps.questions(text) : []
  }
}

/// Smart Chips: story-specific questions generated for each story, with generic ones as a fallback.
struct AgentChip: Identifiable, Hashable {
  let icon: String
  let title: String

  var id: String { title }

  init(icon: String, title: String) {
    self.icon = icon
    self.title = title
  }

  init(_ question: AgentQuestion) {
    self.init(icon: Self.icon(for: question.type), title: question.text)
  }

  static func icon(for type: String) -> String {
    switch type {
    case "debate": return "flame"
    case "code": return "chevron.left.forwardslash.chevron.right"
    case "compare": return "arrow.left.arrow.right"
    case "fit": return "scope"
    case "risk": return "exclamationmark.triangle"
    case "history": return "clock.arrow.circlepath"
    case "data": return "chart.bar"
    case "practice": return "hammer"
    default: return "lightbulb"
    }
  }

  static let fallback: [AgentChip] = [
    AgentChip(icon: "flame", title: String(localized: "What is the biggest disagreement in the comments?")),
    AgentChip(icon: "chevron.left.forwardslash.chevron.right", title: String(localized: "Explain the core code or architecture")),
    AgentChip(icon: "arrow.left.arrow.right", title: String(localized: "Compare the alternatives mentioned")),
    AgentChip(icon: "scope", title: String(localized: "When does this fit, and when not?")),
  ]
}

@MainActor
@Observable
final class AgentViewModel {
  private(set) var messages: [AgentMessage] = []
  private(set) var isStreaming = false
  private(set) var remaining: Int?
  private(set) var limit: Int?
  /// Generic chips show immediately; story-specific ones replace them as soon as they arrive.
  private(set) var suggestions: [AgentChip]
  private(set) var isLoadingSuggestions = false
  /// Set while an answer has been requested but no text has arrived yet.
  private(set) var waitingSince: Date?
  var errorMessage: String?
  var quotaExceeded = false
  /// The question to resend when the last attempt failed for a transient reason.
  private(set) var retryableQuestion: String?

  @ObservationIgnored private let context: AgentContext
  @ObservationIgnored private var streamTask: Task<Void, Never>?
  @ObservationIgnored private var watchdog: Task<Void, Never>?

  /// Give up when no text has arrived after this long.
  static let firstTokenTimeout: TimeInterval = 30
  /// Streamed text is applied to the UI at most this often, so long answers don't re-render per token.
  static let renderInterval: TimeInterval = 0.06

  init(context: AgentContext) {
    self.context = context
    suggestions = AgentQuestionStore.shared.cached(for: context)?.map(AgentChip.init) ?? AgentChip.fallback
  }

  var canSend: Bool { !isStreaming }

  /// Follow-up chips under the latest finished answer.
  var followUpChips: [AgentChip] {
    guard !isStreaming, let last = messages.last, last.role == .assistant else { return [] }
    return last.followUps.map { AgentChip(icon: "arrow.turn.down.right", title: $0) }
  }

  /// Replaces the generic chips with story-specific ones; keeps the generic ones if that fails or is slow.
  func loadSuggestions() async {
    guard AgentQuestionStore.shared.cached(for: context) == nil, !isLoadingSuggestions else { return }
    isLoadingSuggestions = true
    let questions = await AgentQuestionStore.shared.questions(for: context)
    isLoadingSuggestions = false
    if !questions.isEmpty {
      withAnimation(AppTheme.Spring.snappy) { suggestions = questions.map(AgentChip.init) }
    }
  }

  func retry() {
    guard let question = retryableQuestion, !isStreaming else { return }
    if messages.last?.role == .user, messages.last?.text == question { messages.removeLast() }
    send(question)
  }

  func send(_ text: String) {
    let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty, !isStreaming else { return }

    errorMessage = nil
    quotaExceeded = false
    retryableQuestion = nil
    messages.append(AgentMessage(role: .user, text: question))
    let history = messages.map { AgentTurn(role: $0.role.rawValue, content: $0.visibleText) }
    messages.append(AgentMessage(role: .assistant, text: ""))
    let replyId = messages[messages.count - 1].id
    isStreaming = true
    waitingSince = Date()
    AppTheme.Haptics.playLightImpact()

    streamTask = Task { [context] in
      var pending = ""
      var lastFlush = Date.distantPast
      do {
        for try await event in AgentService.stream(context: context, history: history) {
          switch event {
          case .meta(let remaining, let limit):
            self.remaining = remaining
            self.limit = limit
          case .delta(let text):
            pending += text
            // First text shows at once; after that, batch updates.
            if self.waitingSince != nil || Date().timeIntervalSince(lastFlush) >= Self.renderInterval {
              self.waitingSince = nil
              self.append(pending, to: replyId)
              pending = ""
              lastFlush = Date()
            }
          case .done:
            break
          }
        }
      } catch is CancellationError {
        // Stopped by the user or the watchdog; keep what was produced.
      } catch {
        if (error as NSError).code != NSURLErrorCancelled {
          self.fail(error, question: question, replyId: replyId)
        }
      }
      if !pending.isEmpty { self.append(pending, to: replyId) }
      self.watchdog?.cancel()
      self.waitingSince = nil
      self.isStreaming = false
      self.dropEmptyReply(replyId)
    }

    watchdog?.cancel()
    watchdog = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.firstTokenTimeout * 1_000_000_000))
      guard let self, !Task.isCancelled, self.waitingSince != nil else { return }
      self.streamTask?.cancel()
      self.errorMessage = String(localized: "The AI is taking too long to respond. Please try again.")
      self.retryableQuestion = question
    }
  }

  /// Stops generation; the partial answer stays. The turn still counts toward today's allowance.
  func stop() {
    watchdog?.cancel()
    streamTask?.cancel()
    streamTask = nil
    waitingSince = nil
    isStreaming = false
  }

  func reset() {
    stop()
    messages.removeAll()
    errorMessage = nil
    quotaExceeded = false
    retryableQuestion = nil
  }

  private func append(_ text: String, to id: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    messages[index].text += text
  }

  private func dropEmptyReply(_ id: UUID) {
    if let index = messages.firstIndex(where: { $0.id == id }), messages[index].text.isEmpty {
      messages.remove(at: index)
    }
  }

  private func fail(_ error: Error, question: String, replyId: UUID) {
    if let serviceError = error as? AIServiceError, serviceError.isQuotaExceeded {
      quotaExceeded = true
      remaining = 0
      // Let the user retry the same question after upgrading.
      if let last = messages.lastIndex(where: { $0.role == .user }) { messages.remove(at: last) }
    } else if case .contentBlocked? = error as? AIServiceError {
      retryableQuestion = nil
    } else {
      retryableQuestion = question
    }
    errorMessage = error.localizedDescription
  }

  /// Reports an AI answer for review (hosted mode only).
  func report(_ message: AgentMessage) async {
    await BackendClient.shared.report(storyId: context.storyId, kind: "agent", reason: message.visibleText)
  }
}
