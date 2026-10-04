// deepDolphin Linux 客户端 —— 设计令牌（**纯函数层**）。
//
// 【为什么单独一个文件、为什么不 import cui】
// 这一层刻意零 CUI 依赖，所以判据能直接编译它并断言取值，
// 不必把整个 GUI 栈拖进命令行检查器。
// 视图层在 `theme.cj`，它消费这里定义的语义名。
// 改色只动视图层，令牌层的取值与判据都不会失真 ——
// 这与 macOS 端 `DesignTokens.swift` / `DesignSystem.swift` 的分层完全同构。
//
// 【取值来源】逐值对应 macOS 端 `DesignTokens.swift` 的
// DSPalette（承接设计稿 docs/gitpulse_ai_workspace.html 的
// tailwind.config → theme.extend.colors.dev）。**不是自己另编的一套** ——
// 两个客户端的同一个「活跃」必须是同一个绿，跨平台对同一概念的颜色不一致，
// 用户会以为是两件事。
package deepdolphin_linux

// ===========================================================================
// 色板
// ===========================================================================

/// 深色一套
public let BG_DARK: Int64 = 0x0F172A
public let CARD_DARK: Int64 = 0x1E293B
public let SIDEBAR_DARK: Int64 = 0x0B0F19
public let BORDER_DARK: Int64 = 0x334155

/// 亮色一套
public let BG_LIGHT: Int64 = 0xF8FAFC
public let CARD_LIGHT: Int64 = 0xFFFFFF
public let SIDEBAR_LIGHT: Int64 = 0xF1F5F9
public let BORDER_LIGHT: Int64 = 0xE2E8F0

/// 强调与双轨（亮暗共用）
public let C_ACCENT: Int64 = 0x3B82F6   // 蓝 · 强调
public let C_SHALLOW: Int64 = 0x10B981  // 绿 · 浅更新（代码/提交轨）
public let C_DEEP: Int64 = 0x8B5CF6     // 紫 · 深更新（AI 记忆/文档轨）
public let C_AI: Int64 = 0x06B6D4       // 青 · AI

/// 状态色
public let C_YELLOW: Int64 = 0xEAB308
public let C_ORANGE: Int64 = 0xF97316
public let C_RED: Int64 = 0xEF4444
public let C_GRAY: Int64 = 0x94A3B8
public let C_SLATE: Int64 = 0x64748B

/// 状态色**作为文字**时的亮底变体。
///
/// 黄/橙这类高明度状态色直接当文字放在亮底上读不清：
/// #EAB308 对白卡只有 1.92:1、#F97316 只有 2.8:1（WCAG 正文要求 4.5:1）。
/// 亮色主题换同色系的深档；**暗色主题保持原值** —— 亮色在暗底上反而是对的
/// （#EAB308 对暗卡 7.6:1）。色点与胶囊底色不走这层：
/// 色块靠面积辨读，不靠文字对比度。
public let C_YELLOW_TEXT_LIGHT: Int64 = 0xA16207   // amber-700 · 对白卡 4.92:1
public let C_ORANGE_TEXT_LIGHT: Int64 = 0xC2410C   // orange-700 · 对白卡 5.18:1

/// 文字该用哪一档状态色。**视图里凡把状态色喂给 `foregroundColor` 都经过这里**，
/// 直接 `dsColor(C_YELLOW)` 写在亮底上就是 1.9:1 的不可读文字。
///
/// ⚠ 刻意用 `==` 而不是 `match case C_YELLOW`：仓颉的 match 里一个大写
/// `let` 常量是**绑定模式**（新变量、匹配一切），不是常量比较 ——
/// 写成 match 会让每个色都落到第一档（本函数首版就栽在这，判据当场红）。
public func dsTextColor(accent: Int64, dark: Bool): Int64 {
    if (dark) {
        return accent
    }
    if (accent == C_YELLOW) {
        return C_YELLOW_TEXT_LIGHT
    }
    if (accent == C_ORANGE) {
        return C_ORANGE_TEXT_LIGHT
    }
    return accent
}

// ===========================================================================
// 间距 —— 刻度 4/8/12/16/20/24，淘汰散值
// ===========================================================================

public let SP_XS: Float64 = 4.0
public let SP_SM: Float64 = 8.0
public let SP_MD: Float64 = 12.0
public let SP_LG: Float64 = 16.0
public let SP_XL: Float64 = 20.0
public let SP_XXL: Float64 = 24.0

// ===========================================================================
// 圆角 —— 收敛到 3 档
// ===========================================================================

public let R_CHIP: Float64 = 3.0     // 迷你条 / 分段条
public let R_CONTROL: Float64 = 6.0  // 控件 / 小卡
public let R_CARD: Float64 = 10.0    // 卡片

// ===========================================================================
// 状态
// ===========================================================================

// ⚠ 字号刻度**不在这里**。曾经另有一套 `FS_*` 常量，与 `components.cj`
// 的 `fs*()` 函数并存 —— 同一个「正文」两处各说各的字号，必然漂移。
// FS_* 全仓零引用，已删；字号只有 `components.cj` 的 `fsMicro…fsDisplay`
// 一套。要加字号档，去那里加，别在这里再立一张表。

/// 语义化状态档。返回语义名而不是颜色，判据才能断言「哪个状态落到哪档」。
public enum DsStatus {
    | Active
    | Idle
    | Stale
    | Merged
    | Dirty
    | Unknown
}

/// 引擎的状态字符串 → 语义档。**未知字符串一律 Unknown** ——
/// 不猜、不默认绿。把「没读懂」画成「活跃」是最坏的一种说谎。
public func dsStatusFrom(raw: String): DsStatus {
    match (raw) {
        case "active" => return DsStatus.Active
        case "idle" => return DsStatus.Idle
        case "stale" => return DsStatus.Stale
        case "merged" => return DsStatus.Merged
        case "dirty" => return DsStatus.Dirty
        case _ => return DsStatus.Unknown
    }
}

/// 两个状态档是否相同。仓颉的枚举**不自动实现** `==`（编译期直接报
/// "invalid binary operator"），所以配一个显式谓词。
/// 判据里用它而不是在每个调用点写一遍 `match`。
public func dsStatusIs(a: DsStatus, b: DsStatus): Bool {
    match (a) {
        case DsStatus.Active => return match (b) { case DsStatus.Active => true; case _ => false }
        case DsStatus.Idle => return match (b) { case DsStatus.Idle => true; case _ => false }
        case DsStatus.Stale => return match (b) { case DsStatus.Stale => true; case _ => false }
        case DsStatus.Merged => return match (b) { case DsStatus.Merged => true; case _ => false }
        case DsStatus.Dirty => return match (b) { case DsStatus.Dirty => true; case _ => false }
        case DsStatus.Unknown => return match (b) { case DsStatus.Unknown => true; case _ => false }
    }
}

/// 状态档的十六进制色。
public func dsStatusColor(s: DsStatus): Int64 {
    match (s) {
        case DsStatus.Active => return C_SHALLOW
        case DsStatus.Idle => return C_YELLOW
        case DsStatus.Stale => return C_ORANGE
        case DsStatus.Merged => return C_DEEP
        case DsStatus.Dirty => return C_RED
        case DsStatus.Unknown => return C_GRAY
    }
}

/// 状态档的中文名。状态点很窄，没有文字替代时读者无从判断。
public func dsStatusLabel(s: DsStatus): String {
    match (s) {
        case DsStatus.Active => return "活跃"
        case DsStatus.Idle => return "空闲"
        case DsStatus.Stale => return "陈旧"
        case DsStatus.Merged => return "已合并"
        case DsStatus.Dirty => return "有未提交改动"
        case DsStatus.Unknown => return "状态未知"
    }
}

// ===========================================================================
// 数值严重度
// ===========================================================================

public enum DsStat {
    // ⚠ 这一档**不能叫 None**。仓颉里 `None` 是 `Option` 的构造器，
    // 而枚举 case 在包作用域是可见的名字 —— 一旦本枚举占了 `None`，
    // 全仓所有 `State<Option<T>>(None)` 都会被解析成 `DsStat.None`，
    // 编译报「expected Option<X>, found Enum-DsStat」，而错的位置在
    // 一个跟设计毫无关系的文件里（appstate.cj），排查成本极高。
    | Clean     // 0：干净
    | Low       // 1–2：轻微
    | Medium    // 3–9：需要注意
    | High      // ≥10：需要处理
}

/// 数值量级分档。
///
/// 【这里修掉过一种说谎的颜色】原实现是「任何 n>0 都橙」——
/// 1 个未提交文件和 300 个未提交文件显示同一个颜色，等于没分级。
///
/// 负数不是 0。负数意味着**数据本身有问题**（引擎给错或解析出了负计数），
/// 这时候报「干净」是最坏的一种说谎；宁可报「需要处理」，让人看见异常。
public func dsStatFrom(n: Int64): DsStat {
    if (n < 0) {
        return DsStat.High
    }
    if (n == 0) {
        return DsStat.Clean
    }
    if (n < 3) {
        return DsStat.Low
    }
    if (n < 10) {
        return DsStat.Medium
    }
    return DsStat.High
}

/// 两个量级档是否相同。理由同 `dsStatusIs`。
public func dsStatIs(a: DsStat, b: DsStat): Bool {
    match (a) {
        case DsStat.Clean => return match (b) { case DsStat.Clean => true; case _ => false }
        case DsStat.Low => return match (b) { case DsStat.Low => true; case _ => false }
        case DsStat.Medium => return match (b) { case DsStat.Medium => true; case _ => false }
        case DsStat.High => return match (b) { case DsStat.High => true; case _ => false }
    }
}

public func dsStatColor(s: DsStat): Int64 {
    match (s) {
        case DsStat.Clean => return C_SLATE
        case DsStat.Low => return C_YELLOW
        case DsStat.Medium => return C_ORANGE
        case DsStat.High => return C_RED
    }
}

/// 量级档的短名。给胶囊用。
///
/// 为什么不能直接显示数字：一个橙色的「1」和另一个橙色的「300」，
/// 只看数字读不出差别到底要不要紧；档位名把「轻微 / 需要注意 / 需要处理」
/// 这层判断直接说出来。数字仍在旁边，两者都不丢。
public func dsStatLabel(s: DsStat): String {
    match (s) {
        case DsStat.Clean => return "干净"
        case DsStat.Low => return "轻微"
        case DsStat.Medium => return "需要注意"
        case DsStat.High => return "需要处理"
    }
}

/// 分档不能只报数字，还得说清它是什么。
public func dsStatDescribe(n: Int64, what: String): String {
    match (dsStatFrom(n)) {
        case DsStat.Clean => return "${what} 0 个，干净"
        case DsStat.Low => return "${what} ${n} 个"
        case DsStat.Medium => return "${what} ${n} 个，需要注意"
        case DsStat.High => return "${what} ${n} 个，需要处理"
    }
}

// ===========================================================================
// 双轨
// ===========================================================================

public enum DsTrack {
    | Shallow
    | Deep
}

public func dsTrackColor(t: DsTrack): Int64 {
    return match (t) {
        case DsTrack.Shallow => C_SHALLOW
        case DsTrack.Deep => C_DEEP
    }
}

public func dsTrackLabel(t: DsTrack): String {
    return match (t) {
        case DsTrack.Shallow => "浅更新"
        case DsTrack.Deep => "深更新"
    }
}

// ===========================================================================
// 序列色 —— 全局唯一映射口
// ===========================================================================

/// 序列色的 12 档，**提交构成与语言分布共用同一份**。
///
/// ⚠ 曾经的病：提交构成卡内联 12 色、语言分布卡内联 8 色，两张卡各写各的。
/// 后果是同一个「蓝」在一张卡里表示 feat、在另一张卡里表示 Swift，
/// 读者拿两张卡对照会误读。这里收敛成一张表，序号 → 颜色只有一个入口。
///
/// ⚠⚠ 本表自己踩过一次同样的病：第 4 档与第 9 档都填了紫 `0x8B5CF6`，
/// 第 5 档与第 11 档都填了青 `0x06B6D4`。后果不是「不够好看」，是
/// **同一根分段条上两段同色、图例里两行同色圆点** —— 读者根本分不出
/// 那是两类。序号语义色表一旦有重复，条形图就废了。
/// 所以这里配一条判据「12 档两两不同」，重复即红。
public func dsSequenceColor(index: Int64): Int64 {
    let palette = dsSequencePalette()
    if (index < 0) {
        return C_GRAY
    }
    return palette[Int64(index % palette.size)]
}

/// 序列色的**完整表**。抽成函数是为了让判据能直接遍历它查重复 ——
/// 判据要能看见全部 12 个值，光看 `dsSequenceColor(0..12)` 是能拿到的，
/// 但那样每取一个都要重新调一遍，落进表里的具体字面量就没人盯了。
public func dsSequencePalette(): Array<Int64> {
    return [
        C_ACCENT,  // 0 蓝
        C_RED,     // 1 红
        C_ORANGE,  // 2 橙
        C_DEEP,    // 3 紫
        C_AI,      // 4 青
        0x6366F1,  // 5 靛
        C_SHALLOW, // 6 薄荷
        0xEC4899,  // 7 粉
        0xA16207,  // 8 棕
        C_YELLOW,  // 9 黄
        0x22D3EE,  // 10 天蓝（与第 4 档的青拉开明度差）
        C_SLATE    // 11 灰
    ]
}

/// 序列色的槽位数。判据要能查「所有调用点的槽位数一致」。
public let DS_SEQUENCE_SLOTS: Int64 = 12
