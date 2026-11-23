// MarkdownWebView.kt —— 助手消息/AI 设置说明的 Markdown 排版渲染（WebView）。
//
// 【通道】C6 收尾批起 WebView 通道抽成通用件 ui/HtmlWebView.kt（KCEF/JCEF 单浏览器复用、
// 装载状态单例、看门狗），本文件只保留 Markdown 特有的两件事：
//   ① 完整 HTML 文档装配（CSS 全部派生自 ui/Design.kt 的 Palette/Type/Space——色值/字号
//      单点真相源纪律不破；HTML 片段由 ai/MarkdownHtml.kt 纯函数转换，判据在那边）；
//   ② 内容高度自适应（加载完成后 JS 注入取 scrollHeight，超出上限交给外层滚动）。
// 【诚实回退】JCEF 缺席/装载失败/装载超时 → 回退纯文本并如实标注原因；
// 【取舍说明】webview 是重量组件（独立渲染进程），每条消息一个会把消息列表压垮；
// 调用方（AiChatPage）也只在最新一条助手消息上启用（该处取舍说明不变）。

package deepdolphin.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import deepdolphin.ai.markdownToBodyHtml
import java.util.Locale
import kotlin.math.roundToInt
// ── 色值桥：Design.kt 的 Compose Color → CSS（仍以 Palette 为唯一来源；全部手工拼串，不走 %f/%X
//    格式化，避免默认 Locale 在某些系统上输出逗号小数点毁掉 CSS）──

private fun Color.cssHex(): String =
    "#${(toArgb() and 0xFFFFFF).toString(16).padStart(6, '0').uppercase(Locale.ROOT)}"

private fun Color.cssRgba(): String {
    val argb = toArgb()
    val a = (argb ushr 24) and 0xFF
    val r = (argb shr 16) and 0xFF
    val g = (argb shr 8) and 0xFF
    val b = argb and 0xFF
    val alpha = ((a / 255.0) * 1000).roundToInt() / 1000.0
    return "rgba($r,$g,$b,$alpha)"
}

/** sp≈px（1x 密度）；整值不带小数点，CSS 干净。 */
private fun Float.px(): String =
    if (this == roundToInt().toFloat()) "${roundToInt()}px" else "${this}px"

/**
 * 完整 HTML 文档：正文 = markdownToBodyHtml（纯函数），样式 = Design.kt 派生。
 * 背景透明（叠在 GlassCard 玻璃底上）；代码块等宽字体。
 */
internal fun markdownDocument(markdown: String, style: TextStyle = Type.body): String {
    val base = style.fontSize.value
    val code = Type.label.fontSize.value
    return """<!DOCTYPE html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:transparent;color:${Palette.TextPrimary.cssHex()};font-size:${base.px()};line-height:1.55;font-family:"Noto Sans CJK SC","PingFang SC","Microsoft YaHei",system-ui,sans-serif;}
h1,h2,h3,h4,h5,h6{font-weight:600;line-height:1.3;margin:${Space.sm.value.px()} 0 ${Space.xs.value + 2}px 0;}
h1{font-size:${Type.display.fontSize.value.px()};}
h2{font-size:${Type.title.fontSize.value.px()};}
h3{font-size:${Type.section.fontSize.value.px()};}
h4,h5,h6{font-size:${Type.card.fontSize.value.px()};}
p{margin:0 0 ${Space.xs.value + 2}px;}
a{color:${Palette.Accent.cssHex()};text-decoration:none;}
a:hover{text-decoration:underline;}
strong{font-weight:700;}
code{font-family:"JetBrains Mono","Noto Sans Mono CJK SC",monospace;font-size:${code.px()};background:${Palette.Card.cssRgba()};border-radius:4px;padding:1px 4px;}
pre{background:${Palette.Card.cssRgba()};border:1px solid ${Palette.Stroke.cssRgba()};border-radius:${(Radius.card.value / 2).px()};padding:${Space.sm.value.px()};margin:${Space.sm.value.px()} 0;overflow-x:auto;}
pre code{background:transparent;padding:0;display:block;white-space:pre;}
table{border-collapse:collapse;margin:${Space.sm.value.px()} 0;width:100%;}
th,td{border:1px solid ${Palette.Stroke.cssRgba()};padding:${Space.xs.value + 2}px ${Space.sm.value}px;text-align:left;}
th{background:${Palette.CardHover.cssRgba()};font-weight:600;}
blockquote{margin:${Space.sm.value.px()} 0;padding:${Space.xs.value.px()} ${Space.sm.value.px()};border-left:3px solid ${Palette.Accent.cssRgba()};color:${Palette.TextSecondary.cssHex()};}
ul,ol{margin:${Space.sm.value.px()} 0;padding-left:${Space.lg.value + 4}px;}
li{margin:2px 0;}
li::marker{color:${Palette.Accent.cssRgba()};}
hr{border:0;border-top:1px solid ${Palette.Stroke.cssRgba()};margin:${Space.sm.value.px()} 0;}
</style></head><body>${markdownToBodyHtml(markdown)}</body></html>"""
}

/**
 * Markdown 排版渲染：JCEF 就绪用 WebView（通道 = HtmlWebView）；缺席/失败/超时回退纯文本并如实标注。
 * 助手消息由 AiChatPage 只在最新一条上启用（见该处取舍说明）；AI 设置页说明同通道。
 */
@Composable
fun MarkdownWebView(
    markdown: String,
    modifier: Modifier = Modifier,
    style: TextStyle = Type.body,
    minHeight: Dp = 64.dp,
) {
    LaunchedEffect(Unit) { WebRuntime.ensureReady() }
    var fallbackWhy by remember(markdown) { mutableStateOf<String?>(null) }
    when (val s = WebRuntime.state) {
        is WebRuntime.State.Init -> FallbackText(
            markdown, modifier, style,
            "JCEF 装载中${WebRuntime.downloadPct?.let { "（${(it * 100).roundToInt()}%）" } ?: ""}——就绪后自动切换",
        )
        is WebRuntime.State.Failed -> FallbackText(markdown, modifier, style, s.why)
        is WebRuntime.State.Ready ->
            if (fallbackWhy != null) FallbackText(markdown, modifier, style, fallbackWhy!!)
            else MarkdownWebBody(markdown, modifier, style, minHeight) { fallbackWhy = it }
    }
}

/** WebView 实体（HtmlWebView 通道）：文档变化重载；加载完成 JS 量高自适应。 */
@Composable
private fun MarkdownWebBody(
    markdown: String,
    modifier: Modifier,
    style: TextStyle,
    minHeight: Dp,
    onFallback: (String) -> Unit,
) {
    val doc = remember(markdown, style) { markdownDocument(markdown, style) }
    // 高度跨文档保留（新文档量高回来前先沿旧高，不闪跳）
    var contentHeight by remember { mutableStateOf(minHeight) }
    HtmlWebView(
        source = HtmlSource.Content(doc),
        modifier = modifier.height(contentHeight),
        transparent = true,
        onEvent = { ev ->
            when (ev) {
                is HtmlWebEvent.Loaded -> ev.evaluate("document.documentElement.scrollHeight.toString()") { v ->
                    v?.toDoubleOrNull()?.let {
                        contentHeight = it.dp.coerceIn(minHeight, 420.dp)
                    }
                }
                is HtmlWebEvent.Failed -> onFallback(ev.why)
            }
        },
    )
}

/** 纯文本回退 + 原因标注（诚实失败纪律：给原因）。 */
@Composable
private fun FallbackText(markdown: String, modifier: Modifier, style: TextStyle, note: String) {
    Column(modifier) {
        Text(markdown, style = style)
        Text("（Markdown 排版未启用：$note —— 暂以纯文本显示）", style = Type.micro.copy(color = Palette.Amber))
    }
}
