// DesignTokens.swift — 设计 token 的**纯函数层**。
//
// 【为什么单独一个文件】这一层刻意**零 SwiftUI / 零 AppKit 依赖**，
// 所以 Tests/ClientCheck 能直接编译它并断言取值，不必把 SwiftUI 拖进命令行检查器。
// 视图层在 DesignSystem.swift，它消费这里定义的语义名。
//
// 【取值来源】逐值对应设计稿 docs/gitpulse_ai_workspace.html 的
// tailwind.config → theme.extend.colors.dev。不要单独改这里的值——要改先改设计稿。
import Foundation

// MARK: - 色板（设计稿原始值，不做亮暗拆分）

enum DSPalette {
    // 深色一套
    static let bgDark       = 0x0F172A
    static let cardDark     = 0x1E293B
    static let sidebarDark  = 0x0B0F19
    static let borderDark   = 0x334155
    // 亮色一套
    static let bgLight      = 0xF8FAFC
    static let cardLight    = 0xFFFFFF
    static let sidebarLight = 0xF1F5F9
    static let borderLight  = 0xE2E8F0
    // 双轨与强调（亮暗共用）
    static let accent       = 0x3B82F6   // 蓝 · 强调
    static let shallow      = 0x10B981   // 绿 · 浅更新（代码/提交轨）
    static let deep         = 0x8B5CF6   // 紫 · 深更新（AI 记忆/文档轨）
    static let ai           = 0x06B6D4   // 青 · AI
}

// MARK: - 状态

/// 语义化的状态档。返回语义名而不是 Color，检查才能断言"哪个状态落到哪档"。
enum DSStatus {
    case active, idle, stale, merged, unknown, dirty

    /// 引擎的状态字符串 → 语义档。未知字符串一律 `.unknown`（不猜、不默认绿）。
    static func from(_ raw: String) -> DSStatus {
        switch raw {
        case "active": return .active
        case "idle":   return .idle
        case "stale":  return .stale
        case "merged": return .merged
        case "dirty":  return .dirty
        default:       return .unknown
        }
    }

    /// VoiceOver 读出来的中文名。状态点只有 8pt 宽，没有文字替代。
    var label: String {
        switch self {
        case .active:  return "活跃"
        case .idle:    return "空闲"
        case .stale:   return "陈旧"
        case .merged:  return "已合并"
        case .dirty:   return "有未提交改动"
        case .unknown: return "状态未知"
        }
    }
}

// MARK: - 数值严重度

/// 数值量级分档。
///
/// 【修掉一个说谎的颜色】原 `statTint` 是「任何 n>0 都橙」——1 个未提交文件和
/// 300 个未提交文件显示同一个颜色，等于没分级。这里按量级分四档。
enum DSStat {
    case none      // 0：干净
    case low       // 1–2：轻微
    case medium    // 3–9：需要注意
    case high      // ≥10：需要处理

    static func from(_ n: Int) -> DSStat {
        // ⚠️ 负数不是 0。第一版写成 `case ..<1: return .none`，
        // 负数会落进「干净」档 —— 而负数意味着**数据本身有问题**（引擎给错、
        // 或解析出了负计数），这时候报「干净」是最坏的一种说谎。
        // 宁可报「需要处理」，让人看见异常。
        if n < 0 { return .high }
        switch n {
        case 0:     return .none
        case 1..<3: return .low
        case 3..<10: return .medium
        default:     return .high
        }
    }

    /// 分档不能只报数字，还得说清它是什么——给 VoiceOver 用的完整短语。
    func describe(_ n: Int, _ what: String) -> String {
        switch self {
        case .none:   return "\(what) 0 个，干净"
        case .low:    return "\(what) \(n) 个"
        case .medium: return "\(what) \(n) 个，需要注意"
        case .high:   return "\(what) \(n) 个，需要处理"
        }
    }
}

// MARK: - 双轨

/// 双轨动作。设计稿最突出的双按钮，浅=绿、深=紫。
enum DSSyncTrack {
    case shallow, deep

    var label: String {
        switch self {
        case .shallow: return "浅更新"
        case .deep:    return "深更新"
        }
    }
}
