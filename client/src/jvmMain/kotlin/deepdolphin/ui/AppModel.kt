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
    enum class Route { DASHBOARD, BOARD, MILESTONES, PROJECT, SETTINGS, AI_CHAT }
    private val _route = MutableStateFlow(Route.DASHBOARD)
    val route: StateFlow<Route> = _route.asStateFlow()
    private val _selectedProject = MutableStateFlow<String?>(null)
    val selectedProject: StateFlow<String?> = _selectedProject.asStateFlow()

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
