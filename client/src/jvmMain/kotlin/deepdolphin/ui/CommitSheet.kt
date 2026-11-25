// CommitSheet.kt —— 勾选文件级提交单（mac CommitSheetView.swift 的 Compose 对位）。
//
// 【数据面，如实标注（与 mac 的差异）】mac 的清单来自引擎 `git status <项目> --json`
// （恒发 ok/entries/total/project，条目带 xy + 归一化 kind，rename 行是拼好的
// "old -> new"）；本机引擎**没有** git status 子命令（真机实测：
// `moongit git status vtest --json` → ok=false「未知操作：status（支持
// pull/push/commit/stash/unstash/fetch）」）。可行最接近形态 = 引擎 `status <项目> --json`
// 的 dirty.files（真机实测：纯路径数组，无 xy、无 per-file kind；改名在两侧各自出现、
// 没有 "old -> new" 整条形态）——行上只有路径，不造假 kind 徽标。
//
// 【提交口径，如实标注】mac 提交走 `git commit <项目> --message M --paths a,b`
// （引擎只暂存勾选路径）；本机引擎 `--paths` 被拒（真机实测 RC=2
// 「未知 flag：--paths」）——**没有子集提交的引擎语义**。可行最接近形态：
// 勾选集保留（核对清单），但提交只在**全选**时可用；部分勾选 = 如实禁用 + 说清原因，
// 不做「勾了子集却整仓提交」的假勾选框（那比没有勾选框更糟）。
//
// 【默认勾选策略】对位 mac CommitSheetView.swift:196：装载后 selected = 全部条目。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.foundation.layout.PaddingValues

// ── 纯函数层（判据见 CommitSheetTest）──

/**
 * 默认勾选集（mac CommitSheetView.swift:196 对位：装载后全选）。
 * 空清单 → 空集（clean 态不渲染清单，也不会走到提交）。
 */
fun defaultCommitSelection(files: List<String>): Set<String> = files.toSet()

/**
 * 部分勾选的披露行；全选 / 空清单 = null（不渲染——空话比没话说更糟）。
 * 措辞必须说清「为什么不能提交」+「怎么办」，不是一句干巴巴的「不可用」。
 */
fun partialCommitNote(files: List<String>, selected: Set<String>): String? =
    if (files.isNotEmpty() && selected.size < files.size) {
        L10n.t("cmp.commit.noPathsNote", selected.size, files.size)
    } else {
        null
    }

/**
 * 提交可用性：非 busy + 清单非空 + **全选**（引擎无子集提交，见文件头）+ 信息拼得出
 * （commitMessage != null：空白信息引擎直接拒）+ 工作区不干净（干净时引擎必拒）。
 */
/** 引擎清单里没列出来的改动数（dirty.files 有上限，dirty.total 是真实数；只增不减，不为负）。 */
fun unlistedDirtyCount(total: Long, listed: Int): Long = (total - listed).coerceAtLeast(0)

fun canSubmitCommitSheet(
    files: List<String>,
    selected: Set<String>,
    typedMessage: String?,
    busy: Boolean,
    clean: Boolean,
): Boolean = !busy && files.isNotEmpty() && selected.containsAll(files) && typedMessage != null && !clean

// ── 提交单（sheet 形态对位 mac：标题行 / 清单四态 / 底部信息+提交）──

@Composable
fun CommitSheet(model: AppModel, project: String) {
    val detail by model.detail.collectAsState()
    val detailState by model.detailState.collectAsState()
    val busy by model.busyAction.collectAsState()
    val feedback by model.gitFeedback.collectAsState()

    // 打开即重读（openCommitSheet 里已触发 loadDetail）；勾选集/信息是本弹窗的草稿
    var selected by remember(project) { mutableStateOf<Set<String>>(emptySet()) }
    var initialized by remember(project) { mutableStateOf(false) }
    var message by remember(project) { mutableStateOf("") }
    var commitType by remember(project) { mutableStateOf<String?>(null) }

    val p = detail?.projects?.firstOrNull { it.name == project }
    val dirty = p?.dirty
    val files = dirty?.files.orEmpty()

    // 清单到货 → 默认全选（mac 对位：selected = Set(entries.map(\.file))，只做一次）
    LaunchedEffect(files) {
        if (!initialized && files.isNotEmpty()) {
            selected = defaultCommitSelection(files)
            initialized = true
        }
    }
    // 提交成功才关弹窗（mac「失败不弹走」：失败原因留在用户正盯着的这张弹窗里）
    LaunchedEffect(feedback) {
        val fb = feedback ?: return@LaunchedEffect
        if (fb.op == "commit" && fb.project == project && fb.ok) {
            model.closeCommitSheet()
        }
    }

    Dialog(
        onDismissRequest = { model.closeCommitSheet() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            Modifier
                .fillMaxWidth(0.5f)
                .fillMaxHeight(0.66f)
                .clip(RoundedCornerShape(Radius.card))
                .shadow(12.dp, RoundedCornerShape(Radius.card))
                .background(Palette.Card)
                .border(1.dp, Palette.Stroke, RoundedCornerShape(Radius.card))
                .padding(Space.lg),
            verticalArrangement = Arrangement.spacedBy(Space.md),
        ) {
            // ── 标题行（mac：标题 + 项目名副行 + 关闭）──
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(L10n.t("detail.commitChanges"), style = Type.title)
                    Text(project, style = Type.label)
                }
                IconButton(FluentIcon.Dismiss, onClick = { model.closeCommitSheet() })
            }

            // ── 主体四态（mac Phase 对位：loading / clean / failed / 清单）──
            //     「干净」与「读失败」必须分开：前者是事实，后者是降级。
            when {
                // 失败态必须排在「加载中」前面：loadDetail 一进来就清空旧详情，
                // 原来的顺序让读失败时永远转圈
                detailState is LoadState.Failed -> Box(Modifier.weight(1f).fillMaxWidth()) {
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("⚠ " + L10n.t("gitop.commitSheet.readFailed"), style = Type.section.copy(color = Palette.Amber))
                        Spacer(Modifier.height(Space.xs))
                        Text((detailState as LoadState.Failed).reason, style = Type.label, maxLines = 3)
                    }
                }
                detailState is LoadState.Loading || p == null -> Box(
                    Modifier.weight(1f).fillMaxWidth(),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(Modifier.size(16.dp), color = Palette.Accent, strokeWidth = 2.dp)
                        Spacer(Modifier.height(Space.sm))
                        Text(L10n.t("gitop.commitSheet.loading"), style = Type.label)
                    }
                }
                dirty == null -> Box(Modifier.weight(1f).fillMaxWidth()) {
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("⚠ " + L10n.t("gitop.commitSheet.readFailed"), style = Type.section.copy(color = Palette.Amber))
                        Spacer(Modifier.height(Space.xs))
                        Text(L10n.t("cmp.err.noDirty"), style = Type.label)
                    }
                }
                !dirty.ok -> Box(Modifier.weight(1f).fillMaxWidth()) {
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("⚠ " + L10n.t("gitop.commitSheet.readFailed"), style = Type.section.copy(color = Palette.Amber))
                        Spacer(Modifier.height(Space.xs))
                        Text(dirty.err ?: L10n.t("cmp.err.noReason"), style = Type.label, maxLines = 3)
                    }
                }
                dirty.clean || files.isEmpty() -> Box(Modifier.weight(1f).fillMaxWidth()) {
                    Text(
                        L10n.t("gitop.commitSheet.clean"),
                        style = Type.body.copy(color = Palette.TextSecondary),
                        modifier = Modifier.align(Alignment.Center),
                    )
                }
                else -> ScrollColumn(
                    Modifier.weight(1f).fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    files.forEach { f ->
                        val checked = f in selected
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(Radius.control))
                                .background(if (checked) Palette.CardHover else Color.Transparent)
                                .clickable {
                                    selected = if (checked) selected - f else selected + f
                                }
                                .padding(horizontal = Space.sm, vertical = 5.dp),
                        ) {
                            IconBox(
                                if (checked) FluentIcon.CheckboxChecked else FluentIcon.CheckboxUnchecked,
                                size = 18.dp,
                                tint = if (checked) Palette.Accent else Palette.TextSecondary,
                            )
                            Spacer(Modifier.width(Space.sm))
                            // 引擎 dirty.files 只有路径（无 xy/kind，见文件头）——不造假徽标
                            Text(
                                f,
                                style = Type.label.copy(fontFamily = FontFamily.Monospace, color = Palette.TextPrimary),
                                maxLines = 1,
                            )
                        }
                    }
                    // 引擎 dirty.files 最多只发前 30 个路径；改动更多时必须说出来——
                    // 清单看着是「30/30 已选」，提交却是整仓，没列出的文件会一并进去
                    val unlisted = unlistedDirtyCount(dirty.total, files.size)
                    if (unlisted > 0) {
                        Text(L10n.t("cmp.commit.unlisted", files.size, unlisted, dirty.total), style = Type.label, color = Palette.Amber)
                    }
                }
            }

            // ── 底部：计数 + 全选切换 + 类型 + 信息 + 提交（只在清单态出现，mac 同款）──
            if (dirty != null && dirty.ok && !dirty.clean && files.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(Space.sm)) {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(Palette.Stroke))
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                        Text(L10n.t("gitop.commitSheet.selectedCount", selected.size, files.size), style = Type.label)
                        Text(
                            if (selected.size == files.size) L10n.t("gitop.commitSheet.deselectAll") else L10n.t("gitop.commitSheet.selectAll"),
                            style = Type.label.copy(color = Palette.Accent, fontWeight = FontWeight.SemiBold),
                            modifier = Modifier.clickable {
                                selected = if (selected.size == files.size) emptySet() else defaultCommitSelection(files)
                            },
                        )
                        Spacer(Modifier.weight(1f))
                        Text(
                            L10n.t("cmp.commit.allNote"),
                            style = Type.micro,
                        )
                    }
                    // 类型前缀（复用既有类型选择：词表 + 拼装判定都在 ProjectDetailView.kt 纯函数层）
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                    ) {
                        Text(L10n.t("cgraph.dim.type"), style = Type.label)
                        Spacer(Modifier.width(Space.xs))
                        listOf(null).plus(COMMIT_TYPE_WORDS).forEach { t ->
                            val sel = commitType == t
                            Text(
                                t ?: L10n.t("cmp.commit.noKind"),
                                style = Type.micro.copy(fontWeight = if (sel) FontWeight.SemiBold else FontWeight.Normal),
                                color = if (sel) Palette.BgBase else Palette.TextSecondary,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(999.dp))
                                    .background(if (sel) Palette.Accent else Palette.CardHover)
                                    .clickable { commitType = t }
                                    .padding(horizontal = 8.dp, vertical = 3.dp),
                            )
                        }
                    }
                    val typed = commitMessage(commitType, message)
                    val partial = partialCommitNote(files, selected)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                        OutlinedTextField(
                            colors = fluentTextFieldColors(),
                            value = message,
                            onValueChange = { message = it },
                            placeholder = { Text(L10n.t("gitop.commitSheet.messagePlaceholder"), style = Type.micro) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            textStyle = Type.body,
                        )
                        Button(
                            onClick = { typed?.let { model.gitOp("commit", project, it) } },
                            enabled = canSubmitCommitSheet(files, selected, typed, busy, clean = false),
                            shape = RoundedCornerShape(Radius.control),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Palette.Accent,
                                contentColor = Palette.OnAccent,
                            ),
                        ) { Text(if (busy) L10n.t("cmp.commit.busy") else L10n.t("gitop.commit")) }
                    }
                    // 部分勾选 = 引擎做不了，如实说（判据 partialCommitNote）
                    partial?.let { Text("⚠ $it", style = Type.micro.copy(color = Palette.Amber)) }
                    // 本弹窗发起的 commit 失败回执：留在原地（mac「失败不弹走」）
                    feedback?.let { fb ->
                        if (fb.op == "commit" && fb.project == project && !fb.ok) {
                            IconBox(FluentIcon.ErrorCircle, size = 14.dp, tint = Palette.Amber)
                            Spacer(Modifier.width(6.dp))
                            Text(
                                fb.text.trim().take(200).ifEmpty { "（引擎未给出原因）" },
                                style = Type.micro.copy(color = Palette.Amber),
                                maxLines = 2,
                            )
                        }
                    }
                }
            }
        }
    }
}
