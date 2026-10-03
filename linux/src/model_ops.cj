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
    public let summary: String

    public init(
        id: String, at: String, branch: String, mode: String, source: String,
        provider: String, commitCount: Int64, commitCountScope: String, summary: String
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
    }

    /// 「本次记录 N 个提交」里 N 的写法。
    ///
    /// `commitCountScope` 是引擎给的统计口径（`all` / `branch` 等），
    /// 拿它出来是必要的 —— 不写口径的话，「8 个提交」在不同口径下
    /// 含义不同，读者会以为自己记错了。
    public func commitText(): String {
        if (this.commitCountScope == "") {
            return "${this.commitCount} 个提交"
        }
        return "${this.commitCount} 个提交（口径 ${this.commitCountScope}）"
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
            Json.strAt(v, "summary", "")
        )
    }
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
