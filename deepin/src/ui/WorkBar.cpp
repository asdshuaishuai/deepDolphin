#include "WorkBar.h"
#include "DualTrackButtons.h"
#include "../app/AppModel.h"
#include "../logic/Derived.h"
#include "DesignTokens.h"
#include <DComboBox>
#include <QHBoxLayout>
#include <QLabel>

DWIDGET_USE_NAMESPACE

namespace {
// 看板/里程碑是**全局视图**，范围选择器显示「全局看板」（Scope.swift:112-117 对位：
// 那条下拉只分「全局 / 单仓库」，不承载「看哪个视图」）。
constexpr int kGlobalIndex = 0;
} // namespace

WorkBar::WorkBar(QWidget *parent)
    : QWidget(parent)
{
    auto *h = new QHBoxLayout(this);
    h->setContentsMargins(DS::Spacing::xxl, DS::Spacing::xs, DS::Spacing::xxl, DS::Spacing::xs);
    h->setSpacing(DS::Spacing::sm);

    auto *globe = new QLabel(this);
    globe->setPixmap(QIcon::fromTheme(QStringLiteral("globe")).pixmap(16, 16));
    h->addWidget(globe);

    m_range = new Dtk::Widget::DComboBox(this);
    m_range->setMaximumWidth(320);
    h->addWidget(m_range);
    h->addStretch(1);

    m_dual = new DualTrackButtons(this);
    h->addWidget(m_dual);

    // 范围选择器**不持有状态**：激活某项 → go 回调（写回 model）
    connect(m_range, &Dtk::Widget::DComboBox::activated, this, [this](int index) {
        if (!m_go)
            return;
        if (index <= kGlobalIndex)
            m_go(Selection::dashboard());
        else if (index - 1 < m_range->property("projectNames").toStringList().size())
            m_go(Selection::project(m_range->property("projectNames").toStringList().at(index - 1)));
    });
}

void WorkBar::refreshFrom(AppModel *model)
{
    // 范围选择器：全局看板（全部 N 个项目）/ 各项目名
    const auto &projects = model->projects();
    QStringList names;
    for (const ProjectStatus &p : projects)
        names << p.name;
    const QString current = model->selection().kind == Selection::Kind::project
        ? model->selection().projectName
        : QString();
    const int globalCount = static_cast<int>(projects.size());
    const QString globalLabel = QStringLiteral("全局看板（全部 %1 个项目）").arg(globalCount);

    QSignalBlocker block(m_range);
    m_range->clear();
    m_range->addItem(globalLabel);
    m_range->addItems(names);
    m_range->setProperty("projectNames", names);
    const int idx = current.isEmpty() ? kGlobalIndex : m_range->findText(current);
    m_range->setCurrentIndex(idx < 0 ? kGlobalIndex : idx);

    // 双轨：范围由 selection 推导（没有第二真相源）
    const UpdateScope scope = scopeFromSelection(model->selection());
    m_dual->setScope(scope);
    m_dual->setPending(model->pendingForScope(scope));
    m_dual->setBusy(busyFor(scope, model->busyAll(), model->busyProjects()));
}
