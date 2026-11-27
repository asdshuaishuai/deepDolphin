#include "AgentToolPlan.h"

#include "EngineTimeouts.h"

#include <QRegularExpression>

namespace AgentToolPlan {
namespace {

// agent 工具的 context 预算（与 AgentCore 同款：8000 字符）。
constexpr int kToolContextBudget = 8000;

QString str(const QJsonObject &params, const QString &key)
{
    return params.value(key).toString().trimmed();
}

/// 数值型参数：只在**确实是数**时给值（"3" 给，"abc" 不给，"" 不给）。
/// 引擎对非法数字会报用法错误 —— 与其把垃圾递给引擎让它报错，
/// 不如不给（缺省交给引擎用它的默认值）。
QString num(const QJsonObject &params, const QString &key)
{
    const QString v = str(params, key);
    if (v.isEmpty())
        return QString();
    static const QRegularExpression re(QStringLiteral("^-?\\d+(\\.\\d+)?$"));
    return re.match(v).hasMatch() ? v : QString();
}

/// 开关型参数：模型给的可能是布尔 true，也可能是字符串 "true"/"1"/"yes"/"on"，
/// 还可能是数字 1。
/// 引擎把 params 声明成**全 string 型必填**，所以模型多半发字符串 ——
/// 只认布尔会让 flag 永远不生效（--force / --violations 形同虚设）。
///
/// ⚠⚠ **数字形态以前也漏了**（批 AS 实测）：`QJsonValue::toString()` 对**数字**
///   返回的是**空串**（不是 "1"）⇒ 走字符串分支必然落空 ⇒ JSON `{"force": 1}`
///   判**假**。⇒ 补上数字分支：**只有 1 为真**（2 之类一律假 —— 不是「非 0 即真」，
///   那是另一套约定；这里跟 mac 侧 `ToolArgs.flag` 必须**同口径**）。
///   ⚠ `isBool()` 要**先**判：Qt 里 `true`/`false` 存成 bool 型、`1`/`0` 存成 double 型，
///   两者在 `isDouble()` 上不重叠（`isDouble()` 只对数字为真）。
bool flag(const QJsonObject &params, const QString &key)
{
    const QJsonValue v = params.value(key);
    if (v.isBool())
        return v.toBool();
    if (v.isDouble())
        return v.toDouble() == 1.0;
    const QString s = v.toString().trimmed().toLower();
    return s == QLatin1String("true") || s == QLatin1String("1")
        || s == QLatin1String("yes") || s == QLatin1String("on");
}

void addIfNotEmpty(QStringList &argv, const QString &key, const QString &value)
{
    if (!value.isEmpty())
        argv << QStringLiteral("--") + key << value;
}

} // namespace

Plan planFor(const QString &name, const QJsonObject &params)
{
    Plan p;
    const QString n = name;

    // ── 原有 10 个（argv 口径与批 V1 之前完全一致，只搬家不改语义）──
    if (n == QLatin1String("get_group_context")) {
        p.argv = { QStringLiteral("context"), QStringLiteral("--budget"),
            QString::number(kToolContextBudget), QStringLiteral("--json") };
        p.timeoutMs = EngineTimeouts::Context;
    } else if (n == QLatin1String("get_project_context")) {
        p.argv = { QStringLiteral("context"), str(params, QStringLiteral("name")),
            QStringLiteral("--budget"), QString::number(kToolContextBudget),
            QStringLiteral("--json") };
        p.timeoutMs = EngineTimeouts::Context;
    } else if (n == QLatin1String("get_project_docs")) {
        p.argv = { QStringLiteral("docs"), str(params, QStringLiteral("name")),
            QStringLiteral("--json") };
        p.timeoutMs = EngineTimeouts::Docs;
    } else if (n == QLatin1String("get_journal")) {
        p.argv = { QStringLiteral("journal"), str(params, QStringLiteral("name")),
            QStringLiteral("--json") };
        p.timeoutMs = EngineTimeouts::Journal;
    } else if (n == QLatin1String("get_milestones")) {
        p.argv = { QStringLiteral("milestone"), QStringLiteral("list"),
            QStringLiteral("--json") };
        p.timeoutMs = EngineTimeouts::Milestones;
    } else if (n == QLatin1String("run_shallow_update")) {
        p.argv = { QStringLiteral("update"), str(params, QStringLiteral("name")),
            QStringLiteral("--json"), QStringLiteral("--quiet") };
        p.timeoutMs = EngineTimeouts::Update;
    } else if (n == QLatin1String("run_deep_update")) {
        p.argv = { QStringLiteral("deep"), str(params, QStringLiteral("name")),
            QStringLiteral("--json"), QStringLiteral("--quiet") };
        p.timeoutMs = EngineTimeouts::Deep;
    } else if (n == QLatin1String("git_commit")) {
        p.argv = { QStringLiteral("git"), QStringLiteral("commit"),
            str(params, QStringLiteral("name")), QStringLiteral("--message"),
            str(params, QStringLiteral("message")), QStringLiteral("--json") };
        p.timeoutMs = EngineTimeouts::Git;
    } else if (n == QLatin1String("git_pull_push")) {
        // 引擎的工具契约写死 op(pull|push) —— 越界明说，不转交引擎
        // （引擎的 git 白名单里没有 fetch，模型要 fetch 也给不了）。
        const QString op = str(params, QStringLiteral("op")).isEmpty()
            ? QStringLiteral("pull") : str(params, QStringLiteral("op"));
        if (op != QLatin1String("pull") && op != QLatin1String("push")) {
            p.reject = QStringLiteral(
                "git_pull_push 的 op 只支持 pull|push，收到：「%1」。已拒绝执行。").arg(op);
            return p;
        }
        p.argv = { QStringLiteral("git"), op, str(params, QStringLiteral("name")),
            QStringLiteral("--json") };
        p.timeoutMs = EngineTimeouts::Git;
    } else if (n == QLatin1String("milestone_done")) {
        p.argv = { QStringLiteral("milestone"), QStringLiteral("done"),
            str(params, QStringLiteral("project")), str(params, QStringLiteral("name")),
            QStringLiteral("--json") };
        p.timeoutMs = EngineTimeouts::Milestones;

    // ── 新增 18 个（图/架构/置信度/补丁能力，mac AgentCore 同款口径）──
    } else if (n == QLatin1String("arch_gen")) {
        p.argv = { QStringLiteral("arch"), QStringLiteral("gen"),
            str(params, QStringLiteral("name")) };
        addIfNotEmpty(p.argv, QStringLiteral("format"), str(params, QStringLiteral("format")));
        p.timeoutMs = 600'000; // 整图重建是重命令
    } else if (n == QLatin1String("arch_update")) {
        p.argv = { QStringLiteral("arch"), QStringLiteral("update"),
            str(params, QStringLiteral("name")) };
        if (flag(params, QStringLiteral("force")))
            p.argv << QStringLiteral("--force");
        p.timeoutMs = 600'000;
    } else if (n == QLatin1String("arch_query")) {
        p.argv = { QStringLiteral("arch"), QStringLiteral("query"),
            str(params, QStringLiteral("name")) };
        const QString module = str(params, QStringLiteral("module"));
        if (!module.isEmpty())
            p.argv << module;
        if (flag(params, QStringLiteral("violations")))
            p.argv << QStringLiteral("--violations");
        p.timeoutMs = 300'000;
    } else if (n == QLatin1String("index_gen")) {
        // manifest 默认 json（喂模型的结构化视图）；显式传了才覆盖
        const QString format = str(params, QStringLiteral("format"));
        p.argv = { QStringLiteral("index"), QStringLiteral("gen"),
            str(params, QStringLiteral("name")), QStringLiteral("--format"),
            format.isEmpty() ? QStringLiteral("json") : format };
        const QString depth = num(params, QStringLiteral("depth"));
        if (!depth.isEmpty())
            p.argv << QStringLiteral("--depth") << depth;
        p.timeoutMs = 600'000;
    } else if (n == QLatin1String("index_update")) {
        p.argv = { QStringLiteral("index"), QStringLiteral("update"),
            str(params, QStringLiteral("name")) };
        if (flag(params, QStringLiteral("force")))
            p.argv << QStringLiteral("--force");
        p.timeoutMs = 600'000;
    } else if (n == QLatin1String("index_overview")) {
        p.argv = { QStringLiteral("index"), QStringLiteral("overview"),
            str(params, QStringLiteral("name")) };
        p.timeoutMs = 120'000;
    } else if (n == QLatin1String("index_query")) {
        // 用法：index query <symbol> [项目] | index query --file <路径> [项目]
        p.argv = { QStringLiteral("index"), QStringLiteral("query") };
        const QString file = str(params, QStringLiteral("file"));
        if (!file.isEmpty())
            p.argv << QStringLiteral("--file") << file;
        const QString symbol = str(params, QStringLiteral("symbol"));
        if (!symbol.isEmpty())
            p.argv << symbol;
        p.argv << str(params, QStringLiteral("name"));
        p.timeoutMs = 180'000;
    } else if (n == QLatin1String("confidence_gen")) {
        const QString format = str(params, QStringLiteral("format"));
        p.argv = { QStringLiteral("confidence"), QStringLiteral("gen"),
            str(params, QStringLiteral("name")), QStringLiteral("--format"),
            format.isEmpty() ? QStringLiteral("json") : format };
        if (flag(params, QStringLiteral("no_ast")))
            p.argv << QStringLiteral("--no-ast");
        if (flag(params, QStringLiteral("db")))
            p.argv << QStringLiteral("--db");
        p.timeoutMs = 600'000;
    } else if (n == QLatin1String("confidence_query")) {
        p.argv = { QStringLiteral("confidence"), QStringLiteral("query"),
            str(params, QStringLiteral("name")) };
        addIfNotEmpty(p.argv, QStringLiteral("file"), str(params, QStringLiteral("file")));
        addIfNotEmpty(p.argv, QStringLiteral("symbol"), str(params, QStringLiteral("symbol")));
        addIfNotEmpty(p.argv, QStringLiteral("kind"), str(params, QStringLiteral("kind")));
        const QString weight = num(params, QStringLiteral("weight"));
        if (!weight.isEmpty())
            p.argv << QStringLiteral("--weight") << weight;
        const QString top = num(params, QStringLiteral("top"));
        if (!top.isEmpty())
            p.argv << QStringLiteral("--top") << top;
        p.timeoutMs = 120'000;
    } else if (n == QLatin1String("render")) {
        // 回执只有落盘路径与复用/新绘判定（不内塞 HTML 全文）
        const QString target = str(params, QStringLiteral("target")).isEmpty()
            ? QStringLiteral("index") : str(params, QStringLiteral("target"));
        p.argv = { QStringLiteral("render"), target, str(params, QStringLiteral("name")) };
        if (flag(params, QStringLiteral("confidence")))
            p.argv << QStringLiteral("--confidence");
        if (flag(params, QStringLiteral("force")))
            p.argv << QStringLiteral("--force");
        p.timeoutMs = 600'000;
    } else if (n == QLatin1String("codegraph_overview")) {
        p.argv = { QStringLiteral("graph"), QStringLiteral("overview"),
            str(params, QStringLiteral("name")), QStringLiteral("--json") };
        p.timeoutMs = 300'000;
    } else if (n == QLatin1String("codegraph_tree")) {
        p.argv = { QStringLiteral("graph"), QStringLiteral("tree"),
            str(params, QStringLiteral("name")), QStringLiteral("--json") };
        const QString depth = num(params, QStringLiteral("depth"));
        if (!depth.isEmpty())
            p.argv << QStringLiteral("--depth") << depth;
        p.timeoutMs = 600'000;
    } else if (n == QLatin1String("codegraph_symbol")) {
        p.argv = { QStringLiteral("graph"), QStringLiteral("symbol"),
            str(params, QStringLiteral("name")), str(params, QStringLiteral("symbol")),
            QStringLiteral("--json") };
        p.timeoutMs = 300'000;
    } else if (n == QLatin1String("codegraph_impact")) {
        p.argv = { QStringLiteral("graph"), QStringLiteral("impact"),
            str(params, QStringLiteral("name")), str(params, QStringLiteral("symbol")),
            QStringLiteral("--json") };
        p.timeoutMs = 300'000;
    } else if (n == QLatin1String("codegraph_arch")) {
        const QString format = str(params, QStringLiteral("format")).isEmpty()
            ? QStringLiteral("html") : str(params, QStringLiteral("format"));
        p.argv = { QStringLiteral("graph"), QStringLiteral("arch"),
            str(params, QStringLiteral("name")), QStringLiteral("--format"), format };
        p.timeoutMs = 600'000;
    } else if (n == QLatin1String("codegraph_confidence")) {
        // 引擎形态：graph confidence <名>（--json=结构化 / --llm=复核提示词 / 缺省=text）
        const QString format = str(params, QStringLiteral("format"));
        p.argv = { QStringLiteral("graph"), QStringLiteral("confidence"),
            str(params, QStringLiteral("name")) };
        if (format == QLatin1String("llm"))
            p.argv << QStringLiteral("--llm");
        else if (format != QLatin1String("text"))
            p.argv << QStringLiteral("--json");
        p.timeoutMs = 600'000;
    } else if (n == QLatin1String("codegraph_patch_confidence")) {
        p.argv = { QStringLiteral("graph"), QStringLiteral("patchconf"),
            str(params, QStringLiteral("name")), QStringLiteral("--patch"),
            str(params, QStringLiteral("patch_path")) };
        p.timeoutMs = 300'000;
    } else if (n == QLatin1String("codegraph_patch_merge")) {
        // 工具参数是两段 JSON **文本**；引擎 CLI 吃文件路径 ——
        // 落盘由执行方做（纯函数层只声明「哪个参数落盘、argv 哪一格放路径」）。
        p.argv = { QStringLiteral("graph"), QStringLiteral("patchconf"),
            QStringLiteral("--merge"), QStringLiteral("{{tmp:algorithm_json}}"),
            QStringLiteral("{{tmp:agent_json}}") };
        p.tempParams = { QStringLiteral("algorithm_json"), QStringLiteral("agent_json") };
        p.timeoutMs = 300'000;
    } else {
        return p; // known=false：未知工具明说，不静默成功
    }

    p.known = true;
    return p;
}

QStringList knownToolNames()
{
    // 与引擎 `tools --json` 声明集严格相等（contract 第 12 组钉住）。
    // 顺序按引擎声明顺序（便于人读两边的差异）。
    return {
        QStringLiteral("get_group_context"),
        QStringLiteral("get_project_context"),
        QStringLiteral("get_project_docs"),
        QStringLiteral("get_journal"),
        QStringLiteral("get_milestones"),
        QStringLiteral("run_shallow_update"),
        QStringLiteral("run_deep_update"),
        QStringLiteral("git_commit"),
        QStringLiteral("git_pull_push"),
        QStringLiteral("milestone_done"),
        QStringLiteral("arch_gen"),
        QStringLiteral("arch_update"),
        QStringLiteral("arch_query"),
        QStringLiteral("index_gen"),
        QStringLiteral("index_update"),
        QStringLiteral("index_overview"),
        QStringLiteral("index_query"),
        QStringLiteral("confidence_gen"),
        QStringLiteral("confidence_query"),
        QStringLiteral("render"),
        QStringLiteral("codegraph_overview"),
        QStringLiteral("codegraph_tree"),
        QStringLiteral("codegraph_symbol"),
        QStringLiteral("codegraph_impact"),
        QStringLiteral("codegraph_arch"),
        QStringLiteral("codegraph_confidence"),
        QStringLiteral("codegraph_patch_confidence"),
        QStringLiteral("codegraph_patch_merge"),
    };
}

} // namespace AgentToolPlan
