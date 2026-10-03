// AIEngine.h — AI 通道的纯数据形状与单轮生成抽象（mac ChatMessage.swift +
// AISDK.LanguageModel 协议面的对位）。
//
// 【零依赖纪律】本头不放任何网络/UI/引擎依赖：AgentConversation / AgentOutcome /
// ToolArgs 这些判定层要直接消费 ChatMessage，谁拖进了 QNetworkAccessManager 谁就
// 把整条判定链拖进线程地狱（mac 把 ChatMessage 从 AISDK 拆出来的同一理由）。
//
// 这几个类型是**协议形状**，不是业务逻辑：一个字段都不许在别处重新造一份。
#pragma once
#include <QList>
#include <QString>
#include <functional>

// 一次原生工具调用（OpenAI 形状；Anthropic 侧由通道转换 tool_use blocks）
struct ToolCall {
    QString id;
    QString name;
    QByteArray argsJson; // JSON 对象字符串
};

// 一条对话消息。role/text/toolCalls/toolCallId 发给模型；
// isError **只给界面用**（「工具根本没跑」这件事靠标记显示，不靠文案匹配）。
struct ChatMessage {
    enum class Role { system, user, assistant, tool };
    Role role = Role::user;
    QString text;
    QList<ToolCall> toolCalls; // assistant 原生工具调用
    QString toolCallId;        // tool 角色消息的调用 id
    bool isError = false;

    const char *roleString() const
    {
        switch (role) {
        case Role::system: return "system";
        case Role::user: return "user";
        case Role::assistant: return "assistant";
        case Role::tool: return "tool";
        }
        return "user";
    }

    static ChatMessage makeUser(const QString &t)
    {
        ChatMessage m;
        m.role = Role::user;
        m.text = t;
        return m;
    }
    static ChatMessage makeAssistant(const QString &t)
    {
        ChatMessage m;
        m.role = Role::assistant;
        m.text = t;
        return m;
    }
    // isError 只影响界面显不显示，不影响发给模型的内容。
    static ChatMessage makeTool(const QString &t, const QString &callId, bool isError = false)
    {
        ChatMessage m;
        m.role = Role::tool;
        m.text = t;
        m.toolCallId = callId;
        m.isError = isError;
        return m;
    }
};

// 工具定义（发给模型的那份契约的唯一来源；params → JSON Schema 在通道内组装）
struct ToolDef {
    QString name;
    QString description;
    QStringList requiredParams; // 全部 string 型必填（引擎 tools --json 的 params 拆分）
};

struct GenerateRequest {
    QString system;
    QList<ChatMessage> messages;
    QList<ToolDef> tools;
    int maxTokens = 4000;
    int timeoutMs = 120'000; // SPEC §4.2：请求 timeout 120s（测试连接用短超时）
};

struct GenerateResult {
    QString text;
    QList<ToolCall> toolCalls;
    QString error; // ok=false 时的中文原因（可指导下一步）
    bool ok = false;
};

// 单轮生成抽象。同步阻塞调用：实现内部自带等待（QEventLoop），
// **调用方必须从 worker 线程进**（PLAN §2.5 ai/AIEngine 行）。
class AIEngine {
public:
    virtual ~AIEngine();

    virtual QString backendId() const = 0;
    // 显式渠道：baseURL/key 齐不齐；系统级 AI：服务在不在总线上。whyNot 给人看的原因。
    virtual bool isConfigured(QString *whyNot = nullptr) const = 0;
    virtual GenerateResult generate(const GenerateRequest &req) = 0;
};
