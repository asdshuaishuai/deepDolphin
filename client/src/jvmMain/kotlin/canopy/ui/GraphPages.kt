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
//   ③ 把产物装进 HtmlWebView；进页即渲染（复用判定生效时毫秒级），产物路径有进程内缓存
//      ——再次进页先秒出旧图，再后台核验刷新（复用就不重载，画面没变就不闪）。
//
// 【页面框架】页头（标题 + 回执胶囊 + 三个按钮）之下整页都是产物：引擎产物在嵌入模式下自己收拢成
// 「命令条 + 画布 + 通栏底条」，布局按它拿到的视口算（按可用区域选列、泳道折行、取景），所以外壳这边
// 要做的只是——给它一个稳定、尽量大的视口（页头高度恒定、底下不压条）、把控件高/圆角/颜色令牌递过去。
//
// 【打开形态】用户定稿 2026-11-25：图谱两页**跟着仓库走**、是专门的页面、不弹窗——
// 路由 Route.GRAPH / Route.ARCH + selectedProject（仓库），入口在各仓库的详情页里。
// （mac 是独立最大化窗口 GraphWindows.open；此处以用户定稿为准，不追 mac。）
// 换仓库即换页；侧栏高亮所属仓库，页头「返回仓库」回详情。
// 【入口接线】详情页页头「代码图谱/架构图」入口 → AppModel.renderGraphArtifact（busy 生成→成功即进页，
// 与 mac 探测逻辑的差异见其注释）。mac 头部的「AI 生成」按钮（GraphAgentTask 播种 agent）与
// 「外部打开」仍缺位——CMP 的 AgentSheet 尚无「关窗后回读产物」回调，不造假按钮。

package canopy.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Stable
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

// ── 回执/产物路径提取（纯函数；对位 mac CodeGraphPageVM.receipt / extractHTMLPath + 复用判定）──
//
// 输出形状以真机引擎为准（fixtures/render/ 四个文件取自 cambium 真跑）：
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

/**
 * 置信度快照过期判定：引擎校验过「快照依据的索引版本 ≠ 当前索引版本」就不把旧快照叠上去
 * （旧行为是悄悄叠一张可能错位的热力图），回执里如实写明要先生成快照。
 * 那一句由引擎 `confidenceStaleNote` 唯一构造、CLI 文本与页面图例同一句；中英各认一处稳定锚。
 */
fun renderStaleConfidence(text: String): Boolean =
    text.contains("置信度快照过期") || text.contains("snapshot is stale", ignoreCase = true)

/**
 * 渲染完要不要补生成置信度快照再重绘：只有热力图（INDEX）会过期；架构图不叠加置信度。
 * 过期时这一页没有热力图，而本会话已经强制重绘过、刷新按钮也不会再生成快照——必须自愈。
 */
fun needsConfidenceRefresh(kind: GraphKind, text: String): Boolean =
    kind == GraphKind.INDEX && renderStaleConfidence(text)

/** 同源产物要不要重载 WebView：非复用（文件真的重写了）或路径变了才重载，否则不闪。 */
fun shouldReloadWebView(reused: Boolean, pathChanged: Boolean): Boolean = !reused || pathChanged

/** 回执里的产物绝对路径：全角或半角冒号后面的 `/…/x.html`（网址不算——它的冒号后面紧跟第二个斜杠）。 */
private val ARTIFACT_PATH_IN_RECEIPT = Regex("""[：:]\s*/(?!/)[^\s]*\.html""")

/**
 * 回执条上给用户看的一行：去掉产物的本机绝对路径——
 * 「已重绘：/home/…/store/p_x/render/index.html · 第 2 版」→「已重绘 · 第 2 版」。
 * 路径是内部位置，摆在状态条上只是一长串挤占宽度的字符；要用它时有去处（页头的「在浏览器中打开」、
 * WebView 没就位时的降级视图）。其余文字原样保留，一个字不改。
 */
fun receiptSummary(text: String): String =
    ARTIFACT_PATH_IN_RECEIPT.replace(text, "").replace(Regex("""\s*·\s*"""), " · ").trim()

// ── 页面模型（mac CodeGraphPageVM / ArchPageVM 的公共骨架；两页只差 kind 的命令与文案）──

/** 回执（mac GraphStatusBar 的 (ok, text) 对位）：渲染结果 / 装载问题 / 缩放核对；显示在页头的胶囊里，null = 不显示。 */
data class GraphReceipt(val ok: Boolean, val text: String)

/** 图谱两页的进程内产物缓存（mac static lastGoodPath 对位）：再次进页先秒出旧图。 */
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
    private val model: AppModel,
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
    /** 引擎回执（末行）：版本/复用/装载问题给用户看（页头的回执胶囊）。 */
    var status by mutableStateOf<GraphReceipt?>(null)

    private val cacheKey: String get() = graphCacheKey(kind, projectName)

    init {
        htmlPath = lastGoodPath[cacheKey]
    }

    /**
     * render（index --confidence / arch）：复用判定在引擎侧（产物新鲜就只报复用，代价毫秒级）。
     * `background` = 先秒出缓存产物后的后台核验：产物仍是复用就不重载 WebView
     * （重载会闪一下，画面没变就不闪）。
     */
    suspend fun render(background: Boolean) {
        if (!background) {
            rendering = true; error = null
        }
        try {
            val text = model.renderGraph(kind, projectName, allowForce = !background)
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

/** 两页只差这些：CLI 子命令、路由、标题词、副标题（mac L10n 口径）、图标瓦片色与字形。 */
enum class GraphKind(
    val cliKind: String,
    val route: AppModel.Route,
    private val titleKey: String,
    private val subtitleKey: String,
    val tileBrush: Brush,
    val tileIcon: FluentIcon,
) {
    INDEX(
        cliKind = "index",
        route = AppModel.Route.GRAPH,
        titleKey = "nav.graph",
        subtitleKey = "cgraph.subtitle",
        tileBrush = accentBrush(), // mac tint .blue → Palette.Accent 同语义内部深→亮渐变
        tileIcon = FluentIcon.DataHistogram,
    ),
    ARCH(
        cliKind = "arch",
        route = AppModel.Route.ARCH,
        titleKey = "nav.arch",
        subtitleKey = "arch.subtitle",
        tileBrush = deepBrush(), // mac tint .purple → Palette.Deep 同语义内部深→亮渐变
        tileIcon = FluentIcon.Organization,
    );

    /** 标题词随取随译（枚举只存键——L10n.t 在调用点求值，换语言即时生效）。 */
    fun titleWord(): String = L10n.t(titleKey)
    fun subtitle(): String = L10n.t(subtitleKey)
}

// ── 页面形态（用户定稿：跟着仓库走的独立页面，不弹窗）──

/**
 * 代码图谱页：跑 `render index <仓库> --confidence`，回执一行显示状态，HtmlWebView 装载引擎 HTML 产物。
 * 仓库取自路由的 selectedProject——页面跟着仓库走，换仓库即换页；busy/error 三态诚实。
 */
@Composable
fun CodeGraphPage(model: AppModel) {
    GraphPage(model, GraphKind.INDEX)
}

/** 架构图页：同机制跑 `render arch <仓库>`。 */
@Composable
fun ArchPage(model: AppModel) {
    GraphPage(model, GraphKind.ARCH)
}

@Composable
private fun GraphPage(model: AppModel, kind: GraphKind) {
    val project by model.selectedProject.collectAsState()
    val name = project
    // 路由守卫下进页必带仓库；真没有时如实说，不画一张没有主体的图
    if (name == null) {
        Box(Modifier.fillMaxSize().padding(Space.xl), contentAlignment = Alignment.Center) {
            Text(L10n.t("cmp.graph.noProject"), style = Type.body.copy(color = Palette.TextSecondary))
        }
        return
    }
    val vm = remember(name, kind) { GraphPageModel(name, kind, model) }
    val scope = rememberCoroutineScope()
    // 进页即渲染；有缓存路径时已先秒出旧图，这里只是后台核验新鲜度（mac .task 对位）
    LaunchedEffect(vm) { vm.render(background = vm.htmlPath != null) }

    Column(Modifier.fillMaxSize()) {
        GraphPageHeader(
            kind = kind,
            repo = name,
            rendering = vm.rendering,
            status = vm.status,
            onDismissStatus = { vm.clearStatus() },
            onRefresh = { scope.launch { vm.render(background = false) } },
            onBack = { model.backToRepo() },
            onOpenExternal = vm.htmlPath?.let { path ->
                {
                    openArtifactExternally(path)?.let { err ->
                        vm.status = GraphReceipt(ok = false, text = err)
                    }
                }
            },
        )
        // 引擎产物铺满页头以下的整页（不套卡片、不留边距、下面不再压回执条）：它自己的外壳已按嵌入模式
        // 收拢成「命令条 + 画布 + 通栏底条」，配色、控件高、圆角走客户端的设计令牌（见 GraphEmbed.kt）——
        // 产物就是这一页的主体，不是贴进来的一张网页。
        // 「卡片里再套卡片」是原样内嵌时最难看的根源：两层描边、两套圆角；
        // 「页头下面再压一条回执条」是第二难的：画布矮 28dp，底部与产物的底条叠成两条横杠（回执挪进页头了）。
        // ⚠️ 页头高度不随回执有无而变（状态胶囊定高、单行）——WebView 一落位就不许被状态变化挤动尺寸。
        GraphContentArea(Modifier.weight(1f).fillMaxWidth(), vm)
    }
}

/**
 * 用系统浏览器打开引擎产物（mac GraphHeaderView 的「在浏览器中打开」对位）：独立打开是完整版的图谱
 * （自带页头、技术状态条）。失败时如实返回原因，不静默。
 */
internal fun openArtifactExternally(path: String): String? = try {
    java.awt.Desktop.getDesktop().browse(java.io.File(path).toURI())
    null
} catch (e: Exception) {
    "browser: " + (e.message ?: e.javaClass.simpleName)
}

/**
 * 页头（与其它页头同一套间距与字级）：图标瓦片 + 标题 +「仓库 · 副标题」+ 回执胶囊 + 在浏览器中打开 / 刷新 / 返回仓库。
 * 回执（渲染结果 / 装载问题 / 缩放核对）摆在页头里而不是页面底下压一条：画布多出一条的高度，
 * 页面底部只剩产物自己的通栏底条。胶囊定高、单行——页头高度不随回执有无而变，WebView 不被挤动。
 */
@Composable
private fun GraphPageHeader(
    kind: GraphKind,
    repo: String,
    rendering: Boolean,
    onRefresh: () -> Unit,
    onBack: () -> Unit,
    onOpenExternal: (() -> Unit)? = null,
    status: GraphReceipt? = null,
    onDismissStatus: (() -> Unit)? = null,
) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Space.xl, vertical = Space.lg),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // 图标瓦片：圆角方块 + 白色图标，同一产品两个页面的视觉锚（渐变 = 语义色内部深→亮）
        Box(
            Modifier.size(32.dp).clip(RoundedCornerShape(Radius.control)).background(kind.tileBrush),
            contentAlignment = Alignment.Center,
        ) { IconBox(kind.tileIcon, size = 20.dp, tint = Color.White) }
        Spacer(Modifier.width(Space.md))
        Column(Modifier.weight(1f)) {
            Text(kind.titleWord(), style = Type.title)
            Text("$repo · ${kind.subtitle()}", style = Type.label, maxLines = 1)
        }
        if (rendering) {
            CircularProgressIndicator(Modifier.size(14.dp), color = Palette.Accent, strokeWidth = 2.dp)
            Spacer(Modifier.width(Space.sm))
            Text(L10n.t("graph.rendering"), style = Type.label, color = Palette.TextSecondary)
            Spacer(Modifier.width(Space.md))
        }
        status?.let { receipt ->
            Spacer(Modifier.width(Space.md))
            GraphReceiptChip(receipt, onDismissStatus)
            Spacer(Modifier.width(Space.md))
        }
        onOpenExternal?.let { open ->
            IconButton(FluentIcon.Open, onClick = open)
            Spacer(Modifier.width(Space.sm))
        }
        FluentButton(L10n.t("toolbar.refresh"), onClick = onRefresh, icon = FluentIcon.ArrowSync, enabled = !rendering)
        Spacer(Modifier.width(Space.sm))
        FluentButton(L10n.t("cmp.graph.backToRepo"), onClick = onBack, icon = FluentIcon.ArrowLeft)
    }
}

/** 页头里的回执胶囊（mac GraphStatusBar 的对位）：一行（ok = 绿✓ / 失败 = 橙⚠），可关闭；长文本截断。 */
@Composable
private fun GraphReceiptChip(receipt: GraphReceipt, onDismiss: (() -> Unit)?) {
    Row(
        Modifier
            .height(ControlHeight)
            .widthIn(max = ReceiptMaxWidth)
            .clip(RoundedCornerShape(Radius.chip))
            .background(if (receipt.ok) Palette.Card else Palette.Amber.copy(alpha = 0.10f))
            .border(Material.borderWidth, if (receipt.ok) Palette.Stroke else Palette.Amber.copy(alpha = 0.45f), RoundedCornerShape(Radius.chip))
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconBox(
            if (receipt.ok) FluentIcon.CheckmarkCircle else FluentIcon.Warning,
            size = 14.dp,
            tint = if (receipt.ok) Palette.Green else Palette.Amber,
        )
        Spacer(Modifier.width(Space.sm))
        Text(
            // 成功回执只留人读的部分；失败回执原文照录（原因里可能就有要去看的路径），放不下截断——
            // 完整原因在内容区的失败态与全局反馈条上都有
            if (receipt.ok) receiptSummary(receipt.text) else receipt.text,
            style = Type.label,
            color = if (receipt.ok) Palette.TextSecondary else Palette.Amber,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (onDismiss != null) {
            Spacer(Modifier.width(Space.sm))
            IconBox(
                FluentIcon.Dismiss, size = 12.dp, tint = Palette.TextSecondary,
                modifier = Modifier.clickable(onClick = onDismiss).padding(4.dp),
            )
        }
    }
}

/** 回执胶囊的最大宽度：再宽就截断——页头右侧还有三个按钮，窄窗口下先让标题。 */
private val ReceiptMaxWidth = 360.dp

/**
 * 仓库详情里进图谱两页的入口（用户定稿：入口在每个仓库里面）。
 * 带图标的小按钮——和旁边一排文字动作区分开，一眼能看出这是「进另一页」而不是又一个原地动作。
 */
@Composable
fun GraphEntryChip(label: String, icon: FluentIcon, tint: Color, enabled: Boolean, onClick: () -> Unit) {
    // Fluent reveal：hover 分层提亮 + 描边同步（与 GlassCard 同一节奏）
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val bg by animateColorAsState(
        if (hovered && enabled) Palette.CardHover else Palette.Card,
        androidx.compose.animation.core.tween(Motion.normal),
        label = "entryBg",
    )
    val stroke by animateColorAsState(
        if (hovered && enabled) Palette.StrokeHover else Palette.Stroke,
        androidx.compose.animation.core.tween(Motion.normal),
        label = "entryStroke",
    )
    Row(
        Modifier
            .clip(RoundedCornerShape(Radius.control))
            .background(bg)
            .border(Material.borderWidth, stroke, RoundedCornerShape(Radius.control))
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconBox(icon, size = 16.dp, tint = if (enabled) tint else Palette.TextTertiary)
        Spacer(Modifier.width(6.dp))
        Text(label, style = Type.body, color = if (enabled) Palette.TextPrimary else Palette.TextTertiary)
    }
}

/** 缩放倍率的写法：1× / 1.25×（Locale.ROOT——小数点恒为句点，回执文本不随区域设置变）。 */
internal fun scaleText(scale: Float): String =
    String.format(java.util.Locale.ROOT, "%.2f", scale).trimEnd('0').trimEnd('.') + "×"

/** 内容区（mac ZStack 对位）：有产物装 WebView；没有则 busy / error / 引导三态诚实。 */
@Composable
private fun GraphContentArea(modifier: Modifier, vm: GraphPageModel) {
    val path = vm.htmlPath
    Box(modifier.background(pageFill())) {
        if (path != null) {
            HtmlWebView(
                source = HtmlSource.LocalFile(path),
                modifier = Modifier.fillMaxSize(),
                reloadToken = vm.reloadToken,
                // 嵌入配置：收拢外壳 + 客户端的设计令牌（架构图另垫暗色，见 graphEmbedHeadScript）
                headScript = graphEmbedHeadScript(arch = vm.kind == GraphKind.ARCH),
                onEvent = { ev ->
                    when (ev) {
                        is HtmlWebEvent.Failed -> vm.status = GraphReceipt(ok = false, text = "WebView ${ev.why}")
                        // 外壳与内嵌内容的比例尺不是一把尺子：如实说，不悄悄缩放任何一边
                        is HtmlWebEvent.Scale -> if (ev.mismatched()) {
                            vm.status = GraphReceipt(
                                ok = false,
                                text = L10n.t("cmp.graph.scaleMismatch", scaleText(ev.hostScale), scaleText(ev.pageScale)),
                            )
                        }
                        else -> {}
                    }
                },
                fallback = { pending -> WebViewFallback(pending, path) },
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

/**
 * JCEF 未就绪/失败时的整页降级（不空白）：装载中给阶段与下载进度，失败如实给原因；
 * 两种情况都附引擎产物路径——WebView 没就位时文件也在，用户可以自己打开。
 */
@Composable
private fun WebViewFallback(pending: WebRuntime.Pending, artifactPath: String) {
    val loading = pending is WebRuntime.Pending.Loading
    val detail = when (pending) {
        is WebRuntime.Pending.Loading -> pending.text
        is WebRuntime.Pending.Failed -> pending.why
    }
    val pct = (pending as? WebRuntime.Pending.Loading)?.pct
    Box(Modifier.fillMaxSize().background(pageFill()), contentAlignment = Alignment.Center) {
        Column(
            Modifier.padding(Space.lg).width(420.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                L10n.t(if (loading) "cmp.graph.webviewPreparing" else "cmp.graph.webviewNA"),
                style = Type.section.copy(color = if (loading) Palette.TextPrimary else Palette.Amber),
            )
            Spacer(Modifier.height(Space.sm))
            Text(detail, style = Type.body.copy(color = Palette.TextSecondary), maxLines = 4)
            if (pct != null) {
                Spacer(Modifier.height(Space.md))
                LinearProgressIndicator(
                    progress = { pct },
                    modifier = Modifier.fillMaxWidth(),
                    color = Palette.Accent,
                    trackColor = Palette.Stroke,
                )
            }
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
