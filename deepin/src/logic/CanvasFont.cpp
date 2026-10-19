#include "CanvasFont.h"

#include <QRegularExpression>

namespace CanvasFont {

Spec parse(const QString &fontSpec)
{
    Spec spec;
    const QStringList parts = fontSpec.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    int idx = 0;

    // ── 字重（可选）：100..900 的数字 ──
    if (idx < parts.size()) {
        bool ok = false;
        const int w = parts.at(idx).toInt(&ok);
        if (ok && w >= 100 && w <= 900) {
            spec.weight = w;
            spec.hasWeight = true;
            ++idx;
        }
    }

    // ── 字号（可选）：数字 + 单位 ──
    // ⚠ 单位**只认 px 与 pt**（浏览器 CSS font 简写口径）。
    //   不认的单位（如 "11em"）整段当字体族名 —— 那是调用方的笔误，
    //   但**不能悄悄当成别的单位**（那会让字号与预期差一截还看不出来）。
    if (idx < parts.size()) {
        QString s = parts.at(idx);
        static const QRegularExpression pxRe(QStringLiteral("^([0-9]*\\.?[0-9]+)px$"),
            QRegularExpression::CaseInsensitiveOption);
        static const QRegularExpression ptRe(QStringLiteral("^([0-9]*\\.?[0-9]+)pt$"),
            QRegularExpression::CaseInsensitiveOption);
        QRegularExpressionMatch m = pxRe.match(s);
        if (m.hasMatch()) {
            spec.pixelSize = qRound(m.captured(1).toDouble());
            ++idx;
        } else {
            m = ptRe.match(s);
            if (m.hasMatch()) {
                spec.pointSize = m.captured(1).toDouble();
                ++idx;
            }
        }
    }

    // ── 字体族（其余各段）──
    for (; idx < parts.size(); ++idx)
        spec.families << parts.at(idx);

    return spec;
}

} // namespace CanvasFont
