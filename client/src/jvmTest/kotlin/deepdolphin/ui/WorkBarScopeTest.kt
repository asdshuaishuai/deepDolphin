// WorkBarScopeTest.kt —— 工作条判据（mac Scope.swift ScopeRules 的 choice/routeOf/
// updateScope/busy 对位：范围↔selection 双向翻译、busy 聚合、全局项标题）。
//
// 纪律锚点（mac Scope.swift 原话）：范围选择器**不持有自己的状态**——
// 读 selection 翻译成范围、写回 goRoute，selection 的视图不是另一份真相。
// 徽章计数（pendingCommitsOf）判据在 HeroUpdateScopeTest，此处不重复。

package deepdolphin.ui

import deepdolphin.ui.AppModel.Route
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkBarScopeTest {

    @BeforeTest
    fun pinZh() {
        // 断言锚定 zh 文案：钉住语言，防宿主 locale / settings.conf 漂移翻红
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    // ── selection → 范围选择器取值：只有仓库级页面（详情 + 图谱两页）收敛到单仓库，其余全是全局 ──

    @Test
    fun projectRouteWithSelectionYieldsProjectChoice() {
        assertEquals(
            ScopeChoice.Project("vtest"),
            WorkBarScope.choice(Route.PROJECT, "vtest"),
        )
    }

    @Test
    fun everyNonProjectRouteIsGroupEvenWithStaleSelection() {
        // selectedProject 在离开详情页前可能残留旧值——路由说了算，残留不参与判定
        for (r in listOf(Route.DASHBOARD, Route.BOARD, Route.MILESTONES, Route.CONFIDENCE, Route.PATCHCHECK, Route.SETTINGS)) {
            assertEquals(ScopeChoice.Group, WorkBarScope.choice(r, "vtest"), "$r 应显示全局")
        }
    }

    @Test
    fun graphPagesFollowTheirRepository() {
        // 图谱两页跟着仓库走（用户定稿 2026-11-25）：看 vtest 的代码图谱/架构图时，更新范围就是 vtest
        assertEquals(ScopeChoice.Project("vtest"), WorkBarScope.choice(Route.GRAPH, "vtest"))
        assertEquals(ScopeChoice.Project("vtest"), WorkBarScope.choice(Route.ARCH, "vtest"))
        assertEquals(ScopeChoice.Group, WorkBarScope.choice(Route.GRAPH, null))
        assertEquals("vtest", WorkBarScope.updateScope(Route.GRAPH, "vtest"))
        assertEquals("vtest", WorkBarScope.updateScope(Route.ARCH, "vtest"))
    }

    @Test
    fun scopePickerOnGraphPageGoesToRepositoryDetail() {
        // 图谱页上在范围选择器里改选仓库 → 落到那个仓库的详情（图谱页只从详情的入口进）
        assertEquals(Route.PROJECT to "vtest", WorkBarScope.routeOf(WorkBarScope.choice(Route.GRAPH, "vtest")))
    }

    @Test
    fun projectRouteWithoutSelectionIsGroup() {
        assertEquals(ScopeChoice.Group, WorkBarScope.choice(Route.PROJECT, null))
        assertEquals(ScopeChoice.Group, WorkBarScope.choice(Route.PROJECT, "  ")) // 空白 = 没有选中
    }

    // ── 范围 → 路由写回（唯一写入口 goRoute；group 落仪表盘）──

    @Test
    fun routeOfGroupGoesToDashboard() {
        assertEquals(Route.DASHBOARD to null, WorkBarScope.routeOf(ScopeChoice.Group))
    }

    @Test
    fun routeOfProjectGoesToProjectDetail() {
        assertEquals(Route.PROJECT to "deepDolphin", WorkBarScope.routeOf(ScopeChoice.Project("deepDolphin")))
    }

    @Test
    fun choiceThenRouteRoundTrips() {
        // selection → choice → routeOf → selection 的往返必须回到原点，
        // 否则范围选择器会把用户带去另一个地方（「跳到不存在的项目」的老路）
        val selections = listOf(
            Route.PROJECT to "vtest",
            Route.DASHBOARD to null,
            Route.BOARD to null,
            Route.MILESTONES to null,
        )
        for ((r, p) in selections) {
            val (backR, backP) = WorkBarScope.routeOf(WorkBarScope.choice(r, p))
            // 任何全局视图写回都落仪表盘（mac ScopeChoice.section：group → dashboard）
            if (r == Route.PROJECT) assertEquals(r to p, backR to backP)
            else assertEquals(Route.DASHBOARD to null, backR to backP)
        }
    }

    // ── 双轨动作范围（与 choice 是两个东西：这个管动作打在谁身上）──

    @Test
    fun updateScopeNullEverywhereExceptProjectDetail() {
        assertNull(WorkBarScope.updateScope(Route.DASHBOARD, null))
        assertNull(WorkBarScope.updateScope(Route.BOARD, "vtest")) // 残留选中不算数
        assertNull(WorkBarScope.updateScope(Route.SETTINGS, null))
        assertEquals("vtest", WorkBarScope.updateScope(Route.PROJECT, "vtest"))
    }

    @Test
    fun updateScopeFeedsPendingBadge() {
        // updateScope 的产物就是 pendingCommitsOf/shallowUpdateLabel 的入参——串起来验一次
        assertEquals("浅更新 · vtest", shallowUpdateLabel(WorkBarScope.updateScope(Route.PROJECT, "vtest")))
        assertEquals("浅更新 · 全部", shallowUpdateLabel(WorkBarScope.updateScope(Route.BOARD, null)))
    }

    // ── 全局项标题（mac L10n zh workbar.global 逐字）──

    @Test
    fun globalLabelCarriesProjectCount() {
        assertEquals("全局看板（全部 0 个项目）", WorkBarScope.globalLabel(0))
        assertEquals("全局看板（全部 3 个项目）", WorkBarScope.globalLabel(3))
    }

    // ── busy 聚合（mac SidebarStatusStrip.busy：isLoading || busyAll || busyProject != nil）──

    @Test
    fun busyIsFalseOnlyWhenAllSourcesIdle() {
        assertFalse(WorkBarScope.busy(refreshing = false, busyAction = false, graphRendering = false))
    }

    @Test
    fun busyLightsOnAnySource() {
        assertTrue(WorkBarScope.busy(refreshing = true, busyAction = false, graphRendering = false), "读流刷新中")
        assertTrue(WorkBarScope.busy(refreshing = false, busyAction = true, graphRendering = false), "写操作跑着")
        assertTrue(WorkBarScope.busy(refreshing = false, busyAction = false, graphRendering = true), "图谱生成中")
    }

    // ── 状态条时间格式（mac .formatted(date: .omitted, time: .shortened) 的时分对位）──

    @Test
    fun statusStripTimeIsHourMinute() {
        val t = java.time.LocalDateTime.of(2026, 11, 24, 9, 5)
        assertEquals("09:05", formatStatusStripTime(t))
    }
}
