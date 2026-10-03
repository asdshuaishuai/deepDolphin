// AnthropicEngine.h — Anthropic Messages 通道（mac AISDK.generateAnthropic 对位）。
//
// 线格式：`POST {base}/v1/messages`，头 `x-api-key` + `anthropic-version: 2023-06-01`；
// system 顶层字段；tools = {name, description, input_schema}；assistant 工具调用 =
// tool_use blocks、工具结果 = user 角色 tool_result blocks（原生块，非文本协议）。
#pragma once
#include "AIEngine.h"

class AnthropicEngine final : public AIEngine {
public:
    AnthropicEngine(const QString &baseURL, const QString &apiKey, const QString &model);

    QString backendId() const override { return QStringLiteral("anthropic"); }
    bool isConfigured(QString *whyNot = nullptr) const override;
    GenerateResult generate(const GenerateRequest &req) override;

private:
    QString m_baseURL;
    QString m_apiKey;
    QString m_model;
};
