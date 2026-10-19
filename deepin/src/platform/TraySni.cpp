#include "TraySni.h"

#include <QDBusAbstractAdaptor>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusVirtualObject>
#include <QDir>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>
#include <QVariant>

namespace TraySni {
/// SNI 的 ToolTip 结构体：`(sa(iiay)ss)` = 图标名 / 像素数组 / 标题 / 描述。
struct ToolTip {
    QString iconName;
    QList<Pixmap> iconPixmap;
    QString title;
    QString description;
};
} // namespace TraySni

// ⚠ `Q_DECLARE_METATYPE` 展开成**全局**的 QMetaTypeId 特化 ⇒ 必须写在全局命名空间
//   （写在 TraySni 里会报「specialization in different namespace」）。
Q_DECLARE_METATYPE(TraySni::Pixmap)
Q_DECLARE_METATYPE(QList<TraySni::Pixmap>)
Q_DECLARE_METATYPE(TraySni::ToolTip)

namespace TraySni {

// ── D-Bus 侧的 marshalling ──────────────────────────────────────────────
// ⚠ `QList<自定义类型>` 在 Qt 6 **没有** marshaller ⇒ 必须手写；
//   结构体的 D-Bus 签名也**推不出来** ⇒ 必须 `registerCustomType` 显式声明。

QDBusArgument &operator<<(QDBusArgument &arg, const Pixmap &p)
{
    arg.beginStructure();
    arg << p.width << p.height << p.bytes;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, Pixmap &p)
{
    arg.beginStructure();
    arg >> p.width >> p.height >> p.bytes;
    arg.endStructure();
    return arg;
}

QDBusArgument &operator<<(QDBusArgument &arg, const ToolTip &t)
{
    arg.beginStructure();
    arg << t.iconName;
    arg << t.iconPixmap;
    arg << t.title;
    arg << t.description;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, ToolTip &t)
{
    arg.beginStructure();
    arg >> t.iconName;
    arg >> t.iconPixmap;
    arg >> t.title;
    arg >> t.description;
    arg.endStructure();
    return arg;
}

} // namespace TraySni

namespace {
// 匿名命名空间提到全局是为了让 platform 命名空间能访问这些符号；
// 这里用局部 using 把判定层的类型引进来（避免到处写全名）。
using ::TraySni::ItemSpec;
using ::TraySni::Pixmap;
using ::TraySni::ToolTip;

void marshallPixmapList(QDBusArgument &arg, const void *data)
{
    const auto *list = static_cast<const QList<Pixmap> *>(data);
    arg.beginArray(QMetaType::fromType<Pixmap>());
    for (const Pixmap &p : *list)
        QDBusMetaType::marshall(arg, QMetaType::fromType<Pixmap>(), &p);
    arg.endArray();
}

void demarshallPixmapList(const QDBusArgument &arg, void *data)
{
    auto *list = static_cast<QList<Pixmap> *>(data);
    arg.beginArray();
    while (!arg.atEnd()) {
        Pixmap p;
        QDBusMetaType::demarshall(arg, QMetaType::fromType<Pixmap>(), &p);
        list->append(p);
    }
    arg.endArray();
}

/// 注册 D-Bus 类型（**幂等**：重复注册不报错）。
///
/// ⚠ `QList<自定义类型>` 在 Qt 6 没有现成 marshaller ⇒ 必须手写；
///   结构体的 D-Bus 签名也**推不出来** ⇒ 必须 `registerCustomType` 显式声明。
void registerDbusTypes()
{
    static bool done = false;
    if (done)
        return;
    done = true;
    qDBusRegisterMetaType<Pixmap>();
    QDBusMetaType::registerCustomType(QMetaType::fromType<Pixmap>(), QByteArrayLiteral("(iiay)"));
    qDBusRegisterMetaType<QList<Pixmap>>();
    QDBusMetaType::registerMarshallOperators(QMetaType::fromType<QList<Pixmap>>(),
                                             marshallPixmapList, demarshallPixmapList);
    QDBusMetaType::registerCustomType(QMetaType::fromType<QList<Pixmap>>(), QByteArrayLiteral("a(iiay)"));
    qDBusRegisterMetaType<ToolTip>();
    QDBusMetaType::registerCustomType(QMetaType::fromType<ToolTip>(), QByteArrayLiteral("(sa(iiay)ss)"));
}

/// 我们的 SNI 项（`QDBusVirtualObject` —— 绕开 Qt 的 Q_PROPERTY 导出，见头文件约束①）。
///
/// ⚠ 属性**一个都不能少**：host 注册后会主动读一遍，读不到就读不下去。
class SniItemObject : public QDBusVirtualObject
{
    Q_OBJECT
public:
    SniItemObject(const TraySni::ItemSpec &spec, QList<Pixmap> pixmaps)
        : m_spec(spec), m_pixmaps(std::move(pixmaps)) {}

    QString introspect(const QString &) const override
    {
        // ⚠ 三个 pixmap 属性的声明**从判定层的必填表生成** ——
        //   属性名如果在这里另写一份，改了一处忘了另一处 ⇒ 宿主按 XML 找不到属性
        //   ⇒ 读不到就当场注销我们（真缺陷，且肉眼极难发现）。
        QString pixmapDecl;
        for (const QString &name : TraySni::requiredProperties()) {
            pixmapDecl += QStringLiteral(
                              "    <property name=\"%1\" type=\"a(iiay)\" access=\"read\"/>\n")
                              .arg(name);
        }
        return QStringLiteral(
            "<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\"\n"
            "\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n"
            "<node>\n"
            "  <interface name=\"org.kde.StatusNotifierItem\">\n"
            "    <method name=\"Activate\"><arg name=\"x\" type=\"i\" direction=\"in\"/>"
            "<arg name=\"y\" type=\"i\" direction=\"in\"/></method>\n"
            "    <method name=\"SecondaryActivate\"><arg name=\"x\" type=\"i\" direction=\"in\"/>"
            "<arg name=\"y\" type=\"i\" direction=\"in\"/></method>\n"
            "    <method name=\"Scroll\"><arg name=\"delta\" type=\"s\" direction=\"in\"/></method>\n"
            "    <method name=\"ContextMenu\"><arg name=\"x\" type=\"i\" direction=\"in\"/>"
            "<arg name=\"y\" type=\"i\" direction=\"in\"/></method>\n"
            "    <property name=\"Category\" type=\"s\" access=\"read\"/>\n"
            "    <property name=\"Id\" type=\"s\" access=\"read\"/>\n"
            "    <property name=\"Title\" type=\"s\" access=\"read\"/>\n"
            "    <property name=\"Status\" type=\"s\" access=\"read\"/>\n"
            "    <property name=\"IconName\" type=\"s\" access=\"read\"/>\n"
            "    <property name=\"OverlayIconName\" type=\"s\" access=\"read\"/>\n"
            "    <property name=\"AttentionIconName\" type=\"s\" access=\"read\"/>\n"
            "    <property name=\"ToolTip\" type=\"(sa(iiay)ss)\" access=\"read\"/>\n"
            "    <property name=\"ItemIsMenu\" type=\"b\" access=\"read\"/>\n"
            "    <property name=\"Menu\" type=\"o\" access=\"read\"/>\n"
            "    <property name=\"IconThemePath\" type=\"s\" access=\"read\"/>\n")
            + pixmapDecl
            + QStringLiteral(
            "  </interface>\n"
            "</node>\n");
    }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        const QString iface = message.interface();
        const QString member = message.member();

        if (iface == QStringLiteral("org.freedesktop.DBus.Properties")
            && member == QStringLiteral("Get")) {
            const QString prop = message.arguments().value(1).toString();
            QDBusMessage reply = message.createReply();
            if (!propertyValue(reply, prop)) {
                connection.send(message.createErrorReply(
                    QStringLiteral("org.freedesktop.DBus.Error.UnknownProperty"),
                    QStringLiteral("Property %1 was not found").arg(prop)));
                return true;
            }
            connection.send(reply);
            return true;
        }
        if (iface == QStringLiteral("org.freedesktop.DBus.Properties")
            && member == QStringLiteral("GetAll")) {
            QVariantMap all;
            for (const QString &p : TraySni::hostReadProperties()) {
                QDBusMessage tmp;
                if (propertyValue(tmp, p))
                    all.insert(p, tmp.arguments().value(0));
            }
            QDBusMessage reply = message.createReply();
            reply.setArguments({QVariant::fromValue(all)});
            connection.send(reply);
            return true;
        }
        if (iface == QStringLiteral("org.kde.StatusNotifierItem")) {
            // 宿主点图标/右键时调的就是这几个方法。
            if (member == QStringLiteral("Activate") || member == QStringLiteral("SecondaryActivate")
                || member == QStringLiteral("ContextMenu")) {
                emit activated(member);
            }
            connection.send(message.createReply());
            return true;
        }
        return false;
    }

    Q_SIGNAL void activated(const QString &action);

    void setPixmaps(const QList<Pixmap> &pixmaps) { m_pixmaps = pixmaps; }
    void setIconName(const QString &name) { m_spec.iconName = name; }

private:
    bool propertyValue(QDBusMessage &reply, const QString &prop)
    {
        if (prop == QStringLiteral("Category")) {
            reply.setArguments({QVariant(m_spec.category)});
            return true;
        }
        if (prop == QStringLiteral("Id")) {
            reply.setArguments({QVariant(m_spec.id)});
            return true;
        }
        if (prop == QStringLiteral("Title")) {
            reply.setArguments({QVariant(m_spec.title)});
            return true;
        }
        if (prop == QStringLiteral("Status")) {
            reply.setArguments({QVariant(m_spec.status)});
            return true;
        }
        if (prop == QStringLiteral("IconName")) {
            reply.setArguments({QVariant(m_spec.iconName)});
            return true;
        }
        if (prop == QStringLiteral("OverlayIconName")) {
            reply.setArguments({QVariant(QString())});
            return true;
        }
        if (prop == QStringLiteral("AttentionIconName")) {
            reply.setArguments({QVariant(QString())});
            return true;
        }
        if (prop == QStringLiteral("ItemIsMenu")) {
            reply.setArguments({QVariant(m_spec.itemIsMenu)});
            return true;
        }
        if (prop == QStringLiteral("IconThemePath")) {
            reply.setArguments({QVariant(m_spec.iconThemePath)});
            return true;
        }
        if (prop == QStringLiteral("Menu")) {
            reply.setArguments({QVariant(QDBusObjectPath(QStringLiteral("/MenuBar")))});
            return true;
        }
        if (prop == QStringLiteral("ToolTip")) {
            ToolTip tip;
            tip.iconName = m_spec.iconName;
            tip.iconPixmap = QList<Pixmap>();
            tip.title = m_spec.title;
            tip.description = QString();
            reply.setArguments({QVariant::fromValue(tip)});
            return true;
        }
        // ⚠ 这三个是**入场券**：host 读不到就当场注销我们 ⇒ 即便没图也必须回一个空数组。
        //   属性名取判定层必填表（真相源唯一）⇒ 平台层不再硬写一份属性名。
        //   主图标给真图；注意态/覆盖态恒空数组（那是「有没有特殊态」的增强）。
        const QStringList pixProps = TraySni::requiredProperties();
        if (pixProps.contains(prop)) {
            const QList<Pixmap> payload =
                (prop == TraySni::primaryPixmapProperty()) ? m_pixmaps : QList<Pixmap>();
            reply.setArguments({QVariant::fromValue(payload)});
            return true;
        }
        return false;
    }

    TraySni::ItemSpec m_spec;
    QList<Pixmap> m_pixmaps;
};

const char kWatcherService[] = "org.kde.StatusNotifierWatcher";
const char kWatcherPath[] = "/StatusNotifierWatcher";

/// 已发布的项（进程内单例）。
SniItemObject *g_item = nullptr;
QString g_serviceName;
QString g_objectPath;

} // namespace

namespace platform {

void registerTraySniDBusTypes()
{
    registerDbusTypes();
}

TraySniNotifier *TraySniNotifier::instance()
{
    static TraySniNotifier inst;
    return &inst;
}

QString trayIconCacheFile()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    return QDir(dir).filePath(QStringLiteral("tray-icon.png"));
}

TraySniStatus probeTraySni()
{
    TraySniStatus st;
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        st.error = QStringLiteral("会话总线未连接");
        return st;
    }

    // ① watcher 在不在（**带超时**：服务不在时 `property()` 会一直等）。
    QDBusMessage probe = QDBusMessage::createMethodCall(
        QString::fromLatin1(kWatcherService), QString::fromLatin1(kWatcherPath),
        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    probe.setArguments({QVariant(QStringLiteral("org.kde.StatusNotifierWatcher")),
                        QVariant(QStringLiteral("ProtocolVersion"))});
    const QDBusMessage probeReply = bus.call(probe, QDBus::Block, 2000);
    if (probeReply.type() != QDBusMessage::ReplyMessage) {
        st.error = QStringLiteral("没有 SNI watcher（桌面不是 SNI 托盘）");
        return st;
    }
    st.watcherPresent = true;

    // ② 接口形状：注册方法是单参数还是双参数、已注册项是属性还是方法。
    TraySni::HostCaps caps;
    caps.watcherPresent = true;
    QDBusMessage introspect = QDBusMessage::createMethodCall(
        QString::fromLatin1(kWatcherService), QString::fromLatin1(kWatcherPath),
        QStringLiteral("org.freedesktop.DBus.Introspectable"), QStringLiteral("Introspect"));
    const QDBusMessage introReply = bus.call(introspect, QDBus::Block, 2000);
    const QString xml = introReply.arguments().value(0).toString();
    caps.singleArgRegister = !xml.contains(QStringLiteral("serviceOrPath"))
        || !xml.contains(QStringLiteral("name=\"service\""));
    caps.itemsAsProperty = xml.contains(QStringLiteral("RegisteredStatusNotifierItems"));

    QDBusMessage itemsMsg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kWatcherService), QString::fromLatin1(kWatcherPath),
        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    itemsMsg.setArguments({QVariant(QStringLiteral("org.kde.StatusNotifierWatcher")),
                            QVariant(QStringLiteral("RegisteredStatusNotifierItems"))});
    const QDBusMessage itemsReply = bus.call(itemsMsg, QDBus::Block, 2000);
    const QVariant outer = itemsReply.arguments().value(0);
    if (outer.canConvert<QDBusVariant>()) {
        const QVariant inner = outer.value<QDBusVariant>().variant();
        if (inner.canConvert<QStringList>())
            st.hostItems = inner.value<QStringList>();
    }
    st.host = TraySni::classifyHost(caps);
    return st;
}

TraySniStatus publishTraySni(const TraySni::ItemSpec &spec, const QList<QImage> &icons)
{
    TraySniStatus st = probeTraySni();
    if (!st.watcherPresent)
        return st;

    registerDbusTypes();

    QDBusConnection bus = QDBusConnection::sessionBus();

    // 服务名：同一进程里只注册一次（重复注册会失败）。
    if (g_serviceName != spec.serviceName) {
        if (!bus.registerService(spec.serviceName)) {
            st.error = QStringLiteral("注册总线服务名失败：%1").arg(bus.lastError().message());
            return st;
        }
        g_serviceName = spec.serviceName;
    }

    // 对象路径：⚠ 必须用 **registerVirtualObject**（见头文件约束①）。
    if (!g_item) {
        g_item = new SniItemObject(spec, TraySni::encodePixmaps(icons));
        g_objectPath = spec.objectPath;
        if (!bus.registerVirtualObject(spec.objectPath, g_item, QDBusConnection::SingleNode)) {
            st.error = QStringLiteral("注册 SNI 对象失败：%1").arg(bus.lastError().message());
            delete g_item;
            g_item = nullptr;
            return st;
        }
        // 宿主点图标/右键 ⇒ 转发给托盘层。
        QObject::connect(g_item, &SniItemObject::activated,
                         TraySniNotifier::instance(), &TraySniNotifier::activated);
    } else {
        g_item->setPixmaps(TraySni::encodePixmaps(icons));
        g_item->setIconName(spec.iconName);
    }

    // 向 watcher 登记。
    const TraySni::Registration mode = TraySni::registrationFor(st.host);
    QDBusMessage call = QDBusMessage::createMethodCall(
        QString::fromLatin1(kWatcherService), QString::fromLatin1(kWatcherPath),
        QStringLiteral("org.kde.StatusNotifierWatcher"), QStringLiteral("RegisterStatusNotifierItem"));
    const QString arg = TraySni::registrationArgument(mode, spec);
    if (st.host == TraySni::Host::Kde) {
        // KDE 的 watcher 是**双参数**（service, path）。
        call.setArguments({QVariant(spec.serviceName), QVariant(spec.objectPath)});
    } else {
        call.setArguments({QVariant(arg)});
    }
    const QDBusMessage reply = bus.call(call, QDBus::Block, 2000);
    if (reply.type() != QDBusMessage::ReplyMessage) {
        st.error = QStringLiteral("向 watcher 登记失败：%1").arg(reply.errorMessage());
        return st;
    }
    st.published = true;

    // ⚠ 通知宿主「图标有了」：宿主可能在自己的托盘 UI **建好之后**才收到注册，
    //   只登记不通知 ⇒ 项在列表里但**不画**（实测：项在、像素对，托盘区仍无变化）。
    //   ⇒ 补发 KDE 扩展的 `NewIcon` + 标准 `PropertiesChanged`。
    {
        QDBusMessage newIcon = QDBusMessage::createSignal(
            spec.objectPath, QStringLiteral("org.kde.StatusNotifierItem"), QStringLiteral("NewIcon"));
        bus.send(newIcon);
        QDBusMessage changed = QDBusMessage::createSignal(
            spec.objectPath, QStringLiteral("org.freedesktop.DBus.Properties"),
            QStringLiteral("PropertiesChanged"));
        QVariantMap props;
        props.insert(TraySni::primaryPixmapProperty(),
                     QVariant::fromValue(TraySni::encodePixmaps(icons)));
        props.insert(QStringLiteral("IconName"), QVariant(spec.iconName));
        changed.setArguments({QVariant(QStringLiteral("org.kde.StatusNotifierItem")),
                              QVariant::fromValue(props), QVariant(QStringList())});
        bus.send(changed);
    }
    return st;
}

bool updateTraySniIcon(const QList<QImage> &icons)
{
    if (!g_item)
        return false;
    g_item->setPixmaps(TraySni::encodePixmaps(icons));
    // 通知宿主图标变了（宿主没订阅就当没发）。
    QDBusMessage sig = QDBusMessage::createSignal(
        g_objectPath, QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"));
    sig.setArguments({QVariant(QStringLiteral("org.kde.StatusNotifierItem")),
                      QVariant::fromValue(QVariantMap{
                          {TraySni::primaryPixmapProperty(),
                           QVariant::fromValue(TraySni::encodePixmaps(icons))}}),
                      QVariant(QStringList())});
    QDBusConnection::sessionBus().send(sig);
    return true;
}

} // namespace platform

#include "TraySni.moc"
