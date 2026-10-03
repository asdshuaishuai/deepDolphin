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
// 超时预算 ≥ 引擎 120s 上界口径（CONTRACT §4.5）：宁可等也不要半截数据。
// UTF-8 尾部 lossy 解码（超时/残缺输出不当代码 JSON）。
#pragma once
#include "../models/EngineError.h"
#include "ProcessRegistry.h"
#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <functional>
#include <optional>

class QProcess;
class QTimer;

// 各命令超时（SPEC §2 表 / PLAN §2.3），单位毫秒
namespace EngineTimeouts {
constexpr int Version = 8'000;        // 探活
constexpr int Status = 30'000;        // status --json（全群）
constexpr int StatusProject = 60'000; // status <name> --json
constexpr int Dashboard = 180'000;
constexpr int Milestones = 60'000;    // milestone list/add/done/drop/reopen/remove
constexpr int Docs = 60'000;
constexpr int Journal = 30'000;
constexpr int Update = 300'000;       // update <name>
constexpr int Deep = 600'000;         // deep <name>
constexpr int UpdateAll = 900'000;    // update（全项目）
constexpr int DeepAll = 1'800'000;    // deep（全项目）
constexpr int Git = 120'000;
constexpr int Add = 30'000;
constexpr int Scan = 300'000;
constexpr int Tools = 30'000;
constexpr int Context = 60'000;
} // namespace EngineTimeouts

class EngineCli : public QObject {
    Q_OBJECT
public:
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

    // 同步调用：仅引擎探活/自检/测试路径使用，不得在 UI 热路径使用。
    static EngineResult runSync(const QStringList &args, int timeoutMs, const QString &bin = {});

    ProcessRegistry *registry() { return &m_registry; }

    // 「停止更新」：真 terminate 引擎进程（只杀 update/deep，不伤并行 status）
    int stopUpdates();

signals:
    // 引擎缺失时首次调用会发出（UI 据此切安装指引页）
    void engineMissing();

private:
    QString m_bin;
    ProcessRegistry m_registry;
};
