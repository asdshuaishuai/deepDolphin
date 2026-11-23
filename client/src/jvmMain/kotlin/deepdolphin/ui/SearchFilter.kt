// SearchFilter.kt —— 搜索过滤（纯函数，mac A11yLabel.swift:79-131 SearchFilter 对位）。
//
// 【为什么是纯函数】「搜不到」有两种完全不同的空：本来就没有（noData）与
// 有东西但没匹配上（noMatch）——不拆开的话，「暂无项目」会把引擎读失败
// 说成用户搜错了词。判定必须可单测，UI 只消费结论。
//
// 匹配规则刻意简单且可预期：大小写不敏感的子串（mac 原话：上分词/模糊匹配
// 会让「为什么搜不到」变得不可解释）。侧栏过滤键 = 项目名 + 分支名
// （mac PanelView.swift:32-36：用户记得「那条 feat 分支」时也要能搜到）。

package deepdolphin.ui

/** 搜索结果的两种「空」。 */
sealed interface SearchEmpty {
    /** 没有任何数据（本来就没有）。 */
    data object NoData : SearchEmpty

    /** 有数据，但没有一条匹配查询。 */
    data class NoMatch(val query: String) : SearchEmpty
}

object SearchFilter {

    /** 按关键词过滤。空查询 ⇒ 原样返回（不制造「搜索后 0 条」的假象）。 */
    fun <T> filter(items: List<T>, query: String, key: (T) -> String): List<T> {
        val q = query.trim()
        if (q.isEmpty()) return items
        return items.filter { key(it).contains(q, ignoreCase = true) }
    }

    /**
     * 结果为空时的原因（视图据此选文案——不许一律「暂无 X」）。
     * 非空结果返回 null；只关心两个数量，刻意不泛型（mac 同款）。
     */
    fun emptyReason(allCount: Int, shownCount: Int, query: String): SearchEmpty? {
        if (shownCount != 0) return null
        if (allCount == 0) return SearchEmpty.NoData
        val q = query.trim()
        // 查询是空的但结果空 ⇒ 只能是「本来就没有」
        return if (q.isEmpty()) SearchEmpty.NoData else SearchEmpty.NoMatch(q)
    }

    /**
     * 空结果文案。两态必须给出不同的话，且把查询原样回显（用户才知道自己搜了什么）。
     * 事实层文本只有 zh/en 两套（mac AppLanguage.usesEnglishFacts 同口径）：
     * 调用方传 noun 与 en（侧栏传 panel.noun.project + 当前语言是否回落英文事实）。
     */
    fun emptyText(
        reason: SearchEmpty,
        noun: String = L10n.t("panel.noun.project"),
        en: Boolean = L10n.language.usesEnglishFacts,
    ): String = when (reason) {
        SearchEmpty.NoData -> if (en) "No $noun yet" else "暂无$noun"
        is SearchEmpty.NoMatch ->
            if (en) "No $noun matching \"${reason.query}\"" else "没有${noun}匹配「${reason.query}」"
    }

    /** 命中数量摘要（搜到 0 条与没搜索过，文案不同；没过滤时不需要说明）。 */
    fun resultSummary(
        allCount: Int,
        shownCount: Int,
        noun: String = L10n.t("panel.noun.project"),
        en: Boolean = L10n.language.usesEnglishFacts,
    ): String? {
        if (allCount == 0) return null
        if (shownCount == allCount) return null
        return if (en) "Matched $shownCount / $allCount $noun" else "匹配 $shownCount / $allCount 个$noun"
    }
}
