#include "MilestoneRowWidget.h"
#include <DWarningButton>
#include "../../logic/Derived.h"
#include "../DesignTokens.h"
#include "../common/Chip.h"
#include "../common/FlatButton.h"
#include "../common/SecondaryLabel.h"
#include <QContextMenuEvent>

DWIDGET_USE_NAMESPACE

#include <QHBoxLayout>
#include <QLabel>
#include <QMenu>
#include <QPainter>
#include <QPushButton>
#include <QVBoxLayout>

namespace {
// 图标五态（unknown 是橙 **?**，不是进行中的蓝； overdue 红！）。
QPixmap stateIcon(const Milestone &m, int size = 14)
{
    QPixmap pm(size, size);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);
    QColor c;
    const bool unknown = Derived::milestoneUnknown(m);
    if (unknown)
        c = DS::semColor(DS::SemColor::orange);
    else if (m.status == QLatin1String("done"))
        c = DS::semColor(DS::SemColor::shallow);
    else if (m.status == QLatin1String("dropped"))
        c = DS::semColor(DS::SemColor::gray);
    else if (m.overdue)
        c = DS::semColor(DS::SemColor::red);
    else
        c = DS::semColor(DS::SemColor::accent);

    p.setPen(QPen(c, 1.4));
    if (unknown) {
        p.setBrush(Qt::NoBrush);
        p.drawEllipse(1, 1, size - 2, size - 2);
        p.drawText(pm.rect(), Qt::AlignCenter, QStringLiteral("?"));
    } else if (m.status == QLatin1String("done")) {
        p.setBrush(c);
        p.drawEllipse(1, 1, size - 2, size - 2);
        p.setPen(QPen(Qt::white, 1.6));
        p.drawLine(4, size / 2, size / 2 - 1, size - 5);
        p.drawLine(size / 2 - 1, size - 5, size - 4, 4);
    } else if (m.status == QLatin1String("dropped")) {
        p.drawEllipse(1, 1, size - 2, size - 2);
        p.drawLine(4, 4, size - 4, size - 4);
        p.drawLine(size - 4, 4, 4, size - 4);
    } else if (m.overdue) {
        p.setBrush(c);
        p.drawEllipse(1, 1, size - 2, size - 2);
        p.setPen(QPen(Qt::white, 1.6));
        p.drawLine(size / 2, 3, size / 2, size / 2 + 1);
        p.drawPoint(size / 2, size - 4);
    } else {
        // open：circle-dashed（蓝虚线圆）
        QPen dash(c, 1.4, Qt::DashLine);
        p.setPen(dash);
        p.setBrush(Qt::NoBrush);
        p.drawEllipse(2, 2, size - 4, size - 4);
    }
    return pm;
}
} // namespace

MilestoneRowWidget::MilestoneRowWidget(QWidget *parent)
    : QWidget(parent)
{
}

void MilestoneRowWidget::setMilestone(const Milestone &m, bool showProjectName)
{
    m_project = m.projectName;
    m_name = m.name;
    m_isOpen = m.status == QLatin1String("open");
    m_isUnknown = Derived::milestoneUnknown(m);
    m_isDropped = m.status == QLatin1String("dropped");
    delete layout();

    auto *h = new QHBoxLayout(this);
    h->setContentsMargins(DS::Spacing::xs, DS::Spacing::xs, DS::Spacing::xs, DS::Spacing::xs);
    h->setSpacing(DS::Spacing::sm);

    auto *icon = new QLabel(this);
    icon->setPixmap(stateIcon(m));
    icon->setToolTip(Derived::milestoneStatusLabel(m));
    h->addWidget(icon);

    auto *mid = new QVBoxLayout;
    mid->setSpacing(2);
    auto *row1 = new QHBoxLayout;
    row1->setSpacing(DS::Spacing::xs);
    if (showProjectName) {
        auto *proj = new SecondaryLabel(m.projectName, this);
        proj->setFont(DS::font(DS::FontT::label));
        row1->addWidget(proj);
    }
    auto *name = new QLabel(m.name, this);
    QFont nf = name->font();
    nf.setWeight(QFont::DemiBold);
    name->setFont(nf);
    row1->addWidget(name);
    if (m.tagReached) {
        auto *tagChip = new Chip(QStringLiteral("tag ✓ %1").arg(m.tagName), this);
        tagChip->setTone(DS::SemColor::shallow);
        row1->addWidget(tagChip);
    }
    row1->addStretch(1);
    mid->addLayout(row1);

    auto *row2 = new QHBoxLayout;
    row2->setSpacing(DS::Spacing::xs);
    if (!m.description.isEmpty()) {
        auto *desc = new SecondaryLabel(m.description, this);
        desc->setFont(DS::font(DS::FontT::label));
        row2->addWidget(desc);
    }
    if (!m.tagReached && !m.tag.isEmpty()) {
        auto *tag = new SecondaryLabel(QStringLiteral("tag %1").arg(m.tag), this);
        tag->setFont(DS::font(DS::FontT::label));
        row2->addWidget(tag);
    }
    // 「创建以来 N 提交」或橙 unverifiedNote（commitsSinceReadable==false 时）
    auto *commits = new QLabel(
        m.commitsSinceReadable ? Derived::milestoneCommitsText(m)
                               : Derived::milestoneUnverifiedNote(m),
        this);
    commits->setFont(DS::font(DS::FontT::label));
    commits->setStyleSheet(m.commitsSinceReadable
            ? QStringLiteral("color: %1;").arg(DS::textSecondary().name())
            : QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
    row2->addWidget(commits);
    row2->addStretch(1);
    mid->addLayout(row2);
    h->addLayout(mid, 1);

    // 右侧：状态词 + 目标日期
    auto *right = new QVBoxLayout;
    right->setSpacing(2);
    auto *status = new QLabel(Derived::milestoneStatusLabel(m), this);
    status->setFont(DS::font(DS::FontT::label));
    const QColor sc = Derived::milestoneUnknown(m) ? DS::semColor(DS::SemColor::orange)
        : m.status == QLatin1String("done")       ? DS::semColor(DS::SemColor::shallow)
        : m.status == QLatin1String("dropped")    ? DS::semColor(DS::SemColor::gray)
        : m.overdue                               ? DS::semColor(DS::SemColor::red)
                                                  : DS::semColor(DS::SemColor::accent);
    status->setStyleSheet(QStringLiteral("color: %1;").arg(sc.name()));
    right->addWidget(status);
    const QString due = Derived::milestoneDueText(m);
    if (!due.isEmpty() && !m.targetDate.isEmpty()) {
        auto *dueLabel = new SecondaryLabel(QStringLiteral("目标 %1 · %2").arg(m.targetDate, due), this);
        dueLabel->setFont(DS::font(DS::FontT::label));
        right->addWidget(dueLabel);
    }
    h->addLayout(right);

    // 行内直达按钮（不用 Menu——List 行内 Menu 命中率不可靠）
    auto *actions = new QHBoxLayout;
    actions->setSpacing(DS::Spacing::xs);
    if (m_isOpen) {
        auto *done = new FlatButton(QStringLiteral("达成"), this);
        connect(done, &QPushButton::clicked, this,
            [this] { emit doneClicked(m_project, m_name); });
        actions->addWidget(done);
    } else if (!m_isUnknown && !m_isDropped) {
        auto *reopen = new FlatButton(QStringLiteral("重开"), this);
        connect(reopen, &QPushButton::clicked, this,
            [this] { emit reopenClicked(m_project, m_name); });
        actions->addWidget(reopen);
    }
    // 破坏性动作 = DWarningButton（DTK 语义件自带警示红，不再手写色值）
    auto *remove = new DWarningButton(this); // DTK6 只有默认构造（dwarningbutton.h:16）
    remove->setText(QStringLiteral("删除"));
    remove->setFlat(true);
    connect(remove, &QPushButton::clicked, this,
        [this] { emit removeClicked(m_project, m_name); });
    actions->addWidget(remove);
    h->addLayout(actions);
}

void MilestoneRowWidget::contextMenuEvent(QContextMenuEvent *event)
{
    QMenu menu(this);
    // 右键菜单：标记达成 / 重新打开 / 放弃（确认）/ 打开项目 / 删除（确认）。
    // UI 词 "open" → CLI "reopen"（信号语义：reopenClicked 由页面层转 CLI）。
    if (m_isOpen) {
        menu.addAction(QStringLiteral("标记达成"), this, [this] { emit doneClicked(m_project, m_name); });
        menu.addAction(QStringLiteral("放弃"), this, [this] { emit dropClicked(m_project, m_name); });
    } else if (!m_isUnknown) {
        // done / dropped 均可重开
        menu.addAction(QStringLiteral("重新打开"), this, [this] { emit reopenClicked(m_project, m_name); });
    }
    menu.addSeparator();
    menu.addAction(QStringLiteral("打开项目"), this, [this] { emit openProject(m_project); });
    menu.addSeparator();
    menu.addAction(QStringLiteral("删除"), this, [this] { emit removeClicked(m_project, m_name); });
    menu.exec(event->globalPos());
}
