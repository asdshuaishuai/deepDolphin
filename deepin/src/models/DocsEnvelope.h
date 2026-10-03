// DocsEnvelope.h — `docs [项目...] --json` 载荷（CONTRACT §2.5）。
//
// 【红线】`project` 键**只在单项目调用时存在**（单项目=envelope，多项目=平铺）。
// unreadable[] 条目 = {project, unreadable:"A,B"}（逗号连接的存在但读不出的文件名），
// 恒发（空数组也在）。
#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <optional>
#include <vector>

struct DocFile {
    QString file;
    QString content;
    QString project; // CLI 追加的所属项目（单项目调用也有）

    static DocFile fromJson(const QJsonObject &o)
    {
        DocFile f;
        f.file = o.value(QLatin1String("file")).toString();
        f.content = o.value(QLatin1String("content")).toString();
        f.project = o.value(QLatin1String("project")).toString();
        return f;
    }
};

struct UnreadableDocs {
    QString project;
    QString unreadable; // "README.md,AGENTS.md"

    static UnreadableDocs fromJson(const QJsonObject &o)
    {
        UnreadableDocs u;
        u.project = o.value(QLatin1String("project")).toString();
        u.unreadable = o.value(QLatin1String("unreadable")).toString();
        return u;
    }
};

struct DocsEnvelope {
    std::optional<QString> project; // 仅单项目调用存在
    std::vector<DocFile> docs;
    std::vector<UnreadableDocs> unreadable;

    static std::optional<DocsEnvelope> fromJson(const QJsonObject &o)
    {
        if (!o.contains(QLatin1String("docs")) || !o.contains(QLatin1String("unreadable")))
            return std::nullopt;
        DocsEnvelope e;
        const QJsonValue p = o.value(QLatin1String("project"));
        if (p.isString())
            e.project = p.toString();
        for (const QJsonValue &v : o.value(QLatin1String("docs")).toArray()) {
            if (v.isObject())
                e.docs.push_back(DocFile::fromJson(v.toObject()));
        }
        for (const QJsonValue &v : o.value(QLatin1String("unreadable")).toArray()) {
            if (v.isObject())
                e.unreadable.push_back(UnreadableDocs::fromJson(v.toObject()));
        }
        return e;
    }
};
