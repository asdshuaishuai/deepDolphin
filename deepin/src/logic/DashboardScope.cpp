#include "DashboardScope.h"
#include "Derived.h"
#include "../models/ProjectStatus.h"

KpiSet kpis(const DashboardData &d, const std::vector<ProjectStatus> &projects)
{
    KpiSet k;
    const int listed = d.projects.listed;
    const int failed = d.projects.failed;

    // 1. 项目总数 —— 主数字必须是 listed（注册表条数），不是 total（只数采集成功）。
    k.projects = listed;
    k.totalSub << QStringLiteral("可读取 %1/%2").arg(d.projects.total).arg(listed)
               << QStringLiteral("近 7 天活跃 %1").arg(d.projects.active7d)
               << QStringLiteral("近 30 天 %1").arg(d.projects.active30d);
    if (failed > 0)
        k.totalSub << QStringLiteral("采集失败 %1 个").arg(failed);

    // 2. 里程碑完成率 —— 分母只取「达没达成有答案的」（done+open），不塞 unknown。
    const MilestoneCounts &ms = d.milestones.counts;
    const int decided = ms.done + ms.open;
    k.milestonePct = decided > 0 ? qRound(static_cast<double>(ms.done) * 100.0 / decided) : 0;
    k.milestoneProgress = decided > 0 ? static_cast<double>(ms.done) / decided : -1.0;
    k.milestoneSub << QStringLiteral("进行中 %1").arg(ms.open)
                   << QStringLiteral("已达成 %1").arg(ms.done);
    if (ms.unknown > 0)
        k.milestoneSub << QStringLiteral("%1 个读不出来").arg(ms.unknown);

    // 3. 待处理 —— 必须是项目数，且与侧栏徽标 / 看板列同一规则（needsAction）。
    int attention = 0;
    int mergeBranchCount = 0;
    for (const ProjectStatus &p : projects) {
        if (Derived::needsAction(p))
            ++attention;
        for (const BranchStatus &b : p.branches) {
            if (Derived::isMergeCandidate(b))
                ++mergeBranchCount;
        }
    }
    k.needsAction = attention;
    k.needsActionTinted = attention > 0;
    k.needsSub << QStringLiteral("有未提交/未跟踪/stash 的 %1 个").arg(d.projects.dirty);
    if (mergeBranchCount > 0)
        k.needsSub << QStringLiteral("待合入分支 %1 条").arg(mergeBranchCount);
    k.needsSub << QStringLiteral("未跟踪文件 %1 个").arg(d.work.untrackedFiles);

    // 4. 分支 —— 真实分支数（repoBranchCount），追踪数组长度只进副说明。
    k.branchSum = Derived::branchKpi(projects);
    int unreadableBranchProjects = 0;
    for (const ProjectStatus &p : projects) {
        if (p.repoBranchCount < 0)
            ++unreadableBranchProjects;
    }
    k.branchSub << QStringLiteral("%1 个 stash").arg(d.work.stashes)
                << QStringLiteral("%1 个未跟踪文件").arg(d.work.untrackedFiles)
                << QStringLiteral("已跟踪明细 %1 条").arg(d.work.branches);
    if (unreadableBranchProjects > 0) {
        k.branchSub << QStringLiteral("%1 个项目的分支数读不出来").arg(unreadableBranchProjects);
    } else if (d.work.branches < k.branchSum) {
        k.branchSub << QStringLiteral("（其余未纳入追踪）");
    }
    int tagCount = 0;
    bool tagKnown = false;
    for (const ProjectStatus &p : projects) {
        tagKnown = true; // tags 在 C++ 契约里恒发（QStringList），有项目即可知
        tagCount += p.tags.size();
    }
    if (tagKnown)
        k.branchSub << QStringLiteral("%1 个 tag").arg(tagCount);
    return k;
}

QString summaryLine(const KpiSet &k)
{
    if (k.needsAction <= 0)
        return QStringLiteral("共 %1 个项目").arg(k.projects);
    return QStringLiteral("%1 个项目 · %2 个项目待处理").arg(k.projects).arg(k.needsAction);
}

MsTally milestoneTally(const QVector<Milestone> &items, const MilestoneCounts *counts)
{
    MsTally t;
    for (const Milestone &m : items) {
        if (m.status == QLatin1String("done"))
            ++t.done;
        else if (m.status == QLatin1String("dropped"))
            ++t.dropped;
        else if (m.status == QLatin1String("open"))
            ++t.open;
        else
            ++t.unknown; // unknown / 未来新增的档位
    }
    t.readCount = counts ? counts->readCount : 0;
    t.complete = counts ? (items.size() == counts->readCount) : false;
    return t;
}

QVector<QPair<QString, QVector<Milestone>>> milestoneGroups(const QVector<Milestone> &items)
{
    QVector<QPair<QString, QVector<Milestone>>> out;
    QVector<int> indexByProject; // 首现顺序 → out 下标
    for (const Milestone &m : items) {
        int idx = -1;
        for (int i = 0; i < out.size(); ++i) {
            if (out.at(i).first == m.projectName) {
                idx = i;
                break;
            }
        }
        if (idx < 0) {
            out.append({ m.projectName, {} });
            idx = out.size() - 1;
        }
        out[idx].second.append(m);
    }
    return out;
}

QVector<Milestone> milestonesForProject(const std::vector<Milestone> &items, const QString &project)
{
    QVector<Milestone> out;
    for (const Milestone &m : items) {
        if (project.isEmpty() || m.projectName == project)
            out.append(m);
    }
    return out;
}
