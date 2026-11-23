// Main.kt —— deepDolphin（Compose Multiplatform）入口。
//
// 批 1：窗口 + 引擎探活（C1）+ 仪表盘（C3）+ C2 周期轮询。
// 能力分批落地（C1–C11，对位 archive/bui 与 macos 基准）；每一步都可运行验证。

package deepdolphin

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.clickable
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowState
import androidx.compose.ui.window.application
import deepdolphin.engine.EngineLocator
import deepdolphin.engine.EngineProbe
import deepdolphin.sysint.TrayQuickView
import deepdolphin.ui.AppModel
import deepdolphin.ui.AppModel.Route
import deepdolphin.ui.AgentSheet
import deepdolphin.ui.SearchEmpty
import deepdolphin.ui.SearchFilter
import deepdolphin.ui.SettingsPage
import deepdolphin.ui.ShortcutMap
import deepdolphin.ui.BoardPage
import deepdolphin.ui.ConfidencePage
import deepdolphin.ui.DashboardPage
import deepdolphin.ui.MilestonesPage
import deepdolphin.ui.PatchCheckPage
import deepdolphin.ui.Palette
import deepdolphin.ui.ArchPage
import deepdolphin.ui.CodeGraphPage
import deepdolphin.ui.ProjectDetailView
import deepdolphin.ui.Radius
import deepdolphin.ui.Space
import deepdolphin.ui.Type
import kotlinx.coroutines.launch

@Composable
fun App(
    initialSection: String? = null,
    initialProject: String? = null,
    onTraySummary: ((String) -> Unit)? = null,
) {
    val scope = rememberCoroutineScope()
    var probe by remember { mutableStateOf<EngineProbe?>(null) }
    var busy by remember { mutableStateOf(true) }
    var model by remember { mutableStateOf<AppModel?>(null) }

    fun reprobe() {
        busy = true
        scope.launch {
            probe = EngineLocator.probe()
            model = probe?.takeIf { it.found }?.let { AppModel(it.path) }
            model?.refreshAll()
            model?.startPolling() // C2 周期轮询 5 分钟
            // 托盘摘要行随探活结果刷新（引擎缺席也要在托盘里说真话，不挂着初始化文案）
            if (model == null) onTraySummary?.invoke("未找到 moonGit 引擎")
            busy = false
        }
    }

    // 托盘摘要行（mac BarView header summaryLine 对位）：status 流每次到货推一行。
    // env == null 是「还没读到」，不是「没有项目」——分开说（侧栏空态同纪律）。
    LaunchedEffect(model) {
        val m = model ?: return@LaunchedEffect
        m.status.collect { env ->
            onTraySummary?.invoke(
                if (env == null) "正在读取项目群…"
                else TrayQuickView.summaryLine(
                    total = env.projects.size,
                    dirtyProjects = env.summary.dirtyProjects,
                )
            )
        }
    }

    LaunchedEffect(Unit) {
        reprobe()
        // C10 深链路由（引擎探活后落地；非法 section 已在 parseDeepLink 归 dashboard）
        initialSection?.let { sec ->
            deepdolphin.ui.AppModel.Route.entries.firstOrNull { it.name.lowercase() == sec }
                ?.let { model?.goRoute(it) }
        }
        initialProject?.let { model?.goRoute(deepdolphin.ui.AppModel.Route.PROJECT, it) }
    }
    DisposableEffect(Unit) { onDispose { model?.stop() } }

    // mac NavigationSplitView 对位：无常驻顶栏——品牌入侧栏，引擎态全屏居中呈现
    when {
        busy -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator(Modifier.size(18.dp), color = Palette.Accent, strokeWidth = 2.dp)
                Spacer(Modifier.height(Space.md))
                Text("正在定位引擎…", style = Type.body.copy(color = Palette.TextSecondary))
            }
        }
        probe != null && probe!!.found && model != null -> SidebarShell(model!!)
        else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("未找到 moonGit 引擎", style = Type.title.copy(color = Palette.Amber))
                Spacer(Modifier.height(Space.sm))
                Text("MOONGIT_BIN / DEEPGIT_BIN 或安装到 PATH 后重试", style = Type.body.copy(color = Palette.TextSecondary))
                Spacer(Modifier.height(Space.lg))
                Button(
                    onClick = { reprobe() },
                    shape = androidx.compose.foundation.shape.RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
                ) { Text("重新检测引擎") }
            }
        }
    }
}

fun main(vararg args: String) = application {
    // C10 深链：--section dashboard|board|milestones / --project <名>
    val link = deepdolphin.sysint.SysInt.parseDeepLink(args.toList())
    // 托盘速览（mac BarView MenuBarExtra 对位；AWT SystemTray/X11）：
    // isSupported() == false（如 Wayland 原生会话）→ install 返回 null，静默降级不报错。
    val tray = TrayQuickView.install(
        onOpenPanel = { java.awt.Window.getWindows().filter { it.isVisible }.forEach { it.toFront() } },
        onQuit = { exitApplication() },
    )
    Window(
        onCloseRequest = {
            tray?.remove()
            exitApplication()
        },
        state = WindowState(width = 1280.dp, height = 860.dp),
        title = "deepDolphin",
    ) {
        App(
            initialSection = link.section,
            initialProject = link.project,
            onTraySummary = tray?.let { t -> { line: String -> t.updateSummary(line) } },
        )
    }
}

/** 侧栏外壳（C3 四页路由；项目行点击进详情；布局对位 mac NavigationSplitView 侧栏）。 */
@Composable
fun SidebarShell(model: AppModel) {
    val route by model.route.collectAsState()
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
    val searchFocus = remember { FocusRequester() }

    Row(
        Modifier
            .fillMaxSize()
            // 窗口级快捷键（mac ShortcutMap + keyboardShortcut 对位）：onPreviewKeyEvent
            // 挂窗口内容根——隧道相位先于任何聚焦子级（含输入框）拿到键事件。
            // 键位唯一来源是 ShortcutMap 纯对象；这里只做动作接线。
            .onPreviewKeyEvent { e ->
                if (!e.isCtrlPressed) return@onPreviewKeyEvent false
                when (ShortcutMap.actionOf(ctrlPressed = true, key = e.key)) {
                    ShortcutMap.Action.DASHBOARD -> { model.goRoute(Route.DASHBOARD); true }
                    ShortcutMap.Action.BOARD -> { model.goRoute(Route.BOARD); true }
                    ShortcutMap.Action.MILESTONES -> { model.goRoute(Route.MILESTONES); true }
                    ShortcutMap.Action.SETTINGS -> { model.goRoute(Route.SETTINGS); true }
                    ShortcutMap.Action.REFRESH -> { model.refreshAll(); true }
                    ShortcutMap.Action.FOCUS_SEARCH -> {
                        runCatching { searchFocus.requestFocus() }
                        true
                    }
                    null -> false
                }
            }
    ) {
        // ── 侧栏 ──
        Column(
            Modifier.width(230.dp).fillMaxHeight().background(Palette.Sidebar)
                .padding(horizontal = Space.md, vertical = Space.lg),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            // 品牌区（mac 侧栏顶部 app 名对位）
            Text("deepDolphin", style = Type.title, color = Palette.TextPrimary)
            Text("moonGit · 项目群进度引擎", style = Type.micro, color = Palette.TextTertiary)
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
                Text("⌕", style = Type.body, color = Palette.TextTertiary)
                Spacer(Modifier.width(Space.xs))
                BasicTextField(
                    value = projectQuery,
                    onValueChange = { projectQuery = it },
                    singleLine = true,
                    textStyle = Type.body.copy(color = Palette.TextPrimary),
                    modifier = Modifier.weight(1f).focusRequester(searchFocus),
                    decorationBox = { inner ->
                        Box {
                            if (projectQuery.isEmpty()) {
                                Text("搜索项目 / 分支", style = Type.body, color = Palette.TextTertiary)
                            }
                            inner()
                        }
                    },
                )
                if (projectQuery.isNotEmpty()) {
                    Spacer(Modifier.width(Space.xs))
                    Text(
                        "×",
                        style = Type.body,
                        color = Palette.TextTertiary,
                        modifier = Modifier.clickable { projectQuery = "" }.padding(horizontal = 2.dp),
                    )
                }
            }
            Spacer(Modifier.height(Space.sm))
            NavGroupLabel("视图")
            NavItem("仪表盘", Route.DASHBOARD == route) { model.goRoute(Route.DASHBOARD) }
            NavItem("看板", Route.BOARD == route) { model.goRoute(Route.BOARD) }
            NavItem("里程碑", Route.MILESTONES == route) { model.goRoute(Route.MILESTONES) }
            // mac PanelView.swift:143-145 对位：两入口排在里程碑后（同属「视图」组）；
            // 文案对位 mac L10n zh：nav.confidence=代码置信度 / nav.patchcheck=补丁体检
            NavItem("代码置信度", Route.CONFIDENCE == route) { model.goRoute(Route.CONFIDENCE) }
            NavItem("补丁体检", Route.PATCHCHECK == route) { model.goRoute(Route.PATCHCHECK) }
            // 仓库组计数 = 过滤后口径（readable/总数 既有披露不变，只是数的是 shown 集）；
            // 搜出来一部分时给 resultSummary 一行（mac resultSummary 对位）
            NavGroupLabel("仓库 · ${shownProjects.count { it.isReadable }}/${shownProjects.size}")
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
            shownProjects.forEach { p ->
                RepoItem(
                    p.name + (if (p.isReadable) "" else "（读不出）"),
                    unreadable = !p.isReadable,
                    selected = Route.PROJECT == route && selected == p.name,
                ) { if (p.isReadable) model.goRoute(Route.PROJECT, p.name) }
            }
            Spacer(Modifier.weight(1f))
            // 设置收在侧栏最底部（mac 原生 Settings scene 的 Linux 对位）
            NavItem("设置", Route.SETTINGS == route) { model.goRoute(Route.SETTINGS) }
            Spacer(Modifier.height(Space.sm))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(6.dp).background(
                        Palette.Green, androidx.compose.foundation.shape.CircleShape,
                    )
                )
                Spacer(Modifier.width(6.dp))
                Text("引擎在线", style = Type.micro, color = Palette.TextSecondary)
                Spacer(Modifier.weight(1f))
                Text("moongit", style = Type.micro, color = Palette.TextTertiary)
            }
        }
        // ── 主区 ──
        Box(Modifier.weight(1f).fillMaxHeight().background(Palette.BgBase)) {
            when (route) {
                Route.DASHBOARD -> DashboardPage(model)
                Route.BOARD -> BoardPage(model)
                Route.MILESTONES -> MilestonesPage(model)
                Route.CONFIDENCE -> ConfidencePage(model)
                Route.PATCHCHECK -> PatchCheckPage(model)
                Route.PROJECT -> ProjectDetailView(model)
                Route.SETTINGS -> SettingsPage(model)
            }
        }
    }
    // agent sheet（对位 mac .sheet(showAgent)：作用域跟随侧栏选中）
    val agentOpen by model.agentOpen.collectAsState()
    if (agentOpen) AgentSheet(model)

    // 扫描单（对位 mac .sheet(showScan)，PanelView.swift:92-94）：仪表盘 hero「添加/扫描」打开
    val scanSheet by model.scanSheet.collectAsState()
    scanSheet?.let { deepdolphin.ui.ScanSheet(model, initialSingle = it) }

    // 图谱两页（对位 mac GraphWindows.open 独立最大化窗口）：开合流驱动，本批无入口（下一批接线）
    val graphPage by model.graphPage.collectAsState()
    graphPage?.let { CodeGraphPage(model, it) }
    val archPage by model.archPage.collectAsState()
    archPage?.let { ArchPage(model, it) }
}

/** 分组小标题（mac List Section header 对位：大写微字号 + tertiary 色）。 */
@Composable
fun NavGroupLabel(label: String) {
    Text(
        label.uppercase(),
        style = Type.micro.copy(fontWeight = FontWeight.Bold),
        color = Palette.TextTertiary,
        modifier = Modifier.padding(top = Space.md, bottom = Space.xs),
    )
}

@Composable
fun NavItem(label: String, selected: Boolean, onClick: () -> Unit) {
    // 左对齐导航项：选中态 = 左指示条 + accent 淡底；hover 由 compose 可点击态涟漪自然呈现
    val bg = if (selected) Palette.Accent.copy(alpha = 0.85f) else Color.Transparent
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(8.dp))
            .background(bg)
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 9.dp),
    ) {
        // 选中左指示条
        Box(
            Modifier.width(3.dp).height(16.dp)
                .background(if (selected) Color.White else Color.Transparent,
                    androidx.compose.foundation.shape.RoundedCornerShape(2.dp))
        )
        Spacer(Modifier.width(10.dp))
        Text(
            label,
            style = Type.body.copy(fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal),
            color = if (selected) Color.White else Palette.TextPrimary,
        )
    }
}

/** 仓库行（小字号版导航项；读不出来的项目用暗红名 + 问号 badge）。 */
@Composable
fun RepoItem(label: String, unreadable: Boolean, selected: Boolean, onClick: () -> Unit) {
    val bg = if (selected) Palette.Accent.copy(alpha = 0.25f) else Color.Transparent
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(6.dp))
            .background(bg)
            .clickable(enabled = !unreadable) { onClick() }
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        Box(
            Modifier.size(8.dp).background(
                if (unreadable) Palette.Red.copy(alpha = 0.7f) else Palette.Green.copy(alpha = 0.7f),
                androidx.compose.foundation.shape.CircleShape)
        )
        Spacer(Modifier.width(8.dp))
        Text(
            label,
            style = Type.micro.copy(fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal),
            color = if (unreadable) Palette.TextSecondary else Palette.TextPrimary,
            maxLines = 1,
        )
    }
}
