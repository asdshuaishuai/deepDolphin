// deepDolphin Linux 客户端 —— 入口。
//
// 仓颉 + CangjieGUI（CUI）的桌面应用。数据全部来自 **moonGit 引擎子进程**
// 的 `--json` 输出，本端不落任何业务数据，与 macOS 端同一边界。
package deepdolphin_linux

import cui.{DesktopApp, WindowSpec}

main(): Int64 {
    let app = DesktopApp(
        WindowSpec("deepDolphin", 1180, 760, scale: 1.0),
        theme: ddTheme()
    )
    // 与 macOS 端一致的下限：低于这个宽度侧栏与 KPI 行会挤成不可用。
    app.setMinimumSize(940, 640)

    let model = AppModel(locateEngine())
    // 启动就读一次。窗口开着却空空如也、要用户点一下「刷新」才动，
    // 那是缺陷不是设计 —— 引擎调用本身就走后台线程，不占 UI。
    // 引擎找不到时 `requestRefresh` 会直接返回，此时空态已经把原因说清楚了。
    app.run {
        // 一次性闸门。写在 build 里就得自己保证只跑一次 ——
        // `app.run` 的闭包是**每次状态变化都重新执行**的构建函数，
        // 直接在里面 `boot(app, model)` 的话，每改一次状态就发一次引擎调用。
        if (!model.booted) {
            model.booted = true
            boot(app, model)
        }
        rootView(model, app)
    }
    return 0
}
