// ShortcutMap.kt —— 键位映射的唯一声明处（纯对象，mac ShortcutMap.swift 对位）。
//
// 【为什么集中声明】散着写 onPreviewKeyEvent 会有三个问题（mac 原话）：
//   1. 冲突查不出来——两个动作各占 Ctrl+1，只有真跑起来才知道；
//   2. 写法不统一；
//   3. 键位数与真实视图数对不上，没人回头核对。
// 视图只问 ShortcutMap.actionOf()；判据用 duplicateKeys() 查撞车。
//
// 【修饰键】mac 是 ⌘（cmd）；Linux 桌面惯例的主修饰键是 Ctrl——全表 Ctrl 组合，
// onPreviewKeyEvent 在窗口根拦截（对位 mac 的窗口级 keyboardShortcut 语义）。
// 本批接线的键位（任务口径）：Ctrl+1/2/3 视图、Ctrl+, 设置、Ctrl+R 刷新、Ctrl+F 聚焦侧栏搜索。
// mac 还有 ⌘4（当前项目）等键位——CMP 未接线就不声明（mac 纪律：键位只跟着真实存在的动作走，
// 声明了没接线的键位 = 用户按了没反应却看不出为什么）。

package deepdolphin.ui

import androidx.compose.ui.input.key.Key

object ShortcutMap {

    /** 快捷键动作。 */
    enum class Action { DASHBOARD, BOARD, MILESTONES, SETTINGS, REFRESH, FOCUS_SEARCH }

    /** 一条键位声明：label 是人类可读形式（判据与提示共用；字母键大写，mac display 同纪律）。 */
    data class Shortcut(val key: Key, val label: String) {
        /** 全表都是 Ctrl 组合（Linux 主修饰键）。 */
        val ctrl: Boolean get() = true
    }

    val dashboard = Shortcut(Key.One, "Ctrl+1")
    val board = Shortcut(Key.Two, "Ctrl+2")
    val milestones = Shortcut(Key.Three, "Ctrl+3")
    val settings = Shortcut(Key.Comma, "Ctrl+,")
    val refresh = Shortcut(Key.R, "Ctrl+R")
    val find = Shortcut(Key.F, "Ctrl+F")

    private val byAction: LinkedHashMap<Action, Shortcut> = linkedMapOf(
        Action.DASHBOARD to dashboard,
        Action.BOARD to board,
        Action.MILESTONES to milestones,
        Action.SETTINGS to settings,
        Action.REFRESH to refresh,
        Action.FOCUS_SEARCH to find,
    )

    /** 动作 → 键位（唯一来源，别处不许手写 Key）。 */
    fun shortcutFor(action: Action): Shortcut = byAction.getValue(action)

    /**
     * 键位 → 动作（onPreviewKeyEvent 的消费口）。
     * Ctrl 未按下返回 null——全表都是 Ctrl 组合，无修饰的裸键不归这里管。
     */
    fun actionOf(ctrlPressed: Boolean, key: Key): Action? {
        if (!ctrlPressed) return null
        return byAction.entries.firstOrNull { it.value.key == key }?.key
    }

    /** 全部声明过的键位。 */
    val all: List<Shortcut> = byAction.values.toList()

    /** 撞车的键位（对位 mac duplicatePairs 判据：返回空 = 表内无冲突）。 */
    fun duplicateKeys(): List<Key> =
        all.groupBy { it.key }.filterValues { it.size > 1 }.keys.toList()
}
