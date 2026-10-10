// ShortcutMap.swift — 快捷键的唯一声明处（纯函数层，零 SwiftUI 依赖）。
//
// 【为什么要有这个】规范 §3.2 列了一串快捷键：⌘R 刷新、⇧⌘U 浅更新、
// ⌥⇧⌘D 深更新、⌘1–⌘5 切视图、⌘F 搜索、⌘, 设置、⌘W 关面板。
// 逐个散着写 `.keyboardShortcut` 会有三个问题：
//   1. **冲突查不出来**。两个视图各写 ⌘1，只有真跑起来才知道。
//   2. **写法不统一**。`"d"`（字符）与 `.defaultAction`（系统语义）
//      混在一起，菜单里显示的键位也可能不一样。
//   3. **规范说的视图数与实际不符**（见下面 ⌘1–⌘3 那条注释），
//      而没人会在写第 5 个 ⌘5 时回头核对到底有几个视图。
//
// 这里是唯一来源：视图只问 `ShortcutMap.shortcut(for:)`。
import Foundation

/// 一个快捷键的声明。
struct Shortcut: Equatable {
    /// 系统语义键（如 ⌘. / ⌘, / ⌘W）。为 nil 时用 `key`。
    let systemKey: String?
    /// 字面键（如 "r" / "1"）。给了 `systemKey` 就不用给。
    let key: String
    let modifiers: [String]

    init(systemKey: String?, key: String = "", modifiers: [String]) {
        self.systemKey = systemKey
        self.key = key
        self.modifiers = modifiers
    }

    /// 给 SwiftUI 用的 `KeyEquivalent` 文本。系统语义键直接透传。
    var keyEquivalent: String { systemKey ?? key }

    /// 人类可读的展示形式，测试与文档共用。
    ///
    /// ⚠️ 字母键**转大写**：菜单里显示「⌘r」会被当成 `⌘R` 之外的东西，
    /// 而 macOS 自己的菜单显示的是大写。
    var display: String {
        var s = ""
        if modifiers.contains("cmd") { s += "⌘" }
        if modifiers.contains("shift") { s += "⇧" }
        if modifiers.contains("alt") { s += "⌥" }
        let k = keyEquivalent
        if k.isEmpty { return s.isEmpty ? "（无键位）" : s }
        if k == " " { return s + "Space" }
        // 只大写**字面键**。系统语义键（⌘. / ⌘, / ⌘W）保持原样 ——
        // 把 "w" 显示成 "⌘W" 看着一样，但拿它当判据会把「实际是 w」说成「实际是 W」。
        let shown: String
        if systemKey != nil {
            shown = k
        } else {
            shown = k.count == 1 && k.first!.isLetter ? k.uppercased() : k
        }
        return s + shown
    }
}

/// 视图切换目标。
enum ShortcutTarget: Equatable {
    case dashboard
    case board
    case milestones
    case graph
    case confidence
    case patchCheck
    /// 打开当前选中的项目（详情是动态的，没有固定第 4 个视图）
    case currentProject
}

/// 快捷键表。
enum ShortcutMap {
    // —— 动作 ——
    static let refresh  = Shortcut(systemKey: nil, key: "r", modifiers: ["cmd"])
    static let shallow  = Shortcut(systemKey: nil, key: "u", modifiers: ["cmd", "shift"])
    static let deep     = Shortcut(systemKey: nil, key: "d", modifiers: ["cmd", "shift", "alt"])
    static let stop     = Shortcut(systemKey: ".", modifiers: ["cmd"])
    /// 聚焦搜索。写成字面 "f" 而不是系统语义键：
    /// `⌘F` 在 macOS 上本来是「查找」，但侧栏搜索是**本应用自己的**筛选，
    /// 复用 ⌘F 会让人以为在找文档。键位一样，语义不同 ——
    /// 这里保留 ⌘F（规范要求）但在标题上写清是「搜索项目」。
    static let find     = Shortcut(systemKey: nil, key: "f", modifiers: ["cmd"])
    static let settings = Shortcut(systemKey: ",", modifiers: ["cmd"])
    static let closePanel = Shortcut(systemKey: "w", modifiers: ["cmd"])

    // —— 视图切换 ——
    //
    // ⚠️ 早先注释写「实际侧栏只有三个固定入口，没有 ⌘5——硬凑一个只会让用户
    // 按了没反应」。后来引擎补齐了代码图谱/置信度/补丁体检三个**真页面**，
    // 固定视图从三个变成六个——这里的原则没变：**键位只跟着真实存在的视图走**，
    // 有一个视图才有一个键位，视图删了键位必须跟着删。
    //   ⌘1 ⇄ 总览      ⌘2 ⇄ 看板      ⌘3 ⇄ 里程碑
    //   ⌘4 ⇄ 打开当前选中的项目（没有项目时**不许**动 selection）
    //   ⌘5 ⇄ 代码图谱   ⌘6 ⇄ 置信度    ⌘7 ⇄ 补丁体检
    /// 固定视图的顺序。**这个数组的长度就是 ⌘N 的上界**，
    /// 别的地方不许再写数字快捷键。
    static let viewOrder: [ShortcutTarget] = [
        .dashboard, .board, .milestones, .graph, .confidence, .patchCheck,
    ]

    /// 第 n 个视图的数字快捷键（n 从 1 起）。越界返回 nil —— 不硬凑。
    static func view(at index: Int) -> ShortcutTarget? {
        guard index >= 1, index <= viewOrder.count else { return nil }
        return viewOrder[index - 1]
    }

    static func shortcut(for target: ShortcutTarget) -> Shortcut? {
        switch target {
        case .dashboard:   return Shortcut(systemKey: nil, key: "1", modifiers: ["cmd"])
        case .board:       return Shortcut(systemKey: nil, key: "2", modifiers: ["cmd"])
        case .milestones:  return Shortcut(systemKey: nil, key: "3", modifiers: ["cmd"])
        case .graph:       return Shortcut(systemKey: nil, key: "5", modifiers: ["cmd"])
        case .confidence:  return Shortcut(systemKey: nil, key: "6", modifiers: ["cmd"])
        case .patchCheck:  return Shortcut(systemKey: nil, key: "7", modifiers: ["cmd"])
        case .currentProject: return Shortcut(systemKey: nil, key: "4", modifiers: ["cmd"])
        }
    }

    /// 全部声明过的快捷键 —— 判据用它检查「有没有重复」。
    ///
    /// ⚠️ `currentProject` **不在 `viewOrder` 里**（那是「固定视图」的列表，
    /// 而项目详情是动态的），但它**确实占着一个键位**（⌘4）。
    /// 漏了它 ⇒ 任何与 ⌘4 撞车的声明都查不出来。
    /// 负控 NC67-d 就是靠这条抓到的。
    static var all: [Shortcut] {
        [refresh, shallow, deep, stop, find, settings, closePanel]
            + viewOrder.compactMap(shortcut(for:))
            + [shortcut(for: .currentProject)].compactMap { $0 }
    }

    /// 两个快捷键是否撞车。
    ///
    /// ⚠️ 比较时**不区分 modifier 顺序**：`cmd+shift+r` 与 `shift+cmd+r`
    /// 是同一个键位（SwiftUI 的 `KeyEquivalent` 也按集合处理）。
    /// 不做这个归一化就会漏报冲突。
    static func conflicts(_ a: Shortcut, _ b: Shortcut) -> Bool {
        a.keyEquivalent == b.keyEquivalent && Set(a.modifiers) == Set(b.modifiers)
    }

    /// 全表里有没有冲突。返回撞车的那些对。
    static func duplicatePairs() -> [(Shortcut, Shortcut)] {
        var out: [(Shortcut, Shortcut)] = []
        let all = self.all
        for i in 0..<all.count {
            for j in (i + 1)..<all.count where conflicts(all[i], all[j]) {
                out.append((all[i], all[j]))
            }
        }
        return out
    }
}
