// Models.kt —— 引擎 --json 契约的唯一 Kotlin 镜像。
//
// 【键名纪律】键名以 fixtures（src/jvmTest/resources/fixtures/，取自真实引擎输出）
// 与 archive/bui 的 models.rs 为准，不许发明键。camelCase 全线一致。
// 【缺键纪律】「缺键 ≠ 零」：可缺席字段一律 nullable，-1 = 读不出来（引擎既定哨兵）。
// 失败项目仍是完整形状（error 有值、dirty/overall 是 {}），isReadable 判定。

package deepdolphin.engine

import androidx.compose.runtime.Immutable

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** 契约解析器：全大写共用。缺键 → default；未知键 → 忽略（引擎加键不破客户端）。 */
val contractJson = Json {
    ignoreUnknownKeys = true
    isLenient = false
    explicitNulls = false
}

/** 缺键抛错 = 契约过旧（入口闸门判；与 mac/BUI 同口径：整体拒绝，不半解析）。 */
fun <T> decodeOrThrow(deserializer: kotlinx.serialization.KSerializer<T>, text: String): T =
    contractJson.decodeFromString(deserializer, text)

// ── status --json ──

@Serializable
@Immutable
data class StatusEnvelope(
    val projects: List<Project> = emptyList(),
    val summary: Summary = Summary(),
    /** 引擎事实语言（zh / en）。缺键 = 不知道，不假设 zh。 */
    val language: String? = null,
)

@Serializable
@Immutable
data class Summary(
    val projectCount: Long = 0,
    val degradedStores: Long = 0,
    val listedProjects: Long = 0,
    val failedProjects: Long = 0,
    val activeProjects: Long = 0,
    val staleProjects: Long = 0,
    val dirtyProjects: Long = 0,
    val branchCount: Long = 0,
    val repoBranchTotal: Long = 0,
    val branchTruncatedProjects: Long = 0,
    val branchUnknownProjects: Long = 0,
    val generatedAt: String = "",
)

@Serializable
@Immutable
data class Project(
    // ── 身份 ──
    val storeHealth: String = "",
    val id: String = "",
    val name: String = "",
    val path: String = "",
    val kind: String = "",
    val remote: String = "",
    /** 采集失败原因。有值 = 读不出来（不是「健康但空」）。 */
    val error: String? = null,
    val headline: String? = null,
    // ── 分支 ──
    val currentBranch: String? = null,
    val defaultBranch: String? = null,
    // ── 脏度（-1 = 读不出来）──
    val userDirtyCount: Long? = null,
    val untrackedCount: Long? = null,
    val untrackedError: String = "",
    val stashCount: Long? = null,
    val worktreeCount: Long? = null,
    // ── 最近提交 ──
    val lastCommitAgo: String? = null,
    val lastCommitAt: String = "",
    // ── 提交构成 ──
    val commitTypes: List<CommitTypeCount> = emptyList(),
    /** null = 引擎没发这个键（不许当成「没截断」）。 */
    val commitTypesTruncated: Boolean? = null,
    // ── 分支明细 ──
    val branches: List<Branch> = emptyList(),
    val repoBranchCount: Long? = null,
    /** 合并建议。null = 当前就在默认分支，不是「没有」。 */
    val mergeHint: MergeHint? = null,
    // ── 日志 ──
    val journal: List<JournalEntry> = emptyList(),
    val journalTruncated: Boolean? = null,
    val journalLimit: Long = 0,
    val journalUnparsableLines: Long? = null,
    // ── 披露与元数据 ──
    val warnings: List<String>? = null,
    val tags: List<String> = emptyList(),
    val manifests: List<String> = emptyList(),
    /** 失败项目实测是 {}（不是 null）。null = 对象缺席。 */
    val dirty: Dirty? = null,
    /** -1 = 读不出来（失败项目）。 */
    val commitCount: Long? = null,
    /** 失败项目实测是 {}。 */
    val overall: Overall? = null,
    val docs: List<DocEntry>? = null,
    val progress: Progress = Progress(),
    val fetchedAt: String = "",
) {
    val isGit: Boolean get() = kind == "git"
    val isReadable: Boolean get() = error == null
    /** 结构化脏度是否已知（dirty.ok=true 且 total 在场）。 */
    val dirtyKnown: Boolean get() = dirty?.ok == true && dirty.total >= 0
    /**
     * 「这条项目该显示哪个分支」——标记为当前的那个，没有就退回第一个。
     * mac 基准 Models.swift:436-438（primaryBranch）同款：领域规则属于模型层，
     * 视图各自内联会抄出几份不同步的判定（mac 曾三份）。branches 是**追踪数组**
     * （无远端基线的仓库恒空），返回 null = 没有分支记录，不是「没有分支」。
     */
    val primaryBranch: Branch? get() = branches.firstOrNull { it.isCurrent } ?: branches.firstOrNull()
}

@Serializable
@Immutable
data class Dirty(
    val ok: Boolean = false,
    val clean: Boolean = false,
    val staged: Long = 0,
    val modified: Long = 0,
    val untracked: Long = 0,
    val conflicts: Long = 0,
    val total: Long = 0,
    val files: List<String> = emptyList(),
    val err: String? = null,
)

@Serializable
@Immutable
data class Overall(
    val summary: String = "",
    val notes: List<String> = emptyList(),
)

@Serializable
@Immutable
data class MergeHint(
    val kind: String = "",
    val ahead: Long = 0,
    val behind: Long = 0,
    val defaultBranch: String = "",
    val target: String = "",
    val description: String = "",
)

@Serializable
@Immutable
data class Progress(
    val updatedAt: String = "",
    val lastUpdateAt: String = "",
    val lastTrackAt: String = "",
    val lastDeepAt: String = "",
    val entryCount: Long = 0,
    val entryCountTruncated: Boolean? = null,
    val entriesKept: Long = 0,
    val runCount: Long = 0,
)

@Serializable
@Immutable
data class DocEntry(
    val file: String = "",
    val exists: Boolean = false,
)

@Serializable
@Immutable
data class Branch(
    val name: String = "",
    val status: String = "",
    val statusLabel: String = "",
    val head: String = "",
    val headShort: String = "",
    val headDate: String = "",
    val headAgo: String = "",
    val headSubject: String = "",
    val summary: String = "",
    val highlights: List<String> = emptyList(),
    val nextSteps: List<String> = emptyList(),
    val aheadOfDefault: Long = 0,
    val merged: Boolean = false,
    val pendingCommits: Long = 0,
    val baselineReset: Boolean = false,
    val provider: String = "",
    val isCurrent: Boolean = false,
    /** fixtures 实测恒发（beacon/main 实测 true）。领先默认分支数只对非默认分支有意义。 */
    val isDefault: Boolean = false,
) {
    /**
     * 这条分支是不是「可以合进默认分支」。判据**逐字对齐引擎**
     * `flow/dashboard.cj:206-209`：`ahead > 0 && !isDefault && !merged`，三条缺一不可：
     *   · `aheadOfDefault > 0` —— 相对默认分支的领先数（**不是** pendingCommits：
     *     那是「引擎还没记录的提交数」，刚跑过 update 恒为 0，与能不能合无关——
     *     引擎专门写回归测试把 mergeCandidates 从 pendingCommits 改成 aheadOfDefault）；
     *   · `!isDefault` —— 默认分支不需要合进自己；
     *   · `!merged` —— 已经合过的分支不再提示。
     * mac 基准 Models.swift:229-231 同款派生属性（提成有名字的属性防三处抄三份漂移）。
     */
    val isMergeCandidate: Boolean get() = aheadOfDefault > 0 && !isDefault && !merged
}

@Serializable
@Immutable
data class JournalEntry(
    val hash: String = "",
    val hashShort: String = "",
    val date: String = "",
    val subject: String = "",
    val body: String = "",
    val files: List<String> = emptyList(),
)

@Serializable
@Immutable
data class CommitTypeCount(
    val kind: String = "",
    val count: Long = 0,
)

// ── dashboard --json ──

@Serializable
@Immutable
data class DashboardData(
    val projects: DashProjects = DashProjects(),
    val work: DashWork = DashWork(),
    val languages: List<LangCount> = emptyList(),
    val languagesTruncated: Boolean? = null,
    val languagesTopCut: Boolean? = null,
    val languagesFailed: Long = 0,
    val languagesFailedReasons: List<String> = emptyList(),
    val milestones: DashMilestones = DashMilestones(),
    val activeProjects: List<ActiveProject> = emptyList(),
    val fetchedAt: String = "",
)

@Serializable
@Immutable
data class DashProjects(
    val total: Long = 0,
    val readable: Long = 0,
    val failed: Long = 0,
    val degraded: Long = 0,
)

@Serializable
@Immutable
data class DashWork(
    val dirty: Long = 0,
    val untracked: Long = 0,
    val conflicts: Long = 0,
    val branchCount: Long = 0,
    val branchCountTruncated: Boolean? = null,
)

@Serializable
@Immutable
data class LangCount(
    val language: String = "",
    val count: Long = 0,
)

@Serializable
@Immutable
data class DashMilestones(
    val counts: MilestoneCounts = MilestoneCounts(),
    val storeHealth: String = "",
)

@Serializable
@Immutable
data class MilestoneCounts(
    val open: Long = 0,
    val done: Long = 0,
    val dropped: Long = 0,
    val unverifiable: Long = 0,
    val engineRead: Long = 0,
)

@Serializable
@Immutable
data class ActiveProject(
    val id: String = "",
    val name: String = "",
    val headline: String? = null,
)

// ── milestone list --json ──

@Serializable
@Immutable
data class MilestoneList(
    val milestones: List<Milestone> = emptyList(),
    val storeHealth: String = "",
    val readCount: Long = 0,
    val orphaned: List<OrphanedMilestone> = emptyList(),
    val excludedDisabled: Long = 0,
)

@Serializable
@Immutable
data class Milestone(
    val projectId: String = "",
    /** 引擎恒发（fixtures/milestones.json + 2026-11 真机 `milestone list --json` 实测）：
     *  里程碑页按项目分组/筛选的展示名直接用它，不必再拿 status 的注册表反查。
     *  孤儿条目（项目已不在册）引擎也给这个名字——不丢。 */
    val projectName: String = "",
    val name: String = "",
    /** null = 缺键（旧引擎或该路径不写）；空串与缺键 UI 上都渲染成「无描述」。 */
    val description: String? = null,
    val targetDate: String = "",
    val tag: String = "",
    /** open / done / dropped / unknown；null = 缺键（无法核验）。 */
    val status: String? = null,
    val createdAt: String = "",
    /** 达成时间。⚠️ 引擎键名是 completedAt（真机 + fixture 实测；mac Models.swift:766 同款）——
     *  原镜像误写成 doneAt，ignoreUnknownKeys 把真键吞掉、本字段恒 null，
     *  「达成于 …」一行从来没显示过。空串 = 未达成。 */
    val completedAt: String = "",
)

@Serializable
@Immutable
data class OrphanedMilestone(
    val projectId: String = "",
    val name: String = "",
    val reason: String = "",
)

// ── milestone add / action / remove 回执 ──

@Serializable
@Immutable
data class MilestoneAddReceipt(
    val project: String = "",
    val milestone: String = "",
    val created: Boolean = false,
)

@Serializable
@Immutable
data class MilestoneActionReceipt(
    val project: String = "",
    val milestone: String = "",
    val requested: String = "",
    val status: String = "",
    val applied: Boolean = false,
)

@Serializable
@Immutable
data class MilestoneRemoveReceipt(
    val project: String = "",
    val milestone: String = "",
    val removed: Boolean = false,
)

// ── docs <name> --json ──

@Serializable
@Immutable
data class DocsPayload(
    val project: String = "",
    val docs: List<DocContent> = emptyList(),
    val unreadable: List<UnreadableDocs> = emptyList(),
)

@Serializable
@Immutable
data class DocContent(
    val project: String = "",
    val file: String = "",
    val content: String = "",
)

/** 实测形状：字符串数组（读不出来的文件名），非对象。 */
typealias UnreadableDocs = String

// ── journal <name> --json ──

@Serializable
@Immutable
data class JournalPayload(
    val entries: List<JournalEntry> = emptyList(),
    val limit: Long = 0,
    val branches: List<String> = emptyList(),
    val projects: List<String> = emptyList(),
    val unparsableLines: Long = 0,
    val windowExhausted: Boolean? = null,
    /** 实测形状：对象（分支维度的耗尽明细）；bool 是旧形状。用 JsonElement 容纳两种。 */
    val branchWindowExhausted: kotlinx.serialization.json.JsonElement? = null,
)

// ── git <op> <name> --json ──

@Serializable
@Immutable
data class GitOpResponse(
    val op: String = "",
    val ok: Boolean = false,
    val project: String = "",
    val output: String = "",
)

@Serializable
@Immutable
data class GitStatusPayload(
    val op: String = "",
    val ok: Boolean = false,
    val project: String = "",
    val output: String = "", // 内层 JSON 字符串：entries[{xy,file,kind}] / total
)

@Serializable
@Immutable
data class GitEntry(
    val xy: String = "",
    val file: String = "",
    val kind: String = "",
)

// ── update / deep <name> --json --quiet ──

@Serializable
@Immutable
data class UpdateReceipt(
    val ok: Boolean = false,
    val mode: String = "",
    val projectId: String = "",
    val project: String = "",
    val provider: String = "",
    val providerLabel: String = "",
    val branchCount: Long = 0,
    val repoBranchCount: Long = 0,
    val branchCountTruncated: Boolean? = null,
    val commitCount: Long = 0,
    val commitCountTruncated: Boolean? = null,
    val docs: List<DocChange> = emptyList(),
    /** CONTRACT §2.4：journal 条目对象或 null（曾误镜像成 Boolean，真机 vtest 回现修正，2026-11）。
     *  「本轮是否写了日志」= journalEntry != null，不得回退成布尔理解。 */
    val journalEntry: JournalEntryRecord? = null,
    val highlights: List<String>? = null,
    val at: String = "",
)

@Serializable
@Immutable
data class DocChange(
    val file: String = "",
    val changed: Boolean = false,
    val created: Boolean = false,
    val backup: String = "",
)

/** update / deep 回执里的 journal 条目（CONTRACT §2.4：journalEntryJson 唯一形状，全部出口一致）。
 *  基准：deepin/src/models/StatusTypes.h 的 JournalEntry + 真机浅更新实测 fixtures/update.json
 *  （此前 fixtures 缺 update 回执，本字段曾无基准凭空镜像成 Boolean——教训：镜像必须有 fixture 锚）。
 *  【缺键纪律】全部字段可缺席；-1 哨兵照传不吞（null = 引擎没发这个键）。 */
@Serializable
@Immutable
data class JournalEntryRecord(
    val id: String = "",
    val at: String = "",
    val project: String = "",
    val projectId: String = "",
    val branch: String = "",
    /** shallow / deep / track / manual（引擎侧枚举）。 */
    val mode: String = "",
    val source: String = "",
    val provider: String = "",
    val providerLabel: String = "",
    /** -1 = 读不出来（引擎既定哨兵）。 */
    val commitCount: Long? = null,
    /** new = 本轮新增 | repoTotal = 仓库总数。 */
    val commitCountScope: String = "",
    /** 缺键 = null ≠ false（不许把「引擎没发」当成「没截断」）。 */
    val commitCountTruncated: Boolean? = null,
    /** -1 = 未知。 */
    val repoBranchCount: Long? = null,
    val branchCountTruncated: Boolean? = null,
    val summary: String = "",
    val highlights: List<String> = emptyList(),
    val nextSteps: List<String> = emptyList(),
    val notes: List<String> = emptyList(),
    /** 契约称仅 deep 条目有；真机浅更新 fixture 实测也带——nullable 两种都容。 */
    val docs: List<String>? = null,
)

/**
 * update / deep 的全项目聚合信封：逐项目成败在 results[]（客户端曾读错键 projects 的教训）。
 *
 * ⚠️ results 是**二态异构数组**（2026-11 真机实测锚定，fixtures/update_all*.json 原样落盘）：
 *   · 成功/单仓库回执：`{ok,mode,project,docs:[…],journalEntry:…}`（[UpdateReceipt]）；
 *   · 失败记录：`{code,message}`——**没有 ok/project 键**（试验：注册 vtestfail 后删其目录，
 *     引擎发 `{"code":"VOLUME_BLOCKED","message":"vtestfail 更新失败：路径不存在或卷未挂载：…"}`）。
 *     镜像成统一的 UpdateReceipt 会把 message（失败原因）整个吞掉——那正是结果面板
 *     唯一要给用户看的东西。这里用 JsonElement 容纳两种形状，[decodeUpdateOutcome] 二态分发。
 * 顶层另有引擎自己记的账：count/failed/succeeded（客户端逐条计数与它分叉时必须披露）。
 */
@Serializable
@Immutable
data class MultiResults(
    val results: List<JsonElement> = emptyList(),
    val count: Long = 0,
    val failed: Long = 0,
    val succeeded: Long = 0,
)

/** results[] 的失败条目（真机实测形状：只有 code + message，两个键都可缺席防御）。 */
@Serializable
@Immutable
data class UpdateFailure(
    val code: String = "",
    val message: String = "",
)

/** results[] 条目的解码终态：成功回执 / 失败记录（二态异构，见 [MultiResults] 注释）。 */
sealed interface UpdateOutcome {
    data class Success(val receipt: UpdateReceipt) : UpdateOutcome
    data class Failure(val failure: UpdateFailure) : UpdateOutcome
}

/**
 * 二态解码（纯函数）：有 `ok` 键 → 成功回执；否则按失败记录（code/message）。
 * 两者都不成立（非对象 / 缺 ok 且无内容）→ 也归失败并如实说明形状不可识别——
 * **不编造成成功**（把读不懂的东西标成 ok 比空着更糟）。
 */
fun decodeUpdateOutcome(el: JsonElement): UpdateOutcome {
    val obj = el as? JsonObject
        ?: return UpdateOutcome.Failure(UpdateFailure("UNPARSABLE", "results 条目不是对象：${el.toString().take(80)}"))
    return if ("ok" in obj) {
        UpdateOutcome.Success(contractJson.decodeFromJsonElement(UpdateReceipt.serializer(), el))
    } else {
        UpdateOutcome.Failure(contractJson.decodeFromJsonElement(UpdateFailure.serializer(), el))
    }
}

// ── scan / add / remove ──

/** scan 回执的候选项目（真机实测：found 个对象的数组；引擎不在此区分新增/已在册，
 *  聚合数 added/existing 另发——逐项目归属由客户端对照扫描前在册集推导，见 ui/ScanSheet.kt）。 */
@Serializable
@Immutable
data class ScanCandidate(
    val name: String = "",
    val path: String = "",
    val kind: String = "",
    val remote: String = "",
)

/** 真机实测形状（fixtures/scan.json，2026-11 真跑锚定）：
 *  candidates = 对象数组；unreadable = 读不出来的目录**路径数组**（不是计数——计数取 .size）。
 *  此前镜像成两个 Long（无 fixture 凭空镜像），真机 scan 一跑解码即失败——按教训修回真实形状。 */
@Serializable
@Immutable
data class ScanPayload(
    val candidates: List<ScanCandidate> = emptyList(),
    val found: Long = 0,
    val added: Long = 0,
    val existing: Long = 0,
    val dirsVisited: Long = 0,
    val truncated: Boolean? = null,
    val depthCapped: Boolean? = null,
    val unreadable: List<String> = emptyList(),
    val depth: Long = 0,
)

@Serializable
@Immutable
data class RegistryEntry(
    val id: String = "",
    val name: String = "",
    val path: String = "",
    val kind: String = "",
    val remote: String = "",
    val addedAt: String = "",
    val tags: List<String> = emptyList(),
    val disabled: Boolean = false,
)

// ── graph confidence <项目> --json ──
//
// 形状锚定：fixtures/confidence/confidence.json（2026-11 真机 moongit 真跑，
// vtest 播种 suspect.py 后的输出）。
// 【与 mac 注释的差异，如实标注】mac ConfidencePageVM 读 dimensions 的 "detail" 键——
// 本机引擎不发 detail，发的是 penalty（罚分）+ findings（条数）；以实测为准展示后者。

@Serializable
@Immutable
data class ConfidenceReport(
    val root: String = "",
    /** 0..100（100 = 未发现结构性疑点；结构性汇总，非正确性证明——semantics 恒发）。 */
    val score: Long = 0,
    /** 引擎只发有疑点的维度（真机 fixture 3/6 个）；六维度全集见引擎 ConfDimension。 */
    val dimensions: List<ConfDimensionScore> = emptyList(),
    val penaltyByFile: List<ConfPenaltyFile> = emptyList(),
    /** 引擎已按权重降序全序排列（sortFindings 契约）。 */
    val findings: List<ConfFinding> = emptyList(),
    val byKind: List<ConfKindCount> = emptyList(),
    val astUsed: Boolean = false,
    /** 降级/覆盖披露（非空必展示，不许静默）。 */
    val astNote: String = "",
    /** 限流披露恒发（真值来自丢弃判定点，不是结果集反推）。 */
    val cappedKind: Boolean = false,
    val cappedTotal: Boolean = false,
    val filesAnalyzed: Long = 0,
    val semantics: String = "",
)

@Serializable
@Immutable
data class ConfDimensionScore(
    /** variable / function / type / pointer / concurrency / structure。 */
    val id: String = "",
    val label: String = "",
    val penalty: Long = 0,
    val findings: Long = 0,
    val score: Long = 0,
)

@Serializable
@Immutable
data class ConfPenaltyFile(
    val file: String = "",
    val penalty: Long = 0,
)

@Serializable
@Immutable
data class ConfFinding(
    val kind: String = "",
    val file: String = "",
    val line: Long = 0,
    val symbol: String = "",
    val evidence: String = "",
    val weight: Long = 0,
)

@Serializable
@Immutable
data class ConfKindCount(
    val kind: String = "",
    val label: String = "",
    val count: Long = 0,
    val weight: Long = 0,
)

// ── graph patchconf <项目> --patch <diff> --json（Layer 1 算法层）──
//
// 形状锚定：fixtures/confidence/patchconf_algorithm.json（真机真跑）。

@Serializable
@Immutable
data class PatchConfidence(
    val schema: String = "",
    /** 0..1（实体置信度均值；null 信号不计入）。 */
    val overall: Double = 0.0,
    /** S1..S10；null = 词法层无法可靠计算（分母为 0），不进 overall——必须如实披露。 */
    val signals: Map<String, Double?> = emptyMap(),
    val entities: List<PatchEntity> = emptyList(),
    val uncertain: List<PatchUncertain> = emptyList(),
    val diagnostics: PatchDiagnostics = PatchDiagnostics(),
)

@Serializable
@Immutable
data class PatchEntity(
    val id: String = "",
    val kind: String = "",
    val confidence: Double = 0.0,
    val file: String = "",
    val line: Long = 0,
    val relations: List<PatchRelation> = emptyList(),
)

@Serializable
@Immutable
data class PatchRelation(
    val type: String = "",
    val target: String = "",
    val confidence: Double = 0.0,
)

@Serializable
@Immutable
data class PatchUncertain(
    val id: String = "",
    val issue: String = "",
    val detail: String = "",
    val candidates: List<String> = emptyList(),
    @SerialName("context_ref")
    val contextRef: PatchContextRef? = null,
)

@Serializable
@Immutable
data class PatchContextRef(
    val file: String = "",
    val line: Long = 0,
)

@Serializable
@Immutable
data class PatchDiagnostics(
    @SerialName("total_entities")
    val totalEntities: Long = 0,
    @SerialName("total_relations")
    val totalRelations: Long = 0,
    @SerialName("parse_errors")
    val parseErrors: Long = 0,
    @SerialName("patch_files")
    val patchFiles: Long = 0,
    @SerialName("added_lines")
    val addedLines: Long = 0,
    @SerialName("null_signals")
    val nullSignals: List<String> = emptyList(),
    @SerialName("null_signals_note")
    val nullSignalsNote: String = "",
)

// ── graph patchconf --merge <alg> <agent> --json（Layer 3 终稿）──
//
// 形状锚定：fixtures/confidence/patchconf_merged.json（真机真跑）。
// 【与 mac 注释的差异，如实标注】mac finalCard 读顶层 "reviewed" 与 alerts 的 "issue" 键——
// 本机引擎实测：复核计数在 diagnostics.reviewed_by_agent；alerts 键集是
// {level, type, detail}（无 issue）。以实测为准，issue 键仍容（缺席回退 type）。

@Serializable
@Immutable
data class MergedConfidence(
    val schema: String = "",
    val overall: Double = 0.0,
    val signals: Map<String, Double?> = emptyMap(),
    /** 算法层实体（source=algorithm）+ 裁决过的 uncertain（source=agent/deferred）。 */
    val entities: List<MergedEntity> = emptyList(),
    val alerts: List<MergedAlert> = emptyList(),
    val sources: MergedSources = MergedSources(),
    val diagnostics: MergedDiagnostics = MergedDiagnostics(),
)

/** 合并实体的键并集（algorithm 分支与 agent 分支字段不同，一律 nullable）。 */
@Serializable
@Immutable
data class MergedEntity(
    val id: String = "",
    val kind: String? = null,
    val confidence: Double = 0.0,
    val file: String? = null,
    val line: Long? = null,
    /** uncertain 合并来的字段（algorithm 实体缺席）。 */
    val issue: String? = null,
    val source: String = "",
    val verdict: String? = null,
    val reason: String? = null,
    @SerialName("context_ref")
    val contextRef: PatchContextRef? = null,
)

@Serializable
@Immutable
data class MergedAlert(
    /** high / medium / low。 */
    val level: String = "",
    /** 引擎实测键是 type（mac 读的 issue 键缺席）；容两个键，展示时 issue 优先。 */
    val type: String = "",
    val issue: String? = null,
    val detail: String = "",
)

@Serializable
@Immutable
data class MergedSources(
    val algorithm: Boolean = false,
    val agent: Boolean = false,
)

@Serializable
@Immutable
data class MergedDiagnostics(
    @SerialName("certain_from_algorithm")
    val certainFromAlgorithm: Long = 0,
    @SerialName("reviewed_by_agent")
    val reviewedByAgent: Long = 0,
    @SerialName("deferred")
    val deferred: Long = 0,
)

/** Layer 2 人工裁决载荷（--merge 的 agent 侧输入；mac verdicts 映射的对位）。 */
@Serializable
@Immutable
data class AgentVerdict(
    val id: String,
    /** resolved / unresolved / ambiguous。 */
    val verdict: String,
    val confidence: Double,
    val reason: String,
)

@Serializable
@Immutable
data class AgentPayload(
    val items: List<AgentVerdict> = emptyList(),
)
