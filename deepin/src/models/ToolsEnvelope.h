// ToolsEnvelope.h — `tools --json` 输出（CONTRACT §2.7）。
// 每个工具仅 3 键 {name, description, params}——**没有** method/path/endpoint
//（引擎有测试锁定）；params 是逗号连接的字符串；10 个工具见 CONTRACT §5.1。
#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <vector>

struct ToolSpec {
    QString name;
    QString description;
    QString params; // 逗号连接，如 "name,message"；无参工具为空串

    static std::optional<ToolSpec> fromJson(const QJsonObject &o)
    {
        if (!o.contains(QLatin1String("name")) || !o.contains(QLatin1String("description"))
            || !o.contains(QLatin1String("params")))
            return std::nullopt;
        ToolSpec t;
        t.name = o.value(QLatin1String("name")).toString();
        t.description = o.value(QLatin1String("description")).toString();
        t.params = o.value(QLatin1String("params")).toString();
        return t;
    }
};

struct ToolsEnvelope {
    std::vector<ToolSpec> tools;
    QString note;

    static std::optional<ToolsEnvelope> fromJson(const QJsonObject &o)
    {
        if (!o.contains(QLatin1String("tools")))
            return std::nullopt;
        ToolsEnvelope e;
        e.note = o.value(QLatin1String("note")).toString();
        for (const QJsonValue &v : o.value(QLatin1String("tools")).toArray()) {
            auto t = ToolSpec::fromJson(v.toObject());
            if (!t)
                return std::nullopt;
            e.tools.push_back(std::move(*t));
        }
        return e;
    }
};
