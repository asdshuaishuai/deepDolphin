// Scope.swift — 顶栏双轨动作的**作用范围**。纯函数层，零 SwiftUI 依赖。
//
// 【为什么没有另做一个「范围选择器」下拉】
// 设计稿顶栏左侧确实有一个范围选择器（🌐 全局视图 / 📦 项目[分支]），
// 但在客户端里**侧栏导航已经承担了同一个角色**：选中项目详情 = 主区显示它，
// 选中仪表盘/看板/里程碑 = 全局。照设计稿再加一个下拉，就是
// 「当前看的是谁」这件事的**两个来源** —— 用户在侧栏点了 B，下拉还写着 A。
//
// 所以这里不给新状态，只把**已有的 selection 翻译成范围**。
// 判据钉的正是这条：范围必须由 selection 推导，不许有独立的 scope 字段。

import Foundation

/// 双轨动作打在谁身上。
enum UpdateScope: Hashable {
    case all
    case project(String)
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

    /// 这个范围内有东西在跑吗（用来禁用按钮）。
    static func isBusy(_ s: UpdateScope, busyAll: Bool, busyProject: String?) -> Bool {
        switch s {
        case .all: return busyAll
        case .project(let n): return busyProject == n
        }
    }
}
