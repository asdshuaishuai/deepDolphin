// QuickView.kt —— 托盘速览窗（mac BarView.swift MenuBarExtra .window 弹窗的 Compose 对位）。
//
// 【形态对位】380px 宽小窗（Dialog）：头部（标题 + 摘要行 + 刷新）→ 项目行区（逐项目
// 一行：名 + 状态词 + 最后提交）→ footer（打开主面板 / 退出）。
//
// 【三态对位（mac BarView.swift:22-27）】引擎断供时：
//   · 引擎缺席（探活失败）→ missing-engine 态（说明 + 重检测入口在主窗口）；
//   · 项目列表空 + 有错误 → empty-or-error 态（错误原文 + 重试）；
//   · 项目列表空 + 无错误 → 空态（「暂无已注册项目」+ 扫描引导）。
// 「空」与「错」是两句话，不许合成一句。
//
// 【行数上限】对位 mac projectRows.prefix(12)：弹窗高度由屏幕约束，超过 12 个项目
// 给「还有 N 个项目，打开面板查看…」引导（mac 注释：MenuBarExtra 里 ScrollView 会
// 塌缩成 0 高——平铺不滚动）。
//
// 【与 mac 的差异，如实标注】mac MenuProjectRow 有迷你进度条（pendingCommits 线性
// 进度）与速览内批量更新确认框（pendingBulk）；本窗按任务口径收在「名 + 状态词 +
// 最后提交」一行 + footer 两钮——批量更新的确认/结果都在主窗口（WorkBar 双轨按钮
// 触发），不在速览窗里另造一份入口（同一动作两处措辞会分叉，mac AgentBulkView.swift:3-8
// 删按钮的同款教训）。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import deepdolphin.engine.Project
import deepdolphin.sysint.TrayQuickView

// ── 纯函数层（判据见 QuickViewTest）──

/**
 * 项目行的副行（mac MenuProjectRow.subtitle 对位；CMP 的 Project 没有 pulseLine 字段，
 * 如实按有的字段来）：错误原文 → 分支「多久前 · 状态词」→ 最后提交多久前 → 非 git →
 * 读不出来。错误行由调用方染红。
 */
fun quickRowSubtitle(p: Project): String {
    p.error?.let { return it }
    val b = p.primaryBranch
    if (b != null && b.headAgo.isNotBlank()) {
        return "${b.headAgo} · ${b.statusLabel.ifBlank { b.status }}"
    }
    if (!p.lastCommitAgo.isNullOrBlank()) return p.lastCommitAgo
    if (!p.isGit) return L10n.t("bar.notGit")
    return L10n.t("cmp.quick.lastCommitNA")
}

/**
 * 行状态点的语义色（mac StatusDot → DSColor.color(DSStatus.from(status)) 的 liveness 对位；
 * 全部取设计令牌，不内联色值）。
 */
fun quickRowTint(l: Liveness): Color = when (l) {
    Liveness.UNREADABLE -> Palette.Red
    Liveness.NOT_GIT, Liveness.UNKNOWN -> Palette.TextTertiary
    Liveness.NEEDS_ACTION -> Palette.Amber
    Liveness.ENGINE_STALE, Liveness.QUIET -> Palette.Yellow
    Liveness.RECENT -> Palette.Green
}

/** 行数上限（mac prefix(12) 对位）。 */
const val QUICK_VIEW_ROW_CAP = 12

/** 超出部分的引导行（mac bar.moreProjects「还有 %d 个项目，打开面板查看…」对位）。 */
fun quickViewMoreLine(total: Int): String? =
    if (total > QUICK_VIEW_ROW_CAP) L10n.t("bar.moreProjects", total - QUICK_VIEW_ROW_CAP) else null

// ── 速览窗 ──

/**
 * @param model null = 引擎缺席（missing-engine 三态；主窗口正显示重检测页）
 * @param onOpenPanel 打开主面板（置前；路由跳转由本窗内各入口自理）
 * @param onQuit 退出应用（mac NSApp.terminate 对位）
 */
@Composable
fun QuickViewDialog(
    model: AppModel?,
    onOpenPanel: () -> Unit,
    onQuit: () -> Unit,
    onDismiss: () -> Unit,
    onRedetect: () -> Unit,
) {
    if (model == null) {
        // missing-engine 态（mac BarView.swift:96-111 对位）：说明 + 重检测；
        // 摘要行如实说引擎缺席（不挂「还没有项目」——那是另一句事实）
        Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            QuickViewShell {
                Text("⚠ " + L10n.t("bar.noEngine"), style = Type.section, modifier = Modifier.padding(horizontal = Space.md, vertical = Space.sm))
                Text(
                    L10n.t("cmp.quick.noEngineHint"),
                    style = Type.label,
                    color = Palette.TextSecondary,
                    modifier = Modifier.padding(horizontal = Space.md),
                )
                Button(
                    onClick = onRedetect,
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.CardHover, contentColor = Palette.TextPrimary),
                    modifier = Modifier.padding(horizontal = Space.md, vertical = Space.xs),
                ) { Text(L10n.t("bar.redetect")) }
                QuickViewFooter(onOpenPanel = onOpenPanel, onQuit = onQuit)
            }
        }
        return
    }
    val status by model.status.collectAsState()
    val statusState by model.statusState.collectAsState()
    val refreshing by model.refreshing.collectAsState()
    val lastError by model.lastError.collectAsState()
    val projects = status?.projects.orEmpty()
    val summary = status?.let { TrayQuickView.summaryLine(it.projects.size, it.summary.dirtyProjects) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        QuickViewShell {
            // ── 头部：标题 + 摘要行 + 刷新（mac header 对位）──
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(horizontal = Space.md),
            ) {
                Text(L10n.t("bar.title"), style = Type.title, modifier = Modifier.weight(1f, fill = false))
                summary?.let {
                    Spacer(Modifier.width(Space.sm))
                    Text(it, style = Type.label, color = Palette.TextSecondary, maxLines = 1)
                }
                Spacer(Modifier.weight(1f))
                if (refreshing) {
                    CircularProgressIndicator(Modifier.size(12.dp), color = Palette.Accent, strokeWidth = 2.dp)
                    Spacer(Modifier.width(Space.xs))
                }
                IconButton(FluentIcon.ArrowSync, onClick = { model.refreshAll() })
            }
            Spacer(Modifier.height(Space.xs))
            Box(Modifier.fillMaxWidth().height(1.dp).background(Palette.Stroke))

            // ── 项目行区三态（mac missing-engine / empty-or-error / projectRows 对位）──
            if (projects.isEmpty() && statusState !is LoadState.Loading && lastError == null && status != null) {
                // 空态（引擎到了、读完、真的没有项目）
                Column(Modifier.padding(horizontal = Space.md, vertical = Space.sm), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                    Text(L10n.t("panel.empty.projects"), style = Type.body.copy(color = Palette.TextSecondary))
                    Text(L10n.t("panel.empty.scanHint"), style = Type.micro)
                }
            } else if (projects.isEmpty() && lastError != null) {
                // 错误态（读失败 ≠ 空）
                Column(Modifier.padding(horizontal = Space.md, vertical = Space.sm), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                    Text("⚠ " + L10n.t("bar.engineError"), style = Type.section.copy(color = Palette.Red))
                    Text(lastError!!, style = Type.label, color = Palette.TextSecondary, maxLines = 3)
                    Button(
                        onClick = { model.refreshAll() },
                        shape = RoundedCornerShape(Radius.control),
                        colors = ButtonDefaults.buttonColors(containerColor = Palette.CardHover, contentColor = Palette.TextPrimary),
                    ) { Text(L10n.t("common.retry")) }
                }
            } else if (projects.isEmpty()) {
                // 读取中（引擎在跑第一次 status）
                Text(
                    L10n.t("bar.loading"),
                    style = Type.body.copy(color = Palette.TextSecondary),
                    modifier = Modifier.padding(horizontal = Space.md, vertical = Space.sm),
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    projects.take(QUICK_VIEW_ROW_CAP).forEach { p ->
                        QuickRow(p) {
                            model.goRoute(AppModel.Route.PROJECT, p.name)
                            onOpenPanel()
                            onDismiss()
                        }
                    }
                    quickViewMoreLine(projects.size)?.let {
                        Text(
                            it,
                            style = Type.label,
                            color = Palette.TextSecondary,
                            modifier = Modifier
                                .clip(RoundedCornerShape(Radius.control))
                                .clickable {
                                    model.goRoute(AppModel.Route.DASHBOARD)
                                    onOpenPanel()
                                    onDismiss()
                                }
                                .padding(horizontal = Space.md, vertical = Space.xs),
                        )
                    }
                }
            }

            Spacer(Modifier.height(Space.xs))
            Box(Modifier.fillMaxWidth().height(1.dp).background(Palette.Stroke))
            // ── footer：打开主面板 / 退出（mac footer 对位；任务口径两钮）──
            QuickViewFooter(
                onOpenPanel = {
                    model.goRoute(AppModel.Route.DASHBOARD)
                    onOpenPanel()
                    onDismiss()
                },
                onQuit = onQuit,
            )
        }
    }
}

/** 380px 外壳（mac BarView .frame(width: 380) 对位）。 */
@Composable
private fun QuickViewShell(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .width(380.dp)
            .skinShadow(Radius.card).clip(RoundedCornerShape(Radius.card))
.shadow(12.dp, RoundedCornerShape(Radius.card))
            .background(Palette.Card)
            .border(Material.borderWidth, Palette.Stroke, RoundedCornerShape(Radius.card))
            .padding(vertical = Space.sm),
        content = content,
    )
}

/** footer：打开主面板（accent 主钮）+ 退出（电源符）。 */
@Composable
private fun QuickViewFooter(onOpenPanel: () -> Unit, onQuit: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().padding(horizontal = Space.md, vertical = Space.xs),
    ) {
        Button(
            onClick = onOpenPanel,
            shape = RoundedCornerShape(Radius.control),
            colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Palette.OnAccent),
        ) { Text(L10n.t("bar.openPanel")) }
        Spacer(Modifier.weight(1f))
        IconButton(FluentIcon.Power, onClick = onQuit)
    }
}

/** 单项目行：状态点 + 名 + 未提交徽标 / 副行（错误红 / 状态词+最后提交）。 */
@Composable
private fun QuickRow(p: Project, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.control))
            .clickable(enabled = p.isReadable, onClick = onClick)
            .padding(horizontal = Space.md, vertical = 5.dp),
    ) {
        Box(Modifier.size(8.dp).background(quickRowTint(livenessOf(p)), CircleShape))
        Spacer(Modifier.width(Space.sm))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(p.name, style = Type.body, fontWeight = FontWeight.Medium, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                if ((p.userDirtyCount ?: 0) > 0) {
                    Spacer(Modifier.width(Space.xs))
                    Text("●${p.userDirtyCount}", style = Type.micro, color = Palette.Amber)
                }
            }
            Text(
                quickRowSubtitle(p),
                style = Type.micro,
                color = if (p.error != null) Palette.Red else Palette.TextSecondary,
                maxLines = 1,
            )
        }
        Spacer(Modifier.width(Space.sm))
        Text(stateWordOf(livenessOf(p)), style = Type.label, color = Palette.TextSecondary)
    }
}
