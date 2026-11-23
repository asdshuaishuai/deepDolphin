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

    // ── 批 2：路由 + 详情 + 写操作反馈 ──
    // 对位 mac：侧栏没有 AI 入口——AI 以 agent sheet 形态从详情页（深浅更新旁）触发，
    // 设置（含 AI tab）收在侧栏最底部「设置」（mac 原生 Settings scene 的 Linux 对位）。
    enum class Route { DASHBOARD, BOARD, MILESTONES, PROJECT, SETTINGS }
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
                _detailState.value = LoadState.Failed(e.message ?: "详情读取失败")
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
            withAction("新建里程碑 $name") { engine.milestoneAdd(project, name, tag, date, desc) }
        }
    }

    fun milestoneAction(project: String, name: String, action: String) {
        scope.launch {
            withAction("里程碑 $name ${action}ed") { engine.milestoneAction(project, name, action) }
        }
    }

    fun milestoneRemove(project: String, name: String) {
        scope.launch {
            withAction("删除里程碑 $name") { engine.milestoneRemove(project, name) }
        }
    }

    // ── 项目群管理：扫描 / 添加（空态 CTA 与引擎 scan/add 的接线；结果如实披露）──
    fun scanProjects(root: String, depth: Int) {
        scope.launch {
            withAction("扫描 $root") {
                val r = engine.scan(root, depth)
                buildString {
                    append("扫描 $root（深度 $depth）：发现 ${r.found} · 新增 ${r.added} · 已在册 ${r.existing} · 访问目录 ${r.dirsVisited}")
                    if (r.truncated == true) append("（结果被截断）")
                    if (r.depthCapped == true) append("（深度被封顶）")
                    if (r.unreadable > 0) append(" · ${r.unreadable} 个目录读不出来")
                }
            }
        }
    }

    fun addProjectPath(path: String, name: String?) {
        scope.launch {
            withAction("添加项目 $path") {
                val r = engine.addProject(path, name)
                "添加项目成功：${r.name.ifBlank { path }}"
            }
        }
    }

    // ── C8 git 白名单六操作 ──
    fun gitOp(op: String, project: String, message: String? = null) {
        scope.launch {
            withAction("git $op $project") {
                val r = engine.gitOp(op, project, message)
                "git $op $project：${r.output.take(160)}"
            }
        }
    }

    // ── C4 更新（浅/深；单项目/全项目）──
    fun updateProject(name: String, deep: Boolean) {
        scope.launch {
            withAction("${if (deep) "深更新" else "浅更新"} $name") {
                val r = engine.update(name, deep)
                "${if (deep) "深更新" else "浅更新"} $name：文档 ${r.docs.count { it.changed || it.created }} 处变更"
            }
        }
    }

    fun updateAll(deep: Boolean) {
        scope.launch {
            withAction("全部${if (deep) "深更新" else "浅更新"}") {
                val r = engine.updateAll(deep)
                val ok = r.results.count { it.ok }
                "全部${if (deep) "深更新" else "浅更新"}：${ok}/${r.results.size} 成功"
            }
        }
    }

    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

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
                } catch (e: Exception) {
                    _statusState.value = LoadState.Failed(e.message ?: "status 读取失败")
                    _lastError.value = e.message
                }
                try {
                    _dashboard.value = engine.dashboard()
                    _dashState.value = LoadState.Loaded
                } catch (e: Exception) {
                    _dashState.value = LoadState.Failed(e.message ?: "dashboard 读取失败")
                }
                try {
                    _milestones.value = engine.milestoneList()
                    _msState.value = LoadState.Loaded
                } catch (e: Exception) {
                    _msState.value = LoadState.Failed(e.message ?: "milestones 读取失败")
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
