//
//  ArticleImages.swift
//  HNEveryDay
//

import Foundation

/// Keeps an article's images through AI translation. Each image becomes an `[IMG:n]` line that the
/// model copies through unchanged; the translated reader puts image n back in its place.
/// Image URLs never go to the model, only the markers.
enum ArticleImages {
  static let maxImages = 20

  /// Article text with each image replaced by an `[IMG:n]` line; marker n refers to `urls[n - 1]`.
  static func markedText(html: String) -> (text: String, urls: [URL]) {
    var urls: [URL] = []
    var marked = ""
    var cursor = html.startIndex
    for match in html.matches(of: imgTag) {
      marked += html[cursor..<match.range.lowerBound]
      cursor = match.range.upperBound
      if urls.count < maxImages, let url = imageURL(in: String(html[match.range])) {
        urls.append(url)
        marked += "\n\n<p>[IMG:\(urls.count)]</p>"
      }
    }
    marked += html[cursor...]
    // stripTags only breaks on <p>; keep headings, list items and blocks apart as well.
    marked = marked.replacing(blockEnd, with: "\n\n").replacing(listItemEnd, with: "\n")
    return (HTMLHelper.stripTags(marked).trimmingCharacters(in: .whitespacesAndNewlines), urls)
  }

  /// Image URLs in document order, numbered the same way as `markedText`.
  static func urls(in html: String) -> [URL] {
    Array(html.matches(of: imgTag).lazy.compactMap { imageURL(in: String(html[$0.range])) }.prefix(maxImages))
  }

  /// The image number of a marker line such as `[IMG:3]`, tolerating the escapes and emphasis
  /// a model sometimes wraps around it.
  static func markerIndex(_ line: String) -> Int? {
    let cleaned = line.replacingOccurrences(of: "\\", with: "")
      .trimmingCharacters(in: CharacterSet(charactersIn: "*_` ").union(.whitespaces))
    guard let match = cleaned.wholeMatch(of: markerLine) else { return nil }
    return Int(match.1)
  }

  /// Removes markers a model left inside a paragraph instead of on their own line.
  static func stripInlineMarkers(_ text: String) -> String {
    text.replacing(inlineMarker, with: "")
  }

  private static let imgTag = /<img\b[^>]*>/.ignoresCase()
  private static let blockEnd = /<\/(?:h[1-6]|div|section|blockquote|pre|figure|figcaption|ul|ol|table|tr)>/.ignoresCase()
  private static let listItemEnd = /<\/li>/.ignoresCase()
  private static let srcAttribute = /\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)')/.ignoresCase()
  private static let tinySize = /\b(?:width|height)\s*=\s*["']?[01](?:px)?["'\s\/>]/.ignoresCase()
  private static let markerLine = /\[IMG:\s*(\d+)\]/.ignoresCase()
  private static let inlineMarker = /\\?\[IMG:\s*\d+\\?\]/.ignoresCase()

  private static func imageURL(in tag: String) -> URL? {
    // Tracking pixels and spacers are 1px; they are not worth a slot or a request.
    guard tag.firstMatch(of: tinySize) == nil,
      let match = tag.firstMatch(of: srcAttribute),
      let raw = match.1 ?? match.2
    else { return nil }
    let src = raw.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespaces)
    guard let url = URL(string: src),
      let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
      // AsyncImage cannot draw SVG.
      url.pathExtension.lowercased() != "svg"
    else { return nil }
    return url
  }
}
