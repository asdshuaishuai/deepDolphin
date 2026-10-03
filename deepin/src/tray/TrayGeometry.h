// TrayGeometry.h — 托盘层几何 token 的收口（M3-7；plan R1 的托盘分册：
// 几何只准落在 DesignTokens/platform/Thresholds 与本头，其余地方只准消费）。
//
// 【取舍】
// · 不并入 ui/DesignTokens.h：弹窗宽/列宽/行距是**托盘域私有**几何，不是全应用的
//   视觉语言（间距刻度/圆角档/字阶归 DS::*）——分开放避免 ui token 被域私有点撑爆；
// · 全是 constexpr 数值、零颜色（tray 层不持色值，纪律同决策 72）；
// · TrayController 感叹三角/感叹点是**一次性占位绘制坐标**（dd-*.svg 就位后整个
//   painter 会被替换，见 TrayController.cpp 注），不收编——给单调用点坐标逐一起名
//   只添间接层；画布/外环/内芯这三个有「尺寸身份」的量才进 token。
#pragma once

namespace TrayGeometry {

// ── 速览弹窗（TrayPopupWindow）──
constexpr int popupWidth = 380;   // 弹窗固定宽（PLAN §6/§2.7）
constexpr int maxRows = 12;       // 平铺 prefix(12)，不用滚动区（ScrollView 塌缩教训）
constexpr int outerMargin = 12;   // 根布局四周留白
constexpr int rootSpacing = 8;    // 根布局行距
constexpr int bodySpacing = 4;    // 项目行之间的间距
constexpr int rowMarginV = 2;     // 项目行内上下留白
constexpr int rowSpacing = 6;     // 项目行内控件间距
constexpr int nameWidth = 120;    // 项目名列固定宽
constexpr int miniBarWidth = 44;  // 行尾迷你进度条宽（高 = DS::Height::barMini）
constexpr int pendingBarCap = 10; // 迷你条满宽档位：宽 × min(pending, 10) / 10

// ── 弹窗定位（popupNear；取不到托盘几何 → 屏幕右上，PLAN §8 T4）──
constexpr int dockGap = 8;      // 贴托盘图标 / 贴屏幕左边的间隙
constexpr int edgeMargin = 16;  // 底边兜底留白
constexpr int fallbackDx = -16; // 屏幕右上落点偏移
constexpr int fallbackDy = 32;

// ── 托盘图标占位绘制（TrayController::tintedIcon）──
constexpr int iconCanvas = 32;    // 画布边长
constexpr int iconRingInset = 4;  // 外环内缩（直径 = canvas − 2×inset = 24）
constexpr int iconCoreInset = 11; // 内芯内缩（直径 = canvas − 2×inset = 10）

} // namespace TrayGeometry
