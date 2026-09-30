// Engine.swift — 引擎发现、进程管理与 HTTP API 客户端。
//
// 【边界】客户端只做展示与交互：
//   - 发现并（按需）拉起引擎 HTTP 服务（deepgit serve）
//   - 所有数据读取走 GET /api/*，所有写操作走 POST /api/*
//   - CLI 进程调用仅保留给「启动服务」与「登录 shell 找引擎」两件事
import Foundation
import AppKit

// MARK: - 错误

enum EngineError: LocalizedError {
    case notFound
    case failed(String)
    case timeout(Int)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "找不到 deepgit 引擎。请运行 deepGit/scripts/install.sh 安装，或设置 DEEPGIT_BIN"
        case .failed(let msg):
            return msg
        case .timeout(let sec):
            return "引擎调用超时（\(sec)s）"
        }
    }
}

// MARK: - 引擎进程管理

final class DeepGitEngine: @unchecked Sendable {
    static let shared = DeepGitEngine()

    private(set) var binaryPath: String?
    private var pathLookupDone = false
    private var serverProcess: Process?
    private(set) var serverManagedByUs = false

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
        binaryPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func refreshBinary() {
        binaryPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        if binaryPath == nil && !pathLookupDone {
            pathLookupDone = true
            binaryPath = lookupInUserShell()
        }
    }

    /// GUI 进程的 PATH 不含用户 shell 配置，用登录 shell 找一次
    private func lookupInUserShell() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "command -v deepgit"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (!path.isEmpty && FileManager.default.isExecutableFile(atPath: path)) ? path : nil
    }

    var serverPort: Int {
        if let s = ProcessInfo.processInfo.environment["DEEPGIT_PORT"], let p = Int(s), p > 0 {
            return p
        }
        return 5177
    }

    func probeServer() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(serverPort)/api/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// 拉起引擎服务（已在运行则直接返回 true）
    func ensureServer() async -> Bool {
        if await probeServer() { return true }
        guard let bin = binaryPath else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["serve", "--port", "\(serverPort)"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        proc.environment = env
        do {
            try proc.run()
        } catch {
            return false
        }
        serverProcess = proc
        serverManagedByUs = true
        for _ in 0..<40 {
            if await probeServer() { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return await probeServer()
    }

    func stopServerIfOurs() {
        guard serverManagedByUs else { return }
        serverProcess?.terminate()
        serverProcess = nil
        serverManagedByUs = false
    }
}

// MARK: - HTTP API 客户端

final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private var base: URL {
        URL(string: "http://127.0.0.1:\(DeepGitEngine.shared.serverPort)")!
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let (data, resp) = try await URLSession.shared.data(for: URLRequest(url: comps.url!))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw EngineError.failed("GET \(path) 失败（HTTP \(code)）")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    func post(_ path: String, query: [String: String] = [:], body: [String: Any] = [:]) async throws -> Data {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        if !body.isEmpty {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw EngineError.failed("POST \(path) 失败（HTTP \(code)）\(msg.isEmpty ? "" : "：\(msg)")")
        }
        return data
    }
}

// MARK: - 系统小工具

enum SysOpen {
    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    static func openTerminal(at path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Terminal", path]
        try? proc.run()
    }

    static func openRemote(_ remote: String) {
        var url = remote
        if url.hasPrefix("git@") {
            url = url.replacingOccurrences(of: ":", with: "/")
                .replacingOccurrences(of: "git@", with: "https://")
        }
        url = url.replacingOccurrences(of: ".git", with: "")
        if let u = URL(string: url) {
            NSWorkspace.shared.open(u)
        }
    }
}
