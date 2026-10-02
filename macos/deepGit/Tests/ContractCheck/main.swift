// main.swift — 客户端 ↔ 引擎契约检查。
//
// 【为什么存在】P0-1 是这样被抓住的：`AIClient.status(name:)` 按**裸 ProjectStatus**
// 解码，而引擎 CLI 恒返回 `{projects, summary, language}` envelope ——
// 100% 必现的 `DecodingError.keyNotFound: Key 'id' not found`，详情面板每次打开都崩。
//
// 那种缺陷靠人工审计发现不了、靠代码评审也挡不住：两边各自「看起来」都合理。
// 真正能挡住的只有一件事 —— **拿引擎的真实输出喂客户端的真实模型**。
//
// 【为什么不放在 SwiftPM test target】本包只有一个 executableTarget，
// 对它做 XCTest 需要处理 main 入口冲突。这里改成独立可执行：
//   swiftc Sources/deepGit/Models.swift Tests/ContractCheck/main.swift -o /tmp/cc
// 关键点：**直接编译真实的 Models.swift**，不复制一份到测试里 ——
// 复制的那份会与源文件漂移，测了等于没测。
//
// 【跑法】scripts/contract-check.sh（它负责建沙箱、造数据、调引擎、传 fixture 路径）

import Foundation

// MARK: - 结果收集

var failures: [String] = []
var checks = 0

func check(_ label: String, _ body: () throws -> String) {
    checks += 1
    do {
        let detail = try body()
        print("  ✓ \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    } catch {
        let msg = "  ✗ \(label)\n      \(error)"
        print(msg)
        failures.append("\(label): \(error)")
    }
}

func expectDecode<T: Decodable>(_ label: String, _ data: Data, as: T.Type) throws -> T {
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        // 解码失败时必须把**期望的键**说出来，否则「解码失败」本身没法定位。
        // 契约破坏最常见的表现就是引擎删了/改了一个键。
        let raw = String(data: data, encoding: .utf8) ?? ""
        let head = raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
        throw NSError(domain: "contract", code: 1, userInfo: [
            NSLocalizedDescriptionKey:
                "\(T.self) 解码失败：\(error)\n      引擎输出前 160 字节：\(head.isEmpty ? "<空>" : String(head))"
        ])
    }
}

func loadFixture(_ name: String) throws -> Data {
    try loadFixtureFile("\(name).json")
}

/// 读 fixture 目录下的任意文件（不加 .json 后缀）。
/// 用于非 JSON 的旁证文件，比如引擎的退出码 —— 那不是 JSON，
/// 但恰恰是 P0-2 成立的前提（"非 0 退出时 stdout 仍带 payload"）。
func loadFixtureFile(_ filename: String) throws -> Data {
    let dir = ProcessInfo.processInfo.environment["DG_FIXTURES"] ?? "."
    let path = "\(dir)/\(filename)"
    guard let d = FileManager.default.contents(atPath: path) else {
        throw NSError(domain: "contract", code: 2, userInfo: [NSLocalizedDescriptionKey:
            "读不到 fixture \(path)（应由 scripts/contract-check.sh 生成）"])
    }
    return d
}

/// 读 Sources/deepGit 下的源文件。
///
/// 用 `#filePath` 定位，不依赖环境变量 —— 与 ClientCheck / AgentCheck 同一路子。
/// 五个检查程序各自单独编译，所以这份助手只能各存一份。
func sourceText(_ name: String) throws -> String {
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ContractCheck
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <pkg>
    return try String(contentsOf: dir.appendingPathComponent("Sources/deepGit/\(name)"),
                      encoding: .utf8)
}

/// 从 Swift 源码里抓出 `executeTool` 的 case 名。
///
/// ⚠️ 这是**抓源码**不是跑代码，判据是拼法。
/// 之所以仍然值得：它比"跑一遍看会不会崩"早一步，
/// 而这一对清单漂移的表现恰恰是运行时的"未知工具"。
/// 比的是**集合**（不是顺序、不是条数），
/// 所以调整 case 顺序、增删空行都不会假红。
/// 局限要写明：改写成 `if name == "x"` 形式就抓不到了 ——
/// 那时这条会**静默空转**，所以下面配了「抓到 0 个就必须报错」的前提检查。
func toolCaseNames(in source: String) -> [String] {
    var out: [String] = []
    for line in source.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("case \"") else { continue }
        guard let q1 = t.firstIndex(of: "\""), let q2 = t[t.index(after: q1)...].firstIndex(of: "\"") else {
            continue
        }
        out.append(String(t[t.index(after: q1)..<q2]))
    }
    return out
}

func structError(_ msg: String) -> NSError {
    NSError(domain: "contract", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
}

/// 一组断言的**准备阶段**：里面的 `try` 抛了要变成一条失败记录，不能逃出去。
///
/// 为什么需要它：这一层原来直接用 `do { … }`，而组内第一句常是
/// `let env = try expectDecode(...)`。引擎改一个键名时它就抛，
/// 错误一路逃到顶层 ⇒ `Fatal error: Error raised at top level` ⇒ 进程 trap。
///
/// crash 也让构建失败，但**其余全部诊断一起丢了** ——
/// 而「引擎动了 JSON 键」恰恰是最需要一次看到所有受影响检查的场景。
/// 实测踩过：把 journal 披露退回条件性发，检查程序直接 trap，
/// 只看得到一句 keyNotFound，另外 30 多项一条都没报。
func require(_ label: String, _ body: () throws -> Void) {
    do {
        try body()
    } catch {
        checks += 1
        print("  ✗ \(label)\n      \(error)")
        failures.append("\(label): \(error)")
    }
}

// MARK: - 1. status --json → StatusEnvelope

print("【1】status --json → StatusEnvelope")
require("第 1 组的准备阶段", {
    let data = try loadFixture("status")
    check("envelope 解码") {
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        return "projects=\(env.projects.count) language=\(env.language ?? "<nil>")"
    }
    check("summary 含全部披露字段") {
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        guard let s = env.summary else {
            throw structError("summary 为 nil —— 引擎恒发 summary，客户端却解不出")
        }
        // 这些字段是 #144/#151/#155 逐条加上去的披露。少任何一个，
        // 客户端就只能把「追踪数」当「全量」显示。
        _ = s.listedProjects
        _ = s.failedProjects
        _ = s.repoBranchTotal
        _ = s.branchTruncatedProjects
        _ = s.branchUnknownProjects
        _ = s.degradedStores
        return "listed=\(s.listedProjects) failed=\(s.failedProjects) " +
               "repoBranchTotal=\(s.repoBranchTotal) unknown=\(s.branchUnknownProjects)"
    }
    check("ProjectStatus 含截断/总量字段") {
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        guard let p = env.projects.first else { throw structError("projects 为空") }
        // 引擎恒发这四个，客户端原实现一个都没建模
        _ = p.repoBranchCount
        _ = p.commitTypesTruncated
        _ = p.storeHealth
        _ = p.progress.entryCount
        _ = p.progress.entryCountTruncated
        _ = p.progress.entriesKept
        return "repoBranchCount=\(p.repoBranchCount) " +
               "commitTypesTruncated=\(p.commitTypesTruncated) " +
               "entryCount=\(p.progress.entryCount) kept=\(p.progress.entriesKept)"
    }
    // P0-1 的直接守卫：客户端 status(name:) 走的就是这个 envelope
    check("status(name:) 用的 envelope 形状可解（不回退裸 ProjectStatus）") {
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        guard !env.projects.isEmpty else { throw structError("projects 为空") }
        let one = env.projects[0]
        guard one.name == "ok" else {
            throw structError("期望名为 ok 的项目，实际是 \(one.name)")
        }
        return "取到 \(one.name)（id=\(one.id)）"
    }
    // ── 「这条项目该显示哪个分支」这条规则的唯一出处 ──
    //
    // ⚠️ 这条规则原来被**抄了三遍**（BarView / BoardView 各一个私有 computed
    // property，PanelView 内联在 else if 里），字面相同、位置不同。
    // 于是改规则要找三处，漏一处就出现「菜单栏说 feat、侧栏说 main」——
    // 而两个界面同屏出现，用户会以为是两个不同的真相。
    // 现在规则在 `ProjectStatus.primaryBranch`（模型层），下面卡三件事：
    //   1. 行为对不对（用**真实引擎 fixture**，不是造出来的数据）
    //   2. 与引擎自己声明的 currentBranch 名字是否自洽（交叉验证）
    //   3. 视图里不许再出现第二份推导（结构卡，见下面那条 check）
    check("时间窗真的改变项目集合（设计稿筛选行 · 真 fixture）") {
        // 「近 7 天 / 近 30 天」是**视图窗口**，不是引擎的档位线（3/14 天）。
        // 它与 `BranchStatus.status` 回答的是两个问题，所以放在模型层
        // `ProjectStatus.updatedWithin(days:)` 是对的。
        //
        // 用真 fixture 验，而不是造 ProjectStatus（它有 30+ 个必填字段，
        // 造出来的数据只证明判据能跑，不证明判据对）。
        // 时间窗类判据必须用**全量**项目 fixture：单项目（只有 ok）里没有「新旧对比」，判据只能空转。
        let data = try loadFixture("status_all")
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        let readables = env.projects.filter { !$0.isUnreadable }
        guard !readables.isEmpty else { throw structError("fixture 里没有可读项目") }

        // 无分支记录 / 更新时间读不出来的项目，必须在任何窗口里都保留 ——
        // 滤掉它等于对用户说「它不在近 7 天内」，而真相是「我们不知道」。
        for p in env.projects where p.daysSinceLastCommit == nil {
            guard p.updatedWithin(days: 7) else {
                throw structError("更新时间读不出来的项目被「近 7 天」筛掉了")
            }
        }
        // 「全量」不许按时间筛：任何项目都必须在。
        for p in env.projects where !p.updatedWithin(days: nil) {
            throw structError("\(p.name) 在全量档位被筛掉了 ⇒ 该档位不该有时间窗")
        }
        // 档位必须真的**分出不同结果**，否则筛选是摆设。
        //
        // ⚠️ 这里原来有个软逃生口：「沙箱里项目可能全都新鲜，那就分不出来」
        //   然后 `return "窗口正确但分不出差异"` —— 全绿通过。
        // 那个口子正是本缺陷能活下来的原因：真数据里 3 个仓库全都没远端、
        // `branches` 全空，旧实现对每个项目都走「没有分支记录 → 保留」，
        // 于是 `inD7 == 全量`，而判据因为「数据都新鲜」主动放过了它。
        // **判据在自己覆盖不到的数据上放行，等于给缺陷发通行证。**
        // 现在改成硬断言：分不出差异就是 fixture 不合格，必须先造出陈旧项目。
        let inD30 = readables.filter { $0.updatedWithin(days: 30) }
        let inD7 = readables.filter { $0.updatedWithin(days: 7) }
        guard inD7.count <= inD30.count else {
            throw structError("近 7 天收下的(\(inD7.count))比近 30 天(\(inD30.count))还多 ⇒ 档位是反的")
        }
        guard inD7.count < readables.count else {
            throw structError("近 7 天收下了全部 \(readables.count) 个项目 ⇒ 它没在筛。"
                + "若 fixture 里确实全新鲜，先造一个陈旧项目（lastCommitAt 拉到 30 天前）再验 —— "
                + "不许用「数据如此」把自己放过去")
        }
        return "近 7 天 \(inD7.count) / 近 30 天 \(inD30.count) / 全量 \(readables.count) —— 窗口真的分档"
    }

    // 上面那条已经能抓住「筛选没在筛」，但它是在**整体**上比较三个集合；
    // 缺陷的具体形状是「判定挂在追踪分支数组上，无远端的仓库恒判保留」。
    // 下面这条直接钉住那个形状：只要 `lastCommitAt` 说得清多老，就不许被放过。
    check("时间窗不许挂在追踪分支数组上（无远端仓库的真实形状）") {
        // 时间窗类判据必须用**全量**项目 fixture：单项目（只有 ok）里没有「新旧对比」，判据只能空转。
        let data = try loadFixture("status_all")
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        let readables = env.projects.filter { !$0.isUnreadable }

        // 老实现的失效条件正是「branches 为空 + lastCommitAt 很旧」：
        // 实测三个本地仓库全部落在这个形状里。找出它们，断言必须被筛掉。
        let emptyBranchArray = readables.filter { $0.branches.isEmpty }
        guard !emptyBranchArray.isEmpty else {
            throw structError("fixture 里没有 branches 为空的项目 ⇒ 这条判据覆盖不到真形状，"
                + "请在沙箱里留一个无远端的本地仓库")
        }
        for p in emptyBranchArray {
            guard let age = p.daysSinceLastCommit else { continue }  // 读不出来 → 本就该保留
            if age > 7 {
                guard !p.updatedWithin(days: 7) else {
                    throw structError("\(p.name)：branches 为空、最后提交 \(age) 天前，"
                        + "却被「近 7 天」收下了 ⇒ 判定退化成了「没有分支记录就保留」")
                }
            }
            if age > 30 {
                guard !p.updatedWithin(days: 30) else {
                    throw structError("\(p.name)：\(age) 天没提交，却被「近 30 天」收下了")
                }
            }
        }

        // 客户端与引擎必须是同一个口径：引擎用 `lastCommitAt` 算
        // active7d/active30d（dashboard.cj:213-226），若客户端用别的依据，
        // 筛选行分出来的集合会和 KPI 副说明里的活跃数自相矛盾。
        // 交叉验证：客户端的 7 天窗口计数 == 引擎的 active7d。
        guard let dash = try? expectDecode("dashboard", loadFixture("dashboard"), as: Dashboard.self) else {
            return "无 dashboard fixture，跳过交叉验证"
        }
        let mine = readables.filter { $0.updatedWithin(days: 7) }.count
        guard mine == dash.projects.active7d else {
            throw structError("客户端「近 7 天」收下 \(mine) 个，引擎 active7d 是 \(dash.projects.active7d) "
                + "⇒ 两边不是同一个口径")
        }
        return "\(emptyBranchArray.count) 个无追踪分支的项目按 lastCommitAt 正确分档；"
            + "与引擎 active7d(\(dash.projects.active7d)) 一致"
    }

    // 上面那条是**症状**判据。这条是**病因**判据：把整族一起钉住。
    //
    // Swift 合成的 `init(from:)` 对「带初始值的不可变存储属性」直接跳过：
    //     let x: Int? = nil        // 编译期 warning，运行时永远是 nil
    // 写这种声明的人以为「默认值 = 缺键时的兜底」，实际是「默认值 = 永远的值」。
    // 本项目有 5 个字段这么写（BranchStatus 四个 + ProjectStatus.lastCommitAt），
    // 引擎恒发也解不出来，其中 lastCommitAt 直接让时间窗筛选变成死控件。
    //
    // 为什么必须单独立一条：原判据是**按字段点名**的（测了 head / headSubject /
    // providerLabel），而那三个恰好不是这么写的 —— 于是判据全绿，
    // 同一文件里另外 4 个死键从头到尾没人看见。
    // 「点名式」判据只覆盖被点名的人；这条改成**按写法**覆盖整族。
    check("带默认值的可选字段必须真的解得出来（let + 初值 = 永不解码）") {
        // 造一份**键齐全**的 JSON 直接验解码通路。
        // 这里造数据是正当的：断言的对象恰恰是「解码这一步」，
        // 而不是「引擎会填什么值」——后者另有真 fixture 在管。
        let entryJSON = """
        {"id":"e1","at":"2026-10-01T10:00:00+08:00","mode":"update","branch":"main",
         "summary":"s","providerLabel":"规则","commitCount":6,
         "commitCountScope":"session","commitCountTruncated":true,
         "repoBranchCount":16,"branchCountTruncated":true}
        """
        let b = try JSONDecoder().decode(JournalEntry.self, from: Data(entryJSON.utf8))
        var missed: [String] = []
        if b.commitCountScope == nil { missed.append("JournalEntry.commitCountScope") }
        if b.commitCountTruncated == nil { missed.append("JournalEntry.commitCountTruncated") }
        if b.repoBranchCount == nil { missed.append("JournalEntry.repoBranchCount") }
        if b.branchCountTruncated == nil { missed.append("JournalEntry.branchCountTruncated") }
        guard missed.isEmpty else {
            throw structError("JSON 里有键，解出来却是 nil：\(missed.joined(separator: ", "))"
                + " ⇒ 声明成了 `let x: T? = nil`，Swift 合成解码器会跳过它（该写 var）")
        }
        // 不许只是「非 nil」——值也要对，否则「解出来了但接错键」照样蒙混过关。
        guard b.commitCountScope == "session" && b.commitCountTruncated == true
                && b.repoBranchCount == 16 && b.branchCountTruncated == true else {
            throw structError("解出来了但值不对：scope=\(b.commitCountScope ?? "nil") "
                + "truncated=\(String(describing: b.commitCountTruncated)) "
                + "repoBranchCount=\(String(describing: b.repoBranchCount))")
        }

        // 同样地验 ProjectStatus.lastCommitAt，并**顺带用真 fixture 交叉验证**：
        // 引擎对每个 git 项目都发 lastCommitAt，解出来却全是 nil 就是没接上。
        let env = try expectDecode("status_all", loadFixture("status_all"), as: StatusEnvelope.self)
        let gitProjects = env.projects.filter { $0.isGit }
        guard !gitProjects.isEmpty else { throw structError("fixture 里没有 git 项目") }
        let noTime = gitProjects.filter { $0.lastCommitAt == nil }
        guard noTime.isEmpty else {
            throw structError("\(noTime.count) 个 git 项目的 lastCommitAt 解出来是 nil"
                + "（引擎恒发）⇒ 字段没接上，时间窗会静默退化成「全保留」")
        }
        // 反向：非 git 项目本来就没有提交时间。
        // ⚠️ 引擎对这种情况给的是**空串** `lastCommitAt: ""` 而不是缺键 ——
        //   只判 `== nil` 会误报（我第一版就这么写的，红了才发现自己猜错了形状）。
        // 真正要保证的是：无论空串还是缺键，都必须落到「读不出来」，
        // 绝不能被当成「0 天前」而混进时间窗。
        for p in env.projects where !p.isGit {
            guard p.daysSinceLastCommit == nil else {
                throw structError("\(p.name) 是非 git 项目，却算出 daysSinceLastCommit="
                    + "\(p.daysSinceLastCommit!)（lastCommitAt=\(p.lastCommitAt ?? "<缺键>"))"
                    + " ⇒ 读不出来被当成了具体天数")
            }
        }
        // 空串在非 git 项目上是常态，但也不能让它污染 git 项目的判读：
        // git 项目若解出空串，同样要落到「读不出来」而不是 0。
        for p in gitProjects where (p.lastCommitAt ?? "").isEmpty && p.daysSinceLastCommit != nil {
            throw structError("\(p.name) 的 lastCommitAt 是空串，却算出了天数")
        }
        return "5 个「默认值兜底」字段全部解码成功（scope/truncated/repoBranchCount/branchCountTruncated/lastCommitAt）；"
            + "\(gitProjects.count) 个 git 项目的提交时间齐全，非 git 项目为 nil"
    }

    check("primaryBranch 命中引擎标记的当前分支（真 fixture）") {
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        // 只在真有「标记为当前的分支」的项目上断言 —— 那是能交叉验证的场景。
        // 没有 isCurrent 时规则退化成「第一个分支」，那只是兜底不是事实，
        // 不该拿它去和引擎声明的名字对账（对不上是正常的）。
        let withCurrent = env.projects.filter { $0.branches.contains { $0.isCurrent } }
        guard !withCurrent.isEmpty else {
            throw structError("fixture 里没有任何带 isCurrent 分支的项目 —— " +
                "要么沙箱没造成功，要么引擎不再发 isCurrent，判据需要重新想")
        }
        for p in withCurrent {
            guard let primary = p.primaryBranch else {
                throw structError("\(p.name) 有 isCurrent 分支，primaryBranch 却是 nil")
            }
            guard primary.isCurrent else {
                throw structError("\(p.name) 选中的 \(primary.name) 不是 isCurrent")
            }
            // 交叉验证：引擎声明的 currentBranch 名字必须就是这一条。
            // 客户端从没读这个字段就自己挑了一条 ⇒ 两边对不上且用户无从察觉。
            guard primary.name == p.currentBranch else {
                throw structError("\(p.name)：primaryBranch=\(primary.name)，" +
                    "但引擎声明 currentBranch=\(p.currentBranch)。" +
                    "两边不一致 ⇒ 界面上显示的分支和引擎说的是同一个分支吗？")
            }
        }
        return "\(withCurrent.count) 个项目的 primaryBranch 与引擎声明的名字一致"
    }
    check("primaryBranch 的兜底与空数组都对（真 fixture）") {
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        for p in env.projects {
            if p.branches.isEmpty {
                guard p.primaryBranch == nil else {
                    throw structError("\(p.name) 没有分支，primaryBranch 却非 nil")
                }
                continue
            }
            // 有分支但没有一个标了 isCurrent ⇒ 必须退回第一个（不能 nil）
            if !p.branches.contains(where: { $0.isCurrent }) {
                guard let primary = p.primaryBranch else {
                    throw structError("\(p.name) 有 \(p.branches.count) 个分支却取不到主分支")
                }
                guard primary.name == p.branches[0].name else {
                    throw structError("\(p.name) 无 isCurrent 时应退回第一个" +
                        "（\(p.branches[0].name)），实际取了 \(primary.name)")
                }
            }
        }
        return "\(env.projects.count) 个项目：空数组→nil / 无 isCurrent→第一个"
    }
})

// MARK: - 2. 错误项目：-1 三态必须原样到达客户端

print("【2】采集失败项目 → -1 三态不得被渲染成 0")
require("第 2 组的准备阶段", {
    let data = try loadFixture("status_error")
    check("错误桩解码") {
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        guard let p = env.projects.first(where: { $0.error != nil }) else {
            throw structError("没有带 error 的项目 —— 沙箱可能没造成功")
        }
        return "\(p.name): \(p.error ?? "")"
    }
    check("userDirtyCount 是 -1 而不是 0") {
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        guard let p = env.projects.first(where: { $0.error != nil }) else {
            throw structError("没有带 error 的项目")
        }
        guard p.userDirtyCount == -1 else {
            throw structError("userDirtyCount=\(p.userDirtyCount)，期望 -1。" +
                "报 0 等于替用户断言「工作区干净」，而真相是整个仓库读不出来")
        }
        return "\(p.userDirtyCount)"
    }
    check("pulseLine 披露「读不出来」而不是静默为空") {
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        guard let p = env.projects.first(where: { $0.error != nil }) else {
            throw structError("没有带 error 的项目")
        }
        let line = p.pulseLine ?? ""
        guard line.contains("读不出来") else {
            throw structError("pulseLine=\"\(line)\"，期望包含「读不出来」。" +
                "为空会被 UI 渲染成「没有未提交改动」—— 把无知说成事实")
        }
        return line
    }
    check("branchScopeLine 在 repoBranchCount=-1 时披露未知") {
        let env = try expectDecode("status", data, as: StatusEnvelope.self)
        guard let p = env.projects.first(where: { $0.error != nil }) else {
            throw structError("没有带 error 的项目")
        }
        guard p.branchScopeLine.contains("读不出来") else {
            throw structError("branchScopeLine=\"\(p.branchScopeLine)\"，期望披露未知")
        }
        return p.branchScopeLine
    }
})

// MARK: - 3. milestone list --json

print("【3】milestone list --json → MilestonesEnvelope")
require("第 3 组的准备阶段", {
    let data = try loadFixture("milestones")
    check("envelope 解码（含披露字段）") {
        let env = try expectDecode("milestones", data, as: MilestonesEnvelope.self)
        return "milestones=\(env.milestones.count) storeHealth=\(env.storeHealth) " +
               "readCount=\(env.readCount) excludedDisabled=\(env.excludedDisabled)"
    }
    check("条目含 gitReadable / commitsSinceReadable") {
        let env = try expectDecode("milestones", data, as: MilestonesEnvelope.self)
        guard let m = env.milestones.first else { throw structError("milestones 为空") }
        // 引擎恒发这两个，客户端原实现一个都没建模
        _ = m.gitReadable
        _ = m.commitsSinceReadable
        return "gitReadable=\(m.gitReadable) commitsSince=\(m.commitsSince) readable=\(m.commitsSinceReadable)"
    }
    check("commitsSince 读不出来时文案必须说读不出来") {
        let env = try expectDecode("milestones", data, as: MilestonesEnvelope.self)
        // 沙箱里有一个指向已删除路径的里程碑：commitsSince 应为 -1
        guard let unknown = env.milestones.first(where: { !$0.commitsSinceReadable })
                ?? env.milestones.first else {
            throw structError("没有可断言的里程碑")
        }
        let text = unknown.commitsText
        if unknown.commitsSinceReadable {
            return text
        }
        guard text.contains("读不出来") else {
            throw structError("commitsText=\"\(text)\"，commitsSince=\(unknown.commitsSince) " +
                "时必须说读不出来，不能显示 0")
        }
        return text
    }
})

// MARK: - 4. 里程碑 unknown 不得渲染成「进行中」

print("【4】里程碑 status=unknown → 不得断言为「进行中」")
require("第 4 组的准备阶段", {
    let data = try loadFixture("milestones")
    check("statusLabel 识别 unknown") {
        let env = try expectDecode("milestones", data, as: MilestonesEnvelope.self)
        guard let m = env.milestones.first else { throw structError("milestones 为空") }
        // 即使沙箱里没有真的 unknown 条目，也要验证判定逻辑本身：
        // 构造一个 status=unknown 的副本，确认它落到「无法核验」而不是「进行中」。
        let probe = MilestoneItem(
            projectId: "p", projectName: "p", name: "n", description: "",
            status: "unknown", targetDate: "", daysToTarget: -1, overdue: false,
            tag: "", tagName: "", tagReached: false,
            commitsSince: -1, commitsSinceReadable: false, gitReadable: false,
            createdAt: "", completedAt: "", unverifiedReason: "仓库读不出来（git rev-parse 失败）"
        )
        guard probe.statusLabel == "无法核验" else {
            throw structError("status=unknown 的 statusLabel=\"\(probe.statusLabel)\"，期望「无法核验」")
        }
        guard !probe.isUnknown == false else {
            throw structError("isUnknown 判定失效")
        }
        return "沙箱里的 status=\(m.status) → 「\(m.statusLabel)」"
    }
})

// MARK: - 5. docs --json

print("【5】docs --json → DocsEnvelope")
require("第 5 组的准备阶段", {
    let data = try loadFixture("docs")
    check("envelope 解码（含 unreadable）") {
        let env = try expectDecode("docs", data, as: DocsEnvelope.self)
        // unreadable 恒发（空时是空数组）。客户端原实现没建模，
        // 于是读失败的文档只是从数组里消失，用户以为项目没有该文档。
        return "docs=\(env.docs.count) unreadable=\(env.unreadable)"
    }
})

// MARK: - 6. dashboard --json

print("【6】dashboard --json → Dashboard")
require("第 6 组的准备阶段", {
    let data = try loadFixture("dashboard")
    check("envelope 解码") {
        let d = try expectDecode("dashboard", data, as: Dashboard.self)
        return "projects=\(d.projects.total)/\(d.projects.listed) " +
               "milestones=\(d.milestones.counts.open) unknown=\(d.milestones.counts.unknown)"
    }
    check("milestones.counts 含 unknown / storeHealth / degraded") {
        let d = try expectDecode("dashboard", data, as: Dashboard.self)
        let c = d.milestones.counts
        // #152/#158 加的披露：unknown 单列 + 存储健康 + 停用/孤儿计数
        _ = c.unknown
        _ = c.storeHealth
        _ = c.degraded
        _ = c.readCount
        _ = c.excludedDisabled
        _ = c.orphaned
        return "unknown=\(c.unknown) storeHealth=\(c.storeHealth) degraded=\(c.degraded)"
    }
})

// MARK: - 7. journal --json 必须是 envelope（不是裸数组）

print("【7】journal --json 顶层形状")
require("第 7 组的准备阶段", {
    let data = try loadFixture("journal")
    check("顶层是 dict 且含 limit 披露") {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw structError("顶层不是 object —— 退回裸数组了。" +
                "裸数组放不下 limit/截断/坏行，消费方无法区分「窗口」与「全量」")
        }
        for k in ["entries", "limit", "unparsableLines"] {
            guard obj[k] != nil else {
                throw structError("缺少 \"\(k)\" 键（实际键：\(obj.keys.sorted())）")
            }
        }
        let n = (obj["entries"] as? [Any])?.count ?? -1
        return "entries=\(n) limit=\(obj["limit"] ?? "?") keys=\(obj.keys.sorted())"
    }
})

// MARK: - 7b. status 内嵌的 journal 条目（这一组是被漏掉后补上的）
//
// 【为什么补这一组】
// 原第 1 组解码 `status` 一直绿，但它的 `journal` 字段在沙箱里恰好是 `null`
// —— `[JournalEntry]?` 直接解成 nil，**一条条目都没解过**。
// 于是「JournalEntry 的字段与引擎对不对得上」这件事从来没被验证过。
// 这就是「测试前提恰好不成立」：不是断言写错了，是断言从没被执行到。
//
// 教训已经写过好几遍，这里再记一次：**通过不是因为对，是因为没走到**。
// 所以本组第一件事就是自证前提 —— 沙箱里必须真的有 journal 条目。

print("【7b】status 内嵌 journal 条目与窗口披露")
require("第 7b 组的准备阶段", {
    let data = try loadFixture("status")
    let env = try expectDecode("status", data, as: StatusEnvelope.self)
    let withJournal = env.projects.filter { ($0.journal?.isEmpty == false) }

    check("前提：沙箱里真的有 journal 条目（否则本组全部空转）") {
        guard !withJournal.isEmpty else {
            throw structError("没有任何项目带 journal 条目 ⇒ 本组断言不会被执行到。" +
                "要让沙箱先跑过一次 update（契约检查脚本已这么做）")
        }
        let n = withJournal[0].journal!.count
        return "\(withJournal.count) 个项目带日志，共 \(n) 条"
    }
    check("journal 条目能解出引擎的 id（不再用编造的 at/branch/mode）") {
        guard let e = withJournal.first?.journal?.first else {
            throw structError("没有条目可解")
        }
        // 引擎恒发 id（两个出口的条目里都有）。
        // 客户端原来自己编了一个 "\(at)/\(branch)/\(mode)"，
        // 于是「同一份日志条目」在引擎和界面里是两个身份。
        guard !e.id.isEmpty else {
            throw structError("id 为空 —— 客户端还在用编造的组合键，或引擎没发 id")
        }
        let fabricated = "\(e.at)/\(e.branch)/\(e.mode)"
        guard e.id != fabricated else {
            throw structError("id == 引擎的 at/branch/mode 拼接 ⇒ 还是编造的那个")
        }
        return "id=\(e.id)"
    }
    check("两个出口的 journal 条目**形状与值完全一致**（同一个概念不许两套真相）") {
        // 这条钉的是 2026-10-01 修掉的缺陷本身：
        //   `status --json` 内嵌的 journal 曾是一份手挑的 9 键投影，
        //   `journal --json` 的 entries 是存储原样的 17 键。
        // 投影丢掉 10 个键（commitCountScope / highlights / nextSteps / notes /
        // source / repoBranchCount / projectId / project 与两个截断标志），
        // 还多造了一个恒为 [] 的 docs。
        //
        // 后果不是"字段少几个"：消费方得写两套解码分支，
        // 而最容易漏的那一套会把「没数据」显示成「一切正常」。
        // 两个出口的 fixture 都由 contract-check.sh 事先收好（同一个项目 ok）。
        let aData = try loadFixture("status")
        let bData = try loadFixture("journal")
        guard let aObj = try? JSONSerialization.jsonObject(with: aData) as? [String: Any],
              let bObj = try? JSONSerialization.jsonObject(with: bData) as? [String: Any],
              let aProj = (aObj["projects"] as? [[String: Any]])?.first,
              let aArr = aProj["journal"] as? [[String: Any]],
              let bArr = bObj["entries"] as? [[String: Any]],
              let a0 = aArr.first, let b0 = bArr.first else {
            throw structError("两个出口都取不到第一条 journal 条目")
        }
        let ka = Set(a0.keys), kb = Set(b0.keys)
        guard ka == kb else {
            throw structError("键集不同 —— status 多/少：\(ka.symmetricDifference(kb).sorted())")
        }
        for k in ka.sorted() where k != "id" {
            let sa = String(describing: a0[k] ?? "nil")
            let sb = String(describing: b0[k] ?? "nil")
            guard sa == sb else {
                throw structError("键 \(k) 值不同：status=\(sa) journal=\(sb)")
            }
        }
        return "\(ka.count) 键全等"
    }
    check("非 git 项目的 warnings 必须真的解出来（引擎说了，模型接不接是两回事）") {
        // 引擎对非 git 项目会说「非 git 仓库：进度基于文件工作时间，不含提交历史」，
        // 而同屏 headline 照旧显示「0 个提交」——
        // 把「压根没测过提交数」说成「一个提交都没有」。
        // 客户端 ProjectStatus 原来**压根没有 warnings 字段**，
        // 于是引擎说了等于没说，谎话由模型层说出口。
        //
        // ⚠️ 必须**点名**查那个非 git 项目：写「遍历所有项目，
        // 遇到非 git 就断言」的话，沙箱里若全是 git 项目，
        // 这条断言会一路空转着变绿 —— 本组已经吃过一次空转的亏
        // （journal 那组的「前提」检查就是为了防这个才加的）。
        // 用专门收的 fixture：上面那份 status 只含 ok（git 项目），
        // 拿不到「非 git」这个真正要紧的样本。
        let plainEnv = try expectDecode("status_plain", try loadFixture("status_plain"),
                                        as: StatusEnvelope.self)
        let plain = plainEnv.projects.first
        guard let plain else {
            throw structError("沙箱里没有 plain 项目（contract-check.sh 应注册一个非 git 目录）"
                              + "—— 本断言会空转，须先修沙箱")
        }
        guard plain.kind != "git" else {
            throw structError("plain 项目不是非 git 的，前提不成立")
        }
        guard !plain.warnings.isEmpty else {
            throw structError("非 git 项目没有 warnings —— 用户无从知道「0 个提交」是「没测过」")
        }
        return "kind=\(plain.kind)，\(plain.warnings.count) 条警告：「\(plain.warnings[0])」"
    }
    check("git 项目的 warnings 应当为空（恒发的空数组，不是缺键）") {
        // 反向对照：恒发之后，正常的 git 项目必须是**空数组**而不是**没有这个键**。
        // 如果哪天又改回条件性发，这条会红。
        let ok = env.projects.first { $0.name == "ok" }
        guard let ok else { throw structError("沙箱里没有 ok 项目") }
        guard ok.warnings.isEmpty else {
            throw structError("正常 git 项目却有警告：\(ok.warnings)")
        }
        return "ok 项目 warnings=[]（键在、值为空）"
    }
    check("warnings 恒发（键的出现与否取决于数据 ⇒ 消费方要写两套解码分支）") {
        // 引擎原来只在非空时才加这个键，与同一对象里
        // journalTruncated / journalLimit / journalUnparsableLines 的恒发口径矛盾。
        let raw = try loadFixture("status")
        guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let projs = obj["projects"] as? [[String: Any]] else {
            throw structError("status fixture 解不出 projects")
        }
        for p in projs {
            guard p.keys.contains("warnings") else {
                throw structError("项目 \(p["name"] ?? "?") 没有 warnings 键 —— 恒发没做到")
            }
        }
        return "\(projs.count) 个项目都带 warnings 键"
    }
    check("「docs 缺失」不得被解码成「没有文档变更」（恒空假值比缺键更坏）") {
        // 引擎只让 deep 写 docs；浅更新的条目压根没这个键。
        // 客户端模型必须接受它的缺席，而不是要求一个恒为 [] 的假值。
        guard let e = withJournal.first?.journal?.first else {
            throw structError("没有条目可解")
        }
        // 不在这里断言 docs 一定缺失（沙箱跑的是浅更新，但那是实现细节），
        // 只钉住：**缺失时不能崩，且不能被填成"确实没有变更"**。
        if e.docs == nil {
            return "本条目未记录 docs（浅更新）—— 模型正确接受缺席"
        }
        return "本条目有 docs（\(e.docs!.count) 项）"
    }
    check("journal 窗口披露恒发（截断不得靠「键在不在」判断）") {
        let p = withJournal[0]
        // 这三个键原来引擎是条件性发的、客户端一个都没建模，
        // 于是「journal 有 N 条」既可能是一共 N 条、也可能只是窗口。
        _ = p.journalTruncated
        _ = p.journalLimit
        _ = p.journalUnparsableLines
        guard p.journalLimit > 0 else {
            throw structError("journalLimit=\(p.journalLimit) ⇒ 窗口大小读不出来")
        }
        return "truncated=\(p.journalTruncated) limit=\(p.journalLimit) 坏行=\(p.journalUnparsableLines)"
    }
    check("commitCount 的 -1 三态不被渲染成 0") {
        let all = withJournal.flatMap { $0.journal ?? [] }
        let unknown = all.filter { $0.commitCount < 0 }
        if !unknown.isEmpty {
            return "\(unknown.count)/\(all.count) 条读不出来，模型保留 -1 未被压成 0"
        }
        // 沙箱里没有 -1 时，用构造样本验证渲染判定本身
        let probe = JournalEntry(
            id: "x", at: "", mode: "track", branch: "", summary: "",
            providerLabel: "", commitCount: -1, docs: []
        )
        guard probe.commitCount == -1 else { throw structError("commitCount 被压成 0 了") }
        return "沙箱无 -1 样本；构造样本确认 -1 被保留"
    }
})

// MARK: - 8. git --json

print("【8】git --json → GitOpResponse")
require("第 8 组的准备阶段", {
    let data = try loadFixture("git")
    check("envelope 解码") {
        let r = try expectDecode("git", data, as: GitOpResponse.self)
        return "op=\(r.op) ok=\(r.ok)"
    }
})

// MARK: - 9. 引擎错误退出时 stdout 必须是可解析的 JSON（P0-2 的前提）

print("【9】全项目采集失败 → stdout 仍带 JSON payload")
require("第 9 组的准备阶段", {
    // 先钉住前提：这个场景必须真的是「非 0 退出」。
    // 少了它，exit 悄悄变回 0 时下面那条照样绿 —— 而 P0-2 修的正是
    // 「非 0 退出时 stdout 被丢弃」。前提没了，整组测试就是空转。
    check("前提：引擎在这个场景下确实非 0 退出") {
        let rc = String(decoding: try loadFixtureFile("status_allfail.rc"), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard rc != "0" else {
            throw structError("exit=0 —— 沙箱没造出「全失败」（有项目路径还活着？），本组全部断言失去意义")
        }
        return "exit=\(rc)"
    }
    let data = try loadFixture("status_allfail")
    check("exit!=0 时的 stdout 可解出 envelope") {
        let env = try expectDecode("status_allfail", data, as: StatusEnvelope.self)
        guard let s = env.summary else { throw structError("summary 为 nil") }
        guard s.failedProjects > 0 else {
            throw structError("failedProjects=0，沙箱可能没造成功")
        }
        let reasons = env.projects.compactMap { $0.error }
        // P0-2 的要害：这些 per-project error 是引擎**唯一**留下的原因 ——
        // 实测该场景 stderr 是 0 字节，丢掉 stdout 就只剩「引擎退出码 1」。
        return "failed=\(s.failedProjects) listed=\(s.listedProjects) 原因示例=\(reasons.first ?? "<无>")"
    }
})

// MARK: - 10. MCP 出口（第三套形状，刻意与 CLI 不同）

/// 解出 MCP content[0].text 里的 JSON。
/// MCP 的协议形状是 `{result: {content: [{text: "..."}]}}`，真正的数据在 text 里（字符串）。
func mcpText(_ name: String) throws -> Data {
    let data = try loadFixture(name)
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw structError("顶层不是 object")
    }
    if let err = obj["error"] as? [String: Any] {
        throw structError("MCP 返回了 error：\(err["message"] ?? "?")")
    }
    guard let result = obj["result"] as? [String: Any],
          let content = result["content"] as? [[String: Any]],
          let first = content.first,
          let text = first["text"] as? String else {
        throw structError("不是预期的 MCP content 形状（实际键：\(obj.keys.sorted())）")
    }
    return Data(text.utf8)
}

print("【10】MCP 出口形状（刻意与 CLI 不同，别「顺手统一」）")
require("第 10 组的准备阶段", {
    let statusData = try mcpText("mcp_status")
    check("get_project_status 是**裸 ProjectStatus**（单项目语义，无需剥 envelope）") {
        // 刻意与 CLI 的恒定 envelope 不同：MCP 工具保证恰好一个项目，
        // 套 envelope 只是让 LLM 多剥一层、白花 token。
        // 若这里改成 envelope，契约检查必须红 —— 那是「统一」掉了刻意设计。
        let p = try expectDecode("mcp_status", statusData, as: ProjectStatus.self)
        guard p.name == "ok" else { throw structError("期望 ok，实际 \(p.name)") }
        return "\(p.name) 裸对象，\(p.branches.count) 分支，commitCount=\(p.commitCount)"
    }
    check("裸 ProjectStatus 含全部披露字段") {
        let p = try expectDecode("mcp_status", statusData, as: ProjectStatus.self)
        _ = p.repoBranchCount
        _ = p.commitTypesTruncated
        _ = p.storeHealth
        _ = p.progress.entryCount
        return "repoBranchCount=\(p.repoBranchCount) storeHealth=\(p.storeHealth)"
    }
})
require("组", {
    let msData = try mcpText("mcp_milestones")
    check("list_milestones 是 {counts, items}") {
        guard let obj = try JSONSerialization.jsonObject(with: msData) as? [String: Any] else {
            throw structError("顶层不是 object")
        }
        guard obj["counts"] != nil, obj["items"] != nil else {
            throw structError("形状不是 {counts, items}（实际键：\(obj.keys.sorted())）")
        }
        return "keys=\(obj.keys.sorted())"
    }
    check("counts 含 9 个披露字段（含 unknown / storeHealth / degraded）") {
        guard let obj = try JSONSerialization.jsonObject(with: msData) as? [String: Any],
              let c = obj["counts"] as? [String: Any] else {
            throw structError("拿不到 counts")
        }
        for k in ["open", "done", "dropped", "unknown", "storeHealth",
                  "degraded", "readCount", "excludedDisabled", "orphaned"] {
            guard c[k] != nil else {
                throw structError("counts 缺 \"\(k)\"（实际键：\(c.keys.sorted())）")
            }
        }
        return "unknown=\(c["unknown"] ?? "?") storeHealth=\(c["storeHealth"] ?? "?")"
    }
    check("items[0] 与 CLI milestone list 的条目键集**完全一致**") {
        // 逐键比对：三个出口复用同一个 milestoneJson，条目形状必须逐键相同。
        // 不同的话，AI 工具循环读到的字段和客户端读到的不一样。
        //
        // 比对方式：拿引擎的 JSON 逐键对照客户端**显式建模**的键集。
        // 不能用「删掉一个键看解不解得出来」—— 那测的是必填字段，
        // 而可选字段缺失时解码照样过、值恒为默认，是更隐蔽的一种不一致。
        //
        // 键集（实测 17 个）：由 kernel.milestoneJson 一份产出，
        //   恒发披露：gitReadable / commitsSince / commitsSinceReadable / unverifiedReason
        //   刻意**没有** id：存储主键只出不进，发出来只会让 LLM 拿它当句柄，
        //   而 milestone_action 只认 project+name（详见该函数注释）。
        guard let obj = try JSONSerialization.jsonObject(with: msData) as? [String: Any],
              let items = obj["items"] as? [[String: Any]],
              let first = items.first else {
            throw structError("items 为空")
        }
        let cliData = try loadFixture("milestones")
        let cli = try expectDecode("milestones", cliData, as: MilestonesEnvelope.self)
        guard let cliItem = cli.milestones.first else { throw structError("CLI 侧 milestones 为空") }
        let modeled: Set<String> = [
            "projectId", "projectName", "name", "description", "status", "targetDate",
            "daysToTarget", "overdue", "tag", "tagName", "tagReached",
            "commitsSince", "commitsSinceReadable", "gitReadable", "createdAt", "completedAt",
            "unverifiedReason",
        ]
        let mcpKeys = Set(first.keys)
        let unmapped = mcpKeys.subtracting(modeled)
        guard unmapped.isEmpty else {
            throw structError("MCP 条目有 \(unmapped.sorted()) 键，而客户端 MilestoneItem 没有建模它们。" +
                "AI 工具循环读得到、客户端读不到 —— 同一份事实两种理解")
        }
        guard modeled.subtracting(mcpKeys).isEmpty else {
            throw structError("客户端建模了 \(modeled.subtracting(mcpKeys).sorted())，" +
                "但引擎三个出口都没这个键（值会恒为默认，是最隐蔽的一种不一致）")
        }
        // 值也要真的对得上，不只是键名
        guard cliItem.name == first["name"] as? String else {
            throw structError("同名里程碑在两个出口的 name 不同：\(cliItem.name) vs \(first["name"] ?? "?")")
        }
        return "\(mcpKeys.count) 键完全一致，且值对得上（name=\(cliItem.name)）"
    }
})
require("组", {
    let dashData = try mcpText("mcp_dashboard")
    check("get_dashboard 可解为 Dashboard") {
        let d = try expectDecode("mcp_dashboard", dashData, as: Dashboard.self)
        return "projects=\(d.projects.total)/\(d.projects.listed) milestones=\(d.milestones.counts.open)"
    }
})

// MARK: - 11. 键集不得随数据变化（本组抓出来的真实缺陷）
//
// unverifiedReason 原先是 `if (!gitReadable) 才加` 的条件性键，
// 而且只有 milestone list 出口有、dashboard 出口没有。实测：
//   健康态：milestone list 17 键 / dashboard 17 键
//   降级态：milestone list 18 键 / dashboard 17 键
// 后果有两层：
//   1. 消费方看见「多了个键」就知道出了故障 —— 这层耦合没有任何契约文档；
//   2. 客户端结构体若把 unverifiedReason 建成可选，缺失时拿到空串，
//      而空串恰好是「一切正常」的值 ⇒ **故障被渲染成正常**。
// 所以恒发 + 三出口一份形状，并由本组钉死。

print("【11】键集不随数据变化（降级态 vs 健康态）")
require("第 11 组的准备阶段", {
    func item(_ fixture: String, project: String,
              path: ([String: Any]) -> [[String: Any]]?) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: try loadFixture(fixture)) as? [String: Any] else {
            throw structError("fixture \(fixture) 顶层不是 object")
        }
        guard let arr = path(obj), let hit = arr.first(where: {
            ($0["projectName"] as? String) == project
        }) else {
            throw structError("fixture \(fixture) 里找不到项目 \(project) 的条目")
        }
        return hit
    }
    let cliItems: ([String: Any]) -> [[String: Any]]? = { $0["milestones"] as? [[String: Any]] }
    let dashItems: ([String: Any]) -> [[String: Any]]? = {
        ($0["milestones"] as? [String: Any])?["items"] as? [[String: Any]]
    }

    let healthyCLI = try item("milestones", project: "ok", path: cliItems)
    let healthyDash = try item("dashboard", project: "ok", path: dashItems)
    let degradedCLI = try item("milestones_deg", project: "plain", path: cliItems)
    let degradedDash = try item("dashboard_deg", project: "plain", path: dashItems)

    check("健康态 CLI 与 dashboard 键集一致") {
        let a = Set(healthyCLI.keys), b = Set(healthyDash.keys)
        guard a == b else {
            throw structError("差集：CLI 独有 \(a.subtracting(b).sorted())，dashboard 独有 \(b.subtracting(a).sorted())")
        }
        return "\(a.count) 键"
    }
    check("降级态键集 == 健康态键集（条件性发键 = 消费方要写两套解码分支）") {
        let healthy = Set(healthyCLI.keys)
        for (label, d) in [("CLI", degradedCLI), ("dashboard", degradedDash)] {
            let got = Set(d.keys)
            guard got == healthy else {
                throw structError("\(label) 降级态多出 \(got.subtracting(healthy).sorted())，" +
                    "少了 \(healthy.subtracting(got).sorted())")
            }
        }
        return "四个集合全等，各 \(healthy.count) 键"
    }
    check("降级态的 unverifiedReason 恒发且非空（原来是「不可读才加」）") {
        if let v = healthyCLI["unverifiedReason"] as? String {
            guard v.isEmpty else { throw structError("健康态就该是空串，实际 \(v)") }
        } else {
            throw structError("健康态没有 unverifiedReason 键 —— 键集随数据漂移了")
        }
        guard let reason = degradedCLI["unverifiedReason"] as? String, !reason.isEmpty else {
            throw structError("降级态的 unverifiedReason 缺失或为空，客户端会把它显示成「一切正常」")
        }
        return "健康态=\"\"，降级态=\"\(reason.prefix(20))…\""
    }
    check("降级态的 -1 三态在两个出口都对得上（status/commitsSince）") {
        for (label, d) in [("CLI", degradedCLI), ("dashboard", degradedDash)] {
            guard (d["status"] as? String) == "unknown" else {
                throw structError("\(label) 降级态 status=\(d["status"] ?? "<nil>")，应是 unknown")
            }
            guard (d["commitsSince"] as? Int) == -1 else {
                throw structError("\(label) 降级态 commitsSince=\(d["commitsSince"] ?? "<nil>")，应是 -1")
            }
            guard (d["commitsSinceReadable"] as? Bool) == false,
                  (d["gitReadable"] as? Bool) == false else {
                throw structError("\(label) 降级态的 readable 标志位不对")
            }
        }
        return "两个出口都是 status=unknown / commitsSince=-1 / readable=false"
    }
    check("客户端能从降级态条目解出原因（unverifiedNote 非空）") {
        let d = try expectDecode("milestones_deg", try loadFixture("milestones_deg"), as: MilestonesEnvelope.self)
        guard let m = d.milestones.first(where: { $0.projectName == "plain" }) else {
            throw structError("降级态里找不到 plain 项目")
        }
        guard m.isUnknown else { throw structError("isUnknown 为 false，UI 会渲染成「进行中」") }
        guard !m.unverifiedNote.isEmpty else {
            throw structError("unverifiedNote 为空 ⇒ 故障行什么也不显示")
        }
        return "isUnknown=true note=\"\(m.unverifiedNote.prefix(16))…\""
    }
    check("引擎没给原因时，客户端也不能显示成空（兜底不是可选项）") {
        // 上一条验的是「引擎给了原因，客户端读到了」。这一条验的是反面：
        // **万一原因没到**（老引擎、条件性发键、字段建成可选而拿到 nil），
        // 客户端必须仍然说点什么。
        //
        // 为什么要单列：把 unverifiedReason 建成 `String?` 再 `?? ""`，
        // 在当前引擎下**全部断言照样绿**（引擎恒发，值不为 nil），
        // 而一旦引擎哪天退回条件发，UI 就会在故障行显示一片空白 ——
        // 正是「读不出来被渲染成正常」这一族。已实测踩过。
        let probe = MilestoneItem(
            projectId: "p", projectName: "p", name: "n", description: "",
            status: "unknown", targetDate: "", daysToTarget: -1, overdue: false,
            tag: "", tagName: "", tagReached: false,
            commitsSince: -1, commitsSinceReadable: false, gitReadable: false,
            createdAt: "", completedAt: "", unverifiedReason: ""
        )
        guard !probe.unverifiedNote.isEmpty else {
            throw structError("unverifiedReason 为空时 unverifiedNote 也是空串 ⇒ 故障行什么都不显示")
        }
        return "引擎没给原因时兜底为「\(probe.unverifiedNote)」"
    }
})

// MARK: - 汇总

// MARK: - 12. 工具清单：引擎声明的与客户端能执行的是同一份

print("")
print("【12】工具清单对应（引擎 tools --json ⇄ 客户端 executeTool 的 switch）")

do {
    let engineTools = try {
        let data = try loadFixture("tools")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["tools"] as? [[String: Any]] else {
            throw structError("tools fixture 解不出 tools 数组")
        }
        return Set(list.compactMap { $0["name"] as? String })
    }()

    let clientCases = Set(toolCaseNames(in: try sourceText("AgentCore.swift")))

    check("前提：两边都抓到了东西（抓不到就是本组空转，必须先修抓取）") {
        guard !engineTools.isEmpty else {
            throw structError("引擎一个工具都没声明 —— 抓取或 fixture 有问题")
        }
        guard !clientCases.isEmpty else {
            throw structError("客户端 switch 里一个 case 都没抓到 —— "
                              + "要么改成了 if name == … 的写法，要么抓取坏了。"
                              + "本组会**静默空转**，不能就这么放过")
        }
        return "引擎 \(engineTools.count) 个 / 客户端 \(clientCases.count) 个"
    }

    check("客户端能执行的工具集 == 引擎声明的工具集（一份清单不许抄两份）") {
        // 漂移的表现：模型调了一个客户端不会执行的工具，
        // 界面上只显示一句「未知工具：X」——
        // 很容易被当成模型乱调，而真因是两份清单已经不一致。
        // 引擎加工具时必须同步客户端，否则这条会红。
        let onlyEngine = engineTools.subtracting(clientCases).sorted()
        let onlyClient = clientCases.subtracting(engineTools).sorted()
        guard onlyEngine.isEmpty, onlyClient.isEmpty else {
            var msg = "两份清单漂移了。"
            if !onlyEngine.isEmpty { msg += "\n      引擎有、客户端不会执行：\(onlyEngine)" }
            if !onlyClient.isEmpty { msg += "\n      客户端会执行、引擎没声明：\(onlyClient)" }
            throw structError(msg)
        }
        return "\(engineTools.count) 个工具完全对应"
    }

    // ---- 第三份副本：MCP 的 tools/list（缺陷 #192）----
    //
    // CLI `tools --json`（客户端据此给模型建工具，10 个）与
    // MCP `tools/list`（Claude Desktop 等 AI 看到的，15 个）
    // 几乎完全不相交：重叠只有 6 个。
    //
    //   只在 CLI  ：get_milestones / git_commit / git_pull_push / milestone_done
    //   只在 MCP  ：list_projects / get_project_status / get_dashboard / git_op
    //               run_track / list_milestones / milestone_add / milestone_action / add_project
    //
    // ⚠️ 下面是**已声明的基线**，不是「应该相同」。
    // 两份注册表服务于不同运行时，能力集本就可以不同 ——
    // 但不同必须是**有意识地**不同。基线的作用是：任何一边加工具，
    // 这条立刻红，并把差集原样打出来，逼着做决定。
    // 不声明的话，漂移永远是静默的，而症状要等到某天模型调了个
    // 另一个运行时有、这里没有的工具时才暴露。
    let cliOnlyBaseline: Set<String> = [
        "get_milestones", "git_commit", "git_pull_push", "milestone_done",
    ]
    let mcpOnlyBaseline: Set<String> = [
        "add_project", "get_dashboard", "get_project_status", "git_op",
        "list_milestones", "list_projects", "milestone_action", "milestone_add", "run_track",
    ]

    check("前提：MCP tools/list fixture 抓到了东西") {
        let data = try loadFixture("mcp_tools_list")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["result"] as? [String: Any],
              let tools = list["tools"] as? [[String: Any]] else {
            throw structError("mcp_tools_list fixture 解不出 result.tools —— 抓取坏了，本组会静默空转")
        }
        guard !tools.isEmpty else { throw structError("MCP 一个工具都没列出") }
        return "\(tools.count) 个"
    }

    check("CLI 清单 ⇄ MCP 清单的差集必须是**已声明**的基线（#192）") {
        let data = try loadFixture("mcp_tools_list")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = obj["result"] as? [String: Any],
              let tools = r["tools"] as? [[String: Any]] else {
            throw structError("mcp_tools_list 解不出")
        }
        let mcpTools = Set(tools.compactMap { $0["name"] as? String })
        let cliOnly = engineTools.subtracting(mcpTools)
        let mcpOnly = mcpTools.subtracting(engineTools)

        guard cliOnly == cliOnlyBaseline, mcpOnly == mcpOnlyBaseline else {
            var msg = "两份工具注册表的差集变了 —— 这必须是一次有意识的决定。\n"
            let d1 = cliOnly.symmetricDifference(cliOnlyBaseline).sorted()
            let d2 = mcpOnly.symmetricDifference(mcpOnlyBaseline).sorted()
            if !d1.isEmpty { msg += "      只在 CLI 的一侧新增/移除：\(d1)\n" }
            if !d2.isEmpty { msg += "      只在 MCP 的一侧新增/移除：\(d2)\n" }
            msg += "      当前 只在CLI=\(cliOnly.sorted()) 只在MCP=\(mcpOnly.sorted())"
            throw structError(msg)
        }
        return "差集与基线一致（CLI 独有 \(cliOnly.count) / MCP 独有 \(mcpOnly.count) / 重叠 \(engineTools.intersection(mcpTools).count)）"
    }

    check("同一能力在两份注册表里不得用**不同的名字**") {
        // 已知的两处改名（实测）：
        //   CLI get_milestones  ⇄  MCP list_milestones
        //   CLI milestone_done  ⇄  MCP milestone_action
        // 「同一件事两个名字」是本引擎反复栽跟头的族：
        // 消费方无从知道它们是不是同一个，模型也会当成两个工具。
        // 这里把已知的对应关系钉住；将来统一命名时改这一处即可。
        let knownRenames: [String: String] = [
            "get_milestones": "list_milestones",
            "milestone_done": "milestone_action",
        ]
        let data = try loadFixture("mcp_tools_list")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = obj["result"] as? [String: Any],
              let tools = r["tools"] as? [[String: Any]] else {
            throw structError("mcp_tools_list 解不出")
        }
        let mcpTools = Set(tools.compactMap { $0["name"] as? String })
        for (cli, mcp) in knownRenames.sorted(by: { $0.key < $1.key }) {
            guard engineTools.contains(cli) else {
                throw structError("CLI 侧的 \(cli) 已经改名了，本对应关系要一起更新")
            }
            guard mcpTools.contains(mcp) else {
                throw structError("MCP 侧的 \(mcp) 已经改名了，本对应关系要一起更新")
            }
        }
        return "\(knownRenames.count) 组改名对应已钉住"
    }

    check("客户端遇到不会执行的工具必须**明说**，不得静默当作成功") {
        let core = try sourceText("AgentCore.swift")
        guard core.contains("未知工具") else {
            throw structError("default 分支没有明说「未知工具」—— "
                              + "工具漂移时会伪装成一次正常调用")
        }
        return "default 分支会明说「未知工具：X」"
    }

    // ---- 以下两条是 #175 补的 ------------------------------------------------
    // 本组原来**只比 name**，所以「每个工具带一列指向已删服务的 /api/* 端点」
    // 一路全绿通过。名字对得上 ≠ 清单没说谎：清单是**要喂给模型的**，
    // 端点那两列直接就是「去调这些地址」的指令。
    check("工具清单不得携带**已删除传输层**的痕迹（/api/*、HTTP、localhost…）") {
        guard let text = String(data: try loadFixture("tools"), encoding: .utf8) else {
            throw structError("tools fixture 不是 UTF-8 文本")
        }
        let banned = ["/api/", "HTTP", "http://", "localhost", "127.0.0.1", "serve"]
        let hit = banned.filter { text.contains($0) }
        guard hit.isEmpty else {
            throw structError("清单里出现已删传输层的痕迹：\(hit.joined(separator: "、"))。"
                              + "HTTP 服务端已整体删除（AGENTS.md 第一条不变量：没有 /api/*），"
                              + "清单只该声明能力与参数")
        }
        return "\(banned.count) 类痕迹一个都没有"
    }

    check("清单只声明能力与参数（不许有 method/path/endpoint/url 这类传输层字段）") {
        let data = try loadFixture("tools")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["tools"] as? [[String: Any]], !list.isEmpty else {
            throw structError("tools fixture 解不出非空 tools 数组")
        }
        for t in list {
            let name = t["name"] as? String ?? "?"
            for k in ["method", "path", "endpoint", "url"] where t[k] != nil {
                throw structError("工具「\(name)」带了传输层字段「\(k)」—— "
                                  + "已删除的 HTTP 端点就是这么被抄回来的")
            }
            for k in ["name", "description", "params"] where t[k] == nil {
                throw structError("工具「\(name)」缺字段「\(k)」")
            }
        }
        return "\(list.count) 个工具形状一致（name/description/params）"
    }

    check("清单的 note 必须真话（不许再教 agent 走 HTTP）") {
        let data = try loadFixture("tools")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let note = obj["note"] as? String, !note.isEmpty else {
            throw structError("清单没有 note —— 消费方无从知道怎么接")
        }
        guard !note.contains("HTTP") else {
            throw structError("note 仍在教 agent 走 HTTP：\(note)")
        }
        return "note 已改成真实传输层说明"
    }
}

// MARK: - 13. 提交类型的条数上界：引擎发的条数必须容得进客户端色板（#206）

print("")
print("【13】提交类型条数上界（跨引擎 ↔ 客户端的边界，#206）")

do {
    // 这个数只能在**真实引擎输出**上量出来：
    // 客户端的色板容量（12）不是猜的，是引擎 COMMIT_TYPE_ORDER 的长度。
    // 引擎的类型词表一旦加长，客户端就会用同一种颜色画两类 ——
    // 分段条上两段糊在一起、图例两行同色圆点，读者无从分辨。
    //
    // ⚠️ 判据是 `count == 12` 而不是 `count <= 12`：只写 <= 的话，
    // 引擎掉到 8 类时这条依然绿，而那时色板就多出 4 个用不上的位置
    // —— 上界漂移不会被任何人发现。
    let data = try loadFixture("status_types")
    let env = try expectDecode("status_types", data, as: StatusEnvelope.self)
    guard let p = env.projects.first(where: { $0.name == "types" }) else {
        throw structError("没拿到 types 项目（projects=\(env.projects.map { $0.name })）")
    }
    let types = p.commitTypes ?? []
    check("真实引擎的 commitTypes 条数 = 12（色板容量的锚）") {
        guard types.count == 12 else {
            throw structError("实测 \(types.count) 条，期望 12。引擎的类型词表变了的话，" +
                              "客户端 CommitTypeColor.palette 要同步加颜色（色板容量 \(CommitTypeColor.capacity)）")
        }
        return types.map { $0.type }.joined(separator: " ")
    }
    check("条数上界必须容得进客户端色板") {
        guard types.count <= CommitTypeColor.capacity else {
            throw structError("引擎发 \(types.count) 条 > 色板容量 \(CommitTypeColor.capacity)：" +
                              "第 \(CommitTypeColor.capacity + 1) 类起会与前面某类同色")
        }
        return "\(types.count) ≤ \(CommitTypeColor.capacity)"
    }
    // 客户端自己的 top-5 截断（#206 的正身）必须发生，且必须说。
    // 这条 fixture 恰好是「引擎数据完整」的那一档：commitTypesTruncated=false
    // 意味着「这就是全量」，而界面此时只列 5 种 —— 披露不能依赖这个标志。
    check("引擎说「这就是全量」时，界面砍掉的类型必须自报") {
        guard !p.commitTypesTruncated else {
            throw structError("这个样本本该是完整档（commitTypesTruncated=false），" +
                              "拿到 true 说明采样窗口变了，#206 的复现前提失效")
        }
        guard let line = p.commitTypeLine else {
            throw structError("commitTypeLine 为 nil，\(types.count) 条类型一个字都没显示")
        }
        guard line.contains("前 5"), line.contains("共 12") else {
            throw structError("藏掉的 \(types.count - 5) 种没有披露：\(line)")
        }
        return line
    }
    check("卡片切片在这份数据上不产生截断（12 = 上界，cut 恒为 false）") {
        let s = commitTypeCardSlice(entries: types.map { (type: $0.type, count: $0.count) })
        guard !s.cut, s.entries.count == 12, s.note == nil else {
            throw structError("12 条（正好是上界）却报了截断：\(s.note ?? "nil")")
        }
        return "画全了"
    }
}

// MARK: - 14. 里程碑条目：引擎不许静默截断，界面砍掉的必须自报（#207）

print("")
print("【14】里程碑卡片完整度（跨引擎 ↔ 客户端的边界，#207）")

do {
    let data = try loadFixture("dashboard")
    let d = try expectDecode("dashboard", data, as: Dashboard.self)
    let c = d.milestones.counts
    let items = d.milestones.items

    check("引擎的 items 是完整的（不许有静默上限）") {
        // 缺陷 #207 的另一半：如果引擎哪天给 items 加个上限而不披露，
        // 客户端那句「共 N 条」就会跟着变成假话，而两边都不会红。
        // 对账等式：计入的 = open+done+dropped+unknown+other，
        // 读到的 = readCount = 计入 + 停用 + 孤儿。
        let accounted = c.open + c.done + c.dropped + c.unknown
        guard accounted == c.readCount - c.excludedDisabled - c.orphaned else {
            throw structError("对账等式不成立：计入 \(accounted)，readCount \(c.readCount) " +
                              "− 停用 \(c.excludedDisabled) − 孤儿 \(c.orphaned)")
        }
        guard items.count == accounted else {
            throw structError("items \(items.count) 条 ≠ 计入 \(accounted) 条 ⇒ 引擎这一层截断了却没说")
        }
        return "items=\(items.count) 与计入数一致"
    }

    check("样本必须真的超过卡片上限（少于 5 条时那处截断是空操作，测它等于没测）") {
        guard items.count > MILESTONE_CARD_MAX else {
            throw structError("样本只有 \(items.count) 条（上限 \(MILESTONE_CARD_MAX)），" +
                              "#207 的前提不成立")
        }
        return "\(items.count) > \(MILESTONE_CARD_MAX)"
    }

    check("界面砍掉的条数必须自报") {
        let s = milestoneCardSlice(itemCount: items.count)
        guard s.cut, s.shown == MILESTONE_CARD_MAX else {
            throw structError("\(items.count) 条却没触发披露：shown=\(s.shown) cut=\(s.cut)")
        }
        guard let note = s.note, note.contains("共 \(items.count) 条") else {
            throw structError("披露里没有写明总数：\(s.note ?? "nil")")
        }
        return note
    }
}

// MARK: - 15. 更新结果的备份披露：引擎恒发、客户端必须解得出（#210/#211）

print("")
print("【15】更新结果的备份披露（跨引擎 ↔ 客户端的边界，#210）")

do {
    let data = try loadFixture("update_one")

    check("单项目 update 的 docs[] 能被客户端模型原样解出") {
        let env = try expectDecode("update_one", data, as: UpdateResultEnvelope.self)
        guard !env.docs.isEmpty else { throw structError("docs 为空 —— 样本没造出文档改动") }
        return "\(env.docs.count) 份文档，project=\(env.project)"
    }

    check("backup 键必须**恒发**（空串 = 确实没备份，不是「不知道」）") {
        // 键出现与否取决于数据的话，消费方就得写两套解码分支，
        // 而最容易漏的那套会把「键不存在」显示成「没备份」——
        // 真实原因可能是「这份文档是新建的」，两者处置完全不同。
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let docs = (obj?["docs"] as? [[String: Any]]) ?? []
        for d in docs {
            guard d.keys.contains("backup") else {
                throw structError("docs 条目缺 backup 键：\(d.keys.sorted())")
            }
            guard let b = d["backup"] as? String else {
                throw structError("backup 不是字符串：\(d["backup"] ?? "nil")")
            }
        }
        return "\(docs.count) 条都带 backup 键"
    }

    check("改动过的既有文档必须带**真实**备份路径") {
        let env = try expectDecode("update_one", data, as: UpdateResultEnvelope.self)
        guard let d = env.docs.first(where: { $0.changed && !$0.created }) else {
            throw structError("样本里没有「改动过的既有文档」这一档（新建是 backup=\"\"，无变化是 changed=false）")
        }
        guard !d.backup.isEmpty else { throw structError("改了文档却说没备份") }
        // 路径必须落在 store 的 backups 目录里，而不是随便编一个
        guard d.backup.contains("/backups/") else {
            throw structError("备份路径不在 backups 目录下：\(d.backup)")
        }
        return d.backup
    }

    check("新建的文档必须没有备份（凭空编一个是谎报）") {
        let env = try expectDecode("update_one", data, as: UpdateResultEnvelope.self)
        for d in env.docs where d.created {
            guard d.backup.isEmpty else {
                throw structError("新建的 \(d.file) 却报了备份：\(d.backup)")
            }
        }
        return "新建 ⇒ 无备份"
    }

    check("通知文案必须跟着引擎报的 docs 走（两种形状都要说对）") {
        // ⚠️ 第一版把「有改动」写死成前提，于是样本变成「无变化」时，
        // 报出来的错是「有改动却说没改」—— **方向正好相反**，
        // 读的人会被带偏。判据必须从数据推出期望，而不是预设一种形状。
        let env = try expectDecode("update_one", data, as: UpdateResultEnvelope.self)
        let s = updateOutcomeSummary(env.outcome, project: env.project)
        guard s.contains(env.project) else { throw structError("文案里没有项目名：\(s)") }
        if env.outcome.anythingTouched {
            guard s.contains("已更新") || s.contains("新建") else {
                throw structError("docs 说有改动，文案却说没改：\(s)")
            }
            for d in env.docs where d.changed && !d.created && !d.backup.isEmpty {
                guard s.contains(d.backup) else {
                    throw structError("备份路径没进文案：\(s)")
                }
            }
        } else {
            guard !s.contains("已更新") && !s.contains("已刷新") else {
                throw structError("docs 说没改动，文案却说改了：\(s)")
            }
        }
        return s
    }

    check("多项目 update 的载荷能解（注意 1 个项目时是**裸**对象，不是 {results:…}）") {
        let allData = try loadFixture("update_all")
        if let all = try? JSONDecoder().decode(UpdateAllEnvelope.self, from: allData) {
            guard all.count == all.results.count else {
                throw structError("count=\(all.count) 与 results.size=\(all.results.count) 对不上")
            }
            guard all.succeeded + all.failed == all.count else {
                throw structError("succeeded+failed ≠ count：\(all.succeeded)+\(all.failed) vs \(all.count)")
            }
            return "\(all.count) 个项目，失败 \(all.failed)"
        }
        // 只有一个项目时引擎给裸对象 —— 两种形状都必须能走通
        let one = try expectDecode("update_all", allData, as: UpdateResultEnvelope.self)
        return "单项目裸对象（project=\(one.project)）"
    }
}

// MARK: - 16. Phase 3 地基层：引擎给了、模型收了、界面说不说

print("【16】Phase 3 地基层的 13 个引擎键（引擎给了、模型收了、界面说不说）")
require("第 16 组的准备阶段", {
    _ = try expectDecode("status", loadFixture("status"), as: StatusEnvelope.self)
    _ = try expectDecode("status_error", loadFixture("status_error"), as: StatusEnvelope.self)
})

check("错误桩的 overall / dirty 是空对象，模型必须吃得下") {
    // 这一条是**本轮真实踩到的那处**：OverallMeta/DirtyInfo 的字段被声明成非可选，
    // 而引擎在采集失败时把这两个键发成 {} ⇒ Decodable 抛 keyNotFound ⇒
    // 后果不是「这个坏项目没总结」，而是**整条 StatusEnvelope 解不出来**，
    // 所有好项目一起消失。非可选字段的代价会被放大到整个列表。
    let env = try expectDecode("status_error", loadFixture("status_error"), as: StatusEnvelope.self)
    guard let p = env.projects.first(where: { $0.error != nil }) else {
        throw structError("没有带 error 的项目 —— 沙箱可能没造成功")
    }
    return "错误桩 \(p.name) 解得出来"
}

check("错误桩的 dirty 必须判为「读不出来」，不是「工作区干净」") {
    let env = try expectDecode("status_error", loadFixture("status_error"), as: StatusEnvelope.self)
    guard let p = env.projects.first(where: { $0.error != nil }) else {
        throw structError("没有带 error 的项目")
    }
    let d = try requireDirty(p)
    guard !d.isReadable else {
        throw structError("错误桩的 dirty 被判成可读。引擎发的是 {}，ok 缺席")
    }
    guard d.dirtyLine.contains("读不出来") else {
        throw structError("dirtyLine=\"\(d.dirtyLine)\"。报「工作区干净」等于替用户断言事实")
    }
    return d.dirtyLine
}

check("dirtyLine 的三档语义（缺席/读不出来 · 干净 · 有改动带分档）") {
    // 显式 false 与缺席是同一件事：引擎没读出来。
    // 把它们当 0 渲染就是「工作区干净」，与 userDirtyCount 的 -1 是同一个坑。
    let unreadable = DirtyInfo(ok: nil, total: 3, modified: 1,
                               staged: 0, untracked: 2, conflicts: 0, files: nil)
    guard unreadable.dirtyLine.contains("读不出来") else {
        throw structError("ok 缺席时 dirtyLine=\"\(unreadable.dirtyLine)\"，期望披露读不出来")
    }
    let denied = DirtyInfo(ok: false, total: 3, modified: 1,
                           staged: 0, untracked: 2, conflicts: 0, files: nil)
    guard denied.dirtyLine.contains("读不出来") else {
        throw structError("ok=false 时 dirtyLine=\"\(denied.dirtyLine)\"，期望披露读不出来")
    }
    let clean = DirtyInfo(ok: true, total: 0, modified: 0,
                          staged: 0, untracked: 0, conflicts: 0, files: [])
    guard clean.dirtyLine == "工作区干净" else {
        throw structError("真干净时 dirtyLine=\"\(clean.dirtyLine)\")")
    }
    let dirty = DirtyInfo(ok: true, total: 3, modified: 1,
                          staged: 0, untracked: 2, conflicts: 0, files: ["a", "b"])
    guard dirty.dirtyLine.contains("未跟踪 2") && dirty.dirtyLine.contains("已修改 1") else {
        throw structError("有改动时分档丢了：\(dirty.dirtyLine)")
    }
    return "四档都对"
}

check("冲突必须顶在最前面（会丢代码的那种不能混进「N 处未提交」）") {
    let d = DirtyInfo(ok: true, total: 5, modified: 1,
                      staged: 1, untracked: 2, conflicts: 1, files: nil)
    let line = d.dirtyLine
    guard line.contains("冲突 1") else { throw structError("冲突没出现在 \(line)") }
    guard let c = line.range(of: "冲突"), let m = line.range(of: "已修改"),
          let s = line.range(of: "已暂存"), let u = line.range(of: "未跟踪") else {
        throw structError("分档不全：\(line)")
    }
    guard c.lowerBound < m.lowerBound, c.lowerBound < s.lowerBound, c.lowerBound < u.lowerBound else {
        throw structError("冲突不在最前：\(line)。混进去会被当成一条普通改动")
    }
    return line
}

check("健康项目的 dirty 必须可读且报真实数字（不是空对象蒙对）") {
    let env = try expectDecode("status", loadFixture("status"), as: StatusEnvelope.self)
    guard let p = env.projects.first, let d = p.dirty else {
        throw structError("样本里没有可用的 dirty")
    }
    guard d.isReadable else {
        throw structError("健康项目的 dirty 判成读不出来 ⇒ 样本没采到工作区，判据等于没跑")
    }
    guard !d.dirtyLine.contains("读不出来") else {
        throw structError("健康项目却报读不出来：\(d.dirtyLine)")
    }
    return d.dirtyLine
}

check("分支新键真的从引擎输出里解出来了（完整 SHA · 原文标题 · 来源）") {
    let env = try expectDecode("status", loadFixture("status"), as: StatusEnvelope.self)
    guard let b = env.projects.first?.branches.first(where: { ($0.head ?? "").count >= 40 }) else {
        throw structError("样本里没有带完整 SHA 的分支 ⇒ headTip 的判据没有数据可跑")
    }
    let tip = b.headTip
    guard tip.contains(b.head!) else {
        throw structError("headTip 里没有完整 SHA：\(tip)")
    }
    guard tip.contains(b.headShort) else {
        throw structError("headTip 里连短 SHA 都没有：\(tip)")
    }
    guard (b.headSubject?.isEmpty == false) else {
        throw structError("headSubject 是空的 —— 判据等于没跑")
    }
    guard !tip.contains("（无标题）") else {
        throw structError("headSubject 明明有值却走了兜底：\(tip)")
    }
    return "\(tip)（来源：\(b.providerLabel)）"
}

check("providerLabel 必须区分规则引擎与 AI（混成一种语气就是隐瞒来源）") {
    let rules = BranchStatus(name: "b", status: "active", statusLabel: "活跃",
                             headShort: "abc1234", headAgo: "刚刚", summary: "s",
                             pendingCommits: 0, aheadOfDefault: 0, isCurrent: false, isDefault: false,
                             highlights: nil, nextSteps: nil, staleDays: 0,
                             headSubject: nil, provider: "rules", head: nil, baselineReset: false)
    guard rules.providerLabel == "规则" else {
        throw structError("provider=rules 时显示「\(rules.providerLabel)」")
    }
    let ai = BranchStatus(name: "b", status: "active", statusLabel: "活跃",
                          headShort: "abc1234", headAgo: "刚刚", summary: "s",
                          pendingCommits: 0, aheadOfDefault: 0, isCurrent: false, isDefault: false,
                          highlights: nil, nextSteps: nil, staleDays: 0,
                          headSubject: nil, provider: "openai/gpt-4o", head: nil, baselineReset: false)
    guard ai.providerLabel == "openai/gpt-4o" else {
        throw structError("AI 来源被抹掉了：显示「\(ai.providerLabel)」")
    }
    let missing = BranchStatus(name: "b", status: "unknown", statusLabel: "未知",
                               headShort: "abc1234", headAgo: "", summary: "s",
                               pendingCommits: 0, aheadOfDefault: 0, isCurrent: false, isDefault: false,
                               highlights: nil, nextSteps: nil, staleDays: -1,
                               headSubject: nil, provider: nil, head: nil, baselineReset: false)
    guard missing.providerLabel == "规则" else {
        throw structError("provider 缺席时的兜底不是「规则」：\(missing.providerLabel)")
    }
    return "rules→规则 / openai→openai / nil→规则"
}

check("staleText 对 -1 必须说「读不出来」，不许说成今天更新过") {
    func mk(_ days: Int) -> BranchStatus {
        BranchStatus(name: "b", status: "unknown", statusLabel: "未知",
                     headShort: "abc1234", headAgo: "", summary: "s",
                     pendingCommits: 0, aheadOfDefault: 0, isCurrent: false, isDefault: false,
                     highlights: nil, nextSteps: nil, staleDays: days,
                     headSubject: nil, provider: "rules", head: nil, baselineReset: false)
    }
    guard mk(-1).staleText.contains("读不出来") else {
        throw structError("staleDays=-1 时 staleText=\"\(mk(-1).staleText)\"")
    }
    guard mk(0).staleText.contains("今天") else {
        throw structError("staleDays=0 时 staleText=\"\(mk(0).staleText)\"")
    }
    guard mk(1).staleText == "1 天没更新" else {
        throw structError("staleDays=1 时 staleText=\"\(mk(1).staleText)\"")
    }
    guard mk(40).staleText == "40 天没更新" else {
        throw structError("staleDays=40 时 staleText=\"\(mk(40).staleText)\"")
    }
    return "-1 / 0 / 1 / 40 四档都对"
}

check("headTip 缺 head 时必须退回短 SHA，不许留下空括号") {
    let b = BranchStatus(name: "b", status: "active", statusLabel: "活跃",
                         headShort: "abc1234", headAgo: "刚刚", summary: "s",
                         pendingCommits: 0, aheadOfDefault: 0, isCurrent: false, isDefault: false,
                         highlights: nil, nextSteps: nil, staleDays: 0,
                         headSubject: "修好了", provider: "rules", head: nil, baselineReset: false)
    guard b.headTip.contains("abc1234") else {
        throw structError("head 缺席时 headTip=\"\(b.headTip)\" —— 短 SHA 是最后一道")
    }
    guard b.headTip.contains("修好了") else {
        throw structError("标题丢了：\(b.headTip)")
    }
    return b.headTip
}

check("manifests 是字符串数组（空数组验证不了元素类型）") {
    // Phase 3 里 `manifests` 在没有依赖清单的仓库上恒为 []，元素类型根本没被验证过。
    // 空数组解不出元素类型，而 `overall` 正是这么栽的（照想象写成子对象，
    // 引擎发的是字符串；错误桩发的又是 {}）。所以样本里必须有真的 package.json。
    let env = try expectDecode("status", loadFixture("status"), as: StatusEnvelope.self)
    let hit = env.projects.first(where: { ($0.manifests?.isEmpty == false) })
    guard let mf = hit?.manifests else {
        throw structError("样本里 manifests 全是空的 ⇒ 元素类型仍未被验证。" +
            "契约检查的沙箱必须造一个带 package.json 的仓库，否则这条永远是空跑")
    }
    guard mf.contains("package.json") else {
        throw structError("manifests=\(mf) 里没有 package.json ⇒ 样本没造对")
    }
    return "\(mf) —— 解得出来且是字符串"
}

check("tags 的元素类型只能查引擎源码（CLI 造不出非空样本）") {
    // `add` 子命令只有 `--name`，没有 tags 参数 ⇒ tags 恒为 [] ⇒
    // 无法用 CLI fixture 验证元素类型。这条改成查引擎**怎么构造**它，
    // 并把局限写明：它是源码级保证，不是解码级保证。
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ContractCheck
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <pkg>
    let src = try String(contentsOf: dir.appendingPathComponent("../../../engine/src/flow/status.cj"),
                         encoding: .utf8)
    guard src.contains("for (t in project.tags)") else {
        throw structError("status.cj 里找不到 for (t in project.tags) ⇒ 判据没对准构造处")
    }
    guard src.contains("tagsArr.add(Json.of(t))") else {
        throw structError("status.cj 不再用 Json.of(t) 构造 tags ⇒ 元素类型可能已变，" +
            "客户端的 [String] 需要重新核对")
    }
    // 引擎错误桩也恒发 tags（空数组），所以模型侧至少不能因缺键而解码失败。
    let env = try expectDecode("status_error", loadFixture("status_error"), as: StatusEnvelope.self)
    guard env.projects.first(where: { $0.error != nil }) != nil else {
        throw structError("错误桩样本不见了")
    }
    return "引擎按 Json.of(String) 构造；错误桩能解码（局限：无法用 CLI 样本解码验证）"
}

check("脏文件清单要能拿到，且截断必须自报（静默砍掉前 8 个是谎报）") {
    func mk(_ files: [String]?) -> DirtyInfo {
        DirtyInfo(ok: true, total: files?.count ?? 0, modified: 1, staged: 0,
                  untracked: 0, conflicts: 0, files: files)
    }
    guard mk(["a.txt", "b.txt"]).dirtyFilesLine == "a.txt · b.txt" else {
        throw structError("两个文件时的清单：\(String(describing: mk(["a.txt", "b.txt"]).dirtyFilesLine))")
    }
    let many = (1...12).map { "f\($0).txt" }
    let line = mk(many).dirtyFilesLine ?? ""
    guard line.contains("还有 4 个") else {
        throw structError("12 个文件被砍成 8 个却不自报：\(line)")
    }
    guard line.hasPrefix("f1.txt") else { throw structError("截断不是取前 8 个：\(line)") }
    // 读不出来时不能列文件 —— 那等于编一份清单
    let unread = DirtyInfo(ok: nil, total: 3, modified: 1, staged: 0,
                           untracked: 2, conflicts: 0, files: ["x"])
    guard unread.dirtyFilesLine == nil else {
        throw structError("读不出来时列出了文件：\(unread.dirtyFilesLine ?? "")")
    }
    return "8/4 两档都对，读不出来时不给清单"
}

check("待记录徽章的数据源：status 必须报**实时** pendingCommits（不是存量快照）") {
    // 这一条盯的是 #213 的根因：status 原来读进度库里存的 pendingCommits，
    // 而那个值在 update 算完后立刻被归零（flow/update.cj:591）
    // ⇒ 顶栏那个徽章永远不亮，而它等的是一个不会来的数字。
    //
    // 样本必须**在 update 之后再提交**才非 0：只在刚跑完 update 的项目上验，
    // 验到的永远是 0，等于什么都没验。
    let env = try expectDecode("status_pending", loadFixture("status_pending"), as: StatusEnvelope.self)
    guard let p = env.projects.first else {
        throw structError("样本里没有项目 —— 沙箱可能没造成功")
    }
    let pending = p.branches.reduce(0) { $0 + $1.pendingCommits }
    guard pending > 0 else {
        throw structError("建基线后又提交了 3 次，status 仍报 pendingCommits=\(pending)。\n" +
            "客户端顶栏的「待记录 N」徽章因此永远不亮 —— 它等的是一个不会来的数字")
    }
    return "pendingCommits=\(pending)（update 之后再提交了 3 次）"
}

func requireDirty(_ p: ProjectStatus) throws -> DirtyInfo {
    guard let d = p.dirty else {
        throw structError("项目 \(p.name) 的 dirty 是 nil —— 引擎恒发这个键，模型却没解出来")
    }
    return d
}

print("")
if failures.isEmpty {
    print("✅ 契约检查通过：\(checks) 项")
    exit(0)
} else {
    print("❌ 契约检查失败：\(failures.count)/\(checks) 项")
    for f in failures { print("   · \(f)") }
    exit(1)
}
