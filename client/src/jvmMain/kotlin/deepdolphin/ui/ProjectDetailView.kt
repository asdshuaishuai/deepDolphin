// ProjectDetailView.kt —— 项目详情页（C3）：脉搏/提交构成/分支/日志/文档四态 + git 操作（C8）+ 更新（C4）
// + 图谱两页入口（busy 生成→成功即开页）+ 提交单对位（类型前缀选择 + 引擎结果反馈）。
//
// 【口径】全部来自 status <n> / docs / journal 的引擎事实；读不出来的字段如实披露（-1 / 缺键）。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import deepdolphin.engine.Project
import deepdolphin.ui.Palette
import deepdolphin.ui.Space
import deepdolphin.ui.Type

@Composable
fun ProjectDetailView(model: AppModel) {
    val name by model.selectedProject.collectAsState()
    val detail by model.detail.collectAsState()
    val detailState by model.detailState.collectAsState()
    val docs by model.docs.collectAsState()
    val journal by model.journal.collectAsState()
    val lastResult by model.lastResult.collectAsState()
    val busyAction by model.busyAction.collectAsState()
    val refreshing by model.refreshing.collectAsState()

    val p = detail?.projects?.firstOrNull()

    LazyColumn(
        Modifier.fillMaxSize()
            .padding(horizontal = Space.xl, vertical = Space.lg),
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
                val graphRendering by model.graphRendering.collectAsState()
                ActionText(
                    if (name != null && graphRendering == "INDEX:$name") L10n.t("cmp.detail.graphRendering") else L10n.t("nav.graph"),
                    Palette.Accent,
                    enabled = name != null && graphRendering == null,
                ) { name?.let { model.renderGraphArtifact(it, GraphKind.INDEX) } }
                ActionText(
                    if (name != null && graphRendering == "ARCH:$name") L10n.t("cmp.detail.archRendering") else L10n.t("nav.arch"),
                    Palette.Deep,
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
                Text(L10n.t("cmp.err.detailRead"), style = Type.section.copy(color = Palette.Amber))
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
                        item(key = "pulse") { PulseCard(p) }
                        item(key = "committypes") { CommitTypesCard(p) }
                        item(key = "branch") { BranchCard(p) }
                        item(key = "git") { GitCard(model, p, busyAction) }
                        item(key = "journal") { JournalCard(journal?.entries.orEmpty(), journal?.unparsableLines, journal?.windowExhausted) }
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
private fun PulseCard(p: Project) {
    SectionCard(L10n.t("detail.pulse"), Modifier.fillMaxWidth()) {
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
            Text(L10n.t("cmp.detail.mergeHint", hint.description, hint.ahead, hint.behind), style = Type.body.copy(color = Palette.Accent))
        }
        p.warnings?.takeIf { it.isNotEmpty() }?.forEach { w ->
            Text("⚠ $w", style = Type.micro.copy(color = Palette.Amber))
        }
    }
}

/** 提交构成 12 色（对位 logic/CommitTypeComposition：12 类不取模）。 */
@Composable
private fun CommitTypesCard(p: Project) {
    SectionCard(L10n.t("cmp.detail.commitMixShort"), Modifier.fillMaxWidth()) {
        val types = p.commitTypes
        if (types.isEmpty()) {
            Text(L10n.t("cmp.detail.noTypeCounts"), style = Type.body.copy(color = Palette.TextSecondary))
        } else {
            val colors = Composition12
            Row(Modifier.fillMaxWidth().height(10.dp)) {
                val total = types.sumOf { it.count }.coerceAtLeast(1)
                types.forEachIndexed { i, t ->
                    Box(
                        Modifier.weight(t.count.toFloat() / total).fillMaxHeight()
                            .background(colors[i % colors.size])
                    )
                }
            }
            Spacer(Modifier.height(Space.sm))
            Row(horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                types.forEachIndexed { i, t ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(8.dp).background(colors[i % colors.size], RoundedCornerShape(2.dp)))
                        Spacer(Modifier.width(4.dp))
                        Text("${t.kind} ${t.count}", style = Type.micro)
                    }
                }
            }
            if (p.commitTypesTruncated == true) Text(L10n.t("cmp.detail.typesTruncated"), style = Type.micro)
        }
    }
}

@Composable
private fun BranchCard(p: Project) {
    SectionCard(L10n.t("dash.card.branch"), Modifier.fillMaxWidth()) {
        val branches = p.branches
        if (branches.isEmpty()) {
            Text(L10n.t("cmp.detail.branchesNA"), style = Type.body.copy(color = Palette.TextSecondary))
        } else {
            branches.forEach { b ->
                Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (b.isCurrent) Pill(L10n.t("detail.branch.current"), Palette.Accent)
                    Spacer(Modifier.width(Space.xs))
                    Text(b.name, style = Type.body.copy(fontWeight = FontWeight.Medium), modifier = Modifier.width(160.dp))
                    Text(b.statusLabel.ifBlank { b.status }, style = Type.micro, modifier = Modifier.width(90.dp))
                    Text(b.headAgo.ifBlank { b.headDate }, style = Type.micro, modifier = Modifier.width(110.dp))
                    b.headSubject.takeIf { it.isNotBlank() }?.let {
                        Text(it, style = Type.micro, maxLines = 1, modifier = Modifier.weight(1f))
                    }
                    if (b.pendingCommits > 0) {
                        Spacer(Modifier.width(Space.xs))
                        Pill("+${b.pendingCommits}", Palette.Accent)
                    }
                }
            }
            p.repoBranchCount?.let { if (branches.size < it) Text(L10n.t("cmp.detail.branchesTruncated", it), style = Type.micro) }
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
                Text(if (fb.ok) "✓" else "⚠", style = Type.label.copy(color = if (fb.ok) Palette.Green else Palette.Amber))
                Spacer(Modifier.width(Space.sm))
                Text(
                    "git ${fb.op} ${fb.project}：${fb.text.trim().take(240).ifEmpty { if (fb.ok) "（引擎无输出）" else "（引擎未给出原因）" }}",
                    style = Type.micro.copy(fontFamily = FontFamily.Monospace),
                    color = if (fb.ok) Palette.TextSecondary else Palette.Amber,
                    maxLines = 3,
                )
            }
        }
    }
}

@Composable
private fun JournalCard(entries: List<deepdolphin.engine.JournalEntry>, unparsable: Long?, windowExhausted: Boolean?) {
    SectionCard(L10n.t("cmp.detail.journalShort"), Modifier.fillMaxWidth()) {
        if (entries.isEmpty()) {
            Text(L10n.t("cmp.detail.journalEmpty"), style = Type.body.copy(color = Palette.TextSecondary))
        } else {
            entries.forEach { e ->
                Row(Modifier.fillMaxWidth().padding(vertical = 3.dp)) {
                    Text(e.hashShort, style = Type.micro, modifier = Modifier.width(70.dp))
                    Text(e.date, style = Type.micro, modifier = Modifier.width(90.dp))
                    Text(e.subject, style = Type.body, maxLines = 1, modifier = Modifier.weight(1f))
                }
            }
        }
        // 披露（缺键 = null 不当「没耗尽」）
        val notes = buildList {
            unparsable?.takeIf { it > 0 }?.let { add(L10n.t("cmp.detail.journalUnparsable", it)) }
            if (windowExhausted == true) add(L10n.t("cmp.detail.journalWindowEnd"))
        }
        notes.forEach {
            Spacer(Modifier.height(Space.xs))
            Text(it, style = Type.micro.copy(color = Palette.Amber))
        }
    }
}

/** 托管文档四态：存在可读 / 存在但读不出 / 不存在 / 未披露。 */
@Composable
private fun DocsCard(docs: List<deepdolphin.engine.DocContent>, unreadable: List<String>) {
    SectionCard(L10n.t("detail.managedDocs"), Modifier.fillMaxWidth()) {
        if (docs.isEmpty() && unreadable.isEmpty()) {
            Text(L10n.t("cmp.detail.docsNoContent"), style = Type.body.copy(color = Palette.TextSecondary))
        } else {
            docs.forEach { d ->
                Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                    Text(d.file, style = Type.body.copy(fontWeight = FontWeight.Medium), modifier = Modifier.width(140.dp))
                    Text(
                        L10n.t("cmp.detail.bytes", d.content.length),
                        style = Type.micro,
                        modifier = Modifier.width(90.dp),
                    )
                    Text(
                        d.content.lineSequence().firstOrNull()?.take(80) ?: L10n.t("cmp.detail.emptyFile"),
                        style = Type.micro, maxLines = 1, modifier = Modifier.weight(1f),
                    )
                }
            }
            if (unreadable.isNotEmpty()) {
                Text(L10n.t("cmp.detail.docsUnreadable", unreadable.joinToString("、")), style = Type.micro.copy(color = Palette.Amber))
            }
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
