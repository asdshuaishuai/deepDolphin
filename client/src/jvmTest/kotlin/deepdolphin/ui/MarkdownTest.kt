// MarkdownTest.kt —— 原生 Markdown 解析与行内样式判据（mac MarkdownParser.swift 的断言对位）。
//
// 用户定稿：只有热力图 / 架构图走 WebView；AI 回答、帮助与关于文档、托管文档正文都原生渲染。
// 二次验证抓到过：帮助文档把 Markdown 源码原样显示（满屏 ## 和 **）。

package deepdolphin.ui

import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MarkdownTest {

    @BeforeTest
    fun pinZh() {
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    // ── 块级 ──

    @Test
    fun headingAndParagraph() {
        assertEquals(
            listOf(MarkdownBlock.Heading(1, "标题"), MarkdownBlock.Paragraph(listOf("正文"))),
            MarkdownParser.blocks("# 标题\n正文"),
        )
        assertEquals(3, MarkdownParser.headingLevel("### 小节"))
        assertNull(MarkdownParser.headingLevel("#hashtag"), "# 后面必须是空格")
        assertNull(MarkdownParser.headingLevel("####### 七级"), "只到六级")
        assertNull(MarkdownParser.headingLevel("#"), "光杆 # 不算标题")
    }

    @Test
    fun fencedCodeKeepsBodyVerbatim() {
        assertEquals(listOf(MarkdownBlock.Code("1\n2")), MarkdownParser.blocks("```js\n1\n2\n```\n"))
        // 没收尾的围栏：一直吃到结尾，不许把后面的内容吞成别的东西
        assertEquals(listOf(MarkdownBlock.Code("x")), MarkdownParser.blocks("```\nx"))
        // 围栏里的 # 不是标题、* 不是列表
        assertEquals(listOf(MarkdownBlock.Code("# not heading\n* not bullet")), MarkdownParser.blocks("```\n# not heading\n* not bullet\n```"))
    }

    @Test
    fun bulletsWithContinuationLines() {
        val b = MarkdownParser.blocks("- 一\n- 二\n  续行\n+ 三")
        assertEquals(listOf(MarkdownBlock.Bullet(listOf("一", "二 续行", "三"))), b)
    }

    @Test
    fun numberedListsKeepTheirOwnNumbers() {
        assertEquals(listOf(MarkdownBlock.Numbered(listOf("1. 一", "2. 二"))), MarkdownParser.blocks("1. 一\n2) 二"))
        assertEquals(12, MarkdownParser.numberedPrefix("12. x"))
        assertNull(MarkdownParser.numberedPrefix("12345. x"), "五位数不算有序列表（mac 同款上限）")
        assertNull(MarkdownParser.numberedPrefix("1.x"), "数字后必须是「. 」或「) 」")
    }

    @Test
    fun quoteDividerAndTable() {
        assertEquals(listOf(MarkdownBlock.Quote(listOf("一", "二"))), MarkdownParser.blocks("> 一\n> 二"))
        assertEquals(listOf(MarkdownBlock.Divider), MarkdownParser.blocks("---"))
        val t = MarkdownParser.blocks("| a | b |\n|---|---|\n| 1 | 2 |")
        assertEquals(1, t.size)
        assertTrue(t[0] is MarkdownBlock.Table)
        assertEquals(3, (t[0] as MarkdownBlock.Table).rows.size)
    }

    @Test
    fun paragraphStopsAtNextBlock() {
        val b = MarkdownParser.blocks("第一行\n第二行\n- 项")
        assertEquals(listOf(MarkdownBlock.Paragraph(listOf("第一行", "第二行")), MarkdownBlock.Bullet(listOf("项"))), b)
    }

    // ── 行内 ──

    @Test
    fun stripInlineKeepsOnlyWords() {
        assertEquals("看 加粗、代码 与 链接", MarkdownParser.stripInline("看 **加粗**、`代码` 与 [链接](https://a.b/c?x=1)"))
    }

    @Test
    fun inlineStylesBoldCodeAndLink() {
        val a = markdownInline("看 **加粗** 与 `代码`", Type.body)
        assertEquals("看 加粗 与 代码", a.text, "标记符不进正文")
        assertTrue(a.spanStyles.any { it.item.fontWeight == FontWeight.Bold }, "粗体要有粗体样式")
        assertTrue(a.spanStyles.any { it.item.fontFamily == FontFamily.Monospace }, "等宽要有等宽字体")
    }

    @Test
    fun inlineLinkIsClickableAndCarriesUrl() {
        val a = markdownInline("[链接](https://a.b/c?x=1)", Type.body)
        assertEquals("链接", a.text)
        val links = a.getLinkAnnotations(0, a.length)
        assertEquals(1, links.size)
        assertEquals("https://a.b/c?x=1", (links[0].item as LinkAnnotation.Url).url)
    }

    @Test
    fun inlineLeavesPlainTextAlone() {
        // 文件名里的下划线、单独的星号不是标记
        val a = markdownInline("client/PLAN.md 与 2 * 3 * 4", Type.body)
        assertEquals("client/PLAN.md 与 2 * 3 * 4", a.text)
        assertTrue(a.spanStyles.isEmpty(), "没有成对标记就不该加样式")
    }

    @Test
    fun blankInputHasNoBlocks() {
        assertTrue(MarkdownParser.blocks("").isEmpty())
        assertTrue(MarkdownParser.blocks("\n\n  \n").isEmpty())
    }

    @Test
    fun strayBoldMarkersAreDroppedNotShown() {
        // 帮助文档里有一处引用了 "**" 字样却没有闭合对——落单的标记不该原样显示
        assertEquals("点击 \"\"+\" 新建里程碑", markdownInline("点击 \"**\"+\" 新建里程碑", Type.body).text)
        assertTrue(markdownInline("a ** b", Type.body).spanStyles.isEmpty(), "落单标记不算粗体")
    }
}

