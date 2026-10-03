#include "MilestonesPage.h"
#include "MilestoneRowWidget.h"
#include "../../logic/DashboardScope.h"
#include "../../logic/Derived.h"
#include "../../logic/SearchFilter.h"
#include "../DesignTokens.h"
#include "../common/EmptyState.h"
#include "../common/FlatButton.h"
#include "../common/SecondaryLabel.h"
#include <DSpinner>
#include <DComboBox>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QTreeWidget>
#include <QVBoxLayout>

DWIDGET_USE_NAMESPACE

MilestonesPage::MilestonesPage(QWidget *parent)
    : QWidget(parent)
{
    auto *root = new QVBoxLayout(this);
    root->setContentsMargins(DS::Spacing::xxl, DS::Spacing::lg, DS::Spacing::xxl, DS::Spacing::xxl);
    root->setSpacing(DS::Spacing::md);

    // 工具行：搜索「里程碑名称」+ 新建里程碑（标题栏不放——1100pt 下会被压成图标）
    auto *tools = new QHBoxLayout;
    auto *search = new DLineEdit(this);
    search->setPlaceholderText(QStringLiteral("搜索里程碑名称"));
    search->setClearButtonEnabled(true);
    search->setMaximumWidth(280);
    connect(search, &DLineEdit::textChanged, this, [this](const QString &t) {
        m_query = t;
        rebuild();
    });
    tools->addWidget(search);
    tools->addStretch(1);
    auto *create = new FlatButton(this);
    create->setText(QStringLiteral("新建里程碑"));
    create->setIcon(QIcon::fromTheme(QStringLiteral("list-add")));
    connect(create, &QPushButton::clicked, this, [this] { emit createRequested(m_projectFilter); });
    tools->addWidget(create);
    root->addLayout(tools);

    // ── 仓库筛选条：内容区顶部（不在标题栏）──
    auto *filterRow = new QHBoxLayout;
    filterRow->setSpacing(DS::Spacing::sm);
    filterRow->addWidget(new QLabel(QStringLiteral("仓库"), this));
    m_projectBox = new DComboBox(this);
    m_projectBox->setMaxVisibleItems(20);
    m_projectBox->setMinimumContentsLength(24);
    m_projectBox->setSizeAdjustPolicy(QComboBox::AdjustToContents);
    connect(m_projectBox, &QComboBox::currentIndexChanged, this, [this](int idx) {
        m_projectFilter = idx <= 0 ? QString() : m_projectBox->itemText(idx);
        if (m_filterCount)
            m_filterCount->setVisible(!m_projectFilter.isEmpty());
        rebuild();
    });
    filterRow->addWidget(m_projectBox);
    m_filterCount = new SecondaryLabel(this);
    m_filterCount->setFont(DS::font(DS::FontT::label));
    m_filterCount->hide();
    filterRow->addWidget(m_filterCount);
    filterRow->addStretch(1);
    root->addLayout(filterRow);

    m_body = new QWidget(this);
    m_bodyLayout = new QVBoxLayout(m_body);
    m_bodyLayout->setContentsMargins(0, 0, 0, 0);
    root->addWidget(m_body, 1);
    rebuild();
}

void MilestonesPage::setEnvelope(const std::optional<MilestonesEnvelope> &envelope,
    const LoadStateBox &state)
{
    m_envelope = envelope;
    m_state = state;
    rebuild();
}

void MilestonesPage::setProjectNames(const QStringList &names)
{
    m_projectNames = names;
}

void MilestonesPage::rebuild()
{
    // 清空主体
    while (m_bodyLayout->count() > 0) {
        QLayoutItem *it = m_bodyLayout->takeAt(0);
        if (it->widget())
            it->widget()->deleteLater();
        delete it;
    }
    m_tree = nullptr;

    // ── 仓库筛选条选项 = 明细首现顺序（页面自有状态，不从 selection 推导）──
    if (m_envelope.has_value()) {
        QStringList order;
        for (const Milestone &m : m_envelope->milestones) {
            if (!order.contains(m.projectName))
                order << m.projectName;
        }
        const QString current = m_projectFilter;
        QSignalBlocker block(m_projectBox);
        m_projectBox->clear();
        m_projectBox->addItem(QStringLiteral("全部项目"));
        m_projectBox->addItems(order);
        const int idx = current.isEmpty() ? 0 : m_projectBox->findText(current);
        m_projectBox->setCurrentIndex(qMax(0, idx));
    }

    // ── 判定顺序（刻意）：先 failed → loading → 搜索空 → 列表 ──
    if (m_state.state == LoadState::failed) {
        // 「读取失败」与「真的还没有里程碑」必须长得不同（iconTone 分档，plan §3b）
        m_bodyLayout->addWidget(new EmptyState(EmptyState::Tone::Warning,
            QStringLiteral("里程碑读不出来"), m_state.message));
        return;
    }
    if (m_state.state == LoadState::idle || m_state.state == LoadState::loading
        || !m_envelope.has_value()) {
        auto *loading = new QWidget(m_body);
        auto *v = new QVBoxLayout(loading);
        auto *sp = new DSpinner(loading);
        sp->start();
        auto *lb = new SecondaryLabel(QStringLiteral("读取里程碑…"), loading);
        v->addStretch(1);
        v->addWidget(sp, 0, Qt::AlignHCenter);
        v->addWidget(lb, 0, Qt::AlignHCenter);
        v->addStretch(2);
        m_bodyLayout->addWidget(loading);
        return;
    }

    // 范围收窄 + 搜索过滤
    const QVector<Milestone> scoped = milestonesForProject(m_envelope->milestones, m_projectFilter);
    QVector<Milestone> shown;
    const QString q = m_query.trimmed();
    for (const Milestone &m : scoped) {
        if (q.isEmpty() || m.name.contains(q, Qt::CaseInsensitive))
            shown.append(m);
    }

    // 搜索空两态：本来就没有 / 没匹配上（两句话分开）
    if (shown.isEmpty()) {
        const auto empty = SearchFilter::emptyText(scoped.size(), shown.size(), m_query,
            QStringLiteral("里程碑"));
        m_bodyLayout->addWidget(new EmptyState(QStringLiteral("flag"),
            empty.text,
            empty.reason == SearchFilter::EmptyText::noMatch
                ? QStringLiteral("换个关键词，或清空搜索框看全部。")
                : QStringLiteral("在里程碑页「新建里程碑」创建第一条；tag 出现即自动判定达成。")));
        return;
    }

    // 命中数摘要（过滤生效时）
    const QString matched = SearchFilter::matchedCountText(scoped.size(), shown.size(),
        QStringLiteral("里程碑"));
    if (!matched.isEmpty()) {
        m_filterCount->setText(matched);
        m_filterCount->setVisible(!m_projectFilter.isEmpty() || !q.isEmpty());
    }

    // ── 列表：按项目分组 Section（头 = 项目名 + 「匹配 x / y 个里程碑」）──
    m_tree = new QTreeWidget(m_body);
    m_tree->setColumnCount(1);
    m_tree->header()->hide();
    m_tree->setFrameShape(QFrame::NoFrame);
    m_tree->setRootIsDecorated(false);
    m_tree->setUniformRowHeights(false);
    const auto groups = milestoneGroups(shown);
    for (const auto &g : groups) {
        auto *header = new QTreeWidgetItem(
            { QStringLiteral("%1（%2）").arg(g.first).arg(g.second.size()) });
        header->setFlags(Qt::ItemIsEnabled);
        QFont hf = header->font(0);
        hf.setBold(true);
        header->setFont(0, hf);
        m_tree->addTopLevelItem(header);
        for (const Milestone &m : g.second) {
            auto *item = new QTreeWidgetItem;
            item->setData(0, Qt::UserRole, m.projectName);
            item->setSizeHint(0, QSize(0, 64));
            header->addChild(item);
            auto *row = new MilestoneRowWidget(m_tree);
            row->setMilestone(m, groups.size() > 1);
            connect(row, &MilestoneRowWidget::doneClicked, this,
                [this](const QString &p, const QString &n) { emit statusAction(p, n, "done"); });
            connect(row, &MilestoneRowWidget::reopenClicked, this,
                [this](const QString &p, const QString &n) { emit statusAction(p, n, "reopen"); });
            connect(row, &MilestoneRowWidget::dropClicked, this,
                [this](const QString &p, const QString &n) { emit statusAction(p, n, "drop"); });
            connect(row, &MilestoneRowWidget::removeClicked, this, &MilestonesPage::removeRequested);
            connect(row, &MilestoneRowWidget::openProject, this, &MilestonesPage::goProject);
            m_tree->setItemWidget(item, 0, row);
        }
        header->setExpanded(true);
    }

    // ── 尾部统计 Section（按明细 tally、按当前范围算，不读全局 counts）──
    auto *statItem = new QTreeWidgetItem;
    statItem->setFlags(Qt::ItemIsEnabled);
    m_tree->addTopLevelItem(statItem);
    const MsTally t = milestoneTally(shown, nullptr);
    QStringList segs;
    segs << QStringLiteral("进行中 %1").arg(t.open)
         << QStringLiteral("已达成 %1").arg(t.done)
         << QStringLiteral("已放弃 %1").arg(t.dropped);
    if (t.unknown > 0)
        segs << QStringLiteral("读不出来 %1").arg(t.unknown);
    auto *statWidget = new QWidget(m_tree);
    auto *sv = new QVBoxLayout(statWidget);
    sv->setContentsMargins(DS::Spacing::md, DS::Spacing::sm, DS::Spacing::md, DS::Spacing::sm);
    auto *statTitle = new QLabel(
        m_projectFilter.isEmpty() ? QStringLiteral("全部项目") : QStringLiteral("%1 的里程碑").arg(m_projectFilter),
        statWidget);
    statTitle->setFont(DS::font(DS::FontT::cardTitle));
    sv->addWidget(statTitle);
    auto *statLine = new SecondaryLabel(segs.join(QStringLiteral(" · ")), statWidget);
    sv->addWidget(statLine);
    // 明细 ≠ readCount → 披露「下界」。对账对象是**引擎信封**（milestones.size() vs
    // readCount），不是搜索/项目筛选后的 shown——筛选是用户意图，不是引擎截断；
    // 无截断时此行不许出现（警告常亮 = 警告失效，摆而不动家族）。
    const bool engineTruncated = m_envelope.has_value()
        && m_envelope->milestones.size() != m_envelope->readCount;
    if (engineTruncated && m_envelope->readCount > 0 && m_projectFilter.isEmpty()) {
        auto *disclosure = new QLabel(
            QStringLiteral("明细只给了 %1 条，引擎读到 %2 条 —— 上面按明细统计，不是全量")
                .arg(m_envelope->milestones.size())
                .arg(m_envelope->readCount),
            statWidget);
        disclosure->setFont(DS::font(DS::FontT::label));
        disclosure->setStyleSheet(
            QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
        disclosure->setWordWrap(true);
        sv->addWidget(disclosure);
    }
    statItem->setSizeHint(0, QSize(0, statWidget->sizeHint().height()));
    m_tree->setItemWidget(statItem, 0, statWidget);

    m_bodyLayout->addWidget(m_tree, 1);
    connect(m_tree, &QTreeWidget::itemClicked, this, [this](QTreeWidgetItem *item) {
        const QString p = item->data(0, Qt::UserRole).toString();
        if (!p.isEmpty())
            emit goProject(p);
    });
}
