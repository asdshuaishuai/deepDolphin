#include "GraphToken.h"

#include <QRegularExpression>

namespace GraphToken {

QColor violationColor()
{
    return QColor(255, 0, 204); // 洋红：引擎违约的显式信号
}

namespace {

// mac 的实现：node:<id> → view.nodeTheme[id] → 再解析一次（这次不传 view）。
// 查不到 → 回落 "text"（图上没有这个节点，不是引擎违约）。
Resolved resolveNode(const GraphThemeTokens &theme, const QString &token, const GraphView *view)
{
    const QString id = token.mid(QStringLiteral("node:").size());
    if (view) {
        const auto it = view->nodeTheme.constFind(id);
        if (it != view->nodeTheme.constEnd())
            return resolve(theme, it.value(), nullptr);
    }
    return resolve(theme, QStringLiteral("text"), nullptr);
}

Resolved resolvePlain(const GraphThemeTokens &theme, const QString &token)
{
    // ② cols.N / fills.N —— 下标越界不静默，落到下面的「未知 token → 洋红」。
    if (token.startsWith(QStringLiteral("cols."))) {
        bool ok = false;
        const int i = token.mid(5).toInt(&ok);
        if (ok && i >= 0 && i < theme.cols.size())
            return { theme.cols.at(i), false };
    } else if (token.startsWith(QStringLiteral("fills."))) {
        bool ok = false;
        const int i = token.mid(6).toInt(&ok);
        if (ok && i >= 0 && i < theme.fills.size())
            return { theme.fills.at(i), false };
    } else if (token.startsWith(QStringLiteral("langs."))) {
        const QString lang = token.mid(6);
        const auto it = theme.langs.constFind(lang);
        if (it != theme.langs.constEnd())
            return { it.value(), false };
        // 语言色查不到 → 回落 text（不是洋红：这是「目录里没这门语言」）。
        return resolve(theme, QStringLiteral("text"), nullptr);
    }
    // ① 直取
    const auto it = theme.simple.constFind(token);
    if (it != theme.simple.constEnd())
        return { it.value(), false };
    // 未知 token = 引擎违约 → 洋红兜底。
    // ⚠ 这里是**固定契约色**，不随主题走（亮/暗都得一眼看出「这是坏 token」），
    //   所以不进 DS 令牌 —— 与 logic/Derived.cpp 的状态色同款写法（RGB 三元组）。
    return { QStringLiteral("rgb(255,0,204)"), true };
}

} // namespace

Resolved resolve(const GraphThemeTokens &theme, const QString &token, const GraphView *view)
{
    if (token.startsWith(QStringLiteral("node:")))
        return resolveNode(theme, token, view);
    return resolvePlain(theme, token);
}

QColor toColor(const QString &hexOrRgba)
{
    const QString t = hexOrRgba.trimmed();
    // rgba(r,g,b,a) 与 rgb(r,g,b) 都收（引擎的 fills 用 rgba，契约兜底色用 rgb）。
    if (t.startsWith(QStringLiteral("rgba")) || t.startsWith(QStringLiteral("rgb"))) {
        static const QRegularExpression re(
            QStringLiteral("rgba?\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*(?:,\\s*([0-9.]+)\\s*)?\\)"));
        const QRegularExpressionMatch m = re.match(t);
        if (m.hasMatch()) {
            QColor c;
            c.setRedF(m.captured(1).toDouble() / 255.0);
            c.setGreenF(m.captured(2).toDouble() / 255.0);
            c.setBlueF(m.captured(3).toDouble() / 255.0);
            c.setAlphaF(m.captured(4).isEmpty() ? 1.0 : m.captured(4).toDouble());
            return c;
        }
        return violationColor();
    }
    QString hex = t;
    if (hex.startsWith(QStringLiteral("#")))
        hex = hex.mid(1);
    if (hex.size() == 3) {
        // #RGB → #RRGGBB
        const QString r = QString(hex.at(0));
        const QString g = QString(hex.at(1));
        const QString b = QString(hex.at(2));
        hex = r + r + g + g + b + b;
    }
    if (hex.size() != 6 && hex.size() != 8)
        return violationColor();
    bool ok = false;
    const uint v = hex.left(6).toUInt(&ok, 16);
    if (!ok)
        return violationColor();
    QColor c;
    c.setRgb(v);
    if (hex.size() == 8) {
        bool aok = false;
        const uint a = hex.mid(6, 2).toUInt(&aok, 16);
        if (aok)
            c.setAlpha(a);
    }
    return c;
}

QColor color(const GraphThemeTokens &theme, const QString &token, const GraphView *view)
{
    const Resolved r = resolve(theme, token, view);
    return toColor(r.value);
}

} // namespace GraphToken
