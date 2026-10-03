// FlowLayout.h — 换行流式布局（项目卡网格 2 列 min 300 → 宽度不足自动折行）。
// 改自 Qt horizontal flow layout 示例（简体版：无动画、无高度缓存）。
#pragma once
#include <QLayout>
#include <QRect>
#include <QStyle>
#include <QWidget>

class FlowLayout : public QLayout {
public:
    explicit FlowLayout(QWidget *parent, int margin = 0, int hSpace = 16, int vSpace = 16)
        : QLayout(parent)
        , m_hSpace(hSpace)
        , m_vSpace(vSpace)
    {
        setContentsMargins(margin, margin, margin, margin);
    }

    ~FlowLayout() override
    {
        while (count() > 0)
            delete takeAt(0);
    }

    void addItem(QLayoutItem *item) override { m_items.append(item); }

    int count() const override { return m_items.size(); }

    QLayoutItem *itemAt(int index) const override
    {
        return (index >= 0 && index < m_items.size()) ? m_items.at(index) : nullptr;
    }

    QLayoutItem *takeAt(int index) override
    {
        return (index >= 0 && index < m_items.size()) ? m_items.takeAt(index) : nullptr;
    }

    Qt::Orientations expandingDirections() const override { return {}; }

    bool hasHeightForWidth() const override { return true; }
    int heightForWidth(int w) const override { return doLayout(QRect(0, 0, w, 0), true); }

    void setGeometry(const QRect &rect) override
    {
        QLayout::setGeometry(rect);
        doLayout(rect, false);
    }

    QSize sizeHint() const override { return minimumSize(); }

    QSize minimumSize() const override
    {
        QSize s;
        for (const QLayoutItem *item : m_items)
            s = s.expandedTo(item->minimumSize());
        const QMargins m = contentsMargins();
        s += QSize(m.left() + m.right(), m.top() + m.bottom());
        return s;
    }

    // 每个卡片固定宽（2 列网格语义），由页面调用。
    void setItemFixedWidth(int w)
    {
        m_fixedWidth = w;
        invalidate();
    }

private:
    int doLayout(const QRect &rect, bool testOnly) const
    {
        const QMargins m = contentsMargins();
        const int availW = rect.width() - m.left() - m.right();
        int x = m.left() + rect.x();
        int y = m.top() + rect.y();
        int rowH = 0;
        int maxRight = x;

        for (QLayoutItem *item : m_items) {
            int w = m_fixedWidth > 0 ? m_fixedWidth : item->sizeHint().width();
            w = qMin(w, availW > 0 ? availW : w);
            const int h = item->sizeHint().height();
            if (x + w > rect.right() - m.right() && rowH > 0) {
                x = m.left() + rect.x();
                y += rowH + m_vSpace;
                rowH = 0;
            }
            if (!testOnly)
                item->setGeometry(QRect(QPoint(x, y), QSize(w, h)));
            x += w + m_hSpace;
            maxRight = qMax(maxRight, x);
            rowH = qMax(rowH, h);
        }
        return y + rowH + m.bottom() - rect.y();
    }

    QVector<QLayoutItem *> m_items;
    int m_hSpace;
    int m_vSpace;
    int m_fixedWidth = 0;
};
