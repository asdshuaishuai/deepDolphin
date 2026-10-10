// GraphPages.swift — 置信度页与补丁体检页。
//   ConfidencePage   代码置信度（六维度 + 披露式 findings：收起=位置，点击=实码）
//   PatchCheckPage   补丁置信度三层体检（Layer1 算法 → 人工裁决 → Layer3 合并；
//                    低置信度实体默认只告知位置，点击展开 diff 代码块）
// 代码图谱页见 CodeGraphPage.swift；架构图画布页见 ArchPage.swift。
import SwiftUI

// MARK: - 项目选择器（多页共用）

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

// MARK: - 代码置信度页

@MainActor
final class ConfidencePageVM: ObservableObject {
    @Published var projectName = ""
    @Published var loading = false
    @Published var error: String?
    @Published var report: [String: Any] = [:]
    @Published var promptCopied = false
    /// 只看高权重疑点（权重 ≥ 8：孤儿/占位/吞错/重复体这一档）。
    @Published var highWeightOnly = false

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

    /// 过滤后的 findings（引擎已按权重降序全序排列）。
    var findings: [[String: Any]] {
        let fs = report["findings"] as? [[String: Any]] ?? []
        guard highWeightOnly else { return fs }
        return fs.filter { ($0["weight"] as? Int ?? 0) >= 8 }
    }

    var projectPath: String {
        // findings 的 file 是仓库相对路径，读实码需要项目绝对路径
        AppModel.shared.projects.first { $0.name == projectName }?.path ?? ""
    }
}

struct ConfidencePage: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject var model: AppModel
    @StateObject private var vm = ConfidencePageVM()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.md) {
                GraphProjectPicker(projectName: $vm.projectName)
                Button(L10n.t("confidence.run")) {
                    Task { await vm.load(all: model.projects) }
                }
                .disabled(vm.loading || vm.projectName.isEmpty)
                Toggle(L10n.t("confidence.highOnly"), isOn: $vm.highWeightOnly)
                    .controlSize(.small)
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
        HStack(alignment: .top, spacing: DSSpacing.lg) {
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
                .background(.quaternary.opacity(0.4), in: DSRect.shape(DSRadius.control))
                .padding(DSSpacing.sm)
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

    /// findings：披露式行（收起=位置告知，点击=展开证据与实码）。
    @ViewBuilder
    private var findingsList: some View {
        let findings = vm.findings
        Text(L10n.t("confidence.findings", findings.count))
            .font(DSTypography.sectionTitle)
        Text(L10n.t("confidence.findingsHint"))
            .font(.caption).foregroundStyle(.secondary)
        ForEach(Array(findings.enumerated()), id: \.offset) { _, f in
            FindingDisclosureRow(
                projectPath: vm.projectPath,
                kindLabel: f["kind"] as? String ?? "",
                file: f["file"] as? String ?? "",
                line: f["line"] as? Int ?? 0,
                symbol: f["symbol"] as? String ?? "",
                weight: f["weight"] as? Int ?? 0,
                evidence: f["evidence"] as? String ?? ""
            )
        }
    }
}

// MARK: - 补丁置信度三层体检页

/// 一条补丁实体的低置信度展示：收起=位置告知，点击展开 diff 代码块。
struct PatchEntityRow: View {
    let diffText: String
    let entity: [String: Any]

    @State private var expanded = false
    @State private var lines: [CodeSnippetLine]?

    private var confidence: Double { entity["confidence"] as? Double ?? 0 }
    private var file: String { entity["file"] as? String ?? "" }
    private var line: Int { entity["line"] as? Int ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Button {
                expanded.toggle()
                if expanded && lines == nil {
                    lines = CodeSnippet.fromDiff(diffText, file: file, line: line)
                }
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    Text("\(Int(confidence * 100))%")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(confidence < 0.5 ? .red : confidence < 0.75 ? .orange : .secondary)
                    Text(entity["kind"] as? String ?? "")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(file):\(line)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                if let lines {
                    CodeSnippetView(lines: lines)
                } else {
                    Text(L10n.t("snippet.unreadable"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(DSSpacing.sm)
        .background(.quaternary.opacity(0.35), in: DSRect.shape(DSRadius.control))
    }
}

@MainActor
final class PatchCheckVM: ObservableObject {
    @Published var projectName = ""
    @Published var running = false
    @Published var error: String?
    @Published var layer1: [String: Any]?
    @Published var diffText = ""
    /// uncertain 条目的裁决：id → (verdict, 置信度)
    @Published var verdicts: [String: (verdict: String, confidence: Double)] = [:]
    @Published var final: [String: Any]?

    /// 低置信度实体（< 0.75），升序——最不可信的排最前。
    var lowConfidenceEntities: [[String: Any]] {
        let ents = layer1?["entities"] as? [[String: Any]] ?? []
        return ents
            .filter { ($0["confidence"] as? Double ?? 1) < 0.75 }
            .sorted { ($0["confidence"] as? Double ?? 1) < ($1["confidence"] as? Double ?? 1) }
    }

    func run(all: [ProjectStatus]) async {
        if projectName.isEmpty, let first = all.first { projectName = first.name }
        guard let project = all.first(where: { $0.name == projectName }) else { return }
        running = true
        error = nil
        layer1 = nil
        final = nil
        verdicts = [:]
        diffText = ""
        do {
            let diff = try await GraphService.workingDiff(projectPath: project.path)
            guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                error = L10n.t("patch.noDiff")
                running = false
                return
            }
            diffText = diff
            let r = try await GraphService.patchConfidence(project: projectName, diffText: diff)
            layer1 = r
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
        VStack(spacing: 0) {
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
                    if let f = vm.final {
                        finalCard(f)
                    }
                    if let l1 = vm.layer1 {
                        layer1Card(l1)
                        lowConfidenceSection
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
                    Text(L10n.t("patch.final")).font(DSTypography.sectionTitle)
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
                    Text(L10n.t("patch.layer1")).font(DSTypography.sectionTitle)
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
                                .padding(.horizontal, DSSpacing.xs).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        } else {
                            Text("\(key) —")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, DSSpacing.xs).padding(.vertical, 1)
                                .background(.quaternary.opacity(0.5), in: Capsule())
                        }
                    }
                }
                ForEach(Array(uncertain.enumerated()), id: \.offset) { _, u in
                    uncertainRow(u)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.sm)
        }
    }

    /// 低置信度代码块：默认收起（只告知位置与分数），点击展开 diff 实码。
    private var lowConfidenceSection: some View {
        let lows = vm.lowConfidenceEntities
        return GroupBox {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(L10n.t("patch.lowEntities", lows.count))
                    .font(DSTypography.sectionTitle)
                if lows.isEmpty {
                    Text(L10n.t("patch.lowEmpty"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L10n.t("patch.lowHint"))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(lows.enumerated()), id: \.offset) { _, e in
                        PatchEntityRow(diffText: vm.diffText, entity: e)
                    }
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
            if let ctx = u["context_ref"] as? [String: Any] {
                Text("\(ctx["file"] as? String ?? ""):\(ctx["line"] as? Int ?? 0)")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(.quaternary.opacity(0.35), in: DSRect.shape(DSRadius.control))
    }
}
