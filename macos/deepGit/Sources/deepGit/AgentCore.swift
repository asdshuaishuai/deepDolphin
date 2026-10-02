// AgentCore.swift — 无 UI 的 agent 执行核心（AI 层的可复用部分）。
//
// 使用方：AgentView（对话）、浅/深更新的 AI 摘要、一键项目说明、定时更新的 AI 简报。
// 引擎是 AI 无关内核：这里拉上下文包（deepgit context --json）与工具清单（deepgit tools --json），
// 组 prompt 后经 ai-sdk 通道（LanguageModel）执行原生工具循环。
import Foundation

enum AgentTarget: Equatable, Hashable {
    case group
    case project(String)

    var label: String {
        switch self {
        case .group: return "整个项目群"
        case .project(let n): return n
        }
    }

    var scopePath: String { "api/context" }
    var scopeQuery: [String: String] {
        switch self {
        case .group: return ["scope": "group", "budget": "9000"]
        case .project(let n): return ["scope": "project", "name": n, "budget": "9000"]
        }
    }
}

enum AgentCore {
    /// GET 原始数据
    static func rawGet(_ path: String, query: [String: String]) async throws -> Data {
        // 本机进程间通信：通过 CLI 子进程获取数据（不是链接进引擎的 FFI，见 AGENTS.md 不变量 58）
        if path == "api/context" {
            let scope = query["scope"] ?? "group"
            let name = query["name"] ?? ""
            let budget = Int(query["budget"] ?? "9000") ?? 9000
            var args = ["context"]
            if scope == "project" { args.append(name) }
            args += ["--budget", String(budget), "--json"]
            return try await EngineCLI.shared.runData(args, timeout: 60)
        }
        if path == "api/tools" {
            return try await EngineCLI.shared.toolsManifest()
        }
        throw EngineError.failed("未知路径：\(path)")
    }

    /// 引擎 tools --json → ai-sdk 工具定义
    static func engineToolDefinitions() async -> [ToolDefinition] {
        guard let data = try? await rawGet("api/tools", query: [:]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tools = obj["tools"] as? [[String: Any]] else { return [] }
        return tools.compactMap { t in
            guard let name = t["name"] as? String else { return nil }
            let desc = (t["description"] as? String) ?? ""
            let paramString = (t["params"] as? String) ?? ""
            var props: [String: Any] = [:]
            var required: [String] = []
            for key in paramString.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !key.isEmpty {
                props[key] = ["type": "string", "description": key]
                required.append(key)
            }
            return ToolDefinition(
                name: name,
                description: desc,
                parametersJSON: ["type": "object", "properties": props, "required": required]
            )
        }
    }

    /// 工具名 → 该工具的 parameters JSON（供 `executeTool` 做必填校验）。
    ///
    /// ⚠️ **agent 循环与「一键全量」共用这一份**，不许各抄一份。
    /// 抄两份必然漂移，而漂移的后果是**必填校验悄悄失效** ——
    /// `run_shallow_update` 传空 `name` 在引擎侧等于「整个项目群」
    /// （`executeTool` 注释里的老坑 NC31），校验一旦失效就是静默的全群改写。
    ///
    /// 必填清单**只从引擎的工具清单取**（`tools --json` 的 `params` 字段），
    /// 不在客户端硬编码：客户端抄一份就等于自己发明契约。
    static func requiredParamsByTool() async -> [String: String] {
        var m: [String: String] = [:]
        for d in await engineToolDefinitions() {
            if let data = try? JSONSerialization.data(withJSONObject: d.parametersJSON),
               let s = String(data: data, encoding: .utf8) {
                m[d.name] = s
            }
        }
        return m
    }

    /// 工具执行（本机进程间：CLI 子进程）。返回 (ok, 结果文本)
    static func executeTool(
        _ name: String,
        params: [String: Any],
        parametersJSONByName: [String: String]
    ) async -> (Bool, String) {
        // ⚠️ 必填校验放在**执行点内部**，不是调用方（缺陷 NC31 的收口）。
        // 空项目名在引擎侧等于「整个项目群」，实测会改写所有项目的 README；
        // 放在调用方的话，将来多一个调用点就绕过去了。
        // 必填清单只有一个来源：已经发给模型的那份 required。
        let required = ToolArgs.required(parametersJSONByName: parametersJSONByName, tool: name)
        let absent = ToolArgs.missing(params: params, required: required)
        if !absent.isEmpty {
            return (false, ToolArgs.missingMessage(tool: name, missing: absent))
        }
        func str(_ key: String) -> String { params[key] as? String ?? "" }
        do {
            switch name {
            case "get_group_context":
                let data = try await rawGet("api/context", query: ["scope": "group", "budget": "8000"])
                return (true, ContextEnvelope.decode(data).context)
            case "get_project_context":
                // ⚠️ 原来这里把整个 JSON 信封原样交给模型（#191）：
                // `{"scope":"project","budget":8000,"context":"# deepGit…\n…"}`
                // 系统提示词那条路交的是 markdown，引擎自己的 MCP 工具回的也是裸 markdown
                // —— 同名工具三种形状，模型读到的第一行是 `{"scope":`。
                let data = try await rawGet("api/context", query: ["scope": "project", "name": str("name"), "budget": "8000"])
                return (true, ContextEnvelope.decode(data).context)
            case "get_project_docs":
                let data = try await EngineCLI.shared.runData(["docs", str("name"), "--json"], timeout: 60)
                return (true, String(data: data, encoding: .utf8) ?? "")
            case "get_journal":
                let data = try await EngineCLI.shared.journal(name: str("name"))
                return (true, String(data: data, encoding: .utf8) ?? "")
            case "get_milestones":
                let data = try await EngineCLI.shared.runData(["milestone", "list", "--json"], timeout: 60)
                return (true, String(data: data, encoding: .utf8) ?? "")
            case "run_shallow_update":
                let data = try await EngineCLI.shared.update(name: str("name"), deep: false)
                return (true, String(data: data, encoding: .utf8) ?? "完成")
            case "run_deep_update":
                let data = try await EngineCLI.shared.update(name: str("name"), deep: true)
                return (true, String(data: data, encoding: .utf8) ?? "完成")
            case "git_commit":
                let data = try await EngineCLI.shared.gitOp(project: str("name"), op: "commit", message: str("message"))
                return (true, String(data: data, encoding: .utf8) ?? "完成")
            case "git_pull_push":
                let data = try await EngineCLI.shared.gitOp(project: str("name"), op: str("op").isEmpty ? "pull" : str("op"))
                return (true, String(data: data, encoding: .utf8) ?? "完成")
            case "milestone_done":
                try await EngineCLI.shared.milestoneAction(project: str("project"), name: str("name"), action: "done")
                return (true, "完成")
            default:
                return (false, "未知工具：\(name)")
            }
        } catch {
            return (false, EngineError.userMessage(for: error))
        }
    }

    /// 运行完整 agent 循环，返回最终回答文本。
    /// onEvent：过程事件（工具调用等），UI 可订阅展示。
    static func run(
        question: String,
        target: AgentTarget,
        config: AIConfig? = nil,
        maxRounds: Int = 4,
        onEvent: ((String) -> Void)? = nil
    ) async throws -> String {
        // 无状态入口：走多轮版本（history 传空），再取最后一条 assistant 文本。
        // 与原实现的返回值等价：正常收尾时最后一条 assistant 就是 result.text，
        // 撞轮次上限时是 partial。
        let convo = try await run(question: question,
                                  target: target,
                                  history: [],
                                  config: config,
                                  maxRounds: maxRounds,
                                  onEvent: onEvent)
        return convo.last(where: { $0.role == "assistant" })?.text ?? ""
    }

    /// 多轮版本：把已有历史接在问题前面，返回**追加后**的完整历史。
    ///
    /// ⚠️ 原来只有上面那个 `run`，它每次都从
    /// `var convo = [ChatMessage.user(question)]` 零起步 —— 于是
    /// 所谓"对话"其实是一串互不相干的一次性提问，模型看不见上一轮。
    /// 「那刚才那个项目后来怎么样了」这类追问必然落空，而且失败得很安静：
    /// 模型会拿第一轮的上下文硬答，答得还挺像回事。
    ///
    /// 返回新数组而不是就地改：调用方（视图模型）要把结果存进 @State，
    /// 而 AgentCore 是无状态的，不该替谁改状态。
    @discardableResult
    static func run(
        question: String,
        target: AgentTarget,
        history: [ChatMessage],
        config: AIConfig? = nil,
        maxRounds: Int = 4,
        onEvent: ((String) -> Void)? = nil
    ) async throws -> [ChatMessage] {
        let cfg = config ?? AIConfig.load()
        guard cfg.isConfigured else {
            throw EngineError.failed("AI 未配置：请在 AI 设置里选择 provider 并填写 API Key")
        }
        let ctxData = try await rawGet(target.scopePath, query: target.scopeQuery)
        // 畸形 JSON 仍然 `try` 抛错（这是对的：引擎二进制坏了就该硬失败，
        // 而不是拿一段说明文字冒充上下文）。
        // 但「JSON 合法、context 键缺失」原来落到 `?? ""`，
        // 空上下文会被模型读成「这个项目群什么都没有」。
        // 「没解出来」与「没有」必须分开 —— 与工具那条路共用同一个判定。
        let ctxObj = try JSONSerialization.jsonObject(with: ctxData) as? [String: Any]
        let decoded = ContextEnvelope.decode(ctxData)
        let context = decoded.note.map { $0 + "\n\n" + decoded.context } ?? decoded.context
        _ = ctxObj
        let toolsData = try await rawGet("api/tools", query: [:])
        let toolsText = String(data: toolsData, encoding: .utf8) ?? "{}"
        let toolDefs = await engineToolDefinitions()
        // 必填参数**只从这一份取**：就是已经发给模型的那份工具定义。
        // 执行端照模型看到过的契约执行，不另抄一份（抄两份必然漂移）。
        // 「一键全量」走的是同一个 `requiredParamsByTool()`，见那里的注释。
        let paramsByTool = await requiredParamsByTool()

        let scopeLine = "scope: \(target.label)"
        let system = """
        你是 deepGit 项目群管理助手。引擎（AI 无关内核）已把当前范围的确定性事实整理给你。

        ## 当前上下文
        用户关注的范围：\(scopeLine)

        ## 可用工具（原生 tool_calls）
        \(toolsText)

        ## 行为准则
        - 需要更多数据或要执行动作时，通过工具调用完成；拿到足够信息后给出最终中文回答
        - 最终回答要具体：点名项目/分支，给可执行建议；不编造上下文里没有的事实
        """

        let fullSystem = system + "\n\n## 当前范围事实（引擎生成）\n\n" + context
        let model = LanguageModel(config: cfg)

        // 历史 + 本轮提问。历史先裁一刀，否则聊几轮就撞上模型的上下文上限，
        // 报一个和"你问题太长"长得一样的错。
        // 拼对话这一步抽在 Conversation.seed —— 「历史会不会被丢」因此可测。
        // 内联在这里时，lint 只能查到某一种写法，换个写法缺陷就溜过去了。
        var convo = Conversation.seed(history: history, question: question)

        for round in 1...maxRounds {
            let result = try await model.generateText(system: fullSystem, messages: convo, tools: toolDefs)
            if result.toolCalls.isEmpty {
                convo.append(ChatMessage.assistant(result.text))
                return convo
            }
            convo.append(ChatMessage(role: "assistant", text: result.text, toolCalls: result.toolCalls, toolCallID: nil))
            for call in result.toolCalls {
                onEvent?("🔧 \(call.name)")
                // ⚠️ 畸形参数必须在**执行之前**拦下（缺陷 NC31）。
                // 原来这里写的是
                //   `(try? JSONSerialization.jsonObject(...)) as? [String: Any] ?? [:]`
                // 畸形 JSON 被吞成「没有参数」，而「没有 name」在客户端会变成
                // 空位置参数 `["update", "", …]`，引擎又把它等同于「整个项目群」——
                // 实测一次畸形的模型响应就会改写所有项目的 README，界面还显示 ✓ 成功。
                //
                // 拦住之后**不执行**，只把原因回报给模型让它重试：
                // 报「执行失败」会诱使模型放弃或编造参数，报清楚才能重试。
                let params: [String: Any]
                switch ToolArgs.decode(call.argumentsJSON) {
                case .malformed(let raw):
                    let why = ToolArgs.malformedMessage(tool: call.name, raw: raw)
                    onEvent?("   ✗ \(call.name)：参数非法，未执行")
                    // isError 必须显式打：界面靠它决定显不显示，
                    // 靠文案里有没有「执行失败」四个字判断过一次就漏过路径。
                    convo.append(ChatMessage.tool(why, callID: call.id, isError: true))
                    continue
                case .object(let obj):
                    params = obj
                }

                // 必填参数由 executeTool **在执行点内部**校验（见那里的注释），
                // 这样将来多一个调用点也绕不过去。这里只负责畸形 JSON 的拦截，
                // 因为它发生在 params 存在之前。
                let (ok, out) = await executeTool(
                    call.name, params: params, parametersJSONByName: paramsByTool)
                // ⚠️ 引擎的截断披露写在**结尾**（#191）。从头部切 16000 会把
                // 引擎那行披露一起切掉，于是模型看到一段「看起来完整、其实缺尾巴」
                // 的上下文。客户端自己切的这刀必须自报家门。
                let clipped = out.count > 16000
                    ? String(out.prefix(16000)) + clientClipNote(out.count, 16000)
                    : out
                onEvent?("   \(ok ? "✓" : "✗") \(call.name)")
                convo.append(ChatMessage.tool(
                    "工具 \(call.name) 执行\(ok ? "成功" : "失败")：\n\(clipped)",
                    callID: call.id, isError: !ok))
            }
            if round == maxRounds {
                // ⚠️ 这里**不能**抛错丢掉这一轮：工具已经在上面执行完了。
                // 判定在 AgentOutcome（独立文件、纯函数、可被 AgentCheck 直接编译测试）：
                // 原来只看「有没有文本」，于是「文本空 + 工具已执行」被判成真空 → throw，
                // 而 run_shallow_update / git_commit 的副作用**早已发生** ——
                // 界面显示「失败」、工具输出与历史全丢，用户重试就重复执行一次（缺陷 NC30）。
                // 只有「文本真空 **且** 这一轮没跑过工具」才该抛错，那时抛错才是诚实说法。
                switch AgentOutcome.finish(
                    text: result.text,
                    executedTools: result.toolCalls.map(\.name),
                    maxRounds: maxRounds
                ) {
                case .final(let message):
                    convo.append(ChatMessage.assistant(message))
                    return convo
                case .failed:
                    throw EngineError.failed("已达工具调用轮次上限（\(maxRounds)），且模型未产出任何文本")
                }
            }
        }
        throw EngineError.failed("agent 循环异常退出")
    }

    /// 一键项目说明：收集事实 → 生成 markdown 项目说明
    static func projectBrief(projectName: String) async throws -> String {
        return try await run(
            question: """
            为项目「\(projectName)」生成一份**项目说明**（markdown），包含：
            1. 一句话定位（结合 README 与代码构成判断它是什么）
            2. 当前状态（分支进度、未提交/未跟踪/stash、最近活跃）
            3. 工程结构要点（语言构成、热点文件）
            4. 风险与建议下一步
            要求：面向"第一次接触这个项目的人"，500 字以内，具体、可执行、不编造。
            """,
            target: .project(projectName)
        )
    }

    /// 更新后摘要：对比本次浅/深更新，生成简短摘要
    static func updateDigest(projectName: String, deep: Bool) async throws -> String {
        return try await run(
            question: """
            刚对项目「\(projectName)」执行了\(deep ? "深度更新" : "浅更新")。
            请基于引擎事实生成一段 ≤120 字的中文摘要：这次更新记录了什么、哪些分支有变化、有什么值得注意的。
            只输出摘要正文。
            """,
            target: .project(projectName),
            maxRounds: 2
        )
    }

    /// 定时更新简报（项目群级）
    static func scheduledDigest() async throws -> String {
        return try await run(
            question: "定时更新已完成。请生成 ≤150 字的项目群简报：哪些项目有新变化、哪些需要人处理（未提交/停滞/待合入）。只输出简报正文。",
            target: .group,
            maxRounds: 3
        )
    }
}
