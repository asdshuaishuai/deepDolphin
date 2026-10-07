// AgentConversation.swift — 对话会话的**判定**（无 UI、无 IO，可直接编译来测）。
//
// 为什么单独抽：AgentView 里那些「能不能发」「这条显示成什么」
// 「历史要截到多长」如果内联在视图里，运行时抓不到、也没法测；
// 而它们恰恰是最容易出静默错误的地方（按钮该灰不灰、历史悄悄涨到爆 token）。
//
// 一个已知缺陷的原样：AgentCore.run 每次都 `var convo = [ChatMessage.user(question)]`
// 从零开始、用完即弃 —— 所谓"对话"其实是**一连串互不相干的一次性提问**。
// 模型看不到上一轮，于是"那刚才那个项目呢"这种追问必然落空。
// 这里定义的多轮语义是修它的前提。
import Foundation

/// 一条**要显示**的消息。内部 `tool` 消息不直接进这个列表：
/// 工具往返是过程，不是对话内容，混进去会把 transcript 撑成一堵墙。
struct TranscriptEntry: Equatable, Identifiable {
    enum Kind: Equatable { case user, assistant, note }
    let id: String
    let kind: Kind
    let text: String

    static func user(_ id: String, _ text: String) -> TranscriptEntry {
        TranscriptEntry(id: id, kind: .user, text: text)
    }
    static func assistant(_ id: String, _ text: String) -> TranscriptEntry {
        TranscriptEntry(id: id, kind: .assistant, text: text)
    }
    static func note(_ id: String, _ text: String) -> TranscriptEntry {
        TranscriptEntry(id: id, kind: .note, text: text)
    }
}

enum Conversation {

    /// 把「已有历史」与「本轮提问」拼成要发给模型的那份对话。
    ///
    /// 抽出来是为了让"多轮"这件事**可测**：
    /// 内联在 `AgentCore.run` 里时，`var convo = [ChatMessage.user(question)]`
    /// 和 `var convo = trimHistory(history) + [...]` 两行长得完全不一样，
    /// 而 lint 只能查到其中一种拼法 —— 换一种写法缺陷就溜过去了。
    /// 抽成函数后，"历史有没有被丢"就是一个能直接断言的行为。
    static func seed(history: [ChatMessage],
                     question: String,
                     maxApproxTokens: Int = 12_000) -> [ChatMessage] {
        var convo = trimHistory(history, maxApproxTokens: maxApproxTokens)
        convo.append(ChatMessage.user(question))
        return convo
    }

    /// 历史裁剪：按**近似 token**保留最近若干轮。
    ///
    /// 为什么不用真实 token 数：这里要防的是"对话越来越长直到 400"，
    /// 精确计费不在职责内。粗略估一个，宁可少留也别让请求炸掉。
    /// 保留的永远是**最近**的，且至少留下最后一条 user 消息 ——
    /// 把最早那轮丢掉不影响"刚才说了什么"，把最新一轮丢掉就直接答非所问。
    static func trimHistory(
        _ history: [ChatMessage],
        maxApproxTokens: Int = 12_000,
        approxTokensPerMessage: Int = 400
    ) -> [ChatMessage] {
        guard maxApproxTokens > 0, approxTokensPerMessage > 0 else { return [] }
        let budget = max(1, maxApproxTokens / approxTokensPerMessage)
        guard history.count > budget else { return history }
        // 尾部是最新，保留最后 budget 条。
        return Array(history.suffix(budget))
    }

    /// 把内部消息列表投影成要显示的 transcript。
    ///
    /// 三条规则，每条都对应一种"看起来对其实丢了信息"的写法：
    ///   · `tool` 消息不显示（是过程不是内容）—— 但**标了 isError 的必须显示**，
    ///     否则「工具根本没跑」这件事在界面上完全不留痕
    ///   · assistant 只有 tool_calls 没有文本时，显示它调用了什么，
    ///     否则模型"干完活不说话"在界面上等同于"卡住了"
    ///   · 空文本的 user 消息不显示（点了发送但内容是空）
    ///
    /// ⚠️ 判断依据是 `isError` 标记，**不是**「文案里有没有『执行失败』四个字」。
    /// 字面量匹配过一次就出事：新增的拒绝路径写的是「已拒绝执行」，
    /// 界面立刻什么都不显示 —— 工具没跑、用户却不知道。
    static func transcript(from history: [ChatMessage],
                           failures: [String] = []) -> [TranscriptEntry] {
        var out: [TranscriptEntry] = []
        for (i, m) in history.enumerated() {
            switch m.role {
            case "user":
                let t = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out.append(.user("m\(i)", t)) }
            case "assistant":
                var t = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty, let calls = m.toolCalls, !calls.isEmpty {
                    t = L10n.t("agent.toolCalls", calls.map(\.name).joined(separator: "、"))
                }
                if !t.isEmpty { out.append(.assistant("m\(i)", t)) }
            case "tool":
                // 工具消息本身不显示；但**失败/被拒绝**这件事用户必须看到。
                guard m.isError else { continue }
                let first = m.text.split(separator: "\n").first.map(String.init) ?? m.text
                out.append(.note("m\(i)", "⚠ " + first))
            default:
                break   // system 不进 transcript
            }
        }
        for (i, f) in failures.enumerated() {
            out.append(.note("f\(i)", "⚠ " + f))
        }
        return out
    }

    /// 「发送」按钮的可用性。
    ///
    /// 四个条件缺一不可 —— 每个都对应一种"点了没反应"或"点了白点"：
    ///   · 非空文本      —— 否则等于替用户发了一条空消息
    ///   · 不在忙        —— 否则连发两次，两轮循环抢同一个上下文
    ///   · AI 已配置     —— 否则发出去必然失败，而错误是回来之后才知道
    ///   · 未被取消       —— 同上
    ///
    /// 为什么要返回**原因**而不是 Bool：按钮灰掉但不给理由，
    /// 用户只能猜是 AI 没配、是自己在跑、还是自己没打字。
    static func canSend(_ text: String, isBusy: Bool, isConfigured: Bool) -> SendDecision {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .blocked(.empty) }
        if !isConfigured { return .blocked(.notConfigured) }
        if isBusy { return .blocked(.busy) }
        return .allowed(t)
    }

    enum SendBlock: Equatable { case empty, notConfigured, busy }
    enum SendDecision: Equatable {
        case allowed(String)          // 携带整理好的文本
        case blocked(SendBlock)
        var isAllowed: Bool { if case .allowed = self { return true }; return false }
    }

    /// 「停止」按钮的可用性。
    ///
    /// 原来没有停止：一次 agent 循环最长 600 秒（update 工具），
    /// 用户只能等或关窗，而关窗并不会真的停掉后台的 Task。
    static func canStop(isBusy: Bool, isCancelled: Bool) -> Bool {
        isBusy && !isCancelled
    }
}
