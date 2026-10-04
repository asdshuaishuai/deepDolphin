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
    /// 侧栏「仓库」组的选中下标。
    ///
    /// ⚠ 它**必须直接绑给 `ListView`**：CUI 的 ListView 点击直接写传入的
    /// `selected`（`selection_widgets.cj` 的 handle），而它的滚动状态特意用
    /// `localState(key)` 持久化以免「a fresh State each frame would reset」——
    /// 选中没做同样保护，因为设计上就假定外部传进来的是**持久实例**。
    /// 传一次性的 `State(0)` 的话，点击写进那个临时实例，下一帧重建就没了：
    /// 侧栏点了不换页，而现场看起来「按钮高亮了但没反应」。
    public let selected = State<Int64>(0)
    /// 侧栏「视图」组的选中下标（0 仪表盘 / 1 看板 / 2 里程碑，-1 = 不高亮）。
    /// 同样必须持久，原因见 `selected`。
    public let viewIndex = State<Int64>(0)
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

    // -------------------------------------------------------------- 破坏性操作确认
    /// 确认框在不在场（根视图上那只 Modal 的 `presented` 绑定）。
    public let confirmOpen = State<Bool>(false)
    /// 挂起待确认的动作。**普通字段而不是 State**：它的每次写入都伴随
    /// `confirmOpen` 的 State 写（开框/关框都会触发整树重建），单独立 State
    /// 只会多出一条「挂起了动作却忘了开关」的分叉路径。
    /// Modal 只在 `presented` 为真时构建内容，读到的必然是挂起的那个动作。
    public var pendingConfirm: Option<PendingConfirm> = None

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
    /// 外观下拉的当前下标。**唯一写入口是设置页的下拉**，
    /// 写入由观察者接到 `applyAppearanceChoice`（保存 + 披露）上。
    public let appearanceIndex = State<Int64>(0)
    /// 上一次外观保存的结果一句话。**空串 = 还没动过**。
    /// ⚠ 不走 `report`：`lastResult` 只画在项目详情页头，设置页上看不见它 ——
    /// 保存结果必须出现在按下那个下拉的地方。
    public let appearanceNote = State<String>("")
    public let appearanceNoteOk = State<Bool>(true)

    public var booted: Bool = false

    /// `DD_SNAP_CLICK` 的一次性闸门：模拟点击**只发一次**。
    ///
    /// `app.run` 的构建闭包每次状态变化都重跑，不挡住的话会每帧写一次
    /// `selected` —— 而 `State` 的 setter 值没变也照样通知，
    /// 于是变成一个永不停歇的导航回环。
    public var snapClickFired: Bool = false

    // ------------------------------------------------- 仪表盘筛选（段 2）
    /// 时间跨度。**状态必须在模型上，不能挂视图**：看板是第二个消费方
    /// （同屏里两个视图必须对「在看什么」说同一句话），各存一份就必然出现
    /// 「仪表盘 1 个 / 看板 3 个」。macOS 端 2026-10 修的正是这个。
    public let dashSpan = State<DashSpan>(DashSpan.All)
    /// 提交类型筛选。**只作用于项目卡的提交结构条**，不改 KPI 数字。
    public let dashCommits = State<DashCommitFilter>(DashCommitFilter.AllCommits)
    /// 范围选择器（WorkBar 左段）的当前项。**必须是持久 State** ——
    /// 控件写进来，下一帧还要读同一个实例才知道现在选的是哪一项。
    public let scopeIndex = State<Int64>(0)

    // -------------------------------------------------------------- 导航
    /// 当前选中的**视图**（侧栏「视图」组）。项目是另一维，见 `selectedProject`。
    public let root = State<RootSection>(RootSection.Dashboard)    /// 当前选中的**项目名**。空串 = 没选。
    ///
    /// ⚠ 为什么与 `root` 分开而不是塞进一个枚举：macOS 端用
    /// `RootSection.project(String)` 一个枚举同时表达两者，本端拆开是因为
    /// CUI 的 `ListView` 用 Int64 索引、`LazyList` 用 Int64 索引，
    /// 用索引当唯一标识比在枚举里塞字符串更直接。
    /// 两组各自的选中下标是 `viewIndex` / `selected`（见各自的注释）。
    public let selectedProject = State<String>("")
    // -------------------------------------------------------------- AI 面板
    /// 主区当前显示哪个 AI 面板。0 = 不显示（走正常路由）。
    ///
    /// ⚠ 不是「开一个窗口」而是**换主区**：CUI 的 `DesktopApp` 只有一扇窗，
    /// 没有 macOS 那个 `Settings` scene / `sheet`。
    /// 所以「AI 助手」「AI 设置」做成主区里的两个视图，
    /// 工具栏按钮来回切。副作用是聊天时不显示仪表盘 ——
    /// 聊天里要看项目现状得先退出去，这是与 macOS 端的**已知差异**，
    /// 如实记在 linux/README.md 里，不假装一致。
    public let aiPane = State<Int64>(0)
    /// AI 对话的完整消息流。`None` = 还没开始。
    public let aiTranscript = State<Option<ArrayList<ChatMessage>>>(None)
    /// 输入框草稿。
    public let aiDraft = State<String>("")
    /// 这一轮跑过哪些工具（人话），给「刚才做了什么」那一行。
    public let aiExecuted = State<ArrayList<String>>(ArrayList<String>())
    /// 这一轮收尾时给的说明（轮次上限之类）。空串 = 没什么要说的。
    public let aiNote = State<String>("")
    /// AI 动作在跑。与引擎动作**共用 `actionBusy` 闸门** ——
    /// 深更新要跑 5 分钟，AI 一轮也可能几十秒，两个闸门会让
    /// 「AI 正在调工具执行深更新」和「用户又点了深更新」撞在一起。
    /// 引擎那边有锁，第二个进程只会一起超时。
    public let aiStatus = State<String>("")
    /// AI 那一轮在跑。**与 `actionBusy` 分开**：闸门可能被「停止」提前放开，
    /// 而「正在跑」这件事本身还要用来决定「停止」按钮显不显示。
    public let aiRunning = State<Bool>(false)
    /// C5 的 AI 结果面板（项目简报 / 群组简报 / 更新后摘要）。空 = 不显示。
    public let aiSheetTitle = State<String>("")
    public let aiSheetBody = State<String>("")
    /// C5 结果面板在跑。
    public let aiSheetBusy = State<Bool>(false)
    public let aiSheetError = State<String>("")

    // ---- 设置页草稿（**不直接写配置**，保存时才落盘）----
    // ⚠ 分草稿与落盘是刻意的：直接写配置的话，用户改到一半还没点保存
    // 就已经生效了，而「保存并测试」这个按钮就失去了意义。
    public let aiProviderIndex = State<Int64>(0)
    public let aiModelIndex = State<Int64>(0)
    public let aiModelManual = State<String>("")
    public let aiKeyDraft = State<String>("")
    public let aiBaseURLDraft = State<String>("")
    public let aiTestResult = State<String>("")
    /// 系统里**已保存**的 API Key 存在吗（只存「在/不在」这个掩码，
    /// 永远不存 key 原文）。
    ///
    /// ⚠ 掩码必须是**模型状态**而不是每次构建去读真值（R4-06）：
    /// 读真值要走 `secret-tool lookup` 子进程（预算 10 秒），钥匙串被锁 /
    /// D-Bus 卡住时一次就冻结界面 10 秒 —— 而设置页的构建闭包每帧都跑。
    /// 真值只在两处读：启动时与保存回包时，都在后台线程
    /// （`refreshKeyPresence`）。
    public let aiKeySavedPresent = State<Bool>(false)
    /// AI 对话流的滚动偏移，接给对话页 `ScrollView` 的 `scrollState`。
    ///
    /// ⚠ 必须是持久 State（与侧栏 `selected` 同一条理由）：控件写进来，
    /// 下一帧还要读同一个实例才知道滚到哪。sendAI 在写入新消息时把它
    /// 顶到一个大值 —— ScrollView 布局期会把偏移钳到「内容高 - 视口高」，
    /// 等价于贴底；之后的滚动由用户说了算（钳制只在偏移越界时发生）。
    public let aiScroll = State<Float32>(0.0)

    // ---- 添加 / 扫描项目面板（功能流 C-05）----
    // actScan / actAddProject 这层写操作曾经**全仓零调用**：侧栏只留一句
    // 指向终端的降级说明（原话不写出 —— 源码扫描判据钉着它）。这里把
    // 面板状态收进模型 ——
    // 草稿不落盘、每次打开就是上次的草稿，与 AI 设置页的 draft 族同款。
    //
    // ⚠ 「换主区」而不是「弹窗」：CUI 的 `DesktopApp` 只有一扇窗（与 `aiPane`
    // 同一条理由，见 `aiPane` 的注释）。打开时顺手关掉 AI 面板 ——
    // 主区同一时刻只有一个场景。
    /// 面板在场。由 `openAddPane` / `closeAddPane` 唯一读写。
    public let addPaneOpen = State<Bool>(false)
    /// 0 = 添加单个项目 / 1 = 批量扫描目录（mac 端 ScanSheet 的 mode 档）。
    public let addMode = State<Int64>(0)
    /// 单项目路径草稿。**路径是这个面板唯一必填的输入**（项目名可空）。
    public let addSinglePath = State<String>("")
    /// 项目名草稿。空 = 引擎从目录名推导。
    public let addSingleName = State<String>("")
    /// 扫描根目录草稿。
    public let scanRoot = State<String>("")
    /// 扫描深度（1…6 层，与 mac 端 Stepper `in 1...6` 同档）。
    public let scanDepth = State<Int64>(2)

    // ---- 启动参数深链（C10）----
    // ⚠ 用**普通字段**而不是 `State<T>`：这两个值只在启动时读一次、
    // 应用一次，不该引起界面重建；而 `State` 的写会通知所有观察者。
    //
    // 为什么挂在模型上而不是 `main()` 的局部变量：`app.run` 的构建闭包
    // **不能捕获可变变量**（仓颉限制），局部 `var` 一进闭包就编译不过。
    public var launchRoute: LaunchRoute = LaunchRoute("", "")
    public var launchPending: Bool = false

    /// 侧栏搜索词。空 = 不过滤。
    public let query = State<String>("")
    /// 范围（WorkBar 左段）。Group = 全局看板，One = 单仓库管控页。
    public let scope = State<ScopeChoice>(ScopeChoice.Group)
    /// 上次刷新完成的时刻（毫秒）。侧栏状态条要显示它。
    public let lastRefreshedMs = State<Int64>(0)
    /// 深链打错字之类的说明。独立于 `problem`，不依赖 `busy`。
    public let routeNotice = State<String>("")

    // ⚠ 引擎位置**可以**晚于建窗再挂（R4-10）：定位要起子进程探活
    // （每个候选一次 `version`，挂住的候选要等超时），放在建窗前就是把
    // 首屏押在子进程身上。字段因此是 var 而不是 let，配套 `attachEngine`。
    public var enginePath: String = ""
    public var engineVia: String = ""
    private var engineProblem: String = ""
    /// 引擎位置挂上了吗。`false` = 还没定位（不是「定位了但没找到」）——
    /// 这两种状态在界面上必须分开（见 syncLabels 与 detail 的预定位卡片）。
    private var engineLocated: Bool = false

    /// 正常路径：模型先建、首帧后再定位（`AppModel()` + `attachEngine`）。
    public init() {
        this.syncLabels()
    }

    /// 夹具 / 判据路径：位置现成就直接挂，语义与挂载后完全一致。
    public init(loc: EngineLocation) {
        this.engineLocated = true
        this.enginePath = loc.path
        this.engineVia = loc.via
        this.engineProblem = loc.problem
        this.syncLabels()
    }

    /// 把定位结果挂上模型。**只挂一次**：重挂会让晚到的失败探测结果
    /// 覆盖一个已经工作着的引擎。挂载本身写的是普通字段，
    /// 但 `syncLabels` 会写 State，界面照常重建。
    public func attachEngine(loc: EngineLocation): Unit {
        if (this.engineLocated) {
            return
        }
        this.engineLocated = true
        this.enginePath = loc.path
        this.engineVia = loc.via
        this.engineProblem = loc.problem
        this.syncLabels()
    }

    /// 引擎定位完了吗（不管找没找到）。没定位完时界面显示「正在定位」，
    /// **不能**显示引擎安装引导 —— 那会把「还没找」说成「没有引擎」。
    public func engineLocatedDone(): Bool {
        return this.engineLocated
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
        if (!this.engineLocated) {
            // 引擎还在定位（定位挪到了首帧后，R4-10）。「还没找」与「找了但没有」
            // 是两句话：这一态只说前者，安装引导留给定位完成之后。
            this.problem.value = ""
            this.emptyHint.value = "正在定位引擎…"
            this.statusText.value = "正在定位引擎…"
            this.canRefresh.value = false
            return
        }
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
    // 「已保存的 key 在不在」只在启动与保存回包各读一次真值（后台线程），
    // 设置页每帧只读掩码 —— 见 `aiKeySavedPresent` 与 `refreshKeyPresence`。
    refreshKeyPresence(app, model)
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
        // ⚠ fire-and-forget 闭包里的异常**没人接**（R4-01）：一线程直接死亡，
        // 下面的 app.post 永远不执行 —— 上面刚置真的 busy 永不复位，
        // 界面永远停在「读取项目群…」，轮询也被 busy 挡住。所以整段兜住，
        // 把原因 post 回界面，保证 busy 必然复位。
        try {
            let statusCall = opStatus(bin)
            let dashCall = opDashboard(bin)
            let msCall = opMilestoneList(bin)
            app.post {
                model.busy.value = false
                applyReads(model, statusCall, dashCall, msCall)
            }
        } catch (e: Exception) {
            let why = e.message
            app.post {
                model.busy.value = false
                model.problem.value = "读取项目群失败：${why}"
                model.refreshLabels()
            }
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
    // journal / docs 同理：它们走的是 `loadProjectDetail` 里的真实子进程调用，
    // 而夹具模式**不起引擎**，所以这两张卡在任何快照里都是空态 ——
    // 布局、换行、口径披露那一行挂在哪儿，全都没有证据。
    match (loadOneFixture(model, dir, "journal.json", PayloadShape.Journal)) {
        case Some(v) =>
            model.journal.value = Some(Journal.from(v))
            model.journalProblem.value = ""
            n += 1
        case None =>
            model.journal.value = None
            model.journalProblem.value = "读不到夹具 ${dir}/journal.json"
    }
    match (loadOneFixture(model, dir, "docs.json", PayloadShape.Docs)) {
        case Some(v) =>
            model.docs.value = Some(DocBundle.from(v))
            model.docsProblem.value = ""
            n += 1
        case None =>
            model.docs.value = None
            model.docsProblem.value = "读不到夹具 ${dir}/docs.json"
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
        // 项目列表变短时把选中下标收回范围里。
        //
        // ⚠ 上界必须用**侧栏真正显示的那份列表**（过了搜索框），
        // 不是 `projects.size`：拿全量数目当上界，搜索生效时下标照样可能
        // 越出可见范围。
        // ⚠ 这个钳位现在**有副作用**了：`selected` 成了侧栏高亮的持久 state，
        // 写它会触发 `goProject` 观察者 → 可能换项目。所以上界得准，
        // 否则一次轮询就能把人从 A 弹到不相干的 B 上。
        let shown = filterProjects(allProjectsOf(model), model.query.value).size
        if (model.selected.value >= shown) {
            model.selected.value = if (shown > 0) { shown - 1 } else { 0 }
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
///
/// `public` 是因为 `main.cj` 的快照点击模拟也要用（后台线程等首帧过去再 post）。
/// 别复制第二份实现：两份 sleep 语义一旦漂移，快照的可复现性就没了。
public func sleepMs(total: Int64): Unit {
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
public func beginAction(model: AppModel, label: String): Bool {
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

public func endAction(model: AppModel, line: String, ok: Bool): Unit {
    model.actionBusy.value = false
    model.actionLabel.value = ""
    model.report(line, ok)
}

// ===========================================================================
// 破坏性操作确认（macOS 端 `DestructiveGuard.swift` 的移植）
//
// 【为什么要有这个】两路调查独立命中同一缺口：里程碑「放弃/删除」直接
// actMilestone(…"drop"/"remove")、「提交」直接 actGit(…"commit")、全局浅/深
// 更新直接 actUpdate —— 全仓确认逻辑零命中。而引擎侧坐实了后果：
//   · `removeMilestone` 直接从列表里剔除并保存 —— **没有备份、没有回收站**，
//     不可逆；
//   · `commit` 走 `git add -A`，提交的是**整个工作区**，不是用户眼前挑的几个
//     文件，「全部」两个字只藏在输入框 placeholder 里；
//   · 批量更新要逐项目改写用户仓库里的 README / AGENTS.md。
//
// 【为什么判定抽成纯函数】直接在每个按钮回调里各写一个 if，就会出现
// 第 N 遍漂移，而「漏了哪一处」没人知道。这里是唯一来源：
// 视图回调只问 `pendConfirm` / `needsConfirmation`。
// ===========================================================================

/// 会改用户数据、且出错代价不对称的动作。
public enum DestructiveAction {
    | RemoveMilestone    // 删除里程碑 —— 引擎直接剔除，无备份，不可逆
    | DropMilestone      // 放弃里程碑 —— 标成 dropped，语义上是「不做了」
    | SetMilestoneStatus // 达成 / 重开 —— 状态可再改，**不**需要确认
    | BulkUpdate         // 批量更新：会把托管区域写进多个仓库的 README/AGENTS.md
    | CommitAll          // 提交全部改动：把工作区里所有未提交内容一次提交掉
}

/// 两个动作档是否相同。仓颉枚举没有 `==`（编译期报 invalid binary operator，
/// 与 `boardColumnIs` / `scopeIs` 同一条理由）。
public func destructiveActionIs(a: DestructiveAction, b: DestructiveAction): Bool {
    match (a) {
        case DestructiveAction.RemoveMilestone => return match (b) {
            case DestructiveAction.RemoveMilestone => true
            case _ => false
        }
        case DestructiveAction.DropMilestone => return match (b) {
            case DestructiveAction.DropMilestone => true
            case _ => false
        }
        case DestructiveAction.SetMilestoneStatus => return match (b) {
            case DestructiveAction.SetMilestoneStatus => true
            case _ => false
        }
        case DestructiveAction.BulkUpdate => return match (b) {
            case DestructiveAction.BulkUpdate => true
            case _ => false
        }
        case DestructiveAction.CommitAll => return match (b) {
            case DestructiveAction.CommitAll => true
            case _ => false
        }
    }
}

/// 需要确认的动作集合。
///
/// ⚠️ `SetMilestoneStatus` **故意不在内**：达成/重开都是可逆的状态切换，
/// 弹确认只会把「确认疲劳」教会用户（点了太多次之后就不看了）——
/// 那比不确认更糟，因为真正的破坏性操作也会被一起忽略。
/// 这条边界不要为了「看起来一致」而扩大（判据里有负控钉着它）。
public func needsConfirmation(a: DestructiveAction): Bool {
    match (a) {
        case DestructiveAction.RemoveMilestone => return true
        case DestructiveAction.DropMilestone => return true
        case DestructiveAction.BulkUpdate => return true
        case DestructiveAction.CommitAll => return true
        case DestructiveAction.SetMilestoneStatus => return false
    }
}

/// 里程碑动作的引擎动词 → 守卫档。认不出的动词落进**免确认**档：
/// 档位判错的方向必须是「少弹框」，不能是「把未知动词当成删除」。
public func milestoneActionKind(op: String): DestructiveAction {
    return (match (op) {
        case "remove" => DestructiveAction.RemoveMilestone
        case "drop" => DestructiveAction.DropMilestone
        case _ => DestructiveAction.SetMilestoneStatus
    })
}

/// 主体（里程碑名 / 项目名）在确认文案里的安全写法。
/// 空名字会让确认框变成「删除里程碑「」？」——用户不知道自己在删什么。
public func safeSubject(raw: String): String {
    let t = raw.trimAscii()
    return (if (t.isEmpty()) { "未命名" } else { t })
}

/// 确认框标题。必须点名**具体对象**，不能只说「确认吗」——
/// 用户要知道自己确认的是哪一个。
public func guardTitle(a: DestructiveAction, subject: String): String {
    return (match (a) {
        case DestructiveAction.RemoveMilestone => "删除里程碑「${subject}」？"
        case DestructiveAction.DropMilestone => "放弃里程碑「${subject}」？"
        case DestructiveAction.BulkUpdate => "更新全部项目？"
        case DestructiveAction.CommitAll => "提交全部改动？"
        case DestructiveAction.SetMilestoneStatus => "确认操作？"
    })
}

/// 确认框正文：**必须说清代价**。
/// 「删除」而不说「不可恢复」，等于让用户以为还能撤销。
public func guardMessage(a: DestructiveAction, subject: String): String {
    return (match (a) {
        // 引擎的 removeMilestone 没有备份、没有回收站 —— 这句是事实陈述，
        // 不是吓唬人的修辞。
        case DestructiveAction.RemoveMilestone =>
            "「${subject}」会被直接删除。引擎不留备份、也没有回收站，删除后无法恢复。"
        case DestructiveAction.DropMilestone =>
            "「${subject}」会被标记为已放弃，日后不再计入进行中的里程碑。之后可以重开，但这次操作本身不会被记录成历史。"
        case DestructiveAction.BulkUpdate =>
            "所有已注册项目的 README / AGENTS.md 等托管区域都会被改写。每个文件在改写前会留备份，但这一步会覆盖多个仓库。"
        case DestructiveAction.CommitAll =>
            "工作区里所有未提交的内容会被合成一次提交，未跟踪文件也会包含在内。提交信息可在之后 amend，但此刻它们会被写进历史。"
        case DestructiveAction.SetMilestoneStatus => "这个操作可以再改回来。"
    })
}

/// 确认按钮的标题。破坏性动作的按钮要说**会发生什么**，不是「确定」——
/// 「确定 / 取消」挨着放的时候，用户得靠位置猜「确定」是确定什么。
public func guardConfirmLabel(a: DestructiveAction): String {
    return (match (a) {
        case DestructiveAction.RemoveMilestone => "删除"
        case DestructiveAction.DropMilestone => "放弃"
        case DestructiveAction.BulkUpdate => "全部更新"
        case DestructiveAction.CommitAll => "全部提交"
        case DestructiveAction.SetMilestoneStatus => "确定"
    })
}

/// 该不该染危险色。可逆的动作不染红：满屏红按钮会稀释「红=危险」这个信号。
/// 批量更新每个文件改写前会留备份（引擎 applyRegions 不变量），可回滚，
/// 所以它**不**进危险档 —— 弹一个红字的「你确定要删东西吗」式对话框，
/// 会把真正的不可逆操作也稀释掉。
public func guardIsDestructiveRole(a: DestructiveAction): Bool {
    return (match (a) {
        case DestructiveAction.RemoveMilestone => true
        case DestructiveAction.DropMilestone => true
        case DestructiveAction.CommitAll => true
        case DestructiveAction.BulkUpdate => false
        case DestructiveAction.SetMilestoneStatus => false
    })
}

/// 更新轨道的人话（按钮标题、确认框标题共用一份词表）。
public func updateTrackLabel(deep: Bool): String {
    return (if (deep) { "深更新" } else { "浅更新" })
}

/// 批量更新的范围描述（mac 端 `DestructiveGuard.bulkUpdateMessage` 同款）。
///
/// ⚠ 批量更新**不该**和「删除里程碑」用同一种确认：它虽然会改写多个仓库，
/// 但每个文件在改写前都会留备份，是可逆的 —— 所以这里只**报范围**
/// （几个项目、哪一轨），让人知道这次会动多少东西。
public func bulkUpdateMessage(projectCount: Int64, deep: Bool): String {
    let n = (if (projectCount > 0) { projectCount } else { 0 })
    if (n == 0) {
        return "当前没有已注册的项目，不会做任何事。"
    }
    let one = (if (n == 1) { "1 个项目" } else { "${n} 个项目" })
    let what = (if (deep) {
        "除浅更新外还会调用 AI 重新生成内容"
    } else {
        "读取 git 历史并改写托管区域（README / AGENTS.md 等）"
    })
    return "将对 ${one} 执行${updateTrackLabel(deep)}：${what}。每个被改写的文件都会先留备份，所以可以回滚。"
}

/// 提交前的工作区规模，驱动确认框里的**具体数字**。
///
/// ⚠ 为什么非要这个：引擎的 `commit` 走 `git add -A` —— 它提交的是
/// **整个工作区**。确认框若只说「要提交了」，用户仍然不知道会连多少东西进历史。
public struct CommitAllScope {
    public let trackedModified: Int64
    public let untracked: Int64
    public let staged: Int64

    public init(trackedModified: Int64, untracked: Int64, staged: Int64) {
        this.trackedModified = trackedModified
        this.untracked = untracked
        this.staged = staged
    }

    /// 会被 `git add -A` 带进这次提交的文件数上界。
    /// 保守取「已改动 + 未跟踪」（暂存里的多半已计入已改动）。
    public func willCommit(): Int64 {
        let sum = this.trackedModified + this.untracked
        return (if (sum > this.staged) { sum } else { this.staged })
    }
}

/// 提交范围的人类可读描述。三态必须**可区分**，不能塌成一句「若干改动」：
/// - 0 个 ⇒ 不该走到确认（没有可提交的东西）
/// - 只有未跟踪 ⇒ 单独说，因为这是最容易出事的一种（误提交 .env/密钥）
/// - 有已跟踪改动 ⇒ 说清数量
public func commitScopeText(s: CommitAllScope): String {
    if (s.willCommit() == 0) {
        return "当前没有待提交的内容"
    }
    let parts = ArrayList<String>()
    if (s.trackedModified > 0) {
        parts.add("${s.trackedModified} 个已改动")
    }
    if (s.untracked > 0) {
        parts.add("${s.untracked} 个未跟踪")
    }
    if (s.staged > 0) {
        parts.add("${s.staged} 个已暂存")
    }
    let list = joinWith(parts, "、")
    if (s.untracked > 0) {
        return "将提交 ${s.willCommit()} 个文件（${list}）。未跟踪文件会首次进入版本历史，其中可能包含本不该提交的内容（如密钥、构建产物）。"
    }
    return "将提交 ${s.willCommit()} 个文件（${list}）。"
}

/// 提交确认框的标题：带上项目名，用户要知道自己确认的是哪个仓库。
public func commitTitle(project: String): String {
    return "在「${safeSubject(project)}」里提交全部改动？"
}

/// 提交确认框正文（带真实数量）。
public func commitMessage(scope: CommitAllScope): String {
    return "${commitScopeText(scope)}提交之后可以用 amend 修改信息，但文件内容已进入历史。"
}

/// 提交范围。引擎只有 `userDirtyCount` / `untrackedCount` 两个口径，
/// 没有「已暂存」——所以那个字段恒 0，**不编造**
/// （mac 端 `DetailViews.commitScope` 同款）；读不出来的 -1 也不许参与计数。
public func commitAllScopeOf(model: AppModel, project: String): CommitAllScope {
    for (p in allProjectsOf(model)) {
        if (p.name == project) {
            let dirty = (if (p.userDirtyCount > 0) { p.userDirtyCount } else { 0 })
            let untracked = (if (p.untrackedCount > 0) { p.untrackedCount } else { 0 })
            return CommitAllScope(dirty, untracked, 0)
        }
    }
    return CommitAllScope(0, 0, 0)
}

/// 一个正在等确认的破坏性动作（挂在模型上，Modal 拿它拼文案）。
public struct PendingConfirm {
    public let action: DestructiveAction
    /// 目标项目：更新（空串 = 全部）/ commit / 里程碑动作的项目名。
    public let project: String
    /// 里程碑名（非里程碑动作为空串）。
    public let name: String
    /// 里程碑动作的引擎动词（done/open/drop/remove；其余为空串）。
    public let op: String
    /// 更新轨道（非更新动作为 false）。
    public let deep: Bool
    /// 提交信息（非 commit 为空串）。
    public let message: String

    public init(action: DestructiveAction, project!: String = "", name!: String = "",
        op!: String = "", deep!: Bool = false, message!: String = "") {
        this.action = action
        this.project = project
        this.name = name
        this.op = op
        this.deep = deep
        this.message = message
    }
}

/// 挂起一次破坏性确认（纯状态，不碰 app —— 判据可以直接驱动）。
///
/// 返回**是否挂起**：破坏性动作 → 写入挂起态并开框，返回 true；
/// 免确认档（达成/重开）→ 什么都不改，返回 false，由调用方当场执行。
public func pendConfirm(model: AppModel, pending: PendingConfirm): Bool {
    if (!needsConfirmation(pending.action)) {
        return false
    }
    model.pendingConfirm = Some(pending)
    model.confirmOpen.value = true
    return true
}

/// 取消：框与挂起动作**一起**清。只关框不清挂起态的话，下次别的按钮开框前
/// 若有残留，确认按钮就会替用户执行上一个动作。
public func cancelConfirm(model: AppModel): Unit {
    model.confirmOpen.value = false
    model.pendingConfirm = None
}

/// 确认框里的「删除 / 放弃 / 全部更新 / 全部提交」按钮。
/// **先取走再执行** —— 深更新要跑几分钟，框留在场上会盖住结果行。
public func runPendingConfirm(app: DesktopApp, model: AppModel): Unit {
    match (takePendingConfirm(model)) {
        case Some(p) => runDestructive(app, model, p)
        case None => ()
    }
}

/// 取走挂起动作并收框（不执行）。拆出来是因为这一半不碰 app ——
/// 无头镜头判据（WidgetTestHost）驱动得了确认路径的状态一半；
/// 执行一半（runDestructive）要真引擎与 DesktopApp，由接线扫描钉住。
public func takePendingConfirm(model: AppModel): Option<PendingConfirm> {
    let p = model.pendingConfirm
    cancelConfirm(model)
    return p
}

/// 真正执行一次动作（确认按钮与免确认直通共用这一份分派）。
public func runDestructive(app: DesktopApp, model: AppModel, p: PendingConfirm): Unit {
    match (p.action) {
        case DestructiveAction.RemoveMilestone => actMilestone(app, model, p.project, p.name, "remove")
        case DestructiveAction.DropMilestone => actMilestone(app, model, p.project, p.name, "drop")
        case DestructiveAction.SetMilestoneStatus => actMilestone(app, model, p.project, p.name, p.op)
        case DestructiveAction.BulkUpdate => actUpdate(app, model, p.project, p.deep)
        case DestructiveAction.CommitAll => actGit(app, model, p.project, "commit", p.message)
    }
}

/// 破坏性按钮回调的**唯一入口**。需要确认 → 挂起并开框；
/// 不需要 → 当场执行。「免确认」由 `needsConfirmation` 唯一裁决，
/// 回调自己不再各写一个 if —— 抄多处的教训见本节头注。
public func requestDestructive(app: DesktopApp, model: AppModel, pending: PendingConfirm): Unit {
    if (pendConfirm(model, pending)) {
        return
    }
    runDestructive(app, model, pending)
}

/// 里程碑行四个按钮（达成/重开/放弃/删除）的统一入口。
/// 达成/重开在这里被 `needsConfirmation` 直通，行为与直连 actMilestone 一致。
public func requestMilestoneAction(app: DesktopApp, model: AppModel, project: String, name: String, op: String): Unit {
    requestDestructive(app, model, PendingConfirm(milestoneActionKind(op), project: project, name: name, op: op))
}

/// 双轨更新按钮（工具栏 / 工作条 / 重新索引）的统一入口。
///
/// **目标是「全部」时必须先过确认**（BulkUpdate）：引擎的批量更新会逐项目
/// 改写托管文档。单项目范围直接执行 —— 与 mac 端 `Model.runUpdate` 的
/// .project 分支同口径：只改一个仓库，且每个文件改写前有备份。
public func requestUpdate(app: DesktopApp, model: AppModel, project: String, deep: Bool): Unit {
    if (project.isEmpty()) {
        requestDestructive(app, model, PendingConfirm(DestructiveAction.BulkUpdate, deep: deep))
        return
    }
    actUpdate(app, model, project, deep)
}

/// 提交按钮的入口（mac 端 `DetailViews` 的 pendingCommit 同款）。
/// 点提交 ≠ 提交：先挂起确认，「全部提交」才真跑。
public func requestCommit(app: DesktopApp, model: AppModel, project: String, message: String): Unit {
    requestDestructive(app, model,
        PendingConfirm(DestructiveAction.CommitAll, project: project, op: "commit", message: message))
}

// ---------------------------------------------------------------------------
// 确认框文案（读挂起动作；没有挂起时给空串 —— 框关着时不参与构建）
// ---------------------------------------------------------------------------

/// 确认框标题。批量更新跟 mac 端一样把轨道写进标题（「全部深更新？」），
/// 提交带仓库名，里程碑点名具体对象。
public func confirmHeading(p: PendingConfirm): String {
    return (match (p.action) {
        case DestructiveAction.BulkUpdate => "全部${updateTrackLabel(p.deep)}？"
        case DestructiveAction.CommitAll => commitTitle(p.project)
        case _ => guardTitle(p.action, safeSubject(p.name))
    })
}

public func confirmHeadingOf(model: AppModel): String {
    return (match (model.pendingConfirm) {
        case Some(p) => confirmHeading(p)
        case None => ""
    })
}

/// 确认框正文。批量更新报范围（有备份，可回滚）、提交报规模（数量 +
/// 未跟踪文件的密钥风险，由模型现场算），里程碑两种直接用守卫层文案。
public func confirmBodyOf(model: AppModel): String {
    return (match (model.pendingConfirm) {
        case Some(p) =>
            (match (p.action) {
                case DestructiveAction.BulkUpdate => bulkUpdateMessage(allProjectsOf(model).size, p.deep)
                case DestructiveAction.CommitAll => commitMessage(commitAllScopeOf(model, p.project))
                case _ => guardMessage(p.action, safeSubject(p.name))
            })
        case None => ""
    })
}

/// 确认按钮的标题。**要说会发生什么**，不是「确定」。
public func confirmButtonLabelOf(model: AppModel): String {
    return (match (model.pendingConfirm) {
        case Some(p) => guardConfirmLabel(p.action)
        case None => "确定"
    })
}

// ===========================================================================
// 写：外观（R2-03 —— 这层实现曾经零 UI 消费，用户根本没法换主题）
// ===========================================================================

/// 应用一次外观选择：记档 + 落盘 + 把结果说在**按下控件的地方**。
///
/// ⚠ **不热切换**。CUI 的 `Theme` 是 `DesktopApp` 的构造参数
/// （vendor `src/core/theme.cj` 标注 Immutable，`DesktopApp` 没有 setTheme），
/// 本进程的框架色改不了 —— 这里只写 XDG 配置，重启后由 `resolveAppearance`
/// 读回来生效。结果文案由 `appearanceApplyNote` 出（成功也写明「重启后生效」）。
///
/// 落盘动作收成参数（`write!`）：真接线传 `saveAppearance`，判据传一个
/// 不碰盘的假写 —— 与 `readAppearanceFrom` 收读函数是同一条纪律。
public func applyAppearanceChoiceBy(
    model: AppModel,
    idx: Int64,
    write!: (DsAppearance) -> String
): Unit {
    let a = appearanceAt(idx)
    model.appearance.value = a
    let (note, ok) = appearanceApplyNote(a, write(a))
    model.appearanceNote.value = note
    model.appearanceNoteOk.value = ok
}

public func applyAppearanceChoice(model: AppModel, idx: Int64): Unit {
    applyAppearanceChoiceBy(model, idx, write: {a => saveAppearance(a)})
}

/// 设置页外观下拉的接线。**返回值必须被持有**：observe 返回的
/// `StateObservation` 是 `Resource`，析构即 close() —— 丢在当场等于
/// 装上又立刻取消（教训见 sidebar.cj 的注释）。
/// 拆出来而不是塞进 mountEffect 闭包，理由同 `installSidebarSelectionObservers`：
/// 能不开窗口就验的规则，绝不因为「它住在闭包里」就变成只能读代码相信。
public func installAppearanceChoiceObserver(model: AppModel): Resource {
    return model.appearanceIndex.observe({_, v => applyAppearanceChoice(model, v)})
}

public func actUpdate(app: DesktopApp, model: AppModel, project: String, deep: Bool): Unit {
    let label = "${updateTrackLabel(deep)} ${project}"
    if (!beginAction(model, label)) {
        return
    }
    let bin = model.enginePath
    spawn {
        let p = opUpdate(bin, project, deep)
        let ok = p.problem.isEmpty()
        let line = if (let Some(v) <- p.json) {
            let u = UpdateOutcome.from(v)
            (if (u.ok) { "✓ " } else { "✗ " }) + label + "：" + u.summaryLine()
        } else {
            "✗ " + label + "：" + p.problem
        }
        app.post {
            endAction(model, line, ok)
            // 写操作改变了事实，必须重读。放在写之后而不是之前，
            // 否则读到的还是旧状态。
            requestRefresh(app, model)
        }
        // 长任务结束发系统通知：深更新要跑 5 分钟，
        // 那期间用户早就不在窗口前了 —— 不发通知等于
        // 「点了就没下文」。
        // ⚠ 通知**在后台线程发**（R4-08）：notify-send 是一次子进程调用
        // （预算 10 秒），放在 app.post 里就是把 UI 线程冻住那么久。
        // ⚠ 通知失败**不弹到界面上**：任务本身已经成功，
        // 在结果行旁边再报一句「发通知失败」会把它盖掉。
        // 失败只在这一处 println 之外静默，
        // 设置页里另有「本机没有 notify-send」的显式说明。
        let notice = notifyUser("deepDolphin",
            updateFinishedNotice(updateTrackLabel(deep), project, ok,
                if (p.json.isSome()) { "" } else { "（" + p.problem + "）" }))
        if (!notice.isEmpty()) {
            println("deepdolphin: " + notice)
        }
    }
}

public func actUpdateAll(app: DesktopApp, model: AppModel, deep: Bool): Unit {
    let label = "${updateTrackLabel(deep)} 全部项目"
    if (!beginAction(model, label)) {
        return
    }
    let bin = model.enginePath
    spawn {
        let p = opUpdateAll(bin, deep)
        let ok = p.problem.isEmpty()
        let line = if (let Some(v) <- p.json) {
            describeBulkResult(v)
        } else {
            "✗ " + label + "：" + p.problem
        }
        app.post {
            endAction(model, line, ok)
            requestRefresh(app, model)
        }
        // 通知在后台线程发（R4-08，理由同 actUpdate）。
        let notice = notifyUser("deepDolphin",
            updateFinishedNotice(if (deep) { "深更新" } else { "浅更新" }, "", ok, line))
        if (!notice.isEmpty()) {
            println("deepdolphin: " + notice)
        }
    }
}

/// 批量结果的一行摘要。
///
/// 逐项目成败必须**分得开**：只报「成功 3 个失败 3 个」而不说是哪三个，
/// 用户只能自己一个个点开找 —— 而失败的往往正是他在乎的那几个。
///
/// 引擎 `update --json` 有**两种合法形状**（contract-check.sh:74 注明两种都要认，
/// 引擎侧唯一出口是 `multiProjectJson`）：
///   · 多项目 / 零项目：聚合信封 `{results, count, succeeded, failed}`；
///   · 单项目：直返逐仓结果 `{ok, docs…}`（不再包信封）。
/// 旧实现读 `projects` —— 两种形状都不认，≥2 项目时结果行恒为
/// 「引擎没有返回逐项目结果」，把引擎确实返回的成败名单整个扔掉（R1-01）。
public func describeBulkResult(v: JsonValue): String {
    let list = Json.arrAt(v, "results")
    if (!list.isEmpty() || Json.has(v, "results")) {
        var okCount: Int64 = 0
        let failed = ArrayList<String>()
        for (item in list) {
            // 成功项是 updateResultToJson 的形状（有 project + ok）；
            // 失败项是 DgError 桩 `{code, message}` —— 没有 ok、没有 error、
            // 也没有 project 键（实测：项目名在 message 里）。
            // 判定口径与引擎 `hasErrorOrCode` 一致：没有结果键 = 失败。
            let name = Json.strAt(item, "project", Json.strAt(item, "name", ""))
            if (Json.has(item, "ok") && Json.boolAt(item, "ok", false)) {
                okCount += 1
                continue
            }
            var why = Json.strAt(item, "message", "")
            if (why.isEmpty()) {
                why = Json.strAt(item, "error", "")
            }
            if (why.isEmpty()) {
                why = Json.strAt(item, "code", "")
            }
            // 失败桩没有 project 键，名字在 message 里（chainError 的上下文），
            // 空名字就不要再包一层空括号。
            if (why.isEmpty()) {
                failed.add(name)
            } else if (name.isEmpty()) {
                failed.add(why)
            } else {
                failed.add("${name}（${why}）")
            }
        }
        if (failed.isEmpty()) {
            return "全部 ${okCount} 个项目执行成功"
        }
        return "已注册 ${list.size} 个，成功 ${okCount} 个，失败 ${failed.size} 个：" +
            "${joinAll(failed.toArray(), "、")}"
    }
    if (Json.has(v, "ok")) {
        // 单项目逐仓形状：与 actUpdate 同一条读法，项目名取载荷里的。
        let u = UpdateOutcome.from(v)
        let who = if (u.project.isEmpty()) { "1 个项目" } else { u.project }
        return (if (u.ok) { "✓ " } else { "✗ " }) + "${who}：" + u.summaryLine()
    }
    // 单项目的失败桩也是裸的 `{code, message}`（引擎 multiProjectJson 对
    // 单元素原样打印）—— 它没有 ok 键，上面接不住，在这里如实报失败。
    let code = Json.strAt(v, "code", "")
    let message = Json.strAt(v, "message", "")
    if (!code.isEmpty() || !message.isEmpty()) {
        let why = if (message.isEmpty()) { code } else { message }
        return "✗ 更新失败：${why}"
    }
    return "引擎没有返回逐项目结果（形状：${joinAll(Json.objKeys(v), "、")}）"
}

/// 写操作载荷的**结果键**判定。动作系（done/open/drop）恒发 `applied`、
/// remove 恒发 `removed`、add 恒发 `created`（引擎 cli.cj 各自的 --json 出口）；
/// 错误桩 `{error:true,code,message}` 这些键一个都没有。
/// 一个结果键都没有 → `None`，调用方必须按**失败**处理 ——
/// 缺省当成功就是在替引擎说谎（R1-02 实测：错误桩曾被渲染成「✓ 标记达成」）。
public func writeVerdictOf(v: JsonValue): Option<Bool> {
    if (Json.has(v, "applied")) {
        return Some(Json.boolAt(v, "applied", false))
    }
    if (Json.has(v, "ok")) {
        return Some(Json.boolAt(v, "ok", false))
    }
    if (Json.has(v, "removed")) {
        return Some(Json.boolAt(v, "removed", false))
    }
    if (Json.has(v, "created")) {
        return Some(Json.boolAt(v, "created", false))
    }
    return None
}

/// 里程碑动作结果的一行与成败。**纯函数**，判据直接喂载荷。
///
/// ⚠ `status` 用安全读取（R4-05）：载荷里的 `status` 若不是字符串，
/// `asStr(s).getOrThrow()` 会抛穿 app.post —— 拆卸期没人接，应用直接死。
public func milestoneResultOf(label: String, v: JsonValue, problem: String): (String, Bool) {
    let applied = (match (writeVerdictOf(v)) {
        case Some(b) => b
        case None => false
    })
    var line = (if (applied) { "✓ " } else { "✗ " }) + label
    if (let Some(s) <- Json.strAtOpt(v, "status")) {
        line = "${line} → ${s}"
    }
    if (!problem.isEmpty()) {
        line = "${line}：${problem}"
    }
    // applied:false 且退出码 0 也算失败（引擎明说：同名 tag 规则把写入压回了，
    // 「实际生效状态」不是请求的状态）。结果行与红 pill 必须说同一句话。
    return (line, applied && problem.isEmpty())
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
            // 渲染规则收在 milestoneResultOf（纯函数，判据直接喂载荷）：
            // ⚠ 错误桩 {error:true,code,message} 没有 applied 键 —— 旧代码
            // 缺省当 true，把「未找到里程碑」渲染成「✓ 标记达成」，
            // 与详情页的「未完成」红 pill 并排自相矛盾（R1-02 实测）。
            var line: String
            var ok: Bool
            if (let Some(v) <- p.json) {
                let (l, o) = milestoneResultOf(label, v, p.problem)
                line = l
                ok = o
            } else {
                line = "✗ " + label + "：" + p.problem
                ok = false
            }
            endAction(model, line, ok)
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
            // 与 actMilestone 同一条判定（writeVerdictOf：created 键在才算成功，
            // 错误桩没有结果键，按失败渲染）。
            var line: String
            var ok: Bool
            if (let Some(v) <- p.json) {
                let (l, o) = milestoneResultOf(label, v, p.problem)
                line = l
                ok = o
            } else {
                line = "✗ " + label + "：" + p.problem
                ok = false
            }
            endAction(model, line, ok)
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
// 写：项目注册（功能流 C-05）
//
// actScan / actAddProject 这层写操作曾经**全仓零调用**：引擎侧 `scan` / `add`
// 俱全，本端侧栏却只留一句指向终端的降级说明，理由是「CUI 没有目录选择器」。
// mac 基准的 ScanSheet 本就是 TextField + 校验表单（单项目 add / 目录批量
// scan + 深度 1-6 + ScanCoverage 披露），表单不需要目录选择器 ——
// 新装用户第一跑就要开终端，是入门路径上最硬的一道墙。
//
// 判定全部抽成**纯函数**（classify 由调用方注入，判据不碰磁盘）：
// 视图只摆控件，分派只问 `addPaneIntentOf`。
// ===========================================================================

/// 路径在磁盘上是什么。**三态而不是 Bool**（mac 端 `PathInput.PathKind`
/// 同一条理由）：有了 Bool 就分不出「不存在」和「存在但是个文件」，
/// 两种完全不同的错误被压成同一句「不是文件夹」，用户拿它去排查方向就错了。
public enum PathKind {
    // ⚠ case 名带前缀：裸的 `File` 会与 std.fs 的 `File` 类在包作用域撞名
    //（与 EmptyReason 不能占 `None` 同一条纪律）。
    | PathMissing
    | PathFile
    | PathDirectory
}

/// 真实磁盘三态。**这是 classify 的唯一真实现**，判据注入假 classify 时不经过它。
///
/// ⚠ `FileInfo` 的构造器遇到 stat 失败是**抛异常**不是返回错误码
/// （engine.cj `isRegularFile` 同一条纪律）—— 不兜住的话，一个权限不足的
/// 路径就能把构建闭包炸穿。
public func classifyPathKind(path: String): PathKind {
    if (path.isEmpty()) {
        return PathKind.PathMissing
    }
    let p = Path(path)
    if (!exists(p)) {
        return PathKind.PathMissing
    }
    try {
        return (if (FileInfo(p).isDirectory()) { PathKind.PathDirectory } else { PathKind.PathFile })
    } catch (e: Exception) {
        return PathKind.PathMissing
    }
}

/// 用户给的路径整理之后能不能直接发给引擎，以及不能的话为什么。
/// `problem` 空串 = 可用。**必须说清楚**：用户改哪个字段、改成什么样，全靠这句话。
public struct PreparedPath {
    public let path: String
    public let problem: String

    public init(path: String, problem: String) {
        this.path = path
        this.problem = problem
    }

    public func isUsable(): Bool {
        return this.path.isEmpty() == false
    }
}

/// 把用户输入（文本框草稿）整理成能发给引擎的路径。**纯函数**。
///
/// 引擎做什么、不做什么（mac 端 `PathInput.prepare` 的实测表，2026-10-01）：
/// `~/sub` 引擎自己会展开；`"  /abs  "`（首尾空格）直接失败；
/// `rel/path` 对**引擎子进程的 CWD** 解析 —— 那个目录用户看不见也改不了。
/// 所以客户端真正要负责的只有两件：**去掉首尾空白**、**拒绝相对路径**。
/// `~` 和尾斜杠语义交给引擎，不重复实现第二套规则。
public func preparePathInput(raw: String): PreparedPath {
    let s = raw.trimAscii()
    if (s.isEmpty()) {
        return PreparedPath("", "路径为空")
    }
    if (!s.startsWith("/") && !s.startsWith("~")) {
        return PreparedPath("", "「${s}」是相对路径 —— 引擎会拿它对着一个你看不见的内部目录去解析。请填以 / 开头的绝对路径。")
    }
    if (s == "~" || s == "~/") {
        return PreparedPath("", "「~」是家目录本身。请填一个具体的项目目录。")
    }
    // 尾斜杠引擎会消解，这里顺手收掉，免得日志里出现 `//`。
    var out = s
    while (out.size > 1 && out.endsWith("/")) {
        out = out[..out.size - 1]
    }
    return PreparedPath(out, "")
}

/// 校验一个「扫描根 / 添加目标」：必须是**已存在的文件夹**。
///
/// 引擎的 scan 收的是根目录；给它一个文件会得到 `found: 0` 的「正常」结果 ——
/// 看起来像「这个目录里没有 git 仓库」，而真相是「你给的根本不是目录」。
/// 先在这里拦下来（mac 端 `validateScanRoot` 同一条规则）。
public func validateScanRoot(raw: String, classify: (String) -> PathKind): PreparedPath {
    let p = preparePathInput(raw)
    if (!p.isUsable()) {
        return p
    }
    match (classify(p.path)) {
        case PathKind.PathDirectory => return p
        case PathKind.PathFile =>
            return PreparedPath("", "「${p.path}」是个文件。请填一个文件夹。")
        case PathKind.PathMissing =>
            return PreparedPath("", "「${p.path}」不存在。请确认目录名后再填绝对路径。")
    }
}

/// 路径框下方的**实时**判定行。空框时一声不吭（mac 端 `currentProblem`
/// 同一口径：空不算错，提交时再拦），填了东西才开口。
/// classify 是一次 stat，敲一个字一次 —— 与「填错了还能点提交、
/// 点了才看到一句看不懂的错」相比，是便宜的那边。
public func livePathProblem(raw: String): String {
    let s = raw.trimAscii()
    if (s.isEmpty()) {
        return ""
    }
    return validateScanRoot(s, classifyPathKind).problem
}

/// 扫描深度档。Stepper 已经钳了，这里兜底：参数化调用（快照/深链）绕过控件时
/// 也不许把 `--depth 0` 递给引擎。
public func clampScanDepth(v: Int64): Int64 {
    if (v < 1) {
        return 1
    }
    if (v > 6) {
        return 6
    }
    return v
}

// ---------------------------------------------------------------------------
// 扫描覆盖度披露（mac 端 ScanCoverage.swift 的移植）
//
// 「没看完」有三种成因，引擎全都发了出来（引擎侧 #179 / #197）：
//   · truncated   —— 撞到目录上限
//   · depthCapped —— 撞到 --depth 上限且下面还有目录没看
//   · unreadable  —— 有目录读不出来
// 三种处置方式不同：加深度 / 分根扫描 / 查权限。合并成一句「没扫完」
// 等于让用户自己猜。`None` 表示「这个键没有」—— 与「明确说是 false」
// 是两件事，不得合并。
// ---------------------------------------------------------------------------

public struct ScanCoverageInput {
    public let found: Int64
    public let added: Int64
    public let existing: Int64
    public let truncated: Option<Bool>
    public let depthCapped: Option<Bool>
    /// 读不出来的目录数（引擎发的是数组，这里收**个数**）。
    public let unreadable: Option<Int64>

    public init(
        found: Int64,
        added: Int64,
        existing: Int64,
        truncated!: Option<Bool> = None,
        depthCapped!: Option<Bool> = None,
        unreadable!: Option<Int64> = None
    ) {
        this.found = found
        this.added = added
        this.existing = existing
        this.truncated = truncated
        this.depthCapped = depthCapped
        this.unreadable = unreadable
    }
}

/// 从引擎 `scan --json` 的载荷里读覆盖情况（引擎 `scanResultJson`：
/// found/added/existing 恒发，truncated/depthCapped 恒发，unreadable 恒发数组）。
/// 读不到的键一律 None —— 旧引擎不发这些键时**不编造**。
public func scanCoverageFrom(v: JsonValue): ScanCoverageInput {
    let truncated: Option<Bool> = (if (Json.has(v, "truncated")) {
        Some(Json.boolAt(v, "truncated", false))
    } else {
        None
    })
    let depthCapped: Option<Bool> = (if (Json.has(v, "depthCapped")) {
        Some(Json.boolAt(v, "depthCapped", false))
    } else {
        None
    })
    let unreadable: Option<Int64> = (if (Json.has(v, "unreadable")) {
        Some(Json.arrAt(v, "unreadable").size)
    } else {
        None
    })
    return ScanCoverageInput(
        Json.intAt(v, "found", 0),
        Json.intAt(v, "added", 0),
        Json.intAt(v, "existing", 0),
        truncated: truncated,
        depthCapped: depthCapped,
        unreadable: unreadable
    )
}

/// 该在界面上附加的那句披露。没有要说的事返回 `None`（**不返回空串** ——
/// 空串会被拼成「…… 」这种看起来像残缺的话）。
public func scanCoverageNote(c: ScanCoverageInput): Option<String> {
    let why = ArrayList<String>()
    match (c.depthCapped) {
        case Some(v) => if (v) { why.add("撞到扫描深度上限，下面还有目录没看") }
        case None => ()
    }
    match (c.truncated) {
        case Some(v) => if (v) { why.add("撞到目录数量上限") }
        case None => ()
    }
    match (c.unreadable) {
        case Some(n) =>
            if (n > 0) {
                why.add("${n} 个目录读不出来（无权限或 I/O 错误）")
            }
        case None => ()
    }
    if (why.isEmpty()) {
        return None
    }
    // 「没看完」和「没有」是两个结论，必须在**同一句**里说清 ——
    // 只说「该目录树里没有 git 仓库」，等于替用户断言了一个引擎没有验证过的结论。
    if (c.found == 0) {
        return Some("本次未扫完（${joinAll(why.toArray(), "，")}）—— 上面「共发现 0 个」只代表已访问的那部分里没有，不是这棵树里没有")
    }
    return Some("本次未扫完（${joinAll(why.toArray(), "，")}）—— 上面列出的不是全部")
}

/// 新增 / 跳过计数的人话句。**披露分母**：只说「新增 0 个」会被读成
/// 「扫过了但没有仓库」，而「扫了 120 个目录一个都没有」是完全不同的两件事。
public func scanResultLine(c: ScanCoverageInput): String {
    var line = "新增 ${c.added} 个 / 共发现 ${c.found} 个"
    if (c.existing > 0) {
        line += "（已存在 ${c.existing} 个跳过）"
    }
    // 「该目录树里没有 git 仓库」**只在真的扫完时才许说**；
    // 「没扫完」和「没有」也不许并排出现 —— 那两句会互相拆台，
    // note 自己会把「只代表已访问的那部分里没有」说清楚。
    if (c.found == 0 && scanCoverageNote(c).isNone()) {
        line += " —— 该目录树里没有 git 仓库"
    }
    return line
}

/// scan 载荷 → 一行结果与成败。**纯函数**，判据直接喂载荷。
///
/// 成功载荷恒发 `found`（引擎 cli.cj `scanResultJson`）；错误桩
/// `{error:true,code,message}` 这些键一个都没有 → 按**失败**渲染 ——
/// 缺省当成功就是在替引擎说谎（与 milestoneResultOf 同一条纪律，R1-02）。
public func scanResultOf(label: String, v: JsonValue, problem: String): (String, Bool) {
    if (!Json.has(v, "found") && !Json.has(v, "added") && !Json.has(v, "candidates")) {
        return ("✗ ${label}：${engineStubWhy(v, "载荷没有 found/added 结果键")}", false)
    }
    let cov = scanCoverageFrom(v)
    var line = "✓ ${label}：${scanResultLine(cov)}"
    match (scanCoverageNote(cov)) {
        case Some(n) => line = "${line}。${n}"
        case None => ()
    }
    if (!problem.isEmpty()) {
        line = "${line}（${problem}）"
    }
    return (line, problem.isEmpty())
}

/// add 载荷 → 一行结果与成败。成功载荷是注册表条目（引擎 registry.cj
/// `ProjectEntry.toJson`：name/path 恒发）；错误桩没有这些键 → 失败。
/// 「已存在」的重复注册引擎也是 rc=0 原样返回条目，条目在场就按成功说话。
public func addProjectResultOf(label: String, v: JsonValue, problem: String): (String, Bool) {
    let name = Json.strAt(v, "name", "")
    let path = Json.strAt(v, "path", "")
    if (name.isEmpty() && path.isEmpty()) {
        return ("✗ ${label}：${engineStubWhy(v, "载荷没有 name/path 结果键")}", false)
    }
    var line = "✓ ${label} → ${name}（${path}）"
    if (!problem.isEmpty()) {
        line = "${line} ${problem}"
    }
    return (line, problem.isEmpty())
}

/// 错误桩的人话原因。message 优先，code 次之，都没有用调用方的兜底句。
private func engineStubWhy(v: JsonValue, fallback: String): String {
    let why = Json.strAt(v, "message", "")
    if (!why.isEmpty()) {
        return why
    }
    let code = Json.strAt(v, "code", "")
    if (!code.isEmpty()) {
        return code
    }
    return fallback
}

// ---------------------------------------------------------------------------
// 面板的开 / 关 / 提交
// ---------------------------------------------------------------------------

/// 「添加 / 扫描项目」面板的**唯一开入口**（侧栏按钮 / 空态按钮 / 快照开关
/// 都走它）。打开时关掉 AI 面板 —— 主区同一时刻只有一个场景。
public func openAddPane(model: AppModel): Unit {
    model.aiPane.value = 0
    model.addPaneOpen.value = true
}

public func closeAddPane(model: AppModel): Unit {
    model.addPaneOpen.value = false
}

/// 面板的模式档名。视图与判据共用一份词表。
public func addModeChoices(): Array<String> {
    return ["添加单个项目", "批量扫描目录"]
}

/// 面板的提交分派判定。**纯函数**（classify 注入）：判据不开窗、不碰磁盘，
/// 就能验「什么草稿会派出什么动作」。
public enum AddPaneIntent {
    | AddSingle(String, String) // 路径, 项目名（可空）
    | ScanRoot(String, Int64)   // 根目录, 深度
    | Blocked(String)           // 校验失败的原因
}

public func addPaneIntentOf(model: AppModel, classify: (String) -> PathKind): AddPaneIntent {
    if (model.addMode.value == 1) {
        let p = validateScanRoot(model.scanRoot.value, classify)
        if (!p.isUsable()) {
            return AddPaneIntent.Blocked(p.problem)
        }
        return AddPaneIntent.ScanRoot(p.path, clampScanDepth(model.scanDepth.value))
    }
    let p = validateScanRoot(model.addSinglePath.value, classify)
    if (!p.isUsable()) {
        return AddPaneIntent.Blocked(p.problem)
    }
    return AddPaneIntent.AddSingle(p.path, model.addSingleName.value.trimAscii())
}

/// 面板提交按钮的入口。校验失败**不关面板**，原因经 `report` 写进
/// 结果区 —— 与其它写操作同一块披露面。
public func submitAddPane(app: DesktopApp, model: AppModel): Unit {
    match (addPaneIntentOf(model, classifyPathKind)) {
        case AddPaneIntent.Blocked(why) => model.report("✗ ${why}", false)
        case AddPaneIntent.AddSingle(path, name) => actAddProject(app, model, path, name)
        case AddPaneIntent.ScanRoot(root, depth) => actScan(app, model, root, depth)
    }
}

public func actScan(app: DesktopApp, model: AppModel, root: String, depth: Int64): Unit {
    let label = "扫描 ${root}"
    if (!beginAction(model, label)) {
        return
    }
    let bin = model.enginePath
    spawn {
        let p = opScan(bin, root, depth)
        app.post {
            // 渲染收在 scanResultOf（纯函数，判据直接喂载荷）：新增/跳过计数、
            // 覆盖度披露、错误桩按失败渲染 —— 结果行必须能独立成立，
            // 「✓ 扫描 /x」这种没有数字的话说了等于没说。
            var line: String
            var ok: Bool
            if (let Some(v) <- p.json) {
                let (l, o) = scanResultOf(label, v, p.problem)
                line = l
                ok = o
            } else {
                line = "✗ " + label + "：" + p.problem
                ok = false
            }
            endAction(model, line, ok)
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
            // 与 actScan 同一条判定：条目在场才算成功（addProjectResultOf）。
            var line: String
            var ok: Bool
            if (let Some(v) <- p.json) {
                let (l, o) = addProjectResultOf(label, v, p.problem)
                line = l
                ok = o
            } else {
                line = "✗ " + label + "：" + p.problem
                ok = false
            }
            endAction(model, line, ok)
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
        // ⚠ 指到**应用内的入口**，不再让新用户去开终端（功能流 C-05：
        // 那句话曾经是入门路径上最硬的一道墙）。侧栏底部就有那只按钮。
        case EmptyReason.NoProjects => return "没有已注册项目。点下方「添加 / 扫描项目」注册。"
        case EmptyReason.NoMatch => return "没有匹配「该搜索词」的${noun}。"
        case EmptyReason.NoReason => return ""
    }
}

// ~~视图行 / 仓库行共用一个连续序号的那套行号模型~~ —— 已删
// （`SIDEBAR_VIEW_ROWS` / `sidebarRowCount` / `viewRowAt` / `projectRowAt` /
// `goRow`，以及它们配套的 `selectedRow`）。
//
// 侧栏早就改成**两个独立的 ListView**（`dd-view-list` + `dd-proj-list`），
// 与 macOS 端一致，所以「视图行与仓库行共用一个下标」这个前提已经不成立了。
// 留着它有两个实际代价：
//   1. 它是**第二个能写路由的地方** —— 这正是它自己注释里警告的那个事故
//      （「别在别处直接写 root / selectedProject」），而它自己就在别处写着；
//   2. 它自称「导航的唯一写入口」，而真正在用的入口叫 `goView` / `openProject`
//      —— 下一个读代码的人会照着注释去调一个没人调的函数。
// 判据里也没有一条用到它（全仓无调用者），删掉不影响任何已验证行为。

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
