// TrayQuickViewTest.kt —— 托盘摘要行纯函数判据（mac BarView header summaryLine 对位：
// 项目数 + 待办数；「读不出来」与「真的是 0」分开说）。
// install/remove 是 AWT 真托盘交互，真机冒烟由终验批截图承担，这里不造假测。

package deepdolphin.sysint

import deepdolphin.ui.AppLanguage
import deepdolphin.ui.L10n
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

class TrayQuickViewTest {

    @BeforeTest
    fun pinZh() {
        // 断言锚定 zh 文案：钉住语言，防宿主 locale / settings.conf 漂移翻红
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    @Test
    fun emptyRegistrySaysSo() {
        assertEquals("还没有项目在册", TrayQuickView.summaryLine(0, dirtyProjects = 0))
    }

    @Test
    fun dirtyCountUnknownIsNotZero() {
        // dirtyProjects == null 是「读不出来」——说成「没有待办」就是把无知说成事实
        assertEquals("3 个项目 · 待办数读不出来", TrayQuickView.summaryLine(3, dirtyProjects = null))
    }

    @Test
    fun zeroDirtyHasItsOwnWording() {
        assertEquals("3 个项目 · 没有待你动手的", TrayQuickView.summaryLine(3, dirtyProjects = 0))
    }

    @Test
    fun dirtyCountShownWithTotal() {
        assertEquals("5 个项目 · 2 个待你动手", TrayQuickView.summaryLine(5, dirtyProjects = 2))
    }
}
