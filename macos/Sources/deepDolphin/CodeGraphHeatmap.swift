// CodeGraphHeatmap.swift — 符号索引热力图的原生 SwiftUI Canvas 驱动
//（形态与引擎 HTML 交付物最终版完全对齐：有序网格卡片 + 关系聚类）。
//
// 与 HTML 的对齐（逐项）：
//   · 布局 = 分层带（文件/类型/函数）内的有序网格——带内语义排序
//    （文件按名、符号按声明行）+ 关系聚类重心扫描（barySweep 3 轮，
//     强关联卡换到相邻格位），#序号 = 最终排布的阅读序
//   · 卡片 = 圆角矩形：置信度热色填充深度 + 同系边框 + 身份色左条 +
//     大号指数 + 名称 + ⚠ 徽标 + 置信度米条；带疑点的卡虚线边框 + 黄点
//   · 走线 = 通道车道（行隙/带隙内分道并排）+ 列间隙垂直段（被卡挡住
//     才绕行）+ Catmull-Rom 平滑拐弯；线色 = 来源节点身份色；
//     guessed 虚线；箭头指调用方向
//   · 焦点退淡：选中卡片后，无关卡与边退淡，直接相连的满亮
//   · 呼吸只在框体内（填充亮度脉动 + 边框呼吸 + 顶部流光），无外光晕
//   · 下钻：点文件卡 → 该文件的符号层；跨作用域被调方 = 边界卡聚合
//
// reduced-motion / 离屏 harness（staticFrame）直取终帧。布局是确定性
// 纯函数：同数据同画布 ⇒ 同排布。

import SwiftUI

// MARK: - 置信度分数（confidence.cj 公式的 Swift 镜像）

func cgConfScore(_ penalty: Int, _ files: Int) -> Int {
    let n = max(1, files)
    let density = Double(penalty) / Double(n)
    let s = Int((100.0 * 20.0 / (20.0 + density)).rounded(.down))
    return min(100, max(0, s))
}

/// 节点罚分 = 子树疑点权重和（与引擎 HEAT 表的文件罚分同口径）。
func cgPenalty(_ n: GNode) -> Int {
    n.subtreeFindings.reduce(0) { $0 + $1.weight }
}

/// 色阶只有一份（与 HTML confidenceColor 逐字同色）。
func cgHeatColor(_ score: Int) -> Color {
    if score >= 80 { return Color(red: 0.349, green: 0.941, blue: 0.722) }  // #59f0b8
    if score >= 60 { return Color(red: 1.0, green: 0.784, blue: 0.341) }    // #ffc857
    return Color(red: 1.0, green: 0.420, blue: 0.541)                       // #ff6b8a
}

/// 身份色（黄金角 137.5° 色相 + 明暗交替）。
func cgIdColor(_ hue: Int) -> Color {
    let v = hue % 2
    return Color(hue: Double(hue) / 360.0,
                 saturation: 0.62 + Double(v) * 0.16,
                 brightness: 0.52 + Double(v) * 0.14)
}

// MARK: - 卡片模型与布局

struct CGCard: Identifiable {
    let node: GNode
    var x: CGFloat
    var y: CGFloat
    let w: CGFloat
    let h: CGFloat
    let layerIndex: Int
    var rank = 0
    var id: String { node.id }
}

enum CGVisualLayer: Int {
    case files = 1, types = 2, funcs = 3, boundary = 5
    var label: String {
        switch self {
        case .files: return "文件"
        case .types: return "类型"
        case .funcs: return "函数"
        case .boundary: return "跨作用域边界"
        }
    }
}

@MainActor
enum CGLayout {
    static func boxSize(_ n: GNode) -> (CGFloat, CGFloat) {
        switch n.kind {
        case .file: return (194, 88)
        case .boundary: return (166, 66)
        case .type: return (184, 76)
        default: return (184, 76)
        }
    }

    /// 视觉分层：file → FILES；class/struct/enum → TYPES；func → FUNCTIONS；
    /// boundary → 边界带。
    static func layer(_ n: GNode) -> CGVisualLayer {
        switch n.kind {
        case .file: return .files
        case .type: return .types
        case .boundary: return .boundary
        default: return .funcs
        }
    }

    /// 当前层级应铺排的节点 + 跨作用域边界聚合（被调方按文件聚合，
    /// 最多 9 张边界卡，溢出并成一张 +N）。
    static func scopeNodes(vm: CodeGraphVM) -> [GNode] {
        var out = vm.heatNodes()
        guard vm.heatDrill != nil else { return out }   // 文件层：符号的作用域边界
        var agg: [String: (count: Int, w: Int)] = [:]
        let inScope = Set(out.map(\.id))
        for e in vm.symEdges where inScope.contains(e.from) && !inScope.contains(e.to) {
            let file = String(e.to.dropFirst(2))        // 去掉 "f:" 前缀 → 源文件路径
            let old = agg[file] ?? (0, 0)
            agg[file] = (old.count + 1, old.w + e.w)
        }
        let sorted = agg.sorted { $0.value.w != $1.value.w ? $0.value.w > $1.value.w : $0.key < $1.key }
        for item in sorted.prefix(9) {
            let b = GNode(kind: .boundary, id: "cgx:" + item.key,
                          name: "↗ " + (item.key as NSString).lastPathComponent)
            b.path = item.key
            b.rollN = item.value.count   // 该文件被当前作用域引用的次数
            b.rollW = min(8, item.value.w)
            out.append(b)
        }
        if sorted.count > 9 {
            let b = GNode(kind: .boundary, id: "cgx:__more", name: "↗ +\(sorted.count - 9)")
            out.append(b)
        }
        return out
    }

    /// 有序网格铺排 + 关系聚类重心扫描（HTML layoutGraph/barySweep 移植）。
    static func layout(vm: CodeGraphVM, nodes: [GNode], in size: CGSize) -> [CGCard] {
        guard !nodes.isEmpty, size.width > 60, size.height > 60 else { return [] }
        // 分层带
        var bands: [(layer: CGVisualLayer, cards: [GNode])] = []
        for n in nodes {
            let l = layer(n)
            if let i = bands.firstIndex(where: { $0.layer == l }) { bands[i].cards.append(n) }
            else { bands.append((l, [n])) }
        }
        bands.sort { $0.layer.rawValue < $1.layer.rawValue }
        // 带内语义排序：符号按声明行，其余按名
        for i in bands.indices {
            bands[i].cards.sort { a, b in
                if a.kind == .sym {
                    if a.declLine != b.declLine { return a.declLine < b.declLine }
                }
                return a.name < b.name
            }
        }
        let GAPX: CGFloat = 78, GAPY: CGFloat = 84
        var maxW: CGFloat = 120, maxH: CGFloat = 70
        for b in bands { for n in b.cards {
            let s = boxSize(n)
            maxW = max(maxW, s.0); maxH = max(maxH, s.1)
        } }
        let cellW = maxW + GAPX, cellH = maxH + GAPY
        let left: CGFloat = 40
        var grids: [(cols: Int, rows: Int, w: CGFloat, h: CGFloat)] = []
        for b in bands {
            let cols = max(1, min(b.cards.count, Int((Double(b.cards.count) * 1.7).squareRoot().rounded(.up))))
            let rows = (b.cards.count + cols - 1) / cols
            grids.append((cols, rows, left * 2 + CGFloat(cols) * cellW - GAPX,
                          40 + CGFloat(rows) * cellH - GAPY + 70))
        }
        let worldW = max(size.width - 40, grids.map(\.w).max() ?? 0)
        let worldH = max(size.height - 20,
                         CGFloat(bands.count > 1 ? 84 * (bands.count - 1) : 0)
                         + grids.reduce(0) { $0 + $1.h } + 60)
        var cards: [CGCard] = []
        var laneY: CGFloat = 30
        for (gi, b) in bands.enumerated() {
            let g = grids[gi]
            let gridW = CGFloat(g.cols) * cellW - GAPX
            let offX = max(left, (worldW - gridW) / 2)
            for (i, n) in b.cards.enumerated() {
                let s = boxSize(n)
                let col = i % g.cols, row = i / g.cols
                cards.append(CGCard(node: n,
                    x: offX + CGFloat(col) * cellW + (cellW - GAPX - s.0) / 2,
                    y: laneY + 40 + CGFloat(row) * cellH + (cellH - GAPY - s.1) / 2,
                    w: s.0, h: s.1, layerIndex: gi))
            }
            laneY += g.h + (bands.count > 1 ? 84 : 0)
        }
        // 关系聚类重心扫描（3 轮：行内按邻居 x 重心、列内按邻居 y 重心）
        barySweep(vm: vm, cards: &cards, worldW: worldW, cellW: cellW, cellH: cellH, left: left, passes: 3)
        // #序号 = 最终排布的阅读序（带内行主序）
        for gi in bands.indices {
            let inBand = cards.filter { $0.layerIndex == gi }
                .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            for (i, c) in inBand.enumerated() {
                if let k = cards.firstIndex(where: { $0.id == c.id }) { cards[k].rank = i + 1 }
            }
        }
        return cards
    }

    private enum CGAxis { case x, y }

    /// 关系聚类重心扫描：格位对换（不破坏网格工整），强关联卡相邻。
    static func barySweep(vm: CodeGraphVM, cards: inout [CGCard], worldW: CGFloat,
                          cellW: CGFloat, cellH: CGFloat, left: CGFloat, passes: Int) {
        func bary(_ id: String, _ axis: CGAxis, cards: [CGCard]) -> CGFloat {
            var sum: CGFloat = 0, w: CGFloat = 0
            let selfCard = cards.first { $0.id == id }
            for e in vm.bubbleEdges() {
                var other: String?
                if e.from == id { other = e.to } else if e.to == id { other = e.from }
                guard let oid = other, let q = cards.first(where: { $0.id == oid }) else { continue }
                let weight = CGFloat(max(1, e.w))
                sum += (axis == .x ? q.x + q.w / 2 : q.y + q.h / 2) * weight
                w += weight
            }
            guard w > 0, let s = selfCard else {
                return axis == .x ? (selfCard?.x ?? 0) + (selfCard?.w ?? 0) / 2 : (selfCard?.y ?? 0)
            }
            return axis == .x ? sum / w - s.w / 2 : sum / w - s.h / 2
        }
        for _ in 0..<passes {
            // 行内重排 x
            var rows: [Int: [CGCard]] = [:]
            for c in cards { rows[Int(c.y / 10), default: []].append(c) }
            for (_, row) in rows {
                guard row.count > 1 else { continue }
                let slots = row.map(\.x).sorted()
                let ordered = row.sorted { bary($0.id, .x, cards: row) < bary($1.id, .x, cards: row) }
                for (i, c) in ordered.enumerated() {
                    if let k = cards.firstIndex(where: { $0.id == c.id }) { cards[k].x = slots[i] }
                }
            }
            // 列内重排 y
            var cols: [Int: [CGCard]] = [:]
            for c in cards { cols[Int(c.x / 10), default: []].append(c) }
            for (_, col) in cols {
                guard col.count > 1 else { continue }
                let slots = col.map(\.y).sorted()
                let ordered = col.sorted { bary($0.id, .y, cards: col) < bary($1.id, .y, cards: col) }
                for (i, c) in ordered.enumerated() {
                    if let k = cards.firstIndex(where: { $0.id == c.id }) { cards[k].y = slots[i] }
                }
            }
        }
    }
}

// MARK: - 视图

struct CodeGraphHeatView: View {
    @ObservedObject var vm: CodeGraphVM
    var onSelect: (GNode) -> Void
    var staticFrame = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?

    private var animated: Bool { !staticFrame && !reduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            if let f = vm.heatDrill {
                crumb(f)
                Divider()
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { (tl: TimelineViewDefaultContext) in
                GeometryReader { geo in
                    // 布局/走线按（层级 + 画布尺寸 + 边数）缓存在 VM：
                    // 30fps 重绘只重画时变项，重心扫描与走线不每帧重跑
                    let grid = vm.heatGrid(size: geo.size)
                    let cards = grid.cards
                    let routes = grid.routes
                    let now = timelineDelta(tl)
                    Canvas { ctx, _ in
                        draw(now: now, cards: cards, routes: routes, into: &ctx, canvas: geo.size)
                    }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in
                        tap(v.location, cards: cards)
                    })
                }
            }
            Divider()
            legend
        }
        .onChange(of: vm.heatDrill?.id) { _ in
            startedAt = animated ? nil : Date(timeIntervalSinceReferenceDate: 0)
        }
    }

    private func timelineDelta(_ tl: TimelineViewDefaultContext) -> Double {
        if staticFrame || reduceMotion { return 10 }
        if startedAt == nil {
            DispatchQueue.main.async { startedAt = tl.date }
            return 0
        }
        return tl.date.timeIntervalSince(startedAt ?? tl.date)
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
                .foregroundStyle(cgHeatColor(cgConfScore(cgPenalty(f), 1)))
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
    }

    // MARK: 绘制

    private func draw(now: Double, cards: [CGCard], routes: [CGEdgeRoute],
                      into ctx: inout GraphicsContext, canvas: CGSize) {
        let byId = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        // 边（画在卡片下层；穿过卡区的部分被卡片盖住）
        for (i, r) in routes.enumerated() {
            guard let a = byId[r.from], let b = byId[r.to] else { continue }
            let ecol = cgIdColor(a.node.hue)
            let lit = vm.selID == r.from || vm.selID == r.to
            let fade: CGFloat = vm.selID != r.from && vm.selID != r.to && vm.selID != nil ? 0.15 : 1
            let pulse = animated ? 0.5 + 0.5 * sin(now * 1.5 + Double(i) * 0.73) : 0.2
            var line = Path()
            line.move(to: r.smoothed[0])
            for p in r.smoothed.dropFirst() { line.addLine(to: p) }
            ctx.stroke(line,
                       with: .color(ecol.opacity(fade * (lit ? 0.92 : 0.42 + pulse * 0.16))),
                       style: StrokeStyle(lineWidth: (lit ? 2.4 : min(2.2, 0.9 + Double(r.w) * 0.14 + pulse * 0.25)),
                                          lineCap: .round,
                                          dash: r.tier == "guessed" ? [5, 4] : [],
                                          dashPhase: animated ? -now * 7 : 0))
            // 箭头（末段方向）
            if let lastP = r.smoothed.last, r.smoothed.count >= 2 {
                let prev = r.smoothed[r.smoothed.count - 2]
                let ang = atan2(lastP.y - prev.y, lastP.x - prev.x)
                var arrow = Path()
                arrow.move(to: CGPoint(x: lastP.x, y: lastP.y))
                arrow.addLine(to: CGPoint(x: lastP.x - 7.5 * cos(ang - 0.44), y: lastP.y - 7.5 * sin(ang - 0.44)))
                arrow.addLine(to: CGPoint(x: lastP.x - 7.5 * cos(ang + 0.44), y: lastP.y - 7.5 * sin(ang + 0.44)))
                arrow.closeSubpath()
                ctx.fill(arrow, with: .color(ecol.opacity(fade * 0.9)))
            }
            // 粒子 = 亮头 + 渐淡拖尾（沿线取样一小段，方向一目了然）
            if animated {
                var h = 0
                for ch in r.from.utf8 { h = (h &* 31 &+ Int(ch)) & 0x7fffffff }
                let tt = (now * (0.12 + Double(r.w) * 0.02) + Double(h % 97) / 97.0)
                    .truncatingRemainder(dividingBy: 1)
                if let p = r.sample(CGFloat(tt)), let q = r.sample(CGFloat(max(0, tt - 0.045))) {
                    var trail = Path()
                    trail.move(to: q)
                    trail.addLine(to: p)
                    ctx.stroke(trail, with: .color(ecol.opacity(fade * 0.35)), lineWidth: 1.6)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4)),
                             with: .color(ecol.opacity(fade * 0.6 + pulse * 0.15)))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 0.9, y: p.y - 0.9, width: 1.8, height: 1.8)),
                             with: .color(Color.white.opacity(fade * 0.8)))
                }
            }
        }
        // 卡片
        for c in cards {
            drawCard(c, now: now, into: &ctx)
        }
    }

    private func drawCard(_ c: CGCard, now: Double, into ctx: inout GraphicsContext) {
        let n = c.node
        let dark = true
        _ = dark
        let score = cgConfScore(cgPenalty(n), 1)
        let col = cgHeatColor(score)
        let idCol = cgIdColor(n.hue)
        let isSelected = vm.selID == n.id
        let phase = (Double(n.hue) + Double(c.rank)) * 0.11
        let pulse = animated ? 0.5 + 0.5 * sin(now * 1.9 + phase) : 0.2
        let hasFindings = cgPenalty(n) > 0
        // 焦点退淡：选中了别的卡 → 非邻居退淡（邻居判定走边集）
        var dim = false
        if let sel = vm.selID, sel != n.id {
            dim = !vm.bubbleEdges().contains { e in
                (e.from == n.id && e.to == sel) || (e.to == n.id && e.from == sel)
                    || (e.from == sel && e.to == n.id) || (e.to == sel && e.from == n.id)
            }
        }
        // 入场错峰：#序越大越晚浮现（带内行主序），easeOutQuad 收尾
        let delay = Double(c.rank - 1) * 0.03 + Double(c.layerIndex) * 0.08
        let appearLocal = min(1, max(0, (now - delay) / 0.35))
        let appear = 1 - (1 - appearLocal) * (1 - appearLocal)
        var alpha: CGFloat = (dim ? 0.45 : 1) * CGFloat(appear)
        // 漂浮：整卡 ±1.2px 微动（相位按色相错开——网格不散、画面是活的）
        let floatX = animated ? sin(now * 0.5 + phase) * 1.2 : 0
        let floatY = animated ? cos(now * 0.42 + phase * 0.8) * 1.2 : 0
        // 呼吸（框体内）：尺度 ±0.3% + 填充亮度脉动
        let grow: CGFloat = animated
            ? (1 + pulse * 0.003 + (isSelected ? 0.003 : 0)) * (0.92 + 0.08 * CGFloat(appear))
            : 1
        let x = c.x + c.w / 2 - c.w * grow / 2 + floatX
        let y = c.y + c.h / 2 - c.h * grow / 2 + floatY
        let w = c.w * grow, h = c.h * grow
        // 框体填充：底色 + 置信度热色沉积（透明度按档位）
        let heatAlpha = (score < 60 ? 0.20 : (score < 80 ? 0.16 : 0.12))
            + (animated ? pulse * 0.05 : 0)
        var fill = Path()
        fill.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h),
                            cornerSize: CGSize(width: 10, height: 10))
        ctx.fill(fill, with: .color(Color(red: 0.075, green: 0.122, blue: 0.19).opacity(alpha)))
        ctx.fill(fill, with: .color(col.opacity(heatAlpha * alpha)))
        // 边框：同系边框呼吸
        var border = fill
        ctx.stroke(border, with: .color(
            isSelected || dim == false && hasFindings == false
                ? col.opacity(0.55 + pulse * 0.25)
                : (hasFindings ? col.opacity(0.45 + pulse * 0.2) : Color.white.opacity(0.14 + pulse * 0.06))
        ), lineWidth: isSelected ? 2 : (hasFindings ? 1.3 : 1.15))
        // 顶部流光：亮带沿顶边循环扫过（位置/相位每卡错开）
        if animated {
            let span = max(1, w - 26)
            let sweep = ((now * 0.13 + phase * 0.11).truncatingRemainder(dividingBy: 1)) * span
            let x0 = x + 13 + max(0, sweep - 14)
            let x1 = x + 13 + min(span, sweep + 14)
            if x1 > x0 {
                var sheen = Path()
                sheen.move(to: CGPoint(x: x0, y: y + 1))
                sheen.addLine(to: CGPoint(x: x1, y: y + 1))
                ctx.stroke(sheen,
                           with: .linearGradient(Gradient(colors: [col.opacity(0), col.opacity(0.5), col.opacity(0)]),
                                                 startPoint: CGPoint(x: x0, y: y + 1),
                                                 endPoint: CGPoint(x: x1, y: y + 1)),
                           lineWidth: 2)
            }
        }
        // 身份色左条
        var bar = Path()
        bar.addRoundedRect(in: CGRect(x: x, y: y, width: 4, height: h), cornerSize: CGSize(width: 2, height: 2))
        ctx.fill(bar, with: .color(idCol))
        // 文本（按 kind：文件 = FILE·lang + 行数；符号 = FUNC + 声明行；
        // 边界 = BOUNDARY + 引用次数）
        let font = Font.caption2
        let rankTxt = c.rank > 0 ? "#\(c.rank) " : ""
        let tag: String
        let meta: String
        let scoreText: String
        switch n.kind {
        case .file:
            tag = "FILE · " + (n.lang.isEmpty ? "cangjie" : n.lang)
            meta = "\(n.lines) 行 · ⚠\(cgPenalty(n))"
            scoreText = String(score)
        case .boundary:
            tag = "BOUNDARY"
            meta = "×\(n.rollN) 调用"
            scoreText = "×\(n.rollN)"
        default:
            tag = "FUNC" + (n.symKind.isEmpty ? "" : " · " + n.symKind)
            meta = "L\(n.declLine) · ⚠\(n.rollN)"
            scoreText = String(score)
        }
        ctx.draw(Text(rankTxt + tag)
            .font(font).foregroundStyle(col.opacity(0.9 * alpha)),
            at: CGPoint(x: x + 13, y: y + 14), anchor: .leading)
        ctx.draw(Text(n.name)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.92 * alpha)),
            at: CGPoint(x: x + 13, y: y + 32), anchor: .leading)
        ctx.draw(Text(meta)
            .font(font).foregroundStyle(Color(white: 0.62).opacity(alpha)),
            at: CGPoint(x: x + 13, y: y + h - 22), anchor: .leading)
        ctx.draw(Text(scoreText)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundStyle(col.opacity(alpha)),
            at: CGPoint(x: x + w - 12, y: y + 16), anchor: .trailing)
        // 米条（置信度）
        var track = Path()
        track.addRoundedRect(in: CGRect(x: x + 13, y: y + h - 10, width: w - 26, height: 3),
                             cornerSize: CGSize(width: 2, height: 2))
        ctx.fill(track, with: .color(Color.white.opacity(0.10 * alpha)))
        var meter = Path()
        meter.addRoundedRect(in: CGRect(x: x + 13, y: y + h - 10,
                                        width: max(1, (w - 26) * CGFloat(score) / 100), height: 3),
                             cornerSize: CGSize(width: 2, height: 2))
        ctx.fill(meter, with: .color(col.opacity(alpha)))
        // 选中描边（框内）
        if isSelected {
            var ring = Path()
            ring.addRoundedRect(in: CGRect(x: x + 2.5, y: y + 2.5, width: w - 5, height: h - 5),
                                cornerSize: CGSize(width: 8, height: 8))
            ctx.stroke(ring, with: .color(col.opacity(0.35 + pulse * 0.3)), lineWidth: 1)
        }
        _ = border
    }

    private func tap(_ p: CGPoint, cards: [CGCard]) {
        for c in cards.reversed() {
            if c.node.kind == .boundary { continue }
            if p.x >= c.x && p.x <= c.x + c.w && p.y >= c.y && p.y <= c.y + c.h {
                if c.node.kind == .file {
                    vm.heatDrill = c.node
                } else {
                    vm.selID = c.node.id
                    onSelect(c.node)
                }
                return
            }
        }
    }

    private var legend: some View {
        HStack(spacing: DSSpacing.md) {
            ForEach([(80, 100, "高 ≥80"), (60, 79, "中 60–79"), (0, 59, "低 <60")], id: \.0) { lo, hi, label in
                HStack(spacing: DSSpacing.xs) {
                    Circle()
                        .fill(cgHeatColor((lo + hi) / 2))
                        .frame(width: 8, height: 8)
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("#序 = 排布阅读序 · 线色 = 来源（左色条）· 虚线 = 词法不确定")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
    }
}

// MARK: - 走线（通道车道 + Catmull-Rom 平滑）

struct CGEdgeRoute {
    let from: String
    let to: String
    let w: Int
    let tier: String
    let points: [CGPoint]           // 折线 waypoint
    let smoothed: [CGPoint]          // Catmull-Rom 采样

    func sample(_ t: CGFloat) -> CGPoint? {
        let pts = smoothed
        guard pts.count > 1 else { return nil }
        var total: CGFloat = 0
        var lens: [CGFloat] = [0]
        for i in 1..<pts.count {
            total += hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y)
            lens.append(total)
        }
        let target = t * total
        for i in 1..<pts.count where lens[i] >= target {
            let seg = max(0.001, lens[i] - lens[i-1])
            let k = (target - lens[i-1]) / seg
            return CGPoint(x: pts[i-1].x + (pts[i].x - pts[i-1].x) * k,
                           y: pts[i-1].y + (pts[i].y - pts[i-1].y) * k)
        }
        return pts.last
    }
}

@MainActor
enum CGEdgeRouting {
    /// 通道车道走线（HTML routeWorldEdges 移植）：行隙/带隙内分道并排，
    /// 列间隙垂直段（被卡挡住才绕行），Catmull-Rom 平滑拐弯。
    static func routes(vm: CodeGraphVM, cards: [CGCard]) -> [CGEdgeRoute] {
        let byId = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let raw = vm.bubbleEdges()
        var out: [CGEdgeRoute] = []
        // 行聚类：带内卡片按 y 聚行（同一水平带的卡共享行隙通道）
        var rowsByLayer: [Int: [(top: CGFloat, bottom: CGFloat, cards: [CGCard])]] = [:]
        for c in cards {
            var rows = rowsByLayer[c.layerIndex] ?? []
            if let ri = rows.firstIndex(where: { abs($0.top - c.y) < 20 }) {
                rows[ri].top = min(rows[ri].top, c.y)
                rows[ri].bottom = max(rows[ri].bottom, c.y + c.h)
                rows[ri].cards.append(c)
            } else {
                rows.append((c.y, c.y + c.h, [c]))
            }
            rowsByLayer[c.layerIndex] = rows
        }
        for k in rowsByLayer.keys {
            rowsByLayer[k]?.sort { $0.top < $1.top }
        }
        func rowOf(_ id: String) -> (layer: Int, idx: Int)? {
            guard let c = byId[id], var rows = rowsByLayer[c.layerIndex] else { return nil }
            for (i, r) in rows.enumerated() where c.y >= r.top - 6 && c.y <= r.top + 24 {
                return (c.layerIndex, i)
            }
            _ = rows
            rows = rowsByLayer[c.layerIndex] ?? []
            return rows.isEmpty ? nil : (c.layerIndex, 0)
        }
        for e in raw {
            guard let a = byId[e.from], let b = byId[e.to] else { continue }
            let rs = rowOf(e.from), rt = rowOf(e.to)
            guard let rsU = rs, let rtU = rt else { continue }
            let sameRow = rsU.layer == rtU.layer && rsU.idx == rtU.idx
            let down = rtU.layer > rsU.layer || (rtU.layer == rsU.layer && rtU.idx > rsU.idx)
            // 端口：向下 = 源底/目标顶；向上 = 源顶/目标底；同行 = 双底
            func anchor(_ c: CGCard, _ side: String, _ t: CGFloat) -> CGPoint {
                let inset: CGFloat = 12
                if side == "top" {
                    return CGPoint(x: c.x + inset + t * max(1, c.w - 2 * inset), y: c.y)
                }
                return CGPoint(x: c.x + inset + t * max(1, c.w - 2 * inset), y: c.y + c.h)
            }
            let spreadA = CGFloat((abs(e.from.hashValue) % 100) + 8) / 100.0
            let spreadB = CGFloat((abs(e.to.hashValue) % 100) + 8) / 100.0
            let s = anchor(a, sameRow ? "bottom" : (down ? "bottom" : "top"), spreadA)
            let t = anchor(b, sameRow ? "bottom" : (down ? "top" : "bottom"), spreadB)
            // 通道 y：行隙中点
            func chBelow(_ layer: Int, _ idx: Int) -> CGFloat? {
                guard let rows = rowsByLayer[layer] else { return nil }
                if idx + 1 < rows.count { return (rows[idx].bottom + rows[idx+1].top) / 2 }
                if let lastRow = rows.last { return lastRow.bottom + 42 }
                return nil
            }
            func chAbove(_ layer: Int, _ idx: Int) -> CGFloat? {
                guard let rows = rowsByLayer[layer] else { return nil }
                if idx > 0 { return (rows[idx-1].bottom + rows[idx].top) / 2 }
                return rows.first.map { $0.top - 42 }
            }
            var pts: [CGPoint] = [s]
            if sameRow {
                let ch = rsU.layer == rtU.layer ? chBelow(rsU.layer, rsU.idx) ?? s.y + 42 : s.y
                pts.append(CGPoint(x: s.x, y: ch))
                pts.append(CGPoint(x: t.x, y: ch))
            } else if down {
                let chA = chBelow(rsU.layer, rsU.idx) ?? s.y
                let chB = chAbove(rtU.layer, rtU.idx) ?? t.y
                pts.append(CGPoint(x: s.x, y: chA))
                if abs(chA - chB) > 2 {
                    // 列间隙垂直段（被卡挡住时绕行）
                    var blocked = false
                    for c in cards where c.id != e.from && c.id != e.to {
                        if c.y + c.h > min(chA, chB) + 4 && c.y < max(chA, chB) - 4
                            && t.x > c.x + 6 && t.x < c.x + c.w - 6 { blocked = true }
                    }
                    if blocked {
                        let vx = t.x + (abs(e.from.hashValue) % 3 == 0 ? -52 : (abs(e.from.hashValue) % 3 == 1 ? 52 : 0))
                        pts.append(CGPoint(x: vx, y: chA))
                        pts.append(CGPoint(x: vx, y: chB))
                        pts.append(CGPoint(x: t.x, y: chB))
                    } else {
                        pts.append(CGPoint(x: t.x, y: chA))
                        if abs(chB - chA) > 2 { pts.append(CGPoint(x: t.x, y: chB)) }
                    }
                }
            } else {
                let chA = chAbove(rsU.layer, rsU.idx) ?? s.y
                let chB = chBelow(rtU.layer, rtU.idx) ?? t.y
                pts.append(CGPoint(x: s.x, y: chA))
                if abs(chA - chB) > 2 {
                    pts.append(CGPoint(x: t.x, y: chA))
                    pts.append(CGPoint(x: t.x, y: chB))
                }
            }
            pts.append(t)
            // 合并重复点 + Catmull-Rom 平滑
            var clean: [CGPoint] = [pts[0]]
            for p in pts.dropFirst() {
                let q = clean.last!
                if abs(p.x - q.x) > 1 || abs(p.y - q.y) > 1 { clean.append(p) }
            }
            guard clean.count >= 2 else { continue }
            out.append(CGEdgeRoute(from: e.from, to: e.to, w: e.w, tier: e.tier,
                                   points: clean, smoothed: catmull(clean, 12)))
        }
        return out
    }

    /// Catmull-Rom 样条采样（折线 waypoint → 平滑曲线密集点）。
    static func catmull(_ pts: [CGPoint], _ per: Int) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var out = [pts[0]]
        for i in 0..<pts.count - 1 {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1],
                p3 = pts[min(pts.count - 1, i + 2)]
            for j in 1...per {
                let t = CGFloat(j) / CGFloat(per)
                let t2 = t * t, t3 = t2 * t
                out.append(CGPoint(
                    x: 0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
                    y: 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)))
            }
        }
        return out
    }
}
