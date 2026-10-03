// 仪表盘的 KPI 口径 —— 与 macOS 端 `DashboardScope.swift` 的 `DashKPIBuilder`
// 逐条对应。
//
// 为什么单独一个文件、为什么是纯函数：
// 这四个数字**同时**出现在页头摘要和四张卡上。macOS 端为同一件事
// 栽过一次 —— 页头自己算了一遍「待处理」，KPI 卡又算了一遍，
// 一个数项一个数项目，同一屏给了两个答案。修法不是「把页头改对」，
// 是**让页头没有自己的算法**：两边都从这一个数组读。
// 所以这里产出的 `kpis` 数组是唯一出处，页头 `dashSummaryLine` 只读它。
package deepdolphin_linux

import std.collection.*

/// 四张 KPI 的身份。顺序即 macOS 端的顺序。
public enum DashKpiKind {
    | Projects
    | Milestones
    | Attention
    | Reach
}

/// 一张 KPI。**`caption`（副说明）不是装饰** ——
/// macOS 端 `KPIWideCard` 的注释原话：
/// 「它回答『这个数字意味着什么』，没有它，数字就只是数字。」
public class DashKpi {
    public let kind: DashKpiKind
    public let title: String
    public let value: Int64
    public let caption: String
    /// 有进度条时为 Some。里程碑完成率才有。
    public let progress: Option<Float64>
    /// 有强调色时为真。待处理为 0 时不该染红 —— 「没有待办」不是坏事。
    public let tint: Bool

    public init(
        kind: DashKpiKind,
        title: String,
        value: Int64,
        caption: String,
        progress: Option<Float64>,
        tint: Bool
    ) {
        this.kind = kind
        this.title = title
        this.value = value
        this.caption = caption
        this.progress = progress
        this.tint = tint
    }
}

/// 逐项目待合入的分支总数。口径与看板「待处理」列同源
/// （`Branch.isMergeCandidate`），不许另写一套。
private func mergeBranchTotal(projects: ArrayList<Project>): Int64 {
    var n: Int64 = 0
    for (p in projects) {
        for (b in p.branches) {
            if (b.isMergeCandidate()) {
                n += 1
            }
        }
    }
    return n
}

/// 四张 KPI。**读数一律取引擎真实发的键**。
///
/// ⚠ 三处口径都有历史教训，改之前先读：
///  1. 「项目总数」必须用 `listed`（注册表条数）而不是 `total`（采集成功数）。
///     实测注册 6、3 个采集失败 ⇒ total=3 / listed=6。用错的话标题写「项目总数 3」，
///     而侧栏写「仓库（6/6）」—— 同一屏两个答案，且用户先看到的是大数字。
///  2. 「待处理」必须是**项目数**，且与侧栏徽标 / 看板「待处理」列同规则
///     （`projectNeedsAction`）。原来是 `dirty + mergeCandidates + (untracked>0?1:0)` ——
///     项目数、分支数、布尔三种单位加成一个数，那个数字没有意义。
///  3. 「分支」主数字必须用 `repoBranchCount` 之和。引擎的 `work.branches`
///     是「各项目 branches 追踪数组长度之和」—— 没远端基线的仓库那个数组是空的，
///     于是 `work.branches` 会是 0，把「明细读不到」说成「没有分支」。
public func buildDashKpis(d: Dashboard, projects: ArrayList<Project>): Array<DashKpi> {
    // ── 1. 项目总数 ──
    var projectsCaption = "可读取 ${d.total}/${d.listed} · 近 7 天活跃 ${d.active7d} · 近 30 天 ${d.active30d}"
    if (d.failed > 0) {
        projectsCaption += " · 采集失败 ${d.failed} 个"
    }
    if (d.excludedDisabled > 0) {
        projectsCaption += " · 已停用 ${d.excludedDisabled} 个（未计入）"
    }

    // ── 2. 里程碑完成率 ──
    // 分母只取「达没达成有答案的」（done + open）。**不把 unknown 塞进分母** ——
    // unknown 是「不知道」，算进分母等于假装它不是目标。
    let ms = d.milestoneCounts
    let decided = ms.decided()
    var pct: Int64 = 0
    var progress: Option<Float64> = None
    if (decided > 0) {
        pct = (ms.done * 100 + decided / 2) / decided   // 四舍五入，整数除法不丢精度
        progress = Some(Float64(ms.done) / Float64(decided))
    }
    var msCaption = "进行中 ${ms.open} · 已达成 ${ms.done}"
    if (ms.unknown > 0) {
        msCaption += " · ${ms.unknown} 个读不出来"
    }
    if (ms.orphaned > 0) {
        // 所属项目已不存在 —— 它既不是「进行中」也不是「已达成」，
        // 静默吞掉就等于把一条里程碑说成不存在。
        msCaption += " · ${ms.orphaned} 条所属项目已不在"
    }
    if (ms.degraded || ms.storeHealth != "ok") {
        msCaption += " · 进度库读不完整（${ms.storeHealth}）"
    }

    // ── 3. 待处理 ──
    var attention: Int64 = 0
    for (p in projects) {
        if (projectNeedsAction(p)) {
            attention += 1
        }
    }
    let mergeBranches = mergeBranchTotal(projects)
    var attentionCaption = "有未提交/未跟踪/stash 的 ${d.dirty} 个"
    if (mergeBranches > 0) {
        attentionCaption += " · 待合入分支 ${mergeBranches} 条"
    }
    attentionCaption += " · 未跟踪文件 ${d.untrackedFiles} 个"

    // ── 4. 分支 ──
    var realBranches: Int64 = 0
    var unreadableBranchProjects: Int64 = 0
    var tagCount: Int64 = 0
    var tagKnown = false
    for (p in projects) {
        if (p.repoBranchCount < 0) {
            unreadableBranchProjects += 1
        } else {
            realBranches += p.repoBranchCount
        }
        // tags 是恒发键（可能为 []）。空数组说明「确实没有」还是「没给」分不清，
        // 所以用 `storeHealth` 有没有正常来判断是不是拿到了真数据。
        if (p.storeHealth == "ok") {
            tagKnown = true
        }
        tagCount += Int64(p.tags.size)
    }
    var reachCaption = "${d.stashes} 个 stash · ${d.untrackedFiles} 个未跟踪文件"
    reachCaption += " · 已跟踪明细 ${d.branches} 条"
    if (unreadableBranchProjects > 0) {
        reachCaption += " · ${unreadableBranchProjects} 个项目的分支数读不出来"
    } else if (d.branches < realBranches) {
        reachCaption += "（其余未纳入追踪）"
    }
    if (tagKnown) {
        reachCaption += " · ${tagCount} 个 tag"
    }

    return [
        DashKpi(DashKpiKind.Projects, "项目总数", d.listed, projectsCaption, None, false),
        DashKpi(DashKpiKind.Milestones, "里程碑完成率", pct, msCaption, progress, false),
        DashKpi(DashKpiKind.Attention, "待处理", attention, attentionCaption, None, attention > 0),
        DashKpi(DashKpiKind.Reach, "分支", realBranches, reachCaption, None, false)
    ]
}

/// 从 kpis 里取某个值。**页头必须走这里，不许自己再算一遍。**
public func kpiValueOf(kpis: Array<DashKpi>, kind: DashKpiKind): Int64 {
    for (k in kpis) {
        if (kindEquals(k.kind, kind)) {
            return k.value
        }
    }
    return 0
}

/// 仓颉枚举不实现 `==`，所以显式给一个。
public func kindEquals(a: DashKpiKind, b: DashKpiKind): Bool {
    match (a) {
        case Projects => return kindIsProjects(b)
        case Milestones => return kindIsMilestones(b)
        case Attention => return kindIsAttention(b)
        case Reach => return kindIsReach(b)
    }
}

public func kindIsProjects(k: DashKpiKind): Bool {
    match (k) {
        case Projects => true
        case _ => false
    }
}

public func kindIsMilestones(k: DashKpiKind): Bool {
    match (k) {
        case Milestones => true
        case _ => false
    }
}

public func kindIsAttention(k: DashKpiKind): Bool {
    match (k) {
        case Attention => true
        case _ => false
    }
}

public func kindIsReach(k: DashKpiKind): Bool {
    match (k) {
        case Reach => true
        case _ => false
    }
}

/// 页头那一行摘要。**从 kpis 读，不自己算**。
public func dashSummaryLine(kpis: Array<DashKpi>): String {
    let projects = kpiValueOf(kpis, DashKpiKind.Projects)
    let attention = kpiValueOf(kpis, DashKpiKind.Attention)
    if (attention <= 0) {
        return "共 ${projects} 个项目"
    }
    return "${projects} 个项目 · ${attention} 个项目待处理"
}
