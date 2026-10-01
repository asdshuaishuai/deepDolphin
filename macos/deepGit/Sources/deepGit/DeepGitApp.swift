// DeepGitApp.swift — deepGit（macOS 客户端）入口。
//
// 多 Scene 架构（正经 Mac 应用）：
//   Window("panel")          主面板——SwiftUI 管理窗口、工具栏、生命周期
//   MenuBarExtra             菜单栏常驻速览
//   Settings                 标准 ⌘, 设置窗口
//   .commands                中文菜单（操作/窗口）
//
// 深链：--project <名称> / --section milestones|board|dashboard
// 【边界】纯客户端：数据全走引擎 CLI 子进程（EngineCLI），不走网络。
// ⚠️ 原文写的是「数据全走引擎 HTTP API」—— 那条路已随 HTTP 服务端整体删除。
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
                // 双轨动作在这里也有一份 —— 菜单项是 macOS 的惯例入口，
                // 而且 ⇧⌘U / ⌥⇧⌘D 挂在这里**一定有效**（挂在 toolbar 按钮上
                // 虽然也合法，但那是另一套分发路径，不拿它赌）。
                // 两条调的都是 `model.runUpdate(deep:)`，
                // 所以范围、确认框、忙碌判定与顶栏按钮**完全一致**。
                //
                // ⚠️ ⌥⇧⌘D 此前**声明了却从来没绑定**：ShortcutMap.deep 写在表里、
                //    冲突检查也把它算进去，但没有一处 keyboardShortcut 用它 ——
                //    于是 §3.2 要求的「⌥⇧⌘D 深更新」是不存在的功能。
                //    绑了才算数。
                Button(ScopeRules.shallowLabel(model.updateScope)) {
                    model.runUpdate(deep: false)
                }
                .keyboardShortcut(ShortcutMap.shallow.keyEquivalentSwiftUI, modifiers: ShortcutMap.shallow.modifiersSwiftUI)
                .disabled(model.updateScopeBusy)

                Button(ScopeRules.deepLabel(model.updateScope)) {
                    model.runUpdate(deep: true)
                }
                .keyboardShortcut(ShortcutMap.deep.keyEquivalentSwiftUI, modifiers: ShortcutMap.deep.modifiersSwiftUI)
                .disabled(model.updateScopeBusy)

                Divider()

                Button("刷新") {
                    Task { await model.refreshAll() }
                }
                .keyboardShortcut(ShortcutMap.refresh.keyEquivalentSwiftUI, modifiers: ShortcutMap.refresh.modifiersSwiftUI)

                // 停止：不加这个，批量更新一旦开始就只能等 15 分钟。
                // 它终止的是**引擎子进程**，不是只取消 Swift 侧的 Task
                // —— 后者对 Task.detached 里的阻塞调用无效（见 EngineCLI 注释）。
                Button("停止更新") {
                    model.stopUpdate()
                }
                .keyboardShortcut(ShortcutMap.stop.keyEquivalentSwiftUI, modifiers: ShortcutMap.stop.modifiersSwiftUI)
                .disabled(!model.canStopUpdate)
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
                // ⚠️ 原来这里还有 `Task { await model.start() }`，
                // 而 PanelView 的 `.task` 也调 start() —— 首次打开跑两遍全量刷新。
                // 加载与定时器的归属权交给 PanelView（唯一入口）。
                handleLaunchArgs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPanelRequest)) { _ in
                openPanel(id: "panel")
            }
            // 菜单栏「全部浅更新」从这里弹确认：那条路是 CommandMenu（不是 View），
            // 挂不上 .confirmationDialog，所以由主面板代为呈现。
            .confirmationDialog(
                model.pendingBulkUpdate.map { "全部\($0.label)？" } ?? "",
                isPresented: Binding(
                    get: { model.pendingBulkUpdate != nil },
                    set: { if !$0 { model.pendingBulkUpdate = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let track = model.pendingBulkUpdate {
                    Button(DestructiveGuard.confirmTitle(for: .bulkUpdate)) {
                        model.startUpdateAll(deep: track == .deep)
                        model.pendingBulkUpdate = nil
                    }
                }
                Button("取消", role: .cancel) { model.pendingBulkUpdate = nil }
            } message: {
                Text(model.pendingBulkUpdate.map {
                    DestructiveGuard.bulkUpdateMessage(projectCount: model.projects.count, track: $0)
                } ?? "")
            }
    }

    private func handleLaunchArgs() {
        // 解析与判定都在纯函数层（Route.swift / Router.swift）：
        // 深链是纯字符串处理，不该只能靠「手动敲一次命令试试」来验证。
        let intent = Route.parse(ProcessInfo.processInfo.arguments)
        model.launchIntent = intent

        if let route = intent.route {
            // 走 go(_:) 而不是直接赋值 —— 跳到一个不存在的项目要被 Router 拦下，
            // 而项目列表此刻通常还没加载完，Router 会先记下、加载完再判。
            model.go(route)
        }
        if intent.openSettings {
            model.showAISettings = true
        }
        // 无头 agent 自测（README 文档化；mock provider 配 defaults 即可全链路验证）
        if let question = intent.agentSelfTest {
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
