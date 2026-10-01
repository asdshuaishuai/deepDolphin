// MarkdownView.swift — 轻量 Markdown 渲染（README / AGENTS 平铺用）。
//
// 【边界】纯客户端展示层：解析只覆盖常见块级语法（标题/列表/代码块/引用/表格提示/分隔线），
// 不追求完整 GFM；引擎侧不参与渲染。行内标记（**bold**、`code`、链接）剥离记号后按纯文本展示。
import SwiftUI

struct MarkdownView: View {
    let text: String
    /// 解析结果**存下来**，不是每次 `body` 现算。
    ///
    /// 原来 `blocks` 是 computed property，而 `body` 在滚动、布局、
    /// 状态变化时都会重新求值 —— 于是 200KB 的 README 每帧全量重解析一次。
    /// 现在只在视图构造时解析一次（`MarkdownParser` 内部还有 4 条记忆化兜底），
    /// `body` 里只做渲染。
    private let parsed: [MarkdownParser.Block]

    init(text: String) {
        self.text = text
        self.parsed = MarkdownParser.blocks(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(parsed.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }


    // MARK: 渲染

    @ViewBuilder
    private func blockView(_ b: MarkdownParser.Block) -> some View {
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
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle().fill(.blue).frame(width: 5, height: 5)
                        Text(item).font(.callout).lineSpacing(3)
                    }
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item).font(.callout).lineSpacing(3)
                }
            }

        case .quote(let lines):
            HStack(alignment: .top, spacing: 0) {
                DSRect.shape(DSRadius.chip)
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
            .surface()

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
            .surface()
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
