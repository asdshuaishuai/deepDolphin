// AiConfigTest.kt —— 工具 schema 形状与渠道默认端点的判据。
//
// 二次验证抓到：properties 被发成了数组（应为以参数名为键的对象），模型拿不到参数名；
// 选了 DeepSeek 仍必须手填 Base URL，否则恒「未配置」。

package canopy.ai

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AiConfigTest {

    @Test
    fun toolSchemaPropertiesIsAnObjectKeyedByName() {
        val schema = ToolDef("get_project_docs", "读文档", listOf("name")).parametersJson()
        val props = schema["properties"] as? kotlinx.serialization.json.JsonObject
        assertTrue(props != null, "properties 必须是对象，实际：${schema["type"]}")
        val name = props!!["name"] as? kotlinx.serialization.json.JsonObject
        assertEquals("string", name?.get("type").let { it.toString().trim('"') })
        assertEquals("""["name"]""", schema["required"].toString())
    }

    @Test
    fun providersHaveDefaultEndpoints() {
        assertEquals("https://api.deepseek.com", AIConfig(providerID = "deepseek").effectiveBaseURL())
        assertEquals("https://api.anthropic.com", AIConfig(providerID = "anthropic").effectiveBaseURL())
        assertEquals("http://localhost:11434", AIConfig(providerID = "ollama").effectiveBaseURL())
        assertEquals("https://example.test", AIConfig(providerID = "deepseek", baseURL = "  https://example.test ").effectiveBaseURL(), "填了用填的")
        assertEquals("", AIConfig(providerID = "custom").effectiveBaseURL())
    }

    @Test
    fun configuredNoLongerRequiresHandTypedUrl() {
        var why: String? = null
        assertTrue(AIConfig(providerID = "deepseek", apiKey = "k").isConfigured { why = it }, "选了 DeepSeek 就该能用默认地址")
        assertNull(why)
        assertFalse(AIConfig(providerID = "deepseek", apiKey = "").isConfigured { why = it })
        assertTrue(why!!.contains("API Key"))
        assertTrue(AIConfig(providerID = "ollama").isConfigured(), "本地服务不需要 key")
        assertFalse(AIConfig(providerID = "custom", apiKey = "k").isConfigured { why = it })
        assertTrue(why!!.contains("custom"), "没默认地址的渠道要点名说出来")
    }
}
