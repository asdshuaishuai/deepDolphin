#include <QNetworkReply>
#include "SelfCheck.h"
#include "SelfCheckInternal.h"
#include "EngineCli.h"
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSet>
#include <QHash>
#include <QTemporaryDir>
#include "../logic/AgentToolPlan.h"
#include "../logic/ArchReceipt.h"
#include "../logic/Backend.h"
#include "../logic/PanelGeometry.h"
#include "../logic/CanvasFont.h"
#include "../logic/CodeGraphBuild.h"
#include "../logic/DashFilter.h"
#include "../logic/Derived.h"
#include "../logic/EngineDownload.h"
#include "../logic/EngineHook.h"
#include "../logic/IconNames.h"
#include "../logic/Liveness.h"
#include "../logic/Notifications.h"
#include "../logic/SemColors.h"
#include "../logic/SnapshotFixture.h"
#include "../logic/DocPages.h"
#include "../logic/DocumentIntegrity.h"
#include "../logic/EngineConfig.h"
#include "../logic/EngineDoctor.h"
#include "../logic/GraphToken.h"
#include "../logic/GraphInsight.h"
#include "../logic/HeatLayout.h"
#include "../logic/IndexStatus.h"
#include "../logic/PatchCheck.h"
#include "../logic/SyntaxHighlight.h"
#include "../logic/ArchViewport.h"
#include "../logic/SceneRender.h"
#include "../logic/Route.h"
#include "../logic/Router.h"
#include "../logic/ShortcutMap.h"
#include "../logic/Thresholds.h"
#include "../logic/DeepinTray.h"
#include "../logic/TraySni.h"
#include "../platform/TraySni.h"
#include "../tray/TrayGeometry.h"
#include "../models/ContextEnvelope.h"
#include "../models/DashboardData.h"
#include "../models/DocsEnvelope.h"
#include "../models/EngineError.h"
#include "../models/EngineFailure.h"
#include "../models/EngineJson.h"
#include "../models/GitOpResponse.h"
#include "../models/JournalEnvelope.h"
#include "../models/Milestone.h"
#include "../models/MilestoneWrite.h"
#include "../models/ProjectEntry.h"
#include "../models/ProjectStatus.h"
#include "../models/ScanResult.h"
#include "../models/StatusEnvelope.h"
#include "../models/ToolsEnvelope.h"
#include "../models/UpdateResult.h"
#include "../models/GraphScene.h"
#include "../models/VerifyEnvelope.h"
#include "../ui/DesignTokens.h"
#include "../ui/common/EmptyState.h"
#include "../ui/common/FlatButton.h"
#include "../ui/common/SegmentedButton.h"
#include "../platform/Canvas2D.h"
#include <QColor>
#include <QDateTime>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QMargins>
#include <QRegularExpression>
#include <QPainter>
#include <QDBusArgument>
#include <QDBusMetaType>

// ⚠ 判据计数与 `check()` 的**唯一实现**在 SelfCheckInternal.h（批 AJ 拆分）。
//   这里只做 using ⇒ 现有的裸调用 `check(log, "…", ok)` 一个字都不用改。
using SelfCheckInternal::check;
using SelfCheckInternal::g_fail;
using SelfCheckInternal::g_pass;
using SelfCheckInternal::J;
// 头文件型模型（Milestone/DocsEnvelope/JournalEnvelope/ScanResult…）的
// fromJson 收 QJsonObject；fixture 以对象形式提供。
using SelfCheckInternal::JO;

namespace {

// ── status 成功条目 fixture：恰 32 恒发键 + mergeHint（键名逐字对 CONTRACT §2.1）──
QString statusProjectJson(const QString &name, bool withError)
{
    if (withError) {
        // 失败桩：同键集 + error；计数 -1
        return QStringLiteral(R"({
            "storeHealth":"ok","id":"p_err","name":"%1","path":"/x/%1","kind":"git","remote":"",
            "tags":[],"headline":"状态获取失败","currentBranch":"","defaultBranch":"",
            "dirty":{"clean":false,"ok":false,"err":"读不出来","staged":0,"modified":0,"untracked":0,"conflicts":0,"total":0,"files":[]},
            "userDirtyCount":-1,"stashCount":-1,"commitCount":-1,"lastCommitAt":"","lastCommitAgo":"",
            "branches":[],"repoBranchCount":-1,"overall":{},"docs":[],"manifests":[],"commitTypes":[],
            "commitTypesTruncated":false,"untrackedCount":-1,"worktreeCount":-1,
            "progress":{"updatedAt":"","lastUpdateAt":"","lastTrackAt":"","lastDeepAt":"","entryCount":0,"entryCountTruncated":false,"entriesKept":0,"runCount":0},
            "journal":[],"journalTruncated":false,"journalLimit":0,"journalUnparsableLines":0,
            "warnings":[],"fetchedAt":"2026-10-03T10:00:00+08:00",
            "error":"路径不存在或卷未挂载：/x/%1"
        })")
            .arg(name);
    }
    return QStringLiteral(R"({
        "storeHealth":"ok","id":"p_ok","name":"%1","path":"/x/%1","kind":"git","remote":"origin",
        "tags":["v1"],"headline":"2 处未提交","currentBranch":"main","defaultBranch":"main",
        "dirty":{"clean":false,"ok":true,"staged":1,"modified":2,"untracked":1,"conflicts":0,"total":4,"files":["a.cpp","b.md"]},
        "userDirtyCount":3,"stashCount":1,"commitCount":42,"lastCommitAt":"2026-10-01T10:00:00+08:00","lastCommitAgo":"2 天前",
        "branches":[{"name":"main","status":"active","statusLabel":"活跃","head":"0123456789abcdef","headShort":"0123456","headDate":"2026-10-01","headAgo":"2 天前","headSubject":"fix: a","summary":"总结","highlights":["更新：a"],"nextSteps":[],"aheadOfDefault":0,"merged":false,"pendingCommits":0,"baselineReset":false,"provider":"rules","isCurrent":true,"isDefault":true,"updatedAt":"2026-10-01T10:00:00+08:00","staleDays":2},
                    {"name":"feat/x","status":"idle","statusLabel":"平缓","head":"1111222233334444","headShort":"1111222","headDate":"2026-09-20","headAgo":"13 天前","headSubject":"feat: x","summary":"总结","highlights":[],"nextSteps":["合回 main"],"aheadOfDefault":2,"merged":false,"pendingCommits":0,"baselineReset":false,"provider":"rules","isCurrent":false,"isDefault":false,"updatedAt":"2026-09-20T10:00:00+08:00","staleDays":13}],
        "repoBranchCount":2,
        "overall":{"summary":"项目推进中","notes":["工作区有 2 处未提交改动"]},
        "docs":[{"file":"README.md","exists":true},{"file":"AGENTS.md","exists":false}],
        "manifests":["package.json"],"commitTypes":[{"type":"fix","count":7},{"type":"feat","count":3}],
        "commitTypesTruncated":false,"untrackedCount":1,"worktreeCount":1,
        "mergeHint":{"kind":"fast-forward","ahead":2,"behind":0,"defaultBranch":"main","target":"main","description":"可直接快进合入"},
        "progress":{"updatedAt":"2026-10-03T08:00:00+08:00","lastUpdateAt":"2026-10-02T08:00:00+08:00","lastTrackAt":"2026-10-01T08:00:00+08:00","lastDeepAt":"","entryCount":5,"entryCountTruncated":false,"entriesKept":5,"runCount":9},
        "journal":[{"id":"j1","at":"2026-10-02T08:00:00+08:00","project":"%1","projectId":"p_ok","branch":"main","mode":"shallow","source":"cli","provider":"rules","providerLabel":"规则","commitCount":3,"commitCountScope":"new","commitCountTruncated":false,"repoBranchCount":2,"branchCountTruncated":false,"summary":"浅更新完成","highlights":[],"nextSteps":[],"notes":[]}],
        "journalTruncated":false,"journalLimit":8,"journalUnparsableLines":0,
        "warnings":["非 git 仓库说明示例"],"fetchedAt":"2026-10-03T10:00:00+08:00"
    })")
        .arg(name);
}

QString statusSummaryJson()
{
    return QStringLiteral(R"({
        "projectCount":2,"listedProjects":3,"failedProjects":1,"degradedStores":0,
        "activeProjects":1,"staleProjects":0,"dirtyProjects":1,"branchCount":2,
        "repoBranchTotal":3,"branchTruncatedProjects":0,"branchUnknownProjects":0,
        "generatedAt":"2026-10-03T10:00:00+08:00"
    })");
}
} // namespace

int SelfCheck::run(QStringList &log)
{
    g_pass = g_fail = 0;

    // ── 0. 面板快照夹具（批 T）────────────────────────────────
    //   面板快照基线必须**可重现** ⇒ 走固定夹具，不走真引擎。
    //   夹具若少覆盖一档状态，基线就少覆盖一档 —— 那是又一种空门。
    {
        const auto env = StatusEnvelope::decodeEnvelopeOrBare(
            QJsonDocument::fromJson(SnapshotFixture::statusJson()));
        check(log, "快照夹具：status 载荷能解析（走真实解析路径）", env.has_value());
        if (env) {
            QSet<int> seen;
            for (const ProjectStatus &p : env->projects)
                seen.insert(static_cast<int>(Derived::liveness(p)));
            check(log, "快照夹具：覆盖 liveness 全部 7 档（少一档 = 基线少一档 = 空门）",
                seen.size() == 7
                    && seen.contains(static_cast<int>(Liveness::recent))
                    && seen.contains(static_cast<int>(Liveness::needsAction))
                    && seen.contains(static_cast<int>(Liveness::engineStale))
                    && seen.contains(static_cast<int>(Liveness::quiet))
                    && seen.contains(static_cast<int>(Liveness::notGit))
                    && seen.contains(static_cast<int>(Liveness::unreadable))
                    && seen.contains(static_cast<int>(Liveness::unknown)));

            QSet<QString> kinds;
            for (const ProjectStatus &p : env->projects)
                for (const BranchStatus &b : p.branches)
                    kinds.insert(b.status);
            check(log, "快照夹具：覆盖分支状态全部 5 档",
                kinds.size() == 5
                    && kinds.contains(QStringLiteral("active"))
                    && kinds.contains(QStringLiteral("idle"))
                    && kinds.contains(QStringLiteral("stale"))
                    && kinds.contains(QStringLiteral("merged"))
                    && kinds.contains(QStringLiteral("unknown")));
        }
        // ⚠ 夹具的时间戳是**相对 now** 生成的 ⇒ 天数恒定。
        //   若哪天改成写死日期，「40 天没更新」会每天变 ⇒ 快照基线天天漂。
        {
            const auto env2 = StatusEnvelope::decodeEnvelopeOrBare(
                QJsonDocument::fromJson(SnapshotFixture::statusJson()));
            int quietDays = -1;
            if (env2) {
                for (const ProjectStatus &p : env2->projects) {
                    if (Derived::liveness(p) == Liveness::quiet) {
                        const auto age = Derived::daysSinceLastCommit(p);
                        quietDays = age.has_value() ? *age : -1;
                    }
                }
            }
            check(log, "快照夹具：天数恒定（相对 now 生成，quiet 档恒为 40 天）",
                quietDays == 40);
        }
        // ⚠ 夹具的时间戳**逐个项目**钉死（不是只看「第一个 quiet 项目」）。
        //   只看一个的话，改了**别的**项目的天数它不红 ⇒ 判据有盲区（负控实测：
        //   把 cygnus 的 40 天改成 41 天，原判据照样绿 —— 而界面上「41 天前提交」
        //   已经变了 ⇒ 基线漂了却没人管）。
        //   规则：**会被算天数的 lastCommitAt 跟真实 now 走**（天数恒定），
        //   **读不出提交时间的项目必须读不出**（不许回落成 0 天）。
        {
            const auto env3 = StatusEnvelope::decodeEnvelopeOrBare(
                QJsonDocument::fromJson(SnapshotFixture::statusJson()));
            static const QHash<QString, int> kExpectedDays = {
                { QStringLiteral("atlas"), 0 },
                { QStringLiteral("borealis"), 0 },
                { QStringLiteral("cygnus"), 40 },
                { QStringLiteral("fennec"), 40 },
            };
            bool ok = env3.has_value();
            int matched = 0;
            if (ok) {
                for (const ProjectStatus &p : env3->projects) {
                    const auto age = Derived::daysSinceLastCommit(p);
                    const auto it = kExpectedDays.constFind(p.name);
                    if (it == kExpectedDays.constEnd()) {
                        // draco-notes / eris / gemini：提交时间**读不出来** ⇒ 不许有天数
                        if (age.has_value())
                            ok = false;
                        continue;
                    }
                    if (!age.has_value() || *age != it.value())
                        ok = false;
                    else
                        ++matched;
                }
                if (matched != kExpectedDays.size())
                    ok = false;
            }
            check(log, "快照夹具：每个项目的「N 天前提交」被钉死（0/0/40/40，其余读不出来）", ok);
        }

        // 里程碑与仪表盘载荷也要能解析（走真实 fromJson）
        check(log, "快照夹具：dashboard 载荷能解析",
            DashboardData::fromJson(
                QJsonDocument::fromJson(SnapshotFixture::dashboardJson()).object()).has_value());
        check(log, "快照夹具：milestone 载荷能解析",
            MilestonesEnvelope::fromJson(
                QJsonDocument::fromJson(SnapshotFixture::milestonesJson()).object()).has_value());

        // ⚠ **基线必须逐字节可重现**（批 T）—— 否则 CI 天天有 diff，
        //   人就学会忽略 diff ⇒ 基线又变成空门（比没门更糟）。
        //   墙钟有两处出口：① 侧栏「上次刷新 HH:mm」② 里程碑「目标 YYYY-MM-DD」。
        //   ① 用固定 epoch（配快照进程固定 TZ=UTC）② 用固定基准日。
        //   这里把两个都钉住 —— 期望值**写死**（不从夹具反推，否则是同义反复）。
        check(log, "快照夹具：刷新时刻固定（不许用墙钟）",
            SnapshotFixture::fixedRefreshedMs() == 1768478400000LL);
        {
            const QJsonObject ms = QJsonDocument::fromJson(SnapshotFixture::milestonesJson()).object();
            const QJsonArray items = ms.value(QStringLiteral("milestones")).toArray();
            const QJsonObject first = items.isEmpty() ? QJsonObject() : items.at(0).toObject();
            check(log, "快照夹具：绝对日期锚定基准日（不随「今天」变）",
                first.value(QStringLiteral("targetDate")).toString() == QStringLiteral("2026-02-14")
                    && first.value(QStringLiteral("createdAt")).toString() == QStringLiteral("2025-12-16"));
        }
        {
            const QJsonObject env = QJsonDocument::fromJson(SnapshotFixture::statusJson()).object();
            const QJsonArray projects = env.value(QStringLiteral("projects")).toArray();
            const QJsonArray branches = projects.isEmpty()
                ? QJsonArray()
                : projects.at(0).toObject().value(QStringLiteral("branches")).toArray();
            const QJsonObject b0 = branches.isEmpty() ? QJsonObject() : branches.at(0).toObject();
            check(log, "快照夹具：分支提交日锚定基准日",
                b0.value(QStringLiteral("headDate")).toString() == QStringLiteral("2026-01-15"));
        }
        // ⚠ 里程碑在 **dashboard 与 milestone list 两处载荷**里各出现一次
        //   —— 它们说的是同一批对象 ⇒ 文本必须逐字相同。
        //   （之前两处各写一份，cygnus 的 targetDate 一边有日期一边空 ⇒ 同一件事两套说法。）
        {
            const QJsonObject dash = QJsonDocument::fromJson(SnapshotFixture::dashboardJson()).object();
            const QJsonObject ms = QJsonDocument::fromJson(SnapshotFixture::milestonesJson()).object();
            const QJsonArray inDash = dash.value(QStringLiteral("milestones")).toObject()
                .value(QStringLiteral("items")).toArray();
            const QJsonArray inList = ms.value(QStringLiteral("milestones")).toArray();
            check(log, "快照夹具：里程碑两处载荷同源（逐字相同）",
                !inDash.isEmpty() && inDash == inList);

            // ⚠ **计数必须与条目对得上**（open+done+dropped+unknown+other = readCount = 条数）。
            //   之前 counts 写 open:2 / readCount:5，而条目只有 4 条、open 只有 1 条
            //   ⇒ 侧栏「里程碑 ●3」与列表里的「2 个未完成」自相矛盾 ⇒ 基线把矛盾固化了。
            const QJsonObject counts = dash.value(QStringLiteral("milestones")).toObject()
                .value(QStringLiteral("counts")).toObject();
            int nOpen = 0, nDone = 0, nDropped = 0, nUnknown = 0, nOther = 0;
            for (const QJsonValue &v : inList) {
                const QString st = v.toObject().value(QStringLiteral("status")).toString();
                if (st == QStringLiteral("open")) ++nOpen;
                else if (st == QStringLiteral("done")) ++nDone;
                else if (st == QStringLiteral("dropped")) ++nDropped;
                else if (st == QStringLiteral("unknown")) ++nUnknown;
                else ++nOther;
            }
            check(log, "快照夹具：里程碑计数与条目自洽（侧栏徽标不许和列表打架）",
                counts.value(QStringLiteral("open")).toInt(-1) == nOpen
                    && counts.value(QStringLiteral("done")).toInt(-1) == nDone
                    && counts.value(QStringLiteral("dropped")).toInt(-1) == nDropped
                    && counts.value(QStringLiteral("unknown")).toInt(-1) == nUnknown
                    && counts.value(QStringLiteral("other")).toInt(-1) == nOther
                    && counts.value(QStringLiteral("readCount")).toInt(-1) == inList.size());
        }
    }

    // ⚠ **Qt 的 arg 重载陷阱**（批 T 实测踩到）：`QStringLiteral("%1 ×%2").arg(QString, int)`
    //   命中的是 **arg(a1, fieldWidth) 重载**（int → qsizetype 是标准转换，比
    //   int → QString 更匹配）⇒ 第二个占位符**原样留在界面上**。
    //   提交构成的图例曾一直显示「feat ×%2」，从来没显示过数量。
    //   这里把「正确写法」与「错误写法」都钉住 —— 免得有人再写回那个形态。
    check(log, "Qt arg 重载：链式单参数才正确（arg(QString,int) 会命中 fieldWidth 重载）",
        QStringLiteral("%1 ×%2").arg(QStringLiteral("feat")).arg(12) == QStringLiteral("feat ×12")
            && QStringLiteral("%1 ×%2").arg(QStringLiteral("feat"), 12) != QStringLiteral("feat ×12"));

    // ── 1. status envelope：成功条目 32 键逐键 ──
    {
        const auto env = StatusEnvelope::decodeEnvelopeOrBare(
            J(QStringLiteral(R"({"projects":[%1,%2],"summary":%3,"language":"zh"})")
                  .arg(statusProjectJson(QStringLiteral("atlas"), false),
                      statusProjectJson(QStringLiteral("gone"), true), statusSummaryJson())));
        check(log, "status envelope 解码", env.has_value());
        if (env) {
            check(log, "status projects 数", env->projects.size() == 2,
                QString::number(env->projects.size()));
            const ProjectStatus &ok = env->projects[0];
            check(log, "成功条目字段抽查", ok.headline == QStringLiteral("2 处未提交")
                    && ok.currentBranch == QStringLiteral("main") && ok.repoBranchCount == 2
                    && ok.dirty.total == 4 && ok.userDirtyCount == 3 && ok.commitCount == 42
                    && ok.branches.size() == 2 && ok.overall.notes.has_value()
                    && ok.mergeHint.has_value() && ok.mergeHint->kind == QStringLiteral("fast-forward")
                    && ok.journalLimit == 8 && ok.lastCommitAt.has_value());
            check(log, "分支 20 键抽查",
                ok.branches[1].aheadOfDefault == 2 && !ok.branches[1].isCurrent
                    && ok.branches[1].staleDays == 13 && ok.branches[1].provider == QStringLiteral("rules"));
            const ProjectStatus &err = env->projects[1];
            check(log, "失败桩同键集解码 + 计数 -1",
                err.isUnreadable() && err.userDirtyCount == -1 && err.commitCount == -1
                    && err.repoBranchCount == -1 && err.headline == QStringLiteral("状态获取失败"));
            check(log, "summary 恒等式 projectCount+failedProjects==listedProjects",
                env->summary.has_value()
                    && env->summary->projectCount + env->summary->failedProjects
                        == env->summary->listedProjects);
            check(log, "language=zh", env->language.value_or(QString()) == QStringLiteral("zh"));
        }

        // 缺一个键 → 整个 envelope 解码失败（CONTRACT §2.1 红线）：
        // 从失败桩 fixture（fetchedAt 行带尾逗号）里删掉 fetchedAt 键
        const auto broken = StatusEnvelope::decodeEnvelopeOrBare(
            J(QStringLiteral(R"({"projects":[%1],"summary":%3,"language":"zh"})")
                  .arg(statusProjectJson(QStringLiteral("gone"), true)
                           .replace("\"fetchedAt\":\"2026-10-03T10:00:00+08:00\",", ""),
                      statusSummaryJson())));
        check(log, "缺键条目被整体拒绝", !broken.has_value());

        // summary 缺 failedProjects → 契约过旧判据（§4.4）
        const auto oldEngine = StatusEnvelope::decodeEnvelopeOrBare(
            J(QStringLiteral(R"({"projects":[],"summary":{"projectCount":0},"language":"zh"})")));
        check(log, "summary 缓键 → summary=nullopt（契约过旧判据）",
            oldEngine.has_value() && !oldEngine->summary.has_value());

        // 旧引擎裸对象兼容
        const auto bare = StatusEnvelope::decodeEnvelopeOrBare(
            J(statusProjectJson(QStringLiteral("legacy"), false)));
        check(log, "旧引擎裸对象兼容", bare.has_value() && bare->projects.size() == 1);
    }

    // ── 2. dashboard ──
    {
        const auto d = DashboardData::fromJson(JO(QStringLiteral(R"({
            "projects":{"total":2,"listed":3,"registered":4,"excludedDisabled":1,"failed":1,"dirty":1,"active7d":1,"active30d":2},
            "work":{"branches":2,"mergeCandidates":1,"untrackedFiles":5,"stashes":1},
            "languages":[{"language":"C++","count":42},{"language":"Rust","count":9}],
            "languagesTruncated":false,"languagesTopCut":false,"languagesFailed":1,
            "languagesFailedReasons":["路径不存在"],
            "milestones":{"counts":{"open":2,"done":1,"dropped":0,"unknown":1,"other":0,"storeHealth":"ok","degraded":false,"readCount":4,"excludedDisabled":0,"orphaned":0},
                          "items":[{"projectId":"p_ok","name":"v1.0","description":"首发","targetDate":"2026-11-01","tag":"","status":"open","createdAt":"2026-10-01","completedAt":"","projectName":"atlas","tagName":"v1.0","tagReached":false,"commitsSince":-1,"commitsSinceReadable":false,"daysToTarget":29,"overdue":false,"gitReadable":false,"unverifiedReason":"仓库不可读"}]},
            "activeProjects":[{"name":"atlas","lastCommitAgo":"2 天前","headline":"2 处未提交"}],
            "fetchedAt":"2026-10-03T10:00:00+08:00"
        })")));
        check(log, "dashboard 解码", d.has_value());
        if (d) {
            check(log, "dashboard 口径抽查（total/listed 两口径并存）",
                d->projects.total == 2 && d->projects.listed == 3 && d->projects.active7d == 1);
            check(log, "dashboard 恒发披露四键",
                !d->languagesTruncated && !d->languagesTopCut && d->languagesFailed == 1
                    && d->languagesFailedReasons.size() == 1);
            check(log, "milestone 17 键无 id 也能解码",
                d->milestones.items.size() == 1 && !d->milestones.items[0].id.has_value()
                    && d->milestones.items[0].commitsSince == -1
                    && d->milestones.items[0].status == QStringLiteral("open"));
            // 对账等式 readCount = open+done+dropped+unknown+excludedDisabled+orphaned
            const MilestoneCounts &c = d->milestones.counts;
            check(log, "readCount 对账等式",
                c.readCount
                    == c.open + c.done + c.dropped + c.unknown + c.excludedDisabled + c.orphaned);
        }
    }

    // ── 3. milestone list envelope ──
    {
        const auto e = MilestonesEnvelope::fromJson(JO(QStringLiteral(R"({
            "milestones":[{"projectId":"p_ok","name":"v1.0","description":"","targetDate":"","tag":"v1.0","status":"done","createdAt":"2026-10-01","completedAt":"2026-10-02","projectName":"atlas","tagName":"v1.0","tagReached":true,"commitsSince":7,"commitsSinceReadable":true,"daysToTarget":-1,"overdue":false,"gitReadable":true,"unverifiedReason":""}],
            "storeHealth":"ok","readCount":1,"orphaned":[{"id":"m_1","projectId":"p_gone","name":"old","description":"","targetDate":"","status":"open","orphaned":true}],
            "excludedDisabled":0
        })")));
        check(log, "milestone list envelope 解码",
            e.has_value() && e->milestones.size() == 1 && e->readCount == 1
                && e->orphaned.size() == 1 && e->orphaned[0].id == QStringLiteral("m_1"));
    }

    // ── 4. update 单/多双形态 + shallow/deep 分派 ──
    {
        // shallow 裸对象（单项目形态）
        const auto shallow = UpdateAllEnvelope::decode(J(QStringLiteral(R"({
            "ok":true,"mode":"shallow","projectId":"p_ok","project":"atlas","provider":"rules","providerLabel":"规则",
            "docs":[{"file":"README.md","changed":true,"created":false,"backup":"/x/.deepgit/backups/README.md.bak"}],
            "journalEntry":{"id":"j9","at":"t","project":"atlas","projectId":"p_ok","branch":"main","mode":"shallow","source":"cli","provider":"rules","providerLabel":"规则","commitCount":1,"commitCountScope":"new","commitCountTruncated":false,"repoBranchCount":2,"branchCountTruncated":false,"summary":"s","highlights":[],"nextSteps":[],"notes":[]},
            "at":"2026-10-03T10:00:00+08:00",
            "branchCount":2,"repoBranchCount":2,"branchCountTruncated":false,"commitCount":42
        })")));
        check(log, "update 单项目裸对象 → shallow",
            shallow.results.size() == 1
                && std::holds_alternative<ShallowUpdateResult>(shallow.results[0]));
        if (std::holds_alternative<ShallowUpdateResult>(shallow.results[0])) {
            const auto &s = std::get<ShallowUpdateResult>(shallow.results[0]);
            check(log, "shallow 四专属键 + backup 恒发",
                s.branchCount == 2 && s.repoBranchCount == 2 && s.commitCount == 42
                    && s.docs.size() == 1
                    && s.docs[0].backup.contains(QStringLiteral("backups")));
        }

        // deep 载荷喂进 shallow 型必须被拒（无 branchCount 四键）
        const auto deepBare = UpdateAllEnvelope::decode(J(QStringLiteral(R"({
            "ok":true,"mode":"deep","projectId":"p","project":"x","provider":"ai","providerLabel":"模型",
            "docs":[],"journalEntry":{"id":"j","at":"t","project":"x","projectId":"p","branch":"b","mode":"deep","source":"cli","provider":"ai","providerLabel":"模型","commitCount":0,"commitCountScope":"repoTotal","commitCountTruncated":false,"repoBranchCount":-1,"branchCountTruncated":false,"summary":"s","highlights":[],"nextSteps":[],"notes":[],"docs":["README.md","AGENTS.md"]},
            "at":"t","highlights":["重写了 README"]
        })")));
        check(log, "deep 裸对象 → DeepUpdateResult（highlights 在、shallow 四键不在）",
            deepBare.results.size() == 1
                && std::holds_alternative<DeepUpdateResult>(deepBare.results[0]));
        if (std::holds_alternative<DeepUpdateResult>(deepBare.results[0])) {
            const auto &dp = std::get<DeepUpdateResult>(deepBare.results[0]);
            check(log, "deep journalEntry 带 docs（浅更新没有这个键的语义保真）",
                dp.journalEntry.has_value() && dp.journalEntry->docs.has_value()
                    && dp.journalEntry->docs->size() == 2);
        }

        // 多项目 envelope：成功项 + 失败项混合
        const auto multi = UpdateAllEnvelope::decode(J(QStringLiteral(R"({
            "results":[{"ok":true,"mode":"shallow","projectId":"p1","project":"a","provider":"rules","providerLabel":"规则","docs":[],"journalEntry":null,"at":"t","branchCount":0,"repoBranchCount":-1,"branchCountTruncated":false,"commitCount":0},
                        {"code":"DOC_WRITE_FAILED","message":"a 更新失败：Permission denied"}],
            "count":2,"failed":1,"succeeded":1
        })")));
        check(log, "多项目 envelope：shallow 成功 + 失败条目",
            multi.results.size() == 2 && multi.failed == 1 && multi.succeeded == 1
                && std::holds_alternative<ShallowUpdateResult>(multi.results[0])
                && std::holds_alternative<UpdateFailureEntry>(multi.results[1]));
    }

    // ── 5. docs / journal / git / scan / list / tools / context ──
    {
        const auto docs = DocsEnvelope::fromJson(JO(QStringLiteral(R"({
            "project":"atlas",
            "docs":[{"file":"README.md","content":"# hi","project":"atlas"}],
            "unreadable":[{"project":"atlas","unreadable":"AGENTS.md,CLAUDE.md"}]
        })")));
        check(log, "docs 单项目 envelope（project 键在）",
            docs.has_value() && docs->project.has_value() && docs->docs.size() == 1
                && docs->unreadable.size() == 1
                && docs->unreadable[0].unreadable == QStringLiteral("AGENTS.md,CLAUDE.md"));

        const auto docsMulti = DocsEnvelope::fromJson(JO(QStringLiteral(R"({
            "docs":[{"file":"README.md","content":"# a","project":"a"},{"file":"README.md","content":"# b","project":"b"}],
            "unreadable":[]
        })")));
        check(log, "docs 多项目平铺（无 project 键）",
            docsMulti.has_value() && !docsMulti->project.has_value()
                && docsMulti->docs.size() == 2);

        const auto journal = JournalEnvelope::fromJson(JO(QStringLiteral(R"({
            "entries":[{"id":"j1","at":"t","project":"a","projectId":"p","branch":"main","mode":"track","source":"cli","provider":"rules","providerLabel":"规则","commitCount":0,"commitCountScope":"new","commitCountTruncated":false,"repoBranchCount":2,"branchCountTruncated":false,"summary":"快照","highlights":[],"nextSteps":[],"notes":[]}],
            "limit":20,"branches":"*","projects":1,"unparsableLines":0,"windowExhausted":false,
            "branchWindowExhausted":{"legacy":"none-in-window"}
        })")));
        check(log, "journal envelope + branchWindowExhausted 对象",
            journal.has_value() && journal->entries.size() == 1 && journal->limit == 20
                && journal->branches == QStringLiteral("*")
                && journal->branchWindowExhausted.value(QStringLiteral("legacy"))
                    == QStringLiteral("none-in-window"));

        const auto git = GitOpResponse::fromJson(JO(
            QStringLiteral(R"({"op":"commit","ok":false,"output":"nothing to commit","project":"a"})")));
        check(log, "git op 响应（ok:false 不是解码失败）",
            git.has_value() && !git->ok && git->op == QStringLiteral("commit"));

        const auto scan = ScanResult::fromJson(JO(QStringLiteral(R"({
            "candidates":[{"name":"a","path":"/x/a","kind":"git","remote":"origin"}],
            "found":3,"added":1,"existing":2,"dirsVisited":40,"truncated":false,"depthCapped":true,
            "unreadable":["/x/locked"],"depth":2
        })")));
        check(log, "scan：found−added==existing + 三披露键",
            scan.has_value() && scan->found - scan->added == scan->existing && scan->depthCapped
                && scan->unreadable.size() == 1);

        const auto list = ProjectEntry::fromJson(JO(QStringLiteral(R"({
            "id":"p_a","name":"a","path":"/x/a","kind":"git","remote":"origin",
            "addedAt":"2026-10-01","tags":[],"disabled":false
        })")));
        check(log, "list/add 条目 8 键（无 created）",
            list.has_value() && !list->disabled && list->kind == QStringLiteral("git"));

        const auto tools = ToolsEnvelope::fromJson(JO(QStringLiteral(R"({
            "tools":[{"name":"get_group_context","description":"读取项目群上下文","params":""},
                     {"name":"git_commit","description":"提交全部改动","params":"name,message"},
                     {"name":"run_shallow_update","description":"浅更新","params":"name"}],
            "note":"params 为逗号分隔参数名"
        })")));
        check(log, "tools：恰 3 键（无 method/path）",
            tools.has_value() && tools->tools.size() == 3
                && tools->tools[1].params == QStringLiteral("name,message"));

        // 旧名别名的机器可读废弃标记（引擎 0.2.0 起）。
        // ⚠ 三态都要钉：① 标了废弃 ⇒ 认得出 + 认得出继任者；
        //   ② **没**标（老引擎）⇒ 缺省**不是**废弃（别把「没有标记」读成「已废弃」）；
        //   ③ 标了废弃但继任者不在面内 ⇒ 收敛不自洽（模型会无路可走）。
        {
            const auto dep = ToolsEnvelope::fromJson(JO(QStringLiteral(R"({
                "tools":[{"name":"index_query","description":"索引查询","params":"name,symbol"},
                         {"name":"codegraph_symbol","description":"符号定位（旧名别名）",
                          "params":"name,symbol","deprecated":true,"replacedBy":"index_query"}]
            })")));
            check(log, "tools：能读出 deprecated / replacedBy（机器可读的废弃标记）",
                dep.has_value() && dep->tools.size() == 2
                    && dep->tools[1].deprecated
                    && dep->tools[1].replacedBy == QStringLiteral("index_query")
                    && !dep->tools[0].deprecated);
            // 收敛口径：非废弃面只剩 1 个（清单 JSON 与工具表同一口径）
            check(log, "tools：废弃别名不进非废弃面（AI 工具面收敛）",
                dep.has_value() && dep->activeTools().size() == 1
                    && dep->activeTools().front().name == QStringLiteral("index_query")
                    && dep->activeJson().value(QStringLiteral("tools")).toArray().size() == 1);
            // 继任者必须就在非废弃面里（否则模型无路可走）
            check(log, "tools：废弃项的继任者必须在非废弃面内（收敛自洽）",
                dep.has_value() && dep->successorsCovered());

            // 缺标记 = 没废弃（老引擎兼容）；继任者缺席 = 不自洽
            const auto old = ToolsEnvelope::fromJson(JO(QStringLiteral(R"({
                "tools":[{"name":"codegraph_symbol","description":"旧引擎的工具","params":"name"}]
            })")));
            check(log, "tools：没标 deprecated 的老引擎工具不算废弃（缺省不是废弃）",
                old.has_value() && !old->tools.front().deprecated
                    && old->activeTools().size() == 1);
            const auto broken = ToolsEnvelope::fromJson(JO(QStringLiteral(R"({
                "tools":[{"name":"codegraph_symbol","description":"别名","params":"name",
                          "deprecated":true,"replacedBy":"index_query"}]
            })")));
            QString missing;
            check(log, "tools：废弃项的继任者缺席 ⇒ 判成收敛不自洽（不静默放过）",
                broken.has_value() && !broken->successorsCovered(&missing)
                    && !missing.isEmpty());
        }

        ContextEnvelope::Note note = ContextEnvelope::Note::ok;
        const auto ctx = ContextEnvelope::decode(
            QStringLiteral(R"({"scope":"group","budget":9000,"context":"# 上下文"})").toUtf8(),
            &note);
        check(log, "context 解码 ok", ctx.has_value() && note == ContextEnvelope::Note::ok
                && ctx->scope == QStringLiteral("group") && ctx->budget == 9000);
        ContextEnvelope::decode(QStringLiteral("not json").toUtf8(), &note);
        check(log, "context 非 JSON → notJson 文案",
            note == ContextEnvelope::Note::notJson
                && !ContextEnvelope::noteText(note).isEmpty());
        ContextEnvelope::decode(
            QStringLiteral(R"({"scope":"group","budget":1})").toUtf8(), &note);
        check(log, "context 缺键 → missingKeys", note == ContextEnvelope::Note::missingKeys);
        ContextEnvelope::decode(
            QStringLiteral(R"({"scope":"project","budget":1,"context":""})").toUtf8(), &note);
        check(log, "context 空串 → emptyContext（「没解出来」≠「没有」）",
            note == ContextEnvelope::Note::emptyContext);
    }

    // ── 6. milestone add / action / remove ──
    {
        const auto add = MilestoneAddResult::fromJson(JO(QStringLiteral(R"({
            "project":"atlas",
            "milestone":{"id":"m_1","projectId":"p_ok","name":"v1.0","description":"首发","targetDate":"2026-11-01","tag":"","status":"open","createdAt":"t","completedAt":"","projectName":"atlas","tagName":"v1.0","tagReached":false,"commitsSince":0,"commitsSinceReadable":true,"daysToTarget":29,"overdue":false,"gitReadable":true,"unverifiedReason":""},
            "created":true
        })")));
        check(log, "milestone add：milestone 含 id + created",
            add.has_value() && add->created && add->milestone.id.value_or(QString())
                    == QStringLiteral("m_1"));

        const auto action = MilestoneActionResult::fromJson(JO(QStringLiteral(R"({
            "project":"atlas","milestone":"v1.0","requested":"reopen","status":"done","applied":false
        })")));
        check(log, "milestone action：applied:false 被压回的语义可读",
            action.has_value() && !action->applied && action->requested == QStringLiteral("reopen")
                && action->status == QStringLiteral("done"));

        const auto rm = MilestoneRemoveResult::fromJson(
            JO(QStringLiteral(R"({"project":"atlas","milestone":"v1.0","removed":true})")));
        check(log, "milestone remove", rm.has_value() && rm->removed);
    }

    // ── 7. EngineFailure 四种形状（CONTRACT §4.1）──
    {
        check(log, "形状① {code,message}",
            EngineFailure::reason(J(QStringLiteral(R"({"code":"DOC_WRITE_FAILED","message":"README.md：Permission denied"})")),
                      QStringLiteral("fallback"))
                .contains(QStringLiteral("DOC_WRITE_FAILED：README.md：Permission denied")));
        check(log, "形状② {error:true,code,message}",
            EngineFailure::reason(J(QStringLiteral(R"({"error":true,"code":"MILESTONE_NOT_FOUND","message":"没有这个里程碑"})")),
                      QStringLiteral("fallback"))
                .contains(QStringLiteral("MILESTONE_NOT_FOUND：没有这个里程碑")));
        const auto batch = EngineFailure::reason(
            J(QStringLiteral(R"({"results":[{"ok":true},{"code":"X","message":"失败一"},{"code":"Y","message":"失败二"}],"count":3,"failed":2,"succeeded":1})")),
            QStringLiteral("退出码 1"));
        check(log, "形状③ 批量：hasErrorOrCode 同规则（ok 键不算失败）+ 汇总",
            batch.contains(QStringLiteral("2 个项目更新失败"))
                && batch.contains(QStringLiteral("失败一")));
        const auto status = EngineFailure::reason(
            J(QStringLiteral(R"({"projects":[{"error":"路径不存在或卷未挂载：/x"},{"name":"ok"}],"summary":{"failedProjects":1,"listedProjects":2}})")),
            QStringLiteral("退出码 1"));
        check(log, "形状④ status 采集失败摘要",
            status.contains(QStringLiteral("1 个项目采集失败"))
                && status.contains(QStringLiteral("路径不存在或卷未挂载")));
        check(log, "形状⑤ dashboard 只有个数",
            EngineFailure::reason(J(QStringLiteral(R"({"projects":{"failed":2}})")),
                                      QStringLiteral("退出码 1"))
                .contains(QStringLiteral("只给了个数")));
        check(log, "批量逐条原因 + 条数",
            EngineFailure::batchReasons(J(QStringLiteral(R"({"results":[{"code":"X","message":"a"},{"code":"Y","message":"b"},{"ok":true}]})")))
                    .size()
                == 2
            && EngineFailure::batchFailedCount(
                   J(QStringLiteral(R"({"results":[{"code":"X","message":"a"}]})")))
                == 1);
        // hasErrorOrCode：ok:false 只是「没写文档」，不算失败
        check(log, "hasErrorOrCode：ok 键在 → 永远不算失败",
            !EngineFailure::isFailure(J(QStringLiteral(R"({"ok":false,"project":"a"})")).object())
                && EngineFailure::isFailure(
                    J(QStringLiteral(R"({"error":"x"})")).object()));
    }

    // ── 8. EngineError 五类文案 ──
    {
        check(log, "notFound 文案含安装引导",
            EngineError::makeNotFound().userMessage().contains(QStringLiteral("install.sh"))
                && EngineError::makeNotFound().userMessage().contains(QStringLiteral("DEEPGIT_BIN")));
        check(log, "timeout 与 cancelled 文案分开",
            EngineError::makeTimeout(30).userMessage().contains(QStringLiteral("超时"))
                && EngineError::makeCancelled(QStringLiteral("update"))
                        .userMessage()
                        .contains(QStringLiteral("已停止")));
        EngineError p = EngineError::makeFailedWithPayload(QStringLiteral("引擎退出码 1"),
            J(QStringLiteral(R"({"code":"E","message":"真因"})")));
        check(log, "failedWithPayload.userMessage 读载荷",
            p.userMessage().contains(QStringLiteral("E：真因")));
    }

    // ── 9. Route / Router / ShortcutMap ──
    {
        const LaunchRoute r = Route::parseArgs({ QStringLiteral("deepDolphin"),
            QStringLiteral("--project"), QStringLiteral("atlas"),
            QStringLiteral("--section"), QStringLiteral("board"),
            QStringLiteral("--open-settings") });
        check(log, "深链：--project 与 --section 同现以 project 为准",
            r.project == QStringLiteral("atlas") && r.section.isEmpty() && r.openSettings);

        const LaunchRoute missing = Route::parseArgs(
            { QStringLiteral("deepDolphin"), QStringLiteral("--project") });
        check(log, "flag 缺值 = 没给", missing.project.isEmpty());

        const LaunchRoute flagAsValue = Route::parseArgs(
            { QStringLiteral("deepDolphin"), QStringLiteral("--project"),
                QStringLiteral("--open-panel") });
        check(log, "flag 值以 -- 开头 = 没给", flagAsValue.project.isEmpty());

        const LaunchRoute selftest = Route::parseArgs(
            { QStringLiteral("deepDolphin"), QStringLiteral("--agent-selftest") });
        check(log, "agent-selftest 缺省问句",
            selftest.agentSelftest
                && selftest.selftestQuestion == Route::defaultSelfTestQuestion());

        check(log, "resolveSection 认不出落 dashboard",
            Route::resolveSection(QStringLiteral("nope")) == QStringLiteral("dashboard")
                && Route::resolveSection(QStringLiteral("milestones"))
                    == QStringLiteral("milestones"));

        // desktop Action「扫描项目」（M2-2）：--scan 是独立开关，不被别的开关吃掉
        const LaunchRoute scan = Route::parseArgs(
            { QStringLiteral("deepDolphin"), QStringLiteral("--scan") });
        check(log, "--scan → openScan", scan.openScan && !scan.agentSelftest);

        // MimeType=inode/directory 的位置参数：目录 → path；带值的 flag 其后值不算路径；
        // 普通文件名不算（本应用只吃目录）
        const LaunchRoute withDir = Route::parseArgs(
            { QStringLiteral("deepDolphin"), QStringLiteral("--project"), QStringLiteral("atlas"),
                QStringLiteral("/tmp") });
        check(log, "%f 位置参数取目录、--project 的值不算",
            withDir.project == QStringLiteral("atlas")
                && withDir.path.value_or(QString()) == QStringLiteral("/tmp"));

        const LaunchRoute fileArg = Route::parseArgs(
            { QStringLiteral("deepDolphin"), QStringLiteral("/etc/hostname") });
        check(log, "非目录裸参数 → 不吃", !fileArg.path.has_value());

        // Router：missing → 改道 dashboard + notice；未加载 → pending
        const LaunchRoute rp = Route::parseArgs(
            { QStringLiteral("deepDolphin"), QStringLiteral("--project"), QStringLiteral("ghost") });
        RouteTarget pending = routeTarget(rp, {}, false);
        check(log, "Router 未加载 → pending", pending.verdict == RouteVerdict::pending);
        RouteTarget missingProj = routeTarget(rp, {}, true);
        check(log, "Router 项目不存在 → missing + notice",
            missingProj.verdict == RouteVerdict::missing
                && missingProj.section == QStringLiteral("dashboard")
                && missingProj.notice.contains(QStringLiteral("ghost")));
        const LaunchRoute rs = Route::parseArgs(
            { QStringLiteral("deepDolphin"), QStringLiteral("--section"), QStringLiteral("board") });
        check(log, "Router --section 直落",
            routeTarget(rs, {}, false).verdict == RouteVerdict::apply
                && routeTarget(rs, {}, false).section == QStringLiteral("board"));

        check(log, "ShortcutMap 无重复键位",
            !ShortcutMap::hasDuplicate(ShortcutMap::shortcutMap(3)));
        check(log, "ShortcutMap 含 Ctrl+4（不在 viewOrder 但占键位）",
            ShortcutMap::find(ShortcutMap::shortcutMap(3), QStringLiteral("view:currentProject"))
                    != nullptr
                && ShortcutMap::shortcutMap(3).size() == 11);
    }

    // ── 10. Thresholds（M3-7）：阈值收口 + 两根消费边界 ──
    {
        // 审计口径（2026-10-04 grep 实证）：未提交通知满 10 处才报、按十位分桶去重
        // （消费方 AppModel::postNotificationsIfNeeded）；时间桶线 7/30。
        check(log, "Thresholds 审计口径：未提交 10/分桶 10 + active7d/30d 天线 7/30",
            Thresholds::dirtyNotifyMinCount == 10 && Thresholds::dirtyBucketWidth == 10
                && Thresholds::activeDays7 == 7 && Thresholds::activeDays30 == 30);

        // recent/quiet 分界吃 activeDays30（Derived::liveness）：
        // 干净项目（无未提交/分支/合入提示）恰 30 天 → recent（≤ 含端点），31 天 → quiet
        ProjectStatus slow;
        slow.storeHealth = QStringLiteral("ok");
        slow.kind = QStringLiteral("git");
        slow.name = QStringLiteral("slow");
        slow.userDirtyCount = 0;
        slow.untrackedCount = 0;
        slow.stashCount = 0;
        slow.lastCommitAt = QDateTime::currentDateTime().addDays(-30).toString(Qt::ISODate);
        const bool at30 = Derived::liveness(slow) == Liveness::recent;
        slow.lastCommitAt = QDateTime::currentDateTime().addDays(-31).toString(Qt::ISODate);
        const bool at31 = Derived::liveness(slow) == Liveness::quiet;
        check(log, "activeDays30 边界：恰 30 天=recent / 31 天=quiet", at30 && at31);

        // 仪表盘时间窗吃 activeDays7/30（DashFilter::keeps）：
        // 近 7 天窗——恰 7 天保留、8 天滤出、读不出来恒保留（不知道 ≠ 不在范围内）
        DashFilter w7;
        w7.window = TimeWindow::days7;
        slow.lastCommitAt = QDateTime::currentDateTime().addDays(-7).toString(Qt::ISODate);
        const bool keep7 = w7.keeps(slow);
        slow.lastCommitAt = QDateTime::currentDateTime().addDays(-8).toString(Qt::ISODate);
        const bool drop8 = !w7.keeps(slow);
        slow.lastCommitAt = QString();
        const bool keepUnknown = w7.keeps(slow);
        check(log, "近 7 天窗（activeDays7）：7 天保留 / 8 天滤出 / 读不出来恒保留",
            keep7 && drop8 && keepUnknown);
    }

    // ── 11. SegmentedButton 样式（M3b）：两档 sheet 不再有未填占位符（plan §4.3 / 坑 #3）──
    {
        // 纯字符串层：--selfcheck 跑在 QGuiApplication 构造前（main.cpp 无头分支），
        // 不实例化控件、不调 DS 取色（DGuiApplicationHelper 无 app 即段错误，
        // 2026-10-04 探针实证）——颜色喂固定值，锁的是「占位符就地填满 + 两档各带
        // 自己档的颜色」这条契约；DS::semColor(accent)/surfaceAlt()/textPrimary()
        // 的接线由 SegmentedButton::restyle() 在 GUI 侧完成（人工审计位）。
        const QColor accent(QStringLiteral("#0081ff"));
        const QColor bg(QStringLiteral("#252525"));
        const QColor fg(QStringLiteral("#ffffff"));
        const QString on = SegmentedButton::sheet(true, accent, bg, fg);
        const QString off = SegmentedButton::sheet(false, accent, bg, fg);
        check(log, "SegmentedButton sheet：两档占位符全填满（坑 #3 不复活）",
            !on.contains(QStringLiteral("%1")) && !on.contains(QStringLiteral("%2"))
                && !off.contains(QStringLiteral("%1")) && !off.contains(QStringLiteral("%2")));
        check(log, "SegmentedButton sheet：选中=accent 底白字 / 未选中=bg 底 fg 字且两档互异",
            on.contains(accent.name()) && on.contains(QStringLiteral("color: white"))
                && off.contains(bg.name()) && off.contains(fg.name()) && on != off);
    }

    // ── 12. EmptyState iconTone（M3b 组件二）：「空」与「读不出来」图标分档锁死 ──
    {
        // 纯字符串层（QGuiApplication 构造前可跑，不实例化控件）：tone→**逻辑图标名**契约——
        // 空态=info / 读不出来=warning，两档必须互异（plan §3b
        // 「"空"与"读不出来"在图标上区分」）。⚠ 批 U 起返回的是**逻辑名**而不是主题名
        //   （真正取图标走 `platform::icon()`，候选链在 `logic/IconNames`）——
        //   主题缺名时才有路可走，且缺失会被告警而不是静默空图。
        //   逻辑名必须在清单里（否则取不到 → 空图标 ⇒ 空门）。
        check(log, "EmptyState iconTone：空=info / 读不出来=warning 且互异且都在图标清单里",
            EmptyState::toneIcon(EmptyState::Tone::Empty) == IconNames::Id::info
                && EmptyState::toneIcon(EmptyState::Tone::Warning) == IconNames::Id::warning
                && IconNames::name(IconNames::Id::info) == QStringLiteral("info")
                && IconNames::name(IconNames::Id::warning) == QStringLiteral("warning"));
    }

    // ── 12b. 图标候选链（批 U · M1-2）─────────────────────────────
    {
        // 判定层纯数据（QGuiApplication 构造前可跑）：候选链是「多几条路」，
        // 每条链**至少两个候选** —— 只写一个名字的链在缺那个名字的主题上就是空图标，
        // 而「哪个图标没解析到」是说不出来的（空门）。
        const QList<IconNames::Id> ids = IconNames::all();
        bool allChainsOk = !ids.isEmpty();
        bool allDistinct = true;
        bool allNamed = true;
        bool allListed = true;
        for (const IconNames::Id id : ids) {
            const QStringList chain = IconNames::fallbacks(id);
            if (chain.size() < 2)
                allChainsOk = false;
            if (QSet<QString>(chain.begin(), chain.end()).size() != chain.size())
                allDistinct = false; // 同一条链里出现重复候选 = 白写一遍
            if (IconNames::name(id).isEmpty())
                allNamed = false;
            // 清单与枚举必须**严格一一对应**：枚举多一项而表里没登记 ⇒ 上面已红；
            // 表里多一项而清单没列 ⇒ 这里红（漏列 = 那个图标永远不会被枚举到）。
            if (chain.isEmpty())
                allListed = false;
        }
        check(log, "图标候选链：清单非空且每条链至少两个候选（缺名时才有路可走）", allChainsOk);
        check(log, "图标候选链：同一条链里不重复", allDistinct);
        check(log, "图标候选链：每个逻辑图标都有名字（探针按名字报告）", allNamed);
        check(log, "图标候选链：枚举项全部登记了候选链（漏登记 = 取不到图标）", allListed);
        // 未知逻辑名必须**认出来**（而不是静默给个空图标）。
        check(log, "图标候选链：未知逻辑名不被当成已知（会报缺失）",
            !IconNames::isKnown(QStringLiteral("__不存在的逻辑名__")));
    }

    // ── 12c. 平台后端判定（批 V · M1-7）─────────────────────────────
    // 判定层纯函数（QGuiApplication 构造前可跑）：后端分档 / 激活动作计划 /
    // 任务栏边距 / 托盘弹窗落点。
    // ⚠ 平台层（`platform/Backend`）那层要碰 QWidget/QScreen，判据落不到
    //   ⇒ 由探针（backendKind）+ 接线门守；这里锁的是**结论**。
    {
        // ── 后端分档：token 边界是重点 ──
        // ⚠ 朴素前缀比较会把 "mywayland" / "xwayland" 也判成 Wayland ⇒
        //   走错激活动作分支（Wayland 分支不调 raise、只发 requestActivate）。
        check(log, "平台后端：X11 认得 xcb（含 xcb- 变体）",
            Backend::classify(QStringLiteral("xcb")) == Backend::Kind::X11
                && Backend::classify(QStringLiteral("xcb-glx")) == Backend::Kind::X11);
        check(log, "平台后端：Wayland 认得 wayland（含 wayland- 变体）",
            Backend::classify(QStringLiteral("wayland")) == Backend::Kind::Wayland
                && Backend::classify(QStringLiteral("wayland-egl")) == Backend::Kind::Wayland);
        check(log, "平台后端：分档带 token 边界（名字后面不是连字符就不算命中）",
            Backend::classify(QStringLiteral("mywayland")) == Backend::Kind::Other
                && Backend::classify(QStringLiteral("xwayland")) == Backend::Kind::Other
                && Backend::classify(QStringLiteral("myxcb")) == Backend::Kind::Other
                // ⚠ 这两个是**分叉夹具**：朴素前缀比较会把它们误判成 Wayland / X11。
                //   只测 mywayland 这类**朴素比较也判对**的名字 ⇒ 判据与错误实现
                //   不分叉 ⇒ 去掉边界照样绿（负控实测，第十八次同类问题）。
                && Backend::classify(QStringLiteral("waylandland")) == Backend::Kind::Other
                && Backend::classify(QStringLiteral("xcbfoo")) == Backend::Kind::Other);
        check(log, "平台后端：认不出的后端归 Other（不是硬套 X11）",
            Backend::classify(QStringLiteral("offscreen")) == Backend::Kind::Other
                && Backend::classify(QStringLiteral("minimal")) == Backend::Kind::Other
                && Backend::classify(QString()) == Backend::Kind::Other);
        check(log, "平台后端：分档名与枚举一一对应（探针按名字报告）",
            Backend::kindName(Backend::Kind::X11) == QStringLiteral("x11")
                && Backend::kindName(Backend::Kind::Wayland) == QStringLiteral("wayland")
                && Backend::kindName(Backend::Kind::Other) == QStringLiteral("other"));

        // ── 激活动作计划：三条分支必须真的不同 ──
        const Backend::Activation planX11 = Backend::activationFor(Backend::Kind::X11);
        const Backend::Activation planWl = Backend::activationFor(Backend::Kind::Wayland);
        const Backend::Activation planOther = Backend::activationFor(Backend::Kind::Other);
        // ⚠ 最小化恢复**三条分支都要**：`show()` 不会恢复最小化窗口（实测）⇒
        //   不恢复 = 面板被最小化后从托盘叫醒「点了跟没点一样」。
        check(log, "窗口激活：三种后端都要先恢复最小化态（show() 拉不回最小化窗口）",
            planX11.restoreIfMinimized && planWl.restoreIfMinimized
                && planOther.restoreIfMinimized);
        check(log, "窗口激活：Wayland 走 requestActivate（activateWindow 在 Wayland 不可靠）",
            !planX11.requestActivate && planWl.requestActivate);
        check(log, "窗口激活：Wayland 不调 raise（合成器管叠放次序，raise 是空操作）",
            planX11.raiseWindow && !planWl.raiseWindow);

        // ── 托盘几何可用性 ──
        check(log, "托盘几何：宽高为 0 或负即不可用（Wayland 常给无效矩形）",
            !Backend::trayGeometryUsable(QRect())
                && !Backend::trayGeometryUsable(QRect(0, 0, 0, 0))
                && !Backend::trayGeometryUsable(QRect(0, 0, -1, 20))
                && Backend::trayGeometryUsable(QRect(1880, 5, 20, 20)));

        // ── 任务栏几何 ──
        const Backend::Insets ins = Backend::reservedInsets(QRect(0, 0, 1920, 1080),
                                                            QRect(0, 30, 1920, 970));
        check(log, "任务栏几何：整屏与可用区的差就是被占掉的边（顶栏 30 + 任务栏 80）",
            ins.left == 0 && ins.top == 30 && ins.right == 0 && ins.bottom == 80);
        const Backend::Insets noPanel = Backend::reservedInsets(QRect(0, 0, 1920, 1080),
                                                               QRect(0, 0, 1920, 1080));
        check(log, "任务栏几何：没有面板时四边边距全为 0", noPanel.isEmpty());

        // ── 托盘弹窗落点 ──
        // ⚠ **参数从托盘域 token 取**（不在这儿另抄一份数）：判据要锁的是**算法**
        //   （落点不越界、托盘几何不可用时落屏幕右上），不是某个具体数值；
        //   数值另抄一份 = 两个出处 = 改一处忘另一处。
        const Backend::PopupGeometry geo = TrayGeometry::popupGeometry();
        const QRect avail(0, 30, 1920, 970); // 顶栏 30 + 任务栏 80

        // ⚠ **右边缘溢出**（本批修的真缺陷）：托盘在屏幕右上角时，弹窗右边缘 =
        //   图标右边缘 + dockGap ⇒ 旧实现会跑出屏幕右边。
        // ⚠ 断言里带**边距**（不只「不越界」）：只断言不越界 ⇒ 去掉「留边距那一夹」
        //   而留着「硬夹紧兜底」时照样绿（负控实测，第十八次同类问题）。
        const Backend::PopupPlacement corner = Backend::placePopup(
            QRect(1898, 5, 20, 20), QSize(380, 300), avail, geo);
        check(log, "托盘弹窗：托盘在屏幕右上角时右边缘不溢出可用区",
            corner.usedTrayGeometry && corner.rect.right() <= avail.right() - geo.edgeMargin);
        // 弹窗与可用区**等高** ⇒ 上下两条边都得在可用区内。
        //   ⚠ 夹紧顺序是 下 → 左 → 上：上边那一夹把弹窗推下去后，底边就出去了
        //   ⇒ 还得再硬夹一次。只夹一边会漏（负控实测）。
        const Backend::PopupPlacement flush = Backend::placePopup(
            QRect(1898, 5, 20, 20), QSize(380, 970), avail, geo);
        check(log, "托盘弹窗：弹窗与可用区等高时上下都还在可用区内",
            flush.rect.top() >= avail.top() && flush.rect.bottom() <= avail.bottom());
        // ⚠ **顶部溢出**：弹窗比可用区高时，顶部不能跑出屏幕（旧实现标题栏被切掉）。
        const Backend::PopupPlacement tall = Backend::placePopup(
            QRect(10, 5, 20, 20), QSize(380, 2000), avail, geo);
        check(log, "托盘弹窗：弹窗比可用区高时顶部不溢出可用区",
            tall.rect.top() >= avail.top());
        // 通用不变量：放得下就整个落在可用区内。
        const Backend::PopupPlacement normal = Backend::placePopup(
            QRect(1000, 200, 20, 20), QSize(380, 300), avail, geo);
        check(log, "托盘弹窗：落点四边都在可用区内",
            normal.rect.left() >= avail.left() && normal.rect.right() <= avail.right()
                && normal.rect.top() >= avail.top() && normal.rect.bottom() <= avail.bottom());
        // 托盘在屏幕**最左边** ⇒ 弹窗左边缘要被推回可用区内。
        // ⚠ 这条单独钉：左边那一夹在上面的用例里**根本没被触发**（图标在中间），
        //   没触发的分支等于没测（改了也不会红）。
        const Backend::PopupPlacement leftEdge = Backend::placePopup(
            QRect(0, 200, 20, 20), QSize(380, 300), avail, geo);
        check(log, "托盘弹窗：托盘在屏幕最左边时左边缘不溢出可用区",
            leftEdge.rect.left() >= avail.left() && leftEdge.clamped);
        // 托盘几何不可用 ⇒ 落屏幕右上（PLAN §8 T4），并**明说**没用托盘几何。
        const Backend::PopupPlacement fallback = Backend::placePopup(
            QRect(), QSize(380, 300), avail, geo);
        check(log, "托盘弹窗：托盘几何不可用时落屏幕右上（并标记没用托盘几何）",
            !fallback.usedTrayGeometry && fallback.rect.right() == avail.right() + geo.fallbackDx
                && fallback.rect.top() == avail.top() + geo.fallbackDy);
        // 夹紧是**可见事实**：越界时标记为真，不越界时为假。
        check(log, "托盘弹窗：越界时标记被夹紧（夹紧不是静默修正）",
            corner.clamped && !normal.clamped);

        // ── 面板感知落点（批 W · M1-8）───────────────────────────
        // ⚠ 这条是本批的**主修复**：DDE 上 `QSystemTrayIcon` 没有宿主
        //   （DDE 托盘画的是应用自绘的 X11 窗口，批 Y 查明）⇒ 托盘坐标**恒拿不到**
        //   ⇒ 旧实现只能瞎猜「屏幕右上」，而托盘在**底部**任务栏里（DDE 默认）
        //   ⇒ 弹窗落在离托盘图标很远的地方。
        {
            PanelGeometry::Panel bottomPanel;
            bottomPanel.valid = true;
            bottomPanel.rect = QRect(0, 1039, 1920, 41); // 本机实测值
            bottomPanel.edge = PanelGeometry::Edge::Bottom;
            const QRect availBottom(0, 0, 1920, 1039);   // 扣掉面板后的可用区

            const Backend::PopupPlacement byPanel = Backend::placePopup(
                QRect(), QSize(380, 300), availBottom, geo, bottomPanel);
            // ⚠ 期望值与无头探针实测**逐字一致**（trayPopupTarget=1524,731,380,300）
            //   —— 判据与运行期事实对得上，不是各算各的。
            check(log, "托盘弹窗：面板在下时弹窗落在面板上方、右对齐（不再飞到屏幕右上）",
                byPanel.usedPanelGeometry && !byPanel.usedTrayGeometry
                    && byPanel.rect.left() == 1524 && byPanel.rect.top() == 731);

            PanelGeometry::Panel topPanel;
            topPanel.valid = true;
            topPanel.rect = QRect(0, 0, 1920, 41);
            topPanel.edge = PanelGeometry::Edge::Top;
            const QRect availTop(0, 41, 1920, 1039);
            const Backend::PopupPlacement byTopPanel = Backend::placePopup(
                QRect(), QSize(380, 300), availTop, geo, topPanel);
            check(log, "托盘弹窗：面板在上时弹窗落在面板下方、右对齐",
                byTopPanel.usedPanelGeometry && byTopPanel.rect.left() == 1524
                    && byTopPanel.rect.top() == 48);
            // 没有面板 ⇒ 旧行为一字不改（屏幕右上）
            const Backend::PopupPlacement noPanel = Backend::placePopup(
                QRect(), QSize(380, 300), availBottom, geo, PanelGeometry::Panel());
            check(log, "托盘弹窗：读不到面板时退回屏幕右上（旧行为不变）",
                !noPanel.usedPanelGeometry && noPanel.rect.top() == 32);
        }
    }

    // ── 12d. DDE 面板几何（批 W · M1-8）─────────────────────────────
    // 判定层纯函数（QGuiApplication 构造前可跑）：面板在哪条边、扣掉面板后
    // 可用区还剩哪块。面板几何来自 D-Bus（平台层），这里锁的是**算法**。
    {
        // 位置枚举（dde-shell 的 Position：0=上 1=右 2=下 3=左）
        check(log, "面板几何：位置枚举对上（0上 1右 2下 3左，别的算不知道）",
            PanelGeometry::edgeFromPosition(0) == PanelGeometry::Edge::Top
                && PanelGeometry::edgeFromPosition(1) == PanelGeometry::Edge::Right
                && PanelGeometry::edgeFromPosition(2) == PanelGeometry::Edge::Bottom
                && PanelGeometry::edgeFromPosition(3) == PanelGeometry::Edge::Left
                && PanelGeometry::edgeFromPosition(99) == PanelGeometry::Edge::Unknown);
        check(log, "面板几何：边的名字能报出来（探针按名字报告）",
            PanelGeometry::edgeName(PanelGeometry::Edge::Bottom) == QStringLiteral("bottom")
                && PanelGeometry::edgeName(PanelGeometry::Edge::Unknown)
                    == QStringLiteral("unknown"));

        const QRect screen(0, 0, 1920, 1080);
        PanelGeometry::Panel bottom;
        bottom.valid = true;
        bottom.rect = QRect(0, 1039, 1920, 41);
        bottom.edge = PanelGeometry::Edge::Bottom;
        // ⚠ 本机实测：面板 (0,1039,1920,41) 扣完应是 (0,0,1920,1039) ——
        //   与 QPA 的 availableGeometry **逐字一致**（两套独立来源对上了）。
        check(log, "面板几何：扣掉底部面板后的可用区（与 QPA 的 availableGeometry 一致）",
            PanelGeometry::usableArea(screen, bottom) == QRect(0, 0, 1920, 1039));

        PanelGeometry::Panel top;
        top.valid = true;
        top.rect = QRect(0, 0, 1920, 41);
        top.edge = PanelGeometry::Edge::Top;
        check(log, "面板几何：扣掉顶部面板后可用区往下移",
            PanelGeometry::usableArea(screen, top) == QRect(0, 41, 1920, 1039));

        PanelGeometry::Panel left;
        left.valid = true;
        left.rect = QRect(0, 0, 41, 1080);
        left.edge = PanelGeometry::Edge::Left;
        check(log, "面板几何：扣掉左侧面板后可用区往右移",
            PanelGeometry::usableArea(screen, left) == QRect(41, 0, 1879, 1080));

        PanelGeometry::Panel right;
        right.valid = true;
        right.rect = QRect(1879, 0, 41, 1080);
        right.edge = PanelGeometry::Edge::Right;
        check(log, "面板几何：扣掉右侧面板后可用区往左移",
            PanelGeometry::usableArea(screen, right) == QRect(0, 0, 1879, 1080));

        // 面板缺席 ⇒ 一点都不能扣（否则可用区凭空少一块）
        check(log, "面板几何：没有面板时可用区原样返回",
            PanelGeometry::usableArea(screen, PanelGeometry::Panel()) == screen);
        // ⚠ **面板悬空**（不贴屏幕边）⇒ 可用区按面板的**上沿**算，不是「减厚度」。
        //   面板 (0,1000,1920,41) 悬在 1080 屏里：正确的是 (0,0,1920,999)；
        //   「减厚度」会算成 (0,0,1920,1039) —— 两种实现在「面板贴边」时**完全一样**，
        //   只测贴边的面板 = 判据与错误实现不分叉（负控实测，第十九次同类问题）。
        PanelGeometry::Panel floating;
        floating.valid = true;
        floating.rect = QRect(0, 1000, 1920, 41);
        floating.edge = PanelGeometry::Edge::Bottom;
        check(log, "面板几何：面板悬空时可用区按面板上沿算（不是减厚度）",
            PanelGeometry::usableArea(screen, floating) == QRect(0, 0, 1920, 1000));
        // 面板把整块屏占满 ⇒ 扣完是空矩形 ⇒ 退回整屏（空矩形会让落点全乱）
        PanelGeometry::Panel huge;
        huge.valid = true;
        huge.rect = screen;
        huge.edge = PanelGeometry::Edge::Bottom;
        check(log, "面板几何：面板占满整屏时退回整屏（不给出空可用区）",
            PanelGeometry::usableArea(screen, huge) == screen);

        // ⚠ **位置读不出来时按几何猜边**：通高的左侧面板同时贴着上/下/左三条边，
        //   按固定顺序挑会挑到「上」⇒ 把可用区从**底**上扣（错得离谱）。
        //   正确答案是「左」（接触长度 = 屏高 > 面板宽）。
        PanelGeometry::Panel sideUnknown;
        sideUnknown.valid = true;
        sideUnknown.rect = QRect(0, 0, 60, 1080); // 通高、贴左
        sideUnknown.edge = PanelGeometry::Edge::Unknown;
        check(log, "面板几何：位置未知时按接触长度猜边（通高左面板判「左」不是「上」）",
            PanelGeometry::usableArea(screen, sideUnknown) == QRect(60, 0, 1860, 1080));
        // ⚠ **通栏顶部面板**（edge 未知）：它同时贴着上/左/右三条边。
        //   按「最后一条命中的边」猜会判成「右」；按「接触长度最大」才判「上」
        //   （接触长度 = 屏宽 > 面板高）。⇒ 上一条与这一条**合起来**才把
        //   「先命中」「后命中」两种错实现都堵住（负控实测，第十九次同类问题）。
        PanelGeometry::Panel topUnknown;
        topUnknown.valid = true;
        topUnknown.rect = QRect(0, 0, 1920, 41); // 通栏、贴上
        topUnknown.edge = PanelGeometry::Edge::Unknown;
        check(log, "面板几何：位置未知时通栏顶部面板判「上」（不是最后命中的那条边）",
            PanelGeometry::usableArea(screen, topUnknown) == QRect(0, 41, 1920, 1039));

        // Wayland 下 QPA 的 availableGeometry **不扣**面板 ⇒ 用面板真几何修正
        const QRect qpaNoPanel(0, 0, 1920, 1080);
        check(log, "面板几何：QPA 没扣面板时用面板真几何补上（Wayland 场景）",
            PanelGeometry::effectiveAvailable(qpaNoPanel, screen, bottom)
                == QRect(0, 0, 1920, 1039));
        // X11 下 QPA 已经扣了 ⇒ 取交不变（不能越扣越多）
        const QRect qpaWithPanel(0, 0, 1920, 1039);
        check(log, "面板几何：QPA 已扣过面板时不重复扣（X11 场景）",
            PanelGeometry::effectiveAvailable(qpaWithPanel, screen, bottom)
                == QRect(0, 0, 1920, 1039));
        // 面板在别的屏上（多屏 + 面板只在主屏）⇒ 不动这块屏
        const QRect otherScreen(1920, 0, 1920, 1080);
        check(log, "面板几何：面板不在这块屏上时不动它",
            PanelGeometry::effectiveAvailable(QRect(1920, 0, 1920, 1080), otherScreen, bottom)
                == QRect(1920, 0, 1920, 1080));
    }

    // ── 13. FlatButton 契约（M3b 组件三）：padding 一档与双态叠加（纯函数层）──
    {
        // 锁两条纯函数契约（QGuiApplication 构造前可跑，DS::Spacing 是 constexpr）：
        // ① 带文字按钮 padding = xs×lg = 4×16，与 DS::buttonPaddingQss 同源（M3-5
        //   「按钮 padding 收成一档」，两种取值途径必须永不漂移）；
        // ② hover/pressed 叠加色半透明、互异且 pressed 更重（paintEvent/Card 范式，
        //   颜色实时取 DS::textPrimary——此处只锁透明度关系，DS 接线是 GUI 侧人工审计位）。
        check(log, "FlatButton padding：一档 4×16（xs×lg，与 buttonPaddingQss 同源）",
            FlatButton::padding()
                == QMargins(DS::Spacing::lg, DS::Spacing::xs, DS::Spacing::lg, DS::Spacing::xs));
        const QColor base(QStringLiteral("#1a1a1a"));
        const QColor hover = FlatButton::overlayColor(base, FlatButton::Tone::Hover);
        const QColor pressed = FlatButton::overlayColor(base, FlatButton::Tone::Pressed);
        check(log, "FlatButton 双态叠加：半透明互异且 pressed 更重（同 base 纯透明度差）",
            hover.alpha() > 0 && hover.alpha() < 255 && pressed.alpha() > hover.alpha()
                && hover.rgb() == pressed.rgb());
    }

    // ── 14. 文档完整性（引擎 verify 四态）：判定层纯函数契约 ──
    {
        // 契约键：checked/failures/undetermined/missing/verified/documents 必发，note 可选。
        const auto vOk = VerifyEnvelope::fromJson(JO(QStringLiteral(R"({
            "checked":1,"failures":0,"undetermined":0,"missing":0,"verified":true,
            "documents":[{"project":"atlas","doc":"README.md","ok":true,"note":"仅文末分隔空行差异"}]
        })")));
        check(log, "verify envelope：六键齐全才解出（documents 恒发）",
            vOk.has_value() && vOk->checked == 1 && vOk->verified && vOk->documents.size() == 1
                && vOk->documents[0].doc == QStringLiteral("README.md"));

        // 缺键 = 契约可能过旧 → nullopt，**不许回落成全 0**（那会把「读不出来」显示成「通过」）。
        const auto vMissingKey = VerifyEnvelope::fromJson(JO(QStringLiteral(R"({
            "checked":1,"verified":true,"documents":[]
        })")));
        check(log, "verify 缺键 → 解不出（不许回落成 0 计数）",
            !vMissingKey.has_value());

        // 四态优先级：missing > failed > undetermined > none > verified。
        VerifyEnvelope e;
        e.checked = 1;
        e.verified = true;
        check(log, "verify 四态：一致 → verified",
            DocumentIntegrity::stateOf(e) == DocumentIntegrity::State::verified);

        VerifyEnvelope miss;
        miss.checked = 1;
        miss.missing = 1;
        miss.verified = false;
        check(log, "verify 四态：缺失优先于不一致（missing > failed > undetermined）",
            DocumentIntegrity::stateOf(miss) == DocumentIntegrity::State::missing);

        VerifyEnvelope fail;
        fail.checked = 1;
        fail.failures = 1;
        fail.undetermined = 1;
        check(log, "verify 四态：不一致优先于无法判定",
            DocumentIntegrity::stateOf(fail) == DocumentIntegrity::State::failed);

        VerifyEnvelope und;
        und.checked = 1;
        und.undetermined = 1;
        und.verified = false;
        check(log, "verify 四态：无法判定是独立一档（≠ 通过）",
            DocumentIntegrity::stateOf(und) == DocumentIntegrity::State::undetermined);

        // 引擎没说通过、也没给任何计数 → 无从判定，不许当通过。
        VerifyEnvelope silent;
        silent.checked = 0;
        silent.verified = false;
        check(log, "verify 四态：引擎没说通过 → 无从判定（不落 verified）",
            DocumentIntegrity::stateOf(silent) == DocumentIntegrity::State::none);

        // 文案纪律：verified 不许带「无法判定」；undetermined 必须说清「不等于通过」。
        const QString okHead
            = DocumentIntegrity::headline(DocumentIntegrity::State::verified, e);
        check(log, "verify 文案：通过档不出现「无法判定」字样",
            okHead.contains(QStringLiteral("通过")) && !okHead.contains(QStringLiteral("无法判定")));

        const QString undHead
            = DocumentIntegrity::headline(DocumentIntegrity::State::undetermined, und);
        check(log, "verify 文案：无法判定档明说「不等于通过」",
            undHead.contains(QStringLiteral("无法判定")) && undHead.contains(QStringLiteral("不等于通过")));

        // 引擎的 note 原样转述 —— 缺失档的 note 带备份路径，那正是用户要的下一步。
        VerifyEnvelope missWithNote;
        missWithNote.checked = 0;
        missWithNote.missing = 1;
        missWithNote.note = QStringLiteral("没有可校验的文档：1 份文档缺失（备份仍在，可从备份恢复）");
        const QString d = DocumentIntegrity::detail(missWithNote);
        check(log, "verify 副说明：引擎 note 原样转述（不吞备份路径）",
            d.contains(QStringLiteral("备份仍在")) && d.contains(QStringLiteral("缺失 1 份")));

        const VerifyDocument doc { QStringLiteral("atlas"), QStringLiteral("README.md"), false,
            QStringLiteral("文档已被删除，但备份仍在 /tmp/x/backups/README.md") };
        const QString line = DocumentIntegrity::documentLine(doc);
        check(log, "verify 文档行：文件名 + 引擎 note（不一致档不装没事）",
            line.contains(QStringLiteral("README.md")) && line.contains(QStringLiteral("不一致"))
                && line.contains(QStringLiteral("backups/README.md")));
    }

    // ── 图谱/架构图 + 符号索引热力图 + 补丁体检：见 SelfCheckGraph.cpp（批 AK 拆分）──
    SelfCheckInternal::checkGraph(log);

    // ── 固定文档页 / 四语言 / 语法高亮：见 SelfCheckDocs.cpp（批 AJ 拆分）──
    SelfCheckInternal::checkDocs(log);

    // ── 图谱三件套 / 引擎获取 / 通知 / 引擎钩子：见 SelfCheckEngine.cpp（批 AJ 拆分）──
    SelfCheckInternal::checkEngine(log);

    // ── 12e. SNI 托盘（批 X · M1-3）────────────────────────────────
    // DDE 的托盘**只认 SNI**（⚠ 批 Y 更正：`_NET_SYSTEM_TRAY_S0` 选区**是存在的**，
    //   但它只托管**应用自绘的 X11 窗口**、不画 SNI 图标 ⇒ 对 SNI 项来说等于没有宿主
    //   ⇒ `QSystemTrayIcon` 在 DDE 上**一个像素都不显示**）。
    // 这一段锁的是判定层（纯函数）：host 分档、注册方式、必填属性、像素编码。
    {
        // ① 没有 watcher ⇒ 只能判「没有」，**不能猜是哪一变体**
        //    （把「读不到」误当成「形状不同」会把接口用错）。
        TraySni::HostCaps none;
        check(log, "SNI：没有 watcher 时判成「没有」（不猜是哪一变体）",
            TraySni::classifyHost(none) == TraySni::Host::None);

        // ② ayatana 变体（本机 DDE 实测：单参数注册 + 已注册项是属性 + ProtocolVersion 0）
        TraySni::HostCaps ayatana;
        ayatana.watcherPresent = true;
        ayatana.singleArgRegister = true;
        ayatana.itemsAsProperty = true;
        ayatana.protocolVersion = 0;
        check(log, "SNI：ayatana 变体识别得出（单参数 + 属性 + ProtocolVersion 0）",
            TraySni::classifyHost(ayatana) == TraySni::Host::Ayatana);

        // ③ KDE 变体（双参数注册）
        TraySni::HostCaps kde = ayatana;
        kde.singleArgRegister = false;
        kde.protocolVersion = 1;
        check(log, "SNI：KDE 变体识别得出（双参数注册）",
            TraySni::classifyHost(kde) == TraySni::Host::Kde);

        // ④ 形状对不上时**不硬套** ayatana（宁可判成「另一种已知形状」也别猜错接口）
        TraySni::HostCaps other = ayatana;
        other.protocolVersion = 7;
        check(log, "SNI：形状对不上时不硬套 ayatana",
            TraySni::classifyHost(other) == TraySni::Host::Kde);

        // ⑤ 注册方式：传**服务名**（项 id 里能一眼认出是自己）
        TraySni::ItemSpec spec;
        spec.serviceName = QStringLiteral("org.deepin.deepDolphin");
        spec.objectPath = QStringLiteral("/StatusNotifierItem");
        check(log, "SNI：注册方式取服务名（项 id 里能认出是自己）",
            TraySni::registrationFor(TraySni::Host::Ayatana) == TraySni::Registration::ServiceName
                && TraySni::registrationArgument(TraySni::Registration::ServiceName, spec)
                       == QStringLiteral("org.deepin.deepDolphin")
                && TraySni::registrationArgument(TraySni::Registration::ObjectPath, spec)
                       == QStringLiteral("/StatusNotifierItem"));

        // ⑥ 必填属性是**入场券**（缺一个当场被注销，实测）
        const QStringList req = TraySni::requiredProperties();
        check(log, "SNI：必填属性是三个 pixmap（缺一个当场被注销）",
            req.size() == 3 && req.contains(QStringLiteral("IconPixmap"))
                && req.contains(QStringLiteral("AttentionIconPixmap"))
                && req.contains(QStringLiteral("OverlayIconPixmap")));

        // ⑦ 诊断要**点名**缺哪个（不只说「不完整」）
        const QStringList missing = TraySni::missingRequired(
            {QStringLiteral("IconPixmap"), QStringLiteral("OverlayIconPixmap")});
        check(log, "SNI：缺哪个能点名（不说「不完整」）",
            missing.size() == 1 && missing.first() == QStringLiteral("AttentionIconPixmap"));

        // ⑧ ⚠ **必填表必须被「宿主会读的属性表」完全覆盖** ——
        //   两张表若各写一份，改了必填表忘了改读表 ⇒ 宿主读到一个我们没暴露的属性
        //   ⇒ 当场被注销（真缺陷）。现在读表直接复用必填表，这条断言是它的护栏。
        const QStringList read = TraySni::hostReadProperties();
        bool covered = true;
        for (const QString &name : req) {
            if (!read.contains(name))
                covered = false;
        }
        check(log, "SNI：宿主会读的属性表覆盖全部必填属性（改一张表不会漏另一张）", covered);

        // ⑨ 主图标属性名与必填表**同源**（平台层不另写一份属性名 ⇒ 不会走偏）
        check(log, "SNI：主图标属性名取自必填表（平台层不另写一份）",
            req.contains(TraySni::primaryPixmapProperty())
                && TraySni::primaryPixmapProperty() == req.value(0));

        // ⑩ 属性都齐了就不该报缺（诊断不能误报）
        check(log, "SNI：必填属性都齐时不报缺（诊断不误报）",
            TraySni::missingRequired(req).isEmpty());

        // ⑪ ★ 像素编码：ARGB32、**网络字节序**（A,R,G,B 依次，每像素 4 字节）
        //   ⚠ 夹具用**非对称**颜色（四个通道互不相等）⇒ 字节序写反必红；
        //   只用「等值颜色」的话，BGRA/RGBA/ARGB 三种错法会互相顶替（历次教训）。
        //   ⚠⚡ **两种源格式都要测**：真实输入是 `QIcon::pixmap().toImage()`
        //   ⇒ **预乘**（Format_ARGB32_Premultiplied）；只测非预乘的话，
        //   「按非预乘去读预乘数据」这种错法**分叉不出来**（实测：整张图编成全 0
        //   的透明图 ⇒ 宿主拿到空图 ⇒ 托盘里不画它，而判据还全绿）。
        {
            QImage nonPremul(2, 1, QImage::Format_ARGB32);
            nonPremul.setPixel(0, 0, qRgba(0x22, 0x33, 0x44, 0x11));
            nonPremul.setPixel(1, 0, qRgba(0x66, 0x77, 0x88, 0x55));
            // 预乘夹具**必须用 QPainter 造**：`QImage::setPixel` 往预乘图里写的是
            // **未预乘的数值**（Qt 直接存，不做预乘）⇒ 拿它当「预乘输入」会造出
            // 一张语义错乱的图。QPainter 画出来的才是**真预乘**（= 真实输入形态）。
            QImage premul(2, 1, QImage::Format_ARGB32_Premultiplied);
            premul.fill(Qt::transparent);
            {
                QPainter p(&premul);
                p.setPen(Qt::NoPen);
                p.setBrush(QColor(0x22, 0x33, 0x44));
                p.drawRect(0, 0, 1, 1);
                p.setBrush(QColor(0x66, 0x77, 0x88));
                p.drawRect(1, 0, 1, 1);
            }
            const QByteArray expect = QByteArray::fromHex("1122334455667788");
            const QByteArray expectOpaque = QByteArray::fromHex("ff223344ff667788");
            check(log, "SNI：像素编码是 ARGB32 网络字节序（源图非预乘）",
                TraySni::encodeArgb32NetworkOrder(nonPremul) == expect);
            check(log, "SNI：像素编码是 ARGB32 网络字节序（源图**预乘**，真实输入形态）",
                TraySni::encodeArgb32NetworkOrder(premul) == expectOpaque);
            // 半透明源图：反预乘有**舍入** ⇒ 按容差比（±2/通道），不按精确字节。
            // ⚠ 期望的通道顺序是 **A,R,G,B**（网络字节序），不是 R,G,B,A。
            QImage half(1, 1, QImage::Format_ARGB32_Premultiplied);
            half.fill(Qt::transparent);
            {
                QPainter p(&half);
                p.setPen(Qt::NoPen);
                p.setBrush(QColor(0x20, 0x40, 0x60, 0x80));
                p.drawRect(0, 0, 1, 1);
            }
            const QByteArray halfBytes = TraySni::encodeArgb32NetworkOrder(half);
            bool halfOk = halfBytes.size() == 4;
            if (halfOk) {
                const int want[4] = {0x80, 0x20, 0x40, 0x60}; // A,R,G,B
                for (int i = 0; i < 4; ++i) {
                    const int got = static_cast<quint8>(halfBytes.at(i));
                    if (qAbs(got - want[i]) > 2)
                        halfOk = false;
                }
            }
            check(log, "SNI：半透明源图反预乘后能还原原色（容差 2/通道）", halfOk);
            const QByteArray bytes = TraySni::encodeArgb32NetworkOrder(nonPremul);
            check(log, "SNI：像素字节数 = 宽×高×4（不补行对齐）",
                bytes.size() == 2 * 1 * 4);
            const QList<TraySni::Pixmap> pms = TraySni::encodePixmap(nonPremul);
            check(log, "SNI：pixmap 元素带对宽高与字节",
                pms.size() == 1 && pms.first().width == 2 && pms.first().height == 1
                    && pms.first().bytes == expect);
        }

        // ⑫ ★★ 像素数组必须能**原样穿过 Qt 真实的 D-Bus 序列化路径**。
        //   ⚠⚠ **这里测的是「Qt 怎么把一个 QVariant 写上线」**，不是我们自己手写的那段：
        //   曾经的错法是给 `QList<Pixmap>` 注册 marshall operators ⇒ Qt 走
        //   「demarshal → marshal」转换，撞上**写模式**的 QDBusArgument
        //   （Qt 会打印 “read from a write-only object”）⇒ 像素被编成**全 0**。
        //   实测后果：总线上的 IconPixmap 是 32×32 但**每字节都是 0**（透明图）
        //   ⇒ 宿主拿到空图 ⇒ 托盘里不画它。**而我们的内部值完全正确** ⇒ 极难查。
        //   ⇒ 判据必须走**同一条路**（QVariant → QDBusMetaType::marshall），
        //     否则这个错法在自检里分叉不出来（判据与错误实现不分叉 = 白测）。
        {
            // ⑫ ★ D-Bus 签名必须**显式声明**：结构体签名推不出来
            //   ⇒ 不声明的话宿主会按 `av` 解，拿到一堆 variant 而不是像素数组
            //   ⇒ 表现为「读到了 IconPixmap，但没有像素」。
            //   ⚠⚠ **这里测不了「字节有没有被编坏」**：`QDBusArgument` 写完就是
            //   **只写**的（「read from a write-only object」）⇒ 同一份数据读不回来。
            //   ⇒ 字节级的端到端判据只能放**真机探针**（外部进程读总线），
            //     放这里只会得到一个「永远红/永远绿」的假判据。
            platform::registerTraySniDBusTypes();
            const QByteArray pixSig =
                QDBusMetaType::typeToSignature(QMetaType::fromType<TraySni::Pixmap>());
            const QByteArray listSig =
                QDBusMetaType::typeToSignature(QMetaType::fromType<QList<TraySni::Pixmap>>());
            check(log, "SNI：pixmap 的 D-Bus 签名是 (iiay) / 数组是 a(iiay)（宿主按这个解）",
                pixSig == QByteArrayLiteral("(iiay)")
                    && listSig == QByteArrayLiteral("a(iiay)"));
        }
    }

    // ── 12f. deepin 托盘**窗口协议**（批 Y · M1-3 的正解）──────────────
    // 这一段锁的是判定层（纯函数、零 X11）：报文格式、选区名、后端选择。
    {
        // ① ⚠⚠ **字段偏移比经典 XEmbed 差一位** —— 放错位置 ⇒ daemon 静默忽略
        //   （实测：按经典布局发 ⇒ daemon 读到的 opcode 是我们的窗口 id ≠ 0
        //   ⇒ 图标永远不出现、且**没有任何报错**）。
        check(log, "deepin 托盘：opcode 放在 l[1]、窗口 id 放在 l[2]（比经典 XEmbed 偏移一位）",
            TraySni::dockFieldIndex(TraySni::DockField::Opcode) == 1
                && TraySni::dockFieldIndex(TraySni::DockField::WindowId) == 2);

        // ② 选区名是 **S0** 变体（无后缀的那个本机没有持有者 ⇒ 发过去 daemon 收不到）
        check(log, "deepin 托盘：选区是 _NET_SYSTEM_TRAY_S0（无后缀那个没有持有者）",
            QByteArray(TraySni::dockSelectionName()) == QByteArrayLiteral("_NET_SYSTEM_TRAY_S0"));

        // ③ 操作码 = 0（REQUEST_DOCK）
        check(log, "deepin 托盘：dock 操作码是 0（REQUEST_DOCK）",
            TraySni::dockOpcodeRequestDock() == 0);

        // ④ 请求组装：opcode 与窗口 id 各就各位
        const TraySni::DockRequest req = TraySni::buildDockRequest(0x6e00001);
        check(log, "deepin 托盘：dock 请求带对了操作码与窗口 id",
            req.opcode == TraySni::dockOpcodeRequestDock() && req.windowId == 0x6e00001);

        // ⑤ ⚠⚠ **后端选择：deepin 选区在场时必须走窗口协议**，
        //   即使 SNI watcher 也在（DDE 25 上 watcher 在，但它**不画** SNI 图标
        //   ⇒ 按「有 watcher 就走 SNI」选 ⇒ 图标永远不出现；批 X 踩的就是这个坑）。
        check(log, "deepin 托盘：选区在场时走窗口协议（哪怕 SNI watcher 也在）",
            TraySni::chooseBackend(true, true) == TraySni::Backend::DeepinWindow);

        // ⑥ 没有 deepin 选区、但有 watcher ⇒ 走 SNI（KDE 系桌面）
        check(log, "deepin 托盘：没有选区但有 watcher 时走 SNI",
            TraySni::chooseBackend(false, true) == TraySni::Backend::Sni);

        // ⑦ 两样都没有 ⇒ 没有后端（不假装成功）
        check(log, "deepin 托盘：既无选区也无 watcher 时判成「没有后端」",
            TraySni::chooseBackend(false, false) == TraySni::Backend::None);

        // ⑧ 后端名字可读（探针/日志用）
        check(log, "deepin 托盘：后端名字分别是 deepin-window / sni / none",
            TraySni::backendName(TraySni::Backend::DeepinWindow) == QStringLiteral("deepin-window")
                && TraySni::backendName(TraySni::Backend::Sni) == QStringLiteral("sni")
                && TraySni::backendName(TraySni::Backend::None) == QStringLiteral("none"));
    }

    // ── 12g. 托盘后端的**强制指定**（测试钩子；批 Y 实测逼出来的）──────
    // ⚠ 背景：DDE 25 上自动选的是 **deepin 窗口协议** ⇒ SNI 那条路走不到
    //   ⇒ 批 X 的「IconPixmap 字节级」端到端判据在 DDE 上永远假红
    //   ⇒ 需要一个显式强制的口子，才能在本机上仍然验 SNI 路径。
    {
        // ① 认得的值
        check(log, "托盘后端强制开关：sni / deepin / none 认得出",
            TraySni::parseBackendOverride(QStringLiteral("sni"))
                == TraySni::BackendOverride(TraySni::Backend::Sni)
                && TraySni::parseBackendOverride(QStringLiteral("deepin"))
                    == TraySni::BackendOverride(TraySni::Backend::DeepinWindow)
                && TraySni::parseBackendOverride(QStringLiteral("none"))
                    == TraySni::BackendOverride(TraySni::Backend::None));

        // ② 没指定 ⇒ 不强制（= 按平台能力自动选）
        check(log, "托盘后端强制开关：空串判成「没指定」",
            !TraySni::parseBackendOverride(QString()).has_value());

        // ③ "auto" 也是「没指定」
        check(log, "托盘后端强制开关：auto 判成「没指定」",
            !TraySni::parseBackendOverride(QStringLiteral("auto")).has_value());

        // ④ ⚠ **认不出 ⇒ 当作没指定**（不静默改道）：
        //   把「打错字」变成「换了一条路」会让判据在**没测到想测的东西**时变绿。
        check(log, "托盘后端强制开关：认不出的字样判成「没指定」（不静默改道）",
            !TraySni::parseBackendOverride(QStringLiteral("瞎写的")).has_value());

        // ⑤ ⚠ 强制**优先于**自动选择：否则探针在本机上想验的那条路根本走不到
        check(log, "托盘后端强制开关：强制 SNI 压过「选区在场 ⇒ 窗口协议」",
            TraySni::chooseBackend(true, true,
                TraySni::BackendOverride(TraySni::Backend::Sni)) == TraySni::Backend::Sni);

        // ⑥ 强制也压过「两样都没有 ⇒ 没有后端」
        check(log, "托盘后端强制开关：强制 deepin 压过「没有后端」",
            TraySni::chooseBackend(false, false,
                TraySni::BackendOverride(TraySni::Backend::DeepinWindow))
                == TraySni::Backend::DeepinWindow);
    }

    log << QStringLiteral("──── selfcheck: %1 passed, %2 failed ────").arg(g_pass).arg(g_fail);
    return g_fail;
}
