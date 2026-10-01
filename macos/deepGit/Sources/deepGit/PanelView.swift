// PanelView.swift — 主面板窗口：侧栏导航 + 详情区。
//
// 【边界】本视图层只消费 AppModel 缓存的引擎数据，不做任何计算。
//
// ⚠️ 原来这里写的是「HTTP API 数据」—— 传输层早改成 CLI 子进程了，
// 这行注释是删除 HTTP 服务端时漏掉的残留。留着会让下一个人
// 去找一个根本不存在的 HTTP 客户端。
import SwiftUI

struct PanelView: View {
    @EnvironmentObject var model: AppModel
    @State private var showScan = false
    @State private var showTCCGuide = false
    @State private var showAgent = false
    /// 侧栏项目搜索词。空 = 不过滤。
    @State private var projectQuery = ""
    /// 自建搜索框的焦点。⌘F 要靠它把光标送进去。
    ///
    /// ⚠️ 为什么不用系统的 `.searchable`：那个搜索栏**不接受外部 focus 绑定**，
    /// 所以 ⌘F 没法把焦点送进去 —— 按了没反应。
    /// 自建的 TextField 才能 `.focused($searchFocused)`。
    /// （AgentView 的输入框一直是自建的 + `@FocusState`，与这里同一条路。）
    @FocusState private var searchFocused: Bool

    /// 过滤后的项目。判定在 SearchFilter（纯函数，可测）。
    ///
    /// 匹配项目名 + 分支名：用户记得「那条 feat 分支」时也能搜到。
    private var shownProjects: [ProjectStatus] {
        SearchFilter.filter(model.projects, query: projectQuery) { p in
            p.name + " " + p.branches.map(\.name).joined(separator: " ")
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 940, minHeight: 620)
        .navigationTitle("deepGit 面板")
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            // ⚠️ 原来这里是 `await model.refreshAll()`，
            // 而 DeepGitPanel.onAppear 又调 `model.start()`（内部也 refreshAll）——
            // **首次打开刷两遍**，每次约 2.1s，于是「打开面板要等」。
            // 现在只由 .task 触发 start()，全量刷新有且只有一个入口。
            await model.start()
            if case .project(let name) = model.selection {
                await model.loadProject(name)
            }
        }
        .onChange(of: model.selection) { section in
            if case .project(let name) = section {
                Task { await model.loadProject(name) }
            }
        }
        .sheet(isPresented: $model.showAISettings) {
            GeneralSettingsView(onClose: { model.showAISettings = false })
                .environmentObject(model)
        }
        .sheet(isPresented: $showAgent) {
            // 范围跟着当前选中：选了项目就聊那个项目，没选就是项目群。
            // 传 .group 而不是一个"默认"值，是因为静默地把项目问题
            // 拿到项目群范围去答，模型会答得很像回事但答的不是那件事。
            AgentView(target: agentTarget)
        }
        .sheet(isPresented: $showTCCGuide) {
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("需要完全磁盘访问权限")
                    .font(.title3.weight(.semibold))
                Text("deepGit 需要访问外置卷上的项目目录。请在系统设置中允许，然后重启 deepGit。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("稍后") { showTCCGuide = false }
                    .foregroundStyle(.secondary)
            }
            .frame(width: 400, height: 280)
        }
        .sheet(isPresented: $showScan) {
            ScanSheet().environmentObject(model)
        }
    }

    // MARK: 侧栏

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarSearch
            Divider()
            // ⚠️ 不用 `$model.selection`：selection 改成 `private(set)` 就是为了让
            // 「路由只有一个入口」成为**编译期**事实，而直接取绑定等于开后门。
            // 侧栏点选走同一个 go(_:) —— 于是点一个不存在的项目也会被 Router 拦下。
            List(selection: Binding(
                get: { model.selection },
                set: { if let s = $0 { model.go(s) } }
            )) {
            Section("总览") {
                // ⌘1–⌘3 的键位声明在 ShortcutMap（唯一来源），这里只消费。
                // ⚠️ 快捷键挂在**已有的导航项**上，不另开一个「视图切换」分组 ——
                //    另开一组会把同一批视图列两遍，两组还不一致（只有这组带 badge），
                //    既破坏侧栏的信息架构，又让人以为它们是两种不同的东西。
                viewShortcut(.dashboard, key: .dashboard)
                viewShortcut(.board, key: .board)
                Label("里程碑", systemImage: "flag.2.crossed")
                    .tag(RootSection.milestones)
                    .badge(model.dashboard.map { d in
                        d.milestones.counts.open + d.milestones.counts.done
                    } ?? 0)
                    .keyboardShortcut(
                        ShortcutMap.shortcut(for: .milestones)?.keyEquivalentSwiftUI ?? KeyEquivalent("\u{0}"),
                        modifiers: ShortcutMap.shortcut(for: .milestones)?.modifiersSwiftUI ?? [.command])
            }
            Section {
                Button {
                    showScan = true
                } label: {
                    Label("添加 / 扫描项目", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            Section("项目（\(shownProjects.count)/\(model.projects.count)）") {
                // ⌘4 打开当前选中的项目。
                // ⚠️ 没有项目时**什么都不做** —— 不能把 selection 改成某个不存在的项目，
                // 也不能弹一个空详情页（那正是「点了没反应」的另一种形态）。
                // 已经在项目详情里时也不动：再点一次等于原地踏步。
                if case .project = model.selection {
                    Label("项目详情", systemImage: "folder")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(A11y.label(fromHelp: "已在项目详情", fallback: "项目详情"))
                } else if !model.projects.isEmpty {
                    Button {
                        if let first = model.projects.first { model.go(.project(first.name)) }
                    } label: {
                        Label("打开项目详情", systemImage: "folder")
                    }
                    .keyboardShortcut(
                        ShortcutMap.shortcut(for: .currentProject)?.keyEquivalentSwiftUI ?? KeyEquivalent("\u{0}"),
                        modifiers: ShortcutMap.shortcut(for: .currentProject)?.modifiersSwiftUI ?? [.command])
                }
                if let reason = SearchFilter.emptyReason(
                    allCount: model.projects.count, shownCount: shownProjects.count, query: projectQuery) {
                    Text(SearchFilter.emptyText(reason, noun: "项目"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(shownProjects) { p in
                    HStack(spacing: 8) {
                        if p.error != nil {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption2)
                        } else if let b = p.branches.first(where: { $0.isCurrent }) ?? p.branches.first {
                            StatusDot(status: b.status)
                        } else {
                            Circle().fill(.secondary).frame(width: 8, height: 8)
                        }
                        Text(p.name)
                            .lineLimit(1)
                        Spacer()
                        if p.userDirtyCount > 0 {
                            Text("●\(p.userDirtyCount)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .tag(RootSection.project(p.name))
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 210)
        .overlay(alignment: .bottom) {
            if let t = model.lastRefreshed {
                Text("刷新于 \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 6)
            }
        }
        }
    }

    /// 侧栏自建搜索框。
    ///
    /// 用它而不是系统 `.searchable` 的唯一理由：**⌘F 必须能把焦点送进来**，
    /// 而系统搜索栏不接受外部 focus 绑定（按了没反应）。
    private var sidebarSearch: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.tertiary)
            TextField("搜索项目或分支", text: $projectQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.callout)
            if !projectQuery.isEmpty {
                Button {
                    projectQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(A11y.label("清除搜索"))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .accessibilityLabel(A11y.label(fromHelp: "搜索项目或分支", fallback: "搜索"))
    }

    // MARK: 视图切换的目标映射

    /// 侧栏导航项 + 它对应的数字快捷键。
    ///
    /// 键位来自 `ShortcutMap`（唯一声明处）；不在那里的目标**不给**快捷键 ——
    /// 给 `"\u{0}"` 意味着那个键永远匹配不到，用户按了没反应却看不出为什么。
    private func viewShortcut(_ section: RootSection, key target: ShortcutTarget) -> some View {
        Label(title(for: section), systemImage: icon(for: section))
            .tag(section)
            .keyboardShortcut(
                ShortcutMap.shortcut(for: target)?.keyEquivalentSwiftUI ?? KeyEquivalent("\u{0}"),
                modifiers: ShortcutMap.shortcut(for: target)?.modifiersSwiftUI ?? [.command])
    }

    private func title(for section: RootSection) -> String {
        switch section {
        case .dashboard:  return "仪表盘"
        case .board:      return "看板"
        case .milestones: return "里程碑"
        case .project:    return "项目"
        }
    }

    private func icon(for section: RootSection) -> String {
        switch section {
        case .dashboard:  return "square.grid.2x2"
        case .board:      return "rectangle.split.3x1"
        case .milestones: return "flag.2.crossed"
        case .project:    return "folder"
        }
    }

    // MARK: 详情路由

    @ViewBuilder
    private var detail: some View {
        // 深链打错字的说明条。**独立于 lastError**，也不依赖 !isLoading ——
        // 它恰恰发生在启动刷新**途中**（列表到了才判得出「不存在」），
        // 挂到错误条那套条件上会被 isLoading 挡掉，用户什么也看不到。
        if let note = model.routeNotice {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(.orange)
                Text(note)
                    .font(.caption)
                    .lineLimit(2)
                Spacer()
                Button {
                    model.dismissRouteNotice()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(A11y.label("关闭提示"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.12))
        }
        // 常驻错误条：项目正常加载时 lastError 也要可见（此前只在空列表时展示 → 静默失败）
        if let err = model.lastError, model.projects.isEmpty == false, !model.isLoading {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    if err.contains("完全磁盘访问") || err.contains("可移除宗卷") {
                        Button("打开系统设置") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                    }
                    Button {
                        model.lastError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.12))
                // ⚠️ 原来这里挂着 `.task { await model.refreshAll() }` ——
                // 错误横幅**一出现就触发一次全量刷新**。于是：
                //   · 每次报错都白刷一遍（2.1s），
                //   · 刷新若再次失败会重新设 lastError，横幅反复闪，
                //   · 最坏情况：刷新中途把用户正要读的这条错误**清掉**（横幅自己消失）。
                // 横幅是**给人看的信息**，不该在用户读它的时候自己动手。
                // 真要重试，用户点工具栏「刷新」；不想看，点右侧的 ×。
            }
        }
        if !model.engineFound {
            setupGuide
        } else if model.projects.isEmpty && model.isLoading {
            ProgressView("读取项目群…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.projects.isEmpty {
            EmptyState(
                icon: "shippingbox",
                title: model.lastError != nil ? "引擎连接失败" : "暂无已注册项目",
                subtitle: model.lastError ?? "运行 deepgit scan <目录> 注册项目群"
            )
        } else {
            switch model.selection {
            case .dashboard:
                DashboardView()
            case .board:
                BoardPage()
            case .milestones:
                MilestonesView()
            case .project(let name):
                ProjectDetailView(projectName: name)
            case nil:
                DashboardView()
            }
        }
    }

    // MARK: 引擎安装引导

    private var setupGuide: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("需要 deepGit 引擎")
                .font(.title3.weight(.medium))
            Text("引擎是独立安装的本地服务，客户端只负责展示。")
                .foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. 仓库内执行：sh scripts/install.sh")
                    Text("2. 注册项目群：deepgit scan ~/dev --depth 4")
                    Text("3. 回到本面板点击刷新")
                }
                .font(.system(.callout, design: .monospaced))
            }
            Button("重新检测引擎") {
                EngineCLI.shared.refreshBinary()
                Task { await model.refreshAll() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 工具栏

    /// 对话范围：选中了项目就是那个项目，否则整个项目群。
    private var agentTarget: AgentTarget {
        if case .project(let name) = model.selection { return .project(name) }
        return .group
    }
    // ⚠️ 这里原来挂着**两个** `.toolbar`（body 上一处 + 上面一处），
    // SwiftUI 会把两组都渲染出来：
    //   · 「刷新」出现两次，而且下面那份没有 `.disabled(model.isLoading)` ——
    //     加载中照样能点，点了撞上 refreshGate 被合并，看起来就是没反应；
    //   · 「全部浅更新」与 UpdateActionMenu 菜单里的「浅更新」重复。
    // 删掉第二处后，「AI 设置」折进这里（它是唯一不重复的），其余不再单独挂。

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // 设计稿顶栏中段：双轨同步主动作。
            // ⚠️ 放在刷新**之前** —— 这是最常做的动作，位置靠左。
            //    菜单里原来那两个裸项已经删掉（见 UpdateActionMenu 的注释），
            //    同一个动作不许在同一个窗口里出现两次。
            DualTrackButtons()

            Button {
                Task { await model.refreshAll() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
            .help("重新读取状态、仪表盘与里程碑（\(ShortcutMap.refresh.display)）")
            .accessibilityLabel(A11y.label("重新读取状态、仪表盘与里程碑"))

            // AI 变体与定时更新（裸的浅/深更新已升为双轨按钮）
            UpdateActionMenu()

            // P0-5：AI 对话入口。
            // 之前 app 里根本没有对话界面 —— AI 只能出一次性结果
            // （项目说明 / 更新摘要），弹一个 sheet 就没下文，
            // 用户想追问只能关掉重来，而 AgentCore.run 每次从零起步。
            Button {
                showAgent = true
            } label: {
                Label("AI 助手", systemImage: "sparkles")
            }
            .help("与 AI 多轮对话（P0-5）")
            .accessibilityLabel(A11y.label("与 AI 多轮对话（P0-5）"))

            Button {
                model.showAISettings = true
            } label: {
                Label("AI 设置", systemImage: "gearshape")
            }
            .help("AI 供应商与凭据设置（\(ShortcutMap.settings.display)）")
            .accessibilityLabel(A11y.label("AI 供应商与凭据设置"))

            // 设计稿顶栏右段：搜索。
            // ⚠️ 之所以做成一个**看得见的按钮**而不只留快捷键：
            // 侧栏搜索是自建的（因为系统 `.searchable` 收不到外部焦点），
            // 它不长得像 macOS 常见的工具栏搜索，⌘F 单独存在时用户发现不了。
            Button {
                searchFocused = true
            } label: {
                Label("搜索项目", systemImage: "magnifyingglass")
            }
            .keyboardShortcut(ShortcutMap.find.keyEquivalentSwiftUI, modifiers: ShortcutMap.find.modifiersSwiftUI)
            .help("在项目与分支中搜索（\(ShortcutMap.find.display)）")
            .accessibilityLabel(A11y.label("在项目与分支中搜索"))
        }
    }
}
