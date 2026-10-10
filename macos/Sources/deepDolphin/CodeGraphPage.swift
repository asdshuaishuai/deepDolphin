// CodeGraphPage.swift — 代码图谱页（与架构图是两个东西）。
//
// 形态参考 deepOrca 的 SymbolGraphView：**以符号为中心的三列关系图**——
// 引用方 | 焦点符号 | 影响面，点击任一文件卡就选中它；渐进披露
// （每列先出前 N 条，"更多"再放一批，hub 符号也能秒出图）。
//
// 与置信度的结合：`graph confidence` 的 findings 按文件聚合，文件卡右上角
// 挂疑点徽标（罚分越高越红）——图谱回答「谁连着谁」，置信度回答「哪里不能信」。
// 选中文件后，下方列出该文件的疑点（披露式：收起=位置，点击展开实码）。
//
// 注意：引擎的引用是**词法级**（file → 引用计数），不是编译器闭包——
// 列头与提示文案都带这个限定。
import SwiftUI

@MainActor
final class CodeGraphVM: ObservableObject {
    @Published var projectName = ""
    @Published var focusSymbol = ""
    @Published var loading = false
    @Published var error: String?

    struct TreeFile: Identifiable {
        let path: String
        let lang: String
        let lines: Int
        let symbolCount: Int
        let inDeg: Int          // 被引用数（referenceEdges 入度）
        let outDeg: Int         // 引用数（出度）
        let penalty: Int
        let findingCount: Int
        var id: String { path }
    }

    struct FileChip: Identifiable {
        let file: String
        /// 影响面列携带的受影响符号名（引用方列为空）。
        let symbol: String
        let weight: Int          // 引用权重（引用方列）
        let penalty: Int         // 该文件的置信度罚分（findings 权重合计）
        let findingCount: Int
        var id: String { file + "#" + symbol }
    }

    @Published var defs: [[String: Any]] = []
    /// 关系树：按被引用数降序的文件清单（图谱的「索引关系树」半边）。
    @Published var treeFiles: [TreeFile] = []
    @Published var callers: [FileChip] = []
    @Published var impacts: [FileChip] = []
    /// 每文件置信度罚分与条数（findings 按文件聚合）。
    @Published var penaltyByFile: [String: (penalty: Int, count: Int)] = [:]
    @Published var allFindings: [[String: Any]] = []
    /// 选中的文件（下方列出该文件疑点，披露式展开实码）。
    @Published var selectedFile: String?

    // 渐进披露（deepOrca 的 band 思路：先小批量出图，"更多"再放一批）
    @Published var callerBand = 12
    @Published var impactBand = 12
    let bandStep = 24

    func load(all: [ProjectStatus], symbol: String? = nil) async {
        if projectName.isEmpty, let first = all.first { projectName = first.name }
        let q = symbol ?? focusSymbol
        guard !projectName.isEmpty, !q.isEmpty else { return }
        loading = true
        error = nil
        do {
            async let sym = GraphService.loadSymbol(project: projectName, symbol: q)
            async let imp = GraphService.loadImpact(project: projectName, symbol: q)
            async let conf = GraphService.loadConfidence(project: projectName)
            async let tree = GraphService.loadTree(project: projectName)
            let (s, i, c, t) = try await (sym, imp, conf, tree)
            applyConfidence(c)
            applyTree(t)
            defs = s["defs"] as? [[String: Any]] ?? []
            let refs = s["referencedBy"] as? [[String: Any]] ?? []
            callers = refs.map { r in
                let f = r["file"] as? String ?? ""
                return FileChip(file: f, symbol: "", weight: r["weight"] as? Int ?? 0,
                                penalty: penaltyByFile[f]?.penalty ?? 0,
                                findingCount: penaltyByFile[f]?.count ?? 0)
            }
            .sorted { $0.weight > $1.weight }
            // ⚠️ 引擎 impactJson 的键是 refFiles（[String]）与 impactedSymbols
            // （[{file,symbol,kind}]），没有 "files"——第一版读错键，影响面列恒空
            // （自测抓到）。影响面用符号级清单，chip 显示 file · symbol。
            let impacted = i["impactedSymbols"] as? [[String: Any]] ?? []
            impacts = impacted.map { d in
                let f = d["file"] as? String ?? ""
                return FileChip(file: f, symbol: d["symbol"] as? String ?? "",
                                weight: 0,
                                penalty: penaltyByFile[f]?.penalty ?? 0,
                                findingCount: penaltyByFile[f]?.count ?? 0)
            }
            focusSymbol = q
            selectedFile = nil
            callerBand = 12
            impactBand = 12
        } catch {
            self.error = EngineError.userMessage(for: error)
        }
        loading = false
    }

    /// 关系树 → 按被引用数降序的文件清单（入度/出度/符号数 + 置信度罚分）。
    func applyTree(_ t: [String: Any]) {
        let files = t["files"] as? [[String: Any]] ?? []
        var inDeg: [String: Int] = [:]
        var outDeg: [String: Int] = [:]
        for e in t["referenceEdges"] as? [[Any]] ?? [] {
            guard e.count >= 3,
                  let from = e[0] as? String, let to = e[1] as? String,
                  let w = e[2] as? Int else { continue }
            outDeg[from, default: 0] += w
            inDeg[to, default: 0] += w
        }
        treeFiles = files.map { f in
            let path = f["path"] as? String ?? ""
            let syms = f["symbols"] as? [[String: Any]] ?? []
            return TreeFile(
                path: path,
                lang: f["lang"] as? String ?? "",
                lines: f["lines"] as? Int ?? 0,
                symbolCount: syms.count,
                inDeg: inDeg[path] ?? 0,
                outDeg: outDeg[path] ?? 0,
                penalty: penaltyByFile[path]?.penalty ?? 0,
                findingCount: penaltyByFile[path]?.count ?? 0)
        }
        .sorted { $0.inDeg > $1.inDeg }
    }

    /// findings 按文件聚合 → 罚分表。
    func applyConfidence(_ c: [String: Any]) {
        let fs = c["findings"] as? [[String: Any]] ?? []
        allFindings = fs
        var agg: [String: (Int, Int)] = [:]
        for f in fs {
            let file = f["file"] as? String ?? ""
            let w = f["weight"] as? Int ?? 0
            let cur = agg[file] ?? (0, 0)
            agg[file] = (cur.0 + w, cur.1 + 1)
        }
        penaltyByFile = agg.mapValues { (penalty: $0.0, count: $0.1) }
    }

    func findings(in file: String) -> [[String: Any]] {
        allFindings.filter { ($0["file"] as? String ?? "") == file }
    }

    var projectPath: String {
        AppModel.shared.projects.first { $0.name == projectName }?.path ?? ""
    }
}

struct CodeGraphPage: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var vm = CodeGraphVM()
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                bar
                if let err = vm.error {
                    Text(err).foregroundStyle(.orange).font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if vm.defs.isEmpty && !vm.loading {
                    emptyHint
                } else {
                    threeColumns
                    fileDetail
                    treeSection
                }
            }
            .padding(DSSpacing.lg)
        }
        .task {
            if vm.projectName.isEmpty && !model.projects.isEmpty {
                vm.projectName = model.projects.first!.name
            }
        }
    }

    private var bar: some View {
        HStack(spacing: DSSpacing.md) {
            GraphProjectPicker(projectName: $vm.projectName)
            TextField(L10n.t("cgraph.search"), text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit { Task { await vm.load(all: model.projects, symbol: query) } }
            Button(L10n.t("cgraph.center")) {
                Task { await vm.load(all: model.projects, symbol: query) }
            }
            .disabled(vm.loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
            if vm.loading { ProgressView().controlSize(.small) }
            Spacer()
        }
    }

    private var emptyHint: some View {
        Text(L10n.t("cgraph.hint"))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, DSSpacing.xl)
    }

    /// 三列：引用方 | 焦点符号 | 影响面（词法级，列头带限定）。
    private var threeColumns: some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            chipColumn(L10n.t("cgraph.callers"), chips: vm.callers, band: $vm.callerBand)
            focusColumn
            chipColumn(L10n.t("cgraph.impactCol"), chips: vm.impacts, band: $vm.impactBand)
        }
    }

    private func chipColumn(_ title: String, chips: [CodeGraphVM.FileChip], band: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(title).font(DSTypography.sectionTitle)
            let visible = chips.prefix(band.wrappedValue)
            ForEach(Array(visible.enumerated()), id: \.offset) { _, chip in
                fileChip(chip)
            }
            if chips.count > band.wrappedValue {
                Button(L10n.t("cgraph.more", chips.count - band.wrappedValue)) {
                    band.wrappedValue += vm.bandStep
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            if chips.isEmpty {
                Text(L10n.t("graph.noDeps")).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileChip(_ chip: CodeGraphVM.FileChip) -> some View {
        Button {
            vm.selectedFile = (vm.selectedFile == chip.file) ? nil : chip.file
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Text(chip.symbol.isEmpty ? chip.file : chip.file + " · " + chip.symbol)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                // 置信度徽标：罚分越高越红（图谱 × 置信度的结合点）
                if chip.findingCount > 0 {
                    Text("⚠\(chip.findingCount)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, DSSpacing.xs).padding(.vertical, DSSpacing.sm)
                        .background(chip.penalty >= 20 ? Color.red :
                                        chip.penalty >= 8 ? Color.orange : Color.gray,
                                    in: Capsule())
                }
                if chip.weight > 0 {
                    Text("×\(chip.weight)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, DSSpacing.sm).padding(.vertical, DSSpacing.xs)
            .background(
                // ⚠️ 三元两侧必须同族：Color 与 HierarchicalShapeStyle 不能直接混
                vm.selectedFile == chip.file
                    ? AnyShapeStyle(Color.accentColor.opacity(0.14))
                    : AnyShapeStyle(.quaternary.opacity(0.4)),
                in: DSRect.shape(DSRadius.chip))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var focusColumn: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(L10n.t("cgraph.focus")).font(DSTypography.sectionTitle)
            Text(vm.focusSymbol.isEmpty ? L10n.t("cgraph.hint") : vm.focusSymbol)
                .font(DSTypography.metric)
            ForEach(Array(vm.defs.enumerated()), id: \.offset) { _, d in
                Text("\(d["file"] as? String ?? ""):\(d["line"] as? Int ?? 0) · \(d["kind"] as? String ?? "")")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(L10n.t("cgraph.lexicalNote"))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .background(.quaternary.opacity(0.3), in: DSRect.shape(DSRadius.control))
    }

    /// 关系树：文件级被引用排行（入度/出度/符号数 + 置信度徽标）。
    /// 点击行 = 选中文件，与上方三列共享同一个详情区。
    private var treeSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(L10n.t("cgraph.treeTitle")).font(DSTypography.sectionTitle)
            Text(L10n.t("cgraph.treeHint"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(vm.treeFiles) { f in
                Button {
                    vm.selectedFile = (vm.selectedFile == f.path) ? nil : f.path
                } label: {
                    HStack(spacing: DSSpacing.sm) {
                        Text(f.path)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        if f.findingCount > 0 {
                            Text("⚠\(f.findingCount)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, DSSpacing.xs)
                                .background(f.penalty >= 20 ? Color.red :
                                                f.penalty >= 8 ? Color.orange : Color.gray,
                                            in: Capsule())
                        }
                        Text(L10n.t("cgraph.depsIn", f.inDeg))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Text(L10n.t("cgraph.depsOut", f.outDeg))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        Text(L10n.t("cgraph.syms", f.symbolCount))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, DSSpacing.sm).padding(.vertical, DSSpacing.xs)
                    .background(vm.selectedFile == f.path
                                ? AnyShapeStyle(Color.accentColor.opacity(0.14))
                                : AnyShapeStyle(.clear),
                                in: DSRect.shape(DSRadius.chip))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 选中文件的疑点（披露式：点击展开实码）。
    @ViewBuilder
    private var fileDetail: some View {
        if let file = vm.selectedFile {
            let findings = vm.findings(in: file)
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(L10n.t("cgraph.fileFindings", file, findings.count))
                    .font(DSTypography.sectionTitle)
                if findings.isEmpty {
                    Text(L10n.t("cgraph.fileClean"))
                        .font(.caption).foregroundStyle(.secondary)
                }
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
