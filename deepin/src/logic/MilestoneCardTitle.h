// MilestoneCardTitle.h — 仪表盘里程碑卡标题与切片（mac MilestoneCard.swift +
// DetailViews.swift:1100-1110 对位，纯函数层）。
//
// 【红线】六段披露逐字保留；items 是引擎的完整列表，「只画前 5 条」是界面自己干的，
// 必须由界面自己披露（「只显示前 5 条（共 N 条），完整清单见「里程碑」页」）。
#pragma once
#include "../models/DashboardData.h"
#include <QString>
#include <algorithm>

namespace MilestoneCard {

constexpr int CARD_MAX = 5;

// 标题六段披露：「里程碑（进行中 N · 已达成 M[ · 已放弃 K][ · ⚠ 无法核验 U]
// [ · 已停用项目的 X 条未计入][ · ⚠ Y 条所属项目已不存在][ · ⚠ milestones.json <health>]」
inline QString title(const MilestoneCounts &c, int excludedDisabled, int orphaned,
    const QString &storeHealth)
{
    QStringList segs;
    segs << QStringLiteral("进行中 %1").arg(c.open);
    segs << QStringLiteral("已达成 %1").arg(c.done);
    if (c.dropped > 0)
        segs << QStringLiteral("已放弃 %1").arg(c.dropped);
    if (c.unknown > 0)
        segs << QStringLiteral("⚠ 无法核验 %1").arg(c.unknown);
    if (excludedDisabled > 0)
        segs << QStringLiteral("已停用项目的 %1 条未计入").arg(excludedDisabled);
    if (orphaned > 0)
        segs << QStringLiteral("⚠ %1 条所属项目已不存在").arg(orphaned);
    if (!storeHealth.isEmpty() && storeHealth != QLatin1String("ok"))
        segs << QStringLiteral("⚠ milestones.json %1").arg(storeHealth);
    return QStringLiteral("里程碑（%1）").arg(segs.join(QStringLiteral(" · ")));
}

inline int shownCount(int itemCount)
{
    return qMin(qMax(0, itemCount), CARD_MAX);
}

// 超出时的披露；空串 = 没什么要说的。
inline QString sliceNote(int itemCount)
{
    const int total = qMax(0, itemCount);
    if (total <= CARD_MAX)
        return QString();
    return QStringLiteral("只显示前 %1 条（共 %2 条），完整清单见「里程碑」页").arg(CARD_MAX).arg(total);
}

} // namespace MilestoneCard
