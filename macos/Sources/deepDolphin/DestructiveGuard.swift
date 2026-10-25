// DestructiveGuard.swift — 破坏性操作的确认判据（纯函数层，零 SwiftUI 依赖）。
//
// 【为什么要有这个】规范 §3.2 写「破坏性操作确认：删除里程碑、放弃里程碑、
// 提交全部改动、批量更新——全部加 confirmationDialog（当前全库 0 个）」。
// 核实后确认这是真缺口，且引擎侧坐实了它有后果：
//   · `removeMilestone`（kernel/milestones.cj:249）直接从列表里剔除并 saveMilestones
//     —— **没有备份、没有回收站**，不可逆。
//   · `setMilestoneStatus(…, "drop")` 把里程碑标成已放弃，同样没有反悔余地
//     （虽然有「重开」，但用户得先知道自己误点了）。
//   · 批量更新要动用户仓库里的 README/AGENTS.md。
//
// 【为什么判定要抽成纯函数】直接在三处各写一个 if 就会出现第 N 遍漂移，
// 而「漏了哪一处」没人知道（这仓库在「同一份约定抄多处」上已经栽到第 8 例）。
// 这里是唯一来源：视图只问 `DestructiveGuard.needsConfirmation(for:)`。
import Foundation

/// 会改用户数据、且出错代价不对称的动作。
enum DestructiveAction: Equatable {
    /// 删除里程碑 —— 引擎直接剔除，无备份，不可逆
    case removeMilestone
    /// 放弃里程碑 —— 标成 dropped，语义上是「不做了」
    case dropMilestone
    /// 达成 / 重开 —— 状态可再改，**不**需要确认
    case setMilestoneStatus
    /// 批量更新：会把托管区域写进用户的 README/AGENTS.md
    case bulkUpdate
    // ⚠️ 2026-10-25 删掉了 `commitAll`：提交已弹窗化（CommitSheetView）——
    // 用户逐文件勾选 + 填信息本身就是确认层，「提交全部改动」的一次性
    // 确认动作没有调用方了。死枚举留在确认判据里等于宣称一条不存在的路。

    /// 引擎侧的动作字符串（`milestoneAction` 的 action 参数）。
    var engineAction: String {
        switch self {
        case .removeMilestone:  return "remove"
        case .dropMilestone:    return "drop"
        case .setMilestoneStatus: return "set"
        case .bulkUpdate:       return "update-all"
        }
    }
}

/// 确认判据 + 文案的唯一来源。
enum DestructiveGuard {
    /// 需要确认的动作集合。
    ///
    /// ⚠️ `setMilestoneStatus` **故意不在内**：达成/重开都是可逆的状态切换，
    /// 弹确认只会把「确认疲劳」教会用户（点了太多次之后就不看了）——
    /// 那比不确认更糟，因为真正的破坏性操作也会被一起忽略。
    /// 这条边界不要为了「看起来一致」而扩大。
    static func needsConfirmation(for action: DestructiveAction) -> Bool {
        switch action {
        case .removeMilestone, .dropMilestone, .bulkUpdate:
            return true
        case .setMilestoneStatus:
            return false
        }
    }

    /// 确认框标题。必须点名**具体对象**，不能只说「确认吗」——
    /// 用户要知道自己确认的是哪一个。
    static func title(for action: DestructiveAction, subject: String) -> String {
        switch action {
        case .removeMilestone:  return "删除里程碑「\(subject)」？"
        case .dropMilestone:    return "放弃里程碑「\(subject)」？"
        case .bulkUpdate:       return "更新全部项目？"
        case .setMilestoneStatus: return "确认操作？"
        }
    }

    /// 确认框正文：**必须说清代价**。
    /// 「删除」而不说「不可恢复」，等于让用户以为还能撤销。
    static func message(for action: DestructiveAction, subject: String) -> String {
        switch action {
        case .removeMilestone:
            return "「\(subject)」会被直接删除。引擎不留备份、也没有回收站，删除后无法恢复。"
        case .dropMilestone:
            return "「\(subject)」会被标记为已放弃，日后不再计入进行中的里程碑。之后可以重开，但这次操作本身不会被记录成历史。"
        case .bulkUpdate:
            return "所有已注册项目的 README / AGENTS.md 等托管区域都会被改写。每个文件在改写前会留备份，但这一步会覆盖多个仓库。"
        case .setMilestoneStatus:
            return "这个操作可以再改回来。"
        }
    }

    /// 确认按钮的标题。破坏性动作的按钮要说**会发生什么**，不是「确定」。
    /// 「确定 / 取消」的一对按钮里，「确定」可能是「确定删掉」也可能是「确定保存」——
    /// 挨着放的时候用户得靠位置猜。
    static func confirmTitle(for action: DestructiveAction) -> String {
        switch action {
        case .removeMilestone:  return "删除"
        case .dropMilestone:    return "放弃"
        case .bulkUpdate:       return "全部更新"
        case .setMilestoneStatus: return "确定"
        }
    }

    /// 主体（里程碑名 / 项目名）在确认文案里的安全写法。
    /// 空名字会让确认框变成「删除里程碑「」？」——用户不知道自己在删什么。
    static func safeSubject(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "未命名" : t
    }

    /// 该不该用 `.destructive` 角色（确认按钮染红）。
    /// 可逆的动作不染红：满屏红按钮会稀释「红=危险」这个信号。
    static func isDestructiveRole(for action: DestructiveAction) -> Bool {
        switch action {
        case .removeMilestone, .dropMilestone:
            return true
        case .bulkUpdate, .setMilestoneStatus:
            return false
        }
    }

    /// 批量更新的范围描述。
    ///
    /// ⚠️ 批量更新**不该**和「删除里程碑」用同一种确认：
    /// 它虽然会改写多个仓库的托管区域，但每个文件在改写前都会留备份
    /// （引擎 `applyRegions`，不变量 62），是可逆的。
    /// 弹一个红字的「你确定要删东西吗」式对话框，会把真正的不可逆操作也稀释掉。
    /// 所以这里只**报范围**（几个项目、哪一轨），让人知道这次会动多少东西。
    static func bulkUpdateMessage(projectCount: Int, track: DSSyncTrack) -> String {
        let n = max(projectCount, 0)
        if n == 0 { return "当前没有已注册的项目，不会做任何事。" }
        let one = n == 1 ? "1 个项目" : "\(n) 个项目"
        let what = track == .shallow
            ? "读取 git 历史并改写托管区域（README / AGENTS.md 等）"
            : "除浅更新外还会调用 AI 重新生成内容"
        return "将对 \(one) 执行\(track.label)：\(what)。每个被改写的文件都会先留备份，所以可以回滚。"
    }
}
