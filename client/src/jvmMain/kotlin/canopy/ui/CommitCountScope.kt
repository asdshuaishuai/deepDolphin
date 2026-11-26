// CommitCountScope.kt —— journal 条目里那个「+N」的口径与徽章判定（mac CommitCountScope.swift 对位）。
//
// 【为什么是纯函数】判定内联在视图里时运行时抓不到，而「同名不同义」只能靠断言钉住：
// 浅更新的 commitCount = 本轮真正新记录的提交数（scope "new"），
// 深更新的 commitCount = 仓库提交总数（scope "repoTotal"，随仓库一直涨）。
// 一个「本轮新增 6」和一个「仓库一共 6 个」若渲染成同一个绿色 +6，读者会得出
// 「深更新也新增了 6 个提交」。口径 / 是否样本 / 读不出来 三种状态必须分开。
// 靠 mode 去猜口径不行：那是约定不是契约（引擎注释原话）。

package canopy.ui

/** 口径。 */
enum class CommitCountScope {
    /** 本轮新增。 */
    NEW_COMMITS,
    /** 仓库提交总数。 */
    REPO_TOTAL,
    /** 口径未知——不能默认成上面任何一个。 */
    UNKNOWN,
    /** 读不出来（-1 或缺键）。 */
    UNREADABLE;

    /** 口径不是「本轮新增」时徽章不能用绿色——绿 + 无限定词 = 把累计量说成增量。 */
    val isIncremental: Boolean get() = this == NEW_COMMITS
}

/** `+N` 该显示成什么。text=null 表示不显示徽章；note 必须写进界面。 */
data class CommitCountBadge(
    val text: String?,
    val scope: CommitCountScope,
    val truncated: Boolean,
    val note: String?,
)

fun commitCountScopeOf(raw: String?, commitCount: Long?): CommitCountScope {
    // 缺键与 -1 一样是「整个数字没意义」，不是「没提交」
    if (commitCount == null || commitCount < 0) return CommitCountScope.UNREADABLE
    return when (raw) {
        "new" -> CommitCountScope.NEW_COMMITS
        "repoTotal" -> CommitCountScope.REPO_TOTAL
        else -> CommitCountScope.UNKNOWN
    }
}

private fun CommitCountScope.suffix(): String = when (this) {
    CommitCountScope.NEW_COMMITS -> L10n.t("cmp.journal.scope.new")
    CommitCountScope.REPO_TOTAL -> L10n.t("cmp.journal.scope.repoTotal")
    CommitCountScope.UNKNOWN -> L10n.t("cmp.journal.scope.unknown")
    CommitCountScope.UNREADABLE -> L10n.t("cmp.journal.scope.unreadable")
}

fun commitCountBadge(commitCount: Long?, scope: String?, truncated: Boolean?): CommitCountBadge {
    val s = commitCountScopeOf(scope, commitCount)
    // 读不出来：绝不能显示成 0
    if (s == CommitCountScope.UNREADABLE) {
        return CommitCountBadge(
            text = L10n.t("cmp.journal.unreadableText"),
            scope = s, truncated = false, note = L10n.t("cmp.journal.unreadableNote"),
        )
    }
    val n = commitCount ?: 0
    // 0 个新增不是一条值得占位的信息
    if (n == 0L) return CommitCountBadge(null, s, false, null)
    val notes = buildList {
        if (s == CommitCountScope.UNKNOWN) add(L10n.t("cmp.journal.unknownScopeNote"))
        if (truncated == true) add(L10n.t("cmp.journal.sampleNote"))
    }
    return CommitCountBadge(
        text = "+$n ${s.suffix()}",
        scope = s,
        truncated = truncated == true,
        note = notes.takeIf { it.isNotEmpty() }?.joinToString(L10n.t("cmp.journal.noteSep")),
    )
}

/** 条目模式标签（mac JournalEntry.modeLabel 对位）。 */
fun journalModeLabel(mode: String): String = when (mode) {
    "track" -> L10n.t("cmp.journal.mode.track")
    "shallow" -> L10n.t("cmp.journal.mode.shallow")
    "deep" -> L10n.t("cmp.journal.mode.deep")
    "manual" -> L10n.t("cmp.journal.mode.manual")
    else -> mode
}

/** 进度日志条数一行（mac Progress.entryCountLine 对位）：截断时写「已保留/总共（已截断）」。 */
fun entryCountLine(entryCount: Long, entriesKept: Long, entryCountTruncated: Boolean?): String =
    if (entryCountTruncated == true || entryCount > entriesKept) {
        L10n.t("cmp.progress.entryCountTruncated", entriesKept, entryCount)
    } else {
        L10n.t("cmp.progress.entryCount", entryCount)
    }
