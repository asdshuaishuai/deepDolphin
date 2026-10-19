#include "SelfCheck.h"
#include "EngineCli.h"
#include <QCryptographicHash>
#include <QDir>
#include <QSet>
#include "../logic/AgentToolPlan.h"
#include "../logic/ArchReceipt.h"
#include "../logic/CanvasFont.h"
#include "../logic/CodeGraphBuild.h"
#include "../logic/DashFilter.h"
#include "../logic/Derived.h"
#include "../logic/EngineDownload.h"
#include "../logic/Liveness.h"
#include "../logic/SemColors.h"
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
#include <QMargins>
#include <QRegularExpression>
#include <QPainter>

namespace {
int g_pass = 0;
int g_fail = 0;

void check(QStringList &log, const QString &name, bool ok, const QString &detail = {})
{
    if (ok) {
        ++g_pass;
        log << QStringLiteral("PASS  %1").arg(name);
    } else {
        ++g_fail;
        log << QStringLiteral("FAIL  %1%2").arg(name, detail.isEmpty() ? QString() : QStringLiteral(" —— ") + detail);
    }
}

QJsonDocument J(const QString &json)
{
    return QJsonDocument::fromJson(json.toUtf8());
}

// 头文件型模型（Milestone/DocsEnvelope/JournalEnvelope/ScanResult…）的
// fromJson 收 QJsonObject；fixture 以对象形式提供。
QJsonObject JO(const QString &json)
{
    return J(json).object();
}

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
        // 纯字符串层（QGuiApplication 构造前可跑，不实例化控件）：tone→图标名契约——
        // 空态=dialog-information / 读不出来=dialog-warning，两档必须互异（plan §3b
        // 「"空"与"读不出来"在图标上区分」）。DS 取色不在其中（取色无 app 即段错误）。
        check(log, "EmptyState iconTone：空=dialog-information / 读不出来=dialog-warning 且互异",
            EmptyState::toneIconName(EmptyState::Tone::Empty)
                    == QStringLiteral("dialog-information")
                && EmptyState::toneIconName(EmptyState::Tone::Warning)
                    == QStringLiteral("dialog-warning"));
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

    // ── 15. 图谱/架构图：场景契约 + token 解析 + 渲染指令 + Canvas2D 像素（章程 §3.5）──
    {
        const QString kSceneJson = QStringLiteral(R"JSON({
            "v":1,"gen":"moongit-graph",
            "meta":{"title":"架构图","truncated":false,
                    "warnings":{"violations":0,"cycleEdges":0,"violationPairs":[],"cycleModules":[]},
                    "chips":[{"layer":0,"count":1,"label":"基础层 1"}]},
            "themes":{
              "dark":{"text":"#e8eef8","muted":"#94a3b8","bg0":"#0b1220","border":"#1e293b",
                      "cols":["#38bdf8","#a78bfa"],"fills":["rgba(10,20,30,0.5)"],"langs":{"swift":"#f05138"}},
              "light":{"text":"#0f172a","muted":"#64748b","bg0":"#f8fafc","border":"#e2e8f0",
                      "cols":["#38bdf8"],"fills":[],"langs":{}}},
            "views":{
              "module:b":{"label":"B","nodeTheme":{"b":"cols.0"},"shapes":[],"particles":[],"hits":[],"edgesDropped":0,
                           "bounds":{"x0":-4,"y0":-34,"x1":324,"y1":162}},
              "arch":{"label":"架构","nodeTheme":{"a":"cols.1"},
                      "shapes":[
                        {"t":"frame","x":10,"y":20,"w":300,"h":120,"color":"cols.0","label":"L4 其他"},
                        {"t":"rrect","x":30,"y":40,"w":120,"h":60,"r":11,"fill":"panel","stroke":"node:a","sw":1.2},
                        {"t":"rect","x":34,"y":49,"w":3.2,"h":42,"fill":"node:a"},
                        {"t":"text","x":42,"y":62,"text":"cli","size":13,"weight":600,"color":"text","align":"left"},
                        {"t":"edge","p":[10,20,30,30,40,40,50,50],"c0":"node:a","c1":"node:b","sw":3.5,"alpha":0.9,"arrow":9,"delay":0},
                        {"t":"edge","p":[10,20,30,30,40,40,50,50],"c0":"node:a","c1":"node:b","delay":999999},
                        {"t":"weird","x":1}
                      ],
                      "particles":[{"p":[0,0,1,1,2,2,3,3],"n":3,"sp":0.001,"color":"accent"}],
                      "hits":[{"id":"a","x":30,"y":40,"w":120,"h":60,"drill":"module:a"}],
                      "edgesDropped":3,
                      "bounds":{"x0":-24,"y0":-54,"x1":512,"y1":228}}},
            "panels":{"arch:a":{"title":"a","sub":"s","stats":"t"}}
        })JSON");
        const auto scene = GraphScene::fromJson(JO(kSceneJson));
        check(log, "scene 契约：v=1 解出；arch 恒排第一（引擎导出顺序）",
            scene.has_value() && scene->views.size() == 2 && scene->views.at(0).id == QLatin1String("arch")
                && scene->views.at(1).id == QLatin1String("module:b"));

        // 契约版本不认识 → 明说不兼容，不静默兼容。
        QJsonObject badV = JO(kSceneJson);
        badV.insert(QStringLiteral("v"), 2);
        check(log, "scene 契约：v≠1 → 解不出（不静默兼容）",
            !GraphScene::fromJson(badV).has_value());

        // 必发键缺 → 契约过旧。
        QJsonObject noViews = JO(kSceneJson);
        noViews.remove(QStringLiteral("views"));
        check(log, "scene 契约：缺 views → 解不出（不许回落成空图）",
            !GraphScene::fromJson(noViews).has_value());

        // 恒发字段：edgesDropped=3（不是「没有丢弃」）；warnings 恒发；chips[].count 是数字。
        check(log, "scene 恒发字段：edgesDropped / meta.warnings / chips[].count 都读得出",
            scene.has_value() && scene->views.at(0).edgesDropped == 3
                && scene->warnings.violations == 0 && scene->warnings.cycleEdges == 0
                && scene->chips.size() == 1 && scene->chips.at(0).count == 1
                && scene->chips.at(0).label == QStringLiteral("基础层 1"));

        // 恒发字段**在不在**：值是 0/空时，「确实没有」与「契约没发」不可区分
        // → 必须另有标志把两者分开（缺字段不回落成 0 的同一条纪律）。
        check(log, "scene 恒发字段：present 标志区分「确实 0」与「契约没发」",
            scene.has_value() && scene->views.at(0).edgesDroppedPresent
                && scene->warningsPresent && scene->chipsPresent
                && scene->views.at(0).boundsPresent && scene->viewsMissingBounds == 0
                && scene->views.at(0).bx0 == -24 && scene->views.at(0).by1 == 228);

        // 缺键的场合：值全回落成 0/空，但 present 标志必须说「没有」
        {
            QJsonObject noBounds = JO(kSceneJson);
            QJsonObject views = noBounds.value(QStringLiteral("views")).toObject();
            QJsonObject arch = views.value(QStringLiteral("arch")).toObject();
            arch.remove(QStringLiteral("bounds"));
            views.insert(QStringLiteral("arch"), arch);
            noBounds.insert(QStringLiteral("views"), views);
            const auto s2 = GraphScene::fromJson(noBounds);
            check(log, "scene 缺 bounds → 不回落成 0（标志说没有，计入待披露）",
                s2.has_value() && !s2->views.at(0).boundsPresent
                    && s2->viewsMissingBounds == 1);

            QJsonObject noDropped = JO(kSceneJson);
            QJsonObject v2 = noDropped.value(QStringLiteral("views")).toObject();
            QJsonObject a2 = v2.value(QStringLiteral("arch")).toObject();
            a2.remove(QStringLiteral("edgesDropped"));
            v2.insert(QStringLiteral("arch"), a2);
            noDropped.insert(QStringLiteral("views"), v2);
            const auto s3 = GraphScene::fromJson(noDropped);
            check(log, "scene 缺 edgesDropped → 不当成「没丢边」（标志说没有）",
                s3.has_value() && !s3->views.at(0).edgesDroppedPresent
                    && s3->views.at(0).edgesDropped == 0);

            QJsonObject noMeta = JO(kSceneJson);
            QJsonObject meta = noMeta.value(QStringLiteral("meta")).toObject();
            meta.remove(QStringLiteral("warnings"));
            meta.remove(QStringLiteral("chips"));
            noMeta.insert(QStringLiteral("meta"), meta);
            const auto s4 = GraphScene::fromJson(noMeta);
            check(log, "scene 缺 warnings/chips → 不当成「没有违规/没有分层」",
                s4.has_value() && !s4->warningsPresent && !s4->chipsPresent
                    && s4->warnings.violations == 0 && s4->chips.isEmpty());
        }

        if (!scene.has_value()) {
            log << QStringLiteral("FAIL  scene 后续判据（场景没解出，后续用例无法跑）");
            ++g_fail;
        } else {
            const GraphView &v = scene->views.at(0);
            const GraphThemeTokens &th = scene->dark;

            // ── token 四形态 + 二跳 ──
            check(log, "token 直取：text/muted/bg0 走 themes 直取",
                GraphToken::resolve(th, QStringLiteral("text"), &v).value
                        == QStringLiteral("#e8eef8")
                    && GraphToken::resolve(th, QStringLiteral("muted"), &v).value
                        == QStringLiteral("#94a3b8"));
            check(log, "token 下标：cols.N / fills.N 走数组",
                GraphToken::resolve(th, QStringLiteral("cols.1"), &v).value
                        == QStringLiteral("#a78bfa")
                    && GraphToken::resolve(th, QStringLiteral("fills.0"), &v).value
                        == QStringLiteral("rgba(10,20,30,0.5)"));
            check(log, "token 字典：langs.<lang> 走 langs",
                GraphToken::resolve(th, QStringLiteral("langs.swift"), &v).value
                    == QStringLiteral("#f05138"));
            // 二跳：node:a → view.nodeTheme[a] = cols.1 → #a78bfa
            check(log, "token 二跳：node:<id> → 视图 nodeTheme → 基础 token",
                GraphToken::resolve(th, QStringLiteral("node:a"), &v).value
                    == QStringLiteral("#a78bfa"));
            // 查不到节点 → 回落 text（不是洋红：图上没有这个节点 ≠ 引擎违约）
            check(log, "token 二跳落空 → 回落 text（不是洋红）",
                GraphToken::resolve(th, QStringLiteral("node:zzz"), &v).value
                        == QStringLiteral("#e8eef8")
                    && !GraphToken::resolve(th, QStringLiteral("node:zzz"), &v).violation);
            // 未知 token → 洋红 + violation 标记（引擎违约的显式信号）
            const GraphToken::Resolved bad = GraphToken::resolve(th, QStringLiteral("nope"), &v);
            check(log, "token 未知 → 洋红兜底 + violation 标记（不静默当黑）",
                bad.violation && GraphToken::toColor(bad.value) == QColor(255, 0, 204));
            // 下标越界 → 也是未知 token → 洋红
            check(log, "token 下标越界 → 洋红兜底（不回落成第 0 项）",
                GraphToken::resolve(th, QStringLiteral("cols.99"), &v).violation);
            // 语言色查不到 → 回落 text
            check(log, "token 语言色查不到 → 回落 text（不是洋红）",
                !GraphToken::resolve(th, QStringLiteral("langs.rust"), &v).violation);

            // 颜色解析：#hex / #hex8 / #rgb / rgba()
            check(log, "颜色解析：#hex / #hexAA / #RGB / rgba() 四形态",
                GraphToken::toColor(QStringLiteral("#ff0000")).name() == QStringLiteral("#ff0000")
                    && GraphToken::toColor(QStringLiteral("#00ff0080")).alpha() == 128
                    && GraphToken::toColor(QStringLiteral("#abc")).name() == QStringLiteral("#aabbcc")
                    && GraphToken::toColor(QStringLiteral("rgba(10,20,30,0.5)")).alpha() > 100);

            // ── 渲染指令序列（记录式接收端）──
            RecordingSink sink;
            const SceneRender::Stats st = SceneRender::render(
                *scene, v, true, ArchViewport::Viewport { 1.0, 0.0, 0.0 }, 800, 600, 1000.0, sink);
            check(log, "渲染：背景先铺满画布（fillRect 用 bg0）",
                sink.ops.size() >= 2 && sink.ops.at(0).contains(QStringLiteral("#0b1220"))
                    && sink.ops.at(1) == QStringLiteral("fillRect(0,0,800,600)"));
            check(log, "渲染：frame → strokeRect + 层框标题",
                sink.ops.contains(QStringLiteral("strokeRect(10,20,300,120)"))
                    && sink.texts.contains(QStringLiteral("L4 其他")));
            check(log, "渲染：rrect → 圆角路径（arcTo×4）+ fill + stroke",
                sink.arcToCount >= 4);
            check(log, "渲染：text → fillText 且字体/对齐按契约",
                sink.texts.contains(QStringLiteral("cli")) && sink.lastFont.contains(QStringLiteral("600"))
                    && sink.lastAlign == QStringLiteral("left"));
            check(log, "渲染：edge → 贝塞尔 + 渐变 + 虚线 + 箭头（渐变 1 个、虚线 2 次）",
                sink.bezierCount >= 1 && sink.gradientCount == 1 && sink.dashCount >= 2);
            check(log, "渲染：入场未到的边不画（delay 999999 → edgesPending=1）",
                st.edgesPending == 1 && st.edges == 1);
            check(log, "渲染：不认识的 shape 类型计数披露（unknown=1，不静默跳）",
                st.unknown == 1);
            check(log, "渲染：粒子按 n 画 3 个（相位循环，不随机）",
                st.particles == 3);
            check(log, "渲染：统计里 drawn 与 unknown 分开（画了什么 vs 不认得什么）",
                st.shapes == 7 && st.drawn == 5 && st.unknown == 1);

            // 同一时刻重画 → 指令序列逐条相同（引擎保证两次导出逐字节一致）
            RecordingSink sink2;
            SceneRender::render(*scene, v, true, ArchViewport::Viewport { 1.0, 0.0, 0.0 }, 800, 600,
                1000.0, sink2);
            check(log, "渲染：同一时刻重画 → 指令序列逐条相同（可复现）",
                sink.ops == sink2.ops);
        }

        // ── Canvas2D 像素级（QPainter 背书）──
        // 差分法：同形状「有阴影 vs 无阴影」比形状外的着色像素数 —— 比绝对值稳。
        auto countOutside = [](bool withShadow) {
            QImage img(60, 60, QImage::Format_ARGB32_Premultiplied);
            img.fill(Qt::transparent);
            {
                QPainter p(&img);
                Canvas2D c(&p);
                c.setFillStyle(CanvasPaint(QColor(0, 0, 255)));
                if (withShadow) {
                    c.setShadowColor(QColor(0, 0, 0));
                    c.setShadowBlur(8);
                }
                c.fillRect(25, 25, 10, 10);
            }
            int n = 0;
            for (int y = 0; y < 60; ++y) {
                for (int x = 0; x < 60; ++x) {
                    if (x >= 25 && x < 35 && y >= 25 && y < 35)
                        continue;
                    if (qAlpha(img.pixel(x, y)) > 0)
                        ++n;
                }
            }
            return n;
        };
        const int noShadow = countOutside(false);
        const int withShadow = countOutside(true);
        check(log, "Canvas2D 像素：fillRect 真的填上了（形状内为实色）",
            noShadow == 0); // 无阴影时形状外一个像素都不该着色
        check(log, "Canvas2D 阴影：shadowBlur>0 时形状外出现淡出像素（阴影真的产生了）",
            withShadow > 0 && withShadow > noShadow);

        // 圆角语义的差分判据：同一个 20×20 方块，圆角(r=8) 的**四角**实心像素
        // 远少于直角 —— 只数 arcTo 调用次数是抓不到「圆角画成了直角」的。
        auto cornerFilled = [](bool rounded) {
            QImage img(40, 40, QImage::Format_ARGB32_Premultiplied);
            img.fill(Qt::transparent);
            {
                QPainter p(&img);
                Canvas2D c(&p);
                c.setFillStyle(CanvasPaint(QColor(0, 0, 255)));
                c.beginPath();
                if (rounded) {
                    const double x = 10, y = 10, w = 20, h = 20, r = 8;
                    c.moveTo(x + r, y);
                    c.arcTo(x + w, y, x + w, y + h, r);
                    c.arcTo(x + w, y + h, x, y + h, r);
                    c.arcTo(x, y + h, x, y, r);
                    c.arcTo(x, y, x + w, y, r);
                    c.closePath();
                } else {
                    c.rect(10, 10, 20, 20);
                }
                c.fill();
            }
            int n = 0;
            for (int cy : { 10, 26 }) {
                for (int cx : { 10, 26 }) {
                    for (int y = cy; y < cy + 4; ++y) {
                        for (int x = cx; x < cx + 4; ++x) {
                            if (qAlpha(img.pixel(x, y)) > 128)
                                ++n;
                        }
                    }
                }
            }
            return n;
        };
        const int sharpCorners = cornerFilled(false);
        const int roundCorners = cornerFilled(true);
        check(log, "Canvas2D 圆角：arcTo 真切出圆角（直角方块的四角实心像素远多于圆角）",
            sharpCorners >= 60 && roundCorners < 20 && roundCorners < sharpCorners);

        // ── 批 D2：架构图页的视口与命中（纯函数层，无头可判）──
        // 视口是最容易悄悄错的一环：缩放没跟上下标就「点不中」，
        // 命中区顺序错了就「选错节点」——两者都不该等到看图才发现。
        GraphView vv;
        vv.id = QStringLiteral("arch");
        vv.bx0 = 0; vv.by0 = 0; vv.bx1 = 200; vv.by1 = 100;
        const ArchViewport::Viewport vp = ArchViewport::fit(vv, 800, 600, 40);
        // scale = min((800-2*40)/200, (600-2*40)/100) = min(3.6, 5.2) = 3.6
        check(log, "视口 fit：缩放 = min((宽-2pad)/包围盒宽, (高-2pad)/包围盒高)",
            qAbs(vp.scale - 3.6) < 1e-6);
        check(log, "视口 fit：内容居中（包围盒中心 → 画布中心）",
            qAbs(ArchViewport::toScreen(vp, 100, 50).x() - 400) < 1e-6
                && qAbs(ArchViewport::toScreen(vp, 100, 50).y() - 300) < 1e-6);

        GraphView tinyView;
        tinyView.bx0 = 0; tinyView.by0 = 0; tinyView.bx1 = 10; tinyView.by1 = 10;
        GraphView hugeView;
        hugeView.bx0 = 0; hugeView.by0 = 0; hugeView.bx1 = 100000; hugeView.by1 = 100000;
        GraphView emptyView;
        check(log, "视口 fit：缩放夹在 [0.05, 4]（放大不越界）",
            qAbs(ArchViewport::fit(tinyView, 800, 600, 40).scale - 4.0) < 1e-6);
        check(log, "视口 fit：缩放夹在 [0.05, 4]（缩小不越界）",
            qAbs(ArchViewport::fit(hugeView, 800, 600, 40).scale - 0.05) < 1e-6);
        check(log, "视口 fit：包围盒非法（空视图）→ 恒等视口（不猜比例）",
            qAbs(ArchViewport::fit(emptyView, 800, 600, 40).scale - 1.0) < 1e-6);

        // 屏幕→世界→屏幕 往返一致（换算式自洽 = 点得中）
        const QPointF back = ArchViewport::toWorld(vp, 123.0, 456.0);
        const QPointF again = ArchViewport::toScreen(vp, back.x(), back.y());
        check(log, "视口换算：屏幕→世界→屏幕 往返一致",
            qAbs(again.x() - 123.0) < 1e-6 && qAbs(again.y() - 456.0) < 1e-6);

        // 命中测试：命中区内命中、 区外不命中（不随便挑一个）
        GraphHit hit;
        hit.id = QStringLiteral("mod:src");
        hit.x = 0; hit.y = 0; hit.w = 100; hit.h = 50;
        vv.hits.append(hit);
        const ArchViewport::Viewport identity { 1.0, 0.0, 0.0 };
        check(log, "命中：点在命中区内 → 命中该节点",
            ArchViewport::hitAt(vv, identity, 50, 25).value_or(QString())
                == QStringLiteral("mod:src"));
        check(log, "命中：点在命中区外 → 没命中（不随便挑一个）",
            !ArchViewport::hitAt(vv, identity, 500, 500).has_value());
        // 缩放后同一世界点仍命中 —— 命中与渲染必须共用同一个视口换算
        const QPointF screenCenter = ArchViewport::toScreen(vp, 50, 25);
        check(log, "命中：视口缩放后同一世界点仍命中（命中与渲染同源）",
            ArchViewport::hitAt(vv, vp, screenCenter.x(), screenCenter.y()).value_or(QString())
                == QStringLiteral("mod:src"));

        // ── 引擎回执提取（回执型命令的 stdout 是人话，不是 JSON）──
        check(log, "回执：取末个非空行（引擎回执最后一行是结论）",
            ArchReceipt::receipt(QStringLiteral("架构已生成：首版（第 0 版）\n  探针：库中无旧记录\n下一步：moongit arch query\n"))
                == QStringLiteral("下一步：moongit arch query"));
        check(log, "回执：全空 → 空串（不把空白行当回执）",
            ArchReceipt::receipt(QStringLiteral("  \n\n ")).isEmpty());
        check(log, "回执：抽出 HTML 绝对路径",
            ArchReceipt::htmlPath(QStringLiteral("已重绘：/tmp/x/store/p_1/arch.html · 第 1 版"))
                == QStringLiteral("/tmp/x/store/p_1/arch.html"));
        check(log, "回执：路径与文案用全角冒号粘连时也抽得出（引擎真实回执形态）",
            ArchReceipt::htmlPath(QStringLiteral("已重绘：/tmp/x/store/p_1/render/arch.html · 第 1 版"))
                == QStringLiteral("/tmp/x/store/p_1/render/arch.html"));
        check(log, "回执：相对路径不认（宁可不给「打开」入口，也不给坏按钮）",
            ArchReceipt::htmlPath(QStringLiteral("已重绘：render/arch.html")).isEmpty());

        // ── 两套输出契约（用错模式 = 成功被报成失败）──
        check(log, "输出契约：Text 模式收文本回执（非空即算成功）",
            EngineCli::stdoutSatisfies(EngineCli::OutputMode::Text, QStringLiteral("架构已生成：首版")));
        check(log, "输出契约：Text 模式空 stdout = 契约破坏（不回落成成功）",
            !EngineCli::stdoutSatisfies(EngineCli::OutputMode::Text, QStringLiteral("  \n ")));
        check(log, "输出契约：Json 模式不收文本（成功被误报成失败的根因）",
            !EngineCli::stdoutSatisfies(EngineCli::OutputMode::Json, QStringLiteral("架构已生成：首版"))
                && EngineCli::stdoutSatisfies(EngineCli::OutputMode::Json, QStringLiteral("{\"v\":1}")));
        check(log, "输出契约：Json 模式空 stdout = 契约破坏（不是合法空态）",
            !EngineCli::stdoutSatisfies(EngineCli::OutputMode::Json, QString()));
        // ── 回执通道：stdout 优先，stdout 空时取 stderr ──
        // ⚠ 引擎的 `report` 把「报告已生成：<路径>」写在 **stderr**
        //   （`arch gen` / `render arch` 才在 stdout —— 实测 2026-10-19）。
        //   只认 stdout 的话，report 会被判成「引擎没有回执（退出码 0）」：
        //   **明明成功却说失败**，报告其实已经落盘了。
        check(log, "输出契约：回执通道 stdout 优先（stdout 非空时不看 stderr）",
            EngineCli::receiptText(QStringLiteral("架构已生成：首版"), QStringLiteral("报告已生成：/x.md"))
                == QStringLiteral("架构已生成：首版"));
        check(log, "输出契约：stdout 空时回执取 stderr（引擎 report 把回执写 stderr）",
            EngineCli::receiptText(QString(), QStringLiteral("报告已生成：/x/report-1.md"))
                == QStringLiteral("报告已生成：/x/report-1.md"));
        check(log, "输出契约：两路都空 = 没有回执（不回落成成功）",
            EngineCli::receiptText(QStringLiteral("  \n "), QString()).isEmpty());

        // ── agent 工具表（纯函数，无头可判）──
        // 引擎 tools --json 声明 28 个工具；客户端必须**能执行全部 28 个**。
        // 漂移的症状很隐蔽：模型调了个客户端不会执行的工具，界面上只显示
        // 「未知工具：X」—— 很容易被当成模型乱调，真因却是两份清单不一致。
        {
            const QStringList names = AgentToolPlan::knownToolNames();
            check(log, "agent 工具表：清单恰好 28 个（与引擎 tools --json 声明集对位）",
                names.size() == 28);
            bool allPlanned = !names.isEmpty();
            for (const QString &tool : names) {
                const AgentToolPlan::Plan p = AgentToolPlan::planFor(tool, QJsonObject());
                if (!p.known || p.argv.isEmpty() || p.timeoutMs <= 0) {
                    allPlanned = false;
                    break;
                }
            }
            check(log, "agent 工具表：每个工具都有可执行的 argv 与超时预算（不是半张表）",
                allPlanned);
            check(log, "agent 工具表：未知工具明说（known=false，不静默成功）",
                !AgentToolPlan::planFor(QStringLiteral("没有这个工具"), QJsonObject()).known);

            // argv 形状：命令与引擎 usage 逐一对应
            const AgentToolPlan::Plan archGen
                = AgentToolPlan::planFor(QStringLiteral("arch_gen"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") } });
            check(log, "agent 工具表：arch_gen → arch gen <项目>",
                archGen.argv == (QStringList { QStringLiteral("arch"), QStringLiteral("gen"),
                    QStringLiteral("atlas") }));
            const AgentToolPlan::Plan cgSym
                = AgentToolPlan::planFor(QStringLiteral("codegraph_symbol"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("symbol"), QStringLiteral("main") } });
            check(log, "agent 工具表：codegraph_symbol → graph symbol <项目> <符号> --json",
                cgSym.argv == (QStringList { QStringLiteral("graph"), QStringLiteral("symbol"),
                    QStringLiteral("atlas"), QStringLiteral("main"), QStringLiteral("--json") }));

            // 开关型参数：引擎把 params 声明成**全 string 型必填**，模型多半发字符串。
            // 只认布尔会让 --force/--violations 永远不生效（形同虚设）。
            const AgentToolPlan::Plan forced
                = AgentToolPlan::planFor(QStringLiteral("arch_update"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("force"), QStringLiteral("true") } });
            const AgentToolPlan::Plan notForced
                = AgentToolPlan::planFor(QStringLiteral("arch_update"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("force"), QStringLiteral("false") } });
            check(log, "agent 工具表：开关参数收字符串形态（模型发 \"true\" 也算开）",
                forced.argv.contains(QStringLiteral("--force"))
                    && !notForced.argv.contains(QStringLiteral("--force")));

            // 数值型参数：不是数就不给（缺省交给引擎），不把垃圾递给引擎让它报错
            const AgentToolPlan::Plan badDepth
                = AgentToolPlan::planFor(QStringLiteral("codegraph_tree"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("depth"), QStringLiteral("abc") } });
            const AgentToolPlan::Plan goodDepth
                = AgentToolPlan::planFor(QStringLiteral("codegraph_tree"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("depth"), QStringLiteral("3") } });
            check(log, "agent 工具表：数值参数只给真数（非数不递给引擎）",
                !badDepth.argv.contains(QStringLiteral("--depth"))
                    && goodDepth.argv.contains(QStringLiteral("--depth"))
                    && goodDepth.argv.contains(QStringLiteral("3")));

            // 白名单：越界明说，不转交（引擎的 op 契约只有 pull|push）
            const AgentToolPlan::Plan badOp
                = AgentToolPlan::planFor(QStringLiteral("git_pull_push"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("op"), QStringLiteral("fetch") } });
            check(log, "agent 工具表：op 越界被拒（明说理由，不静默转交）",
                !badOp.reject.isEmpty() && badOp.argv.isEmpty());

            // 需要落临时文件的工具：纯函数层只声明「落哪个 + argv 哪一格放路径」
            const AgentToolPlan::Plan merge
                = AgentToolPlan::planFor(QStringLiteral("codegraph_patch_merge"),
                    QJsonObject { { QStringLiteral("algorithm_json"), QStringLiteral("{}") },
                        { QStringLiteral("agent_json"), QStringLiteral("{}") } });
            check(log, "agent 工具表：吃路径的工具声明临时文件（落盘交给执行方）",
                merge.tempParams.size() == 2
                    && merge.argv.contains(QStringLiteral("{{tmp:algorithm_json}}"))
                    && merge.argv.contains(QStringLiteral("{{tmp:agent_json}}")));

            // format 决定 flag：llm → --llm；text → 纯文本；缺省 → --json
            const AgentToolPlan::Plan confLlm
                = AgentToolPlan::planFor(QStringLiteral("codegraph_confidence"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("format"), QStringLiteral("llm") } });
            const AgentToolPlan::Plan confText
                = AgentToolPlan::planFor(QStringLiteral("codegraph_confidence"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("format"), QStringLiteral("text") } });
            const AgentToolPlan::Plan confDefault
                = AgentToolPlan::planFor(QStringLiteral("codegraph_confidence"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") } });
            check(log, "agent 工具表：format 决定 flag（llm/text/缺省各走各的）",
                confLlm.argv.contains(QStringLiteral("--llm"))
                    && !confText.argv.contains(QStringLiteral("--llm"))
                    && !confText.argv.contains(QStringLiteral("--json"))
                    && confDefault.argv.contains(QStringLiteral("--json")));
        }

        // ── 代码图谱数据层（三源 → 一棵树，纯函数）──
        // 合成规则里藏着三处最容易悄悄错的地方：符号 id 的构造式、疑点归属
        // （函数级那份已归属，置信度侧那份要去重）、汇总卷积。
        {
            const QJsonObject tree = QJsonDocument::fromJson(QByteArray(R"JSON({
              "root": "/tmp/atlas",
              "files": [
                {"path": "src/core/util.c", "lang": "c", "lines": 20,
                 "symbols": [{"kind": "func", "name": "worker", "line": 3},
                             {"kind": "func", "name": "helper", "line": 9}]},
                {"path": "src/main.c", "lang": "c", "lines": 5,
                 "symbols": [{"kind": "func", "name": "main", "line": 1}]}
              ],
              "referenceEdges": [["src/main.c", "src/core/util.c", 2]],
              "depth": 6, "truncated": false, "skipped": 0, "oversizeSkipped": 0,
              "unreadableDirs": [], "unreadableDirsTruncated": false
            })JSON")).object();
            const QJsonObject conf = QJsonDocument::fromJson(QByteArray(R"JSON({
              "root": "/tmp/atlas", "score": 76, "astUsed": false,
              "astNote": "语法树不可用：未安装 ast-grep",
              "dimensions": [{"id": "structure", "label": "结构级", "penalty": 12, "findings": 1, "score": 76}],
              "findings": [
                {"kind": "orphan", "file": "src/core/util.c", "line": 3, "symbol": "helper", "weight": 12, "evidence": "定义后无引用"},
                {"kind": "magic-number", "file": "src/main.c", "line": 1, "symbol": "main", "weight": 5, "evidence": "魔法数"}
              ]
            })JSON")).object();
            const QJsonObject fns = QJsonDocument::fromJson(QByteArray(R"JSON({
              "functions": [
                {"id": "f:src/core/util.c:3:worker", "file": "src/core/util.c", "name": "worker",
                 "kind": "func", "line": 3, "lang": "c", "weight": 12, "trunc": false,
                 "findings": [{"line": 3, "weight": 12, "kind": "orphan", "dim": "structure", "label": "孤儿符号", "evidence": "定义后无引用"}]},
                {"id": "f:src/main.c:1:main", "file": "src/main.c", "name": "main",
                 "kind": "func", "line": 1, "lang": "c", "weight": 0, "trunc": false, "findings": []}
              ],
              "functionEdges": [{"from": "f:src/main.c:1:main", "to": "f:src/core/util.c:3:worker", "w": 2, "tier": "resolved"}],
              "codeSnippets": {"f:src/core/util.c:3:worker": "void worker(void){}\nint x = 1;"}
            })JSON")).object();

            CodeGraphBuild::Source src;
            src.tree = tree;
            src.confidence = conf;
            src.functions = fns;
            const CodeGraphBuild::Result g = CodeGraphBuild::build(src, QStringLiteral("atlas"));

            check(log, "代码图谱：三源齐 → 合成成功（骨架：根+2 层目录+2 文件+3 符号 = 8 节点）",
                g.ok && g.graph.nodes.size() == 8 && g.graph.root >= 0);
            // 符号 id 构造式：tree 的 symbols 不带 id，客户端按引擎同形造
            check(log, "代码图谱：符号 id 按引擎同形构造（f:路径:行号:名字）",
                g.ok && g.graph.indexOf(QStringLiteral("f:src/core/util.c:3:worker")) >= 0
                    && CodeGraphBuild::symbolId(QStringLiteral("src/core/util.c"), 3,
                          QStringLiteral("worker"))
                        == QStringLiteral("f:src/core/util.c:3:worker"));
            // 疑点归属：函数级疑点挂符号；置信度侧同一条不再重复挂文件
            const int workerIdx = g.graph.indexOf(QStringLiteral("f:src/core/util.c:3:worker"));
            const int utilFileIdx = g.graph.indexOf(QStringLiteral("f:src/core/util.c"));
            const int mainFileIdx = g.graph.indexOf(QStringLiteral("f:src/main.c"));
            check(log, "代码图谱：函数级疑点挂到符号（不是文件）",
                g.ok && workerIdx >= 0 && g.graph.nodes.at(workerIdx).ownFindings.size() == 1);
            check(log, "代码图谱：已归属的疑点不重复挂文件（去重，疑点不被数两遍）",
                g.ok && utilFileIdx >= 0 && g.graph.nodes.at(utilFileIdx).ownFindings.isEmpty());
            check(log, "代码图谱：置信度侧的孤儿疑点挂到文件（没被任何符号领走的那些）",
                g.ok && mainFileIdx >= 0 && g.graph.nodes.at(mainFileIdx).ownFindings.size() == 1
                    && g.graph.nodes.at(mainFileIdx).ownFindings.first().kind
                        == QStringLiteral("magic-number"));
            // 汇总卷积：子树疑点数与最高权重
            check(log, "代码图谱：汇总卷积（子树疑点数 2 / 最高权重 12）",
                g.ok && g.graph.nodes.at(g.graph.root).rollN == 2
                    && g.graph.nodes.at(g.graph.root).rollW == 12
                    && g.graph.nodes.at(g.graph.root).fileCount == 2);
            // 排序：目录在前、文件按名、符号按声明行
            // 树形：root → src(目录) → { core(目录) → util.c(文件), main.c(文件) }
            const GraphNode *rootNode = g.ok ? g.graph.node(g.graph.root) : nullptr;
            bool orderOk = rootNode && rootNode->kids.size() == 1
                && g.graph.node(rootNode->kids.first())->kind == GraphNodeKind::dir;
            if (orderOk) {
                const GraphNode *srcDir = g.graph.node(rootNode->kids.first());
                orderOk = srcDir->kids.size() == 2
                    && g.graph.node(srcDir->kids.at(0))->kind == GraphNodeKind::dir
                    && g.graph.node(srcDir->kids.at(0))->name == QStringLiteral("core")
                    && g.graph.node(srcDir->kids.at(1))->kind == GraphNodeKind::file
                    && g.graph.node(srcDir->kids.at(1))->name == QStringLiteral("main.c");
                if (orderOk) {
                    const GraphNode *coreDir = g.graph.node(srcDir->kids.at(0));
                    orderOk = coreDir->kids.size() == 1
                        && g.graph.node(coreDir->kids.first())->name
                            == QStringLiteral("util.c");
                    if (orderOk) {
                        // 同一文件的符号按**声明行**排（不是按名字）
                        const GraphNode *utilFile = g.graph.node(coreDir->kids.first());
                        // ⚠ 夹具刻意让两种排序**分叉**：worker@3（名字在后）
                        //   排前、helper@9 排后 —— 若实现改成按名字排，这条会红。
                        orderOk = utilFile->kids.size() == 2
                            && g.graph.node(utilFile->kids.at(0))->name
                                == QStringLiteral("worker")
                            && g.graph.node(utilFile->kids.at(0))->declLine == 3
                            && g.graph.node(utilFile->kids.at(1))->name
                                == QStringLiteral("helper")
                            && g.graph.node(utilFile->kids.at(1))->declLine == 9;
                    }
                }
            }
            check(log, "代码图谱：排序（目录在前、文件按名、符号按声明行）", orderOk);
            // 符号级调用边 + 源码片段
            check(log, "代码图谱：符号级调用边与源码片段都读得出",
                g.ok && g.symEdges.size() == 1
                    && g.symEdges.first().from == QStringLiteral("f:src/main.c:1:main")
                    && g.symEdges.first().to == QStringLiteral("f:src/core/util.c:3:worker")
                    && g.snippets.contains(QStringLiteral("f:src/core/util.c:3:worker"))
                    && g.fileEdges.size() == 1);
            // 截断披露：0 与「没发」可区分
            check(log, "代码图谱：截断披露（缺键不得当作「没有」）",
                g.ok && g.truncatedPresent && g.skippedPresent
                    && g.oversizeSkippedPresent && g.depth == 6);
            // 置信度总分与降级说明
            check(log, "代码图谱：置信度总分与语法树降级说明都带出来",
                g.ok && g.score == 76 && !g.astNote.isEmpty() && !g.astUsed);
            // 缺源：说清是哪一种
            {
                CodeGraphBuild::Source s2;
                s2.confidence = conf;
                s2.functions = fns;
                const CodeGraphBuild::Result r2 = CodeGraphBuild::build(s2, QStringLiteral("atlas"));
                CodeGraphBuild::Source s3;
                s3.tree = tree;
                s3.functions = fns;
                const CodeGraphBuild::Result r3 = CodeGraphBuild::build(s3, QStringLiteral("atlas"));
                CodeGraphBuild::Source s4;
                s4.tree = tree;
                s4.confidence = conf;
                const CodeGraphBuild::Result r4 = CodeGraphBuild::build(s4, QStringLiteral("atlas"));
                check(log, "代码图谱：缺源明说是哪一种（不回落成空图）",
                    !r2.ok && r2.error.contains(QStringLiteral("图树"))
                        && !r3.ok && r3.error.contains(QStringLiteral("置信度"))
                        && !r4.ok && r4.error.contains(QStringLiteral("函数级")));
            }
            // 可见行：展开与搜索
            {
                QStringList expanded { QStringLiteral("root"), QStringLiteral("d:src") };
                const auto rows = CodeGraphBuild::visibleRows(g.graph, expanded, QString());
                check(log, "代码图谱：可见行随展开态算（根+目录 → 根+目录+2 文件）",
                    rows.size() == 4);
                const auto filtered
                    = CodeGraphBuild::visibleRows(g.graph, QStringList(), QStringLiteral("worker"));
                check(log, "代码图谱：搜索过滤只留命中的路径（含祖先）",
                    !filtered.isEmpty()
                        && filtered.last().node == workerIdx);
            }
        }
    }

    // ── 符号索引热力图（布局与走线，纯函数）──
    // 热力图是代码图谱左栏的另一种模式：文件层铺文件卡，点文件卡下钻到符号层。
    // 铺排与走线都在 logic/HeatLayout（零 QWidget 头），所以判据能无头跑。
    // 判据盯的是**画出来对不对**，不是「函数被调用了没有」：
    //   ① 分数公式与热色三档（契约色，逐字对齐 HTML 交付物）
    //   ② 身份色相：黄金角散布，且**与节点顺序无关**（换个顺序画得一样）
    //   ③ 作用域：文件层=全部文件；下钻层=该文件符号 + 跨作用域边界卡（≤9 + "+N"）
    //   ④ 铺排：不重叠、网格等距、序号连续、分带有序
    //   ⑤ 重心扫描**真的跑了**（关联卡的次序被重排）—— 这条最容易被悄悄摘掉
    //   ⑥ 走线：端点贴在卡上、边不丢、曲线过端点
    {
        // ---- 夹具：一棵两文件的树（a.c 两个符号、b.c 一个符号）----
        auto addNode = [](CodeGraph &g, GraphNodeKind kind, const QString &id, const QString &name,
                          const QString &path, int declLine) {
            GraphNode n;
            n.kind = kind;
            n.id = id;
            n.name = name;
            n.path = path;
            n.declLine = declLine;
            g.nodes << n;
            const int idx = g.nodes.size() - 1;
            g.indexById.insert(id, idx);
            return idx;
        };
        auto addSym = [&addNode](CodeGraph &g, int parent, const QString &path,
                        const QString &name, int line) {
            const int idx = addNode(g, GraphNodeKind::sym,
                QStringLiteral("f:%1:%2:%3").arg(path).arg(line).arg(name), name, path, line);
            g.nodes[parent].kids << idx;
            g.nodes[idx].parent = parent;
            return idx;
        };
        CodeGraph hg;
        const int hA = addNode(hg, GraphNodeKind::file, QStringLiteral("f:src/a.c"),
            QStringLiteral("a.c"), QStringLiteral("src/a.c"), 0);
        const int hB = addNode(hg, GraphNodeKind::file, QStringLiteral("f:src/b.c"),
            QStringLiteral("b.c"), QStringLiteral("src/b.c"), 0);
        hg.root = hA;
        addSym(hg, hA, QStringLiteral("src/a.c"), QStringLiteral("alpha"), 1);
        addSym(hg, hA, QStringLiteral("src/a.c"), QStringLiteral("beta"), 5);
        addSym(hg, hB, QStringLiteral("src/b.c"), QStringLiteral("gamma"), 2);
        hg.nodes[hA].rollWeightSum = 12; // 文件的子树罚分（热色输入）

        // alpha → gamma 是**跨文件**调用（下钻 a.c 时算跨作用域边界）；
        // beta → alpha 是**同文件**调用（下钻 a.c 时算作用域内的边）。
        const QVector<HeatLayout::Edge> hSymEdges {
            HeatLayout::Edge { QStringLiteral("f:src/a.c:1:alpha"),
                QStringLiteral("f:src/b.c:2:gamma"), 3, QStringLiteral("resolved") },
            HeatLayout::Edge { QStringLiteral("f:src/a.c:5:beta"),
                QStringLiteral("f:src/a.c:1:alpha"), 1, QStringLiteral("resolved") },
        };
        const QVector<GraphFileEdge> hFileEdges {
            GraphFileEdge { QStringLiteral("src/a.c"), QStringLiteral("src/b.c"), 2 },
        };
        // 文件层的边集（文件级引用边 → 节点 id 形如 f:路径）
        const QVector<HeatLayout::Edge> hFileEdgesOut
            = HeatLayout::scopeEdges(hg, hSymEdges, hFileEdges, -1);
        const QHash<QString, int> hHues = HeatLayout::huesFor(hg);

        // ① 分数公式（引擎 confidence 的镜像）与热色三档
        check(log, "热力图：置信度分数按罚分算（0→100 / 5→80 / 20→50，多文件摊薄）",
            HeatLayout::confScore(0, 1) == 100 && HeatLayout::confScore(5, 1) == 80
                && HeatLayout::confScore(20, 1) == 50 && HeatLayout::confScore(20, 2) == 66
                && HeatLayout::confScore(0, 1) > HeatLayout::confScore(5, 1)
                && HeatLayout::confScore(5, 1) > HeatLayout::confScore(20, 1));
        check(log, "热力图：热色三档边界（≥80 / ≥60 / 其余）且三色互异",
            HeatLayout::heatColor(80) == QColor(89, 240, 184)
                && HeatLayout::heatColor(79) == QColor(255, 200, 87)
                && HeatLayout::heatColor(60) == QColor(255, 200, 87)
                && HeatLayout::heatColor(59) == QColor(255, 107, 138)
                && HeatLayout::heatColor(85) != HeatLayout::heatColor(65)
                && HeatLayout::heatColor(65) != HeatLayout::heatColor(20));

        // ② 身份色：同色相稳定、不同色相不同色；色相按 id 字典序的黄金角分配
        check(log, "热力图：身份色同色相稳定、异色相异色",
            HeatLayout::idColor(30) == HeatLayout::idColor(30)
                && HeatLayout::idColor(30) != HeatLayout::idColor(200));
        {
            // 黄金角：排序后相邻两 id 的色相差 = round(137.508) = 138
            QStringList ids;
            for (const GraphNode &n : hg.nodes) {
                if (n.kind != GraphNodeKind::dir)
                    ids << n.id;
            }
            ids.sort();
            bool golden = ids.size() >= 2;
            if (golden) {
                const int d = (hHues.value(ids.at(1)) - hHues.value(ids.at(0)) + 360) % 360;
                golden = (d == 138);
            }
            check(log, "热力图：身份色相按黄金角 137.508° 散布（相邻 id 色相差 138）", golden);
        }
        {
            // 身份色相**与节点在 arena 里的顺序无关**（排序键是 id 字典序）——
            // 换一个遍历顺序画出来必须一模一样，否则「同一份数据两台机器两张脸」。
            CodeGraph hg2 = hg;
            std::reverse(hg2.nodes.begin(), hg2.nodes.end());
            const QHash<QString, int> hHues2 = HeatLayout::huesFor(hg2);
            bool same = hHues.size() == hHues2.size();
            for (auto it = hHues.constBegin(); same && it != hHues.constEnd(); ++it)
                same = (hHues2.value(it.key()) == it.value());
            check(log, "热力图：身份色相与节点顺序无关（同一份数据画出来一样）", same);
        }

        // ③ 作用域：文件层 = 全部文件；下钻层 = 该文件符号 + 跨作用域边界卡
        const QVector<HeatLayout::Card> hFileCards
            = HeatLayout::scopeCards(hg, hHues, -1, hSymEdges);
        check(log, "热力图：文件层铺全部文件卡（按名排序，无符号卡）",
            hFileCards.size() == 2 && hFileCards.at(0).name == QStringLiteral("a.c")
                && hFileCards.at(1).name == QStringLiteral("b.c")
                && hFileCards.at(0).kind == GraphNodeKind::file
                && !hFileCards.at(0).boundary);
        const QVector<HeatLayout::Card> hDrillCards
            = HeatLayout::scopeCards(hg, hHues, hA, hSymEdges);
        {
            bool shape = hDrillCards.size() == 3;
            if (shape) {
                // 两个符号卡（按声明行 alpha(1) → beta(5)）+ 一个跨作用域边界卡
                shape = hDrillCards.at(0).name == QStringLiteral("alpha")
                    && hDrillCards.at(1).name == QStringLiteral("beta")
                    && hDrillCards.at(0).declLine == 1 && hDrillCards.at(1).declLine == 5
                    && !hDrillCards.at(0).boundary && !hDrillCards.at(1).boundary
                    && hDrillCards.at(2).boundary
                    && hDrillCards.at(2).path == QStringLiteral("src/b.c");
            }
            check(log, "热力图：下钻层 = 该文件符号（按声明行）+ 跨作用域边界卡（按文件聚合）",
                shape);
        }
        {
            // 边界卡上限：跨作用域引用超过 9 个文件 → 9 张 + 一张「+N」
            CodeGraph many = hg;
            QVector<HeatLayout::Edge> edges = hSymEdges;
            for (int i = 0; i < 12; ++i) {
                const QString path = QStringLiteral("src/x%1.c").arg(i);
                const QString sid = QStringLiteral("f:%1:1:g%2").arg(path).arg(i);
                // ⚠ 这些符号**不能**挂到 a.c 的子节点下 —— 挂上去就在作用域内，
                //   就不算「跨作用域」了（那是夹具的坑，不是实现的坑）。
                addNode(many, GraphNodeKind::sym, sid, QStringLiteral("g%1").arg(i), path, 1);
                edges << HeatLayout::Edge { QStringLiteral("f:src/a.c:1:alpha"), sid, 1,
                    QStringLiteral("resolved") };
            }
            const QHash<QString, int> manyHues = HeatLayout::huesFor(many);
            const QVector<HeatLayout::Card> manyCards
                = HeatLayout::scopeCards(many, manyHues, hA, edges);
            int boundaryCards = 0;
            bool hasMore = false;
            for (const HeatLayout::Card &c : manyCards) {
                if (!c.boundary)
                    continue;
                ++boundaryCards;
                if (c.id == QStringLiteral("cgx:__more"))
                    hasMore = true;
            }
            check(log, "热力图：跨作用域边界卡封顶 9 张，溢出并成「+N」（不无限铺）",
                boundaryCards == 10 && hasMore);
        }
        {
            // 作用域内的边只留同文件那条；跨文件那条不混进来
            const QVector<HeatLayout::Edge> hDrillEdges
                = HeatLayout::scopeEdges(hg, hSymEdges, hFileEdges, hA);
            check(log, "热力图：下钻层的边只含作用域内的（同文件）调用",
                hDrillEdges.size() == 1
                    && hDrillEdges.first().from == QStringLiteral("f:src/a.c:5:beta")
                    && hDrillEdges.first().to == QStringLiteral("f:src/a.c:1:alpha"));
        }
        {
            // 文件层的边是文件级引用边（节点 id 形如 f:路径）
            check(log, "热力图：文件层的边是文件级引用边（id 形如 f:路径）",
                hFileEdgesOut.size() == 1
                    && hFileEdgesOut.first().from == QStringLiteral("f:src/a.c")
                    && hFileEdgesOut.first().to == QStringLiteral("f:src/b.c"));
        }

        // ④ 铺排：不重叠、网格等距、序号连续
        const QVector<HeatLayout::Card> hLaid
            = HeatLayout::layout(hFileCards, hFileEdgesOut, 800, 600);
        {
            bool noOverlap = true;
            for (int i = 0; i < hLaid.size() && noOverlap; ++i) {
                for (int j = i + 1; j < hLaid.size(); ++j) {
                    const HeatLayout::Card &x = hLaid.at(i);
                    const HeatLayout::Card &y = hLaid.at(j);
                    if (x.x < y.x + y.w && y.x < x.x + x.w && x.y < y.y + y.h
                        && y.y < x.y + x.h)
                        noOverlap = false;
                }
            }
            check(log, "热力图：卡片互不重叠（重叠的图没法读）", noOverlap && hLaid.size() == 2);
        }
        {
            // 同一行内：y 严格相等、卡高一致（网格工整）
            bool grid = hLaid.size() == 2;
            if (grid) {
                const HeatLayout::Card &x = hLaid.at(0);
                const HeatLayout::Card &y = hLaid.at(1);
                grid = qFuzzyCompare(x.y, y.y) && qFuzzyCompare(x.h, y.h)
                    && !qFuzzyCompare(x.x, y.x);
            }
            check(log, "热力图：同一行内卡片 y 相等（网格工整，不许参差）", grid);
        }
        {
            // 序号：带内**阅读序**（先 y 后 x）从 1 连续
            // ⚠ 序号跟的是排布后的阅读序，不是 arena/输入序 —— 重心扫描会换位，
            //   序号必须跟着换（不然徽标和看到的顺序对不上）。
            QVector<HeatLayout::Card> byRead = hLaid;
            std::sort(byRead.begin(), byRead.end(),
                [](const HeatLayout::Card &a, const HeatLayout::Card &b) {
                    if (!qFuzzyCompare(a.y, b.y))
                        return a.y < b.y;
                    return a.x < b.x;
                });
            bool rank = !byRead.isEmpty();
            for (int i = 0; i < byRead.size() && rank; ++i)
                rank = (byRead.at(i).rank == i + 1);
            check(log, "热力图：序号徽标按阅读序从 1 连续", rank);
        }
        {
            // 铺排结果**与输入顺序无关**（带内先按语义排序再铺）
            QVector<HeatLayout::Card> shuffled = hFileCards;
            std::reverse(shuffled.begin(), shuffled.end());
            const QVector<HeatLayout::Card> laid2
                = HeatLayout::layout(shuffled, hFileEdgesOut, 800, 600);
            bool same = laid2.size() == hLaid.size();
            for (int i = 0; same && i < hLaid.size(); ++i)
                same = (laid2.at(i).id == hLaid.at(i).id)
                    && qFuzzyCompare(laid2.at(i).x, hLaid.at(i).x)
                    && qFuzzyCompare(laid2.at(i).y, hLaid.at(i).y);
            check(log, "热力图：铺排结果与输入顺序无关（同一份数据画出来一样）", same);
        }
        {
            // 分带：文件带在上、符号带在下（下钻层才有两带）
            const QVector<HeatLayout::Card> drillLaid
                = HeatLayout::layout(hDrillCards, QVector<HeatLayout::Edge>(), 800, 600);
            bool banded = drillLaid.size() == 3;
            if (banded) {
                // 边界卡在独立的一带（layerIndex 更大），y 更大
                int symLayer = -1, bndLayer = -1;
                for (const HeatLayout::Card &c : drillLaid) {
                    if (c.boundary)
                        bndLayer = c.layerIndex;
                    else if (symLayer < 0)
                        symLayer = c.layerIndex;
                }
                banded = symLayer >= 0 && bndLayer > symLayer;
            }
            check(log, "热力图：分带有序（符号带在上、跨作用域边界带在下）", banded);
        }

        // ⑤ 重心扫描**真的跑了**（最容易悄悄摘掉的一段）
        // 夹具：三个文件排成一行，a.c ↔ c.c 有边。名次序是 a,b,c；
        // 重心扫描会把关联的两张卡重排到邻居重心一侧 —— 于是 a 的 x 跑到 c 的右边。
        // 摘掉扫描 → a 仍在最左 → 这条判据必须变红。
        {
            CodeGraph g3;
            auto addFile = [&g3](const QString &name) {
                GraphNode n;
                n.kind = GraphNodeKind::file;
                n.id = QStringLiteral("f:src/") + name;
                n.name = name;
                n.path = QStringLiteral("src/") + name;
                g3.nodes << n;
                return g3.nodes.size() - 1;
            };
            addFile(QStringLiteral("a.c"));
            addFile(QStringLiteral("b.c"));
            addFile(QStringLiteral("c.c"));
            const QHash<QString, int> hues3 = HeatLayout::huesFor(g3);
            const QVector<HeatLayout::Card> scope3
                = HeatLayout::scopeCards(g3, hues3, -1, QVector<HeatLayout::Edge>());
            const QVector<HeatLayout::Edge> edges3 {
                HeatLayout::Edge { QStringLiteral("f:src/a.c"), QStringLiteral("f:src/c.c"), 2,
                    QStringLiteral("resolved") },
            };
            const QVector<HeatLayout::Card> laid3
                = HeatLayout::layout(scope3, edges3, 800, 600);
            double ax = 0, cx = 0;
            bool found = laid3.size() == 3;
            for (const HeatLayout::Card &c : laid3) {
                if (c.id == QStringLiteral("f:src/a.c"))
                    ax = c.x;
                if (c.id == QStringLiteral("f:src/c.c"))
                    cx = c.x;
            }
            check(log, "热力图：重心扫描生效（关联卡被重排到邻居重心侧）",
                found && ax > cx);
        }

        // ⑥ 走线：端点贴在卡上、边不丢、曲线过端点
        {
            const QVector<HeatLayout::Route> hRoutes
                = HeatLayout::routes(hLaid, hFileEdgesOut);
            bool ends = hRoutes.size() == 1;
            if (ends) {
                const HeatLayout::Route &r = hRoutes.first();
                ends = r.points.size() >= 2 && r.smoothed.size() >= 2
                    && !r.smoothed.first().isNull() && !r.smoothed.last().isNull();
            }
            check(log, "热力图：走线有折线与平滑采样（边不丢）", ends);
        }
        {
            // Catmull-Rom：过端点、点数 = 1 + (n-1)*per
            const QVector<QPointF> pts { QPointF(0, 0), QPointF(10, 20), QPointF(30, 5),
                QPointF(50, 40) };
            const QVector<QPointF> sm = HeatLayout::catmull(pts, 8);
            check(log, "热力图：曲线过首尾端点且采样数按段数给足",
                sm.size() == 1 + (pts.size() - 1) * 8 && qFuzzyCompare(sm.first().x(), 0.0)
                    && qFuzzyCompare(sm.first().y(), 0.0) && qFuzzyCompare(sm.last().x(), 50.0)
                    && qFuzzyCompare(sm.last().y(), 40.0));
        }
    }

    // ── 补丁体检（引擎 graph patchconf 三层，判定层纯函数）──
    // 判据盯的是「披露得对不对」与「排序/阈值算得对不对」：
    //   ① null 信号 ≠ 0 分（null = 分母为 0、算不出）
    //   ② 契约形状不对时**必须报错**，不许当 0 分放行
    //   ③ 低置信度实体：阈值 + 升序 + 置信度未知不参与
    //   ④ 裁决 id **原样回填**（uncertain.id 与 entity.id 不是同一套 id 空间）
    //   ⑤ 终稿的复核数在 diagnostics.reviewed_by_agent（不在顶层 reviewed）
    //   ⑥ diff 抽实码：行号对得上、抽不到就说抽不到
    {
        // ---- 夹具：一份 Layer 1 载荷（形状照引擎实测）----
        const QString kLayer1 = QStringLiteral(R"JSON({
  "schema": "moongit-patch-confidence/1",
  "overall": 0.5625,
  "signals": {"S1": 1, "S2": 0, "S3": 0.5, "S4": null, "S5": 1,
              "S6": 0, "S7": null, "S8": 1, "S9": 1, "S10": 1},
  "entities": [
    {"id": "helper@src/util.c:5", "kind": "func", "confidence": 0.9,
     "file": "src/util.c", "line": 5, "relations": []},
    {"id": "weak@src/util.c:9", "kind": "func", "confidence": 0.4,
     "file": "src/util.c", "line": 9, "relations": []},
    {"id": "worse@src/util.c:12", "kind": "func", "confidence": 0.1,
     "file": "src/util.c", "line": 12, "relations": []},
    {"id": "unknown@src/util.c:20", "kind": "func",
     "file": "src/util.c", "line": 20, "relations": []}
  ],
  "uncertain": [
    {"id": "src/util.c@6:mystery_call", "issue": "unresolved_call",
     "detail": "call to mystery_call(…) not found in repo or patch",
     "candidates": [], "context_ref": {"file": "src/util.c", "line": 6}}
  ],
  "diagnostics": {"total_entities": 4, "total_relations": 3, "parse_errors": 0,
                  "patch_files": 1, "added_lines": 9, "null_signals": ["S4", "S7"],
                  "null_signals_note": "null 信号 = 词法层无法可靠计算"}
})JSON");
        const QJsonDocument kDoc = QJsonDocument::fromJson(kLayer1.toUtf8());
        const PatchLayer1 l1 = PatchCheck::parseLayer1(kDoc.object());

        check(log, "补丁体检：Layer 1 载荷解析（总分 / 实体 / 拿不准的项 / 诊断）",
            l1.ok && l1.schema == QLatin1String("moongit-patch-confidence/1")
                && l1.overallPresent && qFuzzyCompare(l1.overall, 0.5625)
                && l1.entities.size() == 4 && l1.uncertain.size() == 1
                && l1.uncertain.first().id == QLatin1String("src/util.c@6:mystery_call")
                && l1.uncertain.first().hasContext
                && l1.uncertain.first().file == QLatin1String("src/util.c")
                && l1.uncertain.first().line == 6
                && l1.diagnostics.present && l1.diagnostics.patchFiles == 1
                && l1.diagnostics.addedLines == 9
                && l1.diagnostics.nullSignals == QStringList({ "S4", "S7" }));

        // ① null 信号 ≠ 0 分：S4/S7 是 null，S2 是 0 —— 两者必须分得开
        {
            bool s4Null = false, s2Zero = false, s1One = false;
            for (const PatchSignal &s : l1.signalList) {
                if (s.key == QLatin1String("S4"))
                    s4Null = !s.hasValue;
                if (s.key == QLatin1String("S2"))
                    s2Zero = s.hasValue && qFuzzyCompare(s.value, 0.0);
                if (s.key == QLatin1String("S1"))
                    s1One = s.hasValue && qFuzzyCompare(s.value, 1.0);
            }
            check(log, "补丁体检：null 信号与 0 分可区分（算不出 ≠ 得了 0 分）",
                s4Null && s2Zero && s1One);
        }
        {
            // 信号键要**列全 10 个**（缺键的也要列出来标成算不出）——
                // 少了 S7，用户不知道是引擎没发还是这一项没算。
            check(log, "补丁体检：信号键列全 S1–S10（缺键不当成不存在）",
                l1.signalList.size() == 10);
        }
        {
            // ② 契约形状不对必须报错，不许当 0 分放行
            QJsonObject noSchema;
            noSchema.insert(QStringLiteral("overall"), 0.5);
            const PatchLayer1 bad1 = PatchCheck::parseLayer1(noSchema);
            QJsonObject oldSchema;
            oldSchema.insert(QStringLiteral("schema"),
                QStringLiteral("moongit-patch-confidence/0"));
            oldSchema.insert(QStringLiteral("signals"), QJsonObject());
            const PatchLayer1 bad2 = PatchCheck::parseLayer1(oldSchema);
            check(log, "补丁体检：契约形状不对时报错（缺 schema / 版本不认识），不当成 0 分",
                !bad1.ok && bad1.error.contains(QStringLiteral("schema")) && !bad2.ok
                    && bad2.error.contains(QStringLiteral("moongit-patch-confidence/1")));
        }
        {
            // ③ 低置信度：阈值 0.75、**升序**、置信度未知（缺键）不参与
            const QVector<PatchEntity> lows = PatchCheck::lowConfidenceEntities(l1);
            bool shape = lows.size() == 2;
            if (shape) {
                shape = qFuzzyCompare(lows.at(0).confidence, 0.1)
                    && qFuzzyCompare(lows.at(1).confidence, 0.4);
                // 0.9 的不参与、缺 confidence 的不参与
                for (const PatchEntity &e : lows)
                    shape = shape && e.confidence < 0.75 && e.confidencePresent;
            }
            check(log, "补丁体检：低置信度实体按 <0.75 筛出并**升序**（最不可信的排最前）", shape);
        }
        {
            // ④ 默认裁决：每个拿不准的项一条、默认存疑 / 0.5、id 原样回填
            const QVector<PatchVerdict> verdicts = PatchCheck::defaultVerdicts(l1);
            check(log, "补丁体检：默认裁决逐项给（存疑 / 0.5，id 原样回填）",
                verdicts.size() == 1
                    && verdicts.first().id == QLatin1String("src/util.c@6:mystery_call")
                    && verdicts.first().verdict == QLatin1String("ambiguous")
                    && qFuzzyCompare(verdicts.first().confidence, 0.5));
        }
        {
            // ⑤ agent.json 形状：task + items；id 原样回填；越界 verdict 归一
            QVector<PatchVerdict> v = PatchCheck::defaultVerdicts(l1);
            v[0].verdict = QLatin1String("resolved");
            v[0].confidence = 0.9;
            const QJsonObject payload = PatchCheck::agentPayload(v);
            const QJsonArray items = payload.value(QStringLiteral("items")).toArray();
            bool shape = payload.value(QStringLiteral("task")).toString()
                    == QLatin1String("layer2_review")
                && items.size() == 1
                && items.at(0).toObject().value(QStringLiteral("id")).toString()
                    == QLatin1String("src/util.c@6:mystery_call")
                && items.at(0).toObject().value(QStringLiteral("verdict")).toString()
                    == QLatin1String("resolved");
            // 越界值要归一，不能原样透给引擎
            QVector<PatchVerdict> bad = PatchCheck::defaultVerdicts(l1);
            bad[0].verdict = QLatin1String("whatever");
            const QJsonArray badItems
                = PatchCheck::agentPayload(bad).value(QStringLiteral("items")).toArray();
            shape = shape && badItems.at(0).toObject().value(QStringLiteral("verdict")).toString()
                == QLatin1String("ambiguous");
            check(log, "补丁体检：agent.json 形状对（task/items、id 原样回填、越界值归一）", shape);
        }
        {
            // ⑤ 终稿：复核数在 diagnostics.reviewed_by_agent（**不在**顶层 reviewed）
            const QString kMerged = QStringLiteral(R"JSON({
  "schema": "moongit-patch-confidence-merged/1",
  "overall": 0.475,
  "signals": {"S1": 0.5, "S4": null},
  "entities": [],
  "alerts": [{"level": "high", "type": "unresolved_call",
              "detail": "call to mystery_call(…) not found in repo or patch — agent 判定未解析"}],
  "sources": {"algorithm": true, "agent": true},
  "diagnostics": {"certain_from_algorithm": 1, "reviewed_by_agent": 1, "deferred": 0}
})JSON");
            const PatchMerged merged
                = PatchCheck::parseMerged(QJsonDocument::fromJson(kMerged.toUtf8()).object());
            check(log, "补丁体检：终稿读复核数走 diagnostics.reviewed_by_agent（顶层 reviewed 没有这个键）",
                merged.ok && merged.overallPresent && qFuzzyCompare(merged.overall, 0.475)
                    && merged.alerts.size() == 1
                    && merged.alerts.first().level == QLatin1String("high")
                    && merged.diagnosticsPresent && merged.reviewedByAgent == 1
                    && merged.certainFromAlgorithm == 1 && merged.deferred == 0
                    && merged.sourcesAlgorithm && merged.sourcesAgent);
        }
        {
            // ⑥ diff 抽实码：行号对得上、文件不在补丁里就是抽不到
            const QString kDiff = QStringLiteral(
                "diff --git a/src/util.c b/src/util.c\n"
                "index 41d0610..5ff4b9a 100644\n"
                "--- a/src/util.c\n"
                "+++ b/src/util.c\n"
                "@@ -1,3 +1,7 @@\n"
                " int compute(int n) {\n"
                "-    return n * 2;\n"
                "+    return n * 3;\n"
                "+}\n"
                "+\n"
                "+int helper(int a) {\n"
                "+    return compute(a) + 1;\n"
                " }\n");
            const QStringList snip
                = PatchCheck::diffSnippet(kDiff, QStringLiteral("src/util.c"), 6, 2);
            const QStringList other
                = PatchCheck::diffSnippet(kDiff, QStringLiteral("src/other.c"), 6, 2);
            check(log, "补丁体检：diff 抽实码行号对得上（抽不到就说抽不到，不给空壳）",
                snip.size() == 4 && snip.at(0).startsWith(QLatin1Char('4'))
                    && snip.at(1).startsWith(QLatin1Char('5'))
                    && snip.at(2) == QLatin1String("6\t    return compute(a) + 1;")
                    && snip.at(3).startsWith(QLatin1Char('7'))
                    && other.isEmpty());
        }
        {
            // hunk 头解析：@@ -3,7 +41,9 @@ → 新起始行 41
            check(log, "补丁体检：hunk 头的新起始行号解析（+41 → 41）",
                PatchCheck::parseNewStart(QStringLiteral("@@ -3,7 +41,9 @@")) == 41
                    && PatchCheck::parseNewStart(QStringLiteral("@@ -1,3 +1,7 @@")) == 1
                    && PatchCheck::parseNewStart(QStringLiteral("no hunk here")) == 0);
        }
        {
            // 分数档位边界（mac 同款：≥0.8 高 / ≥0.5 中 / 其余低）
            check(log, "补丁体检：分数档位边界（0.8 高 / 0.5 中 / 其余低）",
                PatchCheck::bandOf(0.8) == PatchCheck::ScoreBand::high
                    && PatchCheck::bandOf(0.79) == PatchCheck::ScoreBand::mid
                    && PatchCheck::bandOf(0.5) == PatchCheck::ScoreBand::mid
                    && PatchCheck::bandOf(0.49) == PatchCheck::ScoreBand::low);
        }
    }

    // ── 固定文档页（关于 / 帮助 / 开源感谢 / 更新日志）──
    // 文档是「写死在代码里」的长文，但它**会撒谎**：抄 mac 的文案就把本客户端
    // 说成 Swift/macOS 的了。所以判据盯的是「事实写对没有」，不是「有没有字」：
    //   ① 四个类目齐全、正文非空、互不相同
    //   ② 平台词写对（Qt / DDE / deepin），且**不含** mac 的平台词
    //   ③ 仓库地址只有一个出处（正文里的 URL 必须都来自 clientRepo()/engineRepo()）
    //   ④ 帮助页提到的入口必须**真的存在**（架构图 / 代码图谱 / 补丁体检）
    //   ⑤ 认不出的语言 → 空串（不回落成中文）
    {
        const QVector<DocPages::Kind> all = DocPages::kinds();
        check(log, "文档页：四个类目齐全且标识稳定（about / help / openSource / changelog）",
            all.size() == 4 && DocPages::kindKey(DocPages::Kind::about) == QStringLiteral("about")
                && DocPages::kindKey(DocPages::Kind::help) == QStringLiteral("help")
                && DocPages::kindKey(DocPages::Kind::openSource)
                    == QStringLiteral("openSource")
                && DocPages::kindKey(DocPages::Kind::changelog)
                    == QStringLiteral("changelog"));

        bool allNonEmpty = !all.isEmpty();
        QSet<QString> seen;
        bool distinct = true;
        for (const DocPages::Kind &k : all) {
            const QString text = DocPages::content(k);
            allNonEmpty = allNonEmpty && !text.trimmed().isEmpty();
            distinct = distinct && !seen.contains(text);
            seen.insert(text);
        }
        check(log, "文档页：四类正文都非空且互不相同（不是同一篇复制四份）",
            allNonEmpty && distinct);

        {
            // 显示名也必须齐全且互不相同（切换按钮不能有两个「帮助」）
            QSet<QString> titles;
            bool ok = true;
            for (const DocPages::Kind &k : all) {
                const QString t = DocPages::kindTitle(k);
                ok = ok && !t.isEmpty() && !titles.contains(t);
                titles.insert(t);
            }
            check(log, "文档页：类目显示名齐全且互不相同", ok);
        }
        {
            // ② 平台词写对：必须是 deepin 的事实，且**不许**出现 mac 的平台词
            const QString about = DocPages::content(DocPages::Kind::about);
            check(log, "文档页：关于页写的是本平台事实（Qt / DDE / deepin），不含 mac 的平台词",
                about.contains(QStringLiteral("Qt")) && about.contains(QStringLiteral("DDE"))
                    && about.contains(QStringLiteral("deepin"))
                    && !about.contains(QStringLiteral("Swift"))
                    && !about.contains(QStringLiteral("macOS")));
        }
        {
            // ③ 仓库地址单一出处：正文里出现的仓库 URL 必须都来自两个函数之一。
            //   ⚠ 正则必须**吃掉路径段**（`/tree/dev` 之类）：只在 `/` 前截断的话，
            //   「https://…/moongit/tree/dev」会被截成「https://…/moongit」→ 蒙对。
            QRegularExpression urlRe(
                QStringLiteral("https://github\\.com/asdshuaishuai/[A-Za-z0-9_./-]+"));
            bool onlyKnown = true;
            for (const DocPages::Kind &k : all) {
                const QString text = DocPages::content(k);
                auto it = urlRe.globalMatch(text);
                while (it.hasNext()) {
                    QString u = it.next().captured(0);
                    while (u.endsWith(QLatin1Char('.'))) // 句末的点不算地址的一部分
                        u.chop(1);
                    onlyKnown = onlyKnown
                        && (u == DocPages::clientRepo() || u == DocPages::engineRepo());
                }
            }
            check(log, "文档页：正文里的仓库地址只有两个出处（不许手抄第三份）",
                onlyKnown && DocPages::content(DocPages::Kind::about)
                        .contains(DocPages::engineRepo())
                    && DocPages::content(DocPages::Kind::openSource)
                        .contains(DocPages::engineRepo()));
        }
        {
            // ④ 帮助页提到的入口必须真的存在（文档不许吹牛）
            const QString help = DocPages::content(DocPages::Kind::help);
            check(log, "文档页：帮助页提到的入口都真实存在（架构图 / 代码图谱 / 补丁体检）",
                help.contains(QStringLiteral("架构图")) && help.contains(QStringLiteral("代码图谱"))
                    && help.contains(QStringLiteral("补丁体检")));
        }
        {
            // 致谢页要点名引擎与模型目录
            const QString ack = DocPages::content(DocPages::Kind::openSource);
            check(log, "文档页：致谢页点名引擎与模型目录",
                ack.contains(QStringLiteral("moongit"))
                    && ack.contains(QStringLiteral("models.dev")));
        }
        {
            // 更新日志要给出版本
            check(log, "文档页：更新日志给出版本号",
                DocPages::content(DocPages::Kind::changelog)
                    .contains(QStringLiteral("v0.1.0")));
        }
        {
            // ⑤ 认不出的语言 → 空串，不回落成中文
            const bool empty = DocPages::content(DocPages::Kind::about,
                static_cast<DocPages::Language>(99))
                                   .isEmpty();
            check(log, "文档页：认不出的语言返回空串（不回落成中文冒充）", empty);
        }
    }

    // ── 语法高亮（9 语言，与引擎 detectLang 对齐）──
    // 判据盯的是「分类对不对」：颜色在界面上只是「怪了点」，分类错了没人会发现。
    //   ① 九种语言齐全且顺序与引擎 detectLang 一致（少一种 = 那种语言的源码是纯色）
    //   ② 每种语言的关键词表都真能用（拿表里的词去扫，必须扫出 keyword）
    //   ③ 四类 token：整行注释 / 字符串（含闭合引号）/ 关键字 / 数字
    //   ④ 字符串里的 # 不是注释（python）
    //   ⑤ 段不重叠、不越界、按 start 升序
    {
        const QVector<QString> langs = SyntaxHighlight::languages();
        check(log, "语法高亮：九种语言齐全且顺序与引擎 detectLang 一致",
            langs.size() == 9 && langs.at(0) == QStringLiteral("swift")
                && langs.at(1) == QStringLiteral("cangjie") && langs.at(2) == QStringLiteral("ts")
                && langs.at(3) == QStringLiteral("python") && langs.at(4) == QStringLiteral("go")
                && langs.at(5) == QStringLiteral("rust") && langs.at(6) == QStringLiteral("java")
                && langs.at(7) == QStringLiteral("kotlin") && langs.at(8) == QStringLiteral("c"));

        {
            // ② 每种语言的关键词表都能用：拿表里的词去扫，必须扫出 keyword
            bool allWork = !langs.isEmpty();
            for (const QString &lang : langs) {
                const QSet<QString> kws = SyntaxHighlight::keywords(lang);
                if (kws.isEmpty()) {
                    allWork = false;
                    break;
                }
                const QString word = *kws.constBegin();
                const QVector<SyntaxHighlight::Span> sp
                    = SyntaxHighlight::highlight(word, lang);
                if (sp.size() != 1 || sp.at(0).kind != SyntaxHighlight::Kind::keyword
                    || sp.at(0).start != 0 || sp.at(0).len != word.size()) {
                    allWork = false;
                    break;
                }
            }
            check(log, "语法高亮：九种语言的关键词表都真能扫出 keyword", allWork);
        }
        {
            // 不认识的语言 → 回落仓颉（mac 同款），且明确说不支持
            check(log, "语法高亮：不认识的语言回落仓颉且被标为不支持",
                !SyntaxHighlight::supportsLanguage(QStringLiteral("brainfuck"))
                    && SyntaxHighlight::supportsLanguage(QStringLiteral("cangjie"))
                    && SyntaxHighlight::keywords(QStringLiteral("brainfuck"))
                        == SyntaxHighlight::keywords(QStringLiteral("cangjie")));
        }
        {
            // 整行注释 → 一整段 comment
            // ⚠ 期望值从字符串**算**出来，不手数长度 —— 手数的那版判据自己数错了，
            //   实现是对的、判据是红的（判据写错比实现写错更难查）。
            const QString line = QStringLiteral("   // 这是注释");
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(line, QStringLiteral("c"));
            check(log, "语法高亮：整行注释扫成一整段",
                sp.size() == 1 && sp.at(0).kind == SyntaxHighlight::Kind::comment
                    && sp.at(0).start == 0 && sp.at(0).len == line.size());
        }
        {
            // 行尾注释 → 从 // 到行尾
            const QString line = QStringLiteral("int x = 1; // 尾注");
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(line, QStringLiteral("c"));
            const int at = line.indexOf(QStringLiteral("//"));
            bool ok = at > 0 && !sp.isEmpty();
            if (ok) {
                const SyntaxHighlight::Span &last = sp.last();
                ok = last.kind == SyntaxHighlight::Kind::comment && last.start == at
                    && last.start + last.len == line.size();
            }
            check(log, "语法高亮：行尾注释从 // 吃到行尾", ok);
        }
        {
            // ③ 字符串吃到**闭合引号**（半截着色的字符串最难看）
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(QStringLiteral("x = \"hi\""), QStringLiteral("c"));
            check(log, "语法高亮：字符串吃到闭合引号",
                sp.size() == 1 && sp.at(0).kind == SyntaxHighlight::Kind::string
                    && sp.at(0).start == 4 && sp.at(0).len == 4);
        }
        {
            // ④ python：字符串里的 # 不是注释
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(QStringLiteral("s = \"# not comment\""),
                    QStringLiteral("python"));
            bool ok = sp.size() == 1 && sp.at(0).kind == SyntaxHighlight::Kind::string;
            if (ok) {
                // 整行不是注释（否则会是一整段 comment）
                ok = sp.at(0).start == 4;
            }
            check(log, "语法高亮：字符串里的 # 不当注释（python）", ok);
        }
        {
            // ④ python：**字符串外**的 # 才是注释（行尾 #）
            //    上一条只验了「字符串里的 #」，碰不到行尾 # 那条分支 —— 夹具得覆盖它。
            const QString line = QStringLiteral("x = 1  # 尾注");
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(line, QStringLiteral("python"));
            const int at = line.indexOf(QLatin1Char('#'));
            bool ok = at > 0 && !sp.isEmpty();
            if (ok) {
                const SyntaxHighlight::Span &last = sp.last();
                ok = last.kind == SyntaxHighlight::Kind::comment && last.start == at
                    && last.start + last.len == line.size();
            }
            check(log, "语法高亮：python 行尾 # 是注释（字符串外才生效）", ok);
        }
        {
            // ③ 关键字 / 数字分类
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(QStringLiteral("return 0xFF;"), QStringLiteral("go"));
            check(log, "语法高亮：关键字与十六进制数字分得开",
                sp.size() == 2 && sp.at(0).kind == SyntaxHighlight::Kind::keyword
                    && sp.at(0).len == 6 && sp.at(1).kind == SyntaxHighlight::Kind::number
                    && sp.at(1).len == 4);
        }
        {
            // ⑤ 段不重叠 / 不越界 / 按 start 升序（乱了就涂花）
            const QString line = QStringLiteral("func main() { let x = 1; /* c */ } // 尾");
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(line, QStringLiteral("cangjie"));
            bool ordered = true, inRange = true, noOverlap = true;
            int prevEnd = 0;
            for (const SyntaxHighlight::Span &s : sp) {
                ordered = ordered && s.start >= prevEnd;
                inRange = inRange && s.start >= 0 && s.len > 0
                    && s.start + s.len <= line.size();
                prevEnd = s.start + s.len;
            }
            for (int i = 1; i < sp.size(); ++i)
                noOverlap = noOverlap && sp.at(i).start >= sp.at(i - 1).start + sp.at(i - 1).len;
            check(log, "语法高亮：段按 start 升序、不重叠、不越界", ordered && inRange && noOverlap);
        }
        {
            // 行注释前缀：python 用 #，其余 //
            check(log, "语法高亮：行注释前缀（python # / 其余 //）",
                SyntaxHighlight::lineCommentPrefix(QStringLiteral("python"))
                        == QStringLiteral("#")
                    && SyntaxHighlight::lineCommentPrefix(QStringLiteral("go"))
                        == QStringLiteral("//"));
        }
        {
            // 空行 → 空段（不产出垃圾）
            check(log, "语法高亮：空行不产出段",
                SyntaxHighlight::highlight(QString(), QStringLiteral("c")).isEmpty()
                    && SyntaxHighlight::highlight(QStringLiteral("   "), QStringLiteral("c"))
                           .isEmpty());
        }
    }

    // ── 图谱三件套（overview / symbol / impact）──
    // 判据盯三处「错得毫无声响」的口径：
    //   ① 引擎**只认符号名** —— 传符号 id 进去它返回空结果，看着像「没有影响面」
    //   ② 符号不存在**不是错误**（引擎返回空 defs 且退出码 0）
    //   ③ 影响面是**词法近似**（引擎自己标 granularity）+ 可能被截断
    {
        check(log, "图谱三件套：符号 id 取名字（引擎只认名字，传 id 会返回空结果）",
            GraphInsight::symbolNameFromId(QStringLiteral("f:src/util.c:1:compute"))
                == QStringLiteral("compute")
                && GraphInsight::symbolNameFromId(QStringLiteral("f:src/a:b.c:7:worker"))
                    == QStringLiteral("worker")
                && GraphInsight::symbolNameFromId(QStringLiteral("nosuchshape")).isEmpty());

        {
            const QString kOv = QStringLiteral(R"JSON({
  "root": "/tmp/x", "files": 3, "symbols": 4,
  "topFiles": [{"path": "src/util.c", "symbols": 3, "lines": 12},
               {"path": "src/main.c", "symbols": 1, "lines": 5}],
  "imports": 0, "referenceEdges": 1,
  "truncated": true, "skipped": 2, "oversizeSkipped": 1,
  "byLang": {"c": 3}, "byKind": {"func": 4},
  "unreadableDirs": ["a/b"], "unreadableDirsTruncated": true
})JSON");
            const GraphInsight::Overview ov
                = GraphInsight::parseOverview(QJsonDocument::fromJson(kOv.toUtf8()).object());
            check(log, "图谱三件套：概览解析（计数 / Top 文件 / 语言 / 种类 / 截断披露）",
                ov.ok && ov.files == 3 && ov.symbols == 4 && ov.referenceEdges == 1
                    && ov.topFiles.size() == 2 && ov.topFiles.at(0).file == QStringLiteral("src/util.c")
                    && ov.topFileSymbols.at(0) == 3 && ov.topFileLines.at(0) == 12
                    && ov.byLang.value(QStringLiteral("c")) == 3
                    && ov.byKind.value(QStringLiteral("func")) == 4
                    && ov.truncated && ov.skipped == 2 && ov.oversizeSkipped == 1
                    && ov.unreadableDirs.size() == 1 && ov.unreadableDirsTruncated);
        }
        {
            // 契约形状不对 → 报错（不当空结果放行）
            const GraphInsight::Overview bad
                = GraphInsight::parseOverview(QJsonObject());
            check(log, "图谱三件套：概览契约形状不对时报错", !bad.ok && !bad.error.isEmpty());
        }
        {
            const QString kSym = QStringLiteral(R"JSON({
  "name": "compute",
  "defs": [{"file": "src/util.c", "line": 1, "kind": "func"}],
  "referencedBy": [{"file": "src/main.c", "weight": 1}]
})JSON");
            const GraphInsight::SymbolDetail sd
                = GraphInsight::parseSymbol(QJsonDocument::fromJson(kSym.toUtf8()).object());
            check(log, "图谱三件套：符号详情解析（定义点 / 引用来源）",
                sd.ok && sd.found() && sd.name == QStringLiteral("compute")
                    && sd.defs.size() == 1 && sd.defs.at(0).file == QStringLiteral("src/util.c")
                    && sd.defs.at(0).line == 1 && sd.referencedBy.size() == 1
                    && sd.referencedBy.at(0).file == QStringLiteral("src/main.c")
                    && sd.referencedBy.at(0).weight == 1);
        }
        {
            // ② 符号不存在：引擎返回空 defs 且**退出码 0** —— 不是契约坏了，是「没找到」
            const QString kMiss = QStringLiteral(R"JSON({"name": "nosuchsym", "defs": []})JSON");
            const GraphInsight::SymbolDetail miss
                = GraphInsight::parseSymbol(QJsonDocument::fromJson(kMiss.toUtf8()).object());
            check(log, "图谱三件套：符号不存在是「没找到」不是错误（ok 仍为真、found 为假）",
                miss.ok && !miss.found() && miss.name == QStringLiteral("nosuchsym"));
        }
        {
            const QString kImp = QStringLiteral(R"JSON({
  "name": "compute",
  "defs": [{"file": "src/util.c", "line": 1, "kind": "func"}],
  "refFiles": ["src/main.c"],
  "impactedSymbols": [{"file": "src/main.c", "symbol": "main", "kind": "func"}],
  "granularity": "lexical-file-level",
  "refFilesCapped": true, "impactedCapped": false
})JSON");
            const GraphInsight::Impact im
                = GraphInsight::parseImpact(QJsonDocument::fromJson(kImp.toUtf8()).object());
            check(log, "图谱三件套：影响面解析（受影响符号 / 引用文件 / 粒度 / 截断）",
                im.ok && im.impactedSymbols.size() == 1
                    && im.impactedSymbols.at(0).symbol == QStringLiteral("main")
                    && im.impactedSymbols.at(0).file == QStringLiteral("src/main.c")
                    && im.refFiles.size() == 1 && im.refFiles.at(0) == QStringLiteral("src/main.c")
                    && im.granularity == QStringLiteral("lexical-file-level")
                    && im.capped() && im.refFilesCapped && !im.impactedCapped);
        }
        {
            const GraphInsight::Impact bad = GraphInsight::parseImpact(QJsonObject());
            check(log, "图谱三件套：影响面契约形状不对时报错", !bad.ok && !bad.error.isEmpty());
        }
    }

    // ── 引擎自检（doctor）与进度报告（report）──
    // 判据盯三处「错得毫无声响」的口径：
    //   ① 「发现问题」≠「命令失败」：引擎 doctor 有问题时**退出码是 1**，
    //      但 stdout 仍是合法 JSON —— 报告有效 ≠ 一切正常。
    //   ② `result` 是**自由文本**（"OK"/"1 个失效"/"无"/"项目外"/"未创建"），
    //      按 `result == "OK"` 判健康会把「注册项目 1 个」误报成故障。
    //   ③ 引擎没发 `problems` 键时**不回落成 0**（那会把「没说」说成「没事」）。
    {
        // 正常载荷（真引擎 2026-10-19 实测形态）
        const EngineDoctor::Report clean = EngineDoctor::parse(JO(R"JSON({
  "checks": [
    {"check": "git", "result": "OK", "detail": "git version 2.39.5"},
    {"check": "数据目录", "result": "OK", "detail": "/home/u/.deepgit"},
    {"check": "注册项目", "result": "0", "detail": "用 `moongit scan` 添加"},
    {"check": "路径有效", "result": "OK", "detail": ""},
    {"check": "当前目录", "result": "项目外", "detail": "/home/u/code"},
    {"check": "临时残留", "result": "无", "detail": "无"}
  ],
  "problems": 0
})JSON"));
        check(log, "引擎自检：载荷解析（检查项逐条 + 引擎口径的问题数）",
            clean.ok && clean.checks.size() == 6 && clean.problems == 0
                && clean.checks.at(0).name == QStringLiteral("git")
                && clean.checks.at(0).result == QStringLiteral("OK")
                && clean.checks.at(0).detail == QStringLiteral("git version 2.39.5")
                && clean.checks.at(2).result == QStringLiteral("0"));
        // ② 自由文本：「注册项目 0」「临时残留 无」「当前目录 项目外」都不是 "OK"，
        //    但引擎的问题数是 0 —— 客户端若自己数「非 OK 的项」就会误报故障。
        check(log, "引擎自检：result 是自由文本（result != \"OK\" 不等于有问题）",
            !clean.hasProblems() && EngineDoctor::toneOf(clean) == EngineDoctor::Tone::ok);
        check(log, "引擎自检：摘要按引擎口径（不是按「非 OK 的项数」）",
            EngineDoctor::summary(clean) == QStringLiteral("6 项检查 · 0 个问题"));

        // 真有问题的一档：引擎 problems=1，**退出码是 1**（自检必须能失败）
        const EngineDoctor::Report bad = EngineDoctor::parse(JO(R"JSON({
  "checks": [
    {"check": "git", "result": "OK", "detail": "git version 2.39.5"},
    {"check": "路径有效", "result": "1 个失效", "detail": "atlas"}
  ],
  "problems": 1
})JSON"));
        check(log, "引擎自检：有问题时仍是一份**有效报告**（退出码 1 ≠ 报告读不出来）",
            bad.ok && bad.hasProblems() && bad.problems == 1
                && EngineDoctor::toneOf(bad) == EngineDoctor::Tone::problem
                && EngineDoctor::summary(bad) == QStringLiteral("2 项检查 · 1 个问题"));

        // ③ 缺 problems 键 → **不回落成 0**（回落会把「引擎没说」说成「没问题」）
        const EngineDoctor::Report noCount = EngineDoctor::parse(JO(R"JSON({
  "checks": [{"check": "git", "result": "OK", "detail": "git version 2.39.5"}]
})JSON"));
        check(log, "引擎自检：缺 problems 键 → 记为「未知」而不是 0（缺字段不回落成 0）",
            noCount.ok && noCount.problemsUnknown() && noCount.problems == -1
                && !noCount.hasProblems()
                && EngineDoctor::toneOf(noCount) == EngineDoctor::Tone::unknown
                && EngineDoctor::summary(noCount).contains(QStringLiteral("问题数未知")));

        // 契约形状不对（缺 checks 键）→ 报错，不当空报告放行
        const EngineDoctor::Report broken = EngineDoctor::parse(JO(R"JSON({"problems": 0})JSON"));
        check(log, "引擎自检：缺 checks 键 → 报错（不当成「0 项检查 · 没问题」）",
            !broken.ok && !broken.error.isEmpty()
                && EngineDoctor::toneOf(broken) == EngineDoctor::Tone::unreadable);

        // 检查项行文：详情为空时不留悬空的「·」
        const EngineDoctor::Check noDetail { QStringLiteral("路径有效"), QStringLiteral("OK"),
            QString() };
        const EngineDoctor::Check withDetail { QStringLiteral("git"), QStringLiteral("OK"),
            QStringLiteral("git version 2.39.5") };
        check(log, "引擎自检：检查项行文（空详情不留悬空分隔符）",
            EngineDoctor::checkLine(noDetail) == QStringLiteral("路径有效 · OK")
                && EngineDoctor::checkLine(withDetail)
                    == QStringLiteral("git · OK · git version 2.39.5"));

        // ── 进度报告回执（引擎 report 是**回执型命令**：stdout 是人话）──
        // 引擎真实回执：「✓ 报告已生成：/abs/path/report-2026-10-19-1792422583649.md（1 个项目）」
        // ⚠ 引擎**不认 NO_COLOR**（实测设了照样带色码）→ 显示前必须剥 ANSI。
        const QString receiptText
            = QStringLiteral("\x1b[32m✓\x1b[0m 报告已生成：/home/u/.deepgit/reports/report-1.md（1 个项目）");
        const QString plainText = ArchReceipt::plain(receiptText);
        check(log, "报告回执：剥掉 ANSI 颜色码（引擎不认 NO_COLOR，裸塞会显示成「[32m✓[0m」）",
            !plainText.contains(QStringLiteral("\x1b")) && !plainText.contains(QStringLiteral("[32m"))
                && plainText.startsWith(QStringLiteral("✓ 报告已生成：")));
        check(log, "报告回执：抽出 .md 落盘绝对路径（「打开报告」入口全靠它）",
            ArchReceipt::filePath(plainText, QStringLiteral(".md"))
                == QStringLiteral("/home/u/.deepgit/reports/report-1.md"));
        // 相对路径不认：打不开的路径等于坏按钮
        check(log, "报告回执：相对路径不抽（打不开的路径等于坏按钮）",
            ArchReceipt::filePath(QStringLiteral("报告已生成：reports/report-1.md"),
                QStringLiteral(".md"))
                .isEmpty());
        // 后缀不匹配不抽：.html 的路径不能当成报告路径
        check(log, "报告回执：后缀不对不抽（.html 不能当报告路径）",
            ArchReceipt::filePath(QStringLiteral("已重绘：/tmp/x/arch.html"), QStringLiteral(".md"))
                .isEmpty());
        // ⚠ 后缀不同的两次抽取**互不污染**。这条钉的是一类「只有第一次对」的错误：
        //   正则若被函数级 static 焊死成第一次的后缀，之后传 .md 也按 .html 找 ——
        //   调用点与参数看着全对，只有行为不对（报告路径永远抽不到）。
        //   所以两个后缀都抽一遍，且**顺序换过来也成立**。
        check(log, "报告回执：后缀不同的两次抽取互不污染（.html 与 .md 各抽各的）",
            ArchReceipt::filePath(QStringLiteral("已重绘：/tmp/x/arch.html"), QStringLiteral(".html"))
                    == QStringLiteral("/tmp/x/arch.html")
                && ArchReceipt::filePath(
                       QStringLiteral("报告已生成：/tmp/x/report-1.md"), QStringLiteral(".md"))
                    == QStringLiteral("/tmp/x/report-1.md")
                && ArchReceipt::filePath(QStringLiteral("已重绘：/tmp/x/arch.html"), QStringLiteral(".md"))
                    .isEmpty());
    }

    // ── 引擎配置（config list / config set）──
    // 判据盯三处「错得毫无声响」的口径：
    //   ① **`backupKeep: 0` 是合法值**（明确不保留备份），**不是**「引擎没发这个键」。
    //      拿 0 当缺失 → 界面把「明确不要备份」说成「不知道留几份」，意思完全相反。
    //   ② **引擎的 `ai` 恒为空对象**（引擎 AI 无关）→ 客户端不许从引擎读 AI 设置
    //      （与客户端自己的 app/Settings 形成两个真相源）。
    //   ③ **可写键只有四个** —— 界面给的键必须是引擎认的那些。
    {
        const EngineConfig::Config c = EngineConfig::parse(JO(R"JSON({
  "version": 1,
  "language": "zh",
  "roots": ["/home/u/dev"],
  "ai": {},
  "update": {
    "docs": ["README.md", "AGENTS.md", "CLAUDE.md"],
    "agentDocCandidates": ["AGENTS.md", "AGENT.md", "CLAUDE.md"],
    "backupKeep": 20,
    "maxShallowBranches": 6
  }
})JSON"));
        check(log, "引擎配置：载荷解析（版本 / 语言 / 扫描根 / 受管文档 / 备份份数 / 分支上限）",
            c.ok && c.version == 1 && c.language == QStringLiteral("zh")
                && c.roots.size() == 1 && c.roots.at(0) == QStringLiteral("/home/u/dev")
                && c.docs.size() == 3 && c.docs.at(0) == QStringLiteral("README.md")
                && c.docs.at(2) == QStringLiteral("CLAUDE.md")
                && c.agentDocCandidates.size() == 3
                && c.hasBackupKeep() && c.backupKeep == 20
                && c.hasMaxShallowBranches() && c.maxShallowBranches == 6);
        check(log, "引擎配置：摘要只报有值的项（缺项不占位）",
            EngineConfig::summary(c) == QStringLiteral("语言 zh · 分支上限 6 · 备份 20 份"));
        {
            // 缺 update 键 → 契约形状不对 → 报错，不当空配置放行
            const EngineConfig::Config bad
                = EngineConfig::parse(JO(R"JSON({"version":1,"language":"zh","roots":[],"ai":{}})JSON"));
            check(log, "引擎配置：缺 update 键时报错（不当成「什么都没设」）",
                !bad.ok && !bad.error.isEmpty());
        }
        {
            // ⚠ 缺键 → -1（未知），**不回落成 0**
            const EngineConfig::Config partial = EngineConfig::parse(JO(R"JSON({
  "version": 1, "language": "zh", "roots": [], "ai": {},
  "update": {"docs": ["README.md"], "agentDocCandidates": []}
})JSON"));
            check(log, "引擎配置：缺 backupKeep/maxShallowBranches → 记为「未知」而不是 0",
                partial.ok && !partial.hasBackupKeep() && partial.backupKeep == -1
                    && !partial.hasMaxShallowBranches() && partial.maxShallowBranches == -1);
        }
        {
            // ⚠ 0 是**合法值**（明确不保留备份 / 不记任何分支）——
            //    拿 0 当缺失会把两件相反的事说成同一句。
            const EngineConfig::Config zero = EngineConfig::parse(JO(R"JSON({
  "version": 1, "language": "zh", "roots": [], "ai": {},
  "update": {"docs": [], "agentDocCandidates": [], "backupKeep": 0, "maxShallowBranches": 0}
})JSON"));
            check(log, "引擎配置：0 是合法值（backupKeep: 0 不被当成「没发」）",
                zero.ok && zero.hasBackupKeep() && zero.backupKeep == 0
                    && zero.hasMaxShallowBranches() && zero.maxShallowBranches == 0);
        }
        check(log, "引擎配置：可写键恰好四个且与引擎一致（界面不能给引擎不认的键）",
            EngineConfig::writableKeys().size() == 4
                && EngineConfig::isWritable(QStringLiteral("language"))
                && EngineConfig::isWritable(QStringLiteral("update.backupKeep"))
                && EngineConfig::isWritable(QStringLiteral("update.maxShallowBranches"))
                && EngineConfig::isWritable(QStringLiteral("roots"))
                && !EngineConfig::isWritable(QStringLiteral("update.docs"))
                && !EngineConfig::isWritable(QStringLiteral("ai")));
    }

    // ── 持久化代码索引的状态（index overview / index update）──
    // 判据盯三处「错得毫无声响」：
    //   ① **「已最新」≠「已更新」**：源文件没动时引擎回 fresh: true，
    //      这次**什么都没重建** —— 界面若说成「更新好了」就是骗人。
    //   ② **`rebuilt` 在 fresh 时引擎不发这个键** —— 按 false 读会把
    //      「这次没重建」说成「从来没重建过」（后者是历史事实）。
    //   ③ **缺字段不回落成 0**：`nodes: 0`（空索引）与「引擎没发 nodes」
    //      （契约漂移）是两件事。
    {
        const IndexStatus::Overview ov = IndexStatus::parseOverview(JO(R"JSON({
  "project": "atlas",
  "updateCount": 1,
  "generatedAt": "2026-10-19T23:38:51.268173877+08:00",
  "selfHealed": false,
  "nodes": 3,
  "edges": 1,
  "files": 1,
  "byKind": {"func": 3},
  "probe": {"files": 1, "bytes": 103, "maxMtime": 1792424331000}
})JSON"));
        check(log, "索引状态：概览解析（代数 / 节点 / 边 / 文件 / 按种类 / 探针）",
            ov.ok && ov.project == QStringLiteral("atlas") && ov.hasUpdateCount()
                && ov.updateCount == 1 && ov.hasNodes() && ov.nodes == 3
                && ov.hasEdges() && ov.edges == 1 && ov.hasFiles() && ov.files == 1
                && ov.byKind.value(QStringLiteral("func")) == 3
                && ov.probeFiles == 1 && ov.probeBytes == 103
                && ov.probeMaxMtime == 1792424331000
                && ov.generatedAt.startsWith(QStringLiteral("2026-10-19T23:38:51")));
        check(log, "索引状态：概览摘要（缺项不占位）",
            IndexStatus::summary(ov)
                == QStringLiteral("索引：3 符号 · 1 边 · 1 文件 · 第 1 代"));
        {
            // 缺 nodes 键 → 契约漂移 → 报错，不当空索引放行
            const IndexStatus::Overview bad = IndexStatus::parseOverview(
                JO(R"JSON({"project":"atlas","updateCount":0,"edges":0,"files":0})JSON"));
            check(log, "索引状态：缺 nodes 键时报错（不当成「0 符号的空索引」）",
                !bad.ok && !bad.error.isEmpty());
        }
        {
            // ⚠ 缺键 → -1（未知），不回落成 0
            const IndexStatus::Overview partial = IndexStatus::parseOverview(
                JO(R"JSON({"project":"atlas","nodes":0,"edges":0,"files":0})JSON"));
            check(log, "索引状态：缺 updateCount 记为「未知」而不是 0",
                partial.ok && !partial.hasUpdateCount() && partial.updateCount == -1
                    && !partial.selfHealedPresent);
        }
        {
            // ⚠ edges / files 缺失 → -1（未知），不回落成 0
            const IndexStatus::Overview noCounts = IndexStatus::parseOverview(
                JO(R"JSON({"project":"atlas","nodes":1})JSON"));
            check(log, "索引状态：缺 edges/files 键记为「未知」而不是 0",
                noCounts.ok && noCounts.hasNodes() && noCounts.nodes == 1
                    && !noCounts.hasEdges() && noCounts.edges == -1
                    && !noCounts.hasFiles() && noCounts.files == -1);
        }
        {
            // ⚠ 探针字段缺失 → -1（未知），不回落成 0
            const IndexStatus::Overview noProbe = IndexStatus::parseOverview(
                JO(R"JSON({"project":"atlas","updateCount":0,"nodes":1,"edges":0,"files":1,
  "probe":{"files":1}})JSON"));
            check(log, "索引状态：缺探针字段记为「未知」而不是 0",
                noProbe.ok && noProbe.probeFiles == 1 && noProbe.probeBytes == -1
                    && noProbe.probeMaxMtime == -1);
        }
        {
            // ⚠ 0 是合法值（空索引），不被当成「没发」
            const IndexStatus::Overview empty = IndexStatus::parseOverview(
                JO(R"JSON({"project":"atlas","updateCount":0,"nodes":0,"edges":0,"files":0})JSON"));
            check(log, "索引状态：0 是合法值（空索引不被当成「没发」）",
                empty.ok && empty.hasNodes() && empty.nodes == 0
                    && empty.hasUpdateCount() && empty.updateCount == 0);
        }
        {
            // 增量更新：源文件没动 → fresh: true，**引擎不发 rebuilt 键**
            const IndexStatus::UpdateResult fresh = IndexStatus::parseUpdate(
                JO(R"JSON({"project":"atlas","fresh":true,"updateCount":1,
  "probe":{"files":1,"bytes":103,"maxMtime":1792424331000}})JSON"));
            check(log, "索引更新：fresh 时引擎不发 rebuilt 键（有 present 标志）",
                fresh.ok && fresh.fresh && !fresh.rebuiltPresent && fresh.hasUpdateCount()
                    && fresh.updateCount == 1 && fresh.indexJsonPath.isEmpty());
        }
        {
            // 增量更新：源文件变了 → fresh: false + rebuilt: true + 落盘路径
            const IndexStatus::UpdateResult rebuilt = IndexStatus::parseUpdate(
                JO(R"JSON({"project":"atlas","fresh":false,"rebuilt":true,"updateCount":1,
  "generatedAt":"2026-10-19T23:38:51.268173877+08:00",
  "probe":{"files":1,"bytes":103,"maxMtime":1792424331000},
  "indexJson":"/tmp/x/store/p_1/index.json"})JSON"));
            check(log, "索引更新：源文件变了 → fresh 假 / rebuilt 真 / 有落盘路径",
                rebuilt.ok && !rebuilt.fresh && rebuilt.rebuilt && rebuilt.rebuiltPresent
                    && rebuilt.indexJsonPath
                        == QStringLiteral("/tmp/x/store/p_1/index.json"));
        }
        {
            // 缺 fresh 键 → 契约漂移 → 报错
            const IndexStatus::UpdateResult bad = IndexStatus::parseUpdate(
                JO(R"JSON({"project":"atlas","updateCount":1})JSON"));
            check(log, "索引更新：缺 fresh 键时报错（契约漂移不放过）",
                !bad.ok && !bad.error.isEmpty());
        }
    }

    // ── Canvas font 简写解析（批 M：性能审计 + pt 单位语义修正）──
    // 判据盯两处：
    //   ① **单位口径**：浏览器 CSS font 简写认 `px` 与 `pt` **两者**。
    //      早期解析器只认 px，把 "11pt" 整段当**字体族名**吞掉 ——
    //      字号**根本没设上**（渲染成默认字号），界面上看着「字号不太对」，
    //      但没人知道是单位没被识别。
    //   ② **不认的单位不当成别的单位**（"11em" 不能悄悄按 11px 算）。
    {
        const CanvasFont::Spec card = CanvasFont::parse(QStringLiteral("11pt sans-serif"));
        check(log, "Canvas 字体：pt 单位被识别（点字号，不是被当成字体族名吞掉）",
            card.pixelSize == 0 && qFuzzyCompare(card.pointSize, 11.0)
                && card.families.size() == 1
                && card.families.at(0) == QStringLiteral("sans-serif"));
        const CanvasFont::Spec px = CanvasFont::parse(QStringLiteral("11px sans-serif"));
        check(log, "Canvas 字体：px 单位被识别（像素字号）",
            px.pixelSize == 11 && px.pointSize == 0
                && px.families.size() == 1
                && px.families.at(0) == QStringLiteral("sans-serif"));
        const CanvasFont::Spec bold = CanvasFont::parse(QStringLiteral("600 12px"));
        check(log, "Canvas 字体：字重 + 像素字号（family 留空 = 保留接收端自身字体族）",
            bold.hasWeight && bold.weight == 600 && bold.pixelSize == 12
                && bold.pointSize == 0 && bold.families.isEmpty());
        const CanvasFont::Spec noWeight = CanvasFont::parse(QStringLiteral("12px"));
        check(log, "Canvas 字体：缺字重时不误认（未显式给 = 没有字重）",
            !noWeight.hasWeight && noWeight.weight == 400 && noWeight.pixelSize == 12);
        const CanvasFont::Spec fam = CanvasFont::parse(
            QStringLiteral("600 12px Noto Sans CJK SC"));
        check(log, "Canvas 字体：多段字体族按空格分开",
            fam.families.size() == 4 && fam.families.at(0) == QStringLiteral("Noto")
                && fam.families.at(3) == QStringLiteral("SC"));
        const CanvasFont::Spec bogus = CanvasFont::parse(QStringLiteral("11em serif"));
        check(log, "Canvas 字体：不认的单位**不当成别的单位**（11em ≠ 11px）",
            bogus.pixelSize == 0 && bogus.pointSize == 0
                && bogus.families.size() == 2
                && bogus.families.at(0) == QStringLiteral("11em"));
        // ⚠ 不认识的段**不被当成别的段**：「12」（无单位）既不是字重（12 < 100）
        //   也不是字号（没单位）→ 不当字重吃掉。错实现若把字重范围放宽到
        //   「>= 0」，这里就会 hasWeight=true —— 分叉点就在这一条。
        const CanvasFont::Spec bare = CanvasFont::parse(QStringLiteral("12"));
        check(log, "Canvas 字体：不认识的段不被当成字重（\"12\" 无单位 → 不是字重）",
            !bare.hasWeight && bare.weight == 400 && bare.pixelSize == 0
                && bare.pointSize == 0);
        const CanvasFont::Spec empty = CanvasFont::parse(QString());
        check(log, "Canvas 字体：空串不崩（不设字号、不设字重）",
            empty.pixelSize == 0 && empty.pointSize == 0 && !empty.hasWeight
                && empty.families.isEmpty());
    }

    // ── 设计系统散值（批 N：存量清零，上限降到 0）──
    // 散值「清零」本身由 D2 门（scripts/ci-d2.sh，源扫描）保证；
    // 这里钉的是**收口后的 token 值** —— 改 token 必须同步改这里的期望值，
    // 而「期望值随手改」是 token 纪律最常见的破口。
    {
        check(log, "设计系统：QSS 字号常量（徽章 11px / 等宽 13px）",
            DS::FontPx::badge == 11 && DS::FontPx::code == 13);
        check(log, "设计系统：Markdown 标题档位（h1/h2/h3 = 22/18/14，正文 11）",
            DS::MD_H1 == 22 && DS::MD_H2 == 18 && DS::MD_H3 == 14 && DS::MD_BODY == 11);
        // alpha 与 RGB 同权：0.18 以前是裸字面量散在 AgentDialog，色进了 DS 而
        // 透明度没进 = 同一个「18% 强调底」散成 N 个真相源。
        check(log, "设计系统：强调底透明度（18%）且 rgba 由 token 拼出",
            DS::Alpha::accentTint == 0.18
                && DS::accentTintRgba(QColor(0, 0, 255)) == QStringLiteral("rgba(0, 0, 255, 0.18)"));
        check(log, "设计系统：底轨遮罩（中性灰 40/255）",
            DS::trackMask() == QColor(128, 128, 128, 40));
        // 热力图画布色：原来散在 HeatmapWidget 的 7 处，收进 HeatLayout 后
        // 「改一处配色」不用翻 7 个地方。
        check(log, "设计系统：热力图画布配色（卡底/文字/标签/注释/描边五档）",
            HeatLayout::Canvas::cardBase() == QColor(19, 31, 48)
                && HeatLayout::Canvas::cardText() == QColor(235, 240, 248)
                && HeatLayout::Canvas::cardLabel() == QColor(190, 200, 215)
                && HeatLayout::Canvas::cardNote() == QColor(200, 210, 225)
                && HeatLayout::Canvas::stroke() == QColor(255, 255, 255));
        // 批 O：状态语义色**单一真相源** —— DS::semColor 必须转发 logic/SemColors，
        // 否则同一个语义色又会有两份定义（这正是批 N 照出来的问题）。
        check(log, "设计系统：状态语义色单一真相源（DS::semColor 转发 SemColors）",
            DS::semColor(DS::SemColor::shallow) == SemColors::shallow()
                && DS::semColor(DS::SemColor::deep) == SemColors::deep()
                && DS::semColor(DS::SemColor::ai) == SemColors::ai()
                && DS::semColor(DS::SemColor::orange) == SemColors::orange()
                && DS::semColor(DS::SemColor::red) == SemColors::red()
                && DS::semColor(DS::SemColor::yellow) == SemColors::yellow()
                && DS::semColor(DS::SemColor::gray) == SemColors::gray()
                && DS::semColor(DS::SemColor::stale) == SemColors::stale());
        // 陈旧红（#EF4444）与危险红（#DC2626）是**两档不同的红**，不许合并。
        check(log, "设计系统：陈旧红与危险红是两档（stale #EF4444 / red #DC2626）",
            SemColors::stale() == QColor(0xEF, 0x44, 0x44)
                && SemColors::red() == QColor(0xDC, 0x26, 0x26)
                && SemColors::stale() != SemColors::red());
        check(log, "设计系统：固定色（图标兜底灰 / 托盘强调蓝 / 托盘条底轨）",
            FixedColors::iconFallback() == QColor(0x88, 0x88, 0x88)
                && FixedColors::trayAccent() == QColor(0x1E, 0x6F, 0xEB)
                && FixedColors::trayBarTrack() == QColor(128, 128, 128, 60));
        // 判定层（logic/Derived）必须与唯一出处同源 —— 判定层不依赖 ui 层，
        // 所以它**只能**从 logic/SemColors 取色。
        check(log, "设计系统：判定层状态色与唯一出处同源（liveness/branch/stat）",
            Derived::livenessColor(Liveness::recent) == SemColors::shallow()
                && Derived::livenessColor(Liveness::needsAction) == SemColors::orange()
                && Derived::livenessColor(Liveness::engineStale) == SemColors::stale()
                && Derived::branchStatusColor(QStringLiteral("active")) == SemColors::shallow()
                && Derived::branchStatusColor(QStringLiteral("stale")) == SemColors::stale()
                && Derived::statTint(5) == SemColors::orange());
    }

    // ── 引擎获取（GitHub Releases 下载）判定层 ──
    {
        const QByteArray withLinux = R"JSON({"tag_name":"v0.2.0","assets":[
          {"name":"moongit-v0.2.0-darwin-arm64.tar.gz","browser_download_url":"https://example.invalid/d.tar.gz","digest":"sha256:6d6e7982068b09521d3f294bd622e07effe93ac586e0ddcbdb5d1f52441cdcb3","size":6463656},
          {"name":"moongit-v0.2.0-linux-x64.tar.gz","browser_download_url":"https://example.invalid/l.tar.gz","digest":"sha256:aaaa0000bbbb1111cccc2222dddd3333eeee4444ffff5555aaaa6666bbbb7777","size":7000000}]})JSON";
        const EngineDownload::Release r = EngineDownload::parseRelease(withLinux);
        check(log, "引擎下载：能从 release 载荷挑出本平台资产（linux-x64）",
            r.parsed && r.tag == QLatin1String("v0.2.0") && r.asset.present
                && r.asset.name == QLatin1String("moongit-v0.2.0-linux-x64.tar.gz")
                && r.asset.url == QLatin1String("https://example.invalid/l.tar.gz")
                && r.asset.size == 7000000 && r.available.size() == 2);
        // ⚠ **「本平台没有资产」不是错误** —— 要能说清「到底有什么」，而不是笼统报失败
        const QByteArray darwinOnly = R"JSON({"tag_name":"v0.1.0","assets":[
          {"name":"moongit-v0.1.0-darwin-arm64.tar.gz","browser_download_url":"https://example.invalid/d.tar.gz","digest":"sha256:6d6e7982068b09521d3f294bd622e07effe93ac586e0ddcbdb5d1f52441cdcb3","size":6463656}]})JSON";
        const EngineDownload::Release r2 = EngineDownload::parseRelease(darwinOnly);
        check(log, "引擎下载：本 release 没有 Linux 资产时能说清「有什么」",
            r2.parsed && !r2.asset.present && r2.available.size() == 1
                && r2.available.first() == QLatin1String("moongit-v0.1.0-darwin-arm64.tar.gz"));
        // 载荷读不懂 ≠ 没有资产：两者要说清的是不同的话
        const EngineDownload::Release r3 = EngineDownload::parseRelease("<html>404</html>");
        check(log, "引擎下载：载荷读不懂时报「读不懂」而不是「没有资产」",
            !r3.parsed && !r3.asset.present && r3.available.isEmpty());
        check(log, "引擎下载：资产名匹配（平台后缀 + 必须是 tar.gz 包）",
            EngineDownload::assetMatches(QStringLiteral("moongit-v0.2.0-linux-x64.tar.gz"),
                QStringLiteral("linux-x64"))
                && !EngineDownload::assetMatches(QStringLiteral("moongit-v0.2.0-darwin-arm64.tar.gz"),
                    QStringLiteral("linux-x64"))
                && !EngineDownload::assetMatches(QStringLiteral("moongit-v0.2.0-linux-x64.zip"),
                    QStringLiteral("linux-x64")));
        // sha256 三态：对 / 错 / **无校验和**（无校验和 ≠ 校验通过，上层要说「未校验」）
        const QByteArray payload("hello");
        const QString sha = QString::fromLatin1(
            QCryptographicHash::hash(payload, QCryptographicHash::Sha256).toHex());
        check(log, "引擎下载：sha256 校验（对/错/无校验和三态）",
            EngineDownload::digestMatches(QStringLiteral("sha256:") + sha, payload)
                && !EngineDownload::digestMatches(QStringLiteral("sha256:") + sha, QByteArray("hellp"))
                && EngineDownload::digestMatches(QString(), payload)
                && !EngineDownload::digestMatches(QStringLiteral("sha256:abc"), payload));
        check(log, "引擎下载：落盘在用户目录（不碰系统目录、不要 sudo）",
            // ⚠ 判据要盯「**在用户目录下**」，不是「不以 / 开头」——
            //   用户目录路径本身就是绝对路径（/home/xxx/...），盯「相对路径」是盯错了。
            EngineDownload::installDir().startsWith(QDir::homePath())
                && !EngineDownload::installDir().startsWith(QLatin1String("/usr"))
                && !EngineDownload::installDir().startsWith(QLatin1String("/opt"))
                && !EngineDownload::installDir().startsWith(QLatin1String("/etc"))
                && EngineDownload::installedBin().endsWith(QLatin1String("/moongit"))
                && EngineDownload::packagedBinName() == QLatin1String("moongit-cli"));
        // 「失败要说清是哪一种」的可验证形式：七种失败各说各的，不许都叫「下载失败」
        const QStringList msgs = {
            EngineDownload::stageMessage(EngineDownload::Stage::networkUnreachable, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::releaseUnreadable, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::noPlatformAsset, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::downloadFailed, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::digestMismatch, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::extractFailed, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::probeFailed, QStringLiteral("x")),
        };
        const QSet<QString> uniq(msgs.begin(), msgs.end());
        check(log, "引擎下载：七种失败各说各的（不许都叫「下载失败」）",
            msgs.size() == 7 && uniq.size() == 7 && !msgs.isEmpty());
    }

    log << QStringLiteral("──── selfcheck: %1 passed, %2 failed ────").arg(g_pass).arg(g_fail);
    return g_fail;
}
