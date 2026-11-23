// MarkdownHtmlTest.kt —— Markdown→HTML 纯函数转换判据（C6 收尾批）。
//
// 【判据】标题/围栏代码块（等宽 + 内容转义）/正文 HTML 转义（不构成注入面）/
//   列表/表格/行内格式/文档令牌（色值·字号必须来自 ui/Design.kt 单点真相源）。
// 【边界】不追求完整 GFM：下划线强调、图片、Setext 标题不支持（宁缺勿错）。

package deepdolphin.ai

import deepdolphin.ui.Type
import deepdolphin.ui.markdownDocument
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MarkdownHtmlTest {

    // ── 判据 1：标题（#..###### → h1..h6；####### 不算标题）──

    @Test
    fun headingsMapToH1ToH6() {
        assertEquals("<h1>总览</h1>", markdownToBodyHtml("# 总览"))
        assertEquals("<h3>三级</h3>", markdownToBodyHtml("### 三级"))
        assertEquals("<h6>最深</h6>", markdownToBodyHtml("###### 最深"))
        val out = markdownToBodyHtml("####### 七个井号不是标题")
        assertFalse(out.contains("<h7>"), "7 级标题不存在：$out")
        assertTrue(out.contains("<p>####### 七个井号不是标题</p>"), "应按普通段落处理：$out")
        // # 后必须跟空格才算标题（#abc 是标签/锚点文本）
        assertEquals("<p>#hashtag</p>", markdownToBodyHtml("#hashtag"))
    }

    // ── 判据 2：围栏代码块（pre/code + 等宽 + 内部只转义不做行内格式）──

    @Test
    fun fencedCodeBlockRendersMonospacePreAndEscapesContent() {
        val out = markdownToBodyHtml("```kotlin\nval a = <b>\nval b = \"x\"\n```")
        assertTrue(out.contains("<pre><code data-lang=\"kotlin\">"), "代码块须落 pre/code：$out")
        assertTrue(out.contains("val a = &lt;b&gt;"), "代码内容必须转义：$out")
        assertFalse(out.contains("<b>"), "不允许原样注入标签：$out")
        // 未闭合围栏不崩溃，余文全部进代码块
        val unclosed = markdownToBodyHtml("```\nx < y")
        assertTrue(unclosed.contains("<pre><code>") && unclosed.contains("x &lt; y"), "未闭合围栏：$unclosed")
        // 完整文档里代码块走等宽字体
        assertTrue(markdownDocument("```js\n1\n```").contains("monospace"), "代码块必须等宽")
    }

    // ── 判据 3：正文转义（AI/引擎返回的文本不构成注入面）──

    @Test
    fun proseIsHtmlEscapedNoScriptInjection() {
        val out = markdownToBodyHtml("<script>alert('x')</script> & \"quotes\"")
        assertTrue(out.contains("&lt;script&gt;"), "尖括号必须实体化：$out")
        assertFalse(out.contains("<script"), "不允许出现原样 script 标签：$out")
        assertTrue(out.contains("&amp;"), "& 必须转义：$out")
        assertTrue(out.contains("&quot;"), "引号必须转义（防属性逃逸）：$out")
        // 行内码里的 HTML 同样实体化
        val inCode = renderInline("`<img src=x>`")
        assertTrue(inCode.contains("<code>&lt;img src=x&gt;</code>"), "行内码转义：$inCode")
    }

    // ── 判据 4：列表（无序 ul / 有序 ol）──

    @Test
    fun listsRenderAsUlAndOl() {
        val out = markdownToBodyHtml("- 甲\n- 乙\n\n1. one\n2. two")
        assertTrue(out.contains("<ul><li>甲</li><li>乙</li></ul>"), "无序列表：$out")
        assertTrue(out.contains("<ol><li>one</li><li>two</li></ol>"), "有序列表：$out")
    }

    // ── 判据 5：表格（表头/分隔行/数据行；格内转义与行内格式）──

    @Test
    fun tableRendersHeaderBodyCells() {
        val out = markdownToBodyHtml("| 名 | 值 |\n|---|---|\n| a | 1 |")
        assertEquals(
            "<table><thead><tr><th>名</th><th>值</th></tr></thead>" +
                "<tbody><tr><td>a</td><td>1</td></tr></tbody></table>",
            out,
            "表格结构：$out",
        )
        // 散文里带竖线但下一行不是分隔行 → 不当表格
        val prose = markdownToBodyHtml("a | b\n普通续行")
        assertFalse(prose.contains("<table>"), "无分隔行不成表格：$prose")
    }

    // ── 判据 6：行内格式（粗/斜/行内码/链接；行内码内不做进一步格式）──

    @Test
    fun inlineFormattingBoldItalicCodeLink() {
        val out = renderInline("看 **加粗**、*斜体*、`代码` 与 [链接](https://a.b/c?x=1&y=2)")
        assertTrue(out.contains("<strong>加粗</strong>"), "粗体：$out")
        assertTrue(out.contains("<em>斜体</em>"), "斜体：$out")
        assertTrue(out.contains("<code>代码</code>"), "行内码：$out")
        assertTrue(
            out.contains("<a href=\"https://a.b/c?x=1&amp;y=2\">链接</a>"),
            "链接 href 需转义：$out",
        )
        // 行内码里的 ** 不触发粗体
        val noBoldInCode = renderInline("`**not bold**`")
        assertTrue(noBoldInCode.contains("<code>**not bold**</code>"), "行内码内容保持原样：$noBoldInCode")
        assertFalse(noBoldInCode.contains("<strong>"), "行内码内不得加粗：$noBoldInCode")
    }

    // ── 判据 7：完整文档的色值/字号必须来自 Design.kt 单点真相源 ──

    @Test
    fun documentDerivesDesignTokensFromDesignKt() {
        val doc = markdownDocument("# 标题\n正文")
        // Palette.TextPrimary = 0xFFE6EDF3
        assertTrue(doc.contains("#E6EDF3"), "正文色必须取自 Palette.TextPrimary：${doc.take(400)}")
        // Type.body = 13sp 作为基准字号；代码字号取 Type.label = 12sp
        assertTrue(doc.contains("font-size:13px"), "基准字号必须取自 Type.body：${doc.take(400)}")
        assertTrue(doc.contains("font-size:12px"), "代码字号必须取自 Type.label：${doc.take(400)}")
        // 背景透明（叠 GlassCard 玻璃底）
        assertTrue(doc.contains("background:transparent"), "WebView 背景须透明")
        assertTrue(doc.contains("<h1>标题</h1>") && doc.contains("<p>正文</p>"), "文档须装下转换结果")
        // 传入 style=Type.micro（11sp）时基准字号跟着变
        assertTrue(
            markdownDocument("x", Type.micro).contains("font-size:10px"),
            "字号必须跟随传入的 Design.kt style（Type.micro=10，mac caption2 档）",
        )
    }

    // ── 判据 8：空输入与段落基线 ──

    @Test
    fun blankInputAndParagraphBasics() {
        assertEquals("", markdownToBodyHtml(""))
        assertEquals("", markdownToBodyHtml("   \n  "))
        assertEquals("<p>单行</p>", markdownToBodyHtml("单行"))
        assertEquals("<p>a<br>b</p>", markdownToBodyHtml("a\nb"), "段落内换行用 <br>")
        // 段落吃到块级起点为止
        assertEquals("<p>前文</p><h2>标题</h2>", markdownToBodyHtml("前文\n## 标题").replace("\n", ""), "块级输出可带换行分隔")
        assertEquals("<blockquote>引一行<br>再一行</blockquote>", markdownToBodyHtml("> 引一行\n> 再一行"))
    }
}
