#include "HeatmapWidget.h"

#include "../logic/CodeGraphBuild.h"
#include "../platform/Canvas2D.h"
#include "DesignTokens.h"

#include <QMouseEvent>
#include <QPainter>
#include <QTimer>
#include <QtMath>
#include <cmath>

namespace {
// 热力图的两种字体（**静态常量**）：原来每张卡片每次重绘都要拼一次
// QStringLiteral("%1pt sans-serif").arg(11) —— 50 张卡 × 30fps = 每秒 6000 次
// QString 分配 + 解析。
// ⚠ 单位是 **pt**（点）—— 浏览器 CSS font 简写认 px 与 pt；早期解析器只认 px，
//   把 "11pt" 当成字体族名吞掉，字号**根本没设上**（渲染成默认字号）。
//   现在由 logic/CanvasFont 按 CSS 口径解析，pt 如实生效。
const QString kFontCard = QStringLiteral("11pt sans-serif");
const QString kFontSub = QStringLiteral("9pt sans-serif");

/// 沿走线取样（mac 的 `CGEdgeRoute.sample`）—— 粒子沿曲线走。
QPointF sampleAt(const HeatLayout::Route &r, double t)
{
    const QVector<QPointF> &pts = r.smoothed;
    if (pts.size() < 2)
        return QPointF();
    double total = 0;
    QVector<double> lens;
    lens << 0;
    for (int i = 1; i < pts.size(); ++i) {
        total += std::hypot(pts.at(i).x() - pts.at(i - 1).x(), pts.at(i).y() - pts.at(i - 1).y());
        lens << total;
    }
    if (total <= 0)
        return pts.first();
    const double target = t * total;
    for (int i = 1; i < pts.size(); ++i) {
        if (lens.at(i) >= target) {
            const double seg = qMax(0.001, lens.at(i) - lens.at(i - 1));
            const double k = (target - lens.at(i - 1)) / seg;
            return QPointF(pts.at(i - 1).x() + (pts.at(i).x() - pts.at(i - 1).x()) * k,
                pts.at(i - 1).y() + (pts.at(i).y() - pts.at(i - 1).y()) * k);
        }
    }
    return pts.last();
}

/// 稳定的字符串哈希（与 HeatLayout 的同款口径：跨平台稳定）。
quint32 stableHash(const QString &s)
{
    quint32 h = 2166136261u;
    for (const QChar c : s) {
        h ^= static_cast<quint32>(c.unicode());
        h *= 16777619u;
    }
    return h;
}

} // namespace

HeatmapWidget::HeatmapWidget(QWidget *parent)
    : QWidget(parent)
{
    setMinimumSize(320, 240);
    m_clock.start();
}

void HeatmapWidget::setData(const CodeGraphBuild::Result *result)
{
    m_result = result;
    m_hues = result ? HeatLayout::huesFor(result->graph) : QHash<QString, int>();
    m_cacheValid = false;
    m_drill = -1;
    m_selected.clear();
    update();
}

void HeatmapWidget::setDrill(int nodeIdx)
{
    if (m_drill == nodeIdx)
        return;
    m_drill = nodeIdx;
    m_cacheValid = false;
    emit drillChanged(m_drill);
    update();
}

void HeatmapWidget::setSelected(const QString &id)
{
    if (m_selected == id)
        return;
    m_selected = id;
    update();
}

void HeatmapWidget::rebuild()
{
    m_cards.clear();
    m_routes.clear();
    m_cardById.clear();
    if (!m_result)
        return;
    const CodeGraph &g = m_result->graph;
    QVector<HeatLayout::Edge> symEdges;
    for (const GraphSymEdge &e : m_result->symEdges)
        symEdges << HeatLayout::Edge { e.from, e.to, e.weight, e.tier };

    const QVector<HeatLayout::Card> scope = HeatLayout::scopeCards(
        g, m_hues, m_drill, symEdges);
    const QVector<HeatLayout::Edge> edges = HeatLayout::scopeEdges(
        g, symEdges, m_result->fileEdges, m_drill);
    m_cards = HeatLayout::layout(scope, edges, width(), height());
    m_routes = HeatLayout::routes(m_cards, edges);
    // id → 卡片 索引（随布局一起建；绘制时只读）
    m_cardById.clear();
    m_cardById.reserve(m_cards.size());
    for (const HeatLayout::Card &c : m_cards)
        m_cardById.insert(c.id, &c);

    // 内容高度 = 卡片包围盒（+ 边距）。**按实测算**而不是布局层估的 —— 估不准
    // 就会出现「卡片铺到画布外、又没有滚动条」的情况（仓库一大就复现）。
    double bottom = 0;
    for (const HeatLayout::Card &c : m_cards)
        bottom = qMax(bottom, c.y + c.h);
    const double h = m_cards.isEmpty() ? 240.0 : bottom + 40.0;
    if (!qFuzzyCompare(h, m_contentHeight)) {
        m_contentHeight = h;
        updateGeometry(); // 让外层滚动区按新内容高度给滚动条
    }
}

QSize HeatmapWidget::sizeHint() const
{
    return QSize(360, static_cast<int>(qCeil(m_contentHeight)));
}

QSize HeatmapWidget::minimumSizeHint() const
{
    return QSize(320, static_cast<int>(qCeil(qMax(240.0, m_contentHeight))));
}

void HeatmapWidget::paintEvent(QPaintEvent *event)
{
    Q_UNUSED(event);
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing, true);
    p.setRenderHint(QPainter::TextAntialiasing, true);

    // 缓存判据 = 层级 + 画布尺寸 + 边数（30fps 重绘只重画时变项）。
    // ⚠ 逐项比较成员，**不拼字符串键** —— 拼键本身每帧一次 QString 分配。
    const int edgeCount = m_result ? m_result->symEdges.size() : 0;
    if (!m_cacheValid || m_cacheDrill != m_drill || m_cacheW != width()
        || m_cacheH != height() || m_cacheEdgeCount != edgeCount) {
        rebuild();
        m_cacheDrill = m_drill;
        m_cacheW = width();
        m_cacheH = height();
        m_cacheEdgeCount = edgeCount;
        m_cacheValid = true;
    }

    p.fillRect(rect(), DS::surfaceAlt());
    if (m_cards.isEmpty()) {
        p.setPen(DS::textSecondary());
        p.drawText(rect(), Qt::AlignCenter, QStringLiteral("没有可铺排的节点"));
        return;
    }

    Canvas2D canvas(&p);
    const double now = static_cast<double>(m_clock.elapsed());
    paintRoutes(p, now);
    paintCards(p);
}

void HeatmapWidget::paintRoutes(QPainter &p, double now)
{
    Canvas2D canvas(&p);
    // ⚠ 用**随布局建好的索引**（m_cardById），不在这里每帧重建 QHash ——
    //   50 张卡 = 每帧 50 次哈希插入，30fps 下每秒 1500 次。
    const QHash<QString, const HeatLayout::Card *> &byId = m_cardById;

    for (int i = 0; i < m_routes.size(); ++i) {
        const HeatLayout::Route &r = m_routes.at(i);
        auto ia = byId.constFind(r.from);
        if (ia == byId.constEnd())
            continue;
        const QColor col = HeatLayout::idColor(ia.value()->hue);
        const bool lit = !m_selected.isEmpty()
            && (r.from == m_selected || r.to == m_selected);
        const double fade = (!m_selected.isEmpty() && !lit) ? 0.15 : 1.0;
        const double pulse = 0.5 + 0.5 * std::sin(now * 1.5 + i * 0.73);

        canvas.setStrokeStyle(CanvasPaint(col));
        canvas.setGlobalAlpha(fade * (lit ? 0.92 : 0.42 + pulse * 0.16));
        canvas.setLineWidth(lit ? 2.4 : qMin(2.2, 0.9 + r.w * 0.14 + pulse * 0.25));
        if (r.tier != QLatin1String("resolved"))
            canvas.setLineDash({ 5, 4 });
        else
            canvas.setLineDash({});
        canvas.beginPath();
        for (int k = 0; k < r.smoothed.size(); ++k) {
            const QPointF &pt = r.smoothed.at(k);
            if (k == 0)
                canvas.moveTo(pt.x(), pt.y());
            else
                canvas.lineTo(pt.x(), pt.y());
        }
        canvas.stroke();
        canvas.setLineDash({});
        canvas.setGlobalAlpha(1.0);

        // 箭头（末段方向）
        if (r.smoothed.size() >= 2) {
            const QPointF last = r.smoothed.last();
            const QPointF prev = r.smoothed.at(r.smoothed.size() - 2);
            const double ang = std::atan2(last.y() - prev.y(), last.x() - prev.x());
            canvas.setFillStyle(CanvasPaint(col));
            canvas.setGlobalAlpha(fade * 0.9);
            canvas.beginPath();
            canvas.moveTo(last.x(), last.y());
            canvas.lineTo(last.x() - 7.5 * std::cos(ang - 0.44), last.y() - 7.5 * std::sin(ang - 0.44));
            canvas.lineTo(last.x() - 7.5 * std::cos(ang + 0.44), last.y() - 7.5 * std::sin(ang + 0.44));
            canvas.closePath();
            canvas.fill();
            canvas.setGlobalAlpha(1.0);
        }

        // 粒子：亮头 + 渐淡拖尾（方向一目了然）
        const double tt = std::fmod(now * (0.12 + r.w * 0.02)
                    + double(stableHash(r.from) % 97) / 97.0, 1.0);
        const QPointF head = sampleAt(r, tt);
        const QPointF tail = sampleAt(r, qMax(0.0, tt - 0.045));
        canvas.setStrokeStyle(CanvasPaint(col));
        canvas.setGlobalAlpha(fade * 0.35);
        canvas.setLineWidth(1.6);
        canvas.beginPath();
        canvas.moveTo(tail.x(), tail.y());
        canvas.lineTo(head.x(), head.y());
        canvas.stroke();
        canvas.setFillStyle(CanvasPaint(col));
        canvas.setGlobalAlpha(fade * 0.6 + pulse * 0.15);
        canvas.beginPath();
        canvas.arc(head.x(), head.y(), 2.2, 0, 2 * M_PI, false);
        canvas.fill();
        canvas.setFillStyle(CanvasPaint(HeatLayout::Canvas::stroke()));
        canvas.setGlobalAlpha(fade * 0.8);
        canvas.beginPath();
        canvas.arc(head.x(), head.y(), 0.9, 0, 2 * M_PI, false);
        canvas.fill();
        canvas.setGlobalAlpha(1.0);
    }
}

void HeatmapWidget::paintCards(QPainter &p)
{
    Canvas2D canvas(&p);
    for (const HeatLayout::Card &c : m_cards) {
        const int score = HeatLayout::confScore(c.penalty, 1);
        const QColor col = HeatLayout::heatColor(score);
        const QColor idCol = HeatLayout::idColor(c.hue);
        const bool isSelected = c.id == m_selected;
        const double phase = (c.hue + c.rank) * 0.11;
        const double pulse = 0.5 + 0.5 * std::sin(static_cast<double>(m_clock.elapsed()) * 1.9 + phase);
        const bool hasFindings = c.penalty > 0;

        // 焦点退淡：选中了别的卡 → 非邻居退淡
        bool dim = false;
        if (!m_selected.isEmpty() && m_selected != c.id && m_result) {
            dim = true;
            for (const GraphSymEdge &e : m_result->symEdges) {
                if ((e.from == c.id && e.to == m_selected) || (e.to == c.id && e.from == m_selected)
                    || (e.from == m_selected && e.to == c.id) || (e.to == m_selected && e.from == c.id)) {
                    dim = false;
                    break;
                }
            }
            for (const GraphFileEdge &e : m_result->fileEdges) {
                const QString fid = QStringLiteral("f:") + e.from;
                const QString tid = QStringLiteral("f:") + e.to;
                if ((fid == c.id && tid == m_selected) || (tid == c.id && fid == m_selected)) {
                    dim = false;
                    break;
                }
            }
        }

        const double alpha = (dim ? 0.45 : 1.0);
        const double heatAlpha = (score < 60 ? 0.20 : (score < 80 ? 0.16 : 0.12)) + pulse * 0.05;

        // 卡底 + 热色沉积
        canvas.setFillStyle(CanvasPaint(HeatLayout::Canvas::cardBase()));
        canvas.setGlobalAlpha(alpha);
        canvas.beginPath();
        canvas.arcTo(c.x, c.y, c.x + c.w, c.y, 10);
        canvas.arcTo(c.x + c.w, c.y, c.x + c.w, c.y + c.h, 10);
        canvas.arcTo(c.x + c.w, c.y + c.h, c.x, c.y + c.h, 10);
        canvas.arcTo(c.x, c.y + c.h, c.x, c.y, 10);
        canvas.closePath();
        canvas.fill();
        canvas.setFillStyle(CanvasPaint(col));
        canvas.setGlobalAlpha(alpha * heatAlpha);
        canvas.fill();
        canvas.setGlobalAlpha(1.0);

        // 边框
        canvas.setStrokeStyle(CanvasPaint(hasFindings || isSelected ? col : HeatLayout::Canvas::stroke()));
        canvas.setGlobalAlpha(alpha * (hasFindings ? 0.45 + pulse * 0.2 : 0.14 + pulse * 0.06));
        canvas.setLineWidth(isSelected ? 2 : (hasFindings ? 1.3 : 1.15));
        canvas.stroke();
        canvas.setGlobalAlpha(1.0);

        // 左侧色条：身份色（边色 = 来源节点色相，故卡上给一条同色条）
        canvas.setFillStyle(CanvasPaint(idCol));
        canvas.setGlobalAlpha(alpha * 0.85);
        canvas.beginPath();
        canvas.rect(c.x + 6, c.y + 10, 3, c.h - 20);
        canvas.fill();
        canvas.setGlobalAlpha(1.0);

        // 名称 + 序号
        canvas.setFillStyle(CanvasPaint(HeatLayout::Canvas::cardText()));
        canvas.setFont(kFontCard);
        canvas.setTextAlign(QStringLiteral("left"));
        canvas.fillText(QStringLiteral("%1. %2").arg(c.rank).arg(c.name), c.x + 14,
            c.y + 22);
        if (c.boundary) {
            canvas.setFillStyle(CanvasPaint(HeatLayout::Canvas::cardNote()));
            canvas.setFont(kFontSub);
            canvas.fillText(QStringLiteral("跨作用域引用"), c.x + 14, c.y + 38);
        } else if (c.kind == GraphNodeKind::file) {
            canvas.setFillStyle(CanvasPaint(HeatLayout::Canvas::cardLabel()));
            canvas.setFont(kFontSub);
            canvas.fillText(QStringLiteral("文件"), c.x + 14, c.y + 38);
        } else {
            canvas.setFillStyle(CanvasPaint(HeatLayout::Canvas::cardLabel()));
            canvas.setFont(kFontSub);
            canvas.fillText(QStringLiteral("符号"), c.x + 14, c.y + 38);
        }

        // 底部置信度米条
        canvas.setFillStyle(CanvasPaint(HeatLayout::Canvas::stroke()));
        canvas.setGlobalAlpha(alpha * 0.10);
        canvas.beginPath();
        canvas.rect(c.x + 13, c.y + c.h - 10, c.w - 26, 3);
        canvas.fill();
        canvas.setFillStyle(CanvasPaint(col));
        canvas.setGlobalAlpha(alpha);
        canvas.beginPath();
        canvas.rect(c.x + 13, c.y + c.h - 10, qMax(1.0, (c.w - 26) * score / 100.0), 3);
        canvas.fill();
        canvas.setGlobalAlpha(1.0);

        // 选中环
        if (isSelected) {
            canvas.setStrokeStyle(CanvasPaint(col));
            canvas.setGlobalAlpha(0.35 + pulse * 0.3);
            canvas.setLineWidth(1);
            canvas.beginPath();
            canvas.arcTo(c.x + 2.5, c.y + 2.5, c.x + c.w - 2.5, c.y + 2.5, 8);
            canvas.arcTo(c.x + c.w - 2.5, c.y + 2.5, c.x + c.w - 2.5, c.y + c.h - 2.5, 8);
            canvas.arcTo(c.x + c.w - 2.5, c.y + c.h - 2.5, c.x + 2.5, c.y + c.h - 2.5, 8);
            canvas.arcTo(c.x + 2.5, c.y + c.h - 2.5, c.x + 2.5, c.y + 2.5, 8);
            canvas.closePath();
            canvas.stroke();
            canvas.setGlobalAlpha(1.0);
        }
    }
}

const HeatLayout::Card *HeatmapWidget::cardAt(double x, double y) const
{
    // 倒序找（后画的在上层）
    for (int i = m_cards.size() - 1; i >= 0; --i) {
        const HeatLayout::Card &c = m_cards.at(i);
        if (c.boundary)
            continue; // 边界卡不可点（mac 同款）
        if (x >= c.x && x <= c.x + c.w && y >= c.y && y <= c.y + c.h)
            return &c;
    }
    return nullptr;
}

void HeatmapWidget::mousePressEvent(QMouseEvent *event)
{
    if (event->button() != Qt::LeftButton) {
        QWidget::mousePressEvent(event);
        return;
    }
    const HeatLayout::Card *c = cardAt(event->position().x(), event->position().y());
    if (!c) {
        QWidget::mousePressEvent(event);
        return;
    }
    if (c->kind == GraphNodeKind::file) {
        // 点文件 → 下钻到符号层
        setDrill(c->node);
        return;
    }
    // 点符号 → 选中（→ 右栏详情）
    m_selected = c->id;
    emit nodeSelected(c->node);
    update();
}

void HeatmapWidget::mouseDoubleClickEvent(QMouseEvent *event)
{
    Q_UNUSED(event);
    // 双击文件卡 → 下钻；双击符号卡 → 选中（单击已做，这里不重复）
}

void HeatmapWidget::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    m_cacheValid = false; // 尺寸变了 → 布局要重算
}

void HeatmapWidget::showEvent(QShowEvent *event)
{
    QWidget::showEvent(event);
    if (!m_anim) {
        m_anim = new QTimer(this);
        m_anim->setInterval(33); // ~30fps
        connect(m_anim, &QTimer::timeout, this, [this] { update(); });
    }
    m_anim->start();
}

void HeatmapWidget::hideEvent(QHideEvent *event)
{
    QWidget::hideEvent(event);
    if (m_anim)
        m_anim->stop(); // 不可见时不转动画时钟
}
