// DashScopeTest.kt —— 仪表盘纯判定层判据（mac DashboardScope / CommitTypeComposition /
// LanguageCoverage / MilestoneCard 的断言对位）。
//
// 筛选控件要成立，就必须真的有东西被它改变；KPI 的每个数字必须说得出它数的是什么。
// 二次验证抓到过：时间窗胶囊只换高亮从不参与过滤；「活跃」KPI 读的是引擎从不发的字段，恒为 0。

package deepdolphin.ui

import deepdolphin.engine.Branch
import deepdolphin.engine.CommitTypeCount
import deepdolphin.engine.DashMilestones
import deepdolphin.engine.DashProjects
import deepdolphin.engine.DashWork
import deepdolphin.engine.DashboardData
import deepdolphin.engine.Milestone
import deepdolphin.engine.MilestoneCounts
import deepdolphin.engine.Project
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DashScopeTest {

    @BeforeTest
    fun pinZh() {
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    private val day = 86_400_000L
    private val now = 1_800_000_000_000L

    private fun committed(daysAgo: Long?) = Project(
        name = "p",
        lastCommitAt = daysAgo?.let {
            java.time.OffsetDateTime.ofInstant(java.time.Instant.ofEpochMilli(now - it * day), java.time.ZoneOffset.UTC).toString()
        } ?: "",
    )

    // ── 时间跨度：按最近更新天数分档；读不出来一律保留 ──

    @Test
    fun spanFilterReallyFilters() {
        val fresh = committed(3)
        val weekOld = committed(7)
        val weekPlus = committed(8)
        val monthPlus = committed(31)
        val unknown = committed(null)
        val all = listOf(fresh, weekOld, weekPlus, monthPlus, unknown)
        // 近 7 天：恰好 7 天算在内；读不出更新时间的始终保留
        assertEquals(listOf(fresh, weekOld, unknown), all.filter { DashFilter(span = DashSpan.D7).keeps(it, now) })
        // 近 30 天：8 天前的在内，31 天前的在外
        assertEquals(listOf(fresh, weekOld, weekPlus, unknown), all.filter { DashFilter(span = DashSpan.D30).keeps(it, now) })
        assertEquals(5, all.count { DashFilter().keeps(it, now) }, "全量不筛")
        assertTrue(updatedWithin(unknown, 7, now), "读不出更新时间的项目始终保留——滤掉它等于说「它不在近 7 天内」")
    }

    @Test
    fun commitTypeFilterOnlyNarrowsStats() {
        val stats = listOf(CommitTypeCount("feat", 3), CommitTypeCount("docs", 1))
        assertEquals(stats, DashFilter().keptStats(stats))
        assertEquals(listOf(stats[1]), DashFilter(commits = DashCommitFilter.Only("docs")).keptStats(stats))
        assertTrue(DashFilter(commits = DashCommitFilter.Only("fix")).keptStats(stats).isEmpty(), "筛到一个不剩时由视图说出来，不画空条")
    }

    // ── KPI 归并 ──

    @Test
    fun projectTotalUsesListedNotCollectionSuccessCount() {
        // 注册 6 个、3 个采集失败：标题必须是 6；写 total(3) 会与同屏侧栏「仓库（6/6）」给出两个答案
        val d = DashboardData(projects = DashProjects(total = 3, listed = 6, failed = 3, active7d = 1, active30d = 2))
        val k = dashKpis(d, emptyList()).first { it.kind == DashKpiKind.PROJECTS }
        assertEquals(6, k.value)
        assertTrue("可读取 3/6" in k.caption && "近 7 天活跃 1" in k.caption && "采集失败 3 个" in k.caption)
    }

    @Test
    fun milestoneRateExcludesUnknownFromDenominator() {
        val d = DashboardData(milestones = DashMilestones(counts = MilestoneCounts(open = 2, done = 1, unknown = 1)))
        val k = dashKpis(d, emptyList()).first { it.kind == DashKpiKind.MILESTONES }
        assertEquals(33, k.value, "1/(1+2)，unknown 不进分母")
        assertEquals(1f / 3f, k.progress)
        assertTrue("1 个读不出来" in k.caption, "unknown 单独披露")
    }

    @Test
    fun attentionCountsProjectsNeedingAction() {
        val d = DashboardData(
            projects = DashProjects(dirty = 2),
            work = DashWork(untrackedFiles = 4),
        )
        val busy = Project(name = "busy", userDirtyCount = 1, repoBranchCount = 4)
        val clean = Project(name = "clean", repoBranchCount = -1)
        val kpis = dashKpis(d, listOf(busy, clean))
        val attention = kpis.first { it.kind == DashKpiKind.ATTENTION }
        assertEquals(1, attention.value, "数的是项目，且与看板「待处理」列同一规则")
        assertTrue(attention.needsAttention)
        assertTrue("未跟踪文件 4 个" in attention.caption)
        // 分支：真实值取 repoBranchCount；读不出来的项目要说出来
        val reach = kpis.first { it.kind == DashKpiKind.REACH }
        assertEquals(4, reach.value)
        assertTrue("1 个项目的分支数读不出来" in reach.caption)
    }

    @Test
    fun summaryLineMentionsAttentionOnlyWhenThereIs() {
        val calm = DashboardData(projects = DashProjects(listed = 5))
        assertEquals("共 5 个项目", dashSummaryLine(dashKpis(calm, emptyList())))
        val busy = DashboardData(projects = DashProjects(listed = 5))
        assertEquals("5 个项目 · 1 个项目待处理", dashSummaryLine(dashKpis(busy, listOf(Project(name = "b", userDirtyCount = 1)))))
    }

    // ── 提交构成：不取模 ──

    @Test
    fun cardSliceNeverWrapsThePalette() {
        val twelve = (1..12).map { CommitTypeCount("t$it", 1) }
        val ok = commitTypeCardSlice(twelve)
        assertFalse(ok.cut)
        assertNull(ok.note)
        val thirteen = commitTypeCardSlice(twelve + CommitTypeCount("t13", 1))
        assertTrue(thirteen.cut)
        assertEquals(12, thirteen.entries.size, "第 13 类不许拿第 1 类的颜色")
        assertTrue("还有 1 种没显示" in thirteen.note!!)
    }

    @Test
    fun compositionLineDisclosesSampleAndCut() {
        val seven = (1..7).map { CommitTypeCount("t$it", 6) }
        val c = commitTypeComposition(seven, sampleTruncated = true, totalCommits = 100)
        assertEquals(5, c.shown)
        assertTrue(c.topCut)
        assertTrue(c.line!!.startsWith("t1 ×6 · t2 ×6"))
        assertTrue("近 42/100 条样本" in c.line && "本行只列前 5 种，共 7 种" in c.line)
        assertNull(commitTypeComposition(emptyList(), true).line)
    }

    // ── 语言分布披露 ──

    @Test
    fun languageCoverageNamesEveryReason() {
        val c = languageCoverage(10, truncated = false, failed = 2, reasons = listOf("x"), topCut = false, shownCount = 8)
        assertTrue("只显示前 8 种语言（共 10 种）" in c.note!!)
        assertTrue("2 个项目语言采集失败" in c.note && "原因示例：x" in c.note)
        assertEquals("暂无数据", c.emptyTitle)
        assertEquals("未采集到语言数据", languageCoverage(0, false, 1, null).emptyTitle)
        assertNull(languageCoverage(2, false, 0, null, shownCount = 2).note)
    }

    // ── 里程碑卡与行 ──

    @Test
    fun milestoneCardSliceAndTitle() {
        assertEquals(5, milestoneCardSlice(7).shown)
        assertTrue(milestoneCardSlice(7).cut)
        assertEquals("只显示前 5 条（共 7 条），完整清单见「里程碑」页", milestoneCardSlice(7).note)
        assertFalse(milestoneCardSlice(3).cut)
        assertEquals(
            "里程碑（进行中 1 · 已达成 0）",
            milestoneCardTitle(MilestoneCounts(open = 1, storeHealth = "ok")),
        )
    }

    @Test
    fun milestoneDerivedTextsFollowMac() {
        val open = Milestone(name = "m", targetDate = "2026-12-01", daysToTarget = 7, status = "open")
        assertEquals("还剩 7 天", milestoneDueText(open))
        assertEquals("进行中", milestoneStatusLabel(open))
        val late = open.copy(daysToTarget = -3, overdue = true)
        assertEquals("逾期 3 天", milestoneDueText(late))
        assertEquals("已逾期", milestoneStatusLabel(late), "状态词随 overdue 变红字")
        assertEquals("", milestoneDueText(open.copy(targetDate = "")), "没有目标日期就没有到期文案")
        assertEquals("", milestoneDueText(open.copy(daysToTarget = -1)), "天数读不出来也不编")
        val unknown = open.copy(gitReadable = false)
        assertTrue(unknown.isUnknown)
        assertEquals("无法核验", milestoneStatusLabel(unknown))
        assertEquals("创建以来 3 提交", milestoneCommitsText(open.copy(commitsSince = 3, commitsSinceReadable = true)))
        assertEquals("提交数读不出来", milestoneCommitsText(open.copy(commitsSinceReadable = false)))
        assertEquals("仓库读不出来", milestoneUnverifiedNote(open.copy(commitsSinceReadable = false, unverifiedReason = "仓库读不出来")))
    }

    // ── 分支 ──

    @Test
    fun branchStaleTextHandlesUnreadable() {
        assertEquals("多久没更新：读不出来", branchStaleText(null))
        assertEquals("多久没更新：读不出来", branchStaleText(-1))
        assertEquals("今天更新过", branchStaleText(0))
        assertEquals("1 天没更新", branchStaleText(1))
        assertEquals("5 天没更新", branchStaleText(5))
    }

    @Test
    fun branchScopeLineDistinguishesTrackedFromReal() {
        assertEquals("3/4 个分支已跟踪", branchScopeLine(3, 4))
        assertEquals("4 个分支", branchScopeLine(4, 4))
        assertEquals("3 个已跟踪分支（仓库真实分支数读不出来）", branchScopeLine(3, -1))
        assertEquals("3 个已跟踪分支（仓库真实分支数读不出来）", branchScopeLine(3, null))
    }

    @Suppress("unused")
    private fun branch() = Branch(name = "main")
}
