// AgentCore.h — 无 UI 的 agent 执行核心（mac AgentCore.swift 对位）。
//
// 引擎是 AI 无关内核：这里拉上下文包（moongit context --json）与工具清单
//（moongit tools --json），组 prompt 后经 AIEngine 执行**原生工具循环（≤4 轮）**。
//
// 【线程约定】run/executeTool 都是同步阻塞（引擎走 EngineCli::runSync、HTTP 走
// 内部 QEventLoop），**必须从 worker 线程进**；UI 经 onEvent 收过程事件并自行
// marshal 回 GUI 线程。
//
// 【单一来源红线】必填参数只从「已发给模型的那份」工具定义取
//（requiredParamsByTool）；agent 循环与「一键全量」共用这一份，抄两份必然漂移，
// 漂移的后果是必填校验悄悄失效 → 空项目名=整个项目群（NC31）。
#pragma once
#include "AIConfig.h"
#include "AIEngine.h"
#include <QAtomicInt>
#include <QJsonObject>
#include <QList>
#include <QMap>
#include <QString>
#include <QStringList>
#include <functional>

class AgentCore {
public:
    struct Target {
        enum class Kind { group, project };
        Kind kind = Kind::group;
        QString projectName;

        bool isGroup() const { return kind == Kind::group; }
        QString label() const
        {
            return isGroup() ? QStringLiteral("整个项目群") : projectName;
        }
    };

    explicit AgentCore(const QString &engineBin)
        : m_bin(engineBin)
    {
    }

    // 引擎 tools --json（30s）→ ToolDef（params "a,b,c" 全部 string 型必填）+
    // 清单原文（进系统提示词）+ name → parametersJSON（必填校验唯一来源）。
    bool loadToolManifest(QVector<ToolDef> *defs, QMap<QString, QString> *paramsByTool,
        QString *toolsText, QString *err);

    // 工具执行（本机 CLI 子进程）。必填校验在**执行点内部**（NC31 收口）。
    // 返回 (ok, 结果文本)；params 已是解码后的对象。
    bool executeTool(const QString &name, const QJsonObject &params,
        const QMap<QString, QString> &paramsByTool, QString *outText);

    // 完整 agent 循环，返回**追加后**的完整历史（调用方存回 @State 等价物）。
    // 失败：*errorOut 非空；调用方把已发提问留回 history（用户的问题不消失）。
    // cancelled：逐轮检查的取消旗标（已 spawn 的引擎子进程由 CLI 超时兜底——与 mac 相同限制）。
    QList<ChatMessage> run(const QString &question, QList<ChatMessage> history,
        const Target &target, const AIConfig &cfg, int maxRounds = 4,
        const std::function<void(const QString &)> &onEvent = {},
        QString *errorOut = nullptr, QAtomicInt *cancelled = nullptr);

private:
    bool runEngineRaw(const QStringList &args, int timeoutMs, QString *rawOut, QString *err);

    QString m_bin; // 引擎二进制；空 = 未找到（工具一律报 notFound 原文，不静默）
};
