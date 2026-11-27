// TraySni.h — SNI（StatusNotifierItem）托盘的**判定层**（纯结论、零 QWidget、零 QDBus）。
//
// 【为什么要有它 —— 批 X 照出来的实情】
//   DDE 的系统托盘**只认 SNI**（`org.kde.StatusNotifierWatcher`），**不认** Qt 的旧托盘协议：
//   · ⚠⚠ **批 Y 更正**：批 X 当时写「`_NET_SYSTEM_TRAY_S0` 选区**不存在**」——
//     **量错了**：`xprop -root` 查的是窗口**属性**，选区要用 `XGetSelectionOwner()` 查。
//     实测 `_NET_SYSTEM_TRAY_S0` **有持有者**（daemon 建的 1×1 InputOnly 窗口），
//     dock 插件正是靠它把图标窗口 reparent 进去 ⇒ **XEmbed 宿主是存在的**
//     （只是它画的是「应用自绘的窗口」，不画 SNI 图标 ⇒ SNI 这条路仍然不通）。
//   · `QSystemTrayIcon::isSystemTrayAvailable()` 为 true，但 `geometry()` 恒为 (0,0,0×0)；
//   · **全屏差分实测：我们的托盘图标在 DDE 上一个像素都没出现** ——
//     旧协议没有宿主 ⇒ 图标**根本不会显示**（不是「显示成灰的」，是**不显示**）。
//   ⇒ M1-3 的性质从「保住图标颜色」变成「**让托盘图标能出现**」（缺陷级，不是优化级）。
//
// 【这一层放什么】
//   判定层只出**结论**，不碰总线：
//   · host 是哪一变体（ayatana / KDE）⇒ 决定注册方式与接口形状；
//   · 注册时给 watcher 传**什么参数**（服务名 / 对象路径）；
//   · 一个 SNI 项对外**必须**有哪些属性（缺了会被 host 当场注销）；
//   · 图标像素怎么编码成 SNI 要的 `a(iiay)`（ARGB32、**网络字节序**）。
//
// 【为什么这些能离线测】
//   `--selfcheck` 跑在 `QGuiApplication` 构造**之前** ⇒ 这里只能是纯函数。
//   像素编码只依赖 `QImage`（值类型，无头可用），总线交互全在平台层。
#pragma once

#include <QByteArray>
#include <QImage>
#include <QList>
#include <QString>
#include <QStringList>

namespace TraySni {

/// SNI 宿主（watcher）的变体。
///
/// ⚠ **不是「KDE vs 非 KDE」的泛泛分类** —— 实测 DDE 提供的 watcher 是
///   **ayatana 变体**：方法只有**单参数** `RegisterStatusNotifierItem(serviceOrPath)`，
///   `RegisteredStatusNotifierItems` 是**属性**（不是方法），
///   `ProtocolVersion` = 0。
///   而 KDE 的 watcher 是**双参数** `RegisterStatusNotifierItem(service, path)`，
///   `RegisteredStatusNotifierItems` 是**方法**，ProtocolVersion 更高。
///   ⇒ 两者对客户端的**要求不同**（尤其「注册参数怎么给」），必须分档。
enum class Host {
    None,   ///< 没有 watcher（服务不在 / 调用失败）
    Ayatana, ///< 单参数注册 + 已注册项是属性 + ProtocolVersion 0
    Kde,     ///< 双参数注册 + 已注册项是方法
};

/// 宿主能力快照（**纯数据**：从总线读来的原样事实）。
struct HostCaps {
    bool watcherPresent = false;  ///< watcher 服务在不在
    bool singleArgRegister = true; ///< RegisterStatusNotifierItem 是单参数吗
    bool itemsAsProperty = true;  ///< 已注册项是属性吗
    int protocolVersion = 0;       ///< watcher 报的 ProtocolVersion
};

/// host 分档（纯判定）。
///
/// ⚠ 判定顺序**有讲究**：先看「有没有 watcher」，再看接口形状 ——
///   一个连服务都不在的 bus，报什么都读不出来 ⇒ 只能判 None，
///   不能因为「读不到已注册项」就当成 KDE（那会把「读不到」误判成「接口形状不同」）。
Host classifyHost(const HostCaps &caps);

/// 注册方式（把项登记到 watcher 时传什么）。
enum class Registration {
    ServiceName, ///< 传**服务名**（host 自己补默认路径 `/StatusNotifierItem`）
    ObjectPath,  ///< 传**对象路径**（host 用调用方的 unique name + 该路径）
};

/// 注册方式判定。
///
/// 【实测结论（批 X）】两种传法 host 都**接受**（方法调用都返回无错误），
///   但**记录下来的项 id 形态不同**：
///   · 传服务名 ⇒ 记录 `服务名 + /StatusNotifierItem`；
///   · 传对象路径 ⇒ 记录 `调用方unique名 + /StatusNotifierItem`。
///   ⇒ **默认用服务名**：项 id 里带的是我们自己的服务名，
///   `RegisteredStatusNotifierItems` 里能一眼认出是自己（排查时有用）。
Registration registrationFor(Host host);

/// 一个 SNI 项对外的契约（**纯数据**：host 看得见的那部分）。
struct ItemSpec {
    QString serviceName;   ///< 我们的总线服务名（如 org.deepin.deepDolphin）
    QString objectPath;    ///< 对象路径（固定 /StatusNotifierItem）
    QString id;            ///< SNI 的 Id
    QString title;         ///< SNI 的 Title
    QString category;      ///< ApplicationStatus / Communications / SystemServices
    QString status;        ///< Active / Passive / NeedsAttention
    QString iconName;      ///< 图标名或**绝对路径**（host 支持绝对路径，实测 ayatana 项就是这么用的）
    QString iconThemePath; ///< 图标主题目录（可空）
    bool itemIsMenu = false;///< 整块图标是不是菜单
};

/// 注册时传给 watcher 的那个参数（按注册方式取 serviceName 或 objectPath）。
QString registrationArgument(Registration mode, const ItemSpec &spec);

/// 宿主**强制要求**的属性（**缺一个就会被当场注销**，实测）。
///
/// 【实测过程】第一版只暴露了 `IconName` 等字符串属性，没暴露 `IconPixmap`
///   ⇒ host 读到 `IconPixmap` 读不到（`UnknownProperty`）⇒ **立刻**发
///   `StatusNotifierItemUnregistered` 把项踢掉。
///   ⇒ 这三个 pixmap 属性是**入场券**，不是「可选增强」。
/// ⚠ 与「ayatana 那两个能显示的项**没有** IconPixmap 属性」并不矛盾：
///   那两项是**应用自己**注册并自带实现的；**host 对新注册的项会主动读一遍**
///   全部属性，读不到就读不下去。
QStringList requiredProperties();

/// **主图标** pixmap 属性的名字（宿主只有读它才拿得到真图）。
///
/// ⚠ 另外两个（注意态 / 覆盖态）恒回**空数组**即可 —— 那是「有没有特殊态」的增强，
///   真实缺陷是「读不到属性」而不是「数组是空的」。
/// ⚠ 它必须和 requiredProperties() 同源（就是它的第一个）——
///   平台层若自己再写一份属性名，两处迟早走偏（改了一处忘了另一处 ⇒
///   宿主按 XML 找不到属性 ⇒ 当场注销我们）。
QString primaryPixmapProperty();

/// 宿主会主动读的**全部**属性（读不到就可能读不下去）。
///
/// 实测 host 注册后主动读的顺序：
///   Id → Menu → IconPixmap → AttentionIconPixmap → OverlayIconPixmap
///   → ToolTip → IconName → IconThemePath
QStringList hostReadProperties();

/// 诊断：给一份「我们暴露了哪些属性」，看缺了哪些**必填**的。
///
/// ⚠ 返回**点名**缺哪几个（不只说「不完整」）：排查时能直接照着补。
QStringList missingRequired(const QStringList &provided);

/// SNI 的一个 pixmap 元素（`(width, height, pixels)`）。
struct Pixmap {
    int width = 0;
    int height = 0;
    QByteArray bytes; ///< ARGB32、**网络字节序**、每像素 4 字节、不补行对齐
};

/// ARGB32 像素：Qt 的 `Format_ARGB32` 内存序是 **小端 BGRA**，
/// 而 D-Bus 的 `ay` 要的是**网络字节序 ARGB**（A,R,G,B 依次，每像素 4 字节）。
///
/// ⚠ 字节序写反 ⇒ 颜色全错（红变蓝那种），而**长度不变** ⇒ 肉眼看图只会觉得「颜色怪」，
///   不会发现是协议层错了 ⇒ 这一层必须有**非对称**夹具盯着。
QByteArray encodeArgb32NetworkOrder(const QImage &image);

/// 一张图 → SNI 的 pixmap 数组（通常给一个尺寸就够；host 会缩放）。
QList<Pixmap> encodePixmap(const QImage &image);

/// 一张图 → SNI 的 pixmap 数组（给多个尺寸，host 挑最合适的那个）。
QList<Pixmap> encodePixmaps(const QList<QImage> &images);

} // namespace TraySni
