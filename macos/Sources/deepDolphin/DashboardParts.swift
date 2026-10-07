// DashboardParts.swift — 仪表盘的四段式零件（设计稿 GitPulse AI Hub 布局）。
//
// 【这一版在改什么】
// 原仪表盘是「渐变 hero + 8 张平铺小卡 + 语言/里程碑两张卡」。
// 设计稿是四段式：**页头 → 筛选行 → 4 张精选 KPI → 逐项目卡网格**。
// 差距不在配色，在于**层次**：
//   · 8 张同权重的小卡没有主次，用户得自己加、自己在脑子里排优先级；
//   · 没有任何筛选，看的是「全部」而不是「我现在关心的那一部分」；
//   · 逐项目的进度散在别处，没有一个能直接点进去的入口。
//
// 【与 DashboardScope.swift 的分工】
// 判定（时间跨度怎么算、提交类型筛哪些段、KPI 怎么归并）全在纯函数层；
// 本文件只负责把结果画出来。**这里不许出现任何算术。**
//
// 【诚实边界，写在类型与注释里而不是靠自觉】
//   · 时间跨度 = 按「最近更新天数」分档，不是「这段时间内的提交量」
//     —— 引擎没有逐项目提交时间序列（D2 已裁定）。
//   · 逐项目的「完成度百分比」= 该项目的里程碑达成率。
//     设计稿那个百分比是「项目完成度」，我们没有这个口径，**不编**。
//   · 设计稿的版本徽标（v2.4-alpha）、42 天连续活跃、热力矩阵：
//     引擎没有这些数据，**不画**。画一个永远空着的格子比不画更糟。

import SwiftUI

// MARK: - 段 2：筛选行

/// 设计稿顶部那条筛选行：时间跨度 / 提交类型 / 重新索引。
///
/// ⚠️ 三个控件都必须**真的改变下面画什么**。摆而不动的控件是最坏的一种控件 ——
/// 用户拨了「近 7 天」而卡片纹丝不动，于是整条筛选行被当成装饰，
/// 而他不知道真正的数据是全部项目的。判据在 ClientCheck。
struct DashboardFilterBar: View {
    @Binding var filter: DashFilter
    /// 只列真实出现过的提交类型。空数组时下拉禁用并说明原因，
    /// 而不是给一个只有「所有提交类型」一项的空壳菜单。
    let commitTypes: [String]
    let reindexing: Bool
    let onReindex: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Text("时间跨度")
                .font(DSTypography.label)
                .foregroundStyle(DSColor.textSecondary)

            Picker("", selection: $filter.span) {
                ForEach(DashSpan.allCases, id: \.self) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            // 口径要写在控件旁边：这是「最近更新」分档，不是「这段时间的提交量」。
            .help("按项目最近一次更新的天数分档（不是统计这段时间内的提交量）")
            .accessibilityLabel(A11y.label("时间跨度筛选"))

            Picker("", selection: $filter.commits) {
                Text(DashCommitFilter.all.label).tag(DashCommitFilter.all)
                ForEach(commitTypes, id: \.self) { t in
                    Text(t).tag(DashCommitFilter.only(t))
                }
            }
            .labelsHidden()
            .frame(width: 170)
            .disabled(commitTypes.isEmpty)
            .help(commitTypes.isEmpty
                  ? "还没有采到任何提交类型（需要仓库有提交历史）"
                  : "只影响每张项目卡的提交结构条与图例，不改上方 KPI 数字")
            .accessibilityLabel(A11y.label("提交类型筛选"))

            Button(action: onReindex) {
                if reindexing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("重新索引", systemImage: "arrow.clockwise")
                }
            }
            .controlSize(.small)
            .disabled(reindexing)
            .help("重新采集一次浅更新")
            .accessibilityLabel(A11y.label("重新索引"))

            Spacer()
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surfaceAlt, in: DSRect.shape(DSRadius.control))
    }
}

// MARK: - 段 3：KPI 宽卡

/// 设计稿的 KPI 卡是「大数字 + 副说明 +（可选）进度条」，
/// 而原来的 `StatCard` 只有「大数字 + 标签」。差别在于**副说明**——
/// 它回答「这个数字意味着什么」，没有它，数字就只是数字。
struct KPIWideCard: View {
    let kpi: DashKPI

    private var tint: Color { kpi.tint == 1 ? .orange : .primary }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(kpi.title)
                .font(DSTypography.label)
                .foregroundStyle(DSColor.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                Text("\(kpi.value)")
                    .font(DSTypography.metric)
                    .foregroundStyle(tint)
                if kpi.kind == .milestones {
                    Text("%")
                        .font(.headline)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            if let p = kpi.progress {
                // 里程碑完成度才画进度条：它本身就是「完成度」。
                // 给「3 个待处理」也画一根进度条是装饰，不是信息。
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .tint(DSColor.deep)
            }

            Text(kpi.caption)
                .font(DSTypography.label)
                .foregroundStyle(DSColor.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .surface()
    }
}

// MARK: - 段 4：逐项目进度卡

/// 设计稿的「全量项目 Git 历史进度大盘」里每张项目卡。
/// 结构照设计稿的层次：标识 → 状态 → 描述 → 里程碑 → 提交结构 → 最近提交 → 入口。
struct ProjectProgressCard: View {
    @EnvironmentObject var model: AppModel
    let project: ProjectStatus
    /// 只传**属于这个项目**的里程碑。传全量再在里面筛，
    /// 迟早会有人忘了筛 —— 卡片上出现别的项目的里程碑，
    /// 而用户完全看不出来（"design-system-core 30%" 出现在 nexus 那张卡里）。
    let milestones: [MilestoneItem]
    let filter: DashFilter

    // MARK: 口径

    /// 里程碑完成率 = 达成 / (达成 + 进行中)。
    /// 刻意**不把 unknown 塞进分母** —— unknown 是「读不出来」，
    /// 算作「没达成」就是把无知说成事实（本项目最高发的那族缺陷）。
    private var milestoneRatio: (done: Int, decided: Int, unknown: Int) {
        let done = milestones.filter { $0.status == "done" }.count
        let open = milestones.filter { $0.status == "open" }.count
        let unknown = milestones.filter { $0.status == "unknown" }.count
        return (done, done + open, unknown)
    }

    private var percent: Int {
        let m = milestoneRatio
        return m.decided > 0 ? Int((Double(m.done) * 100 / Double(m.decided)).rounded()) : 0
    }

    /// 状态词。**只从事实推**，不写修辞。
    ///
    /// ⚠️ 这里原来有**两版**，都错，而且错法不同：
    ///   · 第一版 `b.staleDays >= 14` —— 被自己的判据抓出来：
    ///     14 天是引擎 `progress.cj:30-36` 的档位线，客户端再写一遍就是两个真相源，
    ///     迟早出现「状态点说停滞、这张卡说正常」。
    ///   · 第二版读 `project.primaryBranch?.status` —— 那也是**追踪数组**，
    ///     无远端基线的仓库恒为空，于是全部落进 `default: 正常`。
    ///     实测一个 47 天没提交的仓库，这张卡显示「**正常**」。
    /// 现在统一消费模型层的 `ProjectStatus.stateWord`（`liveness` 那一份），
    /// 看板与项目卡对同一个项目必然给出同一个词。
    private var stateWord: (String, Color) {
        let s = project.stateWord
        let color: Color
        switch s.tone {
        case .unreadable, .unknown: color = .red
        case .notGit:               color = .secondary
        case .needsAction:          color = .orange
        case .engineStale, .quiet:  color = .secondary
        case .recent:               color = .green
        }
        return (s.text, color)
    }

    private var branchLabel: String {
        // ⚠️ 原来这里只读 `primaryBranch`（追踪数组里的对象），数组空就显示
        // 「无分支记录」。但引擎**恒发** `currentBranch`（分支名字符串），
        // 实测一个 4 分支、无远端基线的仓库：branches=[] 而 currentBranch="main"。
        // 于是卡片说「无分支记录」而侧栏/详情页显示 main —— 两处矛盾，
        // 且真相是「明细没追踪到」，不是「没有分支」。
        // 这正是本项目最高发的那族：把「不知道」说成「没有」。
        if let b = project.primaryBranch { return b.name }
        if !project.currentBranch.isEmpty { return project.currentBranch }
        return "无分支记录"
    }

    /// 明细（HEAD、状态、进度）是否拿得到。拿不到时那一行要**说清楚**，
    /// 不能画成「这个项目没有提交」。
    private var branchDetailMissing: Bool {
        project.primaryBranch == nil && !project.isUnreadable
    }

    private var headBranch: BranchStatus? { project.primaryBranch }

    // MARK: 视图

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // 行 1：项目名（等宽，设计稿用 mono 体现「这是标识符」）+ 状态词
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                Text(project.name)
                    .font(.system(.headline, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: DSSpacing.sm)
                let w = stateWord
                Label(w.0, systemImage: "circle.fill")
                    .font(DSTypography.label)
                    .foregroundStyle(w.1)
                    .labelStyle(.titleAndIcon)
            }

            // 行 2：一句描述。读不出来时不能编一句。
            Text(project.isUnreadable
                 ? (project.error ?? "这个项目读不出来")
                 : (project.headline.isEmpty ? "没有提交摘要" : project.headline))
                .font(.caption)
                .foregroundStyle(project.isUnreadable ? .red : DSColor.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // 行 3：里程碑完成度 + 分支（设计稿这行是「里程碑完成度 (34/40 关联提交)  分支: main」）
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                milestoneLine
                Spacer(minLength: DSSpacing.sm)
                Text("分支")
                    .font(DSTypography.label)
                    .foregroundStyle(DSColor.textTertiary)
                Text(branchLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
            }

            // 行 4：提交结构（堆叠条 + 图例，受提交类型筛选控制）
            if !project.isUnreadable {
                commitComposition
            }

            // 行 5：最近提交 + 进入独立管控页的入口
            HStack(spacing: DSSpacing.sm) {
                if let b = headBranch {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(DSColor.textTertiary)
                    Text(b.headShort.isEmpty ? b.name : b.headShort)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(DSColor.textSecondary)
                    Text(b.headSubject ?? b.summary)
                        .font(DSTypography.label)
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if branchDetailMissing {
                    // 明细读不到 ≠ 没有提交。这句话必须存在，
                    // 否则「空着的一行」会被读成「这个项目什么都没干」。
                    Text("分支明细未纳入追踪（提交类型分布仍可用）")
                        .font(DSTypography.label)
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                } else {
                    Text("读不出来")
                        .font(DSTypography.label)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: DSSpacing.sm)
                // 「查看 Git 链路 →」= 进入该仓库的**独立管控页**
                // （用户点名要保留的第 2 点：每个 git 仓库项目的独立管控查看）
                Button {
                    model.go(.project(project.name))
                } label: {
                    HStack(spacing: 2) {
                        Text("进入管控")
                        Image(systemName: "arrow.right")
                    }
                    .font(DSTypography.label)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSColor.accent)
                .help("打开 \(project.name) 的独立管控页")
                .accessibilityLabel(A11y.label("进入 \(project.name) 的独立管控页"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .surface()
        .contentShape(Rectangle())
        .onTapGesture { model.go(.project(project.name)) }
    }

    // MARK: 里程碑那一行

    @ViewBuilder
    private var milestoneLine: some View {
        let m = milestoneRatio
        if m.decided == 0 && m.unknown > 0 {
            Text("里程碑读不出来（\(m.unknown) 个）")
                .font(DSTypography.label)
                .foregroundStyle(.orange)
        } else if m.decided == 0 {
            Text("未设里程碑")
                .font(DSTypography.label)
                .foregroundStyle(DSColor.textTertiary)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                Text("里程碑")
                    .font(DSTypography.label)
                    .foregroundStyle(DSColor.textTertiary)
                Text("\(m.done)/\(m.decided)")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(DSColor.textSecondary)
                Text("\(percent)%")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(DSColor.deep)
                if m.unknown > 0 {
                    // unknown 单列：混进「已达成/进行中」就是把无知说成事实
                    Text("· \(m.unknown) 个读不出来")
                        .font(DSTypography.label)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: 提交结构（堆叠条 + 图例）

    @ViewBuilder
    private var commitComposition: some View {
        let kept = filter.keptStats(project.commitTypes ?? [])
        if let all = project.commitTypes, all.isEmpty {
            Text("这个项目没有提交历史（或读不出来）")
                .font(DSTypography.label)
                .foregroundStyle(DSColor.textTertiary)
        } else if kept.isEmpty {
            // 筛到一个都不剩时**必须说出来**，不能画一根空条装作「没有提交」
            Text("该筛选下这个项目没有匹配的提交类型")
                .font(DSTypography.label)
                .foregroundStyle(DSColor.textTertiary)
        } else {
            // ⚠️ **不取模**：`palette[i % capacity]` 会让第 13 类拿到第 1 类的颜色，
            // 两段同色的分段条于是并成一段，而用户以为那是同一种类型。
            // 色板画不完的条数由 `commitTypeCardSlice` **说出来**
            // （判定在纯函数层 CommitTypeComposition.swift）。
            let slice = commitTypeCardSlice(entries: kept.map { ($0.type, $0.count) })
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack {
                    Text("提交结构")
                        .font(DSTypography.label)
                        .foregroundStyle(DSColor.textTertiary)
                    Spacer()
                    // 样本披露必须在场：commitTypes 是**最近 N 条的样本**，
                    // 拿样本当全量展示是本项目修过的缺陷。
                    if project.commitTypesTruncated {
                        Text("样本")
                            .font(DSTypography.label)
                            .foregroundStyle(.orange)
                            .help("引擎只给了最近若干条提交的类型分布，不是全量")
                            .accessibilityLabel(A11y.label("提交类型是样本，不是全量"))
                    }
                }
                SegmentedBar(segments: slice.entries.enumerated().map { i, e in
                    .init(label: e.type, value: Double(e.count),
                          color: DSColor.sequence(CommitTypeColor.palette[i]))
                })
                FlowLegend(items: slice.entries.enumerated().map { i, e in
                    (e.type, "\(e.count)", DSColor.sequence(CommitTypeColor.palette[i]))
                })
                if let note = slice.note {
                    Text(note)
                        .font(DSTypography.label)
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
        }
    }
}
