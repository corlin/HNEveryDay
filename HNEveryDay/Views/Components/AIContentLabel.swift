//
//  AIContentLabel.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import SwiftUI

/// Explicit "AI-generated" marking for model output, as required by China's rules on labelling
/// AI-generated content. Shown next to summaries and Agent answers, and appended to copied/shared text.
struct AIContentLabel: View {
  var body: some View {
    Label {
      Text("AI-generated, may be inaccurate")
    } icon: {
      Image(systemName: "sparkles")
    }
    .labelStyle(.titleAndIcon)
  }

  /// Text leaving the app (copy, share) keeps the label.
  static func labeled(_ text: String) -> String {
    "\(text)\n\n— \(String(localized: "AI-generated content · HNEveryDay"))"
  }
}
