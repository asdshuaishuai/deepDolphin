package deepdolphin.engine

import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

// EngineLocator.kt —— C1 引擎发现与探活。
// 发现顺序与各端一致：MOONGIT_BIN → DEEPGIT_BIN → 仓内构建（../../moonGit）→ PATH。
// 探活：`<引擎> version`，退出码 0 即就绪。所有引擎访问都是子进程 + --json，
// 没有 HTTP、没有 FFI、没有第二份事实来源（与 macos / deepin / linux / archive-bui 同一口径）。

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

    /** 同步执行引擎命令（阻塞；UI 侧一律在协程 IO 调度器里调用）。 */
    fun run(bin: String, args: List<String>, timeoutSec: Long = 120): Pair<Int, String> {
        val proc = ProcessBuilder(listOf(bin) + args)
            .redirectErrorStream(false)
            .start()
        val out = proc.inputStream.bufferedReader().readText()
        val finished = proc.waitFor(timeoutSec, TimeUnit.SECONDS)
        if (!finished) {
            proc.destroyForcibly()
            return Pair(-1, "超时（${timeoutSec}s）")
        }
        return Pair(proc.exitValue(), out)
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
