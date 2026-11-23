// ShortcutMapTest.kt —— 键位映射判据（mac ShortcutMap.swift 的 duplicatePairs/shortcut(for:)
// 判据对位：映射唯一来源、无撞车、Ctrl 才消费）。

package deepdolphin.ui

import androidx.compose.ui.input.key.Key
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
            assertEquals(a, ShortcutMap.actionOf(true, sc.key), "$a 声明了键位却映射不回来")
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
}
