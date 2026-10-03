#include "ProjectProgressCard.h"
#include "../../logic/CommitTypeComposition.h"
#include "../../logic/Derived.h"
#include "../DesignTokens.h"
#include "../common/Chip.h"
#include "../common/LegendRow.h"
#include "../common/FlatButton.h"
#include "../common/SecondaryLabel.h"
#include "../common/SegmentedBar.h"
#include "../common/Card.h"
#include "../../models/ProjectStatus.h"
#include <QHBoxLayout>
#include <QLabel>
#include <QMouseEvent>
#include <QPainter>
#include <QVBoxLayout>
#include <QPushButton>

namespace {
// 「这条项目该显示哪个分支」三级回退：primaryBranch → currentBranch 字符串 → 「无分支记录」。
// 分支数组是**追踪数组**，空 ≠ 没有分支（无远端基线的仓库它恒空）。
QString branchDisplayName(const ProjectStatus &p)
{
    if (const BranchStatus *pb = Derived::primaryBranch(p))
        return pb->name;
    if (!p.currentBranch.isEmpty())
        return p.currentBranch;
    return QStringLiteral("无分支记录");
}
} // namespace

ProjectProgressCard::ProjectProgressCard(QWidget *parent)
    : QWidget(parent)
{
    setCursor(Qt::PointingHandCursor);
    setToolTipDuration(0);
}

void ProjectProgressCard::setProject(const ProjectStatus &p, const DashFilter &filter,
    const MsTally *ms)
{
    m_name = p.name;
    delete layout(); // 整卡重建（卡片数 ≤ 数十，代价可忽略）

    auto *outer = new QVBoxLayout(this);
    outer->setContentsMargins(0, 0, 0, 0);
    auto *card = new Card(this);
    outer->addWidget(card);
    auto *v = new QVBoxLayout(card);
    v->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
    v->setSpacing(DS::Spacing::sm);

    // ── 行 1：项目名（等宽，中段截断）+ 状态词（圆点，色随 tone）──
    auto *row1 = new QHBoxLayout;
    auto *name = new QLabel(p.name, card);
    QFont mono(QStringLiteral("monospace"));
    mono.setStyleHint(QFont::Monospace);
    mono.setWeight(QFont::DemiBold);
    mono.setPixelSize(13);
    name->setFont(mono);
    name->setMaximumWidth(220);
    name->setTextInteractionFlags(Qt::NoTextInteraction);
    // 中段截断：名称过长时掐中间（/path/to/project 的尾部是目录名，比掐尾部更有用）
    QString shown = p.name;
    if (shown.size() > 24) {
        const int keep = 10;
        shown = shown.left(keep) + QStringLiteral("…") + shown.right(keep);
    }
    name->setText(shown);
    row1->addWidget(name, 1);

    const Derived::StateWord sw = Derived::stateWord(p);
    auto *dot = new QLabel(card);
    QPixmap pm(DS::Height::dot, DS::Height::dot); // 状态点统一 8px（M3-5）
    pm.fill(Qt::transparent);
    QPainter dp(&pm);
    dp.setRenderHint(QPainter::Antialiasing);
    dp.setPen(Qt::NoPen);
    dp.setBrush(Derived::livenessColor(sw.tone));
    dp.drawEllipse(0, 0, DS::Height::dot, DS::Height::dot);
    dot->setPixmap(pm);
    auto *state = new QLabel(sw.text, card);
    state->setFont(DS::font(DS::FontT::label));
    state->setStyleSheet(QStringLiteral("color: %1;").arg(Derived::livenessColor(sw.tone).name()));
    row1->addWidget(dot);
    row1->addWidget(state);
    v->addLayout(row1);

    // ── 行 2：headline（unreadable 时显示 error 红）──
    auto *headline = new QLabel(
        p.isUnreadable() ? p.error.value_or(QStringLiteral("读不出来"))
                         : (p.headline.isEmpty() ? QStringLiteral("—") : p.headline),
        card);
    headline->setWordWrap(true);
    headline->setStyleSheet(
        p.isUnreadable() ? QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::red).name())
                         : QStringLiteral("color: %1;").arg(DS::textSecondary().name()));
    v->addWidget(headline);

    // ── 行 3：里程碑完成度 + 右侧「分支 <名>」──
    auto *row3 = new QHBoxLayout;
    QLabel *msLabel = nullptr;
    if (ms == nullptr || (ms->done + ms->open) == 0) {
        if (ms != nullptr && ms->unknown > 0) {
            msLabel = new QLabel(QStringLiteral("里程碑读不出来（%1 个）").arg(ms->unknown), card);
            msLabel->setStyleSheet(
                QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
        } else {
            msLabel = new SecondaryLabel(QStringLiteral("未设里程碑"), card);
        }
    } else {
        const int decided = ms->done + ms->open;
        const int pct = qRound(ms->done * 100.0 / decided);
        msLabel = new SecondaryLabel(
            QStringLiteral("%1/%2 · %3%").arg(ms->done).arg(decided).arg(pct), card);
    }
    msLabel->setFont(DS::font(DS::FontT::label));
    row3->addWidget(msLabel);
    row3->addStretch(1);
    auto *branch = new SecondaryLabel(QStringLiteral("分支 %1").arg(branchDisplayName(p)), card);
    branch->setFont(DS::font(DS::FontT::label));
    row3->addWidget(branch);
    v->addLayout(row3);

    // ── 行 4：提交结构（受提交类型筛选；空→说明；样本截断→「样本」橙标）──
    const auto entries = CommitTypes::filtered(CommitTypes::toEntries(p.commitTypes),
        filter.commitType);
    if (entries.isEmpty()) {
        auto *empty = new SecondaryLabel(QStringLiteral("该筛选下这个项目没有匹配的提交类型"), card);
        empty->setFont(DS::font(DS::FontT::label));
        v->addWidget(empty);
    } else {
        auto *bar = new SegmentedBar(card);
        QVector<QPair<QColor, int>> barData;
        QVector<QPair<QColor, QString>> legend;
        const int capped = qMin<int>(entries.size(), CommitTypes::PALETTE_CAPACITY);
        for (int i = 0; i < capped; ++i) {
            const QColor c = CommitTypes::sequenceColor(i);
            barData.append({ c, entries.at(i).second });
            legend.append({ c, QStringLiteral("%1 ×%2").arg(entries.at(i).first,
                entries.at(i).second) });
        }
        bar->setData(barData);
        v->addWidget(bar);
        auto *legendRow = new LegendRow(card);
        legendRow->setEntries(legend);
        v->addWidget(legendRow);
        if (p.commitTypesTruncated) {
            auto *sample = new Chip(QStringLiteral("样本"), card);
            sample->setTone(DS::SemColor::orange);
            sample->setToolTip(QStringLiteral("提交类型是引擎的最近样本，非全量"));
            auto *sampleRow = new QHBoxLayout;
            sampleRow->setContentsMargins(0, 0, 0, 0);
            sampleRow->addWidget(sample);
            sampleRow->addStretch(1);
            v->addLayout(sampleRow);
        }
    }

    // ── 行 5：最近提交 / 「分支明细未纳入追踪（提交类型分布仍可用）」+「进入管控 →」──
    auto *row5 = new QHBoxLayout;
    const BranchStatus *pb = Derived::primaryBranch(p);
    QString recentText;
    if (pb && !pb->headShort.isEmpty())
        recentText = pb->headSubject.isEmpty()
            ? QStringLiteral("%1 %2").arg(pb->headShort, pb->headAgo)
            : QStringLiteral("%1 %2").arg(pb->headShort, pb->headSubject);
    else if (pb)
        recentText = QStringLiteral("%1 · %2").arg(pb->name, pb->headAgo);
    else
        recentText = QStringLiteral("分支明细未纳入追踪（提交类型分布仍可用）");
    auto *recent = new SecondaryLabel(recentText, card);
    recent->setFont(DS::font(DS::FontT::label));
    row5->addWidget(recent, 1);
    auto *go = new FlatButton(QStringLiteral("进入管控 →"), card);
    go->setCursor(Qt::PointingHandCursor);
    connect(go, &QPushButton::clicked, this, [this] { emit goProject(m_name); });
    row5->addWidget(go);
    v->addLayout(row5);
}

void ProjectProgressCard::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton && !m_name.isEmpty())
        emit goProject(m_name);
    QWidget::mouseReleaseEvent(event);
}
