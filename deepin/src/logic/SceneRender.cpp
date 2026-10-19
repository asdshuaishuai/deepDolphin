#include "SceneRender.h"

#include <QtMath>
#include <cmath>

#include "GraphToken.h"

namespace SceneRender {

namespace {

struct Pt {
    double x = 0, y = 0;
};

/// 三次贝塞尔求点（粒子沿边流动用；与引擎/Web 驱动的公式同款）。
Pt cubicAt(const Pt &p0, const Pt &c1, const Pt &c2, const Pt &p3, double t)
{
    const double u = 1 - t;
    const double a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
    return { a * p0.x + b * c1.x + c * c2.x + d * p3.x, a * p0.y + b * c1.y + c * c2.y + d * p3.y };
}

/// 圆角矩形路径（Canvas2D 的 arcTo 链，与引擎 Web 驱动的 roundRect 同款）。
void roundRectPath(CanvasSink &s, double x, double y, double w, double h, double r)
{
    r = qMin(r, qMin(w, h) / 2.0);
    s.beginPath();
    s.moveTo(x + r, y);
    s.arcTo(x + w, y, x + w, y + h, r);
    s.arcTo(x + w, y + h, x, y + h, r);
    s.arcTo(x, y + h, x, y, r);
    s.arcTo(x, y, x + w, y, r);
    s.closePath();
}

QString fontString(int weight, double sizePx)
{
    // Canvas font 简写："<weight> <size>px"（family 留空 → 接收端保留自身字体族）。
    return QStringLiteral("%1 %2px").arg(weight).arg(sizePx);
}

} // namespace

Stats render(const GraphScene &scene, const GraphView &view, bool dark,
    const ArchViewport::Viewport &vp, double width, double height, double nowMs, CanvasSink &sink)
{
    Stats st;
    const GraphThemeTokens &theme = dark ? scene.dark : scene.light;

    // token 解析：node: 二跳要查当前视图的 nodeTheme（契约：二跳结果落在前三类）。
    auto token = [&](const QString &name) {
        return GraphToken::color(theme, name, &view);
    };

    auto pt = [&](double x, double y) {
        return Pt { x * vp.scale + vp.offsetX, y * vp.scale + vp.offsetY };
    };

    // 背景
    sink.setFillStyle(CanvasPaint(token(QStringLiteral("bg0"))));
    sink.fillRect(0, 0, width, height);

    for (const GraphShape &sh : view.shapes) {
        ++st.shapes;
        if (sh.type == QLatin1String("frame")) {
            const Pt o = pt(sh.x, sh.y);
            const double w = sh.w * vp.scale;
            const double h = sh.h * vp.scale;
            sink.setStrokeStyle(CanvasPaint(
                token(sh.color.isEmpty() ? QStringLiteral("border") : sh.color)));
            sink.setLineWidth(1.4);
            sink.strokeRect(o.x, o.y, w, h);
            // 层框标题（引擎在 frame 上带 **label** 键；缺 label 不画，不占位）
            if (!sh.label.isEmpty()) {
                sink.setFillStyle(CanvasPaint(token(QStringLiteral("muted"))));
                sink.setFont(fontString(600, 12));
                sink.setTextAlign(QStringLiteral("left"));
                sink.fillText(sh.label, o.x + 12, o.y + 6);
                ++st.texts;
            }
            ++st.drawn;
        } else if (sh.type == QLatin1String("rrect")) {
            const Pt o = pt(sh.x, sh.y);
            const double w = sh.w * vp.scale;
            const double h = sh.h * vp.scale;
            roundRectPath(sink, o.x, o.y, w, h, sh.r * vp.scale);
            sink.setFillStyle(CanvasPaint(
                token(sh.fill.isEmpty() ? QStringLiteral("panel") : sh.fill)));
            sink.fill();
            if (!sh.stroke.isEmpty()) {
                sink.setStrokeStyle(CanvasPaint(token(sh.stroke)));
                sink.setLineWidth(sh.sw > 0 ? sh.sw : 1.0);
                sink.stroke();
            }
            ++st.drawn;
        } else if (sh.type == QLatin1String("rect")) {
            const Pt o = pt(sh.x, sh.y);
            sink.setFillStyle(CanvasPaint(
                token(sh.fill.isEmpty() ? QStringLiteral("accent") : sh.fill)));
            sink.fillRect(o.x, o.y, qMax(sh.w * vp.scale, 1.5), sh.h * vp.scale);
            ++st.drawn;
        } else if (sh.type == QLatin1String("text")) {
            const Pt o = pt(sh.x, sh.y);
            const double size = sh.size > 0 ? sh.size : 12.0;
            const int weight = sh.weight >= 600 ? 600 : 400;
            sink.setFillStyle(CanvasPaint(
                token(sh.color.isEmpty() ? QStringLiteral("text") : sh.color)));
            sink.setFont(fontString(weight, size));
            sink.setTextAlign(sh.align == QLatin1String("center")
                    ? QStringLiteral("center")
                    : QStringLiteral("left"));
            // Canvas2D 的 fillText 的 y 是**基线**（引擎 Web 驱动同款：节点标签 y+22）。
            sink.fillText(sh.text, o.x, o.y);
            ++st.texts;
            ++st.drawn;
        } else if (sh.type == QLatin1String("edge")) {
            if (sh.points.size() < 8) {
                ++st.unknown;
                continue;
            }
            // 入场错峰：delay（毫秒）之前这条边还没开始生长 —— 不画，不算画过。
            if (nowMs - sh.delay < 0) {
                ++st.edgesPending;
                continue;
            }
            const Pt p0 = pt(sh.points.at(0), sh.points.at(1));
            const Pt c1 = pt(sh.points.at(2), sh.points.at(3));
            const Pt c2 = pt(sh.points.at(4), sh.points.at(5));
            const Pt p3 = pt(sh.points.at(6), sh.points.at(7));
            const QColor c0 = token(sh.c0.isEmpty() ? QStringLiteral("arrow") : sh.c0);
            const QColor c1c = token(sh.c1.isEmpty() ? QStringLiteral("arrow") : sh.c1);
            const double alpha = sh.alpha > 0 ? sh.alpha : 0.85;

            sink.beginPath();
            sink.moveTo(p0.x, p0.y);
            sink.bezierCurveTo(c1.x, c1.y, c2.x, c2.y, p3.x, p3.y);
            // 渐变描边：起端色带 alpha，终端色不带（与 Web 驱动同款）
            QLinearGradient *g = sink.createLinearGradient(p0.x, p0.y, p3.x, p3.y);
            if (g) {
                QColor a = c0;
                a.setAlphaF(alpha);
                sink.addColorStop(0.0, a);
                sink.addColorStop(1.0, c1c);
                sink.setStrokeStyle(CanvasPaint(g));
            } else {
                sink.setStrokeStyle(CanvasPaint(c0));
            }
            sink.setLineWidth(qMax(sh.sw * vp.scale, 0.8));
            // 虚线流光：dash 固定 [7,5]，phase 随时间推进（Web 驱动同款节奏）
            sink.setLineDash(QVector<double> { 7.0, 5.0 });
            sink.setLineDashOffset(-std::fmod(nowMs * 26.0, 12.0));
            sink.stroke();
            sink.setLineDash(QVector<double>());

            // 箭头：终点方向的小三角
            const double arrow = qMax(sh.arrow * vp.scale, 4.0);
            double dx = p3.x - c2.x, dy = p3.y - c2.y;
            const double len = qMax(qSqrt(dx * dx + dy * dy), 0.001);
            dx /= len;
            dy /= len;
            const double px = -dy, py = dx;
            sink.beginPath();
            sink.moveTo(p3.x, p3.y);
            sink.lineTo(p3.x - dx * arrow + px * arrow * 0.45, p3.y - dy * arrow + py * arrow * 0.45);
            sink.lineTo(p3.x - dx * arrow - px * arrow * 0.45, p3.y - dy * arrow - py * arrow * 0.45);
            sink.closePath();
            sink.setFillStyle(CanvasPaint(c1c));
            sink.fill();
            ++st.edges;
            ++st.drawn;
        } else {
            // 不认识的 shape 类型 = 引擎违约：**计数披露，不静默跳**。
            ++st.unknown;
        }
    }

    // 流动粒子：相位 (i+1)/(n+1)，零随机（引擎保证两次导出一致）。
    for (const GraphParticle &g : view.particles) {
        if (g.p.size() < 8)
            continue;
        const Pt p0 { g.p.at(0), g.p.at(1) };
        const Pt c1 { g.p.at(2), g.p.at(3) };
        const Pt c2 { g.p.at(4), g.p.at(5) };
        const Pt p3 { g.p.at(6), g.p.at(7) };
        const QColor pc = token(g.color.isEmpty() ? QStringLiteral("accent") : g.color);
        const int n = qMax(g.n, 0);
        for (int i = 0; i < n; ++i) {
            const double phase = static_cast<double>(i + 1) / static_cast<double>(n + 1);
            double t = std::fmod(phase + nowMs * g.sp * 1000.0, 1.0);
            if (t < 0)
                t += 1.0;
            const Pt pos = cubicAt(p0, c1, c2, p3, t);
            const double radius = qMax(2.2 * vp.scale, 1.2);
            QColor c = pc;
            c.setAlphaF(0.9);
            sink.setFillStyle(CanvasPaint(c));
            sink.beginPath();
            sink.arc(pos.x, pos.y, radius, 0.0, 2 * M_PI, false);
            sink.fill();
            ++st.particles;
        }
    }

    return st;
}

} // namespace SceneRender
