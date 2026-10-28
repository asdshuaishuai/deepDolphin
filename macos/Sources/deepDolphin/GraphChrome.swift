// GraphChrome.swift — 图谱两页（架构图/代码图谱）的呈现层公共件。
//
// 用户定稿 2026-10-27：两图打开时**直接最大化显示**，不局限在主面板内——
// 用独立 NSWindow（NSHostingView 承载 SwiftUI 页面），打开即铺满工作区，
// 同一仓库同一图已开窗就前置（不开重窗）。
//
// 头部/状态栏两件公共 UI：两页共用同一套结构（图标瓦片 + 标题 + 动作区 /
// 底部回执条），视觉只在图标与文案上区分——同一产品的两个页面长得像同一家。
import SwiftUI
import AppKit

// MARK: - 独立窗口（最大化打开）

enum GraphWindows {
    /// 存活窗口登记（key = "<kind>:<project>"）。窗口被用户关掉后条目仍可能
    /// 残留（isReleasedWhenClosed=false），前置前用 isVisible 校验。
    private static var live: [String: NSWindow] = [:]

    /// 供 GraphAgentTask 等特殊窗口（尺寸策略不同）复用同一张登记表。
    static func register(key: String, window: NSWindow) {
        live[key] = window
    }

    static func liveWindow(_ key: String) -> NSWindow? {
        live[key]
    }

    /// 打开（或前置）某个图谱窗口。frame 直接铺满可见工作区 = 最大化。
    @MainActor
    static func open(kind: String, projectName: String, title: String,
                     maximize: Bool = true,
                     @ViewBuilder view: () -> some View) {
        let key = "\(kind):\(projectName)"
        NSApp.activate(ignoringOtherApps: true)
        if let w = live[key], w.isVisible {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 960, height: 640)
        w.contentView = NSHostingView(rootView: view())
        w.center()
        // 用户定稿：图谱窗口打开直接铺满工作区；对话窗口按内容尺寸居中
        if maximize, let screen = w.screen ?? NSScreen.main {
            w.setFrame(screen.visibleFrame, display: true)
        }
        w.makeKeyAndOrderFront(nil)
        live[key] = w
    }
}

// MARK: - 头部（图标瓦片 + 标题 + 动作区）

struct GraphHeaderView: View {
    @ObservedObject private var l10n = L10n.shared
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    /// 生成按钮（带文字；nil = 本页没有生成动作）
    let generateTitle: String?
    var onGenerate: (() -> Void)?
    let generating: Bool
    var onRefresh: () -> Void
    let refreshing: Bool
    var onOpenExternal: (() -> Void)?
    let canOpenExternal: Bool

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            // 图标瓦片：圆角方块 + 白色符号，同一产品两个页面的视觉锚
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: DSRect.shape(DSRadius.control))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let t = generateTitle, let f = onGenerate {
                Button(action: f) {
                    Label(t, systemImage: "wand.and.stars")
                }
                .disabled(generating || refreshing)
                .help(t)
                .accessibilityLabel(A11y.label(t))
            }
            Button(action: onRefresh) {
                if refreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(refreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help(L10n.t("cgraph.reload"))
            .accessibilityLabel(A11y.label(L10n.t("cgraph.reload")))
            if let f = onOpenExternal {
                Button(action: f) {
                    Image(systemName: "safari")
                }
                .disabled(!canOpenExternal)
                .help(L10n.t("graph.openExternal"))
                .accessibilityLabel(A11y.label(L10n.t("graph.openExternal")))
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
    }
}

// MARK: - 底部回执条（引擎回执 / 错误）

struct GraphStatusBar: View {
    /// (ok, 文案)；nil = 不占高度
    let message: (ok: Bool, text: String)?
    var onDismiss: (() -> Void)?

    var body: some View {
        if let m = message {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: m.ok ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(m.ok ? Color.green : .orange)
                    .font(.caption)
                Text(m.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(m.ok ? DSColor.textSecondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                if let f = onDismiss {
                    Button(action: f) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.t("gitop.clearOutput"))
                    .accessibilityLabel(A11y.label(L10n.t("gitop.clearOutput")))
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.xs)
            .background(m.ok ? Color.clear : Color.orange.opacity(0.08))
        }
    }
}

// MARK: - 内容区加载态（首次渲染时的居中提示）

struct GraphLoadingHint: View {
    let text: String

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            ProgressView()
                .controlSize(.regular)
            Text(text)
                .font(.callout)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 图谱产物（探测/生成的唯一构造点）

@MainActor
enum GraphArtifact {
    /// 产物是否已生成。引擎 `render check` **只探测不自愈**（自愈可能触发
    /// 整库重建，分钟级——「看一眼按钮该亮哪个」付不起这个代价）。
    /// 探测失败（旧引擎没有这个子命令 / 进程错误）按「未生成」处理：
    /// 按钮退到生成形态，点生成走 render 照样能打开，不会把路堵死。
    static func exists(_ project: String, kind: String) async -> Bool {
        guard let data = try? await EngineCLI.shared.runData(
            ["render", "check", kind, project, "--json"], timeout: 60),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return (obj["exists"] as? Bool) ?? false
    }

    // ⚠️ 2026-10-28 删除了直出的 generateArch/generateGraph：生成改由
    // agent 播种引擎 skill 工作流驱动（GraphAgentTask）——引擎 AI 无关，
    // 编排归 LLM；确定性命令仍由 agent 的引擎工具执行，只是不再由 GUI 静默直出。

    private static func lastLine(_ text: String) -> String? {
        for line in text.split(separator: "\n").reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return nil
    }
}

// MARK: - LLM 驱动的图谱生成（用户定稿 2026-10-28：生成必须走 agent）
//
// 引擎提供 `moongit skill graph`（生成工作流 playbook，唯一来源），
// 客户端把 playbook + 目标仓库播种给 agent——agent 用它的引擎工具
// （index gen / confidence gen / confidence query / render / arch gen /
// graph arch --json …）执行工作流并向用户报告治理信号。
// 客户端不再直接调生成管线；探测（render check）仍是本地毫秒级只读。

@MainActor
enum GraphAgentTask {
    /// 引擎工作流文本的进程内缓存（同一会话只取一次）。
    private static var cachedSkill: String?

    private static func skillText() async -> String {
        if let c = cachedSkill { return c }
        let text = (try? await EngineCLI.shared.runData(["skill", "graph"], timeout: 60))
            .flatMap { String(data: $0, encoding: .utf8) }
        // 取不到（旧引擎没有该子命令）也要给 agent 一句可执行的最低指令，
        // 不能把 nil 播种成空任务。
        let fallback = "用引擎 CLI 为目标仓库生成交付物：index gen / confidence gen / render index --confidence，或 arch gen / render arch；用 render check 验证产物，报告路径与治理信号。"
        let v = text ?? fallback
        cachedSkill = v
        return v
    }

    /// 播种任务 = 引擎工作流 + 目标仓库 + 本次交付物 + 期望的报告。
    static func task(project: String, kind: String) async -> String {
        let skill = await skillText()
        let what = kind == "arch"
            ? "交付物 B——架构图（render/arch.html）"
            : "交付物 A——代码图谱 / 置信度热力图（render/index.html）"
        return skill + "\n---\n目标仓库：\(project)\n本次要生成：\(what)\n完成后报告：产物路径 + 治理信号（违规/环/职责违规）。"
    }

    /// 打开独立 agent 窗口执行任务（不最大化：对话窗口按内容尺寸居中）。
    /// 窗口关闭时回调 onClose——调用方借此重探产物、替换生成/打开按钮。
    @discardableResult
    static func launch(project: String, kind: String, onClose: (() -> Void)? = nil) async -> NSWindow {
        let full = await task(project: project, kind: kind)
        let key = "agent-\(kind):\(project)"
        NSApp.activate(ignoringOtherApps: true)
        if let w = GraphWindows.liveWindow(key), w.isVisible {
            w.makeKeyAndOrderFront(nil)
            return w
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        w.title = "AI 生成 · \(project)"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: AgentView(target: .project(project), initialTask: full))
        w.center()
        w.makeKeyAndOrderFront(nil)
        GraphWindows.register(key: key, window: w)
        if let onClose {
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main) { note in
                if (note.object as? NSWindow) === w { onClose() }
            }
        }
        return w
    }
}
