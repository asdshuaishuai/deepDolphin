// GraphPages.kt —— 图谱两页：代码图谱 / 架构图（mac CodeGraphPage.swift / ArchPage.swift /
// GraphWebView.swift / GraphChrome.swift 的 Compose 对位）。
//
// ⚠️ 用户定稿 2026-10-27（mac 基准同款）：**客户端不再原生绘制**。引擎 `render index` /
// `render arch` 的交互 HTML 产物（零依赖单文件：图谱自带列表/热力图双模式、关系连线、
// 下钻、返回上级、搜索、明暗主题、置信度报告）就是正身，本页用 WebView 直接装载该文件。
// 两份绘制实现必然漂移，HTML 的交互面客户端追不上。
//
// 页面职责对位 mac 收敛为三件事：
//   ① 触发引擎渲染（render index --confidence / render arch：复用或重绘，回执带版本）；
//   ② 从输出提回执末行与产物路径（纯函数，判据见 GraphParseTest；fixture 取自真机引擎）；
//   ③ 把产物装进 HtmlWebView；打开即渲染（复用判定生效时毫秒级），产物路径有进程内缓存
//      ——重开窗口先秒开旧图，再后台核验刷新（复用就不重载，画面没变就不闪）。
//
// 【打开形态】对位 mac 2026-10-27「独立窗口最大化」：Compose 下用
// Dialog(usePlatformDefaultWidth=false) + 92% 宽高近似全屏，标题「代码图谱/架构图 · 项目名」，带关闭。
// 【入口接线】详情页动作条「代码图谱/架构图」→ AppModel.renderGraphArtifact（busy 生成→成功即开页，
// 与 mac 探测逻辑的差异见其注释）。mac 头部的「AI 生成」按钮（GraphAgentTask 播种 agent）与
// 「外部打开」仍缺位——CMP 的 AgentSheet 尚无「关窗后回读产物」回调，不造假按钮。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import deepdolphin.engine.Engine
import kotlinx.coroutines.launch

// ── 回执/产物路径提取（纯函数；对位 mac CodeGraphPageVM.receipt / extractHTMLPath + 复用判定）──
//
// 输出形状以真机引擎为准（fixtures/render/ 四个文件取自 moongit 真跑）：
//   已重绘：/home/…/render/index.html · 首版（第 0 版）
//     图例注明：无置信度数据（confidence.json 缺席）——本页只呈现结构
//   已复用（产物未变）：/home/…/render/index.html · 首版（第 0 版）
//   已复用持久化渲染（首版（第 0 版））：/home/…/render/arch.html
// 路径黏在全角冒号后**无空格**——mac 的空格分词 + hasPrefix("/") 在此形状会漏提，
// 这里如实适配为「/ 开头、.html 结尾、不含空白」的 token 正则（语义同为绝对路径产物）。

/** 引擎回执的末行（版本/复用判定给用户看；mac receipt 同逻辑：最后一个非空行）。 */
fun receiptLine(text: String): String? =
    text.lineSequence().map { it.trim() }.lastOrNull { it.isNotEmpty() }

/** 产物绝对路径：全文第一个「以 / 开头、以 .html 结尾、中间无空白」的片段；没有 = null。 */
fun extractHtmlPath(text: String): String? =
    text.lineSequence()
        .flatMap { HTML_PATH_TOKEN.findAll(it) }
        .firstOrNull()?.value

// '/' 前不能是路径构成字符（字母数字/_/.-）——相对路径 render/index.html 里的 "/index.html"
// 不算产物（绝对路径语义与 mac hasPrefix("/") 一致）；真机输出里路径黏在全角冒号后，天然满足。
private val HTML_PATH_TOKEN = Regex("""(?<![\w/.-])/[^\s]+\.html""")

/** 复用判定（mac text.contains("复用")；引擎 en 语言的 "reused" 同语义一并识别）。 */
fun renderReused(text: String): Boolean =
    text.contains("复用") || text.contains("reused", ignoreCase = true)

/** 同源产物要不要重载 WebView：非复用（文件真的重写了）或路径变了才重载，否则不闪。 */
fun shouldReloadWebView(reused: Boolean, pathChanged: Boolean): Boolean = !reused || pathChanged

// ── 页面模型（mac CodeGraphPageVM / ArchPageVM 的公共骨架；两页只差 kind 的命令与文案）──

/** 底部回执条状态（mac GraphStatusBar 的 (ok, text) 对位）；null = 不占高度。 */
data class GraphReceipt(val ok: Boolean, val text: String)

/** 图谱两页的进程内产物缓存（mac static lastGoodPath 对位）：重开窗口先秒开旧图。 */
private val lastGoodPath = mutableMapOf<String, String>()

/** 缓存键的唯一口径（页内 init 与外部记账共用，防两处拼串漂移）。 */
private fun graphCacheKey(kind: GraphKind, project: String): String = "${kind.name}:$project"

/**
 * 进程内缓存记一笔产物路径——详情页入口 render 成功后调用（本批接线）：
 * 随后 openGraph/openArch 打开的页 init 即命中缓存先秒开旧图，
 * 页内后台核验再跑一遍 render，引擎复用判定毫秒级返回且不触发 WebView 重载（不闪）。
 */
fun rememberGraphArtifact(kind: GraphKind, project: String, path: String) {
    lastGoodPath[graphCacheKey(kind, project)] = path
}

@Stable
class GraphPageModel(
    val projectName: String,
    val kind: GraphKind,
    private val engine: Engine,
) {
    var rendering by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    /** WebView 正在展示的产物路径（null = 还没有，显示引导空态）。 */
    var htmlPath by mutableStateOf<String?>(null)
        private set
    /** 重新渲染后路径不变也要刷新 WebView（对位 mac reloadToken）。 */
    var reloadToken by mutableIntStateOf(0)
        private set
    /** 引擎回执（末行）：版本/复用/装载问题给用户看（底部状态条）。 */
    var status by mutableStateOf<GraphReceipt?>(null)

    private val cacheKey: String get() = graphCacheKey(kind, projectName)

    init {
        htmlPath = lastGoodPath[cacheKey]
    }

    /**
     * render（index --confidence / arch）：复用判定在引擎侧（产物新鲜就只报复用，代价毫秒级）。
     * `background` = 秒开缓存后的后台核验：产物仍是复用就不重载 WebView
     * （重载会闪一下，画面没变就不闪）。
     */
    suspend fun render(background: Boolean) {
        if (!background) {
            rendering = true; error = null
        }
        try {
            val text = engine.renderGraph(kind.cliKind, projectName, withConfidence = kind == GraphKind.INDEX)
            receiptLine(text)?.let { status = GraphReceipt(ok = true, text = it) }
            val p = extractHtmlPath(text)
            if (p != null) {
                val reused = renderReused(text)
                val pathChanged = htmlPath != p
                htmlPath = p
                lastGoodPath[cacheKey] = p
                if (shouldReloadWebView(reused, pathChanged)) reloadToken++
            } else {
                error = text.ifBlank { L10n.t("cmp.err.renderNoPath", kind.cliKind) }
                status = GraphReceipt(ok = false, text = receiptLine(text) ?: "render failed")
            }
        } catch (e: Exception) {
            error = e.message ?: e.javaClass.simpleName
            status = GraphReceipt(ok = false, text = error!!)
        } finally {
            rendering = false
        }
    }

    fun clearStatus() {
        status = null
    }
}

/** 两页只差这些：CLI 子命令、标题词、副标题（mac L10n 口径）、图标瓦片色与字形。 */
enum class GraphKind(
    val cliKind: String,
    private val titleKey: String,
    private val subtitleKey: String,
    val tileBrush: Brush,
    val tileGlyph: String,
) {
    INDEX(
        cliKind = "index",
        titleKey = "nav.graph",
        subtitleKey = "cgraph.subtitle",
        tileBrush = accentBrush(), // mac tint .blue → Palette.Accent 同语义内部深→亮渐变
        tileGlyph = "◈",
    ),
    ARCH(
        cliKind = "arch",
        titleKey = "nav.arch",
        subtitleKey = "arch.subtitle",
        tileBrush = deepBrush(), // mac tint .purple → Palette.Deep 同语义内部深→亮渐变
        tileGlyph = "▦",
    );

    /** 标题词随取随译（枚举只存键——L10n.t 在调用点求值，换语言即时生效）。 */
    fun titleWord(): String = L10n.t(titleKey)
    fun subtitle(): String = L10n.t(subtitleKey)
}

// ── 打开形态（对位 mac GraphWindows.open：独立窗口最大化）──

/**
 * 代码图谱页（对位 mac CodeGraphPage）：跑 `render index <项目> --confidence`，
 * 回执一行显示状态，HtmlWebView 装载引擎 HTML 产物；busy/error 三态诚实。
 */
@Composable
fun CodeGraphPage(model: AppModel, projectName: String) {
    GraphPageDialog(model, projectName, GraphKind.INDEX)
}

/** 架构图页（对位 mac ArchPage）：同机制跑 `render arch <项目>`。 */
@Composable
fun ArchPage(model: AppModel, projectName: String) {
    GraphPageDialog(model, projectName, GraphKind.ARCH)
}

@Composable
private fun GraphPageDialog(model: AppModel, projectName: String, kind: GraphKind) {
    val vm = remember(projectName, kind) { GraphPageModel(projectName, kind, model.engine) }
    val scope = rememberCoroutineScope()
    // 打开即渲染；有缓存路径时窗口已先秒开旧图，这里只是后台核验新鲜度（mac .task 对位）
    LaunchedEffect(vm) { vm.render(background = vm.htmlPath != null) }

    Dialog(
        onDismissRequest = { model.closeGraphPage(kind) },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            Modifier
                .fillMaxWidth(0.92f)
                .fillMaxHeight(0.92f)
                .clip(RoundedCornerShape(Radius.card))
                .background(Palette.Card),
        ) {
            GraphHeaderBar(
                title = "${kind.titleWord()} · $projectName",
                subtitle = kind.subtitle(),
                tileBrush = kind.tileBrush,
                tileGlyph = kind.tileGlyph,
                rendering = vm.rendering,
                onRefresh = { scope.launch { vm.render(background = false) } },
                onClose = { model.closeGraphPage(kind) },
            )
            HorizontalDivider(color = Palette.Stroke)
            GraphContentArea(Modifier.weight(1f).fillMaxWidth(), vm)
            HorizontalDivider(color = Palette.Stroke)
            GraphStatusBar(vm.status) { vm.clearStatus() }
        }
    }
}

/** 头部（mac GraphHeaderView 对位）：图标瓦片 + 标题 + 副标题 + 刷新/关闭动作区。 */
@Composable
private fun GraphHeaderBar(
    title: String,
    subtitle: String,
    tileBrush: Brush,
    tileGlyph: String,
    rendering: Boolean,
    onRefresh: () -> Unit,
    onClose: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Space.lg, vertical = Space.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // 图标瓦片：圆角方块 + 白色字形，同一产品两个页面的视觉锚（渐变 = 语义色内部深→亮）
        Box(
            Modifier.size(30.dp).clip(RoundedCornerShape(Radius.control)).background(tileBrush),
            contentAlignment = Alignment.Center,
        ) { Text(tileGlyph, style = Type.card.copy(color = Color.White)) }
        Spacer(Modifier.width(Space.md))
        Column(Modifier.weight(1f)) {
            Text(title, style = Type.title, maxLines = 1)
            Text(subtitle, style = Type.label, maxLines = 1)
        }
        if (rendering) {
            CircularProgressIndicator(Modifier.size(14.dp), color = Palette.Accent, strokeWidth = 2.dp)
            Spacer(Modifier.width(Space.sm))
        }
        ActionText(L10n.t("toolbar.refresh"), Palette.TextSecondary, enabled = !rendering, onClick = onRefresh)
        Spacer(Modifier.width(Space.sm))
        ActionText(L10n.t("common.close"), Palette.TextSecondary, enabled = true, onClick = onClose)
    }
}

/** 内容区（mac ZStack 对位）：有产物装 WebView；没有则 busy / error / 引导三态诚实。 */
@Composable
private fun GraphContentArea(modifier: Modifier, vm: GraphPageModel) {
    val path = vm.htmlPath
    Box(modifier.background(Palette.BgBase)) {
        if (path != null) {
            HtmlWebView(
                source = HtmlSource.LocalFile(path),
                modifier = Modifier.fillMaxSize(),
                reloadToken = vm.reloadToken,
                onEvent = { ev ->
                    if (ev is HtmlWebEvent.Failed) {
                        vm.status = GraphReceipt(ok = false, text = "WebView ${ev.why}")
                    }
                },
                fallback = { why -> WebViewUnavailable(why, path) },
            )
        } else {
            when {
                vm.rendering -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(Modifier.size(18.dp), color = Palette.Accent, strokeWidth = 2.dp)
                        Spacer(Modifier.height(Space.md))
                        Text(L10n.t("graph.rendering"), style = Type.body.copy(color = Palette.TextSecondary))
                    }
                }
                vm.error != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(
                        Modifier.padding(Space.lg),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(L10n.t("cmp.graph.renderFailed"), style = Type.section.copy(color = Palette.Amber))
                        Spacer(Modifier.height(Space.sm))
                        Text(vm.error ?: "", style = Type.body.copy(color = Palette.TextSecondary), maxLines = 6)
                    }
                }
                else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(L10n.t("cmp.graph.renderFirstOpen"), style = Type.body.copy(color = Palette.TextSecondary))
                }
            }
        }
    }
}

/** JCEF 缺席/失败时的整页降级（不空白）：如实给原因 + 引擎产物路径展示。 */
@Composable
private fun WebViewUnavailable(why: String, artifactPath: String) {
    Box(Modifier.fillMaxSize().background(Palette.BgBase), contentAlignment = Alignment.Center) {
        Column(
            Modifier.padding(Space.lg),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(L10n.t("cmp.graph.webviewNA"), style = Type.section.copy(color = Palette.Amber))
            Spacer(Modifier.height(Space.sm))
            Text(why, style = Type.body.copy(color = Palette.TextSecondary), maxLines = 4)
            Spacer(Modifier.height(Space.md))
            Text(L10n.t("cmp.graph.artifactPath"), style = Type.label)
            Text(
                artifactPath,
                style = Type.micro.copy(fontFamily = FontFamily.Monospace),
                color = Palette.TextSecondary,
                maxLines = 2,
            )
        }
    }
}

/** 底部回执条（mac GraphStatusBar 对位）：一行回执（ok=绿✓ / 失败=橙⚠），可关闭。 */
@Composable
private fun GraphStatusBar(receipt: GraphReceipt?, onDismiss: () -> Unit) {
    if (receipt == null) return
    Row(
        Modifier
            .fillMaxWidth()
            .background(if (receipt.ok) Color.Transparent else Palette.Amber.copy(alpha = 0.08f))
            .padding(horizontal = Space.lg, vertical = Space.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(if (receipt.ok) "✓" else "⚠", style = Type.label.copy(color = if (receipt.ok) Palette.Green else Palette.Amber))
        Spacer(Modifier.width(Space.sm))
        Text(
            receipt.text,
            style = Type.label.copy(fontFamily = FontFamily.Monospace),
            color = if (receipt.ok) Palette.TextSecondary else Palette.Amber,
            maxLines = 1,
        )
        Spacer(Modifier.weight(1f))
        ActionText("×", Palette.TextSecondary, enabled = true, onClick = onDismiss)
    }
}
