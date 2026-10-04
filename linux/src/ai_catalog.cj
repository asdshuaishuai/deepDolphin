// deepDolphin Linux 客户端 —— models.dev 目录（C7 数据源）。
//
// 与 macOS 端 `ModelsDev.swift` + `ProviderPickerSlice.swift` 逐条对齐。
// **共用同一份快照**：`assets/models/models-dev.json`（仓库根公共资源，
// 与图标同一套「平台不许各存一份」纪律）。
//
// 【为什么目录与解析必须拆开】macOS 那边 `parse()` 曾经把
// 「加锁」和「解析」写在同一个函数里，而解析内部又去拿同一把锁 ——
// `NSLock` 不可重入，直接永久死锁。开发期 `swift run` 触发不到
// （bundle 里没资源，提前 return），**打包后 AI 永久不可用**。
// 本端没有锁（单线程 UI 线程解析），但同一个纪律照搬：
// `parseCatalog` 是**纯函数**，不碰任何全局状态。
package deepdolphin_linux

import std.fs.*
import std.env.*
import std.collection.*

// ---------------------------------------------------------------------------
// 数据
// ---------------------------------------------------------------------------

public class CatalogModel {
    public let id: String
    public let name: String
    /// 支不支持原生 tool_calls。**C6 的硬前提** —— 不支持就别进候选。
    public let toolCall: Bool
    public let reasoning: Bool
    /// 快照里是**扁平键**。见下面 `catalogModelOf` 的警告。
    public let contextTokens: Option<Int64>
    public let outputTokens: Option<Int64>
    public let costIn: Option<Float64>
    public let costOut: Option<Float64>

    public init(
        id: String,
        name: String,
        toolCall: Bool,
        reasoning: Bool,
        contextTokens: Option<Int64>,
        outputTokens: Option<Int64>,
        costIn: Option<Float64>,
        costOut: Option<Float64>
    ) {
        this.id = id
        this.name = name
        this.toolCall = toolCall
        this.reasoning = reasoning
        this.contextTokens = contextTokens
        this.outputTokens = outputTokens
        this.costIn = costIn
        this.costOut = costOut
    }
}

public class CatalogProvider {
    public let id: String
    public let name: String
    /// models.dev 声明的 API 端点。**实测很多家是 null**（openai、deepinfra 都是），
    /// 所以「null」是常态而不是异常 —— 那几家要用户手填 Base URL。
    public let api: String
    public let models: ArrayList<CatalogModel>

    public init(id: String, name: String, api: String, models: ArrayList<CatalogModel>) {
        this.id = id
        this.name = name
        this.api = api
        this.models = models
    }
}

// ---------------------------------------------------------------------------
// 解析（纯函数）
// ---------------------------------------------------------------------------

/// 解出目录。**纯函数：无全局状态、无锁、无 IO。**
///
/// 排序规则照抄 macOS 端：**有端点的在前，其余按模型数降序**。
/// 本端多了一个 macOS 没有的东西 —— **按 id 兜底**。
/// macOS 那边遍历的是 Swift `Dictionary`（无序）而排序又是非稳定的，
/// 模型数相同的几家次序随机；仓颉这边遍历的是保序的
/// `ArrayList<(String, JsonValue)>`，我明确加 id 兜底是为了让
/// 「第 40 家 / 第 41 家各有多少模型」这种断点判断在两平台上可复现。
public func parseCatalog(text: String): ArrayList<CatalogProvider> {
    let out = ArrayList<CatalogProvider>()
    match (Json.parse(text)) {
        case None => return out
        case Some(root) =>
            let entries = match (Json.asObj(root)) {
                case Some(m) => m
                case None => return out
            }
            for ((pid, rawProvider) in entries) {
                let p = Json.asObj(rawProvider)
                match (p) {
                    case None => ()
                    case Some(pobj) =>
                        let models = ArrayList<CatalogModel>()
                        match (Json.asObj(Json.getOr(rawProvider, "models"))) {
                            case Some(mobj) =>
                                for ((mid, rawModel) in mobj) {
                                    match (catalogModelOf(mid, rawModel)) {
                                        case Some(m) => models.add(m)
                                        case None => ()
                                    }
                                }
                            case None => ()
                        }
                        if (models.isEmpty()) {
                            continue
                        }
                        sortCatalogModels(models)
                        let api = Json.strAt(rawProvider, "api", "")
                        out.add(CatalogProvider(pid, Json.strAt(rawProvider, "name", pid), api, models))
                }
            }
    }
    sortCatalogProviders(out)
    return out
}

/// ⚠ 快照里的数值字段是**扁平键**：`context` / `output` / `cost_in` / `cost_out`。
///
/// 嵌套的 `limit{}` / `cost{}` 两种都读：线上格式哪天改回嵌套，这里照样能读。
/// 两种形状都取不到才是 nil —— 那才是真的「没有」，而不是「读错了键」。
private func catalogModelOf(id: String, raw: JsonValue): Option<CatalogModel> {
    let nestedLimit = Json.asObj(Json.getOr(raw, "limit"))
    let nestedCost = Json.asObj(Json.getOr(raw, "cost"))

    func intFrom(flat: String, nest: String, nobj: Option<ArrayList<(String, JsonValue)>>): Option<Int64> {
        let flatV = Json.intAt(raw, flat, Int64(-1))
        if (flatV >= 0) {
            return Some(flatV)
        }
        match (nobj) {
            case Some(m) =>
                let v = Json.intAt(JsonValue.JObj(m), nest, Int64(-1))
                let r: Option<Int64> = if (v < 0) { None } else { Some(v) }
                return r
            case None => return None
        }
    }
    func numFrom(flat: String, nest: String, nobj: Option<ArrayList<(String, JsonValue)>>): Option<Float64> {
        let flatV = Json.numAt(raw, flat, Float64(-1.0))
        if (flatV >= 0.0) {
            return Some(flatV)
        }
        match (nobj) {
            case Some(m) =>
                let v = Json.numAt(JsonValue.JObj(m), nest, Float64(-1.0))
                let r: Option<Float64> = if (v < 0.0) { None } else { Some(v) }
                return r
            case None => return None
        }
    }

    return Some(CatalogModel(
        id,
        Json.strAt(raw, "name", id),
        Json.boolAt(raw, "tool_call", false),
        Json.boolAt(raw, "reasoning", false),
        intFrom("context", "context", nestedLimit),
        intFrom("output", "output", nestedLimit),
        numFrom("cost_in", "input", nestedCost),
        numFrom("cost_out", "output", nestedCost)
    ))
}

private func sortCatalogModels(models: ArrayList<CatalogModel>): Unit {
    // 插入排序：模型数量级在几百，n² 可接受，且不依赖任何排序 API 形状。
    for (i in 1..models.size) {
        let cur = models[i]
        var j = i - 1
        while (j >= 0 && models[j].id > cur.id) {
            models[j + 1] = models[j]
            j -= 1
        }
        models[j + 1] = cur
    }
}

private func sortCatalogProviders(ps: ArrayList<CatalogProvider>): Unit {
    for (i in 1..ps.size) {
        let cur = ps[i]
        var j = i - 1
        while (j >= 0 && providerLess(cur, ps[j])) {
            ps[j + 1] = ps[j]
            j -= 1
        }
        ps[j + 1] = cur
    }
}

/// 「a 该排在 b 前面」。有端点的优先，其次模型数多，**最后按 id 兜底**。
private func providerLess(a: CatalogProvider, b: CatalogProvider): Bool {
    let aHas = !a.api.isEmpty()
    let bHas = !b.api.isEmpty()
    if (aHas != bHas) {
        return aHas
    }
    if (a.models.size != b.models.size) {
        return a.models.size > b.models.size
    }
    return a.id < b.id
}

// ---------------------------------------------------------------------------
// 目录加载（唯一入口）
// ---------------------------------------------------------------------------

/// 快照候选路径。**按顺序**找，第一个存在的就用。
///
/// 顺序不是随意的：显式环境变量 → XDG 数据目录（刷新过的缓存）→ 默认安装位
/// （`~/.local/share/deepdolphin`）。**缓存排在安装位前面**：用户点过
/// 「刷新目录」之后，刷新结果必须真的被用上 —— 否则「刷新」这个动作在
/// 界面上成功了，下次启动又读回旧的那份。候选构造抽成收三个环境串的
/// **纯函数**（catalogSearchPathCandidates），判据直接断言三条齐全、
/// 缓存先于安装位。
///
/// ⚠ 这里**没有**「当前工作目录」这一项，而且是有意的：
/// 仓颉 1.0.5 没有任何可执行文件自身路径 / 工作目录的 API
/// （实测 getExecutablePath / currentDir / getCwd / getWorkingDir 等
/// 全部 undeclared identifier），而工作目录取决于用户从哪个终端起进程，
/// 换个标签页就变了。仓内快照（`assets/models/models-dev.json`）因此
/// **只有启动脚本够得着**：run.sh / dev-launch.sh 注入 `DEEPDOLPHIN_MODELS`
/// —— 与它注入 `DEEPGIT_BIN` 是同一套做法。⚠ 这句注释曾经只是**声称**：
/// 七个脚本零命中、从文档主入口 run.sh 启动则整个 C7 目录死亡（红色
/// 「模型目录不可用」卡），T2 批次起脚本真的注入，源码扫描判据钉住注入行。
public func catalogSearchPathCandidates(env: String, xdgData: String, home: String): ArrayList<String> {
    let out = ArrayList<String>()
    let e = env.trimAscii()
    if (!e.isEmpty()) {
        out.add(e)
    }
    out.add("${xdgData}/deepdolphin/models-dev.json")
    out.add("${home}/.local/share/deepdolphin/models-dev.json")
    return out
}

public func catalogSearchPaths(): ArrayList<String> {
    return catalogSearchPathCandidates(
        getVariable("DEEPDOLPHIN_MODELS") ?? "",
        homeShare(),
        getVariable("HOME") ?? "")
}

public func findCatalogFile(): String {
    for (p in catalogSearchPaths()) {
        if (exists(p)) {
            return p
        }
    }
    return ""
}

/// 把候选路径列表拼成一句人话。`Array`/`ArrayList` 都没有 `join`。
private func joinPaths(ps: ArrayList<String>): String {
    let sb = StringBuilder()
    for (i in 0..ps.size) {
        if (i > 0) { sb.append("、") }
        sb.append(ps[i])
    }
    return sb.toString()
}

/// XDG 数据基目录：刷新缓存放 `$XDG_DATA_HOME/deepdolphin`，
/// 不放用户配置（候选构造见 catalogSearchPathCandidates）。
public func homeShare(): String {
    let xdg = (getVariable("XDG_DATA_HOME") ?? "").trimAscii()
    if (!xdg.isEmpty() && xdg.startsWith("/")) {
        return xdg
    }
    return "${(getVariable("HOME") ?? "")}/.local/share"
}

/// 读目录。**读不到返回空表**，并由 `catalogProblem()` 说出原因。
private var cachedCatalog: ?ArrayList<CatalogProvider> = None

public func loadCatalog(): ArrayList<CatalogProvider> {
    match (cachedCatalog) {
        case Some(c) => return c
        case None => ()
    }
    let path = findCatalogFile()
    var parsed = ArrayList<CatalogProvider>()
    if (!path.isEmpty()) {
        parsed = parseCatalog(String.fromUtf8(File.readFrom(path)))
    }
    cachedCatalog = Some(parsed)
    return parsed
}

/// 目录为什么不能用。**空串 = 没问题**。设置页原样显示。
public func catalogProblem(): String {
    if (!findCatalogFile().isEmpty()) {
        return ""
    }
    return "找不到 models.dev 目录快照（找过：${joinPaths(catalogSearchPaths())}）。" +
        "AI 设置里会选不了 provider —— 重新获取：curl -fsSL https://models.dev/api.json " +
        "-o assets/models/models-dev.json"
}

/// 某个 provider 的端点。空串 = 目录里没有（要用户手填）。
public func providerAPIFromSnapshot(pid: String): String {
    for (p in loadCatalog()) {
        if (p.id == pid) {
            return p.api
        }
    }
    return ""
}

// ---------------------------------------------------------------------------
// 选择器
// ---------------------------------------------------------------------------

/// Provider 选择器最多列几家（**唯一来源**）。
public const PROVIDER_PICKER_MAX: Int64 = 40

public class ProviderPickerSlice {
    /// 列表里实际列出的家数。
    public let shown: Int64
    /// 目录里**有可用端点**的家数（= 能被列出来的总集合）。
    public let withEndpoint: Int64
    /// 目录总家数（**包含没有端点的那些**）。
    public let total: Int64
    public let cut: Bool
    /// 该补的一句话；空串 = 没什么要说的。
    public let note: String

    public init(shown: Int64, withEndpoint: Int64, total: Int64, cut: Bool, note: String) {
        this.shown = shown
        this.withEndpoint = withEndpoint
        this.total = total
        this.cut = cut
        this.note = note
    }
}

/// 选择器完整度的**唯一**判定点。纯函数，判据直接喂数字。
///
/// ⚠ 这一段是照抄 macOS 端 `providerPickerSlice`（缺陷 #209）：
/// 目录实测 225 家、其中 199 家有端点，而选择器只列前 40 家，
/// **159 家用户根本选不到**。而 section 标题写的是「目录 · 225 家」，
/// 零限定词 —— 一个声称完整的数字配一个被砍过的列表，而没人说。
///
/// 截断本身是合理的（第 40 家 33 模型、第 41 家 32，正好在自然断点上），
/// 要修的是**标签**，不是取消上限。末尾必须给出**可执行的下一步**，
/// 只说「还有 159 家」而不说怎么够到，等于把一个可用功能报成缺失。
public func providerPickerSlice(total: Int64, withEndpoint: Int64, limit!: Int64 = PROVIDER_PICKER_MAX): ProviderPickerSlice {
    let all = (if (total < 0) { Int64(0) } else { total })
    let usable = (if (withEndpoint < 0) { Int64(0) } else { withEndpoint })
    // cap 传 0 会让列表一条都不列，而披露还会说「只列前 0 家」——
    // 与其产出自相矛盾的话，不如至少列一家。
    let cap = (if (limit < 1) { Int64(1) } else { limit })
    let shown = (if (usable < cap) { usable } else { cap })
    if (shown >= usable) {
        return ProviderPickerSlice(shown, usable, all, false, "")
    }
    var note = "只列模型最多的前 ${shown} 家（共 ${usable} 家有可用端点"
    if (all > usable) {
        note += "，目录共 ${all} 家"
    }
    note += "）；其余的可用下方「Base URL 覆盖」手填端点"
    return ProviderPickerSlice(shown, usable, all, true, note)
}

/// 设置页的 provider 候选：**有端点、模型数多的优先**。
/// 排序已在 `sortCatalogProviders` 里做，这里只过滤与截断。
public func popularProviders(limit!: Int64 = PROVIDER_PICKER_MAX): ArrayList<CatalogProvider> {
    let out = ArrayList<CatalogProvider>()
    for (p in loadCatalog()) {
        if (!p.api.isEmpty()) {
            out.add(p)
            if (Int64(out.size) >= limit) {
                break
            }
        }
    }
    return out
}

/// 选择器完整度披露所需的两个数。数字来自**真实目录**，不是写死的。
public func providerPickerCoverage(): ProviderPickerSlice {
    let all = loadCatalog()
    var withEndpoint: Int64 = 0
    for (p in all) {
        if (!p.api.isEmpty()) {
            withEndpoint += 1
        }
    }
    return providerPickerSlice(Int64(all.size), withEndpoint)
}

/// 某家的模型候选。**只列支持 tool_calls 的** —— C6 的 agent 循环
/// 依赖原生工具调用，不支持的模型列出来只会让用户在第一次提问时撞墙。
public func providerToolModels(pid: String): ArrayList<CatalogModel> {
    let out = ArrayList<CatalogModel>()
    for (p in loadCatalog()) {
        if (p.id == pid) {
            for (m in p.models) {
                if (m.toolCall) {
                    out.add(m)
                }
            }
            return out
        }
    }
    return out
}
