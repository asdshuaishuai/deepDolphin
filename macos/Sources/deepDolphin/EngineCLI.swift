// EngineCLI.swift — 引擎的本机进程间通信层（deepDesign 模式的数据通道）。
//
// ⚠️ 术语：这里**不是**「进程内 FFI」。引擎是**子进程**（或 MCP stdio），
// 与本进程在同一台机器上，但不共享地址空间。进程内 FFI（dylib 直连）已决定不做，
// 见 moonGit/AGENTS.md 不变量 58。
//
// 【边界】客户端通过 CLI 子进程调用引擎（`deepgit <命令> --json`），
// 不走 HTTP 网络。引擎二进制来自应用内嵌副本或系统安装。
// 每次调用是独立子进程：无状态、无端口、无网络、无并发冲突。
import Foundation

enum EngineError: LocalizedError {
    case notFound
    case failed(String)
    /// 引擎以非 0 退出，但 stdout 是一份可解析的 JSON。
    ///
    /// 必须带 payload 抛出来而不是丢掉 —— 引擎的退出码表达的是「整体可用性」，
    /// 不是「每个操作成功与否」。全部项目采集失败时它照样打印完整 JSON
    /// （含 failedProjects 与每条的具体 error）再 exit 1，而 stderr 是空的。
    /// 丢掉 payload 就只剩一句无信息量的「引擎退出码 1」。
    case failedWithPayload(message: String, payload: Data)
    case timeout(Int)
    /// 用户主动停止。**必须和 timeout 分开**：
    /// 被停掉是他自己按的（不必惊慌、不该报"失败"），
    /// 超时是引擎卡住了（要报、且值得担心）。
    /// 混成一句「操作失败」会让人以为刚跑了一半的更新坏了。
    case cancelled(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "找不到 moonGit 引擎。请运行 moonGit/scripts/install.sh 安装，或设置 DEEPGIT_BIN"
        case .failed(let msg):
            return msg
        case .failedWithPayload(let msg, _):
            return msg
        case .timeout(let sec):
            return "引擎调用超时（\(sec)s）"
        case .cancelled(let cmd):
            return "已停止：\(cmd)"
        }
    }

    /// 若这个错误带着引擎的 JSON 输出，取出来。
    var jsonPayload: Data? {
        if case .failedWithPayload(_, let payload) = self { return payload }
        return nil
    }

    /// **给人（和模型）看的失败原因**。
    ///
    /// ⚠️ 缺陷 #193：`errorDescription` 在 `failedWithPayload` 这一支返回的是
    /// 「引擎退出码 1」——`run` 构造它时**根本没看 payload**。而载荷里
    /// 引擎把原因写得明明白白（`DOC_WRITE_FAILED` 那条甚至逐个文件列了
    /// Permission denied）。于是所有 `catch` 里的 `error.localizedDescription`
    /// 拿到的都是那句无信息量的话，载荷白留了。
    ///
    /// `errorDescription` 本身**不能改**：它是 `LocalizedError` 的协议要求，
    /// 而 payload 的解码要跑 JSON 解析。协议实现与判定拆开，
    /// 由本属性负责「读得懂载荷的那一层」。
    ///
    /// 消费方一律改用本属性，不要再用 `errorDescription` / `localizedDescription`。
    var userMessage: String {
        guard case .failedWithPayload = self else { return errorDescription ?? "引擎失败（无详细信息）" }
        return EngineFailure.reason(payload: jsonPayload,
                                    fallback: errorDescription ?? "引擎失败（无详细信息）")
    }

    /// 给 `catch` 块用的统一入口：`catch { lastError = ??? }` 写成
    /// `catch { lastError = EngineError.userMessage(for: error) }`。
    ///
    /// 为什么不要求每个 catch 都手写 `as? EngineError`：
    /// 缺陷 #193 的根因就是「正确写法要跨三个文件记住十几次」——
    /// 于是那 25 处一处都没写。**判据要能在一行里用完**，
    /// 否则它就等于不存在。`as? EngineError` 里不是引擎错误的照旧
    /// 走 `localizedDescription`（AI 侧、网络侧的错也走这一个函数）。
    static func userMessage(for error: any Error) -> String {
        if let e = error as? EngineError { return e.userMessage }
        return error.localizedDescription
    }
}

final class EngineCLI: @unchecked Sendable {
    static let shared = EngineCLI()

    private var _binaryPath: String?
    private let pathLock = NSLock()
    private var pathLookupDone = false

    /// 线程安全读取（runJSON/runData 在 detached 线程并发读）
    var binaryPath: String? {
        pathLock.lock(); defer { pathLock.unlock() }
        return _binaryPath
    }

    // MARK: 引擎发现

    private var candidates: [String] {
        var paths: [String] = []
        if let env = ProcessInfo.processInfo.environment["DEEPGIT_BIN"], !env.isEmpty {
            paths.append(env)
        }
        // 内嵌副本与已安装版都先找新名 moongit，再回退旧名 deepgit。
        //
        // ⚠️ 回退不能省：引擎命令名 2026-10-03 改成 moongit，但装在用户机器上的
        //    旧版仍然是 ~/.local/bin/deepgit。只列新名的话，**没跑过 install.sh
        //    的机器上引擎会静默找不到** —— 而找不到时上层会回落到「无引擎」态，
        //    面板照常打开、只是所有数据都不刷新，看不出是「引擎没找到」。
        for name in ["moongit", "deepgit"] {
            if let bundled = Bundle.main.path(forResource: name, ofType: nil) {
                paths.append(bundled)
            }
        }
        for dir in ["\(NSHomeDirectory())/.local/bin", "/usr/local/bin", "/opt/homebrew/bin"] {
            paths.append("\(dir)/moongit")
            paths.append("\(dir)/deepgit")
        }
        return paths
    }

    private init() {
        _binaryPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func refreshBinary() {
        pathLock.lock(); defer { pathLock.unlock() }
        _binaryPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        if _binaryPath == nil && !pathLookupDone {
            pathLookupDone = true
            _binaryPath = lookupInUserShell()
        }
    }

    private func lookupInUserShell() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "command -v deepgit"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (!path.isEmpty && FileManager.default.isExecutableFile(atPath: path)) ? path : nil
    }

    // MARK: 核心执行

    /// 运行引擎 CLI 命令，返回 stdout Data。超时保护 + 管道持续读取防死锁。
    func run(_ args: [String], timeout: TimeInterval = 60) throws -> Data {
        if binaryPath == nil { refreshBinary() }
        guard let bin = binaryPath else { throw EngineError.notFound }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        var outBuf = Data()
        var errBuf = Data()
        let lock = NSLock()
        // EOF 信号量：handler 收到空数据（EOF）时 signal——收尾必须等它，
        // 否则 handler 手里的最后一块数据可能在 readDataToEndOfFile 之后才 append（乱序）
        let outEOF = DispatchSemaphore(value: 0)
        let errEOF = DispatchSemaphore(value: 0)
        var outSawEOF = false
        var errSawEOF = false
        outPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty {
                h.readabilityHandler = nil
                lock.lock(); outSawEOF = true; lock.unlock()
                outEOF.signal()
            } else {
                lock.lock(); outBuf.append(d); lock.unlock()
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty {
                h.readabilityHandler = nil
                lock.lock(); errSawEOF = true; lock.unlock()
                errEOF.signal()
            } else {
                lock.lock(); errBuf.append(d); lock.unlock()
            }
        }

        do { try proc.run() } catch {
            throw EngineError.failed("无法启动引擎（\(bin)）：\(error.localizedDescription)")
        }
        registry.add(proc, command: args.first ?? "")

        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        // 「用户按了停止」与「跑到超时」是两件事，对用户也是两条完全不同的消息：
        // 前者是他自己干的（不必惊慌、更不该报失败），后者是引擎卡住了。
        // 由注册表回答"谁停的" —— 不用退出状态反推，见 ProcessRegistry 注释。
        let stoppedByUser = registry.remove(proc)
        if proc.isRunning {
            proc.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if proc.isRunning { proc.interrupt() }
            registry.remove(proc)
            throw EngineError.timeout(Int(timeout))
        }
        if stoppedByUser {
            throw EngineError.cancelled(args.first ?? "引擎命令")
        }

        // 等 handler 报 EOF（最长 2s 防御），再做清尾追加——消除乱序窗口
        _ = outEOF.wait(timeout: .now() + 2)
        _ = errEOF.wait(timeout: .now() + 2)
        lock.lock(); defer { lock.unlock() }
        if !outSawEOF {
            outBuf.append(outPipe.fileHandleForReading.readDataToEndOfFile())
        }
        if !errSawEOF {
            errBuf.append(errPipe.fileHandleForReading.readDataToEndOfFile())
        }
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        if proc.terminationStatus != 0 {
            // ⚠️ **stdout 不能丢**。
            //
            // 引擎的退出码语义是「整体是否可用」，不是「每个操作是否成功」：
            //   `status --json` 全部项目采集失败 → 先打印完整 JSON（含每个项目
            //     各自的 error 与原因），再 exit 1。cli.cj 的注释原话：
            //     「JSON 消费者尚可从 failedProjects / projects.failed 恢复，
            //       靠退出码判断的不行」
            //   `milestone list --json` milestones.json 损坏 → exit 1
            //
            // 实测（两个项目路径全失效）：
            //   exit=1, stdout=2572 字节合法 JSON（failedProjects=2，
            //   每条都带「路径不存在或卷未挂载：…」）, **stderr=0 字节**
            //
            // 原来这里无条件 throw，outBuf 整份被丢，而 stderr 是空的 ⇒
            // 抛出的消息退化成 "引擎退出码 1" —— 真实原因（每个项目各自的具体
            // 错误）一个字都没留下。Model.swift 的 catch 只设 lastError，
            // 于是用户看到「引擎退出码 1」，菜单栏却继续显示上一次刷新的旧数据。
            //
            // 修法：stdout 能解析成 JSON 就先把它交给调用方，让上层用
            // failedProjects / per-project error 决定怎么呈现；
            // 确实解析不了（真崩了）才退回 stderr / 退出码文案。
            let msg = String(data: errBuf, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: outBuf),
               obj is [String: Any] {
                // 形状是对的：把 JSON 还给调用方，别把原因吞了。
                // 退出码信息挂在消息上，调用方若只想要数据可以忽略。
                let note = msg.isEmpty ? "" : "\n\(msg)"
                throw EngineError.failedWithPayload(
                    message: "引擎退出码 \(proc.terminationStatus)\(note)",
                    payload: outBuf
                )
            }
            // ⚠️ 缺陷 #193 的第二条：stdout 不是 JSON 时**也别整份丢掉**。
            //
            // usage 类失败恰恰是这种形状 —— 实测
            // `deepgit git commit proj`（缺 --message）：
            //   rc=1, stdout=`需要提交信息（--message）`（纯文本，**真因在这**）,
            //   stderr=`✗ proj：commit 失败`（一句没信息量的汇总）
            // 原来这里只取 stderr ⇒ 用户看到「✗ proj：commit 失败」，
            // 唯一说清「要加 --message」的那句掉在地上。
            //
            // 拼接规则：**stdout 是主因，stderr 是补充**。
            // 顺序反过来就等于把汇总放在解释前面，等于没修。
            let outText = String(data: outBuf, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var parts: [String] = []
            if !outText.isEmpty { parts.append(outText) }
            if !msg.isEmpty { parts.append(msg) }
            if parts.isEmpty { parts.append("引擎退出码 \(proc.terminationStatus)") }
            throw EngineError.failed(parts.joined(separator: "\n"))
        }
        return outBuf
    }

    /// 解析 JSON 输出
    func runJSON<T: Decodable>(_ args: [String], as type: T.Type, timeout: TimeInterval = 120) async throws -> T {
        let data = try await Task.detached(priority: .utility) { [self] in
            try run(args, timeout: timeout)
        }.value
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 返回原始 Data
    func runData(_ args: [String], timeout: TimeInterval = 120) async throws -> Data {
        return try await Task.detached(priority: .utility) { [self] in
            try run(args, timeout: timeout)
        }.value
    }

    // MARK: 停止

    /// 正在跑的引擎子进程。
    ///
    /// **为什么必须有这张表**：取消 Swift 侧的 Task 杀不掉引擎进程。
    /// `run` 是同步阻塞的（`Thread.sleep` 轮询），`runData` 把它包在
    /// `Task.detached` 里 —— 而**取消只对结构化并发传播**，
    /// detached task 不受调用方取消影响。于是：
    ///
    ///     Task { await model.updateAll(...) }.cancel()
    ///     → 外层提前返回，detached 那个照样阻塞
    ///     → 引擎子进程一直跑到自己结束或超时（updateAll 最长 **900 秒**）
    ///
    /// 所以「停止」的唯一有效动作是**真的 terminate 那个 Process**。
    /// 没有这张表，UI 上就只能挂一个假的停止按钮。
    private final class ProcessRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var procs: [ObjectIdentifier: (proc: Process, command: String)] = [:]
        /// 被**用户主动**停掉的进程。
        ///
        /// 为什么不从 `terminationStatus` / `terminationReason` 反推：
        /// 超时分支的 `interrupt()` 同样会让进程死于信号，
        /// 两种情况在 Foundation 眼里长得几乎一样 ——
        /// 靠退出状态猜「这是用户按的」迟早会猜错，
        /// 而猜错的后果是：用户主动停了，却弹一个「超时」的报错。
        /// 谁停的，只有发起方知道，所以由发起方记。
        private var userStopped: Set<ObjectIdentifier> = []

        func add(_ p: Process, command: String) {
            lock.lock(); defer { lock.unlock() }
            procs[ObjectIdentifier(p)] = (p, command)
        }

        /// 取出并移除，返回它是否被用户主动停过。
        func remove(_ p: Process) -> Bool {
            lock.lock(); defer { lock.unlock() }
            let id = ObjectIdentifier(p)
            procs.removeValue(forKey: id)
            return userStopped.remove(id) != nil
        }

        /// 返回被终止的进程数。
        @discardableResult
        func terminate(matching predicate: (String) -> Bool) -> Int {
            lock.lock()
            let hits = procs.filter { predicate($0.value.command) }
            for (id, _) in hits { userStopped.insert(id) }
            let targets = hits.map(\.value.proc)
            lock.unlock()
            var n = 0
            for p in targets where p.isRunning {
                p.terminate()
                n += 1
            }
            return n
        }
        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return procs.count
        }
    }

    private let registry = ProcessRegistry()

    /// 正在运行的引擎子进程数（UI 用来决定「可停止」）。
    var runningProcessCount: Int { registry.count }

    /// 终止正在跑的引擎子进程。
    ///
    /// `onlyCommands` 为空表示全杀；给出前缀则只杀匹配的
    /// ——「停止更新」不该顺手把并行的状态刷新也掐掉。
    ///
    /// `terminate()` 发的是 SIGTERM，引擎有机会正常收尾；
    /// 真不动的那些由 `run` 里的超时分支升级到 `interrupt()`。
    @discardableResult
    func terminateRunning(onlyCommands: [String] = []) -> Int {
        guard !onlyCommands.isEmpty else { return registry.terminate { _ in true } }
        return registry.terminate { command in
            onlyCommands.contains { command.hasPrefix($0) }
        }
    }
}
