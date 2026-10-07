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

/// 主面板窗口的**唯一出处**。
///
/// ⚠️ 原来标题字面量散在 4 处，而其中 2 处**判的字符串根本不会成立**：
///     · `Window("deepDolphin", id: "panel")`     —— 场景的初始标题
///     · `PanelView` 的 `.navigationTitle("deepDolphin 面板")` —— 实际生效的标题
///     · `AppDelegate.openPanel()` 的 `w.title == "deepGit"`
///     · `DockMenuTarget.openPanel()` 的 `w.title == "deepGit"`
///
/// `NSApp.windows[i].title` 取的是**导航标题**，也就是 `.navigationTitle`
/// 覆盖之后的那个值（真 app 的 AX 窗口名读到的正是「deepGit 面板」）。
/// ⇒ 后面那两处比较**永不成立**，「窗口已经开着就直接 focus」的快路径
/// 从来没跑过，每次都落到后面的通知转发。
///
/// 功能**没坏**（`openWindow(id: "panel")` 同样会把已开的窗口带到前面），
/// 但注释里写着「NSApp.windows 兜底」的那条其实才是唯一在跑的一条 ——
/// 与本项目反复修过的「声明了 dismiss 却一次没用」是同一族。
/// 顺带把两段逐字重复的「叫醒面板」也收了（原来 AppDelegate 与
/// DockMenuTarget 各抄一份，改一处忘另一处必然发生）。
enum PanelWindow {
    /// 窗口标题。`Window(...)` 与 `.navigationTitle(...)` 都用它。
    static let title = "deepDolphin"

    /// 这扇窗是不是主面板。
    ///
    /// 只认 `title` 那**一个**出处 —— 写第二份字面量就是等着它漂移。
    static func isPanel(_ window: NSWindow) -> Bool {
        window.title == title
    }

    /// 叫醒主面板。**Dock 菜单、通知点击、菜单栏三处共用这一条路。**
    ///
    /// 先找已存在的窗口并前置；找不到（首次启动 / 窗口被销毁）才发通知，
    /// 由 SwiftUI 场景的 `openWindow` 兜底创建。
    @MainActor
    static func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let panel = NSApp.windows.first(where: isPanel) {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        NotificationCenter.default.post(name: .openPanelRequest, object: nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Dock 右键菜单的动作接收者。
    ///
    /// ⚠️ 不能直接用 `AppDelegate` 自己当 target：它是 `NSObject`（不是
    /// `NSResponder`），**不在 responder chain 里**，而 `NSMenuItem.target`
    /// 留空时只会在 chain 里找 —— 菜单项会灰着点不动。
    /// 也正因为 target 是弱引用，得由 AppDelegate 强持有它
    /// （AppDelegate 的生命周期 = app 的生命周期，够长）。
    private lazy var dockTarget = DockMenuTarget()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.setUp()
        // 通知点击 → 打开/激活主面板（NSApp.windows 兜底：窗口被关也能找回）
        Notifier.shared.onOpenPanel = { [weak self] in
            self?.openPanel()
        }
    }

    /// 打开或激活主面板。通知点击与 Dock 菜单共用这一条路。
    ///
    /// 实现已收进 `PanelWindow.bringToFront()`：原来这里和 `DockMenuTarget`
    /// 各抄了一份逐字相同的「activate → 找同名窗口 → 前置 → 否则发通知」。
    ///
    /// ⚠️ 用 `MainActor.assumeIsolated` 而不是把整个方法标 `@MainActor`：
    /// `applicationDidFinishLaunching` 与 `NSMenuItem` 的 action 回调
    /// 都不是 `@MainActor` 隔离的，而 `bringToFront()` 是。
    /// 理由与 `buildDockMenu` / `shallowUpdateAll` 完全相同：
    /// 这些回调**必在主线程**（AppKit 的 delegate 与 action 都在主线程），
    /// `assumeIsolated` 在非主线程会直接断言，正好是「别这么用」的提示。
    func openPanel() {
        MainActor.assumeIsolated { PanelWindow.bringToFront() }
    }

    /// Dock 图标右键菜单（README 声明过，此前**完全没实现**）。
    ///
    /// 只做两件最常做的事：打开面板、全部浅更新。
    /// 刻意不放更多 —— Dock 菜单在 macOS 里的定位就是「高频动作的快捷入口」，
    /// 完整动作表在应用内「操作」菜单里。
    ///
    /// ⚠️ `AppModel` 是 `@MainActor` 隔离的，而 NSApplicationDelegate 协议方法
    /// 不是。这里用 `MainActor.assumeIsolated` 而不是 `Task { @MainActor in }`：
    /// 返回值是**同步**的 `NSMenu`，不能 await；而菜单项的 target / isEnabled
    /// 本来就只能在主线程设置。AppKit 的 delegate 回调必在主线程，所以这个
    /// 假设成立（`assumeIsolated` 在非主线程会直接断言，正好是"别这么用"的提示）。
    func applicationDockMenu(_ sender: NSMenu) -> NSMenu? {
        MainActor.assumeIsolated { buildDockMenu() }
    }

    @MainActor
    private func buildDockMenu() -> NSMenu? {
        let model = AppModel.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(title: "打开面板", action: #selector(DockMenuTarget.openPanel), keyEquivalent: "")
        open.target = dockTarget
        menu.addItem(open)

        // 「全部浅更新」是**破坏性动作**（会写文件），所以只设 pending，
        // 由主面板的 confirmationDialog 呈现确认 —— 不在这里直接开跑。
        // ⚠️ 而且必须先叫醒面板：确认框挂在面板上，窗口没开就没人呈现它，
        // 用户点了会以为「点了没反应」。
        let shallow = NSMenuItem(title: "全部浅更新", action: #selector(DockMenuTarget.shallowUpdateAll), keyEquivalent: "")
        shallow.target = dockTarget
        shallow.isEnabled = !model.updateScopeBusy
        menu.addItem(shallow)

        return menu
    }

    func requestFullQuit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }
}

/// Dock 菜单的 action 接收者（`@objc` 方法必须挂在一个 NSObject 上）。
private final class DockMenuTarget: NSObject {
    /// 与 `AppDelegate.openPanel()` **同一个实现**（`PanelWindow.bringToFront`）——
    /// 原来这里抄了一份逐字相同的实现，两处各改各的，早晚会分叉。
    /// `assumeIsolated` 的理由同上（action 回调必在主线程）。
    @objc func openPanel() {
        MainActor.assumeIsolated { PanelWindow.bringToFront() }
    }

    @objc func shallowUpdateAll() {
        // 同 applicationDockMenu：AppModel 是 @MainActor 隔离的，
        // 而 NSMenuItem 的 action 回调是同步的非隔离上下文。
        MainActor.assumeIsolated {
            AppModel.shared.requestBulkUpdate(deep: false)
        }
        // 确认框挂在主面板上，面板没开就没人呈现它 ⇒ 先叫醒
        openPanel()
    }
}

// ⚠️ 离屏渲染 harness（scripts/render-harness/）要自己当 @main，
// 于是这里整块用条件编译屏蔽。屏蔽的是 **@main 入口**，不是视图 ——
// DeepGitPanel 在下面，harness 照样能用它渲染截图。
#if !DEEPGIT_RENDER_HARNESS
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
        Window(PanelWindow.title, id: "panel") {
            DeepGitPanel()
                .environmentObject(model)
                        }
        .defaultSize(width: 1100, height: 720)
        .commands { AppCommands() }

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
            AppSettingsView()
                .environmentObject(model)
        }

        // 原生菜单栏「关于 deepDolphin」打开的独立窗口（正经 Mac 应用三件套之一）
        Window(L10n.t("menu.about"), id: "about") {
            AboutWindowView()
        }
        .windowResizability(.contentSize)

        // 原生菜单栏「帮助」打开的独立窗口（与设置面板帮助 Tab 同一份文档内容）
        Window(L10n.t("menu.help"), id: "help") {
            HelpWindowView()
        }
        .defaultSize(width: 560, height: 640)
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

// ⚠️ 应用菜单命令必须放进独立的 `Commands` 结构体：
// `.commands { }` 尾闭包里取不到 `@Environment(\.openWindow)`，
// 编译期直接报错 —— 这是 SwiftUI 的硬边界，不是写法偏好。
struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        // 应用菜单：关于（设置 ⌘, 由 Settings scene 自动带上）。
        // ⚠️ 关于项与帮助窗口共用 AboutWindowView —— 标准关于面板放不下
        // 「这是谁 · 引擎是什么 · 仓库在哪」三件事（见 AboutHelpWindows.swift）。
        CommandGroup(replacing: .appInfo) {
            Button(l10n.str["menu.about"] ?? "关于 deepDolphin") {
                openWindow(id: "about")
                NSApp.activate(ignoringOtherApps: true)
            }
        }

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

        // 帮助菜单：应用内帮助（独立窗口）+ 两个仓库入口。
        // CommandGroup(.help) 的存在本身让「帮助」菜单出现在菜单栏 ——
        // 原来应用根本没有这一项，而「设置/关于/帮助」是正经 Mac 应用的三件套。
        CommandGroup(after: .help) {
            Button(l10n.str["menu.help"] ?? "deepGit 帮助") {
                openWindow(id: "help")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("\(l10n.str["menu.github"] ?? "GitHub") · deepDolphin") {
                NSWorkspace.shared.open(URL(string: "https://github.com/asdshuaishuai/deepDolphin")!)
            }
            Button("\(l10n.str["menu.engine"] ?? "Engine") · moonGit") {
                NSWorkspace.shared.open(URL(string: "https://github.com/asdshuaishuai/moongit")!)
            }
        }
    }
}

#endif  // DEEPGIT_RENDER_HARNESS（只屏蔽 @main 入口，视图留在外面）

/// 面板窗口根视图（处理深链参数 + 生命周期）
struct DeepGitPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openPanel
    @Environment(\.openSettings) private var openSettings

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
                        // 跑完把逐仓库结果交给面板。⚠️ 以前这条路径只有一条
                        // 聚合通知（「N 个项目已更新」），哪个仓库改了哪些文档、
                        // 哪个失败了、备份在哪，全都看不见。
                        model.startUpdateAll(deep: track == .deep) { r in
                            model.agentBulkResult = r
                        }
                        model.pendingBulkUpdate = nil
                    }
                }
                Button("取消", role: .cancel) { model.pendingBulkUpdate = nil }
            } message: {
                Text(model.pendingBulkUpdate.map {
                    DestructiveGuard.bulkUpdateMessage(projectCount: model.projects.count, track: $0)
                } ?? "")
            }
            // 全量结果面板。挂在主面板上：菜单栏与 Dock 两条入口都是
            // CommandMenu / NSMenuItem（不是 View），挂不上 sheet。
            .sheet(item: $model.agentBulkResult) { r in
                AgentBulkResultSheet(report: r)
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
            // 与工具栏齿轮同一条路：系统原生设置窗口（Settings scene）。
            openSettings()
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
