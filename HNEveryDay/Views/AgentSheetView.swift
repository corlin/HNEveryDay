//
//  AgentSheetView.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import SwiftUI

/// "✨ Ask Agent": Smart Chips for one-tap questions plus free-form follow-ups, streamed.
struct AgentSheetView: View {
  @State private var model: AgentViewModel
  @State private var input = ""
  @State private var showPaywall = false
  @State private var reportedIds: Set<UUID> = []
  @FocusState private var inputFocused: Bool
  @Environment(\.dismiss) private var dismiss

  init(context: AgentContext) {
    _model = State(initialValue: AgentViewModel(context: context))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
              if model.messages.isEmpty {
                chips
              }
              ForEach(model.messages) { message in
                bubble(message)
                  .id(message.id)
              }
              if !model.followUpChips.isEmpty {
                chipList(model.followUpChips)
              }
              if let error = model.errorMessage {
                errorCard(error)
              }
              Color.clear.frame(height: 1).id("bottom")
            }
            .padding(14)
          }
          .scrollDismissesKeyboard(.interactively)
          .onChange(of: model.messages.last?.text) { _, _ in
            withAnimation(AppTheme.Spring.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
          }
        }
        inputBar
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle(Text("Ask Agent"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          if let remaining = model.remaining, let limit = model.limit {
            Text("Today \(remaining)/\(limit)")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            model.stop()
            dismiss()
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }
          .accessibilityLabel(Text("Close"))
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .onAppear { AppTheme.Haptics.playLightImpact() }
    .task { await model.loadSuggestions() }
    .sheet(isPresented: $showPaywall) {
      PaywallView(reason: .agent)
    }
    .onDisappear { model.stop() }
  }

  // MARK: - Pieces

  private var chips: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text("Quick questions")
        if model.isLoadingSuggestions {
          ProgressView()
            .controlSize(.mini)
            .accessibilityLabel(Text("Loading questions"))
        }
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      chipList(model.suggestions)
    }
  }

  private func chipList(_ chips: [AgentChip]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(chips) { chip in
        Button {
          model.send(chip.title)
        } label: {
          Label(chip.title, systemImage: chip.icon)
            .font(.subheadline)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
              RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.tactile)
        .foregroundStyle(.primary)
      }
    }
  }

  @ViewBuilder
  private func bubble(_ message: AgentMessage) -> some View {
    switch message.role {
    case .user:
      HStack {
        Spacer(minLength: 40)
        Text(message.text)
          .font(.subheadline)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(Color.orange.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 12))
      }
    case .assistant:
      VStack(alignment: .leading, spacing: 6) {
        if message.visibleText.isEmpty {
          thinkingIndicator
        } else {
          MarkdownContentView(content: message.visibleText)
        }
        if !message.visibleText.isEmpty && !(model.isStreaming && message.id == model.messages.last?.id) {
          HStack(spacing: 12) {
            AIContentLabel()
            if AIMode.current == .hosted {
              Button(reportedIds.contains(message.id) ? "Reported" : "Report") {
                reportedIds.insert(message.id)
                Task { await model.report(message) }
              }
              .disabled(reportedIds.contains(message.id))
            }
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .contextMenu {
        Button {
          UIPasteboard.general.string = AIContentLabel.labeled(message.visibleText)
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        ShareLink(item: AIContentLabel.labeled(message.visibleText))
      }
    }
  }

  /// Shown until the first words arrive; after a few seconds it says how long it has been waiting.
  private var thinkingIndicator: some View {
    HStack(spacing: 8) {
      ProgressView().controlSize(.small)
      if let since = model.waitingSince {
        TimelineView(.periodic(from: since, by: 1)) { timeline in
          let seconds = Int(timeline.date.timeIntervalSince(since))
          Group {
            if seconds >= 3 {
              Text("Thinking… \(seconds)s")
            } else {
              Text("Thinking…")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
        }
      }
    }
  }

  private func errorCard(_ error: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(error)
        .font(.caption)
        .foregroundStyle(.secondary)
      if model.retryableQuestion != nil {
        Button {
          model.retry()
        } label: {
          Label("Try Again", systemImage: "arrow.clockwise")
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(.orange)
      }
      if model.quotaExceeded && StoreManager.shared.isPaywallAvailable {
        Button {
          showPaywall = true
        } label: {
          Label("Upgrade to HNEveryDay Pro", systemImage: "sparkles")
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private var inputBar: some View {
    HStack(spacing: 8) {
      TextField("Ask a follow-up…", text: $input, axis: .vertical)
        .lineLimit(1...4)
        .focused($inputFocused)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .submitLabel(.send)
        .onSubmit(submit)

      if model.isStreaming {
        Button {
          model.stop()
        } label: {
          Image(systemName: "stop.circle.fill").font(.title2)
        }
        .tint(.orange)
        .accessibilityLabel(Text("Stop"))
      } else {
        Button(action: submit) {
          Image(systemName: "arrow.up.circle.fill").font(.title2)
        }
        .tint(.orange)
        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel(Text("Send"))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.bar)
  }

  private func submit() {
    let text = input
    input = ""
    model.send(text)
  }
}

/// Floating "✨ Ask Agent" capsule for the reader and comments.
struct AskAgentButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label("Ask Agent", systemImage: "sparkles")
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
    .buttonStyle(.tactile)
    .foregroundStyle(.orange)
  }
}
