// GraphScene.swift — 引擎图谱服务的 Swift 桥（数据面）。
//
// ⚠️ 用户定稿 2026-10-27：架构图/代码图谱**不再原生绘制**——本文件原有的
// moongit-graph-scene v1 场景模型（GraphTheme/GraphScene/GraphSceneViewData
// + token 解析）随原生 Canvas 驱动一起删除，引擎侧 scene 出口同步移除；
// 交付正身 = 引擎 render 的交互 HTML，客户端用 WKWebView 直接渲染。
// 这里只保留仍然有消费方的 JSON 数据面（置信度体检页在用）。
import Foundation
import SwiftUI

enum GraphServiceError: LocalizedError {
    case badScene(String)

    var errorDescription: String? {
        switch self {
        case .badScene(let why): return L10n.t("graph.err.scene", why)
        }
    }
}

/// 引擎图谱数据的 Swift 桥。全部走 EngineCLI 子进程（与既有数据通道同一条）。
enum GraphService {
    static func runJSON(_ args: [String], timeout: TimeInterval = 180) async throws -> [String: Any] {
        let data = try await EngineCLI.shared.runData(args, timeout: timeout)
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw GraphServiceError.badScene("引擎输出不是 JSON 对象：\(args.joined(separator: " "))")
        }
        return dict
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
