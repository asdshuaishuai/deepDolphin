#include "ProcessRegistry.h"
#include <QProcess>

ProcessRegistry::ProcessRegistry(QObject *parent)
    : QObject(parent)
{
}

void ProcessRegistry::registerProcess(QProcess *proc, const QString &cmdTag)
{
    if (!proc)
        return;
    Entry e;
    e.proc = proc;
    e.cmdTag = cmdTag;
    connect(proc, &QProcess::finished, this, [this, proc] { onProcessFinished(proc); });
    connect(proc, &QProcess::errorOccurred, this, [this, proc](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart || error == QProcess::Crashed)
            onProcessFinished(proc);
    });
    // QProcess 析构（deleteLater）也要清表
    connect(proc, &QObject::destroyed, this, [this, proc] { onProcessFinished(proc); });
    m_procs.push_back(std::move(e));
}

void ProcessRegistry::onProcessFinished(const QProcess *proc)
{
    QString tag;
    bool removed = false;
    for (auto it = m_procs.begin(); it != m_procs.end();) {
        if (it->proc == proc) {
            tag = it->cmdTag;
            if (it->killTimer) {
                it->killTimer->stop();
                it->killTimer->deleteLater();
            }
            it = m_procs.erase(it);
            removed = true;
        } else {
            ++it;
        }
    }
    if (!removed)
        return;
    // userStopped 清除延后一拍：本表的 finished/Crashed 槽连接在先（registerProcess），
    // EngineCli 的收尾槽连接在后——同一次 finished 派发里它还要读 wasUserStopped；
    // 在这里立刻清掉它读到的恒为 false，「被停」就被误报成「引擎进程异常退出」。
    // 下一圈事件循环再清：GUI 动作（用户再按停止）必然排在它之后，无误清窗口。
    QTimer::singleShot(0, this, [this, proc] { m_userStopped.remove(proc); });
    // 该标签已无在跑进程 → allFinished
    if (!anyRunning({ tag }))
        emit allFinished(tag);
}

int ProcessRegistry::terminateRunning(const QStringList &onlyCommands)
{
    std::vector<QProcess *> targets;
    for (const Entry &e : m_procs) {
        if (e.proc.isNull())
            continue;
        const bool match = onlyCommands.isEmpty()
            || std::any_of(onlyCommands.cbegin(), onlyCommands.cend(),
                   [&](const QString &prefix) { return e.cmdTag.startsWith(prefix); });
        if (!match)
            continue;
        m_userStopped.insert(e.proc.data());
        targets.push_back(e.proc.data());
    }
    int n = 0;
    for (QProcess *p : targets) {
        if (p->state() == QProcess::NotRunning)
            continue;
        p->terminate(); // SIGTERM：引擎有机会正常收尾
        ++n;
        // 2s 后仍活着 → 升级 SIGKILL；定时器挂自身存活期，随 Entry 清理
        auto *timer = new QTimer(p);
        timer->setSingleShot(true);
        connect(timer, &QTimer::timeout, p, [p] {
            if (p->state() != QProcess::NotRunning)
                p->kill();
        });
        timer->start(2000);
        for (Entry &e : m_procs) {
            if (e.proc == p)
                e.killTimer = timer;
        }
    }
    return n;
}

bool ProcessRegistry::anyRunning(const QStringList &cmdTags) const
{
    for (const Entry &e : m_procs) {
        if (e.proc.isNull())
            continue;
        if (e.proc->state() == QProcess::NotRunning)
            continue;
        if (cmdTags.isEmpty())
            return true;
        for (const QString &tag : cmdTags) {
            if (e.cmdTag.startsWith(tag))
                return true;
        }
    }
    return false;
}

bool ProcessRegistry::wasUserStopped(const QProcess *proc) const
{
    return m_userStopped.contains(proc);
}

int ProcessRegistry::count() const
{
    int n = 0;
    for (const Entry &e : m_procs) {
        if (!e.proc.isNull() && e.proc->state() != QProcess::NotRunning)
            ++n;
    }
    return n;
}
