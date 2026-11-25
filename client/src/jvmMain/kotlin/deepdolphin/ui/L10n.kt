// L10n.kt —— 多语言本地化系统（对位 mac L10n.swift；zh-CN / en / zh-TW / ja）。
//
// 设计（与 mac 同源）：
// - 四语言表在 L10nTables.kt（脚本从 mac 基准生成，504 键照搬不改写）；
//   CMP 特有键在 L10nCmpKeys.kt（mac 没有、CMP 新增的文案，以 zh 为源补四语言）。
// - 语言状态是 Compose mutableStateOf：任何 composable 里调 L10n.t("key") 即订阅，
//   setLanguage 一翻全界面即时生效（mac @Published language + ObservableObject 对位）。
// - 语言选择存 settings.conf 的 app.language 键（独立节，与 ai.* / update.* 共文件
//   不共键，mergeInto 只动自己的键——防「存外观抹别节」事故，纪律同 AutoUpdateSettings）。
// - 启动恢复：conf 有值用 conf；没有则跟随系统语言（mac
//   Bundle.main.preferredLocalizations 对位：只认这四种，认不出的缺省 zh-CN）。
// - miss 回退链：当前语言表 → en → key（mac 同链；表 = mac 基准表 + CMP 特有键表）。
// - 表值占位符沿用 Swift 口径：%@（任意值）/ %d（整数）/ %1$d 位置参；
//   t(key, args...) 时 %@ → %s 后走 String.format(Locale.ROOT)。
//   不带参调用原样返回（表值里 75% 这类字面百分号不会被格式化——mac 同款语义）。

package deepdolphin.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** 应用语言（对位 mac AppLanguage；label 不本地化——各语言永远用本名显示）。 */
enum class AppLanguage(val code: String, val label: String) {
    ZH_CN("zh-CN", "简体中文"),
    EN("en", "English"),
    ZH_TW("zh-TW", "繁體中文"),
    JA("ja", "日本語");

    /** 事实层文本（KPI 标题/空态词等）只有 zh/en 两套：繁中共用简中事实，日文回落英文。 */
    val usesEnglishFacts: Boolean get() = this == EN || this == JA

    companion object {
        fun fromCode(code: String?): AppLanguage? = code?.let { c ->
            entries.firstOrNull { it.code == c }
        }

        /**
         * 跟随系统语言（mac preferredLocalizations 对位）：只认这四种。
         * 中文按地区细分（TW/HK/MO/澳门用繁体）；认不出返回 null（调用方落 zh-CN）。
         */
        fun fromSystemLocale(locale: java.util.Locale): AppLanguage? = when (locale.language) {
            "zh" -> when (locale.country.uppercase()) {
                "TW", "HK", "MO" -> ZH_TW
                else -> ZH_CN
            }
            "en" -> EN
            "ja" -> JA
            else -> null
        }
    }
}

/** 固定长文四件套（对位 mac DocPageKind）。titleKey 复用 settings.* 键做小节标题。 */
enum class DocKind(val titleKey: String) {
    ABOUT("settings.about"),
    HELP("settings.help"),
    OPEN_SOURCE("settings.openSource"),
    CHANGELOG("settings.changelog"),
}

object L10n {
    /** 当前语言（Compose 状态：t() 在组合中读它 ⇒ 换语言全界面重组）。 */
    var language: AppLanguage by mutableStateOf(restoreLanguage())
        private set

    /** settings.conf 的语言键（mac UserDefaults "app.language" 对位）。 */
    const val LANGUAGE_KEY = "app.language"

    // ── conf 纯函数（可单测；与 AutoUpdateSettings.mergeInto 同纪律）──

    /** 从 conf 文本解析语言；没配/坏值返回 null（调用方走系统语言/缺省 zh）。 */
    fun languageFromConf(text: String): AppLanguage? {
        val map = text.lines().mapNotNull { line ->
            val i = line.indexOf('=')
            if (i > 0) line.substringBefore('=').trim() to line.substringAfter('=', "").trim() else null
        }.toMap()
        return AppLanguage.fromCode(map[LANGUAGE_KEY])
    }

    /** 只合并 app.language 键；ai.* / update.* 与其他行原样保留（不重排、不删注释行）。 */
    fun mergeLanguageInto(existing: String, lang: AppLanguage): String {
        val out = existing.lines().filterNot { line ->
            line.substringBefore('=').trim() == LANGUAGE_KEY
        }
        return (out + "$LANGUAGE_KEY=${lang.code}").joinToString("\n") + "\n"
    }

    private fun restoreLanguage(): AppLanguage =
        languageFromConf(ConfStore.read())
            ?: AppLanguage.fromSystemLocale(java.util.Locale.getDefault())
            ?: AppLanguage.ZH_CN

    /** 当前语言完整表（mac 表 + CMP 特有键；internal 供单测做键集完整性校验）。 */
    // 合并表只算一次：原来每次 t() 都把两张表相加拷一遍（约 850 项），
    // 每次重组里每个字符串都拷一遍——纯浪费。
    private val mergedTables: Map<AppLanguage, Map<String, String>> = AppLanguage.entries.associateWith { lang ->
        when (lang) {
            AppLanguage.ZH_CN -> L10N_ZH_CN + L10N_CMP_ZH_CN
            AppLanguage.EN -> L10N_EN + L10N_CMP_EN
            AppLanguage.ZH_TW -> L10N_ZH_TW + L10N_CMP_ZH_TW
            AppLanguage.JA -> L10N_JA + L10N_CMP_JA
        }
    }

    fun table(lang: AppLanguage): Map<String, String> = mergedTables.getValue(lang)

    /** 翻译入口：`L10n.t("nav.dashboard")`。miss 回退：当前表 → en → key（mac 同链）。 */
    fun t(key: String): String = table(language)[key] ?: table(AppLanguage.EN)[key] ?: key

    /** 带参数的翻译：表值里 %@ / %d / %1$d 占位（%@ 运行期折算 %s）。 */
    fun t(key: String, vararg args: Any?): String {
        val raw = t(key)
        if (args.isEmpty()) return raw
        return String.format(java.util.Locale.ROOT, raw.replace("%@", "%s"), *args)
    }

    /** 固定长文获取（对位 mac L10n.shared.doc(_:)）。 */
    fun doc(kind: DocKind): String = DocPagesText.content(kind, language)

    /** 只切内存状态不落盘（单测钉语言用——不许碰真实 settings.conf）。 */
    fun applyLanguage(lang: AppLanguage) {
        language = lang
    }

    /**
     * 切语言并持久化（对位 mac didSet 写 UserDefaults + 设置页 Picker 即时生效）。
     * 返回写 conf 的错误（null = 成功）；写失败语言状态也已切换——界面即时生效优先，
     * 持久化失败如实回给设置页展示（mac UserDefaults 不会失败，conf 会——差异如实）。
     */
    fun setLanguage(lang: AppLanguage): String? {
        applyLanguage(lang)
        return ConfStore.writeLanguage(lang)
    }
}
