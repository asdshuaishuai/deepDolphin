// HtmlWebView.kt —— JCEF 单浏览器复用的通用 WebView 容器（C6 的 Markdown 通道抽出的公共件）。
//
// 【抽出来的理由】Markdown 排版与图谱产物页（mac GraphWebView 对位）共用同一份事实：
//   - KCEF/JCEF 每进程只装载一次（重量组件，独立渲染进程）——装载状态是全局单例；
//   - 组件内部只有一个 WebView，源变化走同一 browser 重载，不另起进程；
//   - 装载失败/超时如实给原因，调用方决定回退形态（纯文本 / 路径展示），不静默空白。
// 【装载目标】HtmlSource 二选一：本机引擎落盘的 HTML 产物路径（file:// 直载，对位 mac
//   GraphWebView 的 loadFileURL——传输层纪律：不跨网络），或客户端拼好的完整 HTML 文档。
// 【重载语义】对位 mac GraphWebView 的 Coordinator：源变更 → content 换新；同源仅
//   reloadToken 变 → navigator.reload()（引擎重绘后路径不变也要刷新）；结构相同的源 +
//   token 未变 → 不重复装载。

package deepdolphin.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import com.multiplatform.webview.web.LoadingState
import com.multiplatform.webview.web.WebContent
import com.multiplatform.webview.web.WebView
import com.multiplatform.webview.web.WebViewState
import com.multiplatform.webview.web.rememberWebViewNavigator
import dev.datlag.kcef.KCEF
import kotlinx.coroutines.delay
import java.io.File
import kotlin.math.roundToInt

/** 装载目标：引擎落盘的 HTML 产物绝对路径，或客户端拼好的完整 HTML 文档。 */
sealed interface HtmlSource {
    data class LocalFile(val path: String) : HtmlSource
    data class Content(val html: String) : HtmlSource
}

/** 页面事件：加载完成（携带就势注入 JS 的句柄）/ 装载失败（携带如实原因）。 */
sealed interface HtmlWebEvent {
    /** 页面加载完成；evaluate = 在当前页面上执行 JS（量高、取标题等）。 */
    class Loaded internal constructor(
        val evaluate: (script: String, onResult: (String?) -> Unit) -> Unit,
    ) : HtmlWebEvent

    /** 装载失败/超时（含主帧错误与 15s 看门狗触发）；why = 如实原因。 */
    data class Failed(val why: String) : HtmlWebEvent
}

/**
 * KCEF/JCEF 装载状态（原 MarkdownWeb 泛化）：每进程只尝试一次；失败/超时如实给原因。
 * 超时不杀后台线程——装载完成（onInitialized）仍会翻 Ready，重试请重启应用。
 */
object WebRuntime {
    sealed interface State {
        data object Init : State // 装载中（调用方先给兜底 UI）
        data object Ready : State // WebView 可用
        data class Failed(val why: String) : State // 装载失败（给原因）
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
                            state.value = State.Failed(e?.message ?: L10n.t("cmp.webview.unknownError"))
                        }
                    },
                    onRestartRequired = {
                        if (state.value is State.Init) {
                            state.value = State.Failed(L10n.t("cmp.webview.needRestart"))
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
            val pct = downloadPct?.let { "，" + L10n.t("cmp.webview.downloading", (it * 100).roundToInt()) } ?: ""
            state.value = State.Failed(L10n.t("cmp.webview.timeout", pct))
        }
    }
}

/**
 * 通用 WebView：JCEF 就绪时装载 HtmlSource；缺席/失败走 fallback 槽（调用方给降级 UI，
 * 如「WebView 不可用 + 引擎产物路径」——不空白）。fillMaxSize 类尺寸由调用方 modifier 决定。
 *
 * @param source 装载目标；null = 还没有产物（本组件不渲染实体，调用方自管空态）
 * @param reloadToken 变更即强制重载（同源路径不变也要刷新；对位 mac reloadToken）
 * @param transparent 透明底（叠玻璃卡用）；图谱产物自带完整背景，传 false
 * @param onEvent 页面事件（加载完成带 JS 句柄 / 失败带原因）
 * @param fallback JCEF 缺席/失败时的降级 UI 槽（收装载原因；不传则不渲染）
 */
@Composable
fun HtmlWebView(
    source: HtmlSource?,
    modifier: Modifier = Modifier,
    reloadToken: Any? = null,
    transparent: Boolean = false,
    onEvent: ((HtmlWebEvent) -> Unit)? = null,
    fallback: (@Composable (why: String) -> Unit)? = null,
) {
    LaunchedEffect(Unit) { WebRuntime.ensureReady() }
    when (val s = WebRuntime.state) {
        is WebRuntime.State.Init ->
            fallback?.invoke(
                L10n.t("cmp.webview.loading", WebRuntime.downloadPct?.let { "（${(it * 100).roundToInt()}%）" } ?: ""),
            )
        is WebRuntime.State.Failed -> fallback?.invoke(s.why)
        is WebRuntime.State.Ready -> WebViewBody(source, modifier, reloadToken, transparent, onEvent)
    }
}

/** WebView 实体：单实例；源/token 变化调度重载；加载完成回事件；看门狗兜底。 */
@Composable
private fun WebViewBody(
    source: HtmlSource?,
    modifier: Modifier,
    reloadToken: Any?,
    transparent: Boolean,
    onEvent: ((HtmlWebEvent) -> Unit)?,
) {
    val webViewState = remember(transparent) {
        WebViewState(WebContent.Data("", null, "utf-8", null, null)).apply {
            // OSR：轻量绘制进 Compose（heavyweight 窗口在滚动列表里会画穿其他组件）；
            // 透明与否由调用方定（markdown 叠玻璃底；图谱产物自带底色不闪白）
            webSettings.desktopWebSettings.offScreenRendering = true
            webSettings.desktopWebSettings.transparent = transparent
        }
    }
    val navigator = rememberWebViewNavigator()

    // 装载调度（对位 mac GraphWebView.updateNSView 的 Coordinator 去重）：
    // 源变更 → content 换新（库内 snapshotFlow 转 loadUrl/loadHtml）；同源仅 token 变 → reload()
    val lastLoad = remember { mutableStateOf<Pair<HtmlSource, Any?>?>(null) }
    LaunchedEffect(source, reloadToken) {
        val last = lastLoad.value
        when {
            source == null -> {}
            last != null && last.first == source && last.second != reloadToken -> navigator.reload()
            last == null || last.first != source -> webViewState.content = when (source) {
                is HtmlSource.Content -> WebContent.Data(source.html, null, "utf-8", null, null)
                is HtmlSource.LocalFile -> WebContent.Url(File(source.path).toURI().toString())
            }
            else -> {} // 同源同 token：SwiftUI 式重复调用不重复装载
        }
        if (source != null) lastLoad.value = source to reloadToken
    }

    // 加载完成 → 事件（主帧错误如实报 Failed；否则 Loaded 带 JS 句柄）
    LaunchedEffect(webViewState, source, reloadToken) {
        snapshotFlow { webViewState.loadingState }.collect { ls ->
            if (ls is LoadingState.Finished) {
                val mainErr = webViewState.errorsForCurrentRequest.firstOrNull { it.isFromMainFrame }
                if (mainErr != null) {
                    onEvent?.invoke(HtmlWebEvent.Failed(L10n.t("cmp.webview.loadFailed", mainErr.description, mainErr.code)))
                } else {
                    onEvent?.invoke(
                        HtmlWebEvent.Loaded { script, onResult -> navigator.evaluateJavaScript(script, onResult) },
                    )
                }
            }
        }
    }

    // 看门狗：15s 没等到加载完成回调 → 如实回退（含 browser 静默缺席的情形）
    LaunchedEffect(source, reloadToken) {
        if (source == null) return@LaunchedEffect
        delay(15_000)
        if (webViewState.loadingState !is LoadingState.Finished) {
            onEvent?.invoke(HtmlWebEvent.Failed(L10n.t("cmp.webview.webviewTimeout")))
        }
    }

    WebView(
        state = webViewState,
        navigator = navigator,
        modifier = modifier,
    )
}
