//
//  CommentRowView.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import SwiftUI

struct CommentRowView: View {
  let node: CommentNode
  var isCollapsed: Bool = false
  @State private var displayText: String = ""

  private var indentation: CGFloat {
    return CGFloat(min(node.depth, 6)) * 14.0
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      if node.depth > 0 {
        Rectangle()
          .fill(depthColor.opacity(0.34))
          .frame(width: 2)
          .clipShape(Capsule())
          .padding(.vertical, 3)
      }

      VStack(alignment: .leading, spacing: 7) {
        headerRow

        if isCollapsed {
          collapsedSummary
        } else if !displayText.isEmpty {
          commentText(displayText)
        } else {
          commentText("[no content]")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 9)
    .padding(.leading, indentation)
    .background(rowBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(rowStroke)
    .contentShape(Rectangle())
    .animation(AppTheme.Spring.fluid, value: isCollapsed)
    .onAppear {
      if let html = node.item.text, !html.isEmpty {
        displayText = HTMLHelper.stripTags(html)
      } else {
        displayText = "[deleted]"
      }
    }
  }

  private var headerRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      Text(node.item.by ?? "unknown")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)

      Text(node.item.time.shortTimeAgo)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .tracking(AppTheme.Typography.metadataTracking)
        .foregroundStyle(.secondary.opacity(0.82))
        .lineLimit(1)

      if isCollapsed {
        Text(hiddenReplyText)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.orange)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary.opacity(0.7))
    }
  }

  private var collapsedSummary: some View {
    Text(displayText.isEmpty ? "[collapsed]" : displayText)
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
      .lineLimit(1)
  }

  private func commentText(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 14))
      .foregroundStyle(text == "[no content]" ? Color.secondary : Color.primary)
      .lineSpacing(3)
      .textSelection(.enabled)
  }

  private var rowBackground: some ShapeStyle {
    Color(.secondarySystemGroupedBackground).opacity(node.depth == 0 ? 0.9 : 0.55)
  }

  private var rowStroke: some View {
    RoundedRectangle(cornerRadius: 8)
      .strokeBorder(Color.primary.opacity(node.depth == 0 ? 0.06 : 0.04), lineWidth: 1)
  }

  private var depthColor: Color {
    let palette: [Color] = [.orange, .blue, .green, .purple, .pink, .teal]
    return palette[node.depth % palette.count]
  }

  private var hiddenReplyText: String {
    let count = node.descendantCount
    if count == 1 {
      return "1 reply hidden"
    }
    return "\(count) replies hidden"
  }
}
