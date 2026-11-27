// AgentIntegrationTest.kt —— AI Agent 集成的判据（全部在临时目录里跑，绝不碰真实的
// ~/.claude.json / ~/.codex / 技能目录：那是用户的 agent 配置，测试写一次就是事故）。
//
// 集成的三个动作各有一个「改坏之后会红」的守卫：
// · MCP 合并必须保留用户已有的 mcpServers 条目（那是别人的服务器配置——丢了就是数据损失）；
//   配置不是合法 JSON 时宁可不动、如实报错，不许覆盖。
// · Codex 的 TOML 块替换不能吃掉用户的其它段落。
// · CLI 安装对已有入口幂等（不覆盖用户/引擎安装器装的版本）。
package canopy.agent

import kotlinx.serialization.json.jsonObject
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AgentIntegrationTest {
    private fun tempHome(): File = File(
        System.getProperty("java.io.tmpdir"),
        "canopy-agent-test-${System.nanoTime()}",
    ).apply { mkdirs() }

    @Test
    fun claudeMcpMergeKeepsUserServersAndIsIdempotent() {
        val existing = """
            {
              "numStartups": 3,
              "projects": {"~/work": {"allowedTools": ["git"]}},
              "mcpServers": {"zai": {"type": "stdio", "command": "npx", "args": ["-y", "x"], "env": {"K": "V"}}}
            }
        """.trimIndent()
        val merged = assertNotNull(mergeClaudeMcp(existing, "cambium"), "合法 JSON 必须能合并")
        val root = kotlinx.serialization.json.Json.parseToJsonElement(merged).jsonObject
        val servers = root["mcpServers"] as? kotlinx.serialization.json.JsonObject
        assertNotNull(servers)
        // 用户已有的服务器原样保留（丢了就是数据损失）
        assertEquals("npx", servers["zai"]?.jsonObject?.get("command")?.toString()?.trim('"'))
        // cambium 进来了：stdio + mcp
        val entry = servers["cambium"]?.jsonObject
        assertNotNull(entry, "cambium 条目要写进 mcpServers")
        assertEquals("\"stdio\"", entry["type"].toString())
        assertEquals("\"cambium\"", entry["command"].toString())
        // 与文件里无关的键原样保留
        assertTrue(root.containsKey("projects"))
        // 幂等：再合并一次不产生第二个条目
        val again = assertNotNull(mergeClaudeMcp(merged, "cambium"))
        assertTrue(claudeRegistered(again))
        assertEquals(servers.size, kotlinx.serialization.json.Json.parseToJsonElement(again).jsonObject["mcpServers"]!!.jsonObject.size)
        // 已注册的判定对旧格式为假、合并后为真
        assertFalse(claudeRegistered(existing))
        // 配置坏了不许覆盖：返回 null，让调用方如实报错
        assertNull(mergeClaudeMcp("{ this is not json", "cambium"))
    }

    @Test
    fun claudeMcpMergeHandlesEmptyConfig() {
        val merged = assertNotNull(mergeClaudeMcp("", "cambium"), "空文件按空对象处理（首次注册也是合法动作）")
        assertTrue(claudeRegistered(merged))
    }

    @Test
    fun codexBlockUpsertAppendsAndReplaces() {
        val config = """
            model = "gpt-5"
            approval_policy = "on-request"

            [mcp_servers.other]
            command = "npx"

            [profiles.fast]
            model = "gpt-5-mini"
        """.trimIndent() + "\n"
        val added = upsertCodexBlock(config, "cambium")
        assertTrue(codexRegistered(added))
        // 用户的其它段落原样保留
        assertTrue(added.contains("model = \"gpt-5\""))
        assertTrue(added.contains("[mcp_servers.other]"))
        assertTrue(added.contains("[profiles.fast]"))
        // 已有的 cambium 块整块替换（改 command 不留旧值），其它段落仍然不丢
        val replaced = upsertCodexBlock(added, "cambium2")
        assertTrue(codexRegistered(replaced))
        assertTrue(replaced.contains("command = \"cambium2\""))
        assertFalse(replaced.contains("command = \"cambium\"\n"))
        assertTrue(replaced.contains("[profiles.fast]"))
        assertEquals(1, Regex("\\[mcp_servers\\.cambium\\]").findAll(replaced).count(), "不许出现两个 cambium 块")
        // 空配置 = 建一个只含 cambium 的文件
        val fresh = upsertCodexBlock("", "cambium")
        assertTrue(codexRegistered(fresh))
    }

    @Test
    fun detectTargetsOnlyListsPresentAgents() {
        val home = tempHome()
        try {
            assertTrue(detectTargets(home).isEmpty(), "什么 agent 都没装 = 空表")
            File(home, ".claude.json").writeText("{}")
            File(home, ".codex").mkdirs()
            File(home, ".zcode/skills").mkdirs()
            val targets = detectTargets(home)
            assertEquals(listOf("claude", "codex", "zcode-skill"), targets.map { it.id }, "没装的 agent 不列（.agents/skills 缺席）")
            File(home, ".agents/skills").mkdirs()
            assertEquals(listOf("claude", "codex", "zcode-skill", "agents-skill"), detectTargets(home).map { it.id })
            // 注册动作真的让 agent 认得 Cambium（对探测目标跑一遍，文件都落在仿真 home 里）
            for (t in targets) {
                when (targetKind(t)) {
                    AgentKind.MCP_CLAUDE, AgentKind.MCP_CODEX -> assertNull(registerMcp(t, "cambium"), t.id)
                    AgentKind.SKILL -> Unit   // skill 安装走引擎子进程，单测不跑
                }
            }
            for (t in targets) {
                if (targetKind(t) != AgentKind.SKILL) {
                    assertTrue(isTargetInstalled(t), "${t.id} 注册后要被探测到")
                    // 幂等：再注册一次是原样成功
                    assertNull(registerMcp(t, "cambium"))
                }
            }
            // 首次改动**已有内容**的配置要留备份（改坏了有得回）；新建的文件没有备份对象
            assertTrue(File(home, ".claude.json.bak-before-cambium").isFile, "Claude 配置要有备份")
            assertFalse(File(home, ".codex/config.toml.bak-before-cambium").exists(), "Codex 是新文件，无备份对象")
            assertTrue(codexRegistered(File(home, ".codex/config.toml").readText()))
        } finally {
            home.deleteRecursively()
        }
    }

    @Test
    fun cliInstallIsIdempotentAndWritesPathLauncher() {
        val home = tempHome()
        val bin = File(home, "engine/bin/cambium-engine").apply {
            parentFile.mkdirs()
            writeText("#!/usr/bin/env bash\nexec engine \"$@\"\n")
            setExecutable(true)
        }
        try {
            assertNotNull(installCli(home, null), "没有捆绑引擎 = 如实报错，不写任何东西")
            assertFalse(File(home, ".local/bin/cambium").exists())
            assertNull(installCli(home, bin), "有捆绑引擎就写入启动器")
            val launcher = File(home, ".local/bin/cambium")
            assertTrue(launcher.isFile && launcher.canExecute())
            assertTrue(launcher.readText().contains(bin.absolutePath), "启动器要指向捆绑引擎")
            // 幂等：已存在（用户的或引擎安装器装的）不覆盖
            launcher.writeText("# user-owned\n")
            assertNull(installCli(home, bin), "已存在 = 原样成功")
            assertEquals("# user-owned\n", launcher.readText(), "不许覆盖已有入口")
        } finally {
            home.deleteRecursively()
        }
    }

    @Test
    fun skillInstalledChecksTheMarkerFile() {
        val dir = File(tempHome(), "skills/cambium").apply { mkdirs() }
        assertFalse(skillInstalled(dir))
        File(dir, "SKILL.md").writeText("# cambium\n")
        assertTrue(skillInstalled(dir))
        dir.parentFile.parentFile.deleteRecursively()
    }
}
