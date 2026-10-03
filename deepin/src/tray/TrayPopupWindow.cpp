#include "TrayPopupWindow.h"
#include "../ui/DesignTokens.h"
#include <QApplication>
#include <QHBoxLayout>
#include <QLabel>
#include <QPainter>
#include <QPainterPath>
#include <QScreen>
#include <QVBoxLayout>

namespace {
constexpr int kPopupWidth = 380;
constexpr int kMaxRows = 12; // 平铺 prefix(12)，不用滚动区（ScrollView 塌缩教训）
} // namespace

TrayPopupWindow::TrayPopupWindow(QWidget *parent)
    : QWidget(parent, Qt::Tool | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint)
{
    setAttribute(Qt::WA_TranslucentBackground);
    setFixedWidth(kPopupWidth);

    auto *root = new QVBoxLayout(this);
    root->setContentsMargins(12, 12, 12, 12);
    root->setSpacing(8);

    // ── header ──
    auto *header = new QHBoxLayout;
    m_title = new QLabel(QStringLiteral("项目群进度"), this);
    QFont titleFont = m_title->font();
    titleFont.setBold(true);
    m_title->setFont(titleFont);
    m_summary = new QLabel(this);
    m_summary->setWordWrap(true);
    m_summary->setStyleSheet(
        QStringLiteral("color: %1;").arg(DS::textSecondary().name()));
    m_refreshBtn = new QPushButton(QStringLiteral("刷新"), this);
    m_refreshBtn->setFlat(true);
    header->addWidget(m_title);
    header->addStretch(1);
    header->addWidget(m_refreshBtn);
    root->addLayout(header);
    root->addWidget(m_summary);

    // ── body（三态，rebuild 时重建）──
    m_body = new QWidget(this);
    m_bodyLayout = new QVBoxLayout(m_body);
    m_bodyLayout->setContentsMargins(0, 0, 0, 0);
    m_bodyLayout->setSpacing(4);
    root->addWidget(m_body);

    // ── footer：打开面板 / 全部浅更新 / 退出 ──
    auto *footer = new QHBoxLayout;
    m_openPanelBtn = new QPushButton(QStringLiteral("打开面板"), this);
    m_updateAllBtn = new QPushButton(QStringLiteral("全部浅更新"), this);
    m_quitBtn = new QPushButton(QStringLiteral("退出"), this);
    m_quitBtn->setFlat(true);
    footer->addWidget(m_openPanelBtn);
    footer->addWidget(m_updateAllBtn);
    footer->addStretch(1);
    footer->addWidget(m_quitBtn);
    root->addLayout(footer);

    connect(m_refreshBtn, &QPushButton::clicked, this, &TrayPopupWindow::refreshClicked);
    connect(m_openPanelBtn, &QPushButton::clicked, this, &TrayPopupWindow::openPanelRequested);
    connect(m_updateAllBtn, &QPushButton::clicked, this, &TrayPopupWindow::updateAllClicked);
    connect(m_quitBtn, &QPushButton::clicked, this, &TrayPopupWindow::quitClicked);

    rebuildBody(TraySnapshot{});
}

void TrayPopupWindow::paintEvent(QPaintEvent *)
{
    // 圆角 + 半透明底（模糊窗口效果留给后续 DBlurEffectWidget 阶段）
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing);
    QPainterPath path;
    path.addRoundedRect(rect().adjusted(1, 1, -1, -1), 10, 10);
    p.fillPath(path, palette().window());
    p.setPen(palette().mid().color());
    p.drawPath(path);
}

bool TrayPopupWindow::event(QEvent *e)
{
    if (e->type() == QEvent::WindowDeactivate)
        hide(); // 点外部/失焦自动收起（MenuBarExtra 行为）
    return QWidget::event(e);
}

bool TrayPopupWindow::eventFilter(QObject *watched, QEvent *e)
{
    // 项目行点击 → openProject（弹窗收起由 refreshFrom/Controller 决定）
    if (e->type() == QEvent::MouseButtonRelease && watched->isWidgetType()) {
        auto *w = qobject_cast<QWidget *>(watched);
        if (w && !w->property("projectName").toString().isEmpty()) {
            emit openProject(w->property("projectName").toString());
            hide();
            return true;
        }
    }
    return QWidget::eventFilter(watched, e);
}

void TrayPopupWindow::refreshFrom(const TraySnapshot &snapshot)
{
    m_snapshot = snapshot;
    m_summary->setText(snapshot.summaryLine);
    m_updateAllBtn->setEnabled(snapshot.engineFound && !snapshot.busy && snapshot.totalProjects > 0);
    rebuildBody(snapshot);
    update();
}

void TrayPopupWindow::popupNear(const QRect &trayIconGeometry)
{
    adjustSize();
    QRect target;
    QScreen *screen = QGuiApplication::screenAt(trayIconGeometry.center());
    if (!screen && QGuiApplication::primaryScreen())
        screen = QGuiApplication::primaryScreen();
    const QRect avail = screen ? screen->availableGeometry()
                               : QRect(0, 0, 1280, 720);
    if (trayIconGeometry.isValid()) {
        target.moveCenter(trayIconGeometry.center());
        target.moveLeft(trayIconGeometry.right() - width() + 8);
        target.moveTop(trayIconGeometry.bottom() + 8);
    } else {
        // 取不到托盘几何 → 屏幕右上（PLAN §8 T4）
        target.moveTopRight(avail.topRight() + QPoint(-16, 32));
    }
    target.setWidth(width());
    target.setHeight(height());
    if (target.bottom() > avail.bottom())
        target.moveBottom(avail.bottom() - 16);
    if (target.left() < avail.left())
        target.moveLeft(avail.left() + 8);
    move(target.topLeft());
    show();
    raise();
    activateWindow();
}

void TrayPopupWindow::rebuildBody(const TraySnapshot &snapshot)
{
    // 清空旧行
    while (m_bodyLayout->count() > 0) {
        QLayoutItem *it = m_bodyLayout->takeAt(0);
        if (it->widget())
            it->widget()->deleteLater();
        delete it;
    }

    if (!snapshot.engineFound) {
        auto *msg = new QLabel(snapshot.engineProblem, m_body);
        msg->setWordWrap(true);
        m_bodyLayout->addWidget(msg);
        return;
    }
    if (snapshot.rows.isEmpty()) {
        auto *msg = new QLabel(snapshot.busy ? QStringLiteral("读取中…")
                                             : QStringLiteral("暂无已注册项目。运行「扫描项目」注册项目群。"),
            m_body);
        msg->setWordWrap(true);
        m_bodyLayout->addWidget(msg);
        return;
    }

    const int shown = qMin(kMaxRows, snapshot.rows.size());
    for (int i = 0; i < shown; ++i) {
        const TraySnapshot::Row &row = snapshot.rows.at(i);
        auto *line = new QWidget(m_body);
        line->setProperty("projectName", row.name);
        auto *h = new QHBoxLayout(line);
        h->setContentsMargins(0, 2, 0, 2);
        h->setSpacing(6);
        auto *dot = new QLabel(line);
        QPixmap pm(10, 10);
        pm.fill(Qt::transparent);
        QPainter p(&pm);
        p.setRenderHint(QPainter::Antialiasing);
        p.setBrush(row.dot.isValid() ? row.dot : QColor(0x9C, 0xA3, 0xAF));
        p.setPen(Qt::NoPen);
        p.drawEllipse(0, 0, 10, 10);
        dot->setPixmap(pm);
        h->addWidget(dot);
        auto *name = new QLabel(row.name, line);
        name->setFixedWidth(120);
        h->addWidget(name);
        // ●N 橙 chip（userDirtyCount>0）
        if (row.dirty > 0) {
            auto *dirty = new QLabel(QStringLiteral("●%1").arg(row.dirty), line);
            dirty->setStyleSheet(
                QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
            h->addWidget(dirty);
        }
        if (row.rowBusy) {
            auto *busy = new QLabel(QStringLiteral("…"), line);
            busy->setStyleSheet(
                QStringLiteral("color: %1;").arg(DS::textSecondary().name()));
            h->addWidget(busy);
        }
        auto *sub = new QLabel(row.unreadable ? row.subtitle
                                              : (row.subtitle.isEmpty() ? QStringLiteral("—")
                                                                        : row.subtitle),
            line);
        // 红 = 语义红单点（tray 层不得持有色值，D2 grep 门）；次级 = DS 单点
        sub->setStyleSheet(row.unreadable
                ? QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::red).name())
                : QStringLiteral("color: %1;").arg(DS::textSecondary().name()));
        h->addWidget(sub, 1);
        if (row.pending > 0) {
            // 右侧 pendingCommits 数字（蓝）+ 迷你进度条（min(pending,10)/10，宽 44）
            auto *pending = new QLabel(QStringLiteral("+%1").arg(row.pending), line);
            // 语义 accent 单点（此前的私有蓝值是审计点名的“第二种蓝”，归并）
            pending->setStyleSheet(
                QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::accent).name()));
            h->addWidget(pending);
            auto *bar = new QLabel(line);
            bar->setFixedSize(44, 4);
            h->addWidget(bar);
            // 迷你进度条（一次性画成 pixmap）
            QPixmap barPm(44, 4);
            barPm.fill(Qt::transparent);
            QPainter bp(&barPm);
            bp.setRenderHint(QPainter::Antialiasing);
            bp.setPen(Qt::NoPen);
            bp.setBrush(QColor(128, 128, 128, 60));
            bp.drawRoundedRect(0, 0, 44, 4, 2, 2);
            bp.setBrush(QColor(0x1E, 0x6F, 0xEB));
            const int w = 44 * qMin(row.pending, 10) / 10;
            if (w > 0)
                bp.drawRoundedRect(0, 0, w, 4, 2, 2);
            bar->setPixmap(barPm);
        }
        // 点击行 = go(.project) + bringToFront + loadProject（经 eventFilter 捕获点击发 openProject）；
        // 子控件全透鼠标——整行命中（「.badge 吃点击」缺陷的等价防御）
        for (QWidget *child : line->findChildren<QWidget *>())
            child->setAttribute(Qt::WA_TransparentForMouseEvents);
        line->setCursor(Qt::PointingHandCursor);
        line->installEventFilter(this);
        m_bodyLayout->addWidget(line);
    }
    if (snapshot.rows.size() > kMaxRows) {
        auto *more = new QLabel(
            QStringLiteral("还有 %1 个项目，打开面板查看…").arg(snapshot.rows.size() - kMaxRows),
            m_body);
        more->setStyleSheet(
            QStringLiteral("color: %1;").arg(DS::textSecondary().name()));
        m_bodyLayout->addWidget(more);
    }
}
