// Buttons.kt —— Fluent 按钮体系（32 高、圆角 4、hover 提亮）与 Pivot 页签条。
//
// 【为什么有个叫 Button 的】界面里三十多处按钮原本直接用 Material3 的 Button（40 高、胶囊感、
// 各处自带颜色参数）。这里放一个**同签名的 Fluent 替身**：参数名照旧（onClick/enabled/shape/colors），
// 颜色从调用点给的 ButtonColors 里读出来，外观统一成 Fluent 的标准按钮——各调用点只需不再导入
// Material3 的 Button，不必逐个改写。强调等级由底色决定：
//   · accent / 语义色实心（浅更新的绿、深更新的紫）= 主操作；
//   · 卡片底 + hairline 描边 = 次操作（刷新、说明这类）。

package deepdolphin.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.takeOrElse
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size

/** Fluent 控件的标准高度。 */
val ControlHeight: Dp = 32.dp

/** 按钮强调等级（Fluent 2 Accent）。 */
enum class Emphasis {
    /** 主操作：accent 实心。一屏最多一个。 */
    Primary,

    /** 次操作：卡片底 + hairline 描边。 */
    Standard,
}

/** 按钮的两种颜色（Material3 的 ButtonColors 在这个版本读不出来，这里放一个同形的替身）。 */
data class ButtonColors(val container: Color, val content: Color)

/** 与 Material3 的 ButtonDefaults.buttonColors 同形：调用点原样传颜色，不必改写。 */
object ButtonDefaults {
    fun buttonColors(
        containerColor: Color = Palette.Card,
        contentColor: Color = Palette.TextPrimary,
    ): ButtonColors = ButtonColors(containerColor, contentColor)
}

/** 语义色实心按钮的 hover：提亮一档。 */
private fun hoverOf(container: Color): Color = lerp(container, Color.White, 0.10f)

/** 卡片底的按钮算「描边次按钮」：要描边，hover 走卡片 hover 色。 */
private fun isStandardSurface(container: Color): Boolean = container == Palette.Card || container == Palette.CardHover

/**
 * Material3 Button 的 Fluent 替身（见文件头）。[shape] 参数收下但不用——按钮圆角全应用统一；
 * [colors] 给了就按它的底色/内容色，没给按次按钮。
 */
@Composable
fun Button(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    shape: androidx.compose.ui.graphics.Shape? = null,
    colors: ButtonColors? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val container = colors?.container?.takeIf { it != Color.Unspecified }
    val onContainer = colors?.content?.takeIf { it != Color.Unspecified }
    val bgIdle = container ?: Palette.Card
    val bgHover = if (container != null && !isStandardSurface(container)) hoverOf(container) else Palette.CardHover
    val fg = onContainer ?: Palette.TextPrimary
    ButtonChrome(onClick, modifier, enabled, bgIdle, bgHover, fg, outlined = container == null || isStandardSurface(bgIdle), content = content)
}

/** 文字按钮（Fluent 标准高度 32、圆角 4）：hover 提亮、禁用降透明度。[icon] 画在文字前面。 */
@Composable
fun FluentButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: FluentIcon? = null,
    emphasis: Emphasis = Emphasis.Standard,
    enabled: Boolean = true,
    container: Color? = null,
    onContainer: Color? = null,
    badge: String? = null,
) {
    val bgIdle: Color
    val bgHover: Color
    val fg: Color
    when {
        container != null -> { bgIdle = container; bgHover = hoverOf(container); fg = onContainer ?: Palette.BgBase }
        emphasis == Emphasis.Primary -> { bgIdle = Palette.Accent; bgHover = Palette.AccentHover; fg = Palette.OnAccent }
        else -> { bgIdle = Palette.Card; bgHover = Palette.CardHover; fg = Palette.TextPrimary }
    }
    ButtonChrome(onClick, modifier, enabled, bgIdle, bgHover, fg, outlined = container == null && emphasis == Emphasis.Standard) {
        icon?.let {
            IconBox(it, size = 16.dp, tint = fg)
            Spacer(Modifier.width(6.dp))
        }
        Text(text, style = Type.body.copy(fontWeight = FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Clip)
        // 计数徽章：只在真有东西时出现（恒显 0 会被无视，「0」还容易被读成「引擎说不用更新」）；
        // 实色按钮上用「白底深字胶囊」，保证读得清
        if (badge != null) {
            Spacer(Modifier.width(6.dp))
            Text(
                badge,
                style = Type.micro.copy(fontWeight = FontWeight.Bold, color = Palette.BgBase),
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(Color.White.copy(alpha = 0.92f))
                    .padding(horizontal = 5.dp, vertical = 1.dp),
            )
        }
    }
}

/** 仅图标的按钮（Fluent 32×32）：hover 提亮、禁用变暗。关闭、刷新、返回这类动作用。 */
@Composable
fun IconButton(
    icon: FluentIcon,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    tint: Color = Color.Unspecified,
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val bg by animateColorAsState(
        if (hovered && enabled) Palette.CardHover else Color.Transparent,
        tween(Motion.normal),
        label = "iconBtnBg",
    )
    Box(
        modifier
            .size(ControlHeight)
            .clip(RoundedCornerShape(Radius.control))
            .background(bg)
            .hoverable(interaction)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        IconBox(icon, size = 16.dp, tint = if (enabled) tint.takeOrElse { Palette.TextSecondary } else Palette.TextTertiary)
    }
}

/** 按钮外壳：底色 hover 渐变、可选 hairline 描边、内容色与字重下发给内容。 */
@Composable
private fun ButtonChrome(
    onClick: () -> Unit,
    modifier: Modifier,
    enabled: Boolean,
    bgIdle: Color,
    bgHover: Color,
    fg: Color,
    outlined: Boolean,
    content: @Composable RowScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val active = hovered && enabled
    val bg by animateColorAsState(if (active) bgHover else bgIdle, tween(Motion.normal), label = "btnBg")
    val border by animateColorAsState(
        if (outlined) (if (active) Palette.StrokeHover else Palette.Stroke) else Color.Transparent,
        tween(Motion.normal),
        label = "btnBorder",
    )
    val contentColor = if (enabled) fg else fg.copy(alpha = 0.45f)
    CompositionLocalProvider(LocalContentColor provides contentColor) {
        Row(
            modifier
                .height(ControlHeight)
                .clip(RoundedCornerShape(Radius.control))
                .background(bg)
                .border(1.dp, border, RoundedCornerShape(Radius.control))
                .hoverable(interaction)
                .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
    }
}

/**
 * Fluent Pivot（页签条）：一条 40 高的导航，选中项文字转主色并压一条 3dp accent 下划线；
 * 未选中项坐一层浅底，hover 提亮。设置页主导航用它——原来是一排 accent 胶囊，
 * 选中的那一颗又亮又圆，看着像按钮而不是「我在哪一页」。
 */
@Composable
fun Pivot(items: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().drawBehind {
        // 整条底部 1px 分隔线；选中项的下划线压在它上面，与下方内容连成一层
        drawRect(Palette.Stroke, topLeft = Offset(0f, size.height - 1.dp.toPx()), size = Size(size.width, 1.dp.toPx()))
    }) {
        Row(Modifier.fillMaxWidth().height(40.dp)) {
            items.forEachIndexed { i, label ->
                val sel = i == selected
                val interaction = remember { MutableInteractionSource() }
                val hovered by interaction.collectIsHoveredAsState()
                val bg by animateColorAsState(
                    when {
                        sel -> Color.Transparent
                        hovered -> Palette.CardHover
                        else -> Palette.Card
                    },
                    tween(Motion.normal),
                    label = "pivotBg",
                )
                Box(
                    Modifier
                        .fillMaxHeight()
                        .background(bg)
                        .clickable(interactionSource = interaction, indication = null) { onSelect(i) }
                        .padding(horizontal = 16.dp)
                        .drawBehind {
                            if (sel) {
                                drawRect(Palette.Accent, topLeft = Offset(0f, size.height - 3.dp.toPx()), size = Size(size.width, 3.dp.toPx()))
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        label,
                        style = Type.body.copy(fontWeight = if (sel) FontWeight.SemiBold else FontWeight.Normal),
                        color = if (sel) Palette.TextPrimary else Palette.TextSecondary,
                    )
                }
            }
        }
    }
}
