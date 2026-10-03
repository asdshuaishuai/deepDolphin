#include "BoardPage.h"
#include "../../app/AppModel.h"
#include "../../logic/DashFilter.h"
#include "../../logic/Derived.h"
#include "../DesignTokens.h"
#include "../common/Chip.h"
#include "../common/SecondaryLabel.h"
#include <QHBoxLayout>
#include <QHeaderView>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>

namespace {
// BoardCardWidget：名称+状态词+headline+warnings 橙+Chips+底排。
// 无 Q_OBJECT（局部辅助类）：按钮动作走 std::function 回调。
// 全部子控件 WA_TransparentForMouseEvents → 点击整卡命中（点卡片 = go(.project)）。
class BoardCardWidget : public QWidget {
public:
    explicit BoardCardWidget(const ProjectStatus &p,
        std::function<void(const QString &)> onShallow,
        std::function<void(const QString &)> onBrief, QWidget *parent = nullptr)
        : QWidget(parent)
        , m_name(p.name)
    {
        auto *v = new QVBoxLayout(this);
        v->setContentsMargins(DS::Spacing::md, DS::Spacing::sm, DS::Spacing::md, DS::Spacing::sm);
        v->setSpacing(4);

        auto *row1 = new QHBoxLayout;
        auto *name = new QLabel(p.name, this);
        QFont f = name->font();
        f.setWeight(QFont::DemiBold);
        name->setFont(f);
        row1->addWidget(name);
        row1->addStretch(1);
        const auto sw = Derived::stateWord(p);
        auto *state = new QLabel(sw.text, this);
        state->setFont(DS::font(DS::FontT::label));
        state->setStyleSheet(QStringLiteral("color: %1;").arg(Derived::livenessColor(sw.tone).name()));
        row1->addWidget(state);
        v->addLayout(row1);

        if (!p.headline.isEmpty() || p.isUnreadable()) {
            auto *headline = new QLabel(
                p.isUnreadable() ? p.error.value_or(QStringLiteral("读不出来")) : p.headline, this);
            headline->setStyleSheet(p.isUnreadable()
                    ? QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::red).name())
                    : QStringLiteral("color: %1;").arg(DS::textSecondary().name()));
            headline->setWordWrap(true);
            v->addWidget(headline);
        }
        for (const QString &w : p.warnings) {
            auto *warn = new QLabel(w, this);
            warn->setStyleSheet(
                QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
            warn->setWordWrap(true);
            warn->setFont(DS::font(DS::FontT::label));
            v->addWidget(warn);
        }

        // Chips：●N 橙 / 未跟踪 N / stash N / 「N 待记录」蓝 / 「分支 <名>」
        auto *chips = new QHBoxLayout;
        chips->setSpacing(DS::Spacing::xs);
        auto addChip = [&chips, this](const QString &text, DS::SemColor tone) {
            auto *chip = new Chip(text, this);
            chip->setTone(tone);
            chips->addWidget(chip);
        };
        if (p.userDirtyCount > 0)
            addChip(QStringLiteral("●%1").arg(p.userDirtyCount), DS::SemColor::orange);
        if (p.untrackedCount > 0)
            addChip(QStringLiteral("未跟踪 %1").arg(p.untrackedCount), DS::SemColor::orange);
        if (p.stashCount > 0)
            addChip(QStringLiteral("stash %1").arg(p.stashCount), DS::SemColor::yellow);
        if (const BranchStatus *pb = Derived::primaryBranch(p)) {
            if (pb->pendingCommits > 0)
                addChip(QStringLiteral("%1 待记录").arg(pb->pendingCommits), DS::SemColor::accent);
        }
        if (!p.currentBranch.isEmpty())
            addChip(QStringLiteral("分支 %1").arg(p.currentBranch), DS::SemColor::gray);
        chips->addStretch(1);
        v->addLayout(chips);

        // 底排：浅更新 + AI 说明 + 右侧「N 天前提交」/「提交时间读不出来」
        auto *bottom = new QHBoxLayout;
        bottom->setSpacing(DS::Spacing::sm);
        auto *shallow = new QPushButton(QStringLiteral("浅更新"), this);
        shallow->setFlat(true);
        connect(shallow, &QPushButton::clicked, this,
            [this, onShallow] { if (onShallow) onShallow(m_name); });
        bottom->addWidget(shallow);
        auto *brief = new QPushButton(QStringLiteral("AI 说明"), this);
        brief->setFlat(true);
        connect(brief, &QPushButton::clicked, this,
            [this, onBrief] { if (onBrief) onBrief(m_name); });
        bottom->addWidget(brief);
        bottom->addStretch(1);
        QString ageText;
        if (p.isUnreadable())
            ageText = p.error.value_or(QStringLiteral("读不出来"));
        else if (const auto age = Derived::daysSinceLastCommit(p); age.has_value())
            ageText = QStringLiteral("%1 天前提交").arg(*age);
        else
            ageText = QStringLiteral("提交时间读不出来");
        auto *age = new SecondaryLabel(ageText, this);
        age->setFont(DS::font(DS::FontT::label));
        bottom->addWidget(age);
        v->addLayout(bottom);

        // 子控件透鼠标，让点击整卡命中（按钮除外）：
        // 复刻侧对「.badge 吃点击」缺陷的等价防御。
        const QList<QWidget *> kids = findChildren<QWidget *>();
        for (QWidget *child : kids) {
            if (child != shallow && child != brief)
                child->setAttribute(Qt::WA_TransparentForMouseEvents);
        }
    }

    QString m_name;
};
} // namespace

BoardPage::BoardPage(QWidget *parent)
    : QWidget(parent)
{
    auto *v = new QVBoxLayout(this);
    v->setContentsMargins(DS::Spacing::xxl, DS::Spacing::lg, DS::Spacing::xxl, DS::Spacing::xxl);
    auto *title = new QLabel(QStringLiteral("现在哪些项目要我动手"), this);
    title->setFont(DS::font(DS::FontT::sectionTitle));
    v->addWidget(title);
    m_tree = new QTreeWidget(this);
    m_tree->setColumnCount(1);
    m_tree->header()->hide();
    m_tree->setFrameShape(QFrame::NoFrame);
    m_tree->setRootIsDecorated(false);
    m_tree->setUniformRowHeights(false);
    m_tree->setSelectionMode(QAbstractItemView::SingleSelection);
    v->addWidget(m_tree, 1);
    connect(m_tree, &QTreeWidget::itemClicked, this, [this](QTreeWidgetItem *item) {
        const QString name = item->data(0, Qt::UserRole).toString();
        if (!name.isEmpty())
            emit goProject(name);
    });
}

void BoardPage::setModel(AppModel *model)
{
    m_model = model;
    // 与 DashboardPage 同一组订阅：dashboardChanged 是启动路径唯一保证广播的信号
    //（fetchDashboard 完成时），只认 projectsChanged 会漏掉首轮数据
    connect(model, &AppModel::dashboardChanged, this, &BoardPage::rebuild);
    connect(model, &AppModel::projectsChanged, this, &BoardPage::rebuild);
    connect(model, &AppModel::dashFilterChanged, this, &BoardPage::rebuild);
    rebuild();
}

void BoardPage::rebuild()
{
    m_tree->clear();
    if (!m_model || m_model->projects().empty())
        return;

    // 同一份筛选状态（与仪表盘共用）
    QVector<const ProjectStatus *> kept;
    for (const ProjectStatus &p : m_model->projects()) {
        if (m_model->dashFilter().keeps(p))
            kept.append(&p);
    }

    // 列映射只读 liveness（needsAction→待处理；engineStale/quiet→久未更新；
    // recent→活跃中；unreadable/notGit/unknown→其他）
    constexpr Derived::BoardColumn kColumns[4] = { Derived::BoardColumn::attention,
        Derived::BoardColumn::active, Derived::BoardColumn::stale, Derived::BoardColumn::other };
    for (const Derived::BoardColumn col : kColumns) {
        QVector<const ProjectStatus *> rows;
        for (const ProjectStatus *p : kept) {
            if (Derived::boardColumn(*p) == col)
                rows.append(p);
        }
        // 列头计数与列出行数**严格一致**（同一份数据渲染两处）
        auto *header = new QTreeWidgetItem(
            { QStringLiteral("%1（%2）").arg(Derived::boardColumnTitle(col)).arg(rows.size()) });
        header->setFlags(Qt::ItemIsEnabled);
        QFont hf = header->font(0);
        hf.setBold(true);
        header->setFont(0, hf);
        m_tree->addTopLevelItem(header);

        if (rows.isEmpty()) {
            // 空列：显示判定依据原文
            auto *basis = new QTreeWidgetItem({ Derived::boardColumnBasis(col) });
            basis->setFlags(Qt::NoItemFlags);
            basis->setForeground(0, palette().mid());
            header->addChild(basis);
            header->setExpanded(true);
            continue;
        }
        for (const ProjectStatus *p : rows) {
            auto *item = new QTreeWidgetItem;
            item->setData(0, Qt::UserRole, p->name);
            item->setSizeHint(0, QSize(0, 96));
            // 行挂在**所属列头**下（与空列判定行同层）：挂顶层会让四列退化成
            // 「四个头 + 一串平铺行」，列头计数与列出行数严格一致被破坏
            header->addChild(item);
            auto *card = new BoardCardWidget(*p,
                [this](const QString &name) { emit shallowFor(name); },
                [this](const QString &name) { emit briefFor(name); }, m_tree);
            m_tree->setItemWidget(item, 0, card);
        }
        header->setExpanded(true); // addChild 默认折叠：不展开列内容不可见
    }
    // 去掉多余的编辑态
    m_tree->setFocusPolicy(Qt::ClickFocus);
}
