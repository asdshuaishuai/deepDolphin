// HtmlWebView.kt —— 图谱两页的 WebView 容器（mac GraphWebView.swift 的对位）。
//
// 【适用范围】用户定稿：只有热力图（代码图谱）/ 架构图走 WebView。引擎 `render index` /
// `render arch` 的交互 HTML 产物是正身，这里原样装载；其余 Markdown 一律原生渲染（Markdown.kt）。
// 【装载目标】HtmlSource 二选一：本机引擎落盘的 HTML 产物路径（file:// 直载，对位 mac 的
// loadFileURL——传输层纪律：不跨网络），或客户端拼好的完整 HTML 文档。
// 【首帧纪律】先不装内容，量到真实尺寸后再装载（产物初始化按视口取景，见 WebViewBody）。
// 【重载语义】对位 mac GraphWebView 的 Coordinator：源变化 → content 换新；同源仅
// reloadToken 变 → navigator.reload()（引擎重绘后路径不变也要刷新）；源与 token 都没变 → 不重复装载。
// 【装载失败/超时】如实给原因，调用方决定回退形态（不静默空白）。

package deepdolphin.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.Modifier
import com.multiplatform.webview.web.LoadingState
import com.multiplatform.webview.web.rememberWebViewNavigator
import com.multiplatform.webview.web.WebContent
import com.multiplatform.webview.web.WebView
import com.multiplatform.webview.web.WebViewNavigator
import com.multiplatform.webview.web.WebViewState
import dev.datlag.kcef.KCEF
import java.io.File
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** 装载目标：引擎落盘的 HTML 产物绝对路径，或客户端拼好的完整 HTML 文档。 */
sealed interface HtmlSource {
    data class LocalFile(val path: String) : HtmlSource
    data class Content(val html: String) : HtmlSource
}

/**
 * 嵌入器外观 → 引擎产物的 prefers-color-scheme。
 * 架构图产物按 matchMedia('(prefers-color-scheme: light)') 选明暗；CEF 在 Linux 上只认 GTK 的
 * 暗色开关，deepin 的暗色不走它——不垫这一层时架构图是浅色，和暗色外壳撞在一起。mac 上
 * WKWebView 跟随系统外观，天然一致。命令行开关（--force-dark-mode 等）实测对它无效。
 * 垫片在文档任何脚本之前改写 matchMedia，产物打开即暗、不会先浅色闪一下；产物内的手动切换不受影响。
 */
internal const val DARK_SCHEME_SHIM: String =
    "(function(){var n=window.matchMedia;window.matchMedia=function(q){var m=n.call(window,q);" +
        "if(q.indexOf('prefers-color-scheme')>=0){Object.defineProperty(m,'matches'," +
        "{get:function(){return q.indexOf('light')<0;}});}return m;};})();"

private val HEAD_OPEN = Regex("<head[^>]*>", RegexOption.IGNORE_CASE)

/** 把垫片插进 <head> 的开头（没有 head 就放文档最前）——必须早于产物自己的任何脚本。 */
internal fun withHeadScript(html: String, script: String): String {
    val tag = "<script>$script</script>"
    val open = HEAD_OPEN.find(html)
    return if (open != null) html.replaceRange(open.range.last + 1, open.range.last + 1, tag) else tag + html
}

/**
 * 垫了脚本的产物落成一份可 file:// 直载的副本（应用缓存目录；内容没变就不重写）。
 * 为什么不走库的 loadHtml：它装的是 KCEF 内部的 file:///kcefbrowser/<id> 映射，本机实测
 * ERR_FILE_NOT_FOUND（原生与绑定配套之后依然如此）——这个栈里只有真实文件的 file:// 直载可靠。
 * 产物是引擎的零依赖单文件，挪目录不影响资源解析；也**不加 <base>**：架构图用
 * history.pushState 写 '#module=…'，基准 URL 一变就会抛 SecurityError。
 */
internal fun writeWrappedArtifact(path: String, headScript: String, cacheRoot: File): String {
    val body = withHeadScript(File(path).readText(), headScript)
    val out = File(File(cacheRoot, "deepDolphin/graph").apply { mkdirs() }, wrappedName(path))
    if (!out.exists() || out.length() != body.toByteArray(Charsets.UTF_8).size.toLong() || out.readText() != body) {
        out.writeText(body)
    }
    return out.absolutePath
}

private fun wrappedName(path: String): String =
    java.security.MessageDigest.getInstance("SHA-1").digest(path.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) } + ".html"

/**
 * 装载一个源：本机文件走 file:// 直载（对位 mac 的 loadFileURL，不跨网络）。
 * [headScript] 非空时先落一份带垫片的副本再直载。
 * ⚠️ 必须经 navigator：库只在创建 browser 时读一次 state.content 的初始值，之后给
 * `webViewState.content` 赋值不会触发任何装载（真窗口诊断抓到：赋了 Url，页面纹丝不动）。
 */
private suspend fun WebViewNavigator.load(source: HtmlSource, headScript: String?) {
    val path = when {
        source !is HtmlSource.LocalFile -> return
        headScript != null -> withContext(Dispatchers.IO) { writeWrappedArtifact(source.path, headScript, cacheRoot()) }
        else -> source.path
    }
    loadUrl(File(path).toURI().toString())
}

private fun cacheRoot(): File = File(System.getenv("XDG_CACHE_HOME") ?: (System.getProperty("user.home") + "/.cache"))

/** 页面事件：加载完成（携带就势注入 JS 的句柄）/ 装载失败（携带如实原因）。 */
sealed interface HtmlWebEvent {
    /** 页面加载完成；evaluate = 在当前页面上执行 JS（量高、取标题等）。 */
    class Loaded internal constructor(
        val evaluate: (script: String, onResult: (String?) -> Unit) -> Unit,
    ) : HtmlWebEvent

    /** 装载失败/超时（含主帧错误与 15s 看门狗触发）；why = 如实原因。 */
    data class Failed(val why: String) : HtmlWebEvent
}

/** KCEF 装载阶段（InitProgress 回调对位）：驱动兜底文案——首跑要下载二百多 MB，不能只说「装载中」。 */
enum class WebPhase(val key: String) {
    LOCATING("cmp.webview.phase.locating"),
    DOWNLOADING("cmp.webview.phase.downloading"),
    EXTRACTING("cmp.webview.phase.extracting"),
    INSTALLING("cmp.webview.phase.install"),
    INITIALIZING("cmp.webview.phase.initializing"),
}

/**
 * KCEF/JCEF 装载状态（每进程只尝试一次）。
 * 原生包钉在与 Java 绑定同源的 JBR 构建上（JcefBundle.kt 记了为什么必须钉）。
 * 判了停滞/失败也不杀装载线程——后台装完仍会翻 Ready，界面自动切换。
 */
object WebRuntime {
    sealed interface State {
        data object Init : State // 装载中（调用方先给兜底 UI）
        data object Ready : State // WebView 可用
        data class Failed(val why: String) : State // 装载失败/停滞（给原因）
    }

    /** 还没就绪时交给兜底槽的状态。 */
    sealed interface Pending {
        /** 装载中：text 按阶段如实说；pct 是下载进度 0..1（null = 不在下载阶段）。 */
        data class Loading(val text: String, val pct: Float?) : Pending

        /** 装载失败/停滞（后台可能仍在继续）。 */
        data class Failed(val why: String) : Pending
    }

    // ⚠️ 必须是 `by` 委托：原来写成 `val state = mutableStateOf(…)`，它是个 MutableState **对象**，
    // 下面 HtmlWebView 的 when (val s = WebRuntime.state) 三个 is 分支永远不匹配——
    // 图谱页因此一直空白：既不就绪、也不失败、连降级文案都不出（二次验证抓到，存在自组件诞生）。
    var state: State by mutableStateOf<State>(State.Init)
        private set

    private var phase: WebPhase? by mutableStateOf<WebPhase?>(null)

    /** 下载进度（0..1；null = 未知）。 */
    private var downloadPct: Float? by mutableStateOf<Float?>(null)

    @Volatile
    private var attempted = false

    /** 最近一次进度回调的时刻：停滞判据的基准（有进度就一直等）。 */
    @Volatile
    private var lastActivityNanos = System.nanoTime()

    private fun touch() {
        lastActivityNanos = System.nanoTime()
    }

    /** 当前兜底状态（装载中按阶段如实说）。 */
    fun pending(): Pending = when (val s = state) {
        is State.Failed -> Pending.Failed(s.why)
        else -> Pending.Loading(loadingText(), if (phase == WebPhase.DOWNLOADING) downloadPct else null)
    }

    private fun loadingText(): String {
        val p = phase ?: WebPhase.LOCATING
        return if (p == WebPhase.DOWNLOADING) {
            L10n.t(p.key, ((downloadPct ?: 0f) * 100).roundToInt())
        } else {
            L10n.t(p.key)
        }
    }

    suspend fun ensureReady() {
        if (attempted) return
        attempted = true
        // 安装目录按钉死的构建标识分子目录：换构建即换目录，不会复用到别的原生包
        val installDir = File(cacheRoot(), "deepDolphin/kcef/${JcefBundle.ID}")
        val pinned = JcefBundle.urlFor()
        Thread {
            try {
                KCEF.initBlocking(
                    builder = {
                        installDir(installDir)
                        download {
                            val url = pinned
                            if (url != null) {
                                custom("$url.checksum")
                                transformHttpResponse(JcefBundle.resolver(url))
                            } else {
                                // 未验证平台：KCEF 默认行为（追 JetBrainsRuntime 最新 release）
                                github()
                            }
                        }
                        progress {
                            onLocating { phase = WebPhase.LOCATING; touch() }
                            // KCEF 回调给的是 0..100 的百分数（实测抓到界面显示 3361%）；这里统一成 0..1
                            onDownloading {
                                downloadPct = (it / 100f).coerceIn(0f, 1f)
                                phase = WebPhase.DOWNLOADING
                                touch()
                            }
                            onExtracting { phase = WebPhase.EXTRACTING; touch() }
                            onInstall { phase = WebPhase.INSTALLING; touch() }
                            onInitializing { phase = WebPhase.INITIALIZING; touch() }
                            onInitialized { state = State.Ready }
                        }
                        settings { cachePath = File(installDir, "cache").absolutePath }
                    },
                    onError = { e ->
                        if (state is State.Init) {
                            state = State.Failed(e?.message ?: L10n.t("cmp.webview.unknownError"))
                        }
                    },
                    onRestartRequired = {
                        if (state is State.Init) {
                            state = State.Failed(L10n.t("cmp.webview.needRestart"))
                        }
                    },
                )
            } catch (t: Throwable) {
                if (state is State.Init) {
                    state = State.Failed(t.message ?: t.javaClass.simpleName)
                }
            }
        }.apply { isDaemon = true; name = "kcef-init" }.start()

        // 等就绪：有进度就一直等（首跑要下二百多 MB，网速不定）；连续无进度超过阈值才判停滞。
        // 下载阶段阈值短——网络断了很快能看出来；解压/安装/启动没有细粒度进度，阈值长。
        while (state is State.Init) {
            delay(250)
            val quiet = if (phase == WebPhase.EXTRACTING || phase == WebPhase.INSTALLING || phase == WebPhase.INITIALIZING) {
                SETUP_QUIET_MS
            } else {
                DOWNLOAD_QUIET_MS
            }
            if (System.nanoTime() - lastActivityNanos >= quiet * 1_000_000L) {
                state = State.Failed(L10n.t("cmp.webview.stalled", quiet / 1000))
                break
            }
        }
    }

    /** 下载阶段允许的最长无进度时间。 */
    private const val DOWNLOAD_QUIET_MS = 30_000L

    /** 解压/安装/启动阶段允许的最长无进度时间（一次性解出四百多 MB，慢盘上要几十秒）。 */
    private const val SETUP_QUIET_MS = 180_000L
}

/**
 * 通用 WebView：JCEF 就绪时装载 HtmlSource；未就绪/失败走 fallback 槽（调用方给降级 UI，
 * 如「装载中 + 阶段」「WebView 不可用 + 引擎产物路径」——不空白）。fillMaxSize 类尺寸由调用方 modifier 决定。
 *
 * @param source 装载目标；null = 还没有产物（本组件不渲染实体，调用方自管空态）
 * @param reloadToken 变更即强制重载（同源路径不变也要刷新；对位 mac reloadToken）
 * @param transparent 透明底：装载前的空白帧露出调用方底色（不闪白），产物自带背景盖在上面
 * @param onEvent 页面事件（加载完成带 JS 句柄 / 失败带原因）
 * @param headScript 插进产物 <head> 最前面的脚本（如 DARK_SCHEME_SHIM）；非空时先落一份带垫片的副本
 * @param fallback JCEF 未就绪/失败时的降级 UI 槽（收装载状态；不传则不渲染）
 */
@Composable
fun HtmlWebView(
    source: HtmlSource?,
    modifier: Modifier = Modifier,
    reloadToken: Any? = null,
    transparent: Boolean = false,
    onEvent: ((HtmlWebEvent) -> Unit)? = null,
    headScript: String? = null,
    fallback: (@Composable (WebRuntime.Pending) -> Unit)? = null,
) {
    LaunchedEffect(Unit) { WebRuntime.ensureReady() }
    when (val s = WebRuntime.state) {
        is WebRuntime.State.Ready ->
            WebViewBody(source, modifier, reloadToken, transparent, onEvent, headScript)
        else -> fallback?.invoke(WebRuntime.pending())
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
    headScript: String?,
) {
    // 先不装内容（NavigatorOnly）：browser 在组合时就创建，那时还没布局——引擎产物的初始化脚本
    // 按当时的 innerWidth/innerHeight 取景（架构图的 fit()），布局完成后只重设画布不重新取景，
    // 结果节点偏在视野外，要点「复位」才回来。这里量到真实尺寸、过两帧让 resize 落到 browser
    // 之后再装载（真窗口实测抓到）。
    val webViewState = remember(transparent) {
        WebViewState(WebContent.NavigatorOnly).apply {
            // OSR：轻量绘制进 Compose（heavyweight 窗口在滚动列表里会画穿其他组件）；
            // 透明与否由调用方定；图谱产物自带底色不闪白
            webSettings.desktopWebSettings.offScreenRendering = true
            webSettings.desktopWebSettings.transparent = transparent
        }
    }
    val navigator = rememberWebViewNavigator()
    var laidOut by remember(transparent) { mutableStateOf(false) }

    // 装载调度（对位 mac GraphWebView.updateNSView 的 Coordinator 去重）：
    // 源变更 → navigator 装载；同源仅 token 变 → reload()（垫了脚本的页面要重读、重落副本）
    val lastLoad = remember(transparent) { mutableStateOf<Pair<HtmlSource, Any?>?>(null) }
    LaunchedEffect(laidOut, source, reloadToken) {
        if (!laidOut) return@LaunchedEffect
        withFrameNanos { }
        withFrameNanos { }
        val last = lastLoad.value
        when {
            source == null -> {}
            // 同源仅 token 变 → reload()。垫了脚本的页面除外：它装的是读进来的快照，reload 只会把
            // 旧快照再放一遍，必须重读文件
            last != null && last.first == source && last.second != reloadToken && headScript == null -> navigator.reload()
            last == null || last.first != source || last.second != reloadToken -> navigator.load(source, headScript)
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
        modifier = modifier.onSizeChanged { if (it.width > 0 && it.height > 0) laidOut = true },
    )
}
