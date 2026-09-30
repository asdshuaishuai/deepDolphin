// AIProvider.swift — 客户端 AI 层（deepDesign 模式）。
//
// 【边界】引擎是 AI 无关内核；AI 的配置、调用与 agent 循环全部在客户端完成：
//   配置 → Keychain（key）+ UserDefaults（其余）
//   调用 → 直连用户选择的 provider（OpenAI 兼容 / Anthropic）
//   工具 → 通过引擎 HTTP API 执行（/api/tools 清单驱动）
import Foundation
import Security

// MARK: - 配置

enum AIPreset: String, CaseIterable, Identifiable {
    case deepseek, openai, anthropic, ollama, custom
    var id: String { rawValue }

    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com"
        case .ollama: return "http://127.0.0.1:11434/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .openai: return "gpt-4o-mini"
        case .anthropic: return "claude-sonnet-4-5"
        case .ollama: return "qwen3:8b"
        case .custom: return ""
        }
    }

    var isAnthropic: Bool { self == .anthropic }

    var label: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .ollama: return "Ollama（本地）"
        case .custom: return "自定义（OpenAI 兼容）"
        }
    }
}

struct AIConfig: Equatable {
    var preset: AIPreset = .deepseek
    var model: String = ""
    var baseURL: String = ""
    var apiKey: String = ""

    var effectiveModel: String { model.isEmpty ? preset.defaultModel : model }
    var effectiveBaseURL: String { baseURL.isEmpty ? preset.defaultBaseURL : baseURL }
    var isConfigured: Bool {
        if preset == .ollama { return !effectiveBaseURL.isEmpty }
        return !apiKey.isEmpty && !effectiveBaseURL.isEmpty
    }

    // ---- 持久化：key 进 Keychain，其余进 UserDefaults ----

    private static let ud = UserDefaults.standard
    private static let service = "cn.deepgit.app.ai"
    private static let keyAccount = "api-key"

    static func load() -> AIConfig {
        var c = AIConfig()
        c.preset = AIPreset(rawValue: Self.ud.string(forKey: "ai.preset") ?? "deepseek") ?? .deepseek
        c.model = Self.ud.string(forKey: "ai.model") ?? ""
        c.baseURL = Self.ud.string(forKey: "ai.baseURL") ?? ""
        // Keychain 优先；空则退回 UserDefaults（无头自测/CI 用，明文）。
        // 正常流程（用户在设置页输入）走 Keychain，ACL 归本 App，无读取弹窗。
        c.apiKey = Keychain.get(service: service, account: keyAccount)
            ?? ud.string(forKey: "ai.apiKey")
            ?? ""
        return c
    }

    func save() {
        Self.ud.set(preset.rawValue, forKey: "ai.preset")
        Self.ud.set(model, forKey: "ai.model")
        Self.ud.set(baseURL, forKey: "ai.baseURL")
        if apiKey.isEmpty {
            Keychain.delete(service: Self.service, account: Self.keyAccount)
        } else {
            Keychain.set(apiKey, service: Self.service, account: Self.keyAccount)
        }
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

// MARK: - 调用

struct AIProvider {
    let config: AIConfig

    struct Message: Equatable {
        let role: String   // system | user | assistant
        let content: String
    }

    /// 对话补全。messages 不含 system（单独传）。
    func chat(system: String, messages: [Message], maxTokens: Int = 4000) async throws -> String {
        guard config.isConfigured else {
            throw EngineError.failed("AI 未配置：请在设置里填写 API Key")
        }
        let base = config.effectiveBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if config.preset.isAnthropic {
            return try await anthropicChat(base: base, system: system, messages: messages, maxTokens: maxTokens)
        }
        return try await openAIChat(base: base, system: system, messages: messages, maxTokens: maxTokens)
    }

    /// OpenAI 兼容（deepseek / openai / ollama / custom）
    private func openAIChat(base: String, system: String, messages: [Message], maxTokens: Int) async throws -> String {
        var payloadMessages: [[String: Any]] = [["role": "system", "content": system]]
        for m in messages {
            payloadMessages.append(["role": m.role, "content": m.content])
        }
        var req = URLRequest(url: URL(string: "\(base)/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.effectiveModel,
            "messages": payloadMessages,
            "stream": false,
            "max_tokens": maxTokens,
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw EngineError.failed("AI 响应异常")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw EngineError.failed("AI 调用失败（HTTP \(http.statusCode)）：\(body.prefix(300))")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw EngineError.failed("AI 响应无法解析")
        }
        return content
    }

    /// Anthropic messages API
    private func anthropicChat(base: String, system: String, messages: [Message], maxTokens: Int) async throws -> String {
        var payloadMessages: [[String: Any]] = []
        for m in messages {
            payloadMessages.append(["role": m.role, "content": m.content])
        }
        var req = URLRequest(url: URL(string: "\(base)/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.effectiveModel,
            "max_tokens": maxTokens,
            "system": system,
            "messages": payloadMessages,
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw EngineError.failed("AI 响应异常")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw EngineError.failed("AI 调用失败（HTTP \(http.statusCode)）：\(body.prefix(300))")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw EngineError.failed("AI 响应无法解析")
        }
        return text
    }

    /// 连通性测试：发一句固定话术
    func testConnection() async throws -> String {
        let reply = try await chat(
            system: "你是连通性测试器，只回复：OK",
            messages: [Message(role: "user", content: "ping")],
            maxTokens: 16
        )
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
