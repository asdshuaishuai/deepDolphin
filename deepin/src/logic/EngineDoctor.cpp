#include "EngineDoctor.h"

#include <QJsonArray>
#include <QJsonValue>
#include <QStringList>

namespace EngineDoctor {

Report parse(const QJsonObject &o)
{
    Report r;
    if (!o.contains(QStringLiteral("checks"))) {
        r.error = QStringLiteral("引擎自检载荷缺 checks 键（契约可能过旧）");
        return r;
    }
    for (const QJsonValue &cv : o.value(QStringLiteral("checks")).toArray()) {
        const QJsonObject c = cv.toObject();
        Check item;
        item.name = c.value(QStringLiteral("check")).toString();
        item.result = c.value(QStringLiteral("result")).toString();
        item.detail = c.value(QStringLiteral("detail")).toString();
        r.checks << item;
    }
    // ⚠ problems 缺键时**不回落成 0**（那会把「引擎没发」说成「没问题」）：
    //   报告照样有效，但摘要要说明「问题数未知」。
    if (o.contains(QStringLiteral("problems")))
        r.problems = o.value(QStringLiteral("problems")).toInt();
    else
        r.problems = -1; // -1 = 未知
    r.ok = true;
    return r;
}

QString summary(const Report &r)
{
    if (!r.ok)
        return QStringLiteral("自检报告读不出来");
    const QString count = QString::number(r.checks.size());
    if (r.problems < 0)
        return QStringLiteral("%1 项检查 · 问题数未知（契约可能过旧）").arg(count);
    if (r.problems == 0)
        return QStringLiteral("%1 项检查 · 0 个问题").arg(count);
    return QStringLiteral("%1 项检查 · %2 个问题").arg(count).arg(r.problems);
}

Tone toneOf(const Report &r)
{
    if (!r.ok)
        return Tone::unreadable;
    if (r.problems < 0)
        return Tone::unknown; // 问题数未知：不是「没问题」
    if (r.problems > 0)
        return Tone::problem;
    return Tone::ok;
}

QString checkLine(const Check &c)
{
    QStringList parts;
    if (!c.name.isEmpty())
        parts << c.name;
    if (!c.result.isEmpty())
        parts << c.result;
    QString line = parts.join(QStringLiteral(" · "));
    if (!c.detail.isEmpty())
        line += (line.isEmpty() ? QString() : QStringLiteral(" · ")) + c.detail;
    return line;
}

} // namespace EngineDoctor
