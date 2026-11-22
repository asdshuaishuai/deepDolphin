// MilestonesView.kt —— 里程碑页（C9）：列表 + 新建表单 + 行内动作（破坏动作过确认）。
//
// 【确认纪律】删除/放弃必过确认框（引擎不留备份）；达成/重开不进确认集合（防确认疲劳）。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import deepdolphin.engine.Milestone
import deepdolphin.ui.Palette
import deepdolphin.ui.Space
import deepdolphin.ui.Type

/** 确认弹窗（Modal：焦点在主按钮、Esc 关闭）。 */
@Composable
fun ConfirmDialog(title: String, body: String, confirmLabel: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    Box(
        Modifier.fillMaxSize().background(Color(0x88000000)).clickable(enabled = false) {},
        contentAlignment = Alignment.Center,
    ) {
        GlassCard(Modifier.width(460.dp)) {
            Text(title, style = Type.section)
            Spacer(Modifier.height(Space.sm))
            Text(body, style = Type.body.copy(color = Palette.TextSecondary))
            Spacer(Modifier.height(Space.lg))
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm), modifier = Modifier.align(Alignment.End)) {
                Text(
                    "取消", style = Type.body,
                    color = Palette.TextSecondary,
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable { onDismiss() }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                )
                Text(
                    confirmLabel, style = Type.body.copy(fontWeight = FontWeight.Bold),
                    color = Color.White,
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(Palette.Red)
                        .clickable { onConfirm() }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
    }
}

@Composable
fun ActionText(label: String, color: Color, enabled: Boolean = true, onClick: () -> Unit) {
    Text(
        label, style = Type.body.copy(fontWeight = FontWeight.Medium),
        color = if (enabled) color else color.copy(alpha = 0.4f),
        modifier = Modifier.clip(RoundedCornerShape(6.dp)).clickable(enabled = enabled) { onClick() }
            .padding(horizontal = 10.dp, vertical = 4.dp),
    )
}

@Composable
fun MilestonesPage(model: AppModel) {
    val ms by model.milestones.collectAsState()
    val msState by model.msState.collectAsState()
    val status by model.status.collectAsState()
    val busyAction by model.busyAction.collectAsState()
    val projects = status?.projects.orEmpty().filter { it.isReadable }

    var showForm by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf<Pair<String, String>?>(null) } // (project, name) 待删除
    var confirmDrop by remember { mutableStateOf<Pair<String, String>?>(null) } // 待放弃

    // 新建表单草稿
    var fProject by remember { mutableStateOf("") }
    var fName by remember { mutableStateOf("") }
    var fTag by remember { mutableStateOf("") }
    var fDate by remember { mutableStateOf("") }
    var fDesc by remember { mutableStateOf("") }
    var formError by remember { mutableStateOf<String?>(null) }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState())
            .padding(horizontal = Space.xl, vertical = Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.lg),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("里程碑", style = Type.title)
                Spacer(Modifier.height(4.dp))
                Text("${ms?.readCount ?: 0} 条 · 存储健康度 ${ms?.storeHealth ?: "?"}", style = Type.label)
            }
            Button(
                onClick = { showForm = !showForm },
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
            ) { Text(if (showForm) "收起表单" else "新建里程碑") }
        }

        // ── 新建表单（卡片化 + 收起 + 项目下拉）──
        if (showForm) {
            GlassCard(Modifier.fillMaxWidth()) {
                Text("新建里程碑", style = Type.section)
                Spacer(Modifier.height(Space.md))
                Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                    // 项目下拉（Dropdown 用 Row+菜单近似：批 3 换 ExposedDropdownMenuBox）
                    Column {
                        Text("项目", style = Type.micro)
                        var open by remember { mutableStateOf(false) }
                        Box {
                            Text(
                                fProject.ifBlank { "选择项目" },
                                style = Type.body,
                                color = if (fProject.isBlank()) Palette.TextSecondary else Palette.TextPrimary,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp)).background(Palette.BgDeep)
                                    .clickable { open = !open }
                                    .padding(horizontal = 12.dp, vertical = 8.dp).width(160.dp),
                            )
                            if (open) {
                                Column(
                                    Modifier.width(220.dp).clip(RoundedCornerShape(8.dp))
                                        .background(Palette.BgDeep).padding(Space.xs)
                                ) {
                                    projects.forEach { p ->
                                        Text(
                                            p.name, style = Type.body,
                                            modifier = Modifier.fillMaxWidth()
                                                .clickable { fProject = p.name; open = false }
                                                .padding(horizontal = 10.dp, vertical = 6.dp),
                                        )
                                    }
                                }
                            }
                        }
                    }
                    LabeledField("名称", fName) { fName = it }
                    LabeledField("tag（可空，存在即自动达成）", fTag) { fTag = it }
                    LabeledField("目标日期 yyyy-MM-dd（可空）", fDate) { fDate = it }
                }
                Spacer(Modifier.height(Space.sm))
                LabeledField("描述（可空）", fDesc, singleLine = false) { fDesc = it }
                formError?.let {
                    Spacer(Modifier.height(Space.xs))
                    Text(it, style = Type.body.copy(color = Palette.Red))
                }
                Spacer(Modifier.height(Space.md))
                Button(
                    onClick = {
                        when {
                            fProject.isBlank() -> formError = "项目不能为空"
                            fName.isBlank() -> formError = "名称不能为空"
                            else -> {
                                formError = null
                                model.milestoneAdd(fProject, fName, fTag.ifBlank { null }, fDate.ifBlank { null }, fDesc.ifBlank { null })
                                fName = ""; fTag = ""; fDate = ""; fDesc = ""
                                showForm = false
                            }
                        }
                    },
                    enabled = !busyAction,
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
                ) { Text("创建") }
            }
        }

        when (val st = msState) {
            is LoadState.Failed -> GlassCard(Modifier.fillMaxWidth()) {
                Text("里程碑读不出来", style = Type.section.copy(color = Palette.Amber))
                Text(st.reason, style = Type.body.copy(color = Palette.TextSecondary))
            }
            else -> {
                val items = ms?.milestones.orEmpty()
                if (items.isEmpty()) GlassCard(Modifier.fillMaxWidth()) {
                    Text("还没有里程碑", style = Type.body.copy(color = Palette.TextSecondary))
                    Text("用上面的表单新建一条", style = Type.micro)
                }
                items.forEach { m ->
                    MilestoneRow(
                        m = m,
                        busy = busyAction,
                        onDone = { model.milestoneAction(m.projectId, m.name, "done") },
                        onReopen = { model.milestoneAction(m.projectId, m.name, "reopen") },
                        onDrop = { confirmDrop = m.projectId to m.name },
                        onRemove = { confirm = m.projectId to m.name },
                    )
                }
                // 孤儿披露
                ms?.orphaned.orEmpty().takeIf { it.isNotEmpty() }?.let { orphans ->
                    GlassCard(Modifier.fillMaxWidth()) {
                        Text("孤儿里程碑 ${orphans.size} 条（引用的项目不在注册表）", style = Type.micro.copy(color = Palette.Amber))
                    }
                }
            }
        }
    }

    // 确认弹窗（破坏动作唯一红门）
    confirm?.let { (proj, name) ->
        ConfirmDialog(
            title = "删除里程碑",
            body = "「$name」（$proj）将被删除。引擎不留备份、没有回收站、无法恢复。",
            confirmLabel = "删除",
            onConfirm = { model.milestoneRemove(proj, name); confirm = null },
            onDismiss = { confirm = null },
        )
    }
    confirmDrop?.let { (proj, name) ->
        ConfirmDialog(
            title = "放弃里程碑",
            body = "「$name」（$proj）将标记为放弃。此操作不删数据，但会改变统计口径。",
            confirmLabel = "放弃",
            onConfirm = { model.milestoneAction(proj, name, "drop"); confirmDrop = null },
            onDismiss = { confirmDrop = null },
        )
    }
}

@Composable
private fun LabeledField(label: String, value: String, singleLine: Boolean = true, onChange: (String) -> Unit) {
    Column {
        Text(label, style = Type.micro)
        androidx.compose.material3.OutlinedTextField(
            value = value,
            onValueChange = onChange,
            singleLine = singleLine,
            modifier = Modifier.width(220.dp),
            textStyle = Type.body,
        )
    }
}

@Composable
private fun MilestoneRow(
    m: Milestone, busy: Boolean,
    onDone: () -> Unit, onReopen: () -> Unit, onDrop: () -> Unit, onRemove: () -> Unit,
) {
    GlassCard(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(m.name, style = Type.card.copy(fontWeight = FontWeight.Bold))
                    Spacer(Modifier.width(Space.sm))
                    when (m.status) {
                        "open" -> Pill("进行中", Palette.Accent)
                        "done" -> Pill("已达成", Palette.Green)
                        "dropped" -> Pill("已放弃", Palette.TextSecondary)
                        else -> Pill("未知", Palette.Amber)
                    }
                    Spacer(Modifier.width(Space.sm))
                    Text(m.projectId, style = Type.micro)
                }
                Spacer(Modifier.height(2.dp))
                val meta = buildList {
                    if (m.tag.isNotBlank()) add("tag ${m.tag}")
                    if (m.targetDate.isNotBlank()) add("目标 ${m.targetDate}")
                    if (m.doneAt?.isNotBlank() == true) add("达成于 ${m.doneAt}")
                }
                if (meta.isNotEmpty()) Text(meta.joinToString(" · "), style = Type.micro)
                m.description?.takeIf { it.isNotBlank() }?.let {
                    Text(it, style = Type.body.copy(color = Palette.TextSecondary), maxLines = 2)
                }
            }
            // 前动作紧邻信息列；破坏对靠右成组（UI 精修纪律）
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                when (m.status) {
                    "open", null, "unknown" -> ActionText("达成", Palette.Green, enabled = !busy, onClick = onDone)
                    "done" -> ActionText("重开", Palette.Accent, enabled = !busy, onClick = onReopen)
                }
                Spacer(Modifier.width(Space.sm))
                ActionText("放弃", Palette.TextSecondary, enabled = !busy, onClick = onDrop)
                ActionText("删除", Palette.Red, enabled = !busy, onClick = onRemove)
            }
        }
    }
}
