#include "ProjectDetailPage.h"
#include "../../logic/CommitTypeComposition.h"
#include "../../logic/Derived.h"
#include "../../logic/DestructiveGuard.h"
#include "../../logic/DashboardScope.h"
#include "../../logic/MilestoneCardTitle.h"
#include "../../platform/SysOpen.h"
#include "../DesignTokens.h"
#include "../common/BusyRow.h"
#include "../common/Chip.h"
#include "../common/ConfirmDialog.h"
#include "../common/CountLabel.h"
#include "../common/EmptyState.h"
#include "../common/LegendRow.h"
#include "../common/MarkdownView.h"
#include "../common/SecondaryLabel.h"
#include "../common/SegmentedBar.h"
#include "../pages/MilestoneRowWidget.h"
#include "../../models/ProjectStatus.h"
#include <DSpinner>
#include <QClipboard>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QPlainTextEdit>
#include <DProgressBar>
#include <QPushButton>
#include <QUrl>
#include <QVBoxLayout>

DWIDGET_USE_NAMESPACE

namespace {
// 页头小图标按钮（borderless；图标优先主题，文字兜底）
QPushButton *iconButton(const QString &iconName, const QString &text, const QString &tooltip,
    QWidget *parent)
{
    auto *b = new QPushButton(text, parent);
    b->setFlat(true);
    b->setToolTip(tooltip);
    b->setIcon(QIcon::fromTheme(iconName));
    b->setCursor(Qt::PointingHandCursor);
    return b;
}

QLabel *smallLabel(const QString &text, QWidget *parent, const QColor &color)
{
    auto *l = new QLabel(text, parent);
    l->setFont(DS::font(DS::FontT::label));
    l->setStyleSheet(QStringLiteral("color: %1;").arg(color.name()));
    l->setWordWrap(true);
    return l;
}
} // namespace

ProjectDetailPage::ProjectDetailPage(QWidget *parent)
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
    m_contentLayout->setSpacing(DS::Spacing::md);
    m_scroll->setWidget(m_content);
    outer->addWidget(m_scroll);
}

void ProjectDetailPage::setProject(const QString &name, const std::optional<ProjectStatus> &p,
    const QString &loadError)
{
    m_name = name;
    m_project = p;
    m_loadError = loadError;
    rebuild();
}

void ProjectDetailPage::setDocs(const QString &name, const std::optional<DocsEnvelope> &docs,
    const LoadStateBox &state)
{
    m_docs = docs;
    m_docsState = state;
    if (m_name != name)
        m_name = name;
    rebuild();
}

void ProjectDetailPage::setMilestones(const QVector<Milestone> &items)
{
    m_milestones = items;
    rebuild();
}

void ProjectDetailPage::setGitOutput(const QString &name, const GitOpResponse &resp)
{
    if (!m_name.isEmpty() && name != m_name)
        return;
    m_gitOutput = resp;
    m_hasGitOutput = true;
    rebuild();
}

void ProjectDetailPage::setBusy(bool busy)
{
    m_busy = busy;
    rebuild();
}

void ProjectDetailPage::rebuild()
{
    while (m_contentLayout->count() > 0) {
        QLayoutItem *it = m_contentLayout->takeAt(0);
        if (it->widget())
            it->widget()->deleteLater();
        delete it;
    }

    // ── 三态 ──
    if (m_loadError.isEmpty() && !m_project.has_value() && !m_name.isEmpty()) {
        // 列表没加载完时短暂存在
        auto *loading = new QWidget(m_content);
        auto *v = new QVBoxLayout(loading);
        auto *sp = new DSpinner(loading);
        sp->start();
        v->addStretch(1);
        v->addWidget(sp, 0, Qt::AlignHCenter);
        v->addStretch(2);
        m_contentLayout->addWidget(loading);
        return;
    }
    if (!m_loadError.isEmpty() || (m_project.has_value() && (*m_project).isUnreadable())) {
        const QString reason = !m_loadError.isEmpty()
            ? m_loadError
            : (*m_project).error.value_or(QStringLiteral("读不出来"));
        auto *retry = new QPushButton(QStringLiteral("重试"), m_content);
        connect(retry, &QPushButton::clicked, this, &ProjectDetailPage::retryRequested);
        m_contentLayout->addWidget(new EmptyState(QStringLiteral("data-warning"),
            QStringLiteral("读不出来：%1").arg(m_name), reason, retry));
        return;
    }
    if (!m_project.has_value()) {
        m_contentLayout->addWidget(new EmptyState(EmptyState::Tone::Empty,
            QStringLiteral("还没有选择项目"), QStringLiteral("从侧栏选择一个项目查看详情。")));
        return;
    }

    const ProjectStatus &p = *m_project;
    m_contentLayout->addWidget(buildHeader(p));
    if (p.isGit())
        m_contentLayout->addWidget(buildCommitCard());

    // 2 列卡：工程脉搏 | 提交构成（近期）
    auto *twoCol = new QWidget(m_content);
    auto *h = new QHBoxLayout(twoCol);
    h->setContentsMargins(0, 0, 0, 0);
    h->setSpacing(DS::Spacing::md);
    h->addWidget(buildPulseCard(p), 1);
    h->addWidget(buildCommitCompositionCard(p), 1);
    m_contentLayout->addWidget(twoCol);

    m_contentLayout->addWidget(buildBranchesCard(p));
    m_contentLayout->addWidget(buildMilestoneCard());
    if (!p.journal.empty())
        m_contentLayout->addWidget(buildJournalCard(p));
    m_contentLayout->addWidget(buildDocsArea());
    m_contentLayout->addStretch(1);
}

QWidget *ProjectDetailPage::buildHeader(const ProjectStatus &p)
{
    auto *header = new QWidget(m_content);
    auto *v = new QVBoxLayout(header);
    v->setContentsMargins(0, 0, 0, 0);
    v->setSpacing(DS::Spacing::xs);

    auto *row1 = new QHBoxLayout;
    auto *name = new QLabel(p.name, header);
    name->setFont(DS::font(DS::FontT::sectionTitle));
    row1->addWidget(name);

    const Derived::StateWord sw = Derived::stateWord(p);
    auto *stateChip = new Chip(sw.text, header);
    stateChip->setTone(sw.tone == Liveness::needsAction ? DS::SemColor::orange
            : sw.tone == Liveness::recent               ? DS::SemColor::shallow
            : sw.tone == Liveness::quiet                ? DS::SemColor::red
            : sw.tone == Liveness::engineStale          ? DS::SemColor::gray
            : sw.tone == Liveness::notGit               ? DS::SemColor::deep
                                                        : DS::SemColor::gray);
    row1->addWidget(stateChip);
    if (!p.isGit()) {
        auto *notGit = new Chip(QStringLiteral("非 git"), header);
        notGit->setTone(DS::SemColor::deep);
        row1->addWidget(notGit);
    }
    row1->addStretch(1);
    if (m_busy) {
        // 忙态 = BusyRow 只转圈（plan §3b 收编；原 16px 手拼 DSpinner，PanelWindow
        // setBusy 驱动的同一个忙态）
        row1->addWidget(new BusyRow(QString(), header));
    }
    v->addLayout(row1);

    if (!p.headline.isEmpty()) {
        auto *headline = new SecondaryLabel(p.headline, header);
        headline->setWordWrap(true);
        v->addWidget(headline);
    }

    // path 可复制（caption）
    auto *pathRow = new QHBoxLayout;
    auto *path = new SecondaryLabel(p.path, header);
    path->setFont(DS::font(DS::FontT::label));
    pathRow->addWidget(path, 1);
    auto *copy = iconButton(QStringLiteral("edit-copy"), QString(),
        QStringLiteral("复制路径"), header);
    connect(copy, &QPushButton::clicked, this, [p] {
        QGuiApplication::clipboard()->setText(p.path);
    });
    pathRow->addWidget(copy);
    v->addLayout(pathRow);

    // warnings 逐条橙（引擎说的「非 git 仓库：进度基于文件活动时间…」必须显示）
    for (const QString &w : p.warnings)
        v->addWidget(smallLabel(w, header, DS::semColor(DS::SemColor::orange)));
    // overall.notes 逐条 info（另一批事实）；overall.summary 仅 commitTypeLine 为空时补位
    if (p.overall.notes.has_value()) {
        for (const QString &n : *p.overall.notes) {
            auto *note = smallLabel(n, header, DS::textSecondary());
            note->setOpenExternalLinks(false);
            v->addWidget(note);
        }
    }
    const QString commitTypeLine = CommitTypes::lineFor(CommitTypes::toEntries(p.commitTypes),
        p.commitTypesTruncated, p.commitCount);
    if (!p.overall.summary.has_value() || commitTypeLine.isEmpty()) {
        if (p.overall.summary.has_value() && !(*p.overall.summary).isEmpty())
            v->addWidget(smallLabel(*p.overall.summary, header, DS::textSecondary()));
    }

    // ── 右侧按钮排：项目说明 + 拉取/推送/抓取 + 分隔 + 暂存/恢复 + 分隔 + 更新菜单 ──
    auto *actions = new QHBoxLayout;
    actions->setSpacing(DS::Spacing::xs);

    auto *brief = iconButton(QStringLiteral("applications-utilities"), QStringLiteral("项目说明"),
        QStringLiteral("AI 项目说明（未配置 AI 时会给出配置指引）"), header);
    connect(brief, &QPushButton::clicked, this, [this] { emit briefRequested(m_name); });
    actions->addWidget(brief);

    // gitOpButtons 唯一构造点：pull/push/fetch + stash/unstash（busy 禁用+转圈）
    const auto addGit = [&actions, this, header](const QString &op, const QString &icon,
                            const QString &tip) {
        auto *b = iconButton(icon, QString(), tip, header);
        b->setEnabled(!m_busy);
        connect(b, &QPushButton::clicked, this,
            [this, op] { emit gitOpRequested(op, m_name, QString()); });
        actions->addWidget(b);
        return b;
    };
    addGit(QStringLiteral("pull"), QStringLiteral("arrow-down"),
        QStringLiteral("拉取（git pull）"));
    addGit(QStringLiteral("push"), QStringLiteral("arrow-up"), QStringLiteral("推送（git push）"));
    addGit(QStringLiteral("fetch"), QStringLiteral("view-refresh"),
        QStringLiteral("抓取（git fetch）"));
    auto *div1 = new QLabel(QStringLiteral("|"), header);
    div1->setStyleSheet(QStringLiteral("color: %1;").arg(DS::surfaceBorder().name()));
    actions->addWidget(div1);
    addGit(QStringLiteral("stash"), QStringLiteral("archive-insert"),
        QStringLiteral("暂存（git stash）"));
    addGit(QStringLiteral("unstash"), QStringLiteral("archive-insert-axis"),
        QStringLiteral("恢复（git stash pop）"));

    auto *div2 = new QLabel(QStringLiteral("|"), header);
    div2->setStyleSheet(QStringLiteral("color: %1;").arg(DS::surfaceBorder().name()));
    actions->addWidget(div2);
    auto *update = iconButton(QStringLiteral("view-refresh"), QStringLiteral("更新"),
        QStringLiteral("浅更新 / 深更新（会改写托管文档）"), header);
    connect(update, &QPushButton::clicked, this, &ProjectDetailPage::updateMenuRequested);
    actions->addWidget(update);
    v->addLayout(actions);

    // 再下一行：Finder（文件管理器）/ 终端 / 远端（remote 为空时不显示远端）
    auto *sysRow = new QHBoxLayout;
    sysRow->setSpacing(DS::Spacing::xs);
    auto *finder = iconButton(QStringLiteral("folder"), QString(),
        QStringLiteral("在文件管理器中显示"), header);
    connect(finder, &QPushButton::clicked, this, [p] { SysOpen::revealInFileManager(p.path); });
    sysRow->addWidget(finder);
    auto *term = iconButton(QStringLiteral("utilities-terminal"), QString(),
        QStringLiteral("在终端中打开"), header);
    connect(term, &QPushButton::clicked, this, [p] { SysOpen::openTerminal(p.path); });
    sysRow->addWidget(term);
    if (!p.remote.isEmpty()) {
        auto *remote = iconButton(QStringLiteral("web-browser"), QString(),
            QStringLiteral("打开远端仓库"), header);
        connect(remote, &QPushButton::clicked, this, [p] {
            QString url = p.remote;
            // git@ → https 浏览器打开（git@host:owner/repo.git → https://host/owner/repo）
            if (url.startsWith(QStringLiteral("git@"))) {
                url = QStringLiteral("https://")
                    + url.mid(4).replace(QLatin1Char(':'), QLatin1Char('/'));
                if (url.endsWith(QLatin1String(".git")))
                    url.chop(4);
            }
            SysOpen::openUrl(QUrl(url));
        });
        sysRow->addWidget(remote);
    }
    sysRow->addStretch(1);
    v->addLayout(sysRow);
    return header;
}

QWidget *ProjectDetailPage::buildCommitCard()
{
    const ProjectStatus &p = *m_project;
    auto *card = new Card(m_content);
    auto *v = new QVBoxLayout(card);
    v->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
    v->setSpacing(DS::Spacing::sm);

    auto *title = new QLabel(QStringLiteral("提交改动"), card);
    title->setFont(DS::font(DS::FontT::cardTitle));
    v->addWidget(title);

    auto *row = new QHBoxLayout;
    m_commitInput = new DLineEdit(card);
    m_commitInput->setPlaceholderText(QStringLiteral("提交信息（提交全部改动）"));
    m_commitInput->setEnabled(!m_busy);
    row->addWidget(m_commitInput, 1);
    m_commitBtn = new QPushButton(QStringLiteral("提交"), card);
    m_commitBtn->setStyleSheet(
        QStringLiteral("QPushButton { background: %1; color: white; border: none;"
                       " border-radius: %2px; %3 }")
            .arg(DS::semColor(DS::SemColor::accent).name())
            .arg(DS::Radius::control)
            .arg(DS::buttonPaddingQss())); // 按钮 padding 一档（M3-5）
    m_commitBtn->setEnabled(!m_busy);
    row->addWidget(m_commitBtn);
    v->addLayout(row);

    // git 输出区：✓成功/✗失败 + 等宽可复制输出 + 清除按钮
    if (m_hasGitOutput) {
        m_gitOutputHost = new QWidget(card);
        auto *gv = new QVBoxLayout(m_gitOutputHost);
        gv->setContentsMargins(0, 0, 0, 0);
        gv->setSpacing(DS::Spacing::xs);
        auto *head = new QHBoxLayout;
        auto *flag = new QLabel(m_gitOutput.ok ? QStringLiteral("✓ 成功") : QStringLiteral("✗ 失败"),
            m_gitOutputHost);
        flag->setFont(DS::font(DS::FontT::label));
        flag->setStyleSheet(QStringLiteral("color: %1;")
                .arg(m_gitOutput.ok ? DS::semColor(DS::SemColor::shallow).name()
                                    : DS::semColor(DS::SemColor::red).name()));
        head->addWidget(flag);
        head->addStretch(1);
        auto *clear = new QPushButton(QStringLiteral("清除"), m_gitOutputHost);
        clear->setFlat(true);
        connect(clear, &QPushButton::clicked, this, [this] {
            m_hasGitOutput = false;
            rebuild();
        });
        head->addWidget(clear);
        gv->addLayout(head);
        auto *output = new DTextEdit(m_gitOutputHost);
        output->setPlainText(m_gitOutput.output);
        output->setReadOnly(true);
        output->setMaximumHeight(130);
        QFont mono(QStringLiteral("monospace"));
        mono.setStyleHint(QFont::Monospace);
        output->setFont(mono);
        output->setFrameShape(QFrame::NoFrame);
        gv->addWidget(output);
        v->addWidget(m_gitOutputHost);
    }

    // 提交 → 确认框「在「X」里提交全部改动？」→「全部提交」（染红）→ gitOp(commit,message)
    const auto doCommit = [this, &p] {
        const QString msg = m_commitInput->text().trimmed();
        if (msg.isEmpty() || m_busy)
            return;
        const DestructiveGuard::Spec spec = { DestructiveGuard::commitTitle(p.name),
            DestructiveGuard::commitMessage(DestructiveGuard::commitScope(p)),
            DestructiveGuard::confirmLabelFor(DestructiveGuard::Action::commitAll), true };
        if (ConfirmDialog::confirm(this->window(), spec))
            emit gitOpRequested(QStringLiteral("commit"), m_name, msg);
    };
    connect(m_commitBtn, &QPushButton::clicked, this, doCommit);
    connect(m_commitInput->lineEdit(), &QLineEdit::returnPressed, this, doCommit); // 回车也触发（DLineEdit 转发内层输入框）
    return card;
}

QWidget *ProjectDetailPage::buildPulseCard(const ProjectStatus &p)
{
    auto *card = new Card(m_content);
    auto *v = new QVBoxLayout(card);
    v->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
    v->setSpacing(DS::Spacing::sm);
    auto *title = new QLabel(QStringLiteral("工程脉搏"), card);
    title->setFont(DS::font(DS::FontT::cardTitle));
    v->addWidget(title);

    // mergeHint 提示条（fast-forward 绿 / merge 橙；kind=="merged" 不显示）
    if (p.mergeHint.has_value()) {
        const QString line = Derived::mergeHintKindLine(*p.mergeHint);
        if (!line.isEmpty()) {
            auto *hint = new Chip(line, card);
            hint->setTone(p.mergeHint->kind == QLatin1String("fast-forward") ? DS::SemColor::shallow
                                                                             : DS::SemColor::orange);
            if (!p.mergeHint->description.isEmpty())
                hint->setToolTip(p.mergeHint->description);
            v->addWidget(hint);
        }
    }

    // Chips：未提交 N/未跟踪 N/stash N/工作区 N（statTint 量级色）
    auto *chips = new QHBoxLayout;
    chips->setSpacing(DS::Spacing::xs);
    const auto addStat = [&chips, &card](const QString &label, int n) {
        if (n < 0) {
            auto *c = new Chip(QStringLiteral("%1 读不出来").arg(label), card);
            c->setTone(DS::SemColor::red);
            chips->addWidget(c);
            return;
        }
        if (n == 0)
            return;
        auto *chip = new Chip(QStringLiteral("%1 %2").arg(label).arg(n), card);
        const QColor t = Derived::statTint(n);
        chip->setTone(!t.isValid()       ? DS::SemColor::gray
            : t == DS::semColor(DS::SemColor::red) ? DS::SemColor::red
            : t == DS::semColor(DS::SemColor::orange) ? DS::SemColor::orange
                                                      : DS::SemColor::yellow);
        chips->addWidget(chip);
    };
    addStat(QStringLiteral("未提交"), p.userDirtyCount);
    addStat(QStringLiteral("未跟踪"), p.untrackedCount);
    addStat(QStringLiteral("stash"), p.stashCount);
    addStat(QStringLiteral("工作区"), p.worktreeCount > 1 ? p.worktreeCount : 0);
    chips->addStretch(1);
    v->addLayout(chips);

    // dirty 结构化行（dirtyLine）
    if (!p.dirty.ok && p.dirty.err.has_value()) {
        v->addWidget(smallLabel(QStringLiteral("工作区读不出来（文件数不可信：%1）")
                                    .arg(*p.dirty.err),
            card, DS::semColor(DS::SemColor::orange)));
    } else if (p.dirty.conflicts > 0) {
        v->addWidget(smallLabel(QStringLiteral("⚠ 冲突 %1").arg(p.dirty.conflicts), card,
            DS::semColor(DS::SemColor::red)));
    } else if (p.dirty.clean) {
        v->addWidget(smallLabel(QStringLiteral("工作区干净"), card, DS::textSecondary()));
    }
    // dirtyFilesLine 最多 8 个文件 +「还有 N 个」
    if (!p.dirty.files.isEmpty()) {
        const int cap = qMin(8, p.dirty.files.size());
        QStringList shown;
        for (int i = 0; i < cap; ++i)
            shown << p.dirty.files.at(i);
        QString text = shown.join(QStringLiteral("、"));
        if (p.dirty.files.size() > cap)
            text += QStringLiteral("，还有 %1 个").arg(p.dirty.files.size() - cap);
        v->addWidget(smallLabel(text, card, DS::textSecondary()));
    }

    // tags / manifests（截断 8 个+还有 N）
    const auto addList = [this, &v, &card](const QString &head, const QStringList &items) {
        if (items.isEmpty())
            return; // 空数组不占位
        QString text = QStringLiteral("%1：%2").arg(head, items.mid(0, 8).join(QStringLiteral("、")));
        if (items.size() > 8)
            text += QStringLiteral("，还有 %1 个").arg(items.size() - 8);
        v->addWidget(smallLabel(text, card, DS::textSecondary()));
    };
    addList(QStringLiteral("tags"), p.tags);
    addList(QStringLiteral("清单"), p.manifests);

    // 托管文档清单（「README.md（已建/未建）」）
    if (!p.docs.empty()) {
        QStringList docList;
        for (const DocRef &d : p.docs)
            docList << QStringLiteral("%1（%2）").arg(d.file,
                d.exists ? QStringLiteral("已建") : QStringLiteral("未建"));
        v->addWidget(smallLabel(QStringLiteral("托管文档：%1").arg(docList.join(QStringLiteral("、"))),
            card, DS::textSecondary()));
    }

    // commitTypeLine
    const QString ctLine = CommitTypes::lineFor(CommitTypes::toEntries(p.commitTypes),
        p.commitTypesTruncated, p.commitCount);
    if (!ctLine.isEmpty())
        v->addWidget(smallLabel(ctLine, card, DS::textSecondary()));

    // 最近提交
    if (const BranchStatus *pb = Derived::primaryBranch(p); pb && !pb->headShort.isEmpty()) {
        v->addWidget(smallLabel(QStringLiteral("最近提交：%1 %2").arg(pb->headShort, pb->headSubject),
            card, DS::textSecondary()));
    }
    // 当前/默认分支行
    v->addWidget(smallLabel(
        QStringLiteral("当前分支 %1 · 默认分支 %2").arg(
            p.currentBranch.isEmpty() ? QStringLiteral("—") : p.currentBranch,
            p.defaultBranch.isEmpty() ? QStringLiteral("—") : p.defaultBranch),
        card, DS::textSecondary()));
    return card;
}

QWidget *ProjectDetailPage::buildCommitCompositionCard(const ProjectStatus &p)
{
    auto *card = new Card(m_content);
    auto *v = new QVBoxLayout(card);
    v->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
    v->setSpacing(DS::Spacing::sm);
    auto *title = new QLabel(QStringLiteral("提交构成（近期）"), card);
    title->setFont(DS::font(DS::FontT::cardTitle));
    v->addWidget(title);

    const auto slice = CommitTypes::cardSlice(CommitTypes::toEntries(p.commitTypes));
    if (slice.rows.isEmpty()) {
        v->addWidget(smallLabel(QStringLiteral("暂无提交类型样本"), card, DS::textSecondary()));
        return card;
    }
    auto *bar = new SegmentedBar(card);
    QVector<QPair<QColor, int>> barData;
    QVector<QPair<QColor, QString>> legend;
    for (int i = 0; i < slice.rows.size(); ++i) {
        const QColor c = CommitTypes::sequenceColor(i);
        barData.append({ c, slice.rows.at(i).second });
        legend.append({ c,
            QStringLiteral("%1 ×%2").arg(slice.rows.at(i).first).arg(slice.rows.at(i).second) });
    }
    bar->setData(barData);
    v->addWidget(bar);
    auto *legendRow = new LegendRow(card);
    legendRow->setEntries(legend);
    v->addWidget(legendRow);
    if (!slice.note.isEmpty())
        v->addWidget(smallLabel(slice.note, card, DS::semColor(DS::SemColor::orange)));
    if (p.commitTypesTruncated)
        v->addWidget(smallLabel(QStringLiteral("样本，非全量"), card,
            DS::semColor(DS::SemColor::orange)));
    return card;
}

QWidget *ProjectDetailPage::buildBranchesCard(const ProjectStatus &p)
{
    auto *card = new Card(m_content);
    auto *v = new QVBoxLayout(card);
    v->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
    v->setSpacing(DS::Spacing::sm);

    // 标题三形态（branchScopeLine）
    auto *title = new QLabel(QStringLiteral("分支进度 · %1").arg(Derived::branchScopeLine(p)), card);
    title->setFont(DS::font(DS::FontT::cardTitle));
    v->addWidget(title);

    if (p.branches.empty()) {
        v->addWidget(smallLabel(QStringLiteral("暂无进度记录，运行一次「浅更新」后会记录分支基线。"),
            card, DS::textSecondary()));
        return card;
    }

    for (const BranchStatus &b : p.branches) {
        // 行 1：状态点 + 分支名（等宽）+ 当前/默认 Chip + statusLabel + provider 徽章
        //（仅 ≠「规则」时显示，青）+ 待记录三态
        auto *row1 = new QWidget(card);
        auto *h = new QHBoxLayout(row1);
        h->setContentsMargins(0, 0, 0, 0);
        h->setSpacing(DS::Spacing::xs);
        auto *dot = new QLabel(row1);
        QPixmap pm(DS::Height::dot, DS::Height::dot); // 状态点统一 8px（M3-5）
        pm.fill(Qt::transparent);
        QPainter dp(&pm);
        dp.setRenderHint(QPainter::Antialiasing);
        dp.setPen(Qt::NoPen);
        dp.setBrush(Derived::branchStatusColor(b.status));
        dp.drawEllipse(0, 0, DS::Height::dot, DS::Height::dot);
        dot->setPixmap(pm);
        h->addWidget(dot);

        auto *bname = new QLabel(b.name, row1);
        QFont mono(QStringLiteral("monospace"));
        mono.setStyleHint(QFont::Monospace);
        bname->setFont(mono);
        h->addWidget(bname);
        if (b.isCurrent) {
            auto *cur = new Chip(QStringLiteral("当前"), row1);
            cur->setTone(DS::SemColor::accent);
            h->addWidget(cur);
        }
        if (b.isDefault) {
            auto *def = new Chip(QStringLiteral("默认"), row1);
            def->setTone(DS::SemColor::gray);
            h->addWidget(def);
        }
        if (!b.statusLabel.isEmpty())
            h->addWidget(smallLabel(b.statusLabel, row1, DS::textSecondary()));
        // provider 徽章仅 ≠「规则」时显示（青）。引擎只发 provider（默认 "rules"）。
        if (!b.provider.isEmpty() && b.provider != QLatin1String("rules")) {
            auto *prov = new Chip(b.provider, row1);
            prov->setTone(DS::SemColor::ai);
            h->addWidget(prov);
        }
        // 待记录三态
        if (b.pendingCommits > 0 && !b.baselineReset)
            h->addWidget(smallLabel(QStringLiteral("%1 待记录").arg(b.pendingCommits), row1,
                DS::semColor(DS::SemColor::accent)));
        else if (b.baselineReset)
            h->addWidget(smallLabel(QStringLiteral("待记录数已失效（基线重建）"), row1,
                DS::semColor(DS::SemColor::orange)));
        h->addStretch(1);
        v->addWidget(row1);

        // 行 2（缩进）：summary（≤2 行）/ headShort·headAgo（tooltip=完整 SHA）/ highlights /
        //「领先默认分支 N」（蓝）/ staleText（颜色跟引擎）/ nextSteps（accent）
        auto *row2 = new QWidget(card);
        row2->setContentsMargins(18, 0, 0, 0);
        auto *v2 = new QVBoxLayout(row2);
        v2->setContentsMargins(0, 0, 0, 0);
        v2->setSpacing(2);
        if (!b.summary.isEmpty()) {
            auto *summary = smallLabel(b.summary, row2, DS::textSecondary());
            summary->setMaximumHeight(38); // ≤2 行
            v2->addWidget(summary);
        }
        if (!b.headShort.isEmpty()) {
            auto *tip = smallLabel(
                QStringLiteral("%1 · %2").arg(b.headShort, b.headAgo.isEmpty()
                        ? QStringLiteral("—")
                        : b.headAgo),
                row2, DS::textSecondary());
            tip->setToolTip(
                QStringLiteral("%1（%2 · %3）").arg(b.headSubject, b.head, b.headAgo));
            v2->addWidget(tip);
        }
        if (b.highlights.has_value()) {
            for (const QString &hl : *b.highlights)
                v2->addWidget(smallLabel(QStringLiteral("· %1").arg(hl), row2, DS::textSecondary()));
        }
        if (b.aheadOfDefault > 0 && !b.baselineReset)
            v2->addWidget(smallLabel(QStringLiteral("领先默认分支 %1").arg(b.aheadOfDefault), row2,
                DS::semColor(DS::SemColor::accent)));
        // staleText 三态颜色跟引擎 status，不自推
        {
            const QColor staleColor = Derived::branchStatusColor(b.status);
            auto *stale = smallLabel(Derived::staleText(b), row2,
                staleColor.isValid() ? staleColor : DS::textSecondary());
            v2->addWidget(stale);
        }
        if (b.nextSteps.has_value()) {
            for (const QString &n : *b.nextSteps)
                v2->addWidget(smallLabel(n, row2, DS::semColor(DS::SemColor::accent)));
        }
        v->addWidget(row2);
    }
    return card;
}

QWidget *ProjectDetailPage::buildMilestoneCard()
{
    auto *card = new Card(m_content);
    auto *v = new QVBoxLayout(card);
    v->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
    v->setSpacing(DS::Spacing::sm);
    auto *title = new QLabel(QStringLiteral("里程碑 · %1 条").arg(m_milestones.size()), card);
    title->setFont(DS::font(DS::FontT::cardTitle));
    v->addWidget(title);

    if (m_milestones.isEmpty()) {
        v->addWidget(smallLabel(QStringLiteral("还没有里程碑。在「里程碑」页创建；tag 出现即自动判定达成。"),
            card, DS::textSecondary()));
        return card;
    }

    // 达成率 done/(done+open) 百分比 + 进度条 +「· U 个读不出来（不计入分母）」
    const MsTally t = milestoneTally(m_milestones, nullptr);
    const int decided = t.done + t.open;
    auto *rateRow = new QHBoxLayout;
    if (decided > 0) {
        const int pct = qRound(t.done * 100.0 / decided);
        auto *bar = new DProgressBar(card);
        bar->setRange(0, 100);
        bar->setValue(pct);
        bar->setTextVisible(false);
        bar->setFixedHeight(DS::Height::bar);
        rateRow->addWidget(bar, 1);
        auto *pctLabel = new QLabel(QStringLiteral("%1%").arg(pct), card);
        pctLabel->setFont(DS::font(DS::FontT::label));
        rateRow->addWidget(pctLabel);
        if (t.unknown > 0)
            rateRow->addWidget(smallLabel(
                QStringLiteral("· %1 个读不出来（不计入分母）").arg(t.unknown), card,
                DS::semColor(DS::SemColor::orange)));
    } else {
        rateRow->addWidget(smallLabel(QStringLiteral("没有可计入达成率的里程碑"), card,
            DS::textSecondary()));
        if (t.unknown > 0)
            rateRow->addWidget(smallLabel(
                QStringLiteral("· %1 个读不出来（不计入分母）").arg(t.unknown), card,
                DS::semColor(DS::SemColor::orange)));
        rateRow->addStretch(1);
    }
    v->addLayout(rateRow);

    for (const Milestone &m : m_milestones) {
        auto *row = new MilestoneRowWidget(card);
        row->setMilestone(m, false);
        connect(row, &MilestoneRowWidget::doneClicked, this,
            [this](const QString &pr, const QString &n) { emit milestoneDone(pr, n); });
        connect(row, &MilestoneRowWidget::reopenClicked, this,
            [this](const QString &pr, const QString &n) { emit milestoneReopen(pr, n); });
        connect(row, &MilestoneRowWidget::dropClicked, this,
            [this](const QString &pr, const QString &n) { emit milestoneDrop(pr, n); });
        connect(row, &MilestoneRowWidget::removeClicked, this,
            [this](const QString &pr, const QString &n) { emit milestoneRemove(pr, n); });
        v->addWidget(row);
    }
    return card;
}

QWidget *ProjectDetailPage::buildJournalCard(const ProjectStatus &p)
{
    auto *card = new Card(m_content);
    auto *v = new QVBoxLayout(card);
    v->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
    v->setSpacing(DS::Spacing::sm);

    // 标题「进度日志 · <entryCountLine>」（「N 条」或「kept/entryCount 条（已截断）」）
    QString entryCountLine;
    if (p.progress.entryCountTruncated || p.progress.entryCount > p.progress.entriesKept)
        entryCountLine = QStringLiteral("%1/%2 条（已截断）")
                             .arg(p.progress.entriesKept)
                             .arg(p.progress.entryCount);
    else
        entryCountLine = QStringLiteral("%1 条").arg(p.progress.entryCount);
    auto *title = new QLabel(QStringLiteral("进度日志 · %1").arg(entryCountLine), card);
    title->setFont(DS::font(DS::FontT::cardTitle));
    v->addWidget(title);

    for (const JournalEntry &e : p.journal) {
        auto *entry = new QWidget(card);
        auto *ev = new QVBoxLayout(entry);
        ev->setContentsMargins(0, 0, 0, 0);
        ev->setSpacing(2);
        auto *head = new QHBoxLayout;
        head->setSpacing(DS::Spacing::xs);
        // modeLabel：快照/浅更新/深度更新/手动
        QString modeLabel;
        if (e.mode == QLatin1String("shallow"))
            modeLabel = QStringLiteral("浅更新");
        else if (e.mode == QLatin1String("deep"))
            modeLabel = QStringLiteral("深度更新");
        else if (e.mode == QLatin1String("track"))
            modeLabel = QStringLiteral("快照");
        else
            modeLabel = e.mode.isEmpty() ? QStringLiteral("手动") : e.mode;
        auto *mode = new Chip(modeLabel, entry);
        mode->setTone(DS::SemColor::gray);
        head->addWidget(mode);
        auto *branch = new QLabel(e.branch, entry);
        QFont mono(QStringLiteral("monospace"));
        mono.setStyleHint(QFont::Monospace);
        branch->setFont(mono);
        head->addWidget(branch);
        head->addStretch(1);
        // commitCountBadge：new 绿「+N 新增」/ repoTotal 灰「+N 累计」/ 读不出→橙 note / 0 不显示
        if (e.commitCount > 0) {
            auto *badge = new Chip(
                e.commitCountScope == QLatin1String("new")
                    ? QStringLiteral("+%1 新增").arg(e.commitCount)
                    : QStringLiteral("+%1 累计").arg(e.commitCount),
                entry);
            badge->setTone(e.commitCountScope == QLatin1String("new") ? DS::SemColor::shallow
                                                                      : DS::SemColor::gray);
            head->addWidget(badge);
        } else if (e.commitCount < 0 || e.commitCountTruncated) {
            auto *note = new Chip(QStringLiteral("提交数读不出来"), entry);
            note->setTone(DS::SemColor::orange);
            head->addWidget(note);
        }
        ev->addLayout(head);
        if (!e.summary.isEmpty())
            ev->addWidget(smallLabel(e.summary, entry, DS::textSecondary()));
        v->addWidget(entry);
    }

    // 尾部披露：journalTruncated / unparsableLines（两轴独立）
    if (p.journalTruncated)
        v->addWidget(smallLabel(
            QStringLiteral("只显示最近 %1 条（按 %2 条取的窗口，不是全部）")
                .arg(p.journal.size())
                .arg(p.journalLimit),
            card, DS::semColor(DS::SemColor::orange)));
    if (p.journalUnparsableLines > 0)
        v->addWidget(smallLabel(
            QStringLiteral("另有 %1 行日志解析不了（不是「日志到此为止」）").arg(p.journalUnparsableLines),
            card, DS::semColor(DS::SemColor::orange)));
    return card;
}

QWidget *ProjectDetailPage::buildDocsArea()
{
    auto *host = new QWidget(m_content);
    auto *v = new QVBoxLayout(host);
    v->setContentsMargins(0, 0, 0, 0);
    v->setSpacing(DS::Spacing::md);

    // 四态 docsPhase：content / failed（橙）/ loading / empty——三种「没有」三句不同的话
    if (m_docsState.state == LoadState::loading || m_docsState.state == LoadState::idle) {
        auto *loading = new QWidget(host);
        auto *lh = new QHBoxLayout(loading);
        auto *sp = new DSpinner(loading);
        sp->start();
        lh->addWidget(sp);
        lh->addWidget(new QLabel(QStringLiteral("读取文档…"), loading));
        lh->addStretch(1);
        v->addWidget(loading);
        return host;
    }
    if (m_docsState.state == LoadState::failed) {
        auto *card = new Card(host);
        card->clearPadding(); // 历史样式：该卡内容布局未设边距（走样式默认），kPadding 会叠双份
        auto *cv = new QVBoxLayout(card);
        cv->addWidget(smallLabel(QStringLiteral("读不出来：%1").arg(m_docsState.message), card,
            DS::semColor(DS::SemColor::orange)));
        v->addWidget(card);
        return host;
    }
    if (!m_docs.has_value() || m_docs->docs.empty()) {
        auto *card = new Card(host);
        card->clearPadding(); // 历史样式：该卡内容布局未设边距（走样式默认），kPadding 会叠双份
        auto *cv = new QVBoxLayout(card);
        cv->addWidget(smallLabel(
            QStringLiteral("这个项目还没有受管的文档。跑一次浅更新会生成 README / AGENTS / CLAUDE。"),
            card, DS::textSecondary()));
        v->addWidget(card);
        return host;
    }

    // 每文件一张卡（标题=文件名，内容 MarkdownView）
    for (const DocFile &f : m_docs->docs) {
        auto *card = new Card(host);
        auto *cv = new QVBoxLayout(card);
        cv->setContentsMargins(0, 0, 0, 0); // 内距走 Card::kPadding（构造即设）
        cv->setSpacing(DS::Spacing::sm);
        auto *title = new QLabel(f.file, card);
        title->setFont(DS::font(DS::FontT::cardTitle));
        cv->addWidget(title);
        auto *md = new MarkdownView(card);
        md->setMarkdownText(f.content);
        cv->addWidget(md);
        v->addWidget(card);
    }
    return host;
}
