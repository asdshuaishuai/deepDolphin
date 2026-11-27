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
//   CANOPY_SKIN_AUDIT_HOVER=1（再加一遍悬停遍）/ CANOPY_SKIN_AUDIT_PRESSED=1（再加一遍按下遍，慢一倍）
//   数据取自本机引擎（只读命令）。没给 CANOPY_SKIN_AUDIT 就跳过——普通门禁不依赖显示器。
//
// 【判据】WCAG 对比度：正文 ≥ 4.5，大字（≥ 24px 高）≥ 3.0。报告分三档：冲突（< 3.0）/ 偏弱 / 达标。
// 禁用的控件不量（非活动组件不设要求）。静置态每页量一遍；悬停遍 / 按下遍另算（见 stateSweep）。
// 前景色是从反锯齿后的像素里估出来的（离背景最远的那一撮），仍略偏保守。
// 产物：<皮肤>-<页面>.png、report.tsv（静置态每段文字一行；状态遍只列被状态改变过的文字，每段留最差的一态）、
// summary.txt（每套皮肤的冲突清单）。
package canopy.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asSkiaBitmap
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.MouseButton
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.performMouseInput
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

/** 可点的节点：clickable 自带 hoverable，所以它们就是悬停目标（这一版 Compose 的语义树里没有单独的「可悬停」标记）。 */
private val CLICKABLE = hasClickAction()

class SkinContrastAudit {
    private data class Page(val section: String, val project: String? = null)

    private data class Hit(
        val page: String, val key: String, val text: String,
        val contrast: Double, val fg: Color, val bg: Color, val big: Boolean,
    )

    /** 一段文字在画面上的位置。必须在测试作用域**内**从语义节点拷出来：作用域一结束场景就销毁，
     *  再去读节点的 boundsInRoot 得到的是全 0（实测抓到：96 段文字全被判成「太小」跳过）。 */
    private data class TextSpot(val text: String, val bounds: Rect, val height: Int) {
        /** 同一段文字在各态之间的身份：文字 + 取整后的位置（悬停抬升会挪 2dp，容 3px）。 */
        val key: String get() = text + "@" + ((bounds.left / 3).roundToInt() * 3) + "," + ((bounds.top / 3).roundToInt() * 3)
    }

    /** 一帧：位图 + 每段文字的位置。 */
    private data class Frame(val bitmap: ImageBitmap, val spots: List<TextSpot>)

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
        val sweepHover = System.getenv("CANOPY_SKIN_AUDIT_HOVER") != null
        val sweepPressed = System.getenv("CANOPY_SKIN_AUDIT_PRESSED") != null
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
            val stateHits = ArrayList<Hit>()
            var targets = 0
            for (p in pages) {
                withScene(p, settleMs) {
                    val rest = snapshot()
                    File(out, "${skin.id}-${p.section}.png").writeBytes(png(rest))
                    hits += measure(rest, rest.spots, p.section)
                    if (sweepHover) {
                        val (found, n) = stateSweep(rest, p.section, out, skin.id, pressed = sweepPressed)
                        stateHits += found
                        targets += n
                    }
                }
            }
            (hits + stateHits).forEach { h ->
                report.appendLine(
                    "${skin.id}\t${h.page}\t${"%.1f".format(h.contrast)}\t${hex(h.fg)}\t${hex(h.bg)}\t" +
                        "${if (h.big) "大字" else "正文"}\t${h.text.take(40)}",
                )
            }
            val bad = hits.filter { it.contrast < 3.0 }
            val weak = hits.filter { it.contrast >= 3.0 && it.contrast < 4.5 }
            val stateBad = stateHits.filter { it.contrast < 3.0 }
            val stateWeak = stateHits.filter { it.contrast >= 3.0 && it.contrast < 4.5 }
            summary.appendLine(
                "## ${skin.id}（${skin.titleZh}）：${hits.size} 段文字，冲突 ${bad.size}，偏弱 ${weak.size}" +
                    if (sweepHover) "；状态遍 ${targets} 个目标，被改变对比度的文字 ${stateHits.size} 段，冲突 ${stateBad.size}，偏弱 ${stateWeak.size}" else "",
            )
            // 冲突的去重清单（同字同色的只列一次），按对比度升序；状态遍的排在后面
            (bad.map { it to "" } + stateBad.map { it to "〔态〕" }).groupBy { Triple(it.first.text, hex(it.first.fg), hex(it.first.bg)) }
                .values.map { it.minBy { h -> h.first.contrast } }.sortedBy { it.first.contrast }.take(24).forEach { (h, tag) ->
                    summary.appendLine("  - ${"%.1f".format(h.contrast)}  ${hex(h.fg)} on ${hex(h.bg)}  ${tag}[${h.page}] ${h.text.take(34)}")
                }
            println("AUDIT ${skin.id}: ${hits.size} texts, ${bad.size} conflicts, ${weak.size} weak" + if (sweepHover) "; states ${targets} targets, ${stateHits.size} changed, ${stateBad.size} conflicts, ${stateWeak.size} weak" else "")
        }
        File(out, "report.tsv").writeText(report.toString())
        File(out, "summary.txt").writeText(summary.toString())
        // 体检本身是报告，不是断言：令牌级的不变量由 SkinTest 钉。这里只保证报告非空（真的量到了东西）。
        assumeTrue("没量到任何文字：渲染环境不可用（没有显示器或 headless）", report.lines().size > 1)
    }

    /** 离屏画一页：每 100ms 泵一帧等异步数据到位，然后在同一个场景里做 [block]（静置态 + 状态遍共用一棵树）。 */
    @OptIn(ExperimentalTestApi::class)
    private fun withScene(p: Page, settleMs: Long, block: ComposeUiTest.() -> Unit) = runComposeUiTest {
        setContent {
            // 与 Main.kt 的真窗口同构：只给 MaterialTheme，皮肤材质由 App 根自己铺（菜单条也在它上面）——
            // 体检原先在这里多包一层 SkinBackdrop，把「菜单条画在材质之外、白字压白底」盖住了
            MaterialTheme(colorScheme = fluentColorScheme(), typography = FluentTypography, shapes = FluentShapes) {
                App(initialSection = p.section, initialProject = p.project)
            }
        }
        pump((settleMs / 100L).toInt().coerceAtLeast(4))
        mainRoot().fetchSemanticsNode() // 先碰一次语义树（之后才有未合并树的节点）
        block()
    }

    /** 主场景的根。悬停会弹出提示条（另一个根）：`onRoot()` 在多于一个根时会直接抛，所以这里取第一个。 */
    @OptIn(ExperimentalTestApi::class)
    private fun ComposeUiTest.mainRoot() = onAllNodes(isRoot(), useUnmergedTree = true)[0]

    /** 等状态切换的动画走完：测试时钟自动跟着真实时间走，`waitForIdle()` 要等树闲置（动画在跑就不闲置）才返回。 */
    @OptIn(ExperimentalTestApi::class)
    private fun ComposeUiTest.settle() {
        waitForIdle()
        waitForIdle()
    }

    @OptIn(ExperimentalTestApi::class)
    private fun ComposeUiTest.pump(times: Int) {
        repeat(times) {
            Thread.sleep(100)
            waitForIdle()
        }
    }

    /** 当前帧：位图 + 每段文字的位置。 */
    @OptIn(ExperimentalTestApi::class)
    private fun ComposeUiTest.snapshot(): Frame {
        // 禁用的控件不量：禁用态的文字本来就淡（WCAG 对非活动组件不设要求），量了只是噪声。
        // 未合并树里「禁用」标记在可点节点上、不在文字节点上——按范围判断：文字中心落在禁用节点里就跳过
        val disabled = onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.Disabled), useUnmergedTree = true)
            .fetchSemanticsNodes().map { it.boundsInRoot }
        val spots = ArrayList<TextSpot>()
        onAllNodes(ANY_TEXT, useUnmergedTree = true).fetchSemanticsNodes().forEach { n ->
            val center = n.boundsInRoot.center
            if (disabled.any { it.contains(center) }) return@forEach
            val text = n.config.getOrNull(SemanticsProperties.Text)!!.joinToString(" ") { it.text }.trim()
            spots.add(TextSpot(text, n.boundsInRoot, n.size.height))
        }
        return Frame(mainRoot().captureToImage(), spots)
    }

    /**
     * 状态遍：指针依次落到每个可悬停节点上（嵌套的可点节点——卡里的按钮——一起进入悬停态），逐次量全页文字；
     * 可选再按一下（不松手时量按下态，然后把指针拖出界再松开——不触发点击）。返回「被状态改变过对比度的文字」
     * （每段只留最差的一态）与目标个数。
     *
     * 【为什么要它】静置态只能证明「放着的时候读得出」。悬停会换底色（卡 → 悬停卡、按钮提亮 / 压暗）、
     * 会把卡上浮、会让加法提亮叠上来——这些在 SkinTest 里只有模型，没有像素。这里量的是画出来的。
     * 只重量变了的文字：每段文字的位置先算一个像素和，和静置帧一样就跳过。
     * 悬停弹出浮层（提示条）时页面文字跳过、浮层里的文字单独量（见 captureState）。
     */
    @OptIn(ExperimentalTestApi::class)
    private fun ComposeUiTest.stateSweep(rest: Frame, page: String, out: File, skinId: String, pressed: Boolean): Pair<List<Hit>, Int> {
        val restHits = measure(rest, rest.spots, page).associateBy { it.key }
        val restSig = signatures(rest)
        val worst = LinkedHashMap<String, Hit>()
        var shots = 0
        // 静置之后才出现的文字节点（id 更大）= 悬停弹出来的浮层里的文字
        val maxRestId = onAllNodes(ANY_TEXT, useUnmergedTree = true).fetchSemanticsNodes().maxOf { it.id }
        fun record(frame: Frame, h: Hit) {
            if (h.contrast < (worst[h.key]?.contrast ?: Double.MAX_VALUE)) {
                worst[h.key] = h
                if (h.contrast < 3.0 && shots < 3) {
                    shots++
                    File(out, "${skinId}-${page.substringBefore('·')}-state${shots}.png").writeBytes(png(frame))
                }
            }
        }
        fun consider(frame: Frame, label: String) {
            val sig = signatures(frame)
            val changed = frame.spots.filter { sig[it] != restSig[it] }
            if (changed.isEmpty()) return
            measure(frame, changed, label).forEach { h ->
                val before = restHits[h.key]?.contrast ?: Double.MAX_VALUE
                if (h.contrast < before - 0.05) record(frame, h)
            }
        }
        /**
         * 量一个状态。悬停在带帮助文案的控件上会弹出提示条——它是另一个根，盖在页面文字上：这一帧的页面文字
         * 量不准（vernacular 实测：提示条盖住「深更新」，量到的是露出来的按钮底色品红，报了 6 处假冲突），
         * 跳过；浮层里的文字单独量（它的底是 PopoverRaised，正是模型之外最该看一眼的那类表面）。
         */
        fun captureState(label: String) {
            val roots = onAllNodes(isRoot(), useUnmergedTree = true)
            val n = roots.fetchSemanticsNodes().size
            if (n == 1) {
                consider(snapshot(), label)
                return
            }
            for (r in 1 until n) {
                val popup = onAllNodes(ANY_TEXT, useUnmergedTree = true).fetchSemanticsNodes().filter { it.id > maxRestId }
                if (popup.isEmpty()) continue
                val frame = Frame(
                    roots[r].captureToImage(),
                    popup.map { TextSpot(it.config.getOrNull(SemanticsProperties.Text)!!.joinToString(" ") { t -> t.text }.trim(), it.boundsInRoot, it.size.height) },
                )
                measure(frame, frame.spots, "$label·浮层").forEach { record(frame, it) }
            }
        }
        val done = HashSet<Rect>()
        var i = 0
        while (true) {
            val nodes = onAllNodes(CLICKABLE, useUnmergedTree = true).fetchSemanticsNodes()
            if (i >= nodes.size) break
            val box = nodes[i].boundsInRoot
            val target = onAllNodes(CLICKABLE, useUnmergedTree = true)[i]
            i++
            if (box.width <= 4f || box.height <= 4f || !done.add(box)) continue
            target.performMouseInput { enter(center) }
            settle()
            captureState("$page·悬停")
            if (pressed) {
                target.performMouseInput { press(MouseButton.Primary) }
                settle()
                captureState("$page·按下")
                // 拖出界再松手：按下态随「指针出界」取消，松开不构成点击；指针出了界，悬停态也随之结束
                target.performMouseInput { moveTo(Offset(-5000f, -5000f)); release(MouseButton.Primary) }
            } else {
                // 指针可能没落在窗口里（滚出视野的节点）：没进入悬停态就不发离开事件
                runCatching { mainRoot().performMouseInput { exit() } }
            }
            settle()
        }
        return worst.values.toList() to done.size
    }

    /** 每段文字位置的像素和（同一位置在两帧里像素全同 ⇒ 状态没动它）。 */
    private fun signatures(frame: Frame): Map<TextSpot, Long> {
        val pm = frame.bitmap.toPixelMap()
        val w = frame.bitmap.width
        val h = frame.bitmap.height
        val m = HashMap<TextSpot, Long>()
        for (n in frame.spots) {
            val x0 = max(0, n.bounds.left.toInt())
            val y0 = max(0, n.bounds.top.toInt())
            val x1 = min(w, n.bounds.right.roundToInt())
            val y1 = min(h, n.bounds.bottom.roundToInt())
            var s = 0L
            for (y in y0 until y1) for (x in x0 until x1) s += pm[x, y].toArgbInt()
            m[n] = s
        }
        return m
    }

    private fun png(frame: Frame): ByteArray =
        SkiaImage.makeFromBitmap(frame.bitmap.asSkiaBitmap()).encodeToData(EncodedImageFormat.PNG)!!.bytes

    private fun measure(frame: Frame, spots: List<TextSpot>, page: String): List<Hit> = measure(frame.bitmap, spots, page)

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
            hits.add(Hit(page, n.key, n.text, contrast, fg, bg, n.height >= 24))
        }
        return hits
    }

    /** Compose 颜色（sRGB）→ ARGB 整数（不透明）。 */
    private fun Color.toArgbInt(): Int =
        (255 shl 24) or ((red * 255f).roundToInt() shl 16) or ((green * 255f).roundToInt() shl 8) or (blue * 255f).roundToInt()

    private fun hex(c: Color): String = String.format("#%02x%02x%02x", (c.red * 255).roundToInt(), (c.green * 255).roundToInt(), (c.blue * 255).roundToInt())
}
