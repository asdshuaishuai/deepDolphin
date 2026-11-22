// Engine.kt —— 引擎命令封装（C1/C2/C4/C8/C9 的数据动作层）。
//
// 【单一入口】全部经 EngineLocator.run（子进程 + NO_COLOR）；UI 一律在协程 IO 里调。
// 【超时预算】与 mac/BUI 对位：宁可等也不要半截数据。

package deepdolphin.engine

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer

class EngineException(val userMessage: String, cause: Throwable? = null) : Exception(userMessage, cause)

open class Engine(val bin: String) {

    private val quiet = listOf("--json", "--quiet")
    private val json = listOf("--json")

    private suspend fun <T> call(
        serializer: KSerializer<T>,
        args: List<String>,
        timeoutSec: Long = 300,
    ): T = withContext(Dispatchers.IO) {
        val full = args + json
        val (rc, out) = EngineLocator.run(bin, full, timeoutSec)
        // 契约 §4.3：exit≠0 但 stdout 可解析 → failedWithPayload，载荷保留
        //（引擎把失败原因写进 stdout：全部项目采集失败也先打印完整 JSON 再 exit 1）。
        // 只有 stdout 不可解析才是真失败。
        try {
            decodeOrThrow(serializer, out)
        } catch (e: Exception) {
            if (rc == 0) {
                throw EngineException("引擎输出不是合法契约（可能契约过旧）：${e.message}", e)
            }
            throw EngineException(
                "引擎退出码 $rc：${out.trim().lineSequence().firstOrNull()?.take(120) ?: "无输出"}",
                e,
            )
        }
    }

    private suspend fun callRaw(args: List<String>, timeoutSec: Long = 300): String =
        withContext(Dispatchers.IO) {
            val (rc, out) = EngineLocator.run(bin, args + json, timeoutSec)
            if (rc != 0) throw EngineException("引擎退出码 $rc：${out.trim().lineSequence().firstOrNull() ?: "无输出"}")
            out
        }

    // ── 读 ──
    suspend fun status(project: String? = null): StatusEnvelope =
        call(StatusEnvelope.serializer(), listOf("status") + (project?.let { listOf(it) } ?: emptyList()), 60)

    suspend fun dashboard(): DashboardData = call(DashboardData.serializer(), listOf("dashboard"), 180)

    suspend fun milestoneList(): MilestoneList = call(MilestoneList.serializer(), listOf("milestone", "list"), 60)

    suspend fun docs(project: String): DocsPayload = call(DocsPayload.serializer(), listOf("docs", project), 60)

    suspend fun journal(project: String, limit: Int = 30): JournalPayload =
        call(JournalPayload.serializer(), listOf("journal", project, "--limit", limit.toString()), 60)

    suspend fun tools(): String = callRaw(listOf("tools"), 30)

    // ── 写（C9）──
    suspend fun milestoneAdd(project: String, name: String, tag: String?, date: String?, desc: String?): MilestoneAddReceipt {
        val args = mutableListOf("milestone", "add", project, name)
        if (!tag.isNullOrBlank()) args += listOf("--tag", tag)
        if (!date.isNullOrBlank()) args += listOf("--date", date)
        if (!desc.isNullOrBlank()) args += listOf("--desc", desc)
        return call(MilestoneAddReceipt.serializer(), args, 60)
    }

    /** action ∈ done|reopen|drop（UI 词 open → CLI reopen 由调用方转换）。 */
    suspend fun milestoneAction(project: String, name: String, action: String): MilestoneActionReceipt =
        call(MilestoneActionReceipt.serializer(), listOf("milestone", action, project, name), 60)

    suspend fun milestoneRemove(project: String, name: String): MilestoneRemoveReceipt =
        call(MilestoneRemoveReceipt.serializer(), listOf("milestone", "remove", project, name), 60)

    // ── git（C8 白名单）──
    suspend fun gitOp(op: String, project: String, message: String? = null): GitOpResponse {
        val args = mutableListOf("git", op, project)
        if (!message.isNullOrBlank()) args += listOf("--message", message)
        return call(GitOpResponse.serializer(), args, 120)
    }

    // ── 更新（C4：浅/深；单项目/全项目）──
    suspend fun update(project: String, deep: Boolean): UpdateReceipt =
        call(UpdateReceipt.serializer(), listOf(if (deep) "deep" else "update", project) + quiet, deepTimeout(deep, false))

    suspend fun updateAll(deep: Boolean): MultiResults =
        call(MultiResults.serializer(), listOf(if (deep) "deep" else "update") + quiet, deepTimeout(deep, true))

    private fun deepTimeout(deep: Boolean, all: Boolean): Long = when {
        deep && all -> 1800L
        deep -> 600L
        all -> 900L
        else -> 300L
    }

    // ── 项目群管理 ──
    suspend fun scan(root: String, depth: Int): ScanPayload =
        call(ScanPayload.serializer(), listOf("scan", root, "--depth", depth.toString()), 300)

    suspend fun addProject(path: String, name: String?): RegistryEntry {
        val args = mutableListOf("add", path)
        if (!name.isNullOrBlank()) args += listOf("--name", name)
        return call(RegistryEntry.serializer(), args, 30)
    }

    suspend fun removeProject(name: String): RegistryEntry =
        call(RegistryEntry.serializer(), listOf("remove", name), 30)

    suspend fun renderCheck(artifact: String, project: String): Pair<Boolean, String> =
        withContext(Dispatchers.IO) {
            val (rc, out) = EngineLocator.run(bin, listOf("render", "check", artifact, project) + json, 30)
            Pair(rc == 0, out)
        }
}
