// CodeGraphPage.swift — 代码图谱页（单仓库锁定，仓库面板入口触发）。
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
//   ③ 把产物装进 WebView（渲染后强制刷新）；外部打开只是入口便利
import SwiftUI

struct CodeGraphPage: View {
    let projectName: String
    @State private var htmlPath: String?
    @State private var reloadToken = 0
    @State private var rendering = false
    @State private var generating = false
    @State private var error: String?
    @State private var status: String?

    init(projectName: String) {
        self.projectName = projectName
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let err = error {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(err).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.xs)
            }
            if let status {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "gearshape.2").foregroundStyle(.tertiary)
                    Text(status).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.xs)
            }
            if htmlPath == nil && !rendering {
                emptyHint
            } else {
                GraphWebView(htmlPath: htmlPath, reloadToken: reloadToken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .task {
            // 单仓库限制：项目名在仓库面板入口处锁定，直接渲染
            if !projectName.isEmpty { await render() }
        }
    }

    private var topBar: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.caption).foregroundStyle(.tertiary)
            Text(projectName).font(.system(.caption, design: .monospaced).weight(.semibold))
            // 生成动作：GUI 具现化引擎的 index gen + confidence gen
            //（建库自愈在引擎侧；置信度缺席时 render 的图例会如实披露）
            Button {
                Task { await generate() }
            } label: {
                Label(L10n.t("cgraph.generate"), systemImage: "wand.and.stars")
            }
            .disabled(generating || rendering || projectName.isEmpty)
            // 渲染/刷新：render index（复用判定在引擎，产物新鲜代价小）
            Button {
                Task { await render() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(rendering || projectName.isEmpty)
            .help(L10n.t("cgraph.reload"))
            .accessibilityLabel(A11y.label(L10n.t("cgraph.reload")))
            Button {
                openExternal()
            } label: {
                Image(systemName: "safari")
            }
            .disabled(htmlPath == nil)
            .help(L10n.t("graph.openExternal"))
            .accessibilityLabel(A11y.label(L10n.t("graph.openExternal")))
            Spacer()
            if rendering || generating { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 引擎动作

    /// render index --confidence：置信度缺席时引擎走纯结构渲染并恒发「无置信度数据」图例。
    private func render() async {
        rendering = true
        error = nil
        defer { rendering = false }
        do {
            let out = try await EngineCLI.shared.runData(
                ["render", "index", projectName, "--confidence"], timeout: 600)
            let text = String(data: out, encoding: .utf8) ?? ""
            status = lastLine(text)
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

    /// 生成 = 建索引 + 生成置信度，随后重渲染。
    private func generate() async {
        generating = true
        status = nil
        defer { generating = false }
        do {
            let a = try await EngineCLI.shared.runData(["index", "gen", projectName], timeout: 600)
            status = lastLine(String(data: a, encoding: .utf8) ?? "")
            let b = try await EngineCLI.shared.runData(["confidence", "gen", projectName], timeout: 600)
            status = lastLine(String(data: b, encoding: .utf8) ?? "")
            await render()
        } catch {
            self.error = EngineError.userMessage(for: error)
        }
    }

    private func openExternal() {
        if let p = htmlPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        }
    }

    /// 引擎回执取末行（版本/复用判定给用户看）。
    private func lastLine(_ text: String) -> String? {
        for line in text.split(separator: "\n").reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// 回执里的产物绝对路径（`.html` 结尾的 `/…` 令牌）。
    private func extractHTMLPath(_ text: String) -> String? {
        for line in text.split(separator: "\n") {
            for token in line.split(separator: " ") {
                let t = token.trimmingCharacters(in: .whitespaces)
                if t.hasSuffix(".html") && t.hasPrefix("/") { return t }
            }
        }
        return nil
    }
}
