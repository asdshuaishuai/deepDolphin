#include "AnthropicEngine.h"
#include "AIChannel.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

AnthropicEngine::AnthropicEngine(const QString &baseURL, const QString &apiKey,
    const QString &model)
    : m_baseURL(baseURL.trimmed())
    , m_apiKey(apiKey)
    , m_model(model)
{
}

bool AnthropicEngine::isConfigured(QString *whyNot) const
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

GenerateResult AnthropicEngine::generate(const GenerateRequest &req)
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
    url.setPath(path + QStringLiteral("/v1/messages"));

    // ── 消息载荷：system 顶层；assistant(tool_use blocks) / tool(tool_result) ──
    QJsonArray payload;
    for (const ChatMessage &m : req.messages) {
        if (m.role == ChatMessage::Role::system)
            continue; // system 走顶层字段，不进 messages
        if (m.role == ChatMessage::Role::assistant && !m.toolCalls.isEmpty()) {
            QJsonArray blocks;
            if (!m.text.isEmpty())
                blocks.append(QJsonObject { { "type", "text" }, { "text", m.text } });
            for (const ToolCall &tc : m.toolCalls) {
                // argumentsJSON 字符串 → input 对象（解不出给空对象，模型可见其错）
                QJsonObject input;
                const QJsonDocument argsDoc = QJsonDocument::fromJson(tc.argsJson);
                if (argsDoc.isObject())
                    input = argsDoc.object();
                blocks.append(QJsonObject {
                    { "type", "tool_use" },
                    { "id", tc.id },
                    { "name", tc.name },
                    { "input", input },
                });
            }
            payload.append(QJsonObject { { "role", "assistant" }, { "content", blocks } });
        } else if (m.role == ChatMessage::Role::tool) {
            payload.append(QJsonObject {
                { "role", "user" },
                { "content",
                    QJsonArray { QJsonObject { { "type", "tool_result" },
                        { "tool_use_id", m.toolCallId },
                        { "content", m.text } } } },
            });
        } else {
            payload.append(QJsonObject { { "role", m.roleString() }, { "content", m.text } });
        }
    }

    QJsonObject body;
    body.insert(QLatin1String("model"), m_model);
    body.insert(QLatin1String("max_tokens"), req.maxTokens);
    if (!req.system.isEmpty())
        body.insert(QLatin1String("system"), req.system);
    body.insert(QLatin1String("messages"), payload);
    if (!req.tools.isEmpty()) {
        QJsonArray tools;
        for (const ToolDef &t : req.tools) {
            QJsonObject props;
            for (const QString &p : t.requiredParams)
                props.insert(p, QJsonObject { { "type", "string" }, { "description", p } });
            tools.append(QJsonObject {
                { "name", t.name },
                { "description", t.description },
                { "input_schema",
                    QJsonObject { { "type", "object" }, { "properties", props },
                        { "required", QJsonArray::fromStringList(t.requiredParams) } } },
            });
        }
        body.insert(QLatin1String("tools"), tools);
    }

    const AIChannel::HttpResponse resp = AIChannel::post(url,
        QJsonDocument(body).toJson(QJsonDocument::Compact),
        { { QStringLiteral("x-api-key"), m_apiKey },
            { QStringLiteral("anthropic-version"), QStringLiteral("2023-06-01") } },
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
    if (!doc.object().contains(QLatin1String("content"))) {
        out.error = QStringLiteral("AI 响应无法解析（content 缺失）");
        return out;
    }
    const QJsonArray content = doc.object().value(QLatin1String("content")).toArray();
    for (const QJsonValue &v : content) {
        const QJsonObject block = v.toObject();
        const QString type = block.value(QLatin1String("type")).toString();
        if (type == QLatin1String("text")) {
            out.text += block.value(QLatin1String("text")).toString();
        } else if (type == QLatin1String("tool_use")) {
            ToolCall call;
            call.id = block.value(QLatin1String("id")).toString();
            if (call.id.isEmpty())
                call.id = QStringLiteral("toolu_%1").arg(out.toolCalls.size());
            call.name = block.value(QLatin1String("name")).toString();
            const QJsonDocument argsDoc(block.value(QLatin1String("input")).toObject());
            call.argsJson = argsDoc.toJson(QJsonDocument::Compact);
            if (call.argsJson.trimmed().isEmpty())
                call.argsJson = "{}";
            out.toolCalls.append(call);
        }
    }
    out.ok = true;
    return out;
}
