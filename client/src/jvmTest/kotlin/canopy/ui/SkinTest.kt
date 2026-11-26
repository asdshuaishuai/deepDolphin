// SkinTest.kt —— 皮肤数据的守卫：14 套（namethatui 全风格 − flat）、颜色必须 8 位 ARGB（6 位 = alpha 0 = 文字隐身）、
// 恢复默认、app.skin 键合并只动自己的键。
package canopy.ui

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
}
