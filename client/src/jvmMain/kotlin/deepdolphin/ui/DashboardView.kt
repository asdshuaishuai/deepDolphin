// DashboardView.kt —— 仪表盘页（C3）：KPI 磁贴 / 语言分布 / 里程碑 / 活跃项目 + 筛选行。
//
// 判定与披露全部来自 logic 层产物（DashboardData 字段），不内联口径；
// 失败披露诚实（采集失败/语言读不出来的原因列出来，不静默）。

package deepdolphin.ui

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
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import deepdolphin.engine.*
import deepdolphin.ui.Palette
import deepdolphin.ui.Radius
import deepdolphin.ui.heroBrushDiagonal
import deepdolphin.ui.Space
import deepdolphin.ui.Type

/** 玻璃磁贴（对位 .card：底 + 描边；.card.hoverable：hover 换底色/描边并上移 2px）。 */
@Composable
fun GlassCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    Column(
        modifier
            .hoverable(interaction)
            .offset(y = if (hovered) (-2).dp else 0.dp) // translateY(-2px)，不动其余几何
            .clip(RoundedCornerShape(Radius.card))
            .border(1.dp, if (hovered) Palette.StrokeHover else Palette.Stroke, RoundedCornerShape(Radius.card))
            .background(if (hovered) Palette.CardHover else Palette.Card)
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

/** KPI 宽卡（对位 mac KPIWideCard：label 顶 + 大数字 accent +（可选）进度条 + 副说明 tertiary）。
 *  进度条只画「完成度」本身有进度语义的指标（里程碑完成率）；给「3 个待处理」画进度条是装饰不是信息。 */
@Composable
fun KpiTile(
    title: String,
    value: String,
    subtitle: String,
    modifier: Modifier = Modifier,
    tone: Color = Palette.Accent,
    progress: Float? = null,
) {
    GlassCard(modifier) {
        Text(title, style = Type.label)
        Spacer(Modifier.height(Space.xs))
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                value, style = Type.display.copy(color = tone),
                maxLines = 1,
            )
        }
        progress?.let { p ->
            Spacer(Modifier.height(Space.xs))
            Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(Palette.BarTrack)) {
                Box(
                    Modifier.fillMaxWidth(p.coerceIn(0f, 1f)).height(6.dp)
                        .clip(RoundedCornerShape(3.dp)).background(tone)
                )
            }
        }
        subtitle.takeIf { it.isNotBlank() }?.let {
            Spacer(Modifier.height(Space.xs))
            Text(it, style = Type.micro, maxLines = 2)
        }
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
    var window by remember { mutableStateOf("all") } // all / 30d / 7d（C3 筛选，批 1 先做时间窗胶囊）

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Space.xl, vertical = Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.lg),
    ) {
        // ── hero 页头（DSGradient.hero：靛→紫→青；产品的「封面」，两处共用一张底的纪律在此继承）──
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Radius.control))
                .background(heroBrushDiagonal())
                .padding(horizontal = Space.xl, vertical = Space.lg),
        ) {
            Column(Modifier.weight(1f)) {
                Text(L10n.t("dash.title"), style = Type.display.copy(color = Color.White))
                Spacer(Modifier.height(4.dp))
                Text(
                    buildString {
                        append(L10n.t("cmp.dash.registered", dash?.projects?.total ?: status?.projects?.size ?: 0))
                        dash?.fetchedAt?.takeIf { it.isNotBlank() }?.let { append(L10n.t("cmp.dash.fetchedAt", it)) }
                        append(L10n.t("cmp.dash.engineLine"))
                        // 深更新会动哪些托管文档写在按钮附近（mac 纪律：动手前必须看得见）
                        append(L10n.t("cmp.dash.deepDocs"))
                    },
                    style = Type.label.copy(color = Color.White.copy(alpha = 0.85f)),
                )
            }
            // 一键项目群说明（mac GroupBriefButton 对位，L10n "dash.projectBrief"）：AI 融进操作——
            // hero 就地带固定问题预填打开 agent sheet（作用域=项目群），不做独立 AI 入口；
            // 「添加/扫描」开扫描单（mac 侧栏添加/扫描动作 + PanelView.swift:92-94 sheet 挂点对位，
            // 单是两种模式：单个添加 / 批量扫描——注册表非空时也要能再进项目）
            //
            // ⚠️ 双轨更新（浅/深）已按 mac 布局归位到内容区顶部 WorkBar 工作条
            // （mac WorkBar.swift：主链路与工具类动作分家——hero 只留工具类动作
            // 与「刷新」）。刷新是工具类（对读流的操作），留在 hero 右侧。
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                Button(
                    onClick = { model.openScanSheet(single = true) },
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color.White.copy(alpha = 0.18f),
                        contentColor = Color.White,
                    ),
                ) { Text(L10n.t("scan.add")) }
                Button(
                    onClick = { model.openScanSheet(single = false) },
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color.White.copy(alpha = 0.18f),
                        contentColor = Color.White,
                    ),
                ) { Text(L10n.t("scan.run")) }
                Button(
                    onClick = { model.openAgent(briefTask(null), title = L10n.t("brief.button")) },
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color.White.copy(alpha = 0.18f),
                        contentColor = Color.White,
                    ),
                ) { Text(L10n.t("brief.button")) }
                Button(
                    onClick = { model.refreshAll() },
                    enabled = !refreshing,
                    shape = RoundedCornerShape(Radius.control),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color.White.copy(alpha = 0.18f),
                        contentColor = Color.White,
                    ),
                ) { Text(if (refreshing) L10n.t("cmp.common.refreshing") else L10n.t("toolbar.refresh")) }
            }
        }

        // ── 筛选行（时间窗胶囊 + 重新索引；mac DashboardFilterBar 三件套对位）──
        Row(horizontalArrangement = Arrangement.spacedBy(Space.sm), verticalAlignment = Alignment.CenterVertically) {
            listOf("all" to L10n.t("cmp.dash.spanAll"), "30d" to L10n.t("cmp.dash.span30"), "7d" to L10n.t("cmp.dash.span7")).forEach { (k, label) ->
                val selected = window == k
                Text(
                    label,
                    style = Type.body.copy(fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal),
                    color = if (selected) Color.White else Palette.TextSecondary,
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(if (selected) Palette.Accent else Palette.Card)
                        .clickable { window = k }
                        .padding(horizontal = 14.dp, vertical = 6.dp),
                )
            }
            Spacer(Modifier.weight(1f))
            // 重新索引（mac DashboardParts.swift:74-84 对位）：**真跑一次全局浅更新 + 重拉仪表盘**，
            // 不是装饰按钮。busy 态如实（转圈 + 禁用，busy 时不叠加）。
            //
            // 【引擎命令调查，真跑 `moongit --help` 锚定】引擎确有索引/重建子命令
            // `index <gen|overview|update|query>`——但那是**符号级持久化代码索引**
            // （graph 系的 db + index.json），与仪表盘数据无关。mac 基准的「重新索引」
            // 语义是浅更新：L10n zh help「重新采集一次浅更新」+ DetailViews.swift:1085-1093
            // reindex() = runUpdate(deep: false) + fetchDashboard()。对位 mac 走 updateAll(false)
            // （withAction 内已含 refreshAll，等价 mac「跑完必须重新拉仪表盘」）。
            val reindexBusy = busyAction || refreshing
            Button(
                onClick = { model.updateAll(deep = false) },
                enabled = !reindexBusy,
                shape = RoundedCornerShape(Radius.control),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Palette.Card,
                    contentColor = Palette.TextPrimary,
                ),
            ) {
                if (reindexBusy) {
                    CircularProgressIndicator(
                        Modifier.size(12.dp),
                        color = Palette.Accent,
                        strokeWidth = 2.dp,
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(L10n.t("cmp.dash.reindexing"), style = Type.body)
                } else {
                    Text("⟳ " + L10n.t("dash.reindex"), style = Type.body)
                }
            }
            Text(L10n.t("cmp.dash.filterHint"), style = Type.micro)
        }

        // ── 空态 CTA（真的没有项目才出现；加载中/读不出来不冒充空态）──
        if (registryEmpty(status)) EmptyRegistryCta(model)

        when (dashState) {
            is LoadState.Failed -> GlassCard(Modifier.fillMaxWidth()) {
                Text(L10n.t("dash.failed.title"), style = Type.section.copy(color = Palette.Amber))
                Spacer(Modifier.height(Space.xs))
                Text((dashState as LoadState.Failed).reason, style = Type.body.copy(color = Palette.TextSecondary))
            }
            else -> {
                // ── 采集失败披露（诚实：原因来自引擎，不推断）──
                val failed = status?.projects.orEmpty().filter { !it.isReadable }
                if (failed.isNotEmpty()) GlassCard(Modifier.fillMaxWidth()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Pill(L10n.t("cmp.dash.failedN", failed.size), Palette.Amber)
                        Spacer(Modifier.width(Space.sm))
                        Text(L10n.t("cmp.dash.failedTitle"), style = Type.card)
                    }
                    Spacer(Modifier.height(Space.sm))
                    failed.forEach { p ->
                        Row(Modifier.padding(vertical = 2.dp)) {
                            Pill(p.name, Palette.Red)
                            Spacer(Modifier.width(Space.sm))
                            Text(p.error ?: L10n.t("cmp.err.noReasonAlt"), style = Type.body.copy(color = Palette.TextSecondary))
                        }
                    }
                }

                // ── KPI 四磁贴 ──
                Row(horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                    val d = dash
                    KpiTile(L10n.t("dash.projectCount"), "${d?.projects?.total ?: 0}",
                        L10n.t("cmp.dash.kpiScope", d?.projects?.readable ?: 0, d?.projects?.failed ?: 0),
                        Modifier.weight(1f))
                    KpiTile(L10n.t("dash.pendingCount"), "${status?.summary?.dirtyProjects ?: 0}",
                        L10n.t("cmp.dash.pendingHint"),
                        Modifier.weight(1f), tone = Palette.Amber)
                    KpiTile(L10n.t("cmp.dash.activeShort"), "${d?.projects?.readable ?: 0}",
                        L10n.t("cmp.dash.activeHint"),
                        Modifier.weight(1f), tone = Palette.Green)
                    KpiTile(L10n.t("cmp.dash.stale"), "${status?.summary?.staleProjects ?: 0}",
                        L10n.t("cmp.dash.staleHint"),
                        Modifier.weight(1f))
                }

                // ── 段 4：逐项目进度卡网格（mac DashboardParts 段 4 对位）──
                Text(L10n.t("dash.grid.title"), style = Type.section)
                Text(
                    buildString {
                        append(L10n.t("cmp.dash.totalN", status?.projects.orEmpty().size))
                        dash?.fetchedAt?.takeIf { it.isNotBlank() }?.let { append(L10n.t("cmp.dash.fetchedAt", it)) }
                    },
                    style = Type.micro,
                )
                val msAll = model.milestones.collectAsState().value?.milestones.orEmpty()
                val readableProjects = status?.projects.orEmpty().filter { it.isReadable }
                if (readableProjects.isEmpty()) {
                    SectionCard(L10n.t("cmp.dash.noProjects"), Modifier.fillMaxWidth()) {
                        Text(L10n.t("cmp.dash.noProjectsHint"), style = Type.body.copy(color = Palette.TextTertiary))
                    }
                } else {
                    readableProjects.chunked(2).forEach { rowProjects ->
                        Row(horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                            rowProjects.forEach { proj ->
                                ProjectProgressCard(
                                    p = proj,
                                    milestones = msAll.filter { it.projectId == proj.id },
                                    onOpen = { },
                                    modifier = Modifier.weight(1f),
                                )
                            }
                            if (rowProjects.size == 1) Spacer(Modifier.weight(1f))
                        }
                    }
                }

                // ── 语言分布 ──
                SectionCard(L10n.t("dash.langDist"), Modifier.fillMaxWidth()) {
                    val langs = dash?.languages.orEmpty()
                    if (langs.isEmpty()) {
                        Text(L10n.t("cmp.dash.noLangs"), style = Type.body.copy(color = Palette.TextSecondary))
                    } else {
                        langs.take(6).forEach { lang ->
                            Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(lang.language, style = Type.body, modifier = Modifier.width(120.dp))
                                val max = langs.maxOf { it.count }.coerceAtLeast(1)
                                Box(
                                    Modifier.weight(1f).height(8.dp).clip(RoundedCornerShape(4.dp))
                                        .background(Palette.BarTrack)
                                ) {
                                    Box(
                                        Modifier.fillMaxWidth(lang.count.toFloat() / max).height(8.dp)
                                            .clip(RoundedCornerShape(4.dp)).background(Palette.Accent)
                                    )
                                }
                                Spacer(Modifier.width(Space.sm))
                                Text("${lang.count}", style = Type.body, modifier = Modifier.width(48.dp))
                            }
                        }
                        // 截断/失败披露
                        dash?.languagesFailed?.takeIf { it > 0 }?.let {
                            Spacer(Modifier.height(Space.xs))
                            Text(
                                L10n.t("cmp.dash.langUnreadable", it) +
                                    (dash?.languagesFailedReasons?.takeIf { r -> r.isNotEmpty() }?.let { r -> "：${r.joinToString("；")}" } ?: ""),
                                style = Type.micro,
                            )
                        }
                        if (dash?.languagesTruncated == true) Text(L10n.t("cmp.dash.langTruncated"), style = Type.micro)
                    }
                }

                // ── 里程碑 ──
                SectionCard(L10n.t("cmp.dash.msCard"), Modifier.fillMaxWidth()) {
                    val ms = dash?.milestones
                    Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                        Pill(L10n.t("cmp.dash.msOpen", ms?.counts?.open ?: 0), Palette.Accent)
                        Pill(L10n.t("cmp.dash.msDone", ms?.counts?.done ?: 0), Palette.Green)
                        Pill(L10n.t("cmp.dash.msDropped", ms?.counts?.dropped ?: 0), Palette.TextSecondary)
                        Pill(L10n.t("cmp.dash.msUnverifiable", ms?.counts?.unverifiable ?: 0), Palette.Amber)
                        Pill(L10n.t("cmp.dash.msEngineRead", ms?.counts?.engineRead ?: 0), Palette.TextSecondary)
                    }
                    ms?.storeHealth?.takeIf { it.isNotBlank() && it != "ok" }?.let {
                        Spacer(Modifier.height(Space.xs))
                        Text(L10n.t("cmp.dash.storeHealth", it), style = Type.micro.copy(color = Palette.Amber))
                    }
                }

                // ── 活跃项目 ──
                SectionCard(L10n.t("dash.activeCount"), Modifier.fillMaxWidth()) {
                    val act = dash?.activeProjects.orEmpty()
                    if (act.isEmpty()) Text(L10n.t("cmp.dash.noActive"), style = Type.body.copy(color = Palette.TextSecondary))
                    else act.forEach { ap ->
                        Row(Modifier.padding(vertical = 3.dp)) {
                            Text(ap.name, style = Type.body.copy(fontWeight = FontWeight.Medium))
                            ap.headline?.let {
                                Spacer(Modifier.width(Space.sm))
                                Text(it, style = Type.label, maxLines = 1)
                            }
                        }
                    }
                }
            }
        }
    }
}

/** 空态 CTA 磁贴（对位 mac/bui `.empty`「还没有注册项目」+ 扫描/添加入口）：
 *  扫描根目录 / 添加项目路径两行表单，接引擎 scan/add；结果与失败原因一行如实披露。 */
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
        Text(
            L10n.t("cmp.dash.heroEmptyBody"),
            style = Type.body.copy(color = Palette.TextSecondary),
        )
        Spacer(Modifier.height(Space.sm))
        // ── 扫描行 ──
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            OutlinedTextField(
                value = scanRoot,
                onValueChange = { scanRoot = it },
                placeholder = { Text(L10n.t("cmp.scan.rootLabel"), style = Type.micro) },
                singleLine = true,
                textStyle = Type.body,
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
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
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
            ) { Text(L10n.t("scan.run")) }
        }
        Spacer(Modifier.height(Space.sm))
        // ── 添加行 ──
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            OutlinedTextField(
                value = addPath,
                onValueChange = { addPath = it },
                placeholder = { Text(L10n.t("cmp.scan.pathLabel"), style = Type.micro) },
                singleLine = true,
                textStyle = Type.body,
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
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
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
            ) { Text(L10n.t("scan.add")) }
        }
        // 操作结果/失败原因就在按钮下方如实披露（写操作必须留结果）
        lastResult?.let {
            Spacer(Modifier.height(Space.sm))
            Text(it, style = Type.body.copy(color = Palette.TextSecondary))
        }
    }
}

/** 胶囊 pill（语义色底 + 深色文字 = WCAG 对比度纪律）。 */
@Composable
fun Pill(text: String, color: Color) {
    Text(
        text,
        style = Type.micro.copy(fontWeight = FontWeight.SemiBold),
        color = Palette.BgBase,
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(color.copy(alpha = 0.9f))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

/** 里程碑完成率（对位 mac ProjectProgressCard.milestoneRatio：达成 / (达成 + 进行中)，unknown 不计入）。 */
data class MilestoneRatio(val done: Int, val open: Int, val unknown: Int) {
    val ratio: Float? get() = if (done + open == 0) null else done.toFloat() / (done + open)
}

fun milestoneRatioOf(milestones: List<Milestone>): MilestoneRatio {
    val done = milestones.count { it.status == "done" }
    val open = milestones.count { it.status == "open" }
    val unknown = milestones.count { it.status == "unknown" }
    return MilestoneRatio(done, open, unknown)
}

// ── 双轨按钮的范围文案与待记录数（shallowUpdateLabel / deepUpdateLabel / pendingCommitsOf）
//    已随双轨按钮归位迁至 WorkBar.kt（判据 HeroUpdateScopeTest 引用不变，同包）──

/** 逐项目进度卡（mac ProjectProgressCard 对位）：标识 → 状态 → 里程碑/分支 → 最近提交 → 入口。 */
@Composable
fun ProjectProgressCard(
    p: Project,
    milestones: List<Milestone>,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GlassCard(modifier.fillMaxWidth()) {
        // 行 1：标识（mono 名 + 待处理 pill）
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(p.name, style = Type.card.copy(fontWeight = FontWeight.Bold))
            Spacer(Modifier.width(Space.sm))
            val dirty = p.userDirtyCount ?: 0
            if (dirty > 0) Pill("●$dirty", Palette.Amber)
        }
        Spacer(Modifier.height(Space.xs))
        // 行 2：状态（可读=进展摘要；读不出=原因）
        if (!p.isReadable) {
            Text(L10n.t("cmp.dash.unreadableWith", p.error ?: L10n.t("cmp.err.noReason")), style = Type.micro.copy(color = Palette.Red))
        } else {
            p.headline?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = Type.body.copy(color = Palette.TextSecondary), maxLines = 2)
            }
        }
        Spacer(Modifier.height(Space.xs))
        // 行 3：里程碑完成度 + 分支（只有「完成度」有进度语义才画条）
        val ratio = milestoneRatioOf(milestones)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(L10n.t("ms.page.title"), style = Type.label)
            Spacer(Modifier.width(Space.xs))
            Text("${ratio.done}/${ratio.done + ratio.open}", style = Type.body)
            ratio.ratio?.let { r ->
                Spacer(Modifier.width(Space.sm))
                Box(Modifier.width(64.dp).height(6.dp).clip(RoundedCornerShape(3.dp)).background(Palette.BarTrack)) {
                    Box(Modifier.fillMaxWidth(r).height(6.dp).clip(RoundedCornerShape(3.dp)).background(Palette.Deep))
                }
            }
            Spacer(Modifier.width(Space.sm))
            Text(L10n.t("cmp.dash.branchLine", p.currentBranch ?: "?"), style = Type.micro)
        }
        Spacer(Modifier.height(Space.xs))
        // 行 4：最近提交（分支明细的当前分支 headAgo/headShort；缺失如实）
        val current = p.branches.firstOrNull { it.isCurrent }
        val ago = current?.headAgo ?: p.lastCommitAgo
        if (!ago.isNullOrBlank()) {
            Text(L10n.t("cmp.dash.lastCommit", ago), style = Type.micro, maxLines = 1)
        }
        // 行 7：入口
        Spacer(Modifier.height(Space.xs))
        ActionText(L10n.t("cmp.dash.detailLink"), Palette.Accent, onClick = onOpen)
    }
}
