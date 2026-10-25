//
//  RemoteConfig.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import Foundation

/// Backend feature switches (kill switch, quotas, products). Cached for an hour; when it cannot be
/// fetched the app assumes everything is on and lets individual requests fail gracefully.
nonisolated struct RemoteConfig: Codable, Sendable {
  nonisolated struct Features: Codable, Sendable {
    var hosted_ai: Bool
    var summary: Bool
    var article_translation: Bool
    var agent: Bool
    var paywall: Bool
  }

  nonisolated struct TierQuotas: Codable, Sendable {
    var summary: Int
    var article: Int
    var agent: Int
    var agent_soft: Int
  }

  var features: Features
  var min_app_version: String
  var quotas: [String: TierQuotas]
  var products: [String]
  var notice: String?
  /// App Store storefronts (alpha-3) where the paywall is hidden. Optional so older cached configs still decode.
  var disabled_storefronts: [String]? = nil
  /// Model filing / registration line shown in Settings where regulation requires it.
  var model_disclosure: String? = nil

  static let fallback = RemoteConfig(
    features: Features(hosted_ai: true, summary: true, article_translation: true, agent: true, paywall: true),
    min_app_version: "0",
    quotas: [:],
    products: ["cn.corlin.hneveryday.pro.monthly", "cn.corlin.hneveryday.pro.annual"],
    notice: nil
  )
}

actor RemoteConfigStore {
  static let shared = RemoteConfigStore()

  private static let cacheKey = "remote_config_cache"
  private static let cacheDateKey = "remote_config_cache_date"
  private static let ttl: TimeInterval = 60 * 60

  private var config: RemoteConfig?
  private var fetchedAt: Date = .distantPast

  init() {
    if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
      let cached = try? JSONDecoder().decode(RemoteConfig.self, from: data)
    {
      config = cached
      fetchedAt = UserDefaults.standard.object(forKey: Self.cacheDateKey) as? Date ?? .distantPast
    }
  }

  func current() async -> RemoteConfig {
    if let config, Date().timeIntervalSince(fetchedAt) < Self.ttl {
      return config
    }
    do {
      let fresh: RemoteConfig = try await BackendClient.shared.get("/api/v1/config", authenticated: false)
      config = fresh
      fetchedAt = Date()
      if let data = try? JSONEncoder().encode(fresh) {
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        UserDefaults.standard.set(fetchedAt, forKey: Self.cacheDateKey)
      }
      return fresh
    } catch {
      return config ?? .fallback
    }
  }
}
