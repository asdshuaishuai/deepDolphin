// Backend.cpp — 平台后端判定（判定层：纯函数、零 UI 依赖）。
#include "Backend.h"

#include <QtGlobal>

namespace {

/// 插件名是否**以 token 开头**：`name == token` 或 `name` 以 `token-` 开头。
///
/// ⚠ 为什么不做朴素前缀比较：朴素 `startsWith("wayland")` 会把
///   "mywayland" / "xwayland" 也算成 Wayland ⇒ 分档错 ⇒ 走错激活动作。
///   加 token 边界后，"wayland" / "wayland-egl" 命中，"mywayland" 不命中。
bool startsWithToken(const QString &name, const QString &token)
{
    if (name == token)
        return true;
    return name.size() > token.size() && name.startsWith(token)
        && name.at(token.size()) == QLatin1Char('-');
}

} // namespace

namespace Backend {

Kind classify(const QString &platformName)
{
    // ⚠ 顺序要紧：Wayland 的 QPA 插件名也叫 "wayland-*"，
    //   而 "xcb" 才是 X11 的插件名。先判 Wayland 再判 X11 不影响结果
    //   （两个 token 不可能同时命中），但把「X11 的判断依据」写清楚更省事。
    if (startsWithToken(platformName, QStringLiteral("wayland")))
        return Kind::Wayland;
    if (startsWithToken(platformName, QStringLiteral("xcb")))
        return Kind::X11;
    return Kind::Other;
}

QString kindName(Kind kind)
{
    switch (kind) {
    case Kind::X11:
        return QStringLiteral("x11");
    case Kind::Wayland:
        return QStringLiteral("wayland");
    case Kind::Other:
        break;
    }
    return QStringLiteral("other");
}

Activation activationFor(Kind kind)
{
    Activation plan;
    switch (kind) {
    case Kind::X11:
        // X11：`raise()` + `activateWindow()` 是老办法，管用 ⇒ 不绕 requestActivate。
        plan.requestActivate = false;
        plan.raiseWindow = true;
        break;
    case Kind::Wayland:
        // Wayland：叠放次序归合成器 ⇒ raise 无效；激活要走 requestActivate。
        plan.requestActivate = true;
        plan.raiseWindow = false;
        break;
    case Kind::Other:
        // 未知后端（offscreen/minimal/未来新协议）：**两样都上**——
        // requestActivate 是通用 API，失败也无害；漏调才是真丢功能。
        plan.requestActivate = true;
        plan.raiseWindow = true;
        break;
    }
    return plan;
}

bool trayGeometryUsable(const QRect &trayIconGeometry)
{
    return trayIconGeometry.width() > 0 && trayIconGeometry.height() > 0;
}

Insets reservedInsets(const QRect &screen, const QRect &available)
{
    Insets in;
    if (screen.isEmpty() || available.isEmpty())
        return in;
    in.left = qMax(0, available.left() - screen.left());
    in.top = qMax(0, available.top() - screen.top());
    in.right = qMax(0, screen.right() - available.right());
    in.bottom = qMax(0, screen.bottom() - available.bottom());
    return in;
}

PopupPlacement placePopup(const QRect &trayIconGeometry, const QSize &popupSize,
                           const QRect &available, const PopupGeometry &geo,
                           const PanelGeometry::Panel &panel)
{
    PopupPlacement out;
    const int w = qMax(0, popupSize.width());
    const int h = qMax(0, popupSize.height());

    QRect proposed;
    if (trayGeometryUsable(trayIconGeometry)) {
        // 托盘图标在位：弹窗落在图标**右下方**。
        // 右边缘 = 图标右边缘 + dockGap（`moveLeft(icon.right() - w + gap)`）。
        out.usedTrayGeometry = true;
        proposed.setLeft(trayIconGeometry.right() - w + geo.dockGap);
        proposed.setTop(trayIconGeometry.bottom() + geo.dockGap);
    } else if (!available.isEmpty()) {
        // 托盘几何不可用（DDE 上的常态：托盘是 SNI，拿不到坐标）⇒ 按**面板位置**落。
        const PanelGeometry::Edge edge = panel.isEmpty() ? PanelGeometry::Edge::Unknown
                                                          : panel.edge;
        if (edge != PanelGeometry::Edge::Unknown && !panel.rect.isEmpty()) {
            // 面板在**哪条边**，弹窗就落在它**朝屏幕中心**的那一侧，
            // 并贴着面板的「尾端」（横板 = 右端，竖板 = 底端）——
            // 那正是托盘图标所在的那个角。
            // ⚠ 一律先算**左上角**再配尺寸：QRect 的 setRight/setBottom 会
            //   反过来挪动另一条边，混着设必然错位。
            out.usedPanelGeometry = true;
            int left = 0;
            int top = 0;
            switch (edge) {
            case PanelGeometry::Edge::Top:
                // 面板在上 ⇒ 弹窗在面板**下方**，右对齐（与屏幕右缘留 fallbackDx）
                left = available.right() + geo.fallbackDx - w + 1;
                top = panel.rect.bottom() + geo.dockGap;
                break;
            case PanelGeometry::Edge::Bottom:
                // 面板在下（DDE 默认）⇒ 弹窗在面板**上方**，右对齐
                left = available.right() + geo.fallbackDx - w + 1;
                top = panel.rect.top() - geo.dockGap - h;
                break;
            case PanelGeometry::Edge::Left:
                // 面板在左 ⇒ 弹窗在面板**右侧**，贴底
                left = panel.rect.right() + geo.dockGap;
                top = available.bottom() - geo.edgeMargin - h;
                break;
            case PanelGeometry::Edge::Right:
                // 面板在右 ⇒ 弹窗在面板**左侧**，贴底
                left = panel.rect.left() - geo.dockGap - w;
                top = available.bottom() - geo.edgeMargin - h;
                break;
            case PanelGeometry::Edge::Unknown:
                break;
            }
            proposed.setLeft(left);
            proposed.setTop(top);
        } else {
            // 面板也读不到 ⇒ 屏幕右上（PLAN §8 T4）。⚠ 右边缘对齐口径：QRect 的
            //   right() = left + w - 1，所以「右边缘落在 p.x()」对应 left = p.x() - w + 1。
            const QPoint topRight = available.topRight() + QPoint(geo.fallbackDx, geo.fallbackDy);
            proposed.setLeft(topRight.x() - w + 1);
            proposed.setTop(topRight.y());
        }
    } else {
        // 既没有托盘几何、又没有任何屏幕 ⇒ **不猜落点**（空矩形的 topRight 是 (-1,-1)，
        // 拿它算会得出负坐标）。落回原点：位置难看，但确定、可测。
        proposed.setLeft(0);
        proposed.setTop(0);
    }
    proposed.setWidth(w);
    proposed.setHeight(h);

    QRect placed = proposed;
    if (!available.isEmpty() && w > 0 && h > 0) {
        if (w <= available.width() && h <= available.height()) {
            // 四边都夹。⚠ 边距**只在真的越界时才生效**（与旧实现同口径：旧实现
            //   只夹下边与左边，也是「越界才夹、夹完留边距」）——
            //   边距若是「无条件保持」，弹窗会被从托盘图标底下推下来十几像素，
            //   那是「离屏幕边留白」被误当成「离图标留白」。
            //   旧实现漏了**右边与上边** ⇒ 托盘在屏幕右上角时弹窗右侧溢出屏幕，
            //   弹窗比可用区高时顶部溢出屏幕（标题栏被切掉）。
            if (placed.right() > available.right())
                placed.moveRight(available.right() - geo.edgeMargin);
            if (placed.bottom() > available.bottom())
                placed.moveBottom(available.bottom() - geo.edgeMargin);
            if (placed.left() < available.left())
                placed.moveLeft(available.left() + geo.dockGap);
            if (placed.top() < available.top())
                placed.moveTop(available.top() + geo.edgeMargin);
            // 四条边互相顶（弹窗几乎占满可用区时，夹紧与留白会打架）⇒ 硬夹一次
            // 兜底：**放得下就一定整个落在可用区内**。
            if (placed.right() > available.right())
                placed.moveRight(available.right());
            if (placed.bottom() > available.bottom())
                placed.moveBottom(available.bottom());
        } else {
            // 弹窗比可用区还大 ⇒ 怎么夹都放不下 ⇒ 贴可用区左上角：
            // 至少标题栏看得见，落点也是**确定的**（不是随夹紧顺序漂）。
            placed.moveTopLeft(available.topLeft());
        }
    }
    out.rect = placed;
    out.clamped = (placed != proposed);
    return out;
}

} // namespace Backend
