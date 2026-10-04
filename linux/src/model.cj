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

/// 引擎给的合并提示。**它真的在载荷里** —— 本机 15 个项目里 3 个有值：
/// `deepOrca` / `moonviz` / `moonpainter`。
///
/// ⚠⚠ 本文件原先有条注释断言「`status --json` 的项目键里根本没有 `mergeHint`
/// （实测 33 个键）」，于是这条通路被**当成死代码**整条删掉了。
/// 那次「实测」量的是 `model_test.cj` 的**载荷夹具**，不是真实输出 ——
/// 与 markdown 夹具栽的是同一个坑。载荷里没有 ≠ 引擎不发；
/// 夹具没写 ≠ 引擎没有。
public class MergeHint {
    /// `fast-forward` / `merge` / `merged`
    public let kind: String
    public let ahead: Int64
    public let behind: Int64
    public let defaultBranch: String
    public let target: String
    /// 引擎写好的整句人话。**优先用它**，不要在客户端重拼 ——
    /// 「需三方合并（领先 20 / 落后 4）」这种口径只有引擎知道。
    public let description: String

    public init(kind: String, ahead: Int64, behind: Int64,
        defaultBranch: String, target: String, description: String) {
        this.kind = kind
        this.ahead = ahead
        this.behind = behind
        this.defaultBranch = defaultBranch
        this.target = target
        this.description = description
    }

    /// 这条提示要不要占位。`merged` 是「已经合过了」，不是待办。
    public func actionable(): Bool {
        return this.kind == "merge" || this.kind == "fast-forward"
    }

    public static func from(v: JsonValue): MergeHint {
        return MergeHint(
            Json.strAt(v, "kind", ""),
            Json.intAt(v, "ahead", 0),
            Json.intAt(v, "behind", 0),
            Json.strAt(v, "defaultBranch", ""),
            Json.strAt(v, "target", ""),
            Json.strAt(v, "description", "")
        )
    }
}

/// 引擎判的**工作区脏度**（与 `userDirtyCount` 是两个口径）。
///
/// 上面那排内联统计的「未提交 / 未跟踪」是**用户改的**，
/// 这个对象是**引擎读到的**，带 `ok` —— 读不出来时 `ok` 缺席或 false，
/// 底下所有数字都不可信。两行数字并排却不标口径，用户会以为它们矛盾。
public class DirtyInfo {
    /// 引擎是否成功读到工作区。**非 true ⇒ 下面所有数字都不可信。**
    public let ok: Bool
    public let total: Int64
    public let modified: Int64
    public let staged: Int64
    public let untracked: Int64
    /// 冲突数。会**丢代码**的那种，必须压在披露最前面单独说。
    public let conflicts: Int64
    /// 脏文件路径。引擎给的，可能含目录。
    public let files: ArrayList<String>

    public init(ok: Bool, total: Int64, modified: Int64, staged: Int64,
        untracked: Int64, conflicts: Int64, files: ArrayList<String>) {
        this.ok = ok
        this.total = total
        this.modified = modified
        this.staged = staged
        this.untracked = untracked
        this.conflicts = conflicts
        this.files = files
    }

    public func readable(): Bool {
        return this.ok
    }

    public static func from(v: JsonValue): DirtyInfo {
        return DirtyInfo(
            Json.boolAt(v, "ok", false),
            Json.intAt(v, "total", 0),
            Json.intAt(v, "modified", 0),
            Json.intAt(v, "staged", 0),
            Json.intAt(v, "untracked", 0),
            Json.intAt(v, "conflicts", 0),
            Json.strArrAt(v, "files")
        )
    }
}

/// 人话版脏度披露。**读不出来时必须说读不出来，不能报 0。**
///
/// 与 macOS 端 `Models.swift` 的 `DirtyInfo.dirtyLine` 同一条规则。
/// 分档不是装饰：冲突（`conflicts > 0`）是会丢代码的那种，
/// 混在「N 处未提交」里会被当成一条普通改动。
public func dirtyLine(d: DirtyInfo): String {
    if (!d.readable()) {
        return "工作区读不出来（文件数不可信）"
    }
    if (d.total <= 0) {
        return "工作区干净"
    }
    let parts = ArrayList<String>()
    if (d.conflicts > 0) { parts.add("⚠ 冲突 ${d.conflicts}") }
    if (d.staged > 0) { parts.add("已暂存 ${d.staged}") }
    if (d.modified > 0) { parts.add("已修改 ${d.modified}") }
    if (d.untracked > 0) { parts.add("未跟踪 ${d.untracked}") }
    if (parts.isEmpty()) {
        return "${d.total} 处未提交"
    }
    return "${d.total} 处未提交（${joinList(parts.toArray())}）"
}

/// 哪些文件脏。`dirtyLine` 说的是「几处」，用户要动手时需要「哪几个」。
///
/// 截断必须自报：静默砍掉前 8 个会让人以为只脏了这几个。
public func dirtyFilesLine(d: DirtyInfo): String {
    if (!d.readable() || d.files.isEmpty()) {
        return ""
    }
    let cap: Int64 = 8
    let sb = StringBuilder()
    var i: Int64 = 0
    for (f in d.files) {
        if (i >= cap) { break }
        if (i > 0) { sb.append(" · ") }
        sb.append(f)
        i += 1
    }
    let hidden = d.files.size - cap
    if (hidden > 0) {
        sb.append(" · 还有 ${hidden} 个")
    }
    return sb.toString()
}

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
    /// 仓库里**真实**的分支数。`-1` = 读不出来。
    ///
    /// ⚠ 引擎的项目对象**只发 `repoBranchCount`**（实测 `moongit status --json`
    /// 的 `projects[i]` 键表里没有 `branchCount`，也没有 `branchCountTruncated`）。
    /// 原来这里还有两个读这两个键的字段，于是 `branchCount` **恒为 0**、
    /// `branchCountTruncated` 恒为 false —— 界面写「分支进度（0）」，
    /// 而仓库实际有分支。已删掉那两个字段：留着一个恒 0 的读数，
    /// 下一个人一定会拿它当事实用。
    /// 需要「追踪到基线的分支数」时用 `branches.size`（本项目自己数）。
    public let repoBranchCount: Int64
    /// 引擎发的 `tags`（真实载荷是数组，可能为空）。
    public let tags: ArrayList<String>
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
    /// 引擎的 `overall.notes` —— **需要留意的点**。
    ///
    /// ⚠ 这一组事实**别处没有**。实测引擎会报：
    /// · `工作区有 2 处未提交改动`（界面上只有一���裸数字，没人这么说过）
    /// · `存在 2 条 stash，注意清理`（数字有，**「注意清理」这半句没有**）
    /// · `非 git 仓库：进度基于文件活动时间，不含提交历史`
    ///   （这一句是**唯一**说明「为什么这个项目提交数是 0」的地方）
    ///
    /// 引擎算了、模型收了、界面不说 ⇒ 等于没算。macOS 端
    /// `DetailViews.swift:282` 有这条通路，本端原先**一个字段都没有**。
    public let overallNotes: ArrayList<String>
    /// 引擎给的合并提示。`None` = 引擎这次没报（大多数项目）。
    ///
    /// ⚠ 载荷里**真的有**这个键，本机 15 个项目里 3 个有值。
    /// 少了它：一个 154 个提交可直接 fast-forward、却没有任何可合并分支的
    /// 仓库（实测 `moonpainter`），界面上**一个字提示都没有** ——
    /// 而这是用户最想知道的那句话。
    public let mergeHint: Option<MergeHint>
    /// 引擎判的工作区脏度。`None` = 引擎没发这个对象。
    public let dirtyInfo: Option<DirtyInfo>
    /// 依赖清单（`package.json` / `Package.swift` / `Cargo.toml` / `moon.mod.json`）。
    /// 空数组**不占位**（实测刚注册的项目就是空）。
    public let manifests: ArrayList<String>

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
        repoBranchCount: Int64,
        tags: ArrayList<String>,
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
        overallSummary: String,
        overallNotes!: ArrayList<String> = ArrayList<String>(),
        mergeHint!: Option<MergeHint> = None,
        dirtyInfo!: Option<DirtyInfo> = None,
        manifests!: ArrayList<String> = ArrayList<String>()
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
        this.repoBranchCount = repoBranchCount
        this.tags = tags
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
        this.overallNotes = overallNotes
        this.mergeHint = mergeHint
        this.dirtyInfo = dirtyInfo
        this.manifests = manifests
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
            Json.intAt(v, "repoBranchCount", -1),
            Json.strListAt(v, "tags"),
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
            Json.strAt(overall, "summary", ""),
            // ⚠ `overall` 在采集失败时是**空对象 `{}`**，不是缺键。
            // 两种都得拿到空数组 —— 写成 `Json.strArrAt(v, "overall.notes")`
            // 之类会静默拿到空，而那恰好与非 git 项目的真实输出**长得一样**：
            // 「读不出来」与「确实没有」被画成同一张脸。
            overallNotes: Json.strArrAt(overall, "notes"),
            // ⚠ 三个键都**真的在真实载荷里**（本机 15 个项目实测：
            //    mergeHint 3 个、dirty 13 个、manifests 8 个）。
            //
            // 「引擎没发」与「引擎发了个 null」要分开：前者是 None，
            // 后者会解出一个全零的 MergeHint，界面上画出一条
            // 「可快进」而 description 是空串 —— 比不画更糟。
            // 所以这里用 `asObj` 把非对象一律当「没发」。
            mergeHint: (match (Json.get(v, "mergeHint")) {
                case Some(mh) => (match (Json.asObj(mh)) {
                    case Some(_) => Some(MergeHint.from(mh))
                    case None => None
                })
                case None => None
            }),
            dirtyInfo: (match (Json.get(v, "dirty")) {
                case Some(dt) => (match (Json.asObj(dt)) {
                    case Some(_) => Some(DirtyInfo.from(dt))
                    case None => None
                })
                case None => None
            }),
            manifests: Json.strArrAt(v, "manifests")
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
/// 里程碑计数。**逐个键对应引擎 `dashboard --json` 的 `milestones.counts`**。
///
/// ⚠ 引擎不发 `total` 键（真实键是 `readCount`）。原来这里读 `counts.total`，
/// 于是 `milestoneTotal` **恒为 0** —— 而判据用的是手写夹具
/// `{"counts":{"total":5,"done":2}}`，里面正好有这个不存在的键，
/// 所以判据一直绿着，真实载荷下却是坏的。
/// 教训：**判据夹具的键必须来自真实载荷**，不能照着字段名想象着写。
public class MilestoneCounts {
    public let open: Int64
    public let done: Int64
    /// 「读不出达没达成」。**不能并进 open 或 done** ——
    /// unknown 是「不知道」，不是「没达成」。引擎注释：
    /// 「『我们不知道』和『没有达成』是两件相反的事，必须分开表达。」
    public let unknown: Int64
    public let dropped: Int64
    public let other: Int64
    /// 引擎实际读到的条数（`total` 键不存在，别再找它）。
    public let readCount: Int64
    public let excludedDisabled: Int64
    public let orphaned: Int64
    public let storeHealth: String
    public let degraded: Bool

    public init(
        open: Int64,
        done: Int64,
        unknown: Int64,
        dropped: Int64,
        other: Int64,
        readCount: Int64,
        excludedDisabled: Int64,
        orphaned: Int64,
        storeHealth: String,
        degraded: Bool
    ) {
        this.open = open
        this.done = done
        this.unknown = unknown
        this.dropped = dropped
        this.other = other
        this.readCount = readCount
        this.excludedDisabled = excludedDisabled
        this.orphaned = orphaned
        this.storeHealth = storeHealth
        this.degraded = degraded
    }

    public static func empty(): MilestoneCounts {
        return MilestoneCounts(0, 0, 0, 0, 0, 0, 0, 0, "unknown", false)
    }

    public static func from(v: JsonValue): MilestoneCounts {
        return MilestoneCounts(
            Json.intAt(v, "open", 0),
            Json.intAt(v, "done", 0),
            Json.intAt(v, "unknown", 0),
            Json.intAt(v, "dropped", 0),
            Json.intAt(v, "other", 0),
            Json.intAt(v, "readCount", 0),
            Json.intAt(v, "excludedDisabled", 0),
            Json.intAt(v, "orphaned", 0),
            Json.strAt(v, "storeHealth", "unknown"),
            Json.boolAt(v, "degraded", false)
        )
    }

    /// 分母只取「达没达成有答案的」（done + open）。
    /// **不把 unknown 塞进分母** —— 那是假装它不是目标。
    public func decided(): Int64 {
        return this.done + this.open
    }
}

/// 一条里程碑。键集来自引擎 `src/cli/cli.cj` 的 `milestoneLine`（消费方解码处）。
///
/// ⚠ 项目归属用 **`projectName`** 而不是 `projectId`。
///
/// 更正一条我先前的错误断言：「引擎不发 projectId」是错的 ——
/// `kernel.milestoneJson` = 存储侧 `toJson()` 全字段（含 projectId）+ 补充键。
/// macOS 端 `ProjectProgressCard` 用 `$0.projectId == p.id` 是有依据的。
///
/// 那这里为什么仍用 projectName：**真实载荷里 `items` 恒为空**
/// （实测 15 个项目时 `items: []`，而 `counts.readCount=1` / `orphaned=1`），
/// 验不了 `projectId` 与 `ProjectStatus.id` 是否逐字相等。
/// `projectName` 恒发、且与 `Project.name` 同源，必然匹配 ——
/// 在无法验证的那条路上取**能验证的那条**。等有了真实 items 再评估。
public class MilestoneItem {
    public let projectName: String
    public let name: String
    /// `open` / `done` / `dropped` / `unknown`。
    /// `unknown` 是「仓库读不出来，没法核验」—— 与 `dropped`（明确放弃）是两件事。
    public let status: String
    public let targetDate: String
    /// `-1` = 未设置**或日期无效**。绝不能当成 0 或某个逾期天数。
    public let daysToTarget: Int64
    public let commitsSince: Int64
    public let tagReached: Bool
    public let overdue: Bool
    /// 仓库读不出来时，tagReached / commitsSince 都是「未知」而不是「没有」。
    /// `status == "unknown"` 时它是原因，不是一句多余的说明。
    public let gitReadable: Bool
    /// 引擎给的「为什么核验不了」，**恒发**：可读时是空串。
    ///
    /// ⚠ 这条要接：引擎原话是「调用方只能靠『有没有这个键』反推出了故障」，
    /// 所以改成恒发。我们若不读它，界面上就只能自己编一句「仓库读不出来」——
    /// 而引擎已经写好了具体原因。
    public let unverifiedReason: String
    /// 里程碑绑定到哪个 tag（未显式绑定时用里程碑名兜底）。
    public let tagName: String

    public init(
        projectName: String,
        name: String,
        status: String,
        targetDate: String,
        daysToTarget: Int64,
        commitsSince: Int64,
        tagReached: Bool,
        overdue: Bool,
        gitReadable: Bool,
        unverifiedReason: String,
        tagName: String
    ) {
        this.projectName = projectName
        this.name = name
        this.status = status
        this.targetDate = targetDate
        this.daysToTarget = daysToTarget
        this.commitsSince = commitsSince
        this.tagReached = tagReached
        this.overdue = overdue
        this.gitReadable = gitReadable
        this.unverifiedReason = unverifiedReason
        this.tagName = tagName
    }

    public static func from(v: JsonValue): MilestoneItem {
        return MilestoneItem(
            Json.strAt(v, "projectName", ""),
            Json.strAt(v, "name", ""),
            Json.strAt(v, "status", "unknown"),
            Json.strAt(v, "targetDate", ""),
            Json.intAt(v, "daysToTarget", -1),
            Json.intAt(v, "commitsSince", 0),
            Json.boolAt(v, "tagReached", false),
            Json.boolAt(v, "overdue", false),
            Json.boolAt(v, "gitReadable", true),
            Json.strAt(v, "unverifiedReason", ""),
            Json.strAt(v, "tagName", Json.strAt(v, "name", ""))
        )
    }

    /// 状态词。`unknown` 与 `dropped` 必须分开 ——
    /// 「系统读不出来」和「明确放弃」是相反的两件事，混同会让系统故障被读成进度清零。
    public func statusLabel(): String {
        match (this.status) {
            case "done" => return "已达成"
            case "dropped" => return "已放弃"
            case "unknown" => return "无法核验（仓库读不出来）"
            case _ => return (if (this.overdue) { "已逾期" } else { "进行中" })
        }
    }
}

public class Dashboard {
    /// 采集成功的项目数（引擎遇到带 error 的会 continue 跳过）。
    public let total: Int64
    /// **注册表条数**。界面上的「项目总数」必须用它，不能用 `total`。
    /// 夹具实测：注册 6、3 个采集失败 ⇒ total=3 / listed=6。
    /// 用错的话标题写「项目总数 3」，而侧栏写「仓库（6/6）」——
    /// 同一屏两个答案，且用户先看到的是那个大数字。
    public let listed: Int64
    public let registered: Int64
    public let excludedDisabled: Int64
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
    /// 头部因 `languagesTopCut` 被砍掉过 —— 与「总数被截断」是两回事。
    public let languagesTopCut: Bool
    public let languagesFailedReasons: ArrayList<String>

    public let activeProjectNames: ArrayList<String>
    public let milestoneCounts: MilestoneCounts
    /// 逐条里程碑。项目卡上的里程碑行靠它（按 `projectName` 归属项目）。
    public let milestoneItems: ArrayList<MilestoneItem>

    public init(
        total: Int64,
        listed: Int64,
        registered: Int64,
        excludedDisabled: Int64,
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
        languagesTopCut: Bool,
        languagesFailedReasons: ArrayList<String>,
        activeProjectNames: ArrayList<String>,
        milestoneCounts: MilestoneCounts,
        milestoneItems: ArrayList<MilestoneItem>
    ) {
        this.total = total
        this.listed = listed
        this.registered = registered
        this.excludedDisabled = excludedDisabled
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
        this.languagesTopCut = languagesTopCut
        this.languagesFailedReasons = languagesFailedReasons
        this.activeProjectNames = activeProjectNames
        this.milestoneCounts = milestoneCounts
        this.milestoneItems = milestoneItems
    }

    public static func empty(): Dashboard {
        return Dashboard(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ArrayList<LanguageCount>(),
            false, 0, false, ArrayList<String>(), ArrayList<String>(), MilestoneCounts.empty(),
            ArrayList<MilestoneItem>())
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
        return Dashboard(
            Json.intAt(p, "total", 0),
            Json.intAt(p, "listed", 0),
            Json.intAt(p, "registered", 0),
            Json.intAt(p, "excludedDisabled", 0),
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
            Json.boolAt(v, "languagesTopCut", false),
            Json.strListAt(v, "languagesFailedReasons"),
            active,
            MilestoneCounts.from(Json.getOr(ms, "counts")),
            milestoneItemsOf(ms)
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

/// 语言分布的覆盖度披露。**四轴彼此独立，少一条就撒谎。**
///
/// 与 macOS 端 `LanguageCoverage.languageCoverage` 逐条对齐。
///
/// ⚠⚠ 这不是理论风险，本机就在发生：`dashboard --json` 给出 **12 种**语言
/// （TypeScript 777 / MoonBit 356 / 其他 210 / … / C/C++ 34 / Shell 16 /
/// Python 13 / Rust 11），而界面 `languageParts` 只画前 8 条 ——
/// **藏起 4 种、一个字都不提**。更糟的是 `languagesTruncated` 与
/// `languagesTopCut` 实测都是 `false`，所以连原有的「已截断」标记都不亮：
/// 读者看到的是一条看起来完整的分段条。macOS 那边把它记成缺陷 #205
/// （14 种语言只列 8 条且零提示），本端原样复现。
///
/// 四个轴：
///   · `truncated`  —— 文件被砍（引擎的跟踪文件上限），掉出去的文件里
///                     可能还藏着**整类**语言
///   · `topCut`     —— 语言**条数**被引擎上限砍掉
///   · `shownCount` —— **界面自己**又砍了一层（本端上限 8）
///   · `failed`     —— 压根没采到（与「这个项目群没有这些语言」无关）
public class LanguageCoverage {
    /// `languages` 为空时该显示什么。空数组有两种成因，文案必须不同：
    /// 「暂无数据」会被读成「真的没有」，而真相可能是「没采到」。
    public let emptyTitle: String
    /// 卡片下方要补的说明；空 = 没什么要说的。
    public let notes: ArrayList<String>

    public init(emptyTitle: String, notes: ArrayList<String>) {
        this.emptyTitle = emptyTitle
        this.notes = notes
    }
}

/// 覆盖度披露的**唯一**判定点。纯函数。
///
/// - `languageCount`: 引擎给出的语言条数（**含**界面上没画出来的那几条）
/// - `shownCount`: 界面**实际画出来**的条数
public func languageCoverage(d: Dashboard, shownCount: Int64): LanguageCoverage {
    let languageCount = d.languages.size
    let notes = ArrayList<String>()

    if (d.languagesTruncated) {
        notes.add("有项目撞到跟踪文件上限，被丢掉的文件里可能还有整类语言")
    }
    if (d.languagesTopCut) {
        notes.add("语言种类超过引擎上限，只列了排名靠前的一部分（不是全部语言）")
    }
    if (shownCount < languageCount) {
        // 界面自己砍的：这一句说的是**这张卡片**，与引擎那两条是两回事
        notes.add("这张卡片只显示前 ${shownCount} 种语言（共 ${languageCount} 种）")
    }
    if (d.languagesFailed > 0) {
        var line = "${d.languagesFailed} 个项目语言采集失败，未计入这份分布（不是「这个项目群没有这些语言」）"
        if (!d.languagesFailedReasons.isEmpty()) {
            line += "；原因示例：${d.languagesFailedReasons[0]}"
        }
        notes.add(line)
    }

    // 采集失败时 languages 为空是**正常结果**，不是「没数据」。
    // 文案必须让用户知道该去查引擎，而不是以为项目群真的没这些语言。
    let emptyTitle = (if (d.languagesFailed > 0 && languageCount == 0) {
        "未采集到语言数据"
    } else {
        "暂无数据"
    })
    return LanguageCoverage(emptyTitle, notes)
}

/// 有没有东西等着动手。
///
/// ⚠ 这条原先**故意少抄了** macOS 端的一条
/// （`mergeHint?.kind == "merge" || == "fast-forward"`），
/// 理由写的是「`status --json` 的项目键里根本没有 `mergeHint`」
/// —— **那句是错的**。那次「实测 33 个键」量的是 `model_test.cj` 的
/// **载荷夹具**，不是真实输出。本机 `moongit status --json` 里
/// 15 个项目有 3 个带 `mergeHint`（`deepOrca` / `moonviz` / `moonpainter`）。
///
/// 载荷里没有 ≠ 引擎不发；夹具没写 ≠ 引擎没有。删一条通路之前，
/// 判据得建立在**真实载荷**上，不是夹具上。
///
/// 实测的量化后果：`moonpainter` 有 154 个提交可直接 fast-forward、
/// 却**没有任何可合并分支** —— 只看分支的话它显示成「一切正常」，
/// 而它其实欠着一次合并。macOS 端把它算进待处理。
public func projectNeedsAction(p: Project): Bool {
    if (p.userDirtyCount > 0 || p.untrackedCount > 0 || p.stashCount > 0) {
        return true
    }
    for (b in p.branches) {
        if (b.isMergeCandidate()) {
            return true
        }
    }
    match (p.mergeHint) {
        case Some(h) => return h.actionable()
        case None => return false
    }
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

/// 解析 `milestones.items`。缺键 / 非数组都返回空列表 ——
/// 真实载荷里这一项**经常是空的**（实测 15 个项目时 items 为 `[]`，
/// 而 counts.readCount=1、orphaned=1），空列表是正常形态，不是错误。
private func milestoneItemsOf(ms: JsonValue): ArrayList<MilestoneItem> {
    let out = ArrayList<MilestoneItem>()
    for (it in Json.arrAt(ms, "items")) {
        out.add(MilestoneItem.from(it))
    }
    return out
}

// ===========================================================================
// C10 停滞提醒（mac 端 Model.postNotificationsIfNeeded 的移植）
//
// 章程 C10 明列「更新完成 / 停滞提醒 / 定时简报」三类通知。更新完成那类
// 早就有（actUpdate/actUpdateAll）；定时简报与这一节的停滞提醒同批补齐。
// ===========================================================================

/// 一条要发的提醒：去重键 + 标题 + 正文。
public struct StaleNotice {
    public let key: String
    public let title: String
    public let body: String

    public init(key: String, title: String, body: String) {
        this.key = key
        this.title = title
        this.body = body
    }
}

/// 扫一轮项目，给出这一轮**新**出现的提醒：(新键, 文案)，两边按下标一一对应。
/// **纯函数**：喂项目列表与已提醒键集，判据不开窗就能验去重语义。
///
/// 键的形状与 mac 端一致（mac 用 `p.id`，本端的身份是项目名 —— 注册表
/// 以名字定位项目，actUpdate 等动作都递名字）：
///   · 非默认分支停滞  `stale:<项目>:<分支名>` —— 分支合掉/删掉后自然不再报；
///   · 未提交 ≥ 10    `dirty:<项目>:<count/10>` —— **桶按 10 取整**：
///     10→19 只报一次，攒到 20 才再报一档。逐个数变化每次都报的话，
///     一天能来十条「11 处、12 处、13 处」—— 那是骚扰不是提醒。
///
/// `headAgo` 进正文：只说「停滞」不说多久，用户无从判断急不急。
/// 采集失败的项目整只跳过：它的分支表和脏数是「没读出来」的空/0，
/// 拿没读到的东西发「停滞了」的提醒，是替引擎下结论。
public func staleReminders(projects: ArrayList<Project>, notified: HashSet<String>): (ArrayList<String>, ArrayList<StaleNotice>) {
    let freshKeys = ArrayList<String>()
    let notices = ArrayList<StaleNotice>()
    for (p in projects) {
        if (p.failed()) {
            continue
        }
        for (b in p.branches) {
            if (b.status != "stale" || b.isDefault) {
                continue
            }
            let key = "stale:${p.name}:${b.name}"
            if (notified.contains(key)) {
                continue
            }
            freshKeys.add(key)
            notices.add(StaleNotice(key, "分支停滞：${p.name}",
                "`${b.name}` 已 ${b.headAgo} 无提交，考虑合并或关闭"))
        }
        if (p.userDirtyCount >= 10) {
            let key = "dirty:${p.name}:${p.userDirtyCount / 10}"
            if (!notified.contains(key)) {
                freshKeys.add(key)
                notices.add(StaleNotice(key, "未提交改动较多：${p.name}",
                    "${p.userDirtyCount} 处改动未提交"))
            }
        }
    }
    return (freshKeys, notices)
}
