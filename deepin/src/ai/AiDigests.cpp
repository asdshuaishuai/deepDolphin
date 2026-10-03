#include "AiDigests.h"
#include "AgentCore.h"
#include "AgentPrompts.h"
#include <QList>

namespace AiDigests {

namespace {
Outcome runOne(const QString &engineBin, const AIConfig &cfg, const QString &question,
    AgentCore::Target target, int maxRounds)
{
    Outcome out;
    AgentCore core(engineBin);
    QString err;
    const QList<ChatMessage> convo = core.run(question, {}, target, cfg, maxRounds, {}, &err);
    if (!err.isEmpty()) {
        out.error = err;
        return out;
    }
    // 正常收尾时最后一条 assistant 就是最终文本（撞上限时是 partial/executedSummary）
    for (int i = convo.size() - 1; i >= 0; --i) {
        if (convo.at(i).role == ChatMessage::Role::assistant) {
            out.text = convo.at(i).text.trimmed();
            break;
        }
    }
    if (out.text.isEmpty()) {
        out.error = QStringLiteral("AI 已调用，但没有产出正文。");
        return out;
    }
    out.ok = true;
    return out;
}
} // namespace

Outcome groupBrief(const QString &engineBin, const AIConfig &cfg)
{
    return runOne(engineBin, cfg, AgentPrompts::groupBriefPrompt(),
        AgentCore::Target { AgentCore::Target::Kind::group, {} }, 4);
}

Outcome projectBrief(const QString &engineBin, const AIConfig &cfg, const QString &project)
{
    return runOne(engineBin, cfg, AgentPrompts::projectBriefPrompt(project),
        AgentCore::Target { AgentCore::Target::Kind::project, project }, 4);
}

Outcome updateDigest(const QString &engineBin, const AIConfig &cfg, const QString &project,
    bool deep)
{
    return runOne(engineBin, cfg, AgentPrompts::updateDigestPrompt(project, deep),
        AgentCore::Target { AgentCore::Target::Kind::project, project }, 2);
}

Outcome scheduledDigest(const QString &engineBin, const AIConfig &cfg)
{
    return runOne(engineBin, cfg, AgentPrompts::scheduledDigestPrompt(),
        AgentCore::Target { AgentCore::Target::Kind::group, {} }, 3);
}

Outcome bulkDigest(const QString &engineBin, const AIConfig &cfg, const QString &outcomeTable,
    bool deep)
{
    return runOne(engineBin, cfg, AgentPrompts::bulkDigestPrompt(outcomeTable, deep),
        AgentCore::Target { AgentCore::Target::Kind::group, {} }, 3);
}

} // namespace AiDigests
