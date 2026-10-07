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

// MARK: - 渐变

/// 主题的质感层。**渐变只做两件事**：hero 页头的底、以及同一语义色内部
/// 的深→亮过渡（`shallow`/`deep`/`accent` 的第二端点是同一个语义色的亮变体，
/// 不是第二种语义）——拿别的语义色来拼渐变等于发明第四种双轨色。
enum DSGradient {
    /// hero 页头：靛 → 紫 → 青。仪表盘页头与关于页头共用，
    /// 两处必须同一张底 —— 这是产品的「封面」，两张封面各画各的迟早分叉。
    static let hero = LinearGradient(
        colors: [Color(rgbHex: DSPalette.heroIndigo), Color(rgbHex: DSPalette.heroViolet), Color(rgbHex: DSPalette.heroCyan)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let shallow = LinearGradient(
        colors: [DSColor.shallow, Color(rgbHex: DSPalette.shallowAlt)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let deep = LinearGradient(
        colors: [DSColor.deep, Color(rgbHex: DSPalette.deepAlt)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let ai = LinearGradient(
        colors: [DSColor.ai, Color(rgbHex: DSPalette.accentAlt)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let accent = LinearGradient(
        colors: [DSColor.accent, Color(rgbHex: DSPalette.heroCyan)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
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

/// 圆角矩形的**唯一构造点**。
///
/// ⚠️ 原来 9 处 `RoundedRectangle(` 里只有 `surface` 内部写了
/// `style: .continuous`，其余 8 处用默认的 circular ——
/// 于是同一张 Card（continuous）里嵌着的 Chip / 描边 / 彩色底（circular）
/// 圆角**接缝对不上**。圆角值早就收敛到 DSRadius 三档了（§3.3），
/// 但「渲染风格有两套」这件事没人管。
///
/// 连续曲率是 macOS 原生控件的做法，所以统一到 `.continuous`；
/// 在这里集中一次，是为了让判据能查「不许再出现裸的 RoundedRectangle」。
enum DSRect {
    /// 返回**具体类型**而不是 `some View`：
    /// 不透明类型进了 `.overlay { }` 这种 ViewBuilder 之后，
    /// 编译器会崩在 "failed to produce diagnostic for expression"
    /// （不是语法错误，是它推导不出来，害我以为是自己写错了）。
    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

extension View {
    /// 统一卡片表面：底色 + 发丝描边 + 单层软阴影。
    ///
    /// 【为什么在唯一构造点加质感】底色、描边、阴影三者必须**同进同退**——
    /// 只给某几张卡加阴影，用户读到的是「这几张卡比较重要」（假层级）；
    /// 全部卡都有同一档质感，层次才回到内容本身。描边用 border token：
    /// 亮色下是浅灰发丝线，暗色下把卡片从同色底上「托」出来；
    /// 阴影压到 0.05 —— 是让平面有一点点浮起，不是卡片投影设计。
    func surface(_ level: DSLevel = .card) -> some View {
        background(level.fill, in: DSRect.shape(level.radius))
            .overlay(DSRect.shape(level.radius).strokeBorder(DSColor.border.opacity(0.8), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }

    /// 语义着色表面。**刻意与 `surface` 分开**：
    /// 这里的颜色本身携带语义（红底 = 出错 / 强调色 = AI 消息），
    /// 收进中性 `surface` 就把「读不出来」和「确实没有」画成同一张卡
    /// —— 与不变量 81「不知道与确实没有必须分开」是同一件事。
    ///
    /// ⚠️ 参数必须是泛型 `ShapeStyle` 而不是 `Color`：
    /// `.quaternary` / `.secondary` / `.tertiary` 是 `HierarchicalShapeStyle`，
    /// 不是 `Color`（`Color.quaternary` 编译不过）。写死 `Color` 就会逼着
    /// 调用方把层级色硬转成 Color，白丢一层语义 —— 同一个坑在三元表达式里
    /// 也踩过（`cond ? .secondary : .red` 两边类型不同族）。
    func tinted<S: ShapeStyle>(_ color: S, radius: CGFloat = DSRadius.card) -> some View {
        background(color, in: DSRect.shape(radius))
    }
}

// MARK: - 图标色块

/// 统计卡 / KPI 卡右上角的语义图标：圆角色块底 + 语义色图标。
///
/// ⚠️ 色块底的透明度在这里收敛（0.14）——原来散在调用方的 `.opacity(0.55)`
/// 文字色与 `.opacity(0.14)` 底色各写各的，两张卡一深一浅。
/// 图标与底必须是**同一个语义色**的两个透明度，这是「色块」而不是「贴纸」。
struct DSIconTile: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: DSRect.shape(DSRadius.control))
    }
}
