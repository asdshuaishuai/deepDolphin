// deepDolphin Linux 客户端 —— Markdown **渲染层**。
//
// ⚠⚠ 上一轮这里**压根没有渲染器**，而且缺得很难看：
// `mdBlocks(...)` 被直接当语句写在 VStack 里，但它只返回一个
// `ArrayList<MdBlock>`、**不发任何控件** —— 编译器会把它标成
// `warning: unused expression`（`ai_view.cj:119` 与 `:540` 两处都在警告里）。
// 后果是：C6 的助手/用户正文与 C5 的结果正文**一个字都不画**，
// 界面上只剩一条角色标签和一个标题。
//
// 【这一层为什么必须有判据】解析层可以脱离窗口测，渲染层不行；
// 于是「每种块都真的画了控件」这件事在真窗口点亮之前是**没有证据**的。
// 所以本文件把「哪些块类型被覆盖」做成一个可断言的清单
// （`mdRenderedKinds`），判据直接比对它与 `MdBlockKind` 的全集 ——
// 将来加一种块而忘了画，判据会红。
//
// 【与 macOS 端 `MarkdownView.swift` 的对应】块类型一一对应，间距 7，
// 标题字号 22/18/15/14 照抄那边。**刻意不套用 `tokens.cj` 的 22/20/16/13** ——
// 那套刻度是面板外壳用的；macOS 端 MarkdownView 自己也是 22/18/15/14，
// 两端都存在「正文刻度 + markdown 刻度」并存的情况。跟着 macOS 走才是一致。
package deepdolphin_linux

import std.collection.*
import cui.{Axis, CrossAxisAlignment, Divider, FontWeight, HStack, Label, LengthUnits,
    Panel, VStack, Widget}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------

/// 整段文本 → 一个可放进 VStack 的控件。
///
/// 走 `mdBlocks`（带记忆化）：CUI 的构建闭包每帧都会跑到这里，
/// 200KB 的 README 每帧重解析一次是主线程上白烧的 CPU。
public func mdView(text: String, dark: Bool): Widget {
    return mdBlocksView(mdBlocks(text), dark)
}

/// 已解析的块 → 控件。
public func mdBlocksView(blocks: ArrayList<MdBlock>, dark: Bool): Widget {
    return VStack {
        for (b in blocks) {
            mdBlockView(b, dark)
        }
    }.spacing(7.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
}

/// 本渲染层**覆盖到的块类型**。判据拿它和 `MdBlockKind` 全集比对，
/// 少一种就红 —— 「加了个新块类型但忘了画控件」是这里最可能犯的错。
public func mdRenderedKinds(): Array<String> {
    return ["heading", "paragraph", "bullet", "numbered", "quote", "code", "divider", "table"]
}

// ---------------------------------------------------------------------------
// 单块
// ---------------------------------------------------------------------------

/// 标题字号。照抄 macOS 端 `MarkdownView.fontSize(for:)`。
private func mdHeadingSize(level: Int64): Float32 {
    return match (level) {
        case 1 => 22.0
        case 2 => 18.0
        case 3 => 15.0
        case _ => 14.0
    }
}

/// 标题前的留白：一二级给 8，三级以下给 4。
/// 没有它，一份简报里连着三个标题会糊成一块。
private func mdHeadingTopPad(level: Int64): Float64 {
    return (if (level <= 2) { 8.0 } else { 4.0 })
}

private func mdBlockView(b: MdBlock, dark: Bool): Widget {
    // 逐个 case 展开而不是「默认当段落」：漏画一种会静默变成一段正文，
    // 看起来像「解析错了」，排查方向从一开始就跑偏。
    if (mdBlockIs(b, MdBlockKind.Heading)) {
        return Label(b.lines[0])
            .fontSize(mdHeadingSize(b.level))
            .fontWeight(FontWeight.semiBold)
    }
    if (mdBlockIs(b, MdBlockKind.Paragraph)) {
        // macOS 端把多行用空格接成一段。这里同理 ——
        // 一段话拆成好几个 Label 会让段间距比行距还大。
        return Label(joinWithSpace(b.lines))
            .fontSize(fsBody()).wrap()
    }
    if (mdBlockIs(b, MdBlockKind.Bullet)) {
        return mdListView(b, true)
    }
    if (mdBlockIs(b, MdBlockKind.Numbered)) {
        return mdListView(b, false)
    }
    if (mdBlockIs(b, MdBlockKind.Quote)) {
        return mdQuoteView(b, dark)
    }
    if (mdBlockIs(b, MdBlockKind.Code)) {
        return mdMonoBlock(splitLines(b.code), dark)
    }
    if (mdBlockIs(b, MdBlockKind.Table)) {
        return mdMonoBlock(b.lines, dark)
    }
    // 分隔线没有内容，只有线
    return Divider()
}

// ---------------------------------------------------------------------------
// 列表
// ---------------------------------------------------------------------------

/// 列表项。无序带一个圆点，有序不带 —— 序号已经写进文本里了
/// （`mdNumberedPrefix` 那条修复就是为了让序号不被切掉）。
private func mdListView(b: MdBlock, dotted: Bool): Widget {
    return VStack {
        for (item in b.lines) {
            HStack {
                if (dotted) {
                    dsDot(dsColor(C_ACCENT))
                }
                Label(item).fontSize(fsBody()).wrap()
            }.spacing(7.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
        }
    }.spacing(4.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
}

// ---------------------------------------------------------------------------
// 引用
// ---------------------------------------------------------------------------

/// 引用：左侧一条竖线 + 弱化正文。
///
/// 用 `Divider(axis: Vertical)` 当竖线：它在 HStack 里天然与右列等高，
/// 而画一个 3vp 宽的 Panel 想让它撑满高度，得靠交叉轴拉伸 ——
/// CUI 没有这个修饰符，写出来的是一根 3vp 的小方块，不是竖线。
private func mdQuoteView(b: MdBlock, dark: Bool): Widget {
    return HStack {
        Divider(axis: Axis.Vertical, color: dsColor(C_ACCENT).withAlpha(130))
        VStack {
            for (line in b.lines) {
                Label(line).fontSize(fsBody()).muted().wrap()
            }
        }.spacing(3.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
    // 间距 10 = macOS 端那条 `.padding(.leading, 10)` 的净效果。
    // ⚠ 中间**不要套 Panel** 去凑这个左边距：CUI 只有 Panel 有 padding，
    // 而没设 style 的 Panel 会带出一层底色，macOS 端引用块是**没有底色**的。
    }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
}

// ---------------------------------------------------------------------------
// 等宽块（代码 / 表格）
// ---------------------------------------------------------------------------

/// 代码块与表格共用：等宽 + 带一层表面。
///
/// ⚠ **这里刻意不套内层 `ScrollView`**。macOS 端对代码块/表格用的是
/// 横向 `ScrollView`，本端做不到等价：CUI 的 `ScrollView` **只有
/// `scrollState`，没有 `hug()`**，无法按内容定高。硬套上去的后果是
/// 快照上「正文画到表格就断了」—— 它之后的兄弟节点全被挤成零高，
/// 看着像解析漏了块（实测过）。改成靠外层竖向滚动 + `Label.wrap()` 换行：
/// 少一层嵌套，少一类压不出来的布局。
///
/// 表格**不拆列**。引擎 `context` 里的分支表一行能到 100+ 字符，
/// 拆列就得自己算列宽，而中文与等宽混排的列宽在 CUI 里没有可靠的测量接口 ——
/// 算错了比不拆更难看。
private func mdMonoBlock(lines: ArrayList<String>, dark: Bool): Widget {
    return Panel {
        VStack {
            for (line in lines) {
                Label(line).fontFamily("monospace").fontSize(fsLabel()).wrap()
            }
        }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
    }.style(dsSurface(DsLevel.Nested, dark)).contentPadding(10.vp).hug()
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

private func joinWithSpace(lines: ArrayList<String>): String {
    let sb = StringBuilder()
    for (i in 0..lines.size) {
        if (i > 0) { sb.append(" ") }
        sb.append(lines[i])
    }
    return sb.toString()
}

private func splitLines(s: String): ArrayList<String> {
    let out = ArrayList<String>()
    for (l in s.split("\n")) {
        out.add(l)
    }
    return out
}
