#include "ArchCanvasWidget.h"

#include "DesignTokens.h"
#include "../platform/Canvas2D.h"
#include "../logic/SceneRender.h"

#include <QMouseEvent>
#include <QPainter>
#include <QTimer>
#include <QWheelEvent>

ArchCanvasWidget::ArchCanvasWidget(QWidget *parent)
    : QWidget(parent)
{
    setMinimumSize(480, 320);
    setMouseTracking(false);
    setAutoFillBackground(false);
    m_dark = DS::isDarkTheme();
    m_clock.start();
}

const GraphView *ArchCanvasWidget::currentView() const
{
    if (!m_scene.has_value())
        return nullptr;
    const GraphView *v = m_scene->view(m_currentView);
    if (v)
        return v;
    // 兜底：指定视图不存在 → 回 arch（契约里 arch 恒在）
    return m_scene->view(QStringLiteral("arch"));
}

QStringList ArchCanvasWidget::viewIds() const
{
    QStringList ids;
    if (!m_scene.has_value())
        return ids;
    for (const GraphView &v : m_scene->views)
        ids << v.id;
    return ids;
}

QString ArchCanvasWidget::currentViewLabel() const
{
    const GraphView *v = currentView();
    if (!v)
        return QStringLiteral("arch");
    return v->label.isEmpty() ? v->id : v->label;
}

bool ArchCanvasWidget::setCurrentView(const QString &id)
{
    if (!m_scene.has_value() || !m_scene->hasView(id))
        return false; // 视图不存在 → 拒绝，不静默换到别的视图
    m_currentView = id;
    m_selected.clear();
    m_userAdjusted = false;
    refit();
    emit nodeSelected(QString());
    return true;
}

void ArchCanvasWidget::setScene(const std::optional<GraphScene> &scene)
{
    m_scene = scene;
    m_userAdjusted = false;
    m_selected.clear();
    // 场景换了一份 → 视图**保留**（新场景仍有该视图时），没有才回 arch
    //（契约里 arch 恒在；旧视图 id 可能已不存在）。
    if (!m_scene.has_value() || !m_scene->hasView(m_currentView))
        m_currentView = QStringLiteral("arch");
    refit();
    ensureAnimTimer();
    update();
}

void ArchCanvasWidget::setDark(bool dark)
{
    if (m_dark == dark)
        return;
    m_dark = dark;
    update();
}

void ArchCanvasWidget::refit()
{
    const GraphView *v = currentView();
    if (!v)
        return;
    m_vp = ArchViewport::fit(*v, width(), height());
    m_userAdjusted = false;
    update();
}

void ArchCanvasWidget::ensureAnimTimer()
{
    // 场景自带流动粒子与流光虚线 → 需要持续重绘。
    // 动画时钟**可见性暂停**：窗口不可见时不转（mac 的性能审计同款纪律）。
    if (!m_scene.has_value())
        return;
    if (!m_anim) {
        m_anim = new QTimer(this);
        m_anim->setInterval(33); // ~30fps
        connect(m_anim, &QTimer::timeout, this, [this] { update(); });
    }
    if (isVisible())
        m_anim->start();
}

void ArchCanvasWidget::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing, true);
    p.setRenderHint(QPainter::TextAntialiasing, true);

    const GraphView *v = currentView();
    if (!v) {
        p.fillRect(rect(), DS::surfaceAlt());
        p.setPen(DS::textSecondary());
        p.drawText(rect(), Qt::AlignCenter, QStringLiteral("没有架构图数据"));
        return;
    }
    Canvas2D canvas(&p);
    SceneRender::render(*m_scene, *v, m_dark, m_vp, width(), height(),
        static_cast<double>(m_clock.elapsed()), canvas);
}

void ArchCanvasWidget::mousePressEvent(QMouseEvent *event)
{
    if (event->button() != Qt::LeftButton) {
        QWidget::mousePressEvent(event);
        return;
    }
    // 左键：先记下拖动起点 —— 移动超过阈值才算拖动（否则点选会被拖动吃掉）
    m_dragging = false;
    m_dragOrigin = event->position();
    m_dragOffset = QPointF(m_vp.offsetX, m_vp.offsetY);
}

void ArchCanvasWidget::mouseMoveEvent(QMouseEvent *event)
{
    if (!(event->buttons() & Qt::LeftButton) || !m_scene.has_value()) {
        QWidget::mouseMoveEvent(event);
        return;
    }
    const QPointF pos = event->position();
    // 拖动阈值：超过 3px 才认作拖动（mac DragGesture 的最小位移同款意图）
    if (!m_dragging && (pos - m_dragOrigin).manhattanLength() < 3.0)
        return;
    m_dragging = true;
    m_vp.offsetX = m_dragOffset.x() + (pos.x() - m_dragOrigin.x());
    m_vp.offsetY = m_dragOffset.y() + (pos.y() - m_dragOrigin.y());
    m_userAdjusted = true;
    update();
}

void ArchCanvasWidget::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() != Qt::LeftButton) {
        QWidget::mouseReleaseEvent(event);
        return;
    }
    const bool wasDragging = m_dragging;
    m_dragging = false;
    if (wasDragging) {
        event->accept();
        return;
    }
    const GraphView *v = currentView();
    if (!v) {
        QWidget::mouseReleaseEvent(event);
        return;
    }
    // 点选：命中同一个节点再点一次 = 取消选择（mac 同款）
    const auto id = ArchViewport::hitAt(*v, m_vp, event->position().x(), event->position().y());
    m_selected = (id.has_value() && id.value() == m_selected) ? QString() : id.value_or(QString());
    emit nodeSelected(m_selected);
}

void ArchCanvasWidget::wheelEvent(QWheelEvent *event)
{
    // 滚轮缩放（以光标为锚）：世界坐标在光标下保持不动。
    const double factor = event->angleDelta().y() > 0 ? 1.12 : 1.0 / 1.12;
    double scale = m_vp.scale * factor;
    scale = qBound(0.05, scale, 4.0);
    const QPointF anchor = event->position();
    const QPointF world = ArchViewport::toWorld(m_vp, anchor.x(), anchor.y());
    m_vp.scale = scale;
    m_vp.offsetX = anchor.x() - world.x() * scale;
    m_vp.offsetY = anchor.y() - world.y() * scale;
    m_userAdjusted = true;
    update();
    event->accept();
}

void ArchCanvasWidget::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    if (!m_userAdjusted)
        refit();
}

void ArchCanvasWidget::showEvent(QShowEvent *event)
{
    QWidget::showEvent(event);
    ensureAnimTimer();
}

void ArchCanvasWidget::hideEvent(QHideEvent *event)
{
    QWidget::hideEvent(event);
    if (m_anim)
        m_anim->stop(); // 不可见时不转动画时钟
}
