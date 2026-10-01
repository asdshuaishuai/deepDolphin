import Foundation

/// 卡片里最多画几种语言（**唯一来源**）。
///
/// 引擎的上限是 `DASH_LANG_TOP`（12），界面再砍到 8。
/// 两个上限**各自都有各自的披露**（`topCut` / `shownCount`），
/// 所以这个数字可以自由调 —— 调大调小都不会让披露失真。
let LANG_BAR_MAX = 8

/// 语言分布卡片的覆盖度披露。**纯函数，零依赖**。
///
/// 为什么单独成文件：判定内联在视图里时，运行时根本抓不到它，
/// 而「失败被渲染成没有」恰恰是那种只能靠断言钉住的问题。
///
/// 引擎侧对应缺陷 #187：
/// `listFiles` 采集失败时原本返回 `FileListing([], 0, false)` ——
/// 既没有错误标志，`truncated: false` 反而**声称没截断**。
/// 于是失败的项目在语言分布里与「零个文件的项目」完全同形。
/// 引擎现在恒发 `languagesFailed` / `languagesFailedReasons`，
/// 本函数负责把它们变成界面上看得见的话。
///
/// 三种状态必须分开，任何两种合并都会撒谎：
///   · 完整        —— 什么也不用说
///   · 截断        —— 看了，只留了一部分
///   · 采集失败    —— 压根没看成（与「这个项目群没有这些语言」无关）
struct LanguageCoverage: Equatable {
    /// `languages` 为空时该显示什么。空数组有两种成因，文案必须不同：
    /// 「暂无数据」会被读成「真的没有」，而真相可能是「没采到」。
    let emptyTitle: String
    /// 卡片下方要补的一行说明；nil 表示没什么要说的。
    let note: String?
}

/// 覆盖度披露的**唯一**判定点。
///
/// - Parameters:
///   - languageCount: 引擎给出的语言条数（**含**界面上没画出来的那几条）
///   - truncated: 引擎的 `languagesTruncated`（撞跟踪文件上限）
///   - failed: 引擎的 `languagesFailed`（采集失败的项目数）
///   - reasons: 引擎的 `languagesFailedReasons`（失败原因样例）
///   - topCut: 引擎的 `languagesTopCut`（语言**条数**被引擎上限砍掉）
///   - shownCount: 界面上**实际画出来**的条数（引擎还额外砍了一层）
///
/// ⚠️ 三个截断轴彼此独立，**少一个就撒谎**：
///   · `truncated` —— 文件被砍（20000 上限），掉出去的文件里可能还有整类语言
///   · `topCut`    —— 语言**条数**被引擎砍（DASH_LANG_TOP）
///   · `shownCount < languageCount` —— **界面自己**又砍了一层
///     （原实现是 `d.languages.prefix(8)`，界面上 8 条、引擎 12 条，
///      而这里拿到的是 `d.languages.count` = 12 —— 于是披露按 12 算、
///      界面画 8 条，**藏起来的那几条一个字都不提**。）
/// 缺陷 #205 实测：14 种语言的仓库，卡片只列 8 条且零提示。
func languageCoverage(
    languageCount: Int,
    truncated: Bool,
    failed: Int,
    reasons: [String]?,
    topCut: Bool = false,
    shownCount: Int? = nil
) -> LanguageCoverage {
    var notes: [String] = []

    if truncated {
        notes.append("有项目撞到跟踪文件上限，被丢掉的文件里可能还有整类语言")
    }
    if topCut {
        notes.append("语言种类超过引擎上限，只列了排名靠前的一部分（不是全部语言）")
    }
    if let shown = shownCount, shown < languageCount {
        // 界面自己砍的：这一句说的是**这张卡片**，与引擎那条是两回事
        notes.append("这张卡片只显示前 \(shown) 种语言（共 \(languageCount) 种）")
    }
    if failed > 0 {
        var line = "\(failed) 个项目语言采集失败，未计入这份分布（不是「这个项目群没有这些语言」）"
        if let first = reasons?.first, !first.isEmpty {
            line += "；原因示例：\(first)"
        }
        notes.append(line)
    }

    // 采集失败时 languages 为空是**正常结果**，不是「没数据」。
    // 文案必须让用户知道该去查引擎，而不是以为项目群真的没这些语言。
    let emptyTitle: String
    if failed > 0 && languageCount == 0 {
        emptyTitle = "未采集到语言数据"
    } else {
        emptyTitle = "暂无数据"
    }

    return LanguageCoverage(
        emptyTitle: emptyTitle,
        note: notes.isEmpty ? nil : notes.joined(separator: "\n")
    )
}
