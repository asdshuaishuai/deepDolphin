// AgentCore.swift — 无 UI 的 agent 执行核心（AI 层的可复用部分）。
//
// 使用方：AgentView（对话）、浅/深更新的 AI 摘要、一键项目说明、定时更新的 AI 简报。
// 引擎是 AI 无关内核：这里拉上下文包（/api/context）与工具清单（/api/tools），
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
        // 进程内通信：通过 CLI 子进程获取数据
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

    /// 引擎 /api/tools → ai-sdk 工具定义
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

    /// 工具执行（引擎 HTTP API）。返回 (ok, 结果文本)
    static func executeTool(_ name: String, params: [String: Any]) async -> (Bool, String) {
        func str(_ key: String) -> String { params[key] as? String ?? "" }
        do {
            switch name {
            case "get_group_context":
                let data = try await rawGet("api/context", query: ["scope": "group", "budget": "8000"])
                return (true, String(data: data, encoding: .utf8) ?? "")
            case "get_project_context":
                let data = try await rawGet("api/context", query: ["scope": "project", "name": str("name"), "budget": "8000"])
                return (true, String(data: data, encoding: .utf8) ?? "")
            case "get_project_docs":
                let data = try await rawGet("api/docs", query: ["name": str("name")])
                return (true, String(data: data, encoding: .utf8) ?? "")
            case "get_journal":
                let data = try await rawGet("api/journal", query: ["name": str("name")])
                return (true, String(data: data, encoding: .utf8) ?? "")
            case "get_milestones":
                let data = try await rawGet("api/milestones", query: [:])
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
            return (false, error.localizedDescription)
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
        let cfg = config ?? AIConfig.load()
        guard cfg.isConfigured else {
            throw EngineError.failed("AI 未配置：请在 AI 设置里选择 provider 并填写 API Key")
        }
        let ctxData = try await rawGet(target.scopePath, query: target.scopeQuery)
        let ctxObj = try JSONSerialization.jsonObject(with: ctxData) as? [String: Any]
        let context = ctxObj?["context"] as? String ?? ""
        let toolsData = try await rawGet("api/tools", query: [:])
        let toolsText = String(data: toolsData, encoding: .utf8) ?? "{}"
        let toolDefs = await engineToolDefinitions()

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
        var convo: [ChatMessage] = [ChatMessage.user(question)]

        for round in 1...maxRounds {
            let result = try await model.generateText(system: fullSystem, messages: convo, tools: toolDefs)
            if result.toolCalls.isEmpty {
                return result.text
            }
            convo.append(ChatMessage(role: "assistant", text: result.text, toolCalls: result.toolCalls, toolCallID: nil))
            for call in result.toolCalls {
                onEvent?("🔧 \(call.name)")
                let params = (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8))) as? [String: Any] ?? [:]
                let (ok, out) = await executeTool(call.name, params: params)
                let clipped = out.count > 16000 ? String(out.prefix(16000)) + "\n…(截断)" : out
                onEvent?("   \(ok ? "✓" : "✗") \(call.name)")
                convo.append(ChatMessage(role: "tool", text: "工具 \(call.name) 执行\(ok ? "成功" : "失败")：\n\(clipped)", toolCalls: nil, toolCallID: call.id))
            }
            if round == maxRounds {
                throw EngineError.failed("已达工具调用轮次上限（\(maxRounds)）")
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
