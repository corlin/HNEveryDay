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
  var onToggleCollapse: () -> Void = {}
  @State private var bodyText: AttributedString?

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
        } else if let bodyText {
          Text(bodyText)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .tint(AppTheme.Palette.brand)
            .lineSpacing(3)
            .textSelection(.enabled)
        } else {
          Text("[deleted]")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 9)
    .padding(.leading, indentation)
    .background(rowBackground)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row))
    .overlay(rowStroke)
    .animation(AppTheme.Spring.fluid, value: isCollapsed)
    .onAppear {
      guard bodyText == nil, let html = node.item.text, !html.isEmpty else { return }
      bodyText = HTMLHelper.attributed(html)
    }
  }

  /// Only the header toggles collapsing, so selecting text and tapping links in the body work normally.
  private var headerRow: some View {
    Button(action: onToggleCollapse) {
      HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text(verbatim: node.item.by ?? "unknown")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)

        Text(node.item.time.shortTimeAgo)
          .font(.system(.caption2, design: .monospaced, weight: .medium))
          .tracking(AppTheme.Typography.metadataTracking)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        if isCollapsed {
          hiddenReplyText
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.Palette.brand)
            .lineLimit(1)
        }

        Spacer(minLength: 0)

        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .frame(minHeight: 28)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(verbatim: node.item.by ?? "unknown"))
    .accessibilityValue(isCollapsed ? Text("Collapsed") : Text("Expanded"))
    .accessibilityHint(isCollapsed ? Text("Shows this comment and its replies") : Text("Hides this comment and its replies"))
  }

  private var collapsedSummary: some View {
    Text(bodyText.map { String($0.characters) } ?? String(localized: "[deleted]"))
      .font(.footnote)
      .foregroundStyle(.secondary)
      .lineLimit(1)
  }

  private var rowBackground: some ShapeStyle {
    Color(.secondarySystemGroupedBackground).opacity(node.depth == 0 ? 0.9 : 0.55)
  }

  private var rowStroke: some View {
    RoundedRectangle(cornerRadius: AppTheme.Radius.row)
      .strokeBorder(Color.primary.opacity(node.depth == 0 ? 0.06 : 0.04), lineWidth: 1)
  }

  private var depthColor: Color {
    let palette: [Color] = [AppTheme.Palette.brand, .blue, .green, .purple, .pink, .teal]
    return palette[node.depth % palette.count]
  }

  private var hiddenReplyText: Text {
    let count = node.descendantCount
    if count == 1 {
      return Text("1 reply hidden")
    }
    return Text("\(count) replies hidden")
  }
}
