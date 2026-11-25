// Markdown.kt —— 原生 Markdown 渲染（mac MarkdownParser.swift + MarkdownView 的 Kotlin 对位）。
//
// 【为什么不用 WebView】用户定稿：只有热力图 / 架构图走 WebView。AI 回答、帮助与关于文档、
// 托管文档正文都在这里原生渲染——不起 JCEF（少一条独立渲染进程，也没有冷启动开销）。
// 二次验证抓到过两个极端：AI 回答走 JCEF WebView（违反定稿），帮助文档则把 Markdown
// 源码原样显示（满屏 ## 和 **）。
//
// 块级文法对位 mac MarkdownParser：标题 / 段落 / 无序列表 / 有序列表 / 引用 / 围栏代码 / 分隔线 / 表格。
// 行内在 mac「只去标记」的基础上多做一步：粗体 / 等宽 / 链接带样式，链接可点。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp

/** 一个块级元素（mac MarkdownParser.Block 对位）。text / lines / items 保留行内标记原样，样式在渲染时加。 */
sealed interface MarkdownBlock {
    data class Heading(val level: Int, val text: String) : MarkdownBlock
    data class Paragraph(val lines: List<String>) : MarkdownBlock
    data class Bullet(val items: List<String>) : MarkdownBlock
    data class Numbered(val items: List<String>) : MarkdownBlock
    data class Quote(val lines: List<String>) : MarkdownBlock
    data class Code(val code: String) : MarkdownBlock
    data object Divider : MarkdownBlock
    data class Table(val rows: List<String>) : MarkdownBlock
}

object MarkdownParser {

    fun blocks(text: String): List<MarkdownBlock> {
        val out = ArrayList<MarkdownBlock>()
        val lines = text.split('\n')
        var i = 0
        while (i < lines.size) {
            val t = lines[i].trim()
            if (t.isEmpty()) {
                i += 1
                continue
            }
            if (t.startsWith("```")) {
                val body = ArrayList<String>()
                i += 1
                while (i < lines.size && !lines[i].trim().startsWith("```")) {
                    body += lines[i]
                    i += 1
                }
                i += 1 // 跳过收尾 ```
                out += MarkdownBlock.Code(body.joinToString("\n"))
                continue
            }
            val level = headingLevel(t)
            if (level != null) {
                out += MarkdownBlock.Heading(level, t.drop(level).trim())
                i += 1
                continue
            }
            if (t == "---" || t == "***" || t == "___") {
                out += MarkdownBlock.Divider
                i += 1
                continue
            }
            // 表格：这一行有竖线，且下一行也以竖线开头（表头 + 分隔行）
            if (t.contains('|') && i + 1 < lines.size && lines[i + 1].trim().startsWith("|")) {
                val rows = ArrayList<String>()
                while (i < lines.size && lines[i].trim().startsWith("|")) {
                    rows += lines[i]
                    i += 1
                }
                out += MarkdownBlock.Table(rows)
                continue
            }
            if (t.startsWith(">")) {
                val body = ArrayList<String>()
                while (i < lines.size && lines[i].trim().startsWith(">")) {
                    body += lines[i].trim().drop(1).trim()
                    i += 1
                }
                out += MarkdownBlock.Quote(body)
                continue
            }
            if (isBullet(t)) {
                val items = ArrayList<String>()
                while (i < lines.size) {
                    val x = lines[i]
                    val xt = x.trim()
                    when {
                        isBullet(xt) -> {
                            items += xt.drop(2).trim()
                            i += 1
                        }
                        // 缩进的续行并入上一项
                        x.startsWith("  ") && xt.isNotEmpty() && items.isNotEmpty() -> {
                            items[items.size - 1] = items.last() + " " + xt
                            i += 1
                        }
                        else -> break
                    }
                }
                out += MarkdownBlock.Bullet(items)
                continue
            }
            if (numberedPrefix(t) != null) {
                val items = ArrayList<String>()
                while (i < lines.size) {
                    val xt = lines[i].trim()
                    val n = numberedPrefix(xt)
                    if (n == null) break
                    // 跳过「数字 + 分隔符」。mac 只跳「.」，`2) 二` 会留下多余的右括号——这里一并跳掉
                    var idx = 0
                    while (idx < xt.length && (xt[idx].isDigit() || xt[idx] == '.' || xt[idx] == ')')) idx += 1
                    items += "$n. " + xt.substring(idx).trim()
                    i += 1
                }
                out += MarkdownBlock.Numbered(items)
                continue
            }
            // 段落：连续的非空行，遇到别的块级开头为止
            val para = ArrayList<String>()
            while (i < lines.size) {
                val x = lines[i].trim()
                if (x.isEmpty() || headingLevel(x) != null || x.startsWith("```") || x.startsWith(">") ||
                    isBullet(x) || x == "---"
                ) break
                para += x
                i += 1
            }
            if (para.isNotEmpty()) out += MarkdownBlock.Paragraph(para)
        }
        return out
    }

    private fun isBullet(t: String): Boolean = t.startsWith("- ") || t.startsWith("* ") || t.startsWith("+ ")

    fun headingLevel(s: String): Int? {
        var n = 0
        for (ch in s) {
            if (ch == '#') n += 1 else break
        }
        return if (n in 1..6 && s.length > n && s[n] == ' ') n else null
    }

    fun numberedPrefix(s: String): Int? {
        var n = 0
        for (ch in s) {
            if (ch.isDigit()) n += 1 else break
        }
        if (n in 1..4) {
            val rest = s.drop(n)
            if (rest.startsWith(". ") || rest.startsWith(") ")) return s.take(n).toIntOrNull()
        }
        return null
    }

    /** 去掉行内标记只留文字（mac stripInline 对位）：链接留文字，粗体/斜体/等宽标记去掉。 */
    fun stripInline(s: String): String {
        var t = s
        while (true) {
            val start = t.indexOf('[')
            if (start < 0) break
            val mid = t.indexOf("](", start + 1)
            if (mid < 0) break
            val end = t.indexOf(')', mid + 2)
            if (end < 0) break
            t = t.substring(0, start) + t.substring(start + 1, mid) + t.substring(end + 1)
        }
        return t.replace("**", "").replace("__", "").replace("`", "")
    }
}

private val INLINE = Regex(
    """\[(?<label>[^\]]+)]\((?<url>[^)\s]+)\)|\*\*(?<bold>[^*]+)\*\*|__(?<bold2>[^_]+)__|`(?<code>[^`]+)`|(?<![*\w])\*(?=\S)(?<it>[^*\n]+?)(?<=\S)\*(?!\*)|\*\*(?<stray>)|__(?<stray2>)""",
)

/** 行内富文本：链接（文字 accent 色、可点）、**粗体**、`等宽`、*斜体*。 */
fun markdownInline(
    raw: String,
    base: TextStyle,
    linkColor: Color = Palette.Accent,
    codeColor: Color = Palette.Ai,
): AnnotatedString = buildAnnotatedString {
    var i = 0
    for (m in INLINE.findAll(raw)) {
        if (m.range.first > i) append(raw.substring(i, m.range.first))
        val g = m.groups
        when {
            g["label"] != null -> withLink(
                LinkAnnotation.Url(g["url"]!!.value, TextLinkStyles(style = SpanStyle(color = linkColor))),
            ) { append(g["label"]!!.value) }
            g["bold"] != null -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(g["bold"]!!.value) }
            g["bold2"] != null -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(g["bold2"]!!.value) }
            g["code"] != null -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, color = codeColor)) { append(g["code"]!!.value) }
            g["it"] != null -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(g["it"]!!.value) }
            // 落单的粗体标记（文档里引用了 "**" 字样、没有闭合对）直接去掉，不把星号显示出来
            g["stray"] != null || g["stray2"] != null -> Unit
        }
        i = m.range.last + 1
    }
    if (i < raw.length) append(raw.substring(i))
}

private val Mono = FontFamily.Monospace

/**
 * 原生 Markdown 正文。[style] 是段落基准字号；标题按它放大（1.6× / 1.35× / 1.15×）。
 * 不起任何 WebView——这是热力图/架构图之外全部 Markdown 的唯一渲染通道。
 */
@Composable
fun MarkdownText(text: String, modifier: Modifier = Modifier, style: TextStyle = Type.body) {
    val blocks = remember(text) { MarkdownParser.blocks(text) }
    val base = style.copy(color = style.color.takeIf { it != Color.Unspecified } ?: Palette.TextPrimary)
    val line = base.lineHeight.takeIf { it != androidx.compose.ui.unit.TextUnit.Unspecified } ?: (base.fontSize * 1.5f)
    val body = base.copy(lineHeight = line)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Space.xs)) {
        blocks.forEachIndexed { idx, b ->
            when (b) {
                is MarkdownBlock.Heading -> {
                    if (idx > 0) Spacer(Modifier.height(Space.xs))
                    val scale = when (b.level) { 1 -> 1.6f; 2 -> 1.35f; 3 -> 1.15f; else -> 1f }
                    Text(
                        markdownInline(b.text, body.copy(fontSize = body.fontSize * scale)),
                        style = body.copy(fontSize = body.fontSize * scale, fontWeight = FontWeight.SemiBold),
                        color = Palette.TextPrimary,
                    )
                }
                is MarkdownBlock.Paragraph -> Text(
                    markdownInline(b.lines.joinToString("\n"), body), style = body,
                )
                is MarkdownBlock.Bullet -> b.items.forEach { item ->
                    Row(Modifier.fillMaxWidth()) {
                        Text("•", style = body.copy(color = Palette.TextSecondary))
                        Spacer(Modifier.width(6.dp))
                        Text(markdownInline(item, body), style = body, modifier = Modifier.weight(1f))
                    }
                }
                is MarkdownBlock.Numbered -> b.items.forEach { item ->
                    Text(markdownInline(item, body), style = body, modifier = Modifier.fillMaxWidth())
                }
                is MarkdownBlock.Quote -> Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
                    // 引用竖条撑满整段高度
                    Box(Modifier.width(2.dp).fillMaxHeight().background(Palette.StrokeHover))
                    Spacer(Modifier.width(Space.sm))
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        b.lines.forEach { Text(markdownInline(it, body.copy(color = Palette.TextSecondary)), style = body.copy(color = Palette.TextSecondary)) }
                    }
                }
                is MarkdownBlock.Code -> Box(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.control)).background(pageFill())
                        .border(Material.borderWidth, Palette.Stroke, RoundedCornerShape(Radius.control)).padding(Space.sm),
                ) {
                    Text(b.code, style = body.copy(fontFamily = Mono, fontSize = body.fontSize * 0.92f), color = Palette.TextPrimary)
                }
                MarkdownBlock.Divider -> HorizontalDivider(color = Palette.Stroke)
                is MarkdownBlock.Table -> Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    b.rows.forEach { row ->
                        Text(
                            row.trim().trim('|').split('|').joinToString("  │  ") { it.trim() },
                            style = body.copy(fontFamily = Mono, fontSize = body.fontSize * 0.92f),
                        )
                    }
                }
            }
        }
    }
}
