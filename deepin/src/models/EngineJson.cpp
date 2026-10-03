#include "EngineJson.h"

namespace EngineJson {

QJsonValue take(const QJsonObject &obj, const char *key)
{
    return obj.value(QLatin1String(key));
}

int intAt(const QJsonObject &obj, const char *key, int fallback)
{
    const QJsonValue v = obj.value(QLatin1String(key));
    if (v.isDouble()) {
        // JSON 数字统一按 double 承载；整数口径在此收口
        return static_cast<int>(v.toDouble());
    }
    return fallback;
}

QString strAt(const QJsonObject &obj, const char *key, const QString &fallback)
{
    const QJsonValue v = obj.value(QLatin1String(key));
    if (v.isString())
        return v.toString();
    return fallback;
}

bool boolAt(const QJsonObject &obj, const char *key, bool fallback)
{
    const QJsonValue v = obj.value(QLatin1String(key));
    if (v.isBool())
        return v.toBool();
    return fallback;
}

double msAt(const QJsonObject &obj, const char *key, double fallback)
{
    const QJsonValue v = obj.value(QLatin1String(key));
    if (v.isDouble())
        return v.toDouble();
    return fallback;
}

QJsonArray arrAt(const QJsonObject &obj, const char *key)
{
    const QJsonValue v = obj.value(QLatin1String(key));
    if (v.isArray())
        return v.toArray();
    return {};
}

QStringList strArrAt(const QJsonObject &obj, const char *key)
{
    QStringList out;
    const QJsonArray arr = arrAt(obj, key);
    out.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        if (v.isString())
            out << v.toString();
    }
    return out;
}

bool isErrorStub(const QJsonObject &obj)
{
    return obj.contains(QLatin1String("error"));
}

bool hasOpKey(const QJsonObject &obj)
{
    return obj.contains(QLatin1String("ok"));
}

bool hasCodeOrError(const QJsonObject &obj)
{
    if (obj.contains(QLatin1String("ok")))
        return false; // 有 ok 键 → 永远不算失败（CONTRACT §3.1）
    return obj.contains(QLatin1String("code")) || obj.contains(QLatin1String("error"));
}

} // namespace EngineJson
