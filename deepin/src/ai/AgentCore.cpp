#include "AgentCore.h"
#include "../app/EngineCli.h"
#include "../logic/AgentToolPlan.h"
#include "../models/ContextEnvelope.h"
#include "../models/ToolsEnvelope.h"
#include "AIEngineFactory.h"
#include "AgentConversation.h"
#include "AgentOutcome.h"
#include "AgentPrompts.h"
#include "ToolArgs.h"
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <memory>

namespace {
// 上下文预算：整轮 9000（SPEC §4.4）；工具内取 8000（与 mac 一致）——
// 工具内的那个已随 argv 形态一起搬进 logic/AgentToolPlan（跟命令形态同处）。
constexpr int kContextBudget = 9000;
// 客户端自报截断阈值：引擎自己的截断披露写在**结尾**，头部切会把它切掉，
// 于是客户端切的这刀必须自报家门（#191）。
constexpr int kToolOutputClip = 16000;

QString clipNote(int original, int clip)
{
    return QStringLiteral(
        "\n\n（客户端在此处截断：原始 %1 字符，只保留前 %2 字符。"
        "要看全量请缩小查询范围，或用更小的 budget 分批取。）")
        .arg(original)
        .arg(clip);
}
} // namespace

bool AgentCore::runEngineRaw(const QStringList &args, int timeoutMs, QString *rawOut, QString *err,
    const QAtomicInt *cancelled)
{
    const EngineCli::EngineResult res = EngineCli::runSync(args, timeoutMs, m_bin, cancelled);
    if (!res.ok()) {
        if (err)
            *err = res.error.userMessage();
        return false;
    }
    if (rawOut)
        *rawOut = res.stdOut;
    return true;
}

bool AgentCore::loadToolManifest(QVector<ToolDef> *defs, QMap<QString, QString> *paramsByTool,
    QString *toolsText, QString *err, const QAtomicInt *cancelled)
{
    QString raw;
    if (!runEngineRaw({ QStringLiteral("tools"), QStringLiteral("--json") },
            EngineTimeouts::Tools, &raw, err, cancelled))
        return false;
    if (toolsText)
        *toolsText = raw; // 兜底：解析失败就用原文（不空提示词）

    // 解析失败 → 空清单不崩（mac engineToolDefinitions 同款守卫）
    const QJsonDocument doc = QJsonDocument::fromJson(raw.toUtf8());
    if (doc.isObject()) {
        if (const auto env = ToolsEnvelope::fromJson(doc.object())) {
            for (const ToolSpec &t : env->tools) {
                ToolDef d;
                d.name = t.name;
                d.description = t.description;
                // params "a,b,c" → 全部 string 型必填（单一来源：引擎 tools --json）
                for (const QString &p : t.params.split(QLatin1Char(','))) {
                    const QString key = p.trimmed();
                    if (!key.isEmpty() && !key.contains(QLatin1Char('(')))
                        d.requiredParams << key;
                }
                // parametersJSON（必填校验唯一来源；与发给模型的定义同源组装）
                QJsonObject props;
                for (const QString &p : d.requiredParams)
                    props.insert(p, QJsonObject { { "type", "string" }, { "description", p } });
                const QJsonDocument paramsDoc(QJsonObject {
                    { "type", "object" },
                    { "properties", props },
                    { "required", QJsonArray::fromStringList(d.requiredParams) },
                });
                // ⚠ 必填校验表收**全部**工具（含废弃别名）—— 契约门第 12 组钉住
                //   「客户端能执行的工具集 == 引擎声明的工具集」，别名必须仍可执行。
                if (paramsByTool)
                    paramsByTool->insert(d.name, QString::fromUtf8(paramsDoc.toJson(QJsonDocument::Compact)));
                // ⚠ 但**模型可调用的工具面**只给非废弃的：引擎标了「旧名别名，
                //   将移除」的那些就别再推荐给模型了（工具面收敛）。
                if (!t.deprecated && defs)
                    defs->append(d);
            }
            // 系统提示词里的清单 = **收敛后**的（与上面的工具面同一口径）——
            // 不收敛的话，提示词里还列着旧名，模型就会去调它。
            if (toolsText) {
                *toolsText = QString::fromUtf8(
                    QJsonDocument(env->activeJson()).toJson(QJsonDocument::Compact));
            }
        }
    }
    return true;
}

bool AgentCore::executeTool(const QString &name, const QJsonObject &params,
    const QMap<QString, QString> &paramsByTool, QString *outText, const QAtomicInt *cancelled)
{
    // ⚠️ 必填校验放在执行点内部（不是调用方）：清单只有一个来源——已发给模型的那份。
    const QStringList requiredList = ToolArgs::required(paramsByTool, name);
    const QStringList absent = ToolArgs::missing(params, requiredList);
    if (!absent.isEmpty()) {
        if (outText)
            *outText = ToolArgs::missingMessage(name, absent);
        return false;
    }

    // argv 形态、参数校验、拒绝理由全在**纯函数表**里（logic/AgentToolPlan）：
    // 28 个工具（与引擎 tools --json 严格对位）的命令形态、flag 解析、白名单
    // 都可无头判；这一层只做 I/O 与执行。
    AgentToolPlan::Plan plan = AgentToolPlan::planFor(name, params);
    if (!plan.known) {
        if (outText)
            *outText = QStringLiteral("未知工具：%1").arg(name);
        return false;
    }
    if (!plan.reject.isEmpty()) {
        if (outText)
            *outText = plan.reject;
        return false;
    }

    // 临时文件：引擎 CLI 吃**路径**的那种（graph patchconf --merge <a.json> <b.json>）。
    // 落盘是 I/O，在这里做 —— 纯函数层只声明「哪个参数要落盘、argv 哪一格放路径」。
    QStringList argv = plan.argv;
    QTemporaryDir tmpDir;
    if (!plan.tempParams.isEmpty()) {
        if (!tmpDir.isValid()) {
            if (outText)
                *outText = QStringLiteral("无法创建临时目录，%1 未执行。").arg(name);
            return false;
        }
        for (const QString &key : plan.tempParams) {
            const QString path = tmpDir.filePath(key + QStringLiteral(".json"));
            QFile f(path);
            if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                if (outText)
                    *outText = QStringLiteral("写临时文件失败（%1），%2 未执行。")
                                   .arg(path, name);
                return false;
            }
            f.write(params.value(key).toString().toUtf8());
            f.close();
            for (QString &a : argv) {
                if (a == QStringLiteral("{{tmp:%1}}").arg(key))
                    a = path;
            }
        }
    }

    QString raw;
    QString err;
    const bool ok = runEngineRaw(argv, plan.timeoutMs, &raw, &err, cancelled);
    if (!ok) {
        if (outText)
            *outText = err;
        return false;
    }
    if (!outText)
        return true;

    // context 两个工具：只交正文给模型（说明走系统提示词那条路，mac 同款）
    if (name == QLatin1String("get_group_context")
        || name == QLatin1String("get_project_context")) {
        ContextEnvelope::Note note;
        if (const auto env = ContextEnvelope::decode(raw.toUtf8(), &note))
            *outText = env->context;
        else
            *outText = raw;
        return true;
    }
    *outText = raw; // 原始 stdout（JSON 原文交给模型解读，mac 同款）
    return true;
}

QList<ChatMessage> AgentCore::run(const QString &question, QList<ChatMessage> history,
    const Target &target, const AIConfig &cfg, int maxRounds,
    const std::function<void(const QString &)> &onEvent, QString *errorOut,
    QAtomicInt *cancelled)
{
    auto fail = [errorOut](const QString &msg) {
        if (errorOut)
            *errorOut = msg;
        return QList<ChatMessage> {};
    };

    // ① 引擎选择（工厂优先级：显式渠道 > 系统级 AI）+ 配置守卫
    const std::unique_ptr<AIEngine> engine = AIEngineFactory::create(cfg);
    QString whyNot;
    if (!engine->isConfigured(&whyNot))
        return fail(QStringLiteral("AI 未配置：%1").arg(whyNot));

    // ② 上下文包（.group → context --budget 9000；.project(n) → context <n> --budget 9000）
    QStringList ctxArgs { QStringLiteral("context") };
    if (!target.isGroup())
        ctxArgs << target.projectName;
    ctxArgs << QStringLiteral("--budget") << QString::number(kContextBudget)
            << QStringLiteral("--json");
    QString ctxRaw;
    QString err;
    if (!runEngineRaw(ctxArgs, EngineTimeouts::Context, &ctxRaw, &err, cancelled))
        return fail(err);
    // 「没解出来」≠「没有」：三种失败（非 JSON/缺键/空串）的说明与正文一起给模型。
    ContextEnvelope::Note note;
    QString context;
    if (const auto env = ContextEnvelope::decode(ctxRaw.toUtf8(), &note))
        context = env->context;
    if (!ContextEnvelope::noteText(note).isEmpty())
        context = ContextEnvelope::noteText(note) + QStringLiteral("\n\n") + context;

    // ③ 工具清单（原文进系统提示词）+ 必填校验的唯一来源
    QVector<ToolDef> toolDefs;
    QMap<QString, QString> paramsByTool;
    QString toolsText;
    if (!loadToolManifest(&toolDefs, &paramsByTool, &toolsText, &err, cancelled))
        return fail(err);

    // ④ 系统提示词 + 当前范围事实
    const QString system = AgentPrompts::systemPrompt(
        QStringLiteral("scope: %1").arg(target.label()), toolsText)
        + QStringLiteral("\n\n## 当前范围事实（引擎生成）\n\n") + context;

    // ⑤ 历史 + 本轮提问（先裁一刀，否则聊几轮就撞上下文上限）
    QList<ChatMessage> convo = AgentConversation::seed(std::move(history), question);

    for (int round = 1; round <= maxRounds; ++round) {
        if (cancelled && cancelled->loadRelaxed())
            return fail(QStringLiteral("AI 请求已取消。"));
        GenerateRequest req;
        req.system = system;
        req.messages = convo;
        req.tools = toolDefs;
        const GenerateResult result = engine->generate(req);
        if (!result.ok)
            return fail(result.error);

        if (result.toolCalls.isEmpty()) {
            convo.append(ChatMessage::makeAssistant(result.text));
            return convo;
        }

        ChatMessage assistantMsg;
        assistantMsg.role = ChatMessage::Role::assistant;
        assistantMsg.text = result.text;
        assistantMsg.toolCalls = result.toolCalls;
        convo.append(assistantMsg);

        QStringList executedThisRound;
        for (const ToolCall &call : result.toolCalls) {
            if (cancelled && cancelled->loadRelaxed())
                return fail(QStringLiteral("AI 请求已取消。"));
            if (onEvent)
                onEvent(QStringLiteral("🔧 %1").arg(call.name));

            // ① 畸形参数在**执行之前**拦下（NC31）：不执行，把原因回报给模型让它重试。
            const ToolArgs::Decoded decoded = ToolArgs::decode(call.argsJson);
            if (decoded.k == ToolArgs::Decoded::K::malformed) {
                const QString why = ToolArgs::malformedMessage(call.name, decoded.raw);
                if (onEvent)
                    onEvent(QStringLiteral("   ✗ %1：参数非法，未执行").arg(call.name));
                convo.append(ChatMessage::makeTool(why, call.id, true));
                continue;
            }

            // ② 必填校验在 executeTool 内部（同一份清单）；③ 截断自报家门；
            // ④ cancelled 透传：工具执行中也能被「停止」终止（M0-5）。
            QString out;
            const bool ok = executeTool(call.name, decoded.obj, paramsByTool, &out, cancelled);
            const QString clipped = out.size() > kToolOutputClip
                ? out.left(kToolOutputClip) + clipNote(out.size(), kToolOutputClip)
                : out;
            if (onEvent)
                onEvent(QStringLiteral("   %1 %2").arg(ok ? QStringLiteral("✓")
                                                          : QStringLiteral("✗"),
                    call.name));
            convo.append(ChatMessage::makeTool(
                QStringLiteral("工具 %1 执行%2：\n%3")
                    .arg(call.name, ok ? QStringLiteral("成功") : QStringLiteral("失败"), clipped),
                call.id, !ok));
            if (ok)
                executedThisRound << call.name;
        }

        if (round == maxRounds) {
            // 撞上限收尾（AgentOutcome 三态）：工具已执行 ≠ 失败；
            // 只有「文本真空且本轮没跑过工具」才抛错。
            const AgentOutcome::Finish finish
                = AgentOutcome::finish(result.text, executedThisRound, maxRounds);
            if (finish.k == AgentOutcome::Finish::K::final) {
                convo.append(ChatMessage::makeAssistant(finish.text));
                return convo;
            }
            return fail(QStringLiteral("已达工具调用轮次上限（%1），且模型未产出任何文本")
                            .arg(maxRounds));
        }
    }
    return fail(QStringLiteral("agent 循环异常退出"));
}
