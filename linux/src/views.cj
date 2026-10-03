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

import cui.{Axis, Badge, BadgeKind, Button, ButtonRole, Color, CrossAxisAlignment, DesktopApp, Divider, Flexible,
    FontWeight, HStack, Label, LengthUnits, Panel, ScrollView, Spacer, State, SurfaceStyle, TextArea, TextField,
    VStack, Widget}
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

/// 范围选择器。**只列真实存在的项目** —— 空项目列表时这一项不会被选中，
/// 不会「选了一个不存在的仓库」。
///
/// 用一排按钮而不是下拉：项目多时下拉要滚动才能看全，
/// 而这一段是「我现在在看哪一片」的主链路，需要一眼看到。
private func scopeButtons(model: AppModel, app: DesktopApp, total: Int64, dark: Bool): Unit {
    HStack {
        Button("全局（${total} 个项目）", {
            =>
                model.scope.value = ScopeChoice.Group
                model.root.value = RootSection.Dashboard
        }).fontSize(12.0).style(scopeStyle(scopeIs(model.scope.value, ScopeChoice.Group), dark))
        for (p in allProjectsOf(model)) {
            Button(p.name, {
                =>
                    model.scope.value = ScopeChoice.One
                    model.selectedProject.value = p.name
                    model.root.value = RootSection.Project
            }).fontSize(12.0)
            .style(scopeStyle(
                p.name == model.selectedProject.value && scopeIs(model.scope.value, ScopeChoice.One),
                dark))
        }
    }.spacing(6.0.vp).hug()
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

func dashboardPane(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    ScrollView(key: "dd-dash-scroll") {
        VStack {
            kpiRow(model, dark)
            if (let Some(p) <- model.snapshot.value) {
                if (p.failedProjects > 0 || !p.failedKnown) {
                    failurePanel(p, dark)
                }
            }
            dashboardBody(model, dark)
            Spacer()
        }.spacing(12.0.vp).padding(16.0.vp)
    }
}

/// 仪表盘主体。**读不到就说原因，不画 0**。
private func dashboardBody(model: AppModel, dark: Bool): Unit {
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
        HStack {
            Flexible { languageCard(d, dark) }
            Flexible { workCard(d, dark) }
        }.spacing(12.0.vp)
    }
}

/// KPI 行。颜色**按这个数字的含义**给，不统一给强调色 ——
/// 「读取失败 3」用蓝底等于把异常说成常态。
private func kpiRow(model: AppModel, dark: Bool): Unit {
    match (model.snapshot.value) {
        case Some(s) =>
            HStack {
                Flexible { dsStatCard("已注册", "${s.listedProjects}", C_ACCENT, dark) }
                Flexible {
                    dsStatCard("读取失败",
                        s.failedLabel(),
                        (if (!s.failedKnown) {
                            C_GRAY
                        } else {
                            (if (s.failedProjects > 0) { C_RED } else { C_SLATE })
                        }),
                        dark)
                }
                Flexible { dsStatCard("活跃", "${s.activeProjects}", C_SHALLOW, dark) }
                Flexible {
                    dsStatCard("停滞", "${s.staleProjects}",
                        dsStatColor(dsStatFrom(s.staleProjects)), dark)
                }
                Flexible {
                    dsStatCard("未提交", "${s.dirtyProjects}",
                        dsStatColor(dsStatFrom(s.dirtyProjects)), dark)
                }
                Flexible { dsStatCard("分支", "${s.branchCount}", C_SLATE, dark) }
            }.spacing(10.0.vp).hug()
        case None => ()
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
                    model.selectedProject.value = p.name
                    model.root.value = RootSection.Project
                    model.scope.value = ScopeChoice.One
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
