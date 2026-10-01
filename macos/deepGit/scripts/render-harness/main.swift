// render-harness/main.swift — 离屏渲染客户端视图并输出 PNG。
//
// 【为什么需要它】
// 项目里反复出现「视觉未验证，只能靠人眼」这个待办：顶栏双轨按钮在 1100 宽
// 下挤不挤、spacing 等值替换后观感如何、圆角改连续曲率后接缝对不对得上 ——
// 这三件都只能看。本 harness 让**代码自己看**：把真实视图在离屏渲染成 PNG，
// 于是「未验证」不再是永久待办。
//
// 【三种模式】run.sh <输出目录> [模式]
//   （无参数）逐个渲染**内容视图** → detail.png / dashboard.png。验内容排版用这个。
//   window   同上，但把视图装进 NSWindow 再拍。差异见第 6 条。
//   panel    整个面板（侧栏 + 顶栏 + 主区）一次拍全 → panel.png。**验顶栏用这个**。
//
// 【边界：它能验什么、不能验什么】
//   能：布局溢出/错位、间距与圆角的实际观感、卡片接缝、颜色层次、三态文案排版、
//       顶栏按钮的排布与是否挤。
//   不能：窗口 chrome 的拖拽/缩放行为、滚动位置、动画、真实交互、真实光标。
//
// 【这一轮实测出来的离屏限制】每条都做过对照实验，不是猜的：
//   1. **不能用 `ImageRenderer`**：它对 NavigationSplitView 这类视图只渲染出
//      一张黄底红斜杠的「禁止」占位图 —— 极易被误当成「界面画成这样」。
//      判据：看到占位图就说明这条路走不通，换 `NSHostingView` + `cacheDisplay`。
//   2. **不要在裸 NSHostingView 里渲染整个面板**：侧栏与路由不参与布局 ⇒
//      截出来是「空侧栏 + 主区停住」，看着像布局坏了。panel 模式用窗口就正常。
//   3. **等待点必须在视图创建之后**：DashboardView 底部挂着
//      `.task { await model.fetchDashboard() }` —— 预加载时等好的终态会在挂载
//      瞬间被重新拉回 .loading，于是截到的是中间态。
//      等的条件也要**与视图的判定同源**（视图读 `dashboardState` 就等它，
//      别等 `dashboard != nil`）。
//   4. **等待必须用 `await`，不能靠 `RunLoop.run(mode:before:)` 空转** ——
//      详见 `render` 的函数头。那条不转就会让视图的 `.task` 永远停在 .loading。
//   5. **窗口可以建，但绝不能上屏**：`orderFront` 需要 UI session，本环境没有，
//      会 SIGSEGV。停在「已建好但没上屏」照样能布局、能取位图 —— 顶栏就是这么拍到的。
//   6. **window / panel 模式下顶栏下方不施加安全区**：detail 内容会滑到顶栏底下、
//      首行被裁。同一份视图在裸视图模式下顶栏完整 ⇒ 是 window 路径的代价，
//      不是布局缺陷。⇒ **panel 模式只看顶栏，内容排版回默认模式看。**
//   7. **header 位置的按钮画不出文字**（快照里是白框）。对照实验：把它从裸
//      `HStack` 改成 `Label` 之后**仍是白框**，而同一张图里 gitOpButton 的
//      文字正常 ⇒ 与 label 结构无关，是位置/样式的离屏限制。
//      **别拿快照判断按钮对不对，要看真窗口。**
//   8. **个别文字行会重叠**（实测 detail header 的 headline 与 path 两行）。
//      对照实验：把 `spacing: 6` 改成 `DSSpacing.sm`(8) 后重叠**依旧**
//      ⇒ 不是间距不够，是未挂窗口时文本行高算不准 ⇒ 同样是离屏限制。
//
// 【⚠️ 一条被推翻的旧结论，留在这是为了不再犯】
//   这里曾经写着「造窗口 orderFront 会 SIGSEGV，所以整窗渲染不可行，顶栏只能人眼看」。
//   **那条结论是假的** —— 那次崩溃是本文件自己的一个无限递归 `log()` 打出来的，
//   而它恰好和整窗渲染的实验在同一批未提交改动里，于是被当成了环境的锅。
//   修掉递归之后：窗口能建（不上屏）、顶栏能拍、侧栏也能拍。
//   教训：**别让「放弃某条路」的理由和一个自己都还没验证过的改动绑在一起** ——
//   要先确认失败原因，再决定要不要放弃。见 AGENTS.md 不变量 101。
//
// 【编译】
//   swiftc -DDEEPGIT_RENDER_HARNESS <Sources/deepGit/*.swift> main.swift -o harness
//   条件编译宏用来屏蔽 DeepGitApp 的 @main（否则两个入口打架）。
//   ⚠️ `#if` 必须**只**包住 @main struct，DeepGitPanel 要留在外面 ——
//   第一版把 `#endif` 放在文件末尾，连 DeepGitPanel 一起屏蔽了，报
//   "cannot find 'DeepGitPanel' in scope"。
//
// 【运行】
//   用同目录的 run.sh（它造沙箱项目、编译、装 .app bundle 再跑）。
//   ⚠️ 裸可执行文件会在 `UNUserNotificationCenter.current()` 处崩
//   （`bundleProxyForCurrentProcess is nil`）—— 通知系统要 bundle，绕不过去。
import SwiftUI
import AppKit

/// 日志唯一入口。
///
/// ⚠️ 存在的理由：`.utf8` 的优先级高于 `+`，所以
/// `Data("a" + "b\n".utf8)` 会变成 `String + Data` 编译失败。
/// 这个坑我在本文件里已经犯了**三次**（每次都是新写的日志行），
/// 写进注释显然没用 —— 所以改成结构性防御：所有日志都必须经过这里，
/// 于是「忘了套 .utf8」这件事不再可能发生。
func log(_ s: String) {
    // ⚠️ 用 `s.utf8` 整体取字节再拼进 Data，不要写成 `Data("a" + "b".utf8)` ——
    // `.utf8` 优先级高于 `+`，那样会被解析成 `String + Data`。
    // ⚠️ 写 stderr 而非 stdout：stdout 在这个 harness 里可能被缓冲，
    // 崩溃时缓冲区里的日志就丢了，而日志恰恰是排查崩溃最需要的东西。
    FileHandle.standardError.write(Data(s.utf8))
}

@MainActor
func run() async {
    let model = AppModel.shared
    await model.start()
    // ⚠️ 只等 `projects` 非空是不够的：第一版就停在这儿，截出来是
    // 「汇总项目群…」的转圈 —— 侧栏有了、主区还在采集，看起来像布局坏了。
    // 渲染快照必须等到**主区画完内容**（仪表盘有数据，或明确失败）。
    // ⚠️ 等待条件必须**和视图的判定条件同源**：视图读的是 `dashboardState`
    // （四态），而我第一版等的是 `dashboard != nil`。两者不是一回事 ——
    // `start()` 内部会再刷一次仪表盘，我可能 break 在两次 fetch 的中间，
    // 截出来就永远是「汇总项目群…」的转圈，看起来像布局坏了。
    var waited = 0
    // 局部函数比 switch+break 清楚：`break` 在 switch 里只跳出 switch，
    // 想跳出 while 得另写标志位，很容易写错（第一版就栽在这）。
    func stateSettled() -> Bool {
        if case .loaded = model.dashboardState { return true }
        if case .failed = model.dashboardState { return true }
        return false
    }
    while waited < 150 && !stateSettled() {
        try? await Task.sleep(nanoseconds: 400_000_000)
        waited += 1
    }
    let stateName: String
    switch model.dashboardState {
    case .idle: stateName = "idle"
    case .loading: stateName = "仍在采集"
    case .loaded: stateName = "已就绪"
    case .failed(let m): stateName = "失败：\(m)"
    }
    // ⚠️ 别写成 `Data("a" + "b\n".utf8)` —— `.utf8` 的优先级高于 `+`，
    // 于是变成 `String + Data`，报 "no exact matches in call to initializer"。
    let stateLine = "harness: 项目 \(model.projects.count) 个 · 仪表盘 \(stateName) · 等了 \(waited) 轮\n"
    log(stateLine)

    // 【对照实验，已做完，结论留在下面】视图挂载前先跑第二次 fetchDashboard：
    //   · 不挂载任何视图 ⇒ 0.33s 到达 .loaded
    //   · 挂在离屏 NSHostingView 里 ⇒ 30s 仍停在 .loading
    // 而引擎 `dashboard --json` 命令行实测只要 0.42s ⇒ 不是「慢」。
    // ⇒ 卡的是**离屏环境**（没有窗口时视图的 .task 拿不到跑完的机会），
    //   不是客户端二次调用有 bug。仪表盘那张快照因此**只能当离屏限制看**。
    // 对照实验的代码已删（它的结论比代码本身更值钱，留在文件里只会被人改坏）。

    let outPath = CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "/tmp/out/panel.png"
    try? FileManager.default.createDirectory(
        atPath: (outPath as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true)

    // ⚠️ **不要渲染整个 DeepGitPanel**（第二版踩过）：NavigationSplitView 的
    // 侧栏与路由在离屏时不参与布局，截出来是「顶栏 + 空侧栏 + 主区停在
    // 「汇总项目群…」，看起来像布局坏了，其实是离屏环境的固有限制。
    // 改成逐个渲染**内容视图**并预加载数据 —— 这样验的正是要看的那些：
    // 卡片间距、圆角接缝、颜色层次、三态文案排版。
    await model.loadProject("alpha")
    await model.loadDocs("alpha")
    await model.fetchDashboard()
    var warm = 0
    while model.projectDetails["alpha"] == nil && warm < 40 {
        try? await Task.sleep(nanoseconds: 250_000_000)
        warm += 1
    }

    let shots: [(base: String, w: CGFloat, h: CGFloat, view: AnyView)] = [
        ("detail", 900, 1500,
         AnyView(ProjectDetailView(projectName: "alpha").environmentObject(model))),
        ("dashboard", 900, 1500,
         AnyView(DashboardView().environmentObject(model))),
    ]
    // argv[2] 选离屏路径：空 = 裸视图；"window" = 装进 NSWindow 但不上屏；
    // "panel" = 整个面板，连侧栏与顶栏一起拍。
    let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
    if mode == "panel" {
        await renderPanel(w: 1100, h: 760, model: model, outPath: outPath)
        exit(0)
    }
    await render(shots: shots, outPath: outPath, model: model, useWindow: mode == "window")
    exit(0)
}

/// 渲染与写盘。
///
/// ⚠️ **这个函数必须是 async，且等待一律用 `await Task.sleep`**。
/// 原来它是同步的，靠 `RunLoop.main.run(mode:before:)` 空转等状态 ——
///
/// **那样转主循环不会排空 MainActor 的任务队列**，后果是：
///   视图的 `.task` 能**启动**（所以 `dashboardState` 被设成 .loading，转圈出现），
///   但它 `await` 完引擎子进程回来后，续体要重新**入主 actor 队列**才能跑
///   ⇒ 那一步永远排不上 ⇒ 状态永远停在 .loading。
///
///   对照实验能证明这不是客户端的锅：同一次 `fetchDashboard()` 在**不挂载视图**时
///   （那里是 `await` 驱动的）0.33s 就到达 .loaded，而引擎 `dashboard --json`
///   命令行实测只要 0.42s ⇒ 不是慢，是等待方式不对。
///   改成 async 之后，Swift 并发运行时自己会驱动主 actor，视图的取数能跑完。
@MainActor
func render(shots: [(base: String, w: CGFloat, h: CGFloat, view: AnyView)],
             outPath: String, model: AppModel, useWindow: Bool) async {
    func stateSettled() -> Bool {
        if case .loaded = model.dashboardState { return true }
        if case .failed = model.dashboardState { return true }
        return false
    }
    for (base, w, h, view) in shots {
        // ⚠️ 别用 `outPath.replacingOccurrences(of: "panel", with: base)`：
        // outPath 里没有 "panel" 时它原样返回 ⇒ 两张图写到同一个文件，
        // 后一张把前一张盖掉，而你只会看到最后一张（还以为是只渲了一处）。
        let dir = (outPath as NSString).deletingLastPathComponent
        let target = "\(dir)/\(base).png"

        // 两条离屏路径都产出同一个 NSView，最后都走 cacheDisplay。
        // 差别在**谁来当宿主的父视图**：
        //   · useWindow=false：直接用裸 NSHostingView，没有窗口。
        //   · useWindow=true ：先装进 NSWindow 的 contentViewController，
        //     但**绝不调 orderFront / makeKeyAndOrderFront**。
        var window: NSWindow? = nil
        let host: NSView
        if useWindow {
            let controller = NSHostingController(rootView: view.frame(width: w, height: h))
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            win.contentViewController = controller
            win.setContentSize(NSSize(width: w, height: h))
            // 关键：窗口停在「已建好但没上屏」的状态。上屏需要 UI session，
            // 本环境没有 —— 但不上屏照样能布局、能取位图。
            window = win
            host = controller.view
        } else {
            let hosting = NSHostingView(rootView: view.frame(width: w, height: h))
            hosting.frame = NSRect(x: 0, y: 0, width: w, height: h)
            host = hosting
        }
        host.frame = NSRect(x: 0, y: 0, width: w, height: h)
        host.layoutSubtreeIfNeeded()

        // ⚠️ **视图挂载后必须再等一次**：DashboardView 底部挂着
        // `.task { await model.fetchDashboard() }` —— 预加载时等好的终态
        // 会在挂载瞬间被重新拉回 .loading，于是截到的是「汇总项目群…」。
        // 这类「视图有取数副作用」的地方，harness 的等待点得在视图**之后**。
        var spin = 0
        while spin < 200 && !stateSettled() {
            try? await Task.sleep(nanoseconds: 50_000_000)
            spin += 1
        }
        // 再多等几轮，让内容真正画出来
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        host.layoutSubtreeIfNeeded()
        log("harness: \(base)（\(useWindow ? "窗口" : "裸视图")）挂载后等了 \(spin) 轮\n")
        if spin >= 200 {
            // 静默超时会被当成「渲染成功但内容空」—— 那是两种完全不同的事。
            log("harness: ⚠️ \(base) 等满 200 轮仍未到终态 ⇒ 截到的是加载态，不是终态\n")
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            log("harness: \(base) 拿不到 bitmap rep\n")
            continue
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { continue }
        do {
            try data.write(to: URL(fileURLWithPath: target))
            log("harness: 已写 \(target)（\(rep.pixelsWide)×\(rep.pixelsHigh)）\n")
        } catch {
            log("harness: 写失败 \(error)\n")
        }
        window = nil   // 释放窗口，避免下一轮仍被上一轮的视图树牵连
    }
}

/// 整面板离屏渲染：侧栏 + 顶栏 + 主区一次拍全。
///
/// ⚠️ **顶栏（NSToolbar）不属于内容视图** —— 它是 `NSWindow` 上的独立对象，
/// 挂在 theme frame（contentView 的父视图）里。所以这里拍的是
/// `window.contentView?.superview`，不是 contentView 本身；拍 contentView
/// 永远拍不到顶栏，这也是本文件第 3 条那句「NSHostingView 拍不到 toolbar」
/// 在**窗口路径**下的准确写法。
///
/// ⚠️ **绝不调 orderFront / makeKeyAndOrderFront**：无 UI session 时会 SIGSEGV。
///   窗口停在「已建好但没上屏」就足以完成布局与取位图。
///   （曾经因为这个崩溃而写下「整窗渲染不可行」的结论，后来发现那次崩溃其实是
///    本文件自己一个无限递归的 log() 打出来的 —— 教训见 AGENTS.md 不变量 101。）
@MainActor
func renderPanel(w: CGFloat, h: CGFloat, model: AppModel, outPath: String) async {
    let dir = (outPath as NSString).deletingLastPathComponent
    let target = "\(dir)/panel.png"
    let controller = NSHostingController(
        rootView: PanelView().environmentObject(model).frame(width: w, height: h))
    let win = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: w, height: h),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered, defer: false)
    win.contentViewController = controller
    win.setContentSize(NSSize(width: w, height: h))
    win.toolbarStyle = .unified

    controller.view.frame = NSRect(x: 0, y: 0, width: w, height: h)
    controller.view.layoutSubtreeIfNeeded()
    // 顶栏的布局由 NSToolbar 在窗口的下一轮布局里完成；同时等主区到终态
    // （PanelView 的 .task 会 start() 一次，DashboardView 的 .task 会再刷仪表盘，
    //  两步合计约 2.5s —— 只空跑 3s 会在主区画完之前就拍，
    //  于是截到「汇总项目群…」，看起来像主区坏了）。
    func stateSettled() -> Bool {
        if case .loaded = model.dashboardState { return true }
        if case .failed = model.dashboardState { return true }
        return false
    }
    var spin = 0
    while spin < 200 && !stateSettled() {
        try? await Task.sleep(nanoseconds: 50_000_000)
        spin += 1
    }
    // 再多跑几轮，让 NSToolbar 完成它自己那一轮布局。
    for _ in 0..<20 {
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    controller.view.layoutSubtreeIfNeeded()
    log("harness: panel 等了 \(spin) 轮到终态\n")

    guard let frame = controller.view.superview else {
        log("harness: panel 拿不到 theme frame\n")
        return
    }
    log("harness: panel theme frame \(frame.frame)\n")
    guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else {
        log("harness: panel 拿不到 bitmap rep\n")
        return
    }
    frame.cacheDisplay(in: frame.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    do {
        try data.write(to: URL(fileURLWithPath: target))
        log("harness: 已写 \(target)（\(rep.pixelsWide)×\(rep.pixelsHigh)）\n")
    } catch {
        log("harness: 写失败 \(error)\n")
    }
}

// harness 自己当入口（DeepGitApp 的 @main 已被条件编译屏蔽）。
final class Flag: @unchecked Sendable { var done = false }
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)   // 不上 Dock、不抢焦点
let flag = Flag()
Task { @MainActor in
    await run()
    flag.done = true
}
// 事件循环：SwiftUI 的 layout 与 MainActor 上的 Task 都挂在主循环上，
// 不跑它就什么都推进不了。
// ⚠️ 只等 run() 完成，别加「无论如何都 signal」的兜底 ——
// 那样会在渲染还没做完时 exit(1)，而退出码 1 又看不出是超时还是崩，
// 排查时容易误判成「渲染不支持这个视图」。
let deadline = Date().addingTimeInterval(180)
while !flag.done && Date() < deadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
log(flag.done
    ? "harness: 完成\n"
    : "harness: 超时 180s（引擎发现失败或数据加载卡住？）\n")
exit(flag.done ? 0 : 1)
