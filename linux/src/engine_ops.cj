// deepDolphin Linux 客户端 —— 引擎操作层。
//
// 与 macOS 端 `AIClient.swift` 一一对应：那边每个 `func xxx() async` 扩展
// 在这边有一个同名同步函数。**能力对齐靠的是这一层，界面自由。**
//
// 全部走 CLI 子进程，不走网络；本端不落任何业务数据（C11）。
package deepdolphin_linux

import std.collection.*

/// 读类操作：失败时**仍然返回载荷**。
///
/// 理由与 macOS 端一致：引擎的退出码表达的是「整体可用性」，
/// 不是每个操作成功与否。全部项目采集失败时它照样打印完整 JSON 再 exit 1，
/// stderr 是空的。丢掉载荷就只剩一句无信息量的「引擎退出码 1」。
public class Payload {
    /// 解析好的 JSON；解析失败时是 None。
    public let json: Option<JsonValue>
    /// 给人看的失败原因；成功时为空串。
    public let problem: String
    /// 引擎以非 0 退出但给出了载荷 —— 界面必须照常渲染并披露。
    public let partial: Bool
    public let exitCode: Int64
    /// 引擎的原始 stdout。文档内容这类「不是 JSON 的正文」要用。
    public let raw: String
    /// 载荷来自契约过旧的引擎（见 engine.cj 的 checkContract）。
    /// 读侧要据此降级显示；写侧压根不发这种形状的载荷。
    public let staleContract: Bool

    public init(
        json: Option<JsonValue>,
        problem: String,
        partial: Bool,
        exitCode: Int64,
        raw: String,
        staleContract!: Bool = false
    ) {
        this.json = json
        this.problem = problem
        this.partial = partial
        this.exitCode = exitCode
        this.raw = raw
        this.staleContract = staleContract
    }

    public func ok(): Bool {
        return this.problem.isEmpty()
    }

    public func value(): JsonValue {
        return this.json.getOrDefault({=> JNull})
    }
}

/// 执行一次引擎调用并把 stdout 解析成载荷。
///
/// 写操作与读操作的差别只有一个：**写操作即使解析不出 JSON 也要报失败**。
/// 读操作解析不出来多半是契约变了，值得照样显示；写操作解析不出来
/// 说明这次动作的结果不明，**绝不能当成成功** —— 用户会以为文件已更新。
/// 超时**按操作定值**，不用一个全局常量。
///
/// 理由：`status` 在 6 个项目上跑只要几秒，而 `dashboard` 要遍历全部
/// 提交与语言。共用一个值必然要么砍掉长操作、要么让短操作卡住。
/// 下面的分档就是这条政策：
///   读快（status/docs/milestone）  30–60 秒
///   读慢（dashboard / journal）    180 秒
///   写（update/git/milestone 写）  600 秒 —— 深更新 5 分钟起步
public func callRaw(
    bin: String,
    args: Array<String>,
    timeoutMs: Int64,
    writeOp: Bool,
    shape!: PayloadShape = PayloadShape.Free
): Payload {
    let res = execCapture(bin, args, timeoutMs)
    if (res.timedOut) {
        return Payload(None, res.stderr, false, -1, res.stdout, staleContract: false)
    }
    match (Json.parse(res.stdout)) {
        case Some(v) =>
            // 契约闸门只对 status/dashboard/milestone 这类**读**载荷有意义：
            // 写操作的载荷形状随命令而变，用一套键去卡它会误报。
            let stale = (!writeOp) && (!checkContractOf(v, shape))
            if (stale) {
                return Payload(Some(v), staleContractMessage(""), true, res.exitCode, res.stdout, staleContract: true)
            }
            if (res.exitCode == 0) {
                return Payload(Some(v), "", false, 0, res.stdout, staleContract: false)
            }
            return Payload(Some(v), describeEngineFailure(res), true, res.exitCode, res.stdout, staleContract: stale)
        case None =>
            // 写操作走到这里：动作结果不明。
            if (writeOp) {
                return Payload(
                    None,
                    "引擎退出码 ${res.exitCode}，且没有输出可解析的 JSON —— 这次动作的结果不明，请到项目里确认后再重试。",
                    false,
                    res.exitCode,
                    res.stdout,
                    staleContract: false
                )
            }
            let why = if (!res.stderr.isEmpty()) { res.stderr.trimAscii() } else {
                "引擎没有输出可解析的 JSON（退出码 ${res.exitCode}）"
            }
            return Payload(None, why, false, res.exitCode, res.stdout, staleContract: false)
    }
}

/// 只读调用的便捷入口。
private func readOp(
    bin: String,
    args: Array<String>,
    timeoutMs: Int64,
    shape!: PayloadShape = PayloadShape.Free
): Payload {
    return callRaw(bin, args, timeoutMs, false, shape: shape)
}

/// 写调用的便捷入口。
private func writeOp(bin: String, args: Array<String>, timeoutMs: Int64): Payload {
    return callRaw(bin, args, timeoutMs, true)
}

// ---------------------------------------------------------------------------
// C2 读：状态 / 仪表盘
// ---------------------------------------------------------------------------

/// 全项目状态。
public func opStatus(bin: String): Payload {
    return readOp(bin, ["status", "--json", "--quiet"], 30000, shape: PayloadShape.Status)
}

/// 单项目状态。
public func opProjectStatus(bin: String, project: String): Payload {
    return readOp(bin, ["status", project, "--json", "--quiet"], 60000, shape: PayloadShape.Status)
}

public func opDashboard(bin: String): Payload {
    return readOp(bin, ["dashboard", "--json"], 180000, shape: PayloadShape.Dashboard)
}

// ---------------------------------------------------------------------------
// C3 读：文档 / 日志 / 里程碑
// ---------------------------------------------------------------------------

/// 文档正文（README / AGENTS / CLAUDE）。
public func opDocs(bin: String, project: String): Payload {
    return readOp(bin, ["docs", project, "--json"], 60000, shape: PayloadShape.Docs)
}

public func opJournal(bin: String, project: String): Payload {
    return readOp(bin, ["journal", project, "--json"], 30000, shape: PayloadShape.Journal)
}

public func opMilestoneList(bin: String): Payload {
    return readOp(bin, ["milestone", "list", "--json"], 60000, shape: PayloadShape.Milestones)
}

// ---------------------------------------------------------------------------
// C4 写：更新
// ---------------------------------------------------------------------------

/// 单项目更新。`deep` 为真走深更新。
///
/// 超时给得比读类大一个量级：深更新要重写文档章节 + 调 AI，
/// 浅更新也要扫全量历史。macOS 端是 300s / 600s，这里同量级。
public func opUpdate(bin: String, project: String, deep: Bool): Payload {
    let cmd = if (deep) { "deep" } else { "update" }
    return writeOp(bin, [cmd, project, "--json", "--quiet"], if (deep) { 600000 } else { 300000 })
}

/// 全部项目更新。
public func opUpdateAll(bin: String, deep: Bool): Payload {
    let cmd = if (deep) { "deep" } else { "update" }
    return writeOp(bin, [cmd, "--json", "--quiet"], if (deep) { 1800000 } else { 900000 })
}

// ---------------------------------------------------------------------------
// C8 写：git 操作
// ---------------------------------------------------------------------------

/// 白名单 git 操作。**这里不校验白名单** —— 引擎侧有白名单，
/// 客户端再抄一份只会带来「两边不一致」的风险；
/// 但界面只暴露白名单里的按钮，所以实际能被点到的是白名单。
public func opGit(bin: String, project: String, op: String, message: String): Payload {
    var args = ArrayList<String>()
    args.add("git")
    args.add(op)
    args.add(project)
    if (!message.isEmpty()) {
        args.add("--message")
        args.add(message)
    }
    args.add("--json")
    return writeOp(bin, args.toArray(), 120000)
}

/// 引擎认可的 git 操作白名单。界面只给这些按钮。
public func gitWhitelist(): Array<String> {
    return ["pull", "push", "commit", "stash", "unstash", "fetch"]
}

/// 白名单的中文标签。
public func gitOpLabel(op: String): String {
    match (op) {
        case "pull" => return "拉取"
        case "push" => return "推送"
        case "commit" => return "提交"
        case "stash" => return "暂存"
        case "unstash" => return "取出暂存"
        case "fetch" => return "抓取"
        case _ => return op
    }
}

// ---------------------------------------------------------------------------
// C9 写：里程碑
// ---------------------------------------------------------------------------

/// 里程碑动作：done / reopen / drop / remove。
///
/// UI 词汇 `open` → 引擎词汇 `reopen`。这层翻译放在这里，
/// 界面就只管说人话，不会把引擎的命令词漏到界面上。
public func opMilestoneAction(bin: String, project: String, name: String, action: String): Payload {
    let cmd = if (action == "open") { "reopen" } else { action }
    return writeOp(bin, ["milestone", cmd, project, name, "--json"], 30000)
}

/// 新建里程碑。空字段直接省略，不给引擎传空串 ——
/// `--tag ""` 与不传 `--tag` 在引擎侧不是一回事。
public func opMilestoneAdd(
    bin: String,
    project: String,
    name: String,
    tag: String,
    targetDate: String,
    description: String
): Payload {
    var args = ArrayList<String>()
    args.add("milestone")
    args.add("add")
    args.add(project)
    args.add(name)
    if (!tag.isEmpty()) {
        args.add("--tag")
        args.add(tag)
    }
    if (!targetDate.isEmpty()) {
        args.add("--date")
        args.add(targetDate)
    }
    if (!description.isEmpty()) {
        args.add("--desc")
        args.add(description)
    }
    args.add("--json")
    return writeOp(bin, args.toArray(), 30000)
}

// ---------------------------------------------------------------------------
// 项目注册
// ---------------------------------------------------------------------------

public func opScan(bin: String, root: String, depth: Int64): Payload {
    return writeOp(bin, ["scan", root, "--depth", "${depth}", "--json"], 300000)
}

public func opAddProject(bin: String, path: String, name: String): Payload {
    var args = ArrayList<String>()
    args.add("add")
    args.add(path)
    if (!name.isEmpty()) {
        args.add("--name")
        args.add(name)
    }
    args.add("--json")
    return writeOp(bin, args.toArray(), 30000)
}

// ---------------------------------------------------------------------------
// C6 读：agent 上下文与工具清单
// ---------------------------------------------------------------------------

public func opContext(bin: String, project: String, budget: Int64): Payload {
    var args = ArrayList<String>()
    args.add("context")
    if (!project.isEmpty()) {
        args.add(project)
    }
    args.add("--budget")
    args.add("${budget}")
    args.add("--json")
    return readOp(bin, args.toArray(), 60000)
}

public func opTools(bin: String): Payload {
    return readOp(bin, ["tools", "--json"], 30000)
}
