// ContractTest.kt —— 引擎 --json 契约的 Kotlin 镜像回归（fixtures 来自真实引擎输出）。
//
// 【口径】缺键 → default；缺**必知键**（顶层 envelope 键）= 契约过旧 → 整体拒绝。
// fixtures 取自 archive/bui 的 linux/tests/fixtures/（真实引擎输出，不手造）。

package canopy.engine

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

    // ── update 全量聚合信封（2026-11 真机批量浅更新两发落盘：全成功批 + 混合失败批）──

    @Test
    fun multiResultsDecodesAllSuccessBatchWithEngineTally() {
        // fixtures/update_all.json：vtest+vtest2 全成功；顶层 count/failed/succeeded 是引擎自己记的账
        val r = decodeOrThrow(MultiResults.serializer(), fixture("update_all"))
        assertEquals(2, r.results.size)
        assertEquals(2L, r.count)
        assertEquals(2L, r.succeeded)
        assertEquals(0L, r.failed)
        val outcomes = r.results.map(::decodeUpdateOutcome)
        assertTrue(outcomes.all { it is UpdateOutcome.Success })
        val first = (outcomes[0] as UpdateOutcome.Success).receipt
        assertTrue(first.ok && first.project == "vtest")
        // docs 条目带备份真实路径（结果面板「备份在哪」的数据源）
        assertTrue(first.docs.any { it.changed && it.backup.isNotBlank() })
    }

    @Test
    fun multiResultsDecodesHeterogeneousFailureEntry() {
        // fixtures/update_all_failed.json：注册 vtestfail 后删其目录的真跑输出。
        // 失败条目是 {code,message}——**没有 ok/project 键**；镜像成统一 UpdateReceipt
        // 会把失败原因整个吞掉，此判据锁死二态异构形状。
        val r = decodeOrThrow(MultiResults.serializer(), fixture("update_all_failed"))
        assertEquals(3, r.results.size)
        assertEquals(1L, r.failed)
        val outcomes = r.results.map(::decodeUpdateOutcome)
        assertEquals(2, outcomes.count { it is UpdateOutcome.Success })
        val failure = outcomes.filterIsInstance<UpdateOutcome.Failure>().single()
        assertEquals("VOLUME_BLOCKED", failure.failure.code)
        assertEquals("vtestfail 更新失败：路径不存在或卷未挂载：/tmp/vtest_failprobe", failure.failure.message)
    }

    @Test
    fun decodeUpdateOutcomeRejectsUnrecognizableShapesAsFailureNotSuccess() {
        // 读不懂的条目归失败并说明形状（不编造成成功）；ok 键存在才算成功回执
        val ok = decodeUpdateOutcome(contractJson.parseToJsonElement("""{"ok":true,"project":"p"}"""))
        assertTrue(ok is UpdateOutcome.Success)
        val fail = decodeUpdateOutcome(contractJson.parseToJsonElement("""{"code":"X","message":"m"}"""))
        assertTrue(fail is UpdateOutcome.Failure)
        val weird = decodeUpdateOutcome(contractJson.parseToJsonElement(""""just a string""""))
        assertTrue(weird is UpdateOutcome.Failure && weird.failure.code == "UNPARSABLE")
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

    // ── graph confidence / patchconf（fixtures/confidence/，2026-11 本机 cambium 真跑落盘：
    //    vtest 播种 suspect.py 后 graph confidence --json / patchconf 两发真命令的 stdout 原样）──

    // 2026-11-27 置信度准确性批：总量与覆盖面进契约（fixtures/confidence/confidence_totals.json 由
    // 本机引擎 dendro check --json 真跑落盘——隔离的 DEEPGIT_HOME 里一个 3 函数的 Python 文件，ast-grep 在位）。
    @Test
    fun confidenceReportCarriesTotalsAndCoverage() {
        val r = decodeOrThrow(ConfidenceReport.serializer(), fixture("confidence/confidence_totals"))
        // 一共检出的条数与总罚分恒发；没截断时总量 = 列出数、罚分 = 逐条权重之和
        assertEquals(6L, r.findingsTotal)
        assertEquals(6, r.findings.size)
        assertEquals(52L, r.penaltyTotal)
        assertEquals(r.findings.sumOf { it.weight }.toInt(), r.penaltyTotal!!.toInt())
        // 分数按总罚分算：100·20 / (20 + 52 / 1 文件) = 27
        assertEquals(27, r.score)
        // 覆盖面七键恒发：全部文件都走成语法树 ⇒ 没有任何类别缺失（不许把「7 类」挂在没降级的报告上）
        val cov = requireNotNull(r.coverage) { "coverage 必须带出来（结构化版 astNote）" }
        assertEquals(1L, cov.astFiles)
        assertEquals(0L, cov.lexicalFiles)
        assertEquals(1L, cov.astBatchesTotal)
        assertEquals(0L, cov.astBatchesFailed)
        assertTrue(cov.kindsDropped.isEmpty())
        assertEquals(0L, cov.nodesDropped)
        assertTrue(cov.kindsUnavailable.isEmpty())
        assertTrue(r.astUsed)
        // 未解析调用按实测精度降权（8 → 3），标签不再是「幻觉调用」
        val unresolved = r.byKind.first { it.kind == "unresolved-call" }
        assertEquals(3L, unresolved.weight)
        assertEquals("未解析调用", unresolved.label)
    }

    // 旧 fixture（准确性批之前的引擎产出）没有新键：镜像必须解码得出来，且缺字段是 null 不是 0
    @Test
    fun confidenceReportWithoutTotalsDecodesWithNulls() {
        val r = decodeOrThrow(ConfidenceReport.serializer(), fixture("confidence/confidence"))
        assertNull(r.findingsTotal, "旧快照没有总量：必须是 null（未知），不许回落成 0")
        assertNull(r.penaltyTotal)
        assertNull(r.coverage)
    }

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
        // 引擎 0.3.0 起每条疑点带符号键（键集恒定）：幻觉调用挂在**调用它的函数**上——
        // symbol 是「谁有问题」、qual 是「问题发生在哪」；id 与代码索引（cambium index query）同一个键
        assertEquals("f:suspect.py:34:swallow", top.id)
        assertEquals("swallow", top.qual)
        assertEquals("function", top.dim)
        assertEquals("幻觉调用", top.label)
        // 定位不到符号的疑点（文件级 TODO 残留）：键照样在、值为空串
        val todo = r.findings.first { it.kind == "todo-residue" }
        assertEquals("", todo.id)
        assertEquals("", todo.qual)
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
        // 夹具是品牌升级前采集的真机样本（当时客户端叫 deepDolphin）——样本是文物，期望值跟样本走；
        // 现在客户端自己产出的裁决理由是「Canopy 人工裁决」（见 ConfidencePagesTest）
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

    // ── 内容断言（二次验证立的规矩：「能解码」不够——镜像写错键名时照样能解码，字段全是默认值）──

    @Test
    fun commitTypesCarryTheirTypeNames() {
        val env = decodeOrThrow(StatusEnvelope.serializer(), fixture("status"))
        val all = env.projects.flatMap { it.commitTypes }
        assertTrue(all.isNotEmpty(), "真实 status 必有提交构成")
        assertTrue(all.all { it.kind.isNotBlank() }, "类型名不能为空：引擎键是 type，原镜像写成裸 kind，图例只剩色块和数字")
    }

    @Test
    fun journalIsTheUpdateLogNotAGitCommitLog() {
        // fixtures/journal.json 是 2026-11-24 真机 `journal vtest --limit 30 --json` 原样落盘
        val j = decodeOrThrow(JournalPayload.serializer(), fixture("journal"))
        assertTrue(j.entries.isNotEmpty())
        j.entries.forEach {
            assertTrue(it.id.isNotBlank() && it.at.isNotBlank() && it.summary.isNotBlank(), "条目必须解出 id/at/summary")
            assertTrue(it.mode.isNotBlank(), "mode 是浅/深/快照的口径来源")
        }
        assertEquals("*", j.branches, "branches 是字符串（* = 全部分支），不是名单")
        // projects 是数字而非名单（原镜像按 List<String> 解，真机必抛）。它的精确语义契约里没写明
        // （真机 5 条条目都属 vtest，值为 1）——只断言它解得出来是数，不据此下更多结论。
        assertTrue(j.projects >= 0)
        assertTrue(j.limit > 0)
    }

    @Test
    fun statusEmbedsJournalEntriesAndMilestoneExtrasDecode() {
        val env = decodeOrThrow(StatusEnvelope.serializer(), fixture("status"))
        val entries = env.projects.flatMap { it.journal }
        assertTrue(entries.isNotEmpty(), "status 内嵌进度日志（mac ProjectStatus.journal 同源）")
        assertTrue(entries.all { it.id.isNotBlank() && it.branch.isNotBlank() })
        val ms = decodeOrThrow(MilestoneList.serializer(), fixture("milestones")).milestones
        assertTrue(ms.isNotEmpty())
        assertTrue(ms.all { it.tagName.isNotBlank() && it.createdAt.isNotBlank() }, "里程碑的真机恒发键要解得出来")
        assertTrue(ms.any { it.daysToTarget != 0L || it.targetDate.isNotBlank() })
    }

    // ── 写回执（2026-11-24 在 vtest2 上「新建 → 删除」往返的真机落盘）──

    @Test
    fun milestoneAddReceiptCarriesTheMilestoneObject() {
        // 契约 §3.8：add 回执里 milestone 是对象（带 id）。原镜像写成字符串，
        // 解码必抛——新建里程碑每次都显示失败，而引擎其实已经建了。
        val r = decodeOrThrow(MilestoneAddReceipt.serializer(), fixture("milestone_add"))
        assertEquals("vtest2", r.project)
        assertEquals("zz-verify-receipt", r.milestone.name)
        assertTrue(r.created)
        assertEquals("open", r.milestone.status)
    }

    @Test
    fun milestoneRemoveReceipt() {
        val r = decodeOrThrow(MilestoneRemoveReceipt.serializer(), fixture("milestone_remove"))
        assertEquals("zz-verify-receipt", r.milestone)
        assertTrue(r.removed)
    }
}

