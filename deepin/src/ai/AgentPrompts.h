// AgentPrompts.h — 六个入口的 prompt 组装（原文逐字对齐 mac AgentCore.swift /
// AIIntegration.swift / AgentBulkUpdate.swift，PLAN §2.5）。
#pragma once
#include <QString>

namespace AgentPrompts {

// 系统提示词：角色 + 当前范围 + 工具清单原文 + 行为准则（AgentCore.swift:213-225 逐字）。
QString systemPrompt(const QString &scopeLine, const QString &toolsText);

// 一键项目群说明（AIIntegration GroupBriefButton 原文）。
QString groupBriefPrompt();

// 一键项目说明（AgentCore.projectBrief 原文）。
QString projectBriefPrompt(const QString &projectName);

// 更新后摘要（AgentCore.updateDigest 原文）。
QString updateDigestPrompt(const QString &projectName, bool deep);

// 定时更新简报（AgentCore.scheduledDigest 原文）。
QString scheduledDigestPrompt();

// 全量 AI 简报（AgentBulkUpdate.digest 原文；outcomeTable 由调用方拼好传入）。
QString bulkDigestPrompt(const QString &outcomeTable, bool deep);

} // namespace AgentPrompts
