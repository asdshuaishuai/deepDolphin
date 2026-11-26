// LegacyPathsTest.kt —— 品牌升级（deepDolphin → Canopy）后的本机迁移判据：
// 目录搬得动就整目录搬、内容一个字节不动；新旧都在用新的且不删旧的；搬不动继续用旧的（设置不丢）；
// 自启旧条目换成指向当前客户端的新条目，入口不可用时不动它。
package canopy.sysint

import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LegacyPathsTest {
    private fun tempParent(): File = Files.createTempDirectory("canopy-mig").toFile()

    @Test
    fun legacyDirIsRenamedWhenNewIsAbsent() {
        val parent = tempParent()
        try {
            val legacy = File(parent, "deepDolphin").apply { mkdir() }
            File(legacy, "settings.conf").writeText("app.skin=glass\napp.language=ja\n")
            File(legacy, "ai.key").writeText("k")
            val dir = migratedDir(parent, "canopy")
            assertEquals(File(parent, "canopy"), dir)
            assertEquals("app.skin=glass\napp.language=ja\n", File(dir, "settings.conf").readText())
            assertEquals("k", File(dir, "ai.key").readText())
            assertFalse(legacy.exists(), "搬走后旧目录不该还在")
        } finally {
            parent.deleteRecursively()
        }
    }

    @Test
    fun existingNewDirWinsAndLegacyIsLeftAlone() {
        val parent = tempParent()
        try {
            File(parent, "canopy").apply { mkdir() }.resolve("settings.conf").writeText("new\n")
            File(parent, "deepDolphin").apply { mkdir() }.resolve("settings.conf").writeText("old\n")
            val dir = migratedDir(parent, "canopy")
            assertEquals(File(parent, "canopy"), dir)
            assertEquals("new\n", File(dir, "settings.conf").readText())
            assertEquals("old\n", File(parent, "deepDolphin/settings.conf").readText())
            assertTrue(File(parent, "deepDolphin").exists(), "不删用户的东西")
        } finally {
            parent.deleteRecursively()
        }
    }

    @Test
    fun neitherExistsReturnsTheNewPath() {
        val parent = tempParent()
        try {
            assertEquals(File(parent, "canopy"), migratedDir(parent, "canopy"))
        } finally {
            parent.deleteRecursively()
        }
    }

    @Test
    fun unmovableLegacyDirFallsBackToItself() {
        val parent = tempParent()
        try {
            File(parent, "deepDolphin").apply { mkdir() }.resolve("settings.conf").writeText("keep\n")
            assertTrue(parent.setWritable(false), "测试前提：父目录设为不可写")
            val dir = migratedDir(parent, "canopy")
            assertEquals(File(parent, "deepDolphin"), dir, "搬不动就继续用旧目录")
            assertEquals("keep\n", File(dir, "settings.conf").readText())
        } finally {
            parent.setWritable(true)
            parent.deleteRecursively()
        }
    }

    @Test
    fun legacyAutostartEntryIsReplacedByTheCurrentOne() {
        val parent = tempParent()
        try {
            File(parent, "deepdolphin.desktop").writeText("[Desktop Entry]\nExec=/opt/deepdolphin/bin/deepdolphin\n")
            val r = migrateLegacyAutostart(parent, "/opt/canopy/bin/canopy")
            assertEquals(AutostartMigration.Migrated, r)
            val cur = File(parent, "canopy.desktop")
            assertTrue(cur.isFile)
            assertTrue(cur.readText().contains("Exec=\"/opt/canopy/bin/canopy\""))
            assertTrue(cur.readText().contains("Name=Canopy"))
            assertFalse(File(parent, "deepdolphin.desktop").exists(), "旧条目不清掉会双自启")
        } finally {
            parent.deleteRecursively()
        }
    }

    @Test
    fun togglingAutostartRemovesTheLegacyEntryToo() {
        val parent = tempParent()
        try {
            File(parent, "deepdolphin.desktop").writeText("[Desktop Entry]\n")
            assertEquals(null, SysInt.setAutostart(parent, "/opt/canopy/bin/canopy", false))
            assertFalse(File(parent, "deepdolphin.desktop").exists())
        } finally {
            parent.deleteRecursively()
        }
    }

    @Test
    fun legacyAutostartWithoutClientEntryIsLeftAlone() {
        val parent = tempParent()
        try {
            File(parent, "deepdolphin.desktop").writeText("[Desktop Entry]\n")
            assertEquals(AutostartMigration.Skipped, migrateLegacyAutostart(parent, null))
            assertTrue(File(parent, "deepdolphin.desktop").isFile, "开发态不动用户的开机自启")
            assertFalse(File(parent, "canopy.desktop").exists())
        } finally {
            parent.deleteRecursively()
        }
    }

    @Test
    fun noLegacyEntryReportsNotNeeded() {
        val parent = tempParent()
        try {
            assertEquals(AutostartMigration.NotNeeded, migrateLegacyAutostart(parent, "/opt/canopy/bin/canopy"))
            assertFalse(File(parent, "canopy.desktop").exists(), "没有旧条目就不该凭空写出新条目")
        } finally {
            parent.deleteRecursively()
        }
    }
}
