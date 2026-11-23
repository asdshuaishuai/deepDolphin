// ConfidencePages.kt —— 侧栏「视图」组两页：代码置信度 + 补丁置信度体检
//（mac GraphPages.swift 的 ConfidencePage / PatchCheckPage 对位）。
//
// 输出形状以真机引擎实测为准（fixtures/confidence/ 四份文件由本机 moongit 真跑落盘，
// 引擎源码 moonGit/src/graph/confidence_render.cj / patchconf_render.cj 同口径）：
//   · graph confidence <项目> --json → score/dimensions/penaltyByFile/findings/byKind/
//     astUsed/astNote/cappedKind/cappedTotal/filesAnalyzed/semantics
//   · graph confidence <项目> --llm → 纯文本提示词（非 JSON，直接可喂模型 → 剪贴板）
//   · graph patchconf <项目> --patch <diff文件> --json → Layer1（signals S1..S10 可 null）
//   · graph patchconf --merge <alg> <agent> --json → Layer3 终稿
// 【与 mac 注释的差异，如实标注】dimensions 无 detail 键（是 penalty+findings 条数）；
// 终稿无顶层 reviewed 键（在 diagnostics.reviewed_by_agent）；alerts 键集是
// {level, type, detail}（mac 读的 issue 键缺席，容两个键、issue 优先）。
//
// 【披露纪律】降级(astNote)/限流(capped*)/空分母(null 信号)/parse_errors 原样展示不静默；
// 低置信度实体默认只告知位置，点击才展开证据/diff 块（mac FindingDisclosureRow 同语义）。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import deepdolphin.engine.AgentPayload
import deepdolphin.engine.AgentVerdict
import deepdolphin.engine.ConfidenceReport
import deepdolphin.engine.ConfFinding
import deepdolphin.engine.Engine
import deepdolphin.engine.MergedAlert
import deepdolphin.engine.MergedConfidence
import deepdolphin.engine.PatchConfidence
import deepdolphin.engine.PatchEntity
import deepdolphin.engine.PatchUncertain
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.awt.Toolkit
import java.awt.datatransfer.StringSelection

// ── 纯函数（判据见 ConfidencePagesTest；阈值全部对位 mac 基准，不发明）──

/** 总分色：≥80 绿 / ≥50 橙 / 其余红（mac reportBody 同阈值）。 */
fun confidenceScoreColor(score: Long): Color =
    if (score >= 80) Palette.Green else if (score >= 50) Palette.Amber else Palette.Red

/** 补丁总体分色：≥0.8 绿 / ≥0.5 橙 / 其余红（mac finalCard/layer1Card 同阈值）。 */
fun patchOverallColor(overall: Double): Color =
    if (overall >= 0.8) Palette.Green else if (overall >= 0.5) Palette.Amber else Palette.Red

/** 实体分色：<0.5 红 / <0.75 橙 / 其余次级色（mac PatchEntityRow 同阈值）。 */
fun patchEntityColor(confidence: Double): Color =
    if (confidence < 0.5) Palette.Red else if (confidence < 0.75) Palette.Amber else Palette.TextSecondary

/** finding 权重越高 = 越不可信：≥8 红（孤儿/占位/吞错/重复体档）/ ≥5 橙 / 其余次级。 */
fun findingWeightColor(weight: Long): Color =
    if (weight >= 8) Palette.Red else if (weight >= 5) Palette.Amber else Palette.TextSecondary

/** 只看高权重疑点（mac highWeightOnly：weight ≥ 8 这一档；关着 = 引擎全序原样）。 */
fun highWeightFindings(fs: List<ConfFinding>, enabled: Boolean): List<ConfFinding> =
    if (!enabled) fs else fs.filter { it.weight >= 8 }

/** 低置信度补丁实体（< 0.75），升序——最不可信的排最前（mac lowConfidenceEntities 同语义）。 */
fun lowConfidencePatchEntities(ents: List<PatchEntity>): List<PatchEntity> =
    ents.filter { it.confidence < 0.75 }.sortedBy { it.confidence }

/** 人工裁决 → agent 载荷置信度（mac uncertainRow 的绑定映射：resolved 0.9 / unresolved 0.05 / 其余 0.5）。 */
fun verdictConfidence(verdict: String): Double = when (verdict) {
    "resolved" -> 0.9
    "unresolved" -> 0.05
    else -> 0.5
}

/** 裁决表 → Layer3 合并的 agent 输入（mac merge 的 items 构造对位）。 */
fun agentVerdictItems(verdicts: Map<String, String>): AgentPayload = AgentPayload(
    verdicts.map { (id, v) -> AgentVerdict(id, v, verdictConfidence(v), "deepDolphin 人工裁决") },
)

/** 信号 chip 文案：有值 = 百分比整数；null = 「—」（分母为 0，契约要求如实披露）。 */
fun signalChipLabel(key: String, value: Double?): String =
    if (value != null) "$key ${if (value >= 1) 100 else (value * 100).toInt()}" else "$key —"

/** 信号 chip 是否为 null 信号（次级色降档）。 */
fun isNullSignal(value: Double?): Boolean = value == null

/** 终稿警示行：[level] 名称 — 详情（issue 键优先、缺席回退实测的 type 键）。 */
fun alertLineText(a: MergedAlert): String =
    "[${a.level}] ${a.issue?.takeIf { it.isNotBlank() } ?: a.type} — ${a.detail}"

/** 从粘贴的 diff 文本里取「覆盖该文件该行」的 hunk 块（mac CodeSnippet.fromDiff 的位置定位部分）。
 *  行号口径 = 补丁后（新文件侧）；找不到 = null（调用方如实说「补丁未覆盖该位置」）。 */
fun extractDiffHunk(diffText: String, file: String, line: Long): String? {
    var currentFile: String? = null
    val lines = diffText.lines()
    var i = 0
    while (i < lines.size) {
        val plus = DIFF_PLUS_FILE.find(lines[i])
        if (plus != null) {
            currentFile = plus.groupValues[1].substringAfterLast('/')
            i++; continue
        }
        val hunk = DIFF_HUNK_HEAD.find(lines[i])
        if (hunk != null && currentFile == file.substringAfterLast('/')) {
            val newStart = hunk.groupValues[3].toLongOrNull() ?: 0L
            val newCount = hunk.groupValues[4].ifEmpty { "1" }.toLongOrNull() ?: 1L
            var j = i + 1
            while (j < lines.size && (lines[j].startsWith(" ") || lines[j].startsWith("+") ||
                    lines[j].startsWith("-") || lines[j].startsWith("\\"))) j++
            if (line >= newStart && line < newStart + maxOf(newCount, 1L)) {
                return lines.subList(i, j).joinToString("\n")
            }
            i = j; continue
        }
        i++
    }
    return null
}

private val DIFF_PLUS_FILE = Regex("""^\+\+\+ b/(.+)$""")
private val DIFF_HUNK_HEAD = Regex("""^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@""")

/** 读实码一行（findings 的 file 是仓库相对路径，需要项目绝对路径）；读不出 = null（如实披露）。 */
fun sourceLineAt(projectPath: String, file: String, line: Long): String? = runCatching {
    val f = File(projectPath, file)
    if (!f.isFile || line < 1) null
    else f.useLines { seq -> seq.drop((line - 1).toInt()).firstOrNull() }
}.getOrNull()

// ── 项目选择器（mac GraphProjectPicker 对位：两页共用）──

@Composable
fun GraphProjectPicker(names: List<String>, selected: String, onSelect: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clip(RoundedCornerShape(Radius.control))
                .background(Palette.BgDeep)
                .clickable { open = !open }
                .padding(horizontal = Space.md, vertical = Space.sm)
                .width(180.dp),
        ) {
            Text(
                selected.ifBlank { "选择项目" },
                style = Type.body,
                color = if (selected.isBlank()) Palette.TextSecondary else Palette.TextPrimary,
                maxLines = 1,
                modifier = Modifier.weight(1f),
            )
            Text("▾", style = Type.label, color = Palette.TextTertiary)
        }
        if (open) {
            Column(
                Modifier.width(196.dp).clip(RoundedCornerShape(Radius.control))
                    .background(Palette.Sidebar).padding(Space.xs)
            ) {
                names.forEach { n ->
                    Text(
                        n, style = Type.body,
                        color = if (n == selected) Palette.Accent else Palette.TextPrimary,
                        modifier = Modifier.fillMaxWidth()
                            .clip(RoundedCornerShape(Radius.chip))
                            .clickable { onSelect(n); open = false }
                            .padding(horizontal = Space.md, vertical = 6.dp),
                    )
                }
            }
        }
    }
}

// ── 置信度页（mac ConfidencePage：六维度总分 + 披露式 findings + LLM 提示词复制）──

@Stable
class ConfidencePageModel(private val engine: Engine) {
    var projectName by mutableStateOf("")
    var loading by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var report by mutableStateOf<ConfidenceReport?>(null)
        private set
    var promptCopied by mutableStateOf(false)
        private set
    /** 只看高权重疑点（权重 ≥ 8；mac highWeightOnly 对位）。 */
    var highWeightOnly by mutableStateOf(false)

    /** graph confidence --json（mac load 对位；fallback = 进页时还没选项目的默认取法）。 */
    suspend fun load(fallbackProject: String?) {
        if (projectName.isBlank()) projectName = fallbackProject ?: ""
        if (projectName.isBlank()) {
            error = "没有在册的可读项目"
            return
        }
        loading = true; error = null
        try {
            report = engine.graphConfidence(projectName)
        } catch (e: Exception) {
            error = e.message ?: e.javaClass.simpleName
        } finally {
            loading = false
        }
    }

    /** graph confidence --llm 纯文本 → AWT 剪贴板（mac copyPrompt 对位：复制态亮 2 秒）。 */
    suspend fun copyPrompt() {
        try {
            val prompt = engine.graphConfidencePrompt(projectName)
            // AWT 剪贴板必须在 EDT 上 setContents；本函数由 UI 协程（Main/swing）调用，
            // invokeLater 双保险不改语义。ClipboardOwner 传 null（不持有内容所有权）。
            java.awt.EventQueue.invokeLater {
                Toolkit.getDefaultToolkit().systemClipboard.setContents(StringSelection(prompt), null)
            }
            promptCopied = true
            delay(2000)
            promptCopied = false
        } catch (e: Exception) {
            error = e.message ?: e.javaClass.simpleName
        }
    }
}

@Composable
fun ConfidencePage(model: AppModel) {
    val status by model.status.collectAsState()
    val projects = status?.projects.orEmpty().filter { it.isReadable }
    val vm = remember { ConfidencePageModel(model.engine) }
    val scope = rememberCoroutineScope()
    // 进页自动体检一次（mac .task 对位：projectName 空时取第一个在册项目）
    LaunchedEffect(vm, projects.isNotEmpty()) {
        if (vm.report == null && !vm.loading && projects.isNotEmpty()) vm.load(projects.first().name)
    }

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Space.xl, vertical = Space.lg),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text("代码置信度", style = Type.title)
                Text(
                    "引擎六维度体检 · 权重降序疑点清单（结构性事实，不是正确性证明）",
                    style = Type.label,
                )
            }
            if (vm.loading) CircularProgressIndicator(Modifier.size(14.dp), color = Palette.Accent, strokeWidth = 2.dp)
        }
        // 工具条（mac 页头对位：选择器 + 体检 + 高权重开关 + 复制提示词）
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Space.xl),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.md),
        ) {
            GraphProjectPicker(projects.map { it.name }, vm.projectName) { vm.projectName = it }
            Button(
                onClick = { scope.launch { vm.load(null) } },
                enabled = !vm.loading && vm.projectName.isNotBlank(),
                shape = RoundedCornerShape(Radius.control),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
            ) { Text("分析") }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                Switch(checked = vm.highWeightOnly, onCheckedChange = { vm.highWeightOnly = it })
                Text("只看高权重（≥8）", style = Type.label)
            }
            Button(
                onClick = { scope.launch { vm.copyPrompt() } },
                enabled = vm.report != null && vm.projectName.isNotBlank(),
                shape = RoundedCornerShape(Radius.control),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.CardHover, contentColor = Palette.TextPrimary),
            ) { Text(if (vm.promptCopied) "已复制 ✓" else "复制 LLM 复核提示词") }
        }
        vm.error?.let {
            Text(
                it, style = Type.body.copy(color = Palette.Amber),
                modifier = Modifier.fillMaxWidth().padding(horizontal = Space.xl, vertical = Space.sm),
            )
        }
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = Space.xl, vertical = Space.lg),
            verticalArrangement = Arrangement.spacedBy(Space.md),
        ) {
            val r = vm.report
            if (r == null) {
                Text(
                    "选项目后点「分析」：引擎输出六维度总分与按权重降序的疑点清单",
                    style = Type.body.copy(color = Palette.TextSecondary),
                    modifier = Modifier.padding(top = Space.xl),
                )
            } else {
                ConfidenceReportBody(r, vm.highWeightOnly, projects.firstOrNull { it.name == vm.projectName }?.path ?: "")
            }
        }
    }
}

@Composable
private fun ConfidenceReportBody(r: ConfidenceReport, highWeightOnly: Boolean, projectPath: String) {
    // 总分 + 维度行（引擎只发有疑点的维度——有几个维度亮几个，不造假补齐）
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Space.lg)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("${r.score}", style = Type.display, color = confidenceScoreColor(r.score))
            Text("总分 / 100", style = Type.micro)
        }
        Column(verticalArrangement = Arrangement.spacedBy(Space.xs)) {
            if (r.dimensions.isEmpty()) {
                Text("引擎未报任何维度的疑点（分数 = 无结构性疑点）", style = Type.label)
            }
            r.dimensions.forEach { d -> DimensionRow(d.label, d.score, d.penalty, d.findings) }
        }
    }
    // 降级/限流披露必须原样展示（契约：不许静默）
    if (r.astNote.isNotBlank()) DisclosureBox(r.astNote)
    if (r.cappedTotal) DisclosureBox("⚠ 疑点已达全量上限——清单是子集，不是全部")
    else if (r.cappedKind) DisclosureBox("⚠ 部分类别达到每文件上限——超出该类的疑点已按类汇总")
    if (r.semantics.isNotBlank()) Text(r.semantics, style = Type.micro, color = Palette.TextTertiary)

    // findings：披露式行（收起 = 位置告知，点击 = 展开证据与实码）
    Text("疑点 ${r.findings.size} 条" + if (highWeightOnly) " · 高权重筛选后 ${highWeightFindings(r.findings, true).size} 条" else "", style = Type.section)
    Text("默认只告知位置；点击行展开引擎证据与实码。权重越高越不可信（≥8 = 红）。", style = Type.micro)
    val shown = highWeightFindings(r.findings, highWeightOnly)
    if (shown.isEmpty()) {
        Text(
            if (r.findings.isEmpty()) "快照里没有疑点" else "高权重筛选后没有匹配的疑点",
            style = Type.body.copy(color = Palette.TextSecondary),
        )
    }
    shown.forEach { f -> FindingDisclosureRow(f, projectPath) }
}

@Composable
private fun DimensionRow(label: String, score: Long, penalty: Long, findings: Long) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
        Text(label, style = Type.body, modifier = Modifier.width(170.dp))
        Box(
            Modifier.width(220.dp).height(6.dp)
                .clip(RoundedCornerShape(Radius.chip)).background(Palette.BarTrack)
        ) {
            Box(
                Modifier.fillMaxHeight().fillMaxWidth((score.coerceIn(0, 100) / 100f))
                    .clip(RoundedCornerShape(Radius.chip)).background(confidenceScoreColor(score)),
            )
        }
        Text("$score", style = Type.label.copy(fontFamily = FontFamily.Monospace), modifier = Modifier.width(28.dp))
        Text("罚分 $penalty · $findings 条", style = Type.micro)
    }
}

/** 披露条（降级/限流——引擎说什么就展示什么，不静默）。 */
@Composable
private fun DisclosureBox(text: String) {
    Text(
        text, style = Type.label.copy(color = Palette.TextSecondary),
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.control))
            .background(Palette.Card.copy(alpha = 0.55f)).padding(Space.sm),
    )
}

/** finding 披露行：收起 = [权重] 类别 位置（低置信度高亮）；展开 = 引擎证据 + 实码一行。 */
@Composable
private fun FindingDisclosureRow(f: ConfFinding, projectPath: String) {
    var expanded by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.control))
            .background(Palette.Card.copy(alpha = 0.55f)).padding(Space.sm),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.sm),
            modifier = Modifier.fillMaxWidth().clickable { expanded = !expanded },
        ) {
            Text(
                "w${f.weight}",
                style = Type.micro.copy(fontWeight = FontWeight.Bold),
                color = findingWeightColor(f.weight),
                modifier = Modifier.clip(RoundedCornerShape(Radius.chip))
                    .background(findingWeightColor(f.weight).copy(alpha = 0.12f))
                    .padding(horizontal = Space.xs, vertical = 1.dp),
            )
            Text(f.kind, style = Type.label)
            Spacer(Modifier.weight(1f))
            Text(
                "${f.file}:${f.line}" + if (f.symbol.isNotBlank()) " · ${f.symbol}" else "",
                style = Type.micro.copy(fontFamily = FontFamily.Monospace),
                color = Palette.TextSecondary,
                maxLines = 1,
            )
            Text(if (expanded) "▾" else "▸", style = Type.micro, color = Palette.TextTertiary)
        }
        if (expanded) {
            Spacer(Modifier.height(Space.xs))
            Text("证据：${f.evidence}", style = Type.body.copy(color = Palette.TextSecondary))
            val src = sourceLineAt(projectPath, f.file, f.line)
            if (src != null) {
                Text(
                    "L${f.line}: $src",
                    style = Type.micro.copy(fontFamily = FontFamily.Monospace),
                    color = Palette.TextPrimary,
                    modifier = Modifier.padding(top = Space.xs),
                )
            } else {
                Text(
                    "实码读不出（文件不在或行超界；上面是引擎证据原文）",
                    style = Type.micro, color = Palette.TextTertiary,
                    modifier = Modifier.padding(top = Space.xs),
                )
            }
        }
    }
}

// ── 补丁体检页（mac PatchCheckPage：diff 文本 → Layer1 算法 → 人工裁决 → Layer3 合并）──

@Stable
class PatchCheckPageModel(private val engine: Engine) {
    var projectName by mutableStateOf("")
    /** diff 输入区（本页输入形态 = 粘贴 diff 文本；mac 是自动取工作区 diff，差异如实标注）。 */
    var diffText by mutableStateOf("")
    var running by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var layer1 by mutableStateOf<PatchConfidence?>(null)
        private set
    var finalReport by mutableStateOf<MergedConfidence?>(null)
        private set
    /** uncertain 裁决表：id → resolved/unresolved/ambiguous（缺席 = ambiguous，mac 同款默认）。 */
    var verdicts by mutableStateOf<Map<String, String>>(emptyMap())

    suspend fun run(fallbackProject: String?) {
        if (projectName.isBlank()) projectName = fallbackProject ?: ""
        if (projectName.isBlank()) {
            error = "没有在册的可读项目"
            return
        }
        if (diffText.isBlank()) {
            error = "先在下面粘贴 diff 文本（git diff 的输出）"
            return
        }
        running = true; error = null; layer1 = null; finalReport = null
        try {
            val r = engine.patchConfidence(projectName, diffText)
            layer1 = r
            verdicts = r.uncertain.associate { it.id to "ambiguous" }
        } catch (e: Exception) {
            error = e.message ?: e.javaClass.simpleName
        } finally {
            running = false
        }
    }

    fun setVerdict(id: String, verdict: String) {
        verdicts = verdicts + (id to verdict)
    }

    /** Layer3：algorithm = Layer1 原样回传，agent = 裁决表（mac merge 对位）。 */
    suspend fun merge() {
        val alg = layer1 ?: return
        running = true; error = null
        try {
            finalReport = engine.mergePatchConfidence(alg, agentVerdictItems(verdicts))
        } catch (e: Exception) {
            error = e.message ?: e.javaClass.simpleName
        } finally {
            running = false
        }
    }
}

@Composable
fun PatchCheckPage(model: AppModel) {
    val status by model.status.collectAsState()
    val projects = status?.projects.orEmpty().filter { it.isReadable }
    val vm = remember { PatchCheckPageModel(model.engine) }
    val scope = rememberCoroutineScope()

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Space.xl, vertical = Space.lg),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text("补丁体检", style = Type.title)
                Text("三层体检：Layer1 算法 → 人工裁决 → Layer3 合并终稿", style = Type.label)
            }
            if (vm.running) CircularProgressIndicator(Modifier.size(14.dp), color = Palette.Accent, strokeWidth = 2.dp)
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Space.xl),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.md),
        ) {
            GraphProjectPicker(projects.map { it.name }, vm.projectName) { vm.projectName = it }
            // 按钮文案：run 对位 mac patch.run（mac 是「体检未提交改动」——它自动取工作区 diff；
            // CMP 输入形态是粘贴 diff 文本，不绑定「未提交」，故收短为「体检」）
            Button(
                onClick = { scope.launch { vm.run(null) } },
                enabled = !vm.running && vm.projectName.isNotBlank(),
                shape = RoundedCornerShape(Radius.control),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
            ) { Text("体检") }
            Button(
                onClick = { scope.launch { vm.merge() } },
                enabled = !vm.running && vm.layer1 != null,
                shape = RoundedCornerShape(Radius.control),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Deep, contentColor = Color.White),
            ) { Text("合并出最终分") }
        }
        vm.error?.let {
            Text(
                it, style = Type.body.copy(color = Palette.Amber),
                modifier = Modifier.fillMaxWidth().padding(horizontal = Space.xl, vertical = Space.sm),
            )
        }
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = Space.xl, vertical = Space.lg),
            verticalArrangement = Arrangement.spacedBy(Space.md),
        ) {
            // diff 输入区（多行；临时文件由引擎封装层写删，页面不落盘）
            GlassCard(Modifier.fillMaxWidth()) {
                Text("diff 输入", style = Type.section)
                Spacer(Modifier.height(Space.xs))
                Text("粘贴 git diff 的输出。引擎跑 Layer1 时写临时文件、用完即删。", style = Type.micro)
                Spacer(Modifier.height(Space.sm))
                OutlinedTextField(
                    value = vm.diffText,
                    onValueChange = { vm.diffText = it },
                    singleLine = false,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 130.dp),
                    textStyle = Type.micro.copy(fontFamily = FontFamily.Monospace),
                )
            }
            vm.finalReport?.let { f -> FinalCard(f) }
            vm.layer1?.let { l1 ->
                Layer1Card(l1, vm.verdicts) { id, v -> vm.setVerdict(id, v) }
                LowConfidenceSection(l1.entities, vm.diffText)
            }
            if (vm.layer1 == null && vm.error == null) {
                Text(
                    "粘贴 diff 后点「体检」：引擎先跑 Layer1 算法层，不确定的条目由你裁决，再合并终稿",
                    style = Type.body.copy(color = Palette.TextSecondary),
                    modifier = Modifier.padding(top = Space.xl),
                )
            }
        }
    }
}

/** Layer3 终稿卡：总分 + 复核计数 + 警示行（计数取 diagnostics.reviewed_by_agent——实测键位）。 */
@Composable
private fun FinalCard(f: MergedConfidence) {
    GlassCard(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
            Text("Layer3 · 合并终稿", style = Type.section)
            Text(
                "${(f.overall * 100).toInt()}",
                style = Type.display,
                color = patchOverallColor(f.overall),
            )
            Column(Modifier.padding(bottom = Space.xs)) {
                Text(
                    "已复核 ${f.diagnostics.reviewedByAgent} 条 · 未处理 ${f.diagnostics.deferred} 条" +
                        " · 算法层确定 ${f.diagnostics.certainFromAlgorithm} 条",
                    style = Type.micro,
                )
            }
        }
        if (f.alerts.isNotEmpty()) {
            Spacer(Modifier.height(Space.sm))
            f.alerts.forEach { a ->
                Text(alertLineText(a), style = Type.label, color = Palette.TextSecondary)
            }
        } else {
            Spacer(Modifier.height(Space.sm))
            Text("无警示行", style = Type.micro)
        }
    }
}

/** Layer1 算法卡：总分 + uncertain 数 + S1..S10 信号 chip（null = 分母 0，如实降档显示）。 */
@Composable
private fun Layer1Card(l1: PatchConfidence, verdicts: Map<String, String>, onVerdict: (String, String) -> Unit) {
    GlassCard(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
            Text("Layer1 · 算法层", style = Type.section)
            Text("${(l1.overall * 100).toInt()}", style = Type.display, color = patchOverallColor(l1.overall))
            Column(Modifier.padding(bottom = Space.xs)) {
                Text(
                    "不确定 ${l1.uncertain.size} 条 · 实体 ${l1.entities.size} · " +
                        "解析失败 ${l1.diagnostics.parseErrors} · 补丁文件 ${l1.diagnostics.patchFiles} · 新增行 ${l1.diagnostics.addedLines}",
                    style = Type.micro,
                )
            }
        }
        Spacer(Modifier.height(Space.sm))
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
            l1.signals.keys.sorted().forEach { k ->
                val v = l1.signals[k]
                Text(
                    signalChipLabel(k, v),
                    style = Type.micro.copy(fontFamily = FontFamily.Monospace),
                    color = if (isNullSignal(v)) Palette.TextTertiary else Palette.TextSecondary,
                    modifier = Modifier.clip(RoundedCornerShape(Radius.chip))
                        .background(Palette.Card.copy(alpha = if (isNullSignal(v)) 0.35f else 0.7f))
                        .padding(horizontal = Space.xs, vertical = 1.dp),
                )
            }
        }
        if (l1.diagnostics.nullSignals.isNotEmpty() && l1.diagnostics.nullSignalsNote.isNotBlank()) {
            Text(l1.diagnostics.nullSignalsNote, style = Type.micro, color = Palette.TextTertiary)
        }
        if (l1.uncertain.isNotEmpty()) {
            Spacer(Modifier.height(Space.md))
            Text("不确定条目 · 人工裁决（Layer2）", style = Type.card)
            Spacer(Modifier.height(Space.xs))
            l1.uncertain.forEach { u ->
                UncertainRow(u, verdicts[u.id] ?: "ambiguous") { v -> onVerdict(u.id, v) }
            }
        }
    }
}

/** uncertain 行：问题 + 详情 + 位置 + 三态裁决（确认/未解决/不确定）。 */
@Composable
private fun UncertainRow(u: PatchUncertain, current: String, onVerdict: (String) -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.sm),
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.control))
            .background(Palette.Card.copy(alpha = 0.55f)).padding(Space.sm),
    ) {
        Column(Modifier.weight(1f)) {
            Text(u.issue, style = Type.label.copy(fontWeight = FontWeight.SemiBold))
            Text(u.detail, style = Type.micro, color = Palette.TextSecondary)
            u.contextRef?.let {
                Text(
                    "${it.file}:${it.line}",
                    style = Type.micro.copy(fontFamily = FontFamily.Monospace),
                    color = Palette.TextTertiary,
                )
            }
        }
        VerdictPills(u.id, onVerdict = onVerdict)
    }
}

/** 三态裁决 pills：resolved/unresolved/ambiguous（选中 = accent 底）。 */
@Composable
private fun VerdictPills(current: String, onVerdict: (String) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
        listOf(
            "resolved" to "确认",
            "unresolved" to "未解决",
            "ambiguous" to "不确定",
        ).forEach { (v, label) ->
            val selected = current == v
            Text(
                label, style = Type.micro,
                color = if (selected) Color.White else Palette.TextSecondary,
                modifier = Modifier.clip(RoundedCornerShape(Radius.control))
                    .background(if (selected) Palette.Accent else Palette.Card)
                    .clickable { onVerdict(v) }
                    .padding(horizontal = Space.sm, vertical = Space.xs),
            )
        }
    }
}

/** 低置信度实体区（< 0.75 升序）：默认只告知位置与分数，点击展开 diff 块。 */
@Composable
private fun LowConfidenceSection(entities: List<PatchEntity>, diffText: String) {
    val lows = lowConfidencePatchEntities(entities)
    GlassCard(Modifier.fillMaxWidth()) {
        Text("低置信度实体 ${lows.size} 个", style = Type.section)
        Spacer(Modifier.height(Space.xs))
        if (lows.isEmpty()) {
            Text("没有低于 0.75 的实体——补丁涉及的位置算法都看得懂", style = Type.label)
        } else {
            Text("最不可信的排最前；点击行展开该位置的 diff 块。", style = Type.micro)
            Spacer(Modifier.height(Space.xs))
            lows.forEach { e -> PatchEntityRow(e, diffText) }
        }
    }
}

/** 实体披露行：收起 = [百分比] 类别 位置；展开 = 覆盖该位置的 diff hunk（无则如实说）。 */
@Composable
private fun PatchEntityRow(e: PatchEntity, diffText: String) {
    var expanded by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.control))
            .background(Palette.Card.copy(alpha = 0.55f)).padding(Space.sm),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.sm),
            modifier = Modifier.fillMaxWidth().clickable { expanded = !expanded },
        ) {
            Text(
                "${(e.confidence * 100).toInt()}%",
                style = Type.micro.copy(fontWeight = FontWeight.Bold),
                color = patchEntityColor(e.confidence),
            )
            Text(e.kind, style = Type.label)
            Spacer(Modifier.weight(1f))
            Text(
                "${e.file}:${e.line}",
                style = Type.micro.copy(fontFamily = FontFamily.Monospace),
                color = Palette.TextSecondary,
                maxLines = 1,
            )
            Text(if (expanded) "▾" else "▸", style = Type.micro, color = Palette.TextTertiary)
        }
        if (expanded) {
            Spacer(Modifier.height(Space.xs))
            val hunk = extractDiffHunk(diffText, e.file, e.line)
            if (hunk != null) {
                Text(
                    hunk,
                    style = Type.micro.copy(fontFamily = FontFamily.Monospace),
                    color = Palette.TextPrimary,
                )
            } else {
                Text("补丁未覆盖该位置（hunk 匹配不到 file:line）", style = Type.micro, color = Palette.TextTertiary)
            }
        }
    }
}
