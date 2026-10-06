// deepDolphin Linux 客户端 —— AI 界面（C5 / C6 / C7）。
//
// 【与 macOS 端的已知结构差异，如实记，不假装一致】
// macOS 是 `Settings` scene + `.sheet`；CUI 的 `DesktopApp` **只有一扇窗**
// （`DesktopApp(spec, theme, …)`，没有窗口数组），所以：
//   · 「AI 设置」「AI 助手」做成**主区里的两个视图**，工具栏按钮来回切
//   · C5 的结果面板做成主区里的一个覆盖层，不是 sheet
// 代价：聊天时看不到仪表盘，要看项目现状得先退出去。
package deepdolphin_linux

import std.collection.*
import cui.{Button, ButtonRole, Color, CrossAxisAlignment, DesktopApp, Divider, Dropdown,
    Flexible, FontWeight, HStack, Key, Label, LengthUnits, Panel, ScrollView, Spacer, State, TextArea,
    TextField, VStack, Widget}
import cui.mountEffect

// ---------------------------------------------------------------------------
// 对话（C6）
// ---------------------------------------------------------------------------

/// 对话作用的项目。**跟着主区范围走** —— 在哪个项目的详情里开对话，
/// 就问哪个项目；不在项目里就是项目群。
public func aiScopeLabel(model: AppModel): String {
    if (rootSectionIs(model.root.value, RootSection.Project) && !model.selectedProject.value.isEmpty()) {
        return "作用域：${model.selectedProject.value}"
    }
    return "作用域：项目群（全部 ${allProjectsOf(model).size} 个项目）"
}

public func aiTargetOf(model: AppModel): AgentTarget {
    if (rootSectionIs(model.root.value, RootSection.Project) && !model.selectedProject.value.isEmpty()) {
        return AgentTarget.Project(model.selectedProject.value)
    }
    return AgentTarget.Group
}

/// 打开某个 AI 面板。
public func openAIPane(model: AppModel, pane: Int64): Unit {
    model.aiPane.value = pane
    if (pane == 1) {
        model.aiDraft.value = ""
    }
}

public func closeAIPane(model: AppModel): Unit {
    model.aiPane.value = 0
}

public func aiChatPane(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    VStack {
        HStack {
            Label("AI 助手").fontSize(fsTitle()).fontWeight(FontWeight.semiBold)
            Label(aiScopeLabel(model)).fontSize(fsLabel()).muted()
            Spacer()
            if (!model.aiExecuted.value.isEmpty()) {
                Label("刚才：${joinList(model.aiExecuted.value.toArray())}").fontSize(fsMicro()).muted().maxLines(1)
            }
            // 停止只在**真的在跑**时出现。一直挂着一个能按的「停止」，
            // 用户会按了发现没反应 —— 那是「按钮不反映状态」这一族缺陷。
            if (model.aiRunning.value) {
                Button("停止", {=> stopAI(model)}, role: ButtonRole.Danger).fontSize(fsBody())
            }
            if (!model.aiExecuted.value.isEmpty()) {
                Button("清空", {=>
                    model.aiTranscript.value = None
                    model.aiExecuted.value = ArrayList<String>()
                    model.aiNote.value = ""
                }).fontSize(fsBody())
            }
            Button("关闭", {=> closeAIWithCheck(model)}).fontSize(fsBody())
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
        Divider()
        // ⚠ 不要用 `Flexible { … }` 包住内容区。
        // 实测：那样内容区会被顶到**输入框上面** —— VStack 里的顺序变成
        // 「标题 / 输入框 / 内容」。要撑满剩余空间用控件自己的 `.flex()`。
        aiTranscriptView(model, dark)
        Divider()
        aiComposer(model, app, dark)
    }.spacing(0.vp)
}

/// 关面板前先看一眼有没有在跑。
///
/// 正在跑时**不关**：关了之后那一轮还会往回写状态，
/// 而 `aiPane` 已经回到 0 —— 用户看着仪表盘，对话内容在背后自己变。
/// 提示语给的是**下一步**（先按停止），不是一句「无法关闭」。
public func closeAIWithCheck(model: AppModel): Unit {
    if (model.aiRunning.value) {
        model.routeNotice.value = "AI 助手还在跑 —— 先按「停止」再关闭。"
        return
    }
    closeAIPane(model)
}

/// 消息角色 → (名字, 色)。**按角色给不同色** ——
/// 对话流里「谁在说」必须一眼可分，否则工具往返和助手的回答会糊成一片。
private func aiRoleTone(role: ChatRole): (String, Int64) {
    return (match (role) {
        case ChatRole.System => ("系统", C_SLATE)
        case ChatRole.User => ("你", C_AI)
        case ChatRole.Assistant => ("助手", C_SHALLOW)
        case ChatRole.Tool => ("工具", C_ORANGE)
    })
}

private func aiMessageRow(m: ChatMessage, dark: Bool): Unit {
    let (name, tint) = aiRoleTone(m.role)
    Panel {
        VStack {
            HStack {
                // ⚠ 文字走 `dsTextColor`：工具行的橙原色压在浅底上只有 2.8:1。
                Label(name).fontSize(fsMicro()).foregroundColor(dsColor(dsTextColor(tint, dark)))
                if (m.isError) {
                    Label("失败").fontSize(fsMicro()).foregroundColor(dsColor(C_RED))
                }
                Spacer()
            }.spacing(4.vp).hug()
            if (chatRoleIs(m.role, ChatRole.Assistant) || chatRoleIs(m.role, ChatRole.User)) {
                // 助手与用户的正文按 Markdown 渲染；工具结果不渲染
                // （那是引擎原文，渲染它等于替引擎重新排版事实）。
                //
                // ⚠ 走 `mdView` 而不是 `mdBlocks`：`mdBlocks` 只返回块数组、
                // **不发控件**，直接当语句写在这里会被编译器标成
                // `unused expression`，正文一个字都不画。
                mdView(aiMessageText(m), dark)
            } else {
                Label(aiMessageText(m)).fontSize(fsBody()).wrap()
            }
        }.spacing(3.0.vp).hug()
    }.style(dsSurface(DsLevel.Nested, dark)).contentPadding(8.0.vp).hug()
}

/// 消息正文。
///
/// ⚠ 工具结果**截断显示**：那整段是喂给模型的，不是给人读的。
/// 几百 KB 的里程碑 JSON 铺在界面上只会让人找不到助手到底答了什么。
public func aiMessageText(m: ChatMessage): String {
    var s = m.text
    if (chatRoleIs(m.role, ChatRole.Assistant) && m.toolCalls.isSome()) {
        let names = ArrayList<String>()
        for (tc in m.toolCalls.getOrThrow()) {
            names.add(toolShortLabel(tc.name))
        }
        if (names.size > 0) {
            if (!s.isEmpty()) { s += "\n\n" }
            s += "→ 调工具：${joinList(names.toArray())}"
        }
    }
    if (chatRoleIs(m.role, ChatRole.Tool) && s.size > 800) {
        s = textPrefix(s, 800) + "\n…（完整结果已交给模型）"
    }
    return s
}

private func aiTranscriptView(model: AppModel, dark: Bool): Unit {
    match (model.aiTranscript.value) {
        case None =>
            // 空态用 HStack + Spacer 做水平居中：VStack 的
            // `crossAxisAlignment(Center)` 不会把「按内容宽度」的 Label 撑开居中，
            // 实际渲染出来那段文字是**贴左边**的（快照实测）。
            Panel {
                HStack {
                    Spacer()
                    VStack {
                        Label("还没聊过").fontSize(fsSection()).muted()
                        Label("问项目群现状、问某个项目的分支、让它跑一次浅更新。\n" +
                            "它只根据引擎返回的事实回答 —— 工具没给的数据，它会说「不知道」。")
                            .fontSize(fsBody()).muted().wrap().width(520.0.vp)
                    }.spacing(6.vp)
                    Spacer()
                }.spacing(0.vp)
            }.style(dsSurface(DsLevel.Card, dark)).contentPadding(24.0.vp).flex()
        case Some(list) =>
            // scrollState 接模型上的 `aiScroll`（R2-06）：新消息写入时把它
            // 顶到底，不再依赖用户记得往下滚。
            ScrollView(key: "dd-ai-scroll") {
                VStack {
                    for (m in list) {
                        aiMessageRow(m, dark)
                    }
                    if (!model.aiNote.value.isEmpty()) {
                        Label(model.aiNote.value).fontSize(fsLabel()).muted().wrap()
                    }
                    if (!model.aiStatus.value.isEmpty()) {
                        Label(model.aiStatus.value).fontSize(fsBody()).muted()
                    }
                }.spacing(6.0.vp)
            }.scrollState(model.aiScroll).flex()
    }
}

/// 把对话流顶到底（R2-06）。取一个远超任何内容高度的值即可：
/// ScrollView 布局期会把偏移钳到「内容高 - 视口高」，正是贴底；
/// 内容不满一屏时钳到 0，也没有副作用。用户随后上滚不受影响。
public func scrollAITranscriptToBottom(model: AppModel): Unit {
    model.aiScroll.value = Float32(1.0e9)
}

/// 能不能发。**空问题不发、跑着不发** —— 与引擎动作共用一个闸门。
public func canSendAI(model: AppModel): Bool {
    return !model.actionBusy.value && !model.aiDraft.value.trimAscii().isEmpty()
}

/// 输入区。
///
/// ⚠ `TextArea` **必须定高**，而且整行用 `.hug()`。
/// 只写 `.flex()`（撑满剩余空间）时，快照实测：输入框**纵向也撑满了整个主区**，
/// 消息流被顶到窗口外面 —— 画面上只剩一个巨大的空输入框。
/// 「看起来顺序不对」的现象，根因是这块控件在抢高度，不是布局顺序。
/// 三行高足够写一个具体问题；再高就该拖窗口了。
private func aiComposer(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    HStack {
        TextArea(model.aiDraft, key: "dd-ai-draft").placeholder("问点什么…").wrap()
            .height(72.0.vp).flex()
        Button("发送", {=> sendAI(app, model)}, role: ButtonRole.Primary)
            .fontSize(fsBody()).enabled(canSendAI(model))
    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.End).hug()
}

/// 发一轮。**UI 线程只做状态切换**，网络与引擎调用全在后台线程。
///
/// ⚠ 这条纪律来自 `appstate.cj` 文件头：UI 线程上跑一次 AI 请求
/// （可能几十秒）会同时冻结输入与绘制。`loadAIConfig` 也算 ——
/// 它要读钥匙串（`secret-tool`，预算 10 秒），同样不能在 UI 线程等。
public func sendAI(app: DesktopApp, model: AppModel): Unit {
    if (!beginAction(model, "AI 助手")) {
        return
    }
    let question = model.aiDraft.value.trimAscii()
    model.aiDraft.value = ""
    let bin = model.enginePath
    let target = aiTargetOf(model)
    let history = (match (model.aiTranscript.value) {
        case Some(l) => l
        case None => ArrayList<ChatMessage>()
    })
    // 提问先推进流里：按下发送就该**立刻**看到自己那条，
    // 而不是等网络回来才出现。
    let shown = ArrayList<ChatMessage>()
    for (m in history) { shown.add(m) }
    shown.add(ChatMessage.user(question))
    model.aiTranscript.value = Some(shown)
    scrollAITranscriptToBottom(model)
    model.aiStatus.value = "正在思考…"
    model.aiNote.value = ""
    model.aiRunning.value = true
    aiStopRequested = false
    aiRoundSeq += 1
    let seq = aiRoundSeq

    spawn {
        // 配置读取在后台做（R4-06）：`loadAIConfig` → `loadAIKey`
        // 里有 10 秒预算的 secret-tool 子进程，放 UI 线程就是
        // 「按下发送界面冻住，钥匙串慢的时候冻 10 秒」。
        let cfg = loadAIConfig()
        let r = runAgent(cfg, bin, target, question, history)
        // ⚠ 回写前先对代号。没有这道守卫：用户「停止 → 立刻发新问题」之后，
        // 上一轮迟到的回写会**覆盖掉新对话** —— 用户的下一条提问凭空消失。
        // 「状态被迟到回写覆盖」是这一族里最招人烦的一种。
        app.post {
            if (!aiRoundIsCurrent(seq)) {
                return
            }
            endAction(model, "AI 助手", r.outcome.problem.isEmpty())
            model.aiRunning.value = false
            model.aiStatus.value = ""
            model.aiExecuted.value = ArrayList<String>(r.outcome.executed.toArray())
            var note = agentNoteOf(r.outcome)
            if (!cfg.loadProblem.isEmpty()) {
                // 配置文件坏了必须说出口：否则界面看着一切正常，
                // 实际 provider/模型已经悄悄回落成默认值（R1-04）。
                note = if (note.isEmpty()) { cfg.loadProblem } else { "${cfg.loadProblem}；${note}" }
            }
            model.aiNote.value = note
            if (r.outcome.problem.isEmpty() || agentOutcomeWasStopped(r.outcome)) {
                model.aiTranscript.value = Some(r.transcript)
                scrollAITranscriptToBottom(model)
            }
        }
    }
}

/// 用户按停止。**UI 线程立刻给反馈**，不等后台那条线程。
public func stopAI(model: AppModel): Unit {
    aiStopRequested = true
    // ⚠ 同时**废止这一轮的代号**（R4-04）。被放弃轮次的任何迟到回写
    // —— 包括「以 Stopped 收尾」的那次 app.post —— 都会被
    // `aiRoundIsCurrent` 拒掉。没有这句的话：用户停止后立刻发起深更新 /
    // git 写，旧一轮的 app.post 仍能通过守卫，再执行一次 endAction，
    // 把**正在跑的那个写动作**的 actionBusy 闸门提前放开 ——
    // 两个引擎写进程抢锁，恰是闸门注释里说要防的局面。
    // 代价如实记：停止那一轮已写出的内容不再补显（状态行里那句话
    // 「会跑完就被丢弃」说的就是它）。
    aiRoundSeq += 1
    model.aiStatus.value = "已停止 — 正在进行的那次请求会跑完就被丢弃"
    model.aiRunning.value = false
    // 闸门在这里**先放开**：用户可能立刻想发新问题或别的写动作，
    // 而闸门要等后台线程回写才关 —— 那会让「停止」之后的下一个动作
    // 被静默拒绝。旧轮的收尾不会捣乱：它连代号守卫都过不去。
    endAction(model, "AI 助手", false)
}

/// 收尾说明。**正常收尾就是空** —— 每次都显示一句「已完成」是噪音。
public func agentNoteOf(o: AgentOutcome): String {
    if (o.problem.isEmpty()) {
        return ""
    }
    return o.problem
}

/// 这一轮是不是被用户停掉的。仓颉枚举没有 `==`，只能显式判。
public func agentOutcomeWasStopped(o: AgentOutcome): Bool {
    return (match (o.kind) {
        case AgentOutcomeKind.Stopped => true
        case _ => false
    })
}

// ---------------------------------------------------------------------------
// 设置（C7）
// ---------------------------------------------------------------------------

public func aiSettingsPane(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    VStack {
        HStack {
            Label("AI 设置").fontSize(fsTitle()).fontWeight(FontWeight.semiBold)
            Spacer()
            Button("关闭", {=> closeAIPane(model)}).fontSize(fsBody())
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
        Divider()
        Flexible { aiSettingsBody(model, app, dark) }
    }.spacing(0.vp)
}

private func aiSettingsBody(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    // 外观下拉的写入接到「保存 + 披露」上（与范围下拉同款 mountEffect 模式）。
    observeAppearanceChoice(model)
    // 定时更新下拉同款：写入接「保存 + 披露」（C5 定时更新 / C10 定时简报）。
    observeScheduleChoice(model)
    let cat = catalogProblem()
    let cov = providerPickerCoverage()
    ScrollView(key: "dd-ai-set-scroll") {
        VStack {
            if (!cat.isEmpty()) {
                aiProblemCard("模型目录不可用", cat, dark)
            }
            aiField("Provider", {=> aiProviderRow(model, dark)}, dark,
                "目录里共 ${cov.total} 家，其中 ${cov.withEndpoint} 家有可用端点。" +
                (if (cov.cut) { cov.note } else { "已全部列出。" }))
            aiField("模型", {=> aiModelRow(model, dark)}, dark,
                "只列支持原生工具调用的模型 —— 不支持的模型在第一轮提问就会撞墙。" +
                "也可以在右边手填模型 id。")
            aiField("API Key", {=> aiKeyRow(model, dark)}, dark,
                "优先存系统钥匙串（libsecret）。没有钥匙串时退到 600 权限的文件 —— " +
                "那种情况下面会写明，不静默降级。")
            aiField("Base URL（留空 = 用目录里的端点）", {=> aiBaseURLRow(model, dark)}, dark,
                "只接受 https，或 127.0.0.1 / localhost 的 http（本地模型）。")
            aiKeyStoreCard(dark)
            aiField("开机自启", {=> aiAutostartRow(model, app, dark)}, dark,
                "写 XDG 的 ~/.config/autostart/deepdolphin.desktop。开关读的是**系统真值**，不是上次点了什么。")
            aiField("外观", {=> aiAppearanceRow(model)}, dark,
                "跟随系统 / 亮 / 暗，写入 XDG 的 settings.conf。主题在启动时定型，切换要重启客户端生效。")
            aiField("定时更新", {=> aiScheduleRow(model)}, dark,
                "按所选周期对全部项目做一次浅更新并发系统通知：配置了 AI 会附项目群简报，未配置只报完成数。" +
                "开启（或改档）后 10 分钟先跑一轮；正在读取或有动作在跑时跳过本轮、顺延到下个周期。" +
                "档位与外观同存 settings.conf（schedule= 小时数）。")
            aiTestCard(model, app, dark)
        }.spacing(10.0.vp)
    }.flex()
}

// ---------------------------------------------------------------------------
// 外观（R2-03）—— 三档实现曾整层零 UI 消费：能存、能读，却没有一处能换
// ---------------------------------------------------------------------------

/// 把外观下拉的写入接到 `applyAppearanceChoice`（记档 + 落盘 + 结果披露）。
/// `mountEffect` 按 key 去重，重建时不会重复注册观察；
/// 接线本体拆在 `installAppearanceChoiceObserver`（appstate.cj），
/// 判据不开窗就能装上它。
private func observeAppearanceChoice(model: AppModel): Unit {
    mountEffect("dd-observe-appearance", {=> installAppearanceChoiceObserver(model)})
}

/// 定时更新下拉的接线（与外观同款 mountEffect 模式；本体在
/// `installScheduleChoiceObserver`，appstate.cj）。
private func observeScheduleChoice(model: AppModel): Unit {
    mountEffect("dd-observe-schedule", {=> installScheduleChoiceObserver(model)})
}

/// 定时更新那一行的控件。六档下拉（关/1/3/6/12/24h）+ 保存结果披露
/// —— 成功写明改档后的行为，写不进去给原因（与外观行同一条结构）。
private func aiScheduleRow(model: AppModel): Widget {
    return VStack {
        HStack {
            Dropdown(scheduleChoices(), model.scheduleIndex, key: "dd-schedule").width(200.0.vp)
            Spacer()
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
        if (!model.scheduleNote.value.isEmpty()) {
            if (model.scheduleNoteOk.value) {
                Label(model.scheduleNote.value).fontSize(fsLabel()).muted().wrap()
            } else {
                Label(model.scheduleNote.value).fontSize(fsLabel()).foregroundColor(dsColor(C_RED)).wrap()
            }
        }
    }.spacing(4.vp).hug()
}

/// 外观那一行的控件。三档下拉 + 两条披露：
/// `appearanceUnknown`（启动时没探到系统外观，说了「为什么这次是亮色」）
/// 与保存结果（成功也写明「重启后生效」，写不进去则给原因）。
private func aiAppearanceRow(model: AppModel): Widget {
    return VStack {
        HStack {
            Dropdown(appearanceChoices(), model.appearanceIndex, key: "dd-appearance").width(200.0.vp)
            if (model.appearanceUnknown.value) {
                Label("本次启动没探到系统外观，先用了亮色 —— 在这里显式选一档，以后就不再猜。")
                    .fontSize(fsLabel()).muted().wrap()
            }
            Spacer()
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
        if (!model.appearanceNote.value.isEmpty()) {
            if (model.appearanceNoteOk.value) {
                Label(model.appearanceNote.value).fontSize(fsLabel()).muted().wrap()
            } else {
                Label(model.appearanceNote.value).fontSize(fsLabel()).foregroundColor(dsColor(C_RED)).wrap()
            }
        }
    }.spacing(4.vp).hug()
}

/// 一个带标题 + 控件 + 说明的字段块。
///
/// ⚠ `body` 收**闭包**而不是 `Widget`。
/// 收 Widget 时（`aiField("Provider", aiProviderRow(model, dark), …)`），
/// `aiProviderRow` 会在**实参求值**的那一刻就把控件发射到**外层**的 VStack ——
/// 快照实测的结果是每个字段的控件都跑到了自己标题的**上方**，
/// 标题与说明留在一个空 Panel 里。
/// CUI 的 DSL 是「调用即发射」，所以要让它落在 Panel 内部就必须延迟到闭包里。
private func aiField(label: String, body: () -> Unit, dark: Bool, note: String): Unit {
    Panel {
        VStack {
            Label(label).fontSize(fsBody()).fontWeight(FontWeight.semiBold)
            body()
            Label(note).fontSize(fsMicro()).muted().wrap()
        }.spacing(4.0.vp).hug()
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(10.0.vp).hug()
}

private func aiProblemCard(title: String, text: String, dark: Bool): Unit {
    Panel {
        VStack {
            Label(title).fontSize(fsBody()).fontWeight(FontWeight.semiBold).foregroundColor(dsColor(C_RED))
            Label(text).fontSize(fsLabel()).wrap()
        }.spacing(4.0.vp).hug()
    }.style(dsSurface(DsLevel.Nested, dark)).contentPadding(10.0.vp).hug()
}

/// 当前选中的 provider id。**-1 = 一个都没选**（目录读不到时的真实状态）。
public func selectedProviderID(model: AppModel): String {
    let list = popularProviders()
    let i = model.aiProviderIndex.value
    if (i < 0 || i >= list.size) {
        return ""
    }
    return list[i].id
}

private func aiProviderRow(model: AppModel, dark: Bool): Widget {
    let list = popularProviders()
    if (list.isEmpty()) {
        return Label("目录读不到，provider 选不了").fontSize(fsBody()).muted()
    }
    let labels = ArrayList<String>()
    for (p in list) {
        labels.add("${p.name}（${p.id} · ${p.models.size} 模型）")
    }
    // ⚠ 不要包 `Flexible`。它在 `VStack` 里会抢走布局 —— 控件被提到 Panel 之外、
    // 渲染到**标题上方**（快照实测：五个字段全中这个症状）。
    // `Dropdown` 自己 `.flex()` 就够。
    return Dropdown(labels.toArray(), model.aiProviderIndex, key: "dd-ai-provider").flex()
}

private func aiModelRow(model: AppModel, dark: Bool): Widget {
    let pid = selectedProviderID(model)
    let models = providerToolModels(pid)
    let labels = ArrayList<String>()
    for (m in models) {
        labels.add("${m.name}（${m.id}）")
    }
    let picker: Widget = (if (models.isEmpty()) {
        Label("先选一个 provider").fontSize(fsBody()).muted()
    } else {
        Dropdown(labels.toArray(), model.aiModelIndex, key: "dd-ai-model").flex()
    })
    return HStack {
        picker
        TextField(model.aiModelManual, key: "dd-ai-model-manual").placeholder("或手填模型 id").width(200.0.vp)
    }.spacing(6.vp).hug()
}

/// 「已保存的 key 在不在」掩码的后台刷新。启动（boot）与保存回包各调一次，
/// 真值读取在后台线程 —— `loadAIKey` 里有 10 秒预算的 secret-tool 子进程，
/// 在 UI 线程等它就是冻结界面（R4-06）。
public func refreshKeyPresence(app: DesktopApp, model: AppModel): Unit {
    spawn {
        let present = !loadAIKey().isEmpty()
        app.post {
            model.aiKeySavedPresent.value = present
        }
    }
}

private func aiKeyRow(model: AppModel, dark: Bool): Widget {
    // ⚠ 只读掩码状态，**不在这里读真值**（R4-06）：本函数在设置页的
    // 构建闭包里，每帧都跑；`loadAIKey` 要碰 secret-tool（预算 10 秒），
    // 放这儿就是「钥匙串一卡，每敲一个字符冻一次界面」。
    // 掩码由 `refreshKeyPresence` 在启动与保存回包时各刷新一次。
    let saved = model.aiKeySavedPresent.value
    return HStack {
        TextField(model.aiKeyDraft, key: "dd-ai-key").placeholder("sk-…").width(300.0.vp)
        Label(if (saved) { "已配置（不显示原文）" } else { "未配置" }).fontSize(fsLabel()).muted()
        Spacer()
    }.spacing(8.vp).hug()
}

private func aiBaseURLRow(model: AppModel, dark: Bool): Widget {
    return HStack {
        TextField(model.aiBaseURLDraft, key: "dd-ai-baseurl")
            .placeholder("https://… 或 http://localhost:11434/v1").width(360.0.vp)
        Button("清空", {=> model.aiBaseURLDraft.value = ""}).fontSize(fsLabel())
        Spacer()
    }.spacing(8.vp).hug()
}

private func aiKeyStoreCard(dark: Bool): Unit {
    Panel {
        VStack {
            Label("密钥现在存在哪").fontSize(fsBody()).fontWeight(FontWeight.semiBold)
            Label(aiKeyStoreDescription()).fontSize(fsLabel()).wrap()
            let degraded = (match (lastKeyStoreDegraded) {
                case Some(true) => true
                case _ => false
            })
            if (degraded) {
                Label("上次保存没能用上系统钥匙串 —— 「已配置」不代表下次启动它还在。")
                    .fontSize(fsLabel()).foregroundColor(dsColor(dsTextColor(C_ORANGE, dark))).wrap()
            }
        }.spacing(4.0.vp).hug()
    }.style(dsSurface(DsLevel.Nested, dark)).contentPadding(10.0.vp).hug()
}

private func aiTestCard(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    Panel {
        HStack {
            VStack {
                Label("保存并测试连接").fontSize(fsBody()).fontWeight(FontWeight.semiBold)
                Label(model.aiTestResult.value).fontSize(fsLabel()).wrap()
            }.spacing(3.0.vp).hug()
            Spacer()
            Button("保存并测试", {=> saveAndTestAI(app, model)}, role: ButtonRole.Primary)
                .fontSize(fsBody()).enabled(!model.actionBusy.value)
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(10.0.vp).hug()
}

/// 从界面草稿组装一份配置。**纯函数** —— 判据直接喂草稿、断言组装结果。
public func configFromDraft(model: AppModel): AIConfig {
    let pid = selectedProviderID(model)
    let models = providerToolModels(pid)
    var mid = model.aiModelManual.value.trimAscii()
    if (mid.isEmpty()) {
        let i = model.aiModelIndex.value
        if (i >= 0 && i < models.size) {
            mid = models[Int64(models.size) - 1 - i].id
        }
    }
    return AIConfig(
        providerID: pid,
        model: mid,
        baseURL: model.aiBaseURLDraft.value.trimAscii(),
        apiKey: model.aiKeyDraft.value
    )
}

/// 保存 + 测试。**先保存再测** —— 测的是「刚填的这份」，
/// 不是磁盘上上一份。
public func saveAndTestAI(app: DesktopApp, model: AppModel): Unit {
    if (!beginAction(model, "测试 AI 连接")) {
        return
    }
    let cfg = configFromDraft(model)
    model.aiTestResult.value = "保存中…"
    spawn {
        // ⚠ 后台线程里**先算成不可变的一个字符串**，再进 `app.post` 闭包 ——
        // 仓颉的闭包不能捕获 `var`（可变变量），
        // 而「先 var 后 if 改」是最自然的写法，一写就编译不过。
        // 更重要的是：结论必须由**执行结果**算出来，
        // 不能在 UI 线程上靠猜「保存大概成功了」。
        let saveProblem = saveAIConfig(cfg)
        // 保存回包前在**后台**把「key 在不在」的掩码刷新一遍
        // （读真值要碰 secret-tool，预算 10 秒，不能进 app.post 再读 —— R4-06）。
        let keyPresent = !loadAIKey().isEmpty()
        let verdict: String = (if (!saveProblem.isEmpty()) {
            saveProblem
        } else {
            let msgs = ArrayList<ChatMessage>()
            msgs.add(ChatMessage.user("ping"))
            let r = generateText(cfg, "你是连通性测试器，只回复：OK", msgs, ArrayList<ToolDefinition>(),
                maxTokens: 16, timeoutMs: 60000)
            if (!r.ok()) {
                r.problem
            } else if (r.result.text.trimAscii().isEmpty()) {
                "连上了，但模型什么都没回（可能被内容过滤拦了）"
            } else {
                "✓ 连上了，模型回：${textPrefix(r.result.text.trimAscii(), 60)}"
            }
        })
        let ok = saveProblem.isEmpty() && !verdict.startsWith("✗")
        app.post {
            model.aiKeySavedPresent.value = keyPresent
            endAction(model, "测试 AI 连接", ok)
            model.aiTestResult.value = verdict
        }
    }
}

// ---------------------------------------------------------------------------
// C5：AI 整合更新
// ---------------------------------------------------------------------------

/// C5 的结果面板。macOS 端是 `.sheet`，这里是主区里的一个覆盖视图。
///
/// ⚠ 事实陈述**不许模型重编**：`onRegenerate` 在本端**不提供**。
/// 面板里的每一句都来自「模型读引擎事实后写的摘要」，
/// 重新生成会得到一个措辞不同但同样基于同一份事实的版本 ——
/// 对用户没有价值，却让「这句话是推出来的还是编出来的」变得不可判定。
public func aiResultPane(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    VStack {
        HStack {
            Label(model.aiSheetTitle.value).fontSize(fsSection()).fontWeight(FontWeight.semiBold)
            Spacer()
            if (model.aiSheetBusy.value) {
                Label("生成中…").fontSize(fsLabel()).muted()
            }
            Button("关闭", {=>
                model.aiPane.value = 0
                model.aiSheetTitle.value = ""
                model.aiSheetBody.value = ""
                model.aiSheetError.value = ""
            }).fontSize(fsBody())
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
        Divider()
        if (!model.aiSheetError.value.isEmpty()) {
            Label(model.aiSheetError.value).fontSize(fsBody())
                .foregroundColor(dsColor(C_RED)).wrap().padding(10.0.vp)
        }
        Flexible {
            ScrollView(key: "dd-ai-sheet-scroll") {
                // ⚠ 走 Markdown 渲染，不是一整块 Label。
                // 整块 Label 的话 `## 标题`、`- 列表`、反引号全部原样露在屏幕上 ——
                // 快照实测过，那是「模型回了东西但看起来像日志」的样子。
                if (model.aiSheetBody.value.isEmpty()) {
                    Label("（还没有内容）").fontSize(fsBody()).muted()
                } else {
                    mdView(model.aiSheetBody.value, dark)
                }
            }.flex()
        }
        Divider()
        Label("内容由模型根据引擎事实生成，事实本身以面板与项目详情页为准。")
            .fontSize(fsMicro()).muted().padding(6.0.vp)
    }.spacing(0.vp)
}

/// 跑一次「让模型写一段说明」并开面板。
///
/// ⚠ **不传工具**。这三个入口（项目简报 / 群组简报 / 更新后摘要）要的是
/// 「基于已有事实的叙述」，不是「让模型自己去查再改」。
/// 给了工具就可能出现写操作（跑深更新、提交代码）——
/// 而用户点的是「给我讲讲现状」，不是「你去改」。
public func runAIBrief(app: DesktopApp, model: AppModel, title: String, question: String, target: AgentTarget): Unit {
    if (!beginAction(model, title)) {
        return
    }
    let bin = model.enginePath
    model.aiSheetTitle.value = title
    model.aiSheetBody.value = ""
    model.aiSheetError.value = ""
    model.aiSheetBusy.value = true
    model.aiPane.value = 3
    spawn {
        // 配置读取在后台做（R4-06）：loadAIConfig → loadAIKey 里有
        // 10 秒预算的 secret-tool 子进程，不能在 UI 线程等它。
        let cfg = loadAIConfig()
        let ctxPayload = opContext(bin, target.projectName(), 4000)
        var system = "你是 deepDolphin 的项目进度助手。下面是引擎给出的确定性事实，请用中文写一段简明说明。"
        var body = ctxPayload.problem
        if (ctxPayload.ok()) {
            system = system + "\n\n以下是引擎给出的确定性事实（唯一可信来源）：\n\n" +
                Json.strAt(ctxPayload.value(), "context", "")
        } else {
            // 读不到上下文时**说清楚**再让模型写 —— 不能让它凭项目名编一段
            system = system + "\n\n⚠ 这次没能读到引擎上下文（" + ctxPayload.problem +
                "）。你**必须**在回答开头说明这一点，不要凭空描述项目现状。"
        }
        if (!cfg.loadProblem.isEmpty()) {
            // 同一条纪律用在配置上：provider/模型回落了要说出来，不静默（R1-04）。
            system = system + "\n\n⚠ 客户端没能完整读取 AI 配置（" + cfg.loadProblem +
                "）。你**必须**在回答开头说明本次使用的 provider/模型可能不是用户配置的那一份。"
        }
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.user(question))
        let r = generateText(cfg, system, msgs, ArrayList<ToolDefinition>(), maxTokens: 1200, timeoutMs: 120000)
        let verdict: String = (if (!r.ok()) { r.problem } else if (r.result.text.trimAscii().isEmpty()) {
            "模型没有返回内容（可能被内容过滤拦了，或 max_tokens 太小）"
        } else { r.result.text })
        let ok = r.ok() && !r.result.text.trimAscii().isEmpty()
        app.post {
            endAction(model, title, ok)
            model.aiSheetBusy.value = false
            if (ok) {
                model.aiSheetBody.value = verdict
            } else {
                model.aiSheetError.value = verdict
            }
        }
    }
}

/// 单项目说明。项目卡与详情页都调它。
public func runProjectBrief(app: DesktopApp, model: AppModel, project: String): Unit {
    runAIBrief(app, model, "项目说明 · ${project}",
        "请写一段这个项目的现状说明：活跃度、分支与待合入、未提交改动、最近在做什么。" +
        "写清楚哪些数据读不出来。", AgentTarget.Project(project))
}

/// 整个项目群说明。
public func runGroupBrief(app: DesktopApp, model: AppModel): Unit {
    runAIBrief(app, model, "项目群说明",
        "请写一段这个项目群的现状说明：整体活跃度、哪些项目需要关注（停滞、有未提交改动、待合入），" +
        "以及建议先处理哪几个、为什么。", AgentTarget.Group)
}

// ---------------------------------------------------------------------------
// C10：设置页里的系统集成开关
// ---------------------------------------------------------------------------

/// 开机自启那一行。**状态读的是系统真值**（autostart 文件在不在），
/// 不是「上次点了什么」—— 桌面环境可能把那个文件删了。
private func aiAutostartRow(model: AppModel, app: DesktopApp, dark: Bool): Widget {
    let on = autostartEnabled()
    return HStack {
        Label(if (on) { "已开启" } else { "已关闭" }).fontSize(fsBody())
        Button(if (on) { "关闭" } else { "开启" }, {=>
            // Exec= 写**客户端真实入口**（scripts/run.sh 绝对路径，它自己摆好
            // 仓颉运行时库路径）。引擎不带 --engine 钉死 —— run.sh 会优先指向
            // 仓内构建，装好的机器走 locateEngine 的 PATH 兜底，与手动启动
            // 是同一条链。算不出入口就**如实报错**，不写 Exec= 残缺的条目：
            // 那种条目会话把参数当程序名执行，界面却显示「已开启」（R3-02）。
            // 提示语走 autostartEntryUnavailableHint（判据钉住）：
            // 从 scripts/run.sh 启动即可算出入口 —— 文档主入口不再满足不了守卫。
            let entry = autostartClientEntry()
            let p = (if (entry.isEmpty()) {
                autostartEntryUnavailableHint()
            } else {
                setAutostart(entry, "", !on)
            })
            if (!p.isEmpty()) {
                model.report(p, false)
            }
        }).fontSize(fsLabel())
        if (!on && !hasNotifySend()) {
            // 两件事都不通时**一起说**，不要让用户以为开了自启就有通知
            Label("（本机没有 notify-send，自启后也没有系统通知）").fontSize(fsMicro()).muted().wrap()
        }
        Spacer()
    }.spacing(8.vp).hug()
}
