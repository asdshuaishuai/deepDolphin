// deepDolphin Linux 客户端 —— 系统集成（C10）。
//
// macOS 端对应三处：`Notifier`（UNUserNotificationCenter）、`LoginItem`
// （SMAppService）、`handleLaunchArgs`（深链）。本端用 Linux 的等价物：
//   · 通知      → `notify-send`（libnotify，GNOME/KDE 默认都有）
//   · 开机自启  → XDG `~/.config/autostart/*.desktop`
//   · 启动参数  → 命令行（`--project` / `--section`）
//
// 【CUI 没有的，如实记】
// CUI **不暴露**托盘 API（没有 SDL_SetWindowIcon、没有 StatusNotifier 绑定），
// 所以 macOS 那个「菜单栏速览」（`MenuBarExtra` + `BarView`）在本端**没有对应物**。
// 不拿「通知」冒充「托盘」—— 那两件事解决的不是同一个问题。
package deepdolphin_linux

import std.fs.*
import std.env.*
import std.collection.*

// ---------------------------------------------------------------------------
// 通知
// ---------------------------------------------------------------------------

/// notify-send 的兜底位置：PATH 上找不到时最后试这一处。
private const NOTIFY_SEND_FALLBACK: String = "/usr/bin/notify-send"

/// notify-send 的位置：先走 PATH，找不到再回退 /usr/bin。
/// ⚠ 第一版钉死 /usr/bin —— 工具装在 PATH 别处（发行版把 bin 挪进 /bin、
/// 用户自装 prefix）时明明有 notify-send 也报「找不到」。
private func notifySendBin(): String {
    let p = firstToolOnPath(["notify-send"])
    return (if (p.isEmpty()) { NOTIFY_SEND_FALLBACK } else { p })
}

public func hasNotifySend(): Bool {
    return exists(notifySendBin())
}

/// 发一条系统通知。**返回失败原因**而不是静默丢。
///
/// ⚠ `notify-send` 缺失在**精简桌面**上很常见（无 GNOME/KDE 的会话）。
/// 静默丢掉的话，用户点了「深更新全部」之后等半天，
/// 不知道是任务卡住了还是通知根本不存在。
public func notifyUser(title: String, body: String): String {
    let bin = notifySendBin()
    if (!exists(bin)) {
        return "找不到 notify-send（PATH 与 /usr/bin 都试过）—— 系统通知不可用（装 libnotify-bin）"
    }
    let r = execCapture(bin, ["-a", "deepDolphin", "-u", "normal", title, body], 10000)
    if (r.timedOut) {
        return "发通知超时"
    }
    if (r.exitCode != 0) {
        let why = if (!r.stderr.trimAscii().isEmpty()) { r.stderr.trimAscii() } else { "退出码 ${r.exitCode}" }
        return "发通知失败（${why}）"
    }
    return ""
}

/// 通知文案。**纯函数**，判据直接断言长任务该怎么说。
///
/// 长任务（深更新要跑 5 分钟）结束时通知里必须有**发生了什么**，
/// 只写「完成」的话用户在几十秒后已经忘了自己点了什么。
public func updateFinishedNotice(actionLabel: String, target: String, ok: Bool, detail: String): String {
    let where_ = (if (target.isEmpty()) { "全部项目" } else { target })
    if (ok) {
        return "${actionLabel}完成：${where_}${detail}"
    }
    return "${actionLabel}失败：${where_}${detail}"
}

// ---------------------------------------------------------------------------
// 开机自启
// ---------------------------------------------------------------------------

/// `$XDG_CONFIG_HOME` 的解析规则：非空且是**绝对路径**才认，否则 `~/.config`。
/// 纯函数核心拆出来给判据（读环境变量的那层是 xdgConfigHome）。
func xdgConfigBase(xdg: String, home: String): String {
    let x = xdg.trimAscii()
    if (!x.isEmpty() && x.startsWith("/")) {
        return x
    }
    return "${home}/.config"
}

/// freedesktop Autostart 规范的用户级自启目录：`$XDG_CONFIG_HOME/autostart`
/// （默认 `~/.config/autostart`）。会话登录时**只扫这一个目录** ——
/// 本文件第一版写进应用私有目录（`~/.config/deepdolphin/autostart/`），
/// 桌面根本不会读到它，整个自启功能等于不存在（R3-01）。
public func xdgAutostartDir(xdg: String, home: String): String {
    return "${xdgConfigBase(xdg, home)}/autostart"
}

private func xdgConfigHome(): String {
    return xdgConfigBase(getVariable("XDG_CONFIG_HOME") ?? "", getVariable("HOME") ?? "")
}

private func autostartPath(): String {
    return "${xdgConfigHome()}/autostart/deepdolphin.desktop"
}

/// .desktop 正文。**纯函数** —— 判据直接看它长什么样。
///
/// ⚠ `Exec=` 按 freedesktop Desktop Entry 规范解析：按**未加引号的空白**
/// 切分参数、引号定界参数。所以每个参数都整段包进双引号、引号内的
/// `"` 与 `\` 用 `\` 转义（见 escapeDesktopExec）—— 旧写法的 `\s`
/// （转义空格）现行规范里没有，会话会把它留成字面 `\ `，路径照样断开。
public func autostartEntry(execPath: String, bin: String): String {
    return "[Desktop Entry]\n" +
        "Type=Application\n" +
        "Name=deepDolphin\n" +
        "Comment=Git 项目群进度面板\n" +
        "Exec=${escapeDesktopExec(execPath)}${if (bin.isEmpty()) { "" } else { " --engine " + escapeDesktopExec(bin) }}\n" +
        "Terminal=false\n" +
        "X-GNOME-Autostart-enabled=true\n"
}

/// XDG `Exec=` 字段的单个参数转义：**整参数包双引号**，引号内的
/// `"` 与 `\` 前面加 `\`。
///
/// 为什么不是旧版的「逐字符反斜杠转义」：Desktop Entry 规范里 Exec 的
/// 反斜杠只在**引号内**转义（规范文本中没有 `\s` 这一种），逐字符写出的
/// `My\ Apps` 会被会话解析成字面反斜杠。整参数加引号后，空格与 `&`、
/// `|`、`;` 这类分隔符全部变成字面字符，`install-icon.sh` 写 .desktop 时
/// 用的是同一条规则。
public func escapeDesktopExec(path: String): String {
    let out = StringBuilder()
    out.append("\"")
    for (r in path.runes()) {
        let c = r.toString()
        if (c == "\\" || c == "\"") {
            out.append("\\")
        }
        out.append(c)
    }
    out.append("\"")
    return out.toString()
}

/// 客户端自己的自启入口：scripts/run.sh 绝对路径。
///
/// Exec= 必须指向**能自己摆好仓颉运行时库路径**的入口 —— 二进制直接跑
/// 缺 `libcangjie-runtime.so`（见 scripts/run.sh 顶部注释），会话拉起必挂。
/// 从本进程 argv[0]（`<root>/linux/target/release/bin/main`）上溯四层到
/// `<root>/linux`，再拼 `scripts/run.sh`。argv[0] 不是绝对路径（从 PATH
/// 或相对路径启动）或 run.sh 不在算出的位置时返回空串 —— 调用方必须把
/// 「算不出入口」如实报错，**不许写一个 Exec= 残缺的条目出去**（R3-02：
/// 第一版传了空 execPath，写出的条目是 `Exec= --engine <bin>`，会话把
/// `--engine` 当程序名执行，客户端永远不会被启动）。
public func autostartClientEntry(): String {
    let args = getCommandLine()
    if (args.size == 0 || !args[0].startsWith("/")) {
        return ""
    }
    // main → bin → release → target → <root>/linux，四层
    var p = args[0]
    for (_ in 0..4) {
        let idx = lastIndexOfSlash(p)
        if (idx < 0) {
            return ""
        }
        p = p[..idx]
    }
    let entry = p + "/scripts/run.sh"
    return (if (exists(entry)) { entry } else { "" })
}

/// 开机自启参数自检（**纯函数**，判据直接断言）。空 Exec= 的条目写出去，
/// 会话会把 `--engine` 之类的参数当程序名执行，界面却照样显示「已开启」。
public func autostartEntryProblem(execPath: String): String {
    if (execPath.trimAscii().isEmpty()) {
        return "开机自启的 Exec= 是空的：会话不知道该启动什么。请从仓库内入口（linux/target/release/bin/main）启动客户端后再开自启"
    }
    return ""
}

/// 开机自启现在是什么状态。**读系统真值**，不是读自己上次写的意图。
public func autostartEnabled(): Bool {
    return exists(autostartPath())
}

/// 设置开机自启。**返回失败原因**，空串 = 成功。
///
/// ⚠ execPath 为空时**拒写**（见 autostartEntryProblem）—— 残缺条目比
/// 没有条目更糟：开关显示「已开启」，会话却什么都启动不了。
///
/// 写完**立刻回读一次**：`.config/autostart` 下的东西可能被发行版的
/// 桌面清理脚本删掉，也可能目录压根没建。写完就说「已开启」而实际没开，
/// 是这一族缺陷里最常见的一种。
public func setAutostart(execPath: String, bin: String, want: Bool): String {
    let bad = autostartEntryProblem(execPath)
    if (want && !bad.isEmpty()) {
        return bad
    }
    let p = autostartPath()
    if (!want) {
        if (!exists(p)) {
            return ""
        }
        try {
            remove(p)
        } catch (e: Exception) {
            return "关掉开机自启失败：${e.message}"
        }
        return if (exists(p)) { "关掉开机自启失败：${p} 还在" } else { "" }
    }
    let parent = (match (parentOf(p)) {
        case Some(d) => d
        case None => return "算不出配置目录：${p}"
    })
    if (!exists(parent)) {
        let r = execCapture("/bin/mkdir", ["-p", parent], 5000)
        if (r.exitCode != 0) {
            return "建开机自启目录失败：${parent}"
        }
    }
    File.writeTo(p, autostartEntry(execPath, bin).toArray())
    if (!exists(p)) {
        return "开机自启条目写完就不见了：${p}"
    }
    // 回读内容，不是回读存在性：文件在但内容被截断的桌面环境确实存在
    let back = String.fromUtf8(File.readFrom(p))
    if (!back.contains("[Desktop Entry]")) {
        return "开机自启条目内容不对：${p}"
    }
    return ""
}

/// 取父目录。仓颉 1.0.5 的 `std.fs` 没有 `dirname`（实测 undeclared）。
private func parentOf(p: String): Option<String> {
    let idx = (lastIndexOfSlash(p))
    if (idx <= 0) {
        return None
    }
    return Some(p[..idx])
}

private func lastIndexOfSlash(p: String): Int64 {
    let b = p.toArray()
    for (i in 0..b.size) {
        if (b[b.size - 1 - i] == 0x2fu8) {
            return Int64(b.size - 1 - i)
        }
    }
    return Int64(-1)
}

// ---------------------------------------------------------------------------
// 启动参数（深链）
// ---------------------------------------------------------------------------

public class LaunchRoute {
    /// 空 = 不指定（留在仪表盘）
    public let section: String
    public let project: String

    public init(section: String, project: String) {
        this.section = section
        this.project = project
    }

    public func isEmpty(): Bool {
        return this.section.isEmpty() && this.project.isEmpty()
    }
}

/// 解析启动参数。**纯函数** —— 判据直接喂 argv 数组。
///
/// 支持 `--section dashboard|board|milestones` 与 `--project <名>`，
/// 与 macOS 端 `Route.swift` 的 `handleLaunchArgs` 同一组键。
/// 未知值**不静默忽略也不报错**：原样带出去让调用方决定说什么，
/// 因为「打错了一个字」与「这版还不支持这个 section」要给的提示不同。
public func parseLaunchRoute(args: Array<String>): LaunchRoute {
    var section = ""
    var project = ""
    var i = 0
    while (i < args.size) {
        let a = args[i]
        if (a == "--section" && i + 1 < args.size) {
            section = args[i + 1]
            i += 2
            continue
        }
        if (a == "--project" && i + 1 < args.size) {
            project = args[i + 1]
            i += 2
            continue
        }
        i += 1
    }
    return LaunchRoute(section, project)
}

/// 深链 section 名 → 侧栏下标。-1 = 不认识。
public func sectionIndexOfName(name: String): Int64 {
    if (name == "dashboard") { return 0 }
    if (name == "board") { return 1 }
    if (name == "milestones") { return 2 }
    return -1
}

/// 按名字找项目在**范围下拉**里的下标（1 起）。找不到 -1。
///
/// ⚠ 用 `allProjectsOf` 而不是 `filterProjects(..., query)` ——
/// 深链是「打开某个项目」，不是「在当前搜索结果里找」：
/// 用户搜着别的词时点桌面通知进来，应该照样能打开那个项目。
public func projectIndexByName(model: AppModel, name: String): Int64 {
    var i: Int64 = 0
    for (p in allProjectsOf(model)) {
        if (p.name == name) {
            return i + 1
        }
        i += 1
    }
    return -1
}

/// 深链落到界面上。**走写入口**（`goView` / `applyScope`），
/// 不自己拼字段 —— 绕过入口就会留下「主区是 B、侧栏亮着 A」。
///
/// 项目不在列表里时**改道仪表盘并说明**，与 macOS 端 `Router.resolve`
/// 的 `projectNotFound` 一致：不打开一个空详情页。
public func applyLaunchRoute(model: AppModel, route: LaunchRoute): Unit {
    if (!route.project.isEmpty()) {
        let idx = projectIndexByName(model, route.project)
        if (idx > 0) {
            applyScope(model, idx)
            return
        }
        model.routeNotice.value = "找不到项目「${route.project}」。项目列表里没有它，可能已被删除或改名。"
    }
    let si = sectionIndexOfName(route.section)
    if (si >= 0) {
        goView(model, si)
        return
    }
    if (!route.section.isEmpty()) {
        model.routeNotice.value = "不认识 --section ${route.section}（可用：dashboard / board / milestones）"
    }
}
