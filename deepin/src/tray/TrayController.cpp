#include "TrayController.h"
#include "TrayPopupWindow.h"
#include "../platform/IconLoader.h"
#include <QApplication>
#include <QMenu>
#include <QPainter>
#include <QSystemTrayIcon>

namespace {
// 基础符号按 tint 染色（menuSymbol 五态的形状归一：感叹三角/感叹圆/双圆格/问号圆）。
// 壳阶段先画几何占位；dd-*.svg 资源与 Qt6Svg 染色通道就位后替换（IconLoader::symbol）。
QIcon tintedIcon(const QColor &tint, bool alert)
{
    QPixmap pm(32, 32);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);
    p.setBrush(tint.isValid() ? tint : QColor(0x10, 0xB9, 0x81));
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
        p.drawEllipse(4, 4, 24, 24);
        p.setBrush(Qt::white);
        p.drawEllipse(11, 11, 10, 10);
    }
    return QIcon(pm);
}

QColor tintColor(Liveness l)
{
    switch (l) {
    case Liveness::engineStale:
        return QColor(0xEF, 0x44, 0x44); // 红（stale 优先）
    case Liveness::needsAction:
        return QColor(0xF5, 0x9E, 0x0B); // 橙（dirty）
    case Liveness::recent:
        return QColor(0x10, 0xB9, 0x81); // 绿
    case Liveness::unreadable:
        return QColor(0xDC, 0x26, 0x26);
    case Liveness::notGit:
        return QColor(0x8B, 0x5C, 0xF6);
    case Liveness::quiet:
    case Liveness::unknown:
        break;
    }
    return QColor(0x9C, 0xA3, 0xAF);
}
} // namespace

TrayController::TrayController(QObject *parent)
    : QObject(parent)
{
    m_icon = new QSystemTrayIcon(this);
    m_popup = new TrayPopupWindow;
    buildMenu();
    connect(m_icon, &QSystemTrayIcon::activated, this, &TrayController::onActivated);

    connect(m_popup, &TrayPopupWindow::openPanelRequested, this, &TrayController::openPanelRequested);
    connect(m_popup, &TrayPopupWindow::updateAllClicked, this, &TrayController::updateAllRequested);
    connect(m_popup, &TrayPopupWindow::openProject, this, &TrayController::openProjectRequested);
    connect(m_popup, &TrayPopupWindow::refreshClicked, this, &TrayController::refreshLightRequested);
    connect(m_popup, &TrayPopupWindow::quitClicked, this, &TrayController::quitRequested);

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
    m_icon->setContextMenu(m_menu);
}

void TrayController::refreshIcon(const QString &menuTitle, Liveness tint)
{
    if (!m_icon)
        return;
    m_icon->setToolTip(menuTitle);
    m_tint = tintColor(tint);
    m_icon->setIcon(tintedIcon(m_tint, tint == Liveness::engineStale
                || tint == Liveness::needsAction));
}

void TrayController::refreshFrom(const TraySnapshot &snapshot)
{
    if (m_popup)
        m_popup->refreshFrom(snapshot);
}

bool TrayController::isVisible() const
{
    return m_icon && m_icon->isVisible();
}

void TrayController::onActivated(QSystemTrayIcon::ActivationReason reason)
{
    switch (reason) {
    case QSystemTrayIcon::Trigger: // 左键 → 弹速览
        if (m_popup) {
            emit refreshLightRequested(); // onShow 轻刷新
            m_popup->popupNear(m_icon->geometry());
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
