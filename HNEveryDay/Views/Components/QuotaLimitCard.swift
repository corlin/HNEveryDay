//
//  QuotaLimitCard.swift
//  HNEveryDay
//
//  Created by AI on 26/10/2026.
//

import SwiftUI

/// The one "daily allowance used up" message for summaries, article translation and the Agent:
/// what ran out, when it comes back, and the upgrade path.
struct QuotaLimitCard: View {
  /// "summary", "article" or "agent", as the backend reports it.
  let kind: String
  var resetAt: Date?
  var onUpgrade: () -> Void

  private let store = StoreManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label {
        Text("Daily limit reached")
          .font(.headline)
      } icon: {
        Image(systemName: "hourglass")
          .foregroundStyle(AppTheme.Palette.brand)
      }

      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if let resetAt {
        Text("Resets at \(resetAt.formatted(date: .omitted, time: .shortened))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if !store.isPro && store.isPaywallAvailable {
        Button(action: onUpgrade) {
          Label("Upgrade to HNEveryDay Pro", systemImage: "crown.fill")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.Palette.brand)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(radius: AppTheme.Radius.card, stroke: AppTheme.Palette.brand.opacity(0.24))
  }

  private var message: LocalizedStringKey {
    if store.isPro {
      return "You've reached today's Pro allowance. It resets tomorrow."
    }
    switch kind {
    case "article": return "You've used today's free article translations."
    case "agent": return "You've used today's free Agent questions."
    default: return "You've used today's free summaries."
    }
  }
}

#Preview {
  QuotaLimitCard(kind: "article", resetAt: Date().addingTimeInterval(3600)) {}
    .padding()
}
