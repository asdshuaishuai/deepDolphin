// deepDolphin Linux 客户端 —— agent 主循环（C6）。
//
// 与 macOS 端 `AgentCore.swift` 对齐：同样的「读上下文 + 读工具清单 +
// 多轮 tool_calls」，同样的轮次上限与收尾判定。
//
// 【边界】引擎是 AI 无关内核。本文件是**唯一的** agent 编排层：
// 它只调引擎 CLI，不碰网络（网络在 ai_http.cj），不自己解析仓库。
package deepdolphin_linux

import std.collection.*

// ---------------------------------------------------------------------------
// 作用域
// ---------------------------------------------------------------------------

public enum AgentTarget {
    | Group
    | Project(String)

    public func label(): String {
        match (this) {
            case Group => return "项目群"
            case Project(n) => return n
        }
    }

    public func projectName(): String {
        match (this) {
            case Group => return ""
            case Project(n) => return n
        }
    }
}

// ---------------------------------------------------------------------------
// 引擎工具清单 → provider 的 JSON Schema
// ---------------------------------------------------------------------------

/// 引擎 `tools --json` 的 `params` 是**逗号分隔的声明串**，不是 JSON Schema。
///
/// 实测（`moongit tools --json`）真实取值：
///   `""`                        → 无参
///   `"name"`                    → 必填字符串
///   `"name,message"`            → 两个必填字符串
///   `"name,op(pull|push)"`      → 必填字符串 + 必填枚举
///
/// 那一段 `(pull|push)` 是枚举注解。不解析它的话，`git_pull_push` 会被
/// 声明成一个叫 `op(pull|push)` 的参数名 —— 模型多半填不出合法值，
/// 而症状是「工具调用一直失败」，看起来像模型能力问题。
/// 真值取自引擎真实输出，不是猜的形状。
public func engineParamsToSchema(params: String): String {
    let props = ArrayList<(String, JsonValue)>()
    let required = ArrayList<JsonValue>()
    for (raw in params.split(",")) {
        let item = raw.trimAscii()
        if (item.isEmpty()) {
            continue
        }
        var name = item
        var enumVals = ArrayList<JsonValue>()
        // 用 split 而不是 indexOf + 切片：`indexOf` 返回 Option，
        // 后面那串下标算术会逼出一堆 Option 解包，而这里只需要两种形状
        // （`name` / `name(a|b)`）。
        let parts = item.split("(")
        if (parts.size == 2 && item.endsWith(")")) {
            name = parts[0].trimAscii()
            // ⚠ 必须把结尾那个 `)` 摘掉。`split("(")` 留下的是 `pull|push)`，
            // 直接 split("|") 会得到枚举值 ["pull", "push)"] ——
            // 于是模型按声明填 `push` 会被 provider 拒，而声明本身看着完全正常。
            // ")" 是单字节 ASCII，按字节切片不会切坏任何 UTF-8 序列。
            let inner = parts[1]
            if (inner.endsWith(")")) {
                for (v in inner[0..inner.size - 1].split("|")) {
                    let vv = v.trimAscii()
                    if (!vv.isEmpty()) {
                        enumVals.add(jstr(vv))
                    }
                }
            }
        }
        if (name.isEmpty()) {
            continue
        }
        let propObj = ArrayList<(String, JsonValue)>()
        jobjAdd(propObj, "type", jstr("string"))
        if (!enumVals.isEmpty()) {
            jobjAdd(propObj, "enum", jarr(enumVals))
        }
        jobjAdd(props, name, jobj(propObj))
        // 引擎声明的参数**一律必填**：它没有可选参数的表示，
        // 而漏标 required 的后果是模型少传参数、引擎那边报「未找到项目」——
        // 一个从模型侧看完全无法自愈的错。
        required.add(jstr(name))
    }
    let out = ArrayList<(String, JsonValue)>()
    jobjAdd(out, "type", jstr("object"))
    jobjAdd(out, "properties", jobj(props))
    jobjAdd(out, "required", jarr(required))
    return jsonWrite(jobj(out))
}

/// 引擎清单 → `ToolDefinition`。**纯函数**，判据直接喂真实载荷。
public func engineToolDefinitions(p: Payload): ArrayList<ToolDefinition> {
    let out = ArrayList<ToolDefinition>()
    for (t in Json.arrAt(p.value(), "tools")) {
        let name = Json.strAt(t, "name", "")
        if (name.isEmpty()) {
            continue
        }
        out.add(ToolDefinition(name, Json.strAt(t, "description", ""), engineParamsToSchema(Json.strAt(t, "params", ""))))
    }
    return out
}

/// 引擎声明的工具名。判据拿它和客户端的映射表对拍。
public func engineToolNames(p: Payload): Array<String> {
    let out = ArrayList<String>()
    for (t in Json.arrAt(p.value(), "tools")) {
        let n = Json.strAt(t, "name", "")
        if (!n.isEmpty()) {
            out.add(n)
        }
    }
    return out.toArray()
}

// ---------------------------------------------------------------------------
// 工具执行
// ---------------------------------------------------------------------------

/// 客户端认识哪些工具名。**这张表必须与引擎 `tools --json` 完全一致** ——
/// 少一个，模型调用它时只会得到一句「未知工具」，用户看到的是
/// 「AI 助手不好用」，而真因是客户端少映射了一个。
public func mappedToolNames(): Array<String> {
    return [
        "get_group_context", "get_project_context", "get_project_docs", "get_journal",
        "get_milestones", "run_shallow_update", "run_deep_update",
        "git_commit", "git_pull_push", "milestone_done"
    ]
}

/// 工具需要的必填参数。判据拿它和引擎的 `params` 对拍。
public func toolRequiredParams(name: String): Array<String> {
    return (match (name) {
        case "get_project_context" => ["name"]
        case "get_project_docs" => ["name"]
        case "get_journal" => ["name"]
        case "run_shallow_update" => ["name"]
        case "run_deep_update" => ["name"]
        case "git_commit" => ["name", "message"]
        case "git_pull_push" => ["name", "op"]
        case "milestone_done" => ["project", "name"]
        case _ => []
    })
}

/// 执行一次引擎工具。
///
/// ⚠ **参数校验在发命令之前**。少传参数时如果照发，引擎要么报一句
/// 语焉不详的错，要么更糟 —— 命中了**别的**项目。
/// 工具返回的文本会**原样进对话**，所以失败也必须是一句人能读的说明。
public func executeEngineTool(bin: String, name: String, argsJSON: String): ToolCallResponse {
    let args = match (Json.parse(argsJSON)) {
        case None => JsonValue.JNull
        case Some(v) => v
    }
    let missing = ArrayList<String>()
    for (req in toolRequiredParams(name)) {
        if (Json.strAt(args, req, "").trimAscii().isEmpty()) {
            missing.add(req)
        }
    }
    if (!missing.isEmpty()) {
        return ToolCallResponse("", name, missingMessage(name, missing.toArray()), isError: true)
    }

    let callId = ""
    let p: Payload = (match (name) {
        case "get_group_context" => opContext(bin, "", 4000)
        case "get_project_context" => opContext(bin, Json.strAt(args, "name", ""), 4000)
        case "get_project_docs" => opDocs(bin, Json.strAt(args, "name", ""))
        case "get_journal" => opJournal(bin, Json.strAt(args, "name", ""))
        case "get_milestones" => opMilestoneList(bin)
        case "run_shallow_update" => opUpdate(bin, Json.strAt(args, "name", ""), false)
        case "run_deep_update" => opUpdate(bin, Json.strAt(args, "name", ""), true)
        case "git_commit" => opGit(bin, Json.strAt(args, "name", ""), "commit", Json.strAt(args, "message", ""))
        case "git_pull_push" =>
            let op = Json.strAt(args, "op", "")
            if (!gitWhitelist().contains(op)) {
                return ToolCallResponse(callId, name, "git 操作「${op}」不在引擎白名单里（可用：${joinList(gitWhitelist())}）", isError: true)
            }
            opGit(bin, Json.strAt(args, "name", ""), op, "")
        case "milestone_done" => opMilestoneAction(bin, Json.strAt(args, "project", ""), Json.strAt(args, "name", ""), "done")
        case _ => return ToolCallResponse(callId, name, "客户端不认识这个工具「${name}」", isError: true)
    })

    if (!p.ok()) {
        // 失败**说清楚是哪一步**。原样把引擎的 problem 递上去 ——
        // 「未找到项目：xxx（可用 moongit list 查看）」对模型来说是可用的信息。
        return ToolCallResponse(callId, name, "工具执行失败：${p.problem}", isError: true)
    }
    return ToolCallResponse(callId, name, toolTextFor(name, p), isError: false)
}

/// 参数不全时要说的那句话。**列出缺了哪些**，不是「参数错误」。
public func missingMessage(name: String, missing: Array<String>): String {
    let sb = StringBuilder()
    sb.append("工具 ${name} 缺少必填参数：")
    for (i in 0..missing.size) {
        if (i > 0) { sb.append("、") }
        sb.append(missing[i])
    }
    sb.append("。请补齐后重新调用。")
    return sb.toString()
}

/// 工具结果给模型的正文。
///
/// ⚠ **不能把整个 JSON 载荷原样塞进对话**：引擎的 status 载荷单个就有几十 KB，
/// 塞进去会把上下文预算吃光，而且里面大半是模型用不上的原始字段。
/// 上下文类工具用引擎自己生成的 markdown（`context`），
/// 其余用载荷的 `summary` 字段（有就优先）。
private func toolTextFor(name: String, p: Payload): String {
    if (name == "get_group_context" || name == "get_project_context") {
        let ctx = Json.strAt(p.value(), "context", "")
        if (!ctx.isEmpty()) {
            return ctx
        }
    }
    let v = p.value()
    let summary = Json.strAt(v, "summary", "")
    if (!summary.isEmpty()) {
        return summary
    }
    if (name == "get_project_docs") {
        // 真实载荷（实测 `moongit docs <项目> --json`）：
        //   {"project": str, "docs": [{"file":…, "content":…, "project":…}], "unreadable": […]}
        // 键是 `docs`、元素字段是 `file` —— 写成 `files`/`path` 会静默拿到空数组，
        // 然后把一段空文本当成功结果喂回模型。
        let sb = StringBuilder()
        for (f in Json.arrAt(v, "docs")) {
            sb.append("## ")
            sb.append(Json.strAt(f, "file", "(未命名)"))
            sb.append("\n\n")
            sb.append(Json.strAt(f, "content", ""))
            sb.append("\n\n")
        }
        // `unreadable` 非空必须说出来：**「读不出来」和「没有」是两件事**。
        // 静默吞掉它，模型就会对着一份不完整的文档下结论。
        let unread = Json.arrAt(v, "unreadable")
        if (!unread.isEmpty()) {
            sb.append("\n> ⚠ 有 ")
            sb.append(unread.size.toString())
            sb.append(" 份文件读不出来：")
            for (i in 0..unread.size) {
                if (i > 0) { sb.append("、") }
                sb.append(Json.strAt(unread[i], "file", Json.strAt(unread[i], "path", "(未命名)")))
            }
            sb.append("。以上内容不完整。\n")
        }
        if (sb.size > 0) {
            return sb.toString()
        }
    }
    let s = jsonWrite(v)
    if (s.size > 6000) {
        return textPrefix(s, 6000) + "\n…（已截断）"
    }
    return s
}

// ---------------------------------------------------------------------------
// 提示词
// ---------------------------------------------------------------------------

/// system 提示词。**纯函数**，判据直接断言里面必须有的那句纪律。
///
/// 末尾拼引擎事实，是为了让模型知道「工具能做什么、不能做什么」这件事
/// 有一个权威来源 —— 而不是靠它猜。
public func agentSystemPrompt(context: String, toolNames: Array<String>, target: AgentTarget): String {
    let sb = StringBuilder()
    sb.append("你是 deepDolphin 的项目进度助手，服务于 Git 项目群。\n\n")
    sb.append("硬性纪律：\n")
    sb.append("1. 一切项目事实来自工具返回的原文。**没有工具结果就不要断言** ——\n")
    sb.append("   不知道就说不知道，不要用「通常」「一般来说」补齐。\n")
    sb.append("2. 「读不出来」与「没有」是两件事，不要混为一谈。\n")
    sb.append("3. 破坏性动作（提交、拉取、推送、标记里程碑达成、深更新）执行前，\n")
    sb.append("   先用一句话说明将要改什么，得到用户确认再调工具。\n")
    sb.append("4. 回答用中文，简洁；能给出具体分支名/提交数就不要用「一些」「若干」。\n\n")
    sb.append("可用工具：")
    for (i in 0..toolNames.size) {
        if (i > 0) { sb.append("、") }
        sb.append(toolNames[i])
    }
    sb.append("\n\n当前作用域：")
    sb.append(target.label())
    sb.append("\n\n以下是引擎给出的确定性事实（唯一可信来源）：\n\n")
    sb.append(context)
    return sb.toString()
}

/// 裁历史 + 塞本轮提问。**纯函数**。
///
/// 历史按条数裁，不按 token 估 —— 本端没有 tokenizer，
/// 而「按字符粗估」会在中文上系统性低估（一个汉字的 token 数接近 1，
/// 但按字符估会给英文超估、给中文低估）。宁可多带几条，
/// 真到了 provider 侧超限，它的报错比这里猜得准。
public func seedConversation(history: ArrayList<ChatMessage>, question: String, keep!: Int64 = 12): ArrayList<ChatMessage> {
    let out = ArrayList<ChatMessage>()
    let n = Int64(history.size)
    let start = (if (n > keep) { n - keep } else { Int64(0) })
    for (i in start..n) {
        out.add(history[i])
    }
    out.add(ChatMessage.user(question))
    return out
}

// ---------------------------------------------------------------------------
// 收尾判定
// ---------------------------------------------------------------------------

public enum AgentOutcomeKind {
    /// 正常收尾：模型不再要求调工具。
    | Finished
    /// 到了轮次上限 —— **但模型这一轮已经写出了正文，必须交付它**。
    | AtRoundLimit
    /// 失败。`problem` 里有原因。
    | Failed
}

public class AgentOutcome {
    public let kind: AgentOutcomeKind
    /// 最终答案正文。轮次上限时是**最后一轮已经写出来的**那段。
    public let text: String
    /// 本轮实际执行过的工具（人话，形如 `浅更新 · deepGit`）。
    public let executed: ArrayList<String>
    public let problem: String

    public init(kind: AgentOutcomeKind, text: String, executed: ArrayList<String>, problem: String) {
        this.kind = kind
        this.text = text
        this.executed = executed
        this.problem = problem
    }
}

/// 收尾状态的中文标签。
///
/// ⚠ 仓颉枚举**不自带 `ToString`**（插值它要求实现 `core` 的 `ToString`），
/// 而这三个值都要出现在界面上（「已收尾 / 已达上限 / 失败」），
/// 所以这里给唯一一处翻译。
public func agentOutcomeLabel(k: AgentOutcomeKind): String {
    return (match (k) {
        case AgentOutcomeKind.Finished => "已收尾"
        case AgentOutcomeKind.AtRoundLimit => "已达轮次上限"
        case AgentOutcomeKind.Failed => "失败"
    })
}

/// 工具名的中文短标签，给「这一轮做了什么」用。
public func toolShortLabel(name: String): String {
    return (match (name) {
        case "get_group_context" => "读项目群上下文"
        case "get_project_context" => "读项目上下文"
        case "get_project_docs" => "读项目文档"
        case "get_journal" => "读进度日志"
        case "get_milestones" => "读里程碑"
        case "run_shallow_update" => "浅更新"
        case "run_deep_update" => "深更新"
        case "git_commit" => "提交"
        case "git_pull_push" => "git 同步"
        case "milestone_done" => "标记里程碑达成"
        case _ => name
    })
}

// ---------------------------------------------------------------------------
// 主循环
// ---------------------------------------------------------------------------

public class AgentRunResult {
    public let outcome: AgentOutcome
    /// 完整对话（含工具往返），界面直接渲染这份。
    public let transcript: ArrayList<ChatMessage>

    public init(outcome: AgentOutcome, transcript: ArrayList<ChatMessage>) {
        this.outcome = outcome
        this.transcript = transcript
    }
}

/// 跑一次 agent。**不流式**（与 macOS 端一致：`"stream": false`）。
///
/// 轮次上限的收尾：macOS 那边原来到上限直接抛错，把模型**已经写出来的**
/// 答案丢掉 —— 用户看到一句「已达上限」，而答案就在手边。
/// 这里到上限时把最后一轮的正文连同「已达上限」一起交付。
public func runAgent(
    cfg: AIConfig,
    bin: String,
    target: AgentTarget,
    question: String,
    history: ArrayList<ChatMessage>,
    maxRounds!: Int64 = 4,
    timeoutMs!: Int64 = 180000
): AgentRunResult {
    let executed = ArrayList<String>()
    if (!cfg.isConfigured()) {
        let why = if (cfg.model.isEmpty()) {
            "AI 未配置：还没选模型（AI 设置 → 模型）"
        } else {
            "AI 未配置：请在 AI 设置里选 provider 并填写 API Key"
        }
        return AgentRunResult(AgentOutcome(AgentOutcomeKind.Failed, "", executed, why), ArrayList<ChatMessage>())
    }

    let ctxPayload = opContext(bin, target.projectName(), 4000)
    if (!ctxPayload.ok()) {
        return AgentRunResult(
            AgentOutcome(AgentOutcomeKind.Failed, "", executed, "读引擎上下文失败：${ctxPayload.problem}"),
            ArrayList<ChatMessage>()
        )
    }
    let toolsPayload = opTools(bin)
    if (!toolsPayload.ok()) {
        return AgentRunResult(
            AgentOutcome(AgentOutcomeKind.Failed, "", executed, "读引擎工具清单失败：${toolsPayload.problem}"),
            ArrayList<ChatMessage>()
        )
    }

    let defs = engineToolDefinitions(toolsPayload)
    let names = ArrayList<String>()
    for (d in defs) {
        names.add(d.name)
    }
    let system = agentSystemPrompt(Json.strAt(ctxPayload.value(), "context", ""), names.toArray(), target)
    let transcript = seedConversation(history, question)

    var lastText = ""
    var round: Int64 = 1
    while (round <= maxRounds) {
        let resp = generateText(cfg, system, transcript, defs, maxTokens: 4000, timeoutMs: timeoutMs)
        if (!resp.ok()) {
            return AgentRunResult(
                AgentOutcome(AgentOutcomeKind.Failed, lastText, executed, "第 ${round} 轮调用失败：${resp.problem}"),
                transcript
            )
        }
        let text = resp.result.text
        if (!text.isEmpty()) {
            lastText = text
        }
        if (resp.result.toolCalls.isEmpty()) {
            transcript.add(ChatMessage.assistant(text))
            return AgentRunResult(
                AgentOutcome(AgentOutcomeKind.Finished, text, executed, ""),
                transcript
            )
        }
        transcript.add(ChatMessage.assistant(text, calls: resp.result.toolCalls))
        for (tc in resp.result.toolCalls) {
            let r = executeEngineTool(bin, tc.name, tc.argumentsJSON)
            let withId = ToolCallResponse(tc.id, tc.name, r.content, isError: r.isError)
            transcript.add(ChatMessage.tool(withId.id, withId.content, isError: withId.isError))
            executed.add(toolExecutedLine(tc.name, r.content, r.isError))
        }
        round += 1
    }
    // 轮次用尽：把**已经写出来的**正文交出去，不说「已达上限」就完事。
    transcript.add(ChatMessage.assistant(lastText))
    return AgentRunResult(
        AgentOutcome(
            AgentOutcomeKind.AtRoundLimit,
            lastText,
            executed,
            "已达 ${maxRounds} 轮工具调用上限，下面是模型到目前为止写出的内容"
        ),
        transcript
    )
}

private func toolExecutedLine(name: String, content: String, isError: Bool): String {
    let sb = StringBuilder()
    sb.append(toolShortLabel(name))
    if (isError) {
        sb.append("（失败：")
        sb.append(textPrefix(content, 80))
        sb.append("）")
    }
    return sb.toString()
}
