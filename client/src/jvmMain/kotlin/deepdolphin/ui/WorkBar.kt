// WorkBar.kt —— 内容区顶部工作条 + 侧栏底部状态条（mac WorkBar.swift 全文对位）。
//
// 【为什么要有这条，按 mac 基准说的】设计稿的顶栏是一条**工作条**，不是一排图标：
//   左边：范围选择器「全局看板 (All Managed Repos)」——在「看整个项目群」与
//         「看某一个仓库」之间切换；
//   右边：双轨主链路「浅更新（带待处理计数）→ 深更新」——两个动作是**一条链的两段**，
//         不是两个并列按钮。
// mac 改版规范 §3.1「原生标题栏 + 分组侧栏工作台」：不自绘标题栏（丢标准窗口行为），
// 工作条放**内容区顶部**，工具类动作（刷新/搜索/设置）与主链路分家。
//
// 【范围选择器的纪律（mac Scope.swift 原话）】不持有自己的状态：读 model.route /
// selectedProject、写回 model.goRoute。它是 selection 的一个**视图**，不是另一份真相
// ——侧栏回答「看哪个视图」，范围回答「看哪些仓库」，两个正交选择在此交汇。
//
// 【链上「箭头」的处理】mac WorkBar.swift:91-95：两个按钮之间**不画字面箭头**——
// 工具栏里的箭头图标会被读成「可点的第三项」。链的语义（浅在前、深在后、深更重）
// 由顺序 + 双轨语义色表达（浅=Shallow 绿 / 深=Deep 紫）。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import deepdolphin.engine.Project
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

// ── 纯函数层（mac Scope.swift ScopeRules 对位；零 Compose 依赖，判据直接测）──

/** 范围选择器的取值（mac ScopeChoice 对位：group / project(name)）。 */
sealed interface ScopeChoice {
    data object Group : ScopeChoice
    data class Project(val name: String) : ScopeChoice
}

object WorkBarScope {

    /** selection → 范围选择器取值（mac ScopeRules.choice 对位）。
     *  只有「正在看某个项目详情」才收敛到那个项目；其余（仪表盘/看板/里程碑/置信度/
     *  补丁体检/设置/没有任何选中）都是全局——看板与里程碑同样是全局视图，
     *  范围选择器只分「全局 / 单仓库」，不承载「看哪个视图」。 */
    fun choice(route: AppModel.Route?, selectedProject: String?): ScopeChoice =
        if (route == AppModel.Route.PROJECT && !selectedProject.isNullOrBlank()) {
            ScopeChoice.Project(selectedProject)
        } else {
            ScopeChoice.Group
        }

    /** 范围 → 路由（mac ScopeChoice.section 对位）。**只有一个写入口**：goRoute。
     *  直接改 route 会绕开路由校验——那正是「跳到不存在的项目」的老路。 */
    fun routeOf(c: ScopeChoice): Pair<AppModel.Route, String?> = when (c) {
        ScopeChoice.Group -> AppModel.Route.DASHBOARD to null
        is ScopeChoice.Project -> AppModel.Route.PROJECT to c.name
    }

    /** 全局项标题（mac L10n zh workbar.global 逐字对位）。 */
    fun globalLabel(projectCount: Int): String = "全局看板（全部 $projectCount 个项目）"

    /** selection → 双轨动作范围（mac ScopeRules.scope / UpdateScope 对位）。
     *  与 [choice] 是两个不同的东西：这个管「更新动作打在谁身上」，那个管「主区显示谁」。
     *  它们在「选中某个项目」时恰好相等，但公式各自独立成函数（mac 同款），不合并。
     *  null = 全部（引擎 updateAll 只管注册表里那些）。 */
    fun updateScope(route: AppModel.Route?, selectedProject: String?): String? =
        (choice(route, selectedProject) as? ScopeChoice.Project)?.name

    /** 「现在有没有东西在跑」聚合（mac SidebarStatusStrip.busy 三源对位：
     *  isLoading / busyAll / busyProject != nil 任一）。
     *  CMP 的三源如实映射：refreshing ↔ isLoading（读流刷新）、busyAction ↔ busyAll 与
     *  busyProject 的合一（CMP 写操作不按范围拆 busy 流，一个 busyAction 管全部——
     *  保守侧聚合，宁可多亮不漏亮）、graphRendering 是 CMP 特有第三源
     *  （图谱生成同样占用引擎，计入「正在采集」）。 */
    fun busy(refreshing: Boolean, busyAction: Boolean, graphRendering: Boolean): Boolean =
        refreshing || busyAction || graphRendering
}

// ── 双轨按钮的范围文案与待记录数（mac Scope.swift ScopeRules 对位；自 DashboardView 迁入，
//    随双轨按钮归位工作条；判据 HeroUpdateScopeTest 不变）──

/**
 * 浅更新按钮标题（mac ScopeRules.shallowLabel 逐字对位）。**必须带范围**：
 * 同一个按钮在两种范围下动作完全不同，不写清楚用户按下前无从知道会动谁。
 * null = 未选项目 = 全部（引擎 updateAll 只管注册表里那些，「全部项目」的「项目」在按钮上省作「全部」）。
 */
fun shallowUpdateLabel(project: String?): String = "浅更新 · ${project ?: "全部"}"

/** 深更新同理（mac deepLabel 对位）。 */
fun deepUpdateLabel(project: String?): String = "深更新 · ${project ?: "全部"}"

/**
 * 范围内待记录提交数（浅更新按钮徽章，mac ScopeRules.pending 对位）：
 * 当前分支 pendingCommits 求和（引擎 status 实时计算；读不出的项目 branches 空 = 0）。
 * project = null ⇒ 全部项目之和。
 */
fun pendingCommitsOf(projects: List<Project>, project: String?): Long =
    projects
        .filter { project == null || it.name == project }
        .sumOf { p -> p.branches.filter { it.isCurrent }.sumOf { it.pendingCommits } }

// ── 工作条（内容区顶部；挂点在 Main.SidebarShell 主区，只在有项目时出现）──

/** 内容区顶部工作条：左范围选择器 + Spacer + 右双轨链（mac WorkBar 对位）。 */
@Composable
fun WorkBar(model: AppModel) {
    val route by model.route.collectAsState()
    val selected by model.selectedProject.collectAsState()
    val status by model.status.collectAsState()
    val refreshing by model.refreshing.collectAsState()
    val busyAction by model.busyAction.collectAsState()
    val graphRendering by model.graphRendering.collectAsState()
    val projects = status?.projects.orEmpty()
    val busy = WorkBarScope.busy(refreshing, busyAction, graphRendering != null)
    val scoped = WorkBarScope.updateScope(route, selected)
    val pending = pendingCommitsOf(projects, scoped)

    Column(Modifier.fillMaxWidth().background(Palette.Card)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Space.lg, vertical = Space.sm),
        ) {
            ScopePicker(model, projects, WorkBarScope.choice(route, selected))
            Spacer(Modifier.weight(1f))
            DualTrackPipeline(model, scoped, busy, pending)
        }
        // mac .overlay(alignment: .bottom) 的 1px 分隔线：工作条与页面内容的界线
        Box(Modifier.fillMaxWidth().height(1.dp).background(Palette.Stroke))
    }
}

/** 范围选择器：globe 图标感 + 当前范围 + 下拉（mac WorkBar.scopePicker 对位）。 */
@Composable
private fun ScopePicker(model: AppModel, projects: List<Project>, current: ScopeChoice) {
    var open by remember { mutableStateOf(false) }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(Radius.control))
            .clickable { open = true }
            .padding(horizontal = Space.sm, vertical = 6.dp),
    ) {
        Text("◍", style = Type.body, color = Palette.TextTertiary)
        Spacer(Modifier.width(Space.xs))
        Text(
            when (current) {
                ScopeChoice.Group -> WorkBarScope.globalLabel(projects.size)
                is ScopeChoice.Project -> current.name
            },
            style = Type.body,
            color = Palette.TextPrimary,
            maxLines = 1,
        )
        Text(" ▾", style = Type.label, color = Palette.TextTertiary)
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            // 只列真实存在的项目（mac 同款）：projects 为空时全局项也不会指向不存在的仓库
            DropdownMenuItem(
                text = { Text(WorkBarScope.globalLabel(projects.size)) },
                onClick = {
                    open = false
                    val (r, p) = WorkBarScope.routeOf(ScopeChoice.Group)
                    model.goRoute(r, p)
                },
            )
            projects.forEach { p ->
                DropdownMenuItem(
                    text = { Text(p.name + (if (p.isReadable) "" else "（读不出）")) },
                    onClick = {
                        open = false
                        val (r, proj) = WorkBarScope.routeOf(ScopeChoice.Project(p.name))
                        model.goRoute(r, proj)
                    },
                )
            }
        }
    }
}

/**
 * 双轨链「浅更新 → 深更新」（mac DualTrackButtons，AIIntegration.swift:306 对位）。
 * 浅前深后、语义色区分；**不画字面箭头**（见文件头）。busy 时链尾小转圈。
 *
 * 【范围=全部 先确认】对位 mac DestructiveGuard：批量更新会改写**多个仓库**的托管
 * 区域——按下不直接跑，先弹告知式确认框（说清动几个仓库、留备份、可回滚，不染红）；
 * 单项目范围照旧直接跑（用户正盯着那个仓库，按钮上的范围文案就是确认）。
 */
@Composable
private fun DualTrackPipeline(model: AppModel, scoped: String?, busy: Boolean, pending: Long) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.sm),
    ) {
        Button(
            onClick = {
                if (scoped != null) model.updateProject(scoped, deep = false) else model.requestBulkUpdate(deep = false)
            },
            enabled = !busy,
            shape = RoundedCornerShape(Radius.control),
            colors = ButtonDefaults.buttonColors(
                containerColor = Palette.Shallow,
                contentColor = Color.White,
            ),
        ) {
            Text(shallowUpdateLabel(scoped))
            // 待记录徽章只在真有东西时出现（恒显 0 会被无视，且「0」容易被读成
            // 「引擎说不用更新」——mac 原话）；白底深字保证在绿底上读得清
            if (pending > 0) {
                Spacer(Modifier.width(6.dp))
                Text(
                    "$pending",
                    style = Type.micro.copy(fontWeight = FontWeight.Bold, color = Palette.BgBase),
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(Color.White)
                        .padding(horizontal = 5.dp, vertical = 1.dp),
                )
            }
        }
        Button(
            onClick = {
                if (scoped != null) model.updateProject(scoped, deep = true) else model.requestBulkUpdate(deep = true)
            },
            enabled = !busy,
            shape = RoundedCornerShape(Radius.control),
            colors = ButtonDefaults.buttonColors(
                containerColor = Palette.Deep,
                contentColor = Color.White,
            ),
        ) { Text(deepUpdateLabel(scoped)) }
        if (busy) {
            CircularProgressIndicator(
                Modifier.size(14.dp),
                color = Palette.Accent,
                strokeWidth = 2.dp,
            )
        }
    }
}

// ── 侧栏底部状态条（mac WorkBar.swift SidebarStatusStrip 对位）──
//
// mac 设计稿左下角是「● Git Hook Active · Syncing」——我们没装 Git Hook，
// **不编一个「Hook Active」**，只报确实知道的两件事：现在有没有东西在跑、上次刷新是什么时候。
// 读不出来与「还没刷新过」是两件事，措辞必须不同。

/** 状态条时间格式（mac .formatted(date: .omitted, time: .shortened) 的时分对位）。 */
val StatusStripTime: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

@Composable
fun SidebarStatusStrip(model: AppModel) {
    val refreshing by model.refreshing.collectAsState()
    val busyAction by model.busyAction.collectAsState()
    val graphRendering by model.graphRendering.collectAsState()
    val busy = WorkBarScope.busy(refreshing, busyAction, graphRendering != null)
    val lastRefreshed by model.lastRefreshed.collectAsState()
    val lastError by model.lastError.collectAsState()
    val status by model.status.collectAsState()

    Column(Modifier.fillMaxWidth().padding(horizontal = Space.md, vertical = Space.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(7.dp).background(
                    if (busy) Palette.Accent else Palette.Shallow,
                    CircleShape,
                )
            )
            Spacer(Modifier.width(Space.xs))
            Text(
                if (busy) "正在采集…" else "空闲",
                style = Type.micro,
                color = Palette.TextSecondary,
            )
            Spacer(Modifier.weight(1f))
            lastRefreshed?.let {
                Text(it.format(StatusStripTime), style = Type.micro, color = Palette.TextTertiary)
            }
        }
        // 第二行两态分开说（mac 同款）：读不出来 ≠ 还没刷新过
        if (lastError != null && status?.projects?.isEmpty() != false) {
            Text(
                "引擎读取失败：${lastError!!.lineSequence().first().take(80)}",
                style = Type.micro,
                color = Palette.Amber,
                maxLines = 1,
            )
        } else if (lastRefreshed == null) {
            Text("尚未刷新", style = Type.micro, color = Palette.TextTertiary)
        }
    }
}

/** 供判据与预览使用的直通辅助：LocalDateTime → 状态条文本。 */
fun formatStatusStripTime(t: LocalDateTime): String = t.format(StatusStripTime)
