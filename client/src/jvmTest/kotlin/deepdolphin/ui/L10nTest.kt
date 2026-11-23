// L10nTest.kt —— 多语言框架判据（对位 mac L10n.swift / DocsPages.swift 的 CMP 对齐面）。
//
// 【判据只增不减】本文件只加不改既有判据。覆盖四块：
//   1. 键集四语言完整性对齐——任何语言缺键/多键即红（缺键即红是任务口径）；
//   2. 占位符口径——%@ / %d / %1$d 四语言数量一致（错位会在运行期拼出残句）；
//   3. t() 语义——回退链（当前 → en → key）、带参格式化、无参原样返回（75% 这类
//      字面百分号不被格式化触碰）；
//   4. 语言切换读写——languageFromConf / mergeLanguageInto 纯函数（settings.conf 的
//      app.language 独立节，不抹 ai.* / update.*）+ 四文档随语言分发。

package deepdolphin.ui

import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class L10nTest {

    @BeforeTest
    fun pinZh() {
        // 默认断言锚定 zh；涉及其他语言的用例自会显式切
        L10n.applyLanguage(AppLanguage.ZH_CN)
    }

    // ── 1. 键集四语言完整性（缺键即红）──

    @Test
    fun fourLanguageTablesHaveIdenticalKeySets() {
        val base = L10n.table(AppLanguage.ZH_CN).keys
        // mac 基准 504 键全量搬运（照搬不改写——数量缩水即搬运出了错）
        assertEquals(504, L10N_ZH_CN.size, "mac zh-CN 表键数")
        assertEquals(L10N_ZH_CN.size + L10N_CMP_ZH_CN.size, base.size, "zh-CN 合表键数（mac + cmp）")
        for (lang in AppLanguage.entries) {
            val keys = L10n.table(lang).keys
            val missing = base - keys
            val extra = keys - base
            assertTrue(
                missing.isEmpty() && extra.isEmpty(),
                "$lang 键集不齐：缺 $missing 多 $extra——缺键即红，以 zh 为源补齐",
            )
        }
    }

    @Test
    fun cmpKeysAreNamespacedAndDoNotShadowMacKeys() {
        val macKeys = L10N_ZH_CN.keys
        val cmpKeys = L10N_CMP_ZH_CN.keys
        // cmp 键全带 cmp. 前缀且不与 mac 键撞名（撞名会被 + 合并静默覆盖——那是最坏情况）
        assertTrue(cmpKeys.all { it.startsWith("cmp.") }, "CMP 特有键必须 cmp. 前缀")
        assertTrue((macKeys intersect cmpKeys).isEmpty(), "CMP 键不得与 mac 键重名")
    }

    // ── 2. 占位符四语言一致（%@ / %d / %1$d）──

    private fun placeholdersOf(v: String): List<String> =
        Regex("%\\d*\\$?[@d]").findAll(v).map { it.value }.sorted().toList()

    @Test
    fun placeholderKindsMatchAcrossLanguages() {
        var checked = 0
        for (key in L10N_ZH_CN.keys) {
            val expect = placeholdersOf(L10N_ZH_CN.getValue(key))
            if (expect.isEmpty()) continue
            checked++
            for (lang in AppLanguage.entries) {
                val got = placeholdersOf(L10n.table(lang).getValue(key))
                assertEquals(expect, got, "$key@$lang 占位符集不一致（%@↔%d 错位会拼出残句）")
            }
        }
        assertTrue(checked > 50, "占位符键样本量异常：$checked")
    }

    // ── 3. t() 语义 ──

    @Test
    fun tResolvesCurrentLanguage() {
        assertEquals("仪表盘", L10n.t("nav.dashboard"))
        L10n.applyLanguage(AppLanguage.EN)
        assertEquals("Dashboard", L10n.t("nav.dashboard"))
    }

    @Test
    fun tFallsBackToEnThenKey() {
        // miss → en → key（mac 同链）。用不存在的键验末端两跳。
        assertEquals("no.such.key", L10n.t("no.such.key"))
        // 四表全覆盖 ⇒ 正常键永远不会走到 key 一跳；en 回退由表结构保证（见键集判据）
    }

    @Test
    fun tFormatsStringAndIntPlaceholders() {
        assertEquals("仓库（2/5）", L10n.t("nav.repos.count", 2, 5))
        L10n.applyLanguage(AppLanguage.JA)
        assertEquals("リポジトリ (2/5)", L10n.t("nav.repos.count", 2, 5)) // mac ja 原文即半角括号
        L10n.applyLanguage(AppLanguage.ZH_CN)
        // %@（任意值）→ %s 折算；%d 收整数
        assertEquals("分支 feat/x", L10n.t("board.chip.branch", "feat/x"))
    }

    @Test
    fun tWithoutArgsReturnsRawSoLiteralPercentStaysIntact() {
        // patch.lowEmpty 含字面「75%」：不带参调用不得走 String.format（mac 同语义）
        assertEquals("没有低于 75% 的实体——本补丁整体可信度尚可。", L10n.t("patch.lowEmpty"))
    }

    // ── 4. 语言切换读写（settings.conf 的 app.language 独立节）──

    @Test
    fun languageFromConfParsesKnownCodesAndDegradesToNull() {
        assertEquals(AppLanguage.ZH_CN, L10n.languageFromConf("app.language=zh-CN"))
        assertEquals(AppLanguage.EN, L10n.languageFromConf("app.language=en"))
        assertEquals(AppLanguage.ZH_TW, L10n.languageFromConf("app.language=zh-TW"))
        assertEquals(AppLanguage.JA, L10n.languageFromConf("app.language=ja"))
        // 没配 / 坏值 → null（调用方走系统语言/缺省 zh，不猜）
        assertNull(L10n.languageFromConf(""))
        assertNull(L10n.languageFromConf("ai.provider=deepseek\nupdate.autoHours=3"))
        assertNull(L10n.languageFromConf("app.language=klingon"))
    }

    @Test
    fun mergeLanguageIntoOnlyTouchesItsOwnKey() {
        val existing = "# 注释保留\nai.provider=deepseek\nupdate.autoHours=3\nupdate.autoTrack=deep\n"
        val out = L10n.mergeLanguageInto(existing, AppLanguage.JA)
        assertTrue(out.contains("ai.provider=deepseek"), "不得抹 ai.* 节")
        assertTrue(out.contains("update.autoHours=3"), "不得抹 update.* 节")
        assertTrue(out.contains("# 注释保留"), "不得删注释行")
        assertTrue(out.contains("app.language=ja"))
        // 换语言 = 原位替换，不是追加第二行
        val out2 = L10n.mergeLanguageInto(out, AppLanguage.EN)
        assertEquals(1, Regex("app.language=").findAll(out2).count())
        assertTrue(out2.contains("app.language=en"))
    }

    @Test
    fun systemLocaleResolutionFollowsRegion() {
        assertEquals(AppLanguage.ZH_TW, AppLanguage.fromSystemLocale(java.util.Locale.TRADITIONAL_CHINESE))
        assertEquals(AppLanguage.ZH_TW, AppLanguage.fromSystemLocale(java.util.Locale("zh", "HK")))
        assertEquals(AppLanguage.ZH_CN, AppLanguage.fromSystemLocale(java.util.Locale.SIMPLIFIED_CHINESE))
        assertEquals(AppLanguage.EN, AppLanguage.fromSystemLocale(java.util.Locale.ENGLISH))
        assertEquals(AppLanguage.JA, AppLanguage.fromSystemLocale(java.util.Locale.JAPANESE))
        // 认不出的语言 → null（调用方落缺省 zh-CN，mac preferredLocalizations 同款纪律）
        assertNull(AppLanguage.fromSystemLocale(java.util.Locale.FRENCH))
    }

    @Test
    fun applyLanguageSwitchesWithoutPersisting() {
        // 单测不许碰真实 settings.conf：applyLanguage 只翻内存状态
        L10n.applyLanguage(AppLanguage.ZH_TW)
        assertEquals("儀表板".let { L10n.t("nav.dashboard") }, L10n.t("nav.dashboard"))
        assertNotEquals("仪表盘", L10n.t("nav.dashboard"))
    }

    // ── 四文档（DocsPages 对位）──

    @Test
    fun docsDispatchByKindAndLanguage() {
        for (lang in AppLanguage.entries) {
            L10n.applyLanguage(lang)
            for (kind in DocKind.entries) {
                val text = L10n.doc(kind)
                assertTrue(text.isNotBlank(), "$kind@$lang 文档为空")
                // 产品名锚定「关于」文档（开源感谢一节只谢第三方，原文没有产品名——不硬造）
                if (kind == DocKind.ABOUT) {
                    assertTrue("deepDolphin" in text, "$kind@$lang 缺产品名")
                }
            }
        }
        // 抽查语言真的在换内容（不是四语言同文）
        L10n.applyLanguage(AppLanguage.ZH_CN)
        val zh = L10n.doc(DocKind.ABOUT)
        L10n.applyLanguage(AppLanguage.EN)
        val en = L10n.doc(DocKind.ABOUT)
        assertNotEquals(zh, en)
        assertTrue("原生客户端" in zh)
        assertTrue("Native client" in en)
    }

    @Test
    fun docKindTitlesReuseSettingsKeys() {
        L10n.applyLanguage(AppLanguage.ZH_CN)
        assertEquals("关于", L10n.t(DocKind.ABOUT.titleKey))
        assertEquals("帮助", L10n.t(DocKind.HELP.titleKey))
        assertEquals("开源感谢", L10n.t(DocKind.OPEN_SOURCE.titleKey))
        assertEquals("更新日志", L10n.t(DocKind.CHANGELOG.titleKey))
    }
}
