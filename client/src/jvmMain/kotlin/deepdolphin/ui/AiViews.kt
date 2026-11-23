// AiViews.kt —— C7 AI 设置页 + C6 AI 助手对话页。
//
// 【key 纪律】key 只进 libsecret（secret-tool 子进程，0600 兜底文件批 4 补）；
// 不进 conf、不进日志。【诚实】未配置给原因与下一步；工具循环事件可见。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import deepdolphin.ai.*
import deepdolphin.engine.EngineLocator
import deepdolphin.ui.Palette
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

@Composable
fun AiSettingsPage(model: AppModel) {
    val saved = remember { ConfStore.readAi() }
    var provider by remember { mutableStateOf(saved.providerID) }
    var model_ by remember { mutableStateOf(saved.model) }
    var baseURL by remember { mutableStateOf(saved.baseURL) }
    var apiKey by remember { mutableStateOf("") } // 不回填明文（只在保存时写入）
    var message by remember { mutableStateOf<String?>(null) }
    var busyTest by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState())
            .padding(horizontal = Space.xl, vertical = Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.md),
    ) {
        Text("AI 设置", style = Type.title)
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
 * C6 AI 助手对话页（工具循环事件可见）。
 * Markdown 渲染（C6 收尾批）：只有【最新一条】助手消息走 WebView 排版
 * （代码块等宽/表格/列表；JCEF 缺席/装载失败自动回退纯文本并如实标注），
 * 历史助手消息保持纯文本 Text——webview 是重量组件（独立渲染进程），
 * 每条消息一个会把 Compose verticalScroll 列表压垮；最新回答是排版收益最高的
 * 那条，单 WebView 内部由 markdown 变化驱动同一 browser 重载。
 * 用户消息保持气泡纯文本（本批边界）。
 */
@Composable
fun AiChatPage(model: AppModel) {
    var draft by remember { mutableStateOf("") }
    var messages by remember { mutableStateOf(listOf<ChatMessage>()) }
    var busy by remember { mutableStateOf(false) }
    var errorBanner by remember { mutableStateOf<String?>(null) }
    var events by remember { mutableStateOf(listOf<String>()) }
    val scope = rememberCoroutineScope()
    val cancelFlag = remember { java.util.concurrent.atomic.AtomicInteger(0) }

    Column(Modifier.fillMaxSize().padding(Space.lg)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("AI 助手", style = Type.title)
                Text("作用域 · 项目群（全部 ${model.status.value?.projects?.size ?: 0} 个项目）", style = Type.micro)
            }
            ActionText("停止", Palette.Amber, enabled = busy) {
                cancelFlag.set(1)
                busy = false
            }
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
                            engine, q, history, "项目群（全部）", cfg, cancelFlag,
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
