// CommitCountScopeTest.kt —— journal 条目「+N」口径判据（mac CommitCountScope.swift 的断言对位）。
//
// 引擎侧缺陷 #188：commitCount 在浅/深两条路径上装的不是同一种东西——
// 浅更新 = 本轮新增，深更新 = 仓库提交总数（随仓库一直涨）。一个「本轮新增 6」和一个
// 「仓库一共 6 个」若渲染成同一个绿色 +6，读者会得出「深更新也新增了 6 个提交」。

package deepdolphin.ui

import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CommitCountScopeTest {

    @BeforeTest
    fun pinZh() {
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    @Test
    fun unreadableNeverRendersAsZero() {
        assertEquals(CommitCountScope.UNREADABLE, commitCountScopeOf("new", -1))
        assertEquals(CommitCountScope.UNREADABLE, commitCountScopeOf("new", null), "缺键与 -1 同义：整个数字没意义")
        val b = commitCountBadge(-1, "new", false)
        assertEquals("提交数读不出来", b.text)
        assertNotNull(b.note, "读不出来必须带一句「不是这轮没有提交」")
    }

    @Test
    fun zeroNewCommitsHasNoBadge() {
        assertNull(commitCountBadge(0, "new", false).text, "0 个新增不是一条值得占位的信息")
        assertNull(commitCountBadge(0, "repoTotal", null).note)
    }

    @Test
    fun newAndRepoTotalAreDifferentBadges() {
        val n = commitCountBadge(6, "new", false)
        val t = commitCountBadge(6, "repoTotal", false)
        assertEquals("+6 新增", n.text)
        assertEquals("+6 累计", t.text)
        assertTrue(n.scope.isIncremental, "本轮新增才能用绿色")
        assertFalse(t.scope.isIncremental, "累计量用绿色 = 把累计说成增量")
    }

    @Test
    fun unknownScopeAndTruncatedAreDisclosed() {
        val u = commitCountBadge(3, null, false)
        assertEquals("+3 口径未知", u.text)
        assertNotNull(u.note, "口径没标出来必须说出来，不能默认成本轮新增")
        val s = commitCountBadge(3, "new", true)
        assertTrue(s.truncated)
        assertEquals("这是采样值，不是全量", s.note)
    }

    @Test
    fun modeLabelsFollowMac() {
        assertEquals("快照", journalModeLabel("track"))
        assertEquals("浅更新", journalModeLabel("shallow"))
        assertEquals("深度更新", journalModeLabel("deep"))
        assertEquals("手动", journalModeLabel("manual"))
        assertEquals("custom", journalModeLabel("custom"), "未知模式原样显示")
    }

    @Test
    fun entryCountLineDisclosesTruncation() {
        assertEquals("12 条", entryCountLine(12, 12, false))
        assertEquals("8/12 条（已截断）", entryCountLine(12, 8, null), "条数多于保留数即截断")
        assertEquals("8/8 条（已截断）", entryCountLine(8, 8, true), "引擎标了截断旗即便相等也要说")
    }
}
