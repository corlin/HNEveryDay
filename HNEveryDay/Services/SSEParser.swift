//
//  SSEParser.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import Foundation

nonisolated struct SSEEvent: Equatable, Sendable {
  let event: String
  let data: String
}

/// Line-oriented Server-Sent Events parser. Works with `URLSession.AsyncBytes.lines`, which drops
/// blank lines, so every `data:` line is emitted immediately with the most recent `event:` name.
nonisolated struct SSEParser: Sendable {
  private var currentEvent = "message"

  mutating func consume(line rawLine: String) -> SSEEvent? {
    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if line.isEmpty {
      currentEvent = "message"
      return nil
    }
    if line.hasPrefix("event:") {
      currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
      return nil
    }
    if line.hasPrefix("data:") {
      let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
      let event = SSEEvent(event: currentEvent, data: data)
      currentEvent = "message"
      return event
    }
    return nil  // comments (":") and unsupported fields
  }
}

/// What the Agent stream yields to the UI.
nonisolated enum AgentStreamEvent: Equatable, Sendable {
  case meta(remaining: Int, limit: Int)
  case delta(String)
  case done
}

nonisolated enum AgentStreamDecoder {
  /// Decodes HNEveryDay backend events (meta / delta / done / error).
  static func hosted(_ event: SSEEvent) throws -> AgentStreamEvent? {
    let object = (try? JSONSerialization.jsonObject(with: Data(event.data.utf8))) as? [String: Any] ?? [:]
    switch event.event {
    case "meta":
      return .meta(remaining: object["remaining"] as? Int ?? 0, limit: object["limit"] as? Int ?? 0)
    case "delta":
      return (object["text"] as? String).map(AgentStreamEvent.delta)
    case "done":
      return .done
    case "error":
      throw AIServiceError.requestFailed(
        status: 502, message: object["message"] as? String ?? "The AI provider stopped responding")
    default:
      return nil
    }
  }

  /// Decodes OpenAI-compatible chat completion chunks (BYOK mode).
  static func openAI(_ event: SSEEvent) -> AgentStreamEvent? {
    if event.data == "[DONE]" { return .done }
    guard let object = (try? JSONSerialization.jsonObject(with: Data(event.data.utf8))) as? [String: Any],
      let choice = (object["choices"] as? [[String: Any]])?.first
    else { return nil }
    if let delta = choice["delta"] as? [String: Any], let text = delta["content"] as? String, !text.isEmpty {
      return .delta(text)
    }
    if choice["finish_reason"] as? String != nil { return .done }
    return nil
  }
}
