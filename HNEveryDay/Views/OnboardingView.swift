//
//  OnboardingView.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import SwiftUI

struct OnboardingView: View {
  @Binding var hasCompletedOnboarding: Bool
  @AppStorage("translation_mode") private var translationMode: String = TranslationMode.defaultRawValue

  private var readingLanguage: String {
    ReadingLanguage.resolvedCode(preferredLanguage: ReadingLanguage.systemCode)
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 0) {
          // MARK: - Logo & Title
          VStack(spacing: 14) {
            Image(systemName: "newspaper.fill")
              .font(.system(.largeTitle, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 84, height: 84)
              .background(AppTheme.Palette.brand, in: RoundedRectangle(cornerRadius: 20))
              .accessibilityHidden(true)

            Text("HNEveryDay", comment: "App name")
              .font(.system(.largeTitle, design: .rounded, weight: .bold))

            Text("Hacker News, read faster and in your language", comment: "App subtitle")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .padding(.top, 56)
          .padding(.bottom, 40)

          // MARK: - Features
          VStack(alignment: .leading, spacing: 22) {
            FeatureRow(
              icon: "list.bullet.clipboard",
              color: AppTheme.Palette.brand,
              title: String(localized: "AI Summaries", comment: "Feature title"),
              description: String(
                localized: "Get the gist of article + discussion in seconds.", comment: "Feature desc")
            )

            FeatureRow(
              icon: "translate",
              color: .blue,
              title: String(localized: "Translation", comment: "Feature title"),
              description: String(
                localized: "Titles and full articles in your language, with code and names left intact.",
                comment: "Feature desc")
            )

            FeatureRow(
              icon: "bubble.left.and.text.bubble.right",
              color: .purple,
              title: String(localized: "Ask Agent", comment: "Feature title"),
              description: String(
                localized: "Ask follow-up questions about the article and the thread.", comment: "Feature desc")
            )

            FeatureRow(
              icon: "doc.plaintext",
              color: .green,
              title: String(localized: "Smart Reader", comment: "Feature title"),
              description: String(
                localized: "Ad-free, distraction-free article parsing.", comment: "Feature desc")
            )
          }
          .padding(.horizontal, 32)

          // MARK: - Translation preference
          if readingLanguage != "en" {
            Toggle(isOn: translationBinding) {
              VStack(alignment: .leading, spacing: 2) {
                Text("Translate into \(ReadingLanguage.shortLabel(for: readingLanguage))")
                  .font(.subheadline.weight(.semibold))
                Text("You can change this anytime in Settings.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .tint(AppTheme.Palette.brand)
            .padding(14)
            .cardSurface(radius: AppTheme.Radius.card)
            .padding(.horizontal, 24)
            .padding(.top, 32)
          }
        }
        .frame(maxWidth: .infinity)
      }

      // MARK: - Get Started
      Button {
        withAnimation {
          hasCompletedOnboarding = true
        }
      } label: {
        Text("Get Started", comment: "Button")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding()
          .background(AppTheme.Palette.brand)
          .foregroundStyle(.white)
          .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
      }
      .buttonStyle(.tactile)
      .padding(.horizontal, 32)
      .padding(.top, 12)
      .padding(.bottom, 24)
    }
    .background(Color(.systemBackground))
  }

  private var translationBinding: Binding<Bool> {
    Binding(
      get: { translationMode != TranslationMode.off.rawValue },
      set: { translationMode = ($0 ? TranslationMode.onDemand : TranslationMode.off).rawValue }
    )
  }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
  let icon: String
  let color: Color
  let title: String
  let description: String

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(color)
        .frame(width: 32)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  OnboardingView(hasCompletedOnboarding: .constant(false))
}
