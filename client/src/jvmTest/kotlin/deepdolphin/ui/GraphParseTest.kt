// GraphParseTest.kt —— 图谱两页回执/产物路径提取的判据（fixture 取自真机引擎 moongit 真跑，
// 零手造：fixtures/render/ 由 `moongit render <index|arch> vtest [--confidence] [--force]` 重定向落盘）。
//
// 判据只增不减：mac CodeGraphPageVM.receipt / extractHTMLPath / contains("复用") 的机制对位，
// 输出形状差异（路径黏全角冒号、无空格）如实适配并在这里锚死。

package deepdolphin.ui

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
        // fixture 取自 moongit 真跑：生成快照后改源码（索引被自动重建成第 1 版），再 render index --confidence
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

    @Test
    fun darkSchemeShimOverridesMediaQueryWithoutTouchingBase() {
        assertTrue(DARK_SCHEME_SHIM.contains("matchMedia"), "垫片改写的是产物的明暗探测口")
        assertTrue(DARK_SCHEME_SHIM.contains("prefers-color-scheme"))
        // ⚠️ 不许加 <base>：架构图用 history.pushState 写 '#module=…'，基准 URL 一变就抛 SecurityError
        assertFalse(withHeadScript("<head></head>", DARK_SCHEME_SHIM).contains("<base", ignoreCase = true))
    }
}
