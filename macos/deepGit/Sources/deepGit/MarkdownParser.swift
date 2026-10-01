// MarkdownParser.swift — MarkdownView 的块级解析（纯函数，无视图依赖）。
//
// 【为什么抽出来】
// 1. 性能：`blocks` 原本是 `MarkdownView` 的 **computed property**，
//    于是 `body` 每求值一次就把整篇文档全量重解析一次 ——
//    200KB 的 README 在滚动/布局时是**每帧**的主线程工作。
//    抽成纯函数后，视图可以在构造时解析一次并缓存。
// 2. 可测：块级解析不依赖 SwiftUI，才可能被单独编译测试
//    （MarkdownView.swift 本身 import SwiftUI，测不了纯逻辑）。
//
// 解析只覆盖常见块级语法，不追求完整 GFM；行内标记剥离记号后按纯文本展示。
import Foundation

enum MarkdownParser {
    /// 块级语法。放在 parser 里而不是视图里，视图只负责渲染。
    enum Block {
        case heading(Int, String)
        case paragraph([String])
        case bullet([String])
        case numbered([String])
        case quote([String])
        case code(String)
        case divider
        case table([String])
    }

    /// 解析整篇文档。纯函数：同输入同输出，不持有状态。
    ///
    /// 记忆化刻意做得很小（4 条）且**不跨文档**：
    /// 缓存无上限会把用户读过的每一篇 README 都留在内存里，
    /// 而收益只体现在「同一个视图被反复构造」这一种情况上。
    private static var memo: [(key: Int, value: [Block])] = []

    static func blocks(_ text: String) -> [Block] {
        let key = text.hashValue
        if let hit = memo.first(where: { $0.key == key }) { return hit.value }
        let parsed = parse(text)
        memo.append((key, parsed))
        if memo.count > 4 { memo.removeFirst(memo.count - 4) }
        return parsed
    }

    private static func parse(_ text: String) -> [Block] {
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
                if let level = MarkdownParser.headingLevel(trimmed) {
                    // ⚠️ dropFirst(level) 只去掉 # 号，**# 后面的空格留了下来** ——
                    // 于是每个标题文本都带一个前导空格，渲染出来全部往右缩进一点。
                    // 抽文件做检查时被断言逮到（这正是把解析器抽成可测纯函数的收益）。
                    let title = String(trimmed.dropFirst(level))
                        .trimmingCharacters(in: .whitespaces)
                    out.append(.heading(level, MarkdownParser.stripInline(title)))
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
                        body.append(MarkdownParser.stripInline(lines[i].trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces)))
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
                            items.append(MarkdownParser.stripInline(String(t.dropFirst(2))))
                            i += 1
                        } else if t.hasPrefix("  ") && !t.isEmpty && !items.isEmpty {
                            // 二级缩进续行并入上一项
                            items[items.count - 1] += " " + MarkdownParser.stripInline(t.trimmingCharacters(in: .whitespaces))
                            i += 1
                        } else {
                            break
                        }
                    }
                    out.append(.bullet(items))
                    continue
                }

                // 有序列表
                if let _ = MarkdownParser.numberedPrefix(trimmed) {
                    var items: [String] = []
                    while i < lines.count {
                        let t = lines[i].trimmingCharacters(in: .whitespaces)
                        if let n = MarkdownParser.numberedPrefix(t) {
                            var idx = t.startIndex
                            while idx < t.endIndex, t[idx].isNumber || t[idx] == "." { idx = t.index(after: idx) }
                            items.append("\(n). " + MarkdownParser.stripInline(String(t[idx...]).trimmingCharacters(in: .whitespaces)))
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
                    if t.isEmpty || MarkdownParser.headingLevel(t) != nil || t.hasPrefix("```") || t.hasPrefix(">") || t.hasPrefix("- ") || t.hasPrefix("* ") || t == "---" {
                        break
                    }
                    para.append(MarkdownParser.stripInline(t))
                    i += 1
                }
                if !para.isEmpty {
                    out.append(.paragraph(para))
                }
            }
            return out
        }

        private static func headingLevel(_ s: String) -> Int? {
            var n = 0
            for ch in s {
                if ch == "#" { n += 1 } else { break }
            }
            if n >= 1 && n <= 6 && s.count > n && s[s.index(s.startIndex, offsetBy: n)] == " " {
                return n
            }
            return nil
        }

        private static func numberedPrefix(_ s: String) -> Int? {
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
        private static func stripInline(_ s: String) -> String {
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
}
