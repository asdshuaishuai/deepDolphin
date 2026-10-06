// deepDolphin Linux 客户端 —— 里程碑页 与 项目详情页。
//
// 【项目详情是一列长卡片，不分子页签】（macOS 端 `ProjectDetailView.content`）
// 我先前做成了 5 个子页签（概览/提交构成/分支/日志/git），
// 后果是**同一条事实被拆散**：分支状态在「分支」页、进度日志在「日志」页、
// 提交构成在另一页，用户要回答「这个仓库现在怎么样」得在五个页签间来回切。
// macOS 端把它摊成一列，滚动一次读完 —— 那是能一眼看全信息密度的唯一排法。
//
// 卡片的**顺序也是照抄的**，因为顺序承载因果：
//   页头（名字 + 状态 + 浅/深更新）
//   → 失败原因（红条，只在失败时）
//   → 工程脉搏 + 提交构成（并排两列）
//   → 提交改动（git 动作紧跟页头那一排，不隔四张卡）
//   → 分支进度
//   → 里程碑
//   → 进度日志
//   → 托管文档（每份一张卡）
package deepdolphin_linux

import std.collection.ArrayList

import cui.{Axis, Badge, BadgeKind, Button, ButtonRole, Color, CrossAxisAlignment, DesktopApp, Divider, Dropdown,
    Flexible, FontWeight, HStack, Label, LengthUnits, Panel, ScrollView, Spacer, State, TextArea, TextField, VStack}
import cui.{rememberState}

// ===========================================================================
// 页：里程碑（macOS 端 `MilestonesView`）
// ===========================================================================

func milestonesPane(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    ScrollView(key: "dd-ms-scroll") {
        VStack {
            HStack {
                Label("里程碑").fontSize(fsTitle()).fontWeight(FontWeight.semiBold)
                Spacer()
                if (let Some(n) <- milestoneCountOf(model)) {
                    dsPill("${n} 条", C_SLATE, dark)
                } else {
                    // 读不出来不显示数字。显示 0 等于说「你没有里程碑」。
                    dsAlertPill("未读取", DsAlert.Warn, dark)
                }
            }.hug()

            if (!model.milestonesProblem.value.isEmpty()) {
                Panel {
                    HStack {
                        dsAlertPill("未读取", DsAlert.Warn, dark)
                        Flexible { Label(model.milestonesProblem.value).fontSize(fsCard()).wrap() }
                    }.spacing(8.0.vp).hug()
                }.style(dsTinted(C_ORANGE, dark)).contentPadding(14.0.vp).hug()
            }

            match (model.milestones.value) {
                case None =>
                    if (model.milestonesProblem.value.isEmpty()) {
                        dsEmptyState("尚未读取里程碑", "点工具栏「刷新」读取。", dark)
                    }
                case Some(ms) =>
                    if (ms.milestones.isEmpty()) {
                        // U3：新建表单收成了折叠区头，空态不再说「下面的表单」
                        //（表单不展开就不在下面）—— 指向那个开关。
                        dsEmptyState("没有里程碑", "展开下面的「新建里程碑」新建一条。", dark)
                    } else {
                        for (m in ms.milestones) {
                            milestoneRow(model, app, m, dark)
                        }
                    }
                    if (ms.orphaned > 0 || ms.excludedDisabled > 0) {
                        Label("另有 ${ms.orphaned} 条孤儿记录、${ms.excludedDisabled} 条来自已禁用项目，未在此显示")
                            .fontSize(fsLabel()).muted().wrap()
                    }
            }

            Divider()
            milestoneForm(model, app, dark)
            Spacer()
        }.spacing(10.0.vp).padding(16.0.vp)
    }
}

/// 里程碑一行。U3 重排（基线 milestones.png 的病：4 行 4 颗红实心按钮墙 +
/// 状态胶囊独立占行首把名字推右 + 三行信息撑到 90px 行高）：
/// · 状态胶囊挪进信息列跟在名字后 —— 它说的是这条里程碑的状态，
///   不是这一行的门牌；单独占行首等于让一颗胶囊管排版。
/// · 动作按钮分两组：「达成/重开」是前进作（可逆状态切换），紧邻信息列；
///   「放弃/删除」是破坏对，靠右成组，中间一道竖隔断 —— 读的动作和毁的
///   动作扫一眼就有界限。
/// · 行内「删除」降 Normal（views.cj confirmButtonRoleOf 的纪律原样：
///   满屏红按钮会稀释「红=危险」，确认框才是唯一的红门）。
///   位置保持在最后 —— 一排等宽按钮里最后一个是「删除」，位置本身就是提示。
///   判据钉的是确认框那颗红（model_test），行内这颗不许再染回去。
/// · tag/目标日/提交数与描述收进第二行：行高约 90px 收到约 72px，
///   四行列表省出近一条行的纵深。
private func milestoneRow(model: AppModel, app: DesktopApp, m: Milestone, dark: Bool): Unit {
    let done = m.isDone()
    let stateLabel = (if (done) { "已达成" } else { "进行中" })
    let stateColor = (if (done) { C_SHALLOW } else { C_ACCENT })
    Panel {
        HStack {
            Flexible {
                VStack {
                    HStack {
                        Label(m.name).fontSize(fsCard()).fontWeight(FontWeight.semiBold)
                        dsPill(stateLabel, stateColor, dark)
                        Label(m.projectName).fontSize(fsLabel()).muted()
                    }.spacing(6.0.vp).hug()
                    HStack {
                        if (!m.tag.isEmpty()) {
                            Label("tag " + m.tag).fontSize(fsLabel()).muted()
                        }
                        if (!m.targetDate.isEmpty()) {
                            Label("目标 " + m.targetDate).fontSize(fsLabel()).muted()
                        }
                        if (m.commitsSinceReadable) {
                            Label("自建以来 ${m.commitsSince} 提交").fontSize(fsLabel()).muted()
                        } else {
                            // 读不出就说读不出。回落成「0 提交」等于谎称
                            // 这个里程碑建好之后什么都没发生过。
                            dsAlertPill("提交数读不出", DsAlert.Warn, dark)
                        }
                        if (!m.description.isEmpty()) {
                            Flexible { Label(m.description).fontSize(fsLabel()).muted().wrap() }
                        }
                    }.spacing(10.0.vp).hug()
                }.spacing(2.0.vp).hug()
            }
            // 前动作（可逆，状态机里直通不进确认集合）紧邻信息列。
            if (!done) {
                Button("达成", {=> requestMilestoneAction(app, model, m.projectName, m.name, "done")})
                    .fontSize(fsBody()).width(62.0.vp)
            } else {
                Button("重开", {=> requestMilestoneAction(app, model, m.projectName, m.name, "open")})
                    .fontSize(fsBody()).width(62.0.vp)
            }
            // 四个按钮统一走 requestMilestoneAction（T1）：放弃/删除会被
            // pendConfirm 挂起并弹确认框；达成/重开是可逆的状态切换，
            // 在状态机里直通 —— **不进确认集合**（防确认疲劳，判据有负控钉着）。
            // 竖隔断：左「前进」右「破坏」两组的界限。
            Divider(axis: Axis.Vertical).height(24.0.vp)
            Button("放弃", {=> requestMilestoneAction(app, model, m.projectName, m.name, "drop")})
                .fontSize(fsBody()).width(62.0.vp)
            Button("删除", {=> requestMilestoneAction(app, model, m.projectName, m.name, "remove")})
                .fontSize(fsBody()).width(62.0.vp)
        }.spacing(8.0.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(12.0.vp, 10.0.vp).hug()
}

/// 「新建里程碑」区。U3 三处改：
/// · 收成一行区头 + 「展开/收起」开关：新建是低频动作，五颗字段 + 按钮常年
///   铺在列表脚下（基线 milestones.png），表单只在展开时在场；
///   判据钉的是 `dd-ms-form-open` 这个 dd-ms- 前缀 key（不许挂错族）。
/// · 表单包进卡片表面（与添加/扫描面板的卡内表单同形态）。
///   右缘收敛的根因在框架测量：TextField.measure 返回 `available.w`
///   （vendor text_field.cj:158），固定宽（.width）之外的裸 TextField 在
///   固定测量趟里会吃满整行可用宽，把日期框顶穿窗缘（基线里目标日期框
///   被切）。行内 TextField 一律 .flex()（走弹性分摊趟），右缘于是
///   对齐到卡片内边距。
/// · 「项目」从手打 TextField 换 Dropdown：已注册项目就在模型里
///   （milestoneProjectChoices 与 scopeLabels 同源 allProjectsOf），
///   默认选中当前 selectedProject —— 让用户照记忆拼名字必然拼错。
///   必填校验（项目、名称都要填）与 actMilestoneAdd 入口原样。
private func milestoneForm(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    let choices = milestoneProjectChoices(model)
    let projectIndex = rememberState<Int64>("dd-ms-project-index") {milestoneProjectDefaultIndex(model)}
    let name = rememberState<String>("dd-ms-name") {""}
    let tag = rememberState<String>("dd-ms-tag") {""}
    let date = rememberState<String>("dd-ms-date") {""}
    let desc = rememberState<String>("dd-ms-desc") {""}
    // 展开态默认收起；DD_SNAP_MS_FORM 快照经 model.snapMsFormOpen 预置
    //（开关走模型字段，与 DD_SNAP_CLICK 同一条通路，不绕过视图状态）。
    let formOpen = rememberState<Bool>("dd-ms-form-open") {model.snapMsFormOpen}
    let toggleLabel = (if (formOpen.value) { "收起" } else { "展开" })
    let arrow = (if (formOpen.value) { "▾" } else { "▸" })
    VStack {
        HStack {
            Label(arrow).fontSize(fsLabel()).muted()
            dsCardTitle("新建里程碑")
            Spacer()
            Button(toggleLabel, {=> formOpen.value = !formOpen.value}).fontSize(fsLabel())
                .key("dd-ms-form-toggle")
        }.spacing(6.0.vp).hug()
        if (formOpen.value) {
            Panel {
                VStack {
                    HStack {
                        Dropdown(choices, projectIndex, key: "dd-ms-project-choice").width(190.0.vp)
                        TextField(name, key: "dd-ms-name").placeholder("名称").flex()
                        TextField(tag, key: "dd-ms-tag").placeholder("tag（可空）").width(140.0.vp)
                        TextField(date, key: "dd-ms-date").placeholder("目标日期 YYYY-MM-DD").width(170.0.vp)
                    }.spacing(8.0.vp).hug()
                    HStack {
                        TextField(desc, key: "dd-ms-desc").placeholder("描述（可空）").flex()
                        Button("新建", {
                            =>
                            let project = milestoneProjectChoiceAt(choices, projectIndex.value)
                            if (project.isEmpty() || name.value.isEmpty()) {
                                model.report("项目和名称都要填", false)
                            } else {
                                actMilestoneAdd(app, model, project, name.value, tag.value, date.value, desc.value)
                            }
                        }, role: ButtonRole.Primary).fontSize(fsCard()).width(88.0.vp)
                    }.spacing(8.0.vp).hug()
                }.spacing(8.0.vp)
            }.style(dsSurface(DsLevel.Card, dark)).contentPadding(12.0.vp).hug()
        }
    }.spacing(8.0.vp).hug()
}

/// 新建里程碑「项目」下拉的选项：**只列已注册项目**。
/// 与 `views.cj` 的 `scopeLabels` 同一条源（`allProjectsOf`）——
/// 项目清单在模型里，不该让用户手打。
public func milestoneProjectChoices(model: AppModel): Array<String> {
    let out = ArrayList<String>()
    for (p in allProjectsOf(model)) {
        out.add(p.name)
    }
    return out.toArray()
}

/// 下拉的默认选中：当前 `selectedProject` 在选项里的下标；读不出/不在列表
/// （含项目群未读）回落 0。**不许回落 -1**：Dropdown 对越界下标夹边界，
/// -1 会显示成第 0 项而状态却是 -1，两处各说各话。
public func milestoneProjectDefaultIndex(model: AppModel): Int64 {
    let selected = selectedProjectNameOf(model)
    var i: Int64 = 0
    for (p in allProjectsOf(model)) {
        if (p.name == selected) {
            return i
        }
        i += 1
    }
    return 0
}

/// 下拉下标 → 项目名。越界（含选项为空）给空串 —— 必填校验
/// 「项目和名称都要填」接得住空串，而不是替用户猜一个项目。
public func milestoneProjectChoiceAt(choices: Array<String>, index: Int64): String {
    if (choices.isEmpty() || index < 0 || index >= choices.size) {
        return ""
    }
    return choices[index]
}

public func selectedProjectNameOf(model: AppModel): String {
    return model.selectedProject.value
}

// ===========================================================================
// 页：项目详情（一列长卡片）
// ===========================================================================

func projectDetail(model: AppModel, app: DesktopApp, p: Project, dark: Bool): Unit {
    let now = nowMs()
    ScrollView(key: "dd-detail-scroll") {
        VStack {
            detailHeader(model, app, p, now, dark)
            if (p.failed()) {
                // 失败项目只显示原因。**不显示「0 提交 / 0 分支」** ——
                // 采集失败时这些计数本来就是 0，画出来等于谎称读过这个仓库。
                Panel {
                    HStack {
                        dsAlertPill("读取失败", DsAlert.Error, dark)
                        Flexible { Label("引擎没能读取这个项目：${p.error}").fontSize(fsCard()).wrap() }
                    }.spacing(8.0.vp).hug()
                }.style(dsTinted(C_RED, dark)).contentPadding(12.0.vp).hug()
                Spacer()
            } else {
                // ⚠ 两张卡**纵向堆叠，不并排**。
                //
                // macOS 端用的是 2 列 `LazyVGrid`。本端试过
                // `HStack { Flexible{} Flexible{} }`，后果是**两张卡的内容被裁掉**：
                // 工程脉搏卡里「提交」那行只剩半截，提交构成卡的分段色条整个不见 ——
                // 而色条不见了，「提交构成」就退化成一张只有图例的表，读不出比例。
                //
                // 根因是 CUI 的 `HStack` 给两个 `Flexible` 子项分配同一行高，
                // 而这两张卡内容高度差很多，短的那张被按长的裁。
                // 纵向堆叠没有这个问题，而且**卡片顺序与 macOS 端一致**
                // （工程脉搏在前、提交构成在后），信息密度不受影响。
                pulseCard(model, p, now, dark)
                commitTypeCard(p, dark)
                if (p.kind == "git") {
                    gitCard(model, app, p, dark)
                }
                branchCard(p, dark)
                journalCard(model, p, dark)
                docsCards(model, p, dark)
            }
            Spacer()
        }.spacing(14.0.vp).padding(16.0.vp)
    }
}

/// 页头：名字 + 状态 + 路径 + 单项目浅/深更新。
private func detailHeader(model: AppModel, app: DesktopApp, p: Project, now: Int64, dark: Bool): Unit {
    let busy = model.actionBusy.value
    VStack {
        HStack {
            Label(p.name).fontSize(fsTitle()).fontWeight(FontWeight.semiBold)
            dsStatusPill(p.activity(), dark)
            dsPill(livenessLabel(projectLiveness(p, now)),
                boardColumnColor(boardColumnOf(projectLiveness(p, now))), dark)
            // 原来这里挂着一个「分支数已截断」告警，条件是 `p.branchCountTruncated` ——
            // 而引擎的项目对象**不发这个键**，恒为 false，于是这个告警
            // 从来没显示过。留着它等于让人以为「截断时有提示」。
            // 分支截断只在上层 `summary.branchTruncatedProjects` 有**项目群级**计数，
            // 单个项目层面引擎不说，详情页就不谎报。
            Spacer()
            // ⚠ `enabled(true)` = 可点。这里曾把方向写反（拿忙碌当可用条件）：
            // 空闲时灰死、忙碌时可点却被闸门拒 —— 与工具栏/WorkBar 那两对
            // 双轨按钮是同一处笔误（R2-01），一并反转。
            // ⚠ 直连 actUpdate 是**有意**的：这两颗只更新当前这一个仓库
            // （mac 端 Model.runUpdate 的 .project 分支同口径，不进确认集合）；
            // 要过确认框的是「全部」目标 —— 那在 requestUpdate 里判，别挪过来。
            Button("浅更新", {=> actUpdate(app, model, p.name, false)}).fontSize(fsBody()).enabled(!busy)
            Button("深更新", {=> actUpdate(app, model, p.name, true)}, role: ButtonRole.Primary)
                .fontSize(fsBody()).enabled(!busy)
        }.crossAxisAlignment(CrossAxisAlignment.Center).hug()
        Label(p.path).fontSize(fsLabel()).muted().maxLines(1)
        // 上一次动作的结果。写在页头而不是状态条 ——
        // 详情页里刚按完的按钮，结果不该要用户把视线移到底部才看到。
        if (!model.lastResult.value.isEmpty()) {
            HStack {
                dsPill(if (model.lastResultOk.value) { "完成" } else { "未完成" },
                    (if (model.lastResultOk.value) { C_SHALLOW } else { C_RED }), dark)
                Flexible { Label(model.lastResult.value).fontSize(fsBody()).wrap() }
            }.spacing(8.0.vp).hug()
        }
    }.spacing(2.0.vp).hug()
}

/// 卡 1/2：工程脉搏。
private func pulseCard(model: AppModel, p: Project, now: Int64, dark: Bool): Unit {
    Panel {
        VStack {
            dsCardTitle("工程脉搏")
            // 合并提示**顶在最前面**。它是这张卡里唯一一句「现在该动手做什么」的话，
            // 埋在中间会被当背景噪音。实测 moonpainter 有 154 个提交可直接
            // fast-forward 却没有任何可合并分支 —— 少了这一条它显示成「一切正常」。
            match (p.mergeHint) {
                case Some(h) =>
                    if (h.actionable()) {
                        // fast-forward 绿 / merge 橙，与 macOS 端
                        // `DetailViews.swift:355` 的取色同一条。
                        // `DsAlert` 只有 Info/Warn/Error 三档、没有「好」，
                        // 所以这里不用 `dsAlertPill`（它按档取色），
                        // 改用 `dsTinted` 自己上色。
                        let tint = (if (h.kind == "fast-forward") { C_SHALLOW } else { C_ORANGE })
                        Panel {
                            HStack {
                                dsPill(
                                    (if (h.kind == "fast-forward") { "可快进" } else { "需合并" }),
                                    tint, dark)
                                // 用引擎写好的整句，不在客户端重拼 ——
                                // 「需三方合并（领先 20 / 落后 4）」这种口径只有引擎知道。
                                Flexible { Label(h.description).fontSize(fsBody()).wrap() }
                            }.spacing(8.0.vp).hug()
                        }.style(dsTinted(tint, dark)).contentPadding(10.vp).hug()
                        // 尾随 Divider 摘掉（U3）：下面那条无条件 Divider 是
                        // 唯一的分隔 —— 原来可合并提示在场时这里出现双线。
                    }
                case None => ()
            }
            Divider()
            // ⚠ Spacer 只能有**一个且放最后**。
            //
            // 原来每个统计项之间都插 Spacer，结果这三行在 1300px 宽的卡里
            // 被撑到两端 —— 两个数字各站一个角、中间一大片空白，
            // 「一组要互相对照的数字」被拉成了「两个互不相干的数字」。
            // 聚在左边才读得出它们是一组。
            //
            // 分支身份降为一行正文（U3，branchHeaderLine）：「main」当 22px
            // 大字摆既不含量级信息还占一行；并进「现状」组，行首与下面的
            // 计数行同轴。判据钉的是 pulseCard 不再调 dsInlineStat 画分支。
            VStack {
                Label(branchHeaderLine(p)).fontSize(fsBody())
                HStack {
                    dsInlineStat("未提交", "${p.userDirtyCount}", dsStatColor(dsStatFrom(p.userDirtyCount)))
                    dsInlineStat("未跟踪", "${p.untrackedCount}", dsStatColor(dsStatFrom(p.untrackedCount)))
                    dsInlineStat("stash", "${p.stashCount}", dsStatColor(dsStatFrom(p.stashCount)))
                    Spacer()
                }.spacing(28.vp).hug()
            }.spacing(4.0.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
            Divider()
            HStack {
                dsInlineStat("提交", "${p.commitCount}", C_SLATE)
                dsInlineStat("工作区", "${p.worktreeCount}", C_SLATE)
                dsInlineStat("进度条目", "${p.progressEntryCount}", C_SLATE)
                Spacer()
            }.spacing(28.vp).hug()
            // 量级分档的话要说出来，不能只靠颜色。
            if (p.userDirtyCount > 0) {
                Divider()
                Label(dsStatLine(p.userDirtyCount, "未提交改动")).fontSize(fsBody())
                    .foregroundColor(dsColor(dsTextColor(dsStatColor(dsStatFrom(p.userDirtyCount)), dark)))
            }
            // `dirty` 是**另一个口径**：上面那排数字是「用户改的」，
            // 这个对象是**引擎读到的**（带 `ok` —— 读不出来时底下数字全是 0）。
            // 两行数字并排却不标口径，用户会以为它们矛盾。
            // 冲突（会丢代码的那种）由 `dirtyLine` 压在最前面单独说。
            match (p.dirtyInfo) {
                case Some(d) =>
                    Divider()
                    HStack {
                        dsAlertPill("引擎口径", DsAlert.Info, dark)
                        Flexible { Label(dirtyLine(d)).fontSize(fsBody()).wrap() }
                    }.spacing(8.0.vp).hug()
                    let files = dirtyFilesLine(d)
                    if (!files.isEmpty()) {
                        Label(files).fontSize(fsLabel()).muted().wrap()
                    }
                case None => ()
            }
            // tags / manifests 是引擎给的「这是个什么项目」的事实。
            // 实测刚注册的项目两个都是空数组，所以空数组**一律不占位** ——
            // 画一个空的「标签」行只会让人以为这里本来该有东西而没采到。
            let tagLine = projectFactsLine("标签", p.tags)
            let manifestLine = projectFactsLine("依赖清单", p.manifests)
            if (!tagLine.isEmpty() || !manifestLine.isEmpty()) {
                Divider()
                VStack {
                    if (!tagLine.isEmpty()) {
                        Label(tagLine).fontSize(fsBody()).wrap()
                    }
                    if (!manifestLine.isEmpty()) {
                        Label(manifestLine).fontSize(fsBody()).wrap()
                    }
                }.spacing(3.0.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
            }
            Divider()
            // 只说一遍。引擎的 `lastCommitAgo` 是给人看的相对串，
            // 我自己算的天数是为了分列 —— 两者并排显示等于同一句话说两遍。
            // ⚠ 天数算不出来时**不许**显示 0 天前：那等于说这个仓库今天刚提交过。
            //   这时退回引擎的相对串；连它都没有，就明说读不出来。
            match (daysSinceLastCommit(p, now)) {
                case Some(age) => Label("最近提交：${age} 天前").fontSize(fsBody())
                case None =>
                    if (p.lastCommitAgo.isEmpty()) {
                        Label("最近提交时间读不出来").fontSize(fsBody())
                            // 灰字过闸门：C_GRAY 原色对白卡只有 2.56:1，亮色主题换 C_SLATE 深档。
                            .foregroundColor(dsColor(dsTextColor(C_GRAY, dark)))
                    } else {
                        Label("最近提交：${p.lastCommitAgo}").fontSize(fsBody())
                    }
            }
            if (overallSummaryShows(p)) {
                Divider()
                Label(p.overallSummary).fontSize(fsBody()).wrap()
            }
            // `overall.notes` 是引擎给的**另一批**事实，与 warnings 不是同一批。
            // 引擎实测会报「存在 2 条 stash，注意清理」——
            // 上面那排内联统计里有 stash 的**数字**，却**没有「注意清理」这半句**；
            // 非 git 项目则靠它说明「为什么提交数是 0」。引擎算了、模型收了、
            // 界面不说 ⇒ 等于没算。macOS 端 `DetailViews.swift:282` 有这条通路。
            if (!p.overallNotes.isEmpty()) {
                Divider()
                HStack {
                    dsAlertPill("引擎提示", DsAlert.Info, dark)
                    Flexible {
                        VStack {
                            for (n in p.overallNotes) {
                                Label("· ${n}").fontSize(fsLabel()).wrap()
                            }
                        }.spacing(3.0.vp).hug()
                    }
                }.spacing(6.0.vp).hug()
            }
            if (p.storeHealth != "" && p.storeHealth != "ok") {
                Divider()
                HStack {
                    dsAlertPill("进度库异常", DsAlert.Warn, dark)
                    Flexible { Label(p.storeHealth).fontSize(fsLabel()).wrap() }
                }.spacing(6.0.vp).hug()
            }
            if (!p.warnings.isEmpty()) {
                Divider()
                HStack {
                    dsAlertPill("引擎警告", DsAlert.Warn, dark)
                    Flexible {
                        VStack {
                            for (w in p.warnings) {
                                Label("· ${w}").fontSize(fsLabel()).wrap()
                            }
                        }.spacing(3.0.vp).hug()
                    }
                }.spacing(6.0.vp).hug()
            }
        }.spacing(8.0.vp)
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
}

/// 卡 2/2：提交构成（近期）。**两条独立的截断披露**。
private func commitTypeCard(p: Project, dark: Bool): Unit {
    let parts = commitTypeParts(p)
    Panel {
        VStack {
            dsCardTitle("提交构成（近期）")
            if (parts.isEmpty()) {
                Label("没有提交构成数据").fontSize(fsBody()).muted()
            } else {
                Flexible { dsSegBar(parts) }
                var total: Int64 = 0
                for (q in parts) {
                    total += q.value
                }
                for (q in parts) {
                    dsLegendRow(q, total)
                }
            }
            // 引擎的采样窗口与界面的显示上限是**两条轴**，少披露一条就是撒谎。
            for (n in commitTypeNotes(p, parts.size)) {
                HStack {
                    dsAlertPill("披露", DsAlert.Info, dark)
                    Flexible { Label(n).fontSize(fsLabel()).wrap() }
                }.spacing(6.0.vp).hug()
            }
        }.spacing(8.0.vp)
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
}

/// 提交构成的可见切片，**最多 8 种**（与语言分布同档）。
public func commitTypeParts(p: Project): Array<DsPart> {
    let cap: Int64 = 8
    let out = ArrayList<DsPart>()
    var i: Int64 = 0
    for (t in p.commitTypes) {
        if (i >= cap) {
            break
        }
        out.add(DsPart(t[0], t[1], slot: i))
        i += 1
    }
    return out.toArray()
}

/// 提交构成的两条截断披露。**少一条就撒谎**。
public func commitTypeNotes(p: Project, shown: Int64): Array<String> {
    let out = ArrayList<String>()
    var sampled: Int64 = 0
    for (t in p.commitTypes) {
        sampled += t[1]
    }
    if (p.commitTypesTruncated) {
        if (p.commitCount > 0) {
            out.add("引擎只采样了近 ${sampled}/${p.commitCount} 条提交，这不是全量")
        } else {
            out.add("引擎只采样了一部分提交，这不是全量")
        }
    }
    if (shown < p.commitTypes.size) {
        out.add("本卡只列前 ${shown} 种，引擎一共给了 ${p.commitTypes.size} 种")
    }
    return out.toArray()
}

/// 引擎那句 `overall.summary` 要不要显示。
///
/// **套的是 macOS 端同一条规则**（`DetailViews.swift:293`）：
/// > `overall.summary` 是引擎对整条提交历史的概括。`commitTypeLine`
/// > 说的是同一件事的另一种切法，重复画会显得啰嗦，
/// > 所以这里只在**它没被别处说过**时才补位。
///
/// macOS 的判据是「我自己的提交构成行是不是空」，而那行在
/// `commitTypes` 为空时才是 nil —— 所以规则等价于「没有提交类型时才补位」。
/// 本端没有那条自己拼的行，但下面「提交构成」卡片在 `commitTypes` 非空时
/// 一定在，所以「别处说过」同样等价于 `commitTypes` 非空。
///
/// ⚠ 不套这条规则的症状不是「啰嗦」，是**同一屏两套词表**：
/// 引擎摘要写「最近 25 个提交：文档×7、修复×6」，紧挨着的图例写
/// `feat / fix / docs / chore`。读者会以为是两个不同的统计口径。
/// 引擎的词表是中文（新增/修复/文档/更新/构建·依赖/样式/界面），
/// 与 `commitTypes` 的原始词表不是一套。
public func overallSummaryShows(p: Project): Bool {
    return p.commitTypes.isEmpty() && !p.overallSummary.isEmpty()
}

/// 一行「标题：值、值、值」。tags / manifests 共用。
///
/// ⚠ 不用胶囊也不用按钮：这两样都是**只读事实**，
/// 做成可点/有底色的样子会让人以为点得动。
/// 一行放不下必须截断**并说「还有 N 个」** —— 静默截会让人以为标签只有前几个。
public func projectFactsLine(title: String, values: ArrayList<String>): String {
    if (values.isEmpty()) {
        return ""
    }
    let cap: Int64 = 8
    let sb = StringBuilder()
    sb.append(title)
    sb.append("：")
    var i: Int64 = 0
    for (v in values) {
        if (i >= cap) { break }
        if (i > 0) { sb.append("、") }
        sb.append(v)
        i += 1
    }
    let hidden = values.size - cap
    if (hidden > 0) {
        sb.append("、还有 ${hidden} 个")
    }
    return sb.toString()
}

/// git 操作按钮行（gitCard 第一排）。**commit 不在行里**：
/// 它有下面的专属按钮 + 确认框（mac 端 `gitOpButtons` 那一排本来就只放
/// pull/push/fetch/stash/unstash）—— 引擎白名单里的 commit 若照单渲染，
/// 就是一个绕过确认、用空提交信息直连的第二个「提交」。
/// 判据：纯函数测试钉行内成分，源码扫描钉按钮行用的是这份切片。
public func gitRowOps(): Array<String> {
    let out = ArrayList<String>()
    for (op in gitWhitelist()) {
        if (op != "commit") {
            out.add(op)
        }
    }
    return out.toArray()
}

/// 卡 3：提交改动（git 动作）。**紧跟页头那一排按钮**，
/// 不隔四张卡 —— 同一组动作被拆成两半，用户会找不到另一半。
private func gitCard(model: AppModel, app: DesktopApp, p: Project, dark: Bool): Unit {
    // 提交信息的状态在**构建期**创建。放进按钮回调里每次点击都会新建一份，
    // 界面上看着能打字，实际每次按键都在丢弃上一份 —— 症状是「有时打不上字」。
    let msg = rememberState<String>("dd-commit-msg-${p.name}") {""}
    Panel {
        VStack {
            HStack {
                dsCardTitle("提交改动")
                Spacer()
                dsAlertPill("白名单：无 reset / clean / force-push", DsAlert.Info, dark)
            }.hug()
            HStack {
                for (op in gitRowOps()) {
                    Button(gitOpLabel(op), {=> actGit(app, model, p.name, op, "")}).fontSize(fsBody())
                }
            }.spacing(8.0.vp).hug()
            Divider()
            HStack {
                TextField(msg, key: "dd-commit-msg-${p.name}")
                    .placeholder("提交信息（仅 commit 用）").flex()
                // 点提交 ≠ 提交（T1）：引擎的 commit 走 git add -A，提交的是
                // **整个工作区**，不是用户眼前挑的那几个文件。先挂起确认，
                // 确认框点名仓库、报工作区规模与未跟踪文件的密钥风险，
                // 「全部提交」才真跑（mac 端 DetailViews 的 pendingCommit 同款）。
                Button("提交", {=> requestCommit(app, model, p.name, msg.value)}, role: ButtonRole.Primary)
                    .fontSize(fsBody()).width(80.0.vp)
            }.spacing(8.0.vp).hug()
        }.spacing(8.0.vp)
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
}

/// 卡 4：分支进度。
///
/// ⚠ `branches.count` 是引擎**追踪到基线**的数量，不是仓库真实分支数。
/// 实测 16 个分支的仓库这里只显示 7 个；刚注册还没 track 过的显示 0，
/// 而仓库实际有 2 个分支 —— 字面写「分支进度（0）」会让人认定仓库没有分支。
private func branchCard(p: Project, dark: Bool): Unit {
    Panel {
        VStack {
            HStack {
                dsCardTitle("分支进度 · ${branchScopeLine(p)}")
                Spacer()
            }.hug()
            if (p.branches.isEmpty()) {
                Label("引擎没有给出分支记录").fontSize(fsBody()).muted()
            } else {
                for (b in p.branches) {
                    HStack {
                        if (b.isCurrent) {
                            dsPill("当前", C_ACCENT, dark)
                        } else {
                            dsStatusPill(b.status, dark)
                        }
                        // 列宽随 fsBody 12→13 校准（170×13/12），防字大后新截断。
                        Label(b.name).fontSize(fsBody()).maxLines(1).width(190.0.vp)
                        Flexible { Label(b.headSubject).fontSize(fsBody()).muted().maxLines(1) }
                        Label(b.headShort).fontSize(fsLabel()).muted()
                        Label(b.headAgo).fontSize(fsLabel()).muted().width(70.0.vp)
                    }.spacing(8.0.vp).hug()
                    if (b.isMergeCandidate()) {
                        Label("领先默认分支 ${b.aheadOfDefault} 个提交 · 待合入")
                            .fontSize(fsLabel()).foregroundColor(dsColor(dsTextColor(C_YELLOW, dark)))
                    }
                    if (b.baselineReset) {
                        Label("待记录数已失效（基线重建）").fontSize(fsLabel())
                            // 同上：灰字过闸门，亮色主题换 C_SLATE 深档。
                            .foregroundColor(dsColor(dsTextColor(C_GRAY, dark)))
                    }
                    Divider()
                }
            }
        }.spacing(8.0.vp)
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
}

/// 分支计数那一行的口径。**必须把「追踪到的」和「仓库真实的」分开说**。
///
/// ⚠ 「追踪到的」必须自己数 `branches` 数组，不能读 `p.branchCount` ——
/// 引擎的项目对象**不发这个键**（实测 `moongit status --json` 的
/// `projects[i]` 键表里没有它，也没有 `branchCountTruncated`），
/// 原来读它得到的是恒 0，于是这行长期显示
/// 「引擎追踪到 0 / 仓库共 4 个」—— 那个 0 是引擎没说话被当成了事实。
public func branchScopeLine(p: Project): String {
    let tracked = p.branches.size
    if (p.repoBranchCount < 0) {
        return "仓库真实分支数读不出，引擎追踪到 ${tracked} 个"
    }
    return "引擎追踪到 ${tracked} / 仓库共 ${p.repoBranchCount} 个"
}

/// 卡 5：进度日志。
///
/// ⚠ 引擎的 journal 上限是 8 条（light=3 / JSON 恒 8），
/// 而 `progress.entryCount` 是**真实条数**。数组长度当全量 ⇒
/// 用户看到 8 条就以为「就更新过 8 次」。
private func journalCard(model: AppModel, p: Project, dark: Bool): Unit {
    Panel {
        VStack {
            HStack {
                dsCardTitle("进度日志 · ${p.progressEntryCount} 条")
                Spacer()
                if (!model.journalProblem.value.isEmpty()) {
                    dsAlertPill("未读取", DsAlert.Warn, dark)
                }
            }.hug()
            if (!model.journalProblem.value.isEmpty()) {
                Label(model.journalProblem.value).fontSize(fsBody()).wrap()
            } else {
                match (model.journal.value) {
                    case None => Label("尚未读取日志").fontSize(fsBody()).muted()
                    case Some(j) =>
                        if (j.entries.isEmpty()) {
                            Label("这个项目还没有进度日志。跑一次浅更新会生成。").fontSize(fsBody()).muted()
                        } else {
                            for (e in j.entries) {
                                VStack {
                                    HStack {
                                        // 列宽随 fsLabel 11→12 校准（时间列放宽到能放下整串
                                        // 「2026-10-01T00:05:52」，基线里它本来就被截成「…05:…」）。
                                        Label(e.at).fontSize(fsLabel()).muted().width(150.0.vp)
                                        Label(e.branch).fontSize(fsLabel()).maxLines(1).width(130.0.vp)
                                        dsTrackPill(if (e.mode == "deep") { DsTrack.Deep } else { DsTrack.Shallow }, dark)
                                        Label(e.commitText()).fontSize(fsLabel()).muted().width(150.0.vp)
                                        Flexible { Label(e.summary).fontSize(fsLabel()).muted().maxLines(2) }
                                    }.spacing(8.0.vp).hug()
                                    // 口径说明挂在**这一条下面**，不塞进那 140vp 的窄列 ——
                                    // 挤成「+6 口径未知；这是采样值…」会被截掉后半句，
                                    // 而那半句正是「别把它当增量看」的全部理由。
                                    let cn = e.commitNote()
                                    if (!cn.isEmpty()) {
                                        Label(cn).fontSize(fsMicro()).muted().wrap()
                                    }
                                }.spacing(2.0.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
                            }
                            // 两条披露是**两件事**，各占一行，不许合并成一句。
                            // 「已截断」说的是「后面还有」，
                            // 「N 行读不出来」说的是「中间有你看漏的」。
                            if (!j.truncatedNote().isEmpty()) {
                                Label(j.truncatedNote()).fontSize(fsLabel()).muted().wrap()
                            }
                            if (!j.unparsableNote().isEmpty()) {
                                Label(j.unparsableNote()).fontSize(fsLabel()).muted().wrap()
                            }
                        }
                }
            }
        }.spacing(8.0.vp)
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
}

/// 卡 6+：托管文档。**每份一张卡**。
///
/// ⚠ 原来写成「有文档才画卡片」—— 三种情况（正在读 / 没有文档 / 读不出来）
/// 渲染成同一个画面：什么都不画。用户据此认为「这个项目确实没有 README」，
/// 而真相可能是权限问题或引擎超时。所以三种情况各有各的样子。
private func docsCards(model: AppModel, p: Project, dark: Bool): Unit {
    let name = p.name
    VStack {
        match (model.docs.value) {
            case None =>
                Panel {
                    VStack {
                        dsCardTitle("托管文档")
                        if (model.docsProblem.value.isEmpty()) {
                            Label("尚未读取文档").fontSize(fsBody()).muted()
                        } else {
                            dsAlertPill("读不出来", DsAlert.Error, dark)
                            Label(model.docsProblem.value).fontSize(fsBody()).wrap()
                        }
                    }.spacing(6.0.vp).hug()
                }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
            case Some(d) =>
                if (d.docs.isEmpty()) {
                    Panel {
                        VStack {
                            dsCardTitle("托管文档")
                            Label("这个项目还没有受管的文档。跑一次浅更新会生成 README / AGENTS / CLAUDE。")
                                .fontSize(fsBody()).muted().wrap()
                        }.spacing(6.0.vp).hug()
                    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
                } else {
                    for (f in d.docs) {
                        docCard(name, f, dark)
                    }
                }
        }
    }.spacing(10.0.vp).hug()
}

/// 一份托管文档一张卡。U3：默认收成一行标题（文件名 + 字节数 + 「展开原文」
/// 开关）—— 原来标题下常挂一块 220vp 定高只读 TextArea，而载荷常常只有
/// 几十个字节（atlas 实测 README 25 / AGENTS 23 字节），两卡合计约 500px，
/// 是整页信息密度最低的一段（基线 detail-atlas.png 页尾）。原文按文件名
/// 记展开态（dd-doc-open- 前缀 key），展开才渲染 TextArea。
/// 读不出的分支**保持常显不折叠**：失败原因本身就是一句话，
/// 折叠它等于把「文档在」假装出来。
private func docCard(owner: String, f: DocFile, dark: Bool): Unit {
    let docOpen = rememberState<Bool>("dd-doc-open-${owner}-${f.file}") {false}
    let toggleLabel = (if (docOpen.value) { "收起原文" } else { "展开原文" })
    Panel {
        VStack {
            HStack {
                dsCardTitle(f.file)
                Spacer()
                Label("${f.content.size} 字节").fontSize(fsLabel()).muted()
                Button(toggleLabel, {=> docOpen.value = !docOpen.value}).fontSize(fsLabel())
            }.spacing(8.0.vp).hug()
            if (!f.unreadableReason.isEmpty()) {
                dsAlertPill("读不出来", DsAlert.Error, dark)
                Label(f.unreadableReason).fontSize(fsBody()).wrap()
            } else if (docOpen.value) {
                TextArea(State<String>(f.content), key: "dd-doc-${owner}-${f.file}",
                    editable: false).height(220.0.vp)
            }
        }.spacing(6.0.vp).hug()
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(14.0.vp).hug()
}

/// 工程脉搏卡的分支身份句。同分支一句话（即默认分支），异分支两个名字
/// 都要点出来 —— 合成一句「当前分支 main」会谎称默认分支不存在。
public func branchHeaderLine(p: Project): String {
    if (p.currentBranch == p.defaultBranch) {
        return "当前分支 ${p.currentBranch}（即默认分支）"
    }
    return "当前分支 ${p.currentBranch} · 默认分支 ${p.defaultBranch}"
}
