// deepDolphin Linux 客户端 —— 应用状态与动作。
//
// 全部界面状态集中在这里，且**只有这里**能改。
// 引擎调用一律在后台线程跑，结果通过 `DesktopApp.post` 回到 UI 线程再写状态 ——
// UI 线程上 `Future.get()` 会同时冻结输入与绘制，而深更新要跑好几分钟。
package deepdolphin_linux

import std.collection.*
import std.fs.*
import cui.{DesktopApp, State}

/// C2 规定的轮询周期：5 分钟。
public const POLL_INTERVAL_MS: Int64 = 300000

public class AppModel {
    // -------------------------------------------------------------- 读侧数据
    public let snapshot = State<Option<StatusSnapshot>>(None)
    public let dashboard = State<Option<Dashboard>>(None)
    /// C9 里程碑
    public let milestones = State<Option<MilestoneSnapshot>>(None)
    /// C3 日志（按当前选中项目懒加载）
    public let journal = State<Option<Journal>>(None)
    /// C3 文档（按当前选中项目懒加载）
    public let docs = State<Option<DocBundle>>(None)

    // -------------------------------------------------------------- 导航
    public let selected = State<Int64>(0)
    /// 详情页内的子页：概览 / 提交构成 / 分支 / 日志 / git
    public let detailTab = State<Int64>(0)
    /// 文档页内的文件页签（README / AGENTS / CLAUDE）
    public let docTab = State<Int64>(0)

    // -------------------------------------------------------------- 忙碌与结果
    /// 读操作中。闸门只挡**重复发起**，不排队 ——
    /// 排队会让用户以为这次点击又多做了一件事。
    public let busy = State<Bool>(false)
    /// 写操作中。读侧与写侧**分开**：
    /// 深更新要跑几分钟，期间的自动轮询必须让路，否则两个引擎进程抢锁。
    public let actionBusy = State<Bool>(false)
    /// 正在跑的动作名，显示在按钮旁。
    public let actionLabel = State<String>("")
    /// 上一条动作的结果（一行）。写操作**必须**留结果，
    /// 「按了没反应」和「跑了但没变化」在界面上长得一样。
    public let lastResult = State<String>("")
    public let lastResultOk = State<Bool>(true)

    public let problem = State<String>("")
    public let staleContract = State<Bool>(false)
    /// 仪表盘载荷被契约闸门拒掉时的原因。**空串 = 正常**。
    ///
    /// ⚠ 这一栏存在的理由：闸门拒掉载荷时如果不留痕，界面会回落到
    /// `Dashboard.empty()` —— 用户看到「语言分布：没有采集到」「待办：全 0」，
    /// 而真实情况是「这份载荷被丢了」。把「读不出来」画成「确实没有」，
    /// 是比报错更坏的一种失败。
    public let dashboardProblem = State<String>("")
    /// 里程碑载荷被拒时的原因。空串 = 正常。
    public let milestonesProblem = State<String>("")
    /// 日志载荷被拒时的原因。空串 = 正常。
    public let journalProblem = State<String>("")
    /// 文档载荷被拒 / 读出错时的原因。空串 = 正常。
    public let docsProblem = State<String>("")
    public let statusText = State<String>("")
    public let emptyHint = State<String>("")
    public let engineLabel = State<String>("")
    public let canRefresh = State<Bool>(false)

    // -------------------------------------------------------------- 轮询
    public let pollEnabled = State<Bool>(true)
    /// 距离下次轮询还有多少毫秒。由 FrameHandler 推进。
    public let pollCountdown = State<Int64>(POLL_INTERVAL_MS)

    // -------------------------------------------------------------- 外观
    /// 走暗色色板。**必须是 State** —— 用户在设置里切亮/暗时
    /// 整棵树要按新色板重画，藏在普通字段里这次切换就不会生效，
    /// 表现是「按钮点了，界面没变，用户以为按钮坏了」。
    public let dark = State<Bool>(false)
    /// 用户选的外观档（跟随系统 / 亮 / 暗）。
    public let appearance = State<DsAppearance>(DsAppearance.System)
    /// 选了「跟随系统」但系统没给出答案。**要说出来**，见 `appearance.cj`。
    public let appearanceUnknown = State<Bool>(false)

    public var booted: Bool = false

    // ------------------------------------------------- 仪表盘筛选（段 2）
    /// 时间跨度。**状态必须在模型上，不能挂视图**：看板是第二个消费方
    /// （同屏里两个视图必须对「在看什么」说同一句话），各存一份就必然出现
    /// 「仪表盘 1 个 / 看板 3 个」。macOS 端 2026-10 修的正是这个。
    public let dashSpan = State<DashSpan>(DashSpan.All)
    /// 提交类型筛选。**只作用于项目卡的提交结构条**，不改 KPI 数字。
    public let dashCommits = State<DashCommitFilter>(DashCommitFilter.AllCommits)

    // -------------------------------------------------------------- 导航
    /// 当前选中的**视图**（侧栏「视图」组）。项目是另一维，见 `selectedProject`。
    public let root = State<RootSection>(RootSection.Dashboard)    /// 当前选中的**项目名**。空串 = 没选。
    ///
    /// ⚠ 为什么与 `root` 分开而不是塞进一个枚举：macOS 端用
    /// `RootSection.project(String)` 一个枚举同时表达两者，本端拆开是因为
    /// CUI 的 `ListView` 用 Int64 索引、`LazyList` 用 Int64 索引，
    /// 侧栏把两组渲染成**同一个列表**（macOS 端也是一个 `List(selection:)`），
    /// 用索引当唯一标识比在枚举里塞字符串更直接。
    /// 两者的**组合关系**由 `selectedIsViewRow` / `selectedProject` 维护。
    public let selectedProject = State<String>("")
    /// 侧栏里被选中的那一行的全局序号（视图组 + 仓库组连续编号）。
    public let selectedRow = State<Int64>(0)
    /// 侧栏搜索词。空 = 不过滤。
    public let query = State<String>("")
    /// 范围（WorkBar 左段）。Group = 全局看板，One = 单仓库管控页。
    public let scope = State<ScopeChoice>(ScopeChoice.Group)
    /// 上次刷新完成的时刻（毫秒）。侧栏状态条要显示它。
    public let lastRefreshedMs = State<Int64>(0)
    /// 深链打错字之类的说明。独立于 `problem`，不依赖 `busy`。
    public let routeNotice = State<String>("")

    public let enginePath: String
    public let engineVia: String
    private let engineProblem: String

    public init(loc: EngineLocation) {
        this.enginePath = loc.path
        this.engineVia = loc.via
        this.engineProblem = loc.problem
        this.syncLabels()
    }

    public func engineReady(): Bool {
        return !this.engineProblem.isEmpty() || !this.enginePath.isEmpty()
    }

    // -------------------------------------------------------------- 派生文案
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

    public func currentProject(): Option<Project> {
        match (this.snapshot.value) {
            case Some(s) =>
                let i = this.selected.value
                if (i >= 0 && i < s.projects.size) {
                    return Some(s.projects[i])
                }
                return None
            case None => return None
        }
    }

    private func syncLabels(): Unit {
        if (!this.engineProblem.isEmpty()) {
            this.problem.value = this.engineProblem
            this.emptyHint.value = this.engineProblem
            this.statusText.value = this.engineProblem
            this.canRefresh.value = false
            return
        }
        this.emptyHint.value = "点右上角「刷新」读取项目群。"
        this.canRefresh.value = true
        this.engineLabel.value = engineLabelFor(this.engineVia, this.enginePath)

        if (this.staleContract.value) {
            this.statusText.value = this.problem.value
            return
        }
        if (this.actionBusy.value) {
            this.statusText.value = "正在执行：${this.actionLabel.value}"
            return
        }
        match (this.snapshot.value) {
            case None => this.statusText.value = "尚未读取"
            case Some(s) =>
                if (!s.failedKnown) {
                    this.statusText.value = "引擎未披露失败项目数（版本过旧），「读取失败」一栏显示 ? 而不是 0"
                } else if (s.failedProjects > 0) {
                    this.statusText.value = "有 ${s.failedProjects} 个项目读取失败，原因见仪表盘与列表"
                } else {
                    this.statusText.value = "已注册 ${s.listedProjects} 个项目，全部读取成功"
                }
        }
    }

    public func refreshLabels(): Unit {
        this.syncLabels()
    }

    /// 一行结果。写操作走这里。
    public func report(line: String, ok: Bool): Unit {
        this.lastResult.value = line
        this.lastResultOk.value = ok
        this.refreshLabels()
    }
}

// ===========================================================================
// 读：状态轮询（C2）
// ===========================================================================

public func boot(app: DesktopApp, model: AppModel): Unit {
    requestRefresh(app, model)
}

public func requestRefresh(app: DesktopApp, model: AppModel): Unit {
    if (model.busy.value || model.actionBusy.value) {
        return
    }
    if (model.enginePath.isEmpty()) {
        return
    }
    model.busy.value = true
    model.refreshLabels()

    let bin = model.enginePath
    spawn {
        let statusCall = opStatus(bin)
        let dashCall = opDashboard(bin)
        let msCall = opMilestoneList(bin)
        app.post {
            model.busy.value = false
            applyReads(model, statusCall, dashCall, msCall)
        }
    }
}

private func applyReads(
    model: AppModel,
    statusCall: Payload,
    dashCall: Payload,
    msCall: Payload
): Unit {
    applyStatusCall(model, statusCall)
    // 每一路读**各自**记自己的失败原因。共用一个 `problem` 的话，
    // 四路里坏了一路就会把另外三路正常的数据也一起标成不可信。
    model.dashboardProblem.value = readProblem(dashCall, PayloadShape.Dashboard)
    model.milestonesProblem.value = readProblem(msCall, PayloadShape.Milestones)
    if (model.dashboardProblem.value.isEmpty() && !dashCall.problem.isEmpty()) {
        model.dashboardProblem.value = dashCall.problem
    }
    if (model.milestonesProblem.value.isEmpty() && !msCall.problem.isEmpty()) {
        model.milestonesProblem.value = msCall.problem
    }
    if (!model.dashboardProblem.value.isEmpty()) {
        model.dashboard.value = None
    } else if (let Some(v) <- dashCall.json) {
        model.dashboard.value = Some(Dashboard.from(v))
    }
    if (!model.milestonesProblem.value.isEmpty()) {
        model.milestones.value = None
    } else if (let Some(v) <- msCall.json) {
        model.milestones.value = Some(MilestoneSnapshot.from(v))
    }
    if (!statusCall.problem.isEmpty()) {
        model.problem.value = statusCall.problem
    }
    model.refreshLabels()
}

/// 一路读的失败原因。**空串代表没问题**，两种失败说法不一样：
/// 被闸门拒 = 引擎太旧/形状不对；调用本身失败 = 执行出错。
public func readProblem(p: Payload, shape: PayloadShape): String {
    if (p.staleContract) {
        return "${shapeLabel(shape)}载荷缺少约定的披露字段，已丢弃这份数据 —— " +
            "界面不会用 0 代替它。请升级 moonGit 引擎。"
    }
    if (!p.problem.isEmpty()) {
        return p.problem
    }
    if (p.json.isNone()) {
        return "${shapeLabel(shape)}：引擎没有返回可解析的结果。"
    }
    return ""
}

/// 从**夹具目录**读一轮，写进 model。返回读到了几个。
///
/// 【为什么需要它】自查布局时，引擎子进程那条路在快照模式下**不可用**：
/// CUI 快照是「连续强制重绘 48 帧就拍照」（`forced = snapshotPath.isSome()`），
/// 渲染循环全速跑，而 `execCapture` 内部要 `spawn` 两个管道读线程再 `wait()`；
/// 线程池被逐帧保留体占满，读线程拿不到执行机会，于是
/// 拍到的永远是「读取项目群…」。试过的三条路都记在 `main.cj` 里了。
///
/// 夹具是**引擎真实输出**（`tests/fixtures/*.json` 由 `moongit status/dashboard/
/// milestone list --json` 直接导出），所以布局自查验的是真数据形状，
/// 不是手编的假对象。`DD_FIXTURE_DIR` 环境变量启用。
public func loadFromFixtureDir(model: AppModel, dir: String): Int64 {
    var n: Int64 = 0
    match (loadOneFixture(model, dir, "status.json", PayloadShape.Status)) {
        case Some(v) =>
            applyStatusCall(model, Payload(Some(v), "", false, 0, "", staleContract: false))
            n += 1
        case None => ()
    }
    match (loadOneFixture(model, dir, "dashboard.json", PayloadShape.Dashboard)) {
        case Some(v) =>
            model.dashboard.value = Some(Dashboard.from(v))
            model.dashboardProblem.value = ""
            n += 1
        case None =>
            model.dashboard.value = None
            model.dashboardProblem.value = "读不到夹具 ${dir}/dashboard.json"
    }
    match (loadOneFixture(model, dir, "milestones.json", PayloadShape.Milestones)) {
        case Some(v) =>
            model.milestones.value = Some(MilestoneSnapshot.from(v))
            model.milestonesProblem.value = ""
            n += 1
        case None =>
            model.milestones.value = None
            model.milestonesProblem.value = "读不到夹具 ${dir}/milestones.json"
    }
    model.refreshLabels()
    return n
}

/// 读一份夹具并过契约闸门。**闸门照走** —— 夹具模式不是后门，
/// 契约不过就该显示「未读取」，不能让自查路径比真实路径宽松。
private func loadOneFixture(model: AppModel, dir: String, name: String, shape: PayloadShape): Option<JsonValue> {
    let path = "${dir}/${name}"
    match (readTextFileOf(path)) {
        case Some(text) =>
            match (Json.parse(text)) {
                case Some(v) =>
                    if (checkContractOf(v, shape)) {
                        return Some(v)
                    }
                    return None
                case None => return None
            }
        case None => return None
    }
}

/// 读文本文件，**读不到返回 `None`**（不是空串）。
/// 空串会被 `Json.parse` 判成「没有 JSON」，两种失败在界面上说法不同。
public func readTextFileOf(path: String): Option<String> {
    let p = Path(path)
    if (path.isEmpty() || !exists(p)) {
        return None
    }
    try {
        return Some(String.fromUtf8(File.readFrom(p)))
    } catch (e: Exception) {
        return None
    }
}

func applyStatusCall(model: AppModel, statusCall: Payload): Unit {
    model.staleContract.value = statusCall.staleContract
    if (statusCall.problem.isEmpty()) {
        model.problem.value = ""
    } else {
        model.problem.value = statusCall.problem
    }
    if (let Some(v) <- statusCall.json) {
        model.snapshot.value = Some(StatusSnapshot.from(v))
        let n = model.snapshot.value.getOrThrow().projects.size
        if (model.selected.value >= n) {
            model.selected.value = if (n > 0) { n - 1 } else { 0 }
        }
    }
    model.refreshLabels()
}

/// C2 轮询：一条睡到点再唤醒 UI 的后台线程。
///
/// ## 为什么不是 FrameHandler
///
/// `FrameHandler` 每帧回调并**每帧请求下一帧**（`event_handler.cj` 里
/// 写死 `ctx.requestFrame()`），等于让应用常驻 60fps。实测挂上之后
/// profile 里 `强制 60`、文本度量每帧都在跑 —— 而周期是 5 分钟。
/// 为了 5 分钟醒一次而每帧烧 CPU，笔记本上就是持续的风扇声。
///
/// CUI 的 `UiContext.requestFrameAt(deadline)` 能按截止时间唤醒，
/// 但 `registerFrameSubscriber` 是 `protected`，跨包的自定义 Widget 用不上；
/// 走 `handle` 拦截 `UiEvent::Frame` 又得依赖同样受保护的 `buildChild`。
/// 与其为绕开这个限制写一整套自定义控件，不如用一条睡着的线程：
/// 睡眠期间应用是**真正的 0 帧空闲**，醒来 `post` 一次即可。
public func startPolling(app: DesktopApp, model: AppModel): Unit {
    spawn {
        while (true) {
            sleepMs(POLL_INTERVAL_MS)
            if (!model.pollEnabled.value) {
                continue
            }
            // post 失败只表示应用已停止，醒来下一轮自然退出。
            if (app.post({=>
                if (model.pollEnabled.value && !model.actionBusy.value && !model.busy.value) {
                    requestRefresh(app, model)
                }
            })) {
                ()
            }
        }
    }
}

/// 睡指定毫秒。拆成小段是为了能被 Ctrl-C 及时打断 ——
/// 一次睡 5 分钟的话，关闭应用要等它睡醒。
private func sleepMs(total: Int64): Unit {
    var left = total
    while (left > 0) {
        let chunk = (if (left > 200) { 200 } else { left })
        sleep(Duration.millisecond * chunk)
        left -= chunk
    }
}

// ===========================================================================
// 写：更新（C4）
// ===========================================================================

/// 所有写动作共用的闸门。
///
/// 闸门是**全局**的而不是「每个按钮一个」：
/// 深更新跑 5 分钟，期间用户点「浅更新全部」并不会让两个引擎进程并行 ——
/// 引擎侧有项目锁，并行只会让两边都等锁，最后一起超时。
/// 一个全局闸门 + 明确的「正在执行：xxx」，比 N 个独立按钮清楚得多。
private func beginAction(model: AppModel, label: String): Bool {
    if (model.actionBusy.value) {
        model.report("已有动作在跑（${model.actionLabel.value}），等它结束再试", false)
        return false
    }
    model.actionBusy.value = true
    model.actionLabel.value = label
    model.lastResult.value = "正在${label}…"
    model.refreshLabels()
    return true
}

private func endAction(model: AppModel, line: String, ok: Bool): Unit {
    model.actionBusy.value = false
    model.actionLabel.value = ""
    model.report(line, ok)
}

public func actUpdate(app: DesktopApp, model: AppModel, project: String, deep: Bool): Unit {
    let label = (if (deep) { "深更新" } else { "浅更新" }) + " ${project}"
    if (!beginAction(model, label)) {
        return
    }
    let bin = model.enginePath
    spawn {
        let p = opUpdate(bin, project, deep)
        app.post {
            let line = if (let Some(v) <- p.json) {
                let u = UpdateOutcome.from(v)
                (if (u.ok) { "✓ " } else { "✗ " }) + label + "：" + u.summaryLine()
            } else {
                "✗ " + label + "：" + p.problem
            }
            endAction(model, line, p.problem.isEmpty())
            // 写操作改变了事实，必须重读。放在写之后而不是之前，
            // 否则读到的还是旧状态。
            requestRefresh(app, model)
        }
    }
}

public func actUpdateAll(app: DesktopApp, model: AppModel, deep: Bool): Unit {
    let label = (if (deep) { "深更新" } else { "浅更新" }) + " 全部项目"
    if (!beginAction(model, label)) {
        return
    }
    let bin = model.enginePath
    spawn {
        let p = opUpdateAll(bin, deep)
        app.post {
            let line = if (let Some(v) <- p.json) {
                describeBulkResult(v)
            } else {
                "✗ " + label + "：" + p.problem
            }
            endAction(model, line, p.problem.isEmpty())
            requestRefresh(app, model)
        }
    }
}

/// 批量结果的一行摘要。
///
/// 逐项目成败必须**分得开**：只报「成功 3 个失败 3 个」而不说是哪三个，
/// 用户只能自己一个个点开找 —— 而失败的往往正是他在乎的那几个。
public func describeBulkResult(v: JsonValue): String {
    let list = Json.arrAt(v, "projects")
    if (list.isEmpty()) {
        return "引擎没有返回逐项目结果（形状：${joinAll(Json.objKeys(v), "、")}）"
    }
    var okCount: Int64 = 0
    let failed = ArrayList<String>()
    for (p in list) {
        if (Json.boolAt(p, "ok", false)) {
            okCount += 1
        } else {
            let n = Json.strAt(p, "project", "?")
            let e = Json.strAt(p, "error", "")
            failed.add(if (e.isEmpty()) { n } else { "${n}（${e}）" })
        }
    }
    if (failed.isEmpty()) {
        return "全部 ${okCount} 个项目执行成功"
    }
    return "已注册 ${list.size} 个，本次实际执行 ${okCount + failed.size} 个，" +
        "成功 ${okCount} 个，失败 ${failed.size} 个：${joinAll(failed.toArray(), "、")}"
}

// ===========================================================================
// 写：git 操作（C8）
// ===========================================================================

public func actGit(app: DesktopApp, model: AppModel, project: String, op: String, message: String): Unit {
    let label = "${gitOpLabel(op)} ${project}"
    if (!beginAction(model, label)) {
        return
    }
    let bin = model.enginePath
    spawn {
        let p = opGit(bin, project, op, message)
        app.post {
            var line: String
            if (let Some(v) <- p.json) {
                let g = GitResult.from(v)
                let head = (if (g.ok) { "✓ " } else { "✗ " }) + label
                // git 的输出**成功时也要显示**：pull 说「Already up to date」
                // 与说有 3 个新提交，后续处理完全不同。
                line = if (g.output.isEmpty()) { head } else { "${head}：${g.output.trimAscii()}" }
            } else {
                line = "✗ " + label + "：" + p.problem
            }
            endAction(model, line, p.ok())
            requestRefresh(app, model)
        }
    }
}

// ===========================================================================
// 写：里程碑（C9）
// ===========================================================================

public func actMilestone(
    app: DesktopApp,
    model: AppModel,
    project: String,
    name: String,
    action: String
): Unit {
    let label = "里程碑「${name}」${milestoneActionLabel(action)}"
    if (!beginAction(model, label)) {
        return
    }
    let bin = model.enginePath
    spawn {
        let p = opMilestoneAction(bin, project, name, action)
        app.post {
            var line: String
            if (let Some(v) <- p.json) {
                // 引擎会明确回 applied：false（tag 自动达成失败等）。
                // 不看它就报成功，是在说谎。
                let applied = Json.boolAt(v, "applied", true)
                line = (if (applied) { "✓ " } else { "✗ " }) + label
                if (let Some(s) <- Json.get(v, "status")) {
                    line = line + " → ${Json.asStr(s).getOrThrow()}"
                }
            } else {
                line = "✗ " + label + "：" + p.problem
            }
            endAction(model, line, p.ok())
            requestRefresh(app, model)
        }
    }
}

public func actMilestoneAdd(
    app: DesktopApp,
    model: AppModel,
    project: String,
    name: String,
    tag: String,
    targetDate: String,
    description: String
): Unit {
    let label = "新建里程碑「${name}」"
    if (!beginAction(model, label)) {
        return
    }
    let bin = model.enginePath
    spawn {
        let p = opMilestoneAdd(bin, project, name, tag, targetDate, description)
        app.post {
            let line = if (let Some(v) <- p.json) {
                (if (Json.boolAt(v, "created", false)) { "✓ " } else { "✗ " }) + label
            } else {
                "✗ " + label + "：" + p.problem
            }
            endAction(model, line, p.ok())
            requestRefresh(app, model)
        }
    }
}

public func milestoneActionLabel(action: String): String {
    match (action) {
        case "done" => return "标记达成"
        case "open" => return "重新打开"
        case "drop" => return "放弃"
        case "remove" => return "删除"
        case _ => return action
    }
}

// ===========================================================================
// 写：项目注册
// ===========================================================================

public func actScan(app: DesktopApp, model: AppModel, root: String, depth: Int64): Unit {
    let label = "扫描 ${root}"
    if (!beginAction(model, label)) {
        return
    }
    let bin = model.enginePath
    spawn {
        let p = opScan(bin, root, depth)
        app.post {
            let line = if (p.ok()) { "✓ " + label } else { "✗ " + label + "：" + p.problem }
            endAction(model, line, p.ok())
            requestRefresh(app, model)
        }
    }
}

public func actAddProject(app: DesktopApp, model: AppModel, path: String, name: String): Unit {
    let label = "注册项目 ${path}"
    if (!beginAction(model, label)) {
        return
    }
    let bin = model.enginePath
    spawn {
        let p = opAddProject(bin, path, name)
        app.post {
            let line = if (p.ok()) { "✓ " + label } else { "✗ " + label + "：" + p.problem }
            endAction(model, line, p.ok())
            requestRefresh(app, model)
        }
    }
}

// ===========================================================================
// C3 详情页的懒加载
// ===========================================================================

/// 切换选中项目时加载它的日志与文档。
///
/// 懒加载而不是一次全拉：`journal <项目> --json` 与 `docs <项目> --json`
/// 都是**按项目**的，10 个项目就是 20 次子进程调用。首屏只把选中那个拉起来，
/// 其余的等点到再说。
public func loadProjectDetail(app: DesktopApp, model: AppModel): Unit {
    match (model.currentProject()) {
        case None =>
            model.journal.value = None
            model.docs.value = None
        case Some(p) =>
            if (p.failed()) {
                // 采集失败的项目没有文档也没有日志可读。
                // 这里返回而不是发请求，免得拿一个必然失败的调用换个更慢的失败。
                model.journal.value = None
                model.docs.value = None
                return
            }
            let bin = model.enginePath
            let name = p.name
            spawn {
                let j = opJournal(bin, name)
                let d = opDocs(bin, name)
                app.post {
                    // 回包可能晚于用户切走 —— 对一下项目名，
                    // 不然 A 项目的日志会显示在 B 项目的详情页里。
                    match (model.currentProject()) {
                        case Some(cur) =>
                            if (cur.name != name) {
                                return
                            }
                        case None => return
                    }
                    if (let Some(v) <- j.json) {
                        model.journal.value = Some(Journal.from(v))
                    }
                    if (let Some(v) <- d.json) {
                        model.docs.value = Some(DocBundle.from(v))
                    }
                }
            }
    }
}

/// 顶栏那行引擎说明。
///
/// ⚠ **不显示全路径**。原来写的是 `引擎 仓内构建 · /Volumes/…/moonGit/target/release/bin/main`，
/// 这个 Label 的固有宽度就是整条路径，HStack 里它把右边的按钮整排挤出窗口 ——
///
///   [截图证据] 「浅更新全部」被切掉、「深更新全部」整个不见了。
///
/// 路径长度在别的机器上会更长（HOME 不同），所以这不是「这台机器上有点挤」。
/// 这里是**纯函数**（收 via 与 path），判据可以直接喂长路径。
///
/// 只留「来源 + 末两段」：`仓内构建 · target/release/bin/main` 足够定位，
/// 而要完整路径的人去设置里看。
/// 顶栏那句。**只说用户能据此行动的话**。
///
/// 原来返回 `引擎 DEEPGIT_BIN · bin/main` —— 那是在报「我们是从哪个环境变量、
/// 路径的哪两段找到引擎的」。这是**诊断信息，不是产品信息**：
/// 用户看到 `DEEPGIT_BIN` 这个环境变量名，既不知道它指什么，也不知道该做什么；
/// 而顶栏是整屏最贵的一行，标题右侧就那么一格。引擎找不到时该说的话在
/// 引擎引导页（`setupGuide`）里说全了，不需要在顶栏再报一次来源。
///
/// `via` / `path` 仍作为参数收着：诊断信息在别处（问题条、引擎引导页）要用，
/// 这里是明确**不往顶栏放**的取舍，不是漏了。
public func engineLabelFor(via: String, path: String): String {
    if (path.isEmpty()) {
        return (if (via.isEmpty()) { "未找到引擎" } else { "引擎未就绪" })
    }
    return "引擎已就绪"
}

private func lastTwoSegments(path: String): String {
    var s = path
    var out = ""
    for (_ in 0..2) {
        let i = lastSlash(s)
        if (i < 0) {
            return (if (out.isEmpty()) { s } else { "${s}/${out}" })
        }
        let seg = s[i + 1..]
        out = (if (out.isEmpty()) { seg } else { "${seg}/${out}" })
        s = s[..i]
    }
    out
}

// ===========================================================================
// 根选区 —— 与 macOS 端 `RootSection` 一一对应
// ===========================================================================

/// 当前选中的「根」。**侧栏同时承载视图导航与仓库列表**，
/// 所以选中项是这两种东西的合流，不是「视图页签 + 另一个项目下拉」。
///
/// 这也是为什么本端**没有顶部页签栏**：macOS 端把两组导航都收在侧栏里，
/// 顶部只留工具类动作。我先前做成「顶部 TabView + 侧栏项目列表」，
/// 于是同一个项目在两个地方都能「选」，而选中状态只有一个 —— 两处会各说各话。
public enum RootSection {
    | Dashboard
    | Board
    | Milestones
    | Project
}

public func rootSectionLabel(r: RootSection): String {
    match (r) {
        case RootSection.Dashboard => return "仪表盘"
        case RootSection.Board => return "看板"
        case RootSection.Milestones => return "里程碑"
        case RootSection.Project => return "项目详情"
    }
}

public func rootSectionIs(r: RootSection, other: RootSection): Bool {
    match (r) {
        case RootSection.Dashboard => return match (other) {
            case RootSection.Dashboard => true
            case _ => false
        }
        case RootSection.Board => return match (other) {
            case RootSection.Board => true
            case _ => false
        }
        case RootSection.Milestones => return match (other) {
            case RootSection.Milestones => true
            case _ => false
        }
        case RootSection.Project => return match (other) {
            case RootSection.Project => true
            case _ => false
        }
    }
}

/// 范围（WorkBar 左段那个选择器）。
///
/// 「看整个项目群」与「看某一个仓库」是两个**正交**的选择：
/// 侧栏管「看哪个视图」，范围管「看哪些仓库」。
/// 砍掉范围选择器后，用户没法从仪表盘直接跳进某个仓库，只能退回侧栏再点一次。
public enum ScopeChoice {
    | Group
    | One
}

/// 侧栏搜索。匹配**项目名 + 分支名** —— 用户记得「那条 feat 分支」时也能搜到。
public func filterProjects(ps: ArrayList<Project>, query: String): ArrayList<Project> {
    let q = query.trimAscii()
    if (q.isEmpty()) {
        return ps
    }
    let out = ArrayList<Project>()
    for (p in ps) {
        if (asciiLower(p.name).contains(asciiLower(q))) {
            out.add(p)
            continue
        }
        for (b in p.branches) {
            if (asciiLower(b.name).contains(asciiLower(q))) {
                out.add(p)
                break
            }
        }
    }
    return out
}

/// 空列表的原因。**「没有项目」与「搜出来是空」必须分开**。
public enum EmptyReason {
    // ⚠ 不能叫 `None`。仓颉里 `None` 是 `Option` 的构造器，枚举 case 在包作用域
    // 可见 —— 一旦本枚举占了 `None`，全仓所有 `State<Option<T>>(None)` 都会被解析成
    // `EmptyReason.None`，编译报「expected Option<X>, found Enum-EmptyReason」，
    // 错的位置在毫不相干的文件里。`DsStat.None` 踩过一次，这里是同一个坑。
    | NoReason
    | NoProjects
    | NoMatch
}

public func emptyReason(allCount: Int64, shownCount: Int64, query: String): EmptyReason {
    if (allCount == 0) {
        return EmptyReason.NoProjects
    }
    if (shownCount == 0) {
        return EmptyReason.NoMatch
    }
    return EmptyReason.NoReason
}

public func emptyText(r: EmptyReason, noun: String): String {
    match (r) {
        case EmptyReason.NoProjects => return "没有已注册项目。跑一次 moongit scan <目录> 注册。"
        case EmptyReason.NoMatch => return "没有匹配「该搜索词」的${noun}。"
        case EmptyReason.NoReason => return ""
    }
}

/// 侧栏「视图」组的行数。视图行与仓库行**共用一个连续序号**，
/// 所以这里的常量就是「第一行仓库在侧栏里的位置」。
public const SIDEBAR_VIEW_ROWS: Int64 = 3

/// 侧栏行的总数 = 视图组 + 仓库组。
public func sidebarRowCount(projectCount: Int64): Int64 {
    return SIDEBAR_VIEW_ROWS + projectCount
}

/// 第 `i` 行是哪个视图。**纯函数**，判据直接喂序号。
public func viewRowAt(i: Int64): Option<RootSection> {
    match (i) {
        case 0 => return Some(RootSection.Dashboard)
        case 1 => return Some(RootSection.Board)
        case 2 => return Some(RootSection.Milestones)
        case _ => return None
    }
}

/// 第 `i` 行对应哪个项目（`i >= SIDEBAR_VIEW_ROWS`）。
public func projectRowAt(i: Int64, projects: ArrayList<Project>): Option<Project> {
    let k = i - SIDEBAR_VIEW_ROWS
    if (k < 0 || k >= projects.size) {
        return None
    }
    return Some(projects[k])
}

/// 选中行 → 当前视图。**只有一个写入口**，视图和详情都读它。
///
/// ⚠ 别在别处直接写 `root` / `selectedProject` —— 两处都能写就会出现
/// 「侧栏高亮在 A、详情显示 B」。和 macOS 端 `model.go(_:)` 同一条纪律。
public func goRow(model: AppModel, row: Int64, projects: ArrayList<Project>): Unit {
    if (row < 0 || row >= sidebarRowCount(projects.size)) {
        // 点到不存在的行**什么都不做**。把选中改成某个不存在的项目、
        // 或者弹一个空详情页，那正是「点了没反应」的另一种形态。
        return
    }
    match (viewRowAt(row)) {
        case Some(r) =>
            model.root.value = r
            model.selectedRow.value = row
            if (!rootSectionIs(r, RootSection.Project)) {
                model.selectedProject.value = ""
            }
            return
        case None => ()
    }
    if (let Some(p) <- projectRowAt(row, projects)) {
        model.selectedProject.value = p.name
        model.root.value = RootSection.Project
        model.selectedRow.value = row
    }
}

/// 当前选中的项目。**读不出来返回 `None`**，不回落成「第一个」。
public func selectedProjectOf(model: AppModel): Option<Project> {
    let name = model.selectedProject.value
    if (name.isEmpty()) {
        return None
    }
    match (model.snapshot.value) {
        case Some(s) =>
            for (p in s.projects) {
                if (p.name == name) {
                    return Some(p)
                }
            }
            // 选中的项目这轮没出现在列表里 —— 说出来，不要静默跳走。
            model.routeNotice.value = "「${name}」这一轮没有出现在项目列表里，可能已被移出托管区。"
            return None
        case None => return None
    }
}

/// 看板行尾的「要你动手」项目数。**读不出来返回 `None`（不显示），不是 0**。
///
/// ⚠ 报的是**待处理数**，不是项目总数 —— 每个视图行都挂同一个总数的话，
/// 徽标就成了装饰。而 `None` 与 `0` 在这一行长得一样：
/// 「读不出来」与「真的是 0」不能画成同一张脸。
public func attentionCount(model: AppModel, nowMs: Int64): Option<Int64> {
    if (model.snapshot.value.isNone()) {
        return None
    }
    let s = model.snapshot.value.getOrThrow()
    var n: Int64 = 0
    for (p in s.projects) {
        if (boardColumnIs(boardColumnOf(projectLiveness(p, nowMs)), BoardColumn.Attention)) {
            n += 1
        }
    }
    return Some(n)
}

/// 里程碑行尾的总数。只数 `open + done`，**不含 unknown** ——
/// unknown 是「读不出来」，算进「你有 N 个里程碑」就是把无知说成事实。
public func milestoneCountOf(model: AppModel): Option<Int64> {
    match (model.milestones.value) {
        case Some(ms) => return Some(Int64(ms.openOnes().size + ms.doneOnes().size))
        case None => return None
    }
}

/// 双轨按钮上的「待处理」数。**只在真有东西时显示** ——
/// 恒显的 0 徽章会被无视，而「0」还容易被读成「引擎说不用更新」。
public func pendingShallow(model: AppModel, nowMs: Int64): Int64 {
    match (model.snapshot.value) {
        case Some(s) =>
            var n: Int64 = 0
            for (p in s.projects) {
                if (projectNeedsAction(p)) {
                    n += p.untrackedCount + p.userDirtyCount
                }
            }
            return n
        case None => return 0
    }
}

/// 双轨按钮的标题随范围变化。`全部` 后缀**只在全局范围下出现**。
public func shallowLabelFor(scope: ScopeChoice): String {
    return (match (scope) {
        case ScopeChoice.Group => "浅更新 · 全部"
        case ScopeChoice.One => "浅更新"
    })
}

public func deepLabelFor(scope: ScopeChoice): String {
    return (match (scope) {
        case ScopeChoice.Group => "深更新 · 全部"
        case ScopeChoice.One => "深更新"
    })
}

/// 两个看板列是否相同。仓颉枚举没有 `==`（编译期报 invalid binary operator）。
public func boardColumnIs(a: BoardColumn, b: BoardColumn): Bool {
    match (a) {
        case BoardColumn.Attention => return match (b) {
            case BoardColumn.Attention => true
            case _ => false
        }
        case BoardColumn.Active => return match (b) {
            case BoardColumn.Active => true
            case _ => false
        }
        case BoardColumn.Quiet => return match (b) {
            case BoardColumn.Quiet => true
            case _ => false
        }
        case BoardColumn.Other => return match (b) {
            case BoardColumn.Other => true
            case _ => false
        }
    }
}

/// 两个范围是否相同。
public func scopeIs(a: ScopeChoice, b: ScopeChoice): Bool {
    match (a) {
        case ScopeChoice.Group => return match (b) {
            case ScopeChoice.Group => true
            case _ => false
        }
        case ScopeChoice.One => return match (b) {
            case ScopeChoice.One => true
            case _ => false
        }
    }
}

/// 全部项目。没读到时给**空列表**，不是回落成「一个都没有」的那份空态 ——
/// 调用方靠 `.isEmpty()` 分辨「没读到」和「确实没有」，而真正的空态由
/// `snapshot.value.isNone()` 判断。
public func allProjectsOf(model: AppModel): ArrayList<Project> {
    match (model.snapshot.value) {
        case Some(s) => return s.projects
        case None => return ArrayList<Project>()
    }
}

/// 当前墙钟毫秒。**只在构建入口取一次**并往下传 ——
/// 判据要固定时刻，同一个项目在一次构建里被算两次就可能得到两个答案。
public func nowMs(): Int64 {
    return nowMillis()
}

/// 时刻 → `HH:MM:SS`。侧栏状态条只要时分秒，多一天少一天不影响判读。
public func clockText(ms: Int64): String {
    let secs = (ms / 1000) % 86400
    let h = secs / 3600
    let m = (secs % 3600) / 60
    let s = secs % 60
    return "${pad2(h)}:${pad2(m)}:${pad2(s)}"
}

private func pad2(v: Int64): String {
    return (if (v < 10) { "0${v}" } else { "${v}" })
}
