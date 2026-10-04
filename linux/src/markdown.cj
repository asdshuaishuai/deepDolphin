// deepDolphin Linux 客户端 —— Markdown 块级解析。
//
// 与 macOS 端 `MarkdownParser.swift` 逐条对齐：同样的块类型、同样的判定顺序、
// 同样的行内记号剥离。**纯函数，无视图依赖** —— 解析是 CUI 构建闭包每帧都会碰到的
// 东西，它必须能不靠开窗口就测。
//
// 【为什么必须缓存】macOS 那边 `blocks` 原本是 `MarkdownView` 的
// computed property，于是 `body` 每求值一次就全量重解析一遍 ——
// 200KB 的 README 在滚动/布局时是**每帧**的主线程工作。
// CUI 的构建闭包同样是每帧跑，所以这里显式做记忆化，
// 而且记忆化**不跨文档**（缓存无上限会把用户读过的每篇文档都留在内存里）。
package deepdolphin_linux

import std.collection.*

// ---------------------------------------------------------------------------
// 块类型
// ---------------------------------------------------------------------------

public enum MdBlockKind {
    | Heading
    | Paragraph
    | Bullet
    | Numbered
    | Quote
    | Code
    | Divider
    | Table
}

public class MdBlock {
    public let kind: MdBlockKind
    /// 标题层级（Heading 才有意义）
    public let level: Int64
    /// 段落 / 列表项 / 引用行 / 表格行
    public let lines: ArrayList<String>
    /// 代码块正文
    public let code: String

    public init(kind: MdBlockKind, level!: Int64 = 0,
        lines!: ArrayList<String> = ArrayList<String>(), code!: String = "") {
        this.kind = kind
        this.level = level
        this.lines = lines
        this.code = code
    }
}

/// 块类型的名字。**判据用它把「解析产出的种类」与「渲染层覆盖的种类」
/// 两张表对上** —— 渲染层（`markdown_view.cj`）依赖 CUI，判据盯不到它的内部，
/// 唯一能验的就是「它声称自己画了哪几种」这张清单是不是真的齐。
public func mdKindName(k: MdBlockKind): String {
    return match (k) {
        case MdBlockKind.Heading => "heading"
        case MdBlockKind.Paragraph => "paragraph"
        case MdBlockKind.Bullet => "bullet"
        case MdBlockKind.Numbered => "numbered"
        case MdBlockKind.Quote => "quote"
        case MdBlockKind.Code => "code"
        case MdBlockKind.Divider => "divider"
        case MdBlockKind.Table => "table"
    }
}

/// `MdBlockKind` 的全集，判据拿它当「不允许漏」的一侧。
public func mdAllKindNames(): Array<String> {
    return [
        "heading", "paragraph", "bullet", "numbered",
        "quote", "code", "divider", "table"
    ]
}

public func mdBlockIs(a: MdBlock, b: MdBlockKind): Bool {
    return (match (a.kind) {
        case MdBlockKind.Heading => (match (b) { case MdBlockKind.Heading => true; case _ => false })
        case MdBlockKind.Paragraph => (match (b) { case MdBlockKind.Paragraph => true; case _ => false })
        case MdBlockKind.Bullet => (match (b) { case MdBlockKind.Bullet => true; case _ => false })
        case MdBlockKind.Numbered => (match (b) { case MdBlockKind.Numbered => true; case _ => false })
        case MdBlockKind.Quote => (match (b) { case MdBlockKind.Quote => true; case _ => false })
        case MdBlockKind.Code => (match (b) { case MdBlockKind.Code => true; case _ => false })
        case MdBlockKind.Divider => (match (b) { case MdBlockKind.Divider => true; case _ => false })
        case MdBlockKind.Table => (match (b) { case MdBlockKind.Table => true; case _ => false })
    })
}

// ---------------------------------------------------------------------------
// 记忆化
// ---------------------------------------------------------------------------

/// 缓存条数上限。**与对话条数同量级**（R4-07）：对话流对每条助手消息各渲染
/// 一份 Markdown（`aiMessageRow` → `mdView` → `mdBlocks`），5 条消息就能把
/// 上限 4 的缓存打穿 —— 命中率趋近 0，滚动一次就全量重解析一遍，
/// 恰是本文件头注释里要避免的那个「每帧的代价」。64 条覆盖真实长对话；
/// 单条是块数组，内存上界仍然有限。
private let MEMO_MAX: Int64 = 64
private var memoKeys = ArrayList<Int64>()
private var memoVals = ArrayList<ArrayList<MdBlock>>()
private var parseCount: Int64 = 0

/// 真正跑过 `mdParse` 的次数。
///
/// **只给判据用**，界面上不显示。它是记忆化唯一能被外部观测到的证据 ——
/// 解析结果长得一模一样，「这次是命中缓存还是又重解析了一遍」从返回值上看不出来，
/// 光断言「两次调用结果相等」等于什么都没断言。
public func mdParseCount(): Int64 {
    return parseCount
}

/// 文本指纹：**全字节**双多项式哈希（两个 31 位素数模，合成约 62 位）。
///
/// ⚠ 必须扫**每一个**字节（R4-07）。旧版只采「长度 + 头尾各 64 字节」，
/// 于是「同长度、头尾一致、中间不同」的两段正文**必然**同键 ——
/// 对话流里就是 A 消息的解析结果被画在 B 消息上，而且注释还要求
/// 「改完文档显式调 mdMemoReset」，全仓却没有一个生产调用点。
/// 改成全字节哈希后，同键不同文只剩哈希碰撞一种可能（~2^-62）。
///
/// 为什么不是 FNV-1a 一类的 64 位回绕哈希：仓颉的 `*` 溢出是**报错**
/// （编译期常量直接拒，运行期抛），本工具链没有可用的回绕乘法；
/// 模素数的两项乘积都稳在 Int64 之内，不借助任何未定义行为。
private func mdFingerprint(text: String): Int64 {
    let bytes = text.toArray()
    var h1: Int64 = 7
    var h2: Int64 = 11
    for (b in bytes) {
        h1 = (h1 * 131 + Int64(b)) % 2147483647    // 2^31 - 1
        h2 = (h2 * 137 + Int64(b)) % 2147483629    // 另一个 31 位素数
    }
    return h1 * 2147483629 + h2
}

/// 解析（带记忆化）。
public func mdBlocks(text: String): ArrayList<MdBlock> {
    let key = mdFingerprint(text)
    for (i in 0..memoKeys.size) {
        if (memoKeys[i] == key) {
            return memoVals[i]
        }
    }
    let parsed = mdParse(text)
    parseCount += 1
    memoKeys.add(key)
    memoVals.add(parsed)
    if (memoKeys.size > MEMO_MAX) {
        // 显式重建而不是「按起点 + 个数」删：仓颉 `ArrayList` 那个方法收的是
        // **闭区间**（实测 `x.remove(0..2)` 删掉 3 个元素），
        // 而按 (from, count) 调用又编译不过 ——
        // 两种写法都得先在心里过一遍「它含不含右端」，重建没有这个歧义。
        let keepKeys = ArrayList<Int64>()
        let keepVals = ArrayList<ArrayList<MdBlock>>()
        let drop = memoKeys.size - MEMO_MAX
        for (i in drop..memoKeys.size) {
            keepKeys.add(memoKeys[i])
            keepVals.add(memoVals[i])
        }
        memoKeys = keepKeys
        memoVals = keepVals
    }
    return parsed
}

/// 缓存清空。**给判据用**：每条判据都要从干净缓存数起，不然上一条判据
/// 解析过的文本会污染本条的 `mdParseCount`。指纹已是全字节哈希，
/// 生产路径不再需要「改完文档手动失效」这种纪律。
public func mdMemoReset(): Unit {
    memoKeys = ArrayList<Int64>()
    memoVals = ArrayList<ArrayList<MdBlock>>()
}

// ---------------------------------------------------------------------------
// 解析
// ---------------------------------------------------------------------------

/// 整篇解析。纯函数。
///
/// 判定顺序照抄 macOS 端：代码块 → 标题 → 分隔线 → 表格 → 引用 →
/// 无序列表 → 有序列表 → 段落。顺序是有意义的：`**粗**` 会被段落吞掉，
/// 而 `>` 必须在段落之前判，否则引用行会变成普通文字。
public func mdParse(text: String): ArrayList<MdBlock> {
    let out = ArrayList<MdBlock>()
    let lines = text.split("\n")
    var i: Int64 = 0
    let n = Int64(lines.size)

    while (i < n) {
        let trimmed = lines[i].trimAscii()

        if (trimmed.isEmpty()) {
            i += 1
            continue
        }

        // 代码块
        if (trimmed.startsWith("```")) {
            let body = ArrayList<String>()
            i += 1
            while (i < n && !lines[i].trimAscii().startsWith("```")) {
                body.add(lines[i])
                i += 1
            }
            i += 1
            let sb = StringBuilder()
            for (k in 0..body.size) {
                // ⚠ 这里必须是**真换行**。写成 "\\n" 拼出来的是字面的反斜杠+n，
                // 判据 `codeFenceIsTakenWholeInsteadOfBeingReadAsText` 就是逮这一条的。
                if (k > 0) { sb.append("\n") }
                sb.append(body[k])
            }
            out.add(MdBlock(MdBlockKind.Code, code: sb.toString()))
            continue
        }

        // 标题
        match (mdHeadingLevel(trimmed)) {
            case Some(level) =>
                // ⚠ 必须把 # 之后的空格一起去掉（`trimAscii` 不能省）。
                // 只 dropFirst(level) 的话每个标题都带一个前导空格，
                // 渲染出来全部往右缩进一点 —— macOS 那边就是这样被断言逮到的，
                // 也正是把解析器抽成可测纯函数的收益。
                out.add(MdBlock(MdBlockKind.Heading, level: level,
                    lines: linesOf1(mdStripInline(trimmed[level..].trimAscii()))))
                i += 1
                continue
            case None => ()
        }

        // 分隔线
        if (trimmed == "---" || trimmed == "***" || trimmed == "___") {
            out.add(MdBlock(MdBlockKind.Divider))
            i += 1
            continue
        }

        // 表格：含 | 的行，且下一行也以 | 开头 —— 整块按等宽处理
        if (trimmed.contains("|") && i + 1 < n && lines[i + 1].trimAscii().startsWith("|")) {
            let rows = ArrayList<String>()
            while (i < n && lines[i].trimAscii().startsWith("|")) {
                rows.add(lines[i].trimAscii())
                i += 1
            }
            out.add(MdBlock(MdBlockKind.Table, lines: rows))
            continue
        }

        // 引用
        if (trimmed.startsWith(">")) {
            let body = ArrayList<String>()
            while (i < n && lines[i].trimAscii().startsWith(">")) {
                body.add(mdStripInline(lines[i].trimAscii()[1..].trimAscii()))
                i += 1
            }
            out.add(MdBlock(MdBlockKind.Quote, lines: body))
            continue
        }

        // 无序列表（- / * / +，含引擎托管区域标记行）
        if (mdIsBullet(trimmed)) {
            let items = ArrayList<String>()
            while (i < n) {
                let raw = lines[i]
                let t = raw.trimAscii()
                if (mdIsBullet(t)) {
                    items.add(mdStripInline(t[2..]))
                    i += 1
                } else if (mdIsIndentedContinuation(raw) && !items.isEmpty()) {
                    // 缩进续行并入上一项
                    items[items.size - 1] = items[items.size - 1] + " " + mdStripInline(t)
                    i += 1
                } else {
                    break
                }
            }
            out.add(MdBlock(MdBlockKind.Bullet, lines: items))
            continue
        }

        // 有序列表
        match (mdNumberedPrefix(trimmed)) {
            case Some(prefixLen) =>
                let items = ArrayList<String>()
                while (i < n) {
                    let raw = lines[i]
                    let t = raw.trimAscii()
                    match (mdNumberedPrefix(t)) {
                        case Some(pl) =>
                            // ⚠ **序号必须留着**。只把前缀切掉的话 `1. 拉分支` 会渲染成
                            // 光秃秃的「拉分支」，一份编号清单在界面上就看不出是清单了。
                            // `12)` 这种分隔符统一规范化成 `12. `。
                            items.add("${mdNumberedValue(t)}. " + mdStripInline(t[pl..].trimAscii()))
                            i += 1
                        case None =>
                            if (mdIsIndentedContinuation(raw) && !items.isEmpty()) {
                                // 同无序列表：缩进续行并入上一项
                                items[items.size - 1] = items[items.size - 1] + " " + mdStripInline(t)
                                i += 1
                            } else {
                                break
                            }
                    }
                }
                out.add(MdBlock(MdBlockKind.Numbered, lines: items))
                continue
            case None => ()
        }

        // 段落（连续非空行）。**遇到任何块级起始就断** ——
        // 不断的话一个 `## 标题` 会被并进上一段。
        let para = ArrayList<String>()
        while (i < n) {
            let t = lines[i].trimAscii()
            let startsBlock = t.isEmpty() || mdIsHeading(t) || t.startsWith("```") || t.startsWith(">") ||
                mdIsBullet(t) || mdIsDivider(t) || mdNumberedPrefix(t).isSome()
            if (startsBlock) {
                break
            }
            para.add(mdStripInline(t))
            i += 1
        }
        if (!para.isEmpty()) {
            out.add(MdBlock(MdBlockKind.Paragraph, lines: para))
        }
    }
    return out
}

private func linesOf1(s: String): ArrayList<String> {
    let a = ArrayList<String>()
    a.add(s)
    return a
}

private func mdIsBullet(t: String): Bool {
    return t.startsWith("- ") || t.startsWith("* ") || t.startsWith("+ ")
}

private func mdIsDivider(t: String): Bool {
    return t == "---" || t == "***" || t == "___"
}

/// 缩进续行（列表项的悬挂缩进）。**入参必须是未 trim 的原行**。
///
/// ⚠ 判据盯的就是这里：写成 `t.startsWith("  ")` 而 `t` 已经是 `trimAscii()` 过的，
/// 那个条件**永远为 false** —— 整个续行分支是死代码，写了等于没写。
/// macOS 端 `MarkdownParser.swift:120` 就是这么写的，两端一致地错，
/// 所以纯看代码发现不了；本端按真实 README 的形状补上。
private func mdIsIndentedContinuation(raw: String): Bool {
    if (raw.isEmpty()) {
        return false
    }
    if (raw.size == raw.trimAscii().size) {
        return false
    }
    return raw.startsWith(" ") || raw.startsWith("\t")
}

private func mdIsHeading(t: String): Bool {
    return mdHeadingLevel(t).isSome()
}

/// `# ` 到 `###### `。**# 之后必须是空格**，否则 `###hashtag` 会被当成标题。
public func mdHeadingLevel(s: String): Option<Int64> {
    var cnt: Int64 = 0
    for (r in s.runes()) {
        if (r.toString() == "#") {
            cnt += 1
        } else {
            break
        }
    }
    if (cnt >= 1 && cnt <= 6 && s.size > cnt) {
        // 第 cnt 个**字节**必须是空格
        if (s.toArray()[cnt] == 0x20u8) {
            return Some(cnt)
        }
    }
    return None
}

/// `1. ` / `2) ` 的前缀**长度**（含分隔符）。None = 不是有序列表项。
///
/// ⚠ 上界是 4 位（macOS 端 `n < 5`）：`2026-06` 这种日期开头不该被当序号。
public func mdNumberedPrefix(s: String): Option<Int64> {
    var cnt: Int64 = 0
    for (r in s.runes()) {
        let c = r.toString()
        if (c >= "0" && c <= "9") {
            cnt += 1
        } else {
            break
        }
    }
    if (cnt > 0 && cnt < 5 && s.size >= cnt + 2) {
        let b = s.toArray()
        if (b[cnt] == 0x2eu8 && b[cnt + 1] == 0x20u8) {
            return Some(cnt + 2)
        }
        if (b[cnt] == 0x29u8 && b[cnt + 1] == 0x20u8) {
            return Some(cnt + 2)
        }
    }
    return None
}

/// 前缀里那串数字的**数值**：`1. ` → 1，`12) ` → 12。
///
/// 渲染时要留序号（`mdNumberedPrefix` 只回答「是不是列表项、前缀多长」），
/// 而序号得是数值 —— `007. ` 显示成 `7. `。
private func mdNumberedValue(s: String): Int64 {
    var v: Int64 = 0
    for (r in s.runes()) {
        let c = r.toString()
        if (c >= "0" && c <= "9") {
            v = v * 10 + (Int64(c.toArray()[0]) - 48)
        } else {
            break
        }
    }
    return v
}

/// 剥离行内记号：`[t](u)` → `t`，`**` `__` `` ` `` 去掉。
///
/// 顺序照抄 macOS 端：先处理链接，再去强调/代码记号。
/// 反过来会在链接 URL 里含 `**` 时先把它吃掉，链接就拼不回去了。
public func mdStripInline(s: String): String {
    var t = s
    while (true) {
        match (mdFindFirst(t, "[")) {
            case None => break
            case Some(start) =>
                match (mdFindFrom(t, "](", start + 1)) {
                    case None => break
                    case Some(mid) =>
                        match (mdFindFrom(t, ")", mid + 2)) {
                            case None => break
                            case Some(end) =>
                                let label = t[start + 1..mid]
                                t = t[0..start] + label + t[end + 1..]
                                continue
                        }
                }
        }
    }
    t = mdReplaceAll(t, "**", "")
    t = mdReplaceAll(t, "__", "")
    t = mdReplaceAll(t, "`", "")
    return t
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

/// 找子串首字节下标。None = 没有。
public func mdFindFirst(s: String, sub: String): Option<Int64> {
    return mdFindFrom(s, sub, 0)
}

/// 从 `from` 起找子串首字节下标。
public func mdFindFrom(s: String, sub: String, from: Int64): Option<Int64> {
    let hay = s.toArray()
    let needle = sub.toArray()
    if (needle.isEmpty() || needle.size > hay.size) {
        return None
    }
    var i = if (from < 0) { 0 } else { from }
    while (i + needle.size <= hay.size) {
        var matched = true
        for (j in 0..needle.size) {
            if (hay[i + j] != needle[j]) {
                matched = false
                break
            }
        }
        if (matched) {
            return Some(i)
        }
        i += 1
    }
    return None
}

/// 全部替换。仓颉的 `String` 没有 `replaceAll`。
public func mdReplaceAll(s: String, from: String, to: String): String {
    let sb = StringBuilder()
    var i: Int64 = 0
    let n = Int64(s.size)
    while (i < n) {
        match (mdFindFrom(s, from, i)) {
            case Some(at) =>
                sb.append(s[i..at])
                sb.append(to)
                i = at + Int64(from.size)
            case None =>
                sb.append(s[i..n])
                i = n
        }
    }
    return sb.toString()
}
