// MockEngine.h — mock 自测通道（providerID=="mock"，PLAN §2.5 / §8 T9）。
//
// 对位 mac「配一个回 tool_calls 的假 provider」的自测做法，但把假 provider 内置：
// 不起本地 HTTP 服务也能全链路验证 agent 工具循环（工具调用 → 客户端执行 → 回喂 →
// 最终文本）。脚本写在 Base URL 的 # 片段里（见 fromScript）；没有片段时按会话
// 状态自动编排：还没跑过工具 → 回一个无必填参数的工具调用；已有工具结果 → 回最终文本。
//
// 【边界】mock 只为本地验证客户端循环，不许在生产路径出现；
// key 走 QSettings 明文通道（AIConfig 已限定 mock 专用，正常保存路径清明文副本）。
#pragma once
#include "AIEngine.h"

class MockEngine final : public AIEngine {
public:
    explicit MockEngine(const QString &baseURL)
        : m_baseURL(baseURL)
    {
    }

    QString backendId() const override { return QStringLiteral("mock"); }
    bool isConfigured(QString *whyNot = nullptr) const override;
    GenerateResult generate(const GenerateRequest &req) override;

    // 按 # 片段脚本产出响应（可独立测试）：
    //   · 无片段：状态机自动编排（无 tool 结果 → 工具调用；有 → 最终文本）
    //   · #tool=<名>[;args={"k":"v"}]：回指定工具调用（args 缺省 {}）
    //   · #final[=文本]：回最终文本（缺省「（mock）最终回答」）
    //   · #fail[=原因]：回错误
    static GenerateResult fromScript(const QString &baseURL, const GenerateRequest &req);

private:
    QString m_baseURL; // 只当脚本载体（# 片段）；为空 = 自动编排
};
