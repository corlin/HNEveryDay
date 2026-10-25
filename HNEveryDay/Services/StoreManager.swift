//
//  StoreManager.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import Foundation
import Observation
import StoreKit

nonisolated struct ProQuota: Decodable, Sendable, Equatable {
  let limit: Int
  let used: Int
  let remaining: Int
}

/// GET /api/v1/me
nonisolated struct AccountStatus: Decodable, Sendable {
  nonisolated struct Subscription: Decodable, Sendable {
    let product_id: String
    let status: String
    let expires_at: Double?
    let auto_renew: Bool?
  }

  let tier: String
  let subscription: Subscription?
  let quotas: [String: ProQuota]

  var isPro: Bool { tier == "pro" }
  var expiresAt: Date? { subscription?.expires_at.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

nonisolated private struct VerifyRequest: Encodable, Sendable {
  let signed_transaction: String
}

nonisolated private struct VerifyResponse: Decodable, Sendable {
  let tier: String
}

/// StoreKit 2 purchases plus the backend's view of the account. The UI shows Pro as soon as
/// StoreKit has a verified entitlement; quotas are always decided by the backend.
@MainActor
@Observable
final class StoreManager {
  static let shared = StoreManager()

  enum PurchaseOutcome {
    case purchased
    case pending
    case cancelled
  }

  private(set) var products: [Product] = []
  private(set) var hasActiveEntitlement = false
  private(set) var account: AccountStatus?
  private(set) var isLoadingProducts = false
  /// Pro is not offered where hosted AI is unavailable (see RemoteConfig.disabled_countries).
  private(set) var isPaywallAvailable = true

  @ObservationIgnored private var updatesTask: Task<Void, Never>?
  private static let appAccountTokenKey = "app_account_token"

  var isPro: Bool { hasActiveEntitlement || account?.isPro == true }

  var annualProduct: Product? { products.first { $0.subscription?.subscriptionPeriod.unit == .year } }
  var monthlyProduct: Product? { products.first { $0.subscription?.subscriptionPeriod.unit == .month } }

  /// Stable anonymous id attached to purchases so the backend can tie transactions to this install.
  var appAccountToken: UUID {
    if let stored = KeychainHelper.read(key: Self.appAccountTokenKey), let uuid = UUID(uuidString: stored) {
      return uuid
    }
    let uuid = UUID()
    _ = KeychainHelper.save(key: Self.appAccountTokenKey, value: uuid.uuidString)
    return uuid
  }

  /// Call once at launch.
  func start() async {
    if updatesTask == nil {
      updatesTask = Task { [weak self] in
        for await update in Transaction.updates {
          await self?.handle(update)
        }
      }
    }
    await refreshAvailability()
    await refreshEntitlements()
  }

  func refreshAvailability() async {
    let config = await RemoteConfigStore.shared.current()
    let storefront = await Storefront.current?.countryCode
    isPaywallAvailable = config.features.paywall && config.features.hosted_ai && storefront != "CHN"
  }

  func loadProducts() async {
    guard products.isEmpty, !isLoadingProducts else { return }
    isLoadingProducts = true
    defer { isLoadingProducts = false }
    let ids = await RemoteConfigStore.shared.current().products
    do {
      products = try await Product.products(for: ids).sorted { $0.price > $1.price }
    } catch {
      print("⚠️ Failed to load products: \(error)")
    }
  }

  func purchase(_ product: Product) async throws -> PurchaseOutcome {
    let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
    switch result {
    case .success(let verification):
      await handle(verification)
      return .purchased
    case .pending:
      return .pending
    case .userCancelled:
      return .cancelled
    @unknown default:
      return .cancelled
    }
  }

  /// "Restore Purchases": syncs with the App Store, then re-sends entitlements to the backend.
  func restore() async throws {
    try await AppStore.sync()
    await refreshEntitlements()
  }

  /// Re-reads current entitlements, syncs them to the backend, and refreshes quotas.
  func refreshEntitlements() async {
    let active = await activeEntitlements()
    for result in active {
      await sync(result)
    }
    hasActiveEntitlement = !active.isEmpty
    await refreshAccount()
  }

  private func activeEntitlements() async -> [VerificationResult<Transaction>] {
    var results: [VerificationResult<Transaction>] = []
    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result, transaction.productType == .autoRenewable,
        transaction.revocationDate == nil
      else { continue }
      results.append(result)
    }
    return results
  }

  func refreshAccount() async {
    guard AIMode.current == .hosted else { return }
    do {
      account = try await BackendClient.shared.get("/api/v1/me")
    } catch {
      print("⚠️ Failed to load account status: \(error)")
    }
  }

  private func handle(_ result: VerificationResult<Transaction>) async {
    guard case .verified(let transaction) = result else { return }
    await sync(result)
    await transaction.finish()
    hasActiveEntitlement = !(await activeEntitlements()).isEmpty
    await refreshAccount()
  }

  /// Sends Apple's signed transaction to the backend, which verifies it independently.
  private func sync(_ result: VerificationResult<Transaction>) async {
    do {
      let _: VerifyResponse = try await BackendClient.shared.post(
        "/api/v1/subscription/verify",
        body: VerifyRequest(signed_transaction: result.jwsRepresentation)
      )
    } catch {
      print("⚠️ Failed to sync subscription: \(error)")
    }
  }
}
