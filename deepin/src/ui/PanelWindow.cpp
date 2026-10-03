#include "PanelWindow.h"
#include "../ai/AIConfig.h"
#include "../ai/AIEngineFactory.h"
#include "../ai/AiDigests.h"
#include "../ai/SecretStore.h"
#include "../logic/DashboardScope.h"
#include "../logic/Derived.h"
#include "../logic/Router.h"
#include "../logic/ShortcutMap.h"
#include "../tray/TrayController.h"
#include "DesignTokens.h"
#include "DualTrackButtons.h"
#include "SidebarNav.h"
#include "WorkBar.h"
#include "common/ConfirmDialog.h"
#include "common/EmptyState.h"
#include "dialogs/AddMilestoneDialog.h"
#include "dialogs/AgentDialog.h"
#include "dialogs/AiResultDialog.h"
#include "dialogs/AiSettingsDialog.h"
#include "../app/Settings.h"
#include "dialogs/ScanDialog.h"
#include "dialogs/panes/AutomationPane.h"
#include "pages/BoardPage.h"
#include "pages/DashboardPage.h"
#include "pages/MilestonesPage.h"
#include "pages/ProjectDetailPage.h"
#include "pages/SetupGuidePage.h"
#include <DGuiApplicationHelper>
#include <DIconButton>
#include <DPushButton>
#include <QApplication>
#include <QCloseEvent>
#include <QCursor>
#include <QDateTime>
#include <QHBoxLayout>
#include <QLocale>
#include <QMenu>
#include <QMetaObject>
#include <QPointer>
#include <QPushButton>
#include <QShortcut>
#include <QSplitter>
#include <QStackedWidget>
#include <QThreadPool>
#include <QTimer>
#include <QVBoxLayout>
#include <QVector>
#include <dtitlebar.h>
#include <memory>

namespace {
// 工具栏图标钮：主题图标在位 → DIconButton（DTK 尺寸/观感接管）；解析不到
//（无图标主题的环境）→ 文字平钮。空按钮比非原生按钮更糟（R2 诚实降级）；
// 真机 DDE 必有图标主题，恒走图标分支。DIconButton 不开放 setText，回退必须换类。
QAbstractButton *makeToolButton(const QString &iconName, const QString &fallbackText,
    const QString &tooltip)
{
    const QIcon icon = QIcon::fromTheme(iconName);
    if (icon.isNull()) {
        auto *btn = new DPushButton;
        btn->setText(fallbackText);
        btn->setFlat(true);
        btn->setToolTip(tooltip);
        return btn;
    }
    auto *btn = new DIconButton;
    btn->setIcon(icon);
    btn->setToolTip(tooltip);
    return btn;
}

constexpr int kMinW = 940, kMinH = 620;
constexpr int kDefaultW = 1100, kDefaultH = 720;
constexpr int kSidebarMinWidth = 210;

enum PageIndex {
    PageSetupGuide = 0,
    PageDashboard,
    PageBoard,
    PageMilestones,
    PageProjectDetail,
};
} // namespace

PanelWindow::PanelWindow(const LaunchRoute &route, const EngineLocator::Result &engine,
    AppModel *model, QWidget *parent)
    : DMainWindow(parent)
    , m_route(route)
    , m_engine(engine)
    , m_model(model)
{
    setWindowTitle(QStringLiteral("deepDolphin 面板")); // 窗口标题唯一出处
    setMinimumSize(kMinW, kMinH);
    resize(kDefaultW, kDefaultH);
    buildUi();
    wireModel();
    wirePages();
    buildMenu();
    bindShortcuts();
    refreshChrome();
}

void PanelWindow::buildUi()
{
    auto *central = new QWidget(this);
    auto *v = new QVBoxLayout(central);
    v->setContentsMargins(0, 0, 0, 0);
    v->setSpacing(0);

    // 1. 深链说明条（详情区顶部；独立于 lastError，互不依赖）
    m_routeNotice = new QLabel(central);
    m_routeNotice->setObjectName(QStringLiteral("routeNotice"));
    m_routeNotice->setStyleSheet(
        QStringLiteral("QLabel#routeNotice { background: palette(midlight); padding: 6px 12px; }"));
    m_routeNotice->setWordWrap(true);
    m_routeNotice->setVisible(false);
    v->addWidget(m_routeNotice);

    // 2. 常驻错误条（橙底 + 可关闭；不得自带刷新任务）
    auto *errorRow = new QWidget(central);
    auto *eh = new QHBoxLayout(errorRow);
    eh->setContentsMargins(12, 4, 12, 4);
    eh->setSpacing(8);
    m_errorBar = new QLabel(errorRow);
    m_errorBar->setStyleSheet(QStringLiteral(
        "QLabel { color: %1; background: %2; padding: 6px 12px; border-radius: 4px; }")
        .arg(DS::semColor(DS::SemColor::orange).name(),
            QColor(DS::semColor(DS::SemColor::orange)).lighter(180).name()));
    m_errorBar->setWordWrap(true);
    eh->addWidget(m_errorBar, 1);
    QAbstractButton *errClose = makeToolButton(QStringLiteral("window-close"),
        QStringLiteral("✕"), QStringLiteral("关闭提示"));
    errClose->setParent(errorRow);
    errClose->setFixedSize(28, 28);
    connect(errClose, &QAbstractButton::clicked, errorRow, &QWidget::hide);
    eh->addWidget(errClose);
    errorRow->hide();
    m_errorBar->setProperty("hostRow", QVariant::fromValue<QWidget *>(errorRow));
    v->addWidget(errorRow);

    // 3. QSplitter：侧栏（minWidth 210）+ 详情区（WorkBar + 页面栈）
    m_splitter = new QSplitter(Qt::Horizontal, central);
    m_sidebar = new SidebarNav(m_splitter);
    m_sidebar->setMinimumWidth(kSidebarMinWidth);
    auto *detailHost = new QWidget(m_splitter);
    auto *dv = new QVBoxLayout(detailHost);
    dv->setContentsMargins(0, 0, 0, 0);
    dv->setSpacing(0);
    m_workBar = new WorkBar(detailHost);
    dv->addWidget(m_workBar);
    m_stack = new QStackedWidget(detailHost);
    dv->addWidget(m_stack, 1);
    m_splitter->addWidget(m_sidebar);
    m_splitter->addWidget(detailHost);
    m_splitter->setStretchFactor(0, 0);
    m_splitter->setStretchFactor(1, 1);
    v->addWidget(m_splitter, 1);
    setCentralWidget(central);

    connect(m_sidebar, &SidebarNav::selectionChanged, this, [this](Selection sel) {
        m_model->go(sel);
    });
    connect(m_sidebar, &SidebarNav::addOrScanClicked, this, [this] { openScanDialog(); });
    connect(m_workBar->dualTrack(), &DualTrackButtons::shallowClicked, this,
        [this] { runUpdateForScope(false); });
    connect(m_workBar->dualTrack(), &DualTrackButtons::deepClicked, this,
        [this] { runUpdateForScope(true); });
    m_workBar->setGoHandler([this](Selection sel) { m_model->go(sel); });
}

void PanelWindow::openScanDialog(const QString &presetPath)
{
    auto *dlg = new ScanDialog(this);
    if (!presetPath.isEmpty())
        dlg->presetPath(presetPath);
    dlg->setAttribute(Qt::WA_DeleteOnClose);
    connect(dlg, &ScanDialog::submitted, this,
        [this](bool addMode, const QString &path, const QString &arg) {
            if (addMode)
                m_model->addProject(path, arg);
            else
                m_model->scan(path, arg.toInt());
        });
    dlg->show();
}

void PanelWindow::wirePages()
{
    m_setupPage = new SetupGuidePage(m_engine.problems.join(QStringLiteral("；")), m_stack);
    m_dashboard = new DashboardPage(m_stack);
    m_board = new BoardPage(m_stack);
    m_milestonesPage = new MilestonesPage(m_stack);
    m_detail = new ProjectDetailPage(m_stack);
    m_stack->addWidget(m_setupPage); // PageSetupGuide
    m_stack->addWidget(m_dashboard);
    m_stack->addWidget(m_board);
    m_stack->addWidget(m_milestonesPage);
    m_stack->addWidget(m_detail);

    m_dashboard->setModel(m_model);
    m_board->setModel(m_model);

    connect(m_dashboard, &DashboardPage::goProject, this,
        [this](const QString &name) { m_model->go(Selection::project(name)); bringToFront(); });
    connect(m_dashboard, &DashboardPage::briefRequested, this, [this] { showBrief(QString()); });
    connect(m_board, &BoardPage::goProject, this, [this](const QString &name) {
        m_model->go(Selection::project(name));
        bringToFront();
    });
    connect(m_board, &BoardPage::shallowFor, this,
        [this](const QString &name) { m_model->runUpdate(name, false); });
    connect(m_board, &BoardPage::briefFor, this, [this](const QString &name) { showBrief(name); });

    connect(m_milestonesPage, &MilestonesPage::goProject, this,
        [this](const QString &p) { m_model->go(Selection::project(p)); });
    connect(m_milestonesPage, &MilestonesPage::createRequested, this, [this](const QString &pref) {
        QStringList projects;
        for (const ProjectStatus &p : m_model->projects())
            projects << p.name;
        if (projects.isEmpty()) {
            showRouteNotice(QStringLiteral("还没有已注册项目——先「添加 / 扫描项目」注册项目群。"));
            return;
        }
        auto *dlg = new AddMilestoneDialog(this, projects, pref);
        dlg->setAttribute(Qt::WA_DeleteOnClose);
        connect(dlg, &AddMilestoneDialog::accepted, this, [this, dlg] {
            m_model->addMilestone(dlg->project(), dlg->name(), dlg->tag(), dlg->targetDate(),
                dlg->desc());
        });
        connect(m_model, &AppModel::milestoneActionFinished, dlg, [dlg](bool ok, const QString &msg) {
            if (!ok)
                dlg->setError(msg); // 失败红字贴表单下方（不关窗）
        });
        dlg->show();
    });
    connect(m_milestonesPage, &MilestonesPage::statusAction, this,
        [this](const QString &p, const QString &n, const QString &action) {
            m_model->setMilestoneStatus(p, n, action); // UI 词已转 CLI（open→reopen）
        });
    connect(m_milestonesPage, &MilestonesPage::removeRequested, this,
        [this](const QString &p, const QString &n) {
            const auto spec = DestructiveGuard::spec(DestructiveGuard::Action::removeMilestone, n);
            if (ConfirmDialog::confirm(this, spec))
                m_model->removeMilestone(p, n);
        });

    connect(m_detail, &ProjectDetailPage::gitOpRequested, this,
        [this](const QString &op, const QString &project, const QString &message) {
            m_model->gitOp(op, project, message);
        });
    connect(m_detail, &ProjectDetailPage::retryRequested, this,
        [this] { m_model->loadProject(m_detail->property("projectName").toString()); });
    connect(m_detail, &ProjectDetailPage::briefRequested, this,
        [this](const QString &p) { showBrief(p); });
    connect(m_detail, &ProjectDetailPage::updateMenuRequested, this, [this] {
        const UpdateScope scope = scopeFromSelection(m_model->selection());
        QMenu menu(this);
        // C5「浅/深更新 + AI 摘要」（mac UpdateActionMenu 的 AI 变体对位）
        menu.addAction(QStringLiteral("浅更新 + AI 摘要 %1").arg(scopeTitle(scope)), this,
            [this] { runUpdateDigestForScope(false); });
        menu.addAction(QStringLiteral("深更新 + AI 报告 %1").arg(scopeTitle(scope)), this,
            [this] { runUpdateDigestForScope(true); });
        menu.addSeparator();
        menu.addAction(QStringLiteral("浅更新 %1").arg(scopeTitle(scope)), this,
            [this] { runUpdateForScope(false); });
        menu.addAction(QStringLiteral("深更新 %1").arg(scopeTitle(scope)), this,
            [this] { runUpdateForScope(true); });
        menu.addSeparator();
        menu.addAction(QStringLiteral("刷新"), this, [this] { m_model->refreshAll(); });
        menu.addAction(QStringLiteral("停止更新"), this, [this] { m_model->stopUpdate(); });
        menu.exec(QCursor::pos());
    });
    // 详情页里程碑动作：达成/重开不确认（可逆）；删除/放弃确认染红
    connect(m_detail, &ProjectDetailPage::milestoneDone, this,
        [this](const QString &p, const QString &n) { m_model->setMilestoneStatus(p, n, "done"); });
    connect(m_detail, &ProjectDetailPage::milestoneReopen, this,
        [this](const QString &p, const QString &n) { m_model->setMilestoneStatus(p, n, "reopen"); });
    connect(m_detail, &ProjectDetailPage::milestoneDrop, this,
        [this](const QString &p, const QString &n) {
            const auto spec = DestructiveGuard::spec(DestructiveGuard::Action::dropMilestone, n);
            if (ConfirmDialog::confirm(this, spec))
                m_model->setMilestoneStatus(p, n, "drop");
        });
    connect(m_detail, &ProjectDetailPage::milestoneRemove, this,
        [this](const QString &p, const QString &n) {
            const auto spec = DestructiveGuard::spec(DestructiveGuard::Action::removeMilestone, n);
            if (ConfirmDialog::confirm(this, spec))
                m_model->removeMilestone(p, n);
        });

    connect(m_setupPage, &SetupGuidePage::redetectClicked, this, [this] {
        // 异步发现链（M0-2）：探活在 worker 跑，按钮不冻结；期间 SetupGuidePage 走忙态
        EngineLocator::Result pending;
        pending.pending = true;
        setEngineResult(pending);
        EngineLocator::locateAsync([this](const EngineLocator::Result &r) {
            setEngineResult(r);
            if (r.found) {
                showRouteNotice(QStringLiteral("引擎已找到：%1").arg(r.bin));
                m_model->refreshAll();
                navigate(m_model->selection());
            }
        });
    });
    // 重探测后引擎状态变化（含失败 → 成功回灌 bin）→ 侧栏/WorkBar/首页路由全部重算
    connect(m_model, &AppModel::engineFoundChanged, this, [this] { refreshChrome(); });
}

void PanelWindow::wireModel()
{
    connect(m_model, &AppModel::projectsChanged, this, &PanelWindow::refreshChrome);
    connect(m_model, &AppModel::dashboardChanged, this, &PanelWindow::refreshChrome);
    connect(m_model, &AppModel::milestonesChanged, this, [this] {
        // 里程碑页 + 详情页里程碑卡（按项目收窄明细）
        m_milestonesPage->setEnvelope(m_model->milestones(), m_model->milestonesState());
        m_milestonesPage->setProjectNames([this] {
            QStringList names;
            for (const ProjectStatus &p : m_model->projects())
                names << p.name;
            return names;
        }());
        updateDetailSelection();
    });
    connect(m_model, &AppModel::selectionChanged, this, [this](Selection sel) {
        m_sidebar->select(sel, false); // 同步侧栏高亮（不再回发信号，防循环）
        navigate(sel);
        // 进入详情 = loadProject + loadDocs（go 已带 loadProject；这里补 docs）
        if (sel.kind == Selection::Kind::project)
            m_model->loadDocs(sel.projectName);
    });
    connect(m_model, &AppModel::busyChanged, this, &PanelWindow::refreshChrome);
    connect(m_model, &AppModel::lastErrorChanged, this, [this](const QString &msg) {
        if (auto *row = m_errorBar->property("hostRow").value<QWidget *>()) {
            m_errorBar->setText(msg);
            row->setVisible(!msg.isEmpty());
        }
        refreshChrome();
    });
    connect(m_model, &AppModel::gitOutputReady, this,
        [this](const QString &name, const GitOpResponse &resp) { m_detail->setGitOutput(name, resp); });
    connect(m_model, &AppModel::projectChanged, this, [this](const QString &name) {
        updateDetailSelection();
        Q_UNUSED(name);
        refreshChrome();
    });
    connect(m_model, &AppModel::docsChanged, this, [this](const QString &name) {
        if (m_model->selection().kind == Selection::Kind::project
            && m_model->selection().projectName == name) {
            m_detail->setDocs(name, m_model->docsFor(name), m_model->docsState(name));
        }
    });
    connect(m_model, &AppModel::bulkReportReady, this, [this](const AgentBulkReport &report) {
        // 全量更新结果面板：无按钮、无重新生成（逐仓库结果是事实陈述）
        auto *dlg = new AiResultDialog(this,
            report.deep ? QStringLiteral("深更新 · 全量") : QStringLiteral("浅更新 · 全量"));
        dlg->setAttribute(Qt::WA_DeleteOnClose);
        dlg->setMarkdown(report.toMarkdown());
        dlg->setRegenerate({}); // **nil = 无重新生成**
        dlg->show();
    });
    connect(m_model, &AppModel::milestoneActionFinished, this, [this](bool ok, const QString &msg) {
        Q_UNUSED(ok);
        if (!msg.isEmpty())
            showRouteNotice(msg);
    });
    // 添加/扫描结果接回主窗口（ScanDialog 提交后窗已关，结果只从这里披露）：
    // 成功文案 + ScanCoverage 覆盖度披露、失败原因——不再发进真空
    connect(m_model, &AppModel::addFinished, this, [this](bool ok, const QString &msg) {
        showRouteNotice(ok ? msg : QStringLiteral("添加失败：%1").arg(msg));
    });
    connect(m_model, &AppModel::scanFinished, this,
        [this](bool ok, const QString &msg, const QString &coverageNote) {
            if (!ok) {
                showRouteNotice(QStringLiteral("扫描失败：%1").arg(msg));
                return;
            }
            showRouteNotice(coverageNote.isEmpty() ? msg
                                                   : QStringLiteral("%1\n%2").arg(msg, coverageNote));
        });
    // 「更新 + AI 摘要」收尾：busy 结果窗一次给出正文/错误（重试按钮在窗上，重跑同一动作）
    connect(m_model, &AppModel::updateDigestReady, this,
        [this](bool ok, bool deep, const QString &project, const QString &text) {
            if (!m_digestDialog)
                return; // 窗已关（用户不看了）：结果只走通知层，不复活旧窗
            Q_UNUSED(deep);
            Q_UNUSED(project);
            if (ok)
                m_digestDialog->setMarkdown(text);
            else
                m_digestDialog->setState(QStringLiteral("error"),
                    text.isEmpty() ? QStringLiteral("更新未完成，AI 报告取消（失败原因见错误条）。")
                                   : text);
        });
    connect(m_model, &AppModel::refreshCycleFinished, this, [this](bool ok) {
        Q_UNUSED(ok);
        m_loadedOnce = m_model->hasLoadedProjectsOnce();
        maybeApplyPendingRoute(); // pendingRoute 补判（加载完的那一次）
        refreshChrome();
    });
}

// ── 引擎状态变更（启动异步发现收尾 / 重探测）：bin 回灌给 CLI + UI 全量重算 ──
// pending（发现链在跑）时保留原文案并让 SetupGuidePage 走忙态；找到了才让「引擎已找到」
// 由调用方（重探测路径）在 notice 里说——启动首发现不打扰用户。
void PanelWindow::setEngineResult(const EngineLocator::Result &engine)
{
    m_engine = engine;
    m_model->setEngineResult(engine);
    m_setupPage->setBusy(engine.pending);
    if (!engine.pending)
        m_setupPage->setProblem(engine.problems.join(QStringLiteral("；")));
    refreshChrome();
    if (engine.found)
        navigate(m_model->selection());
    emit traySnapshotChanged(); // 托盘 tooltip / 速览数据里的 engineFound 要跟着变
}

void PanelWindow::refreshChrome()
{
    // 侧栏：项目行（shown/total）+ 徽标计数
    QVector<ProjectStatus> projects;
    for (const ProjectStatus &p : m_model->projects())
        projects.append(p);
    const int total = static_cast<int>(projects.size());
    const int failed = m_model->summary().has_value() ? m_model->summary()->failedProjects : 0;
    m_sidebar->setProjects(projects, total, total);
    m_sidebar->setAttentionCount(Derived::attentionCount(m_model->projects()));
    // 里程碑行 = counts.open + done（读不出 → nullopt 不显示）
    if (m_model->dashboard().has_value())
        m_sidebar->setMilestoneCount(
            Derived::milestoneBadge(m_model->dashboard()->milestones.counts));
    else
        m_sidebar->setMilestoneCount(std::nullopt);

    // 状态条四文案：正在检测引擎…/正在采集…/空闲/引擎连接失败/尚未刷新
    if (m_model->enginePending()) {
        m_sidebar->setStatusStrip(QStringLiteral("正在检测引擎…"), Liveness::unknown);
    } else if (!m_model->engineFound()) {
        m_sidebar->setStatusStrip(QStringLiteral("引擎连接失败"), Liveness::unreadable);
    } else if (m_model->isLoading()) {
        m_sidebar->setStatusStrip(QStringLiteral("正在采集…"), Liveness::unknown);
    } else if (m_model->lastRefreshedMs() > 0) {
        const QString t = QLocale().toString(
            QDateTime::fromMSecsSinceEpoch(m_model->lastRefreshedMs()), QStringLiteral("HH:mm"));
        m_sidebar->setStatusStrip(QStringLiteral("空闲 · 上次刷新 %1").arg(t), Liveness::recent);
    } else {
        m_sidebar->setStatusStrip(QStringLiteral("尚未刷新"), Liveness::unknown);
    }
    Q_UNUSED(failed);

    // WorkBar：只在「引擎就绪且有项目」时出现
    m_workBar->setVisible(m_model->engineFound() && !m_model->projects().empty());
    m_workBar->refreshFrom(m_model);

    // 引擎未找到 → 安装指引首屏
    if (!m_model->engineFound()) {
        m_stack->setCurrentIndex(PageSetupGuide);
        return;
    }
    navigate(m_model->selection());
}

void PanelWindow::navigate(Selection sel)
{
    m_selection = sel;
    if (!m_model->engineFound()) {
        m_stack->setCurrentIndex(PageSetupGuide); // 引擎未找到：一切路由先落安装指引
        return;
    }
    switch (sel.kind) {
    case Selection::Kind::board:
        m_stack->setCurrentIndex(PageBoard);
        break;
    case Selection::Kind::milestones:
        m_stack->setCurrentIndex(PageMilestones);
        break;
    case Selection::Kind::project: {
        m_detail->setProperty("projectName", sel.projectName);
        updateDetailSelection();
        m_stack->setCurrentIndex(PageProjectDetail);
        break;
    }
    case Selection::Kind::dashboard:
        m_stack->setCurrentIndex(PageDashboard);
        break;
    }
}

void PanelWindow::updateDetailSelection()
{
    if (m_model->selection().kind != Selection::Kind::project)
        return;
    const QString name = m_model->selection().projectName;
    m_detail->setProperty("projectName", name);
    m_detail->setProject(name, m_model->project(name), m_model->projectLoadError(name));
    m_detail->setDocs(name, m_model->docsFor(name), m_model->docsState(name));
    m_detail->setBusy(m_model->busyProjects().contains(name));
    // 详情页里程碑卡（该项目范围的明细）
    QVector<Milestone> mine;
    if (m_model->milestones().has_value()) {
        for (const Milestone &m : m_model->milestones()->milestones) {
            if (m.projectName == name)
                mine.append(m);
        }
    }
    m_detail->setMilestones(mine);
}

void PanelWindow::buildMenu()
{
    // 操作菜单挂 DTitlebar（DTK 风格）
    QMenu *panelMenu = new QMenu(this);
    connect(panelMenu->addAction(QStringLiteral("浅更新 %1")
                                 .arg(scopeTitle(scopeFromSelection(m_model->selection())))),
        &QAction::triggered, this, [this] { runUpdateForScope(false); });
    connect(panelMenu->addAction(QStringLiteral("深更新 %1")
                                 .arg(scopeTitle(scopeFromSelection(m_model->selection())))),
        &QAction::triggered, this, [this] { runUpdateForScope(true); });
    panelMenu->addSeparator();
    connect(panelMenu->addAction(QStringLiteral("刷新")), &QAction::triggered, this,
        [this] { m_model->refreshAll(); });
    connect(panelMenu->addAction(QStringLiteral("停止更新")), &QAction::triggered, this,
        [this] { m_model->stopUpdate(); });
    panelMenu->addSeparator();
    connect(panelMenu->addAction(QStringLiteral("添加 / 扫描项目")), &QAction::triggered, this,
        [this] { openScanDialog(); });
    panelMenu->addAction(QStringLiteral("设置"), this, &PanelWindow::showSettings);

    if (DTitlebar *tb = titlebar()) {
        tb->setMenu(panelMenu);
        // 工具栏**只挂一处**：刷新 / AI 助手 / AI 设置 / 搜索。
        // 【偏差记录】双轨按钮按 PLAN §2.6 同时列在「工具栏」与 WorkBar 两处；
        // 为守「全量更新入口唯一」红线（§3.3-1），只保留 WorkBar 一处（与范围选择器同排）。
        // 标准动作 = DIconButton（图标走 freedesktop 主题名；尺寸 DStyle::PM_IconButtonIconSize
        // 由 DTK 样式接管）。图标名解析不到（无图标主题的环境）退回文字平钮——空按钮
        // 比非原生按钮更糟（R2 诚实降级）。「AI 助手」无 freedesktop 标准图标名，恒文字钮。
        QAbstractButton *refresh = makeToolButton(QStringLiteral("view-refresh"),
            QStringLiteral("刷新"), QStringLiteral("刷新（Ctrl+R）"));
        connect(refresh, &QAbstractButton::clicked, this, [this] { m_model->refreshAll(); });
        auto *agentBtn = new DPushButton(this);
        agentBtn->setText(QStringLiteral("AI 助手"));
        agentBtn->setFlat(true);
        agentBtn->setToolTip(QStringLiteral("AI 助手对话"));
        connect(agentBtn, &QPushButton::clicked, this, &PanelWindow::showAgentDialog);
        QAbstractButton *settingsBtn = makeToolButton(QStringLiteral("preferences-system"),
            QStringLiteral("设置"), QStringLiteral("设置（Ctrl+,）"));
        connect(settingsBtn, &QAbstractButton::clicked, this, &PanelWindow::showSettings);
        QAbstractButton *searchBtn = makeToolButton(QStringLiteral("system-search"),
            QStringLiteral("搜索"), QStringLiteral("搜索（Ctrl+F，焦点送进侧栏搜索框）"));
        connect(searchBtn, &QAbstractButton::clicked, this, [this] { m_sidebar->focusSearch(); });
        tb->addWidget(refresh);
        tb->addWidget(agentBtn);
        tb->addWidget(settingsBtn);
        tb->addWidget(searchBtn);
    }
}

void PanelWindow::bindShortcuts()
{
    // ShortcutMap 是唯一声明处；菜单显示串按 Qt 自动生成（平台差异已记录）
    const auto map = ShortcutMap::shortcutMap(ShortcutMap::viewOrder().size());
    for (const ShortcutSpec &spec : map) {
        auto *sc = new QShortcut(spec.seq, this);
        if (spec.actionId == QLatin1String("refresh")) {
            connect(sc, &QShortcut::activated, this, [this] { m_model->refreshAll(); });
        } else if (spec.actionId == QLatin1String("shallowUpdate")) {
            connect(sc, &QShortcut::activated, this, [this] { runUpdateForScope(false); });
        } else if (spec.actionId == QLatin1String("deepUpdate")) {
            connect(sc, &QShortcut::activated, this, [this] { runUpdateForScope(true); });
        } else if (spec.actionId == QLatin1String("stopUpdate")) {
            connect(sc, &QShortcut::activated, this, [this] { m_model->stopUpdate(); });
        } else if (spec.actionId == QLatin1String("focusSearch")) {
            connect(sc, &QShortcut::activated, this, [this] { m_sidebar->focusSearch(); });
        } else if (spec.actionId == QLatin1String("settings")) {
            connect(sc, &QShortcut::activated, this, &PanelWindow::showSettings);
        } else if (spec.actionId == QLatin1String("closePanel")) {
            connect(sc, &QShortcut::activated, this, &QWidget::close);
        } else if (spec.actionId.startsWith(QLatin1String("view:"))) {
            const QString target = spec.actionId.mid(5);
            connect(sc, &QShortcut::activated, this, [this, target] {
                if (target == QLatin1String("dashboard"))
                    m_model->go(Selection::dashboard());
                else if (target == QLatin1String("board"))
                    m_model->go(Selection::board());
                else if (target == QLatin1String("milestones"))
                    m_model->go(Selection::milestones());
                else if (target == QLatin1String("currentProject")) {
                    // ⌘4 = 打开当前选中项目（第一个）：没有项目不动 selection；已在详情页不动
                    if (m_model->projects().empty())
                        return;
                    if (m_model->selection().kind == Selection::Kind::project)
                        return;
                    m_model->go(Selection::project(m_model->projects().front().name));
                }
            });
        } else {
            sc->deleteLater();
        }
    }
}

void PanelWindow::runUpdateForScope(bool deep)
{
    // 范围由 selection 推导（没有第二真相源）：project → 单项目；其余 → 全局（确认框）
    const UpdateScope scope = scopeFromSelection(m_model->selection());
    if (scope.kind == UpdateScopeKind::project) {
        m_model->runUpdate(scope.name, deep);
        return;
    }
    confirmBulkUpdate(deep);
}

void PanelWindow::runUpdateDigestForScope(bool deep)
{
    // C5「更新 + AI 摘要」（mac UpdateActionMenu 的 updateWithAISummary 对位）：
    // 先真更新（AppModel::runUpdateDigest 走同一把 busy 锁/收尾），成功后 worker 生成
    // AiDigests::updateDigest，结果经 updateDigestReady 回填本窗（busy → 正文/错误）。
    const UpdateScope scope = scopeFromSelection(m_model->selection());
    if (scope.kind != UpdateScopeKind::project || scope.name.isEmpty())
        return; // AI 变体只对项目档（全局批量的 AI 简报在结果面板/定时通知里）
    // 与 runUpdateDigest 的入口锁同判：开窗前先拦，否则模型直接 return，busy 窗悬死
    if (m_model->busyAll() || m_model->busyProjects().contains(scope.name)) {
        showRouteNotice(QStringLiteral("该项目已有更新在进行，请等它结束再生成 AI 报告。"));
        return;
    }
    auto *dlg = new AiResultDialog(this,
        QStringLiteral("%1AI 报告 · %2")
            .arg(deep ? QStringLiteral("深度更新") : QStringLiteral("浅更新"), scope.name));
    dlg->setAttribute(Qt::WA_DeleteOnClose);
    dlg->setState(QStringLiteral("busy"), QStringLiteral("正在更新，随后生成 AI 报告…"));
    dlg->show();
    // 重试重跑同一个动作（错误态的「重新生成」必须真传——mac UpdateActionMenu 教训）
    QPointer<AiResultDialog> dlgGuard(dlg);
    dlg->setRegenerate([this, dlgGuard, deep] {
        if (!dlgGuard)
            return;
        dlgGuard->close(); // WA_DeleteOnClose：旧窗退场，runUpdateDigestForScope 开新窗
        runUpdateDigestForScope(deep);
    });
    m_digestDialog = dlg;
    m_model->runUpdateDigest(scope.name, deep);
}

void PanelWindow::confirmBulkUpdate(bool deep)
{
    // 全量更新：入口唯一（双轨按钮全局档）；**必须弹确认框**；确认按钮不染红（有备份可回滚）
    const int count = static_cast<int>(m_model->projects().size());
    DestructiveGuard::Spec spec;
    spec.title = deep ? QStringLiteral("全部深更新？") : QStringLiteral("全部浅更新？");
    spec.body = DestructiveGuard::bulkUpdateMessage(count, deep);
    spec.confirmLabel = QStringLiteral("全部更新");
    spec.destructive = false;
    if (ConfirmDialog::confirm(this, spec))
        m_model->updateAll(deep, false, {});
}

void PanelWindow::showAgentDialog()
{
    // 范围跟随 selection（mac AgentView：选中项目=该项目否则 group）。
    // 成员复用（非 deleteOnClose）：worker 回调经 QPointer 保护，关窗即停任务。
    const Selection sel = m_model->selection();
    AgentCore::Target target;
    if (sel.kind == Selection::Kind::project && !sel.projectName.isEmpty()) {
        target.kind = AgentCore::Target::Kind::project;
        target.projectName = sel.projectName;
    }
    if (!m_agent) {
        m_agent = new AgentDialog(this, m_model->cli()->engineBin(), target);
        connect(m_model, &AppModel::selectionChanged, this, [this](Selection s) {
            if (!m_agent || m_agent->isVisible())
                return; // 对话开着不换范围（历史属于打开时的范围）
            AgentCore::Target t;
            if (s.kind == Selection::Kind::project && !s.projectName.isEmpty()) {
                t.kind = AgentCore::Target::Kind::project;
                t.projectName = s.projectName;
            }
            m_agent->retarget(t);
        });
    } else {
        m_agent->retarget(target);
    }
    m_agent->show();
    m_agent->raise();
    m_agent->activateWindow();
}

void PanelWindow::showBrief(const QString &project, const QString &titleOverride)
{
    // 「项目说明/项目群说明」（C5/C6 的 AI 简报入口）：
    // · 未配置（系统级 AI 缺席且无显式渠道）→ 「AI 未配置：…」原文透出（CHARTER §3）；
    // · 已配置 → worker 线程跑 AiDigests（agent 工具循环），GUI 不阻塞；
    // · AI 失败不炸面板：错误进弹窗的 error 态，重试按钮真传。
    const bool isGroup = project.isEmpty();
    QString title;
    if (!titleOverride.isEmpty() && !isGroup)
        title = titleOverride;
    else if (isGroup)
        title = QStringLiteral("项目群说明");
    else
        title = QStringLiteral("项目说明 · %1").arg(project);
    auto *dlg = new AiResultDialog(this, title);
    dlg->setAttribute(Qt::WA_DeleteOnClose);
    // 先进 busy 态：key 读取（同步 libsecret）与「已配置」判定都在 worker 里做
    //（PLAN §2.5——GLib 同步 API 不进 GUI 线程）；未配置的诚实降级文案经 Outcome 回来
    dlg->setState(QStringLiteral("busy"), QStringLiteral("AI 正在收集引擎事实并生成…"));
    dlg->show();

    // worker：AgentCore（引擎 CLI 同步 + HTTP 同步）全程在 QThreadPool；
    // 结果经 invokeMethod 回 GUI（QPointer 双守卫：窗口/面板任一销毁即丢弃）。
    QPointer<PanelWindow> guard(this);
    QPointer<AiResultDialog> dlgGuard(dlg);
    const QString engineBin = m_model->cli()->engineBin();
    // Settings 身份/明文回退只在 GUI 线程读好按值带进 worker（M0-4 不跨线程碰 Settings）
    AIConfig identity = AIConfig::load();
    const QString fallbackKey = Settings::instance().aiApiKeyPlaintext();
    auto runDigest = [engineBin, project, isGroup](const AIConfig &cfg) -> AiDigests::Outcome {
        if (isGroup)
            return AiDigests::groupBrief(engineBin, cfg);
        return AiDigests::projectBrief(engineBin, cfg, project);
    };
    QThreadPool::globalInstance()->start([this, guard, dlgGuard, runDigest, project, identity,
                                         fallbackKey] {
        AIConfig cfg = identity;
        {
            SecretStore store; // 同步 libsecret 只在 worker（PLAN §2.5）
            cfg.apiKey = AIConfig::loadKey(&store, fallbackKey);
        }
        AiDigests::Outcome out;
        QString why;
        const std::unique_ptr<AIEngine> engine = AIEngineFactory::create(cfg);
        if (!engine->isConfigured(&why)) {
            out.error = QStringLiteral(
                "AI 未配置：%1\n\n请在「设置 → AI」里选择 OpenAI 兼容或 Anthropic "
                "渠道并填写 API Key。更新动作不受影响，只是没有 AI 摘要。")
                            .arg(why);
        } else {
            out = runDigest(cfg);
        }
        if (!guard || !dlgGuard)
            return;
        QMetaObject::invokeMethod(
            guard,
            [this, guard, dlgGuard, out, project] {
                if (!guard || !dlgGuard)
                    return;
                if (out.ok)
                    dlgGuard->setMarkdown(out.text);
                else
                    dlgGuard->setState(QStringLiteral("error"), out.error);
                // 重新生成真传（nil 会静默无反应）；重跑同一个 brief
                dlgGuard->setRegenerate([this, guard, project] {
                    if (guard)
                        showBrief(project);
                });
            },
            Qt::QueuedConnection);
    });
}

void PanelWindow::showSettings()
{
    if (!m_settings) {
        m_settings = new AiSettingsDialog(this);
        connect(m_settings->automationPane(), &AutomationPane::autoHoursChanged, m_model,
            &AppModel::restartAutoTimer); // 改完立即生效（不经过保存按钮）
    }
    m_settings->show();
    m_settings->raise();
    m_settings->activateWindow();
}

void PanelWindow::showRouteNotice(const QString &text)
{
    m_routeNotice->setText(text);
    m_routeNotice->setVisible(true);
    QTimer::singleShot(8000, this, [this] { m_routeNotice->setVisible(false); });
}

void PanelWindow::applyRoute(const LaunchRoute &route)
{
    m_route = route;
    m_routeConsumed = false; // 新深链必须重新落地一次（哪怕上一条已消费）
    if (route.openSettings)
        showSettings();
    if (route.openScan)
        openScanDialog();
    if (route.path.has_value())
        openScanDialog(*route.path); // 桌面项「在面板中打开目录」：预填后弹出
    maybeApplyPendingRoute();
    bringToFront();
}

void PanelWindow::maybeApplyPendingRoute()
{
    // 路由闩：深链/默认视图只落地一次。没有闩时，每次 refreshCycleFinished（含 300s
    // 轻刷新）都会对空路由拿到 {apply, dashboard} 并 navigate——用户当前页面被周期性
    // 打回仪表盘（mac pendingRoute 只在「加载完补判一次」，同语义）。
    if (m_routeConsumed)
        return;
    std::vector<ProjectStatus> projects(m_model->projects().begin(), m_model->projects().end());
    RouteTarget target = routeTarget(m_route, projects, m_loadedOnce);
    if (target.verdict == RouteVerdict::pending)
        return; // 「不知道」：还不能判，下一轮收尾再来补判（不消费）
    m_routeConsumed = true; // apply/missing 都算判过：missing 的说明条也不该反复弹
    if (target.verdict == RouteVerdict::apply) {
        // 走 model（setSelection + 信号）：侧栏高亮与页面栈同源，不再各改各的
        if (!target.project.isEmpty())
            m_model->go(Selection::project(target.project));
        else
            m_model->go(Selection { target.section == QLatin1String("board")
                        ? Selection::Kind::board
                        : (target.section == QLatin1String("milestones")
                                  ? Selection::Kind::milestones
                                  : Selection::Kind::dashboard),
                QString() });
    }
    if (!target.notice.isEmpty())
        showRouteNotice(target.notice);
}

void PanelWindow::attachTray(TrayController *tray)
{
    connect(tray, &TrayController::openPanelRequested, this, &PanelWindow::bringToFront);
    // 「全部浅更新」：先 bringToFront 再确认框（窗口没开就没人呈现确认框）
    connect(tray, &TrayController::updateAllRequested, this, [this] {
        bringToFront();
        confirmBulkUpdate(false);
    });
    connect(tray, &TrayController::openProjectRequested, this, [this](const QString &name) {
        m_model->go(Selection::project(name));
        bringToFront();
    });
    connect(tray, &TrayController::refreshLightRequested, m_model, &AppModel::refreshLight);
    emit traySnapshotChanged();
}

TraySnapshot PanelWindow::traySnapshot() const
{
    TraySnapshot snap;
    snap.engineFound = m_model->engineFound();
    snap.engineProblem = m_model->engineProblem().isEmpty()
        ? EngineLocator::installHint()
        : m_model->engineProblem();
    snap.busy = m_model->isLoading();

    // summaryLine（KpiSet 唯一口径；无仪表盘时给项目数摘要）
    if (m_model->dashboard().has_value()) {
        const KpiSet k = kpis(*m_model->dashboard(), m_model->projects());
        snap.summaryLine = summaryLine(k);
    } else {
        snap.summaryLine = QStringLiteral("共 %1 个项目").arg(m_model->projects().size());
    }

    // MenuProjectRow：状态点+名+●N 橙+busy；副标题三级回退；pending 蓝数字+迷你条
    for (const ProjectStatus &p : m_model->projects()) {
        TraySnapshot::Row row;
        row.name = p.name;
        row.dot = Derived::livenessColor(Derived::liveness(p));
        row.dirty = p.userDirtyCount;
        row.pending = 0;
        if (!p.isUnreadable()) {
            for (const BranchStatus &b : p.branches)
                row.pending += qMax(0, b.pendingCommits);
        }
        row.unreadable = p.isUnreadable();
        // 副标题三级回退：pulseLine → 「<headAgo> · <statusLabel>」 → lastCommitAgo /「非 git 项目」
        if (p.isUnreadable()) {
            row.subtitle = p.error.value_or(QStringLiteral("读不出来"));
        } else if (!Derived::pulseLine(p).isEmpty()) {
            row.subtitle = Derived::pulseLine(p);
        } else if (const BranchStatus *pb = Derived::primaryBranch(p);
                   pb && (!pb->headAgo.isEmpty() || !pb->statusLabel.isEmpty())) {
            row.subtitle = QStringLiteral("%1 · %2").arg(
                pb->headAgo.isEmpty() ? QStringLiteral("—") : pb->headAgo,
                pb->statusLabel);
        } else if (!p.lastCommitAgo.isEmpty()) {
            row.subtitle = p.lastCommitAgo;
        } else if (!p.isGit()) {
            row.subtitle = QStringLiteral("非 git 项目");
        } else {
            row.subtitle = QStringLiteral("—");
        }
        row.rowBusy = m_model->busyProjects().contains(p.name);
        snap.rows.append(row);
    }
    snap.totalProjects = static_cast<int>(m_model->projects().size());
    return snap;
}

void PanelWindow::bringToFront()
{
    show();
    raise();
    activateWindow();
}

void PanelWindow::closeEvent(QCloseEvent *event)
{
    // 托盘常驻：关面板只隐藏（退出走托盘菜单/退出动作）
    hide();
    event->ignore();
}
