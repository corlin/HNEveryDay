//
//  DeviceAuth.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import CryptoKit
import DeviceCheck
import Foundation

/// Obtains short-lived device tokens from the backend.
/// Devices that support App Attest prove they run a genuine copy of the app; others
/// (simulator, unsupported hardware) fall back to an anonymous token with smaller quotas.
actor DeviceAuth {
  static let shared = DeviceAuth()

  private enum Keys {
    static let keyId = "app_attest_key_id"
    static let anonymousId = "anonymous_device_id"
    static let token = "device_token"
    static let tokenExpiry = "device_token_expiry"
  }

  nonisolated private struct TokenResponse: Decodable, Sendable {
    let device_id: String
    let token: String
    let expires_at: TimeInterval
    let attested: Bool
  }

  nonisolated private struct ChallengeResponse: Decodable, Sendable {
    let challenge: String
  }

  private var token: String?
  private var expiresAt: Date = .distantPast
  private var refreshTask: Task<String, Error>?

  init() {
    token = KeychainHelper.read(key: Keys.token)
    if let stored = KeychainHelper.read(key: Keys.tokenExpiry), let seconds = TimeInterval(stored) {
      expiresAt = Date(timeIntervalSince1970: seconds)
    }
  }

  /// A token valid for at least five more minutes, refreshing it if needed.
  func validToken() async throws -> String {
    if let token, expiresAt.timeIntervalSinceNow > 300 {
      return token
    }
    if let refreshTask {
      return try await refreshTask.value
    }
    let task = Task { try await self.refresh() }
    refreshTask = task
    defer { refreshTask = nil }
    return try await task.value
  }

  /// Drops the cached token, e.g. after the backend answered 401.
  func invalidate() {
    token = nil
    expiresAt = .distantPast
    KeychainHelper.delete(key: Keys.token)
    KeychainHelper.delete(key: Keys.tokenExpiry)
  }

  private func refresh() async throws -> String {
    let response: TokenResponse
    if DCAppAttestService.shared.isSupported {
      do {
        response = try await attestedToken()
      } catch {
        print("⚠️ App Attest failed, using an anonymous token: \(error)")
        response = try await anonymousToken()
      }
    } else {
      response = try await anonymousToken()
    }
    store(response)
    return response.token
  }

  private func store(_ response: TokenResponse) {
    token = response.token
    expiresAt = Date(timeIntervalSince1970: response.expires_at)
    _ = KeychainHelper.save(key: Keys.token, value: response.token)
    _ = KeychainHelper.save(key: Keys.tokenExpiry, value: String(response.expires_at))
  }

  private func attestedToken() async throws -> TokenResponse {
    let service = DCAppAttestService.shared

    // Renew with an assertion when this device already attested a key.
    if let keyId = KeychainHelper.read(key: Keys.keyId) {
      do {
        let challenge = try await fetchChallenge()
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let assertion = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
        return try await BackendClient.shared.post(
          "/api/v1/auth/assert",
          body: ["key_id": keyId, "assertion": assertion.base64EncodedString(), "challenge": challenge],
          authenticated: false
        )
      } catch {
        // The key may have been invalidated (reinstall, OS update) or the server forgot it; attest a new one.
        print("⚠️ App Attest assertion failed, attesting a new key: \(error)")
        KeychainHelper.delete(key: Keys.keyId)
      }
    }

    let keyId = try await service.generateKey()
    let challenge = try await fetchChallenge()
    let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
    let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
    let response: TokenResponse = try await BackendClient.shared.post(
      "/api/v1/auth/attest",
      body: ["key_id": keyId, "attestation": attestation.base64EncodedString(), "challenge": challenge],
      authenticated: false
    )
    _ = KeychainHelper.save(key: Keys.keyId, value: keyId)
    return response
  }

  private func anonymousToken() async throws -> TokenResponse {
    var body: [String: String] = [:]
    if let existing = KeychainHelper.read(key: Keys.anonymousId) {
      body["device_id"] = existing
    }
    let response: TokenResponse = try await BackendClient.shared.post(
      "/api/v1/auth/anonymous", body: body, authenticated: false)
    _ = KeychainHelper.save(key: Keys.anonymousId, value: response.device_id)
    return response
  }

  private func fetchChallenge() async throws -> String {
    let response: ChallengeResponse = try await BackendClient.shared.post(
      "/api/v1/auth/challenge", body: [String: String](), authenticated: false)
    return response.challenge
  }
}
