// AiDigests.h — AI 一次性入口（PLAN §2.5）：五个 prompt 各自跑一轮 agent 工具循环。
//
// 统一语义：
// · 未配置（系统级 AI 缺席且无显式渠道）→ error = 「AI 未配置：…」原文，调用方原样透出；
// · 系统级 AI 在但无补全出口 → error = SystemAiEngine 的明确降级文案；
// · 更新动作**不因 AI 失败而失败**（CHARTER §3）——调用方对 error 只做「附注」不做「失败」。
//
// 【线程】全部同步阻塞，调用方放 worker 线程。
#pragma once
#include "AIConfig.h"
#include <QString>

namespace AiDigests {

struct Outcome {
    bool ok = false;
    QString text;  // ok 时的正文（markdown）
    QString error; // !ok 时的中文原因（永不为空——「没生成」要说为什么）
};

Outcome groupBrief(const QString &engineBin, const AIConfig &cfg);
Outcome projectBrief(const QString &engineBin, const AIConfig &cfg, const QString &project);
Outcome updateDigest(const QString &engineBin, const AIConfig &cfg, const QString &project,
    bool deep);
Outcome scheduledDigest(const QString &engineBin, const AIConfig &cfg);
Outcome bulkDigest(const QString &engineBin, const AIConfig &cfg, const QString &outcomeTable,
    bool deep);

} // namespace AiDigests
