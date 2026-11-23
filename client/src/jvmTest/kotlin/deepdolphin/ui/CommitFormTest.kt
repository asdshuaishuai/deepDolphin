// CommitFormTest.kt —— 提交单纯函数判据（commitMessage：类型前缀拼装）。
//
// 口径锚定引擎 kernel/git.cj：COMMIT_TYPE_ORDER 12 类去 other（git.cj:888）、别名归并
// （git.cj:922-936）、--message 非空硬要求（git.cj:1846）。判据只增不减。

package deepdolphin.ui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class CommitFormTest {

    // ── 空白信息 → null（按钮可用性挂在这里；引擎对空 message 直接拒）──

    @Test
    fun blankMessageIsNeverSubmittable() {
        assertNull(commitMessage(null, ""))
        assertNull(commitMessage(null, "   "))
        assertNull(commitMessage("feat", "\n\t "), "类型救不了空白信息")
    }

    // ── 无类型：信息 trim 后原样（引擎归到 other 桶）──

    @Test
    fun noTypePassesTrimmedMessageUntouched() {
        assertEquals("修了个问题", commitMessage(null, " 修了个问题 "))
        assertEquals("修了个问题", commitMessage("  ", " 修了个问题 "), "空白类型 = 无类型")
    }

    // ── 有类型：前缀拼装 ──

    @Test
    fun typeBecomesPrefix() {
        assertEquals("feat: 加了扫描单", commitMessage("feat", " 加了扫描单 "))
        assertEquals("fix: 修了空指针", commitMessage("fix", "修了空指针"))
    }

    // ── 信息已自带类型前缀 → 不双前缀（词表 + 引擎同款别名 + scope 形）──

    @Test
    fun alreadyTypedMessageIsNotDoublePrefixed() {
        assertEquals("feat: x", commitMessage("fix", "feat: x"), "前缀词不重复加")
        assertEquals("feat(api): x", commitMessage("fix", "feat(api): x"), "scope 形也不重复加")
        assertEquals("feature: x", commitMessage("feat", "feature: x"), "引擎别名（feature→feat）同认")
        assertEquals("HOTFIX: y", commitMessage("fix", "HOTFIX: y"), "别名大小写不敏感；用户原文不被改写")
    }

    @Test
    fun typeWordsMatchEngineVocabulary() {
        // 引擎 COMMIT_TYPE_ORDER 去 other（other 是无前缀的归类，客户端用「无类型」表达）
        assertEquals(
            listOf("feat", "fix", "perf", "refactor", "docs", "test", "build", "ci", "style", "chore", "revert"),
            COMMIT_TYPE_WORDS,
        )
        COMMIT_TYPE_WORDS.forEach { w -> assertEquals("$w: 事", commitMessage(w, "事")) }
    }
}
