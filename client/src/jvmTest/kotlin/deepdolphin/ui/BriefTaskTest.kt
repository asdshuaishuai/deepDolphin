// BriefTaskTest.kt —— 一键说明任务串的固定口径（对位 mac 基准逐句，判据只增不减）。

package deepdolphin.ui

import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class BriefTaskTest {

    @BeforeTest
    fun pinZh() {
        // 断言锚定 zh 文案：钉住语言，防宿主 locale / settings.conf 漂移翻红
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    @Test
    fun groupBriefQuestionMatchesMacWording() {
        // 项目群（null）：mac GroupBriefButton 的固定问题逐句一致
        // （AIIntegration.swift:439，target .group；400 字上限口径不变）
        assertEquals(
            "生成一份项目群说明（markdown）：项目构成与定位、各项目一句话现状、需要人处理的事项（未提交/停滞/待合入）、整体建议。400 字以内。",
            briefTask(null),
        )
    }

    @Test
    fun projectBriefInterpolatesNameAndKeepsFourSections() {
        // 单项目：mac AgentCore.projectBrief 四段式（AgentCore.swift:469-476）——
        // 项目名必须进问题串（作用域靠它，不是靠 UI 上下文）；四段一条不少；500 字上限与「不编造」在
        val q = briefTask("deepGit")
        assertTrue(q.contains("「deepGit」"), "项目名未进问题串：$q")
        listOf(
            "1. 一句话定位（结合 README 与代码构成判断它是什么）",
            "2. 当前状态（分支进度、未提交/未跟踪/stash、最近活跃）",
            "3. 工程结构要点（语言构成、热点文件）",
            "4. 风险与建议下一步",
        ).forEach { section -> assertTrue(q.contains(section), "缺段：$section") }
        assertTrue(q.contains("500 字以内") && q.contains("不编造"))
    }

    @Test
    fun nullAndBlankFallToGroupAndDifferFromProject() {
        // 空白串按项目群兜底（调用点约定传 null，纯函数对脏输入不崩、不产出第三种口径）；
        // 项目群与单项目是两种不同的问题，绝不串
        assertEquals(briefTask(null), briefTask("   "))
        assertNotEquals(briefTask(null), briefTask("deepGit"))
        assertTrue(briefTask(null).contains("项目群说明"))
    }
}
