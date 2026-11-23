// BoardView.kt —— 看板页（C3 board 列视图，批 5 从 stub 变真实现）。
//
// 【信息架构】参照 archive/bui views/board.rs 的列纪律（列判据写明 / 列头计数与行数
//   同源 / 空列如实披露 / 读不出来单列），行对象按本客户端的引擎口径：
//   一条分支（status --json 的 branches[]）= 一张卡；列 = 引擎发的 branch.status
//   原值（active/stale/idle/merged，fixtures 与 macos StatusColor 实测口径）。
//   页面里没有第二份判据：列分配只读引擎原值，不重算引擎已给的结论。
//
// 【读不出来单列】采集失败（error 有值）的项目不是「没有分支」也不是「闲置」，
//   是「没读到」。单独一列 + 引擎原因原文；不许混进任何状态列——把失败项目
//   混进闲置列会让看板说「这个项目很闲」，而真相是「这个项目没被读出来」。
//
// 【列表不全要披露】beacon 实测 repoBranchCount=2 但 branches[] 只返回 1 条，
//   summary.branchCount=8 而 branches 总数 7：引擎计数与返回行不是一回事。
//   这类项目在页头如实披露「返回 M/N」，不把「没返回」当「不存在」。
//
// 【空列】写「没有分支落在这列」+ 该列判据，不写「暂无数据」——读者需要知道
//   「为什么这里会空」。列头计数 = 该列 List 的 size，不存在两套口径。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import deepdolphin.engine.Branch
import deepdolphin.engine.Project
import deepdolphin.engine.StatusEnvelope
import deepdolphin.ui.Palette
import deepdolphin.ui.Space
import deepdolphin.ui.Type

// ══════════════════════════════════════════════════════════════════════
// 列分配纯函数（jvmTest 的 BoardContractTest 直测这一段）
// ══════════════════════════════════════════════════════════════════════

/** 看板列（顺序即展示顺序）。判据文案 = 空列时如实告诉读者「这里为什么空」。 */
enum class BoardColumnId(val title: String, val criteria: String) {
    ACTIVE("活跃", "引擎分支状态 active：近期有提交。"),
    STALE("停滞", "引擎分支状态 stale：久未更新。"),
    IDLE("闲置", "引擎分支状态 idle：当前无活动。"),
    MERGED("已合入", "引擎分支状态 merged：已并入默认分支。"),
    UNKNOWN("口径未知", "状态缺键、unknown 或引擎新增而本客户端未收录的口径——原值展示，不猜。"),
    UNREADABLE("读不出来", "项目采集失败（error）。这不是「闲置」也不是「没有分支」，是「没读到」。"),
}

/** 一张分支卡的数据（字段全部来自引擎，客户端不推断）。 */
data class BoardRow(
    val project: String,
    val branch: String,
    /** 引擎 status 原值（缺键 = 空串）。列分配用它，卡片上原样展示。 */
    val status: String,
    val statusLabel: String,
    val isDefault: Boolean,
    val isCurrent: Boolean,
    val headShort: String,
    val headAgo: String,
    val headSubject: String,
    /** 相对默认分支的领先数；isDefault = true 时它没有意义，卡片不展示。 */
    val aheadOfDefault: Long,
    val baselineReset: Boolean,
) {
    /** headShort 缺键/空 = 最近提交读不出来（不是「没有提交历史」）。 */
    val headKnown: Boolean get() = headShort.isNotBlank()
}

/** 读不出来列的一行：项目 + 引擎原因原文。 */
data class UnreadableProject(val name: String, val error: String?)

/** 看板模型：列分配的唯一产物。columns 覆盖全部 BoardColumnId（空列也在场）。 */
data class BoardModel(
    val columns: Map<BoardColumnId, List<BoardRow>>,
    /** 采集失败的项目（引擎 error 原文随行）。 */
    val unreadable: List<UnreadableProject>,
    /** 可读但没有分支的项目（非 git / 尚无分支）——如实列出，不静默丢行。 */
    val noBranchProjects: List<String>,
    /** repoBranchCount > branches.size 的项目：引擎返回的分支不全。 */
    val partialBranchProjects: List<String>,
    /** 全部分支卡数 = 各状态列行数之和（UNREADABLE 是项目列，不计分支）。 */
    val totalBranches: Int,
) {
    fun rowsIn(id: BoardColumnId): List<BoardRow> = columns[id].orEmpty()
    fun count(id: BoardColumnId): Int = rowsIn(id).size
}

/** 引擎 status 原值 → 列。未收录/缺键一律进 UNKNOWN，不丢行、不猜语义。 */
fun boardColumnOf(status: String): BoardColumnId = when (status) {
    "active" -> BoardColumnId.ACTIVE
    "stale" -> BoardColumnId.STALE
    "idle" -> BoardColumnId.IDLE
    "merged" -> BoardColumnId.MERGED
    else -> BoardColumnId.UNKNOWN
}

fun boardRowOf(project: Project, b: Branch): BoardRow = BoardRow(
    project = project.name,
    branch = b.name,
    status = b.status,
    statusLabel = b.statusLabel,
    isDefault = b.isDefault,
    isCurrent = b.isCurrent,
    headShort = b.headShort,
    headAgo = b.headAgo,
    headSubject = b.headSubject,
    aheadOfDefault = b.aheadOfDefault,
    baselineReset = b.baselineReset,
)

/** 整个 status --json → 看板。失败项目单列；无分支项目如实列出；不重算引擎口径。 */
fun boardModelOf(projects: List<Project>): BoardModel {
    val columns = BoardColumnId.entries.associateWith { mutableListOf<BoardRow>() }
    val unreadable = mutableListOf<UnreadableProject>()
    val noBranch = mutableListOf<String>()
    val partial = mutableListOf<String>()
    for (p in projects) {
        if (!p.isReadable) {
            unreadable += UnreadableProject(p.name, p.error)
            continue
        }
        if (p.branches.isEmpty()) {
            noBranch += p.name
            continue
        }
        val known = p.repoBranchCount ?: -1L
        if (known > p.branches.size) partial += "${p.name}（引擎返回 ${p.branches.size}/$known）"
        for (b in p.branches) columns.getValue(boardColumnOf(b.status)) += boardRowOf(p, b)
    }
    val rows = columns.values.sumOf { it.size }
    return BoardModel(columns, unreadable, noBranch, partial, totalBranches = rows)
}

/** 从信封取看板模型（status 为 null 时给空模型——UI 层先披露「正在读取」，不假装空看板）。 */
fun boardModelOf(env: StatusEnvelope?): BoardModel = boardModelOf(env?.projects.orEmpty())

// ══════════════════════════════════════════════════════════════════════
// 渲染
// ══════════════════════════════════════════════════════════════════════

/** 列的语义点色（只走 Palette；映射是展示层，不参与列分配）。 */
private fun columnTone(id: BoardColumnId): Color = when (id) {
    BoardColumnId.ACTIVE -> Palette.Green
    BoardColumnId.STALE -> Palette.Red
    BoardColumnId.IDLE -> Palette.Amber
    BoardColumnId.MERGED -> Palette.Purple
    BoardColumnId.UNKNOWN -> Palette.TextSecondary
    BoardColumnId.UNREADABLE -> Palette.Red
}

@Composable
fun BoardPage(model: AppModel) {
    val status by model.status.collectAsState()
    val statusState by model.statusState.collectAsState()
    val refreshing by model.refreshing.collectAsState()

    // 列分配纯函数在组合外跑不了（Compose 里用 remember 按信封缓存）。
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
                        append("$total 个项目 · ${board.totalBranches} 条分支按引擎状态分列")
                        if (board.unreadable.isNotEmpty()) append(" · 读不出来 ${board.unreadable.size}")
                        if (board.noBranchProjects.isNotEmpty()) append(" · 无分支 ${board.noBranchProjects.size}")
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
                    "项目清单读不出来：${(statusState as LoadState.Failed).reason}——下面没有列，不是「没有分支」",
                    Palette.Amber,
                )
            LoadState.Loaded -> {}
        }

        // ── 披露行：分支不全 / 无分支项目（引擎事实，客户端不推断）──
        if (board.partialBranchProjects.isNotEmpty()) {
            Text(
                "分支列表不全（仓库分支多于引擎返回，卡片可能缺行）：${board.partialBranchProjects.joinToString("、")}",
                style = Type.micro.copy(color = Palette.Amber),
            )
        }
        if (board.noBranchProjects.isNotEmpty()) {
            Text(
                "这些项目可读但没有分支（非 git 或尚无分支），不占状态列：${board.noBranchProjects.joinToString("、")}",
                style = Type.micro,
            )
        }

        // ── 列区（status 读到了才渲染列；失败/读取中不渲染，避免「空看板」冒充真相）──
        if (statusState is LoadState.Loaded) {
            // 【布局对位 mac BoardView】横向四列在内容区只占 1/3 且要横向滚动（mac 已否决）——
            // 改为垂直分组：列头在上、卡片纵向排布，整页纵向滚动。
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(Space.lg),
            ) {
                BoardColumnId.entries.forEach { id -> BoardColumnUi(id, board) { p -> model.goRoute(AppModel.Route.PROJECT, p) } }
            }
        }
    }
}

/** 一列：列头（点色 + 标题 + 计数）+ 判据 + 卡片（或空态披露）。 */
@Composable
private fun BoardColumnUi(id: BoardColumnId, board: BoardModel, onOpenProject: (String) -> Unit) {
    val rows = board.rowsIn(id)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.card))
            .background(Palette.Card)
            .border(1.dp, Palette.Stroke, RoundedCornerShape(Radius.card))
            .padding(Space.md),
    ) {
        // 列头计数与 rows 同源（同一个 List.size），不存在两套口径。
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).background(columnTone(id), CircleShape))
            Spacer(Modifier.width(Space.sm))
            Text(id.title, style = Type.section)
            Spacer(Modifier.weight(1f))
            Text("${rows.size}", style = Type.card.copy(color = columnTone(id), fontWeight = FontWeight.Bold))
        }
        Spacer(Modifier.height(Space.xs))
        Text(id.criteria, style = Type.micro)

        Spacer(Modifier.height(Space.sm))
        Column(verticalArrangement = Arrangement.spacedBy(Space.sm)) {
            when {
                // 分支列的空态：如实说没有分支落在这列，判据已在列头。
                id != BoardColumnId.UNREADABLE && rows.isEmpty() ->
                    Text("没有分支落在这列", style = Type.body.copy(color = Palette.TextSecondary))
                id == BoardColumnId.UNREADABLE && board.unreadable.isEmpty() ->
                    Text("没有读不出来的项目", style = Type.body.copy(color = Palette.TextSecondary))
                id == BoardColumnId.UNREADABLE ->
                    board.unreadable.forEach { u -> UnreadableCard(u) }
                else ->
                    rows.forEach { r -> BranchCard(r, onOpenProject) }
            }
        }
    }
}

/** 分支卡：分支名 / 所属项目 / 最近提交 / 领先默认分支数。整卡点击进项目详情。 */
@Composable
private fun BranchCard(r: BoardRow, onOpenProject: (String) -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Palette.CardHover)
            .clickable { onOpenProject(r.project) }
            .padding(Space.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            // 当前检出分支：accent 点；其余分支：描边点。颜色只走 Palette。
            Box(
                Modifier.size(8.dp).background(
                    if (r.isCurrent) Palette.Accent else Palette.Stroke,
                    CircleShape,
                ),
            )
            Spacer(Modifier.width(Space.sm))
            Text(r.branch, style = Type.card, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            if (r.isDefault) {
                Spacer(Modifier.width(Space.sm))
                Text("默认", style = Type.micro.copy(color = Palette.TextSecondary))
            }
        }
        Text(r.project, style = Type.micro)
        Spacer(Modifier.height(Space.xs))
        // 最近提交：headShort 缺失 = 读不出来（引擎没给），不写「无提交」。
        if (r.headKnown) {
            Text(
                buildString {
                    append(r.headShort)
                    if (r.headAgo.isNotBlank()) append(" · ${r.headAgo}")
                },
                style = Type.micro,
            )
            if (r.headSubject.isNotBlank()) {
                Text(r.headSubject, style = Type.micro, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        } else {
            Text("最近提交读不出来", style = Type.micro)
        }
        // 领先默认分支数：只对非默认分支有意义；基线重建过 ⇒ 原区间不可比（引擎字段 baselineReset）。
        when {
            r.isDefault -> {}
            r.baselineReset -> Text("基线重建过，领先数不可比", style = Type.micro.copy(color = Palette.Amber))
            r.aheadOfDefault > 0 -> Text("领先默认分支 ${r.aheadOfDefault}", style = Type.micro.copy(color = Palette.Accent))
            else -> Text("与默认分支持平", style = Type.micro)
        }
    }
}

/** 读不出来卡：项目名 + 引擎原因原文（不推断、不翻译）。 */
@Composable
private fun UnreadableCard(u: UnreadableProject) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Palette.CardHover)
            .padding(Space.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).background(Palette.Red.copy(alpha = 0.7f), CircleShape))
            Spacer(Modifier.width(Space.sm))
            Text(u.name, style = Type.card)
        }
        Spacer(Modifier.height(Space.xs))
        Text(u.error ?: "引擎未给原因", style = Type.micro, maxLines = 2, overflow = TextOverflow.Ellipsis)
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
