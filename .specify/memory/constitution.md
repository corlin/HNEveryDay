<!--
Sync Impact Report:
- Version change: N/A -> v1.0.0
- List of modified principles: N/A (Initial ratification)
- Added sections: Core Principles, Governance & Versioning, Tech Stack & Development Standards
- Templates requiring updates: ✅ spec-template.md, ✅ plan-template.md, ✅ tasks-template.md
-->

# HNEveryDay Project Constitution

- **Version**: v1.0.0
- **Ratification Date**: 2026-07-23
- **Last Amended Date**: 2026-07-23

## Core Principles

### 1. Architecture & Concurrency
- **MVVM Pattern**: The application MUST strictly adhere to the SwiftUI + MVVM architecture. Views MUST remain light and declarative, delegating logic and state management to `ObservableObject` / `@Observable` ViewModels.
- **Strict Threading & Concurrency**: All asynchronous operations, data processing, and network calls MUST use Swift native `async/await` and thread-safe `actor` types. Main-thread blocking is strictly prohibited; all state mutations targeting the UI MUST execute on `@MainActor`.

### 2. Extreme Performance & Fluid UX
- **120fps Scrolling**: UI rendering and list scrolling MUST maintain 120fps without dropping frames.
- **Tree Optimization**: Comment tree structures MUST support color-coded nesting and collapsible nodes with localized sub-tree rendering to avoid heavy view re-evaluations.
- **Zero Heavy View Work**: Expensive computations, HTML parsing, or regex matching MUST occur in background actors/services before reaching the View layer.

### 3. Privacy & Local-First Security
- **Secure Keychain Storage**: All sensitive credentials (such as AI Provider API Keys) MUST be stored strictly in the iOS Keychain (`Security` framework). Storing API keys in `UserDefaults` or plaintext files is prohibited.
- **Local-First AI Control**: AI configurations and preferences MUST remain on-device. Zero telemetry or user tracking payload MAY be transmitted to unapproved third parties.

### 4. Resilience & Graceful Degradation
- **Exponential Backoff**: All external network calls and AI service requests MUST implement robust exponential backoff retries (e.g., 3x backoff retry strategy).
- **Graceful Error UI**: When network failures or API key errors occur, the UI MUST display clear, non-intrusive feedback guiding the user to recover without crashing or showing blank states.

## Governance & Versioning

- **Version Scheme**: The constitution follows Semantic Versioning (`MAJOR.MINOR.PATCH`).
  - **MAJOR**: Breaking removals or fundamental redefinitions of core principles.
  - **MINOR**: Addition of new principles or significant structural guidance expansion.
  - **PATCH**: Non-semantic clarifications, typo fixes, or wording polish.
- **Amendment Procedure**: Any amendment MUST update the `LAST_AMENDED_DATE`, increment the version number, and generate a Sync Impact Report at the top of this document.
- **Template Synchronization**: Every constitution update MUST verify alignment across `.specify/templates/` templates.

## Tech Stack & Compliance Rules

- **Target Platform**: iOS 18.6+
- **Language**: Swift 5+
- **UI Framework**: SwiftUI
- **Persistence**: SwiftData with read-through caching
- **Security**: iOS Keychain (`KeychainServices`)
