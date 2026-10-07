import Foundation

/// 仪表盘里程碑卡片最多画几条（**唯一来源**）。
///
/// 引擎的 `milestones.items` 是**完整**的：`buildMilestoneOverview` 里
/// 没有任何条数上限，启用项目的每一条都会进数组，而 `counts.readCount`
/// 与各分桶之间还有一条对账等式（引擎侧 `accounted == readCount` 已断言）。
/// 所以「只画前 5 条」完全是界面自己干的，必须由界面自己说。
let MILESTONE_CARD_MAX = 5

/// 里程碑卡片的可见切片。
struct MilestoneCardSlice: Equatable {
    /// 卡片实际画出来的条数。
    let shown: Int
    /// 引擎一共给了几条。
    let total: Int
    /// 卡片自己砍掉了条数。
    let cut: Bool
    /// 卡片下方要补的一行说明；nil = 没什么要说的。
    let note: String?
}

/// 里程碑卡片切片的**唯一**判定点。**纯函数，零依赖**。
///
/// - Parameters:
///   - itemCount: 引擎给的 `milestones.items` 条数（完整列表，不是画出来的条数）
///   - cardMax: 卡片最多画几条（默认 `MILESTONE_CARD_MAX`）
///
/// ⚠️ 缺陷 #207 实测：1 个项目 8 条进行中里程碑，`dashboard --json` 给
/// `counts.open = 8` 且 `items` 8 条，而卡片标题按 counts 说话
/// （「进行中 8」）、列表只画 5 条 —— v6.0 / v7.0 / v8.0 静默消失，
/// 退出码 0，没有任何字段提示。
///
/// 这与 #205（语言）、#206（提交类型）是同一个家族第三次复发，形态完全一致：
/// **引擎给了完整数据 + 一个「这就是全量」的真话，消费方自己砍了一层却零披露。**
/// 三次的修法也必须是同一个形状 —— 判定抽成纯函数、披露写进界面、由 lint 守住接线。
func milestoneCardSlice(
    itemCount: Int,
    cardMax: Int = MILESTONE_CARD_MAX,
    en: Bool = false
) -> MilestoneCardSlice {
    let total = max(0, itemCount)
    guard total > 0 else {
        return MilestoneCardSlice(shown: 0, total: 0, cut: false, note: nil)
    }
    // cardMax 传 0 会让卡片一条都不画，而披露还会说「只显示前 0 条」——
    // 与其产出自相矛盾的话，不如至少画一条。正常路径走不到（常量是 5）。
    let cap = max(1, cardMax)
    let shown = min(total, cap)
    guard shown < total else {
        return MilestoneCardSlice(shown: shown, total: total, cut: false, note: nil)
    }
    return MilestoneCardSlice(
        shown: shown,
        total: total,
        cut: true,
        note: en ? "Showing the first \(shown) of \(total); see the Milestones page for the full list"
                 : "只显示前 \(shown) 条（共 \(total) 条），完整清单见「里程碑」页"
    )
}
