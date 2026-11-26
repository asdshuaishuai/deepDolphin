// Engine.kt —— 引擎命令封装（C1/C2/C4/C8/C9 的数据动作层）。
//
// 【单一入口】全部经 EngineLocator.run（子进程 + NO_COLOR）；UI 一律在协程 IO 里调。
// 【超时预算】与 mac/BUI 对位：宁可等也不要半截数据。

package canopy.engine

import canopy.ui.L10n
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

open class EngineException(val userMessage: String, cause: Throwable? = null) : Exception(userMessage, cause)

/** 用户主动停止了这次引擎调用（mac StopDecision：stopped ≠ failed，不报成失败）。 */
class EngineStoppedException : EngineException("stopped")

open class Engine(val bin: String) {

    companion object {
        /**
         * merge 回传的 algorithm 载荷编码器（mergePatchConfidence 用）：
         * 显式 null（contractJson 的 explicitNulls=false 会把 signals 里的
         * null 键——S4/S7 = 分母 0 的披露事实——整个丢掉）+ 缺省值照发
         * （投影不重写字段清单）。internal：判据直接测这一份，不复制配置。
         */
        internal val mergeRoundTripJson: Json =
            Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }


    private val quiet = listOf("--json", "--quiet")
    private val json = listOf("--json")

    /**
     * 引擎 JSON 调用的唯一入口。失败判定两条（二次验证抓到：两条都曾缺失，失败被报成成功）：
     *   1. exit≠0 = 这次调用失败，**即便 stdout 能解码**——引擎失败时打的是裸 {error,code,message}
     *      或 {code,message}，按回执解码会得到全默认值，界面显示「文档 0 处变更 ✓」。
     *      只有 status 享「exit≠0 但载荷完整」的待遇（全部项目采集失败也先打完整 JSON 再 exit 1）。
     *   2. 原因优先级：stdout 里的 message → stderr 首个非空行 → stdout 首行 → 「无输出」。
     */
    private suspend fun <T> call(
        serializer: KSerializer<T>,
        args: List<String>,
        timeoutSec: Long = 300,
        tolerateNonZeroExit: Boolean = false,
    ): T = withContext(Dispatchers.IO) {
        val full = args + json
        val (rc, out, err) = EngineLocator.runSplit(bin, full, timeoutSec)
        if (rc == EngineLocator.STOPPED_RC) throw EngineStoppedException()
        val stderrWhy = err.trim().lineSequence().firstOrNull { it.isNotBlank() }
        fun fail(cause: Throwable? = null): Nothing = throw EngineException(
            L10n.t("err.exitCode", rc) + "：" + (
                engineMessageOf(out)
                    ?: stderrWhy
                    ?: out.trim().lineSequence().firstOrNull()?.take(120)
                    ?: L10n.t("cmp.err.noOutput")
                ),
            cause,
        )
        if (rc != 0 && !tolerateNonZeroExit) fail()
        try {
            decodeOrThrow(serializer, out)
        } catch (e: Exception) {
            if (rc != 0) fail(e)
            throw EngineException(
                L10n.t("cmp.err.contract", e.message ?: "") + (stderrWhy?.let { "；$it" } ?: ""),
                e,
            )
        }
    }

    /** stdout 是错误信封时取出引擎给的 message；不是（或解析不了）返回 null。 */
    internal fun engineMessageOf(out: String): String? = try {
        Json.parseToJsonElement(out).let { it as? kotlinx.serialization.json.JsonObject }
            ?.get("message")?.let { it as? kotlinx.serialization.json.JsonPrimitive }?.takeIf { v -> v.isString }?.content
    } catch (_: Exception) {
        null
    }

    private suspend fun callRaw(args: List<String>, timeoutSec: Long = 300): String =
        withContext(Dispatchers.IO) {
            val (rc, out, err) = EngineLocator.runSplit(bin, args + json, timeoutSec)
            if (rc == EngineLocator.STOPPED_RC) throw EngineStoppedException()
            if (rc != 0) throw EngineException(
                L10n.t("err.exitCode", rc) + "：" + (
                    engineMessageOf(out)
                        ?: err.trim().lineSequence().firstOrNull { it.isNotBlank() }
                        ?: out.trim().lineSequence().firstOrNull() ?: L10n.t("cmp.err.noOutput")
                ),
            )
            out
        }

    // ── 读 ──
    suspend fun status(project: String? = null): StatusEnvelope =
        call(
            StatusEnvelope.serializer(),
            listOf("status") + (project?.let { listOf(it) } ?: emptyList()),
            60,
            tolerateNonZeroExit = true, // 有项目采集失败时引擎先打完整 JSON 再 exit 1：载荷要保留
        )

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

    // ── 图谱渲染（render index/arch：文本回执 + 产物路径；mac EngineCLI.runData 原样 args 的对位）──
    //
    // 这族命令的 stdout 是人读回执（「已重绘/已复用（产物未变）：路径 · 版本」），不是 JSON——
    // 不走 call()/callRaw()（它们会附加 --json，且失败时丢弃 stderr 原因）。
    // 回执末行/产物路径/复用判定的提取是纯函数，判据在 ui/GraphPages.kt 的 GraphParseTest。

    /** render index/arch：成功返回 stdout 全文；失败抛 EngineException（stderr 原因已在消息里）。 */
    suspend fun renderGraph(kind: String, project: String, withConfidence: Boolean = false, force: Boolean = false): String =
        withContext(Dispatchers.IO) {
            require(kind == "index" || kind == "arch") { L10n.t("cmp.err.renderKind", kind) }
            val args = mutableListOf("render", kind, project)
            if (withConfidence) args += "--confidence"
            // --force：引擎的「产物未变」复用不看置信度快照有没有新出现——纯结构旧产物
            // 会被一直复用，热力图永远缺席；数据就绪后必须强制重绘一次
            if (force) args += "--force"
            // 600s 对位 mac render 超时预算：整库重绘是分钟级，宁可等也不要半截
            val (rc, out) = EngineLocator.runMerged(bin, args, 600)
            if (rc != 0) throw EngineException(
                L10n.t("cmp.err.renderFail", kind, project, rc,
                    out.trim().lineSequence().firstOrNull() ?: L10n.t("cmp.err.noOutput")),
            )
            out
        }

    /**
     * confidence gen <项目>：生成置信度快照（confidence.json）——代码图谱热力图的**数据源**。
     * 二次验证抓到：全工程只跑 render index --confidence、从不生成快照；快照缺席时引擎只出
     * 纯结构图（回执自己写明「无置信度数据——本页只呈现结构」）。
     */
    suspend fun confidenceGen(project: String): String = withContext(Dispatchers.IO) {
        val (rc, out) = EngineLocator.runMerged(bin, listOf("dendro", "gen", project, "--format", "text"), 300)
        if (rc == EngineLocator.STOPPED_RC) throw EngineStoppedException()
        if (rc != 0) throw EngineException(
            L10n.t("err.exitCode", rc) + "：" + (out.trim().lineSequence().firstOrNull { it.isNotBlank() } ?: L10n.t("cmp.err.noOutput")),
        )
        out
    }

    // ── 置信度体检 / 补丁体检（mac GraphScene.swift:32-68 同形态；形状以真机实测锚定，
    //    fixtures/confidence/ 三份 JSON 即本机引擎真跑落盘）──

    /** graph confidence <项目> --json：六维度 + findings（mac loadConfidence 对位，300s 预算同款）。 */
    suspend fun graphConfidence(project: String): ConfidenceReport =
        call(ConfidenceReport.serializer(), listOf("dendro", "check", project), 300)

    /**
     * graph confidence <项目> --llm：出的是纯文本提示词（直接可喂模型），不是 JSON——
     * 不走 call()（会附加 --json）。stdout/stderr 分流：提示词要进剪贴板，引擎写在
     * stderr 的迁移提示等杂音不得混入；失败原因取 stderr 首个非空行。mac confidencePrompt 对位。
     */
    suspend fun graphConfidencePrompt(project: String): String =
        withContext(Dispatchers.IO) {
            val (rc, out, err) = EngineLocator.runSplit(bin, listOf("dendro", "check", project, "--llm"), 300)
            if (rc != 0) throw EngineException(
                L10n.t("cmp.err.renderConfFail", project, rc,
                    err.trim().lineSequence().firstOrNull { it.isNotBlank() }
                        ?: out.trim().lineSequence().firstOrNull() ?: L10n.t("cmp.err.noOutput")),
            )
            out
        }

    /**
     * graph patchconf <项目> --patch <diff文件> --json（Layer 1）：diff 文本写临时文件、
     * 跑完即删（mac GraphScene.swift:44-50 同形态）。
     */
    suspend fun patchConfidence(project: String, diffText: String): PatchConfidence =
        withContext(Dispatchers.IO) {
            val tmp = kotlin.io.path.createTempFile(prefix = "canopy-patch-", suffix = ".diff").toFile()
            try {
                tmp.writeText(diffText)
                call(PatchConfidence.serializer(), listOf("dendro", "patch", project, "--patch", tmp.absolutePath), 300)
            } finally {
                tmp.delete()
            }
        }

    /**
     * graph patchconf --merge <alg> <agent> --json（Layer 3 终稿）：两份 JSON 写临时文件、
     * 跑完即删（mac mergePatch 对位；algorithm = Layer1 原样回传，agent = 人工裁决条目）。
     *
     * 【编码器口径】回传的 algorithm 必须保留 signals 里的 null 键（S4/S7 = 分母 0 的
     * 披露事实）——contractJson 的 explicitNulls=false 会把 Map 里的 null 值丢掉，
     * 这里用 mergeRoundTripJson 忠实往返（缺省值也照发，投影不重写字段清单）。
     */
    suspend fun mergePatchConfidence(algorithm: PatchConfidence, agent: AgentPayload): MergedConfidence =
        withContext(Dispatchers.IO) {
            val algFile = kotlin.io.path.createTempFile(prefix = "dd-alg-", suffix = ".json").toFile()
            val agentFile = kotlin.io.path.createTempFile(prefix = "dd-agent-", suffix = ".json").toFile()
            try {
                algFile.writeText(mergeRoundTripJson.encodeToString(PatchConfidence.serializer(), algorithm))
                agentFile.writeText(mergeRoundTripJson.encodeToString(AgentPayload.serializer(), agent))
                call(
                    MergedConfidence.serializer(),
                    listOf("dendro", "merge", algFile.absolutePath, agentFile.absolutePath),
                    120,
                )
            } finally {
                algFile.delete()
                agentFile.delete()
            }
        }
}
