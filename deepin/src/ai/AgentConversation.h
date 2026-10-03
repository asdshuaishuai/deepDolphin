// AgentConversation.h — 对话会话的判定（无 UI、无 IO、可单测；mac AgentConversation.swift 对位）。
//
// 「能不能发」「这条显示成什么」「历史截到多长」内联进视图就运行时抓不到，
// 而它们恰是最容易出静默错误的地方（按钮该灰不灰、历史悄悄涨爆 token）。
#pragma once
#include "AIEngine.h"
#include <QString>
#include <QStringList>
#include <QVector>

namespace AgentConversation {

// 一条**要显示**的消息。内部 tool 消息不直接进列表（工具往返是过程不是对话内容），
// 但**标了 isError 的必须显示**——否则「工具根本没跑」在界面上完全不留痕。
struct TranscriptEntry {
    enum class Kind { user, assistant, note };
    Kind kind = Kind::user;
    QString text;
};

// 把「已有历史」与「本轮提问」拼成要发给模型的那份对话。
// 「历史有没有被丢」因此可测（mac：曾每次从零起步，追问必然落空）。
QList<ChatMessage> seed(QList<ChatMessage> history, const QString &question,
    int maxApproxTokens = 12'000);

// 历史裁剪：按近似 token 保留**最近**若干轮（12000/400 = 30 条）。
// 粗略估一个，宁可少留也别让请求炸掉；保留最近，丢最早那轮不影响「刚才说什么」。
QList<ChatMessage> trimHistory(QList<ChatMessage> history, int maxApproxTokens = 12'000,
    int approxTokensPerMessage = 400);

// 内部消息列表 → 显示 transcript（transcript 三规则：tool 不显示/isError 必显、
// assistant 空 text 有 toolCalls →「（调用工具：a、b）」、空 user 不显示）。
QVector<TranscriptEntry> transcript(const QList<ChatMessage> &history);

// 「发送」的可用性：返回**原因**而不是 Bool——按钮灰掉但不给理由，用户只能猜。
enum class SendBlock { none, empty, notConfigured, busy };
struct SendDecision {
    bool allowed = false;
    QString text;      // allowed 时携带整理好的文本
    SendBlock block = SendBlock::none;
};
SendDecision canSend(const QString &draft, bool isBusy, bool isConfigured);

// 「停止」的可用性：忙且尚未在停止中。
bool canStop(bool isBusy, bool isCancelled);

} // namespace AgentConversation
