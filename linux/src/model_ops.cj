// deepDolphin Linux 客户端 —— 写操作与详情页的载荷模型。
//
// 键名全部对着**引擎真实输出**核过一遍（不是照着 macOS 的 Swift 抄，
// 也不是照着文档想）。上一轮凭空写了个 `activity` 字段，引擎根本不发，
// 于是每个项目都显示「未知」—— 这种事只能靠取真实载荷来避免。
package deepdolphin_linux

import std.collection.*

// ---------------------------------------------------------------------------
// C9 里程碑
// ---------------------------------------------------------------------------

public class Milestone {
    public let projectId: String
    public let projectName: String
    public let name: String
    public let description: String
    public let targetDate: String
    public let tag: String
    public let status: String
    public let createdAt: String
    public let completedAt: String
    /// 绑定的 tag 已达成（引擎算的，客户端不推断）。
    public let tagReached: Bool
    public let commitsSince: Int64
    /// 提交数读不出来时为 false —— 那时 commitsSince 没有意义，
    /// 跟「0 个提交」是两回事。
    public let commitsSinceReadable: Bool
    public let daysToTarget: Int64
    public let id: String

    public init(
        projectId: String, projectName: String, name: String, description: String,
        targetDate: String, tag: String, status: String, createdAt: String, completedAt: String,
        tagReached: Bool, commitsSince: Int64, commitsSinceReadable: Bool, daysToTarget: Int64, id: String
    ) {
        this.projectId = projectId
        this.projectName = projectName
        this.name = name
        this.description = description
        this.targetDate = targetDate
        this.tag = tag
        this.status = status
        this.createdAt = createdAt
        this.completedAt = completedAt
        this.tagReached = tagReached
        this.commitsSince = commitsSince
        this.commitsSinceReadable = commitsSinceReadable
        this.daysToTarget = daysToTarget
        this.id = id
    }

    public func isDone(): Bool {
        return this.status == "done"
    }

    public static func from(v: JsonValue): Milestone {
        return Milestone(
            Json.strAt(v, "projectId", ""),
            Json.strAt(v, "projectName", ""),
            Json.strAt(v, "name", ""),
            Json.strAt(v, "description", ""),
            Json.strAt(v, "targetDate", ""),
            Json.strAt(v, "tag", ""),
            Json.strAt(v, "status", "open"),
            Json.strAt(v, "createdAt", ""),
            Json.strAt(v, "completedAt", ""),
            Json.boolAt(v, "tagReached", false),
            Json.intAt(v, "commitsSince", 0),
            Json.boolAt(v, "commitsSinceReadable", true),
            Json.intAt(v, "daysToTarget", 0),
            Json.strAt(v, "id", "")
        )
    }
}

public class MilestoneSnapshot {
    public let milestones: ArrayList<Milestone>
    /// 进度库里读不出来 / 孤儿 / 被禁用项目排除掉的条目数。
    public let readCount: Int64
    public let orphaned: Int64
    public let excludedDisabled: Int64
    public let storeHealth: String

    public init(
        milestones: ArrayList<Milestone>,
        readCount: Int64,
        orphaned: Int64,
        excludedDisabled: Int64,
        storeHealth: String
    ) {
        this.milestones = milestones
        this.readCount = readCount
        this.orphaned = orphaned
        this.excludedDisabled = excludedDisabled
        this.storeHealth = storeHealth
    }

    public func openOnes(): ArrayList<Milestone> {
        let out = ArrayList<Milestone>()
        for (m in this.milestones) {
            if (!m.isDone()) {
                out.add(m)
            }
        }
        return out
    }

    public func doneOnes(): ArrayList<Milestone> {
        let out = ArrayList<Milestone>()
        for (m in this.milestones) {
            if (m.isDone()) {
                out.add(m)
            }
        }
        return out
    }

    public static func from(v: JsonValue): MilestoneSnapshot {
        let ms = ArrayList<Milestone>()
        for (m in Json.arrAt(v, "milestones")) {
            ms.add(Milestone.from(m))
        }
        return MilestoneSnapshot(
            ms,
            Json.intAt(v, "readCount", 0),
            Json.intAt(v, "orphaned", 0),
            Json.intAt(v, "excludedDisabled", 0),
            Json.strAt(v, "storeHealth", "")
        )
    }
}

// ---------------------------------------------------------------------------
// C3 文档
// ---------------------------------------------------------------------------

public class DocFile {
    public let file: String
    public let content: String
    /// 读不出内容（权限 / 不是 UTF-8）。非空时**不能**显示成「文档为空」。
    public let unreadableReason: String

    public init(file: String, content: String, unreadableReason: String) {
        this.file = file
        this.content = content
        this.unreadableReason = unreadableReason
    }

    public static func from(v: JsonValue): DocFile {
        return DocFile(
            Json.strAt(v, "file", ""),
            Json.strAt(v, "content", ""),
            Json.strAt(v, "unreadable", "")
        )
    }
}

public class DocBundle {
    public let project: String
    public let docs: ArrayList<DocFile>
    /// 引擎报告读不出来的文档名。
    public let unreadable: ArrayList<String>

    public init(project: String, docs: ArrayList<DocFile>, unreadable: ArrayList<String>) {
        this.project = project
        this.docs = docs
        this.unreadable = unreadable
    }

    public static func from(v: JsonValue): DocBundle {
        let ds = ArrayList<DocFile>()
        for (d in Json.arrAt(v, "docs")) {
            ds.add(DocFile.from(d))
        }
        return DocBundle(
            Json.strAt(v, "project", ""),
            ds,
            Json.strArrAt(v, "unreadable")
        )
    }
}

// ---------------------------------------------------------------------------
// C3 日志
// ---------------------------------------------------------------------------

public class JournalEntry {
    public let id: String
    public let at: String
    public let branch: String
    public let mode: String
    public let source: String
    public let provider: String
    public let commitCount: Int64
    public let commitCountScope: String
    /// 这条提交数是不是采样值。
    ///
    /// ⚠ 实测 journal entry **没有**这个键（真实 57 条的键集是
    /// id/at/project/projectId/branch/mode/source/provider/commitCount/
    /// summary/highlights/nextSteps/notes/providerLabel），
    /// 所以它恒为 false。字段留着是因为契约里给了位置，
    /// 引擎哪天补上时披露已经就位。
    public let truncated: Bool
    public let summary: String

    public init(
        id: String, at: String, branch: String, mode: String, source: String,
        provider: String, commitCount: Int64, commitCountScope: String, summary: String,
        truncated!: Bool = false
    ) {
        this.id = id
        this.at = at
        this.branch = branch
        this.mode = mode
        this.source = source
        this.provider = provider
        this.commitCount = commitCount
        this.commitCountScope = commitCountScope
        this.summary = summary
        this.truncated = truncated
    }

    /// 「本次记录 N 个提交」里 N 的写法。
    ///
    /// ⚠⚠ 这里原先的注释写着「`commitCountScope` 是引擎给的统计口径
    /// （`all` / `branch` 等）」—— **那个词汇表不存在**。实测本机
    /// `journal --json` 的 57 条 entry **根本没有 `commitCountScope` 这个键**，
    /// 而 macOS 端 `CommitCountScope.swift` 记录的两个真实取值是
    /// `new` / `repoTotal`。三方对不上，所以下面按 macOS 的规则重写：
    /// **认不出就认不出，不许默认成任何一种。**
    ///
    /// 引擎侧缺陷 #188：`commitCount` 在两条路径上装的是不同的东西 ——
    /// 浅更新 = 本轮真正新记录的提交数，深更新 = 仓库提交总数（无上限）。
    /// 引擎的注释写明「靠 mode 字段去猜口径不行：那是约定不是契约」。
    ///
    /// 症状：日志里一个「本轮新增 6」和一个「仓库一共 6 个」渲染成两个
    /// 一模一样的 `6 个提交`，读者会得出「深更新也新增了 6 个」——
    /// 而那个数会随仓库一直涨。
    public func commitText(): String {
        let b = commitCountBadge(this.commitCount, this.commitCountScope, this.truncated)
        if (b.text.isEmpty()) {
            return ""
        }
        return b.text
    }

    /// 与 `commitText` 配套的补充说明（空串 = 无）。
    public func commitNote(): String {
        return commitCountBadge(this.commitCount, this.commitCountScope, this.truncated).note
    }

    public static func from(v: JsonValue): JournalEntry {
        return JournalEntry(
            Json.strAt(v, "id", ""),
            Json.strAt(v, "at", ""),
            Json.strAt(v, "branch", ""),
            Json.strAt(v, "mode", ""),
            Json.strAt(v, "source", ""),
            Json.strAt(v, "provider", ""),
            Json.intAt(v, "commitCount", 0),
            Json.strAt(v, "commitCountScope", ""),
            Json.strAt(v, "summary", ""),
            truncated: Json.boolAt(v, "commitCountTruncated", false)
        )
    }
}

/// journal 条目里那个 `+N` 的**口径**。纯函数。
///
/// 四种状态必须分开，合并任何两个都会撒谎：
/// 口径、读不出来、零、口径未知。
public enum CommitScope {
    | NewCommits   // 本轮新增
    | RepoTotal    // 仓库提交总数
    | Unknown      // 口径没标出来 —— **不能**默认成上面任何一个
    | Unreadable   // -1，整个数字没意义
}

public class CommitCountBadge {
    /// 空串 = 不显示徽章（0 个提交不是一条值得占位的信息）。
    public let text: String
    public let scope: CommitScope
    /// 必须写进界面的补充说明；空串 = 无。
    public let note: String

    public init(text: String, scope: CommitScope, note: String) {
        this.text = text
        this.scope = scope
        this.note = note
    }
}

public func commitScopeOf(raw: String, commitCount: Int64): CommitScope {
    // 读不出来绝不能显示成 0 —— -1 是「整个数字没意义」，不是「没提交」。
    if (commitCount < 0) {
        return CommitScope.Unreadable
    }
    if (raw == "new") {
        return CommitScope.NewCommits
    }
    if (raw == "repoTotal") {
        return CommitScope.RepoTotal
    }
    return CommitScope.Unknown
}

private func commitScopeSuffix(s: CommitScope): String {
    return match (s) {
        case CommitScope.NewCommits => "新增"
        case CommitScope.RepoTotal => "累计"
        case CommitScope.Unknown => "口径未知"
        case CommitScope.Unreadable => "读不出来"
    }
}

/// 口径不是「本轮新增」时**不能**继续用增量绿 ——
/// 绿 + 无限定词 = 「这次变好了这么多」，那是把累计量说成增量。
public func commitScopeIsIncremental(s: CommitScope): Bool {
    return match (s) {
        case CommitScope.NewCommits => return true
        case _ => return false
    }
}

/// `+N` 该显示成什么。**纯函数**。
///
/// ⚠ `truncated` 走 `Bool` 而不是三态：实测 journal entry **没有**截断标志
/// （键只有 id/at/project/projectId/branch/mode/source/provider/commitCount/
/// summary/highlights/nextSteps/notes/providerLabel），传 nil 时这一轴不响。
/// 别为了「与 macOS 签名一致」把它编成三态。
public func commitCountBadge(commitCount: Int64, scope: String, truncated: Bool): CommitCountBadge {
    let s = commitScopeOf(scope, commitCount)

    if (match (s) { case CommitScope.Unreadable => true; case _ => false }) {
        return CommitCountBadge("提交数读不出来", s, "不是「这轮没有提交」")
    }
    // 0 不是徽章要表达的事
    if (commitCount == 0) {
        return CommitCountBadge("", s, "")
    }

    let notes = ArrayList<String>()
    if (match (s) { case CommitScope.Unknown => true; case _ => false }) {
        notes.add("这条的提交数口径没标出来，无法判断是本轮新增还是仓库累计")
    }
    if (truncated) {
        notes.add("这是采样值，不是全量")
    }
    var note = ""
    if (!notes.isEmpty()) {
        note = joinList(notes.toArray())
    }
    return CommitCountBadge("+${commitCount} ${commitScopeSuffix(s)}", s, note)
}

public class Journal {
    public let entries: ArrayList<JournalEntry>
    public let limit: Int64
    public let windowExhausted: Bool
    public let unparsableLines: Int64

    public init(entries: ArrayList<JournalEntry>, limit: Int64, windowExhausted: Bool, unparsableLines: Int64) {
        this.entries = entries
        this.limit = limit
        this.windowExhausted = windowExhausted
        this.unparsableLines = unparsableLines
    }

    /// 日志被截断时必须说出来。
    ///
    /// 只显示最近 N 条而不说「还有更多」，用户会以为这就是全部，
    /// 进而得出「这个项目最近只更新过 N 次」这种**看起来很确定**的错结论。
    public func truncatedNote(): String {
        if (this.windowExhausted) {
            return "日志已截断（上限 ${this.limit} 条），这不是全部历史"
        }
        return ""
    }

    /// 解析不了的行数要说出来，而且**措辞不许含糊**。
    ///
    /// 与 macOS 端 `DetailViews.swift:717` 同一条：
    /// 「有 N 行读不出来」和「日志到此为止」是两件完全不同的事 ——
    /// 前者意味着**中间有内容你看漏了**，后者意味着没有更多了。
    /// 写成一句「部分日志不可用」会把这两者糊在一起，而用户会
    /// 以为那条分界线就是历史的终点。
    ///
    /// ⚠ 这是**防御性**通路：本机 `journal --json` 实测
    /// `unparsableLines: 0`。留着是因为字段在契约里，
    /// 引擎哪次换了日志格式它就会变成非 0，而那时界面必须已经会说这句话。
    public func unparsableNote(): String {
        if (this.unparsableLines > 0) {
            return "另有 ${this.unparsableLines} 行日志解析不了（不是「日志到此为止」）"
        }
        return ""
    }

    public static func from(v: JsonValue): Journal {
        let es = ArrayList<JournalEntry>()
        for (e in Json.arrAt(v, "entries")) {
            es.add(JournalEntry.from(e))
        }
        return Journal(
            es,
            Json.intAt(v, "limit", 0),
            Json.boolAt(v, "windowExhausted", false),
            Json.intAt(v, "unparsableLines", 0)
        )
    }
}

// ---------------------------------------------------------------------------
// C4 更新结果
// ---------------------------------------------------------------------------

public class DocOutcome {
    public let file: String
    public let changed: Bool
    public let created: Bool
    public let backup: String

    public init(file: String, changed: Bool, created: Bool, backup: String) {
        this.file = file
        this.changed = changed
        this.created = created
        this.backup = backup
    }

    public static func from(v: JsonValue): DocOutcome {
        return DocOutcome(
            Json.strAt(v, "file", ""),
            Json.boolAt(v, "changed", false),
            Json.boolAt(v, "created", false),
            Json.strAt(v, "backup", "")
        )
    }
}

public class UpdateOutcome {
    public let ok: Bool
    public let mode: String
    public let project: String
    public let providerLabel: String
    public let branchCount: Int64
    public let branchCountTruncated: Bool
    public let commitCount: Int64
    public let docs: ArrayList<DocOutcome>
    public let at: String

    public init(
        ok: Bool, mode: String, project: String, providerLabel: String,
        branchCount: Int64, branchCountTruncated: Bool, commitCount: Int64,
        docs: ArrayList<DocOutcome>, at: String
    ) {
        this.ok = ok
        this.mode = mode
        this.project = project
        this.providerLabel = providerLabel
        this.branchCount = branchCount
        this.branchCountTruncated = branchCountTruncated
        this.commitCount = commitCount
        this.docs = docs
        this.at = at
    }

    /// 逐文件结果的一行摘要。
    ///
    /// 与 macOS 端同一条纪律：**备份路径要一并说**。引擎改了用户手写的
    /// README/AGENTS，用户第一反应是「我写的东西呢」，
    /// 答案（备份在哪）必须在这条摘要里，而不是藏在日志里。
    public func summaryLine(): String {
        let changed = this.changedDocs()
        if (changed.isEmpty()) {
            return "文档没有变化"
        }
        let parts = ArrayList<String>()
        for (d in changed) {
            let verb = if (d.created) { "新建" } else { "改写" }
            parts.add("${verb} ${d.file}")
        }
        let withBackup = changed[0]
        let tail = if (withBackup.backup.isEmpty()) { "" } else { "（备份：${withBackup.backup}）" }
        return "${joinAll(parts.toArray(), "、")}${tail}"
    }

    public func changedDocs(): ArrayList<DocOutcome> {
        let out = ArrayList<DocOutcome>()
        for (d in this.docs) {
            if (d.changed || d.created) {
                out.add(d)
            }
        }
        return out
    }

    public static func from(v: JsonValue): UpdateOutcome {
        let ds = ArrayList<DocOutcome>()
        for (d in Json.arrAt(v, "docs")) {
            ds.add(DocOutcome.from(d))
        }
        return UpdateOutcome(
            Json.boolAt(v, "ok", false),
            Json.strAt(v, "mode", ""),
            Json.strAt(v, "project", ""),
            Json.strAt(v, "providerLabel", ""),
            Json.intAt(v, "branchCount", 0),
            Json.boolAt(v, "branchCountTruncated", false),
            Json.intAt(v, "commitCount", 0),
            ds,
            Json.strAt(v, "at", "")
        )
    }
}

// ---------------------------------------------------------------------------
// C8 git 结果
// ---------------------------------------------------------------------------

public class GitResult {
    public let op: String
    public let ok: Bool
    public let project: String
    /// git 的原始输出。**成功时也要显示** ——
    /// `pull` 说「Already up to date」与说有 3 个新提交，处理方式完全不同。
    public let output: String

    public init(op: String, ok: Bool, project: String, output: String) {
        this.op = op
        this.ok = ok
        this.project = project
        this.output = output
    }

    public static func from(v: JsonValue): GitResult {
        return GitResult(
            Json.strAt(v, "op", ""),
            Json.boolAt(v, "ok", false),
            Json.strAt(v, "project", ""),
            Json.strAt(v, "output", "")
        )
    }
}
