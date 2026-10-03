// ProjectStatus.h — `status --json` 的单项目条目（CONTRACT §2.1 逐键）。
//
// 【红线】成功条目恰 32 键；失败桩与成功条目**同键集**再多一个 `error`，
// 计数全 -1。fromJson 对缺失键**整体拒绝**（返回 nullopt）——
// 引擎侧有测试锁定成功态键集（testErrorStatusJsonHasEveryKeyOfSuccessShape），
// 客户端拒绝意味着契约漂移被当场暴露，而不是静默把缺键读成默认值。
//
// mergeHint 与 staleBranches 是仅有的两个顶层可选键（CONTRACT 注明触发条件）。
#pragma once
#include "StatusTypes.h"
#include <QString>
#include <QStringList>
#include <optional>
#include <vector>

struct CommitTypeStat {
    QString type;
    int count = 0;
};

struct DocRef {
    QString file;
    bool exists = false;   // exists=false = 引擎管着它但文件还没建
};

struct ProjectStatus {
    // ── 32 个恒发键 ──
    QString storeHealth;      // ok|corrupt|unreadable
    QString id;
    QString name;
    QString path;
    QString kind;             // git|dir
    QString remote;
    QStringList tags;
    QString headline;
    QString currentBranch;    // 分支名字符串（「该显示哪个分支」的推导在 logic 层）
    QString defaultBranch;
    DirtyState dirty;
    int userDirtyCount = -1;  // -1 = 读不出来（错误桩刻意用 -1，不是 0）
    int stashCount = 0;
    int commitCount = -1;     // 仓库提交总数，-1 = 读不出来
    std::optional<QString> lastCommitAt;  // ISO8601 带时区；空/缺 = 引擎没给
    QString lastCommitAgo;
    std::vector<BranchStatus> branches;
    int repoBranchCount = -1; // 仓库真实分支数；-1 = 读不出来，不是 0
    OverallInfo overall;
    std::vector<DocRef> docs; // {file, exists}
    QStringList manifests;
    std::vector<CommitTypeStat> commitTypes;  // 最近 15 条样本
    bool commitTypesTruncated = false;
    int untrackedCount = -1;
    int worktreeCount = -1;
    ProgressInfo progress;
    std::vector<JournalEntry> journal;
    bool journalTruncated = false;
    int journalLimit = 0;     // JSON 路径恒 8
    int journalUnparsableLines = 0;
    QStringList warnings;
    QString fetchedAt;

    // ── 可选键 ──
    std::optional<QString> error;            // 失败桩原因（「路径不存在或卷未挂载：…」）
    std::optional<MergeHint> mergeHint;      // 仅 git 项目且有合入建议时出现
    std::optional<QStringList> staleBranches; // 进度库记了、git 里已不存在的分支

    bool isGit() const { return kind == QLatin1String("git"); }
    // 采集失败 ⇒ 上面所有计数都是未知（-1），不是 0
    bool isUnreadable() const { return error.has_value(); }

    // 解析失败（缺任一恒发键）→ nullopt
    static std::optional<ProjectStatus> fromJson(const class QJsonObject &o);
};
