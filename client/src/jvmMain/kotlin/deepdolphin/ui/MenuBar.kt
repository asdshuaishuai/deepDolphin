// MenuBar.kt —— 窗口内菜单条（mac 原生菜单栏 CommandMenu/CommandGroup 的 Linux 等价物）。
//
// Compose Desktop 无原生菜单栏；mac 的「操作」菜单（全部浅/深更新走同一确认链、
// 刷新、停止更新=杀引擎子进程本体）与「帮助」菜单（帮助文档 + 两个仓库入口）
// 在这里以窗口顶部的 Fluent 菜单条对位。菜单项与工作条/快捷键走同一入口
//（requestBulkUpdate / refreshAll），不另开第二条真相。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** 帮助文档深开触发（帮助菜单 → 设置-关于-帮助子 tab；自增计数即触发一次）。 */
object DocsNav {
    val openHelp = kotlinx.coroutines.flow.MutableStateFlow(0)
}

/** 窗口内菜单条（mac 菜单栏命令的等价物；只在引擎就绪的主面板态出现）。 */
@Composable
fun AppMenuBar(model: AppModel) {
    Row(
        Modifier.fillMaxWidth().height(32.dp).background(Palette.Sidebar)
            .padding(horizontal = Space.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        MenuAnchor(L10n.t("cmp.menu.operations")) { close ->
            DropdownMenuItem(
                text = { Text(L10n.t("update.allShallow"), style = Type.body) },
                onClick = { model.requestBulkUpdate(deep = false); close() },
            )
            DropdownMenuItem(
                text = { Text(L10n.t("update.deepAll"), style = Type.body) },
                onClick = { model.requestBulkUpdate(deep = true); close() },
            )
            HorizontalDivider(color = Palette.Stroke)
            DropdownMenuItem(
                text = { Text(L10n.t("toolbar.refresh"), style = Type.body) },
                onClick = { model.refreshAll(); close() },
            )
            DropdownMenuItem(
                text = { Text(L10n.t("cmp.menu.stopUpdate"), style = Type.body) },
                onClick = { model.stopUpdate(); close() },
            )
        }
        MenuAnchor(L10n.t("menu.help")) { close ->
            DropdownMenuItem(
                text = { Text(L10n.t("menu.help"), style = Type.body) },
                onClick = {
                    model.goRoute(AppModel.Route.SETTINGS)
                    DocsNav.openHelp.value += 1
                    close()
                },
            )
            HorizontalDivider(color = Palette.Stroke)
            DropdownMenuItem(
                text = { Text("GitHub · deepDolphin", style = Type.body) },
                onClick = { browse("https://github.com/asdshuaishuai/deepDolphin"); close() },
            )
            DropdownMenuItem(
                text = { Text("Engine · moonGit", style = Type.body) },
                onClick = { browse("https://github.com/asdshuaishuai/moongit"); close() },
            )
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
