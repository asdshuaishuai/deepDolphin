// Backend.h — 平台层：**执行**后端差异（PLAN §9 M1-7）。
//
// 【这一层收口三件事】
//   ① **托盘弹窗定位** —— 以前只在 `TrayPopupWindow::popupNear` 里现算，
//      取不到托盘几何时靠一个写死的 1280×720 兜底；现在统一走
//      `trayPopupTarget()`，落点算法在判定层（`logic/Backend`）。
//   ② **窗口激活** —— 以前 8 处各写一遍 `show(); raise(); activateWindow();`，
//      且**都叫不醒最小化的窗口**（实测：`show()` 不会恢复最小化态）⇒
//      统一走 `activate()`，一处修一处生效。
//   ③ **任务栏几何** —— 以前「屏幕可用区」在托盘弹窗里现取，现由
//      `availableGeometryAt()` / `taskbarInsetsAt()` 统一给。
//
// 【为什么判定与执行要分层】
//   `--selfcheck` 跑在 `QGuiApplication` 构造**之前** ⇒ 落点算法、激活动作计划
//   这类**结论**必须能在无应用对象时算出来（放判定层 `logic/Backend`）；
//   真碰 QWidget/QScreen 的**动作**放这一层。
//   ⇒ 结论可离线测（判据），动作靠探针 + 接线门（可见面）。
#pragma once

#include "../logic/Backend.h"

#include <QPoint>
#include <QRect>
#include <QSize>
#include <QString>

class QSystemTrayIcon;
class QWidget;

namespace platform {

/// 后端分档（判定层的类型）。
/// ⚠ 用别名而不是直接写 `Backend::Kind`：本层所在命名空间叫 `platform`，
///   而分档类型住在全局命名空间的 `Backend` 里 —— 写全名啰嗦，
///   起别名还能避开将来出现 `platform::Backend` 时的名字遮蔽。
using BackendKind = ::Backend::Kind;

/// 当前显示后端（判 `QGuiApplication::platformName()`）。
BackendKind current();

/// 当前 QPA 插件名（原样，探针报；离屏是 "offscreen"）。
QString currentName();

/// 当前是不是 Wayland。
bool isWayland();

/// 窗口激活（**唯一入口**）。
///
/// 做了什么、为什么：
/// · 最小化时**只摘掉最小化位**再 show —— `show()` 不会把最小化的窗口拉回来
///   （实测：离屏 + xcb 两种后端，show() 之后仍是 minimized ⇒ 从托盘叫醒面板
///   「点了跟没点一样」）。
/// · **不用 `showNormal()`** —— 它会顺带清掉最大化位（实测）⇒ 用户把面板最大化着，
///   从托盘叫醒时会被打回普通大小。
/// · Wayland 走 `windowHandle()->requestActivate()`（`activateWindow()` 在 Wayland
///   上不可靠）；Wayland 上 `raise()` 是空操作（叠放次序归合成器），故不调。
void activate(QWidget *w);

/// 托盘图标几何（**已判可用性**）：不可用时返回**空矩形**。
///
/// ⚠ Wayland 上 `QSystemTrayIcon::geometry()` 常返回无效矩形（托盘由合成器托管，
///   客户端拿不到坐标）⇒ 直接拿它定位 = 弹窗飞到屏幕左上。
///   这里统一判一次，调用方拿到的要么是真几何、要么是空矩形。
QRect trayIconGeometry(const QSystemTrayIcon *icon);

/// 锚点所在屏幕的**可用区**（已扣掉面板/任务栏）。
/// 取不到屏幕时返回空矩形（不猜分辨率）。
QRect availableGeometryAt(const QPoint &anchor);

/// 锚点所在屏幕的**整块**矩形（**未**扣面板/任务栏）。
///
/// ⚠ 与 `availableGeometryAt()` 的区别就是「扣没扣面板」——
///   面板真几何要拿整屏去算「扣掉它之后还剩哪块」⇒ 两个都要。
QRect screenGeometryAt(const QPoint &anchor);

/// 锚点所在屏幕被面板/任务栏占掉的边距（**任务栏几何**）。
Backend::Insets taskbarInsetsAt(const QPoint &anchor);

/// 托盘弹窗落点（收口定位）。
/// @param trayIconGeometry 托盘图标几何（宽高非正 = 不可用 ⇒ 落屏幕右上）。
/// @param popupSize        弹窗尺寸。
/// @param geo              定位参数（数值出自托盘域 token，本层不拥有）。
QRect trayPopupTarget(const QRect &trayIconGeometry, const QSize &popupSize,
                       const Backend::PopupGeometry &geo);

} // namespace platform
