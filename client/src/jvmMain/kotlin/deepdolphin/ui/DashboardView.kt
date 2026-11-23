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
            .clip(RoundedCornerShape(Space.tileRadius))
            .border(1.dp, if (hovered) Palette.StrokeHover else Palette.Stroke, RoundedCornerShape(Space.tileRadius))
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

/** KPI 磁贴：数字 + 标题 + 次级说明行。 */
@Composable
fun KpiTile(title: String, value: String, subtitle: String, modifier: Modifier = Modifier, tone: Color = Palette.TextPrimary) {
    GlassCard(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = Type.card)
            Spacer(Modifier.width(Space.sm))
        }
        Spacer(Modifier.height(Space.sm))
        Text(value, style = Type.display.copy(color = tone, fontSize = 34.sp))
        subtitle.takeIf { it.isNotBlank() }?.let {
            Spacer(Modifier.height(Space.xs))
            Text(it, style = Type.micro)
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
    var window by remember { mutableStateOf("all") } // all / 30d / 7d（C3 筛选，批 1 先做时间窗胶囊）

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Space.xl, vertical = Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.lg),
    ) {
        // ── 页头 ──
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("项目群脉搏", style = Type.title)
                Spacer(Modifier.height(4.dp))
                Text(
                    buildString {
                        append("${dash?.projects?.total ?: status?.projects?.size ?: 0} 个项目在册")
                        dash?.fetchedAt?.takeIf { it.isNotBlank() }?.let { append(" · 数据时间 $it") }
                        append(" · 引擎 moongit")
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

        // ── 筛选行（时间窗胶囊）──
        Row(horizontalArrangement = Arrangement.spacedBy(Space.sm), verticalAlignment = Alignment.CenterVertically) {
            listOf("all" to "全量", "30d" to "30 天", "7d" to "7 天").forEach { (k, label) ->
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
            Text("时间窗→项目卡+构成 · 类型→仅构成 · KPI 全量", style = Type.micro)
        }

        // ── 空态 CTA（真的没有项目才出现；加载中/读不出来不冒充空态）──
        if (registryEmpty(status)) EmptyRegistryCta(model)

        when (dashState) {
            is LoadState.Failed -> GlassCard(Modifier.fillMaxWidth()) {
                Text("仪表盘读不出来", style = Type.section.copy(color = Palette.Amber))
                Spacer(Modifier.height(Space.xs))
                Text((dashState as LoadState.Failed).reason, style = Type.body.copy(color = Palette.TextSecondary))
            }
            else -> {
                // ── 采集失败披露（诚实：原因来自引擎，不推断）──
                val failed = status?.projects.orEmpty().filter { !it.isReadable }
                if (failed.isNotEmpty()) GlassCard(Modifier.fillMaxWidth()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Pill("采集失败 ${failed.size}", Palette.Amber)
                        Spacer(Modifier.width(Space.sm))
                        Text("以下项目读取失败 —— 原因来自引擎，不是客户端推断", style = Type.card)
                    }
                    Spacer(Modifier.height(Space.sm))
                    failed.forEach { p ->
                        Row(Modifier.padding(vertical = 2.dp)) {
                            Pill(p.name, Palette.Red)
                            Spacer(Modifier.width(Space.sm))
                            Text(p.error ?: "原因未给出", style = Type.body.copy(color = Palette.TextSecondary))
                        }
                    }
                }

                // ── KPI 四磁贴 ──
                Row(horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                    val d = dash
                    KpiTile("项目总数", "${d?.projects?.total ?: 0}",
                        "含采集失败、不含已停用 · 采集成功 ${d?.projects?.readable ?: 0} · 失败 ${d?.projects?.failed ?: 0}",
                        Modifier.weight(1f))
                    KpiTile("待你动手", "${status?.summary?.dirtyProjects ?: 0}",
                        "有未提交改动的项目 · 未跟踪与 stash 不计入",
                        Modifier.weight(1f), tone = Palette.Amber)
                    KpiTile("活跃", "${d?.projects?.readable ?: 0}",
                        "最近 7 天有新提交（采集成功口径）",
                        Modifier.weight(1f), tone = Palette.Green)
                    KpiTile("停滞（逾期未动）", "${status?.summary?.staleProjects ?: 0}",
                        "8–30 天无提交 · >30 天未更新",
                        Modifier.weight(1f))
                }

                // ── 语言分布 ──
                SectionCard("语言分布（跟踪文件数）", Modifier.fillMaxWidth()) {
                    val langs = dash?.languages.orEmpty()
                    if (langs.isEmpty()) {
                        Text("暂无语言数据", style = Type.body.copy(color = Palette.TextSecondary))
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
                                "另有 ${it} 个项目语言读不出来" +
                                    (dash?.languagesFailedReasons?.takeIf { r -> r.isNotEmpty() }?.let { r -> "：${r.joinToString("；")}" } ?: ""),
                                style = Type.micro,
                            )
                        }
                        if (dash?.languagesTruncated == true) Text("语言列表被截断（只显示前几名）", style = Type.micro)
                    }
                }

                // ── 里程碑 ──
                SectionCard("里程碑（dashboard 口径）", Modifier.fillMaxWidth()) {
                    val ms = dash?.milestones
                    Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                        Pill("开放 ${ms?.counts?.open ?: 0}", Palette.Accent)
                        Pill("完成 ${ms?.counts?.done ?: 0}", Palette.Green)
                        Pill("放弃 ${ms?.counts?.dropped ?: 0}", Palette.TextSecondary)
                        Pill("无法核验 ${ms?.counts?.unverifiable ?: 0}", Palette.Amber)
                        Pill("引擎读到 ${ms?.counts?.engineRead ?: 0} 条", Palette.TextSecondary)
                    }
                    ms?.storeHealth?.takeIf { it.isNotBlank() && it != "ok" }?.let {
                        Spacer(Modifier.height(Space.xs))
                        Text("存储健康度：$it（降级披露）", style = Type.micro.copy(color = Palette.Amber))
                    }
                }

                // ── 活跃项目 ──
                SectionCard("近 7 天活跃", Modifier.fillMaxWidth()) {
                    val act = dash?.activeProjects.orEmpty()
                    if (act.isEmpty()) Text("近 7 天没有项目有提交", style = Type.body.copy(color = Palette.TextSecondary))
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
        Text("还没有项目在册", style = Type.section)
        Spacer(Modifier.height(Space.xs))
        Text(
            "注册表是空的（引擎读成功才算数）—— 扫描一个仓库根目录，或直接添加单个项目路径",
            style = Type.body.copy(color = Palette.TextSecondary),
        )
        Spacer(Modifier.height(Space.sm))
        // ── 扫描行 ──
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            OutlinedTextField(
                value = scanRoot,
                onValueChange = { scanRoot = it },
                placeholder = { Text("扫描根目录（如 ~/code）", style = Type.micro) },
                singleLine = true,
                textStyle = Type.body,
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
                value = scanDepth,
                onValueChange = { scanDepth = it },
                placeholder = { Text("深度", style = Type.micro) },
                singleLine = true,
                textStyle = Type.body,
                modifier = Modifier.width(72.dp),
            )
            Button(
                onClick = { model.scanProjects(scanRoot.trim(), scanDepth.trim().toIntOrNull() ?: 2) },
                enabled = !busy && scanRoot.isNotBlank(),
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
            ) { Text("扫描") }
        }
        Spacer(Modifier.height(Space.sm))
        // ── 添加行 ──
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            OutlinedTextField(
                value = addPath,
                onValueChange = { addPath = it },
                placeholder = { Text("添加项目路径（git 仓库目录）", style = Type.micro) },
                singleLine = true,
                textStyle = Type.body,
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
                value = addName,
                onValueChange = { addName = it },
                placeholder = { Text("名称（可空）", style = Type.micro) },
                singleLine = true,
                textStyle = Type.body,
                modifier = Modifier.width(120.dp),
            )
            Button(
                onClick = { model.addProjectPath(addPath.trim(), addName.trim().takeIf { it.isNotBlank() }) },
                enabled = !busy && addPath.isNotBlank(),
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.Accent, contentColor = Color.White),
            ) { Text("添加") }
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
