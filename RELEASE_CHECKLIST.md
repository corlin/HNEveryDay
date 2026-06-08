# Release Checklist

## Release Candidate

- Version: `1.0` (`CURRENT_PROJECT_VERSION = 1`)
- Bundle ID: `cn.corlin.hneveryday.HNEveryDay`
- Deployment target: iOS `18.6`
- Swift language mode: `5.0`
- Current status: release candidate hardening

## Automated Checks

- [x] Unit tests pass on iPhone 17 Pro Simulator.
- [x] `git diff --check` passes.
- [x] README and CHANGELOG describe the current build and validation setup.

Command:

```bash
xcodebuild test -project HNEveryDay.xcodeproj -scheme HNEveryDay -destination id=9CFE28FE-F334-43F7-BBC2-3770BB6DF0E9 -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

Last verified: 2026-06-08, 20 unit tests passed.

## Smoke QA

- [x] App installs and launches on iPhone 17 Pro Max Simulator.
- [x] First-launch onboarding appears or, after completion, the Hacker News feed appears.
- [x] Feed loads top stories.
- [ ] Story detail opens from the feed.
- [ ] Reader mode shows parsed article content or falls back to web view cleanly.
- [ ] Comments tab loads and comment collapse/expand works.
- [ ] Save/unsave story updates the saved filter.
- [ ] Summary sheet opens without an API key and shows a useful configuration error.
- [ ] Markdown export share sheet opens from story detail.
- [ ] Settings opens and displays AI provider, language, cache, and app version sections.

Smoke note: on 2026-06-08, installed and launched the Debug app on iPhone 17 Pro Max Simulator (`CBA84A70-F9C4-4945-87D6-9B8AE5DF0B14`). The first-launch onboarding screen rendered correctly. After presetting `has_completed_onboarding`, the Hacker News feed loaded top stories. Deeper interaction checks remain manual until UI tapping automation is available.

## Known Limits Before Release

- AI summaries require the user to bring a compatible API key.
- Reader parsing depends on each article site's markup and can fall back to web view.
- Manual App Store archive/export validation is not covered by the simulator test run.

## Release Steps

- [ ] Complete Smoke QA.
- [ ] Confirm `CHANGELOG.md` is updated.
- [ ] Confirm working tree is clean.
- [ ] Create release tag, for example `v1.0-rc1`.
- [ ] Push tag to origin.
