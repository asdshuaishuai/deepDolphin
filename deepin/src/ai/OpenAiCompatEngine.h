// OpenAiCompatEngine.h — OpenAI 兼容通道（deepseek / openai / ollama / openrouter /
// 网关 / 自定义，mac AISDK.generateOpenAICompatible 对位）。
//
// 线格式：`Authorization: Bearer`；tools = {type:function, function:{name,description,
// parameters}}；assistant 工具调用 / tool 角色消息走**原生 tool_calls 线格式**
//（不是文本协议）；stream:false；timeout 由 GenerateRequest.timeoutMs（默认 120s）。
#pragma once
#include "AIEngine.h"

class OpenAiCompatEngine final : public AIEngine {
public:
    // apiKey/baseURL/model 从 AIConfig 拷进（引擎不回读 QSettings，线程安全）
    OpenAiCompatEngine(const QString &baseURL, const QString &apiKey, const QString &model);

    QString backendId() const override { return QStringLiteral("openai-compat"); }
    bool isConfigured(QString *whyNot = nullptr) const override;
    GenerateResult generate(const GenerateRequest &req) override;

private:
    QString m_baseURL;
    QString m_apiKey;
    QString m_model;
};
