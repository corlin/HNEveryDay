# Implementation Plan: UI/UX & Motion Polish (ui-ux-motion-polish)

## Summary
Technical implementation plan for comprehensive Apple Design polish (WWDC Designing Fluid Interfaces, WWDC Audio-Haptic Experiences, WWDC Typography & Materials) and Emil Kowalski Design Engineering refinement across HNEveryDay.

## Constitution Alignment Check
- [x] **Architecture**: All UI design tokens centralized in `DesignSystem.swift`; Views remain declarative and lightweight.
- [x] **Concurrency**: All UI state updates run on `@MainActor` with 100% thread safety.
- [x] **Performance**: GPU-accelerated transform & opacity rendering maintaining 120fps scrolling.
- [x] **Security**: Keychain and local-first privacy intact with zero analytics.
- [x] **Resilience**: Smooth error recovery, non-blocking fallback states, and complete accessibility graceful degradation (`Reduce Motion` & `Reduce Transparency`).

## Proposed Changes

### Layer 1: Design System & Tokens
#### [MODIFY] [DesignSystem.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Utilities/DesignSystem.swift)
- Centralized `AppTheme` struct containing:
  - `Touch`: Press scale (0.978) and duration (0.12s).
  - `Spring`: `fluid` (`stiffness: 300, damping: 28`), `momentum` (`duration: 0.35, bounce: 0.15`), and `snappy` (`duration: 0.2`).
  - `Typography`: `titleTracking` (`-0.2pt`), `metadataTracking` (`+0.1pt`).
  - `Haptics`: Three-tier frame-synchronized feedback (`playLightImpact`, `playMediumImpact`, `playSuccessNotification`).
  - `Accessibility`: Modifiers for `prefers-reduced-motion` and `prefers-reduced-transparency`.

### Layer 2: Core Components & Views
#### [MODIFY] [StoryRowView.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Views/StoryRowView.swift)
- Apply optical typography tracking (`-0.2pt` on title, `+0.1pt` on monospaced metadata).
- Integrate `.buttonStyle(.tactile)` for instant touch-down scale effect.

#### [MODIFY] [CommentRowView.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Views/Components/CommentRowView.swift)
- Integrate interruptible spring animations (`AppTheme.Spring.fluid`) supporting velocity handoff and mid-motion reversal.
- Trigger `AppTheme.Haptics.playLightImpact()` on the exact frame of node collapse/expand.

#### [MODIFY] [SummaryView.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Views/Components/SummaryView.swift)
- Upgrade background to `.ultraThinMaterial` with top border highlight catching light.
- Apply high-contrast semantic typography and trigger-anchored transition expansion.
- Fire `AppTheme.Haptics.playSuccessNotification()` on AI summary generation completion.

#### [MODIFY] [FeedView.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Views/FeedView.swift)
- Apply `.buttonStyle(.tactile)` to feed items.
- Trigger `AppTheme.Haptics.playMediumImpact()` on bookmark/save operations in `DataService.swift`.

## Verification Plan

### Automated Tests
- Execute `xcodebuild test` using iOS 17/18 Simulator:
  ```bash
  xcodebuild test -project HNEveryDay.xcodeproj -scheme HNEveryDay -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
  ```

### Manual Verification
- Test 1: Verify immediate touch-down scale feedback (0.978) on story list items.
- Test 2: Perform mid-motion drag and interruption on comment tree folding.
- Test 3: Inspect `.ultraThinMaterial` translucency over dark/light scroll content.
- Test 4: Verify distinct haptic feedback intensities (Light for collapse, Medium for save, Success for AI completion).
- Test 5: Verify accessibility fallback when Reduce Motion / Reduce Transparency is enabled in iOS Simulator settings.
