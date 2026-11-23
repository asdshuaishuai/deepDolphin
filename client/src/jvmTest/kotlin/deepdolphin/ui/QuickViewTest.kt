// QuickViewTest.kt —— 托盘速览窗行文案判据（副行四态 / 超行数引导 / 状态点语义色）。
// Dialog 本体是 AWT/Compose 真交互，真机冒烟由终验批承担，这里只测纯函数。判据只增不减。

package deepdolphin.ui

import deepdolphin.engine.Branch
import deepdolphin.engine.Project
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class QuickViewTest {

    @BeforeTest
    fun pinZh() {
        // 断言锚定 zh 文案：钉住语言，防宿主 locale / settings.conf 漂移翻红
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    private fun project(
        error: String? = null,
        kind: String = "git",
        branches: List<Branch> = emptyList(),
        lastCommitAgo: String? = null,
    ) = Project(error = error, kind = kind, branches = branches, lastCommitAgo = lastCommitAgo)

    // ── 副行四态（mac MenuProjectRow.subtitle 对位；CMP 无 pulseLine 字段，如实按有的字段来）──

    @Test
    fun errorComesFirstAndVerbatim() {
        assertEquals("路径不存在或卷未挂载：/tmp/gone", project(error = "路径不存在或卷未挂载：/tmp/gone").let(::quickRowSubtitle))
    }

    @Test
    fun primaryBranchGivesHeadAgoAndStatusWord() {
        val p = project(
            branches = listOf(
                Branch(name = "feature/x", status = "active", statusLabel = "活跃", headAgo = "4 小时前", isCurrent = true),
                Branch(name = "main", status = "idle", statusLabel = "闲置"),
            ),
        )
        // 当前分支优先（primaryBranch：isCurrent 回退第一个）；状态词用引擎的 statusLabel
        assertEquals("4 小时前 · 活跃", quickRowSubtitle(p))
    }

    @Test
    fun noBranchFallsBackToLastCommitAgo() {
        assertEquals("23 天前", quickRowSubtitle(project(lastCommitAgo = "23 天前")))
    }

    @Test
    fun nonGitProjectHasItsOwnWording() {
        assertEquals("非 git 项目", quickRowSubtitle(project(kind = "dir")))
    }

    @Test
    fun gitWithoutTimesSaysUnknownNotZero() {
        // 「读不出来」不许折成「刚刚」或别的确定态
        assertEquals("最后提交时间读不出来", quickRowSubtitle(project()))
    }

    // ── 超行数引导（mac bar.moreProjects 对位）──

    @Test
    fun upToTwelveRowsHaveNoMoreLine() {
        assertNull(quickViewMoreLine(12))
    }

    @Test
    fun beyondTwelveShowsRemainder() {
        assertEquals("还有 3 个项目，打开面板查看…", quickViewMoreLine(15))
        assertEquals("还有 1 个项目，打开面板查看…", quickViewMoreLine(13))
    }

    // ── 状态点语义色（mac StatusDot 的 liveness 对位；断言打在设计令牌等值上）──

    @Test
    fun unreadableIsRedAndRecentIsGreen() {
        assertEquals(Palette.Red, quickRowTint(Liveness.UNREADABLE))
        assertEquals(Palette.Green, quickRowTint(Liveness.RECENT))
        assertEquals(Palette.Amber, quickRowTint(Liveness.NEEDS_ACTION))
        assertEquals(Palette.Yellow, quickRowTint(Liveness.QUIET))
        assertEquals(Palette.TextTertiary, quickRowTint(Liveness.NOT_GIT))
    }
}
