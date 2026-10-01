// MilestonesView.swift — 里程碑管理页。
// 行内直操作：点击行跳项目；··· 菜单 = 达成/重开/放弃/打开项目/删除（右键同效）。
import SwiftUI

struct MilestonesView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAddSheet = false
    /// 搜索词。空 = 不过滤。
    @State private var query = ""

    /// 过滤后的里程碑。判定在 SearchFilter（纯函数，可测）。
    private var shown: [MilestoneItem] {
        SearchFilter.filter(model.milestones, query: query) { $0.name }
    }

    var body: some View {
        Group {
            // ⚠️ 判定顺序是刻意的：**先看读没读出来，再看空不空**。
            // 原来只有 `SearchFilter.emptyReason(…)`，于是「读取失败」与
            // 「真的还没有里程碑」都渲染成「里程碑绑定 git tag 后…」——
            // 用户据此以为是自己还没建，于是一直不去建。
            if case .failed(let msg) = model.milestonesState {
                EmptyState(
                    icon: "exclamationmark.triangle",
                    title: "里程碑读不出来",
                    subtitle: msg
                )
            } else if model.milestonesState.phase(hasContent: !model.milestones.isEmpty) == .loading {
                ProgressView("读取里程碑…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let reason = SearchFilter.emptyReason(
                allCount: model.milestones.count, shownCount: shown.count, query: query) {
                EmptyState(
                    icon: "flag.2.crossed",
                    title: SearchFilter.emptyText(reason, noun: "里程碑"),
                    subtitle: reason == .noData
                        ? "里程碑绑定 git tag 后，tag 出现即自动判定达成"
                        : "换个关键词，或清空搜索框看全部"
                )
            } else {
                List {
                    Section {
                        ForEach(shown) { m in
                            MilestoneRow(milestone: m)
                        }
                    } header: {
                        HStack {
                            Text("全部里程碑（\(model.milestones.count)）")
                            Spacer()
                            // 过滤生效时必须说清「这是过滤后的」，
                            // 否则 8 条里只列 3 条会被读成「就这 3 个」
                            if let s = SearchFilter.resultSummary(
                                allCount: model.milestones.count, shownCount: shown.count,
                                noun: "里程碑") {
                                Text(s)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let c = model.dashboard?.milestones.counts {
                                Text("进行中 \(c.open) · 已达成 \(c.done) · 已放弃 \(c.dropped)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "搜索里程碑名称")
        .navigationTitle("里程碑")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("新建里程碑", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMilestoneSheet()
                .environmentObject(model)
        }
        .task { await model.fetchMilestones() }
    }
}

// MARK: - 行

struct MilestoneRow: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var model: AppModel
    let milestone: MilestoneItem

    /// 待确认的破坏性动作。nil = 没在等确认。
    ///
    /// ⚠️ 原来「删除」「放弃」是裸按钮，点一下直接调引擎 ——
    /// 而 `removeMilestone`（引擎 kernel/milestones.cj:249）是直接剔除 + saveMilestones，
    /// **不留备份、没有回收站**，点错了就没了。
    @State private var pendingAction: DestructiveAction?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconTint)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(milestone.projectName)
                        .foregroundStyle(.secondary)
                    Text(milestone.name)
                        .font(.headline)
                    if milestone.tagReached {
                        Chip(text: "tag ✓", tint: .green)
                    }
                }
                if !milestone.description.isEmpty {
                    Text(milestone.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    if !milestone.tagName.isEmpty && !milestone.tagReached {
                        Text("tag \(milestone.tagName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    // ⚠️ 原来判 `commitsSince > 0`，而读不出来时引擎给 -1 ——
                    // 于是「提交数读不出来」和「0 提交」都不显示任何东西，
                    // 两者在 UI 上完全同构。引擎恒发 commitsSinceReadable 就是为了区分。
                    if milestone.commitsSinceReadable {
                        if milestone.commitsSince > 0 {
                            Text("创建以来 \(milestone.commitsSince) 提交")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        // 引擎给了原因就用原因。「提交数读不出来」只说了现象，
                        // 而原因决定用户该做什么（挂掉的盘 ≠ 坏掉的 .git）。
                        // 引擎恒发 unverifiedReason，这行以前拿不到它。
                        Text(milestone.unverifiedNote)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(milestone.statusLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(statusTint)
                if !milestone.dueText.isEmpty {
                    Text("目标 \(milestone.targetDate) · \(milestone.dueText)")
                        .font(.caption2)
                        .foregroundStyle(milestone.overdue ? .red : .secondary)
                } else if !milestone.targetDate.isEmpty {
                    Text("目标 \(milestone.targetDate)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // 行内直达按钮（不用 Menu：List 行内 Menu 命中率不可靠）
            HStack(spacing: 2) {
                if milestone.status == "open" {
                    actionButton("达成", "checkmark.circle.fill", .green) {
                        Task { await model.milestoneAction(milestone, action: "done") }
                    }
                }
                // unknown（仓库读不出来）时不给「重开」按钮：引擎会把 open
                // 按「tag 达成即自动完成」算回 unknown，用户点了只会看到没变化。
                if milestone.status != "open" && !milestone.isUnknown {
                    actionButton("重开", "arrow.counterclockwise.circle.fill", .blue) {
                        Task { await model.milestoneAction(milestone, action: "reopen") }
                    }
                }
                actionButton("删除", "trash.fill", .red) {
                    pendingAction = .removeMilestone
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                model.go(.project(milestone.projectName))
                openWindow(id: "panel")
                await model.loadProject(milestone.projectName)
            }
        }
        .contextMenu { rowActions }
        .confirmationDialog(
            pendingAction.map { DestructiveGuard.title(for: $0, subject: subject) } ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(DestructiveGuard.confirmTitle(for: action), role: DestructiveGuard.isDestructiveRole(for: action) ? .destructive : nil) {
                Task {
                    await model.milestoneAction(milestone, action: action.engineAction)
                    pendingAction = nil
                }
            }
        } message: { action in
            Text(DestructiveGuard.message(for: action, subject: subject))
        }
    }

    /// 确认框里点名的主体。空名会渲染成「删除里程碑「」？」，用户不知道在删什么。
    private var subject: String {
        DestructiveGuard.safeSubject(milestone.name)
    }

    @ViewBuilder
    private var rowActions: some View {
        if milestone.status != "done" {
            Button("标记达成") { Task { await model.milestoneAction(milestone, action: "done") } }
        }
        if milestone.status != "open" {
            Button("重新打开") { Task { await model.milestoneAction(milestone, action: "reopen") } }
        }
        if milestone.status != "dropped" {
            Button("放弃") { pendingAction = .dropMilestone }
        }
        Divider()
        Button("打开项目") {
            Task {
                model.go(.project(milestone.projectName))
                openWindow(id: "panel")
                await model.loadProject(milestone.projectName)
            }
        }
        Divider()
        Button("删除", role: .destructive) { pendingAction = .removeMilestone }
    }

    private func actionButton(_ label: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .foregroundStyle(tint.opacity(0.75))
                .font(.subheadline)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(A11y.label(fromHelp: label, fallback: "里程碑操作"))
    }

    private var icon: String {
        if milestone.status == "done" { return "checkmark.circle.fill" }
        if milestone.status == "dropped" { return "xmark.circle" }
        // unknown 必须有自己的图标：原来落到 circle.dashed（进行中的外观），
        // 配合 statusLabel 缺失就成了「一切正常」的样子。
        if milestone.isUnknown { return "questionmark.circle.fill" }
        return milestone.overdue ? "exclamationmark.circle.fill" : "circle.dashed"
    }

    private var iconTint: Color {
        if milestone.status == "done" { return .green }
        if milestone.status == "dropped" { return .secondary }
        // 读不出来用橙色报警，不能用蓝色（蓝 = 正常进行中）
        if milestone.isUnknown { return .orange }
        return milestone.overdue ? .red : .blue
    }

    private var statusTint: Color {
        if milestone.status == "done" { return .green }
        if milestone.status == "dropped" { return .secondary }
        if milestone.isUnknown { return .orange }
        return milestone.overdue ? .red : .primary
    }
}

// MARK: - 新建里程碑

struct AddMilestoneSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var project = ""
    @State private var name = ""
    @State private var tag = ""
    @State private var hasDate = false
    @State private var date = Date().addingTimeInterval(30 * 86400)
    @State private var desc = ""
    @State private var submitting = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("项目", selection: $project) {
                    ForEach(model.projects) { p in
                        Text(p.name).tag(p.name)
                    }
                }
                TextField("名称（如 v1.0）", text: $name)
                TextField("绑定 tag（可选，tag 存在即自动达成）", text: $tag)
                Toggle("设定目标日期", isOn: $hasDate)
                if hasDate {
                    DatePicker("目标日期", selection: $date, displayedComponents: .date)
                }
                TextField("描述（可选）", text: $desc)
            }
            .formStyle(.grouped)

            if let err = errorText {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(project.isEmpty || name.isEmpty || submitting)
                    .padding(.leading, 8)
            }
            .padding()
        }
        .frame(width: 440, height: 340)
        .onAppear {
            if project.isEmpty {
                project = model.selection.flatMap {
                    if case .project(let name) = $0 { return name }
                    return nil
                } ?? model.projects.first?.name ?? ""
            }
        }
    }

    private func submit() {
        submitting = true
        errorText = nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        Task {
            do {
                try await model.addMilestone(
                    project: project,
                    name: name,
                    tag: tag,
                    targetDate: hasDate ? formatter.string(from: date) : "",
                    description: desc
                )
                dismiss()
            } catch {
                errorText = EngineError.userMessage(for: error)
            }
            submitting = false
        }
    }
}
