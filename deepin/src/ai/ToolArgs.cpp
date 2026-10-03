#include "ToolArgs.h"
#include <QJsonArray>
#include <QJsonDocument>

namespace ToolArgs {

Decoded decode(const QByteArray &argsJson)
{
    Decoded d;
    const QByteArray trimmed = argsJson.trimmed();
    // 空串不是「合法的空对象」：它意味着模型根本没给出参数结构，
    // 而 {} 至少是模型明确表示「没有额外参数」。两者不能混。
    if (trimmed.isEmpty()) {
        d.k = Decoded::K::malformed;
        d.raw = QStringLiteral("（空串）");
        return d;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(trimmed);
    if (!doc.isObject()) {
        d.k = Decoded::K::malformed;
        const QString raw = QString::fromUtf8(trimmed);
        d.raw = doc.isNull() ? raw.left(200)
                             : QStringLiteral("顶层不是 JSON 对象：%1").arg(raw.left(200));
        return d;
    }
    d.k = Decoded::K::object;
    d.obj = doc.object();
    return d;
}

QStringList missing(const QJsonObject &params, const QStringList &requiredList)
{
    QStringList out;
    for (const QString &key : requiredList) {
        const QJsonValue v = params.value(key);
        if (v.isUndefined() || v.isNull()) {
            out << key;
            continue;
        }
        if (v.isString() && v.toString().trimmed().isEmpty())
            out << key; // 空白等同缺
    }
    return out;
}

QString missingMessage(const QString &tool, const QStringList &missingList)
{
    return QStringLiteral("工具「%1」缺少必填参数：%2。"
                          "这些参数没有安全的默认值：引擎把空项目名理解成「整个项目群」，"
                          "所以这里宁可报错也不猜。请带上这些参数重新调用，不要自己编造项目名。")
        .arg(tool, missingList.join(QStringLiteral("、")));
}

QString malformedMessage(const QString &tool, const QString &raw)
{
    return QStringLiteral("工具「%1」的参数不是合法的 JSON 对象，已拒绝执行：%2。"
                          "请重新调用并给出形如 {\"key\": \"value\"} 的参数对象。")
        .arg(tool, raw);
}

QStringList required(const QMap<QString, QString> &parametersJSONByName, const QString &tool)
{
    const auto it = parametersJSONByName.constFind(tool);
    if (it == parametersJSONByName.cend())
        return {};
    const QJsonDocument doc = QJsonDocument::fromJson(it->toUtf8());
    if (!doc.isObject())
        return {};
    QStringList out;
    for (const QJsonValue &v : doc.object().value(QLatin1String("required")).toArray())
        out << v.toString();
    return out;
}

} // namespace ToolArgs
