// Models.swift — 与引擎 CLI 的 `--json` 输出对齐的契约模型。
//
// 【边界】字段名必须与 moonGit/src/flow/*.cj 的 JSON 输出严格一致；
// 引擎改键名 = 破坏契约，必须同步改这里（AGENTS.md 有约定）。
//
// ⚠️ 原来这里写的是「与引擎 HTTP API 对齐」—— 传输层早已改成 CLI 子进程，
// HTTP 服务端也已整体删除（AGENTS.md 第一条不变量：没有 /api/*）。
// 这行会把下一个人引去找一个根本不存在的接口。
import Foundation

// MARK: - 状态（deepgit status --json）

struct EngineSummary: Decodable, Hashable {
    /// 只统计**采集成功**的项目。引擎的 groupSummary 显式 continue 跳过带 error 的条目。
    /// 拿它当「项目总数」会把采集失败的项目悄悄抹掉 —— 引擎为此才补 listedProjects。
    let projectCount: Int
    /// 注册表里一共多少条项目（= 表格会渲染的行数）。
    let listedProjects: Int
    /// 其中采集失败的数量。>0 时必须披露，不能只报 projectCount。
    let failedProjects: Int
    let activeProjects: Int
    let staleProjects: Int
    let dirtyProjects: Int
    /// 引擎**追踪到基线**的分支数，不是仓库真实总数。
    let branchCount: Int
    /// 仓库真实分支总数之和。-1 不可能出现在这里（引擎是求和），但为 0 时
    /// 说明所有项目的 repoBranchCount 都读不出来 —— 那时看 branchUnknownProjects。
    let repoBranchTotal: Int
    /// 有多少项目「追踪数 < 仓库真实数」，即分支没被全部追踪。
    let branchTruncatedProjects: Int
    /// 有多少项目的仓库分支数**读不出来**。这些不计入 repoBranchTotal。
    let branchUnknownProjects: Int
    /// 有多少个项目的存储处于降级/损坏态。
    let degradedStores: Int
}

struct CommitTypeStat: Decodable, Hashable {
    let type: String
    let count: Int
}

struct MergeHint: Decodable, Hashable {
    let kind: String
    let ahead: Int
    let behind: Int
    let defaultBranch: String
    let target: String
    let description: String
}

/// 引擎给的「一句话总结 + 需要留意的点」。
///
/// 实测 `notes` 会带**别处没有的事实**（「工作区有 2 处未提交改动」），
/// 所以它不是 `headline` 的同义重复 —— 丢了它，界面就没有任何地方说这句。
///
/// ⚠️ **字段必须可缺席**：采集失败时引擎把 `overall` 发成空对象 `{}`。
/// 这里任何一个字段声明成非可选，`Decodable` 就会在**错误桩**上抛
/// keyNotFound —— 后果不是「这个坏项目显示不出总结」，而是**整条
/// `StatusEnvelope` 解码失败**，所有项目（包括好的那些）一起消失。
/// 非可选字段的错误会被放大到整个列表，这是本轮实际踩到的。
struct OverallMeta: Decodable, Hashable {
    let summary: String?
    let notes: [String]?

    /// 有话说才说话。空对象（错误桩）与空串一律当作「没有」。
    var displaySummary: String? {
        guard let s = summary, !s.isEmpty else { return nil }
        return s
    }

    /// 空对象 ⇒ 空数组。界面按「有没有内容」决定画不画，不占位。
    var displayNotes: [String] {
        notes ?? []
    }
}

/// 工作区脏度的结构化视图。
///
/// ⚠️ `ok` 是这里最要紧的一位：`false` 表示**引擎没读出来**（权限/路径问题），
/// 此时 `total` 等数字全是 0，直接显示就是「工作区干净」——
/// 与 `userDirtyCount` 的 -1 是同一个坑（不变量 33 那族）。
///
/// ⚠️ 同 OverallMeta：错误桩发的是 `{}`，字段全部可缺席。
/// `ok` 缺席与 `ok=false` 一样是「读不出来」，都不能当「干净」。
struct DirtyInfo: Decodable, Hashable {
    /// 引擎是否成功读到工作区。**非 true ⇒ 下面的数字都不可信。**
    let ok: Bool?
    let total: Int?
    let modified: Int?
    let staged: Int?
    let untracked: Int?
    let conflicts: Int?
    /// 脏文件路径。引擎给的，可能包含目录（实测 `store/`）。
    ///
    /// ⚠️ 刻意**没有** `clean` 字段：它与 `total == 0` 完全同义，
    /// 而 `dirtyLine` 已经用 total 判过「工作区干净」——
    /// 收一个永远不参与判断的字段就是不变量 76 说的「收了不说」。
    let files: [String]?

    /// 读不出来（字段缺席、显式 false）——**不是「工作区干净」**。
    var isReadable: Bool { ok == true }

    /// 哪些文件脏。`dirtyLine` 说的是「几处」，用户要动手时需要「哪几个」。
    ///
    /// 截断必须自报：静默砍掉前 8 个会让人以为只脏了这几个。
    var dirtyFilesLine: String? {
        guard isReadable, let f = files, !f.isEmpty else { return nil }
        let cap = 8
        let shown = f.prefix(cap).joined(separator: " · ")
        let hidden = f.count - cap
        return hidden > 0 ? "\(shown) · 还有 \(hidden) 个" : shown
    }

    /// 人话版脏度披露。读不出来时必须说读不出来，不能报 0。
    ///
    /// 分档不是装饰：冲突（conflicts>0）是会丢代码的那种，必须压在最前面单独说，
    /// 混在「N 处未提交」里会被当成一条普通改动。
    var dirtyLine: String {
        guard isReadable else { return "工作区读不出来（文件数不可信）" }
        let t = total ?? 0
        guard t > 0 else { return "工作区干净" }
        var parts: [String] = []
        let c = conflicts ?? 0
        if c > 0 { parts.append("⚠ 冲突 \(c)") }
        let s = staged ?? 0
        if s > 0 { parts.append("已暂存 \(s)") }
        let m = modified ?? 0
        if m > 0 { parts.append("已修改 \(m)") }
        let u = untracked ?? 0
        if u > 0 { parts.append("未跟踪 \(u)") }
        return parts.isEmpty ? "\(t) 处未提交" : "\(t) 处未提交（" + parts.joined(separator: " · ") + "）"
    }
}

/// 托管文档的引用。`exists=false` 表示引擎管着它但文件还没建。
struct DocRef: Decodable, Hashable {
    let file: String
    let exists: Bool
}

struct BranchStatus: Decodable, Identifiable, Hashable {
    let name: String
    let status: String
    let statusLabel: String
    let headShort: String
    let headAgo: String
    let summary: String
    let pendingCommits: Int
    let aheadOfDefault: Int
    let isCurrent: Bool
    let isDefault: Bool

    /// 这条分支是不是已经合进默认分支了。
    ///
    /// ⚠️ 引擎恒发这个键（`status --json` 的分支对象里实测有 `"merged": false`），
    /// 而模型原来**没有它** —— 于是客户端算「哪些分支可以合」时
    /// 少一个排除条件，只能拿 `isDefault` 顶替。
    /// 写成 `let merged: Bool` 而不是 `var ... = false`：后者会被合成的
    /// `init(from:)` 跳过、永远是 false（见不变量 105 的整族）。
    let merged: Bool

    // ── 引擎给了、模型原来没有的键（Phase 3 地基层）──

    /// 这条分支最近发生的**具体事件**。实测形如 `["更新：“第二次”", "微调：“首次”"]`。
    ///
    /// ⚠️ 它与 `summary` 不是一回事：`summary` 是一句话概括，
    /// `highlights` 是**逐条**的。用户问「这条分支最近动了什么」，
    /// 答案在这个数组里 —— 丢掉它就只能给一句概括。
    let highlights: [String]?

    /// 引擎建议的下一步。实测可以是 `[]`（没有建议），所以是空数组**不是**没有信息。
    let nextSteps: [String]?

    /// 距离上次更新多少天。**-1 = 算不出来**（不是 0 天前）。
    let staleDays: Int

    /// HEAD 提交的完整标题（`summary` 是概括，这里是原文）。
    let headSubject: String?

    /// 生成 `summary`/`highlights` 的来源（rules / 具体的 AI provider）。
    let provider: String?

    /// 完整 commit SHA。`headShort` 只有 7 位，排查问题时不够。
    let head: String?

    /// 基线被重建过 ⇒ `aheadOfDefault`/`pendingCommits` 的原区间已不可比。
    ///
    /// ⚠️ 模型原来根本没有这个键，于是界面上「待记录 12」和「领先默认 3」
    /// 在基线重建后照报不误 —— 数字是真的，但**没有意义**。
    let baselineReset: Bool

    var id: String { name }

    /// 「多久没更新」的人类可读说法。**读不出来不许说成 0**。
    var staleText: String {
        if staleDays < 0 { return "多久没更新：读不出来" }
        if staleDays == 0 { return "今天更新过" }
        if staleDays == 1 { return "1 天没更新" }
        return "\(staleDays) 天没更新"
    }

    /// 谁说的这句总结。规则引擎说的与 AI 说的，可信度不同，
    /// 界面上混成同一种语气就是隐瞒来源。实测没配 AI 时恒为 `rules`。
    var providerLabel: String {
        guard let p = provider, !p.isEmpty, p != "rules" else { return "规则" }
        return p
    }

    /// 悬停/朗读用的完整提交信息：原文标题 + 全 SHA。
    /// 7 位短 SHA 交出去对方查不了，所以这里必须带上完整的。
    var headTip: String {
        let sha = (head?.isEmpty == false) ? head! : headShort
        let subject = (headSubject?.isEmpty == false) ? headSubject! : "（无标题）"
        return "\(subject)（\(sha) · \(headAgo)）"
    }

    /// 这条分支是不是「可以合进默认分支」。
    ///
    /// ⚠️ 判据**逐字对齐引擎** `flow/dashboard.cj:206-209`：
    ///     ahead > 0 && !isDefault && !merged
    /// 三条缺一不可：
    ///   · `aheadOfDefault > 0` —— 相对默认分支的领先数
    ///     （**不是** `pendingCommits`，理由见 `ProjectStatus.needsAction` 的注释）
    ///   · `!isDefault` —— 默认分支不需要合进自己
    ///   · `!merged` —— 已经合过的分支不再提示（模型原来连这个键都没有）
    ///
    /// 提成有名字的派生属性而不是散在调用点里：三处都要用
    /// （`needsAction`、KPI 的待合入分支数、看板列），抄三份必然漂移。
    var isMergeCandidate: Bool {
        aheadOfDefault > 0 && !isDefault && !merged
    }
}

struct JournalEntry: Decodable, Identifiable, Hashable {
    /// 引擎给的日志条目主键（journal.md 里的锚点）。
    ///
    /// ⚠️ 原来这里是**编出来的** `"\(at)/\(branch)/\(mode)"`，
    /// 理由是「引擎的 journal 条目没有 id 键」—— 那句话**当时是对的，现在错了**：
    /// 引擎两个出口都已经恒发 `id`（实测 `status` 内嵌 9 键、
    /// `journal --json` 的 entries 17 键，都含 `id`）。
    ///
    /// 留着编造的 id 就是「同一份事实两种理解」：AI 工具循环拿到引擎主键，
    /// 界面内部却用另一套，跨系统对不上号。引擎给了就用引擎的。
    let id: String

    let at: String
    let mode: String
    let branch: String
    let summary: String
    let providerLabel: String
    /// 本次记录的提交数。-1 = 读不出来（不是 0 个提交）。
    let commitCount: Int
    /// 本次更新触碰到的文档。
    ///
    /// ⚠️ **可选**，而且它「没有值」是有意义的，不是解码容错：
    /// 引擎只让**深度更新**往 journal entry 里写 `docs`（`flow/deep.cj`），
    /// 浅更新路径里 `docChanges` 是在 entry 定稿之后才建的（`flow/update.cj`），
    /// 所以浅更新的条目**压根没有这个键**。
    ///
    /// 原来这里是 `let docs: [String]` 必填，之所以"一直能解"，
    /// 是因为 `flow/status.cj` 当时有一份手挑的 9 键投影，
    /// 对不存在的 `docs` 硬塞了一个 `[]` ——
    /// 于是「这次没碰文档」和「这个键压根没写过」被压成同一个值。
    /// 恒空的假值比缺键更坏：缺键至少能被检测。
    /// 两套形状合并（引擎改用 `journalEntryJson`）后假值没了，
    /// 这个键如实地变成条件性，于是模型必须跟着承认它条件性。
    ///
    /// 用的时候要分三态说：`nil` = 未记录（浅更新不记），
    /// `[]` = 记录了且没碰任何文档，两者不能合成一句话。
    let docs: [String]?

    /// `commitCount` 的口径。**同名不同义**，引擎为此专门加了这个字段。
    ///
    ///   "new"       —— 本轮真正新记录的提交数（浅更新）
    ///   "repoTotal" —— 仓库提交总数（深更新，无上限）
    ///
    /// 引擎的注释写得很直白：「靠 mode 字段去猜口径不行：那是约定不是契约」。
    /// 原来客户端既不解它也不显示它，于是日志里一个 `+6`（本轮新增）
    /// 和一个 `+6`（仓库一共 6 个）渲染成两个一模一样的绿色徽章。
    /// 缺这个字段不是解码容错，是把两种事实压成一种。
    ///
    /// ⚠️ **下面这四个字段必须是 `var`，不能是 `let`——这不是风格问题。**
    /// Swift 合成的 `init(from:)` 对「带初始值的不可变存储属性」**直接跳过**：
    ///     let x: Int? = nil
    /// 编译期就有一句 `immutable property will not be decoded because it is
    /// declared with an initial value which cannot be overwritten`。
    /// 也就是说写成 `let`，这个键**引擎恒发也永远解不出来**，
    /// 字段永远是默认值 —— 代码读起来完全正常，数据却从来没到过。
    /// 本项目因此白丢过 4 个引擎键（下面四个）+ 1 个（`lastCommitAt`），
    /// 代价是仪表盘的「近 7 天 / 近 30 天」筛选**在任何数据下都是死控件**。
    /// 改成 `var` 之后，默认值只作为「缺键 = 旧版本引擎」的兜底，解码照常发生。
    /// ⚠️ 下一个人若把它「整理」回 `let`，缺陷会原样复活。
    var commitCountScope: String? = nil
    /// `commitCount` 是样本而非全量。引擎恒发（缺陷 #188）。
    /// 缺键 = 旧版本引擎，按 false 处理但不能当成「已确认没截断」。
    var commitCountTruncated: Bool? = nil
    /// 仓库真实分支数，-1 = 读不出来。与「建立了基线的分支数」不是同一口径。
    var repoBranchCount: Int? = nil
    /// 追踪分支数 < 仓库分支数。恒发。
    var branchCountTruncated: Bool? = nil

    var modeLabel: String {
        switch mode {
        case "track": return "快照"
        case "shallow": return "浅更新"
        case "deep": return "深度更新"
        case "manual": return "手动"
        default: return mode
        }
    }
}

struct ProjectStatus: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let kind: String
    let remote: String
    let headline: String
    let currentBranch: String
    let defaultBranch: String
    /// 用户改动的文件数。**-1 = 读不出来**（不是 0）。
    /// 引擎的错误桩刻意用 -1：报 0 等于替用户断言「工作区干净」，
    /// 而真相是「整个仓库读不出来」。客户端若把它当 0 会显示「干净」，
    /// 用户据此认为改动已提交。
    let userDirtyCount: Int
    let untrackedCount: Int
    let stashCount: Int
    let worktreeCount: Int
    /// 仓库提交总数。-1 = 读不出来。
    let commitCount: Int
    let lastCommitAgo: String
    /// 最后一次提交时间（ISO8601 带时区）。nil = 引擎没给（非 git 项目）。
    ///
    /// ⚠️ 模型**原来没有这个键**。后果不是少显示一行，而是**筛选行整个是死的**：
    /// 时间窗只能去读 `primaryBranch?.staleDays`，而 `branches` 是**追踪数组** ——
    /// 没有远端基线的仓库它恒为空。实测三个本地仓库（atlas/beacon/legacy）：
    ///     branches       = []      ← 三个全是空
    ///     lastCommitAt   = "2026-08-16T10:00:00+08:00"  ← 唯一有效的活跃度证据
    /// 于是 `updatedWithin` 每一次都走「没有分支记录 → 保留」，
    /// 用户点「近 7 天」，三个项目**一个都不会被筛掉**，控件看起来能用、实际是空转。
    /// 「摆而不动的控件」比没有控件更糟，而它之所以能蒙混过关，
    /// 是因为判据拿**带分支记录的假数据**验的，真数据里那个数组根本没被覆盖（见不变量 104）。
    /// ⚠️ 下面是 `var` 不是 `let`，理由见 `BranchStatus.commitCountScope` 的注释：
    /// Swift 合成解码器会**跳过**带初始值的不可变存储属性，字段就永远解不出来。
    var lastCommitAt: String? = nil
    let commitTypes: [CommitTypeStat]?
    /// commitTypes 是**最近 N 条的样本**，不是全量。引擎恒发这个标志。
    /// 原来客户端完全没建模，于是「类型分布」卡片把样本当全量展示。
    let commitTypesTruncated: Bool
    /// 仓库真实分支数。**-1 = 读不出来**（非 git 项目或 for-each-ref 失败）。
    /// branches 数组只是引擎追踪到基线的那些，两者不是一回事 ——
    /// 实测 16 个分支的仓库，追踪数只有 7。
    let repoBranchCount: Int
    let mergeHint: MergeHint?
    let branches: [BranchStatus]
    let journal: [JournalEntry]?

    /// 引擎说的「需要你知道、但不算失败」。
    ///
    /// ⚠️ 这里原来**压根没有这个字段** —— 引擎给了，模型把它丢了，
    /// 于是那句话说给谁听都没有。实测一个非 git 目录注册成项目后：
    ///     warnings     = ["非 git 仓库：进度基于文件活动时间，不含提交历史"]
    ///     commitCount  = 0
    /// 而界面显示的是「0 个提交」——
    /// 把「压根没测过提交数」显示成「一个提交都没有」。
    /// 这就是本项目最高发的那族缺陷（把「不知道」显示成「没有」），
    /// 只不过这次谎话由**模型层**说出口，不是引擎。
    ///
    /// 引擎已改成恒发（与 journalTruncated 同一口径），所以这里非可选。
    /// 非空时必须显示 —— 尤其 `commitCount == 0` 的项目：
    /// 0 在有 git 时是事实，在非 git 时是**没测过**。
    let warnings: [String]
    /// journal 是**窗口**不是全量。引擎恒发这三个键。
    ///
    /// 原来引擎是 `if (truncated) 才加`，客户端则三个都没建模 ——
    /// 于是「journal 有 8 条」既可能是「一共 8 条」，也可能是「只给了最近 8 条」，
    /// 界面两种情况长得一模一样。这是「上限当全量」这一族在 journal 上的复现
    /// （引擎在 commitTypes / progress / journalLimit 上都做了披露，唯独这里漏了）。
    let journalTruncated: Bool
    /// 窗口大小。未截断时也有值，便于说明「按 N 条取的」。
    let journalLimit: Int
    /// journal.md 里解析不了的行数。>0 ⇒ 日志有内容读不出来，不是「日志很短」。
    let journalUnparsableLines: Int
    /// 该项目的进度存储健康度。恒发。
    let storeHealth: String
    /// 进度元信息：真实条数、截断标志、保留数。
    let progress: ProgressMeta
    let error: String?

    // ── 以下是引擎给了、而模型**原来一个都没有**的键（Phase 3 地基层）。
    //
    // 共同后果：引擎认真算出来的话，界面一个字都显示不出来。
    // 实测一个两提交的项目，`overall.notes` 报的是
    //     "工作区有 2 处未提交改动"
    // 而界面上既没有这句话，也没有任何地方提「2 处」——
    // 不是显示错了，是**根本没这条通路**。

    /// 引擎给的一句人话总结（`summary`）＋需要留意的点（`notes`）。
    /// 实测 notes 会出现「工作区有 N 处未提交改动」这类**别处没有的事实**。
    let overall: OverallMeta?

    /// git tag 列表。里程碑绑 tag 后这里能看到实际有哪些。
    let tags: [String]?

    /// 依赖清单（package.json 等）。用于回答「这是个什么项目」。
    let manifests: [String]?

    /// 工作区脏度的**结构化**版本。
    ///
    /// ⚠️ 与 `userDirtyCount` 的区别：那个是「用户改的」，
    /// 这个是引擎判的（含 `ok`——读不出来时 `ok=false`）。
    /// 两个口径都在时不能混用：读不出来时该说「读不出来」。
    let dirty: DirtyInfo?

    /// 托管文档的清单（`exists` 区分「引擎管着但还没建」与「没有」）。
    let docs: [DocRef]?

    var isGit: Bool { kind == "git" }

    /// 「这条项目该显示哪个分支」——标记为当前的那个，没有就退回第一个。
    ///
    /// ⚠️ **为什么不叫 `currentBranch`**：那个名字已经被引擎给的
    /// **分支名字符串**占了（`currentBranch: String`，见上面字段列表）。
    /// 两个同名不同义的东西并排放在一个类型上，是最容易被静默用错的形式 ——
    /// `p.currentBranch.name` 能编过（String 没有 name…好吧会报错），
    /// 但读代码的人得停下来想一秒才知道拿到的是名字还是对象。
    /// 所以这里叫 `primaryBranch`：**主分支 = 界面上该代表这个项目的那一条**。
    ///
    /// ⚠️ 这条规则原来被**抄了三遍**，而且其中一份还是另一种拼法：
    ///     BarView.swift     `private var currentBranch: BranchStatus? { … }`
    ///     BoardView.swift   `private var currentBranch: BranchStatus? { … }`
    ///     PanelView.swift   内联在 `ForEach` 的 `else if let` 里
    /// 三份字面相同、位置不同 ⇒ 规则要改就得找三处，漏一处就出现
    /// 「菜单栏说 feat、侧栏说 main」。领域规则属于模型层（见不变量 97）。
    var primaryBranch: BranchStatus? {
        branches.first { $0.isCurrent } ?? branches.first
    }

    /// 采集失败 ⇒ 上面所有计数都是未知（-1），不是 0。
    var isUnreadable: Bool { error != nil }

    /// 距最后一次提交多少天。nil = **读不出来**（非 git 项目 / 时间解析不了 / 引擎没给键）。
    ///
    /// ⚠️ 算术必须与引擎**逐字一致**，否则筛选结果会和 KPI 里的
    /// 「近 7 天活跃 / 近 30 天活跃」对不上 —— 那两个数是引擎自己算的：
    ///     let ageDays = (nowMs - ms) / 86400000      // dashboard.cj:219，整数除法
    ///     if (ageDays <= 7)  { commits7d  += 1 }
    ///     if (ageDays <= 30) { commits30d += 1 }
    /// 所以这里也先换算成毫秒差再**整除**，不用 `interval / 86400.0` 的浮点版本：
    /// 两者在负数（未来时间戳）和边界上会差一天，而边界正好是筛选的分界线。
    var daysSinceLastCommit: Int? {
        guard let raw = lastCommitAt, !raw.isEmpty else { return nil }
        guard let date = ProjectStatus.parseISO8601(raw) else { return nil }
        let deltaMs = Int64((Date().timeIntervalSince1970 - date.timeIntervalSince1970) * 1000)
        return Int(deltaMs / 86_400_000)
    }

    /// 引擎的时间戳形如 `2026-08-16T10:00:00+08:00`。
    /// `ISO8601DateFormatter` 的默认策略**不吃带偏移量**的写法，
    /// 解析失败返回 nil —— 而 nil 会被上层读成「读不出来」，
    /// 于是所有项目都留在「全量」里，筛选静默失效。所以这里显式放行偏移量。
    static func parseISO8601(_ raw: String) -> Date? {
        let withOffset = ISO8601DateFormatter()
        withOffset.formatOptions = [.withInternetDateTime]
        if let d = withOffset.date(from: raw) { return d }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFrac.date(from: raw)
    }

    /// 这个项目**在最近 `days` 天内更新过**吗？`days` 为 nil = 不按时间筛。
    ///
    /// ⚠️ **这不是「档位」判定，务必与 `BranchStatus.status` 分开。**
    ///   · `status`（active / idle / stale / merged）是**引擎的档位线**（3/14 天），
    ///     客户端只消费、绝不自己重算（判据「客户端不得拿 staleDays 自己推档位」卡着）。
    ///   · 这里回答的是**另一个问题**：「设计稿仪表盘顶部那条
    ///     「全量历史 / 近 30 天 / 近 7 天」要框住哪些项目」。
    ///     那是**视图窗口**，不是状态分类。
    ///
    /// 判定依据是 `daysSinceLastCommit`（源自 `lastCommitAt`），
    /// **不是** `primaryBranch?.staleDays` —— 后者是追踪分支的「距上次被引擎记录」，
    /// 语义相近但两处不同：无远端基线时 `branches` 恒空、恒判「保留」；
    /// 就算不空，追踪分支的更新也未必等于仓库最后一次提交。
    /// 引擎算 active7d/active30d 用的是 `lastCommitAt`，这里跟着它走才是同一个口径。
    ///
    /// ⚠️ 读不出来（无 git / 时间解析不了）时一律**保留** ——
    /// 滤掉它等于对用户说「它不在近 7 天内」，而真相是「我们不知道」。
    /// 这与本项目最高发的那族缺陷（把「不知道」说成「没有」）同源。
    func updatedWithin(days: Int?) -> Bool {
        guard let days else { return true }          // 不按时间筛
        guard let age = daysSinceLastCommit else { return true }  // 读不出来 → 保留
        return age <= days
    }

    /// 这个项目**还在不在动**。看板分列与项目卡状态词的唯一依据。
    ///
    /// ⚠️ **为什么要有这一份，而不是各视图自己算**：
    /// 同一个问题在代码里被算过两遍，两遍都错，而且错法不同 ——
    ///   · `boardColumn(for:)`  判 `p.branches.contains { $0.status == "stale" }`
    ///   · `ProjectProgressCard.stateWord` 判 `primaryBranch?.status`
    /// 两者都依赖 `branches`（**追踪数组**），而无远端基线的仓库它恒为空。
    /// 于是实测一个 47 天没提交的仓库：
    ///     看板   → 落进 `.active`，「停滞」列**恒为 0**
    ///     项目卡 → 落进 `default`，显示「**正常**」
    /// 「47 天没人动的仓库」被两个界面同时说成活的，
    /// 而根因是同一个：**把「追踪数组里没有」当成了「没有」。**
    ///
    /// 判据只用两类数据：
    ///   1. `primaryBranch?.status` —— 引擎的档位判定（active/idle/stale/merged），
    ///      **有追踪分支时它最精确**，优先采用；
    ///   2. `daysSinceLastCommit` —— 引擎恒发的 `lastCommitAt` 推出来的天数，
    ///      30 这条线是**引擎自己的**（`dashboard.cj:224` 的 `ageDays <= 30`，
    ///      也就是 `active30d` 那个桶），不是客户端新造的阈值。
    ///      没有追踪分支时它就是唯一可用的证据。
    enum Liveness: Hashable {
        /// 采集失败：所有计数都是未知。
        case unreadable
        /// 非 git 项目：没有提交历史可谈。
        case notGit
        /// 有东西等着动手。
        case needsAction
        /// 引擎判定为停滞（只有追踪到基线的分支才可能）。
        case engineStale
        /// 30 天以上没有新提交。
        case quiet
        /// 30 天内有新提交。
        case recent
        /// 提交时间读不出来 —— 「不知道」，不许折进上面任何一档。
        case unknown
    }

    /// 待处理信号：有未提交 / 未跟踪 / stash / 待合入的分支。
    ///
    /// ⚠️ 分支那一项原来写的是 `branches.contains { $0.pendingCommits > 0 && !$0.isDefault }`
    /// —— **引擎已经明确说过这是错的**（`flow/dashboard.cj:200-208`）：
    /// `pendingCommits` 是「引擎还没记录的提交数」，刚跑过 update 的分支恒为 0，
    /// 而它与「这个分支能不能合」毫无关系。引擎为此专门写了回归测试
    /// `testDashboardMergeCandidatesUsesAheadOfDefaultNotPending`，把 `mergeCandidates`
    /// 的判据从 `pendingCommits` 改成 `aheadOfDefault`。
    ///
    /// **客户端把引擎刚修掉的那个错误又犯了一遍。** 实测（三个仓库、5 个分支）：
    ///     分支 feature/b1..b3 / old/branch：aheadOfDefault = 1，pendingCommits = 0
    ///     ⇒ 引擎 `work.mergeCandidates` = 5
    ///     ⇒ 客户端 `needsAction` 判出 0 个项目
    /// 后果是全链路的：侧栏「看板 0」、看板「待处理」列空、
    /// 项目卡把有可合并分支的仓库显示成「正常」。
    ///
    /// ⇒ 判据**必须逐字对齐引擎**（`ahead > 0 && !isDefault && !merged`），
    /// 不许客户端自己发明「能不能合」的判法。
    var needsAction: Bool {
        userDirtyCount > 0 || untrackedCount > 0 || stashCount > 0
            || branches.contains { $0.isMergeCandidate }
            || (mergeHint?.kind == "merge" || mergeHint?.kind == "fast-forward")
    }

    var liveness: Liveness {
        if isUnreadable { return .unreadable }
        if !isGit { return .notGit }
        // ⚠️ **`needsAction` 必须排在 `engineStale` 前面**（2026-10-02 修）。
        //
        // 真 app 现场：侧栏「看板 **1**」而仪表盘「待处理 **3**」——
        // 又是同一件事给了两个答案。根因不是两处用了不同算法（它们都走 liveness），
        // 而是 liveness **内部**先判停滞：`primaryBranch?.status == "stale"`
        // 一命中就 return，`needsAction` 根本没机会被问。
        // 沙箱里 beacon / legacy 正是这种项目 —— 既有停滞的主分支，
        // 又各有一条待合入分支，于是它们的「有活要干」被整段吞掉。
        //
        // 两条理由支持把「等我动手」排在「多久没动」前面：
        //   1. 两者**不互斥**。先命中哪个纯属书写顺序，而书写顺序不该决定事实。
        //   2. `.attention` 列自己的表头就是「有未提交、未跟踪、stash 或
        //      **待合入的分支**」—— 按这句话的定义，一个有待合入分支的项目
        //      无论主分支多停滞都该进这一列。旧顺序和列的定义是矛盾的。
        //
        // 代价照实说：「停滞」列会因为项目被更紧急的状态吸走而变少。
        // 但**信息没有丢** —— 每张项目卡仍单独写着「main: 停滞」
        // （`branchScopeLine` 那一行，与 liveness 无关），详情页也在。
        if needsAction { return .needsAction }
        // 引擎的档位最精确，但**只在它真的给出一行分支记录时**才有。
        if primaryBranch?.status == "stale" { return .engineStale }
        guard let age = daysSinceLastCommit else { return .unknown }
        return age <= 30 ? .recent : .quiet
    }

    /// 状态词（项目卡用）。**只从事实推，不写修辞**。
    ///
    /// ⚠️ 这里原来写的是 `b.staleDays >= 14` —— 被自己的判据抓出来过：
    /// 14 天是引擎 `progress.cj:30-36` 的档位线，客户端再写一遍就是两个真相源。
    /// 改成读引擎的 `b.status` 之后**又错了**：那也是追踪数组，
    /// 无远端仓库拿不到，于是全部落进 `default: 正常`。
    /// 现在统一走 `liveness`，两条证据按可得性择一。
    var stateWord: (text: String, tone: Liveness) {
        switch liveness {
        case .unreadable:  return ("读不出来", .unreadable)
        case .notGit:      return ("非 git 目录", .notGit)
        case .needsAction: return ("有未提交改动", .needsAction)
        case .engineStale: return ("停滞", .engineStale)
        case .quiet:
            // ⚠️ 措辞跟着依据走：这里用的是 30 天那条线，
            // 写「停滞」会让人以为是引擎的 14 天档位。
            return ("\(daysSinceLastCommit ?? 0) 天没更新", .quiet)
        case .recent:      return ("正常", .recent)
        case .unknown:     return ("状态读不出来", .unknown)
        }
    }

    /// 「N 个已跟踪分支」＋「仓库共 M 个」的披露。
    /// M 读不出来时只报追踪数并说明，不能显示 0 也不能假装知道。
    var branchScopeLine: String {
        let tracked = branches.count
        if repoBranchCount < 0 {
            return "\(tracked) 个已跟踪分支（仓库真实分支数读不出来）"
        }
        if repoBranchCount > tracked {
            return "\(tracked)/\(repoBranchCount) 个分支已跟踪"
        }
        return "\(tracked) 个分支"
    }

    /// 工程脉搏（有值得说才返回）
    ///
    /// ⚠️ -1 必须被当「读不出来」，不能当 0。
    /// 原来 `userDirtyCount > 0` 配上引擎错误桩的 -1 会让脉搏整条为空 ——
    /// 用户看到的是「没有未提交改动」，而真相是「工作区根本读不出来」。
    var pulseLine: String? {
        if isUnreadable {
            return "仓库读不出来（\(error ?? "未知原因")）"
        }
        var parts: [String] = []
        if userDirtyCount > 0 { parts.append("未提交 \(userDirtyCount)") }
        if untrackedCount > 0 { parts.append("未跟踪 \(untrackedCount)") }
        if stashCount > 0 { parts.append("stash \(stashCount)") }
        if worktreeCount > 1 { parts.append("工作区 ×\(worktreeCount)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 脉冲行上的提交构成。判定在 `CommitTypeComposition.swift`（零依赖纯函数）。
    ///
    /// ⚠️ 原来这里是 `types.prefix(5)` 内联 + 只按 `commitTypesTruncated` 披露，
    /// 而后者说的是**引擎的采样窗口**、不是界面的 top-5：
    /// 引擎数据越完整（`commitTypesTruncated=false`，即「这就是全量」），
    /// 界面藏掉的类型就越多、披露就越少（缺陷 #206）。
    /// 实测 14 提交 14 种类型的仓库：引擎给 12 条、客户端只列 5 条、零提示。
    var commitTypeLine: String? {
        commitTypeComposition(
            entries: (commitTypes ?? []).map { (type: $0.type, count: $0.count) },
            sampleTruncated: commitTypesTruncated,
            totalCommits: commitCount
        ).line
    }
}

/// 进度存储的元信息。引擎恒发这 8 个键。
struct ProgressMeta: Decodable, Hashable {
    let updatedAt: String
    let lastUpdateAt: String
    let lastTrackAt: String
    let lastDeepAt: String
    /// 真实条数，**不是** progress.json 里被截到 200 的数组长度。
    let entryCount: Int
    /// 真的撞到上限了吗（不是「没采到样本」）。
    let entryCountTruncated: Bool
    /// 实际保留了多少条。entryCount > entriesKept ⇒ 被截断了。
    let entriesKept: Int
    let runCount: Int

    /// 条数披露：被截断时写「N/M」，否则写全量。
    var entryCountLine: String {
        if entryCountTruncated || entryCount > entriesKept {
            return "\(entriesKept)/\(entryCount) 条（已截断）"
        }
        return "\(entryCount) 条"
    }
}

struct StatusEnvelope: Decodable {
    let projects: [ProjectStatus]
    let summary: EngineSummary?
    /// 引擎恒发（CLI 与 MCP 两侧一致）。消费方据此知道文案语言，
    /// 不用从别的字段猜。
    let language: String?
}

// MARK: - 仪表盘（deepgit dashboard --json）

struct DashboardProjects: Decodable, Hashable {
    /// 只数**采集成功**的项目。
    let total: Int
    /// 注册表里一共多少条（= 表格会渲染的行数）。引擎恒发。
    /// 少了它，「共 N 个项目」就只能是 total，采集失败的项目从视野里消失。
    let listed: Int
    /// 采集失败的数量。>0 时必须披露。
    let failed: Int
    let dirty: Int
    let active7d: Int
    let active30d: Int
}

struct DashboardWork: Decodable, Hashable {
    let branches: Int
    let mergeCandidates: Int
    let untrackedFiles: Int
    let stashes: Int
}

struct LanguageStat: Decodable, Hashable {
    let language: String
    let count: Int
}

struct MilestoneCounts: Decodable, Hashable {
    let open: Int
    let done: Int
    let dropped: Int
    /// 仓库读不出来、**不知道**达没达成的里程碑数。
    /// 引擎刻意把它与 open/done/dropped 分开 —— 混进任一侧都是谎报。
    let unknown: Int
    /// milestones.json 的存储健康度。恒发：空数组 + corrupt 与「真的没有里程碑」
    /// 必须能被区分开。
    let storeHealth: String
    /// 存储降级/损坏 ⇒ 上面那些 0 不是「没有」。
    let degraded: Bool
    /// 实际读到的条数（损坏时是 0，而它**不是**「没有里程碑」的证据）。
    let readCount: Int
    /// 属于已停用项目、被故意排除的条数。
    let excludedDisabled: Int
    /// 所属项目已不存在的孤儿条数（数据还在 milestones.json 里）。
    let orphaned: Int
}

struct MilestoneItem: Decodable, Identifiable, Hashable {
    let projectId: String
    let projectName: String
    let name: String
    let description: String
    /// 引擎发的是 **effectiveStatus**，可以是 `unknown` —— 仓库读不出来，
    /// 我们**不知道**它达没达成。不是「没达成」。
    let status: String
    let targetDate: String
    /// -1 = 未设置目标日期（不是「今天到期」）。
    let daysToTarget: Int
    let overdue: Bool
    let tag: String
    /// 引擎解析后的实际 tag 名（未显式绑定时用里程碑名兜底）。
    let tagName: String
    let tagReached: Bool
    /// 创建以来的提交数，**-1 = 读不出来**（不是 0）。
    let commitsSince: Int
    /// commitsSince >= 0。与 -1 配套。
    let commitsSinceReadable: Bool
    /// 仓库是否可读。false ⇒ status 只能是 unknown。
    let gitReadable: Bool
    let createdAt: String
    let completedAt: String
    /// 引擎给的「为什么核验不了」，**恒发**：可读时是空串。
    ///
    /// 之前它是 `if (!gitReadable) 才加` 的条件性键，而且只在 `milestone list`
    /// 出口有、`dashboard` 出口根本没有（实测降级态：CLI 18 键 / dashboard 17 键）。
    /// 条件性发键意味着消费方要么写两套解码分支，要么把「键不存在」当默认值 ——
    /// 而默认的空串恰好等于「一切正常」，于是故障被读成正常。
    /// 现在三个出口共用 kernel.milestoneJson 一份形状，恒发。
    let unverifiedReason: String

    /// 列表用的稳定标识：项目 + 里程碑名。
    ///
    /// 引擎在 milestones.json 里存着一个主键 `id`（m_xxx），但**只读出口不发它**
    /// （剥在 kernel.milestoneJson）。原因是它是「只出不进」的：全引擎没有任何 API
    /// 收它作入参 —— `milestone_action` 用的是 project + name。若留着它，
    /// 客户端这个算出来的 id 与它永远不相等，同一里程碑就有两个身份；
    /// 而 LLM 在列表里看到 `id`，还会自然地拿它当句柄传回去，注定失败。
    ///
    /// 列表的 diff 需要的是「同一项目内唯一」，用 projectId+name 更合适
    /// （同一里程碑名在不同项目下会重复，只用 name 不唯一）。
    var id: String { "\(projectId)/\(name)" }
    /// 我们**不知道**达没达成 —— 与「已达成」是相反的两件事，必须分开表达。
    ///
    /// 引擎的注释原话：「『我们不知道』和『没有达成』是两件相反的事，
    /// 必须分开表达」。仓库损坏 / 卷掉线 / .git/objects 丢失时（引擎描述的真实事故：
    /// 此时成就数反而减少且零告警）status 就是 unknown。
    ///
    /// 原实现没有这个分支，会落到最后一行渲染成「进行中」+ 蓝色虚线圆圈 ——
    /// **最该报警的时刻被渲染成了确定性结论**。
    var isUnknown: Bool { status == "unknown" || !gitReadable }

    var statusLabel: String {
        if isUnknown { return "无法核验" }
        if status == "done" { return "已达成" }
        if status == "dropped" { return "已放弃" }
        return overdue ? "已逾期" : "进行中"
    }

    /// 目标日期描述：还剩 N 天 / 逾期 N 天 / 无
    var dueText: String {
        guard !targetDate.isEmpty, daysToTarget != -1 else { return "" }
        if daysToTarget >= 0 { return "还剩 \(daysToTarget) 天" }
        return "逾期 \(-daysToTarget) 天"
    }

    /// 提交数描述。读不出来必须说读不出来，不能显示「0」。
    var commitsText: String {
        if !commitsSinceReadable || commitsSince < 0 { return "提交数读不出来" }
        return "创建以来 \(commitsSince) 提交"
    }

    /// 核验不了时的**原因**；正常时是空串。
    ///
    /// 引擎恒发这个键（可读时为空串），所以这里不需要判「键在不在」——
    /// 判了就得写两套分支，而两套分支里最容易漏掉的那套会把故障显示成正常。
    /// 万一拿到空值（老引擎），退回原先的「读不出来」文案，不显示空白。
    var unverifiedNote: String {
        unverifiedReason.isEmpty ? "提交数读不出来" : unverifiedReason
    }
}

struct DashboardMilestones: Decodable, Hashable {
    let counts: MilestoneCounts
    let items: [MilestoneItem]
}

struct ActiveProject: Decodable, Hashable {
    let name: String
    let lastCommitAgo: String
    let headline: String
}

struct Dashboard: Decodable {
    let projects: DashboardProjects
    let work: DashboardWork
    let languages: [LanguageStat]
    let milestones: DashboardMilestones
    let activeProjects: [ActiveProject]
    let fetchedAt: String
    /// 有项目撞到跟踪文件上限，被丢掉的文件里可能还含整类语言。
    /// 引擎早就恒发这个字段了，本模型原先**根本没解**，
    /// 于是这份披露只对 `--json` 的消费方有效，界面上永远看不到。
    let languagesTruncated: Bool?
    /// 语言采集**失败**的项目数（引擎侧恒发，0 也在）。
    /// 与截断是两回事：截断 = 看了留一部分；失败 = 压根没看成。
    /// 没有它，失败的项目会静默消失，而截断标志是 false，
    /// 界面等于反过来告诉用户「这份语言画像是完整的」。
    let languagesFailed: Int?
    /// 失败原因样例，供界面直接显示。
    let languagesFailedReasons: [String]?
    /// 引擎把**语言条数**砍到上限了（引擎侧 #205，与 `languagesTruncated` 是两个独立轴）。
    ///
    /// 没有它，界面无法区分「这就是全部语言」与「只给了前 N 种」——
    /// 而两者在 `languages` 数组的形状上完全相同。
    let languagesTopCut: Bool?
}

struct MilestonesEnvelope: Decodable {
    let milestones: [MilestoneItem]
    /// milestones.json 的存储健康度，恒发（实测 CLI 侧键集：
    /// milestones / orphaned / readCount / storeHealth / excludedDisabled）。
    /// 少了它，空数组会被读成「还没有里程碑」——
    /// 而真相可能是「数据还在盘上，只是暂时读不出来」。
    let storeHealth: String
    /// 实际读到的条数。
    let readCount: Int
    /// 属于已停用项目、被故意排除的条数。
    let excludedDisabled: Int
    /// 所属项目已不存在的孤儿条数。客户端必须能看到它们还在，
    /// 否则用户会以为里程碑已被系统删除（数据其实在 milestones.json 里）。
    let orphaned: [OrphanMilestone]
}

struct OrphanMilestone: Decodable, Hashable {
    let projectId: String
    let name: String
    let targetDate: String
    let status: String
}

// MARK: - 展示辅助

/// 统一的状态色：active 绿 / idle 黄 / stale 红 / merged 紫
enum StatusColor {
    static func systemColor(for status: String) -> String {
        switch status {
        case "active": return "green"
        case "idle": return "yellow"
        case "stale": return "red"
        case "merged": return "purple"
        default: return "gray"
        }
    }
}

// MARK: - 项目文档（deepgit docs --json）

struct DocFile: Decodable, Identifiable, Hashable {
    let file: String
    let content: String

    var id: String { file }
}

// MARK: - 更新结果（deepgit update/deep <项目> --json）

/// 一次文档写入的结果。形状照 `updateResultToJson` / `deepResultToJson` 产出。
struct DocChange: Decodable, Hashable {
    let file: String
    let changed: Bool
    let created: Bool
    /// `--dry-run` 才有的预览文本。
    let preview: String?
    /// 本次写入前的备份**真实路径**。**引擎恒发**（缺陷 #210）：
    /// 空串 = 确实没有备份（新建 / 无变化 / dry-run），不是「不知道」。
    ///
    /// 原来引擎在 `flow/{update,deep}.cj` 的调用点把 `res.backup` 直接丢掉了，
    /// 于是引擎每轮都留一份、按 `backupKeep` 裁剪，而用户从不知道它存在 ——
    /// 想要回滚时无从下手，旧版本还会被静默删掉。
    let backup: String

    var outcome: DocOutcome {
        DocOutcome(file: file, changed: changed, created: created, backup: backup)
    }
}

/// 单项目 update/deep 的载荷。顶层是**扁平对象**（实测，不是 `{result:…}` 包装）。
struct UpdateResultEnvelope: Decodable, Hashable {
    let project: String
    let mode: String
    let docs: [DocChange]

    var outcome: UpdateOutcome { updateOutcome(docs.map { $0.outcome }) }
}

/// 多项目 update/deep 的载荷（`results.size > 1` 时引擎才给这个形状；
/// **恰好 1 个项目时给的是裸的 `UpdateResultEnvelope`** —— 见 `multiProjectJson`）。
struct UpdateAllEnvelope: Decodable, Hashable {
    struct One: Decodable, Hashable {
        let project: String
        let docs: [DocChange]?
        /// 失败项目带这个键（`error` / `code`）。
        let error: String?
    }
    let results: [One]
    let count: Int
    let succeeded: Int
    let failed: Int
}

struct DocsEnvelope: Decodable {
    let docs: [DocFile]
    /// 存在但读取失败的文档文件名。**引擎恒发**（空时是空数组）。
    /// 原来完全没建模，于是读失败的文档只是从数组里消失，
    /// 详情页少一张卡片，用户会认为项目根本没有该文档。
    ///
    /// 引擎的注释原话：「读失败的文档按项目分组披露。不能只丢进数组 ——
    /// 数组少一条，消费方看到的就是『这个项目的 README 不存在』」。
    let unreadable: [String]
}

// MARK: - git 操作（deepgit git <op> <项目> --json）

struct GitOpResponse: Decodable {
    let op: String
    let ok: Bool
    let output: String
    let project: String?
}
