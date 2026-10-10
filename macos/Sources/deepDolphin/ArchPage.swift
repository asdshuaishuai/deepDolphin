// ArchPage.swift — 架构图页（独立于代码图谱）。
//
// ⚠️ 渲染归属：本页**直接用客户端自己的 Canvas 实现**（ArchCanvasView 的
// SwiftUI GraphicsContext = Swift 语言版的 Canvas2D 对应物）把 scene 契约
// 画在应用内——不导出 HTML、不开浏览器。Web 驱动只是引擎多出口之一，
// 客户端的正路永远是 scene 数据 + 本机 Canvas。
//
// 分工：**架构图**回答「模块怎么分层、依赖是否违规」（scene 画布，引擎确定性
// 布局与治理信号）；**代码图谱**（CodeGraphPage）回答「符号谁连着谁、哪里
// 不能信」。两者数据源不同（scene JSON vs symbol/impact/confidence），页面
// 也就必须分开——上一版揉在一页里，两个问题都答不清。
import SwiftUI

@MainActor
final class ArchPageVM: ObservableObject {
    @Published var projectName = ""
    @Published var loading = false
    @Published var error: String?
    @Published var overview: [String: Any] = [:]
    let canvas = ArchCanvasVM()

    func load(all: [ProjectStatus]) async {
        if projectName.isEmpty, let first = all.first {
            projectName = first.name
        }
        guard !projectName.isEmpty else { return }
        loading = true
        error = nil
        do {
            async let ov = GraphService.loadOverview(project: projectName)
            async let sc: Void = canvas.load(project: projectName)
            overview = try await ov
            await sc
        } catch {
            self.error = EngineError.userMessage(for: error)
        }
        loading = false
    }
}

struct ArchPage: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var vm = ArchPageVM()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.md) {
                GraphProjectPicker(projectName: $vm.projectName)
                Button {
                    Task { await vm.load(all: model.projects) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.loading || vm.projectName.isEmpty)
                .help(L10n.t("common.refresh"))
                .accessibilityLabel(A11y.label(L10n.t("common.refresh")))
                Spacer()
                if vm.loading { ProgressView().controlSize(.small) }
            }
            .padding(DSSpacing.md)
            if let err = vm.error {
                Text(err).foregroundStyle(.orange).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DSSpacing.md)
            }
            VStack(spacing: DSSpacing.sm) {
                ArchCanvasView(vm: vm.canvas)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                sceneFooter
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.sm)
        }
        .task {
            if vm.projectName.isEmpty || !model.projects.contains(where: { $0.name == vm.projectName }) {
                await vm.load(all: model.projects)
            }
        }
    }


    /// 契约要求：警示与截断必须如实披露（缺键不得当作「没有」）。
    @ViewBuilder
    private var sceneFooter: some View {
        if let s = vm.canvas.scene, let v = vm.canvas.currentView {
            let w = s.meta["warnings"] as? [String: Any]
            let violations = w?["violations"] as? Int ?? 0
            let cycleEdges = w?["cycleEdges"] as? Int ?? 0
            HStack(spacing: DSSpacing.md) {
                if violations > 0 || cycleEdges > 0 {
                    Label(L10n.t("graph.warnings", violations, cycleEdges),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if v.edgesDropped > 0 {
                    Label(L10n.t("graph.edgesDropped", v.edgesDropped),
                          systemImage: "arrow.down.to.line.compact")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let chips = s.meta["chips"] as? [[String: Any]] {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                            // count 是数字字段；label 只是文案（契约原文）
                            let count = chip["count"] as? Int ?? 0
                            Text(chip["label"] as? String ?? "").font(.caption2)
                                .foregroundStyle(.secondary)
                                + Text(" \(count)").font(.caption2).bold()
                        }
                    }
                }
            }
        }
    }
}
