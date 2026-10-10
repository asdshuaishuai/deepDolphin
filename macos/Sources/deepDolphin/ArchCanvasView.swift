// ArchCanvasView.swift — moongit-graph-scene v1 的 SwiftUI 驱动。
//
// 契约：moonGit 仓库 docs/graph-scene-schema.md。Web 驱动（archhtml.cj）消费
// 同一份场景 JSON；本文件证明「任何 Canvas2D 移植都能驱动」那条承诺在
// CoreGraphics/Swift 一侧成立——绘制只依赖 scene 数据，交互（下钻/选中）
// 是命中区驱动的，零引擎私有语义。
//
// 对应关系（Canvas2D 子集 → GraphicsContext）：
//   fillRect/fill        → ctx.fill(Path(rect), .color)
//   strokeRect/stroke    → path.stroke(color, StrokeStyle)
//   setLineDash(+offset) → StrokeStyle(dash:dashPhase:)（流光推进）
//   bezierCurveTo        → Path.addCurve
//   linearGradient       → .linearGradient(Gradient, start, end)
//   globalAlpha          → 颜色 opacity
//   font/textAlign       → ctx.resolve(Text) + anchor
import SwiftUI

// MARK: - 视图模型

@MainActor
final class ArchCanvasVM: ObservableObject {
    @Published var scene: GraphScene?
    /// 当前视图 id："arch" 或 "module:xxx"。
    @Published var currentViewID = "arch"
    /// 选中的节点（右侧详情面板取 panels["<view>:<id>"]）。
    @Published var selectedNode: String?
    @Published var manualDark: Bool?
    @Published var loadError: String?

    // 视口：screen = world · scale + offset
    private(set) var scale: CGFloat = 1
    private(set) var offset: CGSize = .zero
    private(set) var canvasSize: CGSize = .zero
    /// 用户动过视口后就不再自动 fit（直到按复位）。
    private var userAdjustedViewport = false
    /// 捏合手势的上一次系数（MagnifyGesture 给的是累计值，按增量缩放）。
    private var lastMagnification: CGFloat = 1

    var currentView: GraphSceneViewData? { scene?.view(currentViewID) }

    /// 展示用主题：nil = 跟随系统。
    func isDark(_ systemDark: Bool) -> Bool {
        manualDark ?? systemDark
    }

    func load(project: String) async {
        do {
            let s = try await GraphService.loadScene(project: project)
            scene = s
            currentViewID = "arch"
            selectedNode = nil
            loadError = nil
            userAdjustedViewport = false
        } catch {
            loadError = EngineError.userMessage(for: error)
        }
    }

    func setView(_ id: String) {
        guard scene?.view(id) != nil else { return }
        currentViewID = id
        selectedNode = nil
        userAdjustedViewport = false
    }

    func goBackToParent() {
        if let parent = currentView?.parent, !parent.isEmpty {
            setView(parent)
        }
    }

    func fitIfNeeded(in size: CGSize) {
        canvasSize = size
        guard !userAdjustedViewport else { return }
        fit(in: size)
    }

    func fit(in size: CGSize) {
        canvasSize = size
        guard let v = currentView, size.width > 1, size.height > 1 else { return }
        let w = max(v.bx1 - v.bx0, 1)
        let h = max(v.by1 - v.by0, 1)
        let pad: CGFloat = 40
        scale = min((size.width - pad * 2) / CGFloat(w), (size.height - pad * 2) / CGFloat(h))
        scale = min(max(scale, 0.05), 4)
        let cx = CGFloat((v.bx0 + v.bx1) / 2)
        let cy = CGFloat((v.by0 + v.by1) / 2)
        offset = CGSize(width: size.width / 2 - cx * scale, height: size.height / 2 - cy * scale)
    }

    func pan(by delta: CGSize) {
        userAdjustedViewport = true
        offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
    }

    /// 捏合缩放（以画布中心为锚）。value 是累计倍率，按增量换算。
    func magnify(to cumulative: CGFloat) {
        let delta = cumulative / max(lastMagnification, 0.001)
        lastMagnification = cumulative
        zoom(by: delta, around: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2))
    }

    func resetMagnificationAnchor() {
        lastMagnification = 1
    }

    func zoom(by factor: CGFloat, around anchor: CGPoint) {
        userAdjustedViewport = true
        let newScale = min(max(scale * factor, 0.05), 4)
        // 锚点的 world 坐标保持不动
        let anchorWorld = CGPoint(x: (anchor.x - offset.width) / scale,
                                  y: (anchor.y - offset.height) / scale)
        scale = newScale
        offset = CGSize(width: anchor.x - anchorWorld.x * scale,
                        height: anchor.y - anchorWorld.y * scale)
    }

    /// 命中测试：屏幕点 → world 点 → hits 区间。
    @discardableResult
    func tap(at screenPoint: CGPoint) -> Bool {
        guard let v = currentView else { return false }
        let wx = (screenPoint.x - offset.width) / scale
        let wy = (screenPoint.y - offset.height) / scale
        for h in v.hits {
            guard let id = h["id"] as? String,
                  let x = h["x"] as? Double, let y = h["y"] as? Double,
                  let w = h["w"] as? Double, let hh = h["h"] as? Double else { continue }
            if wx >= CGFloat(x) && wx <= CGFloat(x + w) && wy >= CGFloat(y) && wy <= CGFloat(y + hh) {
                selectedNode = (selectedNode == id) ? nil : id
                return true
            }
        }
        selectedNode = nil
        return false
    }

    /// 选中节点的详情面板（契约两级形状：架构级带 langs，文件级没有）。
    var selectedPanel: [String: Any]? {
        guard let id = selectedNode else { return nil }
        return scene?.panels["\(currentViewID):\(id)"]
    }

    // MARK: 绘制

    func draw(into ctx: inout GraphicsContext, size: CGSize, now: TimeInterval, dark: Bool) {
        guard let s = scene, let v = currentView else { return }
        let theme = dark ? s.dark : s.light

        func token(_ name: String) -> Color { s.color(for: name, theme: dark, view: v) }

        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: CGFloat(x) * scale + offset.width, y: CGFloat(y) * scale + offset.height)
        }

        // 背景
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(token("bg0")))

        for shape in v.shapes {
            let t = shape["t"] as? String ?? ""
            func num(_ k: String) -> Double {
                if let v = shape[k] as? Double { return v }
                if let v = shape[k] as? Int { return Double(v) }
                return 0
            }
            switch t {
            case "frame":
                let origin = pt(num("x"), num("y"))
                let screen = CGRect(origin: origin,
                                    size: CGSize(width: num("w") * scale, height: num("h") * scale))
                ctx.stroke(Path(screen), with: .color(token(shape["color"] as? String ?? "border")),
                           style: StrokeStyle(lineWidth: 1.4))
                if let label = shape["label"] as? String {
                    drawText(ctx: &ctx, text: label, at: CGPoint(x: origin.x + 12, y: origin.y + 6),
                             size: 12, weight: .semibold, color: token("muted"), align: .leading)
                }
            case "rrect":
                let screen = CGRect(origin: pt(num("x"), num("y")),
                                    size: CGSize(width: num("w") * scale, height: num("h") * scale))
                let radius = min(num("r") * scale, min(screen.width, screen.height) / 2)
                let path = Path(roundedRect: screen, cornerRadius: max(radius, 0))
                let fill = token(shape["fill"] as? String ?? "panel")
                ctx.fill(path, with: .color(fill))
                if let st = shape["stroke"] as? String {
                    ctx.stroke(path, with: .color(token(st)),
                               style: StrokeStyle(lineWidth: num("sw") > 0 ? CGFloat(num("sw")) : 1))
                }
            case "rect":
                let screen = CGRect(origin: pt(num("x"), num("y")),
                                    size: CGSize(width: max(num("w") * scale, 1.5),
                                                 height: num("h") * scale))
                ctx.fill(Path(screen), with: .color(token(shape["fill"] as? String ?? "accent")))
            case "text":
                drawText(ctx: &ctx, text: shape["text"] as? String ?? "",
                         at: pt(num("x"), num("y")),
                         size: CGFloat(num("size") > 0 ? num("size") : 12),
                         weight: num("weight") >= 600 ? .semibold : .regular,
                         color: token(shape["color"] as? String ?? "text"),
                         align: shape["align"] as? String == "center" ? .center : .leading)
            case "edge":
                let p = shape["p"] as? [Double] ?? []
                guard p.count >= 8 else { continue }
                // 入场错峰：delay（毫秒）之前这条边还没开始生长
                let elapsed = now * 1000 - num("delay")
                if elapsed < 0 { continue }
                let p0 = pt(p[0], p[1]), c1 = pt(p[2], p[3]), c2 = pt(p[4], p[5]), p3 = pt(p[6], p[7])
                var path = Path()
                path.move(to: p0)
                path.addCurve(to: p3, control1: c1, control2: c2)
                let c0Color = token(shape["c0"] as? String ?? "arrow")
                let c1Color = token(shape["c1"] as? String ?? "arrow")
                let alpha = num("alpha") > 0 ? CGFloat(num("alpha")) : 0.85
                let style = StrokeStyle(lineWidth: max(num("sw") * scale, 0.8),
                                        lineCap: .round,
                                        dash: [7, 5],
                                        dashPhase: -CGFloat((now * 26).truncatingRemainder(dividingBy: 12)))
                ctx.stroke(path, with: .linearGradient(
                    Gradient(colors: [c0Color.opacity(alpha), c1Color]),
                    startPoint: p0, endPoint: p3), style: style)
                // 箭头：终点方向的小三角
                let arrow = max(num("arrow") * scale, 4)
                var dir = CGPoint(x: p3.x - c2.x, y: p3.y - c2.y)
                let len = max(sqrt(dir.x * dir.x + dir.y * dir.y), 0.001)
                dir = CGPoint(x: dir.x / len, y: dir.y / len)
                let perp = CGPoint(x: -dir.y, y: dir.x)
                var head = Path()
                head.move(to: p3)
                head.addLine(to: CGPoint(x: p3.x - dir.x * arrow + perp.x * arrow * 0.45,
                                         y: p3.y - dir.y * arrow + perp.y * arrow * 0.45))
                head.addLine(to: CGPoint(x: p3.x - dir.x * arrow - perp.x * arrow * 0.45,
                                         y: p3.y - dir.y * arrow - perp.y * arrow * 0.45))
                head.closeSubpath()
                ctx.fill(head, with: .color(c1Color))
            default:
                continue
            }
        }

        // 流动粒子：相位 (i+1)/(n+1)，引擎保证两次导出一致（零随机）；
        // 驱动只做 t = phase + now·sp 的循环推进（sp 单位是毫秒倒数的相位）。
        for group in v.particles {
            let p = group["p"] as? [Double] ?? []
            guard p.count >= 8 else { continue }
            let n = (group["n"] as? Int) ?? ((group["n"] as? Double).map(Int.init) ?? 0)
            let sp = (group["sp"] as? Double) ?? 0
            let pc = token(group["color"] as? String ?? "accent")
            let p0 = pt(p[0], p[1]), c1 = pt(p[2], p[3]), c2 = pt(p[4], p[5]), p3 = pt(p[6], p[7])
            for i in 0..<max(n, 0) {
                let phase = Double(i + 1) / Double(n + 1)
                var t = fmod(phase + now * sp * 1000.0, 1.0)
                if t < 0 { t += 1 }
                let pos = cubic(p0, c1, c2, p3, CGFloat(t))
                let radius = max(2.2 * scale, 1.2)
                let rect = CGRect(x: pos.x - radius, y: pos.y - radius,
                                  width: radius * 2, height: radius * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(pc.opacity(0.9)))
            }
        }
    }

    private func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
                       y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }

    private func drawText(ctx: inout GraphicsContext, text: String, at: CGPoint,
                          size: CGFloat, weight: Font.Weight, color: Color,
                          align: TextAlignment) {
        let anchor: UnitPoint = align == .center ? .top : .topLeading
        let resolved = ctx.resolve(
            Text(text)
                .font(.system(size: size, weight: weight))
                .foregroundColor(color)
        )
        ctx.draw(resolved, at: at, anchor: anchor)
    }
}

// MARK: - 视图

struct ArchCanvasView: View {
    @ObservedObject var vm: ArchCanvasVM
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let dark = vm.isDark(systemScheme == .dark)
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    vm.fitIfNeeded(in: size)
                    vm.draw(into: &ctx, size: size, now: now, dark: dark)
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { g in
                    _ = vm.tap(at: g.location)
                })
                .gesture(DragGesture()
                    .onChanged { g in vm.pan(by: g.translation) })
                .gesture(MagnifyGesture()
                    .onChanged { g in vm.magnify(to: g.magnification) }
                    .onEnded { _ in vm.resetMagnificationAnchor() })
            }
            .clipped()
            .overlay(alignment: .topTrailing) { toolbar(dark: dark) }
            .onChange(of: geo.size) { newSize in
                vm.fitIfNeeded(in: newSize)
            }
        }
    }

    private func toolbar(dark: Bool) -> some View {
        HStack(spacing: DSSpacing.sm) {
            if let s = vm.scene {
                Menu {
                    ForEach(s.views, id: \.id) { v in
                        Button(v.label) { vm.setView(v.id) }
                    }
                } label: {
                    Label(vm.currentView?.label ?? "arch", systemImage: "diagram.projective")
                }
                .fixedSize()
            }
            Button {
                vm.fit(in: vm.canvasSize)
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            Button {
                vm.manualDark = !dark
            } label: {
                Image(systemName: dark ? "sun.max" : "moon")
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .padding(DSSpacing.sm)
        .background(.ultraThinMaterial, in: DSRect.shape(DSRadius.control))
        .padding(10)
    }
}
