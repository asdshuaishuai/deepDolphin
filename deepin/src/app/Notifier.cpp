#include "Notifier.h"
#include "Settings.h"
#include "../logic/Notifications.h"
#include <DNotifySender>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QVariantMap>

DCORE_USE_NAMESPACE

Notifier::Notifier(QObject *parent)
    : QObject(parent)
{
    // 订阅通知动作/关闭：只认自己刚发的那条 id（别人发的通知不抢）。
    QDBusConnection::sessionBus().connect(QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("ActionInvoked"), this,
        SLOT(onActionInvoked(uint, QString)));
    QDBusConnection::sessionBus().connect(QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("NotificationClosed"), this,
        SLOT(onNotificationClosed(uint, uint)));
}

void Notifier::notify(const QString &title, const QString &body, const QStringList &actions)
{
    // 空 actions = 带默认「打开面板」（mac 版全部通知可点进面板，Linux 用动作按钮等价实现）
    send(title, body, actions.isEmpty()
            ? QStringList { QStringLiteral("open"), QStringLiteral("打开面板") }
            : actions);
}

void Notifier::notifyOnce(const QString &dedupeKey, const QString &title, const QString &body)
{
    if (m_notifiedKeys.contains(dedupeKey))
        return;
    m_notifiedKeys.insert(dedupeKey);
    send(title, body, { QStringLiteral("open"), QStringLiteral("打开面板") });
}

void Notifier::send(const QString &title, const QString &body, const QStringList &actions)
{
    QVariantMap hints;
    hints.insert(QStringLiteral("category"), QStringLiteral("DIGEST"));
    // deepin 通知服务器认的两个关键 hint（M1-4）：
    // · desktop-entry = 我们的 .desktop 文件名（与 setDesktopFileName 同一字符串）：
    //   通知中心点通知/「跳转到应用」才能定位回本应用；缺了它在不同 DDE 版本行为不一致。
    // · image-path = 应用图标名：通知没图标时显示默认灰块。
    hints.insert(QStringLiteral("desktop-entry"), QStringLiteral("cn.deepdolphin.app"));
    hints.insert(QStringLiteral("image-path"), QStringLiteral("deepdolphin"));
    auto sender = DUtil::DNotifySender(title)
                      .appName(QStringLiteral("deepDolphin 面板"))
                      .appBody(body)
                      .hints(hints)
                      // ⚠ 显示时长**由设置驱动**（M1-4 的最后一项）；
                      //   归一在判定层（logic/Notifications）—— 0 在 D-Bus 语义里是
                      //   「永不消失」⇒ 绝不能原样传出去。
                      .timeOut(Settings::instance().notifyTimeoutMs());
    // 同类语义的通知**按类别顶替**（replaceId），失败/停滞这类"状态型"通知不该在通知中心
    // 堆成一摞；mac 侧同样是"一条槽位随状态刷新"（SPEC §3.2）。彼此不同类的通知互不顶替。
    // ⚠ 「算不算状态型」的判定在**判定层**（logic/Notifications）⇒ 无头可测。
    const uint replaceId = m_replaceIds.value(Notifications::categoryOf(title), 0);
    if (replaceId != 0 && Notifications::replacesPrevious(title))
        sender = sender.replaceId(replaceId);
    if (!actions.isEmpty())
        sender = sender.actions(actions);
    const QDBusPendingCall call = sender.call();
    QDBusPendingCallWatcher *w = new QDBusPendingCallWatcher(call, this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w, title] {
        const QDBusMessage reply = w->reply();
        if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
            const uint id = reply.arguments().first().toUInt();
            m_knownIds.insert(id);
            // 记住这条 id 作为该类别下一次的 replaceId（下一条同类别通知顶替它）
            m_replaceIds.insert(Notifications::categoryOf(title), id);
        }
        w->deleteLater();
    });
}

void Notifier::onActionInvoked(uint id, const QString &actionKey)
{
    if (!m_knownIds.contains(id))
        return;
    emit actionInvoked(actionKey);
}

void Notifier::onNotificationClosed(uint id, uint reason)
{
    Q_UNUSED(reason);
    m_knownIds.remove(id);
    // 被用户关掉的类别不该再"顶替"自己——清掉该 id 的类别归属
    for (auto it = m_replaceIds.begin(); it != m_replaceIds.end(); ++it) {
        if (it.value() == id) {
            it = m_replaceIds.erase(it);
            break;
        }
    }
}
