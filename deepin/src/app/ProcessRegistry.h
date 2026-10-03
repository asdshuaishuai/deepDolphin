// ProcessRegistry.h — 引擎子进程登记表（mac EngineCLI.ProcessRegistry 对位）。
//
// 【为什么必须有这张表】取消调用方的协程/定时器杀不掉引擎进程——
// 「停止更新」的唯一有效动作是**真的 terminate 那个 QProcess**。
// 只杀 `update`/`deep` 不伤并行 `status`（SPEC §3.3.5）：terminateRunning 按
// cmdTag（命令首词）前缀过滤。
//
// 谁停的，只有发起方知道：超时分支同样会让进程死于信号，靠退出状态反推
// 「这是用户按的」迟早猜错。Registry 记 userStopped，EngineCli 收尾时来问。
#pragma once
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <vector>

class QProcess;

class ProcessRegistry : public QObject {
    Q_OBJECT
public:
    explicit ProcessRegistry(QObject *parent = nullptr);

    // 进程启动后立即登记；cmdTag 通常是命令首词（"update"/"deep"/"status"…）
    void registerProcess(QProcess *proc, const QString &cmdTag);

    // 终止匹配 onlyCommands 前缀的进程（空表 = 全杀）。
    // 先 terminate（SIGTERM，引擎有机会收尾），2s 后仍活着再 kill。
    // 返回被终止的进程数。
    int terminateRunning(const QStringList &onlyCommands);

    // 是否还有匹配 cmdTags（空表 = 任意）的进程在跑
    bool anyRunning(const QStringList &cmdTags) const;

    // 进程是否被用户主动停过（收尾时由 EngineCli 查询）
    bool wasUserStopped(const QProcess *proc) const;

    // 当前登记的进程数（UI 用来决定「可停止」）
    int count() const;

signals:
    // 某命令标签的进程**全部**结束时发出（标签为空串 = 全部进程跑完）
    void allFinished(const QString &cmdTag);

private:
    struct Entry {
        QPointer<QProcess> proc;
        QString cmdTag;
        QTimer *killTimer = nullptr; // terminate 后 2s 升级 kill 的定时器（成员持有防幽灵）
    };
    void onProcessFinished(const QProcess *proc);

    std::vector<Entry> m_procs;
    QSet<const QProcess *> m_userStopped;
};
