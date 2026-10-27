// ArchPage.swift — 架构图页（单仓库锁定，仓库面板入口触发）。
//
// ⚠️ 用户定稿 2026-10-27：**不再原生绘制**。引擎 `render arch` 的交互 HTML
// 产物（零依赖单文件，含关系连线/模块下钻/返回/搜索/明暗主题）就是正身，
// 本页用 WKWebView 直接渲染该文件；原生 Canvas 版已删除——
// 两份绘制实现必然漂移，且 HTML 的交互面客户端追不上。
//
// 页面职责收敛为三件事：
//   ① 触发引擎生成（arch gen：写 arch.json，探针对账）
//   ② 触发引擎渲染（render arch：复用或重绘交互 HTML，回执带版本）
//   ③ 把产物装进 WebView（并在渲染后强制刷新）；外部打开只是入口便利
import SwiftUI

@MainActor
final class ArchPageVM: ObservableObject {
    /// 单仓库限制：项目名在仓库面板的入口处锁定（页面内无切换选择器）
    let projectName: String
    @Published var loading = false
    @Published var error: String?
    /// WebView 正在展示的产物路径（nil = 还没有，显示引导空态）
    @Published var htmlPath: String?
    /// 重新渲染后路径不变也要刷新 WebView
    @Published var reloadToken = 0
    /// 引擎回执（末行）：版本/探针/违规数直接给用户看
    @Published var genStatus: String?
    @Published var generating = false

    init(projectName: String) {
        self.projectName = projectName
    }

    private func receipt(_ text: String) -> String? {
        for line in text.split(separator: "\n").reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// render arch：复用判定在引擎侧（产物新鲜就只报 reused，代价小）。
    /// 页面打开与「刷新」都走这里。
    func render() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let out = try await EngineCLI.shared.runData(["render", "arch", projectName], timeout: 600)
            let text = String(data: out, encoding: .utf8) ?? ""
            genStatus = receipt(text)
            if let p = extractHTMLPath(text) {
                htmlPath = p
                reloadToken += 1
            } else {
                error = text
            }
        } catch {
            self.error = EngineError.userMessage(for: error)
        }
    }

    /// arch gen：重建 arch.json（探针对账决定首版/版本号），完成后重渲染。
    func generate() async {
        generating = true
        genStatus = nil
        defer { generating = false }
        do {
            let r = try await EngineCLI.shared.runData(["arch", "gen", projectName], timeout: 600)
            genStatus = receipt(String(data: r, encoding: .utf8) ?? "")
            await render()
        } catch {
            genStatus = EngineError.userMessage(for: error)
        }
    }

    private func extractHTMLPath(_ text: String) -> String? {
        for line in text.split(separator: "\n") {
            for token in line.split(separator: " ") {
                let t = token.trimmingCharacters(in: .whitespaces)
                if t.hasSuffix(".html") && t.hasPrefix("/") { return t }
            }
        }
        return nil
    }

    func openExternal() {
        if let p = htmlPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        }
    }
}

struct ArchPage: View {
    /// 单仓库限制：项目名在仓库面板的入口处锁定（页面内无切换选择器）
    let projectName: String
    @ObservedObject var vm: ArchPageVM

    init(projectName: String) {
        self.projectName = projectName
        _vm = ObservedObject(wrappedValue: ArchPageVM(projectName: projectName))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let err = vm.error {
                Text(err).foregroundStyle(.orange).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DSSpacing.md)
            }
            if let status = vm.genStatus {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "gearshape.2").foregroundStyle(.tertiary)
                    Text(status).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, DSSpacing.md).padding(.vertical, DSSpacing.xs)
            }
            if vm.htmlPath == nil && !vm.loading {
                emptyHint
            } else {
                GraphWebView(htmlPath: vm.htmlPath, reloadToken: vm.reloadToken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .task {
            // 单仓库限制：项目名在仓库面板入口处锁定，直接渲染
            if !projectName.isEmpty { await vm.render() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: "shippingbox").font(.caption).foregroundStyle(.tertiary)
            Text(projectName).font(.system(.caption, design: .monospaced).weight(.semibold))
            // 生成动作：GUI 具现化引擎的 arch gen（写 arch.json，探针对账）
            Button {
                Task { await vm.generate() }
            } label: {
                Label(L10n.t("arch.generate"), systemImage: "wand.and.stars")
            }
            .disabled(vm.generating || projectName.isEmpty)
            // 渲染/刷新：render arch（复用判定在引擎，产物新鲜代价小）
            Button {
                Task { await vm.render() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(vm.loading || projectName.isEmpty)
            .help(L10n.t("cgraph.reload"))
            .accessibilityLabel(A11y.label(L10n.t("cgraph.reload")))
            Button {
                vm.openExternal()
            } label: {
                Image(systemName: "safari")
            }
            .disabled(vm.htmlPath == nil)
            .help(L10n.t("graph.openExternal"))
            .accessibilityLabel(A11y.label(L10n.t("graph.openExternal")))
            Spacer()
            if vm.loading || vm.generating { ProgressView().controlSize(.small) }
        }
        .padding(DSSpacing.md)
    }

    private var emptyHint: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "shippingbox")
                .font(.title).foregroundStyle(.tertiary)
            Text(projectName.isEmpty
                 ? L10n.t("graph.needProject")
                 : L10n.t("arch.renderFirst"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
