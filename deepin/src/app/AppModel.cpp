#include "AppModel.h"
#include "../ai/AIConfig.h"
#include "../ai/AIEngine.h"
#include "../ai/AIEngineFactory.h"
#include "../ai/AiDigests.h"
#include "../ai/SecretStore.h"
#include "../logic/Derived.h"
#include "../logic/EngineDownload.h"
#include "../logic/EngineHook.h"
#include "../logic/SnapshotFixture.h"
#include "../logic/PatchCheck.h"
#include "../logic/ScanCoverage.h"
#include "../logic/StopDecision.h"
#include "../logic/UpdateOutcome.h"
#include "EngineInstaller.h"
#include "Notifier.h"
#include "Settings.h"
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QMetaObject>
#include <QPointer>
#include <QProcess>
#include <QTemporaryDir>
#include <QThreadPool>
#include <QTimer>
#include <algorithm>

#include "AppModelInternal.h"

using AppModelInternal::kQuiet;
using AppModelInternal::loadAiConfigWithFallbackKey;
using AppModelInternal::loadAiKeyInWorker;
using AppModelInternal::sortProjects;


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
    , m_installer(new EngineInstaller(this))
{
    connect(m_installer, &EngineInstaller::finished, this,
        [this](const EngineInstaller::Result &r) {
            m_engineDownloading = false;
            m_engineDownloadMessage = r.message;
            emit engineDownloadingChanged();
            if (!r.ok) {
                emit engineDownloadFinished(false, r.message);
                return;
            }
            // 装好了 → **立刻**重跑发现链：装到 ~/.local/libexec/deepdolphin/moongit 的引擎
            // 是发现链的候选之一，不重跑的话用户还得自己重启应用才认得出引擎。
            EngineLocator::Result pending;
            pending.pending = true;
            setEngineResult(pending);
            EngineLocator::locateAsync([this, r](const EngineLocator::Result &found) {
                setEngineResult(found);
                QString msg = r.message;
                if (found.found)
                    msg += QStringLiteral("；已可使用");
                else
                    msg += QStringLiteral("；⚠ 装好了，但发现链仍没找到它 —— 请检查安装位置与权限");
                m_engineDownloadMessage = msg;
                // ⚠ 只发**一次**收尾信号（下载完成 + 复检合并成一条结论）。
                emit engineDownloadFinished(true, msg);
            });
        });
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
                AIConfig identity = loadAiConfigWithFallbackKey(); // Settings 只在 GUI 线程读（M0-4）
                QThreadPool::globalInstance()->start([this, guard, engineBin, doneBody, identity] {
                    AIConfig cfg = identity;
                    loadAiKeyInWorker(&cfg);
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
            if (!res.payload.has_value() || !applyStatusPayload(*res.payload, true)) {
                onDone(false);
                return;
            }
            onDone(true);
        });
}

// ── 载荷应用（批 T：取数与判定分层）────────────────────────────
//   引擎取数与夹具注入**共用**这三个函数 —— 夹具走的就是真实解析路径，
//   所以面板快照顺带覆盖契约解析，而不只是「摆一堆好看的字」。
bool AppModel::applyStatusPayload(const QJsonDocument &doc, bool checkPaths)
{
    const auto env = StatusEnvelope::decodeEnvelopeOrBare(doc);
    if (!env.has_value()) {
        m_lastError = QStringLiteral("引擎输出不是合法的项目状态（契约可能过旧）");
        emit lastErrorChanged(m_lastError);
        return false;
    }
    // TCC 预检的 Linux 等价物（PLAN §8 T6）：首个项目路径可读性预检
    // ⚠ 夹具模式跳过（checkPaths=false）—— 夹具项目是假的，路径本就不存在；
    //   预检是「真实项目路径不可读」的事，夹具没有这个语义。
    if (checkPaths) {
        for (const ProjectStatus &p : env->projects) {
            if (!p.isUnreadable() && !p.path.isEmpty() && !QFileInfo::exists(p.path)) {
                m_lastError = QStringLiteral("%1：路径不存在或卷未挂载（%2）")
                                  .arg(p.name, p.path);
                emit lastErrorChanged(m_lastError);
                break;
            }
        }
    }
    m_projects = env->projects;
    sortProjects(m_projects);
    m_summary = env->summary;
    m_hasLoadedProjectsOnce = true; // 成功才置位（pendingRoute 在此处补判）
    emit projectsChanged();
    return true;
}

bool AppModel::applyDashboardPayload(const QJsonDocument &doc)
{
    const auto d = DashboardData::fromJson(doc.object());
    if (!d.has_value()) {
        m_dashboardState = { LoadState::failed,
            QStringLiteral("仪表盘载荷缺键（契约可能过旧）") };
        emit dashboardChanged();
        return false;
    }
    m_dashboard = d;
    m_dashboardState = { LoadState::loaded, QString() };
    emit dashboardChanged();
    return true;
}

bool AppModel::applyMilestonesPayload(const QJsonDocument &doc)
{
    const auto e = MilestonesEnvelope::fromJson(doc.object());
    if (!e.has_value()) {
        m_milestonesState = { LoadState::failed,
            QStringLiteral("里程碑载荷缺键（契约可能过旧）") };
        emit milestonesChanged();
        return false;
    }
    applyMilestoneLoadRules(*e);
    return true;
}

void AppModel::useSnapshotFixture()
{
    // 夹具 = 判定层产出的固定 JSON。
    // ⚠ 走**同一段解析路径**（applyStatusPayload / applyDashboardPayload /
    //   applyMilestonesPayload）⇒ 顺带覆盖契约解析。
    // ⚠ 夹具的时间戳**分两类**：会被算天数的 `lastCommitAt` 跟真实 now 走（天数恒定），
    //   只会被显示成绝对字符串的锚定基准日（绝对日期不随日子变）—— 详见 SnapshotFixture.h。
    applyStatusPayload(QJsonDocument::fromJson(SnapshotFixture::statusJson()), false);
    applyDashboardPayload(QJsonDocument::fromJson(SnapshotFixture::dashboardJson()));
    applyMilestonesPayload(QJsonDocument::fromJson(SnapshotFixture::milestonesJson()));
    // ⚠ **不许用墙钟**（批 T）：侧栏渲染「空闲 · 上次刷新 HH:mm」，用墙钟就意味着
    //   基线每分钟变一次、换台机器（时区不同）也变 ⇒ CI 天天有 diff ⇒ 人就学会
    //   忽略 diff ⇒ 基线又变成空门。固定时刻 + 快照进程固定 TZ=UTC ⇒ 逐字节可重现。
    m_lastRefreshedMs = SnapshotFixture::fixedRefreshedMs();
    emit refreshCycleFinished(true);
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
            // 解析与应用走**同一段**（批 T：夹具与引擎共用，避免两份解析逻辑）
            if (!applyDashboardPayload(*res.payload)) {
                fetchMilestones();
                return;
            }
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
            if (!applyMilestonesPayload(*res.payload)) {
                m_lastRefreshedMs = QDateTime::currentMSecsSinceEpoch();
                postNotificationsIfNeeded();
                leaveRefresh();
                emit refreshCycleFinished(false);
                emit refreshAllFinished(false);
                return;
            }
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

// 文档完整性校验：引擎 `verify <name> --json`。
// 只读命令 —— 客户端不写任何用户数据，校验口径全部来自引擎（VERIFY 契约）。
void AppModel::loadVerify(const QString &name)
{
    m_verifyStates[name] = { LoadState::loading, QString() };
    emit verifyChanged(name);
    m_cli->callJson({ QStringLiteral("verify"), name, QStringLiteral("--json") },
        EngineTimeouts::Verify, [this, name](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value()) {
                m_verifyStates[name] = { LoadState::failed,
                    res.ok() ? QStringLiteral("引擎输出不是合法 JSON（契约可能过旧）")
                             : res.error.userMessage() };
                emit verifyChanged(name);
                return;
            }
            const auto e = VerifyEnvelope::fromJson(res.payload->object());
            if (!e.has_value()) {
                m_verifyStates[name] = { LoadState::failed,
                    QStringLiteral("verify 载荷缺键（契约可能过旧）") };
                emit verifyChanged(name);
                return;
            }
            m_verifies[name] = *e;
            m_verifyStates[name] = { LoadState::loaded, QString() };
            emit verifyChanged(name);
        });
}

// 架构图场景：引擎 `graph arch <name> --format scene`（moongit-graph-scene v1）。
// 只读命令 —— 不写用户数据；场景数据由引擎确定性生成，客户端只负责画。
void AppModel::loadScene(const QString &name)
{
    m_sceneStates[name] = { LoadState::loading, QString() };
    emit sceneChanged(name);
    m_cli->callJson({ QStringLiteral("graph"), QStringLiteral("arch"), name,
                        QStringLiteral("--format"), QStringLiteral("scene") },
        EngineTimeouts::Graph, [this, name](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value()) {
                m_sceneStates[name] = { LoadState::failed,
                    res.ok() ? QStringLiteral("引擎输出不是合法 JSON（契约可能过旧）")
                             : res.error.userMessage() };
                emit sceneChanged(name);
                return;
            }
            const auto s = GraphScene::fromJson(res.payload->object());
            if (!s.has_value()) {
                m_sceneStates[name] = { LoadState::failed,
                    QStringLiteral("场景契约不认识（版本不对或缺键）") };
                emit sceneChanged(name);
                return;
            }
            m_scenes[name] = *s;
            m_sceneStates[name] = { LoadState::loaded, QString() };
            emit sceneChanged(name);
        });
}

// 架构图生成：引擎 `arch gen <name>`。**经引擎写**（客户端不直接碰项目文件）——
// 章程 C11「客户端永远只经引擎写文档」在这里同样成立。
// 回执型命令 → 走 Text 契约（引擎 stdout 是人话回执，不是 JSON）。
void AppModel::genArch(const QString &name)
{
    m_cli->callText({ QStringLiteral("arch"), QStringLiteral("gen"), name },
        EngineTimeouts::Graph, [this, name](const EngineCli::EngineResult &res) {
            emit archActionFinished(res.ok(), name,
                res.ok() ? res.receipt : res.error.userMessage());
        });
}

// 架构图导出：引擎 `render arch <name>`（落盘单文件 HTML —— 引擎层交付物，
// 不是本平台的渲染路径：章程 §3.5「平台渲染零外包」说的是运行时渲染）。
void AppModel::exportArch(const QString &name)
{
    m_cli->callText({ QStringLiteral("render"), QStringLiteral("arch"), name },
        EngineTimeouts::Graph, [this, name](const EngineCli::EngineResult &res) {
            emit archActionFinished(res.ok(), name,
                res.ok() ? res.receipt : res.error.userMessage());
        });
}

// 代码图谱：引擎三源（graph tree / confidence / functions）→ 一棵树。
// 三个命令**并行**取（互不依赖），合成的规则在 logic/CodeGraphBuild（纯函数层）。
void AppModel::loadCodeGraph(const QString &name)
{
    m_codeGraphStates[name] = { LoadState::loading, QString() };
    emit codeGraphChanged(name);

    auto tree = std::make_shared<QJsonObject>();
    auto conf = std::make_shared<QJsonObject>();
    auto fns = std::make_shared<QJsonObject>();
    auto errs = std::make_shared<QStringList>();
    auto done = std::make_shared<int>(0);

    // 三源齐了才合成 —— 少一源就说清缺哪一源（合成器会点名）。
    const auto finish = [this, name, tree, conf, fns, errs, done]() {
        if (*done < 3)
            return;
        if (!errs->isEmpty()) {
            m_codeGraphStates[name] = { LoadState::failed, errs->join(QStringLiteral("；")) };
            emit codeGraphChanged(name);
            return;
        }
        CodeGraphBuild::Source src;
        src.tree = *tree;
        src.confidence = *conf;
        src.functions = *fns;
        const CodeGraphBuild::Result r = CodeGraphBuild::build(src, name);
        if (!r.ok) {
            m_codeGraphStates[name] = { LoadState::failed, r.error };
            emit codeGraphChanged(name);
            return;
        }
        m_codeGraphs[name] = r;
        m_codeGraphStates[name] = { LoadState::loaded, QString() };
        emit codeGraphChanged(name);
    };

    const auto grab = [this, name, done, errs, finish](const QString &label,
                        std::shared_ptr<QJsonObject> slot, const QStringList &args) {
        m_cli->callJson(args, EngineTimeouts::Graph,
            [name, label, done, errs, finish, slot](const EngineCli::EngineResult &res) {
                if (!res.ok() || !res.payload.has_value() || !res.payload->isObject()) {
                    errs->append(QStringLiteral("%1：%2")
                                     .arg(label,
                                         res.ok() ? QStringLiteral("输出不是 JSON 对象")
                                                  : res.error.userMessage()));
                } else {
                    *slot = res.payload->object();
                }
                *done += 1;
                finish();
            });
    };

    grab(QStringLiteral("图树"), tree,
        { QStringLiteral("graph"), QStringLiteral("tree"), name, QStringLiteral("--depth"),
            QStringLiteral("8"), QStringLiteral("--json") });
    grab(QStringLiteral("置信度"), conf,
        { QStringLiteral("graph"), QStringLiteral("confidence"), name,
            QStringLiteral("--json") });
    grab(QStringLiteral("函数级图谱"), fns,
        { QStringLiteral("graph"), QStringLiteral("functions"), name,
            QStringLiteral("--json") });
}

// 生成索引 + 置信度：引擎 index gen --stats + confidence gen（写库/落盘）。
// 两个都是**回执型**命令（stdout 是人话）→ 走 Text 契约。
void AppModel::genIndex(const QString &name)
{
    m_cli->callText({ QStringLiteral("index"), QStringLiteral("gen"), name,
                        QStringLiteral("--stats") },
        EngineTimeouts::Deep, [this, name](const EngineCli::EngineResult &res) {
            if (!res.ok()) {
                emit archActionFinished(false, name, res.error.userMessage());
                return;
            }
            const QString first = res.receipt;
            // 索引生成完还要算置信度（`confidence gen` 才是最终结论，回执取它）
            m_cli->callText({ QStringLiteral("confidence"), QStringLiteral("gen"), name },
                EngineTimeouts::Deep, [this, name, first](const EngineCli::EngineResult &r2) {
                    if (!r2.ok()) {
                        emit archActionFinished(false, name, r2.error.userMessage());
                        return;
                    }
                    emit archActionFinished(true, name, r2.receipt.isEmpty()
                        ? first : r2.receipt);
                    loadCodeGraph(name); // 数据全换了 → 重载
                });
        });
}

// 导出交互 HTML：引擎 render index --confidence（落盘单文件 HTML —— 引擎层交付物）。
void AppModel::exportIndex(const QString &name)
{
    m_cli->callText({ QStringLiteral("render"), QStringLiteral("index"), name,
                        QStringLiteral("--confidence") },
        EngineTimeouts::Deep, [this, name](const EngineCli::EngineResult &res) {
            emit archActionFinished(res.ok(), name, res.ok() ? res.receipt
                                                             : res.error.userMessage());
        });
}

// 代码图谱页的回执与架构图页共用一个信号（都是「引擎跑完给一句话」）。

// ── 补丁体检（引擎 graph patchconf 三层）──

QString AppModel::workingDiff(const QString &name, QString *error) const
{
    // 找项目的绝对路径（引擎 status 的 projects[].path）
    QString path;
    for (const ProjectStatus &p : m_projects) {
        if (p.name == name) {
            path = p.path;
            break;
        }
    }
    if (path.isEmpty()) {
        if (error)
            *error = QStringLiteral("找不到项目 %1 的本地路径（补丁体检要读它的工作区）").arg(name);
        return QString();
    }
    // 只读 `git diff HEAD` —— 不写、不动仓库。
    QProcess proc;
    proc.start(QStringLiteral("git"), { QStringLiteral("-C"), path, QStringLiteral("diff"),
        QStringLiteral("HEAD") });
    if (!proc.waitForStarted(5000)) {
        if (error)
            *error = QStringLiteral("git 启动失败（补丁体检读不到工作区改动）");
        return QString();
    }
    if (!proc.waitForFinished(30000)) {
        proc.kill();
        proc.waitForFinished(2000);
        if (error)
            *error = QStringLiteral("git diff 超时（工作区可能太大）");
        return QString();
    }
    const QByteArray out = proc.readAllStandardOutput();
    if (proc.exitCode() != 0) {
        if (error)
            *error = QStringLiteral("git diff 失败：%1")
                         .arg(QString::fromUtf8(proc.readAllStandardError()).trimmed());
        return QString();
    }
    return QString::fromUtf8(out);
}

void AppModel::loadPatchCheck(const QString &name)
{
    m_patchStates[name] = { LoadState::loading, QString() };
    emit patchCheckChanged(name);

    QString err;
    const QString diff = workingDiff(name, &err);
    if (!err.isEmpty()) {
        m_patchStates[name] = { LoadState::failed, err };
        emit patchCheckChanged(name);
        return;
    }
    if (diff.trimmed().isEmpty()) {
        m_patchStates[name] = { LoadState::failed,
            QStringLiteral("工作区没有未提交改动（补丁体检没有输入）") };
        emit patchCheckChanged(name);
        return;
    }

    // 引擎的 --patch 吃**文件路径**（不是 diff 正文）—— 落盘在 app 层做，
    // 判定层只管解析结果。临时目录随 QTemporaryDir 析构自动清。
    QTemporaryDir tmpDir;
    if (!tmpDir.isValid()) {
        m_patchStates[name] = { LoadState::failed, QStringLiteral("临时目录建不起来，补丁体检未执行") };
        emit patchCheckChanged(name);
        return;
    }
    const QString diffPath = tmpDir.filePath(QStringLiteral("patch.diff"));
    {
        QFile f(diffPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            m_patchStates[name] = { LoadState::failed, QStringLiteral("临时 diff 写不下去，补丁体检未执行") };
            emit patchCheckChanged(name);
            return;
        }
        f.write(diff.toUtf8());
    }
    m_cli->callJson({ QStringLiteral("graph"), QStringLiteral("patchconf"), name,
                        QStringLiteral("--patch"), diffPath, QStringLiteral("--json") },
        EngineTimeouts::Graph, [this, name](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value() || !res.payload->isObject()) {
                m_patchStates[name] = { LoadState::failed,
                    res.ok() ? QStringLiteral("补丁体检输出不是 JSON 对象")
                             : res.error.userMessage() };
                emit patchCheckChanged(name);
                return;
            }
            const PatchLayer1 layer = PatchCheck::parseLayer1(res.payload->object());
            if (!layer.ok) {
                m_patchStates[name] = { LoadState::failed, layer.error };
                emit patchCheckChanged(name);
                return;
            }
            m_patchLayers[name] = layer;
            // 原始载荷留着：合并终稿时**原样回写**（丢了就拼不出正确的终稿）。
            m_patchRawPayload[name] = res.payload->object();
            m_patchStates[name] = { LoadState::loaded, QString() };
            emit patchCheckChanged(name);
        });
}

void AppModel::mergePatchCheck(const QString &name, const QJsonObject &agentPayload)
{
    const PatchLayer1 *layer = patchFor(name);
    if (!layer) {
        m_patchStates[name] = { LoadState::failed, QStringLiteral("还没有算法层结果，没法合并终稿") };
        emit patchCheckChanged(name);
        return;
    }
    // 引擎的 --merge 吃两个**文件路径**（算法结果 + 裁决）—— 落盘在 app 层做。
    QTemporaryDir tmpDir;
    if (!tmpDir.isValid()) {
        m_patchStates[name] = { LoadState::failed, QStringLiteral("临时目录建不起来，合并终稿未执行") };
        emit patchCheckChanged(name);
        return;
    }
    const QString algPath = tmpDir.filePath(QStringLiteral("algorithm.json"));
    const QString agentPath = tmpDir.filePath(QStringLiteral("agent.json"));
    {
        // ⚠ 算法结果**原样回写**引擎给的那份载荷（mac 同款）——
        //   自己拼一个精简版会把 entities/uncertain/signals 丢掉，
        //   合并出来的终稿就没有实体了。
        QFile f(algPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            m_patchStates[name] = { LoadState::failed, QStringLiteral("算法结果落盘失败，合并终稿未执行") };
            emit patchCheckChanged(name);
            return;
        }
        const QJsonObject &raw = m_patchRawPayload.value(name);
        if (raw.isEmpty()) {
            m_patchStates[name] = { LoadState::failed, QStringLiteral("算法层原始载荷丢了，合并终稿未执行") };
            emit patchCheckChanged(name);
            return;
        }
        f.write(QJsonDocument(raw).toJson(QJsonDocument::Indented));
    }
    {
        QFile f(agentPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            m_patchStates[name] = { LoadState::failed, QStringLiteral("裁决落盘失败，合并终稿未执行") };
            emit patchCheckChanged(name);
            return;
        }
        f.write(QJsonDocument(agentPayload).toJson(QJsonDocument::Indented));
    }
    m_cli->callJson({ QStringLiteral("graph"), QStringLiteral("patchconf"),
                        QStringLiteral("--merge"), algPath, agentPath, QStringLiteral("--json") },
        EngineTimeouts::Graph, [this, name](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value() || !res.payload->isObject()) {
                m_patchStates[name] = { LoadState::failed,
                    res.ok() ? QStringLiteral("合并终稿输出不是 JSON 对象")
                             : res.error.userMessage() };
                emit patchCheckChanged(name);
                return;
            }
            const PatchMerged merged = PatchCheck::parseMerged(res.payload->object());
            if (!merged.ok) {
                m_patchStates[name] = { LoadState::failed, merged.error };
                emit patchCheckChanged(name);
                return;
            }
            m_patchMerged[name] = merged;
            m_patchStates[name] = { LoadState::loaded, QString() };
            emit patchMerged(name);
            emit patchCheckChanged(name);
        });
}

// ── 引擎自检（doctor）与进度报告（report）──

void AppModel::runDoctor()
{
    m_cli->callJson({ QStringLiteral("doctor"), QStringLiteral("--json") },
        EngineTimeouts::Status, [this](const EngineCli::EngineResult &res) {
            // ⚠ 引擎 doctor 在**发现问题时退出码是 1**，但 stdout 仍是合法 JSON。
            //   那是「环境有问题」，不是「命令崩了」—— 所以先看载荷有没有解析出来，
            //   解析出来了就是一份**有效报告**（问题数由报告自己说）。
            if (res.payload.has_value() && res.payload->isObject()) {
                const EngineDoctor::Report r = EngineDoctor::parse(res.payload->object());
                if (r.ok) {
                    m_doctor = r;
                    emit doctorFinished(r);
                    return;
                }
                m_doctor = r;
                emit doctorFinished(r);
                return;
            }
            EngineDoctor::Report bad;
            bad.ok = false;
            bad.error = res.ok() ? QStringLiteral("引擎自检输出不是 JSON 对象")
                                  : res.error.userMessage();
            m_doctor = bad;
            emit doctorFinished(bad);
        });
}

void AppModel::exportReport(const QString &name)
{
    // 回执型命令：stdout 是人话（"报告已生成：<路径>（N 个项目）"），
    // 走 Text 契约；路径从回执里抽（ArchReceipt::filePath 的 .md 特例）。
    // ⚠ 回执走**独立信号**：archActionFinished 是架构图窗在收的，混流会让
    //   架构图窗显示报告的回执，还可能被当成「架构已生成」而重载画布。
    m_cli->callText({ QStringLiteral("report"), name },
        EngineTimeouts::Deep, [this, name](const EngineCli::EngineResult &res) {
            emit reportExported(res.ok(), name, res.ok() ? res.receipt
                                                         : res.error.userMessage());
        });
}

// ── 持久化代码索引的状态（index overview / index update）──

void AppModel::loadIndexOverview(const QString &name)
{
    m_indexStates[name] = { LoadState::loading, QString() };
    emit indexStatusChanged(name);
    m_cli->callJson({ QStringLiteral("index"), QStringLiteral("overview"), name,
                        QStringLiteral("--json") },
        EngineTimeouts::Graph, [this, name](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value() || !res.payload->isObject()) {
                m_indexStates[name] = { LoadState::failed,
                    res.ok() ? QStringLiteral("索引状态输出不是 JSON 对象")
                             : res.error.userMessage() };
                emit indexStatusChanged(name);
                return;
            }
            const IndexStatus::Overview ov = IndexStatus::parseOverview(res.payload->object());
            if (!ov.ok) {
                m_indexStates[name] = { LoadState::failed, ov.error };
                emit indexStatusChanged(name);
                return;
            }
            m_indexOverviews[name] = ov;
            m_indexStates[name] = { LoadState::loaded, QString() };
            emit indexStatusChanged(name);
        });
}

void AppModel::updateIndex(const QString &name)
{
    // 走 **Json 契约**：`index update --json` 给的是结构化结果
    // （fresh / rebuilt / updateCount / indexJson 落盘路径），
    // 人话形态只有一句「已最新——首版（第 0 版）」，拿不到这些。
    m_cli->callJson({ QStringLiteral("index"), QStringLiteral("update"), name,
                        QStringLiteral("--json") },
        EngineTimeouts::Deep, [this, name](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value() || !res.payload->isObject()) {
                emit indexUpdated(name, false,
                    res.ok() ? QStringLiteral("索引更新输出不是 JSON 对象")
                             : res.error.userMessage());
                return;
            }
            const IndexStatus::UpdateResult u = IndexStatus::parseUpdate(res.payload->object());
            if (!u.ok) {
                emit indexUpdated(name, false, u.error);
                return;
            }
            // ⚠ 「已最新」≠「已更新」：源文件没动时引擎回 fresh: true，
            //   这次**什么都没重建** —— 界面要说清，不能说成「更新好了」。
            QString text;
            if (u.fresh)
                text = QStringLiteral("源文件没动，索引已是最新（第 %1 代）")
                           .arg(u.updateCount >= 0 ? QString::number(u.updateCount)
                                                   : QStringLiteral("?"));
            else if (u.rebuilt)
                text = QStringLiteral("索引已重建（第 %1 代）%2")
                           .arg(u.updateCount >= 0 ? QString::number(u.updateCount)
                                                   : QStringLiteral("?"),
                               u.indexJsonPath);
            else
                text = QStringLiteral("索引已更新（第 %1 代）")
                           .arg(u.updateCount >= 0 ? QString::number(u.updateCount)
                                                   : QStringLiteral("?"));
            // 索引内容变了 → 重新读索引状态，并重载代码图谱（数据换了）
            loadIndexOverview(name);
            if (!u.fresh)
                loadCodeGraph(name);
            emit indexUpdated(name, true, text);
        });
}

// ── 引擎配置（config list / config set）──

void AppModel::loadEngineConfig()
{
    m_engineConfigState = { LoadState::loading, QString() };
    emit engineConfigChanged();
    // `config list --json` 是 **Json 契约**（stdout 是一份 JSON 对象）。
    m_cli->callJson({ QStringLiteral("config"), QStringLiteral("list"),
                        QStringLiteral("--json") },
        EngineTimeouts::Status, [this](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value() || !res.payload->isObject()) {
                m_engineConfigState = { LoadState::failed,
                    res.ok() ? QStringLiteral("引擎配置输出不是 JSON 对象")
                             : res.error.userMessage() };
                emit engineConfigChanged();
                return;
            }
            const EngineConfig::Config c = EngineConfig::parse(res.payload->object());
            if (!c.ok) {
                m_engineConfigState = { LoadState::failed, c.error };
                emit engineConfigChanged();
                return;
            }
            m_engineConfig = c;
            m_engineConfigState = { LoadState::loaded, QString() };
            emit engineConfigChanged();
        });
}

void AppModel::setEngineConfig(const QString &key, const QString &value)
{
    // 键白名单在客户端也卡一道：引擎对未知键会报错，但那是**事后**；
    // 客户端先拦一道，界面就不会给用户一个必然失败的键。
    if (!EngineConfig::isWritable(key)) {
        emit engineConfigSaved(false, QStringLiteral("引擎不认这个配置键：%1").arg(key));
        return;
    }
    // ⚠ 回执型命令，**回执在 stderr**（实测 2026-10-19：`config set` 与 `report` 同款）。
    //   走 Text 契约（callText），回执由 EngineCli::receiptText 两路兜底取回。
    m_cli->callText({ QStringLiteral("config"), QStringLiteral("set"), key, value },
        EngineTimeouts::Status, [this, key](const EngineCli::EngineResult &res) {
            if (!res.ok()) {
                emit engineConfigSaved(false, res.error.userMessage());
                return;
            }
            // 写完重读 —— 界面显示的必须是**引擎当前真的在用的值**，
            // 不是客户端刚发过去的值（引擎可能做了钳制或改写）。
            loadEngineConfig();
            emit engineConfigSaved(true, res.receipt);
        });
}

// ── 图谱三件套（引擎 graph overview / symbol / impact）──


    // ── 图谱/索引/概览/符号/影响：见 AppModelGraph.cpp（批 AL 拆分）──
    // ── 更新/批量/git 操作/扫描/里程碑写入：见 AppModelUpdate.cpp（批 AL 拆分）──
