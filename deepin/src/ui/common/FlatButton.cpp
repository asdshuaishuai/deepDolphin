#include "FlatButton.h"
#include <QFontMetrics>
#include <QPainter>
#include <QPainterPath>
#include <QStyle>
#include <QStyleOptionButton>

FlatButton::FlatButton(QWidget *parent)
    : QPushButton(parent)
{
    init();
}

FlatButton::FlatButton(const QString &text, QWidget *parent)
    : QPushButton(text, parent)
{
    init();
}

void FlatButton::init()
{
    setFlat(true);                       // 语义（本类接管绘制，flat 只是不再要实底）
    setCursor(Qt::PointingHandCursor);   // 平钮 = 动作入口（原 headerButton 助手口径）
    setAttribute(Qt::WA_Hover, true);    // hover 重绘不依赖样式 polish
    DS::tagFont(this, DS::FontT::body);  // 字号档位 + dsFont 登记（切字号跟随）
}

QColor FlatButton::overlayColor(const QColor &base, Tone tone)
{
    QColor c = base;
    c.setAlpha(tone == Tone::Pressed ? 46 : 26); // ≈18% / ≈10%
    return c;
}

QMargins FlatButton::padding()
{
    return { DS::Spacing::lg, DS::Spacing::xs, DS::Spacing::lg, DS::Spacing::xs };
}

QSize FlatButton::sizeHint() const
{
    const QFontMetrics fm(font());
    const QSize ic = iconSize();
    // 纯图标位：四周 xs 的方块（原 headerButton 文字为空的 copy/finder/term/remote）
    if (text().isEmpty()) {
        const int side = qMax(ic.height(), fm.height());
        return { side + 2 * DS::Spacing::xs, side + 2 * DS::Spacing::xs };
    }
    int w = padding().left() + padding().right() + fm.horizontalAdvance(text());
    int h = padding().top() + padding().bottom() + fm.height();
    if (!icon().isNull()) {
        w += ic.width() + DS::Spacing::xs; // 图标与文字之间一档 xs
        h = qMax(h, padding().top() + padding().bottom() + ic.height());
    }
    return { w, h };
}

QSize FlatButton::minimumSizeHint() const
{
    return sizeHint(); // 平钮不截字：最小即建议
}

void FlatButton::paintEvent(QPaintEvent *event)
{
    Q_UNUSED(event);
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing);

    // hover/pressed 底色：DS::textPrimary 低透明叠加（实时取值，Card.h 范式——
    // 切主题/字号由 DS::repolish 的 update() 自然重刷，无 QSS 快照）
    if (isEnabled() && (underMouse() || isDown())) {
        QPainterPath path;
        const int r = DS::Radius::control;
        path.addRoundedRect(rect().adjusted(0, 0, -1, -1), r, r);
        p.fillPath(path,
            overlayColor(DS::textPrimary(), isDown() ? Tone::Pressed : Tone::Hover));
    }

    // 文字/图标交给样式画（保留禁用灰化与图标布局的样式细节），文字色从 DS:: 取：
    // 启用 = textPrimary、禁用 = textSecondary，不经 QSS（M3-4：颜色注入走 paintEvent）
    QStyleOptionButton opt;
    initStyleOption(&opt);
    opt.palette.setColor(QPalette::ButtonText,
        isEnabled() ? DS::textPrimary() : DS::textSecondary());
    style()->drawControl(QStyle::CE_PushButtonLabel, &opt, &p, this);
    if (opt.state & QStyle::State_HasFocus)
        style()->drawPrimitive(QStyle::PE_FrameFocusRect, &opt, &p, this); // 键盘焦点环
}
