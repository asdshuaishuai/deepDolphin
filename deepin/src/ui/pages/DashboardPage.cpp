#include "DashboardPage.h"
#include "DashboardFilterBar.h"
#include "ProjectProgressCard.h"
#include "../../app/AppModel.h"
#include "../../logic/CommitTypeComposition.h"
#include "../../logic/DashboardScope.h"
#include "../../logic/Derived.h"
#include "../../platform/DpiPixmap.h"
#include "../../logic/LanguageCoverage.h"
#include "../../logic/MilestoneCardTitle.h"
#include "../DesignTokens.h"
#include "../common/EmptyState.h"
#include "../common/FlatButton.h"
#include "../common/FlowLayout.h"
#include "../common/LegendRow.h"
#include "../common/SecondaryLabel.h"
#include "../common/SegmentedBar.h"
#include <DPushButton>
#include <DSpinner>
#include <QGridLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <DProgressBar>
#include <QPushButton>
#include <QVBoxLayout>

DWIDGET_USE_NAMESPACE

namespace {
// ⚠ **活跃项目摘要的定宽上限**（批 AO）：headline 来自引擎，长度不受控。
//   原来这个 300 是**裸字面量**写在调用点（且是「硬裁」而非省略号）。
//   ⇒ 提到本地常量并与省略号口径绑在一起（同 SidebarNav 的 kProjectNameMaxPx 做法）。
constexpr int kActiveHeadlineMaxPx = 300;
} // namespace

DashboardPage::DashboardPage(QWidget *parent)
    : QWidget(parent)
{
    auto *outer = new QVBoxLayout(this);
    outer->setContentsMargins(0, 0, 0, 0);
    m_scroll = new DScrollArea(this);
    m_scroll->setFrameShape(QFrame::NoFrame);
    m_scroll->setWidgetResizable(true);
    m_content = new QWidget(this);
    m_contentLayout = new QVBoxLayout(m_content);
    m_contentLayout->setContentsMargins(DS::Spacing::xxl, DS::Spacing::lg, DS::Spacing::xxl,
        DS::Spacing::xxl);
    m_contentLayout->setSpacing(DS::Spacing::lg);
    m_scroll->setWidget(m_content);
    outer->addWidget(m_scroll);
}

void DashboardPage::setModel(AppModel *model)
{
    m_model = model;
    // 筛选行的信号在 rebuild() 里建 m_filterBar 时逐实例连接（m_filterBar 每轮重建）
    connect(model, &AppModel::dashboardChanged, this, &DashboardPage::rebuild);
    connect(model, &AppModel::projectsChanged, this, &DashboardPage::rebuild);
    connect(model, &AppModel::dashFilterChanged, this, &DashboardPage::rebuild);
    rebuild();
}

void DashboardPage::rebuild()
{
    // 清空重建
    while (m_contentLayout->count() > 0) {
        QLayoutItem *it = m_contentLayout->takeAt(0);
        if (it->widget())
            it->widget()->deleteLater();
        delete it;
    }

    if (!m_model || !m_model->engineFound()) {
        m_contentLayout->addWidget(new EmptyState(EmptyState::Tone::Warning,
            QStringLiteral("引擎未找到"), QStringLiteral("安装引擎后「重新检测引擎」即可开始。")));
        return;
    }

    // ── 相位判定（每数据源一份自己的 LoadState；SPEC §3.5 四分支）──
    const LoadStateBox st = m_model->dashboardState();
    if (st.state == LoadState::failed) {
        m_contentLayout->addWidget(new EmptyState(EmptyState::Tone::Warning,
            QStringLiteral("仪表盘读不出来"), st.message));
        return;
    }
    if (st.state == LoadState::idle || st.state == LoadState::loading) {
        auto *loading = new QWidget(this);
        auto *v = new QVBoxLayout(loading);
        auto *sp = new DSpinner(loading);
        sp->start();
        auto *lb = new SecondaryLabel(QStringLiteral("汇总项目群…"), loading);
        v->addStretch(1);
        v->addWidget(sp, 0, Qt::AlignHCenter);
        v->addWidget(lb, 0, Qt::AlignHCenter);
        v->addStretch(2);
        m_contentLayout->addWidget(loading);
        return;
    }
    if (m_model->projects().empty()) {
        // 主 CTA 槽位（plan §3b）：空态给「下一步」——「添加 / 扫描项目」（与侧栏同一动作）。
        // 空态主 CTA 保持实底钮，不随 FlatButton 收编（同「主操作不降平钮」口径）
        auto *addBtn = new DPushButton(QStringLiteral("添加 / 扫描项目"), m_content);
        addBtn->setToolTip(QStringLiteral("注册项目后运行一次浅更新，仪表盘开始出数"));
        connect(addBtn, &QPushButton::clicked, this, &DashboardPage::addScanRequested);
        m_contentLayout->addWidget(new EmptyState(IconNames::Id::folderNew,
            QStringLiteral("仪表盘还没有数据"),
            QStringLiteral("注册项目后运行一次浅更新，这里会出现项目群脉搏。"), addBtn));
        return;
    }

    // ── 页头 ──
    auto *header = new QWidget(m_content);
    auto *hv = new QVBoxLayout(header);
    hv->setContentsMargins(0, 0, 0, 0);
    hv->setSpacing(DS::Spacing::xs);
    auto *title = new QLabel(QStringLiteral("项目群脉搏"), header);
    title->setFont(DS::font(DS::FontT::sectionTitle));
    hv->addWidget(title);

    const KpiSet k = kpis(*m_model->dashboard(), m_model->projects());
    auto *hr = new QHBoxLayout;
    m_summary = new SecondaryLabel(summaryLine(k), header);
    hr->addWidget(m_summary, 1);
    auto *brief = new FlatButton(header);
    brief->setText(QStringLiteral("项目群说明"));
    brief->setToolTip(QStringLiteral("AI 项目群说明（未配置 AI 时会给出配置指引）"));
    connect(brief, &QPushButton::clicked, this, &DashboardPage::briefRequested);
    hr->addWidget(brief);
    hv->addLayout(hr);
    m_contentLayout->addWidget(header);

    // ── 筛选行 ──
    m_filterBar = new DashboardFilterBar(m_content);
    m_filterBar->setFilter(m_filter);
    QStringList types;
    for (const ProjectStatus &p : m_model->projects()) {
        for (const CommitTypeStat &c : p.commitTypes) {
            if (!types.contains(c.type))
                types << c.type;
        }
    }
    types.sort();
    m_filterBar->setTypeOptions(types, !types.isEmpty(),
        QStringLiteral("当前项目群没有提交类型样本（跑一次浅更新后出现）"));
    connect(m_filterBar, &DashboardFilterBar::windowChanged, this, [this](TimeWindow w) {
        m_filter.window = w;
        if (m_model)
            m_model->setDashFilter(m_filter);
        rebuild();
    });
    connect(m_filterBar, &DashboardFilterBar::typeChanged, this, [this](const QString &t) {
        m_filter.commitType = t;
        if (m_model)
            m_model->setDashFilter(m_filter);
        rebuild();
    });
    connect(m_filterBar, &DashboardFilterBar::reindexClicked, this, [this] {
        if (!m_model || m_reindexing)
            return;
        m_reindexing = true;
        m_filterBar->setReindexBusy(true);
        m_model->updateAll(false, true, [this](const AgentBulkReport &) {
            m_reindexing = false;
            m_filterBar->setReindexBusy(false);
            rebuild();
        });
    });
    m_contentLayout->addWidget(m_filterBar);

    // ── KPI 4 卡（QGridLayout；**固定两行两列**）──
    // ⚠ **实测订正（批 AM）**：这段注释原来声称「窗宽 <980 时会折成 2 列」，
    //   而**代码里根本没有那种折行机制**（4 张卡写死在 (0,0)(0,1)(1,0)(1,1)）
    //   ⇒ 说法与实现相反（与批 AI 的 `Notifier.h` 同类：注释比实现还自信）。
    //   ⇒ 现在按**实际行为**写：固定 2×2。
    // ⚠ 为什么**不做** 1/2/4 列响应式（PLAN §3c 原提案）：实测 mac 侧是
    //   **固定 4 列**（`macos/Sources/deepDolphin/DetailViews.swift:902-903`
    //   `LazyVGrid(count: 4)`）⇒ 「按窗宽 1/2/4」是 deepin 侧的提案，**无 mac 对位**；
    //   而 2×2 在窄窗口下仍可读（宽窗口则两列各自拉宽）⇒ 保持 2×2。
    //   ⚠ 将来若真要响应式：**改这里 + 补判定层**（列数判定不许写在 resizeEvent 里
    //   ——那样无头测不到），别只改一半。
    auto *kpiHost = new QWidget(m_content);
    auto *kpiGrid = new QGridLayout(kpiHost);
    kpiGrid->setContentsMargins(0, 0, 0, 0);
    kpiGrid->setSpacing(DS::Spacing::md);
    const auto mkCard = [&](const QString &t, const QString &v, const QStringList &sub, bool tinted,
                            QWidget *bar) {
        auto *card = new Card(kpiHost);
        auto *cv = new QVBoxLayout(card);
        cv->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
        cv->setSpacing(DS::Spacing::xs);
        auto *tLabel = new QLabel(t, card);
        tLabel->setFont(DS::font(DS::FontT::cardTitle));
        cv->addWidget(tLabel);
        auto *vLabel = new QLabel(v, card);
        vLabel->setFont(DS::font(DS::FontT::metric));
        if (tinted)
            vLabel->setStyleSheet(
                QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
        cv->addWidget(vLabel);
        if (bar)
            cv->addWidget(bar);
        auto *subLabel = new SecondaryLabel(sub.join(QStringLiteral(" · ")), card);
        subLabel->setFont(DS::font(DS::FontT::label));
        subLabel->setWordWrap(true);
        cv->addWidget(subLabel);
        return card;
    };
    QProgressBar *msBar = nullptr; // DProgressBar 即 QProgressBar 子类
    if (k.milestoneProgress >= 0) {
        msBar = new DProgressBar(kpiHost);
        msBar->setRange(0, 100);
        msBar->setValue(k.milestonePct);
        msBar->setTextVisible(false);
        msBar->setFixedHeight(DS::Height::bar);
    }
    kpiGrid->addWidget(mkCard(QStringLiteral("项目总数"), QString::number(k.projects), k.totalSub,
                           false, nullptr),
        0, 0);
    kpiGrid->addWidget(mkCard(QStringLiteral("里程碑完成率"), QStringLiteral("%1%").arg(k.milestonePct),
                           k.milestoneSub, false, msBar),
        0, 1);
    kpiGrid->addWidget(mkCard(QStringLiteral("待处理"), QString::number(k.needsAction), k.needsSub,
                           k.needsActionTinted, nullptr),
        1, 0);
    kpiGrid->addWidget(mkCard(QStringLiteral("分支"), QString::number(k.branchSum), k.branchSub,
                           false, nullptr),
        1, 1);
    m_contentLayout->addWidget(kpiHost);

    // ── 逐项目卡网格（只列过时间窗筛选的项目；读不出时间的项目始终保留）──
    auto *projHead = new QWidget(m_content);
    auto *ph = new QHBoxLayout(projHead);
    ph->setContentsMargins(0, 0, 0, 0);
    auto *projTitle = new QLabel(QStringLiteral("各项目演进进度与里程碑明细"), projHead);
    projTitle->setFont(DS::font(DS::FontT::cardTitle));
    ph->addWidget(projTitle);
    ph->addStretch(1);
    QVector<const ProjectStatus *> kept;
    int total = 0;
    for (const ProjectStatus &p : m_model->projects()) {
        ++total;
        if (m_filter.keeps(p))
            kept.append(&p);
    }
    QString countText;
    if (m_filter.window == TimeWindow::all)
        countText = QStringLiteral("共 %1 个项目").arg(kept.size());
    else
        countText = QStringLiteral("%1/%2 个项目（最近更新在 %3）")
                        .arg(kept.size())
                        .arg(total)
                        .arg(m_filter.windowLabel());
    auto *countLabel = new SecondaryLabel(countText, projHead);
    countLabel->setFont(DS::font(DS::FontT::label));
    ph->addWidget(countLabel);
    m_contentLayout->addWidget(projHead);

    auto *flowHost = new QWidget(m_content);
    auto *flow = new FlowLayout(flowHost, 0, DS::Spacing::md, DS::Spacing::md);
    flow->setItemFixedWidth(440);
    // 每项目的里程碑明细 tally（按项目收窄；收窄的是明细，全局 counts 不再往下传）
    const QVector<Milestone> allItems(m_model->dashboard()->milestones.items.begin(),
        m_model->dashboard()->milestones.items.end());
    const auto groups = milestoneGroups(allItems);
    QMap<QString, MsTally> msByProject;
    for (const auto &g : groups)
        msByProject.insert(g.first, milestoneTally(g.second, nullptr));
    if (kept.isEmpty()) {
        // 卡内空态 = EmptyState::compact（iconTone 分档，plan §3b；原一句话裸标签无图标）
        flow->addWidget(EmptyState::compact(EmptyState::Tone::Empty,
            QStringLiteral("读不出更新时间的项目始终保留，不会被筛掉。当前筛选下没有项目。"),
            flowHost));
    } else {
        for (const ProjectStatus *p : kept) {
            auto *card = new ProjectProgressCard(flowHost);
            const MsTally ms = msByProject.value(p->name);
            card->setProject(*p, m_filter, msByProject.contains(p->name) ? &ms : nullptr);
            connect(card, &ProjectProgressCard::goProject, this, &DashboardPage::goProject);
            flow->addWidget(card);
        }
    }
    m_contentLayout->addWidget(flowHost);

    // ── 语言分布卡 ──
    m_contentLayout->addWidget(buildLanguagesCard());
    // ── 里程碑卡 ──
    m_contentLayout->addWidget(buildMilestonesCard());
    // ── 近 7 天活跃卡 ──
    if (!m_model->dashboard()->activeProjects.empty())
        m_contentLayout->addWidget(buildActiveCard());

    m_contentLayout->addStretch(1);
}

QWidget *DashboardPage::buildLanguagesCard()
{
    auto *card = new Card(this);
    auto *v = new QVBoxLayout(card);
    v->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
    v->setSpacing(DS::Spacing::sm);
    auto *title = new QLabel(QStringLiteral("语言分布（跟踪文件数）"), card);
    title->setFont(DS::font(DS::FontT::cardTitle));
    v->addWidget(title);

    const auto cov = LanguageCoverage::coverage(*m_model->dashboard());
    if (cov.rows.isEmpty()) {
        // 「空」与「读不出来」图标分档（plan §3b）：采集失败（failed>0）是读不出来，
        // 不是「这个项目群没有语言」——语言口径在 logic 层，图标档在这里跟着 failed 走
        const EmptyState::Tone tone = m_model->dashboard()->languagesFailed > 0
            ? EmptyState::Tone::Warning
            : EmptyState::Tone::Empty;
        v->addWidget(EmptyState::compact(tone, cov.emptyTitle, card));
    } else {
        auto *bar = new SegmentedBar(card);
        bar->setData(cov.barData);
        v->addWidget(bar);
        auto *legend = new LegendRow(card);
        QVector<QPair<QColor, QString>> entries;
        for (int i = 0; i < cov.rows.size(); ++i)
            entries.append({ cov.barData.at(i).first,
                QStringLiteral("%1 %2").arg(cov.rows.at(i).first).arg(cov.rows.at(i).second) });
        legend->setEntries(entries);
        v->addWidget(legend);
    }
    if (!cov.note.isEmpty()) {
        auto *note = new QLabel(cov.note, card);
        note->setFont(DS::font(DS::FontT::label));
        note->setStyleSheet(QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
        note->setWordWrap(true);
        v->addWidget(note);
    }
    return card;
}

QWidget *DashboardPage::buildMilestonesCard()
{
    auto *card = new Card(this);
    auto *v = new QVBoxLayout(card);
    v->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
    v->setSpacing(DS::Spacing::sm);

    const DashboardData &d = *m_model->dashboard();
    const MilestoneCounts &counts = d.milestones.counts;
    auto *title = new QLabel(MilestoneCard::title(counts, counts.excludedDisabled, counts.orphaned,
                                 counts.storeHealth),
        card);
    title->setFont(DS::font(DS::FontT::cardTitle));
    title->setWordWrap(true);
    v->addWidget(title);

    // degraded 空态：读不出来（不是「没有」）——Warning 档图标承载区分（plan §3b；
    // 原橙字让位给告警图标，语义色不进卡内正文）
    if (counts.degraded && d.milestones.items.empty()) {
        v->addWidget(EmptyState::compact(EmptyState::Tone::Warning,
            QStringLiteral("里程碑读不出来（不是「没有」）"), card));
        return card;
    }
    if (d.milestones.items.empty()) {
        v->addWidget(
            EmptyState::compact(EmptyState::Tone::Empty, QStringLiteral("还没有里程碑"), card));
        return card;
    }

    const int shown = MilestoneCard::shownCount(static_cast<int>(d.milestones.items.size()));
    for (int i = 0; i < shown; ++i) {
        const Milestone &m = d.milestones.items.at(i);
        auto *row = new QLabel(
            QStringLiteral("%1 · %2（%3）").arg(m.projectName, m.name,
                Derived::milestoneStatusLabel(m)),
            card);
        row->setFont(DS::font(DS::FontT::body));
        row->setStyleSheet(QStringLiteral("color: %1;").arg(DS::textPrimary().name()));
        v->addWidget(row);
    }
    const QString note = MilestoneCard::sliceNote(static_cast<int>(d.milestones.items.size()));
    if (!note.isEmpty()) {
        auto *noteLabel = new QLabel(note, card);
        noteLabel->setFont(DS::font(DS::FontT::label));
        noteLabel->setStyleSheet(
            QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
        v->addWidget(noteLabel);
    }
    return card;
}

QWidget *DashboardPage::buildActiveCard()
{
    auto *card = new Card(this);
    auto *v = new QVBoxLayout(card);
    v->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
    v->setSpacing(DS::Spacing::sm);
    auto *title = new QLabel(QStringLiteral("近 7 天活跃项目"), card);
    title->setFont(DS::font(DS::FontT::cardTitle));
    v->addWidget(title);
    for (const DashboardActiveProject &a : m_model->dashboard()->activeProjects) {
        auto *row = new QWidget(card);
        auto *h = new QHBoxLayout(row);
        h->setContentsMargins(0, 0, 0, 0);
        h->setSpacing(DS::Spacing::sm);
        auto *dot = new QLabel(row);
        // ⚠ **HiDPI 感知**（批 AP · M3c）：按 dpr 放大后画。
        QPixmap pm = platform::dpiPixmap(QSize(DS::Height::dot, DS::Height::dot)); // 状态点统一 8px（M3-5）
        pm.fill(Qt::transparent);
        QPainter p(&pm);
        p.setRenderHint(QPainter::Antialiasing);
        p.setPen(Qt::NoPen);
        p.setBrush(DS::semColor(DS::SemColor::shallow));
        p.drawEllipse(0, 0, DS::Height::dot, DS::Height::dot);
        dot->setPixmap(pm);
        auto *name = new QLabel(a.name, row);
        h->addWidget(dot);
        h->addWidget(name);
        auto *ago = new SecondaryLabel(a.lastCommitAgo, row);
        h->addWidget(ago);
        h->addStretch(1);
        auto *headline = new SecondaryLabel(a.headline, row);
        // ⚠ **省略号，不是硬裁**（批 AO）：headline 来自**引擎**（`DocumentIntegrity::headline`）
        //   ⇒ 长度不受我们控制（实测可到「状态读不出来」这种整句，也可能更长）；
        //   原来只 `setMaximumWidth(300)` ⇒ QLabel 默认**直接切掉后半截**（半个字、无提示）
        //   ⇒ 用户看到「一切正」不知道后面是什么。
        //   ⇒ 按可用宽度算省略号，**完整文进 tooltip**（鼠标悬停能看全）。
        //   ⚠ mac 侧对位 `DashboardParts.swift` 用的是 `Text(...)`（SwiftUI 自动截断 + 可悬停）
        //   ⇒ 「省略号 + 完整可查」是**两边一致**的口径。
        headline->setText(headline->fontMetrics().elidedText(
            a.headline, Qt::ElideRight, kActiveHeadlineMaxPx));
        headline->setToolTip(a.headline);
        v->addWidget(row);
    }
    return card;
}
