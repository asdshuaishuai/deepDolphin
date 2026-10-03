// DesignTokens.cpp — 设计 tokens（mac DesignTokens.swift/DesignSystem.swift → DTK 映射）。
//
// 【映射纪律（PLAN §8 T1/T2）】
// · 表面/文字色**接 DTK 调色板**（DGuiApplicationHelper::applicationPalette，亮暗自适应）
//   ——它们是皮肤，用户改系统主题/强调色时必须跟着变；
// · **语义色保留 mac 取值**（shallow/deep/ai/orange/red/yellow/gray）：它们承载跨页一致的
//   状态语义，不是皮肤；accent 例外——它接 DTK 的 LightLively（DSuggestButton 等 DTK
//   控件的强调底色），这样原生控件与我们的强调色永远同色；
// · 字号接 DFontManager 档位（T1..T11，T5=14/T6=12/T7=11/T8=10），用户在控制中心放大
//   字号时全应用一起放大——不再各自 setPixelSize；
// · 间距 6 档 + 圆角 3 档（chip=3/control=6/card=10）逐值对齐 mac DSSpacing/DSRadius；
// · 12 色序列色板在 logic/CommitTypeComposition（容量外不取模，越界返回无效 QColor）。
//
// 【实证边界（本仓 README 决策 13 同源，2026-10-03 offscreen 探针复测）】
// `standardPalette()` 的 DPalette 扩展角色（ItemBackground/TextTitle/TextTips/FrameBorder）
// 在没有 DTK 样式插件的环境里都是 #ffffff/#000000 —— **不能用**。可用的是：
//   · QPalette 标准角色（Window/Base/Text/Mid）——两个环境都对；
//   · DPalette::PlaceholderText（提示文字，浅 #555555 / 深 #C0C6D4）；
//   · DPalette::LightLively（DTK 推荐按钮底色，浅 #0081FF / 深 #0059D2）。
// 取不到值（isValid 检查失败）时退回 deepin 官方视觉规范值，绝不静默变白。
#include "DesignTokens.h"
#include <DGuiApplicationHelper>
#include <DFontManager>
#include <QGuiApplication>
#include <QLabel>
#include <QPalette>
#include <DPalette>
#include <dtkgui_global.h>

DGUI_USE_NAMESPACE

namespace DS {

namespace {
// 生效主题：DEEPDOLPHIN_THEME=light|dark 强制（offscreen 探不到系统配置时快照可确定性
// 拍亮/暗），否则跟 DGuiApplicationHelper 的系统主题。
DGuiApplicationHelper::ColorType effectiveTheme()
{
    const QString env = qEnvironmentVariable("DEEPDOLPHIN_THEME");
    if (env.compare(QLatin1String("light"), Qt::CaseInsensitive) == 0)
        return DGuiApplicationHelper::LightType;
    if (env.compare(QLatin1String("dark"), Qt::CaseInsensitive) == 0)
        return DGuiApplicationHelper::DarkType;
    return DGuiApplicationHelper::instance()->themeType();
}

QColor themed(const char *light, const char *dark)
{
    return QColor(effectiveTheme() == DGuiApplicationHelper::DarkType ? dark : light);
}

// 从运行期调色板取色；调色板与主题不自洽时退回 deepin 视觉规范值。
// 这就是"接 DTK 生态"与"渲染不塌"之间唯一的一处握手。
QColor paletteRole(QPalette::ColorRole role, const char *light, const char *dark)
{
    if (paletteIsThemeConsistent()) {
        const QColor c = DGuiApplicationHelper::instance()->applicationPalette().color(
            QPalette::Active, role);
        if (c.isValid() && c.alpha() > 0)
            return c;
    }
    return themed(light, dark);
}

QColor paletteRole(DPalette::ColorType role, const char *light, const char *dark)
{
    if (paletteIsThemeConsistent()) {
        const QColor c = DGuiApplicationHelper::instance()->applicationPalette().color(
            QPalette::Active, role);
        if (c.isValid() && c.alpha() > 0)
            return c;
    }
    return themed(light, dark);
}
} // namespace

// 运行期调色板与当前主题是否自洽（用 Window 角色的明度当"它站在哪个主题"的判据）。
// 不自洽时一律不许用它的值——暗色主题拿到浅色调色板 = 白底黑字。
bool paletteIsThemeConsistent()
{
    const QColor window = DGuiApplicationHelper::instance()->applicationPalette().color(
        QPalette::Active, QPalette::Window);
    if (!window.isValid() || window.alpha() == 0)
        return false;
    const bool dark = effectiveTheme() == DGuiApplicationHelper::DarkType;
    return dark ? window.lightness() < 128 : window.lightness() >= 128;
}

QColor semColor(SemColor c)
{
    switch (c) {
    case SemColor::accent:
        // accent = DTK 推荐按钮底色（LightLively）——与 DSuggestButton/DPushButton 的
        // 原生强调色同源，不再另立门户；取不到退回 deepin 规范强调蓝。
        return paletteRole(DPalette::LightLively, "#0081ff", "#3b9eff");
    case SemColor::shallow:
        return QColor(0x10, 0xB9, 0x81);
    case SemColor::deep:
        return QColor(0x8B, 0x5C, 0xF6);
    case SemColor::ai:
        return QColor(0x06, 0xB6, 0xD4);
    case SemColor::orange:
        return QColor(0xF5, 0x9E, 0x0B);
    case SemColor::red:
        return QColor(0xDC, 0x26, 0x26);
    case SemColor::yellow:
        return QColor(0xE8, 0xB0, 0x1C);
    case SemColor::gray:
        break;
    }
    return QColor(0x9C, 0xA3, 0xAF);
}

bool isDarkTheme()
{
    return effectiveTheme() == DGuiApplicationHelper::DarkType;
}

// 无 DTK 配置环境（offscreen/无样式插件）的一整套应用调色板——**只由 DS:: 值构造**，
// 与各页面从 DS:: 取的表面/文字色同源，不会出现"侧栏浅、内容深"的缝合体。
QPalette applicationPaletteFallback()
{
    const bool dark = isDarkTheme();
    const QColor window = surfaceAlt();
    const QColor base = surfaceCard();
    const QColor text = textPrimary();
    const QColor mid = textSecondary();
    const QColor border = surfaceBorder();
    QPalette pal;
    pal.setColor(QPalette::Window, window);
    pal.setColor(QPalette::WindowText, text);
    pal.setColor(QPalette::Base, base);
    pal.setColor(QPalette::AlternateBase, window);
    pal.setColor(QPalette::Text, text);
    pal.setColor(QPalette::Button, base);
    pal.setColor(QPalette::ButtonText, text);
    pal.setColor(QPalette::ToolTipBase, base);
    pal.setColor(QPalette::ToolTipText, text);
    pal.setColor(QPalette::Mid, border);
    pal.setColor(QPalette::Midlight, dark ? border.lighter(120) : QColor(Qt::white));
    pal.setColor(QPalette::Light, dark ? border.lighter(140) : QColor(Qt::white));
    pal.setColor(QPalette::Dark, border.darker(140));
    pal.setColor(QPalette::Highlight, semColor(SemColor::accent));
    pal.setColor(QPalette::HighlightedText, dark ? QColor(Qt::black) : QColor(Qt::white));
    pal.setColor(QPalette::PlaceholderText, mid);
    pal.setColor(QPalette::Disabled, QPalette::WindowText, mid);
    pal.setColor(QPalette::Disabled, QPalette::ButtonText, mid);
    pal.setColor(QPalette::Disabled, QPalette::Text, mid);
    return pal;
}

QColor surfaceCard()
{
    // 卡片表面 = 调色板 Base（浅 #FFFFFF / 深 #282828）
    return paletteRole(QPalette::Base, "#ffffff", "#2d2d2d");
}

QColor surfaceAlt()
{
    // 窗口底 = 调色板 Window（浅 #F8F8F8 / 深 #252525）
    return paletteRole(QPalette::Window, "#f8f8f8", "#252525");
}

QColor surfaceBorder()
{
    // 描边 = 调色板 Mid（浅 #E4E4E4 / 深 #434343）——与 DDE 原生控件同档
    return paletteRole(QPalette::Mid, "#e0e0e0", "#393939");
}

QColor textPrimary()
{
    // 主文字 = 调色板 Text
    return paletteRole(QPalette::Text, "#000000", "#ffffff");
}

QColor textSecondary()
{
    // 次级文字 = DTK 的 PlaceholderText（提示性文本专用角色）
    return paletteRole(DPalette::PlaceholderText, "#808080", "#a6a6a6");
}

QFont font(FontT t){
    const DFontManager *fm = DGuiApplicationHelper::instance()->fontManager();
    const QFont base = QGuiApplication::font();
    // 档位映射（DFontManager 实测：T5=14/T6=12/T7=11/T8=10/T4=18/T3=22）：
    //   metric KPI 大数字 → T4；sectionTitle 页内段题 → T5；cardTitle 卡题 → T6；
    //   body 正文 / label 次要说明 → T7（同档，靠颜色分主次，DDE 惯例）；badge → T8。
    // 控制中心放大字号 → 这些档位一起变，界面随之放大（F1/F2）。
    switch (t) {
    case FontT::metric:
        return fm->get(DFontManager::T4, base);
    case FontT::sectionTitle:
        return fm->get(DFontManager::T5, base);
    case FontT::cardTitle:
        return fm->get(DFontManager::T6, base);
    case FontT::body:
        return fm->get(DFontManager::T7, base);
    case FontT::label:
        return fm->get(DFontManager::T7, base);
    case FontT::badge:
        return fm->get(DFontManager::T8, base);
    }
    return base;
}

// ── 主题/字号变化：登记 + 重算（M3-4）──
// 为什么用 property 而不是遍历时猜：构建期的取值已经固化在 QSS/字号里，唯一能重算的
// 办法是"当初登记过意图"。property("dsSecondary")/property("dsFont") 就是那份意图。
void tagSecondaryStyle(QLabel *label)
{
    if (!label)
        return;
    label->setProperty("dsSecondary", true);
    label->setStyleSheet(QStringLiteral("color: %1;").arg(textSecondary().name()));
}

void tagFont(QWidget *w, FontT t)
{
    if (!w)
        return;
    w->setProperty("dsFont", static_cast<int>(t));
    w->setFont(font(t));
}

void repolish(QWidget *root)
{
    if (!root)
        return;
    const QList<QWidget *> tree = [root] {
        QList<QWidget *> all = root->findChildren<QWidget *>(Qt::FindChildrenRecursively);
        all.prepend(root);
        return all;
    }();
    for (QWidget *w : tree) {
        if (w->property("dsSecondary").toBool()) {
            const QVariant prev = w->property("dsFont"); // 次级标签常同时挂了字号
            if (prev.isValid() && qobject_cast<QLabel *>(w))
                w->setFont(font(static_cast<FontT>(prev.toInt())));
            w->setStyleSheet(QStringLiteral("color: %1;").arg(textSecondary().name()));
            continue;
        }
        const QVariant f = w->property("dsFont");
        if (f.isValid())
            w->setFont(font(static_cast<FontT>(f.toInt())));
    }
    root->ensurePolished();
    root->update();
}

} // namespace DS
