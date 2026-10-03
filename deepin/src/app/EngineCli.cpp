#include "EngineCli.h"
#include <DLog>
#include <QElapsedTimer>
#include <QJsonParseError>
#include <QProcess>
#include <QProcessEnvironment>
#include <QTimer>
#include <algorithm>
#include <memory>

DCORE_USE_NAMESPACE

namespace {
// stdout/stderr 统一按 UTF-8 lossy 解码（超时/残缺输出不崩、不当合法 JSON）
QString lossy(const QByteArray &raw)
{
    return QString::fromUtf8(raw);
}

bool parseObject(const QByteArray &raw, QJsonDocument *out)
{
    QJsonParseError err{};
    QJsonDocument doc = QJsonDocument::fromJson(raw, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return false;
    *out = doc;
    return true;
}

EngineCli::EngineResult classifyResult(QProcess *proc, const QStringList &args, bool timedOut, bool userStopped)
{
    EngineCli::EngineResult r;
    const QString cmdLabel = args.value(0, QStringLiteral("引擎命令"));
    if (timedOut) {
        // 超时文案由调用方按实际预算秒数覆盖（classify 拿不到 timeoutMs）
        r.timedOut = true;
        r.error = EngineError::makeFailed(QStringLiteral("引擎调用超时。"));
        return r;
    }
    r.exitCode = proc->exitCode();
    r.stdOut = lossy(proc->readAllStandardOutput());
    r.stdErr = lossy(proc->readAllStandardError());

    if (userStopped) {
        r.cancelled = true;
        r.error = EngineError::makeCancelled(cmdLabel);
        return r;
    }

    QJsonDocument payload;
    const bool stdoutIsJson = parseObject(r.stdOut.toUtf8(), &payload);

    if (proc->exitStatus() != QProcess::NormalExit) {
        r.error = EngineError::makeFailed(QStringLiteral("引擎进程异常退出（%1）")
                                              .arg(cmdLabel));
        return r;
    }

    if (r.exitCode == 0) {
        if (stdoutIsJson) {
            r.payload = payload;
            return r; // 成功
        }
        // 空 stdout 是契约破坏，不是合法空态（CONTRACT §0）
        r.error = EngineError::makeFailed(
            QStringLiteral("引擎输出不是合法 JSON（命令 %1，退出码 0）。"
                           "可能引擎版本与客户端契约不匹配，请升级引擎。")
                .arg(cmdLabel));
        return r;
    }

    // exit≠0：stdout 可解析 → failedWithPayload，载荷保留（CONTRACT §4.3）
    if (stdoutIsJson) {
        r.payload = payload;
        QString note = QStringLiteral("引擎退出码 %1").arg(r.exitCode);
        if (!r.stdErr.trimmed().isEmpty())
            note += QStringLiteral("\n") + r.stdErr.trimmed();
        r.error = EngineError::makeFailedWithPayload(note, payload);
        return r;
    }
    // stdout 非 JSON：stdout 是主因，stderr 是补充（usage 类失败真因在 stdout）
    QStringList parts;
    const QString out = r.stdOut.trimmed();
    const QString err = r.stdErr.trimmed();
    if (!out.isEmpty())
        parts << out;
    if (!err.isEmpty())
        parts << err;
    if (parts.isEmpty())
        parts << QStringLiteral("引擎退出码 %1").arg(r.exitCode);
    r.error = EngineError::makeFailed(parts.join(QLatin1Char('\n')));
    return r;
}
} // namespace

EngineCli::EngineCli(QObject *parent)
    : QObject(parent)
{
}

void EngineCli::setEngineBin(const QString &bin)
{
    m_bin = bin;
}

int EngineCli::stopUpdates()
{
    return m_registry.terminateRunning({ QStringLiteral("update"), QStringLiteral("deep") });
}

void EngineCli::callJson(const QStringList &args, int timeoutMs,
                         std::function<void(const EngineResult &)> onDone)
{
    if (m_bin.isEmpty()) {
        emit engineMissing();
        EngineResult r;
        r.error = EngineError::makeNotFound();
        if (onDone)
            onDone(r);
        return;
    }

    auto *proc = new QProcess(this);
    proc->setProgram(m_bin);
    proc->setArguments(args);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("NO_COLOR"), QStringLiteral("1"));
    proc->setProcessEnvironment(env);

    const QString cmdTag = args.value(0, QStringLiteral("engine"));
    m_registry.registerProcess(proc, cmdTag);

    auto *timer = new QTimer(proc);
    timer->setSingleShot(true);
    const QElapsedTimer startedAt = [] {
        QElapsedTimer t;
        t.start();
        return t;
    }();

    // 收尾函数：只执行一次（超时分支与 finished 分支竞态保护）。
    // shared_ptr 让它在各 lambda 间共享可变状态，不借 mutable（mutable 使
    // operator() 非 const，被内层 lambda 按值捕获后将无法调用）。
    auto finishedOnce = std::make_shared<bool>(false);
    auto finish = [this, proc, timer, onDone, finishedOnce, timeoutMs, cmdTag, startedAt](
                      bool timedOut) {
        if (*finishedOnce)
            return;
        *finishedOnce = true;
        timer->stop();
        const bool userStopped = m_registry.wasUserStopped(proc) && !timedOut;
        EngineCli::EngineResult r = classifyResult(proc, proc->arguments(), timedOut, userStopped);
        if (timedOut)
            r.error = EngineError::makeTimeout(qMax(1, timeoutMs / 1000));
        // 真机排障唯一可靠的现场（M0-9）：跑了什么、结果、耗时、是否超时/被停。
        // 只打命令名与退出码——不打参数（可能含项目名/路径），stdout 一律不进日志。
        if (r.timedOut)
            dWarning() << "engine:" << cmdTag << "超时（预算" << timeoutMs / 1000 << "s）";
        else if (r.cancelled)
            dInfo() << "engine:" << cmdTag << "被用户停止";
        else if (!r.ok())
            dWarning() << "engine:" << cmdTag << "失败 exit=" << r.exitCode
                       << "耗时" << startedAt.elapsed() << "ms";
        else
            dInfo() << "engine:" << cmdTag << "ok 耗时" << startedAt.elapsed() << "ms";
        if (onDone)
            onDone(r);
        proc->deleteLater();
    };

    connect(timer, &QTimer::timeout, proc, [proc, finish] {
        if (proc->state() == QProcess::NotRunning) {
            finish(true);
            return;
        }
        proc->terminate(); // 先 SIGTERM 给引擎收尾机会
        QTimer::singleShot(2000, proc, [proc] {
            if (proc->state() != QProcess::NotRunning)
                proc->kill();
        });
        // 给 2.5s 宽限等进程退出；仍未退出则强制按超时收尾
        QTimer::singleShot(2500, proc, [finish] { finish(true); });
    });

    connect(proc, &QProcess::finished, proc,
            [finish](int, QProcess::ExitStatus) { finish(false); });
    connect(proc, &QProcess::errorOccurred, proc,
        [this, proc, timer, finish, onDone, finishedOnce](QProcess::ProcessError e) {
            if (e != QProcess::FailedToStart)
                return;
            // 引擎起不来：明确报错（不是 notFound——路径是探活过的，多半是权限/库缺失）
            if (!*finishedOnce) {
                *finishedOnce = true;
                timer->stop();
                EngineCli::EngineResult r;
                r.error = EngineError::makeFailed(
                    QStringLiteral("无法启动引擎（%1）。请检查文件是否可执行、依赖库是否完整。")
                        .arg(m_bin));
                if (onDone)
                    onDone(r);
                proc->deleteLater();
            }
        });

    timer->start(timeoutMs);
    proc->start();
}

EngineCli::EngineResult EngineCli::runSync(const QStringList &args, int timeoutMs, const QString &bin)
{
    EngineCli::EngineResult r;
    const QString program = bin.isEmpty() ? qEnvironmentVariable("DEEPGIT_BIN") : bin;
    if (program.trimmed().isEmpty()) {
        r.error = EngineError::makeNotFound();
        return r;
    }
    QProcess proc;
    proc.setProgram(program);
    proc.setArguments(args);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("NO_COLOR"), QStringLiteral("1"));
    proc.setProcessEnvironment(env);
    proc.start();
    if (!proc.waitForStarted(5000)) {
        r.error = EngineError::makeFailed(
            QStringLiteral("无法启动引擎（%1）。").arg(program));
        return r;
    }
    if (!proc.waitForFinished(timeoutMs)) {
        proc.terminate();
        if (!proc.waitForFinished(2000))
            proc.kill();
        r.timedOut = true;
        r.error = EngineError::makeTimeout(timeoutMs / 1000);
        return r;
    }
    return classifyResult(&proc, args, false, false);
}
