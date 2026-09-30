// DeepGitApp.swift — deepGit（macOS 客户端）入口。
//
// 多 Scene 架构（正经 Mac 应用）：
//   Window("panel")          主面板——SwiftUI 管理窗口、工具栏、生命周期
//   MenuBarExtra             菜单栏常驻速览
//   Settings                 标准 ⌘, 设置窗口
//   .commands                中文菜单（操作/窗口）
//
// 深链：--project <名称> / --section milestones|board|dashboard
// 【边界】纯客户端：数据全走引擎 HTTP API。
import SwiftUI
import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.setUp()
        // 通知点击 → 打开/激活主面板（NSApp.windows 兜底：窗口被关也能找回）
        Notifier.shared.onOpenPanel = {
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.title == "deepGit" {
                w.makeKeyAndOrderFront(nil)
                return
            }
            // 窗口已销毁：由 SwiftUI Window scene 的 openWindow 兜底（通知中心转发）
            NotificationCenter.default.post(name: .openPanelRequest, object: nil)
        }
    }

    func requestFullQuit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }
}

@main
struct DeepGitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared
    @Environment(\.openWindow) private var openWindow

    init() {
        // 深链参数在首次 UI 出现时处理（onAppear 在 DeepGitPanel）
    }

    var body: some Scene {
        // 主面板窗口（启动自动打开）
        Window("deepGit", id: "panel") {
            DeepGitPanel()
                .environmentObject(model)
                        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("操作") {
                Button("刷新") {
                    Task { await model.refreshAll() }
                }
                .keyboardShortcut("r")
                Divider()
                Button("全部浅更新") {
                    Task { await model.updateAll(deep: false) }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }

        // 菜单栏速览
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

        // 标准 ⌘, 设置
        Settings {
            GeneralSettingsView()
                .environmentObject(model)
        }
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

/// 面板窗口根视图（处理深链参数 + 生命周期）
struct DeepGitPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openPanel

    var body: some View {
        PanelView()
            .onAppear {
                Notifier.shared.setUp()
                Task { await model.start() }
                handleLaunchArgs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPanelRequest)) { _ in
                openPanel(id: "panel")
            }
    }

    private func handleLaunchArgs() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--open-panel") || args.contains("--open-settings") else { return }
        if let i = args.firstIndex(of: "--project"), i + 1 < args.count {
            model.selection = .project(args[i + 1])
        } else if let i = args.firstIndex(of: "--section"), i + 1 < args.count {
            switch args[i + 1] {
            case "milestones": model.selection = .milestones
            case "board": model.selection = .board
            default: model.selection = .dashboard
            }
        }
        if args.contains("--open-settings") {
            model.showAISettings = true
        }
        // 无头 agent 自测（README 文档化；mock provider 配 defaults 即可全链路验证）
        if let i = args.firstIndex(of: "--agent-selftest") {
            let question = (i + 1 < args.count) ? args[i + 1] : "总结一下项目群现状"
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                do {
                    let answer = try await AgentCore.run(question: question, target: .group)
                    print("[selftest] FINAL: \(answer.prefix(200))")
                } catch {
                    print("[selftest] ERROR: \(error.localizedDescription)")
                }
                print("[selftest-done]")
            }
        }
    }
}
