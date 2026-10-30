//
//  MarkdownContentView.swift
//  HNEveryDay
//
//  Created by AI on 02/01/2026.
//

import SwiftUI

/// Custom Markdown renderer that properly handles headers, bullets, and bold text
struct MarkdownContentView: View {
  let content: String
  /// Images for `[IMG:n]` marker lines (translated articles); markers without an image are dropped.
  var images: [URL] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(parseLines(), id: \.id) { line in
        line.view
      }
    }
    .textSelection(.enabled)
  }

  private func parseLines() -> [ParsedLine] {
    let lines = content.components(separatedBy: "\n")
    var result: [ParsedLine] = []
    var id = 0

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Skip empty lines
      if trimmed.isEmpty {
        id += 1
        result.append(ParsedLine(id: id, view: AnyView(Spacer().frame(height: 4))))
        continue
      }

      id += 1

      // Image marker [IMG:n]
      if let index = ArticleImages.markerIndex(trimmed) {
        if images.indices.contains(index - 1) {
          result.append(ParsedLine(id: id, view: AnyView(ArticleImageView(url: images[index - 1]))))
        }
        continue
      }

      // Header ##
      if trimmed.hasPrefix("## ") {
        let text = String(trimmed.dropFirst(3))
        result.append(
          ParsedLine(
            id: id,
            view: AnyView(
              Text(text)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.top, 8)
            )))
      }
      // Bullet point -
      else if trimmed.hasPrefix("- ") {
        let text = String(trimmed.dropFirst(2))
        result.append(
          ParsedLine(
            id: id,
            view: AnyView(
              HStack(alignment: .top, spacing: 8) {
                Text("•")
                  .font(.body)
                  .foregroundStyle(AppTheme.Palette.brand)
                Text(parseBoldText(text))
                  .font(.subheadline)
                  .foregroundStyle(.primary)
                  .lineSpacing(4)
              }
              .padding(.leading, 4)
            )))
      }
      // Regular text
      else {
        result.append(
          ParsedLine(
            id: id,
            view: AnyView(
              Text(parseBoldText(ArticleImages.stripInlineMarkers(trimmed)))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(6)
            )))
      }
    }

    return result
  }

  /// Parses **bold** text into AttributedString
  private func parseBoldText(_ text: String) -> AttributedString {
    var result = AttributedString()
    var current = text

    while let boldStart = current.range(of: "**") {
      // Add text before bold
      let before = String(current[..<boldStart.lowerBound])
      result += AttributedString(before)

      // Find closing **
      let afterStart = current[boldStart.upperBound...]
      if let boldEnd = afterStart.range(of: "**") {
        let boldText = String(afterStart[..<boldEnd.lowerBound])
        var boldAttr = AttributedString(boldText)
        boldAttr.inlinePresentationIntent = .stronglyEmphasized
        result += boldAttr
        current = String(afterStart[boldEnd.upperBound...])
      } else {
        // No closing **, just add rest
        result += AttributedString(String(afterStart))
        current = ""
      }
    }

    // Add remaining text
    result += AttributedString(current)
    return result
  }
}

/// An article image that takes no space until it loads, so a blocked or broken image leaves no gap.
private struct ArticleImageView: View {
  let url: URL

  var body: some View {
    AsyncImage(url: url) { phase in
      if let image = phase.image {
        image
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .padding(.vertical, 4)
      }
    }
    .accessibilityHidden(true)
  }
}

private struct ParsedLine: Identifiable {
  let id: Int
  let view: AnyView
}

#Preview {
  ScrollView {
    MarkdownContentView(
      content: """
        ## 📝 文章核心
        这是一段测试文本，用来展示 Markdown 渲染效果。

        ## 💬 讨论焦点
        - **观点一**: 这是第一个要点的说明。
        - **观点二**: 这是第二个要点的说明。
        - **观点三**: 这是第三个要点的说明。

        ## 🎯 结论
        这是总结性的结论文本。
        """
    )
    .padding()
  }
}
