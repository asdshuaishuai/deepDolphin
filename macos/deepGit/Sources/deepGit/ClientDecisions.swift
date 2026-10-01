// ClientDecisions.swift — 客户端的状态判定（纯函数，无任何依赖）。
//
// 单独成文件、零依赖，是为了让 Tests/ClientCheck 能**直接编译本文件**来测它。
// 复制一份到测试里会漂移 —— 契约检查当初就是因为用了副本而失去意义。
// 不要往这里加 Foundation / SwiftUI / AppModel 依赖，那会让它没法单独编译。
//
// 收在这里的两个判定，共同点是：**内联在视图/生命周期代码里时测不到**，
// 而它们各自都对应一个已经咬过人的缺陷。
//   · 开机自启开关失败后不回滚（P1-10）—— 开关说谎
//   · 刷新进行中时把用户请求静默丢弃（P1-12）—— 点刷新像没反应

// MARK: - 开机自启：开关必须显示系统的真实状态

enum LoginItemOutcome {
    /// 请求的状态与系统实际状态不一致时的说明。
    ///
    /// 为什么不能只信「我们请求了什么」：`SMAppService.register()` 会抛错
    /// （沙箱策略、用户拒绝、app 未签名等），而原实现只 `NSLog` 一句，
    /// Toggle 仍停在用户点的那一侧 —— **开关在说它自己知道是假的话**。
    /// 真相只能来自系统：`SMAppService.mainApp.status`。
    static func mismatchNote(requested: Bool, actualEnabled: Bool) -> String? {
        guard requested != actualEnabled else { return nil }
        return requested
            ? "开机自启注册失败，系统实际仍是关闭的 —— 开关已回滚"
            : "开机自启注销失败，系统实际仍是开启的 —— 开关已回滚"
    }

    /// 该把开关显示成什么：**系统的实际状态**，不是用户的意图。
    static func displayedState(requested: Bool, actualEnabled: Bool) -> Bool {
        actualEnabled
    }
}

// MARK: - 刷新闸门：用户点的刷新不许被静默丢弃

/// 「正在刷新时又收到刷新请求」的状态机。
///
/// 原实现是 `refreshAll() { if isLoading { return } … }` ——
/// 一次手动刷新正好撞上定时刷新或另一次刷新，就被**静默丢掉**：
/// 按钮按下去有转圈（isLoading 已经是 true），转完却什么也没变，
/// 也没有任何提示。这正是「点刷新像没反应」的直接来源。
///
/// 正确做法是**合并**而不是丢弃：记下「还要再刷一次」，等当前这次跑完再补。
/// 反复请求不叠加成 N 次（跑 N 遍同样慢，还会让用户以为程序失控）。
struct RefreshGate {
    private(set) var isRunning = false
    private(set) var hasPending = false

    /// 收到一次刷新请求。返回 true 表示「这次真的可以开始跑」。
    mutating func request() -> Bool {
        if isRunning {
            // 已在跑：合并成一次待补，别排队 N 遍
            hasPending = true
            return false
        }
        isRunning = true
        return true
    }

    /// 当前这次跑完了。返回 true 表示「还有一次待补，需要马上接着跑」。
    mutating func finish() -> Bool {
        isRunning = false
        defer { hasPending = false }
        return hasPending
    }

    /// 供 UI 判断「转圈是不是因为还有排队的刷新」（避免转完却无事发生）
    var shouldShowPendingHint: Bool { isRunning && hasPending }
}
