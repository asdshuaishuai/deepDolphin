#include "TrayController.h"
#include "TrayGeometry.h"
#include "TrayPopupWindow.h"
#include "../logic/SemColors.h"
#include "../logic/DeepinTray.h"
#include "../platform/Backend.h"
#include "../platform/DeepinTray.h"
#include "../platform/TrayBackend.h"
#include <QApplication>
#include <QDebug>
#include <QCursor>
#include <QDir>
#include <QFileInfo>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QSaveFile>
#include <QSystemTrayIcon>

namespace {
// 基础符号按 tint 染色（menuSymbol 五态的形状归一：感叹三角/感叹圆/双圆格/问号圆）。
// 壳阶段先画几何占位（画布/外环/内芯取 TrayGeometry；感叹三角与感叹点是
// 一次性占位坐标，dd-*.svg 资源与 Qt6Svg 染色通道就位后连同整个 painter 替换）。
QIcon tintedIcon(const QColor &tint, bool alert)
{
    const int canvas = TrayGeometry::iconCanvas;
    const int ringD = canvas - 2 * TrayGeometry::iconRingInset;
    const int coreD = canvas - 2 * TrayGeometry::iconCoreInset;
    QPixmap pm(canvas, canvas);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);
    p.setBrush(tint.isValid() ? tint : SemColors::shallow());
    p.setPen(Qt::NoPen);
    if (alert) {
        // 感叹三角（⚠︎ 形）
        QPolygonF tri;
        tri << QPointF(16, 3) << QPointF(29, 27) << QPointF(3, 27);
        p.drawPolygon(tri);
        p.setBrush(Qt::white);
        p.drawRect(14.5, 11, 3, 8);
        p.drawEllipse(QPointF(16, 23), 1.6, 1.6);
    } else {
        // ⚠⚠⚡ **必须用 QRect 重载**：`QPainter::drawEllipse(qreal, qreal, qreal, qreal)`
        //   的前两个参数是**圆心**（rx, ry），**不是**左上角！
        //   写成 `drawEllipse(inset, inset, d, d)` ⇒ 实际画在 (-8,-8)-(16,16)
        //   ⇒ 整个圆几乎在画布外 ⇒ **图标是全透明的**（实测：中心像素 0x00000000），
        //   而且这跟平台无关 —— **所有桌面上的托盘图标都是空白的**。
        p.drawEllipse(QRect(TrayGeometry::iconRingInset, TrayGeometry::iconRingInset,
                             ringD, ringD));
        p.setBrush(Qt::white);
        p.drawEllipse(QRect(TrayGeometry::iconCoreInset, TrayGeometry::iconCoreInset,
                             coreD, coreD));
    }
    return QIcon(pm);
}

QColor tintColor(Liveness l)
{
    switch (l) {
    case Liveness::engineStale:
        return SemColors::stale(); // 陈旧红（stale 优先）
    case Liveness::needsAction:
        return SemColors::orange(); // 橙（dirty）
    case Liveness::recent:
        return SemColors::shallow(); // 绿
    case Liveness::unreadable:
        return SemColors::red();
    case Liveness::notGit:
        return SemColors::deep();
    case Liveness::quiet:
    case Liveness::unknown:
        break;
    }
    return SemColors::gray();
}
} // namespace

TrayController::TrayController(QObject *parent)
    : QObject(parent)
{
    m_popup = new TrayPopupWindow;
    connect(m_popup, &TrayPopupWindow::openPanelRequested, this, &TrayController::openPanelRequested);
    connect(m_popup, &TrayPopupWindow::updateAllClicked, this, &TrayController::updateAllRequested);
    connect(m_popup, &TrayPopupWindow::openProject, this, &TrayController::openProjectRequested);
    connect(m_popup, &TrayPopupWindow::refreshClicked, this, &TrayController::refreshLightRequested);
    connect(m_popup, &TrayPopupWindow::quitClicked, this, &TrayController::quitRequested);

    // 桌面托盘走**哪条路**？（三选一，不并存）
    //   · deepin 私有窗口协议（DDE 25）：自绘 X11 窗口 + REQUEST_DOCK；
    //   · 标准 SNI（KDE 系桌面）；
    //   · 旧协议（其余桌面：QSystemTrayIcon）。
    // ⚠ **顺序有讲究**：DDE 25 上 SNI watcher 也在（ayatana 变体）但**不画** SNI 图标
    //   ⇒ 若「有 watcher 就走 SNI」，图标永远不出现（批 X 踩的就是这个坑）。
    m_sniStatus = platform::probeTraySni();
    m_deepinStatus = platform::probeDeepinTray();
    const TraySni::BackendOverride forced = platform::trayBackendOverride();
    m_backend = TraySni::chooseBackend(m_deepinStatus.selectionPresent,
                                        m_sniStatus.watcherPresent, forced);
    m_sniMode = m_backend == TraySni::Backend::Sni;

    // ⚠ **报出实际走的后端** —— 真机探针要盯这一段：
    //   「探针强制了某条路」≠「应用真走了那条路」⇒ 判据必须核对应用自己报的。
    // ⚠ 打**单条**格式化字符串（不是多个参数）：`qInfo` 逐参数打印时会给
    //   QString **加引号**（`托盘后端 = "deepin-window"`）⇒ 探针按空格切字段就会切错。
    qInfo() << QStringLiteral("托盘后端 = %1（%2）")
                   .arg(TraySni::backendName(m_backend),
                        forced.has_value() ? QStringLiteral("强制") : QStringLiteral("自动"));

    if (m_backend == TraySni::Backend::DeepinWindow) {
        // ⚠ deepin 走窗口协议：**不建** QSystemTrayIcon（它在这儿没有宿主，
        //   一个像素都不显示）⇒ 托盘图标 = 我们自己画进一个 X11 窗口。
        buildMenu();
        m_currentIcon = tintedIcon(tintColor(Liveness::unknown), false);
        publishDeepinIcon(QStringLiteral("deepDolphin"));
        return;
    }

    if (m_sniMode) {
        // ⚠ SNI 模式：**不建** QSystemTrayIcon —— 旧协议在 DDE 上没有宿主
        //   （DDE 托盘画的是应用自绘的 X11 窗口，批 Y 查明），
        //   图标根本不会显示（实测全屏差分 0 像素），留着只是白占一个对象。
        buildMenu();
        connect(platform::TraySniNotifier::instance(), &platform::TraySniNotifier::activated,
                this, &TrayController::onSniActivated);
        // ⚠ **先给图标再发布** —— 首次发布时 `m_currentIcon` 是空的 ⇒
        //   编码出来的 IconPixmap 会是**全 0 的透明图** ⇒ 宿主拿到一张空图
        //   ⇒ 托盘里不画它（实测：项在 watcher 列表里，但托盘区一个像素没多）。
        m_currentIcon = tintedIcon(tintColor(Liveness::unknown), false);
        publishSniIcon(QStringLiteral("deepDolphin"));
        return;
    }

    m_icon = new QSystemTrayIcon(this);
    buildMenu();
    connect(m_icon, &QSystemTrayIcon::activated, this, &TrayController::onActivated);

    m_icon->setIcon(tintedIcon(tintColor(Liveness::unknown), false));
    m_icon->setToolTip(QStringLiteral("deepDolphin"));
    m_icon->show();
}

TrayController::~TrayController() = default;

void TrayController::buildMenu()
{
    m_menu = new QMenu;
    // 刻意两项（mac Dock 菜单纪律）+ Linux 必要的退出项
    QAction *open = m_menu->addAction(QStringLiteral("打开面板"));
    QAction *updateAll = m_menu->addAction(QStringLiteral("全部浅更新"));
    m_menu->addSeparator();
    QAction *quit = m_menu->addAction(QStringLiteral("退出"));
    connect(open, &QAction::triggered, this, &TrayController::openPanelRequested);
    connect(updateAll, &QAction::triggered, this, &TrayController::updateAllRequested);
    connect(quit, &QAction::triggered, this, &TrayController::quitRequested);
    // ⚠ SNI 模式下没有 QSystemTrayIcon ⇒ 菜单不能挂它（宿主点右键时我们自己弹）。
    if (m_icon)
        m_icon->setContextMenu(m_menu);
}

void TrayController::publishSniIcon(const QString &menuTitle)
{
    if (!m_sniMode)
        return;
    const QPixmap pm = m_currentIcon.pixmap(32, 32);
    if (pm.isNull())
        return;


    // IconName 指**绝对路径**（宿主支持：ayatana 那个能显示的项就是这么用的）⇒
    // 得真有个文件在那儿 ⇒ 写缓存目录（属「程序自身依赖」，不是业务数据）。
    const QString file = platform::trayIconCacheFile();
    QDir().mkpath(QFileInfo(file).absolutePath());
    QSaveFile f(file);
    if (f.open(QIODevice::WriteOnly) && pm.save(&f, "PNG"))
        f.commit();

    TraySni::ItemSpec spec;
    spec.serviceName = QStringLiteral("org.deepin.deepDolphin");
    spec.objectPath = QStringLiteral("/StatusNotifierItem");
    spec.id = QStringLiteral("deepDolphin");
    spec.title = menuTitle;
    spec.category = QStringLiteral("ApplicationStatus");
    spec.status = QStringLiteral("Active");
    spec.iconName = file;
    spec.iconThemePath = QFileInfo(file).absolutePath();
    spec.itemIsMenu = false;

    const QList<QImage> icons{pm.toImage()};
    m_sniStatus = platform::publishTraySni(spec, icons);
    if (!m_sniStatus.published && m_sniStatus.error.isEmpty())
        m_sniStatus.error = QStringLiteral("SNI 发布未完成");
}

void TrayController::publishDeepinIcon(const QString &menuTitle)
{
    if (m_backend != TraySni::Backend::DeepinWindow)
        return;
    const QPixmap pm = m_currentIcon.pixmap(32, 32);
    if (pm.isNull())
        return;
    // ⚠ 窗口名 = 托盘里显示的名字（实测 daemon 的 `GetName` 读窗口名；
    //   cc-switch / clash-verge 也是「窗口名 = 应用名」）。
    m_deepinStatus = platform::publishDeepinTray(pm.toImage(), menuTitle);
    if (!m_deepinStatus.published) {
        if (m_deepinStatus.error.isEmpty())
            m_deepinStatus.error = QStringLiteral("deepin 托盘窗口协议发布未完成");
        // ⚠ 失败要**看得见**（静默失败 ⇒ 托盘里没图标却没人知道为什么）
        qWarning() << "deepin 托盘窗口协议：发布失败 ——" << m_deepinStatus.error;
    } else {
        qInfo() << "deepin 托盘窗口协议：已认领，窗口 id ="
                << QStringLiteral("0x%1").arg(m_deepinStatus.windowId, 0, 16);
    }
}

void TrayController::onSniActivated(const QString &action)
{
    if (action == QLatin1String("ContextMenu")) {
        if (m_menu)
            m_menu->popup(QCursor::pos());
        return;
    }
    if (action == QLatin1String("Activate")) {
        if (m_popup) {
            emit refreshLightRequested();
            // SNI **没有位置字段**（实测：ItemPixmap/IconName 都不带几何）⇒
            // 落点只能按**面板几何**算（批 W 的 platform::trayPopupTarget）。
            m_popup->popupNear(QRect());
        }
        return;
    }
    emit openPanelRequested();
}

void TrayController::refreshIcon(const QString &menuTitle, Liveness tint)
{
    m_tint = tintColor(tint);
    m_currentIcon = tintedIcon(m_tint, tint == Liveness::engineStale
                || tint == Liveness::needsAction);
    if (m_backend == TraySni::Backend::DeepinWindow) {
        // 窗口已经在 ⇒ 直接重画（daemon 盯 damage ⇒ 会发 `Changed`，dock 重新抓图）
        if (m_deepinStatus.published)
            platform::updateDeepinTrayIcon(m_currentIcon.pixmap(32, 32).toImage());
        else
            publishDeepinIcon(menuTitle);
        return;
    }
    if (m_sniMode) {
        publishSniIcon(menuTitle);
        return;
    }
    if (!m_icon)
        return;
    m_icon->setToolTip(menuTitle);
    m_icon->setIcon(m_currentIcon);
}

void TrayController::refreshFrom(const TraySnapshot &snapshot)
{
    if (m_popup)
        m_popup->refreshFrom(snapshot);
}

bool TrayController::isVisible() const
{
    // 「可见」= 已登记进宿主（deepin 窗口协议 / SNI）；旧协议下看 QSystemTrayIcon。
    if (m_backend == TraySni::Backend::DeepinWindow)
        return m_deepinStatus.published;
    if (m_sniMode)
        return m_sniStatus.published;
    return m_icon && m_icon->isVisible();
}

void TrayController::onActivated(QSystemTrayIcon::ActivationReason reason)
{
    switch (reason) {
    case QSystemTrayIcon::Trigger: // 左键 → 弹速览
        if (m_popup) {
            emit refreshLightRequested(); // onShow 轻刷新
            // 托盘几何经平台层取（**已判可用性**）：Wayland 上托盘由合成器托管，
            // `QSystemTrayIcon::geometry()` 常是无效矩形 ⇒ 直接拿去定位会让弹窗飞到屏幕左上。
            m_popup->popupNear(platform::trayIconGeometry(m_icon));
        }
        break;
    case QSystemTrayIcon::Context: // 右键 → 菜单（setContextMenu 已接管）
    case QSystemTrayIcon::DoubleClick:
    case QSystemTrayIcon::MiddleClick:
        emit openPanelRequested();
        break;
    case QSystemTrayIcon::Unknown:
        break;
    }
}
