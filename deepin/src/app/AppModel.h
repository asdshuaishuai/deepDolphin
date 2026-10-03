// AppModel.h — 进程级数据编排（mac Model.swift 对位，PLAN §2.3）。
//
// 【纪律】
// · 每数据源一份自己的 LoadState（dashboardState/milestonesState/docsStates/
//   projectLoadErrors），**不共用 lastError**（SPEC §3.5）；
// · refreshAll 顺序 status →（失败短路）→ dashboard → milestones；RefreshGate 合并闸门
//   （撞上不丢弃、排队补跑一次不叠加）；
// · 定时器三件套：轻刷新 300s（仅 status）、定时更新（update.autoHours）+ 首轮 600s 一次性
//   （**必须存成员**，否则每次开面板多挂一个幽灵）；
// · busyAll 单锁覆盖所有批量入口；先 refreshAll 再冻结名单（全部条目含采集失败）；
// · UI 只消费 signals；口径全在 logic 层。
#pragma once
#include "../logic/DashFilter.h"
#include "../logic/Liveness.h"
#include "../logic/Route.h"
#include "../logic/Scope.h"
#include "../models/DashboardData.h"
#include "../models/LoadState.h"
#include "../models/DocsEnvelope.h"
#include "../models/GitOpResponse.h"
#include "../models/Milestone.h"
#include "../models/ProjectStatus.h"
#include "../models/StatusEnvelope.h"
#include "../models/UpdateResult.h"
#include "EngineCli.h"
#include "EngineLocator.h"
#include <QElapsedTimer>
#include <QMap>
#include <QMetaObject>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QTimer>
#include <QVector>
#include <functional>
#include <optional>
#include <vector>

class Notifier;
class QProcess;

// 全量更新结果面板数据（mac AgentBulkUpdate.Report 对位；逐仓库明细永远生成，不含 AI 成分）。
struct AgentBulkRow {
    QString name;
    bool ok = false;
    QString detail; // ok=UpdateOutcome.summary；!ok=引擎/工具给的原因（不编造）
};
struct AgentBulkReport {
    bool deep = false;
    int attempted = 0;
    int succeeded = 0;
    int failed = 0;
    QVector<AgentBulkRow> rows;    // 项目名 → 一行说明
    QString aiNote;                // **永远有值**（未配置 AI → 降级说明原文）

    QString toMarkdown() const;
    // AI 简报问句用的逐仓库表（mac AgentBulkUpdate.digest 原文口径：完成/失败（原因））
    QString outcomeTable() const;
};

class AppModel : public QObject {
    Q_OBJECT
public:
    explicit AppModel(const EngineLocator::Result &engine, EngineCli *cli, QObject *parent = nullptr);

    void start();
    void stop(); // 收掉 3 个 timer（引擎子进程由 EngineCli/ProcessRegistry 收口）

    // ── 只读状态 ──
    bool engineFound() const { return m_engineFound; }
    bool enginePending() const { return m_enginePending; } // 发现链在跑：UI 走忙态，别说"未找到"
    QString engineProblem() const { return m_engineProblem; }
    const std::vector<ProjectStatus> &projects() const { return m_projects; }
    const std::optional<ProjectStatus> project(const QString &name) const;
    const std::optional<EngineSummary> &summary() const { return m_summary; }
    const std::optional<DashboardData> &dashboard() const { return m_dashboard; }
    const LoadStateBox &dashboardState() const { return m_dashboardState; }
    const std::optional<MilestonesEnvelope> &milestones() const { return m_milestones; }
    const LoadStateBox &milestonesState() const { return m_milestonesState; }
    LoadStateBox docsState(const QString &name) const { return m_docsStates.value(name); }
    const std::optional<DocsEnvelope> docsFor(const QString &name) const
    {
        return m_docs.contains(name) ? std::optional<DocsEnvelope>(m_docs.value(name))
                                     : std::nullopt;
    }
    QString projectLoadError(const QString &name) const { return m_projectLoadErrors.value(name); }
    QString lastError() const { return m_lastError; }
    bool hasLoadedProjectsOnce() const { return m_hasLoadedProjectsOnce; }
    qint64 lastRefreshedMs() const { return m_lastRefreshedMs; }
    bool busyAll() const { return m_busyAll; }
    const QSet<QString> &busyProjects() const { return m_busyProjects; }
    const Selection &selection() const { return m_selection; }
    const DashFilter &dashFilter() const { return m_dashFilter; }
    bool isLoading() const { return m_refreshing || m_busyAll || !m_busyProjects.isEmpty(); }
    // 浅更新待记录徽章（实时值按范围取——引擎已修恒 0 缺陷，客户端只消费）
    int pendingForScope(const UpdateScope &scope) const;

    EngineCli *cli() { return m_cli; }
    Notifier *notifier() const { return m_notifier; } // 通知动作（open）→ 上层 bringToFront

    // ── 数据动作 ──
    void refreshAll();
    void refreshLight(); // 300s 周期 / 托盘弹窗 onShow：仅 status
    void loadProject(const QString &name);
    void loadDocs(const QString &name);

    void runUpdate(const QString &name, bool deep);
    // C5「更新 + AI 摘要」（mac UpdateActionMenu 变体）：真更新走同一把 busy 锁，
    // 成功后 worker 生成 AiDigests::updateDigest，结果经 updateDigestReady 广播
    void runUpdateDigest(const QString &name, bool deep);
    void updateAll(bool deep, bool silent, std::function<void(const AgentBulkReport &)> onDone);
    void stopUpdate(); // StopDecision 三态（唯一警告 = cancelled）

    void gitOp(const QString &op, const QString &name, const QString &message = QString());

    void addProject(const QString &path, const QString &name);
    void scan(const QString &root, int depth); // 结果经 scanFinished 广播

    void addMilestone(const QString &project, const QString &name, const QString &tag,
        const QString &date, const QString &desc);
    // action ∈ done|reopen|drop（UI 词 "open" → CLI "reopen" 由调用方转换）
    void setMilestoneStatus(const QString &project, const QString &name, const QString &action);
    void removeMilestone(const QString &project, const QString &name);

    void setSelection(Selection sel);
    void go(Selection sel); // 等价 setSelection + 通知路由
    void setDashFilter(const DashFilter &f);
    void restartAutoTimer(); // 设置页改周期后立即生效（不经过保存按钮）
    void clearLastError();
    void setEngineResult(const EngineLocator::Result &engine); // 「重新检测引擎」后更新故障态

    // 托盘速览快照（main 轮询/信号驱动填充）
    struct TrayState {
        QString menuTitle;
        Liveness tint = Liveness::unknown;
    };
    TrayState trayState() const;

signals:
    void projectsChanged();
    void dashboardChanged();
    void milestonesChanged();
    void projectChanged(const QString &name);
    void docsChanged(const QString &name);
    void gitOutputReady(const QString &name, const GitOpResponse &resp);
    void scanFinished(bool ok, const QString &message, const QString &coverageNote);
    void addFinished(bool ok, const QString &message);
    void milestoneActionFinished(bool ok, const QString &message);
    void busyChanged();
    void lastErrorChanged(const QString &message);
    void selectionChanged(Selection sel);
    void dashFilterChanged();
    void bulkReportReady(const AgentBulkReport &report);
    void refreshCycleFinished(bool ok); // 一轮 refreshAll 收尾（托盘/侧栏状态条用）
    // 「更新 + AI 摘要」收尾：ok=报告已生成（text=markdown）；!ok=没有生成（text=原因，
    // 可为空——更新本身失败时原因已走 lastError/通知，这里只撤 UI 的 busy 态）
    void updateDigestReady(bool ok, bool deep, const QString &project, const QString &text);

    // 引擎发现结果变化（含「重新检测引擎」后的回灌）：UI 重新读 engineFound/engineProblem
    void engineFoundChanged();

private:
    // ── 合并闸门：撞上不丢弃、排队补跑一次不叠加 ──
    bool tryEnterRefresh();
    void leaveRefresh();

    void runRefreshAll();
    void fetchStatus(std::function<void(bool ok)> onDone);
    void fetchDashboard();
    void fetchMilestones();
    void applyMilestoneLoadRules(const MilestonesEnvelope &e); // 存储降级三规则
    void postNotificationsIfNeeded();
    void runBulkOverFrozenTargets(bool deep, bool silent,
        std::function<void(const AgentBulkReport &)> finish);

    void runUpdateInternal(const QString &name, bool deep,
        std::function<void(bool ok, const UpdateResultBase *result)> onDone);
    void reloadAfterWrite(const QString &projectName); // update/git/milestone 写操作后的回读

    EngineLocator::Result m_engine;
    EngineCli *m_cli = nullptr;
    Notifier *m_notifier = nullptr;

    std::vector<ProjectStatus> m_projects;
    std::optional<EngineSummary> m_summary;
    std::optional<DashboardData> m_dashboard;
    LoadStateBox m_dashboardState;
    std::optional<MilestonesEnvelope> m_milestones;
    LoadStateBox m_milestonesState;
    QMap<QString, LoadStateBox> m_docsStates;
    QMap<QString, DocsEnvelope> m_docs;
    QMap<QString, QString> m_projectLoadErrors;

    QString m_lastError;
    bool m_hasLoadedProjectsOnce = false;
    qint64 m_lastRefreshedMs = 0;

    Selection m_selection;
    DashFilter m_dashFilter;

    bool m_busyAll = false;
    QSet<QString> m_busyProjects;
    bool m_refreshing = false;
    bool m_refreshQueued = false;
    bool m_bulkStopRequested = false; // 「停止更新」置位：runBulkOverFrozenTargets 不再启动剩余仓库
    QMetaObject::Connection m_bulkGate; // updateAll 等 refreshCycleFinished 的一次性闸门（存成员：disconnect 需要真连接）
    bool m_engineFound = false;
    bool m_enginePending = false; // 发现链在跑（locateAsync 未收尾）；期间引擎未找到不算"连接失败"
    QString m_engineProblem;

    QTimer *m_lightTimer = nullptr;  // 300s 轻刷新
    QTimer *m_autoTimer = nullptr;   // 定时更新（autoHours 周期）
    QTimer *m_firstRunTimer = nullptr; // 首轮 600s 一次性（存成员防幽灵）
    QElapsedTimer m_refreshStart;

    // 通知去重（「新变差」才发）
    QSet<QString> m_notifiedBranchStale;
    QSet<QString> m_notifiedDirtyBucket;
    QSet<QString> m_seenStaleBranches; // 只有「新出现」的停滞分支才提醒
    bool m_havePrevSnapshot = false;
};
