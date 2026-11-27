// GraphHeaderLayoutTest.kt —— 图谱两页页头的布局判据（离屏 Compose 场景：量的是真的布局结果）。
//
// 【量的是什么】最小窗口（960，内容区 730）下页头的标题不许被挤成一个字一行——原先标题列是页头里
// 唯一带 weight 的一列，回执胶囊（最宽 360）与三个按钮先把宽度占满，标题只剩几十像素（实拍竖排）。
// 现在标题按内容宽、永远单行，让位顺序是：回执胶囊缩到只剩图标 → 副标题不显示。

package canopy.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.test.BeforeTest
import kotlin.test.Test

class GraphHeaderLayoutTest {

    @BeforeTest
    fun pinZh() {
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    private fun subtitleOf(repo: String, kind: GraphKind) = "$repo · ${kind.subtitle()}"

    @OptIn(ExperimentalTestApi::class)
    private fun header(width: Dp, status: GraphReceipt?, block: androidx.compose.ui.test.ComposeUiTest.() -> Unit) =
        runComposeUiTest {
            setContent {
                MaterialTheme(colorScheme = fluentColorScheme(), typography = FluentTypography, shapes = FluentShapes) {
                    Column(Modifier.width(width)) {
                        Box(Modifier.fillMaxWidth()) {
                            GraphPageHeader(
                                kind = GraphKind.ARCH,
                                repo = "engine",
                                rendering = false,
                                onRefresh = {},
                                onBack = {},
                                onOpenExternal = {},
                                status = status,
                                onDismissStatus = status?.let { {} },
                            )
                        }
                    }
                }
            }
            waitForIdle()
            block()
        }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun narrowHeaderKeepsTitleOnOneLineAndDropsSubtitle() = header(730.dp, GraphReceipt(ok = true, text = "已复用持久化渲染（第 3 版）")) {
        // 标题仍在、且是横向排开的（一个字的宽度远不到 48dp）
        onNodeWithText("架构图").assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(20.dp)
        // 副标题让位
        onNodeWithText(subtitleOf("engine", GraphKind.ARCH), substring = true).assertDoesNotExist()
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun narrowHeaderWithoutReceiptStillShowsAllButtons() = header(730.dp, null) {
        onNodeWithText("架构图").assertWidthIsAtLeast(48.dp)
        // 没有回执时三个按钮都在（回执块的花括号曾把按钮吞进去：status 为 null 时按钮整排消失）
        onNodeWithText(L10n.t("toolbar.refresh")).assertExists()
        onNodeWithText(L10n.t("cmp.graph.backToRepo")).assertExists()
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun wideHeaderShowsSubtitle() = header(1040.dp, GraphReceipt(ok = true, text = "已复用持久化渲染（第 3 版）")) {
        onNodeWithText("架构图").assertWidthIsAtLeast(48.dp)
        onNodeWithText(subtitleOf("engine", GraphKind.ARCH), substring = true).assertExists()
    }
}
