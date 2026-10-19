// TraySni.h — 平台层：把 deepDolphin 作为 **SNI 项**发布到 DDE 的系统托盘。
//
// 【为什么需要这一层 —— 批 X 照出来的实情】
//   DDE 的托盘**只认 SNI**，不认 Qt 的旧托盘协议：
//   · ⚠⚠ **批 Y 更正**：批 X 写「`_NET_SYSTEM_TRAY_S0` 选区**不存在**」是**量错了**
//     （`xprop -root` 查属性、选区要用 `XGetSelectionOwner()` 查）⇒ 选区**有**持有者，
//     但它托管的是**应用自绘的 X11 窗口**，不画 SNI 图标 ⇒ SNI 这条路仍然不通；
//   · `QSystemTrayIcon::isSystemTrayAvailable()` 为 true，但 `geometry()` 恒 (0,0,0×0)；
//   · **全屏差分实测：旧协议下我们的托盘图标一个像素都没出现**（不是变灰，是**不显示**）。
//   ⇒ 在 DDE 上必须自己实现一个最小的 `org.kde.StatusNotifierItem`。
//
// 【实测出来的硬约束（照抄就会踩）】
//   ① **必须用 `QDBusVirtualObject`（`registerVirtualObject`）** ——
//      用 `Q_PROPERTY` 导出（`registerObject`）时，Qt 6.8 在处理**外来进程**的
//      `Properties.Get` 时会**静默退出**（实测：进程正常跑完、退出码 0，
//      但 D-Bus 侧报「recipient disconnected without replying」⇒ 名字失去 owner
//      ⇒ watcher 当场把项注销）。属性在不在都一样崩 ⇒ 不是数据问题，是导出路径的问题。
//   ② **必须暴露 `IconPixmap` / `AttentionIconPixmap` / `OverlayIconPixmap`**
//      —— 缺一个，host 读到 `UnknownProperty` 就**立刻**注销该项（实测）。
//   ③ `ToolTip` 的类型是结构体 `(sa(iiay)ss)`，不是字符串。
//   ④ `IconName` 可以指**绝对路径**（ayatana 那个能显示的项就是这么用的）。
//
// 【分工】判定层（`logic/TraySni`）给结论；这一层碰总线。
#pragma once

#include "../logic/TraySni.h"

#include <QImage>
#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>

namespace platform {

/// SNI 项的宿主事件出口（托盘层订阅它）。
///
/// ⚠ 单例（进程内只有一个 SNI 项）—— 信号源随项一起活着。
class TraySniNotifier : public QObject
{
    Q_OBJECT
public:
    static TraySniNotifier *instance();

    /// 宿主点了图标/按了右键（action = "Activate" / "ContextMenu" / …）。
    Q_SIGNAL void activated(const QString &action);
};

/// SNI 发布状态（**说清是哪一种失败**，不只说「没成功」）。
struct TraySniStatus {
    bool watcherPresent = false;   ///< 桌面上有没有 SNI watcher（没有 ⇒ 这台机器不是 DDE 式托盘）
    bool published = false;        ///< 我们的项是否**已登记进 watcher**
    TraySni::Host host = TraySni::Host::None; ///< host 变体
    QStringList hostItems;         ///< watcher 里的已注册项（排查用）
    QString error;                 ///< 失败原因（空 = 没失败）
};

/// 注册 SNI 用的 D-Bus 类型（幂等；**自检也要调它**）。
///
/// ⚠ `QList<自定义类型>` 在 Qt 6 没有现成 marshaller ⇒ 必须手写
///   （`registerMarshallOperators`）；
///   结构体的 D-Bus 签名也**推不出来** ⇒ 必须 `registerCustomType` 显式声明
///   （`Pixmap` = `(iiay)`、`QList<Pixmap>` = `a(iiay)`）——
///   不显式声明的话宿主会把它当 `av` 解，拿到的是一堆 variant 而不是像素数组。
void registerTraySniDBusTypes();

/// 探测本机有没有 SNI watcher，以及它是哪一变体。
///
/// ⚠ 读 watcher 属性**必须带超时**：`QDBusInterface::property()` 没有超时参数，
///   服务不在时会**一直等** ⇒ 用 `QDBusConnection::call(..., QDBus::Block, ms)`。
TraySniStatus probeTraySni();

/// 把 deepDolphin 作为 SNI 项发布出去（注册服务名 + 对象 + 登记到 watcher）。
///
/// @param spec  项的对外契约（服务名/路径/Id/Title/…）。
/// @param icons 图标（多尺寸；会被编码成 SNI 的 `a(iiay)`）。
TraySniStatus publishTraySni(const TraySni::ItemSpec &spec, const QList<QImage> &icons);

/// 更新已发布项的图标（状态变化时刷新）。
///
/// ⚠ 宿主侧没有「换图标」的标准动作 ⇒ 做法是**改属性值**（`IconPixmap` / `IconName`），
///   并发 `PropertiesChanged` 通知；实在不行就撤了重发。
bool updateTraySniIcon(const QList<QImage> &icons);

/// 图标缓存文件（`IconName` 指它）。
///
/// ⚠ **写盘只限「程序自身依赖」**：托盘图标要是一个**绝对路径**，
///   就得真有个文件在那儿 —— 这属于「程序自己的依赖」，不是业务数据。
QString trayIconCacheFile();

} // namespace platform
