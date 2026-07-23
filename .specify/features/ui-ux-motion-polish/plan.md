# Implementation Plan: UI/UX & Motion Polish (ui-ux-motion-polish)

## Summary
Technical plan for adding DesignSystem Tokens, touch feedback, interruptible spring animations, translucent materials, and optical typography.

## Constitution Alignment Check
- [x] **Architecture**: Centralized design tokens in `DesignSystem.swift`; Views remain declarative.
- [x] **Concurrency**: Thread-safe UI updates on `@MainActor`.
- [x] **Performance**: GPU-accelerated transform & opacity animations maintaining 120fps.
- [x] **Security**: Keychain and local-first privacy intact.
- [x] **Resilience**: Error states and graceful degradation unchanged.

## Proposed Changes

### Layer 1: Design System & Utilities
#### [NEW] [DesignSystem.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Utilities/DesignSystem.swift)
- Centralized `AppTheme` struct with `Touch`, `Spring`, `Typography`, `Materials`, and `Haptics`.

### Layer 2: Views & Components
#### [MODIFY] [StoryRowView.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Views/StoryRowView.swift)
- Add press feedback scale and optical tracking adjustments.

#### [MODIFY] [CommentRowView.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Views/Components/CommentRowView.swift)
- Integrate interruptible spring animations, press scale, and soft haptics.

#### [MODIFY] [SummaryView.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Views/Components/SummaryView.swift)
- Upgrade to `.ultraThinMaterial` background and smooth state transitions.

#### [MODIFY] [FeedView.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Views/FeedView.swift)
- Tune list item animations using `AppTheme.Spring.fluid`.

## Verification Plan

### Automated Tests
- Build project using Xcode tooling.
- Run `HNEveryDayTests` target if present.

### Manual Verification
- Verify instant press state response on story rows and comment nodes.
- Test continuous, interruptible folding of deep comment subtrees.
- Inspect liquid material translucency in Dark and Light modes.
