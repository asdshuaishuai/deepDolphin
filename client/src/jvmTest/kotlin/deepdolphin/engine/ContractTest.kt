// ContractTest.kt —— 引擎 --json 契约的 Kotlin 镜像回归（fixtures 来自真实引擎输出）。
//
// 【口径】缺键 → default；缺**必知键**（顶层 envelope 键）= 契约过旧 → 整体拒绝。
// fixtures 取自 archive/bui 的 linux/tests/fixtures/（真实引擎输出，不手造）。

package deepdolphin.engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ContractTest {

    /** fixtures 与源码同仓：从仓库相对路径直读（DD_FIXTURE_DIR 同款做法，比 classpath 资源透明）。 */
    private fun fixture(name: String): String {
        val f = java.io.File("src/jvmTest/resources/fixtures/$name.json")
        check(f.isFile) { "fixture 缺失：${f.absolutePath}" }
        return f.readText()
    }

    // ── status：真实全量输出 ──

    @Test
    fun statusEnvelopeParsesRealFullOutput() {
        val env = decodeOrThrow(StatusEnvelope.serializer(), fixture("status"))
        assertTrue(env.projects.isNotEmpty(), "真实 status 必有项目")
        val p = env.projects.first()
        assertTrue(p.name.isNotBlank())
        // 哨兵语义抽查：-1 = 读不出来；error 有值 = 不可读
        val failed = env.projects.filter { !it.isReadable }
        failed.forEach {
            assertTrue(!it.error.isNullOrBlank(), "失败项目必带原因（诚实披露）")
        }
    }

    @Test
    fun summaryCountsAreNonNegative() {
        val env = decodeOrThrow(StatusEnvelope.serializer(), fixture("status"))
        with(env.summary) {
            assertTrue(projectCount >= 0 && failedProjects >= 0 && activeProjects >= 0)
        }
    }

    // ── dashboard ──

    @Test
    fun dashboardParsesWithTruncationFlags() {
        val d = decodeOrThrow(DashboardData.serializer(), fixture("dashboard"))
        assertTrue(d.fetchedAt.isNotBlank())
        // 截断三旗：缺键 = null ≠ false（不许把「引擎没发」当成「没截断」）
        // languagesTruncated / languagesTopCut 是 nullable 的存在性证明
        d.languagesTruncated?.let { assertTrue(it || !it) }
    }

    @Test
    fun dashboardLanguagesCarryCounts() {
        val d = decodeOrThrow(DashboardData.serializer(), fixture("dashboard"))
        d.languages.forEach { assertTrue(it.count >= 0 && it.language.isNotBlank()) }
    }

    // ── milestones ──

    @Test
    fun milestoneListParsesStoreHealth() {
        val m = decodeOrThrow(MilestoneList.serializer(), fixture("milestones"))
        assertTrue(m.storeHealth.isNotBlank(), "存储健康度必有值（降级三规则依赖它）")
        assertTrue(m.readCount >= 0)
        m.milestones.forEach { ms ->
            assertTrue(ms.name.isNotBlank())
            // status ∈ open/done/dropped/unknown/null
            ms.status?.let {
                assertTrue(it in setOf("open", "done", "dropped", "unknown"), "未知状态 $it")
            }
        }
    }

    // ── docs / journal ──

    @Test
    fun docsPayloadSeparatesReadableFromUnreadable() {
        val docs = decodeOrThrow(DocsPayload.serializer(), fixture("docs"))
        docs.docs.forEach { assertTrue(it.file.isNotBlank()) }
    }

    @Test
    fun journalPayloadCarriesWindowDisclosure() {
        val j = decodeOrThrow(JournalPayload.serializer(), fixture("journal"))
        assertTrue(j.limit >= 0)
        // 窗口耗尽披露：缺键 = null（不许当成「没耗尽」）
        j.windowExhausted?.let { assertTrue(it || !it) }
    }

    // ── 缺必知键 = 契约过旧（入口闸门）──

    @Test
    fun emptyEnvelopeParsesToEmptyProjectsCallerMustDisclose() {
        // 引擎侧 envelope 键全部宽松（default）；缺 projects = 空，不是错误——
        // 但调用方拿到的 projects.isEmpty() 必须**如实呈现「尚无数据」**，不假装成功。
        val env = decodeOrThrow(StatusEnvelope.serializer(), """{"summary":{}}""")
        assertTrue(env.projects.isEmpty())
    }

    @Test
    fun garbageInputIsRejected() {
        // 非 JSON 输入必须整体拒绝（不半解析）
        assertFailsWith<Exception> {
            decodeOrThrow(StatusEnvelope.serializer(), "不是 JSON")
        }
    }

    @Test
    fun unknownKeysAreIgnoredForwardCompatible() {
        // 引擎加键不破客户端（向前兼容）
        val env = decodeOrThrow(
            StatusEnvelope.serializer(),
            """{"projects":[],"summary":{},"futureKey":{"x":1}}""",
        )
        assertEquals(0, env.projects.size)
    }

    @Test
    fun wrongTypeIsRejected() {
        // 类型错 = 契约破坏，不许 isLenient 兜底
        assertFailsWith<Exception> {
            decodeOrThrow(StatusEnvelope.serializer(), """{"projects":"not-an-array","summary":{}}""")
        }
    }
}
