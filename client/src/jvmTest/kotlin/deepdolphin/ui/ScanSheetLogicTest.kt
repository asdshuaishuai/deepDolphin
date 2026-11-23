// ScanSheetLogicTest.kt —— 扫描单纯函数判据（mac PathInput / ScanCoverage 的对位机制，
// 输出形状差异以真机引擎实测为准：candidates 不带逐项目归属标记、unreadable 是路径数组）。
//
// 判据只增不减：路径三态判定、整备、逐项目归属推导、聚合行与覆盖度披露的成立条件。

package deepdolphin.ui

import deepdolphin.engine.ScanCandidate
import deepdolphin.engine.ScanPayload
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ScanSheetLogicTest {

    // ── scanRootProblem：磁盘三态不压成 Bool（「不存在」和「是文件」是两句不同的话）──

    @Test
    fun blankPathIsItsOwnProblem() {
        assertEquals("路径还没填", scanRootProblem("", PathKind.MISSING))
        assertEquals("路径还没填", scanRootProblem("   ", PathKind.MISSING))
    }

    @Test
    fun missingAndFileAreSeparateProblems() {
        assertEquals("路径不存在（先确认拼对了没有）", scanRootProblem("/nope", PathKind.MISSING))
        assertEquals("这是文件，不是目录（这里要目录）", scanRootProblem("/tmp/a.txt", PathKind.FILE))
        assertNull(scanRootProblem("/tmp", PathKind.DIRECTORY))
    }

    // ── prepareScanRoot：按钮可用性挂在这里（首尾空格如实修，引擎实测对 " /path " 直接失败）──

    @Test
    fun prepareTrimsWhitespaceAndRequiresDirectory() {
        val classify: (String) -> PathKind = { p -> if (p == "/tmp") PathKind.DIRECTORY else PathKind.MISSING }
        assertEquals("/tmp", prepareScanRoot("  /tmp  ", classify), "首尾空格修掉再交给引擎")
        assertNull(prepareScanRoot("  /tmp ", { PathKind.FILE }), "文件不可用")
        assertNull(prepareScanRoot("   ", { PathKind.DIRECTORY }), "空白不可用")
        assertNull(prepareScanRoot("/missing", { PathKind.MISSING }), "不存在不可用")
    }

    // ── scanRows：逐项目归属 = 候选 × 扫描前在册集（引擎 payload 只有聚合数的推导补位）──

    private fun cand(name: String, path: String) = ScanCandidate(name = name, path = path)

    @Test
    fun rowsDeriveExistingFromPreScanRegistry() {
        val rows = scanRows(
            candidates = listOf(cand("a", "/x/a"), cand("b", "/x/b")),
            registeredPaths = setOf("/x/b"),
        )
        assertEquals(2, rows.size)
        assertEquals(false, rows[0].existing, "不在扫描前在册集 → 新增")
        assertEquals(true, rows[1].existing, "在扫描前在册集 → 已在册")
    }

    @Test
    fun rowMatchingToleratesTrailingSlash() {
        val rows = scanRows(listOf(cand("a", "/x/a/")), setOf("/x/a"))
        assertEquals(true, rows.single().existing, "尾斜杠两侧都 trimEnd 再比")
    }

    @Test
    fun emptyCandidatesYieldEmptyRows() {
        assertTrue(scanRows(emptyList(), setOf("/x/a")).isEmpty())
    }

    // ── scanCoverageNote：三种「没看完」分开说；found=0 且没扫完不许断言「没有」──

    @Test
    fun fullCoverageHasNoNote() {
        assertNull(scanCoverageNote(found = 3, truncated = false, depthCapped = false, unreadableCount = 0))
        assertNull(scanCoverageNote(found = 3, truncated = null, depthCapped = null, unreadableCount = 0))
    }

    @Test
    fun threeIncompleteCausesAreListedSeparately() {
        val note = scanCoverageNote(found = 2, truncated = true, depthCapped = true, unreadableCount = 4)
        assertTrue(note!!.contains("撞到扫描深度上限"), "成因一：深度")
        assertTrue(note.contains("撞到目录数量上限"), "成因二：目录数")
        assertTrue(note.contains("4 个目录读不出来"), "成因三：不可读")
        assertTrue(note.contains("列出的不是全部"), "有发现时口径是「不是全部」")
    }

    @Test
    fun foundZeroAndIncompleteMustNotClaimEmpty() {
        val note = scanCoverageNote(found = 0, truncated = null, depthCapped = true, unreadableCount = 0)
        assertTrue(note!!.contains("只代表已访问的那部分里没有"), "「没扫完」和「没有」不许互换（对位 mac 缺陷 #197 第二出口）")
    }

    // ── scanAggregateLine：聚合行以引擎口径为准 ──

    @Test
    fun aggregateLineCountsFromEnginePayload() {
        val r = ScanPayload(found = 3, added = 1, existing = 2, dirsVisited = 5)
        assertEquals("发现 3 · 新增 1 · 已在册 2 · 访问目录 5", scanAggregateLine(r))
    }

    @Test
    fun emptyTreeClaimOnlyWhenScanActuallyCompleted() {
        // 扫完了（无任何「没看完」旗）才许说「没有 git 仓库」——引擎验证过的结论
        val clean = ScanPayload(found = 0, added = 0, existing = 0, truncated = false, depthCapped = false)
        assertTrue(scanAggregateLine(clean).contains("该目录树里没有 git 仓库"))

        // 没扫完（depthCapped=true）→ 改说「只代表已访问部分」，两句话不许并排出现
        val capped = ScanPayload(found = 0, added = 0, existing = 0, truncated = false, depthCapped = true)
        val line = scanAggregateLine(capped)
        assertTrue(!line.contains("该目录树里没有 git 仓库"), "未扫完不许断言「没有」")
        assertTrue(line.contains("只代表已访问的那部分里没有"))
    }

    @Test
    fun unreadableDirectoriesSurfaceInAggregateNote() {
        val r = ScanPayload(found = 1, added = 1, unreadable = listOf("/tmp/blocked"))
        assertTrue(scanAggregateLine(r).contains("1 个目录读不出来"))
    }
}
