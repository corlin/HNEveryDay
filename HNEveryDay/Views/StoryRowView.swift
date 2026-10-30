//
//  StoryRowView.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import SwiftData
import SwiftUI

struct StoryRowView: View {
  let item: HNItem
  let isRead: Bool
  let isSaved: Bool
  var translatedTitle: String?
  var isTranslatingTitle: Bool = false

  @ScaledMetric(relativeTo: .subheadline) private var scoreColumnWidth: CGFloat = 38

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      scoreColumn
      contentColumn
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 9)
    .background(rowBackground, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row))
    .overlay(alignment: .leading) {
      if isSaved {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(AppTheme.Palette.brand)
          .frame(width: 3)
          .padding(.vertical, 10)
      }
    }
    .overlay(rowStroke)
    .contentShape(Rectangle())  // Make entire row tappable
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(accessibilityDescription))
  }

  private var scoreColumn: some View {
    VStack(alignment: .trailing, spacing: 1) {
      Text(scoreText)
        .font(.system(.subheadline, design: .monospaced, weight: .bold))
        .foregroundStyle(isRead ? Color.secondary : AppTheme.Palette.brand)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(width: scoreColumnWidth, alignment: .trailing)
    .padding(.top, 2)
  }

  private var contentColumn: some View {
    VStack(alignment: .leading, spacing: 7) {
      titleBlock
      metadataRow
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var titleBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        if translatedTitle != nil {
          Image(systemName: "sparkles")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.Palette.brand)
            .accessibilityLabel(Text("AI translation", comment: "Explicit label on machine-translated articles"))
        }

        Text(displayTitle)
          .font(.subheadline.weight(isRead ? .regular : .semibold))
          .tracking(AppTheme.Typography.titleTracking)
          .foregroundStyle(isRead ? .secondary : .primary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let originalTitle {
        Text(originalTitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      } else if isTranslatingTitle {
        HStack(spacing: 5) {
          ProgressView()
            .controlSize(.mini)
          Text("Translating title...")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var metadataRow: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        timeText
        domainChip
        authorText
        commentCount
      }

      HStack(spacing: 8) {
        timeText
        domainChip
        commentCount
      }

      HStack(spacing: 8) {
        timeText
        commentCount
      }
    }
    .font(.caption2.weight(.medium))
    .tracking(AppTheme.Typography.metadataTracking)
    .foregroundStyle(.secondary)
  }

  private var timeText: some View {
    Text(item.time.shortTimeAgo)
      .fontDesign(.monospaced)
      .foregroundStyle(.secondary)
      .lineLimit(1)
  }

  @ViewBuilder
  private var domainChip: some View {
    if let domain = item.url?.hostDomain {
      HStack(spacing: 0) {
        SiteIcon(domain: domain)
        Text(domain)
          .lineLimit(1)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.primary.opacity(0.055))
      .clipShape(RoundedRectangle(cornerRadius: 5))
    }
  }

  private var authorText: some View {
    Text("by \(item.by ?? "unknown")")
      .lineLimit(1)
  }

  private var commentCount: some View {
    HStack(spacing: 3) {
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.caption2.weight(.semibold))
      Text("\(item.descendants ?? 0)")
        .fontDesign(.monospaced)
    }
    .lineLimit(1)
  }

  private var rowBackground: some ShapeStyle {
    Color(.secondarySystemGroupedBackground).opacity(isRead ? 0.58 : 0.92)
  }

  private var rowStroke: some View {
    RoundedRectangle(cornerRadius: AppTheme.Radius.row)
      .strokeBorder(
        AppTheme.Palette.hairline,
        lineWidth: 1
      )
  }

  private var accessibilityDescription: String {
    var parts = [displayTitle]
    if let score = item.score { parts.append(String(localized: "\(score) points")) }
    parts.append(String(localized: "\(item.descendants ?? 0) comments"))
    if let domain = item.url?.hostDomain { parts.append(domain) }
    parts.append(item.time.shortTimeAgo)
    if isSaved { parts.append(String(localized: "Saved")) }
    if isRead { parts.append(String(localized: "Read")) }
    return parts.joined(separator: ", ")
  }

  private var scoreText: String {
    guard let score = item.score else { return "--" }
    return "\(score)"
  }

  private var displayTitle: String {
    translatedTitle?.isEmpty == false ? translatedTitle! : item.title ?? "Untitled"
  }

  private var originalTitle: String? {
    guard let translatedTitle, !translatedTitle.isEmpty else { return nil }
    guard translatedTitle != item.title else { return nil }
    return item.title
  }
}

#Preview {
  StoryRowView(
    item: HNItem(
      id: 1,
      type: .story,
      by: "geeker_01",
      time: Date(),
      text: nil,
      url: "https://github.com/apple/swift",
      score: 42,
      title: "Swift 6 Release Notes and Migration Guide for advanced developers",
      descendants: 12,
      kids: [],
      parent: nil,
      deleted: nil,
      dead: nil
    ),
    isRead: false,
    isSaved: true
  )
  .padding()
}

/// The site's icon beside its domain. Takes no space until it loads, so sites without an icon
/// (or a failed request) look exactly like before.
private struct SiteIcon: View {
  let domain: String
  @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 12

  var body: some View {
    AsyncImage(url: BackendConfig.iconURL(domain: domain)) { phase in
      if let image = phase.image {
        image
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .frame(width: size, height: size)
          .clipShape(RoundedRectangle(cornerRadius: 2.5))
          .padding(.trailing, 4)
      }
    }
    .accessibilityHidden(true)
  }
}
