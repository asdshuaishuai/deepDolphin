// IconResolver.h — 图标**统一入口**（平台层执行，PLAN §9 M1-2）。
//
// 【为什么统一】
//   M1-2 之前，图标名散在 11 处 UI 代码里（`QIcon::fromTheme("…")`），
//   解析不到时**静默变成空图标** —— 没人知道是哪个名字没的（空门）。
//   ⇒ 全部走本文件：候选链在判定层（`logic/IconNames`），本层只管**执行**与**报缺失**。
//
// 【解析顺序】
//   ① **DDci 优先**（deepin 自己的图标集，真机观感最好）；
//   ② freedesktop **主题图标**；
//   ③ **qrc 染色兜底**（`dd-*` 的 currentColor SVG，免安装也能用；需 Qt6Svg）；
//   ④ 全落空 ⇒ **缺失告警**（qWarning + 记入 missingIcons()）+ tint 圆点占位
//      —— 宁可显形为占位，也不假装是某个具体符号。
#pragma once

#include "../logic/IconNames.h"

#include <QIcon>
#include <QSize>
#include <QString>
#include <QStringList>

namespace platform {

/// 取图标（统一入口）。
/// @param id   逻辑图标（`IconNames::Id` 枚举 —— 拼错编译不过）
/// @param size 目标尺寸（像素）
/// @param tint 占位/染色用的颜色（无效时用兜底灰）
QIcon icon(IconNames::Id id, const QSize &size = QSize(16, 16), const QColor &tint = QColor());

/// 解析来源（给探针/自检看）：`dci` / `theme` / `qrc` / `none` / `missing`。
///   `none` = 这台机器**没有图标主题**（环境事实，不是图标名错）；
///   `missing` = 环境有主题但这个名字解析不到（**我们的问题** ⇒ 已告警 + 占位）。
QString resolveSource(IconNames::Id id, const QSize &size = QSize(16, 16));

/// 解析过但**没找到**的逻辑图标名（缺失告警的可见面；去重、保序）。
QStringList missingIcons();

} // namespace platform
