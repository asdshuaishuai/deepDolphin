// deepDolphin Linux 客户端 —— 主视图。
//
// 【结构与 macOS 端 `PanelView` 一比一】
//   ┌ 工具栏：双轨按钮 | 刷新 | AI 助手 | AI 设置 | 搜索 ┐   ← 只有工具类动作
//   ├──────────────────┬──────────────────────────────┤
//   │ 侧栏             │ 深链提示条                    │
//   │  搜索            │ 错误条                        │
//   │  视图组 3 行     │ WorkBar（范围 + 双轨）        │
//   │  仓库组 N 行     │ 按选中路由分派                │
//   │  ＋添加/扫描     │                              │
//   │  状态条          │                              │
//   └──────────────────┴──────────────────────────────┘
//
// 本文件**不写任何颜色字面量**。取色一律经过
// `dsSurface` / `dsPill` / `dsAlertPill` / `dsStatColor` / `dsSequenceColor`，
// 它们最终都指向 `tokens.cj`。在视图里写 `Color.rgb(...)` 就会分家 ——
// 两端同一个「活跃」颜色不同，用户会以为是两件事。
package deepdolphin_linux

import std.collection.ArrayList

import cui.{Axis, Badge, BadgeKind, Button, ButtonRole, Color, CrossAxisAlignment, DesktopApp, Divider, Dropdown,
    Flexible, FontWeight, HStack, Label, LengthUnits, Panel, ScrollView, Spacer, State, SurfaceStyle, TextArea,
    TextField, VStack, Widget}
import cui.LengthUnits
import cui.{mountEffect, rememberState}

// ===========================================================================
// 根
// ===========================================================================

func rootView(model: AppModel, app: DesktopApp): Unit {
    let dark = model.dark.value
    VStack {
        toolbar(model, app, dark)
        Divider()
        Flexible { mainArea(model, app, dark) }
    }.spacing(0.vp)
}

/// 引擎找不到时的空态。**先判引擎、再判项目、再判加载中** ——
/// 顺序反了会在「引擎没装」时先闪一下「读取项目群…」。
func mainArea(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    HStack {
        sidebar(model, app, dark)
        Divider(axis: Axis.Vertical)
        Flexible { detail(model, app, dark) }
    }.spacing(0.vp)
}

// ===========================================================================
// 工具栏
// ===========================================================================

/// 工具栏。**只放工具类动作** —— 刷新 / AI / 设置 / 搜索。
///
/// ⚠ 双轨更新按钮放在这里**且** WorkBar 里也有一对，是 macOS 端的有意选择
/// （工具栏那对是常用快捷入口，WorkBar 那对带范围语义）。
/// 但同一个动作不许在**同一处**出现两次措辞不同的按钮。
///
/// ⚠ 顶栏**不显示引擎全路径**。曾经写成
/// `引擎 仓内构建 · /Volumes/…/moonGit/target/release/bin/main`，
/// 那个 Label 的固有宽度就是整条路径，把右边按钮整排挤出窗口 ——
/// 「浅更新全部」被切掉、「深更新全部」整个消失。路径长度在别的机器上
/// 还会更长（HOME 不同），所以这不是「这台机器上有点挤」。
func toolbar(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    let busy = model.busy.value || model.actionBusy.value
    Panel {
        HStack {
            Label("deepDolphin").fontSize(15.0).fontWeight(FontWeight.semiBold)
            Label(model.engineLabel.value).fontSize(11.0).muted().maxLines(1).width(240.0.vp)
            Spacer()
            DualTrackButtons(model, app, dark)
            Divider(axis: Axis.Vertical).height(18.vp)
            Button("刷新", {=> requestRefresh(app, model)}, role: ButtonRole.Primary)
                .fontSize(12.0).enabled(busy)
            Button("AI 助手", {=> model.report("AI 助手尚未接入（见待办）", false)}).fontSize(12.0)
            Button("AI 设置", {=> model.report("AI 设置尚未接入（见待办）", false)}).fontSize(12.0)
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.style(toolbarSurface(dark)).contentPadding(12.0.vp, 8.0.vp)
}

/// 工具栏底衬。**不画边框、不圆角** —— 它贴着窗口边，
/// 一旦有圆角就会在窗口顶边留下一条两像素的缺口。
private func toolbarSurface(dark: Bool): SurfaceStyle {
    return SurfaceStyle(dsColor(if (dark) { BG_DARK } else { CARD_LIGHT }), radius: 0.0)
}

/// 双轨按钮（macOS 端 `DualTrackButtons`）。
///
/// 标题随范围变化：全局下是「浅更新 · 全部」，单仓库下是「浅更新」。
/// 待处理数**只在真有东西时出现** —— 恒显的 0 徽章会被无视，
/// 而「0」还容易被读成「引擎说不用更新」。
func DualTrackButtons(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    let busy = model.actionBusy.value
    let now = nowMs()
    let pending = pendingShallow(model, now)
    let scope = model.scope.value
    HStack {
        Button(shallowLabelFor(scope), {=> actUpdate(app, model, updateTargetOf(model), false)})
            .fontSize(12.0).enabled(busy)
        if (pending > 0) {
            dsPill("${pending}", C_SHALLOW, dark)
        }
        Button(deepLabelFor(scope), {=> actUpdate(app, model, updateTargetOf(model), true)}, role: ButtonRole.Primary)
            .fontSize(12.0).enabled(busy)
    }.spacing(6.0.vp).hug()
}

/// 双轨动作的目标项目。空串 = 全部。
public func updateTargetOf(model: AppModel): String {
    if (scopeIs(model.scope.value, ScopeChoice.One)) {
        return model.selectedProject.value
    }
    return ""
}

// ===========================================================================
// 详情区
// ===========================================================================

func detail(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    VStack {
        if (!model.routeNotice.value.isEmpty()) {
            banner("提示", model.routeNotice.value, C_ORANGE, dark, {=> model.routeNotice.value = ""})
        }
        if (!model.problem.value.isEmpty() && model.snapshot.value.isSome() && !model.busy.value) {
            // 常驻错误条。项目正常加载时 `problem` 也要可见 ——
            // 此前只在空列表时展示，于是**静默失败**。
            // ⚠ 横幅**不挂任何自动刷新**：它是给人看的信息，
            // 不该在用户读它的时候自己动手把内容换掉。
            banner("注意", model.problem.value, C_ORANGE, dark, {=> model.problem.value = ""})
        }
        if (model.enginePath.isEmpty()) {
            setupGuide(model, app, dark)
        } else if (model.snapshot.value.isSome() && allProjectsOf(model).isEmpty()) {
            emptyState(
                (if (model.problem.value.isEmpty()) { "暂无已注册项目" } else { "引擎连接失败" }),
                (if (!model.problem.value.isEmpty()) {
                    model.problem.value
                } else {
                    "运行 moongit scan <目录> 注册项目群"
                }),
                model, app, dark
            )
        } else if (model.snapshot.value.isNone()) {
            Panel {
                VStack {
                    Label("读取项目群…").fontSize(15.0).muted()
                }.spacing(0.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
            }.style(dsSurface(DsLevel.Card, dark)).contentPadding(24.0.vp).flex()
        } else {
            VStack {
                // 主工作条。只在**有项目**时出现：没项目时范围选择器
                // 没有第二个选项，它就是一根装饰条。
                if (!allProjectsOf(model).isEmpty()) {
                    workBar(model, app, dark)
                }
                route(model, app, dark)
            }.spacing(0.vp)
        }
    }.spacing(0.vp)
}

/// 提示条 / 错误条。两类用**不同措辞**：
/// 一个是「深链打错字」，一个是「引擎/执行出错」，不能共用一句话。
private func banner(title: String, text: String, tint: Int64, dark: Bool, onClose: () -> Unit): Unit {
    Panel {
        HStack {
            dsAlertPill(title, DsAlert.Warn, dark)
            Flexible { Label(text).fontSize(12.0).wrap() }
            Button("关闭", onClose).fontSize(11.0)
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.style(dsTinted(tint, dark)).padding(10.0.vp, 6.0.vp)
}

/// 按选中分派。**只有一个 `switch`**，和 macOS 端 `detail` 一致 ——
/// 多个地方各自判「现在该显示什么」，早晚会有一处漏判。
func route(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    match (model.root.value) {
        case RootSection.Dashboard => dashboardPane(model, app, dark)
        case RootSection.Board => boardPane(model, app, dark)
        case RootSection.Milestones => milestonesPane(model, app, dark)
        case RootSection.Project =>
            match (selectedProjectOf(model)) {
                case Some(p) => projectDetail(model, app, p, dark)
                case None =>
                    dsEmptyState("在左侧选一个项目", "上面两行是视图，下面是受管项目。", dark)
            }
    }
}

// ===========================================================================
// WorkBar（macOS 端 `WorkBar`）
// ===========================================================================

/// 主工作条：左段范围选择器 + 右段双轨链路。
///
/// 改版规范定了「原生标题栏 + 分组侧栏工作台」，所以**不自绘标题栏** ——
/// 那会丢掉标准窗口行为（拖动 / 全屏 / 菜单栏）。
/// 合理化的做法就是把它放在**内容区顶部**，原生工具栏只留工具类动作。
private func workBar(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    observeScope(model)
    let total = allProjectsOf(model).size
    Panel {
        HStack {
            Label("范围").fontSize(12.0).muted()
            scopeButtons(model, app, total, dark)
            Spacer()
            DualTrackButtons(model, app, dark)
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.style(SurfaceStyle(dsColor(if (dark) { SIDEBAR_DARK } else { SIDEBAR_LIGHT }), radius: 0.0))
        .contentPadding(12.0.vp, 8.0.vp)
}

/// 范围选择器（WorkBar 左段）。
///
/// ⚠ 用**下拉**而不是一排按钮 —— 这不是审美问题，是功能问题：
/// 15 个项目时一排按钮排到第 11 个就被右缘截断，而右侧
/// 「浅更新 / 深更新」两个主链路按钮**整个被挤出窗口**（实测，夹具扩到 15 个项目复现）。
/// macOS 端用的是 `Picker` + `.frame(maxWidth: 320)`，CUI 的 `Dropdown` 是对应物
/// （弹层内可滚动、宽度按最长项自适应）。
///
/// 原来那句注释写「用一排按钮而不是下拉：项目多时下拉要滚动才能看全」——
/// 在 macOS 上成立，在 CUI 上不成立：这里没有下拉，于是自己排了一排，
/// 而一排在项目变多时会把**别的控件**挤掉。拿不到的控件不能成为
/// 排版失控的理由。
private func scopeButtons(model: AppModel, app: DesktopApp, total: Int64, dark: Bool): Unit {
    // 「范围」这个标签由外层 workBar 出，这里不再重复一遍 ——
    // 重复的标签在窄窗口下会显得像有两个同名控件。
    Flexible { Dropdown(scopeLabels(model, total), model.scopeIndex, key: "dd-scope") }
}

/// 范围下拉的选项：**只列真实存在的项目**。项目列表为空时那一项不会被选中，
/// 不会「选了一个不存在的仓库」。
public func scopeLabels(model: AppModel, total: Int64): Array<String> {
    let out = ArrayList<String>()
    out.add("全局（${total} 个项目）")
    for (p in allProjectsOf(model)) {
        out.add(p.name)
    }
    return out.toArray()
}

/// 下标 → 范围。**范围选择的唯一写入口** ——
/// 原来三处各写一遍 `scope` / `selectedProject` / `root`，
/// 漏写一处就会出现「标题说单仓库、内容是全局」。
///
/// ⚠ 两条分支都**转手给 `goView` / `openProject`**，不自己拼字段。
/// 范围条是侧栏之外的第二个入口，它切了主区就得负责把侧栏两组高亮跟上；
/// 自己写那三个字段的话，侧栏会停在旧地方不动。
public func applyScope(model: AppModel, idx: Int64): Unit {
    let ps = allProjectsOf(model)
    if (idx <= 0) {
        // 「全局」= 回仪表盘。goView 会清掉 `selectedProject`，
        // 于是 `scopeIndexOf` 自然回落成 0，下拉与主区不再分家。
        if (!scopeIs(model.scope.value, ScopeChoice.Group)) {
            model.scope.value = ScopeChoice.Group
        }
        goView(model, 0)
    } else if (idx - 1 < ps.size) {
        openProject(model, ps[Int64(idx - 1)].name)
    }
}

/// 范围 → 下标。0 = 全局，-1 = 不在范围里（下拉退回显示全局）。
public func scopeIndexOf(model: AppModel): Int64 {
    if (!scopeIs(model.scope.value, ScopeChoice.One)) {
        return 0
    }
    let name = model.selectedProject.value
    var i: Int64 = 0
    for (p in allProjectsOf(model)) {
        if (p.name == name) {
            return i + 1
        }
        i += 1
    }
    return 0
}

/// 把下拉的写入接到路由上。`mountEffect` 按 key 去重，重建时不会重复注册。
private func observeScope(model: AppModel): Unit {
    mountEffect("dd-observe-scope", {
        => model.scopeIndex.observe({_, v => applyScope(model, v)})
    })
    // 反向：别处（侧栏 / 详情页返回）改了范围，下拉要跟着显示对的那一项。
    mountEffect("dd-sync-scope", {
        => model.scope.observe({_, _ => syncScopeIndex(model)})
    })
}

private func syncScopeIndex(model: AppModel): Unit {
    let want = scopeIndexOf(model)
    if (model.scopeIndex.value != want) {
        model.scopeIndex.value = want
    }
}

/// 范围按钮的底色：选中用强调色的淡底，未选中用中性底。
///
/// ⚠ 收一个显式的 `selected` 布尔而不是「传枚举进来自己比」——
/// 上一个写法要同时判 `scopeIs(...)` 和 `s == ScopeChoice.One`，
/// 两个条件在「全局范围 + 单仓库按钮」这一组合下会同时成立，
/// 于是全局项和单仓库项**一起**被点亮。范围错了主区内容就全错。
private func scopeStyle(selected: Bool, dark: Bool): SurfaceStyle {
    if (selected) {
        return SurfaceStyle(dsPillBg(C_ACCENT, dark), radius: Float32(R_CONTROL))
    }
    return SurfaceStyle(dsColor(if (dark) { CARD_DARK } else { CARD_LIGHT }), radius: Float32(R_CONTROL))
}

// ===========================================================================
// 引擎安装引导（macOS 端 `setupGuide`）
// ===========================================================================

func setupGuide(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    Panel {
        VStack {
            Label("需要 moonGit 引擎").fontSize(17.0).fontWeight(FontWeight.semiBold)
            Label("引擎是独立安装的本地工具，客户端只负责展示。").fontSize(13.0).muted()
            Panel {
                VStack {
                    Label("1. 仓库内执行：sh scripts/install.sh").fontSize(12.0)
                    Label("2. 注册项目群：moongit scan ~/dev --depth 4").fontSize(12.0)
                    Label("3. 回到这里点「刷新」").fontSize(12.0)
                }.spacing(6.0.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
            }.style(dsSurface(DsLevel.Nested, dark)).contentPadding(14.0.vp)
            Button("重新检测引擎", {=> requestRefresh(app, model)}, role: ButtonRole.Primary).fontSize(13.0)
        }.spacing(14.0.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(28.0.vp).flex()
}

func emptyState(title: String, why: String, model: AppModel, app: DesktopApp, dark: Bool): Unit {
    Panel {
        VStack {
            Label(title).fontSize(17.0).fontWeight(FontWeight.semiBold)
            Label(why).fontSize(13.0).muted().wrap()
            if (model.canRefresh.value) {
                Button("重新读取", {=> requestRefresh(app, model)}, role: ButtonRole.Primary).fontSize(13.0)
            }
        }.spacing(10.0.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(24.0.vp).flex()
}

// ===========================================================================
// 页：仪表盘
// ===========================================================================

/// 仪表盘。段序与 macOS 端 `DashboardView.dashboardContent` **逐段对应**：
///
///   段 1  页头「项目群脉搏」+ 摘要行
///   段 2  筛选行（时间跨度 / 提交类型 / 重新索引）—— 见 `dashFilterBar`
///   段 3  4 张带副说明的 KPI
///   段 4  逐项目卡网格
///   段 5  语言分布 + 里程碑
///
/// 原来这里是「6 张只有数字的卡 + 语言分布 + 自造的待办卡」，
/// 既没有页头也没有项目卡网格 —— 那不是 macOS 的仪表盘，
/// 少掉的信息比多出来的还多。
func dashboardPane(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    ScrollView(key: "dd-dash-scroll") {
        VStack {
            // 失败面板必须在**最前**：它说的是「这一屏的数字有几个不可信」，
            // 埋在下面等于让人先读一遍假数据再看到警告。
            if (let Some(p) <- model.snapshot.value) {
                if (p.failedProjects > 0 || !p.failedKnown) {
                    failurePanel(p, dark)
                }
            }
            dashboardBody(model, app, dark)
            Spacer()
        }.spacing(20.0.vp).padding(20.0.vp)
    }
}

/// 仪表盘主体。**读不到就说原因，不画 0**。
private func dashboardBody(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    if (!model.dashboardProblem.value.isEmpty()) {
        Panel {
            VStack {
                HStack {
                    dsAlertPill("未读取", DsAlert.Warn, dark)
                    Flexible { Label(model.dashboardProblem.value).fontSize(13.0).wrap() }
                }.spacing(8.0.vp).hug()
                Label("这一块不会用 0 填。修好上面说的原因后点工具栏「刷新」。")
                    .fontSize(11.0).muted().wrap()
            }.spacing(6.0.vp)
        }.style(dsTinted(C_ORANGE, dark)).contentPadding(14.0.vp).hug()
    } else if (model.dashboard.value.isNone()) {
        dsEmptyState("正在读取仪表盘", "统计要遍历全部提交，稍等。", dark)
    } else {
        let d = model.dashboard.value.getOrThrow()
        let projects = snapshotProjects(model)
        let kpis = buildDashKpis(d, projects)

        // ── 段 1：页头 ──
        HStack {
            VStack {
                Label("项目群脉搏").fontSize(22.0).fontWeight(FontWeight.bold)
                Label(dashSummaryLine(kpis)).fontSize(13.0).muted()
            }.crossAxisAlignment(CrossAxisAlignment.Start).hug()
            Spacer()
        }.hug()

        // ── 段 2：筛选行 ──
        dashFilterBar(model, app, projects, dark)

        // ── 段 3：4 张带副说明的 KPI ──
        kpiGrid(kpis, dark)

        // ── 段 4：逐项目卡网格 ──
        projectGrid(model, app, d, projects, dark)

        // ── 段 5：语言分布 + 里程碑 ──
        // 两张卡**都 hug**（按内容高度），不 `.flex()` 强制等高：
        // 语言分布最多 8 行图例、里程碑最多 3 行，强行等高会把高的那张
        // 尾部裁掉 —— 而且 CUI 的 `Flexible` 不会给内容让路，它只分配空间。
        HStack {
            Flexible { languageCard(d, dark) }
            Flexible { milestoneCard(d, dark) }
        }.spacing(14.0.vp)
    }
}

/// 逐项目快照。仪表盘页的 KPI 与项目卡都要用，**取一次**。
private func snapshotProjects(model: AppModel): ArrayList<Project> {
    match (model.snapshot.value) {
        case Some(s) => return s.projects
        case None => return ArrayList<Project>()
    }
}

/// 4 张 KPI 卡。**每张都必须有副说明** —— 没有副说明的数字只是数字。
private func kpiGrid(kpis: Array<DashKpi>, dark: Bool): Unit {
    HStack {
        Flexible { kpiWideCard(kpis[0], dark) }
        Flexible { kpiWideCard(kpis[1], dark) }
    }.spacing(14.0.vp).hug()
    HStack {
        Flexible { kpiWideCard(kpis[2], dark) }
        Flexible { kpiWideCard(kpis[3], dark) }
    }.spacing(14.0.vp).hug()
}

/// 一张 KPI。大数字 + 标签 + **副说明** +（里程碑那张）进度条。
private func kpiWideCard(k: DashKpi, dark: Bool): Unit {
    let tint = kpiTintHex(k)
    // 进度条的颜色：里程碑那张跟大数字同色，其余用主色。
    let barColor = (if (tint.isSome()) { tint.getOrThrow() } else { C_ACCENT })
    Panel {
        VStack {
            HStack {
                Label(k.title).fontSize(12.0).muted()
                Spacer()
                // 「待处理 0」不该染红：没有待办不是坏事，
                // 染红等于把常态说成异常（与「读取失败」用红一个道理）。
                if (k.tint) {
                    dsAlertPill("有事要做", DsAlert.Warn, dark)
                }
            }.hug()
            match (tint) {
                case Some(c) =>
                    Label("${k.value}").fontSize(30.0).fontWeight(FontWeight.bold)
                        .foregroundColor(dsColor(c))
                case None =>
                    Label("${k.value}").fontSize(30.0).fontWeight(FontWeight.bold)
            }
            match (k.progress) {
                case Some(r) => dsMiniBarRatio(r, barColor, dark)
                case None => ()
            }
            Label(k.caption).fontSize(11.0).muted().wrap()
        }.crossAxisAlignment(CrossAxisAlignment.Start).spacing(6.0.vp)
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
}

/// KPI 大数字要不要染色，返回 `None` 就是用主题默认文字色。
///
/// 没有「文字色」这个令牌是刻意的：设计令牌层只给**语义色**，
/// 普通文字由主题管。凭空加一个 `C_TEXT` 会让「深浅色下文字该多深」
/// 这件事同时受两处控制。
private func kpiTintHex(k: DashKpi): Option<Int64> {
    match (k.kind) {
        case DashKpiKind.Milestones => return Some(C_ACCENT)
        case DashKpiKind.Attention => return (if (k.tint) { Some(C_ORANGE) } else { None })
        case DashKpiKind.Projects => return None
        case DashKpiKind.Reach => return None
    }
}

/// 失败项目面板。**一个都不折叠**，原因逐条给出 ——
/// 折叠成「3 个项目失败」时用户无法判断是自己的项目挂了还是配置问题。
private func failurePanel(snap: StatusSnapshot, dark: Bool): Unit {
    Panel {
        VStack {
            HStack {
                dsAlertPill("读取失败", DsAlert.Error, dark)
                Label("以下项目读取失败 —— 原因来自引擎，不是客户端推断")
                    .fontSize(13.0).fontWeight(FontWeight.semiBold)
            }.spacing(8.0.vp).hug()
            Divider()
            if (!snap.failedKnown) {
                Label("引擎没有披露失败项目数，下面这些是逐个读出来的。").fontSize(12.0).wrap()
            }
            for (p in snap.projects) {
                if (p.failed()) {
                    HStack {
                        Badge(p.name, kind: BadgeKind.Danger)
                        Flexible { Label(p.error).fontSize(12.0).wrap() }
                    }.spacing(8.0.vp).hug()
                }
            }
        }.spacing(8.0.vp)
    }.style(dsTinted(C_RED, dark, strong: true)).contentPadding(14.0.vp).hug()
}

/// 语言分布。分段条 + 图例**共用同一份序号 → 颜色映射**。
/// 图例是**必须**的：色点自己不会说话，读者按「颜色 ↔ 语言名」配对。
private func languageCard(dash: Dashboard, dark: Bool): Unit {
    let parts = languageParts(dash)
    Panel {
        VStack {
            HStack {
                dsCardTitle("语言分布")
                Spacer()
                if (dash.languagesTruncated) {
                    dsAlertPill("已截断", DsAlert.Warn, dark)
                }
                if (dash.languagesFailed > 0) {
                    dsAlertPill("${dash.languagesFailed} 个读不出", DsAlert.Warn, dark)
                }
            }.hug()
            if (parts.isEmpty()) {
                Label("引擎没有给出语言分布").fontSize(12.0).muted()
            } else {
                Flexible { dsSegBar(parts) }
                for (p in parts) {
                    dsLegendRow(p, languageTotal(parts))
                }
                if (dash.languagesTruncated) {
                    Label("（上面不是全部语言）").fontSize(11.0).muted()
                }
            }
        }.spacing(8.0.vp)
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).flex()
}

/// 语言分布的可见切片，**最多 8 档**。
public func languageParts(dash: Dashboard): Array<DsPart> {
    let cap: Int64 = 8
    let out = ArrayList<DsPart>()
    var i: Int64 = 0
    for (l in dash.languages) {
        if (i >= cap) {
            break
        }
        out.add(DsPart(l.language, l.count, slot: i))
        i += 1
    }
    return out.toArray()
}

private func languageTotal(parts: Array<DsPart>): Int64 {
    var t: Int64 = 0
    for (p in parts) {
        t += p.value
    }
    return t
}

/// 待办。绝对量，每条画一条小条。
private func workCard(dash: Dashboard, dark: Bool): Unit {
    Panel {
        VStack {
            dsCardTitle("待办")
            Divider()
            workRow("分支", dash.branches, 40, C_ACCENT, dark)
            workRow("待合入", dash.mergeCandidates, 10, C_YELLOW, dark)
            workRow("未跟踪", dash.untrackedFiles, 20, C_ORANGE, dark)
            workRow("stash", dash.stashes, 10, C_DEEP, dark)
            if (dash.failed > 0) {
                Divider()
                HStack {
                    Label("读取失败").fontSize(12.0)
                    Spacer()
                    dsStatPill(dash.failed, dark)
                }.hug()
            }
        }.spacing(8.0.vp)
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).flex()
}

private func workRow(title: String, n: Int64, full: Int64, color: Int64, dark: Bool): Unit {
    VStack {
        HStack {
            Label(title).fontSize(12.0)
            Spacer()
            Label("${n}").fontSize(12.0).fontWeight(FontWeight.semiBold)
                .foregroundColor(dsColor(dsStatColor(dsStatFrom(n))))
        }.hug()
        dsMiniBar(n, full, color, dark)
    }.spacing(3.0.vp).hug()
}

// ---------------------------------------------------------------------------
// 段 2：筛选行
// ---------------------------------------------------------------------------

/// 当前筛选。**唯一出处** —— 标题计数、网格过滤、提交结构条都从这里取，
/// 不许各自再读一遍 `dashSpan` / `dashCommits`。
public func currentDashFilter(model: AppModel): DashFilter {
    return DashFilter(model.dashSpan.value, model.dashCommits.value)
}

/// 筛选行。**三个控件都真的改变下面画什么**：
///   时间跨度 → 网格里出现哪些项目（按最近更新天数）
///   提交类型 → 项目卡里堆叠条画哪几段、图例列哪几行
///   重新索引 → 真跑一次浅更新并重拉
/// 摆而不动的控件是最坏的一种控件，判据里专门钉住「它有效果」。
private func dashFilterBar(
    model: AppModel,
    app: DesktopApp,
    projects: ArrayList<Project>,
    dark: Bool
): Unit {
    let f = currentDashFilter(model)
    Panel {
        HStack {
            // 时间跨度：点一下切下一档。**标签写「最近更新」而不是「提交」** ——
            // 引擎没有逐项目的提交时间序列，我们只能按最后更新天数分档。
            Button("最近更新：${spanLabel(f.span)}", {=> model.dashSpan.value = spanNext(f.span)})
                .fontSize(12.0)
            dsCommitsPicker(model, projects, dark)
            Spacer()
            // 用 `busy` 而不是另设一个 `reindexing` 标志：
            // `busy` 才是「有没有东西真在跑」的真值；另设标志只会带来
            // 「什么时候把它复位回来」这个假问题（写操作跑完才复位，
            // 而 CUI 没有回调可以挂这个点）。
            Button(
                (if (model.busy.value) { "重新索引中…" } else { "重新索引" }),
                {=> actUpdate(app, model, "", false)},
                role: ButtonRole.Primary
            ).fontSize(12.0).enabled(!model.busy.value && !model.actionBusy.value)
        }.spacing(8.0.vp).hug()
    }.style(dsSurface(DsLevel.Nested, dark)).contentPadding(10.0.vp, 8.0.vp).hug()
}

/// 提交类型选择器。**选项来自引擎真给的数据**（逐项目 commitTypes 求并集），
/// 不是写死一份列表 —— 写死的话引擎新增一个类型时这个控件就落下一项。
private func dsCommitsPicker(model: AppModel, projects: ArrayList<Project>, dark: Bool): Unit {
    let kinds = allCommitTypes(projects)
    HStack {
        dsFilterChip("所有提交类型", commitFilterIsAll(model.dashCommits.value), {
            => model.dashCommits.value = DashCommitFilter.AllCommits
        }, dark)
        for (k in kinds) {
            // 6 个之后再排就挤了；引擎给了 12 档色板，但这里选 6 个是**排版**取舍，
            // 不是数据取舍 —— 剩下的通过「所有提交类型」能看到。
            if (k.index < 6) {
                dsFilterChip(k.name, commitFilterEquals(model.dashCommits.value,
                    DashCommitFilter.Only(k.name)), {
                    => model.dashCommits.value = DashCommitFilter.Only(k.name)
                }, dark)
            }
        }
    }.spacing(6.0.vp).hug()
}

private func dsFilterChip(label: String, on: Bool, tap: () -> Unit, dark: Bool): Unit {
    Button(label, tap).fontSize(12.0)
        .style(if (on) {
            dsTinted(C_ACCENT, dark, strong: true)
        } else {
            dsSurface(DsLevel.Card, dark)
        })
}

// ---------------------------------------------------------------------------
// 段 4：逐项目卡网格（macOS 端 `DashboardView.projectGrid`）
// ---------------------------------------------------------------------------

/// 逐项目卡网格。标题右侧**必须说清画了几个 / 一共几个** ——
/// 标题写「（12）」而下面画 3 张卡，正是本项目栽过多次的那族缺陷。
private func projectGrid(
    model: AppModel,
    app: DesktopApp,
    d: Dashboard,
    projects: ArrayList<Project>,
    dark: Bool
): Unit {
    let f = currentDashFilter(model)
    let now = nowMillis()
    let shown = filteredProjects(f, projects, now)
    VStack {
        HStack {
            Label("各项目演进进度与里程碑明细")
                .fontSize(15.0).fontWeight(FontWeight.semiBold)
            Spacer()
            // 标题必须**跟着筛选走**并说清被筛掉了多少 ——
            // 标题写「（12）」而下面画 3 张卡，正是本项目踩过多次的那族缺陷。
            Label(gridCountLine(shown.size, projects.size, f)).fontSize(11.0).muted()
        }.hug()
        if (shown.isEmpty()) {
            dsEmptyState("没有可展示的项目", "引擎没给出项目列表。", dark)
        } else {
            // 2 列网格。逐行手摆而不是找「网格」控件：CUI 没有 LazyVGrid。
            // ⚠ 每张卡都 `.hug()`：`HStack` 给两个 `Flexible` 子项分配**同一行高**，
            // 谁矮谁被裁。hug 让行高由最高的那张决定，短卡自己占上面那段。
            var i: Int64 = 0
            while (i < shown.size) {
                // 闭包**不能捕获可变变量**，所以先把这一行的两张卡取成不可变值。
                let left = shown[Int64(i)]
                let right: Option<Project> = (if (i + 1 < shown.size) {
                    Some(shown[i + 1])
                } else {
                    None
                })
                HStack {
                    Flexible { projectCard(model, d, left, dark) }
                    match (right) {
                        case Some(rp) => Flexible { projectCard(model, d, rp, dark) }
                        // 奇数张时补一个占位，否则最后一行只剩左半边，
                        // 视觉上像「右边那块丢了」。
                        case None => Flexible { VStack {} }
                    }
                }.spacing(14.0.vp).hug()
                i += 2
            }
        }
    }.crossAxisAlignment(CrossAxisAlignment.Start).spacing(12.0.vp)
}

/// 一张项目卡。行序对齐 macOS 端 `ProjectProgressCard`。
private func projectCard(model: AppModel, d: Dashboard, p: Project, dark: Bool): Unit {
    let now = nowMillis()
    let f = currentDashFilter(model)
    Panel {
        VStack {
            // 行 1：项目名 + 状态词
            HStack {
                Label(p.name).fontSize(14.0).fontWeight(FontWeight.semiBold)
                Flexible {}
                dsPill(livenessLabel(projectLiveness(p, now)),
                    boardColumnColor(boardColumnOf(projectLiveness(p, now))), dark)
            }.hug()

            // 行 2：一句描述。**读不出来时不能编一句**。
            if (!p.error.isEmpty()) {
                Label(p.error).fontSize(11.0).wrap()
                    .foregroundColor(dsColor(C_RED))
            } else if (p.headline.isEmpty()) {
                Label("没有提交摘要").fontSize(11.0).muted()
            } else {
                Label(p.headline).fontSize(11.0).muted().wrap()
            }

            // 行 3：里程碑完成度 + 分支
            HStack {
                projectMilestoneLine(d, p)
                Spacer()
                Label("分支").fontSize(11.0).muted()
                Label(primaryBranchLabel(p)).fontSize(11.0)
            }.hug()

            // 行 4：提交结构（堆叠条 + 图例）
            let parts = keptCommitParts(f, p)
            if (parts.isEmpty()) {
                // ⚠ 与「提交类型读不出来」要分开说：一个是引擎没给，
                // 一个是筛选把它筛掉了。混同会让用户以为项目没有提交类型。
                Label((if (p.commitTypes.isEmpty()) {
                    "提交类型读不出来"
                } else {
                    "此筛选下没有可画的提交类型"
                })).fontSize(11.0).muted()
            } else {
                Flexible { dsSegBar(parts) }
                HStack {
                    Flexible { commitTypeLegendOf(parts) }
                }.hug()
            }

            // 行 5：最近提交
            recentCommitLine(p)
        }.crossAxisAlignment(CrossAxisAlignment.Start).spacing(8.0.vp)
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
}

/// 分支名。**追踪数组空 ≠ 没有分支** —— 引擎恒发 `currentBranch`。
/// 实测一个 4 分支、无远端基线的仓库：`branches=[]` 而 `currentBranch="main"`，
/// 说成「无分支记录」就是把「明细没追踪到」说成「没有分支」。
private func primaryBranchLabel(p: Project): String {
    if (p.branches.size > 0) {
        return p.branches[0].name
    }
    if (!p.currentBranch.isEmpty()) {
        return p.currentBranch
    }
    return "无分支记录"
}

/// 里程碑完成度。分母只取「达没达成有答案的」，**不含 unknown**。
private func projectMilestoneLine(d: Dashboard, p: Project): Widget {
    var done: Int64 = 0
    var open: Int64 = 0
    var unknown: Int64 = 0
    for (m in d.milestoneItems) {
        if (m.projectName != p.name) {
            continue
        }
        match (m.status) {
            case "done" => done += 1
            case "unknown" => unknown += 1
            case _ => open += 1
        }
    }
    if (done + open + unknown == 0) {
        return Label("无里程碑").fontSize(11.0).muted()
    }
    let decided = done + open
    var text = (if (decided > 0) { "里程碑 ${done * 100 / decided}%" } else { "里程碑无法核验" })
    if (unknown > 0) {
        text += " · ${unknown} 条读不出来"
    }
    return Label(text).fontSize(11.0)
}

/// 最近提交那一行。明细读不到时**必须说读不到**，不能画成空行。
private func recentCommitLine(p: Project): Widget {
    if (!p.error.isEmpty()) {
        return Label("读不出来").fontSize(11.0).muted()
    }
    if (p.branches.size == 0) {
        // 空着的一行会被读成「这个项目什么都没干」
        return Label("分支明细未纳入追踪（提交类型分布仍可用）").fontSize(11.0).muted()
    }
    let b = p.branches[0]
    let head = (if (b.headShort.isEmpty()) { b.name } else { b.headShort })
    let subject = (if (b.headSubject.isEmpty()) { b.summary } else { b.headSubject })
    return HStack {
        Label(head).fontSize(11.0)
        Flexible { Label(subject).fontSize(11.0).muted() }
    }.hug()
}

/// 提交类型总量。**必须单独一个函数**：`VStack` 的闭包不能捕获可变变量，
/// 在闭包外面用 `var` 累加再被闭包读到就编译不过。
private func commitTypeTotal(parts: Array<DsPart>): Int64 {
    var t: Int64 = 0
    for (x in parts) {
        t += x.value
    }
    return t
}

/// 图例：前 4 种 + 「还有 N 种」。
private func commitTypeLegendOf(parts: Array<DsPart>): Widget {
    let total = commitTypeTotal(parts)
    VStack {
        // 用 `for` 而不是 `while` + 计数器：闭包不能捕获可变变量，
        // 而 CUI 的 VStack DSL 只在 `for` 里逐条放控件（没有 `add()`）。
        for (x in parts) {
            if (x.slot < 4) {
                dsLegendRow(x, total)
            }
        }
        if (parts.size > 4) {
            Label("还有 ${parts.size - 4} 种").fontSize(10.0).muted()
        }
    }.crossAxisAlignment(CrossAxisAlignment.Start).spacing(3.0.vp)
}

// ---------------------------------------------------------------------------
// 段 5 右卡：里程碑（macOS 端 `Card(title: milestoneCardTitle(...))`）
// ---------------------------------------------------------------------------

/// 里程碑卡标题。**只准用能诚实表达的那几个 counts 字段**。
///
/// 引擎的 counts 有 10 个键。`open`/`done` 是采集到的事实；
/// `unknown` 是「读不出来」，**不能并进 open 或 done**（并进去等于假装它是目标）；
/// `excludedDisabled`/`orphaned` 属于不该计入的，必须单列说清。
/// 原来这里只写「进行中 N · 已达成 M」，unknown 被静默吞掉 ——
/// 存储损坏时用户看到「进行中 0 · 已达成 0」，读出来是「这个项目群一个里程碑都没有」。
private func milestoneCardTitle(c: MilestoneCounts): String {
    var t = "里程碑 · 进行中 ${c.open} · 已达成 ${c.done}"
    if (c.unknown > 0) {
        t += " · ${c.unknown} 条无法核验"
    }
    if (c.orphaned > 0) {
        t += " · ${c.orphaned} 条所属项目已不在"
    }
    if (c.excludedDisabled > 0) {
        t += " · 已停用项目 ${c.excludedDisabled} 条未计入"
    }
    return t
}

private func milestoneCard(d: Dashboard, dark: Bool): Unit {
    let c = d.milestoneCounts
    Panel {
        VStack {
            Label(milestoneCardTitle(c))
                .fontSize(15.0).fontWeight(FontWeight.semiBold).wrap()
            Divider()
            if (d.milestoneItems.isEmpty()) {
                if (c.degraded || c.storeHealth != "ok") {
                    // 「读不出来」与「没有」必须两种样子
                    Label("里程碑读不出来（不是「没有」）").fontSize(12.0).muted()
                    Label("milestones.json ${c.storeHealth}，读到 ${c.readCount} 条")
                        .fontSize(11.0).muted().wrap()
                } else {
                    Label("暂无里程碑").fontSize(12.0).muted()
                    Label("在「里程碑」页添加").fontSize(11.0).muted()
                }
            } else {
                var i: Int64 = 0
                while (i < d.milestoneItems.size) {
                    milestoneRow(d.milestoneItems[Int64(i)], dark)
                    i += 1
                }
            }
        }.crossAxisAlignment(CrossAxisAlignment.Start).spacing(8.0.vp)
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
}

private func milestoneRow(m: MilestoneItem, dark: Bool): Unit {
    // 状态用**形状**编码而不是颜色：颜色在灰度/色觉障碍下不可辨，
    // 而 CUI 的行是纯文本，形状是唯一能可靠进文字的信息。
    let mark = (if (m.status == "done") {
        "✓"
    } else if (m.status == "dropped") {
        "✕"
    } else if (m.status == "unknown") {
        "?"
    } else {
        "●"
    })
    VStack {
        HStack {
            Label("${mark} ${m.projectName} · ${m.name}").fontSize(11.0).wrap()
            Spacer()
            Label(milestoneDueText(m)).fontSize(10.0).muted()
        }.hug()
        // 核验不了时把**引擎给的原因**说出来。引擎的 `unverifiedReason` 是恒发键
        // （可读时是空串），不读它就等于自己编一句「读不出来」——
        // 而引擎已经把具体原因写好了。
        if (m.status == "unknown" && !m.unverifiedReason.isEmpty()) {
            Label(m.unverifiedReason).fontSize(10.0).wrap()
                .foregroundColor(dsColor(C_ORANGE))
        }
    }.crossAxisAlignment(CrossAxisAlignment.Start).spacing(2.0.vp)
}

/// 到期文本。`daysToTarget == -1` 是「未设置**或日期无效**」——
/// 绝不能掉进「逾期 1 天」那一档：假数字没了，假断言还在。
public func milestoneDueText(m: MilestoneItem): String {
    if (m.targetDate.isEmpty()) {
        return ""
    }
    if (m.daysToTarget < 0) {
        return "${m.targetDate}（日期无效，算不出还剩天数）"
    }
    if (m.daysToTarget >= 0) {
        return "还剩 ${m.daysToTarget} 天"
    }
    return "逾期 ${-m.daysToTarget} 天"
}

// ===========================================================================
// 页：看板（macOS 端 `BoardPage` / `BoardView`）
// ===========================================================================

func boardPane(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    let now = nowMs()
    let all = allProjectsOf(model)
    ScrollView(key: "dd-board-scroll") {
        VStack {
            HStack {
                Label("看板").fontSize(17.0).fontWeight(FontWeight.semiBold)
                Spacer()
                Label("按「要不要你动手」分列，不按项目总数排").fontSize(11.0).muted()
            }.hug()
            for (c in boardColumns()) {
                boardColumnCard(model, app, c, all, now, dark)
            }
            Spacer()
        }.spacing(12.0.vp).padding(16.0.vp)
    }
}

public func boardColumns(): Array<BoardColumn> {
    return [BoardColumn.Attention, BoardColumn.Active, BoardColumn.Quiet, BoardColumn.Other]
}

/// 一列。**空列也把判定依据写出来** ——
/// 「0」既可能是「真没有」也可能是「没量出来」。
private func boardColumnCard(
    model: AppModel,
    app: DesktopApp,
    c: BoardColumn,
    all: ArrayList<Project>,
    now: Int64,
    dark: Bool
): Unit {
    let members = boardMembers(c, all, now)
    Panel {
        VStack {
            HStack {
                dsDot(dsColor(boardColumnColor(c)))
                Label(boardColumnLabel(c)).fontSize(14.0).fontWeight(FontWeight.semiBold)
                Spacer()
                Label("${members.size}").fontSize(12.0).muted()
            }.spacing(6.0.vp).hug()
            Label(boardColumnBasis(c)).fontSize(11.0).muted().wrap()
            Divider()
            if (members.isEmpty()) {
                Label("这一列现在是空的").fontSize(12.0).muted()
            } else {
                for (p in members) {
                    boardCard(model, app, p, now, dark)
                }
            }
        }.spacing(8.0.vp)
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
}

public func boardColumnColor(c: BoardColumn): Int64 {
    match (c) {
        case BoardColumn.Attention => return C_ORANGE
        case BoardColumn.Active => return C_SHALLOW
        case BoardColumn.Quiet => return C_SLATE
        case BoardColumn.Other => return C_GRAY
    }
}

/// 该列里的项目。**纯函数** —— 判据直接喂一组项目与固定时刻。
public func boardMembers(c: BoardColumn, all: ArrayList<Project>, now: Int64): ArrayList<Project> {
    let out = ArrayList<Project>()
    for (p in all) {
        if (boardColumnIs(boardColumnOf(projectLiveness(p, now)), c)) {
            out.add(p)
        }
    }
    return out
}

/// 看板里的一张项目卡。
private func boardCard(model: AppModel, app: DesktopApp, p: Project, now: Int64, dark: Bool): Unit {
    Panel {
        HStack {
            VStack {
                HStack {
                    Label(p.name).fontSize(13.0).fontWeight(FontWeight.semiBold)
                    Label(livenessLabel(projectLiveness(p, now))).fontSize(11.0)
                        .foregroundColor(dsColor(boardColumnColor(boardColumnOf(projectLiveness(p, now)))))
                }.spacing(6.0.vp).hug()
                Label(boardCardLine(p, now)).fontSize(11.0).muted().wrap()
            }.spacing(2.0.vp).hug()
            Spacer()
            Button("打开", {
                =>
                    // 走唯一写入口，不自己拼那三个字段。
                    // 绕过入口的后果不是「代码风格问题」：侧栏仓库组的高亮
                    // 停在别的项目上，而主区已经换成这一个了。
                    openProject(model, p.name)
            }).fontSize(11.0)
        }.spacing(8.0.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.style(dsSurface(DsLevel.Nested, dark)).contentPadding(10.0.vp).hug()
}

/// 项目卡那一行事实。**逐项标出「读不出来」**，
/// 不让某个缺失的字段变成一句看起来完整的谎话。
public func boardCardLine(p: Project, now: Int64): String {
    if (p.failed()) {
        return "读不出来：${p.error}"
    }
    var parts = ArrayList<String>()
    if (p.userDirtyCount > 0) {
        parts.add("未提交 ${p.userDirtyCount}")
    }
    if (p.untrackedCount > 0) {
        parts.add("未跟踪 ${p.untrackedCount}")
    }
    if (p.stashCount > 0) {
        parts.add("stash ${p.stashCount}")
    }
    var merges: Int64 = 0
    for (b in p.branches) {
        if (b.isMergeCandidate()) {
            merges += 1
        }
    }
    if (merges > 0) {
        parts.add("待合入 ${merges}")
    }
    if (parts.isEmpty()) {
        // 没有任何「要动手」的东西时，报最后提交时间 ——
        // 而**读不出来就说读不出来**，不回落到「今天」。
        match (daysSinceLastCommit(p, now)) {
            case Some(age) => return "最近提交：${age} 天前"
            case None => return "最近提交时间读不出来"
        }
    }
    return joinWith(parts, " · ")
}

public func joinWith(items: ArrayList<String>, sep: String): String {
    var out = ""
    var i: Int64 = 0
    for (s in items) {
        if (i > 0) {
            out += sep
        }
        out += s
        i += 1
    }
    return out
}
