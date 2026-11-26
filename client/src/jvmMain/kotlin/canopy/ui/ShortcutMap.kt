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
// 键位与 mac 全表一一对应（⌘→Ctrl）：视图 1/2/3/7/8、当前项目 4、设置 ⌘,、刷新 R、
// 浅更新 ⇧⌘U、深更新 ⌥⇧⌘D、停止 ⌘.、查找 F。
// 二次验证抓到：原来只接了 6 个键，且处理器不分按下/抬起——每个快捷键触发两遍。

package canopy.ui

import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.input.key.Key
import java.awt.Component
import java.awt.KeyEventDispatcher
import java.awt.KeyboardFocusManager
import java.awt.event.KeyEvent

object ShortcutMap {

    /** 快捷键动作。 */
    enum class Action {
        DASHBOARD, BOARD, MILESTONES, CONFIDENCE, PATCHCHECK, CURRENT_PROJECT,
        SETTINGS, REFRESH, SHALLOW_UPDATE, DEEP_UPDATE, STOP_UPDATE, FOCUS_SEARCH,
    }

    /** 一条键位声明：label 是人类可读形式（判据与提示共用；字母键大写，mac display 同纪律）；
     *  awt 是同一个键在 AWT 侧的虚拟键码（WebView 持有焦点时键事件走 AWT，见 awtActionOf）。 */
    data class Shortcut(
        val key: Key,
        val label: String,
        val shift: Boolean = false,
        val alt: Boolean = false,
        val awt: Int = KeyEvent.VK_UNDEFINED,
    ) {
        /** 全表都是 Ctrl 组合（Linux 主修饰键）。 */
        val ctrl: Boolean get() = true
    }

    val dashboard = Shortcut(Key.One, "Ctrl+1", awt = KeyEvent.VK_1)
    val board = Shortcut(Key.Two, "Ctrl+2", awt = KeyEvent.VK_2)
    val milestones = Shortcut(Key.Three, "Ctrl+3", awt = KeyEvent.VK_3)
    val confidence = Shortcut(Key.Seven, "Ctrl+7", awt = KeyEvent.VK_7)
    val patchCheck = Shortcut(Key.Eight, "Ctrl+8", awt = KeyEvent.VK_8)
    val currentProject = Shortcut(Key.Four, "Ctrl+4", awt = KeyEvent.VK_4)
    val settings = Shortcut(Key.Comma, "Ctrl+,", awt = KeyEvent.VK_COMMA)
    val refresh = Shortcut(Key.R, "Ctrl+R", awt = KeyEvent.VK_R)
    val shallow = Shortcut(Key.U, "Ctrl+Shift+U", shift = true, awt = KeyEvent.VK_U)
    val deep = Shortcut(Key.D, "Ctrl+Shift+Alt+D", shift = true, alt = true, awt = KeyEvent.VK_D)
    val stop = Shortcut(Key.Period, "Ctrl+.", awt = KeyEvent.VK_PERIOD)
    val find = Shortcut(Key.F, "Ctrl+F", awt = KeyEvent.VK_F)

    private val byAction: LinkedHashMap<Action, Shortcut> = linkedMapOf(
        Action.DASHBOARD to dashboard,
        Action.BOARD to board,
        Action.MILESTONES to milestones,
        Action.CONFIDENCE to confidence,
        Action.PATCHCHECK to patchCheck,
        Action.CURRENT_PROJECT to currentProject,
        Action.SETTINGS to settings,
        Action.REFRESH to refresh,
        Action.SHALLOW_UPDATE to shallow,
        Action.DEEP_UPDATE to deep,
        Action.STOP_UPDATE to stop,
        Action.FOCUS_SEARCH to find,
    )

    /** 动作 → 键位（唯一来源，别处不许手写 Key）。 */
    fun shortcutFor(action: Action): Shortcut = byAction.getValue(action)

    /**
     * 键位 → 动作（onPreviewKeyEvent 的消费口）。修饰键必须**整组匹配**：
     * Ctrl+U 不是 Ctrl+Shift+U；Ctrl 未按下返回 null——裸键不归这里管。
     */
    fun actionOf(ctrlPressed: Boolean, key: Key, shift: Boolean = false, alt: Boolean = false): Action? {
        if (!ctrlPressed) return null
        return byAction.entries.firstOrNull { (_, sc) -> sc.key == key && sc.shift == shift && sc.alt == alt }?.key
    }

    /**
     * AWT 键事件 → 动作（修饰键同样整组匹配）。
     * 键事件在 AWT 层被 [AppShortcuts] 统一接管，不再依赖 Compose 里「恰好有节点持有焦点」：
     * 原先挂在窗口内容根的 onPreviewKeyEvent 只在内部某个节点有焦点时才收得到事件——刚启动什么都没点、
     * 或被点的控件随即消失（清空搜索框的「×」）时焦点为空，Ctrl+1/2/3 全没反应；
     * WebView（AWT 组件）持有焦点时更是完全收不到。
     */
    fun awtActionOf(e: KeyEvent): Action? {
        if (e.id != KeyEvent.KEY_PRESSED || !e.isControlDown || e.isMetaDown) return null
        return byAction.entries.firstOrNull { (_, sc) ->
            sc.awt == e.keyCode && sc.shift == e.isShiftDown && sc.alt == e.isAltDown
        }?.key
    }

    /** 全部声明过的键位。 */
    val all: List<Shortcut> = byAction.values.toList()

    /** 撞车的键位（对位 mac duplicatePairs 判据：键 + 修饰键整组相同才算撞；返回空 = 表内无冲突）。 */
    fun duplicateKeys(): List<Key> =
        all.groupBy { Triple(it.key, it.shift, it.alt) }.filterValues { it.size > 1 }.keys.map { it.first }
}

/**
 * 应用快捷键的统一接管点：KeyEventDispatcher 在事件送达焦点归属者之前被调用，
 * 焦点在主画布、输入框、弹出的菜单/对话框还是 WebView 里都一样生效；命中应用键位就执行并吞掉
 * （Ctrl+R 是「刷新全部」而不是刷新网页，全窗口一致），其余原样放行。
 * handle 只在 AWT 事件线程上读写。
 */
internal object AppShortcuts : KeyEventDispatcher {
    private var handle: ((ShortcutMap.Action, Component?) -> Boolean)? = null

    /** 装上唯一的处理器（重复调用只替换处理器，分发器只登记一次）。 */
    fun install(h: (ShortcutMap.Action, Component?) -> Boolean) {
        if (handle == null) KeyboardFocusManager.getCurrentKeyboardFocusManager().addKeyEventDispatcher(this)
        handle = h
    }

    override fun dispatchKeyEvent(e: KeyEvent): Boolean {
        val h = handle ?: return false
        return ShortcutMap.awtActionOf(e)?.let { h(it, e.source as? Component) } ?: false
    }
}

/** 侧栏搜索框的焦点句柄（Ctrl+F）。 */
internal object SidebarSearchFocus {
    val requester = FocusRequester()

    /**
     * 把光标送进侧栏搜索框。[from] 是发起时的 AWT 事件源：焦点在 WebView（AWT 组件）里时，
     * 只给搜索框 Compose 焦点收不到按键——先把 AWT 焦点交还给主面板的画布。
     */
    fun request(from: Component? = null): Boolean = runCatching {
        if (from != null) {
            mainCanvasOf(from)?.requestFocusInWindow()
            // AWT 焦点转移不是立刻生效的：等它落到主画布，再向 Compose 要焦点
            javax.swing.Timer(150) {
                requester.requestFocus()
            }.apply { isRepeats = false; start() }
        } else {
            requester.requestFocus()
        }
        true
    }.getOrDefault(false)

    /**
     * WebView 宿主往上找到互操作组，它的上一级是主面板；主画布是主面板里除互操作组与占位隐形组件
     * 之外那个可聚焦的子级。Compose 这几个类是 internal，只能按名字认——换 Compose 版本若改名，
     * 这里安全地退化为「不交还焦点」（Ctrl+F 聚焦不到搜索框），不会抛异常。
     */
    private fun mainCanvasOf(from: Component): Component? {
        val interop = generateSequence(from) { it.parent }
            .firstOrNull { it.javaClass.name == "androidx.compose.ui.awt.SwingInteropViewGroup" } ?: return null
        val panel = interop.parent ?: return null
        return panel.components.firstOrNull { c ->
            c !== interop && c.isFocusable && !c.javaClass.simpleName.contains("Invisible")
        }
    }
}

/**
 * 快捷键动作的唯一执行口：窗口根的 onPreviewKeyEvent 与 WebView 聚焦时的 AWT 转发
 * （HtmlWebView）都走这里——按钮、菜单、两处快捷键不会各写一套范围/确认/忙碌判定。
 * 返回 true = 已处理。
 */
fun AppModel.runShortcut(action: ShortcutMap.Action, focusSearch: () -> Boolean = { false }): Boolean = when (action) {
    ShortcutMap.Action.DASHBOARD -> { goRoute(AppModel.Route.DASHBOARD); true }
    ShortcutMap.Action.BOARD -> { goRoute(AppModel.Route.BOARD); true }
    ShortcutMap.Action.MILESTONES -> { goRoute(AppModel.Route.MILESTONES); true }
    ShortcutMap.Action.CONFIDENCE -> { goRoute(AppModel.Route.CONFIDENCE); true }
    ShortcutMap.Action.PATCHCHECK -> { goRoute(AppModel.Route.PATCHCHECK); true }
    ShortcutMap.Action.CURRENT_PROJECT -> {
        // 已在某个仓库里就不动（再按一次 = 原地踏步）；否则进列表里的第一个
        if (selectedProject.value == null) {
            status.value?.projects?.firstOrNull()?.let { goRoute(AppModel.Route.PROJECT, it.name) }
        }
        true
    }
    ShortcutMap.Action.SETTINGS -> { goRoute(AppModel.Route.SETTINGS); true }
    ShortcutMap.Action.REFRESH -> { refreshAll(); true }
    // 双轨与停止走和按钮/菜单同一个入口（范围、确认框、忙碌判定完全一致）
    ShortcutMap.Action.SHALLOW_UPDATE -> { runUpdate(deep = false); true }
    ShortcutMap.Action.DEEP_UPDATE -> { runUpdate(deep = true); true }
    ShortcutMap.Action.STOP_UPDATE -> { stopUpdate(); true }
    ShortcutMap.Action.FOCUS_SEARCH -> { focusSearch(); true }
}
