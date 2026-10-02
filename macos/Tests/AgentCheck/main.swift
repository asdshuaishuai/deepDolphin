// AgentCheck — agent 判定层的检查。
//
// 编译的是 Sources/deepDolphin/*.swift 本体（不是副本）：
// 副本会与源文件漂移，测了等于没测。
//
// 覆盖两个缺陷：
//   P0-4 轮次上限时 `throw`，把本轮模型**已经写出来的** `result.text` 一起丢掉
//   P0-5 agent 每次从零起步（`var convo = [ChatMessage.user(question)]`），
//         所谓"对话"其实是一串互不相干的一次性提问
//
// 【跑法】scripts/agent-check.sh

import Foundation

var failures: [String] = []
var checks = 0

func check(_ label: String, _ body: () throws -> String) {
    checks += 1
    do {
        let detail = try body()
        print("  ✓ \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    } catch {
        print("  ✗ \(label)\n      \(error)")
        failures.append("\(label): \(error)")
    }
}

func fail(_ msg: String) -> NSError {
    NSError(domain: "agent", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
}

/// 剥掉 Swift 注释（`//` 与 `/* */`），保留字符串字面量内容。
///
/// ⚠️ 这不是洁癖，是被 lint 自己抓出来的：修 NC31 时我在 AgentCore 的注释里
/// 引用了旧的 `as? [String: Any] ?? [:]`（AgentCore.swift:211），
/// 结果「不得再用 `?? [:]`」那条 lint 报「还在用」——
/// 它匹配到的是我自己写的说明文字，而那行代码早改掉了。
/// 负控 NC31-b 验证过：把 code() 退化成恒等函数，那条 lint 立刻假红。
///
/// ⚠️ 但**别夸大**。同类的「1b lint 会被注释骗绿」我一度也写在这里，
/// 实测（负控 NC31-c）不成立：AgentCore 的注释写的是「判定在 AgentOutcome」，
/// 并没有 `AgentOutcome.finish` 这个字面量，所以那条 lint 没被注释骗过。
/// 剥注释的价值在于**挡住真的会被骗的那些**，
/// 而不是给每条 lint 都套一层保险 —— 套错了会让人以为这里有第二个缺陷。
///
/// 状态机而不是正则：源码里有 `"https://…"` 这类字面量，
/// 正则分不清 `//` 是注释还是 URL 的一部分。
func code(_ src: String) -> String {
    var out = ""
    var inLine = false
    var inBlock = false
    var inStr = false
    var escaped = false
    var i = src.startIndex
    let end = src.endIndex
    while i < end {
        let c = src[i]
        let n = src.index(after: i)
        let cn: Character? = n < end ? src[n] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", cn == "/" { inBlock = false; i = src.index(after: n); continue }
        } else if inStr {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inStr = false }
        } else {
            if c == "/", cn == "/" { inLine = true; i = src.index(after: n); continue }
            if c == "/", cn == "*" { inBlock = true; i = src.index(after: n); continue }
            if c == "\"" { inStr = true }
            out.append(c)
        }
        i = n
    }
    return out
}

/// 读 Sources/deepGit 下的源文件。
///
/// 五个检查程序各自单独编译，没有共享模块，所以这份助手只能各存一份。
/// 别为了"去重"去建一个共享 target —— 那会让 5 套检查里任何一套
/// 编译失败时都看不到其他套的诊断，而改键名时最需要一次看到全部。
func sourceText(_ name: String) throws -> String {
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // AgentCheck
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <pkg>
    return try String(contentsOf: dir.appendingPathComponent("Sources/deepDolphin/\(name)"),
                      encoding: .utf8)
}

print("【1】轮次上限时不得丢掉已生成的答案（P0-4）")

check("有内容 ⇒ 交出内容，而不是抛错") {
    let answer = "deepGit 的 dashboard 里程碑有三个出口，形状必须一致。"
    guard let out = AgentOutcome.atRoundLimit(text: answer, maxRounds: 8) else {
        throw fail("返回了 nil ⇒ 调用方会抛错，答案被丢掉（这就是 P0-4 本身）")
    }
    guard out.contains(answer) else {
        throw fail("返回值里没有原答案，答案仍被丢弃")
    }
    return "原答案完整保留在返回值里"
}

check("返回值必须**自报**这是上限时的内容（不能让人误以为任务做完了）") {
    guard let out = AgentOutcome.atRoundLimit(text: "部分结论。", maxRounds: 8) else {
        throw fail("返回 nil")
    }
    // 少了这句，用户会把半截答案当成完整结论 —— 那是另一种谎报
    guard out.contains("已达工具调用轮次上限") else {
        throw fail("没有标注「已达上限」⇒ 半个答案会被当成完整答案")
    }
    guard out.contains("8") else {
        throw fail("没有回显轮次数，调用方无从判断被截断到什么程度")
    }
    return "标注了上限与轮次数"
}

check("空文本 ⇒ 返回 nil（此时抛错才是诚实说法）") {
    guard AgentOutcome.atRoundLimit(text: "", maxRounds: 8) == nil else {
        throw fail("空文本却返回了内容 ⇒ UI 会显示一个空白「答案」")
    }
    return "空串返回 nil"
}

check("只有空白字符 ⇒ 也算空（trim 之后再判）") {
    for ws in ["   ", "\n", "\n\n\n", " \t\n " ] {
        guard AgentOutcome.atRoundLimit(text: ws, maxRounds: 8) == nil else {
            throw fail("纯空白 \(ws.debugDescription) 被当成了有内容")
        }
    }
    return "4 种纯空白都判为空"
}

check("三态不重叠：有内容 / 纯空白 / 真空，各走各的分支") {
    // 「有内容」与「纯空白」的分界是 trim 之后是否为空。
    // 两边同时满足或同时不满足都说明判定写糊了。
    let withText = AgentOutcome.atRoundLimit(text: "答案", maxRounds: 4) != nil
    let withBlank = AgentOutcome.atRoundLimit(text: "  \n ", maxRounds: 4) != nil
    let withEmpty = AgentOutcome.atRoundLimit(text: "", maxRounds: 4) != nil
    guard withText && !withBlank && !withEmpty else {
        throw fail("三态判定不一致：有文本=\(withText) 纯空白=\(withBlank) 真空=\(withEmpty)")
    }
    return "有文本→有值 / 纯空白→无 / 真空→无"
}

check("轮次数原样回显，不被写死") {
    for n in [1, 3, 8, 20] {
        guard let out = AgentOutcome.atRoundLimit(text: "x", maxRounds: n),
              out.contains("\(n)") else {
            throw fail("maxRounds=\(n) 没有正确回显")
        }
    }
    return "1/3/8/20 都正确回显"
}

check("判定是纯函数（同输入同输出，不改入参）") {
    let input = "  结论  \n"
    let a = AgentOutcome.atRoundLimit(text: input, maxRounds: 5)
    let b = AgentOutcome.atRoundLimit(text: input, maxRounds: 5)
    guard a == b else { throw fail("两次调用结果不同") }
    guard input == "  结论  \n" else { throw fail("入参被改了") }
    return "稳定且无副作用"
}

// MARK: - 1b. NC30：撞上限时「工具已执行」绝不能被判成失败
//
// 复现（/tmp 下的复现程序，逐行照抄 AgentCore 循环的收尾控制流）：
//   引擎真执行 : ["get_project_status", …, "run_shallow_update"]
//   工具结果条数: 4 条
//   循环结果   : ❌ THROWN：已达工具调用轮次上限（4），且模型未产出任何文本
// 即：写盘的 run_shallow_update 改完了文档，界面却说「失败」，
// 工具输出、过程事件、整段历史一并丢掉 —— 用户重试就是重复执行一次。
//
// 这不是边角：模型只在返回 tool_calls 时 text 本来就是空的
// （OpenAI 兼容 content=null、Anthropic 无 text block），
// 所以「最后一轮仍在调工具」是正常路径。

print("【1a】code() 必须真的剥掉注释（否则所有 lint 一起空转）")
do {
    check("行注释被剥、块注释被剥、字符串里的 // 保留") {
        let src = """
        let a = 1  // 这行注释里写着 as? [String: Any] ?? [:]
        /* 块注释
           里面也有 AgentOutcome.finish */
        let url = "https://example.com/x"
        """
        let out = code(src)
        guard !out.contains("这行注释里写着") else { throw fail("行注释没剥掉") }
        guard !out.contains("块注释") else { throw fail("块注释没剥掉") }
        guard out.contains("https://example.com/x") else {
            throw fail("字符串字面量里的 // 被误当成注释起点 —— URL 会被截断")
        }
        return "注释已剥、URL 完好"
    }

    check("真实文件：注释里提到的符号不应出现在 code() 结果里") {
        let pkg = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = pkg.appendingPathComponent("Sources/deepDolphin/AgentCore.swift")
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard raw.contains("//") else { throw fail("读不到 AgentCore.swift") }
        // AgentCore 的注释里明确引用了旧的 `?? [:]`；剥完必须消失
        guard code(raw).count < raw.count else {
            throw fail("code() 一个字符都没删 —— 它在原地返回，lint 会匹配到注释")
        }
        return "code() 结果 \(code(raw).count) < 原文 \(raw.count)"
    }
}

print("【1b】撞轮次上限时，工具已执行 ≠ 失败（NC30）")
do {
    func finalText(_ f: AgentOutcome.AgentFinish) -> String? {
        if case .final(let s) = f { return s }
        return nil
    }

    check("工具已执行 + 文本空 → 必须交出内容，绝不能是「失败」") {
        let f = AgentOutcome.finish(
            text: "",
            executedTools: ["run_shallow_update", "git_commit"],
            maxRounds: 4
        )
        guard let out = finalText(f) else {
            throw fail("这一轮跑了 2 个工具却被判成 .failed —— "
                       + "副作用已经发生，抛错等于把生效的操作报成失败")
        }
        return "交出 \(out.count) 字收尾文案"
    }

    check("收尾文案必须点名工具、说清已生效、并劝阻重复执行") {
        let out = finalText(AgentOutcome.finish(
            text: "", executedTools: ["run_shallow_update"], maxRounds: 4
        )) ?? ""
        guard out.contains("run_shallow_update") else {
            throw fail("文案没有点名工具：\(out)")
        }
        guard out.contains("已经执行完") else {
            throw fail("文案没说清「已执行完」—— 用户会以为没跑过而重试：\(out)")
        }
        guard out.contains("不要重复执行") else {
            throw fail("文案没有劝阻重复执行：\(out)")
        }
        return "点名 + 已生效 + 劝重复，三点都在"
    }

    check("工具已执行 + 有文本 → 仍然保留模型原文（不得被工具摘要顶掉）") {
        let out = finalText(AgentOutcome.finish(
            text: "已经查完了。", executedTools: ["get_journal"], maxRounds: 4
        )) ?? ""
        guard out.contains("已经查完了。") else {
            throw fail("模型原文被丢了：\(out)")
        }
        return "原文 + 上限标注都在"
    }

    check("文本真空 **且** 没跑过工具 → 仍判 .failed（别把这条也一并放开）") {
        let f = AgentOutcome.finish(text: "  \n ", executedTools: [], maxRounds: 4)
        guard finalText(f) == nil else {
            throw fail("什么都没发生时却交出了内容 —— 那是在编造")
        }
        return "真空仍然抛错"
    }

    // ---- 源 lint：判定不许被内联回循环 --------------------------------------
    // 抽成纯函数只是第一步；AgentCore 若改回自己判，
    // 上面四条就变成在测一段没人调用的代码 —— 测了等于没测。
    // 同 client-check 里「UI 必须走 StopDecision」是同一个道理。
    check("AgentCore 的轮次上限收尾必须走 AgentOutcome.finish（lint）") {
        let pkg = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = pkg.appendingPathComponent("Sources/deepDolphin/AgentCore.swift")
        // code() 剥注释：AgentCore.swift:211 的注释里引用着旧的 `?? [:]`，
        // 不剥的话那条「不得再用」会假红。1b 这条实测没被注释骗到（NC31-c），
        // 但走同一条路径更省心，且不会因为将来注释写法一变就失效。
        let src = code((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        // 前提守卫：抓不到就是空转，必须先确认真的读到了这个文件
        guard src.contains("AgentCore") else {
            throw fail("读不到 AgentCore.swift（路径 \(url.path)）—— 本条会静默空转")
        }
        guard src.contains("AgentOutcome.finish") else {
            throw fail("AgentCore 没有调 AgentOutcome.finish —— "
                       + "轮次上限的收尾判定被内联回循环了，"
                       + "工具已执行时会退回「抛错报失败」的老路")
        }
        return "收尾判定来自 AgentOutcome，不是内联"
    }
}

// MARK: - 1c. NC31：畸形入参与缺必填，绝不能变成「换个作用域照样执行」
//
// 复现（/tmp 沙箱，两个已注册项目 repoA / repoB）：
//   AgentCore 原来 `(try? JSONSerialization.jsonObject(...)) as? [String: Any] ?? [:]`
//   → 模型吐一次畸形 JSON → params = [:] → name = ""
//   → 客户端拼出**空位置参数** ["update", "", "--json", "--quiet"]
//   → 引擎把空位置参数等同于「不传项目名」
//   → 实测 `deepgit update ""` 把 repoA、repoB 的 README **都改写了**，exit 0
// 界面上那次工具调用显示「✓ 执行成功」。
//
// 读侧同样扩大作用域：journal "" → 所有项目的日志；context "" → 整个项目群上下文。
//
// 根因是「解析失败」被当成了「参数为空」。这两件事必须分开。

print("【1c】工具入参：畸形/缺必填 ≠ 没有参数（NC31）")
do {
    func isMalformed(_ d: ToolArgs.Decoded) -> Bool {
        if case .malformed = d { return true }
        return false
    }
    func objectOf(_ d: ToolArgs.Decoded) -> [String: Any]? {
        if case .object(let o) = d { return o }
        return nil
    }

    check("前提：畸形串、空串、顶层非对象，都必须判为 malformed") {
        // 抓不到 = 集合为空 = 静默空转，所以先把三类畸形逐个点名。
        let broken = [
            "{\"name\": \"foo\"",       // 截断
            "not json at all",          // 根本不是 JSON
            "[1,2,3]",                  // 顶层是数组
            "\"just a string\"",        // 顶层是字符串
            "   ",                      // 纯空白
            "",                         // 空串
        ]
        var missed: [String] = []
        for raw in broken where !isMalformed(ToolArgs.decode(raw)) {
            missed.append(raw.isEmpty ? "<空串>" : raw)
        }
        guard missed.isEmpty else {
            throw fail("这些畸形输入被当成了合法参数：\(missed.joined(separator: " / "))")
        }
        return "\(broken.count) 类畸形全部拦住"
    }

    check("空串 ≠ 合法空对象（这两件事混起来就是本缺陷的根因）") {
        guard isMalformed(ToolArgs.decode("")) else {
            throw fail("空串被判成合法参数 —— 于是它会变成 [:] 继续往下走")
        }
        guard objectOf(ToolArgs.decode("{}")) != nil else {
            throw fail("`{}` 必须判为合法空对象：模型明确表示「没有额外参数」是合法的")
        }
        return "空串拦下、{} 放行"
    }

    check("畸形入参的回报文案要让模型能重试（说清是参数问题、给出正确形状）") {
        let m = ToolArgs.malformedMessage(tool: "run_shallow_update", raw: "{\"name\":")
        guard m.contains("run_shallow_update") else { throw fail("文案没点名工具：\(m)") }
        guard m.contains("JSON") else { throw fail("文案没说清是 JSON 问题：\(m)") }
        guard m.contains("重新调用") else { throw fail("文案没让模型重试：\(m)") }
        return "点名 + 说清格式 + 促重试"
    }

    check("空白值等同于缺（`{\"name\":\"  \"}` 与没给一样危险）") {
        let p: [String: Any] = ["name": "  \n "]
        guard ToolArgs.missing(params: p, required: ["name"]) == ["name"] else {
            throw fail("纯空白没有被算作缺 —— 引擎会拿它当空位置参数")
        }
        guard ToolArgs.missing(params: ["name": "foo"], required: ["name"]).isEmpty else {
            throw fail("有值却被算作缺")
        }
        return "空白=缺、有值=不缺"
    }

    check("缺必填的文案必须说清「引擎把空项目名理解成整个项目群」") {
        let m = ToolArgs.missingMessage(tool: "run_deep_update", missing: ["name"])
        guard m.contains("run_deep_update") else { throw fail("没点名工具：\(m)") }
        guard m.contains("name") else { throw fail("没点名缺的参数：\(m)") }
        guard m.contains("整个项目群") else {
            throw fail("没说清空项目名的后果 —— 模型会以为随便填一个就行：\(m)")
        }
        return "点名 + 点参 + 说后果"
    }

    check("必填参数只有一个来源：已发给模型的那份 required") {
        // 这份 parametersJSON 与 AgentCore 发给模型的是同一份形状
        let byName: [String: String] = [
            "run_shallow_update": #"{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}"#,
            "get_group_context": #"{"type":"object","properties":{},"required":[]}"#,
        ]
        guard ToolArgs.required(parametersJSONByName: byName, tool: "run_shallow_update") == ["name"] else {
            throw fail("没取到 run_shallow_update 的必填参数")
        }
        guard ToolArgs.required(parametersJSONByName: byName, tool: "get_group_context").isEmpty else {
            throw fail("群级工具被凭空要求了参数")
        }
        guard ToolArgs.required(parametersJSONByName: byName, tool: "查无此工具").isEmpty else {
            throw fail("未知工具不该有必填参数")
        }
        return "required 取自同一份契约"
    }

    // ---- 源 lint：拦审定在执行之前，且不许退回 `?? [:]` --------------------
    check("AgentCore 必须在执行前拦下畸形入参，且不得再用 `?? [:]`（lint）") {
        let pkg = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = pkg.appendingPathComponent("Sources/deepDolphin/AgentCore.swift")
        let src = code((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        guard src.contains("AgentCore") else {
            throw fail("读不到 AgentCore.swift（\(url.path)）—— 本条会静默空转")
        }
        guard !src.contains("as? [String: Any] ?? [:]") else {
            throw fail("AgentCore 还在用 `as? [String: Any] ?? [:]` —— "
                       + "畸形参数又被吞成「没有参数」，空项目名会变成整个项目群")
        }
        guard src.contains("ToolArgs.decode") else {
            throw fail("AgentCore 没走 ToolArgs.decode —— 解析判定被内联回去了")
        }
        guard src.contains("ToolArgs.missing") else {
            throw fail("AgentCore 没走 ToolArgs.missing —— 缺必填参数没人拦")
        }
        // 更要紧的一条：校验必须落在**执行点内部**。
        // 放调用方的话，今天只有一个调用点所以看不出问题，
        // 将来多一个调用点就绕过去了 —— 而绕过去的后果是批量写操作。
        guard src.contains("parametersJSONByName: [String: String]") else {
            throw fail("executeTool 没有接 parametersJSONByName —— "
                       + "必填校验可能被放回调用方，新增调用点就会绕过它")
        }
        return "解析在循环前拦、必填在执行点拦"
    }
}

// MARK: - 1d. NC32：工具「没跑成」这件事，界面必须看得见
//
// 这是修 NC31 时自己踩的坑：原来 `transcript` 靠
// `m.text.contains("执行失败")` 决定要不要显示 tool 消息。
// 新加的「拒绝畸形参数」路径写的是「已拒绝执行」—— 四个字对不上，
// 于是**工具根本没执行、界面上一个字都没有**。
// 用户看到的是：模型说了句不痛不痒的话，那次工具调用像没发生过。
//
// 根因是拿**文案字面量**当状态标记。状态该由发起方打，界面只读标记。

print("【1d】工具失败/被拒必须在 transcript 里留痕（NC32）")
do {
    check("isError 的 tool 消息必须显示，**哪怕文案里没有「执行失败」**") {
        // 这句文案来自 ToolArgs.malformedMessage，真机上就是这么写的
        let rejected = ToolArgs.malformedMessage(tool: "run_shallow_update", raw: "{\"name\":")
        guard !rejected.contains("执行失败") else {
            throw fail("前提不成立：这段文案里居然含「执行失败」—— 那测的就不是字面量不匹配这个缺陷了")
        }
        let out = Conversation.transcript(from: [ChatMessage.tool(rejected, callID: "c1", isError: true)])
        guard out.count == 1 else {
            throw fail("被拒绝的工具调用在界面上不留痕（条目数 \(out.count)）—— 工具没跑，用户却不知道")
        }
        guard out[0].kind == .note else { throw fail("被拒绝的工具调用没渲染成警示条目") }
        guard out[0].text.contains("run_shallow_update") else {
            throw fail("警示条目里没有工具名：\(out[0].text)")
        }
        return "无「执行失败」字样也照样显示"
    }

    check("成功的 tool 消息仍然不显示（过程不是对话内容）") {
        let okMsg = ChatMessage.tool("工具 get_journal 执行成功：\n# 日志", callID: "c2", isError: false)
        let out = Conversation.transcript(from: [okMsg])
        guard out.isEmpty else {
            throw fail("成功的工具往返被塞进了 transcript：\(out.map(\.text))")
        }
        return "成功的不显示、失败的显示"
    }

    check("失败标记与文案解耦：换措辞也不会漏显示") {
        // 模拟「以后有人把文案改成别的说法」：标记还在，显示就必须还在
        for wording in ["执行失败", "已拒绝执行", "没跑成", "skipped", "boom"] {
            let out = Conversation.transcript(
                from: [ChatMessage.tool("工具 x " + wording, callID: "c", isError: true)])
            guard out.count == 1 else {
                throw fail("文案改成「\(wording)」后界面就不显示了 —— 说明还在靠字面量")
            }
        }
        return "5 种措辞全部照样显示"
    }

    check("user / assistant 的既有规则不得被这次改动带坏") {
        let history: [ChatMessage] = [
            ChatMessage.system("系统提示"),
            ChatMessage.user("  "),                              // 空 user 不显示
            ChatMessage.user("问题"),
            ChatMessage(role: "assistant", text: "", toolCalls: [
                ToolCallRequest(id: "t1", name: "get_journal", argumentsJSON: "{}")
            ], toolCallID: nil),                                // 只调工具无文本 → 显示调用了什么
            ChatMessage.tool("工具 get_journal 执行成功", callID: "t1"),  // 成功不显示
        ]
        let out = Conversation.transcript(from: history)
        guard out.count == 2 else {
            throw fail("期望 2 条（问题 + 调用了什么），实际 \(out.count)：\(out.map(\.text))")
        }
        guard out[1].text.contains("get_journal") else {
            throw fail("第二条没显示工具名：\(out[1].text)")
        }
        return "空 user 隐藏、无文本 assistant 显示调用、成功工具隐藏"
    }

    // ---- 源 lint：判定不许退回字面量匹配 -----------------------------------
    check("transcript 不得退回「文案里有没有某四个字」（lint）") {
        let pkg = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = pkg.appendingPathComponent("Sources/deepDolphin/AgentConversation.swift")
        let src = code((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        guard src.contains("enum Conversation") else {
            throw fail("读不到 AgentConversation.swift（\(url.path)）—— 本条会静默空转")
        }
        guard !src.contains("contains(\"执行失败\")") else {
            throw fail("transcript 又在拿文案字面量判断失败了 —— "
                       + "换个措辞的工具拒绝就会在界面上静默消失")
        }
        guard src.contains("m.isError") else {
            throw fail("transcript 没读 isError 标记 —— 失败状态得由发起方打")
        }
        return "靠 isError 标记，不靠文案"
    }
}

// MARK: - 2. P0-3：AIResultSheet 的「重试」必须有实现
//
// 这条**不是**运行时测试，是源码级守卫 —— 先说清楚，免得被误读成更强的保证：
// `onRegenerate` 是视图构造期传入的闭包，「传没传」在运行期观察不到
// （按钮点了没反应是 UI 行为，自动化不了）。
// 但它可以被静态钉住：只要有任一调用点写 `onRegenerate: nil`，
// 那个「重试」按钮就必然是死的。原实现正是如此
// （四个调用点里三个传了真闭包，只有更新菜单那个传了 nil）。
//
// 读法要说清楚：这是 lint，不是行为测试。它挡的是「再写一个 nil 进去」。

print("【2】AIResultSheet 的「重试」按钮不得是死的（P0-3）")
do {
    let src = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // AgentCheck
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <pkg>
        .appendingPathComponent("Sources/deepDolphin/AIIntegration.swift")
    let board = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/deepDolphin/BoardView.swift")
    let files = [src, board]

    check("所有 AIResultSheet 调用点都传了实现（没有 onRegenerate: nil）") {
        var total = 0
        var offenders: [String] = []
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            // 逐个调用点切片：以 `AIResultSheet(` 起，到下一个 `)` 收尾
            var idx = text.startIndex
            while let r = text.range(of: "AIResultSheet(", range: idx..<text.endIndex) {
                total += 1
                let rest = text[r.upperBound...]
                let end = rest.range(of: "\n            )")?.lowerBound ?? rest.endIndex
                let call = String(text[r.upperBound..<end])
                if call.contains("onRegenerate: nil") {
                    let line = text[..<r.lowerBound].filter { $0 == "\n" }.count + 1
                    offenders.append("\(f.lastPathComponent):\(line)")
                }
                idx = r.upperBound
            }
        }
        guard total > 0 else { throw fail("一个 AIResultSheet 调用点都没扫到，检查本身失效") }
        guard offenders.isEmpty else {
            throw fail("这些调用点传了 nil ⇒ 「重试」按钮点了没反应：\(offenders)")
        }
        return "\(total) 个调用点全部传了实现"
    }

    check("「重试」按钮没有再用 ? 静默吞掉（nil 时不该静默无反应）") {
        let text = try String(contentsOf: src, encoding: .utf8)
        guard text.contains("Button(\"重试\")") else {
            throw fail("找不到「重试」按钮，检查前提不成立")
        }
        // 按钮体必须真的调用闭包，而不是 optional-chaining 掉空
        if text.contains("Button(\"重试\") { onRegenerate?() }") {
            // 这是可接受的写法：前提是所有调用点都传了实现（上一条已钉）。
            // 之所以不在这里判死，是因为「nil 时静默」只在有 nil 调用点时才有害。
            return "按钮体是 onRegenerate?()，由上一条「无 nil 调用点」保证它一定非空"
        }
        return "按钮体已不是静默 optional-chaining"
    }
}

// MARK: - 2. P0-5：多轮对话的判定

print("")

print("【2】多轮对话判定（P0-5：原来每轮都从零起步）")

func userMsg(_ t: String) -> ChatMessage { ChatMessage.user(t) }
func asstMsg(_ t: String) -> ChatMessage { ChatMessage.assistant(t) }

do {
    // MARK: 历史不能被清零

    check("历史必须原样接在问题前面（原来每轮从零起步，追问必然落空）") {
        let history = [userMsg("a"), asstMsg("b"), userMsg("c"), asstMsg("d")]
        // Conversation.seed 就是原来那行 `[ChatMessage.user(question)]` 的替代品。
        // 查**行为**而不是查拼法：内联版只要换个写法，lint 就抓不到了。
        let convo = Conversation.seed(history: history, question: "新问题")
        guard convo.count == history.count + 1 else {
            throw fail("历史被吃掉了：\(history.count) 条进去，\(convo.count) 条出来")
        }
        guard convo.dropLast().map(\.text) == history.map(\.text) else {
            throw fail("历史内容被改动了")
        }
        guard convo.last?.text == "新问题" else {
            throw fail("新问题没接在最后：\(convo.last?.text ?? "nil")")
        }
        return "\(history.count) 条历史 + 1 条新问题 = \(convo.count) 条"
    }

    check("seed 必须在**任何**裁剪之前保住历史（顺序反了就等于丢上文）") {
        // 50 条历史、预算只够 10 条：无论怎么裁，最后一条 user 必须还在，
        // 而最老那几条可以走 —— 少了它们不影响"刚才说了什么"。
        var h: [ChatMessage] = []
        for i in 1...50 { h.append(userMsg("u\(i)")) }
        let convo = Conversation.seed(history: h, question: "现在呢？",
                                       maxApproxTokens: 4000)
        guard convo.count == 11 else {
            throw fail("应 10 条历史 + 1 条新问题，实际 \(convo.count) 条")
        }
        guard convo.last?.text == "现在呢？" else {
            throw fail("本轮提问不在最后：\(convo.last?.text ?? "nil")")
        }
        guard convo.contains(where: { $0.text == "u50" }) else {
            throw fail("上一轮的用户消息被裁掉了 —— 追问会答非所问")
        }
        return "50 条历史 → 留最近 10 条 + 本轮提问，上一条仍在"
    }

    check("裁剪保留**最近**的（丢掉最早那轮不影响「刚才说了什么」）") {
        var h: [ChatMessage] = []
        for i in 1...50 { h.append(userMsg("u\(i)")) }
        let t = Conversation.trimHistory(h, maxApproxTokens: 4000, approxTokensPerMessage: 400)
        guard t.count == 10 else { throw fail("应留 10 条，实际 \(t.count) 条") }
        guard t.first?.text == "u41" else {
            throw fail("留下的不是最近的，第一条是「\(t.first?.text ?? "nil")」")
        }
        guard t.last?.text == "u50" else {
            throw fail("最新的没保住，最后一条是「\(t.last?.text ?? "nil")」")
        }
        return "50 条裁到最近 10 条（u41…u50）"
    }

    check("没超预算时一条都不能丢（丢一条就是一次「它忘了我刚说的话」）") {
        let h = [userMsg("a"), asstMsg("b"), userMsg("c")]
        let t = Conversation.trimHistory(h, maxApproxTokens: 12_000, approxTokensPerMessage: 400)
        guard t == h else { throw fail("没超预算却裁了：\(t.count) vs \(h.count)") }
        return "3 条 < 预算 30 条，原样返回"
    }

    check("预算是 0 或负数时不能除出空数组（会让对话凭空清零）") {
        for budget in [0, -1] {
            let t = Conversation.trimHistory([userMsg("a"), asstMsg("b")],
                                            maxApproxTokens: budget)
            guard t.isEmpty else {
                throw fail("预算=\(budget) 却返回了 \(t.count) 条")
            }
        }
        return "两个非法预算都安全返回空（而不是崩或裁出垃圾）"
    }

    check("裁剪是纯函数（同输入同输出，不改原数组）") {
        let h = [userMsg("a"), asstMsg("b"), userMsg("c"), asstMsg("d")]
        let before = h
        _ = Conversation.trimHistory(h, maxApproxTokens: 400, approxTokensPerMessage: 400)
        guard h == before else { throw fail("入参被改了") }
        let a = Conversation.trimHistory(h, maxApproxTokens: 400, approxTokensPerMessage: 400)
        let b = Conversation.trimHistory(h, maxApproxTokens: 400, approxTokensPerMessage: 400)
        guard a == b else { throw fail("两次结果不同") }
        return "稳定且无副作用"
    }

    // MARK: transcript 投影

    check("工具往返不直接进 transcript（否则对话被一堵墙淹没）") {
        let h: [ChatMessage] = [
            userMsg("查一下"),
            ChatMessage(role: "assistant", text: "", toolCalls: [
                ToolCallRequest(id: "1", name: "get_project_status", argumentsJSON: "{}")
            ], toolCallID: nil),
            ChatMessage(role: "tool", text: "工具 get_project_status 执行成功：\n{...}", toolCalls: nil, toolCallID: "1"),
            asstMsg("项目有 3 个分支"),
        ]
        let t = Conversation.transcript(from: h)
        guard t.count == 3 else {
            throw fail("应投影出 3 条（user / 只调工具的 assistant / 最终回答），实际 \(t.count)：\(t.map(\.text))")
        }
        guard t[1].text.contains("get_project_status") else {
            throw fail("「只调工具不说话」那条没显示调用了什么：\(t[1].text)")
        }
        return "3 条：提问 / 调用了工具 / 回答"
    }

    check("工具**执行失败**必须显示（成功的不显示，失败的不能藏）") {
        // ⚠️ 这条原来是靠「文案里含『执行失败』四个字」判定的，
        // 也就是说**测试和实现耦合在同一个字面量上**：
        // 谁把措辞改一改，测试和功能会一起悄悄失效（缺陷 NC32）。
        // 现在失败状态由发起方用 isError 打，测试也只依赖这个标记。
        let ok = ChatMessage.tool("工具 x 执行成功：\n{}", callID: "1")
        let bad = ChatMessage.tool("工具 x 执行失败：\n路径不存在", callID: "1", isError: true)
        let t = Conversation.transcript(from: [ok])
        guard t.isEmpty else { throw fail("成功的工具消息不该显示：\(t)") }
        let t2 = Conversation.transcript(from: [bad])
        guard t2.count == 1 else { throw fail("失败的工具消息被藏了（用户会以为一切正常）") }
        guard t2[0].text.contains("失败") else { throw fail("失败提示没说失败：\(t2[0].text)") }
        return "成功隐藏 / 失败可见"
    }

    check("system 消息不进 transcript（用户不该看到塞给他的系统提示）") {
        let t = Conversation.transcript(from: [ChatMessage.system("你是助手…"), userMsg("hi")])
        guard t.count == 1, t[0].kind == .user else {
            throw fail("system 漏进 transcript 了：\(t.map(\.kind))")
        }
        return "只显示 1 条用户消息"
    }

    check("空文本不产生气泡（否则屏幕上出现一个空框）") {
        let t = Conversation.transcript(from: [userMsg("   "), asstMsg("\n\t"), userMsg("真问题")])
        guard t.count == 1, t[0].text == "真问题" else {
            throw fail("空消息没被滤掉：\(t.map(\.text))")
        }
        return "3 条里只留 1 条"
    }

    // MARK: 发送按钮判定

    check("发送按钮四个条件缺一不可（每个都对应一种「点了没反应」）") {
        guard !Conversation.canSend("", isBusy: false, isConfigured: true).isAllowed else {
            throw fail("空文本被放行了")
        }
        guard !Conversation.canSend("   \n", isBusy: false, isConfigured: true).isAllowed else {
            throw fail("纯空白被放行了")
        }
        guard !Conversation.canSend("hi", isBusy: true, isConfigured: true).isAllowed else {
            throw fail("忙的时候被放行了（两轮循环会抢同一个上下文）")
        }
        guard !Conversation.canSend("hi", isBusy: false, isConfigured: false).isAllowed else {
            throw fail("AI 没配置也被放行了（发出去必然失败）")
        }
        guard Conversation.canSend("hi", isBusy: false, isConfigured: true).isAllowed else {
            throw fail("正常情况被误禁用了")
        }
        return "4 个条件各自都能拦住"
    }

    check("禁用时必须说清是哪一条（灰着不给理由，用户只能猜）") {
        let cases: [(String, Bool, Bool, Conversation.SendBlock)] = [
            ("", false, true, .empty),
            ("hi", true, true, .busy),
            ("hi", false, false, .notConfigured),
        ]
        for (text, busy, cfg, want) in cases {
            let d = Conversation.canSend(text, isBusy: busy, isConfigured: cfg)
            guard case .blocked(let got) = d else {
                throw fail("「\(text)」本该被禁却放行了")
            }
            guard got == want else {
                throw fail("「\(text)」禁用原因是 \(got)，应为 \(want)")
            }
        }
        return "3 种禁用各有各的说法"
    }

    check("放行时携带的是整理过的文本（首尾空白不该发给模型）") {
        guard case .allowed(let t) = Conversation.canSend("  你好 \n", isBusy: false, isConfigured: true) else {
            throw fail("未放行")
        }
        guard t == "你好" else { throw fail("带空白发出去了：\(t.debugDescription)") }
        return "「  你好 \\n」→「你好」"
    }

    check("三种阻断原因必须互不相同（塌成 Bool 就分不出「去设置」和「等一下」）") {
        guard Conversation.SendBlock.empty != .busy else { throw fail("状态塌了") }
        guard Conversation.SendBlock.notConfigured != .busy else { throw fail("状态塌了") }
        // 「未配置」与「忙」必须可区分：前者要引导去设置，后者要等。
        let unconfigured = Conversation.canSend("hi", isBusy: false, isConfigured: false)
        let busy = Conversation.canSend("hi", isBusy: true, isConfigured: true)
        guard unconfigured != busy else { throw fail("两种情况被判成同一个") }
        return "3 种阻断原因互不相同"
    }

    // MARK: 停止

    check("停止只在「正在跑且没被停过」时可用（否则是死按钮或重复点击）") {
        guard Conversation.canStop(isBusy: true, isCancelled: false) else {
            throw fail("正在跑时不能停 —— 用户只能干等（单轮最长 600 秒）")
        }
        guard !Conversation.canStop(isBusy: false, isCancelled: false) else {
            throw fail("空闲时「停止」可用 —— 是个死按钮")
        }
        guard !Conversation.canStop(isBusy: true, isCancelled: true) else {
            throw fail("已停止后还能再点停止")
        }
        return "三种组合各自正确"
    }
}

// MARK: - 3. P0-5 的源码守卫

print("")
print("【3】多轮对话的源码守卫（lint，非行为测试）")

do {
    let core = try sourceText("AgentCore.swift")
    let view = try sourceText("AgentView.swift")
    let panel = try sourceText("PanelView.swift")

    check("AgentCore 必须提供带 history 的入口（多轮的前提）") {
        guard core.contains("history: [ChatMessage]") else {
            throw fail("AgentCore 没有接受历史的入口 —— 追问无法带上文")
        }
        // 这里只查**接线**：对话怎么拼由 Conversation.seed 负责，那边查行为。
        // 拼法本身不在这里断言 —— 换个写法就漏，那是 NC18 吃过的亏。
        guard core.contains("Conversation.seed(history: history, question: question)") else {
            throw fail("AgentCore 没有走 Conversation.seed —— 历史可能被就地丢弃")
        }
        return "带 history 的 run + 走 Conversation.seed"
    }

    check("AgentCore 必须返回完整历史（只回最后一句就等于没有对话）") {
        guard core.contains("-> [ChatMessage]") else {
            throw fail("多轮版本没有返回完整历史")
        }
        guard core.contains("convo.append(ChatMessage.assistant(") else {
            throw fail("没有把最终回答追加进历史 —— 下一轮模型看不到自己说过什么")
        }
        return "返回 [ChatMessage] 并追加 assistant"
    }

    check("AgentView 必须真的把历史传进去（只建不传 = 依然是单轮）") {
        guard view.contains("history: before") else {
            throw fail("AgentView 没把 history 传给 AgentCore.run")
        }
        guard view.contains("history = updated") else {
            throw fail("没把返回的历史存回会话")
        }
        return "传入 before、存回 updated"
    }

    check("失败时必须把已发出的提问留回去（否则用户白打一遍）") {
        guard view.contains("history = before + [ChatMessage.user(text)]") else {
            throw fail("失败后没有保留那条提问 —— 用户的问题凭空消失")
        }
        return "失败也保留原问题"
    }

    check("必须有停止入口（原最长一轮 600 秒，用户只能干等）") {
        guard view.contains("func stop()") else { throw fail("AgentChatModel 没有 stop()") }
        guard view.contains("work?.cancel()") else {
            throw fail("stop() 没有取消 Task —— 点了还在跑")
        }
        guard view.contains("onDisappear { chat.stop() }") else {
            throw fail("关窗不停 —— 后台 agent 会往一个不存在的界面写状态")
        }
        return "stop() + onDisappear 取消"
    }

    check("对话必须有入口（写了没人点得开，等于没做）") {
        guard panel.contains("AgentView(target:") else {
            throw fail("PanelView 里没有呈现 AgentView")
        }
        guard panel.contains("Label(\"AI 助手\"") else {
            throw fail("工具栏里没有「AI 助手」按钮")
        }
        return "工具栏按钮 + sheet 呈现"
    }

    check("对话范围必须跟随当前选中（静默拿项目群去答项目问题会答得很像回事）") {
        guard panel.contains("if case .project(let name) = model.selection") else {
            throw fail("对话范围没有跟随 model.selection")
        }
        return "选中项目→该项目，否则项目群"
    }

    check("视图不得绕过 Conversation 自己做判定") {
        // 判定一旦内联回视图里，就又变成"编译过、评审看不出、只在运行时发作"。
        guard view.contains("Conversation.canSend") else {
            throw fail("AgentView 没有用 Conversation.canSend —— 判定被内联了")
        }
        guard view.contains("Conversation.canStop") else {
            throw fail("AgentView 没有用 Conversation.canStop")
        }
        return "canSend / canStop 都走纯函数"
    }

    check("发送按钮禁用时必须给出原因") {
        guard view.contains("sendHelp") else {
            throw fail("没有禁用原因文案 —— 按钮灰着但用户不知道为什么")
        }
        return "有 sendHelp"
    }
}

// MARK: - 4. AI 错误文案：必须能指导下一步

print("")
print("【4】AI 错误文案（原来 URLError 裸传，中文界面里显示英文原文）")

do {
    check("连不上服务时必须说清是哪个地址 + 下一步怎么做") {
        let r = AIErrorMessage.describe(.cannotConnectToHost, host: "api.example.com:443")
        guard r.title.contains("api.example.com:443") else {
            throw fail("没说试的是哪个地址：\(r.title)")
        }
        guard r.hint.contains("baseURL") else {
            throw fail("没告诉用户该查什么：\(r.hint)")
        }
        return r.text
    }

    check("超时不得只说「超时」（用户不知道是该换模型还是该换网络）") {
        let r = AIErrorMessage.describe(.timedOut, host: nil)
        guard r.hint.contains("模型") || r.hint.contains("网络") else {
            throw fail("超时没有任何可执行建议：\(r.hint)")
        }
        return r.text
    }

    check("每种网络错误都必须带建议（只说「失败了」等于让用户猜）") {
        let codes: [URLError.Code] = [
            .cannotConnectToHost, .cannotFindHost, .timedOut,
            .notConnectedToInternet, .networkConnectionLost,
            .secureConnectionFailed, .serverCertificateUntrusted,
            .userAuthenticationRequired, .appTransportSecurityRequiresSecureConnection,
            .badURL, .cancelled, .dataNotAllowed,
        ]
        for c in codes {
            let r = AIErrorMessage.describe(c, host: "h")
            guard !r.title.isEmpty else { throw fail("\(c) 没有标题") }
            guard r.hint.count >= 6 else {
                throw fail("\(c) 的建议太短或为空：\(r.hint.debugDescription)")
            }
            guard r.text.contains("。") else {
                throw fail("\(c) 拼不出完整句子：\(r.text)")
            }
        }
        return "\(codes.count) 种错误码都带可执行建议"
    }

    check("证书类错误必须说清是证书问题（否则用户会去查 key）") {
        for c in [URLError.Code.serverCertificateUntrusted,
                  .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot] {
            let r = AIErrorMessage.describe(c, host: "h")
            guard r.title.contains("证书") else {
                throw fail("\(c) 没说证书：\(r.title)")
            }
        }
        return "3 种证书错误都点名"
    }

    check("错误里绝不能带出 API Key（它会进 UI、日志、通知中心）") {
        // 有些服务把 key 放在 URL 的 user 或 query 里。
        // 而这条文本会被写进错误横幅、日志与通知中心 —— 泄出去无法收回。
        let risky = [
            "https://sk-secret-123@api.example.com/v1",
            "https://api.example.com/v1?api_key=sk-secret-123",
            "https://user:sk-secret-123@api.example.com:8443/v1",
        ]
        for u in risky {
            let host = AIErrorMessage.hostOf(u) ?? ""
            guard !host.isEmpty else {
                throw fail("「\(u)」解析不出 host")
            }
            guard !host.contains("sk-secret-123") else {
                throw fail("host 里带出了 key：\(host)")
            }
        }
        // 解析不出来的地址宁可少说，也不能把原文打出去
        guard AIErrorMessage.hostOf("这不是一个 URL") == nil else {
            throw fail("解析失败时应当返回 nil 而不是回显原文")
        }
        guard AIErrorMessage.hostOf(nil) == nil, AIErrorMessage.hostOf("") == nil else {
            throw fail("空输入应返回 nil")
        }
        return "3 种含 key 的写法都只留 host:port"
    }

    check("通道错误要能被解包（外层的壳不该显示给用户）") {
        // AISDK.post 抛的是 AIChannelError；调用点拿 localizedDescription。
        // 如果 describe 不解包，用户会看到"AI 调用失败。…"套着一条已翻译的文本。
        let inner = NSError(domain: NSURLErrorDomain, code: URLError.cannotConnectToHost.rawValue)
        let wrapped = AIChannelError(underlying: inner, attemptedURL: "https://api.x.com/v1")
        let r = AIErrorMessage.describe(wrapped)
        guard r.title.contains("api.x.com") else {
            throw fail("解包后没拿到地址：\(r.title)")
        }
        guard !r.title.contains("AI 调用失败") else {
            throw fail("套了两层说明：\(r.title)")
        }
        // 而 localizedDescription 本身就是好文案 —— 六个调用点不用改就是这个原因
        let viaLocalized = wrapped.localizedDescription ?? ""
        guard viaLocalized.contains("baseURL") else {
            throw fail("localizedDescription 不是可执行文案：\(viaLocalized)")
        }
        return "解包正常，且 localizedDescription 直接可用"
    }

    // 源码守卫
    let sdk = try sourceText("AISDK.swift")

    check("AISDK.post 必须把网络错误包成 AIChannelError（裸传 = 英文原文）") {
        guard sdk.contains("AIChannelError(underlying:") else {
            throw fail("post() 没有包装错误 —— 六个调用点会继续显示 Cocoa 英文原文")
        }
        guard sdk.contains("attemptedURL: url.absoluteString") else {
            throw fail("包装时没带上试过的地址 —— 用户仍不知道是哪一处错了")
        }
        return "包装 + 带地址"
    }
}

print("")
if failures.isEmpty {
    print("✅ agent 检查通过：\(checks) 项")
    exit(0)
} else {
    print("❌ agent 检查失败：\(failures.count)/\(checks) 项")
    for f in failures { print("   · \(f)") }
    exit(1)
}
