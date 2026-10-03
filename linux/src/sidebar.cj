// deepDolphin Linux 客户端 —— 侧栏。
//
// 【布局与 macOS 端 `PanelView.sidebar` 一比一】
// 侧栏同时承载**两组**：视图（仪表盘 / 看板 / 里程碑）与仓库（受管项目）。
// 顶部没有页签栏 —— 同一个项目在「顶部页签」和「侧栏」两处都能选，
// 而选中状态只有一个，两处必然各说各话。
// 导航只有两个写入口：切视图 `goView` / 进项目 `openProject`，
// 侧栏之外的入口（范围下拉、看板卡）也必须走它们 ——
// 绕过入口就会留下「主区是 B、侧栏亮着 A」。
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
import cui.{EffectCleanup}

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
    // 侧栏两组的点击接回路由
    observeSidebarSelection(model)
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

/// 视图组的选中态。**直接返回持久 state，不是每次新建一个常量**。
///
/// ⚠ 原来这里是「每帧从 `root` 现算」：`if (是项目页) return State(-1)`，
/// 然后 `match (root) { … }`，每次重建都造一个**新实例**。
/// 而 CUI 的 `ListView` 点击**直接写**传入的 `selected`
/// （`selection_widgets.cj` 的 handle）—— 写进那个临时实例，
/// 下一帧重建就没了，于是**侧栏点了不换页**。
/// 它自己的滚动状态特意用 `localState(key)` 持久化（注释写着
/// 「a fresh State each frame would reset」），选中没做同样保护，
/// 因为设计上就假定外部传进来的是**持久实例**。
/// 更能说明问题的旁证：`goView` / `goProject` 两个写入口当时已写好，
/// 却**从未被任何地方调用** —— 接线的那一步漏了。
public func viewSelection(model: AppModel): State<Int64> {
    return model.viewIndex
}

/// 项目组的选中下标。没选项目时是 -1（ListView 会当成没有高亮）。
/// 同样返回持久 state，理由见 `viewSelection`。
public func projectSelection(model: AppModel): State<Int64> {
    return model.selected
}

/// 把 ListView 的选中接回路由。
///
/// `mountEffect` 按 key 去重，重建时不会重复注册观察。
/// 两个观察者合成**一个** effect：它们同生同灭（都随侧栏一起挂载/卸载），
/// 拆成两个 key 只是多一次去重表查找，没有语义差别。
/// ⚠ 无回环的要点：`goView(-1)` 是**哑操作**（viewAtIndex(-1) 返回 None），
/// 所以「进项目详情时把 viewIndex 置 -1」不会又触发一次导航。
private func observeSidebarSelection(model: AppModel): Unit {
    mountEffect("dd-obs-sidebar-sel", {=> installSidebarSelectionObservers(model)})
}

/// ⚠⚠ **接线本体**。这里不是「顺手写的辅助函数」——
/// 它是「侧栏点一下会不会换页」这条规则的**唯一实现**，
/// 原来整段塞在 `mountEffect` 的闭包里，而闭包要活动的 StateStore
/// 才能执行（`declareLifecycleEffect` → `currentStateStore()`），
/// 判据不开窗就跑不了。后果是：
/// **把 `sidebar()` 里那行调用删掉，118 条判据全绿，侧栏从此点了不换页。**
///
/// 拆出来的理由与 `goView` 去掉 `app` 参数一样：
/// 能不开窗口就验的规则，绝不因为「它住在闭包里」就变成只能读代码相信。
///
/// 装上之后，`model.selected` / `model.viewIndex` 被写（ListView 点击就是
/// 直接写这两个 State，见 `AppModel.selected` 的注释）就会走路由。
///
/// ⚠ 返回值**必须被持有**：`observe` 返回的 `StateObservation` 是
/// `Resource`，析构会 `close()`，而 `close()` 就是「取消以后的回调」。
/// 丢在当场 = 装上又立刻取消 = 侧栏点了不换页，且没有任何报错。
/// 用 CUI 自己的 `EffectCleanup` 包一层，不要自己再造一个 Resource。
public func installSidebarSelectionObservers(model: AppModel): Resource {
    let v = model.viewIndex.observe({_, v => goView(model, v)})
    let p = model.selected.observe({_, v => goProject(model, v)})
    return EffectCleanup({=> v.close(); p.close()})
}

/// 侧栏「仓库」组里某个项目所在的行号。
///
/// ⚠ **按侧栏真正显示的那份列表算**（过了搜索），不是按全量列表。
/// 返回 -1 = 搜索把这一行滤掉了、界面上根本没有这一行 ——
/// 「这一行看不见」和「这一行是第 0 行」是两件事，混起来就会高亮一个不相干的仓库。
public func sidebarProjectIndex(model: AppModel, name: String): Int64 {
    let shown = filterProjects(allProjectsOf(model), model.query.value)
    var i: Int64 = 0
    for (p in shown) {
        if (p.name == name) {
            return i
        }
        i += 1
    }
    return -1
}

/// 切到某个视图的**唯一**写入口：路由 + 侧栏两组高亮**一起**写。
///
/// ⚠ **不收 `app`**：这个函数原来带着一个 `DesktopApp` 参数却根本没用它。
/// 带着它就等于「这一步需要开窗口」，于是判据只能开窗才能验 ——
///
/// 能不开窗口就验的规则，绝不挪到视图测试里去。
/// 真需要 app 的地方（加载详情）是 `loadProjectDetail`，由 `selectedProject`
/// 的观察者调用，与「选谁」这一步分开。
func goView(model: AppModel, i: Int64): Unit {
    match (viewAtIndex(i)) {
        case Some(r) =>
            if (!rootSectionIs(model.root.value, r)) {
                model.root.value = r
            }
            if (!model.selectedProject.value.isEmpty()) {
                model.selectedProject.value = ""
            }
            // 范围条不用在这里「同步」：上面清掉 `selectedProject` 之后，
            // `scopeIndexOf` 自然回落成 0，下拉与主区不会分家。
            // 侧栏：视图组亮这一行，仓库组撤掉高亮。
            // `viewIndex` 就是本次点击写进来的那个值，这一句是给
            // **不经过侧栏**的调用方（范围下拉选「全局」）补上的。
            model.viewIndex.setIfChanged(i)
            model.selected.setIfChanged(-1)
        case None => ()
    }
}

/// 进项目详情的**唯一**写入口 —— 侧栏点、范围下拉点、看板卡「打开」都走它。
///
/// ⚠ 五个字段必须**一起**写：路由三项（`selectedProject` / `root` / `scope`）
/// 加侧栏两组高亮（`viewIndex` / `selected`）。只写路由不写高亮的症状很具体：
/// **主区已经是 B，侧栏还亮着 A**。侧栏高亮改成持久 State 之前它是每帧
/// 从 `selectedProject` 现算的，所以绕过侧栏也「碰巧对」；不再现算了，
/// 每一处导航都得自己负责把高亮跟上。
///
/// ⚠ 全部「值变了才写」：写 `model.selected` 会触发它的观察者 `goProject`，
/// 而 `goProject` 又调回本函数（幂等自愈）。普通 `State` 的 `value = x`
/// 在**值没变时照样通知**（`state.cj` 的 setter 不比较旧值，
/// 抑制要靠 `setIfChanged` 或带 mutation policy 的 State），
/// 无条件写就是无限递归：写 → 通知 → 观察者 → 再写 → 再通知……
/// 枚举（`RootSection` / `ScopeChoice`）本身不实现 `==`，
/// 所以那两处用现成的 `rootSectionIs` / `scopeIs` 谓词判等。
public func openProject(model: AppModel, name: String): Unit {
    model.selectedProject.setIfChanged(name)
    if (!rootSectionIs(model.root.value, RootSection.Project)) {
        model.root.value = RootSection.Project
    }
    if (!scopeIs(model.scope.value, ScopeChoice.One)) {
        model.scope.value = ScopeChoice.One
    }
    // 视图组这时**不该**高亮（项目详情不属于「仪表盘/看板/里程碑」中的任何一个）。
    // 置 -1 不会回环：`goView(-1)` 的 `viewAtIndex(-1)` 返回 None，是哑操作。
    model.viewIndex.setIfChanged(-1)
    model.selected.setIfChanged(sidebarProjectIndex(model, name))
}

/// 选中项目行 → 走唯一写入口。
func goProject(model: AppModel, i: Int64): Unit {
    let shown = filterProjects(allProjectsOf(model), model.query.value)
    if (i < 0 || i >= shown.size) {
        // 点到不存在的行**什么都不做**。把选中改成某个不存在的项目、
        // 或者弹一个空详情页，那正是「点了没反应」的另一种形态。
        return
    }
    openProject(model, shown[i].name)
}

/// ~~视图变更后同步范围~~ —— 已删。
///
/// 它的函数体是空的（两条分支都直接落空），注释却宣称「把范围收回全局」：
/// 一句描述了一个不存在的行为的注释，比没有注释更糟。
/// 而它想做的事其实**已经发生了**：`goView` 对非项目视图会清掉
/// `selectedProject`，`scopeIndexOf` 于是回落成 0，范围下拉自然跟着回到「全局」。
/// 再加一个同步函数，只是让同一个结果有两个来源。
/// macOS 端也没有对应物 —— 它的 `Model.go(_:)` 只写 `selection`，不碰 scope。

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
        //
        // ⚠ 判据必须是**界面上有没有数据**，不是「内部有没有走过刷新流程」。
        // 原来只看 `lastRefreshedMs == 0`，于是夹具模式（数据直接读盘、
        // 不经过刷新流程）下状态条一直写「尚未刷新」—— 而同一屏上
        // 项目列表、仪表盘全是实打实的数据。那句话不是描述，是自相矛盾。
        if (!model.problem.value.isEmpty() && model.snapshot.value.isNone()) {
            Label("引擎连接失败").fontSize(11.0).foregroundColor(dsColor(C_ORANGE)).maxLines(1)
        } else if (model.lastRefreshedMs.value == 0 && model.snapshot.value.isNone()) {
            Label("尚未刷新").fontSize(11.0).muted()
        }
    }.hug().spacing(2.0.vp).padding(10.0.vp, 8.0.vp)
}
