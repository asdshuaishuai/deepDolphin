#include "EngineError.h"
#include "EngineFailure.h"

namespace {
// CONTRACT §1.1 / §4.2：全落空时的可操作提示，绝不静默降级。
const char kInstallHint[] =
    "找不到 moonGit 引擎。请运行 moonGit/scripts/install.sh 安装，"
    "或设置环境变量 DEEPGIT_BIN 指向引擎二进制，然后重新检测。";
} // namespace

QString EngineError::userMessage() const
{
    switch (kind) {
    case EngineErrorKind::notFound:
        return QString::fromUtf8(kInstallHint);
    case EngineErrorKind::failedWithPayload:
        if (payload.has_value())
            return EngineFailure::reason(*payload, message);
        return message;
    case EngineErrorKind::timeout:
    case EngineErrorKind::cancelled:
    case EngineErrorKind::failed:
        return message;
    }
    return message;
}

EngineError EngineError::makeNotFound()
{
    EngineError e;
    e.kind = EngineErrorKind::notFound;
    e.message = QString::fromUtf8(kInstallHint);
    return e;
}

EngineError EngineError::makeTimeout(int seconds)
{
    EngineError e;
    e.kind = EngineErrorKind::timeout;
    e.message = QStringLiteral("引擎调用超时（%1s）。引擎在处理大仓库时可能确实需要这么久；"
                               "如果反复出现，可停止更新后重试。")
                    .arg(seconds);
    return e;
}

EngineError EngineError::makeCancelled(const QString &cmd)
{
    EngineError e;
    e.kind = EngineErrorKind::cancelled;
    e.message = QStringLiteral("已停止：%1").arg(cmd);
    return e;
}

EngineError EngineError::makeFailed(const QString &message)
{
    EngineError e;
    e.kind = EngineErrorKind::failed;
    e.message = message;
    return e;
}

EngineError EngineError::makeFailedWithPayload(const QString &message, const QJsonDocument &payload)
{
    EngineError e;
    e.kind = EngineErrorKind::failedWithPayload;
    e.message = message;
    e.payload = payload;
    return e;
}
