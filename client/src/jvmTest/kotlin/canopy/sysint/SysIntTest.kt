// SysIntTest.kt —— C10 判据：Exec 转义 / 自启写盘沙盒 / 深链解析（纯函数 + /tmp 沙盒）。

package canopy.sysint

import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertNotNull

class SysIntTest {

    @Test
    fun execEscapingIsDesktopSpec() {
        assertEquals("\"/opt/canopy/bin/canopy\"", SysInt.escapeDesktopExec("/opt/canopy/bin/canopy"))
        assertEquals("\"/opt/my app/canopy\"", SysInt.escapeDesktopExec("/opt/my app/canopy"))
        // 引号/反斜杠/反引号/$ 都要转义（desktop Exec 注入面）
        assertTrue(SysInt.escapeDesktopExec("/a\"b").contains("\\\""))
        assertTrue(SysInt.escapeDesktopExec("/a\$b").contains("\\$"))
        assertTrue(SysInt.escapeDesktopExec("/a`b").contains("\\`"))
    }

    @Test
    fun autostartEntryRequiresAbsoluteExecutable() {
        // run.sh 相对路径教训：argv[0] 非 / 开头 → 拒绝（null）
        assertNull(SysInt.autostartClientEntry("./target/release/bin/main"))
        assertNull(SysInt.autostartClientEntry("/not/exist/binary"))
        val tmp = Files.createTempFile("dd-client", ".bin").toFile().apply { setExecutable(true) }
        assertNotNull(SysInt.autostartClientEntry(tmp.absolutePath))
        tmp.delete()
    }

    @Test
    fun autostartWriteAndRemoveInSandbox() {
        val sandbox = Files.createTempDirectory("dd-autostart-test").toFile()
        val entry = SysInt.autostartClientEntry("/bin/true")!!
        // 开启
        val err1 = SysInt.setAutostart(sandbox, entry, enabled = true)
        assertNull(err1)
        val f = java.io.File(sandbox, "canopy.desktop")
        assertTrue(f.isFile)
        val content = f.readText()
        assertTrue(content.contains("[Desktop Entry]"))
        assertTrue(content.contains("Exec=\""))
        assertFalse(content.contains("OnlyShowIn"), "Linux 通用端不写 OnlyShowIn")
        // 关闭
        val err2 = SysInt.setAutostart(sandbox, entry, enabled = false)
        assertNull(err2)
        assertFalse(f.exists())
        sandbox.deleteRecursively()
    }

    @Test
    fun deepLinkParsesSectionAndProject() {
        val d1 = SysInt.parseDeepLink(listOf("--section", "board"))
        assertTrue(d1.valid); assertEquals("board", d1.section)
        val d2 = SysInt.parseDeepLink(listOf("--project", "atlas"))
        assertTrue(d2.valid); assertEquals("atlas", d2.project)
        // 非法 section 落 dashboard（宽容）
        val d3 = SysInt.parseDeepLink(listOf("--section", "nope"))
        assertEquals(null, d3.section)
        // 无参 = 无深链
        assertFalse(SysInt.parseDeepLink(emptyList()).valid)
    }

    @Test
    fun notifyAvailableProbeDoesNotThrow() {
        // 真实探测（本机 notify-send 缺席 → false；装了 → true）：只验证不抛
        SysInt.notifyAvailable()
    }
}
