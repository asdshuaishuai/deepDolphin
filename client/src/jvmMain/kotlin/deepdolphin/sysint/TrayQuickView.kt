// TrayQuickView.kt —— 托盘速览（mac BarView.swift MenuBarExtra 菜单栏速览的 Linux 对位）。
//
// 【形态差异，如实标注】mac 是 MenuBarExtra .window 弹窗（点托盘图标即弹）；
// Linux X11 侧 AWT SystemTray 只有左键点击/右键菜单——托盘**点击直弹 Compose 窗**
// 没有可靠通道（TrayIcon actionEvent 是双击且随平台变）。对位形态：菜单「速览」
// 开 380px 速览窗（BarView 完整形态在 ui/QuickView.kt：头部/项目行三态/footer），
// 菜单本身保留摘要行（禁用项）+ 打开面板 + 退出。
//
// 【降级纪律】SystemTray.isSupported() == false（Wayland 原生会话无 XEmbed 托盘、
// 无系统托盘的 WM 等）→ install 返回 null，静默不装、不报错（任务口径）；
// add 抛 AWTException 同样返回 null。

package deepdolphin.sysint

import deepdolphin.ui.L10n
import deepdolphin.ui.Palette
import androidx.compose.ui.graphics.toArgb
import java.awt.Color
import java.awt.EventQueue
import java.awt.PopupMenu
import java.awt.MenuItem
import java.awt.SystemTray
import java.awt.TrayIcon
import java.awt.image.BufferedImage

object TrayQuickView {

    /**
     * 摘要行（对位 mac BarView header 的 model.summaryLine）：
     * 项目数 + 待办（待你动手）数。dirtyProjects == null 是「读不出来」，
     * 不是 0——分开说。
     */
    fun summaryLine(total: Int, dirtyProjects: Long?): String = when {
        total == 0 -> L10n.t("cmp.tray.summary.none")
        dirtyProjects == null -> L10n.t("cmp.tray.summary.unreadable", total)
        dirtyProjects <= 0L -> L10n.t("cmp.tray.summary.zero", total)
        else -> L10n.t("cmp.tray.summary.dirty", total, dirtyProjects)
    }

    /**
     * 装托盘图标 + 菜单。返回句柄（null = 本环境不支持，静默降级）。
     * 必须在 AWT EDT 上 add（Compose Desktop 的主线程即 EDT；main 里直接调）。
     *
     * 菜单入口两枚（mac MenuBarExtra 点击弹窗的菜单对位）：「速览」开 380px 速览窗
     * （BarView 完整形态，ui/QuickView.kt）；「打开面板」置前主窗口。
     */
    fun install(onOpenPanel: () -> Unit, onQuit: () -> Unit, onQuickView: () -> Unit): Handle? {
        if (!SystemTray.isSupported()) return null
        return try {
            val menu = PopupMenu()
            val summaryItem = MenuItem("deepDolphin").apply { isEnabled = false }
            menu.add(summaryItem)
            menu.addSeparator()
            menu.add(MenuItem(L10n.t("cmp.tray.quickView")).apply { addActionListener { onQuickView() } })
            menu.add(MenuItem(L10n.t("bar.openPanel")).apply { addActionListener { onOpenPanel() } })
            menu.add(MenuItem(L10n.t("bar.quit")).apply { addActionListener { onQuit() } })

            val icon = TrayIcon(trayImage(), "deepDolphin", menu).apply { isImageAutoSize = true }
            SystemTray.getSystemTray().add(icon)
            Handle(icon, summaryItem)
        } catch (_: Exception) {
            // AWTException（托盘区已满/显示端拒绝）等：与不支持同路，静默降级
            null
        }
    }

    /** 22px 圆点图标（X11 托盘惯例尺寸；主色取设计令牌 Accent，不内联色值）。 */
    private fun trayImage(): BufferedImage {
        val img = BufferedImage(22, 22, BufferedImage.TYPE_INT_ARGB)
        val g = img.createGraphics()
        try {
            g.setRenderingHint(java.awt.RenderingHints.KEY_ANTIALIASING, java.awt.RenderingHints.VALUE_ANTIALIAS_ON)
            g.color = Color(Palette.Accent.toArgb())
            g.fillOval(2, 2, 18, 18)
            g.color = Color.WHITE
            g.fillOval(9, 9, 4, 4)
        } finally {
            g.dispose()
        }
        return img
    }

    /** 托盘句柄：更新摘要行 / 卸除图标。 */
    class Handle internal constructor(
        private val icon: TrayIcon,
        private val summaryItem: MenuItem,
    ) {
        /** 刷新摘要行（状态流变化时由 UI 推送）。 */
        fun updateSummary(line: String) {
            EventQueue.invokeLater { summaryItem.label = line }
        }

        /** 卸除托盘图标（窗口关闭/退出前调用；幂等——重复 remove 由 SystemTray 吞掉）。 */
        fun remove() {
            EventQueue.invokeLater {
                runCatching { SystemTray.getSystemTray().remove(icon) }
            }
        }
    }
}
