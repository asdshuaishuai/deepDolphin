// BulkUpdate.kt —— 全量更新的告知式确认框 + 结果面板（mac AgentBulkUpdate.swift /
// AgentBulkView.swift / DestructiveGuard.swift bulkUpdate 分支的 Compose 对位）。
//
// 【为什么确认框是告知式的，不染红】对位 mac DestructiveGuard.swift:117-130 原话：
// 批量更新会改写多个仓库的托管区域，但每个文件改写前引擎都留备份（applyRegions
// 不变量），是可逆的——弹红字的「你确定要删东西吗」会稀释「红=危险」的信号，
// 所以只**报范围**（几个项目、哪一轨、会动什么、备份在哪），不染红。
//
// 【数据源边界，如实标注】mac 走 agent 工具通道逐仓库调 run_shallow_update /
// run_deep_update，跑完由 AI 生成 ≤200 字简报（AgentBulkUpdate.digest）；CMP 的
// 数据源是 Engine.updateAll 单发批量命令的 MultiResults——逐仓库成败/改了哪些文档/
// 备份路径都在引擎回执里（真机 fixtures/update_all*.json 锚定），面板只摊引擎事实。
// AI 简报那一层 CMP 没有（不伪造）；mac 的 aiNote 恒有值纪律在这里的对应物是
// coverageNote / tallyMismatchNote 两行引擎口径核对披露。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import deepdolphin.engine.MultiResults
import deepdolphin.engine.UpdateOutcome
import deepdolphin.engine.UpdateReceipt
import kotlin.math.max
import kotlin.math.min

// ── 纯函数层（判据见 BulkUpdateTest；mac DestructiveGuard / updateOutcomeSummary 对位）──

/** 轨道词（mac DSSyncTrack.label 对位：浅更新 / 深更新）。 */
fun bulkTrackWord(deep: Boolean): String = if (deep) "深更新" else "浅更新"

/** 确认框标题（mac bar.bulkConfirm「全部%@？」对位）。 */
fun bulkConfirmTitle(deep: Boolean): String = "全部${if (deep) "深" else "浅"}更新？"

/**
 * 确认框正文（mac DestructiveGuard.bulkUpdateMessage 逐字对位）：
 * n=0 有自己的话（「不会做任何事」）；浅/深两轨说清各自会动什么；
 * 结尾必须说备份（可回滚是「不染红」的全部依据）。
 */
fun bulkUpdateMessage(projectCount: Int, deep: Boolean): String {
    val n = max(projectCount, 0)
    if (n == 0) return "当前没有已注册的项目，不会做任何事。"
    val one = if (n == 1) "1 个项目" else "$n 个项目"
    val what = if (!deep) {
        "读取 git 历史并改写托管区域（README / AGENTS.md 等）"
    } else {
        "除浅更新外还会调用 AI 重新生成内容"
    }
    return "将对 $one 执行${bulkTrackWord(deep)}：$what。每个被改写的文件都会先留备份，所以可以回滚。"
}

/**
 * 单仓库成功回执的结果行（mac UpdateOutcome.swift updateOutcomeSummary 逐字对位）。
 * 三态分开说（缺陷 #211 的纪律：合成一句话就会撒谎）：
 *   · 引擎没报文档     —— 不许说「已刷新」；
 *   · 报了但没变       —— 说「没有变化」，不是「已更新」；
 *   · 真的动了          —— 说改了哪些；有备份必须给路径，没有备份（新建）不许编。
 */
fun updateOutcomeLine(r: UpdateReceipt, nameMax: Int = 2): String {
    val project = r.project.ifBlank { "（引擎未给项目名）" }
    if (r.docs.isEmpty()) return "$project：本次没有需要更新的文档"
    val touched = r.docs.filter { it.changed }
    if (touched.isEmpty()) return "$project：文档没有变化（${r.docs.joinToString("、") { it.file }}）"
    val cap = max(1, nameMax)
    val listed = touched.take(cap).joinToString("、") { if (it.created) "新建 ${it.file}" else "已更新 ${it.file}" }
    var s = "$project：" + listed
    if (touched.size > min(cap, touched.size)) s += " 等 ${touched.size} 个文档"
    // 备份只给第一个（一行放不下多条路径；「备份存在」这个事实比枚举更重要）
    touched.firstOrNull { it.backup.isNotBlank() }?.let { first ->
        s += "（${first.file} 的旧版本已备份到 ${first.backup}）"
    }
    return s
}

/**
 * 整批结果（mac AgentBulkUpdate.Report 对位；attempted=发起时注册表项目数，
 * outcomes=引擎 results[] 二态解码——两者不是一回事，分叉必须能被看见）。
 */
data class BulkReport(
    val deep: Boolean,
    /** 发起时注册表里的项目数（mac Report.attempted 对位：一个不漏的名单基数）。 */
    val attempted: Int,
    /** 引擎回执解码后的逐仓库终态。 */
    val outcomes: List<UpdateOutcome>,
    /** 引擎信封自记的账（count/failed/succeeded；与逐条计数分叉时披露）。 */
    val engineCount: Long,
    val engineFailed: Long,
) {
    val succeeded: Int get() = outcomes.count { it is UpdateOutcome.Success }
    val failed: Int get() = outcomes.size - succeeded

    /** 面板标题（mac L10n bulk.title「全量%@更新 · %d 个仓库」对位：浅/深度两词）。 */
    fun title(): String = "全量${if (deep) "深度" else "浅"}更新 · ${max(attempted, outcomes.size)} 个仓库"

    /** 页头反馈行（lastResult 的那一行；「成功」一个词贯穿，不换词造成两个答案）。 */
    fun headLine(): String = "全部${bulkTrackWord(deep)}：成功 $succeeded / 共 ${outcomes.size} 个回执"

    /**
     * 逐仓库小节的 tally（mac outcomeMarkdown 的 tally 对位，措辞纪律照抄）：
     * 失败 0 时说「N 个仓库全部成功」不说「成功 N · 失败 0」（不必读者自己做减法）。
     */
    fun tally(): String = when {
        outcomes.isEmpty() -> "引擎没有返回任何仓库结果"
        failed == 0 -> "$succeeded 个仓库全部成功"
        else -> "成功 $succeeded · 失败 $failed"
    }

    /**
     * 覆盖度披露：注册表名单 vs 引擎回执条数。mac 靠「逐个显式传项目名」保证一个不漏；
     * CMP 是引擎侧自己遍历注册表——它没给回执的仓库客户端**不知道**结果，
     * 不许默认成成功或失败，只能如实说「没有回执」。
     */
    fun coverageNote(): String? = when {
        attempted > 0 && outcomes.isEmpty() ->
            "注册表里有 $attempted 个项目，但引擎没有返回任何结果条目——本次每个仓库的实际状态未知。"
        outcomes.size < attempted ->
            "引擎只返回 ${outcomes.size}/${attempted} 个仓库的结果，其余没有回执——不在上面编造它们的状态。"
        else -> null
    }

    /** 引擎自记账与客户端逐条计数的分叉披露（两边数字对不上时以逐条为准，但必须说）。 */
    fun tallyMismatchNote(): String? =
        if (engineCount > 0 && engineCount != outcomes.size.toLong()) {
            "引擎信封计数 count=$engineCount 与结果条数 ${outcomes.size} 不一致，以逐条结果为准。"
        } else {
            null
        }

    companion object {
        fun of(deep: Boolean, attempted: Int, r: MultiResults): BulkReport = BulkReport(
            deep = deep,
            attempted = attempted,
            outcomes = r.results.map { deepdolphin.engine.decodeUpdateOutcome(it) },
            engineCount = r.count,
            engineFailed = r.failed,
        )
    }
}

// ── 确认框（mac confirmationDialog 对位：告知式，不染红）──

@Composable
fun BulkUpdateConfirmDialog(model: AppModel) {
    val pending by model.pendingBulk.collectAsState()
    val deep = pending ?: return
    val status by model.status.collectAsState()
    val projectCount = status?.projects?.size ?: 0
    Dialog(
        onDismissRequest = { model.cancelBulkUpdate() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            Modifier
                .width(420.dp)
                .clip(RoundedCornerShape(Radius.card))
                .background(Palette.Card)
                .padding(Space.lg),
            verticalArrangement = Arrangement.spacedBy(Space.md),
        ) {
            Text(bulkConfirmTitle(deep), style = Type.title)
            Text(bulkUpdateMessage(projectCount, deep), style = Type.body.copy(color = Palette.TextSecondary))
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                Spacer(Modifier.weight(1f))
                Button(
                    onClick = { model.cancelBulkUpdate() },
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Palette.CardHover,
                        contentColor = Palette.TextPrimary,
                    ),
                ) { Text("取消") }
                // 确认钮不染红（对位 mac isDestructiveRole(bulkUpdate)=false：可逆操作）
                Button(
                    onClick = { model.confirmBulkUpdate(deep) },
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Palette.Accent,
                        contentColor = Color.White,
                    ),
                ) { Text("全部更新") }
            }
        }
    }
}

// ── 结果面板（mac AgentBulkResultSheet 对位：逐仓库摊结果，无重生成按钮）──

@Composable
fun AgentBulkResultSheet(model: AppModel) {
    val report by model.bulkReport.collectAsState()
    val r = report ?: return
    Dialog(
        onDismissRequest = { model.closeBulkResult() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            Modifier
                .fillMaxWidth(0.52f)
                .fillMaxHeight(0.72f)
                .clip(RoundedCornerShape(Radius.card))
                .background(Palette.Card)
                .padding(Space.lg),
            verticalArrangement = Arrangement.spacedBy(Space.md),
        ) {
            // ── 标题 + 总账（mac markdown 头对位：注册/执行/成功/失败四个数）──
            Text(r.title(), style = Type.title)
            Text(
                "已注册项目 ${r.attempted} 个，本次实际执行 ${r.outcomes.size} 个，" +
                    "成功 ${r.succeeded} 个，失败 ${r.failed} 个。",
                style = Type.label,
            )
            // ── 逐仓库结果（永远生成、零 AI 成分——事实陈述不许让模型重写）──
            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(Space.xs),
            ) {
                Text("逐仓库结果（${r.tally()}）", style = Type.section)
                if (r.outcomes.isEmpty()) {
                    Text("没有结果条目。", style = Type.body.copy(color = Palette.TextSecondary))
                } else {
                    r.outcomes.forEach { o ->
                        Row(Modifier.fillMaxWidth()) {
                            Box(
                                Modifier.size(8.dp).background(
                                    if (o is UpdateOutcome.Success) Palette.Green else Palette.Red,
                                    CircleShape,
                                ),
                            )
                            Spacer(Modifier.width(Space.sm))
                            Text(
                                when (o) {
                                    is UpdateOutcome.Success -> updateOutcomeLine(o.receipt)
                                    is UpdateOutcome.Failure ->
                                        "✗ ${o.failure.message.ifBlank { "更新失败（${o.failure.code.ifBlank { "引擎未给原因" }}）" }}"
                                },
                                style = Type.body.copy(fontFamily = FontFamily.Monospace, fontSize = Type.label.fontSize),
                                color = if (o is UpdateOutcome.Success) Palette.TextSecondary else Palette.Red,
                            )
                        }
                    }
                }
                // ── 覆盖度 / 账目分叉披露（引擎口径核对，amber 说实话）──
                r.coverageNote()?.let {
                    Spacer(Modifier.height(Space.xs))
                    Text("⚠ $it", style = Type.micro.copy(color = Palette.Amber))
                }
                r.tallyMismatchNote()?.let {
                    Text("⚠ $it", style = Type.micro.copy(color = Palette.Amber))
                }
            }
            Row {
                Spacer(Modifier.weight(1f))
                Button(
                    onClick = { model.closeBulkResult() },
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Palette.Accent,
                        contentColor = Color.White,
                    ),
                ) { Text("关闭") }
            }
        }
    }
}
