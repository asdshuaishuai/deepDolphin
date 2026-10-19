// EngineCli.h — 引擎 CLI 子进程客户端（`moongit <命令> --json`）。
//
// 【边界】无 HTTP 服务、无端口；每次调用一个独立 QProcess：无状态、无并发冲突。
// 每次调用注入 NO_COLOR=1（SPEC §0）。
//
// 错误分类（CONTRACT §4）：
// · exit==0 → stdout 应是一份合法 JSON（空 stdout = 契约破坏，不是合法空态）；
// · exit≠0 但 stdout 可解析 JSON → failedWithPayload，**载荷保留**（ENGINE 把
//   失败原因写在 stdout：全部项目采集失败也先打印完整 JSON 再 exit 1）；
// · exit≠0 且 stdout 非 JSON → failed，stdout 是主因、stderr 是补充（usage 类
//   失败的真因在 stdout 纯文本里，如「需要提交信息（--message）」）；
// · 超时 → 杀进程 + timeout（与 cancelled 严格分开）；
// · 引擎缺失 → notFound + engineMissing 信号。
//
// 【两套输出契约】引擎的输出分两类，**判据不同**，不能共用一条：
// · Json 模式（`--json` 命令）：stdout 必须是一份合法 JSON 对象；
// · Text 模式（`arch gen` / `render arch` 这类回执型命令）：stdout 必须是**非空
//   文本**，引擎把回执写成人话（如「架构已生成：首版（第 0 版）」）。
// 用错模式的后果很具体：拿 Json 模式去收 Text 命令的输出，exit==0 但 stdout 不是
// JSON 会被判成「引擎输出不是合法 JSON」——**成功被报成失败**。
//
// 超时预算 ≥ 引擎 120s 上界口径（CONTRACT §4.5）：宁可等也不要半截数据。
// UTF-8 尾部 lossy 解码（超时/残缺输出不当代码 JSON）。
#pragma once
#include "../models/EngineError.h"
#include "ProcessRegistry.h"
#include <QElapsedTimer>
#include <QAtomicInt>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <functional>
#include <optional>

class QProcess;
class QTimer;

// 各命令超时（SPEC §2 表 / PLAN §2.3），单位毫秒。
// 常量已下沉到 logic/EngineTimeouts.h —— agent 工具表（logic/AgentToolPlan）
// 要用同一批数字，同一件事两处字面量必然漂移（改了引擎调用忘了改工具表，
// 症状是「大仓整图构建在 agent 里被砍成 120 秒」这类难查的问题）。
// logic/ 不依赖 app/，所以常量住在下面这一层；这里 include 它，
// `EngineTimeouts::X` 的写法在全局作用域照样成立（老调用点零改动）。
#include "../logic/EngineTimeouts.h"

class EngineCli : public QObject {
    Q_OBJECT
public:
    /// stdout 的契约形态。决定 exit==0 时 stdout 该被怎么判（见文件头「两套输出契约」）。
    enum class OutputMode {
        Json, ///< stdout 应是合法 JSON 对象（`--json` 命令）
        Text, ///< stdout 应是非空文本（回执型命令：arch gen / render arch）
    };

    struct EngineResult {
        int exitCode = -1;
        QString stdOut;
        QString stdErr;
        bool timedOut = false;
        bool cancelled = false;
        std::optional<QJsonDocument> payload; // exit==0 或 failedWithPayload 时尽量有
        EngineError error;                    // isNull() = 成功

        bool ok() const { return error.isNull(); }
    };

    explicit EngineCli(QObject *parent = nullptr);

    // 引擎二进制路径；空 = 未找到（调用即 notFound + engineMissing）
    void setEngineBin(const QString &bin);
    QString engineBin() const { return m_bin; }

    // 引擎是否已定位（locate 由调用方负责；这里只持结果）
    bool engineFound() const { return !m_bin.isEmpty(); }

    // 异步调用：完成时在事件循环线程回调 onDone；QProcess 由本类收回。
    void callJson(const QStringList &args, int timeoutMs,
                  std::function<void(const EngineResult &)> onDone);

    // 同上，但按 Text 契约判 stdout（回执型命令专用；回执在 res.stdOut）。
    void callText(const QStringList &args, int timeoutMs,
                  std::function<void(const EngineResult &)> onDone);

    // 纯判定：这份 stdout 满不满该 mode 的契约？**分类逻辑的唯一出处**（判据直接测它）。
    // · Json：必须能解析成一个 JSON 对象（空 stdout = 契约破坏）；
    // · Text：必须非空（引擎说成功了却没给回执 = 契约破坏）。
    static bool stdoutSatisfies(OutputMode mode, const QString &stdoutText);

    // 同步调用：引擎探活/自检与 agent worker 使用，不得在 UI 热路径使用。
    // cancelled 非空时切片等待（M0-5）：旗标置位 → terminate（2s 后 kill）+ cancelled 结果，
    // 「停止」不必再等当前引擎命令跑完（deep 最长 600s）。
    static EngineResult runSync(const QStringList &args, int timeoutMs, const QString &bin = {},
                                const QAtomicInt *cancelled = nullptr);

    ProcessRegistry *registry() { return &m_registry; }

    // 「停止更新」：真 terminate 引擎进程（只杀 update/deep，不伤并行 status）
    int stopUpdates();

signals:
    // 引擎缺失时首次调用会发出（UI 据此切安装指引页）
    void engineMissing();

private:
    // 两条公开调用路径的唯一实现处（进程管理/超时/取消/分类/收尾都在这里）。
    void callWithMode(const QStringList &args, int timeoutMs, OutputMode mode,
                      std::function<void(const EngineResult &)> onDone);

    QString m_bin;
    ProcessRegistry m_registry;
};
