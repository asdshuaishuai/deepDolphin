#include "ArchDialog.h"

#include "../../app/AppModel.h"
#include "../../logic/ArchReceipt.h"
#include "../../models/LoadState.h"
#include "../ArchCanvasWidget.h"
#include "../DesignTokens.h"
#include "../common/FlatButton.h"
#include "../common/SecondaryLabel.h"

#include <DComboBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QVBoxLayout>

ArchDialog::ArchDialog(const QString &projectName, AppModel *model, QWidget *parent)
    : DDialog(parent)
    , m_project(projectName)
    , m_model(model)
{
    setWindowTitle(QStringLiteral("架构图 · %1").arg(m_project));
    resize(1080, 720);
    setMinimumSize(720, 480);
    setOnButtonClickedClose(false);

    auto *content = new QWidget(this);
    auto *v = new QVBoxLayout(content);
    v->setContentsMargins(0, 0, 0, 0);
    v->setSpacing(DS::Spacing::sm);

    // ── 页头：项目名 + 刷新 / 生成 / 导出（mac ArchPage 页头同款）──
    auto *head = new QHBoxLayout;
    head->setSpacing(DS::Spacing::xs);
    auto *title = new QLabel(m_project, content);
    title->setFont(DS::font(DS::FontT::sectionTitle));
    head->addWidget(title);
    head->addStretch(1);

    auto *refresh = new FlatButton(content);
    refresh->setText(QStringLiteral("刷新"));
    refresh->setToolTip(QStringLiteral("重新读取架构图场景"));
    connect(refresh, &QPushButton::clicked, this, [this] { reload(); });
    head->addWidget(refresh);

    // 生成：引擎 `arch gen`（写 arch.json —— 经引擎写，客户端不碰项目文件）
    auto *gen = new FlatButton(content);
    gen->setText(QStringLiteral("生成"));
    gen->setToolTip(QStringLiteral("重新生成架构数据（引擎 arch gen）"));
    connect(gen, &QPushButton::clicked, this, [this] {
        m_errorBar->hide();
        m_model->genArch(m_project);
    });
    head->addWidget(gen);

    // 导出：引擎 `render arch`（落盘交互 HTML —— 引擎层交付物）
    auto *exportBtn = new FlatButton(content);
    exportBtn->setText(QStringLiteral("导出"));
    exportBtn->setToolTip(QStringLiteral("导出交互 HTML（引擎 render arch）"));
    connect(exportBtn, &QPushButton::clicked, this, [this] {
        m_errorBar->hide();
        m_model->exportArch(m_project);
    });
    head->addWidget(exportBtn);
    v->addLayout(head);

    // ── 错误条（mac 的橙色错误行同款）──
    m_errorBar = new QLabel(content);
    m_errorBar->setWordWrap(true);
    m_errorBar->setStyleSheet(
        QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
    m_errorBar->hide();
    v->addWidget(m_errorBar);

    // ── 回执行：引擎回执末行（版本/探针/违规数直接给用户看）──
    auto *receiptRow = new QHBoxLayout;
    receiptRow->setSpacing(DS::Spacing::xs);
    m_receipt = new SecondaryLabel(QString(), content);
    m_receipt->setWordWrap(true);
    m_receipt->hide();
    receiptRow->addWidget(m_receipt, 1);
    // 导出成功后出现：打开落盘的 HTML（mac openExport 同款）
    m_openExport = new FlatButton(content);
    m_openExport->setText(QStringLiteral("打开导出文件"));
    m_openExport->setToolTip(m_exportedPath);
    m_openExport->hide();
    connect(m_openExport, &QPushButton::clicked, this,
        [this] { emit openExportedFile(m_exportedPath); });
    receiptRow->addWidget(m_openExport);
    v->addLayout(receiptRow);

    // ── 画布工具条：视图切换 / 复位 / 主题（mac 画布浮层工具条同款）──
    auto *tools = new QHBoxLayout;
    tools->setSpacing(DS::Spacing::xs);
    m_viewBox = new DComboBox(content);
    m_viewBox->setSizeAdjustPolicy(QComboBox::AdjustToContents);
    m_viewBox->setToolTip(QStringLiteral("切换视图（arch / 各模块）"));
    connect(m_viewBox, &QComboBox::currentIndexChanged, this, [this](int idx) {
        if (idx < 0)
            return;
        const QString id = m_viewBox->itemData(idx).toString();
        if (!m_canvas->setCurrentView(id))
            m_viewBox->setCurrentIndex(m_canvas->currentViewId() == id ? idx : 0);
    });
    tools->addWidget(m_viewBox);

    auto *fit = new FlatButton(content);
    fit->setText(QStringLiteral("复位"));
    fit->setToolTip(QStringLiteral("回到自适应视图"));
    connect(fit, &QPushButton::clicked, this, [this] { m_canvas->refit(); });
    tools->addWidget(fit);

    auto *theme = new FlatButton(content);
    theme->setText(QStringLiteral("深色"));
    theme->setToolTip(QStringLiteral("切换画布深浅主题"));
    connect(theme, &QPushButton::clicked, this, [this, theme] {
        const bool next = !m_canvas->dark();
        m_canvas->setDark(next);
        theme->setText(next ? QStringLiteral("浅色") : QStringLiteral("深色"));
    });
    tools->addWidget(theme);

    tools->addStretch(1);
    m_selected = new SecondaryLabel(QString(), content);
    tools->addWidget(m_selected);
    v->addLayout(tools);

    // ── 画布 ──
    m_canvas = new ArchCanvasWidget(content);
    connect(m_canvas, &ArchCanvasWidget::nodeSelected, this, [this](const QString &id) {
        m_selected->setText(id.isEmpty() ? QString() : QStringLiteral("已选：%1").arg(id));
    });
    v->addWidget(m_canvas, 1);

    // ── 披露行：违规 / 环 / 被丢弃的边 / 分层 chips ──
    // 契约要求「警示与截断必须如实披露」（缺键不得当作「没有」）。
    auto *footer = new QHBoxLayout;
    footer->setSpacing(DS::Spacing::md);
    m_warnBar = new SecondaryLabel(QString(), content);
    m_warnBar->setStyleSheet(
        QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
    footer->addWidget(m_warnBar);
    m_droppedBar = new SecondaryLabel(QString(), content);
    footer->addWidget(m_droppedBar);
    m_boundsWarn = new SecondaryLabel(QString(), content);
    m_boundsWarn->setStyleSheet(
        QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
    footer->addWidget(m_boundsWarn);
    footer->addStretch(1);
    m_chips = new SecondaryLabel(QString(), content);
    footer->addWidget(m_chips);
    v->addLayout(footer);

    addContent(content);
    addButton(QStringLiteral("关闭"), true);

    // ── 引擎回执 / 场景变更 ──
    if (m_model) {
        connect(m_model, &AppModel::archActionFinished, this,
            [this](bool ok, const QString &project, const QString &receipt) {
                // 回执按项目路由：两个项目的架构图窗可以同时开着，
                // 串台就会在错误的窗口里显示回执/触发重载。
                if (project != m_project)
                    return;
                if (!ok) {
                    showError(receipt);
                    return;
                }
                showReceipt(receipt);
                // 生成后重载画布（场景是引擎算出来的，客户端不自造）
                if (receipt.contains(QStringLiteral("架构已生成")))
                    reload();
            });
        connect(m_model, &AppModel::sceneChanged, this, [this](const QString &name) {
            if (name == m_project)
                refreshScene();
        });
    }

    reload();
}

void ArchDialog::reload()
{
    m_errorBar->hide();
    if (m_model)
        m_model->loadScene(m_project);
}

void ArchDialog::showError(const QString &text)
{
    m_errorBar->setText(text);
    m_errorBar->show();
    m_receipt->hide();
}

void ArchDialog::showReceipt(const QString &text)
{
    const QString line = ArchReceipt::receipt(text);
    m_receipt->setText(line);
    m_receipt->setVisible(!line.isEmpty());
    // 导出成功 → 从回执里抽出落盘路径，给一个「打开」入口（mac openExport 同款）
    m_exportedPath = ArchReceipt::htmlPath(text);
    m_openExport->setVisible(!m_exportedPath.isEmpty());
    m_openExport->setToolTip(m_exportedPath);
}

void ArchDialog::refreshScene()
{
    const LoadStateBox st = m_model ? m_model->sceneState(m_project) : LoadStateBox();
    if (st.state == LoadState::failed) {
        showError(st.message);
        return;
    }
    if (st.state != LoadState::loaded) {
        // 加载中：**不清画布** —— mac 同款（旧内容留到新内容到位，
        // 否则点一次「刷新」画布就白闪一下）。
        m_errorBar->hide();
        return;
    }
    m_errorBar->hide();
    const GraphScene *scene = m_model ? m_model->sceneFor(m_project) : nullptr;
    // 记下当前视图：setScene 之后要能把它放回下拉（场景换了不该把用户拽回 arch）
    const QString keep = m_canvas->currentViewId();
    m_canvas->setScene(scene ? std::optional<GraphScene>(*scene) : std::nullopt);

    // 视图下拉：按契约顺序（arch 恒第一）。每次重建（场景换了，标签可能变了），
    // 但**保留当前视图**（重建下拉不该把用户正在看的视图拽回 arch）。
    const QStringList ids = m_canvas->viewIds();
    m_viewBox->blockSignals(true);
    m_viewBox->clear();
    for (const QString &id : ids) {
        const GraphView *v = scene ? scene->view(id) : nullptr;
        m_viewBox->addItem(v && !v->label.isEmpty() ? v->label : id, id);
    }
    const int keepIdx = m_viewBox->findData(keep);
    m_viewBox->setCurrentIndex(keepIdx >= 0 ? keepIdx : 0);
    m_viewBox->blockSignals(false);
    refreshFooter();
}

void ArchDialog::refreshFooter()
{
    const GraphScene *scene = m_model ? m_model->sceneFor(m_project) : nullptr;
    if (!scene) {
        m_warnBar->setText(QString());
        m_droppedBar->setText(QString());
        m_chips->setText(QString());
        m_boundsWarn->setText(QString());
        return;
    }
    // 警示：违规 + 环（恒发字段，0 也发 —— 0 就当没有）。
    // ⚠ 缺键时值全是 0，与「确实没有违规」不可区分 → 必须说「未知」，
    //   不能显示成「没有违规」（缺字段不回落成 0 的同一条纪律）。
    const GraphWarnings &w = scene->warnings;
    if (!scene->warningsPresent) {
        m_warnBar->setText(QStringLiteral("告警未知（契约可能过旧）"));
    } else if (w.violations > 0 || w.cycleEdges > 0) {
        m_warnBar->setText(QStringLiteral("违规 %1 · 环边 %2").arg(w.violations).arg(w.cycleEdges));
    } else {
        m_warnBar->setText(QString());
    }

    // 被丢弃的边：>0 才说（0 = 没丢边，不占位）；缺键 → 未知，不是「没丢」。
    const GraphView *v = scene->view(QStringLiteral("arch"));
    if (!v || !v->edgesDroppedPresent) {
        m_droppedBar->setText(QStringLiteral("被丢弃的边数未知（契约可能过旧）"));
    } else if (v->edgesDropped > 0) {
        m_droppedBar->setText(QStringLiteral("已丢弃边 %1").arg(v->edgesDropped));
    } else {
        m_droppedBar->setText(QString());
    }

    // 缺包围盒的视图：这些视图只能按恒等视口画（看起来就是「没缩放」），
    // 原因必须说给用户听。
    if (scene->viewsMissingBounds > 0) {
        m_boundsWarn->setText(
            QStringLiteral("%1 个视图缺包围盒（无法自适应）").arg(scene->viewsMissingBounds));
    } else {
        m_boundsWarn->setText(QString());
    }

    // 分层 chips：count 是**数字字段**，布局读它，不从 label 抠数字
    if (!scene->chipsPresent) {
        m_chips->setText(QStringLiteral("分层未知（契约可能过旧）"));
        return;
    }
    QStringList chipTexts;
    for (const GraphChip &c : scene->chips)
        chipTexts << QStringLiteral("%1 %2").arg(c.label).arg(c.count);
    m_chips->setText(chipTexts.join(QStringLiteral(" · ")));
}
