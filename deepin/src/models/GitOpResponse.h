// GitOpResponse.h — `git <pull|push|commit|stash|unstash|fetch> [项目] [--message M] --json`
// 条目：{op, ok, output, project}（GitOpResult.toJson 3 键 + project）。
// 【红线】白名单制 6 操作；commit 缺 --message → ok:false（不抛错）；
// 任一项目失败整体 exit 1 —— 载荷与退出码都要看。
#pragma once
#include <QJsonObject>
#include <QString>

struct GitOpResponse {
    QString op;
    bool ok = false;
    QString output;
    QString project;

    static std::optional<GitOpResponse> fromJson(const QJsonObject &o)
    {
        if (!o.contains(QLatin1String("op")) || !o.contains(QLatin1String("ok"))
            || !o.contains(QLatin1String("output")))
            return std::nullopt;
        GitOpResponse g;
        g.op = o.value(QLatin1String("op")).toString();
        g.ok = o.value(QLatin1String("ok")).toBool();
        g.output = o.value(QLatin1String("output")).toString();
        g.project = o.value(QLatin1String("project")).toString();
        return g;
    }
};
