#include "Derived.h"
#include "SemColors.h"
#include "Thresholds.h"
#include "../models/ProjectStatus.h"
#include <QDateTime>
#include <QTimeZone>

namespace Derived {

const BranchStatus *primaryBranch(const ProjectStatus &p)
{
    for (const BranchStatus &b : p.branches) {
        if (b.isCurrent)
            return &b;
    }
    return p.branches.empty() ? nullptr : &p.branches.front();
}

std::optional<int> daysSinceLastCommit(const ProjectStatus &p)
{
    if (!p.lastCommitAt.has_value() || p.lastCommitAt->isEmpty())
        return std::nullopt;
    const QDateTime dt = QDateTime::fromString(*p.lastCommitAt, Qt::ISODate);
    if (!dt.isValid())
        return std::nullopt;
    // 引擎算术（dashboard.cj:219）：(nowMs - ms) / 86400000 整数除法——
    // 不用浮点版本：负数（未来时间戳）与边界上会差一天，而边界正是筛选分界线。
    const qint64 deltaMs = QDateTime::currentDateTime().toMSecsSinceEpoch()
        - dt.toMSecsSinceEpoch();
    return static_cast<int>(deltaMs / 86'400'000);
}

bool isMergeCandidate(const BranchStatus &b)
{
    // 逐字对齐引擎（flow/dashboard.cj:200-208）：pendingCommits 与「能不能合」无关。
    return b.aheadOfDefault > 0 && !b.isDefault && !b.merged;
}

bool needsAction(const ProjectStatus &p)
{
    if (p.isUnreadable())
        return false; // 采集失败：所有计数都是未知，不许当「待处理」也不许当「干净」
    if (p.userDirtyCount > 0 || p.untrackedCount > 0 || p.stashCount > 0)
        return true;
    for (const BranchStatus &b : p.branches) {
        if (isMergeCandidate(b))
            return true;
    }
    if (p.mergeHint.has_value()) {
        const QString k = p.mergeHint->kind;
        if (k == QLatin1String("merge") || k == QLatin1String("fast-forward"))
            return true;
    }
    return false;
}

Liveness liveness(const ProjectStatus &p)
{
    // ⚠️ 顺序即正确性：needsAction 必须在 engineStale **之前**（SPEC §3.7）。
    if (p.isUnreadable())
        return Liveness::unreadable;
    if (!p.isGit())
        return Liveness::notGit;
    if (needsAction(p))
        return Liveness::needsAction;
    const BranchStatus *pb = primaryBranch(p);
    if (pb && pb->status == QLatin1String("stale"))
        return Liveness::engineStale;
    const std::optional<int> age = daysSinceLastCommit(p);
    if (!age.has_value())
        return Liveness::unknown;
    return *age <= Thresholds::activeDays30 ? Liveness::recent : Liveness::quiet;
}

StateWord stateWord(const ProjectStatus &p)
{
    switch (liveness(p)) {
    case Liveness::unreadable:
        return { QStringLiteral("读不出来"), Liveness::unreadable };
    case Liveness::notGit:
        return { QStringLiteral("非 git 目录"), Liveness::notGit };
    case Liveness::needsAction:
        return { QStringLiteral("有未提交改动"), Liveness::needsAction };
    case Liveness::engineStale:
        return { QStringLiteral("停滞"), Liveness::engineStale };
    case Liveness::quiet:
        // activeDays30 线（引擎 active30d 桶）——说「N 天没更新」，不说「停滞」。
        return { QStringLiteral("%1 天没更新").arg(daysSinceLastCommit(p).value_or(0)),
            Liveness::quiet };
    case Liveness::recent:
        return { QStringLiteral("正常"), Liveness::recent };
    case Liveness::unknown:
        break;
    }
    return { QStringLiteral("状态读不出来"), Liveness::unknown };
}

BoardColumn boardColumn(const ProjectStatus &p)
{
    switch (liveness(p)) {
    case Liveness::needsAction:
        return BoardColumn::attention;
    case Liveness::recent:
        return BoardColumn::active;
    case Liveness::engineStale:
    case Liveness::quiet:
        return BoardColumn::stale;
    case Liveness::unreadable:
    case Liveness::notGit:
    case Liveness::unknown:
        break;
    }
    return BoardColumn::other;
}

QString boardColumnTitle(BoardColumn c)
{
    switch (c) {
    case BoardColumn::attention:
        return QStringLiteral("待处理");
    case BoardColumn::active:
        return QStringLiteral("活跃中");
    case BoardColumn::stale:
        return QStringLiteral("久未更新");
    case BoardColumn::other:
        break;
    }
    return QStringLiteral("其他");
}

QString boardColumnBasis(BoardColumn c)
{
    // 空列判定依据（mac BoardView.swift:59-66 原文）。
    switch (c) {
    case BoardColumn::attention:
        return QStringLiteral("有未提交、未跟踪、stash 或待合入的分支");
    case BoardColumn::active:
        return QStringLiteral("30 天内有过新提交");
    case BoardColumn::stale:
        return QStringLiteral("超过 30 天没有新提交（引擎 active30d 那条线）");
    case BoardColumn::other:
        break;
    }
    return QStringLiteral("采集失败、非 git，或提交时间读不出来");
}

int attentionCount(const std::vector<ProjectStatus> &projects)
{
    int n = 0;
    for (const ProjectStatus &p : projects) {
        if (needsAction(p))
            ++n;
    }
    return n;
}

int milestoneBadge(const MilestoneCounts &counts)
{
    // open + done；unknown 不进徽标（读不出来 ≠ 「进行中」）。
    return counts.open + counts.done;
}

int branchKpi(const std::vector<ProjectStatus> &projects)
{
    int sum = 0;
    for (const ProjectStatus &p : projects)
        sum += qMax(0, p.repoBranchCount); // -1 = 读不出来，不许当 0 也不许当负
    return sum;
}

QString mergeHintKindLine(const MergeHint &hint)
{
    if (hint.kind == QLatin1String("merged"))
        return QString(); // 已合入：不再提示（CONTRACT §2.1）
    if (hint.kind == QLatin1String("fast-forward"))
        return QStringLiteral("可快进合入默认分支");
    if (hint.kind == QLatin1String("merge"))
        return QStringLiteral("可合入默认分支");
    // rebase / no-default 不当合入提示（消费方判 kind）。
    return QString();
}

QString pulseLine(const ProjectStatus &p)
{
    if (p.isUnreadable())
        return QStringLiteral("仓库读不出来（%1）").arg(p.error.value_or(QStringLiteral("未知原因")));
    QStringList parts;
    if (p.userDirtyCount > 0)
        parts << QStringLiteral("未提交 %1").arg(p.userDirtyCount);
    if (p.untrackedCount > 0)
        parts << QStringLiteral("未跟踪 %1").arg(p.untrackedCount);
    if (p.stashCount > 0)
        parts << QStringLiteral("stash %1").arg(p.stashCount);
    if (p.worktreeCount > 1)
        parts << QStringLiteral("工作区 ×%1").arg(p.worktreeCount);
    return parts.join(QStringLiteral(" · "));
}

QString branchScopeLine(const ProjectStatus &p)
{
    const int tracked = static_cast<int>(p.branches.size());
    if (p.repoBranchCount < 0)
        return QStringLiteral("%1 个已跟踪分支（仓库真实分支数读不出来）").arg(tracked);
    if (p.repoBranchCount > tracked)
        return QStringLiteral("%1/%2 个分支已跟踪").arg(tracked).arg(p.repoBranchCount);
    return QStringLiteral("%1 个分支").arg(tracked);
}

QString staleText(const BranchStatus &b)
{
    if (b.staleDays < 0)
        return QStringLiteral("多久没更新：读不出来");
    if (b.staleDays == 0)
        return QStringLiteral("今天更新过");
    return QStringLiteral("%1 天没更新").arg(b.staleDays);
}

bool milestoneUnknown(const Milestone &m)
{
    // 「我们不知道」与「没有达成」是相反的两件事，必须分开表达。
    return m.status == QLatin1String("unknown") || !m.gitReadable;
}

QString milestoneStatusLabel(const Milestone &m)
{
    if (milestoneUnknown(m))
        return QStringLiteral("无法核验");
    if (m.status == QLatin1String("done"))
        return QStringLiteral("已达成");
    if (m.status == QLatin1String("dropped"))
        return QStringLiteral("已放弃");
    return m.overdue ? QStringLiteral("已逾期") : QStringLiteral("进行中");
}

QString milestoneDueText(const Milestone &m)
{
    if (m.targetDate.isEmpty() || m.daysToTarget == -1)
        return QString();
    if (m.daysToTarget >= 0)
        return QStringLiteral("还剩 %1 天").arg(m.daysToTarget);
    return QStringLiteral("逾期 %1 天").arg(-m.daysToTarget);
}

QString milestoneCommitsText(const Milestone &m)
{
    if (!m.commitsSinceReadable || m.commitsSince < 0)
        return QStringLiteral("提交数读不出来");
    return QStringLiteral("创建以来 %1 提交").arg(m.commitsSince);
}

QString milestoneUnverifiedNote(const Milestone &m)
{
    return m.unverifiedReason.isEmpty() ? QStringLiteral("提交数读不出来") : m.unverifiedReason;
}

QColor livenessColor(Liveness l)
{
    // 【批 R · 跨端取值对齐】对齐 mac **活代码**（`BoardView.stateColor` /
    // `DashboardParts.stateWord` 两处多数派，不是那段没人调用的 `StatusColor`）：
    //   engineStale/quiet → 灰（静默，不是「坏了」）
    //   notGit            → 灰（不适用；紫色已被「深更新轨 / 已合并」占用）
    //   unknown           → 红（读不出来 = 真有问题，不许装成「不活跃」的灰）
    // ⚠ 托盘**不跟这套**（托盘图标无文字，颜色是唯一信号）—— 见 SemColors.h。
    switch (l) {
    case Liveness::needsAction:
        return SemColors::orange(); // 橙
    case Liveness::engineStale:
    case Liveness::quiet:
        return SemColors::gray(); // 静默
    case Liveness::recent:
        return SemColors::shallow(); // 绿
    case Liveness::unreadable:
        return SemColors::red(); // 采集失败
    case Liveness::notGit:
        return SemColors::gray(); // 不适用
    case Liveness::unknown:
        return SemColors::red(); // 读不出来（与 unreadable 同档）
    }
    return SemColors::gray(); // 灰
}

QColor branchStatusColor(const QString &status)
{
    // active绿 / idle黄 / **stale橙** / merged紫 / 未知灰。
    // ⚠ stale 染**橙**（不是红）—— 对齐 mac 活代码 `DSColor.color(.stale)` = .orange。
    //   （原先染陈旧红 #EF4444：那档红与危险红 #DC2626 肉眼几乎分不出，却表达两件事。）
    if (status == QLatin1String("active"))
        return SemColors::shallow();
    if (status == QLatin1String("idle"))
        return SemColors::yellow();
    if (status == QLatin1String("stale"))
        return SemColors::orange();
    if (status == QLatin1String("merged"))
        return SemColors::deep();
    return SemColors::gray();
}

QStringList branchStatusKinds()
{
    // 引擎 `computeBranchStatus` 的**全部**产出（`moongit/src/kernel/progress.cj:14-37`）：
    //   merged / unknown / active / idle / stale —— 就这 5 档，没有别的。
    // ⚠ 别加引擎不产出的档（如 mac 的 `dirty`）：加了就是**永远画不出来的一格**。
    return {
        QStringLiteral("active"),
        QStringLiteral("idle"),
        QStringLiteral("stale"),
        QStringLiteral("merged"),
        QStringLiteral("unknown"),
    };
}

QList<Liveness> livenessKinds()
{
    // Liveness 的**全部**档位（`logic/Liveness.h` 的枚举，共 7 档）。
    // 穷举列出而不是「抄一份」—— 加一档 Liveness 时这里必须跟着改（编译器盯得住），
    // 色卡样张也就自动多画一格，不会漏画一档。
    return {
        Liveness::unreadable,
        Liveness::notGit,
        Liveness::needsAction,
        Liveness::engineStale,
        Liveness::quiet,
        Liveness::recent,
        Liveness::unknown,
    };
}

QColor statTint(int n)
{
    // 量级分档（DSStat）：负数（读不出来）按红处理，不许当「干净」。
    if (n < 0)
        return SemColors::red();
    if (n == 0)
        return QColor(); // 无效 = 跟随文字色
    if (n <= 2)
        return SemColors::yellow();
    if (n <= 9)
        return SemColors::orange();
    return SemColors::red();
}

} // namespace Derived
