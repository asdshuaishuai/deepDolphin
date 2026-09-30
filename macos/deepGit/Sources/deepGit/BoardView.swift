// BoardView.swift — 项目管理画板（看板）。
//
// 列 = 引擎推导的健康状态（不可手改——状态来自 git 事实）：
//   活跃中 / 待处理（有未提交·未跟踪·待合入）/ 停滞 / 其他（merged/非 git/错误）
// 卡片 = 项目：脉搏徽标 + 快捷动作（浅更新 / 项目说明），点击进详情。
import SwiftUI

enum BoardColumn: String, CaseIterable, Identifiable {
    case active = "活跃中"
    case attention = "待处理"
    case stale = "停滞"
    case other = "其他"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .active: return .green
        case .attention: return .orange
        case .stale: return .red
        case .other: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .active: return "bolt.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .stale: return "zzz"
        case .other: return "tray.full"
        }
    }
}

func boardColumn(for p: ProjectStatus) -> BoardColumn {
    if p.error != nil || !p.isGit { return .other }
    if p.branches.contains(where: { $0.status == "stale" }) { return .stale }
    let attention = p.userDirtyCount > 0 || p.untrackedCount > 0 || p.stashCount > 0
        || p.branches.contains { $0.pendingCommits > 0 && !$0.isDefault }
        || (p.mergeHint?.kind == "merge" || p.mergeHint?.kind == "fast-forward")
    if attention { return .attention }
    if p.branches.contains(where: { $0.status == "active" || $0.status == "idle" }) || !p.lastCommitAgo.isEmpty {
        return .active
    }
    return .other
}

struct BoardView: View {
    @EnvironmentObject var model: AppModel

    private func cards(for column: BoardColumn) -> [ProjectStatus] {
        model.projects.filter { boardColumn(for: $0) == column }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(BoardColumn.allCases) { column in
                    BoardColumnView(column: column, projects: cards(for: column))
                }
            }
            .padding(16)
        }
        .navigationTitle("看板")
        .refreshable { await model.refreshLight() }
    }
}

struct BoardColumnView: View {
    let column: BoardColumn
    let projects: [ProjectStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: column.icon)
                    .foregroundStyle(column.color)
                Text(column.rawValue)
                    .font(.subheadline.weight(.semibold))
                Text("\(projects.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(column.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(column.color)
                Spacer()
            }
            .padding(.horizontal, 4)

            if projects.isEmpty {
                VStack(spacing: 4) {
                    Circle().strokeBorder(column.color.opacity(0.3), lineWidth: 1).frame(width: 26, height: 26)
                    Text("空")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(projects) { p in
                    BoardCard(project: p, tint: column.color)
                }
            }
        }
        .frame(width: 280)
    }
}

struct BoardCard: View {
    @EnvironmentObject var model: AppModel
    let project: ProjectStatus
    let tint: Color
    @State private var briefSheet = false
    @State private var briefBusy = false
    @State private var briefText = ""
    @State private var briefError: String?

    private var currentBranch: BranchStatus? {
        project.branches.first { $0.isCurrent } ?? project.branches.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(project.name)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if model.busyProject == project.name {
                    ProgressView().controlSize(.mini)
                }
            }

            if let err = project.error {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text(project.headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    if project.userDirtyCount > 0 { Chip(text: "●\(project.userDirtyCount)", tint: .orange) }
                    if project.untrackedCount > 0 { Chip(text: "未跟踪 \(project.untrackedCount)", tint: .orange) }
                    if project.stashCount > 0 { Chip(text: "stash \(project.stashCount)", tint: .secondary) }
                    if let b = currentBranch, b.pendingCommits > 0 {
                        Chip(text: "\(b.pendingCommits) 待记录", tint: .blue)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    Task { await model.update(project, deep: false) }
                } label: {
                    Label("浅更新", systemImage: "arrow.down.circle")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .disabled(model.busyProject == project.name || model.busyAll)

                Button {
                    generateBrief()
                } label: {
                    Label("说明", systemImage: "sparkles")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .disabled(briefBusy)

                Spacer()
                if let b = currentBranch, !b.headAgo.isEmpty {
                    Text(b.headAgo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                model.selection = .project(project.name)
                PanelWindowController.shared.open(model: model)
                await model.loadProject(project.name)
            }
        }
        .sheet(isPresented: $briefSheet) {
            AIResultSheet(
                title: "项目说明 · \(project.name)",
                markdown: briefText,
                busy: briefBusy,
                errorText: briefError,
                onRegenerate: { generateBrief() }
            )
        }
    }

    private func generateBrief() {
        briefBusy = true
        briefError = nil
        briefText = ""
        briefSheet = true
        Task {
            do {
                briefText = try await model.projectBrief(for: project)
            } catch {
                briefError = error.localizedDescription
            }
            briefBusy = false
        }
    }
}
