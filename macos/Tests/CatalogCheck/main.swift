// CatalogCheck — models.dev 目录层的检查。
//
// 【为什么单独一个程序，而不是并进 ContractCheck】
// ContractCheck 拿**引擎真实输出**喂**客户端真实模型**，管的是跨进程契约。
// 这里管的是纯客户端内部的两个缺陷，性质不同：
//   P0-1  `ModelCatalog.parse()` 持 `NSLock` 后调 `parseInto()` 再取同一把
//         **非递归**锁 ⇒ 永久自死锁。触发条件是「无 Application Support 缓存
//         + bundle 里有 models-dev.json」，也就是**打包后的 .app**。
//         `swift run` 走不到这条分支（Bundle 无资源，提前 return），
//         所以它在开发期**完全测不出来**，而打包版 AI 100% 永久不可用。
//   P0-2  快照是**扁平键**（context / cost_in / cost_out），解析器读**嵌套**
//         （limit{} / cost{}）⇒ 225 个 provider 的上下文窗口与成本全为 nil。
//
// P0-1 的检查必须带**看门狗**：死锁的表现是「永远不返回」，不是「返回错的值」。
// 普通断言等不到结果，只能自己超时。macOS 没有 timeout(1)，所以这里用
// DispatchQueue + 主线程 runloop 实现。
//
// 【跑法】scripts/catalog-check.sh

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
    NSError(domain: "catalog", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
}

// MARK: - 0. 找到真实快照

// 优先用仓内那份真快照（1.2MB，225 个 provider）——这正是打包时被读的那份。
let snapshotURLs = [
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // CatalogCheck
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <pkg>
        .appendingPathComponent("Resources/models-dev.json"),
]

guard let snapshot = snapshotURLs.first.flatMap({ try? Data(contentsOf: $0) }),
      !snapshot.isEmpty else {
    print("✗ 读不到 Resources/models-dev.json，检查无法进行。")
    exit(2)
}
let snapshotSize = snapshot.count

print("【0】快照 \(snapshotSize / 1024)KB")

// MARK: - 1. P0-1：解析必须是纯函数，且不能自死锁

print("【1】ModelCatalog 不得自死锁（P0-1，打包版 AI 永久不可用的根因）")
do {
    // 1a. 纯函数存在且可独立调用 —— 解析与加锁物理分离，自死锁就写不出来。
    check("parseCatalog 是可独立调用的纯函数（不加锁、不碰全局状态）") {
        let providers = parseCatalog(data: snapshot)
        guard !providers.isEmpty else {
            throw fail("解析出 0 个 provider，测试前提不成立")
        }
        return "\(providers.count) 个 provider"
    }

    // 1b. 看门狗：真去构造 ModelCatalog.shared，10 秒内拿不到就算死锁。
    //     这是唯一能证明「不再死锁」的检查 —— 死锁不是返回值，是不返回。
    check("ModelCatalog.shared 在 10 秒内完成加载（真死锁会挂在这里）") {
        let done = DispatchSemaphore(value: 0)
        let box = ResultBox()
        DispatchQueue.global(qos: .userInitiated).async {
            // 走「解析 → 加锁赋值 → 读出」的完整路径，但绕开磁盘与网络
            // （见 init(snapshotOnly:) 的注释）。真实 .app 里正是这条路径死锁。
            let cat = ModelCatalog(snapshotOnly: snapshot)
            box.value = cat.providers
            done.signal()
        }
        guard done.wait(timeout: .now() + 10) == .success else {
            throw fail("10 秒仍未返回 —— 自死锁复现了（原实现持 NSLock 后再取同一把锁）")
        }
        guard let got = box.value, !got.isEmpty else {
            throw fail("返回了空目录，方向不对（这是另一个问题，不是死锁）")
        }
        return "10 秒内返回 \(got.count) 个 provider"
    }
}

// MARK: - 2. P0-2：扁平键必须读得到

print("【2】上下文窗口与成本必须读得出来（P0-2，原实现全为 nil）")
do {
    let providers = parseCatalog(data: snapshot)
    let allModels = providers.flatMap { p in p.models.map { (p.id, $0) } }

    check("快照规模符合前提（否则下面的断言是空转）") {
        guard providers.count > 200 else {
            throw fail("只有 \(providers.count) 个 provider，快照不对，断言会空转")
        }
        guard allModels.count > 500 else {
            throw fail("只有 \(allModels.count) 个模型，快照不对")
        }
        return "\(providers.count) provider / \(allModels.count) 模型"
    }

    check("contextTokens 不再全为 nil（读的是嵌套 limit{}，实际是扁平 context）") {
        let withCtx = allModels.filter { $0.1.contextTokens != nil }
        // 真的「没有上下文窗口」是极少数（本地小模型可能不报）。
        // 判定用比例而不是「必须全有」：后者在快照更新后可能假红。
        let ratio = Double(withCtx.count) / Double(allModels.count)
        guard ratio > 0.5 else {
            throw fail("只有 \(withCtx.count)/\(allModels.count) 有 contextTokens，解析仍在读错形状")
        }
        let sample = withCtx.first.map { "\($0.0)/\($0.1.id) ctx=\($0.1.contextTokens!)" } ?? ""
        return String(format: "%.0f%% 有值（%d/%d），样例 %@", ratio * 100, withCtx.count, allModels.count, sample)
    }

    check("outputTokens 不再全为 nil") {
        let withOut = allModels.filter { $0.1.outputTokens != nil }
        let ratio = Double(withOut.count) / Double(allModels.count)
        guard ratio > 0.5 else {
            throw fail("只有 \(withOut.count)/\(allModels.count) 有 outputTokens")
        }
        return String(format: "%.0f%% 有值（%d/%d）", ratio * 100, withOut.count, allModels.count)
    }

    check("成本读得到（读的是嵌套 cost{}，实际是扁平 cost_in / cost_out）") {
        let withCost = allModels.filter { $0.1.costInputPerMTok != nil || $0.1.costOutputPerMTok != nil }
        let ratio = Double(withCost.count) / Double(allModels.count)
        guard ratio > 0.2 else {
            throw fail("只有 \(withCost.count)/\(allModels.count) 有成本")
        }
        let s = withCost.first.map { "\($0.1.id) in=\($0.1.costInputPerMTok ?? -1) out=\($0.1.costOutputPerMTok ?? -1)" } ?? ""
        return String(format: "%.0f%% 有值（%d/%d），样例 %@", ratio * 100, withCost.count, allModels.count, s)
    }

    // 嵌套形状必须仍然兼容：models.dev 线上格式若改回嵌套，不能又变成全 nil。
    check("嵌套形状仍兼容（线上格式若改回 limit{}/cost{} 不能又全 nil）") {
        let nested = """
        {"acme":{"name":"acme","api":"https://x","models":{
          "m1":{"name":"M1","tool_call":true,"limit":{"context":128000,"output":8192},
                "cost":{"input":3.0,"output":15.0}}}}}
        """
        guard let ps = parseCatalog(data: Data(nested.utf8)).first,
              let m = ps.models.first else {
            throw fail("嵌套快照解析不出 provider")
        }
        guard m.contextTokens == 128000, m.outputTokens == 8192,
              m.contextTokens != nil, m.costInputPerMTok == 3.0, m.costOutputPerMTok == 15.0 else {
            throw fail("嵌套形状读不出来：ctx=\(String(describing: m.contextTokens)) " +
                       "in=\(String(describing: m.costInputPerMTok))")
        }
        return "limit{}/cost{} 与 context/cost_in 两种形状都读得出"
    }

    check("两种形状混在同一个快照里也能各取所长") {
        let mixed = """
        {"acme":{"api":"https://x","models":{
          "flat":{"context":1000,"cost_in":1.0},
          "nested":{"limit":{"context":2000},"cost":{"output":2.0}}}}}
        """
        guard let ps = parseCatalog(data: Data(mixed.utf8)).first else {
            throw fail("解析不出 provider")
        }
        let flat = ps.models.first { $0.id == "flat" }
        let nested = ps.models.first { $0.id == "nested" }
        guard flat?.contextTokens == 1000, flat?.costInputPerMTok == 1.0,
              nested?.contextTokens == 2000, nested?.costOutputPerMTok == 2.0 else {
            throw fail("混排时读错了：flat=\(String(describing: flat)) nested=\(String(describing: nested))")
        }
        return "扁平项与嵌套项在同一快照里各取所长"
    }
}

// MARK: - 3. 纯函数的其他性质

print("【3】纯函数的其他性质")
do {
    check("畸形输入返回空目录而不是崩溃（fail-open 不能变成 fail-crash）") {
        for (label, raw) in [("非 JSON", "{not json"), ("顶层是数组", "[]"),
                             ("空对象", "{}"), ("provider 没有 models", "{\"a\":{}}")] {
            let got = parseCatalog(data: Data(raw.utf8))
            guard got.isEmpty else { throw fail("\(label) 却解析出 \(got.count) 个 provider") }
        }
        return "4 种畸形输入全部安全降级为空"
    }

    check("同一个 Data 解析两次结果相同（纯函数，没有隐藏状态）") {
        let a = parseCatalog(data: snapshot)
        let b = parseCatalog(data: snapshot)
        guard a.count == b.count,
              a.map(\.id) == b.map(\.id),
              a.flatMap(\.models).count == b.flatMap(\.models).count else {
            throw fail("两次解析结果不同，说明有隐藏状态")
        }
        return "\(a.count) provider 稳定"
    }

    check("有 api 端点的 provider 排在前面（通道组装靠这个顺序）") {
        let ps = parseCatalog(data: snapshot)
        let withApi = ps.filter { !($0.api?.isEmpty ?? true) }.count
        guard withApi > 0 else { throw fail("一个带端点的都没有") }
        // 断言方式：第一个「无端点」出现之后不应再有「带端点」的
        let firstNoApi = ps.firstIndex { $0.api?.isEmpty ?? true } ?? ps.count
        let after = ps[firstNoApi...].filter { !($0.api?.isEmpty ?? true) }
        guard after.isEmpty else {
            throw fail("第 \(firstNoApi) 个无端点之后还有 \(after.count) 个带端点的")
        }
        return "\(withApi) 个带端点，全部排在前面"
    }
}

// MARK: - 4. Provider 选择器的完整度（缺陷 #209）

print("")
print("【4】Provider 选择器：标题的总家数 ≠ 列表的条数（#209）")

do {
    // 真实快照数字（Resources/models-dev.json，实测）：
    //   目录 225 家 → 有可用端点 199 家 → 列表只列前 40 家
    // 被砍掉的 159 家里模型数最多的 32 个（第 41 家 nearai），
    // 而第 40 家 opencode-go 有 33 个 —— 上限卡在自然断点上，**上限本身是对的**。
    // 缺陷只在于标题写「225 家」而列表给 40 家，零披露。
    //
    // ⚠️ 数据必须走 `parseCatalog(data:)`（纯函数），**不能**用
    // `ModelCatalog.shared` —— 那是 1b 组用来验死锁的单例，此刻还没加载完。
    // 第一版就是这么写的，结果 `shown=0 withEndpoint=0`，而我那条
    // 「列表条数与披露对得上」的检查在 0 == 0 上**白转着变绿** ——
    // 空数据上的相等断言是最容易自我欺骗的一种。
    let all = parseCatalog(data: snapshot)
    let withApi = all.filter { !($0.api?.isEmpty ?? true) }
    let cov = providerPickerSlice(total: all.count, withEndpoint: withApi.count)
    // 前提：这份快照真的被砍过。下面每一条都在这个前提之下，
    // 快照一旦变小/变大，先在这里报出来，而不是让后面空转。
    guard cov.cut else {
        print("✗ 快照只有 \(cov.withEndpoint) 家有端点，#209 的前提不成立（上限 \(PROVIDER_PICKER_MAX)）")
        exit(2)
    }

    check("披露必须同时给出两个口径（目录总数 / 有端点数）") {
        guard cov.shown == PROVIDER_PICKER_MAX, cov.withEndpoint > cov.shown else {
            throw fail("口径不对：shown=\(cov.shown) withEndpoint=\(cov.withEndpoint)")
        }
        guard let note = cov.note else { throw fail("真实快照竟然没触发披露") }
        guard note.contains("共 \(cov.withEndpoint) 家") else {
            throw fail("披露里没有写出有端点的总家数：\(note)")
        }
        guard note.contains("前 \(cov.shown) 家") else {
            throw fail("披露里没有写出实际列了几家：\(note)")
        }
        return note
    }

    check("披露必须给出可执行的下一步，不能只说「其余略」") {
        // 设置页本来就有「Base URL 覆盖」输入框 ⇒ 被砍的那些家**是能用的**。
        // 只报数字不报路径，等于把一个可用功能说成缺失。
        guard let note = cov.note, note.contains("Base URL 覆盖") else {
            throw fail("没有告诉用户怎么够到被砍掉的那些家：\(cov.note ?? "nil")")
        }
        return "指到「Base URL 覆盖」"
    }

    check("PROVIDER_PICKER_MAX 是唯一来源：popularProviders 的默认上限不许另写一个 40") {
        guard PROVIDER_PICKER_MAX == 40 else { throw fail("常量变了：\(PROVIDER_PICKER_MAX)") }
        // 对照：默认参数必须引用这个常量，否则上限改成 7 也不会有人发现
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CatalogCheck
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // <pkg>
            .appendingPathComponent("Sources/deepDolphin/ModelsDev.swift"), encoding: .utf8)
        guard src.contains("limit: Int = PROVIDER_PICKER_MAX") else {
            throw fail("popularProviders 的默认值不是那个常量")
        }
        return "唯一来源"
    }

    check("真实目录：列表条数必须等于披露的条数（别拿全集数冒充列表数）") {
        let listed = Array(withApi.prefix(PROVIDER_PICKER_MAX))
        guard listed.count == cov.shown else {
            throw fail("实际能列 \(listed.count) 家，披露说 \(cov.shown) 家")
        }
        // 列出来的每一家都必须真的有端点（有端点过滤失效 ⇒ 会有 0 端点的条目混进来）
        for p in listed where (p.api?.isEmpty ?? true) {
            throw fail("列表里有没端点的 provider：\(p.id)")
        }
        return "\(listed.count)/\(cov.withEndpoint) 家有端点，全部列得出且都有端点"
    }

    check("上限卡在自然断点上（这决定了该不该保留上限，而不是无脑取消）") {
        // 第 40 家与第 41 家的模型数差得少 ⇒ 上限砍掉的都是「更少模型」的那些。
        // 如果哪天排序变了、这个前提不成立，提示词里那句「上限合理」就是假的。
        let n40 = withApi[PROVIDER_PICKER_MAX - 1].models.count
        let n41 = withApi[PROVIDER_PICKER_MAX].models.count
        guard n40 >= n41 else {
            throw fail("排序不是模型数降序：第 \(PROVIDER_PICKER_MAX) 家 \(n40) 个模型 < " +
                       "第 \(PROVIDER_PICKER_MAX + 1) 家 \(n41) 个 ⇒ 上限不再卡在断点上")
        }
        return "第 \(PROVIDER_PICKER_MAX) 家 \(n40) 模型 ≥ 第 \(PROVIDER_PICKER_MAX + 1) 家 \(n41) 模型"
    }

    check("不剩时不许造披露") {
        let s = providerPickerSlice(total: 225, withEndpoint: 12)
        guard !s.cut, s.shown == 12, s.note == nil else {
            throw fail("12 < 上限却报了截断：\(s.note ?? "nil")")
        }
        return "沉默是对的"
    }

    check("正好等于上限：不许造披露（否则上面那条没有判别力）") {
        let s = providerPickerSlice(total: 40, withEndpoint: PROVIDER_PICKER_MAX)
        guard !s.cut, s.note == nil else { throw fail("正好 \(PROVIDER_PICKER_MAX) 家却报了截断") }
        return "\(PROVIDER_PICKER_MAX) 家列全"
    }

    check("没有端点的那些家数也要说（225 与 199 不是同一个数）") {
        let s2 = providerPickerSlice(total: 225, withEndpoint: 199)
        guard let n2 = s2.note, n2.contains("目录共 225 家") else {
            throw fail("披露没有区分「目录总数」与「有端点数」：\(s2.note ?? "nil")")
        }
        return "两个口径都说了"
    }

    check("空目录：必须是沉默的 0") {
        let s = providerPickerSlice(total: 0, withEndpoint: 0)
        guard s.shown == 0, !s.cut, s.note == nil else {
            throw fail("空输入产出了：\(s.note ?? "nil")")
        }
        let neg = providerPickerSlice(total: -3, withEndpoint: -1)
        guard neg.total == 0, neg.withEndpoint == 0, neg.note == nil else {
            throw fail("负数输入产出了：\(neg.note ?? "nil")")
        }
        return "空/负都沉默"
    }

    check("limit 传 0 不许产出「只列前 0 家」这种自相矛盾的话") {
        let s = providerPickerSlice(total: 225, withEndpoint: 199, limit: 0)
        guard s.shown >= 1, let note = s.note, !note.contains("前 0 家") else {
            throw fail("limit=0 的输出自相矛盾：\(s.note ?? "nil")")
        }
        return "至少列一家"
    }
}

// MARK: - 汇总

print("")
if failures.isEmpty {
    print("✅ 目录检查通过：\(checks) 项")
    exit(0)
} else {
    print("❌ 目录检查失败：\(failures.count)/\(checks) 项")
    for f in failures { print("   · \(f)") }
    exit(1)
}

/// 看门狗与赋值之间的桥（避免在闭包里跨并发边界共享可变状态）
final class ResultBox: @unchecked Sendable {
    private var stored: [CatalogProvider]?
    private let lock = NSLock()
    var value: [CatalogProvider]? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}
