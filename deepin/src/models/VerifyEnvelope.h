// VerifyEnvelope.h — `verify [项目...] --json` 载荷（引擎新能力接入批 V1）。
//
// 【红线】
// · 四档判定是**引擎的判据**，客户端不许自己重算：
//   failures（明确不一致）/ undetermined（**无法判定**）/ missing（文档缺失，备份仍在）/
//   verified（逐字节一致）。
// · `undetermined` 是最要紧的一档：备份被删、权限被改、托管区结构异常时，
//   引擎拒绝替一次它根本没做的校验背书 —— 客户端也不许把它显示成「通过」。
// · 必发键：checked / failures / undetermined / missing / verified / documents。
//   少任一 → fromJson 返回 nullopt（契约可能过旧），**不许回落成 0**。
// · `note` 可选：只有「没有可校验的文档」那一档引擎才给 note。
#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <optional>
#include <vector>

struct VerifyDocument {
    QString project;
    QString doc;
    bool ok = false;
    QString note;

    static VerifyDocument fromJson(const QJsonObject &o)
    {
        VerifyDocument d;
        d.project = o.value(QLatin1String("project")).toString();
        d.doc = o.value(QLatin1String("doc")).toString();
        d.ok = o.value(QLatin1String("ok")).toBool(false);
        d.note = o.value(QLatin1String("note")).toString();
        return d;
    }
};

struct VerifyEnvelope {
    int checked = 0;
    int failures = 0;
    int undetermined = 0;
    int missing = 0;
    bool verified = false;
    QString note; // 仅「没有可校验的文档」那一档有
    std::vector<VerifyDocument> documents;

    static std::optional<VerifyEnvelope> fromJson(const QJsonObject &o)
    {
        static const char *kRequired[] = { "checked", "failures", "undetermined", "missing", "verified",
            "documents" };
        for (const char *k : kRequired) {
            if (!o.contains(QLatin1String(k)))
                return std::nullopt;
        }
        VerifyEnvelope e;
        e.checked = o.value(QLatin1String("checked")).toInt();
        e.failures = o.value(QLatin1String("failures")).toInt();
        e.undetermined = o.value(QLatin1String("undetermined")).toInt();
        e.missing = o.value(QLatin1String("missing")).toInt();
        e.verified = o.value(QLatin1String("verified")).toBool(false);
        e.note = o.value(QLatin1String("note")).toString();
        for (const QJsonValue &v : o.value(QLatin1String("documents")).toArray()) {
            if (v.isObject())
                e.documents.push_back(VerifyDocument::fromJson(v.toObject()));
        }
        return e;
    }
};
