// PanelGeometry.cpp — DDE 面板几何判定层（纯函数）。
#include "PanelGeometry.h"

namespace PanelGeometry {

Edge edgeFromPosition(int position)
{
    // dde-shell 的 Position 枚举：0=Top 1=Right 2=Bottom 3=Left。
    switch (position) {
    case 0:
        return Edge::Top;
    case 1:
        return Edge::Right;
    case 2:
        return Edge::Bottom;
    case 3:
        return Edge::Left;
    default:
        break;
    }
    return Edge::Unknown;
}

QString edgeName(Edge edge)
{
    switch (edge) {
    case Edge::Top:
        return QStringLiteral("top");
    case Edge::Right:
        return QStringLiteral("right");
    case Edge::Bottom:
        return QStringLiteral("bottom");
    case Edge::Left:
        return QStringLiteral("left");
    case Edge::Unknown:
        break;
    }
    return QStringLiteral("unknown");
}

namespace {

/// 面板贴着哪条边（位置读不出来时的兜底）。
///
/// ⚠ 按**接触长度**选边，不按「先判上再判下」：
///   · 通栏的底栏：只贴下沿 ⇒ 接触长度 = 屏宽 ⇒ 判「下」；
///   · 通高的侧栏：同时贴三沿（上下左）⇒ 接触长度 = 屏高 ⇒ 判「左」
///     （按固定顺序挑会挑到「上」，把可用区从**底**上扣 ⇒ 错得离谱）。
Edge dominantEdge(const QRect &screen, const QRect &panel)
{
    // 面板与屏幕在两个轴上的重叠长度
    const int hOverlap = qMax(0, qMin(screen.right(), panel.right())
                                   - qMax(screen.left(), panel.left()) + 1);
    const int vOverlap = qMax(0, qMin(screen.bottom(), panel.bottom())
                                   - qMax(screen.top(), panel.top()) + 1);

    struct Candidate {
        Edge edge;
        bool touches;
        int contact;
    };
    const Candidate candidates[] = {
        { Edge::Top, panel.top() <= screen.top() + 1, hOverlap },
        { Edge::Bottom, panel.bottom() >= screen.bottom() - 1, hOverlap },
        { Edge::Left, panel.left() <= screen.left() + 1, vOverlap },
        { Edge::Right, panel.right() >= screen.right() - 1, vOverlap },
    };
    Edge best = Edge::Unknown;
    int bestContact = 0;
    for (const Candidate &c : candidates) {
        if (c.touches && c.contact > bestContact) {
            best = c.edge;
            bestContact = c.contact;
        }
    }
    return best;
}

} // namespace

QRect usableArea(const QRect &screen, const Panel &panel)
{
    if (panel.isEmpty() || screen.isEmpty())
        return screen;

    Edge edge = panel.edge;
    if (edge == Edge::Unknown)
        edge = dominantEdge(screen, panel.rect);
    if (edge == Edge::Unknown)
        return screen; // 猜不出边 ⇒ 不扣（宁可不扣，也不要扣错边）

    QRect out = screen;
    // ⚠ 用 `adjust`（按**差值**挪边）而不是 `setTop/setBottom`（按**绝对值**设边）：
    //   我们扣的是「面板相对屏幕边沿的**差值**」——按差值挪，不会把另一条边带偏。
    //   （实测 Qt6 的 setter 是「设这一条边、另一边不动」⇒ 会**改变**可用区大小；
    //     而 adjust 挪的是边、差值算错时才明显歪。两者在「面板贴着屏边」时等价，
    //     面板**悬空**时就分道扬镳了 —— 实测：面板 (0,1000,1920,41) 悬在 1080 屏里，
    //     正确的可用区是 (0,0,1920,999)（按面板**上沿**），减厚度会算成 (0,0,1920,1039)。）
    switch (edge) {
    case Edge::Top:
        out.adjust(0, (panel.rect.bottom() + 1) - screen.top(), 0, 0);
        break;
    case Edge::Right:
        out.adjust(0, 0, (panel.rect.left() - 1) - screen.right(), 0);
        break;
    case Edge::Bottom:
        out.adjust(0, 0, 0, (panel.rect.top() - 1) - screen.bottom());
        break;
    case Edge::Left:
        out.adjust((panel.rect.right() + 1) - screen.left(), 0, 0, 0);
        break;
    case Edge::Unknown:
        break;
    }
    // 面板把整块屏占满 / 比屏还大 ⇒ 扣完是空矩形 ⇒ 退回整屏
    // （空矩形会让落点判定以为「没有可用区」，落点全乱）。
    if (out.isEmpty())
        return screen;
    return out;
}

QRect effectiveAvailable(const QRect &qpaAvailable, const QRect &screen, const Panel &panel)
{
    if (panel.isEmpty() || screen.isEmpty())
        return qpaAvailable;
    // 面板不在这块屏上（多屏 + 面板只在主屏）⇒ 不动。
    if (!panel.rect.intersects(screen))
        return qpaAvailable;
    const QRect byPanel = usableArea(screen, panel);
    if (byPanel == screen)
        return qpaAvailable;
    const QRect out = qpaAvailable.intersected(byPanel);
    // 取交后空了（QPA 与面板两套说法打架）⇒ 宁可信 QPA（它至少是平台自己说的）。
    if (out.isEmpty())
        return qpaAvailable;
    return out;
}

} // namespace PanelGeometry
