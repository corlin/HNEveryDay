//
//  AgentViewModel.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import Foundation
import Observation

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
  private(set) var suggestions: [AgentChip] = []
  private(set) var isLoadingSuggestions = false
  var errorMessage: String?
  var quotaExceeded = false

  @ObservationIgnored private let context: AgentContext
  @ObservationIgnored private var streamTask: Task<Void, Never>?

  init(context: AgentContext) {
    self.context = context
  }

  var canSend: Bool { !isStreaming }

  /// Follow-up chips under the latest finished answer.
  var followUpChips: [AgentChip] {
    guard !isStreaming, let last = messages.last, last.role == .assistant else { return [] }
    return last.followUps.map { AgentChip(icon: "arrow.turn.down.right", title: $0) }
  }

  /// Loads story-specific starter questions; falls back to generic ones when generation fails.
  func loadSuggestions() async {
    guard suggestions.isEmpty, !isLoadingSuggestions else { return }
    isLoadingSuggestions = true
    defer { isLoadingSuggestions = false }
    let questions = (try? await AgentService.questions(context: context)) ?? []
    suggestions = questions.isEmpty ? AgentChip.fallback : questions.map(AgentChip.init)
  }

  func send(_ text: String) {
    let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty, !isStreaming else { return }

    errorMessage = nil
    quotaExceeded = false
    messages.append(AgentMessage(role: .user, text: question))
    let history = messages.map { AgentTurn(role: $0.role.rawValue, content: $0.visibleText) }
    messages.append(AgentMessage(role: .assistant, text: ""))
    let replyId = messages[messages.count - 1].id
    isStreaming = true
    AppTheme.Haptics.playLightImpact()

    streamTask = Task { [context] in
      do {
        for try await event in AgentService.stream(context: context, history: history) {
          switch event {
          case .meta(let remaining, let limit):
            self.remaining = remaining
            self.limit = limit
          case .delta(let text):
            self.append(text, to: replyId)
          case .done:
            break
          }
        }
      } catch is CancellationError {
        // Stopped by the user; keep what was produced.
      } catch {
        if (error as NSError).code != NSURLErrorCancelled {
          self.fail(error, replyId: replyId)
        }
      }
      self.isStreaming = false
      self.dropEmptyReply(replyId)
    }
  }

  /// Stops generation; the partial answer stays. The turn still counts toward today's allowance.
  func stop() {
    streamTask?.cancel()
    streamTask = nil
    isStreaming = false
  }

  func reset() {
    stop()
    messages.removeAll()
    errorMessage = nil
    quotaExceeded = false
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

  private func fail(_ error: Error, replyId: UUID) {
    if let serviceError = error as? AIServiceError, serviceError.isQuotaExceeded {
      quotaExceeded = true
      remaining = 0
      // Let the user retry the same question after upgrading.
      if let last = messages.lastIndex(where: { $0.role == .user }) { messages.remove(at: last) }
    }
    errorMessage = error.localizedDescription
  }

  /// Reports an AI answer for review (hosted mode only).
  func report(_ message: AgentMessage) async {
    await BackendClient.shared.report(storyId: context.storyId, kind: "agent", reason: message.visibleText)
  }
}
