#include "AgentCore.h"
#include "../app/EngineCli.h"
#include "../models/ContextEnvelope.h"
#include "../models/ToolsEnvelope.h"
#include "AIEngineFactory.h"
#include "AgentConversation.h"
#include "AgentOutcome.h"
#include "AgentPrompts.h"
#include "ToolArgs.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <memory>

namespace {
// 上下文预算：整轮 9000（SPEC §4.4）；工具内取 8000（与 mac 一致）。
constexpr int kContextBudget = 9000;
constexpr int kToolContextBudget = 8000;
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

bool AgentCore::runEngineRaw(const QStringList &args, int timeoutMs, QString *rawOut, QString *err)
{
    const EngineCli::EngineResult res = EngineCli::runSync(args, timeoutMs, m_bin);
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
    QString *toolsText, QString *err)
{
    QString raw;
    if (!runEngineRaw({ QStringLiteral("tools"), QStringLiteral("--json") },
            EngineTimeouts::Tools, &raw, err))
        return false;
    if (toolsText)
        *toolsText = raw; // 清单**原文**进系统提示词（mac 同款）

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
                if (paramsByTool)
                    paramsByTool->insert(d.name, QString::fromUtf8(paramsDoc.toJson(QJsonDocument::Compact)));
                if (defs)
                    defs->append(d);
            }
        }
    }
    return true;
}

bool AgentCore::executeTool(const QString &name, const QJsonObject &params,
    const QMap<QString, QString> &paramsByTool, QString *outText)
{
    // ⚠️ 必填校验放在执行点内部（不是调用方）：清单只有一个来源——已发给模型的那份。
    const QStringList requiredList = ToolArgs::required(paramsByTool, name);
    const QStringList absent = ToolArgs::missing(params, requiredList);
    if (!absent.isEmpty()) {
        if (outText)
            *outText = ToolArgs::missingMessage(name, absent);
        return false;
    }
    const auto str = [&params](const QString &key) {
        return params.value(key).toString();
    };

    QString raw;
    QString err;
    bool ok = false;
    // 10 个工具，与引擎 tools --json 声明集严格相等（contract 钉住）；
    // default → 明说「未知工具」，不静默成功。
    if (name == QLatin1String("get_group_context")) {
        ok = runEngineRaw({ QStringLiteral("context"), QStringLiteral("--budget"),
                                QString::number(kToolContextBudget), QStringLiteral("--json") },
            EngineTimeouts::Context, &raw, &err);
        if (ok && outText) {
            ContextEnvelope::Note note;
            if (const auto env = ContextEnvelope::decode(raw.toUtf8(), &note))
                *outText = env->context; // mac：工具内只交正文（说明走系统提示词那条路）
            else
                *outText = raw;
        }
    } else if (name == QLatin1String("get_project_context")) {
        ok = runEngineRaw({ QStringLiteral("context"), str(QStringLiteral("name")),
                                QStringLiteral("--budget"), QString::number(kToolContextBudget),
                                QStringLiteral("--json") },
            EngineTimeouts::Context, &raw, &err);
        if (ok && outText) {
            ContextEnvelope::Note note;
            if (const auto env = ContextEnvelope::decode(raw.toUtf8(), &note))
                *outText = env->context;
            else
                *outText = raw;
        }
    } else if (name == QLatin1String("get_project_docs")) {
        ok = runEngineRaw({ QStringLiteral("docs"), str(QStringLiteral("name")),
                                QStringLiteral("--json") },
            EngineTimeouts::Docs, &raw, &err);
    } else if (name == QLatin1String("get_journal")) {
        ok = runEngineRaw({ QStringLiteral("journal"), str(QStringLiteral("name")),
                                QStringLiteral("--json") },
            EngineTimeouts::Journal, &raw, &err);
    } else if (name == QLatin1String("get_milestones")) {
        ok = runEngineRaw({ QStringLiteral("milestone"), QStringLiteral("list"),
                                QStringLiteral("--json") },
            EngineTimeouts::Milestones, &raw, &err);
    } else if (name == QLatin1String("run_shallow_update")) {
        ok = runEngineRaw({ QStringLiteral("update"), str(QStringLiteral("name")),
                                QStringLiteral("--json"), QStringLiteral("--quiet") },
            EngineTimeouts::Update, &raw, &err);
    } else if (name == QLatin1String("run_deep_update")) {
        ok = runEngineRaw({ QStringLiteral("deep"), str(QStringLiteral("name")),
                                QStringLiteral("--json"), QStringLiteral("--quiet") },
            EngineTimeouts::Deep, &raw, &err);
    } else if (name == QLatin1String("git_commit")) {
        ok = runEngineRaw({ QStringLiteral("git"), QStringLiteral("commit"),
                                str(QStringLiteral("name")), QStringLiteral("--message"),
                                str(QStringLiteral("message")), QStringLiteral("--json") },
            EngineTimeouts::Git, &raw, &err);
    } else if (name == QLatin1String("git_pull_push")) {
        // 引擎 git 白名单里 agent 工具只该碰 pull/push——越界明说，不转交
        QString op = str(QStringLiteral("op"));
        if (op.isEmpty())
            op = QStringLiteral("pull");
        if (op != QLatin1String("pull") && op != QLatin1String("push")) {
            if (outText)
                *outText = QStringLiteral(
                    "git_pull_push 的 op 只支持 pull|push，收到：「%1」。已拒绝执行。")
                    .arg(op);
            return false;
        }
        ok = runEngineRaw({ QStringLiteral("git"), op, str(QStringLiteral("name")),
                                QStringLiteral("--json") },
            EngineTimeouts::Git, &raw, &err);
    } else if (name == QLatin1String("milestone_done")) {
        ok = runEngineRaw({ QStringLiteral("milestone"), QStringLiteral("done"),
                                str(QStringLiteral("project")), str(QStringLiteral("name")),
                                QStringLiteral("--json") },
            EngineTimeouts::Milestones, &raw, &err);
    } else {
        if (outText)
            *outText = QStringLiteral("未知工具：%1").arg(name);
        return false;
    }

    if (!ok) {
        if (outText)
            *outText = err;
        return false;
    }
    if (outText)
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
    if (!runEngineRaw(ctxArgs, EngineTimeouts::Context, &ctxRaw, &err))
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
    if (!loadToolManifest(&toolDefs, &paramsByTool, &toolsText, &err))
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

            // ② 必填校验在 executeTool 内部（同一份清单）；③ 截断自报家门。
            QString out;
            const bool ok = executeTool(call.name, decoded.obj, paramsByTool, &out);
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
