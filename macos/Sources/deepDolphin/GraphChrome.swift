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

    /// 打开（或前置）某个图谱窗口。frame 直接铺满可见工作区 = 最大化。
    @MainActor
    static func open(kind: String, projectName: String, title: String,
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
        if let screen = w.screen ?? NSScreen.main {
            w.setFrame(screen.visibleFrame, display: true)   // 直接最大化
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

    /// 生成架构图：arch gen（写 arch.json，探针对账）+ render arch（落交互 HTML）。
    /// 返回 (成功?, 引擎回执末行)。
    @discardableResult
    static func generateArch(_ project: String) async -> (ok: Bool, receipt: String?) {
        do {
            let r = try await EngineCLI.shared.runData(["arch", "gen", project], timeout: 600)
            let line = lastLine(String(data: r, encoding: .utf8) ?? "")
            let out = try await EngineCLI.shared.runData(["render", "arch", project], timeout: 600)
            return (true, lastLine(String(data: out, encoding: .utf8) ?? "") ?? line)
        } catch {
            return (false, EngineError.userMessage(for: error))
        }
    }

    /// 生成代码图谱：index gen（建库）+ confidence gen（置信度）+ render index。
    /// 置信度一步失败不拦渲染（引擎对缺席置信度恒发「无置信度数据」图例）。
    @discardableResult
    static func generateGraph(_ project: String) async -> (ok: Bool, receipt: String?) {
        do {
            let a = try await EngineCLI.shared.runData(["index", "gen", project], timeout: 600)
            let lineA = lastLine(String(data: a, encoding: .utf8) ?? "")
            var line = lineA
            if let b = try? await EngineCLI.shared.runData(["confidence", "gen", project], timeout: 600) {
                line = lastLine(String(data: b, encoding: .utf8) ?? "") ?? lineA
            }
            let out = try await EngineCLI.shared.runData(
                ["render", "index", project, "--confidence"], timeout: 600)
            return (true, lastLine(String(data: out, encoding: .utf8) ?? "") ?? line)
        } catch {
            return (false, EngineError.userMessage(for: error))
        }
    }

    private static func lastLine(_ text: String) -> String? {
        for line in text.split(separator: "\n").reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return nil
    }
}
