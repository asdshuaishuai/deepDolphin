// Main.kt —— deepDolphin（Compose Multiplatform）入口。
//
// 批 1：窗口 + 引擎探活（C1）+ 仪表盘（C3）+ C2 周期轮询。
// 能力分批落地（C1–C11，对位 archive/bui 与 macos 基准）；每一步都可运行验证。

package deepdolphin

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.application
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowState
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.window.ApplicationScope
import deepdolphin.engine.EngineLocator
import deepdolphin.engine.EngineProbe
import deepdolphin.sysint.TrayQuickView
import deepdolphin.ui.AgentBulkResultSheet
import deepdolphin.ui.AgentSheet
import deepdolphin.ui.AppMenuBar
import deepdolphin.ui.AppModel
import deepdolphin.ui.AppModel.Route
import deepdolphin.ui.ArchPage
import deepdolphin.ui.BoardPage
import deepdolphin.ui.BulkUpdateConfirmDialog
import deepdolphin.ui.CodeGraphPage
import deepdolphin.ui.ConfidencePage
import deepdolphin.ui.DashboardPage
import deepdolphin.ui.fluentColorScheme
import deepdolphin.ui.FluentShapes
import deepdolphin.ui.FluentTypography
import deepdolphin.ui.isRepoScoped
import deepdolphin.ui.L10n
import deepdolphin.ui.Liveness
import deepdolphin.ui.livenessOf
import deepdolphin.ui.MilestonesPage
import deepdolphin.ui.Motion
import deepdolphin.ui.Palette
import deepdolphin.ui.PatchCheckPage
import deepdolphin.ui.ProjectDetailView
import deepdolphin.ui.QuickViewDialog
import deepdolphin.ui.Radius
import deepdolphin.ui.runShortcut
import deepdolphin.ui.SearchEmpty
import deepdolphin.ui.SearchFilter
import deepdolphin.ui.SettingsPage
import deepdolphin.ui.AppShortcuts
import deepdolphin.ui.FluentButton
import deepdolphin.ui.FluentIcon
import deepdolphin.ui.IconBox
import deepdolphin.ui.ScrollColumn
import deepdolphin.ui.IconButton
import deepdolphin.ui.Emphasis
import deepdolphin.ui.SidebarSearchFocus
import deepdolphin.ui.SidebarStatusStrip
import deepdolphin.ui.Space
import deepdolphin.ui.Type
import deepdolphin.ui.WorkBar
import kotlinx.coroutines.launch

/** 托盘「速览」→ 速览窗开合的跨线程触发（AWT 菜单回调在 EDT，组合在 Compose 主线程；
 *  StateFlow 线程安全，Compose 侧 collectAsState 消费）。 */
object QuickViewTrigger {
    val open = kotlinx.coroutines.flow.MutableStateFlow(false)
}

@Composable
fun App(
    initialSection: String? = null,
    initialProject: String? = null,
    onTraySummary: ((String) -> Unit)? = null,
    onQuit: (() -> Unit)? = null,
) {
    val scope = rememberCoroutineScope()
    var probe by remember { mutableStateOf<EngineProbe?>(null) }
    var busy by remember { mutableStateOf(true) }
    var model by remember { mutableStateOf<AppModel?>(null) }
    // 托盘速览窗开合（mac MenuBarExtra 弹窗对位）：托盘菜单回调翻 QuickViewTrigger，
    // 窗体是 QuickViewDialog（380px；引擎缺席时也开得出——missing-engine 三态在窗内）。
    val quickViewOpen by QuickViewTrigger.open.collectAsState()

    // 深链只应用一次（「重新检测引擎」不再重复跳转）
    var deepLinkPending by remember { mutableStateOf(true) }

    fun reprobe() {
        busy = true
        scope.launch {
            probe = EngineLocator.probe()
            model = probe?.takeIf { it.found }?.let { AppModel(it.path) }
            // 全窗口快捷键在 AWT 层统一接管，动作执行的唯一出口是 runShortcut——焦点在主画布、输入框、
            // 弹出的菜单/对话框还是图谱页的 WebView 里都一致生效（不再挂在 Compose 的焦点链上）
            model?.let { m ->
                AppShortcuts.install { action, source ->
                    m.runShortcut(action) { SidebarSearchFocus.request(source) }
                    true
                }
            }
            model?.refreshAll()
            model?.startPolling() // C2 周期轮询 5 分钟
            // 深链路由必须在 model 就绪**之后**落地。原来紧跟在异步 reprobe() 后面同步执行，
            // 那时 model 还是 null——--section/--project 从来没生效过（二次验证抓到）。
            if (deepLinkPending) {
                deepLinkPending = false
                // section 与 project 一次落地：原来分两次 goRoute，带 --project 的 --section graph
                // 会被后一发 PROJECT 覆盖——图谱深链从来没落到过图谱页
                val section = initialSection?.let { sec ->
                    deepdolphin.ui.AppModel.Route.entries.firstOrNull { it.name.lowercase() == sec }
                }
                when {
                    section != null -> model?.goRoute(section, initialProject)
                    initialProject != null -> model?.goRoute(deepdolphin.ui.AppModel.Route.PROJECT, initialProject)
                }
            }
            // 托盘摘要行随探活结果刷新（引擎缺席也要在托盘里说真话，不挂着初始化文案）
            if (model == null) onTraySummary?.invoke(L10n.t("bar.noEngine"))
            busy = false
        }
    }

    // 托盘摘要行（mac BarView header summaryLine 对位）：status 流每次到货推一行。
    // env == null 是「还没读到」，不是「没有项目」——分开说（侧栏空态同纪律）。
    LaunchedEffect(model) {
        val m = model ?: return@LaunchedEffect
        m.status.collect { env ->
            onTraySummary?.invoke(
                if (env == null) L10n.t("cmp.tray.reading")
                else TrayQuickView.summaryLine(
                    total = env.projects.size,
                    dirtyProjects = env.summary.dirtyProjects,
                )
            )
        }
    }

    LaunchedEffect(Unit) { reprobe() }
    DisposableEffect(Unit) { onDispose { model?.stop() } }

    // mac NavigationSplitView 对位：无常驻顶栏——品牌入侧栏，引擎态全屏居中呈现
    when {
        busy -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator(Modifier.size(18.dp), color = Palette.Accent, strokeWidth = 2.dp)
                Spacer(Modifier.height(Space.md))
                Text(L10n.t("cmp.probe.locating"), style = Type.body.copy(color = Palette.TextSecondary))
            }
        }
        probe != null && probe!!.found && model != null -> Column(Modifier.fillMaxSize()) {
            // 窗口内菜单条（mac 原生菜单栏命令的等价物：操作/帮助）
            AppMenuBar(model!!, onQuit = { onQuit?.invoke() })
            Box(Modifier.weight(1f)) { SidebarShell(model!!) }
        }
        else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(L10n.t("bar.noEngine"), style = Type.title.copy(color = Palette.Amber))
                Spacer(Modifier.height(Space.sm))
                Text(L10n.t("cmp.probe.binHint"), style = Type.body.copy(color = Palette.TextSecondary))
                Spacer(Modifier.height(Space.lg))
                Button(
                    onClick = { reprobe() },
                    shape = androidx.compose.foundation.shape.RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Palette.OnAccent),
                ) { Text(L10n.t("setup.recheck")) }
            }
        }
    }

    // 托盘速览窗（mac BarView 完整形态）：引擎缺席时也开得出（missing-engine 三态在窗内）
    if (quickViewOpen) {
        QuickViewDialog(
            model = model,
            onOpenPanel = { java.awt.Window.getWindows().filter { it.isVisible }.forEach { it.toFront() } },
            onQuit = { onQuit?.invoke() },
            onDismiss = { QuickViewTrigger.open.value = false },
            onRedetect = {
                QuickViewTrigger.open.value = false
                reprobe()
            },
        )
    }
}

/** 关闭钩子的宽限时间：到点进程还在就硬退（见 [armExitWatchdog]）。 */
private const val EXIT_GRACE_MS = 4_000L

/**
 * 退出兜底：关闭钩子跑完自然退出最好；[EXIT_GRACE_MS] 内没退就 halt。
 * 实测抓到过：图谱页的浏览器状态异常后，CEF 的关闭钩子卡在「等客户端销毁」——进程收了 SIGTERM
 * 四分钟不退，窗口一直留在屏幕上。带原生组件的应用不能指望用户自己去杀进程。
 */
private fun armExitWatchdog() {
    Thread {
        Thread.sleep(EXIT_GRACE_MS)
        Runtime.getRuntime().halt(0)
    }.apply { isDaemon = true; name = "exit-watchdog" }.start()
}

/** 应用内退出的唯一出口（关窗 / 菜单 / 托盘）：关闭钩子 + 硬退兜底。
 *  （exitApplication 是 ApplicationScope 的成员，只能在 application {} 的作用域里调。） */
private fun ApplicationScope.exitApp() {
    armExitWatchdog()
    exitApplication()
}

fun main(vararg args: String) {
    // 启动打点（T0=main 进入；窗口首组合打 STARTUP_MS——性能判据）
    StartupMark.t0 = System.currentTimeMillis()
    // 外部 SIGTERM（会话注销、关机）走同一个带兜底的出口：先照常跑关闭钩子，卡住就硬退。
    // jdk.unsupported 的 Signal 不在（极简运行时）时保持默认行为，不影响启动。
    runCatching {
        sun.misc.Signal.handle(sun.misc.Signal("TERM")) {
            armExitWatchdog()
            Runtime.getRuntime().exit(0)
        }
    }
    application {
    // C10 深链：--section dashboard|board|milestones / --project <名>
    val link = deepdolphin.sysint.SysInt.parseDeepLink(args.toList())
    // 托盘速览（mac BarView MenuBarExtra 对位；AWT SystemTray/X11）：
    // isSupported() == false（如 Wayland 原生会话）→ install 返回 null，静默降级不报错。
    val tray = TrayQuickView.install(
        onOpenPanel = { java.awt.Window.getWindows().filter { it.isVisible }.forEach { it.toFront() } },
        onQuit = { exitApp() },
        onQuickView = { QuickViewTrigger.open.value = true },
    )
    Window(
        onCloseRequest = {
            tray?.remove()
            exitApp()
        },
        state = WindowState(width = 1280.dp, height = 860.dp),
        title = "deepDolphin",
    ) {
        LaunchedEffect(Unit) { StartupMark.report() }

        // 根主题：所有没显式配色的 Material 组件从这里取缺省（Fluent 暗色方案），
        // 不再回落到 M3 默认浅色——开关、输入框描边、菜单在暗色界面上曾经很突兀
        MaterialTheme(
            colorScheme = fluentColorScheme(),
            typography = FluentTypography,
            shapes = FluentShapes,
        ) {
            App(
                initialSection = link.section,
                initialProject = link.project,
                onTraySummary = tray?.let { t -> { line: String -> t.updateSummary(line) } },
                onQuit = { exitApp() },
            )
        }
    }
    }
}

/** 启动耗时上报（T0 由 main 记；窗口首组合时打 STARTUP_MS）。 */
internal object StartupMark {
    @Volatile var t0 = 0L
    @Volatile private var reported = false
    fun report() {
        if (t0 > 0 && !reported) {
            reported = true
            println("STARTUP_MS=" + (System.currentTimeMillis() - t0))
        }
    }
}

/** 侧栏外壳（C3 四页路由；项目行点击进详情；布局对位 mac NavigationSplitView 侧栏）。 */
@Composable
fun SidebarShell(model: AppModel, onQuit: () -> Unit = {}) {
    val route by model.route.collectAsState()
    val dash by model.dashboard.collectAsState()
    val status by model.status.collectAsState()
    val selected by model.selectedProject.collectAsState()
    val projects = status?.projects.orEmpty()

    // ── 侧栏搜索（mac PanelView.swift:19-36/238-262 sidebarSearch 对位）──
    // 搜索词空 = 不过滤；匹配键 = 项目名 + 分支名（记得「那条 feat 分支」也能搜到）。
    // 判定全在 SearchFilter 纯函数（可单测），这里只消费。
    var projectQuery by remember { mutableStateOf("") }
    val shownProjects = SearchFilter.filter(projects, projectQuery) { p ->
        p.name + " " + p.branches.joinToString(" ") { it.name }
    }
    // Ctrl+F 要能把光标送进搜索框（mac 自建搜索框 + @FocusState 的 Compose 对位：
    // FocusRequester 只吃自建输入框——这是不用封装件、用 BasicTextField 的原因）
    val searchFocus = SidebarSearchFocus.requester

    Row(Modifier.fillMaxSize()) {
        // ── 侧栏 ──
        Column(
            Modifier.width(230.dp).fillMaxHeight().background(Palette.Sidebar)
                .padding(horizontal = Space.md, vertical = Space.lg),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            // 品牌区（mac 侧栏顶部 app 名对位）
            Text("deepDolphin", style = Type.title, color = Palette.TextPrimary)
            Text(L10n.t("cmp.sidebar.subtitle"), style = Type.micro, color = Palette.TextTertiary)
            Spacer(Modifier.height(Space.md))
            // 侧栏搜索框（mac sidebarSearch：放大镜 + 素输入框 + 清除钮；
            // 搜索框在侧栏顶部、仓库组之上——过滤的是下面的「仓库」组）
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(Radius.control))
                    .background(Palette.Card)
                    .padding(horizontal = Space.sm, vertical = 6.dp),
            ) {
                IconBox(FluentIcon.Search, size = 16.dp, tint = Palette.TextSecondary)
                Spacer(Modifier.width(6.dp))
                BasicTextField(
                    value = projectQuery,
                    onValueChange = { projectQuery = it },
                    singleLine = true,
                    textStyle = Type.body.copy(color = Palette.TextPrimary),
                    modifier = Modifier.weight(1f).focusRequester(searchFocus),
                    decorationBox = { inner ->
                        Box {
                            if (projectQuery.isEmpty()) {
                                Text(L10n.t("panel.search.placeholder"), style = Type.body, color = Palette.TextTertiary)
                            }
                            inner()
                        }
                    },
                )
                if (projectQuery.isNotEmpty()) {
                    Spacer(Modifier.width(Space.xs))
                    IconBox(
                        FluentIcon.Dismiss,
                        size = 12.dp,
                        tint = Palette.TextSecondary,
                        modifier = Modifier.clickable { projectQuery = "" }.padding(4.dp),
                    )
                }
            }
            Spacer(Modifier.height(Space.sm))
            // 列表区可滚动（mac NavigationSplitView 内的 List 对位）：项目多时不再把多出的行压没，
            // 也不再挤掉底部的「添加/扫描」「设置」与状态条（二次验证抓到）
            ScrollColumn(Modifier.weight(1f)) {
            NavGroupLabel(L10n.t("nav.views"))
            NavItem(L10n.t("nav.dashboard"), Route.DASHBOARD == route, icon = FluentIcon.Home) { model.goRoute(Route.DASHBOARD) }
            // 行内计数（mac countedRow 对位）：看板 = 要你动手的项目数；里程碑 = 进行中 + 已达成。
            // 仪表盘还没读到时不出数（null ≠ 0）。
            val attentionCount: Long? = dash?.let { projects.count { livenessOf(it) == Liveness.NEEDS_ACTION } }?.toLong()
            val milestoneCount: Long? = dash?.let { it.milestones.counts.open + it.milestones.counts.done }
            NavItem(L10n.t("board.title"), Route.BOARD == route, count = attentionCount, icon = FluentIcon.Board) {
                model.goRoute(Route.BOARD)
            }
            NavItem(L10n.t("ms.page.title"), Route.MILESTONES == route, count = milestoneCount, icon = FluentIcon.Target) {
                model.goRoute(Route.MILESTONES)
            }
            // mac PanelView.swift:143-145 对位：两入口排在里程碑后（同属「视图」组）；
            // 文案对位 mac L10n zh：nav.confidence=代码置信度 / nav.patchcheck=补丁体检
            NavItem(L10n.t("nav.confidence"), Route.CONFIDENCE == route, icon = FluentIcon.ShieldCheckmark) {
                model.goRoute(Route.CONFIDENCE)
            }
            NavItem(L10n.t("nav.patchcheck"), Route.PATCHCHECK == route, icon = FluentIcon.Stethoscope) {
                model.goRoute(Route.PATCHCHECK)
            }
            // 仓库组计数 = 过滤后口径（readable/总数 既有披露不变，只是数的是 shown 集）；
            // 搜出来一部分时给 resultSummary 一行（mac resultSummary 对位）
            NavGroupLabel(L10n.t("nav.repos.count", shownProjects.count { it.isReadable }, shownProjects.size))
            SearchFilter.resultSummary(projects.size, shownProjects.size)?.let {
                Text(it, style = Type.micro, color = Palette.TextSecondary)
            }
            // 空结果两态分开说（mac emptyReason/emptyText 对位）：「本来就没有」≠「没匹配上」
            SearchFilter.emptyReason(projects.size, shownProjects.size, projectQuery)?.let { reason ->
                Text(
                    SearchFilter.emptyText(reason),
                    style = Type.micro,
                    color = if (reason == SearchEmpty.NoData) Palette.TextTertiary else Palette.TextSecondary,
                )
            }
            // 仓库组首行（mac PanelView.swift:153-166 对位）：已在某个仓库的页面里 = 一行说明；
            // 否则给「打开项目详情」直接进列表里的第一个
            val repoPage = selected?.takeIf { route.isRepoScoped() }
            if (repoPage != null) {
                Text(
                    L10n.t(if (route == Route.GRAPH) "nav.graph" else if (route == Route.ARCH) "nav.arch" else "nav.projectDetail"),
                    style = Type.micro,
                    color = Palette.TextSecondary,
                )
            } else if (projects.isNotEmpty()) {
                NavItem(L10n.t("nav.openProjectDetail"), false, icon = FluentIcon.FolderOpen) {
                    projects.first().name.let { model.goRoute(Route.PROJECT, it) }
                }
            }
            shownProjects.forEach { p ->
                RepoItem(
                    p.name + (if (p.isReadable) "" else L10n.t("cmp.repos.unreadableSuffix")),
                    status = if (p.isReadable) p.primaryBranch?.status else null,
                    // 有未提交改动时行尾给「●N」（mac PanelView.swift:186-189 对位）
                    dirtyCount = (p.userDirtyCount ?: 0).takeIf { it > 0 },
                    unreadable = !p.isReadable,
                    // 仓库级页面（详情 + 跟仓库走的图谱两页）都高亮所属仓库
                    selected = route.isRepoScoped() && selected == p.name,
                    // 读不出的项目也要能点进去看原因——不可点等于把失败藏起来
                ) { model.goRoute(Route.PROJECT, p.name) }
            }
            } // 列表区（可滚动）收口
            // 「添加 / 扫描项目」是动作不是导航项，放侧栏底部动作区（mac PanelView.swift:213-221 对位；
            // 原来挂在仪表盘 hero 上，mac 的 hero 只有项目群说明）
            Box(Modifier.fillMaxWidth().height(1.dp).background(Palette.Stroke))
            NavItem(L10n.t("nav.addScan"), false, icon = FluentIcon.FolderAdd) { model.openScanSheet(single = false) }
            // 设置收在侧栏最底部（mac 原生 Settings scene 的 Linux 对位）
            NavItem(L10n.t("toolbar.settings"), Route.SETTINGS == route, icon = FluentIcon.Settings) {
                model.goRoute(Route.SETTINGS)
            }
            // ── 侧栏底部状态条（mac WorkBar.swift SidebarStatusStrip 对位，PanelView.swift:228
            //    挂点同位：设置项之下、侧栏最底）──
            // 原来这里是静态的「引擎在线」绿点——探活成功≠一直在采集，那是把常量画成状态。
            // 换成动态两行：有没有东西在跑（busy 聚合）+ 上次刷新时间（lastRefreshed）。
            Spacer(Modifier.height(Space.sm))
            Box(Modifier.fillMaxWidth().height(1.dp).background(Palette.Stroke))
            SidebarStatusStrip(model)
        }
        // ── 主区 ──
        Box(Modifier.weight(1f).fillMaxHeight().background(Palette.BgBase)) {
            Column(Modifier.fillMaxSize()) {
                // 内容区顶部工作条（mac WorkBar；PanelView.swift:465-469 挂点对位）：
                // ⚠️ 只在**有项目**时出现——没项目时范围选择器没有第二个选项，
                // 它就是一根装饰条（mac 原话）。范围选择器 + 双轨链都在这条上。
                // 设置页不挂工作条（mac 设置是独立窗口，上面没有范围选择器与更新按钮）。
                if (projects.isNotEmpty() && route != Route.SETTINGS) WorkBar(model)
                // 全局反馈条（mac PanelView 的 lastError / 写操作结果）：在看板、里程碑、置信度、
                // 体检、设置页点「停止更新」或里程碑增删，原来没有任何可见反馈。
                // 项目详情页有自己的结果行（带就地「AI 解读」），不重复显示；
                // 图谱两页没有自己的结果行，渲染失败/置信度快照跳过都在这条上说。
                if (route != Route.PROJECT) FeedbackStrip(model)
                Box(Modifier.weight(1f)) {
                    when (route) {
                        Route.DASHBOARD -> DashboardPage(model)
                        Route.BOARD -> BoardPage(model)
                        Route.MILESTONES -> MilestonesPage(model)
                        Route.CONFIDENCE -> ConfidencePage(model)
                        Route.PATCHCHECK -> PatchCheckPage(model)
                        Route.PROJECT -> ProjectDetailView(model)
                        // 图谱两页跟着仓库走（用户定稿：不弹窗、专门一页、入口在仓库里）
                        Route.GRAPH -> CodeGraphPage(model)
                        Route.ARCH -> ArchPage(model)
                        Route.SETTINGS -> SettingsPage(model)
                    }
                }
            }
        }
    }
    // agent sheet（对位 mac .sheet(showAgent)：作用域跟随侧栏选中）
    val agentOpen by model.agentOpen.collectAsState()
    if (agentOpen) AgentSheet(model)

    // 扫描单（对位 mac .sheet(showScan)，PanelView.swift:92-94）：仪表盘 hero「添加/扫描」打开
    val scanSheet by model.scanSheet.collectAsState()
    scanSheet?.let { deepdolphin.ui.ScanSheet(model, initialSingle = it) }

    // 全量更新两框（对位 mac DeepGitApp.swift:327-356：告知式确认框 + 全量结果面板
    // 都挂在主面板上——双轨按钮「· 全部」是唯一发起入口）
    if (model.pendingBulk.collectAsState().value != null) BulkUpdateConfirmDialog(model)
    if (model.bulkReport.collectAsState().value != null) AgentBulkResultSheet(model)
}

/** 分组小标题（mac List Section header 对位：大写微字号 + tertiary 色）。 */
@Composable
fun NavGroupLabel(label: String) {
    Text(
        label.uppercase(),
        style = Type.micro.copy(fontWeight = FontWeight.Bold),
        color = Palette.TextTertiary,
        modifier = Modifier.padding(start = 23.dp, top = Space.md, bottom = Space.xs), // 与导航文字左缘对齐
    )
}

@Composable
fun NavItem(label: String, selected: Boolean, count: Long? = null, icon: FluentIcon? = null, onClick: () -> Unit) {
    // Fluent NavigationView 形态：选中 = 左 accent pill 指示条 + accent 10% 分层底（150ms 渐变），
    // 文字保持 primary（Fluent 选中不改文字色为白）
    val bg by animateColorAsState(
        if (selected) Palette.Accent.copy(alpha = 0.10f) else Color.Transparent,
        animationSpec = tween(Motion.normal), label = "navBg",
    )
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(Radius.control))
            .background(bg)
            .clickable { onClick() }
            .padding(horizontal = 10.dp, vertical = 8.dp),
    ) {
        // Fluent 选中 pill 指示条（3dp 宽 16dp 高圆条，accent）
        Box(
            Modifier.width(3.dp).height(16.dp)
                .background(if (selected) Palette.Accent else Color.Transparent,
                    androidx.compose.foundation.shape.RoundedCornerShape(2.dp))
        )
        Spacer(Modifier.width(10.dp))
        // 图标（Fluent NavigationView：选中项图标转 accent，未选中跟随次级文字）
        icon?.let {
            IconBox(it, size = 18.dp, tint = if (selected) Palette.Accent else Palette.TextSecondary)
            Spacer(Modifier.width(10.dp))
        }
        Text(
            label,
            style = Type.body.copy(fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal),
            color = Palette.TextPrimary,
            modifier = Modifier.weight(1f),
        )
        // 行内计数用文字而不是 badge（mac 实测：选择型列表的行上挂 .badge 会让这一行点不动）
        count?.let {
            Spacer(Modifier.width(Space.sm))
            Text(it.toString(), style = Type.micro, color = Palette.TextSecondary)
        }
    }
}

/** 页面顶部的反馈条：写操作结果一行 / 最近的读取错误；可关。 */
@Composable
private fun FeedbackStrip(model: AppModel) {
    val result by model.lastResult.collectAsState()
    val error by model.lastError.collectAsState()
    if (result == null && error == null) return
    Row(
        Modifier.fillMaxWidth().background(Palette.Card)
            .drawBehind {
                drawRect(color = Palette.Stroke, size = size.copy(height = 1.dp.toPx()))
            }
            .padding(horizontal = Space.xl, vertical = Space.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val shown = result
        val failed = shown != null && "✗" in shown
        val (mark, markTint) = when {
            error != null -> FluentIcon.Warning to Palette.Amber
            failed -> FluentIcon.ErrorCircle to Palette.Amber
            else -> FluentIcon.CheckmarkCircle to Palette.Green
        }
        IconBox(mark, size = 16.dp, tint = markTint)
        Spacer(Modifier.width(Space.sm))
        Text(
            shown ?: error.orEmpty().removePrefix("⚠ "),
            style = Type.label,
            color = if (error != null || failed) Palette.Amber else Palette.TextSecondary,
            maxLines = 3,
            modifier = Modifier.weight(1f),
        )
        IconButton(FluentIcon.Dismiss, onClick = { model.dismissFeedback() })
    }
}

/** 仓库行（小字号版导航项；读不出来的项目用暗红名 + 问号 badge）。 */
@Composable
fun RepoItem(label: String, status: String?, dirtyCount: Long?, unreadable: Boolean, selected: Boolean, onClick: () -> Unit) {
    // Fluent：选中 = accent 8% 分层底（150ms 渐变），pill 指示条交给 NavItem 一级导航
    val bg by animateColorAsState(
        if (selected) Palette.Accent.copy(alpha = 0.08f) else Color.Transparent,
        animationSpec = tween(Motion.normal), label = "repoBg",
    )
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(Radius.control))
            .background(bg)
            .clickable { onClick() } // 读不出的行也能点进去看原因（enabled = !unreadable 等于把失败藏起来）
            .padding(horizontal = 10.dp, vertical = 6.dp),
    ) {
        // 状态点读引擎的分支档位（mac StatusDot(status:) 对位）；读不出来 = 红点
        Box(
            Modifier.size(8.dp).background(repoRowTint(status, unreadable), androidx.compose.foundation.shape.CircleShape)
        )
        Spacer(Modifier.width(8.dp))
        Text(
            label,
            style = Type.micro.copy(fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal),
            color = if (unreadable) Palette.TextSecondary else Palette.TextPrimary,
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        dirtyCount?.let {
            Spacer(Modifier.width(Space.xs))
            Box(Modifier.size(6.dp).background(Palette.Amber, androidx.compose.foundation.shape.CircleShape))
            Spacer(Modifier.width(3.dp))
            Text(it.toString(), style = Type.micro, color = Palette.Amber)
        }
    }
}

/** 档位 → 颜色（mac StatusDot：active=绿 / idle=黄 / stale=橙 / merged=紫）；没分支记录 = 中性灰。 */
private fun repoRowTint(status: String?, unreadable: Boolean): Color = when {
    unreadable -> Palette.Red
    status == "active" -> Palette.Green
    status == "idle" -> Palette.Yellow
    status == "stale" -> Palette.Amber
    status == "merged" -> Palette.Deep
    else -> Palette.TextTertiary
}
