// AgentBulkUpdate.swift —「一键全量」：对**所有**已注册仓库跑一次更新。
//
// 【为什么要有这个，而不是把顶栏那两个按钮改成「全部」】
// 顶栏双轨按钮的范围由 `selection` 推导：停在某个项目上时它就是「浅更新 · deepGit」。
// 那是对的（用户在看哪个仓库，就更新哪个），但它**没有**一个永远指向全群的入口 ——
// Dock 菜单与 CommandMenu 的「全部浅更新」也只有浅的那一轨，深的那一轨没有对应项。
// 于是「把所有仓库都更新一遍」这件事在不同入口下要么范围含糊、要么干脆没有。
//
// 【「基于 AI agent 执行」在这里的具体含义 —— 不要泛读成「顺便让 AI 写个摘要」】
// 更新**执行本身**走的是 `AgentCore.executeTool`，也就是 agent 工具循环
// 用的同一条执行点：同一份工具清单（`tools --json`）、同一套必填校验、
// 同一个 CLI 通道。区别只在**谁来决定跑哪些仓库** ——
//   · agent 对话：模型自己决定（那是它的工作）
//   · 一键全量：**代码决定，逐个显式传项目名**
// 这条边界是刻意的：全量的价值就是「一个不漏」，
// 而「跑哪些仓库」一旦交给模型，就有可能少跑一个而界面上看不出来。
// 把「全量」交给概率，等于把用户唯一能预期的那件事变成不可预期。
//
// ⚠️ 老坑 NC31：`run_shallow_update` 传**空**项目名，引擎侧等于「整个项目群」。
// 所以这里逐个显式传名，且必填校验走的是 agent 循环同一份清单（不许客户端自造）。
import Foundation

enum AgentBulkUpdate {

    /// 全量批次计数。只给 `Report.id` 用 —— 让结果面板能挂 `.sheet(item:)`。
    private static var bulkRunCounter = 0

    /// 引擎导出的两个更新工具名。**不许在客户端另写一份字符串**：
    /// 引擎改名而客户端不改，失败会表现为「全量按钮点了没反应」，
    /// 而不是一条能被看见的报错。
    static func toolName(deep: Bool) -> String {
        deep ? "run_deep_update" : "run_shallow_update"
    }

    /// 单个仓库的执行结果。
    struct Outcome {
        let name: String
        let ok: Bool
        /// 失败时是**引擎/工具给的原因**，不是客户端编的。
        let detail: String
    }

    /// 整批的结果。AI 简报是**可选的一层**，不是结果本身。
    ///
    /// `Identifiable` 是为了能挂 `.sheet(item:)`：结果要等跑完才知道，
    /// 而 `.sheet(isPresented:)` 得配一个**独立**的 Bool，
    /// 那个 Bool 与结果一旦不同步就会出现「空面板」或「面板关不掉」。
    struct Report: Identifiable {
        let deep: Bool
        let outcomes: [Outcome]
        /// 本次实际尝试的仓库数（= 已注册项目数，一个不漏）。
        let attempted: Int
        /// AI 简报正文。空 = 没生成，原因看 `aiNote`。
        let aiText: String
        /// AI 那一层发生了什么/为什么没发生。**永远有值**（成功也给），
        /// 否则「没生成」和「生成了一篇空的」在界面上长得一样。
        let aiNote: String

        /// 同一次全量可能连着跑（用户确认一次、再确认一次），
        /// 身份按「跑了多少次」区分，不按内容 —— 内容会重复。
        let id: Int = { AgentBulkUpdate.bulkRunCounter += 1; return AgentBulkUpdate.bulkRunCounter }()

        var succeeded: Int { outcomes.filter(\.ok).count }
        var failed: Int { outcomes.count - succeeded }

        /// 逐仓库明细。**这一段永远生成，且不含任何 AI 成分** ——
        /// 界面上「哪些仓库更新了、哪些没更」是事实陈述，
        /// 放进模型生成的 markdown 里就变成了「模型说哪些更新了」。
        ///
        /// ⚠️ 用**列表**不用表格：第一版是 markdown 表格，真 app 一跑就被
        /// 撑爆了（备份路径很长，表格单元不换行 ⇒ 右侧整段被截掉）。
        /// 列表能换行，而且逐条读比横着扫更适合「每个仓库两三行」这种密度。
        var outcomeMarkdown: String {
            guard !outcomes.isEmpty else { return "_没有已注册的项目，本次什么也没做。_" }
            let items = outcomes.map { o in
                "- **\(o.name)**　\(o.ok ? "✅" : "❌")　\(escapeCell(o.detail))"
            }
            // ⚠️ 这里原来写的是「\(succeeded)/\(outcomes.count) 完成」。
            // 真 app 一跑就看出问题：上一行刚说完「成功 3 个，失败 3 个」，
            // 下一行紧接着写「3/6 完成」—— **同一件事用了两个词**
            // （「成功」和「完成」），而两个词在中文里不总是同义：
            // 用户很容易把「3/6 完成」读成「6 个里完成了 3 个」之外的别的分母，
            // 或者以为失败的 3 个不算在 6 里。
            // ⇒ 判据家族里已经有「一屏之内不许出现两个答案」，
            //   **措辞也算** —— 数字对但换个词说，照样是分叉。
            // 改成与上一行同一个词，并把失败的条数也说清，不必读者自己做减法。
            let failed = outcomes.count - succeeded
            let tally = failed > 0
                ? "成功 \(succeeded) · 失败 \(failed)"
                : "\(succeeded) 个仓库全部成功"
            return """
            ## 逐仓库结果（\(tally)）

            \(items.joined(separator: "\n"))
            """
        }

        /// 整份结果面板的 markdown。
        var markdown: String {
            let head = """
            # \(deep ? "深度更新" : "浅更新") · 全量

            已注册项目 **\(attempted)** 个，本次实际执行 **\(outcomes.count)** 个，
            成功 **\(succeeded)** 个，失败 **\(failed)** 个。

            """
            var tail = "\n\n## AI 简报\n\n\(aiNote)\n"
            if !aiText.isEmpty {
                tail += "\n" + aiText + "\n"
            }
            return head + outcomeMarkdown + tail
        }

        private func escapeCell(_ s: String) -> String {
            s.replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: " ")
        }
    }

    /// 跑一次全量。
    ///
    /// ⚠️ `projects` 必须是**注册表里的全部项目**，不能是「采集成功的那些」。
    /// 引擎的 `status --json` 会把采集失败的项目也放进 `projects` 数组（带 `error`），
    /// 所以 `AppModel.projects` 本身就是全量名单；取 `summary.projectCount`
    /// 反而会漏掉坏掉的项目 —— 那正是最需要被告知「这个仓库更新不了」的那些。
    ///
    /// ⚠️ 一个仓库失败**不中断**整批：第 2 个仓库失败就整个退出的话，
    /// 「全量」变成了「跑到一半」，而界面上只会说「更新完成」。
    static func run(deep: Bool, projects: [ProjectStatus]) async -> Report {
        let tool = toolName(deep: deep)
        let required = await AgentCore.requiredParamsByTool()

        var outcomes: [Outcome] = []
        outcomes.reserveCapacity(projects.count)
        for p in projects {
            // 路径已经读不出来的项目：引擎那边必然失败，而工具调用会把原因带回来。
            // 这里**不预先跳过** —— 跳过就等于把「这个仓库没更新」从结果里抹掉，
            // 而界面上「全量完成」会让人以为每个仓库都动过了。
            let (ok, text) = await AgentCore.executeTool(
                tool,
                params: ["name": p.name],
                parametersJSONByName: required
            )
            outcomes.append(Outcome(
                name: p.name,
                ok: ok,
                detail: ok ? describe(text, fallback: p.name) : text
            ))
        }

        let ai = await digest(deep: deep, outcomes: outcomes)
        return Report(deep: deep, outcomes: outcomes, attempted: projects.count,
                      aiText: ai.text, aiNote: ai.note)
    }

    /// 工具返回的是**引擎的原始 JSON**（`{ok, mode, project, docs:[…], journalEntry:{…}}`）。
    ///
    /// ⚠️ 第一版直接把这段 JSON 塞进结果表格。真 app 一跑就看出来两件事：
    ///   · 表格被撑爆（面板右侧截断），`projectId` / `journalEntry` 这些
    ///     内部字段对用户零意义却占满整行；
    ///   · 更糟的是它把「哪个文档被改了、有没有备份」这条**用户唯一需要的信息**
    ///     埋在一堆字段里 —— 而项目里早就有说这件事的唯一口径
    ///     （`updateOutcomeSummary`，为缺陷 #211 写的：区分「没报文档 /
    ///     报了没变 / 真动了」三态，有备份必须说备份在哪）。
    /// 所以这里解码后转调那一个口径，**不另写一份措辞**。
    /// 解不出来就只说「已完成」，不退回到「已刷新」那句假话。
    private static func describe(_ raw: String, fallback: String) -> String {
        guard let data = raw.data(using: .utf8),
              let env = try? JSONDecoder().decode(UpdateResultEnvelope.self, from: data) else {
            return "已完成（引擎未返回可读的结果明细）"
        }
        return updateOutcomeSummary(env.outcome, project: env.project.isEmpty ? fallback : env.project)
    }

    /// AI 简报那一层。
    ///
    /// ⚠️ AI 未配置时**不许假装跑过**：`AgentCore.run` 会抛
    /// 「AI 未配置：请在 AI 设置里选择 provider 并填写 API Key」，
    /// 那条消息本身就是用户该看到的行动指引，原样透出即可。
    /// 更新本身已经跑完了 —— 报「失败」会让人以为仓库没被动过。
    private static func digest(
        deep: Bool, outcomes: [Outcome]
    ) async -> (text: String, note: String) {
        let table = outcomes.map { "\($0.name)：\($0.ok ? "完成" : "失败（\($0.detail)）")" }
            .joined(separator: "\n")
        let question = """
        刚对**全部已注册项目**执行了\(deep ? "深度更新" : "浅更新")，逐仓库结果如下：

        \(table.isEmpty ? "（没有已注册项目）" : table)

        请生成 ≤200 字的中文简报：这次全量更新整体发生了什么、哪些仓库需要人处理
        （更新失败 / 长期未更新 / 有未提交改动 / 待合入分支）。只输出简报正文，不要复述表格。
        """
        do {
            let text = try await AgentCore.run(
                question: question, target: .group, maxRounds: 3
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return ("", "AI 已调用，但没有产出正文。更新本身已完成（见上表）。")
            }
            return (trimmed, "由 AI agent 依据引擎事实生成。")
        } catch {
            let msg = EngineError.userMessage(for: error)
            return ("", "未生成 AI 简报：\(msg)\n\n更新本身已经执行完毕，结果以上表为准。")
        }
    }
}
