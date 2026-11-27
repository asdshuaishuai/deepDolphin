// ColorSampleSheet.cpp — 状态色样张（批 R）。
//
// 【纪律】本文件**不许**出现任何色值字面量 —— 颜色一律从判定层取：
//   · liveness 档   → Derived::livenessColor()
//   · 分支状态档     → Derived::branchStatusColor()
//   · 托盘专用陈旧红 → logic/SemColors::stale()
//   · 固定色         → logic/SemColors::FixedColors
//   · 表面/文字色    → ui/DesignTokens
// 写成字面量 = 第二份定义 = D2 散值门会红（这是有意的）。
#include "ColorSampleSheet.h"

#include "../logic/Derived.h"
#include "../logic/Liveness.h"
#include "../logic/SemColors.h"
#include "DesignTokens.h"

#include <QFont>
#include <QPainter>
#include <QPainterPath>

namespace {
/// 样张里的档位标签（**样张专用**的语义名，不是产品文案 ——
/// 产品文案另有出处：`StatusDot::statusTip` / `Derived::stateWord`）。
QString livenessName(Liveness l)
{
    switch (l) {
    case Liveness::unreadable:
        return QStringLiteral("unreadable · 采集失败");
    case Liveness::notGit:
        return QStringLiteral("notGit · 非 git 目录");
    case Liveness::needsAction:
        return QStringLiteral("needsAction · 有未提交改动");
    case Liveness::engineStale:
        return QStringLiteral("engineStale · 引擎判定停滞");
    case Liveness::quiet:
        return QStringLiteral("quiet · 30 天以上没有新提交");
    case Liveness::recent:
        return QStringLiteral("recent · 正常");
    case Liveness::unknown:
        break;
    }
    return QStringLiteral("unknown · 提交时间读不出来");
}
} // namespace

ColorSampleSheet::ColorSampleSheet(QWidget *parent)
    : QWidget(parent)
{
    setFixedSize(sizeHint());
    setAutoFillBackground(true);
    QPalette pal = palette();
    pal.setColor(QPalette::Window, DS::surfaceCard());
    setPalette(pal);
}

void ColorSampleSheet::drawRow(QPainter &p, int y, const QColor &c, const QString &name, const QString &note)
{
    // 色块
    QPainterPath block;
    block.addRoundedRect(QRectF(24, y, 28, 28), 6, 6);
    p.fillPath(block, c);
    p.setPen(QPen(DS::surfaceBorder(), 1));
    p.drawPath(block);

    // 档位名
    p.setPen(DS::textPrimary());
    p.setFont(DS::font(DS::FontT::body));
    p.drawText(QRectF(66, y + 2, 420, 16), Qt::AlignLeft | Qt::AlignVCenter, name);

    // 色值 + 说明
    p.setPen(DS::textSecondary());
    p.setFont(DS::font(DS::FontT::label));
    p.drawText(QRectF(500, y + 2, 90, 16), Qt::AlignLeft | Qt::AlignVCenter, c.name().toUpper());
    p.drawText(QRectF(600, y + 2, 280, 16), Qt::AlignLeft | Qt::AlignVCenter, note);
}

void ColorSampleSheet::paintEvent(QPaintEvent *event)
{
    Q_UNUSED(event);
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing);
    p.fillRect(rect(), DS::surfaceCard());

    int y = 20;

    // 标题
    p.setPen(DS::textPrimary());
    p.setFont(DS::font(DS::FontT::cardTitle));
    p.drawText(QRectF(24, y, 600, 24), Qt::AlignLeft | Qt::AlignVCenter,
        QStringLiteral("状态语义色样张（批 R 定案 · 对齐 mac 活代码）"));
    y += 34;

    // ── Liveness（项目活跃度）──
    p.setPen(DS::textSecondary());
    p.setFont(DS::font(DS::FontT::sectionTitle));
    p.drawText(QRectF(24, y, 600, 20), Qt::AlignLeft | Qt::AlignVCenter,
        QStringLiteral("Liveness · 项目活跃度（7 档 · UI 层口径：有状态词，颜色只做辅助）"));
    y += 26;
    for (Liveness l : Derived::livenessKinds()) {
        drawRow(p, y, Derived::livenessColor(l), livenessName(l), QString());
        y += 34;
    }
    y += 10;

    // ── 分支状态（引擎产出的档位）──
    p.setPen(DS::textSecondary());
    p.setFont(DS::font(DS::FontT::sectionTitle));
    p.drawText(QRectF(24, y, 600, 20), Qt::AlignLeft | Qt::AlignVCenter,
        QStringLiteral("分支状态 · 引擎 computeBranchStatus（5 档）"));
    y += 26;
    for (const QString &kind : Derived::branchStatusKinds()) {
        drawRow(p, y, Derived::branchStatusColor(kind), kind, QString());
        y += 34;
    }
    y += 10;

    // ── 托盘专用档 + 固定色 ──
    p.setPen(DS::textSecondary());
    p.setFont(DS::font(DS::FontT::sectionTitle));
    p.drawText(QRectF(24, y, 700, 20), Qt::AlignLeft | Qt::AlignVCenter,
        QStringLiteral("托盘专用档与固定色（托盘图标无文字 → 颜色是唯一信号）"));
    y += 26;
    drawRow(p, y, SemColors::stale(), QStringLiteral("stale · 托盘「停滞」告警"),
        QStringLiteral("仅托盘用：UI 层不挂这一档"));
    y += 34;
    drawRow(p, y, FixedColors::iconFallback(), QStringLiteral("iconFallback · 图标 tint 兜底灰"),
        QString());
    y += 34;
    drawRow(p, y, FixedColors::trayAccent(), QStringLiteral("trayAccent · 托盘强调蓝"), QString());
    y += 34;
    drawRow(p, y, FixedColors::trayBarTrack(), QStringLiteral("trayBarTrack · 托盘条底轨"),
        QStringLiteral("灰 60/255 · 与分段条底轨 40/255 同语义不同档"));
}
