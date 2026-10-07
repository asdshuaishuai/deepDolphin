// BoardView.swift — 项目管理画板（看板）。
//
// 【看板回答的是另一个问题】
// 仪表盘回答「整体怎么样」（4 张 KPI + 项目卡网格）；
// 看板回答「**现在哪些项目要我动手**」。
// 所以它不是仪表盘的另一种排版 —— 它按**可执行性**分列，而不是按规模或字母。
//
// 【分列规则在模型层】
// 判定是 `ProjectStatus.liveness`（Models.swift），本文件只负责把它映射成列。
// 原来这里有一份私有的 `boardColumn(for:)`，它判 `p.branches.contains { $0.status == "stale" }`
// —— `branches` 是**追踪数组**，无远端基线的仓库恒为空，
// 于是「停滞」列**永远是 0**，47 天没提交的仓库会落进「活跃中」。
// 同一个错误在项目卡的 `stateWord` 上又犯了一次（都显示「正常」）。
// 两处都改成消费模型层那一份，见 `ProjectStatus.liveness` 的注释。
//
// 【为什么不是横向四列】
// 原来是 `ScrollView(.horizontal)` + 四列 200–260 宽。在 1100pt 窗口下实测：
// 四列挤在内容区左边约 1/3，右边整片空白，**还要横向滚动**。
// macOS 上横向滚动画板是反模式（触控板横滚费劲、窗口一窄就切不全）。
// 改成 `List` + `Section`：原生的分组标题、计数、原生行高与滚动，
// 窄窗口下自动变成一列，不需要额外适配。
//
// 【为什么不再截断】
// 原来每列只列 `projects.prefix(4)`，剩下几个只显示一句「还有 N 个…」——
// 列头徽标写着 7、列里只有 4 张卡，**另外 3 个永远点不到**。
// 徽标报数和实际列出来的东西对不上，正是「上限当全量」那一族。
// 现在全列。

import SwiftUI

enum BoardColumn: String, CaseIterable, Identifiable {
    case attention = "待处理"
    case active    = "活跃中"
    case quiet     = "久未更新"
    case other     = "其他"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .attention: return .orange
        case .active:    return .green
        case .quiet:     return .secondary
        case .other:     return .secondary
        }
    }

    var icon: String {
        switch self {
        case .attention: return "exclamationmark.circle.fill"
        case .active:    return "bolt.fill"
        case .quiet:     return "zzz"
        case .other:     return "tray.full"
        }
    }

    /// 这一列的判定依据 —— 空列也要说清「为什么空」，
    /// 界面显示名（rawValue 是中文身份串，只作标识不作展示）。
    func label(en: Bool) -> String {
        switch self {
        case .attention: return en ? "Needs Attention" : "待处理"
        case .active:    return en ? "Active" : "活跃中"
        case .quiet:     return en ? "Quiet" : "久未更新"
        case .other:     return en ? "Other" : "其他"
        }
    }

    /// 否则「0」既可能是「真没有」也可能是「没量出来」。
    var basis: String {
        switch self {
        case .attention: return L10n.t("board.basis.attention")
        case .active:    return L10n.t("board.basis.active")
        case .quiet:     return L10n.t("board.basis.quiet")
        case .other:     return L10n.t("board.basis.other")
        }
    }
}

extension ProjectStatus {
    /// 这个项目该进哪一列。**只读 `liveness`**，不自己判。
    var boardColumn: BoardColumn {
        switch liveness {
        case .needsAction: return .attention
        case .engineStale, .quiet: return .quiet
        case .recent:      return .active
        case .unreadable, .notGit, .unknown: return .other
        }
    }
}

struct BoardPage: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject var model: AppModel

    /// 看板看到的项目集合。
    ///
    /// ⚠️ 用的是**仪表盘那一份筛选**（`model.dashFilter`），不是自己的 `model.projects`。
    /// 原来两个视图各看各的：用户在仪表盘选了「近 7 天」（3 个项目变 1 个），
    /// 切到看板还是 3 个 —— 同一屏里两个视图对「我现在在看什么」各说各话。
    /// 筛选状态放在 `AppModel` 而不是 `DashboardView` 的 `@State`：
    /// 后者在视图重建时会被重置（切到看板再切回来，筛选就悄悄弹回「全量」）。
    private var shown: [ProjectStatus] {
        model.projects.filter { model.dashFilter.keeps(project: $0) }
    }

    var body: some View {
        List {
            ForEach(BoardColumn.allCases) { column in
                let list = shown.filter { $0.boardColumn == column }
                Section {
                    if list.isEmpty {
                        Text(column.basis)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(list) { p in
                            BoardCard(project: p)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: column.icon)
                            .foregroundStyle(column.color)
                        Text(column.label(en: L10n.shared.language.usesEnglishFacts))
                        // ⚠️ 计数必须和下面真的列出来的行数一致 ——
                        //    原来这里是 7、列出来 4（prefix(4)），差额只写在「还有 3 个…」里。
                        Text("\(list.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle(L10n.t("board.title"))
    }
}

struct BoardCard: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var model: AppModel
    let project: ProjectStatus
    @State private var briefSheet = false
    @State private var briefBusy = false
    @State private var briefText = ""
    @State private var briefError: String?

    /// 当前分支。规则在 `ProjectStatus.primaryBranch`（模型层），
    /// 这里只消费 —— 原来这里是本文件私有的第二份。
    private var currentBranch: BranchStatus? { project.primaryBranch }

    /// 状态词。与项目卡共用 `ProjectStatus.stateWord`（模型层那一份）。
    private var state: (text: String, tone: ProjectStatus.Liveness) { project.stateWord(en: L10n.shared.language.usesEnglishFacts) }

    private var stateColor: Color {
        switch state.tone {
        case .unreadable, .unknown: return .red
        case .notGit:               return .secondary
        case .needsAction:          return .orange
        case .engineStale, .quiet:  return .secondary
        case .recent:               return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(project.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(state.text)
                    .font(.caption)
                    .foregroundStyle(stateColor)
                Spacer()
                if model.busyProject == project.name {
                    ProgressView().controlSize(.mini)
                }
            }

            if let err = project.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text(project.headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // 卡片上也要显示 warnings：这里正是「0 个提交」最容易被当成事实的地方
                // （列表一眼扫过去，谁会去点开详情）。
                ForEach(project.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    if project.userDirtyCount > 0 { Chip(text: "●\(project.userDirtyCount)", tint: .orange) }
                    if project.untrackedCount > 0 { Chip(text: L10n.t("board.chip.untracked", project.untrackedCount), tint: .orange) }
                    if project.stashCount > 0 { Chip(text: "stash \(project.stashCount)", tint: .secondary) }
                    if let b = currentBranch, b.pendingCommits > 0 {
                        Chip(text: L10n.t("board.chip.pending", b.pendingCommits), tint: .blue)
                    }
                    // 分支行：追踪数组拿不到时退回引擎声明的当前分支名。
                    // 「没有分支记录」和「这个项目没有分支」是两回事。
                    if let b = currentBranch {
                        Chip(text: L10n.t("board.chip.branch", b.name), tint: .secondary)
                    } else if !project.currentBranch.isEmpty {
                        Chip(text: L10n.t("board.chip.branch", project.currentBranch), tint: .secondary)
                    }
                }
            }

            Divider()

            HStack(spacing: DSSpacing.sm) {
                Button {
                    model.startUpdate(project, deep: false)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(L10n.t("workbar.shallow"))
                .accessibilityLabel(A11y.label(L10n.t("workbar.shallow")))
                .disabled(model.busyProject == project.name || model.busyAll)

                Button {
                    generateBrief()
                } label: {
                    Image(systemName: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(L10n.t("board.brief"))
                .accessibilityLabel(A11y.label(L10n.t("board.brief")))
                .disabled(briefBusy)

                Spacer()
                // 最后一次提交时间。看板的价值就是「多久没人动它」，
                // 只写一句「暂无新变化」回答不了这个问题。
                if let age = project.daysSinceLastCommit {
                    Text(age == 0 ? L10n.t("board.committedToday") : L10n.t("board.committedDaysAgo", age))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                } else {
                    Text(L10n.t("board.committedUnknown"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, DSSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                model.go(.project(project.name))
                openWindow(id: "panel")
                await model.loadProject(project.name)
            }
        }
        .sheet(isPresented: $briefSheet) {
            AIResultSheet(
                title: L10n.t("board.briefTitle", project.name),
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
                briefError = EngineError.userMessage(for: error)
            }
            briefBusy = false
        }
    }
}
