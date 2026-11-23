// DesignRefinementTest.kt —— Fluent 设计系统判据（用户定稿：完全的 Fluent 美学；WinUI 3 暗色域）：
// 安静 hero（无多色渐变）、白 alpha 分层表面、白三级文字、圆角三档、accent 亮蓝配近黑文字。

package deepdolphin.ui

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DesignRefinementTest {

    @BeforeTest
    fun pinZh() {
        // 断言锚定 zh 文案：钉住语言，防宿主 locale / settings.conf 漂移翻红
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    // ── hero：安静分层（两端同族近灰，禁多色）──

    @Test
    fun heroStopsStayQuietLayered() {
        val stops = heroStops()
        assertEquals(listOf(Palette.HeroTop, Palette.HeroBottom), stops)
        val dr = kotlin.math.abs(stops[0].red - stops[1].red)
        val dg = kotlin.math.abs(stops[0].green - stops[1].green)
        val db = kotlin.math.abs(stops[0].blue - stops[1].blue)
        assertTrue(dr + dg + db < 0.3f, "hero 两端必须是同族近灰（Fluent 安静头），不许多色渐变")
    }

    @Test
    fun heroBrushIsGradientType() {
        val brush = heroBrushDiagonal()
        assertTrue(brush.toString().contains("Gradient("), "hero 必须是渐变：${brush::class.simpleName}")
    }

    // ── 表面：Mica 底 + 白 alpha 分层 ──

    @Test
    fun surfacesFollowFluentLayering() {
        assertEquals(Color(0xFF1F1F1F), Palette.BgBase)   // SolidBackgroundFillColorBase 暗色
        assertEquals(Color(0xFF292929), Palette.Card)     // Layer ~4% 白
        assertEquals(Color(0xFF191919), Palette.Sidebar)  // NavigationView pane
        assertEquals(Color(0x14FFFFFF), Palette.Stroke)   // 白 8% hairline
    }

    @Test
    fun sidebarIsDarkerThanBase() {
        // 侧栏必须比页面底更暗（分层的视觉锚点）
        val lum = { c: Color -> c.red + c.green + c.blue }
        assertTrue(lum(Palette.Sidebar) < lum(Palette.BgBase))
    }

    @Test
    fun textFollowsWhiteThreeLevels() {
        assertEquals(Color(0xFFFFFFFF), Palette.TextPrimary)   // 100%
        assertEquals(Color(0xA8FFFFFF), Palette.TextSecondary) // 66%
        assertEquals(Color(0x73FFFFFF), Palette.TextTertiary)  // 45%
    }

    // ── accent：Fluent 暗色亮蓝 + 近黑文字（对比度纪律）──

    @Test
    fun accentIsFluentDarkBlueWithDarkOnColor() {
        assertEquals(Color(0xFF60CDFF), Palette.Accent)
        assertEquals(Color(0xFF1B1B1B), Palette.OnAccent)
        // 亮 accent 上必须配深文字（WCAG 方向性校验）
        val lum = { c: Color -> 0.2126f * c.red + 0.7152f * c.green + 0.0722f * c.blue }
        assertTrue(lum(Palette.Accent) - lum(Palette.OnAccent) > 0.4f, "accent 与其上文字的明度差必须够大")
    }

    // ── 圆角与动效档 ──

    @Test
    fun radiusFollowsFluentTiers() {
        assertEquals(4.dp, Radius.chip)
        assertEquals(4.dp, Radius.control)
        assertEquals(8.dp, Radius.card)
    }

    @Test
    fun motionTiersAre150And300() {
        assertEquals(150, Motion.normal)
        assertEquals(300, Motion.slow)
    }

    @Test
    fun compositionSequenceIsTwelveDistinctColors() {
        assertEquals(12, Composition12.size)
        assertEquals(12, Composition12.distinct().size, "12 色不许取模复用")
    }
}
