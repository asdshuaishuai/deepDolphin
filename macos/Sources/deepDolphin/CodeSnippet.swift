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
                    Text(l.text.isEmpty ? " " : l.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(l.isHit ? .primary : .secondary)
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
