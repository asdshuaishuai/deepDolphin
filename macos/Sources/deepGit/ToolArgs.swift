// ToolArgs.swift — 工具入参的解析与必填校验（纯函数，无业务依赖）。
//
// 单独成文件是为了能被 AgentCheck 直接编译测试，且判定不内联回
// AgentCore 的循环里 —— 内联了就又不可测了（见 AGENTS.md 不变量 28）。
//
// ⚠️ 不要往这里加 AppModel / EngineCLI / SwiftUI 依赖，那会让它没法单独编译。

import Foundation

enum ToolArgs {
    /// 一次工具调用的入参解析结果。
    enum Decoded {
        /// 合法 JSON 对象
        case object([String: Any])
        /// **不是**合法 JSON 对象 —— 与「合法的空对象 {}」是两件事
        case malformed(String)
    }

    /// 解析模型给的 `argumentsJSON`。
    ///
    /// ⚠️ 缺陷 NC31：原来在 AgentCore 里写成
    /// `(try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]`
    /// —— **畸形 JSON 被静默吞成「没有参数」**。
    /// 而对 `run_shallow_update` / `run_deep_update` 这类工具，
    /// 「没有 name」在客户端会变成**空位置参数** `["update", "", …]`，
    /// 引擎又把空位置参数等同于「不传项目名」= **整个项目群**。
    /// 实测（/tmp 沙箱，两个已注册项目）：
    ///   `deepgit update "" --json --quiet` → repoA、repoB 的 README 都被改写，exit 0。
    /// 于是一次畸形的模型响应 = **静默改写所有项目**，界面上还显示「✓ 执行成功」。
    ///
    /// 读侧同样扩大作用域：`journal ""` 返回所有项目的日志，
    /// `context ""` 静默退化成整个项目群的上下文（都不报错）。
    static func decode(_ raw: String) -> Decoded {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空串不是「合法的空对象」：它意味着模型根本没给出参数结构，
        // 而空对象 `{}` 至少是模型明确表示「没有额外参数」。两者不能混。
        guard !trimmed.isEmpty else { return .malformed("（空串）") }
        guard let data = trimmed.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) else {
            return .malformed(String(trimmed.prefix(200)))
        }
        guard let dict = any as? [String: Any] else {
            return .malformed("顶层不是 JSON 对象：\(String(trimmed.prefix(200)))")
        }
        return .object(dict)
    }

    /// 必填参数里缺了哪些。**空白等同于缺**（`{"name": "  "}` 与没给一样危险）。
    static func missing(params: [String: Any], required: [String]) -> [String] {
        var out: [String] = []
        for key in required {
            guard let value = params[key], !(value is NSNull) else {
                out.append(key)
                continue
            }
            if let s = value as? String,
               s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(key)
            }
        }
        return out
    }

    /// 回报给模型的文案：说清缺什么、**以及为什么不能自己猜**。
    ///
    /// 「为什么」这一句是刻意的：模型看到「缺少 name」很可能顺手编一个项目名，
    /// 那比报错更糟 —— 它会写进一个根本不存在的项目。
    static func missingMessage(tool: String, missing: [String]) -> String {
        let list = missing.joined(separator: "、")
        return "工具「\(tool)」缺少必填参数：\(list)。"
            + "这些参数没有安全的默认值：引擎把空项目名理解成「整个项目群」，"
            + "所以这里宁可报错也不猜。请带上这些参数重新调用，"
            + "不要自己编造项目名。"
    }

    /// 解析畸形入参时的文案（回报给模型，让它能重试而不是放弃）。
    static func malformedMessage(tool: String, raw: String) -> String {
        return "工具「\(tool)」的参数不是合法的 JSON 对象，已拒绝执行：\(raw)。"
            + "请重新调用并给出形如 {\"key\": \"value\"} 的参数对象。"
    }

    /// 从「已经发给模型的那份工具定义」里取必填参数。
    ///
    /// 只有一个来源：执行端照**模型看到过的**那份契约执行，不另抄一份 ——
    /// 抄两份必然漂移（这正是工具清单两条副本的老毛病）。
    /// - Parameters:
    ///   - parametersJSONByName: 工具名 → 该工具的 parametersJSON
    ///   - tool: 本次调用的工具名
    static func required(parametersJSONByName: [String: String], tool: String) -> [String] {
        guard let raw = parametersJSONByName[tool],
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let req = obj["required"] as? [String] else { return [] }
        return req
    }
}
