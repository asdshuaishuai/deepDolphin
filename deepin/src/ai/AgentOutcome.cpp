#include "AgentOutcome.h"

namespace AgentOutcome {

std::optional<QString> atRoundLimit(const QString &text, int maxRounds)
{
    const QString partial = text.trimmed();
    if (partial.isEmpty())
        return std::nullopt;
    return partial + QStringLiteral(
                         "\n\n> ⚠️ 已达工具调用轮次上限（%1 轮），以上是达到上限时已生成的内容"
                         " —— 还可能有工具结果没被消化。")
                         .arg(maxRounds);
}

Finish finish(const QString &text, const QStringList &executedTools, int maxRounds)
{
    Finish f;
    if (const std::optional<QString> partial = atRoundLimit(text, maxRounds)) {
        f.k = Finish::K::final;
        f.text = *partial;
        return f;
    }
    // 文本真空，但工具已经生效 —— 报「失败」才是撒谎
    if (executedTools.isEmpty())
        return f; // failed
    f.k = Finish::K::final;
    f.text = executedSummary(executedTools, maxRounds);
    return f;
}

QString executedSummary(const QStringList &tools, int maxRounds)
{
    return QStringLiteral("> ⚠️ 已达工具调用轮次上限（%1 轮），模型还没来得及解读结果。\n"
                          "> 但这些工具**已经执行完并且生效了**：%2。\n"
                          "> 请不要重复执行；要接着问就直接说，工具结果仍留在会话里。")
        .arg(maxRounds)
        .arg(tools.join(QStringLiteral("、")));
}

} // namespace AgentOutcome
