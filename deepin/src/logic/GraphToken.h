// GraphToken.h — 场景颜色 token 的解析（纯函数层，零 QWidget 头）。
//
// 【契约】引擎 themes 里的颜色是 **token**，不是色值。四类形态：
//   ① "text" / "muted" / "bg0" …   → themes.<主题> 直取
//   ② "cols.N" / "fills.N"         → themes.<主题>.cols / fills 数组下标
//   ③ "langs.<lang>"               → themes.<主题>.langs 字典
//   ④ "node:<id>"                  → **二跳**：视图级 nodeTheme[<id>] 得再一个 token，递归解析
//
// 【红线】
// · 未知 token = **引擎违约**（契约原话）。显式洋红兜底 —— 绝不静默当黑、
//   也不静默融进背景（mac GraphScene.swift 同款纪律）。
// · 二跳的结果必然落在前三类；查不到时回落 "text"（不是洋红 —— 那是「图上没有这个节点」，
//   不是「引擎发了坏 token」）。
// · 引擎的 colors 两种形态都有：#hex（cols）与 rgba()（fills），两种都要收。
#pragma once
#include <QColor>
#include <QString>
#include "../models/GraphScene.h"

namespace GraphToken {

/// token → 颜色字符串（引擎原样：#hex / rgba()）。violation=true = 未知 token（引擎违约）。
struct Resolved {
    QString value;
    bool violation = false;
};

/// 解析一个 token。view 可为 nullptr（二跳时传 nullptr，见契约）。
Resolved resolve(const GraphThemeTokens &theme, const QString &token, const GraphView *view);

/// 便捷：直接给 QColor。未知 token 走洋红兜底。
QColor color(const GraphThemeTokens &theme, const QString &token, const GraphView *view);

/// "#RRGGBB" / "#RRGGBBAA" / "#RGB" / "rgba(r,g,b,a)" → QColor。
/// 解析不了 → 洋红（同「坏 token 显式兜底」纪律，不静默当黑）。
QColor toColor(const QString &hexOrRgba);

/// 洋红兜底色（引擎违约的显式信号）。
QColor violationColor();

} // namespace GraphToken
