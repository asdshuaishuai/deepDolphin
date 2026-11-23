// ProjectDetailView.kt —— 项目详情页（C3）：脉搏/提交构成/分支/日志/文档四态 + git 操作（C8）+ 更新（C4）。
//
// 【口径】全部来自 status <n> / docs / journal 的引擎事实；读不出来的字段如实披露（-1 / 缺键）。

package deepdolphin.ui

import androidx.compose.foundation.background
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

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState())
            .padding(horizontal = Space.xl, vertical = Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.lg),
    ) {
        // ── 页头 + 写动作条（唯一 chrome 落点：PageHeader 纪律）──
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(name ?: "项目详情", style = Type.title)
                p?.headline?.let {
                    Spacer(Modifier.height(4.dp))
                    Text(it, style = Type.label)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                ActionText("浅更新", Palette.Accent, enabled = !busyAction && refreshing.not()) {
                    name?.let { model.updateProject(it, deep = false) }
                }
                ActionText("深更新", Palette.Accent, enabled = !busyAction) {
                    name?.let { model.updateProject(it, deep = true) }
                }
                ActionText("刷新", Palette.TextSecondary, enabled = !refreshing) {
                    name?.let { model.loadDetail(it) }
                }
                // 没有 AI 按钮：AI 融进操作——更新完成后结果行就地给「AI 解读」
            }
        }

        // 写操作结果一行（actionStripOf 的 PageHeader 落点）；
        // 深浅更新的结果就地给「AI 解读」——AI 融进操作，不做独立入口（mac UpdateActionMenu AI 变体对位）
        lastResult?.let {
            GlassCard(Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(it, style = Type.body, maxLines = 3, modifier = Modifier.weight(1f))
                    if (it.startsWith("浅更新") || it.startsWith("深更新")) {
                        Spacer(Modifier.width(Space.sm))
                        ActionText("AI 解读", Palette.Ai, enabled = true) {
                            model.openAgent("解读这次更新的结果「$it」：发生了什么、有什么值得注意的？只根据引擎返回的事实回答。")
                        }
                    }
                }
            }
        }

        when (val st = detailState) {
            is LoadState.Failed -> GlassCard(Modifier.fillMaxWidth()) {
                Text("详情读不出来", style = Type.section.copy(color = Palette.Amber))
                Text(st.reason, style = Type.body.copy(color = Palette.TextSecondary))
            }
            is LoadState.Loading -> GlassCard(Modifier.fillMaxWidth()) {
                Text("读取中…", style = Type.body.copy(color = Palette.TextSecondary))
            }
            else -> {
                if (p == null) {
                    GlassCard(Modifier.fillMaxWidth()) { Text("项目没有数据", style = Type.body) }
                } else {
                    if (!p.isReadable) UnreadableCard(p) else {
                        PulseCard(p)
                        CommitTypesCard(p)
                        BranchCard(p)
                        GitCard(model, p, busyAction)
                        JournalCard(journal?.entries.orEmpty(), journal?.unparsableLines, journal?.windowExhausted)
                        DocsCard(docs?.docs.orEmpty(), docs?.unreadable.orEmpty())
                    }
                }
            }
        }
    }
}

@Composable
private fun UnreadableCard(p: Project) {
    GlassCard(Modifier.fillMaxWidth()) {
        Pill("读不出来", Palette.Red)
        Spacer(Modifier.height(Space.sm))
        Text(p.error ?: "引擎未给出原因", style = Type.body.copy(color = Palette.TextSecondary))
        Text("路径：${p.path}", style = Type.micro)
    }
}

/** 工程脉搏：当前/默认分支、脏度、提交数、进度时间戳。 */
@Composable
private fun PulseCard(p: Project) {
    SectionCard("工程脉搏", Modifier.fillMaxWidth()) {
        // 分支一行（同分支合并披露）
        val branchLine = if (p.currentBranch == p.defaultBranch) {
            "当前分支 ${p.currentBranch ?: "?"}（即默认分支）"
        } else {
            "当前分支 ${p.currentBranch ?: "?"} · 默认分支 ${p.defaultBranch ?: "?"}"
        }
        Text(branchLine, style = Type.body)
        Spacer(Modifier.height(Space.sm))
        val dirty = p.dirty
        val dirtyText = when {
            dirty == null -> "脏度读不出来"
            dirty.ok && dirty.clean -> "工作区干净"
            dirty.ok -> "未提交 ${dirty.total}（暂存 ${dirty.staged} · 修改 ${dirty.modified} · 未跟踪 ${dirty.untracked}）"
            else -> "脏度读取失败：${dirty.err ?: "未给出原因"}"
        }
        Text(dirtyText, style = Type.body)
        Spacer(Modifier.height(2.dp))
        Text(
            buildString {
                append("提交数 ${if ((p.commitCount ?: -1) < 0) "读不出来" else p.commitCount}")
                p.lastCommitAgo?.let { append(" · 最近提交 $it") }
            },
            style = Type.body,
        )
        // 合并建议（缺键 = 就在默认分支，不是「没有」）
        p.mergeHint?.let { hint ->
            Spacer(Modifier.height(Space.sm))
            Text("合并建议：${hint.description}（领先 ${hint.ahead} / 落后 ${hint.behind}）", style = Type.body.copy(color = Palette.Accent))
        }
        p.warnings?.takeIf { it.isNotEmpty() }?.forEach { w ->
            Text("⚠ $w", style = Type.micro.copy(color = Palette.Amber))
        }
    }
}

/** 提交构成 12 色（对位 logic/CommitTypeComposition：12 类不取模）。 */
@Composable
private fun CommitTypesCard(p: Project) {
    SectionCard("提交构成", Modifier.fillMaxWidth()) {
        val types = p.commitTypes
        if (types.isEmpty()) {
            Text("没有可用的类型计数（样本内没有提交或引擎读不出来）", style = Type.body.copy(color = Palette.TextSecondary))
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
            if (p.commitTypesTruncated == true) Text("类型列表被截断", style = Type.micro)
        }
    }
}

@Composable
private fun BranchCard(p: Project) {
    SectionCard("分支", Modifier.fillMaxWidth()) {
        val branches = p.branches
        if (branches.isEmpty()) {
            Text("分支数读不出来 · 引擎没返回分支明细", style = Type.body.copy(color = Palette.TextSecondary))
        } else {
            branches.forEach { b ->
                Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (b.isCurrent) Pill("当前", Palette.Accent)
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
            p.repoBranchCount?.let { if (branches.size < it) Text("分支明细被截断：仓库共 $it 条", style = Type.micro) }
        }
    }
}

/** git 白名单六操作（C8）+ 提交信息输入。 */
@Composable
private fun GitCard(model: AppModel, p: Project, busy: Boolean) {
    var message by remember { mutableStateOf("") }
    SectionCard("git 操作", Modifier.fillMaxWidth()) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            listOf("pull", "push", "stash", "unstash", "fetch").forEach { op ->
                ActionText(op, Palette.TextSecondary, enabled = !busy) { model.gitOp(op, p.name) }
            }
        }
        Spacer(Modifier.height(Space.sm))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            OutlinedTextField(
                value = message,
                onValueChange = { message = it },
                placeholder = { Text("提交信息（提交全部改动）", style = Type.micro) },
                singleLine = true,
                modifier = Modifier.weight(1f),
                textStyle = Type.body,
            )
            ActionText("提交", Palette.Accent, enabled = !busy && message.isNotBlank()) {
                model.gitOp("commit", p.name, message)
                message = ""
            }
        }
    }
}

@Composable
private fun JournalCard(entries: List<deepdolphin.engine.JournalEntry>, unparsable: Long?, windowExhausted: Boolean?) {
    SectionCard("提交日志", Modifier.fillMaxWidth()) {
        if (entries.isEmpty()) {
            Text("日志没有条目（窗口内没有提交或读不出来）", style = Type.body.copy(color = Palette.TextSecondary))
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
            unparsable?.takeIf { it > 0 }?.let { add("$it 行解析不了（已如实跳过）") }
            if (windowExhausted == true) add("日志窗口已耗尽（更早的提交不在窗口内）")
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
    SectionCard("托管文档", Modifier.fillMaxWidth()) {
        if (docs.isEmpty() && unreadable.isEmpty()) {
            Text("引擎没有返回文档内容", style = Type.body.copy(color = Palette.TextSecondary))
        } else {
            docs.forEach { d ->
                Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                    Text(d.file, style = Type.body.copy(fontWeight = FontWeight.Medium), modifier = Modifier.width(140.dp))
                    Text(
                        "${d.content.length} 字节",
                        style = Type.micro,
                        modifier = Modifier.width(90.dp),
                    )
                    Text(
                        d.content.lineSequence().firstOrNull()?.take(80) ?: "（空文件）",
                        style = Type.micro, maxLines = 1, modifier = Modifier.weight(1f),
                    )
                }
            }
            if (unreadable.isNotEmpty()) {
                Text("存在但读取失败：${unreadable.joinToString("、")}", style = Type.micro.copy(color = Palette.Amber))
            }
        }
    }
}
