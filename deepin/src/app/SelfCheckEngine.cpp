// SelfCheckEngine.cpp — `--selfcheck` 分片：**图谱三件套 + 引擎获取 + 通知 + 引擎钩子**。
//
// ⚠ 为什么拆出来（批 AJ · M4a）：`SelfCheck.cpp` 原本是**一个 3800 多行的函数**
//   ⇒ 拆成多分片；「记一条判据」的实现仍只有一份（`SelfCheckInternal.h`）。
// ⚠ 拆分的验收：**判据条数不许变**（393 条）—— ci.sh 的 SC_MIN 盯着。
#include "SelfCheckInternal.h"
#include "../logic/CanvasFont.h"
#include "../logic/SemColors.h"
#include <QTemporaryDir>
#include "../logic/ArchReceipt.h"
#include "../logic/Derived.h"
#include "../logic/EngineConfig.h"
#include "../ui/DesignTokens.h"
#include <QDir>
#include <QFile>
#include "../logic/EngineDoctor.h"
#include "../logic/EngineDownload.h"
#include "../logic/EngineHook.h"
#include "../logic/GraphInsight.h"
#include "../logic/HeatLayout.h"
#include "../logic/IndexStatus.h"
#include "../logic/Notifications.h"
#include "../logic/SceneRender.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QString>
#include <QStringList>

#include "SelfCheckInternal.h"
#include "../logic/CanvasFont.h"
#include "../logic/EngineDoctor.h"
#include "../logic/EngineDownload.h"
#include "../logic/EngineHook.h"
#include "../logic/GraphInsight.h"
#include "../logic/HeatLayout.h"
#include "../logic/IndexStatus.h"
#include "../logic/Notifications.h"
#include "../logic/SceneRender.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QString>
#include <QStringList>

using SelfCheckInternal::check;
using SelfCheckInternal::J;
using SelfCheckInternal::JO;

namespace SelfCheckInternal {

void checkEngine(QStringList &log)
{
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
                && DS::semColor(DS::SemColor::gray) == SemColors::gray());
        // 陈旧红（#EF4444）与危险红（#DC2626）是**两档不同的红**，不许合并。
        // ⚠ 批 R：陈旧红**只服务托盘**（托盘图标无文字，颜色是它区分档位的唯一手段）。
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
        // 【批 R · 跨端取值对齐】下面的取值即定案（对齐 mac 活代码，见台账 D.1）：
        //   静默(停滞/久未更新)与不适用(非 git)→ 灰；读不出来(unknown)→ 红；
        //   分支 stale → 橙。
        check(log, "设计系统：判定层状态色与唯一出处同源（liveness/branch/stat）",
            Derived::livenessColor(Liveness::recent) == SemColors::shallow()
                && Derived::livenessColor(Liveness::needsAction) == SemColors::orange()
                && Derived::livenessColor(Liveness::engineStale) == SemColors::gray()
                && Derived::livenessColor(Liveness::quiet) == SemColors::gray()
                && Derived::livenessColor(Liveness::notGit) == SemColors::gray()
                && Derived::livenessColor(Liveness::unreadable) == SemColors::red()
                && Derived::livenessColor(Liveness::unknown) == SemColors::red()
                && Derived::branchStatusColor(QStringLiteral("active")) == SemColors::shallow()
                && Derived::branchStatusColor(QStringLiteral("idle")) == SemColors::yellow()
                && Derived::branchStatusColor(QStringLiteral("stale")) == SemColors::orange()
                && Derived::branchStatusColor(QStringLiteral("merged")) == SemColors::deep()
                && Derived::statTint(5) == SemColors::orange());
        // 陈旧红是**托盘专用**档：判定层（UI 层语义）一律不挂它 ——
        // 它与危险红 #DC2626 肉眼几乎分不出，UI 层两个红同时出现 = 读者分不出。
        check(log, "设计系统：陈旧红是托盘专用档（判定层不挂这一档）",
            Derived::livenessColor(Liveness::engineStale) != SemColors::stale()
                && Derived::livenessColor(Liveness::quiet) != SemColors::stale()
                && Derived::livenessColor(Liveness::notGit) != SemColors::stale()
                && Derived::livenessColor(Liveness::unknown) != SemColors::stale()
                && Derived::branchStatusColor(QStringLiteral("stale")) != SemColors::stale()
                && Derived::statTint(5) != SemColors::stale());
        // 档位清单（色卡样张与判据都从这里取）：份数与内容钉死 ——
        // 少一档 = 样张少画一格 = 基线里那一格没有 = 又一个空门。
        check(log, "设计系统：档位清单齐全（liveness 7 档 / 分支状态 5 档）",
            Derived::livenessKinds().size() == 7
                && Derived::branchStatusKinds().size() == 5
                && Derived::branchStatusKinds().contains(QStringLiteral("active"))
                && Derived::branchStatusKinds().contains(QStringLiteral("idle"))
                && Derived::branchStatusKinds().contains(QStringLiteral("stale"))
                && Derived::branchStatusKinds().contains(QStringLiteral("merged"))
                && Derived::branchStatusKinds().contains(QStringLiteral("unknown")));
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
                // ⚠ 发布包**根部**的可执行文件是 `moongit`（启动器），**不是** `moongit-cli`——
                //   真二进制在包内 `bin/moongit-cli`，启动器按自身所在目录去找它。
                //   拿错名字 = 落盘后启动器 exec 不到东西 = 装了个跑不起来的引擎。
                && EngineDownload::packagedBinName() == QLatin1String("moongit")
                // ⚠ 整包落盘：bin/ 与 runtime/ 必须**一起**落（少了 runtime 就是
                //   Library not loaded，少了 bin 就是 exec 不到）⇒ 只落一个文件是不合格的。
                && EngineDownload::packagedDirs().contains(QStringLiteral("bin"))
                && EngineDownload::packagedDirs().contains(QStringLiteral("runtime"))
                && EngineDownload::packagedDirs().size() >= 2);
        // 网络韧性：瞬时故障要重试，永久故障不要（实测依据见 logic/EngineDownload.h）。
        // ⚠ 判据盯**两件事**：① 哪些错误算「瞬时」；② 重试有**上限**且退避**递增**。
        //   「不重试」的那些必须被明确排除 —— 否则一个 404 会被重试三遍让用户干等。
        check(log, "引擎下载：可重试的只有瞬时故障（连接被关/超时/未知网络错/服务端 5xx）",
            EngineDownload::isRetryableNetworkError(QNetworkReply::RemoteHostClosedError)
            && EngineDownload::isRetryableNetworkError(QNetworkReply::TimeoutError)
            && EngineDownload::isRetryableNetworkError(QNetworkReply::UnknownNetworkError)
            && EngineDownload::isRetryableNetworkError(QNetworkReply::UnknownServerError)
            // 永久故障**不**重试
            && !EngineDownload::isRetryableNetworkError(QNetworkReply::ContentNotFoundError)
            && !EngineDownload::isRetryableNetworkError(QNetworkReply::HostNotFoundError)
            && !EngineDownload::isRetryableNetworkError(QNetworkReply::ConnectionRefusedError)
            && !EngineDownload::isRetryableNetworkError(QNetworkReply::NoError));
        check(log, "引擎下载：重试有上限且退避递增（不是无限重试、也不是干等）",
            EngineDownload::maxDownloadAttempts() >= 2
            && EngineDownload::maxDownloadAttempts() <= 5
            && EngineDownload::retryDelayMs(1) > 0
            && EngineDownload::retryDelayMs(2) > EngineDownload::retryDelayMs(1)
            && EngineDownload::retryDelayMs(3) > EngineDownload::retryDelayMs(2)
            // 越界输入要**防御**（不能返回 0 造成「立刻重试」的死循环）
            && EngineDownload::retryDelayMs(0) > 0
            && EngineDownload::retryDelayMs(99) > 0);

        // ⚠ **安装必须「旁路构建 + 通过后切换」**（批 AF 修的真 bug）。
        //   原实现是「先删旧引擎 → 再解包 → 最后才探活」⇒ 装到坏包时
        //   **原来能用的引擎被顶替成坏的**（实测 old 0.9.9 → boom），且无法回滚。
        //   判据盯三件事：① 旁路目录**与目标同级**（同文件系统 ⇒ rename 原子）
        //   且**不等于**目标（否则又变成「就地覆盖」）；② 版本解析认得出引擎版本
        //   且**不把仓颉 SDK 版本当引擎版本**；③ 降级要挡、但**版本未知不挡**。
        check(log, "引擎下载：旁路目录与目标同级且互不相同（切换才能原子）",
            EngineDownload::stagingDir(EngineDownload::installDir())
                    != EngineDownload::installDir()
                && EngineDownload::backupDir(EngineDownload::installDir())
                    != EngineDownload::installDir()
                && EngineDownload::stagingDir(EngineDownload::installDir())
                    != EngineDownload::backupDir(EngineDownload::installDir())
                // ⚠ **同父目录**才是同一文件系统 ⇒ rename 才原子
                && QFileInfo(EngineDownload::stagingDir(EngineDownload::installDir()))
                       .absolutePath()
                    == QFileInfo(EngineDownload::installDir()).absolutePath()
                && QFileInfo(EngineDownload::backupDir(EngineDownload::installDir()))
                       .absolutePath()
                    == QFileInfo(EngineDownload::installDir()).absolutePath());
        check(log, "引擎下载：版本解析认得出引擎版本（且不把 SDK 版本当引擎版本）",
            // ⚠ 真实输出形如 `moonGit Engine 0.2.1 (Cangjie 1.0.5 LTS)` ——
            //   括号里的 1.0.5 是**仓颉 SDK** 的版本，不锚定 "Engine" 就会取错。
            EngineDownload::parseEngineVersion(
                    QStringLiteral("moonGit Engine 0.2.1 (Cangjie 1.0.5 LTS)"))
                == QLatin1String("0.2.1")
            && EngineDownload::parseEngineVersion(QStringLiteral("moongit 0.0.0-contract"))
                == QLatin1String("0.0.0")
            // ⚠ 认不出来就是「不知道」——不猜（返回空串）
            && EngineDownload::parseEngineVersion(QStringLiteral("no version here")).isEmpty()
            && EngineDownload::parseEngineVersion(QString()).isEmpty()
            // ⚠⚠ **说「Engine」却给不出版本 ⇒ 不知道（空）**，不许把 SDK 版本顶上来。
            //   这一条是**负控照出来的**：原先实现里有「锚定失败就退回全文第一个 x.y」的
            //   兜底 ⇒ 遇到 `moonGit Engine (Cangjie 1.0.5 LTS)` 会把 SDK 的 1.0.5
            //   当成引擎版本 ⇒ 降级判定会拿 SDK 版本比大小 ⇒ 误挡/误放。
            && EngineDownload::parseEngineVersion(
                    QStringLiteral("moonGit Engine (Cangjie 1.0.5 LTS)")).isEmpty());
        check(log, "引擎下载：版本按数字段比（0.2.10 > 0.2.9，不是字符串比）",
            EngineDownload::compareVersions(QStringLiteral("0.2.10"),
                               QStringLiteral("0.2.9")) > 0
                && EngineDownload::compareVersions(QStringLiteral("0.2.9"),
                               QStringLiteral("0.2.10")) < 0
                && EngineDownload::compareVersions(QStringLiteral("v0.2.1"),
                               QStringLiteral("0.2.1")) == 0
                // 缺失段当 0
                && EngineDownload::compareVersions(QStringLiteral("0.2"),
                               QStringLiteral("0.2.0")) == 0
                && EngineDownload::compareVersions(QStringLiteral("0.2.1"),
                               QStringLiteral("0.2.1")) == 0);
        check(log, "引擎下载：拒绝降级，但版本未知时**不**误挡合法升级",
            EngineDownload::isDowngrade(QStringLiteral("0.2.1"), QStringLiteral("0.2.0"))
                && EngineDownload::isDowngrade(QStringLiteral("0.2.1"), QStringLiteral("0.1.9"))
                && !EngineDownload::isDowngrade(QStringLiteral("0.2.1"),
                                          QStringLiteral("0.2.2"))
                && !EngineDownload::isDowngrade(QStringLiteral("0.2.1"),
                                          QStringLiteral("0.2.1"))
                // ⚠ **任一方版本未知 ⇒ 不判降级**（解析失败不该挡掉一次合法升级）
                && !EngineDownload::isDowngrade(QString(), QStringLiteral("0.2.0"))
                && !EngineDownload::isDowngrade(QStringLiteral("0.2.1"), QString()));
        check(log, "引擎下载：失败时如实说「原引擎还在不在」（三种情形各说各的）",
            EngineDownload::preserveNote(true, true).contains(QStringLiteral("保留"))
                && EngineDownload::preserveNote(false, false).contains(QStringLiteral("未安装"))
                // ⚠ 「本来有」但指纹变了 ⇒ 老实说「状态已变」，别装作没事
                && EngineDownload::preserveNote(true, false).contains(QStringLiteral("改变"))
                && EngineDownload::preserveNote(true, true)
                    != EngineDownload::preserveNote(true, false)
                && EngineDownload::preserveNote(true, true)
                    != EngineDownload::preserveNote(false, false));
        {
            // 「目标目录里原本有没有引擎」是**升级/首装**的分界：
            // 半个文件（上次装崩了）不算「有引擎」——否则失败文案会说错。
            QTemporaryDir probeDir;
            const QString base = probeDir.path() + QStringLiteral("/dd");
            QDir().mkpath(base);
            const QString bin = base + QStringLiteral("/moongit");
            QFile f(bin);
            f.open(QIODevice::WriteOnly);
            f.write("x");
            f.close();
            const bool emptyDir = !EngineDownload::hasInstalledEngine(base);
            QFile::setPermissions(bin,
                QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner | QFile::ReadGroup
                    | QFile::ExeGroup | QFile::ReadOther | QFile::ExeOther);
            check(log, "引擎下载：只有真能跑的引擎才算「已装」（半个文件不算）",
                emptyDir && EngineDownload::hasInstalledEngine(base));
            // ⚠ **指纹**必须能分辨「内容被换了」——
            //   单看「文件还在」证明不了「没被动过」（负控照出「还在但被顶替」）。
            const QString fp1 = EngineDownload::engineFingerprint(base);
            f.open(QIODevice::WriteOnly | QIODevice::Truncate);
            f.write("longer content here");
            f.close();
            const QString fp2 = EngineDownload::engineFingerprint(base);
            check(log, "引擎下载：引擎指纹能分辨「内容被换过」（存在性证明不了没被动过）",
                !fp1.isEmpty() && !fp2.isEmpty() && fp1 != fp2
                    && EngineDownload::engineFingerprint(
                               probeDir.path() + QStringLiteral("/nope"))
                           .isEmpty());
        }

        // 「失败要说清是哪一种」的可验证形式：八种失败各说各的，不许都叫「下载失败」
        const QStringList msgs = {
            EngineDownload::stageMessage(EngineDownload::Stage::networkUnreachable, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::releaseUnreadable, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::noPlatformAsset, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::downloadFailed, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::digestMismatch, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::extractFailed, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::probeFailed, QStringLiteral("x")),
            EngineDownload::stageMessage(EngineDownload::Stage::versionDowngrade, QStringLiteral("x")),
        };
        const QSet<QString> uniq(msgs.begin(), msgs.end());
        check(log, "引擎下载：八种失败各说各的（不许都叫「下载失败」）",
            msgs.size() == 8 && uniq.size() == 8 && !msgs.isEmpty());

        // ── 批 AH：安装指引文案（引擎缺失时用户**唯一**看到的那句话）──
        // ⚠ **旧文案让人去跑 `moonGit/scripts/install.sh`** —— 那是**仓库里**的脚本，
        //   拿 deb 的普通用户根本没有那个仓库 ⇒ 指了一条走不通的路。
        //   判据钉死：指引里不许再出现 install.sh，且必须给得出**可执行**的下一步。
        // ⚠ 判据要与错误实现**分叉**：旧文案含 "install.sh" ⇒ 这里立刻红。
        const QString hint = EngineDownload::installHint();
        check(log, "引擎缺失指引：不再指向走不通的路，且给得出可执行的下一步",
            !hint.isEmpty()
                && !hint.contains(QStringLiteral("install.sh"))
                && hint.contains(QStringLiteral("DEEPGIT_BIN"))
                && hint.contains(QStringLiteral("~/.local/bin")));
        // ⚠ 动作文案必须**齐备**且**互不相同**：
        //   标签/悬停/忙态各说各的（忙态不是标签的复读，否则下载中看不出在动）。
        const QString dLabel = EngineDownload::downloadActionLabel();
        const QString dTip = EngineDownload::downloadActionTooltip();
        const QString dBusy = EngineDownload::downloadBusyLabel();
        check(log, "引擎下载：动作标签/悬停说明/忙态文案齐备且互不相同",
            !dLabel.isEmpty() && !dTip.isEmpty() && !dBusy.isEmpty()
                && dLabel != dBusy && dTip != dLabel && dTip != dBusy);
        // 状态四态（已找到/正在查找/正在下载/没找到）**互不相同**：
        //   撞车 = 两种情况说同一句话 = 用户分不清发生了什么。
        // ⚠ 下载中**优先**于「没找到」：下载期间引擎确实不在，
        //   但说「没找到」会让用户以为按钮没生效。
        const QString stFound = EngineDownload::downloadStatusText(true, false, false);
        const QString stPending = EngineDownload::downloadStatusText(false, true, false);
        const QString stDown = EngineDownload::downloadStatusText(false, false, true);
        const QString stNone = EngineDownload::downloadStatusText(false, false, false);
        check(log, "引擎状态说明：四态互不相同，且下载中不说「没找到」",
            !stFound.isEmpty() && !stPending.isEmpty() && !stDown.isEmpty() && !stNone.isEmpty()
                && stFound != stPending && stFound != stDown && stFound != stNone
                && stPending != stDown && stPending != stNone && stDown != stNone
                && !stDown.contains(QStringLiteral("没有找到"))
                && !stDown.contains(QStringLiteral("正在查找")));
    }

    // ── 通知（显示时长归一 + 顶替规则）判定层 ──
    {
        // ⚠ D-Bus 的 `expire_timeout` 语义：0 = **永不消失**、-1 = 服务器缺省
        //   ⇒ 0 绝不能原样传出去（用户会看到通知赖在通知中心不走）。
        check(log, "通知：显示时长归一（越界夹紧、非正取缺省）",
            Notifications::normalizeTimeoutMs(5000) == 5000
                && Notifications::normalizeTimeoutMs(0) == Notifications::kDefaultTimeoutMs
                && Notifications::normalizeTimeoutMs(-1) == Notifications::kDefaultTimeoutMs
                && Notifications::normalizeTimeoutMs(1) == Notifications::kMinTimeoutMs
                && Notifications::normalizeTimeoutMs(999999999) == Notifications::kMaxTimeoutMs
                && Notifications::kDefaultTimeoutMs > Notifications::kMinTimeoutMs
                && Notifications::kMaxTimeoutMs > Notifications::kDefaultTimeoutMs);
        // ⚠ 顶替规则：只有「状态型」顶替；**两个不同的状态型归同一类**
        //   （否则「更新失败」与「项目停滞」各占一槽 ⇒ 通知中心照样会堆）。
        check(log, "通知：状态型顶替、其余并存（两个状态型归同一类）",
            Notifications::categoryOf(QStringLiteral("更新失败")) == QLatin1String("state")
                && Notifications::categoryOf(QStringLiteral("项目停滞")) == QLatin1String("state")
                && Notifications::categoryOf(QStringLiteral("更新完成")).isEmpty()
                && Notifications::categoryOf(QStringLiteral("定时更新简报")).isEmpty()
                && Notifications::replacesPrevious(QStringLiteral("更新失败"))
                && Notifications::replacesPrevious(QStringLiteral("项目停滞"))
                && !Notifications::replacesPrevious(QStringLiteral("更新完成"))
                && !Notifications::replacesPrevious(QStringLiteral("定时更新简报"))
                && Notifications::categoryOf(QStringLiteral("更新失败"))
                    == Notifications::categoryOf(QStringLiteral("项目停滞")));
    }

    // ── 引擎钩子（post-commit / post-merge 托管块）判定层 ──
    {
        // ⚠ 夹具里 **post-commit=true、post-merge=false**（不对称）——
        //   这样「位置约定搞反」的实现会立刻红（两个值相同时分叉不出来）。
        const QByteArray both = R"JSON({"project":"demo","installed":[true,true],"log":"/tmp/h.log"})JSON";
        const QByteArray one = R"JSON({"project":"demo","installed":[true,false],"log":"/tmp/h.log"})JSON";
        const QByteArray none = R"JSON({"project":"demo","installed":[false,false],"log":"/tmp/h.log"})JSON";
        const EngineHook::Status b = EngineHook::parseStatus(both);
        const EngineHook::Status o = EngineHook::parseStatus(one);
        const EngineHook::Status n = EngineHook::parseStatus(none);
        check(log, "引擎钩子：能读出 post-commit / post-merge 的安装状态",
            b.parsed && b.installedPresent && b.postCommit && b.postMerge
                && b.project == QLatin1String("demo") && b.log == QLatin1String("/tmp/h.log")
                && EngineHook::installedCount(b) == 2);
        // ⚠ **位置约定**：[0]=post-commit、[1]=post-merge。搞反了这里就红。
        check(log, "引擎钩子：installed 数组的位置约定（[0]=post-commit，[1]=post-merge）",
            o.parsed && o.installedPresent && o.postCommit && !o.postMerge
                && EngineHook::installedCount(o) == 1);
        // 缺 installed 键 = **契约漂移**，不是「没装」—— 混了会让人去重装一个已装的钩子
        const EngineHook::Status missing = EngineHook::parseStatus(
            R"JSON({"project":"demo","log":"/tmp/h.log"})JSON");
        check(log, "引擎钩子：缺 installed 键记「读不出来」而不是「没装」",
            missing.parsed && !missing.installedPresent && !missing.postCommit
                && !missing.postMerge);
        // 数组不够长 = 契约漂移（不是「那一项没装」）
        const EngineHook::Status shortArr = EngineHook::parseStatus(
            R"JSON({"project":"demo","installed":[true]})JSON");
        check(log, "引擎钩子：installed 数组不够长记「读不出来」",
            shortArr.parsed && !shortArr.installedPresent);
        const EngineHook::Status garbage = EngineHook::parseStatus("<html>404</html>");
        check(log, "引擎钩子：载荷读不懂报「读不懂」而不是「没装」",
            !garbage.parsed && !garbage.installedPresent);
        // 四种情形要四种说法
        const QStringList hookMsgs = {
            EngineHook::summary(b),
            EngineHook::summary(o),
            EngineHook::summary(n),
            EngineHook::summary(missing),
        };
        const QSet<QString> hookUniq(hookMsgs.begin(), hookMsgs.end());
        check(log, "引擎钩子：四种状态各说各的（都装/装一半/没装/读不出来）",
            hookMsgs.size() == 4 && hookUniq.size() == 4);
        // 批量汇总必须**点名失败的项目**（「N 个成功」不等于「全成功」）
        QVector<EngineHook::Item> items;
        items.push_back({ QStringLiteral("ok1"), true, QString() });
        items.push_back({ QStringLiteral("bad1"), false, QStringLiteral("引擎退出码 1") });
        const QString batch = EngineHook::batchSummary(items);
        // ⚠ **中文匹配串必须用 QStringLiteral，不能用 QLatin1String** ——
        //   Latin-1 每字符 1 字节，装不下中文（会被截断 → 匹配恒假 → 判据看着在、
        //   实际抓不住任何东西）。纯 ASCII 才用 QLatin1String。
        check(log, "引擎钩子：批量汇总点名失败的项目（不只报成功数）",
            batch.contains(QStringLiteral("1 个项目成功"))
                && batch.contains(QStringLiteral("bad1"))
                && batch.contains(QStringLiteral("引擎退出码 1")));
    }

}

} // namespace SelfCheckInternal
