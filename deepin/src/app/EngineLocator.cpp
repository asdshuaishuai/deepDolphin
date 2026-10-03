#include "EngineLocator.h"
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QRunnable>
#include <QThreadPool>

namespace {
constexpr int kProbeTimeoutMs = 8000; // CONTRACT §1.1：version 探活 8s

QString homePath()
{
    return QDir::homePath();
}

QStringList candidatePaths(QStringList *problems)
{
    QStringList paths;

    // 1. DEEPGIT_BIN：非空 → 必须可用，否则报错不静默跳过
    const QString envBin = qEnvironmentVariable("DEEPGIT_BIN").trimmed();
    const bool envSet = !envBin.isEmpty();
    if (envSet)
        paths << envBin;

    // 2. 仓内开发构建：<工作区根>/moonGit/target/release/bin/main
    //    本客户端位于 <工作区根>/deepDolphin/deepin/build → 上溯三级即工作区根。
    const QString appDir = QCoreApplication::instance()
        ? QCoreApplication::applicationDirPath()
        : QDir::currentPath();
    paths << QDir(appDir + QStringLiteral("/../../../moonGit/target/release/bin/main"))
                 .absolutePath();

    // 3/4. 常见安装位：先新名 moongit，再旧名 deepgit（旧名兜底不能省）
    const QStringList dirs = {
        homePath() + QStringLiteral("/.local/bin"),
        QStringLiteral("/usr/local/bin"),
        QStringLiteral("/usr/bin"),
    };
    for (const QString &dir : dirs) {
        paths << dir + QStringLiteral("/moongit");
        paths << dir + QStringLiteral("/deepgit");
    }

    // 5. PATH
    const QString moongit = QStandardPaths::findExecutable(QStringLiteral("moongit"));
    if (!moongit.isEmpty())
        paths << moongit;
    const QString deepgit = QStandardPaths::findExecutable(QStringLiteral("deepgit"));
    if (!deepgit.isEmpty())
        paths << deepgit;

    if (problems && envSet)
        *problems << QStringLiteral("已设置 DEEPGIT_BIN=%1").arg(envBin);
    return paths;
}
} // namespace

bool EngineLocator::probe(const QString &bin)
{
    const QFileInfo info(bin);
    if (!info.exists() || !info.isFile())
        return false;

    QProcess proc;
    proc.setProgram(bin);
    proc.setArguments({ QStringLiteral("version") });
    // 探活也注入 NO_COLOR（与正式调用同一环境口径）
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("NO_COLOR"), QStringLiteral("1"));
    proc.setProcessEnvironment(env);
    proc.start();
    if (!proc.waitForStarted(3000))
        return false;
    if (!proc.waitForFinished(kProbeTimeoutMs)) {
        proc.kill();
        proc.waitForFinished(2000);
        return false;
    }
    return proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0;
}

EngineLocator::Result EngineLocator::locate()
{
    Result result;
    const QString envBin = qEnvironmentVariable("DEEPGIT_BIN").trimmed();
    const bool envSet = !envBin.isEmpty();

    QStringList problems;
    const QStringList candidates = candidatePaths(&problems);

    for (const QString &path : candidates) {
        if (probe(path)) {
            result.bin = QDir(path).absolutePath();
            result.found = true;
            return result;
        }
        // DEEPGIT_BIN 指向的候选**必须**可用：报错并停止（不静默跳到下一个候选）
        if (envSet && QDir::cleanPath(path) == QDir::cleanPath(envBin)) {
            result.problems << QStringLiteral(
                "DEEPGIT_BIN 指向的引擎不存在或不可执行：%1").arg(envBin);
            result.problems << installHint();
            return result; // 不再尝试其他候选
        }
    }

    result.problems << QStringLiteral("在 DEEPGIT_BIN、开发构建目录、~/.local/bin、"
                                      "/usr/local/bin 与 PATH 上都没有找到可用的 moongit/deepgit。");
    result.problems << installHint();
    return result;
}

QString EngineLocator::installHint()
{
    return QString::fromUtf8(
        "请运行 moonGit/scripts/install.sh 安装引擎（安装到 ~/.local/bin/moongit），"
        "或设置环境变量 DEEPGIT_BIN 指向引擎二进制，然后点击「重新检测引擎」。");
}

namespace {
// 把「同步 locate()」包成 worker 任务。
// ⚠ 线程与生命周期：QThreadPool 的 QRunnable 跑完即自动删除，因此**绝不允许**把 `this`
//   捕获进投递回 GUI 线程的 lambda（那是一个必然的 use-after-free——本仓实测段错误，
//   表现为主线程进事件循环后立刻崩，日志里连回调第一行都打不出来）。
//   做法：worker 线程内把回调 swap 出来，用**值捕获**的 lambda 投递，此后与本对象无关。
class LocateTask : public QRunnable {
public:
    explicit LocateTask(std::function<void(const EngineLocator::Result &)> cb)
        : m_cb(std::move(cb))
    {
    }

    void run() override
    {
        const EngineLocator::Result r = EngineLocator::locate();
        std::function<void(const EngineLocator::Result &)> cb;
        cb.swap(m_cb); // 在 worker 线程就交出去：投递的 lambda 只持有这份副本
        QObject *app = QCoreApplication::instance();
        if (!app) {
            // 无事件循环（理论路径：QCoreApplication 都没建）→ 就地执行，不丢结果
            if (cb)
                cb(r);
            return;
        }
        QMetaObject::invokeMethod(
            app,
            [cb, r]() mutable {
                if (cb)
                    cb(r);
            },
            Qt::QueuedConnection);
    }

private:
    std::function<void(const EngineLocator::Result &)> m_cb;
};
} // namespace

void EngineLocator::locateAsync(const std::function<void(const Result &)> &cb)
{
    // 非自动删除 + 池内排队：并发点「重新检测引擎」最坏多跑一次探活（结果以最后一次为准），
    // 比"人手去管任务生命周期"安全。
    auto *task = new LocateTask(cb);
    task->setAutoDelete(true);
    QThreadPool::globalInstance()->start(task);
}
