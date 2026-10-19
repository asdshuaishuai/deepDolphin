// DdePanel.cpp — DDE 面板几何取数（平台层：读 D-Bus）。
#include "DdePanel.h"

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusVariant>
#include <QMetaObject>
#include <QThreadPool>
#include <QVariant>

namespace platform {

namespace DdePanel {

namespace {

/// 面板服务的三个等价入口（实测三者都在，接口一致）。
/// ⚠ **顺序有意义**：新服务名才带 `position`（面板在哪条边），
///   旧的两个只有 `geometry` ⇒ 先试新的，position 读不到再退回
///   「按几何猜边」（判定层的 dominantEdge）。
struct ServiceEntry {
    const char *service;
    const char *path;
};
const ServiceEntry kServices[] = {
    { "org.deepin.ds.Dock", "/org/deepin/ds/Dock" },
    { "org.deepin.dde.Dock1", "/org/deepin/dde/Dock1" },
    { "org.deepin.dde.daemon.Dock1", "/org/deepin/dde/daemon/Dock1" },
};
const char kInterface[] = "org.deepin.dde.Dock1";

/// 缓存（只在 GUI 线程读写 ⇒ 无需加锁）。
PanelGeometry::Panel g_panel;

/// 读一个属性；读不到返回无效 QVariant。
///
/// ⚠ **必须走 `QDBusConnection::call` 而不是 `QDBusInterface::property`**：
///   后者没有超时参数 ⇒ 面板服务卡住时会把调用方（GUI 线程）一起卡住。
///   `call(..., QDBus::Block, 2000)` 有 2s 上限；服务**不存在**时
///   实测**立刻**返回错误（不等 2s）⇒ 非 DDE 桌面零成本。
QVariant readProperty(const QString &service, const QString &path, const QString &property)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path,
                                                     QStringLiteral("org.freedesktop.DBus.Properties"),
                                                     QStringLiteral("Get"));
    msg << QString::fromLatin1(kInterface) << property;
    const QDBusMessage reply =
        QDBusConnection::sessionBus().call(msg, QDBus::Block, 2000);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return QVariant();
    QVariant value = reply.arguments().value(0);
    // 属性值裹在 variant 里 ⇒ 拆一层。
    if (value.canConvert<QDBusVariant>())
        value = qvariant_cast<QDBusVariant>(value).variant();
    return value;
}

/// 把 D-Bus 传回来的 (iiii) 拆成 QRect。
///
/// ⚠⚠ **必须用 `qdbus_cast<QRect>`，不能自己 `arg >> x >> y >> w >> h`**：
///   存进 QVariant 的 QDBusArgument **丢掉了类型上下文**（它带着「当前类型」，
///   而那个上下文在变体里存不住）⇒ 直接 `>> int` 会走进 libdbus 的
///   「type struct 114 not a basic type」并 **abort**（实测崩过一次）。
///   `qdbus_cast` 走**注册过的类型解档器**（QRect 的 (iiii) 布局它知道）⇒ 正常。
///   ⚠ 前提：QRect 必须先 `qDBusRegisterMetaType<QRect>()` 注册过。
bool rectFromVariant(const QVariant &value, QRect *out)
{
    if (!value.isValid())
        return false;
    if (value.canConvert<QRect>()) {
        *out = value.value<QRect>();
        return !out->isEmpty();
    }
    if (!value.canConvert<QDBusArgument>())
        return false;
    const QRect rect = qdbus_cast<QRect>(value.value<QDBusArgument>());
    if (rect.isEmpty())
        return false;
    *out = rect;
    return true;
}

} // namespace

PanelGeometry::Panel readNow()
{
    // ⚠ QRect 的 (iiii) 布局要注册过才能被 qdbus_cast 解档（见 rectFromVariant 注）。
    static const bool registered = [] {
        qDBusRegisterMetaType<QRect>();
        return true;
    }();
    Q_UNUSED(registered);

    PanelGeometry::Panel panel;
    for (const ServiceEntry &entry : kServices) {
        const QString service = QString::fromLatin1(entry.service);
        const QString path = QString::fromLatin1(entry.path);
        QRect rect;
        if (!rectFromVariant(readProperty(service, path, QStringLiteral("geometry")), &rect))
            continue;
        panel.valid = true;
        panel.rect = rect;
        // position 只有新服务有；读不到就留 Unknown（判定层会按几何猜边）。
        const QVariant pos = readProperty(service, path, QStringLiteral("position"));
        if (pos.isValid() && pos.canConvert<int>())
            panel.edge = PanelGeometry::edgeFromPosition(pos.toInt());
        return panel;
    }
    return panel;
}

PanelGeometry::Panel current()
{
    return g_panel;
}

void refreshAsync()
{
    QThreadPool::globalInstance()->start([] {
        const PanelGeometry::Panel panel = readNow();
        QCoreApplication *app = QCoreApplication::instance();
        if (!app)
            return;
        // 回 GUI 线程再写缓存 ⇒ 读缓存的代码不必加锁。
        QMetaObject::invokeMethod(
            app,
            [panel] { g_panel = panel; },
            Qt::QueuedConnection);
    });
}

bool servicePresent()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    for (const ServiceEntry &entry : kServices) {
        if (bus.interface()->isServiceRegistered(QString::fromLatin1(entry.service)))
            return true;
    }
    return false;
}

} // namespace DdePanel

} // namespace platform
