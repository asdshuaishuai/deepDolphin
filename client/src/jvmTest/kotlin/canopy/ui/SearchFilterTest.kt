// SearchFilterTest.kt —— 侧栏搜索过滤判据（mac A11yLabel.swift:79-131 SearchFilter 对位）。
//
// 判据只增不减。核心三态：空查询不过滤、匹配项目名+分支名、
// 「没匹配上」与「本来就没有」必须给出不同的文案。

package canopy.ui

import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SearchFilterTest {

    @BeforeTest
    fun pinZh() {
        // 断言锚定 zh 文案：钉住语言，防宿主 locale / settings.conf 漂移翻红
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    private data class Repo(val name: String, val branches: List<String>)

    private val repos = listOf(
        Repo("vtest", listOf("main", "feat/tray")),
        Repo("Canopy", listOf("next/cmp", "main")),
        Repo("legacy-tool", emptyList()),
    )

    private fun key(r: Repo) = r.name + " " + r.branches.joinToString(" ") { it }

    // ── filter ──

    @Test
    fun emptyQueryReturnsAllUntouched() {
        // 空查询 ⇒ 原样返回，不制造「搜索后 0 条」的假象（mac 同款判据）
        assertEquals(repos, SearchFilter.filter(repos, "", ::key))
        assertEquals(repos, SearchFilter.filter(repos, "   ", ::key), "纯空白查询等同未搜")
    }

    @Test
    fun matchesProjectNameCaseInsensitively() {
        assertEquals(listOf(repos[1]), SearchFilter.filter(repos, "canopy", ::key))   // 小写查询命中大写开头的仓库名
        assertEquals(listOf(repos[0]), SearchFilter.filter(repos, "VTEST", ::key))
    }

    @Test
    fun matchesBranchName() {
        // 用户记得「那条 feat 分支」时也能搜到（mac PanelView.swift:31-35 匹配口径）
        assertEquals(listOf(repos[0]), SearchFilter.filter(repos, "feat", ::key))
        assertEquals(listOf(repos[1]), SearchFilter.filter(repos, "next/cmp", ::key))
    }

    @Test
    fun noMatchFiltersEverythingOut() {
        assertTrue(SearchFilter.filter(repos, "不存在的词", ::key).isEmpty())
    }

    // ── emptyReason：两种空必须分开 ──

    @Test
    fun nonEmptyResultHasNoEmptyReason() {
        assertNull(SearchFilter.emptyReason(allCount = 3, shownCount = 1, query = "x"))
    }

    @Test
    fun noDataWhenNothingEverExisted() {
        val r = SearchFilter.emptyReason(allCount = 0, shownCount = 0, query = "任意")
        assertIs<SearchEmpty.NoData>(r)
    }

    @Test
    fun noMatchWhenDataExistsButQueryMisses() {
        val r = SearchFilter.emptyReason(allCount = 3, shownCount = 0, query = " feat ")
        val nm = assertIs<SearchEmpty.NoMatch>(r)
        assertEquals("feat", nm.query, "查询原样回显前先修边——回显的是用户搜的词")
    }

    @Test
    fun blankQueryWithEmptyResultIsNoDataNotNoMatch() {
        // 查询是空的但结果空 ⇒ 只能是「本来就没有」
        val r = SearchFilter.emptyReason(allCount = 3, shownCount = 0, query = "")
        assertIs<SearchEmpty.NoData>(r)
    }

    // ── emptyText：两态不同的话，且把查询回显 ──

    @Test
    fun emptyTextDistinguishesTwoEmpties() {
        assertEquals("暂无项目", SearchFilter.emptyText(SearchEmpty.NoData))
        assertEquals(
            "没有项目匹配「feat」",
            SearchFilter.emptyText(SearchEmpty.NoMatch("feat")),
            "回显查询，用户才知道自己搜了什么",
        )
        assertTrue(
            SearchFilter.emptyText(SearchEmpty.NoData) != SearchFilter.emptyText(SearchEmpty.NoMatch("x")),
        )
    }

    // ── resultSummary：搜到 0 条与没搜索过，文案不同 ──

    @Test
    fun resultSummaryOnlyWhenActuallyFiltered() {
        assertNull(SearchFilter.resultSummary(0, 0), "本来就没有 ⇒ 不需要「匹配」说明")
        assertNull(SearchFilter.resultSummary(3, 3), "没过滤 ⇒ 不需要说明")
        assertEquals("匹配 1 / 3 个项目", SearchFilter.resultSummary(3, 1))
        assertEquals("匹配 0 / 3 个项目", SearchFilter.resultSummary(3, 0))
    }

    // ── 组合走查：侧栏真实用法（emptyReason 的输入来自 filter 的输出）──

    @Test
    fun sidebarWiringMissLeadsToNoMatch() {
        val shown = SearchFilter.filter(repos, "cambium", ::key)
        assertEquals(0, shown.size)
        val reason = SearchFilter.emptyReason(repos.size, shown.size, "cambium")
        assertIs<SearchEmpty.NoMatch>(reason)
    }
}
