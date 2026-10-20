#include "Notifications.h"

namespace Notifications {

int normalizeTimeoutMs(int ms)
{
    // ⚠ 0 在 D-Bus 语义里是「**永不消失**」⇒ 绝不能把 0 原样传出去。
    if (ms <= 0)
        return kDefaultTimeoutMs;
    if (ms < kMinTimeoutMs)
        return kMinTimeoutMs;
    if (ms > kMaxTimeoutMs)
        return kMaxTimeoutMs;
    return ms;
}

QString categoryOf(const QString &title)
{
    // ⚠ 「状态型」= 失败/停滞这类**会反复出现**的通知 ⇒ 同类别互相顶替，
    //   不该在通知中心堆成一摞；其余（更新完成/定时简报）按标题天然区分 ⇒ 并存。
    if (title.contains(QStringLiteral("失败")) || title.contains(QStringLiteral("停滞")))
        return QStringLiteral("state");
    return QString();
}

bool replacesPrevious(const QString &title)
{
    return !categoryOf(title).isEmpty();
}

} // namespace Notifications
