// EngineCLI.swift — 引擎进程内通信层（deepDesign 模式的数据通道）。
//
// 【边界】客户端通过 CLI 子进程调用引擎（`deepgit <命令> --json`），
// 不走 HTTP 网络。引擎二进制来自应用内嵌副本或系统安装。
// 每次调用是独立子进程：无状态、无端口、无网络、无并发冲突。
import Foundation

enum EngineError: LocalizedError {
    case notFound
    case failed(String)
    case timeout(Int)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "找不到 deepGit 引擎。请运行 deepgit-engine/scripts/install.sh 安装，或设置 DEEPGIT_BIN"
        case .failed(let msg):
            return msg
        case .timeout(let sec):
            return "引擎调用超时（\(sec)s）"
        }
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
        if let bundled = Bundle.main.path(forResource: "deepgit", ofType: nil) {
            paths.append(bundled)
        }
        paths.append(NSHomeDirectory() + "/.local/bin/deepgit")
        paths.append("/usr/local/bin/deepgit")
        paths.append("/opt/homebrew/bin/deepgit")
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

        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning {
            proc.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if proc.isRunning { proc.interrupt() }
            throw EngineError.timeout(Int(timeout))
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
            let msg = String(data: errBuf, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw EngineError.failed(msg.isEmpty ? "引擎退出码 \(proc.terminationStatus)" : msg)
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
}
