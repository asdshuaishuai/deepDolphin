// DashboardGridTest.kt —— 逐项目进度卡判定层的判据（里程碑完成率口径）。

package deepdolphin.ui

import deepdolphin.engine.Milestone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class DashboardGridTest {

    private fun ms(status: String?) = Milestone(name = "m", projectId = "p", status = status)

    @Test
    fun milestoneRatioIsDoneOverDonePlusOpen() {
        val r = milestoneRatioOf(listOf(ms("done"), ms("done"), ms("open")))
        assertEquals(2, r.done)
        assertEquals(1, r.open)
        assertEquals(2f / 3f, r.ratio!!, 0.001f)
    }

    @Test
    fun unknownStatusDoesNotCountIntoRatio() {
        // unknown 不计入分母（对位 mac milestoneRatio：unknown 单独披露）
        val r = milestoneRatioOf(listOf(ms("done"), ms("unknown"), ms(null)))
        assertEquals(1, r.done)
        assertEquals(0, r.open)
        assertEquals(2, r.unknown)
        assertNull(r.ratio, "无可判定的里程碑（全 unknown/缺键）→ 不画进度条")
    }

    @Test
    fun emptyMilestonesHasNoProgressBar() {
        val r = milestoneRatioOf(emptyList())
        assertNull(r.ratio)
    }
}
