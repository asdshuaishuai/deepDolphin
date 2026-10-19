#include "SelfCheck.h"
#include "../logic/DashFilter.h"
#include "../logic/Derived.h"
#include "../logic/DocumentIntegrity.h"
#include "../logic/GraphToken.h"
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
              "module:b":{"label":"B","nodeTheme":{"b":"cols.0"},"shapes":[],"particles":[],"hits":[],"edgesDropped":0},
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
                      "edgesDropped":3}},
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
                *scene, v, true, SceneRender::Viewport { 1.0, 0.0, 0.0 }, 800, 600, 1000.0, sink);
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
            SceneRender::render(*scene, v, true, SceneRender::Viewport { 1.0, 0.0, 0.0 }, 800, 600,
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
    }

    log << QStringLiteral("──── selfcheck: %1 passed, %2 failed ────").arg(g_pass).arg(g_fail);
    return g_fail;
}
