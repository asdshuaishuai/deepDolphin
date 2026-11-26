// BulkUpdateTest.kt —— 全量更新聚合判据（确认文案 / 逐仓库三态行 / 整批账目与覆盖度披露）。
//
// 数据面锚定两份真机 fixtures（2026-11 本机 cambium 真跑落盘）：
//   · update_all.json —— 全成功批（vtest+vtest2，docs 带 backup 路径）；
//   · update_all_failed.json —— 混合批（2 成功 + 1 失败；失败条目实测是
//     {code:"VOLUME_BLOCKED", message:"vtestfail 更新失败：…"}，**没有 ok/project 键**）。
// 文案口径对位 mac DestructiveGuard.bulkUpdateMessage / UpdateOutcome.updateOutcomeSummary /
// AgentBulkUpdate.Report.tally（措辞纪律照抄：一个词贯穿、失败数不留给读者做减法）。

package canopy.ui

import canopy.engine.DocChange
import canopy.engine.MultiResults
import canopy.engine.UpdateFailure
import canopy.engine.UpdateOutcome
import canopy.engine.UpdateReceipt
import canopy.engine.decodeOrThrow
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BulkUpdateTest {

    @BeforeTest
    fun pinZh() {
        // 断言锚定 zh 文案：钉住语言，防宿主 locale / settings.conf 漂移翻红
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    private fun fixture(name: String): String {
        val f = java.io.File("src/jvmTest/resources/fixtures/$name.json")
        check(f.isFile) { "fixture 缺失：${f.absolutePath}" }
        return f.readText()
    }

    // ── 告知式确认文案（mac DestructiveGuard.bulkUpdateMessage 逐字对位）──

    @Test
    fun confirmMessageForZeroProjectsSaysNothingWillHappen() {
        assertEquals("当前没有已注册的项目，不会做任何事。", bulkUpdateMessage(0, deep = false))
    }

    @Test
    fun confirmMessageShallowSaysWhatAndBackup() {
        assertEquals(
            "将对 1 个项目 执行浅更新：读取 git 历史并改写托管区域（README / AGENTS.md 等）。" +
                "每个被改写的文件都会先留备份，所以可以回滚。",
            bulkUpdateMessage(1, deep = false),
        )
    }

    @Test
    fun confirmMessageDeepNamesAiAndPluralizes() {
        assertEquals(
            "将对 3 个项目 执行深更新：除浅更新外还会调用 AI 重新生成内容。" +
                "每个被改写的文件都会先留备份，所以可以回滚。",
            bulkUpdateMessage(3, deep = true),
        )
    }

    @Test
    fun confirmTitleNamesTrack() {
        assertEquals("全部浅更新？", bulkConfirmTitle(deep = false))
        assertEquals("全部深更新？", bulkConfirmTitle(deep = true))
    }

    // ── 逐仓库三态行（mac updateOutcomeSummary 对位：合成一句话就会撒谎）──

    private fun receipt(project: String = "vtest", docs: List<DocChange> = emptyList()) =
        UpdateReceipt(ok = true, project = project, docs = docs)

    @Test
    fun noDocsReportedIsNotRefreshed() {
        assertEquals("vtest：本次没有需要更新的文档", updateOutcomeLine(receipt()))
    }

    @Test
    fun unchangedDocsAreCalledUnchanged() {
        assertEquals(
            "vtest：文档没有变化（README.md、AGENTS.md）",
            updateOutcomeLine(receipt(docs = listOf(DocChange("README.md"), DocChange("AGENTS.md")))),
        )
    }

    @Test
    fun touchedDocsWithBackupNameTheBackupPath() {
        assertEquals(
            "vtest：已更新 README.md（README.md 的旧版本已备份到 /store/backups/README.md）",
            updateOutcomeLine(
                receipt(docs = listOf(DocChange("README.md", changed = true, backup = "/store/backups/README.md"))),
            ),
        )
    }

    @Test
    fun createdFilesGetNoBackupMention() {
        // 新建 ⇒ 没有旧版本 ⇒ 没有备份：不许给它编一个
        assertEquals(
            "vtest：新建 AGENTS.md",
            updateOutcomeLine(receipt(docs = listOf(DocChange("AGENTS.md", changed = true, created = true)))),
        )
    }

    @Test
    fun listingIsCappedWithRemainderCount() {
        val line = updateOutcomeLine(
            receipt(
                docs = listOf(
                    DocChange("a.md", changed = true),
                    DocChange("b.md", changed = true, created = true),
                    DocChange("c.md", changed = true),
                ),
            ),
            nameMax = 2,
        )
        assertEquals("vtest：已更新 a.md、新建 b.md 等 3 个文档", line)
    }

    // ── 整批账目（真机 fixtures）──

    @Test
    fun allSuccessBatchAggregatesFromRealFixture() {
        val r = decodeOrThrow(MultiResults.serializer(), fixture("update_all"))
        assertEquals(2, r.results.size)
        assertEquals(2L, r.count)
        assertEquals(0L, r.failed)
        val report = BulkReport.of(deep = false, attempted = 2, r = r)
        assertEquals(2, report.succeeded)
        assertEquals(0, report.failed)
        // 措辞纪律（mac 对位）：失败 0 不说「成功 2 · 失败 0」，读者不该自己做减法
        assertEquals("2 个仓库全部成功", report.tally())
        assertNull(report.coverageNote(), "回执条数=名单数，无需披露")
        assertNull(report.tallyMismatchNote())
        assertEquals("全量浅更新 · 2 个仓库", report.title())
        assertEquals("全部浅更新：成功 2 / 共 2 个回执", report.headLine())
        // 真机 fixture 的成功行带备份路径（updateOutcomeLine 走「已更新 + 备份」形）
        val line = (report.outcomes[0] as UpdateOutcome.Success).let { updateOutcomeLine(it.receipt) }
        assertTrue("已备份到" in line, "备份路径必须带到面板行：$line")
    }

    @Test
    fun mixedBatchDecodesFailureEntriesWithReason() {
        val r = decodeOrThrow(MultiResults.serializer(), fixture("update_all_failed"))
        assertEquals(3, r.results.size)
        assertEquals(1L, r.failed)
        val failures = r.results.map { canopy.engine.decodeUpdateOutcome(it) }
            .filterIsInstance<UpdateOutcome.Failure>()
        assertEquals(1, failures.size)
        assertEquals("VOLUME_BLOCKED", failures[0].failure.code)
        assertTrue("vtestfail 更新失败：路径不存在或卷未挂载" in failures[0].failure.message)
        val report = BulkReport.of(deep = true, attempted = 3, r = r)
        assertEquals(2, report.succeeded)
        assertEquals(1, report.failed)
        assertEquals("成功 2 · 失败 1", report.tally())
        assertNull(report.coverageNote())
        assertEquals("全量深度更新 · 3 个仓库", report.title())
    }

    @Test
    fun coverageNoteDisclosesShortfallAgainstRegistry() {
        // 引擎只回 3/5 条：没有回执的仓库不许编状态
        val r = MultiResults(
            results = (1..3).map {
                canopy.engine.contractJson.parseToJsonElement("""{"ok":true,"project":"p$it","docs":[]}""")
            },
        )
        val report = BulkReport.of(deep = false, attempted = 5, r = r)
        assertEquals("引擎只返回 3/5 个仓库的结果，其余没有回执——不在上面编造它们的状态。", report.coverageNote())
    }

    @Test
    fun zeroOutcomesWithRegistrySaysUnknownNotSuccess() {
        val report = BulkReport.of(deep = false, attempted = 2, r = MultiResults())
        assertEquals("引擎没有返回任何仓库结果", report.tally())
        assertEquals(
            "注册表里有 2 个项目，但引擎没有返回任何结果条目——本次每个仓库的实际状态未知。",
            report.coverageNote(),
        )
    }

    @Test
    fun tallyMismatchNoteComparesEngineEnvelopeCount() {
        val r = MultiResults(
            count = 7,
            results = (1..3).map {
                canopy.engine.contractJson.parseToJsonElement("""{"ok":true,"project":"p$it","docs":[]}""")
            },
        )
        assertEquals(
            "引擎信封计数 count=7 与结果条数 3 不一致，以逐条结果为准。",
            BulkReport.of(deep = false, attempted = 3, r = r).tallyMismatchNote(),
        )
        // count=0（引擎没记账）不算分叉——不披露
        assertNull(BulkReport.of(deep = false, attempted = 3, r = MultiResults(count = 0)).tallyMismatchNote())
    }

    @Test
    fun failureRowFallsBackToCodeWhenMessageBlank() {
        // 防御形状：引擎万一发空 message，行上给 code，不说「无原因」三个字都不带
        val f = UpdateFailure(code = "E_X", message = "")
        assertTrue(f.message.isBlank())
    }
}
