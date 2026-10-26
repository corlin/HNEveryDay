//
//  SkeletonView.swift
//  HNEveryDay
//
//  Created by AI on 02/01/2026.
//

import SwiftUI

struct SkeletonView: View {
  var body: some View {
    VStack(spacing: 10) {
      ForEach(0..<8, id: \.self) { index in
        SkeletonRow(titleWidthFraction: index.isMultiple(of: 3) ? 0.55 : 0.8)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Loading"))
  }
}

/// Same layout as `StoryRowView` (score column, two title lines, metadata), so nothing jumps when stories arrive.
struct SkeletonRow: View {
  var titleWidthFraction: CGFloat = 0.8
  @State private var shimmerOffset: CGFloat = -1
  @ScaledMetric(relativeTo: .subheadline) private var scoreColumnWidth: CGFloat = 38

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      HStack {
        Spacer(minLength: 0)
        bar(width: 26, height: 14, opacity: 0.2)
      }
      .frame(width: scoreColumnWidth)
      .padding(.top, 2)

      VStack(alignment: .leading, spacing: 7) {
        bar(height: 14, opacity: 0.2)
        GeometryReader { geometry in
          bar(width: geometry.size.width * titleWidthFraction, height: 14, opacity: 0.2)
        }
        .frame(height: 14)
        HStack(spacing: 8) {
          bar(width: 34, height: 10, opacity: 0.12)
          bar(width: 76, height: 10, opacity: 0.12)
          bar(width: 30, height: 10, opacity: 0.12)
        }
        .padding(.top, 2)
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 11)
    .cardSurface()
    .overlay(
      GeometryReader { geometry in
        LinearGradient(
          gradient: Gradient(colors: [
            Color.clear,
            Color.white.opacity(0.3),
            Color.clear,
          ]),
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: 100)
        .offset(x: shimmerOffset * geometry.size.width)
        .blendMode(.overlay)
      }
    )
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row))
    .onAppear {
      withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
        shimmerOffset = 2
      }
    }
  }

  private func bar(width: CGFloat? = nil, height: CGFloat, opacity: Double) -> some View {
    RoundedRectangle(cornerRadius: 4)
      .fill(Color.secondary.opacity(opacity))
      .frame(width: width, height: height)
      .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
  }
}

#Preview {
  SkeletonView()
    .padding()
}
