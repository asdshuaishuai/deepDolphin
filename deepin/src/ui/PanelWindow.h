// PanelWindow.h — 主窗口（mac PanelView 对位，PLAN §4.1）。
//
// DMainWindow + QSplitter（侧栏 minWidth 210 + QStackedWidget 页面栈）；
// min 940×620、默认 1100×720；详情区自上而下：routeNotice / lastError / WorkBar / 页面栈。
// 工具栏**只挂一处**（DTitlebar）：双轨 → 刷新 → 更多 → AI 助手 → AI 设置 → 搜索。
#pragma once
#include "../app/AppModel.h"
#include "../app/EngineCli.h"
#include "../app/EngineLocator.h"
#include "../logic/Route.h"
#include "../logic/Scope.h"
#include "../tray/TrayController.h"
#include <DMainWindow>
#include <QLabel>
#include <QPointer>
#include <optional>

class QStackedWidget;
class QSplitter;
class SidebarNav;
class WorkBar;
class DashboardPage;
class BoardPage;
class MilestonesPage;
class ProjectDetailPage;
class SetupGuidePage;
class AiResultDialog;
class AiSettingsDialog;
class AgentDialog;
class TrayController;

DWIDGET_USE_NAMESPACE

class PanelWindow : public DMainWindow {
    Q_OBJECT
public:
    PanelWindow(const LaunchRoute &route, const EngineLocator::Result &engine, AppModel *model,
        QWidget *parent = nullptr);

    void bringToFront();               // 唯一叫醒入口（托盘/通知/二实例共用）
    void setEngineResult(const EngineLocator::Result &engine); // 重新检测引擎 / 启动异步发现的唯一入口
    void navigate(Selection sel);      // 侧栏/路由 → 页面栈
    void showRouteNotice(const QString &text); // 深链说明条（详情区顶部，独立于 lastError）
    void applyRoute(const LaunchRoute &route); // 二实例深链转发
    void attachTray(TrayController *tray);     // 托盘信号接线（main 持有托盘）

signals:
    void traySnapshotChanged(); // main 借此刷托盘（fillSnapshot 由本类提供）

public:
    TraySnapshot traySnapshot() const; // 托盘速览数据（AppModel 派生）

protected:
    void closeEvent(QCloseEvent *event) override;

private:
    void buildUi();
    void buildMenu();
    void bindShortcuts();
    void wireModel();
    void wirePages();
    void openScanDialog(const QString &presetPath = QString());
    void refreshChrome();   // 侧栏计数/状态条/WorkBar/双轨/错误条
    void maybeApplyPendingRoute();
    void showSettings();
    void showAgentDialog();  // AI 助手（范围跟随 selection；成员复用防 worker 悬垂）
    void showBrief(const QString &project, const QString &titleOverride = QString()); // AI 说明（worker 生成；未配置 → 诚实降级）
    void confirmBulkUpdate(bool deep);
    void runUpdateForScope(bool deep);
    void runUpdateDigestForScope(bool deep); // C5「更新 + AI 摘要」菜单变体（mac UpdateActionMenu 对位）
    void updateDetailSelection();

    LaunchRoute m_route;
    EngineLocator::Result m_engine;
    AppModel *m_model = nullptr;

    SidebarNav *m_sidebar = nullptr;
    QStackedWidget *m_stack = nullptr;
    QSplitter *m_splitter = nullptr;
    QLabel *m_routeNotice = nullptr;
    QLabel *m_errorBar = nullptr;
    WorkBar *m_workBar = nullptr;

    SetupGuidePage *m_setupPage = nullptr;
    DashboardPage *m_dashboard = nullptr;
    BoardPage *m_board = nullptr;
    MilestonesPage *m_milestonesPage = nullptr;
    ProjectDetailPage *m_detail = nullptr;
    AiSettingsDialog *m_settings = nullptr;
    AgentDialog *m_agent = nullptr; // AI 助手（成员复用：worker 回调不悬垂）
    QPointer<AiResultDialog> m_digestDialog; // 「更新 + AI 摘要」结果窗（busy → 正文/错误）

    Selection m_selection;
    bool m_loadedOnce = false;  // AppModel::hasLoadedProjectsOnce 的镜像（补判 pendingRoute）
    bool m_routeConsumed = false; // 路由闩：深链/默认视图只落地一次（300s 轻刷新不得反复 navigate）
};
