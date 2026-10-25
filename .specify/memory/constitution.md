<!--
Sync Impact Report:
- Version change: v1.0.0 -> v2.0.0 (MAJOR)
- Modified principles: "3. Privacy & Local-First Security" redefined as "3. Privacy, Security & Approved Processors"
  (hosted AI backend and hosted model provider become approved processors; BYOK stays local-first).
- Added principles: "5. Bounded Cost & Server-Side Trust"
- Added sections: Approved Third-Party Processors
- Rationale: docs/PRO_PAYWALL_AND_BACKEND_SPEC.md v0.2 introduces a hosted Cloudflare backend and paid tier.
- Templates requiring updates: ✅ spec-template.md, ✅ plan-template.md, ✅ tasks-template.md (no principle names referenced)

Previous report (v1.0.0): initial ratification.
-->

# HNEveryDay Project Constitution

- **Version**: v2.0.0
- **Ratification Date**: 2026-07-23
- **Last Amended Date**: 2026-10-25

## Core Principles

### 1. Architecture & Concurrency
- **MVVM Pattern**: The application MUST strictly adhere to the SwiftUI + MVVM architecture. Views MUST remain light and declarative, delegating logic and state management to `ObservableObject` / `@Observable` ViewModels.
- **Strict Threading & Concurrency**: All asynchronous operations, data processing, and network calls MUST use Swift native `async/await` and thread-safe `actor` types. Main-thread blocking is strictly prohibited; all state mutations targeting the UI MUST execute on `@MainActor`.

### 2. Extreme Performance & Fluid UX
- **120fps Scrolling**: UI rendering and list scrolling MUST maintain 120fps without dropping frames.
- **Tree Optimization**: Comment tree structures MUST support color-coded nesting and collapsible nodes with localized sub-tree rendering to avoid heavy view re-evaluations.
- **Zero Heavy View Work**: Expensive computations, HTML parsing, or regex matching MUST occur in background actors/services before reaching the View layer.

### 3. Privacy, Security & Approved Processors
- **Secure Keychain Storage**: All sensitive credentials (BYOK provider API keys, App Attest key ids, app account tokens) MUST be stored strictly in the iOS Keychain (`Security` framework). Storing them in `UserDefaults` or plaintext files is prohibited.
- **Two AI Modes**: Hosted mode (default) sends AI requests only to the project's own backend. BYOK mode (advanced) sends AI requests directly to the user's configured provider and MUST NOT route through the project backend.
- **Approved Processors Only**: User content MAY be sent only to the processors listed under "Approved Third-Party Processors". No telemetry or tracking payload MAY be sent anywhere else.
- **Data Minimization**: The backend MUST NOT persist Agent conversations. Device identity MUST be anonymous (App Attest key id), never linked to personal data.

### 4. Resilience & Graceful Degradation
- **Exponential Backoff**: All external network calls and AI service requests MUST implement robust exponential backoff retries (e.g., 3x backoff retry strategy).
- **Graceful Error UI**: When network failures or API key errors occur, the UI MUST display clear, non-intrusive feedback guiding the user to recover without crashing or showing blank states.

### 5. Bounded Cost & Server-Side Trust
- **No Unbounded Promises**: Any feature whose cost grows with usage MUST have a quota or fair-use limit and a global budget circuit breaker.
- **Server Is the Source of Truth**: Entitlements, quotas and device identity MUST be decided server-side (App Attest, verified App Store transactions). The client MUST NOT be trusted for these.
- **Kill Switch**: Every hosted feature MUST be remotely disableable, and the app MUST degrade gracefully (original text, BYOK) when it is.
- **News Feed Independence**: The story list and comments MUST keep loading directly from the official Hacker News API, independent of the project backend.

## Approved Third-Party Processors

| Processor | Purpose | Data |
| :-- | :-- | :-- |
| Hacker News official API (Firebase) | News feed, comments | None (read-only) |
| HNEveryDay backend (Cloudflare Workers / D1) | Hosted AI, quotas, subscription state | Anonymous device id, article excerpts, Agent prompts (not stored) |
| Hosted model provider (DeepSeek, via backend) | AI generation | Article excerpts, comments, Agent prompts |
| Apple (StoreKit, App Attest, App Store Server API) | Purchases, device attestation | Transactions, attestation |
| User-configured provider (BYOK mode only) | AI generation | As chosen by the user |

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
- **Security**: iOS Keychain (`KeychainServices`), App Attest (`DeviceCheck`)
- **Payments**: StoreKit 2
- **Backend**: Cloudflare Workers (TypeScript), D1, KV, Durable Objects (`backend/`)
