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
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
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
import androidx.compose.foundation.layout.PaddingValues

/** key 的安全存储读写（libsecret secret-tool；失败如实告知）。 */
object SecretStore {
    /** 兜底文件：$XDG_CONFIG_HOME/deepDolphin/ai.key（仅本人可读）。 */
    internal fun keyFile(): File = File(ConfStore.dir(), "ai.key")

    /** 没装 secret-tool（IOException）返回 null；装了就返回 (退出码, 输出)。 */
    private fun secretLookup(): Pair<Int, String>? = try {
        val proc = ProcessBuilder(
            listOf("secret-tool", "lookup", "application", "deepdolphin", "service", "deepdolphin-ai", "username", "api-key"),
        ).start()
        val out = proc.inputStream.bufferedReader(Charsets.UTF_8).readText()
        proc.errorStream.bufferedReader(Charsets.UTF_8).readText()
        Pair(proc.waitFor(), out.trim())
    } catch (_: java.io.IOException) {
        null
    }

    private fun secretStore(key: String): Boolean = try {
        val proc = ProcessBuilder(
            listOf("secret-tool", "store", "--label=deepDolphin AI Key",
                "application", "deepdolphin", "service", "deepdolphin-ai", "username", "api-key"),
        ).start()
        proc.outputStream.use { it.write(key.toByteArray(Charsets.UTF_8)) }
        proc.inputStream.bufferedReader(Charsets.UTF_8).readText()
        proc.errorStream.bufferedReader(Charsets.UTF_8).readText()
        proc.waitFor() == 0
    } catch (_: Exception) {
        false
    }

    private fun secretClear() {
        try {
            val proc = ProcessBuilder(
                listOf("secret-tool", "clear", "application", "deepdolphin", "service", "deepdolphin-ai", "username", "api-key"),
            ).start()
            proc.waitFor()
        } catch (_: Exception) {
            /* 没有 secret-tool：兜底文件删掉即可 */
        }
    }

    private fun writeKeyFile(key: String): String? = try {
        val f = keyFile()
        f.parentFile?.mkdirs()
        val path = f.toPath()
        java.nio.file.Files.writeString(path, key, Charsets.UTF_8)
        java.nio.file.Files.setPosixFilePermissions(
            path,
            setOf(java.nio.file.attribute.PosixFilePermission.OWNER_READ, java.nio.file.attribute.PosixFilePermission.OWNER_WRITE),
        )
        null
    } catch (e: Exception) {
        e.message ?: e.javaClass.simpleName
    }

    /** 保存 key。null = 成功；否则是失败原因。 */
    fun saveKey(key: String): String? {
        if (key.contains('\n')) return "key 不能包含换行"
        if (secretStore(key)) {
            // 钥匙串成功：别再留一份兜底文件
            keyFile().delete()
            return null
        }
        return writeKeyFile(key)
    }

    /** key 存在哪（给保存后的提示用）。 */
    fun whereStored(): String =
        if (keyFile().isFile) L10n.t("cmp.ai.storedFile") else L10n.t("cmp.ai.storedSecret")

    fun loadKey(): String? {
        // 1) libsecret；读不出来（没装 / 钥匙串锁着）不等于「没填」——继续看兜底文件
        val hit = secretLookup()
        if (hit != null && hit.first == 0 && hit.second.isNotBlank()) return hit.second
        // 2) 兜底文件
        return try {
            keyFile().takeIf { it.isFile }?.readText(Charsets.UTF_8)?.trim()?.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        }
    }

    /** 清除已存 key（钥匙串 + 兜底文件）。 */
    fun clearKey() {
        secretClear()
        keyFile().delete()
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

    /** 配置目录（~/.config/deepDolphin；XDG 可改）。 */
    fun dir(): File = confFile.parentFile!!.also { it.mkdirs() }

    fun writeAi(cfg: AiSettings): String? = try {
        confFile.writeText(AiSettings.mergeInto(read(), cfg))
        null
    } catch (e: Exception) {
        e.message
    }

    fun readAi(): AiSettings = AiSettings.fromConf(read())

    /** 定时更新（update.* 独立节，mac "update.autoHours" UserDefaults 键的 conf 对位）。 */
    fun writeAuto(cfg: AutoUpdateSettings): String? = try {
        confFile.writeText(AutoUpdateSettings.mergeInto(read(), cfg))
        null
    } catch (e: Exception) {
        e.message
    }

    fun readAuto(): AutoUpdateSettings = AutoUpdateSettings.fromConf(read())

    /** 界面语言（app.language 独立键节，mac UserDefaults "app.language" 的 conf 对位）。 */
    fun writeLanguage(lang: AppLanguage): String? = try {
        confFile.writeText(L10n.mergeLanguageInto(read(), lang))
        null
    } catch (e: Exception) {
        e.message
    }
}

/**
 * 设置页（mac 原生 Settings scene 的 Linux 对位；侧栏最底部「设置」进入）。
 * 对位 AppSettingsView 的 TabView：通用 / AI / 自动化 / 关于（ScheduleCard 收编为第四 tab 前的
 * 「自动化随后续批收编」已于本批落地）。
 */
@Composable
fun SettingsPage(model: AppModel) {
    var tab by remember { mutableStateOf(0) }
    // 菜单「关于 / 帮助」先切到「关于」tab（索引 3），子 tab 由 AboutPane 按同一请求选定；
    // 原来只有 AboutPane 订阅，而它要等「关于」tab 组合后才存在——帮助菜单因此落到「通用」
    LaunchedEffect(Unit) {
        DocsNav.request.collect { kind -> if (kind != null) tab = 3 }
    }
    // 版面：标题 → 贯通内容区宽度的页签条（Fluent Pivot）→ 可滚动的内容
    Column(Modifier.fillMaxSize()) {
        Text(L10n.t("toolbar.settings"), style = Type.title, modifier = Modifier.padding(horizontal = Space.xl, vertical = Space.lg))
        Pivot(
            listOf(L10n.t("settings.general"), L10n.t("settings.ai"), L10n.t("settings.automation"), L10n.t("settings.about")),
            selected = tab,
            onSelect = { tab = it },
        )
        ScrollColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = Space.xl, vertical = Space.lg),
            verticalArrangement = Arrangement.spacedBy(Space.md),
        ) {
            when (tab) {
                0 -> GeneralPane()
                1 -> AiSettingsPane()
                2 -> SchedulePane(model)
                else -> AboutPane()
            }
        }
    }
}

/**
 * 通用 tab：语言选择器（mac GeneralTab Picker 对位：简体中文/English/繁體中文/日本語，
 * 即时生效——L10n.language 是 Compose 状态，一翻全界面）+ 自启动
 * （XDG autostart；仅打包安装态可开——gradle run 无客户端入口）。
 */
@Composable
private fun GeneralPane() {
    LanguageCard()
    AutostartCard()
}

/** 语言卡（mac GeneralTab 第一 Section：Picker → CMP 用 ChoicePill 行，选中即写 settings.conf）。 */
@Composable
private fun LanguageCard() {
    // 读 L10n.language（Compose 状态）：别处切了语言这里同步高亮
    val current = L10n.language
    var message by remember { mutableStateOf<String?>(null) }
    GlassCard(Modifier.fillMaxWidth()) {
        Text(L10n.t("settings.language"), style = Type.section)
        Spacer(Modifier.height(Space.sm))
        Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            AppLanguage.entries.forEach { lang ->
                // label 永远用本名显示（mac 同款——语言名不参与翻译）
                ChoicePill(lang.label, selected = current == lang) {
                    val err = L10n.setLanguage(lang)
                    message = err?.let { L10n.t("cmp.settings.languageWriteFailed", it) }
                }
            }
        }
        message?.let {
            Spacer(Modifier.height(Space.sm))
            Text(it, style = Type.micro, color = Palette.Amber)
        }
    }
}

/** 自启动卡（mac GeneralTab 第二 Section 的 Linux XDG 对位）。 */
@Composable
private fun AutostartCard() {
    val entry = remember { autostartEntry() }
    val dir = remember { SysInt.autostartDir() }
    var enabled by remember { mutableStateOf(File(dir, "deepdolphin.desktop").isFile) }
    var message by remember { mutableStateOf<String?>(null) }
    GlassCard(Modifier.fillMaxWidth()) {
        Text(L10n.t("cmp.settings.autostartShort"), style = Type.section)
        Spacer(Modifier.height(Space.sm))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(L10n.t("settings.autostartToggle"), style = Type.body)
                Text(
                    entry?.let { L10n.t("cmp.settings.entryPath", it) }
                        ?: L10n.t("cmp.settings.autostartDevNote"),
                    style = Type.micro, color = Palette.TextSecondary,
                )
            }
            Switch(
                colors = fluentSwitchColors(),
                checked = enabled && entry != null,
                onCheckedChange = { on ->
                    val e = entry
                    if (e == null) {
                        message = L10n.t("cmp.settings.autostartNoEntry")
                        return@Switch
                    }
                    val err = SysInt.setAutostart(dir, e, on)
                    if (err == null) {
                        enabled = on
                        message = if (on) L10n.t("cmp.settings.autostartWritten", dir.absolutePath)
                        else L10n.t("cmp.settings.autostartRemoved")
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

/**
 * 自动化 tab（mac AppSettingsView 第四 tab 的 ScheduleCard 对位，AISettingsView.swift:257-284
 * 原文形态：grouped 卡片 + 间隔选择器 + 两条说明，无保存按钮——立即生效）。
 * 本版多一个轨道选择（浅/深，任务口径「定时浅/深更新」）；mac 版只有浅轨道
 * （runScheduledUpdate 固定 deep: false）——差异如实写进卡片说明，不冒充同款。
 */
@Composable
private fun SchedulePane(model: AppModel) {
    var cfg by remember { mutableStateOf(model.autoUpdateSettings()) }
    var message by remember { mutableStateOf<String?>(null) }

    fun apply(next: AutoUpdateSettings) {
        cfg = next
        val err = model.setAutoUpdate(next)
        message = when {
            err != null -> L10n.t("cmp.schedule.writeFailed", err)
            next.hours <= 0 -> L10n.t("cmp.schedule.disabledOk")
            else -> L10n.t("cmp.schedule.enabledOk", next.hours, L10n.t(if (next.deep) "bulk.deepWord" else "bulk.shallowWord"))
        }
    }

    GlassCard(Modifier.fillMaxWidth()) {
        Text(L10n.t("schedule.label"), style = Type.section)
        Spacer(Modifier.height(Space.sm))
        Text(L10n.t("cmp.schedule.interval"), style = Type.micro, color = Palette.TextSecondary)
        Spacer(Modifier.height(Space.xs))
        Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            AutoUpdateSettings.HOUR_CHOICES.forEach { h ->
                val label = L10n.t(when (h) { 0 -> "schedule.off"; 1 -> "schedule.h1"; 3 -> "schedule.h3"; 6 -> "schedule.h6"; 12 -> "schedule.h12"; 24 -> "schedule.h24"; else -> return@forEach })
                ChoicePill(label, selected = cfg.hours == h) { apply(cfg.copy(hours = h)) }
            }
        }
        Spacer(Modifier.height(Space.md))
        Text(L10n.t("cmp.schedule.track"), style = Type.micro, color = Palette.TextSecondary)
        Spacer(Modifier.height(Space.xs))
        Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            ChoicePill(L10n.t("cmp.schedule.trackShallow"), selected = !cfg.deep) { apply(cfg.copy(deep = false)) }
            ChoicePill(L10n.t("cmp.schedule.trackDeep"), selected = cfg.deep) { apply(cfg.copy(deep = true)) }
        }
        Spacer(Modifier.height(Space.md))
        Text(L10n.t("cmp.schedule.note1"), style = Type.micro, color = Palette.TextSecondary)
        Text(L10n.t("cmp.schedule.note2"), style = Type.micro, color = Palette.TextSecondary)
        Text(
            L10n.t("cmp.schedule.macDiff"),
            style = Type.micro, color = Palette.TextTertiary,
        )
        message?.let {
            Spacer(Modifier.height(Space.sm))
            Text(it, style = Type.body.copy(color = if (it.contains("✓")) Palette.Green else Palette.Amber))
        }
    }
}

/** 选择胶囊（间隔 / 轨道 / 语言 / 关于子页签共用）：选中 accent 底配近黑字——accent 是亮蓝，白字压上去只有 2:1。 */
@Composable
private fun ChoicePill(label: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        label, style = Type.body,
        color = if (selected) Palette.OnAccent else Palette.TextSecondary,
        modifier = Modifier
            .clip(RoundedCornerShape(Radius.control))
            .background(if (selected) Palette.Accent else Palette.Card)
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
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
    var busySave by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.md)) {
        // 原生 Markdown（说明里带 **粗体**；纯 Text 会把星号显示出来）
        MarkdownText(L10n.t("cmp.ai.keyNote"), style = Type.micro)

        GlassCard(Modifier.fillMaxWidth()) {
            Text(L10n.t("cmp.ai.provider"), style = Type.section)
            Spacer(Modifier.height(Space.sm))
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                listOf(
                    "deepseek" to L10n.t("cmp.ai.providerDeepseek"),
                    "anthropic" to "Anthropic",
                    "ollama" to L10n.t("cmp.ai.providerOllama"),
                    "mock" to L10n.t("cmp.ai.providerMock"),
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
            FieldRow(L10n.t("cmp.ai.model"), model_) { model_ = it }
            FieldRow(L10n.t("cmp.ai.baseUrl"), baseURL) { baseURL = it }
            FieldRow(L10n.t("cmp.ai.apiKey"), apiKey, password = true) { apiKey = it }
            // 输入框不回填明文，留空有歧义：给一个明确的「清除已存 key」
            ActionText(L10n.t("cmp.ai.clearKey"), Palette.TextSecondary, enabled = !busySave) {
                scope.launch {
                    withContext(Dispatchers.IO) { SecretStore.clearKey() }
                    message = L10n.t("cmp.ai.keyCleared")
                }
            }
            Spacer(Modifier.height(Space.md))
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                Button(
                    onClick = {
                        busySave = true
                        scope.launch {
                            // secret-tool 是子进程：放 IO 线程，别卡界面
                            val (err, keyErr, where) = withContext(Dispatchers.IO) {
                                Triple(
                                    ConfStore.writeAi(AiSettings(provider, model_, baseURL)),
                                    apiKey.takeIf { it.isNotBlank() }?.let { SecretStore.saveKey(it) },
                                    if (apiKey.isNotBlank()) SecretStore.whereStored() else null,
                                )
                            }
                            message = when {
                                err != null -> L10n.t("cmp.ai.saveFailed", err)
                                keyErr != null -> L10n.t("cmp.ai.saveKeyFailed", keyErr)
                                else -> L10n.t("cmp.ai.savedOk") + (where?.let { " " + it } ?: "")
                            }
                            busySave = false
                        }
                    },
                    enabled = !busySave,
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Palette.OnAccent),
                ) { Text(L10n.t("common.save")) }
                Button(
                    onClick = {
                        busyTest = true
                        scope.launch {
                            // 测的是**输入框里的** key（没填才用已存的）——
                            // 原来只测已存的：新填的 key 没保存先测会报「API Key 为空」，或拿旧 key 得出错误结论
                            val key = apiKey.trim().ifBlank { withContext(Dispatchers.IO) { SecretStore.loadKey() } ?: "" }
                            val cfg = AIConfig(provider, model_, baseURL, key)
                            val engine = AIEngineFactory.create(cfg)
                            var why = ""
                            val ok = engine.isConfigured { why = it }
                            message = if (!ok) {
                                busyTest = false
                                L10n.t("cmp.ai.notConfigured", why)
                            } else {
                                val r = engine.generate(GenerateRequest(system = "你是连通性探测器。", messages = listOf(ChatMessage.makeUser("回复「连通」两个字"))))
                                busyTest = false
                                if (r.ok) L10n.t("cmp.ai.testOk", r.text.take(60)) else L10n.t("cmp.ai.testFailed", r.error)
                            }
                        }
                    },
                    enabled = !busyTest,
                    shape = RoundedCornerShape(8.dp),
                ) { Text(if (busyTest) L10n.t("cmp.ai.testing") else L10n.t("cmp.ai.test")) }
            }
            message?.let {
                Spacer(Modifier.height(Space.sm))
                Text(it, style = Type.body.copy(color = if (it.contains("✓") || it.startsWith(L10n.t("cmp.ai.testOk", ""))) Palette.Green else Palette.Amber))
            }
        }
    }
}

/**
 * 关于 tab（mac AboutCombinedTab 对位）：版本与判据口径卡 + 四文档子 tab
 * （关于/帮助/开源感谢/更新日志，对位 mac DocsPages 四语言内容——L10n.doc 随语言取）。
 * 一次只渲染当前子 tab 的文档；内容是静态文本，切 tab 不重跑引擎。
 * 渲染走原生 MarkdownText（不起 WebView）。
 */
@Composable
private fun AboutPane() {
    var docTab by remember { mutableStateOf(DocKind.ABOUT) }
    // 菜单深开的请求在这里消费：切到对应子 tab 后清空（否则下次进设置页会再跳一次）
    LaunchedEffect(Unit) {
        DocsNav.request.collect { kind -> kind?.let { docTab = it; DocsNav.request.value = null } }
    }
    GlassCard(Modifier.fillMaxWidth()) {
        Text("deepDolphin", style = Type.section)
        Text(L10n.t("cmp.about.versionLine"), style = Type.body.copy(color = Palette.TextSecondary))
        Spacer(Modifier.height(Space.sm))
        MarkdownText(L10n.t("cmp.about.criteriaNote"), style = Type.micro.copy(color = Palette.TextTertiary))
    }
    Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
        DocKind.entries.forEach { kind ->
            ChoicePill(L10n.t(kind.titleKey), selected = docTab == kind) { docTab = kind }
        }
    }
    // 原生 Markdown 渲染（不起 WebView）；文档是 Markdown，原样显示会满屏 ## 和 **
    MarkdownText(L10n.doc(docTab), Modifier.fillMaxWidth().heightIn(min = 320.dp))
}

@Composable
private fun FieldRow(label: String, value: String, password: Boolean = false, onChange: (String) -> Unit) {
    Column {
        Text(label, style = Type.micro)
        OutlinedTextField(
            colors = fluentTextFieldColors(),
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
    val scopeLabel = selected ?: L10n.t("cmp.agent.scopeAll", projectCount)
    Dialog(
        onDismissRequest = { model.closeAgent() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            Modifier.fillMaxWidth(0.62f).fillMaxHeight(0.8f)
                .clip(RoundedCornerShape(Radius.card))
.shadow(12.dp, RoundedCornerShape(Radius.card))
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
                val head = initialTitle ?: if (initialTask != null) L10n.t("cmp.agent.readback") else "AI"
                Text("$head · $scopeLabel", style = Type.title)
                Text(L10n.t("cmp.agent.factNote"), style = Type.micro)
            }
            ActionText(L10n.t("agent.stop"), Palette.Amber, enabled = busy) {
                cancelFlag.set(1)
                busy = false
            }
            Spacer(Modifier.width(Space.sm))
            ActionText(L10n.t("common.close"), Palette.TextSecondary, enabled = true) { model.closeAgent() }
        }
        Spacer(Modifier.height(Space.md))
        // 消息区
        ScrollColumn(
            Modifier.weight(1f).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(Space.sm),
        ) {
            if (messages.isEmpty()) {
                Text(L10n.t("cmp.agent.noHistory"), style = Type.section.copy(color = Palette.TextSecondary))
                Text(L10n.t("cmp.agent.noHistoryHint"), style = Type.body.copy(color = Palette.TextSecondary))
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
                    // 助手回答全部原生 Markdown（不再只给最新一条走 WebView）：不起 JCEF，
                    // 历史消息同样有代码块/列表/表格排版
                    Role.assistant -> GlassCard(Modifier.fillMaxWidth()) {
                        MarkdownText(m.text, Modifier.fillMaxWidth())
                    }
                    else -> if (m.isError) Row(verticalAlignment = Alignment.CenterVertically) {
                        IconBox(FluentIcon.Warning, size = 14.dp, tint = Palette.Amber)
                        Spacer(Modifier.width(6.dp))
                        Text(m.text.take(120), style = Type.micro.copy(color = Palette.Amber))
                    }
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
                colors = fluentTextFieldColors(),
                value = draft,
                onValueChange = { draft = it },
                placeholder = { Text(L10n.t("cmp.agent.askPlaceholder"), style = Type.body.copy(color = Palette.TextSecondary)) },
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
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Palette.OnAccent),
            ) { Text(if (busy) L10n.t("cmp.agent.thinkingShort") else L10n.t("agent.send")) }
        }
    }
}

/** 引擎 bin 的兜底解析（对话期探活缓存失效时的救急）。 */
private fun engineBinPath(): String = System.getenv("MOONGIT_BIN") ?: System.getenv("DEEPGIT_BIN") ?: "moongit"
