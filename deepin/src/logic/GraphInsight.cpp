#include "GraphInsight.h"

#include <QJsonArray>
#include <QJsonValue>

namespace GraphInsight {
namespace {

QVector<Def> readDefs(const QJsonValue &v)
{
    QVector<Def> out;
    for (const QJsonValue &dv : v.toArray()) {
        const QJsonObject d = dv.toObject();
        Def def;
        def.file = d.value(QStringLiteral("file")).toString();
        def.line = d.value(QStringLiteral("line")).toInt();
        def.kind = d.value(QStringLiteral("kind")).toString();
        out << def;
    }
    return out;
}

} // namespace

QString symbolNameFromId(const QString &id)
{
    // id 形如 f:<路径>:<行号>:<名字> —— 名字是**最后一段**。
    // 路径里也可能带冒号，所以不能简单取第二段。
    const QStringList parts = id.split(QLatin1Char(':'));
    if (parts.size() < 3)
        return QString();
    return parts.last();
}

Overview parseOverview(const QJsonObject &o)
{
    Overview r;
    if (!o.contains(QStringLiteral("files")) || !o.contains(QStringLiteral("symbols"))) {
        r.error = QStringLiteral("图谱概览载荷缺 files/symbols 键（契约可能过旧）");
        return r;
    }
    r.root = o.value(QStringLiteral("root")).toString();
    r.files = o.value(QStringLiteral("files")).toInt();
    r.symbols = o.value(QStringLiteral("symbols")).toInt();
    r.imports = o.value(QStringLiteral("imports")).toInt();
    r.referenceEdges = o.value(QStringLiteral("referenceEdges")).toInt();

    const QJsonArray tops = o.value(QStringLiteral("topFiles")).toArray();
    for (const QJsonValue &tv : tops) {
        const QJsonObject t = tv.toObject();
        Def d;
        d.file = t.value(QStringLiteral("path")).toString();
        r.topFiles << d;
        r.topFileSymbols << t.value(QStringLiteral("symbols")).toInt();
        r.topFileLines << t.value(QStringLiteral("lines")).toInt();
    }

    const QJsonObject langs = o.value(QStringLiteral("byLang")).toObject();
    for (auto it = langs.constBegin(); it != langs.constEnd(); ++it)
        r.byLang.insert(it.key(), it.value().toInt());
    const QJsonObject kinds = o.value(QStringLiteral("byKind")).toObject();
    for (auto it = kinds.constBegin(); it != kinds.constEnd(); ++it)
        r.byKind.insert(it.key(), it.value().toInt());

    r.truncated = o.value(QStringLiteral("truncated")).toBool();
    r.skipped = o.value(QStringLiteral("skipped")).toInt();
    r.oversizeSkipped = o.value(QStringLiteral("oversizeSkipped")).toInt();
    for (const QJsonValue &uv : o.value(QStringLiteral("unreadableDirs")).toArray())
        r.unreadableDirs << uv.toString();
    r.unreadableDirsTruncated = o.value(QStringLiteral("unreadableDirsTruncated")).toBool();

    r.ok = true;
    return r;
}

SymbolDetail parseSymbol(const QJsonObject &o)
{
    SymbolDetail r;
    if (!o.contains(QStringLiteral("name"))) {
        r.error = QStringLiteral("图谱符号载荷缺 name 键（契约可能过旧）");
        return r;
    }
    r.name = o.value(QStringLiteral("name")).toString();
    r.defs = readDefs(o.value(QStringLiteral("defs")));
    for (const QJsonValue &rv : o.value(QStringLiteral("referencedBy")).toArray()) {
        const QJsonObject ro = rv.toObject();
        Ref ref;
        ref.file = ro.value(QStringLiteral("file")).toString();
        ref.weight = ro.value(QStringLiteral("weight")).toInt();
        r.referencedBy << ref;
    }
    // ⚠ 引擎对**不存在的符号**返回空 defs 且退出码 0 —— 那不是错误，
    //   是「没找到」。ok 保持 true，由 found() 区分「没找到」与「契约坏了」。
    r.ok = true;
    return r;
}

Impact parseImpact(const QJsonObject &o)
{
    Impact r;
    if (!o.contains(QStringLiteral("name"))) {
        r.error = QStringLiteral("图谱影响面载荷缺 name 键（契约可能过旧）");
        return r;
    }
    r.name = o.value(QStringLiteral("name")).toString();
    r.defs = readDefs(o.value(QStringLiteral("defs")));
    for (const QJsonValue &fv : o.value(QStringLiteral("refFiles")).toArray())
        r.refFiles << fv.toString();
    for (const QJsonValue &iv : o.value(QStringLiteral("impactedSymbols")).toArray()) {
        const QJsonObject io = iv.toObject();
        Impacted im;
        im.file = io.value(QStringLiteral("file")).toString();
        im.symbol = io.value(QStringLiteral("symbol")).toString();
        im.kind = io.value(QStringLiteral("kind")).toString();
        r.impactedSymbols << im;
    }
    r.granularity = o.value(QStringLiteral("granularity")).toString();
    r.refFilesCapped = o.value(QStringLiteral("refFilesCapped")).toBool();
    r.impactedCapped = o.value(QStringLiteral("impactedCapped")).toBool();
    r.ok = true;
    return r;
}

} // namespace GraphInsight
