// Design.kt —— Fluent 深色设计系统（对位 archive/bui design.rs 与 mac 基准）。
//
// 【单点真相源】颜色/字号/间距全在此处；UI 组件不得内联色值。
// 【对比度】次级文字 ≥4.5:1（亮底深变体纪律）。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

object Palette {
    val BgBase = Color(0xFF0A0F1A)      // 页面底
    val BgDeep = Color(0xFF0C1424)      // 渐变底
    val Card = Color(0x14FFFFFF)        // 玻璃磁贴底（白 8%）
    val CardHover = Color(0x1FFFFFFF)   // 磁贴 hover（白 12%）
    val Stroke = Color(0x22FFFFFF)      // 描边
    val StrokeHover = Color(0x4D7CA6FF) // 磁贴 hover 描边（对位 .card.hoverable:hover rgba(124,166,255,.30)）
    val BarTrack = Color(0x1AFFFFFF)    // 语言分布条底轨（白 10%）
    val TextPrimary = Color(0xFFE6EDF3)
    val TextSecondary = Color(0xFF9AA8B8) // 对 #0A0F1A ≥ 4.5:1
    val Accent = Color(0xFF4C8DFF)
    val Green = Color(0xFF3FCF8E)
    val GreenTextDark = Color(0xFF0E9F6E)  // 亮底深变体（WCAG）
    val Amber = Color(0xFFF0883E)
    val AmberTextDark = Color(0xFFB45309)
    val Red = Color(0xFFF26D6D)
    val RedTextDark = Color(0xFFB91C1C)
    val Purple = Color(0xFFB08CFF)
}

/** 字号七档（对位 archive/bui fsDisplay..fsMicro，向框架 TITLE 靠拢，正文 ≥13）。 */
object Type {
    val display = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Palette.TextPrimary)
    val title = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Palette.TextPrimary)
    val section = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Palette.TextPrimary)
    val card = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Palette.TextPrimary)
    val body = TextStyle(fontSize = 13.sp, color = Palette.TextPrimary)
    val label = TextStyle(fontSize = 12.sp, color = Palette.TextSecondary)
    val micro = TextStyle(fontSize = 11.sp, color = Palette.TextSecondary)
}

object Space {
    val xs = 4.dp; val sm = 8.dp; val md = 12.dp; val lg = 18.dp; val xl = 24.dp
    val tileRadius = 12.dp
}

/** 提交构成 12 色（对位 logic CommitTypeComposition：12 类不取模，构成条与图例共用）。 */
val Composition12 = listOf(
    Color(0xFF4C8DFF), Color(0xFF3FCF8E), Color(0xFFB08CFF), Color(0xFFF0883E),
    Color(0xFFF26D6D), Color(0xFFE3B341), Color(0xFF38BDF8), Color(0xFF9AE6B4),
    Color(0xFFF6AD55), Color(0xFFFC8181), Color(0xFF76E4F7), Color(0xFFB794F4),
)

// ── aurora 背景（对位 archive/bui design.rs .aurora-a/b/c：三个 720px 圆形斑块）──
//    135deg 单层渐变：0% 实色 → 72% 全透明；整层透明度 .10，低透明度不抢内容。

/** 斑块层整体透明度（CSS `.aurora { opacity: .10 }`）。 */
const val AURORA_LAYER_ALPHA = 0.10f

/** 渐变淡出点（CSS `linear-gradient(135deg, C 0%, transparent 72%)`）。 */
const val AURORA_FADE_STOP = 0.72f

/** 斑块直径（CSS `width/height: 720px`）。 */
const val AURORA_SIZE_PX = 720f

/** 135deg 渐变档位（CSS `C 0% → transparent 72%`）：纯数据，可与 Brush 构造分开单测。 */
fun auroraStops(color: Color): List<Pair<Float, Color>> = listOf(
    0f to color,
    AURORA_FADE_STOP to color.copy(alpha = 0f),
)

/** 135deg = 渐变轴指向右下（start=左上角，end=右下角）；纯函数可单测。 */
fun auroraAxis(sizePx: Float): Pair<Offset, Offset> = Offset.Zero to Offset(sizePx, sizePx)

/** aurora 斑块渐变：档位 + 轴的机械应用（Brush 无公开字段，断言打在纯数据上）。 */
fun auroraBrush(color: Color, sizePx: Float = AURORA_SIZE_PX): Brush {
    val (start, end) = auroraAxis(sizePx)
    return Brush.linearGradient(*auroraStops(color).toTypedArray(), start = start, end = end)
}

/** 一个斑块的锚点（宿主内左上偏移，px）与颜色。 */
data class AuroraPatch(val color: Color, val left: Float, val top: Float)

/** 三斑块锚点（CSS 定位换算成宿主内绝对偏移；b 的 right/c 的 bottom/百分比全部显式换算）。 */
fun auroraPatches(width: Float, height: Float): List<AuroraPatch> = listOf(
    AuroraPatch(Palette.Accent, -220f, -280f),                                 // aurora-a #4C8DFF left -220 top -280
    AuroraPatch(Palette.Purple, width - AURORA_SIZE_PX + 240f, 90f),           // aurora-b #B08CFF right -240 top 90
    AuroraPatch(Palette.Green, width * 0.28f, height - AURORA_SIZE_PX + 360f), // aurora-c #3FCF8E left 28% bottom -360
)

/** aurora 背景层：铺满宿主、裁剪越界（负偏移斑块不得渗透邻居），叠在页面底色之上、内容之下。 */
@Composable
fun AuroraBackdrop(modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxSize().clipToBounds()) {
        val patches = auroraPatches(constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
        patches.forEach { p ->
            Box(
                Modifier
                    .offset { IntOffset(p.left.roundToInt(), p.top.roundToInt()) }
                    .alpha(AURORA_LAYER_ALPHA)
                    .size(AURORA_SIZE_PX.dp)
                    .background(auroraBrush(p.color)),
            )
        }
    }
}
