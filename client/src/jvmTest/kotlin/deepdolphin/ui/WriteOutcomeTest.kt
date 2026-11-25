// WriteOutcomeTest.kt —— 写操作结果行的判据（回执说什么，界面就报什么）。

package deepdolphin.ui

import deepdolphin.engine.MilestoneActionReceipt
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WriteOutcomeTest {

    @BeforeTest
    fun pinZh() {
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    @Test
    fun appliedActionReportsEffectiveStatus() {
        val done = MilestoneActionReceipt(project = "p", milestone = "v1", requested = "done", status = "done", applied = true)
        assertEquals("里程碑「v1」已标记达成", msActionOutcome(done))
        assertEquals("里程碑「v1」已重新打开", msActionOutcome(done.copy(requested = "reopen", status = "open")))
    }

    @Test
    fun nonAppliedIsNotReportedAsSuccess() {
        // 请求 reopen，但被「同名 tag 已存在即自动 done」压回：必须说出没生效
        val r = MilestoneActionReceipt(project = "p", milestone = "v1", requested = "reopen", status = "done", applied = false)
        val out = msActionOutcome(r)
        assertTrue(out.startsWith("里程碑「v1」已标记达成"))
        assertTrue("请求「reopen」未生效" in out && "实际状态是「done」" in out, out)
        assertFalse("doneed" in out, "不再拼出「doneed」这种词")
    }

    @Test
    fun unknownStatusIsShownVerbatim() {
        val r = MilestoneActionReceipt(project = "p", milestone = "m", requested = "done", status = "paused", applied = true)
        assertEquals("里程碑「m」当前状态：paused", msActionOutcome(r))
    }

    @Test
    fun commitSheetDisclosesUnlistedChanges() {
        assertEquals(0L, unlistedDirtyCount(5, 5))
        assertEquals(0L, unlistedDirtyCount(3, 5), "列出的比总数多（口径分叉）时不报负数")
        assertEquals(12L, unlistedDirtyCount(42, 30), "引擎清单上限 30：另外 12 处没列出")
    }
}
