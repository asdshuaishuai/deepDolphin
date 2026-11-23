// ScanSheet.kt —— 扫描单（mac ScanSheet.swift 的 Compose 对位；挂点=仪表盘 hero「扫描/添加」，
// 对位 mac PanelView.swift:92-94 的 .sheet(showScan)）。
//
// 职责切分对位 mac：路径判定是纯函数（mac PathInput 的对位，磁盘探查以 classifier 注入
// 可单测），这里只负责取值与呈现。扫描结果**逐项目如实列出**：引擎 scan payload 的
// candidates 不带「新增/已在册」归属标记（真机实测，fixtures/scan.json 锚定），只有聚合数
// added/existing——逐项目归属由客户端对照**扫描前**在册路径集推导（两份引擎事实的推导，
// 不发明）；聚合行仍以引擎口径为准。
//
// 【边界，如实】mac 的「选择…」目录面板与拖放回填不做（Compose Desktop 目录选择器
// 走 AWT FileDialog，本批先收在纯表单口径）；扫描参数形态以本机引擎实测为准：
// `moongit scan <根目录> --depth N`（--help 实测；无其他必填参数）。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import deepdolphin.engine.ScanCandidate
import deepdolphin.engine.ScanPayload

// ── 路径判定（mac PathInput 对位；三态不压成 Bool——「不存在」和「是文件」是两句不同的话）──

enum class PathKind { MISSING, FILE, DIRECTORY }

/** 路径的问题一句话；没有问题 = null（不返回空串——空串会拼出残缺的话，mac 同款纪律）。 */
fun scanRootProblem(raw: String, kind: PathKind): String? = when {
    raw.isBlank() -> "路径还没填"
    kind == PathKind.MISSING -> "路径不存在（先确认拼对了没有）"
    kind == PathKind.FILE -> "这是文件，不是目录（这里要目录）"
    else -> null
}

/** 整备后的可用目录路径；不可用 = null（提交按钮的可用性挂在这里，不打「发了才知道」的回环）。 */
fun prepareScanRoot(raw: String, classifier: (String) -> PathKind): String? {
    val t = raw.trim()
    return if (t.isNotEmpty() && classifier(t) == PathKind.DIRECTORY) t else null
}

// ── 逐项目结论（引擎聚合数 + 客户端在册集对照的推导）──

/** 一行扫描结论：existing=true 已在册（引擎没重复注册）；false 新增成功。 */
data class ScanRow(val name: String, val path: String, val existing: Boolean)

/** 候选 × 扫描前在册路径集 → 逐项目归属。路径比较容忍尾斜杠（两侧都 trimEnd）。 */
fun scanRows(candidates: List<ScanCandidate>, registeredPaths: Set<String>): List<ScanRow> =
    candidates.map { ScanRow(it.name, it.path, it.path.trimEnd('/') in registeredPaths) }

// ── 覆盖度披露（mac ScanCoverage.note 对位：三种「没看完」分开说；found=0 且没扫完时
//    不许替引擎断言「这棵树里没有」——引擎只验证过已访问的那部分）──

fun scanCoverageNote(found: Long, truncated: Boolean?, depthCapped: Boolean?, unreadableCount: Int): String? {
    val why = buildList {
        if (depthCapped == true) add("撞到扫描深度上限，下面还有目录没看")
        if (truncated == true) add("撞到目录数量上限")
        if (unreadableCount > 0) add("$unreadableCount 个目录读不出来（无权限或 I/O 错误）")
    }
    if (why.isEmpty()) return null
    return if (found == 0L) {
        "本次未扫完（${why.joinToString("，")}）——「共发现 0 个」只代表已访问的那部分里没有，不是这棵树里没有"
    } else {
        "本次未扫完（${why.joinToString("，")}）——上面列出的不是全部"
    }
}

/** 引擎口径聚合行（含覆盖度披露与「没有 git 仓库」的成立判定——只在真的扫完时才许说）。 */
fun scanAggregateLine(r: ScanPayload): String = buildString {
    append("发现 ${r.found} · 新增 ${r.added} · 已在册 ${r.existing} · 访问目录 ${r.dirsVisited}")
    val note = scanCoverageNote(r.found, r.truncated, r.depthCapped, r.unreadable.size)
    if (r.found == 0L && note == null) append(" —— 该目录树里没有 git 仓库")
    note?.let {
        append("\n")
        append(it)
    }
}

// ── 扫描单（sheet 形态对位 mac：模式切换 + 表单 + 逐项目结果 + 失败原因）──

@Composable
fun ScanSheet(model: AppModel, initialSingle: Boolean) {
    var single by remember { mutableStateOf(initialSingle) }
    var path by remember { mutableStateOf(System.getProperty("user.home") ?: "") }
    var name by remember { mutableStateOf("") }
    var depth by remember { mutableStateOf("2") } // mac Stepper 默认 2、范围 1...6，同款默认
    val busy by model.busyAction.collectAsState()
    val outcome by model.scanOutcome.collectAsState()
    val lastResult by model.lastResult.collectAsState()

    fun classify(p: String): PathKind = when {
        !java.io.File(p).exists() -> PathKind.MISSING
        java.io.File(p).isDirectory -> PathKind.DIRECTORY
        else -> PathKind.FILE
    }

    val preparedPath = prepareScanRoot(path) { classify(it) }
    val pathProblem = scanRootProblem(path, classify(path.trim()))
    val depthInt = depth.trim().toIntOrNull()
    val depthProblem = if (single) null else if (depthInt == null || depthInt !in 1..6) "深度要 1–6 的整数" else null
    val canRun = !busy && preparedPath != null && depthProblem == null

    Dialog(
        onDismissRequest = { model.closeScanSheet() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            Modifier
                .fillMaxWidth(0.46f)
                .fillMaxHeight(0.7f)
                .clip(RoundedCornerShape(Radius.card))
                .background(Palette.Card)
                .border(1.dp, Palette.Stroke, RoundedCornerShape(Radius.card))
                .padding(Space.lg),
            verticalArrangement = Arrangement.spacedBy(Space.md),
        ) {
            // ── 标题 + 模式切换（mac segmented Picker 对位：scan.tab.single / scan.tab.batch）──
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(if (single) "添加项目" else "批量扫描", style = Type.title)
                    Text(
                        if (single) "注册单个项目路径（名称可空）" else "扫一个根目录，把发现的仓库注册进来",
                        style = Type.label,
                    )
                }
                ScanModeTab("单个添加", selected = single) { single = true }
                Spacer(Modifier.width(Space.xs))
                ScanModeTab("批量扫描", selected = !single) { single = false }
            }

            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(Space.sm),
            ) {
                // ── 表单（单个：路径+名称；批量：根目录+深度）──
                OutlinedTextField(
                    value = path,
                    onValueChange = { path = it },
                    placeholder = {
                        Text(if (single) "项目路径（git 仓库目录）" else "扫描根目录（如 ~/code）", style = Type.micro)
                    },
                    singleLine = true,
                    textStyle = Type.body,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (single) {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        placeholder = { Text("名称（可空，默认取目录名）", style = Type.micro) },
                        singleLine = true,
                        textStyle = Type.body,
                        modifier = Modifier.fillMaxWidth(),
                    )
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                        OutlinedTextField(
                            value = depth,
                            onValueChange = { depth = it },
                            placeholder = { Text("深度", style = Type.micro) },
                            singleLine = true,
                            textStyle = Type.body,
                            modifier = Modifier.width(90.dp),
                        )
                        Text("扫描深度 1–6（默认 2）", style = Type.micro)
                    }
                }
                pathProblem?.let { Text("⚠ $it", style = Type.micro.copy(color = Palette.Amber)) }
                depthProblem?.let { Text("⚠ $it", style = Type.micro.copy(color = Palette.Amber)) }

                // ── 结果：批量=逐项目行+聚合行；单个=操作结果一行 ──
                if (!single) {
                    val oc = outcome
                    if (oc == null) {
                        Text("还没跑过扫描", style = Type.body.copy(color = Palette.TextSecondary))
                    } else if (oc.error != null) {
                        Text("扫描失败：${oc.error}", style = Type.body.copy(color = Palette.Red))
                    } else {
                        Text("上次扫描 ${oc.root}（深度 ${oc.depth}）：", style = Type.label)
                        if (oc.rows.isEmpty()) {
                            Text("引擎没有发现任何仓库", style = Type.body.copy(color = Palette.TextSecondary))
                        } else {
                            oc.rows.forEach { row ->
                                Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Pill(if (row.existing) "已在册" else "新增", if (row.existing) Palette.TextSecondary else Palette.Green)
                                    Spacer(Modifier.width(Space.sm))
                                    Text(row.name, style = Type.body, modifier = Modifier.width(130.dp), maxLines = 1)
                                    Text(row.path, style = Type.micro, maxLines = 1, modifier = Modifier.weight(1f))
                                }
                            }
                        }
                        // 聚合行按行渲染：首行引擎口径计数，其余是覆盖度披露（amber）
                        oc.aggregate.lines().forEachIndexed { i, line ->
                            Text(
                                line,
                                style = Type.micro,
                                color = if (i == 0) Palette.TextSecondary else Palette.Amber,
                            )
                        }
                        // 推导与引擎聚合分叉时兜底披露（以引擎为准）
                        val derivedNew = oc.rows.count { !it.existing }
                        val derivedExisting = oc.rows.count { it.existing }
                        if (derivedNew.toLong() != extractCount(oc.aggregate, "新增") ||
                            derivedExisting.toLong() != extractCount(oc.aggregate, "已在册")
                        ) {
                            Text(
                                "逐项目判定（新增 $derivedNew · 已在册 $derivedExisting）与引擎聚合数不一致，以引擎聚合为准（扫描期间注册表可能被并发改动）",
                                style = Type.micro.copy(color = Palette.Amber),
                            )
                        }
                    }
                } else {
                    lastResult?.let { Text(it, style = Type.body.copy(color = Palette.TextSecondary), maxLines = 3) }
                }
            }

            // ── 底部按钮（mac common.cancel + scan.add/scan.run 对位）──
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm), verticalAlignment = Alignment.CenterVertically) {
                Spacer(Modifier.weight(1f))
                Button(
                    onClick = { model.closeScanSheet() },
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Palette.CardHover,
                        contentColor = Palette.TextPrimary,
                    ),
                ) { Text("关闭") }
                Button(
                    onClick = {
                        val p = preparedPath ?: return@Button
                        if (single) {
                            model.addProjectPath(p, name.trim().takeIf { it.isNotEmpty() })
                        } else {
                            model.scanProjects(p, depthInt ?: 2)
                        }
                    },
                    enabled = canRun,
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Palette.Accent,
                        contentColor = Color.White,
                    ),
                ) { Text(if (busy) "进行中…" else if (single) "添加" else "开始扫描") }
            }
        }
    }
}

/** 从聚合首行抠计数（「发现 3 · 新增 1 · 已在册 2 · 访问目录 5」→ 新增=1）；仅用于分叉兜底披露。 */
private fun extractCount(aggregate: String, label: String): Long =
    Regex("$label (\\d+)").find(aggregate)?.groupValues?.get(1)?.toLongOrNull() ?: -1L

/** 模式切换胶囊（mac segmented picker 的近似：选中 accent 底、未选中描边）。 */
@Composable
private fun ScanModeTab(label: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        label,
        style = Type.micro.copy(fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal),
        color = if (selected) Color.White else Palette.TextSecondary,
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(if (selected) Palette.Accent else Color.Transparent)
            .border(1.dp, if (selected) Palette.Accent else Palette.Stroke, RoundedCornerShape(999.dp))
            .clickable { onClick() }
            .padding(horizontal = 10.dp, vertical = 4.dp),
    )
}
