// DashFilter.h — 仪表盘/看板共用的筛选状态（mac Models.swift:452-494 + DashboardScope.swift 对位）。
//
// 【红线】
// · 时间窗挂 `lastCommitAt`（毫秒差整除 86400000，对齐引擎 active7d/30d 桶）；
//   读不出来 → **任何窗口都保留**（滤掉等于说「它不在近 7 天内」，真相是「不知道」）。
// · 提交类型筛选**只影响堆叠条与图例，不改 KPI**（commitTypes 是引擎的最近样本，
//   拿样本算「全局提交总数」是拿小样本充总量）。
// · 仪表盘与看板**共用同一份筛选状态**（两个视图不许各持一份）。
#pragma once
#include <QString>
#include <vector>

class ProjectStatus;
struct CommitTypeStat;

enum class TimeWindow {
    all,
    days30,
    days7,
};

// 「全量 / 近 30 天 / 近 7 天」（筛选行的三档标签）。
QString timeWindowLabel(TimeWindow w);
// help 原文：「按项目最近一次更新的天数分档（不是统计这段时间内的提交量）」。
QString timeWindowHelp();

struct DashFilter {
    TimeWindow window = TimeWindow::all;
    QString commitType; // 空 = 所有提交类型

    // 项目是否落在时间窗内（判定依据 daysSinceLastCommit，不是 primaryBranch.staleDays）。
    bool keeps(const ProjectStatus &p) const;

    // 堆叠条/图例要不要画这一类（只作用于提交结构条）。
    bool typeAllowed(const QString &type) const;

    // 「全量」/「近 30 天」/「近 7 天」——「N/M 个项目（最近更新在 近 7 天）」用。
    QString windowLabel() const { return timeWindowLabel(window); }
};

// 项目行的可见性（侧栏搜索用）：名称或任一分支名包含查询（大小写不敏感子串）。
bool projectMatchesQuery(const ProjectStatus &p, const QString &query);
