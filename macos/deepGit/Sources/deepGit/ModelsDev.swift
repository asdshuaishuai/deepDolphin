// ModelsDev.swift — models.dev 目录访问层（deepOrca model-catalog 同构）。
//
// 定位：**模型数据骨干**。api.json 快照（vendor + 可选网络刷新）提供
// provider → model 的确定性元数据（tool_call / 上下文窗口 / 成本 / api 端点），
// 供设置页选择器与通道组装消费。
// 数据无关、fail-open：快照缺失或畸形时降级为空目录，行为等于今天。
import Foundation

// MARK: - 数据视图

struct CatalogModel {
    let id: String
    let name: String
    let toolCall: Bool
    let reasoning: Bool
    let contextTokens: Int?
    let outputTokens: Int?
    let costInputPerMTok: Double?
    let costOutputPerMTok: Double?
}

struct CatalogProvider {
    let id: String
    let name: String
    /// models.dev 声明的 API 端点（OpenAI 兼容优先；anthropic 官方为 v1 messages）
    let api: String?
    let models: [CatalogModel]

    var modelWithToolCall: [CatalogModel] {
        models.filter { $0.toolCall }
    }

    func model(_ id: String) -> CatalogModel? {
        models.first { $0.id == id }
    }
}

// MARK: - 目录

final class ModelCatalog: @unchecked Sendable {
    static let shared = ModelCatalog()

    private(set) var providers: [CatalogProvider] = []
    private let loadLock = NSLock()
    private static let refreshFlag = "models-dev.refreshed"

    private init() {
        loadBundled()
        refreshFromNetworkIfNeeded()
    }

    /// bundle 内的 vendor 快照（同步、启动即用）
    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "models-dev", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        parse(data: data)
    }

    /// 启动后尝试拉一次最新目录（失败静默，快照兜底）
    private func refreshFromNetworkIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.refreshFlag) else { return }
        UserDefaults.standard.set(true, forKey: Self.refreshFlag)
        guard let url = URL(string: "https://models.dev/api.json") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            let ok = self.parseInto(data: data)  // parseInto 内部自带锁
            if ok {
                // 记住网络版，下次启动优先
                if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let dir = dir.appendingPathComponent("deepGit", isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try? data.write(to: dir.appendingPathComponent("models-dev.json"))
                }
            }
        }
    }

    private func parse(data: Data) {
        loadLock.lock()
        defer { loadLock.unlock() }
        _ = parseInto(data: data)
    }

    /// 返回是否解析成功
    @discardableResult
    private func parseInto(data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        var out: [CatalogProvider] = []
        for (pid, rawProvider) in root {
            guard let p = rawProvider as? [String: Any],
                  let rawModels = p["models"] as? [String: Any], !rawModels.isEmpty else { continue }
            var models: [CatalogModel] = []
            for (mid, rawModel) in rawModels {
                guard let m = rawModel as? [String: Any] else { continue }
                let limit = m["limit"] as? [String: Any]
                let cost = m["cost"] as? [String: Any]
                models.append(CatalogModel(
                    id: mid,
                    name: (m["name"] as? String) ?? mid,
                    toolCall: (m["tool_call"] as? Bool) ?? false,
                    reasoning: (m["reasoning"] as? Bool) ?? false,
                    contextTokens: limit?["context"] as? Int,
                    outputTokens: limit?["output"] as? Int,
                    costInputPerMTok: cost?["input"] as? Double,
                    costOutputPerMTok: cost?["output"] as? Double
                ))
            }
            guard !models.isEmpty else { continue }
            out.append(CatalogProvider(
                id: pid,
                name: (p["name"] as? String) ?? pid,
                api: p["api"] as? String,
                models: models.sorted { $0.id < $1.id }
            ))
        }
        // 有 api 端点的在前（可直接组装通道），其余按模型数
        out.sort {
            if ($0.api?.isEmpty ?? true) != ($1.api?.isEmpty ?? true) {
                return !($0.api?.isEmpty ?? true)
            }
            return $0.models.count > $1.models.count
        }
        loadLock.lock()
        providers = out
        loadLock.unlock()
        return true
    }

    func provider(_ id: String) -> CatalogProvider? {
        providers.first { $0.id == id }
    }

    /// 设置页 provider 候选：有端点、模型数多的优先
    func popularProviders(limit: Int = 40) -> [CatalogProvider] {
        Array(providers.filter { !($0.api?.isEmpty ?? true) }.prefix(limit))
    }
}
