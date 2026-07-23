# Feature Specification: Batch Data Fetching & AI Translation Pipeline (batch-translation-and-fetching)

## Overview & User Value
- **Summary**: High-throughput data prefetching and batch AI title translation pipeline for HNEveryDay. Replaces low-capacity, view-driven translation triggers with a unified super-batch background pipeline to reduce API calls by >80%, lower AI token costs, and provide instantaneous tab switching.
- **Target Experience**: Zero-latency switching across Hacker News channels with pre-translated Chinese titles cached locally in SwiftData.

## Clarifications

### Session 2026-07-23 (Round 1)
- Q: 针对数据拉取与 AI 标题翻译调度逻辑，如何降低调度频次与费用并提高系统吞吐量？ → A: **Option A (数据驱动预加载 + 集中大批次后台翻译)**：将单页拉取扩至 40-50 条，数据获取后自动在后台触发大批次 AI 集中翻译并入库，UI 零等待直接读本地缓存。
- Q: 不同类型的数据 (Top, New, Best, Show, Ask, Jobs) 如何预拉取，范围如何设定？ → A: **Option A (主力频道 Top/New/Best 预拉取)**：启动/刷新时预拉取并去重 Top、New、Best 三大主频道前 40 条（约 60-80 条独特文章），集中完成大批次 AI 翻译并存储。

### Session 2026-07-23 (Round 2)
- Q: 再次综合评估模型调用频率，如何压缩调用频率并加大单次批量？ → A: **Option A (50条/次超大批次 + 清理 View 层防抖)**：彻底废弃 `FeedView` 层零散的 `.task` 350ms 防抖队列，统一由 `FeedViewModel` / `AIService` 将未翻译标题拆分为 **50 条/次** 超大 Batch，一次性合并发送 API，频次降低 80%+。
- Q: AI 摘要与全文翻译如何防重调用？ → A: **Option A (Task Coalescing 在途合流屏障 + 全局缓存)**：在 `AIService` 中增加 Task Coalescing 机制，在途请求自动合流，彻底杜绝重复 API 调用，结果 100% 自动入库复用。

## Requirements

### Functional Requirements
- **FR-1 (Multi-Feed Prefetching)**: Upon app launch or feed refresh, the system MUST concurrently fetch story IDs for `Top`, `New`, and `Best` feeds (top 40 IDs per feed), merge and deduplicate them into a unique set (~60-80 stories).
- **FR-2 (Batch Item Fetching)**: The system MUST fetch story item metadata in concurrent batches using `HNClient.shared.fetchItems(ids:)` with an increased page capacity of 50 items per page.
- **FR-3 (Super-Batch 50-Item Translation Pipeline)**: The background pipeline MUST group untranslated story titles into 50-item super-batches per API request. View-driven scattered debounce queues MUST be removed.
- **FR-4 (Task Coalescing & In-Flight Coalescing Barrier)**: `AIService` MUST implement Task Coalescing for in-flight requests to ensure duplicate concurrent calls for the same item/batch share a single active task.
- **FR-5 (Cache-First UI Rendering)**: All translated titles MUST be persisted into SwiftData via `DataService`. Views MUST load translations 100% directly from local cache without triggering per-row UI debounce delays.
- **FR-6 (Resilience & Fallback)**: If a batch AI translation request fails, individual items MUST retain their original titles without breaking the feed or blocking subsequent pages.

### Non-Functional Requirements (Constitution Compliance)
- **NFR-1 (Architecture)**: All fetching and translation orchestration MUST occur within `FeedViewModel` / `AIService` background tasks. Views MUST remain purely declarative.
- **NFR-2 (Performance)**: Feed scrolling MUST remain 120fps smooth; network parsing and AI JSON processing MUST run off `@MainActor`.
- **NFR-3 (Cost & Efficiency)**: API call frequency MUST be compressed by >80% by utilizing 50-title super-batch requests instead of small UI debounces.
- **NFR-4 (Privacy & Security)**: API Keys for AI provider MUST continue to be retrieved securely from iOS Keychain.

## Data Model & Flow
1. `HNClient` fetches `topstories.json`, `newstories.json`, `beststories.json` concurrently.
2. `Set<Int>` deduplication produces unique `storyIDs`.
3. Parallel HTTP batch fetching yields `[HNItem]`.
4. `AIService.translateTitles` executes super-batch request (50 titles/batch).
5. Task Coalescing prevents duplicate in-flight requests.
6. Results saved to `DataService` (SwiftData) -> UI updates reactively.

## Out of Scope
- Unnecessary background translation for feeds disabled by user settings.
