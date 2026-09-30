// MarkdownView.swift — 轻量 Markdown 渲染（README / AGENTS 平铺用）。
//
// 【边界】纯客户端展示层：解析只覆盖常见块级语法（标题/列表/代码块/引用/表格提示/分隔线），
// 不追求完整 GFM；引擎侧不参与渲染。行内标记（**bold**、`code`、链接）剥离记号后按纯文本展示。
import SwiftUI

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: 块级解析

    private enum Block {
        case heading(Int, String)
        case paragraph([String])
        case bullet([String])
        case numbered([String])
        case quote([String])
        case code(String)
        case divider
        case table([String])
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // 代码块
            if trimmed.hasPrefix("```") {
                var body: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    body.append(lines[i])
                    i += 1
                }
                i += 1  // 跳过收尾 ```
                out.append(.code(body.joined(separator: "\n")))
                continue
            }

            // 标题
            if let level = headingLevel(trimmed) {
                out.append(.heading(level, stripInline(String(trimmed.dropFirst(level)))))
                i += 1
                continue
            }

            // 分隔线
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                out.append(.divider)
                i += 1
                continue
            }

            // 表格：含 | 的连续行整块按等宽处理
            if trimmed.contains("|") && i + 1 < lines.count
                && lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                var rows: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(lines[i])
                    i += 1
                }
                out.append(.table(rows))
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                var body: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    body.append(stripInline(lines[i].trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                out.append(.quote(body))
                continue
            }

            // 无序列表（含托管区域标记行）
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                        items.append(stripInline(String(t.dropFirst(2))))
                        i += 1
                    } else if t.hasPrefix("  ") && !t.isEmpty && !items.isEmpty {
                        // 二级缩进续行并入上一项
                        items[items.count - 1] += " " + stripInline(t.trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else {
                        break
                    }
                }
                out.append(.bullet(items))
                continue
            }

            // 有序列表
            if let _ = numberedPrefix(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let n = numberedPrefix(t) {
                        var idx = t.startIndex
                        while idx < t.endIndex, t[idx].isNumber || t[idx] == "." { idx = t.index(after: idx) }
                        items.append("\(n). " + stripInline(String(t[idx...]).trimmingCharacters(in: .whitespaces)))
                        i += 1
                    } else {
                        break
                    }
                }
                out.append(.numbered(items))
                continue
            }

            // 普通段落（连续非空行）
            var para: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || headingLevel(t) != nil || t.hasPrefix("```") || t.hasPrefix(">") || t.hasPrefix("- ") || t.hasPrefix("* ") || t == "---" {
                    break
                }
                para.append(stripInline(t))
                i += 1
            }
            if !para.isEmpty {
                out.append(.paragraph(para))
            }
        }
        return out
    }

    private func headingLevel(_ s: String) -> Int? {
        var n = 0
        for ch in s {
            if ch == "#" { n += 1 } else { break }
        }
        if n >= 1 && n <= 6 && s.count > n && s[s.index(s.startIndex, offsetBy: n)] == " " {
            return n
        }
        return nil
    }

    private func numberedPrefix(_ s: String) -> Int? {
        var n = 0
        for ch in s {
            if ch.isNumber { n += 1 } else { break }
        }
        if n > 0 && n < 5 {
            let rest = s.dropFirst(n)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return Int(s.prefix(n))
            }
        }
        return nil
    }

    /// 剥离行内记号：`code` → code；**b** → b；[t](u) → t
    private func stripInline(_ s: String) -> String {
        var t = String(s)
        // 链接 [text](url) → text
        while let start = t.range(of: "[") {
            guard let mid = t.range(of: "](", range: start.upperBound..<t.endIndex),
                  let end = t.range(of: ")", range: mid.upperBound..<t.endIndex) else { break }
            let label = String(t[start.upperBound..<mid.lowerBound])
            t = String(t[..<start.lowerBound]) + label + String(t[end.upperBound...])
        }
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "__", with: "")
        t = t.replacingOccurrences(of: "`", with: "")
        return t
    }

    // MARK: 渲染

    @ViewBuilder
    private func blockView(_ b: Block) -> some View {
        switch b {
        case .heading(let level, let text):
            Text(text)
                .font(.system(size: fontSize(for: level), weight: .semibold, design: .rounded))
                .padding(.top, level <= 2 ? 8 : 4)

        case .paragraph(let lines):
            Text(lines.joined(separator: " "))
                .font(.callout)
                .lineSpacing(4)

        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle().fill(.blue).frame(width: 5, height: 5)
                        Text(item).font(.callout).lineSpacing(3)
                    }
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item).font(.callout).lineSpacing(3)
                }
            }

        case .quote(let lines):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.blue.opacity(0.5))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        Text(l).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 10)
            }

        case .code(let body):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(body)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

        case .divider:
            Divider().padding(.vertical, 3)

        case .table(let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Text(row)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func fontSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 18
        case 3: return 15
        default: return 14
        }
    }
}
