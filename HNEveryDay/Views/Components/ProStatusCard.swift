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
      HStack(spacing: 10) {
        Image(systemName: store.isPro ? "checkmark.seal.fill" : "sparkles")
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text(store.isPro ? "HNEveryDay Pro" : "Free")
            .font(.headline)
          if let expiresAt = store.account?.expiresAt, store.isPro {
            Text("Renews or expires on \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
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
          Label("Upgrade to HNEveryDay Pro", systemImage: "arrow.up.circle.fill")
        }
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
      LabeledContent(title) {
        Text("\(quota.remaining) / \(quota.limit)")
          .fontDesign(.monospaced)
      }
    }
  }
}
