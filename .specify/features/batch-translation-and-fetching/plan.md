# Implementation Plan: Batch Data Fetching & AI Translation Pipeline (batch-translation-and-fetching)

## Summary
Technical implementation plan for high-throughput multi-feed prefetching and large-batch AI title translation pipeline.

## Constitution Alignment Check
- [x] **Architecture**: MVVM separation preserved; data prefetching & batch translation handled in `FeedViewModel` / `AIService` / `HNClient`.
- [x] **Concurrency**: Concurrently fetch Top/New/Best IDs with `TaskGroup` off `@MainActor`.
- [x] **Performance**: Page capacity enlarged to 40 items, AI batch size enlarged to 25 items per request.
- [x] **Security**: Keychain API Key management unchanged.
- [x] **Resilience**: Graceful fallback if batch translation fails.

## Proposed Changes

### Layer 1: Services & Networking
#### [MODIFY] [HNClient.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Services/HNClient.swift)
- Add `fetchMultiFeedIds(types: [StoryType])` to fetch and deduplicate IDs across Top, New, and Best feeds.

#### [MODIFY] [AIService.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Services/AIService.swift)
- Adjust `batchSize` default limit for title translation to 25 items per request for higher throughput and reduced API token overhead.

### Layer 2: ViewModels & Logic
#### [MODIFY] [FeedViewModel.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/ViewModels/FeedViewModel.swift)
- Increase `pageSize` to 40 items.
- Implement multi-feed prefetching (`prefetchPrimaryFeeds()`).
- Implement data-driven background AI title translation batch pipeline (`processBatchTranslations()`).

### Layer 3: Views
#### [MODIFY] [FeedView.swift](file:///Users/corlin/appdev/HNEveryDay/HNEveryDay/Views/FeedView.swift)
- Simplify view translation triggering by prioritizing local cache reads and delegating batch prefetching to `FeedViewModel`.

## Verification Plan

### Automated Tests
- Build project using Xcode command line.
- Execute unit test target `HNEveryDayTests` to ensure zero regressions.

### Manual Verification
- Verify 0ms tab switching between Top, New, and Best.
- Confirm Chinese translations populate in bulk without UI scrolling delays.
