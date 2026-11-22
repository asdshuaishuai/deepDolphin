// BoardView.kt —— 看板页（C3 的 board 列视图）批 2 只给骨架壳：数据已有（status 的 branches），
// 列渲染留批 3（拖拽/列裁剪等交互一次做对）。空态如实披露，不假装功能存在。

package deepdolphin.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import deepdolphin.ui.Palette
import deepdolphin.ui.Type

@Composable
fun BoardPage(model: AppModel) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("看板列视图在批 3 落地", style = Type.title)
            Spacer(Modifier.height(8.dp))
            Text("数据通路（status.branches）已就绪；列渲染与拖拽一次做对", style = Type.body.copy(color = Palette.TextSecondary))
        }
    }
}
