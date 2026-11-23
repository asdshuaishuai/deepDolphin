// ContractTest.kt —— 引擎 --json 契约的 Kotlin 镜像回归（fixtures 来自真实引擎输出）。
//
// 【口径】缺键 → default；缺**必知键**（顶层 envelope 键）= 契约过旧 → 整体拒绝。
// fixtures 取自 archive/bui 的 linux/tests/fixtures/（真实引擎输出，不手造）。

package deepdolphin.engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.encodeToString

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

    // ── update（真机回执：journalEntry 是对象，不是布尔）──

    @Test
    fun updateReceiptParsesJournalEntryObject() {
        // 真机 vtest 浅更新输出（journalEntry 曾被误镜像成 Boolean，解析即炸——本用例锁死回归）
        val r = decodeOrThrow(UpdateReceipt.serializer(), fixture("update"))
        assertTrue(r.ok && r.mode == "shallow")
        val j = checkNotNull(r.journalEntry) { "真机回执 journalEntry 必为对象（CONTRACT §2.4）" }
        assertEquals("j_1795443424375_0", j.id)
        assertEquals("main", j.branch)
        assertEquals("new", j.commitCountScope)
        assertEquals(0L, j.commitCount)
        assertTrue(j.highlights.isNotEmpty())
        // docs 键 nullable：契约称仅 deep 条目有，真机浅更新实测也带
        assertEquals(listOf("README.md"), j.docs)
    }

    @Test
    fun updateReceiptToleratesNullJournalEntry() {
        // 聚合信封里的空形状：journalEntry 可为 null（对位 deepin SelfCheck 多项目样例）；
        // 「本轮是否写了日志」= journalEntry != null，不是布尔
        val r = decodeOrThrow(UpdateReceipt.serializer(), """{"ok":true,"mode":"shallow","journalEntry":null}""")
        assertEquals(null, r.journalEntry)
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

    // ── scan：真机输出（fixtures/scan.json，2026-11 真跑锚定：混合新增/已在册 + 1 个不可读目录）──

    @Test
    fun scanPayloadParsesRealShapeWithCandidateArray() {
        // 此前镜像把 candidates/unreadable 镜成 Long（无 fixture 凭空镜像）——真机 scan
        // 一跑解码即失败。此判据锚死真实形状：candidates=对象数组、unreadable=路径数组。
        val r = decodeOrThrow(ScanPayload.serializer(), fixture("scan"))
        assertEquals(3, r.candidates.size, "真机 fixture：3 个候选（1 新增 + 2 已在册）")
        assertEquals(3, r.found)
        assertEquals(1, r.added)
        assertEquals(2, r.existing)
        assertTrue(r.candidates.all { it.path.startsWith("/") && it.kind == "git" }, "候选必带绝对路径与 kind")
        assertEquals(listOf("/tmp/dd-scanarea/blocked"), r.unreadable, "unreadable 是路径数组（不是计数）")
        assertEquals(false, r.truncated, "真机 fixture 恒发布尔（此处 false）")
        assertEquals(false, r.depthCapped)
        assertEquals(2, r.depth)
    }

    @Test
    fun scanPayloadMissingKeysFallBackToDefaults() {
        // 缺键 → default（候选空 + unreadable 空 + 截断旗 null ≠ false），调用方必须自己披露
        val r = decodeOrThrow(ScanPayload.serializer(), """{"found":0,"added":0,"existing":0}""")
        assertEquals(0, r.candidates.size)
        assertEquals(0, r.unreadable.size)
        assertEquals(null, r.truncated)
        assertEquals(null, r.depthCapped)
    }

    // ── graph confidence / patchconf（fixtures/confidence/，2026-11 本机 moongit 真跑落盘：
    //    vtest 播种 suspect.py 后 graph confidence --json / patchconf 两发真命令的 stdout 原样）──

    @Test
    fun confidenceReportParsesRealShape() {
        val r = decodeOrThrow(ConfidenceReport.serializer(), fixture("confidence/confidence"))
        assertEquals(51, r.score)
        assertEquals("/tmp/vtest", r.root)
        assertEquals(1, r.filesAnalyzed)
        // 降级披露恒发非空（ast-grep 缺席 → 词法级），限流披露恒发布尔
        assertTrue(r.astNote.isNotBlank(), "降级披露必须带出来（不许静默）")
        assertEquals(false, r.astUsed)
        assertEquals(false, r.cappedTotal)
        assertEquals(false, r.cappedKind)
        // 维度形状以实测为准：{id,label,penalty,findings,score}（mac 注释的 detail 键引擎不发）
        assertEquals(3, r.dimensions.size, "真机 fixture：只有有疑点的 3 个维度（六维度全集里的）")
        val dim = r.dimensions.first { it.id == "function" }
        assertEquals("函数/对象级", dim.label)
        assertEquals(14, dim.penalty)
        assertEquals(2, dim.findings)
        assertEquals(58, dim.score)
        // findings 按权重降序全序（引擎 sortFindings 契约）
        val weights = r.findings.map { it.weight }
        assertEquals(weights.sortedDescending(), weights, "findings 必须按权重降序")
        assertEquals(4, r.findings.size)
        val top = r.findings.first()
        assertEquals("unresolved-call", top.kind)
        assertEquals("suspect.py", top.file)
        assertEquals(36, top.line)
        assertEquals("risky", top.symbol)
        assertTrue(top.evidence.isNotBlank())
        // 罚分表与按类计数（引擎键 penaltyByFile / byKind，mac 未消费、镜像仍保留）
        assertEquals(listOf(ConfPenaltyFile("suspect.py", 19)), r.penaltyByFile)
        assertEquals(4, r.byKind.size)
        assertTrue(r.semantics.isNotBlank(), "语义边界恒发")
    }

    @Test
    fun patchConfidenceParsesRealShapeWithNullSignals() {
        val p = decodeOrThrow(PatchConfidence.serializer(), fixture("confidence/patchconf_algorithm"))
        assertEquals("moongit-patch-confidence/1", p.schema)
        assertEquals(0.6875, p.overall)
        // null 信号 = 分母 0（契约要求如实披露，不是 0 分）
        assertNull(p.signals["S4"])
        assertNull(p.signals["S7"])
        assertEquals(0.5, p.signals["S1"])
        assertEquals(1.0, p.signals["S5"])
        assertEquals(0.0, p.signals["S2"])
        assertEquals(listOf("S4", "S7"), p.diagnostics.nullSignals)
        assertTrue(p.diagnostics.nullSignalsNote.isNotBlank())
        // 实体与 uncertain 的定位形状
        val e = p.entities.single()
        assertEquals("new_risky_call@suspect.py:33", e.id)
        assertEquals("func", e.kind)
        assertEquals(1.0, e.confidence)
        assertEquals("suspect.py", e.file)
        assertEquals(33, e.line)
        assertEquals(1, e.relations.size)
        assertEquals("calls", e.relations.first().type)
        val u = p.uncertain.single()
        assertEquals("suspect.py@34:risky", u.id)
        assertEquals("unresolved_call", u.issue)
        assertEquals("suspect.py", u.contextRef?.file)
        assertEquals(34, u.contextRef?.line)
        assertEquals(0, p.diagnostics.parseErrors)
        assertEquals(1, p.diagnostics.patchFiles)
        assertEquals(6, p.diagnostics.addedLines)
        assertEquals(1, p.diagnostics.totalEntities)
        assertEquals(2, p.diagnostics.totalRelations)
    }

    @Test
    fun mergedConfidenceParsesRealShape() {
        val m = decodeOrThrow(MergedConfidence.serializer(), fixture("confidence/patchconf_merged"))
        assertEquals("moongit-patch-confidence-merged/1", m.schema)
        assertEquals(0.905, m.overall)
        // 合并实体键并集：algorithm 分支（带 kind/file/line）与 agent 分支（带 verdict/reason）
        assertEquals(2, m.entities.size)
        val alg = m.entities.first { it.source == "algorithm" }
        assertEquals("func", alg.kind)
        assertEquals("suspect.py", alg.file)
        assertEquals(33, alg.line)
        val ag = m.entities.first { it.source == "agent" }
        assertEquals("resolved", ag.verdict)
        assertEquals("deepDolphin 人工裁决", ag.reason)
        assertEquals("suspect.py", ag.contextRef?.file)
        // 计数与来源（实测键位：diagnostics.reviewed_by_agent，mac 注释的顶层 reviewed 键引擎不发）
        assertEquals(1, m.diagnostics.reviewedByAgent)
        assertEquals(1, m.diagnostics.certainFromAlgorithm)
        assertEquals(0, m.diagnostics.deferred)
        assertTrue(m.sources.agent)
        // 本机真跑 alerts 为空（resolved 无警示）；键集 {level,type,detail} 由镜像容错覆盖
        assertEquals(0, m.alerts.size)
        // signals 原样流过终稿（null 键不丢）
        assertNull(m.signals["S4"])
    }

    @Test
    fun mergedAlertToleratesEngineTypeKeyAndLegacyIssueKey() {
        // 实测键集是 {level,type,detail}；issue 键缺席 → null（展示层回退 type，见 alertLineText）
        val a = decodeOrThrow(
            MergedAlert.serializer(),
            """{"level":"high","type":"unresolved_call","detail":"call not found"}""",
        )
        assertEquals("high", a.level)
        assertEquals("unresolved_call", a.type)
        assertNull(a.issue)
    }

    @Test
    fun patchConfidenceRoundTripKeepsNullSignalsForMerge() {
        // merge 的 algorithm 回传必须保住 null 信号键——contractJson(explicitNulls=false)
        // 编码会丢键，引擎侧终稿的 S4/S7 披露随之消失。mergeRoundTripJson 是唯一编码器，
        // 这里判据直接测它（decode→encode→decode 三段不丢事实）。
        val p = decodeOrThrow(PatchConfidence.serializer(), fixture("confidence/patchconf_algorithm"))
        val text = Engine.mergeRoundTripJson.encodeToString(PatchConfidence.serializer(), p)
        assertTrue("\"S4\":null" in text, "null 信号键必须在回传 JSON 里（compact 无空格形状）")
        val back = decodeOrThrow(PatchConfidence.serializer(), text)
        assertEquals(p, back, "decode→encode→decode 全等（忠实往返）")
    }
}
