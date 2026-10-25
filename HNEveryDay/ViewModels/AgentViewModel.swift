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
  var text: String
}

/// Smart Chips shown before the first question; one tap asks a common question.
struct AgentChip: Identifiable, Hashable {
  let id: String
  let icon: String
  let title: String

  static let all: [AgentChip] = [
    AgentChip(id: "controversy", icon: "flame", title: String(localized: "What is the biggest disagreement in the comments?")),
    AgentChip(id: "code", icon: "chevron.left.forwardslash.chevron.right", title: String(localized: "Explain the core code or architecture")),
    AgentChip(id: "alternatives", icon: "arrow.left.arrow.right", title: String(localized: "Compare the alternatives mentioned")),
    AgentChip(id: "fit", icon: "scope", title: String(localized: "When does this fit, and when not?")),
  ]
}

nonisolated private struct AgentReportRequest: Encodable, Sendable {
  let story_id: Int
  let kind: String
  let reason: String
}

nonisolated private struct AgentReportResponse: Decodable, Sendable {
  let ok: Bool
}

@MainActor
@Observable
final class AgentViewModel {
  private(set) var messages: [AgentMessage] = []
  private(set) var isStreaming = false
  private(set) var remaining: Int?
  private(set) var limit: Int?
  var errorMessage: String?
  var quotaExceeded = false

  @ObservationIgnored private let context: AgentContext
  @ObservationIgnored private var streamTask: Task<Void, Never>?

  init(context: AgentContext) {
    self.context = context
  }

  var canSend: Bool { !isStreaming }

  func send(_ text: String) {
    let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty, !isStreaming else { return }

    errorMessage = nil
    quotaExceeded = false
    messages.append(AgentMessage(role: .user, text: question))
    let history = messages.map { AgentTurn(role: $0.role.rawValue, content: $0.text) }
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
    let _: AgentReportResponse? = try? await BackendClient.shared.post(
      "/api/v1/report",
      body: AgentReportRequest(story_id: context.storyId, kind: "agent", reason: String(message.text.prefix(1000)))
    )
  }
}
