// MenuBar.kt —— 窗口内菜单条（mac 原生菜单栏 CommandMenu/CommandGroup 的 Linux 等价物）。
//
// Compose Desktop 无原生菜单栏；mac 的应用菜单（关于 / 设置 / 退出）、「操作」菜单
// （浅/深更新跟随当前范围、刷新、停止更新）与「帮助」菜单（帮助文档 + 两个仓库入口）
// 在这里以窗口顶部的 Fluent 菜单条对位。菜单项与工作条/快捷键走同一入口
//（runUpdate / refreshAll / stopUpdate），不另开第二条真相。
//
// 二次验证抓到：原来「操作」菜单恒为全部范围且没有禁用态；帮助菜单落到「设置·通用」
// 而不是关于 tab；没有应用菜单；刷新只在仪表盘 hero 里有（mac 的工具栏刷新常驻）。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.MutableStateFlow

/** 文档深开请求（帮助/关于菜单 → 设置页「关于」tab 的对应子 tab）；消费方取用后清空。 */
object DocsNav {
    val request = MutableStateFlow<DocKind?>(null)
    fun open(kind: DocKind) {
        request.value = kind
    }
}

/** 窗口内菜单条（mac 菜单栏命令的等价物；只在引擎就绪的主面板态出现）。 */
@Composable
fun AppMenuBar(model: AppModel, onQuit: () -> Unit = {}) {
    val busy by model.busyAction.collectAsState()
    Row(
        Modifier.fillMaxWidth().height(44.dp).background(Palette.Sidebar)
            .padding(horizontal = Space.lg),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        MenuAnchor("deepDolphin") { close ->
            DropdownMenuItem(
                text = { Text(L10n.t("menu.about"), style = Type.body) },
                onClick = { model.goRoute(AppModel.Route.SETTINGS); DocsNav.open(DocKind.ABOUT); close() },
            )
            DropdownMenuItem(
                text = { Text(L10n.t("toolbar.settings"), style = Type.body) },
                onClick = { model.goRoute(AppModel.Route.SETTINGS); close() },
            )
            HorizontalDivider(color = Palette.Stroke)
            DropdownMenuItem(
                text = { Text(L10n.t("common.quit"), style = Type.body) },
                onClick = { close(); onQuit() },
            )
        }
        MenuAnchor(L10n.t("cmp.menu.operations")) { close ->
            // 菜单项跟随当前范围（mac 同款）：选中项目 = 单项目直跑；全局 = 先弹告知式确认
            val scoped = WorkBarScope.updateScope(model.route.value, model.selectedProject.value)
            DropdownMenuItem(
                text = { Text(shallowUpdateLabel(scoped), style = Type.body) },
                enabled = !busy,
                onClick = { model.runUpdate(deep = false); close() },
            )
            DropdownMenuItem(
                text = { Text(deepUpdateLabel(scoped), style = Type.body) },
                enabled = !busy,
                onClick = { model.runUpdate(deep = true); close() },
            )
            HorizontalDivider(color = Palette.Stroke)
            DropdownMenuItem(
                text = { Text(L10n.t("toolbar.refresh"), style = Type.body) },
                onClick = { model.refreshAll(); close() },
            )
            // 没有更新在跑时禁用（mac .disabled(!model.canStopUpdate)）
            DropdownMenuItem(
                text = { Text(L10n.t("cmp.menu.stopUpdate"), style = Type.body) },
                enabled = model.canStopUpdate,
                onClick = { model.stopUpdate(); close() },
            )
        }
        MenuAnchor(L10n.t("menu.help")) { close ->
            DropdownMenuItem(
                text = { Text(L10n.t("menu.help"), style = Type.body) },
                onClick = { model.goRoute(AppModel.Route.SETTINGS); DocsNav.open(DocKind.HELP); close() },
            )
            HorizontalDivider(color = Palette.Stroke)
            DropdownMenuItem(
                text = { Text(L10n.t("menu.github"), style = Type.body) },
                onClick = { browse("https://github.com/asdshuaishuai/deepDolphin"); close() },
            )
            DropdownMenuItem(
                text = { Text(L10n.t("menu.engine"), style = Type.body) },
                onClick = { browse("https://github.com/asdshuaishuai/moongit"); close() },
            )
        }
        Spacer(Modifier.weight(1f))
        // 常驻刷新：mac 在原生工具栏，每一页都在；CMP 原来只有仪表盘 hero 里有
        HelpTooltip(L10n.t("dash.reindex.help")) {
            FluentButton(L10n.t("toolbar.refresh"), onClick = { model.refreshAll() }, icon = FluentIcon.ArrowSync)
        }
    }
}

/** 菜单锚点：文字按钮 + 下拉（Fluent 菜单条形态：无边框、hover 由底色呈现）。 */
@Composable
private fun MenuAnchor(
    label: String,
    content: @Composable (close: () -> Unit) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        Text(
            label,
            style = Type.body,
            color = Palette.TextPrimary,
            modifier = Modifier
                .clickable { open = true }
                .padding(horizontal = Space.md, vertical = 4.dp),
        )
        DropdownMenu(
            expanded = open,
            onDismissRequest = { open = false },
            containerColor = Palette.Card,
        ) {
            content { open = false }
        }
    }
}

/** 打开系统浏览器（帮助菜单的仓库入口）。 */
private fun browse(url: String) {
    runCatching {
        java.awt.Desktop.getDesktop().browse(java.net.URI(url))
    }.onFailure {
        // 无桌面环境的兜底：如实输出到控制台（GUI 无处弹，不静默吞）
        println("open url failed: $url (${it.message})")
    }
}
