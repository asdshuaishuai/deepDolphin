// StopDecision.swift — 「这次更新能不能被停 / 停掉后该怎么说」的判定。
//
// 抽出来的原因：这两个判定内联在 AppModel 里时，运行时抓不到，
// 而它们恰好是"看起来实现了、其实没生效"的高发区 ——
// 上一版就是"停止"按钮接了个只取消 Swift Task 的假实现，
// 而 run 是同步阻塞 + Task.detached，取消根本传不到引擎进程。
import Foundation

enum StopDecision {

    /// 「停止」按钮的可用性。
    ///
    /// 三个条件缺一不可：
    ///   · 有东西在跑      —— 否则是死按钮（点了没有任何反馈）
    ///   · 还没在停        —— 否则可以连点
    ///   · 不是引擎自己超时 —— 超时之后没有"在跑的进程"可停
    static func canStop(isBusyAll: Bool,
                        busyProject: String?,
                        isStopping: Bool) -> Bool {
        guard !isStopping else { return false }
        return isBusyAll || busyProject != nil
    }

    /// 「开始批量更新」按钮的可用性。
    ///
    /// ⚠️ 这条对应一个真实缺陷：DeepGitApp 的「全部浅更新」菜单项原来
    /// **没有任何 .disabled**，而 `updateAll` 开头是
    /// `guard !busyAll else { return false }` ——
    /// 于是更新跑着的时候（引擎侧超时 900 秒）点它，
    /// 结果是**点了什么都没发生，也没有任何提示**。
    /// 同一族的还有 P1-12 那个被静默丢弃的刷新请求。
    static func canStartUpdateAll(isBusyAll: Bool) -> Bool { !isBusyAll }

    /// 停止之后该显示什么。
    ///
    /// 三态，因为「没找到进程可杀」是一个**真实的第三种情况**：
    /// 用户按了停止，但那一刻引擎刚好自己跑完了。
    /// 把它报成「已停止」是撒谎（其实早就结束了），
    /// 报成「失败」也是撒谎（用户没做错任何事）。
    enum Outcome: Equatable {
        case stopped(killed: Int)
        case alreadyFinished
        case cancelled            // 被取消而非被杀掉
    }
    static func outcome(killed: Int, taskWasCancelled: Bool) -> Outcome {
        if killed > 0 { return .stopped(killed: killed) }
        if taskWasCancelled { return .cancelled }
        return .alreadyFinished
    }

    /// 该给用户看的话。**每种都要说实话**，
    /// 不许把「早结束了」说成「已停止」——
    /// 用户会以为那一整轮的结果是可信的。
    static func message(_ o: Outcome, itemCount: Int) -> String {
        switch o {
        case .stopped(let killed):
            return killed == 1 ? "已停止 1 个正在进行的更新" : "已停止 \(killed) 个正在进行的更新"
        case .alreadyFinished:
            return "停止时更新已经跑完了（\(itemCount) 个项目）"
        case .cancelled:
            return "已取消等待（更新可能仍在后台收尾）"
        }
    }

    /// 该不该**警告**用户。
    ///
    /// 被停掉**不是失败** —— 报「更新失败」会让人以为刚跑了一半的更新坏了，
    /// 于是去手动改文档、去查仓库，白折腾一场。
    /// 「停止时已经跑完了」更不是失败，那本来就是成功。
    ///
    /// 唯一值得警告的是 `.cancelled`：Swift 侧取消了等待，但**引擎进程还活着**
    /// —— 它可能还在写进度库，而界面已经不认这次操作了。
    /// 这时必须说，否则用户以为停了、其实没停。
    static func shouldWarn(_ o: Outcome) -> Bool {
        if case .cancelled = o { return true }
        return false
    }
}
