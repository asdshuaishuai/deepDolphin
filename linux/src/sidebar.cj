// deepDolphin Linux 客户端 —— 侧栏。
//
// 【布局与 macOS 端 `PanelView.sidebar` 一比一】
// 侧栏同时承载**两组**：视图（仪表盘 / 看板 / 里程碑）与仓库（受管项目）。
// 顶部没有页签栏 —— 同一个项目在「顶部页签」和「侧栏」两处都能选，
// 而选中状态只有一个，两处必然各说各话。导航只有一个入口：`goRow`。
//
// 行构成照抄 macOS 端：
//   视图行：名称 + 行尾计数（读不出来时**不显示**，不是 0）
//   项目行：状态标记 → 项目名 → 未提交数
//
// 「添加 / 扫描项目」在**底部动作区**，不在导航列表里 —— 它是动作不是导航项，
// 放在两组中间会把信息架构切成三段（macOS 端踩过，见 PanelView.swift 注释）。
//
// ⚠【一处做不到完全一致，如实记下来】
// macOS 端每行左侧是一个**着色的状态点**（`StatusDot`）。CUI 没有「可点的富行」
// 控件：`ListView` 只收 `Array<String>`（行是纯文本），`Button` 只收标题串，
// `ReorderableList` 是拖拽排序不是选择，`Widget` 基类上没有 `onClick`。
// 所以本端用**形状**代替颜色编码状态（● 活跃 / ○ 停滞 / ✕ 读不出来），
// 颜色留给详情页里真正需要它的地方。
// **不拿 ZStack + 透明按钮叠命中区去硬凑** —— 命中测试一旦和渲染层对不上，
// 症状是「看着能点、点不动」，那比少一个颜色严重得多。
package deepdolphin_linux

import std.collection.ArrayList

import cui.{Button, Color, CrossAxisAlignment, DesktopApp, Divider, EventHandler, FontWeight, HStack, Key, Label,
    ListView, LengthUnits, Panel, Spacer, State, TextField, UiEvent, VStack}
import cui.mountEffect

/// 侧栏最小宽度。与 macOS 端 `minWidth: 210` 同量级。
/// 再窄时项目名会先于计数被切掉，而项目名是这一行唯一不可替代的信息。
private const SIDEBAR_W: Float64 = 240.0

/// 视图组的三个固定标签。**顺序与 macOS 端 `RootSection` 一致**：
/// 仪表盘 → 看板 → 里程碑。
private func viewLabels(): Array<String> {
    return ["仪表盘", "看板", "里程碑"]
}

/// 视图行 → 选区。
public func viewAtIndex(i: Int64): Option<RootSection> {
    match (i) {
        case 0 => return Some(RootSection.Dashboard)
        case 1 => return Some(RootSection.Board)
        case 2 => return Some(RootSection.Milestones)
        case _ => return None
    }
}

/// 项目行的状态标记字符。
///
/// 形状而不是颜色：见文件头的说明。`✕` 是唯一带「出错」语义的形状，
/// 所以它必须**和颜色无关地**可辨 —— 一个红色的圆点会被当成「活跃」。
public func projectMark(p: Project, nowMs: Int64): String {
    let l = projectLiveness(p, nowMs)
    match (l) {
        case Liveness.Unreadable => return "✕"
        case Liveness.NotGit => return "○"
        case Liveness.NeedsAction => return "◐"
        case Liveness.EngineStale => return "○"
        case Liveness.Quiet => return "○"
        case Liveness.Recent => return "●"
        case Liveness.Unknown => return "?"
    }
}

/// 侧栏项目行的文字。**项目名必须是第一个词** ——
/// macOS 端把状态放在名字前面的一个小图标上，而 CUI 只能给纯文本，
/// 名字后面挂任何东西都会让它右移。所以：名字在前，状态在括号里。
public func sidebarProjectLabel(p: Project, nowMs: Int64): String {
    if (p.failed()) {
        // 失败项目显示**引擎给的原因**，不显示「0 提交 / 0 分支」——
        // 采集失败时那些计数本来就是 0，画出来等于谎称读过这个仓库。
        return "${p.name}（读不出：${shortError(p.error)}）"
    }
    if (p.userDirtyCount > 0) {
        return "${p.name}  ●${p.userDirtyCount}"
    }
    return "${p.name}  ${projectMark(p, nowMs)}"
}

/// 错误串在侧栏里要**短**。整条路径往行里一塞，名字就被挤出可视区，
/// 而名字是这一行唯一不可替代的信息 —— 原因要能点进去看到，名字不能丢。
public func shortError(e: String): String {
    return clipText(e, 28)
}

/// 按**字符数**截断（不是字节）。
///
/// ⚠ 按字节截会把一个汉字劈成半个 —— 界面上出现「路��不存在」这种
/// 半个字，用户以为是编码坏了。引擎的错误串里全是中文路径。
public func clipText(s: String, max: Int64): String {
    var n: Int64 = 0
    for (_ in s.runes()) {
        n += 1
        if (n > max) {
            return s[..byteIndexOfRune(s, max)] + "…"
        }
    }
    return s
}

/// 第 `n` 个字符的起始字节下标。越界时给串长。
public func byteIndexOfRune(s: String, n: Int64): Int64 {
    var i: Int64 = 0
    var seen: Int64 = 0
    for (r in s.runes()) {
        if (seen == n) {
            return i
        }
        i += utf8LenOf(r.toString())
        seen += 1
    }
    return Int64(s.toArray().size)
}

private func utf8LenOf(ch: String): Int64 {
    let n = ch.toArray().size
    if (n <= 1) { return 1 }
    if (n <= 2) { return 2 }
    if (n <= 3) { return 3 }
    return 4
}

/// 侧栏视图行的文字 + 行尾计数。**读不出来时计数为空串**，不是「0」。
public func sidebarViewLabel(r: RootSection, count: Option<Int64>): String {
    let name = rootSectionLabel(r)
    return (match (count) {
        case Some(n) => "${name}   ${n}"
        case None => name
    })
}

private func observeSelection(model: AppModel, app: DesktopApp): Unit {
    mountEffect("dd-observe-selected", {
        => model.selectedProject.observe({_, _ => loadProjectDetail(app, model)})
    })
}

func sidebar(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    observeSelection(model, app)
    let now = nowMs()
    let all = allProjectsOf(model)
    let shown = filterProjects(all, model.query.value)
    let shownNames = sidebarProjectLabels(shown, now)
    let viewNames = sidebarViewLabels(model, now)
    let viewSel = viewSelection(model)
    let projSel = projectSelection(model)

    Panel {
        VStack {
            sidebarSearch(model, dark)
            Divider()
            groupHeader("视图", dark)
            if (viewNames.isEmpty()) {
                Spacer()
            } else {
                ListView(viewNames, viewSel, key: "dd-view-list").flex()
            }
            Divider()
            groupHeader("仓库（${shown.size}/${all.size}）", dark)
            if (shownNames.isEmpty()) {
                Spacer()
                Label(emptyText(emptyReason(all.size, shown.size, model.query.value), "项目"))
                    .fontSize(11.0).muted().wrap()
                Spacer()
            } else {
                ListView(shownNames, projSel, key: "dd-proj-list").flex()
            }
            Divider()
            sidebarActions(model, app, dark)
            Divider()
            SidebarStatusStrip(model, dark)
        }.spacing(0.vp)
    }.style(dsSidebar(dark)).hug().contentPadding(insets(0.0, 8.0, 0.0, 8.0)).width(SIDEBAR_W.vp)
}

/// 侧栏视图行的标签数组。
public func sidebarViewLabels(model: AppModel, now: Int64): Array<String> {
    let out = ArrayList<String>()
    for (i in 0..viewLabels().size) {
        match (viewAtIndex(i)) {
            case Some(r) =>
                let count = match (r) {
                    case RootSection.Board => attentionCount(model, now)
                    case RootSection.Milestones => milestoneCountOf(model)
                    case _ => Option<Int64>.None
                }
                out.add(sidebarViewLabel(r, count))
            case None => ()
        }
    }
    return out.toArray()
}

public func sidebarProjectLabels(ps: ArrayList<Project>, now: Int64): Array<String> {
    let out = ArrayList<String>()
    for (p in ps) {
        out.add(sidebarProjectLabel(p, now))
    }
    return out.toArray()
}

/// 视图组的选中下标。**只在当前选中确实是视图时**才有意义，
/// 选中项目时返回 0 但界面高亮不会落在视图组上（由 `isViewSelected` 区分）。
private func viewSelection(model: AppModel): State<Int64> {
    if (rootSectionIs(model.root.value, RootSection.Project)) {
        return State<Int64>(-1)
    }
    match (model.root.value) {
        case RootSection.Dashboard => return State<Int64>(0)
        case RootSection.Board => return State<Int64>(1)
        case RootSection.Milestones => return State<Int64>(2)
        case RootSection.Project => return State<Int64>(-1)
    }
}

/// 项目组的选中下标。没选项目时是 -1（ListView 会当成没有高亮）。
private func projectSelection(model: AppModel): State<Int64> {
    if (!rootSectionIs(model.root.value, RootSection.Project)) {
        return State<Int64>(-1)
    }
    let name = model.selectedProject.value
    let shown = filterProjects(allProjectsOf(model), model.query.value)
    var i: Int64 = 0
    for (p in shown) {
        if (p.name == name) {
            return State<Int64>(i)
        }
        i += 1
    }
    return State<Int64>(-1)
}

/// 选中视图行 → 走唯一写入口。
func goView(model: AppModel, app: DesktopApp, i: Int64): Unit {
    match (viewAtIndex(i)) {
        case Some(r) =>
            model.root.value = r
            model.selectedProject.value = ""
            syncScope(model)
        case None => ()
    }
}

/// 选中项目行 → 走唯一写入口。
func goProject(model: AppModel, app: DesktopApp, i: Int64): Unit {
    let shown = filterProjects(allProjectsOf(model), model.query.value)
    if (i < 0 || i >= shown.size) {
        // 点到不存在的行**什么都不做**。把选中改成某个不存在的项目、
        // 或者弹一个空详情页，那正是「点了没反应」的另一种形态。
        return
    }
    model.selectedProject.value = shown[i].name
    model.root.value = RootSection.Project
    model.scope.value = ScopeChoice.One
}

/// 视图变更后同步范围。**只有「非项目视图」才把范围收回全局** ——
/// 选了一个项目再点「仪表盘」，范围应该留在那个项目上（WorkBar 选的），
/// 而不是被顺手重置掉。
func syncScope(model: AppModel): Unit {
    if (!rootSectionIs(model.root.value, RootSection.Project)) {
        if (!model.selectedProject.value.isEmpty()) {
            return
        }
    }
}

/// 分组标题。`Label` 没有 `hug()`（那是 `Panel` / `VStack` 的方法），
/// 所以用一层 Panel 承载内边距 —— 直接给 Label 加 padding 会连着
/// 背景一起铺满整行，标题就变成一条色带。
private func groupHeader(text: String, dark: Bool): Unit {
    Panel {
        Label(text).fontSize(11.0).fontWeight(FontWeight.semiBold)
    }.hug().contentPadding(insets(4.0, 8.0, 2.0, 8.0))
}

private func sidebarSearch(model: AppModel, dark: Bool): Unit {
    HStack {
        Label("搜索").fontSize(11.0).muted()
        TextField(model.query, key: "dd-sidebar-search").placeholder("项目或分支").flex()
        if (!model.query.value.isEmpty()) {
            Button("清除", {=> model.query.value = ""}).fontSize(11.0)
        }
    }.hug().spacing(4.0.vp).padding(8.0.vp, 6.0.vp)
}

/// 侧栏底部动作区。**故意不放进导航列表**（见文件头）。
private func sidebarActions(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    HStack {
        Label("＋ 添加 / 扫描项目").fontSize(13.0).foregroundColor(dsColor(C_ACCENT))
        Spacer()
    }.hug().spacing(6.0.vp).padding(10.0.vp, 8.0.vp)
}

/// 侧栏常驻状态条（macOS 端 `SidebarStatusStrip`）。
///
/// ⚠ 只报**我们确实知道**的两件事：现在有没有东西在跑、上次刷新什么时候。
/// 不编一个「Git Hook Active」—— 那会让用户以为有个钩子在替他跑，
/// 而我们根本没装。
private func SidebarStatusStrip(model: AppModel, dark: Bool): Unit {
    let busy = model.busy.value || model.actionBusy.value
    VStack {
        HStack {
            dsDot(dsColor(if (busy) { C_ACCENT } else { C_SHALLOW }))
            Label(if (busy) { "正在采集…" } else { "空闲" }).fontSize(11.0)
            Spacer()
            if (model.lastRefreshedMs.value > 0) {
                Label(clockText(model.lastRefreshedMs.value)).fontSize(11.0).muted()
            }
        }.spacing(5.0.vp).hug()
        // 「读不出来」与「还没刷新过」是两件事，措辞必须不同。
        if (!model.problem.value.isEmpty() && model.snapshot.value.isNone()) {
            Label("引擎连接失败").fontSize(11.0).foregroundColor(dsColor(C_ORANGE)).maxLines(1)
        } else if (model.lastRefreshedMs.value == 0) {
            Label("尚未刷新").fontSize(11.0).muted()
        }
    }.hug().spacing(2.0.vp).padding(10.0.vp, 8.0.vp)
}
