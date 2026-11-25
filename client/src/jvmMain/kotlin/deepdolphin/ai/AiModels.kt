// AiModels.kt —— AI 通道的协议形状（deepin ai/AIEngine.h 的 Kotlin 对位；字段一比一）。
//
// 【零依赖纪律】不放网络/UI/引擎依赖：AgentConversation / 判定层直接消费 ChatMessage。

package deepdolphin.ai

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import kotlinx.serialization.json.add

enum class Role { system, user, assistant, tool }

/** 一次原生工具调用（OpenAI 形状；Anthropic 侧由通道转换 tool_use blocks）。 */
data class ToolCall(val id: String, val name: String, val argsJson: String)

/** 一条对话消息。isError 只给界面用（「工具根本没跑」靠标记，不靠文案匹配）。 */
data class ChatMessage(
    val role: Role,
    val text: String = "",
    val toolCalls: List<ToolCall> = emptyList(),
    val toolCallId: String = "",
    val isError: Boolean = false,
) {
    companion object {
        fun makeUser(t: String) = ChatMessage(Role.user, text = t)
        fun makeAssistant(t: String) = ChatMessage(Role.assistant, text = t)
        fun makeTool(t: String, callId: String, isError: Boolean = false) =
            ChatMessage(Role.tool, text = t, toolCallId = callId, isError = isError)
        fun makeSystem(t: String) = ChatMessage(Role.system, text = t)
    }

    fun roleString(): String = when (role) {
        Role.system -> "system"; Role.user -> "user"; Role.assistant -> "assistant"; Role.tool -> "tool"
    }
}

/** 工具定义（发给模型契约的唯一来源；params → JSON Schema 在通道内组装）。 */
data class ToolDef(val name: String, val description: String, val requiredParams: List<String>) {
    /** OpenAI functions 形状的 parameters JSON Schema（与 deepin AIEngine::parametersJSON 同构）。 */
    fun parametersJson(): JsonObject = buildJsonObject {
        put("type", "object")
        // properties 必须是「以参数名为键的对象」（JSON Schema / mac 同款）。
        // 原来发成了数组——模型拿不到参数名和类型，严格校验的渠道会整包拒收。
        putJsonObject("properties") {
            requiredParams.forEach { p ->
                putJsonObject(p) {
                    put("type", "string")
                    put("description", p)
                }
            }
        }
        putJsonArray("required") { requiredParams.forEach { add(it) } }
    }
}

data class GenerateRequest(
    val system: String,
    val messages: List<ChatMessage>,
    val tools: List<ToolDef> = emptyList(),
    val maxTokens: Int = 4000,
    val timeoutMs: Int = 120_000,
)

data class GenerateResult(
    val text: String = "",
    val toolCalls: List<ToolCall> = emptyList(),
    val error: String = "", // ok=false 时的中文原因（可指导下一步）
) {
    val ok: Boolean get() = error.isEmpty()
}

/** AI 渠道配置（ai.* 键对位；key 只进安全存储，明文回退仅 headless/mock）。 */
data class AIConfig(
    val providerID: String = "deepseek",
    val model: String = "",
    val baseURL: String = "",
    val apiKey: String = "",
) {
    /** 实际使用的端点：填了用填的，没填用渠道默认（选了 DeepSeek 不必再手填 URL）。 */
    fun effectiveBaseURL(): String = baseURL.trim().ifEmpty { DEFAULT_BASE_URLS[providerID] ?: "" }

    fun isConfigured(whyNot: (String) -> Unit = {}): Boolean = when {
        providerID == "mock" -> true
        effectiveBaseURL().isBlank() -> { whyNot(deepdolphin.ui.L10n.t("cmp.ai.noBaseUrl", providerID)); false }
        providerID == "ollama" -> true // 本地服务不需要 key
        apiKey.isBlank() -> { whyNot(deepdolphin.ui.L10n.t("cmp.ai.noKey")); false }
        else -> true
    }

    companion object {
        /** 各渠道默认端点（与仓内 deepin / linux / mac 各端一致）。 */
        val DEFAULT_BASE_URLS: Map<String, String> = mapOf(
            "deepseek" to "https://api.deepseek.com",
            "anthropic" to "https://api.anthropic.com",
            "ollama" to "http://localhost:11434",
        )
    }
}

// ── settings.conf 的 ai.* 键（C7 持久化；key 不进 conf）──

@Serializable
data class AiSettings(
    @SerialName("ai.providerID") val providerID: String = "deepseek",
    @SerialName("ai.model") val model: String = "",
    @SerialName("ai.baseURL") val baseURL: String = "",
) {
    fun toConf(): String = "ai.providerID=$providerID\nai.model=$model\nai.baseURL=$baseURL\n"

    companion object {
        private val KEYS = setOf("ai.providerID", "ai.model", "ai.baseURL")
        /** 与 confWithKey 同纪律：只合并 ai.* 键，其他行原样保留（防「存外观抹定时档」同族事故）。 */
        fun mergeInto(existing: String, cfg: AiSettings): String {
            val cfgMap = mapOf(
                "ai.providerID" to cfg.providerID,
                "ai.model" to cfg.model,
                "ai.baseURL" to cfg.baseURL,
            )
            val out = existing.lines().mapNotNull { line ->
                val key = line.substringBefore('=').trim()
                if (key in KEYS) null else line
            }
            return (out + KEYS.map { "$it=${cfgMap[it]}" }).joinToString("\n") + "\n"
        }

        fun fromConf(text: String): AiSettings {
            val map = text.lines().associate {
                val i = it.indexOf('=')
                if (i > 0) it.substringBefore('=').trim() to it.substringAfter('=', "").trim() else null to ""
            }.filterKeys { it != null }
            return AiSettings(
                providerID = map["ai.providerID"] ?: "deepseek",
                model = map["ai.model"] ?: "",
                baseURL = map["ai.baseURL"] ?: "",
            )
        }
    }
}
