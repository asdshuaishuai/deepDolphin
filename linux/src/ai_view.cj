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
            Label("AI 助手").fontSize(15.0).fontWeight(FontWeight.semiBold)
            Label(aiScopeLabel(model)).fontSize(11.0).muted()
            Spacer()
            if (!model.aiExecuted.value.isEmpty()) {
                Label("刚才：${joinList(model.aiExecuted.value.toArray())}").fontSize(10.0).muted().maxLines(1)
            }
            // 停止只在**真的在跑**时出现。一直挂着一个能按的「停止」，
            // 用户会按了发现没反应 —— 那是「按钮不反映状态」这一族缺陷。
            if (model.aiRunning.value) {
                Button("停止", {=> stopAI(model)}, role: ButtonRole.Danger).fontSize(12.0)
            }
            if (!model.aiExecuted.value.isEmpty()) {
                Button("清空", {=>
                    model.aiTranscript.value = None
                    model.aiExecuted.value = ArrayList<String>()
                    model.aiNote.value = ""
                }).fontSize(12.0)
            }
            Button("关闭", {=> closeAIWithCheck(model)}).fontSize(12.0)
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
                Label(name).fontSize(10.0).foregroundColor(dsColor(tint))
                if (m.isError) {
                    Label("失败").fontSize(10.0).foregroundColor(dsColor(C_RED))
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
                Label(aiMessageText(m)).fontSize(12.0).wrap()
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
                        Label("还没聊过").fontSize(15.0).muted()
                        Label("问项目群现状、问某个项目的分支、让它跑一次浅更新。\n" +
                            "它只根据引擎返回的事实回答 —— 工具没给的数据，它会说「不知道」。")
                            .fontSize(12.0).muted().wrap().width(520.0.vp)
                    }.spacing(6.vp)
                    Spacer()
                }.spacing(0.vp)
            }.style(dsSurface(DsLevel.Card, dark)).contentPadding(24.0.vp).flex()
        case Some(list) =>
            ScrollView(key: "dd-ai-scroll") {
                VStack {
                    for (m in list) {
                        aiMessageRow(m, dark)
                    }
                    if (!model.aiNote.value.isEmpty()) {
                        Label(model.aiNote.value).fontSize(11.0).muted().wrap()
                    }
                    if (!model.aiStatus.value.isEmpty()) {
                        Label(model.aiStatus.value).fontSize(12.0).muted()
                    }
                }.spacing(6.0.vp)
            }.flex()
    }
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
            .fontSize(12.0).enabled(canSendAI(model))
    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.End).hug()
}

/// 发一轮。**UI 线程只做状态切换**，网络与引擎调用全在后台线程。
///
/// ⚠ 这条纪律来自 `appstate.cj` 文件头：UI 线程上跑一次 AI 请求
/// （可能几十秒）会同时冻结输入与绘制。
public func sendAI(app: DesktopApp, model: AppModel): Unit {
    if (!beginAction(model, "AI 助手")) {
        return
    }
    let question = model.aiDraft.value.trimAscii()
    model.aiDraft.value = ""
    let cfg = loadAIConfig()
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
    model.aiStatus.value = "正在思考…"
    model.aiNote.value = ""
    model.aiRunning.value = true
    aiStopRequested = false
    aiRoundSeq += 1
    let seq = aiRoundSeq

    spawn {
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
            model.aiNote.value = agentNoteOf(r.outcome)
            if (r.outcome.problem.isEmpty() || agentOutcomeWasStopped(r.outcome)) {
                model.aiTranscript.value = Some(r.transcript)
            }
        }
    }
}

/// 用户按停止。**UI 线程立刻给反馈**，不等后台那条线程。
public func stopAI(model: AppModel): Unit {
    aiStopRequested = true
    model.aiStatus.value = "已停止 — 正在进行的那次请求会跑完就被丢弃"
    model.aiRunning.value = false
    // 闸门在这里**先放开**：用户可能立刻想发新问题，
    // 而闸门要等后台线程回写才关 —— 那会让「停止」之后的下一个动作被静默拒绝。
    // 代价是可能有一轮旧请求还在收尾，`aiRoundIsCurrent` 负责不让它覆盖界面。
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
            Label("AI 设置").fontSize(15.0).fontWeight(FontWeight.semiBold)
            Spacer()
            Button("关闭", {=> closeAIPane(model)}).fontSize(12.0)
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
        Divider()
        Flexible { aiSettingsBody(model, app, dark) }
    }.spacing(0.vp)
}

private func aiSettingsBody(model: AppModel, app: DesktopApp, dark: Bool): Unit {
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
            aiTestCard(model, app, dark)
        }.spacing(10.0.vp)
    }.flex()
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
            Label(label).fontSize(12.0).fontWeight(FontWeight.semiBold)
            body()
            Label(note).fontSize(10.0).muted().wrap()
        }.spacing(4.0.vp).hug()
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(10.0.vp).hug()
}

private func aiProblemCard(title: String, text: String, dark: Bool): Unit {
    Panel {
        VStack {
            Label(title).fontSize(12.0).fontWeight(FontWeight.semiBold).foregroundColor(dsColor(C_RED))
            Label(text).fontSize(11.0).wrap()
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
        return Label("目录读不到，provider 选不了").fontSize(12.0).muted()
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
        Label("先选一个 provider").fontSize(12.0).muted()
    } else {
        Dropdown(labels.toArray(), model.aiModelIndex, key: "dd-ai-model").flex()
    })
    return HStack {
        picker
        TextField(model.aiModelManual, key: "dd-ai-model-manual").placeholder("或手填模型 id").width(200.0.vp)
    }.spacing(6.vp).hug()
}

private func aiKeyRow(model: AppModel, dark: Bool): Widget {
    let saved = loadAIKey()
    return HStack {
        TextField(model.aiKeyDraft, key: "dd-ai-key").placeholder("sk-…").width(300.0.vp)
        Label(if (saved.isEmpty()) { "未配置" } else { "已配置（不显示原文）" }).fontSize(11.0).muted()
        Spacer()
    }.spacing(8.vp).hug()
}

private func aiBaseURLRow(model: AppModel, dark: Bool): Widget {
    return HStack {
        TextField(model.aiBaseURLDraft, key: "dd-ai-baseurl")
            .placeholder("https://… 或 http://localhost:11434/v1").width(360.0.vp)
        Button("清空", {=> model.aiBaseURLDraft.value = ""}).fontSize(11.0)
        Spacer()
    }.spacing(8.vp).hug()
}

private func aiKeyStoreCard(dark: Bool): Unit {
    Panel {
        VStack {
            Label("密钥现在存在哪").fontSize(12.0).fontWeight(FontWeight.semiBold)
            Label(aiKeyStoreDescription()).fontSize(11.0).wrap()
            let degraded = (match (lastKeyStoreDegraded) {
                case Some(true) => true
                case _ => false
            })
            if (degraded) {
                Label("上次保存没能用上系统钥匙串 —— 「已配置」不代表下次启动它还在。")
                    .fontSize(11.0).foregroundColor(dsColor(C_ORANGE)).wrap()
            }
        }.spacing(4.0.vp).hug()
    }.style(dsSurface(DsLevel.Nested, dark)).contentPadding(10.0.vp).hug()
}

private func aiTestCard(model: AppModel, app: DesktopApp, dark: Bool): Unit {
    Panel {
        HStack {
            VStack {
                Label("保存并测试连接").fontSize(12.0).fontWeight(FontWeight.semiBold)
                Label(model.aiTestResult.value).fontSize(11.0).wrap()
            }.spacing(3.0.vp).hug()
            Spacer()
            Button("保存并测试", {=> saveAndTestAI(app, model)}, role: ButtonRole.Primary)
                .fontSize(12.0).enabled(!model.actionBusy.value)
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
            Label(model.aiSheetTitle.value).fontSize(15.0).fontWeight(FontWeight.semiBold)
            Spacer()
            if (model.aiSheetBusy.value) {
                Label("生成中…").fontSize(11.0).muted()
            }
            Button("关闭", {=>
                model.aiPane.value = 0
                model.aiSheetTitle.value = ""
                model.aiSheetBody.value = ""
                model.aiSheetError.value = ""
            }).fontSize(12.0)
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
        Divider()
        if (!model.aiSheetError.value.isEmpty()) {
            Label(model.aiSheetError.value).fontSize(12.0)
                .foregroundColor(dsColor(C_RED)).wrap().padding(10.0.vp)
        }
        Flexible {
            ScrollView(key: "dd-ai-sheet-scroll") {
                // ⚠ 走 Markdown 渲染，不是一整块 Label。
                // 整块 Label 的话 `## 标题`、`- 列表`、反引号全部原样露在屏幕上 ——
                // 快照实测过，那是「模型回了东西但看起来像日志」的样子。
                if (model.aiSheetBody.value.isEmpty()) {
                    Label("（还没有内容）").fontSize(12.0).muted()
                } else {
                    mdView(model.aiSheetBody.value, dark)
                }
            }.flex()
        }
        Divider()
        Label("内容由模型根据引擎事实生成，事实本身以面板与项目详情页为准。")
            .fontSize(10.0).muted().padding(6.0.vp)
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
    let cfg = loadAIConfig()
    let bin = model.enginePath
    model.aiSheetTitle.value = title
    model.aiSheetBody.value = ""
    model.aiSheetError.value = ""
    model.aiSheetBusy.value = true
    model.aiPane.value = 3
    spawn {
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
        Label(if (on) { "已开启" } else { "已关闭" }).fontSize(12.0)
        Button(if (on) { "关闭" } else { "开启" }, {=>
            // Exec= 写的是**引擎**参数，客户端自己的启动路径由启动脚本负责
            let p = setAutostart("", model.enginePath, !on)
            if (!p.isEmpty()) {
                model.report(p, false)
            }
        }).fontSize(11.0)
        if (!on && !hasNotifySend()) {
            // 两件事都不通时**一起说**，不要让用户以为开了自启就有通知
            Label("（本机没有 notify-send，自启后也没有系统通知）").fontSize(10.0).muted().wrap()
        }
        Spacer()
    }.spacing(8.vp).hug()
}
