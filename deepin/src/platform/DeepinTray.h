// DeepinTray.h — 平台层：把 deepDolphin 以 **deepin 托盘窗口协议**发布出去。
//
// 【为什么要有这一层 —— 批 Y 查明的事实】
//   deepin 25 的托盘区画的是**应用自绘的 X11 窗口**，不是 SNI 图标：
//   · 托管方 `org.deepin.dde.TrayManager1`（owner = dde-session-daemon 的 trayicon1 模块）
//     持有 **`_NET_SYSTEM_TRAY_S0`** 选区（1×1 InputOnly 窗口）并登记图标窗口；
//   · 绘制方 dde-dock 的托盘插件读 `TrayIcons` → 建容器 → **reparent** 图标窗口进去
//     → 抓窗口图像当图标。
//   ⇒ 我们要做的：**自绘一个 X11 窗口当图标** + 向选区持有者发 `REQUEST_DOCK`。
//
// 【报文格式的坑（照抄经典写法会被静默忽略）】
//   ClientMessage `type=_NET_SYSTEM_TRAY_OPCODE`，
//   **`l[1]`=opcode(0=REQUEST_DOCK)、`l[2]`=窗口 id** —— **比经典 XEmbed 偏移一位**
//   （经典是 l[0]/l[1]/l[2]）。权威来源：linuxdeepin/dde-daemon → trayicon1/traymanager.go。
//   ⇒ 字段下标由判定层 `logic/DeepinTray` 给（`dockFieldIndex`），这一层**不许**写死数字。
//
// 【分工】判定层出结论（可离线单测）；这一层碰 X11。
#pragma once

#include <QImage>
#include <QString>

namespace platform {

/// deepin 托盘窗口协议的发布状态（**说清是哪一种失败**）。
struct DeepinTrayStatus {
    bool selectionPresent = false; ///< `_NET_SYSTEM_TRAY_S0` 选区**有没有持有者**
    bool published = false;        ///< 我们的窗口**有没有被 daemon 登记进 `TrayIcons`**
    quint32 windowId = 0;          ///< 我们的图标窗口 id（排查用）
    QString error;                 ///< 失败原因（空 = 没失败）
};

/// 探测本机有没有 deepin 托盘选区（= 是不是 deepin 式托盘）。
DeepinTrayStatus probeDeepinTray();

/// 发布图标窗口（自绘 + 发 `REQUEST_DOCK`）。
///
/// @param icon        图标（会被画进 X11 窗口）
/// @param windowName  窗口名（= 托盘里显示的名字；实测 daemon 的 `GetName` 读它）
DeepinTrayStatus publishDeepinTray(const QImage &icon, const QString &windowName);

/// 换图标（重画窗口内容；daemon 盯 damage ⇒ 会发 `Changed`，dock 重新抓图）。
bool updateDeepinTrayIcon(const QImage &icon);

} // namespace platform
