#include "EngineConfig.h"

#include <QJsonArray>
#include <QJsonValue>

namespace EngineConfig {

namespace {
/// 字符串数组（`roots` / `docs` / `agentDocCandidates`）。
QStringList toStringList(const QJsonValue &v)
{
    QStringList out;
    for (const QJsonValue &item : v.toArray()) {
        const QString s = item.toString();
        if (!s.isEmpty())
            out << s;
    }
    return out;
}
} // namespace

Config parse(const QJsonObject &o)
{
    Config c;
    // 顶层形状：缺 `update` 键说明契约对不上（引擎新版本的配置结构变了）。
    // 不当空配置放行 —— 那会让界面显示「什么都没设」，而引擎其实有配置。
    if (!o.contains(QStringLiteral("update"))) {
        c.error = QStringLiteral("引擎配置载荷缺 update 键（契约可能过旧）");
        return c;
    }
    if (o.contains(QStringLiteral("version")))
        c.version = o.value(QStringLiteral("version")).toInt();
    c.language = o.value(QStringLiteral("language")).toString();
    c.roots = toStringList(o.value(QStringLiteral("roots")));

    const QJsonObject u = o.value(QStringLiteral("update")).toObject();
    c.docs = toStringList(u.value(QStringLiteral("docs")));
    c.agentDocCandidates = toStringList(u.value(QStringLiteral("agentDocCandidates")));
    // ⚠ 缺键 → -1（未知），**不回落成 0**：`backupKeep: 0` 是合法值
    //   （明确不保留备份），拿 0 当缺失会把两件相反的事说成同一句。
    if (u.contains(QStringLiteral("backupKeep")))
        c.backupKeep = u.value(QStringLiteral("backupKeep")).toInt();
    if (u.contains(QStringLiteral("maxShallowBranches")))
        c.maxShallowBranches = u.value(QStringLiteral("maxShallowBranches")).toInt();

    c.ok = true;
    return c;
}

QStringList writableKeys()
{
    // 与引擎的「可用：language, update.backupKeep, update.maxShallowBranches, roots」
    // 同一份清单（实测 2026-10-19，moongit dev d363b6a）。
    return { QStringLiteral("language"), QStringLiteral("update.backupKeep"),
        QStringLiteral("update.maxShallowBranches"), QStringLiteral("roots") };
}

bool isWritable(const QString &key)
{
    return writableKeys().contains(key);
}

QString summary(const Config &c)
{
    if (!c.ok)
        return QStringLiteral("引擎配置读不出来");
    QStringList parts;
    if (!c.language.isEmpty())
        parts << QStringLiteral("语言 %1").arg(c.language);
    if (c.hasMaxShallowBranches())
        parts << QStringLiteral("分支上限 %1").arg(c.maxShallowBranches);
    if (c.hasBackupKeep())
        parts << QStringLiteral("备份 %1 份").arg(c.backupKeep);
    if (parts.isEmpty())
        return QStringLiteral("引擎配置未给出可展示的项");
    return parts.join(QStringLiteral(" · "));
}

} // namespace EngineConfig
