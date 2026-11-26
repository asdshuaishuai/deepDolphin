// Skin.kt —— 界面皮肤（namethatui.com/styles 全量风格，flat design 按用户要求除外）。
//
// 【令牌怎么换】Design.kt 的 Palette / Type / Radius 是 mutableStateOf 支撑的可变令牌；
// Skins.apply(skin) 把一份 Skin 的值写进去，正在组合的界面全部重组——与切语言同一机制。
// 组件的「形态」差异（描边宽度、阴影形态、顶部光泽、背景装饰）走 Material 令牌，
// Buttons.kt / Design.kt 的绘制代码按它渲染，不在调用点里 if 皮肤。
//
// 【为什么适配放在令牌而不是每个界面】界面代码只读令牌（Palette.Card 这类），
// 换皮肤 = 换令牌值；任何界面手写死色值都会在浅色皮肤上破——那是要逐个修的 bug，不是风格。
//
// 【持久化】settings.conf 的 app.skin 键（与 app.language 同一合并纪律：只动自己的键）。
package canopy.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** 阴影形态（namethatui 各风格的标志性立体感差异全在这里）。 */
enum class ShadowProfile {
    /** 无阴影（Fluent / 极简 / 粗野主义原始网页）。 */
    NONE,

    /** 双向软阴影（新拟态：左上亮、右下暗，同色系凸起）。 */
    SOFT_DUAL,

    /** 硬偏移阴影（新粗野主义：黑描边 + 无模糊的实心偏移块）。 */
    HARD_OFFSET,

    /** 大模糊软阴影（黏土拟态：胖乎乎的浮起）。 */
    PUFFY,

    /** 有色光晕（Y2K / 液态玻璃 / Aero：颜色外溢发光）。 */
    GLOW,
}

/** 背景装饰（窗口最底层的材质；页面与侧栏在其上透明或半透明）。 */
enum class BackdropKind {
    NONE,
    /** 玻璃拟态：深底上的彩色光斑壁纸。 */
    GLASS_WALLPAPER,
    /** 拟物：皮革 + 缝线。 */
    LEATHER,
    /** Y2K：铬银渐变 + 细网格。 */
    CHROME_GRID,
    /** Frutiger Aero：天空到草地 + 气泡。 */
    GRASS_BUBBLES,
    /** 远古网页：深蓝底 + 星星贴纸。 */
    GEO_STARS,
    /** Windows Aero：蓝色极光渐变。 */
    AERO_GRADIENT,
}

/** 一份完整的皮肤。颜色一一对应 Palette 的令牌槽。 */
data class Skin(
    val id: String,
    val titleZh: String,
    val titleEn: String,
    // 表面
    val bgBase: Color,
    val sidebar: Color,
    val card: Color,
    val cardHover: Color,
    val cardPressed: Color,
    val stroke: Color,
    val strokeHover: Color,
    val barTrack: Color,
    // 文字
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    // 语义
    val accent: Color,
    val onAccent: Color,
    val accentHover: Color,
    val shallow: Color,
    val deep: Color,
    val ai: Color,
    val green: Color,
    val yellow: Color,
    val amber: Color,
    val red: Color,
    // 渐变端点
    val heroTop: Color,
    val heroBottom: Color,
    val accentAlt: Color,
    val shallowAlt: Color,
    val deepAlt: Color,
    // 形态
    val radiusChip: Dp,
    val radiusControl: Dp,
    val radiusCard: Dp,
    val borderWidth: Dp = 1.dp,
    val shadow: ShadowProfile = ShadowProfile.NONE,
    val shadowDark: Color = Color(0x40000000),
    val shadowLight: Color = Color(0x40FFFFFF),
    val glowColor: Color = Color.Transparent,
    val gloss: Boolean = false,
    val glossStrength: Float = 0.16f,
    val backdrop: BackdropKind = BackdropKind.NONE,
)

private fun C(hex: Long) = Color(hex)

/** 全部皮肤（namethatui.com/styles 的 15 个风格，flat design 按用户要求除外；头一个是现行 Fluent）。 */
object Skins {
    private val fluent = Skin(
        id = "fluent", titleZh = "Fluent 暗色", titleEn = "Fluent Dark",
        bgBase = C(0xFF1F1F1F), sidebar = C(0xFF191919), card = C(0xFF292929), cardHover = C(0xFF303030),
        cardPressed = C(0xFF262626), stroke = C(0x14FFFFFF), strokeHover = C(0x24FFFFFF), barTrack = C(0xFF303030),
        textPrimary = C(0xFFFFFFFF), textSecondary = C(0xA8FFFFFF), textTertiary = C(0x87FFFFFF),
        accent = C(0xFF60CDFF), onAccent = C(0xFF1B1B1B), accentHover = C(0xFF48BDF2),
        shallow = C(0xFF6CCB5F), deep = C(0xFFB5A6FF), ai = C(0xFF4CD6E8),
        green = C(0xFF6CCB5F), yellow = C(0xFFFFD24A), amber = C(0xFFFFB35C), red = C(0xFFFF99A4),
        heroTop = C(0xFF2E2E2E), heroBottom = C(0xFF262626),
        accentAlt = C(0xFF9BDFFF), shallowAlt = C(0xFF9FE2A0), deepAlt = C(0xFFD0C8FF),
        radiusChip = 4.dp, radiusControl = 4.dp, radiusCard = 8.dp,
    )

    private val glass = Skin(
        id = "glass", titleZh = "玻璃拟态", titleEn = "Glassmorphism",
        bgBase = C(0xFF141225), sidebar = C(0x2EFFFFFF), card = C(0x26FFFFFF), cardHover = C(0x3DFFFFFF),
        cardPressed = C(0x1FFFFFFF), stroke = C(0x3DFFFFFF), strokeHover = C(0x59FFFFFF), barTrack = C(0x2EFFFFFF),
        textPrimary = C(0xFFFFFFFF), textSecondary = C(0xCCFFFFFF), textTertiary = C(0x99FFFFFF),
        accent = C(0xFF8AD8FF), onAccent = C(0xFF101828), accentHover = C(0xFFA8E4FF),
        shallow = C(0xFF8CFFCE), deep = C(0xFFD3C2FF), ai = C(0xFF8AE8FF),
        green = C(0xFF8CFFCE), yellow = C(0xFFFFE08A), amber = C(0xFFFFC98A), red = C(0xFFFFA3B8),
        heroTop = C(0x667C5CFF), heroBottom = C(0x33141225),
        accentAlt = C(0xFFB8E8FF), shallowAlt = C(0xFFB2FFDF), deepAlt = C(0xFFE6DBFF),
        radiusChip = 8.dp, radiusControl = 10.dp, radiusCard = 16.dp,
        shadow = ShadowProfile.GLOW, glowColor = C(0x33000000), backdrop = BackdropKind.GLASS_WALLPAPER,
    )

    private val liquid = Skin(
        id = "liquid", titleZh = "液态玻璃", titleEn = "Liquid Glass",
        bgBase = C(0xFF10131A), sidebar = C(0x24FFFFFF), card = C(0x1FFFFFFF), cardHover = C(0x38FFFFFF),
        cardPressed = C(0x17FFFFFF), stroke = C(0x4DFFFFFF), strokeHover = C(0x66FFFFFF), barTrack = C(0x24FFFFFF),
        textPrimary = C(0xFFFFFFFF), textSecondary = C(0xD6FFFFFF), textTertiary = C(0xA0FFFFFF),
        accent = C(0xFF4DA9FF), onAccent = C(0xFF071120), accentHover = C(0xFF73BDFF),
        shallow = C(0xFF38D97F), deep = C(0xFFB96AF2), ai = C(0xFF45C8FF),
        green = C(0xFF38D97F), yellow = C(0xFFFFD54A), amber = C(0xFFFFB35C), red = C(0xFFFF6B6B),
        heroTop = C(0x551E6DD8), heroBottom = C(0x3310131A),
        accentAlt = C(0xFF9ACDFF), shallowAlt = C(0xFF86E8B4), deepAlt = C(0xFFD2A6FF),
        radiusChip = 10.dp, radiusControl = 14.dp, radiusCard = 22.dp,
        shadow = ShadowProfile.GLOW, glowColor = C(0x406FA8FF), gloss = true, glossStrength = 0.24f,
        backdrop = BackdropKind.GLASS_WALLPAPER,
    )

    private val neumorphism = Skin(
        id = "neo", titleZh = "新拟态", titleEn = "Neumorphism",
        bgBase = C(0xFFE3E8F0), sidebar = C(0xFFDDE3EC), card = C(0xFFE3E8F0), cardHover = C(0xFFEAEFF5),
        cardPressed = C(0xFFD8DEE8), stroke = C(0xFFD3DAE4), strokeHover = C(0xFFC4CEDB), barTrack = C(0xFFD3DAE4),
        textPrimary = C(0xFF2B3440), textSecondary = C(0xFF5A6675), textTertiary = C(0xFF8A96A6),
        accent = C(0xFF5B7CFA), onAccent = C(0xFFFFFFFF), accentHover = C(0xFF4A6CE8),
        shallow = C(0xFF2FA46B), deep = C(0xFF7A5AF8), ai = C(0xFF18A0B7),
        green = C(0xFF2FA46B), yellow = C(0xFFD99A1C), amber = C(0xFFD97C1C), red = C(0xFFE5484D),
        heroTop = C(0xFFEAEFF6), heroBottom = C(0xFFE3E8F0),
        accentAlt = C(0xFF8AA2FF), shallowAlt = C(0xFF5FC491), deepAlt = C(0xFF9F8CFF),
        radiusChip = 8.dp, radiusControl = 12.dp, radiusCard = 16.dp,
        shadow = ShadowProfile.SOFT_DUAL, shadowDark = C(0xB1A3B1C6), shadowLight = C(0xC8FFFFFF),
    )

    private val clay = Skin(
        id = "clay", titleZh = "黏土拟态", titleEn = "Claymorphism",
        bgBase = C(0xFFE7E4F9), sidebar = C(0xFFDDD9F5), card = C(0xFFF4F2FF), cardHover = C(0xFFFAF9FF),
        cardPressed = C(0xFFE9E6FC), stroke = C(0xFFE2DEF8), strokeHover = C(0xFFD3CEF0), barTrack = C(0xFFDCD8F4),
        textPrimary = C(0xFF3A3A55), textSecondary = C(0xFF6A6A8A), textTertiary = C(0xFF9C9CB8),
        accent = C(0xFF7C6CF6), onAccent = C(0xFFFFFFFF), accentHover = C(0xFF6A59EC),
        shallow = C(0xFF4CC38A), deep = C(0xFF8E7CFF), ai = C(0xFF38BDF8),
        green = C(0xFF4CC38A), yellow = C(0xFFFFC24B), amber = C(0xFFFFA94D), red = C(0xFFF26D6D),
        heroTop = C(0xFFF0EEFF), heroBottom = C(0xFFE7E4F9),
        accentAlt = C(0xFFA39AFF), shallowAlt = C(0xFF7DD9AF), deepAlt = C(0xFFB2A6FF),
        radiusChip = 10.dp, radiusControl = 16.dp, radiusCard = 20.dp,
        shadow = ShadowProfile.PUFFY, shadowDark = C(0x80B7AFF0),
    )

    private val neobrutalism = Skin(
        id = "neobrutal", titleZh = "新粗野主义", titleEn = "Neobrutalism",
        bgBase = C(0xFFF5F0E8), sidebar = C(0xFFEDE6D8), card = C(0xFFFFFCF5), cardHover = C(0xFFFFF3D9),
        cardPressed = C(0xFFEFE6D4), stroke = C(0xFF111111), strokeHover = C(0xFF111111), barTrack = C(0xFFE4DCCB),
        textPrimary = C(0xFF111111), textSecondary = C(0xFF444444), textTertiary = C(0xFF777777),
        accent = C(0xFFFFC700), onAccent = C(0xFF111111), accentHover = C(0xFFFFD84D),
        shallow = C(0xFF4DE08A), deep = C(0xFF8E7CFF), ai = C(0xFF4AC6E8),
        green = C(0xFF4DE08A), yellow = C(0xFFFFC700), amber = C(0xFFFFA23E), red = C(0xFFFF5D5D),
        heroTop = C(0xFFFFF8E8), heroBottom = C(0xFFF5F0E8),
        accentAlt = C(0xFFFFDE66), shallowAlt = C(0xFF7DEBAA), deepAlt = C(0xFFAC9DFF),
        radiusChip = 0.dp, radiusControl = 0.dp, radiusCard = 0.dp, borderWidth = 2.dp,
        shadow = ShadowProfile.HARD_OFFSET, shadowDark = C(0xFF111111),
    )

    private val webBrutalism = Skin(
        id = "brutal", titleZh = "网页粗野主义", titleEn = "Web Brutalism",
        bgBase = C(0xFFFFFFFF), sidebar = C(0xFFD4D0C8), card = C(0xFFF0F0F0), cardHover = C(0xFFE4E4E4),
        cardPressed = C(0xFFDCDCDC), stroke = C(0xFF808080), strokeHover = C(0xFF4A4A4A), barTrack = C(0xFFC8C8C8),
        textPrimary = C(0xFF000000), textSecondary = C(0xFF333333), textTertiary = C(0xFF666666),
        accent = C(0xFF0000EE), onAccent = C(0xFFFFFFFF), accentHover = C(0xFF0000CC),
        shallow = C(0xFF008000), deep = C(0xFF800080), ai = C(0xFF008080),
        green = C(0xFF008000), yellow = C(0xFFB8860B), amber = C(0xFFCC7A00), red = C(0xFFCC0000),
        heroTop = C(0xFFFFFFFF), heroBottom = C(0xFFE8E8E8),
        accentAlt = C(0xFF5555FF), shallowAlt = C(0xFF33AA33), deepAlt = C(0xFFAA55AA),
        radiusChip = 0.dp, radiusControl = 0.dp, radiusCard = 0.dp,
    )

    private val y2k = Skin(
        id = "y2k", titleZh = "Y2K 千禧", titleEn = "Y2K Millennium",
        bgBase = C(0xFF0E0E16), sidebar = C(0xFF14141F), card = C(0xFF1C1C2A), cardHover = C(0xFF262638),
        cardPressed = C(0xFF181824), stroke = C(0xFF4A4A62), strokeHover = C(0xFF6A6A88), barTrack = C(0xFF26263A),
        textPrimary = C(0xFFF2F0FF), textSecondary = C(0xFFC4C0E0), textTertiary = C(0xFF9490BC),
        accent = C(0xFFFF6EC7), onAccent = C(0xFF1A0A16), accentHover = C(0xFFFF8FD4),
        shallow = C(0xFF6AE3FF), deep = C(0xFFB388FF), ai = C(0xFF7AF0FF),
        green = C(0xFF7DF9C6), yellow = C(0xFFFFE066), amber = C(0xFFFFC266), red = C(0xFFFF7A9E),
        heroTop = C(0xFF2A1E44), heroBottom = C(0xFF0E0E16),
        accentAlt = C(0xFFFF9EDB), shallowAlt = C(0xFF9AF0FF), deepAlt = C(0xFFCFB0FF),
        radiusChip = 10.dp, radiusControl = 14.dp, radiusCard = 18.dp,
        shadow = ShadowProfile.GLOW, glowColor = C(0x59FF6EC7), gloss = true, glossStrength = 0.20f,
        backdrop = BackdropKind.CHROME_GRID,
    )

    private val frutiger = Skin(
        id = "frutiger", titleZh = "Frutiger Aero", titleEn = "Frutiger Aero",
        bgBase = C(0xFFDFF3FB), sidebar = C(0xC9CBE9F7), card = C(0xD9FFFFFF), cardHover = C(0xE8FFFFFF),
        cardPressed = C(0xCCF2FAFD), stroke = C(0xFF9CC8DE), strokeHover = C(0xFF7FB4CE), barTrack = C(0xFFBFE0EE),
        textPrimary = C(0xFF123A4C), textSecondary = C(0xFF3D6B7E), textTertiary = C(0xFF6E97A8),
        accent = C(0xFF0EA45B), onAccent = C(0xFFFFFFFF), accentHover = C(0xFF0C8F4F),
        shallow = C(0xFF34C759), deep = C(0xFF2E9BC0), ai = C(0xFF00A8C8),
        green = C(0xFF34C759), yellow = C(0xFFF5B915), amber = C(0xFFF59A15), red = C(0xFFE5533C),
        heroTop = C(0xFF9AD9F2), heroBottom = C(0xFFCDEBD8),
        accentAlt = C(0xFF5BC98F), shallowAlt = C(0xFF6FD98F), deepAlt = C(0xFF6CC0DE),
        radiusChip = 6.dp, radiusControl = 10.dp, radiusCard = 14.dp,
        shadow = ShadowProfile.SOFT_DUAL, shadowDark = C(0x4A2E6B8A), shadowLight = C(0xB8FFFFFF),
        gloss = true, glossStrength = 0.30f, backdrop = BackdropKind.GRASS_BUBBLES,
    )

    private val skeuomorphism = Skin(
        id = "skeuo", titleZh = "拟物皮革", titleEn = "Skeuomorphism",
        bgBase = C(0xFF3E2B23), sidebar = C(0xFF33231C), card = C(0xFF4A352B), cardHover = C(0xFF563E31),
        cardPressed = C(0xFF423025), stroke = C(0xFF5E4536), strokeHover = C(0xFF75573F), barTrack = C(0xFF4A362B),
        textPrimary = C(0xFFF2E8D8), textSecondary = C(0xFFC9B79C), textTertiary = C(0xFF9A886F),
        accent = C(0xFFC9A227), onAccent = C(0xFF2B1D12), accentHover = C(0xFFDDB539),
        shallow = C(0xFF7FA86B), deep = C(0xFFA97C50), ai = C(0xFF8FAF6A),
        green = C(0xFF7FA86B), yellow = C(0xFFD9A441), amber = C(0xFFD99241), red = C(0xFFC0564A),
        heroTop = C(0xFF4A352B), heroBottom = C(0xFF33231C),
        accentAlt = C(0xFFE0BC4C), shallowAlt = C(0xFF9CC284), deepAlt = C(0xFFC2966B),
        radiusChip = 6.dp, radiusControl = 8.dp, radiusCard = 12.dp,
        shadow = ShadowProfile.SOFT_DUAL, shadowDark = C(0x8C1A100B), shadowLight = C(0x4D8A6F52),
        backdrop = BackdropKind.LEATHER,
    )

    private val vernacular = Skin(
        id = "vernacular", titleZh = "远古网页", titleEn = "Vernacular Web",
        bgBase = C(0xFF000066), sidebar = C(0xFF000044), card = C(0xFF28289E), cardHover = C(0xFF3434B4),
        cardPressed = C(0xFF20208A), stroke = C(0xFFC0C0C0), strokeHover = C(0xFFFFFFFF), barTrack = C(0xFF1A1A70),
        textPrimary = C(0xFFFFFFFF), textSecondary = C(0xFFCCCCCC), textTertiary = C(0xFF9999FF),
        accent = C(0xFF00FF00), onAccent = C(0xFF000000), accentHover = C(0xFF66FF66),
        shallow = C(0xFF00FF00), deep = C(0xFFFF00FF), ai = C(0xFF00FFFF),
        green = C(0xFF00FF00), yellow = C(0xFFFFFF00), amber = C(0xFFFFAA00), red = C(0xFFFF3333),
        heroTop = C(0xFF000099), heroBottom = C(0xFF000066),
        accentAlt = C(0xFF88FF88), shallowAlt = C(0xFF88FF88), deepAlt = C(0xFFFF88FF),
        radiusChip = 0.dp, radiusControl = 0.dp, radiusCard = 0.dp, borderWidth = 2.dp,
        backdrop = BackdropKind.GEO_STARS,
    )

    private val aqua = Skin(
        id = "aqua", titleZh = "Aqua 经典", titleEn = "Aqua (classic Mac)",
        bgBase = C(0xFFD6DCE8), sidebar = C(0xFFCCD4E4), card = C(0xFFEDF1F7), cardHover = C(0xFFF6F9FD),
        cardPressed = C(0xFFE2E8F2), stroke = C(0xFFA6B4CC), strokeHover = C(0xFF8CA0C0), barTrack = C(0xFFBFC9DC),
        textPrimary = C(0xFF1A2433), textSecondary = C(0xFF4A5A70), textTertiary = C(0xFF7A8AA0),
        accent = C(0xFF3B7EF0), onAccent = C(0xFFFFFFFF), accentHover = C(0xFF2E6CD8),
        shallow = C(0xFF34C759), deep = C(0xFF7D7AFF), ai = C(0xFF32ADE6),
        green = C(0xFF34C759), yellow = C(0xFFF5B915), amber = C(0xFFF59A15), red = C(0xFFFF3B30),
        heroTop = C(0xFFE8EDF6), heroBottom = C(0xFFD6DCE8),
        accentAlt = C(0xFF6FA6FF), shallowAlt = C(0xFF66D985), deepAlt = C(0xFFA3A3FF),
        radiusChip = 8.dp, radiusControl = 16.dp, radiusCard = 14.dp,
        shadow = ShadowProfile.SOFT_DUAL, shadowDark = C(0x52243752), shadowLight = C(0xD9FFFFFF),
        gloss = true, glossStrength = 0.42f,
    )

    private val aero = Skin(
        id = "aero", titleZh = "Windows Aero", titleEn = "Windows Aero",
        bgBase = C(0xFF16273E), sidebar = C(0x593D6EA0), card = C(0x3DFFFFFF), cardHover = C(0x59FFFFFF),
        cardPressed = C(0x2EFFFFFF), stroke = C(0x59FFFFFF), strokeHover = C(0x80FFFFFF), barTrack = C(0x40FFFFFF),
        textPrimary = C(0xFFFFFFFF), textSecondary = C(0xFFDCE9F7), textTertiary = C(0xFF9FB6CD),
        accent = C(0xFF5CB3F5), onAccent = C(0xFF0B2340), accentHover = C(0xFF7FC4FA),
        shallow = C(0xFF6BD68A), deep = C(0xFFB48CFF), ai = C(0xFF54C8E8),
        green = C(0xFF6BD68A), yellow = C(0xFFFFD257), amber = C(0xFFFFB35C), red = C(0xFFFF7A70),
        heroTop = C(0xFF2A4A75), heroBottom = C(0xFF16273E),
        accentAlt = C(0xFF8FCBFA), shallowAlt = C(0xFF96E2B0), deepAlt = C(0xFFCDB0FF),
        radiusChip = 6.dp, radiusControl = 8.dp, radiusCard = 10.dp,
        shadow = ShadowProfile.GLOW, glowColor = C(0x553D7EBB), gloss = true, glossStrength = 0.22f,
        backdrop = BackdropKind.AERO_GRADIENT,
    )

    private val minimal = Skin(
        id = "minimal", titleZh = "极简主义", titleEn = "Minimalism",
        bgBase = C(0xFFFFFFFF), sidebar = C(0xFFFAFAFA), card = C(0xFFFFFFFF), cardHover = C(0xFFF7F7F7),
        cardPressed = C(0xFFF2F2F2), stroke = C(0xFFECECEC), strokeHover = C(0xFFDADADA), barTrack = C(0xFFEEEEEE),
        textPrimary = C(0xFF111111), textSecondary = C(0xFF555555), textTertiary = C(0xFF999999),
        accent = C(0xFF111111), onAccent = C(0xFFFFFFFF), accentHover = C(0xFF333333),
        shallow = C(0xFF2E7D32), deep = C(0xFF5E35B1), ai = C(0xFF00838F),
        green = C(0xFF2E7D32), yellow = C(0xFFF9A825), amber = C(0xFFEF6C00), red = C(0xFFD32F2F),
        heroTop = C(0xFFFFFFFF), heroBottom = C(0xFFFAFAFA),
        accentAlt = C(0xFF444444), shallowAlt = C(0xFF55A567), deepAlt = C(0xFF8561C4),
        radiusChip = 4.dp, radiusControl = 6.dp, radiusCard = 6.dp,
    )

    /** id → 皮肤（restore 与设置页查找用）。 */
    val byId: Map<String, Skin> =
        listOf(fluent, glass, liquid, neumorphism, clay, neobrutalism, webBrutalism, y2k, frutiger,
            skeuomorphism, vernacular, aqua, aero, minimal).associateBy { it.id }

    val all: List<Skin> = byId.values.toList()
    const val DEFAULT_ID = "fluent"
    const val CONF_KEY = "app.skin"

    /** 当前皮肤（Compose 状态：apply 换它 ⇒ 全界面重组）。 */
    var current by mutableStateOf(fluent)
        private set

    /** 把一份皮肤写进全部令牌（Palette / Type / Radius / Material）。 */
    fun apply(skin: Skin) {
        current = skin
        Palette.BgBase = skin.bgBase
        Palette.Sidebar = skin.sidebar
        Palette.Card = skin.card
        Palette.CardHover = skin.cardHover
        Palette.CardPressed = skin.cardPressed
        Palette.Stroke = skin.stroke
        Palette.StrokeHover = skin.strokeHover
        Palette.BarTrack = skin.barTrack
        Palette.TextPrimary = skin.textPrimary
        Palette.TextSecondary = skin.textSecondary
        Palette.TextTertiary = skin.textTertiary
        Palette.Accent = skin.accent
        Palette.OnAccent = skin.onAccent
        Palette.AccentHover = skin.accentHover
        Palette.Shallow = skin.shallow
        Palette.Deep = skin.deep
        Palette.Ai = skin.ai
        Palette.Shallow = skin.green
        Palette.Yellow = skin.yellow
        Palette.Amber = skin.amber
        Palette.Red = skin.red
        Palette.HeroTop = skin.heroTop
        Palette.HeroBottom = skin.heroBottom
        Palette.AccentAlt = skin.accentAlt
        Palette.ShallowAlt = skin.shallowAlt
        Palette.DeepAlt = skin.deepAlt
        Type.display = Type.display.copy(color = skin.textPrimary)
        Type.title = Type.title.copy(color = skin.textPrimary)
        Type.section = Type.section.copy(color = skin.textPrimary)
        Type.card = Type.card.copy(color = skin.textPrimary)
        Type.body = Type.body.copy(color = skin.textPrimary)
        Type.label = Type.label.copy(color = skin.textSecondary)
        Type.micro = Type.micro.copy(color = skin.textTertiary)
        Radius.chip = skin.radiusChip
        Radius.control = skin.radiusControl
        Radius.card = skin.radiusCard
        Material.borderWidth = skin.borderWidth
        Material.shadow = skin.shadow
        Material.shadowDark = skin.shadowDark
        Material.shadowLight = skin.shadowLight
        Material.glowColor = skin.glowColor
        Material.gloss = skin.gloss
        Material.glossStrength = skin.glossStrength
        Material.backdrop = skin.backdrop
    }

    /** 应用并持久化；返回写 conf 的错误（null = 成功）。 */
    fun select(id: String): String? {
        val skin = byId[id] ?: return null
        apply(skin)
        return ConfStore.writeKey(CONF_KEY, id)
    }

    /** 启动时读 settings.conf（没配 / 坏值 / 未知 id = 默认 Fluent）。 */
    fun restore() {
        val text = ConfStore.read()
        val id = text.lines().mapNotNull { line ->
            val i = line.indexOf('=')
            if (i > 0) line.substringBefore('=').trim() to line.substringAfter('=', "").trim() else null
        }.toMap()[CONF_KEY] ?: return
        byId[id]?.let { apply(it) }
    }
}

/** 设计令牌里的「材质」档：描边宽度 / 阴影形态 / 光泽 / 背景装饰（换皮肤时由 Skins.apply 写入）。 */
object Material {
    var borderWidth by mutableStateOf(1.dp)
    var shadow by mutableStateOf(ShadowProfile.NONE)
    var shadowDark by mutableStateOf(Color(0x40000000))
    var shadowLight by mutableStateOf(Color(0x40FFFFFF))
    var glowColor by mutableStateOf(Color.Transparent)
    var gloss by mutableStateOf(false)
    var glossStrength by mutableStateOf(0.16f)
    var backdrop by mutableStateOf(BackdropKind.NONE)
}

// ── 绘制辅助（Buttons.kt 与卡片容器共用；按 Material 令牌渲染，调用点不 if 皮肤）──

/** 深浅底上都读得清的前景色：亮底给近黑、暗底给白（namethatui 的 token 思路：对比度优先）。 */
fun readableOn(c: Color): Color = if (c.luminance() > 0.55f) Color(0xFF111111) else Color(0xFFFFFFFF)

/**
 * 皮肤阴影：画在本元素后面（drawBehind 在链上放在 clip/background 之前）。
 * [pressedAt] = 硬偏移阴影在按下时把内容挪进阴影里，绘制侧据此把阴影收掉。
 */
fun Modifier.skinShadow(radius: Dp, pressedAt: Boolean = false): Modifier =
    drawBehind {
        val r = CornerRadius(radius.toPx(), radius.toPx())
        when (Material.shadow) {
            ShadowProfile.NONE -> {}
            ShadowProfile.HARD_OFFSET -> if (!pressedAt) {
                drawRoundRect(Material.shadowDark, topLeft = Offset(3.dp.toPx(), 3.dp.toPx()),
                    size = Size(size.width, size.height), cornerRadius = r)
            }
            ShadowProfile.SOFT_DUAL -> {
                drawRoundRect(Material.shadowDark, topLeft = Offset(2.5f.dp.toPx(), 2.5f.dp.toPx()),
                    size = Size(size.width, size.height), cornerRadius = r)
                drawRoundRect(Material.shadowLight, topLeft = Offset(-2.5f.dp.toPx(), -2.5f.dp.toPx()),
                    size = Size(size.width, size.height), cornerRadius = r)
            }
            ShadowProfile.PUFFY -> for (i in 1..5) {
                val grow = i * 3f.dp.toPx()
                drawRoundRect(Material.shadowDark.copy(alpha = Material.shadowDark.alpha * (1f - i * 0.16f)),
                    topLeft = Offset(-grow, -grow + 2f.dp.toPx()),
                    size = Size(size.width + grow * 2, size.height + grow * 2),
                    cornerRadius = CornerRadius(r.x + grow, r.y + grow))
            }
            ShadowProfile.GLOW -> for (i in 1..4) {
                val grow = i * 2.5f.dp.toPx()
                drawRoundRect(Material.glowColor.copy(alpha = Material.glowColor.alpha * (1f - i * 0.18f)),
                    topLeft = Offset(-grow, -grow), size = Size(size.width + grow * 2, size.height + grow * 2),
                    cornerRadius = CornerRadius(r.x + grow, r.y + grow))
            }
        }
    }

/** 顶部光泽（Aqua 糖果 / Frutiger 高光 / Y2K 铬银）：链上放在 background 之后、内容之前。 */
fun Modifier.skinGloss(radius: Dp): Modifier = if (!Material.gloss) this else drawBehind {
    val g = Brush.verticalGradient(
        0f to Color.White.copy(alpha = Material.glossStrength),
        0.55f to Color.Transparent,
    )
    drawRoundRect(brush = g, topLeft = Offset.Zero, size = size, cornerRadius = CornerRadius(radius.toPx(), radius.toPx()))
}

/** 窗口最底层的材质装饰（Main.kt 在外壳 Row 后面画）。 */
@Composable
fun SkinBackdrop(modifier: Modifier = Modifier) {
    androidx.compose.foundation.layout.Box(modifier.background(Palette.BgBase).drawBehind {
        when (Material.backdrop) {
            BackdropKind.NONE -> {}
            BackdropKind.GLASS_WALLPAPER, BackdropKind.AERO_GRADIENT -> {
                val blobs = if (Material.backdrop == BackdropKind.GLASS_WALLPAPER) {
                    listOf(Triple(0.22f, 0.18f, Color(0xFF7C5CFF)), Triple(0.78f, 0.30f, Color(0xFF3AB6E8)), Triple(0.60f, 0.86f, Color(0xFFFF6BD6)))
                } else {
                    listOf(Triple(0.30f, 0.16f, Color(0xFF3D7EBB)), Triple(0.74f, 0.42f, Color(0xFF1E4E8A)), Triple(0.52f, 0.88f, Color(0xFF14406B)))
                }
                blobs.forEach { (fx, fy, c) ->
                    drawCircle(Brush.radialGradient(listOf(c.copy(alpha = 0.26f), Color.Transparent)),
                        radius = maxOf(size.width, size.height) * 0.30f, center = Offset(size.width * fx, size.height * fy))
                }
            }
            BackdropKind.LEATHER -> {
                drawRect(Brush.verticalGradient(listOf(Color(0xFF442F26), Color(0xFF2A1B14))))
                // 缝线：内缩一圈的虚线圆角框
                val inset = 14f.dp.toPx()
                drawRoundRect(
                    color = Color(0x66C9A227), topLeft = Offset(inset, inset),
                    size = Size(size.width - inset * 2, size.height - inset * 2),
                    cornerRadius = CornerRadius(18f.dp.toPx()), style = Stroke(width = 1.5f.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 8f))),
                )
            }
            BackdropKind.CHROME_GRID -> {
                drawRect(Brush.verticalGradient(listOf(Color(0xFF2A2A44), Color(0xFF0E0E16))))
                val step = 28f.dp.toPx()
                var x = step; while (x < size.width) { drawLine(Color(0x14FFFFFF), Offset(x, 0f), Offset(x, size.height)); x += step }
                var y = step; while (y < size.height) { drawLine(Color(0x14FFFFFF), Offset(0f, y), Offset(size.width, y)); y += step }
                drawRect(Brush.verticalGradient(listOf(Color(0x3DC0C6D4), Color(0x00C0C6D4))),
                    topLeft = Offset.Zero, size = Size(size.width, size.height * 0.12f))
            }
            BackdropKind.GRASS_BUBBLES -> {
                drawRect(Brush.verticalGradient(0f to Color(0xFF8ED0F5), 0.62f to Color(0xFFC8E9F8), 0.78f to Color(0xFFBFE8C8), 1f to Color(0xFF8FD08F)))
                // 气泡：固定伪随机位置的一圈白圈
                val stars = listOf(0.12f to 0.30f, 0.30f to 0.16f, 0.52f to 0.36f, 0.72f to 0.20f, 0.88f to 0.46f, 0.42f to 0.58f, 0.66f to 0.66f)
                stars.forEachIndexed { i, (fx, fy) ->
                    val r = (6 + (i * 7) % 16) * 1f.dp.toPx()
                    drawCircle(Color(0x40FFFFFF), radius = r, center = Offset(size.width * fx, size.height * fy))
                    drawCircle(Color(0x66FFFFFF), radius = r, center = Offset(size.width * fx, size.height * fy), style = Stroke(1.2f.dp.toPx()))
                }
            }
            BackdropKind.GEO_STARS -> {
                drawRect(Color(0xFF000066))
                val colors = listOf(Color(0xFFFFFF66), Color(0xFF66FFFF), Color(0xFFFF66CC), Color(0xFF66FF66))
                for (i in 0 until 64) {
                    val fx = ((i * 127) % 97) / 97f
                    val fy = ((i * 211) % 89) / 89f
                    val cx = size.width * (0.02f + fx * 0.96f)
                    val cy = size.height * (0.02f + fy * 0.96f)
                    val r = 3f.dp.toPx() + (i % 3) * 1f.dp.toPx()
                    drawLine(colors[i % colors.size], Offset(cx - r, cy), Offset(cx + r, cy), strokeWidth = 1.4f.dp.toPx())
                    drawLine(colors[i % colors.size], Offset(cx, cy - r), Offset(cx, cy + r), strokeWidth = 1.4f.dp.toPx())
                }
            }
        }
    })
}
