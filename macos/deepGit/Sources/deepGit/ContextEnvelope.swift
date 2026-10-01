import Foundation

/// `context --json` 信封的解码。**纯函数，零依赖**。
///
/// 为什么要有它（缺陷 #191）：同一个数据在客户端有**两条路**，
/// 两条路给模型的形状不一样：
///   · 系统提示词那条路（AgentCore 拼 fullSystem）抽了 `context` → markdown
///   · 工具结果那条路（`get_group_context` / `get_project_context`）
///     把整个 `{"scope":…,"budget":…,"context":"# deepGit…\n…"}` 塞进对话
/// 而引擎自己的 MCP 工具返回的是**裸 markdown**。
/// 于是同名工具：走引擎 MCP 得 markdown，走客户端得转义过的 JSON 字符串。
/// 模型读到的第一行是 `{"scope":"project","budget":8000,"context":"# deepGit`。
///
/// 附带一条更硬的：原系统提示词那条路写的是
/// `ctxObj?["context"] as? String ?? ""` —— 解不出就得到**空串**。
/// 空上下文会被模型读成「这个项目群什么都没有」，而真相是「没解出来」。
/// 「没解出来」必须说出来，不能并进「没有」。
enum ContextEnvelope {
    /// 解出的上下文。`note` 非 nil 时必须与正文一起交给模型。
    static func decode(_ data: Data) -> (context: String, note: String?) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // 不是预期形状：把原文交出去（可能仍有用），但**必须说清它没按预期解码。
            let raw = String(data: data, encoding: .utf8) ?? ""
            return (raw, "（引擎返回的不是预期的 context JSON 形状，以下为原文，可能无法解析）")
        }
        if let ctx = obj["context"] as? String, !ctx.isEmpty {
            return (ctx, nil)
        }
        if let ctx = obj["context"] as? String, ctx.isEmpty {
            return (ctx, "（引擎返回了空的 context：这个范围**没有内容**，不是「没解出来」）")
        }
        // 有 JSON、但没有 context 键
        return (String(data: data, encoding: .utf8) ?? "",
                "（引擎返回的 JSON 里没有 context 键：以下为原文，**这不等于「没有上下文」**）")
    }
}

/// 客户端自己再截一次时的措辞。**纯函数**。
///
/// ⚠️ 引擎已经在自己的预算边界上披露过「内容不完整」，
/// 而那行披露写在**结尾**。客户端从头部按 16000 字符再切一刀，
/// 就会把引擎那行披露一起切掉 —— 于是模型看到的是
/// 「一段看起来完整、其实缺了尾巴」的上下文。
/// 所以客户端自己切的这一刀必须**自报家门**：
/// 说清是客户端截的（不是引擎预算），并指路去缩小范围。
func clientClipNote(_ originalCount: Int, _ limit: Int) -> String {
    return "\n…（客户端在此处截断：原始 \(originalCount) 字符，只给了前 \(limit) 字符。"
        + "上面的内容**不完整**，末尾可能还有引擎自己披露的截断信息也没带过来。"
        + "要看全量请缩小查询范围，或用更小的 budget 分批取。）"
}
