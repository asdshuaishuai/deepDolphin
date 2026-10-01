// render-harness/main.swift — 离屏渲染客户端视图并输出 PNG。
//
// 【为什么需要它】
// 项目里反复出现「视觉未验证，只能靠人眼」这个待办：顶栏双轨按钮在 1100 宽
// 下挤不挤、spacing 等值替换后观感如何、圆角改连续曲率后接缝对不对得上 ——
// 这三件都只能看。本 harness 让**代码自己看**：把真实视图在离屏渲染成 PNG，
// 于是「未验证」不再是永久待办。
//
// 【边界：它能验什么、不能验什么】
//   能：布局溢出/错位、间距与圆角的实际观感、卡片接缝、颜色层次、三态文案排版。
//   不能：窗口 chrome、真实 toolbar（toolbar 由 NSWindow 承载，不是视图的一部分）、
//         滚动位置、动画、真实交互。
//   所以 toolbar 类问题仍需人眼，这里**不假装**能覆盖。
//
// 【这一轮实测出来的离屏限制】每条都做过对照实验，不是猜的：
//   1. **不能用 `ImageRenderer`**：它对 NavigationSplitView 这类视图只渲染出
//      一张黄底红斜杠的「禁止」占位图 —— 极易被误当成「界面画成这样」。
//      判据：看到占位图就说明这条路走不通，换 `NSHostingView` + `cacheDisplay`。
//   2. **不要渲染整个 DeepGitPanel**：NavigationSplitView 的侧栏与路由在离屏时
//      不参与布局 ⇒ 截出来是「顶栏 + 空侧栏 + 主区停在「汇总项目群…」」，
//      看着像布局坏了，其实是离屏环境限制。逐个渲染**内容视图**才对。
//   3. **等待点必须在视图创建之后**：DashboardView 底部挂着
//      `.task { await model.fetchDashboard() }` —— 预加载时等好的终态会在挂载
//      瞬间被重新拉回 .loading，于是截到的是中间态。
//      等的条件也要**与视图的判定同源**（视图读 `dashboardState` 就等它，
//      别等 `dashboard != nil`）。
//   4. **header 位置的按钮画不出文字**（快照里是白框）。对照实验：把它从裸
//      `HStack` 改成 `Label` 之后**仍是白框**，而同一张图里 gitOpButton 的
//      文字正常 ⇒ 与 label 结构无关，是位置/样式的离屏限制。
//      **别拿快照判断按钮对不对，要看真窗口。**
//   5. **个别文字行会重叠**（实测 header 的 headline 与 path 两行）。对照实验：
//      把 `spacing: 6` 改成 `DSSpacing.sm`(8) 后重叠**依旧** ⇒ 不是间距不够，
//      是未挂窗口时文本行高算不准 ⇒ 同样是离屏限制。
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
    FileHandle.standardError.write(Data(stateLine.utf8))

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
    render(shots: shots, outPath: outPath, model: model)
    exit(0)
}

/// 渲染与写盘。**刻意不是 async** —— `RunLoop.run(mode:before:)` 被标注了
/// `NS_SWIFT_UNAVAILABLE_FROM_ASYNC`，放在 async 函数体里每次编译都刷警告
/// （第一版就在 async 里跑，警告刷了满屏）。数据准备在 `run()` 里做完，
/// 这里的循环只需要转主循环，不需要 await。
@MainActor
func render(shots: [(base: String, w: CGFloat, h: CGFloat, view: AnyView)],
             outPath: String, model: AppModel) {
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
        let hosting = NSHostingView(rootView: view.frame(width: w, height: h))
        hosting.frame = NSRect(x: 0, y: 0, width: w, height: h)
        hosting.layoutSubtreeIfNeeded()
        // ⚠️ **视图挂载后必须再等一次**：DashboardView 底部挂着
        // `.task { await model.fetchDashboard() }` —— 预加载时等好的终态
        // 会在挂载瞬间被重新拉回 .loading，于是截到的是「汇总项目群…」。
        // 这类「视图有取数副作用」的地方，harness 的等待点得在视图**之后**。
        var spin = 0
        while spin < 200 && !stateSettled() {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            spin += 1
        }
        // 再空跑几轮，让内容真正画出来
        for _ in 0..<12 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        hosting.layoutSubtreeIfNeeded()
        FileHandle.standardError.write(Data("harness: \(base) 视图挂载后等了 \(spin) 轮\n".utf8))
        if spin >= 200 {
            // 静默超时会被当成「渲染成功但内容空」—— 那是两种完全不同的事。
            // 实测：DashboardView 的 `.task` 在离屏 NSHostingView 里发起的
            // 引擎子进程调用不保证在快照窗口内返回，于是状态一直挂在 .loading。
            FileHandle.standardError.write(Data(
                "harness: ⚠️ \(base) 等满 200 轮仍未到终态 ⇒ 截到的多半是加载态，\n"
                + "        这是离屏限制（见本文件顶部第 3 条），不是界面缺陷。\n".utf8))
        }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            FileHandle.standardError.write(Data("harness: \(base) 拿不到 bitmap rep\n".utf8))
            continue
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { continue }
        do {
            try data.write(to: URL(fileURLWithPath: target))
            FileHandle.standardError.write(Data("harness: 已写 \(target)（\(rep.pixelsWide)×\(rep.pixelsHigh)）\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("harness: 写失败 \(error)\n".utf8))
        }
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
FileHandle.standardError.write(Data(flag.done
    ? "harness: 完成\n".utf8
    : "harness: 超时 180s（引擎发现失败或数据加载卡住？）\n".utf8))
exit(flag.done ? 0 : 1)
