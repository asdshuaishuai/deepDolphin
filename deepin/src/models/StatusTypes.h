// StatusTypes.h — status/journal 载荷的内嵌类型（CONTRACT §2.1/§2.4 逐键）。
//
// 【边界】结构体字段名 = CONTRACT 键名（驼峰化）；JSON 键名字符串只出现在
// 各 fromJson 里。「可选」键用 std::optional 承载；「未知/读不到 = -1」用 int 原样承载，
// 语义判断（「读不出来 ≠ 0」）交给 logic 层（PLAN 里程碑 2 的 logic/Derived）。
#pragma once
#include <QString>
#include <QStringList>
#include <optional>

// ── 工作区脏度（CONTRACT：clean、ok、err 仅 !ok 时有、staged、modified、
//    untracked、conflicts、total、files[] 最多 30 条）──
struct DirtyState {
    bool clean = false;
    bool ok = false;                       // 非 true ⇒ 数字不可信
    std::optional<QString> err;            // 仅 ok=false 时有
    int staged = 0;
    int modified = 0;
    int untracked = 0;
    int conflicts = 0;
    int total = 0;
    QStringList files;

    static DirtyState fromJson(const class QJsonObject &o);
};

// ── 合入提示（CONTRACT §2.1：可选——仅 git 项目且有合入建议时出现）──
// kind ∈ fast-forward|merge|rebase|no-default|merged；
// 注意 rebase/no-default 不当合入提示（消费方判 kind）。
struct MergeHint {
    QString kind;
    int ahead = 0;
    int behind = 0;
    QString defaultBranch;
    QString target;
    QString description;

    static MergeHint fromJson(const class QJsonObject &o);
};

// ── 分支条目（CONTRACT：20 键，flow/status.cj:83-140）──
struct BranchStatus {
    QString name;
    QString status;        // active(3 天内)|idle(14 天内)|stale(>14 天)|merged
    QString statusLabel;   // 本地化文案
    QString head;          // 完整 SHA
    QString headShort;
    QString headDate;
    QString headAgo;
    QString headSubject;   // 可为空串
    QString summary;
    std::optional<QStringList> highlights;
    std::optional<QStringList> nextSteps;
    int aheadOfDefault = 0;
    bool merged = false;
    int pendingCommits = 0;    // 实时计算：head 空/baselineReset/>500 时报 0
    bool baselineReset = false;
    QString provider;          // 默认 "rules"
    bool isCurrent = false;
    bool isDefault = false;
    QString updatedAt;
    int staleDays = -1;        // -1 = 未知

    static BranchStatus fromJson(const class QJsonObject &o);
};

// ── 进度元信息（CONTRACT：8 键恒发）──
struct ProgressInfo {
    QString updatedAt;
    QString lastUpdateAt;
    QString lastTrackAt;
    QString lastDeepAt;
    int entryCount = 0;             // 真实总数，可能与 entriesKept 不同
    bool entryCountTruncated = false;
    int entriesKept = 0;
    int runCount = 0;

    static ProgressInfo fromJson(const class QJsonObject &o);
};

// ── overall 对象（CONTRACT：{summary, notes[]}；错误桩发空对象 {}，
//    所以两个成员都必须可缺席——见 mac Models.swift OverallMeta 的教训）──
struct OverallInfo {
    std::optional<QString> summary;
    std::optional<QStringList> notes;

    static OverallInfo fromJson(const class QJsonObject &o);
};

// ── journal 条目（CONTRACT §2.4：journalEntryJson 唯一形状，全部出口一致）──
// docs 键仅 deep 条目有（浅更新压根不写这个键 → std::optional，nil≠[]）。
struct JournalEntry {
    QString id;
    QString at;
    QString project;
    QString projectId;
    QString branch;
    QString mode;               // "shallow"|"deep"|…("track"/"manual")
    QString source;
    QString provider;
    QString providerLabel;
    int commitCount = 0;        // -1 = 读不出来
    QString commitCountScope;   // "new"=本轮新增 | "repoTotal"=仓库总数
    bool commitCountTruncated = false;
    int repoBranchCount = -1;   // -1 = 未知
    bool branchCountTruncated = false;
    QString summary;
    QStringList highlights;
    QStringList nextSteps;
    QStringList notes;
    std::optional<QStringList> docs; // 仅 deep 条目有

    static JournalEntry fromJson(const class QJsonObject &o);
};
