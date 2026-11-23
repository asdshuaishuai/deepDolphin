// AppModel.kt —— 进程级数据编排（mac Model.swift / archive-bui appstate 对位）。
//
// 【纪律】每数据源一份自己的 LoadState（不共用 lastError）；UI 只消费 StateFlow；
// 所有引擎调用在 Dispatchers.IO；refreshAll 顺序 status → dashboard → milestones。

package deepdolphin.ui

import deepdolphin.engine.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// 读态三态（加载/成功/失败——与 BUI 三态判定一致：failed ≠ empty）
sealed interface LoadState {
    data object Loading : LoadState
    data object Loaded : LoadState
    data class Failed(val reason: String) : LoadState
}

/** MultiResults.results 二态解码的批包装（updateAll / runScheduledUpdate 共用一份口径）。 */
internal fun decodeUpdateOutcomes(r: MultiResults): List<UpdateOutcome> = r.results.map(::decodeUpdateOutcome)

class AppModel(private val engineBin: String) {

    val engine = Engine(engineBin)

    private val _status = MutableStateFlow<StatusEnvelope?>(null)
    val status: StateFlow<StatusEnvelope?> = _status.asStateFlow()
    private val _statusState = MutableStateFlow<LoadState>(LoadState.Loading)
    val statusState: StateFlow<LoadState> = _statusState.asStateFlow()

    private val _dashboard = MutableStateFlow<DashboardData?>(null)
    val dashboard: StateFlow<DashboardData?> = _dashboard.asStateFlow()
    private val _dashState = MutableStateFlow<LoadState>(LoadState.Loading)
    val dashState: StateFlow<LoadState> = _dashState.asStateFlow()

    private val _milestones = MutableStateFlow<MilestoneList?>(null)
    val milestones: StateFlow<MilestoneList?> = _milestones.asStateFlow()
    private val _msState = MutableStateFlow<LoadState>(LoadState.Loading)
    val msState: StateFlow<LoadState> = _msState.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    private val _refreshing = MutableStateFlow(false)
    val refreshing: StateFlow<Boolean> = _refreshing.asStateFlow()

    /**
     * 上次刷新成功时间（mac Model.swift:160 @Published lastRefreshed 对位；
     * 侧栏状态条右侧读它）。null = 还没成功刷新过——「尚未刷新」而非编一个 0 点。
     */
    private val _lastRefreshed = MutableStateFlow<java.time.LocalDateTime?>(null)
    val lastRefreshed: StateFlow<java.time.LocalDateTime?> = _lastRefreshed.asStateFlow()

    // ── 批 2：路由 + 详情 + 写操作反馈 ──
    // 对位 mac：侧栏没有 AI 入口——AI 以 agent sheet 形态从详情页（深浅更新旁）触发，
    // 设置（含 AI tab）收在侧栏最底部「设置」（mac 原生 Settings scene 的 Linux 对位）。
    enum class Route { DASHBOARD, BOARD, MILESTONES, CONFIDENCE, PATCHCHECK, PROJECT, SETTINGS }
    private val _route = MutableStateFlow(Route.DASHBOARD)
    val route: StateFlow<Route> = _route.asStateFlow()
    private val _selectedProject = MutableStateFlow<String?>(null)
    val selectedProject: StateFlow<String?> = _selectedProject.asStateFlow()

    /**
     * agent sheet 开合（对位 mac GraphChrome 的 AgentView(initialTask:) 语义）。
     * 没有独立入口——AI 融进操作：深/浅更新完成后就地「AI 解读」、一键「项目群/项目说明」
     * 都带着预填任务打开（mac GroupBriefButton / ProjectBriefButton 对位）。
     * title = sheet 头部措辞（「项目群说明」「项目说明」…）；null 时由 AgentSheet
     * 按有无任务回退到「更新解读 / AI」既有口径。
     */
    private val _agentOpen = MutableStateFlow(false)
    val agentOpen: StateFlow<Boolean> = _agentOpen.asStateFlow()
    private val _agentTask = MutableStateFlow<String?>(null)
    val agentTask: StateFlow<String?> = _agentTask.asStateFlow()
    private val _agentTitle = MutableStateFlow<String?>(null)
    val agentTitle: StateFlow<String?> = _agentTitle.asStateFlow()
    fun openAgent(task: String? = null, title: String? = null) {
        _agentTask.value = task; _agentTitle.value = title; _agentOpen.value = true
    }
    fun closeAgent() {
        _agentOpen.value = false; _agentTask.value = null; _agentTitle.value = null
    }

    // ── 图谱两页开合流（mac GraphWindows.open 的对位；Dialog 接近全屏，标题带项目名）──
    // 值 = 项目名（单仓库锁定：入口处定死，页面内无切换）；null = 关。
    // 本批只挂状态流 + Main 挂载渲染，详情页入口下一批接线。
    private val _graphPage = MutableStateFlow<String?>(null)
    val graphPage: StateFlow<String?> = _graphPage.asStateFlow()
    private val _archPage = MutableStateFlow<String?>(null)
    val archPage: StateFlow<String?> = _archPage.asStateFlow()

    fun openGraph(project: String) {
        _graphPage.value = project
    }

    fun closeGraph() {
        _graphPage.value = null
    }

    fun openArch(project: String) {
        _archPage.value = project
    }

    fun closeArch() {
        _archPage.value = null
    }

    /** GraphPageDialog 的统一关闭口（kind 路由到对应流）。 */
    fun closeGraphPage(kind: GraphKind) {
        when (kind) {
            GraphKind.INDEX -> closeGraph()
            GraphKind.ARCH -> closeArch()
        }
    }

    /**
     * 图谱两页的生成入口（详情页动作条接线，本批）。
     *
     * 【与 mac 探测逻辑的差异，如实标注】mac（DetailViews.swift:229-307）先探产物
     * （render check，GraphChrome.swift:182-194：exists=true → 按钮直接是「打开」；
     * exists=false → 「生成」形态，且生成走 GraphAgentTask 播种 agent 的 LLM 工作流）。
     * 本机引擎没有 render check 子命令（实测：`render check index <项目>` 报用法错）——
     * 按 mac 自己的降级先例（GraphChrome.swift:185-187 注释：探测失败按「未生成」处理）：
     * 不探测、不做「打开/生成」两态按钮，点按统一 busy 态跑 render——
     *   · 产物已在：引擎侧复用判定毫秒级返回（回执说「复用」），render 完即开页 = 秒开；
     *   · 产物不在：这一发就是首次生成（分钟级，busy 态如实等待）。
     * 成功后先把产物路径记进进程内缓存再开页：页 init 即命中缓存先出图，
     * 页内后台核验跑 render 得「复用」不重载（画面不闪）。
     * 另一差异：CMP 生成直接跑确定性 render 命令（无 agent 播种回调，不造假按钮）。
     */
    private val _graphRendering = MutableStateFlow<String?>(null) // "<kind>:<project>"；null = 空闲
    val graphRendering: StateFlow<String?> = _graphRendering.asStateFlow()

    fun renderGraphArtifact(project: String, kind: GraphKind) {
        if (_graphRendering.value != null) return
        scope.launch {
            _graphRendering.value = "${kind.name}:$project"
            try {
                val text = engine.renderGraph(kind.cliKind, project, withConfidence = kind == GraphKind.INDEX)
                val path = extractHtmlPath(text)
                if (path == null) {
                    _lastResult.value =
                        L10n.t("cmp.update.renderFailNoPath", kind.titleWord(), project, receiptLine(text) ?: L10n.t("cmp.err.noOutput"))
                } else {
                    rememberGraphArtifact(kind, project, path)
                    when (kind) {
                        GraphKind.INDEX -> openGraph(project)
                        GraphKind.ARCH -> openArch(project)
                    }
                }
            } catch (e: Exception) {
                _lastResult.value = L10n.t("cmp.update.renderFail", kind.titleWord(), project, e.message ?: e.javaClass.simpleName)
            } finally {
                _graphRendering.value = null
            }
        }
    }

    private val _detail = MutableStateFlow<StatusEnvelope?>(null) // status <name> 单项目信封
    val detail: StateFlow<StatusEnvelope?> = _detail.asStateFlow()
    private val _detailState = MutableStateFlow<LoadState>(LoadState.Loading)
    val detailState: StateFlow<LoadState> = _detailState.asStateFlow()

    private val _docs = MutableStateFlow<DocsPayload?>(null)
    val docs: StateFlow<DocsPayload?> = _docs.asStateFlow()

    private val _journal = MutableStateFlow<JournalPayload?>(null)
    val journal: StateFlow<JournalPayload?> = _journal.asStateFlow()

    /** 写操作结果一行（「写操作必须留结果」纪律）；null = 无。 */
    private val _lastResult = MutableStateFlow<String?>(null)
    val lastResult: StateFlow<String?> = _lastResult.asStateFlow()
    private val _busyAction = MutableStateFlow(false)
    val busyAction: StateFlow<Boolean> = _busyAction.asStateFlow()

    fun goRoute(r: Route, project: String? = null) {
        _route.value = r
        _selectedProject.value = project
        if (r == Route.PROJECT && project != null) loadDetail(project)
    }

    /** 单项目详情三源：status <n> → docs → journal（失败不短路，逐源披露）。 */
    fun loadDetail(name: String) {
        scope.launch {
            _detailState.value = LoadState.Loading
            try {
                _detail.value = engine.status(name)
                _detailState.value = LoadState.Loaded
            } catch (e: Exception) {
                _detailState.value = LoadState.Failed(e.message ?: L10n.t("cmp.err.detailRead"))
            }
            try { _docs.value = engine.docs(name) } catch (_: Exception) { _docs.value = null }
            try { _journal.value = engine.journal(name) } catch (_: Exception) { _journal.value = null }
        }
    }

    private suspend fun <T> withAction(label: String, block: suspend () -> T): T? {
        if (_busyAction.value) return null
        _busyAction.value = true
        try {
            val r = block()
            _lastResult.value = "$label ✓"
            refreshAll()
            return r
        } catch (e: Exception) {
            _lastResult.value = "$label ✗ ${e.message}"
            return null
        } finally {
            _busyAction.value = false
        }
    }

    // ── C9 里程碑 CRUD ──
    fun milestoneAdd(project: String, name: String, tag: String?, date: String?, desc: String?) {
        scope.launch {
            withAction(L10n.t("cmp.action.msAdd", name)) { engine.milestoneAdd(project, name, tag, date, desc) }
        }
    }

    fun milestoneAction(project: String, name: String, action: String) {
        scope.launch {
            withAction(L10n.t("cmp.action.msAction", name, action)) { engine.milestoneAction(project, name, action) }
        }
    }

    fun milestoneRemove(project: String, name: String) {
        scope.launch {
            withAction(L10n.t("cmp.action.msRemove", name)) { engine.milestoneRemove(project, name) }
        }
    }

    // ── 项目群管理：扫描 / 添加（空态 CTA 与引擎 scan/add 的接线；结果如实披露）──

    /**
     * 扫描单（mac ScanSheet + PanelView.swift:92-94 sheet 挂点对位）：
     * 逐项目结论 = 客户端对照「扫描前在册路径集」推导（引擎 payload 只有聚合数
     * added/existing——candidates 不带归属标记，真机实测锚定，不发明）；聚合行
     * 仍以引擎口径为准，两处计数若分叉以聚合行兜底披露。
     */
    data class ScanOutcome(
        val root: String,
        val depth: Int,
        /** 逐项目行（新增 / 已在册）；引擎没跑成时为空。 */
        val rows: List<ScanRow>,
        /** 引擎口径聚合行（含覆盖度披露与「没有 git 仓库」的成立判定）。 */
        val aggregate: String,
        /** 表单级失败（引擎没跑成 / 输出不可解析）：有值时 rows/aggregate 不可信。 */
        val error: String? = null,
    )

    private val _scanOutcome = MutableStateFlow<ScanOutcome?>(null)
    val scanOutcome: StateFlow<ScanOutcome?> = _scanOutcome.asStateFlow()

    fun scanProjects(root: String, depth: Int) {
        scope.launch {
            if (_busyAction.value) return@launch
            _busyAction.value = true
            try {
                // 在册集快照必须在引擎跑之前取——scan 边跑边注册，跑完再取就全是「已在册」
                val before = _status.value?.projects?.map { it.path.trimEnd('/') }?.toSet() ?: emptySet()
                val r = engine.scan(root, depth)
                val outcome = ScanOutcome(
                    root = root,
                    depth = depth,
                    rows = scanRows(r.candidates, before),
                    aggregate = scanAggregateLine(r),
                )
                _scanOutcome.value = outcome
                _lastResult.value = outcome.aggregate
                refreshAll()
            } catch (e: Exception) {
                _scanOutcome.value = ScanOutcome(root, depth, emptyList(), "", e.message ?: L10n.t("cmp.action.scanFail"))
                _lastResult.value = L10n.t("cmp.action.scanFailWith", root, e.message ?: L10n.t("cmp.action.scanFail"))
            } finally {
                _busyAction.value = false
            }
        }
    }

    fun addProjectPath(path: String, name: String?) {
        scope.launch {
            withAction(L10n.t("cmp.action.addProject", path)) {
                val r = engine.addProject(path, name)
                L10n.t("cmp.action.addProjectDone", r.name.ifBlank { path })
            }
        }
    }

    // ── 扫描单开合（mac .sheet(showScan) 对位；值 = 初始模式：true 单个添加 / false 批量扫描）──
    private val _scanSheet = MutableStateFlow<Boolean?>(null)
    val scanSheet: StateFlow<Boolean?> = _scanSheet.asStateFlow()

    fun openScanSheet(single: Boolean) {
        _scanSheet.value = single
    }

    fun closeScanSheet() {
        _scanSheet.value = null
    }

    // ── C8 git 白名单六操作 ──
    //
    // 【本批修正】原实现把「git $op $project ✓」写进 lastResult 就完了——引擎回执里的
    // ok=false（如 commit 撞上干净工作区、push 撞上远端拒绝）也被标成 ✓，output 一字不出。
    // 对位 mac CommitSheetView 的结果反馈口径：成败与原因留在用户正盯着的提交区，
    // 失败不弹走。feedback 流给 GitCard 就地渲染；lastResult 仍留一行页头摘要。
    data class GitFeedback(val op: String, val project: String, val ok: Boolean, val text: String)

    private val _gitFeedback = MutableStateFlow<GitFeedback?>(null)
    val gitFeedback: StateFlow<GitFeedback?> = _gitFeedback.asStateFlow()

    fun gitOp(op: String, project: String, message: String? = null) {
        scope.launch {
            if (_busyAction.value) return@launch
            _busyAction.value = true
            _gitFeedback.value = null
            try {
                val r = engine.gitOp(op, project, message)
                _gitFeedback.value = GitFeedback(op, project, r.ok, r.output)
                _lastResult.value = "git $op $project " + if (r.ok) "✓" else L10n.t("cmp.action.gitOkFalse")
                refreshAll()
            } catch (e: Exception) {
                _gitFeedback.value = GitFeedback(op, project, false, e.message ?: L10n.t("cmp.err.engineCall"))
                _lastResult.value = "git $op $project ✗ ${e.message}"
            } finally {
                _busyAction.value = false
            }
        }
    }

    // ── C4 更新（浅/深；单项目/全项目）──
    fun updateProject(name: String, deep: Boolean) {
        scope.launch {
            val word = L10n.t(if (deep) "update.deepWord" else "update.shallowWord")
            withAction("$word $name") {
                val r = engine.update(name, deep)
                L10n.t("cmp.update.doneDocs", word, name, r.docs.count { it.changed || it.created })
            }
        }
    }

    fun updateAll(deep: Boolean) {
        scope.launch {
            val word = L10n.t(if (deep) "update.deepWord" else "update.shallowWord")
            withAction(L10n.t("cmp.update.allLabel", word)) {
                val r = engine.updateAll(deep)
                val ok = decodeUpdateOutcomes(r).count { it is UpdateOutcome.Success }
                L10n.t("cmp.update.allDone", word, ok, r.results.size)
            }
        }
    }

    // ── 提交单开合（mac CommitSheetView 的 sheet 挂点对位；值 = 项目名）──
    // 打开即重读详情（mac .task { await load() } 对位：sheet 里的清单不许用页面上的旧数据）。
    private val _commitSheet = MutableStateFlow<String?>(null)
    val commitSheet: StateFlow<String?> = _commitSheet.asStateFlow()

    fun openCommitSheet(project: String) {
        _commitSheet.value = project
        loadDetail(project)
    }

    fun closeCommitSheet() {
        _commitSheet.value = null
    }

    // ── 全量更新：告知式确认 + 结果面板（mac pendingBulkUpdate / agentBulkResult 对位）──
    //
    // 【与 mac 的差异，如实标注】mac 全量走 agent 工具通道逐仓库调 run_shallow_update /
    // run_deep_update（AgentBulkUpdate.run），跑完另生成一份 AI 简报（aiText/aiNote）；
    // CMP 数据源 = Engine.updateAll 单发批量命令的 MultiResults（引擎侧一次遍历注册表，
    // 逐仓库成败在 results[]，失败原因在 {code,message} 条目——真机实测锚定）。
    // AI 简报层 CMP 不做：面板只摊引擎事实，缺的层不伪造（mac 的 aiNote 恒有值的纪律
    // 在 CMP 的对应物是 coverageNote/tallyMismatchNote 两行引擎口径核对披露）。
    private val _pendingBulk = MutableStateFlow<Boolean?>(null) // true=深轨；null=没在等确认
    val pendingBulk: StateFlow<Boolean?> = _pendingBulk.asStateFlow()

    private val _bulkReport = MutableStateFlow<BulkReport?>(null)
    val bulkReport: StateFlow<BulkReport?> = _bulkReport.asStateFlow()

    /** 双轨按钮「· 全部」范围先弹告知式确认（不直接跑——批量更新会改写多个仓库的托管区域）。 */
    fun requestBulkUpdate(deep: Boolean) {
        if (_busyAction.value) return
        _pendingBulk.value = deep
    }

    fun cancelBulkUpdate() {
        _pendingBulk.value = null
    }

    fun closeBulkResult() {
        _bulkReport.value = null
    }

    /** 确认框「全部更新」按下后的执行（mac DeepGitApp.swift:336-344 对位：跑完把 report 交给面板）。 */
    fun confirmBulkUpdate(deep: Boolean) {
        _pendingBulk.value = null
        scope.launch {
            if (_busyAction.value) return@launch
            _busyAction.value = true
            try {
                // 名单在**发起时**取（mac updateAll 同款纪律：界面那份是上次加载的，
                // 注册表可能被别的进程改过；attempted 用于结果面板的覆盖度核对）
                val attempted = _status.value?.projects?.size ?: 0
                val r = engine.updateAll(deep)
                val report = BulkReport.of(deep, attempted, r)
                _bulkReport.value = report
                _lastResult.value = report.headLine()
                refreshAll()
            } catch (e: Exception) {
                // 整发失败：引擎一个仓库的回执都没给，结果面板无从摊起——
                // 不开空面板，失败原因留页头反馈行（如实：什么都没跑成）
                _lastResult.value = L10n.t("cmp.update.allFailed", L10n.t(if (deep) "update.deepWord" else "update.shallowWord"), e.message ?: L10n.t("cmp.err.engineCall"))
            } finally {
                _busyAction.value = false
            }
        }
    }

    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // ── 定时更新（mac AIIntegration.swift:119-173 setAutoUpdate / restartAutoTimer /
    //    runScheduledUpdate 对位）──
    //
    // 【与 mac 的差异，如实标注】mac 面板关了菜单栏进程还在，Timer 是常驻的；
    // CMP 无守护进程——定时器是本进程协程，应用存活期生效、退出即停，
    // 重启后 init 按配置重建（「重启后按配置恢复」）。mac 的系统通知 + AI 简报推送
    // CMP 未接（无通知通道消费方）：结果写进页头操作反馈行（lastResult），如实降级。
    private var autoTimerJob: Job? = null

    init { restartAutoTimer() }

    /** 当前配置（settings.conf 的 update.* 节；设置页「自动化」tab 读它）。 */
    fun autoUpdateSettings(): AutoUpdateSettings = ConfStore.readAuto()

    /**
     * 改配置 = 写 conf + 立即重启定时器（对位 mac setAutoUpdate「改完立即生效」，
     * 此设置不走草稿/保存流）。写失败如实回传给界面。
     */
    fun setAutoUpdate(cfg: AutoUpdateSettings): String? {
        val err = ConfStore.writeAuto(cfg)
        if (err == null) restartAutoTimer()
        return err
    }

    /**
     * （重）建定时器。必须先收掉旧的——否则每次调用都多挂一个周期协程
     * （mac 原话：面板开关 N 次 ⇒ N 个幽灵 timer）。hours ≤ 0 = 关闭，不挂。
     * 首轮延迟 10 分钟：避免「刚打开应用就全量更新」（mac firstRunTimer 600s 同款纪律）。
     */
    fun restartAutoTimer() {
        autoTimerJob?.cancel()
        autoTimerJob = null
        val cfg = ConfStore.readAuto()
        if (cfg.hours <= 0) return
        autoTimerJob = scope.launch {
            delay(600_000L)
            while (isActive) {
                runScheduledUpdate(cfg.deep)
                delay(cfg.hours * 3_600_000L)
            }
        }
    }

    /** 周期到点的那次更新（对位 mac runScheduledUpdate：busy 时不叠加，失败不静默）。 */
    private suspend fun runScheduledUpdate(deep: Boolean) {
        if (_busyAction.value || _refreshing.value) return
        val track = L10n.t(if (deep) "bulk.deepWord" else "bulk.shallowWord")
        try {
            val r = engine.updateAll(deep)
            val ok = decodeUpdateOutcomes(r).count { it is UpdateOutcome.Success }
            _lastResult.value = L10n.t("cmp.update.schedDone", track, ok, r.results.size)
        } catch (e: Exception) {
            _lastResult.value = L10n.t("cmp.update.schedFailed", track, e.message)
        }
        refreshAll()
    }

    private var pollJob: Job? = null

    /** refreshAll：status → dashboard → milestones（失败不短路后续——尽力而为，逐源披露）。 */
    fun refreshAll() {
        if (_refreshing.value) return
        scope.launch {
            _refreshing.value = true
            try {
                try {
                    _status.value = engine.status()
                    _statusState.value = LoadState.Loaded
                    // 刷新时间戳只在 status 成功时记（mac Model.swift:485-492：status 失败
                    // 提前 return、不更新 lastRefreshed——「读不出来」不算「刷新过」）
                    _lastRefreshed.value = java.time.LocalDateTime.now()
                } catch (e: Exception) {
                    _statusState.value = LoadState.Failed(e.message ?: L10n.t("cmp.err.statusRead"))
                    _lastError.value = e.message
                }
                try {
                    _dashboard.value = engine.dashboard()
                    _dashState.value = LoadState.Loaded
                } catch (e: Exception) {
                    _dashState.value = LoadState.Failed(e.message ?: L10n.t("cmp.err.dashRead"))
                }
                try {
                    _milestones.value = engine.milestoneList()
                    _msState.value = LoadState.Loaded
                } catch (e: Exception) {
                    _msState.value = LoadState.Failed(e.message ?: L10n.t("cmp.err.msRead"))
                }
            } finally {
                _refreshing.value = false
            }
        }
    }

    /** C2 周期轮询（默认 5 分钟，与 mac/BUI 一致）。 */
    fun startPolling(periodMs: Long = 300_000) {
        pollJob?.cancel()
        pollJob = scope.launch {
            while (isActive) {
                delay(periodMs)
                refreshAll()
            }
        }
    }

    fun stop() {
        pollJob?.cancel()
        autoTimerJob?.cancel()
        scope.cancel()
    }
}

/**
 * 一键说明任务串（纯函数，判据见 BriefTaskTest）。口径逐句对位 mac 基准，不发明问题：
 * - project = null（或空白，defensive）→ 项目群说明：mac GroupBriefButton 的固定问题
 *   （AIIntegration.swift:439，target .group）；
 * - project = 名称 → 单项目说明：mac AgentCore.projectBrief 的四段式问题
 *   （AgentCore.swift:469-476，target .project(name)）。
 */
fun briefTask(project: String?): String =
    if (project.isNullOrBlank()) {
        // mac 基准单行问题，字句保持一致
        "生成一份项目群说明（markdown）：项目构成与定位、各项目一句话现状、需要人处理的事项（未提交/停滞/待合入）、整体建议。400 字以内。"
    } else {
        // mac 基准多行问题（Swift 多行字面量去除缩进后的原文；引号是 ASCII 直引号）
        """
        为项目「${project}」生成一份**项目说明**（markdown），包含：
        1. 一句话定位（结合 README 与代码构成判断它是什么）
        2. 当前状态（分支进度、未提交/未跟踪/stash、最近活跃）
        3. 工程结构要点（语言构成、热点文件）
        4. 风险与建议下一步
        要求：面向"第一次接触这个项目的人"，500 字以内，具体、可执行、不编造。
        """.trimIndent()
    }
