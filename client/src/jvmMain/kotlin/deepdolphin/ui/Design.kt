// Design.kt —— Fluent 深色设计系统（对位 archive/bui design.rs 与 mac 基准）。
//
// 【单点真相源】颜色/字号/间距全在此处；UI 组件不得内联色值。
// 【对比度】次级文字 ≥4.5:1（亮底深变体纪律）。

package deepdolphin.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

object Palette {
    val BgBase = Color(0xFF0A0F1A)      // 页面底
    val BgDeep = Color(0xFF0C1424)      // 渐变底
    val Card = Color(0x14FFFFFF)        // 玻璃磁贴底（白 8%）
    val CardHover = Color(0x1FFFFFFF)   // 磁贴 hover（白 12%）
    val Stroke = Color(0x22FFFFFF)      // 描边
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
