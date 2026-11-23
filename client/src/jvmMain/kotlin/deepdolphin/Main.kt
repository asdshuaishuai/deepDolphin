// Main.kt —— deepDolphin（Compose Multiplatform）入口。
//
// 批 1：窗口 + 引擎探活（C1）+ 仪表盘（C3）+ C2 周期轮询。
// 能力分批落地（C1–C11，对位 archive/bui 与 macos 基准）；每一步都可运行验证。

package deepdolphin

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.clickable
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowState
import androidx.compose.ui.window.application
import deepdolphin.engine.EngineLocator
import deepdolphin.engine.EngineProbe
import deepdolphin.ui.AppModel
import deepdolphin.ui.AppModel.Route
import deepdolphin.ui.AgentSheet
import deepdolphin.ui.SettingsPage
import deepdolphin.ui.BoardPage
import deepdolphin.ui.DashboardPage
import deepdolphin.ui.MilestonesPage
import deepdolphin.ui.Palette
import deepdolphin.ui.ProjectDetailView
import deepdolphin.ui.Radius
import deepdolphin.ui.Space
import deepdolphin.ui.Type
import kotlinx.coroutines.launch

@Composable
fun App(initialSection: String? = null, initialProject: String? = null) {
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
            busy = false
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
    Window(
        onCloseRequest = ::exitApplication,
        state = WindowState(width = 1280.dp, height = 860.dp),
        title = "deepDolphin",
    ) {
        App(initialSection = link.section, initialProject = link.project)
    }
}

/** 侧栏外壳（C3 四页路由；项目行点击进详情；布局对位 mac NavigationSplitView 侧栏）。 */
@Composable
fun SidebarShell(model: AppModel) {
    val route by model.route.collectAsState()
    val status by model.status.collectAsState()
    val selected by model.selectedProject.collectAsState()
    val projects = status?.projects.orEmpty()
    val readable = projects.count { it.isReadable }

    Row(Modifier.fillMaxSize()) {
        // ── 侧栏 ──
        Column(
            Modifier.width(230.dp).fillMaxHeight().background(Palette.Sidebar)
                .padding(horizontal = Space.md, vertical = Space.lg),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            // 品牌区（mac 侧栏顶部 app 名对位）
            Text("deepDolphin", style = Type.title, color = Palette.TextPrimary)
            Text("moonGit · 项目群进度引擎", style = Type.micro, color = Palette.TextTertiary)
            Spacer(Modifier.height(Space.lg))
            NavGroupLabel("视图")
            NavItem("仪表盘", Route.DASHBOARD == route) { model.goRoute(Route.DASHBOARD) }
            NavItem("看板", Route.BOARD == route) { model.goRoute(Route.BOARD) }
            NavItem("里程碑", Route.MILESTONES == route) { model.goRoute(Route.MILESTONES) }
            NavGroupLabel("仓库 · $readable/${projects.size}")
            projects.forEach { p ->
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
                Route.PROJECT -> ProjectDetailView(model)
                Route.SETTINGS -> SettingsPage(model)
            }
        }
    }
    // agent sheet（对位 mac .sheet(showAgent)：作用域跟随侧栏选中）
    val agentOpen by model.agentOpen.collectAsState()
    if (agentOpen) AgentSheet(model)
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
