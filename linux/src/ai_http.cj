// deepDolphin Linux 客户端 —— AI 通道（发请求那一层）。
//
// 与 macOS 端 `AISDK.swift` 对齐：同样两套协议（OpenAI 兼容 / Anthropic）、
// 同样不流式、同样原生 tool_calls。
//
// 【为什么走 curl 子进程而不是 std.net】
// 仓颉标准库**没有**可用的 HTTP 客户端：`std.net` 只有裸 socket，
// 而 TLS（`std.crypto` 里没有可用的 TLS 实现）没有着落。
// 自己实现 TLS 客户端不是本项目该干的事。curl 是 Linux 桌面环境的事实标准
// （curl 8.x 起 `-H @file` / `-d @file` 都稳定可用）。
//
// 【为什么密钥绝不进命令行】
// 命令行参数在 `ps` 输出里对**同机所有用户**可见。
// `-H "Authorization: Bearer sk-..."` 等于把 API Key 广播出去。
// 所以头和体都写进 0700 配置目录里的 0600 临时文件，用 `@file` 引用，
// 发完（无论成败）立刻删；进程被杀没删干净的，下次启动清扫补删。
package deepdolphin_linux

import std.fs.*
import std.env.*
import std.collection.*

// ---------------------------------------------------------------------------
// 对话数据结构（与 macOS 端 ChatMessage.swift 一一对应）
// ---------------------------------------------------------------------------

public class ToolCallRequest {
    public let id: String
    public let name: String
    /// **已经是 JSON 文本**。不做二次解析 —— 原样回传给 provider，
    /// 中间转一次对象就多一次「转回来不完全一样」的机会。
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        this.id = id
        this.name = name
        this.argumentsJSON = argumentsJSON
    }
}

public class ToolCallResponse {
    public let id: String
    public let name: String
    public let content: String
    public let isError: Bool

    public init(id: String, name: String, content: String, isError!: Bool = false) {
        this.id = id
        this.name = name
        this.content = content
        this.isError = isError
    }
}

public class ToolDefinition {
    public let name: String
    public let description: String
    /// JSON Schema 文本。
    public let parametersJSON: String

    public init(name: String, description: String, parametersJSON: String) {
        this.name = name
        this.description = description
        this.parametersJSON = parametersJSON
    }
}

public class GenerateTextResult {
    public let text: String
    public let toolCalls: ArrayList<ToolCallRequest>

    public init(text: String, toolCalls!: ArrayList<ToolCallRequest> = ArrayList<ToolCallRequest>()) {
        this.text = text
        this.toolCalls = toolCalls
    }
}

public enum ChatRole {
    | System
    | User
    | Assistant
    | Tool
}

/// 角色判等。仓颉枚举**不实现 `==`**，所以要显式谓词。
public func chatRoleIs(a: ChatRole, b: ChatRole): Bool {
    return (match (a) {
        case ChatRole.System => (match (b) { case ChatRole.System => true; case _ => false })
        case ChatRole.User => (match (b) { case ChatRole.User => true; case _ => false })
        case ChatRole.Assistant => (match (b) { case ChatRole.Assistant => true; case _ => false })
        case ChatRole.Tool => (match (b) { case ChatRole.Tool => true; case _ => false })
    })
}

public class ChatMessage {
    public let role: ChatRole
    public let text: String
    public let toolCalls: Option<ArrayList<ToolCallRequest>>
    public let toolCallID: String
    public let isError: Bool

    public init(
        role: ChatRole,
        text: String,
        toolCalls!: Option<ArrayList<ToolCallRequest>> = None,
        toolCallID!: String = "",
        isError!: Bool = false
    ) {
        this.role = role
        this.text = text
        this.toolCalls = toolCalls
        this.toolCallID = toolCallID
        this.isError = isError
    }

    public static func system(t: String): ChatMessage {
        return ChatMessage(ChatRole.System, t)
    }

    public static func user(t: String): ChatMessage {
        return ChatMessage(ChatRole.User, t)
    }

    public static func assistant(t: String, calls!: ArrayList<ToolCallRequest> = ArrayList<ToolCallRequest>()): ChatMessage {
        if (calls.isEmpty()) {
            return ChatMessage(ChatRole.Assistant, t)
        }
        return ChatMessage(ChatRole.Assistant, t, toolCalls: Some(calls))
    }

    public static func tool(id: String, content: String, isError!: Bool = false): ChatMessage {
        return ChatMessage(ChatRole.Tool, content, toolCallID: id, isError: isError)
    }
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

public class AIHttpResult {
    public let httpCode: Int64
    public let body: String
    /// 给用户看的失败原因；成功时为空串。**已脱敏**。
    public let problem: String
    /// 试的是哪个地址。网络出错时这句话是唯一有用的线索。
    public let attemptedURL: String

    public init(httpCode: Int64, body: String, problem: String, attemptedURL: String) {
        this.httpCode = httpCode
        this.body = body
        this.problem = problem
        this.attemptedURL = attemptedURL
    }

    public func ok(): Bool {
        return this.problem.isEmpty()
    }
}

/// curl 的兜底位置：PATH 上找不到时最后试这一处。
private const CURL_FALLBACK: String = "/usr/bin/curl"

/// curl 的位置：先走 PATH，找不到再回退 /usr/bin。
/// ⚠ 第一版钉死 /usr/bin —— 工具装在 PATH 别处（/bin、用户自装 prefix）
/// 的机器上明明有 curl 也报「找不到」。
private func curlBin(): String {
    let p = firstToolOnPath(["curl"])
    return (if (p.isEmpty()) { CURL_FALLBACK } else { p })
}

/// 旧版临时文件的目录（/tmp）。现在的临时文件写在 0700 的配置目录里，
/// 这个函数只剩一个用途：**启动清扫**要连上一版残留的
/// `/tmp/deepdolphin-ai-*` 一起删。
private func aiTempDir(): String {
    let t = (getVariable("TMPDIR") ?? "").trimAscii()
    if (!t.isEmpty() && t.startsWith("/")) {
        return t
    }
    return "/tmp"
}

/// 进程内递增计数：同一毫秒里的两次请求（理论上不会，但闸门只管 UI 侧）
/// 也不至于拿到同一个临时文件名。
private var aiTempSeq: Int64 = 0

/// 请求临时文件路径。**写在 0700 的配置目录**，不写 /tmp（R4-03）：
///   · /tmp 全世界可进，头文件里又是 API Key —— 「写完再 chmod 600」
///     挡不住 umask 生成的那个瞬间；
///   · 旧版只拿毫秒时间戳当名字，可预测，重放/并发会互相踩。
/// 目录 700（见 ensureConfigDir）+ 毫秒 + 进程内计数，两条都关死。
private func tempPath(tag: String): String {
    aiTempSeq += 1
    return "${aiConfigDir()}/deepdolphin-ai-${tag}-${nowMillis()}-${aiTempSeq}"
}

/// 清扫上次进程残留下来的 AI 请求临时文件。
///
/// 进程被 SIGKILL / 断电 / 崩溃时，finally 清理不会跑 —— 头文件里是
/// API Key，残留就得在**下一次启动**补删。旧版临时文件写在 /tmp，
/// 也要一并扫掉。启动时在后台线程调一次。
/// 返回空串 = 成功（含「没有残留」）；非空 = 失败原因。
///
/// ⚠ glob 只认本应用**真的会创建**的三个名字（body / head / out），
/// 不认宽前缀 `deepdolphin-ai-*`：前缀是他人的命名空间也会撞上的形状
/// （本仓 ai-e2e.sh 的备份文件就叫 `deepdolphin-ai-test.XXXXXX`），
/// 按前缀删会把别人的在用文件一起删掉 —— 实测真的发生过。
public func sweepAITempLeftovers(): String {
    for (dir in [aiConfigDir(), aiTempDir()]) {
        if (!exists(dir)) {
            continue
        }
        // 目录走**位置参数**传给 sh，不拼进脚本串 —— 目录里有空格、
        // 引号也不会变成另一条命令。`rm -f` 对不存在的字面参数安静退出 0
        // （glob 没匹配上就是这个形状），所以「没有残留」与「删干净」同路。
        let r = execCapture(
            "/bin/sh",
            ["-c", "rm -f -- \"$1\"/deepdolphin-ai-body-* \"$1\"/deepdolphin-ai-head-* \"$1\"/deepdolphin-ai-out-*", "dd-sweep", dir],
            10000
        )
        if (r.timedOut || r.exitCode != 0) {
            let why = if (!r.stderr.trimAscii().isEmpty()) { r.stderr.trimAscii() } else {
                "退出码 ${r.exitCode}"
            }
            return "清扫 AI 临时文件失败（${why}）：${dir}"
        }
    }
    return ""
}

/// POST 一份 JSON。**唯一**的网络出口。
///
/// 失败分三类，分别说不同的话（macOS 端 `AIChannelError` 同一个理由）：
///   · curl 自己失败（没装 / 证书错 / 连不上 / 超时）
///   · HTTP 非 200（body 里常有 provider 给的原因）
///   · 200 但 body 解析不出来
/// 三类混成一句「AI 调用失败」，用户在「测试连接」那一步什么也判断不出来。
public func aiPostJSON(url: String, bodyText: String, headerLines: ArrayList<String>, timeoutMs: Int64): AIHttpResult {
    let curl = curlBin()
    if (!exists(curl)) {
        return AIHttpResult(-1, "", "找不到 curl（PATH 与 /usr/bin 都试过）—— AI 通道依赖它发请求（装 curl 即可）", url)
    }
    // 临时文件的家。目录就绪失败时**如实失败**，不退回 /tmp ——
    // 那不是降级，是把密钥头文件重新敞给全机用户。
    let mk = ensureConfigDir()
    if (!mk.isEmpty()) {
        return AIHttpResult(-1, "", "AI 请求的私有临时目录没能就绪：${mk}", url)
    }
    let bodyFile = tempPath("body")
    let headFile = tempPath("head")
    let outFile = tempPath("out")
    // 头文件里就是 API Key、体文件里是完整对话 —— 都按 0600 私有文件
    // 原子写入（writePrivateFile：临时文件→chmod 600→rename）。
    let sb = StringBuilder()
    for (h in headerLines) {
        sb.append(h)
        sb.append("\n")
    }
    let headProblem = writePrivateFile(headFile, sb.toString(), "密钥请求头")
    if (!headProblem.isEmpty()) {
        return AIHttpResult(-1, "", headProblem, url)
    }
    let bodyProblem = writePrivateFile(bodyFile, bodyText, "请求体")
    if (!bodyProblem.isEmpty()) {
        // 头文件已落盘，不能留着 —— 那里面有 API Key。
        removeQuiet(headFile)
        return AIHttpResult(-1, "", bodyProblem, url)
    }

    let secs = (if (timeoutMs < 1000) { Int64(1) } else { timeoutMs / 1000 })
    let r = execCapture(curl, [
        "-sS",
        "--max-time", secs.toString(),
        "-X", "POST",
        "-H", "@${headFile}",
        "-H", "Content-Type: application/json",
        "-d", "@${bodyFile}",
        "-o", outFile,
        "-w", "%{http_code}",
        url
    ], timeoutMs + 10000)

    // ⚠ 顺序承重：**先读 outFile，再清临时文件**。
    // 反过来写（先清后读）是本文件第一版的写法，症状是
    // 「请求发出去了、服务端也收到了、但客户端说『AI 响应不是 JSON』」
    // —— 因为响应体已经被自己删了。纯函数判据测不到它：
    // 它只在真发一次请求时发作（端到端实测才暴露）。
    //
    // ⚠ 整段包 try/finally：读取这一步**无论抛不抛**，三个临时文件都必须
    // 清掉 —— 头文件里有 API Key，残留一份在磁盘上比一次失败的请求严重
    // 得多（R4-02：旧版异常恰好从「读」与「清」之间穿过，头文件永久残留，
    // 后台线程随之死亡）。解码走 fromUtf8Lossy：GBK 错误页、网关吐出的
    // 压缩体/二进制垃圾一律换成 U+FFFD，不再把「服务端返回了乱码」
    // 变成「客户端抛异常」。万一 finally 被 SIGKILL 打断，
    // 启动清扫（sweepAITempLeftovers）兜底。
    var body = ""
    var readProblem = ""
    try {
        if (exists(outFile)) {
            body = fromUtf8Lossy(File.readFrom(outFile))
        }
    } catch (e: Exception) {
        readProblem = "读取 AI 响应失败（${e.message}）"
    } finally {
        for (p in [bodyFile, headFile, outFile]) {
            if (exists(p)) {
                removeQuiet(p)
            }
        }
    }

    if (r.timedOut) {
        return AIHttpResult(-1, "", "AI 请求超时（${secs} 秒）：${url}", url)
    }
    if (!readProblem.isEmpty()) {
        return AIHttpResult(-1, "", "${readProblem}：${url}", url)
    }
    // curl 用非 0 退出表达**传输层**失败（连不上、证书、参数错）；
    // HTTP 4xx/5xx 时它照样退出 0，状态码在 stdout 里。
    let codeText = r.stdout.trimAscii()
    if (r.exitCode != 0 && codeText.isEmpty()) {
        let why = if (!r.stderr.trimAscii().isEmpty()) { r.stderr.trimAscii() } else {
            "curl 退出码 ${r.exitCode}"
        }
        return AIHttpResult(-1, "", "连不上 AI 服务（${why}）：${url}", url)
    }
    // 状态码按**字节**读（不是 rune）：`-w %{http_code}` 只会吐 ASCII 数字。
    var code = Int64(0)
    for (b in codeText.toArray()) {
        if (b >= 0x30u8 && b <= 0x39u8) {
            code = code * 10 + Int64(b - 0x30u8)
        }
    }
    if (code != 200) {
        return AIHttpResult(code, body, "AI 调用失败（HTTP ${code}）：${redactAI(textPrefix(body, 300))}", url)
    }
    return AIHttpResult(code, body, "", url)
}

/// 日志/错误文本脱敏。照抄 macOS 端 `AISDK.redacted` 的口径：
/// 出现凭证模式就**整体**换成一句提示，而不是做局部替换 ——
/// 局部替换漏一个变体（`sk-ant-`、JWT、带 query 的 token）就把密钥漏出去。
public func redactAI(text: String): String {
    for (pat in ["Bearer ", "sk-", "x-api-key", "sk-ant-", "api_key"]) {
        if (text.contains(pat)) {
            return "（响应含敏感字段，已隐藏）"
        }
    }
    return text
}

public func textPrefix(s: String, n: Int64): String {
    var out = ""
    for (r in s.runes()) {
        if (out.size >= n) {
            return out + "…"
        }
        out += r.toString()
    }
    return out
}

// ---------------------------------------------------------------------------
// 协议
// ---------------------------------------------------------------------------

/// 端点尾部斜杠要剪掉：`https://x/` + `/chat/completions` = `//chat/completions`，
/// 相当一部分网关会把双斜杠当 404。
private func trimTrailingSlashes(s: String): String {
    var t = s.trimAscii()
    while (t.endsWith("/")) {
        t = t[0..t.size - 1]
    }
    return t
}

/// 一次性补全（带原生工具调用）。**返回失败原因而不是抛异常** ——
/// 调用点有六处，每一处都要把原因显示给用户。
public func generateText(
    cfg: AIConfig,
    system: String,
    messages: ArrayList<ChatMessage>,
    tools: ArrayList<ToolDefinition>,
    maxTokens!: Int64 = 4000,
    timeoutMs!: Int64 = 120000
): AIHttpResult2 {
    if (!cfg.isConfigured()) {
        let why = if (cfg.effectiveBaseURL().isEmpty()) {
            "AI 未配置：${cfg.providerID} 在目录里没有可用端点，请在「AI 设置」里填 Base URL（只接受 https，或 127.0.0.1 / localhost）"
        } else {
            "AI 未配置：还没填 API Key（设置 → AI 设置）"
        }
        return AIHttpResult2(GenerateTextResult(""), why)
    }
    let base = trimTrailingSlashes(cfg.effectiveBaseURL())
    if (base.isEmpty()) {
        return AIHttpResult2(GenerateTextResult(""), "Base URL 为空：请在 AI 设置里补全")
    }
    if (cfg.isAnthropic()) {
        return generateAnthropic(cfg, base, system, messages, tools, maxTokens, timeoutMs)
    }
    return generateOpenAICompatible(cfg, base, system, messages, tools, maxTokens, timeoutMs)
}

/// 协议层的返回：要么结果，要么原因。二选一。
public class AIHttpResult2 {
    public let result: GenerateTextResult
    public let problem: String

    public init(result: GenerateTextResult, problem: String) {
        this.result = result
        this.problem = problem
    }

    public func ok(): Bool {
        return this.problem.isEmpty()
    }
}

private func generateOpenAICompatible(
    cfg: AIConfig,
    base: String,
    system: String,
    messages: ArrayList<ChatMessage>,
    tools: ArrayList<ToolDefinition>,
    maxTokens: Int64,
    timeoutMs: Int64
): AIHttpResult2 {
    let payload = ArrayList<JsonValue>()
    payload.add(jobj(pairsOf1("role", "system", "content", system)))
    for (m in messages) {
        match (m.role) {
            case ChatRole.Assistant =>
                match (m.toolCalls) {
                    case Some(calls) =>
                        let arr = ArrayList<JsonValue>()
                        for (tc in calls) {
                            let fn = ArrayList<(String, JsonValue)>()
                            jobjAdd(fn, "name", jstr(tc.name))
                            jobjAdd(fn, "arguments", jstr(tc.argumentsJSON))
                            let one = ArrayList<(String, JsonValue)>()
                            jobjAdd(one, "id", jstr(tc.id))
                            jobjAdd(one, "type", jstr("function"))
                            jobjAdd(one, "function", jobj(fn))
                            arr.add(jobj(one))
                        }
                        let e = ArrayList<(String, JsonValue)>()
                        jobjAdd(e, "role", jstr("assistant"))
                        if (!m.text.isEmpty()) {
                            jobjAdd(e, "content", jstr(m.text))
                        }
                        jobjAdd(e, "tool_calls", jarr(arr))
                        payload.add(jobj(e))
                    case None =>
                        payload.add(jobj(pairsOf1("role", "assistant", "content", m.text)))
                }
            case ChatRole.Tool =>
                let e = ArrayList<(String, JsonValue)>()
                jobjAdd(e, "role", jstr("tool"))
                jobjAdd(e, "tool_call_id", jstr(m.toolCallID))
                jobjAdd(e, "content", jstr(m.text))
                payload.add(jobj(e))
            case ChatRole.System => payload.add(jobj(pairsOf1("role", "system", "content", m.text)))
            case ChatRole.User => payload.add(jobj(pairsOf1("role", "user", "content", m.text)))
        }
    }

    let body = ArrayList<(String, JsonValue)>()
    jobjAdd(body, "model", jstr(cfg.model))
    jobjAdd(body, "messages", jarr(payload))
    jobjAdd(body, "stream", JsonValue.JBool(false))
    jobjAdd(body, "max_tokens", jnum(Float64(maxTokens)))
    if (!tools.isEmpty()) {
        let arr = ArrayList<JsonValue>()
        for (t in tools) {
            let fn = ArrayList<(String, JsonValue)>()
            jobjAdd(fn, "name", jstr(t.name))
            jobjAdd(fn, "description", jstr(t.description))
            // parameters 是**内嵌对象**，不是字符串。
            match (Json.parse(t.parametersJSON)) {
                case Some(p) => jobjAdd(fn, "parameters", p)
                case None => jobjAdd(fn, "parameters", jobj(ArrayList<(String, JsonValue)>()))
            }
            let one = ArrayList<(String, JsonValue)>()
            jobjAdd(one, "type", jstr("function"))
            jobjAdd(one, "function", jobj(fn))
            arr.add(jobj(one))
        }
        jobjAdd(body, "tools", jarr(arr))
    }

    let heads = ArrayList<String>()
    if (!cfg.apiKey.isEmpty()) {
        heads.add("Authorization: Bearer ${cfg.apiKey}")
    }
    let res = aiPostJSON("${base}/chat/completions", jsonWrite(jobj(body)), heads, timeoutMs)
    if (!res.ok()) {
        return AIHttpResult2(GenerateTextResult(""), res.problem)
    }
    return parseOpenAIResponse(res.body)
}

/// OpenAI 兼容响应解析。**纯函数**，判据直接喂真实形状的 JSON。
public func parseOpenAIResponse(body: String): AIHttpResult2 {
    match (Json.parse(body)) {
        case None => return AIHttpResult2(GenerateTextResult(""), "AI 响应不是 JSON：${redactAI(textPrefix(body, 200))}")
        case Some(obj) =>
            let choices = Json.arrAt(obj, "choices")
            if (choices.isEmpty()) {
                return AIHttpResult2(GenerateTextResult(""), "AI 响应里没有 choices：${redactAI(textPrefix(body, 200))}")
            }
            let msg = Json.getOr(choices[0], "message")
            let text = Json.strAt(msg, "content", "")
            let calls = ArrayList<ToolCallRequest>()
            for (tc in Json.arrAt(msg, "tool_calls")) {
                let fn = Json.getOr(tc, "function")
                calls.add(ToolCallRequest(
                    Json.strAt(tc, "id", "call_${calls.size}"),
                    Json.strAt(fn, "name", ""),
                    Json.strAt(fn, "arguments", "{}")
                ))
            }
            return AIHttpResult2(GenerateTextResult(text, toolCalls: calls), "")
    }
}

private func generateAnthropic(
    cfg: AIConfig,
    base: String,
    system: String,
    messages: ArrayList<ChatMessage>,
    tools: ArrayList<ToolDefinition>,
    maxTokens: Int64,
    timeoutMs: Int64
): AIHttpResult2 {
    let payload = ArrayList<JsonValue>()
    for (m in messages) {
        match (m.role) {
            case ChatRole.Assistant =>
                match (m.toolCalls) {
                    case Some(calls) =>
                        let blocks = ArrayList<JsonValue>()
                        if (!m.text.isEmpty()) {
                            blocks.add(jobj(pairsOf1("type", "text", "text", m.text)))
                        }
                        for (tc in calls) {
                            let inner = match (Json.parse(tc.argumentsJSON)) {
                                case Some(v) => v
                                case None => jobj(ArrayList<(String, JsonValue)>())
                            }
                            let b = ArrayList<(String, JsonValue)>()
                            jobjAdd(b, "type", jstr("tool_use"))
                            jobjAdd(b, "id", jstr(tc.id))
                            jobjAdd(b, "name", jstr(tc.name))
                            jobjAdd(b, "input", inner)
                            blocks.add(jobj(b))
                        }
                        let e = ArrayList<(String, JsonValue)>()
                        jobjAdd(e, "role", jstr("assistant"))
                        jobjAdd(e, "content", jarr(blocks))
                        payload.add(jobj(e))
                    case None =>
                        let blocks = ArrayList<JsonValue>()
                        blocks.add(jobj(pairsOf1("type", "text", "text", m.text)))
                        let e = ArrayList<(String, JsonValue)>()
                        jobjAdd(e, "role", jstr("assistant"))
                        jobjAdd(e, "content", jarr(blocks))
                        payload.add(jobj(e))
                }
            case ChatRole.Tool =>
                // Anthropic 的工具结果是**一条 user 消息里的 tool_result 块**，
                // 不是独立的 tool role —— 写成 OpenAI 那套会被 400。
                let b = ArrayList<(String, JsonValue)>()
                jobjAdd(b, "type", jstr("tool_result"))
                jobjAdd(b, "tool_use_id", jstr(m.toolCallID))
                jobjAdd(b, "content", jstr(m.text))
                let e = ArrayList<(String, JsonValue)>()
                jobjAdd(e, "role", jstr("user"))
                jobjAdd(e, "content", jarr(ArrayList<JsonValue>([jobj(b)])))
                payload.add(jobj(e))
            case ChatRole.System =>
                let e = ArrayList<(String, JsonValue)>()
                jobjAdd(e, "role", jstr("user"))
                jobjAdd(e, "content", jstr(m.text))
                payload.add(jobj(e))
            case ChatRole.User => payload.add(jobj(pairsOf1("role", "user", "content", m.text)))
        }
    }

    let body = ArrayList<(String, JsonValue)>()
    jobjAdd(body, "model", jstr(cfg.model))
    jobjAdd(body, "max_tokens", jnum(Float64(maxTokens)))
    jobjAdd(body, "system", jstr(system))
    jobjAdd(body, "messages", jarr(payload))
    if (!tools.isEmpty()) {
        let arr = ArrayList<JsonValue>()
        for (t in tools) {
            let inner = match (Json.parse(t.parametersJSON)) {
                case Some(v) => v
                case None => jobj(ArrayList<(String, JsonValue)>())
            }
            let one = ArrayList<(String, JsonValue)>()
            jobjAdd(one, "name", jstr(t.name))
            jobjAdd(one, "description", jstr(t.description))
            jobjAdd(one, "input_schema", inner)
            arr.add(jobj(one))
        }
        jobjAdd(body, "tools", jarr(arr))
    }

    let heads = ArrayList<String>()
    if (!cfg.apiKey.isEmpty()) {
        heads.add("x-api-key: ${cfg.apiKey}")
    }
    heads.add("anthropic-version: 2023-06-01")
    let res = aiPostJSON("${base}/v1/messages", jsonWrite(jobj(body)), heads, timeoutMs)
    if (!res.ok()) {
        return AIHttpResult2(GenerateTextResult(""), res.problem)
    }
    return parseAnthropicResponse(res.body)
}

/// Anthropic 响应解析。纯函数。
public func parseAnthropicResponse(body: String): AIHttpResult2 {
    match (Json.parse(body)) {
        case None => return AIHttpResult2(GenerateTextResult(""), "AI 响应不是 JSON：${redactAI(textPrefix(body, 200))}")
        case Some(obj) =>
            let sb = StringBuilder()
            let calls = ArrayList<ToolCallRequest>()
            for (block in Json.arrAt(obj, "content")) {
                let t = Json.strAt(block, "type", "")
                if (t == "text") {
                    sb.append(Json.strAt(block, "text", ""))
                } else if (t == "tool_use") {
                    calls.add(ToolCallRequest(
                        Json.strAt(block, "id", "toolu_${calls.size}"),
                        Json.strAt(block, "name", ""),
                        jsonWrite(Json.getOr(block, "input"))
                    ))
                }
            }
            return AIHttpResult2(GenerateTextResult(sb.toString(), toolCalls: calls), "")
    }
}

/// `{"role": r, "content": c}` 的简写。
private func pairsOf1(k1: String, v1: String, k2: String, v2: String): ArrayList<(String, JsonValue)> {
    let p = ArrayList<(String, JsonValue)>()
    jobjAdd(p, k1, jstr(v1))
    jobjAdd(p, k2, jstr(v2))
    return p
}
