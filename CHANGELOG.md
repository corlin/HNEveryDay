# Changelog

## Unreleased - 2026-06-08

### Highlights

- Improved the cache-backed reading flow: saved stories can reopen cached content and hydrate missing story metadata before loading comments.
- Localized the AI summary prompt so explicit English and Simplified Chinese preferences produce matching summary templates.
- Added a unit test target with coverage for Markdown export, HTML cleanup, AI prompt construction, comment tree flattening, Hacker News client errors, and comment loading behavior.
- Hardened Hacker News networking with clearer HTTP, empty response, null payload, network, and decoding errors.
- Centralized comment tree flattening and improved collapsed-thread reply counts.
- Added an adaptive article translation foundation: settings can disable translation, translate on demand, or auto-translate Reader content when the source language differs from the preferred reading language.
- Added automatic feed title translation in Auto mode, with visible-row translation, original-title fallback, and cached translated titles.
- Cached translated article title/body locally and added a translated Reader view backed by OpenAI-compatible providers.
- Switched the first-run AI defaults to DeepSeek with `deepseek-v4-flash` while keeping API keys user-supplied and stored only in Keychain.
- Expanded AI response and translation language options beyond English and Simplified Chinese, including Traditional Chinese, Japanese, Korean, Spanish, French, German, Portuguese, and Russian.
- Updated README files to match the current Swift language mode, iOS deployment target, Xcode verification, and test command.

### Validation

- `xcodebuild test -project HNEveryDay.xcodeproj -scheme HNEveryDay -destination id=9CFE28FE-F334-43F7-BBC2-3770BB6DF0E9 -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO`
- 20 unit tests passed on iPhone 17 Pro Simulator.
- `xcodebuild build -project HNEveryDay.xcodeproj -scheme HNEveryDay -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO`
- Adaptive article and title translation build verification passed; live LLM output remains a manual QA item.
