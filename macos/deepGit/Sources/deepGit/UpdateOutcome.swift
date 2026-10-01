import Foundation

/// 一份文档在一次更新里的结果（**零依赖**，与 `DocChange` 的 Codable 解耦）。
struct DocOutcome: Equatable {
    let file: String
    let changed: Bool
    let created: Bool
    /// 本次写入前的备份**真实路径**；空串 = 确实没有备份
    /// （新建文件本来就没有旧版本 / 无变化 / dry-run），**不是**「不知道」。
    let backup: String

    /// 是不是「这次真的动了这个文件」。
    var touched: Bool { changed }
}

/// 一次更新之后，文档到底发生了什么。
///
/// 三种状态必须分开，合成一句话就会撒谎（缺陷 #211）：
///   · 引擎没报任何文档      —— 不是「文档都更新了」
///   · 报了但都没变          —— 不是「文档已刷新」
///   · 真的改了/新建了        —— 这才可以说「已更新」
struct UpdateOutcome: Equatable {
    let docs: [DocOutcome]
    /// 真的被改动的（含新建）。
    let touched: [DocOutcome]
    /// 本轮新建的（新建 ⇒ **没有备份**，别给它编一个）。
    let created: [DocOutcome]
    /// 改动过且留了备份的。
    let backedUp: [DocOutcome]

    var anythingTouched: Bool { !touched.isEmpty }
}

/// 更新结果的**唯一**判定点。**纯函数，零依赖**。
func updateOutcome(_ docs: [DocOutcome]) -> UpdateOutcome {
    UpdateOutcome(
        docs: docs,
        touched: docs.filter { $0.touched },
        created: docs.filter { $0.created },
        backedUp: docs.filter { $0.touched && !$0.backup.isEmpty }
    )
}

/// 通知栏那一行该说什么。**纯函数，零依赖**。
///
/// ⚠️ 缺陷 #211 实测：客户端原来把更新结果整个丢掉
/// （`_ = try await EngineCLI.shared.update(...)`），然后**无条件**弹一句
/// 「X 的文档托管区域已刷新」——
/// 而引擎在文档没变化时输出的是「README.md 无变化」。
/// **没做被说成做了**，与「失败被当成没有」是同一条轴的两个方向。
///
/// ⚠️ 三条硬规则：
///   · **没说改动就不能说「已刷新」**。引擎报了但没变，就老实说「没有变化」。
///   · **有备份就必须说备份在哪**。引擎每次改文档都留一份、按 `backupKeep` 裁剪，
///     用户不知道它存在 ⇒ 想要回滚时无从下手，而且旧版本会被静默删掉。
///     反过来也成立：**没有备份不许提备份**（新建文件本来就没有旧版本）。
///   · 列举文件有上限时必须说还剩几个（#205 那一族：每一层截断各自披露）。
func updateOutcomeSummary(
    _ o: UpdateOutcome,
    project: String,
    nameMax: Int = 2
) -> String {
    guard !o.docs.isEmpty else {
        // 引擎没报文档：可能是 --scope 限定，也可能这次没有托管目标。
        // 一律**不说**「已刷新」—— 那是拿一个未知当成功报出去。
        return "\(project)：本次没有需要更新的文档"
    }
    guard o.anythingTouched else {
        let names = o.docs.map { $0.file }
        return "\(project)：文档没有变化（\(names.joined(separator: "、"))）"
    }

    // 文件名一行最多列 nameMax 个，多的必须说清楚有几个没列
    let cap = max(1, nameMax)
    let listed = Array(o.touched.prefix(cap)).map { d in
        d.created ? "新建 \(d.file)" : "已更新 \(d.file)"
    }
    var s = "\(project)：" + listed.joined(separator: "、")
    if o.touched.count > listed.count {
        s += " 等 \(o.touched.count) 个文档"
    }
    // 备份路径只给第一个：通知栏一行放不下多条路径，
    // 而「备份存在」这个事实必须说，具体路径给一条就够用户去找。
    if let first = o.backedUp.first {
        s += "（\(first.file) 的旧版本已备份到 \(first.backup)）"
    }
    return s
}
