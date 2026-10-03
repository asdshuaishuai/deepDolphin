#include "AppModel.h"
#include "../ai/AIConfig.h"
#include "../ai/AIEngine.h"
#include "../ai/AIEngineFactory.h"
#include "../ai/AiDigests.h"
#include "../ai/SecretStore.h"
#include "../logic/Derived.h"
#include "../logic/ScanCoverage.h"
#include "../logic/StopDecision.h"
#include "../logic/UpdateOutcome.h"
#include "Notifier.h"
#include "Settings.h"
#include <QDateTime>
#include <QFileInfo>
#include <QJsonObject>
#include <QLocale>
#include <QMetaObject>
#include <QPointer>
#include <QThreadPool>
#include <QTimer>
#include <algorithm>

namespace {

// status/update/deep 的全局静默旗标（叙述层走 stderr，--json 载荷干净）
const QStringList kQuiet = { QStringLiteral("--json"), QStringLiteral("--quiet") };

// 里程碑 CLI 子命令 → 用户文案（done/drop/reopen 是引擎动词，不直接见人）
QString milestoneActionLabel(const QString &action)
{
    if (action == QLatin1String("done"))
        return QStringLiteral("已达成里程碑");
    if (action == QLatin1String("drop"))
        return QStringLiteral("已放弃里程碑");
    if (action == QLatin1String("reopen"))
        return QStringLiteral("已重开里程碑");
    if (action == QLatin1String("remove"))
        return QStringLiteral("已删除里程碑");
    return action;
}

// AI 配置快照：key 从安全存储读（同步 libsecret）——**只允许在 worker 线程调**
//（PLAN §2.5：GLib 同步 API 不阻塞 UI；钥匙串迟缓时不能冻住界面）。
AIConfig loadAiConfigWithKey()
{
    AIConfig cfg = AIConfig::load();
    SecretStore store;
    cfg.apiKey = AIConfig::loadKey(&store);
    return cfg;
}

// 项目按系统本地化排序（QString::localeAwareCompare，mac localizedStandardCompare 对位）
void sortProjects(std::vector<ProjectStatus> &projects)
{
    std::sort(projects.begin(), projects.end(),
        [](const ProjectStatus &a, const ProjectStatus &b) {
            return a.name.localeAwareCompare(b.name) < 0;
        });
}

} // namespace

QString AgentBulkReport::toMarkdown() const
{
    // 结果面板：列表不用表格；总账分母 = attempted（唯一来源）。
    // 「实际执行」= rows.size()（不是 attempted）：中途「停止更新」就地收尾时，
    // 未启动的仓库没有逐仓库行，账必须对得上。
    QString md = QStringLiteral("# %1 · 全量\n\n")
                     .arg(deep ? QStringLiteral("深更新") : QStringLiteral("浅更新"));
    md += QStringLiteral("已注册 %1 个，实际执行 %2 个，成功 %3，失败 %4。\n\n")
              .arg(attempted)
              .arg(rows.size())
              .arg(succeeded)
              .arg(failed);
    md += QStringLiteral("## 逐仓库结果\n");
    if (rows.isEmpty()) {
        md += QStringLiteral("（没有已注册项目，未执行任何仓库。）\n");
    } else {
        for (const AgentBulkRow &r : rows)
            md += QStringLiteral("- **%1** %2%3\n")
                      .arg(r.name,
                          r.ok ? QStringLiteral("✅") : QStringLiteral("❌"), QStringLiteral(" ")
                              + r.detail);
    }
    md += QStringLiteral("\n## AI 简报\n\n%1\n").arg(aiNote);
    return md;
}

QString AgentBulkReport::outcomeTable() const
{
    // mac AgentBulkUpdate.digest 的逐仓库表：`name：完成` / `name：失败（原因）`
    if (rows.isEmpty())
        return QStringLiteral("（没有已注册项目）");
    QStringList lines;
    for (const AgentBulkRow &r : rows)
        lines << QStringLiteral("%1：%2")
                     .arg(r.name,
                         r.ok ? QStringLiteral("完成")
                              : QStringLiteral("失败（%1）").arg(r.detail));
    return lines.join(QStringLiteral("\n"));
}

AppModel::AppModel(const EngineLocator::Result &engine, EngineCli *cli, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
    , m_cli(cli)
    , m_notifier(new Notifier(this))
    , m_engineFound(engine.found)
    , m_enginePending(engine.pending)
    , m_engineProblem(engine.problems.join(QStringLiteral("；")))
{
    connect(m_cli, &EngineCli::engineMissing, this, [this] {
        // 引擎在运行中消失（被删/权限变化）：如实转故障态，不静默。
        // 但「从来没设过 bin」不是"引擎消失"——那是从未发现过引擎（SetupGuidePage 的口径），
        // 不能让一次 notFound 把启动态从"未发现"改写成"运行中丢失"（M0-1：否则界面文案错说原因）。
        if (m_cli->engineBin().isEmpty())
            return;
        m_engineFound = false;
        m_engineProblem = EngineLocator::installHint();
    });
}

void AppModel::start()
{
    // 三件套 timer（先收再挂——restartAutoTimer 语义一致）
    if (!m_lightTimer) {
        m_lightTimer = new QTimer(this);
        m_lightTimer->setInterval(300 * 1000);
        connect(m_lightTimer, &QTimer::timeout, this, &AppModel::refreshLight);
    }
    if (!m_autoTimer) {
        m_autoTimer = new QTimer(this);
        connect(m_autoTimer, &QTimer::timeout, this, [this] {
            // 定时更新 = 全量浅更新（silent）；AI 简报经通知送达（mac runScheduledUpdate 对位：
            // 已配置 → 「定时更新简报」；失败 → 「定时更新完成 + 简报失败原因」；未配置 → 完成通知）
            updateAll(false, true, [this](const AgentBulkReport &report) {
                if (report.failed > 0) {
                    m_notifier->notify(QStringLiteral("定时更新失败"),
                        QStringLiteral("%1 个项目更新，%2 个失败（详见面板）")
                            .arg(report.succeeded)
                            .arg(report.failed),
                        {});
                    return;
                }
                const QString doneBody = report.attempted > 0 && report.succeeded == 0
                    ? QStringLiteral("%1 个项目进度已记录").arg(report.attempted)
                    : QStringLiteral("%1 个项目已更新").arg(report.attempted);
                // key 读取（同步 libsecret）与「已配置」判定都在 worker（PLAN §2.5）；
                // 未配置（T8 降级）：不伪造摘要，完成通知照发
                QPointer<AppModel> guard(this);
                const QString engineBin = m_cli->engineBin();
                QThreadPool::globalInstance()->start([this, guard, engineBin, doneBody] {
                    AIConfig cfg = loadAiConfigWithKey();
                    QString why;
                    if (!AIEngineFactory::create(cfg)->isConfigured(&why)) {
                        if (!guard)
                            return;
                        QMetaObject::invokeMethod(
                            guard,
                            [this, guard, doneBody] {
                                if (!guard)
                                    return;
                                m_notifier->notify(QStringLiteral("定时更新完成"), doneBody, {});
                            },
                            Qt::QueuedConnection);
                        return;
                    }
                    // AI 简报在 worker 生成（agent 工具循环阻塞——不占 GUI 线程）
                    const AiDigests::Outcome d = AiDigests::scheduledDigest(engineBin, cfg);
                    if (!guard)
                        return;
                    QMetaObject::invokeMethod(
                        guard,
                        [this, guard, d] {
                            if (!guard)
                                return;
                            if (d.ok)
                                m_notifier->notify(QStringLiteral("定时更新简报"), d.text.left(180), {});
                            else
                                m_notifier->notify(QStringLiteral("定时更新完成"),
                                    QStringLiteral("全部项目进度已记录（AI 简报失败：%1）")
                                        .arg(d.error.left(60)),
                                    {});
                        },
                        Qt::QueuedConnection);
                });
            });
        });
    }
    if (!m_firstRunTimer) {
        m_firstRunTimer = new QTimer(this);
        m_firstRunTimer->setSingleShot(true);
        connect(m_firstRunTimer, &QTimer::timeout, m_autoTimer, [this] { m_autoTimer->start(); });
    }
    restartAutoTimer();

    refreshAll();
}

void AppModel::stop()
{
    // 收掉 3 个 timer；引擎子进程由 EngineCli/ProcessRegistry 随进程收口
    if (m_lightTimer)
        m_lightTimer->stop();
    if (m_autoTimer)
        m_autoTimer->stop();
    if (m_firstRunTimer)
        m_firstRunTimer->stop();
}

void AppModel::restartAutoTimer()
{
    const int hours = Settings::instance().autoUpdateHours();
    if (m_autoTimer)
        m_autoTimer->stop();
    if (m_firstRunTimer)
        m_firstRunTimer->stop();
    if (hours <= 0)
        return; // 关闭
    // 首轮 600s 一次性 + 周期 timer（两个都存成员——幽灵 timer 的教训）
    m_firstRunTimer->start(600 * 1000);
    m_autoTimer->start(hours * 3600 * 1000);
}

// ── 合并闸门 ──

bool AppModel::tryEnterRefresh()
{
    if (m_refreshing) {
        m_refreshQueued = true; // 撞上不丢弃：当前这轮结束后补跑一次
        return false;
    }
    m_refreshing = true;
    return true;
}

void AppModel::leaveRefresh()
{
    m_refreshing = false;
    if (m_refreshQueued) {
        m_refreshQueued = false;
        QTimer::singleShot(0, this, &AppModel::refreshAll);
    }
    emit busyChanged();
}

void AppModel::refreshAll()
{
    if (!tryEnterRefresh())
        return;
    runRefreshAll();
}

void AppModel::runRefreshAll()
{
    m_refreshStart.start();
    fetchStatus([this](bool ok) {
        if (!ok) {
            // 失败短路：不等 dashboard/milestones 的 180s
            leaveRefresh();
            emit refreshCycleFinished(false);
            emit refreshAllFinished(false);
            return;
        }
        // status 落地即广播：看板/侧栏只认 projectsChanged，启动路径不发它们就永远空白
        emit projectsChanged();
        fetchDashboard();
    });
}

void AppModel::refreshLight()
{
    if (!engineFound())
        return;
    fetchStatus([this](bool) {
        emit projectsChanged();
        emit refreshCycleFinished(true);
    });
}

void AppModel::fetchStatus(std::function<void(bool ok)> onDone)
{
    m_cli->callJson(QStringList { QStringLiteral("status") } + kQuiet, EngineTimeouts::Status,
        [this, onDone](const EngineCli::EngineResult &res) {
            if (!res.ok()) {
                m_lastError = res.error.userMessage();
                emit lastErrorChanged(m_lastError);
                onDone(false);
                return;
            }
            const auto env = res.payload.has_value()
                ? StatusEnvelope::decodeEnvelopeOrBare(*res.payload)
                : std::nullopt;
            if (!env.has_value()) {
                m_lastError = QStringLiteral("引擎输出不是合法的项目状态（契约可能过旧）");
                emit lastErrorChanged(m_lastError);
                onDone(false);
                return;
            }
            // TCC 预检的 Linux 等价物（PLAN §8 T6）：首个项目路径可读性预检
            for (const ProjectStatus &p : env->projects) {
                if (!p.isUnreadable() && !p.path.isEmpty() && !QFileInfo::exists(p.path)) {
                    m_lastError = QStringLiteral("%1：路径不存在或卷未挂载（%2）")
                                      .arg(p.name, p.path);
                    emit lastErrorChanged(m_lastError);
                    break;
                }
            }
            m_projects = env->projects;
            sortProjects(m_projects);
            m_summary = env->summary;
            m_hasLoadedProjectsOnce = true; // 成功才置位（pendingRoute 在此处补判）
            onDone(true);
        });
}

void AppModel::fetchDashboard()
{
    m_dashboardState = { LoadState::loading, QString() };
    emit dashboardChanged();
    m_cli->callJson({ QStringLiteral("dashboard"), QStringLiteral("--json") },
        EngineTimeouts::Dashboard, [this](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value()) {
                m_dashboardState = { LoadState::failed,
                    res.ok() ? QStringLiteral("引擎输出不是合法 JSON（契约可能过旧）")
                             : res.error.userMessage() };
                emit dashboardChanged();
                fetchMilestones();
                return;
            }
            const auto d = DashboardData::fromJson(res.payload->object());
            if (!d.has_value()) {
                m_dashboardState = { LoadState::failed,
                    QStringLiteral("仪表盘载荷缺键（契约可能过旧）") };
                emit dashboardChanged();
                fetchMilestones();
                return;
            }
            m_dashboard = d;
            m_dashboardState = { LoadState::loaded, QString() };
            emit dashboardChanged();
            fetchMilestones();
        });
}

void AppModel::fetchMilestones()
{
    m_cli->callJson({ QStringLiteral("milestone"), QStringLiteral("list"), QStringLiteral("--json") },
        EngineTimeouts::Milestones, [this](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value()) {
                m_milestonesState = { LoadState::failed,
                    res.ok() ? QStringLiteral("引擎输出不是合法 JSON（契约可能过旧）")
                             : res.error.userMessage() };
                emit milestonesChanged();
                m_lastRefreshedMs = QDateTime::currentMSecsSinceEpoch();
                postNotificationsIfNeeded();
                leaveRefresh();
                emit refreshCycleFinished(false);
                emit refreshAllFinished(false);
                return;
            }
            const auto e = MilestonesEnvelope::fromJson(res.payload->object());
            if (!e.has_value()) {
                m_milestonesState = { LoadState::failed,
                    QStringLiteral("里程碑载荷缺键（契约可能过旧）") };
                emit milestonesChanged();
                m_lastRefreshedMs = QDateTime::currentMSecsSinceEpoch();
                postNotificationsIfNeeded();
                leaveRefresh();
                emit refreshCycleFinished(false);
                emit refreshAllFinished(false);
                return;
            }
            applyMilestoneLoadRules(*e);
            m_lastRefreshedMs = QDateTime::currentMSecsSinceEpoch();
            postNotificationsIfNeeded();
            leaveRefresh();
            emit refreshCycleFinished(true);
            emit refreshAllFinished(true);
        });
}

void AppModel::applyMilestoneLoadRules(const MilestonesEnvelope &e)
{
    // 存储降级三规则（SPEC §3.5 LoadRules）：
    //   ok → loaded；readCount>0 → loaded + degradedNotice（挂 lastError）；==0 → failed。
    m_milestones = e;
    const QString health = e.storeHealth;
    if (health == QLatin1String("ok")) {
        m_milestonesState = { LoadState::loaded, QString() };
    } else if (e.readCount > 0) {
        const QString notice = QStringLiteral("milestones.json %1：读到 %2 条，另有部分读不出来")
                                   .arg(health)
                                   .arg(e.readCount);
        m_milestonesState = { LoadState::loaded, notice };
        m_lastError = notice;
        emit lastErrorChanged(m_lastError);
    } else {
        m_milestonesState = { LoadState::failed,
            QStringLiteral("里程碑存储降级（%1），读到 0 条 —— 这不是「还没有里程碑」").arg(health) };
    }
    emit milestonesChanged();
}

void AppModel::loadProject(const QString &name)
{
    m_cli->callJson(QStringList { QStringLiteral("status"), name } + kQuiet,
        EngineTimeouts::StatusProject,
        [this, name](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value()) {
                m_projectLoadErrors[name] = res.ok()
                    ? QStringLiteral("引擎输出不是合法 JSON（契约可能过旧）")
                    : res.error.userMessage();
                emit projectChanged(name);
                return;
            }
            const auto env = StatusEnvelope::decodeEnvelopeOrBare(*res.payload);
            if (!env.has_value() || env->projects.empty()) {
                // 空列表 → 显式报错不造假壳（SPEC §2）
                m_projectLoadErrors[name] = QStringLiteral("引擎没有返回该项目（可能已被移除）");
                emit projectChanged(name);
                return;
            }
            m_projectLoadErrors.remove(name);
            // 回写主列表（保持主刷新口径一致）
            bool replaced = false;
            for (ProjectStatus &p : m_projects) {
                if (p.name == name) {
                    p = env->projects.front();
                    replaced = true;
                    break;
                }
            }
            if (!replaced)
                m_projects.push_back(env->projects.front());
            emit projectChanged(name);
            emit projectsChanged();
        });
}

void AppModel::loadDocs(const QString &name)
{
    m_docsStates[name] = { LoadState::loading, QString() };
    emit docsChanged(name);
    m_cli->callJson({ QStringLiteral("docs"), name, QStringLiteral("--json") },
        EngineTimeouts::Docs, [this, name](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value()) {
                m_docsStates[name] = { LoadState::failed,
                    res.ok() ? QStringLiteral("引擎输出不是合法 JSON（契约可能过旧）")
                             : res.error.userMessage() };
                emit docsChanged(name);
                return;
            }
            const auto e = DocsEnvelope::fromJson(res.payload->object());
            if (!e.has_value()) {
                m_docsStates[name] = { LoadState::failed, QStringLiteral("docs 载荷缺键（契约可能过旧）") };
                emit docsChanged(name);
                return;
            }
            m_docs[name] = *e;
            m_docsStates[name] = { LoadState::loaded, QString() };
            // unreadable 非空 → 挂 lastError（SPEC §1.4-D / Model.swift:598-600）
            for (const UnreadableDocs &u : e->unreadable) {
                if (u.unreadable.isEmpty())
                    continue;
                m_lastError = QStringLiteral("%1：以下文档存在但读取失败 —— %2")
                                  .arg(u.project.isEmpty() ? name : u.project, u.unreadable);
                emit lastErrorChanged(m_lastError);
            }
            emit docsChanged(name);
        });
}

// ── 更新动作 ──

void AppModel::runUpdate(const QString &name, bool deep)
{
    if (m_busyAll || m_busyProjects.contains(name))
        return;
    runUpdateInternal(name, deep, [this, name, deep](bool ok, const UpdateResultBase *result) {
        Q_UNUSED(deep);
        if (!ok)
            return;
        if (result)
            m_notifier->notify(deep ? QStringLiteral("深度更新完成") : QStringLiteral("进度已记录"),
                UpdateOutcome::summary(*result), {});
        reloadAfterWrite(name);
    });
}

void AppModel::runUpdateInternal(const QString &name, bool deep,
    std::function<void(bool ok, const UpdateResultBase *result)> onDone)
{
    m_busyProjects.insert(name);
    emit busyChanged();
    const QString cmd = deep ? QStringLiteral("deep") : QStringLiteral("update");
    m_cli->callJson(QStringList { cmd, name } + kQuiet, deep ? EngineTimeouts::Deep : EngineTimeouts::Update,
        [this, name, deep, onDone](const EngineCli::EngineResult &res) {
            m_busyProjects.remove(name);
            emit busyChanged();
            if (res.error.kind == EngineErrorKind::cancelled) {
                // 被停不报失败：不写 lastError/不弹通知；收尾回调仍要走到
                //（调用方撤自己的 busy/等待态——如「更新 + AI 摘要」的结果窗）
                onDone(false, nullptr);
                return;
            }
            if (!res.ok()) {
                m_lastError = QStringLiteral("%1：%2").arg(name, res.error.userMessage());
                emit lastErrorChanged(m_lastError);
                m_notifier->notify(QStringLiteral("更新失败"), m_lastError, {});
                onDone(false, nullptr);
                return;
            }
            if (!res.payload.has_value()) {
                onDone(false, nullptr);
                return;
            }
            const UpdateResultAny any = decodeUpdateResultEntry(res.payload->object());
            if (std::holds_alternative<UpdateFailureEntry>(any)) {
                m_lastError = QStringLiteral("%1：%2")
                                  .arg(name, std::get<UpdateFailureEntry>(any).message);
                emit lastErrorChanged(m_lastError);
                onDone(false, nullptr);
                return;
            }
            const UpdateResultBase *base = std::holds_alternative<ShallowUpdateResult>(any)
                ? static_cast<const UpdateResultBase *>(&std::get<ShallowUpdateResult>(any))
                : static_cast<const UpdateResultBase *>(&std::get<DeepUpdateResult>(any));
            onDone(true, base);
        });
}

void AppModel::runUpdateDigest(const QString &name, bool deep)
{
    if (m_busyAll || m_busyProjects.contains(name))
        return;
    runUpdateInternal(name, deep, [this, name, deep](bool ok, const UpdateResultBase *result) {
        Q_UNUSED(result);
        if (!ok) {
            // 更新失败/被停：AI 报告无从生成——ok=false + 空原因（失败原因已走
            // lastError/通知），调用方只负责撤 busy 态
            emit updateDigestReady(false, deep, name, QString());
            return;
        }
        reloadAfterWrite(name);
        // AI 摘要在 worker：agent 工具循环阻塞 + key 读取是同步 libsecret——
        // 两件事都不进 GUI 线程（PLAN §2.5）
        QPointer<AppModel> guard(this);
        const QString engineBin = m_cli->engineBin();
        QThreadPool::globalInstance()->start([this, guard, name, deep, engineBin] {
            AIConfig cfg = loadAiConfigWithKey();
            AiDigests::Outcome d;
            QString why;
            if (!AIEngineFactory::create(cfg)->isConfigured(&why)) {
                d.error = QStringLiteral(
                    "AI 未配置：%1\n\n更新本身已经完成，结果以通知为准；"
                    "要生成 AI 报告请在「设置 → AI」里选择渠道并填写 API Key。")
                                  .arg(why);
            } else {
                d = AiDigests::updateDigest(engineBin, cfg, name, deep);
            }
            if (!guard)
                return;
            QMetaObject::invokeMethod(
                guard,
                [this, guard, name, deep, d] {
                    if (!guard)
                        return;
                    emit updateDigestReady(d.ok, deep, name, d.ok ? d.text : d.error);
                },
                Qt::QueuedConnection);
        });
    });
}

void AppModel::updateAll(bool deep, bool silent, std::function<void(const AgentBulkReport &)> onDone)
{
    if (m_busyAll)
        return; // busyAll 单锁：同一把锁覆盖所有批量入口，不得绕过
    m_busyAll = true;
    emit busyChanged();

    auto finish = [this, deep, silent, onDone](const AgentBulkReport &report) {
        m_busyAll = false;
        emit busyChanged();
        refreshAll();
        if (!silent) {
            if (report.failed > 0)
                m_notifier->notify(
                    deep ? QStringLiteral("全部深度更新完成") : QStringLiteral("全部进度已记录"),
                    QStringLiteral("%1 个项目更新，%2 个失败（详见面板）")
                        .arg(report.succeeded)
                        .arg(report.failed),
                    {});
            else if (report.succeeded == 0)
                m_notifier->notify(
                    deep ? QStringLiteral("全部深度更新完成") : QStringLiteral("全部进度已记录"),
                    QStringLiteral("%1 个项目都没有需要更新的文档").arg(report.attempted), {});
            else
                m_notifier->notify(
                    deep ? QStringLiteral("全部深度更新完成") : QStringLiteral("全部进度已记录"),
                    QStringLiteral("%1 个项目已更新（%2 个有进展）")
                        .arg(report.attempted)
                        .arg(report.succeeded),
                    {});
            // 结果面板只随 UI 入口弹（mac updateAll(silent:) 从不设 agentBulkResult）：
            // 定时更新/重新索引走 silent，不发 bulkReportReady，不在后台偷偷弹窗
            emit bulkReportReady(report);
        }
        if (onDone)
            onDone(report);
    };

    // 覆盖顺序：先 refreshAll（刷新注册表）**等它跑完**再冻结名单——
    // 防拿陈旧名单漏掉别的进程新注册的仓库（实测：CLI 加仓库后不刷新就全量 → 账对不上）。
    refreshAll();
    m_bulkStopRequested = false; // 新一轮全量开启：清除上一轮的停止请求
    // 闸门连接存成员（m_bulkGate）再回填：不能把 Connection 按值捕获进自身初始化器
    //（捕获到的是未初始化副本，disconnect 断不开真连接——循环重跑全量更新）
    // 接 refreshAllFinished（专用信号）：refreshCycleFinished 被 300s 轻刷新共用，
    // 接那里会让轻刷新在全量刷新落地前提前放行 → 冻结陈旧名单（M0-6）
    if (m_bulkGate)
        disconnect(m_bulkGate); // 理论不可达（busyAll 单锁期内不会有第二个闸门），防御性清理
    m_bulkGate = connect(this, &AppModel::refreshAllFinished, this,
        [this, deep, silent, finish](bool) mutable {
            if (m_bulkGate) {
                disconnect(m_bulkGate);
                m_bulkGate = QMetaObject::Connection();
            }
            runBulkOverFrozenTargets(deep, silent, finish);
        });
}

void AppModel::runBulkOverFrozenTargets(bool deep, bool silent,
    std::function<void(const AgentBulkReport &)> finish)
{
    // 名单 = projects **全部条目（含采集失败的）**——失败项目恰是最需要被告知的
    QVector<ProjectStatus> targets;
    for (const ProjectStatus &p : m_projects)
        targets.append(p);

    auto report = new AgentBulkReport;
    report->deep = deep;
    report->attempted = targets.size();
    if (targets.isEmpty()) {
        // aiNote 三态之一：没东西可跑也要说明 AI 层发生了什么。
        // key 读取（同步 libsecret）走 worker（PLAN §2.5）；结论回 GUI 再 finish。
        QPointer<AppModel> guard(this);
        QThreadPool::globalInstance()->start([this, guard, report, finish] {
            AIConfig cfg = loadAiConfigWithKey();
            QString why;
            const bool aiUsable = AIEngineFactory::create(cfg)->isConfigured(&why);
            report->aiNote = aiUsable
                ? QStringLiteral("没有已注册项目，AI 简报无事可写。")
                : QStringLiteral(
                    "未生成 AI 简报：AI 未配置。更新本身没有可执行的项目，结果以逐仓库列表为准。");
            if (!guard) {
                delete report;
                return;
            }
            QMetaObject::invokeMethod(
                guard, [guard, report, finish] { finish(*report); delete report; },
                Qt::QueuedConnection);
        });
        return;
    }

    // 逐仓库顺序执行（代码逐个显式传项目名——不许 prefix/filter/dropFirst；一个失败不中断）
    struct Shared {
        QVector<ProjectStatus> targets;
        int index = 0;
        AgentBulkReport *report = nullptr;
        std::function<void()> next;
    };
    auto shared = new Shared { targets, 0, report, {} };
    const int timeout = deep ? EngineTimeouts::DeepAll : EngineTimeouts::UpdateAll;
    // 循环收尾：逐仓库事实先行；AI 简报（仅 UI 入口）在 worker 生成后再交出结果——
    // 定时更新场景（silent）不重复生成，简报经「定时更新简报」通知送达。
    // key 读取（同步 libsecret）与「已配置」判定一并放 worker（PLAN §2.5），
    // 分支结论回 GUI 再 finish/派生 bulkDigest。
    auto finalize = [this, deep, silent, finish](AgentBulkReport out) {
        QPointer<AppModel> guard(this);
        const QString engineBin = m_cli->engineBin();
        const QString table = out.outcomeTable();
        QThreadPool::globalInstance()->start([this, guard, deep, silent, finish, engineBin, out,
                                                 table] {
            AIConfig cfg = loadAiConfigWithKey();
            QString why;
            const bool aiUsable = AIEngineFactory::create(cfg)->isConfigured(&why);
            if (!guard)
                return;
            if (silent || !aiUsable) {
                AgentBulkReport local = out;
                local.aiNote = aiUsable
                    ? QStringLiteral("定时更新场景：AI 简报经「定时更新简报」通知送达；此处只列事实。")
                    : QStringLiteral("未生成 AI 简报：AI 未配置（%1）。"
                                     "更新本身已经执行完毕，结果以逐仓库列表为准。")
                          .arg(why);
                QMetaObject::invokeMethod(
                    guard, [guard, local, finish] { finish(local); }, Qt::QueuedConnection);
                return;
            }
            // UI 入口：worker 里跑 bulkDigest（agent 工具循环阻塞），完成后才 finish——
            // 结果面板一次给出最终 aiNote（mac UpdateActionMenu 的 busy → 正文同构）。
            const AiDigests::Outcome d = AiDigests::bulkDigest(engineBin, cfg, table, deep);
            AgentBulkReport final = out;
            if (d.ok)
                final.aiNote = QStringLiteral("由 AI agent 依据引擎事实生成。\n\n") + d.text;
            else
                final.aiNote = QStringLiteral("未生成 AI 简报：%1\n\n"
                                              "更新本身已经执行完毕，结果以逐仓库列表为准。")
                                   .arg(d.error);
            QMetaObject::invokeMethod(
                guard, [guard, final, finish] { finish(final); }, Qt::QueuedConnection);
        });
    };
    shared->next = [this, shared, deep, timeout, finalize] {
        // 停止判据：「停止更新」已请求（引擎子进程被杀、当前仓库会以 cancelled 收尾）→
        // 不再启动剩余仓库，就地收尾（mac ②cancel Swift Task 的对位）
        if (shared->index >= shared->targets.size() || m_bulkStopRequested) {
            // 此时正在执行的就是 shared->next 这个 functor——先把自己要用的东西拷出来，
            // shared 的销毁延后一拍：在 operator() 存续期内 delete 自身 functor 是
            // use-after-free（finalize/finish 的捕获会读到被复用的内存——实测停止路径
            // 上 finish 的 this 变成垃圾指针，必现段错误）
            AgentBulkReport out = *shared->report;
            const std::function<void(AgentBulkReport)> fin = finalize;
            AgentBulkReport *rep = shared->report;
            QTimer::singleShot(0, this, [shared, rep] { delete rep; delete shared; });
            fin(out);
            return;
        }
        const ProjectStatus p = shared->targets.at(shared->index++);
        const QString cmd = deep ? QStringLiteral("deep") : QStringLiteral("update");
        m_cli->callJson(QStringList { cmd, p.name } + kQuiet, timeout,
            [this, shared, p](const EngineCli::EngineResult &res) {
                bool okEntry = false;
                if (res.ok() && res.payload.has_value()) {
                    const UpdateResultAny any = decodeUpdateResultEntry(res.payload->object());
                    if (!std::holds_alternative<UpdateFailureEntry>(any)) {
                        const UpdateResultBase *base
                            = std::holds_alternative<ShallowUpdateResult>(any)
                            ? static_cast<const UpdateResultBase *>(
                                  &std::get<ShallowUpdateResult>(any))
                            : static_cast<const UpdateResultBase *>(
                                  &std::get<DeepUpdateResult>(any));
                        shared->report->succeeded += 1;
                        shared->report->rows.append(
                            { p.name, true, UpdateOutcome::summary(*base) });
                        okEntry = true;
                    }
                }
                if (!okEntry) {
                    shared->report->failed += 1;
                    shared->report->rows.append({ p.name, false,
                        res.error.kind == EngineErrorKind::cancelled
                            ? QStringLiteral("已停止")
                            : res.error.userMessage() });
                }
                shared->next();
            });
    };
    shared->next();
}

void AppModel::stopUpdate()
{
    // 两步顺序不能反：① 真杀引擎子进程（只杀 update/deep，不伤并行 status）
    // ② 请求批量链停止——runBulkOverFrozenTargets 见 m_bulkStopRequested 即不再
    // 启动剩余仓库（mac ②cancel Swift Task 的对位）
    const int killed = m_cli->stopUpdates();
    m_bulkStopRequested = true;
    const bool stillAlive = !m_busyProjects.isEmpty() || m_busyAll;
    const StopDecision::Outcome o = StopDecision::decide(killed, stillAlive);
    // busyAll/busyProjects **不在此复位**：提前复位会让新一轮 updateAll 与残留旧链并发
    // （旧链各回调会立刻以 cancelled 收尾并自己释放锁——真正的收尾在各回调里）
    emit busyChanged();
    m_notifier->notify(QStringLiteral("停止更新"), StopDecision::message(o, m_projects.size()), {});
    if (StopDecision::shouldWarn(o)) {
        m_lastError = StopDecision::message(o, m_projects.size());
        emit lastErrorChanged(m_lastError);
    }
}

// ── git 操作 ──

void AppModel::gitOp(const QString &op, const QString &name, const QString &message)
{
    if (m_busyProjects.contains(name))
        return;
    m_busyProjects.insert(name);
    emit busyChanged();
    QStringList args = { QStringLiteral("git"), op, name };
    if (!message.isEmpty())
        args << QStringLiteral("--message") << message;
    args << QStringLiteral("--json");
    m_cli->callJson(args, EngineTimeouts::Git, [this, name, op](const EngineCli::EngineResult &res) {
        m_busyProjects.remove(name);
        emit busyChanged();
        GitOpResponse resp;
        if (res.ok() && res.payload.has_value()) {
            const auto parsed = GitOpResponse::fromJson(res.payload->object());
            if (parsed.has_value())
                resp = *parsed;
        }
        if (resp.op.isEmpty()) {
            resp.op = op;
            resp.ok = false;
            resp.project = name;
            resp.output = res.ok() ? QStringLiteral("引擎输出不是合法 JSON（契约可能过旧）")
                                   : res.error.userMessage();
        }
        if (resp.ok)
            m_notifier->notify(QStringLiteral("git %1 完成").arg(op), name, {});
        emit gitOutputReady(name, resp);
        reloadAfterWrite(name);
    });
}

void AppModel::reloadAfterWrite(const QString &projectName)
{
    // 写操作后回读单项目 + 文档 + 里程碑/仪表盘聚合（失败不短路——尽力而为的刷新）
    loadProject(projectName);
    loadDocs(projectName);
    m_cli->callJson({ QStringLiteral("milestone"), QStringLiteral("list"), QStringLiteral("--json") },
        EngineTimeouts::Milestones, [this](const EngineCli::EngineResult &res) {
            if (res.ok() && res.payload.has_value()) {
                const auto e = MilestonesEnvelope::fromJson(res.payload->object());
                if (e.has_value())
                    applyMilestoneLoadRules(*e);
            }
        });
}

// ── 添加 / 扫描 ──

void AppModel::addProject(const QString &path, const QString &name)
{
    QStringList args = { QStringLiteral("add"), path, QStringLiteral("--json") };
    if (!name.isEmpty())
        args << QStringLiteral("--name") << name;
    m_cli->callJson(args, EngineTimeouts::Add, [this, path](const EngineCli::EngineResult &res) {
        if (!res.ok()) {
            emit addFinished(false, res.error.userMessage());
            return;
        }
        emit addFinished(true, QStringLiteral("已注册 %1").arg(path));
        refreshAll();
    });
}

void AppModel::scan(const QString &root, int depth)
{
    m_cli->callJson({ QStringLiteral("scan"), root, QStringLiteral("--depth"),
                         QString::number(depth), QStringLiteral("--json") },
        EngineTimeouts::Scan, [this](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value()) {
                emit scanFinished(false,
                    res.ok() ? QStringLiteral("引擎输出不是合法 JSON（契约可能过旧）")
                             : res.error.userMessage(),
                    QString());
                return;
            }
            const QJsonObject o = res.payload->object();
            const int added = o.value(QLatin1String("added")).toInt();
            const int found = o.value(QLatin1String("found")).toInt();
            const int existing = o.value(QLatin1String("existing")).toInt();
            QString msg = QStringLiteral("新增 %1 个 / 共发现 %2 个").arg(added).arg(found);
            if (existing > 0)
                msg += QStringLiteral("（已存在 %1 个跳过）").arg(existing);
            ScanCoverage::Input in;
            in.found = found;
            in.truncated = o.contains(QLatin1String("truncated"))
                ? o.value(QLatin1String("truncated")).toBool()
                : false;
            in.depthCapped = o.contains(QLatin1String("depthCapped"))
                ? o.value(QLatin1String("depthCapped")).toBool()
                : false;
            in.unreadable = o.value(QLatin1String("unreadable")).toArray().size();
            emit scanFinished(true, msg, ScanCoverage::note(in));
            refreshAll();
        });
}

// ── 里程碑写操作 ──

void AppModel::addMilestone(const QString &project, const QString &name, const QString &tag,
    const QString &date, const QString &desc)
{
    // 空 tag/date/desc **不发键**（引擎按键存在与否判定）
    QStringList args = { QStringLiteral("milestone"), QStringLiteral("add"), project, name };
    if (!tag.isEmpty())
        args << QStringLiteral("--tag") << tag;
    if (!date.isEmpty())
        args << QStringLiteral("--date") << date;
    if (!desc.isEmpty())
        args << QStringLiteral("--desc") << desc;
    args << QStringLiteral("--json");
    m_cli->callJson(args, EngineTimeouts::Milestones, [this, project, name](const EngineCli::EngineResult &res) {
        if (!res.ok()) {
            emit milestoneActionFinished(false, res.error.userMessage());
            return;
        }
        emit milestoneActionFinished(true, QStringLiteral("已创建里程碑「%1」").arg(name));
        reloadAfterWrite(project);
    });
}

void AppModel::setMilestoneStatus(const QString &project, const QString &name, const QString &action)
{
    m_cli->callJson({ QStringLiteral("milestone"), action, project, name, QStringLiteral("--json") },
        EngineTimeouts::Milestones, [this, project, name, action](const EngineCli::EngineResult &res) {
            // 载荷为 {project, milestone, requested, status, applied}（CONTRACT §3.8，无 message 键）。
            // status 是实际生效状态：达成时展示它，被压回（applied:false，如同名 tag 的
            // 自动达成规则）时也展示它——不许显示空原因。
            bool applied = true;
            QString status;
            if (res.ok() && res.payload.has_value()) {
                const QJsonObject o = res.payload->object();
                if (o.contains(QLatin1String("applied")))
                    applied = o.value(QLatin1String("applied")).toBool(true);
                if (o.contains(QLatin1String("status")))
                    status = o.value(QLatin1String("status")).toString();
            }
            if (!res.ok()) {
                emit milestoneActionFinished(false, res.error.userMessage());
                return;
            }
            emit milestoneActionFinished(true,
                applied ? QStringLiteral("%1「%2」，当前状态 %3")
                              .arg(milestoneActionLabel(action), name,
                                   status.isEmpty() ? QStringLiteral("未知") : status)
                        : QStringLiteral("引擎未应用该操作：「%1」实际状态仍为 %2（可能被同名 tag 的自动达成规则压回）")
                              .arg(name, status.isEmpty() ? QStringLiteral("未知") : status));
            reloadAfterWrite(project);
        });
}

void AppModel::removeMilestone(const QString &project, const QString &name)
{
    m_cli->callJson({ QStringLiteral("milestone"), QStringLiteral("remove"), project, name,
                         QStringLiteral("--json") },
        EngineTimeouts::Milestones, [this, project, name](const EngineCli::EngineResult &res) {
            if (!res.ok()) {
                emit milestoneActionFinished(false, res.error.userMessage());
                return;
            }
            emit milestoneActionFinished(true, QStringLiteral("已删除里程碑「%1」").arg(name));
            reloadAfterWrite(project);
        });
}

// ── 选择 / 筛选 ──

void AppModel::setSelection(Selection sel)
{
    if (m_selection == sel)
        return;
    m_selection = sel;
    emit selectionChanged(sel);
}

void AppModel::go(Selection sel)
{
    setSelection(sel);
    if (sel.kind == Selection::Kind::project)
        loadProject(sel.projectName);
}

void AppModel::setDashFilter(const DashFilter &f)
{
    m_dashFilter = f;
    emit dashFilterChanged();
}

void AppModel::clearLastError()
{
    m_lastError.clear();
    emit lastErrorChanged(QString());
}

void AppModel::setEngineResult(const EngineLocator::Result &engine)
{
    const bool foundChanged = m_engineFound != engine.found;
    m_engineFound = engine.found;
    m_enginePending = engine.pending;
    m_engineProblem = engine.problems.join(QStringLiteral("；"));
    // 把新发现的引擎二进制回灌给 CLI（M0-1）：只改 UI 文案而不改 bin 的话，
    // 「重新检测引擎」提示"已找到"后每次调用仍走 engineMissing → notFound，
    // 且上面的处理器又会把 m_engineFound 翻回 false → 用户必须重启应用。
    // found 时设 bin；未找到时清空 bin，让 both 状态（未发现/曾发现又丢失）统一由
    // engineMissing 处理器的 isEmpty 判定分流。
    if (m_cli)
        m_cli->setEngineBin(engine.found ? engine.bin : QString());
    if (foundChanged)
        emit engineFoundChanged();
}

// ── 派生查询 ──

const std::optional<ProjectStatus> AppModel::project(const QString &name) const
{
    for (const ProjectStatus &p : m_projects) {
        if (p.name == name)
            return p;
    }
    return std::nullopt;
}

int AppModel::pendingForScope(const UpdateScope &scope) const
{
    // pendingCommits 实时值按范围取（mac Scope.swift pending 对位）
    if (scope.kind == UpdateScopeKind::project) {
        const auto p = project(scope.name);
        if (!p.has_value())
            return 0;
        int sum = 0;
        for (const BranchStatus &b : p->branches)
            sum += qMax(0, b.pendingCommits);
        return sum;
    }
    int total = 0;
    for (const ProjectStatus &p : m_projects) {
        for (const BranchStatus &b : p.branches)
            total += qMax(0, b.pendingCommits);
    }
    return total;
}

AppModel::TrayState AppModel::trayState() const
{
    // menuTitle 规则（mac Model.swift:323-355）：「<N> ⚠︎<S>」/「<N> ●<D>」互斥、⚠︎ 优先
    TrayState st;
    if (!m_engineFound)
        return { QStringLiteral("？"), Liveness::unreadable };
    if (m_refreshing && m_projects.empty())
        return { QStringLiteral("⋯"), Liveness::unknown };
    if (!m_lastError.isEmpty() && m_projects.empty())
        return { QStringLiteral("！"), Liveness::unreadable };

    int stale = 0;
    int dirty = 0;
    if (m_summary.has_value()) {
        stale = m_summary->staleProjects;
        dirty = m_summary->dirtyProjects;
    } else {
        for (const ProjectStatus &p : m_projects) {
            if (p.userDirtyCount > 0)
                ++dirty;
            for (const BranchStatus &b : p.branches) {
                if (b.status == QLatin1String("stale")) {
                    ++stale;
                    break;
                }
            }
        }
    }
    QString title = QString::number(m_projects.size());
    Liveness tint = Liveness::recent;
    if (stale > 0) {
        title += QStringLiteral(" ⚠︎%1").arg(stale);
        tint = Liveness::engineStale;
    } else if (dirty > 0) {
        title += QStringLiteral(" ●%1").arg(dirty);
        tint = Liveness::needsAction;
    }
    return { title, tint };
}

// ── 通知（「新变差」才发）──

void AppModel::postNotificationsIfNeeded()
{
    // 通知文案三态照 SPEC §3.2；去重键：停滞按 (project,branch) 对、未提交按十位分桶。
    int newStaleCount = 0;
    for (const ProjectStatus &p : m_projects) {
        if (p.isUnreadable())
            continue;
        for (const BranchStatus &b : p.branches) {
            const QString key = QStringLiteral("%1/%2").arg(p.id.isEmpty() ? p.name : p.id, b.name);
            if (b.status == QLatin1String("stale") && !b.isDefault) {
                ++newStaleCount;
                if (!m_havePrevSnapshot || !m_seenStaleBranches.contains(key)) {
                    m_seenStaleBranches.insert(key);
                    m_notifier->notifyOnce(QStringLiteral("stale:%1").arg(key),
                        QStringLiteral("分支停滞：%1").arg(p.name),
                        QStringLiteral("「%1」 已 %2 无提交，考虑合并或关闭")
                            .arg(b.name, b.headAgo.isEmpty() ? QStringLiteral("一段时间") : b.headAgo));
                }
            } else {
                m_seenStaleBranches.remove(key);
            }
        }
        // 未提交过多：userDirtyCount >= 10，按十位分桶去重
        if (p.userDirtyCount >= 10) {
            const int bucket = p.userDirtyCount / 10;
            m_notifier->notifyOnce(QStringLiteral("dirty:%1:%2").arg(p.name).arg(bucket),
                QStringLiteral("未提交改动较多：%1").arg(p.name),
                QStringLiteral("%1 处改动未提交").arg(p.userDirtyCount));
        }
    }
    m_havePrevSnapshot = true;
    Q_UNUSED(newStaleCount);
}
