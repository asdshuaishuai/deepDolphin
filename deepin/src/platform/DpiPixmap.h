#pragma once
// DpiPixmap.h — **HiDPI 感知的自绘位图**（批 AP · M3c HiDPI）
//
// 【为什么需要它】
// 我们有 9 处用 QPainter **自己画**小图形（状态点 / 迷你条 / 托盘图标 / 里程碑图标）。
// 原来它们都这么写：
//     QPixmap pm(8, 8);           // ← 8×8 **设备**像素
//     pm.fill(Qt::transparent);
//     QPainter p(&pm); p.drawEllipse(0, 0, 8, 8);
//
// 在 dpr=1（100%）下没问题；但控制中心把缩放调到 **125%/150%/200%** 时：
//   · 这张 8×8 的位图**只有 8×8 设备像素**，而控件要画的是 8 **逻辑**像素
//     （= 16 设备像素）⇒ 位图被**放大** ⇒ 圆点边缘锯齿、**发虚**。
//   实测（dpr=2）：1x 路径画出的圆点只有 **6 层**半透明过渡像素（块状），
//   而按 dpr 放大后画的是 **50 层**（平滑）⇒ 差别是可量化的，不是"看着有点糊"。
//
// 【修法】
// 用本文件提供的 `platform::dpiPixmap(logicalSize)`：
//   · 缓冲区按 **logicalSize × dpr** 开；
//   · `setDevicePixelRatio(dpr)` ⇒ QPainter 在它上面**仍用逻辑坐标**画
//     （Qt 自动按 dpr 缩放坐标系）⇒ 画出来的图形是**按 dpr 分辨率**渲染的。
// ⇒ 图形尺寸（逻辑）不变，但像素密度对了 ⇒ HiDPI 下不发虚。
//
// 【与 platform::icon() 的分工（别混）】
//   · `platform::icon()` 走**图标主题**（DDci / 主题 / qrc 染色）——那边**自己**按 dpr 取图
//     （见 `IconResolver.cpp` 的 `fromDci`：`dci.pixmap(dpr, …)` + `setDevicePixelRatio(dpr)`）。
//   · 本文件只管**我们自己用 QPainter 画**的位图（主题里没有的那些）。
//
// ⚠ 调用前提：必须有 QGuiApplication（QPixmap 本身就需要）。
//   `--selfcheck` 跑在 **GUI app 构造之前**（main.cpp 无头分支）⇒ 那里不能用本文件。
#include <QPixmap>
#include <QSize>

namespace platform {

/// 当前 devicePixelRatio（没有 QGuiApplication 时按 1.0 —— 不猜）。
qreal devicePixelRatio();

/// 造一张**按 dpr 放大**的透明 QPixmap。
///   · `logicalSize` 是**逻辑**尺寸（控件该占多大）；
///   · 返回值的**缓冲区**是 logicalSize × dpr，`devicePixelRatio()` 已是 dpr；
///   · 在它上面用 QPainter 画时**仍写逻辑坐标**（Qt 自动缩放）⇒ 图形不发虚。
QPixmap dpiPixmap(const QSize &logicalSize);

} // namespace platform
