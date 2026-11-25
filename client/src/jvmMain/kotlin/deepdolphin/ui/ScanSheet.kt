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
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import deepdolphin.engine.ScanCandidate
import deepdolphin.engine.ScanPayload
import androidx.compose.foundation.layout.PaddingValues

// ── 路径判定（mac PathInput 对位；三态不压成 Bool——「不存在」和「是文件」是两句不同的话）──

enum class PathKind { MISSING, FILE, DIRECTORY }

/** 路径的问题一句话；没有问题 = null（不返回空串——空串会拼出残缺的话，mac 同款纪律）。 */
fun scanRootProblem(raw: String, kind: PathKind): String? = when {
    raw.isBlank() -> L10n.t("cmp.scan.pathEmpty")
    kind == PathKind.MISSING -> L10n.t("cmp.scan.pathMissing")
    kind == PathKind.FILE -> L10n.t("cmp.scan.pathIsFile")
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
    // 事实层分隔符随语言（zh 系全角逗号、en/ja 半角——usesEnglishFacts 同口径）
    val sep = if (L10n.language.usesEnglishFacts) ", " else "，"
    val why = buildList {
        if (depthCapped == true) add(L10n.t("cmp.scan.depthCapped"))
        if (truncated == true) add(L10n.t("cmp.scan.dirCapped"))
        if (unreadableCount > 0) add(L10n.t("cmp.scan.unreadableDirs", unreadableCount))
    }
    if (why.isEmpty()) return null
    return if (found == 0L) {
        L10n.t("cmp.scan.incompleteNoRepos", why.joinToString(sep))
    } else {
        L10n.t("cmp.scan.incompletePartial", why.joinToString(sep))
    }
}

/** 引擎口径聚合行（含覆盖度披露与「没有 git 仓库」的成立判定——只在真的扫完时才许说）。 */
fun scanAggregateLine(r: ScanPayload): String = buildString {
    append(L10n.t("cmp.scan.aggregateLine", r.found, r.added, r.existing, r.dirsVisited))
    val note = scanCoverageNote(r.found, r.truncated, r.depthCapped, r.unreadable.size)
    if (r.found == 0L && note == null) append(L10n.t("scan.none.found"))
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
    val depthProblem = if (single) null else if (depthInt == null || depthInt !in 1..6) L10n.t("cmp.scan.depthRange") else null
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
.shadow(12.dp, RoundedCornerShape(Radius.card))
                .background(Palette.Card)
                .border(Material.borderWidth, Palette.Stroke, RoundedCornerShape(Radius.card))
                .padding(Space.lg),
            verticalArrangement = Arrangement.spacedBy(Space.md),
        ) {
            // ── 标题 + 模式切换（mac segmented Picker 对位：scan.tab.single / scan.tab.batch）──
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(if (single) L10n.t("scan.tab.single") else L10n.t("scan.tab.batch"), style = Type.title)
                    Text(
                        if (single) L10n.t("cmp.scan.singleSubtitle") else L10n.t("cmp.scan.batchSubtitle"),
                        style = Type.label,
                    )
                }
                ScanModeTab(L10n.t("cmp.scan.singleTab"), selected = single) { single = true }
                Spacer(Modifier.width(Space.xs))
                ScanModeTab(L10n.t("scan.tab.batch"), selected = !single) { single = false }
            }

            ScrollColumn(
                Modifier.weight(1f).fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(Space.sm),
            ) {
                // ── 表单（单个：路径+名称；批量：根目录+深度）──
                OutlinedTextField(
                    colors = fluentTextFieldColors(),
                    value = path,
                    onValueChange = { path = it },
                    placeholder = {
                        Text(if (single) L10n.t("cmp.scan.pathLabel") else L10n.t("cmp.scan.rootLabel"), style = Type.micro)
                    },
                    singleLine = true,
                    textStyle = Type.body,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (single) {
                    OutlinedTextField(
                        colors = fluentTextFieldColors(),
                        value = name,
                        onValueChange = { name = it },
                        placeholder = { Text(L10n.t("cmp.scan.nameOptional"), style = Type.micro) },
                        singleLine = true,
                        textStyle = Type.body,
                        modifier = Modifier.fillMaxWidth(),
                    )
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                        OutlinedTextField(
                            colors = fluentTextFieldColors(),
                            value = depth,
                            onValueChange = { depth = it },
                            placeholder = { Text(L10n.t("bulk.deepWord"), style = Type.micro) },
                            singleLine = true,
                            textStyle = Type.body,
                            modifier = Modifier.width(90.dp),
                        )
                        Text(L10n.t("cmp.scan.depthLabel"), style = Type.micro)
                    }
                }
                pathProblem?.let { Text("⚠ $it", style = Type.micro.copy(color = Palette.Amber)) }
                depthProblem?.let { Text("⚠ $it", style = Type.micro.copy(color = Palette.Amber)) }

                // ── 结果：批量=逐项目行+聚合行；单个=操作结果一行 ──
                if (!single) {
                    val oc = outcome
                    if (oc == null) {
                        Text(L10n.t("cmp.scan.notRun"), style = Type.body.copy(color = Palette.TextSecondary))
                    } else if (oc.error != null) {
                        Text(L10n.t("cmp.scan.failedWith", oc.error ?: ""), style = Type.body.copy(color = Palette.Red))
                    } else {
                        Text(L10n.t("cmp.scan.lastRun", oc.root, oc.depth), style = Type.label)
                        if (oc.rows.isEmpty()) {
                            Text(L10n.t("cmp.scan.noneFound"), style = Type.body.copy(color = Palette.TextSecondary))
                        } else {
                            oc.rows.forEach { row ->
                                Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Pill(if (row.existing) L10n.t("cmp.scan.existing") else L10n.t("gitop.kind.added"), if (row.existing) Palette.TextSecondary else Palette.Green)
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
                        if (derivedNew.toLong() != extractCount(oc.aggregate, L10n.t("cmp.scan.addedLabel")) ||
                            derivedExisting.toLong() != extractCount(oc.aggregate, L10n.t("cmp.scan.existing"))
                        ) {
                            Text(
                                L10n.t("cmp.scan.tallyMismatch", derivedNew, derivedExisting),
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
                ) { Text(L10n.t("common.close")) }
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
                        contentColor = Palette.OnAccent,
                    ),
                ) { Text(if (busy) L10n.t("cmp.scan.busy") else if (single) L10n.t("scan.add") else L10n.t("cmp.scan.runBtn")) }
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
            .border(Material.borderWidth, if (selected) Palette.Accent else Palette.Stroke, RoundedCornerShape(999.dp))
            .clickable { onClick() }
            .padding(horizontal = 10.dp, vertical = 4.dp),
    )
}
