// Design.kt —— Fluent Design 设计系统（用户定稿：完全的 Fluent 美学；WinUI 3 暗色域）。
//
// 【分层纪律】Mica 质感不透明底 + 白 alpha 分层表面（Fluent Layer：静 4%/hover 6%/press 3% 白），
//   描边一律白 alpha hairline；不再使用多色大渐变（Fluent 不用张扬渐变）。
// 【圆角三档】chip 4 / control 4 / card 8（Fluent overlay 8）。
// 【文字】白三级：primary 100% / secondary 66% / tertiary 45%。
// 【动效】150ms 常规 / 300ms 浮层（Motion 令牌；曲线用默认减速近似 Fluent decelerate）。

package deepdolphin.ui

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ── Fluent 暗色表面（SolidBackgroundFillColorBase / LayerFillColorDefault / NavigationView pane）──
object Palette {
    /** 页面底（Mica 质感不透明近似 #1F1F1F）。 */
    val BgBase = Color(0xFF1F1F1F)
    /** 卡片分层（LayerFillColorDefault 暗色近似：底上叠 ~4% 白）。 */
    val Card = Color(0xFF292929)
    /** 卡片 hover（~6% 白，Fluent reveal）。 */
    val CardHover = Color(0xFF303030)
    /** 按压缩暗（~3% 白）。 */
    val CardPressed = Color(0xFF262626)
    /** 侧栏底（NavigationView pane：比底更暗一档）。 */
    val Sidebar = Color(0xFF191919)
    /** hairline 描边（白 8%）。 */
    val Stroke = Color(0x14FFFFFF)
    /** hover 描边（白 14%）。 */
    val StrokeHover = Color(0x24FFFFFF)
    /** 语言分布条底轨。 */
    val BarTrack = Color(0xFF303030)

    // ── 文字三级（白 100/66/45%）──
    val TextPrimary = Color(0xFFFFFFFF)
    val TextSecondary = Color(0xA8FFFFFF)
    val TextTertiary = Color(0x73FFFFFF)

    // ── 强调与双轨（Fluent 暗色 accent 亮蓝 + 语义轨道色按暗底提亮）──
    /** Fluent 暗色主题 accent（#60CDFF）。 */
    val Accent = Color(0xFF60CDFF)
    /** accent 上的文字（Fluent 暗色 accent 亮，配近黑文字）。 */
    val OnAccent = Color(0xFF1B1B1B)
    val Shallow = Color(0xFF6CCB5F)  // 绿 · 浅更新（暗底提亮）
    val Deep = Color(0xFFB5A6FF)     // 紫 · 深更新（暗底提亮）
    val Ai = Color(0xFF4CD6E8)       // 青 · AI（暗底提亮）

    // ── 状态 ──
    val Green = Shallow
    val Yellow = Color(0xFFFFD24A)
    val Amber = Color(0xFFFFB35C)
    val Red = Color(0xFFFF99A4)

    // ── hero（安静 Fluent 头：分层底纵向微渐变，无多色）──
    val HeroTop = Color(0xFF2E2E2E)
    val HeroBottom = Color(0xFF262626)
    val ShallowAlt = Color(0xFF9FE2A0)
    val DeepAlt = Color(0xFFD0C8FF)
    val AccentAlt = Color(0xFF9BDFFF)

    // ── 旧引用兼容（视图用名 → Fluent 语义）──
    val BgDeep = Sidebar
    val GreenTextDark = Shallow
    val AmberTextDark = Amber
    val RedTextDark = Red
    val Purple = Deep
    val HeroIndigo = HeroTop
    val HeroViolet = HeroTop
    val HeroCyan = HeroBottom
    val StrokeHoverLegacy = StrokeHover
}

/** 字号档位（Fluent ramp：caption 12 / body 14 / subtitle 16 / title 20 / display 28）。 */
object Type {
    val display = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    val title = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    val section = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    val card = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    val body = TextStyle(fontSize = 14.sp, color = Palette.TextPrimary)
    val label = TextStyle(fontSize = 12.sp, color = Palette.TextSecondary)
    val micro = TextStyle(fontSize = 11.sp, color = Palette.TextTertiary)
}

/** 间距刻度 4/8/12/16/20/24（8 网格）。 */
object Space {
    val xs = 4.dp; val sm = 8.dp; val md = 12.dp; val lg = 16.dp; val xl = 20.dp; val xxl = 24.dp
}

/** 圆角三档（Fluent：control 4 / card 8 / overlay 8）。 */
object Radius {
    val chip = 4.dp; val control = 4.dp; val card = 8.dp
}

/** 动效时长（Fluent：常规 150ms / 浮层 300ms）。 */
object Motion {
    const val normal = 150
    const val slow = 300
}

/** 提交构成序列色（12 类穷举、不取模；Fluent 暗底域）。 */
val Composition12 = listOf(
    Color(0xFF60CDFF), // accent blue
    Color(0xFFFF99A4), // red
    Color(0xFFFFB35C), // orange
    Color(0xFFB5A6FF), // purple
    Color(0xFF4DD0C4), // teal
    Color(0xFF9AA8FF), // indigo
    Color(0xFF6CCB5F), // green
    Color(0xFFFF9FD6), // pink
    Color(0xFFC99A6B), // brown
    Color(0xFFFFD24A), // yellow
    Color(0xFF4CD6E8), // cyan
    Color(0xFF9E9E9E), // gray
)

// ── 渐变：只做安静分层（hero 纵向微渐变）与同语义深→亮 ──

/** hero 端点（安静 Fluent 头：分层底顶 → 底）。 */
fun heroStops(): List<Color> = listOf(Palette.HeroTop, Palette.HeroBottom)

/** hero 页头纵向微渐变（纯函数可单测）。 */
fun heroBrushDiagonal(): Brush = Brush.verticalGradient(heroStops())

/** 语义色内部深→亮（同语义 Alt，不拼第二种语义）。 */
fun semanticBrush(head: Color, alt: Color): Brush = Brush.linearGradient(listOf(head, alt))

fun shallowBrush(): Brush = semanticBrush(Palette.Shallow, Palette.ShallowAlt)
fun deepBrush(): Brush = semanticBrush(Palette.Deep, Palette.DeepAlt)
fun aiBrush(): Brush = semanticBrush(Palette.Ai, Palette.AccentAlt)
fun accentBrush(): Brush = semanticBrush(Palette.Accent, Palette.AccentAlt)
