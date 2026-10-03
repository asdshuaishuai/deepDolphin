// deepDolphin Linux 客户端 —— 引擎载荷的模型层。
//
// 注意：这里是**唯一**与引擎耦合的地方：键名对不上，界面就会静默显示空值。
// 每个字段的缺省值都取「宁可显示 0 / 未知，也不要假装有数据」。
//
// 与 macOS 端同源的纪律：
//   - 失败的项目**留在列表里**并显示原因，不静默过滤 —— 过滤掉等于
//     「已注册 6 个」在界面上变成 3 个，用户无从知道少了什么。
//   - 披露字段不因数据缺失而消失。
package deepdolphin_linux

import std.collection.*

/// 一个分支的进度行。
public class Branch {
    public let name: String
    public let status: String
    public let statusLabel: String
    public let headShort: String
    public let headAgo: String
    public let headSubject: String
    public let summary: String
    public let isCurrent: Bool
    public let isDefault: Bool
    public let aheadOfDefault: Int64
    public let merged: Bool
    public let staleDays: Int64
    public let pendingCommits: Int64
    public let baselineReset: Bool

    public init(
        name: String,
        status: String,
        statusLabel: String,
        headShort: String,
        headAgo: String,
        headSubject: String,
        summary: String,
        isCurrent: Bool,
        isDefault: Bool,
        aheadOfDefault: Int64,
        merged: Bool,
        staleDays: Int64,
        pendingCommits: Int64,
        baselineReset: Bool
    ) {
        this.name = name
        this.status = status
        this.statusLabel = statusLabel
        this.headShort = headShort
        this.headAgo = headAgo
        this.headSubject = headSubject
        this.summary = summary
        this.isCurrent = isCurrent
        this.isDefault = isDefault
        this.aheadOfDefault = aheadOfDefault
        this.merged = merged
        this.staleDays = staleDays
        this.pendingCommits = pendingCommits
        this.baselineReset = baselineReset
    }

    public static func from(v: JsonValue): Branch {
        return Branch(
            Json.strAt(v, "name", "?"),
            Json.strAt(v, "status", ""),
            Json.strAt(v, "statusLabel", ""),
            Json.strAt(v, "headShort", ""),
            Json.strAt(v, "headAgo", ""),
            Json.strAt(v, "headSubject", ""),
            Json.strAt(v, "summary", ""),
            Json.boolAt(v, "isCurrent", false),
            Json.boolAt(v, "isDefault", false),
            Json.intAt(v, "aheadOfDefault", 0),
            Json.boolAt(v, "merged", false),
            Json.intAt(v, "staleDays", -1),
            Json.intAt(v, "pendingCommits", 0),
            Json.boolAt(v, "baselineReset", false)
        )
    }

    /// 待合入候选：领先默认分支、且不是默认分支本身、且没被合掉。
    /// 三条都要 —— 只看 `aheadOfDefault > 0` 会把默认分支自己也算进去。
    public func isMergeCandidate(): Bool {
        return this.aheadOfDefault > 0 && !this.isDefault && !this.merged
    }

    /// 停滞了几天。`-1` = **读不出来**，不是 0 天。
    public func staleText(): String {
        return (if (this.staleDays < 0) { "停滞天数读不出" } else { "停滞 ${this.staleDays} 天" })
    }
}

/// 一个已注册项目的现状。
public class Project {
    public let name: String
    public let path: String
    public let kind: String
    public let headline: String
    public let currentBranch: String
    public let defaultBranch: String
    public let remote: String

    /// 用户自己造成的未提交改动数（已排除引擎托管文档）。
    public let userDirtyCount: Int64
    public let untrackedCount: Int64
    public let stashCount: Int64
    public let worktreeCount: Int64
    public let commitCount: Int64
    public let branchCount: Int64
    /// 仓库里**真实**的分支数。`-1` = 读不出来。
    ///
    /// ⚠ 与 `branchCount` 是两回事：`branchCount` 是引擎**追踪到基线**的数量，
    /// 实测 16 个分支的仓库只报 7 个，刚注册还没 track 的报 0 —— 而仓库实际有分支。
    /// 字面写「分支进度（0）」会让人认定仓库没有分支。
    public let repoBranchCount: Int64
    /// 分支数被截断。截断时 branchCount **不是全量**。
    public let branchCountTruncated: Bool
    public let lastCommitAgo: String
    /// ISO 8601 原始串。**看板分列靠它算天数**（`lastCommitAgo` 是给人看的相对串）。
    public let lastCommitAt: String
    public let storeHealth: String

    /// 引擎采集这个项目时出的错。**非空就是失败项目**，界面必须显示出来。
    public let error: String

    public let branches: ArrayList<Branch>
    public let commitTypes: ArrayList<(String, Int64)>
    /// 引擎的**采样窗口**截断了提交类型（近 N 条 vs 全仓 M 条）。
    ///
    /// ⚠ 与「界面自己只列前 8 种」是**两条独立的轴**。
    /// 只披露一条就是撒谎：引擎给全量而界面藏起一半，读者会把
    /// 看到的 8 种当成这个项目的全部提交类型。
    public let commitTypesTruncated: Bool
    public let docs: ArrayList<String>
    public let progressEntryCount: Int64
    public let progressUpdatedAt: String
    public let warnings: ArrayList<String>
    public let overallSummary: String

    public init(
        name: String,
        path: String,
        kind: String,
        headline: String,
        currentBranch: String,
        defaultBranch: String,
        remote: String,
        userDirtyCount: Int64,
        untrackedCount: Int64,
        stashCount: Int64,
        worktreeCount: Int64,
        commitCount: Int64,
        branchCount: Int64,
        repoBranchCount: Int64,
        branchCountTruncated: Bool,
        lastCommitAgo: String,
        lastCommitAt: String,
        storeHealth: String,
        error: String,
        branches: ArrayList<Branch>,
        commitTypes: ArrayList<(String, Int64)>,
        commitTypesTruncated: Bool,
        docs: ArrayList<String>,
        progressEntryCount: Int64,
        progressUpdatedAt: String,
        warnings: ArrayList<String>,
        overallSummary: String
    ) {
        this.name = name
        this.path = path
        this.kind = kind
        this.headline = headline
        this.currentBranch = currentBranch
        this.defaultBranch = defaultBranch
        this.remote = remote
        this.userDirtyCount = userDirtyCount
        this.untrackedCount = untrackedCount
        this.stashCount = stashCount
        this.worktreeCount = worktreeCount
        this.commitCount = commitCount
        this.branchCount = branchCount
        this.repoBranchCount = repoBranchCount
        this.branchCountTruncated = branchCountTruncated
        this.lastCommitAgo = lastCommitAgo
        this.lastCommitAt = lastCommitAt
        this.storeHealth = storeHealth
        this.error = error
        this.branches = branches
        this.commitTypes = commitTypes
        this.commitTypesTruncated = commitTypesTruncated
        this.docs = docs
        this.progressEntryCount = progressEntryCount
        this.progressUpdatedAt = progressUpdatedAt
        this.warnings = warnings
        this.overallSummary = overallSummary
    }

    /// 采集失败的项目：分支/提交/文档全是空的，但**必须留在列表里**。
    public func failed(): Bool {
        return !this.error.isEmpty()
    }

    /// 项目活跃度：`active` / `idle` / `stale` / `merged` / `unknown`。
    ///
    /// **这是客户端派生的，不是引擎给的。** 引擎的 `status --json`
    /// 逐项目**没有**活跃度字段（只有 `summary.activeProjects` / `staleProjects`
    /// 两个计数），活跃度挂在 `branches[].status` 上。
    /// 一开始这里写的是 `Json.strAt(v, "activity", "unknown")` ——
    /// 键不存在，于是每个项目都显示「未知」，而界面上看着像个正经判定。
    /// 采集失败时返回 `unknown` 而不是 `stale`：
    /// 没读到 ≠ 停滞，把「不知道」说成「停滞」是在替引擎下结论。
    public func activity(): String {
        if (this.failed() || this.branches.isEmpty()) {
            return "unknown"
        }
        // 优先当前分支；没有标 current 的就退到默认分支，再退到第一行。
        var pick: ?Branch = None
        for (b in this.branches) {
            if (b.isCurrent) {
                pick = Some(b)
                break
            }
        }
        if (pick.isNone()) {
            for (b in this.branches) {
                if (b.isDefault) {
                    pick = Some(b)
                    break
                }
            }
        }
        if (pick.isNone()) {
            pick = Some(this.branches[0])
        }
        match (pick) {
            case Some(b) => return b.status
            case None => return "unknown"
        }
    }

    /// 侧栏行上显示的一行摘要。
    ///
    /// 失败项目只显示原因，不显示「0 提交」这类**看似正常的假数据** ——
    /// 采集失败时 commitCount 本来就是 0，显示成「0 提交」等于谎称读过这个仓库。
    public func sidebarLine(): String {
        if (this.failed()) {
            return this.error
        }
        if (this.userDirtyCount > 0) {
            return "${this.userDirtyCount} 处未提交 · ${this.lastCommitAgo}"
        }
        return this.lastCommitAgo
    }

    public static func from(v: JsonValue): Project {
        let brs = ArrayList<Branch>()
        for (b in Json.arrAt(v, "branches")) {
            brs.add(Branch.from(b))
        }
        let types = ArrayList<(String, Int64)>()
        for (t in Json.arrAt(v, "commitTypes")) {
            types.add((Json.strAt(t, "type", "?"), Json.intAt(t, "count", 0)))
        }
        let docs = ArrayList<String>()
        for (d in Json.arrAt(v, "docs")) {
            if (Json.boolAt(d, "exists", false)) {
                docs.add(Json.strAt(d, "file", "?"))
            }
        }
        let warns = Json.strArrAt(v, "warnings")
        let progress = Json.getOr(v, "progress")
        let overall = Json.getOr(v, "overall")

        return Project(
            Json.strAt(v, "name", "(未命名)"),
            Json.strAt(v, "path", ""),
            Json.strAt(v, "kind", ""),
            Json.strAt(v, "headline", ""),
            Json.strAt(v, "currentBranch", ""),
            Json.strAt(v, "defaultBranch", ""),
            Json.strAt(v, "remote", ""),
            Json.intAt(v, "userDirtyCount", 0),
            Json.intAt(v, "untrackedCount", 0),
            Json.intAt(v, "stashCount", 0),
            Json.intAt(v, "worktreeCount", 0),
            Json.intAt(v, "commitCount", 0),
            Json.intAt(v, "branchCount", 0),
            Json.intAt(v, "repoBranchCount", -1),
            Json.boolAt(v, "branchCountTruncated", false),
            Json.strAt(v, "lastCommitAgo", ""),
            Json.strAt(v, "lastCommitAt", ""),
            Json.strAt(v, "storeHealth", ""),
            Json.strAt(v, "error", ""),
            brs,
            types,
            Json.boolAt(v, "commitTypesTruncated", false),
            docs,
            Json.intAt(progress, "entryCount", 0),
            Json.strAt(progress, "updatedAt", ""),
            warns,
            Json.strAt(overall, "summary", "")
        )
    }
}

/// `status --json` 的一整份快照。
public class StatusSnapshot {
    public let projects: ArrayList<Project>
    public let generatedAt: String

    public let listedProjects: Int64
    /// 引擎自己报的失败项目数。`failedKnown` 为 false 时**这个数没有意义**。
    public let failedProjects: Int64
    /// 引擎有没有报 failedProjects 这个字段。
    ///
    /// 缺字段时不能回落成 0：那等于把「引擎没说有几个失败」
    /// 说成「一个都没失败」。这正是过旧引擎把读不到的项目显示成空项目的那条路径，
    /// `engine.cj` 的 `checkContract` 已经在入口拦了一道，这里是模型层自己的兜底 ——
    /// 免得以后有人新加一个调用点，绕过那道闸门又把陷阱请回来。
    public let failedKnown: Bool
    public let activeProjects: Int64
    public let staleProjects: Int64
    public let dirtyProjects: Int64
    public let branchCount: Int64
    public let degradedStores: Int64

    public init(
        projects: ArrayList<Project>,
        generatedAt: String,
        listedProjects: Int64,
        failedProjects: Int64,
        failedKnown: Bool,
        activeProjects: Int64,
        staleProjects: Int64,
        dirtyProjects: Int64,
        branchCount: Int64,
        degradedStores: Int64
    ) {
        this.projects = projects
        this.generatedAt = generatedAt
        this.listedProjects = listedProjects
        this.failedProjects = failedProjects
        this.failedKnown = failedKnown
        this.activeProjects = activeProjects
        this.staleProjects = staleProjects
        this.dirtyProjects = dirtyProjects
        this.branchCount = branchCount
        this.degradedStores = degradedStores
    }

    /// 失败项目数给人看的写法。引擎没报这个字段时写「?」而不是 0。
    public func failedLabel(): String {
        if (!this.failedKnown) {
            return "?"
        }
        return "${this.failedProjects}"
    }

    /// 成功读到状态的项目数。
    ///
    /// 与 `listedProjects` 刻意分开：引擎的 listedProjects 是**注册表里的条目数**，
    /// 失败的那些也计入。用它当「我看到了几个项目」会在有人挂了外置盘时
    /// 少报 3 个，而用户界面上根本没有那 3 个 —— 对不上，疑心生暗鬼。
    public func readableProjects(): Int64 {
        var n: Int64 = 0
        for (p in this.projects) {
            if (!p.failed()) {
                n += 1
            }
        }
        return n
    }

    public func find(name: String): Option<Project> {
        for (p in this.projects) {
            if (p.name == name) {
                return Some(p)
            }
        }
        return None
    }

    /// 空快照。**只用于「还没有数据」，不用于「读到了空」**——
    /// 后者是一个真实的快照（`listedProjects = 0`），两者不能混。
    public static func empty(): StatusSnapshot {
        return StatusSnapshot(ArrayList<Project>(), "", 0, 0, true, 0, 0, 0, 0, 0)
    }

    public static func from(v: JsonValue): StatusSnapshot {
        let ps = ArrayList<Project>()
        for (item in Json.arrAt(v, "projects")) {
            ps.add(Project.from(item))
        }
        let s = Json.getOr(v, "summary")
        return StatusSnapshot(
            ps,
            Json.strAt(s, "generatedAt", ""),
            Json.intAt(s, "listedProjects", 0),
            Json.intAt(s, "failedProjects", 0),
            Json.has(s, "failedProjects"),
            Json.intAt(s, "activeProjects", 0),
            Json.intAt(s, "staleProjects", 0),
            Json.intAt(s, "dirtyProjects", 0),
            Json.intAt(s, "branchCount", 0),
            Json.intAt(s, "degradedStores", 0)
        )
    }
}

/// 一次语言分布条目。
public class LanguageCount {
    public let language: String
    public let count: Int64

    public init(language: String, count: Int64) {
        this.language = language
        this.count = count
    }
}

/// `dashboard --json` 的聚合视图。
public class Dashboard {
    public let total: Int64
    public let registered: Int64
    public let failed: Int64
    public let dirty: Int64
    public let active7d: Int64
    public let active30d: Int64

    public let branches: Int64
    public let mergeCandidates: Int64
    public let untrackedFiles: Int64
    public let stashes: Int64

    public let languages: ArrayList<LanguageCount>
    public let languagesTruncated: Bool
    public let languagesFailed: Int64

    public let activeProjectNames: ArrayList<String>
    public let milestoneTotal: Int64
    public let milestoneDone: Int64

    public init(
        total: Int64,
        registered: Int64,
        failed: Int64,
        dirty: Int64,
        active7d: Int64,
        active30d: Int64,
        branches: Int64,
        mergeCandidates: Int64,
        untrackedFiles: Int64,
        stashes: Int64,
        languages: ArrayList<LanguageCount>,
        languagesTruncated: Bool,
        languagesFailed: Int64,
        activeProjectNames: ArrayList<String>,
        milestoneTotal: Int64,
        milestoneDone: Int64
    ) {
        this.total = total
        this.registered = registered
        this.failed = failed
        this.dirty = dirty
        this.active7d = active7d
        this.active30d = active30d
        this.branches = branches
        this.mergeCandidates = mergeCandidates
        this.untrackedFiles = untrackedFiles
        this.stashes = stashes
        this.languages = languages
        this.languagesTruncated = languagesTruncated
        this.languagesFailed = languagesFailed
        this.activeProjectNames = activeProjectNames
        this.milestoneTotal = milestoneTotal
        this.milestoneDone = milestoneDone
    }

    public static func empty(): Dashboard {
        return Dashboard(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ArrayList<LanguageCount>(),
            false, 0, ArrayList<String>(), 0, 0)
    }

    public static func from(v: JsonValue): Dashboard {
        let p = Json.getOr(v, "projects")
        let w = Json.getOr(v, "work")
        let langs = ArrayList<LanguageCount>()
        for (l in Json.arrAt(v, "languages")) {
            langs.add(LanguageCount(Json.strAt(l, "language", "?"), Json.intAt(l, "count", 0)))
        }
        let active = ArrayList<String>()
        for (a in Json.arrAt(v, "activeProjects")) {
            active.add(Json.strAt(a, "name", "?"))
        }
        let ms = Json.getOr(v, "milestones")
        let counts = Json.getOr(ms, "counts")
        return Dashboard(
            Json.intAt(p, "total", 0),
            Json.intAt(p, "registered", 0),
            Json.intAt(p, "failed", 0),
            Json.intAt(p, "dirty", 0),
            Json.intAt(p, "active7d", 0),
            Json.intAt(p, "active30d", 0),
            Json.intAt(w, "branches", 0),
            Json.intAt(w, "mergeCandidates", 0),
            Json.intAt(w, "untrackedFiles", 0),
            Json.intAt(w, "stashes", 0),
            langs,
            Json.boolAt(v, "languagesTruncated", false),
            Json.intAt(v, "languagesFailed", 0),
            active,
            Json.intAt(counts, "total", 0),
            Json.intAt(counts, "done", 0)
        )
    }
}

// ===========================================================================
// 看板分列 —— 与 macOS 端 `BoardColumn` / `ProjectStatus.liveness` 逐条对应
// ===========================================================================

/// 项目活跃度。**顺序与判定与 macOS 端完全一致**。
///
/// ⚠ 「待处理」必须排在「停滞」前面（macOS 端 2026-10-02 修的同一个 bug）。
/// macOS 现场症状：侧栏「看板 1」而仪表盘「待处理 3」—— 同一件事两个答案。
/// 根因不是两处算法不同（都走 liveness），而是 liveness **内部**先判停滞：
/// `primaryBranch.status == "stale"` 一命中就 return，「有活要干」根本没机会被问。
/// 两条理由支持「等我动手」优先：
///   1. 两者**不互斥**，先命中哪个纯属书写顺序，而书写顺序不该决定事实；
///   2. 「待处理」列的表头定义就包含「待合入的分支」——
///      有待合入分支的项目无论主分支多停滞都该进这一列。
/// 代价照实说：「久未更新」列会因此变少，但信息没丢 ——
/// 每张项目卡仍单独写着主分支的停滞状态。
public enum Liveness {
    | Unreadable  // 采集失败：所有计数都是未知，不是 0
    | NotGit      // 非 git 项目
    | NeedsAction // 有东西等着动手
    | EngineStale // 引擎判定为停滞（只有追踪到基线的分支才可能）
    | Quiet       // 30 天以上没有新提交
    | Recent      // 30 天内有新提交
    | Unknown     // 提交时间读不出来 —— 不许折进上面任何一档
}

public func livenessLabel(l: Liveness): String {
    match (l) {
        case Liveness.Unreadable => return "读不出来"
        case Liveness.NotGit => return "非 git"
        case Liveness.NeedsAction => return "待处理"
        case Liveness.EngineStale => return "停滞"
        case Liveness.Quiet => return "久未更新"
        case Liveness.Recent => return "活跃"
        case Liveness.Unknown => return "未知"
    }
}

/// 看板的四列。空列也带 `basis`（为什么空）——
/// 「0」既可能是「真没有」也可能是「没量出来」，只显示数字分不开。
public enum BoardColumn {
    | Attention
    | Active
    | Quiet
    | Other
}

public func boardColumnLabel(c: BoardColumn): String {
    match (c) {
        case BoardColumn.Attention => return "待处理"
        case BoardColumn.Active => return "活跃中"
        case BoardColumn.Quiet => return "久未更新"
        case BoardColumn.Other => return "其他"
    }
}

public func boardColumnBasis(c: BoardColumn): String {
    match (c) {
        case BoardColumn.Attention => return "有未提交、未跟踪、stash 或待合入的分支"
        case BoardColumn.Active => return "30 天内有过新提交"
        case BoardColumn.Quiet => return "超过 30 天没有新提交"
        case BoardColumn.Other => return "采集失败、非 git，或提交时间读不出来"
    }
}

public func boardColumnOf(l: Liveness): BoardColumn {
    match (l) {
        case Liveness.NeedsAction => return BoardColumn.Attention
        case Liveness.EngineStale => return BoardColumn.Quiet
        case Liveness.Quiet => return BoardColumn.Quiet
        case Liveness.Recent => return BoardColumn.Active
        case Liveness.Unreadable => return BoardColumn.Other
        case Liveness.NotGit => return BoardColumn.Other
        case Liveness.Unknown => return BoardColumn.Other
    }
}

/// 有没有东西等着动手。
///
/// ⚠ macOS 端这里还有一条 `mergeHint?.kind == "merge" || == "fast-forward"`。
/// **本端不抄那条**：`status --json` 的项目键里**根本没有 `mergeHint`**
/// （实测 33 个键，见 model_test.cj 的载荷夹具），macOS 端把它解成可选、
/// 在真实载荷下恒为 nil，那条分支**从来没被触发过**。
/// 照抄等于把一段死代码搬过来冒充能力。待合入的判定走
/// `branches[].isMergeCandidate`（`aheadOfDefault > 0 && !isDefault && !merged`），
/// 那条是真有数据的。
public func projectNeedsAction(p: Project): Bool {
    if (p.userDirtyCount > 0 || p.untrackedCount > 0 || p.stashCount > 0) {
        return true
    }
    for (b in p.branches) {
        if (b.isMergeCandidate()) {
            return true
        }
    }
    return false
}

public func branchIsMergeCandidate(b: Branch): Bool {
    return b.aheadOfDefault > 0 && !b.isDefault && !b.merged
}

/// 距最后一次提交多少天。`None` = **读不出来**（非 git / 时间解析不了 / 引擎没给键）。
///
/// ⚠ 算术必须与引擎**逐字一致**，否则看板分列会和仪表盘 KPI 对不上：
///     let ageDays = (nowMs - ms) / 86400000      // 引擎 dashboard.cj，整数除法
/// 所以这里也是整数除法，且**不四舍五入**。差一天就会让一个 30.6 天的项目
/// 掉进「活跃中」还是「久未更新」——而这两列是互斥的。
public func daysSinceLastCommit(p: Project, nowMs: Int64): Option<Int64> {
    match (parseIso8601Ms(p.lastCommitAt)) {
        case Some(ms) =>
            if (nowMs < ms) {
                return Some(0)
            }
            return Some((nowMs - ms) / 86400000)
        case None => return None
    }
}

/// 项目的活跃度判定。**纯函数**（收 nowMs）—— 判据要能喂固定时刻，
/// 不然同一个项目在测试跑两次可能是两个答案。
public func projectLiveness(p: Project, nowMs: Int64): Liveness {
    if (p.failed()) {
        return Liveness.Unreadable
    }
    if (p.kind != "git") {
        return Liveness.NotGit
    }
    if (projectNeedsAction(p)) {
        return Liveness.NeedsAction
    }
    // 引擎的档位最精确，但**只在它真的给出一行分支记录时**才有。
    if (primaryBranchStatus(p) == "stale") {
        return Liveness.EngineStale
    }
    match (daysSinceLastCommit(p, nowMs)) {
        case Some(age) => return (if (age <= 30) { Liveness.Recent } else { Liveness.Quiet })
        case None => return Liveness.Unknown
    }
}

/// 「这条项目该显示哪个分支」—— 标记为当前的那个，没有就退回第一个。
public func primaryBranch(p: Project): Option<Branch> {
    for (b in p.branches) {
        if (b.isCurrent) {
            return Some(b)
        }
    }
    if (p.branches.size > 0) {
        return Some(p.branches[0])
    }
    return None
}

public func primaryBranchStatus(p: Project): String {
    match (primaryBranch(p)) {
        case Some(b) => return b.status
        case None => return ""
    }
}
