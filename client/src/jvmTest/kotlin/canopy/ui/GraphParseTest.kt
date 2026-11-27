// GraphParseTest.kt —— 图谱两页回执/产物路径提取的判据（fixture 取自真机引擎 cambium 真跑，
// 零手造：fixtures/render/ 由 `cambium render <index|arch> vtest [--confidence] [--force]` 重定向落盘）。
//
// 判据只增不减：mac CodeGraphPageVM.receipt / extractHTMLPath / contains("复用") 的机制对位，
// 输出形状差异（路径黏全角冒号、无空格）如实适配并在这里锚死。

package canopy.ui

import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.unit.dp
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GraphParseTest {

    @BeforeTest
    fun pinZh() {
        // 断言锚定 zh 文案：钉住语言，防宿主 locale / settings.conf 漂移翻红
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    /** fixtures 与源码同仓：从仓库相对路径直读（ContractTest 同款做法，比 classpath 资源透明）。 */
    private fun fixture(name: String): String {
        val f = File("src/jvmTest/resources/fixtures/render/$name.txt")
        check(f.isFile) { "fixture 缺失：${f.absolutePath}" }
        return f.readText()
    }

    // ── receiptLine：末行（mac receipt 同逻辑：最后一个非空行）──

    @Test
    fun receiptLineIsLastNonEmptyLine() {
        // index 带「图例注明」次行时，回执末行 = 图例行（版本信息在首行路径后面）
        assertEquals(
            "图例注明：无置信度数据（confidence.json 缺席）——本页只呈现结构",
            receiptLine(fixture("index_reused")),
        )
    }

    @Test
    fun receiptLineOfSingleLineArchOutput() {
        // arch 复用是单行输出：末行就是「已复用持久化渲染…」整行
        assertEquals(
            "已复用持久化渲染（首版（第 0 版））：/home/superShuai/.deepgit/store/p_f80de38f6095/render/arch.html",
            receiptLine(fixture("arch_reused")),
        )
    }

    @Test
    fun receiptLineSkipsTrailingBlankLines() {
        // 引擎输出以换行收尾时不算出「空回执」
        assertEquals("已重绘：/a/render/arch.html · 首版（第 0 版）", receiptLine("已重绘：/a/render/arch.html · 首版（第 0 版）\n\n"))
        assertNull(receiptLine("\n \n"))
    }

    // ── extractHtmlPath：产物绝对路径（mac extractHTMLPath 对位；适配黏全角冒号的真实形状）──

    @Test
    fun extractsPathGluedAfterFullWidthColon() {
        // 真机形状：路径黏在「：」后无空格（mac 的空格分词会漏提；正则提取锚死此形状）
        assertEquals(
            "/home/superShuai/.deepgit/store/p_f80de38f6095/render/index.html",
            extractHtmlPath(fixture("index_redrawn")),
        )
        assertEquals(
            "/home/superShuai/.deepgit/store/p_f80de38f6095/render/index.html",
            extractHtmlPath(fixture("index_reused")),
        )
        assertEquals(
            "/home/superShuai/.deepgit/store/p_f80de38f6095/render/arch.html",
            extractHtmlPath(fixture("arch_reused")),
        )
        assertEquals(
            "/home/superShuai/.deepgit/store/p_f80de38f6095/render/arch.html",
            extractHtmlPath(fixture("arch_redrawn")),
        )
    }

    @Test
    fun extractPathStopsAtWhitespace() {
        // 路径后跟「 · 首版」不吞进路径
        assertEquals("/a/b/index.html", extractHtmlPath("已重绘：/a/b/index.html · 首版（第 0 版）"))
    }

    @Test
    fun extractPathRequiresAbsoluteHtmlToken() {
        // 相对路径 / 非 .html / 没有 → null（绝对路径语义与 mac hasPrefix("/") 一致）
        assertNull(extractHtmlPath("已重绘：render/index.html · 首版"))
        assertNull(extractHtmlPath("产物在 /tmp/arch.json 已更新"))
        assertNull(extractHtmlPath("没有任何产物字样"))
    }

    // ── renderReused：复用判定（mac text.contains("复用")）──

    @Test
    fun reusedWordingDetectedInAllRealVariants() {
        assertTrue(renderReused(fixture("index_reused")), "「已复用（产物未变）」必须判复用")
        assertTrue(renderReused(fixture("arch_reused")), "「已复用持久化渲染」必须判复用")
        assertFalse(renderReused(fixture("index_redrawn")), "「已重绘」不是复用")
        assertFalse(renderReused(fixture("arch_redrawn")), "「已重绘」不是复用")
    }

    @Test
    fun reusedEnglishWordingAlsoDetected() {
        // 引擎 T() 的 en 语言输出同语义（mac 只查中文；这里如实扩一档，不改变中文判定）
        assertTrue(renderReused("Reused persisted render (v1): /tmp/a/arch.html"))
        assertTrue(renderReused("reused (product unchanged): /tmp/a/index.html"))
        assertFalse(renderReused("Redrawn: /tmp/a/index.html · v1"))
    }

    // ── 置信度快照过期：引擎不再把旧快照叠上去，回执如实说明——客户端据此补生成再重绘 ──

    @Test
    fun staleConfidenceWordingDetectedInRealReceipts() {
        // fixture 取自 cambium 真跑：生成快照后改源码（索引被自动重建成第 1 版），再 render index --confidence
        val zh = fixture("index_stale_confidence")
        val en = fixture("index_stale_confidence_en")
        assertTrue(renderStaleConfidence(zh), "「置信度快照过期……先 moongit confidence gen」必须判过期")
        assertTrue(renderStaleConfidence(en), "en 回执「Confidence snapshot is stale …」必须判过期")
        // 过期回执照样提得到产物路径（结构图照常可看）；末行就是过期说明
        assertTrue(extractHtmlPath(zh)!!.endsWith("/render/index.html"))
        assertTrue(receiptLine(zh)!!.contains("置信度快照过期"))
    }

    @Test
    fun freshReceiptsAreNotStale() {
        listOf("index_redrawn", "index_reused", "arch_redrawn", "arch_reused").forEach { name ->
            assertFalse(renderStaleConfidence(fixture(name)), "$name 没有过期说明，不得判过期")
        }
    }

    @Test
    fun onlyHeatMapRefreshesConfidence() {
        // 热力图过期要自愈；架构图不叠加置信度，回执里出现同样的话也不该去生成快照
        assertTrue(needsConfidenceRefresh(GraphKind.INDEX, fixture("index_stale_confidence")))
        assertFalse(needsConfidenceRefresh(GraphKind.INDEX, fixture("index_redrawn")))
        assertFalse(needsConfidenceRefresh(GraphKind.ARCH, fixture("index_stale_confidence")))
    }

    // ── 重载判定：复用且路径没变就不重载（不闪）──

    @Test
    fun reloadOnlyWhenRedrawnOrPathChanged() {
        assertTrue(shouldReloadWebView(reused = false, pathChanged = false), "重绘了必须重载")
        assertTrue(shouldReloadWebView(reused = true, pathChanged = true), "复用但路径变了要重载")
        assertFalse(shouldReloadWebView(reused = true, pathChanged = false), "复用且路径没变不重载（画面没变就不闪）")
    }

    // ── 端到端解析链：真输出 → 末行 + 路径 + 复用三件套一起成立 ──

    @Test
    fun realOutputsDriveFullParseChain() {
        listOf("index_redrawn", "index_reused", "arch_redrawn", "arch_reused").forEach { name ->
            val text = fixture(name)
            assertTrue(receiptLine(text)!!.isNotBlank(), "$name 必有回执行")
            assertTrue(extractHtmlPath(text)!!.startsWith("/"), "$name 必提得到绝对产物路径")
        }
    }
    // ── 页面形态（用户定稿 2026-11-25：跟仓库走的独立页面，不弹窗）──

    @Test
    fun graphKindsOwnTheirRoutes() {
        assertEquals(AppModel.Route.GRAPH, GraphKind.INDEX.route)
        assertEquals(AppModel.Route.ARCH, GraphKind.ARCH.route)
        // 仓库级页面 = 详情 + 图谱两页：侧栏高亮所属仓库、更新范围收敛到它
        listOf(AppModel.Route.PROJECT, AppModel.Route.GRAPH, AppModel.Route.ARCH).forEach {
            assertTrue(it.isRepoScoped(), "$it 必须算仓库级页面")
        }
        listOf(
            AppModel.Route.DASHBOARD, AppModel.Route.BOARD, AppModel.Route.MILESTONES,
            AppModel.Route.CONFIDENCE, AppModel.Route.PATCHCHECK, AppModel.Route.SETTINGS,
        ).forEach { assertFalse(it.isRepoScoped(), "$it 是全局视图") }
    }

    // ── 嵌入配置：把客户端的设计令牌翻译成产物的嵌入模式声明（GraphEmbed.kt）──

    @Test
    fun embedHeadScriptDeclaresPageChromeWithClientTokens() {
        val script = graphEmbedHeadScript(arch = false)
        assertTrue(script.startsWith("(function(){window.CAMBIUM_EMBED="), "声明必须在产物任何脚本之前由宿主给出")
        assertTrue(script.contains("\"chrome\":\"page\""), "chrome=page：产物才会收拢外壳")
        assertFalse(script.contains("</script"), "脚本里不许出现能截断 <script> 的串")
        val vars = decodeEmbedVars(script)
        // 底色、描边、文字、强调色都来自 Design.kt 的 Palette（改令牌 ⇒ 图谱跟着变，不手抄颜色）
        assertEquals("#1f1f1f", vars["--bg"])
        assertEquals("#292929", vars["--panel"])
        assertEquals("rgba(255,255,255,0.078)", vars["--line2"])
        assertEquals("rgba(255,255,255,0.141)", vars["--line"])
        assertEquals("#ffffff", vars["--text"])
        assertEquals("rgba(255,255,255,0.659)", vars["--muted"])
        assertEquals("#60cdff", vars["--cyan"])
        assertEquals("#60cdff", vars["--accent"])
        assertEquals("#6ccb5f", vars["--green"])
        assertEquals("#ffd24a", vars["--yellow"])
        assertEquals("#ff99a4", vars["--red"])
        assertEquals("8px", vars["--radius"])
        assertEquals("#191919", vars["--e-surface"])
        // 架构图产物：暗色垫片在前（不认识嵌入配置的老引擎产物跟随 prefers-color-scheme，仍要是暗色）
        assertTrue(graphEmbedHeadScript(arch = true).startsWith(DARK_SCHEME_SHIM))
    }

    @Test
    fun embedVarsCarrySizeTokensAndFollowSkinRadius() {
        // 尺寸契约：控件高、底条高、控件圆角、卡片圆角——与外壳同值（Fluent 默认 32 / 32 / 4 / 8），
        // 产物嵌入样式里不再写死 28/30px、4/6px
        val fluent = decodeEmbedVars(graphEmbedHeadScript(arch = false))
        assertEquals("32px", fluent["--e-ctl-h"])
        assertEquals("32px", fluent["--e-foot-h"])
        assertEquals("4px", fluent["--e-r-ctl"])
        assertEquals("8px", fluent["--e-r-card"])
        try {
            // 换成直角皮肤：嵌入页的输入框、按钮、卡片跟着变方角（令牌改 ⇒ 图谱跟着变）
            Skins.apply(Skins.byId.getValue("neobrutal"))
            val neo = decodeEmbedVars(graphEmbedHeadScript(arch = false))
            assertEquals("0px", neo["--e-r-ctl"])
            assertEquals("0px", neo["--e-r-card"])
            assertEquals("0px", neo["--radius"], "画在画布上的卡片圆角同源")
            assertEquals("32px", neo["--e-ctl-h"], "控件高不随皮肤变")
        } finally {
            Skins.apply(Skins.byId.getValue(Skins.DEFAULT_ID))
        }
    }

    @Test
    fun cssPxWritesIntegersPlainAndKeepsOneDecimal() {
        assertEquals("8px", cssPx(8.dp))
        assertEquals("0px", cssPx(0.dp))
        assertEquals("2.5px", cssPx(2.5.dp))
    }

    @Test
    fun scaleCheckFlagsOnlyRealMismatches() {
        // 同一把尺子、或 Windows 高分屏的取整差（AWT 144dpi → 1.44，Chromium 1.5）都不算；
        // 显示缩放只被一边认出来（外壳 1×、内嵌 1.5×）才算
        assertFalse(HtmlWebEvent.Scale(1f, 1f).mismatched())
        assertFalse(HtmlWebEvent.Scale(1.44f, 1.5f).mismatched())
        assertFalse(HtmlWebEvent.Scale(2f, 2f).mismatched())
        assertTrue(HtmlWebEvent.Scale(1f, 1.5f).mismatched())
        assertTrue(HtmlWebEvent.Scale(1f, 0.75f).mismatched())
        assertEquals("1×", scaleText(1f))
        assertEquals("1.25×", scaleText(1.25f))
        assertEquals("1.5×", scaleText(1.5f))
    }

    @Test
    fun colorToCssKeepsLocaleAndTrimsAlpha() {
        assertEquals("#1f1f1f", androidx.compose.ui.graphics.Color(0xFF1F1F1F).toCss())
        assertEquals("rgba(255,255,255,0.659)", androidx.compose.ui.graphics.Color(0xA8FFFFFF).toCss())
        // 透明度按 8 位量化（0.10 × 255 四舍五入成 26 ⇒ 26/255）
        assertEquals("rgba(96,205,255,0.102)", androidx.compose.ui.graphics.Color(0xFF60CDFF).copy(alpha = 0.10f).toCss())
        assertEquals("rgba(255,255,255,0)", androidx.compose.ui.graphics.Color(0x00FFFFFF).toCss())
    }

    // ── 回执条：去掉产物的内部路径，其余一字不改 ──

    @Test
    fun receiptSummaryDropsArtifactPathAndKeepsTheRest() {
        assertEquals("已重绘 · 第 2 版", receiptSummary("已重绘：/home/superShuai/.deepgit/store/p_f80de38f6095/render/index.html · 第 2 版"))
        assertEquals(
            "已复用（产物未变） · 第 2 版",
            receiptSummary("已复用（产物未变）：/tmp/dg-probe-ui/store/p_f80de38f6095/render/index.html · 第 2 版"),
        )
        assertEquals(
            "已复用持久化渲染（首版（第 0 版））",
            receiptSummary("已复用持久化渲染（首版（第 0 版））：/home/superShuai/.deepgit/store/p_f80de38f6095/render/arch.html"),
        )
        assertEquals("Redrawn · v1", receiptSummary("Redrawn: /tmp/a/index.html · v1"))
        // 过期说明原样保留（它是用户要照着做的事）
        val stale = "置信度快照过期（依据首版（第 0 版）索引，当前第 1 版）——先 cambium confidence gen"
        assertEquals(stale, receiptSummary(stale))
        // 网址里的 .html 不算产物路径
        assertEquals("打开 http://example.com/a.html 失败", receiptSummary("打开 http://example.com/a.html 失败"))
    }

    // ── 装载：原生包钉版 + 暗色垫片 ──

    @Test
    fun nativeBundleIsPinnedPerPlatform() {
        val pinned = "https://cache-redirector.jetbrains.com/intellij-jbr/jbr_jcef-21.0.4-linux-x64-b631.2.tar.gz"
        assertEquals(pinned, JcefBundle.urlFor("Linux", "amd64"))
        assertEquals(pinned, JcefBundle.urlFor("Linux", "x86_64"))
        // 未验证平台不钉（调用方退回 KCEF 默认下载）——不拿 linux-x64 的包去装别的平台
        assertNull(JcefBundle.urlFor("Linux", "aarch64"))
        assertNull(JcefBundle.urlFor("Mac OS X", "x86_64"))
        assertNull(JcefBundle.urlFor("Windows 11", "amd64"))
    }

    @Test
    fun headScriptLandsBeforeAnyArtifactScript() {
        // 垫片必须早于产物自己的脚本：<head> 开头；标签大小写不敏感；没有 head 就放文档最前
        val out = withHeadScript(
            "<html><HEAD data-x=\"1\"><meta charset=\"utf-8\"><script>ART</script></HEAD><body></body></html>", "SHIM",
        )
        assertEquals(
            "<html><HEAD data-x=\"1\"><script>SHIM</script><meta charset=\"utf-8\"><script>ART</script></HEAD><body></body></html>", out,
        )
        assertEquals("<script>SHIM</script><html><body></body></html>", withHeadScript("<html><body></body></html>", "SHIM"))
    }

    // ── 页头紧凑态（内容区宽度定；原先标题列是唯一带 weight 的一列，最小窗口下标题竖排）──

    @Test
    fun graphHeaderGoesCompactBelowTheThreshold() {
        assertTrue(graphHeaderCompact(730f), "最小窗口 960 − 侧栏 230 = 730：紧凑")
        assertTrue(graphHeaderCompact(859.9f))
        assertFalse(graphHeaderCompact(860f), "阈值本身不进紧凑")
        assertFalse(graphHeaderCompact(1050f), "默认窗口 1280 − 侧栏：不紧凑")
    }

    @Test
    fun archCanvasPaletteCarriesTextLevelLaneColors() {
        // 泳道标签是文字：cols 是填充色，浅色皮肤下黄 / 浅绿读不出来——宿主要另给一份文字级的
        val script = graphEmbedHeadScript(arch = true)
        assertTrue(script.contains("\"textCols\""), "嵌入配置的画布调色板要带 textCols")
        assertTrue(script.contains("\"cols\""), "填充色照旧（卡片描边、边线渐变用它）")
    }

    /** 嵌入配置里的画布调色板（不是合法配置 = 空表）。 */
    private fun embedCanvasOf(script: String): JsonObject {
        val at = script.indexOf("window.CAMBIUM_EMBED=")
        assertTrue(at >= 0, "嵌入配置要在 head 脚本里")
        val body = script.substring(at + "window.CAMBIUM_EMBED=".length).removeSuffix("})();").removeSuffix(";").trim()
        return canopy.engine.contractJson.parseToJsonElement(body).jsonObject["canvas"]!!.jsonObject
    }

    private fun JsonObject.strings(key: String): List<String> = this[key]!!.jsonArray.map { it.jsonPrimitive.content }

    @Test
    fun laneLabelsStayReadableOnTheirOwnLaneAcrossSkins() {
        // 泳道标签压在自己颜色的泳道上。原先职责视图用产物自带的角色色（给暗色底挑的）：Aqua 上七档是
        // 1.44–2.20:1；架构级的标签虽有文字级颜色，但换肤保底只认皮肤自己的表面，不认这块带色的画布
        //（玻璃拟态上紫字差 0.05）。现在两套标签都走 laneInk：同一色相的文字级 + 按自己那条泳道保底 4.5。
        assertEquals(7, roleFills().toSet().size, "七个角色的填充色互不相同")
        assertEquals(5, layerFills().toSet().size, "五层的填充色互不相同")
        val stats = ArrayList<Triple<String, Int, Float>>()
        try {
            for (skin in Skins.all) {
                Skins.apply(skin)
                val canvas = embedCanvasOf(graphEmbedHeadScript(arch = true))
                assertEquals(layerFills().map { it.toCss() }, canvas.strings("cols"), skin.id)
                assertEquals(roleFills().map { it.toCss() }, canvas.strings("roleCols"), skin.id)
                assertEquals(layerTexts().map { it.toCss() }, canvas.strings("textCols"), skin.id)
                assertEquals(roleTexts().map { it.toCss() }, canvas.strings("roleTextCols"), skin.id)
                val sets = listOf(
                    Triple(layerFills(), layerTexts(), 0.10f * 0.9f),
                    Triple(roleFills(), roleTexts(), 0.07f * 0.9f),
                )
                // 画布是 BgBase → Sidebar 的纵向渐变（半透明的先压在页面底上），泳道底压在它之上；两端各算一次
                val bases = listOf(Palette.BgBase, Palette.Sidebar.compositeOver(Palette.BgBase))
                for ((fills, texts, alpha) in sets) {
                    assertEquals(fills.size, texts.size)
                    for (i in fills.indices) {
                        val lanes = bases.map { fills[i].copy(alpha = alpha).compositeOver(it) }
                        for (lane in lanes) {
                            val c = contrastOf(texts[i].compositeOver(lane), lane)
                            assertTrue(c >= 4.5f, "${skin.id} · 泳道 $i · 标签 ${texts[i].toCss()} 压在泳道 ${lane.toCss()} 上只有 ${"%.2f".format(c)}:1")
                        }
                        // 墨是从同一色相的文字级派生的：达标就原样，不达标才被保底推过——不许是另挑的颜色
                        val level = ink(fills[i])
                        val worst = lanes.minOf { contrastOf(level.compositeOver(it), it) }
                        if (worst >= 4.5f) assertEquals(level, texts[i], "${skin.id} · 泳道 $i 本来就达标，不该被改动")
                        stats.add(Triple(skin.id, i, worst))
                    }
                }
            }
            // 体检记录（进测试报告的 system-out）：每套皮肤里最差的一条泳道，以及被保底推过的条目
            stats.groupBy { it.first }.forEach { (id, mine) ->
                println("LANE_INK $id: worst=${"%.2f".format(mine.minOf { it.third })}:1 floored=${mine.count { it.third < 4.5f }}/${mine.size}")
            }
        } finally {
            Skins.apply(Skins.byId.getValue(Skins.DEFAULT_ID))
        }
    }

    @Test
    fun darkSchemeShimOverridesMediaQueryWithoutTouchingBase() {
        assertTrue(DARK_SCHEME_SHIM.contains("matchMedia"), "垫片改写的是产物的明暗探测口")
        assertTrue(DARK_SCHEME_SHIM.contains("prefers-color-scheme"))
        // ⚠️ 不许加 <base>：架构图用 history.pushState 写 '#module=…'，基准 URL 一变就抛 SecurityError
        assertFalse(withHeadScript("<head></head>", DARK_SCHEME_SHIM).contains("<base", ignoreCase = true))
    }
}
