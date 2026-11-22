// Main.kt —— deepDolphin（Compose Multiplatform）入口。
//
// 骨架职责：窗口 + 引擎探活 + 磁贴外壳。能力分批落地（C1–C11，
// 对位 archive/bui 与 macos 基准）；每一步都可运行验证。

package deepdolphin

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import kotlinx.coroutines.launch

@Composable
fun App() {
    val scope = rememberCoroutineScope()
    var probe by remember { mutableStateOf<EngineProbe?>(null) }
    var busy by remember { mutableStateOf(true) }

    fun reprobe() {
        busy = true
        scope.launch {
            probe = EngineLocator.probe()
            busy = false
        }
    }

    LaunchedEffect(Unit) { reprobe() }

    MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(primary = Color(0xFF4C8DFF))) {
        Column(Modifier.fillMaxSize().background(Color(0xFF0A0F1A))) {
            // 页头
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text("deepDolphin", color = Color(0xFFE6EDF3), fontWeight = FontWeight.Bold)
                    Text(
                        "moonGit · 项目群进度引擎（Compose Multiplatform）",
                        color = Color(0xFF8B98A9),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Button(onClick = { reprobe() }, shape = RoundedCornerShape(8.dp)) {
                    Text("重新检测引擎")
                }
            }
            // 状态磁贴
            Box(Modifier.fillMaxSize().padding(20.dp), contentAlignment = Alignment.Center) {
                when {
                    busy -> Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(22.dp))
                        Spacer(Modifier.width(12.dp))
                        Text("正在定位引擎…", color = Color(0xFF8B98A9))
                    }
                    probe != null && probe!!.found -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("✓ 引擎已就绪", color = Color(0xFF3FCF8E), fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(8.dp))
                        Text(probe!!.version, color = Color(0xFFE6EDF3))
                        Spacer(Modifier.height(4.dp))
                        Text(probe!!.path, color = Color(0xFF8B98A9), style = MaterialTheme.typography.bodySmall)
                        Text(
                            "面板四页 / AI 助手 / 设置等能力将分批落地（C1–C11）",
                            color = Color(0xFF8B98A9), style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    else -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("未找到 moonGit 引擎", color = Color(0xFFF0883E), fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(8.dp))
                        Text("MOONGIT_BIN / DEEPGIT_BIN 或安装到 PATH 后，点「重新检测引擎」", color = Color(0xFF8B98A9))
                    }
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
