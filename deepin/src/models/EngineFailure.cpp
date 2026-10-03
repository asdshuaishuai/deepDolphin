#include "EngineFailure.h"
#include <QJsonArray>
#include <QJsonObject>

namespace {
// 单条消息 clip：换行 →「 / 」、300 字截断（多行 DOC_WRITE_FAILED 通知栏放不下，
// 但不能截成看不出所以然）。
QString clip(const QString &s)
{
    QString flat = s;
    flat.replace(QLatin1Char('\n'), QStringLiteral(" / "));
    flat = flat.trimmed();
    if (flat.size() > 300)
        return flat.left(300) + QStringLiteral("…");
    return flat;
}

QString nonEmpty(const QString &s)
{
    const QString t = s.trimmed();
    return t.isEmpty() ? QStringLiteral("引擎失败（无详细信息）") : clip(t);
}

// 非空字符串才收；空串/非字符串 → nullopt（「键在但空」≠「键不在」的判断交给调用处）
std::optional<QString> nonemptyString(const QJsonValue &v)
{
    if (!v.isString())
        return std::nullopt;
    const QString t = v.toString().trimmed();
    if (t.isEmpty())
        return std::nullopt;
    return t;
}

QString decorate(const QJsonValue &code, const QString &message)
{
    const std::optional<QString> c = nonemptyString(code);
    if (c.has_value())
        return clip(*c + QStringLiteral("：") + message);
    return clip(message);
}

// 「N 个项目失败：a；b；c」——超过 4 条就说还剩几条（截断必须自报）。
QString summarize(const QString &head, const QStringList &reasons)
{
    QStringList show;
    const int limit = qMin(4, reasons.size());
    for (int i = 0; i < limit; ++i)
        show << clip(reasons.at(i));
    QString s = head + QStringLiteral("：") + show.join(QStringLiteral("；"));
    if (reasons.size() > show.size())
        s += QStringLiteral("；…另有 %1 个失败").arg(reasons.size() - show.size());
    return s;
}

// ③④⑤ 的摘要；nil（nullopt）= 不是批量/采集失败形状。
std::optional<QString> batchOutcome(const QJsonObject &obj)
{
    // ③ update/deep 全项目：{results, count, succeeded, failed}
    if (obj.contains(QLatin1String("results")) && obj.value(QLatin1String("results")).isArray()) {
        QStringList reasons;
        const QJsonArray arr = obj.value(QLatin1String("results")).toArray();
        for (const QJsonValue &v : arr) {
            if (!v.isObject())
                continue;
            const QJsonObject d = v.toObject();
            if (!EngineFailure::isFailure(d))
                continue;
            const std::optional<QString> msg = nonemptyString(d.value(QLatin1String("message")));
            if (msg.has_value())
                reasons << decorate(d.value(QLatin1String("code")), *msg);
        }
        // 个数优先取引擎写的 failed：没带 message 的失败项不该被悄悄漏掉
        int failed = obj.contains(QLatin1String("failed"))
                         ? obj.value(QLatin1String("failed")).toInt(-1)
                         : -1;
        if (failed < 0)
            failed = reasons.size();
        if (failed <= 0)
            return QStringLiteral("引擎以非 0 退出但未在载荷里给出失败项");
        return summarize(QStringLiteral("%1 个项目更新失败").arg(failed), reasons);
    }

    // ④ status：{projects:[…], summary:{failedProjects:N}}
    if (obj.contains(QLatin1String("projects"))
        && obj.value(QLatin1String("projects")).isArray()
        && obj.contains(QLatin1String("summary"))) {
        const int n = obj.value(QLatin1String("summary")).toObject()
                          .value(QLatin1String("failedProjects"))
                          .toInt(0);
        if (n > 0) {
            QStringList reasons;
            for (const QJsonValue &v : obj.value(QLatin1String("projects")).toArray()) {
                if (!v.isObject())
                    continue;
                const std::optional<QString> e =
                    nonemptyString(v.toObject().value(QLatin1String("error")));
                if (e.has_value())
                    reasons << *e;
            }
            if (reasons.isEmpty())
                return QStringLiteral("%1 个项目采集失败（引擎未给出逐条原因）").arg(n);
            return summarize(QStringLiteral("%1 个项目采集失败").arg(n), reasons);
        }
    }

    // ⑤ dashboard：projects 是计数对象，只有 failed 一个数
    if (obj.contains(QLatin1String("projects"))
        && obj.value(QLatin1String("projects")).isObject()) {
        const int n = obj.value(QLatin1String("projects"))
                          .toObject()
                          .value(QLatin1String("failed"))
                          .toInt(0);
        if (n > 0)
            return QStringLiteral("%1 个项目采集失败（引擎在此只给了个数，未给逐条原因）").arg(n);
    }
    return std::nullopt;
}
} // namespace

namespace EngineFailure {

bool isFailure(const QJsonObject &d)
{
    if (d.contains(QLatin1String("ok")))
        return false; // 有 ok 键 ⇒ 不是失败（ok:false 只是「没写文档」）
    return d.contains(QLatin1String("code")) || d.contains(QLatin1String("error"));
}

QString reason(const QJsonDocument &payload, const QString &fallback)
{
    if (!payload.isObject())
        return nonEmpty(fallback);
    const QJsonObject obj = payload.object();

    // 批量形状先判：顶层没有 message，只看顶层会把成功的批说成失败
    if (auto batch = batchOutcome(obj))
        return *batch;

    // ① {code,message,details?}
    if (auto msg = nonemptyString(obj.value(QLatin1String("message"))))
        return decorate(obj.value(QLatin1String("code")), *msg);

    // ② {error:true,code,message}（error 是布尔）与失败桩 {error:"原因"}：
    //    error 为**非空字符串**时是真因；为布尔 true 时落到 message 分支已处理。
    const QJsonValue errVal = obj.value(QLatin1String("error"));
    if (errVal.isString()) {
        if (auto msg = nonemptyString(errVal))
            return decorate(obj.value(QLatin1String("code")), *msg);
    }

    // 不猜：交回退路，另附载荷原文摘要
    const QString raw = QString::fromUtf8(payload.toJson(QJsonDocument::Compact)).trimmed();
    if (raw.isEmpty())
        return nonEmpty(fallback);
    return QStringLiteral("%1（引擎输出：%2）").arg(nonEmpty(fallback), clip(raw));
}

QString reason(const QJsonDocument &payload, int exitCode)
{
    return reason(payload, QStringLiteral("引擎退出码 %1").arg(exitCode));
}

QStringList batchReasons(const QJsonDocument &payload)
{
    QStringList out;
    if (!payload.isObject())
        return out;
    const QJsonValue results = payload.object().value(QLatin1String("results"));
    if (!results.isArray())
        return out;
    for (const QJsonValue &v : results.toArray()) {
        if (!v.isObject())
            continue;
        const QJsonObject d = v.toObject();
        if (!isFailure(d))
            continue;
        const std::optional<QString> msg = nonemptyString(d.value(QLatin1String("message")));
        if (msg.has_value())
            out << decorate(d.value(QLatin1String("code")), *msg);
    }
    return out;
}

int batchFailedCount(const QJsonDocument &payload)
{
    if (!payload.isObject())
        return -1;
    if (!payload.object().contains(QLatin1String("results")))
        return -1;
    return batchReasons(payload).size();
}

} // namespace EngineFailure
