// Controls.kt —— Fluent 输入控件：文本框、下拉菜单与菜单项、下拉选择框。
//
// 【为什么有几个和 Material3 同名的函数】界面里十几个文本框、菜单原本直接用 Material3 的
// 同名组件（56 高的文本框、48 高的菜单项、无边框的菜单面板），另外还有三处自绘的
// 「点开在原地撑开一块」的假下拉。这里放**同签名的 Fluent 替身**：参数名照旧、颜色照读，
// 外观统一成 Fluent 的控件规格——各调用点只需不再导入 Material3 的同名组件。
//   · 文本框：36 高、圆角 4、hairline 描边，聚焦转 accent；
//   · 菜单面板：圆角 8、卡片底、hairline 描边 + 投影（浮层与页面分层）；
//   · 菜单项：36 高；
//   · 下拉选择框（FluentDropdown）：与文本框同一套外观，真正的浮出菜单，选中项带勾。

package deepdolphin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.TextFieldColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.BorderStroke

/** Fluent 文本框高度（单行）。 */
private val FieldHeight: Dp = 36.dp

/** Material3 OutlinedTextField 的 Fluent 替身（见文件头）。[colors] 只用来取聚焦/常态的描边色。 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun OutlinedTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    singleLine: Boolean = true,
    placeholder: (@Composable () -> Unit)? = null,
    textStyle: TextStyle = Type.body,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    colors: TextFieldColors = fluentTextFieldColors(),
    maxLines: Int = Int.MAX_VALUE,
) {
    val interaction = remember { MutableInteractionSource() }
    val shape = RoundedCornerShape(Radius.control)
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        enabled = enabled,
        singleLine = singleLine,
        textStyle = textStyle.copy(color = if (enabled) Palette.TextPrimary else Palette.TextTertiary),
        cursorBrush = SolidColor(Palette.Accent),
        visualTransformation = visualTransformation,
        interactionSource = interaction,
        maxLines = if (singleLine) 1 else maxLines,
        modifier = modifier.then(if (singleLine) Modifier.height(FieldHeight) else Modifier),
        decorationBox = { inner ->
            androidx.compose.material3.OutlinedTextFieldDefaults.DecorationBox(
                value = value,
                innerTextField = inner,
                enabled = enabled,
                singleLine = singleLine,
                visualTransformation = visualTransformation,
                interactionSource = interaction,
                placeholder = placeholder,
                colors = colors,
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 7.dp),
                container = {
                    androidx.compose.material3.OutlinedTextFieldDefaults.Container(
                        enabled = enabled,
                        isError = false,
                        interactionSource = interaction,
                        modifier = Modifier,
                        colors = colors,
                        shape = shape,
                    )
                },
            )
        },
    )
}

/** Material3 DropdownMenu 的 Fluent 替身：圆角 8、卡片底、hairline 描边 + 投影。 */
@Composable
fun DropdownMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    offset: DpOffset = DpOffset.Zero,
    containerColor: Color = Palette.Card,
    content: @Composable ColumnScope.() -> Unit,
) {
    androidx.compose.material3.DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismissRequest,
        modifier = modifier,
        offset = offset,
        shape = RoundedCornerShape(Radius.card),
        containerColor = containerColor,
        tonalElevation = 0.dp,
        shadowElevation = 12.dp,
        border = BorderStroke(1.dp, Palette.Stroke),
        content = content,
    )
}

/** Material3 DropdownMenuItem 的 Fluent 替身：36 高、左右 12 内边距。 */
@Composable
fun DropdownMenuItem(
    text: @Composable () -> Unit,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    androidx.compose.material3.DropdownMenuItem(
        text = text,
        onClick = onClick,
        modifier = modifier.height(ControlHeight + 4.dp),
        enabled = enabled,
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
    )
}

/**
 * Fluent 下拉选择框：外观与文本框同一套（[FluentDropdown] 的盒身自己画，36 高、圆角 4、
 * hairline 描边、hover 提亮），点开是真正的浮出菜单——不再在原地撑开一块把下面的内容挤走。
 * [options] 是 (键, 显示文字) 列表；[selectedKey] 为 null 时显示 [placeholder]。
 */
@Composable
fun FluentDropdown(
    options: List<Pair<String, String>>,
    selectedKey: String?,
    placeholder: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    var open by rememberSaveable { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val focusedLook = open
    val border by androidx.compose.animation.animateColorAsState(
        when {
            !enabled -> Palette.Stroke
            focusedLook -> Palette.Accent
            hovered -> Palette.StrokeHover
            else -> Palette.StrokeHover
        },
        androidx.compose.animation.core.tween(Motion.normal),
        label = "dropdownBorder",
    )
    val bg by androidx.compose.animation.animateColorAsState(
        if (hovered && enabled) Palette.CardHover else Color.Transparent,
        androidx.compose.animation.core.tween(Motion.normal),
        label = "dropdownBg",
    )
    val selectedLabel = options.firstOrNull { it.first == selectedKey }?.second
    Box(modifier) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .height(FieldHeight)
                .clip(RoundedCornerShape(Radius.control))
                .background(bg)
                .border(1.dp, border, RoundedCornerShape(Radius.control))
                .clickable(interactionSource = interaction, indication = null, enabled = enabled) { open = true }
                .padding(horizontal = 12.dp),
        ) {
            BasicText(
                text = selectedLabel ?: placeholder,
                style = Type.body.copy(
                    color = when {
                        selectedLabel == null -> Palette.TextSecondary
                        !enabled -> Palette.TextTertiary
                        else -> Palette.TextPrimary
                    },
                ),
                maxLines = 1,
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(6.dp))
            IconBox(FluentIcon.ChevronDown, size = 12.dp, tint = Palette.TextSecondary)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { (key, label) ->
                DropdownMenuItem(
                    text = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            // 选中项打勾；未选项留同样的宽度，文字左缘对齐
                            Box(Modifier.width(16.dp)) {
                                if (key == selectedKey) {
                                    IconBox(FluentIcon.Checkmark, size = 14.dp, tint = Palette.Accent)
                                }
                            }
                            Spacer(Modifier.width(8.dp))
                            BasicText(
                                text = label,
                                style = Type.body.copy(
                                    color = if (key == selectedKey) Palette.Accent else Palette.TextPrimary,
                                ),
                                maxLines = 1,
                            )
                        }
                    },
                    onClick = {
                        open = false
                        onSelect(key)
                    },
                )
            }
        }
    }
}
