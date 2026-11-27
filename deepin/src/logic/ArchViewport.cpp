#include "ArchViewport.h"

#include <QtMath>

namespace ArchViewport {

Viewport fit(const GraphView &v, double width, double height, double pad)
{
    Viewport vp;
    const double w = v.bx1 - v.bx0;
    const double h = v.by1 - v.by0;
    if (width <= 1.0 || height <= 1.0)
        return vp;
    if (w <= 0.0 || h <= 0.0)
        return vp; // 包围盒非法（空视图）：给恒等视口，不猜比例
    double scale = qMin((width - pad * 2) / w, (height - pad * 2) / h);
    scale = qBound(0.05, scale, 4.0);
    const double cx = (v.bx0 + v.bx1) / 2.0;
    const double cy = (v.by0 + v.by1) / 2.0;
    vp.scale = scale;
    vp.offsetX = width / 2.0 - cx * scale;
    vp.offsetY = height / 2.0 - cy * scale;
    return vp;
}

QPointF toWorld(const Viewport &vp, double screenX, double screenY)
{
    if (vp.scale <= 0.0)
        return QPointF(screenX, screenY);
    return QPointF((screenX - vp.offsetX) / vp.scale, (screenY - vp.offsetY) / vp.scale);
}

QPointF toScreen(const Viewport &vp, double worldX, double worldY)
{
    return QPointF(worldX * vp.scale + vp.offsetX, worldY * vp.scale + vp.offsetY);
}

std::optional<QString> hitAt(const GraphView &v, const Viewport &vp, double screenX, double screenY)
{
    const QPointF w = toWorld(vp, screenX, screenY);
    for (const GraphHit &h : v.hits) {
        if (h.id.isEmpty())
            continue;
        if (w.x() >= h.x && w.x() <= h.x + h.w && w.y() >= h.y && w.y() <= h.y + h.h)
            return h.id;
    }
    return std::nullopt;
}

} // namespace ArchViewport
