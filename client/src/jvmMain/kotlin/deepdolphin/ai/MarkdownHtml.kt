// MarkdownHtml.kt —— Markdown → HTML 的纯函数转换（C6 收尾批：助手消息排版渲染的数据层）。
//
// 【定位】无视图依赖、可独立判据测试（对位 archive/bui macos/Sources/deepDolphin/MarkdownParser.swift
// 的「解析抽纯函数」做法）。覆盖常见块级语法（标题/围栏代码块/列表/表格/引用/分隔线）
// 与行内（粗体/斜体/行内码/链接），不追求完整 GFM——下划线强调、图片、Setext 标题不支持
// （下划线易误伤 `foo_bar` 这类路径，宁缺勿错）。
// 【纪律】正文先 HTML 转义再套标签：AI/引擎返回的文本不构成注入面——<script>
// 只能以实体形式出现；颜色/字号不在本层，完整文档由 ui/MarkdownWebView 的
// markdownDocument 从 Design.kt 单点真相源装配。
// 【判据】jvmTest/deepdolphin/ai/MarkdownHtmlTest.kt：标题/代码块/转义/列表/表格/行内/文档令牌。

package deepdolphin.ai

/** HTML 转义（& < > " '）。纯函数。 */
fun escapeHtml(text: String): String = buildString(text.length + 16) {
    for (c in text) when (c) {
        '&' -> append("&amp;")
        '<' -> append("&lt;")
        '>' -> append("&gt;")
        '"' -> append("&quot;")
        '\'' -> append("&#39;")
        else -> append(c)
    }
}

private val INLINE_CODE = Regex("`([^`\n]+)`")
private val LINK = Regex("""\[([^\]\n]+)]\(([^)\s]+)\)""")
private val BOLD = Regex("""\*\*([^*\n]+)\*\*""")
private val EM = Regex("""(?<!\*)\*([^*\n]+)\*(?!\*)""")
private val PLACEHOLDER = Regex("\uE000(\\d+)\uE001")

/** 行内格式：转义 → 行内码摘出（私用区占位）→ 链接/粗/斜 → 还原 <code>。纯函数。 */
fun renderInline(text: String): String {
    val escaped = escapeHtml(text)
    val codeSpans = mutableListOf<String>()
    // 占位符用私用区字符（\uE000/\uE001），后续粗/斜/链接的正则都不会碰到它
    val withCodes = INLINE_CODE.replace(escaped) { m ->
        codeSpans += m.groupValues[1]
        "\uE000${codeSpans.size - 1}\uE001"
    }
    var s = withCodes
    // 链接：url 已被转义（引号成 &quot;），不可能破 href 属性
    s = LINK.replace(s) { m -> "<a href=\"${m.groupValues[2]}\">${m.groupValues[1]}</a>" }
    s = BOLD.replace(s) { m -> "<strong>${m.groupValues[1]}</strong>" }
    s = EM.replace(s) { m -> "<em>${m.groupValues[1]}</em>" }
    return PLACEHOLDER.replace(s) { m -> "<code>${codeSpans[m.groupValues[1].toInt()]}</code>" }
}

/** 块级转换：markdown → HTML 片段（不含 html/body 壳）。空/纯空白输入返回空串。纯函数。 */
fun markdownToBodyHtml(markdown: String): String {
    if (markdown.isBlank()) return ""
    val lines = markdown.replace("\r\n", "\n").replace('\r', '\n').split('\n')
    val out = StringBuilder()
    var i = 0
    while (i < lines.size) {
        val t = lines[i].trim()
        when {
            t.isEmpty() -> i++

            isFence(t) -> { // ``` 围栏代码块：内部只转义，不做行内格式
                val lang = t.removePrefix("```").trim()
                val body = StringBuilder()
                i++
                while (i < lines.size && !lines[i].trim().startsWith("```")) {
                    body.append(lines[i]).append('\n'); i++
                }
                i++ // 跳过收尾 ```（缺失则已到文件尾）
                val langAttr = if (lang.isEmpty()) "" else " data-lang=\"${escapeHtml(lang)}\""
                out.append("<pre><code$langAttr>${escapeHtml(body.toString().trimEnd('\n'))}</code></pre>\n")
            }

            headingLevel(t) != null -> {
                val lvl = headingLevel(t)!!
                out.append("<h$lvl>${renderInline(t.dropWhile { it == '#' }.trim())}</h$lvl>\n")
                i++
            }

            isHr(t) -> { out.append("<hr>\n"); i++ }

            isTableRow(t) && i + 1 < lines.size && isTableSeparator(lines[i + 1].trim()) -> {
                val header = splitRow(t)
                i += 2
                val rows = mutableListOf<List<String>>()
                while (i < lines.size && isTableRow(lines[i].trim())) { rows += splitRow(lines[i].trim()); i++ }
                out.append("<table><thead><tr>")
                header.forEach { out.append("<th>${renderInline(it)}</th>") }
                out.append("</tr></thead><tbody>")
                rows.forEach { r ->
                    out.append("<tr>")
                    r.forEach { c -> out.append("<td>${renderInline(c)}</td>") }
                    out.append("</tr>")
                }
                out.append("</tbody></table>\n")
            }

            t.startsWith(">") -> { // 引用：> 行合并，行间 <br>
                val body = StringBuilder()
                while (i < lines.size && lines[i].trim().startsWith(">")) {
                    if (body.isNotEmpty()) body.append("<br>")
                    body.append(renderInline(lines[i].trim().removePrefix(">").trim()))
                    i++
                }
                out.append("<blockquote>$body</blockquote>\n")
            }

            isBullet(t) -> {
                out.append("<ul>")
                while (i < lines.size && isBullet(lines[i].trim())) {
                    out.append("<li>${renderInline(lines[i].trim().substring(2).trim())}</li>")
                    i++
                }
                out.append("</ul>\n")
            }

            isOrdered(t) -> {
                out.append("<ol>")
                while (i < lines.size && isOrdered(lines[i].trim())) {
                    val item = lines[i].trim().dropWhile { it.isDigit() || it == '.' || it == ')' }.trim()
                    out.append("<li>${renderInline(item)}</li>")
                    i++
                }
                out.append("</ol>\n")
            }

            else -> { // 段落：吃到空行或下一个块级起点，行间 <br>
                val para = StringBuilder()
                while (i < lines.size) {
                    val tt = lines[i].trim()
                    if (tt.isEmpty() || isFence(tt) || headingLevel(tt) != null || isHr(tt) ||
                        isBullet(tt) || isOrdered(tt) || tt.startsWith(">") ||
                        (isTableRow(tt) && i + 1 < lines.size && isTableSeparator(lines[i + 1].trim()))
                    ) break
                    if (para.isNotEmpty()) para.append("<br>")
                    para.append(renderInline(tt))
                    i++
                }
                out.append("<p>$para</p>\n")
            }
        }
    }
    return out.toString().trimEnd('\n')
}

private fun isFence(t: String) = t.startsWith("```")

/** `#{1,6}` + 空格/行尾 才算标题（####### 或 #abc 不算）。 */
private fun headingLevel(t: String): Int? {
    if (!t.startsWith("#")) return null
    val n = t.takeWhile { it == '#' }.length
    if (n > 6) return null
    val rest = t.drop(n)
    return if (rest.isEmpty() || rest[0] == ' ') n else null
}

private fun isHr(t: String) = t == "---" || t == "***" || t == "___"

/** 表格行：以 | 开头（窄口径，避免把带竖线的散文误判成表格）。 */
private fun isTableRow(t: String) = t.startsWith("|") && t.length > 1

/** 分隔行：每个格子都是 `:?-+:?` 且至少一个 -。 */
private fun isTableSeparator(t: String): Boolean {
    if (!t.contains("-") || !t.contains("|")) return false
    return splitRow(t).isNotEmpty() &&
        splitRow(t).all { Regex("^:?-+:?$").matches(it.replace(" ", "")) }
}

/** 按竖线切格；去掉首尾包裹竖线与空白。 */
private fun splitRow(t: String): List<String> {
    var s = t
    if (s.startsWith("|")) s = s.substring(1)
    if (s.endsWith("|")) s = s.substring(0, s.length - 1)
    return s.split("|").map { it.trim() }
}

private fun isBullet(t: String) = t.startsWith("- ") || t.startsWith("* ") || t.startsWith("+ ")
private fun isOrdered(t: String) = Regex("""^\d{1,9}[.)]\s+.+""").matches(t)
