import Foundation

/// 脉冲行里最多列几种提交类型（**唯一来源**）。
///
/// 引擎的 `commitTypes` 是**完整**的（它不砍条数，只砍采样窗口），
/// 所以「只列前 5 种」这件事完全是界面自己干的，必须由界面自己说。
/// 原来写成 `types.prefix(5)` 内联在 `ProjectStatus` 的计算属性里，
/// 而那里唯一的披露 `commitTypesTruncated` 说的是**另一条轴**（引擎的采样窗口）
/// —— 两轴混用，于是引擎数据越完整，界面藏得越狠且越沉默。
let COMMIT_TYPE_LINE_MAX = 5

/// 提交构成卡片的颜色表（**唯一来源**）。
///
/// 容量必须 ≥ 引擎 `COMMIT_TYPE_ORDER` 的长度（实测 12）。
/// 引擎把旧分类法遗留的类型也报出来，但它们全部聚进 `other` 桶，
/// 所以 `commitTypes` 的**条数**上界 = `COMMIT_TYPE_ORDER` 的长度，与采样窗口无关。
///
/// ⚠️ 色板比这个上界短的后果不是「不好看」，是**把两类画成了一类**：
/// `palette[i % palette.count]` 会让第 13 类拿到第 1 类的颜色，
/// 分段条上两段糊在一起、图例里两行同色圆点，读者无从分辨。
/// 所以容量不是「取模就好」，而是由 `commitTypeCardSlice` 变成一条
/// **带披露的真实上限**（见下）。
enum CommitTypeColor: String, CaseIterable {
    case blue, red, orange, purple, teal, indigo, mint, pink, brown, yellow, cyan, gray

    /// 取色顺序。**只有这一处**决定第 i 类拿到什么颜色。
    /// 视图按 `CommitTypeColor.palette` 取，不再自带一份颜色字面量。
    static let palette: [CommitTypeColor] = [
        .blue, .red, .orange, .purple, .teal, .indigo,
        .mint, .pink, .brown, .yellow, .cyan, .gray,
    ]

    /// 色板容量。契约检查拿它与**真实引擎**输出的条数比对，
    /// 引擎的类型词表一旦变长，这里必须跟着加颜色 —— 否则检查会红。
    static var capacity: Int { palette.count }
}

/// 提交构成的一行摘要 + 它的完整度。
struct CommitTypeComposition: Equatable {
    /// 画在脉冲行里的那句话；nil 表示压根没有提交类型可列。
    let line: String?
    /// 这一行实际列了几种（`entries` 的条数，不是引擎给的条数）。
    let shown: Int
    /// 引擎一共给了几种。
    let total: Int
    /// **界面自己**砍掉了条数（与引擎的 `commitTypesTruncated` 是两条独立的轴）。
    let topCut: Bool
}

/// 提交构成卡片的可见切片。
///
/// `capacity` 来自 `CommitTypeColor.capacity`：色板画不完的条数**说出来**，
/// 而不是靠取模把两段涂成同一个颜色（缺陷 #206）。
///
/// ⚠️ 不声明 `Equatable`：`entries` 是元组数组，而元组不参与 `==` 合成。
/// （声明了会直接编译失败 —— 这比让检查去比两个切片更早暴露问题。）
struct CommitTypeCardSlice {
    let entries: [(type: String, count: Int)]
    /// 引擎一共给了几种（`entries` 可能比它少）。
    let total: Int
    /// 有类型因为色板容量被挡在了卡片外。
    let cut: Bool
    /// 给卡片补的一行说明；nil = 没什么要说的。
    let note: String?
}

/// 提交构成摘要的**唯一**判定点。**纯函数，零依赖**。
///
/// - Parameters:
///   - entries: 引擎给的 `(类型, 条数)`，**完整**列表（不预先截断）
///   - sampleTruncated: 引擎的 `commitTypesTruncated`（采样窗口 < 提交总数）
///   - totalCommits: 引擎的 `commitCount`（真实提交总数；-1 = 读不出来）
///   - lineMax: 这一行最多列几种（默认 `COMMIT_TYPE_LINE_MAX`）
///
/// ⚠️ 两条截断轴彼此独立，**少一条就撒谎**：
///   · `sampleTruncated` —— 引擎的**采样窗口**（近 15 条 vs 全仓 23 条）
///   · `topCut`          —— **界面自己**只列前 N 种（共 12 种只列 5 种）
/// 缺陷 #206 实测：14 个提交 14 种类型的仓库，引擎给 12 条且
/// `commitTypesTruncated=false`（=「这就是全量」），界面只列 5 条、
/// 披露一个字都没有 —— 读出来是「这个项目就是 feat/fix/perf/refactor/docs 五种类型」。
func commitTypeComposition(
    entries: [(type: String, count: Int)],
    sampleTruncated: Bool,
    totalCommits: Int = 0,
    lineMax: Int = COMMIT_TYPE_LINE_MAX
) -> CommitTypeComposition {
    let total = entries.count
    guard total > 0 else {
        return CommitTypeComposition(line: nil, shown: 0, total: 0, topCut: false)
    }
    // lineMax 传 0 会让这一行一个字类型都不列，而披露还会说「只列前 0 种」——
    // 与其产出这种自相矛盾的话，不如至少列一种。正常路径走不到（常量是 5）。
    let cap = max(1, lineMax)
    let shown = min(total, cap)
    let body = entries.prefix(cap).map { "\($0.type) ×\($0.count)" }.joined(separator: " · ")

    var notes: [String] = []
    if sampleTruncated {
        // 分母必须写出来：「已截断」而不说「近几条/共几条」，
        // 读者只能把样本当全量（引擎 report/agent 那边已经这么写了）。
        let sampled = entries.reduce(0) { $0 + $1.count }
        notes.append(totalCommits > 0 ? "近 \(sampled)/\(totalCommits) 条样本" : "样本，非全量")
    }
    if shown < total {
        notes.append("本行只列前 \(shown) 种，共 \(total) 种，完整构成见「提交构成」卡片")
    }

    return CommitTypeComposition(
        line: notes.isEmpty ? body : "\(body)（\(notes.joined(separator: "；"))）",
        shown: shown,
        total: total,
        topCut: shown < total
    )
}

/// 提交构成卡片的切片。**纯函数，零依赖**。
///
/// 引擎的条数上界目前恰好等于色板容量（12），所以 `cut` 实际是 false；
/// 它的价值在于**词表变长时**（引擎加第 13 种类型）表现成一句披露，
/// 而不是两段同色的分段条。
func commitTypeCardSlice(
    entries: [(type: String, count: Int)],
    capacity: Int = CommitTypeColor.capacity
) -> CommitTypeCardSlice {
    let total = entries.count
    guard capacity > 0, total > capacity else {
        return CommitTypeCardSlice(entries: entries, total: total, cut: false, note: nil)
    }
    return CommitTypeCardSlice(
        entries: Array(entries.prefix(capacity)),
        total: total,
        cut: true,
        note: "色板最多区分 \(capacity) 种类型，还有 \(total - capacity) 种没显示"
    )
}
