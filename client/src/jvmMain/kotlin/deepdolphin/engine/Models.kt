// Models.kt —— 引擎 --json 契约的唯一 Kotlin 镜像。
//
// 【键名纪律】键名以 fixtures（src/jvmTest/resources/fixtures/，取自真实引擎输出）
// 与 archive/bui 的 models.rs 为准，不许发明键。camelCase 全线一致。
// 【缺键纪律】「缺键 ≠ 零」：可缺席字段一律 nullable，-1 = 读不出来（引擎既定哨兵）。
// 失败项目仍是完整形状（error 有值、dirty/overall 是 {}），isReadable 判定。

package deepdolphin.engine

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
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
data class StatusEnvelope(
    val projects: List<Project> = emptyList(),
    val summary: Summary = Summary(),
    /** 引擎事实语言（zh / en）。缺键 = 不知道，不假设 zh。 */
    val language: String? = null,
)

@Serializable
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
}

@Serializable
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
data class Overall(
    val summary: String = "",
    val notes: List<String> = emptyList(),
)

@Serializable
data class MergeHint(
    val kind: String = "",
    val ahead: Long = 0,
    val behind: Long = 0,
    val defaultBranch: String = "",
    val target: String = "",
    val description: String = "",
)

@Serializable
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
data class DocEntry(
    val file: String = "",
    val exists: Boolean = false,
)

@Serializable
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
)

@Serializable
data class JournalEntry(
    val hash: String = "",
    val hashShort: String = "",
    val date: String = "",
    val subject: String = "",
    val body: String = "",
    val files: List<String> = emptyList(),
)

@Serializable
data class CommitTypeCount(
    val kind: String = "",
    val count: Long = 0,
)

// ── dashboard --json ──

@Serializable
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
data class DashProjects(
    val total: Long = 0,
    val readable: Long = 0,
    val failed: Long = 0,
    val degraded: Long = 0,
)

@Serializable
data class DashWork(
    val dirty: Long = 0,
    val untracked: Long = 0,
    val conflicts: Long = 0,
    val branchCount: Long = 0,
    val branchCountTruncated: Boolean? = null,
)

@Serializable
data class LangCount(
    val language: String = "",
    val count: Long = 0,
)

@Serializable
data class DashMilestones(
    val counts: MilestoneCounts = MilestoneCounts(),
    val storeHealth: String = "",
)

@Serializable
data class MilestoneCounts(
    val open: Long = 0,
    val done: Long = 0,
    val dropped: Long = 0,
    val unverifiable: Long = 0,
    val engineRead: Long = 0,
)

@Serializable
data class ActiveProject(
    val id: String = "",
    val name: String = "",
    val headline: String? = null,
)

// ── milestone list --json ──

@Serializable
data class MilestoneList(
    val milestones: List<Milestone> = emptyList(),
    val storeHealth: String = "",
    val readCount: Long = 0,
    val orphaned: List<OrphanedMilestone> = emptyList(),
    val excludedDisabled: Long = 0,
)

@Serializable
data class Milestone(
    val projectId: String = "",
    val name: String = "",
    /** null = 缺键（旧引擎或该路径不写）；空串与缺键 UI 上都渲染成「无描述」。 */
    val description: String? = null,
    val targetDate: String = "",
    val tag: String = "",
    /** open / done / dropped / unknown；null = 缺键（无法核验）。 */
    val status: String? = null,
    val createdAt: String = "",
    val doneAt: String? = null,
)

@Serializable
data class OrphanedMilestone(
    val projectId: String = "",
    val name: String = "",
    val reason: String = "",
)

// ── milestone add / action / remove 回执 ──

@Serializable
data class MilestoneAddReceipt(
    val project: String = "",
    val milestone: String = "",
    val created: Boolean = false,
)

@Serializable
data class MilestoneActionReceipt(
    val project: String = "",
    val milestone: String = "",
    val requested: String = "",
    val status: String = "",
    val applied: Boolean = false,
)

@Serializable
data class MilestoneRemoveReceipt(
    val project: String = "",
    val milestone: String = "",
    val removed: Boolean = false,
)

// ── docs <name> --json ──

@Serializable
data class DocsPayload(
    val project: String = "",
    val docs: List<DocContent> = emptyList(),
    val unreadable: List<UnreadableDocs> = emptyList(),
)

@Serializable
data class DocContent(
    val project: String = "",
    val file: String = "",
    val content: String = "",
)

/** 实测形状：字符串数组（读不出来的文件名），非对象。 */
typealias UnreadableDocs = String

// ── journal <name> --json ──

@Serializable
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
data class GitOpResponse(
    val op: String = "",
    val ok: Boolean = false,
    val project: String = "",
    val output: String = "",
)

@Serializable
data class GitStatusPayload(
    val op: String = "",
    val ok: Boolean = false,
    val project: String = "",
    val output: String = "", // 内层 JSON 字符串：entries[{xy,file,kind}] / total
)

@Serializable
data class GitEntry(
    val xy: String = "",
    val file: String = "",
    val kind: String = "",
)

// ── update / deep <name> --json --quiet ──

@Serializable
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
    val journalEntry: Boolean = false,
    val highlights: List<String>? = null,
    val at: String = "",
)

@Serializable
data class DocChange(
    val file: String = "",
    val changed: Boolean = false,
    val created: Boolean = false,
    val backup: String = "",
)

/** update / deep 的全项目聚合信封：逐项目成败在 results[]（客户端曾读错键 projects 的教训）。 */
@Serializable
data class MultiResults(
    val results: List<UpdateReceipt> = emptyList(),
)

// ── scan / add / remove ──

@Serializable
data class ScanPayload(
    val candidates: Long = 0,
    val found: Long = 0,
    val added: Long = 0,
    val existing: Long = 0,
    val dirsVisited: Long = 0,
    val truncated: Boolean? = null,
    val depthCapped: Boolean? = null,
    val unreadable: Long = 0,
    val depth: Long = 0,
)

@Serializable
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
