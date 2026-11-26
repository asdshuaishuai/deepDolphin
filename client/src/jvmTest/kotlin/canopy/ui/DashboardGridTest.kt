// DashboardGridTest.kt —— 逐项目进度卡判定层的判据（里程碑完成率口径）。

package canopy.ui

import canopy.engine.Milestone
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
        // unknown 不计入分母（对位 mac milestoneRatio：unknown 单独披露）；
        // [done, unknown, null] → done=1, open=0, unknown=1, ratio=1.0
        val r = milestoneRatioOf(listOf(ms("done"), ms("unknown"), ms(null)))
        assertEquals(1, r.done)
        assertEquals(0, r.open)
        assertEquals(1, r.unknown)
        assertEquals(1.0f, r.ratio!!, 0.001f)
    }

    @Test
    fun emptyMilestonesHasNoProgressBar() {
        val r = milestoneRatioOf(emptyList())
        assertNull(r.ratio)
    }
}
