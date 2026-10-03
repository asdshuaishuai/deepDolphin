// deepDolphin Linux 客户端 —— 入口。
//
// 仓颉 + CangjieGUI（CUI）的桌面应用。数据全部来自 **moonGit 引擎子进程**
// 的 `--json` 输出，本端不落任何业务数据，与 macOS 端同一边界。
package deepdolphin_linux

import cui.{AppMetadata, DesktopApp, WindowSpec}
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
    let fontProblem = installAppFonts()

    // 外观在**建窗之前**定下来：CUI 的 `Theme` 是 `DesktopApp` 的构造参数，
    // 建成之后换不了（`Theme` 不可变，且 `DesktopApp` 没有 setTheme）。
    // 要跟随系统切换就得重启应用 —— 这条限制在界面上要说出去，
    // 否则用户点「暗色」发现要重启，会以为功能坏了。
    let (dark, probeFailed) = resolveAppearance()
    let model = AppModel(locateEngine())
    model.dark.value = dark
    model.appearance.value = readSavedAppearance()
    model.appearanceUnknown.value = probeFailed
    model.problem.value = fontProblem

    // 夹具模式：直接从磁盘读引擎真实输出，不起子进程。
    // 布局自查走这条路 —— 理由见 `loadFromFixtureDir` 的注释。
    let fixtureDir = getVariable("DD_FIXTURE_DIR") ?? ""
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
        let proj = (getVariable("DD_SNAP_PROJECT") ?? "").trimAscii()
        if (!proj.isEmpty()) {
            // 同理：走 `applyScope`，别自己拼那三个字段
            let idx = snapshotProjectIndex(model, proj)
            if (idx > 0) {
                applyScope(model, idx)
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
    app.run {
        // 一次性闸门。写在 build 里就得自己保证只跑一次 ——
        // `app.run` 的闭包是**每次状态变化都重新执行**的构建函数，
        // 直接在里面 `boot(app, model)` 的话，每改一次状态就发一次引擎调用。
        // 快照模式下 `booted` 已被预载置真，这里不会再发引擎调用。
        if (!model.booted) {
            model.booted = true
            boot(app, model)
            startPolling(app, model)
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
    return 0
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
