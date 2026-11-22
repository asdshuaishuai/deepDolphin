// DashboardView.kt —— 仪表盘页（C3）：KPI 磁贴 / 语言分布 / 里程碑 / 活跃项目 + 筛选行。
//
// 判定与披露全部来自 logic 层产物（DashboardData 字段），不内联口径；
// 失败披露诚实（采集失败/语言读不出来的原因列出来，不静默）。

package deepdolphin.ui

import androidx.compose.foundation.background
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import deepdolphin.engine.*
import deepdolphin.ui.Palette
import deepdolphin.ui.Space
import deepdolphin.ui.Type

@Composable
fun GlassCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .clip(RoundedCornerShape(Space.tileRadius))
            .background(Palette.Card)
            .padding(Space.lg),
        content = content,
    )
}

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
                GlassCard(Modifier.fillMaxWidth()) {
                    Text("语言分布（跟踪文件数）", style = Type.section)
                    Spacer(Modifier.height(Space.sm))
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
                                        .background(Color(0x1AFFFFFF))
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
                GlassCard(Modifier.fillMaxWidth()) {
                    Text("里程碑（dashboard 口径）", style = Type.section)
                    Spacer(Modifier.height(Space.sm))
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
                GlassCard(Modifier.fillMaxWidth()) {
                    Text("近 7 天活跃", style = Type.section)
                    Spacer(Modifier.height(Space.sm))
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

/** 胶囊 pill（语义色底 + 深色文字 = WCAG 对比度纪律）。 */
@Composable
fun Pill(text: String, color: Color) {
    Text(
        text,
        style = Type.micro.copy(fontWeight = FontWeight.SemiBold),
        color = Color(0xFF0A0F1A),
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(color.copy(alpha = 0.9f))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}
