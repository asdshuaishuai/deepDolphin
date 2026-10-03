// AIEngineFactory.h — 后端选择（PLAN §5.2 优先级）：
//
//   1. AIConfig 已配置显式渠道（isConfigured：baseURL 非空 &&（ollama/mock 或 key 非空））
//      → OpenAI 兼容 / Anthropic / Mock —— **优先于系统级 AI**；
//   2. 否则 → SystemAiEngine（系统级 AI，默认后端）；
//   3. 系统级 AI 也不可用（服务消失）→ generate/isConfigured 给明确错误，
//      全部 AI 入口如实报「AI 未配置」，更新动作照常可用（CHARTER §3）。
//
// testConnection：system prompt「你是连通性测试器，只回复：OK」+ user "ping"，
// maxTokens 16；系统后端返回 probe 结果文案；mock 返回固定连通文案。
#pragma once
#include "AIConfig.h"
#include <memory>
#include <QString>

class AIEngine;

class AIEngineFactory {
public:
    // 按优先级产出引擎；返回的引擎恒非空（默认 = SystemAiEngine）。
    static std::unique_ptr<AIEngine> create(const AIConfig &cfg);

    // 未配置任何显式渠道时的默认引擎（系统级 AI）。
    static std::unique_ptr<AIEngine> defaultEngine();

    // 连通性测试（同步；调用方放 worker 线程）。返回给人看的一行结论。
    static QString testConnection(const AIConfig &cfg);
};
