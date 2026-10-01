// ShortcutKey.swift — 把 ShortcutMap 的声明翻成 SwiftUI 要的类型。
//
// 【为什么单独一个文件】ShortcutMap.swift **刻意零 SwiftUI 依赖**，
// 所以 Tests/ClientCheck 能直接编它并断言「有没有撞键」。
// 而 `keyboardShortcut` 要的是 `KeyEquivalent`（SwiftUI 的类型），
// 于是这层换算必须住在引 SwiftUI 的地方 —— 混进 ShortcutMap 会把
// 「可断言的纯函数层」和「视图层」搅在一起（见 DesignTokens/DesignSystem 的分层）。
import SwiftUI

extension Shortcut {
    /// SwiftUI 的键。
    ///
    /// ⚠️ `KeyEquivalent` 收的是 **Character** 而不是 String ——
    /// 系统语义键（`"."` / `","` / `"w"`）都是单字符，取首字符即可。
    /// 空键位（`shortcut(for:)` 返回 nil 时的兜底）给 `"\u{0}"`：
    /// 它匹配不到任何真实按键，**不会**误触发别人的快捷键。
    var keyEquivalentSwiftUI: KeyEquivalent {
        let k = keyEquivalent
        return KeyEquivalent(k.first ?? "\u{0}")
    }

    /// SwiftUI 的 modifier 集合。
    ///
    /// 视图用 `.keyboardShortcut(s.keyEquivalentSwiftUI, modifiers: s.modifiersSwiftUI)`，
    /// 免得每处手写 `[.command, .shift]` 而某处漏一个 ——
    /// 漏一个不会编译失败，只会让 ⇧ 静默失效。
    var modifiersSwiftUI: EventModifiers {
        var m: EventModifiers = []
        if self.modifiers.contains("cmd") { m.insert(.command) }
        if self.modifiers.contains("shift") { m.insert(.shift) }
        if self.modifiers.contains("alt") { m.insert(.option) }
        return m
    }
}
