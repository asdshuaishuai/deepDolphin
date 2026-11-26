// EngineExecTest.kt —— 引擎子进程执行纪律判据（用 /bin/sh 当假引擎，不依赖 cambium）。
//
// 二次验证抓到：原实现「阻塞读完 stdout 才检查超时」——引擎挂死永不超时、busy 永不复位；
// stderr 从不读——失败原因（引擎只写在 stderr）全丢，界面上只剩「退出码 1：无输出」。

package canopy.engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class EngineExecTest {

    private val sh = java.io.File("/bin/sh")

    /** 没有 /bin/sh（非 POSIX 环境）就跳过并说明。 */
    private fun shell(): String? {
        if (!sh.canExecute()) println("SKIP EngineExecTest：本机没有 /bin/sh")
        return sh.absolutePath.takeIf { sh.canExecute() }
    }

    @Test
    fun stderrIsCapturedSeparately() {
        val shell = shell() ?: return
        val (rc, out, err) = EngineLocator.runSplit(shell, listOf("-c", "echo out; echo '✗ 未找到项目' 1>&2; exit 3"), 20)
        assertEquals(3, rc)
        assertEquals("out\n", out)
        assertEquals("✗ 未找到项目\n", err, "引擎写在 stderr 的原因必须带回来")
    }

    @Test
    fun timeoutActuallyFires() {
        val t0 = System.currentTimeMillis()
        val shell = shell() ?: return
        val (rc, out) = EngineLocator.run(shell, listOf("-c", "sleep 6; echo late"), 1)
        val elapsed = System.currentTimeMillis() - t0
        assertEquals(-1, rc)
        assertTrue(out.contains("超时"), "超时回执要写明原因，实际：$out")
        assertTrue(elapsed in 900..4_000, "1 秒超时应在 1–4 秒内返回，实际 ${elapsed}ms")
    }

    @Test
    fun hugeStderrDoesNotDeadlock() {
        // stderr 写满管道缓冲（64KB）而没人读，引擎自己会卡住——泵线程必须一直在排空
        val shell = shell() ?: return
        val (rc, out, err) = EngineLocator.runSplit(
            shell, listOf("-c", "head -c 300000 /dev/zero | tr '\\0' x 1>&2; echo done"), 30,
        )
        assertEquals(0, rc)
        assertEquals("done\n", out)
        assertEquals(300_000, err.length)
    }

    @Test
    fun engineFailureMessageComesFromErrorEnvelope() {
        // 真机落盘：`milestone done vtest2 no-such-milestone --json`（exit 1）
        val raw = java.io.File("src/jvmTest/resources/fixtures/milestone_not_found.json").readText()
        assertEquals("未找到里程碑：no-such-milestone", Engine("cambium").engineMessageOf(raw))
        assertEquals(null, Engine("cambium").engineMessageOf("""{"project":"vtest2","created":true}"""), "成功回执里没有 message")
        assertEquals(null, Engine("cambium").engineMessageOf("not json at all"))
    }

    @Test
    fun runKeepsStdoutClean() {
        // 引擎会在 stderr 打「命令将迁移」提示：run() 的 stdout 必须干净，否则 --json 输出解不了
        val shell = shell() ?: return
        val (rc, out) = EngineLocator.run(shell, listOf("-c", "echo '{\"ok\":true}'; echo '提示：命令将迁移' 1>&2"), 20)
        assertEquals(0, rc)
        assertEquals("{\"ok\":true}\n", out)
        // 要合并文本的调用方才用 runMerged
        assertEquals("{\"ok\":true}\n提示：命令将迁移\n", EngineLocator.runMerged(shell, listOf("-c", "echo '{\"ok\":true}'; echo '提示：命令将迁移' 1>&2"), 20).second)
    }
}

