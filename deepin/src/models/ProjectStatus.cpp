#include "ProjectStatus.h"
#include "EngineJson.h"
#include <QJsonObject>

// 本文件是 status 命令全部嵌套类型的**唯一**键名出处：
// DirtyState/BranchStatus/MergeHint/ProgressInfo/OverallInfo/JournalEntry/DocRef/
// CommitTypeStat/ProjectStatus。

DirtyState DirtyState::fromJson(const QJsonObject &o)
{
    DirtyState d;
    d.clean = EngineJson::boolAt(o, "clean");
    d.ok = EngineJson::boolAt(o, "ok");
    const QJsonValue err = EngineJson::take(o, "err");
    if (err.isString())
        d.err = err.toString();
    d.staged = EngineJson::intAt(o, "staged", 0);
    d.modified = EngineJson::intAt(o, "modified", 0);
    d.untracked = EngineJson::intAt(o, "untracked", 0);
    d.conflicts = EngineJson::intAt(o, "conflicts", 0);
    d.total = EngineJson::intAt(o, "total", 0);
    d.files = EngineJson::strArrAt(o, "files");
    return d;
}

MergeHint MergeHint::fromJson(const QJsonObject &o)
{
    MergeHint m;
    m.kind = EngineJson::strAt(o, "kind");
    m.ahead = EngineJson::intAt(o, "ahead", 0);
    m.behind = EngineJson::intAt(o, "behind", 0);
    m.defaultBranch = EngineJson::strAt(o, "defaultBranch");
    m.target = EngineJson::strAt(o, "target");
    m.description = EngineJson::strAt(o, "description");
    return m;
}

BranchStatus BranchStatus::fromJson(const QJsonObject &o)
{
    BranchStatus b;
    b.name = EngineJson::strAt(o, "name");
    b.status = EngineJson::strAt(o, "status");
    b.statusLabel = EngineJson::strAt(o, "statusLabel");
    b.head = EngineJson::strAt(o, "head");
    b.headShort = EngineJson::strAt(o, "headShort");
    b.headDate = EngineJson::strAt(o, "headDate");
    b.headAgo = EngineJson::strAt(o, "headAgo");
    b.headSubject = EngineJson::strAt(o, "headSubject");
    b.summary = EngineJson::strAt(o, "summary");
    const QJsonValue hl = EngineJson::take(o, "highlights");
    if (hl.isArray()) {
        QStringList list;
        for (const QJsonValue &v : hl.toArray())
            list << v.toString();
        b.highlights = list;
    }
    const QJsonValue ns = EngineJson::take(o, "nextSteps");
    if (ns.isArray()) {
        QStringList list;
        for (const QJsonValue &v : ns.toArray())
            list << v.toString();
        b.nextSteps = list;
    }
    b.aheadOfDefault = EngineJson::intAt(o, "aheadOfDefault", 0);
    b.merged = EngineJson::boolAt(o, "merged");
    b.pendingCommits = EngineJson::intAt(o, "pendingCommits", 0);
    b.baselineReset = EngineJson::boolAt(o, "baselineReset");
    b.provider = EngineJson::strAt(o, "provider");
    b.isCurrent = EngineJson::boolAt(o, "isCurrent");
    b.isDefault = EngineJson::boolAt(o, "isDefault");
    b.updatedAt = EngineJson::strAt(o, "updatedAt");
    b.staleDays = EngineJson::intAt(o, "staleDays", -1);
    return b;
}

ProgressInfo ProgressInfo::fromJson(const QJsonObject &o)
{
    ProgressInfo p;
    p.updatedAt = EngineJson::strAt(o, "updatedAt");
    p.lastUpdateAt = EngineJson::strAt(o, "lastUpdateAt");
    p.lastTrackAt = EngineJson::strAt(o, "lastTrackAt");
    p.lastDeepAt = EngineJson::strAt(o, "lastDeepAt");
    p.entryCount = EngineJson::intAt(o, "entryCount", 0);
    p.entryCountTruncated = EngineJson::boolAt(o, "entryCountTruncated");
    p.entriesKept = EngineJson::intAt(o, "entriesKept", 0);
    p.runCount = EngineJson::intAt(o, "runCount", 0);
    return p;
}

OverallInfo OverallInfo::fromJson(const QJsonObject &o)
{
    OverallInfo w;
    const QJsonValue s = EngineJson::take(o, "summary");
    if (s.isString())
        w.summary = s.toString();
    const QJsonValue n = EngineJson::take(o, "notes");
    if (n.isArray()) {
        QStringList list;
        for (const QJsonValue &v : n.toArray())
            list << v.toString();
        w.notes = list;
    }
    return w;
}

JournalEntry JournalEntry::fromJson(const QJsonObject &o)
{
    JournalEntry j;
    j.id = EngineJson::strAt(o, "id");
    j.at = EngineJson::strAt(o, "at");
    j.project = EngineJson::strAt(o, "project");
    j.projectId = EngineJson::strAt(o, "projectId");
    j.branch = EngineJson::strAt(o, "branch");
    j.mode = EngineJson::strAt(o, "mode");
    j.source = EngineJson::strAt(o, "source");
    j.provider = EngineJson::strAt(o, "provider");
    j.providerLabel = EngineJson::strAt(o, "providerLabel");
    j.commitCount = EngineJson::intAt(o, "commitCount", 0);
    j.commitCountScope = EngineJson::strAt(o, "commitCountScope");
    j.commitCountTruncated = EngineJson::boolAt(o, "commitCountTruncated");
    j.repoBranchCount = EngineJson::intAt(o, "repoBranchCount", -1);
    j.branchCountTruncated = EngineJson::boolAt(o, "branchCountTruncated");
    j.summary = EngineJson::strAt(o, "summary");
    j.highlights = EngineJson::strArrAt(o, "highlights");
    j.nextSteps = EngineJson::strArrAt(o, "nextSteps");
    j.notes = EngineJson::strArrAt(o, "notes");
    // docs 键仅 deep 条目有；缺键与空数组是两种事实，不能压成一种
    const QJsonValue docs = EngineJson::take(o, "docs");
    if (docs.isArray()) {
        QStringList list;
        for (const QJsonValue &v : docs.toArray())
            list << v.toString();
        j.docs = list;
    }
    return j;
}

std::optional<ProjectStatus> ProjectStatus::fromJson(const QJsonObject &o)
{
    // 成功条目 32 恒发键；失败桩同键集 + error。缺任一恒发键 → 整体拒绝。
    static const char *kRequired[] = {
        "storeHealth", "id", "name", "path", "kind", "remote", "tags", "headline",
        "currentBranch", "defaultBranch", "dirty", "userDirtyCount", "stashCount",
        "commitCount", "lastCommitAt", "lastCommitAgo", "branches", "repoBranchCount",
        "overall", "docs", "manifests", "commitTypes", "commitTypesTruncated",
        "untrackedCount", "worktreeCount", "progress", "journal", "journalTruncated",
        "journalLimit", "journalUnparsableLines", "warnings", "fetchedAt",
    };
    for (const char *k : kRequired) {
        if (!o.contains(QLatin1String(k)))
            return std::nullopt;
    }

    ProjectStatus p;
    p.storeHealth = EngineJson::strAt(o, "storeHealth");
    p.id = EngineJson::strAt(o, "id");
    p.name = EngineJson::strAt(o, "name");
    p.path = EngineJson::strAt(o, "path");
    p.kind = EngineJson::strAt(o, "kind");
    p.remote = EngineJson::strAt(o, "remote");
    p.tags = EngineJson::strArrAt(o, "tags");
    p.headline = EngineJson::strAt(o, "headline");
    p.currentBranch = EngineJson::strAt(o, "currentBranch");
    p.defaultBranch = EngineJson::strAt(o, "defaultBranch");

    const QJsonValue dirty = EngineJson::take(o, "dirty");
    p.dirty = dirty.isObject() ? DirtyState::fromJson(dirty.toObject()) : DirtyState{};

    p.userDirtyCount = EngineJson::intAt(o, "userDirtyCount", -1);
    p.stashCount = EngineJson::intAt(o, "stashCount", 0);
    p.commitCount = EngineJson::intAt(o, "commitCount", -1);
    const QJsonValue lca = EngineJson::take(o, "lastCommitAt");
    if (lca.isString())
        p.lastCommitAt = lca.toString(); // 空串也收：非 git 项目引擎发空/不给
    p.lastCommitAgo = EngineJson::strAt(o, "lastCommitAgo");

    for (const QJsonValue &v : EngineJson::arrAt(o, "branches")) {
        if (v.isObject())
            p.branches.push_back(BranchStatus::fromJson(v.toObject()));
    }
    p.repoBranchCount = EngineJson::intAt(o, "repoBranchCount", -1);

    const QJsonValue overall = EngineJson::take(o, "overall");
    p.overall = overall.isObject() ? OverallInfo::fromJson(overall.toObject()) : OverallInfo{};

    for (const QJsonValue &v : EngineJson::arrAt(o, "docs")) {
        if (!v.isObject())
            continue;
        const QJsonObject d = v.toObject();
        p.docs.push_back(DocRef{ EngineJson::strAt(d, "file"), EngineJson::boolAt(d, "exists") });
    }
    p.manifests = EngineJson::strArrAt(o, "manifests");

    for (const QJsonValue &v : EngineJson::arrAt(o, "commitTypes")) {
        if (!v.isObject())
            continue;
        const QJsonObject c = v.toObject();
        p.commitTypes.push_back(
            CommitTypeStat{ EngineJson::strAt(c, "type"), EngineJson::intAt(c, "count", 0) });
    }
    p.commitTypesTruncated = EngineJson::boolAt(o, "commitTypesTruncated");
    p.untrackedCount = EngineJson::intAt(o, "untrackedCount", -1);
    p.worktreeCount = EngineJson::intAt(o, "worktreeCount", -1);

    const QJsonValue progress = EngineJson::take(o, "progress");
    p.progress = progress.isObject() ? ProgressInfo::fromJson(progress.toObject()) : ProgressInfo{};

    for (const QJsonValue &v : EngineJson::arrAt(o, "journal")) {
        if (v.isObject())
            p.journal.push_back(JournalEntry::fromJson(v.toObject()));
    }
    p.journalTruncated = EngineJson::boolAt(o, "journalTruncated");
    p.journalLimit = EngineJson::intAt(o, "journalLimit", 0);
    p.journalUnparsableLines = EngineJson::intAt(o, "journalUnparsableLines", 0);
    p.warnings = EngineJson::strArrAt(o, "warnings");
    p.fetchedAt = EngineJson::strAt(o, "fetchedAt");

    // ── 可选键 ──
    const QJsonValue err = EngineJson::take(o, "error");
    if (err.isString())
        p.error = err.toString();
    const QJsonValue mh = EngineJson::take(o, "mergeHint");
    if (mh.isObject())
        p.mergeHint = MergeHint::fromJson(mh.toObject());
    const QJsonValue sb = EngineJson::take(o, "staleBranches");
    if (sb.isArray()) {
        QStringList list;
        for (const QJsonValue &v : sb.toArray())
            list << v.toString();
        p.staleBranches = list;
    }
    return p;
}
