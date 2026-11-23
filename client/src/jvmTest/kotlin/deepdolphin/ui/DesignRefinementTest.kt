// DesignRefinementTest.kt —— UI 精修收口批的判据：aurora 渐变构造纯函数 + 空态判定。
//
// 【对位】archive/bui design.rs：`.aurora-a/b/c` = 三个 720px 圆形斑块、135deg 单层渐变
//   （0% 实色 → 72% 全透明）、整层透明度 .10；锚点定位 right/bottom/百分比在
//   `auroraPatches` 里显式换算成宿主内绝对偏移。
// 【空态】对位 mac 基准「三种没有分开说」：加载中（信封未到）/ 读不出来 ≠ 空态，
//   绝不拿 CTA 冒充；只有引擎成功读过且在册列表为空才是真空。

package deepdolphin.ui

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.LinearGradient
import deepdolphin.engine.Project
import deepdolphin.engine.StatusEnvelope
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DesignRefinementTest {

    // ── aurora 渐变构造（纯函数）──

    @Test
    fun auroraAxisAimsDownRightLikeCss135Deg() {
        // CSS 135deg = 渐变轴指向右下：start 左上角 → end 右下角。
        val (start, end) = auroraAxis(720f)
        assertEquals(Offset.Zero, start, "135deg 渐变轴起点必须是左上角")
        assertEquals(Offset(720f, 720f), end, "135deg 渐变轴终点必须是右下角（720×720 对角）")
    }

    @Test
    fun auroraStopsFadeToTransparentAtCss72PercentStop() {
        val c = Color(0xFF4C8DFF)
        val stops = auroraStops(c)
        assertEquals(2, stops.size, "单层渐变：实色 + 淡出两档")
        val (s0, c0) = stops[0]
        val (s1, c1) = stops[1]
        assertEquals(0f, s0, "第一档在 0%")
        assertEquals(c, c0, "0% 必须是入参实色（不掺透明度）")
        assertEquals(AURORA_FADE_STOP, s1, "淡出点冻结在 CSS 的 72%")
        assertEquals(0f, c1.alpha, "淡出档必须全透明")
        assertEquals(c, c1.copy(alpha = 1f), "淡出档保持同一色相（只动 alpha）")
    }

    @Test
    fun auroraBrushAppliesStopsAndAxisAsLinearGradient() {
        val b = auroraBrush(Palette.Accent, sizePx = 720f)
        assertTrue(b is LinearGradient, "aurora 必须是线性渐变（BUI 只用已知安全的 linear-gradient）")
    }

    @Test
    fun auroraLayerOpacityIsTenPercent() {
        assertEquals(0.10f, AURORA_LAYER_ALPHA, "对位 .aurora { opacity: .10 }：低透明度不抢内容")
    }

    @Test
    fun auroraPatchesAnchorLikeCssSpec() {
        val w = 1280f
        val h = 800f
        val patches = auroraPatches(w, h)
        assertEquals(3, patches.size, "aurora-a/b/c 三斑块")
        // a：left -220 / top -280（左上负偏移，越界由宿主裁剪）。
        assertEquals(Palette.Accent, patches[0].color, "aurora-a 用 #4C8DFF（Accent 同源）")
        assertEquals(-220f, patches[0].left)
        assertEquals(-280f, patches[0].top)
        // b：right -240 → 左缘 = w - 720 + 240；top 90。
        assertEquals(Palette.Purple, patches[1].color, "aurora-b 用 #B08CFF（Purple 同源）")
        assertEquals(w - 720f + 240f, patches[1].left, "right:-240px 必须换算成绝对左缘")
        assertEquals(90f, patches[1].top)
        // c：left 28% / bottom -360 → 上缘 = h - 720 + 360。
        assertEquals(Palette.Green, patches[2].color, "aurora-c 用 #3FCF8E（Green 同源）")
        assertEquals(0.28f * w, patches[2].left, 0.001f)
        assertEquals(h - 720f + 360f, patches[2].top, "bottom:-360px 必须换算成绝对上缘")
    }

    @Test
    fun auroraPatchSizeIsCss720Px() {
        assertEquals(720f, AURORA_SIZE_PX, "斑块直径冻结在 CSS 的 720px")
    }

    // ── 空态判定（纯函数）──

    @Test
    fun registryEmptyOnlyWhenReadSucceededAndListEmpty() {
        assertTrue(registryEmpty(StatusEnvelope()), "引擎读成功 + 在册列表为空 = 真空，给 CTA")
    }

    @Test
    fun registryEmptyNeverClaimsLoadingAsEmpty() {
        assertFalse(registryEmpty(null), "信封未到（加载中）≠ 空态：不冒充「还没有项目」")
    }

    @Test
    fun registryEmptyNeverClaimsUnreadableProjectsAsEmpty() {
        // 全部项目采集失败：项目在册，只是读不出来 —— 绝不当空态（对位 mac 基准「三种没有」）。
        val failedOnly = StatusEnvelope(
            projects = listOf(Project(name = "gone", error = "exit 128")),
        )
        assertFalse(registryEmpty(failedOnly), "读不出来的项目 ≠ 没有项目")
        // 有可读项目更不用说。
        assertFalse(registryEmpty(StatusEnvelope(projects = listOf(Project(name = "atlas")))))
    }
}
