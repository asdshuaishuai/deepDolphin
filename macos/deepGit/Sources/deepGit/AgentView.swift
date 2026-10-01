// AgentView.swift — 与 AI 的多轮对话（P0-5）。
//
// 之前 app 里根本没有对话界面：AI 只能出**一次性**结果（项目说明 / 更新摘要 /
// 简报），弹一个 AIResultSheet 就没有下文了。用户想追问只能关掉重来，
// 而 AgentCore.run 每次从零起步，于是"那刚才那个项目呢"这类问题无解。
//
// 这一屏的骨架：会话状态（历史）+ 输入 + 发送/停止 + 过程事件。
// 判定全在 AgentConversation（纯函数、可测），这里只负责呈现与调度。
import SwiftUI

@MainActor
final class AgentChatModel: ObservableObject {
    /// 内部消息历史（含 tool 往返），发给模型的那一份。
    @Published private(set) var history: [ChatMessage] = []
    @Published private(set) var busy = false
    @Published private(set) var cancelled = false
    @Published private(set) var errorText: String?
    /// 工具调用的过程事件，正在跑的时候显示。
    @Published private(set) var events: [String] = []

    let target: AgentTarget
    /// 只读快照：AI 配置在设置里改，这一屏按需读，不缓存。
    var isConfigured: Bool { AIConfig.load().isConfigured }

    private var work: Task<Void, Never>?

    init(target: AgentTarget) { self.target = target }

    var transcript: [TranscriptEntry] {
        Conversation.transcript(from: history)
    }

    var sendDecision: Conversation.SendDecision {
        Conversation.canSend(draft, isBusy: busy, isConfigured: isConfigured)
    }
    var canStop: Bool { Conversation.canStop(isBusy: busy, isCancelled: cancelled) }

    /// 输入框内容放在视图里，这里只是个转发位 —— 判定需要它。
    var draft: String = "" {
        didSet { objectWillChange.send() }
    }

    func send() {
        guard case .allowed(let text) = sendDecision else { return }
        draft = ""
        busy = true
        cancelled = false
        errorText = nil
        events = []
        let before = history
        work?.cancel()
        work = Task {
            defer { busy = false; events = [] }
            do {
                let updated = try await AgentCore.run(
                    question: text,
                    target: target,
                    history: before,
                    onEvent: { [weak self] ev in self?.events.append(ev) }
                )
                guard !Task.isCancelled else { return }
                history = updated
            } catch is CancellationError {
                cancelled = true
            } catch {
                guard !Task.isCancelled else { return }
                // 失败时把**已发出的那条提问**留回去：否则用户的问题凭空消失，
                // 而他还得凭记忆重新打一遍。
                history = before + [ChatMessage.user(text)]
                errorText = EngineError.userMessage(for: error)
            }
        }
    }

    /// 停止：取消 Task。
    ///
    /// 原来没有任何地方能停。一轮 agent 里 `run_shallow_update` 超时设的是
    /// 300 秒、`deep` 是 600 秒 —— 用户只能干等，而关窗也停不掉后台的 Task。
    /// 注意取消的是**Swift 侧的等待**；已经 spawn 出去的引擎子进程
    /// 由 EngineCLI 的超时兜底收尾（见 AGENTS.md 里 execCapture 的已知限制）。
    func stop() {
        guard canStop else { return }
        cancelled = true
        work?.cancel()
        work = nil
    }

    func clear() {
        work?.cancel()
        work = nil
        history = []
        events = []
        errorText = nil
        cancelled = false
        busy = false
    }

    deinit { work?.cancel() }
}

struct AgentView: View {
    @StateObject private var chat: AgentChatModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    init(target: AgentTarget) {
        // StateObject 的初值只在这一处被求值，必须先拿到实例再包起来。
        _chat = StateObject(wrappedValue: AgentChatModel(target: target))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcriptView
            if let err = chat.errorText {
                errorBanner(err)
            }
            Divider()
            inputBar
        }
        .frame(width: 720, height: 620)
        .onAppear { inputFocused = true }
        .onDisappear { chat.stop() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            Text("AI 助手 · \(chat.target.label)")
                .font(.headline)
            Spacer()
            Button {
                chat.clear()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("清空对话")
            .accessibilityLabel(A11y.label("清空对话"))
            .disabled(chat.history.isEmpty)

            Button {
                // 有历史时先停、再关：否则关窗后 agent 还在后台跑，
                // 跑完还会往一个已经不存在的界面上写状态。
                chat.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("关闭")
            .accessibilityLabel(A11y.label("关闭"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DSSpacing.md) {
                    if chat.history.isEmpty {
                        emptyHint
                    }
                    ForEach(chat.transcript) { e in
                        bubble(e).id(e.id)
                    }
                    if !chat.events.isEmpty {
                        ForEach(Array(chat.events.enumerated()), id: \.offset) { _, ev in
                            Text(ev)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if chat.busy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(chat.cancelled ? "正在停止…" : "AI 正在思考…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: chat.history.count) { _, _ in
                if let last = chat.transcript.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("可以问：")
                .font(.headline)
            ForEach(chat.target == .group ? groupSamples : projectSamples, id: \.self) { s in
                Button {
                    chat.draft = s
                    chat.send()
                } label: {
                    Text(s).foregroundStyle(.link)
                }
                .buttonStyle(.plain)
                .disabled(!chat.isConfigured)
            }
            if !chat.isConfigured {
                Text("AI 尚未配置 —— 先到 AI 设置里选 provider 并填 API Key。")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var groupSamples: [String] {
        ["哪些项目有未提交改动？", "最近一周哪些项目停滞了？", "按里程碑汇总一下当前进度。"]
    }
    private var projectSamples: [String] {
        ["这个项目现在什么状态？", "有哪些未完成的里程碑？", "跑一次浅更新并总结变化。"]
    }

    @ViewBuilder
    private func bubble(_ e: TranscriptEntry) -> some View {
        switch e.kind {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(e.text)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: DSRadius.card))
            }
        case .assistant:
            MarkdownView(text: e.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .note:
            Label(e.text, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func errorBanner(_ err: String) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            Text(err).font(.caption).foregroundStyle(.red)
            Spacer()
            Button {
                // 失败后重发**同一条**：草稿已经被清空了，
                // 让用户重新打一遍是在惩罚他。
                if let last = chat.history.last, last.role == "user" {
                    chat.draft = last.text
                    chat.send()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("重发上一条")
            .accessibilityLabel(A11y.label("重发上一条"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: DSSpacing.sm) {
            TextField("问点什么…（⌘↩ 发送）", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { chat.send() }

            if chat.canStop {
                Button {
                    chat.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("停止")
                .accessibilityLabel(A11y.label("停止"))
            }

            Button {
                chat.send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!chat.sendDecision.isAllowed)
            .help(sendHelp)
            .accessibilityLabel(A11y.label(fromHelp: sendHelp, fallback: "发送"))
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
    }

    /// 按钮灰着的时候要说为什么，否则用户只能猜。
    private var sendHelp: String {
        switch chat.sendDecision {
        case .allowed: return "发送"
        case .blocked(.empty): return "先输入内容"
        case .blocked(.notConfigured): return "AI 未配置 —— 先到 AI 设置填写"
        case .blocked(.busy): return "正在回答上一条"
        }
    }
}
