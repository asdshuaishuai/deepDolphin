// A11yLabel.swift — 无障碍标签的派生规则（纯函数层，零 SwiftUI 依赖）。
//
// 【为什么要有这个】规范 §3.2 写「全部交互控件补 accessibilityLabel /
// accessibilityValue（当前 0 个，图标按钮只有 .help()，VoiceOver 读不到）」。
// 核实：全库 `.help()` 20 处，`accessibilityLabel` 只有 2 处（StatusDot 与新加的那条）。
//
// 【形状】`.help("清空对话")` 与 `accessibilityLabel("清空对话")` 是**同一句**话，
// 写两遍就是这仓库第 N 次「同一份约定抄多处」——而两处漂了没人知道。
// 所以：`.help` 是唯一来源，标签由 `a11yLabel(fromHelp:)` 派生，
// 视图用 `.accessibilityLabel(A11y.label("清空对话"))` 与 `.help("清空对话")` 共用同一字面量。
import Foundation

/// 无障碍标签派生。
enum A11y {
    /// 从 `.help` 文案派生 VoiceOver 标签。
    ///
    /// 空文案 ⇒ 返回 nil（**不编一个标签**）。
    /// 空标签比没有标签更糟：VoiceOver 会念出一个空按钮，用户完全不知道它是什么。
    static func label(fromHelp help: String) -> String? {
        let t = help.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 一定要拿到一个可用标签时的入口（modifier 链不能挂 `nil`）。
    ///
    /// ⚠️ 兜底必须是一句**有意义的话**，不能是空串。
    /// `.accessibilityLabel("")` 会让 VoiceOver 念出一个空按钮 ——
    /// 那比没有标签更坏，因为控件「存在但无名」。
    /// 拿不到就用 `fallback`，而 fallback 也要是能让人猜出这是什么的词。
    static func label(fromHelp help: String, fallback: String) -> String {
        label(fromHelp: help) ?? label(fromHelp: fallback) ?? "操作"
    }

    /// **字面量**文案的快捷入口。
    ///
    /// 字面量非空，所以返回 `String` 而不是 `String?` ——
    /// 调用点就不必写 `?? ""`（那个兜底是我第一版批量生成时留下的，
    /// 与本文件「空标签比没标签更糟」的判断自相矛盾）。
    static func label(_ literal: String) -> String {
        label(fromHelp: literal) ?? literal
    }

    /// 「标签 + 状态」的合成，供「标签会随状态变」的控件用
    /// （例如按钮本身固定叫「浅更新」，但当前项目忙时要读出「忙」）。
    static func label(_ name: String, value: String) -> String {
        let n = label(fromHelp: name) ?? "操作"
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? n : "\(n)，\(v)"
    }

    /// 数值控件的三态措辞。
    ///
    /// ⚠️ 三态必须**可区分**：把「读不出来」渲染成「0」是最常见的一种撒谎
    /// （引擎用 -1 表示读不出来，见 commitCount 那条判据）。
    /// 所以这里给的是三个**不同**的句子，不是一个带数字的模板。
    static func count(_ n: Int, _ what: String) -> String {
        let w = label(fromHelp: what) ?? "数量"
        if n < 0 { return "\(w)：读不出来" }
        if n == 0 { return "\(w)：0" }
        return "\(w)：\(n)"
    }

    /// 列表位置，供 VoiceOver 报「第 3 项，共 12 项」——否则用户不知道列表有多长。
    static func position(_ index: Int, of total: Int, _ name: String) -> String {
        let n = label(fromHelp: name) ?? "项目"
        guard total > 0 else { return n }
        return "\(n)，第 \(index + 1) 项，共 \(total) 项"
    }
}

/// 搜索过滤（纯函数）。
///
/// 【为什么单独一个文件】规范 §3.2 要求「项目与里程碑列表（当前是平铺 ForEach，
/// 无搜索无过滤）」。过滤逻辑必须是纯函数，否则没法断言「搜不到时说的是
/// 「没有匹配」而不是「什么都没有」」——而这两种三态完全不是一回事。
///
/// ⚠️ 与既有缺陷同源：引擎用 -1 表示「读不出来」（见 commitCount 判据），
/// 这里同理——**空结果必须区分「没匹配上」与「本来就没有」**。
enum SearchFilter {
    /// 搜索结果的两种「空」。
    enum Empty: Equatable {
        /// 没有任何数据（本来就没有）
        case noData
        /// 有数据，但没有一条匹配查询
        case noMatch(query: String)
    }

    /// 按关键词过滤。空查询 ⇒ 原样返回（不制造「搜索后 0 条」的假象）。
    ///
    /// 匹配规则刻意**简单且可预期**：大小写不敏感的子串。
    /// 上分词/模糊匹配会让「为什么搜不到」变得不可解释 —— 而用户搜不到
    /// 又不知道为什么，正是搜索最糟的失败方式。
    static func filter<T>(_ items: [T], query: String, key: (T) -> String) -> [T] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { key($0).localizedCaseInsensitiveContains(q) }
    }

    /// 结果为空时的原因。视图据此选文案 —— **不许一律显示「暂无 X」**。
    ///
    /// ⚠️ 刻意**不泛型**：它只关心两个数量，不需要元素类型。
    /// 写成泛型时 `T` 只出现在参数里、不出现在返回值里，
    /// Swift 会直接编译失败（`generic parameter 'T' is not used in function signature`）——
    /// 那条报错在提醒：这里本来就该是非泛型的。
    static func emptyReason(allCount: Int, shownCount: Int, query: String) -> Empty? {
        guard shownCount == 0 else { return nil }
        if allCount == 0 { return .noData }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // 查询是空的但结果空 ⇒ 只能是「本来就没有」
        return q.isEmpty ? .noData : .noMatch(query: q)
    }

    /// 空结果文案。两态必须给出**不同**的话，且都要给出下一步。
    static func emptyText(_ reason: Empty, noun: String, en: Bool = false) -> String {
        switch reason {
        case .noData:
            return en ? "No \(noun) yet" : "暂无\(noun)"
        case .noMatch(let q):
            // 说清「有东西但没匹配上」，并把查询原样回显，用户才知道自己搜了什么
            return en ? "No \(noun) matching \"\(q)\"" : "没有\(noun)匹配「\(q)」"
        }
    }

    /// 命中数量摘要，供 VoiceOver 与视觉提示共用。
    /// 搜到 0 条与没搜索过，文案不同。
    static func resultSummary(allCount: Int, shownCount: Int, noun: String, en: Bool = false) -> String? {
        if allCount == 0 { return nil }
        if shownCount == allCount { return nil }   // 没过滤，不需要额外说明
        return en ? "Matched \(shownCount) / \(allCount) \(noun)"
                  : "匹配 \(shownCount) / \(allCount) 个\(noun)"
    }
}
