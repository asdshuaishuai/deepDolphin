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

package canopy.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.onClick
import androidx.compose.ui.input.pointer.PointerButton
import androidx.compose.foundation.PointerMatcher
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import canopy.engine.Milestone
import canopy.ui.Palette
import canopy.ui.Space
import canopy.ui.Type
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.PaddingValues

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
            // 破坏动作红门的键盘可达性：两个裸文字键都挂焦点环（accent outline，画在键外不挤布局），
            // 确认键初始持焦——键盘用户进弹窗就能 Enter 确认 / Tab 取消，不必摸鼠标。
            val confirmFocus = remember { FocusRequester() }
            LaunchedEffect(Unit) { confirmFocus.requestFocus() }
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm), modifier = Modifier.align(Alignment.End)) {
                Text(
                    L10n.t("common.cancel"), style = Type.body,
                    color = Palette.TextSecondary,
                    modifier = Modifier.focusRing(radius = 8.dp)
                        .clip(RoundedCornerShape(8.dp)).clickable { onDismiss() }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                )
                Text(
                    confirmLabel, style = Type.body.copy(fontWeight = FontWeight.Bold),
                    color = Color.White,
                    modifier = Modifier.focusRequester(confirmFocus).focusRing(radius = 8.dp)
                        .clip(RoundedCornerShape(8.dp)).background(Palette.Red)
                        .clickable { onConfirm() }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
    }
}

/**
 * 文字动作（Fluent「subtle」次按钮）：平时只有文字，hover 才出底色——页头动作条、行内操作用它。
 * 与描边按钮（FluentButton Standard）的区别是「轻」：一排并列的次要动作不互相抢眼。
 */
@Composable
fun ActionText(
    label: String,
    color: Color,
    enabled: Boolean = true,
    icon: FluentIcon? = null,
    onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val bg by animateColorAsState(
        if (hovered && enabled) Palette.CardHover else Color.Transparent,
        tween(Motion.normal),
        label = "actionBg",
    )
    val content = if (enabled) color else color.copy(alpha = 0.4f)
    Row(
        Modifier
            .height(ControlHeight)
            .clip(RoundedCornerShape(Radius.control))
            .background(bg)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick)
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let {
            IconBox(it, size = 16.dp, tint = content)
            Spacer(Modifier.width(6.dp))
        }
        Text(label, style = Type.body.copy(fontWeight = FontWeight.Medium), color = content, maxLines = 1)
    }
}

@Composable
private fun LabeledField(label: String, value: String, singleLine: Boolean = true, onChange: (String) -> Unit) {
    Column {
        Text(label, style = Type.micro)
        OutlinedTextField(
            colors = fluentTextFieldColors(),
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

    ScrollColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = Space.xl, vertical = Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.lg),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(L10n.t("ms.page.title"), style = Type.title)
                Spacer(Modifier.height(4.dp))
                Text(L10n.t("cmp.ms.healthLine", ms?.readCount ?: 0, ms?.storeHealth ?: "?"), style = Type.label)
            }
            Button(
                onClick = { showForm = !showForm },
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Palette.OnAccent),
            ) { Text(if (showForm) L10n.t("cmp.ms.collapseForm") else L10n.t("ms.new")) }
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
                Text(L10n.t("ms.new"), style = Type.section)
                Spacer(Modifier.height(Space.md))
                Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                    Column {
                        Text(L10n.t("ms.form.project"), style = Type.micro)
                        FluentDropdown(
                            options = projects.map { it.name to it.name },
                            selectedKey = fProject.ifBlank { null },
                            placeholder = L10n.t("cmp.form.selectProject"),
                            onSelect = { fProject = it },
                            modifier = Modifier.width(180.dp),
                        )
                    }
                    LabeledField(L10n.t("ms.name"), fName) { fName = it }
                    LabeledField(L10n.t("cmp.ms.tagOptional"), fTag) { fTag = it }
                    LabeledField(L10n.t("cmp.ms.dateOptional"), fDate) { fDate = it }
                }
                Spacer(Modifier.height(Space.sm))
                LabeledField(L10n.t("cmp.ms.descOptional"), fDesc, singleLine = false) { fDesc = it }
                formError?.let {
                    Spacer(Modifier.height(Space.xs))
                    Text(it, style = Type.body.copy(color = Palette.Red))
                }
                Spacer(Modifier.height(Space.md))
                Button(
                    onClick = {
                        when {
                            fProject.isBlank() -> formError = L10n.t("cmp.ms.errProject")
                            fName.isBlank() -> formError = L10n.t("cmp.ms.errName")
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
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Palette.OnAccent),
                ) { Text(L10n.t("ms.form.create")) }
            }
        }

        // ⚠️ 判定顺序是刻意的（对位 mac MilestonesView.swift:62-75）：
        //   **先看读没读出来，再看空不空**——「读取失败」与「真的还没有」
        //   是两句话，混成一句用户会以为自己还没建。
        when (val st = msState) {
            is LoadState.Failed -> GlassCard(Modifier.fillMaxWidth()) {
                Text(L10n.t("ms.page.unreadable"), style = Type.section.copy(color = Palette.Amber))
                Spacer(Modifier.height(Space.xs))
                Text(st.reason, style = Type.body.copy(color = Palette.TextSecondary))
                Text(L10n.t("cmp.ms.loadFailed"), style = Type.micro)
            }
            LoadState.Loading -> if (all.isEmpty()) {
                // 首读加载态：形状占位（组头一条线 + 3 张行卡骨架，微光扫过），替换一行「读取中」文字——
                // 列表首次加载不转圈；行卡骨架与加载完成后的里程碑行节奏对得上
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.sm)) {
                    SkeletonLine(width = 180.dp, height = 16.dp)
                    repeat(3) { SkeletonCard(Modifier.fillMaxWidth(), height = 72.dp) }
                }
            }
            else -> {
                val empty = SearchFilter.emptyReason(allCount = scoped.size, shownCount = shown.size, query = query)
                if (empty != null) {
                    GlassCard(Modifier.fillMaxWidth()) {
                        Text(SearchFilter.emptyText(empty, noun = L10n.t("ms.page.title")), style = Type.section)
                        Spacer(Modifier.height(Space.xs))
                        // 空态副说明：收窄到单仓库后「没有」有两种完全不同的原因
                        //（对位 mac emptySubtitle：这个仓库真的没有 vs 有但全被搜索滤掉了）。
                        val filterName = knownProjects.firstOrNull { it.projectId == projectFilter }?.projectName
                        Text(
                            when {
                                empty is SearchEmpty.NoData && projectFilter != null && filterName != null ->
                                    L10n.t("cmp.ms.emptyProjectHint", filterName)
                                empty is SearchEmpty.NoData -> L10n.t("ms.empty.hint")
                                else -> L10n.t("ms.empty.search")
                            },
                            style = Type.body.copy(color = Palette.TextSecondary),
                        )
                        Spacer(Modifier.height(Space.sm))
                        // 空态要教下一步：一键清搜索 + 切回全部仓库（标签复用「全部」），
                        // 别让用户回头找顶上的筛选条自己一项项还原
                        ActionText(L10n.t("cmp.ms.allShort"), Palette.Accent) {
                            query = ""
                            projectFilter = null
                        }
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
                                    allCount = scoped.size, shownCount = shown.size, noun = L10n.t("ms.page.title"),
                                )?.let { Text(it, style = Type.micro) }
                                Spacer(Modifier.weight(1f))
                                // 「只看这个项目」切换：点击即把 projectFilter 收窄到该组
                                //（对位 mac projectFilter 状态的本页快捷入口；已收窄到本组时收起）。
                                if (projectFilter != g.projectId) {
                                    ActionText(L10n.t("cmp.ms.onlyThisProject"), Palette.Accent) { projectFilter = g.projectId }
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
                                    onOpenProject = { model.goRoute(AppModel.Route.PROJECT, m.projectName) },
                                )
                            }
                        }
                    }

                    // ── 范围统计：按明细、按当前范围算（对位 mac：不读全局 counts——
                    //    收窄到单仓库后继续报全局数字，等于把全局完成率说成这个仓库的）──
                    GlassCard(Modifier.fillMaxWidth()) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                            Text(
                                if (projectFilter == null) L10n.t("ms.scope.all") else
                                    L10n.t("ms.scope.project", knownProjects.firstOrNull { it.projectId == projectFilter }?.projectName ?: projectFilter),
                                style = Type.label,
                            )
                            Spacer(Modifier.weight(1f))
                            Text("${tally.open}", style = Type.body.copy(color = Palette.Accent))
                            Text(L10n.t("ms.filter.open"), style = Type.label)
                            Text("${tally.done}", style = Type.body.copy(color = Palette.Green))
                            Text(L10n.t("ms.filter.done"), style = Type.label)
                            Text("${tally.dropped}", style = Type.body.copy(color = Palette.TextSecondary))
                            Text(L10n.t("ms.filter.dropped"), style = Type.label)
                            if (tally.unknown > 0) {
                                Text("${tally.unknown}", style = Type.body.copy(color = Palette.Amber))
                                Text(L10n.t("ms.filter.unreadable"), style = Type.label)
                            }
                        }
                        if (!DashMilestoneScope.isComplete(all, ms?.readCount)) {
                            Spacer(Modifier.height(Space.xs))
                            // 明细被窗口截过 ⇒ 上面的数只是**下界**，必须说出来。
                            Text(
                                L10n.t("cmp.ms.detailPartial", all.size, ms?.readCount ?: "?"),
                                style = Type.micro.copy(color = Palette.Amber),
                            )
                        }
                    }
                }

                // 孤儿披露
                ms?.orphaned.orEmpty().takeIf { it.isNotEmpty() }?.let { orphans ->
                    GlassCard(Modifier.fillMaxWidth()) {
                        Text(L10n.t("cmp.ms.orphans", orphans.size), style = Type.micro.copy(color = Palette.Amber))
                    }
                }
            }
        }
    }

    // 确认弹窗（破坏动作唯一红门）
    confirm?.let { (proj, name) ->
        ConfirmDialog(
            title = L10n.t("cmp.ms.confirmDelete"),
            body = L10n.t("cmp.ms.confirmDeleteBody", name, proj),
            confirmLabel = L10n.t("ms.row.delete"),
            onConfirm = { model.milestoneRemove(proj, name); confirm = null },
            onDismiss = { confirm = null },
        )
    }
    confirmDrop?.let { (proj, name) ->
        ConfirmDialog(
            title = L10n.t("cmp.ms.confirmDrop"),
            body = L10n.t("cmp.ms.confirmDropBody", name, proj),
            confirmLabel = L10n.t("ms.action.drop"),
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
        Text(L10n.t("ms.scope.repo"), style = Type.label)
        // 「全部」用空串当键：下拉的键一律非空，空串翻译回「不过滤」
        FluentDropdown(
            options = listOf("" to L10n.t("cmp.ms.allWithCount", knownProjects.sumOf { it.items.size })) +
                knownProjects.map { it.projectId to "${it.projectName}（${it.items.size}）" },
            selectedKey = projectFilter ?: "",
            placeholder = L10n.t("cmp.ms.allShort"),
            onSelect = { key -> onSelect(key.ifBlank { null }) },
            enabled = knownProjects.isNotEmpty(),
            modifier = Modifier.width(200.dp),
        )
        // 搜索框（复用 SearchFilter 纯函数；对位 mac .searchable 的 prompt）。
        OutlinedTextField(
            colors = fluentTextFieldColors(),
            value = query,
            onValueChange = onQuery,
            placeholder = { Text(L10n.t("ms.search.placeholder"), style = Type.micro) },
            singleLine = true,
            textStyle = Type.body,
            modifier = Modifier.width(220.dp),
        )
        if (projectFilter != null || query.isNotBlank()) {
            Text(L10n.t("ms.filtered", shownCount, scopedCount), style = Type.label)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun MilestoneRow(
    m: Milestone, busy: Boolean,
    onDone: () -> Unit, onReopen: () -> Unit, onDrop: () -> Unit, onRemove: () -> Unit,
    onOpenProject: () -> Unit = {},
) {
    // 右键菜单（mac rowActions 对位）：达成 / 重新打开 / 放弃 / 打开项目 / 删除
    var menuOpen by remember { mutableStateOf(false) }
    androidx.compose.foundation.layout.Box(Modifier.fillMaxWidth()) {
        GlassCard(
            Modifier.fillMaxWidth()
                // 键盘焦点环：pointerInput 不产焦点节点，行自己挂 focusable 让 Tab 落得进来，
                // 环画在卡外（focusRing 挂上游）；hover 上浮/提亮走 GlassCard 的 interactive=true
                .focusRing(radius = Radius.card)
                .focusable()
                // 点行 = 进该里程碑所属项目的详情（mac onTapGesture 对位）；右键 = 行操作菜单
                .pointerInput(m.id) { detectTapGestures(onTap = { onOpenProject() }) }
                .onClick(matcher = PointerMatcher.mouse(PointerButton.Secondary)) { menuOpen = true },
            interactive = true,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                // 状态图标：达成 ✓ / 放弃 ✕ / 无法核验 ? / 逾期 ! / 其余 ○
                val iconTint = when {
                    m.status == "done" -> Palette.Green
                    m.status == "dropped" -> Palette.TextSecondary
                    m.isUnknown -> Palette.Amber
                    m.overdue -> Palette.Red
                    else -> Palette.Accent
                }
                // 状态图标（mac StatusDot 同语义）：达成=带勾圆、放弃=带叉圆、未知=问号、逾期=警告、进行中=空心圆
                val stateIcon = when {
                    m.status == "done" -> FluentIcon.CheckmarkCircle
                    m.status == "dropped" -> FluentIcon.DismissCircle
                    m.isUnknown -> FluentIcon.QuestionCircle
                    m.overdue -> FluentIcon.Warning
                    else -> FluentIcon.Circle
                }
                Box(
                    Modifier.size(20.dp).clip(androidx.compose.foundation.shape.CircleShape)
                        .background(iconTint.copy(alpha = 0.16f)),
                    contentAlignment = Alignment.Center,
                ) { IconBox(stateIcon, size = 12.dp, tint = iconTint) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                        Text(m.projectName, style = Type.label)
                        // 长名：weight 吃掉剩余宽度 + ellipsis（真截到才出 tooltip 全文）——
                        // 不加截断会把右侧状态/动作列挤出卡片
                        Box(Modifier.weight(1f)) {
                            TruncatedText(m.name, style = Type.card)
                        }
                        if (m.tagReached) Pill("tag ✓", Palette.Green)
                    }
                    m.description?.takeIf { it.isNotBlank() }?.let {
                        TruncatedText(it, style = Type.label)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                        // 绑了 tag 但还没打到：把 tag 名亮出来（达成靠 tag 出现，用户得知道等哪个）
                        if (m.tagName.isNotBlank() && !m.tagReached) Text("tag ${m.tagName}", style = Type.micro)
                        if (m.commitsSinceReadable) {
                            if (m.commitsSince > 0) Text(milestoneCommitsText(m), style = Type.micro)
                        } else {
                            Text(milestoneUnverifiedNote(m), style = Type.micro, color = Palette.Amber, maxLines = 2)
                        }
                    }
                }
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    val statusTint = when {
                        m.status == "done" -> Palette.Green
                        m.status == "dropped" -> Palette.TextSecondary
                        m.isUnknown -> Palette.Amber
                        m.overdue -> Palette.Red
                        else -> Palette.TextPrimary
                    }
                    Text(milestoneStatusLabel(m), style = Type.body.copy(fontWeight = FontWeight.Medium), color = statusTint)
                    val due = milestoneDueText(m)
                    when {
                        due.isNotBlank() -> Text(
                            L10n.t("ms.row.due", m.targetDate, due), style = Type.micro,
                            color = if (m.overdue) Palette.Red else Palette.TextSecondary,
                        )
                        m.targetDate.isNotBlank() -> Text(L10n.t("ms.row.dueOnly", m.targetDate), style = Type.micro)
                    }
                }
                // 行内动作（mac 同款三个）：达成（进行中才有）/ 重新打开（非进行中且可核验）/ 删除；放弃在右键菜单
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (m.status == "open") ActionText(L10n.t("ms.row.done"), Palette.Green, enabled = !busy, onClick = onDone)
                    if (m.status != "open" && !m.isUnknown) ActionText(L10n.t("ms.row.reopen"), Palette.Accent, enabled = !busy, onClick = onReopen)
                    ActionText(L10n.t("ms.row.delete"), Palette.Red, enabled = !busy, onClick = onRemove)
                }
            }
        }
        androidx.compose.material3.DropdownMenu(
            expanded = menuOpen, onDismissRequest = { menuOpen = false },
            containerColor = Palette.Card,
        ) {
            val close = { menuOpen = false }
            if (m.status != "done") DropdownMenuItem(text = { Text(L10n.t("ms.action.done"), style = Type.body) }, onClick = { close(); onDone() })
            if (m.status != "open") DropdownMenuItem(text = { Text(L10n.t("ms.action.reopen"), style = Type.body) }, onClick = { close(); onReopen() })
            if (m.status != "dropped") DropdownMenuItem(text = { Text(L10n.t("ms.action.drop"), style = Type.body) }, onClick = { close(); onDrop() })
            androidx.compose.material3.HorizontalDivider(color = Palette.Stroke)
            DropdownMenuItem(text = { Text(L10n.t("ms.action.openProject"), style = Type.body) }, onClick = { close(); onOpenProject() })
            androidx.compose.material3.HorizontalDivider(color = Palette.Stroke)
            DropdownMenuItem(text = { Text(L10n.t("ms.row.delete"), style = Type.body.copy(color = Palette.Red)) }, onClick = { close(); onRemove() })
        }
    }
}

/** 带破坏性操作守卫的里程碑行（详情页里程碑卡用；放弃/删除先确认，文案与里程碑页同一份）。 */
@Composable
internal fun GuardedMilestoneRow(model: AppModel, m: Milestone) {
    val busy by model.busyAction.collectAsState()
    var pending by remember { mutableStateOf<String?>(null) } // "drop" | "remove"
    MilestoneRow(
        m = m, busy = busy,
        onDone = { model.milestoneAction(m.projectId, m.name, "done") },
        onReopen = { model.milestoneAction(m.projectId, m.name, "reopen") },
        onDrop = { pending = "drop" },
        onRemove = { pending = "remove" },
        onOpenProject = { model.goRoute(AppModel.Route.PROJECT, m.projectName) },
    )
    pending?.let { kind ->
        val drop = kind == "drop"
        ConfirmDialog(
            title = if (drop) L10n.t("cmp.ms.confirmDrop") else L10n.t("cmp.ms.confirmDelete"),
            body = if (drop) L10n.t("cmp.ms.confirmDropBody", m.name, m.projectName) else L10n.t("cmp.ms.confirmDeleteBody", m.name, m.projectName),
            confirmLabel = if (drop) L10n.t("ms.action.drop") else L10n.t("ms.row.delete"),
            onConfirm = {
                pending = null
                if (drop) model.milestoneAction(m.projectId, m.name, "drop") else model.milestoneRemove(m.projectId, m.name)
            },
            onDismiss = { pending = null },
        )
    }
}
