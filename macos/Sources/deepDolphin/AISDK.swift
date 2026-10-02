// AISDK.swift — 客户端 AI 通道（deepOrca ai-sdk 模式的 Swift 实现）。
//
// 【边界】引擎是 AI 无关内核；模型目录来自 models.dev（ModelCatalog），
// 通道按 OpenAI 兼容 / Anthropic 双协议组装（baseURL 来自目录或用户覆盖），
// 工具走**原生 tool_calls / tool_use 线格式**（非文本协议）。
// API Key 存 macOS 钥匙串，永不进引擎与日志。
import Foundation
import Security

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
    private static let service = "cn.deepdolphin.app.ai"
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

    /// 上次 `save()` 是否把 key 真正写进了 Keychain。
    ///
    /// 为什么要单独记：`isConfigured` 只看 `apiKey` 非空，
    /// 而那个非空值是**用户刚输入的**——哪怕 Keychain 写失败了它也非空。
    /// 于是设置页显示「已配置」、保存按钮照常成功、下次启动 key 消失。
    /// 这个标志让 `keychainSaveFailed` 能把那次失败说出口。
    /// nil = 还没保存过（不是「保存成功」也不是「失败」）。
    static var keychainSaveFailed: Bool?

    /// 保存。返回 nil 表示成功；非 nil 是给用户看的失败原因。
    ///
    /// 原来返回 `Void` 且完全不看 `SecItemAdd` 的返回码 ——
    /// 「key 没存进去」这件事不留任何痕迹。
    @discardableResult
    func save() -> String? {
        Self.ud.set(providerID, forKey: "ai.providerID")
        Self.ud.set(model, forKey: "ai.model")
        Self.ud.set(baseURL, forKey: "ai.baseURL")
        var problem: String?
        if apiKey.isEmpty {
            let st = Keychain.delete(service: Self.service, account: Self.keyAccount)
            // -25300 = 本来就没有，清空是成功的
            if st != errSecSuccess && st != errSecItemNotFound {
                problem = "清除 Keychain 里的 key 失败（\(Keychain.describe(st))）"
            }
            Self.keychainSaveFailed = (problem == nil) ? false : true
        } else {
            let st = Keychain.set(apiKey, service: Self.service, account: Self.keyAccount)
            if st != errSecSuccess {
                problem = "key 没能存进 Keychain（\(Keychain.describe(st))）—— " +
                    "设置会丢失，请重试或检查钥匙串权限"
            }
            Self.keychainSaveFailed = (st != errSecSuccess)
        }
        // 清掉 mock 自测可能残留的明文副本（否则清空 key 后 isConfigured 仍为 true）
        Self.ud.removeObject(forKey: "ai.apiKey")
        if let problem { NSLog("deepgit: \(problem)") }
        return problem
    }
}

extension Keychain {
    /// `OSStatus` 的人类可读形式（`-34018` 这种数字对用户毫无意义）。
    static func describe(_ status: OSStatus) -> String {
        let msg = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
        return "\(status) \(msg)"
    }
}

// MARK: - Keychain

/// Keychain 读写。**每个函数都返回 `OSStatus`**，调用方必须检查。
///
/// ⚠️ 原来三个函数都返回 `Void`，`SecItemDelete` / `SecItemAdd` 的返回码
/// 直接丢掉。于是「key 存不进去」这件事**没有任何痕迹**：
/// `AIConfig.save()` 照常返回，设置页显示已保存，`isConfigured` 也是 true，
/// 下次启动 `load()` 却读了个空 —— key 静默消失，用户只会觉得「这软件有 bug」。
///
/// 诚实说明：**我没能在当前构建配置下复现出活的写入失败**。
/// 实测（2026-10-01，arm64 / ad-hoc 签名）CLI 与 .app bundle 两种形态
/// `SecItemAdd` 都返回 0，跨进程 `SecItemCopyMatching` 也能读回。
/// 所以这是**潜在**失效路径（keychain 被锁、条目 ACL 不匹配、
/// 未来改成正式签名后 entitlement 变化），不是当前就咬人的 bug。
/// 但丢弃返回码属于本项目最高发的那族缺陷（读不出来/没做成被报成做成了），
/// 而且修起来是几行的事，不值得留着。
enum Keychain {
    /// - Returns: `errSecSuccess` 表示成功；其余是 `OSStatus`（见 `SecCopyErrorMessageString`）。
    @discardableResult
    static func set(_ value: String, service: String, account: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else { return errSecParam }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // 先删后加：同名条目已存在时 SecItemAdd 会返回 errSecDuplicateItem(-25299)。
        // 删除失败要分情况：-25300（item not found）是正常的，
        // 其它错误则意味着「旧条目可能还在」，此时直接 add 必然失败。
        let delStatus = SecItemDelete(query as CFDictionary)
        if delStatus != errSecSuccess && delStatus != errSecItemNotFound {
            return delStatus
        }
        var attrs = query
        attrs[kSecValueData as String] = data
        return SecItemAdd(attrs as CFDictionary, nil)
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
        // 读失败和「没有 key」都返回 nil —— 调用方分不出这两种，
        // 但这与写不同：读失败时用户本来也没有可用的 key，行为一致。
        // 需要区分时看 `getDetailed`。
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 需要区分「没有」与「读失败」时用这个。
    static func getDetailed(service: String, account: String) -> (value: String?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return (nil, status) }
        guard let data = result as? Data, let s = String(data: data, encoding: .utf8) else {
            return (nil, errSecDecode)
        }
        return (s, status)
    }

    @discardableResult
    static func delete(service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary)
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
        // ⚠️ 网络错误必须**包一层**再抛出去。
        //
        // 原来 `URLError` 裸传，而六个调用点全都用 `error.localizedDescription`
        // —— 于是用户在中文界面里看到的是
        //     "Could not connect to the server."
        // 英文、且不告诉他**哪一部分**错了。而这恰恰发生在「测试连接」上：
        // 用户刚填完 baseURL 想知道对不对，这句话没用。
        //
        // 包一层而不是让每个调用点多传参数：漏传一处，那个出口就退回英文。
        // 让错误自己带着"试的是哪个地址"，`localizedDescription` 在任何地方都自动是好的。
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw EngineError.failed("AI 响应异常")
            }
            guard http.statusCode == 200 else {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw EngineError.failed("AI 调用失败（HTTP \(http.statusCode)）：\(Self.redacted(text).prefix(300))")
            }
            return data
        } catch {
            throw AIChannelError(underlying: error, attemptedURL: url.absoluteString)
        }
    }
}
