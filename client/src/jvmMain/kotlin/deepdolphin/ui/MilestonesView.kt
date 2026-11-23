// MilestonesView.kt —— 里程碑页（对位 mac MilestonesView.swift）：筛选 + 搜索 + 按项目分组。
//
// 【取数口径在纯函数层】DashMilestoneScope（对位 mac DashboardScope.swift:125-186
// 同名 enum）：先按项目收窄明细，再叠搜索词。判定抽纯函数由判据直测——
// 筛选控件最常见的失败不是「不好看」，而是「摆在那里不起作用」。
//
// 【为什么里程碑页必须有项目筛选】它是唯一能改数据的视图（新建/达成/放弃/删除
// 都走这里），仪表盘和项目卡上的里程碑全是只读副本——多仓库时摊平一张列表，
// 「这条属于哪个仓库」只剩一行小字。对位 mac：projectFilter 是**本页自己的**
// 筛选状态（默认全部，用户自己收窄），不联动 model.route（mac 教训：从
// model.selection 读范围是个恒为 nil 的死控件——切到本页那一刻 selection 就变了）。
//
// 【统计不许拿明细当全量】明细（milestones[]）没有截断标志，readCount 是引擎
// 真正读到的条数；两者不等时按明细算的统计只是**下界**，必须说出来
// （对位 mac「上限当全量」纪律）。
//
// 【确认纪律】删除/放弃必过确认框（引擎不留备份）；达成/重开不进确认集合（防确认疲劳）。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import deepdolphin.engine.Milestone
import deepdolphin.ui.Palette
import deepdolphin.ui.Space
import deepdolphin.ui.Type

// ══════════════════════════════════════════════════════════════════════
// 取数口径（纯函数层，对位 mac DashboardScope.swift:125-186 DashMilestoneScope）
// ══════════════════════════════════════════════════════════════════════

/** 里程碑按项目分组的一组（首现顺序，组内保持明细顺序）。 */
data class MilestoneGroup(val projectId: String, val projectName: String, val items: List<Milestone>)

/** 明细的状态分布。unknown 单列——「仓库读不出来，不知道达没达成」，
 *  混进 open 或 done 都是把「不知道」说成事实。 */
data class MsTally(val open: Int, val done: Int, val dropped: Int, val unknown: Int)

object DashMilestoneScope {

    /** 按范围收窄。project 为 null = 全部项目（对位 mac items(_:project:)）。
     *  收窄的是**明细**；全局 counts（dashboard 口径）没有项目维度，收窄后不能继续报它。 */
    fun items(all: List<Milestone>, project: String?): List<Milestone> =
        if (project == null) all else all.filter { it.projectId == project }

    /** 按项目分组，保持首现顺序（对位 mac groups(_:)：明细按项目成组，
     *  首现顺序就是稳定的项目顺序，不额外排序）。展示名用引擎的 projectName，
     *  缺席回退 projectId——孤儿条目（项目不在册）引擎也给名字，不丢。 */
    fun groups(items: List<Milestone>): List<MilestoneGroup> {
        val order = mutableListOf<String>()
        val buckets = mutableMapOf<String, MutableList<Milestone>>()
        for (m in items) {
            if (buckets[m.projectId] == null) {
                order += m.projectId
                buckets[m.projectId] = mutableListOf()
            }
            buckets.getValue(m.projectId) += m
        }
        return order.map { id ->
            val list = buckets.getValue(id)
            MilestoneGroup(id, list.firstOrNull { it.projectName.isNotBlank() }?.projectName ?: id, list)
        }
    }

    /** 明细里的状态分布（对位 mac tally(_:)）。status null（缺键无法核验）进 unknown，
     *  未来新增档位同样进 unknown——不丢条、不猜语义。 */
    fun tally(items: List<Milestone>): MsTally {
        var t = MsTally(0, 0, 0, 0)
        for (m in items) {
            t = when (m.status) {
                "done" -> t.copy(done = t.done + 1)
                "dropped" -> t.copy(dropped = t.dropped + 1)
                "open" -> t.copy(open = t.open + 1)
                else -> t.copy(unknown = t.unknown + 1)
            }
        }
        return t
    }

    /** 明细是否等于引擎真正读到的全部（对位 mac isComplete(_:)）。
     *  readCount 缺席（null）= 不知道，按不完整处理让界面披露，不假装完整。 */
    fun isComplete(items: List<Milestone>, readCount: Long?): Boolean =
        readCount != null && items.size.toLong() == readCount
}

// ══════════════════════════════════════════════════════════════════════
// 渲染
// ══════════════════════════════════════════════════════════════════════

/** 确认弹窗（Modal：焦点在主按钮、Esc 关闭）。 */
@Composable
fun ConfirmDialog(title: String, body: String, confirmLabel: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    Box(
        Modifier.fillMaxSize().background(Color(0x88000000)).clickable(enabled = false) {},
        contentAlignment = Alignment.Center,
    ) {
        GlassCard(Modifier.width(460.dp)) {
            Text(title, style = Type.section)
            Spacer(Modifier.height(Space.sm))
            Text(body, style = Type.body.copy(color = Palette.TextSecondary))
            Spacer(Modifier.height(Space.lg))
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm), modifier = Modifier.align(Alignment.End)) {
                Text(
                    "取消", style = Type.body,
                    color = Palette.TextSecondary,
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable { onDismiss() }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                )
                Text(
                    confirmLabel, style = Type.body.copy(fontWeight = FontWeight.Bold),
                    color = Color.White,
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(Palette.Red)
                        .clickable { onConfirm() }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
    }
}

@Composable
fun ActionText(label: String, color: Color, enabled: Boolean = true, onClick: () -> Unit) {
    Text(
        label, style = Type.body.copy(fontWeight = FontWeight.Medium),
        color = if (enabled) color else color.copy(alpha = 0.4f),
        modifier = Modifier.clip(RoundedCornerShape(6.dp)).clickable(enabled = enabled) { onClick() }
            .padding(horizontal = 10.dp, vertical = 4.dp),
    )
}

@Composable
private fun LabeledField(label: String, value: String, singleLine: Boolean = true, onChange: (String) -> Unit) {
    Column {
        Text(label, style = Type.micro)
        OutlinedTextField(
            value = value,
            onValueChange = onChange,
            singleLine = singleLine,
            modifier = Modifier.width(220.dp),
            textStyle = Type.body,
        )
    }
}

@Composable
fun MilestonesPage(model: AppModel) {
    val ms by model.milestones.collectAsState()
    val msState by model.msState.collectAsState()
    val status by model.status.collectAsState()
    val busyAction by model.busyAction.collectAsState()
    val projects = status?.projects.orEmpty().filter { it.isReadable }

    // ── 本页自己的筛选状态（对位 mac @State projectFilter / query；默认全部）──
    var projectFilter by remember { mutableStateOf<String?>(null) } // projectId；null = 全部
    var query by remember { mutableStateOf("") }

    var showForm by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf<Pair<String, String>?>(null) } // (project, name) 待删除
    var confirmDrop by remember { mutableStateOf<Pair<String, String>?>(null) } // 待放弃

    // 新建表单草稿
    var fProject by remember { mutableStateOf("") }
    var fName by remember { mutableStateOf("") }
    var fTag by remember { mutableStateOf("") }
    var fDate by remember { mutableStateOf("") }
    var fDesc by remember { mutableStateOf("") }
    var formError by remember { mutableStateOf<String?>(null) }

    // ── 取数：先项目收窄再叠搜索（两步都是纯函数，判定见 DashMilestoneScope）──
    val all = ms?.milestones.orEmpty()
    val scoped = DashMilestoneScope.items(all, projectFilter)
    val shown = SearchFilter.filter(scoped, query) { it.name }
    val groups = DashMilestoneScope.groups(shown)
    val tally = DashMilestoneScope.tally(shown)
    val knownProjects = remember(all) { DashMilestoneScope.groups(all) } // 下拉用：首现顺序

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState())
            .padding(horizontal = Space.xl, vertical = Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.lg),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("里程碑", style = Type.title)
                Spacer(Modifier.height(4.dp))
                Text("${ms?.readCount ?: 0} 条 · 存储健康度 ${ms?.storeHealth ?: "?"}", style = Type.label)
            }
            Button(
                onClick = { showForm = !showForm },
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
            ) { Text(if (showForm) "收起表单" else "新建里程碑") }
        }

        // ── 筛选条（常驻内容区顶部，对位 mac milestoneFilterBar：仓库下拉 + 搜索 + 筛出计数）──
        MilestoneFilterBar(
            knownProjects = knownProjects,
            projectFilter = projectFilter,
            onSelect = { projectFilter = it },
            query = query,
            onQuery = { query = it },
            scopedCount = scoped.size,
            shownCount = shown.size,
        )

        // ── 新建表单（卡片化 + 收起 + 项目下拉）──
        if (showForm) {
            GlassCard(Modifier.fillMaxWidth()) {
                Text("新建里程碑", style = Type.section)
                Spacer(Modifier.height(Space.md))
                Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                    Column {
                        Text("项目", style = Type.micro)
                        var open by remember { mutableStateOf(false) }
                        Box {
                            Text(
                                fProject.ifBlank { "选择项目" },
                                style = Type.body,
                                color = if (fProject.isBlank()) Palette.TextSecondary else Palette.TextPrimary,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp)).background(Palette.BgDeep)
                                    .clickable { open = !open }
                                    .padding(horizontal = 12.dp, vertical = 8.dp).width(160.dp),
                            )
                            if (open) {
                                Column(
                                    Modifier.width(220.dp).clip(RoundedCornerShape(8.dp))
                                        .background(Palette.BgDeep).padding(Space.xs)
                                ) {
                                    projects.forEach { p ->
                                        Text(
                                            p.name, style = Type.body,
                                            modifier = Modifier.fillMaxWidth()
                                                .clickable { fProject = p.name; open = false }
                                                .padding(horizontal = 10.dp, vertical = 6.dp),
                                        )
                                    }
                                }
                            }
                        }
                    }
                    LabeledField("名称", fName) { fName = it }
                    LabeledField("tag（可空，存在即自动达成）", fTag) { fTag = it }
                    LabeledField("目标日期 yyyy-MM-dd（可空）", fDate) { fDate = it }
                }
                Spacer(Modifier.height(Space.sm))
                LabeledField("描述（可空）", fDesc, singleLine = false) { fDesc = it }
                formError?.let {
                    Spacer(Modifier.height(Space.xs))
                    Text(it, style = Type.body.copy(color = Palette.Red))
                }
                Spacer(Modifier.height(Space.md))
                Button(
                    onClick = {
                        when {
                            fProject.isBlank() -> formError = "项目不能为空"
                            fName.isBlank() -> formError = "名称不能为空"
                            else -> {
                                formError = null
                                model.milestoneAdd(fProject, fName, fTag.ifBlank { null }, fDate.ifBlank { null }, fDesc.ifBlank { null })
                                fName = ""; fTag = ""; fDate = ""; fDesc = ""
                                showForm = false
                            }
                        }
                    },
                    enabled = !busyAction,
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
                ) { Text("创建") }
            }
        }

        // ⚠️ 判定顺序是刻意的（对位 mac MilestonesView.swift:62-75）：
        //   **先看读没读出来，再看空不空**——「读取失败」与「真的还没有」
        //   是两句话，混成一句用户会以为自己还没建。
        when (val st = msState) {
            is LoadState.Failed -> GlassCard(Modifier.fillMaxWidth()) {
                Text("里程碑读不出来", style = Type.section.copy(color = Palette.Amber))
                Spacer(Modifier.height(Space.xs))
                Text(st.reason, style = Type.body.copy(color = Palette.TextSecondary))
                Text("下面没有列表——这是读取失败，不是「没有里程碑」", style = Type.micro)
            }
            LoadState.Loading -> if (all.isEmpty()) {
                Text("读取里程碑…", style = Type.body.copy(color = Palette.TextSecondary))
            }
            else -> {
                val empty = SearchFilter.emptyReason(allCount = scoped.size, shownCount = shown.size, query = query)
                if (empty != null) {
                    GlassCard(Modifier.fillMaxWidth()) {
                        Text(SearchFilter.emptyText(empty, noun = "里程碑"), style = Type.section)
                        Spacer(Modifier.height(Space.xs))
                        // 空态副说明：收窄到单仓库后「没有」有两种完全不同的原因
                        //（对位 mac emptySubtitle：这个仓库真的没有 vs 有但全被搜索滤掉了）。
                        val filterName = knownProjects.firstOrNull { it.projectId == projectFilter }?.projectName
                        Text(
                            when {
                                empty is SearchEmpty.NoData && projectFilter != null && filterName != null ->
                                    "「$filterName」还没有里程碑。切回「全部」可以看其它仓库的。"
                                empty is SearchEmpty.NoData -> "里程碑绑定 git tag 后，tag 出现即自动判定达成"
                                else -> "换个关键词，或清空搜索框看全部"
                            },
                            style = Type.body.copy(color = Palette.TextSecondary),
                        )
                    }
                } else {
                    // ── 按项目分组的列表（对位 mac：里程碑绑在项目上，摊平就分不清谁是谁）──
                    groups.forEach { g ->
                        Column(Modifier.fillMaxWidth()) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                // 单仓库范围时分组标题就是那个仓库本身；全局时带计数。
                                Text(
                                    if (projectFilter == null) g.projectName else "${g.projectName}（${g.items.size}）",
                                    style = Type.section,
                                )
                                Spacer(Modifier.width(Space.sm))
                                SearchFilter.resultSummary(
                                    allCount = scoped.size, shownCount = shown.size, noun = "里程碑",
                                )?.let { Text(it, style = Type.micro) }
                                Spacer(Modifier.weight(1f))
                                // 「只看这个项目」切换：点击即把 projectFilter 收窄到该组
                                //（对位 mac projectFilter 状态的本页快捷入口；已收窄到本组时收起）。
                                if (projectFilter != g.projectId) {
                                    ActionText("只看这个项目", Palette.Accent) { projectFilter = g.projectId }
                                }
                            }
                            Spacer(Modifier.height(Space.sm))
                            g.items.forEach { m ->
                                MilestoneRow(
                                    m = m,
                                    busy = busyAction,
                                    onDone = { model.milestoneAction(m.projectId, m.name, "done") },
                                    onReopen = { model.milestoneAction(m.projectId, m.name, "reopen") },
                                    onDrop = { confirmDrop = m.projectId to m.name },
                                    onRemove = { confirm = m.projectId to m.name },
                                )
                            }
                        }
                    }

                    // ── 范围统计：按明细、按当前范围算（对位 mac：不读全局 counts——
                    //    收窄到单仓库后继续报全局数字，等于把全局完成率说成这个仓库的）──
                    GlassCard(Modifier.fillMaxWidth()) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                            Text(
                                if (projectFilter == null) "全部项目" else
                                    "${knownProjects.firstOrNull { it.projectId == projectFilter }?.projectName ?: projectFilter} 的里程碑",
                                style = Type.label,
                            )
                            Spacer(Modifier.weight(1f))
                            Text("${tally.open}", style = Type.body.copy(color = Palette.Accent))
                            Text("进行中", style = Type.label)
                            Text("${tally.done}", style = Type.body.copy(color = Palette.Green))
                            Text("已达成", style = Type.label)
                            Text("${tally.dropped}", style = Type.body.copy(color = Palette.TextSecondary))
                            Text("已放弃", style = Type.label)
                            if (tally.unknown > 0) {
                                Text("${tally.unknown}", style = Type.body.copy(color = Palette.Amber))
                                Text("读不出来", style = Type.label)
                            }
                        }
                        if (!DashMilestoneScope.isComplete(all, ms?.readCount)) {
                            Spacer(Modifier.height(Space.xs))
                            // 明细被窗口截过 ⇒ 上面的数只是**下界**，必须说出来。
                            Text(
                                "明细只给了 ${all.size} 条，引擎读到 ${ms?.readCount ?: "?"} 条——上面按明细统计，不是全量",
                                style = Type.micro.copy(color = Palette.Amber),
                            )
                        }
                    }
                }

                // 孤儿披露
                ms?.orphaned.orEmpty().takeIf { it.isNotEmpty() }?.let { orphans ->
                    GlassCard(Modifier.fillMaxWidth()) {
                        Text("孤儿里程碑 ${orphans.size} 条（引用的项目不在注册表）", style = Type.micro.copy(color = Palette.Amber))
                    }
                }
            }
        }
    }

    // 确认弹窗（破坏动作唯一红门）
    confirm?.let { (proj, name) ->
        ConfirmDialog(
            title = "删除里程碑",
            body = "「$name」（$proj）将被删除。引擎不留备份、没有回收站、无法恢复。",
            confirmLabel = "删除",
            onConfirm = { model.milestoneRemove(proj, name); confirm = null },
            onDismiss = { confirm = null },
        )
    }
    confirmDrop?.let { (proj, name) ->
        ConfirmDialog(
            title = "放弃里程碑",
            body = "「$name」（$proj）将标记为放弃。此操作不删数据，但会改变统计口径。",
            confirmLabel = "放弃",
            onConfirm = { model.milestoneAction(proj, name, "drop"); confirmDrop = null },
            onDismiss = { confirmDrop = null },
        )
    }
}

/**
 * 仓库筛选条（对位 mac milestoneFilterBar：常驻内容区顶部）。
 * 筛选生效时说清「从多少条里筛到多少条」——只报筛后的条数，
 * 读者没法判断是被筛掉了还是本来就没那么多。
 */
@Composable
private fun MilestoneFilterBar(
    knownProjects: List<MilestoneGroup>,
    projectFilter: String?,
    onSelect: (String?) -> Unit,
    query: String,
    onQuery: (String) -> Unit,
    scopedCount: Int,
    shownCount: Int,
) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
        Text("仓库", style = Type.label)
        var open by remember { mutableStateOf(false) }
        val filterName = knownProjects.firstOrNull { it.projectId == projectFilter }?.projectName
        Box {
            Text(
                filterName ?: "全部",
                style = Type.body,
                color = if (projectFilter == null) Palette.TextSecondary else Palette.TextPrimary,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp)).background(Palette.BgDeep)
                    .clickable(enabled = knownProjects.isNotEmpty()) { open = !open }
                    .padding(horizontal = 12.dp, vertical = 8.dp).width(140.dp),
            )
            if (open && knownProjects.isNotEmpty()) {
                Column(
                    Modifier.width(200.dp).clip(RoundedCornerShape(8.dp))
                        .background(Palette.BgDeep).padding(Space.xs)
                ) {
                    Text(
                        "全部（${knownProjects.sumOf { it.items.size }}）",
                        style = Type.body,
                        modifier = Modifier.fillMaxWidth()
                            .clickable { onSelect(null); open = false }
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                    )
                    knownProjects.forEach { g ->
                        Text(
                            "${g.projectName}（${g.items.size}）",
                            style = Type.body,
                            modifier = Modifier.fillMaxWidth()
                                .clickable { onSelect(g.projectId); open = false }
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                        )
                    }
                }
            }
        }
        // 搜索框（复用 SearchFilter 纯函数；对位 mac .searchable 的 prompt）。
        OutlinedTextField(
            value = query,
            onValueChange = onQuery,
            placeholder = { Text("搜索里程碑名称", style = Type.micro) },
            singleLine = true,
            textStyle = Type.body,
            modifier = Modifier.width(220.dp),
        )
        if (projectFilter != null || query.isNotBlank()) {
            Text("筛出 $shownCount / $scopedCount 条", style = Type.label)
        }
    }
}

@Composable
private fun MilestoneRow(
    m: Milestone, busy: Boolean,
    onDone: () -> Unit, onReopen: () -> Unit, onDrop: () -> Unit, onRemove: () -> Unit,
) {
    GlassCard(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(m.name, style = Type.card.copy(fontWeight = FontWeight.Bold))
                    Spacer(Modifier.width(Space.sm))
                    when (m.status) {
                        "open" -> Pill("进行中", Palette.Accent)
                        "done" -> Pill("已达成", Palette.Green)
                        "dropped" -> Pill("已放弃", Palette.TextSecondary)
                        // unknown 单列：仓库读不出来 ≠ 没达成，不许渲染成「进行中」。
                        else -> Pill("无法核验", Palette.Amber)
                    }
                    Spacer(Modifier.width(Space.sm))
                    Text(m.projectName.ifBlank { m.projectId }, style = Type.micro)
                }
                Spacer(Modifier.height(2.dp))
                val meta = buildList {
                    if (m.tag.isNotBlank()) add("tag ${m.tag}")
                    if (m.targetDate.isNotBlank()) add("目标 ${m.targetDate}")
                    if (m.completedAt.isNotBlank()) add("达成于 ${m.completedAt}")
                }
                if (meta.isNotEmpty()) Text(meta.joinToString(" · "), style = Type.micro)
                m.description?.takeIf { it.isNotBlank() }?.let {
                    Text(it, style = Type.body.copy(color = Palette.TextSecondary), maxLines = 2)
                }
            }
            // 前动作紧邻信息列；破坏对靠右成组（UI 精修纪律）
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                when (m.status) {
                    "open", null, "unknown" -> ActionText("达成", Palette.Green, enabled = !busy, onClick = onDone)
                    "done" -> ActionText("重开", Palette.Accent, enabled = !busy, onClick = onReopen)
                }
                Spacer(Modifier.width(Space.sm))
                ActionText("放弃", Palette.TextSecondary, enabled = !busy, onClick = onDrop)
                ActionText("删除", Palette.Red, enabled = !busy, onClick = onRemove)
            }
        }
    }
}
