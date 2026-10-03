// LegendRow.h — 图例（与 SegmentedBar 同源色：dot 颜色由调用方传入，不内联第二套色板）。
// 无 Q_OBJECT：纯呈现。
#pragma once
#include "../DesignTokens.h"
#include <QColor>
#include <QPair>
#include <QPainter>
#include <QHBoxLayout>
#include <QLabel>
#include <QWidget>
#include <QVector>

class LegendRow : public QWidget {
public:
    explicit LegendRow(QWidget *parent = nullptr)
        : QWidget(parent)
    {
        m_flow = new QHBoxLayout(this);
        m_flow->setContentsMargins(0, 0, 0, 0);
        m_flow->setSpacing(DS::Spacing::sm);
        m_flow->addStretch(1);
    }

    void setEntries(const QVector<QPair<QColor, QString>> &entries)
    {
        // 重建行（条目随筛选变化）
        while (m_flow->count() > 0) {
            QLayoutItem *it = m_flow->takeAt(0);
            if (it->widget())
                it->widget()->deleteLater();
            delete it;
        }
        for (const auto &e : entries) {
            auto *dot = new QLabel(this);
            dot->setFixedSize(8, 8);
            QPixmap pm(8, 8);
            pm.fill(Qt::transparent);
            QPainter p(&pm);
            p.setRenderHint(QPainter::Antialiasing);
            p.setPen(Qt::NoPen);
            p.setBrush(e.first);
            p.drawEllipse(0, 0, 8, 8);
            dot->setPixmap(pm);
            dot->setToolTip(e.second);
            auto *label = new QLabel(e.second, this);
            label->setFont(DS::font(DS::FontT::label));
            label->setStyleSheet(QStringLiteral("color: %1;").arg(DS::textSecondary().name()));
            auto *cell = new QWidget(this);
            auto *h = new QHBoxLayout(cell);
            h->setContentsMargins(0, 0, 0, 0);
            h->setSpacing(4);
            h->addWidget(dot);
            h->addWidget(label);
            m_flow->addWidget(cell);
        }
        auto *stretch = new QWidget(this);
        stretch->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Preferred);
        m_flow->addWidget(stretch);
        setVisible(!entries.isEmpty());
    }

private:
    QHBoxLayout *m_flow = nullptr;
};
