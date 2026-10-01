import Foundation

/// Provider 选择器最多列几家（**唯一来源**）。
///
/// `ModelCatalog.popularProviders` 原来写死 `limit: Int = 40`，
/// 而界面标题报的是目录**总**家数（实测 225）—— 两个数字都真实，
/// 但它们讲的是**不同的集合**，标题却让人以为「225 家里随便挑」。
let PROVIDER_PICKER_MAX = 40

/// Provider 选择器的可见范围披露。
struct ProviderPickerSlice: Equatable {
    /// 列表里实际列出的家数。
    let shown: Int
    /// 目录里**有可用端点**的家数（= 能被列出来的总集合）。
    let withEndpoint: Int
    /// 目录总家数（**包含没有端点的那些**）。
    let total: Int
    /// 列表被上限砍掉了。
    let cut: Bool
    /// 该补的一句话；nil = 没什么要说的。
    let note: String?
}

/// Provider 选择器完整度的**唯一**判定点。**纯函数，零依赖**。
///
/// - Parameters:
///   - total: 目录总家数（`ModelCatalog.providers.count`）
///   - withEndpoint: 其中有可用 api 端点的家数（`popularProviders` 的全集）
///   - limit: 列表最多列几家（默认 `PROVIDER_PICKER_MAX`）
///
/// ⚠️ 缺陷 #209 实测（真实快照 `Resources/models-dev.json`）：
/// 目录 225 家，其中 **199 家有可用端点**，而选择器只列前 **40 家** ——
/// **159 家有端点的 provider 用户根本选不到**（含 `minimax-cn-coding-plan`、28 个模型，
/// `alibaba-token-plan-cn` 28 个，`ai21`、`inference`、`databricks`、`wandb` …）。
/// 而 section 标题写的是「models.dev 目录 · 225 家」，零限定词。
/// 模型那一栏有过滤框，**provider 那一栏没有**。
///
/// 这与 #205（语言）/ #206（提交类型）/ #207（里程碑）是同一家族的第四次复发：
/// **一个声称完整的数字，配一个被砍过的列表，而没人说。**
///
/// ⚠️ 但这一处和前三次有个重要区别，别照抄结论：
/// 上限**本身是合理的** —— 目录在加载时按「有端点优先 + 模型数降序」排过序，
/// 实测第 40 家有 33 个模型、第 41 家 32 个，正好卡在自然断点上；
/// 被砍掉的 159 家里模型数最多的也就 32 个。
/// 所以要修的是**标签**（把两个不同的数字说成一个），
/// 不是取消上限，也不是把 185 家全塞进 Picker。
func providerPickerSlice(
    total: Int,
    withEndpoint: Int,
    limit: Int = PROVIDER_PICKER_MAX
) -> ProviderPickerSlice {
    let all = max(0, total)
    let usable = max(0, withEndpoint)
    // cap 传 0 会让列表一条都不列，而披露还会说「只列前 0 家」——
    // 与其产出自相矛盾的话，不如至少列一家。正常路径走不到（常量是 40）。
    let cap = max(1, limit)
    let shown = min(usable, cap)
    guard shown < usable else {
        return ProviderPickerSlice(shown: shown, withEndpoint: usable, total: all,
                                   cut: false, note: nil)
    }
    // 末尾必须给出**可执行的下一步**，不是一句「其余略」：
    // 设置页本来就有「Base URL 覆盖」输入框与「手动输入模型 id」，
    // 所以被砍掉的那几家**是能用的** —— 只是要从这里走过去。
    // 只说「还有 159 家」而不说怎么够到，等于把一个可用功能报成缺失。
    let note = "只列模型最多的前 \(shown) 家（共 \(usable) 家有可用端点"
        + (all > usable ? "，目录共 \(all) 家" : "")
        + "）；其余的可用下方「Base URL 覆盖」手填端点"
    return ProviderPickerSlice(shown: shown, withEndpoint: usable, total: all,
                               cut: true, note: note)
}
