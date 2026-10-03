// ProjectEntry.h — `list --json` 裸数组条目 / `add` 输出（CONTRACT §3.5，8 键）。
// ⚠️ add --json **没有** created 键（cli.cj:1473-1475 只打印 entry.toJson()）；
// 重复注册不是错误、恒 exit 0；kind ∈ git|dir。
#pragma once
#include <QJsonObject>
#include <QString>
#include <QStringList>

struct ProjectEntry {
    QString id;
    QString name;
    QString path;
    QString kind;      // git|dir
    QString remote;
    QString addedAt;
    QStringList tags;
    bool disabled = false;

    static std::optional<ProjectEntry> fromJson(const QJsonObject &o)
    {
        static const char *kKeys[] = {
            "id", "name", "path", "kind", "remote", "addedAt", "tags", "disabled",
        };
        for (const char *k : kKeys) {
            if (!o.contains(QLatin1String(k)))
                return std::nullopt;
        }
        ProjectEntry e;
        e.id = o.value(QLatin1String("id")).toString();
        e.name = o.value(QLatin1String("name")).toString();
        e.path = o.value(QLatin1String("path")).toString();
        e.kind = o.value(QLatin1String("kind")).toString();
        e.remote = o.value(QLatin1String("remote")).toString();
        e.addedAt = o.value(QLatin1String("addedAt")).toString();
        for (const QJsonValue &v : o.value(QLatin1String("tags")).toArray())
            e.tags << v.toString();
        e.disabled = o.value(QLatin1String("disabled")).toBool();
        return e;
    }
};
