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

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      scoreColumn
      contentColumn
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 9)
    .background(rowBackground)
    .overlay(alignment: .leading) {
      if isSaved {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(Color.orange)
          .frame(width: 3)
          .padding(.vertical, 10)
      }
    }
    .overlay(rowStroke)
    .contentShape(Rectangle())  // Make entire row tappable
  }

  private var scoreColumn: some View {
    VStack(alignment: .trailing, spacing: 1) {
      Text(scoreText)
        .font(.system(size: 14, weight: .bold, design: .monospaced))
        .foregroundStyle(isRead ? Color.secondary : Color.orange)
        .lineLimit(1)
        .minimumScaleFactor(0.72)

      Text("pts")
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(width: 38, alignment: .trailing)
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.orange)
            .accessibilityLabel(Text("AI translation", comment: "Explicit label on machine-translated articles"))
        }

        Text(displayTitle)
          .font(.system(size: 15, weight: isRead ? .regular : .semibold))
          .tracking(AppTheme.Typography.titleTracking)
          .foregroundStyle(isRead ? .secondary : .primary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let originalTitle {
        Text(originalTitle)
          .font(.system(size: 12, weight: .regular))
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
        savedMark
      }

      HStack(spacing: 8) {
        timeText
        domainChip
        commentCount
        savedMark
      }

      HStack(spacing: 3) {
        timeText
        commentCount
        savedMark
      }
    }
    .font(.system(size: 11, weight: .medium))
    .tracking(AppTheme.Typography.metadataTracking)
    .foregroundStyle(.secondary)
  }

  private var timeText: some View {
    Text(item.time.shortTimeAgo)
      .fontDesign(.monospaced)
      .foregroundStyle(.secondary.opacity(0.78))
      .lineLimit(1)
  }

  @ViewBuilder
  private var domainChip: some View {
    if let domain = item.url?.hostDomain {
      Text(domain)
        .lineLimit(1)
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
        .font(.system(size: 10, weight: .semibold))
      Text("\(item.descendants ?? 0)")
        .fontDesign(.monospaced)
    }
    .lineLimit(1)
  }

  @ViewBuilder
  private var savedMark: some View {
    if isSaved {
      Image(systemName: "bookmark.fill")
        .foregroundStyle(.orange)
    }
  }

  private var rowBackground: some ShapeStyle {
    Color(.secondarySystemGroupedBackground).opacity(isRead ? 0.58 : 0.92)
  }

  private var rowStroke: some View {
    RoundedRectangle(cornerRadius: 8)
      .strokeBorder(
        isSaved ? Color.orange.opacity(0.34) : Color.primary.opacity(0.06),
        lineWidth: 1
      )
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
