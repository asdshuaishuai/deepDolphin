// WorkBar.swift — 主工作条：范围选择器 + 双轨主动作。
//
// 【为什么要有这条，按设计稿说的】
// 设计稿（GitPulse AI Hub）的顶栏是一条**工作条**，不是一排图标：
//   左边：范围选择器「全局视图 (All Managed Repos)」——在「看整个项目群」与
//         「看某一个仓库」之间切换；
//   右边：双轨主链路「⚡ 浅更新 (带待处理计数) → 🪄 深更新」，
//         两个动作之间有箭头，表示它们是**一条链的两段**，不是两个并列按钮。
//
// 改版规范 §3.1 定了「原生标题栏 + 分组侧栏工作台」（D3），
// 所以**不自绘标题栏**（那会丢掉标准窗口行为：拖动、全屏、菜单栏）。
// 合理化的做法是：把设计稿那条工作条放在**内容区顶部**，
// 原生工具栏只留工具类动作（刷新 / 更多 / AI / 设置 / 搜索）。
//
// 【这条工作条解决的正是用户点名的两件事之间的切换】
//   全局看板  ←—— 范围 = 全局 ——→  单仓库独立管控
// 所以它不是装饰：改了范围，主区真的换内容（判定在 Scope.swift / AppModel.go）。
import SwiftUI

struct WorkBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            scopePicker
            Spacer(minLength: DSSpacing.md)
            // ⚠️ 「一键全量」与右边的双轨是**两种不同的动作**（范围 + 执行方式都不同），
            // 所以用一条分隔线把它们明确切开，而不是并排摆成四个同级按钮：
            // 四个长得差不多的更新按钮摆在一起，用户无法在按下之前判断会动哪些仓库。
            // 分隔线也是设计稿那条「双轨是一条链」的呼应 —— 链是右边那两个。
            HStack(spacing: DSSpacing.md) {
                AgentBulkButtons()
                Rectangle()
                    .fill(DSColor.border)
                    .frame(width: 1, height: 18)
                pipeline
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surfaceAlt)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DSColor.border)
                .frame(height: 1)
        }
    }

    // MARK: 范围选择器（设计稿左段）

    /// 设计稿的「全局视图 (All Managed Repos)」。
    ///
    /// ⚠️ 我此前在 README 里写过「不另造范围选择器，侧栏导航已承担同角色」——
    /// **那条是错的**：侧栏管的是「看哪个视图」，范围管的是「看哪些仓库」，
    /// 是两个正交的选择。砍掉它之后，用户无法从仪表盘直接跳进某个仓库，
    /// 只能退回侧栏再点一次。现在它就是这两个视图之间的开关。
    private var scopePicker: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "globe")
                .font(.caption)
                .foregroundStyle(DSColor.textTertiary)
            Picker("", selection: scopeBinding) {
                Text("全局看板（全部 \(model.projects.count) 个项目）")
                    .tag(ScopeChoice.group)
                // 只列真实存在的项目。`model.projects` 为空时这一项不会被选中，
                // 而 Picker 会退回第一项（group），所以不会出现「选了一个不存在的仓库」。
                ForEach(model.projects) { p in
                    Text(p.name).tag(ScopeChoice.project(p.name))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320)
            .help("在「全局看板」与「单个仓库的独立管控页」之间切换")
            .accessibilityLabel(A11y.label("范围选择器"))
        }
    }

    /// 范围 → 路由。**只有一个写入口**：`model.go(_:)`。
    /// 直接写 `selection` 会绕开 Router 的校验（那正是「跳到不存在的项目」的老路）。
    private var scopeBinding: Binding<ScopeChoice> {
        Binding(
            get: { ScopeRules.choice(for: model.selection) },
            set: { model.go($0.section) }
        )
    }

    // MARK: 双轨链路（设计稿右段）

    /// 设计稿把两个按钮画成一条链：浅更新 →（箭头）→ 深更新。
    /// 这里保留那条链的**语义**（浅在前、深在后、深更重），
    /// 但不用自绘箭头 —— 工具栏里的两个按钮之间插一个箭头图标，
    /// 在 macOS 上会被读成「这是一个可点的第三项」。
    /// 深度/浅度的区别改由**颜色 + 说明**表达（见两个按钮的 help）。
    private var pipeline: some View {
        DualTrackButtons()
    }
}

/// 侧栏底部常驻状态条（设计稿左下角那条）。
///
/// 设计稿是「● Git Hook Active · Syncing / 决策线操作：12m ago」。
/// 我们没有 Git Hook 机制，**不编一个「Hook Active」** ——
/// 那会让用户以为有个钩子在替他跑，而我们根本没装。
/// 只报**我们确实知道**的两件事：现在有没有东西在跑、上次刷新是什么时候。
struct SidebarStatusStrip: View {
    @ObservedObject var model: AppModel

    private var busy: Bool {
        model.isLoading || model.busyAll || model.busyProject != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DSSpacing.xs) {
                Circle()
                    .fill(busy ? DSColor.accent : DSColor.shallow)
                    .frame(width: 7, height: 7)
                Text(busy ? "正在采集…" : "空闲")
                    .font(.caption2)
                Spacer(minLength: DSSpacing.xs)
                if let t = model.lastRefreshed {
                    Text(t.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
            // 读不出来与「还没刷新过」是两件事，措辞必须不同。
            if let err = model.lastError, model.projects.isEmpty {
                Text("引擎连接失败")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if model.lastRefreshed == nil {
                Text("尚未刷新")
                    .font(.caption2)
                    .foregroundStyle(DSColor.textTertiary)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(DSColor.border).frame(height: 1)
        }
    }
}
