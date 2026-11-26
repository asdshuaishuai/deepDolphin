// DashboardView.kt —— 仪表盘页（mac DashboardView + DashboardParts.swift 的 Kotlin 对位）。
//
// 【四段式】页头 → 筛选行 → 4 张精选 KPI → 逐项目卡网格 →（语言分布 ‖ 里程碑）→ 近 7 天活跃。
// 判定（时间跨度怎么算、提交类型筛哪些段、KPI 怎么归并、切片披露）全在 DashScope.kt 纯函数层；
// 本文件只负责把结果画出来——**这里不许出现任何算术**（mac 基准原话）。
//
// 【三条控件必须真的改变下面画什么】摆而不动的控件是最坏的一种控件：用户拨了「近 7 天」
// 而卡片纹丝不动，整条筛选行就被当成装饰。二次验证抓到过：时间窗胶囊只换高亮、从不参与过滤。

package canopy.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import canopy.engine.*
import canopy.ui.Palette
import canopy.ui.Radius
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import canopy.ui.heroBrushDiagonal
import canopy.ui.Space
import canopy.ui.Type
import kotlin.math.roundToInt
import androidx.compose.foundation.layout.PaddingValues

private val Mono = FontFamily.Monospace

/**
 * 玻璃磁贴（Fluent reveal：hover 分层渐变 + 描边提亮；底 + hairline 描边）。
 * [interactive] = 卡片能不能按：分区卡 / 筛选行 / 空态这类摆着看的卡不给 hover 反应
 * （hover 只属于能按的东西，全卡无差别提亮是最坏的一种噪音）；可点卡（项目进度卡、
 * 里程碑行）interactive=true——提亮仍走自己的 Card→CardHover 底色动画（hoverLift 传
 * brighten=false 免得叠亮），另挂 hoverLift 上浮 2dp、描边同步提亮。
 */
@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    interactive: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    // Fluent reveal：hover 分层 4%→6% 白渐变（150ms），描边同步提亮；不抬升几何
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val bg by androidx.compose.animation.animateColorAsState(
        if (interactive && hovered) Palette.CardHover else Palette.Card,
        androidx.compose.animation.core.tween(Motion.normal), label = "cardBg",
    )
    val stroke by androidx.compose.animation.animateColorAsState(
        if (interactive && hovered) Palette.StrokeHover else Palette.Stroke,
        androidx.compose.animation.core.tween(Motion.normal), label = "cardStroke",
    )
    Column(
        modifier
            .skinShadow(Radius.card)
            // 链序与 ButtonChrome 同构：skinShadow 下游、clip/background 上游（hoverLift 契约）
            .hoverLift(interaction, enabled = interactive, radius = Radius.card, brighten = false)
            .hoverable(interaction, enabled = interactive)
            .clip(RoundedCornerShape(Radius.card))
            .background(bg)
            .skinGloss(Radius.card)
            .border(Material.borderWidth, stroke, RoundedCornerShape(Radius.card))
            .padding(Space.lg),
        content = content,
    )
}

/** 分区卡：标题 + 固定节奏（仪表盘与详情页共用的分区标题纪律）。 */
@Composable
fun SectionCard(title: String, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    GlassCard(modifier) {
        Text(title, style = Type.section)
        Spacer(Modifier.height(Space.sm))
        content()
    }
}

/** 空态判定（对位 mac 基准「三种没有分开说」）：只有「引擎成功读过且在册列表为空」才是真空。
 *  信封未到（加载中）或读取失败 ≠ 空态 —— 绝不拿 CTA 冒充；纯函数可单测。 */
fun registryEmpty(envelope: StatusEnvelope?): Boolean = envelope != null && envelope.projects.isEmpty()

/** 胶囊 pill（语义色底 + 深色文字 = WCAG 对比度纪律）。形状与内边距走 Badge 令牌（pill 档：全圆 + h8/v2）。 */
@Composable
fun Pill(text: String, color: Color, dot: Boolean = false) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(Badge.pillShape)
            .background(color.copy(alpha = 0.9f))
            .padding(horizontal = Badge.pillPadH, vertical = Badge.pillPadV),
    ) {
        // 圆点用画的不用「●」字：字形的圆在不同字体里大小不一，还挤着数字
        if (dot) {
            Box(Modifier.size(6.dp).background(Palette.BgBase, androidx.compose.foundation.shape.CircleShape))
            Spacer(Modifier.width(4.dp))
        }
        Text(text, style = Type.micro.copy(fontWeight = FontWeight.SemiBold), color = Palette.BgBase)
    }
}

/** 分段堆叠条（提交构成 / 语言分布共用）：各段宽度 = 数值占比。 */
@Composable
fun SegmentedBar(values: List<Long>, colors: List<Color>, modifier: Modifier = Modifier) {
    val total = values.sum().coerceAtLeast(1)
    Row(
        modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(Radius.chip)).background(Palette.BarTrack),
    ) {
        values.forEachIndexed { i, v ->
            if (v > 0) {
                Box(
                    Modifier.weight(v.toFloat() / total).fillMaxHeight()
                        .background(colors.getOrElse(i) { Color.Transparent }),
                )
            }
        }
    }
}

/**
 * 提交构成块（堆叠条 + 图例，项目卡与详情页共用）。**不取模**：色板画不完的条数由
 * commitTypeCardSlice 说出来——取模会让第 13 类拿到第 1 类的颜色，两段同色并成一段。
 * sampleTruncated = 引擎只给了最近 N 条样本，样本披露必须在场。
 */
@Composable
fun CommitCompositionBlock(entries: List<CommitTypeCount>, sampleTruncated: Boolean) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
        val slice = commitTypeCardSlice(entries)
        SegmentedBar(slice.entries.map { it.count }, slice.entries.indices.map { Composition12[it] })
        FlowLegend(slice.entries.mapIndexed { i, e -> Triple(e.kind, e.count.toString(), Composition12[i]) })
        slice.note?.let { Text(it, style = Type.micro) }
        if (sampleTruncated) Text(L10n.t("dash.card.sample"), style = Type.micro, color = Palette.Amber)
    }
}

/** 自动换行图例（色块 + 名称 + 计数）。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FlowLegend(items: List<Triple<String, String, Color>>) {
    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.md), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
        items.forEach { (label, count, color) ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(8.dp).background(color, RoundedCornerShape(2.dp)))
                Spacer(Modifier.width(4.dp))
                Text(label, style = Type.micro)
                Spacer(Modifier.width(4.dp))
                Text(count, style = Type.micro.copy(fontWeight = FontWeight.Medium), color = Palette.TextSecondary)
            }
        }
    }
}

/** KPI 宽卡（mac KPIWideCard 对位：标题 + 大数字 +（仅里程碑）进度条 + 副说明）。 */
@Composable
fun KpiTile(kpi: DashKpi, modifier: Modifier = Modifier) {
    val accent = when (kpi.kind) {
        DashKpiKind.PROJECTS -> Palette.Accent
        DashKpiKind.MILESTONES -> Palette.Deep
        // attention：没事绿、有事橙，颜色随事实变
        DashKpiKind.ATTENTION -> if (kpi.needsAttention) Palette.Amber else Palette.Green
        DashKpiKind.REACH -> Palette.Green
    }
    GlassCard(modifier) {
        Text(kpi.title, style = Type.label)
        Spacer(Modifier.height(Space.xs))
        Row(verticalAlignment = Alignment.Bottom) {
            Text(kpi.value.toString(), style = Type.display.copy(color = accent), maxLines = 1)
            if (kpi.kind == DashKpiKind.MILESTONES) {
                Spacer(Modifier.width(2.dp))
                Text("%", style = Type.section.copy(color = Palette.TextSecondary))
            }
        }
        // 里程碑完成度才画进度条：给「3 个待处理」画一根进度条是装饰，不是信息
        kpi.progress?.let { p ->
            Spacer(Modifier.height(Space.xs))
            Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(Palette.BarTrack)) {
                Box(Modifier.fillMaxWidth(p.coerceIn(0f, 1f)).height(6.dp).background(accent))
            }
        }
        Spacer(Modifier.height(Space.xs))
        // 副说明可能很长：两行截断（真截到才出 tooltip 全文），不许把四张卡的节奏撑破
        TruncatedText(kpi.caption, style = Type.micro, maxLines = 2)
    }
}

/** 仪表盘整页。 */
@Composable
fun DashboardPage(model: AppModel) {
    val status by model.status.collectAsState()
    val dash by model.dashboard.collectAsState()
    val dashState by model.dashState.collectAsState()
    val refreshing by model.refreshing.collectAsState()
    val busyAction by model.busyAction.collectAsState()
    val reindexBusy = busyAction || refreshing
    val projects = status?.projects.orEmpty()
    // 筛选态挂在 model 上（mac model.dashFilter 对位）：切到别的页再回来，筛选不丢
    val filter = model.dashFilter

    ScrollColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = Space.xl, vertical = Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.lg),
    ) {
        if (registryEmpty(status)) EmptyRegistryCta(model)

        val d = dash
        if (d != null) {
            // ── 段 1：页头（标题 + KPI 汇总行；对位 mac dashboardContent 的 hero）──
            val kpis = dashKpis(d, projects)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Radius.card))
                    .background(heroBrushDiagonal())
                    .drawBehind {
                        // accent 顶 hairline（Fluent 头部点缀）
                        drawRect(color = Palette.Accent.copy(alpha = 0.55f), size = size.copy(height = 1.dp.toPx()))
                    }
                    .padding(horizontal = Space.xl, vertical = Space.lg),
            ) {
                Column(Modifier.weight(1f)) {
                    Text(L10n.t("dash.title"), style = Type.display)
                    Spacer(Modifier.height(4.dp))
                    Text(dashSummaryLine(kpis), style = Type.label)
                }
                // 一键项目群说明（mac GroupBriefButton 对位）：AI 融进操作——固定问题预填打开 agent sheet
                Button(
                    onClick = { model.openAgent(briefTask(null), title = L10n.t("brief.button")) },
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.Card, contentColor = Palette.TextPrimary),
                ) { Text(L10n.t("brief.button")) }
                Spacer(Modifier.width(Space.sm))
                // 刷新：mac 在原生工具栏；CMP 无原生工具栏，这里与菜单条「操作 → 刷新」是同一动作
                Button(
                    onClick = { model.refreshAll() },
                    enabled = !refreshing,
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(containerColor = Palette.Card, contentColor = Palette.TextPrimary),
                ) { Text(if (refreshing) L10n.t("cmp.common.refreshing") else L10n.t("toolbar.refresh")) }
            }

            // ── 段 2：筛选行（时间跨度 / 提交类型 / 重新索引——三个控件都真的改变下面画什么）──
            GlassCard(Modifier.fillMaxWidth()) {
                Row(horizontalArrangement = Arrangement.spacedBy(Space.md), verticalAlignment = Alignment.CenterVertically) {
                    Text(L10n.t("dash.filter.span"), style = Type.label)
                    // 口径写在控件旁：这是「最近更新」分档，不是「这段时间的提交量」。
                    // 芯片组容器用实底 Palette.Card + hairline 描边——pageFill() 在带装饰的皮肤下
                    // 返回透明，芯片组会直接浮在装饰上没有容器（浅色/装饰皮肤对比度缺口）。
                    L10n.t("dash.filter.span.help").let { hint ->
                        HelpTooltip(hint) {
                            Row(
                                Modifier.clip(RoundedCornerShape(Radius.control))
                                    .background(Palette.Card)
                                    .border(Material.borderWidth, Palette.Stroke, RoundedCornerShape(Radius.control))
                                    .padding(2.dp),
                            ) {
                                DashSpan.entries.forEach { s ->
                                    val selected = filter.span == s
                                    Text(
                                        s.label, style = Type.label,
                                        color = if (selected) Palette.TextPrimary else Palette.TextSecondary,
                                        modifier = Modifier
                                            // 焦点环挂在 clickable 上游：键盘焦点画 accent 环，指针会话压环
                                            .focusRing(radius = Radius.chip)
                                            .clip(RoundedCornerShape(Radius.chip))
                                            .background(if (selected) Palette.CardHover else Color.Transparent)
                                            .clickable { model.dashFilter = filter.copy(span = s) }
                                            .padding(horizontal = 10.dp, vertical = 4.dp),
                                    )
                                }
                            }
                        }
                    }
                    // 提交类型下拉：只列真实出现过的类型；一个都没有时禁用并说明原因
                    val commitTypes = availableCommitTypes(projects)
                    var typesOpen by remember { mutableStateOf(false) }
                    Box {
                        HelpTooltip(
                            if (commitTypes.isEmpty()) L10n.t("dash.filter.nocommits") else L10n.t("dash.filter.commits.help"),
                        ) {
                            Text(
                                filter.commits.label, style = Type.label,
                                color = if (commitTypes.isEmpty()) Palette.TextTertiary else Palette.TextPrimary,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(Radius.control))
                                    .background(if (commitTypes.isEmpty()) Palette.BgBase else Palette.CardHover)
                                    .let { m -> if (commitTypes.isEmpty()) m else m.clickable { typesOpen = !typesOpen } }
                                    .padding(horizontal = 10.dp, vertical = 5.dp)
                                    .width(170.dp),
                            )
                        }
                        if (typesOpen) {
                          // 弹层不参与父盒子的尺寸（matchParentSize），定位在控件正下方
                          Box(Modifier.matchParentSize()) {
                            Column(
                                Modifier.offset(y = 30.dp).width(200.dp)
                                    .shadow(8.dp, RoundedCornerShape(Radius.control))
                                    .background(Palette.Card).border(Material.borderWidth, Palette.Stroke, RoundedCornerShape(Radius.control))
                                    .padding(Space.xs),
                            ) {
                                Text(
                                    DashCommitFilter.All.label, style = Type.body,
                                    modifier = Modifier.fillMaxWidth()
                                        .clickable { model.dashFilter = filter.copy(commits = DashCommitFilter.All); typesOpen = false }
                                        .padding(horizontal = 10.dp, vertical = 6.dp),
                                )
                                commitTypes.forEach { t ->
                                    Text(
                                        t, style = Type.body,
                                        modifier = Modifier.fillMaxWidth()
                                            .clickable { model.dashFilter = filter.copy(commits = DashCommitFilter.Only(t)); typesOpen = false }
                                            .padding(horizontal = 10.dp, vertical = 6.dp),
                                    )
                                }
                            }
                          }
                        }
                    }
                    Button(
                        onClick = { model.runUpdate(deep = false) },
                        enabled = !reindexBusy,
                        shape = RoundedCornerShape(Radius.control),
                        colors = ButtonDefaults.buttonColors(containerColor = Palette.Card, contentColor = Palette.TextPrimary),
                    ) {
                        if (reindexBusy) {
                            CircularProgressIndicator(Modifier.size(12.dp), color = Palette.Accent, strokeWidth = 2.dp)
                            Spacer(Modifier.width(6.dp))
                            Text(L10n.t("cmp.dash.reindexing"), style = Type.body)
                        } else {
                            IconBox(FluentIcon.ArrowSync, size = 16.dp)
                            Spacer(Modifier.width(6.dp))
                            Text(L10n.t("dash.reindex"), style = Type.body)
                        }
                    }
                    Spacer(Modifier.weight(1f))
                }
            }

            // ── 段 3：4 张精选 KPI ──
            Row(horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                kpis.forEach { KpiTile(it, Modifier.weight(1f)) }
            }

            // ── 段 4：逐项目进度卡网格（受时间跨度筛选）──
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.md)) {
                val shown = projects.filter { filter.keeps(it) }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(L10n.t("dash.grid.title"), style = Type.section)
                    Spacer(Modifier.weight(1f))
                    Text(
                        if (shown.size == projects.size) L10n.t("dash.grid.all", projects.size)
                        else L10n.t("dash.grid.filtered", shown.size, projects.size, filter.span.label),
                        style = Type.label,
                    )
                }
                if (projects.isNotEmpty() && shown.isEmpty()) {
                    GlassCard(Modifier.fillMaxWidth()) {
                        Text(L10n.t("dash.grid.none.title"), style = Type.section)
                        Text(L10n.t("dash.grid.none.body", projects.size, filter.span.label), style = Type.label)
                        Spacer(Modifier.height(Space.sm))
                        // 空态要教下一步：一键恢复默认口径（全部时间跨度 + 全部提交类型），
                        // 不让用户自己回想刚才拨了哪个开关
                        ActionText(L10n.t("cmp.ms.allShort"), Palette.Accent) {
                            model.dashFilter = DashFilter()
                        }
                    }
                }
                shown.chunked(2).forEach { rowProjects ->
                    Row(horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                        rowProjects.forEach { proj ->
                            ProjectProgressCard(
                                p = proj,
                                milestones = d.milestones.items.filter { it.projectId == proj.id },
                                filter = filter,
                                onOpen = { model.goRoute(AppModel.Route.PROJECT, proj.name) },
                                modifier = Modifier.weight(1f),
                            )
                        }
                        if (rowProjects.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }

            // ── 语言分布 ‖ 里程碑 ──
            Row(horizontalArrangement = Arrangement.spacedBy(Space.lg)) {
                SectionCard(L10n.t("dash.langDist"), Modifier.weight(1f)) {
                    val langs = d.languages
                    val coverage = languageCoverage(
                        languageCount = langs.size,
                        truncated = d.languagesTruncated == true,
                        failed = d.languagesFailed,
                        reasons = d.languagesFailedReasons,
                        topCut = d.languagesTopCut == true,
                        shownCount = minOf(langs.size, LANG_BAR_MAX),
                    )
                    if (langs.isEmpty()) {
                        Text(coverage.emptyTitle, style = Type.body.copy(color = Palette.TextTertiary))
                    } else {
                        val shownLangs = langs.take(LANG_BAR_MAX)
                        SegmentedBar(shownLangs.map { it.count }, shownLangs.indices.map { Composition12[it] })
                        Spacer(Modifier.height(Space.sm))
                        shownLangs.forEachIndexed { i, l ->
                            Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.size(7.dp).background(Composition12[i], CircleShape))
                                Spacer(Modifier.width(Space.sm))
                                Text(l.language, style = Type.label, modifier = Modifier.weight(1f))
                                Text("${l.count}", style = Type.label.copy(fontWeight = FontWeight.Medium), color = Palette.TextSecondary)
                            }
                        }
                    }
                    coverage.note?.let {
                        Spacer(Modifier.height(Space.xs))
                        Text(it, style = Type.micro)
                    }
                }
                SectionCard(milestoneCardTitle(d.milestones.counts), Modifier.weight(1f)) {
                    val items = d.milestones.items
                    if (items.isEmpty()) {
                        val degraded = d.milestones.counts.degraded
                        Text(
                            if (degraded) L10n.t("dash.msCard.unreadable") else L10n.t("dash.msCard.none"),
                            style = Type.body.copy(color = if (degraded) Palette.Amber else Palette.TextTertiary),
                        )
                        Text(
                            if (degraded) L10n.t("dash.msCard.degradedetail", d.milestones.counts.storeHealth, d.milestones.counts.readCount)
                            else L10n.t("dash.msCard.addHint"),
                            style = Type.label,
                        )
                        // addHint 只教「去哪加」，不导——给它配一个直达入口（ms.new 现成键）。
                        // 降级（读不出来）时入口不出现：现在该说的是存储健康，不是让人去新建
                        if (!degraded) {
                            Spacer(Modifier.height(Space.sm))
                            ActionText(L10n.t("ms.new"), Palette.Accent) { model.goRoute(AppModel.Route.MILESTONES) }
                        }
                    } else {
                        val slice = milestoneCardSlice(items.size)
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            items.take(slice.shown).forEach { m ->
                                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                    val done = m.status == "done"
                                    Box(
                                        Modifier.size(7.dp).background(
                                            when {
                                                done -> Palette.Green
                                                m.overdue -> Palette.Red
                                                else -> Palette.TextSecondary
                                            },
                                            CircleShape,
                                        ),
                                    )
                                    Spacer(Modifier.width(Space.sm))
                                    Text(m.projectName, style = Type.label)
                                    Spacer(Modifier.width(Space.xs))
                                    Text(m.name, style = Type.body.copy(fontWeight = FontWeight.Medium))
                                    Spacer(Modifier.weight(1f))
                                    milestoneDueText(m).takeIf { it.isNotBlank() }?.let {
                                        Text(it, style = Type.label, color = if (m.overdue) Palette.Red else Palette.TextSecondary)
                                    }
                                }
                            }
                        }
                        slice.note?.let {
                            Spacer(Modifier.height(Space.xs))
                            Text(it, style = Type.micro)
                        }
                    }
                }
            }

            // ── 近 7 天活跃 ──
            if (d.activeProjects.isNotEmpty()) {
                SectionCard(L10n.t("dash.active.title", d.activeProjects.size), Modifier.fillMaxWidth()) {
                    d.activeProjects.forEach { a ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(7.dp).background(Palette.Green, CircleShape))
                            Spacer(Modifier.width(Space.sm))
                            Text(a.name, style = Type.body)
                            Spacer(Modifier.weight(1f))
                            Text(a.lastCommitAgo, style = Type.label, color = Palette.TextSecondary)
                            a.headline?.let {
                                Spacer(Modifier.width(Space.md))
                                // 长标题：280dp 封顶 + ellipsis，真截到才悬停给全文
                                TruncatedText(it, Modifier.widthIn(max = 280.dp), color = Palette.TextTertiary)
                            }
                        }
                    }
                }
            }
        } else {
            when (val st = dashState) {
                is LoadState.Failed -> GlassCard(Modifier.fillMaxWidth()) {
                    Text(L10n.t("dash.failed.title"), style = Type.section.copy(color = Palette.Amber))
                    Spacer(Modifier.height(Space.xs))
                    Text(st.reason, style = Type.body.copy(color = Palette.TextSecondary))
                }
                else -> {
                    // 首读加载态：形状占位（微光扫过），不转圈——4 张 KPI 骨架 tile + 2 张项目卡骨架，
                    // 版面节奏与加载完成后的「4 KPI → 项目卡网格」对得上，避免文字卡换骨架时的版面跳动
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.md)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                            repeat(4) { SkeletonCard(Modifier.weight(1f)) }
                        }
                        repeat(2) { SkeletonCard(Modifier.fillMaxWidth(), height = 176.dp) }
                    }
                }
            }
        }
    }
}

/** 空态 CTA 磁贴（对位 mac/bui `.empty`「还没有注册项目」+ 扫描/添加入口）。 */
@Composable
private fun EmptyRegistryCta(model: AppModel) {
    val busy by model.busyAction.collectAsState()
    val lastResult by model.lastResult.collectAsState()
    var scanRoot by remember { mutableStateOf(System.getProperty("user.home") ?: "") }
    var scanDepth by remember { mutableStateOf("2") }
    var addPath by remember { mutableStateOf("") }
    var addName by remember { mutableStateOf("") }

    GlassCard(Modifier.fillMaxWidth()) {
        Text(L10n.t("cmp.dash.heroEmpty"), style = Type.section)
        Spacer(Modifier.height(Space.xs))
        Text(L10n.t("cmp.dash.heroEmptyBody"), style = Type.body.copy(color = Palette.TextSecondary))
        Spacer(Modifier.height(Space.sm))
        // ── 扫描行 ──
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            OutlinedTextField(
                colors = fluentTextFieldColors(),
                value = scanRoot,
                onValueChange = { scanRoot = it },
                placeholder = { Text(L10n.t("cmp.scan.rootLabel"), style = Type.micro) },
                singleLine = true,
                textStyle = Type.body,
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
                colors = fluentTextFieldColors(),
                value = scanDepth,
                onValueChange = { scanDepth = it },
                placeholder = { Text(L10n.t("cmp.scan.depthShort"), style = Type.micro) },
                singleLine = true,
                textStyle = Type.body,
                modifier = Modifier.width(72.dp),
            )
            Button(
                onClick = { model.scanProjects(scanRoot.trim(), scanDepth.trim().toIntOrNull() ?: 2) },
                enabled = !busy && scanRoot.isNotBlank(),
                shape = RoundedCornerShape(Radius.control),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Palette.OnAccent),
            ) { Text(L10n.t("scan.run")) }
        }
        Spacer(Modifier.height(Space.sm))
        // ── 添加行 ──
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            OutlinedTextField(
                colors = fluentTextFieldColors(),
                value = addPath,
                onValueChange = { addPath = it },
                placeholder = { Text(L10n.t("cmp.scan.pathLabel"), style = Type.micro) },
                singleLine = true,
                textStyle = Type.body,
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
                colors = fluentTextFieldColors(),
                value = addName,
                onValueChange = { addName = it },
                placeholder = { Text(L10n.t("cmp.scan.nameOptional"), style = Type.micro) },
                singleLine = true,
                textStyle = Type.body,
                modifier = Modifier.width(120.dp),
            )
            Button(
                onClick = { model.addProjectPath(addPath.trim(), addName.trim().takeIf { it.isNotBlank() }) },
                enabled = !busy && addPath.isNotBlank(),
                shape = RoundedCornerShape(Radius.control),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Palette.OnAccent),
            ) { Text(L10n.t("scan.add")) }
        }
        // 操作结果/失败原因就在按钮下方如实披露（写操作必须留结果）
        lastResult?.let {
            Spacer(Modifier.height(Space.sm))
            Text(it, style = Type.body.copy(color = Palette.TextSecondary))
        }
    }
}

/** 里程碑完成率（mac ProjectProgressCard.milestoneRatio 对位：达成 / (达成 + 进行中)，unknown 不计入）。 */
data class MilestoneRatio(val done: Int, val open: Int, val unknown: Int) {
    val ratio: Float? get() = if (done + open == 0) null else done.toFloat() / (done + open)
}

fun milestoneRatioOf(milestones: List<Milestone>): MilestoneRatio {
    val done = milestones.count { it.status == "done" }
    val open = milestones.count { it.status == "open" }
    val unknown = milestones.count { it.status == "unknown" }
    return MilestoneRatio(done, open, unknown)
}

/** 状态词颜色（mac ProjectProgressCard.stateWord 的 tone → color）。 */
private fun livenessTone(l: Liveness): Color = when (l) {
    Liveness.UNREADABLE, Liveness.UNKNOWN -> Palette.Red
    Liveness.NOT_GIT -> Palette.TextSecondary
    Liveness.NEEDS_ACTION -> Palette.Amber
    Liveness.ENGINE_STALE, Liveness.QUIET -> Palette.TextSecondary
    Liveness.RECENT -> Palette.Green
}

/**
 * 逐项目进度卡（mac ProjectProgressCard 对位）：
 * 标识 → 状态 → 描述 → 里程碑完成度 + 分支 → 提交结构（受类型筛选）→ 最近提交 + 入口。
 */
@Composable
fun ProjectProgressCard(
    p: Project,
    milestones: List<Milestone>,
    filter: DashFilter,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GlassCard(
        // 整卡可点：焦点环挂在 clickable 上游（键盘焦点画 accent 环，指针会话压环）；
        // hover 上浮/提亮在 GlassCard（interactive=true）里挂，链序与 ButtonChrome 同构
        modifier.fillMaxWidth().focusRing(radius = Radius.card).clickable { onOpen() },
        interactive = true,
    ) {
        // 行 1：项目名（等宽）+ 状态词
        val l = livenessOf(p)
        Row(verticalAlignment = Alignment.CenterVertically) {
            // 长项目名：ellipsis + 真截到才出 tooltip 全文（原来 maxLines=1 硬截，读不到全名）
            Box(Modifier.weight(1f, fill = false)) {
                TruncatedText(p.name, style = Type.card.copy(fontFamily = Mono))
            }
            Spacer(Modifier.weight(1f))
            Box(Modifier.size(7.dp).background(livenessTone(l), CircleShape))
            Spacer(Modifier.width(Space.xs))
            // 「久未更新」要说清是多少天（不传天数会显示成「? 天没更新」）
            Text(stateWordOf(l, daysSinceLastCommit(p)), style = Type.label, color = livenessTone(l))
        }
        Spacer(Modifier.height(Space.xs))
        // 行 2：一句描述。读不出来时不能编一句
        Text(
            if (!p.isReadable) p.error ?: L10n.t("dash.card.unreadable")
            else p.headline?.takeIf { it.isNotBlank() } ?: L10n.t("dash.card.nosummary"),
            style = Type.label,
            color = if (!p.isReadable) Palette.Red else Palette.TextSecondary,
            maxLines = 2,
        )
        Spacer(Modifier.height(Space.xs))
        // 行 3：里程碑完成度 + 分支
        Row(verticalAlignment = Alignment.CenterVertically) {
            val m = milestoneRatioOf(milestones)
            val decided = m.done + m.open
            when {
                decided == 0 && m.unknown > 0 -> Text(L10n.t("dash.ms.unreadableCount", m.unknown), style = Type.label, color = Palette.Amber)
                decided == 0 -> Text(L10n.t("dash.ms.none"), style = Type.label, color = Palette.TextTertiary)
                else -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                    Text(L10n.t("dash.ms.label"), style = Type.label, color = Palette.TextTertiary)
                    Text("${m.done}/$decided", style = Type.label.copy(fontWeight = FontWeight.Medium), color = Palette.TextSecondary)
                    val pct = (m.done.toDouble() * 100 / decided).roundToInt()
                    Text("$pct%", style = Type.label.copy(fontWeight = FontWeight.SemiBold), color = Palette.Deep)
                    if (m.unknown > 0) Text(L10n.t("dash.ms.unknownNote", m.unknown), style = Type.label, color = Palette.Amber)
                }
            }
            Spacer(Modifier.weight(1f))
            Text(L10n.t("dash.card.branch"), style = Type.label, color = Palette.TextTertiary)
            Spacer(Modifier.width(Space.xs))
            // 引擎恒发 currentBranch；追踪数组空时不能说「无分支记录」——那正是把「不知道」说成「没有」
            val branchLabel = p.primaryBranch?.name ?: p.currentBranch?.takeIf { it.isNotBlank() } ?: L10n.t("detail.nobranch")
            TruncatedText(branchLabel, style = Type.label.copy(fontFamily = Mono), color = Palette.TextSecondary)
        }
        // 行 4：提交结构（堆叠条 + 图例，受提交类型筛选控制）
        if (p.isReadable) {
            Spacer(Modifier.height(Space.sm))
            val all = p.commitTypes
            val kept = filter.keptStats(all)
            when {
                all.isEmpty() -> Text(L10n.t("dash.card.nohistory"), style = Type.label, color = Palette.TextTertiary)
                // 筛到一个都不剩时必须说出来，不能画一根空条装作「没有提交」
                kept.isEmpty() -> Text(L10n.t("dash.card.nomatch"), style = Type.label, color = Palette.TextTertiary)
                else -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(L10n.t("dash.card.composition"), style = Type.label, color = Palette.TextTertiary)
                        Spacer(Modifier.weight(1f))
                        // 样本披露：commitTypes 是最近 N 条的样本，拿样本当全量是修过的缺陷
                        if (p.commitTypesTruncated == true) Text(L10n.t("dash.card.sample"), style = Type.label, color = Palette.Amber)
                    }
                    Spacer(Modifier.height(Space.xs))
                    CommitCompositionBlock(kept, sampleTruncated = false)
                }
            }
        }
        // 行 5：最近提交 + 进入独立管控页的入口
        Spacer(Modifier.height(Space.sm))
        Row(verticalAlignment = Alignment.CenterVertically) {
            val head = p.primaryBranch
            val branchDetailMissing = p.primaryBranch == null && p.isReadable
            when {
                head != null -> {
                    TruncatedText(head.headShort.ifBlank { head.name }, style = Type.label.copy(fontFamily = Mono), color = Palette.TextSecondary)
                    Spacer(Modifier.width(Space.sm))
                    // 长提交标题吃掉剩余宽度（weight 的 TruncatedText 外包一层 Box），动作 chip 不被挤走
                    Box(Modifier.weight(1f)) {
                        TruncatedText(head.headSubject.ifBlank { head.summary }, color = Palette.TextTertiary)
                    }
                }
                // 明细读不到 ≠ 没有提交。这句话必须存在，否则「空着的一行」会被读成「什么都没干」
                branchDetailMissing -> Text(L10n.t("detail.branch.untracked"), style = Type.label, color = Palette.TextTertiary, modifier = Modifier.weight(1f))
                else -> Text(L10n.t("dash.card.unreadableShort"), style = Type.label, color = Palette.Red, modifier = Modifier.weight(1f))
            }
            Spacer(Modifier.width(Space.sm))
            // 可点入口归 chip 语义：形状跟皮肤圆角（Badge.chipShape），内边距统一 chip 档（h12/v6）；
            // 焦点环挂 clickable 上游——键盘用户 Tab 到这里也有可见落点
            Text(
                L10n.t("detail.enter") + " →",
                style = Type.label,
                color = Palette.Accent,
                modifier = Modifier
                    .focusRing()
                    .clip(Badge.chipShape)
                    .background(Palette.Accent.copy(alpha = 0.12f))
                    .clickable { onOpen() }
                    .padding(horizontal = Badge.chipPadH, vertical = Badge.chipPadV),
            )
        }
    }
}
