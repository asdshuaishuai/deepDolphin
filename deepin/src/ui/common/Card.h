// Card.h — 卡片表面（mac DSLevel 对位）。圆角 10/6/3，表面接 DTK 调色板。
// 无 Q_OBJECT：无信号，纯呈现（避免无谓的 moc 开销）。
#pragma once
#include "../DesignTokens.h"
#include <QFrame>
#include <QMargins>
#include <QPainter>
#include <QPainterPath>

class Card : public QFrame {
public:
    enum class Level { card, nested, inset };

    // 卡片统一内边距（M3-6 间距单点：水平 lg、垂直 md）。原先 12 处手工复制
    // （ProjectDetailPage 7、DashboardPage 4、ProjectProgressCard 1）。
    // 注意：widget 边距与卡上布局的默认边距会**叠加**（offscreen 实证：fusion
    // 顶层布局默认 11px）——卡上布局一律 setContentsMargins(0,0,0,0)，内距交给这里。
    static constexpr QMargins kPadding{ DS::Spacing::lg, DS::Spacing::md, DS::Spacing::lg,
        DS::Spacing::md };

    explicit Card(QWidget *parent = nullptr, Level level = Level::card)
        : QFrame(parent)
        , m_level(level)
    {
        setAttribute(Qt::WA_StyledBackground, false);
        setContentsMargins(kPadding); // M3-6：构造即设置，调用点不再各写一份
    }

    // 例外口：历史上未显式设内距的卡（现仅 docs 失败/空态两张）内容布局走样式
    // 默认边距，kPadding 会叠出双份内距——退回原状，维持观感零变化。
    void clearPadding()
    {
        setContentsMargins(QMargins());
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
