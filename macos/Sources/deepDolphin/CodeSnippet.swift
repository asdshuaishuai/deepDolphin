// CodeSnippet.swift — 低置信度代码块的实码展示。
//
// 置信度页 / 补丁体检页共用：给 (项目路径, 文件, 行号) 或 diff 文本，
// 展示带行号的代码片段并高亮问题行。「低置信度」不能只给一句元数据——
// 用户必须看到代码本身才能判断该不该信（审查定稿的要求）。
import SwiftUI

// MARK: - 片段模型

struct CodeSnippetLine: Identifiable {
    let lineNumber: Int
    let text: String
    let isHit: Bool
    var id: Int { lineNumber }
}

enum CodeSnippet {
    /// 从磁盘读源码，取 line ± context 的片段。读不到返回 nil（调用方显示占位）。
    static func fromDisk(projectPath: String, file: String, line: Int, context: Int = 3) -> [CodeSnippetLine]? {
        let path = projectPath.hasSuffix("/")
            ? projectPath + file
            : projectPath + "/" + file
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return slice(raw, around: line, context: context)
    }

    /// 从 unified diff 文本提取某文件某新增行所在 hunk（只保留 + 行，含上下文）。
    /// 补丁体检的低置信度实体都落在新增行上。
    static func fromDiff(_ diff: String, file: String, line: Int, context: Int = 2) -> [CodeSnippetLine]? {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var currentFile = ""
        var hunk: [CodeSnippetLine] = []
        var newLine = 0
        var inTargetHunk = false
        for l in lines {
            if l.hasPrefix("diff --git") || l.hasPrefix("index ") {
                currentFile = ""
                inTargetHunk = false
                continue
            }
            if l.hasPrefix("+++ b/") || l.hasPrefix("+++ ") {
                currentFile = String(l.dropFirst(l.hasPrefix("+++ b/") ? 6 : 4))
                    .trimmingCharacters(in: .whitespaces)
                continue
            }
            if l.hasPrefix("@@") {
                newLine = parseNewStart(l)
                inTargetHunk = (currentFile == file)
                    && line >= newLine - context && line <= newLine + 400
                if inTargetHunk { hunk = [] }
                continue
            }
            guard inTargetHunk, currentFile == file else { continue }
            if l.hasPrefix("+") {
                let n = newLine
                hunk.append(CodeSnippetLine(lineNumber: n, text: String(l.dropFirst()), isHit: n == line))
                newLine += 1
            } else if l.hasPrefix(" ") {
                hunk.append(CodeSnippetLine(lineNumber: newLine, text: String(l.dropFirst()), isHit: false))
                newLine += 1
            }
            // - 行跳过（旧版本内容，不进新文件行号流）
        }
        guard !hunk.isEmpty else { return nil }
        // 只保留命中行 ± context
        guard let hitIdx = hunk.firstIndex(where: { $0.isHit }) else { return hunk }
        let lo = max(hunk.startIndex, hitIdx - context)
        let hi = min(hunk.index(before: hunk.endIndex), hitIdx + context)
        return Array(hunk[lo...hi])
    }

    /// `@@ -3,7 +41,9 @@ ...` 里的新起始行。
    static func parseNewStart(_ header: String) -> Int {
        // 形如 @@ -a,b +c,d @@：取 + 后到逗号（或空格）的数字
        guard let plus = header.firstIndex(of: "+") else { return 0 }
        var digits = ""
        for ch in header[header.index(after: plus)...] {
            if ch.isNumber { digits.append(ch) } else { break }
        }
        return Int(digits) ?? 0
    }

    private static func slice(_ raw: String, around line: Int, context: Int) -> [CodeSnippetLine] {
        let all = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lo = max(1, line - context)
        let hi = min(all.count, line + context)
        guard line >= 1 && line <= all.count else { return [] }
        return (lo...hi).map { n in
            CodeSnippetLine(lineNumber: n, text: all[n - 1], isHit: n == line)
        }
    }
}

// MARK: - 视图

struct CodeSnippetView: View {
    let lines: [CodeSnippetLine]
    /// 源码语言（引擎 functionGraph.lang；nil = 按仓颉兜底）
    var lang: String = "cangjie"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    let text = lines.map { String(format: "%4d  %@", $0.lineNumber, $0.text) }
                        .joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help(L10n.t("snippet.copy"))
                .accessibilityLabel(A11y.label(L10n.t("snippet.copy")))
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.top, DSSpacing.xs)
            ForEach(lines) { l in
                HStack(alignment: .top, spacing: DSSpacing.sm) {
                    Text("\(l.lineNumber)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(l.isHit ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                        .frame(width: 34, alignment: .trailing)
                    Text(SyntaxHighlight.highlight(l.text, lang: lang))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, 1)
                .background(l.isHit ? Color.orange.opacity(0.12) : .clear)
            }
            .padding(.bottom, DSSpacing.xs)
        }
        .background(.quaternary.opacity(0.3), in: DSRect.shape(DSRadius.control))
    }
}

// MARK: - 可展开的发现行（收起=位置告知，点击=展开详情与代码块）

/// 一条置信度发现的**披露式**行。默认收起：只告知「哪里有什么问题」；
/// 点击展开：证据 + 实码片段（惰性从磁盘读，展开那一刻才读）。
/// 低置信度内容不直接铺开——列表要先能扫，细节按需展开。
struct FindingDisclosureRow: View {
    let projectPath: String
    let kindLabel: String
    let file: String
    let line: Int
    let symbol: String
    let weight: Int
    let evidence: String

    @State private var expanded = false
    @State private var lines: [CodeSnippetLine]?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Button {
                expanded.toggle()
                if expanded && lines == nil {
                    lines = CodeSnippet.fromDisk(projectPath: projectPath, file: file, line: line)
                }
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    Text("\(weight)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(weight >= 10 ? Color.red : weight >= 6 ? Color.orange : Color.gray,
                                    in: Capsule())
                    Text(kindLabel)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(file):\(line)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !symbol.isEmpty {
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, DSSpacing.xl)
            }
            if expanded {
                if !evidence.isEmpty {
                    Text(evidence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let lines {
                    CodeSnippetView(lines: lines)
                } else {
                    Text(L10n.t("snippet.unreadable"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(DSSpacing.sm)
        .background(.quaternary.opacity(0.35), in: DSRect.shape(DSRadius.control))
    }
}

// MARK: - Swift 原生多语言语法高亮（客户端独立实现，与引擎 HTML 高亮无关）

/// 客户端自己的高亮引擎：`AttributedString` + 按语言查表。
/// 消费引擎 `functionGraph.lang` 字段，但着色实现完全是 SwiftUI 的。
/// 四类 token：关键字（紫）/ 字符串（绿）/ 注释（灰）/ 数字（黄）。
enum SyntaxHighlight {
    /// 各语言关键字集（与引擎 detectLang 的 9 种语言对齐）。
    static let keywords: [String: Set<String>] = [
        "cangjie": ["package","import","class","struct","enum","interface","extend","func","let","var","const",
                   "match","case","if","else","while","for","return","try","catch","throw","true","false",
                   "this","super","init","override","public","private","internal","protected","static",
                   "abstract","open","where","in","as","is","spawn","prop","volatile","unsafe","mut","ref",
                   "final","sealed","typealias","operator","infix"],
        "swift": ["import","class","struct","enum","protocol","func","let","var","if","else","guard","while",
                  "for","return","try","catch","throw","true","false","self","super","init","override",
                  "public","private","internal","fileprivate","open","static","final","where","in","as","is",
                  "extension","weak","unowned","lazy","mutating","didSet","willSet","some","any","async",
                  "await","throws","rethrows","case","switch","default","break","continue","fallthrough"],
        "ts": ["import","export","from","class","extends","implements","interface","type","enum","function",
               "const","let","var","if","else","while","for","of","in","return","try","catch","throw",
               "true","false","null","undefined","this","super","new","delete","typeof","instanceof","void",
               "async","await","yield","static","get","set","public","private","protected","readonly",
               "abstract","as","is","break","continue","case","switch","default","do"],
        "python": ["import","from","class","def","lambda","if","elif","else","while","for","in","return",
                   "try","except","finally","raise","True","False","None","self","super","global","nonlocal",
                   "yield","async","await","with","as","pass","break","continue","and","or","not","is","del"],
        "go": ["package","import","func","var","const","type","struct","interface","map","chan","go","defer",
               "if","else","for","range","return","switch","case","default","true","false","nil","break",
               "continue","goto","fallthrough","select"],
        "rust": ["fn","let","mut","const","struct","enum","trait","impl","for","in","if","else","while","loop",
                 "match","return","true","false","self","Self","super","crate","mod","pub","use","extern","as",
                 "where","async","await","move","ref","dyn","type","unsafe","break","continue"],
        "java": ["package","import","class","interface","enum","record","extends","implements","public","private",
                 "protected","static","final","abstract","void","int","long","double","float","boolean","char",
                 "byte","short","if","else","while","for","return","try","catch","finally","throw","throws",
                 "true","false","null","this","super","new","instanceof","synchronized","volatile","transient",
                 "default","sealed","permits","var","break","continue","do","switch","case"],
        "kotlin": ["package","import","class","object","interface","fun","val","var","if","else","when","while",
                   "for","return","try","catch","finally","throw","true","false","null","this","super","init",
                   "override","open","abstract","final","sealed","data","companion","internal","private",
                   "protected","public","lateinit","lazy","by","is","as","in","out","reified","suspend",
                   "inline","operator","infix","external","const","break","continue","do"],
        "c": ["auto","break","case","char","const","continue","default","do","double","else","enum","extern",
              "float","for","goto","if","inline","int","long","register","restrict","return","short","signed",
              "sizeof","static","struct","switch","typedef","union","unsigned","void","volatile","while",
              "class","public","private","protected","virtual","override","final","template","typename",
              "namespace","using","new","delete","nullptr","constexpr","noexcept"],
    ]

    /// 单语言注释前缀（python/shell 用 #，其余 //）。
    static func lineCommentPrefix(for lang: String) -> String {
        return lang == "python" ? "#" : "//"
    }

    /// 高亮一行代码 → AttributedString（四类 token 着色）。
    /// O(n) 单遍扫描；Swift Character 索引天然处理多字节字符。
    static func highlight(_ line: String, lang: String) -> AttributedString {
        var result = AttributedString(line.isEmpty ? " " : line)
        let kws = keywords[lang] ?? keywords["cangjie"]!
        let cmPrefix = lineCommentPrefix(for: lang)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // 注释行：整行灰
        if trimmed.hasPrefix(cmPrefix) {
            result.foregroundColor = .secondary
            return result
        }

        let chars = Array(line)
        var i = 0

        func colorRange(_ from: Int, _ to: Int, _ color: Color) {
            guard from < to, to <= chars.count else { return }
            let s = result.index(result.startIndex, offsetByCharacters: from)
            let e = result.index(s, offsetByCharacters: to - from)
            result[s..<e].foregroundColor = color
        }

        func isIdentChar(_ c: Character) -> Bool { c.isLetter || c == "_" || c.isNumber }
        func isIdentStart(_ c: Character) -> Bool { c.isLetter || c == "_" }

        while i < chars.count {
            let c = chars[i]
            // 字符串（绿）
            if c == "\"" || c == "'" {
                var j = i + 1
                while j < chars.count && chars[j] != c { j += 1 }
                colorRange(i, min(j + 1, chars.count), .green)
                i = j + 1
                continue
            }
            // 行内注释（// 或 #，灰到行尾）
            if i + 1 < chars.count && c == "/" && chars[i + 1] == "/" {
                colorRange(i, chars.count, .secondary)
                break
            }
            if c == "#" && lang == "python" {
                colorRange(i, chars.count, .secondary)
                break
            }
            // 标识符（关键字紫）
            if isIdentStart(c) {
                var j = i
                while j < chars.count && isIdentChar(chars[j]) { j += 1 }
                let word = String(chars[i..<j])
                if kws.contains(word) {
                    colorRange(i, j, .purple)
                }
                i = j
                continue
            }
            // 数字（黄）
            if c.isNumber {
                var j = i
                while j < chars.count && (chars[j].isNumber || chars[j].isHexDigit || "xX._".contains(chars[j])) { j += 1 }
                colorRange(i, j, .yellow)
                i = j
                continue
            }
            i += 1
        }
        return result
    }
}
