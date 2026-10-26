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
        VStack(alignment: .leading, spacing: 18) {
          header
          if let banner = reasonBanner {
            Label {
              Text(banner)
            } icon: {
              Image(systemName: "hourglass")
                .foregroundStyle(AppTheme.Palette.brand)
            }
            .font(.footnote)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Palette.brandFill)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row))
          }
          benefits
          comparison
          productOptions
          footer
        }
        .padding(16)
      }
      .background(Color(.systemGroupedBackground))
      // The purchase button stays on screen on small phones instead of scrolling below the fold.
      .safeAreaInset(edge: .bottom, spacing: 0) {
        purchaseBar
      }
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
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: "crown.fill")
        .font(.largeTitle)
        .foregroundStyle(AppTheme.Palette.brand)
        .accessibilityHidden(true)
      Text("HNEveryDay Pro")
        .font(.largeTitle.weight(.bold))
        .tracking(AppTheme.Typography.titleTracking)
      Text("More AI for reading Hacker News: more summaries, full-article translation and the Ask Agent companion.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var benefits: some View {
    VStack(alignment: .leading, spacing: 14) {
      benefitRow(
        icon: "list.bullet.clipboard",
        title: "Summaries for every story you open",
        detail: "Article and discussion boiled down to the key points and disagreements.")
      benefitRow(
        icon: "translate",
        title: "Read full articles in your language",
        detail: "Whole-article translation that keeps code, names and links intact.")
      benefitRow(
        icon: "bubble.left.and.text.bubble.right",
        title: "Many more Ask Agent questions",
        detail: "Follow-up questions about the article and the thread, answered in context.")
    }
  }

  private func benefitRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(AppTheme.Palette.brand)
        .frame(width: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
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
    VStack(alignment: .leading, spacing: 8) {
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
        GridRow {
          Text("Per day").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          Text("Free").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
          Text("Pro").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.Palette.brand)
            .gridColumnAlignment(.trailing)
        }
        Divider().gridCellColumns(3)
        comparisonRow(
          "New summaries",
          free: quotaText("free", \.summary, fallback: 10),
          pro: quotaText("pro", \.summary, fallback: 200))
        comparisonRow(
          "Article translations",
          free: quotaText("free", \.article, fallback: 3),
          pro: quotaText("pro", \.article, fallback: 50))
        comparisonRow(
          "Ask Agent questions",
          free: quotaText("free", \.agent, fallback: 3),
          pro: "\(quotaText("pro", \.agent_soft, fallback: 50))*")
      }
      .font(.subheadline)

      Text("Title translation is unlimited on both. * Ask Agent on Pro is fair use; heavy use may be slowed down.")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .cardSurface(radius: AppTheme.Radius.card)
  }

  private func comparisonRow(_ title: LocalizedStringKey, free: String, pro: String) -> some View {
    GridRow {
      Text(title)
      Text(verbatim: free).foregroundStyle(.secondary).monospacedDigit()
      Text(verbatim: pro).fontWeight(.semibold).monospacedDigit()
    }
  }

  @ViewBuilder
  private var productOptions: some View {
    if store.products.isEmpty {
      VStack(spacing: 10) {
        if store.isLoadingProducts {
          ProgressView()
        } else {
          Text("Subscriptions are not available right now.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Button("Try Again") {
            Task { await load() }
          }
          .buttonStyle(.bordered)
          .tint(AppTheme.Palette.brand)
        }
      }
      .frame(maxWidth: .infinity)
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
          .foregroundStyle(isSelected ? AppTheme.Palette.brand : Color.secondary)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(product.displayName).font(.headline)
            if isAnnual {
              Text(savingsBadge(for: product) ?? "Best Value")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.Palette.brandFill)
                .foregroundStyle(AppTheme.Palette.brand)
                .clipShape(Capsule())
            }
          }
          if let trial = trialDescription(product) {
            Text(trial).font(.caption).foregroundStyle(AppTheme.Palette.brand)
          }
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text(product.displayPrice).font(.headline).monospacedDigit()
          Text(periodLabel(product)).font(.caption2).foregroundStyle(.secondary)
          if isAnnual {
            Text("\((product.price / 12).formatted(product.priceFormatStyle)) / month")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
        }
      }
      .padding(14)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
      .overlay(
        RoundedRectangle(cornerRadius: AppTheme.Radius.card)
          .strokeBorder(
            isSelected ? AppTheme.Palette.brand : AppTheme.Palette.hairline,
            lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.tactile)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var purchaseBar: some View {
    VStack(spacing: 8) {
      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }

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
        .background(AppTheme.Palette.brand)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
      }
      .buttonStyle(.tactile)
      .disabled(isPurchasing || selectedProduct == nil)
      .opacity(selectedProduct == nil ? 0.5 : 1)

      Button("Restore Purchases") {
        Task { await restore() }
      }
      .font(.footnote)
      .disabled(isPurchasing)
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
    .padding(.bottom, 6)
    .background(.bar)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(AppTheme.Palette.hairline)
        .frame(height: 1)
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

  /// "Save 40%" against twelve months of the monthly plan, when both are on sale.
  private func savingsBadge(for annual: Product) -> LocalizedStringKey? {
    guard let monthly = store.monthlyProduct, monthly.price > 0 else { return nil }
    let ratio = annual.price / (monthly.price * 12)
    let percent = NSDecimalNumber(decimal: (1 - ratio) * 100).intValue
    guard percent >= 5 else { return nil }
    return "Save \(percent)%"
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
      errorMessage = Self.friendlyMessage(for: error)
    }
  }

  /// StoreKit's own errors are terse and English-only; say what happened and what to do.
  private static func friendlyMessage(for error: Error) -> String {
    if let storeError = error as? StoreKitError {
      switch storeError {
      case .networkError:
        return String(localized: "Couldn't reach the App Store. Check your connection and try again.")
      case .notAvailableInStorefront:
        return String(localized: "This subscription isn't available in your App Store region.")
      case .notEntitled:
        return String(localized: "No active subscription was found for this Apple ID.")
      default:
        break
      }
    }
    if let purchaseError = error as? Product.PurchaseError, case .purchaseNotAllowed = purchaseError {
      return String(localized: "Purchases are turned off on this device (Screen Time or device management).")
    }
    return String(localized: "The purchase couldn't be completed. Please try again.")
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
      errorMessage = Self.friendlyMessage(for: error)
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
