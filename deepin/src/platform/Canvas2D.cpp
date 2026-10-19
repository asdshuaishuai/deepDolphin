#include "Canvas2D.h"

#include <QFontMetricsF>
#include <QImage>
#include <QtMath>

namespace {

// alpha 盒式模糊（三遍≈高斯）。阴影模拟用：把离屏图的 alpha 通道糊开。
void blurAlpha(QImage &img, int radius)
{
    if (radius <= 0)
        return;
    const int w = img.width();
    const int h = img.height();
    if (w <= 0 || h <= 0)
        return;
    QVector<int> a(w * h);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x)
            a[y * w + x] = qAlpha(img.pixel(x, y));
    }
    QVector<int> tmp(w * h);
    for (int pass = 0; pass < 3; ++pass) {
        // 横向
        for (int y = 0; y < h; ++y) {
            int sum = 0;
            const int *row = a.data() + y * w;
            int *out = tmp.data() + y * w;
            for (int x = -radius; x <= radius; ++x)
                sum += row[qBound(0, x, w - 1)];
            const int n = radius * 2 + 1;
            for (int x = 0; x < w; ++x) {
                out[x] = sum / n;
                const int add = qBound(0, x + radius + 1, w - 1);
                const int sub = qBound(0, x - radius, w - 1);
                sum += row[add] - row[sub];
            }
        }
        // 纵向
        for (int x = 0; x < w; ++x) {
            int sum = 0;
            for (int y = -radius; y <= radius; ++y)
                sum += tmp[qBound(0, y, h - 1) * w + x];
            const int n = radius * 2 + 1;
            for (int y = 0; y < h; ++y) {
                a[y * w + x] = sum / n;
                const int add = qBound(0, y + radius + 1, h - 1);
                const int sub = qBound(0, y - radius, h - 1);
                sum += tmp[add * w + x] - tmp[sub * w + x];
            }
        }
    }
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const int al = a[y * w + x];
            if (al == 0)
                continue;
            QColor c = img.pixelColor(x, y);
            c.setAlpha(al);
            img.setPixelColor(x, y, c);
        }
    }
}

} // namespace

Canvas2D::Canvas2D(QPainter *painter)
    : m_painter(painter)
{
    m_fill.color = QColor(0, 0, 0);
    m_stroke.color = QColor(0, 0, 0);
    m_font = QFont();
    m_font.setPixelSize(12);
}

void Canvas2D::setTransform(double a, double b, double c, double d, double e, double f)
{
    // Qt6 没有 QTransform::setMatrix —— 用构造器直接给矩阵。
    m_painter->setTransform(QTransform(a, b, c, d, e, f));
}

QBrush Canvas2D::fillBrush() const
{
    if (m_fill.gradient && m_fill.grad)
        return QBrush(*m_fill.grad);
    return QBrush(m_fill.color);
}

QPen Canvas2D::strokePen() const
{
    QPen pen;
    if (m_stroke.gradient && m_stroke.grad) {
        pen.setBrush(QBrush(*m_stroke.grad));
    } else {
        pen.setBrush(QBrush(m_stroke.color));
    }
    pen.setWidthF(m_lineWidth);
    pen.setCapStyle(Qt::RoundCap);
    pen.setJoinStyle(Qt::RoundJoin);
    if (!m_dash.isEmpty()) {
        QVector<qreal> pattern;
        for (double d : m_dash)
            pattern << d;
        pen.setDashPattern(pattern);
        pen.setDashOffset(m_dashOffset);
    }
    return pen;
}

void Canvas2D::fillRect(double x, double y, double w, double h)
{
    m_painter->save();
    m_painter->setOpacity(m_globalAlpha);
    withShadow([&](QPainter &p) {
        p.setBrush(fillBrush());
        p.setPen(Qt::NoPen);
        p.fillRect(QRectF(x, y, w, h), fillBrush());
    });
    m_painter->restore();
}

void Canvas2D::strokeRect(double x, double y, double w, double h)
{
    m_painter->save();
    m_painter->setOpacity(m_globalAlpha);
    withShadow([&](QPainter &p) {
        p.setPen(strokePen());
        p.setBrush(Qt::NoBrush);
        p.drawRect(QRectF(x, y, w, h));
    });
    m_painter->restore();
}

void Canvas2D::rect(double x, double y, double w, double h)
{
    m_path.addRect(QRectF(x, y, w, h));
}

void Canvas2D::beginPath()
{
    m_path = QPainterPath();
}

void Canvas2D::moveTo(double x, double y)
{
    m_path.moveTo(x, y);
}

void Canvas2D::lineTo(double x, double y)
{
    m_path.lineTo(x, y);
}

void Canvas2D::arcTo(double x1, double y1, double x2, double y2, double r)
{
    // Canvas2D 的 arcTo：从当前点切到 (x1,y1) 再切到 (x2,y2) 的圆角。
    // ⚠ Qt6 移除了 QPainterPath::arcTo(点,点,半径) 重载 —— 语义自己实现，
    //   不许拿「圆弧 + 直连」凑数（那会让引擎的 roundRect 画出直角）。
    const QPointF p1(x1, y1);
    const QPointF p2(x2, y2);
    const QPointF p0 = m_path.currentPosition();
    if (qFuzzyCompare(p0.x() + 1.0, p1.x() + 1.0) && qFuzzyCompare(p0.y() + 1.0, p1.y() + 1.0))
        return; // 契约：当前点 == 第一点 → 什么都不做
    if (r <= 0.0) {
        m_path.lineTo(p1);
        return;
    }
    const QPointF v1 = p0 - p1;
    const QPointF v2 = p2 - p1;
    const double len1 = std::hypot(v1.x(), v1.y());
    const double len2 = std::hypot(v2.x(), v2.y());
    if (len1 <= 0.0 || len2 <= 0.0) {
        m_path.lineTo(p1);
        return;
    }
    const QPointF u1 = v1 / len1;
    const QPointF u2 = v2 / len2;
    const double dot = qBound(-1.0, QPointF::dotProduct(u1, u2), 1.0);
    const double angle = std::acos(dot); // 两段夹角
    if (angle <= 1e-9) {
        m_path.lineTo(p1); // 共线 → 直线
        return;
    }
    const double cross = u1.x() * u2.y() - u1.y() * u2.x();
    if (qFuzzyIsNull(cross)) {
        m_path.lineTo(p1);
        return;
    }
    // 半径夹取：切线距 t = r / tan(angle/2) 不得超过任一段长
    const double tanHalf = std::tan(angle / 2.0);
    double rr = r;
    double t = rr / tanHalf;
    if (t > len1 || t > len2) {
        t = qMin(len1, len2);
        rr = t * tanHalf;
    }
    // 切点与圆心
    const QPointF pA = p1 + u1 * t;
    const QPointF pB = p1 + u2 * t;
    const QPointF bis = (u1 + u2);
    const double bisLen = std::hypot(bis.x(), bis.y());
    if (bisLen <= 0.0) {
        m_path.lineTo(p1);
        return;
    }
    const QPointF center = p1 + (bis / bisLen) * (rr / std::sin(angle / 2.0));
    const double startDeg = qRadiansToDegrees(std::atan2(pA.y() - center.y(), pA.x() - center.x()));
    // 圆弧张角 = π − 夹角；方向由叉积定（cross>0 → 负角，cross<0 → 正角）
    const double sweepDeg = qRadiansToDegrees(M_PI - angle) * (cross > 0 ? -1.0 : 1.0);
    m_path.arcTo(QRectF(center.x() - rr, center.y() - rr, rr * 2, rr * 2), startDeg, sweepDeg);
}

void Canvas2D::closePath()
{
    m_path.closeSubpath();
}

void Canvas2D::arc(double x, double y, double r, double a0, double a1, bool ccw)
{
    // Canvas 角度是弧度、正方向在屏幕上是顺时针；QPainter 用度数、正方向逆时针。
    // 两者在 y 轴朝下的坐标系下视觉一致，故 sweep 直接取角差，ccw 取负。
    const double startDeg = qRadiansToDegrees(a0);
    double sweepDeg = qRadiansToDegrees(a1 - a0);
    if (ccw)
        sweepDeg = -sweepDeg;
    m_path.arcMoveTo(QRectF(x - r, y - r, r * 2, r * 2), startDeg);
    m_path.arcTo(QRectF(x - r, y - r, r * 2, r * 2), startDeg, sweepDeg);
}

void Canvas2D::bezierCurveTo(double c1x, double c1y, double c2x, double c2y, double x, double y)
{
    m_path.cubicTo(c1x, c1y, c2x, c2y, x, y);
}

void Canvas2D::fill()
{
    m_painter->save();
    m_painter->setOpacity(m_globalAlpha);
    withShadow([&](QPainter &p) {
        p.setPen(Qt::NoPen);
        p.setBrush(fillBrush());
        p.fillPath(m_path, fillBrush());
    });
    m_painter->restore();
}

void Canvas2D::stroke()
{
    m_painter->save();
    m_painter->setOpacity(m_globalAlpha);
    withShadow([&](QPainter &p) {
        p.setPen(strokePen());
        p.setBrush(Qt::NoBrush);
        p.drawPath(m_path); // Qt6 移除了 strokePath —— drawPath + NoBrush 等价
    });
    m_painter->restore();
}

void Canvas2D::fillText(const QString &text, double x, double y)
{
    m_painter->save();
    m_painter->setOpacity(m_globalAlpha);
    m_painter->setFont(m_font);
    m_painter->setPen(m_fill.color);
    const QFontMetricsF fm(m_font);
    double tx = x;
    if (m_textAlign == QLatin1String("center"))
        tx = x - fm.horizontalAdvance(text) / 2.0;
    else if (m_textAlign == QLatin1String("right"))
        tx = x - fm.horizontalAdvance(text);
    // Canvas 的 fillText 的 y 是**基线**；QPainter 的 drawText(QPointF) 同样是基线。
    m_painter->drawText(QPointF(tx, y), text);
    m_painter->restore();
}

QLinearGradient *Canvas2D::createLinearGradient(double x0, double y0, double x1, double y1)
{
    auto *g = new QLinearGradient(QPointF(x0, y0), QPointF(x1, y1));
    m_pendingGradient = g;
    return g;
}

void Canvas2D::addColorStop(double offset, const QColor &c)
{
    if (m_pendingGradient)
        m_pendingGradient->setColorAt(offset, c);
}

void Canvas2D::setLineDash(const QVector<double> &dashes)
{
    m_dash = dashes;
}

void Canvas2D::setLineDashOffset(double offset)
{
    m_dashOffset = offset;
}

void Canvas2D::setShadowBlur(double v)
{
    m_shadowBlur = v;
}

void Canvas2D::setShadowColor(const QColor &c)
{
    m_shadowColor = c;
}

void Canvas2D::setGlobalAlpha(double v)
{
    m_globalAlpha = v;
}

void Canvas2D::setLineWidth(double v)
{
    m_lineWidth = v;
}

void Canvas2D::setStrokeStyle(const CanvasPaint &p)
{
    m_stroke.gradient = p.isGradient();
    m_stroke.color = p.color;
    m_stroke.grad = p.gradient;
}

void Canvas2D::setFillStyle(const CanvasPaint &p)
{
    m_fill.gradient = p.isGradient();
    m_fill.color = p.color;
    m_fill.grad = p.gradient;
}

void Canvas2D::setFont(const QString &f)
{
    // Canvas font 简写："<weight> <size>px <family>"（weight 可省）。
    QFont nf;
    const QStringList parts = f.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    int idx = 0;
    int weight = QFont::Normal;
    bool hasWeight = false;
    if (idx < parts.size()) {
        bool ok = false;
        const int w = parts.at(idx).toInt(&ok);
        if (ok && w >= 100 && w <= 900) {
            weight = w;
            hasWeight = true;
            ++idx;
        }
    }
    double px = 0;
    if (idx < parts.size()) {
        QString s = parts.at(idx);
        if (s.endsWith(QLatin1String("px"), Qt::CaseInsensitive))
            s.chop(2);
        bool ok = false;
        const double v = s.toDouble(&ok);
        if (ok) {
            px = v;
            ++idx;
        }
    }
    if (px > 0)
        nf.setPixelSize(static_cast<int>(px));
    if (hasWeight)
        nf.setWeight(static_cast<QFont::Weight>(weight));
    QStringList fam;
    for (; idx < parts.size(); ++idx)
        fam << parts.at(idx);
    if (!fam.isEmpty())
        nf.setFamilies(fam);
    m_font = nf;
}

void Canvas2D::setTextAlign(const QString &a)
{
    m_textAlign = a;
}

void Canvas2D::withShadow(const std::function<void(QPainter &)> &op)
{
    if (m_shadowBlur <= 0.0 || !m_shadowColor.isValid() || m_shadowColor.alpha() == 0) {
        if (m_painter)
            op(*m_painter);
        return;
    }
    const QPaintDevice *dev = m_painter->device();
    const int devW = dev ? dev->width() : 0;
    const int devH = dev ? dev->height() : 0;
    if (devW <= 0 || devH <= 0)
        return;
    const int radius = qMax(1, static_cast<int>(m_shadowBlur / 2.0));
    const QSize size(devW, devH);

    // 1) 离屏画出形状（用阴影色），拿到 alpha 掩膜。
    QImage mask(size, QImage::Format_ARGB32_Premultiplied);
    mask.fill(Qt::transparent);
    {
        QPainter p(&mask);
        p.setRenderHint(QPainter::Antialiasing, true);
        p.setTransform(m_painter->transform());
        p.setPen(Qt::NoPen);
        p.setBrush(QBrush(m_shadowColor));
        op(p);
    }
    // 2) alpha 模糊（三遍盒式 ≈ 高斯）。
    blurAlpha(mask, radius);
    // 3) 用阴影色着色（保留模糊后的 alpha）。
    QImage shadow(size, QImage::Format_ARGB32_Premultiplied);
    shadow.fill(Qt::transparent);
    {
        QPainter p(&shadow);
        p.drawImage(0, 0, mask);
    }
    // 4) 合成到目标（离屏图已是设备坐标 → 用单位变换贴回）。
    m_painter->save();
    m_painter->resetTransform();
    m_painter->setOpacity(1.0);
    m_painter->drawImage(0, 0, shadow);
    m_painter->restore();
    // 5) 真正画一遍形状（阴影在下，形状在上）。
    op(*m_painter);
}
