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

@MainActor
final class AgentSession: ObservableObject {
    @Published var messages: [AgentMessage] = []
    @Published var input: String = ""
    @Published var thinking = false
    @Published var target: AgentTarget = .group
    @Published var lastDuration: TimeInterval?

    /// selftest 日志开关
    var logSink: ((String) -> Void)?
    /// 无头自测直接注入配置（不走 UserDefaults）
    var overrideConfig: AIConfig?

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
            let final = try await AgentCore.run(
                question: question,
                target: target,
                config: overrideConfig,
                onEvent: { [weak self] event in
                    Task { @MainActor in
                        if event.hasPrefix("🔧") {
                            self?.messages.append(AgentMessage(kind: .assistant, text: event))
                        }
                    }
                }
            )
            messages.append(AgentMessage(kind: .assistant, text: final))
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
