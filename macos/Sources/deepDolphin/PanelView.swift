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
    @State private var showHelp = false
    @State private var showAbout = false
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
        .navigationTitle(PanelWindow.title)
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
            AppSettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showAgent) {
            // 范围跟着当前选中：选了项目就聊那个项目，没选就是项目群。
            // 传 .group 而不是一个"默认"值，是因为静默地把项目问题
            // 拿到项目群范围去答，模型会答得很像回事但答的不是那件事。
            AgentView(target: agentTarget)
        }
        .sheet(isPresented: $showTCCGuide) {
            VStack(spacing: DSSpacing.lg) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("需要完全磁盘访问权限")
                    .font(.title3.weight(.semibold))
                Text("deepDolphin 需要访问外置卷上的项目目录。请在系统设置中允许，然后重启 deepDolphin。")
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
            // ── 分组：视图 / 仓库 ──
            //
            // 设计稿侧栏是三组（双轨协同管道 / Git 结构与进度分析 / 受管 Git 仓库），
            // 但它第一组的四个入口（变动管道、AGENT.md 记忆治理、动态 README、Release）
            // **本项目没有这些功能** —— 照抄会造一排点进去是空页的入口。
            // 所以按**本应用真有的东西**重组：
            //   「视图」= 三个固定视图（对应设计稿的「Git 结构与进度分析」）
            //   「仓库」= 受管项目（对应设计稿的「受管 Git 仓库」）
            // 「添加 / 扫描项目」是**动作**不是导航项，原来它自己占一个
            // **没有标题的单项 Section**，正好卡在两组中间把信息架构切成三段 ——
            // 移到底部动作区（见下），两组才真的是两组。
            Section("视图") {
                // ⌘1–⌘3 的键位声明在 ShortcutMap（唯一来源），这里只消费。
                // ⚠️ 快捷键挂在**已有的导航项**上，不另开一个「视图切换」分组 ——
                //    另开一组会把同一批视图列两遍，两组还不一致（只有这组带计数），
                //    既破坏侧栏的信息架构，又让人以为它们是两种不同的东西。
                viewShortcut(.dashboard, key: .dashboard)
                countedRow(title: "看板", icon: icon(for: .board), route: .board,
                           target: .board, count: attentionCount)
                // ⚠️ 这里**原来用的是 `.badge(...)`**，而那一行因此**点不动**。
                //    实测（本机 macOS 26）：侧栏「里程碑」连点 5 次，
                //    `selection` 的 didSet 一次都没触发 —— `go(.milestones)`
                //    根本没被调用过；把 `.badge` 去掉后同一次点击立刻生效。
                //    `.badge()` 在**选择型 List**（`List(selection:)`）的行上会
                //    接管命中测试，行的点击与选中高亮一起失效。
                //    症状极隐蔽：那一行看着完全正常、⌘3 也能进，
                //    只有真去点它才会发现是死的 —— 而「进不去的导航项」
                //    等于这个视图对鼠标用户不存在。
                //    计数改用行内文字（`countedRow`），不用 badge。
                countedRow(title: "里程碑", icon: icon(for: .milestones), route: .milestones,
                           target: .milestones, count: milestoneCountValue)
            }
            Section("仓库（\(shownProjects.count)/\(model.projects.count)）") {
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
                    HStack(spacing: DSSpacing.sm) {
                        if p.error != nil {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption2)
                        } else if let b = p.primaryBranch {
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
        // 设计稿侧栏底部有一条常驻状态条（Git Hook Active · Syncing / 上次操作时间）。
        // 原来这里是 `.overlay(alignment: .bottom)` 把「刷新于」**浮在列表上面** ——
        // 列表内容滚到底时会从它底下穿过去，看着像文字被压住了。
        // `.safeAreaInset` 让它占据自己的布局空间，列表自动避开。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // 动作区在状态条**之上**。
            //
            // ⚠️ 原来「添加 / 扫描项目」是侧栏 List 里的**一个没有标题的单项 Section**，
            //    正好卡在「视图」与「项目」两组中间 —— 它是**动作**不是导航项，
            //    放在导航结构里会把两组切成三段，读者会以为那是第三个分组。
            //    而且它没有 `.tag(...)`，在 `List(selection:)` 里点它会清掉当前选中 ——
            //    侧栏一点就跳回「项目详情」那行，是另一种「点了没反应」。
            //    移出 List 之后两件事一起消失：分组干净了，点击也不再改选中。
            VStack(spacing: 0) {
                Divider()
                Button {
                    showScan = true
                } label: {
                    Label("添加 / 扫描项目", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                .foregroundStyle(.blue)
                .help("注册一个项目，或扫描目录自动发现项目")
                .accessibilityLabel(A11y.label("添加或扫描项目"))
                Divider()
                SidebarStatusStrip(model: model)
            }
        }
        }
    }

    /// 侧栏自建搜索框。
    ///
    /// 用它而不是系统 `.searchable` 的唯一理由：**⌘F 必须能把焦点送进来**，
    /// 而系统搜索栏不接受外部 focus 绑定（按了没反应）。
    private var sidebarSearch: some View {
        HStack(spacing: DSSpacing.xs) {
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
        .padding(.vertical, DSSpacing.xs)
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

    /// 带行尾计数的侧栏导航项。**看板与里程碑共用这一处**。
    ///
    /// ⚠️ 为什么不用 `.badge()`：它在 `List(selection:)` 的行上会接管命中测试，
    /// 整行点不动（实测连点 5 次 selection 一次未变），而外观完全正常。
    /// 三个视图行必须走同一个构造点 —— 一旦某个行手写 HStack、另一个用 badge，
    /// 两行的点击行为就会分叉，而那只有真点一次才发现得了。
    ///
    /// ⚠️ 计数为 nil 时**什么都不显示**，而不是显示 0：
    /// 「读不出来」与「真的是 0」在侧栏这一行长得一样的话，
    /// 用户会把没读到当成没有。
    private func countedRow(title: String, icon: String, route: RootSection,
                            target: ShortcutTarget, count: Int?) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: icon)
            Spacer(minLength: 8)
            if let count {
                Text("\(count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(count > 0 ? .secondary : .tertiary)
            }
        }
        .tag(route)
        .keyboardShortcut(
            ShortcutMap.shortcut(for: target)?.keyEquivalentSwiftUI ?? KeyEquivalent("\u{0}"),
            modifiers: ShortcutMap.shortcut(for: target)?.modifiersSwiftUI ?? [.command])
    }

    /// 看板行尾的「要你动手」项目数。
    ///
    /// ⚠️ **报的是待处理数，不是项目总数** —— 设计稿给「变动管道」打的徽标
    /// 是 `totalPendingShallowCommits`，也是「有几件事等我做」。
    /// 报总数的话每个视图行都是同一个数字，徽标就成了装饰。
    ///
    /// ⚠️ 也不受仪表盘的时间窗筛选影响：徽标回答「**现在**有几件事要我动手」，
    /// 筛选回答「我在看哪一段时间」。把筛选套上去会让徽标随筛选跳变，
    /// 而它并不属于任何一个时间窗。
    private var attentionCount: Int? {
        model.dashboard == nil ? nil
            : model.projects.filter { $0.boardColumn == .attention }.count
    }

    /// 里程碑行尾的总数。只数 `open + done`，**不含 `unknown`**
    /// —— unknown 是「读不出来」，算进「你有 N 个里程碑」就是把无知说成事实。
    /// 读不出来时返回 nil（不显示），而不是 0。
    private var milestoneCountValue: Int? {
        model.dashboard.map { d in
            d.milestones.counts.open + d.milestones.counts.done
        }
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
            HStack(spacing: DSSpacing.sm) {
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
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.12))
        }
        // 常驻错误条：项目正常加载时 lastError 也要可见（此前只在空列表时展示 → 静默失败）
        if let err = model.lastError, model.projects.isEmpty == false, !model.isLoading {
            VStack(spacing: 0) {
                HStack(spacing: DSSpacing.sm) {
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
                .padding(.horizontal, DSSpacing.md)
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
            VStack(spacing: 0) {
                // 设计稿的主工作条（范围选择器 + 双轨链路）。
                // ⚠️ 放在内容区顶部而不是自绘标题栏：规范 §3.1 定了
                // 「原生标题栏 + 分组侧栏工作台」（D3），自绘标题栏会丢掉
                // 标准窗口行为（拖动 / 全屏 / 菜单栏）。工作条承载的是
                // 「看哪些仓库 + 对它做什么」这条主链路，与工具栏上的
                // 刷新/搜索/设置不是一类东西。
                //
                // ⚠️ 只在**引擎已就绪且有项目**时出现：没项目时
                // 范围选择器没有第二个选项，它就是一根装饰条。
                if !model.projects.isEmpty {
                    WorkBar()
                }
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
    }

    // MARK: 引擎安装引导

    private var setupGuide: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("需要 moonGit 引擎")
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
