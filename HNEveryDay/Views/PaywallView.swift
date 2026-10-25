//
//  PaywallView.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import StoreKit
import SwiftUI

/// Why the paywall was opened; only ever in response to something the user did.
enum PaywallReason: Equatable {
  case settings
  case quota(kind: String)
  case agent
}

struct PaywallView: View {
  var reason: PaywallReason = .settings

  @Environment(\.dismiss) private var dismiss
  private let store = StoreManager.shared

  @State private var selectedProductId: Product.ID?
  @State private var eligibleForTrial: Set<Product.ID> = []
  @State private var quotas: [String: RemoteConfig.TierQuotas] = [:]
  @State private var isPurchasing = false
  @State private var hudMessage: LocalizedStringKey?
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          header
          if let banner = reasonBanner {
            Text(banner)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.orange.opacity(0.1))
              .clipShape(RoundedRectangle(cornerRadius: 10))
          }
          comparison
          productOptions
          purchaseButton
          footer
        }
        .padding(16)
      }
      .background(Color(.systemGroupedBackground))
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
          }
          .accessibilityLabel(Text("Close"))
        }
      }
      .overlay(alignment: .top) {
        if let hudMessage {
          Text(hudMessage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(.top, 8)
        }
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .task { await load() }
  }

  // MARK: - Sections

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: "sparkles")
          .foregroundStyle(.orange)
        Text("HNEveryDay Pro")
          .font(.title2.weight(.bold))
          .tracking(AppTheme.Typography.titleTracking)
      }
      Text("More AI for reading Hacker News: more summaries, full-article translation and the Ask Agent companion.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var reasonBanner: LocalizedStringKey? {
    switch reason {
    case .settings:
      return nil
    case .agent:
      return "You've used today's free Agent questions."
    case .quota(let kind):
      return kind == "article"
        ? "You've used today's free article translations."
        : "You've used today's free summaries."
    }
  }

  private func quotaText(_ tier: String, _ key: KeyPath<RemoteConfig.TierQuotas, Int>, fallback: Int) -> String {
    String(quotas[tier]?[keyPath: key] ?? fallback)
  }

  private var comparison: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
      GridRow {
        Text("")
        Text("Free").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Text("Pro").font(.caption.weight(.semibold)).foregroundStyle(.orange)
      }
      Divider().gridCellColumns(3)
      comparisonRow("Title translation", free: Text("Unlimited"), pro: Text("Unlimited"))
      comparisonRow(
        "New summaries / day",
        free: Text(quotaText("free", \.summary, fallback: 10)),
        pro: Text(quotaText("pro", \.summary, fallback: 200)))
      comparisonRow(
        "Article translations / day",
        free: Text(quotaText("free", \.article, fallback: 3)),
        pro: Text(quotaText("pro", \.article, fallback: 50)))
      comparisonRow(
        "Ask Agent / day",
        free: Text(quotaText("free", \.agent, fallback: 3)),
        pro: Text("\(quotaText("pro", \.agent_soft, fallback: 50))+"))
    }
    .font(.subheadline)
    .padding(14)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private func comparisonRow(_ title: LocalizedStringKey, free: Text, pro: Text) -> some View {
    GridRow {
      Text(title)
      free.foregroundStyle(.secondary).fontDesign(.monospaced)
      pro.fontWeight(.semibold).fontDesign(.monospaced)
    }
  }

  @ViewBuilder
  private var productOptions: some View {
    if store.products.isEmpty {
      HStack {
        Spacer()
        if store.isLoadingProducts {
          ProgressView()
        } else {
          Text("Subscriptions are not available right now.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(.vertical, 20)
    } else {
      VStack(spacing: 10) {
        ForEach(store.products) { product in
          productCard(product)
        }
      }
    }
  }

  private func productCard(_ product: Product) -> some View {
    let isSelected = selectedProductId == product.id
    let isAnnual = product.subscription?.subscriptionPeriod.unit == .year
    return Button {
      selectedProductId = product.id
    } label: {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isSelected ? Color.orange : Color.secondary)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(product.displayName).font(.headline)
            if isAnnual {
              Text("Best Value")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
            }
          }
          if let trial = trialDescription(product) {
            Text(trial).font(.caption).foregroundStyle(.orange)
          }
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text(product.displayPrice).font(.headline).fontDesign(.monospaced)
          Text(periodLabel(product)).font(.caption2).foregroundStyle(.secondary)
        }
      }
      .padding(14)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(isSelected ? Color.orange : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.tactile)
  }

  private var purchaseButton: some View {
    VStack(spacing: 10) {
      Button {
        Task { await purchaseSelected() }
      } label: {
        HStack {
          Spacer()
          if isPurchasing {
            ProgressView().tint(.white)
          } else {
            Text(purchaseTitle).font(.headline)
          }
          Spacer()
        }
        .padding(.vertical, 14)
        .background(Color.orange)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.tactile)
      .disabled(isPurchasing || selectedProduct == nil)

      Button("Restore Purchases") {
        Task { await restore() }
      }
      .font(.subheadline)
      .disabled(isPurchasing)

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        "Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Your Apple ID is charged within 24 hours before renewal. A free trial converts to a paid subscription when it ends. Manage or cancel anytime in your Apple ID settings."
      )
      Text("AI content is generated automatically from articles and community discussion and may be inaccurate. For reference only.")
      HStack(spacing: 16) {
        Link("Terms of Use", destination: LegalLinks.termsOfUse)
        NavigationLink("Privacy Policy") {
          LegalLinks.privacyPolicyView
        }
      }
      .font(.caption.weight(.medium))
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
  }

  // MARK: - Helpers

  private var selectedProduct: Product? {
    store.products.first { $0.id == selectedProductId }
  }

  private var purchaseTitle: LocalizedStringKey {
    if let product = selectedProduct, trialDescription(product) != nil {
      return "Start Free Trial"
    }
    return "Subscribe"
  }

  private func periodLabel(_ product: Product) -> LocalizedStringKey {
    switch product.subscription?.subscriptionPeriod.unit {
    case .year: return "per year"
    case .month: return "per month"
    case .week: return "per week"
    default: return ""
    }
  }

  private func trialDescription(_ product: Product) -> LocalizedStringKey? {
    guard eligibleForTrial.contains(product.id),
      let offer = product.subscription?.introductoryOffer,
      offer.paymentMode == .freeTrial
    else { return nil }
    let period = offer.period
    switch period.unit {
    case .day: return "\(period.value)-day free trial"
    case .week: return "\(period.value * 7)-day free trial"
    case .month: return "\(period.value)-month free trial"
    default: return "Free trial"
    }
  }

  private func load() async {
    await store.loadProducts()
    if selectedProductId == nil {
      selectedProductId = (store.annualProduct ?? store.products.first)?.id
    }
    for product in store.products {
      if await product.subscription?.isEligibleForIntroOffer == true {
        eligibleForTrial.insert(product.id)
      }
    }
    quotas = await RemoteConfigStore.shared.current().quotas
  }

  private func purchaseSelected() async {
    guard let product = selectedProduct else { return }
    isPurchasing = true
    errorMessage = nil
    defer { isPurchasing = false }
    do {
      switch try await store.purchase(product) {
      case .purchased:
        AppTheme.Haptics.playSuccessNotification()
        await showHUD("Welcome to Pro!")
        dismiss()
      case .pending:
        await showHUD("Purchase pending approval.")
      case .cancelled:
        break
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func restore() async {
    isPurchasing = true
    errorMessage = nil
    await showHUD("Restoring purchases…", autoHide: false)
    defer { isPurchasing = false }
    do {
      try await store.restore()
      await showHUD(store.isPro ? "Purchases restored." : "No active subscription found.")
    } catch {
      withAnimation { hudMessage = nil }
      errorMessage = error.localizedDescription
    }
  }

  private func showHUD(_ message: LocalizedStringKey, autoHide: Bool = true) async {
    withAnimation(AppTheme.Spring.snappy) { hudMessage = message }
    guard autoHide else { return }
    try? await Task.sleep(for: .seconds(1.6))
    withAnimation(AppTheme.Spring.snappy) {
      if hudMessage == message { hudMessage = nil }
    }
  }
}

#Preview {
  PaywallView(reason: .quota(kind: "summary"))
}
