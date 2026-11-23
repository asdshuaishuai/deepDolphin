// TrayQuickView.kt —— 托盘速览（mac BarView.swift MenuBarExtra 菜单栏速览的 Linux 对位）。
//
// 【形态差异，如实标注】mac 是 MenuBarExtra .window 弹窗（项目行 + 迷你进度条 +
// 批量更新确认框，BarView.swift:17-39）；Linux X11 侧只有 AWT SystemTray 的
// 右键菜单——本类做简版对位：摘要行（禁用菜单项）+ 打开面板 + 退出。
// 项目行/迷你进度条/托盘内浅更新不做：PopupMenu 撑不起列表交互，硬塞是假形态。
//
// 【降级纪律】SystemTray.isSupported() == false（Wayland 原生会话无 XEmbed 托盘、
// 无系统托盘的 WM 等）→ install 返回 null，静默不装、不报错（任务口径）；
// add 抛 AWTException 同样返回 null。

package deepdolphin.sysint

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
        total == 0 -> "还没有项目在册"
        dirtyProjects == null -> "$total 个项目 · 待办数读不出来"
        dirtyProjects <= 0L -> "$total 个项目 · 没有待你动手的"
        else -> "$total 个项目 · $dirtyProjects 个待你动手"
    }

    /**
     * 装托盘图标 + 菜单。返回句柄（null = 本环境不支持，静默降级）。
     * 必须在 AWT EDT 上 add（Compose Desktop 的主线程即 EDT；main 里直接调）。
     */
    fun install(onOpenPanel: () -> Unit, onQuit: () -> Unit): Handle? {
        if (!SystemTray.isSupported()) return null
        return try {
            val menu = PopupMenu()
            val summaryItem = MenuItem("deepDolphin").apply { isEnabled = false }
            menu.add(summaryItem)
            menu.addSeparator()
            menu.add(MenuItem("打开面板").apply { addActionListener { onOpenPanel() } })
            menu.add(MenuItem("退出").apply { addActionListener { onQuit() } })

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
