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

// MARK: - 解析（纯函数，无锁、无全局状态）

/// 从 models.dev 的 `api.json` 快照解出目录。
///
/// 【为什么不放在 ModelCatalog 里直接解析】
/// 原来的 `parse()` 是这样写的：
/// ```swift
/// private func parse(data: Data) {
///     loadLock.lock()
///     defer { loadLock.unlock() }
///     _ = parseInto(data: data)   // ← parseInto 内部第 140 行又 loadLock.lock()
/// }
/// ```
/// `NSLock` **不可重入**（不是 `NSRecursiveLock`），于是同一线程二次加锁 ⇒ 永久死锁。
/// 触发路径：没有 Application Support 缓存、但 bundle 里有 `models-dev.json` ——
/// 也就是**打包后的 .app**。`swift run` 不触发（Bundle 无资源，提前 return），
/// 所以开发期怎么测都测不出来，而打包版 AI 功能 100% 永久不可用；
/// 又因为 `init` 卡死，磁盘缓存永远写不进去，每次启动都重蹈覆辙。
///
/// 抽成纯函数后，「解析」与「加锁」在物理上就是两段代码，自死锁无从写出。
func parseCatalog(data: Data) -> [CatalogProvider] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return []
    }
    var out: [CatalogProvider] = []
    for (pid, rawProvider) in root {
        guard let p = rawProvider as? [String: Any],
              let rawModels = p["models"] as? [String: Any], !rawModels.isEmpty else { continue }
        var models: [CatalogModel] = []
        for (mid, rawModel) in rawModels {
            guard let m = rawModel as? [String: Any] else { continue }
            models.append(CatalogModel(id: mid, raw: m))
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
    return out
}

extension CatalogModel {
    /// 快照里的数值字段是**扁平键**：`context` / `output` / `cost_in` / `cost_out`。
    ///
    /// ⚠️ 原实现读的是嵌套的 `limit{}` / `cost{}`，而实际快照里这两个键
    /// **根本不存在**（实测 `Resources/models-dev.json`：225 个 provider、
    /// model 的键是 context/cost_in/cost_out/name/output/reasoning/tool_call）。
    /// 于是 225 个 provider 的上下文窗口与成本徽标**全为 nil**，
    /// 设置页的徽标静默消失 —— 数据在，只是读不出来。
    ///
    /// 嵌套写法仍然兼容：models.dev 的线上格式若哪天改回嵌套，这里照样能读。
    /// 两种形状都取不到时才是 nil —— 那才是真的「没有」。
    init(id: String, raw: [String: Any]) {
        let limit = raw["limit"] as? [String: Any]
        let cost = raw["cost"] as? [String: Any]
        self.init(
            id: id,
            name: (raw["name"] as? String) ?? id,
            toolCall: (raw["tool_call"] as? Bool) ?? false,
            reasoning: (raw["reasoning"] as? Bool) ?? false,
            contextTokens: (raw["context"] as? Int) ?? (limit?["context"] as? Int),
            outputTokens: (raw["output"] as? Int) ?? (limit?["output"] as? Int),
            costInputPerMTok: (raw["cost_in"] as? Double) ?? (cost?["input"] as? Double),
            costOutputPerMTok: (raw["cost_out"] as? Double) ?? (cost?["output"] as? Double)
        )
    }
}

// MARK: - 目录

final class ModelCatalog: @unchecked Sendable {
    static let shared = ModelCatalog()

    private var _providers: [CatalogProvider] = []
    private let loadLock = NSLock()
    var providers: [CatalogProvider] {
        loadLock.lock(); defer { loadLock.unlock() }
        return _providers
    }
    private static let refreshFlag = "models-dev.refreshed"

    private init() {
        loadBundled()
        refreshFromNetworkIfNeeded()
    }

    /// 只跑「解析 → 加锁赋值 → 读出」这一条路径，不碰磁盘也不发网络请求。
    ///
    /// 存在的理由：自死锁只发生在这条路径上，而 `private init` 会顺带读
    /// Application Support、读 Bundle、**发一个真实的 models.dev 网络请求** ——
    /// 都不能塞进检查程序里。走这个入口才能既复现「加锁赋值」这一步，
    /// 又不掺任何别的副作用。
    init(snapshotOnly data: Data) {
        adopt(parseCatalog(data: data))
    }

    /// **唯一的**写入点。解析在锁外做完，这里只负责换引用。
    private func adopt(_ parsed: [CatalogProvider]) {
        guard !parsed.isEmpty else { return }
        loadLock.lock(); defer { loadLock.unlock() }
        _providers = parsed
    }

    /// bundle 内的 vendor 快照（同步、启动即用）
    private func loadBundled() {
        // 优先读回上次网络刷新的快照（比 bundle 内的新）
        if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let cached = dir.appendingPathComponent("deepGit/models-dev.json")
            if let data = try? Data(contentsOf: cached) {
                adopt(parseCatalog(data: data))
                if !providers.isEmpty { return }
            }
        }
        guard let url = Bundle.main.url(forResource: "models-dev", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        adopt(parseCatalog(data: data))
    }

    /// 启动后尝试拉一次最新目录（失败静默，快照兜底）
    private func refreshFromNetworkIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.refreshFlag) else { return }
        guard let url = URL(string: "https://models.dev/api.json") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            let parsed = parseCatalog(data: data)
            guard !parsed.isEmpty else { return }
            self.adopt(parsed)
            if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let dir = dir.appendingPathComponent("deepGit", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? data.write(to: dir.appendingPathComponent("models-dev.json"))
            }
            // ⚠️ 刷新标志**成功之后**才置位。
            // 原实现在发起请求**之前**就置位，于是断网启动一次 ⇒ 终身不再重试：
            // 这个标志写在 UserDefaults 里，跨启动存活，而用户可能只是当时没网。
            // 「拉不到就永远不拉」正是本项目反复修的那族缺陷（读不出来说成没有）。
            UserDefaults.standard.set(true, forKey: Self.refreshFlag)
        }
    }

    func provider(_ id: String) -> CatalogProvider? {
        providers.first { $0.id == id }
    }

    /// 设置页 provider 候选：有端点、模型数多的优先。
    ///
    /// 「模型数多的优先」来自 `parse()` 里的加载期排序（有端点优先，
    /// 其余按模型数降序），**不是**在这里排的 —— 这里只做过滤与截断。
    ///
    /// ⚠️ 上限 `PROVIDER_PICKER_MAX` 是**唯一来源**（ProviderPickerSlice.swift），
    /// 原来这里写死 `limit: Int = 40`，而界面标题报的是目录总家数（225）——
    /// 两个数字都真实，但讲的是不同的集合，标题却让人以为「225 家里随便挑」。
    /// 实测 199 家有端点，只列 40 家 ⇒ 159 家用户选不到，零披露（缺陷 #209）。
    /// 截断本身是合理的（第 40 家 33 个模型、第 41 家 32 个，正好在自然断点上），
    /// 所以要修的是标签，不是取消上限。披露走 `providerPickerSlice`。
    func popularProviders(limit: Int = PROVIDER_PICKER_MAX) -> [CatalogProvider] {
        Array(providers.filter { !($0.api?.isEmpty ?? true) }.prefix(limit))
    }

    /// 选择器完整度披露所需的两个数。**纯函数在 ProviderPickerSlice.swift**，
    /// 这里只负责把目录的真实数字交给它。
    var providerPickerCoverage: ProviderPickerSlice {
        providerPickerSlice(
            total: providers.count,
            withEndpoint: providers.filter { !($0.api?.isEmpty ?? true) }.count
        )
    }
}
