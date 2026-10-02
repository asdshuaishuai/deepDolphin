// AIClient.swift — 引擎 CLI 的 Swift 便捷封装（类型安全的 API 界面）。
// 所有数据操作走 CLI 子进程，不走 HTTP 网络。
import Foundation

// MARK: - 便捷封装

extension EngineCLI {
    /// 全项目状态。
    ///
    /// 引擎 CLI 的 `status --json` **恒定返回 envelope**（单项目/零项目/多项目同形状）——
    /// cli.cj 的注释原话：「恒定 envelope 形状：单项目/零项目/全部停用也与多项目一致
    /// （客户端契约）」。不存在裸 ProjectStatus 这个形状。
    func status(light: Bool) async throws -> StatusEnvelope {
        let data = try await runData(["status", "--json", "--quiet"], timeout: 30)
        return try decodeEnvelopeOrBare(data, context: "status")
    }

    /// 单项目状态。
    ///
    /// ⚠️ 原来这里按**裸 ProjectStatus** 解码，而引擎返回 `{projects, summary, language}`
    /// —— 实测 `DecodingError.keyNotFound: Key 'id' not found`，**100% 必崩**。
    /// 后果：每次打开项目详情页（DetailViews 的 .task 调 loadProject）都抛错，
    /// 橙条常驻；每次 gitOp / update 之后也抛错；而 projectDetails[name] 永不写入，
    /// 详情页永久回落到列表数据。
    ///
    /// 同文件的 status(light:) 本来就有「先试 envelope 再试裸」的兜底，
    /// 唯独这里没有 —— 引擎侧根本没有第二个形状可兜，所以那是遗漏不是有意。
    /// 现在两个方法共用同一个 decodeEnvelopeOrBare。
    func status(name: String) async throws -> ProjectStatus {
        let data = try await runData(["status", name, "--json", "--quiet"], timeout: 60)
        let env = try decodeEnvelopeOrBare(data, context: "status \(name)")
        guard let match = env.projects.first(where: { $0.name == name })
                ?? env.projects.first,
              !env.projects.isEmpty else {
            // 引擎返回了空 projects —— 这是「查无此项」或「采集全失败」，
            // 不能凭空造一个空壳 ProjectStatus，那会让 UI 显示「一切正常」。
            throw EngineError.failed("未找到项目「\(name)」的状态（引擎返回了空列表）")
        }
        return match
    }

    /// envelope 优先、裸对象兜底的解码。
    ///
    /// 兜底不是「怕引擎变契约」，而是防御**旧版已安装引擎**：客户端可能比引擎新，
    /// 用户机器上装的是还没改成恒定 envelope 的旧二进制。两种形状都能读，
    /// 就不会因为客户端升级而把老引擎的用法读崩。
    func decodeEnvelopeOrBare(_ data: Data, context: String) throws -> StatusEnvelope {
        if let env = try? JSONDecoder().decode(StatusEnvelope.self, from: data) {
            return env
        }
        if let single = try? JSONDecoder().decode(ProjectStatus.self, from: data) {
            // 裸形状（老版引擎）没有 language，置 nil 而非编造一个默认语言。
            return StatusEnvelope(projects: [single], summary: nil, language: nil)
        }
        // 走到这里说明 stdout 既不是 envelope 也不是 ProjectStatus。
        // 把原文带出去，否则用户只看到一句「无法解析」。
        let raw = String(data: data, encoding: .utf8) ?? ""
        let head = raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
        throw EngineError.failed("引擎输出无法解析（\(context)）：\(head.isEmpty ? "stdout 为空" : String(head)))")
    }

    func dashboard() async throws -> Dashboard {
        try await runJSON(["dashboard", "--json"], as: Dashboard.self, timeout: 180)
    }

    func milestones() async throws -> MilestonesEnvelope {
        try await runJSON(["milestone", "list", "--json"], as: MilestonesEnvelope.self, timeout: 60)
    }

    func docs(name: String) async throws -> DocsEnvelope {
        // 引擎 deepgit docs <项目> --json 输出 {docs:[{file,content}]}
        try await runJSON(["docs", name, "--json"], as: DocsEnvelope.self, timeout: 60)
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
        // UI 词汇 "open" → 引擎 CLI 词汇 "reopen"
        let cmd = action == "open" ? "reopen" : action
        _ = try await runData(["milestone", cmd, project, name, "--json"], timeout: 30)
    }

    func addMilestone(project: String, name: String, tag: String, date: String, desc: String = "") async throws {
        var args = ["milestone", "add", project, name]
        if !tag.isEmpty { args += ["--tag", tag] }
        if !date.isEmpty { args += ["--date", date] }
        if !desc.isEmpty { args += ["--desc", desc] }
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

    // 这里原来还有一个 `agentContext(scope:name:budget:)`。
    // 它是**死代码**：全仓零调用点，且与 `AgentCore.rawGet("api/context")`
    // 的实现逐字相同（同样的 args 拼装、同样的 timeout: 60）。
    //
    // 为什么留着是隐患而不只是冗余：它把「怎么拉上下文」这个约定
    // 复制成了两份。哪天 AgentCore 那边加了 `--depth` 之类的东西，
    // 这份不会跟着改 —— 而它**看起来还能用**，只是没人调。
    // 「同一份约定抄多处，漏一处就破」这个引擎已经栽到第 9 例。
    //
    // 拉上下文的唯一入口现在是 `AgentCore.rawGet("api/context")`。
}
