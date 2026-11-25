// Design.kt —— Fluent Design 设计系统（用户定稿：完全的 Fluent 美学；WinUI 3 暗色域）。
//
// 【分层纪律】Mica 质感不透明底 + 白 alpha 分层表面（Fluent Layer：静 4%/hover 6%/press 3% 白），
//   描边一律白 alpha hairline；不再使用多色大渐变（Fluent 不用张扬渐变）。
// 【圆角三档】chip 4 / control 4 / card 8（Fluent overlay 8）。
// 【文字】白三级：primary 100% / secondary 66% / tertiary 45%。
// 【动效】150ms 常规 / 300ms 浮层（Motion 令牌；曲线用默认减速近似 Fluent decelerate）。

package deepdolphin.ui

import androidx.compose.material3.PlainTooltip

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.VerticalScrollbar
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.ScrollbarStyle
import androidx.compose.foundation.rememberScrollbarAdapter
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier

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

    // ── 文字三级（白 100/66/53%）──
    // 三级文字按 53% 定：原来 45% 在卡片底（#292929）上只有 4.2:1，不到正文 4.5:1 的底线；
    // 提到 53% 后在底/卡片/侧栏三种底色上都 ≥ 5:1（次级 66% 约 7.9:1）。
    val TextPrimary = Color(0xFFFFFFFF)
    val TextSecondary = Color(0xA8FFFFFF)
    val TextTertiary = Color(0x87FFFFFF)

    // ── 强调与双轨（Fluent 暗色 accent 亮蓝 + 语义轨道色按暗底提亮）──
    /** Fluent 暗色主题 accent（#60CDFF）。 */
    val Accent = Color(0xFF60CDFF)
    /** accent 上的文字（Fluent 暗色 accent 亮，配近黑文字）。 */
    val OnAccent = Color(0xFF1B1B1B)
    /** accent 按钮 hover（比 accent 深一档）。 */
    val AccentHover = Color(0xFF48BDF2)
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
    // 行高按 Fluent 2 排版（Body 14/20、Caption 12/16、Subtitle 16/22、Title 20/28）：
    // 多行正文与说明文字靠它拉开行距；此前不带行高，密排的说明读起来糊成一片
    val display = TextStyle(fontSize = 28.sp, lineHeight = 36.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    val title = TextStyle(fontSize = 20.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    val section = TextStyle(fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    val card = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    val body = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, color = Palette.TextPrimary)
    val label = TextStyle(fontSize = 12.sp, lineHeight = 16.sp, color = Palette.TextSecondary)
    val micro = TextStyle(fontSize = 11.sp, lineHeight = 14.sp, color = Palette.TextTertiary)
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

// ── Material 根主题（所有没显式配色的 Material 组件的唯一缺省来源）──
// 二次验证抓到：应用根上没包 MaterialTheme，Switch / 输入框描边 / 菜单等回落到 M3 默认**浅色**方案，
// 在暗色界面上突兀。暗色方案从上面的 Fluent 令牌派生，组件不内联色值。

/** Fluent 暗色方案（Material3 组件缺省配色的唯一来源）。 */
fun fluentColorScheme(): androidx.compose.material3.ColorScheme =
    androidx.compose.material3.darkColorScheme(
        primary = Palette.Accent, onPrimary = Palette.OnAccent,
        primaryContainer = Palette.Accent.copy(alpha = 0.16f), onPrimaryContainer = Palette.Accent,
        inversePrimary = Palette.AccentAlt,
        secondary = Palette.Deep, onSecondary = Palette.BgBase,
        secondaryContainer = Palette.Deep.copy(alpha = 0.16f), onSecondaryContainer = Palette.Deep,
        tertiary = Palette.Ai, onTertiary = Palette.BgBase,
        tertiaryContainer = Palette.Ai.copy(alpha = 0.16f), onTertiaryContainer = Palette.Ai,
        background = Palette.BgBase, onBackground = Palette.TextPrimary,
        surface = Palette.Card, onSurface = Palette.TextPrimary,
        surfaceVariant = Palette.CardHover, onSurfaceVariant = Palette.TextSecondary,
        surfaceTint = Color.Transparent,
        inverseSurface = Palette.TextPrimary, inverseOnSurface = Palette.BgBase,
        outline = Palette.StrokeHover, outlineVariant = Palette.Stroke,
        error = Palette.Red, onError = Palette.BgBase,
        errorContainer = Palette.Red.copy(alpha = 0.16f), onErrorContainer = Palette.Red,
        surfaceBright = Palette.CardHover, surfaceDim = Palette.BgBase,
        surfaceContainerLowest = Palette.Sidebar, surfaceContainerLow = Palette.BgBase,
        surfaceContainer = Palette.Card, surfaceContainerHigh = Palette.CardHover,
        surfaceContainerHighest = Palette.CardHover,
    )

/** Fluent 圆角档映射到 Material 形状档。 */
val FluentShapes = androidx.compose.material3.Shapes(
    extraSmall = androidx.compose.foundation.shape.RoundedCornerShape(Radius.chip),
    small = androidx.compose.foundation.shape.RoundedCornerShape(Radius.chip),
    medium = androidx.compose.foundation.shape.RoundedCornerShape(Radius.control),
    large = androidx.compose.foundation.shape.RoundedCornerShape(Radius.card),
    extraLarge = androidx.compose.foundation.shape.RoundedCornerShape(Radius.card),
)

/** Fluent 字阶映射到 Material 字体档（与 Type 的字号一致）。 */
val FluentTypography = androidx.compose.material3.Typography(
    labelSmall = androidx.compose.ui.text.TextStyle(fontSize = 11.sp, color = Palette.TextTertiary),
    labelMedium = androidx.compose.ui.text.TextStyle(fontSize = 12.sp, color = Palette.TextSecondary),
    labelLarge = androidx.compose.ui.text.TextStyle(fontSize = 14.sp, color = Palette.TextPrimary),
    bodySmall = androidx.compose.ui.text.TextStyle(fontSize = 12.sp, color = Palette.TextSecondary),
    bodyMedium = androidx.compose.ui.text.TextStyle(fontSize = 14.sp, color = Palette.TextPrimary),
    bodyLarge = androidx.compose.ui.text.TextStyle(fontSize = 16.sp, color = Palette.TextPrimary),
    titleMedium = androidx.compose.ui.text.TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary),
    titleLarge = androidx.compose.ui.text.TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary),
)

/** Fluent 开关配色（开 = accent 轨 + 近黑钮；关 = hairline 轨）。 */
@androidx.compose.runtime.Composable
fun fluentSwitchColors() = androidx.compose.material3.SwitchDefaults.colors(
    checkedTrackColor = Palette.Accent,
    checkedThumbColor = Palette.OnAccent,
    checkedBorderColor = Color.Transparent,
    uncheckedTrackColor = Palette.StrokeHover,
    uncheckedThumbColor = Palette.TextSecondary,
    uncheckedBorderColor = Color.Transparent,
)

/** Fluent 文本框配色（hairline 描边，聚焦 accent）。 */
@androidx.compose.runtime.Composable
fun fluentTextFieldColors() = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
    focusedBorderColor = Palette.Accent,
    unfocusedBorderColor = Palette.StrokeHover,
    errorBorderColor = Palette.Red,
    focusedLabelColor = Palette.Accent,
    unfocusedLabelColor = Palette.TextSecondary,
    cursorColor = Palette.Accent,
    focusedTextColor = Palette.TextPrimary,
    unfocusedTextColor = Palette.TextPrimary,
    focusedPlaceholderColor = Palette.TextTertiary,
    unfocusedPlaceholderColor = Palette.TextTertiary,
)

/** 悬停提示（mac .help 的对位）：把口径/帮助文案挂在控件上，不占版面。 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@androidx.compose.runtime.Composable
fun HelpTooltip(text: String, content: @androidx.compose.runtime.Composable () -> Unit) {
    androidx.compose.material3.TooltipBox(
        positionProvider = androidx.compose.material3.TooltipDefaults.rememberPlainTooltipPositionProvider(),
        tooltip = {
            // PlainTooltip / RichTooltip 是 TooltipBoxScope 的成员（material3 1.3）
            PlainTooltip(containerColor = Palette.CardHover, contentColor = Palette.TextPrimary) {
                androidx.compose.material3.Text(text, style = Type.label)
            }
        },
        state = androidx.compose.material3.rememberTooltipState(),
        content = { content() },
    )
}

// ── 滚动条（Fluent：细、贴右缘、静止低对比、hover 提亮）──
//
// 【为什么要有滚动条】原来所有可滚动区都是「裸滚」：内容超出视口时界面上没有任何提示，
// 用户不知道下面还有东西，也不知道自己在长页面的什么位置。Compose Desktop 的滚动条
// 需要显式挂——这里给两套容器把它收进来，页面代码只换一个函数名。

/** 滚动条样式。 */
@Composable
private fun scrollbarLook() = ScrollbarStyle(
    minimalHeight = 24.dp,
    thickness = 6.dp,
    shape = RoundedCornerShape(3.dp),
    hoverDurationMillis = Motion.normal,
    unhoverColor = Palette.Stroke,
    hoverColor = Palette.StrokeHover,
)

/**
 * 带滚动条的纵向滚动列。[modifier] 给外层容器（weight / fillMaxSize 这类），
 * [contentPadding] 是内容内边距（滚动条贴在内容区的最右缘，不被内边距挤进来）。
 */
@Composable
fun ScrollColumn(
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(),
    verticalArrangement: Arrangement.Vertical = Arrangement.Top,
    content: @Composable ColumnScope.() -> Unit,
) {
    val state = rememberScrollState()
    Box(modifier) {
        Column(
            Modifier.fillMaxSize().verticalScroll(state).padding(contentPadding),
            verticalArrangement = verticalArrangement,
            content = content,
        )
        VerticalScrollbar(
            modifier = Modifier.align(Alignment.CenterEnd).fillMaxHeight(),
            adapter = rememberScrollbarAdapter(state),
            style = scrollbarLook(),
        )
    }
}

/** 带滚动条的 LazyColumn（语义同 [ScrollColumn]；list 的内容用 LazyListScope 发条目）。 */
@Composable
fun ScrollLazyColumn(
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(),
    verticalArrangement: Arrangement.Vertical = Arrangement.Top,
    content: LazyListScope.() -> Unit,
) {
    val state = rememberLazyListState()
    Box(modifier) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = state,
            contentPadding = contentPadding,
            verticalArrangement = verticalArrangement,
            content = content,
        )
        VerticalScrollbar(
            modifier = Modifier.align(Alignment.CenterEnd).fillMaxHeight(),
            adapter = rememberScrollbarAdapter(state),
            style = scrollbarLook(),
        )
    }
}
