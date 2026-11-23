// ConfidencePagesTest.kt —— 置信度页 / 补丁体检页纯函数判据
//（fixture 取自真机引擎：fixtures/confidence/ 由本机 moongit 真跑落盘，零手造）。
//
// 判据只增不减：阈值全部对位 mac 基准（highWeightOnly ≥ 8 / 低置信度 < 0.75 /
// 裁决置信度 resolved 0.9 · unresolved 0.05 · ambiguous 0.5），不发明口径。

package deepdolphin.ui

import deepdolphin.engine.ConfFinding
import deepdolphin.engine.PatchEntity
import java.io.File
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ConfidencePagesTest {

    @BeforeTest
    fun pinZh() {
        // 断言锚定 zh 文案：钉住语言，防宿主 locale / settings.conf 漂移翻红
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    private fun fixture(name: String): String {
        val f = File("src/jvmTest/resources/fixtures/confidence/$name")
        check(f.isFile) { "fixture 缺失：${f.absolutePath}" }
        return f.readText()
    }

    private fun finding(weight: Long, file: String = "a.py") = ConfFinding(
        kind = "k$weight", file = file, line = 1, symbol = "s", evidence = "e", weight = weight,
    )

    // ── 高权重筛选（mac highWeightOnly 对位：≥ 8 这一档）──

    @Test
    fun highWeightFilterKeepsWeightAtLeastEightWhenEnabled() {
        val fs = listOf(finding(8), finding(7), finding(3), finding(10))
        assertEquals(listOf(8L, 10L), highWeightFindings(fs, true).map { it.weight })
    }

    @Test
    fun highWeightFilterOffKeepsEngineOrderUntouched() {
        val fs = listOf(finding(3), finding(10))
        assertEquals(fs, highWeightFindings(fs, false), "关着 = 引擎全序原样（不重排）")
    }

    // ── 低置信度补丁实体（mac lowConfidenceEntities 对位：< 0.75 升序）──

    private fun entity(confidence: Double, file: String = "a.py") =
        PatchEntity(id = "$confidence", kind = "func", confidence = confidence, file = file, line = 1)

    @Test
    fun lowConfidenceEntitiesFilterBelowPointSevenFiveSortedAscending() {
        val ents = listOf(entity(0.9), entity(0.6), entity(0.74), entity(0.1), entity(0.75))
        val lows = lowConfidencePatchEntities(ents)
        assertEquals(listOf(0.1, 0.6, 0.74), lows.map { it.confidence }, "0.75 本身不算低；最不可信的排最前")
    }

    // ── 裁决 → agent 载荷（mac uncertainRow 绑定映射 + merge items 构造对位）──

    @Test
    fun verdictConfidenceMapsThreeStates() {
        assertEquals(0.9, verdictConfidence("resolved"))
        assertEquals(0.05, verdictConfidence("unresolved"))
        assertEquals(0.5, verdictConfidence("ambiguous"))
        assertEquals(0.5, verdictConfidence("anything-else"), "未知裁决按 ambiguous 档，不崩")
    }

    @Test
    fun agentVerdictItemsCarryConfidenceAndReason() {
        val payload = agentVerdictItems(mapOf("a@f:1" to "resolved", "b@f:2" to "unresolved", "c@f:3" to "ambiguous"))
        assertEquals(3, payload.items.size)
        val resolved = payload.items.first { it.id == "a@f:1" }
        assertEquals(0.9, resolved.confidence)
        assertEquals("deepDolphin 人工裁决", resolved.reason)
        assertEquals(0.05, payload.items.first { it.id == "b@f:2" }.confidence)
        assertEquals(0.5, payload.items.first { it.id == "c@f:3" }.confidence)
    }

    // ── 信号 chip（null = 分母 0，契约要求如实披露）──

    @Test
    fun signalChipLabelFormatsValuesAndNulls() {
        assertEquals("S1 50", signalChipLabel("S1", 0.5))
        assertEquals("S5 100", signalChipLabel("S5", 1.0), "1.0 显示满分 100，不是 1")
        assertEquals("S2 0", signalChipLabel("S2", 0.0))
        assertEquals("S4 —", signalChipLabel("S4", null))
        assertTrue(isNullSignal(null))
        assertEquals(false, isNullSignal(0.0), "0 分是事实，不是 null（分母为 0 才是）")
    }

    // ── 终稿警示行（issue 键优先、缺席回退实测的 type 键）──

    @Test
    fun alertLinePrefersIssueKeyAndFallsBackToType() {
        assertEquals(
            "[high] 吞错误 — 有人 catch 了没处理",
            alertLineText(deepdolphin.engine.MergedAlert(level = "high", type = "swallowed_error", issue = "吞错误", detail = "有人 catch 了没处理")),
        )
        assertEquals(
            "[high] swallowed_error — call not found",
            alertLineText(deepdolphin.engine.MergedAlert(level = "high", type = "swallowed_error", issue = null, detail = "call not found")),
        )
    }

    // ── diff hunk 定位（mac CodeSnippet.fromDiff 的位置定位部分；真机 patch.diff 锚定）──

    @Test
    fun extractDiffHunkFindsCoveringHunkFromRealPatch() {
        val diff = fixture("patch.diff")
        // 真机 fixture：实体 new_risky_call@suspect.py:33 落在 hunk @@ -30,6 +30,12 @@ 内
        val hunk = extractDiffHunk(diff, "suspect.py", 33)
        assertTrue(hunk != null && hunk.startsWith("@@ -30,6 +30,12 @@"), "返回头行 + 块体：${hunk?.take(40)}")
        assertTrue(hunk!!.contains("+def new_risky_call(x):"), "新增行在块体里")
    }

    @Test
    fun extractDiffHunkReturnsNullWhenLineNotCovered() {
        val diff = fixture("patch.diff")
        assertNull(extractDiffHunk(diff, "suspect.py", 5), "行不在任何 hunk 的新文件侧覆盖区间")
        assertNull(extractDiffHunk(diff, "other.py", 33), "文件不匹配")
        assertNull(extractDiffHunk("", "suspect.py", 33), "空 diff")
    }

    // ── 实码读一行（findings 披露行展开用；读不出 = null 如实披露）──

    @Test
    fun sourceLineAtReadsLineOrDisclosesNull() {
        val tmp = kotlin.io.path.createTempFile(prefix = "dd-srcline-", suffix = ".py").toFile()
        try {
            tmp.writeText("alpha\nbeta\ngamma\n")
            assertEquals("beta", sourceLineAt(tmp.parent, tmp.name, 2))
            assertNull(sourceLineAt(tmp.parent, tmp.name, 99), "行超界 = null")
            assertNull(sourceLineAt(tmp.parent, "not-exist.py", 1), "文件不在 = null")
            assertNull(sourceLineAt(tmp.parent, tmp.name, 0), "行号 < 1 = null")
        } finally {
            tmp.delete()
        }
    }
}
