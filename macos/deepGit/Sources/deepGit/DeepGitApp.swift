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
            CommandGroup(after: .appInfo) {
                Button("设置…") {
                    AppModel.shared.showAISettings = true
                }
                .keyboardShortcut(",")
            }
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
    }
}
