// deepDolphin Linux 客户端 —— 基础视图件。
//
// 【与 macOS 端同构】`Components.swift` 里的 StatusDot / StatCard /
// SegmentedBar / Chip / Card，在本文件各有对应。同样的语义、同样的令牌来源，
// 只是**摆法**按 Linux 桌面习惯走 —— 章程允许交互与布局自由发挥，
// 不允许的是「同一个概念在两端长得不一样」。
//
// 【为什么不用 CUI 的 Badge 当状态胶囊】`Badge` 的六档颜色是 CUI 自己写死的
// （`badge.cj:64` 的 `badgeColor`），和本项目的令牌层对不上：
// 同一个「活跃」，macOS 是令牌层的绿，CUI Badge 又是另一个绿。
// 跨平台颜色不一致，用户会以为是两件事。所以状态胶囊走 `RichSpan.highlight`
// 自绘，取色**只有一个入口** —— `dsPill`。
package deepdolphin_linux

import cui.{CanvasWidget, Color, CrossAxisAlignment, FontWeight, HStack, Label, LengthInsets, LengthUnits,
    Panel, Rect, Renderer, RichSpan, RichText, Spacer, SurfaceStyle, VStack, Widget}

// ===========================================================================
// 字体刻度 —— 字号只有这七档，淘汰散值
//
// ⚠ 全仓唯一一套字号表（tokens.cj 里那套 FS_* 死令牌已删）。
// 视图写 `.fontSize(fsBody())` 这样的裸字面量就是另立刻度 —— 散值一律收进来。
// Markdown 渲染器的 `mdHeadingSize` 是照抄 macOS 端的独立映射，不算散值。
// ===========================================================================

public func fsDisplay(): Float32 { return 22.0 }   // 大号数值（KPI / 统计卡 / 内联统计）与仪表盘页头
public func fsTitle(): Float32 { return 17.0 }     // 页标题 / 详情页头项目名
public func fsSection(): Float32 { return 15.0 }   // 区块标题
public func fsCard(): Float32 { return 13.0 }      // 卡片标题 / 卡内行标题
public func fsBody(): Float32 { return 12.0 }      // 正文
public func fsLabel(): Float32 { return 11.0 }     // 次要标注
public func fsMicro(): Float32 { return 10.0 }     // 徽标 / 披露

// ===========================================================================
// 语义胶囊 —— 状态与标签的唯一构造点
// ===========================================================================

/// 胶囊的**底色**。语义色在浅色底上要淡，否则正文字会糊在底里。
/// 当前色板的边框色。
public func dsBorderOf(dark: Bool): Int64 {
    return (if (dark) { BORDER_DARK } else { BORDER_LIGHT })
}

public func dsPillBg(accent: Int64, dark: Bool): Color {
    let c = dsColor(accent)
    return (if (dark) { c.withAlpha(38) } else { c.withAlpha(30) })
}

/// 状态胶囊。**颜色只从 `dsStatusColor` 来**，不在调用点写字面量。
///
/// ⚠ 文字走 `dsTextColor` 而不是原色：胶囊底是原色@alpha 铺出来的浅底，
/// 高明度的黄/橙原字压在上面同样不够对比（黄原色对它自己的胶囊底只有
/// ≈1.8:1）。底色仍是原色 —— 状态由底色承担，文字只保证读得清。
public func dsPill(text: String, accent: Int64, dark: Bool): Widget {
    return RichText([
        RichSpan.text(text, color: dsColor(dsTextColor(accent, dark))).highlight(dsPillBg(accent, dark))
            .fontSize(fsMicro()).bold()
    ])
}

/// 状态胶囊：引擎的原始状态字符串直接进来，内部走 `dsStatusFrom`。
///
/// 未知字符串落 `.unknown`（灰），于是界面上出现「状态未知」而不是一片绿。
/// 不猜是这里最重要的一件事。
public func dsStatusPill(raw: String, dark: Bool): Widget {
    let s = dsStatusFrom(raw)
    return dsPill(dsStatusLabel(s), dsStatusColor(s), dark)
}

/// 数值量级胶囊。用在 KPI 卡与「未提交 / 未跟踪 / stash」这类计数上。
public func dsStatPill(n: Int64, dark: Bool): Widget {
    let s = dsStatFrom(n)
    return dsPill(dsStatLabel(s), dsStatColor(s), dark)
}

/// 数值量级的一句话。屏幕阅读器与「只想读一行」的时候用这个。
public func dsStatLine(n: Int64, what: String): String {
    return dsStatDescribe(n, what)
}

/// 双轨胶囊。浅=绿、深=紫 —— 设计稿最突出的那对颜色。
public func dsTrackPill(t: DsTrack, dark: Bool): Widget {
    return dsPill(dsTrackLabel(t), dsTrackColor(t), dark)
}

// ===========================================================================
// 状态点
// ===========================================================================

/// 状态点。8pt 的点没有文字替代，所以紧挨着它的行**必须**有中文状态名。
public func dsStatusDot(raw: String): Widget {
    return dsDot(dsColor(dsStatusColor(dsStatusFrom(raw))))
}

/// 纯色圆点。给图例与统计卡用。
public func dsDot(color: Color): Widget {
    // `hug()` 必须排在 `width`/`height` 前面：它返回 `Panel`，
    // 而后两个是 `Widget` 基类修饰符、返回 `Widget`，先调了就调不上了。
    return Panel { }
        .style(SurfaceStyle(color, radius: Float32(99.0)))
        .contentPadding(0.vp)
        .hug()
        .width(8.vp)
        .height(8.vp)
}

// ===========================================================================
// 统计卡
// ===========================================================================

/// 统计卡：大号数值 + 小号标注。数值按语义着色。
///
/// ⚠ 数值**不是**永远用强调色。「读取失败 3」用强调蓝是错的 ——
/// 失败是异常，该是红/琥珀；用蓝色等于把异常说成常态。
/// 所以 tint 由调用方按**这个数字的含义**给，不由本函数猜。
public func dsStatCard(label: String, value: String, tint: Int64, dark: Bool): Widget {
    return Panel {
        VStack {
            RichText([
                RichSpan.text(value, color: dsColor(tint)).fontSize(fsDisplay()).bold()
            ])
            Label(label).fontSize(fsLabel()).muted()
        }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(12.vp, 10.vp).flex()
}

/// 统计卡的另一种摆法：数值与标注同一行。省垂直空间，
/// 用于「概览」页那种一排七八个的小格子。
public func dsInlineStat(label: String, value: String, tint: Int64): Widget {
    return VStack {
        RichText([RichSpan.text(value, color: dsColor(tint)).fontSize(fsDisplay()).bold()])
        Label(label).fontSize(fsMicro()).muted()
    }.spacing(1.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
}

// ===========================================================================
// 分段比例条
// ===========================================================================

/// 一段：标签 + 数值 + 颜色序号。**颜色由序号决定**，调用点不传颜色 ——
/// 传颜色就会出现「提交构成卡和语言分布卡各调各的」这个病。
public struct DsPart {
    public let label: String
    public let value: Int64
    public let slot: Int64
    public let note: String

    public init(label: String, value: Int64, slot!: Int64 = 0, note!: String = "") {
        this.label = label
        this.value = value
        this.slot = slot
        this.note = note
    }
}

/// 分段比例条（提交构成 / 语言分布共用）。
///
/// ⚠ 段与段之间留 2vp 的缝。这不是为了好看 —— **是为了让两段同色时仍然可分**。
/// 色板 12 档在真实数据里可能出现两次撞色（深浅两档同色系），
/// 没有缝就是一根纯色条，读者会以为只有一类。
/// 颜色唯一性由判据盯着，这里只管把缝画出来。
public func dsSegBar(parts: Array<DsPart>): Widget {
    return CanvasWidget({renderer: Renderer, rect: Rect =>
        var total: Int64 = 0
        for (p in parts) {
            total += p.value
        }
        if (total <= 0) {
            return
        }
        let radius = Float32(R_CHIP)
        let gap: Float32 = 2.0
        var x = rect.x
        for (p in parts) {
            let full = rect.w * Float32(p.value) / Float32(total)
            let w = max(1.0, full - gap)
            if (x + w > rect.x) {
                renderer.fillRoundedRect(Rect(x, rect.y, min(w, rect.x + rect.w - x), rect.h), radius,
                    dsColor(dsSequenceColor(p.slot)))
            }
            x += full
        }
    }).height(10.vp)
}

/// 单值迷你条。用于「待合入 N / 分支 M」这种绝对量。
/// 满量程 `full` 显式传，因为「10 条待合入」和「3 条待合入」不能画得一样长。
public func dsMiniBar(value: Int64, full: Int64, color: Int64, dark: Bool): Widget {
    return CanvasWidget({renderer: Renderer, rect: Rect =>
        let radius = Float32(R_CHIP)
        // 轨道必须画出来：没有轨道，读者不知道这一条是「画满了」还是「只有这么长」。
        let track = dsBorderOf(dark)
        renderer.fillRoundedRect(rect, radius, dsColor(track))
        if (value > 0) {
            let top = max(1, full)
            let w = rect.w * Float32(min(value, top)) / Float32(top)
            renderer.fillRoundedRect(Rect(rect.x, rect.y, w, rect.h), radius, dsColor(color))
        }
    }).height(6.vp)
}

/// 比例版小条（0.0–1.0）。里程碑完成率用这个 ——
/// 它是**比例**不是计数，拿 `dsMiniBar(3, 4, …)` 去表达"75%"是绕路，
/// 而且分母 0 时那条 `max(1, full)` 会把 0/0 画成满格。
public func dsMiniBarRatio(ratio: Float64, color: Int64, dark: Bool): Widget {
    return CanvasWidget({renderer: Renderer, rect: Rect =>
        let radius = Float32(R_CHIP)
        renderer.fillRoundedRect(rect, radius, dsColor(dsBorderOf(dark)))
        // 夹到 0..1：比例算错时宁可画空也不要画出反方向的条。
        let r = max(0.0, min(1.0, ratio))
        if (r > 0.0) {
            let w = rect.w * Float32(r)
            renderer.fillRoundedRect(Rect(rect.x, rect.y, w, rect.h), radius, dsColor(color))
        }
    }).height(6.vp)
}

// ===========================================================================
// 图例
// ===========================================================================

/// 图例行：色点 + 名称 + 数量 + 占比。
///
/// 名字与色点**必须成对出现**。色点自己不说话，
/// 拿两张卡对照时读者是按颜色配的，不是按位置配的。
public func dsLegendRow(p: DsPart, total: Int64): Widget {
    let pct = (if (total > 0) { p.value * 100 / total } else { 0 })
    return HStack {
        dsDot(dsColor(dsSequenceColor(p.slot)))
        Label(p.label).fontSize(fsBody())
        if (!p.note.isEmpty()) {
            Label(p.note).fontSize(fsMicro()).muted()
        }
        Spacer()
        Label("${p.value}").fontSize(fsBody())
        Label("${pct}%").fontSize(fsMicro()).muted().width(38.vp)
    }.spacing(6.vp).hug()
}

// ===========================================================================
// 卡片骨架
// ===========================================================================

/// 区块标题 + 一条分隔线。所有内容卡都用它开头，位置与字重统一。
public func dsCardTitle(text: String): Widget {
    return Label(text).fontSize(fsCard()).fontWeight(FontWeight.semiBold)
}

/// 区块标题 + 右侧的补充说明。右侧说明不是装饰：
/// 「已截断 / 读不出 / 引擎警告」这类披露都挂在这里，不塞进正文里混着。
public func dsCardTitleRow(text: String, note: String, noteColor: Int64): Widget {
    return HStack {
        dsCardTitle(text)
        Spacer()
        if (!note.isEmpty()) {
            Label(note).fontSize(fsMicro()).foregroundColor(dsColor(noteColor))
        }
    }.spacing(8.vp).hug()
}

/// 内容卡的标准外壳：外层卡片表面 + 内边距 + 纵向节奏。
public func dsCard(body: () -> Unit, dark: Bool, pad!: Float64 = 16.0): Widget {
    return Panel { VStack { body() }.spacing(8.vp) }
        .style(dsSurface(DsLevel.Card, dark))
        .contentPadding(pad.vp)
        .flex()
}

/// 卡内嵌套块。比主卡暗一档，让「主卡里的一小块」在视觉上退后一层。
public func dsNested(body: () -> Unit, dark: Bool): Widget {
    return Panel { VStack { body() }.spacing(6.vp) }
        .style(dsSurface(DsLevel.Nested, dark))
        .contentPadding(10.vp)
        .hug()
}

/// 空态。文案分三层：发生了什么 / 为什么 / 下一步。
/// 只有一行「暂无数据」的空态，用户既不知道是空还是坏，也不知道该干什么。
public func dsEmptyState(title: String, why: String, dark: Bool): Widget {
    return Panel {
        VStack {
            Label(title).fontSize(fsSection()).fontWeight(FontWeight.semiBold)
            if (!why.isEmpty()) {
                Label(why).fontSize(fsBody()).muted().wrap()
            }
        }.spacing(6.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.style(dsSurface(DsLevel.Card, dark)).contentPadding(24.vp).flex()
}

// ===========================================================================
// 告警胶囊 —— 与「状态胶囊」严格分开
// ===========================================================================

/// 告警级别。**不是** `DsStatus`。
///
/// 两者混用过一次，症状是：失败面板标题挂出来一个灰色「状态未知」胶囊。
/// 原因是我把中文词「异常」喂给了 `dsStatusFrom` —— 那个函数的词表是
/// **引擎的状态词**（active/idle/stale/merged/dirty），中文根本不在里面，
/// 于是走了 Unknown 分支变成灰色。
///
/// 后果不小：整块失败面板的标题是灰的，看起来像「一条普通的提示」，
/// 而实际是「3 个项目读不到」。颜色在这里是**唯一**的严重度信号。
public enum DsAlert {
    | Info
    | Warn
    | Error
}

public func dsAlertColor(a: DsAlert): Int64 {
    match (a) {
        case DsAlert.Info => return C_ACCENT
        case DsAlert.Warn => return C_ORANGE
        case DsAlert.Error => return C_RED
    }
}

public func dsAlertPill(text: String, level: DsAlert, dark: Bool): Widget {
    return dsPill(text, dsAlertColor(level), dark)
}

// ===========================================================================
// 内边距助手
// ===========================================================================

/// 四边内边距。
///
/// ⚠ 为什么需要这个助手：CUI 的 `contentPadding` 只有
/// `(all)` / `(horizontal, vertical)` / `(Insets)` 三种形式，**没有**四参位置写法；
/// 而 `padding` 的四参是**具名**的（`left:/top:/right:/bottom:`），
/// 位置传四个会被当成 `Insets` 的一个参数而报
/// "expected 1 argument, found 4"。两套签名混着写很容易踩。
public func insets(top: Float64, right: Float64, bottom: Float64, left: Float64): LengthInsets {
    return LengthInsets(top: top.vp, right: right.vp, bottom: bottom.vp, left: left.vp)
}

/// 只上下留白（多用于贴在容器边上的行）。
public func padY(v: Float64): LengthInsets {
    return LengthInsets(top: v.vp, right: 0.0.vp, bottom: v.vp, left: 0.0.vp)
}
