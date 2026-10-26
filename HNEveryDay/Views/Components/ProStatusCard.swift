//
//  ProStatusCard.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import StoreKit
import SwiftUI

/// Settings section showing the Pro tier, renewal date and today's hosted AI allowance.
struct ProStatusSection: View {
  private let store = StoreManager.shared
  @State private var showPaywall = false
  @State private var showManageSubscriptions = false

  var body: some View {
    Section {
      HStack(spacing: 12) {
        Image(systemName: store.isPro ? "crown.fill" : "person.crop.circle")
          .font(.title2)
          .foregroundStyle(store.isPro ? AppTheme.Palette.brand : Color.secondary)
          .frame(width: 32)
        VStack(alignment: .leading, spacing: 2) {
          Text(store.isPro ? "HNEveryDay Pro" : "Free Plan")
            .font(.headline)
          if let expiresAt = store.account?.expiresAt, store.isPro {
            Text("Renews or expires on \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else if !store.isPro {
            Text("Daily AI allowance, resets every day")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      if let quotas = store.account?.quotas, AIMode.current == .hosted {
        quotaRow("Summaries today", quotas["summary"])
        quotaRow("Article translations today", quotas["article"])
        quotaRow("Agent questions today", quotas["agent"])
      }

      if store.isPro {
        Button("Manage Subscription") { showManageSubscriptions = true }
      } else if store.isPaywallAvailable {
        Button {
          showPaywall = true
        } label: {
          HStack {
            Label("Upgrade to HNEveryDay Pro", systemImage: "crown.fill")
              .font(.body.weight(.semibold))
            Spacer()
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
        }
        .foregroundStyle(AppTheme.Palette.brand)
      }
    } header: {
      Text("Membership", comment: "Section header")
    }
    .sheet(isPresented: $showPaywall) {
      PaywallView(reason: .settings)
    }
    .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
    .task {
      await store.refreshAvailability()
      await store.refreshAccount()
    }
  }

  @ViewBuilder
  private func quotaRow(_ title: LocalizedStringKey, _ quota: ProQuota?) -> some View {
    if let quota {
      VStack(alignment: .leading, spacing: 6) {
        LabeledContent(title) {
          Text("\(quota.remaining) / \(quota.limit)")
            .monospacedDigit()
        }
        ProgressView(value: Double(quota.remaining), total: Double(max(quota.limit, 1)))
          .tint(quota.remaining == 0 ? Color.red : AppTheme.Palette.brand)
          .accessibilityHidden(true)
      }
    }
  }
}
