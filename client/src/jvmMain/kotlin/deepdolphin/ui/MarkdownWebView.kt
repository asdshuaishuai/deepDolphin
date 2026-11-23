// MarkdownWebView.kt —— C6 收尾批：助手消息/AI 设置说明的 Markdown 排版渲染（WebView）。
//
// 【通道】桌面走 io.github.kevinnzou:compose-webview-multiplatform 的 KCEF/JCEF；
// 完整 HTML 文档在本文件装配，CSS 全部派生自 ui/Design.kt（Palette/Type/Space）——
// 色值/字号单点真相源纪律不破；HTML 片段由 ai/MarkdownHtml.kt 纯函数转换（判据在那边）。
// 【诚实回退】JCEF 缺席/装载失败/装载超时 → 回退纯文本并如实标注原因（MarkdownWeb.State.Failed.why）；
// KCEF 每进程只尝试装载一次，超时后后台继续装载、完成即自动切排版（onInitialized 回调）。
// 【取舍说明】webview 是重量组件（独立渲染进程），每条消息一个会把消息列表压垮；
// 本组件内部只有一个 WebView，markdown 变化走 WebViewState.content → 同一 browser 重载，
// 内容高度用 JS 注入（scrollHeight）回填。调用方（AiChatPage）也只在最新一条助手消息上启用。

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
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.multiplatform.webview.web.LoadingState
import com.multiplatform.webview.web.WebContent
import com.multiplatform.webview.web.WebView
import com.multiplatform.webview.web.WebViewState
import com.multiplatform.webview.web.rememberWebViewNavigator
import deepdolphin.ai.markdownToBodyHtml
import dev.datlag.kcef.KCEF
import kotlinx.coroutines.delay
import java.io.File
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
pre{background:${Palette.Card.cssRgba()};border:1px solid ${Palette.Stroke.cssRgba()};border-radius:${(Space.tileRadius.value / 2).px()};padding:${Space.sm.value.px()};margin:${Space.sm.value.px()} 0;overflow-x:auto;}
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
 * KCEF/JCEF 装载状态：每进程只尝试一次；失败/超时如实给原因，UI 回退纯文本。
 * 超时不杀后台线程——装载完成（onInitialized）仍会翻 Ready，重试请重启应用。
 */
object MarkdownWeb {
    sealed interface State {
        data object Init : State // 装载中（先给纯文本兜底）
        data object Ready : State // WebView 可用
        data class Failed(val why: String) : State // 装载失败（给原因；本轮纯文本）
    }

    val state = mutableStateOf<State>(State.Init)

    /** JCEF 二进制下载进度（0..1；null=未知）。仅用于诚实披露装载卡在哪。 */
    var downloadPct by mutableStateOf<Float?>(null)
        private set

    @Volatile
    private var attempted = false

    suspend fun ensureReady() {
        if (attempted) return
        attempted = true
        val cacheDir = File(
            System.getenv("XDG_CACHE_HOME") ?: (System.getProperty("user.home") + "/.cache"),
            "deepDolphin/kcef",
        )
        Thread {
            try {
                KCEF.initBlocking(
                    builder = {
                        installDir(cacheDir)
                        download { github() } // JCEF 二进制来自 KCEF 的 GitHub release
                        progress {
                            onDownloading { downloadPct = it }
                            onInitialized { state.value = State.Ready }
                        }
                        settings { cachePath = File(cacheDir, "cache").absolutePath }
                    },
                    onError = { e ->
                        if (state.value is State.Init) {
                            state.value = State.Failed(e?.message ?: "未知错误（onError）")
                        }
                    },
                    onRestartRequired = {
                        if (state.value is State.Init) {
                            state.value = State.Failed("JCEF 装载需重启应用后继续")
                        }
                    },
                )
            } catch (t: Throwable) {
                if (state.value is State.Init) {
                    state.value = State.Failed(t.message ?: t.javaClass.simpleName)
                }
            }
        }.apply { isDaemon = true; name = "kcef-init" }.start()

        // 至多等 20s：没就绪先如实回退（后台装载继续，完成后自动切换）
        val deadline = System.currentTimeMillis() + 20_000
        while (state.value is State.Init && System.currentTimeMillis() < deadline) delay(200)
        if (state.value is State.Init) {
            val pct = downloadPct?.let { "，下载 ${(it * 100).roundToInt()}%" } ?: ""
            state.value = State.Failed("装载超时（>20s$pct）——后台继续装载，完成后自动切换")
        }
    }
}

/**
 * Markdown 排版渲染：JCEF 就绪用 WebView；缺席/失败/超时回退纯文本并如实标注。
 * 助手消息由 AiChatPage 只在最新一条上启用（见该处取舍说明）；AI 设置页说明同通道。
 */
@Composable
fun MarkdownWebView(
    markdown: String,
    modifier: Modifier = Modifier,
    style: TextStyle = Type.body,
    minHeight: Dp = 64.dp,
) {
    LaunchedEffect(Unit) { MarkdownWeb.ensureReady() }
    var fallbackWhy by remember(markdown) { mutableStateOf<String?>(null) }
    when (val s = MarkdownWeb.state) {
        is MarkdownWeb.State.Init -> FallbackText(
            markdown, modifier, style,
            "JCEF 装载中${MarkdownWeb.downloadPct?.let { "（${(it * 100).roundToInt()}%）" } ?: ""}——就绪后自动切换",
        )
        is MarkdownWeb.State.Failed -> FallbackText(markdown, modifier, style, s.why)
        is MarkdownWeb.State.Ready ->
            if (fallbackWhy != null) FallbackText(markdown, modifier, style, fallbackWhy!!)
            else WebViewBody(markdown, modifier, style, minHeight) { fallbackWhy = it }
    }
}

/** WebView 实体：单实例；文档变化 → content 重载；加载完成 → JS 注入量高自适应。 */
@Composable
private fun WebViewBody(
    markdown: String,
    modifier: Modifier,
    style: TextStyle,
    minHeight: Dp,
    onFallback: (String) -> Unit,
) {
    val doc = remember(markdown, style) { markdownDocument(markdown, style) }
    val webViewState = remember {
        WebViewState(WebContent.Data("", null, "utf-8", null, null)).apply {
            // OSR：轻量绘制进 Compose（heavyweight 窗口在滚动列表里会画穿其他组件）；
            // 透明：叠 GlassCard 玻璃底，不闪白。
            webSettings.desktopWebSettings.offScreenRendering = true
            webSettings.desktopWebSettings.transparent = true
        }
    }
    val navigator = rememberWebViewNavigator()
    var contentHeight by remember { mutableStateOf(minHeight) }

    // 文档变化 → 同一 browser 重载（库内对 state.content 的 snapshotFlow 转 loadHtml）
    LaunchedEffect(doc) { webViewState.content = WebContent.Data(doc, null, "utf-8", null, null) }

    // 加载完成 → JS 注入取内容高，自适应高度（超出上限交给外层滚动/滚轮）
    LaunchedEffect(webViewState, doc) {
        snapshotFlow { webViewState.loadingState }.collect { ls ->
            if (ls is LoadingState.Finished) {
                navigator.evaluateJavaScript("document.documentElement.scrollHeight.toString()") { v ->
                    v.toDoubleOrNull()?.let {
                        contentHeight = it.dp.coerceIn(minHeight, 420.dp)
                    }
                }
            }
        }
    }

    // 看门狗：15s 没等到加载完成回调 → 如实回退（含 browser 静默缺席的情形）
    LaunchedEffect(doc) {
        delay(15_000)
        if (webViewState.loadingState !is LoadingState.Finished) {
            onFallback("WebView 装载超时（15s 未完成）")
        }
    }

    WebView(
        state = webViewState,
        navigator = navigator,
        modifier = modifier.height(contentHeight),
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
