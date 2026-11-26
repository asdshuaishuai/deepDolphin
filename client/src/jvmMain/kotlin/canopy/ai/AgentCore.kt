// AgentCore.kt —— agent 工具循环（≤4 轮；deepin AgentCore 的 Kotlin 对位）。
//
// 【单一来源红线】必填参数只从「已发给模型的那份」工具定义取（requiredParamsByTool）。
// 【取消】逐轮检查 + 工具执行中切片响应（stopAI 真杀引擎子进程）。

package canopy.ai

import canopy.engine.Engine
import canopy.engine.DocsPayload
import canopy.engine.JournalPayload
import canopy.engine.MilestoneList
import canopy.engine.UpdateReceipt
import canopy.engine.GitOpResponse
import canopy.engine.MilestoneActionReceipt
import canopy.engine.EngineLocator
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.jsonObject
import java.util.concurrent.atomic.AtomicInteger

class AgentCore(private val engineBin: String) {

    companion object {
        const val CONTEXT_BUDGET = 9000
        const val TOOL_CONTEXT_BUDGET = 8000
        const val TOOL_OUTPUT_CLIP = 16000
        const val MAX_ROUNDS = 4
    }

    /** 引擎 tools --json → 工具定义 + 必填校验唯一来源（params "a,b,c" 全 string 必填）。 */
    suspend fun loadToolManifest(engine: Engine): Pair<List<ToolDef>, Map<String, String>> {
        // 引擎 tools --json 原文（进系统提示词）；探活失败的清单按空处理（同款守卫）
        val raw = try { engine.tools() } catch (e: Exception) { "" }
        val defs = mutableListOf<ToolDef>()
        val paramsByTool = mutableMapOf<String, String>()
        try {
            val obj = Json.parseToJsonElement(raw).jsonObject
            val tools = obj["tools"]?.jsonArray ?: return emptyList<ToolDef>() to paramsByTool
            tools.forEach { t ->
                val o = t.jsonObject
                val name = o["name"]?.toString()?.trim('"') ?: return@forEach
                val desc = o["description"]?.toString()?.trim('"') ?: ""
                val params = o["params"]?.toString()?.trim('"') ?: ""
                val required = params.split(',').map { it.trim() }
                    .filter { it.isNotBlank() && !it.contains('(') }
                defs += ToolDef(name, desc, required)
                paramsByTool[name] = buildJsonObject {
                    put("type", "object")
                    put("required", kotlinx.serialization.json.JsonArray(required.map { kotlinx.serialization.json.JsonPrimitive(it) }))
                }.toString()
            }
        } catch (_: Exception) { /* 清单解析失败 → 空清单不崩（引擎侧同款守卫） */ }
        return defs to paramsByTool
    }

    /** 必填校验在执行点内部（NC31 收口）。 */
    private fun missingArgs(paramsByTool: Map<String, String>, name: String, argsJson: String): List<String> {
        val required = paramsByTool[name]?.let {
            Json.parseToJsonElement(it).jsonObject["required"]?.toString()
                ?.trim('[', ']')?.split(',')?.map { s -> s.trim('"') } ?: emptyList()
        } ?: emptyList()
        val obj = try { Json.parseToJsonElement(argsJson.ifBlank { "{}" }).jsonObject } catch (_: Exception) { return required }
        return required.filter { obj[it] == null || obj[it].toString() == "null" || obj[it].toString() == "\"\"" }
    }

    /** 单工具执行（本机 CLI 子进程）。返回 (ok, 结果文本)。suspend：内部走 Engine 的 IO 挂起。 */
    suspend fun executeTool(engine: Engine, name: String, argsJson: String, paramsByTool: Map<String, String>): Pair<Boolean, String> {
        val absent = missingArgs(paramsByTool, name, argsJson)
        if (absent.isNotEmpty()) {
            return Pair(false, "工具 $name 缺必填参数：${absent.joinToString("、")}。请补齐后重试。")
        }
        val obj = try { Json.parseToJsonElement(argsJson.ifBlank { "{}" }).jsonObject } catch (_: Exception) { kotlinx.serialization.json.JsonObject(emptyMap()) }
        fun arg(key: String) = obj[key]?.toString()?.trim('"') ?: ""
        val clipped: (String) -> String = { out ->
            if (out.length > TOOL_OUTPUT_CLIP) out.take(TOOL_OUTPUT_CLIP) +
                "\n\n（客户端在此处截断：原始 ${out.length} 字符，只保留前 $TOOL_OUTPUT_CLIP 字符。）" else out
        }
        return try {
            when (name) {
                "get_group_context" -> {
                    val (rc, out) = EngineLocator.run(engineBin, listOf("context", "--budget", "$TOOL_CONTEXT_BUDGET", "--json"), 60)
                    Pair(rc == 0, clipped(if (rc == 0) out else "引擎退出码 $rc"))
                }
                "get_project_context" -> {
                    val (rc, out) = EngineLocator.run(engineBin, listOf("context", arg("name"), "--budget", "$TOOL_CONTEXT_BUDGET", "--json"), 60)
                    Pair(rc == 0, clipped(if (rc == 0) out else "引擎退出码 $rc"))
                }
                "get_project_docs" -> {
                    val r = engine.docs(arg("name"))
                    Pair(true, clipped(Json.encodeToString(DocsPayload.serializer(), r)))
                }
                "get_journal" -> {
                    val r = engine.journal(arg("name"))
                    Pair(true, clipped(Json.encodeToString(JournalPayload.serializer(), r)))
                }
                "get_milestones" -> {
                    val r = engine.milestoneList()
                    Pair(true, clipped(Json.encodeToString(MilestoneList.serializer(), r)))
                }
                "run_shallow_update" -> {
                    val r = engine.update(arg("name"), deep = false)
                    Pair(true, clipped(Json.encodeToString(UpdateReceipt.serializer(), r)))
                }
                "run_deep_update" -> {
                    val r = engine.update(arg("name"), deep = true)
                    Pair(true, clipped(Json.encodeToString(UpdateReceipt.serializer(), r)))
                }
                "git_commit" -> {
                    val r = engine.gitOp("commit", arg("name"), arg("message"))
                    Pair(true, clipped(Json.encodeToString(GitOpResponse.serializer(), r)))
                }
                "git_pull_push" -> {
                    val op = arg("op").ifBlank { "pull" }
                    if (op != "pull" && op != "push") {
                        Pair(false, "git_pull_push 的 op 只支持 pull|push，收到：「$op」。已拒绝执行。")
                    } else {
                        val r = engine.gitOp(op, arg("name"))
                        Pair(true, clipped(Json.encodeToString(GitOpResponse.serializer(), r)))
                    }
                }
                "milestone_done" -> {
                    val r = engine.milestoneAction(arg("project"), arg("name"), "done")
                    Pair(true, clipped(Json.encodeToString(MilestoneActionReceipt.serializer(), r)))
                }
                else -> Pair(false, "未知工具：$name")
            }
        } catch (e: Exception) {
            Pair(false, "工具执行失败：${e.message}")
        }
    }

    /** 完整 agent 循环（IO 协程内调用）。失败：返回 error 非空；调用方把已发提问留回 history。 */
    suspend fun run(
        engine: Engine,
        question: String,
        history: List<ChatMessage>,
        targetLabel: String,
        cfg: AIConfig,
        cancelled: AtomicInteger? = null,
        onEvent: ((String) -> Unit)? = null,
    ): Pair<List<ChatMessage>, String> {
        val aiEngine = AIEngineFactory.create(cfg)
        var why = ""
        if (!aiEngine.isConfigured { why = it }) {
            return history to "AI 未配置：$why"
        }
        if (cancelled?.get() == 1) return history to "AI 请求已取消。"

        // ① 上下文包 + 工具清单
        val contextRaw = try {
            val (rc, out) = EngineLocator.run(engineBin, listOf("context", "--budget", "$CONTEXT_BUDGET", "--json"), 60)
            if (rc == 0) out else "（上下文读取失败：引擎退出码 $rc）"
        } catch (e: Exception) {
            "（上下文读取失败：${e.message}）"
        }
        val (toolDefs, paramsByTool) = loadToolManifest(engine)

        val system = buildString {
            append("你是 Canopy 项目群进度面板的 AI 助手。范围：$targetLabel。")
            append("只依据工具返回的引擎事实回答——工具没给的数据，如实说「不知道」。")
            append("\n\n## 可用工具清单（引擎 tools --json 原文）\n")
            append(toolDefs.joinToString("\n") { "- ${it.name}: ${it.description}（必填：${it.requiredParams.joinToString(",")}）" })
            append("\n\n## 当前范围事实（引擎生成）\n")
            append(contextRaw)
        }

        var convo = history + ChatMessage.makeUser(question)
        var round = 0
        while (round < MAX_ROUNDS) {
            round += 1
            if (cancelled?.get() == 1) return convo to "AI 请求已取消。"
            val result = aiEngine.generate(GenerateRequest(system = system, messages = convo, tools = toolDefs))
            if (!result.ok) return convo to result.error
            if (result.toolCalls.isEmpty()) {
                return (convo + ChatMessage.makeAssistant(result.text)) to ""
            }
            convo = convo + ChatMessage(Role.assistant, text = result.text, toolCalls = result.toolCalls)
            var executedAny = false
            for (call in result.toolCalls) {
                if (cancelled?.get() == 1) return convo to "AI 请求已取消。"
                onEvent?.invoke("🔧 ${call.name}")
                val (ok, out) = executeTool(engine, call.name, call.argsJson, paramsByTool)
                executedAny = executedAny || ok
                onEvent?.invoke("   ${if (ok) "✓" else "✗"} ${call.name}")
                convo = convo + ChatMessage.makeTool("工具 ${call.name} 执行${if (ok) "成功" else "失败"}：\n$out", call.id, !ok)
            }
            if (round == MAX_ROUNDS) {
                return if (executedAny) {
                    // 工具已执行 ≠ 失败：回喂最后一轮结果请模型收尾一次（不再允许工具调用）
                    val last = aiEngine.generate(GenerateRequest(system = system, messages = convo, tools = emptyList()))
                    if (last.ok) (convo + ChatMessage.makeAssistant(last.text)) to ""
                    else convo to "已达工具调用轮次上限（$MAX_ROUNDS），且收尾生成失败：${last.error}"
                } else {
                    convo to "已达工具调用轮次上限（$MAX_ROUNDS），且模型未产出任何文本"
                }
            }
        }
        return convo to "agent 循环异常退出"
    }
}
