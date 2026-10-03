// SearchFilter.h — 搜索空态/命中数文案（mac A11yLabel.swift:105-122 对位，纯函数层）。
//
// 【红线】「本来就没有」与「没匹配上」两句话必须分开；过滤生效时报「匹配 x / y 个名词」。
#pragma once
#include <QString>

namespace SearchFilter {

struct EmptyText {
    enum Reason { none, noData, noMatch } reason = none;
    QString text;
};

// shownCount==0 时给出空态原因与文案；否则 reason=none。
inline EmptyText emptyText(int allCount, int shownCount, const QString &query, const QString &noun)
{
    if (shownCount != 0)
        return {};
    if (allCount == 0)
        return { EmptyText::noData, QStringLiteral("暂无%1").arg(noun) };
    const QString q = query.trimmed();
    if (q.isEmpty())
        return { EmptyText::noData, QStringLiteral("暂无%1").arg(noun) };
    return { EmptyText::noMatch, QStringLiteral("没有%1匹配「%2」").arg(noun, q) };
}

// 命中数摘要；没过滤（shown==all）或本来就没有 → 空串（不显示）。
inline QString matchedCountText(int allCount, int shownCount, const QString &noun)
{
    if (allCount == 0 || shownCount == allCount)
        return QString();
    return QStringLiteral("匹配 %1 / %2 个%3").arg(shownCount).arg(allCount).arg(noun);
}

} // namespace SearchFilter
