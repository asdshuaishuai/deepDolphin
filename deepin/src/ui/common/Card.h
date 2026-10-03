// Card.h — 卡片表面（mac DSLevel 对位）。圆角 10/6/3，表面接 DTK 调色板。
// 无 Q_OBJECT：无信号，纯呈现（避免无谓的 moc 开销）。
#pragma once
#include "../DesignTokens.h"
#include <QFrame>
#include <QPainter>
#include <QPainterPath>

class Card : public QFrame {
public:
    enum class Level { card, nested, inset };

    explicit Card(QWidget *parent = nullptr, Level level = Level::card)
        : QFrame(parent)
        , m_level(level)
    {
        setAttribute(Qt::WA_StyledBackground, false);
    }

    void setLevel(Level l)
    {
        m_level = l;
        update();
    }

protected:
    void paintEvent(QPaintEvent *event) override
    {
        Q_UNUSED(event);
        QPainter p(this);
        p.setRenderHint(QPainter::Antialiasing);
        QColor fill;
        int radius = DS::Radius::card;
        switch (m_level) {
        case Level::card:
            fill = DS::surfaceCard();
            radius = DS::Radius::card;
            break;
        case Level::nested:
            fill = DS::surfaceAlt();
            radius = DS::Radius::control;
            break;
        case Level::inset:
            fill = DS::surfaceCard();
            fill.setAlpha(153); // surface 60%
            radius = DS::Radius::chip;
            break;
        }
        QPainterPath path;
        path.addRoundedRect(rect().adjusted(0, 0, -1, -1), radius, radius);
        p.fillPath(path, fill);
        p.setPen(QPen(DS::surfaceBorder(), 1));
        p.drawPath(path);
    }

private:
    Level m_level;
};
