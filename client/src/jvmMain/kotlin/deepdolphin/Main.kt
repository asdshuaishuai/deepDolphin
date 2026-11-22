// Main.kt —— deepDolphin（Compose Multiplatform）入口。
//
// 批 1：窗口 + 引擎探活（C1）+ 仪表盘（C3）+ C2 周期轮询。
// 能力分批落地（C1–C11，对位 archive/bui 与 macos 基准）；每一步都可运行验证。

package deepdolphin

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowState
import androidx.compose.ui.window.application
import deepdolphin.engine.EngineLocator
import deepdolphin.engine.EngineProbe
import deepdolphin.ui.AppModel
import deepdolphin.ui.DashboardPage
import deepdolphin.ui.Palette
import deepdolphin.ui.Type
import kotlinx.coroutines.launch

@Composable
fun App() {
    val scope = rememberCoroutineScope()
    var probe by remember { mutableStateOf<EngineProbe?>(null) }
    var busy by remember { mutableStateOf(true) }
    var model by remember { mutableStateOf<AppModel?>(null) }

    fun reprobe() {
        busy = true
        scope.launch {
            probe = EngineLocator.probe()
            model = probe?.takeIf { it.found }?.let { AppModel(it.path) }
            model?.refreshAll()
            model?.startPolling() // C2 周期轮询 5 分钟
            busy = false
        }
    }

    LaunchedEffect(Unit) { reprobe() }
    DisposableEffect(Unit) { onDispose { model?.stop() } }

    Column(Modifier.fillMaxSize().background(Palette.BgBase)) {
        // ── 页头（唯一 chrome；双轨更新只在 WorkBar 一处的纪律随批 2 落地）──
        Row(
            Modifier.fillMaxWidth().background(Palette.BgDeep).padding(horizontal = 20.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                Text("deepDolphin", style = Type.section.copy(fontWeight = FontWeight.Bold))
                Text("moonGit · 项目群进度引擎（Compose Multiplatform）", style = Type.micro)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (busy) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = Palette.Accent, strokeWidth = 2.dp)
                    Text("正在定位引擎…", style = Type.label)
                }
                Button(
                    onClick = { reprobe() },
                    enabled = !busy,
                    shape = androidx.compose.foundation.shape.RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
                ) { Text("重新检测引擎") }
            }
        }

        when {
            busy -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("正在定位引擎…", style = Type.body.copy(color = Palette.TextSecondary))
            }
            probe != null && probe!!.found && model != null -> DashboardPage(model!!)
            else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("未找到 moonGit 引擎", style = Type.title.copy(color = Palette.Amber))
                    Spacer(Modifier.height(8.dp))
                    Text("MOONGIT_BIN / DEEPGIT_BIN 或安装到 PATH 后，点「重新检测引擎」", style = Type.body.copy(color = Palette.TextSecondary))
                }
            }
        }
    }
}

fun main() = application {
    Window(
        onCloseRequest = ::exitApplication,
        state = WindowState(width = 1280.dp, height = 860.dp),
        title = "deepDolphin",
    ) {
        App()
    }
}
