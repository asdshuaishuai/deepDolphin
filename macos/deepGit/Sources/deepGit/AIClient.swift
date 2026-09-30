// AIClient.swift — 引擎 CLI 的 Swift 便捷封装（类型安全的 API 界面）。
// 所有数据操作走 CLI 子进程，不走 HTTP 网络。
import Foundation

// MARK: - 便捷封装

extension EngineCLI {
    func status(light: Bool) async throws -> StatusEnvelope {
        var args = ["status", "--json", "--quiet"]
        if light { args.append("--quiet") }
        return try await runJSON(args, as: StatusEnvelope.self, timeout: 180)
    }

    func status(name: String) async throws -> ProjectStatus {
        try await runJSON(["status", name, "--json", "--quiet"], as: ProjectStatus.self, timeout: 60)
    }

    func dashboard() async throws -> Dashboard {
        try await runJSON(["dashboard", "--json"], as: Dashboard.self, timeout: 180)
    }

    func milestones() async throws -> MilestonesEnvelope {
        try await runJSON(["milestone", "list", "--json"], as: MilestonesEnvelope.self, timeout: 60)
    }

    func docs(name: String) async throws -> DocsEnvelope {
        try await runJSON(["context", name, "--json"], as: DocsEnvelope.self, timeout: 60)
    }

    func journal(name: String) async throws -> Data {
        try await runData(["journal", name, "--json"], timeout: 30)
    }

    func update(name: String, deep: Bool) async throws -> Data {
        let cmd = deep ? "deep" : "update"
        return try await runData([cmd, name, "--json", "--quiet"], timeout: deep ? 600 : 300)
    }

    func updateAll(deep: Bool) async throws -> Data {
        let cmd = deep ? "deep" : "update"
        return try await runData([cmd, "--json", "--quiet"], timeout: deep ? 1800 : 900)
    }

    func gitOp(project: String, op: String, message: String = "") async throws -> Data {
        var args = ["git", op, project]
        if !message.isEmpty { args += ["--message", message] }
        args.append("--json")
        return try await runData(args, timeout: 120)
    }

    func milestoneAction(project: String, name: String, action: String) async throws {
        let cmd = action == "remove" ? "remove" : action
        _ = try await runData(["milestone", cmd, project, name, "--json"], timeout: 30)
    }

    func addMilestone(project: String, name: String, tag: String, date: String) async throws {
        var args = ["milestone", "add", project, name]
        if !tag.isEmpty { args += ["--tag", tag] }
        if !date.isEmpty { args += ["--date", date] }
        args.append("--json")
        _ = try await runData(args, timeout: 30)
    }

    func scan(root: String, depth: Int) async throws -> Data {
        return try await runData(
            ["scan", root, "--depth", String(depth), "--json"],
            timeout: 300
        )
    }

    func addProject(path: String, name: String) async throws -> Data {
        var args = ["add", path]
        if !name.isEmpty { args += ["--name", name] }
        args.append("--json")
        return try await runData(args, timeout: 30)
    }

    func toolsManifest() async throws -> Data {
        try await runData(["tools", "--json"], timeout: 30)
    }

    func agentContext(scope: String, name: String, budget: Int) async throws -> Data {
        var args = ["context"]
        if scope == "project" { args.append(name) }
        args += ["--budget", String(budget), "--json"]
        return try await runData(args, timeout: 60)
    }
}
