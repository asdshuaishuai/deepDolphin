// 仪表盘的筛选口径 —— 与 macOS 端 `DashboardScope.swift` 的 `DashSpan` /
// `DashCommitFilter` / `DashFilter` 逐条对应。
//
// 【为什么单独抽出来】
// 筛选控件最常见的失败不是「不好看」，而是**摆在那里不起作用** ——
// 用户拨了「近 7 天」而卡片数字纹丝不动，于是整个筛选行被当成装饰。
// 判定放在视图里就只能靠肉眼发现，所以抽成纯函数，由判据直接断言：
// 「每个枚举都配一个『过滤后是什么』，而不是只有一个名字」。
package deepdolphin_linux

import std.collection.*

// ===========================================================================
// 时间跨度
// ===========================================================================

/// 设计稿是「全量历史 / 近 30 天 / 近 7 天」。
///
/// ⚠ **我们能过滤的到底是什么**：引擎只给「最后更新距今多少天」
/// （`daysSinceLastCommit`）与两个**聚合**活跃数（active7d / active30d），
/// **没有**逐项目的提交时间序列。所以这里的「时间跨度」= 按最近更新天数分档，
/// 而不是「只统计这段时间内的提交」—— 后者需要的数据引擎没有。
/// 界面上必须照实写「最近更新」，不能写「近 7 天的提交」。
public enum DashSpan {
    | All
    | D30
    | D7
}

public func spanLabel(s: DashSpan): String {
    match (s) {
        case DashSpan.All => return "全量"
        case DashSpan.D30 => return "近 30 天"
        case DashSpan.D7 => return "近 7 天"
    }
}

/// 该档位的时间窗（天）。`None` = 不按时间筛。
///
/// ⚠ 这里**只有数字，没有判定**。判定委托给 `daysSinceLastCommit` ——
/// 引擎已经有 3/14/30 天档位线，客户端再写一套阈值就成了两个真相源。
public func spanMaxDays(s: DashSpan): Option<Int64> {
    match (s) {
        case DashSpan.All => return None
        case DashSpan.D30 => return Some(30)
        case DashSpan.D7 => return Some(7)
    }
}

/// 点一下切到下一档（全量 → 30 天 → 7 天 → 全量）。
public func spanNext(s: DashSpan): DashSpan {
    match (s) {
        case DashSpan.All => return DashSpan.D30
        case DashSpan.D30 => return DashSpan.D7
        case DashSpan.D7 => return DashSpan.All
    }
}

public func spanIs(s: DashSpan, other: DashSpan): Bool {
    match ((s, other)) {
        case (DashSpan.All, DashSpan.All) => return true
        case (DashSpan.D30, DashSpan.D30) => return true
        case (DashSpan.D7, DashSpan.D7) => return true
        case _ => return false
    }
}

/// 档位必须**从宽到严**递增 —— 否则「近 7 天」比「全量」还宽就是反的。
public func spanIsStricterThanAll(s: DashSpan): Bool {
    return spanMaxDays(s).isSome()
}

// ===========================================================================
// 提交类型
// ===========================================================================

/// ⚠ **这个筛选只作用于提交结构条**：决定堆叠条画哪几段、图例列哪几行。
/// 它**不改** KPI 数字 —— `commitTypes` 是引擎给的**最近 N 条样本**
/// （`commitTypesTruncated` 恒发），拿样本去重算「全局提交总数」
/// 是拿小样本充总量。这条边界写在判定上，不靠注释。
public enum DashCommitFilter {
    | AllCommits
    | Only(String)
}

public func commitFilterLabel(f: DashCommitFilter): String {
    match (f) {
        case DashCommitFilter.AllCommits => return "所有提交类型"
        case DashCommitFilter.Only(t) => return t
    }
}

public func commitAllowed(f: DashCommitFilter, t: String): Bool {
    match (f) {
        case DashCommitFilter.AllCommits => return true
        case DashCommitFilter.Only(want) => return want == t
    }
}

public func commitFilterIsAll(f: DashCommitFilter): Bool {
    match (f) {
        case DashCommitFilter.AllCommits => true
        case DashCommitFilter.Only(_) => false
    }
}

public func commitFilterEquals(a: DashCommitFilter, b: DashCommitFilter): Bool {
    match ((a, b)) {
        case (DashCommitFilter.AllCommits, DashCommitFilter.AllCommits) => return true
        case (DashCommitFilter.Only(x), DashCommitFilter.Only(y)) => return x == y
        case _ => return false
    }
}

// ===========================================================================
// 组合筛选
// ===========================================================================

/// 一份筛选 = 时间跨度 + 提交类型。纯数据、可单测；
/// 视图只负责把控件的值塞进来、把结果画出去。
public class DashFilter {
    public let span: DashSpan
    public let commits: DashCommitFilter

    public init(span: DashSpan, commits: DashCommitFilter) {
        this.span = span
        this.commits = commits
    }

    public static func none(): DashFilter {
        return DashFilter(DashSpan.All, DashCommitFilter.AllCommits)
    }
}

/// 项目是否落在范围内。
///
/// ⚠ **读不出更新时间的项目一律保留**：它的真实状态是「不知道」，
/// 不是「不在范围内」。筛掉它等于把「我们没读到」说成「这项目很久没动了」——
/// 而这正是本项目最高发的那族缺陷（把「不知道」说成「没有」）。
public func keepsProject(f: DashFilter, p: Project, nowMs: Int64): Bool {
    match (spanMaxDays(f.span)) {
        case None => return true
        case Some(maxDays) =>
            match (daysSinceLastCommit(p, nowMs)) {
                case Some(age) => return age <= maxDays
                case None => return true
            }
    }
}

/// 堆叠条 / 图例要画的提交类型。**只影响结构条，不影响 KPI。**
public func keptCommitTypes(f: DashFilter, p: Project): ArrayList<(String, Int64)> {
    let out = ArrayList<(String, Int64)>()
    for (t in p.commitTypes) {
        if (commitAllowed(f.commits, t[0])) {
            out.add(t)
        }
    }
    return out
}

/// 明细标题那一行。**必须说清画了几个 / 一共几个** ——
/// 标题写「（12）」而下面画 3 张卡，正是本项目栽过多次的那族缺陷。
public func gridCountLine(shown: Int64, total: Int64, f: DashFilter): String {
    if (shown == total) {
        return "共 ${total} 个项目"
    }
    return "${shown}/${total} 个项目（最近更新在 ${spanLabel(f.span)}）"
}

// ===========================================================================
// 提交类型并集（筛选行的选项来源）
// ===========================================================================

/// 筛选行里的一个提交类型选项。`index` 是**降序后的名次** ——
/// 色板按名次取色（第 1 名 = 蓝），所以名次变了颜色就跟着变，
/// 这是有意的：堆叠条与图例必须用同一个名次，否则两张卡对照会误读。
public class CommitKind {
    public let index: Int64
    public let name: String
    public let total: Int64

    public init(index: Int64, name: String, total: Int64) {
        this.index = index
        this.name = name
        this.total = total
    }
}

/// 逐项目求提交类型的并集，按**累计条数降序**。
///
/// ⚠ 选项必须来自引擎真给的数据，不能写死一份列表：
/// 写死的话引擎新增一个类型时这个控件就落下一项，
/// 而用户会以为「这个类型不存在」。
public func allCommitTypes(projects: ArrayList<Project>): ArrayList<CommitKind> {
    let names = ArrayList<String>()
    let counts = ArrayList<Int64>()
    for (p in projects) {
        for (t in p.commitTypes) {
            var hit: Int64 = -1
            var i: Int64 = 0
            while (i < names.size) {
                if (names[Int64(i)] == t[0]) {
                    hit = i
                    break
                }
                i += 1
            }
            if (hit < 0) {
                names.add(t[0])
                counts.add(t[1])
            } else {
                counts[Int64(hit)] = counts[Int64(hit)] + t[1]
            }
        }
    }
    // 按累计条数**降序**排：第 1 名 = 最多的那个 = 蓝（色板首位）。
    // 选「最多的」当第 1 名不是审美，是信息量 —— 一眼能看见主体。
    // 冒泡实现，项数个位数。
    var n = names.size
    while (n > 1) {
        n -= 1
        var i: Int64 = 0
        while (i < n) {
            if (counts[Int64(i)] < counts[i + 1]) {
                let tn = names[Int64(i)]
                names[Int64(i)] = names[i + 1]
                names[i + 1] = tn
                let tc = counts[Int64(i)]
                counts[Int64(i)] = counts[i + 1]
                counts[i + 1] = tc
            }
            i += 1
        }
    }
    // 名次 = 降序后的下标
    let out = ArrayList<CommitKind>()
    var k: Int64 = 0
    while (k < names.size) {
        out.add(CommitKind(k, names[Int64(k)], counts[Int64(k)]))
        k += 1
    }
    return out
}

/// 筛选后的提交类型 → `DsPart`。
///
/// ⚠ `slot` 取**该项目内的顺序**，与 `detail.cj` 的 `commitTypeParts` 同源，
/// 也与 macOS 端 `d.languages.prefix(...).enumerated()` 的做法一致。
///
/// 曾经试过用「全局累计名次」取色（跨项目统一 feat=第几名），
/// 那样 `slot` 与**位置**就脱节了：名次第 1 的段排在第 2 位，
/// 而堆叠条的段顺序、图例的行顺序、颜色号必须三者自洽，
/// 否则读者在堆叠条里看到第 1 段是紫色、在图例里第 1 行却是蓝色。
/// 筛选器该改变的是「看得见多少」，不该改变数据的身份。
public func keptCommitParts(f: DashFilter, p: Project): Array<DsPart> {
    let kept = keptCommitTypes(f, p)
    let out = ArrayList<DsPart>()
    var slot: Int64 = 0
    for (t in kept) {
        out.add(DsPart(t[0], t[1], slot: slot))
        slot += 1
    }
    return out.toArray()
}

/// 按筛选留下项目。判定逐条走 `keepsProject`（读不出更新时间的保留）。
public func filteredProjects(
    f: DashFilter,
    projects: ArrayList<Project>,
    nowMs: Int64
): ArrayList<Project> {
    let out = ArrayList<Project>()
    for (p in projects) {
        if (keepsProject(f, p, nowMs)) {
            out.add(p)
        }
    }
    return out
}
