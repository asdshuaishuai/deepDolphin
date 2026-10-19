#include "DocumentIntegrity.h"

namespace DocumentIntegrity {

State stateOf(const VerifyEnvelope &e)
{
    // 优先级即严重度：缺失 > 明确不一致 > 无法判定 > 无从校验 > 通过。
    // 「引擎没说通过、也没给任何计数」→ 无从判定，不许当通过。
    if (e.missing > 0)
        return State::missing;
    if (e.failures > 0)
        return State::failed;
    if (e.undetermined > 0)
        return State::undetermined;
    if (e.checked <= 0)
        return State::none;
    if (e.verified)
        return State::verified;
    return State::undetermined;
}

QString headline(State s, const VerifyEnvelope &e)
{
    switch (s) {
    case State::verified:
        return QStringLiteral("文档完整性：通过（%1 份逐字节一致）").arg(e.checked);
    case State::failed:
        return QStringLiteral("文档完整性：%1 份与备份不一致").arg(e.failures);
    case State::undetermined:
        return QStringLiteral("文档完整性：%1 份无法判定（不等于通过）").arg(e.undetermined);
    case State::missing:
        return QStringLiteral("文档完整性：%1 份文档缺失（备份仍在，可恢复）").arg(e.missing);
    case State::none:
        break;
    }
    return QStringLiteral("文档完整性：没有可校验的文档");
}

QString detail(const VerifyEnvelope &e)
{
    QStringList parts;
    if (e.checked > 0)
        parts << QStringLiteral("已校验 %1 份").arg(e.checked);
    if (e.failures > 0)
        parts << QStringLiteral("不一致 %1 份").arg(e.failures);
    if (e.undetermined > 0)
        parts << QStringLiteral("无法判定 %1 份").arg(e.undetermined);
    if (e.missing > 0)
        parts << QStringLiteral("缺失 %1 份").arg(e.missing);
    // 引擎的 note 原样转述：缺失时它带备份路径，那正是用户要的下一步。
    if (!e.note.isEmpty())
        parts << e.note;
    return parts.join(QStringLiteral(" · "));
}

QString documentLine(const VerifyDocument &d)
{
    QString line = QStringLiteral("%1（%2）").arg(d.doc, d.ok ? QStringLiteral("一致") : QStringLiteral("不一致"));
    if (!d.note.isEmpty())
        line += QStringLiteral("：%1").arg(d.note);
    return line;
}

} // namespace DocumentIntegrity
