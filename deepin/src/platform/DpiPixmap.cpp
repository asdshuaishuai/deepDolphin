#include "DpiPixmap.h"
#include <QGuiApplication>

namespace platform {

qreal devicePixelRatio()
{
    // 无 QGuiApplication 时按 1.0（不猜）：--selfcheck 跑在 GUI app 构造之前，
    // 那条路上不该出现 QPixmap（QPixmap 本身就需要 QGuiApplication）。
    return qApp ? qApp->devicePixelRatio() : 1.0;
}

QPixmap dpiPixmap(const QSize &logicalSize)
{
    const qreal dpr = devicePixelRatio();
    // ⚠ QSize * qreal 会四舍五入到整数设备像素 ⇒ dpr=1.5 时 8 → 12（不是 8.0）。
    QPixmap pm(logicalSize * dpr);
    // ⚠ **必须设**：设了之后 QPainter 在这张图上按 dpr 缩放坐标系，
    //   于是 drawEllipse(0,0,8,8) 画出来是 16×16 **设备**像素的圆（dpr=2）。
    //   不设的话位图只有 8×8 设备像素，被控件放大 ⇒ 发虚（这正是我们要修的）。
    pm.setDevicePixelRatio(dpr);
    return pm;
}

} // namespace platform
