// Router.swift — 「要不要真的跳过去」的**唯一**决策处。纯函数层，零 SwiftUI 依赖。
//
// 旧实现有两处对不上的地方：
//   1. `selection` 被 9 处直接赋值（PanelView / BarView / BoardView /
//      MilestonesView / DeepGitApp），没有任何一处解释「这么跳合不合理」，
//      于是**跳到一个不存在的项目**也照样跳。
//   2. 跳过去之后 `ProjectDetailView` 的 else 分支是
//      `ProgressView("加载 X …")`，而项目确实不存在时 `project` 永远是 nil
//      ⇒ 主区**永远转圈**，没有任何报错 —— 把「读不出来」说成「还在读」。
//
// ⚠️ 最容易写错的一条：**项目列表还没加载完时不能判「不存在」**。
// 启动瞬间 projects 是空的，此时任何深链都会被误判成「找不到」，
// 于是深链功能等于永远失效。所以要显式区分「不知道」与「确实没有」。

import Foundation

enum Router {
    /// 去不去，以及去不去的理由。
    enum Resolution: Equatable {
        /// 照原样去。
        case go(RootSection?)
        /// 项目列表已加载，里面确实没有这个项目。
        case projectNotFound(String)
        /// 项目列表**还没加载完** —— 现在还不知道，先去，详情页负责显示读不出来。
        case listNotLoaded
    }

    /// 唯一的路由决策。
    ///
    /// - Parameter loadedProjects: 已加载的项目名。**nil = 还没加载完**，
    ///   与「加载完了但是空的」是**两件事**（后者是真的一个项目都没有）。
    static func resolve(_ target: RootSection?, loadedProjects: [String]?) -> Resolution {
        guard case .project(let name)? = target else {
            // 非项目目标（三个固定视图 / nil）不需要项目列表就能跳。
            return .go(target)
        }
        guard let loaded = loadedProjects else {
            // 不知道 ≠ 没有。此刻判「不存在」会把深链整个废掉。
            return .listNotLoaded
        }
        return loaded.contains(name) ? .go(target) : .projectNotFound(name)
    }

    /// 「项目列表加载完了吗」——由调用方用**真实状态**回答，不用 `projects.isEmpty` 猜。
    ///
    /// 为什么不能靠数组空不空：刚注册的项目群真的可以是空的，
    /// 而「还没加载」也表现为空数组 —— 两者混起来，
    /// 空项目群的用户一启动深链就会被告知「找不到项目」。
    ///
    /// 收 `[String]` 而不是 `[ProjectStatus]`：让这个文件零模型依赖，
    /// ClientCheck 才能只编译它就断言路由规则（否则每加一个模型字段
    /// 都会把判据的编译清单拖下水）。
    static func loadedNames(_ names: [String], hasLoadedOnce: Bool) -> [String]? {
        hasLoadedOnce ? names : nil
    }
}
