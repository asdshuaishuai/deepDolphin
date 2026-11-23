// Design.kt —— macOS 纯粹设计系统（对位 macos/Sources/deepDolphin/DesignTokens.swift +
// DesignSystem.swift 的 Kotlin 镜像；语义名与取值逐项对位，UI 组件不得内联色值）。
//
// 【渐变纪律】渐变只做两件事：hero 页头底、同一语义色内部深→亮过渡。
//   拿别的语义色来拼渐变 = 发明第四种双轨色（mac 基准原话）。
// 【圆角三档】chip 3 / control 6 / card 10。淘汰散值。
// 【文字】跟随系统文本样式档位：metric=title2 semibold、sectionTitle=headline、
//   cardTitle=subheadline semibold、body、label=caption、badge=caption2。

package deepdolphin.ui

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ── 表面三级 + 侧栏 + 描边（DSPalette 暗色系；亮色跟随系统属后续批）──
object Palette {
    /** 页面底（bgDark 0x0F172A）。 */
    val BgBase = Color(0xFF0F172A)
    /** 卡片表面（cardDark 0x1E293B）。实色，非玻璃。 */
    val Card = Color(0xFF1E293B)
    /** 卡片 hover 微亮（slate-750 近似，对位 .card.hoverable surface-2）。 */
    val CardHover = Color(0xFF283A52)
    /** 侧栏底（sidebarDark 0x0B0F19）。 */
    val Sidebar = Color(0xFF0B0F19)
    /** hairline 描边（borderDark 0x334155）。 */
    val Stroke = Color(0xFF334155)
    /** hover 描边（对位 .card.hoverable:hover rgba(124,166,255,.30) 的实色近似）。 */
    val StrokeHover = Color(0xFF7CA6FF)
    /** 语言分布条底轨。 */
    val BarTrack = Color(0xFF334155)

    // ── 文字三级 ──
    val TextPrimary = Color(0xFFE6EDF3)     // slate-200（≈ Color.primary dark）
    val TextSecondary = Color(0xFF94A3B8)   // slate-400
    val TextTertiary = Color(0xFF94A3B8).copy(alpha = 0.65f)

    // ── 双轨与强调（DSPalette 原值）──
    val Accent = Color(0xFF3B82F6)   // 蓝 · 强调（0x3B82F6）
    val Shallow = Color(0xFF10B981)  // 绿 · 浅更新（0x10B981）
    val Deep = Color(0xFF8B5CF6)     // 紫 · 深更新（0x8B5CF6）
    val Ai = Color(0xFF06B6D4)       // 青 · AI（0x06B6D4）

    // ── 状态（DSColor.color(_:) 对位：active=shallow、idle=yellow、stale=orange、merged=deep、dirty=red）──
    val Green = Shallow
    val Yellow = Color(0xFFEAB308)
    val Amber = Color(0xFFF97316)
    val Red = Color(0xFFEF4444)

    // ── hero 渐变端点（DSGradient.hero：靛 → 紫 → 青）──
    val HeroIndigo = Color(0xFF4F46E5)
    val HeroViolet = Color(0xFF7C3AED)
    val HeroCyan = Color(0xFF06B6D4)
    val ShallowAlt = Color(0xFF34D399)
    val DeepAlt = Color(0xFFA78BFA)
    val AccentAlt = Color(0xFF60A5FA)

    // ── 旧引用兼容（批 1-4 视图用名 → mac 语义）──
    val BgDeep = Sidebar
    val GreenTextDark = Shallow
    val AmberTextDark = Amber
    val RedTextDark = Red
    val Purple = Deep
}

/** 字号档位（对位 DSTypography：系统文本样式语义，档位值向 macOS 点数靠拢）。 */
object Type {
    /** metric：KPI 大数（title2 semibold）。 */
    val display = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    /** sectionTitle：headline。 */
    val title = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Palette.TextPrimary)
    /** 与 title 同族（mac headline 唯一）；卡片小节标题用 card。 */
    val section = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    /** cardTitle：subheadline semibold。 */
    val card = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    val body = TextStyle(fontSize = 13.sp, color = Palette.TextPrimary)
    /** label：caption，次级色。 */
    val label = TextStyle(fontSize = 12.sp, color = Palette.TextSecondary)
    /** badge：caption2，tertiary。 */
    val micro = TextStyle(fontSize = 10.sp, color = Palette.TextTertiary)
}

/** 间距刻度 4/8/12/16/20/24（DSSpacing 原值；淘汰 18 这类散值）。 */
object Space {
    val xs = 4.dp; val sm = 8.dp; val md = 12.dp; val lg = 16.dp; val xl = 20.dp; val xxl = 24.dp
}

/** 圆角三档（DSRadius：chip 3 / control 6 / card 10）。 */
object Radius {
    val chip = 3.dp; val control = 6.dp; val card = 10.dp
}

/** 提交构成序列色（DSColor.sequence(_:): 12 类穷举、不取模——mac 基准原话）。 */
val Composition12 = listOf(
    Color(0xFF3B82F6), // blue
    Color(0xFFEF4444), // red
    Color(0xFFF97316), // orange
    Color(0xFF8B5CF6), // purple
    Color(0xFF14B8A6), // teal
    Color(0xFF6366F1), // indigo
    Color(0xFF34D399), // mint
    Color(0xFFEC4899), // pink
    Color(0xFFB45309), // brown
    Color(0xFFEAB308), // yellow
    Color(0xFF06B6D4), // cyan
    Color(0xFF6B7280), // gray
)

// ── 渐变（DSGradient 对位：渐变只做两件事——hero 页头底、同一语义色内部深→亮）──

/** hero 渐变端点（靛 → 紫 → 青；start 左上 → end 右下）。 */
fun heroStops(): List<Color> = listOf(Palette.HeroIndigo, Palette.HeroViolet, Palette.HeroCyan)

/** hero 页头渐变（纯函数可单测；Brush 无公开字段，断言打在端点数据上）。 */
fun heroBrushDiagonal(): Brush = Brush.linearGradient(
    heroStops(),
    start = Offset.Zero,
    end = Offset.Infinite,
)

/** 语义色内部深→亮（shallow/deep/ai 各自的亮端是同语义的 Alt，不是第二种语义）。 */
fun semanticBrush(head: Color, alt: Color): Brush = Brush.linearGradient(listOf(head, alt), start = Offset.Zero, end = Offset.Infinite)

fun shallowBrush(): Brush = semanticBrush(Palette.Shallow, Palette.ShallowAlt)
fun deepBrush(): Brush = semanticBrush(Palette.Deep, Palette.DeepAlt)
fun aiBrush(): Brush = semanticBrush(Palette.Ai, Palette.AccentAlt)
fun accentBrush(): Brush = semanticBrush(Palette.Accent, Palette.AccentAlt)
