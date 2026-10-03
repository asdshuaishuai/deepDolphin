#include "AgentPrompts.h"

namespace AgentPrompts {

QString systemPrompt(const QString &scopeLine, const QString &toolsText)
{
    // AgentCore.swift:213-225 原文；角色名沿用「deepGit 项目群管理助手」
    //（moonGit 是 deepGit 的现名，客户端文案对齐 mac 基准不改口）。
    return QStringLiteral(
        "你是 deepGit 项目群管理助手。引擎（AI 无关内核）已把当前范围的确定性事实整理给你。\n"
        "\n"
        "## 当前上下文\n"
        "用户关注的范围：%1\n"
        "\n"
        "## 可用工具（原生 tool_calls）\n"
        "%2\n"
        "\n"
        "## 行为准则\n"
        "- 需要更多数据或要执行动作时，通过工具调用完成；拿到足够信息后给出最终中文回答\n"
        "- 最终回答要具体：点名项目/分支，给可执行建议；不编造上下文里没有的事实\n")
        .arg(scopeLine, toolsText);
}

QString groupBriefPrompt()
{
    return QStringLiteral(
        "生成一份项目群说明（markdown）：项目构成与定位、各项目一句话现状、"
        "需要人处理的事项（未提交/停滞/待合入）、整体建议。400 字以内。");
}

QString projectBriefPrompt(const QString &projectName)
{
    return QStringLiteral(
        "为项目「%1」生成一份**项目说明**（markdown），包含：\n"
        "1. 一句话定位（结合 README 与代码构成判断它是什么）\n"
        "2. 当前状态（分支进度、未提交/未跟踪/stash、最近活跃）\n"
        "3. 工程结构要点（语言构成、热点文件）\n"
        "4. 风险与建议下一步\n"
        "要求：面向\"第一次接触这个项目的人\"，500 字以内，具体、可执行、不编造。\n")
        .arg(projectName);
}

QString updateDigestPrompt(const QString &projectName, bool deep)
{
    return QStringLiteral(
        "刚对项目「%1」执行了%2。\n"
        "请基于引擎事实生成一段 ≤120 字的中文摘要：这次更新记录了什么、哪些分支有变化、"
        "有什么值得注意的。\n"
        "只输出摘要正文。\n")
        .arg(projectName, deep ? QStringLiteral("深度更新") : QStringLiteral("浅更新"));
}

QString scheduledDigestPrompt()
{
    return QStringLiteral(
        "定时更新已完成。请生成 ≤150 字的项目群简报：哪些项目有新变化、"
        "哪些需要人处理（未提交/停滞/待合入）。只输出简报正文。");
}

QString bulkDigestPrompt(const QString &outcomeTable, bool deep)
{
    return QStringLiteral(
        "刚对**全部已注册项目**执行了%1，逐仓库结果如下：\n"
        "\n"
        "%2\n"
        "\n"
        "请生成 ≤200 字的中文简报：这次全量更新整体发生了什么、哪些仓库需要人处理"
        "（更新失败 / 长期未更新 / 有未提交改动 / 待合入分支）。只输出简报正文，不要复述表格。\n")
        .arg(deep ? QStringLiteral("深度更新") : QStringLiteral("浅更新"), outcomeTable);
}

} // namespace AgentPrompts
