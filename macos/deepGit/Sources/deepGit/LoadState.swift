// LoadState.swift — 一处数据源的加载四态 → 界面该画什么。纯函数层，零 SwiftUI 依赖。
//
// 【它修的是什么】
// `DashboardView` 原来是 `if let d = model.dashboard { … } else { ProgressView("汇总项目群…") }`，
// 于是仪表盘采集失败时**主区永远转圈**，既不报错也不停 ——
// 而错误横幅同时挂在 PanelView 顶部，用户看到的是「一条报错 + 一个永不停歇的加载中」。
// 里程碑页是同一族：读失败和「真的还没有里程碑」都渲染成
// 「里程碑绑定 git tag 后…」，于是「读不出来」被说成了「没有」。
//
// 【为什么不用 lastError 就够了】
// `lastError` 是**全局**的：git 操作失败、深链打错字、扫描失败都会写它。
// 拿它判断「仪表盘读不出来了吗」会把别的操作的错误算到仪表盘头上。
// 所以每个数据源得有自己的一份加载结果。

import Foundation

/// 一个数据源的加载结果。
enum LoadState: Equatable {
    case idle       // 还没开始
    case loading    // 在读
    case loaded     // 读成功了
    case failed(String)  // 读不出来，附带原因

    /// 界面该画哪一态。`hasContent` 由调用方给 —— 「空」的定义各数据源不同
    /// （里程碑是空数组，仪表盘是整个对象为 nil）。
    ///
    /// ⚠️ 必须是 `func` 不是 `var`：Swift 的**计算属性不带参数**，
    /// 带参数的只能是方法。写成 `var phase(hasContent: Bool)` 会报
    /// 「consecutive declarations on a line must be separated by ';'」——
    /// 那句报错完全指不到真正的位置，害我二分了好几轮才反应过来。
    func phase(hasContent: Bool) -> LoadPhase {
        switch self {
        case .idle, .loading: return .loading
        case .failed(let m): return .failed(m)
        case .loaded: return hasContent ? .content : .empty
        }
    }
}

/// 界面层要处理的五种局面。
enum LoadPhase: Equatable {
    case loading
    case empty
    case failed(String)
    case content
}

enum LoadRules {
    /// 存储降级时的判定。
    ///
    /// ⚠️ 「读到 0 条且 storeHealth 坏了」与「真的没有里程碑」是两件事：
    /// 前者是说这个空是**不可信的**，后者是说这个空是真的。
    /// 判错的后果是用户以为还没建里程碑，于是一直不去建。
    ///
    /// 读到 >0 条但 storeHealth 坏了 ⇒ 内容可信（只是有一部分读不出来），
    /// 按 loaded 处理，另外由调用方挂一条说明。
    static func state(storeHealth: String, readCount: Int) -> LoadState {
        if storeHealth == "ok" { return .loaded }
        return readCount > 0 ? .loaded : .failed(
            "里程碑存储降级（\(storeHealth)），读到 0 条 —— **这不是「还没有里程碑」**")
    }

    /// 降级但读到了一部分时的说明文字。loaded 状态下的附带披露。
    static func degradedNotice(storeHealth: String, readCount: Int) -> String? {
        guard storeHealth != "ok" else { return nil }
        return "milestones.json \(storeHealth)：读到 \(readCount) 条，另有部分读不出来"
    }
}
