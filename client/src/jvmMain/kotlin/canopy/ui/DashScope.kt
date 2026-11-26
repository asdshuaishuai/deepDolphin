// DashScope.kt —— 仪表盘的筛选口径与 KPI 归并（mac DashboardScope.swift / CommitTypeComposition.swift /
// LanguageCoverage.swift / MilestoneCard.swift 及 Models.swift 里里程碑/分支派生属性的 Kotlin 对位）。
//
// 【为什么是纯函数层】mac 的注释原话：这类控件的失败不是「不好看」，而是「摆在那里不起作用」
// ——用户拨了「近 7 天」而卡片数字纹丝不动。判定内联在视图里就只能靠肉眼发现，
// 所以判定全在这里，视图只把控件的值塞进来、把结果画出去。**视图里不许出现算术。**

package canopy.ui

import canopy.engine.CommitTypeCount
import canopy.engine.DashboardData
import canopy.engine.Milestone
import canopy.engine.MilestoneCounts
import canopy.engine.Project
import kotlin.math.roundToInt

const val COMMIT_TYPE_LINE_MAX = 5
const val LANG_BAR_MAX = 8
const val MILESTONE_CARD_MAX = 5

/** 色板容量（提交构成 12 类穷举、不取模）。 */
val COMMIT_TYPE_CAPACITY: Int get() = Composition12.size

// ════════════════ 时间跨度 ════════════════

/**
 * 时间跨度。口径：按「最近更新天数」分档——引擎没有逐项目的提交时间序列，
 * 不是「这段时间内的提交量」。界面上必须照实说「最近更新」。
 */
enum class DashSpan(val maxDays: Int?) {
    ALL(null), D30(30), D7(7);

    val label: String get() = when (this) {
        ALL -> L10n.t("cmp.dash.spanAll")
        D30 -> L10n.t("cmp.dash.span30")
        D7 -> L10n.t("cmp.dash.span7")
    }
}

/**
 * 项目在最近 days 天内更新过吗。days=null = 不按时间筛。
 * 判定依据是 daysSinceLastCommit（源自 lastCommitAt），**不是** staleDays：
 * 后者是追踪分支「距上次被引擎记录」，无远端基线时 branches 恒空。
 * 读不出来时一律**保留**——滤掉它等于说「它不在近 7 天内」，而真相是「不知道」。
 */
fun updatedWithin(p: Project, days: Int?, nowMs: Long = System.currentTimeMillis()): Boolean {
    if (days == null) return true
    val age = daysSinceLastCommit(p, nowMs) ?: return true
    return age <= days
}

// ════════════════ 提交类型筛选 ════════════════

/** 只作用于提交结构条：决定堆叠条画哪几段、图例列哪几行。**不改 KPI 数字**。 */
sealed interface DashCommitFilter {
    data object All : DashCommitFilter
    data class Only(val type: String) : DashCommitFilter

    fun allowed(type: String): Boolean = this == All || (this is Only && this.type == type)

    val label: String
        get() = when (this) {
            All -> L10n.t("cmp.dash.allTypes")
            is Only -> type
        }
}

/** 只列真实出现过的提交类型（按项目首现去重后排序）。 */
fun availableCommitTypes(projects: List<Project>): List<String> =
    projects.flatMap { it.commitTypes }.map { it.kind }.distinct().sorted()

// ════════════════ 组合筛选 ════════════════

data class DashFilter(
    val span: DashSpan = DashSpan.ALL,
    val commits: DashCommitFilter = DashCommitFilter.All,
) {
    fun keeps(p: Project, nowMs: Long = System.currentTimeMillis()): Boolean = updatedWithin(p, span.maxDays, nowMs)

    fun keptStats(stats: List<CommitTypeCount>): List<CommitTypeCount> = stats.filter { commits.allowed(it.kind) }
}

// ════════════════ KPI 归并 ════════════════

enum class DashKpiKind { PROJECTS, MILESTONES, ATTENTION, REACH }

data class DashKpi(
    val kind: DashKpiKind,
    val title: String,
    /** 主数字。里程碑完成率是 0…100；其余是计数。 */
    val value: Long,
    /** 副说明：回答「这个数字意味着什么」。 */
    val caption: String,
    /** 只有里程碑完成度才画进度条。 */
    val progress: Float? = null,
    /** 待处理卡：有没有事（颜色随事实变）。 */
    val needsAttention: Boolean = false,
)

/**
 * 四张 KPI（mac DashKPIBuilder.kpis 对位）：
 *   1. 我有多少东西 → 项目总数（主数字必须是 listed，不是 total）
 *   2. 目标完成到什么程度 → 里程碑完成率
 *   3. 有多少事等着我处理 → 待处理项目数（与侧栏徽标 / 看板同源：needsAction）
 *   4. 仓库面有多宽 → 分支（repoBranchCount 真实值，不是追踪数组长度）
 */
fun dashKpis(d: DashboardData, projects: List<Project>): List<DashKpi> {
    val listed = d.projects.listed
    val failed = d.projects.failed
    // 1. total 只数采集成功的；标题写 total 会与同屏侧栏「仓库（N/M）」给出两个答案
    var projectsCaption = L10n.t(
        "cmp.kpi.projectsCaption", d.projects.total, listed, d.projects.active7d, d.projects.active30d,
    )
    if (failed > 0) projectsCaption += L10n.t("cmp.kpi.failedSuffix", failed)

    // 2. 分母只取「达没达成有答案的」——不把 unknown 塞进分母
    val ms = d.milestones.counts
    val decided = ms.done + ms.open
    val pct = if (decided > 0) (ms.done.toDouble() * 100 / decided).roundToInt().toLong() else 0L
    var msCaption = L10n.t("cmp.kpi.msCaption", ms.open, ms.done)
    if (ms.unknown > 0) msCaption += L10n.t("cmp.kpi.msUnknown", ms.unknown)

    // 3. 必须是**项目数**，且与看板「待处理」列同一规则；构成降级到副说明并写清单位
    val attentionProjects = projects.filter { needsAction(it) }
    val mergeBranchCount = projects.sumOf { p -> p.branches.count { it.isMergeCandidate } }
    var attentionCaption = L10n.t("cmp.kpi.attentionDirty", d.projects.dirty)
    if (mergeBranchCount > 0) attentionCaption += L10n.t("cmp.kpi.mergeBranches", mergeBranchCount)
    attentionCaption += L10n.t("cmp.kpi.untrackedFiles", d.work.untrackedFiles)

    // 4. work.branches = 追踪数组长度之和（无远端基线时恒 0）；真实分支数是 repoBranchCount
    val realBranches = projects.sumOf { (it.repoBranchCount ?: -1).coerceAtLeast(0) }
    val unreadableBranchCount = projects.count { (it.repoBranchCount ?: -1) < 0 }
    var reachCaption = L10n.t("cmp.kpi.reachCaption", d.work.stashes, d.work.untrackedFiles)
    reachCaption += L10n.t("cmp.kpi.trackedEntries", d.work.branches)
    if (unreadableBranchCount > 0) {
        reachCaption += L10n.t("cmp.kpi.unreadableBranches", unreadableBranchCount)
    } else if (d.work.branches < realBranches) {
        reachCaption += L10n.t("cmp.kpi.restUntracked")
    }
    // tags 对可读项目恒发（可能为空数组）；一条都读不到时不编 tag 数
    if (projects.any { it.isReadable }) {
        reachCaption += L10n.t("cmp.kpi.tagCount", projects.sumOf { it.tags.size })
    }

    return listOf(
        DashKpi(DashKpiKind.PROJECTS, L10n.t("dash.projectCount"), listed, projectsCaption),
        DashKpi(
            DashKpiKind.MILESTONES, L10n.t("cmp.kpi.msTitle"), pct, msCaption,
            progress = if (decided > 0) ms.done.toFloat() / decided else null,
        ),
        DashKpi(DashKpiKind.ATTENTION, L10n.t("dash.pendingCount"), attentionProjects.size.toLong(), attentionCaption,
            needsAttention = attentionProjects.isNotEmpty()),
        DashKpi(DashKpiKind.REACH, L10n.t("cmp.kpi.branchesTitle"), realBranches, reachCaption),
    )
}

/** 速览/页头的一行汇总（mac DashKPIBuilder.summaryLine 对位）。 */
fun dashSummaryLine(kpis: List<DashKpi>): String {
    fun value(kind: DashKpiKind) = kpis.firstOrNull { it.kind == kind }?.value ?: 0L
    val projects = value(DashKpiKind.PROJECTS)
    val attention = value(DashKpiKind.ATTENTION)
    return if (attention > 0) {
        L10n.t("cmp.kpi.summaryAttention", projects, attention)
    } else {
        L10n.t("cmp.kpi.summary", projects)
    }
}

// ════════════════ 提交构成 ════════════════

data class CommitTypeComposition(val line: String?, val shown: Int, val total: Int, val topCut: Boolean)

data class CommitTypeCardSlice(val entries: List<CommitTypeCount>, val total: Int, val cut: Boolean, val note: String?)

/** 一行文字版（提交构成行）。 */
fun commitTypeComposition(
    entries: List<CommitTypeCount>,
    sampleTruncated: Boolean,
    totalCommits: Long = 0,
    lineMax: Int = COMMIT_TYPE_LINE_MAX,
): CommitTypeComposition {
    val total = entries.size
    if (total == 0) return CommitTypeComposition(null, 0, 0, false)
    val cap = lineMax.coerceAtLeast(1)
    val shown = minOf(total, cap)
    val body = entries.take(cap).joinToString(" · ") { "${it.kind} ×${it.count}" }
    val notes = mutableListOf<String>()
    if (sampleTruncated) {
        val sampled = entries.sumOf { it.count }
        notes += if (totalCommits > 0) L10n.t("cmp.ct.lineSample", sampled, totalCommits) else L10n.t("cmp.ct.lineSampleNoTotal")
    }
    if (shown < total) notes += L10n.t("cmp.ct.lineCut", shown, total)
    return CommitTypeComposition(
        line = if (notes.isEmpty()) body else "$body（${notes.joinToString("；")}）",
        shown = shown, total = total, topCut = shown < total,
    )
}

/** 卡片里的堆叠条 + 图例要画的段。**不取模**——取模会让第 13 类拿到第 1 类的颜色，两段同色并成一段。 */
fun commitTypeCardSlice(entries: List<CommitTypeCount>, capacity: Int = COMMIT_TYPE_CAPACITY): CommitTypeCardSlice {
    val total = entries.size
    if (capacity <= 0 || total <= capacity) return CommitTypeCardSlice(entries, total, false, null)
    return CommitTypeCardSlice(
        entries.take(capacity), total, true,
        L10n.t("cmp.ct.paletteCut", capacity, total - capacity),
    )
}

// ════════════════ 语言分布披露 ════════════════

data class LanguageCoverage(val emptyTitle: String, val note: String?)

fun languageCoverage(
    languageCount: Int,
    truncated: Boolean,
    failed: Long,
    reasons: List<String>?,
    topCut: Boolean = false,
    shownCount: Int? = null,
): LanguageCoverage {
    val notes = mutableListOf<String>()
    if (truncated) notes += L10n.t("cmp.lang.truncated")
    if (topCut) notes += L10n.t("cmp.lang.topCut")
    if (shownCount != null && shownCount < languageCount) notes += L10n.t("cmp.lang.shownCut", shownCount, languageCount)
    if (failed > 0) {
        var line = L10n.t("cmp.lang.failed", failed)
        reasons?.firstOrNull()?.takeIf { it.isNotBlank() }?.let { line += L10n.t("cmp.lang.failedReason", it) }
        notes += line
    }
    val emptyTitle = if (failed > 0 && languageCount == 0) L10n.t("cmp.lang.emptyFailed") else L10n.t("cmp.lang.empty")
    return LanguageCoverage(emptyTitle, notes.takeIf { it.isNotEmpty() }?.joinToString("\n"))
}

// ════════════════ 里程碑卡 ════════════════

data class MilestoneCardSlice(val shown: Int, val total: Int, val cut: Boolean, val note: String?)

fun milestoneCardSlice(itemCount: Int, cardMax: Int = MILESTONE_CARD_MAX): MilestoneCardSlice {
    val total = itemCount.coerceAtLeast(0)
    if (total == 0) return MilestoneCardSlice(0, 0, false, null)
    val shown = minOf(total, cardMax.coerceAtLeast(1))
    if (shown >= total) return MilestoneCardSlice(shown, total, false, null)
    return MilestoneCardSlice(shown, total, true, L10n.t("ms.card.truncated", shown, total))
}

fun milestoneCardTitle(c: MilestoneCounts): String {
    val parts = mutableListOf(L10n.t("ms.title.open", c.open), L10n.t("ms.title.done", c.done))
    if (c.dropped > 0) parts += L10n.t("ms.title.dropped", c.dropped)
    if (c.unknown > 0) parts += L10n.t("ms.title.unknown", c.unknown)
    if (c.excludedDisabled > 0) parts += L10n.t("ms.title.excluded", c.excludedDisabled)
    if (c.orphaned > 0) parts += L10n.t("ms.title.orphaned", c.orphaned)
    if (c.degraded || c.storeHealth != "ok") parts += "⚠ milestones.json ${c.storeHealth}"
    return L10n.t("ms.title.head", parts.joinToString(" · "))
}

// ════════════════ 里程碑行派生（mac MilestoneItem）════════════════

fun milestoneStatusLabel(m: Milestone): String = when {
    m.isUnknown -> L10n.t("cmp.ms.unverifiable")
    m.status == "done" -> L10n.t("ms.done")
    m.status == "dropped" -> L10n.t("ms.dropped")
    m.overdue -> L10n.t("ms.overdue")
    else -> L10n.t("ms.open")
}

/** 到期文案；空串 = 没有目标日期或天数读不出来。 */
fun milestoneDueText(m: Milestone): String {
    if (m.targetDate.isEmpty() || m.daysToTarget == -1L) return ""
    return if (m.daysToTarget >= 0) L10n.t("cmp.ms.daysLeft", m.daysToTarget) else L10n.t("cmp.ms.overdueDays", -m.daysToTarget)
}

fun milestoneCommitsText(m: Milestone): String =
    if (!m.commitsSinceReadable || m.commitsSince < 0) L10n.t("cmp.ms.commitsUnreadable")
    else L10n.t("ms.row.since", m.commitsSince.toString())

fun milestoneUnverifiedNote(m: Milestone): String =
    m.unverifiedReason.ifBlank { L10n.t("cmp.ms.commitsUnreadable") }

// ════════════════ 分支派生（mac BranchStatus.staleText）════════════════

/** 追踪分支「多久没更新」；null/-1 = 读不出来。 */
fun branchStaleText(staleDays: Long?): String = when {
    staleDays == null || staleDays < 0 -> L10n.t("cmp.branch.staleUnreadable")
    staleDays == 0L -> L10n.t("cmp.branch.staleToday")
    staleDays == 1L -> L10n.t("cmp.branch.staleOne")
    else -> L10n.t("cmp.branch.staleDays", staleDays)
}

// ════════════════ 分支范围行（mac ProjectStatus.branchScopeLine）════════════════

/** 分支卡标题的口径行：已跟踪几条 / 仓库真实几条——两者不等本身就是该说给用户听的信息。 */
fun branchScopeLine(tracked: Int, repoBranchCount: Long?): String = when {
    repoBranchCount == null || repoBranchCount < 0 -> L10n.t("cmp.detail.branchScopeUnreadable", tracked)
    repoBranchCount > tracked -> L10n.t("cmp.detail.branchScopePartial", tracked, repoBranchCount)
    else -> L10n.t("cmp.detail.branchScope", tracked)
}
