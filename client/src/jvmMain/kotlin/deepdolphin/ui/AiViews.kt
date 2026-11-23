// AiViews.kt —— C7 AI 设置页 + C6 AI 助手对话页。
//
// 【key 纪律】key 只进 libsecret（secret-tool 子进程，0600 兜底文件批 4 补）；
// 不进 conf、不进日志。【诚实】未配置给原因与下一步；工具循环事件可见。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import deepdolphin.ai.*
import deepdolphin.engine.EngineLocator
import deepdolphin.sysint.SysInt
import deepdolphin.ui.Palette
import deepdolphin.ui.Radius
import deepdolphin.ui.Space
import deepdolphin.ui.Type
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** key 的安全存储读写（libsecret secret-tool；失败如实告知）。 */
object SecretStore {
    private fun secretTool(vararg args: String): Pair<Int, String> {
        val proc = ProcessBuilder(listOf("secret-tool", *args)).start()
        val out = proc.inputStream.bufferedReader().readText()
        val rc = proc.waitFor()
        return Pair(rc, out.trim())
    }

    /** 保存 key（喂 stdin 给 secret-tool store）。 */
    fun saveKey(key: String): String? = try {
        val proc = ProcessBuilder(
            listOf("secret-tool", "store", "--label=deepDolphin AI Key",
                "application", "deepdolphin", "service", "deepdolphin-ai", "username", "api-key")
        ).start()
        proc.outputStream.use { it.write(key.toByteArray()) }
        val rc = proc.waitFor()
        if (rc == 0) null else "libsecret 返回 $rc（钥匙串未解锁？）"
    } catch (e: Exception) {
        e.message
    }

    fun loadKey(): String? = try {
        val (rc, out) = secretTool(
            "lookup", "application", "deepdolphin", "service", "deepdolphin-ai", "username", "api-key",
        )
        if (rc == 0 && out.isNotBlank()) out else null
    } catch (_: Exception) {
        null
    }
}

/** settings.conf 读写（~/.config/deepDolphin/settings.conf；ai.* 合并纪律见 AiSettings）。 */
object ConfStore {
    private val confFile: File
        get() {
            val xdg = System.getenv("XDG_CONFIG_HOME") ?: System.getProperty("user.home") + "/.config"
            return File("$xdg/deepDolphin/settings.conf").also { it.parentFile?.mkdirs() }
        }

    fun read(): String = if (confFile.isFile) confFile.readText() else ""
    fun writeAi(cfg: AiSettings): String? = try {
        confFile.writeText(AiSettings.mergeInto(read(), cfg))
        null
    } catch (e: Exception) {
        e.message
    }

    fun readAi(): AiSettings = AiSettings.fromConf(read())
}

/**
 * 设置页（mac 原生 Settings scene 的 Linux 对位；侧栏最底部「设置」进入）。
 * 对位 AppSettingsView 的 TabView：通用 / AI / 关于（自动化随后续批收编）。
 */
@Composable
fun SettingsPage(model: AppModel) {
    var tab by remember { mutableStateOf(0) }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState())
            .padding(horizontal = Space.xl, vertical = Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.md),
    ) {
        Text("设置", style = Type.title)
        Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            listOf("通用", "AI", "关于").forEachIndexed { i, label ->
                val selected = tab == i
                Text(
                    label, style = Type.body,
                    color = if (selected) Color.White else Palette.TextSecondary,
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(if (selected) Palette.Accent else Palette.Card)
                        .clickable { tab = i }
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }
        when (tab) {
            0 -> GeneralPane()
            1 -> AiSettingsPane()
            else -> AboutPane()
        }
    }
}

/** 通用 tab：自启动（XDG autostart；仅打包安装态可开——gradle run 无客户端入口）。 */
@Composable
private fun GeneralPane() {
    val entry = remember { autostartEntry() }
    val dir = remember { SysInt.autostartDir() }
    var enabled by remember { mutableStateOf(File(dir, "deepdolphin.desktop").isFile) }
    var message by remember { mutableStateOf<String?>(null) }
    GlassCard(Modifier.fillMaxWidth()) {
        Text("自启动", style = Type.section)
        Spacer(Modifier.height(Space.sm))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("登录时自动启动 deepDolphin", style = Type.body)
                Text(
                    entry?.let { "入口：$it" }
                        ?: "开发模式（gradle run）没有客户端入口，安装 deb/AppImage 后可用",
                    style = Type.micro, color = Palette.TextSecondary,
                )
            }
            Switch(
                checked = enabled && entry != null,
                onCheckedChange = { on ->
                    val e = entry
                    if (e == null) {
                        message = "没有可执行入口（开发模式）；安装后重试"
                        return@Switch
                    }
                    val err = SysInt.setAutostart(dir, e, on)
                    if (err == null) {
                        enabled = on
                        message = if (on) "已写入 ${dir.absolutePath}/deepdolphin.desktop" else "已移除自启条目"
                    } else message = err
                },
                enabled = entry != null,
            )
        }
        message?.let {
            Spacer(Modifier.height(Space.sm))
            Text(it, style = Type.micro, color = Palette.TextSecondary)
        }
    }
}

/** 自启入口探测：打包态 cmdline[0] = launcher（deepdolphin）；gradle run = java → 不可用。 */
private fun autostartEntry(): String? {
    val first = runCatching {
        File("/proc/self/cmdline").readBytes().toString(Charsets.UTF_8)
            .split('\u0000').firstOrNull { it.isNotBlank() }
    }.getOrNull() ?: return null
    return SysInt.autostartClientEntry(first)?.takeIf { File(it).name == "deepdolphin" }
}

/** AI tab（原「AI 设置」页收编；key 纪律与连通性测试不变）。 */
@Composable
fun AiSettingsPane() {
    val saved = remember { ConfStore.readAi() }
    var provider by remember { mutableStateOf(saved.providerID) }
    var model_ by remember { mutableStateOf(saved.model) }
    var baseURL by remember { mutableStateOf(saved.baseURL) }
    var apiKey by remember { mutableStateOf("") } // 不回填明文（只在保存时写入）
    var message by remember { mutableStateOf<String?>(null) }
    var busyTest by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.md)) {
        // 说明走 Markdown 渲染通道（WebView；JCEF 不可用自动回退纯文本并如实标注）
        MarkdownWebView(
            "**key 只进系统安全存储（libsecret）**，不写配置文件、不进日志",
            Modifier.fillMaxWidth(), style = Type.micro, minHeight = 28.dp,
        )

        GlassCard(Modifier.fillMaxWidth()) {
            Text("渠道", style = Type.section)
            Spacer(Modifier.height(Space.sm))
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                listOf(
                    "deepseek" to "DeepSeek（OpenAI 兼容）",
                    "anthropic" to "Anthropic",
                    "ollama" to "Ollama（本地）",
                    "mock" to "mock（本地自测）",
                ).forEach { (id, label) ->
                    val selected = provider == id
                    Text(
                        label, style = Type.body,
                        color = if (selected) Color.White else Palette.TextSecondary,
                        modifier = Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .background(if (selected) Palette.Accent else Palette.Card)
                            .clickable { provider = id }
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                }
            }
            Spacer(Modifier.height(Space.md))
            FieldRow("模型", model_) { model_ = it }
            FieldRow("Base URL", baseURL) { baseURL = it }
            FieldRow("API Key（写入安全存储）", apiKey, password = true) { apiKey = it }
            Spacer(Modifier.height(Space.md))
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                Button(
                    onClick = {
                        val err = ConfStore.writeAi(AiSettings(provider, model_, baseURL))
                        val keyErr = apiKey.takeIf { it.isNotBlank() }?.let { SecretStore.saveKey(it) }
                        message = when {
                            err != null -> "保存失败：$err"
                            keyErr != null -> "渠道已保存，但 key 写入安全存储失败：$keyErr"
                            else -> "已保存（重启后生效）✓"
                        }
                    },
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
                ) { Text("保存") }
                Button(
                    onClick = {
                        busyTest = true
                        scope.launch {
                            val key = withContext(Dispatchers.IO) { SecretStore.loadKey() } ?: ""
                            val cfg = AIConfig(provider, model_, baseURL, key)
                            val engine = AIEngineFactory.create(cfg)
                            var why = ""
                            val ok = engine.isConfigured { why = it }
                            message = if (!ok) {
                                busyTest = false
                                "未配置：$why"
                            } else {
                                val r = engine.generate(GenerateRequest(system = "你是连通性探测器。", messages = listOf(ChatMessage.makeUser("回复「连通」两个字"))))
                                busyTest = false
                                if (r.ok) "连通：${r.text.take(60)}" else "连通失败：${r.error}"
                            }
                        }
                    },
                    enabled = !busyTest,
                    shape = RoundedCornerShape(8.dp),
                ) { Text(if (busyTest) "测试中…" else "测试连接") }
            }
            message?.let {
                Spacer(Modifier.height(Space.sm))
                Text(it, style = Type.body.copy(color = if (it.contains("✓") || it.startsWith("连通：")) Palette.Green else Palette.Amber))
            }
        }
    }
}

/** 关于 tab（诚实边界：版本与判据口径，不编功能清单）。 */
@Composable
private fun AboutPane() {
    GlassCard(Modifier.fillMaxWidth()) {
        Text("deepDolphin", style = Type.section)
        Text("0.1.0 · moonGit 引擎的跨平台桌面客户端（Compose Multiplatform）", style = Type.body.copy(color = Palette.TextSecondary))
        Spacer(Modifier.height(Space.sm))
        Text("引擎判据 61 条，判据只增不减；能力口径以 client/PLAN.md 为准。", style = Type.micro, color = Palette.TextTertiary)
    }
}

@Composable
private fun FieldRow(label: String, value: String, password: Boolean = false, onChange: (String) -> Unit) {
    Column {
        Text(label, style = Type.micro)
        OutlinedTextField(
            value = value,
            onValueChange = onChange,
            singleLine = true,
            visualTransformation = if (password) androidx.compose.ui.text.input.PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
            modifier = Modifier.fillMaxWidth(),
            textStyle = Type.body,
        )
    }
}

/**
 * AI 报告 sheet（对位 mac AIResultSheet/AgentView：没有独立入口、没有「AI 助手」按钮——
 * AI 融进操作：深/浅更新完成后就地「AI 解读」、仪表盘/详情页的「项目群说明/项目说明」
 * 都带着预填任务打开（GraphChrome initialTask 同语义；mac GroupBriefButton/ProjectBriefButton 对位）。
 * 作用域跟随侧栏选中；最新一条回答走 Markdown 排版（AIResultSheet 的报告形态），
 * 底部输入行可就地追问（多轮）。
 */
@Composable
fun AgentSheet(model: AppModel) {
    val selected by model.selectedProject.collectAsState()
    val task by model.agentTask.collectAsState()
    val title by model.agentTitle.collectAsState()
    val projectCount = model.status.value?.projects?.size ?: 0
    val scopeLabel = selected ?: "项目群（全部 $projectCount 个项目）"
    Dialog(
        onDismissRequest = { model.closeAgent() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            Modifier.fillMaxWidth(0.62f).fillMaxHeight(0.8f)
                .clip(RoundedCornerShape(Radius.card))
                .background(Palette.Card)
                .border(1.dp, Palette.Stroke, RoundedCornerShape(Radius.card))
                .padding(Space.lg),
        ) {
            AgentConversation(model, scopeLabel, task, title)
        }
    }
}

@Composable
private fun AgentConversation(model: AppModel, scopeLabel: String, initialTask: String?, initialTitle: String?) {
    var draft by remember { mutableStateOf("") }
    var messages by remember { mutableStateOf(listOf<ChatMessage>()) }
    var busy by remember { mutableStateOf(false) }
    var errorBanner by remember { mutableStateOf<String?>(null) }
    var events by remember { mutableStateOf(listOf<String>()) }
    val scope = rememberCoroutineScope()
    val cancelFlag = remember { java.util.concurrent.atomic.AtomicInteger(0) }

    // 预填任务自动发送（AIResultSheet 的「打开即跑」对位）；只发一次（messages 空时）
    fun send(q: String) {
        if (q.isBlank() || busy) return
        draft = ""
        busy = true
        errorBanner = null
        cancelFlag.set(0)
        events = emptyList()
        val history = messages
        messages = history + ChatMessage.makeUser(q)
        scope.launch(Dispatchers.Default) {
            val engine = model.engine
            val saved = ConfStore.readAi()
            val key = withContext(Dispatchers.IO) { SecretStore.loadKey() } ?: ""
            val cfg = AIConfig(saved.providerID, saved.model, saved.baseURL, key)
            val core = AgentCore(model.engine.bin.ifBlank { engineBinPath() })
            val (convo, err) = core.run(
                engine, q, history, scopeLabel, cfg, cancelFlag,
            ) { ev ->
                events = events + ev
            }
            kotlinx.coroutines.withContext(Dispatchers.Main) {
                busy = false
                if (err.isNotEmpty()) {
                    errorBanner = err
                } else {
                    messages = convo
                }
            }
        }
    }

    LaunchedEffect(initialTask) {
        initialTask?.takeIf { messages.isEmpty() }?.let { send(it) }
    }

    Column(Modifier.fillMaxSize().padding(Space.lg)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                // 头部措辞按入口：说明入口给「项目群说明/项目说明」，更新解读与裸入口保持既有口径
                val head = initialTitle ?: if (initialTask != null) "更新解读" else "AI"
                Text("$head · $scopeLabel", style = Type.title)
                Text("它只根据引擎返回的事实回答——工具没给的数据，它会说「不知道」。", style = Type.micro)
            }
            ActionText("停止", Palette.Amber, enabled = busy) {
                cancelFlag.set(1)
                busy = false
            }
            Spacer(Modifier.width(Space.sm))
            ActionText("关闭", Palette.TextSecondary, enabled = true) { model.closeAgent() }
        }
        Spacer(Modifier.height(Space.md))
        // 消息区
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(Space.sm),
        ) {
            if (messages.isEmpty()) {
                Text("还没聊过", style = Type.section.copy(color = Palette.TextSecondary))
                Text("问项目群现状、问某个项目的分支。它只根据引擎返回的事实回答——工具没给的数据，它会说「不知道」。", style = Type.body.copy(color = Palette.TextSecondary))
            }
            val lastAssistant = messages.indexOfLast { it.role == Role.assistant }
            messages.forEachIndexed { idx, m ->
                when (m.role) {
                    Role.user -> Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                        Box(
                            Modifier.clip(RoundedCornerShape(10.dp)).background(Palette.Accent.copy(alpha = 0.18f))
                                .padding(10.dp)
                        ) { Text(m.text, style = Type.body) }
                    }
                    Role.assistant -> GlassCard(Modifier.fillMaxWidth()) {
                        if (idx == lastAssistant) {
                            MarkdownWebView(m.text, Modifier.fillMaxWidth())
                        } else {
                            Text(m.text, style = Type.body)
                        }
                    }
                    else -> if (m.isError) Text("⚠ ${m.text.take(120)}", style = Type.micro.copy(color = Palette.Amber))
                }
            }
            if (events.isNotEmpty()) GlassCard(Modifier.fillMaxWidth()) {
                events.forEach { Text(it, style = Type.micro, color = Palette.TextSecondary) }
            }
            errorBanner?.let {
                GlassCard(Modifier.fillMaxWidth()) {
                    Text(it, style = Type.body.copy(color = Palette.Amber))
                }
            }
        }
        Spacer(Modifier.height(Space.md))
        // 输入行（脱窗缘呼吸）
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                placeholder = { Text("问点什么…", style = Type.body.copy(color = Palette.TextSecondary)) },
                modifier = Modifier.weight(1f),
                textStyle = Type.body,
                enabled = !busy,
            )
            Spacer(Modifier.width(Space.sm))
            Button(
                onClick = {
                    val q = draft.trim()
                    if (q.isBlank() || busy) return@Button
                    send(q)
                },
                enabled = !busy && draft.isNotBlank(),
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
            ) { Text(if (busy) "思考中…" else "发送") }
        }
    }
}

/** 引擎 bin 的兜底解析（对话期探活缓存失效时的救急）。 */
private fun engineBinPath(): String = System.getenv("MOONGIT_BIN") ?: System.getenv("DEEPGIT_BIN") ?: "moongit"
