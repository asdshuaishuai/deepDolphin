#include "OpenAiCompatEngine.h"
#include "AIChannel.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

OpenAiCompatEngine::OpenAiCompatEngine(const QString &baseURL, const QString &apiKey,
    const QString &model)
    : m_baseURL(baseURL.trimmed())
    , m_apiKey(apiKey)
    , m_model(model)
{
}

bool OpenAiCompatEngine::isConfigured(QString *whyNot) const
{
    if (m_baseURL.isEmpty()) {
        if (whyNot)
            *whyNot = QStringLiteral("Base URL 为空（请在 AI 设置里选择 provider 或填写覆盖）");
        return false;
    }
    if (m_apiKey.trimmed().isEmpty()) {
        if (whyNot)
            *whyNot = QStringLiteral("API Key 为空（请填写；key 只存入安全存储）");
        return false;
    }
    return true;
}

GenerateResult OpenAiCompatEngine::generate(const GenerateRequest &req)
{
    GenerateResult out;
    QString why;
    if (!isConfigured(&why)) {
        out.error = QStringLiteral("AI 未配置：%1").arg(why);
        return out;
    }
    QUrl url(m_baseURL);
    if (!url.isValid() || !AIChannel::urlAllowed(url)) {
        out.error = QStringLiteral(
            "Base URL 只允许 https:// 或 http://127.0.0.1 / http://localhost"
            "（防止密钥被发给不可信端点）");
        return out;
    }
    QString path = url.path();
    if (path.endsWith(QLatin1Char('/')))
        path.chop(1);
    url.setPath(path + QStringLiteral("/chat/completions"));

    // ── 消息载荷：system 首 + assistant(tool_calls) / tool 原生线格式 ──
    QJsonArray payload;
    if (!req.system.isEmpty()) {
        payload.append(QJsonObject { { "role", "system" }, { "content", req.system } });
    }
    for (const ChatMessage &m : req.messages) {
        if (m.role == ChatMessage::Role::assistant && !m.toolCalls.isEmpty()) {
            QJsonObject entry;
            entry.insert(QLatin1String("role"), QLatin1String("assistant"));
            if (!m.text.isEmpty())
                entry.insert(QLatin1String("content"), m.text);
            QJsonArray calls;
            for (const ToolCall &tc : m.toolCalls) {
                calls.append(QJsonObject {
                    { "id", tc.id },
                    { "type", "function" },
                    { "function",
                        QJsonObject { { "name", tc.name },
                            { "arguments", QString::fromUtf8(tc.argsJson) } } },
                });
            }
            entry.insert(QLatin1String("tool_calls"), calls);
            payload.append(entry);
        } else if (m.role == ChatMessage::Role::tool) {
            payload.append(QJsonObject {
                { "role", "tool" },
                { "tool_call_id", m.toolCallId },
                { "content", m.text },
            });
        } else {
            payload.append(QJsonObject { { "role", m.roleString() }, { "content", m.text } });
        }
    }

    QJsonObject body;
    body.insert(QLatin1String("model"), m_model);
    body.insert(QLatin1String("messages"), payload);
    body.insert(QLatin1String("stream"), false);
    body.insert(QLatin1String("max_tokens"), req.maxTokens);
    if (!req.tools.isEmpty()) {
        QJsonArray tools;
        for (const ToolDef &t : req.tools) {
            // params "a,b,c" → {type:object, properties:{k:{type:string}}, required:[…]}
            // —— 全部 string 型必填（引擎 tools --json 的 params 是唯一来源）
            QJsonObject props;
            for (const QString &p : t.requiredParams)
                props.insert(p, QJsonObject { { "type", "string" }, { "description", p } });
            tools.append(QJsonObject {
                { "type", "function" },
                { "function",
                    QJsonObject { { "name", t.name }, { "description", t.description },
                        { "parameters",
                            QJsonObject { { "type", "object" }, { "properties", props },
                                { "required", QJsonArray::fromStringList(t.requiredParams) } } } } },
            });
        }
        body.insert(QLatin1String("tools"), tools);
    }

    // ── POST（共享传输层：120s / 脱敏 / 网络错误中文翻译）──
    const AIChannel::HttpResponse resp = AIChannel::post(url,
        QJsonDocument(body).toJson(QJsonDocument::Compact),
        { { QStringLiteral("Authorization"), QStringLiteral("Bearer %1").arg(m_apiKey) } },
        req.timeoutMs);
    if (!resp.networkOk) {
        out.error = AIChannel::describeNetworkError(resp.errCode, AIChannel::hostOf(url));
        return out;
    }
    if (resp.status != 200) {
        out.error = QStringLiteral("AI 调用失败（HTTP %1）：%2")
                        .arg(resp.status)
                        .arg(AIChannel::redact(QString::fromUtf8(resp.body)));
        return out;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(resp.body);
    const QJsonArray choices = doc.object().value(QLatin1String("choices")).toArray();
    if (choices.isEmpty() || !choices.first().toObject().contains(QLatin1String("message"))) {
        out.error = QStringLiteral("AI 响应无法解析（choices/message 缺失）");
        return out;
    }
    const QJsonObject message = choices.first().toObject().value(QLatin1String("message")).toObject();
    out.text = message.value(QLatin1String("content")).toString();
    const QJsonArray rawCalls = message.value(QLatin1String("tool_calls")).toArray();
    for (int i = 0; i < rawCalls.size(); ++i) {
        const QJsonObject tc = rawCalls.at(i).toObject();
        const QJsonObject fn = tc.value(QLatin1String("function")).toObject();
        const QString name = fn.value(QLatin1String("name")).toString();
        if (name.isEmpty())
            continue; // 形状不全的调用丢弃（与 mac 一致）
        ToolCall call;
        call.id = tc.value(QLatin1String("id")).toString();
        if (call.id.isEmpty())
            call.id = QStringLiteral("call_%1").arg(i);
        call.name = name;
        call.argsJson = fn.value(QLatin1String("arguments")).toString().toUtf8();
        if (call.argsJson.trimmed().isEmpty())
            call.argsJson = "{}";
        out.toolCalls.append(call);
    }
    out.ok = true;
    return out;
}
