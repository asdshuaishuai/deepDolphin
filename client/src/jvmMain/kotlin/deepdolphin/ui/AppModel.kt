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
