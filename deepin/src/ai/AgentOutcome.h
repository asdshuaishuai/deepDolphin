// AgentOutcome.h — agent 循环撞轮次上限时的收尾判定（纯函数；mac AgentOutcome.swift 对位）。
//
// 三态（与「不知道 ≠ 没有」同族）：
//   · 有文本（trim 后非空）→ 交出内容 + 标注「这是上限时的内容，可能不完整」；
//   · 文本真空但**本轮工具已执行** → executedSummary——工具早已生效
//     （run_shallow_update 改完文档、git_commit 已进仓库），报「失败」才是撒谎
//     （缺陷 NC30：报失败会诱导用户重试 = 同一 commit 提交两次）；
//   · 两者皆无 → failed，调用方抛错——那时抛错才是诚实说法。
#pragma once
#include <QString>
#include <QStringList>
#include <optional>

namespace AgentOutcome {

struct Finish {
    enum class K { failed, final } k = K::failed;
    QString text; // k==final 时作为最后一条 assistant 消息追加
};

// 轮次上限时应展示的文本；nullopt = 没有可展示的内容。
std::optional<QString> atRoundLimit(const QString &text, int maxRounds);

Finish finish(const QString &text, const QStringList &executedTools, int maxRounds);

// 「工具跑完了但模型没来得及解读」的收尾文案（独立成函数：两个消费方不许措辞漂移）。
QString executedSummary(const QStringList &tools, int maxRounds);

} // namespace AgentOutcome
