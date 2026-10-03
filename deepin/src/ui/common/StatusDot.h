// StatusDot.h — 状态圆点（五态：红橙绿灰黄；未知一律落灰，不许默认绿）。
// 无 Q_OBJECT：纯呈现。
#pragma once
#include "../../logic/Derived.h"
#include "../../logic/Liveness.h"
#include "../DesignTokens.h"
#include <QPainter>
#include <QWidget>

class StatusDot : public QWidget {
public:
    explicit StatusDot(QWidget *parent = nullptr)
        : QWidget(parent)
    {
        setFixedSize(DS::Height::dot, DS::Height::dot); // 状态点统一 8px（M3-5，原 10 自成一档）
        setLiveness(Liveness::unknown);
    }

    void setLiveness(Liveness l)
    {
        m_color = Derived::livenessColor(l);
        setToolTip(statusTip(l));
        update();
    }

    void setColor(const QColor &c)
    {
        m_color = c;
        update();
    }

protected:
    void paintEvent(QPaintEvent *event) override
    {
        Q_UNUSED(event);
        QPainter p(this);
        p.setRenderHint(QPainter::Antialiasing);
        p.setPen(Qt::NoPen);
        p.setBrush(m_color);
        p.drawEllipse(rect().adjusted(0, 0, -1, -1));
    }

private:
    static QString statusTip(Liveness l)
    {
        switch (l) {
        case Liveness::unreadable:
            return QStringLiteral("采集失败");
        case Liveness::notGit:
            return QStringLiteral("非 git 目录");
        case Liveness::needsAction:
            return QStringLiteral("有未提交改动");
        case Liveness::engineStale:
            return QStringLiteral("停滞");
        case Liveness::quiet:
            return QStringLiteral("30 天以上没有新提交");
        case Liveness::recent:
            return QStringLiteral("正常");
        case Liveness::unknown:
            break;
        }
        return QStringLiteral("状态读不出来");
    }

    QColor m_color = DS::semColor(DS::SemColor::gray);
};
