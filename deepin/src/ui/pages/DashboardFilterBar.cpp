#include "DashboardFilterBar.h"
#include "../DesignTokens.h"
#include <QHBoxLayout>
#include <QLabel>

namespace {
// 三档分段（实测 libdtk6widget 6.7.47 导出类无 DSegmentedControl）：
// 三枚 QPushButton 组，选中态用 QSS 高亮（accent 底 + 白字）。
// 占位符在函数内就地填满——之前 %1/%2 留给调用方两级 .arg，未选中分支
// 没有第二个占位符，颜色喂进去只换来 6 条「Argument missing」告警。
QString segSheet(bool checked)
{
    const QString base = QStringLiteral(
        "QPushButton { border: none; border-radius: %1px; padding: 3px 12px; }");
    if (checked)
        return base.arg(DS::Radius::chip)
            + QStringLiteral("QPushButton { background: %1; color: white; }")
                  .arg(DS::semColor(DS::SemColor::accent).name());
    return base.arg(DS::Radius::chip)
        + QStringLiteral("QPushButton { background: palette(midlight); color: palette(text); }");
}
} // namespace

DashboardFilterBar::DashboardFilterBar(QWidget *parent)
    : QWidget(parent)
{
    auto *h = new QHBoxLayout(this);
    h->setContentsMargins(0, 0, 0, 0);
    h->setSpacing(DS::Spacing::sm);

    auto *timeLabel = new QLabel(QStringLiteral("时间跨度"), this);
    h->addWidget(timeLabel);

    m_windowGroup = new QButtonGroup(this);
    m_windowGroup->setExclusive(true);
    const TimeWindow windows[3] = { TimeWindow::all, TimeWindow::days30, TimeWindow::days7 };
    for (int i = 0; i < 3; ++i) {
        m_windowBtns[i] = new QPushButton(timeWindowLabel(windows[i]), this);
        m_windowBtns[i]->setCheckable(true);
        m_windowBtns[i]->setToolTip(timeWindowHelp());
        m_windowBtns[i]->setStyleSheet(segSheet(windows[i] == TimeWindow::all));
        m_windowGroup->addButton(m_windowBtns[i], i);
        h->addWidget(m_windowBtns[i]);
        connect(m_windowBtns[i], &QPushButton::clicked, this, [this, windows, i] {
            m_window = windows[i];
            reflectWindow();
            emit windowChanged(m_window);
        });
    }
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
    m_reindex->setText(busy ? QStringLiteral("重新索引…") : QStringLiteral("重新索引"));
}

void DashboardFilterBar::reflectWindow()
{
    const TimeWindow windows[3] = { TimeWindow::all, TimeWindow::days30, TimeWindow::days7 };
    for (int i = 0; i < 3; ++i) {
        m_windowBtns[i]->setChecked(m_window == windows[i]);
        m_windowBtns[i]->setStyleSheet(segSheet(m_window == windows[i]));
    }
}
