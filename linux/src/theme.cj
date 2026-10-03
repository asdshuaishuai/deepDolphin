// deepDolphin Linux 客户端 —— 视图层设计系统。
//
// 消费 `tokens.cj` 的语义名，把它们变成实际的颜色/间距/圆角/字号。
// 改色只动这里，令牌层与判据不受影响。
//
// 【亮暗】跟随系统外观。两套色板都从令牌层取，两端同时存在。
package deepdolphin_linux

import cui.{Color, SurfaceStyle, Theme}

/// 十六进制 → Color。
func dsColor(hex: Int64): Color {
    return Color.rgb((hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF)
}

/// 表面层级。**刻意只有三档**，淘汰散值。
public enum DsLevel {
    | Card    // 主卡
    | Nested  // 卡内嵌套块
    | Inset   // 更轻的嵌入区
}

/// 中性表面。**不带语义**。
public func dsSurface(level: DsLevel, dark: Bool): SurfaceStyle {
    let fill = match (level) {
        case DsLevel.Card => (if (dark) { CARD_DARK } else { CARD_LIGHT })
        case DsLevel.Nested => (if (dark) { BG_DARK } else { BG_LIGHT })
        case DsLevel.Inset => (if (dark) { BG_DARK } else { SIDEBAR_LIGHT })
    }
    let border = (if (dark) { BORDER_DARK } else { BORDER_LIGHT })
    let radius = match (level) {
        case DsLevel.Card => R_CARD
        case DsLevel.Nested => R_CONTROL
        case DsLevel.Inset => R_CHIP
    }
    return SurfaceStyle(dsColor(fill), border: dsColor(border), borderWidth: 1.0, radius: Float32(radius))
}

/// 侧栏表面。与主卡区分开，让「导航」与「内容」在视觉上分层。
public func dsSidebar(dark: Bool): SurfaceStyle {
    let fill = (if (dark) { SIDEBAR_DARK } else { SIDEBAR_LIGHT })
    let border = (if (dark) { BORDER_DARK } else { BORDER_LIGHT })
    return SurfaceStyle(dsColor(fill), border: dsColor(border), borderWidth: 1.0, radius: Float32(R_CARD))
}

/// **语义着色表面**。刻意与 `dsSurface` 分开：
///
/// 这里的颜色本身携带语义（红底 = 出错 / 琥珀底 = 部分失败 / 绿底 = 全成功）。
/// 收进中性表面就把「读不出来」和「确实没有」画成同一张卡 ——
/// 与 macOS 端不变量 81「不知道与确实没有必须分开」是同一件事。
public func dsTinted(accent: Int64, dark: Bool, strong!: Bool = false): SurfaceStyle {
    // 强色（出错）用低透明度铺底 + 同色系描边；弱色（提示）只描边。
    // 两种都在暗色下重新取底色，否则亮色版的浅底在暗色主题里会发白。
    let fillHex = (if (dark) { CARD_DARK } else { CARD_LIGHT })
    let borderHex = accent
    return SurfaceStyle(
        dsColor(fillHex),
        border: dsColor(borderHex).withAlpha(if (strong) { 110 } else { 70 }),
        borderWidth: 1.0,
        radius: Float32(R_CONTROL)
    )
}

/// 状态点颜色（供 Badge / 状态行取色）。
public func dsStatusBadgeColor(s: DsStatus): Int64 {
    return dsStatusColor(s)
}

/// CUI 主题。亮色。
public func ddLightTheme(): Theme {
    return Theme(
        bg: dsColor(BG_LIGHT),
        panel: dsColor(CARD_LIGHT),
        panelEdge: dsColor(BORDER_LIGHT),
        text: dsColor(0x0F172A),
        mutedText: dsColor(0x64748B),
        accent: dsColor(C_ACCENT),
        accentText: dsColor(0xFFFFFF),
        danger: dsColor(C_RED),
        field: dsColor(0xF1F5F9),
        fieldActive: dsColor(0xDBEAFE),
        panelRaised: dsColor(CARD_LIGHT),
        accentSoft: dsColor(0xDBEAFE),
        shadow: dsColor(0x0F172A).withAlpha(0),
        radius: Float32(R_CARD),
        smallRadius: Float32(R_CHIP),
        controlRadius: Float32(R_CONTROL),
        borderWidth: 1.0
    )
}

/// CUI 主题。暗色。
public func ddDarkTheme(): Theme {
    return Theme(
        bg: dsColor(BG_DARK),
        panel: dsColor(CARD_DARK),
        panelEdge: dsColor(BORDER_DARK),
        text: dsColor(0xE2E8F0),
        mutedText: dsColor(0x94A3B8),
        accent: dsColor(C_ACCENT),
        accentText: dsColor(0x0F172A),
        danger: dsColor(C_RED),
        field: dsColor(0x0B0F19),
        fieldActive: dsColor(0x1E3A5F),
        panelRaised: dsColor(0x334155),
        accentSoft: dsColor(0x1E3A5F),
        shadow: dsColor(0x000000).withAlpha(0),
        radius: Float32(R_CARD),
        smallRadius: Float32(R_CHIP),
        controlRadius: Float32(R_CONTROL),
        borderWidth: 1.0
    )
}
