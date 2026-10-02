// AgentOutcome.swift — agent 循环的收尾判定（纯函数，无依赖）。
//
// 单独成文件是刻意的：这里只放**能被独立编译**的纯判定，
// 好让 Tests/AgentCheck 直接编译本文件来测它 ——
// 复制一份到测试里会漂移，测了等于没测（副本漂移已坑过一次：
// 契约检查当初就是因为用了副本而失去意义）。
//
// 不要往这里加 Foundation/SwiftUI/AppModel 依赖，那会让它没法单独编译。

/// agent 循环到达工具调用轮次上限时，怎么收尾。
///
/// 背景（缺陷 P0-4）：原来在 `round == maxRounds` 时直接 `throw`，
/// 把**这一轮模型已经写出来的 `result.text` 一起丢掉**。
/// 模型在调工具的同时一直在组织答案，于是用户看到的是一句
/// 「已达工具调用轮次上限」，而一份接近完整的答案就在手边。
/// 「有答案不给」是这个项目最不该发生的一类损失。
///
/// 三态（与本项目一贯的「不知道 ≠ 没有」同一族）：
///   · 有内容            → 交出内容 + 标注「这是上限时的内容，可能不完整」
///   · 空但有空白字符    → 同上（先 trim，避免只有换行时也当成有答案）
///   · 真空              → nil，调用方该抛错。此时抛错才是诚实说法：
///                          工具调用轮里通常本来就没有文本。
///
/// 抽成纯函数的另一个理由：判定内联在 for 循环里时，
/// 单测抓不到「空文本」这一档 —— 而那一档恰恰是最容易悄悄写错的。
enum AgentOutcome {
    /// - Returns: 轮次上限时应展示的文本；`nil` 表示没有可展示的内容，调用方应抛错。
    static func atRoundLimit(text: String, maxRounds: Int) -> String? {
        let partial = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return nil }
        return partial
            + "\n\n> ⚠️ 已达工具调用轮次上限（\(maxRounds) 轮），以上是达到上限时已生成的内容"
            + " —— 还可能有工具结果没被消化。"
    }

    /// 撞轮次上限时的收尾方式。
    enum AgentFinish {
        /// 真空：既没有文本、这一轮也没跑过工具 —— 调用方该抛错。
        case failed
        /// 有东西可交：调用方把它作为最后一条 assistant 消息追加进历史。
        case final(String)
    }

    /// 撞轮次上限时整体该怎么收尾 —— **本轮已执行的工具必须被说出来**。
    ///
    /// ⚠️ 缺陷 NC30：原来循环收尾只看「这一轮有没有文本」，
    /// 于是「文本为空 + 工具已执行」被归进真空档 → `throw`。
    /// 可这时的工具**早就跑完了**：`run_shallow_update` 改完了文档、
    /// `git_commit` 的提交已经进了仓库。抛错会被界面显示成「失败」，
    /// 工具输出、过程事件、整段历史一并丢掉，
    /// 而用户看到的只是一句「未产出任何文本」——
    /// 他据此重试，就是同一个 commit 提交两次、同一次更新跑两遍。
    ///
    /// 这不是边角：模型只在返回 `tool_calls` 时 `text` 本来就是空的
    /// （OpenAI 兼容里 `content` 为 null，Anthropic 里没有 text block），
    /// 所以「最后一轮仍在调工具」是**正常路径**。
    static func finish(text: String, executedTools: [String], maxRounds: Int) -> AgentFinish {
        if let partial = atRoundLimit(text: text, maxRounds: maxRounds) {
            return .final(partial)
        }
        // 文本真空，但工具已经生效 —— 报「失败」才是撒谎
        guard !executedTools.isEmpty else { return .failed }
        return .final(executedSummary(tools: executedTools, maxRounds: maxRounds))
    }

    /// 「工具跑完了但模型没来得及解读」的收尾文案。
    ///
    /// 独立成函数是因为它有两份潜在消费方（对话历史 + 定时简报），
    /// 而措辞一旦漂移就会出现「一处说已执行、一处说失败」。
    static func executedSummary(tools: [String], maxRounds: Int) -> String {
        let names = tools.joined(separator: "、")
        return "> ⚠️ 已达工具调用轮次上限（\(maxRounds) 轮），模型还没来得及解读结果。\n"
            + "> 但这些工具**已经执行完并且生效了**：\(names)。\n"
            + "> 请不要重复执行；要接着问就直接说，工具结果仍留在会话里。"
    }
}
