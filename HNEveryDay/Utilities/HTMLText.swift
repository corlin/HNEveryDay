//
//  HTMLText.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import SwiftUI

enum HTMLHelper {
  /// Strips HTML tags and converts to plain text
  static func stripTags(_ html: String) -> String {
    guard !html.isEmpty else { return "" }

    var result =
      html
      // Convert paragraph and line breaks
      .replacingOccurrences(of: "<p>", with: "")
      .replacingOccurrences(of: "</p>", with: "\n\n")
      .replacingOccurrences(of: "<br>", with: "\n")
      .replacingOccurrences(of: "<br/>", with: "\n")
      .replacingOccurrences(of: "<br />", with: "\n")
      // Decode HTML entities
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#x27;", with: "'")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&#x2F;", with: "/")

    // Remove remaining HTML tags
    result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

    // Clean up multiple newlines
    while result.contains("\n\n\n") {
      result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Parses HN-flavoured HTML (paragraphs, links, italics, code blocks) to an AttributedString.
  @MainActor
  static func parse(_ html: String) -> AttributedString {
    attributed(html)
  }

  private nonisolated static let tagPattern = try! NSRegularExpression(pattern: "<(/?)([a-zA-Z0-9]+)([^>]*)>")
  private nonisolated static let hrefPattern = try! NSRegularExpression(
    pattern: "href\\s*=\\s*\"([^\"]*)\"", options: .caseInsensitive)
  private nonisolated static let numericEntityPattern = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")

  /// Keeps the structure HN comments use: `<p>` paragraphs, `<a href>` links, `<i>` emphasis and `<pre><code>` blocks.
  nonisolated static func attributed(_ html: String) -> AttributedString {
    guard !html.isEmpty else { return AttributedString() }

    var result = AttributedString()
    var italicDepth = 0
    var codeDepth = 0
    var link: URL?
    var cursor = 0
    let source = html as NSString

    /// Ends the text with `count` newlines, counting ones already there (so `<p><pre>` gives one blank line).
    func appendBreak(_ count: Int) {
      guard !result.characters.isEmpty else { return }
      let trailing = result.characters.reversed().prefix { $0 == "\n" }.count
      if count > trailing {
        result += AttributedString(String(repeating: "\n", count: count - trailing))
      }
    }

    func appendText(_ raw: String) {
      let text = codeDepth > 0 ? raw : raw.replacingOccurrences(of: "\n", with: " ")
      guard !text.isEmpty else { return }
      var piece = AttributedString(decodeEntities(text))
      var intent: InlinePresentationIntent = []
      if italicDepth > 0 { intent.insert(.emphasized) }
      if codeDepth > 0 { intent.insert(.code) }
      if !intent.isEmpty { piece.inlinePresentationIntent = intent }
      if let link { piece.link = link }
      result += piece
    }

    let matches = tagPattern.matches(in: html, range: NSRange(location: 0, length: source.length))
    for match in matches {
      appendText(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
      cursor = match.range.location + match.range.length

      let isClosing = source.substring(with: match.range(at: 1)) == "/"
      let tag = source.substring(with: match.range(at: 2)).lowercased()
      let attributes = source.substring(with: match.range(at: 3))

      switch tag {
      case "p":
        if !isClosing { appendBreak(2) }
      case "br":
        appendBreak(1)
      case "i", "em":
        italicDepth = max(0, italicDepth + (isClosing ? -1 : 1))
      case "pre":
        if !isClosing { appendBreak(2) }
        codeDepth = max(0, codeDepth + (isClosing ? -1 : 1))
      case "a":
        if isClosing {
          link = nil
        } else {
          let attrs = attributes as NSString
          if let hrefMatch = hrefPattern.firstMatch(
            in: attributes, range: NSRange(location: 0, length: attrs.length))
          {
            link = URL(string: decodeEntities(attrs.substring(with: hrefMatch.range(at: 1))))
          }
        }
      default:
        break
      }
    }
    appendText(source.substring(from: cursor))

    // Drop trailing whitespace and newlines (e.g. after a closing </pre>).
    while let last = result.characters.last, last.isWhitespace {
      result.characters.removeLast()
    }
    return result
  }

  nonisolated static func decodeEntities(_ text: String) -> String {
    guard text.contains("&") else { return text }
    var decoded =
      text
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&nbsp;", with: " ")

    let ns = decoded as NSString
    let matches = numericEntityPattern.matches(in: decoded, range: NSRange(location: 0, length: ns.length))
    if !matches.isEmpty {
      var rebuilt = ""
      var cursor = 0
      for match in matches {
        rebuilt += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        let isHex = ns.substring(with: match.range(at: 1)) == "x"
        let digits = ns.substring(with: match.range(at: 2))
        if let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) {
          rebuilt.unicodeScalars.append(scalar)
        } else {
          rebuilt += ns.substring(with: match.range)
        }
        cursor = match.range.location + match.range.length
      }
      rebuilt += ns.substring(from: cursor)
      decoded = rebuilt
    }
    // Last, so "&amp;lt;" stays the literal text "&lt;".
    return decoded.replacingOccurrences(of: "&amp;", with: "&")
  }

  /// Escapes text for interpolation into an HTML document.
  nonisolated static func escape(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
