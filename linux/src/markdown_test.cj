// deepDolphin Linux 客户端 —— Markdown 块级解析判据。
//
// 【夹具从哪来】全部是**逐字真实输出**，不是照着「典型 markdown」手写的：
// - REAL_CONTEXT：本机 `moongit context --json` 的 `context` 字段第 1-37 行原文
// - REAL_README：本仓库 `linux/README.md`「与 macOS 端的已知差异」小节原文
//
// 【为什么要照抄真实输出】第一版夹具是手编的，结果里面写了一句
// 「引擎托管区域里常见缩进续行」—— 拿引擎真实输出量了一遍，**0 行**。
// 那句话是凭想象写的。手编夹具会把「我以为的输入形状」和「真实输入形状」
// 一起锁进判据里，两者不一致时判据全绿而界面照旧难看。
package deepdolphin_linux

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/// 引擎 `moongit context --json` → `context` 字段第 1-37 行（本机实测原文）。
///
/// 结构（独立于实现、按 GFM 规则数出来）：13 块 =
/// 标题×6（层级 1,2,2,3,3,3）+ 引用×1 + 无序列表×4（2/4/2/4 共 12 项）+ 表格×2（各 3 行）。
private let REAL_CONTEXT = """
# moonGit 项目群上下文

> 生成于 2026-10-03 19:31 · 引擎为 AI 无关内核，以下为确定性事实

## 总览

- 项目 15 个 · 近 7 天活跃 9 · 有未提交改动 7
- 分支 22 · 待合入 4 · 未跟踪文件 20 · stash 2

## 项目速览

### deeporca-site

- 路径：/Volumes/data/dev/coding/deeporca-site
- 现状：main: 活跃
- 分支：当前 main · 默认 main
- 提交构成（全部 14 条）：feat ×4 · fix ×4 · docs ×2 · other ×4

| 分支 | 状态 | 待记录 | 最近提交 |
|---|---|---|---|
| ▸main | 闲置 | 0 | 3 天前 merge: 合入远端 5 个提交，保留 deepDesign v6.0 内容与纸感主题 |

### moonviz-promo

- 路径：/Volumes/data/dev/coding/deeporca-site/moonviz-promo（非 git）
- 现状：2 天内有改动 · 非 git 项目 · 1 个文件

### system1

- 路径：/Volumes/data/dev/coding/deeporca-site/x-studio/system1
- 现状：main: 闲置
- 分支：当前 main · 默认 main
- 提交构成（全部 2 条）：other ×2

| 分支 | 状态 | 待记录 | 最近提交 |
|---|---|---|---|
| ▸main | 闲置 | 0 | 11 天前 移除调试残留 ui_flow_test.mjs（临时 playwright 脚本，不入库） |
"""

/// 本仓库 `linux/README.md` 第 171-188 行原文。
///
/// 这段的真实形状是 **GFM 悬挂缩进**：每个序号项下面挂 1-3 行缩进续行。
/// 少了续行并入，一段 5 条的清单会被打散成「有序列表 / 段落 / 有序列表 / 段落…」
/// 十几块，界面上看起来就是一段段互不相干的文字。
private let REAL_README = """
1. **没有托盘**。CUI 不暴露托盘 API（无 `SDL_SetWindowIcon`、
   无 StatusNotifier 绑定），所以 macOS 的「菜单栏速览」（`MenuBarExtra` + `BarView`）
   在本端没有对应物。不拿「通知」冒充「托盘」—— 那不是同一件事。
2. **AI 面板是主区视图，不是独立窗口/sheet**。CUI 的 `DesktopApp` 只有一扇窗。
   代价：聊天时看不到仪表盘。
3. **密钥降级到 600 权限文件**。macOS 走 Keychain；本端优先 libsecret
   （`secret-tool`），没有时退到 `~/.config/deepdolphin/api-key`（chmod 600），
   **并在设置页显式写明**。不静默降级。
4. **`providerToolModels` 只列支持 tool_calls 的模型** —— 不支持的模型
   在第一轮提问就会撞墙。与 macOS 端 `modelWithToolCall` 同一条规则。
5. **「停止」不是杀请求，是立刻放弃这一轮**。macOS 端 `stop()` 取消任务；
   本端按下停止后：UI 马上解锁、显示已写出来的内容、主循环在**每个工具
   调用之前**与每轮之间检查停止标志、迟到的回写被轮次代号拦住。
   **已经发出但还没回来的那次 HTTP 请求仍然会跑完**（最多到它自己的超时），
   结果被丢弃 —— 这一点在界面上如实写出来。
   为什么不杀 curl：`SubProcess` 句柄由派发它的那条线程持有并在里面 `wait()`，
   从 UI 线程对同一句柄调 `terminate` 是跨线程操作，CUI/SDL 都没承诺它安全。
   赌它不崩，不如换一条确定不崩的路。
"""

// ---------------------------------------------------------------------------
// 行内 / 标题层
// ---------------------------------------------------------------------------

@Test
func headingsLoseTheirMarkerAndTheirSpaceNotJustTheHashes(): Unit {
    // ⚠ 这一条逮的是真 bug：`dropFirst(level)` 只去掉 `#`，**# 后面的空格留了下来**
    // —— 每个标题都带一个前导空格，渲染出来全部往右缩进一点。
    // macOS 端 `MarkdownParser.swift:75` 是 `dropFirst(level)` 再 `trimming`，本端
    // 头一次移植漏了那个 `trimming`，判据当场变红。
    let bs = mdBlocks("## 标题")
    @Expect(bs.size, 1)
    @Expect(bs[0].level, 2)
    @Expect(bs[0].lines[0], "标题")
    // 各级都要对，且都不能带前导空格
    @Expect(mdBlocks("# 一级")[0].lines[0], "一级")
    @Expect(mdBlocks("###### 六级")[0].lines[0], "六级")
    @Expect(mdHeadingLevel("# a").getOrThrow(), 1)
    @Expect(mdHeadingLevel("###### a").getOrThrow(), 6)
    // 七个 # 不是标题（GFM 只到 6）
    @Expect(mdHeadingLevel("####### a").isNone())
    // # 之后没有空格 → 不是标题
    @Expect(mdHeadingLevel("#hashtag").isNone())
    @Expect(mdHeadingLevel("no").isNone())
}

@Test
func inlineMarkersAreStrippedAndLinksKeepTheirLabel(): Unit {
    @Expect(mdStripInline("`get_milestones`"), "get_milestones")
    @Expect(mdStripInline("**待合入 4 个分支**"), "待合入 4 个分支")
    @Expect(mdStripInline("见 [引擎文档](https://x.dev/a) 那里"), "见 引擎文档 那里")
    // 多个链接都要剥
    @Expect(mdStripInline("[a](u1) 和 [b](u2)"), "a 和 b")
    // 半截链接不许把后面的正文吃掉
    @Expect(mdStripInline("见 [未闭合 的东西"), "见 [未闭合 的东西")
    @Expect(mdStripInline("纯文本"), "纯文本")
}

// ---------------------------------------------------------------------------
// 块级判定顺序
// ---------------------------------------------------------------------------

@Test
func theBlockOrderIsCheckedBeforeParagraphSoNothingGetsSwallowed(): Unit {
    // 判定顺序是有意义的：`**粗**` 会被段落吞掉，
    // 而 `>` 必须在段落之前判，否则引用行会变成普通文字。
    let bs = mdBlocks("## H\n\n- a\n- b\n\n> 引用\n\n段落")
    @Expect(bs.size, 4)
    @Expect(mdBlockIs(bs[0], MdBlockKind.Heading))
    @Expect(mdBlockIs(bs[1], MdBlockKind.Bullet))
    @Expect(bs[1].lines.size, 2)
    @Expect(mdBlockIs(bs[2], MdBlockKind.Quote))
    @Expect(mdBlockIs(bs[3], MdBlockKind.Paragraph))
}

@Test
func codeFenceIsTakenWholeInsteadOfBeingReadAsText(): Unit {
    let src = "前\n\n```bash\ncjpm build\ncjpm test\n```\n\n后"
    let bs = mdBlocks(src)
    @Expect(bs.size, 3)
    @Expect(mdBlockIs(bs[1], MdBlockKind.Code))
    // ⚠ 真换行。头一次写成 `sb.append("\\n")` 拼出来的是字面反斜杠+n，
    // 代码块在界面上会显示成一行 `cjpm build\ncjpm test`。
    @Expect(bs[1].code, "cjpm build\ncjpm test")
    @Expect(bs[1].code.contains("\n"), true)
    // 围栏里的内容不能被当成别的块
    for (line in bs[1].code.split("\n")) {
        @Expect(mdHeadingLevel(line).isNone())
    }
    @Expect(!bs[1].code.contains("#"))
}

@Test
func orderedListPrefixIsCappedSoDatesAreNotReadAsNumbers(): Unit {
    // `2026-06` 这种开头不该被当成序号 —— 上界 4 位数字，
    // 判据盯的就是这条（与 macOS 端 `n < 5` 同一条规则）。
    @Expect(mdNumberedPrefix("1. a").getOrThrow(), 3)
    @Expect(mdNumberedPrefix("12) b").getOrThrow(), 4)
    @Expect(mdNumberedPrefix("2026-06-01 更新").isNone())
    // 5 位数字就超界了（`99. ` 是 2 位，**在界内** —— 别把它当反例）
    @Expect(mdNumberedPrefix("12345. 太长").isNone())
    @Expect(mdNumberedPrefix("99. 两位").getOrThrow(), 4)
    @Expect(mdNumberedPrefix("没有序号").isNone())
    // 数字后面不是「. 」也不是「) 」就不是
    @Expect(mdNumberedPrefix("1.a").isNone())
    @Expect(mdNumberedPrefix("1. x").getOrThrow(), 3)
}

@Test
func orderedListKeepsItsNumbersBecauseAChecklistWithoutNumbersIsNotAChecklist(): Unit {
    // ⚠ 头一次移植只把前缀切掉，于是 `1. 拉分支` 渲染成光秃秃的「拉分支」——
    // 一份编号清单在界面上就看不出是清单了。
    let bs = mdBlocks("1. 拉分支\n2. 跑测试\n3. 提交")
    @Expect(bs.size, 1)
    @Expect(mdBlockIs(bs[0], MdBlockKind.Numbered))
    @Expect(bs[0].lines.size, 3)
    @Expect(bs[0].lines[0], "1. 拉分支")
    @Expect(bs[0].lines[2], "3. 提交")
    // `)` 分隔符规范化成 `. `（macOS 端会漏出一个悬空的 `)`，本端不跟那个 bug）
    @Expect(mdBlocks("12) b")[0].lines[0], "12. b")
    // 两位数不能被截成一位
    @Expect(mdBlocks("10. a\n11. b")[0].lines[1], "11. b")
}

@Test
func tableNeedsBothThePipeAndTheNextRowToQualify(): Unit {
    // 只含 `|` 的普通行不该被当成表格。
    let bs = mdBlocks("a | b\n普通行")
    for (b in bs) {
        @Expect(!mdBlockIs(b, MdBlockKind.Table))
    }
    // 连续 | 开头的行才是表格
    let t = mdBlocks("| 分支 | 状态 |\n|---|---|\n| main | 活跃 |")
    @Expect(t.size, 1)
    @Expect(mdBlockIs(t[0], MdBlockKind.Table))
    @Expect(t[0].lines.size, 3)
}

@Test
func dividerNeedsTheWholeLineToBeThreeMarks(): Unit {
    @Expect(mdBlocks("---").size, 1)
    @Expect(mdBlockIs(mdBlocks("---")[0], MdBlockKind.Divider))
    @Expect(mdBlockIs(mdBlocks("***")[0], MdBlockKind.Divider))
    @Expect(mdBlockIs(mdBlocks("___")[0], MdBlockKind.Divider))
    // `---abc` 不是分隔线（首版这里写的是 `@Expect(...size >= 0)` —— 恒真，
    // 等于没断言，已经删掉）
    for (b in mdBlocks("---abc")) {
        @Expect(!mdBlockIs(b, MdBlockKind.Divider))
    }
    for (b in mdBlocks("- --- 列表项不是分隔线")) {
        @Expect(!mdBlockIs(b, MdBlockKind.Divider))
    }
    // 表格分隔行 `|---|---|` 不是分隔线
    for (b in mdBlocks("|---|---|")) {
        @Expect(!mdBlockIs(b, MdBlockKind.Divider))
    }
}

// ---------------------------------------------------------------------------
// 真实输入
// ---------------------------------------------------------------------------

@Test
func realEngineContextParsesIntoTheBlocksItVisuallyHas(): Unit {
    // 夹具是引擎真实输出。期望值是**按 GFM 规则独立数出来的**（13 块），
    // 不是跑一遍实现再把输出抄进断言 —— 那样断言只会盖章实现自己的行为。
    let bs = mdBlocks(REAL_CONTEXT)
    @Expect(bs.size, 13)

    var headings: Int64 = 0
    var bullets: Int64 = 0
    var tables: Int64 = 0
    var quotes: Int64 = 0
    var bulletItems: Int64 = 0
    var tableRows: Int64 = 0
    for (b in bs) {
        if (mdBlockIs(b, MdBlockKind.Heading)) { headings += 1 }
        if (mdBlockIs(b, MdBlockKind.Bullet)) { bullets += 1; bulletItems += b.lines.size }
        if (mdBlockIs(b, MdBlockKind.Table)) { tables += 1; tableRows += b.lines.size }
        if (mdBlockIs(b, MdBlockKind.Quote)) { quotes += 1 }
    }
    @Expect(headings, 6)
    @Expect(bullets, 4)
    @Expect(tables, 2)
    @Expect(quotes, 1)
    @Expect(bulletItems, 12)
    @Expect(tableRows, 6)

    // 引用内容里带 ⚠ 与预算说明，不能被剥掉
    var q = ""
    for (b in bs) {
        if (mdBlockIs(b, MdBlockKind.Quote)) { q = b.lines[0] }
    }
    @Expect(q.contains("引擎为 AI 无关内核"), true)
}

@Test
func realContextLeavesNoMarkdownMarkersInAnythingThatGetsDrawn(): Unit {
    // 「## 」「**」「`」露在界面上」是这一族缺陷**唯一**用户看得见的症状，
    // 所以判据直接盯渲染出来的文本，不盯中间结构。
    //
    // ⚠ 表格**不在行首检查的范围里**：竖线是表格的内容（等宽排版靠它对齐，
    // macOS 端也是 `Text(row)` 原样画），拿「不许以 | 开头」去卡表格是
    // 把内容当噪声 —— 第一版就是这么写的，红了 4 条，红的原因跟判据声称的
    // 判据根本不是一回事。
    for (b in mdParse(REAL_CONTEXT)) {
        let isTable = mdBlockIs(b, MdBlockKind.Table)
        for (line in b.lines) {
            // 强调与代码记号：任何块里都不该残留
            @Expect(line.contains("**"), false)
            @Expect(line.contains("`"), false)
            if (!isTable) {
                @Expect(line.startsWith("#"), false)
                @Expect(line.startsWith(">"), false)
                @Expect(line.startsWith("- "), false)
                @Expect(line.startsWith("|"), false)
            }
        }
    }
}

@Test
func hangingIndentJoinsTheItemAboveInsteadOfFragmentingTheList(): Unit {
    // ⚠ 夹具是本仓库 README 原文：GFM 悬挂缩进，5 个序号项各挂 1-3 行续行。
    //
    // 少了续行并入，这段会被打散成「有序列表 / 段落 / 有序列表 / 段落…」十几块。
    // 而头一次移植的续行分支是**死代码**：它先 `trimAscii()` 再问
    // 「是不是以两个空格开头」，那个条件恒为 false（macOS 端同一处也错）。
    // 更糟的是有序列表压根没写续行分支 —— 第一版手编夹具里只测了无序列表，
    // 于是这个洞从判据缝里漏了过去。真实 README 的续行**全挂在有序列表下面**。
    let bs = mdBlocks(REAL_README)
    @Expect(bs.size, 1)
    @Expect(mdBlockIs(bs[0], MdBlockKind.Numbered))
    @Expect(bs[0].lines.size, 5)
    // 序号留着
    @Expect(bs[0].lines[0].startsWith("1. "), true)
    @Expect(bs[0].lines[4].startsWith("5. "), true)
    // 首行与末行续行都并进了第 1 项
    @Expect(bs[0].lines[0].contains("没有托盘"), true)
    @Expect(bs[0].lines[0].contains("在本端没有对应物"), true)
    // 第 3 项有两行续行，两行都得在
    @Expect(bs[0].lines[2].contains("macOS 走 Keychain"), true)
    @Expect(bs[0].lines[2].contains("并在设置页显式写明"), true)
    // 第 5 项有三行续行
    @Expect(bs[0].lines[4].contains("赌它不崩"), true)
    // 行内记号照样剥
    @Expect(bs[0].lines[1].contains("DesktopApp"), true)
    @Expect(bs[0].lines[1].contains("`"), false)
}

@Test
func aDividerRightAfterAParagraphIsNotSwallowedByIt(): Unit {
    // 段落遇到任何块级起始都必须断。头一次移植只判了 `t == "---"`，
    // 于是 `***` / `___` 两种分隔线会被并进上一段 ——
    // 界面上「一段话」里凭空多出三个星号。
    for (mark in ["---", "***", "___"]) {
        let bs = mdBlocks("段落第一行\n${mark}\n段落第二行")
        @Expect(bs.size, 3)
        @Expect(mdBlockIs(bs[0], MdBlockKind.Paragraph))
        @Expect(mdBlockIs(bs[1], MdBlockKind.Divider))
        @Expect(mdBlockIs(bs[2], MdBlockKind.Paragraph))
        @Expect(bs[0].lines.size, 1)
        @Expect(bs[2].lines.size, 1)
    }
    // 同族：有序列表紧跟段落时也不能被吞（`1. ` 那条判定两端口径不同，
    // 本端以「不吞」为准）
    let n = mdBlocks("段落第一行\n1. 序号项")
    @Expect(n.size, 2)
    @Expect(mdBlockIs(n[1], MdBlockKind.Numbered))
}

@Test
func theRendererClaimsExactlyTheKindsTheParserCanProduce(): Unit {
    // 渲染层（`markdown_view.cj`）依赖 CUI，判据进不去它的内部，
    // 唯一能验的是它**声称自己画了哪几种**（`mdRenderedKinds`）这张清单。
    // 这一条把三张表对齐：枚举全集 / 清单本身 / 解析真实产出。
    // 「新加一种块却忘了画控件」在这里会红 —— 那种漏画的块在界面上
    // 会被默认分支当成一段正文，用户看到的是「解析错了」，方向直接跑偏。
    let all = mdAllKindNames()
    let rendered = mdRenderedKinds()

    // 清单不许少、不许多、不许重
    @Expect(rendered.size, all.size)
    for (name in rendered) {
        @Expect(all.contains(name), true)
    }
    var seen = ArrayList<String>()
    for (name in rendered) {
        @Expect(seen.contains(name), false)
        seen.add(name)
    }

    // 拿一段「八种块齐全」的文本过一遍解析，产出的种类必须正好是这张清单
    let kitchenSink = """
    # 一级

    段落第一行
    段落第二行

    - 列表项

    1. 序号项

    > 引用

    ```sh
    echo hi
    ```

    ---

    | 列 | 值 |
    |---|---|
    | a | b |
    """
    var produced = ArrayList<String>()
    for (b in mdParse(kitchenSink)) {
        let name = mdKindName(b.kind)
        if (!produced.contains(name)) {
            produced.add(name)
        }
    }
    @Expect(produced.size, all.size)
    for (name in all) {
        @Expect(produced.contains(name), true)
        @Expect(rendered.contains(name), true)
    }
}

@Test
func bulletHangingIndentWorksTooNotJustTheNumberedOne(): Unit {
    // 无序列表的同一个分支。它和有序列表是两处独立代码，
    // 一处修好不等于另一处也修好，所以分开判。
    let bs = mdBlocks("- 第一项\n  这是续行\n- 第二项")
    @Expect(bs.size, 1)
    @Expect(mdBlockIs(bs[0], MdBlockKind.Bullet))
    @Expect(bs[0].lines.size, 2)
    @Expect(bs[0].lines[0].contains("第一项"), true)
    @Expect(bs[0].lines[0].contains("这是续行"), true)
    @Expect(bs[0].lines[1], "第二项")
}

// ---------------------------------------------------------------------------
// 记忆化
// ---------------------------------------------------------------------------

@Test
func parsingIsCachedBecauseTheBuildClosureRunsEveryFrame(): Unit {
    // macOS 那边 `blocks` 原本是 computed property，body 每求值一次就全量重解析 ——
    // 200KB 的 README 在滚动时是**每帧**的主线程工作。
    // CUI 的构建闭包同样每帧跑，所以记忆化是必需品。
    //
    // 判据盯的是**解析次数**，不是返回值：同一份文本解析两次，
    // 前后拿到的块长得一模一样，光断言「结果相等」等于什么都没断言。
    // 首版就是那么写的，绿了但其实没测到东西。
    mdMemoReset()
    let before = mdParseCount()
    mdBlocks(REAL_CONTEXT)
    let afterFirst = mdParseCount()
    @Expect(afterFirst - before, 1)

    // 同一份文本再来 3 次：一次都不该重新解析
    mdBlocks(REAL_CONTEXT)
    mdBlocks(REAL_CONTEXT)
    mdBlocks(REAL_CONTEXT)
    @Expect(mdParseCount() - afterFirst, 0)

    // 换个文本 → 该解析一次
    mdBlocks("# 别处")
    @Expect(mdParseCount() - afterFirst, 1)
}

@Test
func theMemoIsCappedSoReadingManyDocsDoesNotPileUpInMemory(): Unit {
    // 缓存无上限会把用户读过的每一篇文档都留在内存里，而收益只体现在
    // 「同一个视图被反复构造」这一种情况上。上界 64 条（R4-07）：
    // 对话流对每条助手消息各渲染一份，上限 4 的旧值在 5 条消息时就被打穿
    // —— 缓存整体失效，滚动一次 = 全部消息重解析一遍。
    mdMemoReset()
    for (i in 0..64) {
        mdBlocks("# 文档 ${i}")
    }
    let at64 = mdParseCount()

    // 64 条全在缓存里：第 0 篇不重解析（旧上界 4 时这条必红）
    mdBlocks("# 文档 0")
    @Expect(mdParseCount() - at64, 0)

    // 第 65 条把最老的挤出去：第 0 篇要重新解析
    mdBlocks("# 一条新的")
    let at65 = mdParseCount()
    mdBlocks("# 文档 0")
    @Expect(mdParseCount() - at65, 1)

    // 而最近的那几篇还在缓存里
    mdBlocks("# 文档 63")
    @Expect(mdParseCount() - at65, 1)

    // 命中不了缓存也只是重新解析一遍，不算错
    let back = mdBlocks("# 文档 0")
    @Expect(back.size, 1)
    @Expect(back[0].lines[0], "文档 0")
}

@Test
func changingTheMiddleBustsTheMemoEvenWhenLengthHeadAndTailAllMatch(): Unit {
    // R4-07 的另一半：旧指纹只采「长度 + 头尾各 64 字节」，两段正文
    // 长度一致、头尾一致时，中间改出花来也命中同一条缓存 ——
    // A 消息的解析结果被画在 B 消息上。指纹改为**全字节**哈希后，
    // 这种必然的同键不同文不再存在（只剩 ~2^-62 的碰撞）。
    mdMemoReset()
    // 头尾都短于旧版 64 字节的采样窗，差异全部藏在它不看的正中间
    let head = "## 开头\n\n"
    let tail = "\n\n结尾一致。"
    var midA = ""
    var midB = ""
    for (i in 0..80) {
        midA += "甲"
        midB += "乙"
    }
    let a = mdBlocks(head + midA + tail)
    let afterA = mdParseCount()
    let b = mdBlocks(head + midB + tail)
    // B 不得命中 A 的缓存：必须真的再解析一次
    @Expect(mdParseCount() - afterA, 1)
    // 两份解析结果内容不同，证明缓存没把 A 的块数组递给 B
    @Expect(a.size, b.size)
    @Expect(a[1].lines[0].contains("甲"), true)
    @Expect(b[1].lines[0].contains("乙"), true)
    @Expect(!a[1].lines[0].contains("乙"), true)
    // 同一段再取一遍 → 命中缓存，不重解析
    mdBlocks(head + midB + tail)
    @Expect(mdParseCount() - afterA, 1)
}
