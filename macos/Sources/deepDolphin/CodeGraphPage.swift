// CodeGraphPage.swift — 代码图谱页（图树主轴，与 HTML 交付物同构）。
//
// 形态：左树右详情双栏（HSplitView 可拖）——**代码图谱是代码层级关系的展示**：
// 项目 → 目录 → 文件 → 符号，严格四层。置信度不是独立板块，是树节点的
// **属性**：每行右侧挂 ⚠N 徽标（档位色随最高权重），目录/文件向上汇总；
// 详细疑点在被选中节点的「置信度」tab 里展开——图谱回答「谁在哪」，
// 置信度回答「哪里不能信」。
//
// 数据：`graph functions --json`（函数级图谱 + findings 内嵌 label/dim/evidence，
// engine c7a2ddc）× `graph confidence --json`（全局分数 + 孤儿 findings）×
// `graph tree --json`（文件/符号骨架）。⚠️ 不要改回读 tree 的 functionGraph
// 键——那个契约里没有这个键（恒为空，旧页面因此从没出过函数级内容）。
//
// 与引擎 HTML 高亮的分工：本页高亮走客户端自己的 SyntaxHighlight
// （AttributedString），引擎高亮只存在于导出的 HTML。
import SwiftUI

// MARK: - 树模型

enum GNodeKind { case root, dir, file, sym, type, boundary }

/// 一条置信度疑点（引擎 findings 的精简形态，字段与 CLI 契约对齐）。
struct GFinding: Identifiable {
    let kind: String       // raw id，如 high-complexity
    let label: String      // 人类可读，如 圈复杂度过高
    let dim: String        // 分组维度 variable/function/…
    let file: String
    let line: Int
    let weight: Int
    let evidence: String
    /// id 必须含文件：不同文件的同类同行号疑点在目录 roll-up 里会撞 id。
    var id: String { "\(file)#\(kind)#\(line)#\(weight)" }
}

/// 树节点。置信度是节点的属性（ownFindings + 向上汇总的 rollN/rollW）。
final class GNode: Identifiable {
    let kind: GNodeKind
    let id: String
    let name: String
    var path: String = ""           // dir/file: 相对路径；sym: 所在文件路径
    var kids: [GNode] = []
    weak var parent: GNode?
    // file
    var lang = ""
    var lines = 0
    // dir（汇总）
    var fileCount = 0
    // sym
    var symKind = ""
    var declLine = 0
    // 置信度属性
    var ownFindings: [GFinding] = []
    var rollN = 0
    var rollW = 0
    // 身份色相（黄金角 137.5° 散布）：出边颜色 = 来源节点色相（HTML 同源）
    var hue = 0

    init(kind: GNodeKind, id: String, name: String) {
        self.kind = kind
        self.id = id
        self.name = name
    }

    /// 节点（含子树）的全部 findings——文件/目录详情的「置信度」tab 用。
    /// sym 只看自己；容器节点收集整棵子树（pill 数字与详情条数必须一致）。
    func collectFindings(_ out: inout [GFinding]) {
        out.append(contentsOf: ownFindings)
        for c in kids { c.collectFindings(&out) }
    }

    var subtreeFindings: [GFinding] {
        var out: [GFinding] = []
        collectFindings(&out)
        return out
    }
}

struct GTreeRow: Identifiable {
    let node: GNode
    let depth: Int
    var id: String { node.id }
}

// MARK: - 视图模型

@MainActor
final class CodeGraphVM: ObservableObject {
    enum DetailTab { case source, conf, rel }

    @Published var projectName: String

    init(projectName: String) {
        self.projectName = projectName
    }
    @Published var loading = false
    @Published var error: String?
    @Published var query = "" { didSet { if oldValue != query { searchOvr.removeAll(); rebuildRows() } } }
    @Published private(set) var rows: [GTreeRow] = []
    @Published private(set) var expanded: Set<String> = []
    @Published var selID: String?
    /// 热力图下钻：nil = 全部文件层；非 nil = 该文件的符号层
    @Published var heatDrill: GNode?
    /// 文件级引用边（graph tree --json 的 referenceEdges：架构口径，
    /// 与 HTML 交付物文件层调用边同一数据源）
    @Published private(set) var fileEdges: [(from: String, to: String, w: Int)] = []
    /// 符号级调用边（functionEdges：w = 调用次数，tier = direct/resolved/guessed）
    @Published private(set) var symEdges: [(from: String, to: String, w: Int, tier: String)] = []

    /// 热力图数据面：当前层级应铺排的节点（nil = 根下所有文件，跨目录；
    /// 钻取态 = 该文件的符号，按声明行序）
    func heatNodes() -> [GNode] {
        if let f = heatDrill {
            return f.kids.filter { $0.kind == .sym }.sorted { $0.declLine < $1.declLine }
        }
        guard let root else { return [] }
        var out: [GNode] = []
        var stack = root.kids
        while let n = stack.popLast() {
            if n.kind == .file { out.append(n) }
            if n.kind == .dir { stack.append(contentsOf: n.kids) }
        }
        return out.sorted { $0.name < $1.name }
    }

    /// 热力图网格缓存（键 = 层级 + 画布尺寸 + 边数）。30fps 重绘只重画
    /// 时变项，重心扫描与走线不每帧重跑。
    private var heatGridCache: (key: String, cards: [CGCard], routes: [CGEdgeRoute])?

    /// 热力图网格（卡片 + 走线），键命中即复用。
    func heatGrid(size: CGSize) -> (cards: [CGCard], routes: [CGEdgeRoute]) {
        let key = "\(heatDrill?.id ?? "all")|\(Int(size.width))x\(Int(size.height))|\(fileEdges.count + symEdges.count)"
        if let c = heatGridCache, c.key == key { return (c.cards, c.routes) }
        let cards = CGLayout.layout(vm: self, nodes: heatNodes(), in: size)
        let routes = CGEdgeRouting.routes(vm: self, cards: cards)
        heatGridCache = (key, cards, routes)
        return (cards, routes)
    }

    // MARK: 生成动作（GUI 具现化引擎能力：index_gen / confidence_gen / render）

    @Published var generating = false
    /// 引擎回执（末行）：版本/探针/自愈披露直接给用户看
    @Published var genStatus: String?
    /// 导出的交互 HTML 路径（render 回执提取）
    @Published var exportedPath: String?

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

    /// 生成索引 + 置信度（写 codegraph.db / index.json / confidence.json），
    /// 完成后重载页面数据——GUI 直接消化引擎的生成能力，不只读不写。
    func generate() async {
        generating = true
        genStatus = nil
        defer { generating = false }
        do {
            let r1 = try await EngineCLI.shared.runData(
                ["index", "gen", projectName, "--stats"], timeout: 600)
            let r2 = try await EngineCLI.shared.runData(
                ["confidence", "gen", projectName], timeout: 600)
            genStatus = receipt(String(data: r2, encoding: .utf8) ?? "")
                ?? receipt(String(data: r1, encoding: .utf8) ?? "")
            heatGridCache = nil   // 生成后数据全换，网格缓存失效
            await load()
        } catch {
            genStatus = EngineError.userMessage(for: error)
        }
    }

    /// 导出交互 HTML（render index --confidence；回执带路径与复用/新绘判定）
    func exportHTML() async {
        generating = true
        genStatus = nil
        defer { generating = false }
        do {
            let out = try await EngineCLI.shared.runData(
                ["render", "index", projectName, "--confidence"], timeout: 600)
            let text = String(data: out, encoding: .utf8) ?? ""
            exportedPath = extractHTMLPath(text)
            genStatus = receipt(text)
        } catch {
            genStatus = EngineError.userMessage(for: error)
        }
    }

    func openExport() {
        if let p = exportedPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        }
    }

    /// 当前层级的边：文件层 = referenceEdges（路径 → 节点 id "f:"+路径）；
    /// 符号层 = 同对聚合的 symEdges。tier 供 guessed 虚线；焦点退淡的
    /// 邻居判定也走这一份。
    func bubbleEdges() -> [(from: String, to: String, w: Int, tier: String)] {
        if let f = heatDrill {
            let ids = Set(f.kids.map(\.id))
            var agg: [String: (String, String, Int, String)] = [:]
            for e in symEdges where ids.contains(e.from) && ids.contains(e.to) {
                let k = e.from + "=>" + e.to
                if let old = agg[k] { agg[k] = (e.from, e.to, old.2 + e.w, old.3) }
                else { agg[k] = (e.from, e.to, e.w, e.tier) }
            }
            return agg.values.map { ($0.0, $0.1, $0.2, $0.3) }
        }
        return fileEdges.map { ("f:" + $0.from, "f:" + $0.to, $0.w, "resolved") }
    }

    /// 身份色相：黄金角 137.5° 散布（相邻节点色相差最大化），排序键与
    /// HTML 的 HUE_OF 相同（节点 id 字典序）。边颜色 = 来源节点色相。
    func assignHues() {
        var ids: [String] = []
        if let root {
            var stack = [root]
            while let n = stack.popLast() {
                if n.kind != .dir { ids.append(n.id) }
                stack.append(contentsOf: n.kids)
            }
        }
        ids.sort()
        for (i, id) in ids.enumerated() {
            nodeByID[id]?.hue = Int((Double(i) * 137.508).rounded()) % 360
        }
    }
    @Published var detailTab: DetailTab = .source
    @Published private(set) var score: Int = 100
    @Published private(set) var astNote = ""

    private var root: GNode?
    private var nodeByID: [String: GNode] = [:]
    private var snippets: [String: String] = [:]
    private var edges: [(from: String, to: String)] = []
    /// 搜索态的手动展开/收起覆盖（auto 展开是算出来的，别被刷新冲掉）。
    private var searchOvr: [String: Bool] = [:]
    /// 搜索态的可见性缓存（name 命中或后代命中）。
    private var visCache: [String: Bool] = [:]

    var selectedNode: GNode? {
        selID.flatMap { nodeByID[$0] }
    }

    var rootLoaded: Bool { root != nil }

    /// 全树第一个带疑点的符号（harness 首屏定位用；与展开态无关——
    /// rows 只含可见行，折叠的文件下 Symbol 行根本不在里面）。
    var firstRiskSymbol: GNode? {
        guard let root else { return nil }
        var queue = [root]
        while let n = queue.popLast() {
            if n.kind == .sym && !n.ownFindings.isEmpty { return n }
            queue.append(contentsOf: n.kids)
        }
        return nil
    }

    var projectPath: String {
        AppModel.shared.projects.first { $0.name == projectName }?.path ?? ""
    }

    // MARK: 加载

    func load() async {
        // 单仓库限制：项目名在 init 锁定（入口在具体仓库的面板）
        guard !projectName.isEmpty else { return }
        loading = true
        error = nil
        do {
            async let treeT = GraphService.loadTree(project: projectName)
            async let confT = GraphService.loadConfidence(project: projectName)
            async let fnT = GraphService.loadFunctions(project: projectName)
            let (t, c, f) = try await (treeT, confT, fnT)
            apply(tree: t, confidence: c, functions: f)
        } catch {
            self.error = EngineError.userMessage(for: error)
        }
        loading = false
    }

    private func apply(tree t: [String: Any], confidence c: [String: Any], functions f: [String: Any]) {
        score = c["score"] as? Int ?? 100
        astNote = c["astNote"] as? String ?? ""
        snippets = f["codeSnippets"] as? [String: String] ?? [:]
        edges = (f["functionEdges"] as? [[String: Any]] ?? []).compactMap { e in
            guard let from = e["from"] as? String, let to = e["to"] as? String else { return nil }
            return (from, to)
        }
        // 符号级调用边（带 w/tier）：热力图符号层画边用（guessed 虚线）
        symEdges = (f["functionEdges"] as? [[String: Any]] ?? []).compactMap { e in
            guard let from = e["from"] as? String, let to = e["to"] as? String else { return nil }
            return (from, to, e["w"] as? Int ?? 1, e["tier"] as? String ?? "resolved")
        }
        // 文件级引用边（架构口径，同 HTML 文件层调用边）；元素是 [from, to, w]
        fileEdges = (t["referenceEdges"] as? [[Any]] ?? []).compactMap { e in
            guard e.count >= 3, let a = e[0] as? String, let b = e[1] as? String else { return nil }
            return (a, b, e[2] as? Int ?? 1)
        }
        // findings：graph functions 的函数级 findings 已按符号体归属好；
        // confidence 侧再取一份孤儿（不落在任何符号体里的）挂到文件。
        // 归属键 = 文件+行号+kind：同名同行号的疑点在不同文件互不干扰。
        var fnFindings: [String: [GFinding]] = [:]   // fnId → findings
        var attributed = Set<String>()
        for fn in f["functions"] as? [[String: Any]] ?? [] {
            guard let id = fn["id"] as? String else { continue }
            let file = fn["file"] as? String ?? ""
            let list = (fn["findings"] as? [[String: Any]] ?? []).map { d -> GFinding in
                attributed.insert(file + "#" + (d["line"] as? Int ?? 0).description + "#" + (d["kind"] as? String ?? ""))
                return GFinding(d, file: file)
            }
            fnFindings[id] = list
        }
        var fileOrphans: [String: [GFinding]] = [:]
        for d in c["findings"] as? [[String: Any]] ?? [] {
            let file = d["file"] as? String ?? ""
            let key = file + "#" + (d["line"] as? Int ?? 0).description + "#" + (d["kind"] as? String ?? "")
            if !attributed.contains(key) {
                fileOrphans[file, default: []].append(GFinding(d, file: file))
            }
        }

        // 骨架：文件 → 目录树；符号挂在文件下（引擎 id：f:file:line:name）
        let rootName = (t["root"] as? String) ?? projectName
        let r = GNode(kind: .root, id: "root", name: (rootName as NSString).lastPathComponent)
        var dirs: [String: GNode] = [:]
        func dirNode(_ segs: [Substring]) -> GNode {
            let path = segs.joined(separator: "/")
            if let d = dirs[path] { return d }
            let parent = segs.count == 1 ? r : dirNode(Array(segs[0..<segs.count - 1]))
            let d = GNode(kind: .dir, id: "d:" + path, name: String(segs.last!))
            d.path = path
            d.parent = parent
            parent.kids.append(d)
            dirs[path] = d
            return d
        }
        let files = t["files"] as? [[String: Any]] ?? []
        for fe in files {
            let path = fe["path"] as? String ?? ""
            let segs = path.split(separator: "/").map { $0 }
            guard let last = segs.last else { continue }
            let parentDir = segs.count == 1 ? r : dirNode(Array(segs[0..<segs.count - 1]))
            let fileNode = GNode(kind: .file, id: "f:" + path, name: String(last))
            fileNode.path = path
            fileNode.lang = fe["lang"] as? String ?? ""
            fileNode.lines = fe["lines"] as? Int ?? 0
            fileNode.parent = parentDir
            parentDir.kids.append(fileNode)
            let syms = fe["symbols"] as? [[String: Any]] ?? []
            for s in syms {
                let sid = s["id"] as? String
                    ?? "f:\(path):\(s["line"] as? Int ?? 0):\(s["name"] as? String ?? "")"
                let sn = GNode(kind: .sym, id: sid, name: s["name"] as? String ?? "")
                sn.path = path
                sn.lang = fileNode.lang
                sn.symKind = s["kind"] as? String ?? "func"
                sn.declLine = s["line"] as? Int ?? 0
                sn.parent = fileNode
                sn.ownFindings = fnFindings[sid] ?? []
                fileNode.kids.append(sn)
            }
            fileNode.ownFindings = fileOrphans[path] ?? []
        }
        root = r
        nodeByID = [:]
        func indexTree(_ n: GNode) {
            nodeByID[n.id] = n
            n.kids.forEach(indexTree)
        }
        indexTree(r)
        sortTree(r)
        rollup(r)
        // 默认展开：根 + 一级目录（同 HTML 交付物）
        expanded = [r.id]
        r.kids.forEach { if $0.kind == .dir { expanded.insert($0.id) } }
        selID = nil
        detailTab = .source
        // 热力图：身份色相（边色 = 来源节点色相）
        assignHues()
        rebuildRows()
    }

    /// 目录在前、文件在后，符号按声明行（同一文件的符号保持源码顺序）。
    private func sortTree(_ n: GNode) {
        n.kids.sort { a, b in
            let aw = a.kind == .dir ? 0 : (a.kind == .file ? 1 : 2)
            let bw = b.kind == .dir ? 0 : (b.kind == .file ? 1 : 2)
            if aw != bw { return aw < bw }
            if a.kind == .sym && b.kind == .sym { return a.declLine < b.declLine }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        n.kids.forEach(sortTree)
    }

    /// 调试/测试：根的直接子节点顺序（harness 日志用，验证目录在前的排序）。
    var rootKidsDebug: [(String, String)] {
        (root?.kids ?? []).map { node -> (String, String) in
            let tag = node.kind == .dir ? "d" : (node.kind == .file ? "f" : "s")
            return (tag, node.name)
        }
    }

    /// 置信度汇总：rollN = 子树疑点数，rollW = 子树最高权重（徽标档位色）。
    private func rollup(_ n: GNode) {
        var cnt = n.ownFindings.count
        var w = n.ownFindings.map(\.weight).max() ?? 0
        var files = 0
        for c in n.kids {
            rollup(c)
            cnt += c.rollN
            w = max(w, c.rollW)
            if c.kind == .file { files += 1 } else { files += c.fileCount }
        }
        n.rollN = cnt
        n.rollW = w
        n.fileCount = files
    }

    // MARK: 行扁平化（搜索 + 展开态）

    private var activeQuery: String {
        query.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func rebuildRows() {
        guard let root else { rows = []; return }
        let q = activeQuery
        visCache.removeAll()
        if !q.isEmpty { _ = visibleInSearch(root, q: q) }
        var out: [GTreeRow] = []
        walk(root, depth: 0, q: q, out: &out)
        rows = out
    }

    private func visibleInSearch(_ n: GNode, q: String) -> Bool {
        if let cached = visCache[n.id] { return cached }
        var hit = n.name.lowercased().contains(q)
        for c in n.kids where visibleInSearch(c, q: q) { hit = true }
        visCache[n.id] = hit
        return hit
    }

    private func walk(_ n: GNode, depth: Int, q: String, out: inout [GTreeRow]) {
        if !q.isEmpty, visCache[n.id] != true { return }
        out.append(GTreeRow(node: n, depth: depth))
        guard !n.kids.isEmpty else { return }
        if isOpen(n) {
            for c in n.kids { walk(c, depth: depth + 1, q: q, out: &out) }
        }
    }

    func isOpen(_ n: GNode) -> Bool {
        if activeQuery.isEmpty { return expanded.contains(n.id) }
        if let ovr = searchOvr[n.id] { return ovr }
        // 搜索态自动展开：有命中后代的节点展开（命中即见路径）
        return n.kids.contains { visCache[$0.id] == true }
    }

    func hasKids(_ n: GNode) -> Bool { !n.kids.isEmpty }

    // MARK: 交互

    func toggle(_ n: GNode) {
        guard !n.kids.isEmpty else { return }
        if activeQuery.isEmpty {
            if !expanded.insert(n.id).inserted { expanded.remove(n.id) }
        } else {
            searchOvr[n.id] = !isOpen(n)
        }
        rebuildRows()
    }

    /// 选中符号（或容器）并展开详情；reveal = 展开祖先让它可见。
    func select(_ n: GNode, tab: DetailTab? = nil, reveal: Bool = true) {
        if reveal {
            var p = n.parent
            while let cur = p {
                expanded.insert(cur.id)
                searchOvr[cur.id] = true
                p = cur.parent
            }
        }
        selID = n.id
        detailTab = tab ?? (n.kind == .sym ? .source : .conf)
        if reveal { rebuildRows() }
    }

    // MARK: 详情数据

    /// 源码 tab 的行（引擎内嵌截断实码 + 行号；finding 行高亮）。
    var sourceLines: [CodeSnippetLine]? {
        guard let n = selectedNode, n.kind == .sym, let code = snippets[n.id] else { return nil }
        let hitLines = Set(n.ownFindings.map(\.line))
        let raw = code.split(separator: "\n", omittingEmptySubsequences: false)
        guard !raw.isEmpty else { return nil }
        return raw.enumerated().map { idx, text in
            CodeSnippetLine(lineNumber: n.declLine + idx, text: String(text),
                            isHit: hitLines.contains(n.declLine + idx))
        }
    }

    var sourceLang: String {
        let l = selectedNode?.lang ?? ""
        return l.isEmpty ? "cangjie" : l
    }

    /// 关系 tab：函数级调用边（词法近似，见引擎 functionGraphData 注释）。
    var callers: [GNode] {
        guard let id = selID else { return [] }
        return edges.compactMap { $0.to == id ? nodeByID[$0.from] : nil }
    }
    var callees: [GNode] {
        guard let id = selID else { return [] }
        return edges.compactMap { $0.from == id ? nodeByID[$0.to] : nil }
    }
}

extension GFinding {
    init(_ d: [String: Any], file: String) {
        kind = d["kind"] as? String ?? ""
        label = d["label"] as? String ?? kind
        dim = d["dim"] as? String ?? "structure"
        self.file = file
        line = d["line"] as? Int ?? 0
        weight = d["weight"] as? Int ?? 0
        evidence = d["evidence"] as? String ?? ""
    }
}

// MARK: - 档位色 / 语言点色（与 HTML 交付物同源）

private enum Tier {
    static func color(_ w: Int) -> Color {
        if w >= 8 { return .red }
        if w >= 5 { return .orange }
        return Color(nsColor: .systemGray)
    }
}

private enum LangDot {
    static func color(_ lang: String) -> Color {
        switch lang {
        case "swift": return Color(red: 0.94, green: 0.32, blue: 0.22)
        case "cangjie": return Color(red: 0.97, green: 0.50, blue: 0.12)
        case "ts": return Color(red: 0.19, green: 0.47, blue: 0.71)
        case "python": return Color(red: 0.21, green: 0.45, blue: 0.65)
        case "go": return Color(red: 0.00, green: 0.68, blue: 0.85)
        case "rust": return Color(red: 0.87, green: 0.65, blue: 0.52)
        case "java": return Color(red: 0.69, green: 0.45, blue: 0.10)
        case "kotlin": return Color(red: 0.66, green: 0.48, blue: 1.00)
        case "c": return Color(nsColor: .systemGray)
        default: return Color(nsColor: .systemGray)
        }
    }
}

/// 符号种类徽标字母（func/class/enum/struct/…）。
private enum KindBadge {
    static func letter(_ kind: String) -> String {
        switch kind {
        case "func", "function": return "F"
        case "class": return "C"
        case "enum": return "E"
        case "struct": return "S"
        case "interface": return "I"
        case "type", "typealias": return "T"
        default: return String(kind.prefix(1)).uppercased()
        }
    }
}

// MARK: - 页面

struct CodeGraphPage: View {
    /// 单仓库限制：项目名在仓库面板的入口处锁定（页面内无切换选择器）
    let projectName: String
    @ObservedObject var vm: CodeGraphVM

    /// 渲染 harness / 预载入口：注入已加载的 VM（离屏截图时引擎调用不能靠
    /// .task 时机，得先装好数据再挂视图）。
    init(projectName: String) {
        self.projectName = projectName
        _vm = ObservedObject(wrappedValue: CodeGraphVM(projectName: projectName))
    }
    /// harness 注入已加载好的 VM（离屏等待与页面判定同源）
    init(projectName: String, vm: CodeGraphVM) {
        self.projectName = projectName
        _vm = ObservedObject(wrappedValue: vm)
    }

    @State private var heatMode = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if let err = vm.error {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(err).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, DSSpacing.lg).padding(.vertical, DSSpacing.xs)
                Divider()
            }
            if let status = vm.genStatus {
                // 生成/导出回执：引擎的版本/探针/自愈披露直接给用户看
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "gearshape.2").foregroundStyle(.tertiary)
                    Text(status).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let p = vm.exportedPath {
                        Button(L10n.t("cgraph.export")) {
                            vm.openExport()
                        }
                        .buttonStyle(.borderless).controlSize(.small)
                        .help(p)
                        .accessibilityLabel(A11y.label(L10n.t("cgraph.export")))
                    }
                }
                .padding(.horizontal, DSSpacing.lg).padding(.vertical, DSSpacing.xs)
                Divider()
            }
            if vm.rootLoaded {
                HSplitView {
                    treePane
                        .frame(minWidth: 300, idealWidth: 360, maxWidth: 620)
                    detailPane
                        .frame(minWidth: 420, maxWidth: .infinity)
                        .layoutPriority(1)
                }
            } else if vm.loading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                emptyHint
            }
        }
        .task {
            // 单仓库限制：页面只在仓库面板打开（init 锁定），直接加载
            await vm.load()
        }
    }

    private var topBar: some View {
        HStack(spacing: DSSpacing.md) {
            // 单仓库限制：页面在仓库面板打开时锁死该仓库（无切换选择器）
            Image(systemName: "shippingbox").font(.caption).foregroundStyle(.tertiary)
            Text(projectName).font(.system(.caption, design: .monospaced).weight(.semibold))
            Button {
                Task { await vm.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("cgraph.reload"))
            .accessibilityLabel(A11y.label(L10n.t("cgraph.reload")))
            // 生成动作：GUI 具现化引擎的 index_gen + confidence_gen（写库/落盘）
            Button {
                Task { await vm.generate() }
            } label: {
                Image(systemName: "wand.and.stars")
            }
            .buttonStyle(.borderless)
            .disabled(vm.generating)
            .help(L10n.t("cgraph.generate"))
            .accessibilityLabel(A11y.label(L10n.t("cgraph.generate")))
            // 导出动作：GUI 具现化引擎的 render index --confidence（落盘交互 HTML）
            Button {
                Task { await vm.exportHTML() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(vm.generating)
            .help(L10n.t("cgraph.export"))
            .accessibilityLabel(A11y.label(L10n.t("cgraph.export")))
            if vm.loading || vm.generating { ProgressView().controlSize(.small) }
            Spacer()
            if vm.rootLoaded {
                Text(L10n.t("cgraph.scoreTitle") + " \(vm.score)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
    }

    private var emptyHint: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title).foregroundStyle(.tertiary)
            if vm.projectName.isEmpty {
                // 单仓库限制：未选定仓库 = 引导先选，不显示定位提示
                Text(L10n.t("graph.needProject"))
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(L10n.t("cgraph.hint"))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 左栏：代码图谱树

    private var treePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    .font(.caption)
                TextField(L10n.t("cgraph.treeSearch"), text: $vm.query)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                if !vm.query.isEmpty {
                    Button {
                        vm.query = ""
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                // 显示模式：列表树 / 符号索引热力图（treemap 原生画布）
                Picker(L10n.t("cgraph.heat"), selection: $heatMode) {
                    Text(L10n.t("cgraph.list")).tag(false)
                    Text(L10n.t("cgraph.heat")).tag(true)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel(A11y.label(L10n.t("cgraph.heat")))
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            Divider()
            if heatMode {
                // 符号索引热力图：treemap 原生画布（点文件下钻符号层，
                // 点符号选中 → 右栏详情；口径与 HTML 交付物一致）
                CodeGraphHeatView(vm: vm) { _ in }
            } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.rows) { row in
                        TreeRowView(vm: vm, node: row.node, depth: row.depth)
                    }
                    if vm.rows.isEmpty {
                        Text(L10n.t("cgraph.noResult"))
                            .font(.caption).foregroundStyle(.tertiary)
                            .padding(DSSpacing.md)
                    }
                }
                .padding(.vertical, DSSpacing.xs)
            }
            }
        }
        .background(.quaternary.opacity(0.18))
    }

    // MARK: 右栏：详情

    private var detailPane: some View {
        Group {
            if let n = vm.selectedNode {
                VStack(alignment: .leading, spacing: 0) {
                    detailHeader(n)
                    Divider()
                    tabBar(n)
                    Divider()
                    detailBody(n)
                }
            } else {
                VStack(spacing: DSSpacing.sm) {
                    Image(systemName: "sidebar.squares.left")
                        .font(.title2).foregroundStyle(.tertiary)
                    Text(L10n.t("cgraph.selectHint"))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func detailHeader(_ n: GNode) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
            Text(kindTag(n))
                .font(.caption2.weight(.bold).monospaced())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.14), in: DSRect.shape(DSRadius.chip))
            Text(n.name)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .lineLimit(1)
            Text(n.kind == .sym ? "\(n.path):\(n.declLine)" : n.path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if n.subtreeFindings.isEmpty {
                Label(L10n.t("cgraph.clean"), systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Text("⚠\(n.subtreeFindings.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Tier.color(n.rollW))
                    .help(L10n.t("cgraph.tabConf"))
                    .accessibilityLabel(A11y.label(L10n.t("cgraph.tabConf")))
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
    }

    private func kindTag(_ n: GNode) -> String {
        switch n.kind {
        case .sym: return n.symKind.uppercased()
        case .file: return L10n.t("cgraph.kFile")
        case .dir: return L10n.t("cgraph.kDir")
        case .root: return L10n.t("cgraph.kProject")
        case .type: return "TYPE"
        case .boundary: return "BOUNDARY"
        }
    }

    private func tabs(for n: GNode) -> [(CodeGraphVM.DetailTab, String)] {
        if n.kind == .sym {
            var out: [(CodeGraphVM.DetailTab, String)] = [(.source, L10n.t("cgraph.tabSource"))]
            if !n.ownFindings.isEmpty {
                out.append((.conf, "\(L10n.t("cgraph.tabConf")) (\(n.ownFindings.count))"))
            }
            out.append((.rel, L10n.t("cgraph.tabRel")))
            return out
        }
        return [(.conf, "\(L10n.t("cgraph.tabConf")) (\(n.subtreeFindings.count))")]
    }

    private func tabBar(_ n: GNode) -> some View {
        HStack(spacing: DSSpacing.lg) {
            ForEach(tabs(for: n), id: \.0) { tab, label in
                Button {
                    vm.detailTab = tab
                } label: {
                    VStack(spacing: DSSpacing.xs) {
                        Text(label)
                            .font(.callout.weight(vm.detailTab == tab ? .semibold : .regular))
                            .foregroundStyle(vm.detailTab == tab ? .primary : .secondary)
                        Rectangle()
                            .fill(vm.detailTab == tab ? Color.accentColor : .clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.sm)
    }

    @ViewBuilder
    private func detailBody(_ n: GNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch vm.detailTab {
                case .source: sourceTab(n)
                case .conf: confTab(n)
                case .rel: relTab(n)
                }
            }
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // 源码 tab：引擎内嵌实码 + 客户端 SyntaxHighlight（与引擎 HTML 高亮分工）
    @ViewBuilder
    private func sourceTab(_ n: GNode) -> some View {
        if let lines = vm.sourceLines {
            CodeSnippetView(lines: lines, lang: vm.sourceLang)
        } else {
            Text(L10n.t("cgraph.srcNa"))
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    // 置信度 tab：按维度分组，pill = 档位色 + 人类可读标签，证据自足
    private func confTab(_ n: GNode) -> some View {
        let findings = n.subtreeFindings
        return VStack(alignment: .leading, spacing: 0) {
            if !vm.astNote.isEmpty {
                Text(vm.astNote)
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.bottom, DSSpacing.sm)
            }
            if findings.isEmpty {
                Text(L10n.t("cgraph.clean"))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                let order = ["variable", "function", "type", "pointer", "concurrency", "structure"]
                let groups = Dictionary(grouping: findings, by: \.dim)
                ForEach(order.filter { groups[$0] != nil }, id: \.self) { dim in
                    let g = (groups[dim] ?? []).sorted { $0.weight > $1.weight }
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("\(dimTitle(dim)) · \(g.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, DSSpacing.sm)
                        ForEach(g) { f in
                            FindingRow(finding: f)
                        }
                    }
                }
                // 未知维度兜底（引擎新增 dim 时客户端不丢数据）
                ForEach(Array(groups.keys.filter { !order.contains($0) }.sorted()), id: \.self) { dim in
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("\(dim) · \(groups[dim]?.count ?? 0)")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            .padding(.top, DSSpacing.sm)
                        ForEach(groups[dim] ?? []) { f in FindingRow(finding: f) }
                    }
                }
            }
        }
    }

    private func dimTitle(_ dim: String) -> String {
        L10n.t("cgraph.dim." + dim)
    }

    // 关系 tab：调用方 / 被调，点击 = 左树 re-center 该符号
    private func relTab(_ n: GNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            relSection(title: L10n.t("cgraph.callersTitle"), nodes: vm.callers,
                       empty: L10n.t("cgraph.noCallers"))
            relSection(title: L10n.t("cgraph.calleesTitle"), nodes: vm.callees,
                       empty: L10n.t("cgraph.noCallees"))
            Text(L10n.t("cgraph.lexicalNote"))
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.top, DSSpacing.md)
        }
    }

    private func relSection(title: String, nodes: [GNode], empty: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("\(title) · \(nodes.count)")
                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                .padding(.top, DSSpacing.sm)
            ForEach(nodes) { peer in
                Button {
                    vm.select(peer, tab: .source)
                } label: {
                    HStack(spacing: DSSpacing.sm) {
                        Text(peer.name)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Text(peer.path)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if !peer.ownFindings.isEmpty {
                            Text("⚠\(peer.ownFindings.count)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(Tier.color(peer.rollW))
                        }
                        Image(systemName: "arrow.turn.down.left")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, DSSpacing.sm).padding(.vertical, DSSpacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if nodes.isEmpty {
                Text(empty).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 树行（置信度徽标是行内属性，不是独立板块）

private struct TreeRowView: View {
    @ObservedObject var vm: CodeGraphVM
    let node: GNode
    let depth: Int

    private var selected: Bool { vm.selID == node.id }

    var body: some View {
        HStack(spacing: 6) {
            chevron
            leading
            Text(node.name)
                .font(.system(node.kind == .sym ? .caption : .callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            meta
            pill
        }
        .padding(.leading, DSSpacing.xs + CGFloat(depth) * 14)
        .padding(.trailing, DSSpacing.sm)
        .frame(height: node.kind == .root ? 32 : (node.kind == .sym ? 22 : 26))
        .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.clear),
                    in: DSRect.shape(DSRadius.chip))
        .contentShape(Rectangle())
        .onTapGesture {
            if node.kind == .sym {
                vm.select(node, tab: .source, reveal: false)
            } else {
                vm.toggle(node)
            }
        }
    }

    @ViewBuilder
    private var chevron: some View {
        if vm.hasKids(node) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(vm.isOpen(node) ? 90 : 0))
                .frame(width: 12)
                .onTapGesture { vm.toggle(node) }
        } else {
            Color.clear.frame(width: 12)
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch node.kind {
        case .root:
            Image(systemName: "cube.fill")
                .font(.caption2).foregroundStyle(.secondary)
        case .dir:
            Image(systemName: "folder.fill")
                .font(.caption2).foregroundStyle(Color(nsColor: .systemBlue).opacity(0.7))
        case .file:
            Circle()
                .fill(LangDot.color(node.lang))
                .frame(width: 7, height: 7)
        case .sym:
            Text(KindBadge.letter(node.symKind))
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
                .background(.quaternary.opacity(0.6), in: DSRect.shape(DSRadius.chip))
        case .type, .boundary:
            // 列表树不呈现这两类（热力图专属），占位空视图保穷尽
            EmptyView()
        }
    }

    @ViewBuilder
    private var meta: some View {
        switch node.kind {
        case .file:
            if node.lines > 0 {
                Text("\(node.lines)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
        case .sym:
            Text("\(node.declLine)")
                .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
        case .dir:
            // 裸数字 + tooltip（同 HTML 交付物）；带单位文案在 1 时会出「1 files」
            Text("\(node.fileCount)")
                .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                .help(L10n.t("cgraph.filesUnit", node.fileCount))
                .accessibilityLabel(A11y.label(L10n.t("cgraph.filesUnit", node.fileCount)))
        case .root:
            Text("\(vm.score)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        case .type, .boundary:
            EmptyView()
        }
    }

    /// ⚠N 徽标：置信度作为树节点属性的唯一视觉表达，档位色 = 子树最高权重。
    @ViewBuilder
    private var pill: some View {
        if node.rollN > 0 {
            Text("⚠\(node.rollN)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(Tier.color(node.rollW))
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Tier.color(node.rollW).opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(Tier.color(node.rollW).opacity(0.45), lineWidth: 0.5))
                .help(pillHelp)
                .accessibilityLabel(A11y.label(pillHelp))
                .onTapGesture { vm.select(node, tab: .conf, reveal: false) }
        }
    }

    private var pillHelp: String {
        let agg = Dictionary(grouping: node.subtreeFindings, by: \.label)
            .map { "\($0.key) ×\($0.value.count)" }
            .sorted()
            .joined(separator: "、")
        return agg.isEmpty ? L10n.t("cgraph.tabConf") : agg
    }
}

// MARK: - 疑点行（置信度 tab 内）

private struct FindingRow: View {
    let finding: GFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: DSSpacing.sm) {
                Text(finding.label)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(Tier.color(finding.weight))
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Tier.color(finding.weight).opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Tier.color(finding.weight).opacity(0.45), lineWidth: 0.5))
                    .help("\(finding.kind) w\(finding.weight)")
                    .accessibilityLabel(A11y.label("\(finding.kind) w\(finding.weight)"))
                Spacer()
                // 目录/项目 roll-up 里一条疑点来自哪个文件必须可见（HTML 版缺这个）
                Text("\(finding.file):\(finding.line)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if !finding.evidence.isEmpty {
                Text(finding.evidence)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}
