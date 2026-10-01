// DesignSystem.swift — 视图层：把 DesignTokens 的语义名变成实际的颜色/间距/圆角/字体。
//
// 【分层，刻意】
//   DesignTokens.swift —— 纯函数层，零 SwiftUI 依赖，可被 ClientCheck 直接断言。
//   本文件             —— 视图层，消费语义名。改色不会让检查失真。
//
// 【取值来源】全部承接设计稿 docs/gitpulse_ai_workspace.html 的 tailwind.config，
// 不是自己编的一套。规范见 docs/deepgit-redesign-plan.md §3.3。
//
// 【边界】暗色/亮色跟随系统（设计稿 darkMode: 'class'，两套色板都有）。
import SwiftUI
import AppKit

// MARK: - 颜色

enum DSColor {
    /// 亮/暗自适应。设计稿两套色板，macOS 跟随系统外观。
    static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgbHex: isDark ? dark : light)
        })
    }

    // 表面三级
    static let surface    = dynamic(light: DSPalette.cardLight,    dark: DSPalette.cardDark)
    static let surfaceAlt = dynamic(light: DSPalette.bgLight,       dark: DSPalette.bgDark)
    static let sidebar    = dynamic(light: DSPalette.sidebarLight,  dark: DSPalette.sidebarDark)
    static let border     = dynamic(light: DSPalette.borderLight,   dark: DSPalette.borderDark)

    // 文字三级
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary  = Color.secondary.opacity(0.65)

    // 双轨与强调
    static let shallow = Color(rgbHex: DSPalette.shallow)
    static let deep    = Color(rgbHex: DSPalette.deep)
    static let ai      = Color(rgbHex: DSPalette.ai)
    static let accent  = Color(rgbHex: DSPalette.accent)

    /// 状态色：语义档 → 颜色
    static func color(_ s: DSStatus) -> Color {
        switch s {
        case .active:  return Color(rgbHex: DSPalette.shallow)
        case .idle:    return .yellow
        case .stale:   return .orange
        case .merged:  return Color(rgbHex: DSPalette.deep)
        case .dirty:   return .red
        case .unknown: return .secondary
        }
    }

    /// **序列色**：排名序号 token → 颜色。全局唯一映射口。
    ///
    /// 序号来自 `CommitTypeColor.palette`（纯函数层里色板的唯一声明处），
    /// 提交构成卡与语言分布卡都走这里。
    ///
    /// ⚠️ 语言分布卡原来在自己函数体里内联了 8 色
    /// （`.blue, .purple, .orange, .teal…`），而提交构成卡是 12 色
    /// （`.blue, .red, .orange, .purple…`）。于是：
    ///   · 同一个「蓝」在一张卡里是 feat、在另一张卡里是 Swift；
    ///   · 序号相同的两项两张卡颜色还不同，读者拿两张卡对照会误读。
    /// 这正是改版规范 §3.3 点名的「消灭两套调色板」。
    ///
    /// 穷举 switch，没有 default：往 `CommitTypeColor` 加新 case 而忘了配颜色，
    /// 编译就红。
    static func sequence(_ c: CommitTypeColor) -> Color {
        switch c {
        case .blue: return .blue
        case .red: return .red
        case .orange: return .orange
        case .purple: return .purple
        case .teal: return .teal
        case .indigo: return .indigo
        case .mint: return .mint
        case .pink: return .pink
        case .brown: return .brown
        case .yellow: return .yellow
        case .cyan: return .cyan
        case .gray: return .gray
        }
    }

    /// 量级色：分档 → 颜色
    static func color(_ s: DSStat) -> Color {
        switch s {
        case .none:   return .primary
        case .low:    return .yellow
        case .medium: return .orange
        case .high:   return .red
        }
    }

    static func color(_ t: DSSyncTrack) -> Color {
        switch t {
        case .shallow: return shallow
        case .deep:    return deep
        }
    }
}

private extension Color {
    init(rgbHex: Int) {
        self.init(
            .sRGB,
            red:     CGFloat((rgbHex >> 16) & 0xFF) / 255.0,
            green:   CGFloat((rgbHex >> 8) & 0xFF) / 255.0,
            blue:    CGFloat( rgbHex       & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

private extension NSColor {
    convenience init(rgbHex: Int) {
        self.init(
            srgbRed: CGFloat((rgbHex >> 16) & 0xFF) / 255.0,
            green:   CGFloat((rgbHex >> 8) & 0xFF) / 255.0,
            blue:    CGFloat( rgbHex       & 0xFF) / 255.0,
            alpha:   1.0
        )
    }
}

// MARK: - 间距

/// 间距刻度 4/8/12/16/20/24。淘汰散值。
enum DSSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - 圆角

/// 圆角收敛到 3 档。淘汰 8 种散值（2/3/4/8/10/11/12/14）。
enum DSRadius {
    static let chip: CGFloat = 3      // 迷你条 / 分段条
    static let control: CGFloat = 6   // 控件 / 小卡
    static let card: CGFloat = 10     // 卡片
}

// MARK: - 字体

/// 收敛到系统文本样式。淘汰 .font(.system(size:))。
enum DSTypography {
    static let metric       = Font.system(.title2, design: .rounded).weight(.semibold)
    static let cardTitle    = Font.subheadline.weight(.semibold)
    static let sectionTitle = Font.headline
    static let body         = Font.body
    static let label        = Font.caption
    static let badge        = Font.caption2
}

// MARK: - 动效

/// 统一缓动与时长，遵循 macOS 观感（不过度）。
enum DSMotion {
    static let quick    = Animation.easeOut(duration: 0.12)
    static let standard = Animation.easeInOut(duration: 0.20)
}

// MARK: - 卡片表面

/// 统一卡片表面。以前 `Color(nsColor: .controlBackgroundColor) + RoundedRectangle`
/// 这对写法散在 5 个文件 9 处，每处圆角还各不相同（8/10/11/12/14）。
enum DSLevel {
    case card, nested, inset

    var fill: Color {
        switch self {
        case .card:   return DSColor.surface
        case .nested: return DSColor.surfaceAlt
        case .inset:  return DSColor.surface.opacity(0.6)
        }
    }

    var radius: CGFloat {
        switch self {
        case .card:   return DSRadius.card
        case .nested: return DSRadius.control
        case .inset:  return DSRadius.chip
        }
    }
}

extension View {
    func surface(_ level: DSLevel = .card) -> some View {
        background(level.fill, in: RoundedRectangle(cornerRadius: level.radius, style: .continuous))
    }
}
