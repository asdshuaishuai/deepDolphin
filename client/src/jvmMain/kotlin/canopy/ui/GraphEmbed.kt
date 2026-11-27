// GraphEmbed.kt —— 引擎图谱产物在页面内嵌时的适配配置。
//
// 【为什么要有这个】产物是引擎渲染的完整网页，自带页头、工具条、面包屑与技术状态条；原样塞进页面时
// 它与客户端自己的页头、回执条叠成六条横杠，画布只剩三分之一高，配色与圆角也不是一套。
// 引擎侧因此给产物加了「嵌入模式」（契约见 cambium 的 treehtml.cj · embedBootstrapJs）：
// 宿主在产物任何脚本之前声明
//   window.CAMBIUM_EMBED = { chrome: "page", vars: { …CSS 自定义属性… }, canvas: { …画在画布上的颜色… } }
// 产物就收拢外壳（一条命令条 + 画布 + 一条通栏底条）、改走宿主的主题。
// 这里只做一件事：把客户端的设计令牌（Design.kt 的 Palette / Radius / ControlHeight）翻译成那份配置——
// 令牌改了，图谱跟着变，不在产物里再手抄一份。老版本的引擎产物不认识这份配置，照旧按独立版渲染（优雅降级，不会坏）。
//
// 【尺寸契约】vars 里的 --e-* 四个是尺寸而不是颜色：控件高、底条高、控件/卡片圆角。
// 产物嵌入模式下的布局（按可用区域选列、泳道折行、取景）看的是它自己的视口，
// 视口 = 页头以下整页；这里的四个值让它的控件与外壳的控件同高同圆角。

package canopy.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.unit.Dp
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

/**
 * 产物换成客户端主题所需的 CSS 自定义属性。热力图与架构图两套变量名都给——多余的无害。
 * 全部由令牌派生：面取 Palette 的表面令牌，罩取 [veil]，语义色给**文字级**——产物里它们当文字与细线用
 * （置信度数字、计数、关系线、状态点）。原先这里写死了一副暗色调色板（节点 #2e2e2e、25% 的白描边……），
 * 浅色皮肤的深色文字压上去读不出来；Fluent 下派生值与原写死值只差 1–3 个色阶。
 */
internal fun graphEmbedVars(): JsonObject = obj {
    // 热力图产物的变量名（cambium treehtml.cj）
    put("--bg", Palette.BgBase.toCss())
    put("--panel", Palette.Card.toCss())
    put("--panel2", Palette.Sidebar.toCss())
    put("--line", Palette.StrokeHover.toCss())
    put("--line2", Palette.Stroke.toCss())
    put("--text", Palette.TextPrimary.toCss())
    put("--muted", Palette.TextSecondary.toCss())
    put("--muted2", Palette.TextTertiary.toCss())
    put("--green", Palette.ShallowText.toCss())
    put("--yellow", Palette.YellowText.toCss())
    put("--red", Palette.RedText.toCss())
    put("--cyan", Palette.AccentText.toCss())
    put("--violet", Palette.DeepText.toCss())
    put("--blue", Palette.AccentText.toCss())
    put("--radius", "${Radius.card.value.toInt()}px")   // Dp.toString() 是 "8.0.dp"，不能直接拼
    put("--sans", "\"system-ui\", \"Segoe UI\", \"Noto Sans\", \"Noto Sans CJK SC\", \"PingFang SC\", \"Microsoft YaHei\", sans-serif")
    put("--mono", "ui-monospace, \"Cascadia Mono\", \"JetBrains Mono\", Menlo, Consolas, \"Noto Sans Mono CJK SC\", monospace")
    // 架构图产物的变量名（cambium archhtml.cj）
    put("--grid", Palette.Card.toCss())
    put("--border", Palette.Stroke.toCss())
    put("--accent", Palette.AccentText.toCss())
    put("--arrow", Palette.TextTertiary.toCss())
    put("--chip", Palette.Card.toCss())
    // 嵌入样式自己的变量（第二层中性面、卡片、悬停、轨道、画布点阵）
    put("--e-surface", Palette.Sidebar.toCss())
    put("--e-card", Palette.Card.toCss())
    put("--e-hover", veil(0.06f).toCss())
    put("--e-track", Palette.BarTrack.toCss())
    put("--e-dot", veil(0.07f).toCss())
    put("--e-field", Palette.Sidebar.toCss())
    put("--e-active", Palette.Accent.copy(alpha = 0.10f).toCss())
    // 尺寸契约（产物嵌入样式里的 --e-* 变量）：控件高、底条高、控件圆角、卡片圆角——与外壳同值，
    // 单位同 CSS px。换成圆角为 0 的皮肤，嵌入页的输入框、按钮也跟着变方角；不传则产物回退到自己的定稿值。
    // 底条是页面最下面唯一的一条，高度取控件高：它和外壳的按钮是同一副尺寸。
    put("--e-ctl-h", cssPx(ControlHeight))
    put("--e-foot-h", cssPx(ControlHeight))
    put("--e-r-ctl", cssPx(Radius.control))
    put("--e-r-card", cssPx(Radius.card))
}

/** dp → CSS 长度：整数就写整数（"8px"），带小数保留一位（"2.5px"）；Dp.toString() 是 "8.0.dp"，不能直接拼。 */
internal fun cssPx(dp: Dp): String {
    val v = dp.value
    return (if (v == v.toLong().toFloat()) v.toLong().toString() else String.format(Locale.ROOT, "%.1f", v)) + "px"
}

/** 画在 canvas 上的颜色与圆角——CSS 管不到像素，只能由产物的绘制代码读这一份。 */
internal fun graphEmbedCanvas(): JsonObject = obj {
    // 热力图画布
    put("bg", Palette.BgBase.toCss())
    put("atmosphere", false)                       // 星点与光斑属于独立版的氛围，页面里不要
    put("bandA", veil(0.03f).toCss())
    put("bandB", veil(0.01f).toCss())
    put("bandLine", Palette.Stroke.toCss())
    put("nodeBoundary", Palette.Sidebar.toCss())
    put("nodeModule", Palette.Card.toCss())
    put("node", Palette.CardHover.toCss())
    put("text", Palette.TextPrimary.toCss())
    put("text3", Palette.TextTertiary.toCss())
    put("chip", veil(0.025f).compositeOver(Palette.CardHover).toCss())
    put("red", Palette.RedText.toCss())
    put("yellow", Palette.YellowText.toCss())
    put("green", Palette.ShallowText.toCss())
    put("accent", Palette.AccentText.toCss())
    put("radius", Radius.card.value.toInt())
    put("selectGlow", 8)                           // 选中卡片的外发光：独立版 16，页面里收一半
    put("track", Palette.BarTrack.toCss())
    put("stroke", veil(0.25f).toCss())
    // 架构图调色板（键名同产物的调色板；值全部取令牌）
    put("bg0", Palette.BgBase.toCss())
    put("bg1", Palette.Sidebar.toCss())
    put("grid", Palette.Card.toCss())
    put("muted", Palette.TextSecondary.toCss())
    put("border", Palette.StrokeHover.toCss())
    put("arrow", Palette.TextTertiary.toCss())
    put("card", Palette.Card.toCss())                // 模块卡片的底
    put("mini", Palette.Well.toCss())                // 小地图的底
    put("cols", JsonArray(layerFills().map { JsonPrimitive(it.toCss()) }))
    // 泳道标签是文字：给文字级的同一组语义色（cols 是填充色，浅色皮肤下黄 / 浅绿压在浅色泳道上读不出来）
    put("textCols", JsonArray(layerTexts().map { JsonPrimitive(it.toCss()) }))
    // 职责视图的角色色，顺序同产物的 ROLEPAL（入口 / 界面 / 服务 / 数据 / 存储 / 支撑 / 其他）。
    // 产物自带的角色色是给它自己的暗色底挑的；嵌入时页面以暗色为基座、只覆盖宿主给的键——
    // 宿主不给的话浅色皮肤下泳道标签只有 1.4–2.2:1（Aqua 实测，文字要 4.5）。按引擎色相的次序换成令牌：
    // 品红→Red、蓝→Accent、绿→Shallow、琥珀→Yellow、紫→Deep；剩下两档引擎是深浅两种灰，
    // 令牌里没有能分成两档的同色相中性色——「支撑」用还没出场的 Amber，「其他」用中性灰。
    put("roleCols", JsonArray(roleFills().map { JsonPrimitive(it.toCss()) }))
    // 标签是文字：走 ink()——同一色相的文字级，换肤时按所在表面保底（判据见 GraphParseTest）
    put("roleTextCols", JsonArray(roleTexts().map { JsonPrimitive(it.toCss()) }))
    put(
        "fills",
        JsonArray(
            layerFills().map { JsonPrimitive(it.copy(alpha = 0.10f).toCss()) },
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
    return (if (arch) DARK_SCHEME_SHIM else "") + "(function(){window.CAMBIUM_EMBED=" + json + ";})();"
}

/** 架构级五层（其他 / 接口 / 编排 / 核心 / 基础）的填充色：每次现读，令牌随皮肤变。 */
internal fun layerFills(): List<Color> =
    listOf(Palette.Accent, Palette.Deep, Palette.Shallow, Palette.Yellow, Palette.TextTertiary)

/** 职责视图七个角色（入口 / 界面 / 服务 / 数据 / 存储 / 支撑 / 其他）的填充色。 */
internal fun roleFills(): List<Color> =
    listOf(Palette.Red, Palette.Accent, Palette.Shallow, Palette.Yellow, Palette.Deep, Palette.Amber, Palette.TextTertiary)

/** 图上画布的两端：画布是 BgBase → Sidebar 的纵向渐变；半透明的侧栏色（玻璃拟态）先压在页面底上。 */
private fun canvasBases(): List<Color> = listOf(Palette.BgBase, Palette.Sidebar.compositeOver(Palette.BgBase))

/**
 * 一档图例色当「墨」用（泳道标签）：[ink] 给同一色相的文字级，再按标签**真正落的表面**保底——
 * 自己那一条泳道（这一档色以 [laneAlpha] 压在画布上）。换肤的保底只认皮肤自己的表面与 0.16 的同色 chip，
 * 这块带色的画布它不知道（玻璃拟态上紫字压在自己的泳道上差 0.05）。已经达标就原样返回，不是重设计。
 */
internal fun laneInk(fill: Color, laneAlpha: Float): Color =
    ensureContrast(ink(fill), canvasBases().map { fill.copy(alpha = laneAlpha).compositeOver(it) }, 4.5f)

/** 层标签的墨：泳道底 = 层色 0.10 × 驱动的 0.9。 */
internal fun layerTexts(): List<Color> = layerFills().map { laneInk(it, 0.10f * 0.9f) }

/** 角色标签的墨：泳道底 = 角色色 0.07 × 0.9。 */
internal fun roleTexts(): List<Color> = roleFills().map { laneInk(it, 0.07f * 0.9f) }

/** 读回一份嵌入配置里的变量（判据与调试用；不是合法配置 = 空表）。 */
internal fun decodeEmbedVars(script: String): Map<String, String> {
    val at = script.indexOf("window.CAMBIUM_EMBED=")
    if (at < 0) return emptyMap()
    val body = script.substring(at + "window.CAMBIUM_EMBED=".length)
        .removeSuffix("})();").removeSuffix(";").trim()
    return runCatching {
        embedJson.parseToJsonElement(body).jsonObject["vars"]?.jsonObject?.mapValues { it.value.jsonPrimitive.content } ?: emptyMap()
    }.getOrDefault(emptyMap())
}
