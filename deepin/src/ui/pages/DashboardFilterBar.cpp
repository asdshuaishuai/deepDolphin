#include "DashboardFilterBar.h"
#include "../DesignTokens.h"
#include "../common/BusyRow.h"
#include "../common/SegmentedButton.h"
#include <QHBoxLayout>
#include <QLabel>

DashboardFilterBar::DashboardFilterBar(QWidget *parent)
    : QWidget(parent)
{
    auto *h = new QHBoxLayout(this);
    h->setContentsMargins(0, 0, 0, 0);
    h->setSpacing(DS::Spacing::sm);

    auto *timeLabel = new QLabel(QStringLiteral("时间跨度"), this);
    h->addWidget(timeLabel);

    // 时间跨度三档：ui/common/SegmentedButton 单一实现（本文件与 AutomationPane 原各自
    // 持有一份 segSheet，M3b 收编；libdtk6widget 6.7.47 无导出 DSegmentedControl）
    m_windowSeg = new SegmentedButton(this);
    const TimeWindow windows[3] = { TimeWindow::all, TimeWindow::days30, TimeWindow::days7 };
    for (int i = 0; i < 3; ++i)
        m_windowSeg->addButton(timeWindowLabel(windows[i]), timeWindowHelp());
    h->addWidget(m_windowSeg);
    m_windowSeg->onClicked = [this, windows](int id) {
        m_window = windows[id];
        reflectWindow();
        emit windowChanged(m_window);
    };

    auto *help = new QLabel(this);
    help->setText(QStringLiteral("ⓘ"));
    help->setToolTip(timeWindowHelp());
    h->addWidget(help);

    h->addSpacing(DS::Spacing::lg);

    auto *typeLabel = new QLabel(QStringLiteral("提交类型"), this);
    h->addWidget(typeLabel);
    m_typeBox = new DComboBox(this);
    m_typeBox->setMaxVisibleItems(16);
    h->addWidget(m_typeBox, 1);
    connect(m_typeBox, &QComboBox::currentIndexChanged, this, [this](int idx) {
        const QString t = idx <= 0 ? QString() : m_typeBox->itemText(idx);
        emit typeChanged(t);
    });

    m_reindex = new QPushButton(QStringLiteral("重新索引"), this);
    m_reindex->setIcon(QIcon::fromTheme(QStringLiteral("view-refresh")));
    m_reindex->setToolTip(QStringLiteral("真跑一次浅更新，然后重新拉取仪表盘"));
    h->addWidget(m_reindex);
    connect(m_reindex, &QPushButton::clicked, this, &DashboardFilterBar::reindexClicked);

    // 忙态 = BusyRow 转圈 + 文案（plan §3b 五处 busy 表达之一）；按钮文案恒定，
    // 不再换字「重新索引…」（换字让按钮宽度跳动，BusyRow 说出「在忙」就够了）
    m_reindexBusy = new BusyRow(QStringLiteral("正在重新索引…"), this);
    m_reindexBusy->setBusy(false);
    h->addWidget(m_reindexBusy);

    h->addStretch(1);
    reflectWindow();
}

void DashboardFilterBar::setFilter(const DashFilter &f)
{
    m_window = f.window;
    reflectWindow();
    const int idx = f.commitType.isEmpty() ? 0 : m_typeBox->findText(f.commitType);
    if (idx >= 0)
        m_typeBox->setCurrentIndex(idx);
}

void DashboardFilterBar::setTypeOptions(const QStringList &types, bool enabled,
    const QString &whyDisabled)
{
    QSignalBlocker block(m_typeBox);
    m_typeBox->clear();
    m_typeBox->addItem(QStringLiteral("所有提交类型"));
    m_typeBox->addItems(types);
    m_typeBox->setEnabled(enabled);
    m_typeBox->setToolTip(enabled ? QString() : whyDisabled);
}

void DashboardFilterBar::setReindexBusy(bool busy)
{
    m_reindex->setEnabled(!busy);
    m_reindexBusy->setBusy(busy); // 转圈 + 「正在重新索引…」（按钮文字不再换字）
}

void DashboardFilterBar::reflectWindow()
{
    const TimeWindow windows[3] = { TimeWindow::all, TimeWindow::days30, TimeWindow::days7 };
    for (int i = 0; i < 3; ++i) {
        if (m_window == windows[i]) {
            m_windowSeg->setChecked(i); // 内部按选中态重刷两档 QSS
            return;
        }
    }
}
