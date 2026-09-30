// AISDK.swift — 客户端 AI 通道（deepOrca ai-sdk 模式的 Swift 实现）。
//
// 【边界】引擎是 AI 无关内核；模型目录来自 models.dev（ModelCatalog），
// 通道按 OpenAI 兼容 / Anthropic 双协议组装（baseURL 来自目录或用户覆盖），
// 工具走**原生 tool_calls / tool_use 线格式**（非文本协议）。
// API Key 存 macOS 钥匙串，永不进引擎与日志。
import Foundation
import Security

// MARK: - 消息与工具

struct ChatMessage: Equatable {
    var role: String           // system | user | assistant | tool
    var text: String
    /// assistant 原生工具调用（OpenAI 形状，Anthropic 侧转换）
    var toolCalls: [ToolCallRequest]?
    /// tool 角色消息的调用 id（OpenAI tool_call_id / Anthropic tool_use_id）
    var toolCallID: String?

    static func system(_ t: String) -> ChatMessage { ChatMessage(role: "system", text: t, toolCalls: nil, toolCallID: nil) }
    static func user(_ t: String) -> ChatMessage { ChatMessage(role: "user", text: t, toolCalls: nil, toolCallID: nil) }
    static func assistant(_ t: String) -> ChatMessage { ChatMessage(role: "assistant", text: t, toolCalls: nil, toolCallID: nil) }
}

struct ToolCallRequest: Equatable {
    let id: String
    let name: String
    /// JSON 对象字符串
    let argumentsJSON: String
}

struct ToolCallResponse: Equatable {
    let id: String
    let name: String
    /// 已执行的结果文本
    let content: String
    let isError: Bool
}

struct ToolDefinition {
    let name: String
    let description: String
    /// JSON Schema 对象（字符串键）
    let parametersJSON: [String: Any]
}

struct GenerateTextResult {
    let text: String
    let toolCalls: [ToolCallRequest]
}

// MARK: - 配置

struct AIConfig: Equatable {
    /// models.dev 的 provider id（如 deepseek / openai / anthropic / openrouter …）
    var providerID: String = "deepseek"
    var model: String = ""
    var baseURL: String = ""
    var apiKey: String = ""

    var isAnthropic: Bool { providerID == "anthropic" }

    var effectiveBaseURL: String {
        if !baseURL.isEmpty { return sanitized(baseURL) }
        // 目录优先，其次常用默认。目录数据来自网络（models.dev），
        // 强制 https（localhost 豁免）——防投毒端点骗取 apiKey
        if let api = ModelCatalog.shared.provider(providerID)?.api, !api.isEmpty {
            return sanitized(api)
        }
        return providerID == "anthropic" ? "https://api.anthropic.com" : ""
    }

    /// 仅放行 https 或 localhost 的 http
    private func sanitized(_ url: String) -> String {
        let lower = url.lowercased()
        if lower.hasPrefix("https://") { return url }
        if lower.hasPrefix("http://127.0.0.1") || lower.hasPrefix("http://localhost") { return url }
        return ""
    }

    var isConfigured: Bool {
        !effectiveBaseURL.isEmpty && (providerID == "ollama" || !apiKey.isEmpty)
    }

    // ---- 持久化：key 进 Keychain，其余进 UserDefaults ----

    private static let ud = UserDefaults.standard
    private static let service = "cn.deepgit.app.ai"
    private static let keyAccount = "api-key"

    static func load() -> AIConfig {
        var c = AIConfig()
        if let pid = ud.string(forKey: "ai.providerID") {
            c.providerID = pid
        } else if let legacy = ud.string(forKey: "ai.preset") {
            // 旧预设迁移：custom 之外的名字都是 models.dev provider id
            c.providerID = (legacy == "custom") ? "deepseek" : legacy
        }
        c.model = ud.string(forKey: "ai.model") ?? ""
        c.baseURL = ud.string(forKey: "ai.baseURL") ?? ""
        // Keychain 优先；空则退回 UserDefaults（无头自测/CI 用，明文）。
        // 正常流程（用户在设置页输入）走 Keychain，ACL 归本 App，无读取弹窗。
        c.apiKey = Keychain.get(service: service, account: keyAccount)
            ?? ud.string(forKey: "ai.apiKey")
            ?? ""
        return c
    }

    func save() {
        Self.ud.set(providerID, forKey: "ai.providerID")
        Self.ud.set(model, forKey: "ai.model")
        Self.ud.set(baseURL, forKey: "ai.baseURL")
        if apiKey.isEmpty {
            Keychain.delete(service: Self.service, account: Self.keyAccount)
        } else {
            Keychain.set(apiKey, service: Self.service, account: Self.keyAccount)
        }
        // 清掉 mock 自测可能残留的明文副本（否则清空 key 后 isConfigured 仍为 true）
        Self.ud.removeObject(forKey: "ai.apiKey")
    }
}

// MARK: - Keychain

enum Keychain {
    static func set(_ value: String, service: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 通道（ai-sdk 的 LanguageModel.swift 版）

struct LanguageModel {
    let config: AIConfig

    /// generateText：一次性补全（带原生工具调用支持）。
    /// 返回文本 + 模型请求的工具调用（如有）。
    func generateText(
        system: String,
        messages: [ChatMessage],
        tools: [ToolDefinition],
        maxTokens: Int = 4000
    ) async throws -> GenerateTextResult {
        guard config.isConfigured else {
            throw EngineError.failed("AI 未配置：请在设置里选择 provider 并填写 API Key")
        }
        let base = config.effectiveBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else {
            throw EngineError.failed("Base URL 为空：请在 AI 设置里补全")
        }
        if config.isAnthropic {
            return try await generateAnthropic(base: base, system: system, messages: messages, tools: tools, maxTokens: maxTokens)
        }
        return try await generateOpenAICompatible(base: base, system: system, messages: messages, tools: tools, maxTokens: maxTokens)
    }

    /// 连通性测试
    func testConnection() async throws -> String {
        let r = try await generateText(
            system: "你是连通性测试器，只回复：OK",
            messages: [ChatMessage.user("ping")],
            tools: [],
            maxTokens: 16
        )
        return r.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: OpenAI 兼容（deepseek / openai / ollama / openrouter / 网关 / 自定义）

    private func generateOpenAICompatible(
        base: String, system: String, messages: [ChatMessage],
        tools: [ToolDefinition], maxTokens: Int
    ) async throws -> GenerateTextResult {
        var payload: [[String: Any]] = [["role": "system", "content": system]]
        for m in messages {
            switch m.role {
            case "assistant" where !(m.toolCalls ?? []).isEmpty:
                var entry: [String: Any] = ["role": "assistant"]
                if !m.text.isEmpty { entry["content"] = m.text }
                entry["tool_calls"] = (m.toolCalls ?? []).map { tc in
                    [
                        "id": tc.id,
                        "type": "function",
                        "function": ["name": tc.name, "arguments": tc.argumentsJSON],
                    ] as [String: Any]
                }
                payload.append(entry)
            case "tool":
                payload.append([
                    "role": "tool",
                    "tool_call_id": m.toolCallID ?? "",
                    "content": m.text,
                ])
            default:
                payload.append(["role": m.role, "content": m.text])
            }
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": payload,
            "stream": false,
            "max_tokens": maxTokens,
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { t in
                ["type": "function", "function": [
                    "name": t.name,
                    "description": t.description,
                    "parameters": t.parametersJSON,
                ]] as [String: Any]
            }
        }

        guard let chatURL = URL(string: "\(base)/chat/completions") else {
            throw EngineError.failed("Base URL 非法：\(base)")
        }
        let data = try await post(url: chatURL, body: body,
                            headers: ["Authorization": "Bearer \(config.apiKey)"])
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw EngineError.failed("AI 响应无法解析")
        }
        let text = (message["content"] as? String) ?? ""
        var calls: [ToolCallRequest] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for (i, tc) in rawCalls.enumerated() {
                guard let fn = tc["function"] as? [String: Any],
                      let name = fn["name"] as? String else { continue }
                calls.append(ToolCallRequest(
                    id: (tc["id"] as? String) ?? "call_\(i)",
                    name: name,
                    argumentsJSON: (fn["arguments"] as? String) ?? "{}"
                ))
            }
        }
        return GenerateTextResult(text: text, toolCalls: calls)
    }

    // MARK: Anthropic messages

    private func generateAnthropic(
        base: String, system: String, messages: [ChatMessage],
        tools: [ToolDefinition], maxTokens: Int
    ) async throws -> GenerateTextResult {
        var payload: [[String: Any]] = []
        for m in messages {
            switch m.role {
            case "assistant" where !(m.toolCalls ?? []).isEmpty:
                var blocks: [[String: Any]] = []
                if !m.text.isEmpty {
                    blocks.append(["type": "text", "text": m.text])
                }
                for tc in m.toolCalls ?? [] {
                    let input = (try? JSONSerialization.jsonObject(with: Data(tc.argumentsJSON.utf8))) as? [String: Any] ?? [:]
                    blocks.append(["type": "tool_use", "id": tc.id, "name": tc.name, "input": input])
                }
                payload.append(["role": "assistant", "content": blocks])
            case "tool":
                payload.append(["role": "user", "content": [[
                    "type": "tool_result",
                    "tool_use_id": m.toolCallID ?? "",
                    "content": m.text,
                ]]])
            default:
                payload.append(["role": m.role, "content": m.text])
            }
        }

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": payload,
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { t in
                ["name": t.name, "description": t.description, "input_schema": t.parametersJSON] as [String: Any]
            }
        }

        guard let msgURL = URL(string: "\(base)/v1/messages") else {
            throw EngineError.failed("Base URL 非法：\(base)")
        }
        let data = try await post(url: msgURL, body: body, headers: [
            "x-api-key": config.apiKey,
            "anthropic-version": "2023-06-01",
        ])
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw EngineError.failed("AI 响应无法解析")
        }
        var text = ""
        var calls: [ToolCallRequest] = []
        for block in content {
            switch block["type"] as? String {
            case "text":
                text += (block["text"] as? String) ?? ""
            case "tool_use":
                let input = block["input"] as? [String: Any] ?? [:]
                let argsJSON = String(data: try JSONSerialization.data(withJSONObject: input), encoding: .utf8) ?? "{}"
                calls.append(ToolCallRequest(
                    id: (block["id"] as? String) ?? "toolu_\(calls.count)",
                    name: (block["name"] as? String) ?? "",
                    argumentsJSON: argsJSON
                ))
            default:
                break
            }
        }
        return GenerateTextResult(text: text, toolCalls: calls)
    }

    /// 错误文本脱敏：剥掉可能被恶意服务器回显的凭证模式
    static func redacted(_ text: String) -> String {
        var t = text
        for pattern in ["Bearer ", "sk-", "x-api-key"] where t.contains(pattern) {
            // 保守做法：包含敏感模式时整体截断为提示
            t = "（响应含敏感字段，已隐藏）"
            break
        }
        return t
    }

    // MARK: 公共 POST

    private func post(url: URL, body: [String: Any], headers: [String: String]) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers where !v.isEmpty {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw EngineError.failed("AI 响应异常")
        }
        guard http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw EngineError.failed("AI 调用失败（HTTP \(http.statusCode)）：\(Self.redacted(text).prefix(300))")
        }
        return data
    }
}
