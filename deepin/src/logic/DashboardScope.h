// DashboardScope.h — 仪表盘 KPI 口径（mac DashboardScope.swift 对位，纯函数层）。
//
// 【红线】
// · 总数 = `dashboard.projects.listed`（注册表条数）**非 total**（total 只数采集成功）；
//   采集失败数降级到副说明披露。
// · 完成率分母 done+open **不含 unknown**；unknown 单独在副说明披露。
// · 待处理 = needsAction **项目数**（与侧栏徽标、看板列同一算法）；分支数降级到副说明。
// · 分支 = Σ max(repoBranchCount,0)（真实分支数；work.branches 只进副说明）。
// · 里程碑统计按明细 tally；明细数 ≠ readCount 时声明「不是全量（下界）」。
#pragma once
#include "../models/DashboardData.h"
#include "../models/Milestone.h"
#include <QString>
#include <QStringList>
#include <QVector>
#include <vector>

class ProjectStatus;

struct KpiSet {
    int projects = 0;        // listed
    int milestonePct = 0;    // 0..100；decided==0 时 0
    double milestoneProgress = -1.0; // 0..1；decided==0 时 -1（没有进度条）
    int needsAction = 0;
    int branchSum = 0;
    QStringList totalSub, milestoneSub, needsSub, branchSub;
    bool needsActionTinted = false; // 有内容时数字染橙
};

KpiSet kpis(const DashboardData &d, const std::vector<ProjectStatus> &projects);

// 页头摘要行：**只读 KpiSet，没有第二算法**。
// 「N 个项目 · M 个项目待处理」/「共 N 个项目」。
QString summaryLine(const KpiSet &k);

// ── 里程碑页/里程碑卡的明细口径 ──

struct MsTally {
    int open = 0;
    int done = 0;
    int dropped = 0;
    int unknown = 0;
    bool complete = false; // 明细数 == readCount（false ⇒ 按明细统计的数是下界）
    int readCount = 0;
};

// 按明细 tally（unknown 单列——混进 open/done 都是把「不知道」说成事实）。
// counts 传空指针时 complete=false（无法对账 ⇒ 按下界处理）。
MsTally milestoneTally(const QVector<Milestone> &items, const MilestoneCounts *counts);

// 按项目分组，保持首现顺序（明细本身按项目成组，不额外排序）。
QVector<QPair<QString, QVector<Milestone>>> milestoneGroups(const QVector<Milestone> &items);

// 按范围收窄明细（project 空 = 全部）。收窄的是**明细**；全局 counts 没有项目维度，
// 收窄后不能继续报它。
QVector<Milestone> milestonesForProject(const std::vector<Milestone> &items, const QString &project);
