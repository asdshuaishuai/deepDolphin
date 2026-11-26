// AiTest.kt —— AI 层判据：mock 全链路 + 设置合并纪律 + URL 安全 + 工具必填校验。

package canopy.ai

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertFalse

class AiTest {

    @Test
    fun mockChannelCompletesToolLoop() = runBlocking {
        // mock 状态机：第 1 轮回工具调用、第 2 轮回最终文本（headless 自测全链路）
        val engine = AIEngineFactory.create(AIConfig(providerID = "mock", baseURL = "mock://", model = "m"))
        assertEquals("mock", engine.backendId)
        assertTrue(engine.isConfigured())
        val r1 = engine.generate(GenerateRequest(system = "s", messages = listOf(ChatMessage.makeUser("q")), tools = listOf(ToolDef("get_group_context", "d", emptyList()))))
        assertTrue(r1.ok && r1.toolCalls.size == 1, "第一轮应回一次工具调用")
        val r2 = engine.generate(GenerateRequest(system = "s", messages = listOf(ChatMessage.makeUser("q"))))
        assertTrue(r2.ok && r2.text.contains("最终回答"), "第二轮应收尾")
    }

    @Test
    fun urlGateBlocksPoisoningEndpoints() {
        assertTrue(urlAllowed("https://api.deepseek.com/v1"))
        assertTrue(urlAllowed("http://127.0.0.1:8080/v1"))
        assertTrue(urlAllowed("http://localhost:11434/v1")) // ollama
        assertFalse(urlAllowed("http://evil.example.com/v1"), "http 非回环必须拒绝")
        assertFalse(urlAllowed("ftp://x"))
    }

    @Test
    fun settingsMergeKeepsForeignKeys() {
        // 「存 AI 设置不抹别的键」——confWithKey 同族事故的判据
        val existing = "update.autoHours=3\nai.providerID=old\nui.theme=dark\nai.model=m1\n"
        val merged = AiSettings.mergeInto(existing, AiSettings(providerID = "anthropic", model = "claude", baseURL = "https://api.anthropic.com"))
        assertTrue(merged.contains("update.autoHours=3"), "非 AI 键必须保留")
        assertTrue(merged.contains("ui.theme=dark"), "非 AI 键必须保留")
        assertTrue(merged.contains("ai.providerID=anthropic"))
        assertTrue(merged.contains("ai.model=claude"))
        assertFalse(merged.contains("ai.providerID=old"))
        // 从 conf 读回
        val back = AiSettings.fromConf(merged)
        assertEquals("anthropic", back.providerID)
        assertEquals("claude", back.model)
    }

    @Test
    fun toolParamsSchemaCarriesRequired() {
        val td = ToolDef("get_project_context", "读项目上下文", listOf("name"))
        val schema = td.parametersJson().toString()
        assertTrue(schema.contains("\"name\""))
        assertTrue(schema.contains("\"required\""))
    }

    @Test
    fun toolArgsValidationReceivesMissingList() = runBlocking {
        // AgentCore 必填校验：缺 name 参数必须报缺（NC31：空项目名=整个项目群）
        val core = AgentCore("")
        val paramsByTool = mapOf("get_project_context" to """{"type":"object","required":["name"]}""")
        val (ok, msg) = core.executeTool(
            canopy.engine.EngineStubInstance, "get_project_context", "{}", paramsByTool,
        )
        assertFalse(ok)
        assertTrue(msg.contains("缺必填参数"), "失败信息要指导下一步：$msg")
    }

    @Test
    fun chatMessageRolesRoundTrip() {
        assertEquals("tool", ChatMessage.makeTool("x", "id1", true).roleString())
        assertEquals("assistant", ChatMessage.makeAssistant("y").roleString())
    }
}
