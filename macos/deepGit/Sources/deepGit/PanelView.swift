// PanelView.swift — 主面板窗口：侧栏导航 + 详情区。
//
// 【边界】本视图层只消费 AppModel 缓存的 HTTP API 数据，不做任何计算。
import SwiftUI

struct PanelView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 940, minHeight: 620)
        .navigationTitle("deepGit 面板")
        .toolbar { toolbarContent }
        .task {
            await model.refreshAll()
            if case .project(let name) = model.selection {
                await model.loadProject(name)
            }
        }
        .onChange(of: model.selection) { section in
            if case .project(let name) = section {
                Task { await model.loadProject(name) }
            }
        }
        .sheet(isPresented: $showAISettings) {
            AISettingsView()
        }
    }

    // MARK: 侧栏

    private var sidebar: some View {
        List(selection: $model.selection) {
            Section("总览") {
                Label("仪表盘", systemImage: "square.grid.2x2")
                    .tag(RootSection.dashboard)
                Label("看板", systemImage: "rectangle.split.3x1")
                    .tag(RootSection.board)
                Label("里程碑", systemImage: "flag.2.crossed")
                    .tag(RootSection.milestones)
                    .badge(model.dashboard.map { d in
                        d.milestones.counts.open + d.milestones.counts.done
                    } ?? 0)
            }
            Section("项目（\(model.projects.count)）") {
                ForEach(model.projects) { p in
                    HStack(spacing: 8) {
                        if p.error != nil {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.system(size: 10))
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

    // MARK: 详情路由

    @ViewBuilder
    private var detail: some View {
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
                BoardView()
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
                .font(.system(size: 44))
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
                DeepGitEngine.shared.refreshBinary()
                Task { await model.refreshAll() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await model.refreshAll() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)

            UpdateActionMenu()
        }
    }

    @State private var showAISettings = false
}
