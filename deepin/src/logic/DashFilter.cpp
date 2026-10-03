#include "DashFilter.h"
#include "Derived.h"
#include "../models/ProjectStatus.h"

QString timeWindowLabel(TimeWindow w)
{
    switch (w) {
    case TimeWindow::all:
        return QStringLiteral("全量");
    case TimeWindow::days30:
        return QStringLiteral("近 30 天");
    case TimeWindow::days7:
        return QStringLiteral("近 7 天");
    }
    return QStringLiteral("全量");
}

QString timeWindowHelp()
{
    return QStringLiteral("按项目最近一次更新的天数分档（不是统计这段时间内的提交量）");
}

bool DashFilter::keeps(const ProjectStatus &p) const
{
    if (window == TimeWindow::all)
        return true; // 不按时间筛
    const std::optional<int> age = Derived::daysSinceLastCommit(p);
    if (!age.has_value())
        return true; // 读不出来 → 保留（不知道 ≠ 不在范围内）
    const int days = (window == TimeWindow::days7) ? 7 : 30;
    return *age <= days;
}

bool DashFilter::typeAllowed(const QString &type) const
{
    return commitType.isEmpty() || commitType == type;
}

bool projectMatchesQuery(const ProjectStatus &p, const QString &query)
{
    const QString q = query.trimmed();
    if (q.isEmpty())
        return true;
    if (p.name.contains(q, Qt::CaseInsensitive))
        return true;
    for (const BranchStatus &b : p.branches) {
        if (b.name.contains(q, Qt::CaseInsensitive))
            return true;
    }
    return false;
}
