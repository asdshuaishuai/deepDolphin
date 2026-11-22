// SysInt.kt —— C10 系统集成（Linux 通用端：freedesktop 机制，无 DDE 专属）。
//
// 通知：notify-send（缺席时如实降级，不静默）；自启：XDG autostart + Exec 绝对
// 路径整参数引号转义（run.sh 相对路径教训）；深链：--section/--project。

package deepdolphin.sysint

import java.io.File

object SysInt {

    // ── 通知 ──
    fun notify(title: String, body: String): Boolean = try {
        val proc = ProcessBuilder(
            listOf("notify-send", "--app-name=deepDolphin", title, body)
        ).start()
        proc.waitFor() == 0
    } catch (_: Exception) {
        false // notify-send 缺席：如实返回 false，调用方决定是否在界面提示
    }

    fun notifyAvailable(): Boolean = runCatching {
        ProcessBuilder(listOf("which", "notify-send")).start().waitFor() == 0
    }.getOrDefault(false)

    // ── XDG 自启（纯函数可测；写盘与判据分离）──

    /** Exec 值的 desktop 规范转义：双引号包裹 + 引号/反斜杠/反引号/$ 转义。 */
    fun escapeDesktopExec(exec: String): String =
        "\"" + exec.replace("\\", "\\\\").replace("\"", "\\\"")
            .replace("`", "\\`").replace("$", "\\$") + "\""

    /** 自启条目的 Exec：argv[0] 必须是真实存在的客户端入口绝对路径。 */
    fun autostartClientEntry(argv0: String): String? {
        if (!argv0.startsWith("/")) return null // 相对路径：run.sh 教训——Exec 会以错误的 cwd 语义解析
        val f = File(argv0)
        return if (f.canExecute()) f.absolutePath else null
    }

    /** 自启 .desktop 的内容（纯函数；X-Generic 不写 OnlyShowIn——Linux 通用端）。 */
    fun autostartDesktop(execPath: String): String = buildString {
        appendLine("[Desktop Entry]")
        appendLine("Type=Application")
        appendLine("Name=deepDolphin")
        appendLine("GenericName=项目群进度引擎")
        appendLine("Exec=" + escapeDesktopExec("$execPath"))
        appendLine("Icon=deepdolphin")
        appendLine("Terminal=false")
        appendLine("X-GNOME-Autostart-enabled=true")
        appendLine("X-GNOME-Autostart-phase=Applications")
        appendLine("StartupNotify=false")
        appendLine("Categories=Development;")
    }

    /** 自启目录（$XDG_CONFIG_HOME/autostart；env 缺省 ~/.config）。 */
    fun autostartDir(xdgConfigHome: String? = System.getenv("XDG_CONFIG_HOME"), home: String = System.getProperty("user.home")): File =
        File(xdgConfigHome?.takeIf { it.isNotBlank() } ?: "$home/.config", "autostart")

    /** 开启自启：写 XDG autostart。返回错误或 null。 */
    fun setAutostart(dir: File, clientEntry: String, enabled: Boolean): String? {
        if (!clientEntry.startsWith("/")) return "客户端入口不是绝对路径：$clientEntry"
        val target = File(dir, "deepdolphin.desktop")
        return if (enabled) {
            try {
                dir.mkdirs()
                target.writeText(autostartDesktop(clientEntry))
                null
            } catch (e: Exception) {
                "写自启失败：${e.message}"
            }
        } else {
            if (target.isFile && !target.delete()) "移除自启失败" else null
        }
    }

    // ── 深链（C10）：--section / --project 解析（与 mac/BUI 同语义）──
    data class DeepLink(val section: String?, val project: String?) {
        val valid: Boolean get() = section != null || project != null
    }

    /** 解析启动参数；未知参数忽略（宽容启动，不因多余参数拒绝）。 */
    fun parseDeepLink(args: List<String>): DeepLink {
        var section: String? = null
        var project: String? = null
        var i = 0
        while (i < args.size) {
            when (args[i]) {
                "--section" -> { section = args.getOrNull(i + 1); i += 2 }
                "--project" -> { project = args.getOrNull(i + 1); i += 2 }
                else -> i += 1
            }
        }
        // 非法 section 落 dashboard（与 mac/BUI 一致：宽容，不崩）
        if (section != null && section !in setOf("dashboard", "board", "milestones")) section = null
        return DeepLink(section, project)
    }
}
