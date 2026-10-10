// GraphScene.swift — moongit-graph-scene v1 的 Swift 侧模型 + 引擎图谱服务。
//
// 契约：moonGit 仓库 docs/graph-scene-schema.md（两层）：
//   ① 渲染契约 = 标准 Canvas2D 子集（本文件 + ArchCanvasView 用 SwiftUI
//      Canvas/GraphicsContext 逐条对应：fillRect/strokeRect/arc/bezierCurveTo/
//      setLineDash/shadow/globalAlpha/font/textAlign/linearGradient）；
//   ② 数据契约 = 场景 JSON（本文件解析）。
//
// 【token 解析规则】颜色一律 token，四类形态：
//   "text"/"muted"/…           → themes.<主题> 直取
//   "cols.N" / "fills.N"       → themes.<主题>.cols/fills 数组下标
//   "langs.<lang>"             → themes.<主题>.langs 字典
//   "node:<id>"                → **二跳**：视图级 nodeTheme[<id>] 得到再一个
//                                token，递归解析。二跳结果必然落在前三类。
// 契约原文：引擎只发 token 表里存在的键；未知 token 视为引擎违约——
// 这里按 muted 兜底并保留日志，不静默当黑。
import Foundation
import SwiftUI

// MARK: - 主题

struct GraphTheme {
    let simple: [String: String]      // bg0/bg1/grid/text/muted/border/arrow/accent/panel
    let cols: [String]
    let fills: [String]
    let langs: [String: String]

    static func parse(_ dict: [String: Any]) -> GraphTheme {
        var simple: [String: String] = [:]
        for (k, v) in dict where k != "cols" && k != "fills" && k != "langs" {
            if let s = v as? String { simple[k] = s }
        }
        return GraphTheme(
            simple: simple,
            cols: dict["cols"] as? [String] ?? [],
            fills: dict["fills"] as? [String] ?? [],
            langs: dict["langs"] as? [String: String] ?? [:]
        )
    }
}

// MARK: - 视图

struct GraphSceneViewData {
    let id: String
    let label: String
    let parent: String
    let nodeTheme: [String: String]
    let shapes: [[String: Any]]
    let particles: [[String: Any]]
    let hits: [[String: Any]]
    let edgesDropped: Int
    /// 内容包围盒（契约 bounds: x0/y0/x1/y1）。
    let bx0: Double, by0: Double, bx1: Double, by1: Double

    static func parse(id: String, _ dict: [String: Any]) -> GraphSceneViewData {
        let b = dict["bounds"] as? [String: Any] ?? [:]
        func num(_ k: String) -> Double { b[k] as? Double ?? (b[k] as? Int).map(Double.init) ?? 0 }
        return GraphSceneViewData(
            id: id,
            label: dict["label"] as? String ?? id,
            parent: dict["parent"] as? String ?? "",
            nodeTheme: dict["nodeTheme"] as? [String: String] ?? [:],
            shapes: dict["shapes"] as? [[String: Any]] ?? [],
            particles: dict["particles"] as? [[String: Any]] ?? [],
            hits: dict["hits"] as? [[String: Any]] ?? [],
            edgesDropped: dict["edgesDropped"] as? Int ?? (dict["edgesDropped"] as? Int64).map(Int.init) ?? 0,
            bx0: num("x0"), by0: num("y0"), bx1: num("x1"), by1: num("y1")
        )
    }
}

// MARK: - 场景文档

struct GraphScene {
    let meta: [String: Any]
    let dark: GraphTheme
    let light: GraphTheme
    /// 保持引擎导出顺序（arch 在前，module:* 在后）。
    let views: [GraphSceneViewData]
    let panels: [String: [String: Any]]

    func view(_ id: String) -> GraphSceneViewData? {
        views.first { $0.id == id }
    }

    static func parse(_ data: Data) throws -> GraphScene {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let root = obj as? [String: Any] else {
            throw GraphServiceError.badScene("root 不是对象")
        }
        guard root["v"] as? Int == 1 else {
            // 契约版本不认识就明说，不做静默兼容
            throw GraphServiceError.badScene("场景版本不是 v1")
        }
        let themes = root["themes"] as? [String: Any] ?? [:]
        let viewsDict = root["views"] as? [String: Any] ?? [:]
        let views = viewsDict
            .compactMap { key, value -> GraphSceneViewData? in
                guard let d = value as? [String: Any] else { return nil }
                return GraphSceneViewData.parse(id: key, d)
            }
            .sorted { a, b in
                // arch 恒排第一；其余按引擎导出顺序（字典序，module:xxx）
                if a.id == "arch" { return true }
                if b.id == "arch" { return false }
                return a.id < b.id
            }
        return GraphScene(
            meta: root["meta"] as? [String: Any] ?? [:],
            dark: GraphTheme.parse(themes["dark"] as? [String: Any] ?? [:]),
            light: GraphTheme.parse(themes["light"] as? [String: Any] ?? [:]),
            views: views,
            panels: root["panels"] as? [String: [String: Any]] ?? [:]
        )
    }

    // MARK: token 解析

    func color(for token: String, theme isDark: Bool, view: GraphSceneViewData?) -> Color {
        let t = isDark ? dark : light
        if token.hasPrefix("node:") {
            // 二跳：node:<id> → 视图 nodeTheme[<id>] → 基础 token
            let id = String(token.dropFirst("node:".count))
            if let v = view, let next = v.nodeTheme[id] {
                return color(for: next, theme: isDark, view: nil)
            }
            return color(for: "text", theme: isDark, view: nil)
        }
        if token.hasPrefix("langs.") {
            let lang = String(token.dropFirst("langs.".count))
            if let hex = t.langs[lang] { return SwiftColor(hexOrRgba: hex) }
            return color(for: "text", theme: isDark, view: nil)
        }
        if token.hasPrefix("cols.") {
            let i = Int(token.dropFirst("cols.".count)) ?? -1
            if i >= 0 && i < t.cols.count { return SwiftColor(hexOrRgba: t.cols[i]) }
        } else if token.hasPrefix("fills.") {
            let i = Int(token.dropFirst("fills.".count)) ?? -1
            if i >= 0 && i < t.fills.count { return SwiftColor(hexOrRgba: t.fills[i]) }
        } else if let hex = t.simple[token] {
            return SwiftColor(hexOrRgba: hex)
        }
        // 未知 token = 引擎违约（契约原话），显式洋红兜底而不是悄悄融进背景
        return Color(red: 1.0, green: 0.0, blue: 0.8)
    }
}

/// #RRGGBB / #RRGGBBAA / rgba(r,g,b,a) → Color。
/// 引擎 themes 里两种形态都有（cols 是 #hex，fills 是 rgba()）。
func SwiftColor(hexOrRgba s: String) -> Color {
    let t = s.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("rgba") {
        let inner = t.dropFirst(4).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        let parts = inner.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count >= 4 {
            return Color(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, opacity: parts[3])
        }
    }
    var hex = String(t.dropFirst(t.hasPrefix("#") ? 1 : 0))
    if hex.count == 3 {
        hex = String(hex.map { "\($0)\($0)" }.joined())
    }
    guard hex.count >= 6, let v = UInt64(hex.prefix(6), radix: 16) else { return .gray }
    let r = Double((v >> 16) & 0xff) / 255
    let g = Double((v >> 8) & 0xff) / 255
    let b = Double(v & 0xff) / 255
    var a = 1.0
    if hex.count >= 8, let av = UInt64(hex.suffix(2), radix: 16) { a = Double(av) / 255 }
    return Color(red: r, green: g, blue: b, opacity: a)
}

// MARK: - 服务

enum GraphServiceError: LocalizedError {
    case badScene(String)

    var errorDescription: String? {
        switch self {
        case .badScene(let why): return L10n.t("graph.err.scene", why)
        }
    }
}

/// 引擎图谱七件套的 Swift 桥。全部走 EngineCLI 子进程（与既有数据通道同一条）。
enum GraphService {
    static func runJSON(_ args: [String], timeout: TimeInterval = 180) async throws -> [String: Any] {
        let data = try await EngineCLI.shared.runData(args, timeout: timeout)
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw GraphServiceError.badScene("引擎输出不是 JSON 对象：\(args.joined(separator: " "))")
        }
        return dict
    }

    static func loadScene(project: String) async throws -> GraphScene {
        let data = try await EngineCLI.shared.runData(
            ["graph", "arch", project, "--format", "scene"], timeout: 300)
        return try GraphScene.parse(data)
    }

    static func loadOverview(project: String) async throws -> [String: Any] {
        try await runJSON(["graph", "overview", project, "--json"])
    }

    static func loadSymbol(project: String, symbol: String) async throws -> [String: Any] {
        try await runJSON(["graph", "symbol", project, symbol, "--json"])
    }

    static func loadImpact(project: String, symbol: String) async throws -> [String: Any] {
        try await runJSON(["graph", "impact", project, symbol, "--json"])
    }

    static func loadConfidence(project: String) async throws -> [String: Any] {
        try await runJSON(["graph", "confidence", project, "--json"], timeout: 300)
    }

    /// --llm 出的是纯文本提示词（直接可喂模型），不是 JSON。
    static func confidencePrompt(project: String) async throws -> String {
        let data = try await EngineCLI.shared.runData(
            ["graph", "confidence", project, "--llm"], timeout: 300)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Layer 1：给一段 diff 文本，写临时文件后走引擎分析。
    static func patchConfidence(project: String, diffText: String) async throws -> [String: Any] {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("deepdolphin-patch-\(UUID().uuidString).diff")
        try diffText.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try await runJSON(
            ["graph", "patchconf", project, "--patch", tmp.path, "--json"], timeout: 300)
    }

    /// Layer 3：algorithm.json + agent.json → final。
    static func mergePatch(algorithm: [String: Any], agent: [String: Any]) async throws -> [String: Any] {
        let tmp = FileManager.default.temporaryDirectory
        let a = tmp.appendingPathComponent("dd-alg-\(UUID().uuidString).json")
        let g = tmp.appendingPathComponent("dd-agent-\(UUID().uuidString).json")
        let aData = try JSONSerialization.data(withJSONObject: algorithm, options: [.prettyPrinted])
        let gData = try JSONSerialization.data(withJSONObject: agent, options: [.prettyPrinted])
        try aData.write(to: a)
        try gData.write(to: g)
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: g)
        }
        return try await runJSON(
            ["graph", "patchconf", "--merge", a.path, g.path, "--json"], timeout: 120)
    }

    /// 项目工作区的未提交 diff（补丁体检的输入）。
    ///
    /// ⚠️ 走本机 git 而不是引擎：引擎的 git_op 白名单只有
    /// pull/push/commit/stash/unstash/fetch（没有 diff——它是读操作，
    /// 且引擎刻意不把任意 git 透传进白名单）。本机只读 `git diff` 不越权。
    static func workingDiff(projectPath: String) async throws -> String {
        let data = try await Task.detached(priority: .utility) { () throws -> Data in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["-C", projectPath, "diff", "HEAD"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            guard (try? proc.run()) != nil else {
                throw GraphServiceError.badScene("git 无法启动")
            }
            let out = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return out
        }.value
        return String(data: data, encoding: .utf8) ?? ""
    }
}
