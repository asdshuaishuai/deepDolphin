// Scope.swift — 顶栏双轨动作的**作用范围**。纯函数层，零 SwiftUI 依赖。
//
// 【关于设计稿那个范围选择器：本文件曾经判定「不要做」，那个论证是错的】
// 原论证：「侧栏导航已经承担了同一个角色（选中项目 = 主区显示它），再加一个下拉
// 就是『当前看的是谁』的两个来源」。
//
// 错在**把两个东西当成了同一个**：
//   · 侧栏回答的是「看哪个**视图**」（仪表盘 / 看板 / 里程碑 / 某个项目）
//   · 设计稿的下拉回答的是「看哪些**仓库**」（全局 / 单仓库）
// 这是两个正交的选择。砍掉下拉的实际后果是：用户在仪表盘上看完概览，
// 想进某个仓库只能退回侧栏重新找一次 —— 主链路断了一节。
//
// 【但「两个来源」这个担心是对的，所以纪律保留】
// 范围选择器**不持有自己的状态**：读 `model.selection`、写 `model.go(_:)`。
// 它是 selection 的一个**视图**，不是另一份真相。判据仍然钉着
// 「不许有独立的 scope 字段」—— 这条没变，变的只是「要不要给它一个界面」。
//
// 所以这里不给新状态，只把**已有的 selection 翻译成范围**（两个方向都要）。

import Foundation

/// 双轨动作打在谁身上。
enum UpdateScope: Hashable {
    case all
    case project(String)
}

/// 范围选择器的取值（设计稿「全局视图 / 单仓库」）。
///
/// ⚠️ 与 `UpdateScope` 是**两个不同的东西**，别合并：
///   · 这个管「主区现在显示谁」—— 界面导航
///   · 那个管「更新动作打在谁身上」—— 动作范围
/// 它们在「选中某个项目」时恰好相等，所以看起来能互相替代；
/// 但用户在**项目详情页里点「全部更新」**时二者必须不同。
enum ScopeChoice: Hashable {
    case group
    case project(String)

    /// 对应的路由。写入口只有一个：`AppModel.go(_:)`。
    var section: RootSection {
        switch self {
        case .group:             return .dashboard
        case .project(let name): return .project(name)
        }
    }
}

enum ScopeRules {
    /// 从主区当前选中推导范围。
    ///
    /// 只有「正在看某个项目详情」才收敛到那个项目；
    /// 其余（仪表盘 / 看板 / 里程碑 / 没有任何选中）都是全局 ——
    /// 把「在看某个项目」当成「只更新这个项目」会让用户以为漏掉了别的仓库。
    static func scope(for selection: RootSection?) -> UpdateScope {
        if case .project(let name)? = selection { return .project(name) }
        return .all
    }

    /// 范围的名字。「全部项目」而不是「全部」—— 引擎的 updateAll 确实只管注册表里那些。
    static func title(_ s: UpdateScope) -> String {
        switch s {
        case .all: return "全部项目"
        case .project(let n): return n
        }
    }

    /// 按钮标题。**必须带范围**：设计稿里同一个按钮会随范围改文案
    /// （「浅更新 (Shallow Sync All)」/「浅更新 (Shallow Sync)」），
    /// 不带的话用户按下之前无从知道会动谁。
    static func shallowLabel(_ s: UpdateScope) -> String {
        switch s {
        case .all: return "浅更新 · 全部"
        case .project(let n): return "浅更新 · \(n)"
        }
    }

    /// 深更新同理。
    static func deepLabel(_ s: UpdateScope) -> String {
        switch s {
        case .all: return "深更新 · 全部"
        case .project(let n): return "深更新 · \(n)"
        }
    }

    /// 深更新会动哪些托管文档 —— 设计稿把它印在按钮上（AGENT.md + README）。
    /// 这里给的是**真话**：客户端实际能深更新的文档以引擎为准，
    /// 引擎托管的是 README / AGENTS / CLAUDE，说「AGENT.md」是错的文件名。
    static let deepTouches = "README · AGENTS · CLAUDE"

    /// 范围内的待记录提交数（浅更新按钮上的徽章）。
    ///
    /// - `allTotal`: 全部项目的待记录之和
    /// - `byProject`: 项目名 → 该项目的待记录
    ///
    /// 分成两个入参而不是收 `[ProjectStatus]`：让这个文件零模型依赖，
    /// 判据能只编译它就验规则。
    ///
    /// ⚠️ 这个数字以前**恒为 0**：引擎的 status 读的是进度库里存的快照，
    ///    而那个快照在 update 算完后立刻被归零（`flow/update.cj:591`），
    ///    于是徽章永远不亮。已改成实时计算（`flow/status.cj`），
    ///    回归由引擎测试 `testStatusPendingCommitsIsLiveNotStoredSnapshot` 盯着。
    static func pending(_ s: UpdateScope, allTotal: Int, byProject: [String: Int]) -> Int {
        switch s {
        case .all: return allTotal
        case .project(let n): return byProject[n] ?? 0
        }
    }

    /// selection → 范围选择器的取值。
    /// 看板/里程碑是**全局视图**，选中它们时范围选择器显示「全局看板」——
    /// 因为设计稿那条下拉只分「全局 / 单仓库」，不承载「看哪个视图」。
    static func choice(for selection: RootSection?) -> ScopeChoice {
        switch selection {
        case .project(let name): return .project(name)
        case .dashboard, .board, .milestones, .none: return .group
        }
    }

    /// 这个范围内有东西在跑吗（用来禁用按钮）。
    static func isBusy(_ s: UpdateScope, busyAll: Bool, busyProject: String?) -> Bool {
        switch s {
        case .all: return busyAll
        case .project(let n): return busyProject == n
        }
    }
}
