// PanelWindow.swift — 主面板窗口管理。
//
// 用 NSWindow 直接承载 SwiftUI 面板视图，而不是 Window scene：
// 1. 可以在启动参数 / 菜单栏 / 任何时机确定性开窗（SwiftUI 的 openWindow
//    依赖视图环境，MenuBarExtra 内容又是懒加载的，启动时拿不到）
// 2. 生命周期可控：关闭仅隐藏，App 退出前统一清理
import AppKit
import SwiftUI

@MainActor
final class PanelWindowController {
    static let shared = PanelWindowController()

    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    /// 调试用：把菜单栏弹窗内容（BarView）放进普通窗口，验证其独立渲染
    func openBarPreview(model: AppModel) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Bar 预览"
        w.contentView = NSHostingView(rootView: BarView().environmentObject(model))
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    func open(model: AppModel) {
        NSLog("deepgit-bar: PanelWindowController.open 被调用")
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "deepGit 面板"
        w.minSize = NSSize(width: 940, height: 620)
        w.titlebarAppearsTransparent = false
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(
            rootView: PanelView().environmentObject(model)
        )
        w.center()
        w.setFrameAutosaveName("deepGitPanel")
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
        NSLog("deepgit-bar: 面板窗口已创建 frame=\(w.frame)")
    }
}
