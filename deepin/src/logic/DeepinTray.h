// DeepinTray.h — deepin 托盘**窗口协议**的判定层（纯结论、零 X11、零 QWidget、零 QDBus）。
//
// 【这条协议是什么（批 Y 实测查明）】
//   deepin 25 的托盘区画的不是 SNI 图标，而是**应用自绘的 X11 窗口**：
//   · 托管方是 `org.deepin.dde.TrayManager1`（owner = dde-session-daemon 的 trayicon1 模块），
//     它持有 **`_NET_SYSTEM_TRAY_S0`** 选区（1×1 InputOnly 窗口）并登记图标窗口；
//   · 绘制方是 dde-dock 的托盘插件，它读 `TrayIcons` → 建 32 位 ARGB 容器
//     → **reparent** 图标窗口进去 → 抓窗口图像当图标。
//   ⇒ 我们要做的：**自绘一个 X11 窗口当图标**，并让 daemon 认领它。
//
// 【注册协议（实测可复现）】
//   1. 查选区持有者：`XGetSelectionOwner(dpy, "_NET_SYSTEM_TRAY_S0")`；
//   2. 向持有者窗口发 ClientMessage：`type = _NET_SYSTEM_TRAY_OPCODE`，
//      **`l[1] = 0`（REQUEST_DOCK）、`l[2] = 我们的窗口 id`**。
//   ⚠⚠ **比经典 XEmbed 偏移一位**（经典是 `l[0]`=opcode、`l[1]`=窗口、`l[2]`=版本）。
//      权威来源：linuxdeepin/dde-daemon → trayicon1/traymanager.go
//      （`opcode := data32[1]`、`win := x.Window(data32[2])`）。
//      ⇒ **实测**：按经典布局发 ⇒ daemon 读到的 opcode 是窗口 id ≠ 0 ⇒ **静默忽略**
//      （`TrayIcons` 不变、也不报错）；按 deepin 布局发 ⇒ 注册成功。
//
// 【为什么放判定层】
//   这一层只出**结论**（字段偏移、请求怎么拼、选区叫什么、哪个 host 走哪条路），
//   不碰 X11 ⇒ `--selfcheck` 里可离线测；X11 动作全在平台层。
#pragma once

#include <QString>

#include <optional>

namespace TraySni {

/// deepin 托盘窗口协议的报文字段（**只列我们真用到的**）。
///
/// ⚠ **字段下标是本协议最容易踩的坑** —— 经典 XEmbed 与 deepin **差一位**。
///   这里把下标显式化，平台层**不许**自己写数字（只能取这里的常量）。
enum class DockField {
    Opcode,   ///< 操作码（REQUEST_DOCK = 0）
    WindowId, ///< 被 dock 的窗口 id
};

/// ClientMessage 的字段下标（deepin 布局：opcode 在 1、窗口 id 在 2）。
///
/// ⚠ 经典 XEmbed 是 opcode=0 / 窗口=1 / 版本=2 —— **照抄经典写法会被静默忽略**。
///   实测：按经典布局发，daemon 读到的 opcode 是我们的窗口 id（≠ 0）⇒ 直接忽略。
constexpr int dockFieldIndex(DockField field)
{
    return field == DockField::Opcode ? 1 : 2;
}

/// 操作码：请求把窗口 dock 进托盘。
constexpr quint32 dockOpcodeRequestDock()
{
    return 0;
}

/// 选区名（deepin 用 **S0** 变体）。
///
/// ⚠ `_NET_SYSTEM_TRAY`（无后缀）本机**没有**持有者；发错选区 daemon 收不到。
constexpr const char *dockSelectionName()
{
    return "_NET_SYSTEM_TRAY_S0";
}

/// 操作码的原子名。
constexpr const char *dockOpcodeAtomName()
{
    return "_NET_SYSTEM_TRAY_OPCODE";
}

/// 一次 dock 请求要带的字段值（**纯数据**，平台层照着填进 ClientMessage）。
struct DockRequest {
    quint32 opcode = 0;   ///< 操作码（REQUEST_DOCK）
    quint32 windowId = 0; ///< 被 dock 的窗口 id
};

/// 构造一次 dock 请求（纯函数）。
///
/// ⚠ 这里**固化**了「opcode 放 l[1]、窗口 id 放 l[2]」这一偏移 ——
///   放错位置 ⇒ daemon 静默忽略 ⇒ 图标永远不出现（且**没有任何报错**）。
inline DockRequest buildDockRequest(quint32 windowId)
{
    DockRequest req;
    req.opcode = dockOpcodeRequestDock();
    req.windowId = windowId;
    return req;
}

/// 托盘实现方式（**二选一**，不并存 —— 见 TrayController 的说明）。
enum class Backend {
    None,          ///< 没有可用后端（没有 watcher、也没有 deepin 选区）
    Sni,           ///< 标准 SNI（KDE 系桌面）
    DeepinWindow,  ///< deepin 私有：自绘 X11 窗口 + REQUEST_DOCK
};

/// 后端的**强制指定**（测试/探针用；`nullopt` = 按平台能力自动选）。
///
/// ⚠ 为什么需要它（批 Y 实测逼出来的）：DDE 25 上自动选的是 **deepin 窗口协议**
///   ⇒ SNI 那条路**根本不会被走** ⇒ 批 X 那个「IconPixmap 字节级」端到端判据
///   在 DDE 上**永远跑不起来**（服务不上线 ⇒ 假红）。
///   ⇒ 探针需要一个**显式强制**的口子，才能在这台机器上仍然验 SNI 路径。
///   ⚠ 用 `std::optional` 而不是拿 `Backend::None` 当哨兵 —— `None` 本身是个
///   **合法取值**（强制走旧协议那条路），拿它当「没指定」会二义。
using BackendOverride = std::optional<Backend>;

/// 解析后端强制开关（**纯函数**）。
///
/// 认得的取值：`sni` / `deepin` / `none`（强制走旧协议那条路）；
/// `auto` / 空串 / **任何认不出的字样** ⇒ 一律 `nullopt`（= 按平台能力自动选）。
///
/// ⚠ **认不出 ⇒ 自动选**，不静默改成某个后端：把「打错字」变成「换了一条路」
///   会让判据在**没测到想测的东西**的情况下变绿（假绿）。
BackendOverride parseBackendOverride(const QString &text);

/// 按平台能力选后端（纯判定）。
///
/// ⚠ 优先级：**先看 deepin 选区在不在**。DDE 25 上 SNI watcher 也在（ayatana 变体），
///   但它**不画** SNI 图标 ⇒ 若按「有 watcher 就走 SNI」选，图标永远不出现。
///   ⇒ deepin 选区在场时**必须**走窗口协议。
///
/// @param deepinSelectionPresent `_NET_SYSTEM_TRAY_S0` 选区**有没有持有者**
/// @param watcherPresent SNI watcher 在不在
/// @param forced 强制指定（测试/探针用）；`nullopt` = 按上面两条自动选。
Backend chooseBackend(bool deepinSelectionPresent, bool watcherPresent,
                      BackendOverride forced = BackendOverride{});

/// 后端的可读名（供探针/日志；纯函数）。
QString backendName(Backend backend);

} // namespace TraySni
