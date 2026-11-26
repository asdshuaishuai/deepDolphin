// SkinContrastAudit.kt —— 逐皮肤「文字 × 表面」对比度体检（离屏渲染，不建窗口）。
//
// 【为什么要有它】14 套皮肤里，浅色皮肤沿用了为深色皮肤挑的粉彩色：强调色当文字、白色当前景压在
// 粉彩按钮上、次级文字太淡——用户在 Aqua 上实拍到标题与按钮文字读不出来。令牌层面能算矩阵
// （SkinTest），但「哪段文字画在什么表面」只有真渲染才说得清：文字可能落在渐变卡、半透明浮层、
// 背景材质上。这里把每套皮肤的各页面离屏画成位图，按语义树取每段文字的位置，量**实际像素**。
//
// 【怎么跑】需要能画字（有 DISPLAY、非 headless）的开发机：
//   CANOPY_SKIN_AUDIT=/tmp/skin-audit gradle jvmTest --tests '*SkinContrastAudit*'
//   可选：CANOPY_SKIN_AUDIT_SKINS=aqua,neo（只跑这几套）CANOPY_SKIN_AUDIT_PAGES=dashboard,board
//   CANOPY_SKIN_AUDIT_PROJECT=vtest（项目页的仓库）CANOPY_SKIN_AUDIT_SETTLE_MS=2600（等异步数据的时间）
//   数据取自本机引擎（只读命令）。没给 CANOPY_SKIN_AUDIT 就跳过——普通门禁不依赖显示器。
//
// 【判据】WCAG 对比度：正文 ≥ 4.5，大字（≥ 24px 高）≥ 3.0。报告分三档：冲突（< 3.0）/ 偏弱 / 达标。
// 禁用的控件不量（非活动组件不设要求）。只量静置态：悬停 / 焦点 / 弹层里的文字由 SkinTest 的表面模型兜。
// 前景色是从反锯齿后的像素里估出来的（离背景最远的那一撮），仍略偏保守。
// 产物：<皮肤>-<页面>.png、report.tsv（每段文字一行）、summary.txt（每套皮肤的冲突清单）。
package canopy.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asSkiaBitmap
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.runComposeUiTest
import canopy.App
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image as SkiaImage
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt
import kotlin.test.Test
import org.junit.Assume.assumeTrue

/** 任何带文字的节点（未合并的语义树——每个 Text 自己一个节点，边界就是文字本身）。 */
private val ANY_TEXT = SemanticsMatcher("hasText") { it.config.getOrNull(SemanticsProperties.Text)?.isNotEmpty() == true }

class SkinContrastAudit {
    private data class Page(val section: String, val project: String? = null)

    private data class Hit(val page: String, val text: String, val contrast: Double, val fg: Color, val bg: Color, val big: Boolean)

    /** 一段文字在画面上的位置。必须在测试作用域**内**从语义节点拷出来：作用域一结束场景就销毁，
     *  再去读节点的 boundsInRoot 得到的是全 0（实测抓到：96 段文字全被判成「太小」跳过）。 */
    private data class TextSpot(val text: String, val bounds: Rect, val height: Int)

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun everyTextIsReadableInEverySkin() {
        val outDir = System.getenv("CANOPY_SKIN_AUDIT")
        assumeTrue("没给 CANOPY_SKIN_AUDIT：逐皮肤对比度体检只在有显示器的开发机上手动触发", outDir != null)
        val out = File(outDir).apply { mkdirs() }
        val only = System.getenv("CANOPY_SKIN_AUDIT_SKINS")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }
        val pageFilter = System.getenv("CANOPY_SKIN_AUDIT_PAGES")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }
        val project = System.getenv("CANOPY_SKIN_AUDIT_PROJECT") ?: "vtest"
        val settleMs = (System.getenv("CANOPY_SKIN_AUDIT_SETTLE_MS") ?: "2600").toLong()
        val pages = listOf(
            Page("dashboard"), Page("board"), Page("milestones"), Page("confidence"), Page("patchcheck"),
            Page("settings"), Page("project", project),
        ).filter { pageFilter == null || it.section in pageFilter }
        val report = StringBuilder("皮肤\t页面\t对比度\t前景\t背景\t字号档\t文字\n")
        val summary = StringBuilder()
        for (skin in Skins.all) {
            if (only != null && skin.id !in only) continue
            Skins.apply(skin)
            L10n.applyLanguage(AppLanguage.ZH_CN)
            val hits = ArrayList<Hit>()
            for (p in pages) {
                val (bitmap, nodes) = render(p, settleMs)
                File(out, "${skin.id}-${p.section}.png").writeBytes(
                    SkiaImage.makeFromBitmap(bitmap.asSkiaBitmap()).encodeToData(EncodedImageFormat.PNG)!!.bytes,
                )
                hits += measure(bitmap, nodes, p.section)
            }
            for (h in hits) {
                report.appendLine(
                    "${skin.id}\t${h.page}\t${"%.1f".format(h.contrast)}\t${hex(h.fg)}\t${hex(h.bg)}\t" +
                        "${if (h.big) "大字" else "正文"}\t${h.text.take(40)}",
                )
            }
            val bad = hits.filter { it.contrast < 3.0 }
            val weak = hits.filter { it.contrast >= 3.0 && it.contrast < 4.5 }
            summary.appendLine("## ${skin.id}（${skin.titleZh}）：${hits.size} 段文字，冲突 ${bad.size}，偏弱 ${weak.size}")
            // 冲突的去重清单（同字同色的只列一次），按对比度升序
            bad.groupBy { Triple(it.text, hex(it.fg), hex(it.bg)) }.values.map { it.minBy { h -> h.contrast } }
                .sortedBy { it.contrast }.take(20).forEach { h ->
                    summary.appendLine("  - ${"%.1f".format(h.contrast)}  ${hex(h.fg)} on ${hex(h.bg)}  [${h.page}] ${h.text.take(34)}")
                }
            println("AUDIT ${skin.id}: ${hits.size} texts, ${bad.size} conflicts, ${weak.size} weak")
        }
        File(out, "report.tsv").writeText(report.toString())
        File(out, "summary.txt").writeText(summary.toString())
        // 体检本身是报告，不是断言：令牌级的不变量由 SkinTest 钉。这里只保证报告非空（真的量到了东西）。
        assumeTrue("没量到任何文字：渲染环境不可用（没有显示器或 headless）", report.lines().size > 1)
    }

    /** 离屏画一页：每 100ms 泵一帧等异步数据到位，返回位图与每段文字的位置。 */
    @OptIn(ExperimentalTestApi::class)
    private fun render(p: Page, settleMs: Long): Pair<ImageBitmap, List<TextSpot>> {
        lateinit var bitmap: ImageBitmap
        val spots = ArrayList<TextSpot>()
        runComposeUiTest {
            setContent {
                // 与 Main.kt 的真窗口同构：只给 MaterialTheme，皮肤材质由 App 根自己铺（菜单条也在它上面）——
                // 体检原先在这里多包一层 SkinBackdrop，把「菜单条画在材质之外、白字压白底」盖住了
                MaterialTheme(colorScheme = fluentColorScheme(), typography = FluentTypography, shapes = FluentShapes) {
                    App(initialSection = p.section, initialProject = p.project)
                }
            }
            repeat((settleMs / 100L).toInt().coerceAtLeast(4)) {
                Thread.sleep(100)
                waitForIdle()
            }
            onRoot().fetchSemanticsNode() // 先碰一次语义树（之后才有未合并树的节点）
            // 禁用的控件不量：禁用态的文字本来就淡（WCAG 对非活动组件不设要求），量了只是噪声。
            // 未合并树里「禁用」标记在可点节点上、不在文字节点上——按范围判断：文字中心落在禁用节点里就跳过
            val disabled = onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.Disabled), useUnmergedTree = true)
                .fetchSemanticsNodes().map { it.boundsInRoot }
            onAllNodes(ANY_TEXT, useUnmergedTree = true).fetchSemanticsNodes().forEach { n ->
                val center = n.boundsInRoot.center
                if (disabled.any { it.contains(center) }) return@forEach
                val text = n.config.getOrNull(SemanticsProperties.Text)!!.joinToString(" ") { it.text }.trim()
                spots.add(TextSpot(text, n.boundsInRoot, n.size.height))
            }
            bitmap = onRoot(useUnmergedTree = true).captureToImage()
        }
        return bitmap to spots
    }

    private fun measure(bitmap: ImageBitmap, spots: List<TextSpot>, page: String): List<Hit> {
        val pm = bitmap.toPixelMap()
        val w = bitmap.width
        val h = bitmap.height
        val hits = ArrayList<Hit>()
        for (n in spots) {
            val r = n.bounds
            val x0 = max(0, r.left.toInt())
            val y0 = max(0, r.top.toInt())
            val x1 = min(w, r.right.roundToInt())
            val y1 = min(h, r.bottom.roundToInt())
            if (x1 - x0 < 3 || y1 - y0 < 6) continue
            val px = IntArray((x1 - x0) * (y1 - y0))
            var k = 0
            for (y in y0 until y1) for (x in x0 until x1) px[k++] = pm[x, y].toArgbInt()
            // 背景 = 量化直方图里最大的一桶的平均色
            val hist = HashMap<Int, IntArray>()
            for (c in px) {
                val key = ((c shr 20) and 0xF00) or ((c shr 12) and 0x0F0) or ((c shr 4) and 0x00F)
                val e = hist.getOrPut(key) { IntArray(4) }
                e[0]++
                e[1] += (c shr 16) and 255
                e[2] += (c shr 8) and 255
                e[3] += c and 255
            }
            val top = hist.values.maxBy { it[0] }
            val nb = top[0]
            val bg = Color(top[1] / nb / 255f, top[2] / nb / 255f, top[3] / nb / 255f)
            // 前景 = 离背景最远的那一撮（≥ 最大色距的 96%）的平均色——反锯齿后笔画核心才是墨色本身。
            // 小字细笔画大半像素是过渡色：取 85% 那一版把三级小字（真值 4.5）读成 3.9。
            // 节点**外圈一圈**的像素不参与：带底色的文字（胶囊、按钮）语义边界盖住整个胶囊，圆角外露出周围
            // 表面的像素、直边上是与周围表面反锯齿的过渡色，「离背景最远」会选中它们（frutiger 的「简体中文」
            // 实为深字压绿：只排除四角时量成了边缘过渡色 2.7，不排除时量成白字 3.2）。
            // 试过「只看中央」（可点的整行很宽，文字在最左时中央只剩零星过渡色）和「非背景里最常见的一色」
            // （细笔画的过渡像素比核心还多）——都比这个差。
            val bR = top[1] / nb / 255f
            val bG = top[2] / nb / 255f
            val bB = top[3] / nb / 255f
            val frame = min(3f, min(x1 - x0, y1 - y0) * 0.15f)
            var maxDist = 0f
            val dists = FloatArray(px.size)
            var k2 = 0
            for (y in y0 until y1) for (x in x0 until x1) {
                val onFrame = x < x0 + frame || x >= x1 - frame || y < y0 + frame || y >= y1 - frame
                val i = k2++
                if (onFrame) continue
                val dr = ((px[i] shr 16) and 255) / 255f - bR
                val dg = ((px[i] shr 8) and 255) / 255f - bG
                val db = (px[i] and 255) / 255f - bB
                val d = sqrt(dr * dr + dg * dg + db * db)
                dists[i] = d
                if (d > maxDist) maxDist = d
            }
            if (maxDist < 0.06f) continue // 这块里没有别的颜色：纯色底上没有可见文字（与底同色的由令牌判据去抓）
            var fr = 0L
            var fgG = 0L
            var fb = 0L
            var n2 = 0
            for (i in px.indices) {
                if (dists[i] >= maxDist * 0.96f) {
                    fr += (px[i] shr 16) and 255
                    fgG += (px[i] shr 8) and 255
                    fb += px[i] and 255
                    n2++
                }
            }
            val fg = Color(fr / n2 / 255f, fgG / n2 / 255f, fb / n2 / 255f)
            val contrast = ((max(bg.luminance(), fg.luminance()) + 0.05f) / (min(bg.luminance(), fg.luminance()) + 0.05f)).toDouble()
            hits.add(Hit(page, n.text, contrast, fg, bg, n.height >= 24))
        }
        return hits
    }

    /** Compose 颜色（sRGB）→ ARGB 整数（不透明）。 */
    private fun Color.toArgbInt(): Int =
        (255 shl 24) or ((red * 255f).roundToInt() shl 16) or ((green * 255f).roundToInt() shl 8) or (blue * 255f).roundToInt()


    private fun hex(c: Color): String = String.format("#%02x%02x%02x", (c.red * 255).roundToInt(), (c.green * 255).roundToInt(), (c.blue * 255).roundToInt())
}
