// MilestonesView.swift — 里程碑管理页。
// 行内直操作：点击行跳项目；··· 菜单 = 达成/重开/放弃/打开项目/删除（右键同效）。
import SwiftUI

struct MilestonesView: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject var model: AppModel
    @State private var showAddSheet = false
    /// 搜索词。空 = 不过滤。
    @State private var query = ""
    /// 只看某一个仓库的里程碑。nil = 全部。
    ///
    /// ⚠️ **这里原来写的是「从 `model.selection` 读当前范围」——
    ///    那是一个恒为 nil 的控件，本页是我亲手做出来的第二个「摆而不动」。**
    ///    `MilestonesView` 只在 `model.selection == .milestones` 时才被渲染
    ///    （PanelView 的 switch），所以 `case .project(let n)? = model.selection`
    ///    在这个视图里**永远不成立**。
    ///    实测：选中 atlas → 点侧栏「里程碑」→ 页面照样摊开 3 个仓库，
    ///    因为切到里程碑的那一刻 selection 就变成 `.milestones` 了，
    ///    上一个视图的范围根本没被记住。
    ///    顶栏那个范围选择器也是同一套推导，所以它俩**看起来是一致的**
    ///    （都显示「全局看板」），一致并不代表这个控件有用。
    ///
    ///    真正缺的能力是：里程碑是唯一能改数据的视图，却没法只管一个仓库。
    ///    所以这里给它**自己的**筛选状态（就像搜索框那样），
    ///    默认全部，用户自己收窄 —— 一个真能用的控件，
    ///    好过一个原理上永远为 nil 的联动。
    @State private var projectFilter: String?

    /// 明细里有里程碑的项目名（按首现顺序）。
    private var knownProjects: [String] {
        var order: [String] = []
        for m in model.milestones where !order.contains(m.projectName) {
            order.append(m.projectName)
        }
        return order
    }

    /// 范围收窄后的明细。判定在 `DashMilestoneScope`（纯函数，可测）。
    private var scoped: [MilestoneItem] {
        DashMilestoneScope.items(model.milestones, project: projectFilter)
    }

    /// 再叠搜索词。判定在 SearchFilter（纯函数，可测）。
    private var shown: [MilestoneItem] {
        SearchFilter.filter(scoped, query: query) { $0.name }
    }

    /// 明细的分组统计。**不读全局 counts** —— 那个没有项目维度，
    /// 收窄到单仓库后继续报它，就是把全局完成率说成这个仓库的。
    private var tally: (open: Int, done: Int, dropped: Int, unknown: Int) {
        DashMilestoneScope.tally(shown)
    }

    /// 明细是否等于全部。不完整时分组统计只是下界，必须说出来。
    private var detailComplete: Bool {
        DashMilestoneScope.isComplete(model.milestones, counts: model.dashboard?.milestones.counts)
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
                    title: L10n.t("ms.page.unreadable"),
                    subtitle: msg
                )
            } else if model.milestonesState.phase(hasContent: !model.milestones.isEmpty) == .loading {
                ProgressView(L10n.t("ms.page.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let reason = SearchFilter.emptyReason(
                allCount: scoped.count, shownCount: shown.count, query: query) {
                EmptyState(
                    icon: "flag.2.crossed",
                    title: SearchFilter.emptyText(reason, noun: L10n.t("nav.milestones"), en: L10n.shared.language.usesEnglishFacts),
                    subtitle: emptySubtitle(reason)
                )
            } else {
                VStack(spacing: 0) {
                    milestoneFilterBar
                    Divider()
                    List {
                    // ⚠️ 原来是一整个 `Section` 把所有仓库的里程碑摊平。
                    //    里程碑是**绑在项目上**的，摊平之后「这条属于哪个仓库」
                    //    只剩一行小字，多仓库时根本分不清谁是谁。
                    ForEach(DashMilestoneScope.groups(shown), id: \.project) { group in
                        Section {
                            ForEach(group.items) { m in
                                MilestoneRow(milestone: m)
                            }
                        } header: {
                            // 单仓库范围时分组标题就是那个仓库本身，
                            // 不重复写「全部里程碑（N）」。
                            HStack {
                                Text(projectFilter == nil
                                     ? group.project
                                     : L10n.t("ms.group.count", group.project, group.items.count))
                                Spacer()
                                if let s = SearchFilter.resultSummary(
                                    allCount: scoped.count, shownCount: shown.count,
                                    noun: L10n.t("nav.milestones"), en: L10n.shared.language.usesEnglishFacts) {
                                    Text(s)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // 统计**按明细算、按当前范围算**，不读全局 counts ——
                    // 收窄到单仓库后继续报全局数字，等于把全局完成率
                    // 说成这个仓库的完成率。unknown 单列，不混进任何一侧。
                    Section {
                        HStack(spacing: DSSpacing.md) {
                            stat(L10n.t("ms.filter.open"), tally.open, .secondary)
                            stat(L10n.t("ms.filter.done"), tally.done, .green)
                            stat(L10n.t("ms.filter.dropped"), tally.dropped, .secondary)
                            if tally.unknown > 0 {
                                stat(L10n.t("ms.filter.unreadable"), tally.unknown, .orange)
                            }
                            Spacer()
                        }
                        .font(.callout)
                        .padding(.vertical, DSSpacing.xs)

                        if !detailComplete {
                            // 明细被窗口截过 ⇒ 上面那些数只是**下界**。
                            // 静默报一个偏小的数，与「上限当全量」是同一族谎报。
                            Label(
                                L10n.t("ms.detailPartial", model.milestones.count)
                                + L10n.t("ms.detailPartial2", model.dashboard?.milestones.counts.readCount ?? 0)
                                + L10n.t("ms.detailPartial3"),
                                systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text(projectFilter.map { L10n.t("ms.scope.project", $0) } ?? L10n.t("ms.scope.all"))
                    }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: L10n.t("ms.search.placeholder"))
        .navigationTitle(L10n.t("ms.page.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label(L10n.t("ms.new"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMilestoneSheet()
                .environmentObject(model)
        }
        .task { await model.fetchMilestones() }
    }

    /// 仓库筛选条。**常驻内容区顶部**，不放工具栏。
    ///
    /// ⚠️ 原来放工具栏，实测 SwiftUI 在 1100pt 窗口下把 `Label` 的标题
    /// 压掉只剩图标 —— 于是「正在筛 atlas」和「没筛」长得一模一样，
    /// 而筛过之后列表变短，用户会以为里程碑被删了。
    /// 一个看不出当前状态的筛选控件，等于没有状态。
    /// 筛选条自己把「筛到谁 / 筛掉了多少」写出来。
    private var milestoneFilterBar: some View {
        HStack(spacing: DSSpacing.md) {
            Text(L10n.t("ms.scope.repo"))
                .font(DSTypography.label)
                .foregroundStyle(DSColor.textSecondary)

            Picker("", selection: $projectFilter) {
                Text(L10n.t("ms.scope.all")).tag(String?.none)
                ForEach(knownProjects, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
            .labelsHidden()
            .frame(width: 180)
            .help(L10n.t("ms.scope.repo.help"))
            .accessibilityLabel(A11y.label(L10n.t("ms.scope.repo.a11y")))
            .disabled(knownProjects.isEmpty)

            // 筛选生效时说清「从多少条里筛到多少条」——
            // 只报筛后的条数，读者没法判断是被筛掉了还是本来就没那么多。
            if projectFilter != nil || !query.isEmpty {
                Text(L10n.t("ms.filtered", shown.count, scoped.count))
                    .font(DSTypography.label)
                    .foregroundStyle(DSColor.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
    }

    /// 空态副说明。**收窄到单仓库后，「没有里程碑」有两种完全不同的原因**：
    /// 这个仓库真的没有 vs 这个仓库有但全被搜索词滤掉了 ——
    /// 更要紧的是，还有一种是「范围里根本没有里程碑数据」。
    private func emptySubtitle(_ reason: SearchFilter.Empty) -> String {
        if let p = projectFilter, scoped.isEmpty, reason == .noData {
            return L10n.t("ms.empty.project", p)
        }
        return reason == .noData
            ? L10n.t("ms.empty.hint")
            : L10n.t("ms.empty.search")
    }

    private func stat(_ title: String, _ n: Int, _ tint: Color) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text("\(n)").font(.body.weight(.semibold)).foregroundStyle(tint)
            Text(title).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 行

struct MilestoneRow: View {
    @ObservedObject private var l10n = L10n.shared
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
        HStack(spacing: DSSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(iconTint)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DSSpacing.sm) {
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
                            Text(L10n.t("ms.row.since", String(milestone.commitsSince)))
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
                    Text(L10n.t("ms.row.due", milestone.targetDate, milestone.dueText))
                        .font(.caption2)
                        .foregroundStyle(milestone.overdue ? .red : .secondary)
                } else if !milestone.targetDate.isEmpty {
                    Text(L10n.t("ms.row.dueOnly", milestone.targetDate))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // 行内直达按钮（不用 Menu：List 行内 Menu 命中率不可靠）
            HStack(spacing: 2) {
                if milestone.status == "open" {
                    actionButton(L10n.t("ms.row.done"), "checkmark.circle.fill", .green) {
                        Task { await model.milestoneAction(milestone, action: "done") }
                    }
                }
                // unknown（仓库读不出来）时不给「重开」按钮：引擎会把 open
                // 按「tag 达成即自动完成」算回 unknown，用户点了只会看到没变化。
                if milestone.status != "open" && !milestone.isUnknown {
                    actionButton(L10n.t("ms.row.reopen"), "arrow.counterclockwise.circle.fill", .blue) {
                        Task { await model.milestoneAction(milestone, action: "reopen") }
                    }
                }
                actionButton(L10n.t("ms.row.delete"), "trash.fill", .red) {
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
            Button(L10n.t("ms.action.done")) { Task { await model.milestoneAction(milestone, action: "done") } }
        }
        if milestone.status != "open" {
            Button(L10n.t("ms.action.reopen")) { Task { await model.milestoneAction(milestone, action: "reopen") } }
        }
        if milestone.status != "dropped" {
            Button(L10n.t("ms.action.drop")) { pendingAction = .dropMilestone }
        }
        Divider()
        Button(L10n.t("ms.action.openProject")) {
            Task {
                model.go(.project(milestone.projectName))
                openWindow(id: "panel")
                await model.loadProject(milestone.projectName)
            }
        }
        Divider()
        Button(L10n.t("ms.row.delete"), role: .destructive) { pendingAction = .removeMilestone }
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
        .accessibilityLabel(A11y.label(fromHelp: label, fallback: L10n.t("ms.actions.a11y")))
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
    @ObservedObject private var l10n = L10n.shared
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
    /// 新建里程碑的**第一个该被填的字段**是名称，不是项目。
    /// 原来焦点不在任何地方，Sheet 一打开用户得先用鼠标点一下才能打字。
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker(L10n.t("ms.form.project"), selection: $project) {
                    ForEach(model.projects) { p in
                        Text(p.name).tag(p.name)
                    }
                }
                TextField(L10n.t("ms.form.name"), text: $name)
                    .focused($nameFocused)
                TextField(L10n.t("ms.form.tag"), text: $tag)
                Toggle(L10n.t("ms.form.setDate"), isOn: $hasDate)
                if hasDate {
                    DatePicker(L10n.t("ms.form.date"), selection: $date, displayedComponents: .date)
                }
                TextField(L10n.t("ms.form.desc"), text: $desc)
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
                Button(L10n.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("ms.form.create")) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(project.isEmpty || name.isEmpty || submitting)
                    .padding(.leading, DSSpacing.sm)
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
            // 放在项目默认值之后：onAppear 里连着改 @State 与 @FocusState 时，
            // 先补齐前置状态，焦点才不会被同一次刷新吃掉。
            nameFocused = true
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
