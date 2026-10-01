// Route.swift — 启动参数 → 路由意图。**纯函数层，零 SwiftUI 依赖**。
//
// 放在这里而不是 DeepGitApp.swift，是因为它必须能被 ClientCheck 编译断言：
// 深链解析是纯字符串处理，没有理由只能靠「手动敲一次命令试试」来验证。
//
// 【修掉的缺陷】`--project foo` / `--section board` 单独使用会被**静默忽略**：
// 旧实现第一行是
//     guard args.contains("--open-panel") || args.contains("--open-settings") else { return }
// 而 `--open-panel` 才是那个 app 的正常启动路径（主面板是「启动自动打开」的），
// 于是**从命令行传深链**必须额外记住再加一个无关的 `--open-panel`，
// 少加了没有任何提示 —— 用户看到的是「深链没生效」。
// 复现：deepGit.app --project target ⇒ selection 停在默认的 .dashboard。
//
// 推广：深链参数**各自独立**生效，任何一个开关都不该被另一个无关开关挡住。

import Foundation

/// 主区当前显示什么。**路由的唯一载体**（原先散落在 9 处直接赋值）。
enum RootSection: Hashable {
    case dashboard
    case milestones
    case board
    case project(String)  // 项目名
}

/// 启动参数解析出的意图。**解析一次**，之后界面只读结果。
///
/// 用 struct 而不是 enum，是因为这些开关**可以并存**：
/// `--open-settings --project foo` 同时出现是合法的，
/// 用 enum 逼着写 `else if` 就一定会漏掉组合。
struct LaunchIntent: Equatable {
    /// 要去的地方。nil = 没指定，按默认视图。
    var route: RootSection?
    var openSettings = false
    var openPanel = false
    /// 无头 agent 自测用的问题。nil = 没要自测。
    var agentSelfTest: String?
}

enum Route {
    /// 把启动参数解析成意图。
    ///
    /// - `--project <名>`   → `.project(名)`
    /// - `--section <名>`   → `.dashboard` / `.board` / `.milestones`；
    ///                      认不出来的名字落 `.dashboard`（默认视图）而不是 nil ——
    ///                      落 nil 会让主区走 `case nil` 分支，行为等价但少了可追溯性。
    /// - `--open-settings` → 设置面板
    /// - `--open-panel`    → 打开主面板（**不再充当其它参数的前置条件**）
    /// - `--agent-selftest [问题]` → 无头 agent 自测
    ///
    /// 参数缺失值（如 `--project` 后面没有名字）当作没给这个参数，
    /// 不当作「项目名叫空串」—— 后者会让详情页去加载一个空名字的项目。
    static func parse(_ args: [String]) -> LaunchIntent {
        var intent = LaunchIntent()
        intent.openPanel = args.contains("--open-panel")
        intent.openSettings = args.contains("--open-settings")

        if let project = value(of: "--project", in: args) {
            intent.route = .project(project)
        } else if let raw = value(of: "--section", in: args) {
            // 必须写 `Route.section` 而不是裸 `section`：局部常量 `raw` 不遮蔽，
            // 但同名局部变量 `section` 会把静态方法遮掉，
            // 症状是「cannot call value of non-function type 'String'」——
            // 报错指向那一行，真正的原因在上一行的绑定名。
            intent.route = Route.section(raw)
        }

        // 问句可省（默认那句），但**必须有值** —— `--agent-selftest` 后面
        // 直接跟下一个 flag 时，那个 flag 不能被当成问句吃掉。
        if let i = args.firstIndex(of: "--agent-selftest") {
            let next = i + 1 < args.count ? args[i + 1] : nil
            if let q = next, !q.hasPrefix("--") {
                intent.agentSelfTest = q
            } else {
                intent.agentSelfTest = defaultSelfTestQuestion
            }
        }
        return intent
    }

    /// 没有问句时用的那句。与 `--agent-selftest` 的旧默认值保持一致，
    /// 写在这里是为了让「默认问句」也有判据可钉。
    static let defaultSelfTestQuestion = "总结一下项目群现状"

    /// `--section` 的取值 → 视图。认不出来落 dashboard。
    static func section(_ raw: String) -> RootSection {
        switch raw {
        case "milestones": return .milestones
        case "board": return .board
        case "dashboard": return .dashboard
        default: return .dashboard
        }
    }

    /// 取 `--flag` 后面那个值。**值本身是 flag 或不存在时返回 nil** ——
    /// 后者很重要：`--project --open-panel` 里的 `--open-panel` 是开关不是项目名，
    /// 当成项目名就会去加载一个叫「--open-panel」的项目，然后永远转圈。
    static func value(of flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        guard !v.isEmpty, !v.hasPrefix("--") else { return nil }
        return v
    }
}
