// SegmentedBar.h — 堆叠分段条（自绘 paintEvent；chip 圆角；段数由调用方切片保证 ≤ 色板容量）。
// 无 Q_OBJECT：纯呈现。
#pragma once
#include "../DesignTokens.h"
#include <QColor>
#include <QPair>
#include <QPainter>
#include <QPainterPath>
#include <QWidget>
#include <QVector>

class SegmentedBar : public QWidget {
public:
    explicit SegmentedBar(QWidget *parent = nullptr)
        : QWidget(parent)
    {
        setFixedHeight(DS::Height::bar); // M3-5：与 DProgressBar 同高（原 8 自成一档）
        setRadius(DS::Radius::chip);
    }

    void setRadius(int r) { m_radius = r; }

    void setData(const QVector<QPair<QColor, int>> &rows)
    {
        m_rows = rows;
        update();
        setVisible(!rows.isEmpty());
    }

protected:
    void paintEvent(QPaintEvent *event) override
    {
        Q_UNUSED(event);
        QPainter p(this);
        p.setRenderHint(QPainter::Antialiasing);
        const qreal total = totalCount();
        QPainterPath clip;
        clip.addRoundedRect(rect(), m_radius, m_radius);
        p.setClipPath(clip);
        // 底轨（无数据时也可见，不画成消失）
        p.fillRect(rect(), QColor(128, 128, 128, 40));
        qreal x = 0;
        for (const auto &row : m_rows) {
            if (row.second <= 0)
                continue;
            const qreal w = static_cast<qreal>(width()) * row.second / total;
            p.fillRect(QRectF(x, 0, w + 0.5, height()), row.first);
            x += w;
        }
    }

private:
    qreal totalCount() const
    {
        qreal t = 0;
        for (const auto &r : m_rows)
            t += qMax(0, r.second);
        return t > 0 ? t : 1;
    }

    QVector<QPair<QColor, int>> m_rows;
    int m_radius = DS::Radius::chip;
};
