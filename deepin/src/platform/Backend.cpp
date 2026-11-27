// Backend.cpp — 平台层：执行后端差异（PLAN §9 M1-7）。
#include "Backend.h"
#include "DdePanel.h"

#include <QCursor>
#include <QGuiApplication>
#include <QScreen>
#include <QSystemTrayIcon>
#include <QWidget>
#include <QWindow>

namespace platform {

BackendKind current()
{
    return ::Backend::classify(QGuiApplication::platformName());
}

QString currentName()
{
    return QGuiApplication::platformName();
}

bool isWayland()
{
    return current() == BackendKind::Wayland;
}

void activate(QWidget *w)
{
    if (!w)
        return;
    const Backend::Activation plan = Backend::activationFor(current());

    // ⚠ **先恢复最小化态再 show**：`show()` 不会把最小化的窗口拉回来
    //   （实测：离屏 + xcb 两种后端，show() 之后 windowState 仍带 WindowMinimized
    //   ⇒ 面板被最小化后从托盘点「打开面板」，点了跟没点一样）。
    // ⚠ **只摘最小化位，不用 showNormal()**：showNormal() 会顺带清掉最大化位
    //   （实测：WindowMaximized → WindowNoState）⇒ 用户最大化着的面板
    //   从托盘叫醒时会被打回普通大小。
    if (plan.restoreIfMinimized && w->isMinimized())
        w->setWindowState(w->windowState() & ~Qt::WindowMinimized);

    w->show();
    if (plan.raiseWindow)
        w->raise();

    if (plan.requestActivate) {
        // Wayland（及未知后端）：走窗口句柄请求激活。
        // ⚠ 句柄可能还没建出来（窗口从未显示过）⇒ 退回老办法。
        if (QWindow *handle = w->windowHandle())
            handle->requestActivate();
        else
            w->activateWindow();
    } else {
        w->activateWindow();
    }
}

QRect trayIconGeometry(const QSystemTrayIcon *icon)
{
    if (!icon)
        return QRect();
    const QRect geo = icon->geometry();
    return Backend::trayGeometryUsable(geo) ? geo : QRect();
}

QRect availableGeometryAt(const QPoint &anchor)
{
    QScreen *screen = QGuiApplication::screenAt(anchor);
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    if (!screen)
        return QRect(); // 这台机器一个屏幕都没有 ⇒ 不猜分辨率
    return screen->availableGeometry();
}

QRect screenGeometryAt(const QPoint &anchor)
{
    QScreen *screen = QGuiApplication::screenAt(anchor);
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    if (!screen)
        return QRect();
    return screen->geometry();
}

Backend::Insets taskbarInsetsAt(const QPoint &anchor)
{
    QScreen *screen = QGuiApplication::screenAt(anchor);
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    if (!screen)
        return Backend::Insets();
    return Backend::reservedInsets(screen->geometry(), screen->availableGeometry());
}

QRect trayPopupTarget(const QRect &trayIconGeometry, const QSize &popupSize,
                       const Backend::PopupGeometry &geo)
{
    // ① 托盘图标所在屏（托盘几何可用时）
    // ② 托盘几何不可用 ⇒ **光标所在屏**（DDE 上 `QSystemTrayIcon` 没有宿主
    //    —— DDE 托盘画的是应用自绘的 X11 窗口，批 Y 查明 ⇒ 拿不到坐标；
    //    用户点了托盘，光标就在那块屏上 ⇒ 用光标比用主屏准）
    // ③ 都没有 ⇒ 主屏（availableGeometryAt 内部兜底）
    const bool haveTray = Backend::trayGeometryUsable(trayIconGeometry);
    const QPoint anchor =
        haveTray ? trayIconGeometry.center() : QCursor::pos();

    // 面板真几何（D-Bus 读来的，见 platform/DdePanel）：
    // Wayland 下 QPA 的 availableGeometry **未必**扣掉面板 ⇒ 用面板真几何修正。
    const PanelGeometry::Panel panel = DdePanel::current();
    const QRect screen = screenGeometryAt(anchor);
    const QRect avail =
        PanelGeometry::effectiveAvailable(availableGeometryAt(anchor), screen, panel);
    return Backend::placePopup(trayIconGeometry, popupSize, avail, geo, panel).rect;
}

} // namespace platform
