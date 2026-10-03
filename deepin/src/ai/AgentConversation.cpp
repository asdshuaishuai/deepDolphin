#include "AgentConversation.h"

namespace AgentConversation {

QList<ChatMessage> trimHistory(QList<ChatMessage> history, int maxApproxTokens,
    int approxTokensPerMessage)
{
    if (maxApproxTokens <= 0 || approxTokensPerMessage <= 0)
        return {};
    const int budget = qMax(1, maxApproxTokens / approxTokensPerMessage);
    if (history.size() <= budget)
        return history;
    // 尾部是最新，保留最后 budget 条。
    return QList<ChatMessage>(history.end() - budget, history.end());
}

QList<ChatMessage> seed(QList<ChatMessage> history, const QString &question, int maxApproxTokens)
{
    QList<ChatMessage> convo = trimHistory(std::move(history), maxApproxTokens);
    convo.append(ChatMessage::makeUser(question));
    return convo;
}

QVector<TranscriptEntry> transcript(const QList<ChatMessage> &history)
{
    QVector<TranscriptEntry> out;
    for (const ChatMessage &m : history) {
        switch (m.role) {
        case ChatMessage::Role::user: {
            const QString t = m.text.trimmed();
            if (!t.isEmpty()) {
                TranscriptEntry e;
                e.kind = TranscriptEntry::Kind::user;
                e.text = t;
                out.append(e);
            }
            break;
        }
        case ChatMessage::Role::assistant: {
            QString t = m.text.trimmed();
            if (t.isEmpty() && !m.toolCalls.isEmpty()) {
                QStringList names;
                for (const ToolCall &tc : m.toolCalls)
                    names << tc.name;
                t = QStringLiteral("（调用工具：%1）").arg(names.join(QStringLiteral("、")));
            }
            if (!t.isEmpty()) {
                TranscriptEntry e;
                e.kind = TranscriptEntry::Kind::assistant;
                e.text = t;
                out.append(e);
            }
            break;
        }
        case ChatMessage::Role::tool: {
            // 工具消息本身不显示；但失败/被拒绝这件事用户必须看到。
            // 判据是 isError 标记，不是文案里有没有「执行失败」（字面量匹配过一次就出事）。
            if (!m.isError)
                break;
            const QString first = m.text.section(QLatin1Char('\n'), 0, 0);
            TranscriptEntry e;
            e.kind = TranscriptEntry::Kind::note;
            e.text = QStringLiteral("⚠ %1").arg(first);
            out.append(e);
            break;
        }
        case ChatMessage::Role::system:
            break; // system 不进 transcript
        }
    }
    return out;
}

SendDecision canSend(const QString &draft, bool isBusy, bool isConfigured)
{
    SendDecision d;
    const QString t = draft.trimmed();
    if (t.isEmpty()) {
        d.block = SendBlock::empty;
        return d;
    }
    if (!isConfigured) {
        d.block = SendBlock::notConfigured;
        return d;
    }
    if (isBusy) {
        d.block = SendBlock::busy;
        return d;
    }
    d.allowed = true;
    d.text = t;
    return d;
}

bool canStop(bool isBusy, bool isCancelled)
{
    return isBusy && !isCancelled;
}

} // namespace AgentConversation
