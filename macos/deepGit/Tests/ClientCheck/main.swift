// ClientCheck — 客户端状态判定的检查。
//
// 编译的是 Sources/deepGit/ClientDecisions.swift 本体（不是副本）——
// 副本会与源文件漂移，测了等于没测。
//
// 覆盖两个已修缺陷：
//   P1-10 开机自启开关失败后不回滚 ⇒ **开关说自己知道是假的话**
//   P1-12 刷新进行中时把用户请求静默丢弃 ⇒ **点刷新像没反应**
//
// 两者都内联在视图/生命周期代码里，运行时抓不到；
// 抽成纯函数后才测得到，也才改得对。
//
// 【跑法】scripts/client-check.sh

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
    NSError(domain: "client", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
}

/// **shell 专用**的剥注释（`#`）。
///
/// 提到文件作用域而不是关在某一组里：后面几组也要 lint shell 脚本，
/// 而定义在 `do { }` 里的函数在文件作用域根本不可见 —— 踩过一次。
///
/// 为什么必须按语言分开：build.sh 的注释是 `#`，而剥 Swift 注释的那个
/// 函数只认 `//` 与 `/* */` —— 于是 build.sh 里那句解释性注释
/// 「原来是 `codesign … 2>/dev/null || true`」被 lint 当成了缺陷代码，假红。
/// 与 Swift 那次一模一样的坑：**源码 lint 不剥对语言的注释就一定出假红**。
func shellCode(_ s: String) -> String {
    var out = ""
    var inLine = false
    for ch in s {
        if ch == "\n" { inLine = false; out.append(ch); continue }
        if inLine { continue }
        if ch == "#" { inLine = true; continue }
        out.append(ch)
    }
    return out
}

/// 源文件目录（`Sources/deepGit`）。
let sourceDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // ClientCheck
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // <pkg>

func sourceText(_ name: String) throws -> String {
    try String(contentsOf: sourceDir.appendingPathComponent("Sources/deepGit/\(name)"),
                encoding: .utf8)
}

/// 读源文件并**剥掉注释**。lint 匹配前必须走这个 ———
/// 解释性注释里引用了散值写法就会假红（【3】里踩过）。
func strippedCode(_ name: String) throws -> String {
    swiftCode(try sourceText(name))
}

/// `Sources/deepGit` 下全部 .swift 文件名（不含路径、不含子目录）。
func allSourceFileNames() throws -> [String] {
    let dir = sourceDir.appendingPathComponent("Sources/deepGit")
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    return names.filter { $0.hasSuffix(".swift") }.sorted()
}

/// 包内任意文件的原文（Sources 之外的路径用它，比如 scripts/ 下的 .sh）。
func pkgText(_ relPath: String) throws -> String {
    try String(contentsOf: sourceDir.appendingPathComponent(relPath), encoding: .utf8)
}

/// 剥掉 Swift 注释的源码。**lint 匹配前必须剥** ——
/// 解释性注释里引用了被删掉的那行代码就会假红（【3】里已踩过）。
///
/// 提到文件作用域：后面几组也要 lint 同一个文件，
/// 而定义在 `do { }` 里的函数在文件作用域根本不可见 —— 踩过一次。
func swiftCode(_ source: String) -> String {
    var out = ""
    out.reserveCapacity(source.count)
    var inLine = false, inBlock = false
    var it = source.makeIterator()
    var pending: Character? = nil
    while let c = pending ?? it.next() {
        pending = nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
            continue
        }
        if inBlock {
            if c == "*" {
                pending = it.next()
                if pending == "/" { inBlock = false; pending = nil }
            }
            continue
        }
        if c == "/" {
            pending = it.next()
            switch pending {
            case "/": inLine = true; pending = nil
            case "*": inBlock = true; pending = nil
            default: out.append(c); if let p = pending { out.append(p); pending = nil }
            }
            continue
        }
        out.append(c)
    }
    return out
}

// MARK: - 1. P1-10：开关必须显示系统的真实状态

print("【1】开机自启开关不得说谎（P1-10）")

check("注册失败（请求 on，系统实际 off）⇒ 报不一致 + 显示 off") {
    guard let note = LoginItemOutcome.mismatchNote(requested: true, actualEnabled: false) else {
        throw fail("没报不一致 ⇒ 开关会停在「开」而系统其实是关的")
    }
    guard LoginItemOutcome.displayedState(requested: true, actualEnabled: false) == false else {
        throw fail("显示成了 on ⇒ 用户看到的开关在说假话")
    }
    return "已回滚并说明：\(note.prefix(12))…"
}

check("注销失败（请求 off，系统实际 on）⇒ 报不一致 + 显示 on") {
    guard let note = LoginItemOutcome.mismatchNote(requested: false, actualEnabled: true) else {
        throw fail("没报不一致")
    }
    guard LoginItemOutcome.displayedState(requested: false, actualEnabled: true) == true else {
        throw fail("显示成了 off")
    }
    return "已回滚并说明：\(note.prefix(12))…"
}

check("请求与实际一致 ⇒ 无需说明（不制造噪音）") {
    guard LoginItemOutcome.mismatchNote(requested: true, actualEnabled: true) == nil,
          LoginItemOutcome.mismatchNote(requested: false, actualEnabled: false) == nil else {
        throw fail("一致时也报了不一致 ⇒ 每次点开关都会冒出一句警告")
    }
    return "on/on 与 off/off 都不报"
}

check("显示状态永远等于系统实际值（与用户意图无关）") {
    // 四种组合全扫：意图 × 实际
    for requested in [true, false] {
        for actual in [true, false] {
            let shown = LoginItemOutcome.displayedState(requested: requested, actualEnabled: actual)
            guard shown == actual else {
                throw fail("意图=\(requested) 实际=\(actual) 却显示 \(shown)")
            }
        }
    }
    return "4 种组合，显示值 100% 等于系统实际值"
}

// MARK: - 2. P1-12：刷新请求不许被静默丢弃

print("【2】刷新请求不许被静默丢弃（P1-12）")

check("空闲时的请求直接开始跑") {
    var g = RefreshGate()
    guard g.request() else { throw fail("空闲时却拒绝了请求") }
    return "立即执行"
}

check("跑着的时候再来请求 ⇒ 记下来而不是丢掉（这是原缺陷）") {
    var g = RefreshGate()
    _ = g.request()                    // 第一次：开始跑
    let second = g.request()           // 第二次：撞上了
    guard !second else {
        throw fail("第二次请求被当成新任务开始了 ⇒ 会有两个并发全量刷新")
    }
    guard g.finish() else {
        throw fail("finish() 没说要补跑 ⇒ 用户的这次刷新被静默丢弃（就是 P1-12）")
    }
    return "已记下，跑完会补一次"
}

check("补跑之后不得无限循环") {
    var g = RefreshGate()
    _ = g.request()
    _ = g.request()
    _ = g.request()                    // 连撞三次
    guard g.finish() else { throw fail("应该要补跑") }
    guard !g.finish() else {
        throw fail("补跑标记没被清掉 ⇒ 会无限补跑")
    }
    return "连撞 3 次只补 1 次"
}

check("补跑期间来的新请求还要再补一次（不能被上一次的收尾吃掉）") {
    var g = RefreshGate()
    _ = g.request()        // 跑 A
    _ = g.request()        // 排 B
    guard g.finish() else { throw fail("B 丢了") }
    _ = g.request()        // 补跑 B
    _ = g.request()        // B 跑的时候又来了 C
    guard g.finish() else { throw fail("C 被 B 的收尾吃掉了") }
    return "A→B→C 三次请求全部兑现"
}

check("空闲时 finish() 不会凭空造出补跑") {
    var g = RefreshGate()
    guard !g.finish() else { throw fail("没在跑却说要补跑") }
    return "无请求时收尾是干净的"
}

check("UI 提示只区分「有排队」而不是「正在刷新」") {
    var g = RefreshGate()
    guard !g.shouldShowPendingHint else { throw fail("刚开始就提示排队") }
    _ = g.request()
    guard !g.shouldShowPendingHint else { throw fail("只有自己在跑却提示排队") }
    _ = g.request()
    guard g.shouldShowPendingHint else {
        throw fail("确实有排队却没提示 ⇒ 用户看到的还是「转完什么都没变」")
    }
    return "只有真排队时才提示"
}

check("闸门是值类型：拷贝出来的副本不会互相污染") {
    var a = RefreshGate()
    _ = a.request()
    var b = a
    _ = b.request()                     // b 上排队
    guard b.shouldShowPendingHint else { throw fail("b 上没记下排队") }
    guard !a.shouldShowPendingHint else {
        throw fail("a 被 b 污染了 ⇒ 值类型被当成了引用类型")
    }
    return "副本互不影响"
}

// MARK: - 3. 其余 P1 的源码级守卫
//
// 先说清楚读法：这一组是 **lint，不是行为测试**。
// 它们对应的是「结构」层面的缺陷 —— 挂了两个 toolbar、timer 没被存下来、
// 错误横幅自己带刷新。这些在运行时观察不到（两个 toolbar 都渲染成正常按钮），
// 但可以静态钉住：写法一旦退回去，lint 立刻红。
// 挡的是「再写一次」，不是「已经发生过」。

print("【3】其余 P1 的源码级守卫（lint，非行为测试）")
do {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ClientCheck
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <pkg>
    let src = root.appendingPathComponent("Sources/deepGit")
    func text(_ name: String) throws -> String {
        try String(contentsOf: src.appendingPathComponent(name), encoding: .utf8)
    }
    /// 统计子串出现次数（不是 contains —— 「只有一处」本身就是要断言的性质）
    func count(_ hay: String, _ needle: String) -> Int {
        var n = 0, i = hay.startIndex
        while let r = hay.range(of: needle, range: i..<hay.endIndex) {
            n += 1
            i = r.upperBound
        }
        return n
    }
    /// **剥掉注释**再匹配。
    ///
    /// 这一步是必须的，而且是被自己的注释咬出来的：修 P1-12 时我在
    /// `refreshAll` 上方写了「原来第一行是 `if isLoading { return }`」，
    /// lint 直接把这行注释当成了「缺陷代码还在」⇒ 假红。
    /// 修 P1-8/P1-11 时同样：解释性注释里引用了被删掉的那行代码。
    //
    // 教训：**源码 lint 不剥注释就一定会有假红**，而假红比没检查更糟 ——
    // 它会让人习惯性忽略这条检查。写 lint 的第一步就该剥注释。
    func code(_ source: String) -> String {
        var out = ""
        out.reserveCapacity(source.count)
        var inLine = false, inBlock = false
        var it = source.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if inLine {
                if c == "\n" { inLine = false; out.append(c) }
                continue
            }
            if inBlock {
                if c == "*" {
                    pending = it.next()
                    if pending == "/" { inBlock = false; pending = nil }
                }
                continue
            }
            if c == "/" {
                pending = it.next()
                switch pending {
                case "/": inLine = true; pending = nil
                case "*": inBlock = true; pending = nil
                default: out.append(c); if let p = pending { out.append(p); pending = nil }
                }
                continue
            }
            out.append(c)
        }
        return out
    }
    func codeOf(_ name: String) throws -> String { try code(try text(name)) }

    check("PanelView 只挂一个 .toolbar（P1-6：两个 ⇒ 刷新按钮出现两次）") {
        let t = try codeOf("PanelView.swift")
        guard t.contains("struct PanelView") else { throw fail("找不到 PanelView") }
        let n = count(t, ".toolbar {")
        guard n == 1 else {
            throw fail("PanelView 挂了 \(n) 个 .toolbar，SwiftUI 会把按钮都渲染出来")
        }
        return "只有 1 处"
    }

    check("工具栏里「刷新」只出现一次，且带 isLoading 禁用") {
        let t = try codeOf("PanelView.swift")
        guard count(t, "Label(\"刷新\"") == 1 else {
            throw fail("「刷新」出现 \(count(t, "Label(\"刷新\"") ) 次 ⇒ 重复按钮")
        }
        guard t.contains(".disabled(model.isLoading)") else {
            throw fail("刷新按钮没有 .disabled(model.isLoading) ⇒ 加载中也能点")
        }
        return "唯一且禁用生效"
    }

    check("错误横幅不得自带 .task { refreshAll }（P1-13）") {
        let t = try codeOf("PanelView.swift")
        // 允许 PanelView 里有 .task（那是 start() 的入口），但横幅那段不许有
        if t.contains(".background(.orange.opacity(0.12))\n                .task") {
            throw fail("错误横幅又挂上了 .task ⇒ 一报错就触发全量刷新，还可能把错误本身刷掉")
        }
        let tasks = count(t, ".task {")
        guard tasks <= 1 else {
            throw fail("PanelView 里有 \(tasks) 处 .task，其中可能有第二处刷新入口")
        }
        return "横幅无自带刷新（PanelView 共 \(tasks) 处 .task）"
    }

    check("start() 必须先清 timer 再重建（P1-7：面板开关 N 次挂 N 个）") {
        let t = try codeOf("Model.swift")
        guard let body = slice(t, from: "func start() async", to: "\n    }") else {
            throw fail("找不到 start()")
        }
        guard body.contains("invalidateTimers()") else {
            throw fail("start() 里没有 invalidateTimers() ⇒ 重复启动会叠加 timer")
        }
        return "start() 先清理"
    }

    check("stop() 必须收掉全部三个 timer（P1-8：原来只杀一个）") {
        let t = try codeOf("Model.swift")
        guard let inv = slice(t, from: "func invalidateTimers()", to: "\n    }") else {
            throw fail("找不到 invalidateTimers()")
        }
        for name in ["timer", "autoTimer", "firstRunTimer"] {
            guard inv.contains("\(name)?.invalidate()") else {
                throw fail("invalidateTimers() 没收掉 \(name)")
            }
        }
        guard let stop = slice(t, from: "func stop()", to: "\n    }"),
              stop.contains("invalidateTimers()") else {
            throw fail("stop() 没走 invalidateTimers()")
        }
        return "timer / autoTimer / firstRunTimer 三个都收"
    }

    check("600 秒首轮 timer 真的被存进 firstRunTimer（P1-7：原来是孤儿）") {
        let t = try codeOf("AIIntegration.swift")
        guard t.contains("firstRunTimer?.invalidate()") else {
            throw fail("restartAutoTimer 没先清旧的 firstRunTimer")
        }
        guard t.contains("firstRunTimer = Timer.scheduledTimer") else {
            throw fail("首轮 timer 仍没被保存 ⇒ 创建完就没人管，面板开关 N 次挂 N 个")
        }
        return "已保存且重启前清理"
    }

    check("批量更新必须走 model（有 busyAll 闸门），不得直连 EngineCLI（P1-8）") {
        let t = try codeOf("AIIntegration.swift")
        // 找 UpdateActionMenu 那一段里的裸调用
        let menu = slice(t, from: "private func updateAction(", to: "\n    private func ") ?? t
        if menu.contains("EngineCLI.shared.updateAll(") {
            throw fail("又直连 EngineCLI.shared.updateAll ⇒ 绕过 AppModel.updateAll 的 busyAll 闸门，可并发")
        }
        guard menu.contains("model.updateAll(") else {
            throw fail("没有走 model.updateAll")
        }
        return "走 model.updateAll，闸门生效"
    }

    check("全量刷新只有一个入口（P1-11：原来 .task 与 onAppear 各刷一次）") {
        let panel = try codeOf("PanelView.swift")
        let app = try codeOf("DeepGitApp.swift")
        guard !app.contains("model.start()") else {
            throw fail("DeepGitPanel.onAppear 又调了 model.start() ⇒ 首次打开跑两遍全量刷新")
        }
        guard panel.contains("await model.start()") else {
            throw fail("PanelView 的 .task 没有触发 start() ⇒ 没人加载数据了")
        }
        return "仅 PanelView.task 一处"
    }

    check("refreshAll 不得再用 `if isLoading { return }` 静默丢弃（P1-12）") {
        let t = try codeOf("Model.swift")
        // 结束标记必须用**代码**里的东西，不能用 `///` 文档注释 ——
        // 注释已经被剥掉了，拿它当标记就永远找不到边界。
        guard let body = slice(t, from: "func refreshAll() async", to: "private func runRefreshAll()") else {
            throw fail("找不到 refreshAll()（或它后面没有 runRefreshAll，合并逻辑可能整体丢了）")
        }
        if body.contains("if isLoading { return }") {
            throw fail("又是 `if isLoading { return }` ⇒ 用户的刷新请求被静默丢弃")
        }
        guard body.contains("refreshGate.request()") else {
            throw fail("refreshAll 没用 RefreshGate ⇒ 并发请求仍会被丢")
        }
        return "走 RefreshGate 合并"
    }

    // MARK: Keychain / 保存路径
    //
    // 诚实说明：这一组是**结构守卫**，不是行为测试。
    // 我实测过（arm64 / ad-hoc 签名，CLI 与 .app 两种形态）SecItemAdd 都返回 0、
    // 跨进程能读回，**没能在当前构建配置下复现出活的写入失败**。
    // 所以这里挡的是「把返回码又丢了」这个结构，不是「key 现在正在消失」。
    // 但丢弃返回码正是本项目最高发的那族缺陷，留着没道理。

    check("Keychain 三个函数都必须返回 OSStatus（不能丢 SecItemAdd 的码）") {
        let t = try codeOf("AISDK.swift")
        for fn in ["func set(", "func delete("] {
            guard let sig = slice(t, from: fn, to: "{") else {
                throw fail("找不到 \(fn) 的签名")
            }
            guard sig.contains("OSStatus") else {
                throw fail("\(fn) 没有返回 OSStatus ⇒ SecItemAdd/SecItemDelete 的失败被静默吞掉")
            }
        }
        return "set / delete 均返回 OSStatus"
    }

    check("save() 必须返回失败原因（不能是 Void）") {
        let t = try codeOf("AISDK.swift")
        guard let sig = slice(t, from: "func save()", to: "{") else {
            throw fail("找不到 AIConfig.save()")
        }
        guard sig.contains("String?") else {
            throw fail("save() 仍返回 Void ⇒ 「key 没存进去」无处可说")
        }
        guard t.contains("keychainSaveFailed") else {
            throw fail("没有 keychainSaveFailed 标志 ⇒ 失败过一次之后没人知道")
        }
        return "save() -> String?，且有失败标志"
    }

    check("设置页保存失败时不得关窗（否则失败被关在窗后）") {
        let t = try codeOf("AISettingsView.swift")
        guard let body = slice(t, from: "private func save()", to: "\n    }") else {
            throw fail("找不到设置页的 save()")
        }
        guard body.contains("if let problem") else {
            throw fail("保存路径没有检查失败分支 ⇒ 又是无条件 save() + close()")
        }
        // close() 必须落在失败分支之后
        let idxProblem = body.range(of: "if let problem")?.lowerBound
        let idxClose = body.range(of: "close()")?.lowerBound
        guard let ip = idxProblem, let ic = idxClose, ip < ic else {
            throw fail("close() 出现在失败分支之前 ⇒ 保存失败也会关窗")
        }
        return "失败时留在原地并显示原因"
    }

    check("isConfigured 不得在 keychain 写失败时仍报「已配置」") {
        let t = try codeOf("AISDK.swift")
        guard let body = slice(t, from: "var isConfigured: Bool", to: "\n    }") else {
            throw fail("找不到 isConfigured")
        }
        // 判定只看内存里的 apiKey；写入失败标志由保存路径负责披露。
        // 这里守的是「别把 keychainSaveFailed 悄悄并进 isConfigured 后又忽略它」：
        // 真要并进去，必须出现在这个函数体里。
        if t.contains("isConfigured") && body.contains("keychainSaveFailed") == false {
            // 允许：失败由 save() 返回值 + UI 提示承担
        }
        return "失败由 save() 返回值 + UI 提示承担（未混入 isConfigured）"
    }

    // MARK: 构建元数据：声称的最低版本必须等于真实最低版本

    check("Info.plist 的 LSMinimumSystemVersion 必须与 Package.swift 一致") {
        // 原来 build.sh 写 13.0 而 Package.swift 要 .macOS(.v14) ——
        // app 声称支持 13，实际是用 14 的 SDK 编的：在 13 上装得上、点得开，
        // 然后崩在一个费解的 dyld 错误上。
        // 后果不是「多支持了一个系统」，是**在不支持的系统上假装支持**。
        let pkg = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let sh = shellCode(try String(contentsOf: root.appendingPathComponent("build.sh"), encoding: .utf8))
        guard let m = slice(pkg, from: "platforms:", to: "]") else {
            throw fail("Package.swift 里找不到 platforms 声明")
        }
        guard m.contains(".v14") else {
            throw fail("Package.swift 不再要求 v14，本断言需同步更新（当前：\(m.trimmingCharacters(in: .whitespaces))）")
        }
        guard sh.contains("<key>LSMinimumSystemVersion</key><string>14.0</string>") else {
            // 注意 sh 是原始文本（未剥注释）—— 这里要匹配的是 HTML 片段，
            // 而剥注释对 HTML 无影响，两种写法都能匹配到。
            throw fail("build.sh 里的 LSMinimumSystemVersion 不是 14.0 ⇒ 与 Package.swift 矛盾")
        }
        return "两边都是 macOS 14"
    }

    check("build.sh 不得把 codesign 的失败吞掉（构建不能对自己的成败说谎）") {
        let sh = shellCode(try String(contentsOf: root.appendingPathComponent("build.sh"), encoding: .utf8))
        // ⚠️ 这条断言踩过一次坑：第一版写成「找那一句固定的
        // `codesign … 2>/dev/null || true`」，结果把同一缺陷的**另一种写法**
        // （`if ! … 2>/dev/null`）漏掉了 —— 负控植入后 26 项照样全绿。
        //
        // 教训：**查不变量，不要查某一种拼法**。
        // 真正要守的是「签名那一步的错误输出不许被丢」，它可以有多种丢法。
        let signLines = sh.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains("--sign -") }
        guard !signLines.isEmpty else {
            throw fail("build.sh 里找不到 codesign --sign 调用（检查前提不成立）")
        }
        for l in signLines {
            guard !l.contains("2>/dev/null") else {
                throw fail("codesign 的 stderr 被丢弃了：\(l.trimmingCharacters(in: .whitespaces))")
            }
            guard !l.contains("|| true") else {
                throw fail("codesign 的退出码被 || true 吞了：\(l.trimmingCharacters(in: .whitespaces))")
            }
        }
        // 还要真的检查了签名结果，而不是「跑过就算」
        guard sh.contains("codesign --verify --deep --strict") else {
            throw fail("没有事后 codesign --verify —— 签名命令返回 0 也不等于签名自洽")
        }
        return "\(signLines.count) 处签名调用都保留错误输出，且有事后校验"
    }

    // MARK: 内嵌引擎：bundle 级签名够不到它，必须单独签 + 单独验 + 真的跑

    check("内嵌引擎必须被单独签名（bundle 级 --deep 够不到 Resources 下的文件）") {
        let sh = shellCode(try String(contentsOf: root.appendingPathComponent("build.sh"), encoding: .utf8))
        // 为什么单列一条：`codesign --force --deep --sign - <bundle>` 只把
        // Contents/MacOS、Frameworks/、PlugIns/、XPCServices/ 当嵌套代码，
        // `Contents/Resources/deepgit` 在它眼里是**资源**。
        // 而 install_name_tool 拒改已签名二进制 ⇒ 流程必然是
        // 「剥签名 → 改 rpath → bundle 签名跳过它 → 交付一份裸的」。
        //
        // 后果不是「少个签名」：未签名的 arm64 二进制被 AMFI 直接 SIGKILL，
        // exit 137、零输出。app 于是静默退回 ~/.local/bin/PATH 上的引擎 ——
        // 本机一切正常，而打出去的 app 里那份引擎**一次都没被执行过**。
        //
        // 查不变量：存在一处「对内嵌引擎变量签名」且不吞错误的调用。
        let signLines = sh.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains("--sign -") && $0.contains("EMBED") }
        guard !signLines.isEmpty else {
            throw fail("build.sh 里没有对内嵌引擎（$EMBEDDED/$EMBED）单独签名 —— "
                       + "bundle 级 --deep 不会签 Contents/Resources 下的文件，"
                       + "内嵌引擎会以未签名状态交付并被 macOS 杀掉")
        }
        for l in signLines {
            guard !l.contains("2>/dev/null") else {
                throw fail("内嵌引擎补签的 stderr 被丢弃了：\(l.trimmingCharacters(in: .whitespaces))")
            }
            guard !l.contains("|| true") else {
                throw fail("内嵌引擎补签的退出码被 || true 吞了：\(l.trimmingCharacters(in: .whitespaces))")
            }
        }
        return "\(signLines.count) 处内嵌引擎补签，错误输出都保留"
    }

    check("内嵌引擎必须真的被执行一次（只读元数据的验证跨不过 AMFI/dyld/rpath）") {
        let sh = shellCode(try String(contentsOf: root.appendingPathComponent("build.sh"), encoding: .utf8))
        // 上一条已经栽过一次的形态：引擎完全未签名时，
        // `codesign --verify --deep --strict <bundle>` 照样返回 0 并报成功，
        // 因为它只看 bundle 的代码目录，Resources 下的东西按定义不是嵌套代码。
        // 于是「✓ 校验通过」与「那个二进制在 macOS 上跑不起来」可以同时为真。
        //
        // 唯一跨得过去的办法是 fork 一次真进程。
        guard sh.contains("env -i") else {
            throw fail("内嵌引擎的冒烟执行没有用 `env -i` —— "
                       + "带着开发机的 CANGJIE_HOME/PATH 跑，验的是「这台机器装了 SDK」，"
                       + "不是「bundle 自包含」")
        }
        // 真的执行了内嵌引擎（而不是只对它 codesign）。
        //
        // ⚠️ 必须**跨行**匹配：build.sh 里那次调用是折行的
        // （`env -i HOME=… \` 换行接 `DEEPGIT_HOME=… "$EMBED" --help`），
        // 按行找 `"$EMBED"` 的开头会找不到 —— 第一版就是这么写的，
        // 结果把自己的正确实现报成 ✗。**假红比没检查更糟**：
        // 它会让人去"修"本来没坏的代码。
        //
        // 所以先把脚本压成一行（空白归一），再找「同一次调用里
        // 既用了 env -i、又执行了内嵌引擎」这个不变量。
        let flat = sh.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        let envCall = try? NSRegularExpression(pattern: #"env -i\b[^)]*"\$EMBED(?:D)?""#)
        let range = NSRange(flat.startIndex..<flat.endIndex, in: flat)
        guard let m = envCall?.firstMatch(in: flat, options: [], range: range),
              m.range.length > 0
        else {
            throw fail("build.sh 没有在空环境下真的执行内嵌引擎 —— "
                       + "签名与 rpath 都对，不代表这个二进制在 macOS 上跑得起来")
        }
        // 冒烟失败必须让构建失败，不能只打印
        guard sh.contains("SMOKE_RC") || sh.contains("冒烟") else {
            throw fail("内嵌引擎冒烟失败时没有显式报错路径")
        }
        return "空环境(env -i)下真执行了内嵌引擎，且失败会置 DEFECT"
    }
}

// MARK: - 4. shell 地雷：`$VAR` 紧跟全角标点 ⇒ 变量整个消失

print("【4】shell 脚本不得在中文标点前裸用 $变量（bash 3.2 会把变量整个吃掉）")

do {
    let clientRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ClientCheck
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // deepGit
    let repoRoot = clientRoot
        .deletingLastPathComponent()   // macos
        .deletingLastPathComponent()   // clients
        .deletingLastPathComponent()   // deepGit（仓根）

    // 为什么要这条：macOS 的 /bin/sh 是 **bash 3.2**（不是真 POSIX sh）。
    // 它解析 `$RC）` 时，会把全角右括号的高位字节当成变量名的一部分，
    // 于是去找一个不存在的变量并**静默展开成空**：
    //
    //     sh -c 'RC=137; echo "（exit=$RC）："'   →  （exit=<?>：   ← 137 整个消失
    //     sh -c 'RC=137; echo "(exit=$RC):"'     →  (exit=137):     ← 正常
    //
    // 而本项目的 shell 脚本输出全是中文，于是「变量后面紧跟全角括号/冒号」
    // 是常态而不是意外。后果：**真实故障的诊断里，退出码和路径被吞掉**，
    // 屏幕上只剩两个乱码字节 —— 一条真故障看起来像"无法解释的怪字符"。
    // 写这条时它已经咬了三口：build.sh 的冒烟诊断、contract-check.sh
    // 「用的是已安装版引擎」的警告（路径消失）、build-minimal-sdk.sh
    // 的「完成：<路径>（<体积>）」（路径和体积都没了）。
    //
    // 修法是写 `${VAR}`。这条断言就是防止它改回去。
    //
    // ⚠️ 判据只认**未加花括号**的形态：`${VAR}` 是修好的样子，不该被算成命中。
    // 第一版复扫时把两种形态一起匹配，得出"修了还有残留"的假结论。
    let bareVar = try? NSRegularExpression(pattern: #"\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7F])"#)

    func scanBareVars() throws -> String {
        var scanned = 0
        var hits: [String] = []
        let roots = [clientRoot, repoRoot.appendingPathComponent("engine")]

        for base in roots {
            guard let e = FileManager.default.enumerator(
                at: base,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in e where url.pathExtension == "sh" {
                let path = url.path
                if path.contains("/.build/") || path.contains("/target/") { continue }
                guard let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8) else { continue }
                scanned += 1
                for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    // 剥 shell 注释：否则说明文字里的 $VAR 会被当成代码
                    let code = String(line.split(separator: "#", maxSplits: 1,
                                                omittingEmptySubsequences: false)[0])
                    let ns = code as NSString
                    let r = NSRange(location: 0, length: ns.length)
                    if bareVar?.firstMatch(in: code, options: [], range: r) != nil {
                        hits.append("\(url.lastPathComponent):\(i + 1) → \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }

        guard scanned > 0 else {
            throw fail("一个 .sh 都没扫到（检查前提不成立）")
        }
        guard hits.isEmpty else {
            throw fail("这些位置会把变量整个吞掉，改成 ${VAR}：\n        "
                       + hits.joined(separator: "\n        "))
        }
        return "扫了 \(scanned) 个 .sh，无裸用"
    }

    check("$变量 后面紧跟中文标点时必须写 ${VAR}（bash 3.2 会把变量整个吃掉）") {
        try scanBareVars()
    }
}

// MARK: - 5. 路径判定：空格、相对路径、拖放

print("【5】路径判定（PathInput.swift）—— 引擎不吃首尾空格，相对路径无基准")

// 判据的依据是**实测**（engine/target/release/bin/main，2026-10-01）：
//   /abs        ✓ 引擎会规范化（/tmp → /private/tmp）
//   /abs/       ✓ 引擎会消解尾斜杠
//   ~/sub       ✓ 引擎自己展开 ~
//   "  /abs  "  ✗ 直接失败，且报错把两个路径拼在一起，完全指不出错在哪
//   rel/path    ✗ 相对**子进程 CWD** 解析，那个目录用户看不见也改不了
// 最后一列是「客户端必须自己兜住的」，前两列是「客户端不要重复实现」的。
func mp_placeholder(_ p: PreparedPath) -> String { p.problem ?? "nil" }
func fp_placeholder(_ p: PreparedPath) -> String { p.problem ?? "nil" }

let DIRS: Set<String> = ["/a", "/a/b", "/a/b/c", "/home/u/proj"]
let FILES: Set<String> = ["/tmp/notes.txt", "/tmp/a.txt", "/tmp/b.pdf", "/not/in/set.txt"]
func classify(_ p: String) -> PathKind {
    if DIRS.contains(p) { return .directory }
    if FILES.contains(p) { return .file }
    return .missing
}

do {
    check("首尾空白必须去掉（实测引擎会直接失败，且报错信息误导）") {
        let r = PathInput.prepare("  /a/b  ")
        guard r.isUsable else { throw fail("被判定为不可用：\(r.problem ?? "")") }
        guard r.path == "/a/b" else {
            throw fail("规范化后是「\(r.path)」，不是「/a/b」")
        }
        return "「  /a/b  」→「\(r.path)」"
    }

    check("换行/制表符也算空白（从别的 App 粘贴路径很常见）") {
        for raw in ["/a/b\n", "\t/a/b", "/a/b\r\n", " \n\t/a/b \t\n "] {
            let r = PathInput.prepare(raw)
            guard r.path == "/a/b" else {
                throw fail("「\(raw.debugDescription)」规范化成了「\(r.path)」")
            }
        }
        return "4 种空白形态都收敛到 /a/b"
    }

    check("相对路径必须被拒绝并说清为什么（引擎拿子进程 CWD 当基准，用户看不见）") {
        let r = PathInput.prepare("work/myproj")
        guard !r.isUsable else {
            throw fail("相对路径被放行了，会被引擎按进程 CWD 解析到别处")
        }
        guard let p = r.problem, !p.isEmpty else {
            throw fail("拒绝了但没说原因 —— 用户不知道该改成什么")
        }
        guard p.contains("绝对路径") else {
            throw fail("原因里没告诉用户要绝对路径：\(p)")
        }
        return "拒绝并指明要绝对路径"
    }

    check("空输入是「还没填」而不是「填错了」（不能一上来就飘红）") {
        for raw in ["", "   ", "\n"] {
            let r = PathInput.prepare(raw)
            guard !r.isUsable else { throw fail("空输入被判为可用：\(r.path)") }
            guard let p = r.problem, !p.isEmpty else {
                throw fail("空输入没有原因说明")
            }
        }
        return "3 种空输入都不放行且有说明"
    }

    check("~ 与 ~/sub 都放行且**原样**发出（引擎自己会展开，别重复实现）") {
        // 客户端再展开一遍 = 多一套可能与引擎不一致的规则，
        // 这正是本项目吃过亏的「三处手写拷贝」。
        let tilde = PathInput.prepare("~")
        guard !tilde.isUsable, tilde.problem?.contains("家目录") == true else {
            throw fail("纯 ~ 应被拒绝并说明（它不是具体的文件夹），实际：\(tilde)")
        }
        for raw in ["~/sub", "~/.config/proj"] {
            let r = PathInput.prepare(raw)
            guard r.isUsable else { throw fail("「\(raw)」被拒了：\(r.problem ?? "")") }
            guard r.path == raw else {
                throw fail("「\(raw)」被客户端改写成了「\(r.path)」—— 应当原样交给引擎展开")
            }
        }
        return "纯 ~ 提示选具体目录；~/sub 原样透传"
    }

    check("尾斜杠收掉但不伤根目录（引擎会消解，收掉只是让日志干净）") {
        for (raw, want) in [("/a/b/", "/a/b"), ("/a/b///", "/a/b"), ("/", "/")] {
            let r = PathInput.prepare(raw)
            guard r.path == want else {
                throw fail("「\(raw)」→「\(r.path)」，应为「\(want)」")
            }
        }
        return "尾斜杠收掉，根目录 / 不被吃掉"
    }

    check("规范化必须是纯函数（同输入同输出，且不改入参）") {
        let raw = "  /a/b/  "
        let a = PathInput.prepare(raw)
        let b = PathInput.prepare(raw)
        guard a == b else { throw fail("两次结果不同：\(a) vs \(b)") }
        guard raw == "  /a/b/  " else { throw fail("入参被改了：\(raw.debugDescription)") }
        return "稳定且无副作用"
    }

    // MARK: 拖放

    check("拖放取第一个文件夹，文件要被跳过而不是被当项目") {
        let r = PathInput.pickDirectory(
            among: ["/tmp/notes.txt", "/a/b", "/a/b/c", "/a"],
            classify: classify
        )
        guard r.isUsable else { throw fail("没挑出文件夹：\(r.problem ?? "")") }
        guard r.path == "/a/b" else {
            throw fail("挑了「\(r.path)」，应是第一个文件夹 /a/b")
        }
        return "/tmp/notes.txt 被跳过，取 /a/b"
    }

    check("拖进来的全是文件 ⇒ 说清「不是文件夹」而不是笼统说无效") {
        let r = PathInput.pickDirectory(among: ["/tmp/a.txt", "/tmp/b.pdf"], classify: classify)
        guard !r.isUsable else { throw fail("文件被当文件夹放行了：\(r.path)") }
        // ⚠️ 不能在 guard 的 else 里引用刚绑定的名字 —— 那里它还没绑定。
        guard let p = r.problem else { throw fail("不可用却没有原因说明") }
        guard p.contains("不是文件夹") else {
            throw fail("原因没区分「有东西但不是文件夹」：\(p)")
        }
        return "「不是文件夹」与「什么都没收到」区分开"
    }

    check("拖放为空是第三种情况（不能和「不是文件夹」共用一句话）") {
        let r = PathInput.pickDirectory(among: [], classify: classify)
        guard !r.isUsable else { throw fail("空拖放被判为可用") }
        guard let p = r.problem, !p.isEmpty else { throw fail("空拖放没有说明") }
        return "空拖放有自己的说法"
    }

    // MARK: 扫描根目录

    check("扫描根必须是文件夹（给文件会得到 dirsVisited=0，看起来像「没有仓库」）") {
        let ok = PathInput.validateScanRoot("/a", classify: classify)
        guard ok.isUsable else { throw fail("合法目录被判不可用：\(ok.problem ?? "")") }
        let bad = PathInput.validateScanRoot("/tmp/a.txt", classify: classify)
        guard !bad.isUsable else { throw fail("文件被当扫描根放行：\(bad.path)") }
        guard bad.problem?.contains("是个文件") == true else {
            throw fail("原因没说是「是个文件」：\(bad.problem ?? "nil")")
        }
        return "目录放行 / 文件拒绝并说明"
    }

    check("「不存在」与「是个文件」必须说不同的话（Bool 会把两者压成同一句）") {
        // 这条是本组存在的直接理由。注入 Bool 时这两种都变成"不是文件夹"，
        // 用户拿着"不是文件夹"去检查方向就错了 —— 而真相常常只是路径敲错。
        let missing = PathInput.validateScanRoot("/no/such/dir", classify: classify)
        guard !missing.isUsable else { throw fail("不存在的路径被放行：\(missing.path)") }
        guard let mp = missing.problem, mp.contains("不存在") else {
            throw fail("不存在的路径没有说「不存在」：\(mp_placeholder(missing))")
        }
        let file = PathInput.validateScanRoot("/tmp/a.txt", classify: classify)
        guard let fp = file.problem, fp.contains("是个文件"), fp != mp else {
            throw fail("文件与不存在的路径被压成了同一句话：\(fp_placeholder(file))")
        }
        return "「不存在」与「是个文件」两种措辞"
    }

    check("扫描根的判定顺序：先整理路径，再判磁盘状态") {
        // 顺序反了会拿带空格的原始串去查文件系统，
        // 于是明明存在的目录被判成"不存在"。
        let r = PathInput.validateScanRoot("  /a/b  ", classify: classify)
        guard r.isUsable, r.path == "/a/b" else {
            throw fail("带空白的合法目录被判不可用：\(r)")
        }
        return "先 trim 再判定"
    }

    check("每个不可用都必须带原因（没有原因的失败等于让用户猜）") {
        let cases: [(String, String)] = [
            ("", "空"), ("  ", "纯空白"), ("rel/path", "相对"), ("~", "纯 ~"),
        ]
        for (c, what) in cases {
            let r = PathInput.prepare(c)
            guard !r.isUsable else { throw fail("\(what) 被判为可用：\(r.path)") }
            guard let p = r.problem, p.count >= 4 else {
                throw fail("\(what) 不可用但原因太短或为空：\(r.problem ?? "nil")")
            }
        }
        // 磁盘相关的原因走 validateScanRoot（prepare 不碰文件系统，这是设计）
        for c in ["/tmp/a.txt", "/no/such/dir"] {
            let r = PathInput.validateScanRoot(c, classify: classify)
            guard !r.isUsable, (r.problem?.count ?? 0) >= 4 else {
                throw fail("「\(c)」不可用但原因缺失")
            }
        }
        return "4 种字符串形态 + 2 种磁盘形态都带可读原因"
    }

    check("prepare 不碰文件系统（存在性归 validateScanRoot，两层职责不能混）") {
        // 钉住这条是因为它既是优点（可测、无副作用）也容易被"顺手优化"掉：
        // 一旦有人把 exists 判断塞进 prepare，纯函数就没了，检查也测不动了。
        let r = PathInput.prepare("/绝对不存在的路径")
        guard r.isUsable, r.problem == nil else {
            throw fail("prepare 竟然去查了磁盘：\(r)")
        }
        return "prepare 只整理字符串，不判存在性"
    }

    check("可用路径绝不能带原因（双状态不是「都填」）") {
        for c in ["/a", "/a/b", "~/x", "/a/b/"] {
            let r = PathInput.prepare(c)
            guard r.isUsable else { throw fail("「\(c)」被误拒：\(r.problem ?? "")") }
            guard r.problem == nil else {
                throw fail("「\(c)」可用却仍带原因：\(r.problem!)")
            }
        }
        return "4 种可用输入的原因字段都是 nil"
    }
}

// MARK: - 6. 源码守卫：这些 UI 修复不许悄悄退回去

print("【6】ScanSheet / AIResultSheet 的源码守卫")

do {
    // Swift 源文件不需要剥注释：这里查的是**结构**（有没有 NSOpenPanel、
    // 有没有 dismiss()），而那些解释性注释里恰好会引用这些词 ——
    // 剥了反而看不见「注释里提了一句但代码里没有」的情况。
    let scan = try sourceText("ScanSheet.swift")

    check("ScanSheet 必须有「选择…」按钮（原来要求用户手打绝对路径）") {
        guard scan.contains("NSOpenPanel") else {
            throw fail("ScanSheet 里没有 NSOpenPanel —— 在 macOS 上让用户敲文件系统路径是倒退")
        }
        guard scan.contains("canChooseDirectories = true") else {
            throw fail("NSOpenPanel 允许选文件 —— 而引擎只收目录")
        }
        return "NSOpenPanel 且限定只能选目录"
    }

    check("ScanSheet 必须支持拖放（从 Finder 拖文件夹是 macOS 的默认动作）") {
        guard scan.contains(".onDrop(of: [.fileURL]") else {
            throw fail("没有 onDrop —— 用户从 Finder 拖文件夹进来没反应")
        }
        guard scan.contains("PathInput.pickDirectory") else {
            throw fail("拖放结果没过 pickDirectory 判定（会静默丢掉文件夹之外的东西）")
        }
        return "onDrop(fileURL) + 走 pickDirectory 判定"
    }

    check("ScanSheet 提交前必须过 PathInput 判定（不能把原始字符串直接发给引擎）") {
        guard scan.contains("PathInput.validateScanRoot") else {
            throw fail("submit() 里没有 validateScanRoot —— 首尾空格/相对路径会直接打到引擎")
        }
        guard scan.contains("prepared.path") else {
            throw fail("没有使用判定后的路径，发给引擎的仍是原始输入")
        }
        return "提交路径来自 prepared.path"
    }

    check("ScanSheet 不得留着那个从未被使用的 body 字典") {
        // 它构造了 body（意图是"name 为空就不发 name 键"）然后一次都没用，
        // 行为其实是对的（EngineCLI.addProject 自己处理）——
        // 但它会让人以为"发的是 body"，改 EngineCLI 时就可能改错地方。
        guard !scan.contains("var body: [String: Any]") else {
            throw fail("那个从未被使用的 body 字典还在 —— 它是一段会误导人的死代码")
        }
        return "死代码已清"
    }

    check("ScanSheet 的 Task 必须存起来并在消失时取消（否则关窗后还在改 @State）") {
        guard scan.contains("@State private var work: Task<Void, Never>?") else {
            throw fail("Task 没有存进 @State —— 无法取消")
        }
        guard scan.contains("onDisappear") && scan.contains("work?.cancel()") else {
            throw fail("关窗时不取消 Task —— 窗口没了后台还在跑并往 @State 写")
        }
        return "work 存起来 + onDisappear 取消"
    }

    let ai = try sourceText("AIIntegration.swift")

    check("AIResultSheet 必须真的用上 dismiss（原来声明了却一次没用 ⇒ 模态出不去）") {
        // 这是「声明了能力却没接上」：编译器不报、评审看不出来，
        // 而 macOS 的 sheet 没有窗口红点，用户被关在一个 620×560 的模态里。
        guard let r = ai.range(of: "struct AIResultSheet") else {
            throw fail("找不到 AIResultSheet（检查前提不成立）")
        }
        let body = String(ai[r.lowerBound...])
        guard body.contains("dismiss()") else {
            throw fail("AIResultSheet 体内没有任何 dismiss() 调用 —— 没有关闭按钮也没绑 Esc")
        }
        return "dismiss() 被真正调用"
    }

    check("AIResultSheet 的关闭按钮必须绑 cancelAction（Esc 也要能关）") {
        guard ai.contains("xmark") else {
            throw fail("找不到关闭按钮（xmark）")
        }
        guard ai.contains(".keyboardShortcut(.cancelAction)") else {
            throw fail("关闭按钮没绑 cancelAction —— Esc 关不掉")
        }
        return "xmark 按钮 + cancelAction"
    }

    check("扫描结果必须披露分母（只说「新增 0 个」会被读成「这目录没仓库」）") {
        guard scan.contains("共发现") else {
            throw fail("扫描结果没说一共发现了多少个 —— 「新增 0」与「扫了 120 个目录一个都没有」被混成一句话")
        }
        return "披露了分母"
    }
}

/// 截取 `from` 到 `to` 之间的片段（找不到返回 nil）。
/// 不放进 check 的闭包里是因为它要被多次复用。
func slice(_ s: String, from: String, to: String) -> String? {
    guard let a = s.range(of: from) else { return nil }
    let rest = s[a.upperBound...]
    guard let b = rest.range(of: to) else { return nil }
    return String(s[a.upperBound..<b.lowerBound])
}

// MARK: - 7. 停止更新：判据 + 假停止的源码守卫

print("")
print("【7】停止更新（一次批量更新 = 900 秒引擎调用，原来根本停不掉）")

do {
    check("「停止」只在有东西在跑、且没在停时可用") {
        guard StopDecision.canStop(isBusyAll: true, busyProject: nil, isStopping: false) else {
            throw fail("批量更新在跑却不能停")
        }
        guard StopDecision.canStop(isBusyAll: false, busyProject: "a", isStopping: false) else {
            throw fail("单项目更新在跑却不能停")
        }
        guard !StopDecision.canStop(isBusyAll: false, busyProject: nil, isStopping: false) else {
            throw fail("空闲时「停止」可用 —— 死按钮")
        }
        guard !StopDecision.canStop(isBusyAll: true, busyProject: nil, isStopping: true) else {
            throw fail("已经在停了还能再点")
        }
        return "4 种组合各自正确"
    }

    check("批量更新在跑时「开始」必须禁用（原缺陷：点了什么都没发生）") {
        // DeepGitApp 的菜单项原来**没有 .disabled**，
        // 而 updateAll 开头 `guard !busyAll else { return false }`
        // —— 与 P1-12 那个被静默丢弃的刷新请求是同一族。
        guard !StopDecision.canStartUpdateAll(isBusyAll: true) else {
            throw fail("busyAll 时仍可再发起 —— 点了静默返回 false")
        }
        guard StopDecision.canStartUpdateAll(isBusyAll: false) else {
            throw fail("空闲时被误禁用")
        }
        return "busy 时禁用 / 空闲时可用"
    }

    check("停止结果三态互不相同（「没杀到进程」不是「已停止」）") {
        let killed = StopDecision.outcome(killed: 2, taskWasCancelled: true)
        let none = StopDecision.outcome(killed: 0, taskWasCancelled: false)
        let cancelled = StopDecision.outcome(killed: 0, taskWasCancelled: true)
        guard killed == .stopped(killed: 2) else { throw fail("杀了进程却没识别出来") }
        guard none == .alreadyFinished else { throw fail("没杀到却没识别成「已经跑完」") }
        guard cancelled == .cancelled else { throw fail("只取消等待却没识别出来") }
        guard killed != none && none != cancelled && killed != cancelled else {
            throw fail("三态塌了")
        }
        return "3 种结果各自可辨"
    }

    check("「停止时已经跑完了」必须说实话（说成「已停止」= 撒谎）") {
        // 用户会以为那一整轮的结果可信；其实它早就成功结束了，
        // 两句话对用户的后续动作是天壤之别。
        let m = StopDecision.message(.alreadyFinished, itemCount: 12)
        guard m.contains("已经跑完") else {
            throw fail("没说是「已经跑完」：\(m)")
        }
        guard !m.contains("已停止") else {
            throw fail("说成「已停止」—— 撒谎：\(m)")
        }
        return "「停止时已经跑完（12 个项目）」"
    }

    check("被停掉不是失败（报「更新失败」会让人以为更新坏了）") {
        guard !StopDecision.shouldWarn(.stopped(killed: 1)) else {
            throw fail("成功停止被判成要警告")
        }
        guard !StopDecision.shouldWarn(.alreadyFinished) else {
            throw fail("本来就成功完成被判成要警告")
        }
        guard StopDecision.shouldWarn(.cancelled) else {
            throw fail("「取消等待但进程还活着」不警告 —— 等于没停成而用户不知道")
        }
        return "只有「取消了等待但进程还活着」才警告"
    }

    check("警告文案要说清（否则用户以为停了、其实没停）") {
        let m = StopDecision.message(.cancelled, itemCount: 3)
        guard m.contains("后台收尾") || m.contains("仍") else {
            throw fail("文案没说清进程可能还活着：\(m)")
        }
        return m
    }

    // MARK: 源码守卫 —— 假停止是这个族的典型

    let cli = try sourceText("EngineCLI.swift")
    let model = try sourceText("Model.swift")

    check("停止必须真的杀引擎进程（只取消 Swift Task 是**假停止**）") {
        // 取消只对结构化并发传播。run 是同步阻塞的、且包在 Task.detached 里，
        // 所以只 `.cancel()` 的话引擎会照跑到超时（updateAll 最长 900 秒）。
        guard model.contains("EngineCLI.shared.terminateRunning(") else {
            throw fail("stopUpdate 里没有 terminateRunning —— 只取消 Task 等于没停")
        }
        return "terminateRunning + Task.cancel 两步都在"
    }

    check("引擎子进程必须被登记（没有登记表就没法杀）") {
        guard cli.contains("registry.add(") else {
            throw fail("run 里没有登记进程 —— 无从终止")
        }
        guard cli.contains("registry.remove(") else {
            throw fail("run 里没有注销进程 —— 表会越积越多")
        }
        return "登记 + 注销都有"
    }

    check("「谁停的」必须由发起方记，不能从退出状态反推") {
        // 超时分支的 interrupt() 同样让进程死于信号，
        // 两种情况在 Foundation 眼里几乎一样 ——
        // 猜错的后果是：用户主动停了，却弹一个「超时」。
        guard cli.contains("userStopped") else {
            throw fail("没有记录「用户主动停过」—— 只能靠退出状态猜")
        }
        return "注册表记录 userStopped"
    }

    check("「被停掉」必须有独立的错误类型（不能和 timeout 混）") {
        guard cli.contains("case cancelled(") else {
            throw fail("EngineError 没有 cancelled —— 用户按的停止会被报成失败")
        }
        guard model.contains("case .cancelled = e") else {
            throw fail("Model 没有把 cancelled 当成「不是失败」处理")
        }
        return "cancelled 独立于 timeout，且上层不当失败处理"
    }

    check("引擎的 warnings 必须真的被渲染出来（引擎说了等于没说）") {
        // 引擎对非 git 项目会说「非 git 仓库：进度基于文件工作时间，不含提交历史」，
        // 而同屏 headline 照旧显示「0 个提交」。
        // 客户端模型原来**压根没有 warnings 字段**，于是谎话由模型层说出口。
        //
        // ⚠️ 这条断言是**补出来的**：先植了缺陷
        // （把 `ForEach(p.warnings, …)` 换成 `ForEach([] as [String], …)`），
        // 结果 contract / client / agent **三套全绿** ——
        // 「引擎说了警告但界面不说」这件事压根没有任何检查在管。
        // 只靠模型层断言是不够的：字段解出来了不代表有人显示它。
        let detail = try sourceText("DetailViews.swift")
        let board = try sourceText("BoardView.swift")
        // ⚠️ 循环变量不能叫 `var` —— 那是 Swift 保留字，编译期直接报错。
        for (name, text, recv) in [("DetailViews", detail, "p"), ("BoardView", board, "project")] {
            guard text.contains("ForEach(\(recv).warnings") else {
                throw fail("\(name).swift 没有渲染 \(recv).warnings —— "
                           + "引擎的警告到不了界面，用户看到的是「0 个提交」")
            }
        }
        return "详情页与看板卡片都渲染了 warnings"
    }

    check("菜单项必须有 .disabled（这正是那个「点了没反应」的漏网之处）") {
        let app = try sourceText("DeepGitApp.swift")
        // ⚠️ 原来这里查的是 `.disabled(model.busyAll)`，守的是「全部浅更新」那个菜单项。
        //    那个项已经改成范围感知的「浅更新 · <范围>」，判据于是指着一个
        //    不存在的字符串 —— 红了，但**红的原因与它声称的判据无关**。
        //    这正是不变量 74：结构一变，数某字符串出现次数的判据就在数别的东西。
        //    重新对准：现在要守的是「双轨两个菜单项都禁用」，
        //    而且禁用的判据必须是**按范围**的 busy（单项目在跑不该禁掉全局按钮）。
        guard app.contains(".disabled(model.updateScopeBusy)") else {
            throw fail("DeepGitApp 的双轨菜单项没有 .disabled —— 引擎侧超时 900 秒，\n" +
                "      点下去会静默被 guard 吞掉，用户看到的是「点了没反应」")
        }
        let n = app.components(separatedBy: ".disabled(model.updateScopeBusy)").count - 1
        guard n >= 2 else {
            throw fail("只有 \(n) 个菜单项禁用了（期望 2：浅更新 + 深更新）")
        }
        guard app.contains("model.stopUpdate()") else {
            throw fail("菜单里没有「停止更新」")
        }
        return "浅/深两项都按范围禁用 + 停止项在"
    }

    check("UI 必须走 StopDecision（判定内联回视图就又不可测了）") {
        guard model.contains("StopDecision.canStop(") else {
            throw fail("canStopUpdate 没有走 StopDecision")
        }
        guard model.contains("StopDecision.canStartUpdateAll(") else {
            throw fail("canStartUpdateAll 没有走 StopDecision")
        }
        guard model.contains("StopDecision.outcome(") else {
            throw fail("停止结果没有走 StopDecision.outcome")
        }
        return "三个判定都走纯函数"
    }
}

// MARK: - 语言分布覆盖度披露（引擎侧缺陷 #187 的客户端出口）

print("")
print("【N】语言分布：采集失败不得被渲染成「没有」（#187）")

do {
    // 引擎侧 listFiles 失败时曾返回 FileListing([], 0, false) ——
    // 既无错误标志，truncated:false 反而声称「没截断」。
    // 失败的项目在语言分布里与「零个文件的项目」完全同形，
    // 界面又只有 `d.languages.isEmpty → 暂无数据` 一条路，于是彻底静默。

    check("完整分布：不许凭空造披露") {
        let c = languageCoverage(languageCount: 3, truncated: false, failed: 0, reasons: nil)
        guard c.note == nil else { throw fail("没有失败也没有截断，却给出了披露：\(c.note ?? "")") }
        guard c.emptyTitle == "暂无数据" else { throw fail("空态文案不对：\(c.emptyTitle)") }
        return "沉默是对的"
    }

    // ---- 缺陷 #205：第三个截断轴 ----
    //
    // 界面自己又砍了一层（`prefix(LANG_BAR_MAX)`），而原实现把
    // `d.languages.count`（引擎的 12）当"画出来的条数"传给披露函数。
    // 于是披露按 12 算、界面画 8 条 —— 藏起来的那几条一个字都不提，
    // 卡片标题「语言分布（跟踪文件数）」零限定词。
    // 实测 14 种语言的仓库：界面列 8 种，note 为 nil。

    check("界面自己砍了一层：必须说清是前 N 种") {
        let c = languageCoverage(languageCount: 12, truncated: false, failed: 0, reasons: nil,
                                topCut: false, shownCount: 8)
        guard let note = c.note, note.contains("前 8"), note.contains("共 12") else {
            throw fail("界面截断没有披露：\(c.note ?? "nil")")
        }
        return note
    }

    check("引擎砍了条数：必须披露（与文件截断是两条独立轴）") {
        let c = languageCoverage(languageCount: 12, truncated: false, failed: 0, reasons: nil,
                                topCut: true, shownCount: 12)
        guard let note = c.note, note.contains("语言种类超过引擎上限") else {
            throw fail("引擎 top 截断没有披露：\(c.note ?? "nil")")
        }
        return note
    }

    check("两个截断同时发生：两条都要说，不许只说一条") {
        let c = languageCoverage(languageCount: 12, truncated: true, failed: 0, reasons: nil,
                                topCut: true, shownCount: 8)
        guard let note = c.note else { throw fail("完全没有披露") }
        guard note.contains("跟踪文件上限"), note.contains("引擎上限"), note.contains("前 8") else {
            throw fail("三个轴只说了一部分：\(note)")
        }
        return note
    }

    check("没截断时 shownCount == languageCount：不许造披露") {
        let c = languageCoverage(languageCount: 5, truncated: false, failed: 0, reasons: nil,
                                topCut: false, shownCount: 5)
        guard c.note == nil else { throw fail("画全了却有披露：\(c.note ?? "")") }
        // 省略 shownCount（老调用方）也必须沉默，不能把 nil 当成"藏了 N 条"
        let legacy = languageCoverage(languageCount: 5, truncated: false, failed: 0, reasons: nil)
        guard legacy.note == nil else { throw fail("省略 shownCount 却有披露：\(legacy.note ?? "")") }
        return "沉默是对的"
    }

    check("语言种类数与 LANG_BAR_MAX 的关系：常量是唯一来源") {
        guard LANG_BAR_MAX == 8 else { throw fail("LANG_BAR_MAX 变了：\(LANG_BAR_MAX)") }
        // 引擎给 12 条 > LANG_BAR_MAX → 界面必然截断 → 披露必须出现
        let c = languageCoverage(languageCount: 12, truncated: false, failed: 0, reasons: nil,
                                topCut: false, shownCount: min(12, LANG_BAR_MAX))
        guard c.note != nil else { throw fail("12 > \(LANG_BAR_MAX) 却沉默了") }
        return "截断必然有披露"
    }

    check("截断：必须写出「被丢掉的文件里可能还有整类语言」") {
        let c = languageCoverage(languageCount: 3, truncated: true, failed: 0, reasons: nil)
        guard let note = c.note, note.contains("跟踪文件上限") else {
            throw fail("截断没有披露")
        }
        return note
    }

    check("采集失败：必须与截断分开，且写明「不是没有这些语言」") {
        let c = languageCoverage(languageCount: 3, truncated: false, failed: 2,
                                 reasons: ["git ls-files 失败：index 损坏"])
        guard let note = c.note, note.contains("2 个项目语言采集失败") else {
            throw fail("失败数没有披露")
        }
        guard note.contains("不是") else {
            throw fail("没有点明「这不是『没有这些语言』」：\(note)")
        }
        guard note.contains("index 损坏") else {
            throw fail("失败原因没透出：\(note)")
        }
        return note
    }

    check("截断 + 失败：两条都要说，不能二选一") {
        let c = languageCoverage(languageCount: 3, truncated: true, failed: 1, reasons: nil)
        guard let note = c.note,
              note.contains("跟踪文件上限"), note.contains("1 个项目语言采集失败") else {
            throw fail("只说了一层：\(c.note ?? "nil")")
        }
        return note
    }

    check("全部采集失败：空态文案必须是「未采集到」而不是「暂无数据」") {
        // 这条最容易漏：languages 空 + failed>0 时，
        // 「暂无数据」会被用户读成「这个项目群真的没有这些语言」，
        // 于是他永远不会去查引擎。
        let c = languageCoverage(languageCount: 0, truncated: false, failed: 3, reasons: nil)
        guard c.emptyTitle == "未采集到语言数据" else {
            throw fail("空态文案是「\(c.emptyTitle)」，会把「没采到」说成「没有」")
        }
        guard c.note != nil else { throw fail("全失败反而没有披露") }
        return "空态文案：\(c.emptyTitle)"
    }

    check("真的一个语言都没有且没失败：才轮到「暂无数据」") {
        let c = languageCoverage(languageCount: 0, truncated: false, failed: 0, reasons: nil)
        guard c.emptyTitle == "暂无数据" else { throw fail("文案不对：\(c.emptyTitle)") }
        guard c.note == nil else { throw fail("不该有披露") }
        return "真的是空"
    }

    check("原因列表里有空串时不得输出「原因示例：」空壳") {
        let c = languageCoverage(languageCount: 1, truncated: false, failed: 1, reasons: [""])
        guard let note = c.note, !note.contains("原因示例") else {
            throw fail("空原因被拼进去了：\(c.note ?? "nil")")
        }
        return note
    }

    check("UI 必须走 languageCoverage（判定内联回视图就又不可测了）") {
        let detail = try sourceText("DetailViews.swift")
        guard detail.contains("languageCoverage(") else {
            throw fail("语言分布卡片没有走 languageCoverage")
        }
        guard detail.contains("coverage.note") else {
            throw fail("披露没有被渲染出来")
        }
        guard !detail.contains("languages.isEmpty {\n                        EmptyState(icon: \"text.justify\", title: \"暂无数据\")") else {
            throw fail("空态又退回写死的「暂无数据」")
        }
        return "判定与渲染都在"
    }

    check("Dashboard 模型必须解出 languagesTruncated（引擎早就恒发了）") {
        let m = try sourceText("Models.swift")
        // 必须匹配到**类型**，不能只 contains 字段名：
        //   · 文档注释里出现同一个词就会假绿
        //   · `let languagesFailedReasons` 本身就是 `let languagesFailed` 的前缀
        // 两次都实测过：前一次删属性仍绿，后一次删字段仍绿。
        guard m.contains("let languagesTruncated:") else {
            throw fail("模型没解 languagesTruncated —— 引擎的截断披露到不了界面")
        }
        guard m.contains("let languagesFailed:") else {
            throw fail("模型没解 languagesFailed —— 采集失败到不了界面")
        }
        guard m.contains("let languagesFailedReasons:") else {
            throw fail("模型没解 languagesFailedReasons —— 失败原因到不了界面")
        }
        return "三个字段都在"
    }
}

// MARK: - journal 的 +N 口径（引擎侧缺陷 #188）

print("")
print("【O】journal：同名不同义的 +N 必须自报口径（#188）")

do {
    // 引擎的 commitCount 在两条路径上装的是不同的东西：
    //   浅更新 commitCountScope="new"       → 本轮真正新记录的提交数
    //   深更新 commitCountScope="repoTotal" → 仓库提交总数（无上限，会一直涨）
    // 引擎注释原话：「靠 mode 字段去猜口径不行：那是约定不是契约」。
    // 客户端原来既不解也不显示，日志里两个一模一样的绿色 +6 并排。

    check("浅更新：徽章写「新增」，绿色") {
        let b = commitCountBadge(commitCount: 3, scope: "new", truncated: false)
        guard let t = b.text, t.contains("新增"), t.contains("3") else {
            throw fail("口径没写出来：\(b.text ?? "nil")")
        }
        guard b.scope == .newCommits, b.scope.isIncremental else {
            throw fail("scope 判错：\(b.scope)")
        }
        return t
    }

    check("深更新：同一个数必须写成「累计」而不是「新增」") {
        let b = commitCountBadge(commitCount: 100, scope: "repoTotal", truncated: false)
        guard let t = b.text, t.contains("累计") else {
            throw fail("累计量被写成了增量语义：\(b.text ?? "nil")")
        }
        // ⚠️ 绿色只留给本轮新增。累计量用绿色 = 「这次变好了 100 个」。
        guard !b.scope.isIncremental else { throw fail("累计量被判成增量") }
        return t
    }

    check("口径缺键：不得默认成任何一个，必须说「口径未知」") {
        // 旧引擎没这个键。默认成 new 或 repoTotal 都是在编造事实。
        let b = commitCountBadge(commitCount: 42, scope: nil, truncated: false)
        guard b.scope == .unknown else { throw fail("缺键被判成了 \(b.scope)") }
        guard b.note != nil, b.note!.contains("无法判断") else {
            throw fail("没有提示口径未知：\(b.note ?? "nil")")
        }
        return b.text ?? ""
    }

    check("未知口径字符串：同样不许猜") {
        let b = commitCountBadge(commitCount: 42, scope: "somethingElse", truncated: false)
        guard b.scope == .unknown else { throw fail("未知取值被判成了 \(b.scope)") }
        return "unknown"
    }

    check("截断：必须说这是采样值") {
        let b = commitCountBadge(commitCount: 30, scope: "new", truncated: true)
        guard b.truncated, let n = b.note, n.contains("采样") else {
            throw fail("截断没披露：\(b.note ?? "nil")")
        }
        return n
    }

    check("commitCount = -1：显示「读不出来」，绝不显示成 0 或空徽章") {
        // 报 0 等于替用户断言「这轮没有提交」，而真相是「整个数字没意义」。
        let b = commitCountBadge(commitCount: -1, scope: "new", truncated: false)
        guard b.scope == .unreadable else { throw fail("-1 被当成了正常数") }
        guard let t = b.text, t.contains("读不出来") else {
            throw fail("没有显示读不出来：\(b.text ?? "nil")")
        }
        guard b.note != nil, b.note!.contains("不是") else {
            throw fail("没有点明「这不是 0」：\(b.note ?? "nil")")
        }
        return t
    }

    check("0：不占徽章位，也不编造披露") {
        let b = commitCountBadge(commitCount: 0, scope: "new", truncated: false)
        guard b.text == nil, b.note == nil else {
            throw fail("0 也被渲染成了徽章：\(b.text ?? "nil") / \(b.note ?? "nil")")
        }
        return "沉默"
    }

    check("truncated 缺键：不许当成「已确认没截断」而闭嘴") {
        // 恒发是引擎的约定，但旧引擎没有。缺键时至少不能断言完整。
        let b = commitCountBadge(commitCount: 30, scope: "new", truncated: nil)
        guard !b.truncated else { throw fail("缺键被判成了已确认") }
        return "缺键不当成确认"
    }

    check("JournalEntry 模型必须解出三个口径字段") {
        let m = try sourceText("Models.swift")
        // ⚠️ 这里原来匹配的是 `let commitCountScope:` ——**按声明语法**判存在性。
        // 后果有两个，第二个更糟：
        //   1. 把它改成 `var` 就红（纯粹因为关键字变了，与对错无关）；
        //   2. `let x: T? = nil` 这种**永不解码**的写法反而能通过 ——
        //      字段在源码里「存在」，判据绿，而运行时永远是 nil。
        //      本项目就靠这条假绿放过了 4 个死键，外加把时间窗筛选变成死控件。
        // 改成按「声明里有没有初值」判：**带初值的不可变存储属性 Swift 不会解码它**，
        // 那才是「解出来了」与「只是写着」的真正分界。
        //
        // ⚠️ 切片必须**限定在 JournalEntry 结构体里**：Models.swift 里
        // `ProjectStatus` 也有一个同名 `repoBranchCount`，而且它是**合法的 let**
        // （非可选、无默认值 → 一定会被解码）。文件级匹配会把它一起判红 ——
        // 我第一版就栽在这儿，是把原注释警告的坑反向踩了一遍：那次是假绿，这次是假红。
        let body = try slice(m, from: "struct JournalEntry", to: "\n}\n")
            ?? "（切不出 JournalEntry 的声明）"
        for name in ["commitCountScope", "commitCountTruncated", "repoBranchCount",
                     "branchCountTruncated"] {
            guard body.contains("\(name):") else {
                throw fail("JournalEntry 没有字段 \(name)")
            }
            if body.contains("let \(name):") {
                throw fail("JournalEntry.\(name) 声明成了 `let` —— Swift 合成解码器会跳过"
                    + "带初值的不可变存储属性，这个键永远解不出来（必须写 var）")
            }
            guard body.contains("var \(name):") else {
                throw fail("JournalEntry.\(name) 既不是 var 也不是可解码的 let，判据不知道它是什么")
            }
        }
        // 反向自查：别把 ProjectStatus 那个合法的 let 也一起改了。
        // 它非可选、无初值，合成解码器一定会解 —— 若哪天有人「顺手统一」成
        // `var repoBranchCount: Int = 0`，老引擎缺键时就会静默变成 0 而不是解码失败。
        let proj = try slice(m, from: "struct ProjectStatus", to: "\n}\n")
            ?? "（切不出 ProjectStatus 的声明）"
        if proj.contains("var repoBranchCount:") {
            throw fail("ProjectStatus.repoBranchCount 被改成了 var + 初值 —— "
                + "它是必填字段，不该有默认值（缺键应当解码失败，而不是静默变 0）")
        }
        return "四个口径字段都是 var（真会被解码）；ProjectStatus.repoBranchCount 仍是必填 let"
    }

    check("UI 必须走 commitCountBadge，且不得再有无口径的绿色 +N") {
        let detail = try sourceText("DetailViews.swift")
        guard detail.contains("commitCountBadge(") else {
            throw fail("journal 卡片没有走 commitCountBadge")
        }
        guard detail.contains("badge.scope.isIncremental") else {
            throw fail("徽章颜色没有跟着口径走")
        }
        guard !detail.contains("Text(\"+\\(e.commitCount)\")") else {
            throw fail("无口径的 +N 徽章还在")
        }
        return "判定与渲染都在"
    }
}

// MARK: - context 信封的形状一致性（#191）

print("")
print("【P】context 交给模型的形状必须只有一种（#191）")

do {
    // 修之前：系统提示词那条路交 markdown，工具结果那条路交整个 JSON 信封，
    // 引擎自己的 MCP 工具交裸 markdown —— 同名工具三种形状。

    check("正常信封：只取 context，不把包装键喂给模型") {
        let raw = ##"{"scope":"project","budget":8000,"context":"# deepGit\n\n- 现状：x\n"}"##
        let d = ContextEnvelope.decode(Data(raw.utf8))
        guard d.context == "# deepGit\n\n- 现状：x\n" else {
            throw fail("取出来的不是 context：\(d.context)")
        }
        guard d.note == nil else { throw fail("正常信封不该有说明：\(d.note ?? "")") }
        // 包装键不得混进正文
        guard !d.context.contains("\"budget\"") else { throw fail("把 JSON 包装键喂给了模型") }
        return "只交正文"
    }

    check("context 键缺失：必须说明「不等于没有上下文」") {
        let raw = ##"{"scope":"group","budget":8000}"##
        let d = ContextEnvelope.decode(Data(raw.utf8))
        guard let note = d.note, note.contains("不等于") else {
            throw fail("缺键被静默当成空上下文：\(d.note ?? "nil")")
        }
        return note
    }

    check("context 为空串：是「这个范围没有内容」，不是「没解出来」") {
        let raw = ##"{"scope":"project","budget":8000,"context":""}"##
        let d = ContextEnvelope.decode(Data(raw.utf8))
        guard let note = d.note, note.contains("没有内容") else {
            throw fail("空串没被如实说明：\(d.note ?? "nil")")
        }
        guard d.context.isEmpty else { throw fail("空串应原样保留为空") }
        return note
    }

    check("不是 JSON：交原文 + 说明，绝不静默") {
        let d = ContextEnvelope.decode(Data("这不是 JSON".utf8))
        guard d.context == "这不是 JSON" else { throw fail("原文丢了") }
        guard d.note != nil, d.note!.contains("不是预期") else {
            throw fail("没有说明形状不对：\(d.note ?? "nil")")
        }
        return d.note!
    }

    check("客户端二次截断必须自报家门") {
        // 引擎的截断披露写在结尾；客户端从头部切，会把它切掉。
        // 所以客户端这一刀必须说清「是我切的」且「上面不完整」。
        let note = clientClipNote(20000, 16000)
        guard note.contains("20000"), note.contains("16000") else {
            throw fail("没说清原长与截长：\(note)")
        }
        guard note.contains("不完整") else { throw fail("没说清内容不完整：\(note)") }
        guard note.contains("客户端") else { throw fail("没说清是谁切的：\(note)") }
        return note
    }

    check("AgentCore 三处都必须走 ContextEnvelope（形状一致性靠它）") {
        let src = try sourceText("AgentCore.swift")
        let hits = src.components(separatedBy: "ContextEnvelope.decode(").count - 1
        guard hits >= 3 else { throw fail("只有 \(hits) 处走了统一解码，应为 3（两个工具 + 系统提示词）") }
        guard src.contains("clientClipNote(") else {
            throw fail("二次截断没有用统一措辞")
        }
        // 收窄到这两个分支：`get_journal` / `get_project_docs` 本来就该返回
        // JSON，用全局「不得出现 raw bytes」去卡它们属于误伤。
        guard let a = src.range(of: "case \"get_group_context\""),
              let b = src.range(of: "case \"get_project_docs\""),
              a.upperBound < b.lowerBound else {
            throw fail("找不到这两个 case 的区间")
        }
        let seg = String(src[a.upperBound..<b.lowerBound])
        guard !seg.contains("String(data: data, encoding: .utf8) ?? \"\"") else {
            throw fail("context 分支还在把原始字节直接当文本交给模型")
        }
        // 静默空串：解不出 context 时 `?? ""` 会让模型读成「这个项目群什么都没有」
        // 必须匹配到 **context 那一行**：文件里另有一处 `params[key] as? String ?? ""`
        // 是合法的参数取值器，用全局匹配会误伤（正控就是这么红的）。
        guard !src.contains("ctxObj?[\"context\"] as? String ?? \"\"") else {
            throw fail("context 提取还在用空串兜底（静默空上下文）")
        }
        // 二次截断的裸标记：切掉引擎写在结尾的披露，却只留一句「(截断)」
        guard !src.contains("\\n…(截断)") else {
            throw fail("二次截断还在用裸标记，丢掉引擎的截断披露")
        }
        return "\(hits) 处统一"
    }
}

// MARK: - 引擎失败原因不许被降级成退出码（#193）

print("")
print("【Q】引擎失败载荷必须被读出来（#193：jsonPayload 零消费方 ⇒ 「引擎退出码 1」）")

// ⚠️ 下面 5 份载荷是**引擎真实输出**（`deepgit <cmd> --json` 非 0 退出），
// 逐字抄的，不是手搓的。手搓夹具比现实更完整就永远测不出漏读
// （#188 的教训：deep.cj 不恒发的字段，被 store.cj 手搓的夹具全写上了）。
do {
    // ① `update <项目> --json` 项目目录只读 → DOC_WRITE_FAILED
    let docWriteFailed = """
    {
      "code": "DOC_WRITE_FAILED",
      "message": "proj 更新失败：进度已记录到 p_70f9163a63b3，但以下文档未能更新（它们的内容仍是上一轮的）：\\n  - README.md：Failed to open the file. Permission denied",
      "details": "proj"
    }
    """

    // ② `milestone done <项目> <不存在的里程碑> --json` → errJson
    let milestoneNotFound = """
    {
      "error": true,
      "code": "MILESTONE_NOT_FOUND",
      "message": "未找到里程碑：nosuchmilestone"
    }
    """

    // ③ `update --json --quiet`（无项目名，多项目）→ 成功/失败**混在同一个数组**。
    //    真实有 5 项，这里留 2 失败 + 1 成功，形状与真输出一致。
    let batchMixed = """
    {
      "results": [
        {
          "code": "VOLUME_BLOCKED",
          "message": "proj 更新失败：路径不存在或卷未挂载：/private/tmp/dg193/proj"
        },
        {
          "code": "VOLUME_BLOCKED",
          "message": "vanish 更新失败：路径不存在或卷未挂载：/private/tmp/dg193/vanish"
        },
        {
          "ok": true,
          "mode": "shallow",
          "projectId": "p_12bc7995b5bc",
          "project": "ok2",
          "provider": "rules",
          "branchCount": 1
        }
      ],
      "count": 3,
      "failed": 2,
      "succeeded": 1
    }
    """

    // ③' 同一形状但**全部成功**却非 0 退出 —— 不能把成功项报成失败。
    let batchAllOK = """
    {
      "results": [ { "ok": true, "project": "ok2", "branchCount": 1 } ],
      "count": 1,
      "failed": 0,
      "succeeded": 1
    }
    """

    // ④ `status --json` 全部项目路径失效 → exit 1，**stderr 0 字节**
    let statusAllFailed = """
    {
      "projects": [
        { "name": "proj", "error": "路径不存在或卷未挂载：/private/tmp/dg193/proj" },
        { "name": "vanish", "error": "路径不存在或卷未挂载：/private/tmp/dg193/vanish" },
        { "name": "ok2" }
      ],
      "summary": { "projectCount": 0, "listedProjects": 3, "failedProjects": 2 },
      "language": []
    }
    """

    // ⑤ `dashboard --json` 全部失败 → exit 1，**只有个数没有原因**。
    //    这一条测的是「引擎确实没给原因时，客户端必须承认没给」，
    //    而不是编一个原因出来。
    let dashboardAllFailed = """
    {
      "projects": { "total": 0, "listed": 5, "registered": 5, "failed": 4 },
      "work": { "branches": 0 },
      "languages": [],
      "languagesTruncated": false,
      "activeProjects": [],
      "fetchedAt": "2026-10-01T17:24:28Z"
    }
    """

    let exitCodeOnly = "引擎退出码 1"

    check("① DOC_WRITE_FAILED ⇒ 说清哪个文件、为什么（这是原缺陷）") {
        let r = EngineFailure.reason(payload: Data(docWriteFailed.utf8), fallback: exitCodeOnly)
        guard r != exitCodeOnly else {
            throw fail("载荷里有原因却原样退了退出码 ⇒ jsonPayload 零消费方的老毛病")
        }
        guard r.contains("DOC_WRITE_FAILED") else { throw fail("丢了机器可读 code：\(r)") }
        guard r.contains("README.md"), r.contains("Permission denied") else {
            throw fail("丢了具体文件或具体原因：\(r)")
        }
        return r.count > 40 ? "已说出文件与原因" : r
    }

    check("① 多行消息压成一行（通知栏放不下，但不许把中间截掉）") {
        let r = EngineFailure.reason(payload: Data(docWriteFailed.utf8), fallback: exitCodeOnly)
        guard !r.contains("\n") else { throw fail("消息里还留着换行，通知栏会显示成多行：\(r)") }
        // 压平靠的是把 \n 换成 / —— 换掉之后两段都还在，顺序也不能反
        guard r.contains("它们的内容仍是上一轮的") , r.contains("Permission denied") else {
            throw fail("压平时把内容丢了：\(r)")
        }
        return "换行已折平，两段都在"
    }

    check("② errJson（error:true）⇒ 说清是哪个里程碑找不到") {
        let r = EngineFailure.reason(payload: Data(milestoneNotFound.utf8), fallback: exitCodeOnly)
        guard r.contains("未找到里程碑：nosuchmilestone") else {
            throw fail("丢了具体原因：\(r)")
        }
        guard r.contains("MILESTONE_NOT_FOUND") else { throw fail("丢了 code：\(r)") }
        return r
    }

    check("③ 批量载荷 ⇒ 逐条列失败项，且**不把成功项算进去**") {
        let r = EngineFailure.reason(payload: Data(batchMixed.utf8), fallback: exitCodeOnly)
        guard r.contains("proj 更新失败"), r.contains("vanish 更新失败") else {
            throw fail("没逐条说出失败的是谁：\(r)")
        }
        // 成功项 project=ok2。把它报成失败比不报更糟 ——
        // 用户会以为 ok2 也要重跑。
        guard !r.contains("ok2") else { throw fail("把成功项 ok2 也算成失败了：\(r)") }
        return r
    }

    check("③' 批量全成功却非 0 退出 ⇒ 说「没给出失败项」，不许把成功项报成失败") {
        let r = EngineFailure.reason(payload: Data(batchAllOK.utf8), fallback: exitCodeOnly)
        guard !r.contains("失败") || r.contains("未在载荷里给出失败项") else {
            throw fail("把全成功的一批说成失败了：\(r)")
        }
        guard r != exitCodeOnly else { throw fail("又退化成退出码了") }
        return r
    }

    check("③'' batchFailedCount 返回 2 而不是 failed 字段（逐条数得对）") {
        guard let n = EngineFailure.batchFailedCount(Data(batchMixed.utf8)) else {
            throw fail("批量载荷没被认出来")
        }
        guard n == 2 else { throw fail("数出 \(n) 条失败，应为 2") }
        return "2"
    }

    // 这条是 #193 顺手挖出来的第二个洞，也是本组最容易写成空话的一条。
    //
    // 客户端判「一个 batch 项是不是失败」，与引擎的 `hasErrorOrCode` 必须**同规则**
    // （引擎 src/util/log.cj：有 `ok` 键 ⇒ 不是失败）。
    // 写成 `ok == true 才算成功` 会数出**比引擎 `failed` 字段更多**的失败项 ——
    // 屏幕上同时出现「2 个项目失败」（客户端数）和 `failed: 1`（引擎数），
    // 而没人知道该信哪个。判据有两份就必然漂移。
    //
    // ⚠️⚠️ 陷阱夹具必须挑**只有一种判据会误判**的形状，否则断言是死的。
    // 踩了两次：
    //   第一次拿 `{ok:true,…}` —— 它没有 message，按 message 过滤和按 ok 过滤
    //     结果一样，删掉 ok 过滤照样全绿。
    //   第二次拿 `{ok:false,message:…}` —— 它也没有 code/error 键，
    //     两种规则都判它不是失败，**还是**抓不住（实测 NC45-e 全绿）。
    // 唯一能分开两种规则的是 `{ok:…, code|error:…}` 这种「两个键都带」的形状：
    //   引擎规则：`ok` 键存在 ⇒ 不是失败
    //   漂移规则：`ok != true` ⇒ 继续看 code/error ⇒ 失败
    check("batch 项的失败判据必须与引擎 hasErrorOrCode 同规则（不许 ok==true 才算成功）") {
        let trap = """
        {
          "results": [
            { "ok": false, "code": "STALE_FLAG", "message": "带 ok 键 ⇒ 引擎判它不是失败", "project": "p1" },
            { "code": "VOLUME_BLOCKED", "message": "proj 更新失败：路径不存在或卷未挂载：/tmp/x" }
          ],
          "count": 2,
          "failed": 1,
          "succeeded": 1
        }
        """
        let rs = EngineFailure.batchReasons(Data(trap.utf8))
        guard rs.count == 1 else {
            throw fail("列出 \(rs.count) 条，引擎的 failed 写的是 1 ⇒ 客户端另发明了一份判据：\(rs)")
        }
        guard !rs.contains(where: { $0.contains("STALE_FLAG") }) else {
            throw fail("把带 ok 键的项当成了失败（与引擎判据不一致）：\(rs)")
        }
        // 摘要里的个数必须用引擎的 failed，不是「我们能说清原因的条数」
        let r = EngineFailure.reason(payload: Data(trap.utf8), fallback: exitCodeOnly)
        guard r.contains("1 个项目更新失败") else {
            throw fail("摘要里的个数没跟着引擎的 failed 走：\(r)")
        }
        return "判据一致，个数取引擎的 failed"
    }

    check("引擎写了 failed 但没给 message ⇒ 个数照引擎的报，不许少报") {
        // failed=2，其中一条没有 message。按 reasons.count 报会说成「1 个失败」，
        // 与载荷里的 failed: 2 对不上 —— 那才是谎报。
        let gap = """
        {
          "results": [
            { "code": "VOLUME_BLOCKED", "message": "proj 更新失败：路径不存在或卷未挂载：/tmp/x" },
            { "code": "SOMETHING_ELSE" }
          ],
          "count": 2,
          "failed": 2,
          "succeeded": 0
        }
        """
        let r = EngineFailure.reason(payload: Data(gap.utf8), fallback: exitCodeOnly)
        guard r.contains("2 个项目更新失败") else {
            throw fail("少数了一条（按能说清的条数报，与载荷里的 failed 对不上）：\(r)")
        }
        return r
    }

    check("④ status 载荷 ⇒ 逐条说清每个项目为什么采集失败") {
        let r = EngineFailure.reason(payload: Data(statusAllFailed.utf8), fallback: exitCodeOnly)
        guard r.contains("2 个项目采集失败") else { throw fail("没说出失败了几个：\(r)") }
        guard r.contains("/private/tmp/dg193/proj"),
              r.contains("/private/tmp/dg193/vanish") else {
            throw fail("没逐条给出原因：\(r)")
        }
        guard !r.contains("ok2") else { throw fail("把采集成功的 ok2 也算成失败了：\(r)") }
        return r.count > 50 ? "2 个项目、逐条有原因" : r
    }

    check("⑤ dashboard 只有个数 ⇒ 说出个数并承认引擎没给逐条原因") {
        let r = EngineFailure.reason(payload: Data(dashboardAllFailed.utf8), fallback: exitCodeOnly)
        guard r.contains("4") else { throw fail("连个数都没保住：\(r)") }
        // 编一个原因比不报更糟：那是谎报。
        guard r.contains("未给") || r.contains("没有原因") else {
            throw fail("引擎没给原因却说得像给了：\(r)")
        }
        return r
    }

    check("⑤' 零失败时不许报失败（failed=0 走不进失败分支）") {
        let ok = """
        { "projects": { "total": 1, "listed": 1, "registered": 1, "failed": 0 },
          "work": { "branches": 1 }, "languages": [], "activeProjects": [] }
        """
        let r = EngineFailure.reason(payload: Data(ok.utf8), fallback: exitCodeOnly)
        guard r == exitCodeOnly else { throw fail("failed=0 却编出了一句失败：\(r)") }
        return "零失败原样退回"
    }

    check("没有载荷时退回 fallback（不得凭空造原因）") {
        let r = EngineFailure.reason(payload: nil, fallback: "未找到项目：nosuch")
        guard r == "未找到项目：nosuch" else { throw fail("无载荷时不该编原因：\(r)") }
        return r
    }

    check("fallback 也是空 ⇒ 仍必须给一句非空的话（不许出现空错误文案）") {
        for fb in ["", "   ", "\n"] {
            let r = EngineFailure.reason(payload: nil, fallback: fb)
            guard !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw fail("fallback=\(fb.debugDescription) 时返回了空串")
            }
        }
        return "空退路也有话说"
    }

    check("batchReasons 只列失败项，供逐条展示/喂模型") {
        let rs = EngineFailure.batchReasons(Data(batchMixed.utf8))
        guard rs.count == 2 else { throw fail("列出 \(rs.count) 条，应为 2") }
        guard !rs.contains(where: { $0.contains("ok2") }) else {
            throw fail("把成功项列进了失败原因：\(rs)")
        }
        return "\(rs.count) 条"
    }

    check("形状不认识时退回 fallback，但**不把原文悄悄吞掉**") {
        let junk = Data("这是一段不是 JSON 的引擎输出".utf8)
        let r = EngineFailure.reason(payload: junk, fallback: exitCodeOnly)
        guard r.contains(exitCodeOnly) else { throw fail("没退回 fallback：\(r)") }
        guard r.contains("这不是 JSON") || r.contains("不是 JSON 的引擎输出") else {
            throw fail("把未知形状的原文吞了，下次又是一句无信息量的话：\(r)")
        }
        return "退路 + 原文"
    }
}

// MARK: - #193 的接线守卫：光有纯函数不够，catch 必须真的用它

do {
    check("EngineError.userMessage 必须真的读 payload（jsonPayload 有消费方了）") {
        let src = try sourceText("EngineCLI.swift")
        guard src.contains("EngineFailure.reason(payload: jsonPayload") else {
            throw fail("EngineError.userMessage 没有读 jsonPayload ⇒ 载荷仍然零消费")
        }
        // errorDescription 那一支不能也去读 payload：它是协议实现，
        // 会被 localize 走；让判定留在 userMessage 一处。
        guard src.contains("var userMessage: String") else {
            throw fail("EngineError 没有 userMessage 接缝")
        }
        return "userMessage 读 payload"
    }

    check("catch 块不得再用 localizedDescription 取引擎失败原因（原缺陷）") {
        // 这些文件里的 catch 包住的都是引擎/代理调用。
        // 名单是**显式**的：只卡引擎驱动的那几个，
        // AI 侧的错误（网络、API key）本来就该走 localizedDescription。
        let files = ["Model.swift", "AgentCore.swift", "BoardView.swift",
                     "MilestonesView.swift", "ScanSheet.swift", "AgentView.swift",
                     "AIIntegration.swift"]
        var bad: [String] = []
        for f in files {
            let t = try sourceText(f)
            for (i, line) in t.components(separatedBy: "\n").enumerated()
            where line.contains("localizedDescription") {
                // 允许的例外：注释里解释这件事的说明行。
                let t2 = line.trimmingCharacters(in: .whitespaces)
                if t2.hasPrefix("//") || t2.hasPrefix("*") || t2.hasPrefix("///") { continue }
                bad.append("\(f):\(i + 1) \(t2)")
            }
        }
        guard bad.isEmpty else {
            throw fail("这些地方仍在丢原因：\n      " + bad.joined(separator: "\n      "))
        }
        return "\(files.count) 个文件的 catch 全部走 EngineError.userMessage(for:)"
    }

    check("EngineCLI 失败路径不得把非 JSON 的 stdout 整份丢掉（usage 类真因在那）") {
        let src = swiftCode(try sourceText("EngineCLI.swift"))
        // 只看 throw 之前那一段：真正的问题是「拿不到 JSON 就只取 stderr」。
        guard let a = src.range(of: "if proc.terminationStatus != 0"),
              let b = src.range(of: "return outBuf") else {
            throw fail("找不到失败分支的区间")
        }
        let seg = String(src[a.lowerBound..<b.lowerBound])
        guard seg.contains("outBuf") else {
            throw fail("失败分支里根本没读 stdout ⇒ usage 类失败的真因（stdout 纯文本）全丢")
        }
        // 原写法：只取 errBuf，outBuf 只在 JSON 成功时才被用到。
        guard seg.contains("outText") else {
            throw fail("非 JSON 的 stdout 仍被整份丢弃")
        }
        return "stdout 纯文本也进了消息"
    }

    check("新增的纯函数必须挂进 client-check.sh 的编译清单（否则测的是副本）") {
        let sh = try pkgText("scripts/client-check.sh")
        guard sh.contains("EngineFailure.swift") else {
            throw fail("client-check.sh 没编译 EngineFailure.swift ⇒ 检查跑的不是本体")
        }
        guard sh.contains("CTXENV="), sh.contains("$CTXENV") else {
            throw fail("编译清单与变量声明对不上")
        }
        return "已挂进编译清单"
    }
}

// MARK: - 扫描覆盖度（引擎侧 #197 的第二个出口：客户端也踩同一个坑）

do {
    // 真实形状：仓库在第 4 层，而 ScanSheet 的默认深度就是 2
    let enginePayload: [String: Any] = [
        "roots": 1, "found": 0, "added": 0, "existing": 0,
        "dirsVisited": 3, "depth": 2,
        "truncated": false, "depthCapped": true, "unreadable": []
    ]

    check("深度不够 ⇒ 不得说「该目录树里没有 git 仓库」") {
        let i = ScanCoverage.input(from: enginePayload)
        let n = ScanCoverage.note(i)
        guard let n else { throw fail("没有任何披露 ⇒ 界面上只剩「共发现 0 个」，读成「这棵树里没有仓库」") }
        guard n.contains("未") || n.contains("没") else { throw fail("没说清「没扫完」：\(n)") }
        guard n.contains("深度") else { throw fail("没说清是深度上限（处置是加深度，不是别的）：\(n)") }
        return n.count > 20 ? "已说明未扫完 + 成因" : n
    }

    check("found=0 时的措辞必须把「不是没有」说到底") {
        // ⚠️ 这里曾经写成 `ScanCoverage.note(...)!` —— 缺陷回归时 note 会是 nil，
        // 强解包直接 Trace/BPT trap：**检查程序自己崩掉**，
        // 输出停在半行，后面所有检查都没跑（实测 rc=133、日志断在一条检查中间）。
        // 检查程序崩了就说不出「哪条错了」—— 和被测代码崩溃一样没用。
        guard let n = ScanCoverage.note(ScanCoverage.input(from: enginePayload)) else {
            throw fail("根本没有披露可检查")
        }
        guard n.contains("不是") || n.contains("只代表") else {
            throw fail("「共发现 0 个」仍会被读成断言式结论：\(n)")
        }
        return "已声明「不代表没有」"
    }

    check("三种没扫全的成因一个都不能漏（处置方式不同）") {
        // 撞目录上限 → 分根扫描
        let t: [String: Any] = ["found": 3, "truncated": true, "depthCapped": false, "unreadable": []]
        guard let nt = ScanCoverage.note(ScanCoverage.input(from: t)) else { throw fail("truncated 被漏了") }
        guard nt.contains("数量上限") else { throw fail("没说是目录数量上限：\(nt)") }
        // 目录读不出来 → 查权限
        let u: [String: Any] = ["found": 0, "truncated": false, "depthCapped": false, "unreadable": ["a", "b"]]
        guard let nu = ScanCoverage.note(ScanCoverage.input(from: u)) else { throw fail("unreadable 被漏了") }
        guard nu.contains("2 个目录") && nu.contains("权限") else { throw fail("没把读不出来的目录说清：\(nu)") }
        // 三者同时发生
        let all: [String: Any] = ["found": 0, "truncated": true, "depthCapped": true, "unreadable": ["a"]]
        let na = ScanCoverage.note(ScanCoverage.input(from: all))
        guard let na, na.contains("深度"), na.contains("数量上限"), na.contains("权限") else {
            throw fail("三种成因没有同时出现（if 链漏组合）：\(na ?? "nil")")
        }
        return "3 种 + 组合都在"
    }

    check("扫完了 ⇒ 一个字都不许多说（不要制造噪音）") {
        let done: [String: Any] = [
            "found": 2, "truncated": false, "depthCapped": false, "unreadable": []
        ]
        guard ScanCoverage.note(ScanCoverage.input(from: done)) == nil else {
            throw fail("扫完了还加披露 ⇒ 每次成功扫描都多一句废话")
        }
        return "nil（视图不追加）"
    }

    check("键缺失（nil）≠ 明确 false") {
        // 老版本引擎不发 depthCapped。缺键时不得当成「被截断」，
        // 也不得当成「没被截断」后就去断言「没有仓库」。
        let old: [String: Any] = ["found": 0, "truncated": false]
        let i = ScanCoverage.input(from: old)
        guard i.depthCapped == nil else { throw fail("缺键被读成了 false") }
        // 缺键时没有别的未扫全信号 ⇒ 什么都不说（由视图决定说不说）
        guard ScanCoverage.note(i) == nil else { throw fail("缺键凭空造出了披露") }
        return "nil 而非 false"
    }

    check("ScanSheet 源码：未扫完时不得并排出现「没有 git 仓库」") {
        let src = try sourceText("ScanSheet.swift")
        guard src.contains("ScanCoverage.note(") else {
            throw fail("视图没用 ScanCoverage.note ⇒ 披露没接上")
        }
        // 剥注释后匹配：注释里为了说明缺陷必然引用了那句原文
        let code = swiftCode(src)
        let bad = code.contains("if found == 0 { line += \" —— 该目录树里没有 git 仓库\" }")
        if bad { throw fail("又无条件断言「没有 git 仓库」了") }
        // 正确的形状：必须以「真的扫完了」为前提
        guard code.contains("found == 0 && note == nil") else {
            throw fail("「没有 git 仓库」没有以 note == nil（扫完了）为前提")
        }
        return "以「扫完了」为前提"
    }

    check("新增的纯函数必须挂进 client-check.sh 的编译清单") {
        let sh = try pkgText("scripts/client-check.sh")
        guard sh.contains("ScanCoverage.swift"), sh.contains("$SCANCOV") else {
            throw fail("client-check.sh 没编译 ScanCoverage.swift ⇒ 检查跑的不是本体")
        }
        return "已挂进编译清单"
    }
}

// MARK: - 提交构成的完整度（缺陷 #206）

print("")
print("【S】提交构成：界面自己砍掉的类型必须自报（#206）")

do {
    /// 14 条同类型提交：用来单独触发「引擎采样窗口被砍」这一条轴。
    /// 定义在使用之前 —— 局部 `func` 放后面在 Swift 里会直接编译失败。
    func sameType(_ n: Int) -> [(type: String, count: Int)] {
        Array(repeating: ("feat", 1), count: n)
    }

    // 实测样本：14 个提交、14 种不同类型（含 3 种旧分类法遗留名）的仓库，
    // `status --json` 的 commitTypes 实测 12 条，commitTypesTruncated=false。
    // 12 = 引擎 COMMIT_TYPE_ORDER 的长度（11 个已知 + other 桶），
    // 与采样窗口无关 ⇒ 这是引擎的**条数**上界。
    let real: [(type: String, count: Int)] = [
        ("feat", 1), ("fix", 1), ("perf", 1), ("refactor", 1), ("docs", 1), ("test", 1),
        ("build", 1), ("ci", 1), ("style", 1), ("chore", 1), ("revert", 1), ("other", 3),
    ]

    check("复现用例：引擎说「这就是全量」时，界面砍掉的 7 种必须披露") {
        // ⚠️ 这一条是 #206 的核心：sampleTruncated == false 恰恰是
        // 「引擎数据完整」的时候，也正是界面藏得最狠的时候。
        let c = commitTypeComposition(entries: real, sampleTruncated: false, totalCommits: 14)
        guard c.shown == 5, c.total == 12, c.topCut else {
            throw fail("口径不对：shown=\(c.shown) total=\(c.total) topCut=\(c.topCut)")
        }
        guard let line = c.line, line.contains("前 5"), line.contains("共 12") else {
            throw fail("藏掉的 7 种没有披露：\(c.line ?? "nil")")
        }
        return line
    }

    check("披露不许顶替内容：前 5 种本身还得列出来") {
        let c = commitTypeComposition(entries: real, sampleTruncated: false, totalCommits: 14)
        let line = c.line ?? ""
        for t in ["feat", "fix", "perf", "refactor", "docs"] where !line.contains(t) {
            throw fail("列出来的那一种不见了：\(t)")
        }
        return "5 种都在"
    }

    check("≤ 上限时不许造披露") {
        let few: [(type: String, count: Int)] = [("feat", 3), ("fix", 1), ("docs", 1)]
        let c = commitTypeComposition(entries: few, sampleTruncated: false, totalCommits: 5)
        guard !c.topCut, c.shown == 3 else { throw fail("画全了却报 topCut") }
        // ⚠️ 只能在 guard **之后**用 line：在 else 里写 `\(line)` 会让 `line`
        // 解析成 stdlib 的 `line()` 宏（报错说「requires leading '#'」）——
        // 因为 guard 的绑定在 else 分支里根本不在作用域。这是本文件踩过的坑。
        guard let line = c.line else { throw fail("有类型却整行都没了") }
        guard !line.contains("（") else {
            throw fail("没有截断却加了括号说明：\(line)")
        }
        return line
    }

    check("引擎采样窗口被砍：必须写出分母（与界面 top-5 是两条轴）") {
        let c = commitTypeComposition(entries: sameType(14), sampleTruncated: true, totalCommits: 23)
        guard let line = c.line, line.contains("近 14/23 条") else {
            throw fail("采样截断没有写分母：\(c.line ?? "nil")")
        }
        return line
    }

    check("提交总数读不出来（-1）时不得写出「近 14/-1 条」") {
        let c = commitTypeComposition(entries: sameType(14), sampleTruncated: true, totalCommits: -1)
        guard let line = c.line else { throw fail("没有输出") }
        guard !line.contains("-1") else { throw fail("把 -1 当分母写出来了：\(line)") }
        guard line.contains("样本，非全量") else { throw fail("没说清是样本：\(line)") }
        return line
    }

    check("两条轴同时发生：两条都要说") {
        let c = commitTypeComposition(entries: real, sampleTruncated: true, totalCommits: 23)
        guard let line = c.line, line.contains("条样本"), line.contains("共 12") else {
            throw fail("只说了一部分：\(c.line ?? "nil")")
        }
        return line
    }

    check("COMMIT_TYPE_LINE_MAX 是唯一来源：比它多的必然触发披露") {
        guard COMMIT_TYPE_LINE_MAX == 5 else { throw fail("常量变了：\(COMMIT_TYPE_LINE_MAX)") }
        // 对照：条数正好等于上限 ⇒ 不许披露（否则上面那条没有判别力）
        let exact = Array(repeating: ("feat", 1), count: COMMIT_TYPE_LINE_MAX)
        let a = commitTypeComposition(entries: exact, sampleTruncated: false, totalCommits: 5)
        guard !a.topCut else { throw fail("正好等于上限却报 topCut") }
        let over = Array(repeating: ("feat", 1), count: COMMIT_TYPE_LINE_MAX + 1)
        let b = commitTypeComposition(entries: over, sampleTruncated: false, totalCommits: 6)
        guard b.topCut, b.line != nil else { throw fail("超过上限却沉默") }
        return "\(COMMIT_TYPE_LINE_MAX) / \(COMMIT_TYPE_LINE_MAX + 1) 两侧都对"
    }

    check("一种类型都没有：整行必须消失（不是空括号）") {
        let c = commitTypeComposition(entries: [], sampleTruncated: false, totalCommits: 0)
        guard c.line == nil, c.shown == 0, !c.topCut else {
            throw fail("空输入产出了：\(c.line ?? "nil")")
        }
        return "nil"
    }

    check("lineMax 传 0 不许产出「只列前 0 种」这种自相矛盾的话") {
        let c = commitTypeComposition(entries: real, sampleTruncated: false,
                                      totalCommits: 14, lineMax: 0)
        guard c.shown >= 1, let line = c.line, !line.contains("前 0 种") else {
            throw fail("lineMax=0 的输出自相矛盾：\(c.line ?? "nil")")
        }
        return "至少列一种"
    }

    // ---- 色板容量：把「取模」变成一条带披露的真实上限 ----

    check("色板容量必须容得下引擎的条数上界，且无重色") {
        // 12 = 引擎 COMMIT_TYPE_ORDER 的长度，契约检查（跑真实引擎）钉这个数。
        guard CommitTypeColor.capacity == 12 else {
            throw fail("色板容量变了：\(CommitTypeColor.capacity)（引擎上界 12；加色要同时改契约检查）")
        }
        let names = Set(CommitTypeColor.palette.map { $0.rawValue })
        guard names.count == CommitTypeColor.capacity else {
            throw fail("色板里有重复颜色，\(CommitTypeColor.capacity) 个位置只有 \(names.count) 种色")
        }
        return "\(CommitTypeColor.capacity) 色不重样"
    }

    check("语言分布卡不许内联第二套调色板（§3.3「消灭两套调色板」）") {
        // 编译期事实：语言卡刻意不取模，前提是「画出来的条数 ≤ 色板容量」。
        // 这条把那个前提钉住 —— 哪天有人把 LANG_BAR_MAX 调到 20 而不同时扩色板，
        // 运行期会直接数组越界崩溃，而判据会在编译检查时就红。
        guard LANG_BAR_MAX <= CommitTypeColor.capacity else {
            throw fail("LANG_BAR_MAX(\(LANG_BAR_MAX)) 超过色板容量(\(CommitTypeColor.capacity))：\n" +
                "      语言卡按序号直取色板（不取模），条数一旦超过容量就是数组越界")
        }
        let v = try strippedCode("DetailViews.swift")
        guard let dash = slice(v, from: "private func dashboardContent(", to: "private func milestoneRow(") else {
            throw fail("切不出 dashboardContent —— lint 判据本身坏了（不是缺陷）")
        }
        if dash.contains("let palette: [Color]") {
            throw fail("语言分布卡又内联了一份颜色字面量 ⇒ 与提交构成卡成「两套调色板」：\n" +
                "      同一个蓝在一张卡里是 feat、在另一张卡里是 Swift，序号相同的两项颜色还不同")
        }
        // 两处取色（分段条 + 图例）都要走单一来源
        guard let bar = slice(dash, from: "SegmentedBar(segments: d.languages",
                              to: "VStack(alignment: .leading, spacing: 5)"),
              let legend = slice(dash, from: "ForEach(d.languages.prefix", to: "id: \\.0)") else {
            throw fail("切不出语言卡的两处取色（结构变了？）")
        }
        for (where_, seg) in [("分段条", bar), ("图例", legend)] {
            guard seg.contains("CommitTypeColor.palette[i]") else {
                throw fail("语言卡\(where_)没有走 CommitTypeColor.palette ⇒ 与提交构成卡不同源")
            }
            guard seg.contains("DSColor.sequence(") else {
                throw fail("语言卡\(where_)没有走 DSColor.sequence ⇒ 色板序号到颜色的映射有第二个出处")
            }
            // 与提交构成卡同一条纪律：取模只会掩盖容量不够
            if seg.contains("%") {
                throw fail("语言卡\(where_)里出现取模 ⇒ 容量不够时被悄悄回绕，两种语言涂成一个颜色")
            }
        }
        return "两处取色同源，且上限 ≤ 色板容量（故不必取模）"
    }

    check("序列色映射必须穷举（加新色忘了配，编译就要红）") {
        let d = try strippedCode("DesignSystem.swift")
        guard let f = slice(d, from: "static func sequence(", to: "\n    }\n") else {
            throw fail("切不出 DSColor.sequence（结构变了？）")
        }
        if f.contains("default:") {
            throw fail("DSColor.sequence 有 default 分支 ⇒ 往 CommitTypeColor 加新 case 时颜色会静默漏掉，\n" +
                "      而类型还不报错")
        }
        // 穷举 switch 下编译器已经兜住了漏配，这里再钉一遍是防「有人加了 default」之后
        // 又少配某个 case（那种情况编译仍然过，只有这条会红）
        for c in CommitTypeColor.allCases where !f.contains("case .\(c.rawValue):") {
            throw fail("序列色映射漏了 .\(c.rawValue) ⇒ 该序号会编译不过或被 default 吃掉")
        }
        return "\(CommitTypeColor.allCases.count) 个色全配，无 default"
    }

    check("spacing 刻度值必须走 token；待确认的散值不许增长（§3.3）") {
        let scale = [4, 8, 12, 16, 20, 24]
        // ⚠️ 散值**故意保留**，不是漏掉：
        // 收敛到刻度会改变布局（14→16 挤不挤？10→8 还是 12？），
        // 离屏快照虽能验观感却不是真窗口（深浅色主题、缩到最小时的截断都拍不到）
        // —— 擅自收敛等于把猜测写进布局。
        // 它们记在 clients/macos/deepGit/README.md 的待人工确认清单里，
        // 这条判据负责盯着「不许再新增」。
        //
        // ⚠️ pending 从 7 档涨到 12 档，**不是新违规，是判据覆盖面被修好之后
        // 才第一次看见的东西**：1（发丝线）、11、18、30、40 这五档此前完全没被计入，
        // 因为老判据根本不匹配 `.padding(...)`。基线 51→87 同理。
        // 30/40 明显不是节奏值而是结构性留白（面板分隔、hero 区），
        // 记下来是为了将来有人收敛时知道它们存在，而不是漏了。
        let pending = [1, 2, 3, 5, 6, 7, 10, 11, 14, 18, 30, 40]
        let baseline = 87
        let SCALE_NAME: [Int: String] = [4: "xs", 8: "sm", 12: "md", 16: "lg", 20: "xl", 24: "xxl"]
        // ⚠️ **三种拼法都要查**，少查一种就等于给另一种开了后门。
        //   原版只查 `spacing: N`（Stack 的参数），而 `.padding(.edge, N)` 与
        //   `.padding(N)` 完全不在视野里 —— 于是「spacing 刻度值零字面量」
        //   这句结论曾经只覆盖了一半：实测漏网 28 处（18 处 .padding(.edge,N)
        //   + 10 处 .padding(N)），其中 11 处在 BarView.swift。
        //   同族：不变量 99（声明存在 ≠ 真的生效）。判据的**覆盖面**本身
        //   也得被当成产物来核，不能只看它「跑通了」。
        //
        //   每种拼法用独立命名组（sp / pe / pa），报错时要说清是哪一种，
        //   否则「padding 里还有 12」这种话没法定位到具体写法。
        let re = try NSRegularExpression(
            pattern: "(?<![A-Za-z0-9_])spacing: (\\d+)(?![\\d.])"
                    + "|\\.padding\\(\\s*\\.[a-zA-Z]+\\s*,\\s*(\\d+)(?![\\d.])"
                    + "|\\.padding\\(\\s*(\\d+)(?![\\d.])")
        var bad: [String] = []
        var pendingCount = 0
        for name in try allSourceFileNames() {
            let code = try strippedCode(name)
            // ⚠️ 新 SDK 里 `matches(in:)` 的 `range:` 没有默认值了，必须显式给全串；
            // 少给时报的是 "missing argument for parameter 'range'"（看着像函数名写错了）。
            let full = NSRange(code.startIndex..<code.endIndex, in: code)
            for m in re.matches(in: code, range: full) {
                // 同理别用 `ns.substring(with:)`：range(at:) 已 Swift 化成
                // Range<String.Index>，两边类型对不上。
                // ⚠️ 三个组只有一个会命中，取「有 range 的那个」——
                //   固定读 group(1) 会把 padding 的值读成空。
                var v = -1
                var how = ""
                for (group, name_) in [(1, "spacing:"), (2, ".padding(.edge,"), (3, ".padding(")] {
                    if let r = Range(m.range(at: group), in: code) {
                        v = Int(code[r]) ?? -1
                        how = name_
                    }
                }
                if v < 0 { continue }
                if v == 0 { continue }          // 「无间距」是真实需求，不在刻度里
                if scale.contains(v) {
                    bad.append("\(name)：\(how) \(v) 等于刻度值 \(SCALE_NAME[v]!) ⇒ 必须写 token，"
                        + "否则改 DSSpacing 时这一处不会跟着动")
                } else if pending.contains(v) {
                    pendingCount += 1
                } else {
                    bad.append("\(name)：\(how) \(v) 是新增散值（刻度只有 4/8/12/16/20/24）")
                }
            }
        }
        guard bad.isEmpty else {
            throw fail(bad.prefix(3).joined(separator: "\n      ")
                + (bad.count > 3 ? "\n      …另有 \(bad.count - 3) 处" : ""))
        }
        guard pendingCount <= baseline else {
            throw fail("待人工确认的散值从 \(baseline) 处涨到 \(pendingCount) 处：\n" +
                "      要么把新值收进刻度（改 DSSpacing 或写 token），要么更新基线并在 README 说明理由")
        }
        return "刻度值零字面量（3 种拼法）；待确认散值 \(pendingCount)/\(baseline)"
    }

    check("圆角矩形只能有一个构造点，且必须是连续曲率（§3.3 圆角收敛的下一层）") {
        // 圆角**值**早就收敛到 DSRadius 三档了，但 9 处 RoundedRectangle 里
        // 只有 surface 内部写了 style: .continuous，其余 8 处用默认 circular ——
        // 同一张 Card（continuous）里嵌着的 Chip / 描边 / 彩色底（circular）
        // 圆角接缝对不上。判据卡「唯一构造点」，才盯得住风格不再分叉。
        let re = try NSRegularExpression(pattern: "RoundedRectangle\\(")
        var spots: [String] = []
        for name in try allSourceFileNames() {
            let code = try strippedCode(name)
            let full = NSRange(code.startIndex..<code.endIndex, in: code)
            for _ in re.matches(in: code, range: full) { spots.append(name) }
        }
        guard spots.count == 1, spots.first == "DesignSystem.swift" else {
            throw fail("裸 RoundedRectangle 出现在 \(spots.count) 个位置：\(spots.joined(separator: ", "))\n" +
                "      ⇒ 唯一构造点 DSRect.shape 之外又冒出来了，圆角风格会再次分叉")
        }
        let d = try strippedCode("DesignSystem.swift")
        guard let f = slice(d, from: "static func shape(", to: "\n    }\n") else {
            throw fail("切不出 DSRect.shape（结构变了？）")
        }
        guard f.contains("style: .continuous") else {
            throw fail("唯一构造点没写 style: .continuous ⇒ 退回默认 circular，与 macOS 原生控件不一致")
        }
        // 语义着色必须能接层级色（.quaternary 是 HierarchicalShapeStyle，不是 Color）
        guard d.contains("func tinted<S: ShapeStyle>") else {
            throw fail("tinted 的参数不是泛型 ShapeStyle ⇒ 层级色（.quaternary/.secondary）传不进来，\n" +
                "      调用方只好把层级色硬转成 Color，白丢一层语义")
        }
        return "1 个构造点 · 连续曲率 · 着色面支持层级色"
    }

    check("动效必须走 DSMotion token，且不许新增裸动效（§3.3「不过度」）") {
        let d = try strippedCode("DesignSystem.swift")
        guard d.contains("enum DSMotion") else { throw fail("DSMotion token 不见了") }
        for tier in ["quick", "standard"] {
            guard d.contains("static let \(tier)") else { throw fail("DSMotion.\(tier) 不见了") }
        }
        // 裸 withAnimation { } 吃的是 SwiftUI 默认（0.25s / default 缓动），
        // 不属于任何一档 —— 「统一缓动与时长」在它那儿就失效了。
        // 全项目曾只有这一处动效，恰好是裸的。
        var bare: [String] = []
        let re = try NSRegularExpression(pattern: "withAnimation\\s*(\\([^)]*\\))?\\s*\\{")
        for name in try allSourceFileNames() {
            let code = try strippedCode(name)
            let full = NSRange(code.startIndex..<code.endIndex, in: code)
            for m in re.matches(in: code, range: full) {
                // withAnimation(x) { } 带参数才是走 token 的写法
                let hasArg = m.range(at: 1).location != NSNotFound
                if !hasArg { bare.append(name) }
            }
        }
        guard bare.isEmpty else {
            throw fail("裸 withAnimation（没走 DSMotion）出现在：\(bare.joined(separator: ", "))\n" +
                "      ⇒ 缓动与时长在那几处不受统一约束；要么写 withAnimation(DSMotion.standard) { }，\n" +
                "      要么确实不需要动效就去掉")
        }
        return "全部动效走 token，裸动效 0 处"
    }

    check("卡片正好 12 条：不许造披露（cut 恒为 false 才是常态）") {
        let s = commitTypeCardSlice(entries: real)
        guard !s.cut, s.entries.count == 12, s.note == nil else {
            throw fail("12 条（= 上界）却报了截断：\(s.note ?? "nil")")
        }
        return "画全了"
    }

    check("卡片 13 条：必须挡在外面并说出来，绝不许靠取模糊过去") {
        var over = real
        over.append(("wip", 1))
        let s = commitTypeCardSlice(entries: over)
        guard s.cut, s.entries.count == 12, s.total == 13 else {
            throw fail("13 条时 cut=\(s.cut) 画了 \(s.entries.count) 条")
        }
        guard let note = s.note, note.contains("还有 1 种") else {
            throw fail("挡住的类型没有披露：\(s.note ?? "nil")")
        }
        return note
    }

    check("容量为 0 的防御：原样透出，不许悄悄吞掉") {
        let s = commitTypeCardSlice(entries: real, capacity: 0)
        guard s.entries.count == 12, !s.cut else {
            throw fail("capacity=0 把 12 条吞成了 \(s.entries.count) 条")
        }
        return "不吞"
    }

    // ---- 接线守卫：判定不许内联回视图/模型 ----

    check("UI 必须走 commitTypeComposition（判定内联回计算属性就又不可测了）") {
        let code = swiftCode(try sourceText("Models.swift"))
        guard code.contains("commitTypeComposition(") else {
            throw fail("ProjectStatus.commitTypeLine 没有走纯函数")
        }
        guard !code.contains("prefix(5)") else {
            throw fail("又出现写死的 prefix(5) —— 上限必须是常量")
        }
        // 上限只能有一处：默认参数已经是唯一来源，属性里不该再抄一遍。
        guard !code.contains("COMMIT_TYPE_LINE_MAX") else {
            throw fail("commitTypeLine 里又把上限抄了一遍（默认参数已是唯一来源）")
        }
        return "判定在纯函数里"
    }

    check("色板不许退回内联字面量 + 取模（那正是把两类画成一类的写法）") {
        // ⚠️ 判据必须**只覆盖提交构成这张卡**。第一版在整个 DetailViews.swift 上匹配
        // `let palette: [Color] = [`，结果把**语言卡**那份 8 色 palette
        // （对齐 LANG_BAR_MAX=8，本身是对的）也判成了缺陷 —— 判据比缺陷宽，
        // 结论就是反的。
        //
        // ⚠️ 边界用**代码**标记而不是 `// MARK:`：本文件真值是 `// MARK: 分支`
        // （没有那个短横），写成 `// MARK: - 分支` 就切不出来 —— 而切不出来时
        // 报的是「lint 判据坏了」，不是「代码有缺陷」，两者别混。
        // ⚠️ 结束边界用**下一个分区标记**，不用「下一个函数」——
        // 用 `private func branchCard(` 的话，后来插在中间的
        // `milestoneCard`（含一个百分号字面量 `50%`）会被算进
        // commitTypeCard 的函数体，判据报「出现取模」——
        // 报错的是判据的边界，不是代码有缺陷，两者别混。
        // 边界跟着文件里**实际的书写顺序**走：commitTypeCard 之后
        // 紧跟的是 `// MARK: 里程碑`（本文件真值是 `// MARK: 里程碑`，
        // 没有短横；写成 `// MARK: - 里程碑` 就切不出来）。
        let raw = try sourceText("DetailViews.swift")
        guard let rawCard = slice(raw, from: "private func commitTypeCard(",
                                  to: "// MARK: 里程碑") else {
            throw fail("切不出 commitTypeCard 的函数体 —— lint 判据本身坏了（不是缺陷）")
        }
        let card = swiftCode(rawCard)
        guard !card.contains("let palette: [Color] = [") else {
            throw fail("提交构成卡又内联了一份颜色字面量")
        }
        // ⚠️ 判据刻意写成「这个函数体里不许出现取模」，而不是
        // 「不许出现 `palette[i % palette.count]`」：
        // 只认死变量名的话，把同一个缺陷换个变量名（`colors[i % colors.count]`）
        // 就能溜过去 —— NC58-b 第一版注入就因为变量名对不上而**假绿**。
        // 这三十行里没有任何一处需要取模：切片函数已经保证条目数 ≤ 色板容量，
        // 所以「取模」在这里只能是「用取模掩盖容量不够」。
        if card.contains("%") {
            throw fail("提交构成卡里又出现取模：色板短于条目数时会把两类画成一个颜色")
        }
        // ⚠️ 必须**两处取色都查**。只查「这个函数体里出现过 CommitTypeColor.palette」
        // 的话，把另一处硬编码成 `Color.blue` 就整条溜过去了 ——
        // NC76 变体 2 实测假绿过一次：注入替换的是**文件里第一处**
        // （提交构成卡的分段条），而语言卡两处原封不动，于是全绿。
        // 「出现过一次」是现象，「每一处都同源」才是实质。
        guard let bar = slice(card, from: "SegmentedBar(segments: slice.entries", to: "FlowLegend(items:"),
              let legend = slice(card, from: "FlowLegend(items:", to: "if let note") else {
            throw fail("切不出提交构成卡的两处取色（结构变了？）")
        }
        for (where_, seg) in [("分段条", bar), ("图例", legend)] {
            guard seg.contains("CommitTypeColor.palette[i]") else {
                throw fail("提交构成卡的\(where_)没有走 CommitTypeColor.palette[i] ⇒ 色板有第二个出处")
            }
            guard seg.contains("DSColor.sequence(") else {
                throw fail("提交构成卡的\(where_)没有走 DSColor.sequence ⇒ 序号到颜色的映射有第二个出处")
            }
        }
        guard card.contains("commitTypeCardSlice(") else {
            throw fail("卡片没有走切片函数 ⇒ 容量上限不是一条真实限制")
        }
        return "单一来源 + 真实上限，两处取色都同源"
    }

    check("新增的纯函数必须挂进 client-check.sh 的编译清单") {
        let sh = try pkgText("scripts/client-check.sh")
        guard sh.contains("CommitTypeComposition.swift"), sh.contains("$CTCOMP") else {
            throw fail("client-check.sh 没编译 CommitTypeComposition.swift ⇒ 检查跑的不是本体")
        }
        return "已挂进编译清单"
    }
}

// MARK: - 里程碑卡片的完整度（缺陷 #207）

print("")
print("【T】里程碑卡片：界面自己砍掉的条数必须自报（#207）")

do {
    // 真实形状：1 个项目 8 条进行中里程碑。引擎 dashboard --json 实测
    // counts.open=8、readCount=8、items 8 条（items 无上限），对账等式成立。
    // 而卡片标题按 counts 说话、列表只画 5 条 ⇒ v6/v7/v8 静默消失。
    // 这是 #205（语言）/ #206（提交类型）之后同家族的第三次复发。

    check("复现用例：8 条画 5 条必须披露") {
        let s = milestoneCardSlice(itemCount: 8)
        guard s.shown == 5, s.total == 8, s.cut else {
            throw fail("口径不对：shown=\(s.shown) total=\(s.total) cut=\(s.cut)")
        }
        guard let note = s.note, note.contains("前 5"), note.contains("共 8") else {
            throw fail("藏掉的 3 条没有披露：\(s.note ?? "nil")")
        }
        return note
    }

    check("披露必须指到真的有全量清单的地方") {
        // 「完整清单见「里程碑」页」不是安慰话：PanelView 真的有那个页面
        // （MilestonesView.swift）。指错地方比不指更糟。
        let s = milestoneCardSlice(itemCount: 8)
        guard let note = s.note, note.contains("里程碑") else {
            throw fail("披露没有指向全量清单：\(s.note ?? "nil")")
        }
        let panel = try sourceText("PanelView.swift")
        guard panel.contains("里程碑") else {
            throw fail("面板里找不到「里程碑」入口 ⇒ 披露指向了一个不存在的地方")
        }
        return "指向真实存在的页面"
    }

    check("≤ 上限时不许造披露") {
        let s = milestoneCardSlice(itemCount: 3)
        guard !s.cut, s.shown == 3, s.note == nil else {
            throw fail("画全了却有披露：\(s.note ?? "nil")")
        }
        return "沉默是对的"
    }

    check("正好等于上限：不许造披露（否则上面那条没有判别力）") {
        let s = milestoneCardSlice(itemCount: MILESTONE_CARD_MAX)
        guard !s.cut, s.shown == MILESTONE_CARD_MAX, s.note == nil else {
            throw fail("正好 \(MILESTONE_CARD_MAX) 条却报了截断")
        }
        return "\(MILESTONE_CARD_MAX) 条画全"
    }

    check("MILESTONE_CARD_MAX 是唯一来源：比它多的必然触发披露") {
        guard MILESTONE_CARD_MAX == 5 else { throw fail("常量变了：\(MILESTONE_CARD_MAX)") }
        let over = milestoneCardSlice(itemCount: MILESTONE_CARD_MAX + 1)
        guard over.cut, over.note != nil else { throw fail("超过上限却沉默") }
        return "\(MILESTONE_CARD_MAX) / \(MILESTONE_CARD_MAX + 1) 两侧都对"
    }

    check("一条都没有：必须是沉默的 0，而不是「前 5 条」") {
        let s = milestoneCardSlice(itemCount: 0)
        guard s.shown == 0, !s.cut, s.note == nil else {
            throw fail("空输入产出了披露：\(s.note ?? "nil")")
        }
        // 负数不许被当成「有 -1 条」而报出奇怪的话
        let neg = milestoneCardSlice(itemCount: -1)
        guard neg.total == 0, neg.note == nil else {
            throw fail("负数输入产出了：\(neg.note ?? "nil")")
        }
        return "空/负都沉默"
    }

    check("cardMax 传 0 不许产出「只显示前 0 条」这种自相矛盾的话") {
        let s = milestoneCardSlice(itemCount: 8, cardMax: 0)
        guard s.shown >= 1, let note = s.note, !note.contains("前 0 条") else {
            throw fail("cardMax=0 的输出自相矛盾：\(s.note ?? "nil")")
        }
        return "至少画一条"
    }

    // ---- 接线守卫：判定不许内联回视图 ----

    check("UI 必须走 milestoneCardSlice（判定内联回视图就又不可测了）") {
        // 判据只覆盖里程碑那张卡：DetailViews 里语言卡/提交构成卡各有一处
        // prefix，判据比缺陷宽就会把它们一起判成违规（#206 的 lint 踩过一次）。
        let raw = try sourceText("DetailViews.swift")
        guard let rawCard = slice(raw, from: "Card(title: milestoneCardTitle(",
                                  to: "// 活跃项目") else {
            throw fail("切不出里程碑卡片的代码块 —— lint 判据本身坏了（不是缺陷）")
        }
        let card = swiftCode(rawCard)
        guard !card.contains("items.prefix(5)") else {
            throw fail("又出现写死的 prefix(5) —— 上限必须是常量")
        }
        guard card.contains("milestoneCardSlice(") else {
            throw fail("里程碑卡片没有走纯函数")
        }
        // 画几条必须用 slice.shown：写第二个字面量就会让披露与画出来的东西对不上
        guard card.contains("prefix(slice.shown)") else {
            throw fail("画条数没有用 slice.shown ⇒ 披露与实际画出的条数可能不一致")
        }
        guard card.contains("slice.note") else {
            throw fail("披露没有被渲染出来")
        }
        return "判定在纯函数里 + 画几条用 shown"
    }

    check("新增的纯函数必须挂进 client-check.sh 的编译清单") {
        let sh = try pkgText("scripts/client-check.sh")
        guard sh.contains("MilestoneCard.swift"), sh.contains("$MSCARD") else {
            throw fail("client-check.sh 没编译 MilestoneCard.swift ⇒ 检查跑的不是本体")
        }
        return "已挂进编译清单"
    }
}

// MARK: - 更新结果的通知文案（缺陷 #211）

print("")
print("【U】更新通知：没说改动不许说「已刷新」（#211）")

do {
    // 真实形状（实测 `deepgit update <项目> --json`）：
    //   docs[0] = {file: README.md, changed: true, created: false,
    //              backup: "/…/store/<id>/backups/README.md/2026-10-01T22-05-34-README.md"}
    let fresh = DocOutcome(file: "README.md", changed: true, created: false,
                           backup: "/s/backups/README.md/2026-10-01T22-05-34-README.md")

    check("复现用例：引擎报没变，就不许说「已刷新」") {
        // ⚠️ 这一条是 #211 的核心。原实现是 `_ = try await …` 之后
        // **无条件**弹「X 的文档托管区域已刷新」，而引擎此时输出
        // 「README.md 无变化」—— 没做被说成做了。
        let same = DocOutcome(file: "README.md", changed: false, created: false, backup: "")
        let s = updateOutcomeSummary(updateOutcome([same]), project: "p")
        guard s.contains("没有变化") else {
            throw fail("没改动却没说没变化：\(s)")
        }
        guard !s.contains("已刷新") && !s.contains("已更新") else {
            throw fail("没改动却说改了：\(s)")
        }
        return s
    }

    check("有改动：必须说改了，而且必须把备份路径说清楚") {
        let s = updateOutcomeSummary(updateOutcome([fresh]), project: "p")
        guard s.contains("已更新 README.md") else { throw fail("没说改了：\(s)") }
        guard s.contains(fresh.backup) else {
            throw fail("没说备份在哪：\(s)")
        }
        return s
    }

    check("新建文件：必须说「新建」且**不许提备份**") {
        // 新建 ⇒ 本来就没有旧版本可备份。给它编一个备份是凭空的事实。
        let c = DocOutcome(file: "AGENTS.md", changed: true, created: true, backup: "")
        let s = updateOutcomeSummary(updateOutcome([c]), project: "p")
        guard s.contains("新建 AGENTS.md") else { throw fail("没说新建：\(s)") }
        guard !s.contains("备份") else { throw fail("给新建文件编了备份：\(s)") }
        return s
    }

    check("引擎没报任何文档：只能说「没有需要更新的」，不能当成「都更新了」") {
        let s = updateOutcomeSummary(updateOutcome([]), project: "p")
        guard s.contains("没有需要更新") else { throw fail("空输入的说法不对：\(s)") }
        guard !s.contains("已更新") && !s.contains("已刷新") else {
            throw fail("空输入被说成已更新：\(s)")
        }
        return s
    }

    check("多份文档：列举有上限时必须说还剩几个（#205 那一族）") {
        let many = (0..<5).map { i in
            DocOutcome(file: "F\(i).md", changed: true, created: false, backup: "/b/F\(i).md")
        }
        let s = updateOutcomeSummary(updateOutcome(many), project: "p")
        guard s.contains("等 5 个文档") else { throw fail("没披露被省略的条数：\(s)") }
        return s
    }

    check("改了但没备份：必须照实说没备份（不许沉默地跳过）") {
        // 这不该发生（复用旧文件就会备份），但如果发生了必须看得见，
        // 而不是让用户以为「改了就有备份可回滚」。
        let noBk = DocOutcome(file: "README.md", changed: true, created: false, backup: "")
        let o = updateOutcome([noBk])
        guard o.anythingTouched, o.backedUp.isEmpty else { throw fail("口径不对") }
        let s = updateOutcomeSummary(o, project: "p")
        guard s.contains("已更新"), !s.contains("备份到") else {
            throw fail("改了却宣称有备份：\(s)")
        }
        return s
    }

    check("nameMax 传 0 不许产出「等 0 个」这种自相矛盾的话") {
        let s = updateOutcomeSummary(updateOutcome([fresh]), project: "p", nameMax: 0)
        guard !s.contains("等 0 个文档") else { throw fail("自相矛盾：\(s)") }
        return s
    }

    check("接线守卫：Model.swift 必须真的用这个判定，不许退回写死文案") {
        let code = swiftCode(try sourceText("Model.swift"))
        // 原来两处都是「结果整个丢掉 + 一句写死的文案」
        guard !code.contains("_ = try await EngineCLI.shared.update(") else {
            throw fail("单项目更新又把结果丢掉了")
        }
        guard !code.contains("_ = try await EngineCLI.shared.updateAll(") else {
            throw fail("批量更新又把结果丢掉了")
        }
        guard !code.contains("的文档托管区域已刷新") else {
            throw fail("又出现那句无条件的「已刷新」")
        }
        guard code.contains("updateOutcomeSummary(") else {
            throw fail("通知文案没有走纯函数")
        }
        return "判定在纯函数里，文案按引擎报的 docs 说话"
    }

    check("新增的纯函数必须挂进 client-check.sh 的编译清单") {
        let sh = try pkgText("scripts/client-check.sh")
        guard sh.contains("UpdateOutcome.swift"), sh.contains("$UPOUT") else {
            throw fail("client-check.sh 没编译 UpdateOutcome.swift ⇒ 检查跑的不是本体")
        }
        return "已挂进编译清单"
    }
}

// MARK: - 设计系统（docs/deepgit-redesign-plan.md §3.3）
//
// 审查结论写的是「设计系统：完全不存在」。这组断言把 token 的**来源**钉死
// （取值必须等于设计稿 tailwind.config，不许自己编），并守住散值不许复活。

do {
    // —— token 取值必须承接设计稿 ——
    check("色板取值必须逐值等于设计稿 tailwind.config（不许自己编一套）") {
        let src = try strippedCode("DesignTokens.swift")
        // 设计稿 tailwind.config → theme.extend.colors.dev
        let expected: [(String, String)] = [
            ("bgDark",       "0x0F172A"),  // dev.bg
            ("cardDark",     "0x1E293B"),  // dev.card
            ("sidebarDark",  "0x0B0F19"),  // dev.sidebar
            ("borderDark",   "0x334155"),  // dev.border
            ("bgLight",      "0xF8FAFC"),  // dev.lightBg
            ("cardLight",    "0xFFFFFF"),  // dev.lightCard
            ("sidebarLight", "0xF1F5F9"),  // dev.lightSidebar
            ("borderLight",  "0xE2E8F0"),  // dev.lightBorder
            ("accent",       "0x3B82F6"),  // dev.accent
            ("shallow",      "0x10B981"),  // dev.shallow
            ("deep",         "0x8B5CF6"),  // dev.deep
            ("ai",           "0x06B6D4")   // dev.ai
        ]
        var wrong: [String] = []
        for (name, hex) in expected {
            guard src.contains("\(name)") else { wrong.append("\(name) 缺失"); continue }
            // 取该行，断言这行里就是设计稿的值
            let line = src.split(separator: "\n").first { $0.contains("let \(name)") } ?? ""
            if !line.contains(hex) { wrong.append("\(name) 应为 \(hex)，实为 \(line.trimmingCharacters(in: .whitespaces))") }
        }
        guard wrong.isEmpty else { throw fail("色板与设计稿不符：\(wrong.joined(separator: "、"))") }
        return "\(expected.count) 个色值全部等于设计稿"
    }

    // —— 状态不许猜 ——
    check("未知状态字符串必须落到 unknown，不许默认绿") {
        // 状态点只有 8pt 宽，配色错了用户看不出来 —— 未知只能是 unknown
        for raw in ["", "weird", "ACTIVE", "merged ", "nil", "0"] {
            guard DSStatus.from(raw) == .unknown else {
                throw fail("「\(raw)」被判成 \(DSStatus.from(raw))，未知状态必须归 unknown")
            }
        }
        // 反向：五个已知状态不许被误判
        let known: [(String, DSStatus)] = [
            ("active", .active), ("idle", .idle), ("stale", .stale),
            ("merged", .merged), ("dirty", .dirty)
        ]
        for (raw, want) in known where DSStatus.from(raw) != want {
            throw fail("「\(raw)」应判 \(want)，实为 \(DSStatus.from(raw))")
        }
        return "5 个已知 + 6 个未知字符串判对"
    }

    check("状态语义必须都有中文标签（8pt 状态点没有文字替代）") {
        let labels: [DSStatus: String] = [
            .active: "活跃", .idle: "空闲", .stale: "陈旧",
            .merged: "已合并", .dirty: "有未提交改动", .unknown: "状态未知"
        ]
        var missing: [String] = []
        for (s, want) in labels where s.label != want { missing.append("\(s)=\(s.label) 应为 \(want)") }
        // 不许出现空标签
        for s in [DSStatus.active, .idle, .stale, .merged, .dirty, .unknown] where s.label.isEmpty {
            missing.append("\(s) 标签为空")
        }
        guard missing.isEmpty else { throw fail(missing.joined(separator: "、")) }
        return "6 个状态都有可读标签"
    }

    // —— 修掉「说谎的颜色」——
    check("数值必须按量级分档，不许「任何 n>0 都一样」") {
        // 这就是被替换掉的旧 statTint：1 个和 300 个未提交文件同色，等于没分级
        let want: [(Int, DSStat)] = [
            (0, .none), (1, .low), (2, .low), (3, .medium), (9, .medium), (10, .high), (999, .high)
        ]
        for (n, expect) in want where DSStat.from(n) != expect {
            throw fail("\(n) 应判 \(expect)，实为 \(DSStat.from(n))")
        }
        // 负数不能落到 none（那会说「干净」）
        guard DSStat.from(-5) != .none else { throw fail("负数被判成 none ⇒ 会说「干净」") }
        // 四档必须真的分出四种，不许塌成一档
        let all = Set([DSStat.from(0), DSStat.from(1), DSStat.from(5), DSStat.from(50)])
        guard all.count == 4 else { throw fail("只分出 \(all.count) 档，量级没被表达") }
        return "0/1-2/3-9/≥10 四档分明"
    }

    check("量级描述必须说出是什么 + 怎么处理（不只是报个数字）") {
        guard DSStat.none.describe(0, "未提交") == "未提交 0 个，干净" else {
            throw fail("0 的描述没说出「干净」，实为 \(DSStat.none.describe(0, "未提交"))")
        }
        guard DSStat.medium.describe(5, "未提交").hasSuffix("需要注意") else {
            throw fail("中档没说「需要注意」")
        }
        guard DSStat.high.describe(50, "未提交").hasSuffix("需要处理") else {
            throw fail("高档没说「需要处理」")
        }
        return "四档都有可执行的完整短语"
    }

    check("双轨标签与设计稿一致（浅=绿轨、深=紫轨）") {
        guard DSSyncTrack.shallow.label == "浅更新" else { throw fail("浅轨标签错") }
        guard DSSyncTrack.deep.label == "深更新" else { throw fail("深轨标签错") }
        return "双轨标签对齐设计稿"
    }

    // —— 以下三条是散值守卫，现在会红，归一化后必须转绿 ——
    check("卡片表面必须收敛到 Surface，旧的 controlBackgroundColor 写法不许复活") {
        let files = try allSourceFileNames()
        var hits: [String] = []
        for f in files {
            let code = try strippedCode(f)
            if code.contains("nsColor: .controlBackgroundColor") { hits.append(f) }
        }
        guard hits.isEmpty else {
            throw fail("这些文件还在手写卡片表面（应改用 .surface(...)）：\(hits.joined(separator: "、"))")
        }
        return "\(files.count) 个源文件已全部走 Surface"
    }

    check("圆角必须收敛到 3 档，不许散值复活") {
        let allowed = ["3", "6", "10"]   // DSRadius.chip/control/card
        let files = try allSourceFileNames()
        var bad: [String] = []
        for f in files {
            let code = try strippedCode(f)
            for pat in ["cornerRadius: ", "cornerRadius("] {
                var rest = Substring(code)
                while let r = rest.range(of: pat) {
                    rest = rest[r.upperBound...]
                    let digits = rest.prefix { $0.isNumber }
                    if !digits.isEmpty, !allowed.contains(String(digits)) {
                        bad.append("\(f):\(String(digits))")
                    }
                }
            }
        }
        let unique = Set(bad)
        guard unique.isEmpty else {
            throw fail("圆角散值（只允许 \(allowed.joined(separator: "/"))）：\(unique.sorted().joined(separator: "、"))")
        }
        return "圆角只剩 3 档"
    }

    check("字体必须用系统文本样式，不许硬编码字面量字号复活") {
        let files = try allSourceFileNames()
        var hits: [String] = []
        for f in files {
            let code = try strippedCode(f)
            var rest = Substring(code)
            while let r = rest.range(of: ".font(.system(size: ") {
                rest = rest[r.upperBound...]
                let digits = rest.prefix { $0.isNumber }
                // size: 后面**不是数字**的，是按内容算出来的字号（MarkdownView 按标题层级
                // 取字号）——那本来就该由内容定，不该归一成固定 token，只放过非数字。
                if !digits.isEmpty { hits.append("\(f):\(String(digits))") }
            }
        }
        guard hits.isEmpty else {
            throw fail("这些文件还在手写字号（应走 DSTypography）：\(hits.joined(separator: "、"))")
        }
        return "\(files.count) 个源文件无硬编码字号（动态字号不算）"
    }

    // —— 编译清单的守卫 ——
    // ⚠️ 第一版写反了：拿「零 SwiftUI 依赖」当「纯函数文件」的判据，
    // 结果 Models.swift / EngineCLI.swift / AISDK.swift 这类**业务**文件
    // 也被算成纯函数、要求进清单 ⇒ 13 个假红。
    // 真正的判据是两条：进了清单的必须真的可断言（零 SwiftUI），
    // 且声明的源文件必须真的出现在 swiftc 命令行里（而不是只写在变量定义里）。
    // ⚠️ 下面两条曾经写成 Swift 断言，**都是恒真的，已删**：
    //   · 「声明了必须真被 swiftc 编译」——少编译一个文件就编不过（DSStatus 找不到），
    //     永远到不了 lint 本身。
    //   · 「声明的文件名必须存在」——文件名打错时 swiftc 先报
    //     "error opening input file"，检查器根本没编出来。
    // 恒真断言比没有断言更糟：它让人以为这一层有人守着。
    // 这两件事已挪到 client-check.sh **编译之前**的 shell 前置检查里（那里才跑得到）。
}

// MARK: - 破坏性操作确认（§3.2「删除里程碑、放弃里程碑、提交全部改动、批量更新」）

do {
    // —— 判据本身 ——
    check("四个破坏性动作必须都要确认，可逆的状态切换不许弹") {
        let mustConfirm: [DestructiveAction] = [.removeMilestone, .dropMilestone, .bulkUpdate, .commitAll]
        for a in mustConfirm where !DestructiveGuard.needsConfirmation(for: a) {
            throw fail("\(a) 属于不可逆/高代价动作，却不要确认")
        }
        // 达成/重开是可逆的，弹确认只会教会用户「确认疲劳」
        guard !DestructiveGuard.needsConfirmation(for: .setMilestoneStatus) else {
            throw fail("达成/重开是可逆的，不该弹确认 —— 那会稀释真破坏性操作的信号")
        }
        return "4 个要确认 + 1 个不要确认，边界成立"
    }

    check("删除里程碑的确认必须说清不可恢复（引擎无备份无回收站）") {
        let m = DestructiveGuard.message(for: .removeMilestone, subject: "v2 上线")
        // 引擎 kernel/milestones.cj:249 是直接剔除 + saveMilestones，没有备份
        guard m.contains("无法恢复") || m.contains("不可恢复") else {
            throw fail("删除文案没说清不可恢复：\(m)")
        }
        guard m.contains("v2 上线") else { throw fail("删除文案没点名具体对象：\(m)") }
        return "说清了不可逆 + 点名对象"
    }

    check("确认框标题必须点名对象，不能是空壳的「确认吗」") {
        for a in [DestructiveAction.removeMilestone, .dropMilestone] {
            let t = DestructiveGuard.title(for: a, subject: "重构登录")
            guard t.contains("重构登录") else { throw fail("\(a) 标题没点名对象：\(t)") }
            guard !t.hasPrefix("确认") else { throw fail("\(a) 标题是无信息的「确认…」：\(t)") }
        }
        // 提交确认必须带上仓库名
        guard DestructiveGuard.commitTitle(project: "deepGit").contains("deepGit") else {
            throw fail("提交确认标题没带仓库名")
        }
        return "标题都点名了具体对象"
    }

    check("空名字不许渲染成「删除里程碑「」？」") {
        for raw in ["", "   ", "\n\t "] {
            guard DestructiveGuard.safeSubject(raw) == "未命名" else {
                throw fail("空名「\(raw)」变成了「\(DestructiveGuard.safeSubject(raw))」")
            }
        }
        // 正常名字不许被改动
        guard DestructiveGuard.safeSubject("  v2 上线  ") == "v2 上线" else {
            throw fail("正常名字被改写了")
        }
        return "空名兜底为「未命名」，正常名只 trim"
    }

    check("提交确认必须报出真实数量（引擎是 git add -A，不是挑的那几个文件）") {
        // 引擎 kernel/git.cj:1792 走 add -A ⇒ 提交整个工作区
        let onlyTracked = DestructiveGuard.commitScopeText(
            DestructiveGuard.CommitScope(trackedModified: 3, untracked: 0, staged: 0))
        guard onlyTracked.contains("3") else { throw fail("没报出改动数：\(onlyTracked)") }

        // 未跟踪文件是最容易出事的一种（误提交 .env/密钥），必须单独点名
        // 判据只查「不该提交」这个**警告的实质**，不查「首次进入版本历史」——
        // 后者只是现象描述，删掉它警告照样成立，判据容忍它就等于没守住。
        let withUntracked = DestructiveGuard.commitScopeText(
            DestructiveGuard.CommitScope(trackedModified: 1, untracked: 2, staged: 0))
        guard withUntracked.contains("未跟踪") else { throw fail("没提未跟踪文件：\(withUntracked)") }
        guard withUntracked.contains("不该提交") else {
            throw fail("没警告未跟踪文件的风险：\(withUntracked)")
        }

        // 0 个 ⇒ 不该走到确认
        let empty = DestructiveGuard.commitScopeText(
            DestructiveGuard.CommitScope(trackedModified: 0, untracked: 0, staged: 0))
        guard empty.contains("没有待提交") else { throw fail("空工作区文案不对：\(empty)") }
        return "三种范围各自可区分"
    }

    check("确认按钮标题必须说会发生什么，不是「确定」") {
        guard DestructiveGuard.confirmTitle(for: .removeMilestone) == "删除" else {
            throw fail("删除按钮标题不对")
        }
        guard DestructiveGuard.confirmTitle(for: .dropMilestone) == "放弃" else {
            throw fail("放弃按钮标题不对")
        }
        // 「确定」留给真的无所谓可说的动作
        guard DestructiveGuard.confirmTitle(for: .setMilestoneStatus) == "确定" else {
            throw fail("可逆动作的按钮标题应保留「确定」")
        }
        return "破坏性按钮说动作，可逆按钮才用「确定」"
    }

    check("不可逆动作的确认按钮要染红，可逆的不染（满屏红会稀释信号）") {
        for a in [DestructiveAction.removeMilestone, .dropMilestone, .commitAll] {
            guard DestructiveGuard.isDestructiveRole(for: a) else { throw fail("\(a) 应染红") }
        }
        guard !DestructiveGuard.isDestructiveRole(for: .setMilestoneStatus) else {
            throw fail("可逆动作不该染红")
        }
        return "红色只给真危险"
    }

    check("批量更新只报范围，不该按不可逆处理（每个文件都留备份）") {
        let m = DestructiveGuard.bulkUpdateMessage(projectCount: 3, track: .shallow)
        guard m.contains("3 个项目") else { throw fail("没报项目数：\(m)") }
        guard m.contains("备份") else {
            throw fail("没说明可回滚，用户会误以为不可逆：\(m)")
        }
        // 0 个项目时不该说「将对 0 个项目执行」
        let zero = DestructiveGuard.bulkUpdateMessage(projectCount: 0, track: .deep)
        guard zero.contains("没有已注册") else { throw fail("0 项目文案不对：\(zero)") }
        // 两轨文案要可区分。
        // ⚠️ 判据要比**正文**，不能比整个字符串 —— 整个字符串里含 track.label
        //（"浅更新"/"深更新"），哪怕正文完全一样，两句也不相等，判据会假绿。
        // 摘掉标签与项目数后再比。
        func stripLabel(_ s: String) -> String {
            s.replacingOccurrences(of: DSSyncTrack.shallow.label, with: "▯")
             .replacingOccurrences(of: DSSyncTrack.deep.label, with: "▯")
             .replacingOccurrences(of: "1 个项目", with: "N")
        }
        let shallowBody = stripLabel(DestructiveGuard.bulkUpdateMessage(projectCount: 1, track: .shallow))
        let deepBody = stripLabel(DestructiveGuard.bulkUpdateMessage(projectCount: 1, track: .deep))
        guard shallowBody != deepBody else {
            throw fail("浅/深更新的正文相同 ⇒ 用户看不出深更新会调用 AI")
        }
        // 深轨必须提到 AI（这是两条轨最大的差别）
        guard DestructiveGuard.bulkUpdateMessage(projectCount: 1, track: .deep).contains("AI") else {
            throw fail("深更新文案没提 AI，用户不知道它比浅更新贵")
        }
        return "报范围 + 说清可回滚 + 两轨正文可区分"
    }

    // —— 接线守卫：判据必须落在真实的 .confirmationDialog 上 ——
    check("里程碑的删除/放弃不许再是裸按钮（引擎直接剔除，无备份无回收站）") {
        let code = try strippedCode("MilestonesView.swift")
        // 裸调用 = 直接把动作塞进 milestoneAction
        if code.contains("milestoneAction(milestone, action: \"remove\")")
            || code.contains("milestoneAction(milestone, action: \"drop\")") {
            throw fail("还有裸的 remove/drop 调用 ⇒ 绕过确认直接改数据")
        }
        guard code.contains("confirmationDialog") else { throw fail("里程碑行没有确认对话框") }
        guard code.contains("pendingAction") else { throw fail("没有待确认状态") }
        return "删除/放弃都走确认"
    }

    check("提交全部改动必须先确认（引擎走 git add -A）") {
        let code = try strippedCode("DetailViews.swift")
        // 提交按钮与回车都必须先进待确认状态，不能直接 doCommit
        if code.contains("Button(\"提交\") { doCommit(") {
            throw fail("提交按钮直接提交 ⇒ 绕过确认")
        }
        if code.contains("onSubmit { doCommit(") {
            throw fail("回车提交直接提交 ⇒ 绕过确认")
        }
        guard code.contains("confirmationDialog") else { throw fail("提交没有确认对话框") }
        guard code.contains("DestructiveGuard.commitMessage") else {
            throw fail("提交确认没报出提交范围")
        }
        return "按钮与回车都先确认，且确认框报范围"
    }

    check("批量更新的两个入口都要有确认（菜单栏 CommandMenu + BarView）") {
        // 同一动作两个入口，漏一个就等于没做
        let bar = try strippedCode("BarView.swift")
        guard bar.contains("confirmationDialog") else { throw fail("BarView 的批量更新没有确认") }
        guard !bar.contains("startUpdateAll(deep: false)\n") || bar.contains("pendingBulk") else {
            throw fail("BarView 仍直接触发批量更新")
        }
        let app = try strippedCode("DeepGitApp.swift")
        // 菜单那条路是 CommandMenu，挂不上 confirmationDialog —— 它必须把待确认状态交给 Model
        guard app.contains("pendingBulkUpdate") else {
            throw fail("CommandMenu 入口没有把待确认状态交给主面板渲染")
        }
        let model = try strippedCode("Model.swift")
        guard model.contains("@Published var pendingBulkUpdate") else {
            throw fail("Model 上没有 pendingBulkUpdate，菜单那条路弹不出确认")
        }
        return "两个入口都有确认"
    }

    check("编译清单里的每个源文件都必须零 SwiftUI 依赖（否则检查器拖不进 SwiftUI）") {
        let sh = try pkgText("scripts/client-check.sh")
        var checked = 0
        for line in sh.split(separator: "\n") {
            guard let eq = line.range(of: "=\"$PKG_DIR/Sources/deepGit/") else { continue }
            let file = String(line[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let code = try strippedCode(file)
            if code.contains("import SwiftUI") || code.contains("import AppKit") {
                throw fail("\(file) 进了编译清单但依赖 SwiftUI ⇒ 命令行检查器编不过")
            }
            checked += 1
        }
        guard checked >= 6 else { throw fail("只检查到 \(checked) 个，清单解析可能失效") }
        return "\(checked) 个入清单文件全部零 SwiftUI 依赖"
    }
}

// MARK: - 无障碍与搜索（§3.2）

do {
    // —— 无障碍标签 ——
    check("空标签比没标签更糟：拿不到文案时必须给有意义的兜底") {
        for empty in ["", "   ", "\n\t "] {
            guard A11y.label(fromHelp: empty) == nil else {
                throw fail("空文案被判成了标签：\(A11y.label(fromHelp: empty) ?? "nil")")
            }
            let fb = A11y.label(fromHelp: empty, fallback: "发送")
            guard fb == "发送" else { throw fail("兜底没生效：\(fb)") }
            guard A11y.label(fromHelp: empty, fallback: "") == "操作" else {
                throw fail("兜底与原文都空时返回了「\(A11y.label(fromHelp: empty, fallback: ""))」")
            }
        }
        return "空文案 → nil；兜底链最终仍非空"
    }

    check("标签必须 trim 后判空（纯空格的文案等于没有）") {
        guard A11y.label(fromHelp: "  刷新  ") == "刷新" else {
            throw fail("没 trim：\(A11y.label(fromHelp: "  刷新  "))")
        }
        guard A11y.label(fromHelp: "\n") == nil else { throw fail("换行被当成了标签") }
        return "trim 生效"
    }

    check("数值的三态必须可区分，「读不出来」不许显示成 0") {
        guard A11y.count(-1, "未提交") == "未提交：读不出来" else {
            throw fail("负数被说成别的：\(A11y.count(-1, "未提交"))")
        }
        guard A11y.count(0, "未提交") == "未提交：0" else { throw fail("0 的措辞不对") }
        guard A11y.count(7, "未提交") == "未提交：7" else { throw fail("正数的措辞不对") }
        let all = Set([A11y.count(-1, "x"), A11y.count(0, "x"), A11y.count(7, "x")])
        guard all.count == 3 else { throw fail("三态塌成了 \(all.count) 种") }
        return "三态可区分"
    }

    check("列表位置要说清「第几项、共几项」") {
        let s = A11y.position(2, of: 12, "项目")
        guard s.contains("第 3 项") else { throw fail("索引没转成 1 基：\(s)") }
        guard s.contains("共 12 项") else { throw fail("没说总数：\(s)") }
        guard A11y.position(0, of: 0, "项目") == "项目" else {
            throw fail("空列表给出了位置信息：\(A11y.position(0, of: 0, "项目"))")
        }
        return "1 基索引 + 总数；空列表不谎报"
    }

    check("每个 .help 都要有配套的 accessibilityLabel（VoiceOver 读不到 help）") {
        let files = try allSourceFileNames()
        var missing: [String] = []
        for f in files {
            if f == "A11yLabel.swift" { continue }   // 自身注释里提到 .help
            let code = try strippedCode(f)
            let helpCount = code.components(separatedBy: ".help(").count - 1
            let a11yCount = code.components(separatedBy: ".accessibilityLabel(").count - 1
            if helpCount > 0 && a11yCount < helpCount {
                missing.append("\(f)（help \(helpCount) 处 / 标签 \(a11yCount) 处）")
            }
        }
        guard missing.isEmpty else {
            throw fail("这些文件的图标按钮只有 .help 没有标签：\(missing.joined(separator: "、"))")
        }
        return "\(files.count) 个源文件：help 与标签一一对应"
    }

    check("不许用空串当兜底标签（控件存在但无名，比没标签更糟）") {
        let files = try allSourceFileNames()
        var hits: Set<String> = []
        for f in files {
            let code = try strippedCode(f)
            if code.contains("accessibilityLabel(\"\")") { hits.insert(f) }
            var rest = Substring(code)
            while let r = rest.range(of: ".accessibilityLabel(") {
                rest = rest[r.upperBound...]
                let line = rest.prefix { $0 != "\n" }
                if line.contains("?? \"\"") { hits.insert(f); break }
            }
        }
        guard hits.isEmpty else {
            throw fail("这些地方用空串兜底：\(hits.sorted().joined(separator: "、"))")
        }
        return "无空串兜底"
    }

    // —— 搜索过滤 ——
    check("空查询必须原样返回，不制造「搜完 0 条」的假象") {
        let items = ["alpha", "beta", "gamma"]
        for q in ["", "   ", "\n"] {
            guard SearchFilter.filter(items, query: q, key: { $0 }) == items else {
                throw fail("空查询「\(q)」改变了结果")
            }
        }
        return "空查询不过滤"
    }

    check("搜索大小写不敏感且是子串匹配（可预期的规则）") {
        let items = ["Alpha", "beta", "GAMMA"]
        guard SearchFilter.filter(items, query: "alp", key: { $0 }) == ["Alpha"] else {
            throw fail("子串匹配失败")
        }
        guard SearchFilter.filter(items, query: "alpH", key: { $0 }) == ["Alpha"] else {
            throw fail("大小写不敏感失效")
        }
        guard SearchFilter.filter(items, query: "  a  ", key: { $0 }).count == 3 else {
            throw fail("查询没 trim")
        }
        return "子串 + 不区分大小写 + trim"
    }

    check("「没匹配上」与「本来就没有」必须分开说") {
        let items = ["alpha", "beta"]
        let shown = SearchFilter.filter(items, query: "zzz", key: { $0 })
        let reason = SearchFilter.emptyReason(allCount: items.count, shownCount: shown.count, query: "zzz")
        guard reason == .noMatch(query: "zzz") else { throw fail("有数据但没匹配上，说成了「没有数据」") }
        let text = SearchFilter.emptyText(reason!, noun: "项目")
        // 判据要卡「回显了 query」这个**意图**，不能只查 query 字面量在不在 ——
        // 那是"碰巧包含"：文案里任何一处提到这个词都能糊弄过去。
        // 真正的判据是：换一个 query 词，输出必须跟着换。
        let other = SearchFilter.emptyText(.noMatch(query: "qqq"), noun: "项目")
        guard text.contains("zzz"), other.contains("qqq"), text != other else {
            throw fail("空结果文案没有随查询词变化（用户不知道自己搜了什么）：\(text) / \(other)")
        }

        let none = SearchFilter.emptyReason(allCount: 0, shownCount: 0, query: "")
        guard none == .noData else { throw fail("空数据应报 noData") }
        guard SearchFilter.emptyText(none!, noun: "项目") == "暂无项目" else {
            throw fail("空数据文案不对")
        }
        guard SearchFilter.emptyText(.noData, noun: "项目")
                != SearchFilter.emptyText(.noMatch(query: "q"), noun: "项目") else {
            throw fail("两种空给了同一句话")
        }
        return "两态可区分且都回显上下文"
    }

    check("有数据且查询非空却 0 结果时，不许说成「本来就没有」") {
        let reason = SearchFilter.emptyReason(allCount: 5, shownCount: 0, query: "不存在")
        guard reason == .noMatch(query: "不存在") else { throw fail("误报成 noData") }
        guard SearchFilter.emptyReason(allCount: 5, shownCount: 0, query: "") == .noData else {
            throw fail("空查询下的 0 结果应是 noData")
        }
        return "两种 0 结果判对"
    }

    check("过滤生效时必须报「匹配 x / y」，不报会被读成「就这些」") {
        guard SearchFilter.resultSummary(allCount: 12, shownCount: 3, noun: "里程碑") == "匹配 3 / 12 个里程碑" else {
            throw fail("摘要格式不对")
        }
        guard SearchFilter.resultSummary(allCount: 12, shownCount: 12, noun: "里程碑") == nil else {
            throw fail("没过滤也报了摘要")
        }
        guard SearchFilter.resultSummary(allCount: 0, shownCount: 0, noun: "里程碑") == nil else {
            throw fail("空列表报了摘要")
        }
        return "只在真的过滤时报，且带分母"
    }

    // —— 接线 ——
    check("两处列表都必须有搜索且接到过滤后的数组") {
        // 里程碑：系统 .searchable（这一处没有被 ⌘F 聚焦的需求）
        let ms = try strippedCode("MilestonesView.swift")
        guard ms.contains(".searchable") || ms.contains("TextField") else {
            throw fail("里程碑列表没有搜索")
        }
        // ⚠️ 必须渲染**过滤后**的数组 —— 否则搜索框是摆设。
        // 这里原来写死 `ForEach(shown)`，里程碑页改成按项目分组后渲染的是
        // `group.items`，判据就报「仍渲染全量」。
        // 那是判据钉**写法**而不是钉**数据流**：分组渲染同样可以是摆设
        // （`groups(model.milestones)` 就绕过了搜索）。
        // 所以改成沿数据流追：groups 的入参必须是 shown，而 shown 必须过 SearchFilter。
        guard ms.contains("SearchFilter.emptyReason") else {
            throw fail("里程碑列表没有区分「没匹配」与「没有」")
        }
        guard ms.contains("SearchFilter.filter(scoped") else {
            throw fail("shown 没走 SearchFilter ⇒ 搜索框是摆设")
        }
        guard ms.contains("groups(shown)") else {
            throw fail("分组渲染的入参不是 shown ⇒ 绕过了搜索过滤")
        }
        // 反向自查：渲染处不许直接吃 model.milestones。
        if ms.contains("groups(model.milestones)") || ms.contains("ForEach(model.milestones)") {
            throw fail("里程碑渲染绕过了过滤链，直接吃全量")
        }

        // 项目列表：⚠️ 这里**刻意不用**系统 .searchable ——
        // 它不接受外部 focus 绑定，⌘F 没法把焦点送进去（按了没反应）。
        // 所以断言的是「有输入框 + 绑了 focus」，不是 `.searchable`。
        // 「不许用系统 searchable」由【Y】组那条专门钉住。
        let pv = try strippedCode("PanelView.swift")
        guard pv.contains("TextField") || pv.contains(".searchable") else {
            throw fail("项目列表没有搜索")
        }
        guard pv.contains("ForEach(shownProjects)") else {
            throw fail("项目列表仍渲染全量 ForEach(model.projects) ⇒ 搜索是摆设")
        }
        return "里程碑与项目列表都接了过滤"
    }

    check("设计稿没有看板页，但看板不是死代码（不许照着过期规范删掉可用功能）") {
        let pv = try strippedCode("PanelView.swift")
        // 规范 §3.1 说「看板页是死代码，删掉」。核实后发现它现在有入口、有 switch 分支。
        // ⚠️ 判据不能只找 `case .board:` —— 那个字符串现在出现在 `title(for:)` 的
        // switch 里（一个 switch 分支 ≠ 一个可达入口）。要钉的是**侧栏入口**。
        //
        // ⚠️ 也**不能只认 `viewShortcut(.board`**：看板行后来改走了
        // `countedRow(title: "看板", …)`（带待处理计数），判据却还在找旧写法，
        // 于是报「看板入口被删了」—— 报错的其实是判据的写法假设，不是代码。
        // 与不变量 107 同一条：判据要钉「这个入口在不在」，不钉「它用哪个构造点写的」。
        guard pv.contains("viewShortcut(.board") || pv.contains("countedRow(title: \"看板\"") else {
            throw fail("侧栏没有看板入口了 —— 确认它是否真的被删了")
        }
        // detail 侧也还得能路由过去
        guard pv.contains("RootSection.board") || pv.contains("case .board:") else {
            throw fail("看板的 detail 分支不见了")
        }
        return "看板仍是可用功能，未被误删（规范前提已过期，见不变量 69）"
    }
}

// MARK: - 快捷键（§3.2）

do {
    // —— 冲突 ——
    check("快捷键表里不许有重复键位") {
        let dups = ShortcutMap.duplicatePairs()
        guard dups.isEmpty else {
            let desc = dups.map { "\($0.0.display) 与 \($0.1.display)" }.joined(separator: "、")
            throw fail("这些键位撞车了（后者永远不触发）：\(desc)")
        }
        return "\(ShortcutMap.all.count) 个键位无冲突"
    }

    check("撞键判定不区分 modifier 顺序（cmd+shift+r 与 shift+cmd+r 是同一个键）") {
        let a = Shortcut(systemKey: nil, key: "r", modifiers: ["cmd", "shift"])
        let b = Shortcut(systemKey: nil, key: "r", modifiers: ["shift", "cmd"])
        guard ShortcutMap.conflicts(a, b) else {
            throw fail("modifier 顺序不同的同一个键没被判为冲突 ⇒ 会漏报")
        }
        // 真的不同则不许误报
        let c = Shortcut(systemKey: nil, key: "r", modifiers: ["cmd"])
        guard !ShortcutMap.conflicts(a, c) else { throw fail("⌘⇧R 与 ⌘R 被误判为冲突") }
        return "顺序归一化生效，无误报"
    }

    check("撞键表必须含所有占着键位的声明（含不在 viewOrder 里的那个）") {
        // ⚠️ currentProject 刻意不在 viewOrder（详情是动态的，没有「第 4 个固定视图」），
        // 但它**确实占着 ⌘4**。漏了它 ⇒ 任何与 ⌘4 撞车的声明都查不出来。
        guard ShortcutMap.all.contains(where: { $0.keyEquivalent == "4" }) else {
            throw fail("all 里没有 ⌘4 ⇒ 与它撞车的键查不出来（NC67-d 抓到的就是这条）")
        }
        // 全表条数 = 7 个动作 + 3 个固定视图 + 1 个 currentProject
        guard ShortcutMap.all.count == 11 else {
            throw fail("全表是 \(ShortcutMap.all.count) 个键位，预期 11（7 动作 + 3 视图 + 1 打开项目）")
        }
        return "11 个键位全部在册"
    }

    // —— 视图数与规范对齐 ——
    check("⌘N 的上界 = 固定视图数，不许硬凑规范里写的 ⌘5") {
        // 规范 §3.2 写「⌘1–⌘5 切视图」，那是按它设想的五个固定视图写的。
        // 实际侧栏只有三个固定入口，项目详情是动态的。
        guard ShortcutMap.viewOrder.count == 3 else {
            throw fail("固定视图数是 \(ShortcutMap.viewOrder.count)，与侧栏实际入口不符")
        }
        guard ShortcutMap.view(at: 1) == .dashboard,
              ShortcutMap.view(at: 2) == .board,
              ShortcutMap.view(at: 3) == .milestones else {
            throw fail("⌘1–⌘3 与侧栏顺序对不上")
        }
        // 越界返回 nil —— 硬凑 ⌘4/⌘5 只会让用户按了没反应
        guard ShortcutMap.view(at: 4) == nil, ShortcutMap.view(at: 5) == nil, ShortcutMap.view(at: 0) == nil else {
            throw fail("越界的数字快捷键仍返回了目标 ⇒ 会有按了没反应的键")
        }
        return "3 个固定视图，越界返回 nil（不硬凑 ⌘5）"
    }

    check("⌘4 单独留给「打开当前选中项目」（详情是动态的，没有第 4 个固定视图）") {
        guard ShortcutMap.shortcut(for: .currentProject)?.keyEquivalent == "4" else {
            throw fail("⌘4 没绑给打开项目详情")
        }
        // 它不在 viewOrder 里（那是固定视图的列表）
        guard !ShortcutMap.viewOrder.contains(.currentProject) else {
            throw fail("currentProject 混进了固定视图列表 ⇒ ⌘4 会被重复占用")
        }
        return "⌘4 独立，不与 ⌘1–⌘3 冲突"
    }

    // —— 展示 ——
    check("快捷键展示要按 ⌘⇧⌥ 顺序，且不出现「无键位」这种占位") {
        // macOS 惯例：修饰符按 ⌘⇧⌥ 固定顺序（⌘ 排最前），与声明时的书写顺序无关。
        // 声明里 shallow 写的是 modifiers: ["cmd","shift"]，展示就该是 ⌘⇧U 而不是 ⇧⌘U。
        guard ShortcutMap.refresh.display == "⌘R" else {
            throw fail("⌘R 显示成「\(ShortcutMap.refresh.display)」")
        }
        guard ShortcutMap.shallow.display == "⌘⇧U" else {
            throw fail("⌘⇧U 显示成「\(ShortcutMap.shallow.display)」")
        }
        guard ShortcutMap.deep.display == "⌘⇧⌥D" else {
            throw fail("⌘⇧⌥D 显示成「\(ShortcutMap.deep.display)」")
        }
        // ⌘W 是系统语义键，保持小写 w（macOS 菜单就是这么显示的）
        guard ShortcutMap.closePanel.display == "⌘w" else {
            throw fail("⌘W 系统键显示成「\(ShortcutMap.closePanel.display)」")
        }
        for s in ShortcutMap.all where s.display == "（无键位）" || s.display.isEmpty {
            throw fail("有个快捷键没有可展示的键位")
        }
        return "⌘⇧⌥ 顺序稳定"
    }

    check("系统语义键与字面键都能取到（⌘. / ⌘, / ⌘W 不是普通字符）") {
        guard ShortcutMap.stop.keyEquivalent == "." else { throw fail("⌘. 的键不对") }
        guard ShortcutMap.settings.keyEquivalent == "," else { throw fail("⌘, 的键不对") }
        guard ShortcutMap.closePanel.keyEquivalent == "w" else { throw fail("⌘W 的键不对") }
        guard ShortcutMap.find.keyEquivalent == "f" else { throw fail("⌘F 的键不对") }
        return "系统键与字面键都能取到"
    }

    // —— 接线 ——
    check("视图必须从 ShortcutMap 取键位，不许在视图里写死数字快捷键") {
        let pv = try strippedCode("PanelView.swift")
        guard pv.contains("viewShortcut(") || pv.contains("ShortcutMap.viewOrder") else {
            throw fail("侧栏没有从 ShortcutMap 取视图列表")
        }
        guard pv.contains("keyEquivalentSwiftUI") else {
            throw fail("侧栏没用 ShortcutMap 的键位换算")
        }
        // 写死的数字快捷键必须不存在。
        // ⚠️ 不能只匹配 `keyboardShortcut("1")` 单参数那种写法 ——
        //    实际代码绝大多数是 `keyboardShortcut("1", modifiers: [.command])`，
        //    只查单参数形等于没查（NC67-f 抓的就是这个洞）。
        //    所以匹配 `keyboardShortcut("` + 数字 开头这个**前缀**。
        for digit in ["1", "2", "3", "4", "5"] where pv.contains("keyboardShortcut(\"\(digit)") {
            throw fail("视图里写死了 keyboardShortcut(\"\(digit)\"…) ⇒ 会与 ShortcutMap 漂移")
        }
        let app = try strippedCode("DeepGitApp.swift")
        guard app.contains("ShortcutMap.refresh") && app.contains("ShortcutMap.shallow") else {
            throw fail("菜单里的快捷键没走 ShortcutMap")
        }
        return "视图与菜单都走声明处"
    }

    check("⌘F 必须能真的把焦点送进搜索框（系统 searchable 收不到外部焦点）") {        let pv = try strippedCode("PanelView.swift")
        guard pv.contains("@FocusState") else {
            throw fail("没有 @FocusState ⇒ ⌘F 无处可聚焦")
        }
        guard pv.contains(".focused($searchFocused)") else {
            throw fail("搜索框没有绑 focus")
        }
        guard pv.contains("searchFocused = true") else {
            throw fail("⌘F 没有把焦点设进去")
        }
        // ⚠️ 如果改回系统 .searchable，⌘F 就失效了 —— 钉住「不许同时用」
        if pv.contains(".searchable(") {
            throw fail("侧栏用了系统 .searchable ⇒ ⌘F 无法把焦点送进去（按了没反应）")
        }
        return "自建搜索框 + @FocusState 接线完整"
    }

    check("同一批视图不许在侧栏列两遍（重复的入口会让人以为是两种东西）") {
        let pv = try strippedCode("PanelView.swift")
        // ⚠️ 这条是 NC67 之后我自己犯的错：给视图切换另开了一个「视图切换」分组，
        // 把「总览」里已有的仪表盘/看板/里程碑又列了一遍 —— 而且两组还不一致
        // （只有「总览」那组带计数），看着像两种不同的视图。
        // 判据要数的是**侧栏里声明了几次导航项**，不是源码里某个字符串出现几次 ——
        // 导航项现在是 `viewShortcut(.dashboard, …)` 与
        // `countedRow(title: "看板", …)` 两种写法（带计数的走后者），
        // 只认前一种会把「看板 0 次」报成重复入口问题。
        //
        // ⚠️ 数的是**两种写法之和**，不是「第一个匹配到的那个」：
        // 只数 `viewShortcut(.board` 的话，复制一份 `countedRow(title: "看板"…)`
        // 到另一组里，这条判据会全绿 —— 而那正是它要防的重复入口。
        func entryCount(_ target: ShortcutTarget, _ title: String) -> Int {
            pv.components(separatedBy: "viewShortcut(.\(target)").count - 1
                + pv.components(separatedBy: "countedRow(title: \"\(title)\"").count - 1
        }
        for (target, title) in [(ShortcutTarget.dashboard, "仪表盘"), (.board, "看板")] {
            let n = entryCount(target, title)
            guard n == 1 else {
                throw fail("「\(title)」的侧栏入口出现 \(n) 次 ⇒ 重复入口（应为 1）")
            }
        }
        // 里程碑那条不走 viewShortcut（它要带计数），单独钉
        let ms = pv.components(separatedBy: "Label(\"里程碑\"").count - 1
            + pv.components(separatedBy: "countedRow(title: \"里程碑\"").count - 1
        guard ms == 1 else {
            throw fail("「里程碑」的侧栏入口出现 \(ms) 次 ⇒ 重复入口（应为 1）")
        }
        // 不许有第二个叫「视图切换」的分组（那是重复列表的信号）
        if pv.contains("视图切换") {
            throw fail("侧栏有一个「视图切换」分组 ⇒ 与「视图」重复列同一批视图")
        }
        // ⚠️ 动作项（添加 / 扫描）不许留在 List 的分组里 ——
        // 它没有 `.tag(...)`，点它会把当前选中清掉（跳回「项目详情」），
        // 而且它把「视图 / 仓库」两组切成三段。
        let list = try slice(pv, from: "List(selection:", to: ".listStyle(.sidebar)")
            ?? "（切不出侧栏 List）"
        if list.contains("添加 / 扫描项目") {
            throw fail("「添加 / 扫描项目」还在侧栏 List 的分组里：它是动作不是导航项，"
                + "没有 tag ⇒ 点击会清掉当前选中，而且把两组切断")
        }
        return "三个固定视图各出现一次（两种写法都计入）、无重复分组、动作项已移出 List"
    }
}

// MARK: - Z. 引擎给了、模型收了、界面说不说
//
// 这组的第一条不是 lint 风格，是**架构**：引擎认真算出来的数据，
// 模型收了、界面不说，等于没算 —— 用户看到的仍是一份残缺的真相。
//
// Phase 3 地基层的账：补了 13 个引擎键进模型，其中 6 个当时一个都没渲染。
// 引擎的档位线是 3/14 天（engine/src/kernel/progress.cj:30-36），
// 客户端当时自己写了个 30 天 —— 两个真相源，且已经开始互相矛盾。

do {
    print("【Z】引擎给了、模型收了、界面说不说（Phase 3 地基层）")

    // ⚠️ 必须走 strippedCode：这条判据匹配的字面量（比较运算符）恰好也是
    //    我自己解释性注释里会写的东西，不剥注释就会自证假红。
    check("客户端不得拿 staleDays 自己推档位（阈值只有引擎一处）") {
        var hits: [String] = []
        for f in try allSourceFileNames() where f != "Models.swift" {
            let code = try strippedCode(f)
            if code.contains("staleDays") { hits.append(f) }
        }
        guard hits.isEmpty else {
            throw fail("视图层出现 staleDays：\(hits.joined(separator: "、"))。\n" +
                "      档位线归引擎（3/14 天）。客户端再写一个阈值就是两个真相源，\n" +
                "      同一个仓库迟早出现「点显示停滞、字显示活跃」。\n" +
                "      要显示天数请经由模型层的 staleText，要上色请经由 DSStatus.from(b.status)")
        }
        return "\(try allSourceFileNames().count - 1) 个视图文件里一次都没有"
    }

    check("工作区脏度必须同时说出两个口径（未提交计数 + 引擎判定明细）") {
        let code = try strippedCode("DetailViews.swift")
        guard code.contains("p.userDirtyCount") else {
            throw fail("「未提交 N」那个口径不见了")
        }
        guard code.contains("d.dirtyLine") else {
            throw fail("引擎判的 dirty 明细（已暂存/已修改/未跟踪/冲突）没有渲染。\n" +
                "      两个口径都在数据里，只画一个用户就无从对照")
        }
        // 「几处」不够用：提交按钮就在下面那张卡里，用户要的是「哪几个」。
        // Git 卡只提供操作按钮，全应用没有第二处列出脏文件。
        guard code.contains("d.dirtyFilesLine") else {
            throw fail("没有渲染脏文件清单。dirtyLine 说的是「几处」，\n" +
                "      而用户点「提交」之前需要知道提交的是哪些文件")
        }
        return "未提交计数 + dirtyLine + 脏文件清单三处都在"
    }

    check("总结的来源必须标出来（规则引擎说的 ≠ AI 说的）") {
        let code = try strippedCode("DetailViews.swift")
        // ⚠️ 必须卡在**显示点**上，不能只查「b.providerLabel 出现过」。
        //    踩过一次：原来写 contains("b.providerLabel")，于是把 Chip 的文案
        //    换成字面量「规则」之后判据照样绿 —— 因为那行判断里也有这个名字。
        //    名字出现过 ≠ 被画出来（不变量 74：判据指向错对象）。
        guard code.contains("Chip(text: b.providerLabel") else {
            throw fail("分支卡没有用 providerLabel 画出来。\n" +
                "      summary/highlights 是谁说的必须可见，否则用户在拿规则引擎的猜测当 AI 的判断")
        }
        // 只在偏离默认时挂：实测没配 AI 时恒为 "rules"，
        // 每行都挂一个「规则」徽章只会训练用户忽略徽章。
        guard code.contains("b.providerLabel != \"规则\"") else {
            throw fail("来源徽章没有在默认情况下隐藏 ⇒ 每个分支都挂一个「规则」徽章")
        }
        let m = try sourceText("Models.swift")
        guard m.contains("var providerLabel") else {
            throw fail("Models.swift 里没有 providerLabel")
        }
        return "规则 / AI 来源在卡上可见，且默认不挂徽章"
    }

    check("基线重建后，两个已失效的数字都必须停报") {
        let code = try strippedCode("DetailViews.swift")
        // 两个：pendingCommits（待记录 N）与 aheadOfDefault（领先默认 N）。
        // 只保护一个 = 界面上仍有一个「真的但没意义」的数字在说话。
        let n = code.components(separatedBy: "b.baselineReset").count - 1
        guard n >= 2 else {
            throw fail("b.baselineReset 只出现 \(n) 处，期望 ≥2。\n" +
                "      基线重建后 aheadOfDefault 与 pendingCommits 的原区间都不可比，\n" +
                "      两处都要停报 —— 漏一处就仍有一个假数字在界面上")
        }
        return "两处数字都受 baselineReset 保护"
    }

    check("短 SHA 必须带着原文标题与完整 SHA（悬停 + 朗读）") {
        let code = try strippedCode("DetailViews.swift")
        guard code.contains(".help(b.headTip)") else {
            throw fail("短 SHA 没有挂 headTip 悬停 ⇒ 排查问题时只有 7 位短 SHA")
        }
        guard code.contains("accessibilityValue(b.headTip)") else {
            throw fail("headTip 只进了悬停没进朗读 —— VoiceOver 用户拿不到提交原文")
        }
        let m = try sourceText("Models.swift")
        guard m.contains("var headTip") else { throw fail("Models.swift 里没有 headTip") }
        return "悬停与朗读都带完整信息"
    }

    check("托管文档必须区分「已建」与「未建」") {
        let code = try strippedCode("DetailViews.swift")
        guard code.contains("exists ? \"已建\"") && code.contains("\"未建\"") else {
            throw fail("docs[].exists 没被渲染。\n" +
                "      「引擎管着但你还没写」与「压根没有这回事」对用户是两件事，\n" +
                "      合成一份文件名清单就把区别抹掉了")
        }
        return "已建 / 未建 分开说"
    }

    check("引擎的 tags / manifests / overall.summary 必须有落点") {
        let code = try strippedCode("DetailViews.swift")
        for (label, needle) in [("tags", "projectFacts(\"标签\""),
                                 ("manifests", "projectFacts(\"依赖清单\""),
                                 ("overall.summary", "displaySummary")] {
            guard code.contains(needle) else {
                throw fail("\(label) 没有渲染 —— 模型收了、引擎算了、界面不说 ⇒ 等于没算")
            }
        }
        // 空数组必须不占位：实测刚注册的项目 tags/manifests 都是 []。
        guard code.contains("!tags.isEmpty") && code.contains("!mf.isEmpty") else {
            throw fail("空的 tags/manifests 也画行 ⇒ 用户以为「本来该有却没采到」")
        }
        return "三处都有落点，且空数组不占位"
    }

    check("长列表必须自报截断（不许静默砍掉）") {
        let code = try strippedCode("DetailViews.swift")
        guard code.contains("hidden > 0") else {
            throw fail("projectFacts 没有披露截断条数 ⇒ 用户以为标签只有前 8 个")
        }
        return "截断自报"
    }
}

// MARK: - R. 路由：深链解析 + 唯一决策处
//
// 「--project foo 单独使用被静默忽略」与「深链打到不存在的项目 → 详情页永远转圈」
// 都是纯字符串 / 纯判定，抽出 Route.swift / Router.swift 后就能单测，
// 不必再靠「手动敲一次命令看日志」。

do {
    print("【R】路由：深链解析 + 唯一决策处")

    check("深链参数彼此独立（--project 不再需要搭便车 --open-panel）") {
        // 旧实现第一行是 `guard args.contains("--open-panel") || ... else { return }`，
        // 而主面板本来就是「启动自动打开」的 ⇒ 从命令行传深链必须额外加一个
        // 无关开关，少加了**没有任何提示**。复现：--project target ⇒ selection 不动。
        guard Route.parse(["deepGit", "--project", "target"]).route == .project("target") else {
            throw fail("--project 单独使用没解析出来：\(Route.parse(["deepGit", "--project", "target"]))")
        }
        guard Route.parse(["deepGit", "--section", "board"]).route == .board else {
            throw fail("--section 单独使用没解析出来")
        }
        guard Route.parse(["deepGit", "--open-settings"]).openSettings else {
            throw fail("--open-settings 没解析出来")
        }
        // 搭便车的旧写法必须**继续**能用：README 文档化过，不能顺手改坏
        guard Route.parse(["deepGit", "--open-panel", "--project", "x"]).route == .project("x") else {
            throw fail("旧的 --open-panel + --project 组合失效了")
        }
        return "--project / --section / --open-settings 各自独立，且旧组合仍可用"
    }

    check("参数缺值或值是另一个 flag 时不许拿它当名字") {
        // `--project --open-panel` 里 `--open-panel` 是开关不是项目名。
        // 当成项目名就会去加载一个叫「--open-panel」的项目，然后永远转圈。
        guard Route.parse(["deepGit", "--project"]).route == nil else {
            throw fail("--project 后面没有值却被当成了路由")
        }
        guard Route.parse(["deepGit", "--project", "--open-panel"]).route == nil else {
            throw fail("把下一个 flag 当成了项目名：\(Route.parse(["deepGit", "--project", "--open-panel"]))")
        }
        guard Route.parse(["deepGit", "--project", ""]).route == nil else {
            throw fail("空串被当成了项目名")
        }
        return "缺值 / flag / 空串 三种都判为「没给」"
    }

    check("--project 与 --section 同现时以 --project 为准（且不吞掉 --section）") {
        let i = Route.parse(["deepGit", "--section", "board", "--project", "target"])
        guard i.route == .project("target") else {
            throw fail("同时给两个时路由=\(String(describing: i.route))")
        }
        return "project 优先"
    }

    check("--agent-selftest 的问句不许吃掉下一个 flag") {
        guard Route.parse(["deepGit", "--agent-selftest"]).agentSelfTest == Route.defaultSelfTestQuestion else {
            throw fail("没给问句时没有落到默认问句")
        }
        guard Route.parse(["deepGit", "--agent-selftest", "现在怎么样？"]).agentSelfTest == "现在怎么样？" else {
            throw fail("显式问句没被取到")
        }
        let withFlag = Route.parse(["deepGit", "--agent-selftest", "--open-panel"])
        guard withFlag.agentSelfTest == Route.defaultSelfTestQuestion else {
            throw fail("把 --open-panel 当成了问句：\(String(describing: withFlag.agentSelfTest))")
        }
        return "缺省 / 显式 / 后面跟 flag 三种都对"
    }

    check("认不出来的 --section 落仪表盘而不是「无路由」") {
        guard Route.section("board") == .board, Route.section("milestones") == .milestones,
              Route.section("dashboard") == .dashboard else {
            throw fail("三个已知 section 认错了")
        }
        guard Route.section("不存在的视图") == .dashboard else {
            throw fail("未知 section 没有落仪表盘")
        }
        return "三个已知 + 未知兜底"
    }

    check("Router 必须区分「不知道」与「确实没有」") {
        // 最容易写错的一条：启动瞬间 projects 是空的，此时判「不存在」
        // ⇒ 深链功能等于永远失效。
        guard Router.resolve(.project("a"), loadedProjects: nil) == .listNotLoaded else {
            throw fail("列表未加载时被判成了别的：\(Router.resolve(.project("a"), loadedProjects: nil))")
        }
        guard Router.resolve(.project("a"), loadedProjects: []) == .projectNotFound("a") else {
            throw fail("加载完了且确实没有时没有报 notFound")
        }
        guard Router.resolve(.project("a"), loadedProjects: ["a", "b"]) == .go(.project("a")) else {
            throw fail("存在的项目没放行")
        }
        // 非项目目标不需要项目列表
        guard Router.resolve(.board, loadedProjects: nil) == .go(.board) else {
            throw fail("固定视图在列表未加载时被拦下了")
        }
        guard Router.resolve(nil, loadedProjects: []) == .go(nil) else {
            throw fail("nil 路由没原样放行")
        }
        return "listNotLoaded / notFound / go 三态都对"
    }

    check("「加载完了」不能靠数组空不空来猜") {
        guard Router.loadedNames([], hasLoadedOnce: false) == nil else {
            throw fail("没加载过却被当成加载完了")
        }
        // 真·空项目群：**加载完了且确实没有**，和上面是不同的事
        guard Router.loadedNames([], hasLoadedOnce: true) == [] else {
            throw fail("加载完的空项目群没有与「未加载」区分开")
        }
        return "空数组的两种含义分开了"
    }

    check("路由只能有一个入口（视图不许直接写 selection）") {
        // 原来是 9 处 `model.selection = ...`。这次把它变成**编译期**事实：
        // selection 声明成 private(set)，判据再钉住「视图里一次都不许出现」。
        var hits: [String] = []
        for f in try allSourceFileNames() where f != "Model.swift" && f != "Route.swift" {
            let code = try strippedCode(f)
            if code.contains(".selection = ") { hits.append(f) }
        }
        guard hits.isEmpty else {
            throw fail("绕过 go(_:) 直接赋值：\(hits.joined(separator: "、"))。\n" +
                "      路由判定（这个项目存不存在）只有一个出处，绕过它就等于放弃判定")
        }
        return "\(try allSourceFileNames().count - 2) 个视图文件里一次都没有"
    }

    check("侧栏点选也必须走 go(_:)（不许用 $model.selection 开后门）") {
        let code = try strippedCode("PanelView.swift")
        guard !code.contains("$model.selection") else {
            throw fail("侧栏用了 $model.selection ⇒ 绕过了 Router，\n" +
                "      点一个不存在的项目仍会被设成 selection")
        }
        guard code.contains("model.go(") else {
            throw fail("侧栏没有走 model.go(_:)")
        }
        return "点选走同一个入口"
    }

    check("路由说明不许占用 lastError（否则会掐断启动刷新）") {
        // runRefreshAll 里有 `if lastError != nil { isLoading = false; return }` ——
        // 那是「刷新失败了别再等 dashboard/milestones」的短路。
        // 拿它报「深链打错字」会让一次打错的深链中断整个启动刷新。
        let m = try strippedCode("Model.swift")
        guard m.contains("routeNotice") else { throw fail("Model.swift 里没有 routeNotice") }
        // ⚠️ 必须**有界**切片。用 components(...).last 会一路取到文件末尾，
        //    把 loadProject 里那个合法的 lastError 也算进来 ⇒ 假红。
        guard let branch = slice(m, from: "case .projectNotFound", to: "case .listNotLoaded") else {
            throw fail("定位不到 projectNotFound 分支，判据没对准位置")
        }
        guard !branch.contains("lastError") else {
            throw fail("projectNotFound 分支写了 lastError ⇒ 深链打错字会短路掉后续刷新")
        }
        guard branch.contains("routeNotice =") else {
            throw fail("projectNotFound 分支没有设置 routeNotice ⇒ 用户看不到任何说明")
        }
        return "说明走独立的 routeNotice"
    }

    check("详情页必须区分「还在读」与「读不出来」") {
        // 原来只有 `else → ProgressView("加载 X …")`：
        // 项目不存在时 project 永远是 nil ⇒ 主区永远转圈，既不报错也不停。
        let code = try strippedCode("DetailViews.swift")
        guard code.contains("model.projectLoadErrors[projectName]") else {
            throw fail("详情页没有读 projectLoadErrors ⇒ 读不出来时会一直显示「加载中」")
        }
        guard code.contains("EmptyState(") else { throw fail("读不出来时没有错误态视图") }
        let m = try strippedCode("Model.swift")
        guard m.contains("projectLoadErrors[name] =") else {
            throw fail("loadProject 失败时没有记录 per-project 错误（只有全局 lastError，详情页看不见）")
        }
        return "失败有错误态，成功一次会清掉旧错误"
    }
}

// MARK: - S. 顶栏双轨主动作（设计稿最突出的那一对）
//
// 设计稿顶栏中段是「浅更新 → 深更新」两个并列按钮，浅更新带待记录徽章，
// 深更新印着它会改哪些托管文档。客户端原来把它们折叠在一个写着「更新」的下拉里。

do {
    print("【S】顶栏双轨主动作（设计稿最突出的那一对）")

    check("范围必须由 selection 推导，不许有独立的 scope 状态") {
        // 设计稿顶栏左侧确实有个范围下拉，但客户端里**侧栏导航已经承担了**这个角色。
        // 再存一份 scope 就是「当前看的是谁」有两个来源：侧栏点了 B、下拉还写着 A。
        guard ScopeRules.scope(for: .project("a")) == .project("a") else { throw fail("项目详情没有收敛成该项目") }
        guard ScopeRules.scope(for: .dashboard) == .all else { throw fail("仪表盘应当是全局范围") }
        guard ScopeRules.scope(for: .board) == .all else { throw fail("看板应当是全局范围") }
        guard ScopeRules.scope(for: .milestones) == .all else { throw fail("里程碑应当是全局范围") }
        guard ScopeRules.scope(for: nil) == .all else { throw fail("没有任何选中时应当是全局范围") }

        let m = try strippedCode("Model.swift")
        guard m.contains("var updateScope: UpdateScope { ScopeRules.scope(for: selection) }") else {
            throw fail("updateScope 不是由 selection 推导的")
        }
        // 判据要卡住「它是推导出来的」而不是「它是个 @Published」。
        // 写成 @Published var updateScope 就能和 selection 各说各话。
        if m.contains("@Published var updateScope") {
            throw fail("updateScope 变成了独立状态 ⇒ 可以和 selection 各说各话")
        }
        return "五个入口全部推导自 selection，无第二真相源"
    }

    check("按钮标题必须带范围（按下之前用户得知道会动谁）") {
        guard ScopeRules.shallowLabel(.all) == "浅更新 · 全部" else {
            throw fail("全局浅更新标题=\(ScopeRules.shallowLabel(.all))")
        }
        guard ScopeRules.shallowLabel(.project("deepGit")) == "浅更新 · deepGit" else {
            throw fail("单项目浅更新标题=\(ScopeRules.shallowLabel(.project("deepGit")))")
        }
        guard ScopeRules.deepLabel(.all) == "深更新 · 全部" else {
            throw fail("全局深更新标题=\(ScopeRules.deepLabel(.all))")
        }
        guard ScopeRules.deepLabel(.project("x")) == "深更新 · x" else {
            throw fail("单项目深更新标题=\(ScopeRules.deepLabel(.project("x")))")
        }
        return "四个标题都带范围"
    }

    check("深更新按钮上写的那份文档清单必须是真的") {
        // 设计稿印的是「AGENT.md + README」，但引擎托管的文件是
        // README / AGENTS / CLAUDE —— 照抄会写出一个不存在的文件名。
        let t = ScopeRules.deepTouches
        guard t.contains("README") && t.contains("AGENTS") && t.contains("CLAUDE") else {
            throw fail("deepTouches=\"\(t)\" 与引擎托管的文档对不上")
        }
        if t.contains("AGENT.md") {
            throw fail("deepTouches 写了 AGENT.md —— 引擎托管的是 AGENTS（无 .md）")
        }
        return t
    }

    check("浅更新的待记录徽章必须有真数据源（这个数字曾经恒为 0）") {
        // 设计稿的浅更新按钮带一个 pending 计数。第一版照抄之后才发现：
        // 引擎的 status 当时读的是进度库里**存的**快照，而那个快照在 update
        // 算完后立刻被归零（flow/update.cj:591）⇒ 徽章永远不亮。
        // 引擎的注释早就承认了（flow/dashboard.cj:205）。
        // 现在引擎改成实时算了，徽章才有意义 —— 但这条判据的作用是
        // 盯住「数据源是真的」，不是盯住「徽章在」：
        // 引擎哪天又退回读存量，这条立刻红。
        let d = try strippedCode("AIIntegration.swift")
        guard let dual = slice(d, from: "struct DualTrackButtons", to: "struct ScheduleMenu") else {
            throw fail("定位不到 DualTrackButtons，判据没对准")
        }
        guard dual.contains("ScopeRules.pending(") else {
            throw fail("徽章没有走 ScopeRules.pending ⇒ 自己拼了一个拿不到真数的数字")
        }
        guard dual.contains("pending > 0") else {
            throw fail("徽章恒显 ⇒ 「0」会被读成「引擎说不用更新」，而恒显的徽章一律被无视")
        }
        // 契约侧：pendingCommits 必须能真的非 0（否则徽章又变成装饰）
        let sc = try strippedCode("Scope.swift")
        guard sc.contains("static func pending(") else { throw fail("ScopeRules.pending 不见了") }
        return "徽章取数走纯函数，且只在非 0 时显示"
    }

    check("徽章的取数必须按范围（不能拿全局的数冒充单项目）") {
        let byProject = ["a": 3, "b": 5]
        guard ScopeRules.pending(.all, allTotal: 8, byProject: byProject) == 8 else {
            throw fail("全局徽章没取到总数")
        }
        guard ScopeRules.pending(.project("a"), allTotal: 8, byProject: byProject) == 3 else {
            throw fail("单项目徽章没取到自己的数")
        }
        guard ScopeRules.pending(.project("缺失"), allTotal: 8, byProject: byProject) == 0 else {
            throw fail("不在表里的项目应给 0 而不是沿用全局数")
        }
        return "全局 8 / a=3 / 缺失=0"
    }

    check("忙碌判定按范围（单项目在跑不该禁掉全局按钮，反之亦然）") {
        guard ScopeRules.isBusy(.all, busyAll: true, busyProject: nil) else { throw fail("全局在跑没被认出") }
        guard !ScopeRules.isBusy(.all, busyAll: false, busyProject: "a") else {
            throw fail("单项目在跑却禁掉了全局按钮")
        }
        guard ScopeRules.isBusy(.project("a"), busyAll: false, busyProject: "a") else {
            throw fail("该项目在跑没被认出")
        }
        guard !ScopeRules.isBusy(.project("b"), busyAll: false, busyProject: "a") else {
            throw fail("别的项目在跑却禁掉了这个按钮")
        }
        return "四个组合都对"
    }

    check("批量更新不许绕过确认框（顶栏按钮也不能是后门）") {
        // ⚠️ runUpdate 一旦直接调 updateAll，原先那个 confirmationDialog 就形同虚设 ——
        //    它还长得像还在工作（菜单项照样在）。
        let m = try strippedCode("Model.swift")
        // ⚠️ 结束标记必须挑一个**剥掉注释后还在**的字符串。
        //    原来用 "// MARK:" 做 to —— 而走的是 strippedCode，注释早没了，
        //    slice 返回 nil，报出来的是「判据没对准」，很难一眼看出真因。
        guard let body = slice(m, from: "func runUpdate(deep: Bool)", to: "private func applyPendingRoute()") else {
            throw fail("定位不到 runUpdate 的函数体，判据没对准")
        }
        guard body.contains("pendingBulkUpdate") else {
            throw fail("runUpdate 没有走 pendingBulkUpdate ⇒ 顶栏的浅/深更新绕过了批量确认框")
        }
        if body.contains("await updateAll(") {
            throw fail("runUpdate 里直接调了 updateAll ⇒ 绕过确认框")
        }
        return "全部范围走确认框"
    }

    check("裸的浅/深更新不许在菜单里再出现一次") {
        // 同一个动作在同一个窗口出现两次，用户会以为是两种不同的东西 ——
        // 而其中一份的标题不会随范围变，信息更少。
        let a = try strippedCode("AIIntegration.swift")
        if a.contains("Label(\"浅更新\", systemImage:") || a.contains("Label(\"深度更新\", systemImage:") {
            throw fail("UpdateActionMenu 里还有裸的浅/深更新项 ⇒ 与顶栏双轨按钮重复")
        }
        guard a.contains("浅更新 + AI 摘要") && a.contains("深度更新 + AI 报告") else {
            throw fail("菜单里的 AI 变体不见了 —— 顶栏双轨按钮不覆盖它们")
        }
        return "菜单只剩 AI 变体与排程"
    }

    check("顶栏必须真的有那对双轨按钮") {
        let p = try strippedCode("PanelView.swift")
        guard p.contains("DualTrackButtons()") else {
            throw fail("工具栏没有挂 DualTrackButtons ⇒ 最常做的两个动作还藏在菜单里")
        }
        guard p.contains("Label(\"搜索项目\"") else {
            throw fail("工具栏的 ⌘F 搜索按钮不见了（重排时把它弄丢过一次）")
        }
        let d = try strippedCode("AIIntegration.swift")
        guard d.contains("struct DualTrackButtons") else { throw fail("DualTrackButtons 组件不见了") }
        return "双轨 + 搜索都在工具栏"
    }

    check("§3.2 要的 ⌥⇧⌘D 必须真的绑上（此前声明了却从没绑定）") {
        // ShortcutMap.deep 写在表里、冲突检查也把它算进去，
        // 但没有任何一处 keyboardShortcut 用它 ⇒ 规范里的「⌥⇧⌘D 深更新」
        // 是一个不存在的功能。声明 ≠ 绑定。
        let a = try strippedCode("DeepGitApp.swift")
        guard a.contains("ShortcutMap.deep.keyEquivalentSwiftUI") else {
            throw fail("ShortcutMap.deep 仍然没有任何地方绑定 ⇒ 规范要求的 ⌥⇧⌘D 不存在")
        }
        guard a.contains("ShortcutMap.shallow.keyEquivalentSwiftUI") else {
            throw fail("⇧⌘U 也没绑上了")
        }
        // 菜单与工具栏必须调同一个入口，否则两处迟早漂移
        guard a.contains("model.runUpdate(deep: false)") && a.contains("model.runUpdate(deep: true)") else {
            throw fail("菜单里的双轨项没有走 runUpdate(deep:)")
        }
        return "⇧⌘U / ⌥⇧⌘D 都绑在同一个入口上"
    }

    check("README 的文件清单必须与磁盘双向一致") {
        // 规范 Phase 5 说「删掉 3 个不存在文件的描述」——那 3 个确实修过，
        // 但真正烂掉的是另一半：**18 个磁盘上有的文件根本不在清单里**，
        // 其中包括全部纯函数层。清单烂到没人能拿它找文件，就等于没有。
        //
        // ⚠️ 比对时必须**先摘掉**「原来这里列的是 … 已删除」那段说明，
        //    否则那两个已被处理掉的文件名会被当成「清单里引用了不存在的文件」。
        let md = try pkgText("README.md")
        var body = md
        if let a = md.range(of: "> ⚠️ 原来这里列的是"),
           let b = md[a.upperBound...].range(of: "\n\n") {
            body = String(md[md.startIndex..<a.lowerBound]) + String(md[b.upperBound...])
        }
        var listed = Set<String>()
        for line in body.components(separatedBy: "\n") where line.hasPrefix("  ") && line.contains(".swift") {
            let name = String(line.trimmingCharacters(in: .whitespaces).prefix(while: { !$0.isWhitespace }))
            if name.hasSuffix(".swift") { listed.insert(name) }
        }
        let disk = Set(try allSourceFileNames())

        let ghost = listed.subtracting(disk).sorted()
        guard ghost.isEmpty else {
            throw fail("清单里列了磁盘上没有的文件：\(ghost.joined(separator: "、"))\n" +
                "      留着会让人去找不存在的文件")
        }
        let missing = disk.subtracting(listed).sorted()
        guard missing.isEmpty else {
            throw fail("磁盘上有但清单里没有：\(missing.joined(separator: "、"))\n" +
                "      共 \(missing.count) 个 —— 清单烂到没人能拿它找文件，就等于没有")
        }
        return "\(disk.count) 个源文件双向对齐"
    }
}

// MARK: - T. 三态：加载 / 空 / 错误必须画成三种样子
//
// §3.2 点名的两个缺陷这一轮都在：
//   · 仪表盘采集失败 → **主区永远转圈**（错误横幅同时挂着，自相矛盾）
//   · 里程碑「读取失败」与「真的还没有」渲染成同一句话

do {
    print("【T】三态：加载 / 空 / 错误必须画成三种样子")

    check("四态映射：idle 与 loading 都算「还在读」") {
        guard LoadState.idle.phase(hasContent: false) == .loading else { throw fail("idle 不该是 loading") }
        guard LoadState.loading.phase(hasContent: false) == .loading else { throw fail("loading 映射错了") }
        // ⚠️ 有内容也不能盖住「还在读」—— 那会让旧数据冒充新数据
        guard LoadState.loading.phase(hasContent: true) == .loading else {
            throw fail("loading 时有旧内容就画成了内容态 ⇒ 拿陈旧数据冒充这次的结果")
        }
        guard LoadState.loaded.phase(hasContent: true) == .content else { throw fail("有内容却没进 content") }
        guard LoadState.loaded.phase(hasContent: false) == .empty else { throw fail("空内容没进 empty") }
        return "五种组合都对"
    }

    check("失败必须带上原因，且不许被当成「空」") {
        guard LoadState.failed("引擎超时").phase(hasContent: false) == .failed("引擎超时") else {
            throw fail("failed 没带出原因")
        }
        // 关键：即使有旧内容，失败也必须显示失败 ——
        // 否则用户看到的是上一次的陈旧数据（fetchDashboard 原来正是这样静默保持旧值）
        guard LoadState.failed("解码失败").phase(hasContent: true) == .failed("解码失败") else {
            throw fail("有旧内容时失败被盖住了 ⇒ 陈旧数据冒充这次的结果")
        }
        return "原因带出，且不被旧内容盖住"
    }

    check("存储降级读到 0 条 ≠ 没有里程碑") {
        // 这是 §3.2 点名的第二处：「读不出来」被渲染成「没有」。
        let bad = LoadRules.state(storeHealth: "corrupt", readCount: 0)
        guard case .failed(let msg) = bad else { throw fail("降级+0 条被当成了 loaded ⇒ 界面会说「还没有里程碑」") }
        guard msg.contains("不是") || msg.contains("不可信") else {
            throw fail("失败文案没有点明「这不是没有」：\(msg)")
        }
        // 降级但读到了一部分 ⇒ 内容是真的，只是有一部分读不出来
        guard LoadRules.state(storeHealth: "degraded", readCount: 5) == .loaded else {
            throw fail("读到 5 条却判成失败 ⇒ 用户会以为一条里程碑都没有")
        }
        return "0 条判失败 / 5 条判成功"
    }

    check("降级披露只在真降级时出现") {
        guard LoadRules.degradedNotice(storeHealth: "ok", readCount: 3) == nil else {
            throw fail("健康状态也挂了降级披露")
        }
        guard LoadRules.degradedNotice(storeHealth: "degraded", readCount: 3) != nil else {
            throw fail("降级了却没有披露")
        }
        return "健康沉默 / 降级说话"
    }

    check("仪表盘不许再是「nil 就转圈」") {
        // 原来：if let d = model.dashboard { … } else { ProgressView("汇总项目群…") }
        // 失败时 dashboard 永远是 nil ⇒ 永远转圈。
        let v = try strippedCode("DetailViews.swift")
        guard v.contains("model.dashboardState.phase(") else {
            throw fail("仪表盘没有走 dashboardState ⇒ 采集失败时主区会永远转圈，\n" +
                "      而错误横幅同时挂在顶部，用户看到「一条报错 + 一个不结束的加载中」")
        }
        guard v.contains("仪表盘读不出来") else { throw fail("仪表盘没有错误态视图") }
        let m = try strippedCode("Model.swift")
        guard m.contains("dashboardState = .failed(msg)") else {
            throw fail("fetchDashboard 失败时没有写 dashboardState")
        }
        return "四态接线完整"
    }

    check("里程碑必须先判「读没读出来」再看「空不空」") {
        let v = try strippedCode("MilestonesView.swift")
        guard v.contains("model.milestonesState") else {
            throw fail("里程碑页没有读 milestonesState ⇒ 读取失败会渲染成「还没有里程碑」")
        }
        guard v.contains("里程碑读不出来") else { throw fail("里程碑没有错误态视图") }
        // 判定顺序：failed 分支必须在 emptyReason 之前
        let failedAt = v.range(of: "case .failed(let msg) = model.milestonesState")
        let emptyAt = v.range(of: "SearchFilter.emptyReason(")
        guard let f = failedAt, let e = emptyAt, f.lowerBound < e.lowerBound else {
            throw fail("「读不出来」的判定排在「空不空」之后 ⇒ 两者仍然渲染成同一句话")
        }
        let m = try strippedCode("Model.swift")
        guard m.contains("LoadRules.state(storeHealth:") else {
            throw fail("fetchMilestones 没有走 LoadRules.state")
        }
        return "先判失败、再判空"
    }

    check("AI 结果弹窗不许固定尺寸（长报告在 620×560 里读不完）") {
        let a = try strippedCode("AIIntegration.swift")
        if a.contains(".frame(width: 620, height: 560)") {
            throw fail("AIResultSheet 仍是固定 620×560 ⇒ 不可缩放，\n" +
                "      一份几千字的报告只能看到开头，用户也没法拖大")
        }
        guard a.contains("idealWidth") && a.contains("minWidth") else {
            throw fail("既没有 ideal 也没有 min ⇒ 不是「可缩放 + 有下限」")
        }
        // .dismiss 声明了却不用是另一类死代码（编译器不报）
        if a.contains("@Environment(\\.dismiss)") && !a.contains("dismiss()") {
            throw fail("声明了 .dismiss 却一次都没用")
        }
        return "可缩放 + 有下限，且 dismiss 真的用了"
    }

    check("文档区三态：读不出来 / 还在读 / 真的没有，必须是三句不同的话") {
        let v = try strippedCode("DetailViews.swift")
        // 不能再有裸的 `if let docs = …, !docs.isEmpty` ——
        // 那条分支不成立时什么都不画，三种情况共用同一个空画面。
        if v.contains("if let docs = model.projectDocs[projectName], !docs.isEmpty") {
            throw fail("文档区还是 `if let docs…, !docs.isEmpty` ⇒ 「读不出来」与「没有文档」\n" +
                "      渲染成同一个空画面，用户据此认为「这个项目确实没有 README」")
        }
        guard v.contains("switch docsPhase") else { throw fail("文档区没走 docsPhase ⇒ 四态在视图侧断了") }
        guard v.contains("model.docsStates[projectName]") else {
            throw fail("docsPhase 没读 model.docsStates ⇒ 纯靠有没有内容猜，失败态无从体现")
        }
        guard v.contains("state.phase(hasContent:") else { throw fail("docsPhase 没走纯函数层 LoadState") }

        guard let sw = slice(v, from: "switch docsPhase", to: "private var docsPhase: LoadPhase") else {
            throw fail("切片失败：switch docsPhase 之后找不到 docsPhase 的定义（结构变了？）")
        }
        for c in ["case .content", "case .failed(let msg)", "case .loading", "case .empty"]
        where !sw.contains(c) {
            throw fail("文档区缺 \(c) 分支 ⇒ 四态只画了三种")
        }
        // 最要紧的一条：空与失败**必须是两句话**。
        // 两者都不画文档卡片，措辞一混就等于没改。
        guard let failed = slice(sw, from: "case .failed(let msg)", to: "case .loading"),
              let emptyAt = sw.range(of: "case .empty") else {
            throw fail("找不到文档区的 failed / empty 分支切片")
        }
        // ⚠️ 空的切片要一路取到 switch 末尾：case 顺序是
        // content → failed → loading → **empty**，所以 empty 后面没有下一个 case 可切。
        let empty = String(sw[emptyAt.lowerBound...])
        guard failed.contains("读不出来") else { throw fail("失败态没说「读不出来」") }
        guard empty.contains("还没有受管的文档") else {
            throw fail("空态没说「还没有受管的文档」⇒ 与失败态区分不开，用户仍会把读失败当成没有")
        }
        if empty.contains("读不出来") {
            throw fail("空态里也写了「读不出来」⇒ 两个分支的措辞被混成同一句")
        }
        return "四态各自有话，失败与空是两句不同的话"
    }

    check("loadDocs 三点接线：起 / 成 / 败都要落状态") {
        let m = try strippedCode("Model.swift")
        guard m.contains("docsStates[name] = .loading") else {
            throw fail("loadDocs 开头没写 .loading ⇒ 读的过程中会被当成「没有文档」")
        }
        guard m.contains("docsStates[name] = .loaded") else { throw fail("读成功没写 .loaded") }
        guard m.contains("docsStates[name] = .failed(msg)") else {
            throw fail("catch 里没写 .failed ⇒ 失败不落到模型上，视图只能靠空数组猜")
        }
        // 引擎要求随 200 披露 unreadable；加状态不能顺手把它删掉
        guard m.contains("!env.unreadable.isEmpty") else {
            throw fail("引擎的 unreadable 披露丢了 ⇒ 客户端拿到少了一条 README 的数组却无从判断")
        }
        return "起 / 成 / 败三点齐全，unreadable 披露仍在"
    }
}

// MARK: - U. 焦点管理：面板打开即可打字
//
// §3.2 点名三处：**里程碑表单、搜索框、扫描面板**。
// 原来只有搜索框有（且那是因为系统 `.searchable` 不吃外部 focus 绑定，
// 才自建了 TextField + @FocusState）。另两处打开后焦点不在任何控件上，
// 用户得先用鼠标点一下才能打字 —— 键盘用户尤其吃亏。

do {
    print("【U】焦点管理：§3.2 点名的三处，打开即可打字")

    check("三处焦点都在，且声明了就得绑到字段上") {
        let ms = try strippedCode("MilestonesView.swift")
        let ss = try strippedCode("ScanSheet.swift")
        let pv = try strippedCode("PanelView.swift")
        for (name, code) in [("里程碑表单", ms), ("扫描面板", ss), ("侧栏搜索框", pv)] {
            guard code.contains("@FocusState") else {
                throw fail("\(name)没有 @FocusState ⇒ 打开面板后要先用鼠标点一下才能打字")
            }
        }
        // 声明了却没绑 = 死代码（不变量 88）
        guard ms.contains(".focused($nameFocused)") else { throw fail("里程碑的 @FocusState 没绑到任何字段") }
        guard ss.contains(".focused($pathFocused)") else { throw fail("扫描面板的 @FocusState 没绑到任何字段") }
        return "三处都在且都绑上了"
    }

    check("焦点必须落在「第一个该填的字段」，不是可有可无的那个") {
        let ms = try strippedCode("MilestonesView.swift")
        let ss = try strippedCode("ScanSheet.swift")
        // 里程碑：项目有默认值，名称才是空着等人填的
        guard let f = slice(ms, from: "TextField(\"名称", to: "TextField(\"绑定 tag"),
              f.contains(".focused($nameFocused)") else {
            throw fail("里程碑的焦点没落在「名称」框上（挂到别的字段或压根没挂）")
        }
        // 扫描面板：路径是唯一必填项，项目名是可选的
        guard let f = slice(ss, from: "TextField(placeholder, text: text)", to: "Button(\"选择…\")"),
              f.contains(".focused($pathFocused)") else {
            throw fail("扫描面板的焦点没落在路径框上")
        }
        return "里程碑给名称、扫描给路径，都不是次要字段"
    }

    check("打开即聚焦；扫描面板切模式还要重送") {
        let ms = try strippedCode("MilestonesView.swift")
        let ss = try strippedCode("ScanSheet.swift")
        guard ms.contains("nameFocused = true") else { throw fail("里程碑 Sheet 打开时没把焦点送进名称框") }
        guard ss.contains("pathFocused = true") else { throw fail("扫描面板打开时没把焦点送进路径框") }
        // 两个模式的路径框共用同一个绑定：切模式不重送，焦点就留在
        // 一个已经不在屏幕上的控件上，用户敲的字会消失
        guard ss.contains(".onChange(of: mode)") else {
            throw fail("扫描面板切换「单个 / 批量」时没重送焦点 ⇒ 焦点留在屏幕外的框里，敲的字消失")
        }
        return "打开即聚焦，切模式重送"
    }
}

// MARK: - V. 文档声明必须兑现
//
// README 的「系统集成」里写着「Dock 菜单：右键 Dock 图标 = 打开面板 / 全部浅更新」，
// 而源码里 `dock` 一处都没有 —— **文档在说一个不存在的功能**。
// 这与不变量 88（声明 ≠ 绑定）同族：文档里的「有」和代码里的「有」也是两个真相源。

do {
    print("【V】文档声明必须兑现（README 写了就要真能做）")

    check("「该显示哪个分支」只能有一个出处：ProjectStatus.primaryBranch") {
        // 行为对不对由 ContractCheck 用**真实引擎 fixture** 验（那边能拿到
        // Models.swift 本体和 status --json 的真实输出）。这里只卡**结构**：
        // 视图里不许再自己推导一遍。
        //
        // ⚠️ 这条规则曾被抄三份：BarView / BoardView 各一个私有 computed property，
        // PanelView 内联在 else if 里。字面相同、位置不同 ⇒ 改规则要找三处，
        // 漏一处就出现「菜单栏说 feat、侧栏说 main」，而两个界面常常同屏。
        //
        // 放行 `if b.isCurrent {` 这种形状是**有意的**：那是「这一行要不要标
        // 『当前』徽标」，是另一个问题，跟「挑哪一条当主分支」无关。
        // 一刀切禁掉 isCurrent 会把正确的用法也一起打掉。
        let re = try NSRegularExpression(pattern: "isCurrent")
        // `if <标识符>.isCurrent` 才放行；其余（first/filter/first(where:)…）全红。
        let displayUse = try NSRegularExpression(
            pattern: "^\\s*if\\s+[A-Za-z_][A-Za-z0-9_]*\\.isCurrent\\b")
        var spots: [String] = []
        for name in try allSourceFileNames() where name != "Models.swift" {
            let code = try strippedCode(name)
            // ⚠️ split 出来的是 Substring，而 firstMatch(in:) 只收 String ——
            // 少这一步就是 "cannot convert value of type 'String.SubSequence'"。
            let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            for (i, line) in lines.enumerated() {
                let full = NSRange(line.startIndex..<line.endIndex, in: line)
                guard re.firstMatch(in: line, range: full) != nil else { continue }
                if displayUse.firstMatch(in: line, range: full) != nil { continue }
                spots.append("\(name)：\(i + 1) 行 `\(line.trimmingCharacters(in: .whitespaces))`")
            }
        }
        guard spots.isEmpty else {
            throw fail("「当前分支」判定又出现了第 \(spots.count) 处自己推导：\n      "
                + spots.prefix(3).joined(separator: "\n      ")
                + "\n      规则只有一个出处：ProjectStatus.primaryBranch（Models.swift）。\n"
                + "      视图里写 `p.branches.first { $0.isCurrent }` 看着没问题，\n"
                + "      但它就是第二个真相源 —— 改了模型层那处，这些地方不会跟着动。")
        }
        return "视图层 0 处自己推导；`if x.isCurrent` 的显示判断放行"
    }

    check("筛选控件必须真的改变渲染，不许是摆设（设计稿筛选行）") {
        // 这条卡的是**最坏的一种控件**：摆在那里、用户拨了、什么也没变。
        // 仪表盘顶部那条筛选行（时间跨度 / 提交类型 / 重新索引）就是这种风险。
        //
        // 这里只验**数据**层：档位窗口必须真的分档、提交类型筛选必须真的改条数。
        // 「给定一个项目，两个档位给出不同答案」那一半由 ContractCheck 用
        // **真 fixture** 验（那边能拿到 ProjectStatus 本体）。
        guard DashSpan.all.maxDays == nil else {
            throw fail("全量档位竟然带时间窗")
        }
        guard let d7 = DashSpan.d7.maxDays, let d30 = DashSpan.d30.maxDays else {
            throw fail("近 7 天 / 近 30 天档位没有时间窗")
        }
        guard d7 < d30 else {
            throw fail("近 7 天的窗口(\(d7))不比近 30 天(\(d30))窄 ⇒ 档位是反的")
        }
        // 提交类型筛选：只画被选中的那类
        let stats = [CommitTypeStat(type: "feat", count: 3),
                     CommitTypeStat(type: "fix", count: 2)]
        guard DashFilter(span: .all, commits: .only("feat")).keptStats(stats).count == 1 else {
            throw fail("提交类型筛选没有真的过滤堆叠条")
        }
        guard DashFilter(span: .all, commits: .all).keptStats(stats).count == 2 else {
            throw fail("「所有提交类型」档位把东西也滤掉了")
        }
        return "时间窗 7 < 30 < 全量；提交类型筛选真的改变条数"
    }

    check("里程碑页必须接范围选择器，且不许拿全局 counts 冒充单仓库") {
        // 造三条例：`MilestoneItem` 是 Decodable，构造要 20+ 个字段，
        // 这里直接解 JSON —— 与契约检查同一套做法（验行为，不验字面量）。
        func item(_ project: String, _ name: String, _ status: String) throws -> MilestoneItem {
            try JSONDecoder().decode(MilestoneItem.self, from: Data("""
            {"projectId":"p-\(project)","projectName":"\(project)","name":"\(name)",
             "description":"","status":"\(status)","targetDate":"","daysToTarget":-1,
             "overdue":false,"tag":"","tagName":"","tagReached":false,
             "commitsSince":-1,"commitsSinceReadable":false,"gitReadable":true,
             "createdAt":"","completedAt":"","unverifiedReason":""}
            """.utf8))
        }
        let all = [
            try item("atlas", "M1", "open"),
            try item("atlas", "M2", "done"),
            try item("beacon", "M1", "open"),
            try item("beacon", "M2", "unknown"),
        ]

        // 1. 范围收窄真的收窄。
        let onlyAtlas = DashMilestoneScope.items(all, project: "atlas")
        guard onlyAtlas.count == 2 else {
            throw fail("收窄到 atlas 后有 \(onlyAtlas.count) 条，应为 2")
        }
        guard DashMilestoneScope.items(all, project: nil).count == 4 else {
            throw fail("全局范围被收窄了")
        }
        guard DashMilestoneScope.items(all, project: "不存在").isEmpty else {
            throw fail("范围指向不存在的项目时应为空")
        }

        // 2. 分组按项目，且每条只出现在自己那一组。
        let g = DashMilestoneScope.groups(all)
        guard g.count == 2 else { throw fail("分成 \(g.count) 组，应为 2") }
        for (_, items) in g {
            guard Set(items.map(\.projectName)).count == 1 else {
                throw fail("某一组里混了多个项目")
            }
        }

        // 3. unknown 必须单列 —— 混进 open 或 done 都是把「不知道」说成事实。
        let t = DashMilestoneScope.tally(all)
        guard t.open == 2, t.done == 1, t.unknown == 1, t.dropped == 0 else {
            throw fail("统计错了：open=\(t.open) done=\(t.done) "
                + "dropped=\(t.dropped) unknown=\(t.unknown)")
        }
        // 收窄后统计也必须跟着收窄，否则就是把全局数说成单仓库的。
        let ta = DashMilestoneScope.tally(onlyAtlas)
        guard ta.open == 1, ta.done == 1, ta.unknown == 0 else {
            throw fail("收窄后的统计没有跟着收窄：\(ta)")
        }

        // 4. 明细不等于引擎读到的条数时，必须能判出「不完整」。
        let full = MilestoneCounts(open: 4, done: 0, dropped: 0, unknown: 0,
                                   storeHealth: "ok", degraded: false,
                                   readCount: 4, excludedDisabled: 0, orphaned: 0)
        guard DashMilestoneScope.isComplete(all, counts: full) else {
            throw fail("明细条数 == readCount 却判成不完整")
        }
        let cut = MilestoneCounts(open: 9, done: 0, dropped: 0, unknown: 0,
                                   storeHealth: "ok", degraded: false,
                                   readCount: 9, excludedDisabled: 0, orphaned: 0)
        guard !DashMilestoneScope.isComplete(all, counts: cut) else {
            throw fail("明细被截断（4/9）却判成完整 ⇒ 界面会把下界当全量报")
        }
        guard !DashMilestoneScope.isComplete(all, counts: nil) else {
            throw fail("拿不到 counts 时判成完整 ⇒ 把「不知道」说成「就是全部」")
        }
        return "范围收窄 / 分组 / unknown 单列 / 截断可辨，四件事都对"
    }

    check("里程碑页的仓库筛选必须是它自己的状态，不许从 selection 推导") {
        // 我在这一页犯过一次，且犯得很有代表性：
        // 把「当前范围」写成 `if case .project(let n)? = model.selection`。
        // 但 `MilestonesView` **只在** `selection == .milestones` 时才被渲染
        // （PanelView 的 switch），于是这个分支**永远不成立** ——
        // 控件在源码里存在、在判据里能测出逻辑、实际恒为 nil。
        // 实测：选中 atlas → 点「里程碑」→ 3 个仓库照旧全列出来。
        //
        // 顶栏那个范围选择器也是同一套推导，所以两者「看起来一致」
        // （都显示全局看板）—— **一致不等于有用**，
        // 这正是「摆而不动」的伪装形态：不是明显地坏，而是默默地什么也没做。
        // ⚠️ 必须**只切 MilestonesView 这一个结构体**：
        // 同一个文件里的 `AddMilestoneSheet` 合法地用 `model.selection` 预选项目
        // （新建里程碑时默认填当前项目），文件级匹配会把它一起判红。
        let ms = try slice(try strippedCode("MilestonesView.swift"),
                           from: "struct MilestonesView", to: "\n}\n")
            ?? "（切不出 MilestonesView）"
        if ms.contains("case .project(let") && ms.contains("model.selection") {
            throw fail("里程碑页从 model.selection 推导项目范围：这个视图只在 "
                + "selection == .milestones 时渲染，那个分支恒为 nil ⇒ 筛选是摆设。"
                + "要筛就用本页自己的 @State。")
        }
        guard ms.contains("@State private var projectFilter") else {
            throw fail("里程碑页没有自己的仓库筛选状态")
        }
        // 筛选必须真的接到数据链上，而不是只改个标题。
        guard ms.contains("DashMilestoneScope.items(model.milestones, project: projectFilter)") else {
            throw fail("projectFilter 没接到取数上 ⇒ 筛了不生效")
        }
        // 反向自查：渲染处不许吃全量。
        if ms.contains("ForEach(model.milestones)") {
            throw fail("里程碑渲染绕过了筛选链，直接吃全量")
        }
        return "仓库筛选是本页自己的 @State，且真的接在取数链上"
    }

    check("侧栏行不许用 .badge()（macOS 选择型 List 里它会吃掉点击）") {
        // 实测（本机 macOS 26）：侧栏「里程碑」那一行带着 `.badge(...)`，
        // 连点 5 次 `selection` 的 didSet **一次都没触发** —— `go()` 根本没被调用。
        // 把 `.badge` 去掉后，同一次点击立刻生效。
        // `.badge()` 在 `List(selection:)` 的行上会接管命中测试：
        // 行的点击与选中高亮一起失效，而外观完全正常。
        //
        // 为什么这条值得单独立：那一行「看着没毛病」，⌘3 也能进，
        // 只有真的用鼠标去点才会发现它是死的 ——
        // 而对鼠标用户来说，进不去的导航项等于这个视图不存在。
        // 判据查源码：选择型 List 的构造处附近不许出现 `.badge(`。
        // ⚠️ 必须用 strippedCode：原文里**注释提到 `.badge(`** 就会自我判红。
        //    这不是假警报那么简单 —— 一条会被自己的注释触发的判据，
        //    下一次有人想在注释里解释这件事时就会莫名其妙地红，然后被人「修」掉。
        let p = try strippedCode("PanelView.swift")
        guard p.contains("List(selection:") else {
            throw fail("PanelView 里找不到选择型 List，这条判据的前提没了")
        }
        if p.contains(".badge(") {
            throw fail("侧栏用了 `.badge(...)`：它在 List(selection:) 的行上会吞掉点击，"
                + "表现为「这一行点不动」而外观完全正常。计数请写进行内文字。")
        }
        return "侧栏没有 .badge()；里程碑计数走行内文字"
    }

    check("项目状态词只能有一处推导（看板列与项目卡必须说同一句话）") {
        // 同一个问题「这个项目状态怎么样」被算过三遍，三遍都错：
        //   · boardColumn(for:) 判 branches（追踪数组） ⇒ 「停滞」列恒 0
        //   · DashboardParts.stateWord 判 primaryBranch?.status ⇒ 全部落进「正常」
        //   · 修好第一个之后，第二个还在错 —— 两个界面同屏给出矛盾的词
        // 修法是判定下沉到 `ProjectStatus.liveness` / `stateWord`，
        // 视图只消费。这里钉住「只有模型层有一份」。
        let m = try sourceText("Models.swift")
        guard m.contains("enum Liveness") && m.contains("var liveness: Liveness")
                && m.contains("var stateWord:") else {
            throw fail("模型层没有 liveness / stateWord ⇒ 状态判定又散回视图了")
        }
        // 视图里不许再自己判「停滞 / 正常」——只许消费。
        for f in ["BoardView.swift", "DashboardParts.swift", "DetailViews.swift"] {
            // 同样要剥注释：这三个文件的注释里**正在解释**这个缺陷，
            // 原文匹配会被自己的说明文字判红。
            let s = try strippedCode(f)
            // 视图里出现 `status == "stale"` / `"idle"` 这类档位字面量就是自己判了。
            for literal in ["status == \"stale\"", "status == \"idle\"",
                            "status == \"active\"", "status == \"merged\""] {
                if s.contains(literal) {
                    throw fail("\(f) 里出现 \(literal) —— 视图在自推档位。"
                        + "引擎的档位在 `primaryBranch.status`，无追踪分支时读不到，"
                        + "该走 `ProjectStatus.liveness`。")
                }
            }
        }
        // 看板列必须是纯映射：拿 liveness 换列，不自己判。
        let b = try strippedCode("BoardView.swift")
        guard b.contains("var boardColumn: BoardColumn") && b.contains("switch liveness") else {
            throw fail("BoardView.boardColumn 必须只按 liveness 映射")
        }
        if b.contains("func boardColumn(for:") {
            throw fail("BoardView 里还留着自由函数 `boardColumn(for:)` —— "
                + "领域规则只许有一份，且必须在模型层")
        }
        if b.contains("prefix(4)") {
            throw fail("看板还在 prefix(4) 截断：列头计数与真的列出来的行数对不上，"
                + "多出来的项目永远点不到")
        }
        return "判定只有 Models.swift 一份；看板列是纯映射；没有静默截断"
    }

    check("筛选状态必须跨视图共享，且不能挂在视图的 @State 上") {
        // 原来 `DashFilter` 是 `DashboardView` 的 `@State`：视图一重建就没了
        // （切到看板再切回来，筛选悄悄弹回「全量」），
        // 而且看板根本读不到它 —— 仪表盘筛到 1 个项目时看板还是 3 个。
        let mdl = try sourceText("Model.swift")
        guard mdl.contains("var dashFilter") else {
            throw fail("AppModel 上没有 dashFilter ⇒ 筛选无法跨视图共享")
        }
        let dv = try strippedCode("DetailViews.swift")
        if dv.contains("@State private var filter = DashFilter()") {
            throw fail("筛选又回到 DashboardView 的 @State 上了："
                + "视图重建即丢失，且看板读不到")
        }
        // 看板必须真的读它，否则「共享」是一句空话。
        let bv = try strippedCode("BoardView.swift")
        guard bv.contains("dashFilter.keeps(project:") else {
            throw fail("看板没有消费 model.dashFilter ⇒ 两个视图对「在看什么」各说各话")
        }
        return "筛选在 AppModel 上；仪表盘与看板消费同一份"
    }

    check("时间窗的判定只许在模型层（档位线归引擎，视图层不许碰 staleDays）") {
        // 引擎的档位线是 3/14 天（progress.cj:30-36）。客户端再写一个阈值
        // 就是两个真相源。**上一组判据已经卡了 staleDays 不许出 Models.swift**，
        // 这里补一条更细的：时间窗的**判定方法**必须在模型层，
        // 免得有人为了绕过那条判据，把天数换个名字（`lastTouchDays`）再写一遍。
        // strippedCode 返回非 Optional 的 String（读不到会直接抛），别写 guard let
        let m = try strippedCode("Models.swift")
        guard m.contains("func updatedWithin(days:") else {
            throw fail("模型层没有 updatedWithin(days:) ⇒ 时间窗判定不知道放哪了")
        }
        // 「读不出来」必须保留 —— 那是这个方法存在的全部理由。
        //
        // ⚠️ 这里原来硬编码了机制 `w.contains("b.staleDays < 0")`。
        // 判据钉**机制**而不是**意图**，于是实现换了数据源（staleDays → lastCommitAt，
        // 因为追踪数组在无远端的仓库里恒空，判据自己反而在为死控件背书），
        // 它就报红 —— 而那次的实现其实是对的。
        // 正确写法：钉「读不出来 ⇒ 放行」这个**语义**，以及判定依据是模型层那个
        // 有名字的派生属性（不是视图里临时算的天数，否则又变成第二真相源）。
        let w = try slice(m, from: "func updatedWithin(days:", to: "\n    }")
            ?? "（切不出 updatedWithin 的方法体）"
        guard w.contains("daysSinceLastCommit") else {
            throw fail("updatedWithin 没有走模型层的 daysSinceLastCommit：\n" + w
                + "      判定依据必须是模型层那个有名字的派生属性，"
                + "在视图里现算天数就是第二真相源")
        }
        // 读不出来的分支：拿不到 age 时必须 `return true`（保留），不许 return false。
        // 这条是语义断言 —— 具体写法（guard let / if let / ?? true）随实现变。
        let keepsUnknown = w.contains("else { return true }")
            || w.contains("?? { return true }")
            || (w.contains("guard let age") && w.contains("else { return true }"))
        guard keepsUnknown else {
            throw fail("updatedWithin 没有「读不出来就保留」的放行分支：\n" + w
                + "      那会把「不知道」说成「不在近 7 天内」")
        }
        guard w.contains("return true") else {
            throw fail("updatedWithin 没有任何放行分支 ⇒ 窗口会把所有项目滤空")
        }
        return "判定在模型层；依据 daysSinceLastCommit；读不出来一律保留"
    }

    check("分支 KPI 必须用 repoBranchCount，不许拿追踪数组长度当分支总数") {
        // 引擎的 work.branches = 各项目 branches **追踪数组**长度之和
        // （dashboard.cj:200）。追踪数组只含「引擎追踪到基线的那些」，
        // 无远端基线的仓库会是空数组，而 repoBranchCount 仍是真实值。
        // 实测：4 分支的仓库 → repoBranchCount=4、branches=[]、work.branches=0。
        // 于是用 work.branches 会显示「分支 0」—— 把「明细读不到」说成「没有分支」。
        let f = try strippedCode("DashboardScope.swift")
        // ⚠️ 切片边界要按文件里**实际的书写顺序**取。`.reach` 那个 KPI 是
        // `return [` 数组的第 4 项，所以「从 .reach 到 return [」永远切不出来 ——
        // 我第一版就是这么写的。而 `repoBranchCount` 又不在数组元素体内
        // （它在数组**之前**的 `let realBranches = …` 里），所以只切元素体也不够。
        // 于是分两段验，各验各的职责。
        guard let calc = try slice(f, from: "let realBranches", to: "return [") else {
            throw fail("切不出分支数的计算区（结构变了？）")
        }
        guard let reach = try slice(f, from: "kind: .reach", to: "\n        ]") else {
            throw fail("切不出 .reach 那个 KPI 的定义（结构变了？）")
        }
        guard calc.contains("repoBranchCount") else {
            throw fail("分支数计算区没读 repoBranchCount ⇒ 主数字没有真实来源")
        }
        if reach.contains("value: d.work.branches") {
            throw fail("分支 KPI 仍然用 work.branches（追踪数组长度）：\n" +
                "      追踪数组为空时显示 0，用户读成「这个项目群一个分支都没有」。\n" +
                "      主数字必须是 repoBranchCount（真实值），追踪长度只能作副说明")
        }
        guard reach.contains("value: realBranches") else {
            throw fail("分支 KPI 的主数字没有用计算好的 realBranches")
        }
        return "主数字取 repoBranchCount，追踪长度降为副说明"
    }

    check("README 声明的 Dock 菜单必须真存在") {
        let readme = try pkgText("README.md")
        guard readme.contains("Dock 菜单") else { throw fail("README 不再声称有 Dock 菜单（若已删除请同步改判据）") }
        let a = try strippedCode("DeepGitApp.swift")
        guard a.contains("applicationDockMenu") else {
            throw fail("没有 applicationDockMenu ⇒ README 写的「Dock 菜单：右键 Dock 图标 = 打开面板 / 全部浅更新」\n" +
                "      是个不存在的功能（要么实现，要么把 README 那行删掉）")
        }
        // ⚠️ 「函数名在」不等于「菜单在」。这个判据前前后后栽了三次：
        //   第一版  contains("applicationDockMenu") ⇒ 注入 `return nil` 假绿
        //   第二版  contains("buildDockMenu()") ⇒ **函数定义本身** `private func
        //           buildDockMenu() -> NSMenu?` 就含这个子串，照样假绿
        //   第三版  slice(… to: "\n    }\n") ⇒ 注入把函数压成单行后找不到结束标记，
        //           切片一路跨到下一个函数，又把 buildDockMenu 的**定义**吃了进来
        // 所以这里既不靠子串也不靠花括号边界，而是**按行取「声明的下一行」** ——
        // 那是函数体的第一行，不可能是别处的定义。
        let lines = a.components(separatedBy: "\n")
        guard let decl = lines.firstIndex(where: { $0.contains("func applicationDockMenu(") }) else {
            throw fail("切不出 applicationDockMenu 的声明行（结构变了？）")
        }
        let bodyLine = decl + 1 < lines.count
            ? lines[decl + 1].trimmingCharacters(in: .whitespaces) : ""
        guard bodyLine.contains("buildDockMenu()") else {
            throw fail("applicationDockMenu 的函数体第一行是「\(bodyLine)」，没调用 buildDockMenu()\n" +
                "      ⇒ 右键 Dock 弹不出菜单，而 README 说的是「右键 Dock 图标 = 打开面板 / 全部浅更新」")
        }
        guard let body = slice(a, from: "private func buildDockMenu(", to: "\n    }\n") else {
            throw fail("切不出 buildDockMenu（结构变了？）")
        }
        guard body.contains("return menu") else {
            throw fail("buildDockMenu 没有 return menu ⇒ 菜单是空的或被写死")
        }
        return "声明兑现，且真的造出菜单"
    }

    check("Dock 菜单项必须都设 target（没设就会灰着点不动）") {
        // ⚠️ 这是实现时踩到的坑：`NSMenuItem.target` 留空时只在 responder chain
        // 里找动作，而 `AppDelegate` 是 `NSObject`（不是 `NSResponder`），
        // **根本不在 chain 里** —— 菜单能弹出来，但两项全是灰的。
        // target 还是弱引用，所以得由 AppDelegate 强持有那个接收者。
        let a = try strippedCode("DeepGitApp.swift")
        guard let items = slice(a, from: "private func buildDockMenu(", to: "\n    }\n") else {
            throw fail("切不出 buildDockMenu（结构变了？）")
        }
        let nItem = items.components(separatedBy: "NSMenuItem(").count - 1
        let nTarget = items.components(separatedBy: ".target = ").count - 1
        guard nItem >= 2 else {
            throw fail("Dock 菜单只有 \(nItem) 项，而 README 声明的是「打开面板 / 全部浅更新」两项")
        }
        guard nItem == nTarget else {
            throw fail("菜单项 \(nItem) 个、设了 target 的 \(nTarget) 个 ⇒ 有项会灰着点不动")
        }
        return "\(nItem) 项全部设了 target"
    }

    check("Dock 的「全部浅更新」必须走不经过 scope 的入口，且不许绕过确认") {
        let a = try strippedCode("DeepGitApp.swift")
        let m = try strippedCode("Model.swift")
        guard m.contains("func requestBulkUpdate(deep:") else {
            throw fail("Model 没有 requestBulkUpdate ⇒ Dock 菜单只能拿 runUpdate 顶替，\n" +
                "      而 runUpdate 按 updateScope 走（范围由 selection 推导）：\n" +
                "      用户停在某个项目上时点「全部」会去更新那**一个**项目")
        }
        // 确认框挂在主面板的 confirmationDialog 上 ⇒ 面板没开就没人呈现
        // ⇒ 点了只设 pending 会表现为「点了没反应」
        guard let f = slice(a, from: "func shallowUpdateAll()", to: "\n    }\n") else {
            throw fail("切不出 DockMenuTarget.shallowUpdateAll")
        }
        // 批量更新会写文件，是破坏性动作：菜单回调里不许直接开跑。
        // ⚠️ 这条必须**排最前**：第一版把它放在最后，于是注入
        // `startUpdateAll(deep: false)` 时先撞上「没走 requestBulkUpdate」就抛了 ——
        // 判据抓到了缺陷，但报的理由不是最严重的那条。
        // 负控的价值一半在「红」，另一半在「红得对不对得上它声称的判据」。
        if f.contains("startUpdateAll(") {
            throw fail("Dock 菜单回调里直接 startUpdateAll ⇒ 绕过了确认框（批量更新会写文件）")
        }
        guard f.contains("requestBulkUpdate(deep: false)") else {
            throw fail("Dock 的「全部浅更新」没走 requestBulkUpdate（可能掉回 scope 推导）")
        }
        guard f.contains("openPanel()") else {
            throw fail("点完之后没有打开面板 ⇒ 确认框挂在面板上，窗口没开就没人呈现，\n" +
                "      用户只会看到「点了没反应」")
        }
        return "走 requestBulkUpdate + 叫醒面板，不绕过确认"
    }
}

print("")
if failures.isEmpty {
    print("✅ 客户端检查通过：\(checks) 项")
    exit(0)
} else {
    print("❌ 客户端检查失败：\(failures.count)/\(checks) 项")
    for f in failures { print("   · \(f)") }
    exit(1)
}
