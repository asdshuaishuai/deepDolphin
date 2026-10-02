// deepDolphin Linux 客户端 —— 应用状态。
//
// 全部界面状态集中在这里，且**只有这里**能改。
// 引擎调用在后台线程跑，结果通过 `DesktopApp.post` 回到 UI 线程再写状态 ——
// UI 线程上 `Future.get()` 会同时冻结输入与绘制，窗口会「卡死」，
// 而 `status --json` 在大项目群上要跑好几秒。
package deepdolphin_linux

import std.collection.*

import cui.{DesktopApp, State}

/// 引擎调用超时。给得比 macOS 端宽松：这个客户端跑在开发机/家用机上，
/// 外置卷上的仓库可能很慢，而**宁可等也不要给半截数据**。
private const ENGINE_TIMEOUT_MS: Int64 = 60000

public class AppModel {
    /// `status --json` 的快照。`None` = 还没成功读到过一次。
    public let snapshot = State<Option<StatusSnapshot>>(None)
    /// `dashboard --json` 的聚合。取不到时仪表盘显示「暂无聚合数据」，
    /// **但 status 的内容照常显示** —— 两份数据互不连坐。
    public let dashboard = State<Option<Dashboard>>(None)

    /// 侧栏选中下标。引擎返回的项目顺序稳定（注册表顺序），
    /// 所以下标在刷新之间是有意义的身份。
    public let selected = State<Int64>(0)

    /// 正在读引擎。**连点两次「刷新」时它就是闸门**：
    /// 第二次点击直接被挡掉，而不是并发起两次引擎调用。
    /// 闸门只挡「重复发起」，不排队 —— 排队会让用户以为有 3 次要做。
    public let busy = State<Bool>(false)

    /// 引擎级问题（找不到 / 契约过旧 / 调用失败）。空串 = 没有。
    public let problem = State<String>("")
    /// 引擎契约过旧：载荷能解析，但缺本客户端依赖的披露字段。
    public let staleContract = State<Bool>(false)
    /// 状态条那一行的话。
    public let statusText = State<String>("")
    /// 空态提示。
    public let emptyHint = State<String>("")
    /// 页头那行「引擎来源 · 路径」。
    public let engineLabel = State<String>("")
    /// 能不能点刷新（引擎没找到时置 false，但空态照样把话说清楚）。
    public let canRefresh = State<Bool>(false)

    /// 启动读取只发一次。由 main 的构建闭包置位。
    public var booted: Bool = false

    public let enginePath: String
    public let engineVia: String
    private let engineProblem: String

    public init(loc: EngineLocation) {
        this.enginePath = loc.path
        this.engineVia = loc.via
        this.engineProblem = loc.problem
        this.syncLabels()
    }

    /// 侧栏每一行的文字。
    ///
    /// 失败项目显示**引擎给的原因**而不是名字 —— 名字在左边已经有一列，
    /// 这里再重复一次就浪费了本该放原因的那一行。
    public func projectLabels(): Array<String> {
        match (this.snapshot.value) {
            case Some(s) =>
                let out = ArrayList<String>()
                for (p in s.projects) {
                    out.add(if (p.failed()) { p.error } else { p.sidebarLine() })
                }
                return out.toArray()
            case None => return Array<String>()
        }
    }

    /// 刷新所有由引擎状态派生的文案。
    ///
    /// 单独抽出来，是因为这些文案有**优先级**：引擎找不到 > 契约过旧 >
    /// 部分失败 > 一切正常。把它们揉成一句「加载失败」，
    /// 用户就得自己猜是哪一种，而三种的处置完全不同。
    private func syncLabels(): Unit {
        if (!this.engineProblem.isEmpty()) {
            this.problem.value = this.engineProblem
            this.emptyHint.value = this.engineProblem
            this.statusText.value = this.engineProblem
            // 引擎都没找到，「刷新」按下去什么也不会发生 ——
            // 按钮这时是禁用的，用户该做的是照着上面那句提示去装引擎。
            this.canRefresh.value = false
            return
        }

        this.emptyHint.value = "点右上角「刷新」读取项目群。"
        this.canRefresh.value = true
        this.engineLabel.value = "引擎 ${this.engineVia} · ${this.enginePath}"

        if (this.staleContract.value) {
            this.statusText.value = this.problem.value
            return
        }
        match (this.snapshot.value) {
            case None =>
                this.statusText.value = "尚未读取"
            case Some(s) =>
                if (!s.failedKnown) {
                    this.statusText.value =
                        "引擎未披露失败项目数（版本过旧），「读取失败」一栏显示 ? 而不是 0"
                } else if (s.failedProjects > 0) {
                    this.statusText.value = "有 ${s.failedProjects} 个项目读取失败，原因见仪表盘与列表"
                } else {
                    this.statusText.value = "已注册 ${s.listedProjects} 个项目，全部读取成功"
                }
        }
    }

    /// 重新计算所有派生文案。状态写完必须调它 ——
    /// 派生文案散在各处各写一遍，是「同一件事显示两种说法」的常见来源。
    public func refreshLabels(): Unit {
        this.syncLabels()
    }
}

/// 引擎定位 + 首次读取。
public func boot(app: DesktopApp, model: AppModel): Unit {
    requestRefresh(app, model)
}

/// 发起一次读取。引擎调用在后台线程，结果 `post` 回 UI 线程。
public func requestRefresh(app: DesktopApp, model: AppModel): Unit {
    if (model.busy.value) {
        // 闸门：连点第二次直接返回。
        // 注意：不排队、不排队。排队会让用户以为这次点击又多做了一件事，
        // 而实际上它只是被合并进了正在跑的那一次。
        return
    }
    if (model.enginePath.isEmpty()) {
        // 引擎都没找到，没什么可「读」的 —— 但状态条必须已经把话说清楚了。
        return
    }

    model.busy.value = true
    model.statusText.value = "正在读取…"

    let bin = model.enginePath
    spawn {
        let statusCall = callEngine(bin, ["status", "--json"], ENGINE_TIMEOUT_MS)
        let dashCall = callEngine(bin, ["dashboard", "--json"], ENGINE_TIMEOUT_MS)
        app.post {
            model.busy.value = false
            applyCalls(model, statusCall, dashCall)
        }
    }
}

/// 把两次调用的结果写进状态。
///
/// status 与 dashboard **互不连坐**：dashboard 挂了不能把已经拿到的
/// 项目列表也一起清空 —— 那是「因为一个附属功能失败而丢掉主功能的数据」。
private func applyCalls(model: AppModel, statusCall: EngineCall, dashCall: EngineCall): Unit {
    if (statusCall.staleContract) {
        model.staleContract.value = true
        model.problem.value = statusCall.problem
    } else if (!statusCall.problem.isEmpty()) {
        model.staleContract.value = false
        model.problem.value = statusCall.problem
    } else {
        model.staleContract.value = false
        model.problem.value = ""
    }

    if (let Some(v) <- statusCall.payload) {
        model.snapshot.value = Some(StatusSnapshot.from(v))
        // 选中的下标可能越过新列表的长度 —— 项目被注销后就会这样。
        // 不夹住的话，详情页会渲染成一个不存在的项目或直接越界。
        let n = model.snapshot.value.getOrThrow().projects.size
        if (model.selected.value >= n) {
            model.selected.value = if (n > 0) { n - 1 } else { 0 }
        }
    }

    if (let Some(v) <- dashCall.payload) {
        if (!dashCall.staleContract) {
            model.dashboard.value = Some(Dashboard.from(v))
        }
    }

    model.refreshLabels()
}
