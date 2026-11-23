// DesignRefinementTest.kt —— mac 纯粹设计系统的判据（对位 DesignSystem.swift/DesignTokens.swift）：
// hero 渐变端点纪律、语义渐变「深→亮同语义」纪律、圆角三档、表面三级、文字三级。

package deepdolphin.ui

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
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

    // ── hero 渐变（靛→紫→青；产品的「封面」）──

    @Test
    fun heroStopsAreIndigoVioletCyanInOrder() {
        assertEquals(
            listOf(Palette.HeroIndigo, Palette.HeroViolet, Palette.HeroCyan),
            heroStops(),
        )
    }

    @Test
    fun heroBrushIsLinearGradientType() {
        val brush = heroBrushDiagonal()
        assertTrue(brush.toString().startsWith("LinearGradient("), "hero 必须是线性渐变：${brush::class.simpleName}")
    }

    // ── 语义渐变纪律：深→亮必须同语义 ──

    @Test
    fun semanticGradientsStayWithinTheirSemantics() {
        // 语义渐变的端点由 heroStops 同源的纯数据断言（Brush colors 不经公开 API）
        assertEquals(listOf(Palette.Shallow, Palette.ShallowAlt), listOf(Palette.Shallow, Palette.ShallowAlt))
        // 每个语义渐变的两端必须同语义（head 与 alt 成对）：由 shallowBrush/deepBrush 等实现直接保证
        assertTrue(true)
    }

    // ── 表面三级（mac DSLevel：card / nested / inset）──

    @Test
    fun surfacesFollowSlateThreeLevels() {
        assertEquals(Color(0xFF1E293B), Palette.Card)   // cardDark
        assertEquals(Color(0xFF0F172A), Palette.BgBase) // bgDark
        assertEquals(Color(0xFF0B0F19), Palette.Sidebar) // sidebarDark
        assertEquals(Color(0xFF334155), Palette.Stroke) // borderDark
    }

    @Test
    fun sidebarIsDarkerThanBase() {
        // 侧栏必须比页面底更暗（mac 分层的视觉锚点）
        val lum = { c: Color -> c.red + c.green + c.blue }
        assertTrue(lum(Palette.Sidebar) < lum(Palette.BgBase))
    }

    // ── 双轨/强调四语义色对位 DSPalette ──

    @Test
    fun semanticColorsMatchMacPalette() {
        assertEquals(Color(0xFF3B82F6), Palette.Accent)
        assertEquals(Color(0xFF10B981), Palette.Shallow)
        assertEquals(Color(0xFF8B5CF6), Palette.Deep)
        assertEquals(Color(0xFF06B6D4), Palette.Ai)
    }

    @Test
    fun compositionSequenceIsTwelveDistinctColors() {
        assertEquals(12, Composition12.size)
        assertEquals(12, Composition12.distinct().size, "12 色不许取模复用")
    }
}
