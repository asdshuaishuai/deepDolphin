// CodeGraphPage.swift — 代码图谱页（单仓库锁定，仓库面板入口触发，独立最大化窗口）。
//
// ⚠️ 用户定稿 2026-10-27：**不再原生绘制**。列表树、符号索引热力图、右侧
// 置信度详情的原生 Canvas/树实现已整体删除——引擎 `render index` 的交互
// HTML 产物（零依赖单文件，含列表/热力图双模式、关系连线、下钻、返回上级、
// 搜索、明暗主题、置信度报告）就是正身，本页用 WKWebView 直接渲染该文件。
// 两份绘制实现必然漂移，HTML 的交互面客户端追不上。
//
// 页面职责收敛为三件事：
//   ① 触发引擎生成（index gen / confidence gen：建库 + 落置信度）
//   ② 触发引擎渲染（render index --confidence：复用或重绘，回执带版本）
//   ③ 把产物装进 WebView；打开即渲染（引擎复用判定生效时毫秒级），
//      上次的产物路径有缓存——**先秒开缓存图，再后台核验刷新**。
import SwiftUI

@MainActor
final class CodeGraphPageVM: ObservableObject {
    /// 单仓库限制：项目名在仓库面板的入口处锁定
    let projectName: String
    @Published var rendering = false
    @Published var generating = false
    @Published var error: String?
    @Published var htmlPath: String?
    @Published var reloadToken = 0
    @Published var status: (ok: Bool, text: String)?

    /// 上次渲染出的产物路径（进程内缓存）：窗口重开时秒开旧图再后台刷新
    private static var lastGoodPath: [String: String] = [:]

    init(projectName: String) {
        self.projectName = projectName
        htmlPath = Self.lastGoodPath[projectName]
    }

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

    /// render index --confidence：置信度缺席时引擎走纯结构渲染并恒发「无置信度数据」图例。
    /// `background` = 秒开缓存后的后台核验：产物仍是复用就不重载 WebView（不闪）。
    func render(background: Bool = false) async {
        if !background { rendering = true; error = nil }
        defer { rendering = false }
        do {
            let out = try await EngineCLI.shared.runData(
                ["render", "index", projectName, "--confidence"], timeout: 600)
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
                status = (false, receipt(text) ?? "render failed")
            }
        } catch {
            self.error = EngineError.userMessage(for: error)
            status = (false, self.error ?? "render failed")
        }
    }

    /// 生成 = LLM 驱动（用户定稿 2026-10-28）：播种引擎 skill 工作流给 agent，
    /// agent 关窗后回读产物（后台核验刷新）。
    func generate() async {
        generating = true
        _ = await GraphAgentTask.launch(project: projectName, kind: "graph") { [weak self] in
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

struct CodeGraphPage: View {
    let projectName: String
    @ObservedObject var vm: CodeGraphPageVM

    init(projectName: String) {
        self.projectName = projectName
        _vm = ObservedObject(wrappedValue: CodeGraphPageVM(projectName: projectName))
    }

    var body: some View {
        VStack(spacing: 0) {
            GraphHeaderView(
                icon: "point.3.connected.trianglepath.dotted",
                tint: .blue,
                title: "\(L10n.t("nav.graph")) · \(projectName)",
                subtitle: L10n.t("cgraph.subtitle"),
                generateTitle: L10n.t("cgraph.generate"),
                onGenerate: { Task { await vm.generate() } },
                generating: vm.generating,
                onRefresh: { Task { await vm.render() } },
                refreshing: vm.rendering,
                onOpenExternal: { vm.openExternal() },
                canOpenExternal: vm.htmlPath != nil)
            Divider()
            ZStack {
                GraphWebView(htmlPath: vm.htmlPath, reloadToken: vm.reloadToken)
                    .opacity(vm.htmlPath == nil ? 0 : 1)
                if vm.htmlPath == nil {
                    if vm.rendering {
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
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title).foregroundStyle(.tertiary)
            Text(projectName.isEmpty
                 ? L10n.t("graph.needProject")
                 : L10n.t("cgraph.renderFirst"))
                .foregroundStyle(.secondary)
        }
    }
}
