// deepDolphin Linux 客户端 —— 入口。
//
// 仓颉 + CangjieGUI（CUI）的桌面应用。数据全部来自 **moonGit 引擎子进程**
// 的 `--json` 输出，本端不落任何业务数据，与 macOS 端同一边界。
package deepdolphin_linux

import cui.{AppMetadata, DesktopApp, WindowSpec}
import std.collection.*
import std.env.*
import std.time.*

/// 快照窗口尺寸。默认 1600×1000（约 4 倍像素，48 帧 ≈ 7.7 秒，
/// 足够引擎把两轮读取跑完）；`DD_SNAP_W` / `DD_SNAP_H` 可覆盖。
private func snapshotW(): Int32 {
    return envInt("DD_SNAP_W", 1600)
}

private func snapshotH(): Int32 {
    return envInt("DD_SNAP_H", 1000)
}

private func envInt(name: String, fallback: Int32): Int32 {
    let raw = (getVariable(name) ?? "").trimAscii()
    if (raw.isEmpty()) {
        return fallback
    }
    var v: Int64 = 0
    var seen: Bool = false
    for (ch in raw.runes()) {
        if (ch.toString() < "0" || ch.toString() > "9") {
            return fallback
        }
        v = v * 10 + Int64(ch.toString().toArray()[0] - 0x30u8)
        seen = true
    }
    if (!seen || v <= 0 || v > 8000) {
        return fallback
    }
    return Int32(v)
}

/// 命令行里有 `--snapshot` 吗。
///
/// CUI 的快照模式是**固定渲染几帧就拍照退出**（`SNAPSHOT_SETTLE_FRAMES`）。
/// 而引擎调用走后台线程、要几秒 —— 于是快照拍到的永远是「读取项目群…」。
/// 布局到底对不对、卡片排得开不开，就没法自查。
///
/// 所以**只在快照模式下**把首轮读取改成同步：先阻塞读一次再开窗。
/// 这是给自查用的开关，不影响正常启动路径 —— 正常启动仍然是
/// 「开窗 → 后台读 → 有数据显示」，那才是用户实际体验的时序。
private func wantsSnapshot(): Bool {
    for (a in getCommandLine()) {
        if (a == "--snapshot") {
            return true
        }
    }
    return false
}

main(args: Array<String>): Int64 {
    // 字体必须在建窗之前装好。顺序反了窗口会先用系统字体排完版，
    // 中文全成豆腐块，而 CUI 不会自动重排。
    // ⚠ R4-10：建窗前**只做这一件阻塞的事**。引擎定位要起子进程探活
    // （每个候选一次 `version`，挂住的候选要等满超时），外观探测最多
    // 要起 5 个子进程 —— 它们都不该挡住首帧。引擎定位挪到了首帧之后
    // （见 `app.run` 闭包里的挂载段）；外观必须留在建窗前 —— CUI 的
    // `Theme` 是构造参数、建成之后换不了（vendor `src/core/theme.cj`：
    // "Immutable"，且 `DesktopApp` 没有 setTheme）—— 但它的探测超时
    // 已降到 1.5 秒，最坏也不会再把窗口挡十几秒。
    let fontProblem = installAppFonts()

    // 上次进程的 AI 请求临时文件可能有残留：头文件里有 API Key，
    // SIGKILL / 崩溃时 ai_http 的 finally 清理跑不到（R4-02）。
    // 启动清扫兜底。放后台线程 —— 它是一次子进程的事，不该挡开窗；
    // 失败只能打日志（界面上没有比「更早之前的残留」更要紧的话要说）。
    spawn {
        let sweepProblem = sweepAITempLeftovers()
        if (!sweepProblem.isEmpty()) {
            println("deepdolphin: " + sweepProblem)
        }
    }

    // 外观在**建窗之前**定下来：CUI 的 `Theme` 是 `DesktopApp` 的构造参数，
    // 建成之后换不了（`Theme` 不可变，且 `DesktopApp` 没有 setTheme）。
    // 要跟随系统切换就得重启应用 —— 这条限制在界面上要说出去，
    // 否则用户点「暗色」发现要重启，会以为功能坏了。
    // （R4-10：locateEngine 已挪到首帧后；这里留下的探测子进程超时降到 1.5 秒。）
    let (dark, probeFailed) = resolveAppearance()
    // 引擎位置**不在建窗前找**（R4-10）：定位要起子进程探活，找不着的候选
    // 一个个试过去能把首屏拖住几十秒。模型先建、首帧后挂（见 app.run 闭包）。
    // 夹具模式例外：快照门禁拍的是布局，挂载语义必须与正常路径一致，
    // 而 app.run 之前没有别的阻塞工作，同步挂上代价最小。
    let fixtureDir = getVariable("DD_FIXTURE_DIR") ?? ""
    let model = (if (fixtureDir.isEmpty()) { AppModel() } else { AppModel(locateEngine()) })
    model.dark.value = dark
    model.appearance.value = readSavedAppearance()
    model.appearanceUnknown.value = probeFailed
    // 设置页的外观下拉按下标工作，初值与已保存的档位对齐（R2-03）。
    model.appearanceIndex.value = appearanceIndex(model.appearance.value)
    model.problem.value = fontProblem
    if (!fixtureDir.isEmpty()) {
        loadFromFixtureDir(model, fixtureDir)
        model.booted = true
        // `DD_SNAP_ROOT` / `DD_SNAP_PROJECT` 指定快照拍哪一页。
        // CUI 快照只会启动即拍，用户点不到别的页 —— 没有这个开关，
        // 看板与项目详情就永远只能靠「代码读着像对的」来相信。
        let root = (getVariable("DD_SNAP_ROOT") ?? "").trimAscii()
        // ⚠ 这里原来**直接写 `model.root`**，绕过了 `goView` 这个唯一写入口，
        // 于是侧栏高亮还停在「仪表盘」而主区已经是「看板」——
        // 截图上一眼就是错的，而且它违反本仓自己的纪律：
        // 「导航只有侧栏一个入口，不许在别处直接写 root / selectedProject」。
        // 快照开关不能因为「只是自查」就享有特权。
        let section: Option<RootSection> = (if (root == "board") {
            Some(RootSection.Board)
        } else if (root == "milestones") {
            Some(RootSection.Milestones)
        } else {
            None
        })
        match (section) {
            case Some(r) => goView(model, sectionIndexOf(r))
            case None => ()
        }
        // 自查开关：直接打开某个 AI 面板。
        // 与 DD_SNAP_ROOT 同一族用途 —— CUI 快照只在启动即拍，
        // 没有这个开关，AI 面板就只能靠「代码读着像对的」来相信。
        // 走 `openAIPane` 而不是直接写 `aiPane`，与其他入口同一条路。
        let aiPane = (getVariable("DD_SNAP_AI") ?? "").trimAscii()
        if (aiPane == "chat" || aiPane == "settings") {
            openAIPane(model, if (aiPane == "chat") { 1 } else { 2 })
        }
        // 对话页快照要给**预置对话**，否则拍到的是空态 ——
        // 空态里没有消息卡，看不到 Markdown 在 `Panel` + `ScrollView`
        // 这层嵌套里排得对不对（与 C5 面板的嵌套不同，得单独拍）。
        if (aiPane == "chat" && getVariable("DD_SNAP_AI_CHAT").isSome()) {
            seedSnapshotChat(model)
        }
        // C5 结果面板：给一段**预置正文**拍静态照。
        // 不发真请求 —— 快照模式没有 provider 可打，而 C5 那块屏
        // 要验的是「结果正文排得对不对」，不是「模型回不回得来」。
        //
        // ⚠ 正文刻意覆盖**八种块类型**，而且用的是**真实形状**：
        // 有序列表带 GFM 悬挂缩进续行（这是本仓库 README 与模型输出的
        // 常见写法，也是上一版渲染器会把清单打散的那一种），
        // 表格照抄引擎 `context` 里的分支表。少覆盖一种，
        // 快照就只是证明「标题和段落能显示」，证明不了渲染器。
        let sheet = (getVariable("DD_SNAP_AI_SHEET") ?? "").trimAscii()
        if (!sheet.isEmpty()) {
            model.aiSheetTitle.value = "项目群说明"
            model.aiSheetBody.value = """
            ## 这一轮做了什么

            - 模型先调了 `get_group_context` 拿到 15 个项目的确定性事实
            - 再调 `get_milestones` 确认没有未达成项

            ## 结论

            项目群整体活跃：近 7 天 9 个项目有提交，7 个有未提交改动。
            **待合入 4 个分支**是最该先看的 —— 它们已经做完但没并进去。

            该先看的地方，按这个顺序：

            1. **moonpainter 有 13 处未提交**，量最大。
               这 13 处已经攒了三天，再拖下去会和 `main` 打架。
            2. **deepOrca 16 处未提交**，其中 3 处是 `src` 下的重命名。
               重命名没并进去会连带影响构建，建议单独一次提交。
            3. 其余项目的未提交量都在 3 处以内，不急。

            | 分支 | 状态 | 待记录 | 最近提交 |
            |---|---|---|---|
            | ▸main | 闲置 | 0 | 3 天前 merge: 合入远端 5 个提交 |
            | feat/ai-panel | 活跃 | 2 | 今天 feat: 面板改版 |

            复核命令长这样：

            ```sh
            moongit context --scope moonpainter
            moongit journal moonpainter --limit 20
            ```

            > ⚠ 有 3 个项目读不出更新时间（`lastCommitAt` 缺失），
            > 上面「近 7 天活跃 9」不含它们。
            """
            model.aiPane.value = 3
        }
        let proj = (getVariable("DD_SNAP_PROJECT") ?? "").trimAscii()
        if (!proj.isEmpty()) {
            // 同理：走 `applyScope`，别自己拼那三个字段
            let idx = snapshotProjectIndex(model, proj)
            if (idx > 0) {
                applyScope(model, idx)
            }
        }
        // T1 自查开关：预置一次**挂起的破坏性确认**，拍「确认 Modal 在场」。
        // 与 DD_SNAP_ROOT 同族 —— CUI 快照只在启动即拍，用户点不出一个确认框；
        // 没有这个开关，确认框的布局（点名对象、代价句、按钮排布）只能靠
        // 「代码读着像对的」来相信。走 `pendConfirm` 而不是直接写字段：
        // 免确认档（done/open）在这里会被拒，快照上框不开，一眼就是接错了。
        // 形状：remove:<里程碑名> | drop:<里程碑名> | commit[:<项目名>] |
        //       update:deep | update:shallow
        let confirm = (getVariable("DD_SNAP_CONFIRM") ?? "").trimAscii()
        if (!confirm.isEmpty()) {
            // 主体可能本身带冒号（里程碑名是自由文本）：第 0 段是动作，
            // 其余原样拼回去。
            let parts = confirm.split(":")
            let kind = parts[0].trimAscii()
            var subject = ""
            for (i in 1..parts.size) {
                subject += (if (subject.isEmpty()) { parts[i] } else { ":${parts[i]}" })
            }
            // 项目名默认取项目群第一个（夹具里是 atlas）；commit 可用
            // commit:<项目名> 指定 —— 挑一个工作区非空的，规模句才有数字可拍。
            var projName = ""
            let ps = allProjectsOf(model)
            if (!subject.isEmpty() && kind == "commit") {
                projName = subject.trimAscii()
            } else if (ps.size > 0) {
                projName = ps[0].name
            }
            if (kind == "remove") {
                pendConfirm(model, PendingConfirm(DestructiveAction.RemoveMilestone,
                    project: projName, name: subject, op: "remove"))
            } else if (kind == "drop") {
                pendConfirm(model, PendingConfirm(DestructiveAction.DropMilestone,
                    project: projName, name: subject, op: "drop"))
            } else if (kind == "commit") {
                pendConfirm(model, PendingConfirm(DestructiveAction.CommitAll,
                    project: projName, op: "commit", message: "快照自查"))
            } else if (kind == "update") {
                pendConfirm(model, PendingConfirm(DestructiveAction.BulkUpdate,
                    deep: subject.trimAscii() == "deep"))
            }
        }
    }

    // 启动参数深链（C10）。与 macOS 端 `handleLaunchArgs` 同一组键。
    // ⚠ **在预载之后**才应用：项目列表还没加载时判断「项目不存在」
    // 会把一个存在的项目误报成不存在（macOS 端 `Router.loadedNames`
    // 专门处理了这一点，这里靠「等列表到了再判」达到同样效果）。
    model.launchRoute = parseLaunchRoute(args)
    model.launchPending = !model.launchRoute.isEmpty()

    // 快照模式下不走预载：**在 `app.run` 之前阻塞等引擎会死锁**
    // （栈停在 `semaphore_wait_trap`，主线程与读线程互相等）。
    // 改在构建闭包里逐帧让出（见 `snapshotGate`），那里事件循环已经在跑。
    let snapMode = wantsSnapshot()

    // 快照模式下把窗口开大：**每帧成本上升，48 帧自然就等到了引擎数据。**
    // CUI 是「渲染满 48 帧就拍照退出」，而引擎读取在后台线程上要约 2 秒；
    // 1180×760 的软件渲染一帧约 40ms，48 帧只有 1.9 秒 —— 刚好差一点，
    // 于是拍到的永远是「读取项目群…」。
    //
    // ⚠ 试过并且**都不行**的两条路，留在这儿免得下个人再走一遍：
    //   1. `app.run` 之前同步预载 → **死锁**（主线程与管道读线程互等，
    //      栈停在 `semaphore_wait_trap`，进程 0% CPU 永不返回）。
    //   2. 在构建闭包里同步预载 → 同样**死锁**。CUI 逐帧用 worker 线程跑
    //      保留体，构建期间线程池已被占满，`execCapture` 派生出来的
    //      两个管道读线程拿不到执行机会，`wait()` 永远等不到。
    //   3. 构建闭包里逐帧 `sleep` 等后台线程 → 数据**永远不来**
    //      （`sleep` 期间仓颉派生线程没有运行机会）。
    // 所以唯一稳的办法是让 48 帧本身变慢，而窗口开大是最省事的一种。
    var winW: Int32 = 1180
    var winH: Int32 = 760
    if (snapMode) {
        winW = snapshotW()
        winH = snapshotH()
    }
    let app = DesktopApp(
        WindowSpec("deepDolphin", winW, winH, scale: 1.0),
        theme: (if (dark) { ddDarkTheme() } else { ddLightTheme() }),
        // 桌面环境靠这三样东西串起来才认得出「这是 deepDolphin」：
        //   .desktop 文件名  hicolor 图标名  这里的 identifier
        // 三者必须**同名**。任何一个对不上，症状都一样 —— 窗口照常起来，
        // 任务栏/启动器里却没有图标（或干脆没有这个应用的条目），
        // 而这个原因极难从现象反推出来。
        //
        // SDL 的映射：Wayland 下 identifier → app_id（XDG desktop file 的
        // basename）；X11 下 → WM_CLASS。所以两个后端都要它在。
        //
        // ⚠ CUI 没有暴露 `SDL_SetWindowIcon`，所以**运行时窗口图标**这条路
        // 在本框架下走不通（vendor 是第三方，不改）。图标由
        // `linux/scripts/install-icon.sh` 装进 hicolor + 装 .desktop 来兑现。
        metadata: Some(AppMetadata(name: Some("deepDolphin"), identifier: Some("deepdolphin")))
    )
    // 与 macOS 端一致的下限：低于这个宽度侧栏与 KPI 行会挤成不可用。
    app.setMinimumSize(940, 640)

    // 启动就读一次。窗口开着却空空如也、要用户点一下「刷新」才动，
    // 那是缺陷不是设计 —— 引擎调用本身就走后台线程，不占 UI。
    // 引擎找不到时 `requestRefresh` 会直接返回，此时空态已经把原因说清楚了。
    //
    // ⚠ R1-02：`app.run` 里（构建闭包、post 回来的闭包、拆卸清理）抛出的
    // 异常会穿透到这里 —— 不接的话进程以未捕获异常裸崩、退出码非 0，
    // 引擎给的原因一个字都看不见。打印到 stderr 后**以 0 退出**：
    // 此时窗口生命周期已经结束，再按崩溃对待只会误导会话与调试器。
    try {
    app.run {
        // 一次性闸门。写在 build 里就得自己保证只跑一次 ——
        // `app.run` 的闭包是**每次状态变化都重新执行**的构建函数，
        // 直接在里面 `boot(app, model)` 的话，每改一次状态就发一次引擎调用。
        // 快照模式下 `booted` 已被预载置真，这里不会再发引擎调用。
        if (!model.booted) {
            model.booted = true
            // R4-10：引擎定位在**首帧之后**做 —— 建窗前不再起探活子进程。
            // 定位可能要几秒，也不能在构建闭包里同步跑（那会冻住首帧）：
            // 放后台，定位完 post 回来挂载，再启动首轮读取与轮询。
            // 夹具模式在 main 里已同步挂载，走不进这个 spawn。
            // ⚠ 定位本身也要兜异常（同 requestRefresh 的教训）：spawn 里的
            // 异常没人接，线程死了 post 永不来，界面永远停在「正在定位引擎…」。
            spawn {
                try {
                    let loc = locateEngine()
                    app.post {
                        model.attachEngine(loc)
                        boot(app, model)
                        startPolling(app, model)
                    }
                } catch (e: Exception) {
                    let why = e.message
                    app.post {
                        model.attachEngine(EngineLocation("", "定位引擎时出错：${why}", ""))
                    }
                }
            }
        }
        // `DD_SNAP_CLICK=<行号>`：模拟「点侧栏仓库组第 N 行」。
        //
        // ⚠ 为什么需要它：侧栏的点击路由装在 `sidebar()` → `mountEffect` 里，
        // 单元判据不开窗就执行不到那个闭包。所以即便接线函数本身已被
        // `clickingTheSidebarActuallyRoutesBecauseSomebodyIsListening` 覆盖，
        // 「**sidebar() 到底还调不调它**」这一截仍然只有读代码能验。
        // 这里让**真实构建**先装上观察者，再写 `selected` ——
        // 快照上侧栏高亮换到了第 N 行，就说明整条链接通了。
        //
        // ⚠⚠ 必须**在 `app.run` 之后**由后台线程 post 回来，不能写在
        // 构建闭包里 —— 闭包是**单次**执行（夹具模式下无状态变化，48 帧
        // 渲染期间它不会重跑），而首次构建时 `mountEffect` 的 prepare 阶段
        // **还没跑**（它在构建体之后），那时的点击必然无人接。
        // 症状与「接线被摘了」一模一样：快照上高亮纹丝不动。实测踩过。
        if (snapMode && !model.snapClickFired) {
            let clickRow = envInt("DD_SNAP_CLICK", -1)
            if (clickRow >= 0) {
                model.snapClickFired = true
                spawn {
                    // 等首帧与 mountEffect 的 prepare 跑完再点。
                    // 48 帧在 1400×2400 下约两秒，1.2 秒落在这中间，
                    // 剩下的帧足够把换页后的界面重画出来。
                    sleepMs(1200)
                    // ⚠ 留这一行不是为了好看：这条路径**失败时完全静默**
                    // （症状就是「快照上高亮没动」，和「点了没反应」一模一样）。
                    if (!app.post({=> model.selected.value = Int64(clickRow)})) {
                        println("[DD_SNAP_CLICK] post 失败：应用已停止，这次快照没验到东西")
                    }
                }
            }
        }
        // 深链**等项目列表到了才应用**。
        //
        // ⚠ 不能在 `boot` 之前判「项目存不存在」：那时 `allProjectsOf` 是空的，
        // 一个真实存在的项目会被报成「找不到」并改道仪表盘 ——
        // 而用户是从桌面通知点进来的，看到的是「那个项目被删了」。
        // macOS 端 `Router.loadedNames(hasLoadedProjectsOnce:)` 处理的是同一件事。
        if (model.launchPending && model.snapshot.value.isSome()) {
            model.launchPending = false
            applyLaunchRoute(model, model.launchRoute)
        }
        rootView(model, app)
    }
    } catch (e: Exception) {
        eprintln("deepdolphin: 退出时出错：${e.message}")
    }
    return 0
}

/// 预置一段对话，给对话页快照用。
///
/// ⚠ 助手那条**刻意包含全部八种块类型**：标题、列表、有序清单（带悬挂缩进
/// 续行）、表格、代码块、引用。少了任何一种，截图就只证明了「一部分能显示」。
/// 工具结果那条是**不渲染 Markdown** 的对照：它是引擎原文，渲染它等于
/// 替引擎重新排版事实 —— 快照上一眼能看出这条与助手那条长得不一样。
private func seedSnapshotChat(model: AppModel): Unit {
    let list = ArrayList<ChatMessage>()
    list.add(ChatMessage(ChatRole.User, "moonpainter 现在什么状况？先说结论，再说依据。"))
    list.add(ChatMessage(ChatRole.Tool, "get_project_context · payload 3.9 KB · 8 个分支 · 4 个里程碑"))
    list.add(ChatMessage(ChatRole.Assistant, """
        ## 结论

        **moonpainter 有 13 处未提交改动**，其中 4 处是新增文件、9 处是修改。
        分支 `main` 已并入远端，本地没有落后。

        ## 依据

        1. **未提交集中在 `src/` 下**。
           13 处里有 9 处在 `src/`，其余 4 处在文档。
        2. **里程碑还有 2 个没打勾**。
           「深更新文档托管区域」和「接入 CI」都还在进行中。
        3. 最近 7 天有 4 次提交，最近一次是昨天。

        | 分支 | 状态 | 待记录 | 最近提交 |
        |---|---|---|---|
        | ▸main | 闲置 | 0 | 1 天前 docs: 补托管区域说明 |
        | feat/ai-panel | 活跃 | 2 | 今天 feat: 面板改版 |

        要看具体文件的话：

        ```sh
        moongit context moonpainter
        moongit journal moonpainter --limit 20
        ```

        > ⚠ `lastCommitAt` 这个项目读不出来，所以「最近 7 天 4 次提交」
        > 是按 journal 的行数数的，不是按时间戳。
        """))
    model.aiTranscript.value = Some(list)
}

/// 视图 → 侧栏下标（0 仪表盘 / 1 看板 / 2 里程碑）。
/// 与 `viewAtIndex` 互逆；没有对应项时返回 -1。
func sectionIndexOf(r: RootSection): Int64 {
    if (rootSectionIs(r, RootSection.Dashboard)) {
        return 0
    }
    if (rootSectionIs(r, RootSection.Board)) {
        return 1
    }
    if (rootSectionIs(r, RootSection.Milestones)) {
        return 2
    }
    return -1
}

/// 范围下拉里某个项目的下标（1 起）。找不到返回 -1。
///
/// 快照开关要跳到指定项目，就必须经过**下拉用的那套下标**，
/// 直接写 `selectedProject` 会让下拉显示错的项 ——
/// 与侧栏高亮失配是同一族问题。
func snapshotProjectIndex(model: AppModel, name: String): Int64 {
    var i: Int64 = 0
    for (p in allProjectsOf(model)) {
        if (p.name == name) {
            return i + 1
        }
        i += 1
    }
    return -1
}
