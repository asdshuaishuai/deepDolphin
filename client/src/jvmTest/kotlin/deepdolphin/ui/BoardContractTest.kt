// BoardContractTest.kt —— 看板（C3 board 列视图）列分配纯函数的契约回归。
//
// 【fixture 为准】真实引擎输出（src/jvmTest/resources/fixtures/status.json）里
//   branch.status 实测口径：active（atlas 4 条）/ stale（legacy 2 条）/ idle（beacon 1 条）。
//   失败项目（gone/newbie/fresh）branches 为空且 error 有值；plainly 可读但零分支（非 git）。
// 【判据】列分配只读引擎 status 原值；未收录/缺键进 UNKNOWN 不丢行；
//   读不出来的项目绝不落进任何状态列；空列保持在场且计数为 0。

package deepdolphin.ui

import deepdolphin.engine.Project
import deepdolphin.engine.StatusEnvelope
import deepdolphin.engine.decodeOrThrow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BoardContractTest {

    /** fixtures 与源码同仓：从仓库相对路径直读（与 ContractTest 同款做法）。 */
    private fun fixture(name: String): String {
        val f = java.io.File("src/jvmTest/resources/fixtures/$name.json")
        check(f.isFile) { "fixture 缺失：${f.absolutePath}" }
        return f.readText()
    }

    private fun realStatus(): StatusEnvelope = decodeOrThrow(StatusEnvelope.serializer(), fixture("status"))

    // ── 列分配：真实引擎输出 ──

    @Test
    fun columnsAllocateByEngineStatusFromRealFixture() {
        val board = boardModelOf(realStatus())
        // fixtures 实测：active=atlas 4 条 / stale=legacy 2 条 / idle=beacon 1 条 / merged=0。
        assertEquals(
            setOf(
                "atlas" to "main", "atlas" to "feature/b1", "atlas" to "feature/b2", "atlas" to "feature/b3",
            ),
            board.rowsIn(BoardColumnId.ACTIVE).map { it.project to it.branch }.toSet(),
            "引擎 status=active 的分支必须全落「活跃」列",
        )
        assertEquals(
            setOf("legacy" to "main", "legacy" to "old/branch"),
            board.rowsIn(BoardColumnId.STALE).map { it.project to it.branch }.toSet(),
            "引擎 status=stale 的分支必须全落「停滞」列",
        )
        assertEquals(
            setOf("beacon" to "main"),
            board.rowsIn(BoardColumnId.IDLE).map { it.project to it.branch }.toSet(),
            "引擎 status=idle 的分支必须全落「闲置」列",
        )
        assertEquals(0, board.count(BoardColumnId.MERGED))
        assertEquals(0, board.count(BoardColumnId.UNKNOWN))
        // 卡片字段如实透传（引擎原值，不加工）。
        val b3 = board.rowsIn(BoardColumnId.ACTIVE).first { it.branch == "feature/b3" }
        assertEquals(1L, b3.aheadOfDefault)
        assertEquals("f4b11a71", b3.headShort)
        assertEquals("刚刚", b3.headAgo)
        assertEquals(true, b3.isCurrent.not()) // 当前检出的是 main
        // beacon/main 的 headShort 缺键 → headKnown=false（读不出来 ≠ 没有提交）。
        val beaconMain = board.rowsIn(BoardColumnId.IDLE).single()
        assertTrue(!beaconMain.headKnown, "beacon/main headShort 缺键必须判为读不出来")
        assertTrue(beaconMain.isDefault, "beacon/main 实测 isDefault=true")
        // 总数 = 各状态列行数之和（UNREADABLE 是项目列，不计分支）。
        assertEquals(7, board.totalBranches)
    }

    // ── 读不出来态：项目绝不混进状态列 ──

    @Test
    fun unreadableProjectsNeverEnterStatusColumns() {
        val board = boardModelOf(realStatus())
        val failedNames = setOf("gone", "newbie", "fresh")
        // 三个失败项目全部单列，且带引擎原因原文（诚实披露：不给原因 = 违规）。
        assertEquals(failedNames, board.unreadable.map { it.name }.toSet(), "采集失败的项目必须全部单列")
        board.unreadable.forEach {
            assertTrue(!it.error.isNullOrBlank(), "读不出来的项目必须带引擎原因（${it.name}）")
        }
        // 任何状态列（含 UNKNOWN）都不许出现失败项目的分支卡。
        BoardColumnId.entries.forEach { id ->
            board.rowsIn(id).forEach { row ->
                assertTrue(
                    row.project !in failedNames,
                    "失败项目 ${row.project} 的分支混进了 ${id} 列——读不出来 ≠ 没有分支",
                )
            }
        }
        // UNREADABLE 不是分支列：branches 恒空，计数走 unreadable 列表。
        assertEquals(0, board.rowsIn(BoardColumnId.UNREADABLE).size)
    }

    // ── 空态：列保持在场、计数 0、判据文案在场 ──

    @Test
    fun emptyColumnsStayPresentWithZeroCountAndCriteria() {
        // 全部 active 的最小信封：stale/idle/merged/unknown 四列都空。
        val env = decodeOrThrow(
            StatusEnvelope.serializer(),
            """
            {"projects":[{"name":"solo","kind":"git","branches":[
                {"name":"main","status":"active","statusLabel":"活跃","isDefault":true}
            ]}],"summary":{}}
            """.trimIndent(),
        )
        val board = boardModelOf(env)
        // 列模型覆盖全部列（空列也在场，UI 才能如实渲染空列而不是悄悄隐藏）。
        assertEquals(BoardColumnId.entries.toSet(), board.columns.keys, "空列必须保持在场")
        listOf(BoardColumnId.STALE, BoardColumnId.IDLE, BoardColumnId.MERGED, BoardColumnId.UNKNOWN).forEach {
            assertEquals(0, board.count(it), "${it} 列应为空")
            assertTrue(board.rowsIn(it).isEmpty())
        }
        assertEquals(1, board.totalBranches)
        // 每一列都有非空判据：空列时读者必须能读到「这列为什么空」。
        BoardColumnId.entries.forEach {
            assertTrue(it.criteria.isNotBlank(), "${it} 判据缺失")
            assertTrue(it.title.isNotBlank(), "${it} 列名缺失")
        }
    }

    // ── 未知口径：不丢行、不猜语义 ──

    @Test
    fun unknownOrMissingStatusLandsInUnknownColumnWithoutLoss() {
        val env = decodeOrThrow(
            StatusEnvelope.serializer(),
            """
            {"projects":[{"name":"p","kind":"git","branches":[
                {"name":"future-branch","status":"hot-new","statusLabel":"新口径"},
                {"name":"missing-branch"},
                {"name":"main","status":"active","statusLabel":"活跃","isDefault":true}
            ]}],"summary":{}}
            """.trimIndent(),
        )
        val board = boardModelOf(env)
        val unknown = board.rowsIn(BoardColumnId.UNKNOWN)
        // 引擎新口径（hot-new）与缺键（missing-branch）都进 UNKNOWN，且原值保留、不猜成 active。
        assertEquals(2, unknown.size, "未收录口径与缺键都必须落「口径未知」列，不许丢行")
        assertEquals("hot-new", unknown.first { it.branch == "future-branch" }.status)
        assertEquals("", unknown.first { it.branch == "missing-branch" }.status)
        assertEquals(1, board.count(BoardColumnId.ACTIVE))
        assertEquals(3, board.totalBranches, "总分支数 = 三条全在，一条不少")
    }

    // ── 无分支 / 分支不全：如实列出，不静默丢行 ──

    @Test
    fun noBranchAndPartialProjectsAreDisclosedNotDropped() {
        val board = boardModelOf(realStatus())
        // plainly 可读（kind=dir）但零分支：必须出现在披露列表里，不许消失。
        assertTrue("plainly" in board.noBranchProjects, "可读但无分支的项目必须如实披露")
        // beacon 实测 repoBranchCount=2 但只返回 1 条：引擎返回不全要披露（返回 M/N）。
        assertTrue(
            board.partialBranchProjects.any { it.startsWith("beacon") },
            "分支不全的项目必须披露：${board.partialBranchProjects}",
        )
        // 合成的可读 git 项目零分支同样进披露（不只在 fixture 这一个样本上成立）。
        val synthesized = boardModelOf(
            listOf(Project(name = "emptyRepo", kind = "git", error = null, repoBranchCount = 0L)),
        )
        assertTrue("emptyRepo" in synthesized.noBranchProjects)
        assertEquals(0, synthesized.totalBranches)
    }

    // ── 计数同源：列头计数与行数一个来源 ──

    @Test
    fun columnCountsShareSingleSourceWithRows() {
        val board = boardModelOf(realStatus())
        BoardColumnId.entries.forEach {
            assertEquals(board.rowsIn(it).size, board.count(it), "${it} 列头计数与行数必须同源")
        }
        assertEquals(
            board.columns.values.sumOf { it.size },
            board.totalBranches,
            "总分支数必须等于各列行数之和（不存在第二套口径）",
        )
        // 信封重载与列表重载一致（UI 拿的是 StateFlow<StatusEnvelope?>）。
        assertEquals(board.totalBranches, boardModelOf(realStatus()).totalBranches)
        assertEquals(0, boardModelOf(null).totalBranches, "信封缺席 = 空，不是失败（失败由 statusState 披露）")
    }
}
