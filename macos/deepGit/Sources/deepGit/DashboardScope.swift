// DashboardScope.swift — 仪表盘的筛选口径（纯函数层，零 SwiftUI 依赖）。
//
// 【为什么单独抽出来】
// 设计稿的仪表盘顶部有一条**筛选行**（时间跨度 / 提交类型 / 重新索引）。
// 这类控件最常见的失败不是「不好看」，而是**摆在那里不起作用** ——
// 用户拨了「近 7 天」而卡片数字纹丝不动，于是整个筛选行被当成装饰。
// 判定放在视图里就只能靠肉眼发现，所以抽成纯函数，由 ClientCheck 直接断言。
//
// 【与不变量 101 的关系】
// 那条讲「放弃某条路的理由不能蹭别人证据」。这里反过来：
// 筛选控件要成立，就必须**真的有东西被它改变**。
// 所以每个枚举都配一个「过滤后是什么」，而不是只有一个名字。

import Foundation

// MARK: - 时间跨度

/// 筛选行的时间跨度。设计稿是「全量历史 / 近 30 天 / 近 7 天」。
///
/// ⚠️ **我们能过滤的到底是什么**：引擎只给「最后更新距今多少天」
/// （`BranchStatus.staleDays`）与两个**聚合**活跃数（active7d / active30d），
/// **没有**逐项目的提交时间序列。所以这里的「时间跨度」= 按最近更新天数
/// 分档，而不是「只统计这段时间内的提交」—— 后者需要的数据引擎没有（D2 已裁定）。
/// 界面上必须照实说是「最近更新」，不能写成「近 7 天的提交」。
enum DashSpan: String, CaseIterable, Hashable {
    case all
    case d30
    case d7

    var label: String {
        switch self {
        case .all: return "全量"
        case .d30: return "近 30 天"
        case .d7:  return "近 7 天"
        }
    }

    /// 该档位的时间窗（天）。nil = 不按时间筛。
    ///
    /// ⚠️ 这里**只有数字，没有判定**。判定在 `ProjectStatus.updatedWithin(days:)`
    /// （模型层）—— 因为 `staleDays` 只有模型层可以读，视图层出现它就会红。
    /// 早先我把 `accepts(staleDays:)` 写在本文件里，等于在客户端新造一套阈值，
    /// 与引擎的 3/14 天档位线并列成「两个真相源」（判据已抓到）。
    var maxDays: Int? {
        switch self {
        case .all: return nil
        case .d30: return 30
        case .d7:  return 7
        }
    }

    /// 档位必须**从宽到严**递增，否则「近 7 天」比「全量」还宽就是反的。
    var isStricterThanAll: Bool { maxDays != nil }
}

// MARK: - 提交类型

/// 筛选行的提交类型（设计稿是「所有提交类型 (All Types)」下拉）。
///
/// ⚠️ **这个筛选只作用于提交结构条**：它决定堆叠条画哪几段、图例列哪几行。
/// 它**不改** KPI 数字 —— 因为 `commitTypes` 是引擎给的**最近 N 条样本**
/// （`commitTypesTruncated` 恒发），拿样本去重算「全局提交总数」是拿小样本充总量。
/// 这条边界必须写在类型上而不是靠注释，否则下一个人会顺手把它接到 KPI 上。
enum DashCommitFilter: Hashable {
    /// 不筛。
    case all
    /// 只看某一类（按 `CommitTypeStat.type` 匹配）。
    case only(String)

    /// 该档位下要画出来的类型集合。`nil` = 全画。
    func allowed(_ type: String) -> Bool {
        switch self {
        case .all:        return true
        case .only(let t): return t == type
        }
    }

    var label: String {
        switch self {
        case .all:       return "所有提交类型"
        case .only(let t): return t
        }
    }
}

// MARK: - 组合筛选

/// 一份筛选 = 时间跨度 + 提交类型 + 重新索引的节流。
///
/// 纯数据、可单测。视图只负责把控件的值塞进来、把结果画出去。
struct DashFilter: Hashable {
    var span: DashSpan = .all
    var commits: DashCommitFilter = .all

    /// 项目是否落在范围内。判定委托给模型层的 `updatedWithin(days:)` ——
    /// 本文件**不许**出现 `staleDays`（档位线归引擎，判据卡着）。
    /// 没有分支记录的项目一律保留：它的真实状态是「不知道」，不是「不在范围内」。
    func keeps(project: ProjectStatus) -> Bool {
        project.updatedWithin(days: span.maxDays)
    }

    /// 堆叠条 / 图例要画的段。
    func keptStats(_ stats: [CommitTypeStat]) -> [CommitTypeStat] {
        stats.filter { commits.allowed($0.type) }
    }
}

// MARK: - 里程碑页的取数口径

/// 里程碑页（`MilestonesView`）的取数与统计。
///
/// ⚠️ **为什么里程碑页必须接范围选择器**：
/// 它是**唯一能改数据**的视图（新建 / 达成 / 放弃 / 删除都走这里），
/// 仪表盘和项目卡上的里程碑全是只读副本。
/// 于是「单仓库」视图里用户正盯着 atlas 的里程碑，里程碑页却摊开全部 3 个仓库的 ——
/// 范围选择器说「atlas」，页面说「全部」，两句话在同一块屏幕上。
///
/// ⚠️ **统计不许拿明细当全量**：
/// `DashboardMilestones.items` 没有截断标志，而 `MilestoneCounts.readCount`
/// 是引擎真正读到的条数。两者不等时，按明细算出来的分组统计**不是全量**，
/// 必须说出来 —— 这与本项目反复踩的「上限当全量」同源。
enum DashMilestoneScope {
    /// 按范围收窄。`project` 为 nil = 全部项目。
    ///
    /// ⚠️ 收窄的是**明细**。全局 `counts`（仪表盘 KPI 用的那个）没有项目维度，
    /// 收窄后**不能**继续报它 —— 那会把「atlas 完成率 0%」说成 atlas 的完成率。
    static func items(_ all: [MilestoneItem], project: String?) -> [MilestoneItem] {
        guard let project else { return all }
        return all.filter { $0.projectName == project }
    }

    /// 按项目分组，保持首现顺序（明细本身是按项目成组的，
    /// 所以首现顺序就是稳定的项目顺序，不额外排序）。
    static func groups(_ items: [MilestoneItem]) -> [(project: String, items: [MilestoneItem])] {
        var order: [String] = []
        var buckets: [String: [MilestoneItem]] = [:]
        for m in items {
            if buckets[m.projectName] == nil {
                order.append(m.projectName)
                buckets[m.projectName] = []
            }
            buckets[m.projectName]?.append(m)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    /// 明细里的状态分布。
    ///
    /// `unknown` 单列 —— 那是「仓库读不出来，不知道达没达成」，
    /// 混进 open 或 done 都是把「不知道」说成事实。
    static func tally(_ items: [MilestoneItem])
        -> (open: Int, done: Int, dropped: Int, unknown: Int) {
        var t = (open: 0, done: 0, dropped: 0, unknown: 0)
        for m in items {
            switch m.status {
            case "done":    t.done += 1
            case "dropped": t.dropped += 1
            case "open":    t.open += 1
            default:        t.unknown += 1   // unknown / 未来新增的档位
            }
        }
        return t
    }

    /// 明细是否等于引擎真正读到的全部。
    ///
    /// ⚠️ `readCount` 是**引擎读到的条数**，而 `items` 是它给了我们的明细。
    /// 两者不等就说明明细被窗口截过，此时按明细算出来的任何数都只是**下界**。
    static func isComplete(_ items: [MilestoneItem], counts: MilestoneCounts?) -> Bool {
        guard let counts else { return false }
        return items.count == counts.readCount
    }
}

// MARK: - KPI 选取

/// 设计稿仪表盘顶部是 **4 张**精选 KPI（带副说明、可带进度条），
/// 而我们原来是 8 张**平铺**小卡（项目总数/7天/30天/脏/分支/待合入/未跟踪/stash），
/// 每张只有「数字 + 标签」，没有任何解释，也没有主次。
///
/// 8 → 4 不是删信息，是把它们**归并成有主次的四问**：
///   1. 我有多少东西            → 项目总数（副说明带活跃度）
///   2. 目标完成到什么程度      → 里程碑完成率（带进度条）
///   3. 有多少事等着我处理      → 待处理项（脏 + 待合入 + 未跟踪）
///   4. 仓库面有多宽            → 跟踪分支（副说明带 tag 数）
/// 少掉的 7 天/30 天/未跟踪/stash 单项并没有丢：它们作为**副说明**挂在对应 KPI 上，
/// 或者作为项目卡里的字段。删的是「平铺」，不是信息。
struct DashKPI: Hashable, Identifiable {
    enum Kind: String, Hashable {
        case projects, milestones, attention, reach
    }
    let kind: Kind
    let title: String
    /// 主数字。里程碑完成率是 0…100；其余是计数。
    let value: Int
    /// 副说明：回答「这个数字意味着什么」。
    let caption: String
    /// 0…1，只有需要表达「完成度」的 KPI 才有。
    var progress: Double? = nil
    /// 语义色（attention 用）。
    var tint: Int = 0

    var id: String { kind.rawValue }
}

/// 口径全在纯函数里，视图不自己算。
enum DashKPIBuilder {
    /// `d` 是仪表盘聚合；`projects` 是逐项目（用于算 tag / 活跃副说明）。
    static func kpis(_ d: Dashboard, projects: [ProjectStatus]) -> [DashKPI] {
        let listed = d.projects.listed
        let failed = d.projects.failed

        // 1. 项目总数 —— 副说明必须带上「采集失败 N 个」，
        //    否则 listed < registered 时失败的项目从视野里消失（本项目踩过）。
        var projectsCaption = "近 7 天活跃 \(d.projects.active7d) · 近 30 天 \(d.projects.active30d)"
        if failed > 0 { projectsCaption += " · 采集失败 \(failed) 个" }
        if d.projects.total < listed { projectsCaption += " · 读得出来 \(d.projects.total)/\(listed)" }

        // 2. 里程碑完成率 —— 分母只取「达没达成有答案的」
        //    （done + open），**不把 unknown 塞进分母**：unknown 是「不知道」，
        //    算进分母等于假装它不是目标。unknown 单独在副说明里披露。
        let ms = d.milestones.counts
        let decided = ms.done + ms.open
        let pct = decided > 0 ? Int((Double(ms.done) * 100 / Double(decided)).rounded()) : 0
        var msCaption = "进行中 \(ms.open) · 已达成 \(ms.done)"
        if ms.unknown > 0 { msCaption += " · \(ms.unknown) 个读不出来" }

        // 3. 待处理项 —— 三类风险合并成一个「要你动手」的数，
        //    因为拆成三张卡时用户要自己加；合并后它们各自仍然作为项目卡字段出现。
        let attention = d.projects.dirty + d.work.mergeCandidates
            + (d.work.untrackedFiles > 0 ? 1 : 0)

        // 4. 分支 —— ⚠️ **这里原本直接用 `d.work.branches`，是个谎报。**
        //    引擎的 `work.branches` = 各项目 `branches` **追踪数组**的长度之和
        //    （dashboard.cj:200 `branchTotal += branches.size`），
        //    而追踪数组只含「引擎追踪到基线的那些」。实测一个 4 分支的仓库：
        //        repoBranchCount = 4     ← 真实值，引擎恒发
        //        branches        = []    ← 追踪数组空（无远端基线可比）
        //    于是 `work.branches` = 0，界面显示「跟踪分支 0」——
        //    用户读成「这个项目群一个分支都没有」。**把「明细读不到」说成了「没有」。**
        //    修法：主数字用 repoBranchCount（真实值），把追踪数组长度作为副说明，
        //    两者不一致本身就是一条该说给用户听的信息。
        let realBranches = projects.reduce(0) { $0 + max(0, $1.repoBranchCount) }
        let unreadableBranchCount = projects.filter { $0.repoBranchCount < 0 }.count
        var reachCaption = "\(d.work.stashes) 个 stash · \(d.work.untrackedFiles) 个未跟踪文件"
        reachCaption += " · 已跟踪明细 \(d.work.branches) 条"
        if unreadableBranchCount > 0 {
            reachCaption += " · \(unreadableBranchCount) 个项目的分支数读不出来"
        } else if d.work.branches < realBranches {
            reachCaption += "（其余未纳入追踪）"
        }
        let tagCount = projects.reduce(0) { $0 + ($1.tags?.count ?? 0) }
        let tagKnown = projects.contains { $0.tags != nil }
        if tagKnown { reachCaption += " · \(tagCount) 个 tag" }

        return [
            DashKPI(kind: .projects, title: "项目总数", value: d.projects.total,
                    caption: projectsCaption),
            DashKPI(kind: .milestones, title: "里程碑完成率", value: pct,
                    caption: msCaption,
                    progress: decided > 0 ? Double(ms.done) / Double(decided) : nil),
            DashKPI(kind: .attention, title: "待处理", value: attention,
                    caption: "有改动的 \(d.projects.dirty) · 待合入 \(d.work.mergeCandidates)"
                            + " · 未跟踪文件 \(d.work.untrackedFiles)",
                    tint: attention > 0 ? 1 : 0),
            DashKPI(kind: .reach, title: "分支", value: realBranches,
                    caption: reachCaption),
        ]
    }
}
