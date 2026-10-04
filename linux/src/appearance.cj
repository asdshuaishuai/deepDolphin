// deepDolphin Linux 客户端 —— 系统外观探测。
//
// 【为什么自己写】CUI 的 `Theme` 是 `DesktopApp` 的构造参数、硬编码默认值，
// 全仓搜 `prefersDark|systemTheme|colorScheme|darkMode` 零命中 ——
// 框架**不提供**跟随系统。所以这一步只能客户端自己做。
//
// 【为什么不猜】探测顺序从「确定」到「不确定」：
//   1. 用户在本应用里显式选过（`$XDG_CONFIG_HOME/deepdolphin/settings.conf`）—— 唯一权威
//   2. `GTK_THEME` 环境变量 —— 明确写了 dark/light
//   3. 桌面自己的设置查询（GNOME / KDE / macOS）—— 要起子进程，慢一点但准
//   4. 全都没探到 → **亮色**，并且把「没探出来」这件事记下来要说出去
//
// 第 4 条是关键：静默挑一个当「跟随系统」，用户看到亮色却以为是系统就是亮色。
// 与 macOS 端同一纪律（不变量 81「不知道」与「确实没有」必须分开）。
package deepdolphin_linux

import std.env.*
import std.fs.*
import cui.{FileSystem}

/// 外观。三档而不是两档 —— 必须留「跟随系统」这一档，
/// 否则用户在系统是暗色时想强制亮色就只能去改系统设置。
public enum DsAppearance {
    | System
    | Light
    | Dark
}

public func dsAppearanceLabel(a: DsAppearance): String {
    match (a) {
        case DsAppearance.System => return "跟随系统"
        case DsAppearance.Light => return "亮色"
        case DsAppearance.Dark => return "暗色"
    }
}

public func dsAppearanceFrom(raw: String): DsAppearance {
    match (raw) {
        case "light" => return DsAppearance.Light
        case "dark" => return DsAppearance.Dark
        case _ => return DsAppearance.System
    }
}

/// 仓颉的枚举**不自动实现** `==` / `!=`（编译期直接报
/// "invalid binary operator"）。所以每个需要比较的枚举都配两个谓词，
/// 而不是在调用点写 `match` —— 后者会在每个用到的地方重复一遍。
public func appearanceIsSystem(a: DsAppearance): Bool {
    match (a) {
        case DsAppearance.System => return true
        case _ => return false
    }
}

public func appearanceIsDark(a: DsAppearance): Bool {
    match (a) {
        case DsAppearance.Dark => return true
        case _ => return false
    }
}

public func dsAppearanceKey(a: DsAppearance): String {
    match (a) {
        case DsAppearance.Light => return "light"
        case DsAppearance.Dark => return "dark"
        case DsAppearance.System => return "system"
    }
}

/// 设置文件路径。XDG 优先，缺失时退回 `~/.config`。
public func settingsPath(): String {
    let xdg = getVariable("XDG_CONFIG_HOME") ?? ""
    let base = (if (xdg.isEmpty()) { homeConfigFallback() } else { xdg })
    return "${base}/deepdolphin/settings.conf"
}

private func homeConfigFallback(): String {
    let home = getVariable("HOME") ?? ""
    return (if (home.isEmpty()) { ".config" } else { "${home}/.config" })
}

/// 读文件内容；读不到返回空串。
///
/// 读不到**不等于**文件里没有那一行 —— 但对外一律表现为「没设置过」，
/// 因为对「用户想设成什么」这个问题，两者给出的答复是一样的（都是没设过），
/// 区别只在排查时才需要，而排查有日志可看。
private func readTextFile(path: String): String {
    let p = Path(path)
    if (!exists(p)) {
        return ""
    }
    try {
        return String.fromUtf8(File.readFrom(p))
    } catch (e: Exception) {
        return ""
    }
}

private func writeTextFile(path: String, content: String): Bool {
    let p = Path(path)
    try {
        let d = p.parent
        if (!d.toString().isEmpty() && !exists(d)) {
            FileSystem.createDirectory(d.toString())
        }
        File.writeTo(p, content.toArray())
        return true
    } catch (e: Exception) {
        return false
    }
}

/// ASCII 小写。仓颉 `String` 上没有公开的 `toLower`，
/// 而这里要小写的全是 `dark` / `light` / `prefer-dark` 这几个 ASCII 关键字。
///
/// **在字节层做，不碰 Rune**：UTF-8 的多字节序列每个字节都 >= 0x80，
/// 与 ASCII 大写区间 [0x41,0x5A] 不相交，所以只折这段不会破坏任何 UTF-8 序列。
/// 走 Rune 反而要多一层 Unicode 大小写折叠的语义要解释。
public func asciiLower(s: String): String {
    let out = s.toArray()
    for (i in 0..out.size) {
        if (out[i] >= 0x41u8 && out[i] <= 0x5Au8) {
            out[i] = out[i] + 0x20u8
        }
    }
    return String.fromUtf8(out)
}

/// 读用户显式选择。**纯函数**（收路径、收读函数）——
/// 判据要能在不碰真实文件系统、不碰真实 HOME 的前提下测它。
public func readAppearanceFrom(text: String): DsAppearance {
    for (raw in text.split("\n")) {
        let line = raw.toString().trimAscii()
        if (line.startsWith("appearance=")) {
            return dsAppearanceFrom(line[11..])
        }
    }
    return DsAppearance.System
}

public func readSavedAppearance(): DsAppearance {
    return readAppearanceFrom(readTextFile(settingsPath()))
}

/// 探测系统偏好。**只在用户选了「跟随系统」时才跑** —— 显式选了就不该再问系统。
///
/// 返回 `Option<Bool>`：`None` = 探测不出来（**不是**「探测到亮色」）。
public func detectSystemDark(): Option<Bool> {
    // 1. GTK_THEME：写明 dark/light 的最省事一条
    let gtk = asciiLower(getVariable("GTK_THEME") ?? "")
    if (gtk.contains("dark")) {
        return Some(true)
    }
    if (gtk.contains("light")) {
        return Some(false)
    }

    // 2. 桌面自己的查询。挨个试，第一个给出明确答案的就用。
    if (probe(["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"], "prefer-dark", "dark")) {
        return Some(true)
    }
    if (probe(["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"], "default", "light")) {
        return Some(false)
    }
    if (probe(["kreadconfig5", "--file", "kdeglobals", "--group", "General", "--key", "colorScheme"],
        "dark", "dark")) {
        return Some(true)
    }
    if (probe(["kreadconfig5", "--file", "kdeglobals", "--group", "General", "--key", "colorScheme"],
        "breeze-light", "light")) {
        return Some(false)
    }

    // 3. macOS。`AppleInterfaceStyle` **不存在就是亮色** ——
    // 这是唯一一个「查不到」有确定含义的地方，所以单独处理。
    let r = execCapture("defaults", ["read", "-g", "AppleInterfaceStyle"], 3000)
    if (r.exitCode == 0) {
        return Some(asciiLower(r.stdout).contains("dark"))
    }
    if (!r.timedOut && asciiLower(r.stderr).contains("does not exist")) {
        return Some(false)
    }
    return None
}

/// 跑一条查询命令，stdout 含 `hit` 判暗、含 `miss` 判亮；都不是就当没探到。
private func probe(argv: Array<String>, hit: String, miss: String): Bool {
    if (argv.isEmpty()) {
        return false
    }
    let r = execCapture(argv[0], argv[1..], 3000)
    if (r.exitCode != 0 || r.timedOut) {
        return false
    }
    let out = asciiLower(r.stdout)
    return (if (out.contains(hit)) { true } else { out.contains(miss) })
}

/// 实际用哪套色板。**纯函数**，收探测结果 —— 判据直接喂组合法的。
///
/// 探测失败退亮色：亮色在两种桌面环境下都不会「看不清」，
/// 而暗色在亮环境下对比度更难受。宁可选保守的那个，
/// 同时把 `failed` 传出去让界面说一句「没探到系统外观」。
public func resolveDarkFrom(saved: DsAppearance, probed: Option<Bool>): Bool {
    if (!appearanceIsSystem(saved)) {
        return appearanceIsDark(saved)
    }
    return (match (probed) {
        case Some(isDark) => isDark
        case None => false
    })
}

/// 这次是不是「用户选了跟随系统、但系统没给出答案」。
public func appearanceProbeFailed(saved: DsAppearance, probed: Option<Bool>): Bool {
    return appearanceIsSystem(saved) && probed.isNone()
}

/// 一次性解析：读设置 → 必要时才探测 → 出色板与披露标记。
public func resolveAppearance(): (Bool, Bool) {
    let saved = readSavedAppearance()
    if (!appearanceIsSystem(saved)) {
        return (appearanceIsDark(saved), false)
    }
    let probed = detectSystemDark()
    return (resolveDarkFrom(saved, probed), appearanceProbeFailed(saved, probed))
}

/// 保存用户显式选择。**返回一句失败原因**（成功时是空串）。
///
/// 写不进去必须说出来：设置没存上，下次启动又跳回「跟随系统」，
/// 用户会以为这按钮是坏的。
public func saveAppearance(a: DsAppearance): String {
    if (writeTextFile(settingsPath(), "appearance=${dsAppearanceKey(a)}\n")) {
        return ""
    }
    return "外观设置没能写入 ${settingsPath()}"
}
