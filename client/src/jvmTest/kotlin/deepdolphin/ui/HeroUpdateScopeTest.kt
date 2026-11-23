// HeroUpdateScopeTest.kt —— hero 双轨更新按钮判据（mac Scope.swift ScopeRules 的
// shallowLabel/deepLabel/pending 对位：按钮文案必须带范围；徽章只数当前分支待记录）。

package deepdolphin.ui

import deepdolphin.engine.Branch
import deepdolphin.engine.Project
import kotlin.test.Test
import kotlin.test.assertEquals

class HeroUpdateScopeTest {

    // ── 按钮文案带范围（mac 逐字对位：「浅更新 · 全部」/「浅更新 · <名>」）──

    @Test
    fun unscopedLabelsSayAll() {
        assertEquals("浅更新 · 全部", shallowUpdateLabel(null))
        assertEquals("深更新 · 全部", deepUpdateLabel(null))
    }

    @Test
    fun scopedLabelsCarryProjectName() {
        assertEquals("浅更新 · vtest", shallowUpdateLabel("vtest"))
        assertEquals("深更新 · deepDolphin", deepUpdateLabel("deepDolphin"))
    }

    // ── 待记录徽章：只数当前分支，非当前分支不计入 ──

    private fun project(name: String, vararg branches: Branch) = Project(name = name, branches = branches.toList())

    @Test
    fun pendingSumsOnlyCurrentBranches() {
        val p = project(
            "vtest",
            Branch(name = "main", isCurrent = true, pendingCommits = 3),
            Branch(name = "feat/x", isCurrent = false, pendingCommits = 7),
        )
        assertEquals(3L, pendingCommitsOf(listOf(p), null), "feat 分支的 7 条不归浅更新管")
    }

    @Test
    fun pendingAcrossAllProjectsWhenUnscoped() {
        val a = project("a", Branch(name = "main", isCurrent = true, pendingCommits = 2))
        val b = project("b", Branch(name = "main", isCurrent = true, pendingCommits = 5))
        val c = project("c") // 读不出来的项目 branches 空 = 0，不是「读不出待记录」
        assertEquals(7L, pendingCommitsOf(listOf(a, b, c), null))
    }

    @Test
    fun pendingScopedToNamedProjectOnly() {
        val a = project("a", Branch(name = "main", isCurrent = true, pendingCommits = 2))
        val b = project("b", Branch(name = "main", isCurrent = true, pendingCommits = 5))
        assertEquals(5L, pendingCommitsOf(listOf(a, b), "b"))
    }

    @Test
    fun zeroPendingStaysZeroForBadgeDiscipline() {
        // 徽章只在 >0 时出现（恒显 0 会被无视——UI 侧判断，纯函数如实给 0）
        val p = project("vtest", Branch(name = "main", isCurrent = true, pendingCommits = 0))
        assertEquals(0L, pendingCommitsOf(listOf(p), null))
    }
}
