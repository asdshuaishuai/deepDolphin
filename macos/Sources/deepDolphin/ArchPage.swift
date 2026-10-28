// ArchPage.swift — 架构图页（单仓库锁定，仓库面板入口触发，独立最大化窗口）。
//
// ⚠️ 用户定稿 2026-10-27：**不再原生绘制**。引擎 `render arch` 的交互 HTML
// 产物（零依赖单文件，含关系连线/模块下钻/返回/搜索/明暗主题）就是正身，
// 本页用 WKWebView 直接渲染该文件；原生 Canvas 版已删除——
// 两份绘制实现必然漂移，且 HTML 的交互面客户端追不上。
//
// 页面职责收敛为三件事：
//   ① 触发引擎生成（arch gen：写 arch.json，探针对账）
//   ② 触发引擎渲染（render arch：复用或重绘，回执带版本）
//   ③ 把产物装进 WebView；打开即渲染（引擎复用判定生效时毫秒级），
//      上次的产物路径有缓存——**先秒开缓存图，再后台核验刷新**。
import SwiftUI

@MainActor
final class ArchPageVM: ObservableObject {
    /// 单仓库限制：项目名在仓库面板的入口处锁定（页面内无切换选择器）
    let projectName: String
    @Published var loading = false
    @Published var generating = false
    @Published var error: String?
    /// WebView 正在展示的产物路径（nil = 还没有，显示引导空态）
    @Published var htmlPath: String?
    /// 重新渲染后路径不变也要刷新 WebView
    @Published var reloadToken = 0
    /// 引擎回执（末行）：版本/探针/违规数给用户看（底部状态条）
    @Published var status: (ok: Bool, text: String)?

    /// 上次渲染出的产物路径（进程内缓存）：窗口重开时秒开旧图再后台刷新
    private static var lastGoodPath: [String: String] = [:]

    init(projectName: String) {
        self.projectName = projectName
        htmlPath = Self.lastGoodPath[projectName]
    }

    /// 引擎回执取末行（版本/复用判定给用户看）。
    private func receipt(_ text: String) -> String? {
        for line in text.split(separator: "\n").reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return nil
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

    /// render arch：复用判定在引擎侧（产物新鲜就只报 reused，代价毫秒级）。
    /// `background` = 秒开缓存后的后台核验：产物仍是复用就不重载 WebView
    /// （重载会闪一下，画面没变就不闪）。
    func render(background: Bool = false) async {
        if !background { loading = true; error = nil }
        defer { loading = false }
        do {
            let out = try await EngineCLI.shared.runData(["render", "arch", projectName], timeout: 600)
            let text = String(data: out, encoding: .utf8) ?? ""
            if let line = receipt(text) {
                status = (true, line)
            }
            if let p = extractHTMLPath(text) {
                let reused = text.contains("复用")
                let pathChanged = (htmlPath != p)
                htmlPath = p
                Self.lastGoodPath[projectName] = p
                if !reused || pathChanged { reloadToken += 1 }
            } else {
                error = text
                status = (false, receipt(text) ?? "render arch failed")
            }
        } catch {
            self.error = EngineError.userMessage(for: error)
            status = (false, self.error ?? "render failed")
        }
    }

    /// arch gen：重建 arch.json（探针对账决定首版/版本号），完成后重渲染。
    /// 生成 = LLM 驱动（用户定稿 2026-10-28）：播种引擎 skill 工作流给 agent，
    /// agent 关窗后回读产物（后台核验刷新，复用就不闪）。
    func generate() async {
        generating = true
        _ = await GraphAgentTask.launch(project: projectName, kind: "arch") { [weak self] in
            Task { @MainActor in
                self?.generating = false
                await self?.render(background: true)
            }
        }
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
            GraphHeaderView(
                icon: "diagram.projective",
                tint: .purple,
                title: "\(L10n.t("nav.arch")) · \(projectName)",
                subtitle: L10n.t("arch.subtitle"),
                generateTitle: L10n.t("arch.generate"),
                onGenerate: { Task { await vm.generate() } },
                generating: vm.generating,
                onRefresh: { Task { await vm.render() } },
                refreshing: vm.loading,
                onOpenExternal: { vm.openExternal() },
                canOpenExternal: vm.htmlPath != nil)
            Divider()
            ZStack {
                GraphWebView(htmlPath: vm.htmlPath, reloadToken: vm.reloadToken)
                    .opacity(vm.htmlPath == nil ? 0 : 1)
                if vm.htmlPath == nil {
                    if vm.loading {
                        GraphLoadingHint(text: L10n.t("graph.rendering"))
                    } else if vm.error == nil {
                        emptyHint
                    }
                }
            }
            Divider()
            GraphStatusBar(message: vm.status, onDismiss: { vm.status = nil })
        }
        .frame(minWidth: 960, minHeight: 640)
        .task {
            // 单仓库限制：项目名在仓库面板入口处锁定，直接渲染。
            // 有缓存路径时窗口已先秒开旧图，这里只是后台核验新鲜度。
            if !projectName.isEmpty { await vm.render(background: vm.htmlPath != nil) }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "diagram.projective")
                .font(.title).foregroundStyle(.tertiary)
            Text(projectName.isEmpty
                 ? L10n.t("graph.needProject")
                 : L10n.t("arch.renderFirst"))
                .foregroundStyle(.secondary)
        }
    }
}
