# Feature Specification: UI/UX & Motion Polish (ui-ux-motion-polish)

## Overview & User Value
- **Summary**: Comprehensive UI/UX experience and fluid motion refactor for HNEveryDay, incorporating Apple Design principles (WWDC Designing Fluid Interfaces) and Emil Kowalski's Design Engineering polish.
- **Target Experience**: Elevate touch responsiveness, spring physics interruptibility, translucency materials, and optical typography to create a tactile, ultra-fluid 120fps native iOS Hacker News client.

## Clarifications

### Session 2026-07-23 (Apple Design Review)
- Q: 模态视图 (Sheet/Summary) 拖拽手势与中途打断控制如何设定？ → A: **Option A (物理弹性 + 速度继承 + 随心打断)**：支持手势中途任意时刻抓取反转，释放时继承手指惯性速度，背景层施加渐进式毛玻璃压暗与深度下压。
- Q: 毛玻璃材质层之上的排版层次与 Vibrancy 可读性如何设计？ → A: **Option A (语义化 Vibrancy 强化 + 光学字距微调)**：大标题紧凑字距 `-0.2pt`，等宽元数据扩展 `+0.1pt`，配合系统语义文本层次，在各种毛玻璃与深色背景下均具备极致可读性。
- Q: 触觉反馈与物理因果律如何调校？ → A: **Option A (帧同步 + 三级物理质感区分)**：视觉与触觉同帧触发，评论折叠 (Light Impact)、文章收藏 (Medium Impact) 与 AI 完成 (Success Notification) 使用三级不同强度的物理触感。
- Q: 空间一致性与源锚点过渡如何约束？ → A: **Option A (源锚点展开 + 对称路径归位)**：动画从触发控件的原点位置展开与退回，空间路径完全对称，直观反映 UI 层级关系。
- Q: 减弱动态效果与透明度降级无障碍如何适配？ → A: **Option A (系统无障碍优雅降级)**：实时响应系统偏好，在开启 `Reduce Motion` 时自动淡出，开启 `Reduce Transparency` 时自动降级为高对比实色背景。

## Requirements

### Functional Requirements
- **FR-1 (Touch Responsiveness)**: All interactive list rows and buttons MUST provide immediate touch down feedback via `.scaleEffect(0.978)` without release latency.
- **FR-2 (Interruptible Physics)**: Comment tree collapsing and sheet modal transitions MUST use Apple-damped spring physics (`stiffness: 300, damping: 28`) supporting mid-motion interruption and velocity handoff.
- **FR-3 (Vibrancy & Materials)**: AI Summary and Reader views MUST utilize Apple liquid glass materials (`.ultraThinMaterial`) with light-catching top border highlights and high-contrast semantic typography.
- **FR-4 (Optical Typography)**: Typography MUST apply optical tracking (-0.2pt for titles >=15pt, +0.1pt for monospaced metadata <=11pt).
- **FR-5 (Physical Haptics)**: Sensory feedback (Haptics) MUST trigger on the exact frame of state change using distinct physical intensities (Light for collapse, Medium for save, Success Notification for AI completion).
- **FR-6 (Spatial Consistency)**: Expanded cards and popovers MUST anchor their origin (`transform-origin`) to the trigger control and dismiss along a symmetric path.
- **FR-7 (Accessibility Adaptability)**: System `prefers-reduced-motion` MUST cross-fade without bounce; `prefers-reduced-transparency` MUST fall back to solid high-contrast cards.

### Non-Functional Requirements (Constitution Compliance)
- **NFR-1 (Architecture)**: All design tokens MUST be centralized in `DesignSystem.swift`. Views MUST remain declarative and light.
- **NFR-2 (Performance)**: MUST maintain 120fps scrolling and off-main-thread transform/opacity rendering.
- **NFR-3 (Privacy)**: No telemetry or analytics added.
- **NFR-4 (Resilience)**: Smooth error recovery and fallback states preserved.

## User Interface & Interactions
- Instant touch down scale down (0.978) + scale up on release.
- Fluid, interruptible comment sub-tree fold/unfold animation.
- Translucent backdrop materials with light catching top borders.
- Three-tier haptic feedback tuned for physical causality.
- Trigger-anchored spatial expansion and symmetric dismissal.

## Out of Scope
- Backend API schema changes.
- Database migration.
