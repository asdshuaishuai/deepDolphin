// deepDolphin Linux 客户端 —— 字体装配。
//
// ## 为什么需要这一层
//
// CUI 在 macOS 上用 `CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 15, NULL)`
// 取系统 UI 字体，拿到的是 SF / Helvetica —— **一个字形的中文都没有**。
// 而 SDL_ttf（FreeType）**不做字形回退**：找不到的字形直接给 .notdef，
// 于是界面上每个汉字都变成豆腐块。
//
// macOS 系统本身是靠 CoreText 的级联回退（PingFang）把中文显示出来的，
// 但那一层在 SDL_ttf 底下，不在 CUI 走的这条路径上。
// 这就是为什么「系统明明装了中文字体，窗口里却全是方块」。
//
// ⇒ 必须**显式**注册一个含 CJK 字形的字体文件当默认字族。
//
// ## 什么时候调用
//
// 必须在**第一帧之前**，也就是 `DesktopApp(...)` 之前。
// CUI 的字体初始化与首次布局绘制都发生在窗口还隐藏的时候，
// 之后再换字族要靠重建全部文本布局，代价大得多。
package deepdolphin_linux

import std.collection.*

import cui.{FontFamily, FontSource, Fonts}

/// 注册后使用的字族名。随便起的，只要不与系统族名撞。
private let APP_FAMILY = "deepDolphinUI"

/// 含 CJK 字形的候选字体，按偏好排序。
///
/// 只列**确定含 CJK 覆盖**的文件。这里不猜「装了应该有」——
/// 猜错的后果是注册了一个拉丁字体，豆腐块照旧，而用户完全看不出哪里错了。
func cjkFontCandidates(): Array<String> {
    [
        // macOS：冬青黑体简体中文 / 华文黑体。PingFang 在新版 macOS 上
        // 不再以独立 .ttc 出现在 /System/Library/Fonts，故不在列。
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/System/Library/Fonts/AppleSDGothicNeo.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
        // Linux：Noto CJK → 文泉驿 → 文鼎 → Android 回退字体
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
        "/usr/share/fonts/truetype/arphic/uming.ttc",
        "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
        // Windows：微软雅黑 → 宋体
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/msyh.ttf",
        "C:/Windows/Fonts/simsun.ttc"
    ]
}

/// 主字体之后的回退链：拉丁、等宽、emoji。
///
/// CJK 字体通常也带拉丁字形，但字形风格未必好看；
/// 显式挂上系统拉丁/等宽字体，英文与数字会用它们渲染。
func fallbackFontCandidates(): Array<String> {
    [
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/Apple Color Emoji.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
        "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/consola.ttf",
        "C:/Windows/Fonts/seguiemj.ttf"
    ]
}

/// 从候选里挑第一个真实存在的文件。
///
/// 「存在」用注入的判定函数，而不是直接 `exists` ——
/// 这样这条选择规则能脱离文件系统单测（见 model_test.cj）。
///
/// 挑**第一个**而不是最后一个：候选表已按偏好排序，
/// 「找到就用后面更好的那个」等于把顺序写反。
public func pickFontFile(candidates: Array<String>, present: (String) -> Bool): Option<String> {
    for (path in candidates) {
        if (present(path)) {
            return Some(path)
        }
    }
    return None
}

private func filePresent(path: String): Bool {
    isRegularFile(path)
}

/// 装配应用字体。返回一句能直接显示给用户的说明。
///
/// 找不到 CJK 字体时**必须说出来**：返回非空的问题串，
/// 由界面显示在状态条上。静默继续 = 用户对着满屏豆腐块而界面说「一切正常」。
public func installAppFonts(): String {
    let cjk = pickFontFile(cjkFontCandidates(), filePresent)
    match (cjk) {
        case None =>
            return "没找到含中文字形的字体，中文会显示成方块。" +
                "macOS: brew install --cask font-noto-sans-cjk；" +
                "Linux: sudo apt install fonts-noto-cjk"
        case Some(primary) =>
            // 回退链：主字体 → 拉丁 → 等宽 → emoji。
            // `cui` 只再导出了 registerFamily(name, FontFamily) 这一个重载，
            // 三参的 (name, path, fallbackPaths) 在 `sdl` 包里才有，
            // 所以这里显式构造 FontFamily —— 顺带把回退顺序写死在代码里，
            // 不依赖调用方传的顺序。
            let fb = ArrayList<FontSource>()
            for (f in pickAllPresent(fallbackFontCandidates(), filePresent)) {
                fb.add(FontSource(f))
            }
            Fonts.registerFamily(APP_FAMILY, FontFamily(FontSource(primary), fallbacks: fb.toArray()))
            Fonts.setDefault(Some(APP_FAMILY))
            return ""
    }
}

/// 收集所有存在的回退字体（主字体后可以挂多个）。
private func pickAllPresent(candidates: Array<String>, present: (String) -> Bool): Array<String> {
    let out = ArrayList<String>()
    for (path in candidates) {
        if (present(path)) {
            out.add(path)
        }
    }
    return out.toArray()
}
