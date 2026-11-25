// AppModel.kt —— 进程级数据编排（mac Model.swift / archive-bui appstate 对位）。
//
// 【纪律】每数据源一份自己的 LoadState（不共用 lastError）；UI 只消费 StateFlow；
// 所有引擎调用在 Dispatchers.IO；refreshAll 顺序 status → dashboard → milestones。

package deepdolphin.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
    // GRAPH / ARCH：代码图谱与架构图——跟着仓库走的独立页面（用户定稿 2026-11-25：不弹窗，
    // 专门一页，入口在各仓库详情里）。与 mac 的「独立最大化窗口」不同，以用户定稿为准。
    enum class Route { DASHBOARD, BOARD, MILESTONES, CONFIDENCE, PATCHCHECK, PROJECT, GRAPH, ARCH, SETTINGS }

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

    // 图谱两页是路由（Route.GRAPH / Route.ARCH）+ selectedProject（仓库）——不再是开合流 + 弹窗。
    // 单仓库锁定：入口处定死，页面内无切换；「返回仓库」回 Route.PROJECT。

    /** 返回当前仓库的详情页（图谱两页的「返回仓库」）。 */
    fun backToRepo() {
        _selectedProject.value?.let { goRoute(Route.PROJECT, it) }
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
     * 成功后先把产物路径记进进程内缓存再进页：页 init 即命中缓存先出图，
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
                val text = renderGraph(kind, project, allowForce = true)
                val path = extractHtmlPath(text)
                if (path == null) {
                    _lastResult.value =
                        L10n.t("cmp.update.renderFailNoPath", kind.titleWord(), project, receiptLine(text) ?: L10n.t("cmp.err.noOutput"))
                } else {
                    rememberGraphArtifact(kind, project, path)
                    goRoute(kind.route, project)
                }
            } catch (e: Exception) {
                _lastResult.value = L10n.t("cmp.update.renderFail", kind.titleWord(), project, e.message ?: e.javaClass.simpleName)
            } finally {
                _graphRendering.value = null
            }
        }
    }

    /**
     * 图谱渲染的统一口径——详情页入口与图谱页自身（深链直达、页内刷新）共用，不各写一套。
     * [allowForce] = 这次是「真的在出图」（首开/刷新）：代码图谱的热力图以置信度快照为数据源，
     * 先出快照再渲染；每个仓库每会话首次强制重绘一次（旧的纯结构产物不 --force 会被一直复用）。
     * false = 先秒出缓存产物后的后台核验，只问引擎「还新鲜吗」（复用就不重载，画面不闪）。
     * 快照生成失败不堵路（仍出结构图），但写进结果行说出来——否则用户以为这个仓库没有热点。
     * 返回引擎原始输出。
     */
    suspend fun renderGraph(kind: GraphKind, project: String, allowForce: Boolean): String {
        var confNote: String? = null
        val force = allowForce && kind == GraphKind.INDEX && graphForcedThisSession.add(project)
        if (force) {
            try {
                engine.confidenceGen(project)
            } catch (e: Exception) {
                confNote = e.message ?: e.javaClass.simpleName
            }
        }
        val text = engine.renderGraph(kind.cliKind, project, withConfidence = kind == GraphKind.INDEX, force = force)
        // 后台核验不改写结果行（别把上一条写操作的结果冲掉）；真的出图时这条就是最新结果
        if (allowForce || confNote != null) {
            _lastResult.value = confNote?.let { L10n.t("cmp.graph.confSkipped", it) }
        }
        return text
    }

    /** 本次会话里已经强制重绘过图谱的仓库（见 [renderGraph] 的 force 说明）。 */
    private val graphForcedThisSession = HashSet<String>()

    private val _detail = MutableStateFlow<StatusEnvelope?>(null) // status <name> 单项目信封
    val detail: StateFlow<StatusEnvelope?> = _detail.asStateFlow()
    private val _detailState = MutableStateFlow<LoadState>(LoadState.Loading)
    val detailState: StateFlow<LoadState> = _detailState.asStateFlow()

    private val _docs = MutableStateFlow<DocsPayload?>(null)
    val docs: StateFlow<DocsPayload?> = _docs.asStateFlow()

    /** 写操作结果一行（「写操作必须留结果」纪律）；null = 无。 */
    private val _lastResult = MutableStateFlow<String?>(null)
    val lastResult: StateFlow<String?> = _lastResult.asStateFlow()
    private val _busyAction = MutableStateFlow(false)
    val busyAction: StateFlow<Boolean> = _busyAction.asStateFlow()

    fun goRoute(r: Route, project: String? = null) {
        // 图谱页没有仓库就没有主体：没点名时落列表里的第一个（深链 --section graph 不带 --project），
        // 一个项目都没有时留给页面自己的空态如实说
        var target = project
        if ((r == Route.GRAPH || r == Route.ARCH) && target.isNullOrBlank()) {
            target = _status.value?.projects?.firstOrNull { it.isReadable }?.name ?: _status.value?.projects?.firstOrNull()?.name
        }
        if (r.isRepoScoped() && target != null) {
            // 项目列表已到且不含该名 = 真不存在（mac Router 守卫对位）；
            // 列表还没到时不能判「不存在」——不知道 ≠ 没有，那会废掉深链
            val env = _status.value
            if (env != null && env.projects.none { it.name == target }) {
                _lastError.value = L10n.t("cmp.route.noProject", target)
                _route.value = Route.DASHBOARD
                _selectedProject.value = null
                return
            }
        }
        _route.value = r
        _selectedProject.value = target
        if (r == Route.PROJECT && target != null) loadDetail(target)
    }

    /** 详情请求序号：快速连点两个项目时，慢的后到不得覆盖先到的（否则标题是 B、内容是 A）。 */
    private val detailRequest = java.util.concurrent.atomic.AtomicInteger(0)

    /** 单项目详情：status <n>（含内嵌进度日志）→ docs（增强源，失败不短路）。 */
    fun loadDetail(name: String) {
        val req = detailRequest.incrementAndGet()
        // 先清掉上一个项目的内容，别让 A 的卡片挂在 B 的标题下
        _detail.value = null
        _docs.value = null
        scope.launch {
            _detailState.value = LoadState.Loading
            try {
                val got = engine.status(name)
                if (req == detailRequest.get()) {
                    _detail.value = got
                    _detailState.value = LoadState.Loaded
                }
            } catch (e: Exception) {
                if (req == detailRequest.get()) _detailState.value = LoadState.Failed(e.message ?: L10n.t("cmp.err.detailRead"))
            }
            // docs 是增强源：失败不短路详情页（托管文档卡按「未披露」如实显示）
            try {
                val got = engine.docs(name)
                if (req == detailRequest.get()) _docs.value = got
            } catch (_: Exception) {
                if (req == detailRequest.get()) _docs.value = null
            }
        }
    }

    /** 关掉页面顶部的反馈条（写操作结果 / 错误）。 */
    fun dismissFeedback() {
        _lastResult.value = null
        _lastError.value = null
    }

    /** 有更新进程在跑才允许「停止更新」（mac canStopUpdate 对位）。 */
    val canStopUpdate: Boolean get() = deepdolphin.engine.EngineLocator.runningUpdateCount() > 0

    private suspend fun <T> withAction(
        label: String,
        successOf: (T) -> String? = { null },
        block: suspend () -> T,
    ): T? {
        // busy 时不许静默吞掉（用户点了没反应 = 不知道为什么）
        if (_busyAction.value) {
            _lastResult.value = L10n.t("cmp.action.busySkipped", label)
            return null
        }
        _busyAction.value = true
        try {
            val r = block()
            // 动作自己算好的结果行优先（「文档 N 处变更」原来被丢，只剩一个 ✓）
            _lastResult.value = successOf(r) ?: "$label ✓"
            refreshAll()
            // 正在看某个项目详情时，写操作之后要把详情重读一遍——否则脉搏/改动构成/日志
            // 还是操作前的数字，用户看到的是「点了没效果」
            if (_route.value == Route.PROJECT) _selectedProject.value?.let { loadDetail(it) }
            return r
        } catch (e: EngineStoppedException) {
            _lastResult.value = L10n.t("cmp.update.stopped", label)
            return null
        } catch (e: Exception) {
            _lastResult.value = "$label ✗ ${e.message}"
            return null
        } finally {
            _busyAction.value = false
        }
    }

    // ── C9 里程碑 CRUD（结果行按回执如实：建没建 / 生效没生效）──

    fun milestoneAdd(project: String, name: String, tag: String?, date: String?, desc: String?) {
        scope.launch {
            withAction(L10n.t("cmp.action.msAdd", name), successOf = { r ->
                if (r.created) L10n.t("cmp.ms.added", name) else L10n.t("cmp.ms.existed", name)
            }) { engine.milestoneAdd(project, name, tag, date, desc) }
        }
    }

    fun milestoneAction(project: String, name: String, action: String) {
        scope.launch {
            withAction(L10n.t("cmp.action.msActionLabel", name), successOf = { r -> msActionOutcome(r) }) {
                engine.milestoneAction(project, name, action)
            }
        }
    }

    fun milestoneRemove(project: String, name: String) {
        scope.launch {
            withAction(L10n.t("cmp.action.msRemove", name), successOf = { r ->
                if (r.removed) L10n.t("cmp.ms.removed", name) else L10n.t("cmp.ms.notRemoved", name)
            }) { engine.milestoneRemove(project, name) }
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
            withAction("$word $name", successOf = { it }) {
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

    /** 仪表盘筛选（时间跨度 + 提交类型；mac model.dashFilter 对位）：切页不丢。 */
    var dashFilter by mutableStateOf(DashFilter())

    /**
     * 双轨动作 / 重新索引的统一入口（mac Model.runUpdate 对位）：
     * 范围 = 单项目 → 直接跑（用户正盯着那个仓库，按钮上的范围文案就是确认）；
     * 范围 = 全部 → 先弹告知式确认。仪表盘「重新索引」原来直接调 updateAll，绕过了确认。
     */
    fun runUpdate(deep: Boolean) {
        // 「更新动作打在谁身上」用 updateScope（mac 同款：与范围选择器的 choice 是两个公式）
        val scoped = WorkBarScope.updateScope(_route.value, _selectedProject.value)
        if (scoped != null) updateProject(scoped, deep) else requestBulkUpdate(deep)
    }

    /** 双轨按钮「· 全部」范围先弹告知式确认（不直接跑——批量更新会改写多个仓库的托管区域）。 */
    fun requestBulkUpdate(deep: Boolean) {
        if (_busyAction.value) return
        _pendingBulk.value = deep
    }

    fun cancelBulkUpdate() {
        _pendingBulk.value = null
    }

    /**
     * 停止更新（mac 菜单栏「停止更新」+ StopDecision 对位）：只终止 update/deep 的引擎子进程本体，
     * 不碰并行的读取/扫描/图谱渲染；先 SIGTERM 再强杀。被停的那次更新报「已停止」，不报失败。
     */
    fun stopUpdate() {
        // terminateUpdates 最多阻塞 2 秒：放到协程里，别卡界面线程
        scope.launch {
        val n = deepdolphin.engine.EngineLocator.terminateUpdates()
        _lastResult.value = when {
            n == 1 -> L10n.t("cmp.stop.one")
            n > 1 -> L10n.t("cmp.stop.many", n)
            else -> L10n.t("cmp.stop.already", _status.value?.projects?.size ?: 0)
        }
        }
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
                _lastResult.value = if (e is EngineStoppedException) {
                    L10n.t("cmp.update.stoppedAll", L10n.t(if (deep) "update.deepWord" else "update.shallowWord"))
                } else {
                    L10n.t("cmp.update.allFailed", L10n.t(if (deep) "update.deepWord" else "update.shallowWord"), e.message ?: L10n.t("cmp.err.engineCall"))
                }
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
        // 必须过 busy 闸门：原来直接调引擎不置 busy，跑的十几分钟里界面显示「空闲」、
        // 更新按钮可点，用户能再发起一次并写同一批托管文档
        _busyAction.value = true
        try {
            val r = engine.updateAll(deep)
            val ok = decodeUpdateOutcomes(r).count { it is UpdateOutcome.Success }
            _lastResult.value = L10n.t("cmp.update.schedDone", track, ok, r.results.size)
        } catch (e: EngineStoppedException) {
            _lastResult.value = L10n.t("cmp.update.stoppedAll", track)
        } catch (e: Exception) {
            _lastResult.value = L10n.t("cmp.update.schedFailed", track, e.message)
        } finally {
            _busyAction.value = false
        }
        refreshAll()
    }

    private var pollJob: Job? = null

    private val refreshQueued = java.util.concurrent.atomic.AtomicBoolean(false)

    /**
     * refreshAll：status → dashboard → milestones（失败不短路后续——尽力而为，逐源披露）。
     * 刷新进行中又来一次（写操作之后的刷新撞上 5 分钟轮询）要**合并**而不是丢弃——
     * 丢弃会让界面停在旧数据直到下次轮询。
     */
    fun refreshAll() {
        if (!refreshQueued.compareAndSet(false, true)) return // 已有刷新在排队/进行：合并
        scope.launch {
            do {
                refreshQueued.set(false)
                _refreshing.value = true
                try {
                    try {
                        _status.value = engine.status()
                        _statusState.value = LoadState.Loaded
                        // 刷新时间戳只在 status 成功时记（mac Model.swift:485-492：status 失败
                        // 提前 return、不更新 lastRefreshed——「读不出来」不算「刷新过」）
                        _lastRefreshed.value = java.time.LocalDateTime.now()
                        // 一次瞬时读取失败不该永远挂着（mac Model.swift:475：成功即清）
                        _lastError.value = null
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
            } while (refreshQueued.getAndSet(false))
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

/** 仓库级页面：详情 + 跟仓库走的图谱两页。页面主体就是选中的那个仓库——侧栏高亮它、
 *  更新范围收敛到它、换仓库即换页。 */
fun AppModel.Route.isRepoScoped(): Boolean =
    this == AppModel.Route.PROJECT || this == AppModel.Route.GRAPH || this == AppModel.Route.ARCH

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

/**
 * 里程碑状态操作的结果行（契约 §3.8）。报「实际生效状态」而不是请求的动作：
 * applied=false = 写入被「同名 tag 已存在即自动 done」规则压回——那不是成功，必须说出来。
 * 纯函数，判据直接测（原来拼成「doneed / droped」，且 applied=false 也显示 ✓）。
 */
internal fun msActionOutcome(r: deepdolphin.engine.MilestoneActionReceipt): String {
    val verb = when (r.status) {
        "done" -> L10n.t("cmp.ms.doneOk", r.milestone)
        "dropped" -> L10n.t("cmp.ms.dropOk", r.milestone)
        "open" -> L10n.t("cmp.ms.reopenOk", r.milestone)
        else -> L10n.t("cmp.ms.nowStatus", r.milestone, r.status)
    }
    return if (r.applied) verb else verb + L10n.t("cmp.ms.notApplied", r.requested, r.status)
}
