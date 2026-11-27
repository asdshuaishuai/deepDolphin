// SkinTest.kt —— 皮肤数据的守卫：14 套（namethatui 全风格 − flat）、颜色必须 8 位 ARGB（6 位 = alpha 0 = 文字隐身）、
// 恢复默认、app.skin 键合并只动自己的键。
package canopy.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.luminance
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SkinTest {
    @Test
    fun allNamethatuiStylesExceptFlatArePresent() {
        // namethatui.com/styles 共 15 个风格；flat design 按用户要求不做。
        // 每个风格一行（zh 名），新增/删除皮肤时同步这张表——对照站点清单的守卫。
        val namethatuiExceptFlat = listOf(
            "拟物皮革", "新拟态", "玻璃拟态", "液态玻璃", "网页粗野主义", "新粗野主义",
            "Y2K 千禧", "Frutiger Aero", "极简主义", "黏土拟态", "远古网页", "Aqua 经典", "Windows Aero",
        )
        assertEquals(namethatuiExceptFlat.size + 1, Skins.all.size, "13 个站点风格 + Fluent 默认")
        namethatuiExceptFlat.forEach { zh ->
            assertTrue(Skins.all.any { it.titleZh == zh }, "缺风格：$zh")
        }
        assertEquals(Skins.DEFAULT_ID, Skins.byId.getValue(Skins.DEFAULT_ID).id)
    }

    @Test
    fun everySkinColorIsFullyOpaqueEnoughToRender() {
        // 6 位 hex（0xRRGGBB）在 Color(Int) 里是 alpha=0 ⇒ 文字/描边全透明。
        // Y2K 与 Aero 的 textSecondary 踩过（实拍：整页文字消失）；这条守卫钉死所有皮肤所有颜色。
        Skins.all.forEach { skin ->
            val colors = listOf(
                "bgBase" to skin.bgBase, "sidebar" to skin.sidebar, "card" to skin.card,
                "cardHover" to skin.cardHover, "cardPressed" to skin.cardPressed,
                "stroke" to skin.stroke, "strokeHover" to skin.strokeHover, "barTrack" to skin.barTrack,
                "textPrimary" to skin.textPrimary, "textSecondary" to skin.textSecondary,
                "textTertiary" to skin.textTertiary, "accent" to skin.accent, "onAccent" to skin.onAccent,
                "accentHover" to skin.accentHover, "shallow" to skin.shallow, "deep" to skin.deep,
                "ai" to skin.ai, "green" to skin.green, "yellow" to skin.yellow,
                "amber" to skin.amber, "red" to skin.red, "heroTop" to skin.heroTop, "heroBottom" to skin.heroBottom,
            )
            colors.forEach { (name, c) ->
                assertTrue(c.alpha > 0.04f, "${skin.id}.$name alpha=${c.alpha} —— 6 位 hex（alpha 0）会隐身")
            }
            // 文字三级在各自底上必须可读（实拍纪律：Y2K/Aero 的隐身文字就是漏网之鱼）
            assertTrue(skin.textPrimary.alpha > 0.9f, "${skin.id}.textPrimary 必须 Near 不透明")
        }
    }

    @Test
    fun applyAndSelectRoundTripThroughConfMerge() {
        val skin = Skins.byId.getValue("aqua")
        // 只动 app.skin 键；其余行（别的设置节）原样保留
        val merged = mergeKeyInto("ai.provider=x\napp.skin=glass\nupdate.autoHours=6", "app.skin", skin.id)
        assertTrue(merged.contains("app.skin=${skin.id}"))
        assertTrue(merged.contains("ai.provider=x"))
        assertTrue(merged.contains("update.autoHours=6"))
        // 换键不串：merge 进空文本也只产生自己那一行
        assertEquals("app.skin=${skin.id}", mergeKeyInto("", "app.skin", skin.id).trim())
    }

    // ── 文字 × 表面的对比度守卫（用户 2026-11-26 在 Aqua 上实拍：橙字 1.4、绿字 1.9、按钮白字 2.2）──

    /** 半透明前景落在某个表面上的实际对比度。 */
    private fun onSurface(fg: Color, surface: Color): Float =
        contrastOf(if (fg.alpha >= 0.999f) fg else fg.compositeOver(surface), surface)

    private class Worst(val contrast: Float, val fg: Color, val surface: Color)

    private fun worst(fg: Color, surfaces: List<Color>): Worst =
        surfaces.minBy { onSurface(fg, it) }.let { Worst(onSurface(fg, it), fg, it) }

    private fun check(w: Worst, floor: Float, what: String): String? =
        if (w.contrast >= floor) null else "$what：${"%.1f".format(w.contrast)} on ${w.surface.toCss()}（前景 ${w.fg.toCss()}）"

    private val inks = listOf(
        "accent" to { Palette.AccentText }, "shallow" to { Palette.ShallowText }, "deep" to { Palette.DeepText },
        "ai" to { Palette.AiText }, "yellow" to { Palette.YellowText }, "amber" to { Palette.AmberText },
        "red" to { Palette.RedText },
    )

    /** 每套皮肤：「卡面」= 卡片落在第一个底色上（Skin.kt 的 textSurfaces 里静置面的第 2 个）。 */
    private fun cardOf(skin: Skin): Color = skin.card.compositeOver(backdropBases(skin.backdrop, skin.bgBase).first())

    /**
     * 静置面（底 / 侧栏 / 卡 / 凹槽 / hero / 菜单）上三级文字按 AAA：主 7、次级 6、三级 5；
     * 光泽顶部与悬停 / 按下上主 / 次级按 AA 4.5，三级与语义墨不跌破 3.0；悬停 + 光泽叠加处主 ≥ 4.5；
     * 语义墨在静置面上 ≥ 4.5；每个语义容器本体上配得出 ≥ 4.5 的前景，它的光泽顶部与悬停色上 ≥ 4.3；
     * accent 的本体 / 光泽顶部 / 悬停色上 ≥ 4.3；提交构成 12 色对底、侧栏、卡 ≥ 3:1。
     * 层级不塌：保底只能把字推得更清楚，不许把次级推成主、三级推成次级（卡面上逐级 ≤ 0.9）。
     */
    @Test
    fun textAndInkAreReadableInEverySkin() {
        val failures = ArrayList<String>()
        val table = StringBuilder()
        try {
            Skins.all.forEach { skin ->
                Skins.apply(skin)
                val s = textSurfaces(skin)
                val card = cardOf(skin)
                check(worst(Palette.TextPrimary, s.resting), 6.9f, "${skin.id} 主文字在静置面上不到 7:1")?.let(failures::add)
                check(worst(Palette.TextSecondary, s.resting), 5.9f, "${skin.id} 次级文字在静置面上不到 6:1")?.let(failures::add)
                check(worst(Palette.TextTertiary, s.resting), 4.9f, "${skin.id} 三级文字在静置面上不到 5:1")?.let(failures::add)
                check(worst(Palette.TextPrimary, s.all), 4.4f, "${skin.id} 主文字在抬升面上不到 4.5:1")?.let(failures::add)
                check(worst(Palette.TextSecondary, s.steady), 4.4f, "${skin.id} 次级文字在抬升面上不到 4.5:1")?.let(failures::add)
                check(worst(Palette.TextSecondary, s.all), 2.9f, "${skin.id} 次级文字在悬停 + 光泽处不到 3:1")?.let(failures::add)
                check(worst(Palette.TextTertiary, s.all), 2.9f, "${skin.id} 三级文字在抬升面上不到 3:1")?.let(failures::add)
                // 层级：卡片落在每个底色上，次级 ≤ 主 × 0.9、三级 ≤ 次级 × 0.9
                backdropBases(skin.backdrop, skin.bgBase).forEach { base ->
                    val on = skin.card.compositeOver(base)
                    val p = onSurface(Palette.TextPrimary, on)
                    val sec = onSurface(Palette.TextSecondary, on)
                    val ter = onSurface(Palette.TextTertiary, on)
                    if (sec > p * 0.9f) failures.add("${skin.id} 卡 ${on.toCss()} 上次级文字与主文字分不开：次 ${"%.1f".format(sec)} / 主 ${"%.1f".format(p)}")
                    if (ter > sec * 0.9f) failures.add("${skin.id} 卡 ${on.toCss()} 上三级文字与次级文字分不开：三 ${"%.1f".format(ter)} / 次 ${"%.1f".format(sec)}")
                }
                // 浮层：菜单条目是主文字压 Popover（按 AAA）；提示条是次级文字压 PopoverRaised（按 AA）。
                // 体检的状态遍里悬停弹出提示条时单独量过它（vernacular 5.4、aqua 8.3）
                check(worst(Palette.TextPrimary, listOf(Palette.Popover)), 6.9f, "${skin.id} 菜单底上的文字不到 7:1")?.let(failures::add)
                check(worst(Palette.TextSecondary, listOf(Palette.PopoverRaised)), 4.4f, "${skin.id} 提示条底上的文字不到 4.5:1")?.let(failures::add)
                inks.forEach { (name, get) ->
                    check(worst(get(), s.resting), 4.4f, "${skin.id} 文字级 $name 在静置面上不到 4.5:1")?.let(failures::add)
                    check(worst(get(), s.all), 2.9f, "${skin.id} 文字级 $name 在抬升面上不到 3:1")?.let(failures::add)
                }
                val g = Material.glossStrength
                val accentTops = if (g > 0f) listOf(Palette.Accent, glossy(Palette.Accent, g), Palette.AccentHover) else listOf(Palette.Accent, Palette.AccentHover)
                if (accentTops.any { contrastOf(Palette.OnAccent, it) < 4.2f }) {
                    failures.add("${skin.id} accent 上 / 光泽顶部 / 悬停色的前景不到 4.3:1（${Palette.OnAccent.toCss()} on ${Palette.Accent.toCss()} / ${Palette.AccentHover.toCss()}）")
                }
                // 提交构成 12 色：分段条与图例点对底、侧栏、卡 ≥ 3:1
                Composition12.forEachIndexed { i, c ->
                    val worst12 = worst(c, compositionSurfaces(skin))
                    if (worst12.contrast < 2.9f) failures.add("${skin.id} 提交构成第 ${i + 1} 色对表面不到 3:1：${c.toCss()} on ${worst12.surface.toCss()}")
                }
                val containers = listOf(
                    "accent" to { Palette.Accent }, "shallow" to { Palette.Shallow }, "deep" to { Palette.Deep },
                    "ai" to { Palette.Ai }, "yellow" to { Palette.Yellow }, "amber" to { Palette.Amber }, "red" to { Palette.Red },
                )
                containers.forEach { (name, get) ->
                    val fill = get()
                    val on = readableOn(fill)
                    val tops = if (g > 0f) listOf(fill, glossy(fill, g), hoverOf(fill, on)) else listOf(fill, hoverOf(fill, on))
                    if (contrastOf(on, fill) < 4.45f || tops.any { contrastOf(on, it) < 4.25f }) {
                        failures.add("${skin.id} $name 容器上的可读前景不到 4.5:1（或光泽顶部 / 悬停上不到 4.3:1）：${on.toCss()} on ${fill.toCss()}")
                    }
                }
                fun f(c: Float) = "%.1f".format(c)
                table.appendLine(
                    "SKININK ${skin.id.padEnd(11)} 卡 ${card.toCss()} 光泽 ${"%.2f".format(Material.glossStrength)}  " +
                        "静置 主${f(onSurface(Palette.TextPrimary, card))} 次${f(onSurface(Palette.TextSecondary, card))} " +
                        "三${f(onSurface(Palette.TextTertiary, card))}  " +
                        "最差抬升 主${f(worst(Palette.TextPrimary, s.all).contrast)} 次${f(worst(Palette.TextSecondary, s.all).contrast)} " +
                        "三${f(worst(Palette.TextTertiary, s.all).contrast)}",
                )
            }
        } finally {
            Skins.apply(Skins.byId.getValue(Skins.DEFAULT_ID))
        }
        println(table)
        assertTrue(failures.isEmpty(), "文字 × 表面对比度不达标（${failures.size} 条）：\n" + failures.joinToString("\n"))
    }

    @Test
    fun primaryTextFollowsTheTheme() {
        // 用户 2026-11-27：「正常情况下文字应该是黑色的；看主题色，主题色是浅色采用深色文字，反之」。
        // 主文字不取皮肤数据（那里是藏青 #1a2433、奶白 #f2e8d8 这类带色相的深 / 浅色）：浅色主题纯黑，深色主题纯白。
        try {
            val light = ArrayList<String>()
            val dark = ArrayList<String>()
            Skins.all.forEach { skin ->
                Skins.apply(skin)
                val lightTheme = contrastOf(Color.Black, skin.bgBase) > contrastOf(Color.White, skin.bgBase)
                (if (lightTheme) light else dark).add(skin.id)
                val expected = if (lightTheme) Color.Black else Color.White
                assertEquals(expected.toCss(), Palette.TextPrimary.toCss(), "${skin.id}（底 ${skin.bgBase.toCss()}）的主文字应是纯${if (lightTheme) "黑" else "白"}")
            }
            // 两边都有人：这条规则不是空转（Fluent 暗色 / Aero / 玻璃 / 皮革…是深色主题，Aqua / 新拟态 / 极简…是浅色）
            assertTrue(light.contains("aqua") && light.contains("minimal") && light.contains("frutiger"), "浅色主题：$light")
            assertTrue(dark.contains("fluent") && dark.contains("aero") && dark.contains("skeuo"), "深色主题：$dark")
        } finally {
            Skins.apply(Skins.byId.getValue(Skins.DEFAULT_ID))
        }
    }

    @Test
    fun everyContainerGetsPureBlackOrWhiteThatReads() {
        // 前景只有纯黑、纯白两种；两者对比度相等的分界亮度 ≈ 0.179，在那里都是 4.58——
        // 所以任何容器色都配得出 ≥ 4.5 的前景。灰阶从黑到白逐级扫一遍，再把每套皮肤的语义色都过一遍
        for (v in 0..255 step 5) {
            val c = Color(v, v, v)
            val on = readableOn(c, 0f)
            assertTrue(on == Color.Black || on == Color.White, "前景只能是纯黑或纯白：$on")
            assertTrue(contrastOf(on, c) >= 4.5f, "灰 $v 上 ${on.toCss()} 只有 ${"%.2f".format(contrastOf(on, c))}")
        }
        try {
            Skins.all.forEach { skin ->
                Skins.apply(skin)
                listOf(Palette.Accent, Palette.Shallow, Palette.Deep, Palette.Ai, Palette.Yellow, Palette.Amber, Palette.Red).forEach { fill ->
                    val on = readableOn(fill, 0f)
                    assertTrue(contrastOf(on, fill) >= 4.5f, "${skin.id} 容器 ${fill.toCss()} 上 ${on.toCss()} 只有 ${"%.2f".format(contrastOf(on, fill))}")
                }
            }
        } finally {
            Skins.apply(Skins.byId.getValue(Skins.DEFAULT_ID))
        }
    }

    @Test
    fun darkDefaultSkinKeepsItsInkUnchanged() {
        // Fluent 暗色的语义色本来就够读：文字级必须等于基色（保底不是重设计，默认外观一个像素不变）
        Skins.apply(Skins.byId.getValue("fluent"))
        assertEquals(Palette.Accent.toCss(), Palette.AccentText.toCss())
        assertEquals(Palette.Shallow.toCss(), Palette.ShallowText.toCss())
        assertEquals(Palette.Deep.toCss(), Palette.DeepText.toCss())
        assertEquals(Palette.Ai.toCss(), Palette.AiText.toCss())
        assertEquals(Palette.Yellow.toCss(), Palette.YellowText.toCss())
        assertEquals(Palette.Amber.toCss(), Palette.AmberText.toCss())
        assertEquals(Palette.Red.toCss(), Palette.RedText.toCss())
        assertEquals(Color(0xFF1B1B1B).toCss(), Palette.OnAccent.toCss(), "暗色的 onAccent 本来达标，不该被换掉")
        assertEquals(Color(0xA8FFFFFF).toCss(), Palette.TextSecondary.toCss(), "暗色的次级文字保持半透明")
        // 三级文字在最不利的静置面（hero 顶部）上是 4.98、差 0.02：推的是透明度（仍是白），不是换成实色
        assertTrue(Palette.TextTertiary.alpha in 0.529f..0.999f, "Fluent 的三级文字仍是半透明的白：${Palette.TextTertiary.toCss()}")
        assertEquals(Color.White.toCss(), Palette.TextTertiary.copy(alpha = 1f).toCss(), "色相没变（仍是白）")
        Skins.apply(Skins.byId.getValue(Skins.DEFAULT_ID))
    }

    @Test
    fun lightSkinInkIsDarkenedAndMidToneContainersGetBlackText() {
        // Aqua：绿 #34C759（亮度约 0.43）当容器时原先配白字（2.2:1）——中等亮度的容器要配深字
        assertEquals(Color.Black.toCss(), readableOn(Color(0xFF34C759)).toCss())
        assertTrue(contrastOf(readableOn(Color(0xFF34C759)), Color(0xFF34C759)) >= 4.5f)
        // 很暗的容器仍配白字
        assertEquals(Color(0xFFFFFFFF).toCss(), readableOn(Color(0xFF1B1B1B)).toCss())
        Skins.apply(Skins.byId.getValue("aqua"))
        // 基色没被改（容器填充、进度条仍是 Aqua 的颜色）；文字级才是压暗的那一档
        assertEquals(Color(0xFF34C759).toCss(), Palette.Shallow.toCss())
        assertTrue(contrastOf(Palette.ShallowText, Palette.Card) >= 4.5f)
        assertEquals(Palette.AmberText.toCss(), ink(Palette.Amber).toCss(), "语义基色当墨 → 文字级")
        assertEquals(Palette.GreenText.toCss(), ink(Palette.Green).toCss())
        assertEquals(Color(0xFF123456).toCss(), ink(Color(0xFF123456)).toCss(), "不是语义基色的原样返回")
        Skins.apply(Skins.byId.getValue(Skins.DEFAULT_ID))
    }
}
