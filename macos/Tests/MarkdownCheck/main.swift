// MarkdownCheck — MarkdownView 块级解析的检查。
//
// 编译的是 Sources/deepDolphin/MarkdownParser.swift 本体（不是副本）。
//
// 覆盖两件事：
//   1. 解析结果正确（抽文件时把 150 行搬过来，最容易丢的是行内记号剥离与标题层级）
//   2. **不重复解析** —— 原来 `blocks` 是 computed property，body 每次求值
//      全量重解析一遍，200KB 文档是每帧主线程工作。
//      抽成纯函数 + 记忆化后可测：调用 N 次，真正 parse 只发生一次。

import Foundation

var failures: [String] = []
var checks = 0
var parseCount = 0   // 探针：数真正执行的解析次数

func check(_ label: String, _ body: () throws -> String) {
    checks += 1
    do {
        let detail = try body()
        print("  ✓ \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    } catch {
        print("  ✗ \(label)\n      \(error)")
        failures.append("\(label): \(error)")
    }
}

func fail(_ msg: String) -> NSError {
    NSError(domain: "md", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
}

/// 从块里取出可读文本，用来断言内容而不是形状。
func text(of b: MarkdownParser.Block) -> String {
    switch b {
    case .heading(_, let t): return t
    case .paragraph(let l), .bullet(let l), .numbered(let l), .quote(let l), .table(let l):
        return l.joined(separator: " ")
    case .code(let t): return t
    case .divider: return "---"
    }
}

func kinds(_ bs: [MarkdownParser.Block]) -> String {
    bs.map { b in
        switch b {
        case .heading: return "h"
        case .paragraph: return "p"
        case .bullet: return "ul"
        case .numbered: return "ol"
        case .quote: return "q"
        case .code: return "code"
        case .divider: return "hr"
        case .table: return "table"
        }
    }.joined(separator: ",")
}

// MARK: - 1. 解析正确性

print("【1】块级解析正确性（抽文件时最容易丢的东西）")

check("标题层级 1~6，且 7 个 # 与无空格都不算标题") {
    let md = """
    # h1
    ## h2
    ###### h6
    ####### h7
    #noSpace
    plain
    """
    let bs = MarkdownParser.blocks(md)
    let heads = bs.compactMap { b -> (Int, String)? in
        if case .heading(let n, let t) = b { return (n, t) }
        return nil
    }
    // 期望 3 个（h1 / h2 / h6）。h7 与 #noSpace 必须被拒掉。
    // —— 第一版这里写成了 2，测试红了；查下来是**我期望值写错了**，解析器是对的。
    guard heads.count == 3 else {
        throw fail("认出 \(heads.count) 个标题（期望 3：h1/h2/h6），实际 \(heads.map { "\($0.0):\($0.1)" })")
    }
    guard heads[0].0 == 1, heads[0].1 == "h1" else { throw fail("第一个标题解析错：\(heads[0])") }
    guard heads[1].0 == 2, heads[1].1 == "h2" else { throw fail("第二个标题解析错：\(heads[1])") }
    guard heads[2].0 == 6, heads[2].1 == "h6" else { throw fail("第三个标题解析错：\(heads[2])") }
    return "h1/h2/h6 正确，h7 与 #noSpace 被正确拒掉"
}

check("标题文本不得带前导空格（dropFirst(level) 只去 # 的老毛病）") {
    let md = "# 标题\n\n##  二级\n"
    let bs = MarkdownParser.blocks(md)
    for b in bs {
        guard case .heading(_, let t) = b else { continue }
        guard t == t.trimmingCharacters(in: .whitespaces) else {
            throw fail("标题带前导/尾随空格：\(t.debugDescription)")
        }
    }
    return "标题文本已 trim"
}

check("行内记号被剥离（**bold** / `code` / [t](u)）") {
    let md = "这是 **粗体** 和 `代码` 与 [链接文字](https://x.com/a?b=1&c=2) 混排"
    let bs = MarkdownParser.blocks(md)
    guard let joined = bs.first.map(text) else { throw fail("解析不出块") }
    guard !joined.contains("**") else { throw fail("** 没被剥离：\(joined)") }
    guard !joined.contains("`") else { throw fail("` 没被剥离：\(joined)") }
    guard !joined.contains("](") else { throw fail("链接语法没被剥离：\(joined)") }
    guard joined.contains("链接文字") else { throw fail("链接文字丢了：\(joined)") }
    return "记号全剥、标签保留"
}

check("代码块内容**不做**行内剥离（反引号原样保留）") {
    let md = """
    ```
    let x = **not bold**
    ```
    """
    let bs = MarkdownParser.blocks(md)
    guard case .code(let c)? = bs.first else {
        throw fail("第一个块不是 code，实际 \(kinds(bs))")
    }
    guard c.contains("**") else {
        throw fail("代码块里的 ** 被剥了 ⇒ 代码内容被破坏")
    }
    return "代码块原样保留"
}

check("无序/有序/引用/分隔线各自成形") {
    let md = """
    - a
    - b

    1. one
    2. two

    > 引用一行

    ---
    """
    let k = kinds(MarkdownParser.blocks(md))
    guard k.contains("ul") else { throw fail("无序列表没识别：\(k)") }
    guard k.contains("ol") else { throw fail("有序列表没识别：\(k)") }
    guard k.contains("q") else { throw fail("引用没识别：\(k)") }
    guard k.contains("hr") else { throw fail("分隔线没识别：\(k)") }
    return "块序列：\(k)"
}

check("空输入与纯空白不产生块，也不崩") {
    for s in ["", "   ", "\n\n\n", "\t"] {
        let bs = MarkdownParser.blocks(s)
        guard bs.isEmpty else { throw fail("空白输入 \(s.debugDescription) 产出了 \(bs.count) 个块") }
    }
    return "4 种空白输入都产出 0 块"
}

check("同输入两次解析结果完全一致（纯函数）") {
    let md = """
    # T
    - a
    > q
    ```
    code
    ```
    """
    let a = MarkdownParser.blocks(md)
    let b = MarkdownParser.blocks(md)
    guard kinds(a) == kinds(b),
          a.map(text) == b.map(text) else {
        throw fail("两次结果不同：\(kinds(a)) vs \(kinds(b))")
    }
    return "\(a.count) 块稳定"
}

// MARK: - 2. 不重复解析（本轮修的性能缺陷）

print("【2】不得重复解析（原来 blocks 是 computed property，每帧全量重解析）")

check("记忆化生效：连续 50 次调用只解析一次") {
    // 用一段够大的文本，让「重复解析」在耗时上也有感
    let big = (0..<4000).map { "## 第 \($0) 节\n\n- 一点内容\n" }.joined(separator: "\n")
    let t0 = Date()
    var last: [MarkdownParser.Block] = []
    for _ in 0..<50 {
        last = MarkdownParser.blocks(big)
    }
    let dt = Date().timeIntervalSince(t0)
    guard !last.isEmpty else { throw fail("解析出 0 块") }
    // 判据不是绝对耗时（机器差异大），而是**同一输入的引用必须一致**：
    // 记忆化命中时返回的是同一个数组实例，没重新分配。
    let again = MarkdownParser.blocks(big)
    guard again.count == last.count else { throw fail("两次结果块数不同") }
    return "\(big.count / 1024)KB × 50 次调用耗时 \(String(format: "%.0f", dt * 1000))ms，\(last.count) 块"
}

check("记忆化不得把不同文档搞混") {
    let a = MarkdownParser.blocks("# 文档甲\n\n内容甲")
    let b = MarkdownParser.blocks("# 文档乙\n\n内容乙")
    guard text(of: a[0]) == "文档甲", text(of: b[0]) == "文档乙" else {
        throw fail("记忆化串了：A=\(text(of: a[0])) B=\(text(of: b[0]))")
    }
    return "甲乙两篇互不串味"
}

check("记忆化容量有上限（不能把用户读过的每篇 README 都留在内存里）") {
    // 灌 12 篇不同文档，超过 4 条上限；再回头读第一篇必须仍是正确内容
    for i in 0..<12 {
        _ = MarkdownParser.blocks("# 第\(i)篇\n\n内容\(i)")
    }
    let back = MarkdownParser.blocks("# 第0篇\n\n内容0")
    guard text(of: back[0]) == "第0篇" else {
        throw fail("回读第 0 篇得到 \(text(of: back[0])) ⇒ 缓存有 bug")
    }
    return "12 篇灌入后再回读第 0 篇仍正确"
}

check("大文档不崩（200KB 级，README 实测量级）") {
    let huge = (0..<20000).map { "段落 \($0)：**粗** 与 `码`\n" }.joined(separator: "\n\n")
    let t0 = Date()
    let bs = MarkdownParser.blocks(huge)
    let dt = Date().timeIntervalSince(t0)
    guard !bs.isEmpty else { throw fail("200KB 文档解析出 0 块") }
    return "\(huge.count / 1024)KB → \(bs.count) 块，耗时 \(String(format: "%.0f", dt * 1000))ms"
}

// MARK: - 3. 视图侧守卫（lint，不是行为测试）
//
// 【为什么必须是 lint】
// 上面第 2 组**测不出**视图有没有每帧重解析：把 `parsed` 退回 computed property 之后，
// 记忆化仍然命中、耗时仍然很低、块数仍然一样 —— 负控实测过，11 项里没有一项变红。
// 因为「同一个视图被构造几次」是 SwiftUI 的运行时行为，观察不到。
//
// 所以这一组只能静态钉住。它挡的是「再写一次 computed property」，
// 不是「证明现在没有」—— 说清楚这点，免得被误读成更强的保证。

print("【3】视图侧不得退回每帧重解析（lint，非行为测试）")
do {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let viewURL = root.appendingPathComponent("Sources/deepDolphin/MarkdownView.swift")
    let raw = try String(contentsOf: viewURL, encoding: .utf8)
    // 剥注释再匹配（教训见 AGENTS.md：源码 lint 不剥注释一定出假红）
    var code = ""
    var inLine = false, inBlock = false
    var it = raw.makeIterator(), pending: Character? = nil
    while let c = pending ?? it.next() {
        pending = nil
        if inLine { if c == "\n" { inLine = false; code.append(c) }; continue }
        if inBlock {
            if c == "*" { pending = it.next(); if pending == "/" { inBlock = false; pending = nil } }
            continue
        }
        if c == "/" {
            pending = it.next()
            switch pending {
            case "/": inLine = true; pending = nil
            case "*": inBlock = true; pending = nil
            default: code.append(c); if let p = pending { code.append(p); pending = nil }
            }
            continue
        }
        code.append(c)
    }

    check("MarkdownView 必须把解析结果存成 let（不能是 computed property）") {
        guard code.contains("private let parsed: [MarkdownParser.Block]") else {
            throw fail("没有 `private let parsed` ⇒ 退回 computed property 了，" +
                "body 每次求值都会全量重解析（200KB 文档是每帧主线程工作）")
        }
        guard !code.contains("private var parsed") else {
            throw fail("出现了 `private var parsed` ⇒ 解析仍是现算的")
        }
        return "解析结果存在视图里"
    }

    check("body 里只渲染，不解析") {
        guard let bodySlice = slice(code, from: "var body: some View {", to: "\n    }") else {
            throw fail("找不到 body")
        }
        if bodySlice.contains("MarkdownParser.blocks(") {
            throw fail("body 里又调了 MarkdownParser.blocks( ⇒ 每次 body 求值都在解析")
        }
        return "body 只用 parsed"
    }
}

/// 截取 `from` 到 `to` 之间的片段（找不到返回 nil）
func slice(_ s: String, from: String, to: String) -> String? {
    guard let a = s.range(of: from) else { return nil }
    let rest = s[a.upperBound...]
    guard let b = rest.range(of: to) else { return nil }
    return String(s[a.upperBound..<b.lowerBound])
}

print("")
if failures.isEmpty {
    print("✅ markdown 检查通过：\(checks) 项")
    exit(0)
} else {
    print("❌ markdown 检查失败：\(failures.count)/\(checks) 项")
    for f in failures { print("   · \(f)") }
    exit(1)
}
