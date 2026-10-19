#include "IndexStatus.h"

#include <QJsonArray>
#include <QJsonValue>
#include <QStringList>

namespace IndexStatus {

namespace {
/// 探针三字段（files / bytes / maxMtime）。
void parseProbe(const QJsonObject &p, Overview *o)
{
    if (p.contains(QStringLiteral("files")))
        o->probeFiles = p.value(QStringLiteral("files")).toInt();
    if (p.contains(QStringLiteral("bytes")))
        o->probeBytes = static_cast<qint64>(p.value(QStringLiteral("bytes")).toDouble());
    if (p.contains(QStringLiteral("maxMtime")))
        o->probeMaxMtime = static_cast<qint64>(p.value(QStringLiteral("maxMtime")).toDouble());
}
} // namespace

Overview parseOverview(const QJsonObject &o)
{
    Overview r;
    // 顶层形状：缺 `nodes` 键说明契约对不上（引擎的配置结构变了）。
    // 不当空索引放行 —— 那会让界面显示「0 符号」，而引擎其实有内容。
    if (!o.contains(QStringLiteral("nodes"))) {
        r.error = QStringLiteral("索引概览载荷缺 nodes 键（契约可能过旧）");
        return r;
    }
    r.project = o.value(QStringLiteral("project")).toString();
    if (o.contains(QStringLiteral("updateCount")))
        r.updateCount = o.value(QStringLiteral("updateCount")).toInt();
    r.generatedAt = o.value(QStringLiteral("generatedAt")).toString();
    // ⚠ 缺键 → 不知道有没有自愈过（不回落成「没自愈」）
    if (o.contains(QStringLiteral("selfHealed"))) {
        r.selfHealedPresent = true;
        r.selfHealed = o.value(QStringLiteral("selfHealed")).toBool();
    }
    // ⚠ 缺键 → -1（未知），不回落成 0：空索引（0）与契约漂移（没发）是两件事。
    // ⚠ nodes 的守卫是**多余**的：上面已早退（缺 nodes 即契约漂移），
    //    到这里 nodes 必定存在 —— 写个 if 反而让人以为「缺了会回落成 0」。
    r.nodes = o.value(QStringLiteral("nodes")).toInt();
    if (o.contains(QStringLiteral("edges")))
        r.edges = o.value(QStringLiteral("edges")).toInt();
    if (o.contains(QStringLiteral("files")))
        r.files = o.value(QStringLiteral("files")).toInt();
    const QJsonObject byKind = o.value(QStringLiteral("byKind")).toObject();
    for (auto it = byKind.begin(); it != byKind.end(); ++it)
        r.byKind.insert(it.key(), it.value().toInt());
    parseProbe(o.value(QStringLiteral("probe")).toObject(), &r);
    r.ok = true;
    return r;
}

UpdateResult parseUpdate(const QJsonObject &o)
{
    UpdateResult r;
    if (!o.contains(QStringLiteral("fresh"))) {
        r.error = QStringLiteral("索引更新载荷缺 fresh 键（契约可能过旧）");
        return r;
    }
    r.project = o.value(QStringLiteral("project")).toString();
    r.fresh = o.value(QStringLiteral("fresh")).toBool();
    // ⚠ rebuilt 在 fresh 时**引擎不发这个键** —— 用 present 标志区分
    //   「这次没重建」（fresh 时）与「从来没重建过」（引擎没发）。
    if (o.contains(QStringLiteral("rebuilt"))) {
        r.rebuiltPresent = true;
        r.rebuilt = o.value(QStringLiteral("rebuilt")).toBool();
    }
    if (o.contains(QStringLiteral("updateCount")))
        r.updateCount = o.value(QStringLiteral("updateCount")).toInt();
    r.generatedAt = o.value(QStringLiteral("generatedAt")).toString();
    r.indexJsonPath = o.value(QStringLiteral("indexJson")).toString();
    r.ok = true;
    return r;
}

QString summary(const Overview &o)
{
    if (!o.ok)
        return QStringLiteral("索引状态读不出来");
    QStringList parts;
    if (o.hasNodes())
        parts << QStringLiteral("%1 符号").arg(o.nodes);
    if (o.hasEdges())
        parts << QStringLiteral("%1 边").arg(o.edges);
    if (o.hasFiles())
        parts << QStringLiteral("%1 文件").arg(o.files);
    if (o.hasUpdateCount())
        parts << QStringLiteral("第 %1 代").arg(o.updateCount);
    if (parts.isEmpty())
        return QStringLiteral("索引状态未给出可展示的项");
    return QStringLiteral("索引：%1").arg(parts.join(QStringLiteral(" · ")));
}

} // namespace IndexStatus
