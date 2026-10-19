// Backend.h — 平台后端判定的**唯一出处**（判定层：纯函数、零 UI 依赖）。
//
// 【为什么要有它】
//   M1-7 之前，「现在跑在 X11 还是 Wayland」「窗口怎么叫醒」「托盘弹窗落哪」
//   这三件事**没有共同出处**：窗口激活在 8 处各写一遍 `show(); raise(); activateWindow();`，
//   托盘弹窗定位只在 `TrayPopupWindow::popupNear` 里现算，后端差异无处安放。
//   ⇒ 收成一层：判定层（本文件）给**结论**，平台层（`platform/Backend.h`）去**执行**。
//
// 【为什么判定层要纯】
//   `--selfcheck` 跑在 `QGuiApplication` 构造**之前**（main.cpp 无头分支），
//   所以这里只能有**纯数据/纯函数**——QRect/QPoint/QSize 是值类型，不需要应用对象。
//   平台层那些真碰 QWidget 的动作（激活窗口）只能靠探针 + 接线门验，判据落不到这一层。
//
// 【判定层与平台层的分工】
//   本层：**只出结论**（后端分档、激活动作计划、任务栏边距、弹窗落点）。
//   平台层：**只执行**（读 QGuiApplication/QScreen，调本层的结论，再动 QWidget）。
//   ⇒ 「结论」可离线测，「执行」由探针 + 接线门守；两边都不藏规则。
#pragma once

#include "PanelGeometry.h"

#include <QPoint>
#include <QRect>
#include <QSize>
#include <QString>

namespace Backend {

/// 显示后端（窗口系统协议那一层，不是 QPA 插件名）。
enum class Kind {
    X11,     ///< X11（QPA 插件名 "xcb"）
    Wayland, ///< Wayland（"wayland" 及 "wayland-*" 变体）
    Other,   ///< 其余（offscreen/minimal/未来新协议）
};

/// QPA 插件名 → 后端分档。
///
/// ⚠ **匹配必须带 token 边界**："wayland" 与 "wayland-egl" 都要命中 Wayland，
///   但 "mywayland" / "xwayland-extra" 那种**不该**命中 —— 否则分档会把
///   一个不相干的后端当成 Wayland 走另一套激活动作。
///   （门项正则同理：累计 16 次「子串互相顶替」的教训。）
Kind classify(const QString &platformName);

/// 后端分档的字符串形式（探针/日志用；`x11` / `wayland` / `other`）。
QString kindName(Kind kind);

/// 窗口激活动作计划（纯结论；平台层照单执行）。
struct Activation {
    /// 最小化时先**只摘掉最小化位**再 show。
    /// ⚠ 为什么不能直接 `showNormal()`：实测（离屏 + xcb 都验过）`showNormal()`
    ///   会**顺带清掉最大化位** ⇒ 用户把面板最大化后从托盘点「打开面板」，
    ///   面板会被打回普通大小。而 `show()` 本身**不恢复**最小化窗口 ——
    ///   最小化态下从托盘叫醒面板，点了跟没点一样（实测：show() 之后仍是 minimized）。
    bool restoreIfMinimized = true;
    /// 走 `windowHandle()->requestActivate()`（Wayland 上 `activateWindow()` 不可靠）。
    /// X11 走 `activateWindow()`（老办法在 X11 上够用）。
    bool requestActivate = false;
    /// 调 `raise()` 把窗口抬到同应用窗口之上。
    /// ⚠ **Wayland 上 `raise()` 是空操作**（叠放次序由合成器说了算）——
    ///   调它没坏处，但会**误导**（让人以为叠放次序被管了）⇒ Wayland 分支不调。
    bool raiseWindow = true;
};

/// 后端 → 激活动作计划。
Activation activationFor(Kind kind);

/// 屏幕被面板/任务栏占掉的边距（**任务栏几何**）。
///
/// 屏幕整块（`QScreen::geometry()`）与可用区（`QScreen::availableGeometry()`）
/// 的差就是面板/任务栏占掉的那几条边。四条边分别记，是因为 DDE 的面板可以
/// 四面都占，单个矩形表达不了。
struct Insets {
    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;

    bool isEmpty() const { return left == 0 && top == 0 && right == 0 && bottom == 0; }
};

/// 整屏 → 可用区 ⇒ 被占掉的边距。
Insets reservedInsets(const QRect &screen, const QRect &available);

/// 托盘图标几何**能不能用**（宽高都得 > 0）。
///
/// ⚠ 这不是「有没有托盘」的问题，是「托盘图标在不在屏幕上」的问题：
///   Wayland 上 `QSystemTrayIcon::geometry()` **常返回无效矩形**
///   （托盘由合成器托管，客户端拿不到坐标）⇒ 拿它定位 = 弹窗飞到屏幕左上。
///   ⇒ 弹窗落点与托盘入口**共用这一个判定**，不各判各的。
bool trayGeometryUsable(const QRect &trayIconGeometry);

/// 托盘弹窗的几何参数。
///
/// ⚠ **本层不拥有这组数值**：dockGap / edgeMargin / fallbackDx / fallbackDy
///   是**托盘域私有 token**，唯一出处是 `tray/TrayGeometry.h`。
///   本层只管「拿到这组数之后怎么落」——数值两处各写一份，改一处忘另一处
///   就是「弹窗贴着屏幕边」这种没人说得清来源的毛病。
///   ⇒ 默认值全 0（表示「调用方没给」）而不是抄一份 token 值。
struct PopupGeometry {
    int dockGap = 0;      ///< 贴托盘图标的间隙
    int edgeMargin = 0;  ///< 贴屏幕边的兜底留白
    int fallbackDx = 0; ///< 托盘几何不可用时：屏幕右上落点的横向偏移
    int fallbackDy = 0;  ///< 托盘几何不可用时：屏幕右上落点的纵向偏移
};

/// 托盘弹窗落点结论。
struct PopupPlacement {
    QRect rect;                       ///< 弹窗最终落点（已夹在可用区内）
    bool usedTrayGeometry = false;    ///< 落点是从托盘图标几何算出来的吗
                                        ///< （false = 托盘几何不可用，落到面板/屏幕角）
    bool usedPanelGeometry = false;   ///< 落点是不是**按面板位置**算的
                                        ///< （面板在下 ⇒ 弹窗在面板上方右对齐）
    bool clamped = false;             ///< 落点有没有被夹紧挪动过
};

/// 托盘弹窗落点（纯几何）。
///
/// 【原实现漏了什么】旧代码只夹了**下边**和**左边**：
///   · 托盘在屏幕**右上角**（DDE 顶栏的托盘就在那儿）⇒ 弹窗右边缘 =
///     `图标右边缘 + dockGap` ⇒ **溢出屏幕右边缘**（最多 8px）；
///   · 弹窗比可用区还高（长项目列表）⇒ 顶部**溢出屏幕上边缘**。
/// ⇒ 这里改成**四边都夹**。
///
/// 【托盘几何不可用时落在哪】——这是 DDE 上的**常态**，不是边角情况：
///   DDE 的系统托盘由 SNI 托管（`org.deepin.dde.TrayManager1`），
///   `QSystemTrayIcon::geometry()` **恒为无效矩形** ⇒ 托盘几何一直不可用。
///   旧实现只能瞎猜「屏幕右上」⇒ 托盘在**底部**任务栏时（DDE 默认布局），
///   弹窗落在离托盘图标**很远**的屏幕右上角。
///   ⇒ 有了面板真几何就能落对：面板在下 ⇒ 弹窗在**面板上方右对齐**，
///     面板在上 ⇒ 面板**下方右对齐**，面板在左/右 ⇒ 弹窗在面板**旁边、贴底**。
///   面板也读不到 ⇒ 退回「屏幕右上」（旧行为，一字未改）。
///
/// @param trayIconGeometry 托盘图标几何；**宽高非正即视为不可用**
///        （Wayland 上 `QSystemTrayIcon::geometry()` 常返回无效矩形）。
/// @param popupSize        弹窗尺寸（由调用方 adjustSize() 后给出）。
/// @param available        可用区（已扣掉面板/任务栏）。
/// @param geo              定位参数（数值由托盘域 token 给，本层不拥有）。
/// @param panel            面板真几何（无效 ⇒ 不按面板定位）。
PopupPlacement placePopup(const QRect &trayIconGeometry, const QSize &popupSize,
                           const QRect &available, const PopupGeometry &geo,
                           const PanelGeometry::Panel &panel = PanelGeometry::Panel());

} // namespace Backend
