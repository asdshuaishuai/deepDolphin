// Automation.kt —— 定时更新配置（mac AIIntegration.swift:121 autoUpdateHoursKey = "update.autoHours"
// 的 settings.conf 对位：Linux 无 UserDefaults，落在 ~/.config/deepDolphin/settings.conf 的
// update.* 独立键节——与 ai.* 共文件不共键，互不抹写）。
//
// 纯数据层：fromConf/mergeInto 只动 update.* 键、其他行原样保留
// （AiSettings.mergeInto 同纪律——防「存外观抹定时档」同族事故）。

package deepdolphin.ui

/** 定时更新配置。hours = 0 ⇒ 关闭；deep = false 浅轨道 / true 深轨道。 */
data class AutoUpdateSettings(
    val hours: Int = 0,
    val deep: Boolean = false,
) {
    /** 间隔档位的展示名（对位 mac ScheduleMenu 的 tag 文案）。 */
    fun hourLabel(): String = if (hours <= 0) L10n.t("schedule.off") else L10n.t("cmp.schedule.everyHours", hours)

    companion object {
        /** 档位与 mac ScheduleCard 逐项一致：关闭 / 1 / 3 / 6 / 12 / 24 小时。 */
        val HOUR_CHOICES: List<Int> = listOf(0, 1, 3, 6, 12, 24)
        const val HOURS_KEY = "update.autoHours"
        const val TRACK_KEY = "update.autoTrack"

        /** 解析（缺失/坏值如实降级：坏 hours 落回 0=关闭，不猜一个间隔）。 */
        fun fromConf(text: String): AutoUpdateSettings {
            val map = text.lines().mapNotNull { line ->
                val i = line.indexOf('=')
                if (i > 0) line.substringBefore('=').trim() to line.substringAfter('=', "").trim() else null
            }.toMap()
            return AutoUpdateSettings(
                hours = (map[HOURS_KEY]?.toIntOrNull() ?: 0).coerceAtLeast(0),
                deep = map[TRACK_KEY] == "deep",
            )
        }

        /** 只合并 update.* 键；ai.* 与其他行原样保留（不重排、不删注释行）。 */
        fun mergeInto(existing: String, cfg: AutoUpdateSettings): String {
            val keys = listOf(HOURS_KEY, TRACK_KEY)
            val vals = mapOf(
                HOURS_KEY to cfg.hours.coerceAtLeast(0).toString(),
                TRACK_KEY to if (cfg.deep) "deep" else "shallow",
            )
            val out = existing.lines().mapNotNull { line ->
                val key = line.substringBefore('=').trim()
                if (key in keys) null else line
            }
            return (out + keys.map { "$it=${vals[it]}" }).joinToString("\n") + "\n"
        }
    }
}
