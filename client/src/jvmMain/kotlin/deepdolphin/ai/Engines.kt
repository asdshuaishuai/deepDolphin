// Engines.kt —— AI 双协议引擎（OpenAI 兼容 + Anthropic）+ 工厂。
//
// 【URL 安全】只放行 https 与 http://127.0.0.1/http://localhost（防投毒端点骗取 apiKey）。
// 【诚实】网络错误/非 2xx 给中文原因与下一步；不静默、不编造。

package deepdolphin.ai

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

fun urlAllowed(url: String): Boolean =
    url.startsWith("https://") ||
        url.startsWith("http://127.0.0.1") ||
        url.startsWith("http://localhost")

interface AIEngine {
    val backendId: String
    fun isConfigured(whyNot: (String) -> Unit = {}): Boolean
    suspend fun generate(req: GenerateRequest): GenerateResult
}

private fun httpPostJson(urlStr: String, apiKey: String, body: String, timeoutMs: Int): Pair<Int, String> {
    val url = URI.create(urlStr).toURL() as URL
    val conn = url.openConnection() as HttpURLConnection
    conn.requestMethod = "POST"
    conn.connectTimeout = 10_000
    conn.readTimeout = timeoutMs
    conn.doOutput = true
    conn.setRequestProperty("Content-Type", "application/json")
    if (apiKey.isNotBlank()) conn.setRequestProperty("Authorization", "Bearer $apiKey")
    conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
    val rc = conn.responseCode
    val text = (if (rc in 200..299) conn.inputStream else conn.errorStream)
        ?.bufferedReader()?.readText() ?: ""
    conn.disconnect()
    return Pair(rc, text)
}

/** 单轮 OpenAI 兼容 /chat/completions（tools = functions 形状）。 */
class OpenAiCompatEngine(private val cfg: AIConfig) : AIEngine {
    override val backendId = "openai-compat"

    override fun isConfigured(whyNot: (String) -> Unit): Boolean = cfg.isConfigured(whyNot)

    override suspend fun generate(req: GenerateRequest): GenerateResult {
        if (!urlAllowed(cfg.baseURL)) {
            return GenerateResult(error = "Base URL 不被允许（只放行 https 与本地回环）：${cfg.baseURL}")
        }
        val messages = buildJsonArray {
            add(buildJsonObject { put("role", "system"); put("content", req.system) })
            req.messages.forEach { m ->
                when (m.role) {
                    Role.tool -> add(buildJsonObject {
                        put("role", "tool")
                        put("content", m.text)
                        put("tool_call_id", m.toolCallId)
                    })
                    Role.assistant -> add(buildJsonObject {
                        put("role", "assistant")
                        if (m.text.isNotBlank()) put("content", m.text)
                        if (m.toolCalls.isNotEmpty()) putJsonArray("tool_calls") {
                            m.toolCalls.forEach { tc ->
                                add(buildJsonObject {
                                    put("id", tc.id)
                                    put("type", "function")
                                    put("function", buildJsonObject {
                                        put("name", tc.name)
                                        put("arguments", tc.argsJson)
                                    })
                                })
                            }
                        }
                    })
                    else -> add(buildJsonObject { put("role", m.roleString()); put("content", m.text) })
                }
            }
        }
        val body = buildJsonObject {
            put("model", cfg.model.ifBlank { "gpt-4o-mini" })
            put("messages", messages)
            put("max_tokens", req.maxTokens)
            if (req.tools.isNotEmpty()) {
                putJsonArray("tools") {
                    req.tools.forEach { td ->
                        add(buildJsonObject {
                            put("type", "function")
                            put("function", buildJsonObject {
                                put("name", td.name)
                                put("description", td.description)
                                put("parameters", td.parametersJson())
                            })
                        })
                    }
                }
            }
        }
        return withContext(Dispatchers.IO) {
            try {
                val url = cfg.baseURL.trimEnd('/') + "/chat/completions"
                val (rc, text) = httpPostJson(url, cfg.apiKey, body.toString(), req.timeoutMs)
                if (rc !in 200..299) {
                    return@withContext GenerateResult(
                        error = "HTTP $rc：${text.take(200)}（检查 Base URL / Key / 模型名）"
                    )
                }
                val obj = Json.parseToJsonElement(text).jsonObject
                val err = obj["error"]
                if (err != null) {
                    return@withContext GenerateResult(error = "provider 返回错误：${err.jsonObject["message"]?.jsonPrimitive?.content ?: "$err"}")
                }
                val choice = obj["choices"]?.jsonArray?.firstOrNull()?.jsonObject
                    ?: return@withContext GenerateResult(error = "响应缺 choices（provider 契约异常）")
                val msg = choice["message"]?.jsonObject ?: JsonObject(emptyMap())
                val calls = msg["tool_calls"]?.jsonArray?.map { tc ->
                    val f = tc.jsonObject["function"]!!.jsonObject
                    ToolCall(
                        id = tc.jsonObject["id"]?.jsonPrimitive?.content ?: "",
                        name = f["name"]?.jsonPrimitive?.content ?: "",
                        argsJson = f["arguments"]?.jsonPrimitive?.content ?: "{}",
                    )
                } ?: emptyList()
                GenerateResult(
                    text = msg["content"]?.jsonPrimitive?.content ?: "",
                    toolCalls = calls,
                )
            } catch (e: Exception) {
                GenerateResult(error = "请求失败：${e.message}（网络不通 / 超时 / URL 错）")
            }
        }
    }
}

/** Anthropic /v1/messages（tool_use blocks；header 用 x-api-key）。 */
class AnthropicEngine(private val cfg: AIConfig) : AIEngine {
    override val backendId = "anthropic"

    override fun isConfigured(whyNot: (String) -> Unit): Boolean = cfg.isConfigured(whyNot)

    override suspend fun generate(req: GenerateRequest): GenerateResult {
        if (!urlAllowed(cfg.baseURL)) {
            return GenerateResult(error = "Base URL 不被允许（只放行 https 与本地回环）：${cfg.baseURL}")
        }
        // system 独立字段；messages 不含 system
        val msgs = buildJsonArray {
            req.messages.filter { it.role != Role.system }.forEach { m ->
                when (m.role) {
                    Role.tool -> add(buildJsonObject {
                        put("role", "user")
                        putJsonArray("content") {
                            add(buildJsonObject {
                                put("type", "tool_result")
                                put("tool_use_id", m.toolCallId)
                                put("content", m.text)
                                put("is_error", m.isError)
                            })
                        }
                    })
                    Role.assistant -> add(buildJsonObject {
                        put("role", "assistant")
                        putJsonArray("content") {
                            if (m.text.isNotBlank()) add(buildJsonObject {
                                put("type", "text"); put("text", m.text)
                            })
                            m.toolCalls.forEach { tc ->
                                add(buildJsonObject {
                                    put("type", "tool_use")
                                    put("id", tc.id)
                                    put("name", tc.name)
                                    put("input", Json.parseToJsonElement(tc.argsJson.ifBlank { "{}" }))
                                })
                            }
                        }
                    })
                    else -> add(buildJsonObject { put("role", m.roleString()); put("content", m.text) })
                }
            }
        }
        val body = buildJsonObject {
            put("model", cfg.model.ifBlank { "claude-sonnet-4-5" })
            put("max_tokens", req.maxTokens)
            put("system", req.system)
            put("messages", msgs)
            if (req.tools.isNotEmpty()) {
                putJsonArray("tools") {
                    req.tools.forEach { td ->
                        add(buildJsonObject {
                            put("name", td.name)
                            put("description", td.description)
                            put("input_schema", td.parametersJson())
                        })
                    }
                }
            }
        }
        return withContext(Dispatchers.IO) {
            try {
                val url = cfg.baseURL.trimEnd('/') + "/v1/messages"
                val conn = URI.create(url).toURL().openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.connectTimeout = 10_000
                conn.readTimeout = req.timeoutMs
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("x-api-key", cfg.apiKey)
                conn.setRequestProperty("anthropic-version", "2023-06-01")
                conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
                val rc = conn.responseCode
                val text = (if (rc in 200..299) conn.inputStream else conn.errorStream)
                    ?.bufferedReader()?.readText() ?: ""
                conn.disconnect()
                if (rc !in 200..299) {
                    return@withContext GenerateResult(error = "HTTP $rc：${text.take(200)}（检查 Base URL / Key / 模型名）")
                }
                val obj = Json.parseToJsonElement(text).jsonObject
                if (obj["error"] != null) {
                    val err = obj["error"]!!.jsonObject
                    return@withContext GenerateResult(error = "provider 返回错误：${err["message"]?.jsonPrimitive?.content ?: "$err"}")
                }
                val blocks = obj["content"]?.jsonArray ?: kotlin.run {
                    return@withContext GenerateResult(error = "响应缺 content（provider 契约异常）")
                }
                var txt = ""
                val calls = mutableListOf<ToolCall>()
                blocks.forEach { b ->
                    val o = b.jsonObject
                    when (o["type"]?.jsonPrimitive?.content) {
                        "text" -> txt += o["text"]?.jsonPrimitive?.content ?: ""
                        "tool_use" -> calls += ToolCall(
                            id = o["id"]?.jsonPrimitive?.content ?: "",
                            name = o["name"]?.jsonPrimitive?.content ?: "",
                            argsJson = o["input"]?.toString() ?: "{}",
                        )
                    }
                }
                GenerateResult(text = txt, toolCalls = calls)
            } catch (e: Exception) {
                GenerateResult(error = "请求失败：${e.message}（网络不通 / 超时 / URL 错）")
            }
        }
    }
}

/** 工厂：显式渠道 > mock。系统级 AI（UOS AI）在 Linux 通用端不适用（freedesktop 无标准）。 */
object AIEngineFactory {
    fun create(cfg: AIConfig): AIEngine = when (cfg.providerID) {
        "anthropic" -> AnthropicEngine(cfg)
        "mock" -> MockEngine()
        else -> OpenAiCompatEngine(cfg) // openai 兼容（deepseek/ollama/openrouter 等同形）
    }
}

/** mock 通道：脚本状态机（headless 自测全链路，不打真 HTTP）。 */
class MockEngine : AIEngine {
    override val backendId = "mock"
    private var round = 0

    override fun isConfigured(whyNot: (String) -> Unit): Boolean = true

    override suspend fun generate(req: GenerateRequest): GenerateResult {
        round += 1
        return if (req.tools.isNotEmpty() && round == 1) {
            GenerateResult(toolCalls = listOf(ToolCall(id = "mock-1", name = req.tools.first().name, argsJson = "{}")))
        } else {
            GenerateResult(text = "（mock）工具已执行，这是最终回答。")
        }
    }
}
