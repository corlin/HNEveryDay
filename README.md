# HNEveryDay (Geeker Edition)

<p align="center">
  <img src="HNEveryDay/Assets.xcassets/AppIcon.appiconset/HNEveryDay_Icon.png" width="120" alt="HNEveryDay Icon" />
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README_ZH.md">简体中文</a>
</p>

**HNEveryDay** is a high-performance, privacy-first, AI-enhanced Hacker News client for iOS, built specifically for Geekers who live in the terminal and dream in code.

It combines the raw information density favored by hackers with the fluid, tactile experience of a modern native iOS app.

---

## ✨ Features

### 🚀 Extreme Performance & Super-Batch Pipeline (v0.06)
- **120fps Scrolling**: Built with optimized SwiftUI lists to handle thousands of items without dropping a frame.
- **Multi-Feed Concurrent Prefetching**: Concurrently fetches and deduplicates `Top`, `New`, and `Best` feeds upon launch/refresh for instant tab switching with zero delay.
- **50-Item Super-Batch AI Pipeline**: Merges title translations into unified 50-item super-batches per API request, cutting API call frequency by >80% and drastically saving token costs.
- **Task Coalescing In-Flight Barrier**: In-flight actor coalescing barrier ensures duplicate concurrent requests for identical items never trigger double API calls.
- **Cache-First SwiftData Storage**: All translations are persisted in SwiftData; UI loads 100% directly from local cache with zero per-row debounce latency.

### 🎨 Apple Design & Tactile Motion Polish
- **AppTheme Design System**: Custom fluid spring physics (`stiffness: 300, damping: 28`), tactile haptic feedback (`.buttonStyle(.tactile)`), and optical typography tracking.
- **Glassmorphism Aesthetic**: Materials like `.ultraThinMaterial` and refined 10pt corner radius card designs.

### 💬 Deep Discussion Threads
- **Recursive Threading**: Visualizes the deep nesting of HN comments with clear, color-coded indentation.
- **Collapsible Threads**: **Tap any comment** to fold its entire subtree. Cleaning up the noise to find the signal has never been easier.
- **Rich Text Rendering**: Full support for HN's HTML comments (italics, code blocks, links) rendered natively.

### 🤖 Local-First AI Intelligence
Get the "Hacker Perspective" in seconds.
- **Magic Summary**: Tap the ✨ button to generate a concise summary of the **Article + Top Discussion**. We don't just summarize the link; we summarize *what hackers are saying about it*.
- **BYO Key (Bring Your Own Key)**: No subscriptions. DeepSeek is preselected by default, but you still use your own API key.
- **Multi-Provider Support**: Built-in presets for the best Global and Chinese models:
    - 🇨🇳 **DeepSeek** (Recommended for coding/tech context, default: `deepseek-flash`)
    - 🇨🇳 **Qwen (Tongyi Qianwen)**
    - 🇨🇳 **ChatGLM (Zhipu)**
    - 🇨🇳 **Doubao (ByteDance)**
    - 🇺🇸 **Gemini** (via OpenAI Compatibility)
    - 🇺🇸 **OpenAI** (GPT-4o/mini)
    - 🏠 **Localhost** (Ollama/LM Studio support)

### 📖 Native Smart Reader
- **Distraction Free**: Removes ads, popups, and clutter. Just the text.
- **Geeker Styled**: Dark mode verified; Code blocks rendered with monospaced fonts and horizontal scrolling.
- **Offline Ready**: Automatically caches article content for subway reading.

### 🧠 Knowledge Engine
- **Markdown Export**: Share -> "Square & Arrow" -> Generates a formatted research note.
- **Deep Context**: Export includes Metadata, AI Summary, and Key Comments. Perfect for Obsidian/Notion.
- **Read History**: Automatically tracks what you've read (Gray links).

### 🌏 Globalization
- **Chinese Support**: Full UI localization for Simplified Chinese (简体中文).
- **Multilingual AI Reading**: AI summaries and translations support English, Simplified/Traditional Chinese, Japanese, Korean, Spanish, French, German, Portuguese, and Russian.

### 🔖 Bookmarks & Keychain Security
- **Bookmarks**: Swipe left to save stories for later, or swipe left for quick manual title translation.
- **Keychain Security**: API keys are stored in iOS Keychain (not UserDefaults).

---

## 🛠 Tech Stack

- **Language**: Swift 6 Strict Concurrency Mode
- **UI Framework**: SwiftUI (iOS 18.6 deployment target)
- **Persistence**: **SwiftData** with optimized "Read-Through" caching.
- **Concurrency**: Swift `async/await`, `Actors` (`TaskCoalescer`), `@Sendable` safe execution.
- **State Management**: MVVM with `ObservableObject` and SwiftUI view state.
- **Networking**: Custom `URLSession` wrapper interacting with Hacker News Firebase API.

---

## ⚙️ Configuration

### Setting up AI
1. Tap the **Gear Icon** (⚙️) on the main feed.
2. Select your **Provider Preset** (e.g., DeepSeek).
    - *The App automatically fills the correct Base URL and Model Name.*
3. Paste your **API Key**. The app never bundles provider secrets.
4. (Optional) You can manually edit the Model Name to use specific versions (default: `deepseek-flash`).
5. Tap **Done**. Keys are stored securely on-device using iOS Keychain.

---

## 📥 Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/corlin/HNEveryDay.git
   ```
2. Open `HNEveryDay.xcodeproj` in a recent Xcode supporting iOS 18+. Verified with Xcode 26.5.
3. Build and Run on your iPhone or Simulator.

---

## ✅ Testing

Run the unit test target with an available iOS Simulator:

```bash
xcodebuild test -project HNEveryDay.xcodeproj -scheme HNEveryDay -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

---

## 📄 License

MIT License. Hacking is for everyone.
