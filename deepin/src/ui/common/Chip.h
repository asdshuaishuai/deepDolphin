// Chip.h — 状态词/chip（`●N` 橙、tag✓ 绿等）。tone 决定底色与文字色（同源，不取模）。
// 无 Q_OBJECT：纯呈现。
#pragma once
#include "../DesignTokens.h"
#include <QLabel>
#include <QPalette>

class Chip : public QLabel {
public:
    explicit Chip(QWidget *parent = nullptr)
        : QLabel(parent)
    {
        apply();
    }

    explicit Chip(const QString &text, QWidget *parent = nullptr)
        : QLabel(text, parent)
    {
        apply();
    }

    void setTone(DS::SemColor tone)
    {
        m_tone = tone;
        apply();
    }

    // 第二文案（QLabel::setText 语义清晰版，供两态切换用）。
    void setText2(const QString &t)
    {
        setText(t);
        setVisible(!t.isEmpty());
    }

private:
    void apply()
    {
        const QColor c = DS::semColor(m_tone);
        QColor bg = c;
        bg.setAlpha(32);
        setStyleSheet(QStringLiteral("QLabel { color: %1; background: %2; border-radius: %3px;"
                                     " padding: 1px 6px; font-size: 11px; }")
                          .arg(c.name(), bg.name())
                          .arg(DS::Radius::chip));
    }

    DS::SemColor m_tone = DS::SemColor::gray;
};
