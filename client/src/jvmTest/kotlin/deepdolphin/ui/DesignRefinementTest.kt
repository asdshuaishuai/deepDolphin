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
        assertEquals(Color(0x87FFFFFF), Palette.TextTertiary)  // 53%（由下面一条对比度判据定）
    }

    @Test
    fun everyTextLevelStaysReadableOnEverySurface() {
        // WCAG 正文底线 4.5:1：三级文字都是半透明白，合成到每一种底色上都要过线。
        // 三级文字原来 45%，在卡片底（#292929）上只有 4.2:1——时间戳、文件名这类小字发灰。
        fun blend(fg: Color, bg: Color): Color = Color(
            red = fg.red * fg.alpha + bg.red * (1 - fg.alpha),
            green = fg.green * fg.alpha + bg.green * (1 - fg.alpha),
            blue = fg.blue * fg.alpha + bg.blue * (1 - fg.alpha),
            alpha = 1f,
        )

        fun luminance(c: Color): Double {
            fun channel(v: Float) = v.toDouble().let { if (it <= 0.03928) it / 12.92 else Math.pow((it + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
        }

        fun contrast(a: Color, b: Color): Double {
            val (hi, lo) = listOf(luminance(a), luminance(b)).sortedDescending()
            return (hi + 0.05) / (lo + 0.05)
        }

        val surfaces = listOf("页面底" to Palette.BgBase, "卡片" to Palette.Card, "卡片 hover" to Palette.CardHover, "侧栏" to Palette.Sidebar)
        val levels = listOf("一级" to Palette.TextPrimary, "二级" to Palette.TextSecondary, "三级" to Palette.TextTertiary)
        levels.forEach { (levelName, text) ->
            surfaces.forEach { (surfaceName, bg) ->
                val ratio = contrast(blend(text, bg), bg)
                assertTrue(ratio >= 4.5, "$levelName 文字在$surfaceName 上只有 ${"%.2f".format(ratio)}:1，不到正文 4.5:1 的底线")
            }
        }
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
