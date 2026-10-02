// Model.swift — 应用状态、数据编排与系统集成（通知 / 开机自启）。
import Foundation
import AppKit
import UserNotifications
import ServiceManagement

// MARK: - 通知

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    /// 点击通知的回调（由 AppDelegate 注入：打开面板）
    var onOpenPanel: (() -> Void)?

    func setUp() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // 通知动作：打开面板
        let openAction = UNNotificationAction(identifier: "OPEN_PANEL", title: "打开面板")
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "DIGEST", actions: [openAction], intentIdentifiers: []),
        ])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "OPEN_PANEL" || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in onOpenPanel?() }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = "DIGEST"
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - 开机自启（SMAppService，macOS 13+）

@available(macOS 13.0, *)
final class LoginItem {
    static let shared = LoginItem()

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // ⚠️ 原来只 NSLog，Toggle 仍停在用户点的那一侧 ——
            // 注册/注销会失败（沙箱策略、用户拒绝、未签名），
            // 而「开关显示自己知道是假的状态」正是这一族缺陷。
            // 不抛给 UI 也不回滚，用户只能靠重启去发现它没生效。
            NSLog("deepgit: 登录项设置失败 \(error)")
        }
        // 真相只来自系统：请求可能失败，也可能「请求成功但系统没照做」。
        // 判定在 LoginItemOutcome（纯函数、可被 client-check 直接编译测试）。
        let actual = isEnabled
        if let note = LoginItemOutcome.mismatchNote(requested: enabled, actualEnabled: actual) {
            NSLog("deepgit: \(note)")
            onLoginItemMismatch?(LoginItemOutcome.displayedState(requested: enabled, actualEnabled: actual), note)
        } else {
            onLoginItemMismatch?(actual, nil)
        }
    }

    /// 设置失败或系统没照做时回调（显示值 + 说明）。
    /// 回调是可选的：没有订阅者时（无 UI 场景）静默。
    var onLoginItemMismatch: ((Bool, String?) -> Void)?
}

// MARK: - 导航

// ⚠️ `RootSection` 已移到 Route.swift（纯函数层）。
// 它是路由的**唯一载体**，而路由规则必须能被 ClientCheck 单独编译断言 ——
// 放在这个 1000 行的文件里，判据就得连带编译整个 AppModel。

// MARK: - 应用状态

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // 面板数据
    @Published var projects: [ProjectStatus] = []
    @Published var summary: EngineSummary?
    @Published var dashboard: Dashboard?
    @Published var milestones: [MilestoneItem] = []
    @Published var projectDetails: [String: ProjectStatus] = [:]

    /// 待确认的批量更新。nil = 没在等确认。
    ///
    /// ⚠️ 为什么放在 Model 而不是视图的 `@State`：
    /// 菜单栏「全部浅更新」在 `DeepGitApp` 的 **`.commands` 修饰器**里——
    /// 那是 `CommandMenu`，**不是 View**，挂不上 `.confirmationDialog`。
    /// 所以待确认状态必须有一个跨视图的落脚点，由主面板 `DeepGitPanel` 渲染对话框。
    /// 同一动作在 `BarView`（菜单栏弹窗）也有入口，那里用自己的 `@State` 即可。
    @Published var pendingBulkUpdate: DSSyncTrack?

    /// 待确认的批量更新。nil = 没在等确认。
    ///
    /// ⚠️ 为什么放在 Model 而不是视图的 `@State`：
    /// 菜单栏「全部浅更新」在 `DeepGitApp` 的 **`.commands` 修饰器**里——
    /// 那是 `CommandMenu`，**不是 View**，挂不上 `.confirmationDialog`。
    /// 所以待确认状态必须有一个跨视图的落脚点，由主面板 `DeepGitPanel` 渲染对话框。
    /// 同一动作在 `BarView`（菜单栏弹窗）也有入口，那里用自己的 `@State` 即可。

    @Published var projectDocs: [String: [DocFile]] = [:]
    /// 每个项目的文档加载结果。理由同 `projectLoadErrors`（见 loadDocs 的注释）。
    @Published private(set) var docsStates: [String: LoadState] = [:]
    @Published var lastGitOpOutput: (ok: Bool, text: String)?

    // UI 状态
    /// 当前主区。**只由 `go(_:)` 写**（见下）——
    /// 原来是 9 处直接赋值，于是「跳到一个不存在的项目」也照样跳，
    /// 详情页再用一个永远不结束的 `ProgressView("加载 X …")` 把它兜住。
    @Published private(set) var selection: RootSection? = .dashboard {
        didSet { NSLog("deepgit-bar: selection → \(String(describing: selection))") }
    }
    @Published var isLoading = false
    /// 仪表盘 + 看板**共用**的那份筛选。
    ///
    /// ⚠️ 为什么放在这里而不是 `DashboardView` 的 `@State`：
    ///   · `@State` 属于视图，视图重建即丢失 —— 切到看板再切回来，
    ///     筛选会悄悄弹回「全量」，用户会以为筛选失灵；
    ///   · 看板是第二个消费方。两个视图各存一份，就会在同一块屏幕上
    ///     对「我现在在看什么」给出两个答案（实测：仪表盘筛到 1 个，看板还是 3 个）。
    /// 判定在 `DashboardScope.swift`（纯函数，可单测）；这里只存值。
    @Published var dashFilter = DashFilter()
    @Published var lastError: String?
    @Published var engineFound = true
    @Published var lastRefreshed: Date?
    @Published var busyProject: String?
    @Published var busyAll = false
    @Published var showAISettings = false
    /// 项目列表**成功加载过**至少一次。
    ///
    /// ⚠️ 不能用 `projects.isEmpty` 代替：真的一个项目都没注册的用户，
    /// 数组也是空的 —— 拿它当「还没加载」会让 Router 永远不敢说「找不到项目」，
    /// 拿它当「加载完了」又会让启动瞬间的空数组被判成「项目群是空的」。
    @Published private(set) var hasLoadedProjectsOnce = false
    /// 深链指向的项目不在列表里 —— 一句**说明**，不是错误。
    ///
    /// ⚠️ 刻意不写进 `lastError`：`runRefreshAll` 里有
    /// `if lastError != nil { isLoading = false; return }` ——
    /// 那是「刷新失败了，别再等 dashboard/milestones」的短路。
    /// 用它报「深链打错字」会让**一次打错的深链掐断整个启动刷新**，
    /// 症状是仪表盘一片空白，比原问题更难查。
    /// 「刷新失败」与「你要去的那个地方不存在」是两件事，各有各的字段。
    @Published private(set) var routeNotice: String?

    /// 每个项目**自己的**加载失败原因。nil = 没失败过。
    ///
    /// ⚠️ 原来只有全局 `lastError`：详情页读不到时它会被设上，
    /// 但详情页自己只看 `project == nil` 于是继续转圈 ——
    /// 用户同时看到一条错误横幅和一个永不停歇的「加载中」。
    @Published private(set) var projectLoadErrors: [String: String] = [:]

    /// 仪表盘 / 里程碑各自的加载结果。
    ///
    /// ⚠️ 不能共用 `lastError`：那个是**全局**的（git 操作失败、深链打错字、
    /// 扫描失败都会写它），拿它判断「仪表盘读不出来了吗」会把别的操作的错误
    /// 算到仪表盘头上。见 LoadState.swift。
    @Published private(set) var dashboardState: LoadState = .idle
    @Published private(set) var milestonesState: LoadState = .idle

    /// 启动参数解析出的路由意图。**解析一次**，之后只读。
    var launchIntent = LaunchIntent()

    /// 深链想去、但项目列表当时还没加载完 —— 加载完再判一次。
    private var pendingRoute: RootSection?

    private var timer: Timer?
    private var notifiedKeys = Set<String>()
    var autoTimer: Timer?
    /// 首轮延迟用的**一次性** timer。必须存下来：
    /// 原实现 `Timer.scheduledTimer(withTimeInterval: 600, repeats: false)`
    /// 创建完就不管了，既不存也不取消 —— 每开一次面板就多挂一个 10 分钟后
    /// 自己触发的幽灵更新，面板开关多少次就有多少个（面板副标题的注释早
    /// 写着「懒加载」，这里正是它的反面）。`firstRunTimer` 当时声明了却从没赋值。
    var firstRunTimer: Timer?
    /// 合并刷新用（见 refreshAll）
    private var refreshGate = RefreshGate()
    /// 确有刷新被排队（不是「正在刷新」）—— 供 UI 区分两种转圈
    @Published private(set) var refreshQueued = false
    /// 面板副标题回调（PanelWindow 注入）
    var onSummaryChange: ((String?) -> Void)?

    // MARK: 路由

    /// **唯一**的路由入口。视图不许直接写 `selection`。
    ///
    /// 去不去、为什么不去，都由 `Router.resolve` 决定（纯函数，可单测）：
    ///   · 目标不是项目 → 直接去
    ///   · 项目列表还没加载完 → 先去，详情页显示读不出来（**不能**在此判「不存在」）
    ///   · 项目列表加载完了、里面没有 → 改道仪表盘并说明，而不是打开一个空详情页
    func go(_ target: RootSection?) {
        applyRoute(target, loaded: Router.loadedNames(projects.map(\.name),
                                                       hasLoadedOnce: hasLoadedProjectsOnce))
    }

    /// 路由判定的落地。参数分开传，让「列表到底加载了没有」由调用方显式交代 ——
    /// 少这一个参数就会出现「启动瞬间的空数组被判成项目群是空的」。
    private func applyRoute(_ target: RootSection?, loaded: [String]?) {
        switch Router.resolve(target, loadedProjects: loaded) {
        case .go(let s):
            pendingRoute = nil
            selection = s
        case .projectNotFound(let name):
            pendingRoute = nil
            routeNotice = "找不到项目「\(name)」。项目列表里没有它，可能已被删除或改名。"
            selection = .dashboard
        case .listNotLoaded:
            // 先记下，等列表到了再判一次（见 applyPendingRoute）
            pendingRoute = target
            selection = target
        }
    }

    /// 打开项目详情的便捷入口。存在的唯一理由是**不给调用方绕过 go(_:)** 的机会。
    func openProject(_ name: String) { go(.project(name)) }

    /// 关掉深链说明条。说明条不是错误 —— 用户看到就够了，不该一直挂着。
    func dismissRouteNotice() { routeNotice = nil }

    // MARK: 更新范围

    /// 双轨动作的作用范围。**由 selection 推导，不是一个独立状态** ——
    /// 设计稿顶栏那个范围下拉在客户端里是侧栏导航的职责，
    /// 再存一份就是「当前看的是谁」有两个来源。
    var updateScope: UpdateScope { ScopeRules.scope(for: selection) }

    /// 项目名 → 该项目的待记录提交数（浅更新徽章用）。
    var pendingByProject: [String: Int] {
        var out: [String: Int] = [:]
        for p in projects {
            out[p.name] = p.branches.reduce(0) { $0 + $1.pendingCommits }
        }
        return out
    }

    /// 全部项目的待记录之和。
    var pendingAll: Int {
        projects.reduce(0) { $0 + $1.branches.reduce(0) { a, b in a + b.pendingCommits } }
    }

    /// 当前范围内有东西在跑吗。
    var updateScopeBusy: Bool {
        ScopeRules.isBusy(updateScope, busyAll: busyAll, busyProject: busyProject)
    }

    /// 按范围执行一次更新（不生成 AI 摘要；AI 变体走 UpdateActionMenu）。
    ///
    /// 只有一个入口在这里 —— 顶栏双轨按钮、菜单项都调它，
    /// 免得同一个动作在两处各写一遍（两处迟早漂移）。
    ///
    /// ⚠️ 范围是「全部」时**必须走确认框**，不许直接 `updateAll`：
    /// 引擎的 `updateAll` 会逐项目改写托管文档，而 §3.2 定的破坏性操作确认
    /// 里就写着「批量更新」。这里一旦绕过，原先那个确认框就形同虚设 ——
    /// 而它还长得像还在工作（菜单项照样在）。
    func runUpdate(deep: Bool) {
        switch updateScope {
        case .project(let name):
            guard let p = projects.first(where: { $0.name == name }) ?? projectDetails[name] else {
                lastError = "找不到项目「\(name)」。项目列表里没有它，可能已被删除或改名。"
                return
            }
            Task { await update(p, deep: deep) }
        case .all:
            requestBulkUpdate(deep: deep)
        }
    }

    /// 「不管当前选中了什么，都要更新全部项目群」的入口。
    ///
    /// ⚠️ 不能靠 `runUpdate(deep:)` 顶替：它按 `updateScope` 走，
    /// 而范围是由 `selection` 推导的 —— 用户停在某个项目上时，
    /// 调它会去更新**那一个项目**，而 Dock 菜单写的是「全部」。
    /// 名字里得说清是「全部」，免得调用方以为它等价于 runUpdate。
    func requestBulkUpdate(deep: Bool) {
        pendingBulkUpdate = deep ? .deep : .shallow
    }

    /// 项目列表加载完之后的补判。
    ///
    /// 直接复用 `go(_:)`：调用它之前 `hasLoadedProjectsOnce` 刚被置为 true，
    /// 所以这一次 `Router` 拿到的是「加载完了」的名单，不再走 listNotLoaded 分支。
    private func applyPendingRoute() {
        guard let target = pendingRoute else { return }
        go(target)
    }

    // MARK: 菜单栏状态项（图标 + 标题 = 实时健康度）

    var menuTitle: String {
        if isLoading && projects.isEmpty { return "⋯" }
        if !engineFound { return "?" }
        if lastError != nil && projects.isEmpty { return "!" }
        var title = "\(projects.count)"
        let stale = summary?.staleProjects
            ?? projects.filter { $0.branches.contains { $0.status == "stale" } }.count
        let dirty = summary?.dirtyProjects
            ?? projects.filter { $0.userDirtyCount > 0 }.count
        if stale > 0 { title += " ⚠︎\(stale)" }
        else if dirty > 0 { title += " ●\(dirty)" }
        return title
    }

    var menuSymbol: String {
        if !engineFound { return "questionmark.circle" }
        if lastError != nil && projects.isEmpty { return "exclamationmark.circle" }
        let stale = summary?.staleProjects ?? 0
        let dirty = summary?.dirtyProjects ?? 0
        if stale > 0 { return "exclamationmark.triangle.fill" }
        if dirty > 0 { return "circle.circle.fill" }
        return "circle.grid.2x2.fill"
    }

    var menuTint: String {
        if !engineFound { return "orange" }
        if lastError != nil && projects.isEmpty { return "red" }
        let stale = summary?.staleProjects ?? 0
        if stale > 0 { return "red" }
        let dirty = summary?.dirtyProjects ?? 0
        if dirty > 0 { return "orange" }
        return "green"
    }

    var summaryLine: String? {
        guard let s = summary else { return nil }
        // ⚠️ 「项目数」必须用 listedProjects（注册表里一共多少条），不是 projectCount
        // （只数采集成功的）。
        //
        // 引擎为此专门补了 listedProjects / failedProjects 并在 CLI 文本路径披露，
        // 注释原话：「表格会渲染全部条目，于是表头写『共 2 个项目』而下面列了 4 行
        // —— 数字自相矛盾，用户会以为只注册了 2 个，坏掉的那 2 个就这么消失在视野里」。
        //
        // 这里用 projectCount 就是客户端把这个缺陷重新引入了一遍：
        // 菜单栏 title 用的是 projects.count（实测 2），副标题用 projectCount（实测 1），
        // 同一个 App 里两个「项目数」互相打架，而坏掉的项目在副标题里人间蒸发。
        var parts = ["\(s.listedProjects) 项目"]
        if s.failedProjects > 0 {
            parts.append("\(s.failedProjects) 读取失败")
        }
        // ⚠️ 分支数必须把「追踪数」与「仓库真实总数」分开。
        //
        // branchCount 是引擎追踪到基线的数量，repoBranchTotal 才是仓库真实总数。
        // 引擎 CLI 的注释点名了这个坑：「实测 16 个分支的仓库 status 只显示 7 个
        // 且零披露」，为此补了 repoBranchTotal / branchTruncatedProjects /
        // branchUnknownProjects 三个披露字段。
        //
        // 直接显示 branchCount 的实测后果：刚注册、还没 track 过的仓库报
        // 「分支 0」而 repoBranchTotal=2 —— 字面写「0 分支」，
        // 用户会据此认定仓库没有分支。
        let tracked = s.branchCount
        let total = s.repoBranchTotal
        if total >= 0 && total > tracked {
            parts.append("\(tracked)/\(total) 分支")
            if s.branchTruncatedProjects > 0 {
                parts.append("\(s.branchTruncatedProjects) 个未全部追踪")
            }
        } else if s.branchUnknownProjects > 0 {
            // 真实总数读不出来：不能说 0，也不能假装知道
            parts.append("\(tracked) 分支")
            parts.append("\(s.branchUnknownProjects) 个项目分支数读不出来")
        } else {
            parts.append("\(tracked) 分支")
        }
        if s.dirtyProjects > 0 { parts.append("\(s.dirtyProjects) 有改动") }
        if s.staleProjects > 0 { parts.append("\(s.staleProjects) 停滞") }
        return parts.joined(separator: " · ")
    }

    // MARK: 生命周期

    func start() async {
        // ⚠️ 必须幂等：面板每次 onAppear 都会调 start()。
        // 原实现不清理旧的 5 分钟 timer 就直接新建（`restartAutoTimer` 至少
        // invalidate 了自己那一个，但 `timer` 那个是先 invalidate 再建，
        // 而 600 秒首轮那个压根没人管），窗口开关 N 次就挂 N 个 timer。
        invalidateTimers()
        await refreshAll()
        restartAutoTimer()
        // 每 5 分钟轻量刷新（bar 常驻，保持轻量）
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshLight() }
        }
    }

    /// 收掉**全部** timer。
    ///
    /// 原 `stop()` 只杀 `timer` 一个，autoTimer（定时更新）与
    /// firstRunTimer（首轮延迟）都活着 —— stop 之后它们照样触发。
    func stop() {
        invalidateTimers()
    }

    private func invalidateTimers() {
        timer?.invalidate(); timer = nil
        autoTimer?.invalidate(); autoTimer = nil
        firstRunTimer?.invalidate(); firstRunTimer = nil
    }

    // MARK: 数据加载

    /// 确保引擎可用：只需要发现到引擎二进制（数据靠每次调用现起子进程，没有常驻服务）
    /// ⚠️ 原来写的是「发现引擎 → 拉起 serve → 探测 health」——
    /// `serve` 子命令与 health 端点都已随 HTTP 服务端整体删除，
    /// 留着这段注释会让人去找一个不存在的服务、并以为引擎需要预热。
    func ensureReady() async -> Bool {
        engineFound = EngineCLI.shared.binaryPath != nil
        guard engineFound else { return false }
        return true
    }

    /// 轻量刷新：仅状态（bar 周期任务用）
    func refreshLight() async {
        await fetchStatus(light: true)
    }

    /// 全量刷新：状态 + 仪表盘 + 里程碑（面板打开 / 手动刷新用）
    func refreshAll() async {
        // ⚠️ 原来第一行是 `if isLoading { return }` ——
        // 一次手动刷新正好撞上定时刷新（或另一次刷新）就被**静默丢弃**：
        // 按钮按下去有转圈（isLoading 已是 true），转完却什么也没变，
        // 也没有任何提示。这就是「点刷新像没反应」的直接来源。
        //
        // 改成**合并**而不是丢弃：撞上时记下「还要再刷一次」，
        // 等当前这次跑完立刻补上。反复请求不叠加成 N 遍
        // （跑 N 遍同样慢，还像程序失控）。判定见 ClientDecisions.RefreshGate。
        guard refreshGate.request() else {
            refreshQueued = true
            return
        }
        await runRefreshAll()
        // 跑完若有待补的请求，立刻补一次（循环而非递归，避免深栈）
        while refreshGate.finish() {
            refreshQueued = false
            if !refreshGate.request() { break }
            await runRefreshAll()
        }
        refreshQueued = false
    }

    /// 真正执行刷新。**调用方负责处理合并**（见 refreshAll）。
    private func runRefreshAll() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let ready = await ensureReady()
        guard ready else {
            lastError = EngineError.notFound.userMessage
            return
        }

        await fetchStatus(light: false)
        // 状态失败时不要等 dashboard/milestones（TCC/引擎问题会让用户干等 180s）
        if lastError != nil {
            isLoading = false
            return
        }
        await fetchDashboard()
        await fetchMilestones()
        lastRefreshed = Date()
        postNotificationsIfNeeded()
    }

    func fetchStatus(light: Bool) async {
        // TCC 预检：外置卷上的项目在 GUI app 未获授权时，git 子进程会被内核无限阻塞。
        // FileManager.isReadableFile 立即返回（不 spawn 子进程），提前拦截并给用户明确指引。
        if let first = projects.first, !FileManager.default.isReadableFile(atPath: first.path) {
            lastError = "无法访问项目目录（\(first.path)）——\n请在 系统设置 → 隐私与安全性 → 完全磁盘访问权限 中允许 deepGit"
            engineFound = true
            return
        }
        do {
            let env = try await EngineCLI.shared.status(light: light)
            projects = env.projects.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            summary = env.summary
            engineFound = true
            // 列表到了 ⇒ 深链指向的项目现在**可以**被核对了（见 applyPendingRoute）。
            // 失败路径**不许**置位：引擎没返回不等于「项目群是空的」，
            // 置位会让「找不到项目」在引擎故障时误报。
            hasLoadedProjectsOnce = true
            applyPendingRoute()
            onSummaryChange?(summaryLine)
        } catch {
            if EngineCLI.shared.binaryPath == nil { engineFound = false }
            lastError = EngineError.userMessage(for: error)
        }
    }

    func fetchDashboard() async {
        // ⚠️ 不能用 `try?`：原来 `dashboard = try? await ...` 在失败时
        // 静默保持旧值 —— 超时（180s）或解码失败都不留任何痕迹，
        // UI 继续显示上一次的陈旧数据且没有任何提示。
        // 用户看到的是「数据没变」，真实原因被完全吞掉。
        dashboardState = .loading
        do {
            dashboard = try await EngineCLI.shared.dashboard()
            // ⚠️ 成功一次就清掉上次的失败 —— 否则项目修好了、转圈还在。
            dashboardState = .loaded
        } catch {
            let msg = EngineError.userMessage(for: error)
            lastError = msg
            // 视图靠它区分「还在读」与「读不出来」；只设全局 lastError 的话，
            // DashboardView 会永远停在 ProgressView（见 LoadState.swift 顶部）。
            dashboardState = .failed(msg)
        }
    }

    func fetchMilestones() async {
        milestonesState = .loading
        do {
            let env = try await EngineCLI.shared.milestones()
            milestones = env.milestones
            // ⚠️ milestones.json 损坏/降级必须说，不能让空数组冒充「还没有里程碑」。
            // 引擎恒发 storeHealth / degraded / readCount 就是为了这个 ——
            // 客户端把它们全丢了，等于把「读不出来」渲染成「没有」。
            //
            // 降级且读到 0 条 ⇒ 这个「空」不可信，按 failed 走；
            // 降级但读到了一部分 ⇒ 内容是真的，只挂一条说明。
            milestonesState = LoadRules.state(storeHealth: env.storeHealth, readCount: env.readCount)
            if let notice = LoadRules.degradedNotice(storeHealth: env.storeHealth, readCount: env.readCount) {
                lastError = notice
            }
        } catch {
            let msg = EngineError.userMessage(for: error)
            lastError = msg
            milestonesState = .failed(msg)
        }
    }

    /// 单项目完整状态（含 8 条日志），面板详情用
    func loadProject(_ name: String) async {
        do {
            let p = try await EngineCLI.shared.status(name: name)
            projectDetails[name] = p
            // 成功一次就清掉上次的失败 —— 否则项目修好了、之前的红色标记还在。
            projectLoadErrors.removeValue(forKey: name)
        } catch {
            let msg = EngineError.userMessage(for: error)
            lastError = msg
            // 详情页靠它区分「还在读」与「读不出来」；只设全局 lastError 的话，
            // 详情页那个 `project == nil` 的分支会永远显示 ProgressView。
            projectLoadErrors[name] = msg
        }
    }

    /// 项目文档内容（README / AGENTS / CLAUDE 平铺展示用）
    ///
    /// ⚠️ 三态与 `loadProject` / `fetchDashboard` 同一族的问题：
    /// 读不出来时这里只是**不赋值**，而详情页是
    /// `if let docs = model.projectDocs[name], !docs.isEmpty { … }` ——
    /// 于是「文档读不出来」与「这个项目没有文档」渲染成**一模一样**：
    /// 什么都不画。用户据此认为「这个项目确实没有 README」。
    func loadDocs(_ name: String) async {
        docsStates[name] = .loading
        do {
            let env = try await EngineCLI.shared.docs(name: name)
            projectDocs[name] = env.docs
            docsStates[name] = .loaded
            // ⚠️ 原来 catch 是空的、unreadable 也没建模 ——
            // 文档读不出来时详情页只是少一张卡片，用户会认为项目没有该文档。
            // 引擎的注释原话：「读失败的文档必须随 200 一起披露，
            // 否则客户端拿到一个少了一条 README 的数组，无从判断是『没有』还是『读不出来』」。
            if !env.unreadable.isEmpty {
                lastError = "\(name)：以下文档存在但读取失败 —— \(env.unreadable.joined(separator: "、"))"
            }
        } catch {
            let msg = EngineError.userMessage(for: error)
            lastError = msg
            docsStates[name] = .failed(msg)
        }
    }

    // MARK: git 操作（引擎侧执行，无破坏性命令）

    @discardableResult
    func gitOp(_ project: ProjectStatus, op: String, message: String = "") async -> Bool {
        busyProject = project.name
        defer { busyProject = nil }
        do {
            let data = try await EngineCLI.shared.gitOp(project: project.name, op: op, message: message)
            let r = try JSONDecoder().decode(GitOpResponse.self, from: data)
            let text = r.output.isEmpty ? (r.ok ? "完成" : "失败") : r.output
            lastGitOpOutput = (r.ok, "[\(r.op)] \(text)")
            await loadProject(project.name)
            await fetchStatus(light: true)
            if r.ok && (op == "commit" || op == "push") {
                Notifier.shared.notify(title: "git \(op) 完成", body: project.name)
            }
            return r.ok
        } catch {
            lastGitOpOutput = (false, "[\(op)] \(EngineError.userMessage(for: error))")
            return false
        }
    }

    // MARK: 更新动作（引擎侧执行）

    /// 正在跑的更新任务。**存下来才能停** —— 原来 Task 是调用方临时建的，
    /// 模型这边只有一个 `busyAll` 标志，于是 UI 上根本没有任何办法中止一次
    /// 已经开始的批量更新（引擎侧超时是 900 秒）。
    private var updateAllTask: Task<Void, Never>?
    private var updateTasks: [String: Task<Void, Never>] = [:]

    /// 当前是否处于「用户按了停止、正在收尾」的状态。
    @Published private(set) var stoppingUpdate = false

    /// 有没有正在跑的、可以被停止的更新。
    var canStopUpdate: Bool {
        StopDecision.canStop(isBusyAll: busyAll,
                             busyProject: busyProject,
                             isStopping: stoppingUpdate)
    }

    /// 「全部浅更新」能不能点。判定在 StopDecision（可测）。
    var canStartUpdateAll: Bool { StopDecision.canStartUpdateAll(isBusyAll: busyAll) }

    /// 停止正在跑的更新。
    ///
    /// 两步缺一不可，而且**顺序不能反**：
    ///   1. `EngineCLI.terminateRunning` —— 真正 kill 掉引擎子进程
    ///   2. 取消 Swift 侧 Task —— 让后续代码别再往下走
    ///
    /// 只做第 2 步是**假的停止**：`run` 同步阻塞且包在 `Task.detached` 里，
    /// 而取消只对结构化并发传播 —— detached task 会照样阻塞到超时。
    /// 只做第 1 步则 `await` 之后还会继续 refreshAll 并弹「更新完成」通知。
    func stopUpdate() {
        guard canStopUpdate else { return }
        stoppingUpdate = true
        let wasRunning = updateAllTask != nil || !updateTasks.isEmpty
        // 只杀 update/deep，别把并行的 status 刷新也掐掉
        let killed = EngineCLI.shared.terminateRunning(onlyCommands: ["update", "deep"])
        updateAllTask?.cancel()
        updateAllTask = nil
        for (_, t) in updateTasks { t.cancel() }
        updateTasks.removeAll()
        // 说实话：被停掉不是失败，"停止时已经跑完了"也不是失败。
        // 唯一要警告的是"取消了等待但进程还活着" —— 那等于没停成。
        let o = StopDecision.outcome(killed: killed, taskWasCancelled: wasRunning)
        let msg = StopDecision.message(o, itemCount: projects.count)
        if StopDecision.shouldWarn(o) {
            lastError = msg
        }
        Notifier.shared.notify(title: "停止更新", body: msg)
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            stoppingUpdate = false
        }
    }

    func update(_ project: ProjectStatus, deep: Bool) async {
        busyProject = project.name
        defer { busyProject = nil; updateTasks[project.name] = nil }
        do {
            let data = try await EngineCLI.shared.update(name: project.name, deep: deep)
            guard !Task.isCancelled else { return }
            await refreshAll()
            await loadProject(project.name)
            // ⚠️ 原来这里是 `_ = try await …` —— 结果整个丢掉，
            // 然后**无条件**弹「文档托管区域已刷新」（缺陷 #211）。
            // 而引擎在文档没变化时输出的是「README.md 无变化」：
            // **没做被说成做了**。现在按引擎报的 docs 说话。
            // 解不出来也不能退回那句假话 —— 那时只说「已完成」。
            var body = "\(project.name) 的更新已完成"
            if let env = try? JSONDecoder().decode(UpdateResultEnvelope.self, from: data) {
                body = updateOutcomeSummary(env.outcome, project: env.project)
            }
            Notifier.shared.notify(
                title: deep ? "深度更新完成" : "进度已记录",
                body: body
            )
        } catch let e as EngineError {
            // 被停掉不是失败 —— 报"更新失败"会让人以为跑了一半的更新坏了
            if case .cancelled = e { return }
            lastError = e.userMessage
            Notifier.shared.notify(title: "更新失败", body: "\(project.name)：\(e.userMessage)")
        } catch {
            guard !Task.isCancelled else { return }
            lastError = EngineError.userMessage(for: error)
            Notifier.shared.notify(title: "更新失败", body: "\(project.name)：\(EngineError.userMessage(for: error))")
        }
    }

    /// 发起一次单项目更新，并把 Task 存下来以便 `stopUpdate` 能中止它。
    func startUpdate(_ project: ProjectStatus, deep: Bool) {
        guard busyProject == nil, !busyAll else { return }
        updateTasks[project.name]?.cancel()
        updateTasks[project.name] = Task { [weak self] in
            await self?.update(project, deep: deep)
        }
    }

    /// 发起一次批量更新，并把 Task 存下来以便 `stopUpdate` 能中止它。
    ///
    /// 原来 UI 直接 `Task { await model.updateAll(deep: false) }`，
    /// 任务在视图里、模型只有一个 bool —— 想停都不知道停谁。
    func startUpdateAll(deep: Bool, silent: Bool = false) {
        guard !busyAll else { return }
        updateAllTask?.cancel()
        updateAllTask = Task { [weak self] in
            _ = await self?.updateAll(deep: deep, silent: silent)
        }
    }

    @discardableResult
    func updateAll(deep: Bool, silent: Bool = false) async -> Bool {
        guard !busyAll else { return false }
        busyAll = true
        defer { busyAll = false }
        do {
            let data = try await EngineCLI.shared.updateAll(deep: deep)
            guard !Task.isCancelled else { return false }
            await refreshAll()
            if !silent {
                // 同样不许无条件说「已记录」：引擎可能一份文档都没动。
                // ⚠️ 引擎的形状随项目数变：只有 1 个项目时给**裸的**
                // `UpdateResultEnvelope`，多个项目才给 `{results,count,…}`。
                // 两种都试一遍，按解得出的那个说话。
                var body = "\(projects.count) 个项目已更新"
                if let all = try? JSONDecoder().decode(UpdateAllEnvelope.self, from: data) {
                    var touchedProjects = 0
                    var changedDocs = 0
                    for r in all.results {
                        let o = updateOutcome((r.docs ?? []).map { $0.outcome })
                        if o.anythingTouched {
                            touchedProjects += 1
                            changedDocs += o.touched.count
                        }
                    }
                    body = all.failed > 0
                        ? "\(all.succeeded) 个项目更新，\(all.failed) 个失败（详见上方错误）"
                        : (changedDocs == 0
                            ? "\(all.count) 个项目都没有需要更新的文档"
                            : "\(all.count) 个项目，共更新 \(changedDocs) 份文档（\(touchedProjects) 个项目有改动）")
                } else if let one = try? JSONDecoder().decode(UpdateResultEnvelope.self, from: data) {
                    body = updateOutcomeSummary(one.outcome, project: one.project)
                }
                Notifier.shared.notify(
                    title: deep ? "全部深度更新完成" : "全部进度已记录",
                    body: body
                )
            }
            return true
        } catch let e as EngineError {
            if case .cancelled = e {
                if !silent { Notifier.shared.notify(title: "已停止", body: "批量更新被手动停止") }
                return false
            }
            lastError = e.userMessage
            if !silent {
                Notifier.shared.notify(title: "批量更新失败", body: e.userMessage)
            }
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            lastError = EngineError.userMessage(for: error)
            if !silent {
                Notifier.shared.notify(title: "批量更新失败", body: EngineError.userMessage(for: error))
            }
            return false
        }
    }

    // MARK: 里程碑动作（引擎侧执行）

    func milestoneAction(_ m: MilestoneItem, action: String) async {
        do {
            try await EngineCLI.shared.milestoneAction(project: m.projectName, name: m.name, action: action)
            await fetchMilestones()
            await fetchDashboard()
        } catch {
            lastError = EngineError.userMessage(for: error)
        }
    }

    func addMilestone(project: String, name: String, tag: String, targetDate: String, description: String) async throws {
        var body: [String: Any] = ["project": project, "name": name]
        if !tag.isEmpty { body["tag"] = tag }
        if !targetDate.isEmpty { body["targetDate"] = targetDate }
        if !description.isEmpty { body["description"] = description }
        try await EngineCLI.shared.addMilestone(project: project, name: name, tag: tag, date: targetDate, desc: description)
        await fetchMilestones()
        await fetchDashboard()
    }

    // MARK: 提醒策略：只在状态「新变差」时提醒，避免重复打扰

    private func postNotificationsIfNeeded() {
        for p in projects {
            for b in p.branches where b.status == "stale" && !b.isDefault {
                let key = "stale:\(p.id):\(b.name)"
                if !notifiedKeys.contains(key) {
                    notifiedKeys.insert(key)
                    Notifier.shared.notify(
                        title: "分支停滞：\(p.name)",
                        body: "`\(b.name)` 已 \(b.headAgo) 无提交，考虑合并或关闭"
                    )
                }
            }
            if p.userDirtyCount >= 10 {
                let key = "dirty:\(p.id):\(p.userDirtyCount / 10)"
                if !notifiedKeys.contains(key) {
                    notifiedKeys.insert(key)
                    Notifier.shared.notify(
                        title: "未提交改动较多：\(p.name)",
                        body: "\(p.userDirtyCount) 处改动未提交"
                    )
                }
            }
        }
    }
}

extension Notification.Name {
    static let openPanelRequest = Notification.Name("deepgit.openPanel")
}
