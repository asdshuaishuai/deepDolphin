#include "CommitTypeComposition.h"
#include "../models/ProjectStatus.h"

namespace CommitTypes {

QColor sequenceColor(int i)
{
    // 12 色固定序（mac CommitTypeColor.palette）：blue, red, orange, purple, teal,
    // indigo, mint, pink, brown, yellow, cyan, gray。容量外**不取模**。
    static const QColor kPalette[PALETTE_CAPACITY] = {
        QColor(0x34, 0x82, 0xF6), // blue
        QColor(0xEF, 0x44, 0x44), // red
        QColor(0xF5, 0x9E, 0x0B), // orange
        QColor(0x8B, 0x5C, 0xF6), // purple
        QColor(0x06, 0xB6, 0xD4), // teal
        QColor(0x63, 0x66, 0xF1), // indigo
        QColor(0x10, 0xB9, 0x81), // mint
        QColor(0xEC, 0x48, 0x99), // pink
        QColor(0xA1, 0x62, 0x2E), // brown
        QColor(0xE8, 0xB0, 0x1C), // yellow
        QColor(0x08, 0x91, 0xA2), // cyan
        QColor(0x9C, 0xA3, 0xAF), // gray
    };
    if (i < 0 || i >= PALETTE_CAPACITY)
        return QColor(); // 无效 = 调用方越界（必须先切片，禁止取模）
    return kPalette[i];
}

Slice cardSlice(const QVector<QPair<QString, int>> &entries)
{
    Slice s;
    s.total = entries.size();
    if (s.total <= PALETTE_CAPACITY) {
        s.rows = entries;
        return s;
    }
    for (int i = 0; i < PALETTE_CAPACITY; ++i)
        s.rows.append(entries.at(i));
    s.cut = true;
    s.note = QStringLiteral("色板最多区分 %1 种类型，还有 %2 种没显示")
                 .arg(PALETTE_CAPACITY)
                 .arg(s.total - PALETTE_CAPACITY);
    return s;
}

QVector<QPair<QString, int>> filtered(const QVector<QPair<QString, int>> &entries,
    const QString &typeFilter)
{
    if (typeFilter.isEmpty())
        return entries;
    QVector<QPair<QString, int>> out;
    for (const auto &e : entries) {
        if (e.first == typeFilter)
            out.append(e);
    }
    return out;
}

QString lineFor(const QVector<QPair<QString, int>> &entries, bool sampleTruncated, int totalCommits)
{
    const int total = entries.size();
    if (total <= 0)
        return QString();
    const int shown = qMin(total, PULSE_LINE_MAX);
    QStringList body;
    for (int i = 0; i < shown; ++i)
        body << QStringLiteral("%1 ×%2").arg(entries.at(i).first).arg(entries.at(i).second);

    QStringList notes;
    if (sampleTruncated) {
        // 分母必须写出来：「已截断」而不说「近几条/共几条」。
        int sampled = 0;
        for (const auto &e : entries)
            sampled += e.second;
        notes << (totalCommits > 0 ? QStringLiteral("近 %1/%2 条样本").arg(sampled).arg(totalCommits)
                                   : QStringLiteral("样本，非全量"));
    }
    if (shown < total)
        notes << QStringLiteral("本行只列前 %1 种，共 %2 种，完整构成见「提交构成」卡片")
                     .arg(shown)
                     .arg(total);
    if (notes.isEmpty())
        return body.join(QStringLiteral(" · "));
    return QStringLiteral("%1（%2）").arg(body.join(QStringLiteral(" · ")),
        notes.join(QStringLiteral("；")));
}

QVector<QPair<QString, int>> toEntries(const std::vector<CommitTypeStat> &stats)
{
    QVector<QPair<QString, int>> out;
    out.reserve(static_cast<int>(stats.size()));
    for (const CommitTypeStat &s : stats)
        out.append({ s.type, s.count });
    return out;
}

} // namespace CommitTypes
