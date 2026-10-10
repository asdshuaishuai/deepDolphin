// GraphPages.swift — 引擎新能力的三个页面：
//   GraphPage        代码图谱 + 交互架构图（scene 画布 + 符号/影响面检索）
//   ConfidencePage   代码置信度（六维度 + findings + LLM 复核提示词）
//   PatchCheckPage   补丁置信度三层体检（Layer1 算法 → 人工裁决 → Layer3 合并）
//
// 数据全部来自引擎 CLI（GraphService）；scene 渲染契约见 GraphScene.swift。
import SwiftUI

// MARK: - 项目选择器（三页共用）

struct GraphProjectPicker: View {
    @EnvironmentObject var model: AppModel
    @Binding var projectName: String

    var body: some View {
        Picker(L10n.t("graph.project"), selection: $projectName) {
            ForEach(model.projects) { p in
                Text(p.name).tag(p.name)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
    }
}

// MARK: - 代码图谱页

@MainActor
final class GraphPageVM: ObservableObject {
    @Published var projectName = ""
    @Published var loading = false
    @Published var error: String?
    @Published var overview: [String: Any] = [:]
    @Published var symbolQuery = ""
    @Published var symbolResult: [String: Any]?
    @Published var impactResult: [String: Any]?
    let canvas = ArchCanvasVM()

    func loadIfNeeded(all: [ProjectStatus]) async {
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

    func searchSymbol() async {
        let q = symbolQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        loading = true
        error = nil
        do {
            symbolResult = try await GraphService.loadSymbol(project: projectName, symbol: q)
            impactResult = try await GraphService.loadImpact(project: projectName, symbol: q)
        } catch {
            self.error = EngineError.userMessage(for: error)
        }
        loading = false
    }
}

struct GraphPage: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject var model: AppModel
    @StateObject private var vm = GraphPageVM()

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            bar
            if let err = vm.error {
                errorBanner(err)
            }
            HSplitView {
                canvasPane
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                sidePane
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380, maxHeight: .infinity)
            }
        }
        .task {
            if vm.projectName.isEmpty || !model.projects.contains(where: { $0.name == vm.projectName }) {
                await vm.loadIfNeeded(all: model.projects)
            }
        }
    }

    private var bar: some View {
        HStack(spacing: DSSpacing.md) {
            GraphProjectPicker(projectName: $vm.projectName)
            Button {
                Task { await vm.loadIfNeeded(all: model.projects) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(vm.loading || vm.projectName.isEmpty)
            .help(L10n.t("common.refresh"))
            .accessibilityLabel(A11y.label(L10n.t("common.refresh")))
            TextField(L10n.t("graph.symbolSearch"), text: $vm.symbolQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .onSubmit { Task { await vm.searchSymbol() } }
            Button(L10n.t("graph.lookup")) {
                Task { await vm.searchSymbol() }
            }
            .disabled(vm.loading || vm.symbolQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
            if vm.loading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
    }

    private func errorBanner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.sm)
            .background(.orange.opacity(0.08), in: DSRect.shape(DSRadius.control))
            .padding(.horizontal, DSSpacing.md)
    }

    /// 主画布区：scene 驱动 + 底部 chips / 警示 / 截断披露。
    private var canvasPane: some View {
        VStack(spacing: DSSpacing.sm) {
            ArchCanvasView(vm: vm.canvas)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            sceneFooter
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.bottom, DSSpacing.sm)
    }

    @ViewBuilder
    private var sceneFooter: some View {
        // 契约要求：警示与截断必须如实披露（缺键不得当作「没有」）。
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

    /// 右侧：选中节点详情面板，或符号/影响面检索结果。
    @ViewBuilder
    private var sidePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                if let panel = vm.canvas.selectedPanel {
                    panelCard(panel)
                }
                if let sym = vm.symbolResult {
                    symbolCard(sym)
                }
                if let impact = vm.impactResult {
                    impactCard(impact)
                }
                if vm.symbolResult == nil && vm.canvas.selectedPanel == nil {
                    Text(L10n.t("graph.sideHint"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DSSpacing.md)
        }
        .frame(maxHeight: .infinity)
    }

    /// 详情面板（契约两级形状：架构级带 langs，文件级没有——langs 必须允许缺席）。
    private func panelCard(_ panel: [String: Any]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(panel["title"] as? String ?? "").font(.headline)
                Text(panel["sub"] as? String ?? "")
                    .font(.callout).foregroundStyle(.secondary)
                Text(panel["stats"] as? String ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                if let langs = panel["langs"] as? [String], !langs.isEmpty {
                    Text(L10n.t("graph.langs") + ": " + langs.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                depRows(L10n.t("graph.outDeps"), panel["out"])
                depRows(L10n.t("graph.inDeps"), panel["in"])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.sm)
        }
    }

    private func depRows(_ title: String, _ raw: Any?) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(title).font(.caption.weight(.semibold))
            if let list = raw as? [[String: Any]], !list.isEmpty {
                ForEach(Array(list.enumerated()), id: \.offset) { _, d in
                    HStack {
                        Text(d["id"] as? String ?? "").font(.caption)
                        Spacer()
                        Text("\(d["w"] as? Int ?? 0)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(L10n.t("graph.noDeps")).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func symbolCard(_ sym: [String: Any]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(L10n.t("graph.symbolCard")).font(.headline)
                let defs = sym["defs"] as? [[String: Any]] ?? []
                ForEach(Array(defs.enumerated()), id: \.offset) { _, d in
                    Text("\(d["file"] as? String ?? ""):\(d["line"] as? Int ?? 0)")
                        .font(.system(.caption, design: .monospaced))
                }
                if defs.isEmpty {
                    Text(L10n.t("graph.symbolNotFound")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.sm)
        }
    }

    private func impactCard(_ impact: [String: Any]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(L10n.t("graph.impactCard")).font(.headline)
                if let files = impact["files"] as? [String], !files.isEmpty {
                    ForEach(files, id: \.self) { f in
                        Text(f).font(.system(.caption, design: .monospaced))
                    }
                } else {
                    Text(L10n.t("graph.noDeps")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.sm)
        }
    }
}

// MARK: - 代码置信度页

@MainActor
final class ConfidencePageVM: ObservableObject {
    @Published var projectName = ""
    @Published var loading = false
    @Published var error: String?
    @Published var report: [String: Any] = [:]
    @Published var promptCopied = false

    func load(all: [ProjectStatus]) async {
        if projectName.isEmpty, let first = all.first { projectName = first.name }
        guard !projectName.isEmpty else { return }
        loading = true
        error = nil
        do {
            report = try await GraphService.loadConfidence(project: projectName)
        } catch {
            self.error = EngineError.userMessage(for: error)
        }
        loading = false
    }

    /// LLM 复核提示词（--llm 出纯文本）→ 复制到剪贴板。
    func copyPrompt() async {
        do {
            let prompt = try await GraphService.confidencePrompt(project: projectName)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            promptCopied = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            promptCopied = false
        } catch {
            self.error = EngineError.userMessage(for: error)
        }
    }
}

struct ConfidencePage: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject var model: AppModel
    @StateObject private var vm = ConfidencePageVM()

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.md) {
                GraphProjectPicker(projectName: $vm.projectName)
                Button(L10n.t("confidence.run")) {
                    Task { await vm.load(all: model.projects) }
                }
                .disabled(vm.loading || vm.projectName.isEmpty)
                Button {
                    Task { await vm.copyPrompt() }
                } label: {
                    Label(vm.promptCopied ? L10n.t("confidence.copied") : L10n.t("confidence.copyPrompt"),
                          systemImage: vm.promptCopied ? "checkmark" : "doc.on.doc")
                }
                .disabled(vm.report.isEmpty)
                Spacer()
                if vm.loading { ProgressView().controlSize(.small) }
            }
            .padding(DSSpacing.md)
            if let err = vm.error {
                Text(err).foregroundStyle(.orange).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DSSpacing.md)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    if vm.report.isEmpty {
                        Text(L10n.t("confidence.hint"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, DSSpacing.xl)
                    } else {
                        reportBody
                    }
                }
                .padding(DSSpacing.lg)
            }
        }
        .task {
            if vm.projectName.isEmpty { await vm.load(all: model.projects) }
        }
    }

    @ViewBuilder
    private var reportBody: some View {
        let score = vm.report["score"] as? Int ?? 0
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            VStack {
                Text("\(score)").font(DSTypography.metric)
                    .foregroundStyle(score >= 80 ? .green : score >= 50 ? .orange : .red)
                Text(L10n.t("confidence.score")).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                if let dims = vm.report["dimensions"] as? [[String: Any]] {
                    ForEach(Array(dims.enumerated()), id: \.offset) { _, d in
                        dimensionRow(d)
                    }
                }
            }
            Spacer()
        }
        // 降级/覆盖披露必须原样展示（契约：不许静默）
        if let note = vm.report["astNote"] as? String, !note.isEmpty {
            Text(note)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpacing.sm)
                .background(.quaternary.opacity(0.4), in: DSRect.shape(DSRadius.control))
        }
        findingsList
    }

    private func dimensionRow(_ d: [String: Any]) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text(d["label"] as? String ?? "")
                .font(.callout).frame(width: 150, alignment: .leading)
            let score = d["score"] as? Int ?? 0
            ProgressView(value: Double(score), total: 100)
                .frame(maxWidth: 260)
                .tint(score >= 80 ? .green : score >= 50 ? .orange : .red)
            Text("\(score)")
                .font(.callout.monospacedDigit()).frame(width: 34, alignment: .trailing)
            if let detail = d["detail"] as? String, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var findingsList: some View {
        let findings = vm.report["findings"] as? [[String: Any]] ?? []
        Text(L10n.t("confidence.findings", findings.count))
            .font(.headline)
        ForEach(Array(findings.enumerated()), id: \.offset) { _, f in
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text(f["kindLabel"] as? String ?? f["kind"] as? String ?? "")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.orange.opacity(0.14), in: Capsule())
                    Text("\(f["file"] as? String ?? ""):\(f["line"] as? Int ?? 0)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(f["symbol"] as? String ?? "").font(.caption)
                    Spacer()
                }
                Text(f["evidence"] as? String ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.sm)
            .background(.quaternary.opacity(0.35), in: DSRect.shape(DSRadius.control))
        }
    }
}

// MARK: - 补丁置信度三层体检页

@MainActor
final class PatchCheckVM: ObservableObject {
    @Published var projectName = ""
    @Published var running = false
    @Published var error: String?
    @Published var layer1: [String: Any]?
    /// uncertain 条目的裁决：id → ("resolved" | "unresolved" | "ambiguous", 置信度)
    @Published var verdicts: [String: (verdict: String, confidence: Double)] = [:]
    @Published var final: [String: Any]?

    func run(all: [ProjectStatus]) async {
        if projectName.isEmpty, let first = all.first { projectName = first.name }
        guard let project = all.first(where: { $0.name == projectName }) else { return }
        running = true
        error = nil
        layer1 = nil
        final = nil
        verdicts = [:]
        do {
            let diff = try await GraphService.workingDiff(projectPath: project.path)
            guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                error = L10n.t("patch.noDiff")
                running = false
                return
            }
            let r = try await GraphService.patchConfidence(project: projectName, diffText: diff)
            layer1 = r
            // 预填默认裁决：全部 deferred → 用户逐条改
            for u in r["uncertain"] as? [[String: Any]] ?? [] {
                if let id = u["id"] as? String {
                    verdicts[id] = ("ambiguous", 0.5)
                }
            }
        } catch {
            self.error = EngineError.userMessage(for: error)
        }
        running = false
    }

    func setVerdict(id: String, verdict: String, confidence: Double) {
        verdicts[id] = (verdict, confidence)
    }

    /// Layer 3：把人工裁决合成 agent.json 喊引擎合并出 final。
    func merge() async {
        guard let alg = layer1 else { return }
        running = true
        error = nil
        do {
            let items: [[String: Any]] = verdicts.map { id, v in
                ["id": id, "verdict": v.verdict, "confidence": v.confidence,
                 "reason": "deepDolphin 人工裁决"]
            }
            final = try await GraphService.mergePatch(
                algorithm: alg,
                agent: ["items": items])
        } catch {
            self.error = EngineError.userMessage(for: error)
        }
        running = false
    }
}

struct PatchCheckPage: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject var model: AppModel
    @StateObject private var vm = PatchCheckVM()

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.md) {
                GraphProjectPicker(projectName: $vm.projectName)
                Button(L10n.t("patch.run")) {
                    Task { await vm.run(all: model.projects) }
                }
                .disabled(vm.running || vm.projectName.isEmpty)
                if vm.layer1 != nil {
                    Button(L10n.t("patch.merge")) {
                        Task { await vm.merge() }
                    }
                    .disabled(vm.running)
                }
                Spacer()
                if vm.running { ProgressView().controlSize(.small) }
            }
            .padding(DSSpacing.md)
            if let err = vm.error {
                Text(err).foregroundStyle(.orange).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DSSpacing.md)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    if let final = vm.final {
                        finalCard(final)
                    }
                    if let l1 = vm.layer1 {
                        layer1Card(l1)
                    }
                    if vm.layer1 == nil && vm.error == nil {
                        Text(L10n.t("patch.hint"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, DSSpacing.xl)
                    }
                }
                .padding(DSSpacing.lg)
            }
        }
        .task {
            if vm.projectName.isEmpty { await vm.run(all: model.projects) }
        }
    }

    private func finalCard(_ f: [String: Any]) -> some View {
        let overall = f["overall"] as? Double ?? 0
        return GroupBox {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
                    Text(L10n.t("patch.final")).font(.headline)
                    Text("\(Int(overall * 100))")
                        .font(DSTypography.metric)
                        .foregroundStyle(overall >= 0.8 ? .green : overall >= 0.5 ? .orange : .red)
                    if let reviewed = f["reviewed"] as? Int {
                        Text(L10n.t("patch.reviewed", reviewed))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let alerts = f["alerts"] as? [[String: Any]], !alerts.isEmpty {
                    ForEach(Array(alerts.enumerated()), id: \.offset) { _, a in
                        Text("[\(a["level"] as? String ?? "")] \(a["issue"] as? String ?? "") — \(a["detail"] as? String ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.sm)
        }
    }

    private func layer1Card(_ l1: [String: Any]) -> some View {
        let overall = l1["overall"] as? Double ?? 0
        let uncertain = l1["uncertain"] as? [[String: Any]] ?? []
        let signals = l1["signals"] as? [String: Any] ?? [:]
        return GroupBox {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text(L10n.t("patch.layer1")).font(.headline)
                    Text("\(Int(overall * 100))")
                        .font(DSTypography.metric.monospacedDigit())
                        .foregroundStyle(overall >= 0.8 ? .green : overall >= 0.5 ? .orange : .red)
                    Spacer()
                    Text(L10n.t("patch.uncertainCount", uncertain.count))
                        .font(.caption).foregroundStyle(.secondary)
                }
                // S1..S10 信号（null = 分母为 0，契约要求如实披露）
                HStack(spacing: DSSpacing.sm) {
                    ForEach(signals.keys.sorted(), id: \.self) { key in
                        if let v = signals[key] as? Double {
                            Text("\(key) \(Int(v * 100))")
                                .font(.caption2.monospacedDigit())
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        } else {
                            Text("\(key) —")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary.opacity(0.5), in: Capsule())
                        }
                    }
                }
                // uncertain 裁决列表（Layer 2 就是人/agent 在这里干活）
                ForEach(Array(uncertain.enumerated()), id: \.offset) { _, u in
                    uncertainRow(u)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.sm)
        }
    }

    private func uncertainRow(_ u: [String: Any]) -> some View {
        let id = u["id"] as? String ?? ""
        let binding = Binding<String>(
            get: { vm.verdicts[id]?.verdict ?? "ambiguous" },
            set: { v in
                switch v {
                case "resolved": vm.setVerdict(id: id, verdict: v, confidence: 0.9)
                case "unresolved": vm.setVerdict(id: id, verdict: v, confidence: 0.05)
                default: vm.setVerdict(id: id, verdict: "ambiguous", confidence: 0.5)
                }
            })
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text(u["issue"] as? String ?? "").font(.caption.weight(.semibold))
                Spacer()
                Picker("", selection: binding) {
                    Text(L10n.t("patch.v.confirmed")).tag("resolved")
                    Text(L10n.t("patch.v.unresolved")).tag("unresolved")
                    Text(L10n.t("patch.v.unsure")).tag("ambiguous")
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 150)
            }
            Text(u["detail"] as? String ?? "").font(.caption).foregroundStyle(.secondary)
            if let file = u["file"] as? String {
                Text("\(file):\(u["line"] as? Int ?? 0)")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(.quaternary.opacity(0.35), in: DSRect.shape(DSRadius.control))
    }
}
