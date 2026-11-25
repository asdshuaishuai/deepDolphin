package deepdolphin.engine

import deepdolphin.ui.L10n
import java.io.File
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// EngineLocator.kt —— 引擎发现与探活 + 引擎子进程执行。
// 发现顺序与各端一致：MOONGIT_BIN → DEEPGIT_BIN → 仓内构建（../../moonGit）→ PATH。
// 探活：`<引擎> version`，退出码 0 即就绪。所有引擎访问都是子进程 + --json，
// 没有 HTTP、没有 FFI、没有第二份事实来源（与 macos / deepin / linux 同一口径）。
//
// 【执行纪律】
//   · stdout / stderr 各用一条泵线程读：主线程先 waitFor(超时) 再收线程。
//     原来是「readText() 阻塞到 EOF 之后才 waitFor」——引擎挂死就永不超时，busy 永不复位；
//     stderr 从不读，写满管道后引擎自己也会卡住。
//   · stderr 必须带回来：引擎把很多失败原因只写在 stderr（如「✗ 未找到项目」），stdout 是空的。
//   · 运行中的进程按命令登记；「停止更新」只终止 update/deep 两类（mac terminateRunning(onlyCommands:) 对位）。

data class EngineProbe(
    val found: Boolean,
    val path: String,
    val version: String,
)

object EngineLocator {

    fun candidates(): List<String> = buildList {
        System.getenv("MOONGIT_BIN")?.takeIf { it.isNotBlank() }?.let(::add)
        System.getenv("DEEPGIT_BIN")?.takeIf { it.isNotBlank() }?.let(::add)
        // 仓内构建（engine 仓库与客户端仓库同层时）
        File("..").absoluteFile.parentFile?.let { repoParent ->
            listOf("moonGit", "moongit").forEach { name ->
                val p = File(repoParent, "$name/target/release/bin/main").absolutePath
                if (File(p).canExecute()) add(p)
            }
        }
        add("moongit")
        add("deepgit")
    }

    private fun resolve(bin: String): File? {
        if (bin.contains('/')) {
            val f = File(bin)
            return if (f.canExecute()) f.absoluteFile else null
        }
        val pathDirs = System.getenv("PATH")?.split(':') ?: emptyList()
        for (dir in pathDirs) {
            val f = File(dir, bin)
            if (f.canExecute()) return f.absoluteFile
        }
        return null
    }

    // ── 运行中进程登记（mac stopUpdate 等价物）──

    private val running = ConcurrentHashMap<Process, String>() // 进程 → 首参数（命令）

    /** 用户每按一次「停止更新」加一；期间结束的更新进程按「已停止」而不是「失败」回报。 */
    @Volatile
    private var stopSerial = 0

    /** 主动停止的回执码（调用方据此报「已停止」，不报「引擎退出码」）。 */
    const val STOPPED_RC = -2

    /** 更新类命令（mac terminateRunning(onlyCommands: ["update", "deep"]) 同款）。 */
    fun isUpdateCommand(command: String?): Boolean = command == "update" || command == "deep"

    /** 正在跑的更新进程数（>0 才允许「停止更新」）。 */
    fun runningUpdateCount(): Int = running.values.count { isUpdateCommand(it) }

    /**
     * 终止所有在跑的更新进程：先 SIGTERM 给引擎收尾窗口（写完回执、清临时文件），
     * 宽限 2 秒仍存活再强杀。只动 update/deep，不碰其它引擎进程。返回终止的进程数。
     * （会阻塞至多 2 秒——不要在界面线程上调，AppModel.stopUpdate 已放到协程里。）
     */
    fun terminateUpdates(): Int {
        val targets = running.filterValues { isUpdateCommand(it) }.keys.toList()
        stopSerial += 1
        targets.forEach { runCatching { it.destroy() } }
        val deadline = System.currentTimeMillis() + 2_000
        for (p in targets) {
            while (System.currentTimeMillis() < deadline && p.isAlive) {
                Thread.sleep(50)
            }
            if (p.isAlive) runCatching { p.destroyForcibly() }
        }
        return targets.size
    }

    // ── 执行核心 ──

    private class Exec(val rc: Int, val out: String, val err: String, val stopped: Boolean, val timedOut: Boolean)

    private fun pump(stream: InputStream, sb: StringBuilder): Thread =
        Thread {
            // 显式 UTF-8：引擎输出是 UTF-8，非 UTF-8 locale 下不能靠平台默认字符集
            runCatching { stream.bufferedReader(Charsets.UTF_8).use { sb.append(it.readText()) } }
        }.apply { isDaemon = true; name = "moongit-pipe"; start() }

    private fun exec(bin: String, args: List<String>, timeoutSec: Long, mergeErr: Boolean, noColor: Boolean): Exec {
        val command = args.firstOrNull() ?: ""
        val proc = ProcessBuilder(listOf(bin) + args)
            .redirectErrorStream(mergeErr)
            .apply { if (noColor) environment()["NO_COLOR"] = "1" }
            .start()
        running[proc] = command
        val serial = stopSerial
        try {
            val out = StringBuilder()
            val err = StringBuilder()
            val pumps = listOfNotNull(pump(proc.inputStream, out), if (mergeErr) null else pump(proc.errorStream, err))
            val finished = proc.waitFor(timeoutSec, TimeUnit.SECONDS)
            if (!finished) {
                // 超时：强杀后立刻返回，不等泵线程——被杀进程的子进程可能还攥着管道，
                // 等它们到 EOF 会把「1 秒超时」拖成好几秒。超时的输出本来也不要。
                proc.destroyForcibly()
                return Exec(-1, "", "", stopped = false, timedOut = true)
            }
            // 引擎退出后管道即到 EOF；给泵线程最多 2 秒收尾（子进程若还攥着管道也不卡死在这里）
            pumps.forEach { it.join(2_000) }
            val stopped = isUpdateCommand(command) && stopSerial != serial
            return Exec(proc.exitValue(), out.toString(), err.toString(), stopped, timedOut = false)
        } finally {
            running.remove(proc)
        }
    }

    /**
     * 同步执行引擎命令：**只回 stdout**（stderr 照读但丢弃——为了不堵管道）。
     * ⚠️ 不能把 stderr 并进来：引擎会在 stderr 打「命令将迁移」之类的提示，
     *    并进 stdout 后 `--json` 的输出就不干净了。要失败原因用 runSplit；要合并文本用 runMerged。
     * 超时返回 (-1, 原因)。
     */
    fun run(bin: String, args: List<String>, timeoutSec: Long = 120): Pair<Int, String> {
        val e = exec(bin, args, timeoutSec, mergeErr = false, noColor = false)
        return when {
            e.stopped -> Pair(STOPPED_RC, "")
            e.timedOut -> Pair(-1, L10n.t("cmp.err.timeoutSec", timeoutSec))
            else -> Pair(e.rc, e.out)
        }
    }

    /** 文本回执命令（render 系）：stderr **并入** stdout；NO_COLOR 双保险。 */
    fun runMerged(bin: String, args: List<String>, timeoutSec: Long = 120): Pair<Int, String> {
        val e = exec(bin, args, timeoutSec, mergeErr = true, noColor = true)
        return when {
            e.stopped -> Pair(STOPPED_RC, "")
            e.timedOut -> Pair(-1, L10n.t("cmp.err.timeoutSec", timeoutSec))
            else -> Pair(e.rc, e.out)
        }
    }

    /** stdout/stderr 分流：stdout 是纯净产物（引擎 JSON 调用一律走这条），失败原因在 stderr 里单独带回。 */
    fun runSplit(bin: String, args: List<String>, timeoutSec: Long = 120): Triple<Int, String, String> {
        val e = exec(bin, args, timeoutSec, mergeErr = false, noColor = true)
        return when {
            e.stopped -> Triple(STOPPED_RC, "", "")
            e.timedOut -> Triple(-1, "", L10n.t("cmp.err.timeoutSec", timeoutSec))
            else -> Triple(e.rc, e.out, e.err)
        }
    }

    suspend fun probe(): EngineProbe = withContext(Dispatchers.IO) {
        for (bin in candidates()) {
            val resolved = resolve(bin) ?: continue
            val (rc, out) = run(resolved.absolutePath, listOf("version"), timeoutSec = 30)
            if (rc == 0) {
                return@withContext EngineProbe(true, resolved.absolutePath, out.trim().lineSequence().firstOrNull() ?: "moongit")
            }
        }
        EngineProbe(false, "", "")
    }
}
