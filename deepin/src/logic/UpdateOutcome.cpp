#include "UpdateOutcome.h"
#include <QVector>
#include <algorithm>

namespace UpdateOutcome {

QVector<Doc> docsOf(const UpdateResultBase &r)
{
    QVector<Doc> out;
    out.reserve(static_cast<int>(r.docs.size()));
    for (const DocChange &d : r.docs) {
        Doc doc;
        doc.file = d.file;
        doc.changed = d.changed;
        doc.created = d.created;
        doc.backup = d.backup;
        out.append(doc);
    }
    return out;
}

QString summary(const QVector<Doc> &docs, const QString &project, int nameMax)
{
    // 引擎没报文档：一律不说「已刷新」——那是拿一个未知当成功报出去。
    if (docs.isEmpty())
        return QStringLiteral("%1：本次没有需要更新的文档").arg(project);

    QVector<Doc> touched;
    QVector<Doc> backedUp;
    for (const Doc &d : docs) {
        if (d.changed) {
            touched.append(d);
            if (!d.backup.isEmpty())
                backedUp.append(d);
        }
    }
    // 报了但都没变：老实说「没有变化」。
    if (touched.isEmpty()) {
        QStringList names;
        for (const Doc &d : docs)
            names << d.file;
        return QStringLiteral("%1：文档没有变化（%2）").arg(project, names.join(QStringLiteral("、")));
    }

    // 列举上限 nameMax（下限 1），多的必须说还剩几个。
    const int cap = qMax(1, nameMax);
    QStringList listed;
    for (int i = 0; i < touched.size() && i < cap; ++i) {
        const Doc &d = touched.at(i);
        listed << (d.created ? QStringLiteral("新建 %1").arg(d.file)
                             : QStringLiteral("已更新 %1").arg(d.file));
    }
    QString s = QStringLiteral("%1：%2").arg(project, listed.join(QStringLiteral("、")));
    if (touched.size() > listed.size())
        s += QStringLiteral(" 等 %1 个文档").arg(touched.size());
    // 备份路径只给第一个：一行放不下多条路径，但「备份存在」必须说。
    if (!backedUp.isEmpty())
        s += QStringLiteral("（%1 的旧版本已备份到 %2）").arg(backedUp.first().file,
            backedUp.first().backup);
    return s;
}

QString summary(const UpdateResultBase &r, int nameMax)
{
    return summary(docsOf(r), r.project, nameMax);
}

} // namespace UpdateOutcome
