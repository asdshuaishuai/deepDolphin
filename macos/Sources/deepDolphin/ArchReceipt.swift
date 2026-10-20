// ArchReceipt.swift — 引擎回执的**纯函数**解析（批 AR）
//
// 【为什么抽成纯函数】
// 原来这段逻辑**内联在两个 ViewModel 里**（ArchPage / CodeGraphPage，
// 各一份**同名复制**）⇒ 既**测不到**、也**改一处漏一处**。
// 抽成纯函数后才能进 `scripts/client-check.sh` 的判据。
//
// 【要修的缺陷】
// 引擎回执的**真实形态**是（2026-10-20 实跑 `moongit render arch` 取得）：
//   已写入：/home/…/.deepgit/store/p_…/render/arch.html · 共 0 个文件，0 个函数（…）
// 路径与文案之间是**全角冒号**（不是空格）⇒ 按**空格**切词会切出
// 「已写入：/path/arch.html」这种**粘连块** ⇒ `hasPrefix("/")` 恒假
// ⇒ **抽不出路径** ⇒ 导出后「打开」入口**始终不出现**（死按钮）。
//
// 【口径与 deepin 侧一致】（对位实现）
// deepin 侧 `deepin/src/logic/ArchReceipt.cpp` 用的是同一套规则：
//   · 边界 = 空白 / 全角冒号「：」/ 中点「·」
//     （deepin 侧的正则是 `(?<=[\s：·])(/[^\s：·]*<后缀>)`）；
//   · 只认**绝对路径**（相对路径不认 —— 打不开的路径等于坏按钮）；
//   · 后缀由调用方给（render arch 出 .html、report 出 .md）。
// ⚠ 本实现**不缓存**任何按后缀构造的正则/字符集 ⇒ 不会踩 deepin 侧
//   踩过的那个坑（正则放在函数级 static 里 ⇒ 「第一次调用用哪个后缀，
//   模式就焊死成哪个」⇒ 之后传 .md 也按 .html 找，报告路径永远抽不到）。
import Foundation

enum ArchReceipt {

    /// 回执的**结论行**：从末尾往前找第一个非空行。
    /// 引擎回执的最后一行才是结论（如「已写入：… · 共 N 个文件」），
    /// 前面几行是明细。
    static func receipt(_ text: String) -> String? {
        for line in text.split(separator: "\n").reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// 从回执里抽出**绝对路径**（后缀由调用方给）。
    /// 抽不到返回 nil（调用方据此**不显示**「打开」入口 —— 宁可没有，不要坏按钮）。
    static func filePath(_ text: String, suffix: String) -> String? {
        if suffix.isEmpty { return nil }
        for line in text.split(separator: "\n") {
            for token in line.components(separatedBy: boundary) {
                let t = token.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("/") && t.hasSuffix(suffix) { return t }
            }
        }
        return nil
    }

    /// render arch 的产物路径（.html）。
    static func htmlPath(_ text: String) -> String? {
        return filePath(text, suffix: ".html")
    }

    /// 路径的**边界字符集**：空白 + 全角冒号「：」+ 中点「·」。
    /// ⚠ 这三个里最要紧的是**全角冒号** —— 引擎真实回执就是用它把路径
    /// 和文案粘在一起的（漏了它 ⇒ 路径抽不出来）。
    private static let boundary: CharacterSet = {
        var s = CharacterSet.whitespacesAndNewlines
        s.insert(charactersIn: "\u{FF1A}") // 全角冒号「：」
        s.insert(charactersIn: "\u{00B7}") // 中点「·」
        return s
    }()
}
