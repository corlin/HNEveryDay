# Actionable Tasks: Batch Data Fetching & AI Translation Pipeline (batch-translation-and-fetching)

## Task Breakdown

### Task Group 1: Service Layer Enhancement
- [x] Task 1.1: Update `HNClient.swift` to add `fetchMultiFeedIds(types:)` for parallel multi-feed fetching and Set deduplication.
- [x] Task 1.2: Update `AIService.swift` to support larger batch sizes (up to 25 items per request).

### Task Group 2: ViewModel Pipeline Implementation
- [x] Task 2.1: Update `FeedViewModel.swift` to increase `pageSize` to 40 items and add data-driven background batch translation.
- [x] Task 2.2: Add primary feed prefetching (`Top`, `New`, `Best`) in `FeedViewModel.swift`.

### Task Group 3: View Layer Integration
- [x] Task 3.1: Update `FeedView.swift` to utilize `FeedViewModel`'s background translation pipeline and local cache.

### Task Group 4: Build & Test Verification
- [x] Task 4.1: Execute `xcodebuild` build and unit tests to verify zero compiler errors and 100% test pass rate.
