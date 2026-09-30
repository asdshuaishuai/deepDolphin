// PanelWindow.swift — 主面板窗口管理（正经 Mac 应用形态）。
//
// - 统一工具栏（NSToolbar .unified）：刷新 / 全部浅更新 / 弹性 / 定时更新菜单 / AI 设置
// - 窗口标题 + 副标题（项目群摘要，随刷新更新）
// - 设置走独立窗口（⌘, / 工具栏）
import AppKit
import SwiftUI

@MainActor
final class PanelWindowController: NSObject, NSToolbarDelegate {
    static let shared = PanelWindowController()

    private var window: NSWindow?
    private var modelRef: AppModel?

    var isVisible: Bool {
        window?.isVisible == true
    }

    // MARK: NSToolbarDelegate

    private enum ItemID: String, CaseIterable {
        case refresh, updateAll, flexible, schedule, aiSettings
    }

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = [
            NSToolbarItem.Identifier(ItemID.refresh.rawValue),
            NSToolbarItem.Identifier(ItemID.updateAll.rawValue),
        ]
        ids.append(.flexibleSpace)
        ids.append(NSToolbarItem.Identifier(ItemID.schedule.rawValue))
        ids.append(NSToolbarItem.Identifier(ItemID.aiSettings.rawValue))
        return ids
    }

    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    nonisolated func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch ItemID(rawValue: itemIdentifier.rawValue) {
        case .refresh:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "刷新"
            item.toolTip = "重新拉取引擎状态"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
            item.target = self
            item.action = #selector(refreshTapped)
            return item
        case .updateAll:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "全部浅更新"
            item.toolTip = "记录全部项目进度并刷新文档"
            item.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "全部浅更新")
            item.target = self
            item.action = #selector(updateAllTapped)
            return item
        case .schedule:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "定时更新"
            item.toolTip = "定时更新间隔"
            item.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "定时更新")
            item.showsIndicator = true
            Task { @MainActor in
                item.menu = Self.scheduleMenu()
            }
            return item
        case .aiSettings:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "AI 设置"
            item.toolTip = "Provider / 模型 / API Key"
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "AI 设置")
            item.target = self
            item.action = #selector(aiSettingsTapped)
            return item
        default:
            return nil
        }
    }

    nonisolated private static func scheduleMenu() -> NSMenu {
        let menu = NSMenu()
        let hours: [(String, Int)] = [("关闭定时更新", 0), ("每 1 小时", 1), ("每 3 小时", 3), ("每 6 小时", 6), ("每 12 小时", 12), ("每 24 小时", 24)]
        for (title, h) in hours {
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.schedulePicked(_:)), keyEquivalent: "")
            item.tag = h
            menu.addItem(item)
        }
        return menu
    }

    @objc private func refreshTapped() {
        Task { await modelRef?.refreshAll() }
    }

    @objc private func updateAllTapped() {
        Task { await modelRef?.updateAll(deep: false) }
    }

    @objc private func aiSettingsTapped() {
        if let m = modelRef {
            openAISettings(model: m)
        }
    }

    static func handleScheduleTag(_ tag: Int) {
        Task { @MainActor in
            AppModel.shared.setAutoUpdate(hours: tag)
        }
    }

    /// 调试用：把菜单栏弹窗内容放进普通窗口
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

    // MARK: 打开主面板

    func open(model: AppModel) {
        modelRef = model
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
        w.title = "deepGit"
        w.subtitle = "本地项目群进度管理"
        w.minSize = NSSize(width: 940, height: 620)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(
            rootView: PanelView().environmentObject(model)
        )

        let toolbar = NSToolbar(identifier: "PanelToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        w.toolbar = toolbar
        w.toolbarStyle = .unified

        w.center()
        w.setFrameAutosaveName("deepGitPanel")
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        model.onSummaryChange = { [weak self] line in
            self?.window?.subtitle = line ?? "本地项目群进度管理"
        }
    }

    /// 关闭全部窗口（保留 bar 运行）
    func closeAll() {
        window?.orderOut(nil)
    }

    // MARK: 设置窗口

    func openAISettings(model: AppModel) {
        modelRef = model
        // SwiftUI sheet 呈现（由 PanelView 持有 .sheet）；NSHostingView 独立窗口在 macOS 27
        // 上布局死循环（窗口缩成 0×0），已弃用
        model.showAISettings = true
        open(model: model)
    }
}
