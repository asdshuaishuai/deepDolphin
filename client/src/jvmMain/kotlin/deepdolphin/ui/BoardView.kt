// BoardView.kt —— 看板页（对位 mac BoardView.swift：项目级 liveness 分列）。
//
// 【看板回答的是另一个问题】
// 仪表盘回答「整体怎么样」；看板回答「**现在哪些项目要我动手**」——
// 按可执行性分列，不按规模或字母。
//
// 【分列规则在模型层，本文件只映射列】（对位 mac BoardView.swift:8-14 的纪律）
// 判定是 `livenessOf`（本文件顶部纯函数层，对位 mac Models.swift:564-590
// ProjectStatus.liveness），列映射 `boardColumnOf` 只消费判定结果、不重算。
// 原实现按**分支级**引擎档位分列（archive/bui 纪律）：一条分支一张卡。
// mac 已否决那个口径——`branches` 是**追踪数组**，无远端基线的仓库恒为空，
// 于是「久未更新」列会靠 `lastCommitAt` 才能救回的项目永远进不了列；
// 引擎档位（active/idle/stale/merged）是分支属性，回答不了「**项目**还要不要动」。
// 本批对位 mac：列 = 项目级 liveness，行 = 项目卡；分支级信息收进卡片
// （分支名/待记录数 chip、已跟踪/仓库分支数披露）。
//
// 【列判据写明】（对位 mac「列判据写明」纪律，L10n zh board.basis.* 原文）
//   待处理   —— 有未提交、未跟踪、stash 或待合入的分支；
//   活跃中   —— 30 天内有过新提交；
//   久未更新 —— 超过 30 天没有新提交（引擎 active30d 那条线）；
//   其他     —— 采集失败、非 git，或提交时间读不出来。
// 空列也保持在场并写明判据：读者需要知道「这里为什么空」，
// 「0」既可能是「真没有」也可能是「没量出来」。
//
// 【与 mac 的差异，如实标注】mac BoardPage 的项目集合走 model.dashFilter
// （仪表盘时间窗筛选，BoardView.swift:102-104）；CMP 仪表盘的时间窗是页面局部
// 状态且尚未作用于任何列表（DashboardView 既有边界），看板先看全量在册项目，
// 不伪造一个不存在的联动。
//
// 【列表纪律】列头计数与行数同源（同一个 List.size，不存在两套口径）；
//   空列如实披露；采集失败项目只落「其他」列（带引擎原因原文），绝不混进
//   liveness 状态列——把失败项目混进「久未更新」会让看板说「这个项目很闲」，
//   而真相是「这个项目没被读出来」。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import deepdolphin.engine.Project
import deepdolphin.engine.StatusEnvelope
import deepdolphin.ui.Palette
import deepdolphin.ui.Space
import deepdolphin.ui.Type

// ══════════════════════════════════════════════════════════════════════
// 模型层判定（对位 mac Models.swift:503-614 的 Liveness / needsAction /
// daysSinceLastCommit / stateWord；纯函数，jvmTest 的 BoardContractTest 直测）
// ══════════════════════════════════════════════════════════════════════

/**
 * 这个项目**还在不在动**（对位 mac Models.swift:523-538）。看板分列与项目卡
 * 状态词的唯一依据——同一个问题只允许有一个判定点。
 */
enum class Liveness {
    /** 采集失败：所有计数都是未知（-1 哨兵），不是 0。 */
    UNREADABLE,
    /** 非 git 项目：没有提交历史可谈。 */
    NOT_GIT,
    /** 有东西等着动手（未提交/未跟踪/stash/待合入分支/合并建议）。 */
    NEEDS_ACTION,
    /** 引擎判定为停滞（只有追踪到基线的分支才可能给出）。 */
    ENGINE_STALE,
    /** 30 天以上没有新提交（引擎 active30d 那条线）。 */
    QUIET,
    /** 30 天内有新提交。 */
    RECENT,
    /** 提交时间读不出来——「不知道」，不许折进上面任何一档。 */
    UNKNOWN,
}

/**
 * 距最后一次提交多少天。null = **读不出来**（非 git / 缺键 / 时间解析不了）。
 *
 * 算术与引擎**逐字一致**（mac Models.swift:445-457 同款）：先换算毫秒差再**整除**
 * 86_400_000，不用浮点天数——两者在负数（未来时间戳）和边界上会差一天，
 * 而边界正是 30 天那条分列线。nowMs 作参数注入（默认系统时钟）供判据钉时间。
 */
fun daysSinceLastCommit(p: Project, nowMs: Long = System.currentTimeMillis()): Int? {
    if (p.lastCommitAt.isBlank()) return null
    return try {
        val at = java.time.OffsetDateTime.parse(p.lastCommitAt).toInstant().toEpochMilli()
        ((nowMs - at) / 86_400_000L).toInt()
    } catch (_: java.time.format.DateTimeParseException) {
        null
    }
}

/**
 * 待处理信号（对位 mac Models.swift:558-562 needsAction）：
 * 有未提交 / 未跟踪 / stash / 待合入的分支 / 引擎合并建议（merge|fast-forward）。
 *
 * ⚠️ 分支那一项判 `isMergeCandidate`（aheadOfDefault > 0 && !isDefault && !merged，
 * 逐字对齐引擎 flow/dashboard.cj:206-209），**不是** pendingCommits——
 * 那是「引擎还没记录的提交数」，刚跑过 update 恒为 0，与能不能合无关；
 * 引擎专门为此写了回归测试，客户端不许把刚修掉的错再犯一遍。
 * 计数键缺席（null，旧引擎）按「读不出这一路信号」处理（不算 >0），
 * 最终档位由 liveness 后续证据（分支档位/提交时间）兜底。
 */
fun needsAction(p: Project): Boolean =
    (p.userDirtyCount ?: 0) > 0 || (p.untrackedCount ?: 0) > 0 || (p.stashCount ?: 0) > 0 ||
        p.branches.any { it.isMergeCandidate } ||
        (p.mergeHint?.kind == "merge" || p.mergeHint?.kind == "fast-forward")

/**
 * liveness 判定（对位 mac Models.swift:564-590）。顺序是**纪律**，不许调换：
 * 1. 采集失败 → UNREADABLE（所有计数都是未知）；
 * 2. 非 git → NOT_GIT；
 * 3. **needsAction 必须排在 engineStale 前面**——两者不互斥，先命中哪个纯属
 *    书写顺序，而「待处理」列自己的定义就是「有未提交/未跟踪/stash 或待合入的
 *    分支」：一个有待合入分支的项目无论主分支多停滞都该进这一列（mac
 *    Models.swift:567-585 用真 app 现场「侧栏看板 1 vs 仪表盘待处理 3」钉过）；
 * 4. 引擎档位 stale 最精确，但只在引擎真的给出一行分支记录时才有；
 * 5. 引擎恒发 lastCommitAt 推出的天数：≤30 → RECENT，>30 → QUIET；
 *    读不出来 → UNKNOWN（不许折进任何一档）。
 */
fun livenessOf(p: Project, nowMs: Long = System.currentTimeMillis()): Liveness {
    if (!p.isReadable) return Liveness.UNREADABLE
    if (!p.isGit) return Liveness.NOT_GIT
    if (needsAction(p)) return Liveness.NEEDS_ACTION
    if (p.primaryBranch?.status == "stale") return Liveness.ENGINE_STALE
    val age = daysSinceLastCommit(p, nowMs) ?: return Liveness.UNKNOWN
    return if (age <= 30) Liveness.RECENT else Liveness.QUIET
}

/** 状态词（项目卡用，对位 mac Models.swift:599-611 stateWord）：只从事实推，不写修辞。 */
fun stateWordOf(l: Liveness, quietDays: Int? = null): String = when (l) {
    Liveness.UNREADABLE -> "读不出来"
    Liveness.NOT_GIT -> "非 git 目录"
    Liveness.NEEDS_ACTION -> "有未提交改动"
    Liveness.ENGINE_STALE -> "停滞"
    // 措辞跟着依据走：用的是 30 天那条线，写「停滞」会让人以为是引擎的 14 天档位。
    Liveness.QUIET -> "${quietDays ?: "?"} 天没更新"
    Liveness.RECENT -> "正常"
    Liveness.UNKNOWN -> "状态读不出来"
}

// ══════════════════════════════════════════════════════════════════════
// 列映射（对位 mac BoardView.swift:31-89：BoardColumn + boardColumn 扩展）
// ══════════════════════════════════════════════════════════════════════

/**
 * 看板列（顺序即展示顺序，对位 mac BoardColumn.allCases：待处理/活跃中/久未更新/其他）。
 * basis = 判据文案（mac L10n zh「board.basis.*」原文）——空列时读者必须能读到
 * 「这列为什么空」；界面常驻展示（列判据写明纪律）。
 */
enum class BoardColumnId(val title: String, val basis: String) {
    ATTENTION("待处理", "有未提交、未跟踪、stash 或待合入的分支"),
    ACTIVE("活跃中", "30 天内有过新提交"),
    QUIET("久未更新", "超过 30 天没有新提交（引擎 active30d 那条线）"),
    OTHER("其他", "采集失败、非 git，或提交时间读不出来"),
}

/** 这个项目该进哪一列（对位 mac BoardView.swift:81-88）。**只读 liveness，不自己判。 */
fun boardColumnOf(l: Liveness): BoardColumnId = when (l) {
    Liveness.NEEDS_ACTION -> BoardColumnId.ATTENTION
    Liveness.RECENT -> BoardColumnId.ACTIVE
    Liveness.ENGINE_STALE, Liveness.QUIET -> BoardColumnId.QUIET
    Liveness.UNREADABLE, Liveness.NOT_GIT, Liveness.UNKNOWN -> BoardColumnId.OTHER
}

/** 一张项目卡的数据（字段全部来自引擎或模型层判定，客户端不推断）。 */
data class BoardCard(
    val name: String,
    val liveness: Liveness,
    /** 模型层状态词（stateWordOf 产物）。 */
    val stateText: String,
    /** 采集失败原因（引擎原文）；null = 可读。 */
    val error: String?,
    val headline: String?,
    val warnings: List<String>,
    /** 用户改动/未跟踪/stash 计数（-1 = 读不出来，卡片按 >0 才亮 chip）。 */
    val dirtyCount: Long?,
    val untrackedCount: Long?,
    val stashCount: Long?,
    /** 当前分支 chip：追踪数组拿得到用主分支名，拿不到退引擎声明的 currentBranch 串；
     *  两者都空 = null（「没有分支记录」和「没声明」都不是「没有分支」）。 */
    val branchChip: String?,
    /** 主分支的待记录数（pendingCommits）；null = 没有分支记录可读。 */
    val pendingCommits: Long?,
    /** 距最后一次提交天数；null = 读不出来（不是「没有提交历史」）。 */
    val daysSinceLastCommit: Int?,
    /** 引擎追踪到的分支数与仓库真实分支数（null = 读不出来）。两者不等 ⇒ 卡内披露。 */
    val trackedBranchCount: Int,
    val repoBranchCount: Long?,
)

/** 看板模型：列分配的唯一产物。columns 覆盖全部 BoardColumnId（空列也在场）。 */
data class BoardModel(val columns: Map<BoardColumnId, List<BoardCard>>) {
    fun cardsIn(id: BoardColumnId): List<BoardCard> = columns[id].orEmpty()
    fun count(id: BoardColumnId): Int = cardsIn(id).size

    /** 全部项目卡数 = 各列行数之和（每个项目恰好一列，不存在第二套口径）。 */
    val totalProjects: Int get() = BoardColumnId.entries.sumOf { count(it) }
}

/** status --json → 看板。判定/映射/卡片字段全在这一个纯函数里产出，UI 不重算。 */
fun boardModelOf(projects: List<Project>, nowMs: Long = System.currentTimeMillis()): BoardModel {
    val columns = BoardColumnId.entries.associateWith { mutableListOf<BoardCard>() }
    for (p in projects) {
        val l = livenessOf(p, nowMs)
        val days = daysSinceLastCommit(p, nowMs)
        val primary = p.primaryBranch
        columns.getValue(boardColumnOf(l)) += BoardCard(
            name = p.name,
            liveness = l,
            stateText = stateWordOf(l, days),
            error = p.error,
            headline = p.headline,
            warnings = p.warnings.orEmpty(),
            dirtyCount = p.userDirtyCount,
            untrackedCount = p.untrackedCount,
            stashCount = p.stashCount,
            branchChip = primary?.name ?: p.currentBranch?.takeIf { it.isNotBlank() },
            pendingCommits = primary?.pendingCommits,
            daysSinceLastCommit = days,
            trackedBranchCount = p.branches.size,
            repoBranchCount = p.repoBranchCount,
        )
    }
    return BoardModel(columns)
}

/** 从信封取看板模型（status 为 null 时给空模型——UI 层先披露「正在读取」，不假装空看板）。 */
fun boardModelOf(env: StatusEnvelope?, nowMs: Long = System.currentTimeMillis()): BoardModel =
    boardModelOf(env?.projects.orEmpty(), nowMs)

// ══════════════════════════════════════════════════════════════════════
// 渲染
// ══════════════════════════════════════════════════════════════════════

/** 列的语义点色（只走 Palette；映射是展示层，不参与列分配）。对位 mac BoardColumn.color。 */
private fun columnTone(id: BoardColumnId): Color = when (id) {
    BoardColumnId.ATTENTION -> Palette.Amber
    BoardColumnId.ACTIVE -> Palette.Green
    BoardColumnId.QUIET -> Palette.TextSecondary
    BoardColumnId.OTHER -> Palette.TextSecondary
}

/** 状态词颜色（对位 mac BoardCard.stateColor 的 tone 映射）。 */
private fun stateTone(l: Liveness): Color = when (l) {
    Liveness.UNREADABLE, Liveness.UNKNOWN -> Palette.Red
    Liveness.NOT_GIT -> Palette.TextSecondary
    Liveness.NEEDS_ACTION -> Palette.Amber
    Liveness.ENGINE_STALE, Liveness.QUIET -> Palette.TextSecondary
    Liveness.RECENT -> Palette.Green
}

@Composable
fun BoardPage(model: AppModel) {
    val status by model.status.collectAsState()
    val statusState by model.statusState.collectAsState()
    val refreshing by model.refreshing.collectAsState()

    // 判定/列映射纯函数在组合外跑不了（Compose 里用 remember 按信封缓存）。
    val board = remember(status) { boardModelOf(status) }

    Column(
        Modifier.fillMaxSize().padding(horizontal = Space.xl, vertical = Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.lg),
    ) {
        // ── 页头 ──
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("看板", style = Type.title)
                Spacer(Modifier.height(Space.xs))
                Text(
                    buildString {
                        val total = status?.projects?.size ?: 0
                        append("$total 个项目按 liveness 分列 · 待处理 ${board.count(BoardColumnId.ATTENTION)}")
                        append(" · 活跃中 ${board.count(BoardColumnId.ACTIVE)} · 久未更新 ${board.count(BoardColumnId.QUIET)}")
                        append(" · 其他 ${board.count(BoardColumnId.OTHER)}")
                    },
                    style = Type.label,
                )
            }
            Button(
                onClick = { model.refreshAll() },
                enabled = !refreshing,
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
            ) { Text(if (refreshing) "刷新中…" else "刷新") }
        }

        // ── 读取三态分开说（「还没读到」「读不出来」「读到 0 个」是三句话）──
        when (statusState) {
            LoadState.Loading -> Banner("正在读取项目清单…", Palette.TextSecondary)
            is LoadState.Failed ->
                Banner(
                    "项目清单读不出来：${(statusState as LoadState.Failed).reason}——下面没有列，不是「没有项目」",
                    Palette.Amber,
                )
            LoadState.Loaded -> {}
        }

        // ── 列区（status 读到了才渲染列；失败/读取中不渲染，避免「空看板」冒充真相）──
        if (statusState is LoadState.Loaded) {
            // List + Section 分组形态（对位 mac：窄窗口一列纵排、原生分组标题，不横向滚动）。
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(Space.lg),
            ) {
                BoardColumnId.entries.forEach { id ->
                    BoardColumnUi(id, board, model) { p ->
                        model.goRoute(AppModel.Route.PROJECT, p)
                    }
                }
            }
        }
    }
}

/** 一列：列头（点色 + 标题 + 计数）+ 判据 + 卡片（或空态披露）。 */
@Composable
private fun BoardColumnUi(id: BoardColumnId, board: BoardModel, model: AppModel, onOpenProject: (String) -> Unit) {
    val cards = board.cardsIn(id)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.card))
            .background(Palette.Card)
            .border(1.dp, Palette.Stroke, RoundedCornerShape(Radius.card))
            .padding(Space.md),
    ) {
        // 列头计数与 cards 同源（同一个 List.size），不存在两套口径。
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).background(columnTone(id), CircleShape))
            Spacer(Modifier.width(Space.sm))
            Text(id.title, style = Type.section)
            Spacer(Modifier.weight(1f))
            Text("${cards.size}", style = Type.card.copy(color = columnTone(id), fontWeight = FontWeight.Bold))
        }
        Spacer(Modifier.height(Space.xs))
        // 列判据常驻（对位 mac「列判据写明」纪律；mac 空列时展示同一段文案）。
        Text(id.basis, style = Type.micro)

        Spacer(Modifier.height(Space.sm))
        Column(verticalArrangement = Arrangement.spacedBy(Space.sm)) {
            if (cards.isEmpty()) {
                // 空列如实披露：说「没有项目落在这列」，判据已在列头——不写「暂无数据」。
                Text("没有项目落在这列", style = Type.body.copy(color = Palette.TextSecondary))
            } else {
                cards.forEach { c -> ProjectCard(c, model, onOpenProject) }
            }
        }
    }
}

/**
 * 项目卡（对位 mac BoardView.swift:139-294 BoardCard 的行内容）：
 * 名字 + 状态词 →（失败=原因红字 / 可读=headline + warnings + 信号 chip 行）→
 * 分割线 → 动作（浅更新 / AI 说明）+ 最后提交时间。
 */
@Composable
private fun ProjectCard(c: BoardCard, model: AppModel, onOpenProject: (String) -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Palette.CardHover)
            .clickable { onOpenProject(c.name) }
            .padding(Space.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(c.name, style = Type.card, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.width(Space.sm))
            Text(c.stateText, style = Type.label.copy(color = stateTone(c.liveness)), maxLines = 1)
        }
        if (c.error != null) {
            // 采集失败：引擎原因原文（不推断、不翻译），红字——这是「读不出来」不是「状态差」。
            Spacer(Modifier.height(Space.xs))
            Text(c.error.ifBlank { "引擎未给原因" }, style = Type.micro.copy(color = Palette.Red), maxLines = 2, overflow = TextOverflow.Ellipsis)
        } else {
            c.headline?.takeIf { it.isNotBlank() }?.let {
                Spacer(Modifier.height(Space.xs))
                Text(it, style = Type.micro, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            // warnings：引擎说「需要你知道、但不算失败」的话（如「0 个提交」最容易被当成事实）。
            c.warnings.forEach { w ->
                Text("⚠ $w", style = Type.micro.copy(color = Palette.Amber), maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.height(Space.xs))
            // 信号 chip 行（对位 mac chips）：脏/未跟踪/stash/待记录/分支名。
            // 计数 -1（读不出来）不亮 chip——不知道 ≠ 0，也不该冒充「有」。
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Space.xs),
            ) {
                if ((c.dirtyCount ?: 0) > 0) Pill("●${c.dirtyCount}", Palette.Amber)
                if ((c.untrackedCount ?: 0) > 0) Pill("未跟踪 ${c.untrackedCount}", Palette.Amber)
                if ((c.stashCount ?: 0) > 0) Pill("stash ${c.stashCount}", Palette.TextSecondary)
                if ((c.pendingCommits ?: 0) > 0) Pill("${c.pendingCommits} 待记录", Palette.Accent)
                // 分支 chip：追踪数组拿不到时退回引擎声明的当前分支名。
                c.branchChip?.let { Pill("分支 $it", Palette.TextSecondary) }
            }
            // 分支列表不全披露（旧看板保留下来的引擎事实）：仓库分支多于引擎返回，
            // 上面的分支/待记录 chip 可能缺行——不把「没返回」当「不存在」。
            if ((c.repoBranchCount ?: -1L) > c.trackedBranchCount) {
                Spacer(Modifier.height(Space.xs))
                Text(
                    "分支列表不全：已跟踪 ${c.trackedBranchCount} / 仓库共 ${c.repoBranchCount}",
                    style = Type.micro.copy(color = Palette.Amber),
                )
            }
        }

        Spacer(Modifier.height(Space.sm))
        Box(Modifier.fillMaxWidth().height(1.dp).background(Palette.Stroke))
        Spacer(Modifier.height(Space.sm))

        // 底部动作行（对位 mac：浅更新 + AI 说明在左，最后提交时间在右——
        // 看板的价值就是「多久没人动它」，只写「暂无新变化」回答不了这个问题）。
        val busy by model.busyAction.collectAsState()
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            ActionText("浅更新", Palette.Shallow, enabled = !busy) { model.updateProject(c.name, deep = false) }
            ActionText("说明", Palette.Ai, enabled = !busy) { model.openAgent(briefTask(c.name), title = "项目说明 · ${c.name}") }
            Spacer(Modifier.weight(1f))
            Text(
                when (val d = c.daysSinceLastCommit) {
                    null -> "提交时间读不出来"
                    0 -> "今天提交过"
                    else -> "$d 天前提交"
                },
                style = Type.micro,
                maxLines = 1,
            )
        }
    }
}

/** 页级横幅（读取中 / 读不出来）。 */
@Composable
private fun Banner(text: String, tone: Color) {
    Text(
        text,
        style = Type.body.copy(color = tone),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Palette.Card)
            .border(1.dp, Palette.Stroke, RoundedCornerShape(8.dp))
            .padding(horizontal = Space.md, vertical = Space.sm),
    )
}
