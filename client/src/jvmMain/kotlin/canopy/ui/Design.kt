// Design.kt —— Fluent Design 设计系统（用户定稿：完全的 Fluent 美学；WinUI 3 暗色域）。
//
// 【分层纪律】Mica 质感不透明底 + 白 alpha 分层表面（Fluent Layer：静 4%/hover 6%/press 3% 白），
//   描边一律白 alpha hairline；不再使用多色大渐变（Fluent 不用张扬渐变）。
// 【圆角三档】chip 4 / control 4 / card 8（Fluent overlay 8）。
// 【文字】白三级：primary 100% / secondary 66% / tertiary 45%。
// 【动效】150ms 常规 / 300ms 浮层（Motion 令牌；曲线用默认减速近似 Fluent decelerate）。
// 【姿态原语】骨架占位 / 焦点环 / 悬停抬升 / 截断文本 / 徽章胶囊是三个区域共用的「姿态」层：
//   只定形状与动效，颜色一律读令牌（骨架微光 CardHover/StrokeHover、焦点环 accent、悬停提亮 CardHover），
//   不出现硬编码深底色——换肤（Skins.apply 写令牌）即全量换姿态外观；无限动画有总开关（Motion.animate）。

package canopy.ui

import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Text

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.VerticalScrollbar
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.ScrollbarStyle
import androidx.compose.foundation.rememberScrollbarAdapter
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.onFocusEvent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ── Fluent 暗色表面（SolidBackgroundFillColorBase / LayerFillColorDefault / NavigationView pane）──
object Palette {
    /** 页面底（Mica 质感不透明近似 #1F1F1F）。 */
    var BgBase by mutableStateOf(Color(0xFF1F1F1F))
    /** 卡片分层（LayerFillColorDefault 暗色近似：底上叠 ~4% 白）。 */
    var Card by mutableStateOf(Color(0xFF292929))
    /** 卡片 hover（~6% 白，Fluent reveal）。 */
    var CardHover by mutableStateOf(Color(0xFF303030))
    /** 按压缩暗（~3% 白）。 */
    var CardPressed by mutableStateOf(Color(0xFF262626))
    /** 卡内凹槽（披露条 / 疑点行 / 信号 chip 的底）：比卡再退一档。不在这里改 Card 的透明度——见 Skin.kt wellOf。 */
    var Well by mutableStateOf(Color(0xFF232323))
    /**
     * 浮层底（菜单、弹窗、提示）：**必须不透明**——它盖在任意内容上。不透明皮肤的卡片本来就是实底（= 卡片色）；
     * 半透明卡片的皮肤（玻璃 / Aero）取「卡片落在底色上的样子」，否则菜单里的字压在底下页面的内容上。
     * [Popover] 给菜单与弹窗，[PopoverRaised] 给提示条（不透明皮肤里原先是卡片 hover 色，略亮一档）。
     */
    var Popover by mutableStateOf(Color(0xFF292929))
    var PopoverRaised by mutableStateOf(Color(0xFF303030))
    /**
     * 卡内容器底（筛选芯片组、卡内次按钮的静置底）：不透明皮肤 = 卡片色；半透明卡片的皮肤 = 透明、只留 hairline 描边。
     * 半透明卡片再叠一层卡片会一层比一层亮：aero 的筛选行是「卡 → 芯片组 Card → 选中片 CardHover」三层，
     * 选中片上的白字实拍 3.8:1。换肤时由 Skins.apply 写入。
     */
    var Inlay by mutableStateOf(Color(0xFF292929))
    /** 侧栏底（NavigationView pane：比底更暗一档）。 */
    var Sidebar by mutableStateOf(Color(0xFF191919))
    /** hairline 描边（白 8%）。 */
    var Stroke by mutableStateOf(Color(0x14FFFFFF))
    /** hover 描边（白 14%）。 */
    var StrokeHover by mutableStateOf(Color(0x24FFFFFF))
    /** 语言分布条底轨。 */
    var BarTrack by mutableStateOf(Color(0xFF303030))

    // ── 文字三级（白 100/66/53%）──
    // 三级文字按 53% 定：原来 45% 在卡片底（#292929）上只有 4.2:1，不到正文 4.5:1 的底线；
    // 提到 53% 后在底/卡片/侧栏三种底色上都 ≥ 5:1（次级 66% 约 7.9:1）。
    var TextPrimary by mutableStateOf(Color(0xFFFFFFFF))
    var TextSecondary by mutableStateOf(Color(0xA8FFFFFF))
    var TextTertiary by mutableStateOf(Color(0x87FFFFFF))

    // ── 强调与双轨（Fluent 暗色 accent 亮蓝 + 语义轨道色按暗底提亮）──
    /** Fluent 暗色主题 accent（#60CDFF）。 */
    var Accent by mutableStateOf(Color(0xFF60CDFF))
    /** accent 上的文字（Fluent 暗色 accent 亮，配近黑文字）。 */
    var OnAccent by mutableStateOf(Color(0xFF1B1B1B))
    /** accent 按钮 hover（比 accent 深一档）。 */
    var AccentHover by mutableStateOf(Color(0xFF48BDF2))
    // 绿 · 浅更新（暗底提亮）
    var Shallow by mutableStateOf(Color(0xFF6CCB5F))
    // 紫 · 深更新（暗底提亮）
    var Deep by mutableStateOf(Color(0xFFB5A6FF))
    // 青 · AI（暗底提亮）
    var Ai by mutableStateOf(Color(0xFF4CD6E8))

    // ── 状态 ──
    val Green: Color get() = Shallow
    var Yellow by mutableStateOf(Color(0xFFFFD24A))
    var Amber by mutableStateOf(Color(0xFFFFB35C))
    var Red by mutableStateOf(Color(0xFFFF99A4))

    // ── 文字级语义色（Skin.kt 在换皮肤时派生）──
    // 语义色身兼两职：当容器填充（按钮、胶囊、进度条——任何颜色都行，前景另配）与当「墨」
    // （画在页面/卡片表面上的文字、图标、徽标、细指示线——必须读得清）。为暗色皮肤挑的粉彩色
    // 在浅色皮肤上当墨只有 1–3 的对比度（Aqua 上实拍：橙字 1.4、绿字 1.9）。
    // 这组是同一色相的「文字级」：在本套皮肤的所有不透明表面上对比度 ≥ 4.5；暗色皮肤本来就达标，等于基色。
    var AccentText by mutableStateOf(Color(0xFF60CDFF))
    var ShallowText by mutableStateOf(Color(0xFF6CCB5F))
    var DeepText by mutableStateOf(Color(0xFFB5A6FF))
    var AiText by mutableStateOf(Color(0xFF4CD6E8))
    var YellowText by mutableStateOf(Color(0xFFFFD24A))
    var AmberText by mutableStateOf(Color(0xFFFFB35C))
    var RedText by mutableStateOf(Color(0xFFFF99A4))
    val GreenText: Color get() = ShallowText

    // ── hero（安静 Fluent 头：分层底纵向微渐变，无多色）──
    var HeroTop by mutableStateOf(Color(0xFF2E2E2E))
    var HeroBottom by mutableStateOf(Color(0xFF262626))
    var ShallowAlt by mutableStateOf(Color(0xFF9FE2A0))
    var DeepAlt by mutableStateOf(Color(0xFFD0C8FF))
    var AccentAlt by mutableStateOf(Color(0xFF9BDFFF))

    // ── 旧引用兼容（视图用名 → Fluent 语义）──
    val BgDeep: Color get() = Sidebar
    val GreenTextDark: Color get() = Shallow
    val AmberTextDark: Color get() = Amber
    val RedTextDark: Color get() = Red
    val Purple: Color get() = Deep
    val HeroIndigo: Color get() = HeroTop
    val HeroViolet: Color get() = HeroTop
    val HeroCyan: Color get() = HeroBottom
    val StrokeHoverLegacy: Color get() = StrokeHover
}

/** 字号档位（Fluent ramp：caption 12 / body 14 / subtitle 16 / title 20 / display 28）。 */
object Type {
    // 行高按 Fluent 2 排版（Body 14/20、Caption 12/16、Subtitle 16/22、Title 20/28）：
    // 多行正文与说明文字靠它拉开行距；此前不带行高，密排的说明读起来糊成一片
    // display 档是 KPI 数字与总分（2 / 12 / 25）：等宽数字（tnum）让同一列里的数在刷新时不对不齐地跳——
    // 「1」与「8」在比例数字下宽度不同（ui-ux-pro-max 规则 number-tabular）。
    var display by mutableStateOf(TextStyle(fontSize = 28.sp, lineHeight = 36.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary, fontFeatureSettings = "tnum"))
    var title by mutableStateOf(TextStyle(fontSize = 20.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary))
    var section by mutableStateOf(TextStyle(fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary))
    var card by mutableStateOf(TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary))
    var body by mutableStateOf(TextStyle(fontSize = 14.sp, lineHeight = 20.sp, color = Palette.TextPrimary))
    var label by mutableStateOf(TextStyle(fontSize = 12.sp, lineHeight = 16.sp, color = Palette.TextSecondary))
    // 12sp 起（原 11sp）：ui-ux-pro-max 的规则集把「正文 < 12px」列为反模式——caption 级的小字
    // 再叠上第三级文字色，行高 14px 在高分屏上发虚。字号 +1、行高 +1，层级关系不变。
    var micro by mutableStateOf(TextStyle(fontSize = 12.sp, lineHeight = 15.sp, color = Palette.TextTertiary))
}

/** 间距刻度 4/8/12/16/20/24（8 网格）。 */
object Space {
    val xs = 4.dp; val sm = 8.dp; val md = 12.dp; val lg = 16.dp; val xl = 20.dp; val xxl = 24.dp
}

/** 圆角三档（Fluent：control 4 / card 8 / overlay 8）。 */
object Radius {
    var chip by mutableStateOf(4.dp)
    var control by mutableStateOf(4.dp)
    var card by mutableStateOf(8.dp)
}

/** 动效时长（Fluent：常规 150ms / 浮层 300ms）。 */
object Motion {
    const val normal = 150
    const val slow = 300

    /**
     * 无障碍总开关：**无限循环**动画（骨架微光这类「永远在动」的东西）必须能被关——
     * 持续运动对前庭敏感的用户不友好。false 时骨架退化为静态色块。一次性的 150ms
     * 过渡（hover / 焦点环）不受它管：状态变化的即时反馈不属于持续运动。
     */
    var animate by mutableStateOf(true)
}

// ── 皮肤/材质令牌（Skin.kt 定义 Skin 与 Skins；这里的取值辅助供页面与卡片统一走）──

/** 页面底的填充：带背景装饰的皮肤返回透明（让窗口层的装饰露出来），其余实色 BgBase。 */
fun pageFill(): Brush = if (Material.backdrop == BackdropKind.NONE) Brush.horizontalGradient(listOf(Palette.BgBase, Palette.BgBase)) else Brush.horizontalGradient(listOf(Color.Transparent, Color.Transparent))

/** 卡片表面：底 + 皮肤描边宽度（链上用于 .background(...) 之后的 .border(...)）。 */
fun cardBorder(): androidx.compose.foundation.BorderStroke =
    androidx.compose.foundation.BorderStroke(Material.borderWidth, Palette.Stroke)

/**
 * 提交构成序列色（12 类穷举、不取模；Fluent 暗底域）的**原始值**。界面读 [Composition12]：换肤时按皮肤保底
 * （Skins.apply）——这组粉彩是为暗底挑的，浅色皮肤上当归档与图例点几乎看不见；保底后对底与卡 ≥ 3:1
 * （非文字图形的 WCAG 1.4.11），暗色皮肤本来就达标、等于原值。
 */
val Composition12Base = listOf(
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

/** 当前皮肤的提交构成序列色（Compose 状态，换肤时 Skins.apply 重算）。 */
var Composition12 by mutableStateOf(Composition12Base)

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
        primaryContainer = Palette.Accent.copy(alpha = 0.16f), onPrimaryContainer = Palette.AccentText,
        inversePrimary = Palette.AccentAlt,
        secondary = Palette.Deep, onSecondary = readableOn(Palette.Deep),
        secondaryContainer = Palette.Deep.copy(alpha = 0.16f), onSecondaryContainer = Palette.DeepText,
        tertiary = Palette.Ai, onTertiary = readableOn(Palette.Ai),
        tertiaryContainer = Palette.Ai.copy(alpha = 0.16f), onTertiaryContainer = Palette.AiText,
        background = Palette.BgBase, onBackground = Palette.TextPrimary,
        surface = Palette.Card, onSurface = Palette.TextPrimary,
        surfaceVariant = Palette.CardHover, onSurfaceVariant = Palette.TextSecondary,
        surfaceTint = Color.Transparent,
        inverseSurface = Palette.TextPrimary, inverseOnSurface = Palette.BgBase,
        outline = Palette.StrokeHover, outlineVariant = Palette.Stroke,
        error = Palette.Red, onError = readableOn(Palette.Red),
        errorContainer = Palette.Red.copy(alpha = 0.16f), onErrorContainer = Palette.RedText,
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

/**
 * Fluent 字阶映射到 Material 字体档（与 Type 的字号一致）。**不带颜色**——这是刻意的：
 * 全应用用的是 Material3 的 `Text`，它的取色顺序是「显式参数 → 样式里的颜色 → 容器给的内容色」。
 * 这里原先每档都写了 `color = Palette.TextPrimary`：实心按钮给的 contentColor 永远轮不到，主按钮上是
 * 白字压亮蓝（Fluent 实拍 1.7:1）；而且这个对象是启动时建一次的常量，颜色冻在默认皮肤的白字上，
 * 浅色皮肤里按钮的字也是白的（Aqua 实拍：白字压白底 1.1:1）。
 * 文字颜色只从两处来：界面自己传的 `Type.*`（换肤时重算），或容器的 `LocalContentColor`。
 */
val FluentTypography = androidx.compose.material3.Typography(
    labelSmall = androidx.compose.ui.text.TextStyle(fontSize = 11.sp),
    labelMedium = androidx.compose.ui.text.TextStyle(fontSize = 12.sp),
    labelLarge = androidx.compose.ui.text.TextStyle(fontSize = 14.sp),
    bodySmall = androidx.compose.ui.text.TextStyle(fontSize = 12.sp),
    bodyMedium = androidx.compose.ui.text.TextStyle(fontSize = 14.sp),
    bodyLarge = androidx.compose.ui.text.TextStyle(fontSize = 16.sp),
    titleMedium = androidx.compose.ui.text.TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = androidx.compose.ui.text.TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold),
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
    focusedBorderColor = Palette.AccentText,
    unfocusedBorderColor = Palette.StrokeHover,
    errorBorderColor = Palette.RedText,
    focusedLabelColor = Palette.AccentText,
    unfocusedLabelColor = Palette.TextSecondary,
    cursorColor = Palette.AccentText,
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
            PlainTooltip(containerColor = Palette.PopoverRaised, contentColor = Palette.TextPrimary) {
                androidx.compose.material3.Text(text, style = Type.label)
            }
        },
        state = androidx.compose.material3.rememberTooltipState(),
        content = { content() },
    )
}

// ── 通用姿态原语（loading / keyboardFocus / hover / truncation / badge）──
//
// 【为什么有一节】三个区域（仪表盘 / 置信度 / 图谱）接线时要的是同一批「姿态」：
// 加载占位、键盘焦点环、可点容器悬停抬升、截断文本、徽章形状。姿态是皮肤的「形」而非「色」：
// 这里只定形状与动效，配色全从 Palette / Material 令牌读，任何调用点重造一遍都会在某张浅色皮肤上破。

/** 骨架微光一轮的时长：派生自 Motion 令牌（一轮 = 4 × 浮层档 300ms），不在调用点裸写毫秒数。 */
private const val SkeletonSweepMillis = Motion.slow * 4

/** 悬停整体提亮的强度上限（Plus 混合里 CardHover 的透明度）；不做到 1，给容器自己的底色动画留层次。 */

/** 指针按下之后多久内落上的焦点算「鼠标取焦」（focus-visible 语义：按下与取焦同窗即指针会话）。 */
private const val PointerFocusWindowMillis = 500L

/**
 * 骨架底 + 微光扫过（loading 姿态的公共画法）。
 * 底 = Palette.CardHover（比所在表面亮一档的令牌），高光带 = Palette.StrokeHover
 * （描边家族的 hover 档：暗色皮肤里是半透明白，浅色皮肤里是实灰——两侧都读得出「这里在扫」，
 * 没有任何硬编码白）。无障碍：无限动画永远可关，[Motion.animate] 为 false 时退化为静态色块。
 */
@Composable
private fun Modifier.skeletonSurface(shape: Shape): Modifier {
    if (!Motion.animate) {
        return clip(shape).background(Palette.CardHover)
    }
    val sweep = rememberInfiniteTransition(label = "skeletonSweep")
    val x by sweep.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(SkeletonSweepMillis, easing = LinearEasing)),
        label = "skeletonBand",
    )
    return clip(shape).drawBehind {
        drawRect(Palette.CardHover)
        // 高光带从左扫到右：带宽与位移按最长边归一，长条与方块两种占位节奏一致
        val band = maxOf(size.width, size.height) * 0.6f
        val left = (size.width + band) * x - band
        drawRect(
            Brush.linearGradient(
                0f to Color.Transparent,
                0.5f to Palette.StrokeHover,
                1f to Color.Transparent,
                start = Offset(left, 0f),
                end = Offset(left + band, size.height),
            ),
        )
    }
}

/**
 * 单行文字占位（loading 姿态）。圆角走 Radius.chip 令牌——粗野皮肤 radius=0 时骨架自然变方块，
 * 占位件跟着皮肤走。[width] 缺省（null）铺满 [modifier] 给出的宽度，给 Dp 就是定宽短行。
 * （宽度用可空不用 Dp.Unspecified：Unspecified 的值是 NaN，而 Dp.equals 走浮点比较，
 * NaN != NaN，哨兵相等判断在它身上不成立。）
 */
@Composable
fun SkeletonLine(
    modifier: Modifier = Modifier,
    width: Dp? = null,
    height: Dp = 12.dp,
) {
    Box(
        modifier
            .then(if (width != null) Modifier.width(width) else Modifier)
            .height(height)
            .skeletonSurface(RoundedCornerShape(Radius.chip)),
    )
}

/** 卡片 / 横幅占位（loading 姿态）：整块圆角 Radius.card 占位，替换转圈或干等的空档。 */
@Composable
fun SkeletonCard(
    modifier: Modifier = Modifier,
    height: Dp = 96.dp,
) {
    Box(modifier.height(height).skeletonSurface(RoundedCornerShape(Radius.card)))
}

/**
 * 键盘焦点环（keyboardFocus 姿态）：accent 色 outline 环，2dp 描边外扩 1dp 画在界外
 * （drawBehind 叠加，不挤动布局）。只在**键盘**焦点出现——focus-visible 语义：
 * 指针按下后半秒内落上的焦点视为鼠标取焦，整段会话抑制环；焦点离开即复位，
 * 下一段 Tab 导航不受牵连。链上挂在 clickable / focusable 的**上游**：
 * 环要画在底色之外（下游 clip/背景盖不到界外的环），且要先于它们看到按下事件。
 * 本修饰符不制造焦点：可点容器用 clickable 自带的焦点节点，纯展示容器自己另挂 focusable()。
 */
fun Modifier.focusRing(
    enabled: Boolean = true,
    color: Color = Palette.AccentText,
    radius: Dp = Radius.control,
): Modifier = composed {
    var focused by remember { mutableStateOf(false) }
    var pointerSession by remember { mutableStateOf(false) }
    var lastPointerDownAt by remember { mutableStateOf(0L) }
    val ringAlpha by animateFloatAsState(
        if (enabled && focused && !pointerSession) 1f else 0f,
        tween(Motion.normal),
        label = "focusRingAlpha",
    )
    onFocusEvent { state ->
        // ⚠ 只认**自身**焦点（isFocused），不含后代：容器挂环 + 行内控件挂环时（仪表盘卡与它的
        // detail chip、里程碑行与它的 ActionText），Tab 到内层若用 hasFocus 会出现整卡环与
        // 控件环两道同亮——焦点环的语义是「环在 Tab 落到的那一个元素上」。
        if (state.isFocused && !focused) {
            // 焦点刚落上：看它是不是指针按出来的（按下与取焦同在半秒内 → 鼠标会话，压环）
            pointerSession = System.currentTimeMillis() - lastPointerDownAt <= PointerFocusWindowMillis
        }
        if (!state.isFocused) pointerSession = false // 会话结束复位，别把下一段键盘导航也压掉
        focused = state.isFocused
    }
        .pointerInput(Unit) {
            awaitPointerEventScope {
                while (true) {
                    // 只旁听按下、不消费：clickable / focusable 的手势照常工作
                    awaitFirstDown(requireUnconsumed = false)
                    lastPointerDownAt = System.currentTimeMillis()
                }
            }
        }
        .drawBehind {
            if (ringAlpha > 0.01f) {
                val strokeW = 2.dp.toPx()
                val gap = 1.dp.toPx()
                drawRoundRect(
                    color = color.copy(alpha = ringAlpha),
                    topLeft = Offset(-gap, -gap),
                    size = Size(size.width + gap * 2, size.height + gap * 2),
                    cornerRadius = CornerRadius(radius.toPx() + gap, radius.toPx() + gap),
                    style = Stroke(width = strokeW),
                )
            }
        }
}

/**
 * 可点容器悬停抬升（hover 姿态）：hover 时——
 *  ① 阴影增强按 Material.shadow 档位：NONE 不加（Fluent 纪律：分层靠提亮，不加阴影）；
 *     软阴影档（SOFT_DUAL / PUFFY / GLOW）用海拔阴影 150ms 淡入（graphicsLayer 的
 *     shadowElevation 档，与容器自己的 skinShadow 叠加即增强）；
 *     硬偏移档（HARD_OFFSET）hover 时再叠一遍 skinShadow——偏移块同形加深，正是粗野主义的 hover 语言。
 *  ② 上浮 [lift]（默认 2dp，graphicsLayer translationY 动画驱动，不动布局，与 skinShadow 各画各的）。
 *  这里**不提亮底色**：提亮要作用在表面上，只能由容器在自己的 background 里做（Card → CardHover，GlassCard
 *  与看板的项目卡都是）。原先本修饰符还有第 ③ 步「整体提亮」——内容画完后叠一层加法混合，说是「只对表面
 *  做加法」，其实连文字一起加：浅色皮肤里深色字被加上 35% 的近白色，整张卡的字被冲淡（Aqua 看板页悬停实拍：
 *  标题、状态词、动作全部掉到 2.1–2.4，体检的状态遍抓到）。暗色皮肤里白字被钳在纯白，所以一直没暴露。
 *
 * 链上挂在 skinShadow 的下游、clip / background 的上游（海拔阴影要画在底色之下才不出暗边）：
 *   `.skinShadow(r).hoverLift(interaction).clip(...).background(...)`（与 ButtonChrome 现有顺序同构）。
 * 不可点容器不挂它——hover 反应只属于能按的东西（目录纪律：GlassCard 那种「全都响应 hover」是反例）。
 */
fun Modifier.hoverLift(
    interaction: InteractionSource,
    enabled: Boolean = true,
    lift: Dp = 2.dp,
    radius: Dp = Radius.card,
): Modifier = composed {
    val hovered by interaction.collectIsHoveredAsState()
    val active = hovered && enabled
    val k by animateFloatAsState(if (active) 1f else 0f, tween(Motion.normal), label = "hoverLiftK")
    // 档位在换肤时整段换：软阴影档走海拔增强，其余档位本修饰符不加阴影
    val softShadowProfile = Material.shadow != ShadowProfile.NONE && Material.shadow != ShadowProfile.HARD_OFFSET
    this
        // ① 硬偏移档：hover 时同形叠一层皮肤阴影（位置在 clip/background 上游，底色会盖住重叠区）
        .then(if (Material.shadow == ShadowProfile.HARD_OFFSET && active) Modifier.skinShadow(radius) else Modifier)
        // ② 上浮 +（软阴影档）海拔增强：一个 graphicsLayer，动画帧只重设层属性，不重建层
        .graphicsLayer {
            translationY = -(lift * k).toPx()
            if (softShadowProfile) {
                shape = RoundedCornerShape(radius)
                shadowElevation = (lift * 2f * k).toPx() // 海拔给 2×lift：软阴影 2dp 几乎看不见，4dp 才读得出「浮起来了」（GraphicsLayerScope 里这是 Float 像素值，不是 Dp）
                ambientShadowColor = Material.shadowDark
                spotShadowColor = Material.shadowDark
            }
        }
}

/**
 * 截断文本（truncation 姿态）：ellipsis 截断；**真截到**（hasVisualOverflow）才包 [HelpTooltip]
 * 悬停给全文（语义 title）。没截断不包 tooltip——满屏悬停提示比截断本身更吵。
 * Row 里要 weight(1f) 的调用点：weight 是 RowScope 修饰符，外包一层 Box(Modifier.weight(1f))
 * 再把本组件放进去。
 */
@Composable
fun TruncatedText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = Type.label,
    color: Color = Color.Unspecified,
    maxLines: Int = 1,
) {
    var overflowed by remember(text) { mutableStateOf(false) }
    val line: @Composable () -> Unit = {
        Text(
            text,
            modifier = modifier,
            style = style,
            color = color,
            maxLines = maxLines,
            overflow = TextOverflow.Ellipsis,
            onTextLayout = { overflowed = it.hasVisualOverflow },
        )
    }
    if (overflowed) HelpTooltip(text) { line() } else line()
}

/**
 * 徽章 / 胶囊 / 碎片姿态令牌（badge / pill / chip）：形状与内边距**成对**取，不许各用各的——
 * 现状三套并存（DashboardView.Pill h8/v2、Buttons badge h5/v1、ChoicePill h12/v6、
 * detail.enter chip h8/v3），各差一点又都差一点。收敛成两档：
 *   · pill：999dp 全圆 + h8/v2（状态徽章一类，DashboardView.Pill 一族）；
 *   · chip：Radius.control（跟皮肤圆角）+ h12/v6（可点选胶囊一类，ChoicePill 一族）。
 * 用法：`Modifier.clip(Badge.pillShape).background(...).padding(horizontal = Badge.pillPadH, vertical = Badge.pillPadV)`。
 */
object Badge {
    /** pill 形状：全圆胶囊（姿态常量，不随皮肤变；状态徽章在所有皮肤里都是胶囊）。 */
    val pillShape = RoundedCornerShape(999.dp)
    val pillPadH = 8.dp
    val pillPadV = 2.dp

    /** chip 形状：控制圆角——get() 每次读令牌，换肤即换形；val 初始化会把它冻在启动时的皮肤上。 */
    val chipShape: RoundedCornerShape get() = RoundedCornerShape(Radius.control)
    val chipPadH = 12.dp
    val chipPadV = 6.dp
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
