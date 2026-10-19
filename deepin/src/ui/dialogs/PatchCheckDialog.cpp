#include "PatchCheckDialog.h"

#include "../../app/AppModel.h"
#include "../../logic/PatchCheck.h"
#include "../../models/LoadState.h"
#include "../../models/PatchReport.h"
#include "../DesignTokens.h"
#include "../common/FlatButton.h"
#include "../common/SecondaryLabel.h"

#include <QComboBox>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QLabel>
#include <QPlainTextEdit>
#include <QScrollArea>
#include <QTextBrowser>
#include <QTreeWidget>
#include <QVBoxLayout>

namespace {

/// 裁决档位 → 引擎的 verdict 词（mac 同款三档）。
const char *const kVerdictWords[3] = { "resolved", "unresolved", "ambiguous" };

/// 裁决档位 → 置信度（mac 同款：已确认 0.9 / 未确认 0.05 / 存疑 0.5）。
const double kVerdictConfidences[3] = { 0.9, 0.05, 0.5 };

QString verdictLabel(int choice)
{
    switch (choice) {
    case 0:
        return QStringLiteral("已确认");
    case 1:
        return QStringLiteral("未确认");
    default:
        return QStringLiteral("存疑");
    }
}

} // namespace

PatchCheckDialog::PatchCheckDialog(const QString &projectName, AppModel *model, QWidget *parent)
    : DDialog(parent)
    , m_project(projectName)
    , m_model(model)
{
    setWindowTitle(QStringLiteral("补丁体检 · %1").arg(m_project));
    resize(1000, 760);
    setMinimumSize(720, 520);
    setOnButtonClickedClose(false);

    auto *content = new QWidget(this);
    auto *v = new QVBoxLayout(content);
    v->setContentsMargins(0, 0, 0, 0);
    v->setSpacing(DS::Spacing::sm);

    // ── 页头：项目名 + 运行体检 / 合并终稿 / 取任务书 + 总分 ──
    auto *head = new QHBoxLayout;
    head->setSpacing(DS::Spacing::xs);
    auto *title = new QLabel(m_project, content);
    title->setFont(DS::font(DS::FontT::sectionTitle));
    head->addWidget(title);
    head->addStretch(1);

    m_run = new FlatButton(content);
    m_run->setText(QStringLiteral("运行体检"));
    m_run->setToolTip(QStringLiteral("对工作区未提交改动做算法层体检（引擎 graph patchconf --patch）"));
    connect(m_run, &QPushButton::clicked, this, [this] { reload(); });
    head->addWidget(m_run);

    m_merge = new FlatButton(content);
    m_merge->setText(QStringLiteral("合并终稿"));
    m_merge->setToolTip(QStringLiteral("把人工裁决与算法结果合并成终稿（引擎 graph patchconf --merge）"));
    m_merge->setEnabled(false);
    connect(m_merge, &QPushButton::clicked, this, [this] {
        if (!m_model)
            return;
        // 裁决 → agent.json（id 原样回填）
        QVector<PatchVerdict> verdicts;
        const PatchLayer1 *l1 = m_model->patchFor(m_project);
        if (l1) {
            for (const PatchUncertain &u : l1->uncertain) {
                const int choice = m_verdicts.value(u.id, 2);
                PatchVerdict v2;
                v2.id = u.id;
                v2.verdict = QLatin1String(kVerdictWords[qBound(0, choice, 2)]);
                v2.confidence = kVerdictConfidences[qBound(0, choice, 2)];
                v2.reason = QStringLiteral("deepDolphin 人工裁决");
                verdicts << v2;
            }
        }
        m_model->mergePatchCheck(m_project, PatchCheck::agentPayload(verdicts));
    });
    head->addWidget(m_merge);

    m_skill = new FlatButton(content);
    m_skill->setText(QStringLiteral("取任务书"));
    m_skill->setToolTip(QStringLiteral("取 Layer 2 人工/模型复核任务书（引擎 graph patchconf --skill）"));
    connect(m_skill, &QPushButton::clicked, this, [this] {
        if (m_model)
            m_model->loadPatchSkill(m_project);
    });
    head->addWidget(m_skill);

    m_score = new SecondaryLabel(QString(), content);
    head->addWidget(m_score);
    v->addLayout(head);

    // ── 错误条 ──
    m_errorBar = new QLabel(content);
    m_errorBar->setWordWrap(true);
    m_errorBar->setStyleSheet(
        QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
    m_errorBar->hide();
    v->addWidget(m_errorBar);

    auto *scroll = new QScrollArea(content);
    scroll->setWidgetResizable(true);
    scroll->setFrameShape(QFrame::NoFrame);
    auto *body = new QWidget(scroll);
    auto *bv = new QVBoxLayout(body);
    bv->setContentsMargins(0, 0, 0, 0);
    bv->setSpacing(DS::Spacing::sm);

    // ── 终稿卡（Layer 3 合并后才有）──
    m_mergedBox = new QTextBrowser(body);
    m_mergedBox->setOpenExternalLinks(false);
    m_mergedBox->hide();
    bv->addWidget(m_mergedBox);

    // ── Layer 1：信号表 ──
    auto *sigTitle = new QLabel(QStringLiteral("算法层信号（S1–S10）"), body);
    sigTitle->setFont(DS::font(DS::FontT::sectionTitle));
    bv->addWidget(sigTitle);

    m_signals = new QTreeWidget(body);
    m_signals->setColumnCount(2);
    m_signals->setHeaderLabels({ QStringLiteral("信号"), QStringLiteral("值") });
    m_signals->header()->setSectionResizeMode(1, QHeaderView::Stretch);
    m_signals->setRootIsDecorated(false);
    bv->addWidget(m_signals);

    // ── Layer 2：拿不准的项（逐项人工裁决）──
    auto *uncTitle = new QLabel(QStringLiteral("拿不准的项（人工裁决）"), body);
    uncTitle->setFont(DS::font(DS::FontT::sectionTitle));
    bv->addWidget(uncTitle);

    m_uncertain = new QTreeWidget(body);
    m_uncertain->setColumnCount(3);
    m_uncertain->setHeaderLabels({ QStringLiteral("项"), QStringLiteral("说明"), QStringLiteral("裁决") });
    m_uncertain->header()->setSectionResizeMode(1, QHeaderView::Stretch);
    bv->addWidget(m_uncertain);

    // ── 低置信度实体（默认收起，点开给 diff 实码）──
    auto *entTitle = new QLabel(QStringLiteral("低置信度实体（点开看实码）"), body);
    entTitle->setFont(DS::font(DS::FontT::sectionTitle));
    bv->addWidget(entTitle);

    m_entities = new QTreeWidget(body);
    m_entities->setColumnCount(2);
    m_entities->setHeaderLabels({ QStringLiteral("实体"), QStringLiteral("位置") });
    m_entities->header()->setSectionResizeMode(1, QHeaderView::Stretch);
    connect(m_entities, &QTreeWidget::itemExpanded, this, [this](QTreeWidgetItem *item) {
        // 惰性展开：点开那一刻才从 diff 里抽实码（mac 同款）
        if (item->childCount() > 0)
            return;
        const QString file = item->data(1, Qt::UserRole).toString();
        const int line = item->data(1, Qt::UserRole + 1).toInt();
        const QStringList lines = PatchCheck::diffSnippet(diffText(), file, line);
        if (lines.isEmpty()) {
            auto *child = new QTreeWidgetItem(item);
            child->setText(0, QStringLiteral("（补丁里读不到这段实码）"));
            return;
        }
        for (const QString &l : lines) {
            auto *child = new QTreeWidgetItem(item);
            const int tab = l.indexOf(QLatin1Char('\t'));
            const QString no = tab > 0 ? l.left(tab) : QString();
            const QString code = tab > 0 ? l.mid(tab + 1) : l;
            child->setText(0, code);
            child->setText(1, no);
        }
    });
    bv->addWidget(m_entities);

    // ── 任务书（--skill 的 markdown）──
    auto *skillTitle = new QLabel(QStringLiteral("Layer 2 任务书"), body);
    skillTitle->setFont(DS::font(DS::FontT::sectionTitle));
    bv->addWidget(skillTitle);
    m_skillBox = new QPlainTextEdit(body);
    m_skillBox->setReadOnly(true);
    m_skillBox->setLineWrapMode(QPlainTextEdit::NoWrap);
    m_skillBox->setFont(QFont(DS::font(DS::FontT::body).family(),
        DS::font(DS::FontT::body).pointSize(), QFont::Monospace));
    m_skillBox->setMinimumHeight(140);
    bv->addWidget(m_skillBox);

    bv->addStretch(1);
    scroll->setWidget(body);
    v->addWidget(scroll, 1);

    addContent(content);
    addButton(QStringLiteral("关闭"), true);

    if (m_model) {
        connect(m_model, &AppModel::patchCheckChanged, this, [this](const QString &name) {
            if (name == m_project)
                refreshView();
        });
        connect(m_model, &AppModel::patchMerged, this, &PatchCheckDialog::onMerged);
        connect(m_model, &AppModel::patchSkillReady, this, &PatchCheckDialog::onSkill);
    }

    reload();
}

void PatchCheckDialog::reload()
{
    m_errorBar->hide();
    if (m_model)
        m_model->loadPatchCheck(m_project);
}

QString PatchCheckDialog::diffText()
{
    if (m_diffLoaded)
        return m_diff;
    if (!m_model)
        return QString();
    QString err;
    const QString d = m_model->workingDiff(m_project, &err);
    if (!err.isEmpty())
        return QString();
    m_diff = d;
    m_diffLoaded = true;
    return m_diff;
}

void PatchCheckDialog::refreshView()
{
    const LoadStateBox st = m_model ? m_model->patchState(m_project) : LoadStateBox();
    if (st.state == LoadState::failed) {
        showError(st.message);
        m_score->setText(QString());
        m_merge->setEnabled(false);
        return;
    }
    if (st.state != LoadState::loaded) {
        m_errorBar->hide();
        return;
    }
    m_errorBar->hide();
    rebuildLayer1();
    rebuildUncertain();
    rebuildLowEntities();
    rebuildMerged();
}

void PatchCheckDialog::rebuildLayer1()
{
    m_signals->clear();
    const PatchLayer1 *l1 = m_model ? m_model->patchFor(m_project) : nullptr;
    if (!l1)
        return;
    for (const PatchSignal &s : l1->signalList) {
        auto *it = new QTreeWidgetItem(m_signals);
        it->setText(0, s.key);
        // null = 分母为 0、算不出 —— 显示「—」，**不能**显示 0（那会被读成「得了 0 分」）
        it->setText(1, s.hasValue ? QString::number(static_cast<int>(s.value * 100))
                                  : QStringLiteral("—（算不出）"));
        if (!s.hasValue)
            it->setForeground(1, DS::textSecondary());
    }
    // 总分
    QString text;
    if (l1->overallPresent) {
        const int pct = static_cast<int>(l1->overall * 100);
        text = QStringLiteral("总分 %1").arg(pct);
        const PatchCheck::ScoreBand band = PatchCheck::bandOf(l1->overall);
        const DS::SemColor tone = band == PatchCheck::ScoreBand::high ? DS::SemColor::shallow
            : band == PatchCheck::ScoreBand::mid              ? DS::SemColor::orange
                                                                     : DS::SemColor::red;
        m_score->setStyleSheet(QStringLiteral("color: %1;").arg(DS::semColor(tone).name()));
    } else {
        text = QStringLiteral("总分未知（契约可能过旧）");
        m_score->setStyleSheet(QString());
    }
    // 诊断披露：null 信号说明、解析错误、补丁文件数、新增行数
    if (l1->diagnostics.present) {
        QStringList bits;
        if (l1->diagnostics.parseErrors > 0)
            bits << QStringLiteral("解析错误 %1").arg(l1->diagnostics.parseErrors);
        bits << QStringLiteral("补丁文件 %1").arg(l1->diagnostics.patchFiles);
        bits << QStringLiteral("新增行 %1").arg(l1->diagnostics.addedLines);
        if (!l1->diagnostics.nullSignals.isEmpty())
            bits << QStringLiteral("算不出的信号 %1").arg(l1->diagnostics.nullSignals.join(QStringLiteral("、")));
        text += QStringLiteral(" · ") + bits.join(QStringLiteral(" · "));
    }
    m_score->setText(text);
    m_merge->setEnabled(!l1->uncertain.isEmpty() || !l1->entities.isEmpty());
}

void PatchCheckDialog::rebuildUncertain()
{
    m_uncertain->clear();
    qDeleteAll(m_verdictBoxes);
    m_verdictBoxes.clear();
    m_verdicts.clear();
    const PatchLayer1 *l1 = m_model ? m_model->patchFor(m_project) : nullptr;
    if (!l1)
        return;
    for (const PatchUncertain &u : l1->uncertain) {
        auto *it = new QTreeWidgetItem(m_uncertain);
        it->setText(0, u.issue);
        it->setText(1, u.detail);
        it->setToolTip(1, u.detail);
        auto *box = new QComboBox(m_uncertain);
        box->addItem(verdictLabel(0));
        box->addItem(verdictLabel(1));
        box->addItem(verdictLabel(2));
        box->setCurrentIndex(2); // 默认存疑（mac 同款：默认 ambiguous / 0.5）
        m_uncertain->setItemWidget(it, 2, box);
        m_verdictBoxes.insert(u.id, box);
        m_verdicts.insert(u.id, 2);
        connect(box, &QComboBox::currentIndexChanged, this, [this, id = u.id](int idx) {
            setVerdict(id, idx);
        });
    }
    if (l1->uncertain.isEmpty()) {
        auto *it = new QTreeWidgetItem(m_uncertain);
        it->setText(0, QStringLiteral("（没有拿不准的项）"));
    }
}

void PatchCheckDialog::setVerdict(const QString &id, int choice)
{
    m_verdicts.insert(id, qBound(0, choice, 2));
}

void PatchCheckDialog::rebuildLowEntities()
{
    m_entities->clear();
    const PatchLayer1 *l1 = m_model ? m_model->patchFor(m_project) : nullptr;
    if (!l1)
        return;
    const QVector<PatchEntity> lows = PatchCheck::lowConfidenceEntities(*l1);
    for (const PatchEntity &e : lows) {
        auto *it = new QTreeWidgetItem(m_entities);
        const int pct = static_cast<int>(e.confidence * 100);
        it->setText(0, QStringLiteral("%1%% · %2").arg(pct).arg(e.kind));
        it->setText(1, QStringLiteral("%1:%2").arg(e.file).arg(e.line));
        it->setData(1, Qt::UserRole, e.file);
        it->setData(1, Qt::UserRole + 1, e.line);
        if (e.confidence < 0.5)
            it->setForeground(0, DS::semColor(DS::SemColor::red));
        else if (e.confidence < 0.75)
            it->setForeground(0, DS::semColor(DS::SemColor::orange));
    }
    if (lows.isEmpty()) {
        auto *it = new QTreeWidgetItem(m_entities);
        it->setText(0, QStringLiteral("（没有低置信度实体）"));
    }
}

void PatchCheckDialog::rebuildMerged()
{
    const PatchMerged *merged = m_model ? m_model->patchMergedFor(m_project) : nullptr;
    if (!merged || !merged->ok) {
        m_mergedBox->hide();
        return;
    }
    QStringList lines;
    lines << QStringLiteral("终稿总分：%1")
                 .arg(merged->overallPresent ? QString::number(static_cast<int>(merged->overall * 100))
                                             : QStringLiteral("未知"));
    if (merged->diagnosticsPresent) {
        lines << QStringLiteral("已复核 %1 项 · 算法层确定 %2 项 · 延后 %3 项")
                     .arg(merged->reviewedByAgent)
                     .arg(merged->certainFromAlgorithm)
                     .arg(merged->deferred);
    }
    lines << QString();
    lines << QStringLiteral("告警：");
    if (merged->alerts.isEmpty()) {
        lines << QStringLiteral("  （无）");
    } else {
        for (const PatchAlert &a : merged->alerts)
            lines << QStringLiteral("  [%1] %2 — %3").arg(a.level, a.type, a.detail);
    }
    m_mergedBox->setPlainText(lines.join(QLatin1Char('\n')));
    m_mergedBox->show();
}

void PatchCheckDialog::onMerged(const QString &name)
{
    if (name != m_project)
        return;
    rebuildMerged();
}

void PatchCheckDialog::onSkill(const QString &name, const QString &text)
{
    if (name != m_project)
        return;
    m_skillBox->setPlainText(text);
}

void PatchCheckDialog::showError(const QString &text)
{
    m_errorBar->setText(text);
    m_errorBar->show();
}
