// deepDolphin Linux 客户端 —— 引擎子进程通道。
//
// 注意：术语对齐 macOS 端：这里**不是**进程内 FFI。引擎是**子进程**，
// 与本进程同机但不共享地址空间。引擎刻意不做 dylib 直连
// （见 moonGit/AGENTS.md 不变量 58），本端也就不该绕开它。
//
// 唯一耦合面是引擎 `--json` 的键名，改引擎必须同步本文件的 model.cj。
package deepdolphin_linux

import std.collection.*
import std.env.*
import std.fs.*
import std.io.*
import std.process.*
import std.time.*

/// 子进程执行结果。
///
/// `stdout` 与 `exitCode` 分开看：引擎的退出码表达的是**整体可用性**，
/// 不是每个操作成功与否。全部项目采集失败时它照样打印完整 JSON
/// （含 failedProjects 与每条的具体 error）再 exit 1，stderr 是空的。
/// 所以「非 0 退出 + 有 JSON」是一等公民，不能当失败丢掉载荷。
public class ExecResult {
    public let exitCode: Int64
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int64, stdout: String, stderr: String, timedOut: Bool) {
        this.exitCode = exitCode
        this.stdout = stdout
        this.stderr = stderr
        this.timedOut = timedOut
    }
}

/// 杀掉子进程之后留给读取线程收尾的时间。
///
/// 在 timeout 之外：等到我们决定要杀时 timeout 已经用完，
/// 读取线程还在等 EOF。不给这段时间就只能丢掉已读到的数据。
private const KILL_GRACE_MS: Int64 = 2000

/// 执行命令（同步，带真实超时）。
///
/// - 管道读取放 spawned 线程（读到 EOF），否则大输出写满管道缓冲会卡死子进程
/// - **先等管道读到 EOF，再 wait() 拿退出码** —— 顺序是承重的
/// - `timeoutMs` 是**整次调用**的等待预算，不是每个阶段各给一份
func execCapture(cmd: String, args: Array<String>, timeoutMs: Int64): ExecResult {
    var sub: SubProcess
    try {
        sub = launch(
            cmd, args,
            stdIn: ProcessRedirect.Inherit,
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe
        )
    } catch (e: Exception) {
        return ExecResult(-1, "", e.message, false)
    }

    // 取引到局部变量再交给读取线程：闭包里直接写 sub.stdOutPipe
    // 会让读取线程去访问一个正被主线程 wait() 操作的句柄。
    let outStream = sub.stdOutPipe
    let errStream = sub.stdErrPipe
    let outFuture = spawn { return readAllFromPipe(outStream) }
    let errFuture = spawn { return readAllFromPipe(errStream) }

    // 两个 get 共用**同一个绝对 deadline**。
    let endAt = nowMillis() + timeoutMs
    func left(): Duration {
        let remain = endAt - nowMillis()
        return Duration.millisecond * (if (remain > 0) { remain } else { 1 })
    }

    var outRead = ("", true)
    var errRead = ("", true)
    var timedOut = false
    try {
        outRead = outFuture.get(left())
    } catch (e: TimeoutException) {
        timedOut = true
    }
    if (!timedOut) {
        try {
            errRead = errFuture.get(left())
        } catch (e: TimeoutException) {
            timedOut = true
        }
    }

    if (timedOut) {
        // 必须杀掉再返回。放任不管会留下孤儿进程。
        // 杀掉后管道才会 EOF，上面两个 spawn 读取线程才能退出，避免线程泄漏累积。
        try {
            if (sub.isAlive()) {
                sub.terminate(force: true)
            }
        } catch (e: Exception) {
            ()
        }
        // 尽力把已经读到的数据取回来，别把等待白白丢掉。
        // 拿到的是**残缺**数据，所以下面一律按失败返回，不当成有效输出。
        let graceEnd = nowMillis() + KILL_GRACE_MS
        func graceLeft(): Duration {
            let remain = graceEnd - nowMillis()
            return Duration.millisecond * (if (remain > 0) { remain } else { 1 })
        }
        try {
            outRead = outFuture.get(graceLeft())
        } catch (e: Exception) {
            ()
        }
        try {
            errRead = errFuture.get(graceLeft())
        } catch (e: Exception) {
            ()
        }
        let why = if (errRead[0].isEmpty()) {
            "命令超时或管道未关闭（${timeoutMs}ms）：${cmd}"
        } else {
            errRead[0]
        }
        return ExecResult(-1, "", why, true)
    }

    // 管道都 EOF 了，子进程几乎必然已退出，wait 是瞬时的。
    var code: Int64 = 0
    try {
        code = sub.wait(timeout: Some(left()))
    } catch (e: TimeoutException) {
        try {
            if (sub.isAlive()) { sub.terminate(force: true) }
        } catch (e2: Exception) {
            ()
        }
        return ExecResult(-1, outRead[0], errRead[0], true)
    } catch (e: Exception) {
        code = -1
    }

    // 读取过程中真抛过错 → 拿到的数据是残缺的。
    // 必须报错而不是返回半截输出 + exit 0：调用方无法区分
    // 「命令成功但输出短」和「命令成功但输出被砍了一半」。
    if (!outRead[1] || !errRead[1]) {
        return ExecResult(-1, outRead[0], "读取子进程输出时管道出错，返回的数据不完整", false)
    }
    return ExecResult(code, outRead[0], errRead[0], false)
}

// ---------------------------------------------------------------------------
// 引擎定位
// ---------------------------------------------------------------------------

/// 引擎发现的结果：路径 + 一句能直接贴给用户的话。
public class EngineLocation {
    public let path: String
    /// 定位过程本身的问题（PATH 里两个名字都没有时才有值）。
    public let problem: String
    /// 用了哪个名字命中的，仅用于状态栏展示。
    public let via: String

    public init(path: String, problem: String, via: String) {
        this.path = path
        this.problem = problem
        this.via = via
    }

    public func found(): Bool {
        return !this.path.isEmpty()
    }
}

/// PATH 解析的共用骨架：给定 PATH 原文，按**目录顺序 × 名字顺序**找第一个
/// 满足 `ok` 的候选。**纯函数**（PATH 原文由调用方传入），判据直接喂。
/// 引擎定位（whichFirst，要「跑一下验证」）与通用工具定位（只验存在）
/// 共用这一个实现 —— 顺序规则只写一遍。
func firstOnPathString(pathEnv: String, names: Array<String>, ok: (String) -> Bool): String {
    let sep: UInt8 = 0x3au8 // ':'
    for (name in names) {
        for (dir in splitOnByte(pathEnv, sep)) {
            if (dir.isEmpty()) {
                continue
            }
            let cand = dir + "/" + name
            if (ok(cand)) {
                return cand
            }
        }
    }
    return ""
}

/// PATH 里逐个名字找可执行文件。
private func whichFirst(names: Array<String>): String {
    return firstOnPathString(getVariable("PATH") ?? "", names, { c => isRegularFile(c) && engineRuns(c) })
}

/// PATH 上找通用命令行工具（curl / notify-send / secret-tool）。
/// 与 whichFirst 同一骨架但**只验存在**：工具坏不坏，由调用方在真用时
/// 把 stderr 如实带回来 —— 拿引擎的 `version` 探测去跑 curl 没有意义。
/// 找不到返回空串，调用方回退各自的绝对路径兜底（R3-06：
/// 钉死 /usr/bin 会错过装在 PATH 别处的同名工具）。
func firstToolOnPath(names: Array<String>): String {
    return firstOnPathString(getVariable("PATH") ?? "", names, { c => isRegularFile(c) })
}

/// 按字节切分，避免引入正则（PATH 里可能有含空格或特殊字符的目录）。
private func splitOnByte(s: String, sep: UInt8): Array<String> {
    let out = ArrayList<String>()
    let b = s.toArray()
    var start: Int64 = 0
    var i: Int64 = 0
    while (i < b.size) {
        if (b[i] == sep) {
            out.add(String.fromUtf8(b[start..i]))
            start = i + 1
        }
        i += 1
    }
    out.add(String.fromUtf8(b[start..b.size]))
    return out.toArray()
}

/// 最后一个 '/' 的下标；没有则返回 -1。
///
/// Cangjie 的 `String.lastIndexOf` 返回 `Option<Int64>`，直接参与算术要
/// 先解包，而这里恰恰是「可能没有」的那一半 —— 单独一个函数把两种情况收干净。
func lastSlash(s: String): Int64 {
    match (s.lastIndexOf("/")) {
        case Some(i) => return i
        case None => return -1
    }
}

/// 用分隔符连接字符串。
func joinAll(items: Array<String>, sep: String): String {
    let sb = StringBuilder()
    var first = true
    for (x in items) {
        if (!first) {
            sb.append(sep)
        }
        first = false
        sb.append(x)
    }
    return sb.toString()
}

/// 本进程可执行文件的绝对路径（取自命令行第 0 项）。
private func selfPath(): String {
    let args = getCommandLine()
    if (args.size > 0 && args[0].startsWith("/")) {
        return args[0]
    }
    return ""
}

/// 仓内开发构建产物：`deepDolphin/linux/target/release/bin/main` 上溯四层
/// 到工作区根，再进 `moonGit/target/release/bin/main`。
///
/// 这条只服务「在仓里直接 `cjpm run`」的开发场景。装到别处时这个路径
/// 不存在，函数返回空串，由 `locateEngine` 顺次退到 PATH ——
/// 找不到就明说找不到，绝不静默降级。
private func repoEngineBinary(): String {
    let me = selfPath()
    if (me.isEmpty()) {
        return ""
    }
    var p = me
    // <root>/deepDolphin/linux/target/release/bin/main
    //   bin → release → target → linux → deepDolphin → root，共 6 级
    for (_ in 0..6) {
        let idx = lastSlash(p)
        if (idx < 0) {
            return ""
        }
        p = p[..idx]
    }
    return p + "/moonGit/target/release/bin/main"
}

/// 定位 moonGit 引擎二进制。
///
/// 顺序：`DEEPGIT_BIN` → 仓内 release 构建 → PATH 上的 `moongit` → `deepgit`。
///
/// **新名优先、旧名兜底**，与 `install.sh` 留软链、macOS 端 `EngineCLI.swift`
/// 的顺序一致。写成只找新名会让没跑过新版 install.sh 的机器上
/// 引擎静默找不到 —— 窗口照常打开，只是数据永远不刷新，
/// 那种失败没有任何报错，比直接打不开更难查。
public func locateEngine(): EngineLocation {
    match (getVariable("DEEPGIT_BIN")) {
        case Some(p) =>
            if (!p.isEmpty() && isRegularFile(p) && engineRuns(p)) {
                return EngineLocation(p, "", "DEEPGIT_BIN")
            }
            return EngineLocation("", "DEEPGIT_BIN 指向的引擎不存在：${p}", "DEEPGIT_BIN")
        case None => ()
    }

    let repoBin = repoEngineBinary()
    if (isRegularFile(repoBin) && engineRuns(repoBin)) {
        return EngineLocation(repoBin, "", "仓内构建")
    }

    let p1 = whichFirst(["moongit"])
    if (!p1.isEmpty()) {
        return EngineLocation(p1, "", "PATH")
    }
    let p2 = whichFirst(["deepgit"])
    if (!p2.isEmpty()) {
        return EngineLocation(p2, "", "PATH（旧名）")
    }

    return EngineLocation(
        "",
        "找不到 moonGit 引擎。请运行 moonGit/scripts/install.sh 安装，或设置 DEEPGIT_BIN。",
        ""
    )
}


/// 毫秒时间戳。用于超时预算的绝对 deadline 计算。
func nowMillis(): Int64 {
    return DateTime.now().toUnixTimeStamp().toMilliseconds()
}

/// 从 UTF-8 字节序列解出字符串；尾部残缺字节替换为 U+FFFD 而不是抛错。
///
/// 引擎的输出被截断（管道满了 / 超时杀掉）时，尾上的多字节字符必然残缺。
/// 那时抛异常等于把「输出不完整」说成「进程崩了」—— 调用方无从区分，
/// 而这两种情况的处置完全不同（前者重试即可，后者要查引擎）。
func fromUtf8Lossy(bytes: Array<UInt8>): String {
    let total = bytes.size
    var end = total
    // 最多回退 3 字节：一个 UTF-8 字符最长 4 字节
    var back = 0
    while (back < 4 && end > 0) {
        let b = bytes[end - 1]
        if ((b & 0xc0u8) != 0x80u8) {
            break
        }
        end -= 1
        back += 1
    }
    if (end == total) {
        return String.fromUtf8(bytes)
    }
    if (end > 0) {
        // 末字节的续字节个数必须与已见首字节声明的长度吻合，否则整段替换
        let lead = bytes[end - 1]
        var need: Int64 = 0
        if ((lead & 0xf8u8) == 0xf0u8) {
            need = 4
        } else if ((lead & 0xf0u8) == 0xe0u8) {
            need = 3
        } else if ((lead & 0xe0u8) == 0xc0u8) {
            need = 2
        } else {
            need = 1
        }
        if (need > 1 && (end - 1 + need) <= total) {
            return String.fromUtf8(bytes[..end - 1 + need])
        }
        return String.fromUtf8(bytes[..(end - 1)])
    }
    return String.fromUtf8(bytes)
}

/// 读干管道直到 EOF。返回 (内容, 是否一路没出错)。
///
/// 第二个返回值不能省：读取中途管道被关掉时，已经读到的数据是**残缺**的，
/// 而「残缺输出 + exit 0」和「正常输出 + exit 0」在调用方看来一模一样。
private func readAllFromPipe(pipe: ?InputStream): (String, Bool) {
    match (pipe) {
        case Some(input) =>
            let total = ArrayList<UInt8>()
            let buf = Array<UInt8>(65536, repeat: 0u8)
            var clean = true
            while (true) {
                var n = 0
                try {
                    n = input.read(buf)
                } catch (e: Exception) {
                    clean = false
                    break
                }
                if (n <= 0) {
                    break
                }
                for (i in 0..n) {
                    total.add(buf[i])
                }
            }
            return (fromUtf8Lossy(total.toArray()), clean)
        case None => return ("", true)
    }
}

/// 一次引擎调用的结果：解析好的载荷 + 失败信息。
///
/// 非 0 退出**不等于**没有载荷。引擎把「整体不可用」编码在退出码里，
/// 而失败的具体原因在 payload 里。丢掉 payload 就只剩一句无信息量的
/// 「引擎退出码 1」。
public class EngineCall {
    public let payload: Option<JsonValue>
    /// 给人看的失败原因；成功时为空串。
    public let problem: String
    /// 引擎以非 0 退出但给出了可解析载荷 —— 界面必须照常渲染并披露。
    public let partial: Bool
    /// 载荷来自一个**契约过旧**的引擎：模型依赖的披露字段根本不存在。
    /// 见 `checkContract`。
    public let staleContract: Bool
    /// 引擎自报版本，仅用于把「请升级」这句话说具体。
    public let engineVersion: String

    public init(
        payload: Option<JsonValue>,
        problem: String,
        partial: Bool,
        staleContract: Bool,
        engineVersion: String
    ) {
        this.payload = payload
        this.problem = problem
        this.partial = partial
        this.staleContract = staleContract
        this.engineVersion = engineVersion
    }

    public func ok(): Bool {
        return this.problem.isEmpty()
    }
}

/// 客户端依赖的披露字段。缺任何一个都不能装作「一切正常」。
///
/// 这条判据是实测逼出来的：机器上装着一版**旧** `deepgit`，
/// 它的 `status --json` 里逐项目**根本没有 `error` 字段**，
/// `summary` 里也没有 `failedProjects` / `listedProjects`。
/// 而 `/tmp/dg-rich` 沙箱里正好有 3 个项目路径不可达。
/// 客户端第一次跑时把它们**当成正常项目**渲染出来了 ——
/// 显示成「0 提交、0 分支、无警告」，和真的健康项目逐字一样。
/// 也就是说：一个过旧的引擎能把「读不到」显示成「读到且是空的」，
/// 而用户没有任何线索能发现。
///
/// 所以这里把契约缺字段当成**错误**上报，而不是当成 0。
/// 读载荷的**形状族**。
///
/// ⚠ 为什么必须分族：契约闸门要卡的是「这份载荷有没有把失败说清楚」。
/// 而**每个命令说的字段名不一样**：
///   status  → `summary.failedProjects` / `summary.listedProjects`
///   dashboard → `projects.failed` / `work.*`（**根本没有 `summary` 键**）
///   milestone → `storeHealth` / `readCount`
///   docs    → `docs` / `project`
///   journal → `entries` / `limit`
///
/// 拿 status 的键去卡所有读载荷的后果（**已经犯过**）：
/// dashboard / milestone / docs / journal 的载荷**全部**被判成「契约过旧」，
/// 界面回落到全 0 并且**一句解释都没有** —— 用户看到「语言分布：没有采集到」，
/// 真实情况是「载荷被闸门丢了」。把「读不出来」画成「确实没有」，
/// 是本项目最不该犯的一类错（不变量 81）。
public enum PayloadShape {
    | Status
    | Dashboard
    | Milestones
    | Docs
    | Journal
    /// 形状随参数变（update / git / milestone 写 / context / tools），不做闸门。
    | Free
}

/// 这个族**必须**有的披露键。缺任何一个就判「契约过旧」。
private func requiredKeysOf(shape: PayloadShape): Array<String> {
    match (shape) {
        case PayloadShape.Status => return ["projects", "summary"]
        case PayloadShape.Dashboard => return ["projects", "work", "languages"]
        case PayloadShape.Milestones => return ["milestones", "storeHealth", "readCount"]
        case PayloadShape.Docs => return ["docs", "project"]
        case PayloadShape.Journal => return ["entries", "limit"]
        case PayloadShape.Free => return []
    }
}

/// `status` 这一族要额外查 `summary` 里的两个计数 ——
/// 它是唯一把失败数放在 `summary` 下的命令。
public func checkContract(payload: JsonValue): Bool {
    return checkContractOf(payload, PayloadShape.Status)
}

/// 按形状族做契约闸门。
public func checkContractOf(payload: JsonValue, shape: PayloadShape): Bool {
    let required = requiredKeysOf(shape)
    if (required.isEmpty()) {
        return true
    }
    for (k in required) {
        if (!Json.has(payload, k)) {
            return false
        }
    }
    if (shapeIs(shape, PayloadShape.Status)) {
        let s = Json.getOr(payload, "summary")
        for (k in ["failedProjects", "listedProjects"]) {
            if (!Json.has(s, k)) {
                return false
            }
        }
    }
    return true
}

public func shapeIs(a: PayloadShape, b: PayloadShape): Bool {
    // ⚠⚠ 这里**绝不能写成自调用**。
    //
    // 第一版我写的是 `case PayloadShape.Status => return shapeIs(b, PayloadShape.Status)`，
    // 想「复用一遍判断」——结果 `a == b == Status` 时它自己调自己，
    // **无限递归**。后果不是报错，是**挂死**：进程 0% CPU、栈无限深，
    // 界面上永远停在「读取项目群…」，而原因（栈太深）在界面上一个字都看不到。
    //
    // 之所以能溜过去：这条路径只在**真数据**上才走到，
    // 而当时的判据用的都是几百字节的手写夹具 —— 见 `realEngineFixturesParseIntoModels`。
    // 顺带说明：仓颉枚举也不实现 `==`，所以这里必须用 `match` 逐档比。
    match (a) {
        case PayloadShape.Status => return match (b) {
            case PayloadShape.Status => true
            case _ => false
        }
        case PayloadShape.Dashboard => return match (b) {
            case PayloadShape.Dashboard => true
            case _ => false
        }
        case PayloadShape.Milestones => return match (b) {
            case PayloadShape.Milestones => true
            case _ => false
        }
        case PayloadShape.Docs => return match (b) {
            case PayloadShape.Docs => true
            case _ => false
        }
        case PayloadShape.Journal => return match (b) {
            case PayloadShape.Journal => true
            case _ => false
        }
        case PayloadShape.Free => return match (b) {
            case PayloadShape.Free => true
            case _ => false
        }
    }
}

/// 形状族的中文名。披露文案要用。
public func shapeLabel(shape: PayloadShape): String {
    match (shape) {
        case PayloadShape.Status => return "状态"
        case PayloadShape.Dashboard => return "仪表盘"
        case PayloadShape.Milestones => return "里程碑"
        case PayloadShape.Docs => return "文档"
        case PayloadShape.Journal => return "日志"
        case PayloadShape.Free => return "结果"
    }
}

/// 调一次引擎并解析它的 `--json` 输出。
///
/// 契约：即使 `res.exitCode != 0`，只要 stdout 是可解析的 JSON 就返回它，
/// 由调用方决定怎么披露。返回 `problem` 时 `payload` 可能是 None
/// （引擎根本没吐出可解析的东西）。
public func callEngine(bin: String, args: Array<String>, timeoutMs: Int64): EngineCall {
    let res = execCapture(bin, args, timeoutMs)
    if (res.timedOut) {
        return EngineCall(None, res.stderr, false, false, "")
    }
    let ver = engineVersionOf(bin)

    match (Json.parse(res.stdout)) {
        case Some(v) =>
            let stale = !checkContract(v)
            if (stale) {
                return EngineCall(
                    Some(v),
                    staleContractMessage(ver),
                    true,
                    true,
                    ver
                )
            }
            if (res.exitCode == 0) {
                return EngineCall(Some(v), "", false, false, ver)
            }
            // 有载荷但退出码非 0：整体不可用，载荷仍要交给界面。
            return EngineCall(Some(v), describeEngineFailure(res), true, false, ver)
        case None =>
            let why = if (!res.stderr.isEmpty()) {
                res.stderr.trimAscii()
            } else {
                "引擎没有输出可解析的 JSON（退出码 ${res.exitCode}）"
            }
            return EngineCall(None, why, false, false, ver)
    }
}

/// 读一次引擎自报版本（缓存意义不大，但只要在报错路径上跑一次）。
private func engineVersionOf(bin: String): String {
    let r = execCapture(bin, ["version"], 8000)
    if (r.timedOut || r.exitCode != 0) {
        return ""
    }
    return r.stdout.trimAscii()
}

func staleContractMessage(ver: String): String {
    let who = if (ver.isEmpty()) { "找到的引擎" } else { "引擎 ${ver}" }
    return "${who} 的输出缺少本客户端依赖的披露字段（failedProjects / listedProjects / 逐项目 error）。" +
        "这种情况下读不到的项目会被显示成「没有数据」，与真的空项目无法区分。" +
        "请用 moonGit/scripts/install.sh 升级引擎。"
}

/// 从引擎的输出里挖出**具体**的失败原因。
///
/// 引擎的全部项目采集失败时会打印完整 JSON 再 exit 1，stderr 是空的。
/// 只报「引擎退出码 1」等于把载荷白留；所以这里优先读 `error` /
/// `failedProjects` 里的原文。
func describeEngineFailure(res: ExecResult): String {
    match (Json.parse(res.stdout)) {
        case Some(v) =>
            let top = Json.strAt(v, "error", "")
            if (!top.isEmpty()) {
                return top
            }
            let failed = Json.arrAt(v, "failedProjects")
            if (!failed.isEmpty()) {
                let names = ArrayList<String>()
                for (p in failed) {
                    let n = Json.strAt(p, "name", "?")
                    let e = Json.strAt(p, "error", "")
                    names.add(if (e.isEmpty()) { n } else { "${n}（${e}）" })
                }
                return "有 ${names.size} 个项目读取失败：${joinAll(names.toArray(), "、")}"
            }
        case None => ()
    }
    if (!res.stderr.isEmpty()) {
        return res.stderr.trimAscii()
    }
    return "引擎退出码 ${res.exitCode}（未给出原因）"
}

/// 候选路径**真能当引擎跑起来**吗。
///
/// 仓颉 1.0.5 的 `FileInfo` **没有**权限位成员（只有 `isDirectory()`），
/// 所以「有没有可执行位」这件事在语言层面根本问不到。
/// 与其猜，不如真跑一次：启动一个不可执行的同名文件会直接抛错，
/// 而这正是我们要排除的那种情况。`version` 无副作用、几十毫秒返回。
private func engineRuns(path: String): Bool {
    let r = execCapture(path, ["version"], 8000)
    return !r.timedOut && r.exitCode == 0
}

/// 是常规文件（不是目录）。
///
/// ⚠ **空路径必须在这里挡掉**。`Path("")` 在仓颉里是
/// `IllegalArgumentException: The path cannot be empty!`，
/// 而 `locateEngine` 的候选表里**天然会出现空串**
/// （`DEEPGIT_BIN` 未设、`repoEngineBinary()` 上溯失败、PATH 里没找到）。
/// 之前这里没挡，结果是：**没有装引擎的机器上，应用一启动就崩** ——
/// 界面上那句「请运行 install.sh 安装，或设置 DEEPGIT_BIN」
/// 永远显示不出来。披露做得再全，崩在披露之前就等于没有。
func isRegularFile(path: String): Bool {
    if (path.isEmpty()) {
        return false
    }
    let p = Path(path)
    if (!exists(p)) {
        return false
    }
    try {
        return !FileInfo(p).isDirectory()
    } catch (e: Exception) {
        // FileInfo 的构造器遇到 stat 失败是抛异常，不是返回错误码。
        // 契约是返回 Bool，所以这里必须兜住。
        return false
    }
}


