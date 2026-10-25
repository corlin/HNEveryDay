//
//  BackendClient.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import Foundation

nonisolated enum BackendConfig {
  /// Deployed Cloudflare Worker (see backend/README.md). Can be overridden for testing
  /// with the "backend_base_url" user default.
  static let defaultBaseURL = "https://hnapi.caifu.social"

  static var baseURL: URL {
    let override = UserDefaults.standard.string(forKey: "backend_base_url") ?? ""
    return URL(string: override.isEmpty ? defaultBaseURL : override)!
  }

  static var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
  }
}

/// Thin JSON client for the HNEveryDay backend. Maps backend error envelopes to `AIServiceError`.
actor BackendClient {
  static let shared = BackendClient()

  nonisolated private struct ErrorEnvelope: Decodable, Sendable {
    nonisolated struct Body: Decodable, Sendable {
      let code: String
      let message: String
      let kind: String?
      let limit: Int?
      let reset_at: Double?
      let retry_after: Int?
    }
    let error: Body
  }

  private let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 30
    configuration.waitsForConnectivity = false
    return URLSession(configuration: configuration)
  }()

  /// - Parameters:
  ///   - timeout: Overrides the 30 s default for slow generations (e.g. full-article translation).
  ///   - retryOnNetworkError: Set to false for expensive, charged requests: a timeout usually means the
  ///     server is still working, and resending would start (and bill) a second generation.
  func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
    _ path: String,
    body: Body,
    authenticated: Bool = true,
    timeout: TimeInterval? = nil,
    retryOnNetworkError: Bool = true
  ) async throws -> Response {
    let data = try await send(
      path, method: "POST", body: try JSONEncoder().encode(body), authenticated: authenticated,
      timeout: timeout, retryOnNetworkError: retryOnNetworkError)
    return try JSONDecoder().decode(Response.self, from: data)
  }

  func get<Response: Decodable & Sendable>(_ path: String, authenticated: Bool = true) async throws -> Response {
    let data = try await send(path, method: "GET", body: nil, authenticated: authenticated)
    return try JSONDecoder().decode(Response.self, from: data)
  }

  /// Opens a streaming (SSE) POST request and returns the byte stream once the status is 200.
  func stream<Body: Encodable & Sendable>(_ path: String, body: Body) async throws -> URLSession.AsyncBytes {
    let encoded = try JSONEncoder().encode(body)
    for attempt in 0..<2 {
      let request = try await makeRequest(path, method: "POST", body: encoded, authenticated: true)
      let (bytes, response) = try await session.bytes(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      if status == 200 { return bytes }
      var data = Data()
      for try await byte in bytes { data.append(byte) }
      if status == 401 && attempt == 0 {
        await DeviceAuth.shared.invalidate()
        continue
      }
      throw Self.mapError(status: status, data: data)
    }
    throw AIServiceError.requestFailed(status: 401, message: "Unauthorized")
  }

  private func makeRequest(_ path: String, method: String, body: Data?, authenticated: Bool) async throws -> URLRequest {
    var request = URLRequest(url: BackendConfig.baseURL.appending(path: path))
    request.httpMethod = method
    request.setValue(BackendConfig.appVersion, forHTTPHeaderField: "X-App-Version")
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if authenticated {
      let token = try await DeviceAuth.shared.validToken()
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  private func send(
    _ path: String,
    method: String,
    body: Data?,
    authenticated: Bool,
    timeout: TimeInterval? = nil,
    retryOnNetworkError: Bool = true
  ) async throws -> Data {
    var lastError: Error = AIServiceError.requestFailed(status: 0, message: "Request failed")
    for attempt in 0..<3 {
      var request = try await makeRequest(path, method: method, body: body, authenticated: authenticated)
      if let timeout { request.timeoutInterval = timeout }
      do {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }
        if status == 401 && authenticated && attempt == 0 {
          await DeviceAuth.shared.invalidate()
          continue
        }
        let error = Self.mapError(status: status, data: data)
        // Only transient upstream errors are retried; quota and availability answers are final.
        guard status == 502 || status == 504, attempt < 2 else { throw error }
        lastError = error
      } catch let error as AIServiceError {
        throw error
      } catch {
        if Task.isCancelled { throw error }
        lastError = AIServiceError.requestFailed(status: 0, message: error.localizedDescription)
        if attempt == 2 || !retryOnNetworkError { break }
      }
      try await Task.sleep(nanoseconds: UInt64(500_000_000 * (attempt + 1)))
    }
    throw lastError
  }

  static func mapError(status: Int, data: Data) -> AIServiceError {
    guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
      return .requestFailed(status: status, message: "Server error (\(status))")
    }
    let body = envelope.error
    switch body.code {
    case "quota_exceeded":
      return .quotaExceeded(
        kind: body.kind ?? "",
        limit: body.limit ?? 0,
        resetAt: body.reset_at.map { Date(timeIntervalSince1970: $0 / 1000) }
      )
    case "slow_down":
      return .slowDown(retryAfter: body.retry_after ?? 60)
    case "content_blocked":
      return .contentBlocked
    case "feature_disabled", "budget_exhausted", "region_unavailable", "upgrade_required":
      return .unavailable(code: body.code, message: body.message)
    default:
      return .requestFailed(status: status, message: body.message)
    }
  }
}

nonisolated private struct ReportRequest: Encodable, Sendable {
  let story_id: Int
  let kind: String
  let reason: String
}

nonisolated private struct ReportResponse: Decodable, Sendable {
  let ok: Bool
}

extension BackendClient {
  /// Flags hosted AI output ("title", "summary", "article", "agent") for moderation. Best effort.
  func report(storyId: Int, kind: String, reason: String) async {
    let _: ReportResponse? = try? await post(
      "/api/v1/report",
      body: ReportRequest(story_id: storyId, kind: kind, reason: String(reason.prefix(1000)))
    )
  }
}
