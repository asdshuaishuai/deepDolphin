// DeepGitApp.swift — deepGit（macOS 客户端）入口。
//
// 双形态系统集成：
//   1. MenuBarExtra（.window 富弹窗）——常驻菜单栏速览 + 快捷动作
//   2. 主面板窗口（NSWindow + PanelView）——完整项目管理面板
//      打开方式：菜单栏「打开面板」、项目行点击、或 `deepGit --open-panel`
//      深链：--project <名称> / --section milestones|dashboard
//
// 【边界】纯客户端：数据全走引擎 HTTP API（GET /api/*），
// 写操作 POST 给引擎（/api/update|deep|git|milestones*）。
// 引擎未运行时按发现链拉起（DEEPGIT_BIN → 内嵌副本 → ~/.local/bin → shell PATH）。
import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.setUp()
        Notifier.shared.onOpenPanel = {
            PanelWindowController.shared.open(model: AppModel.shared)
        }
        Task { await AppModel.shared.start() }

        let args = ProcessInfo.processInfo.arguments
        if args.contains("--bar-preview") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                PanelWindowController.shared.openBarPreview(model: AppModel.shared)
            }
            return
        }
        if let i = args.firstIndex(of: "--agent-selftest"), i + 1 < args.count {
            let question = args[i + 1]
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                _ = await AppModel.shared.ensureReady()
                let session = AgentSession()
                session.logSink = { msg in print("[selftest] \(msg)") }
                await session.ask(question)
                for m in session.messages {
                    let tag: String
                    switch m.kind {
                    case .user: tag = "user"
                    case .assistant: tag = "assistant"
                    case .toolCall(let n, _, let ok): tag = "tool(\(n),ok=\(ok))"
                    case .error: tag = "error"
                    }
                    print("[selftest-msg] \(tag): \(m.text.prefix(120).replacingOccurrences(of: "\n", with: " "))")
                }
                print("[selftest-done]")
                Foundation.exit(0)
            }
            return
        }
        if args.contains("--open-panel") {
            var section: RootSection?
            if let i = args.firstIndex(of: "--project"), i + 1 < args.count {
                section = .project(args[i + 1])
            } else if let i = args.firstIndex(of: "--section"), i + 1 < args.count {
                switch args[i + 1] {
                case "milestones": section = .milestones
                case "board": section = .board
                default: section = .dashboard
                }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                if let s = section {
                    AppModel.shared.selection = s
                }
                PanelWindowController.shared.open(model: AppModel.shared)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
        DeepGitEngine.shared.stopServerIfOurs()
    }

    // Dock 右键菜单：系统集成速捷入口
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let open = NSMenuItem(title: "打开面板", action: #selector(openPanelFromDock), keyEquivalent: "")
        menu.addItem(open)
        let update = NSMenuItem(title: "全部浅更新", action: #selector(shallowAllFromDock), keyEquivalent: "")
        menu.addItem(update)
        return menu
    }

    @objc func openPanelFromDock() {
        PanelWindowController.shared.open(model: AppModel.shared)
    }

    @objc func shallowAllFromDock() {
        Task { await AppModel.shared.updateAll(deep: false) }
    }
}

@main
struct DeepGitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        // 菜单栏速览入口（.window 风格富弹窗）
        MenuBarExtra {
            BarView()
                .environmentObject(model)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: model.menuSymbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(menuTint)
                Text(model.menuTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuTint: Color {
        switch model.menuTint {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        default: return .secondary
        }
    }
}
