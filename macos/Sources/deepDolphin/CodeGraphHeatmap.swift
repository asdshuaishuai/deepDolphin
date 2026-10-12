// CodeGraphHeatmap.swift — 符号索引热力图的原生 SwiftUI Canvas 驱动。
//
// 形态：treemap（确定性 squarified 布局）——文件瓦片面积 ∝ 行数，颜色 =
// 置信度热力（与引擎 HTML 同一色阶：≥80 青绿 / ≥60 琥珀 / <60 红）。
// 点文件瓦片下钻到该文件的符号层（面积 ∝ 符号体行距），面包屑返回；
// 点符号瓦片 = 选中，右栏详情复用 CodeGraphPage 既有管道（vm.selID）。
//
// 数据：CodeGraphVM 已加载的 GNode 树（graph tree/functions/confidence
// 三路合流），不另起数据源。罚分口径与引擎一致：文件 = 子树疑点权重和；
// confScore = floor(100·20/(20+罚分/n))——confidence.cj 公式 confidenceScore
// 的 Swift 镜像（引擎侧对齐锚点：confidenceScore(20,1)==50）。
//
// 布局纯函数：squarified（Bruls et al.）同输入同输出，零随机零时间。

import SwiftUI

// MARK: - 置信度分数（confidence.cj 公式的 Swift 镜像）

func cgConfScore(_ penalty: Int, _ files: Int) -> Int {
    let n = max(1, files)
    let density = Double(penalty) / Double(n)
    let s = Int((100.0 * 20.0 / (20.0 + density)).rounded(.down))
    return min(100, max(0, s))
}

/// 文件的罚分 = 子树疑点权重和（与引擎 HEAT 表的文件罚分同口径：
/// 大多数 finding 按行号归属到符号体，容器罚分含符号级）。
func cgPenalty(_ n: GNode) -> Int {
    n.subtreeFindings.reduce(0) { $0 + $1.weight }
}

/// 色阶只有一份（与引擎 scoreHex 语义对齐：≥80 绿 / ≥60 黄 / <60 红）。
func cgHeatColor(_ score: Int, dark: Bool) -> Color {
    if score >= 80 {
        return dark ? Color(red: 0.18, green: 0.83, blue: 0.75)
                    : Color(red: 0.05, green: 0.58, blue: 0.53)
    }
    if score >= 60 {
        return dark ? Color(red: 0.98, green: 0.78, blue: 0.14)
                    : Color(red: 0.85, green: 0.47, blue: 0.02)
    }
    return dark ? Color(red: 0.97, green: 0.44, blue: 0.44)
                : Color(red: 0.86, green: 0.15, blue: 0.15)
}

// MARK: - squarified treemap（Bruls et al.，确定性）

enum CGSquarify {
    /// weights 与 items 一一对应；返回与输入同序的矩形数组。
    static func tiles(weights: [Double], in rect: CGRect) -> [CGRect] {
        let total = weights.reduce(0, +)
        guard total > 0, rect.width >= 1, rect.height >= 1 else {
            return Array(repeating: .zero, count: weights.count)
        }
        let area = weights.map { $0 / total * Double(rect.width * rect.height) }
        var out = [CGRect](repeating: .zero, count: weights.count)
        var remaining = rect
        var start = 0
        while start < weights.count {
            // 行铺在剩余矩形的短边上（height >= width → 行横铺在顶部）
            let layRow = remaining.height >= remaining.width
            let side = Double(layRow ? remaining.width : remaining.height)
            var count = 0
            var rowArea = 0.0
            var best = Double.greatestFiniteMagnitude
            while start + count < weights.count {
                let newRow = rowArea + area[start + count]
                let thickness = newRow / max(0.001, side)
                var worst = 0.0
                for k in 0...count {
                    let len = area[start + k] / max(0.001, newRow) * side
                    let ratio = max(len / thickness, thickness / len)
                    worst = max(worst, ratio)
                }
                if count == 0 || worst <= best {
                    best = worst
                    rowArea = newRow
                    count += 1
                } else {
                    break
                }
            }
            if count == 0 { count = 1; rowArea = area[start] }
            let thickness = CGFloat(rowArea / max(0.001, side))
            var offset = 0.0
            for k in 0..<count {
                let len = CGFloat(area[start + k] / max(0.001, rowArea) * side)
                let r: CGRect
                if layRow {
                    r = CGRect(x: remaining.minX + offset, y: remaining.minY,
                               width: len, height: thickness)
                } else {
                    r = CGRect(x: remaining.minX, y: remaining.minY + offset,
                               width: thickness, height: len)
                }
                out[start + k] = r
                offset += len
            }
            remaining = layRow
                ? CGRect(x: remaining.minX, y: remaining.minY + thickness,
                         width: remaining.width, height: max(0, remaining.height - thickness))
                : CGRect(x: remaining.minX + thickness, y: remaining.minY,
                         width: max(0, remaining.width - thickness), height: remaining.height)
            start += count
        }
        return out
    }
}

// MARK: - 瓦片构建（纯函数：树 + 钻取层级 + 画布尺寸 → 瓦片）

struct CGTile: Identifiable {
    let node: GNode
    let rect: CGRect
    let score: Int
    var id: String { node.id }
}

enum CGHeatLayout {
    /// 瓦片权重：文件 ∝ 行数；符号 ∝ 符号体行距（下一符号声明行 − 本行，
    /// 末尾到文件行数）。纯函数（非隔离）：调用方在 MainActor 取好节点。
    static func weights(for nodes: [GNode]) -> [Double] {
        guard let first = nodes.first else { return [] }
        if first.kind == .sym {
            let fileLines = max(1, first.parent?.lines ?? 0)
            return nodes.enumerated().map { i, s in
                let end = (i + 1 < nodes.count) ? nodes[i + 1].declLine - 1 : fileLines
                return Double(max(1, end - s.declLine + 1))
            }
        }
        return nodes.map { Double(max(1, $0.lines)) }
    }

    static func tiles(nodes: [GNode], size: CGSize) -> [CGTile] {
        guard !nodes.isEmpty, size.width > 20, size.height > 20 else { return [] }
        let rects = CGSquarify.tiles(weights: weights(for: nodes), in: CGRect(origin: .zero, size: size))
        return zip(nodes, rects).map { node, rect in
            CGTile(node: node, rect: rect, score: cgConfScore(cgPenalty(node), 1))
        }
        .filter { $0.rect.width > 2 && $0.rect.height > 2 }
    }
}

// MARK: - 视图

struct CodeGraphHeatView: View {
    @ObservedObject var vm: CodeGraphVM
    var onSelect: (GNode) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            if let f = vm.heatDrill {
                crumb(f)
                Divider()
            }
            GeometryReader { geo in
                // 取数在 MainActor（vm.heatNodes），布局是纯函数
                let nodes = vm.heatNodes()
                let tiles = CGHeatLayout.tiles(nodes: nodes, size: geo.size)
                Canvas { ctx, _ in
                    draw(tiles, into: &ctx)
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    tap(v.location, tiles: tiles)
                })
            }
            Divider()
            legend
        }
    }

    private func crumb(_ f: GNode) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Button {
                vm.heatDrill = nil
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("cgraph.list"))
            .accessibilityLabel(A11y.label(L10n.t("cgraph.list")))
            Image(systemName: "doc.text").font(.caption).foregroundStyle(.tertiary)
            Text(f.name).font(.system(.caption, design: .monospaced)).lineLimit(1)
            Spacer()
            Text("⚠\(cgPenalty(f))").font(.caption.monospacedDigit())
                .foregroundStyle(cgHeatColor(cgConfScore(cgPenalty(f), 1), dark: scheme == .dark))
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
    }

    private func draw(_ tiles: [CGTile], into ctx: inout GraphicsContext) {
        let dark = scheme == .dark
        for t in tiles {
            let heat = cgHeatColor(t.score, dark: dark)
            ctx.fill(Path(t.rect), with: .color(heat.opacity(0.20)))
            ctx.stroke(Path(t.rect.insetBy(dx: 0.5, dy: 0.5)),
                       with: .color(heat.opacity(0.85)), lineWidth: 1)
            if vm.selID == t.node.id {
                ctx.stroke(Path(t.rect.insetBy(dx: 1.5, dy: 1.5)),
                           with: .color(.accentColor), lineWidth: 2)
            }
            let w = t.rect.width, h = t.rect.height
            if w > 64 && h > 34 {
                ctx.draw(Text(t.node.name)
                    .font(.caption2).foregroundStyle(dark ? Color.white : Color.black.opacity(0.85)),
                    at: CGPoint(x: t.rect.minX + 8, y: t.rect.minY + 5), anchor: .topLeading)
                ctx.draw(Text("⚠\(t.node.rollN)")
                    .font(.caption2).foregroundStyle(Color(white: dark ? 0.72 : 0.38)),
                    at: CGPoint(x: t.rect.minX + 8, y: t.rect.maxY - 5), anchor: .bottomLeading)
            }
            if w > 40 && h > 20 {
                ctx.draw(Text(String(t.score))
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(heat),
                    at: CGPoint(x: t.rect.maxX - 8, y: t.rect.minY + 5), anchor: .topTrailing)
            }
        }
    }

    private func tap(_ p: CGPoint, tiles: [CGTile]) {
        // 命中测试从最上层（后画的）往回找：小瓦片优先
        for t in tiles.reversed() where t.rect.contains(p) {
            if t.node.kind == .file {
                vm.heatDrill = t.node
            } else {
                vm.selID = t.node.id
                onSelect(t.node)
            }
            return
        }
    }

    private var legend: some View {
        HStack(spacing: DSSpacing.md) {
            ForEach([(80, 100, "高 ≥80"), (60, 79, "中 60–79"), (0, 59, "低 <60")], id: \.0) { lo, hi, label in
                HStack(spacing: DSSpacing.xs) {
                    Circle()
                        .fill(cgHeatColor((lo + hi) / 2, dark: scheme == .dark))
                        .frame(width: 8, height: 8)
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("面积 ∝ 行数 · 颜色 = 置信度指数")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
    }
}
