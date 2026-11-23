// BoardContractTest.kt —— 看板 liveness 分列的契约回归（对位 mac BoardView.swift /
// Models.swift:503-614：判定在模型层、列映射只消费判定）。
//
// 【fixture 为准】真实引擎输出（src/jvmTest/resources/fixtures/status.json）：
//   atlas（stash 2）/ beacon（mergeHint fast-forward）/ legacy（untracked 1）→ 待处理；
//   gone/newbie/fresh（error）+ plainly（kind=dir）→ 其他。
// 【判据】liveness 判定顺序（失败 > 非 git > 待处理 > 引擎停滞 > 30 天线）；
//   needsAction 的分支项逐字对齐引擎 mergeCandidates 判据（aheadOfDefault，
//   不是 pendingCommits）；读不出来的项目绝不落进 liveness 状态列；
//   空列保持在场且判据文案在场；列头计数与行数同源、每个项目恰好一列。

package deepdolphin.ui

import deepdolphin.engine.Branch
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

    /** 钉住「现在」：fixture 里 lastCommitAt 是 2026-08/09/10 月的旧时间戳，
     *  判定必须可重复——nowMs 作参数注入（默认系统时钟），判据用固定基准。 */
    private val nowMs: Long =
        java.time.OffsetDateTime.parse("2026-10-03T10:00:00+08:00").toInstant().toEpochMilli()

    private fun boardOf(env: StatusEnvelope?) = boardModelOf(env, nowMs)

    // ── 列分配：真实引擎输出（判定在模型层，列只映射）──

    @Test
    fun columnsFollowModelLivenessFromRealFixture() {
        val board = boardOf(realStatus())
        // fixtures 实测：stash/mergeHint/untracked 把三个可读 git 项目全部顶进「待处理」。
        assertEquals(
            setOf("atlas", "beacon", "legacy"),
            board.cardsIn(BoardColumnId.ATTENTION).map { it.name }.toSet(),
            "有待处理信号的项目必须落「待处理」列（liveness.needsAction）",
        )
        assertEquals(0, board.count(BoardColumnId.ACTIVE), "fixture 时间基准下无 30 天内提交的项目")
        assertEquals(0, board.count(BoardColumnId.QUIET))
        assertEquals(
            setOf("gone", "newbie", "fresh", "plainly"),
            board.cardsIn(BoardColumnId.OTHER).map { it.name }.toSet(),
            "采集失败（3 个）与非 git（plainly）必须落「其他」列",
        )
        // 状态词走模型层 stateWord，不读分支档位：atlas 主分支 active，
        // 但 stash 2 ⇒ 状态词是「有未提交改动」。
        assertEquals("有未提交改动", board.cardsIn(BoardColumnId.ATTENTION).first { it.name == "atlas" }.stateText)
    }

    @Test
    fun livenessOrderIsDisciplineNotAccident() {
        // 1) needsAction 必须排在 engineStale 前面（mac Models.swift:567-585）：
        //    有待合入分支的项目无论主分支多停滞都该进「待处理」。
        val staleAndDirty = Project(
            name = "stale-dirty", kind = "git", untrackedCount = 1L,
            branches = listOf(Branch(name = "main", status = "stale", isDefault = true, isCurrent = true)),
        )
        assertEquals(Liveness.NEEDS_ACTION, livenessOf(staleAndDirty, nowMs))
        assertEquals(BoardColumnId.ATTENTION, boardColumnOf(livenessOf(staleAndDirty, nowMs)))
        // 2) 非 git 排在 needsAction 前面：dir 项目没有提交历史可谈，脏度不是它的语言。
        val dirtyDir = Project(name = "dirty-dir", kind = "dir", userDirtyCount = 1L, untrackedCount = 1L)
        assertEquals(Liveness.NOT_GIT, livenessOf(dirtyDir, nowMs))
        assertEquals(BoardColumnId.OTHER, boardColumnOf(livenessOf(dirtyDir, nowMs)))
        // 3) 只有引擎停滞档位、无待处理信号 ⇒ ENGINE_STALE →「久未更新」列。
        val staleOnly = Project(
            name = "stale-only", kind = "git", lastCommitAt = "2026-08-01T10:00:00+08:00",
            branches = listOf(Branch(name = "main", status = "stale", isDefault = true, isCurrent = true)),
        )
        assertEquals(Liveness.ENGINE_STALE, livenessOf(staleOnly, nowMs))
        assertEquals(BoardColumnId.QUIET, boardColumnOf(livenessOf(staleOnly, nowMs)))
    }

    @Test
    fun daysSinceLastCommitUsesIntegerDivisionAnd30DayLine() {
        fun p(at: String) = Project(name = "t", kind = "git", lastCommitAt = at)
        // 30 天整 → RECENT；31 天 → QUIET（引擎 active30d 那条线，≤30 含边界）。
        assertEquals(30, daysSinceLastCommit(p("2026-09-03T10:00:00+08:00"), nowMs))
        assertEquals(31, daysSinceLastCommit(p("2026-09-02T10:00:00+08:00"), nowMs))
        assertEquals(Liveness.RECENT, livenessOf(p("2026-09-03T10:00:00+08:00"), nowMs))
        assertEquals(Liveness.QUIET, livenessOf(p("2026-09-02T10:00:00+08:00"), nowMs))
        // 整除不进位：30 天又 23 小时仍是 30（浮点口径会在边界差一天）。
        assertEquals(30, daysSinceLastCommit(p("2026-09-02T11:00:00+08:00"), nowMs))
        // 读不出来（缺键 / 解析不了）→ UNKNOWN，不许折进任何一档。
        assertEquals(null, daysSinceLastCommit(p(""), nowMs))
        assertEquals(null, daysSinceLastCommit(p("not-a-time"), nowMs))
        assertEquals(Liveness.UNKNOWN, livenessOf(Project(name = "u", kind = "git"), nowMs))
        assertEquals(BoardColumnId.OTHER, boardColumnOf(Liveness.UNKNOWN))
    }

    @Test
    fun mergeCandidateRuleMatchesEngineVerbatim() {
        fun proj(branch: Branch, hint: String? = null) = Project(
            name = "m", kind = "git",
            branches = listOf(branch),
            mergeHint = hint?.let { deepdolphin.engine.MergeHint(kind = it) },
        )
        // ahead > 0 && !isDefault && !merged（flow/dashboard.cj:206-209 逐字）。
        assertTrue(Branch(name = "f", aheadOfDefault = 1L).isMergeCandidate)
        assertEquals(Liveness.NEEDS_ACTION, livenessOf(proj(Branch(name = "f", aheadOfDefault = 1L)), nowMs))
        // ⚠️ pendingCommits 不算：那是「引擎还没记录的提交数」，刚 update 完恒为 0，
        // 与能不能合无关——引擎专门修掉过的错，客户端不许再犯。
        assertEquals(
            Liveness.RECENT,
            livenessOf(
                Project(
                    name = "p", kind = "git", lastCommitAt = "2026-09-03T10:00:00+08:00",
                    branches = listOf(Branch(name = "f", pendingCommits = 5L)),
                ),
                nowMs,
            ),
        )
        // 默认分支不需要合进自己；已合过的分支不再提示。
        assertTrue(!Branch(name = "main", aheadOfDefault = 2L, isDefault = true).isMergeCandidate)
        assertTrue(!Branch(name = "f", aheadOfDefault = 2L, merged = true).isMergeCandidate)
        // 引擎合并建议（mergeHint kind = merge / fast-forward）也算待处理。
        assertEquals(Liveness.NEEDS_ACTION, livenessOf(proj(Branch(name = "main", isDefault = true), "fast-forward"), nowMs))
        assertEquals(Liveness.NEEDS_ACTION, livenessOf(proj(Branch(name = "main", isDefault = true), "merge"), nowMs))
        // fixture 的 beacon 正是这条路：分支档位 idle、无脏度，靠 mergeHint fast-forward 进待处理。
        assertEquals(
            Liveness.NEEDS_ACTION,
            livenessOf(realStatus().projects.first { it.name == "beacon" }, nowMs),
        )
    }

    // ── 读不出来态：项目绝不混进 liveness 状态列 ──

    @Test
    fun unreadableProjectsLandOnlyInOtherColumn() {
        val board = boardOf(realStatus())
        val failedNames = setOf("gone", "newbie", "fresh")
        // 失败项目全部落「其他」列，且带引擎原因原文（诚实披露：不给原因 = 违规）。
        failedNames.forEach { name ->
            val card = board.cardsIn(BoardColumnId.OTHER).first { it.name == name }
            assertTrue(!card.error.isNullOrBlank(), "读不出来的项目必须带引擎原因（$name）")
        }
        // 任何 liveness 状态列都不许出现失败项目——读不出来 ≠ 停滞/活跃/待处理。
        listOf(BoardColumnId.ATTENTION, BoardColumnId.ACTIVE, BoardColumnId.QUIET).forEach { id ->
            board.cardsIn(id).forEach { card ->
                assertTrue(
                    card.name !in failedNames,
                    "失败项目 ${card.name} 混进了 $id 列——读不出来 ≠ 没有状态",
                )
            }
        }
    }

    // ── 空态：列保持在场、计数 0、判据文案在场 ──

    @Test
    fun emptyColumnsStayPresentWithBasisAndZeroCount() {
        // 只有待处理信号的单项目信封：活跃中/久未更新/其他三列都空。
        val env = decodeOrThrow(
            StatusEnvelope.serializer(),
            """
            {"projects":[{"name":"solo","kind":"git","stashCount":1,"branches":[
                {"name":"main","status":"active","statusLabel":"活跃","isDefault":true}
            ]}],"summary":{}}
            """.trimIndent(),
        )
        val board = boardOf(env)
        // 列模型覆盖全部列（空列也在场，UI 才能如实渲染空列而不是悄悄隐藏）。
        assertEquals(BoardColumnId.entries.toSet(), board.columns.keys, "空列必须保持在场")
        assertEquals(1, board.count(BoardColumnId.ATTENTION))
        listOf(BoardColumnId.ACTIVE, BoardColumnId.QUIET, BoardColumnId.OTHER).forEach {
            assertEquals(0, board.count(it), "$it 列应为空")
            assertTrue(board.cardsIn(it).isEmpty())
        }
        // 每一列都有非空判据：空列时读者必须能读到「这列为什么空」（列判据写明纪律）。
        BoardColumnId.entries.forEach {
            assertTrue(it.basis.isNotBlank(), "${it} 判据缺失")
            assertTrue(it.title.isNotBlank(), "${it} 列名缺失")
        }
    }

    // ── 计数同源：列头计数与行数一个来源、每个项目恰好一列 ──

    @Test
    fun columnCountsShareSingleSourceAndEveryProjectLandsExactlyOneColumn() {
        val board = boardOf(realStatus())
        BoardColumnId.entries.forEach {
            assertEquals(board.cardsIn(it).size, board.count(it), "$it 列头计数与行数必须同源")
        }
        // 8 个在册项目每个恰好出现一次（谁也不被静默丢行，谁也不重复占列）。
        val names = BoardColumnId.entries.flatMap { board.cardsIn(it).map { c -> c.name } }
        assertEquals(realStatus().projects.size, names.size)
        assertEquals(names.toSet().size, names.size, "同一项目不许出现在两列")
        assertEquals(names.size, board.totalProjects, "总项目数 = 各列行数之和（不存在第二套口径）")
        // 信封缺席 = 空，不是失败（失败由 statusState 披露）。
        assertEquals(0, boardOf(null).totalProjects)
    }

    // ── 状态词：只从事实推，不写修辞（对位 mac stateWord）──

    @Test
    fun stateWordFollowsLivenessFacts() {
        assertEquals("正常", stateWordOf(Liveness.RECENT))
        assertEquals("40 天没更新", stateWordOf(Liveness.QUIET, 40))
        assertEquals("停滞", stateWordOf(Liveness.ENGINE_STALE))
        assertEquals("有未提交改动", stateWordOf(Liveness.NEEDS_ACTION))
        assertEquals("非 git 目录", stateWordOf(Liveness.NOT_GIT))
        assertEquals("读不出来", stateWordOf(Liveness.UNREADABLE))
        // UNKNOWN 的措辞必须是「读不出来」——「不知道」不许折进任何一档。
        assertEquals("状态读不出来", stateWordOf(Liveness.UNKNOWN))
        // 卡片字段如实透传：legacy 的 untracked=1 与分支摘要在卡上（引擎原值，不加工）。
        val legacy = boardOf(realStatus()).cardsIn(BoardColumnId.ATTENTION).first { it.name == "legacy" }
        assertEquals(1L, legacy.untrackedCount)
        assertEquals(2, legacy.trackedBranchCount)
        assertEquals(2L, legacy.repoBranchCount)
    }
}
