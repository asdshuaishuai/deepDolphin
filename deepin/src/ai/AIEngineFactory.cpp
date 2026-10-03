#include "AIEngineFactory.h"
#include "AIEngine.h"
#include "AnthropicEngine.h"
#include "MockEngine.h"
#include "OpenAiCompatEngine.h"
#include "SystemAiEngine.h"

std::unique_ptr<AIEngine> AIEngineFactory::defaultEngine()
{
    return std::make_unique<SystemAiEngine>();
}

std::unique_ptr<AIEngine> AIEngineFactory::create(const AIConfig &cfg)
{
    // 显式渠道优先（PLAN §5.2）；配置不全（baseURL 空 / key 缺）不硬造渠道，
    // 落回系统级 AI —— 它的 isConfigured/generate 会给出「AI 未配置」的明确原文。
    if (!cfg.isConfigured())
        return defaultEngine();
    if (cfg.providerID == QLatin1String("mock"))
        return std::make_unique<MockEngine>(cfg.baseURL);
    if (cfg.providerID == QLatin1String("anthropic"))
        return std::make_unique<AnthropicEngine>(cfg.baseURL, cfg.apiKey, cfg.model);
    // 其余一切 provider id（deepseek/openai/ollama/openrouter/自定义）都走 OpenAI 兼容线
    return std::make_unique<OpenAiCompatEngine>(cfg.baseURL, cfg.apiKey, cfg.model);
}

QString AIEngineFactory::testConnection(const AIConfig &cfg)
{
    const QString pid = cfg.providerID;

    // ── 系统级 AI（显式选中「system」或没有任何显式渠道）──
    if (pid == QLatin1String("system") || !cfg.isConfigured()) {
        SystemAiEngine sys;
        if (sys.probe() == SystemAiEngine::Cap::Present) {
            return QStringLiteral(
                "检测到 UOS AI 服务（com.deepin.copilot），但它不支持程序化补全，"
                "无法用于摘要与工具循环；助手页可用「用 UOS AI 打开」唤起对话窗口。"
                "要启用生成能力，请选择 OpenAI 兼容或 Anthropic 渠道并填写 API Key。");
        }
        QString why;
        sys.isConfigured(&why);
        return QStringLiteral("✗ AI 未配置：%1").arg(why);
    }

    // ── mock：固定连通文案（不起网络）──
    if (pid == QLatin1String("mock"))
        return QStringLiteral("连通：OK（mock 自测通道）");

    // ── 显式渠道：真发一次最小请求 ──
    GenerateRequest req;
    req.system = QStringLiteral("你是连通性测试器，只回复：OK");
    req.messages.append(ChatMessage::makeUser(QStringLiteral("ping")));
    req.maxTokens = 16;
    req.timeoutMs = 20'000; // 测试连接用短超时（完整生成走默认 120s）
    const GenerateResult r = AIEngineFactory::create(cfg)->generate(req);
    if (!r.ok)
        return r.error;
    if (r.text.trimmed().isEmpty())
        return QStringLiteral("已连接，但响应里没有文本（响应形状可能不匹配）");
    return QStringLiteral("连通：%1").arg(r.text.trimmed().left(40));
}
