// AgentView.swift — AI 助手（deepDesign 模式的上层 AI 实现）。
//
// 工作方式：
//   1. 从引擎拉上下文包（/api/context，预算内 markdown）+ 工具清单（/api/tools）
//   2. system prompt = 角色说明 + 工具清单 + 上下文
//   3. 模型若需更多数据/要执行动作，回复 {"tool": "...", "params": {...}} JSON；
//      客户端通过引擎 HTTP API 执行后把结果喂回，最多 4 轮
//   4. 模型不再调用工具时，回复即最终答案（Markdown 渲染）
//
// 引擎保持 AI 无关：这里所有智能都在客户端，所有事实与动作都来自引擎。
import SwiftUI

// MARK: - 会话状态

struct AgentMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        case user
        case assistant
        case toolCall(name: String, result: String, ok: Bool)
        case error
    }
    let id: UUID
    var kind: Kind
    var text: String

    init(kind: Kind, text: String) {
        self.id = UUID()
        self.kind = kind
        self.text = text
    }
}

enum AgentTarget: Equatable, Hashable {
    case group
    case project(String)

    var label: String {
        switch self {
        case .group: return "整个项目群"
        case .project(let n): return n
        }
    }
}

@MainActor
final class AgentSession: ObservableObject {
    @Published var messages: [AgentMessage] = []
    @Published var input: String = ""
    @Published var thinking = false
    @Published var target: AgentTarget = .group
    @Published var lastDuration: TimeInterval?

    /// selftest 日志开关
    var logSink: ((String) -> Void)?

    /// 解析模型回复中的工具调用（```json {"tool":...,"params":{...}} ```）
    private func parseToolCall(_ reply: String) -> (name: String, params: [String: Any])? {
        guard let start = reply.range(of: "```json"),
              let end = reply.range(of: "```", range: start.upperBound..<reply.endIndex) else {
            // 也容忍裸 JSON 单行
            let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
                  let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tool = obj["tool"] as? String else { return nil }
            return (tool, obj["params"] as? [String: Any] ?? [:])
        }
        let body = String(reply[start.upperBound..<end.lowerBound])
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = obj["tool"] as? String else { return nil }
        return (tool, obj["params"] as? [String: Any] ?? [:])
    }

    /// 工具名 → 引擎 HTTP 调用。返回 (ok, 摘要文本)
    private func executeTool(_ name: String, params: [String: Any]) async -> (Bool, String) {
        let str = { (key: String) in params[key] as? String ?? "" }
        do {
            switch name {
            case "get_group_context", "get_project_context", "get_project_docs", "get_journal", "get_milestones":
                var path = ""
                var query: [String: String] = [:]
                switch name {
                case "get_group_context":
                    path = "api/context"; query = ["scope": "group", "budget": "8000"]
                case "get_project_context":
                    path = "api/context"; query = ["scope": "project", "name": str("name")]
                case "get_project_docs":
                    path = "api/docs"; query = ["name": str("name")]
                case "get_journal":
                    path = "api/journal"; query = ["name": str("name")]
                default:
                    path = "api/milestones"
                }
                let data = try await rawGet(path, query: query)
                return (true, String(data: data, encoding: .utf8) ?? "")
            case "run_shallow_update":
                let data = try await APIClient.shared.post("api/update", query: ["name": str("name")])
                return (true, String(data: data, encoding: .utf8) ?? "完成")
            case "run_deep_update":
                let data = try await APIClient.shared.post("api/deep", query: ["name": str("name")])
                return (true, String(data: data, encoding: .utf8) ?? "完成")
            case "git_commit":
                let data = try await APIClient.shared.post(
                    "api/git",
                    body: ["project": str("name"), "op": "commit", "message": str("message")]
                )
                return (true, String(data: data, encoding: .utf8) ?? "完成")
            case "git_pull_push":
                let data = try await APIClient.shared.post(
                    "api/git",
                    body: ["project": str("name"), "op": str("op").isEmpty ? "pull" : str("op")]
                )
                return (true, String(data: data, encoding: .utf8) ?? "完成")
            case "milestone_done":
                let data = try await APIClient.shared.post(
                    "api/milestones/action",
                    body: ["project": str("project"), "name": str("name"), "action": "done"]
                )
                return (true, String(data: data, encoding: .utf8) ?? "完成")
            default:
                return (false, "未知工具：\(name)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// GET 原始数据（工具结果原样喂给模型）
    private func rawGet(_ path: String, query: [String: String]) async throws -> Data {
        var comps = URLComponents(
            url: URL(string: "http://127.0.0.1:\(DeepGitEngine.shared.serverPort)")!.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let (data, resp) = try await URLSession.shared.data(for: URLRequest(url: comps.url!))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw EngineError.failed("GET \(path) 失败")
        }
        return data
    }

    /// 上下文包 + 工具清单 → system prompt
    private func buildSystemPrompt(toolsManifest: String) -> String {
        let scopeLine: String
        switch target {
        case .group: scopeLine = "scope=group（整个项目群）"
        case .project(let n): scopeLine = "scope=project&name=\(n)（项目 \(n)）"
        }
        return """
        你是 deepGit 项目群管理助手。引擎（AI 无关内核）已经把当前范围的确定性事实整理给你。

        ## 当前上下文
        用户关注的范围：\(scopeLine)
        引擎端点：http://127.0.0.1:\(DeepGitEngine.shared.serverPort)

        ## 可用工具（通过回复 JSON 调用）
        \(toolsManifest)

        ## 调用规则
        - 需要更多数据或要执行动作时，只回复一个 JSON 代码块：
          ```json
          {"tool": "工具名", "params": {"参数名": "值"}}
          ```
        - 引擎会把工具结果作为新的用户消息给你；拿到足够信息后，用 Markdown 给出最终中文回答
        - 最终回答要具体：点名项目/分支，给可执行建议；不编造上下文里没有的事实
        """
    }

    func send() async {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !thinking else { return }
        input = ""
        await ask(question)
    }

    /// 可编程入口：--agent-selftest 无头验证用（与 send 共享全链路）
    func ask(_ question: String) async {
        thinking = true
        let startedAt = Date()
        defer { thinking = false }

        guard AIConfig.load().isConfigured else {
            messages.append(AgentMessage(kind: .error, text: "AI 未配置：右上角 ⚙️ 填写 provider 与 API Key"))
            return
        }

        messages.append(AgentMessage(kind: .user, text: question))
        logSink?("USER: \(question)")

        do {
            // 上下文 + 工具清单
            let scopePath: String
            let scopeQuery: [String: String]
            switch target {
            case .group:
                scopePath = "api/context"; scopeQuery = ["scope": "group", "budget": "9000"]
            case .project(let n):
                scopePath = "api/context"; scopeQuery = ["scope": "project", "name": n, "budget": "9000"]
            }
            let ctxData = try await rawGet(scopePath, query: scopeQuery)
            let ctxObj = try JSONSerialization.jsonObject(with: ctxData) as? [String: Any]
            let context = ctxObj?["context"] as? String ?? ""
            let toolsData = try await rawGet("api/tools", query: [:])
            let toolsText = String(data: toolsData, encoding: .utf8) ?? "{}"

            let provider = AIProvider(config: AIConfig.load())
            let system = buildSystemPrompt(toolsManifest: toolsText)
                + "\n\n## 当前范围事实（引擎生成）\n\n" + context

            var convo: [AIProvider.Message] = [AIProvider.Message(role: "user", content: question)]

            // 工具循环（≤4 轮）
            for round in 1...4 {
                let reply = try await provider.chat(system: system, messages: convo)
                if let call = parseToolCall(reply) {
                    messages.append(AgentMessage(kind: .assistant, text: "🔧 调用工具 `\(call.name)`"))
                    logSink?("TOOL_CALL: \(call.name) params=\(call.params)")
                    let (ok, result) = await executeTool(call.name, params: call.params)
                    let clipped = result.count > 16000 ? String(result.prefix(16000)) + "\n…(截断)" : result
                    messages.append(AgentMessage(kind: .toolCall(name: call.name, result: clipped, ok: ok), text: clipped))
                    convo.append(AIProvider.Message(role: "assistant", content: reply))
                    convo.append(AIProvider.Message(
                        role: "user",
                        content: "工具 \(call.name) 执行\(ok ? "成功" : "失败")，结果：\n\(clipped)\n\n请继续。"
                    ))
                } else {
                    messages.append(AgentMessage(kind: .assistant, text: reply))
                    logSink?("FINAL: \(reply.prefix(200))")
                    break
                }
                if round == 4 {
                    messages.append(AgentMessage(kind: .error, text: "已达工具调用轮次上限（4），请拆分问题或直接提问"))
                }
            }
            lastDuration = Date().timeIntervalSince(startedAt)
        } catch {
            messages.append(AgentMessage(kind: .error, text: error.localizedDescription))
        }
    }
}

// MARK: - 视图

struct AgentView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var session = AgentSession()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            targetBar
            Divider()
            chatList
            Divider()
            inputBar
        }
        .navigationTitle("AI 助手")
    }

    private var targetBar: some View {
        HStack(spacing: 10) {
            Picker("范围", selection: $session.target) {
                Text("整个项目群").tag(AgentTarget.group)
                ForEach(model.projects) { p in
                    Text(p.name).tag(AgentTarget.project(p.name))
                }
            }
            .frame(width: 260)
            Spacer()
            if session.thinking {
                ProgressView().controlSize(.small)
                Text("思考中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let d = session.lastDuration {
                Text(String(format: "%.1fs", d))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("AI 设置")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if session.messages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("问问你的项目群")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("例如：「哪些分支该合并了？」、「deepOffice 最近在做什么？」、「给 rust 项目提交未提交改动」")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                    ForEach(session.messages) { m in
                        MessageBubble(message: m).id(m.id)
                    }
                }
                .padding(14)
            }
            .onChange(of: session.messages.count) { _ in
                if let last = session.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("询问项目群…（Enter 发送）", text: $session.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { Task { await session.send() } }
            Button {
                Task { await session.send() }
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(session.input.trimmingCharacters(in: .whitespaces).isEmpty || session.thinking)
        }
        .padding(10)
    }
}

struct MessageBubble: View {
    let message: AgentMessage

    var body: some View {
        switch message.kind {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    MarkdownView(text: message.text)
                }
                Spacer(minLength: 30)
            }
        case .toolCall(let name, let result, let ok):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ok ? Color.green : Color.red)
                        .font(.caption)
                    Text("工具 \(name)")
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                ScrollView {
                    Text(result)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        case .error:
            Label(message.text, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.callout)
        }
    }
}
