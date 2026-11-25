// GraphEmbed.kt —— 引擎图谱产物在页面内嵌时的适配配置。
//
// 【为什么要有这个】产物是引擎渲染的完整网页，自带页头、工具条、面包屑与技术状态条；原样塞进页面时
// 它与客户端自己的页头、回执条叠成六条横杠，画布只剩三分之一高，配色与圆角也不是一套。
// 引擎侧因此给产物加了「嵌入模式」（契约见 moongit 的 treehtml.cj · embedBootstrapJs）：
// 宿主在产物任何脚本之前声明
//   window.MOONGIT_EMBED = { chrome: "page", vars: { …CSS 自定义属性… }, canvas: { …画在画布上的颜色… } }
// 产物就收拢外壳（一条命令条 + 画布 + 一条面包屑条）、改走宿主的主题。
// 这里只做一件事：把客户端的设计令牌（Design.kt 的 Palette）翻译成那份配置——令牌改了，图谱跟着变，
// 不在产物里再手抄一份颜色。老版本的引擎产物不认识这份配置，照旧按独立版渲染（优雅降级，不会坏）。

package deepdolphin.ui

import androidx.compose.ui.graphics.Color
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.Locale

private val embedJson = Json { prettyPrint = false }

/** Compose 颜色 → CSS 颜色：不透明写 #rrggbb，带透明度写 rgba()（小数点恒为句点，不随区域设置变）。 */
internal fun Color.toCss(): String {
    fun ch(f: Float): Int = (f.coerceIn(0f, 1f) * 255f + 0.5f).toInt()
    return if (alpha >= 0.999f) {
        String.format(Locale.ROOT, "#%02x%02x%02x", ch(red), ch(green), ch(blue))
    } else {
        val a = String.format(Locale.ROOT, "%.3f", alpha).trimEnd('0').trimEnd('.')
        "rgba(${ch(red)},${ch(green)},${ch(blue)},$a)"
    }
}

private fun obj(build: JsonObjectBuilder.() -> Unit): JsonObject = buildJsonObject { build() }

/** 产物换成客户端主题所需的 CSS 自定义属性。热力图与架构图两套变量名都给——多余的无害。 */
internal fun graphEmbedVars(): JsonObject = obj {
    // 热力图产物的变量名（moongit treehtml.cj）
    put("--bg", Palette.BgBase.toCss())
    put("--panel", Palette.Card.toCss())
    put("--panel2", Palette.Sidebar.toCss())
    put("--line", Palette.StrokeHover.toCss())
    put("--line2", Palette.Stroke.toCss())
    put("--text", Palette.TextPrimary.toCss())
    put("--muted", Palette.TextSecondary.toCss())
    put("--muted2", Palette.TextTertiary.toCss())
    put("--green", Palette.Shallow.toCss())
    put("--yellow", Palette.Yellow.toCss())
    put("--red", Palette.Red.toCss())
    put("--cyan", Palette.Accent.toCss())
    put("--violet", Palette.Deep.toCss())
    put("--blue", Palette.Accent.toCss())
    put("--radius", "${Radius.card.value.toInt()}px")   // Dp.toString() 是 "8.0.dp"，不能直接拼
    put("--sans", "\"system-ui\", \"Segoe UI\", \"Noto Sans\", \"Noto Sans CJK SC\", \"PingFang SC\", \"Microsoft YaHei\", sans-serif")
    put("--mono", "ui-monospace, \"Cascadia Mono\", \"JetBrains Mono\", Menlo, Consolas, \"Noto Sans Mono CJK SC\", monospace")
    // 架构图产物的变量名（moongit archhtml.cj）
    put("--grid", Color(0xFF2A2A2A).toCss())
    put("--border", Palette.Stroke.toCss())
    put("--accent", Palette.Accent.toCss())
    put("--arrow", Palette.TextTertiary.toCss())
    put("--chip", Palette.Card.toCss())
    // 嵌入样式自己的变量（第二层中性面、卡片、悬停、轨道、画布点阵）
    put("--e-surface", Palette.Sidebar.toCss())
    put("--e-card", Palette.Card.toCss())
    put("--e-hover", Color(0x0FFFFFFF).toCss())
    put("--e-track", Palette.BarTrack.toCss())
    put("--e-dot", Color(0x12FFFFFF).toCss())
    put("--e-field", Color(0xFF1B1B1B).toCss())
    put("--e-active", Palette.Accent.copy(alpha = 0.10f).toCss())
}

/** 画在 canvas 上的颜色与圆角——CSS 管不到像素，只能由产物的绘制代码读这一份。 */
internal fun graphEmbedCanvas(): JsonObject = obj {
    // 热力图画布
    put("bg", Palette.BgBase.toCss())
    put("atmosphere", false)                       // 星点与光斑属于独立版的氛围，页面里不要
    put("bandA", Color(0x07FFFFFF).toCss())
    put("bandB", Color(0x03FFFFFF).toCss())
    put("bandLine", Palette.Stroke.toCss())
    put("nodeBoundary", Color(0xFF1B1B1B).toCss())
    put("nodeModule", Color(0xFF2A2A2A).toCss())
    put("node", Color(0xFF2E2E2E).toCss())
    put("text", Palette.TextPrimary.toCss())
    put("text3", Color(0x8FFFFFFF).toCss())
    put("chip", Color(0xFF333333).toCss())
    put("red", Palette.Red.toCss())
    put("yellow", Palette.Yellow.toCss())
    put("green", Palette.Shallow.toCss())
    put("accent", Palette.Accent.toCss())
    put("radius", Radius.card.value.toInt())
    put("selectGlow", 8)                           // 选中卡片的外发光：独立版 16，页面里收一半
    put("track", Palette.BarTrack.toCss())
    put("stroke", Color(0x40FFFFFF).toCss())
    // 架构图调色板（键名同它的暗色调色板）
    put("bg0", Palette.BgBase.toCss())
    put("bg1", Color(0xFF1C1C1C).toCss())
    put("grid", Color(0xFF2A2A2A).toCss())
    put("muted", Palette.TextSecondary.toCss())
    put("border", Palette.StrokeHover.toCss())
    put("arrow", Palette.TextTertiary.toCss())
    put("card", Color(0xF52B2B2B).toCss())           // 模块卡片的底（独立版是深蓝）
    put("mini", Color(0xEB292929).toCss())           // 小地图的底
    put("cols", JsonArray(listOf(Palette.Accent, Palette.Deep, Palette.Shallow, Palette.Yellow, Color(0xFF9A9A9A)).map { JsonPrimitive(it.toCss()) }))
    put(
        "fills",
        JsonArray(
            listOf(Palette.Accent, Palette.Deep, Palette.Shallow, Palette.Yellow, Color(0xFF9A9A9A)).map {
                JsonPrimitive(it.copy(alpha = 0.10f).toCss())
            },
        ),
    )
}

/**
 * 插进产物 <head> 最前面的脚本：声明嵌入配置。架构图另垫暗色——产物在嵌入模式下本就恒为暗色，
 * 这一层是给不认识嵌入配置的老引擎产物留的（它们跟随 prefers-color-scheme）。
 */
internal fun graphEmbedHeadScript(arch: Boolean): String {
    val cfg = obj {
        put("chrome", "page")
        put("vars", graphEmbedVars())
        put("canvas", graphEmbedCanvas())
    }
    val json = embedJson.encodeToString(JsonObject.serializer(), cfg)
    return (if (arch) DARK_SCHEME_SHIM else "") + "(function(){window.MOONGIT_EMBED=" + json + ";})();"
}

/** 读回一份嵌入配置里的变量（判据与调试用；不是合法配置 = 空表）。 */
internal fun decodeEmbedVars(script: String): Map<String, String> {
    val at = script.indexOf("window.MOONGIT_EMBED=")
    if (at < 0) return emptyMap()
    val body = script.substring(at + "window.MOONGIT_EMBED=".length)
        .removeSuffix("})();").removeSuffix(";").trim()
    return runCatching {
        embedJson.parseToJsonElement(body).jsonObject["vars"]?.jsonObject?.mapValues { it.value.jsonPrimitive.content } ?: emptyMap()
    }.getOrDefault(emptyMap())
}
