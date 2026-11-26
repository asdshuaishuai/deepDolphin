// ProjectDetailView.kt —— 项目详情页（C3）：脉搏/提交构成/分支/日志/文档四态 + git 操作（C8）+ 更新（C4）
// + 图谱两页入口（busy 生成→成功即开页）+ 提交单对位（类型前缀选择 + 引擎结果反馈）。
//
// 【口径】全部来自 status <n> / docs 的引擎事实（进度日志读 status 内嵌的 project.journal）；读不出来的字段如实披露（-1 / 缺键）。

package canopy.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import canopy.engine.Project
import canopy.ui.Palette
import canopy.ui.Space
import canopy.ui.Type
import kotlin.math.roundToInt
import androidx.compose.foundation.layout.PaddingValues

@Composable
fun ProjectDetailView(model: AppModel) {
    val name by model.selectedProject.collectAsState()
    val detail by model.detail.collectAsState()
    val detailState by model.detailState.collectAsState()
    val docs by model.docs.collectAsState()
    val lastResult by model.lastResult.collectAsState()
    val busyAction by model.busyAction.collectAsState()
    val milestones by model.milestones.collectAsState()
    val refreshing by model.refreshing.collectAsState()

    val p = detail?.projects?.firstOrNull()

    ScrollLazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = Space.xl, vertical = Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.lg),
    ) {
        // ── 页头 + 写动作条（唯一 chrome 落点：PageHeader 纪律）──
        item(key = "header") {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(name ?: L10n.t("nav.projectDetail"), style = Type.title)
                p?.headline?.let {
                    Spacer(Modifier.height(4.dp))
                    Text(it, style = Type.label)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                ActionText(L10n.t("workbar.shallow"), Palette.Accent, enabled = !busyAction && refreshing.not()) {
                    name?.let { model.updateProject(it, deep = false) }
                }
                ActionText(L10n.t("workbar.deep"), Palette.Accent, enabled = !busyAction) {
                    name?.let { model.updateProject(it, deep = true) }
                }
                // 一键项目说明（mac ProjectBriefButton 对位，L10n "detail.projectBrief"）：AI 融进操作——
                // 动作条就地带固定问题预填打开 agent sheet（作用域=本详情项目），不做独立 AI 入口
                ActionText(L10n.t("detail.brief"), Palette.Ai, enabled = name != null) {
                    name?.let { model.openAgent(briefTask(it), title = L10n.t("detail.brief")) }
                }
                // 图谱两页入口（mac DetailViews.swift:229-307 按钮形态对位；用户定稿：两图只能从
                // 具体仓库面板触发）。⚠️ 与 mac 探测逻辑的差异（如实标注）：mac 先探产物
                // （render check：已生成→「打开」按钮 / 未生成→「生成」按钮走 agent 播种）；
                // 本机引擎没有 render check 子命令——按 mac 降级先例（探测失败=未生成，
                // GraphChrome.swift:185-187）不做两态按钮：点按统一 busy 态跑 render，
                // 产物已在时引擎复用判定毫秒级返回（回执说「复用」）即秒开，
                // 不在时这一发就是首次生成（分钟级）。详见 AppModel.renderGraphArtifact。
                // 两页跟着仓库走（用户定稿 2026-11-25：不弹窗、专门一页）——入口就在这里，
                // 做成带字形的小按钮，和旁边的文字动作区分开
                val graphRendering by model.graphRendering.collectAsState()
                GraphEntryChip(
                    label = if (name != null && graphRendering == "INDEX:$name") L10n.t("cmp.detail.graphRendering") else L10n.t("nav.graph"),
                    icon = GraphKind.INDEX.tileIcon,
                    tint = Palette.AccentText,
                    enabled = name != null && graphRendering == null,
                ) { name?.let { model.renderGraphArtifact(it, GraphKind.INDEX) } }
                GraphEntryChip(
                    label = if (name != null && graphRendering == "ARCH:$name") L10n.t("cmp.detail.archRendering") else L10n.t("nav.arch"),
                    icon = GraphKind.ARCH.tileIcon,
                    tint = Palette.DeepText,
                    enabled = name != null && graphRendering == null,
                ) { name?.let { model.renderGraphArtifact(it, GraphKind.ARCH) } }
                ActionText(L10n.t("toolbar.refresh"), Palette.TextSecondary, enabled = !refreshing) {
                    name?.let { model.loadDetail(it) }
                }
            }
        }
        }

        // 写操作结果一行（actionStripOf 的 PageHeader 落点）；
        // 深浅更新的结果就地给「AI 解读」——AI 融进操作，不做独立入口（mac UpdateActionMenu AI 变体对位）
        lastResult?.let {
            item(key = "lastResult") {
            GlassCard(Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(it, style = Type.body, maxLines = 3, modifier = Modifier.weight(1f))
                    if (it.startsWith(L10n.t("workbar.shallow")) || it.startsWith(L10n.t("workbar.deep"))) {
                        Spacer(Modifier.width(Space.sm))
                        ActionText(L10n.t("cmp.detail.aiBrief"), Palette.Ai, enabled = true) {
                            model.openAgent("解读这次更新的结果「$it」：发生了什么、有什么值得注意的？只根据引擎返回的事实回答。")
                        }
                    }
                }
            }
            }
        }

        when (val st = detailState) {
            is LoadState.Failed -> item(key = "failed") { GlassCard(Modifier.fillMaxWidth()) {
                Text(L10n.t("cmp.err.detailRead"), style = Type.section.copy(color = Palette.AmberText))
                Text(st.reason, style = Type.body.copy(color = Palette.TextSecondary))
            } }
            is LoadState.Loading -> item(key = "loading") { GlassCard(Modifier.fillMaxWidth()) {
                Text(L10n.t("bar.loading"), style = Type.body.copy(color = Palette.TextSecondary))
            } }
            else -> {
                if (p == null) {
                    item(key = "nodata") { GlassCard(Modifier.fillMaxWidth()) { Text(L10n.t("cmp.detail.noData"), style = Type.body) } }
                } else {
                    if (!p.isReadable) item(key = "unreadable") { UnreadableCard(p) } else {
                        // 脉搏 ‖ 提交构成 两列并排（mac DetailViews.swift:84-87 LazyVGrid 对位）
                        item(key = "pulseRow") {
                            Row(horizontalArrangement = Arrangement.spacedBy(Space.lg)) {
                                PulseCard(p, Modifier.weight(1f))
                                CommitTypesCard(p, Modifier.weight(1f))
                            }
                        }
                        item(key = "branch") { BranchCard(p) }
                        // 里程碑卡（mac milestoneCard：本项目的里程碑 + 达成率）
                        milestones?.let { all -> if (all.milestones.any { it.projectName == p.name }) item(key = "milestones") {
                            DetailMilestoneCard(model, all.milestones.filter { it.projectName == p.name })
                        } }
                        item(key = "git") { GitCard(model, p, busyAction) }
                        // 进度日志：只在有条目时出卡（mac DetailViews.swift:109 同款）
                        if (p.journal.isNotEmpty()) item(key = "journal") { JournalCard(p) }
                        item(key = "docs") { DocsCard(docs?.docs.orEmpty(), docs?.unreadable.orEmpty()) }
                    }
                }
            }
        }
    }
    // 提交单（mac .sheet(commitSheetProject) 对位：页头「提交」按钮是唯一入口）
    val commitSheet by model.commitSheet.collectAsState()
    commitSheet?.let { CommitSheet(model, it) }
}

@Composable
private fun UnreadableCard(p: Project) {
    GlassCard(Modifier.fillMaxWidth()) {
        Pill(L10n.t("ms.filter.unreadable"), Palette.Red)
        Spacer(Modifier.height(Space.sm))
        Text(p.error ?: L10n.t("cmp.err.noReason"), style = Type.body.copy(color = Palette.TextSecondary))
        Text(L10n.t("cmp.detail.path", p.path), style = Type.micro)
    }
}

/** 工程脉搏：当前/默认分支、脏度、提交数、进度时间戳。 */
@Composable
private fun PulseCard(p: Project, modifier: Modifier = Modifier) {
    SectionCard(L10n.t("detail.pulse"), modifier) {
        // 分支一行（同分支合并披露）
        val branchLine = if (p.currentBranch == p.defaultBranch) {
            L10n.t("cmp.detail.currentIsDefault", p.currentBranch ?: "?")
        } else {
            L10n.t("cmp.detail.branchLine", p.currentBranch ?: "?", p.defaultBranch ?: "?")
        }
        Text(branchLine, style = Type.body)
        Spacer(Modifier.height(Space.sm))
        val dirty = p.dirty
        val dirtyText = when {
            dirty == null -> L10n.t("cmp.detail.dirtyNA")
            dirty.ok && dirty.clean -> L10n.t("cmp.detail.dirtyClean")
            dirty.ok -> L10n.t("cmp.detail.dirtyCounts", dirty.total, dirty.staged, dirty.modified, dirty.untracked)
            else -> L10n.t("cmp.detail.dirtyFailed", dirty.err ?: L10n.t("cmp.err.noReasonAlt"))
        }
        Text(dirtyText, style = Type.body)
        Spacer(Modifier.height(2.dp))
        Text(
            buildString {
                append(L10n.t("cmp.detail.commitCount", if ((p.commitCount ?: -1) < 0) L10n.t("cmp.detail.commitCountNA") else p.commitCount.toString()))
                p.lastCommitAgo?.let { append(L10n.t("cmp.detail.lastCommitAt", it)) }
            },
            style = Type.body,
        )
        // 合并建议（缺键 = 就在默认分支，不是「没有」）
        p.mergeHint?.let { hint ->
            Spacer(Modifier.height(Space.sm))
            Text(L10n.t("cmp.detail.mergeHint", hint.description, hint.ahead, hint.behind), style = Type.body.copy(color = Palette.AccentText))
        }
        p.warnings?.takeIf { it.isNotEmpty() }?.forEach { w ->
            Text("⚠ $w", style = Type.micro.copy(color = Palette.AmberText))
        }
    }
}

/** 提交构成 12 色（对位 logic/CommitTypeComposition：12 类不取模）。 */
@Composable
private fun CommitTypesCard(p: Project, modifier: Modifier = Modifier) {
    SectionCard(L10n.t("detail.composition"), modifier) {
        val types = p.commitTypes
        if (types.isEmpty()) {
            Text(L10n.t("detail.commit.none"), style = Type.body.copy(color = Palette.TextTertiary))
        } else {
            // 堆叠条 + 图例（不取模；色板画不完的条数由切片说出来）
            CommitCompositionBlock(types, sampleTruncated = false)
            if (p.commitTypesTruncated == true) Text(L10n.t("dash.card.sample"), style = Type.micro, color = Palette.AmberText)
        }
    }
}

@Composable
private fun BranchCard(p: Project) {
    val branches = p.branches
    SectionCard(L10n.t("detail.branchProgress", branchScopeLine(branches.size, p.repoBranchCount)), Modifier.fillMaxWidth()) {
        if (branches.isEmpty()) {
            // 「没有分支记录」与「这个项目没有分支」是两回事：空态给的是下一步（mac 同款）
            Text(L10n.t("detail.branch.empty"), style = Type.body.copy(color = Palette.TextSecondary))
            Text(L10n.t("detail.branch.empty.hint"), style = Type.micro)
        } else {
            branches.forEachIndexed { idx, b ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                    Box(Modifier.size(8.dp).background(branchStatusTint(b.status), androidx.compose.foundation.shape.CircleShape))
                    Text(b.name, style = Type.body.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace), maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                    if (b.isCurrent) Spacer(Modifier.width(Space.xs)); if (b.isCurrent) Pill(L10n.t("detail.branch.current"), Palette.Accent)
                    if (b.isDefault) Spacer(Modifier.width(Space.xs)); if (b.isDefault) Pill(L10n.t("detail.branch.default"), Palette.TextSecondary)
                    Spacer(Modifier.weight(1f))
                    Text(b.statusLabel.ifBlank { b.status }, style = Type.label, color = Palette.TextSecondary)
                    // 非「规则」提供方的条目要标出来（AI 摘要与规则摘要的可信度不同）
                    if (b.provider.isNotBlank() && b.provider != "rules") {
                        Spacer(Modifier.width(Space.xs))
                        Pill(b.provider, Palette.Ai)
                    }
                    if (b.pendingCommits > 0) {
                        Spacer(Modifier.width(Space.sm))
                        Text(L10n.t("detail.pending.invalid"), style = Type.label, color = Palette.AmberText)
                    } else if (b.baselineReset) {
                        Spacer(Modifier.width(Space.sm))
                        Text(L10n.t("detail.baseline.reset"), style = Type.label, color = Palette.TextTertiary)
                    }
                }
                Column(Modifier.padding(start = 18.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(b.summary, style = Type.label, color = Palette.TextSecondary, maxLines = 2)
                    Text("${b.headShort} · ${b.headAgo}", style = Type.micro)
                    b.highlights.forEach { h -> Text("· $h", style = Type.micro, maxLines = 1) }
                    Row(Modifier.fillMaxWidth()) {
                        // 领先默认分支数——基线重建过的分支，领先数已不可比，不报
                        if (b.aheadOfDefault > 0 && !b.baselineReset) {
                            Text(L10n.t("detail.branch.ahead", b.aheadOfDefault), style = Type.micro, color = Palette.AccentText)
                        }
                        Spacer(Modifier.weight(1f))
                        // 「多久没更新」自己处理 -1（读不出来）
                        Text(branchStaleText(b.staleDays), style = Type.micro, color = branchStatusTint(b.status))
                    }
                    b.nextSteps.forEach { n ->
                        Row {
                            IconBox(FluentIcon.ArrowRight, size = 12.dp, tint = Palette.AccentText)
                            Spacer(Modifier.width(6.dp))
                            Text(n, style = Type.micro, color = Palette.AccentText, maxLines = 2, modifier = Modifier.weight(1f))
                        }
                    }
                }
                if (idx != branches.lastIndex) {
                    androidx.compose.material3.HorizontalDivider(
                        color = Palette.Stroke, modifier = Modifier.padding(vertical = Space.sm),
                    )
                }
            }
        }
    }
}

/** 分支档位 → 颜色（mac StatusDot：active=绿 / idle=黄 / stale=橙 / merged=紫 / 其余中性灰）。 */
private fun branchStatusTint(status: String): Color = when (status) {
    "active" -> Palette.GreenText
    "idle" -> Palette.YellowText
    "stale" -> Palette.AmberText
    "merged" -> Palette.DeepText
    else -> Palette.TextTertiary
}

/** 详情页里程碑卡（mac milestoneCard 对位）：达成率 + 进度 + 本项目的里程碑行。 */
@Composable
private fun DetailMilestoneCard(model: AppModel, mine: List<canopy.engine.Milestone>) {
    SectionCard(L10n.t("detail.ms.count", mine.size), Modifier.fillMaxWidth()) {
        if (mine.isEmpty()) {
            Text(L10n.t("detail.ms.none"), style = Type.body.copy(color = Palette.TextSecondary))
            Text(L10n.t("detail.ms.none.hint"), style = Type.micro)
        } else {
            val t = milestoneRatioOf(mine)
            val decided = t.done + t.open
            if (decided > 0) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                    Text(L10n.t("detail.ms.rate"), style = Type.label, color = Palette.TextSecondary)
                    val pct = (t.done.toDouble() * 100 / decided).roundToInt()
                    Text("$pct%", style = Type.section)
                    Text("${t.done}/$decided", style = Type.label, color = Palette.TextSecondary)
                    if (t.unknown > 0) Text(L10n.t("detail.ms.unknownDenom", t.unknown), style = Type.label, color = Palette.AmberText)
                }
                Spacer(Modifier.height(Space.sm))
                Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(Radius.chip)).background(Palette.BarTrack)) {
                    Box(Modifier.fillMaxWidth((t.done.toFloat() / decided).coerceIn(0f, 1f)).height(6.dp).background(Palette.Deep))
                }
            }
            androidx.compose.material3.HorizontalDivider(color = Palette.Stroke, modifier = Modifier.padding(vertical = Space.sm))
            Column(verticalArrangement = Arrangement.spacedBy(Space.sm)) {
                mine.forEach { m -> GuardedMilestoneRow(model, m) }
            }
        }
    }
}

/**
 * git 白名单六操作（C8）+ 提交入口（mac DetailViews.swift:162-193 gitOpButtons 对位：
 * **提交是唯一入口、点开提交单**——CommitSheetView 承载勾选/信息/类型；这张卡只留
 * 其余五操作 + 改动构成披露 + 结果横幅）。
 *
 * 【提交口径，如实】本机引擎 `git commit` 是 add -A 全量（真机实测 --paths RC=2 拒），
 * 子集提交没有引擎语义——勾选集在提交单里作为核对清单、全选才能提交（见 CommitSheet.kt
 * 文件头）。改动构成行只报引擎 status 契约 dirty 里的四类计数（已暂存/修改/未跟踪/冲突）；
 * mac 类型集的 added/deleted/renamed 是 per-file XY 归一词，本机引擎没有 git status
 * 子命令、dirty.files 不带 kind——如实不造。
 */
@Composable
private fun GitCard(model: AppModel, p: Project, busy: Boolean) {
    val feedback by model.gitFeedback.collectAsState()

    SectionCard(L10n.t("detail.gitOps"), Modifier.fillMaxWidth()) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            // 提交（mac 用户定稿：放推送旁边的本地提交入口——点开选文件提交单）
            ActionText(L10n.t("gitop.commit"), Palette.Accent, enabled = !busy && p.isGit) { model.openCommitSheet(p.name) }
            listOf("pull", "push", L10n.t("dash.stash"), "unstash", "fetch").forEach { op ->
                ActionText(op, Palette.TextSecondary, enabled = !busy) { model.gitOp(op, p.name) }
            }
        }
        Spacer(Modifier.height(Space.sm))
        // ── 改动构成披露（引擎 dirty 四类计数；干净/读不出/缺键三态分开说）──
        val dirty = p.dirty
        Text(
            when {
                dirty == null -> L10n.t("cmp.detail.dirtyCardNA")
                !dirty.ok -> L10n.t("cmp.detail.dirtyCardFailed", dirty.err ?: L10n.t("cmp.err.noReasonAlt"))
                dirty.clean -> L10n.t("cmp.detail.dirtyCardClean")
                else -> L10n.t("cmp.detail.dirtyCardWill", dirty.staged, dirty.modified, dirty.untracked, dirty.conflicts)
            },
            style = Type.body.copy(color = Palette.TextSecondary),
        )
        // ── 结果反馈（mac「失败不弹走」对位；六操作的结果都落在这里——提交单自己
        //    也有一份就地反馈，这里是页面级横幅）──
        feedback?.let { fb ->
            Spacer(Modifier.height(Space.xs))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (fb.ok) "✓" else "⚠", style = Type.label.copy(color = if (fb.ok) Palette.GreenText else Palette.AmberText))
                Spacer(Modifier.width(Space.sm))
                Text(
                    "git ${fb.op} ${fb.project}：${fb.text.trim().take(240).ifEmpty { if (fb.ok) "（引擎无输出）" else "（引擎未给出原因）" }}",
                    style = Type.micro.copy(fontFamily = FontFamily.Monospace),
                    color = if (fb.ok) Palette.TextSecondary else Palette.AmberText,
                    maxLines = 3,
                )
            }
        }
    }
}

/** 进度日志（mac journalCard 对位）：数据来自 status 内嵌的 project.journal。 */
@Composable
private fun JournalCard(p: Project) {
    SectionCard(
        L10n.t(
            "detail.journalCard",
            entryCountLine(p.progress.entryCount, p.progress.entriesKept, p.progress.entryCountTruncated),
        ),
        Modifier.fillMaxWidth(),
    ) {
        p.journal.forEachIndexed { idx, e ->
            // 口径与截断必须由纯函数判定：同一个 +N 在浅/深两条路径上含义不同
            val badge = commitCountBadge(e.commitCount, e.commitCountScope, e.commitCountTruncated)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                Text(
                    journalModeLabel(e.mode), style = Type.micro, color = Palette.TextSecondary,
                    modifier = Modifier.clip(RoundedCornerShape(Radius.control)).background(Palette.Stroke)
                        .padding(horizontal = 5.dp, vertical = 1.dp),
                )
                Spacer(Modifier.width(Space.sm + 2.dp))
                Text(
                    e.branch, style = Type.label.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace),
                    color = Palette.TextSecondary,
                )
                Spacer(Modifier.width(Space.sm))
                Text(e.summary, style = Type.label, maxLines = 1, modifier = Modifier.weight(1f))
                // 绿色只留给「本轮新增」：累计量用绿色等于说「这次变好了这么多」
                badge.text?.let {
                    Spacer(Modifier.width(Space.sm))
                    Text(
                        it, style = Type.micro.copy(fontWeight = FontWeight.SemiBold),
                        color = if (badge.scope.isIncremental) Palette.GreenText else Palette.TextSecondary,
                    )
                }
            }
            badge.note?.let {
                Spacer(Modifier.height(2.dp))
                Text(it, style = Type.micro, color = Palette.AmberText)
            }
            if (idx != p.journal.lastIndex) {
                androidx.compose.material3.HorizontalDivider(
                    color = Palette.Stroke, modifier = Modifier.padding(vertical = Space.xs),
                )
            }
        }
        // 窗口与全量必须能被区分开；journal.md 里有解析不了的行时也要说
        if (p.journalTruncated == true) {
            Text(L10n.t("detail.journal.truncated", p.journal.size, p.journalLimit), style = Type.micro, color = Palette.AmberText)
        }
        (p.journalUnparsableLines ?: 0).takeIf { it > 0 }?.let {
            Text(L10n.t("detail.journal.unparsable", it), style = Type.micro, color = Palette.AmberText)
        }
    }
}

/** 托管文档四态：存在可读 / 存在但读不出 / 不存在 / 未披露。 */
@Composable
private fun DocsCard(docs: List<canopy.engine.DocContent>, unreadable: List<String>) {
    if (docs.isEmpty()) {
        SectionCard(L10n.t("detail.managedDocs"), Modifier.fillMaxWidth()) {
            Text(
                if (unreadable.isNotEmpty()) L10n.t("cmp.detail.docsUnreadable", unreadable.joinToString("、"))
                else L10n.t("cmp.detail.docsNoContent"),
                style = Type.body.copy(color = if (unreadable.isNotEmpty()) Palette.AmberText else Palette.TextSecondary),
            )
        }
        return
    }
    // 每份托管文档一张卡、渲染正文（mac DetailViews.swift:114-120 对位：原来只列文件名和首行，
    // 用户在客户端里根本读不到文档）。正文走原生 Markdown，不起 WebView。
    docs.forEach { d ->
        SectionCard(d.file, Modifier.fillMaxWidth()) {
            if (d.content.isBlank()) {
                Text(L10n.t("cmp.detail.emptyFile"), style = Type.label, color = Palette.TextTertiary)
            } else {
                MarkdownText(d.content, Modifier.fillMaxWidth())
            }
        }
    }
    if (unreadable.isNotEmpty()) {
        GlassCard(Modifier.fillMaxWidth()) {
            Text(L10n.t("cmp.detail.docsUnreadable", unreadable.joinToString("、")), style = Type.label, color = Palette.AmberText)
        }
    }
}

// ── 提交单纯函数（判据见 CommitFormTest）──

/**
 * 提交类型词表（引擎 kernel/git.cj:888 COMMIT_TYPE_ORDER 去 other；other 是引擎对
 * **无前缀**提交的归类，客户端用「无类型」表达同一件事，不发明第 13 类）。
 * 别名表对位引擎 commitTypeOf 的归并（feature/add→feat 等，git.cj:922-936）——
 * 只用于「信息已自带前缀就不重复加」的判定，不用于改写用户的信息。
 */
val COMMIT_TYPE_WORDS = listOf(
    "feat", "fix", "perf", "refactor", "docs", "test", "build", "ci", "style", "chore", "revert",
)

private val COMMIT_TYPE_ALIASES = listOf("feature", "add", "bugfix", "hotfix", "bug", "performance", "tests", "tst")

/** 信息开头是否已经是类型前缀（"feat: x" / "feat(api): x" / 别名同认）。 */
private fun typedAlready(msg: String): Boolean {
    val lower = msg.lowercase()
    return (COMMIT_TYPE_WORDS + COMMIT_TYPE_ALIASES).any {
        lower == it || lower.startsWith("$it:") || lower.startsWith("$it(")
    }
}

/**
 * 提交信息拼装：类型非空 → "<type>: <信息>"；信息已自带类型前缀 → 原样（不双前缀）；
 * 信息空白 → null（引擎要求 --message 非空，git.cj:1846「需要提交信息」；按钮可用性挂在这里）。
 */
fun commitMessage(type: String?, raw: String): String? {
    val msg = raw.trim()
    if (msg.isEmpty()) return null
    val t = type?.trim().orEmpty()
    if (t.isEmpty() || typedAlready(msg)) return msg
    return "$t: $msg"
}
