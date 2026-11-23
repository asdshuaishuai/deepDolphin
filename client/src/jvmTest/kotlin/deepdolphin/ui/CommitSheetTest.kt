// CommitSheetTest.kt —— 提交单勾选策略判据（默认全选 / 部分勾选披露 / 提交门禁）。
//
// 默认勾选口径锚定 mac CommitSheetView.swift:196（装载后 selected = 全部条目）；
// 部分勾选不可提交的口径锚定本机引擎实测：`git commit --paths` RC=2「未知 flag：--paths」
// ——没有子集提交语义，勾选集只作核对清单。判据只增不减。

package deepdolphin.ui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CommitSheetTest {

    // ── 默认勾选：对位 mac（装载即全选）──

    @Test
    fun defaultSelectionChecksEverything() {
        assertEquals(setOf("a.py", "b.txt", "old -> new"), defaultCommitSelection(listOf("a.py", "b.txt", "old -> new")))
    }

    @Test
    fun defaultSelectionOfEmptyListIsEmpty() {
        assertTrue(defaultCommitSelection(emptyList()).isEmpty(), "空清单默认勾选为空（clean 态不走提交）")
    }

    // ── 部分勾选披露：全选/空清单 = null；部分 = 说清「为什么不能提交」──

    @Test
    fun fullSelectionProducesNoNote() {
        assertNull(partialCommitNote(listOf("a", "b"), setOf("a", "b")))
        assertNull(partialCommitNote(emptyList(), emptySet()), "空清单没有「部分」可言")
    }

    @Test
    fun partialSelectionNoteCountsAndNamesTheReason() {
        val note = checkNotNull(partialCommitNote(listOf("a.py", "b.txt", "c.md"), setOf("a.py")))
        assertTrue("已选 1/3" in note, "先给数字：$note")
        assertTrue("--paths" in note, "必须点名引擎限制（实测被拒的参数），不是一句干巴巴的「不可用」：$note")
        assertTrue("无法只提交勾选的子集" in note, "说清勾选集没有子集提交语义：$note")
    }

    @Test
    fun emptySelectionIsAlsoPartial() {
        // 全不选之后：0/2 也是部分勾选（不是第四种状态）
        assertTrue(partialCommitNote(listOf("a", "b"), emptySet()) != null)
    }

    // ── 提交门禁：全选 + 信息拼得出 + 非 busy + 非空清单 + 非干净 ──

    @Test
    fun fullSelectionWithMessageSubmits() {
        assertTrue(canSubmitCommitSheet(listOf("a", "b"), setOf("a", "b"), "feat: x", busy = false, clean = false))
    }

    @Test
    fun partialSelectionNeverSubmits() {
        assertFalse(canSubmitCommitSheet(listOf("a", "b"), setOf("a"), "feat: x", busy = false, clean = false))
        assertFalse(canSubmitCommitSheet(listOf("a", "b"), emptySet(), "feat: x", busy = false, clean = false))
    }

    @Test
    fun blankMessageOrBusyOrEmptyOrCleanBlocks() {
        assertFalse(canSubmitCommitSheet(listOf("a"), setOf("a"), null, busy = false, clean = false), "信息拼不出（commitMessage=null）")
        assertFalse(canSubmitCommitSheet(listOf("a"), setOf("a"), "x", busy = true, clean = false), "引擎在忙")
        assertFalse(canSubmitCommitSheet(emptyList(), emptySet(), "x", busy = false, clean = false), "没有清单（clean 态）")
        assertFalse(canSubmitCommitSheet(listOf("a"), setOf("a"), "x", busy = false, clean = true), "干净工作区引擎必拒，按钮先如实禁用")
    }
}
