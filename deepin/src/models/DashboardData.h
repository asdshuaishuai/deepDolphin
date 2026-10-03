// DashboardData.h — `dashboard --json` 载荷（CONTRACT §2.2 逐键）。
//
// 口径红线：projects.total = 采集成功数；projects.listed = **参与统计**数（已剔除停用）
// ——仪表盘「总数」必须用 listed 不用 total（logic/DashboardScope 阶段的纪律，
// 模型层先把两键都如实收下）。
#pragma once
#include "Milestone.h"
#include <QString>
#include <QStringList>
#include <optional>

struct DashboardProjects {
    int total = 0;
    int listed = 0;
    int registered = 0;
    int excludedDisabled = 0;
    int failed = 0;
    int dirty = 0;
    int active7d = 0;
    int active30d = 0;
};

struct DashboardWork {
    int branches = 0;
    int mergeCandidates = 0;   // 判据是 aheadOfDefault>0 && !isDefault && !merged（非 pendingCommits）
    int untrackedFiles = 0;
    int stashes = 0;
};

struct LanguageStat {
    QString language;
    int count = 0;
};

struct MilestoneCounts {
    int open = 0;
    int done = 0;
    int dropped = 0;
    int unknown = 0;
    int other = 0;
    QString storeHealth;
    bool degraded = false;
    int readCount = 0;
    int excludedDisabled = 0;
    int orphaned = 0;
};

struct DashboardMilestones {
    MilestoneCounts counts;
    std::vector<Milestone> items;
};

struct DashboardActiveProject {
    QString name;
    QString lastCommitAgo;
    QString headline;
};

struct DashboardData {
    DashboardProjects projects;
    DashboardWork work;
    std::vector<LanguageStat> languages;
    bool languagesTruncated = false;   // 撞 20000 文件上限
    bool languagesTopCut = false;      // 语言条数被 Top12 砍
    int languagesFailed = 0;           // 采集失败项目数
    QStringList languagesFailedReasons;
    DashboardMilestones milestones;
    std::vector<DashboardActiveProject> activeProjects;
    QString fetchedAt;

    // 后四键（languagesTruncated/TopCut/Failed/Reasons）**恒发**：缺键 = 契约过旧 → nullopt
    static std::optional<DashboardData> fromJson(const class QJsonObject &o);
};
