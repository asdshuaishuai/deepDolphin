// BarView.swift — 菜单栏弹窗（MenuBarExtra .window 风格）。
//
// 系统集成的速览入口：总览 + 快捷动作，详情引导到主面板。
import SwiftUI

struct BarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var model: AppModel

    /// 待确认的批量更新。nil = 没在等确认。
    ///
    /// 批量更新会改写**多个仓库**的托管区域，所以先说清范围再动手。
    /// 它不是不可逆的（每个文件都留备份），所以确认框是告知式的，不染红。
    @State private var pendingBulk: DSSyncTrack?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 4)

            if !model.engineFound {
                missingEngine
            } else if model.projects.isEmpty {
                emptyOrError
            } else {
                projectRows
            }

            Divider().padding(.vertical, 4)
            footer
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(width: 380)
        .onAppear {
            Task { await model.refreshAll() }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            Text("项目群进度")
                .font(.headline)
            if let line = model.summaryLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新")
            .accessibilityLabel(A11y.label("刷新"))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: 项目行

    // 注意：MenuBarExtra 弹窗里 ScrollView 会塌缩成 0 高，这里用平铺 VStack
    // （超过 12 个项目时给出面板引导，弹窗高度由系统自动约束在屏幕内）
    private var projectRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.projects.prefix(12)) { p in
                MenuProjectRow(project: p)
            }
            if model.projects.count > 12 {
                Button {
                    openMainPanel(section: .dashboard)
                } label: {
                    Text("还有 \(model.projects.count - 12) 个项目，打开面板查看…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: 空态 / 错误态

    private var missingEngine: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("未找到 deepGit 引擎", systemImage: "questionmark.circle")
                .font(.subheadline.weight(.medium))
            Text("运行 deepgit-engine 的 scripts/install.sh 安装，或设 DEEPGIT_BIN")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("重新检测") {
                EngineCLI.shared.refreshBinary()
                Task { await model.refreshAll() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var emptyOrError: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let err = model.lastError {
                Label("引擎错误", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Button("重试") {
                    Task { await model.refreshAll() }
                }
                .controlSize(.small)
            } else {
                Text(model.isLoading ? "读取中…" : "暂无已注册项目")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("运行 deepgit scan <目录> 注册项目群")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: 底部动作

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                openMainPanel(section: .dashboard)
            } label: {
                Label("打开面板", systemImage: "rectangle.inset.filled.and.person.filled")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)

            Button {
                pendingBulk = .shallow
            } label: {
                if model.busyAll {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("全部浅更新")
                }
            }
            .controlSize(.small)
            .disabled(model.busyAll || model.projects.isEmpty)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("完全退出")
            .accessibilityLabel(A11y.label("完全退出"))
        }
        .padding(.horizontal, 12)
        .confirmationDialog(
            pendingBulk.map { "全部\($0.label)？" } ?? "",
            isPresented: Binding(
                get: { pendingBulk != nil },
                set: { if !$0 { pendingBulk = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let track = pendingBulk {
                Button(DestructiveGuard.confirmTitle(for: .bulkUpdate)) {
                    model.startUpdateAll(deep: track == .deep)
                    pendingBulk = nil
                }
            }
            Button("取消", role: .cancel) { pendingBulk = nil }
        } message: {
            Text(pendingBulk.map {
                DestructiveGuard.bulkUpdateMessage(projectCount: model.projects.count, track: $0)
            } ?? "")
        }
    }

    private func openMainPanel(section: RootSection) {
        model.go(section)
        openWindow(id: "panel")
    }
}

/// 菜单栏弹窗里的单项目行：状态点 + 名称 + 未提交徽标 + 待记录迷你进度条
struct MenuProjectRow: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var model: AppModel
    let project: ProjectStatus

    private var currentBranch: BranchStatus? {
        project.branches.first { $0.isCurrent } ?? project.branches.first
    }

    var body: some View {
        Button {
            model.go(.project(project.name))
            openWindow(id: "panel")
            Task { await model.loadProject(project.name) }
        } label: {
            HStack(spacing: 8) {
                if project.error != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption2)
                } else if let b = currentBranch {
                    StatusDot(status: b.status)
                } else {
                    Circle().fill(.secondary).frame(width: 8, height: 8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        if project.userDirtyCount > 0 {
                            Chip(text: "●\(project.userDirtyCount)", tint: .orange)
                        }
                        if model.busyProject == project.name {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    Text(project.error ?? subtitle)
                        .font(.caption2)
                        .foregroundStyle(project.error != nil ? .red : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let b = currentBranch, b.pendingCommits > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(b.pendingCommits)")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.blue)
                        ProgressView(value: Double(min(b.pendingCommits, 10)), total: 10)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .frame(width: 44)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if let pulse = project.pulseLine { return pulse }
        if let b = currentBranch, !b.headAgo.isEmpty {
            return "\(b.headAgo) · \(b.statusLabel)"
        }
        return project.lastCommitAgo.isEmpty ? "非 git 项目" : project.lastCommitAgo
    }
}
