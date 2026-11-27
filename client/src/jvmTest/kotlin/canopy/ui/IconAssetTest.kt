// IconAssetTest.kt —— 窗口图标的判据。
//
// 图标链路是：assets/icon/mark.svg（母版）→ make-icons.py → assets/icon/out/（全平台唯一的一套）→
// 构建时并进客户端资源 icon/canopy.png → Window(icon = …)。
// 少掉任何一节的症状都要开真窗口才看得到（任务栏上是 Compose 自带的 Kotlin 图标，或者应用菜单里是
// 打包器的默认图）。这里把它前移到单测：资源在、和 out/ 里那份逐字节相同、画的确实是「森林谱系」，
// 并且资源目录里没有偷偷留第二份拷贝（第二份迟早和母版分家）。
package canopy.ui

import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class IconAssetTest {
    /** 从测试的工作目录往上找仓库根（Gradle 把工作目录设在 client/；根的标志是有 assets/icon/out）。 */
    private fun repoRoot(): File {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            if (File(dir, "assets/icon/out").isDirectory) return dir
            dir = dir.parentFile
        }
        error("从 ${System.getProperty("user.dir")} 往上找不到带 assets/icon/out 的仓库根")
    }

    private fun iconResource() = IconAssetTest::class.java.getResourceAsStream("/icon/canopy.png")

    private fun argb(img: BufferedImage, x: Int, y: Int): Long = img.getRGB(x, y).toLong() and 0xFFFFFFFFL

    private fun rgb(pixel: Long) = Triple(((pixel shr 16) and 0xFF).toInt(), ((pixel shr 8) and 0xFF).toInt(), (pixel and 0xFF).toInt())

    @Test
    fun windowIconResourceIsTheSharedAsset() {
        val bytes = iconResource()?.use { it.readBytes() }
        assertTrue(bytes != null && bytes.isNotEmpty(), "资源里没有 /icon/canopy.png：build.gradle.kts 的 jvmProcessResources 没把它并进来")
        // 逐字节相同 = 客户端没有自己的另一份；图标要换只能换母版再重导
        val shared = File(repoRoot(), "assets/icon/out/png/256.png").readBytes()
        assertTrue(shared.contentEquals(bytes), "资源里的图标与 assets/icon/out/png/256.png 不是同一份字节")
    }

    @Test
    fun windowIconIsTheForestLineageMark() {
        val img = iconResource()?.use { ImageIO.read(it) } ?: error("读不出 /icon/canopy.png")
        assertEquals(256, img.width)
        assertEquals(256, img.height)
        // 满幅圆角方底：四角透明，四条边的中点不透明（母版不许留透明边距，边距由导出按平台加）
        for ((x, y) in listOf(2 to 2, 253 to 2, 2 to 253, 253 to 253)) {
            assertEquals(0L, argb(img, x, y) ushr 24, "($x, $y) 应是圆角外的透明像素")
        }
        for ((x, y) in listOf(128 to 1, 128 to 254, 1 to 128, 254 to 128)) {
            assertEquals(255L, argb(img, x, y) ushr 24, "($x, $y) 应在方底边上、不透明")
        }
        // 方底是森林绿（不是旧品牌的深蓝，也不是 Compose / Kotlin 的橙紫）：取左侧远离图形的一点
        val (r, g, b) = rgb(argb(img, 22, 128))
        assertTrue(g > r + 40 && g > b + 20, "方底应是绿色为主，实际 rgb($r, $g, $b)")
        // 顶冠：母版里 (512, 300) 是顶冠的圆心，缩到 256 即 (128, 75)——很亮的薄荷色
        val (cr, cg, cb) = rgb(argb(img, 128, 75))
        assertTrue(cr > 170 && cg > 230 && cb > 190, "顶冠应是亮薄荷色（高光偏左上，圆心不是最亮处），实际 rgb($cr, $cg, $cb)")
    }

    @Test
    fun resourcesCarryNoSecondCopyOfTheIcon() {
        val res = File(repoRoot(), "client/src/jvmMain/resources")
        assertTrue(res.isDirectory, "资源目录 $res 不存在")
        val copies = res.walkTopDown()
            .filter { it.isFile && (it.extension.lowercase() in setOf("ico", "icns") || it.name.equals("canopy.png", ignoreCase = true)) }
            .map { it.relativeTo(res).path }
            .toList()
        assertTrue(copies.isEmpty(), "资源目录里不许放图标拷贝（唯一一套在 assets/icon/out/）：$copies")
    }
}
