// CanvasFont.h — Canvas font 简写的解析（纯函数，零 QWidget 头）。
//
// 【为什么抽出来】
// ① **语义**：Canvas 的 font 简写是**浏览器 CSS font 简写** —— 字号单位
//    `px` 与 `pt` **都认**。早先的解析器只认 `px`（把 `pt` 整段当成**字体族名**
//    吞掉），于是「11pt sans-serif」既没设字号、又塞了个不存在的字体族进去 ——
//    界面看上去「字号不太对」，但没人知道是**单位没被识别**。
//    这违背 CanvasSink 头注释的红线：「语义是浏览器 Canvas2D 的语义，
//    不是『差不多就行』」。
// ② **性能**：30fps 下每帧每张卡片都要 setFont —— 解析（split + QFont 构造 +
//    字体族匹配）不便宜。抽成纯函数后，平台侧可按串**缓存 QFont**。
//
// 【单位口径】
// · `px` → 像素字号（QFont::setPixelSize）
// · `pt` → 点字号（QFont::setPointSizeF，1pt = 1/72 英寸，与 CSS 一致）
// · 两者都缺 → 不设字号（用接收端默认），**不回落成某个具体字号**
#pragma once
#include <QString>
#include <QStringList>

namespace CanvasFont {

/// 解析出来的字体规格。
struct Spec {
    int weight = 400;      ///< 字重（100..900；缺省 400 = Normal）
    bool hasWeight = false;///< 是否**显式**给了字重（缺省 != 显式 Normal）
    int pixelSize = 0;     ///< 像素字号（0 = 未指定；**不是**「0px 字号」）
    double pointSize = 0;  ///< 点字号（0 = 未指定）
    QStringList families;  ///< 字体族（空 = 保留接收端自身字体族）
};

/// 解析 Canvas font 简写（浏览器 CSS font 简写口径）。
///
/// 形态：「[weight ]size[px|pt] [family…]」
/// · weight：100..900 的数字（缺省 400）
/// · size：数字 + 单位（`px` / `pt`；缺单位则**不认**，不回落成别的单位）
/// · family：其余各段（按空格分开）
///
/// 例：`"600 12px"` → weight 600 / pixelSize 12；
///     `"11pt sans-serif"` → pointSize 11 / families ["sans-serif"]；
///     `"600 12px Noto Sans CJK SC"` → families 四段。
Spec parse(const QString &fontSpec);

} // namespace CanvasFont
