// AgentIntegration.kt —— AI Agent 集成：把引擎的 CLI / MCP / Skill 装进本机的编码 agent。
//
// 引擎（Cambium 2026-11-28）已经有三个现成出口：
//   · cambium           —— CLI 本体（status / render / dendro / arch / hook …，全部 --json）
//   · cambium mcp       —— MCP 服务（stdio JSON-RPC，工具与客户端同一套契约）
//   · cambium skill install [--dir D] —— 把 SKILL.md 装进 agent 的技能目录
// 本模块把它们接到 agent 实际读取的位置（2026-11-28 用户：安装客户端后，可以在设置里启用
// AI agent 的能力——cli、skill 和 mcp 直接安装到、或被 agent 识别到启用）：
//   · CLI：~/.local/bin/cambium。已装 = 只读状态；未装且应用镜像捆绑了引擎（deb 内
//     /opt/canopy/engine/，见 client/scripts/package-device.sh）= 写一个指到捆绑引擎的启动器。
//   · MCP：~/.claude.json 的 mcpServers（Claude Code）、~/.codex/config.toml 的
//     [mcp_servers.cambium]（Codex CLI）。改用户已有的 agent 配置是写用户数据：
//     原子写（临时文件 + rename）、首次改动留 .bak-before-cambium 备份、合并保留用户
//     已有的 mcpServers 条目（合并是纯函数，判据见 AgentIntegrationTest）。
//   · Skill：~/.zcode/skills/cambium、~/.agents/skills/cambium（目录存在才装；内容由引擎出，
//     这里不抄一份——「字符串表是生成物，手改会被覆盖」的同一纪律）。
// ZCode 的 MCP 服务配置走它自己的 UI（本机没有可写的配置文件），技能目录是它认的部分。

package canopy.agent

import canopy.engine.EngineLocator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import java.io.File

/** 探测出的一个集成目标：一个 agent 的一处挂载点（MCP 配置文件或技能目录）。 */
data class AgentTarget(
    val id: String,
    /** UI 文案的 L10n 键（四语言见 L10nCmpKeys 的 cmp.agent.* 段）。 */
    val labelKey: String,
    /** MCP_CLAUDE / MCP_CODEX = 配置文件；SKILL = 技能目录。 */
    val file: File,
)

enum class AgentKind { MCP_CLAUDE, MCP_CODEX, SKILL }

/** 一处目标的安装状态：installed = agent 已经认得 Cambium。 */
data class AgentTargetStatus(val target: AgentTarget, val kind: AgentKind, val installed: Boolean)

/** 整张集成状态（设置页 AI tab 的 AgentIntegrationCard 一次探测得到）。 */
data class AgentIntegrationStatus(
    val cliPath: String,
    val cliVersion: String,
    val cliFound: Boolean,
    /** 应用镜像捆绑的引擎启动器（engine/bin/cambium-engine）；null = 没有捆绑（开发态）。 */
    val bundledLauncher: File?,
    val targets: List<AgentTargetStatus>,
)

private val json = Json { prettyPrint = true }

/** Claude Code 的 MCP 条目形状（与用户配置里已有的条目同构：type/command/args）。 */
internal fun claudeMcpEntry(command: String): JsonObject = JsonObject(
    mapOf(
        "type" to JsonPrimitive("stdio"),
        "command" to JsonPrimitive(command),
        "args" to kotlinx.serialization.json.JsonArray(listOf(JsonPrimitive("mcp"))),
    ),
)

/**
 * 把 cambium 合并进 ~/.claude.json 的 mcpServers，返回**整份文件**的新文本。
 * 用户已有的服务器条目原样保留（JsonElement 往返不改任何别的键）；配置不是合法 JSON
 * 或不是对象时返回 null——宁可不动用户的配置，也不悄悄覆盖（调用方如实报错）。
 */
internal fun mergeClaudeMcp(configText: String, command: String): String? {
    val root = if (configText.isBlank()) {
        JsonObject(emptyMap())
    } else {
        try {
            Json.parseToJsonElement(configText).jsonObject
        } catch (e: Exception) {
            return null
        }
    }
    val servers = root["mcpServers"] as? JsonObject ?: JsonObject(emptyMap())
    val merged = JsonObject(servers + ("cambium" to claudeMcpEntry(command)))
    return json.encodeToString(JsonObject.serializer(), JsonObject(root + ("mcpServers" to merged)))
}

internal fun claudeRegistered(configText: String?): Boolean {
    if (configText.isNullOrBlank()) return false
    return try {
        (Json.parseToJsonElement(configText).jsonObject["mcpServers"] as? JsonObject)
            ?.containsKey("cambium") == true
    } catch (e: Exception) {
        false
    }
}

internal fun codexRegistered(configText: String?): Boolean =
    configText != null && configText.contains("[mcp_servers.cambium]")

/**
 * Codex CLI 的 config.toml：把 [mcp_servers.cambium] 块写入——已有就整块替换（块 = 该行到
 * 下一个顶格 `[` 段头或文件尾），没有就追加。用户的其它段落原样保留（按行拼接，不解析 TOML）。
 */
internal fun upsertCodexBlock(config: String, command: String): String {
    val block = "[mcp_servers.cambium]\ncommand = \"$command\"\nargs = [\"mcp\"]\n"
    val lines = config.lines()
    val start = lines.indexOfFirst { it.trim() == "[mcp_servers.cambium]" }
    return if (start >= 0) {
        var end = start + 1
        while (end < lines.size && !lines[end].startsWith("[")) end += 1
        (lines.subList(0, start).toMutableList() + block.trimEnd().split('\n') + lines.subList(end, lines.size).toMutableList())
            .joinToString("\n") + (if (config.endsWith("\n") || config.isEmpty()) "\n" else "")
    } else {
        val sb = StringBuilder()
        sb.append(config)
        if (config.isNotEmpty() && !config.endsWith("\n")) sb.append('\n')
        if (config.isNotBlank()) sb.append('\n')
        sb.append(block)
        sb.toString()
    }
}

/**
 * 本机有哪些 agent 挂载点。按「配置/目录存在」判定——用户没装某个 agent 就不列出它，
 * 列出来也装不进去（注册一个 Claude Code 不存在的 ~/.claude.json 是凭空造配置）。
 */
fun detectTargets(home: File): List<AgentTarget> = buildList {
    val claude = File(home, ".claude.json")
    if (claude.isFile) {
        add(AgentTarget("claude", "cmp.agent.mcpClaude", claude))
    }
    if (File(home, ".codex").isDirectory) {
        add(AgentTarget("codex", "cmp.agent.mcpCodex", File(home, ".codex/config.toml")))
    }
    val zcode = File(home, ".zcode/skills")
    if (zcode.isDirectory) {
        add(AgentTarget("zcode-skill", "cmp.agent.skillZcode", File(zcode, "cambium")))
    }
    val agents = File(home, ".agents/skills")
    if (agents.isDirectory) {
        add(AgentTarget("agents-skill", "cmp.agent.skillAgents", File(agents, "cambium")))
    }
}

internal fun targetKind(target: AgentTarget): AgentKind = when (target.id) {
    "claude" -> AgentKind.MCP_CLAUDE
    "codex" -> AgentKind.MCP_CODEX
    else -> AgentKind.SKILL
}

fun skillInstalled(dir: File): Boolean = File(dir, "SKILL.md").isFile

/** 设置页一次探测：CLI 定位（含版本）+ 捆绑引擎 + 各 agent 挂载点的安装状态。IO 线程跑。 */
suspend fun probeAgentIntegration(): AgentIntegrationStatus = withContext(Dispatchers.IO) {
    val probe = EngineLocator.probe()
    val home = File(System.getProperty("user.home"))
    AgentIntegrationStatus(
        cliPath = probe.path,
        cliVersion = probe.version,
        cliFound = probe.found,
        bundledLauncher = bundledEngineLauncher(),
        targets = detectTargets(home).map { AgentTargetStatus(it, targetKind(it), isTargetInstalled(it)) },
    )
}

/** 一处目标当前是否已注册（读它指向的文件/目录，不看内存）。 */
fun isTargetInstalled(target: AgentTarget): Boolean = when (targetKind(target)) {
    AgentKind.MCP_CLAUDE -> claudeRegistered(readTextOrNull(target.file))
    AgentKind.MCP_CODEX -> codexRegistered(readTextOrNull(target.file))
    AgentKind.SKILL -> skillInstalled(target.file)
}

internal fun readTextOrNull(f: File): String? = try {
    if (f.isFile) f.readText() else null
} catch (e: Exception) {
    null
}

/** 原子写（临时文件 + rename，同目录保证同分区）；出错抛异常由调用方转成回执。 */
internal fun writeAtomic(f: File, text: String) {
    f.parentFile?.mkdirs()
    val tmp = File(f.parentFile, f.name + ".canopy-tmp")
    tmp.writeText(text)
    if (!tmp.renameTo(f)) {
        tmp.delete()
        throw java.io.IOException("rename failed: ${tmp.path} -> ${f.path}")
    }
}

/**
 * 应用镜像捆绑的引擎目录（deb 里 /opt/canopy/engine/，见 client/scripts/package-device.sh）。
 * 探测次序：jpackage 的 APPDIR → 用户级安装 → 系统级安装。都没有 = null（开发态没有捆绑引擎，
 * CLI 行只显示探测状态）。
 */
fun bundledEngineLauncher(): File? = listOf(
    System.getenv("APPDIR")?.let { File(it, "engine/bin/cambium-engine") },
    File(File(System.getProperty("user.home"), ".local/opt/canopy"), "engine/bin/cambium-engine"),
    File("/opt/canopy/engine/bin/cambium-engine"),
).firstOrNull { it != null && it.isFile }

/**
 * CLI 注册：把捆绑引擎挂到 ~/.local/bin/cambium（PATH 上，agent 直接可用）。
 * 幂等：目标已存在时不覆盖——那是用户（或引擎安装器）装的版本，替换它们不是这个按钮的事，
 * 调用方重新探测状态就能看到「已就绪」。返回 null = 成功；非 null = 失败/未做的事的原话。
 */
fun installCli(home: File, bundledLauncher: File?): String? {
    if (bundledLauncher == null || !bundledLauncher.isFile) return "no bundled engine"
    val target = File(home, ".local/bin/cambium")
    if (target.exists()) return null   // 幂等：已有入口（用户的或引擎安装器装的）不覆盖
    val script = "#!/usr/bin/env bash\n" +
        "# Canopy 写入的引擎启动器（设置 → AI Agent 集成）：exec 应用镜像捆绑的 Cambium 引擎。\n" +
        "exec \"${bundledLauncher.absolutePath}\" \"$@\"\n"
    return try {
        writeAtomic(target, script)
        target.setExecutable(true, false)
        null
    } catch (e: Exception) {
        e.message ?: e.javaClass.simpleName
    }
}

/**
 * MCP 注册：把 cambium mcp（stdio）写进目标 agent 的配置。command 用已解析的引擎绝对路径不行——
 * agent 在自己的环境里跑，PATH 上的 cambium 才是稳定入口（installCli 保证它在）。
 * 幂等：已注册 = 原样成功（调用方重新探测状态就能看到「已注册」）。
 * 返回 null = 成功；非 null = 失败原话。
 */
fun registerMcp(target: AgentTarget, command: String): String? = try {
    when (targetKind(target)) {
        AgentKind.MCP_CLAUDE -> {
            val existing = readTextOrNull(target.file) ?: "{}"
            if (claudeRegistered(existing)) {
                null
            } else {
                val merged = mergeClaudeMcp(existing, command)
                if (merged == null) {
                    "not valid JSON: ${target.file.path}"
                } else {
                    // 第一次改动用户的 agent 配置留一份备份（改坏了有得回）
                    if (existing.isNotBlank()) {
                        val bak = File(target.file.parentFile, target.file.name + ".bak-before-cambium")
                        if (!bak.exists()) bak.writeText(existing)
                    }
                    writeAtomic(target.file, merged)
                    null
                }
            }
        }
        AgentKind.MCP_CODEX -> {
            val existing = readTextOrNull(target.file) ?: ""
            if (codexRegistered(existing)) {
                null
            } else {
                if (existing.isNotBlank()) {
                    val bak = File(target.file.parentFile, target.file.name + ".bak-before-cambium")
                    if (!bak.exists()) bak.writeText(existing)
                }
                writeAtomic(target.file, upsertCodexBlock(existing, command))
                null
            }
        }
        AgentKind.SKILL -> "not an mcp target"
    }
} catch (e: Exception) {
    e.message ?: e.javaClass.simpleName
}

/**
 * Skill 安装：调引擎的 `cambium skill install --dir D`——SKILL.md 的正文只有引擎一个出处，
 * 这里不抄一份。返回 null = 成功；非 null = 失败原话（引擎 stderr/stdout 首行）。
 */
fun installSkill(target: AgentTarget, engineBin: String): String? {
    if (targetKind(target) != AgentKind.SKILL) return "not a skill target"
    return try {
        val (rc, out) = EngineLocator.run(engineBin, listOf("skill", "install", "--dir", target.file.absolutePath))
        if (rc == 0) null else out.trim().lineSequence().firstOrNull { it.isNotBlank() } ?: "exit $rc"
    } catch (e: Exception) {
        e.message ?: e.javaClass.simpleName
    }
}
