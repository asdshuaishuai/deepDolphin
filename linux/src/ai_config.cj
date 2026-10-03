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
/// 字段与 macOS 端一一对应，不增不减：多一个字段就多一处两端可能长歪的地方。
public class AIConfig {
    /// models.dev 的 provider id（如 deepseek / openai / anthropic / openrouter …）
    public let providerID: String
    public let model: String
    /// 用户手填的端点覆盖。空 = 用目录里的端点。
    public let baseURL: String
    public let apiKey: String

    public init(
        providerID!: String = "deepseek",
        model!: String = "",
        baseURL!: String = "",
        apiKey!: String = ""
    ) {
        this.providerID = providerID
        this.model = model
        this.baseURL = baseURL
        this.apiKey = apiKey
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
private const SECRET_TOOL: String = "/usr/bin/secret-tool"

public func hasSecretTool(): Bool {
    return exists(SECRET_TOOL)
}

// ---------------------------------------------------------------------------
// 落盘
// ---------------------------------------------------------------------------

/// 建目录。仓颉 1.0.5 的 `std.fs` **没有** `mkdir`（实测：chdir/mkdir/
/// stat 全是 undeclared identifier，只有 `exists`/`remove`/`copy`/`rename`），
/// 所以走子进程。目录建不出来必须报错，不许静默 —— 后面每一次写都会失败。
private func ensureConfigDir(): String {
    let dir = aiConfigDir()
    if (exists(dir)) {
        return ""
    }
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
    return ""
}

private func writePrivateFile(path: String, content: String): String {
    if (exists(path)) {
        // 先删再写：`File.writeTo` 不保证会截断已有文件，
        // 「旧内容比新内容长」时会留下尾巴（一个典型的半截凭据）。
        remove(path)
    }
    File.writeTo(path, content.toArray())
    // ⚠ chmod 必须在写**之后**：先 chmod 再写的话，
    // 新文件按 umask 生成（常见 0644），密钥在 chmod 之前的那一瞬是全局可读的。
    let r = execCapture("/bin/chmod", ["600", path], 5000)
    if (r.exitCode != 0) {
        return "密钥文件权限没能收紧到 600（${path}）—— 别的用户可能读到 API Key"
    }
    return ""
}

/// 读配置 + 读密钥。**任何一步读不出来都给默认值，不抛** —— 客户端不该因为
/// 配置文件损坏就起不来。
public func loadAIConfig(): AIConfig {
    var pid = "deepseek"
    var mdl = ""
    var base = ""
    if (exists(aiConfigPath())) {
        if (let Some(v) <- Json.parse(String.fromUtf8(File.readFrom(aiConfigPath())))) {
            pid = Json.strAt(v, "providerID", "deepseek")
            mdl = Json.strAt(v, "model", "")
            base = Json.strAt(v, "baseURL", "")
        }
    }
    return AIConfig(providerID: pid, model: mdl, baseURL: base, apiKey: loadAIKey())
}

/// 读密钥。**系统钥匙串优先**，读不到再退兜底文件。
///
/// 两个来源都空 = 真的没配。两个都在但**不一致**时取钥匙串的，
/// 并在设置页说明（用户可能换了机器，兜底文件是旧的）。
public func loadAIKey(): String {
    if (hasSecretTool()) {
        let r = execCapture(SECRET_TOOL, ["lookup", "service", AI_KEYRING_SERVICE, "account", "api-key"], 10000)
        if (!r.timedOut && r.exitCode == 0) {
            let v = r.stdout.trimAscii()
            if (!v.isEmpty()) {
                return v
            }
        }
    }
    let p = aiKeyFilePath()
    if (exists(p)) {
        return String.fromUtf8(File.readFrom(p)).trimAscii()
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
    if (exists(aiConfigPath())) {
        remove(aiConfigPath())
    }
    File.writeTo(aiConfigPath(), doc.toArray())

    var problem = ""
    if (c.apiKey.isEmpty()) {
        // 清空：两个来源都得清，否则「清空后 isConfigured 仍为 true」。
        if (hasSecretTool()) {
            let r = execCapture(SECRET_TOOL, ["clear", "service", AI_KEYRING_SERVICE, "account", "api-key"], 10000)
            if (!r.timedOut && r.exitCode != 0) {
                problem = "清除系统钥匙串里的密钥失败（退出码 ${r.exitCode}）"
            }
        }
        if (exists(aiKeyFilePath())) {
            remove(aiKeyFilePath())
        }
        lastKeyStoreDegraded = Some(!problem.isEmpty())
        return problem
    }

    if (hasSecretTool()) {
        let r = execCapture(
            SECRET_TOOL,
            ["store", "--label=deepDolphin AI", "service", AI_KEYRING_SERVICE, "account", "api-key"],
            10000
        )
        if (r.timedOut || r.exitCode != 0) {
            problem = "密钥没能存进系统钥匙串（退出码 ${r.exitCode}）"
        }
        if (problem.isEmpty()) {
            // 存进钥匙串了，兜底文件里的旧明文必须删掉 ——
            // 否则清空 key 之后那个文件还在，下次 `loadAIKey` 会把它读回来。
            if (exists(aiKeyFilePath())) {
                remove(aiKeyFilePath())
            }
            lastKeyStoreDegraded = Some(false)
            return ""
        }
    }

    // 兜底：0600 文件。**这不是静默降级** —— 返回值非空，
    // 设置页会把「没有系统钥匙串，密钥以 600 权限存放在 …」显示出来。
    let wp = writePrivateFile(aiKeyFilePath(), c.apiKey)
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
