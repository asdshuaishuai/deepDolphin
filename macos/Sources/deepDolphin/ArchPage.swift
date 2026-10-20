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
    /// 单仓库限制：项目名在仓库面板的入口处锁定（页面内无切换选择器）
    @Published var projectName: String
    @Published var loading = false
    @Published var error: String?
    @Published var overview: [String: Any] = [:]
    let canvas = ArchCanvasVM()

    init(projectName: String) {
        self.projectName = projectName
    }

    @Published var generating = false
    /// 引擎回执（末行）：版本/探针/违规数直接给用户看
    @Published var genStatus: String?
    @Published var exportedPath: String?

    // ⚠ 回执解析已收敛到纯函数 `ArchReceipt`（批 AR）：原来这里是**两份同名复制**
    //   （本文件 + CodeGraphPage），各写各的 ⇒ 改一处漏一处、也**测不到**。
    //   而且那份复制按**空格**切词 —— 引擎真实回执里路径是粘在**全角冒号**后的
    //   （「已写入：/path/arch.html · …」）⇒ 路径**永远抽不出来**
    //   ⇒ 导出后「打开」入口**始终不出现**（死按钮）。

    /// 生成架构（写 arch.json，探针对账决定首版/版本号），完成后重载画布。
    func generate() async {
        generating = true
        genStatus = nil
        defer { generating = false }
        do {
            let r = try await EngineCLI.shared.runData(
                ["arch", "gen", projectName], timeout: 600)
            genStatus = ArchReceipt.receipt(String(data: r, encoding: .utf8) ?? "")
            await load()
        } catch {
            genStatus = EngineError.userMessage(for: error)
        }
    }

    /// 导出架构交互 HTML（render arch；回执带路径与复用/新绘判定）
    func exportHTML() async {
        generating = true
        genStatus = nil
        defer { generating = false }
        do {
            let out = try await EngineCLI.shared.runData(
                ["render", "arch", projectName], timeout: 600)
            let text = String(data: out, encoding: .utf8) ?? ""
            exportedPath = ArchReceipt.htmlPath(text)
            genStatus = ArchReceipt.receipt(text)
        } catch {
            genStatus = EngineError.userMessage(for: error)
        }
    }

    func openExport() {
        if let p = exportedPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        }
    }

    func load() async {
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
    /// 单仓库限制：项目名在仓库面板的入口处锁定（页面内无切换选择器）
    let projectName: String
    // ObservedObject：观察 VM 的 loading/error 变化（VM 由入口持有）
    @ObservedObject var vm: ArchPageVM

    init(projectName: String) {
        self.projectName = projectName
        _vm = ObservedObject(wrappedValue: ArchPageVM(projectName: projectName))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.md) {
                // 单仓库限制：页面在仓库面板打开时锁死该仓库（无切换选择器）
                Image(systemName: "shippingbox").font(.caption).foregroundStyle(.tertiary)
                Text(projectName).font(.system(.caption, design: .monospaced).weight(.semibold))
                Button {
                    Task { await vm.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.loading)
                .help(L10n.t("common.refresh"))
                .accessibilityLabel(A11y.label(L10n.t("common.refresh")))
                // 生成动作：GUI 具现化引擎的 arch_gen（写 arch.json，探针对账）
                Button {
                    Task { await vm.generate() }
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(.borderless)
                .disabled(vm.generating)
                .help(L10n.t("arch.generate"))
                .accessibilityLabel(A11y.label(L10n.t("arch.generate")))
                // 导出动作：GUI 具现化引擎的 render arch（落盘交互 HTML）
                Button {
                    Task { await vm.exportHTML() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(vm.generating)
                .help(L10n.t("arch.export"))
                .accessibilityLabel(A11y.label(L10n.t("arch.export")))
                Spacer()
                if vm.loading || vm.generating { ProgressView().controlSize(.small) }
            }
            .padding(DSSpacing.md)
            if let err = vm.error {
                Text(err).foregroundStyle(.orange).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DSSpacing.md)
            }
            if let status = vm.genStatus {
                // 生成/导出回执：版本/探针/违规数直接给用户看
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "gearshape.2").foregroundStyle(.tertiary)
                    Text(status).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let p = vm.exportedPath {
                        Button(L10n.t("arch.export")) {
                            vm.openExport()
                        }
                        .buttonStyle(.borderless).controlSize(.small)
                        .help(p)
                        .accessibilityLabel(A11y.label(L10n.t("arch.export")))
                    }
                }
                .padding(.horizontal, DSSpacing.md).padding(.vertical, DSSpacing.xs)
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
            // 单仓库限制：项目名在仓库面板入口处锁定，直接加载
            await vm.load()
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
