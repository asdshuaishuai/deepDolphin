#include "CodeGraphDialog.h"

#include "../../app/AppModel.h"
#include "../../logic/ArchReceipt.h"
#include "../../logic/CodeGraphBuild.h"
#include "../../models/CodeGraph.h"
#include "../DesignTokens.h"
#include "../common/FlatButton.h"
#include "../common/SecondaryLabel.h"

#include <QHBoxLayout>
#include <QHeaderView>
#include <QLabel>
#include <QLineEdit>
#include <QPlainTextEdit>
#include <QSet>
#include <QSplitter>
#include <QTextCharFormat>
#include <QTreeWidget>
#include <QVBoxLayout>
#include <functional>

namespace {
constexpr int kNodeRole = Qt::UserRole + 1; ///< QTreeWidgetItem 上的 arena 索引

QString kindLabel(GraphNodeKind k)
{
    switch (k) {
    case GraphNodeKind::root:
        return QStringLiteral("仓库");
    case GraphNodeKind::dir:
        return QStringLiteral("目录");
    case GraphNodeKind::file:
        return QStringLiteral("文件");
    case GraphNodeKind::sym:
        return QStringLiteral("符号");
    }
    return QString();
}
} // namespace

CodeGraphDialog::CodeGraphDialog(const QString &projectName, AppModel *model, QWidget *parent)
    : DDialog(parent)
    , m_project(projectName)
    , m_model(model)
{
    setWindowTitle(QStringLiteral("代码图谱 · %1").arg(m_project));
    resize(1180, 760);
    setMinimumSize(820, 520);
    setOnButtonClickedClose(false);

    auto *content = new QWidget(this);
    auto *v = new QVBoxLayout(content);
    v->setContentsMargins(0, 0, 0, 0);
    v->setSpacing(DS::Spacing::sm);

    // ── 顶栏：项目名 + 刷新/生成/导出 + 置信度总分 ──
    auto *top = new QHBoxLayout;
    top->setSpacing(DS::Spacing::xs);
    auto *title = new QLabel(m_project, content);
    title->setFont(DS::font(DS::FontT::sectionTitle));
    top->addWidget(title);
    top->addStretch(1);

    auto *reloadBtn = new FlatButton(content);
    reloadBtn->setText(QStringLiteral("刷新"));
    reloadBtn->setToolTip(QStringLiteral("重新读取代码图谱"));
    connect(reloadBtn, &QPushButton::clicked, this, [this] { reload(); });
    top->addWidget(reloadBtn);

    // 生成：引擎 index gen + confidence gen（写库/落盘 —— 经引擎写）
    auto *genBtn = new FlatButton(content);
    genBtn->setText(QStringLiteral("生成"));
    genBtn->setToolTip(QStringLiteral("生成符号索引与置信度（引擎 index gen / confidence gen）"));
    connect(genBtn, &QPushButton::clicked, this, [this] {
        m_errorBar->hide();
        m_model->genIndex(m_project);
    });
    top->addWidget(genBtn);

    // 导出：引擎 render index --confidence（落盘交互 HTML —— 引擎层交付物）
    auto *exportBtn = new FlatButton(content);
    exportBtn->setText(QStringLiteral("导出"));
    exportBtn->setToolTip(QStringLiteral("导出交互 HTML（引擎 render index --confidence）"));
    connect(exportBtn, &QPushButton::clicked, this, [this] {
        m_errorBar->hide();
        m_model->exportIndex(m_project);
    });
    top->addWidget(exportBtn);

    m_score = new SecondaryLabel(QString(), content);
    top->addWidget(m_score);
    v->addLayout(top);

    // ── 错误条 ──
    m_errorBar = new QLabel(content);
    m_errorBar->setWordWrap(true);
    m_errorBar->setStyleSheet(
        QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
    m_errorBar->hide();
    v->addWidget(m_errorBar);

    // ── 回执行：引擎回执末行（版本/探针/自愈披露给用户看）──
    auto *receiptRow = new QHBoxLayout;
    receiptRow->setSpacing(DS::Spacing::xs);
    m_receipt = new SecondaryLabel(QString(), content);
    m_receipt->setWordWrap(true);
    m_receipt->hide();
    receiptRow->addWidget(m_receipt, 1);
    m_openExport = new FlatButton(content);
    m_openExport->setText(QStringLiteral("打开导出文件"));
    m_openExport->hide();
    connect(m_openExport, &QPushButton::clicked, this,
        [this] { emit openExportedFile(m_exportedPath); });
    receiptRow->addWidget(m_openExport);
    v->addLayout(receiptRow);

    // ── 两栏 ──
    auto *split = new QSplitter(Qt::Horizontal, content);

    // 左栏：搜索 + 列表树
    auto *left = new QWidget(split);
    auto *lv = new QVBoxLayout(left);
    lv->setContentsMargins(0, 0, 0, 0);
    lv->setSpacing(DS::Spacing::xs);
    m_search = new QLineEdit(left);
    m_search->setPlaceholderText(QStringLiteral("搜索文件或符号…"));
    m_search->setClearButtonEnabled(true);
    connect(m_search, &QLineEdit::textChanged, this, &CodeGraphDialog::onSearchChanged);
    lv->addWidget(m_search);
    m_tree = new QTreeWidget(left);
    m_tree->setHeaderHidden(true);
    m_tree->setUniformRowHeights(true);
    m_tree->setColumnCount(1);
    connect(m_tree, &QTreeWidget::itemActivated, this, &CodeGraphDialog::onItemActivated);
    connect(m_tree, &QTreeWidget::itemClicked, this, [this](QTreeWidgetItem *item, int) {
        onItemActivated(item, 0);
    });
    connect(m_tree, &QTreeWidget::itemExpanded, this, [this](QTreeWidgetItem *item) {
        const int idx = nodeIndexOf(item);
        if (idx < 0)
            return;
        const CodeGraphBuild::Result *g = m_model ? m_model->codeGraphFor(m_project) : nullptr;
        if (!g)
            return;
        const QString id = g->graph.nodes.at(idx).id;
        if (!m_expanded.contains(id))
            m_expanded << id;
    });
    connect(m_tree, &QTreeWidget::itemCollapsed, this, [this](QTreeWidgetItem *item) {
        const int idx = nodeIndexOf(item);
        if (idx < 0)
            return;
        const CodeGraphBuild::Result *g = m_model ? m_model->codeGraphFor(m_project) : nullptr;
        if (!g)
            return;
        m_expanded.removeAll(g->graph.nodes.at(idx).id);
    });
    lv->addWidget(m_tree, 1);
    split->addWidget(left);

    // 右栏：详情头 + 页签 + 详情体
    auto *right = new QWidget(split);
    auto *rv = new QVBoxLayout(right);
    rv->setContentsMargins(0, 0, 0, 0);
    rv->setSpacing(DS::Spacing::xs);
    m_detailTitle = new QLabel(right);
    m_detailTitle->setFont(DS::font(DS::FontT::sectionTitle));
    m_detailTitle->setWordWrap(true);
    rv->addWidget(m_detailTitle);

    auto *tabs = new QHBoxLayout;
    tabs->setSpacing(DS::Spacing::xs);
    m_tabSource = new FlatButton(right);
    m_tabSource->setText(QStringLiteral("源码"));
    connect(m_tabSource, &QPushButton::clicked, this, [this] {
        m_tab = DetailTab::source;
        showDetail();
    });
    tabs->addWidget(m_tabSource);
    m_tabConfidence = new FlatButton(right);
    m_tabConfidence->setText(QStringLiteral("置信度"));
    connect(m_tabConfidence, &QPushButton::clicked, this, [this] {
        m_tab = DetailTab::confidence;
        showDetail();
    });
    tabs->addWidget(m_tabConfidence);
    m_tabRelation = new FlatButton(right);
    m_tabRelation->setText(QStringLiteral("关系"));
    connect(m_tabRelation, &QPushButton::clicked, this, [this] {
        m_tab = DetailTab::relation;
        showDetail();
    });
    tabs->addWidget(m_tabRelation);
    tabs->addStretch(1);
    rv->addLayout(tabs);

    m_source = new QPlainTextEdit(right);
    m_source->setReadOnly(true);
    m_source->setLineWrapMode(QPlainTextEdit::NoWrap);
    m_source->setFont(QFont(DS::font(DS::FontT::body).family(),
        DS::font(DS::FontT::body).pointSize(), QFont::Monospace));
    rv->addWidget(m_source, 1);

    m_findings = new QTreeWidget(right);
    m_findings->setColumnCount(4);
    m_findings->setHeaderLabels({ QStringLiteral("类型"), QStringLiteral("行"),
        QStringLiteral("权重"), QStringLiteral("证据") });
    m_findings->header()->setSectionResizeMode(3, QHeaderView::Stretch);
    rv->addWidget(m_findings, 1);

    m_relations = new QTreeWidget(right);
    m_relations->setColumnCount(3);
    m_relations->setHeaderLabels({ QStringLiteral("方向"), QStringLiteral("符号"),
        QStringLiteral("位置") });
    m_relations->header()->setSectionResizeMode(2, QHeaderView::Stretch);
    rv->addWidget(m_relations, 1);

    split->addWidget(right);
    split->setStretchFactor(0, 2);
    split->setStretchFactor(1, 3);
    v->addWidget(split, 1);

    addContent(content);
    addButton(QStringLiteral("关闭"), true);

    if (m_model) {
        connect(m_model, &AppModel::codeGraphChanged, this, [this](const QString &name) {
            if (name == m_project)
                refreshData();
        });
        // 生成/导出的回执与架构图页共用一个信号（都是「引擎跑完给一句话」）
        connect(m_model, &AppModel::archActionFinished, this,
            [this](bool ok, const QString &project, const QString &receipt) {
                if (project != m_project)
                    return;
                if (!ok) {
                    showError(receipt);
                    return;
                }
                showReceipt(receipt);
            });
    }

    reload();
}

void CodeGraphDialog::reload()
{
    m_errorBar->hide();
    if (m_model)
        m_model->loadCodeGraph(m_project);
}

void CodeGraphDialog::refreshData()
{
    const LoadStateBox st = m_model ? m_model->codeGraphState(m_project) : LoadStateBox();
    if (st.state == LoadState::failed) {
        showError(st.message);
        m_tree->clear();
        m_score->setText(QString());
        return;
    }
    if (st.state != LoadState::loaded) {
        m_errorBar->hide();
        return;
    }
    m_errorBar->hide();
    m_selected = -1;
    m_expanded.clear();
    rebuildTree();
    updateScore();
    showDetail();
}

void CodeGraphDialog::rebuildTree()
{
    const CodeGraphBuild::Result *g = m_model ? m_model->codeGraphFor(m_project) : nullptr;
    m_tree->clear();
    if (!g || g->graph.root < 0)
        return;
    // 默认展开：根 + 一级目录（与 HTML 交付物同款）
    m_expanded.clear();
    m_expanded << g->graph.nodes.at(g->graph.root).id;
    for (int k : g->graph.nodes.at(g->graph.root).kids) {
        const GraphNode &n = g->graph.nodes.at(k);
        if (n.kind == GraphNodeKind::dir)
            m_expanded << n.id;
    }

    // 用纯函数算出的可见行重建树（**可见性以判定层为准**）：
    // 行是 DFS 序 + 深度，按深度把项挂到对应父项下。
    const auto rows = CodeGraphBuild::visibleRows(g->graph, m_expanded, m_query);
    QVector<QTreeWidgetItem *> stack; // 按深度
    for (const GraphTreeRow &row : rows) {
        const GraphNode *n = g->graph.node(row.node);
        if (!n)
            continue;
        auto *item = new QTreeWidgetItem();
        item->setText(0, n->name);
        item->setData(0, kNodeRole, row.node);
        item->setToolTip(0, n->kind == GraphNodeKind::sym
                ? QStringLiteral("%1 · %2:%3").arg(n->symKind, n->path).arg(n->declLine)
                : n->path);
        // 疑点徽标：子树疑点数（0 不占位）
        if (n->rollN > 0) {
            item->setText(1, QString::number(n->rollN));
            item->setToolTip(1, QStringLiteral("子树疑点 %1 个（最高权重 %2）")
                                 .arg(n->rollN)
                                 .arg(n->rollW));
        }
        if (row.depth == 0) {
            m_tree->addTopLevelItem(item);
            stack.clear();
            stack << item;
        } else {
            if (stack.size() >= row.depth)
                stack[row.depth - 1]->addChild(item);
            stack.resize(row.depth);
            stack << item;
        }
    }
    m_tree->setColumnCount(2);
    m_tree->header()->setSectionHidden(1, true);
    applyVisibility();
}

void CodeGraphDialog::applyVisibility()
{
    const CodeGraphBuild::Result *g = m_model ? m_model->codeGraphFor(m_project) : nullptr;
    if (!g)
        return;
    // 可见集合以纯函数为准（搜索命中 + 展开态）
    const auto rows = CodeGraphBuild::visibleRows(g->graph, m_expanded, m_query);
    QSet<int> visible;
    for (const GraphTreeRow &row : rows)
        visible.insert(row.node);

    // 树控件的项 → arena 索引
    const std::function<void(QTreeWidgetItem *)> mark
        = [&](QTreeWidgetItem *item) {
            const int idx = item->data(0, kNodeRole).toInt();
            item->setHidden(!visible.contains(idx));
            for (int i = 0; i < item->childCount(); ++i)
                mark(item->child(i));
        };
    for (int i = 0; i < m_tree->topLevelItemCount(); ++i)
        mark(m_tree->topLevelItem(i));

    // 搜索态：命中路径上的祖先要展开，否则「看得见命中、看不见路径」
    if (!m_query.trimmed().isEmpty()) {
        const std::function<void(QTreeWidgetItem *)> expand
            = [&](QTreeWidgetItem *item) {
                bool anyVisibleChild = false;
                for (int i = 0; i < item->childCount(); ++i) {
                    expand(item->child(i));
                    if (!item->child(i)->isHidden())
                        anyVisibleChild = true;
                }
                if (anyVisibleChild)
                    item->setExpanded(true);
            };
        for (int i = 0; i < m_tree->topLevelItemCount(); ++i)
            expand(m_tree->topLevelItem(i));
    }
}

int CodeGraphDialog::nodeIndexOf(QTreeWidgetItem *item) const
{
    if (!item)
        return -1;
    return item->data(0, kNodeRole).toInt();
}

void CodeGraphDialog::onItemActivated(QTreeWidgetItem *item, int column)
{
    Q_UNUSED(column);
    const int idx = nodeIndexOf(item);
    if (idx < 0)
        return;
    m_selected = idx;
    // 选中符号默认看源码，选容器看置信度（mac 同款）
    const CodeGraphBuild::Result *g = m_model ? m_model->codeGraphFor(m_project) : nullptr;
    if (g) {
        const GraphNode &n = g->graph.nodes.at(idx);
        m_tab = n.kind == GraphNodeKind::sym ? DetailTab::source : DetailTab::confidence;
    }
    showDetail();
}

void CodeGraphDialog::onSearchChanged(const QString &text)
{
    m_query = text;
    applyVisibility();
}

void CodeGraphDialog::updateScore()
{
    const CodeGraphBuild::Result *g = m_model ? m_model->codeGraphFor(m_project) : nullptr;
    if (!g) {
        m_score->setText(QString());
        return;
    }
    QString text = QStringLiteral("置信度 %1").arg(g->score);
    // 截断披露：0 与「没发」可区分（present 标志）→ 有截断就说清
    if (g->truncatedPresent && g->truncated)
        text += QStringLiteral(" · 已截断");
    if (g->skippedPresent && g->skipped > 0)
        text += QStringLiteral(" · 跳过 %1").arg(g->skipped);
    if (g->oversizeSkippedPresent && g->oversizeSkipped > 0)
        text += QStringLiteral(" · 超限跳过 %1").arg(g->oversizeSkipped);
    if (!g->astNote.isEmpty())
        text += QStringLiteral(" · 语法树降级");
    m_score->setText(text);
}

void CodeGraphDialog::showDetail()
{
    const CodeGraphBuild::Result *g = m_model ? m_model->codeGraphFor(m_project) : nullptr;
    m_source->hide();
    m_findings->hide();
    m_relations->hide();
    if (!g || m_selected < 0) {
        m_detailTitle->setText(QStringLiteral("未选中节点"));
        return;
    }
    const GraphNode &n = g->graph.nodes.at(m_selected);
    QString title = n.name;
    if (n.kind == GraphNodeKind::sym)
        title = QStringLiteral("%1 · %2:%3").arg(n.name, n.path).arg(n.declLine);
    else if (n.kind == GraphNodeKind::file)
        title = QStringLiteral("%1（%2 行）").arg(n.name).arg(n.lines);
    else if (n.kind == GraphNodeKind::dir)
        title = QStringLiteral("%1/").arg(n.name);
    if (n.rollN > 0)
        title += QStringLiteral(" · 疑点 %1").arg(n.rollN);
    m_detailTitle->setText(title);

    switch (m_tab) {
    case DetailTab::source:
        m_source->show();
        showSource();
        break;
    case DetailTab::confidence:
        m_findings->show();
        showConfidence();
        break;
    case DetailTab::relation:
        m_relations->show();
        showRelation();
        break;
    }
}

void CodeGraphDialog::showSource()
{
    const CodeGraphBuild::Result *g = m_model ? m_model->codeGraphFor(m_project) : nullptr;
    m_source->clear();
    if (!g || m_selected < 0)
        return;
    const GraphNode &n = g->graph.nodes.at(m_selected);
    const QString code = g->snippets.value(n.id);
    if (code.isEmpty()) {
        m_source->setPlainText(
            n.kind == GraphNodeKind::sym
                ? QStringLiteral("（没有该符号的源码片段 —— 引擎未提供或已截断）")
                : QStringLiteral("（源码页签只对符号有效）"));
        return;
    }
    const QStringList lines = code.split(QLatin1Char('\n'));
    QStringList out;
    for (int i = 0; i < lines.size(); ++i)
        out << QStringLiteral("%1\t%2").arg(n.declLine + i, 5).arg(lines.at(i));
    m_source->setPlainText(out.join(QLatin1Char('\n')));
}

void CodeGraphDialog::showConfidence()
{
    const CodeGraphBuild::Result *g = m_model ? m_model->codeGraphFor(m_project) : nullptr;
    m_findings->clear();
    if (!g || m_selected < 0)
        return;
    const GraphNode &n = g->graph.nodes.at(m_selected);
    // 本节点直接挂着的疑点 + 子树汇总（子树疑点总数在标题上已给）
    for (const GraphFinding &f : n.ownFindings) {
        auto *it = new QTreeWidgetItem(m_findings);
        it->setText(0, f.label.isEmpty() ? f.kind : f.label);
        it->setText(1, QString::number(f.line));
        it->setText(2, QString::number(f.weight));
        it->setText(3, f.evidence);
        if (f.weight >= 10)
            it->setForeground(2, DS::semColor(DS::SemColor::red));
        else if (f.weight >= 5)
            it->setForeground(2, DS::semColor(DS::SemColor::orange));
    }
    if (n.ownFindings.isEmpty()) {
        auto *it = new QTreeWidgetItem(m_findings);
        it->setText(0, QStringLiteral("（本节点没有直接挂着的疑点）"));
    }
}

void CodeGraphDialog::showRelation()
{
    const CodeGraphBuild::Result *g = m_model ? m_model->codeGraphFor(m_project) : nullptr;
    m_relations->clear();
    if (!g || m_selected < 0)
        return;
    const QString id = g->graph.nodes.at(m_selected).id;
    int callers = 0;
    int callees = 0;
    for (const GraphSymEdge &e : g->symEdges) {
        const bool isCaller = e.to == id;
        const bool isCallee = e.from == id;
        if (!isCaller && !isCallee)
            continue;
        const QString otherId = isCaller ? e.from : e.to;
        const int otherIdx = g->graph.indexOf(otherId);
        const GraphNode *other = g->graph.node(otherIdx);
        auto *it = new QTreeWidgetItem(m_relations);
        it->setText(0, isCaller ? QStringLiteral("调用方") : QStringLiteral("被调方"));
        it->setText(1, other ? other->name : otherId);
        it->setText(2, other ? QStringLiteral("%1:%2").arg(other->path).arg(other->declLine)
                              : QString());
        if (e.tier != QLatin1String("resolved"))
            it->setToolTip(2, QStringLiteral("调用边是词法近似（%1）").arg(e.tier));
        if (isCaller)
            ++callers;
        else
            ++callees;
    }
    if (callers == 0 && callees == 0) {
        auto *it = new QTreeWidgetItem(m_relations);
        it->setText(0, QStringLiteral("（没有调用关系 —— 引擎的调用边是词法近似，可能漏）"));
    }
}

void CodeGraphDialog::showError(const QString &text)
{
    m_errorBar->setText(text);
    m_errorBar->show();
    m_receipt->hide();
}

void CodeGraphDialog::showReceipt(const QString &text)
{
    const QString line = ArchReceipt::receipt(text);
    m_receipt->setText(line);
    m_receipt->setVisible(!line.isEmpty());
    m_exportedPath = ArchReceipt::htmlPath(text);
    m_openExport->setVisible(!m_exportedPath.isEmpty());
    m_openExport->setToolTip(m_exportedPath);
}
