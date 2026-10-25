# HNEveryDay (极客版)

<p align="center">
  <img src="HNEveryDay/Assets.xcassets/AppIcon.appiconset/HNEveryDay_Icon.png" width="120" alt="HNEveryDay Icon" />
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README_ZH.md">简体中文</a>
</p>

**HNEveryDay** 是一款高性能、隐私优先、AI 增强的 iOS Hacker News 客户端，专为那些以终端为家、以代码为梦的极客们打造。

它结合了黑客们钟爱的信息密度与现代原生 iOS 应用的流畅触感体验。

---

## ✨ 功能特性

### 🚀 极致性能与超大批次 AI 管线 (v0.06)
- **120fps 滚动**：优化的 SwiftUI 列表，处理数千条目毫不掉帧。
- **多频道并发预拉取**：启动/刷新时自动并发预拉取并去重 `Top`、`New` 和 `Best` 三大频道（约 60-80 条独特文章），实现频道切换零延迟。
- **50 条/次超大批次 AI 翻译管线**：将标题翻译收拢为 50 条/次合并发送，降低 API 调用频次 80% 以上，大幅节省 Token 费用。
- **在途请求合流屏障 (Task Coalescing)**：Actor 级在途屏障自动拦截并合并相同批次的并发请求，杜绝重复 API 调用。
- **缓存优先 SwiftData 存储**：翻译结果自动落库，UI 100% 优先读取本地缓存，消除逐行防抖等待。

### 🎨 Apple Design 与触感设计
- **AppTheme 设计系统**：符合 Apple 物理弹性动画（`stiffness: 300, damping: 28`）、触感反馈（`.buttonStyle(.tactile)`）与光学字距微调。
- **毛玻璃与质感设计**：采用 `.ultraThinMaterial` 材质与 10pt 圆角卡片，呈现精致极客视觉。

### 💬 深度讨论区
- **递归嵌套**：通过清晰的缩进可视化 HN 评论的深层嵌套。
- **可折叠评论**：点击任意评论即可折叠整个子树，过滤噪音。
- **富文本渲染**：完整支持 HN HTML 评论（斜体、代码块、链接）。

### 🤖 本地优先的 AI 智能
秒级获取“黑客视角”：
- **智能总结**：点击 ✨ 按钮，生成 **文章 + 热门讨论** 的精炼摘要。
- **自带密钥 (BYO Key)**：无需订阅，默认预设 DeepSeek，使用您自己的 API Key。
- **多服务商支持**：内置国内外主流模型预设：
  - 🇨🇳 **DeepSeek**（推荐，默认模型：`deepseek-flash`）
  - 🇨🇳 **通义千问 (Qwen)**
  - 🇨🇳 **智谱 ChatGLM**
  - 🇨🇳 **字节豆包**
  - 🇺🇸 **Gemini**（通过 OpenAI 兼容接口）
  - 🇺🇸 **OpenAI** (GPT-4o/mini)
  - 🏠 **本地部署**（支持 Ollama/LM Studio）

### 📖 原生智能阅读器
- **无干扰模式**：移除广告与杂乱内容。
- **极客风格**：深色模式验证；代码块使用等宽字体并支持横向滚动。
- **离线就绪**：自动缓存文章内容，地铁阅读无忧。

### 🧠 知识引擎
- **Markdown 导出**：一键生成格式化的研究笔记。
- **深度上下文**：导出包含元数据、AI 摘要和精选评论，完美适配 Obsidian/Notion。
- **阅读历史**：自动追踪已读内容（灰色链接标记）。

### 🌏 国际化
- **中文支持**：完整的简体中文 UI 本地化。
- **多语言 AI 阅读**：AI 摘要与翻译支持英文、简体中文、繁体中文、日文、韩文、西班牙文、法文、德文、葡萄牙文和俄文。

### 🔖 收藏与钥匙串安全
- **收藏与快捷操作**：左滑保存文章，或左滑快速触发单条标题翻译。
- **钥匙串安全**：API 密钥存储于 iOS Keychain（非 UserDefaults）。

---

## 🛠 技术栈

- **语言**：Swift 6 严格并发模式 (Strict Concurrency Mode)
- **UI 框架**：SwiftUI（部署目标：iOS 18.6）
- **持久化**：**SwiftData** + 优化的"读穿"缓存策略
- **并发**：Swift `async/await`，`Actor`（`TaskCoalescer`），`@Sendable` 线程安全
- **状态管理**：MVVM + `ObservableObject` 与 SwiftUI 视图状态
- **网络**：基于 `URLSession` 的自定义封装，对接 Hacker News Firebase API

---

## ⚙️ 配置说明

### 设置 AI 服务
1. 点击主界面的 **齿轮图标** (⚙️)
2. 选择 **服务商预设**（如 DeepSeek）
   - *应用会自动填充正确的 Base URL 和模型名称*
3. 粘贴您的 **API 密钥**，应用不会内置服务商密钥
4. （可选）手动编辑模型名称以使用特定版本，默认模型为 `deepseek-flash`
5. 点击 **完成**，密钥安全存储于设备钥匙串中

---

## 📥 安装

1. 克隆仓库：
   ```bash
   git clone https://github.com/corlin/HNEveryDay.git
   ```
2. 使用支持 iOS 18+ 的 Xcode 打开 `HNEveryDay.xcodeproj`（已用 Xcode 26.5 验证）
3. 在 iPhone 或模拟器上构建运行

---

## ✅ 测试

使用可用的 iOS 模拟器运行单元测试：

```bash
xcodebuild test -project HNEveryDay.xcodeproj -scheme HNEveryDay -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

---

## 📄 许可证

MIT License. Hacking is for everyone.
