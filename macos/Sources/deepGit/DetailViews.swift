// DetailViews.swift — 项目详情页与仪表盘页。
import SwiftUI

// MARK: - 项目详情

struct ProjectDetailView: View {
    @EnvironmentObject var model: AppModel
    let projectName: String
    @State private var commitMessage = ""
    /// 待确认的「提交全部改动」。nil = 没在等确认。
    ///
    /// ⚠️ 这条原来点一下就提交。引擎的 `commit` 走 `git add -A`
    /// （kernel/git.cj:1792）—— 提交的是**整个工作区**，不是用户挑的那几个文件。
    /// 而「全部」两个字只藏在输入框的 placeholder 里，一填就被盖掉。
    @State private var pendingCommit: ProjectStatus?

    private var project: ProjectStatus? {
        model.projectDetails[projectName] ?? model.projects.first { $0.name == projectName }
    }

    var body: some View {
        Group {
            if let p = project {
                content(p)
            } else if let err = model.projectLoadErrors[projectName] {
                // ⚠️ 原来这里只有 else → ProgressView，于是项目**不存在**或读不出来时
                // 主区永远转圈：既不报错也不停，用户会一直等一个不会来的结果。
                // 这正是「把读不出来说成还在读」。
                EmptyState(
                    icon: "exclamationmark.triangle",
                    title: "读不出来：\(projectName)",
                    subtitle: err
                )
                .padding(DSSpacing.xxl)
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
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header(p)
                if let err = p.error {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .padding(DSSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tinted(.red.opacity(0.08))
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    Card(title: "工程脉搏") { pulseCard(p) }
                    Card(title: "提交构成（近期）") { commitTypeCard(p) }
                }
                // ⚠️ 提交卡在页头那排按钮**下面**（不是原来的中下部）。
                //    页头已经放了拉取/推送/抓取/暂存/恢复，
                //    把提交留在四张卡之后等于「同一组动作被拆成两半、还隔了四张卡」。
                if p.isGit {
                    Card(title: "提交改动") { gitCard(p) }
                }
                // ⚠️ branches.count 是引擎**追踪到基线**的数量，不是仓库真实分支数。
                // 实测 16 个分支的仓库这里只显示 7 个；刚注册还没 track 过的仓库显示 0，
                // 而仓库实际有 2 个分支 —— 字面写「分支进度（0）」会让人认定仓库没有分支。
                // repoBranchCount = -1 时更要说明「读不出来」，不能显示 0。
                Card(title: "分支进度 · \(p.branchScopeLine)") { branchCard(p) }
                // ⚠️ 里程碑原来**只在里程碑页里有**。
                //    而这一页才是「这个仓库的独立管控页」——
                //    仪表盘卡、项目卡、管控页三处都不显示里程碑，
                //    用户要管一个仓库的里程碑，得先记住它叫什么、
                //    再去里程碑页用筛选器把它筛出来。
                //    里程碑是「目标达成度」，正是管控页该回答的问题。
                milestoneCard(p)
                if let journal = p.journal, !journal.isEmpty {
                    // 引擎的 journal 上限是 8 条（light=3 / JSON 恒 8），
                    // 而 progress.entryCount 是**真实条数**。数组长度当全量 ⇒
                    // 用户看到 8 条就以为「就更新过 8 次」。
                    Card(title: "进度日志 · \(p.progress.entryCountLine)") { journalCard(journal, of: p) }
                }
                // ⚠️ 原来是 `if let docs = …, !docs.isEmpty { 画卡片 }` ——
                //    三种情况（正在读 / 没有文档 / 读不出来）**渲染成同一个画面**：
                //    什么都不画。用户据此认为「这个项目确实没有 README」，
                //    而真相可能是权限问题或引擎超时（见 Model.loadDocs 的注释）。
                switch docsPhase {
                case .content:
                    if let docs = model.projectDocs[projectName] {
                        ForEach(docs) { doc in
                            Card(title: doc.file) {
                                MarkdownView(text: doc.content)
                            }
                        }
                    }
                case .failed(let msg):
                    Card(title: "托管文档") {
                        Label("读不出来：\(msg)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                case .loading:
                    Card(title: "托管文档") {
                        ProgressView("读取文档…")
                            .font(.caption)
                            .controlSize(.small)
                    }
                case .empty:
                    // 「真的没有文档」与「读不出来」是两件事，必须分别说。
                    Card(title: "托管文档") {
                        Text("这个项目还没有受管的文档。跑一次浅更新会生成 README / AGENTS / CLAUDE。")
                            .font(.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
            .padding(18)
        }
    }

    /// 文档区该画哪一种。判定在纯函数层 `LoadState`（可单测）。
    private var docsPhase: LoadPhase {
        let state = model.docsStates[projectName] ?? .idle
        let has = !(model.projectDocs[projectName] ?? []).isEmpty
        return state.phase(hasContent: has)
    }

    // MARK: Git 操作

    /// 页头那一排 git 操作按钮（拉取 / 推送 / 抓取 / 暂存 / 恢复）。
    ///
    /// ⚠️ 原来这张「Git 操作」卡里同时装着按钮排和提交表单。
    /// 按钮排挪到页头之后，卡里只剩提交 ——
    /// 标题也因此从「Git 操作」改成「提交改动」，
    /// 否则一个只讲提交的卡顶着「Git 操作」的名字，与页头那排对不上。
    /// 页头那一排 git 操作按钮。**唯一构造点** ——
    /// 一旦下面那张提交卡里再抄一份 `gitOpButton(...)`，
    /// 两处的可用性判定就会分叉（这里要判 `busyProject`），而那只有真点一次才发现。
    private func gitOpButtons(_ p: ProjectStatus) -> some View {
        HStack(spacing: DSSpacing.xs) {
            gitOpButton(p, "拉取", "arrow.down.to.line", "pull")
            gitOpButton(p, "推送", "arrow.up.to.line", "push")
            gitOpButton(p, "抓取", "arrow.triangle.2.circlepath", "fetch")
            Divider().frame(height: 14)
            gitOpButton(p, "暂存", "archivebox", "stash")
            gitOpButton(p, "恢复", "tray.and.arrow.down", "unstash")
            if model.busyProject == p.name {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func gitCard(_ p: ProjectStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: DSSpacing.sm) {
                TextField("提交信息（提交全部改动）", text: $commitMessage)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { pendingCommit = p }
                Button("提交") { pendingCommit = p }
                    .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty || model.busyProject == p.name)
            }

            if let out = model.lastGitOpOutput {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
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
                        .accessibilityLabel(A11y.label("清除输出"))
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
                .surface()
            }
        }
        .confirmationDialog(
            pendingCommit.map { DestructiveGuard.commitTitle(project: $0.name) } ?? "",
            isPresented: Binding(
                get: { pendingCommit != nil },
                set: { if !$0 { pendingCommit = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("全部提交", role: .destructive) {
                if let p = pendingCommit { doCommit(p) }
                pendingCommit = nil
            }
            Button("取消", role: .cancel) { pendingCommit = nil }
        } message: {
            Text(pendingCommit.map { DestructiveGuard.commitMessage(scope: commitScope($0)) } ?? "")
        }
    }

    /// 提交范围。引擎只有 `userDirtyCount` / `untrackedCount` 两个口径，
    /// 没有「已暂存」——所以那个字段恒 0，**不编造**。
    private func commitScope(_ p: ProjectStatus) -> DestructiveGuard.CommitScope {
        DestructiveGuard.CommitScope(
            trackedModified: max(p.userDirtyCount, 0),
            untracked: max(p.untrackedCount, 0),
            staged: 0
        )
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
        HStack(alignment: .top, spacing: DSSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: DSSpacing.sm) {
                    Text(p.name)
                        .font(.title.weight(.semibold))
                    // ⚠️ 状态词原来只有仪表盘项目卡有，管控页没有。
                    //    同一个仓库，仪表盘说「47 天没更新」、管控页什么都不说 ——
                    //    用户会以为管控页漏了，而实际上是两处各算各的。
                    //    现在统一走 `ProjectStatus.stateWord`（模型层那一份）。
                    Chip(text: p.stateWord.text, tint: stateTint(p.stateWord.tone))
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
                // 引擎的 warnings 之前没有任何地方显示 ——
                // 它说了「非 git 仓库：进度基于文件活动时间，不含提交历史」，
                // 而同屏的 headline 照旧显示「0 个提交」。
                // 用户据此认为"这个项目真的一个提交都没有"。
                // 披露已经存在于数据里，缺的是把它显示出来这一步。
                ForEach(p.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                // `overall.notes` 是引擎给的**另一批**事实，与 warnings 不是同一批。
                // 实测它会说「工作区有 2 处未提交改动」——
                // 而界面上除了那句笼统的 headline，没有任何地方提「2 处」。
                // 引擎算了、模型收了、界面不说 ⇒ 等于没算。
                if let notes = p.overall?.displayNotes, !notes.isEmpty {
                    ForEach(notes, id: \.self) { n in
                        Label(n, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                // `overall.summary` 是引擎对**整条提交历史**的概括
                // （实测「最近 2 个提交：新增×2」）。
                // `commitTypeLine` 说的是同一件事的另一种切法，重复画会显得啰嗦，
                // 所以这里只在**它没被别处说过**时才补位。
                if let s = p.overall?.displaySummary, p.commitTypeLine == nil {
                    Text(s)
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    ProjectBriefButton(project: p)
                    // ⚠️ 单一仓库的 git 操作**在页头**，与「项目说明」平齐。
                    //    原来它们在页面中下部的「Git 操作」卡里，而页头右侧是
                    //    「项目说明 + 更新」—— 于是最常用的两个动作被埋在
                    //    分支进度、里程碑、日志、托管文档四张卡下面，
                    //    第一屏根本看不到，而页头那一排却空着。
                    //    用户 2026-10-02 明确要求「把单一仓库的 git 操作放到顶部，
                    //    项目说明平齐」。
                    //
                    //    **提交不在这里**：它要一个提交信息输入框，按钮排塞不下，
                    //    硬塞进去会让页头多出一整行输入框把标题挤掉。
                    //    它留在下面的「提交改动」卡里。
                    if p.isGit { gitOpButtons(p) }
                    Divider().frame(height: 16)
                    UpdateActionMenu(project: p)
                }
                HStack(spacing: 10) {
                    Button {
                        SysOpen.revealInFinder(p.path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 中显示")
                    .accessibilityLabel(A11y.label("在 Finder 中显示"))
                    Button {
                        SysOpen.openTerminal(at: p.path)
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .buttonStyle(.borderless)
                    .help("在终端中打开")
                    .accessibilityLabel(A11y.label("在终端中打开"))
                    if !p.remote.isEmpty {
                        Button {
                            SysOpen.openRemote(p.remote)
                        } label: {
                            Image(systemName: "globe")
                        }
                        .buttonStyle(.borderless)
                        .help("打开远端仓库")
                        .accessibilityLabel(A11y.label("打开远端仓库"))
                    }
                }
            }
        }
    }

    // MARK: 工程脉搏

    @ViewBuilder
    private func pulseCard(_ p: ProjectStatus) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            if let h = p.mergeHint, h.kind != "merged" {
                Label(h.description, systemImage: h.kind == "fast-forward" ? "arrow.up.right" : "arrow.triangle.merge")
                    .font(.callout)
                    .foregroundStyle(h.kind == "fast-forward" ? .green : .orange)
                    .padding(DSSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tinted((h.kind == "fast-forward" ? Color.green : Color.orange).opacity(0.08),
                            radius: DSRadius.control)
            }
            HStack(spacing: DSSpacing.sm) {
                Chip(text: "未提交 \(p.userDirtyCount)", tint: statTint(p.userDirtyCount))
                Chip(text: "未跟踪 \(p.untrackedCount)", tint: statTint(p.untrackedCount))
                Chip(text: "stash \(p.stashCount)", tint: statTint(p.stashCount))
                Chip(text: "工作区 \(p.worktreeCount)", tint: .secondary)
            }
            // `dirty` 是**另一个口径**：上面那几个数是「用户改的」，
            // 这个对象是引擎判的（带 `ok` —— 读不出来时 ok 缺席/false，数字全是 0）。
            // 两行数字并排却不标口径，用户会以为它们矛盾。
            // 冲突（会丢代码的那种）必须单独顶在最前面，不能混进「N 处未提交」。
            if let d = p.dirty {
                Label(d.dirtyLine, systemImage: d.isReadable ? "square.and.pencil" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(d.isReadable ? DSColor.textSecondary : .orange)
                // 「几处」不够 —— 用户要动手时需要「哪几个」，
                // 而提交按钮就在下面那张卡里。截断由模型自己报（还有 N 个）。
                if let files = d.dirtyFilesLine {
                    Text(files)
                        .font(.caption2)
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .accessibilityLabel(A11y.label("未提交的文件"))
                        .accessibilityValue(files)
                }
            }
            // tags / manifests 是引擎给的「这是个什么项目」的事实。
            // 实测一个刚注册的项目 tags=[] manifests=[]，所以空数组一律不占位 ——
            // 画一个空的「标签」行只会让人以为这里本来该有东西而没采到。
            if let tags = p.tags, !tags.isEmpty {
                projectFacts("标签", tags)
            }
            if let mf = p.manifests, !mf.isEmpty {
                projectFacts("依赖清单", mf)
            }
            // `docs[].exists` 区分「引擎管着这个文件但还没建」与「压根没有这回事」——
            // 对用户是两件不同的事：前者是「你还没写」，后者是「这里不用写」。
            // 合成一份文件名清单就把这个区别抹掉了。
            if let docs = p.docs, !docs.isEmpty {
                projectFacts("托管文档", docs.map { "\($0.file)（\($0.exists ? "已建" : "未建")）" })
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

    /// 一行「标题：值、值、值」。tags / manifests 共用。
    ///
    /// 不用 Chip 也不用 Button：这两样都是**只读事实**，
    /// 做成可点/有底色的样子会让人以为点得动。
    private func projectFacts(_ title: String, _ values: [String]) -> some View {
        // 一行放不下就必须截断并说「还有 N 个」，不能静默截 ——
        // 静默截会让人以为标签只有前几个。
        let shown = Array(values.prefix(8))
        let hidden = values.count - shown.count
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DSColor.textTertiary)
            Text(shown.joined(separator: " · ") + (hidden > 0 ? " · 还有 \(hidden) 个" : ""))
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .accessibilityElement()
        .accessibilityLabel(A11y.label(title, value: shown.joined(separator: "、") + (hidden > 0 ? "，还有 \(hidden) 个" : "")))
    }

    // MARK: 提交构成

    @ViewBuilder
    private func commitTypeCard(_ p: ProjectStatus) -> some View {
        if let types = p.commitTypes, !types.isEmpty {
            // 切片与色板容量来自同一处（CommitTypeComposition.swift），
            // 取色顺序也只由 CommitTypeColor.palette 决定 ——
            // 原来这里内联一份 12 色字面量 + `palette[i % palette.count]`，
            // 词表一变长就把两类涂成同一个颜色（缺陷 #206）。
            let slice = commitTypeCardSlice(
                entries: types.map { (type: $0.type, count: $0.count) }
            )
            VStack(alignment: .leading, spacing: 10) {
                SegmentedBar(segments: slice.entries.enumerated().map { i, t in
                    .init(label: t.type, value: Double(t.count),
                          color: DSColor.sequence(CommitTypeColor.palette[i]))
                })
                FlowLegend(items: slice.entries.enumerated().map { i, t in
                    (t.type, "\(t.count)", DSColor.sequence(CommitTypeColor.palette[i]))
                })
                if let note = slice.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            EmptyState(icon: "chart.bar", title: "暂无提交数据")
                .frame(height: 80)
        }
    }


    // MARK: 里程碑

    /// `stateWord` 的语气 → 颜色。与看板、项目卡同一套映射。
    private func stateTint(_ tone: ProjectStatus.Liveness) -> Color {
        switch tone {
        case .unreadable, .unknown: return .red
        case .notGit:               return .gray
        case .needsAction:          return .orange
        case .engineStale, .quiet:  return .secondary
        case .recent:               return .green
        }
    }

    /// 这个仓库的里程碑。行内直接复用 `MilestoneRow`（达成 / 放弃 / 删除都在那）。
    ///
    /// 取数走 `DashMilestoneScope`（与里程碑页同一份口径）——
    /// 两页各写一遍筛选就会出现「管控页 2 条、里程碑页 3 条」。
    @ViewBuilder
    private func milestoneCard(_ p: ProjectStatus) -> some View {
        let mine = DashMilestoneScope.items(model.milestones, project: p.name)
        let t = DashMilestoneScope.tally(mine)
        Card(title: "里程碑 · \(mine.count) 条") {
            if model.milestonesState.phase(hasContent: !model.milestones.isEmpty) == .loading {
                ProgressView("读取里程碑…").frame(height: 60)
            } else if mine.isEmpty {
                // 两种「没有」必须说不同的话：这个仓库真的没建里程碑，
                // 还是里程碑数据根本读不出来。后者显示「去建里程碑」是误导。
                if case .failed(let msg) = model.milestonesState {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else {
                    EmptyState(icon: "flag.2.crossed", title: "还没有里程碑",
                                subtitle: "在「里程碑」页新建，绑定 git tag 后 tag 出现即自动判定达成")
                        .frame(height: 80)
                }
            } else {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    // 分母只取「达没达成有答案的」（done + open）。
                    // unknown 是「仓库读不出来」，算作「没达成」就是把无知说成事实。
                    let decided = t.done + t.open
                    if decided > 0 {
                        HStack(spacing: DSSpacing.sm) {
                            Text("达成率")
                                .font(DSTypography.label)
                                .foregroundStyle(DSColor.textSecondary)
                            Text("\(Int((Double(t.done) * 100 / Double(decided)).rounded()))%")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                            Text("\(t.done)/\(decided)")
                                .font(DSTypography.label)
                                .foregroundStyle(DSColor.textSecondary)
                                .monospacedDigit()
                            if t.unknown > 0 {
                                Text("· \(t.unknown) 个读不出来（不计入分母）")
                                    .font(DSTypography.label)
                                    .foregroundStyle(.orange)
                            }
                        }
                        ProgressView(value: Double(t.done), total: Double(decided))
                    }
                    Divider()
                    ForEach(mine) { m in
                        MilestoneRow(milestone: m)
                    }
                }
            }
        }
    }

    // MARK: 分支

    @ViewBuilder
    private func branchCard(_ p: ProjectStatus) -> some View {
        if p.branches.isEmpty {
            EmptyState(icon: "arrow.triangle.branch", title: "暂无进度记录", subtitle: "运行一次「浅更新」后，各分支进度会出现在这里")
                .frame(height: 90)
        } else {
            VStack(spacing: DSSpacing.sm) {
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
                        // `provider` 决定上面那句话是谁说的。规则引擎说的和 AI 说的
                        // 可信度不一样，混成同一种语气就是隐瞒来源。
                        //
                        // 只在**偏离默认**时挂徽章：实测没配 AI 时恒为 "rules"，
                        // 每行都挂一个「规则」只会训练用户忽略徽章 ——
                        // 而这个徽章真正要说的是「这句是模型推出来的，不是数出来的」。
                        if b.providerLabel != "规则" {
                            Chip(text: b.providerLabel, tint: DSColor.ai)
                        }
                        if b.pendingCommits > 0 {
                            // ⚠️ 基线被重建过 ⇒ 原提交区间不可比，这个数字已无意义。
                            // 照报「待记录 37」会让用户以为漏记了 37 个提交。
                            Text("待记录数已失效（基线重建）")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if b.baselineReset {
                            Text("基线已重建")
                                .font(.caption)
                                .foregroundStyle(DSColor.textTertiary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(b.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        // `headSubject` 是 HEAD 提交**原文标题**，`summary` 是概括。
                        // 用户报 bug 时要的是原文，不是概括 —— 挂在短 SHA 上做悬停与朗读。
                        // `head` 是完整 SHA：7 位排查问题时不够。
                        Text("\(b.headShort) · \(b.headAgo)")
                            .font(.caption2)
                            .foregroundStyle(DSColor.textTertiary)
                            .help(b.headTip)
                            .accessibilityLabel(A11y.label("当前提交"))
                            .accessibilityValue(b.headTip)
                        // `highlights` 是**逐条**的具体事件（实测 ["更新：“第二次”", …]），
                        // 与上面那句概括不同。用户问「这条分支最近动了什么」，
                        // 答案在这个数组里 —— 丢掉它就只能给一句概括。
                        if let hs = b.highlights, !hs.isEmpty {
                            ForEach(hs, id: \.self) { h in
                                Text("· \(h)")
                                    .font(.caption2)
                                    .foregroundStyle(DSColor.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        HStack {
                            // ⚠️ 同上：基线重建后这个差值不可比，不能照报。
                            if b.aheadOfDefault > 0 && !b.baselineReset {
                                Text("领先默认分支 \(b.aheadOfDefault)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            Spacer()
                            // `staleDays` 单独一行而不是塞进上面那个 HStack：
                            // 那是「事实」（短 SHA + 多久前），而这个是「判断」
                            // （多久没更新 ⇒ 该不该管它）。混在一行里两个意思糊在一起。
                            // ⚠️ staleText 自己处理 -1：算不出来时显示「读不出来」，
                            // 不会显示成「今天更新过」。
                            Text(b.staleText)
                                .font(.caption2)
                                // ⚠️ 颜色跟**引擎的 status**，不跟 staleDays 自己再推一遍。
                                // 引擎的档位线是 3 / 14 天（progress.cj:30-36），客户端
                                // 自己写一个阈值（第一版写了 30）就会和引擎的分歧 ——
                                // 同一张卡片上左边的点与这行字说两种话。
                                // 顺带一提：原来那句三元还混了 HierarchicalShapeStyle
                                // 与 Color 两个类型，编译直接断在它上面。
                                .foregroundStyle(DSColor.color(DSStatus.from(b.status)))
                        }
                        // `nextSteps` 是引擎给的**可执行**建议。
                        // 空数组是「没有建议」而不是「不知道」——
                        // 所以只在有内容时显示，不占位。
                        if let ns = b.nextSteps, !ns.isEmpty {
                            ForEach(ns, id: \.self) { s in
                                Label(s, systemImage: "arrow.turn.down.right")
                                    .font(.caption2)
                                    .foregroundStyle(DSColor.accent)
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

    /// `of p`：截断披露要用到 journalTruncated / journalLimit / journalUnparsableLines，
    /// 它们在 ProjectStatus 上而不在条目上。原先这个函数只收数组，
    /// 拿不到窗口与全量的区分依据 —— 于是那一段什么都不敢显示。
    private func journalCard(_ journal: [JournalEntry], of p: ProjectStatus) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            ForEach(journal) { e in
                // 口径与截断必须由纯函数判定（#188）：同一个 `+N` 在浅/深
                // 两条路径上含义不同，客户端原来一律渲染成无口径的绿色徽章。
                let badge = commitCountBadge(
                    commitCount: e.commitCount,
                    scope: e.commitCountScope,
                    truncated: e.commitCountTruncated
                )
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(e.modeLabel)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .tinted(.quaternary, radius: DSRadius.control)
                    Text(e.branch)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(e.summary)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    if let text = badge.text {
                        Text(text)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            // 绿色只留给「本轮新增」。累计量用绿色等于说
                            // 「这次变好了这么多」，而那个数会随仓库一直涨。
                            .foregroundStyle(badge.scope.isIncremental ? .green : .secondary)
                    }
                }
                if let note = badge.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if e.id != journal.last?.id {
                    Divider()
                }
            }
            // ⚠️ 窗口与全量必须能被区分开。
            // 原来这一段什么都不显示，于是「只有 8 条」被读成「一共就 8 条」——
            // 引擎恒发 journalTruncated / journalLimit 就是为了这句话能被说出来。
            // 同样地，journal.md 里有解析不了的行时也要说，
            // 否则「日志很短」和「日志读不出来」在界面上完全同构。
            if p.journalTruncated {
                Text("只显示最近 \(journal.count) 条（按 \(p.journalLimit) 条取的窗口，不是全部）")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if p.journalUnparsableLines > 0 {
                Text("另有 \(p.journalUnparsableLines) 行日志解析不了（不是「日志到此为止」）")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - 图例（自动换行）

struct FlowLegend: View {
    let items: [(String, String, Color)]

    var body: some View {
        FlowLayout(spacing: DSSpacing.sm) {
            ForEach(items, id: \.0) { label, value, color in
                HStack(spacing: DSSpacing.xs) {
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
    /// 筛选行。判定在 `DashboardScope.swift`（纯函数，可单测）——
    /// 摆在界面上的控件若不影响数据，就只是装饰。
    ///
    /// ⚠️ 状态在 `AppModel.dashFilter`，**不在这里的 `@State`**：
    ///   1. `@State` 挂在视图上，视图重建就没了 —— 切到看板再切回来，
    ///      筛选悄悄弹回「全量」，用户会以为筛选失灵；
    ///   2. 看板是**第二个消费方**（同屏里两个视图必须对「在看什么」说同一句话），
    ///      各存一份就必然出现「仪表盘 1 个 / 看板 3 个」。
    @State private var reindexing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                // ⚠️ 原来只有 `if let … else ProgressView`，于是采集失败时
                // **主区永远转圈** —— 错误横幅挂在 PanelView 顶部，
                // 于是用户同时看到「一条报错」和「一个永不停歇的加载中」。
                // 「还在读」与「读不出来」必须有两种样子（见 LoadState.swift）。
                switch model.dashboardState.phase(hasContent: model.dashboard != nil) {
                case .content:
                    if let d = model.dashboard { dashboardContent(d) }
                case .failed(let msg):
                    EmptyState(
                        icon: "exclamationmark.triangle",
                        title: "仪表盘读不出来",
                        subtitle: msg
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                case .empty:
                    EmptyState(
                        icon: "chart.bar.xaxis",
                        title: "仪表盘还没有数据",
                        subtitle: "注册项目后运行一次浅更新"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                case .loading:
                    ProgressView("汇总项目群…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .frame(minHeight: 300)
                }
            }
            .padding(DSSpacing.lg)
        }
        .task { await model.fetchDashboard() }
    }

    private func dashboardContent(_ d: Dashboard) -> some View {
        // ⚠️ **算一次，两处消费**。页头那句摘要与下面 4 张 KPI 卡以前各算各的，
        // 于是同一屏给出两个「项目总数」和两个「待处理」：
        // 页头用 `d.projects.total`（仅采集成功）+ `dirty + mergeCandidates + 布尔`
        // （项目数 / 分支数 / 布尔三种单位相加），KPI 卡用 `listed` + 项目数。
        // 用户先看到的是页头那个大数字。
        // 现在两边都从这一个数组取 —— **不是加判据，是消掉分叉的那个源头**。
        let kpis = DashKPIBuilder.kpis(d, projects: model.projects)
        return VStack(alignment: .leading, spacing: DSSpacing.lg) {
            // ── 段 1：页头 ──
            // ⚠️ 原来这里是一整块紫蓝渐变 hero + **8 张平铺统计卡**
            // （项目/7天/30天/脏/分支/待合入/未跟踪/stash），每张只有
            // 「数字 + 标签」，没有主次、没有解释，也没有筛选。
            // 渐变没有信息量，却把页头和统计卡挤成同一团。
            // 这一版按设计稿的四段式重排：**层次**问题优先于配色问题。
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("项目群脉搏")
                        .font(.title2.weight(.bold))
                    Text(DashKPIBuilder.summaryLine(kpis))
                        .font(.callout)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Spacer(minLength: DSSpacing.md)
                GroupBriefButton()
            }

            // ── 段 2：筛选行（设计稿有，我们原来没有）──
            // 三个控件**都真的改变下面画什么**（判定见 DashboardScope.swift）：
            //   时间跨度 → 项目卡网格里出现哪些项目（按最近更新天数）
            //   提交类型 → 项目卡里堆叠条画哪几段、图例列哪几行
            //   重新索引 → 真跑一次浅更新并重新拉数据
            // 摆而不动的控件是最坏的一种控件，判据里专门钉住「它有效果」。
            DashboardFilterBar(
                filter: $model.dashFilter,
                commitTypes: availableCommitTypes(),
                reindexing: reindexing,
                onReindex: reindex
            )

            // ── 段 3：4 张精选 KPI ──
            // 8 → 4 不是删信息，是把它们**归并成有主次的四个问**：
            // 有多少东西 / 目标完成到什么程度 / 有多少事等着处理 / 仓库面有多宽。
            // 少掉的 7天/30天/未跟踪/stash 变成 KPI 的**副说明**或项目卡字段，
            // 删掉的是平铺，不是信息。口径在 DashKPIBuilder（纯函数，可单测）。
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.md), count: 4),
                spacing: DSSpacing.md
            ) {
                ForEach(kpis) { k in
                    KPIWideCard(kpi: k)
                }
            }

            // ── 段 4：逐项目卡网格（设计稿的核心区块）──
            // 设计稿这里是 2 列网格，每张卡：名称 + 版本徽标 / 大百分比 + 状态词 /
            // 描述 / 里程碑进度 / 进度条 / 提交结构堆叠条 + 图例 / 最新 commit + 链路入口。
            // 我们没有「版本号」这种数据（引擎不给，见 D2），
            // 所以百分比换成**能诚实算出来的**逐项目里程碑完成率，
            // 状态词从分支 staleDays 与脏文件数推出来 —— 都是事实，不是修辞。
            // 每张卡同时是**进入该仓库独立管控页的入口**（用户点名要保留的第 2 点）。
            projectGrid(d)




            // 语言分布 + 里程碑
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                Card(title: "语言分布（跟踪文件数）") {
                    // 覆盖度披露走纯函数 languageCoverage（缺陷 #187）。
                    // 内联在这里的话，「失败被当成没有」只能靠肉眼发现。
                    // ⚠️ shownCount 必须是**这张卡片实际画出来**的条数（缺陷 #205）。
                    // 原来这里只传 `d.languages.count`（引擎给的 12），
                    // 而下面画的是 prefix(LANG_BAR_MAX) = 8 条 ——
                    // 披露按 12 算、界面画 8 条，藏起来的那 4 条一个字都不提。
                    let shown = min(d.languages.count, LANG_BAR_MAX)
                    let coverage = languageCoverage(
                        languageCount: d.languages.count,
                        truncated: d.languagesTruncated ?? false,
                        failed: d.languagesFailed ?? 0,
                        reasons: d.languagesFailedReasons,
                        topCut: d.languagesTopCut ?? false,
                        shownCount: shown
                    )
                    if d.languages.isEmpty {
                        EmptyState(icon: "text.justify", title: coverage.emptyTitle).frame(height: 70)
                    } else {
                        // ⚠️ 原来这里内联 8 色字面量（.blue, .purple, .orange, .teal…），
                        // 而提交构成卡用 12 色（.blue, .red, .orange, .purple…）：
                        // 同一个「蓝」在一张卡里是 feat、在另一张卡里是 Swift，
                        // 序号相同的两项两张卡颜色还不同，读者拿两张卡对照会误读。
                        // 这正是改版规范 §3.3 点名的「消灭两套调色板」。
                        // 现在与提交构成卡同源：第 1 名 = 蓝，两张卡一致。
                        //
                        // 刻意**不取模**：LANG_BAR_MAX(8) ≤ 色板容量(12) 是硬保证
                        // （判据锁着），取模只会掩盖「上限被悄悄改大」。
                        VStack(alignment: .leading, spacing: 10) {
                            SegmentedBar(segments: d.languages.prefix(LANG_BAR_MAX).enumerated().map { i, l in
                                .init(label: l.language, value: Double(l.count),
                                      color: DSColor.sequence(CommitTypeColor.palette[i]))
                            })
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(d.languages.prefix(LANG_BAR_MAX).enumerated().map { i, l in
                                    (l.language, l.count, DSColor.sequence(CommitTypeColor.palette[i]))
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
                    // 披露恒发：哪怕分布是空的、图根本没画出来，
                    // 「有项目没采到」这句话也必须出现在这张卡片里。
                    if let note = coverage.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                }

                Card(title: milestoneCardTitle(d.milestones.counts)) {
                    if d.milestones.items.isEmpty {
                        EmptyState(
                            icon: d.milestones.counts.degraded ? "exclamationmark.triangle" : "flag",
                            title: d.milestones.counts.degraded
                                ? "里程碑读不出来（不是「没有」）"
                                : "暂无里程碑",
                            subtitle: d.milestones.counts.degraded
                                ? "milestones.json \(d.milestones.counts.storeHealth)，读到 \(d.milestones.counts.readCount) 条"
                                : "在「里程碑」页添加"
                        ).frame(height: 70)
                    } else {
                        // ⚠️ 切片与上限来自 MilestoneCard.swift（缺陷 #207）：
                        // 原来这里写死 `items.prefix(5)`，而标题按 counts 全量说话
                        // （「进行中 8」），8 条里静默藏掉 3 条。
                        // 画几条必须用 slice.shown，不许再写第二个字面量 ——
                        // 那正是让披露与画出来的东西对不上的原因。
                        let slice = milestoneCardSlice(itemCount: d.milestones.items.count)
                        VStack(spacing: 6) {
                            ForEach(d.milestones.items.prefix(slice.shown)) { m in
                                milestoneRow(m)
                            }
                            if let note = slice.note {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: 筛选用到的提交类型（只列**出现过**的，不编）

    private func availableCommitTypes() -> [String] {
        var seen: [String] = []
        for p in model.projects {
            for s in p.commitTypes ?? [] where !seen.contains(s.type) {
                seen.append(s.type)
            }
        }
        return seen.sorted()
    }

    // MARK: 重新索引

    /// 真跑一次浅更新。**不是装饰按钮**。
    /// 跑完必须重新拉仪表盘，否则用户点了看不到任何数字变化。
    private func reindex() {
        guard !reindexing else { return }
        reindexing = true
        Task {
            await model.runUpdate(deep: false)
            await model.fetchDashboard()
            reindexing = false
        }
    }

    // MARK: 段 4：逐项目卡网格

    private func projectGrid(_ d: Dashboard) -> some View {
        let all = model.projects
        let shown = all.filter { model.dashFilter.keeps(project: $0) }
        return VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Text("各项目演进进度与里程碑明细")
                    .font(.headline)
                Spacer()
                // 明细标题必须**跟着筛选走**并说清被筛掉了多少 ——
                // 标题写「（12）」而下面画 3 张卡，就是本项目踩过多次的那族缺陷。
                Text(shown.count == all.count
                     ? "共 \(all.count) 个项目"
                     : "\(shown.count)/\(all.count) 个项目（最近更新在 \(model.dashFilter.span.label)）")
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            if shown.isEmpty {
                EmptyState(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "这个时间跨度下没有项目",
                    subtitle: "共 \(all.count) 个项目，最近 \(model.dashFilter.span.label)更新过。" +
                             "读不出更新时间的项目始终保留，不会被筛掉"
                )
                .frame(minHeight: 120)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 300),
                                                       spacing: DSSpacing.md), count: 2),
                    spacing: DSSpacing.md
                ) {
                    ForEach(shown) { p in
                        ProjectProgressCard(
                            project: p,
                            milestones: d.milestones.items.filter { $0.projectId == p.id },
                            filter: model.dashFilter
                        )
                    }
                }
            }
        }
    }


    private func milestoneRow(_ m: MilestoneItem) -> some View {
        HStack(spacing: DSSpacing.sm) {
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

// MARK: - 里程碑卡片标题

/// 里程碑卡片的标题。**纯函数**（判定不内联在视图里，才能被测试断言）。
///
/// 引擎的 counts 一共 9 个字段，卡片标题只准用其中能诚实表达的那几个：
///   open / done        —— 采集到了的事实
///   unknown            —— **不知道**达没达成，必须单列，不能并进 open 或 done
///   excludedDisabled   —— 属于已停用项目，故意没计入
///   orphaned           —— 所属项目已不存在，列不出来
///   storeHealth/degraded —— 存储读不出来，上面那些 0 不是「没有」
///
/// 引擎侧的注释：「『我们不知道』和『没有达成』是两件相反的事，必须分开表达。」
/// 原来标题只有「进行中 N · 已达成 M」，unknown 被静默吞掉 ——
/// 仓库损坏时用户看到「进行中 0 · 已达成 0」，读出来是「这个项目一个里程碑都没有」。
func milestoneCardTitle(_ c: MilestoneCounts) -> String {
    var parts = ["进行中 \(c.open)", "已达成 \(c.done)"]
    if c.dropped > 0 { parts.append("已放弃 \(c.dropped)") }
    if c.unknown > 0 { parts.append("⚠ 无法核验 \(c.unknown)") }
    if c.excludedDisabled > 0 { parts.append("已停用项目的 \(c.excludedDisabled) 条未计入") }
    if c.orphaned > 0 { parts.append("⚠ \(c.orphaned) 条所属项目已不存在") }
    if c.degraded || c.storeHealth != "ok" {
        parts.append("⚠ milestones.json \(c.storeHealth)")
    }
    return "里程碑（" + parts.joined(separator: " · ") + "）"
}
