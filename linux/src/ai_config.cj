// deepDolphin Linux 客户端 —— AI 配置（C7）。
//
// 与 macOS 端 `AISDK.swift` 的 `AIConfig` 逐条对齐：同样的字段、
// 同样的 `effectiveBaseURL` 规则、同样的「保存失败要说出口」。
//
// 【边界】密钥**永不进引擎、永不进命令行、永不进日志**。
// 本文件只负责「存」和「读」，发请求在 ai_http.cj。
package deepdolphin_linux

import std.fs.*
import std.env.*
import std.collection.*

/// libsecret 的 service 名。与 macOS 端 Keychain 的 service 同名同义，
/// 这样两端的凭据在各自的系统钥匙串里指向同一件事。
private const AI_KEYRING_SERVICE: String = "cn.deepdolphin.app.ai"

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

/// AI 通道配置。
///
/// **落盘的四个字段**（providerID / model / baseURL / apiKey）与 macOS 端
/// 一一对应，不增不减：多一个字段就多一处两端可能长歪的地方。
/// `loadProblem` 不在其列 —— 它是**读取诊断**，不落盘、不进请求、
/// 两端各自生成，见它的注释。
public class AIConfig {
    /// models.dev 的 provider id（如 deepseek / openai / anthropic / openrouter …）
    public let providerID: String
    public let model: String
    /// 用户手填的端点覆盖。空 = 用目录里的端点。
    public let baseURL: String
    public let apiKey: String
    /// 读取 `settings.json` 时遇到的问题。**空串 = 读得干净**。
    ///
    /// ⚠ 没有它，「文件坏了」与「文件不存在」长得一模一样：
    /// 两者都静默回落 deepseek，用户看到的配置和真正生效的配置是两份
    /// （R1-04）。文件不存在是正常的首次启动，不算问题；
    /// 存在但读不出/解析不了才计进来。
    public let loadProblem: String

    public init(
        providerID!: String = "deepseek",
        model!: String = "",
        baseURL!: String = "",
        apiKey!: String = "",
        loadProblem!: String = ""
    ) {
        this.providerID = providerID
        this.model = model
        this.baseURL = baseURL
        this.apiKey = apiKey
        this.loadProblem = loadProblem
    }

    public func isAnthropic(): Bool {
        return this.providerID == "anthropic"
    }

    /// 实际要用的端点。**空串 = 没配好**，调用方必须拒绝发请求。
    ///
    /// ⚠ 与 macOS 端同一条规则，一个字没改：只放行 `https://`，
    /// `http://` 只对 127.0.0.1 / localhost 豁免。
    /// 理由是**防投毒端点**：目录数据来自网络（models.dev），
    /// 攻击者只要能改目录里一个 api 字段，就能让本客户端把用户的 API Key
    /// 连同每次对话内容 POST 到他的服务器 —— 而用户界面上看不出任何异常。
    /// localhost 豁免是为了本地模型（ollama / LM Studio）能用。
    public func effectiveBaseURL(): String {
        if (!this.baseURL.trimAscii().isEmpty()) {
            return sanitizeBaseURL(this.baseURL)
        }
        let fromCatalog = providerAPIFromSnapshot(this.providerID)
        if (!fromCatalog.isEmpty()) {
            return sanitizeBaseURL(fromCatalog)
        }
        // 目录里没有端点的那些家（openai / deepinfra 在实测快照里 api 就是 null），
        // 只有 anthropic 有内置兜底 —— 与 macOS 端一致。
        return if (this.isAnthropic()) { "https://api.anthropic.com" } else { "" }
    }

    /// 本地模型（ollama）不需要 Key，其余都要。
    public func isConfigured(): Bool {
        if (this.effectiveBaseURL().isEmpty()) {
            return false
        }
        return this.providerID == "ollama" || !this.apiKey.isEmpty()
    }
}

/// 端点清洗。**只放行 https，http 仅对 localhost / 127.0.0.1 豁免。**
/// 纯函数，判据直接喂各种畸形输入。
public func sanitizeBaseURL(raw: String): String {
    let url = raw.trimAscii()
    let lower = asciiLower(url)
    if (lower.startsWith("https://")) {
        return url
    }
    if (lower.startsWith("http://127.0.0.1") || lower.startsWith("http://localhost")) {
        return url
    }
    return ""
}

// ---------------------------------------------------------------------------
// 路径
// ---------------------------------------------------------------------------

/// 配置目录。**遵循 XDG**，没有 `XDG_CONFIG_HOME` 时退回 `~/.config`。
///
/// ⚠ 不用仓内路径存用户数据：那是源码树，不是数据目录。
/// 引擎自己的数据在 `DEEPGIT_HOME`（默认 `~/.deepgit`），两件事分开 ——
/// 卸载客户端不该连累引擎的注册表。
public func aiConfigDir(): String {
    let xdg = (getVariable("XDG_CONFIG_HOME") ?? "").trimAscii()
    if (!xdg.isEmpty() && xdg.startsWith("/")) {
        return "${xdg}/deepdolphin"
    }
    return "${(getVariable("HOME") ?? "")}/.config/deepdolphin"
}

public func aiConfigPath(): String {
    return "${aiConfigDir()}/settings.json"
}

/// 密钥兜底文件。**只存密钥**，且权限 0600。
public func aiKeyFilePath(): String {
    return "${aiConfigDir()}/api-key"
}

/// libsecret 的命令行前端。**没有它就没有系统钥匙环**。
/// 位置先走 PATH，找不到再回退 /usr/bin（钉死一个绝对路径会错过
/// 装在 PATH 别处的同名工具，与 curl / notify-send 同一条规则）。
private const SECRET_TOOL_FALLBACK: String = "/usr/bin/secret-tool"

private func secretToolBin(): String {
    let p = firstToolOnPath(["secret-tool"])
    return (if (p.isEmpty()) { SECRET_TOOL_FALLBACK } else { p })
}

public func hasSecretTool(): Bool {
    return exists(secretToolBin())
}

// ---------------------------------------------------------------------------
// 落盘
// ---------------------------------------------------------------------------

/// 建目录，并把目录权限收紧到 **700**。返回空串 = 就绪；非空 = 给用户看的原因。
/// （包内多处要用 —— ai_http 的请求临时文件也落在这里，所以不再是 private。）
///
/// 仓颉 1.0.5 的 `std.fs` **没有** `mkdir`（实测：chdir/mkdir/
/// stat 全是 undeclared identifier，只有 `exists`/`remove`/`copy`/`rename`），
/// 所以走子进程。目录建不出来必须报错，不许静默 —— 后面每一次写都会失败。
///
/// ⚠ chmod 700 是**安全闭环的必要一半**（R1-05）：这个目录里存 API Key 的
/// 兜底明文和 AI 请求的临时文件。临时文件从创建到 chmod 之间按 umask 生成
/// （常见 0644），单靠「写完再 chmod 文件」挡不住那个瞬间 —— 目录 700 之后
/// 其他用户根本进不来，窗口才真正闭合。老版本建出的目录可能还是 755，
/// 所以**每次都收紧一遍**（幂等，成本是一次子进程，写路径全在后台线程）。
func ensureConfigDir(): String {
    let dir = aiConfigDir()
    if (!exists(dir)) {
        let r = execCapture("/bin/mkdir", ["-p", dir], 5000)
        if (r.timedOut) {
            return "建配置目录超时：${dir}"
        }
        if (r.exitCode != 0) {
            let why = if (!r.stderr.trimAscii().isEmpty()) { r.stderr.trimAscii() } else {
                "退出码 ${r.exitCode}"
            }
            return "建配置目录失败（${why}）：${dir}"
        }
    }
    let r = execCapture("/bin/chmod", ["700", dir], 5000)
    if (r.timedOut || r.exitCode != 0) {
        let why = if (r.timedOut) { "chmod 超时" } else {
            if (!r.stderr.trimAscii().isEmpty()) { r.stderr.trimAscii() } else { "退出码 ${r.exitCode}" }
        }
        return "配置目录权限没能收紧到 700（${why}）：${dir} —— 里面存密钥，宁可不用也不敞着"
    }
    return ""
}

/// 进程内递增计数，给临时文件名防撞（同一毫秒内可能写两个文件）。
private var privateWriteSeq: Int64 = 0

/// 原子替换写一个 **0600** 的私有文件。返回空串 = 成功；非空 = 给用户看的失败原因。
///
/// 步骤与顺序是承重的（R1-05）：
///   1. **同目录**先写临时文件（名字带毫秒 + 进程内计数，不会撞上别的调用）；
///   2. 立即 chmod 600 **临时文件** —— 这是这份内容第一次碰到磁盘，
///      600 必须赶在它出现在**最终路径**之前生效；
///   3. `rename(overwrite: true)` 原子替换（实测语义：目标存在则整个换掉，
///      同文件系统内是原子的）。中途失败/被杀，旧文件要么完整、要么没动 ——
///      不会出现「旧密钥已删、新密钥没写上」的空档。
///
/// ⚠ 旧实现是 remove → writeTo → chmod：文件先按 umask（常见 0644）出现在
/// 最终路径上、之后才收紧，密钥存在一个全局可读的窗口；而且 remove 之后
/// 任何一步失败 = 旧内容已经丢了。两个毛病都从这里改掉。
/// `File.writeTo` 不保证截断已有文件（「旧比新长会留尾巴」），
/// 临时文件每次都是新名字，这个坑也顺带不存在了。
///
/// 【前置】目录已就绪（调用方先过 `ensureConfigDir`），且与最终文件**同一
/// 文件系统**（rename 跨文件系统会失败 —— 临时文件就放在目标旁边）。
func writePrivateFile(path: String, content: String, what: String): String {
    privateWriteSeq += 1
    let tmp = "${path}.tmp-${nowMillis()}-${privateWriteSeq}"
    try {
        File.writeTo(tmp, content.toArray())
    } catch (e: Exception) {
        return "${what}没能写进临时文件（${e.message}）：${path}"
    }
    let cm = execCapture("/bin/chmod", ["600", tmp], 5000)
    if (cm.timedOut || cm.exitCode != 0) {
        removeQuiet(tmp)
        let why = if (cm.timedOut) { "chmod 超时" } else { "chmod 退出码 ${cm.exitCode}" }
        return "${what}的权限没能收紧到 600（${why}），已放弃替换：${path}"
    }
    try {
        rename(Path(tmp), to: Path(path), overwrite: true)
    } catch (e: Exception) {
        removeQuiet(tmp)
        return "${what}没能原子替换（${e.message}）：${path}"
    }
    return ""
}

/// 尽力删，删不掉也不抛 —— finally 清理与失败回滚用这个。
/// 真删不掉的残留由启动清扫（sweepAITempLeftovers）兜底。
func removeQuiet(path: String): Unit {
    try {
        remove(path)
    } catch (e: Exception) {
        ()
    }
}

/// 读配置 + 读密钥。**读不出来给默认值，不抛** —— 客户端不该因为
/// 配置文件损坏就起不来；但「回落了」这件事沿 `AIConfig.loadProblem`
/// 说出来，不再静默（R1-04）。
public func loadAIConfig(): AIConfig {
    var pid = "deepseek"
    var mdl = ""
    var base = ""
    var problem = ""
    let p = aiConfigPath()
    if (exists(p)) {
        var text = ""
        try {
            text = fromUtf8Lossy(File.readFrom(p))
        } catch (e: Exception) {
            problem = "设置文件读不出来（${e.message}），provider/模型回落为默认值：${p}"
        }
        if (problem.isEmpty()) {
            let parsed = parseAIConfigDoc(text, p)
            pid = parsed.providerID
            mdl = parsed.model
            base = parsed.baseURL
            problem = parsed.loadProblem
        }
    }
    return AIConfig(providerID: pid, model: mdl, baseURL: base, apiKey: loadAIKey(), loadProblem: problem)
}

/// `settings.json` 文本 → 配置。**纯函数**，判据直接喂坏文本。
/// 解析不了不抛也不静默：字段回落默认值，`loadProblem` 里给原因与文件路径。
public func parseAIConfigDoc(text: String, path: String): AIConfig {
    match (Json.parse(text)) {
        case Some(v) =>
            return AIConfig(
                providerID: Json.strAt(v, "providerID", "deepseek"),
                model: Json.strAt(v, "model", ""),
                baseURL: Json.strAt(v, "baseURL", ""),
                apiKey: "",
                loadProblem: ""
            )
        case None =>
            return AIConfig(loadProblem: "设置文件不是合法 JSON，provider/模型回落为默认值：${path}")
    }
}

/// 读密钥。**系统钥匙串优先**，读不到再退兜底文件。
///
/// 两个来源都空 = 真的没配。两个都在但**不一致**时取钥匙串的，
/// 并在设置页说明（用户可能换了机器，兜底文件是旧的）。
public func loadAIKey(): String {
    if (hasSecretTool()) {
        let r = execCapture(secretToolBin(), ["lookup", "service", AI_KEYRING_SERVICE, "account", "api-key"], 10000)
        if (!r.timedOut && r.exitCode == 0) {
            let v = r.stdout.trimAscii()
            if (!v.isEmpty()) {
                return v
            }
        }
    }
    let p = aiKeyFilePath()
    if (exists(p)) {
        // 有损解码 + 兜 try：这个函数会被设置页的掩码状态读到（后台线程），
        // 但也曾被构建闭包调用 —— 在那里抛异常就是整棵界面树崩掉。
        try {
            return fromUtf8Lossy(File.readFrom(p)).trimAscii()
        } catch (e: Exception) {
            return ""
        }
    }
    return ""
}

/// 上次保存时，密钥**真正进了系统钥匙串**吗？
/// `None` = 还没保存过（不是「成功」也不是「失败」）。
///
/// 为什么要单独记：`isConfigured` 只看 `apiKey` 非空，而那个非空值是
/// **用户刚输入的** —— 哪怕落盘失败了它也非空。于是设置页显示「已配置」、
/// 保存按钮报成功、下次启动 key 消失。这个标志就是让那次降级说出口的
/// （与 macOS 端 `keychainSaveFailed` 同一条理由）。
public var lastKeyStoreDegraded: ?Bool = None


/// 保存。**返回空串 = 成功，非空 = 给用户看的失败原因。**
///
/// 字段写 `settings.json`；密钥走钥匙串，钥匙串不可用时退到 0600 文件，
/// 退到文件这件事**必须**通过返回值和 `lastKeyStoreDegraded` 说出来。
public func saveAIConfig(c: AIConfig): String {
    let mk = ensureConfigDir()
    if (!mk.isEmpty()) {
        return mk
    }
    let pairs = ArrayList<(String, JsonValue)>()
    jobjAdd(pairs, "providerID", jstr(c.providerID))
    jobjAdd(pairs, "model", jstr(c.model))
    jobjAdd(pairs, "baseURL", jstr(c.baseURL))
    let doc = jsonWrite(jobj(pairs))
    // settings.json 与密钥文件走同一条原子替换（R1-04）：remove→writeTo
    // 的旧写法中途失败/被杀 = 配置整个消失，provider/模型悄悄退回默认值。
    let ws = writePrivateFile(aiConfigPath(), doc, "设置文件")
    if (!ws.isEmpty()) {
        return ws
    }

    var problem = ""
    if (c.apiKey.isEmpty()) {
        // 清空：两个来源都得清，否则「清空后 isConfigured 仍为 true」。
        if (hasSecretTool()) {
            let r = execCapture(secretToolBin(), ["clear", "service", AI_KEYRING_SERVICE, "account", "api-key"], 10000)
            if (!r.timedOut && r.exitCode != 0) {
                problem = "清除系统钥匙串里的密钥失败（退出码 ${r.exitCode}）"
            }
        }
        removeQuiet(aiKeyFilePath())
        lastKeyStoreDegraded = Some(!problem.isEmpty())
        return problem
    }

    if (hasSecretTool()) {
        let r = execCapture(
            secretToolBin(),
            ["store", "--label=deepDolphin AI", "service", AI_KEYRING_SERVICE, "account", "api-key"],
            10000
        )
        if (r.timedOut || r.exitCode != 0) {
            problem = "密钥没能存进系统钥匙串（退出码 ${r.exitCode}）"
        }
        if (problem.isEmpty()) {
            // 存进钥匙串了，兜底文件里的旧明文必须删掉 ——
            // 否则清空 key 之后那个文件还在，下次 `loadAIKey` 会把它读回来。
            removeQuiet(aiKeyFilePath())
            lastKeyStoreDegraded = Some(false)
            return ""
        }
    }

    // 兜底：0600 文件。**这不是静默降级** —— 返回值非空，
    // 设置页会把「没有系统钥匙串，密钥以 600 权限存放在 …」显示出来。
    let wp = writePrivateFile(aiKeyFilePath(), c.apiKey, "密钥文件")
    if (!wp.isEmpty()) {
        return wp
    }
    lastKeyStoreDegraded = Some(true)
    return if (hasSecretTool()) { problem } else { "" }
}

/// 密钥现在**实际**存在哪。给设置页显示用，不猜。
public func aiKeyStoreDescription(): String {
    if (hasSecretTool()) {
        if (exists(aiKeyFilePath())) {
            return "系统钥匙串 + 旧兜底文件（两者都在，以钥匙串为准）"
        }
        return "系统钥匙串（GNOME Keyring / KWallet）"
    }
    if (exists(aiKeyFilePath())) {
        return "无系统钥匙串，密钥以 600 权限存放在 ${aiKeyFilePath()}"
    }
    return "未配置"
}
