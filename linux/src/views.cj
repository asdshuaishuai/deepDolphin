// deepDolphin Linux 客户端 —— 界面。
//
// 分工：本文件只负责**怎么显示** —— 一切「显示什么」的判断都在 model.cj。
// 这样每条显示规则都能脱离窗口单测（见 model_test.cj），
// 而窗口层只做「把状态画出来」，没有第二份真相。
package deepdolphin_linux

import cui.{Badge, BadgeKind, Button, ButtonRole, Color, CrossAxisAlignment, DesktopApp, Divider}
import cui.{Flexible, FontWeight, HStack, Label, ListView, Panel, Spacer, SurfaceStyle}
import cui.{LengthUnits, TabView, Theme, VStack, rememberState}

// 布局间距令牌。**只有这四个值**——macOS 端有 DSSpacing 同源的约束
// （4/8/12/16/20/24），这里照抄同一套，避免两个客户端的密度悄悄分家。
private let S1: Float64 = 4.0
private let S2: Float64 = 8.0
private let S3: Float64 = 12.0
private let S4: Float64 = 16.0

/// 强调色：海豚蓝。
let DD_ACCENT = Color.rgb(38, 108, 178)

func card(): SurfaceStyle {
    SurfaceStyle(Color.rgb(255, 255, 255), border: Color.rgb(226, 230, 235), borderWidth: 1.0, radius: 12.0)
}

func ddTheme(): Theme {
    Theme(
        bg: Color.rgb(244, 246, 248),
        panel: Color.rgb(255, 255, 255),
        panelEdge: Color.rgb(222, 227, 233),
        text: Color.rgb(28, 32, 38),
        mutedText: Color.rgb(112, 120, 130),
        accent: DD_ACCENT,
        accentText: Color.rgb(255, 255, 255),
        danger: Color.rgb(198, 62, 54),
        field: Color.rgb(250, 251, 252),
        fieldActive: Color.rgb(238, 245, 252),
        panelRaised: Color.rgb(255, 255, 255),
        accentSoft: Color.rgb(228, 240, 252),
        shadow: Color.rgba(40, 50, 60, 0),
        radius: 12.0,
        controlRadius: 6.0,
        borderWidth: 0.0
    )
}

// ---------------------------------------------------------------------------
// 根
// ---------------------------------------------------------------------------

func rootView(model: AppModel, app: DesktopApp): Unit {
    VStack {
        header(model, app)
        Divider()
        Flexible {
            mainArea(model, app)
        }
        Divider()
        statusBar(model)
    }.spacing(S3.vp).padding(S4.vp)
}

func header(model: AppModel, app: DesktopApp): Unit {
    HStack {
        VStack {
            Label("deepDolphin").fontSize(20.fp).fontWeight(FontWeight.semiBold)
            Label(model.engineLabel.value).fontSize(11.fp).muted()
        }.spacing(2.vp).hug()
        Spacer()
        if (model.busy.value) {
            Badge("正在读取…", kind: BadgeKind.Info)
        }
        Button("刷新", {=> requestRefresh(app, model)}, role: ButtonRole.Primary)
            .fontSize(13.fp)
            .key("dd-refresh")
    }.spacing(S3.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
}

func mainArea(model: AppModel, app: DesktopApp): Unit {
    if (model.snapshot.value.isNone()) {
        emptyState(model, app)
    } else {
        let tab = rememberState<Int64>("dd-tab") {0}
        HStack {
            sidebar(model)
            TabView(["仪表盘", "项目详情"], tab) {
                dashboardPane(model)
                detailPane(model)
            }.flex()
        }.spacing(S3.vp)
    }
}

/// 没数据时的空态。**必须说清是「没读到」还是「确实没有」** ——
/// 这两种在界面上长得一模一样，而用户对它们的处置完全不同。
func emptyState(model: AppModel, app: DesktopApp): Unit {
    Panel {
        VStack {
            Label(if (model.busy.value) { "正在读取项目群…" } else { "还没有数据" })
                .fontSize(17.fp).fontWeight(FontWeight.semiBold)
            Label(model.emptyHint.value).fontSize(12.fp).muted()
            if (model.problem.value.isEmpty() && !model.busy.value) {
                Button("重新读取", {=> requestRefresh(app, model)},
                    role: ButtonRole.Primary).fontSize(13.fp)
            }
        }.spacing(S3.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.style(card()).contentPadding(S4.vp).flex()
}

func sidebar(model: AppModel): Unit {
    Panel {
        VStack {
            HStack {
                Label("项目").fontSize(12.fp).muted()
                Spacer()
                Label("${model.snapshot.value.getOrThrow().projects.size}")
                    .fontSize(12.fp).muted()
            }.hug()
            Divider()
            if (model.projectLabels().isEmpty()) {
                Spacer()
                Label("没有已注册项目").fontSize(12.fp).muted()
                Spacer()
            } else {
                ListView(model.projectLabels(), model.selected, key: "dd-projects").flex()
            }
        }.spacing(S3.vp)
    }.style(card()).contentPadding(S3.vp).hug().width(230.vp)
}

// ---------------------------------------------------------------------------
// 仪表盘
// ---------------------------------------------------------------------------

func dashboardPane(model: AppModel): Unit {
    let snap = model.snapshot.value.getOrThrow()
    let dashOpt = model.dashboard.value
    // 聚合没读到时用空聚合占位，**但项目列表照常显示** ——
    // 两份数据互不连坐，不能因为 dashboard 挂了就把 status 也清掉。
    let dash = (if (dashOpt.isSome()) { dashOpt.getOrThrow() } else { Dashboard.empty() })
    Panel {
        VStack {
            HStack {
                Label("项目群脉搏").fontSize(16.fp).fontWeight(FontWeight.semiBold)
                Spacer()
                Label("统计于 ${snap.generatedAt}").fontSize(11.fp).muted()
            }.hug()
            Divider()

            HStack {
                kpiCard("已注册", "${snap.listedProjects}", BadgeKind.Accent)
                kpiCard("读取失败", snap.failedLabel(), failureKind(snap))
                kpiCard("活跃", "${snap.activeProjects}", BadgeKind.Success)
                kpiCard("停滞", "${snap.staleProjects}", BadgeKind.Warning)
                kpiCard("未提交", "${snap.dirtyProjects}", (if (snap.dirtyProjects > 0) {
                    BadgeKind.Warning
                } else {
                    BadgeKind.Neutral
                }))
                kpiCard("分支", "${snap.branchCount}", BadgeKind.Neutral)
            }.spacing(S2.vp).hug()

            Divider()

            if (snap.failedProjects > 0) {
                failurePanel(snap)
                Divider()
            }

            HStack {
                Flexible {
                    VStack {
                        Label("提交构成").fontSize(13.fp).fontWeight(FontWeight.semiBold)
                        Divider()
                        languageList(dash)
                    }.spacing(S2.vp).hug()
                }
                Flexible {
                    VStack {
                        Label("待办").fontSize(13.fp).fontWeight(FontWeight.semiBold)
                        Divider()
                        Label("分支 ${dash.branches}").fontSize(12.fp)
                        Label("待合入 ${dash.mergeCandidates}").fontSize(12.fp)
                        Label("未跟踪 ${dash.untrackedFiles}").fontSize(12.fp)
                        Label("stash ${dash.stashes}").fontSize(12.fp)
                    }.spacing(S2.vp).hug()
                }
            }.spacing(S3.vp)
        }.spacing(S3.vp)
    }.style(card()).contentPadding(S4.vp).flex()
}

func kpiCard(title: String, value: String, kind: BadgeKind): Unit {
    Panel {
        VStack {
            Label(value).fontSize(22.fp).fontWeight(FontWeight.semiBold)
            Badge(title, kind: kind)
        }.spacing(S1.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.style(card()).contentPadding(S3.vp).flex()
}

/// 失败披露面板。
///
/// 存在的理由：引擎把「读不到」编码成项目条目上的 `error`，
/// 而不是把它从列表里删掉。客户端要是照单全收地只画好的那批，
/// 「已注册 6 个」在界面上会变成 3 个 —— 用户无从知道少了什么。
private func failureKind(snap: StatusSnapshot): BadgeKind {
    if (!snap.failedKnown) {
        return BadgeKind.Warning
    }
    return if (snap.failedProjects > 0) { BadgeKind.Danger } else { BadgeKind.Success }
}

/// 列出每个失败项目与它的原因，一个都不折叠。
private func failurePanel(snap: StatusSnapshot): Unit {
    Panel {
        VStack {
            Label("以下项目读取失败（原因来自引擎，不是客户端推断）")
                .fontSize(13.fp).fontWeight(FontWeight.semiBold)
            Divider()
            for (p in snap.projects) {
                if (p.failed()) {
                    HStack {
                        Badge(p.name, kind: BadgeKind.Danger)
                        Flexible {Label(p.error).fontSize(12.fp)}
                    }.spacing(S2.vp).hug()
                }
            }
        }.spacing(S2.vp)
    }.style(SurfaceStyle(Color.rgb(253, 244, 243), border: Color.rgb(240, 205, 200), borderWidth: 1.0, radius: 10.0))
    .contentPadding(S3.vp).hug()
}

func languageList(dash: Dashboard): Unit {
    if (dash.languages.isEmpty()) {
        Label("没有采集到语言分布").fontSize(12.fp).muted()
    } else {
        var n = 0
        for (l in dash.languages) {
            if (n >= 8) {
                Label("…共 ${dash.languages.size} 种").fontSize(11.fp).muted()
                break
            }
            HStack {
                Label(l.language).fontSize(12.fp)
                Spacer()
                Label("${l.count}").fontSize(12.fp).muted()
            }.hug()
            n += 1
        }
    }
}

// ---------------------------------------------------------------------------
// 项目详情
// ---------------------------------------------------------------------------

func detailPane(model: AppModel): Unit {
    let snap = model.snapshot.value.getOrThrow()
    let idx = model.selected.value
    if (idx < 0 || idx >= snap.projects.size) {
        Panel {
            VStack {
                Label("在左侧选一个项目").fontSize(15.fp)
                Label("Tab 聚焦列表后用 ↑/↓ 切换").fontSize(12.fp).muted()
            }.spacing(S2.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
        }.style(card()).contentPadding(S4.vp).flex()
    } else {
        projectDetail(snap.projects[idx])
    }
}

func projectDetail(p: Project): Unit {
    Panel {
        VStack {
            HStack {
                Label(p.name).fontSize(17.fp).fontWeight(FontWeight.semiBold)
                Badge(activityLabel(p.activity()), kind: activityKind(p.activity()))
                Spacer()
                if (p.failed()) {
                    Badge("读取失败", kind: BadgeKind.Danger)
                }
            }.hug()
            Label(p.path).fontSize(11.fp).muted()
            Divider()

            if (p.failed()) {
                // 失败项目只显示原因。**不显示「0 提交 / 0 分支」** ——
                // 采集失败时这些计数本来就是 0，画出来等于谎称读过这个仓库。
                Label("引擎没能读取这个项目：${p.error}").fontSize(13.fp)
                Spacer()
            } else {
                HStack {
                    stat("当前分支", p.currentBranch)
                    stat("默认分支", p.defaultBranch)
                    stat("提交", "${p.commitCount}")
                    stat("分支", "${p.branchCount}")
                    stat("未提交", "${p.userDirtyCount}")
                    stat("未跟踪", "${p.untrackedCount}")
                    stat("stash", "${p.stashCount}")
                    stat("进度条目", "${p.progressEntryCount}")
                }.spacing(S3.vp).hug()
                Divider()
                if (!p.overallSummary.isEmpty()) {
                    Label(p.overallSummary).fontSize(12.fp)
                    Divider()
                }
                Label("分支进度").fontSize(13.fp).fontWeight(FontWeight.semiBold)
                Divider()
                if (p.branches.isEmpty()) {
                    Label("没有分支记录").fontSize(12.fp).muted()
                } else {
                    for (b in p.branches) {
                        branchRow(b)
                    }
                }
                if (!p.warnings.isEmpty()) {
                    Divider()
                    Label("引擎警告").fontSize(13.fp).fontWeight(FontWeight.semiBold)
                    for (w in p.warnings) {
                        Label("· ${w}").fontSize(12.fp)
                    }
                }
                Spacer()
            }
        }.spacing(S2.vp)
    }.style(card()).contentPadding(S4.vp).flex()
}

func stat(title: String, value: String): Unit {
    VStack {
        Label(value).fontSize(14.fp).fontWeight(FontWeight.semiBold)
        Label(title).fontSize(11.fp).muted()
    }.spacing(1.vp).hug()
}

func branchRow(b: Branch): Unit {
    HStack {
        Badge(if (b.isCurrent) { "当前" } else { b.statusLabel },
            kind: activityKind(b.status))
        Label(b.name).fontSize(12.fp)
        Flexible {Label(b.headSubject).fontSize(12.fp).muted()}
        Label(b.headShort).fontSize(11.fp).muted()
        Label(b.headAgo).fontSize(11.fp).muted()
    }.spacing(S2.vp).hug()
}

// ---------------------------------------------------------------------------
// 状态条
// ---------------------------------------------------------------------------

/// 状态条：任何一件「不顺利」的事都必须在这里说出来。
///
/// 三种不顺利各有各的写法，**不能合并成一句「加载失败」**：
///   1. 引擎根本没找到 —— 没数据可谈，必须给出下一步；
///   2. 引擎契约过旧 —— 有数据但不可信，必须说明哪里不可信；
///   3. 部分项目失败 —— 数据可信但不全，必须指出少了谁。
func statusBar(model: AppModel): Unit {
    HStack {
        Badge(kindText(model), kind: (if (model.staleContract.value) {
            BadgeKind.Warning
        } else {
            BadgeKind.Neutral
        }))
        Flexible {Label(model.statusText.value).fontSize(11.fp).muted()}
        if (!model.busy.value && model.canRefresh.value) {
            Label("⌘R 刷新").fontSize(11.fp).muted()
        }
    }.spacing(S2.vp).hug()
}


/// 状态条徽标上的两个字。
private func kindText(model: AppModel): String {
    if (!model.problem.value.isEmpty()) {
        return "异常"
    }
    if (model.staleContract.value) {
        return "版本过旧"
    }
    match (model.snapshot.value) {
        case Some(s) =>
            if (!s.failedKnown) {
                return "未知"
            }
            return if (s.failedProjects > 0) { "部分失败" } else { "正常" }
        case None => return "待读取"
    }
}

func activityLabel(a: String): String {
    match (a) {
        case "active" => return "活跃"
        case "idle" => return "静置"
        case "stale" => return "停滞"
        case "merged" => return "已合入"
        case _ => return "未知"
    }
}

func activityKind(a: String): BadgeKind {
    match (a) {
        case "active" => return BadgeKind.Success
        case "idle" => return BadgeKind.Info
        case "stale" => return BadgeKind.Warning
        case "merged" => return BadgeKind.Accent
        case _ => return BadgeKind.Neutral
    }
}
