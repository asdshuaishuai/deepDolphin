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

import std.collection.*
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

/// 两个外观档是否相同。理由同 `tokens.cj` 的 `dsStatusIs`：
/// 枚举不自动实现 `==`，判据要比较档位（例如「下标往返后还是同一档」）
/// 就用这个谓词，不在调用点各写一遍 `match`。
public func appearanceIs(a: DsAppearance, b: DsAppearance): Bool {
    match (a) {
        case DsAppearance.System => return match (b) { case DsAppearance.System => true; case _ => false }
        case DsAppearance.Light => return match (b) { case DsAppearance.Light => true; case _ => false }
        case DsAppearance.Dark => return match (b) { case DsAppearance.Dark => true; case _ => false }
    }
}

public func dsAppearanceKey(a: DsAppearance): String {
    match (a) {
        case DsAppearance.Light => return "light"
        case DsAppearance.Dark => return "dark"
        case DsAppearance.System => return "system"
    }
}

// ---------------------------------------------------------------------------
// 设置页的外观下拉 —— 档位 ↔ 下标 ↔ 结果文案
// ---------------------------------------------------------------------------

/// 档位 → 下拉下标。CUI 的 `Dropdown` 只收 `State<Int64>` 下标，
/// 映射必须可逆且可测 —— 顺序即「从自动到手动」：跟随系统 / 亮 / 暗。
public func appearanceIndex(a: DsAppearance): Int64 {
    match (a) {
        case DsAppearance.System => return 0
        case DsAppearance.Light => return 1
        case DsAppearance.Dark => return 2
    }
}

/// 下拉下标 → 档位。**越界一律回落「跟随系统」** —— 与 `dsAppearanceFrom`
/// 对不认识的字符串的处理一致：不知道就回到自动档，不猜。
public func appearanceAt(i: Int64): DsAppearance {
    match (i) {
        case 1 => return DsAppearance.Light
        case 2 => return DsAppearance.Dark
        case _ => return DsAppearance.System
    }
}

/// 外观下拉的选项。顺序与 `appearanceIndex` / `appearanceAt` 对齐。
public func appearanceChoices(): Array<String> {
    return [
        dsAppearanceLabel(DsAppearance.System),
        dsAppearanceLabel(DsAppearance.Light),
        dsAppearanceLabel(DsAppearance.Dark)
    ]
}

/// 应用一次外观选择的结果文案 + 成败。**纯函数** —— 判据喂「写入是否成功」。
///
/// 成功也要说「重启后生效」：CUI 的 `Theme` 是 `DesktopApp` 的构造参数
/// （vendor `src/core/theme.cj` 标注 Immutable，`DesktopApp` 没有 setTheme），
/// 换档只落盘，本进程的界面不会跟着变。不写这句，用户点了「暗色」
/// 看着界面没变，会以为按钮是坏的。
public func appearanceApplyNote(a: DsAppearance, writeProblem: String): (String, Bool) {
    if (writeProblem.isEmpty()) {
        return ("已保存为「${dsAppearanceLabel(a)}」—— 主题在启动时定型，重启客户端后生效。", true)
    }
    return (writeProblem, false)
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
    // ⚠ 探测超时 1500ms（R4-10）：这条链在建窗之前跑（Theme 是构造参数），
    // 每个挂住的探测都直接挡住首屏；正常应答在几十毫秒内，
    // 1.5 秒足够区分「答了」与「挂了」。
    let r = execCapture("defaults", ["read", "-g", "AppleInterfaceStyle"], 1500)
    if (r.exitCode == 0) {
        return Some(asciiLower(r.stdout).contains("dark"))
    }
    if (!r.timedOut && asciiLower(r.stderr).contains("does not exist")) {
        return Some(false)
    }
    return None
}

/// 跑一条查询命令，stdout 含 `hit` 判暗、含 `miss` 判亮；都不是就当没探到。
/// 超时 1500ms（R4-10）：这条链在建窗之前跑，探测挂住就是在挡首屏。
private func probe(argv: Array<String>, hit: String, miss: String): Bool {
    if (argv.isEmpty()) {
        return false
    }
    let r = execCapture(argv[0], argv[1..], 1500)
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
///
/// ⚠ **合并写而不是整文件覆写**（confWithKey）：settings.conf 里现在不止
/// appearance 一个键（C5 的定时更新档 `schedule=` 也在这里）——
/// 谁整文件重写，谁就会把别人刚存的那一行抹掉，而且是在用户保存一个
/// 完全无关的设置时发生的（「改个外观，定时更新被悄悄关掉」）。
public func saveAppearance(a: DsAppearance): String {
    let merged = confWithKey(readTextFile(settingsPath()), "appearance", dsAppearanceKey(a))
    if (writeTextFile(settingsPath(), merged)) {
        return ""
    }
    return "外观设置没能写入 ${settingsPath()}"
}

// ---------------------------------------------------------------------------
// 定时更新档（C5）—— settings.conf 的 `schedule=<小时数>`，0 = 关。
//
// 与外观共用同一个 conf 文件，所以写入必须走 confWithKey 的**合并写**；
// 档位表与解析全部收成纯函数 —— 判据不碰真实 HOME 就能验「非法值回落关」。
// ---------------------------------------------------------------------------

/// 定时更新支持的档位（小时）。与 mac 端 ScheduleMenu 同一组：
/// 0=关 / 1 / 3 / 6 / 12 / 24。
public func scheduleTiers(): Array<Int64> {
    return [0, 1, 3, 6, 12, 24]
}

/// 档位 → 下拉下标。表里没有的值（含越界）回落 0 = 关。
public func scheduleIndexOf(hours: Int64): Int64 {
    let tiers = scheduleTiers()
    for (i in 0..tiers.size) {
        if (tiers[i] == hours) {
            return i
        }
    }
    return 0
}

/// 下拉下标 → 档位。**越界一律回落「关」** —— 与 `appearanceAt`
/// 对不认识的值同一条纪律：不知道就回到关，不猜。
public func scheduleHoursAt(index: Int64): Int64 {
    let tiers = scheduleTiers()
    if (index < 0 || index >= tiers.size) {
        return 0
    }
    return tiers[index]
}

/// 下拉的选项文案。顺序与 `scheduleIndexOf` / `scheduleHoursAt` 对齐
/// （词表与 mac 端 ScheduleMenu 同款）。
public func scheduleChoices(): Array<String> {
    return ["关闭", "每 1 小时", "每 3 小时", "每 6 小时", "每 12 小时", "每 24 小时"]
}

/// conf 的单个值 → 档位。**非法一律 0 = 关**：非数字、负数、小数、带单位、
/// 超长（>3 位，档位表最大 24）都不认；表外的「看起来合法」值（2/5/999…）
/// 也不认 —— 定时更新会在后台改写用户仓库的托管文档，替用户猜一个
/// 他没选过的周期，比不开更危险。
public func scheduleHoursFromConf(raw: String): Int64 {
    let s = raw.trimAscii()
    let b = s.toArray()
    if (b.size < 1 || b.size > 3) {
        return 0
    }
    for (x in b) {
        if (x < 0x30u8 || x > 0x39u8) {
            return 0
        }
    }
    var v: Int64 = 0
    for (x in b) {
        v = v * 10 + Int64(x - 0x30u8)
    }
    // 下标往返一遍：在表里 → 原值；不在表里 → 0（关）。
    return scheduleHoursAt(scheduleIndexOf(v))
}

/// 整份 conf 文本 → 档位。找 `schedule=` 那一行；没有该行 = 从没设置过 = 关
/// （与 `readAppearanceFrom` 同一条读法，`schedule=` 长 9 字节）。
public func readScheduleHoursFrom(text: String): Int64 {
    for (raw in text.split("\n")) {
        let line = raw.toString().trimAscii()
        if (line.startsWith("schedule=")) {
            return scheduleHoursFromConf(line[9..])
        }
    }
    return 0
}

public func readSavedScheduleHours(): Int64 {
    return readScheduleHoursFrom(readTextFile(settingsPath()))
}

/// 把 conf 文本里 `key=` 那一行换成新值；没有就追加。**其余行原样保留**。
/// **纯函数** —— 「外观保存不许抹掉定时档」这类合并性质，判据直接喂文本。
///
/// 末尾空行不累积：原文件带不带收尾换行，反复保存后都收敛成
/// 「一行一个换行」，不会越存越长。
public func confWithKey(text: String, key: String, value: String): String {
    let prefix = "${key}="
    let lines = ArrayList<String>()
    var found = false
    for (raw in text.split("\n")) {
        let line = raw.toString()
        if (line.trimAscii().startsWith(prefix)) {
            lines.add("${prefix}${value}")
            found = true
        } else {
            lines.add(line)
        }
    }
    // 先收掉末尾空行（原文件带不带收尾换行都收敛成一行一个换行），
    // **再**追加缺失的键 —— 不然新键会插在收尾空行之后，文件里留出一个空档。
    while (!lines.isEmpty() && lines[lines.size - 1].isEmpty()) {
        lines.remove(at: lines.size - 1)
    }
    if (!found) {
        lines.add("${prefix}${value}")
    }
    let out = StringBuilder()
    for (l in lines) {
        out.append("${l}\n")
    }
    return out.toString()
}

/// 保存定时档。**返回一句失败原因**（成功时是空串），与 saveAppearance 同一条纪律。
public func saveScheduleHours(hours: Int64): String {
    let merged = confWithKey(readTextFile(settingsPath()), "schedule", "${hours}")
    if (writeTextFile(settingsPath(), merged)) {
        return ""
    }
    return "定时更新设置没能写入 ${settingsPath()}"
}
