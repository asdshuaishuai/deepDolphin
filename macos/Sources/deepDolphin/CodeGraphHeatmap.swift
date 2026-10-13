// CodeGraphHeatmap.swift — 符号索引热力图的原生 SwiftUI Canvas 驱动
//（形态与引擎 HTML 交付物完全对齐：力导向气泡）。
//
// 布局：CodeGraphVM.bubbles(size:)——确定性力模拟（黄金角散点 + 240 轮，
// 常数/排序/fitExtent 与引擎 layoutBubbles 逐项对齐），同数据同画布 ⇒
// 同坐标。绘制期叠加与 HTML 相同的三层时间动效：入场扩散错峰（easeOut
// 双段）、呼吸 ±3% 半径、漂浮漂移 ±2.4px；粒子沿微弯贝塞尔边匀速流动。
//
// 语义对齐：
//   · 颜色 = 置信度指数（confScore 与引擎 confidenceScore 同式同值；
//     色阶与 HTML confidenceColor 逐字同色：≥80 #59f0b8 / 60–79 #ffc857 /
//     <60 #ff6b8a）
//   · 边颜色 = 来源节点身份色（黄金角 137.5° 色相，HTML HUE_OF 同源）
//   · 符号层 guessed 边虚线（词法不确定要看得出来）
//   · 点文件气泡下钻符号层（面包屑返回）；点符号气泡 = 选中，右栏详情
//     复用 CodeGraphPage 既有管道（vm.selID）
//
// reduced-motion / 离屏 harness（staticFrame）直取终帧：无入场动画、
// 无呼吸漂移、无粒子——布局本身不受影响（确定性）。

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

/// 色阶只有一份（与 HTML confidenceColor 逐字同色；HTML 现为暗色单主题，
/// 两套外观同色）。
func cgHeatColor(_ score: Int) -> Color {
    if score >= 80 { return Color(red: 0.349, green: 0.941, blue: 0.722) }  // #59f0b8
    if score >= 60 { return Color(red: 1.0, green: 0.784, blue: 0.341) }    // #ffc857
    return Color(red: 1.0, green: 0.420, blue: 0.541)                       // #ff6b8a
}

/// 边的语义色：来源节点身份色相（HTML HUE_OF 同源）；guessed 琥珀。
func cgEdgeColor(tier: String, hue: Int) -> Color {
    if tier == "guessed" { return Color(red: 1.0, green: 0.784, blue: 0.341) }
    let v = hue % 2
    return Color(hue: Double(hue) / 360.0,
                 saturation: 0.62 + Double(v) * 0.16,
                 brightness: 0.52 + Double(v) * 0.14)
}

// MARK: - 视图

struct CodeGraphHeatView: View {
    @ObservedObject var vm: CodeGraphVM
    var onSelect: (GNode) -> Void
    /// 离屏 harness 直取终帧（无入场动画/呼吸/粒子）
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
            TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                    paused: !animated)) { tl in
                GeometryReader { geo in
                    let bubbles = vm.bubbles(size: geo.size)
                    let edges = vm.bubbleEdges()
                    let now = timelineDelta(tl)
                    Canvas { ctx, size in
                        draw(now: now, size: size, bubbles: bubbles, edges: edges, into: &ctx)
                    }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in
                        tap(v.location, bubbles: bubbles)
                    })
                }
            }
            Divider()
            legend
        }
        .onChange(of: vm.heatDrill?.id) { _ in
            if !animated { startedAt = Date(timeIntervalSinceReferenceDate: 0) }
        }
    }

    /// 时间轴相对起点（入场进度/呼吸/粒子的时间基准）。staticFrame /
    /// reduced-motion 直接给大偏移 ⇒ 所有时变项都取终帧。
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

    // MARK: 绘制（HTML drawBubble/drawCodeEdge 的 GraphicsContext 移植）

    private func draw(now: Double, size: CGSize, bubbles: [CodeGraphVM.CGBubble],
                      edges: [(from: String, to: String, w: Int, tier: String)],
                      into ctx: inout GraphicsContext) {
        let W = max(1, size.width)
        let H = max(1, size.height)
        let byId = Dictionary(uniqueKeysWithValues: bubbles.map { ($0.id, $0) })
        let hueById = Dictionary(uniqueKeysWithValues: bubbles.map { ($0.id, $0.node.hue) })
        // 气泡几何：入场错峰 + 呼吸 ±3% + 漂移 ±2.4px（HTML drawBubble 同式）
        var geo: [String: (x: CGFloat, y: CGFloat, r: CGFloat, alpha: CGFloat)] = [:]
        for b in bubbles {
            let dC = sqrt(pow(b.x - W / 2, 2) + pow(b.y - H / 2, 2))
            let df = min(1, dC / (max(W, H) * 0.55))
            let local = min(1, max(0, now / 0.34 * 1.6 - df * 0.6))
            let ease = 1 - (1 - local) * (1 - local)
            let phase = (b.x * 0.7 + b.y * 1.3) * 0.01
            let rr = b.r * ease * (1 + sin(now * 1.1 + phase) * 0.03)
            let px = W / 2 + (b.x - W / 2) * ease + sin(now * 0.53 + phase) * 2.4
            let py = H / 2 + (b.y - H / 2) * ease + cos(now * 0.43 + phase * 0.8) * 2.8
            geo[b.id] = (px, py, max(0.6, rr), ease)
        }
        // 边：微弯贝塞尔 + 箭头 + 粒子（HTML drawCodeEdge 同式）
        for e in edges {
            guard let a = byId[e.from], let b = byId[e.to],
                  let ga = geo[e.from], let gb = geo[e.to] else { continue }
            let dx = gb.x - ga.x, dy = gb.y - ga.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist < 1 { continue }
            let sx = ga.x + dx / dist * (ga.r + 2), sy = ga.y + dy / dist * (ga.r + 2)
            let tx = gb.x - dx / dist * (gb.r + 5), ty = gb.y - dy / dist * (gb.r + 5)
            let mx = (sx + tx) / 2 - dy * 0.12
            let my = (sy + ty) / 2 + dx * 0.12
            let hue = hueById[e.from] ?? 0
            let ecol = cgEdgeColor(tier: e.tier, hue: hue)
            let lit = vm.selID == e.from || vm.selID == e.to
            var path = Path()
            path.move(to: CGPoint(x: sx, y: sy))
            path.addCurve(to: CGPoint(x: tx, y: ty),
                          control1: CGPoint(x: mx, y: my),
                          control2: CGPoint(x: mx, y: my))
            ctx.stroke(path, with: .color(ecol.opacity(lit ? 0.9 : 0.45)),
                       style: StrokeStyle(lineWidth: lit ? 1.9 : min(2.6, 0.9 + Double(e.w) * 0.14),
                                          lineCap: .round,
                                          dash: e.tier == "guessed" ? [5, 4] : []))
            // 箭头（末段方向）
            let ux = tx - mx, uy = ty - my
            let ul = (sqrt(ux * ux + uy * uy)) > 0 ? sqrt(ux * ux + uy * uy) : 1
            let nx = ux / ul, ny = uy / ul
            var arrow = Path()
            arrow.move(to: CGPoint(x: tx, y: ty))
            arrow.addLine(to: CGPoint(x: tx - (nx * 5.5 - ny * 2.75), y: ty - (ny * 5.5 + nx * 2.75)))
            arrow.addLine(to: CGPoint(x: tx - (nx * 5.5 + ny * 2.75), y: ty - (ny * 5.5 - nx * 2.75)))
            arrow.closeSubpath()
            ctx.fill(arrow, with: .color(ecol.opacity(lit ? 0.95 : 0.6)))
            // 粒子：沿曲线匀速流动（确定性相位 = 来源 id 哈希）
            if animated {
                var h = 0
                for ch in e.from.utf8 { h = (h &* 31 &+ Int(ch)) & 0x7fffffff }
                let tt = (now * 0.7 + Double(h % 97) / 97.0).truncatingRemainder(dividingBy: 1)
                let iu = 1 - tt
                let qx = iu * iu * sx + 2 * iu * tt * mx + tt * tt * tx
                let qy = iu * iu * sy + 2 * iu * tt * my + tt * tt * ty
                ctx.fill(Path(ellipseIn: CGRect(x: qx - 1.8, y: qy - 1.8, width: 3.6, height: 3.6)),
                         with: .color(ecol.opacity(0.5)))
            }
        }
        // 气泡（边之上）
        for b in bubbles {
            guard let g = geo[b.id] else { continue }
            let heat = cgHeatColor(b.score)
            let selected = vm.selID == b.id
            let body = Path(ellipseIn: CGRect(x: g.x - g.r, y: g.y - g.r, width: g.r * 2, height: g.r * 2))
            ctx.fill(body, with: .color(heat.opacity(0.30 * g.alpha)))
            ctx.stroke(body, with: .color(heat.opacity(0.9 * g.alpha)),
                       lineWidth: selected ? 2 : 1.3)
            if g.r >= 13 {
                ctx.draw(Text(String(b.score))
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(heat.opacity(g.alpha)),
                    at: CGPoint(x: g.x, y: g.y), anchor: .center)
            }
            let label = b.node.name + " ·" + String(b.score)
            let t = label.count > 26 ? String(label.prefix(25)) + "…" : label
            ctx.draw(Text(t)
                .font(.caption2)
                .foregroundStyle(Color(white: 0.85).opacity(0.85 * g.alpha)),
                at: CGPoint(x: g.x, y: g.y + g.r + 6), anchor: .top)
            if b.node.rollN > 0 {
                ctx.draw(Text("⚠\(b.node.rollN)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.orange.opacity(0.85 * g.alpha)),
                    at: CGPoint(x: g.x, y: g.y + g.r + 18), anchor: .top)
            }
        }
    }

    private func tap(_ p: CGPoint, bubbles: [CodeGraphVM.CGBubble]) {
        for b in bubbles.reversed() {
            let d = sqrt(pow(p.x - b.x, 2) + pow(p.y - b.y, 2))
            if d <= b.r + 4 {
                if b.node.kind == .file {
                    vm.heatDrill = b.node
                } else {
                    vm.selID = b.node.id
                    onSelect(b.node)
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
            Text("面积 ∝ 行数 · 颜色 = 置信度指数 · 线色 = 来源")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
    }
}
