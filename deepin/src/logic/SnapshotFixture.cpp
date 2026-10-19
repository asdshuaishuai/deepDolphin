// SnapshotFixture.cpp — 面板快照夹具（批 T）。
//
// 【纪律】本文件**只产出 JSON**，不碰任何 UI 头（判定层红线）——
//   夹具走**真实的解析路径**（AppModel → StatusEnvelope::decodeEnvelopeOrBare
//   / DashboardData::fromJson / MilestonesEnvelope::fromJson），
//   所以它顺带覆盖了契约解析，而不只是「摆一堆好看的字」。
#include "SnapshotFixture.h"

#include <QDate>
#include <QDateTime>
#include <QString>

namespace {
/// 故事基准日（固定）—— 夹具里所有**绝对日期**都从它派生。
/// 为什么固定：绝对日期一旦跟着「今天」走，基线每天 UTC 午夜就变一次
///   ⇒ CI 天天有 diff ⇒ 人就学会忽略 diff ⇒ 基线又变成空门。
const char kAnchorDate[] = "2026-01-15";

/// 故事基准时刻（UTC 12:00）—— 绝对时刻类字段（fetchedAt/generatedAt/updatedAt）用它。
const char kAnchorMoment[] = "2026-01-15T12:00:00Z";

/// 距今 n 小时的 ISO8601（UTC）—— **只给会被算天数的 lastCommitAt 用**。
QString hoursAgoIso(int h)
{
    return QDateTime::currentDateTimeUtc().addSecs(-h * 3600).toString(Qt::ISODate);
}

/// 距今 n 天的 ISO8601（UTC）—— 同上，**只给 lastCommitAt 用**。
QString daysAgoIso(int d)
{
    return QDateTime::currentDateTimeUtc().addSecs(-d * 86400).toString(Qt::ISODate);
}

/// 基准日的 ISO8601 时刻（固定）。
QString anchorMomentIso()
{
    return QString::fromLatin1(kAnchorMoment);
}

/// 基准日（YYYY-MM-DD，固定）—— 夹具里的「今天」。
QString anchorDate()
{
    return QString::fromLatin1(kAnchorDate);
}

/// 基准日 + n 天（YYYY-MM-DD，固定）。
QString anchorPlusDays(int d)
{
    return QDate::fromString(QString::fromLatin1(kAnchorDate), Qt::ISODate)
        .addDays(d).toString(Qt::ISODate);
}

/// 基准日 - n 天（YYYY-MM-DD，固定）。
QString anchorMinusDays(int d)
{
    return anchorPlusDays(-d);
}

/// 一条分支的 JSON。
QString branchJson(const QString &name, const QString &status, const QString &label,
    const QString &head, const QString &headShort, const QString &headDate, const QString &headAgo,
    const QString &subject, int ahead, bool merged, bool isCurrent, bool isDefault, int staleDays)
{
    // ⚠ staleDays = -1（未知）⇒ updatedAt 留空：那档的含义就是「时间戳不可信」，
    //   给个未来的时间戳反而自相矛盾。
    const QString updatedAt = staleDays < 0 ? QString() : anchorMinusDays(staleDays);
    return QStringLiteral(R"({
        "name":"%1","status":"%2","statusLabel":"%3","head":"%4","headShort":"%5",
        "headDate":"%6","headAgo":"%7","headSubject":"%8","summary":"%8",
        "highlights":[],"nextSteps":[],"aheadOfDefault":%9,"merged":%10,"pendingCommits":0,
        "baselineReset":false,"provider":"rules","isCurrent":%11,"isDefault":%12,
        "updatedAt":"%13","staleDays":%14
    })")
        .arg(name, status, label, head, headShort, headDate, headAgo, subject)
        .arg(ahead)
        .arg(merged ? QStringLiteral("true") : QStringLiteral("false"))
        .arg(isCurrent ? QStringLiteral("true") : QStringLiteral("false"))
        .arg(isDefault ? QStringLiteral("true") : QStringLiteral("false"))
        .arg(updatedAt, QString::number(staleDays));
}

/// 一个 status 项目的 JSON（32 恒发键，形状照 CONTRACT §2.1）。
/// `body` 是项目特有的那几项（branches / dirty / 计数 / 时间）。
///
/// ⚠ 这里**用 replace 逐个替换**而不是 `QString::arg`：arg 对**重复的占位符**
///   只替换第一次（`%11` 出现两次 → 第二个原样留在 JSON 里 → 解析直接失败）。
///   这个坑踩过一次就记住：模板里同一个占位符只能出现一次。
QString projectJson(const QString &id, const QString &name, const QString &path, const QString &kind,
    const QString &branches, int branchCount, const QString &dirty, int userDirtyCount, int untrackedCount,
    const QString &lastCommitAt, const QString &lastCommitAgo, int commitCount,
    const QString &headline, const QString &error, const QString &overall, const QString &commitTypes)
{
    QString s = QStringLiteral(R"({
        "storeHealth":"ok","id":"@id","name":"@name","path":"@path","kind":"@kind","remote":"origin",
        "tags":[],"headline":"@headline","currentBranch":"main","defaultBranch":"main",
        "dirty":@dirty,
        "userDirtyCount":@userDirtyCount,"stashCount":0,"commitCount":@commitCount,
        "lastCommitAt":"@lastCommitAt","lastCommitAgo":"@lastCommitAgo",
        "branches":[@branches],
        "repoBranchCount":@branchCount,"overall":@overall,"docs":[{"file":"README.md","exists":true}],
        "manifests":["package.json"],"commitTypes":@commitTypes,
        "commitTypesTruncated":false,"untrackedCount":@untrackedCount,"worktreeCount":@untrackedCount,
        "progress":{"updatedAt":"@moment","lastUpdateAt":"@moment","lastTrackAt":"@moment","lastDeepAt":"",
                    "entryCount":3,"entryCountTruncated":false,"entriesKept":3,"runCount":7},
        "journal":[],"journalTruncated":false,"journalLimit":8,"journalUnparsableLines":0,
        "warnings":[],"fetchedAt":"@moment"
        @error
    })");
    s.replace(QStringLiteral("@id"), id);
    s.replace(QStringLiteral("@name"), name);
    s.replace(QStringLiteral("@path"), path);
    s.replace(QStringLiteral("@kind"), kind);
    s.replace(QStringLiteral("@headline"), headline);
    s.replace(QStringLiteral("@dirty"), dirty);
    s.replace(QStringLiteral("@userDirtyCount"), QString::number(userDirtyCount));
    s.replace(QStringLiteral("@commitCount"), QString::number(commitCount));
    // ⚠ **@lastCommitAt 是整个夹具里唯一跟着真实 now 走的字段**。
    //   因为 `Derived::daysSinceLastCommit` 要拿它跟「真实现在」比 epoch 算天数
    //   —— 写死的话「40 天没更新」会随日子一天天变 ⇒ 基线天天漂。
    //   其余时间戳（@moment）一律锚定基准日 ⇒ 绝对日期不随日子变。
    s.replace(QStringLiteral("@lastCommitAt"), lastCommitAt);
    s.replace(QStringLiteral("@lastCommitAgo"), lastCommitAgo);
    s.replace(QStringLiteral("@branches"), branches);
    s.replace(QStringLiteral("@branchCount"), QString::number(branchCount));
    s.replace(QStringLiteral("@overall"), overall);
    s.replace(QStringLiteral("@commitTypes"), commitTypes);
    s.replace(QStringLiteral("@untrackedCount"), QString::number(untrackedCount));
    s.replace(QStringLiteral("@moment"), anchorMomentIso());
    s.replace(QStringLiteral("@error"), error);
    return s;
}

/// 4 条里程碑的 items 数组 —— **两处载荷共用同一份文本**。
///   之前 dashboard 与 milestone list 各写一份，两边对 cygnus 的 targetDate
///   说的不是一回事（一边有日期、一边空）⇒ 同一件事在两个页面说得不一样。
///   里程碑是「同一个对象」⇒ 只许有一份文本。
QString milestoneItemsJson()
{
    return QStringLiteral(R"([
        {"projectId":"p_atlas","name":"v1.0","description":"首个正式版本","targetDate":"%1","tag":"v1.0",
         "status":"open","createdAt":"%2","completedAt":"","projectName":"atlas","tagName":"v1.0",
         "tagReached":false,"commitsSince":18,"commitsSinceReadable":true,"daysToTarget":30,
         "overdue":false,"gitReadable":true,"unverifiedReason":""},
        {"projectId":"p_borealis","name":"性能基线","description":"建立性能基线","targetDate":"%1","tag":"",
         "status":"done","createdAt":"%2","completedAt":"%3","projectName":"borealis","tagName":"",
         "tagReached":false,"commitsSince":25,"commitsSinceReadable":true,"daysToTarget":30,
         "overdue":false,"gitReadable":true,"unverifiedReason":""},
        {"projectId":"p_cygnus","name":"重构","description":"引擎层重构","targetDate":"","tag":"",
         "status":"dropped","createdAt":"%2","completedAt":"","projectName":"cygnus","tagName":"",
         "tagReached":false,"commitsSince":-1,"commitsSinceReadable":false,"daysToTarget":-1,
         "overdue":false,"gitReadable":true,"unverifiedReason":""},
        {"projectId":"p_fennec","name":"长期计划","description":"暂缓","targetDate":"","tag":"",
         "status":"unknown","createdAt":"%2","completedAt":"","projectName":"fennec","tagName":"",
         "tagReached":false,"commitsSince":-1,"commitsSinceReadable":false,"daysToTarget":-1,
         "overdue":false,"gitReadable":false,"unverifiedReason":"仓库不可读"}
    ])")
        .arg(anchorPlusDays(30), anchorMinusDays(30), anchorMinusDays(2));
}
} // namespace

namespace SnapshotFixture {

QByteArray statusJson()
{
    // ── 7 个项目，一档一个 Liveness ──────────────────────────
    // atlas    : recent      —— 绿（今天更新过）
    // borealis : needsAction —— 橙（有未提交改动）
    // cygnus   : engineStale —— 灰（引擎判定停滞：分支 stale）
    // draco    : notGit      —— 灰（非 git 目录）
    // eris     : unreadable  —— 红（采集失败）
    // fennec   : quiet       —— 灰（40 天没更新）
    // gemini   : unknown     —— 红（提交时间读不出来）
    const QString cleanDirty = QStringLiteral(R"({"clean":true,"ok":true,"err":"","staged":0,"modified":0,"untracked":0,"conflicts":0,"total":0,"files":[]})");
    const QString dirtyDirty = QStringLiteral(R"({"clean":false,"ok":true,"err":"","staged":1,"modified":2,"untracked":1,"conflicts":0,"total":4,"files":["src/app.cpp","docs/plan.md"]})");
    const QString failDirty = QStringLiteral(R"({"clean":false,"ok":false,"err":"读不出来","staged":0,"modified":0,"untracked":0,"conflicts":0,"total":0,"files":[]})");

    // atlas：4 条分支，把分支状态 5 档盖住（active/idle/merged/unknown + cygnus 的 stale）
    // ⚠ headDate 一律**锚定基准日**（跟着 headAgo 走：今天 = 基准日，5 天前 = 基准日-5）
    const QString atlasBranches = branchJson(QStringLiteral("main"), QStringLiteral("active"),
                                     QStringLiteral("活跃"), QStringLiteral("0123456789abcdef0123456789abcdef01234567"),
                                     QStringLiteral("0123456"), anchorDate(), QStringLiteral("今天"),
                                     QStringLiteral("feat: 快照夹具"), 0, false, true, true, 0)
        + QStringLiteral(",")
        // ⚠ ahead 必须是 0 —— ahead>0 会触发 needsAction（优先级高于 recent），
        //   atlas 就不是「绿点」那一档了（侧栏会全是橙/灰/红，看不出 recent 档）。
        + branchJson(QStringLiteral("feat/snapshot"), QStringLiteral("idle"), QStringLiteral("平缓"),
            QStringLiteral("111122223333444455556666777788889999aaa"), QStringLiteral("1111222"),
            anchorMinusDays(5), QStringLiteral("5 天前"), QStringLiteral("feat: 夹具分支"), 0, false, false, false, 5)
        + QStringLiteral(",")
        + branchJson(QStringLiteral("release/1.0"), QStringLiteral("merged"), QStringLiteral("已合并"),
            QStringLiteral("aaaabbbbccccddddeeeeffff0000111122223333"), QStringLiteral("aaaabbb"),
            anchorDate(), QStringLiteral("今天"), QStringLiteral("chore: 发布准备"), 0, true, false, false, 0)
        + QStringLiteral(",")
        + branchJson(QStringLiteral("wip/unknown"), QStringLiteral("unknown"), QStringLiteral("未知"),
            QStringLiteral(""), QStringLiteral(""), QStringLiteral(""), QStringLiteral(""),
            QStringLiteral(""), 0, false, false, false, -1);

    const QString cygnusBranches = branchJson(QStringLiteral("main"), QStringLiteral("stale"),
                                      QStringLiteral("陈旧"), QStringLiteral("9999888877776666555544443333222211110000"),
                                      QStringLiteral("9999888"), anchorMinusDays(40),
                                      QStringLiteral("40 天前"), QStringLiteral("fix: 很久以前"), 0, false, true, true, 40);

    // 名字故意取长：让名称截断/换行也被基线盯住
    const QString atlas = projectJson(QStringLiteral("p_atlas"), QStringLiteral("atlas"),
        QStringLiteral("/srv/projects/atlas"), QStringLiteral("git"), atlasBranches, 4, cleanDirty,
        0, 0, hoursAgoIso(3), QStringLiteral("今天"), 128,
        QStringLiteral("一切正常"), QString(), QStringLiteral(R"({"summary":"项目推进中","notes":[]})"),
        QStringLiteral(R"([{"type":"feat","count":12},{"type":"fix","count":8},{"type":"docs","count":3}])"));

    const QString borealis = projectJson(QStringLiteral("p_borealis"), QStringLiteral("borealis"),
        QStringLiteral("/srv/projects/borealis"), QStringLiteral("git"),
        branchJson(QStringLiteral("main"), QStringLiteral("active"), QStringLiteral("活跃"),
            QStringLiteral("bbbcccccdddeeeeffff00001111222233334444"), QStringLiteral("bbbcccc"),
            anchorDate(), QStringLiteral("今天"), QStringLiteral("chore: 清理"), 3, false, true, true, 0),
        1, dirtyDirty, 3, 1, hoursAgoIso(20), QStringLiteral("昨天"), 64,
        QStringLiteral("4 处未提交"), QString(), QStringLiteral(R"({"summary":"有未提交改动","notes":["工作区有改动"]})"),
        QStringLiteral(R"([{"type":"fix","count":5},{"type":"chore","count":2}])"));

    const QString cygnus = projectJson(QStringLiteral("p_cygnus"), QStringLiteral("cygnus"),
        QStringLiteral("/srv/projects/cygnus"), QStringLiteral("git"), cygnusBranches, 1, cleanDirty,
        0, 0, daysAgoIso(40), QStringLiteral("40 天前"), 210,
        QStringLiteral("停滞"), QString(), QStringLiteral(R"({"summary":"停滞","notes":["主分支 40 天没更新"]})"),
        QStringLiteral(R"([{"type":"fix","count":9}])"));

    const QString draco = projectJson(QStringLiteral("p_draco"), QStringLiteral("draco-notes"),
        QStringLiteral("/srv/projects/draco-notes"), QStringLiteral("dir"), QString(),
        0, cleanDirty, 0, 0, QString(), QString(), -1,
        QStringLiteral("非 git 目录"), QString(), QStringLiteral(R"({"summary":"不是仓库","notes":[]})"),
        QStringLiteral("[]"));

    const QString eris = projectJson(QStringLiteral("p_eris"), QStringLiteral("eris"),
        QStringLiteral("/srv/projects/eris"), QStringLiteral("git"), QString(), 0, failDirty,
        -1, -1, QString(), QString(), -1,
        QStringLiteral("状态获取失败"),
        QStringLiteral(",\"error\":\"路径不存在或卷未挂载：/srv/projects/eris\""),
        QStringLiteral(R"({"summary":"读不出来","notes":[]})"), QStringLiteral("[]"));

    const QString fennec = projectJson(QStringLiteral("p_fennec"), QStringLiteral("fennec"),
        QStringLiteral("/srv/projects/fennec"), QStringLiteral("git"),
        branchJson(QStringLiteral("main"), QStringLiteral("idle"), QStringLiteral("平缓"),
            QStringLiteral("ccc4444dddd5555eeee6666ffff7777aaaa8888"), QStringLiteral("ccc4444"),
            anchorMinusDays(40), QStringLiteral("40 天前"), QStringLiteral("feat: 很久以前"), 0, false, true, true, 40),
        1, cleanDirty, 0, 0, daysAgoIso(40), QStringLiteral("40 天前"), 33,
        QStringLiteral("40 天没更新"), QString(), QStringLiteral(R"({"summary":"很久没动","notes":[]})"),
        QStringLiteral(R"([{"type":"docs","count":1}])"));

    const QString gemini = projectJson(QStringLiteral("p_gemini"), QStringLiteral("gemini"),
        QStringLiteral("/srv/projects/gemini"), QStringLiteral("git"), QString(),
        0, cleanDirty, 0, 0, QString(), QString(), 12,
        QStringLiteral("状态读不出来"), QString(), QStringLiteral(R"({"summary":"读不出来","notes":[]})"),
        QStringLiteral("[]"));

    const QString summary = QStringLiteral(R"({
        "projectCount":7,"listedProjects":7,"failedProjects":1,"degradedStores":0,
        "activeProjects":3,"staleProjects":1,"dirtyProjects":1,"branchCount":6,
        "repoBranchTotal":6,"branchTruncatedProjects":0,"branchUnknownProjects":0,
        "generatedAt":"%1"
    })")
                                .arg(anchorMomentIso());

    return QStringLiteral(R"({"projects":[%1],"summary":%2,"language":"zh"})")
        .arg(QStringLiteral("%1,%2,%3,%4,%5,%6,%7")
                 .arg(atlas, borealis, cygnus, draco, eris, fennec, gemini),
            summary)
        .toUtf8();
}

QByteArray dashboardJson()
{
    // ⚠ counts 必须与 items **对得上**（open+done+dropped+unknown+other = readCount = 条数）。
    //   之前 counts 写 open:2 / readCount:5，而 items 只有 4 条、open 只有 1 条
    //   ⇒ 侧栏「里程碑 ●3」与列表里的「2 个未完成」自相矛盾 ⇒ 基线把矛盾固化了。
    const QString milestones = QStringLiteral(R"({
        "counts":{"open":1,"done":1,"dropped":1,"unknown":1,"other":0,"storeHealth":"ok",
                  "degraded":false,"readCount":4,"excludedDisabled":0,"orphaned":0},
        "items":%1})")
                      .arg(milestoneItemsJson());

    return QStringLiteral(R"({
        "projects":{"total":7,"listed":7,"registered":8,"excludedDisabled":1,"failed":1,"dirty":1,"active7d":3,"active30d":4},
        "work":{"branches":6,"mergeCandidates":1,"untrackedFiles":2,"stashes":0},
        "languages":[{"language":"C++","count":128},{"language":"Rust","count":42},
                     {"language":"Python","count":17},{"language":"Shell","count":6}],
        "languagesTruncated":false,"languagesTopCut":false,"languagesFailed":1,
        "languagesFailedReasons":["路径不存在或卷未挂载：/srv/projects/eris"],
        "milestones":%1,
        "activeProjects":[{"name":"atlas","lastCommitAgo":"今天","headline":"一切正常"},
                          {"name":"borealis","lastCommitAgo":"昨天","headline":"4 处未提交"},
                          {"name":"gemini","lastCommitAgo":"","headline":"状态读不出来"}],
        "fetchedAt":"%2"
    })")
        .arg(milestones, anchorMomentIso())
        .toUtf8();
}

QByteArray milestonesJson()
{
    return QStringLiteral(R"({
        "milestones":%1,
        "storeHealth":"ok",
        "readCount":4,
        "orphaned":[],
        "excludedDisabled":0
    })")
        .arg(milestoneItemsJson())
        .toUtf8();
}

qint64 fixedRefreshedMs()
{
    // 故事基准时刻（UTC 12:00）—— 固定 epoch。
    // 配合快照进程固定 TZ=UTC（main.cpp）⇒ 侧栏渲染成固定的「12:00」。
    return QDateTime::fromString(QString::fromLatin1(kAnchorMoment), Qt::ISODate).toMSecsSinceEpoch();
}

} // namespace SnapshotFixture
