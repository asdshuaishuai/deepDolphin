// ShortcutMapTest.kt —— 键位映射判据（mac ShortcutMap.swift 的 duplicatePairs/shortcut(for:)
// 判据对位：映射唯一来源、无撞车、Ctrl 才消费）。

package canopy.ui

import androidx.compose.ui.input.key.Key
import java.awt.event.KeyEvent
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ShortcutMapTest {

    @BeforeTest
    fun pinZh() {
        // 断言锚定 zh 文案：钉住语言，防宿主 locale / settings.conf 漂移翻红
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    // ── 映射本体（任务口径：Ctrl+1/2/3 视图、Ctrl+, 设置、Ctrl+R 刷新、Ctrl+F 聚焦搜索）──

    @Test
    fun viewKeysMapToViews() {
        assertEquals(ShortcutMap.Action.DASHBOARD, ShortcutMap.actionOf(true, Key.One))
        assertEquals(ShortcutMap.Action.BOARD, ShortcutMap.actionOf(true, Key.Two))
        assertEquals(ShortcutMap.Action.MILESTONES, ShortcutMap.actionOf(true, Key.Three))
    }

    @Test
    fun settingsIsCommaAndRefreshIsR() {
        assertEquals(ShortcutMap.Action.SETTINGS, ShortcutMap.actionOf(true, Key.Comma))
        assertEquals(ShortcutMap.Action.REFRESH, ShortcutMap.actionOf(true, Key.R))
        assertEquals(ShortcutMap.Action.FOCUS_SEARCH, ShortcutMap.actionOf(true, Key.F))
    }

    @Test
    fun everyDeclaredActionResolvesBackToItsKey() {
        // shortcutFor ↔ actionOf 必须互逆：声明了却消费不到的键位 = 用户按了没反应
        ShortcutMap.Action.entries.forEach { a ->
            val sc = ShortcutMap.shortcutFor(a)
            assertEquals(a, ShortcutMap.actionOf(true, sc.key, sc.shift, sc.alt), "$a 声明了键位却映射不回来")
        }
    }

    // ── 修饰键纪律：全表 Ctrl 组合，裸键不消费 ──

    @Test
    fun bareKeysWithoutCtrlAreNotConsumed() {
        // 文本框里敲 1/r/f/, 不许被窗口级拦截吞掉
        ShortcutMap.all.forEach { sc ->
            assertEquals(null, ShortcutMap.actionOf(false, sc.key), "${sc.label} 的裸键不得触发动作")
        }
    }

    @Test
    fun everyShortcutIsCtrlCombo() {
        ShortcutMap.all.forEach { sc ->
            assertTrue(sc.ctrl, "${sc.label} 必须是 Ctrl 组合（Linux 主修饰键，全表一致）")
        }
    }

    // ── 冲突判据（对位 mac duplicatePairs：两个动作占同一个键只有真跑起来才知道）──

    @Test
    fun noDuplicateKeys() {
        assertEquals(emptyList(), ShortcutMap.duplicateKeys())
    }

    @Test
    fun labelsAreUniqueAndPrefixed() {
        val labels = ShortcutMap.all.map { it.label }
        assertEquals(labels.size, labels.toSet().size, "人类可读键位不得重名")
        labels.forEach { assertTrue(it.startsWith("Ctrl+"), "$it 展示形必须带修饰键前缀") }
    }

    @Test
    fun unknownKeyMapsToNothing() {
        assertEquals(null, ShortcutMap.actionOf(true, Key.Nine))
        assertEquals(null, ShortcutMap.actionOf(true, Key.X))
    }

    // ── AWT 侧映射（WebView 持有焦点时键事件走 AWT，Compose 的预览收不到）：
    //    两套键码必须指向同一张表——少了任何一个，图谱页里那个快捷键就哑 ──

    private val awtSource = java.awt.Canvas()

    private fun awtEvent(id: Int, code: Int, mods: Int) =
        java.awt.event.KeyEvent(awtSource, id, 0L, mods, code, KeyEvent.CHAR_UNDEFINED)

    @Test
    fun everyShortcutCarriesAnAwtCodeMatchingItsLabel() {
        // 不用 KeyEvent.getKeyText 反查：它跟着 JVM 默认语言走（中文下逗号显示成「逗号」），
        // 判据要跟语言无关——这里手写一张「展示形键名 → AWT 键码」的对照表
        val expected = mapOf(
            "1" to KeyEvent.VK_1, "2" to KeyEvent.VK_2, "3" to KeyEvent.VK_3, "4" to KeyEvent.VK_4,
            "7" to KeyEvent.VK_7, "8" to KeyEvent.VK_8, "," to KeyEvent.VK_COMMA, "R" to KeyEvent.VK_R,
            "U" to KeyEvent.VK_U, "D" to KeyEvent.VK_D, "." to KeyEvent.VK_PERIOD, "F" to KeyEvent.VK_F,
        )
        ShortcutMap.all.forEach { sc ->
            val keyName = sc.label.substringAfterLast('+')
            assertEquals(expected[keyName], sc.awt, "${sc.label} 的 AWT 键码与展示形不是同一个键")
        }
        assertEquals(ShortcutMap.all.size, expected.size, "对照表要覆盖全表键位")
    }

    @Test
    fun awtEventsResolveToTheSameActions() {
        assertEquals(ShortcutMap.Action.DASHBOARD, ShortcutMap.awtActionOf(awtEvent(KeyEvent.KEY_PRESSED, KeyEvent.VK_1, KeyEvent.CTRL_DOWN_MASK)))
        assertEquals(ShortcutMap.Action.FOCUS_SEARCH, ShortcutMap.awtActionOf(awtEvent(KeyEvent.KEY_PRESSED, KeyEvent.VK_F, KeyEvent.CTRL_DOWN_MASK)))
        assertEquals(
            ShortcutMap.Action.SHALLOW_UPDATE,
            ShortcutMap.awtActionOf(awtEvent(KeyEvent.KEY_PRESSED, KeyEvent.VK_U, KeyEvent.CTRL_DOWN_MASK or KeyEvent.SHIFT_DOWN_MASK)),
        )
        assertEquals(
            ShortcutMap.Action.DEEP_UPDATE,
            ShortcutMap.awtActionOf(awtEvent(KeyEvent.KEY_PRESSED, KeyEvent.VK_D, KeyEvent.CTRL_DOWN_MASK or KeyEvent.SHIFT_DOWN_MASK or KeyEvent.ALT_DOWN_MASK)),
        )
        // Ctrl+U 不是浅更新；松开沿不算；裸键不消费；带 Meta 的组合不算
        assertEquals(null, ShortcutMap.awtActionOf(awtEvent(KeyEvent.KEY_PRESSED, KeyEvent.VK_U, KeyEvent.CTRL_DOWN_MASK)))
        assertEquals(null, ShortcutMap.awtActionOf(awtEvent(KeyEvent.KEY_RELEASED, KeyEvent.VK_1, KeyEvent.CTRL_DOWN_MASK)))
        assertEquals(null, ShortcutMap.awtActionOf(awtEvent(KeyEvent.KEY_PRESSED, KeyEvent.VK_1, 0)))
        assertEquals(null, ShortcutMap.awtActionOf(awtEvent(KeyEvent.KEY_PRESSED, KeyEvent.VK_F, KeyEvent.CTRL_DOWN_MASK or KeyEvent.META_DOWN_MASK)))
    }
}
