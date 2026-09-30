// DetailViews.swift — 项目详情页与仪表盘页。
import SwiftUI

// MARK: - 项目详情

struct ProjectDetailView: View {
    @EnvironmentObject var model: AppModel
    let projectName: String
    @State private var commitMessage = ""

    private var project: ProjectStatus? {
        model.projectDetails[projectName] ?? model.projects.first { $0.name == projectName }
    }

    var body: some View {
        Group {
            if let p = project {
                content(p)
            } else {
                ProgressView("加载 \(projectName) …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await model.loadProject(projectName)
            await model.loadDocs(projectName)
        }
    }

    private func content(_ p: ProjectStatus) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(p)
                if let err = p.error {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    Card(title: "工程脉搏") { pulseCard(p) }
                    Card(title: "提交构成（近期）") { commitTypeCard(p) }
                }
                Card(title: "分支进度（\(p.branches.count)）") { branchCard(p) }
                if p.isGit {
                    Card(title: "Git 操作") { gitCard(p) }
                }
                if let journal = p.journal, !journal.isEmpty {
                    Card(title: "进度日志") { journalCard(journal) }
                }
                if let docs = model.projectDocs[projectName], !docs.isEmpty {
                    ForEach(docs) { doc in
                        Card(title: doc.file) {
                            MarkdownView(text: doc.content)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    // MARK: Git 操作

    private func gitCard(_ p: ProjectStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                gitOpButton(p, "拉取", "arrow.down.to.line", "pull")
                gitOpButton(p, "推送", "arrow.up.to.line", "push")
                gitOpButton(p, "抓取", "arrow.triangle.2.circlepath", "fetch")
                Divider().frame(height: 16)
                gitOpButton(p, "暂存", "archivebox", "stash")
                gitOpButton(p, "恢复", "tray.and.arrow.down", "unstash")
                Spacer()
                if model.busyProject == p.name {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                TextField("提交信息（提交全部改动）", text: $commitMessage)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { doCommit(p) }
                Button("提交") { doCommit(p) }
                    .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty || model.busyProject == p.name)
            }

            if let out = model.lastGitOpOutput {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: out.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(out.ok ? Color.green : Color.red)
                            .font(.caption)
                        Text(out.ok ? "成功" : "失败")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(out.ok ? Color.green : Color.red)
                        Spacer()
                        Button {
                            model.lastGitOpOutput = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("清除输出")
                    }
                    ScrollView {
                        Text(out.text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 130)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func gitOpButton(_ p: ProjectStatus, _ label: String, _ icon: String, _ op: String) -> some View {
        Button {
            Task { await model.gitOp(p, op: op) }
        } label: {
            Label(label, systemImage: icon)
        }
        .disabled(model.busyProject == p.name || model.busyAll)
    }

    private func doCommit(_ p: ProjectStatus) {
        let msg = commitMessage.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        let message = msg
        commitMessage = ""
        Task { await model.gitOp(p, op: "commit", message: message) }
    }

    // MARK: 头部

    private func header(_ p: ProjectStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(p.name)
                        .font(.title.weight(.semibold))
                    if !p.isGit {
                        Chip(text: "非 git", tint: .gray)
                    }
                    if model.busyProject == p.name {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(p.headline)
                    .foregroundStyle(.secondary)
                Text(p.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Button("浅更新") {
                        Task { await model.update(p, deep: false) }
                    }
                    .disabled(model.busyProject != nil || model.busyAll)
                    Button("深度更新") {
                        Task { await model.update(p, deep: true) }
                    }
                    .disabled(model.busyProject != nil || model.busyAll)
                }
                HStack(spacing: 10) {
                    Button {
                        SysOpen.revealInFinder(p.path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 中显示")
                    Button {
                        SysOpen.openTerminal(at: p.path)
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .buttonStyle(.borderless)
                    .help("在终端中打开")
                    if !p.remote.isEmpty {
                        Button {
                            SysOpen.openRemote(p.remote)
                        } label: {
                            Image(systemName: "globe")
                        }
                        .buttonStyle(.borderless)
                        .help("打开远端仓库")
                    }
                }
            }
        }
    }

    // MARK: 工程脉搏

    @ViewBuilder
    private func pulseCard(_ p: ProjectStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let h = p.mergeHint, h.kind != "merged" {
                Label(h.description, systemImage: h.kind == "fast-forward" ? "arrow.up.right" : "arrow.triangle.merge")
                    .font(.callout)
                    .foregroundStyle(h.kind == "fast-forward" ? .green : .orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (h.kind == "fast-forward" ? Color.green : Color.orange).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            }
            HStack(spacing: 8) {
                Chip(text: "未提交 \(p.userDirtyCount)", tint: statTint(p.userDirtyCount))
                Chip(text: "未跟踪 \(p.untrackedCount)", tint: statTint(p.untrackedCount))
                Chip(text: "stash \(p.stashCount)", tint: statTint(p.stashCount))
                Chip(text: "工作区 \(p.worktreeCount)", tint: .secondary)
            }
            if let types = p.commitTypeLine {
                Text(types)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !p.lastCommitAgo.isEmpty {
                Text("最近提交：\(p.lastCommitAgo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("当前 \(p.currentBranch.isEmpty ? "—" : p.currentBranch) · 默认 \(p.defaultBranch.isEmpty ? "—" : p.defaultBranch)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: 提交构成

    @ViewBuilder
    private func commitTypeCard(_ p: ProjectStatus) -> some View {
        if let types = p.commitTypes, !types.isEmpty {
            let palette: [Color] = [.blue, .red, .orange, .purple, .teal, .indigo, .mint, .pink, .brown, .yellow, .cyan, .gray]
            VStack(alignment: .leading, spacing: 10) {
                SegmentedBar(segments: types.enumerated().map { i, t in
                    .init(label: t.type, value: Double(t.count), color: palette[i % palette.count])
                })
                FlowLegend(items: types.enumerated().map { i, t in
                    (t.type, "\(t.count)", palette[i % palette.count])
                })
            }
        } else {
            EmptyState(icon: "chart.bar", title: "暂无提交数据")
                .frame(height: 80)
        }
    }

    // MARK: 分支

    @ViewBuilder
    private func branchCard(_ p: ProjectStatus) -> some View {
        if p.branches.isEmpty {
            EmptyState(icon: "arrow.triangle.branch", title: "暂无进度记录", subtitle: "运行一次「浅更新」后，各分支进度会出现在这里")
                .frame(height: 90)
        } else {
            VStack(spacing: 8) {
                ForEach(p.branches) { b in
                    HStack(spacing: 10) {
                        StatusDot(status: b.status)
                        Text(b.name)
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                        if b.isCurrent {
                            Chip(text: "当前", tint: .blue)
                        }
                        if b.isDefault {
                            Chip(text: "默认", tint: .secondary)
                        }
                        Spacer()
                        Text(b.statusLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if b.pendingCommits > 0 {
                            Text("\(b.pendingCommits) 待记录")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(b.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack {
                            Text("\(b.headShort) · \(b.headAgo)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if b.aheadOfDefault > 0 {
                                Text("领先默认分支 \(b.aheadOfDefault)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .padding(.leading, 18)
                    if b.id != p.branches.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: 日志

    private func journalCard(_ journal: [JournalEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(journal) { e in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(e.modeLabel)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    Text(e.branch)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(e.summary)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    if e.commitCount > 0 {
                        Text("+\(e.commitCount)")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                if e.id != journal.last?.id {
                    Divider()
                }
            }
        }
    }
}

// MARK: - 图例（自动换行）

struct FlowLegend: View {
    let items: [(String, String, Color)]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.0) { label, value, color in
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(label)
                        .font(.caption)
                    Text(value)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 流式布局简化版：横向滚动，信息密度优先
struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) { content }
        }
        .frame(height: 20)
    }
}

// MARK: - 仪表盘

struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let d = model.dashboard {
                    dashboardContent(d)
                } else {
                    ProgressView("汇总项目群…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .frame(minHeight: 300)
                }
            }
            .padding(18)
        }
        .task { await model.fetchDashboard() }
    }

    private func dashboardContent(_ d: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // 统计卡
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(label: "项目总数", value: "\(d.projects.total)")
                StatCard(label: "近 7 天活跃", value: "\(d.projects.active7d)", tint: .green)
                StatCard(label: "近 30 天活跃", value: "\(d.projects.active30d)")
                StatCard(label: "有未提交改动", value: "\(d.projects.dirty)", tint: statTint(d.projects.dirty))
            }

            // 工作面
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(label: "分支", value: "\(d.work.branches)")
                StatCard(label: "待合入分支", value: "\(d.work.mergeCandidates)", tint: statTint(d.work.mergeCandidates))
                StatCard(label: "未跟踪文件", value: "\(d.work.untrackedFiles)", tint: statTint(d.work.untrackedFiles))
                StatCard(label: "stash", value: "\(d.work.stashes)")
            }

            // 语言分布 + 里程碑
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                Card(title: "语言分布（跟踪文件数）") {
                    if d.languages.isEmpty {
                        EmptyState(icon: "text.justify", title: "暂无数据").frame(height: 70)
                    } else {
                        let palette: [Color] = [.blue, .purple, .orange, .teal, .pink, .indigo, .mint, .yellow]
                        VStack(alignment: .leading, spacing: 10) {
                            SegmentedBar(segments: d.languages.prefix(8).enumerated().map { i, l in
                                .init(label: l.language, value: Double(l.count), color: palette[i % palette.count])
                            })
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(d.languages.prefix(8).enumerated().map { i, l in
                                    (l.language, l.count, palette[i % palette.count])
                                }, id: \.0) { lang, count, color in
                                    HStack {
                                        Circle().fill(color).frame(width: 7, height: 7)
                                        Text(lang).font(.caption)
                                        Spacer()
                                        Text("\(count)")
                                            .font(.system(.caption, design: .rounded).weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Card(title: "里程碑（进行中 \(d.milestones.counts.open) · 已达成 \(d.milestones.counts.done)）") {
                    if d.milestones.items.isEmpty {
                        EmptyState(icon: "flag", title: "暂无里程碑", subtitle: "在「里程碑」页添加").frame(height: 70)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(d.milestones.items.prefix(5)) { m in
                                milestoneRow(m)
                            }
                        }
                    }
                }
            }

            // 活跃项目
            if !d.activeProjects.isEmpty {
                Card(title: "近 7 天活跃项目（\(d.activeProjects.count)）") {
                    VStack(spacing: 7) {
                        ForEach(d.activeProjects, id: \.name) { a in
                            HStack {
                                Circle().fill(.green).frame(width: 7, height: 7)
                                Text(a.name).font(.callout)
                                Spacer()
                                Text(a.lastCommitAgo)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(a.headline)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 280, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    private func milestoneRow(_ m: MilestoneItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: m.status == "done" ? "checkmark.circle.fill" : (m.overdue ? "exclamationmark.circle.fill" : "circle.dashed"))
                .foregroundStyle(m.status == "done" ? Color.green : (m.overdue ? Color.red : .secondary))
            Text(m.projectName)
                .foregroundStyle(.secondary)
            Text(m.name)
                .font(.callout.weight(.medium))
            Spacer()
            if !m.dueText.isEmpty {
                Text(m.dueText)
                    .font(.caption)
                    .foregroundStyle(m.overdue ? .red : .secondary)
            }
        }
    }
}
