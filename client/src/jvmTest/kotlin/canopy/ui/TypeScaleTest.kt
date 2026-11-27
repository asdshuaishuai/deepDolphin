// TypeScaleTest.kt —— 字号档位的判据（ui-ux-pro-max 规则集：正文不小于 12px；数据数字用等宽数字）。

package canopy.ui

import androidx.compose.ui.unit.sp
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TypeScaleTest {

    @Test
    fun smallestTypeSizeIsAtLeastTwelve() {
        // 规则集把「正文 < 12px」列为反模式：caption 级的 micro 原先是 11sp
        assertTrue(Type.micro.fontSize >= 12.sp, "micro 不得低于 12sp（现为 ${Type.micro.fontSize}）")
        assertTrue(Type.label.fontSize >= 12.sp)
        assertTrue(Type.body.fontSize >= 12.sp)
    }

    @Test
    fun displayNumeralsAreTabular() {
        // KPI 数字与总分用 display 档：等宽数字让同一列里的数在刷新时不跳
        assertEquals("tnum", Type.display.fontFeatureSettings)
    }
}
