// EngineError.h — 引擎调用的五类错误（SPEC §3.5 / mac EngineCLI.EngineError 对位）。
//
// 关键口径：
// · failedWithPayload：exit≠0 但 stdout 是 JSON → **载荷必须保留**（引擎把失败原因
//   写在 stdout 里：全部项目采集失败也照样打印完整 JSON 再 exit 1）。
// · timeout 与 cancelled 文案分开：超时是引擎卡住（要报、值得担心）；
//   被停是用户自己按的（不报「失败」）。
// · notFound：引擎缺失的明确报错 + 安装引导文案（CONTRACT §1.1）。
#pragma once
#include <QJsonDocument>
#include <QString>
#include <optional>

enum class EngineErrorKind {
    notFound,          // 引擎二进制缺失
    failed,            // exit≠0 且 stdout 无可解析 JSON（原因 = stdout 主因 + stderr 补充）
    failedWithPayload, // exit≠0 但 stdout 是 JSON（payload 保留）
    timeout,           // 超时被杀
    cancelled,         // 用户主动停止
};

struct EngineError {
    EngineErrorKind kind = EngineErrorKind::failed;
    QString message;
    std::optional<QJsonDocument> payload; // 仅 failedWithPayload

    bool isNull() const { return message.isEmpty() && kind == EngineErrorKind::failed && !payload.has_value(); }

    // 给人（和模型）看的失败原因：failedWithPayload 会去读载荷
    //（EngineFailure::reason），其余分支用 message。永不为空。
    QString userMessage() const;

    // ── 便捷构造 ──
    static EngineError makeNotFound();                    // 含安装引导原文
    static EngineError makeTimeout(int seconds);
    static EngineError makeCancelled(const QString &cmd);
    static EngineError makeFailed(const QString &message);
    static EngineError makeFailedWithPayload(const QString &message, const QJsonDocument &payload);
};
