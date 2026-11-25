// Icons.kt —— 图标体系（Fluent System Icons）。按钮见 Buttons.kt。
//
// 【为什么】此前界面拿 Unicode 字形充当图标（⌕ ✓ ⚠ × ← ▾ ◈ ▦ ☑ …）：不同字体回退到不同字形，
// 粗细、基线、视觉大小都不一致，导航项则干脆没有图标。换成一套真正的图标字体——微软官方的
// Fluent System Icons（MIT），同一笔画粗细、同一网格，正是 Fluent 的原生图标语言。
// 字体随应用打包（src/jvmMain/resources/fonts/），码点取自官方同仓的 FluentSystemIcons-Regular.json；
// 只收 Regular——选中态靠着色表达，不换 Filled 字重（省一半体积）。
//
// 【绘制】字体的 em 框就是设计框（unitsPerEm 500 = 上伸 500 / 下伸 0）：把基线画在盒子底边、
// 左缘贴 0，字形就恰好充满 size 见方。这个 Compose 版本没有按文件加载字体的公开接口，
// 所以用 Java2D 把每个字形按**实际像素边长**渲染成白色位图并缓存，显示时着色：同步可得，
// 不依赖字体解析器的异步加载，高分屏下也按真实像素渲染而不发虚。

package deepdolphin.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.takeOrElse
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.roundToInt

/**
 * 用到的图标（码点来自官方码点表；20 号字形按 16–24dp 用，16 号字形给 14dp 以下用）。
 * 名字对位官方 `ic_fluent_<name>_<size>_regular`，查表/增补都以它为准。
 */
enum class FluentIcon(val code: Int) {
    // 导航与入口
    Home(0xF480),
    Board(0xE156),
    Target(0xF781),
    ShieldCheckmark(0xEAC8),
    Stethoscope(0xF724),
    Settings(0xF6A9),
    Search(0xF68F),
    Folder(0xF418),
    FolderOpen(0xF42E),
    FolderAdd(0xF41C),
    FolderProhibited(0xE65C),

    // 动作
    ArrowSync(0xF190),
    ArrowLeft(0xF15B),
    ArrowRight(0xF181),
    Dismiss(0xF368),
    Add(0xF109),
    ChevronDown(0xF2A2),
    ChevronRight(0xF2AF),
    ChevronUp(0xF2B5),
    Checkmark(0xE305),
    Warning(0xF868),
    Info(0xF4A2),
    ErrorCircle(0xF3F0),
    Delete(0xF34C),
    Edit(0xF3DD),
    Copy(0xF32B),
    Open(0xF582),
    Play(0xF605),
    Pause(0xF5A1),
    Stop(0xF72A),
    Power(0xF60E),
    Scan(0xEA54),

    // 图谱两页
    DataHistogram(0xF342),
    Organization(0xF58A),
    Flowchart(0xE639),
    BranchFork(0xE1DF),

    // 语义
    Sparkle(0xEB33),
    ChatHelp(0xF220),
    History(0xF47E),
    Clock(0xF2DD),
    Calendar(0xE24E),
    CheckmarkCircle(0xF297),
    DismissCircle(0xF36C),
    QuestionCircle(0xF63C),
    Circle(0xF2BA),
    Trophy(0xF835),
    TaskList(0xEC99),
    DocumentText(0xE557),
    DocumentCheckmark(0xE4F1),
    PeopleTeam(0xF5B8),
    Flag(0xF40B),
    FlagOff(0xE616),
    Lightbulb(0xF4D6),
    LocalLanguage(0xF4F3),
    Bot(0xE1B8),
    Key(0xF4B6),
    Link(0xF4E4),
    Timer(0xED88),
    Globe(0xF45A),
    Rocket(0xF677),
    CheckboxChecked(0xF27C),
    CheckboxUnchecked(0xF290),
}

private val FluentIcon.character: Char get() = code.toChar()

/** 字形位图缓存：键 = 图标 × 像素边长。白色字形 + 透明底，着色交给显示层。 */
private object GlyphBitmaps {
    private const val FONT_PATH = "/fonts/FluentSystemIcons-Regular.ttf"

    private val baseFont: java.awt.Font by lazy {
        val stream = GlyphBitmaps::class.java.getResourceAsStream(FONT_PATH)
            ?: error("图标字体缺失：$FONT_PATH（应随应用打包在 resources/fonts/）")
        java.awt.Font.createFont(java.awt.Font.TRUETYPE_FONT, stream)
    }

    private val cache = ConcurrentHashMap<Pair<FluentIcon, Int>, ImageBitmap>()

    fun get(icon: FluentIcon, sidePx: Int): ImageBitmap = cache.getOrPut(icon to sidePx) {
        val image = BufferedImage(sidePx, sidePx, BufferedImage.TYPE_INT_ARGB)
        val g = image.createGraphics()
        try {
            g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
            g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON)
            g.setRenderingHint(RenderingHints.KEY_FRACTIONALMETRICS, RenderingHints.VALUE_FRACTIONALMETRICS_OFF)
            g.font = baseFont.deriveFont(sidePx.toFloat())
            g.color = java.awt.Color.WHITE
            // em 框即设计框：基线落在盒子底边，x 从 0 起
            g.drawString(icon.character.toString(), 0, sidePx)
        } finally {
            g.dispose()
        }
        image.toComposeImageBitmap()
    }
}

/**
 * 一枚图标：[size] 见方。按**实际像素边长**渲染并缓存位图（2x 缩放下取 2x 位图，不发虚），
 * 以 [tint] 着色；未指定 tint 时取 [Palette.TextSecondary]。contentDescription 留空——
 * 图标旁边的文字已经是它的名字；纯图标按钮由调用方给工具提示。
 */
@Composable
fun IconBox(
    icon: FluentIcon,
    modifier: Modifier = Modifier,
    size: Dp = 20.dp,
    tint: Color = Color.Unspecified,
) {
    val sidePx = with(LocalDensity.current) { size.roundToPx() }.coerceAtLeast(1)
    val bitmap = remember(icon, sidePx) { GlyphBitmaps.get(icon, sidePx) }
    Image(
        bitmap = bitmap,
        contentDescription = null,
        modifier = modifier.size(size),
        colorFilter = ColorFilter.tint(tint.takeOrElse { Palette.TextSecondary }),
    )
}
