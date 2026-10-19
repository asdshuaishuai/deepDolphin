// SemColors.h — **与主题无关的固定色**的唯一出处（判定层，纯数据、零 UI 依赖）。
//
// 【为什么不在 ui/DesignTokens.h】
//   ① `DS::semColor()` 里有一档 `accent` 要接 **DTK 主题强调色**
//      （DGuiApplicationHelper，ui 层的东西）—— 判定层不能碰它；
//   ② 判定层（`logic/Derived.cpp` 的 livenessColor / branchStatusColor / statTint）
//      要返回 QColor，它**不能依赖 ui 层**（纪律：`logic/` 零 UI 依赖）；
//   ③ 托盘（`tray/`）与平台层（`platform/IconLoader`）也要用同一批色 —— 它们
//      各自写字面量 = 同一个语义多份定义。
//   ⇒ 纯色值下沉到判定层，`DS::semColor()` **转发**过来（见 ui/DesignTokens.cpp），
//     全仓一份出处。
//
// 【分层对位 mac】
//   mac 的 `DesignTokens.swift` 是**纯函数层**（零 SwiftUI 依赖），
//   `DesignSystem.swift`（视图层）才把语义名变成颜色。本文件对位前者。
//
// 【⚠ 取值纪律】
//   这里的值是**已对齐 mac 的既有取值**，不是随手调的。改这里 = 改全 app 观感，
//   须走「跨端取值对齐」那一批（会动视觉基线），不许在别的批次里顺手改。
#pragma once
#include <QColor>

/// 状态语义色 —— 承载**跨页一致的状态语义**（不是皮肤）。
/// 取值承接 mac 的 tailwind 色板（`DSPalette`），状态档位见 mac `Models.swift`
/// 的 `StatusColor.systemColor`（active 绿 / idle 黄 / stale 红 / merged 紫 / 灰）。
namespace SemColors {
inline QColor shallow() { return QColor(0x10, 0xB9, 0x81); } ///< 绿 #10B981 · 浅更新轨 / 活跃
inline QColor deep() { return QColor(0x8B, 0x5C, 0xF6); }    ///< 紫 #8B5CF6 · 深更新轨 / 已合并
inline QColor ai() { return QColor(0x06, 0xB6, 0xD4); }      ///< 青 #06B6D4 · AI
inline QColor orange() { return QColor(0xF5, 0x9E, 0x0B); }  ///< 橙 #F59E0B · needsAction / 量级中档
inline QColor red() { return QColor(0xDC, 0x26, 0x26); }     ///< 红 #DC2626 · 错误 / 量级高档
inline QColor yellow() { return QColor(0xE8, 0xB0, 0x1C); }  ///< 黄 #E8B01C · idle / 量级低档
inline QColor gray() { return QColor(0x9C, 0xA3, 0xAF); }    ///< 灰 #9CA3AF · unknown

/// **陈旧红**（#EF4444）：分支 `stale` / 引擎停滞 / 久未更新。
/// ⚠ 与 `red()`（#DC2626）是**两档不同的红**，不是笔误：
///   `red` = 错误/危险（量级高档、读不出来）；`stale` = 陈旧/停滞（分支状态）。
///   mac 的 `StatusColor.systemColor` 把 `stale` 映射成 red，故这档红是**语义**不是皮肤。
inline QColor stale() { return QColor(0xEF, 0x44, 0x44); }
} // namespace SemColors

/// 与状态语义无关的**固定色**（不随主题改写）。
namespace FixedColors {
inline QColor iconFallback() { return QColor(0x88, 0x88, 0x88); } ///< 图标 tint 兜底灰
inline QColor trayAccent() { return QColor(0x1E, 0x6F, 0xEB); }   ///< 托盘强调蓝
/// 托盘迷你进度条的**底轨遮罩**（中性灰 60/255）。
/// ⚠ 与 `DS::trackMask()`（分段条底轨遮罩，灰 **40**/255）是**同语义不同档** ——
///   迷你条更小、底轨要更重才看得见。跨端取值对齐那一批要核对这两档该不该统一。
inline QColor trayBarTrack() { return QColor(128, 128, 128, 60); }
} // namespace FixedColors
