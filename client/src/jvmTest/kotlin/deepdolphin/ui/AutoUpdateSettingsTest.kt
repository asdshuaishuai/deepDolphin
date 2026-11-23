// AutoUpdateSettingsTest.kt —— 定时更新配置读写判据（mac setAutoUpdate/update.autoHours 对位；
// mergeInto 只动 update.* 键、不抹 ai.* ——「存外观抹定时档」同族事故的判据）。

package deepdolphin.ui

import deepdolphin.ai.AiSettings
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AutoUpdateSettingsTest {

    // ── fromConf ──

    @Test
    fun emptyConfMeansOff() {
        val cfg = AutoUpdateSettings.fromConf("")
        assertEquals(0, cfg.hours)
        assertFalse(cfg.deep)
    }

    @Test
    fun parsesHoursAndTrack() {
        val cfg = AutoUpdateSettings.fromConf("update.autoHours=3\nupdate.autoTrack=deep\n")
        assertEquals(3, cfg.hours)
        assertTrue(cfg.deep)
    }

    @Test
    fun badValuesDegradeToOffNotGuesses() {
        // 坏 hours 落回 0=关闭，不猜一个间隔；track 只认 "deep"，其他值 = 浅轨道
        assertEquals(0, AutoUpdateSettings.fromConf("update.autoHours=abc").hours)
        assertEquals(0, AutoUpdateSettings.fromConf("update.autoHours=-5").hours, "负数不猜成 0 小时间隔")
        assertFalse(AutoUpdateSettings.fromConf("update.autoTrack=Deep").deep)
    }

    @Test
    fun hourChoicesMatchMacScheduleCard() {
        // mac ScheduleMenu tags：0/1/3/6/12/24（含「关闭」档）
        assertEquals(listOf(0, 1, 3, 6, 12, 24), AutoUpdateSettings.HOUR_CHOICES)
    }

    @Test
    fun hourLabelMatchesMacWording() {
        assertEquals("关闭", AutoUpdateSettings(hours = 0).hourLabel())
        assertEquals("每 1 小时", AutoUpdateSettings(hours = 1).hourLabel())
        assertEquals("每 24 小时", AutoUpdateSettings(hours = 24).hourLabel())
    }

    // ── mergeInto：独立节纪律 ──

    @Test
    fun mergePreservesAiKeysAndForeignLines() {
        val existing = "ai.providerID=deepseek\nai.model=x\nai.baseURL=https://a\n# 注释行原样保留\n"
        val out = AutoUpdateSettings.mergeInto(existing, AutoUpdateSettings(hours = 6, deep = true))
        assertTrue("ai.providerID=deepseek" in out.lines(), "ai.* 不得被定时档写盘抹掉")
        assertTrue("# 注释行原样保留" in out.lines())
        assertTrue("update.autoHours=6" in out.lines())
        assertTrue("update.autoTrack=deep" in out.lines())
    }

    @Test
    fun mergeReplacesOldUpdateKeysWithoutDuplication() {
        val existing = "update.autoHours=1\nupdate.autoTrack=shallow\n"
        val out = AutoUpdateSettings.mergeInto(existing, AutoUpdateSettings(hours = 12))
        assertEquals(1, out.lines().count { it.startsWith("update.autoHours=") }, "旧值必须换掉，不许两行并存")
        assertTrue("update.autoHours=12" in out.lines())
        assertTrue("update.autoTrack=shallow" in out.lines())
    }

    @Test
    fun roundTripSurvivesConfFile() {
        val cfg = AutoUpdateSettings(hours = 24, deep = true)
        val text = AutoUpdateSettings.mergeInto("ai.model=m\n", cfg)
        assertEquals(cfg, AutoUpdateSettings.fromConf(text))
    }

    @Test
    fun autoAndAiWritesDoNotClobberEachOther() {
        // 两条写路径共用一个 settings.conf：先后各写一次，两节都在
        var text = AiSettings.mergeInto("", AiSettings(providerID = "ollama", model = "q", baseURL = "http://l"))
        text = AutoUpdateSettings.mergeInto(text, AutoUpdateSettings(hours = 3))
        assertEquals(AiSettings(providerID = "ollama", model = "q", baseURL = "http://l"), AiSettings.fromConf(text))
        assertEquals(AutoUpdateSettings(hours = 3, deep = false), AutoUpdateSettings.fromConf(text))
    }
}
