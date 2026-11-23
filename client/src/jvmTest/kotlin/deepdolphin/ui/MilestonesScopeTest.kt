// MilestonesScopeTest.kt —— 里程碑页取数口径的纯函数判据（对位 mac
// DashboardScope.swift:125-186 DashMilestoneScope + MilestonesView 的两步过滤）。
//
// 【fixture 为准】真实引擎输出（fixtures/milestones.json，2026-11 真机
// `milestone list --json` 锚定）：atlas 3 条（2 open + 1 done）+ beacon 1 条（open），
// readCount=4；条目恒带 projectName / completedAt。
// 【判据】先按项目收窄再叠搜索（顺序是语义：搜索词作用在收窄后的明细上）；
//   分组保持首现顺序；unknown 单列不混桶；空态两分（范围里真的没有 ≠ 搜不到）；
//   明细条数 ≠ readCount ⇒ 统计只是下界必须可判。

package deepdolphin.ui

import deepdolphin.engine.Milestone
import deepdolphin.engine.MilestoneList
import deepdolphin.engine.decodeOrThrow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MilestonesScopeTest {

    private fun fixture(name: String): String {
        val f = java.io.File("src/jvmTest/resources/fixtures/$name.json")
        check(f.isFile) { "fixture 缺失：${f.absolutePath}" }
        return f.readText()
    }

    private fun realList(): MilestoneList = decodeOrThrow(MilestoneList.serializer(), fixture("milestones"))

    private val ATLAS = "p_f6630122ab2e"
    private val BEACON = "p_835dc72b196f"

    // ── 镜像锚：真机键先立住（分组/筛选全靠它们）──

    @Test
    fun fixtureCarriesProjectNameAndCompletedAt() {
        val list = realList()
        // projectName 恒发：分组头/下拉不需要拿 status 注册表反查。
        assertEquals("atlas", list.milestones.first { it.projectId == ATLAS }.projectName)
        assertEquals("beacon", list.milestones.first { it.projectId == BEACON }.projectName)
        // completedAt（引擎真键名）：done 条目带值、open 条目空串——不是 null。
        val done = list.milestones.first { it.status == "done" }
        assertTrue(done.completedAt.isNotBlank(), "达成条目必须带达成时间")
        assertTrue(list.milestones.filter { it.status == "open" }.all { it.completedAt.isEmpty() })
    }

    // ── scope：先项目收窄（对位 mac items(_:project:)）──

    @Test
    fun projectScopeNarrowsDetailsOnly() {
        val all = realList().milestones
        assertEquals(4, DashMilestoneScope.items(all, null).size, "null = 全部，不收窄")
        assertEquals(3, DashMilestoneScope.items(all, ATLAS).size, "收窄到 atlas 明细 3 条")
        assertEquals(0, DashMilestoneScope.items(all, "p_missing").size, "收窄到不在册项目 = 该范围明细为空（不是失败）")
    }

    // ── 搜索叠加：作用在收窄后的明细上（对位 mac shown = SearchFilter.filter(scoped)）──

    @Test
    fun searchOverlaysOnScopeNotOnAll() {
        val all = realList().milestones
        // 全局搜「登录」：只有 atlas 的「接入统一登录」命中。
        assertEquals(
            listOf("接入统一登录"),
            SearchFilter.filter(DashMilestoneScope.items(all, null), "登录") { it.name }.map { it.name },
        )
        // 已收窄到 beacon 再搜「登录」：范围里 1 条、命中 0 条 → NoMatch（不是 NoData）。
        val scoped = DashMilestoneScope.items(all, BEACON)
        val shown = SearchFilter.filter(scoped, "登录") { it.name }
        assertEquals(0, shown.size)
        assertEquals(
            SearchEmpty.NoMatch("登录"),
            SearchFilter.emptyReason(allCount = scoped.size, shownCount = shown.size, query = "登录"),
            "有数据但没匹配 = NoMatch——不许把「搜不到」说成「本来就没有」",
        )
    }

    // ── 分组：首现顺序 + 计数（对位 mac groups(_:)）──

    @Test
    fun groupsKeepFirstAppearanceOrderWithCounts() {
        val all = realList().milestones
        val groups = DashMilestoneScope.groups(all)
        assertEquals(listOf("atlas", "beacon"), groups.map { it.projectName }, "首现顺序，不额外排序")
        assertEquals(3, groups[0].items.size)
        assertEquals(1, groups[1].items.size)
        assertEquals(4, groups.sumOf { it.items.size }, "分组不丢行不重复")
        // 「只看这个项目」语义：分组头动作把 projectFilter 设到该组 ⇒ 剩下的恰好是这一组。
        val pick = groups[1]
        assertEquals(pick.items, DashMilestoneScope.items(all, pick.projectId))
    }

    @Test
    fun groupsFallBackToProjectIdWhenNameMissing() {
        // projectName 缺键（旧引擎）回退 projectId——孤儿条目不丢、组头仍有可读标识。
        val g = DashMilestoneScope.groups(listOf(Milestone(projectId = "p_x", name = "m1"))).single()
        assertEquals("p_x", g.projectName)
    }

    // ── 统计：unknown 单列（对位 mac tally(_:)）──

    @Test
    fun tallyUnknownStandsAlone() {
        assertEquals(MsTally(3, 1, 0, 0), DashMilestoneScope.tally(realList().milestones))
        // null（缺键无法核验）与未来新增档位都进 unknown，不丢条、不猜语义。
        val t = DashMilestoneScope.tally(
            listOf(
                Milestone(status = "open"),
                Milestone(status = "done"),
                Milestone(status = "dropped"),
                Milestone(status = "unknown"),
                Milestone(status = null),
            ),
        )
        assertEquals(MsTally(1, 1, 1, 2), t)
    }

    // ── 空态两分：读取失败 ≠ 没有（对位 mac MilestonesView.swift:62-75 的判定顺序）──

    @Test
    fun emptyReasonSplitsNoDataFromNoMatchThroughPipeline() {
        val all = realList().milestones
        // 收窄到空范围 + 空查询 → NoData：「这个范围里真的没有」。
        val emptyScope = DashMilestoneScope.items(all, "p_missing")
        assertEquals(
            SearchEmpty.NoData,
            SearchFilter.emptyReason(allCount = emptyScope.size, shownCount = 0, query = ""),
        )
        // 全量 + 空查询不可能空（fixture 有 4 条）；NoData 只能来自空范围或真空数据。
        assertNull(SearchFilter.emptyReason(allCount = all.size, shownCount = all.size, query = ""))
        // 有数据 + 查询不匹配 → NoMatch（查询原样回显）。
        assertEquals(
            SearchEmpty.NoMatch("zzz"),
            SearchFilter.emptyReason(allCount = all.size, shownCount = 0, query = "zzz"),
        )
    }

    // ── 明细 ≠ 全量 ⇒ 统计只是下界（对位 mac isComplete(_:)）──

    @Test
    fun isCompleteFlagsDetailWindowBelowReadCount() {
        val list = realList()
        assertTrue(DashMilestoneScope.isComplete(list.milestones, list.readCount), "fixture：4 条明细 = readCount 4")
        // 明细被窗口截过（引擎只给了 2 条但读到 4 条）→ 不完整，界面必须披露下界。
        assertTrue(!DashMilestoneScope.isComplete(list.milestones.take(2), list.readCount))
        // readCount 缺席 = 不知道，按不完整处理让界面披露，不假装完整。
        assertTrue(!DashMilestoneScope.isComplete(list.milestones, null))
    }
}
