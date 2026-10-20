// ToolsEnvelope.h — `tools --json` 输出（CONTRACT §2.7）。
//
// 每个工具 3 键 {name, description, params}——**没有** method/path/endpoint
//（引擎有测试锁定）；params 是逗号连接的字符串。
// ⚠ 旧名别名另有 2 键 {deprecated, replacedBy}（引擎 0.2.0 起）——
//   缺这两键 = 引擎没标废弃（老引擎）⇒ 缺省**不是**废弃，别把「没有标记」
//   读成「已废弃」。
#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <vector>

struct ToolSpec {
    QString name;
    QString description;
    QString params; // 逗号连接，如 "name,message"；无参工具为空串
    bool deprecated = false; ///< 引擎标了 deprecated:true（旧名别名，将移除）
    QString replacedBy;      ///< 继任工具名（引擎给；废弃项非空）

    /// 引擎给的**原始对象**（收敛后重序列化清单时保真用）。
    ///
    /// ⚠ 为什么留原始对象：不用上面的字段重拼一遍清单 —— 那是「在另一个出口
    ///   重写字段列表」，引擎新加字段时会**静默丢**（引擎 AGENTS.md 的纪律）。
    QJsonObject raw;

    static std::optional<ToolSpec> fromJson(const QJsonObject &o)
    {
        if (!o.contains(QLatin1String("name")) || !o.contains(QLatin1String("description"))
            || !o.contains(QLatin1String("params")))
            return std::nullopt;
        ToolSpec t;
        t.name = o.value(QLatin1String("name")).toString();
        t.description = o.value(QLatin1String("description")).toString();
        t.params = o.value(QLatin1String("params")).toString();
        t.deprecated = o.value(QLatin1String("deprecated")).toBool(false);
        t.replacedBy = o.value(QLatin1String("replacedBy")).toString();
        t.raw = o;
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

    /// **非废弃**的工具（AI 工具面的收敛口径）。
    std::vector<ToolSpec> activeTools() const
    {
        std::vector<ToolSpec> out;
        for (const ToolSpec &t : tools) {
            if (!t.deprecated)
                out.push_back(t);
        }
        return out;
    }

    /// 收敛后的清单 JSON（给系统提示词用）。
    ///
    /// ⚠ 与 `activeTools()` **同一口径** —— 提示词里有的工具，必须也在模型
    ///   可调用的工具表里；反过来也一样。否则模型会去调一个「提示词里有、
    ///   工具表里没有」的名字（或者反过来），两头不一致。
    QJsonObject activeJson() const
    {
        QJsonObject o;
        QJsonArray arr;
        for (const ToolSpec &t : tools) {
            if (!t.deprecated)
                arr.append(t.raw);
        }
        o.insert(QStringLiteral("tools"), arr);
        if (!note.isEmpty())
            o.insert(QStringLiteral("note"), note);
        return o;
    }

    /// 废弃项的**继任者是否都在非废弃面内**（收敛的自洽性）。
    ///
    /// ⚠ 为什么要有：若引擎把 A 标废弃、而它的继任者 B 也在面外（同样废弃 /
    ///   根本不存在）⇒ 模型**无路可走**（旧名不让调、新名不提供）⇒
    ///   这种不自洽要在客户端这一侧就暴露出来，而不是让模型自己撞。
    ///
    /// ⚠ 空 `replacedBy` 也算不覆盖：引擎标了废弃却不说继任者 ⇒ 客户端
    ///   无从知道该推荐谁。
    bool successorsCovered(QString *missing = nullptr) const
    {
        QStringList names;
        for (const ToolSpec &t : tools) {
            if (!t.deprecated)
                names << t.name;
        }
        bool ok = true;
        for (const ToolSpec &t : tools) {
            if (!t.deprecated)
                continue;
            if (t.replacedBy.isEmpty() || !names.contains(t.replacedBy)) {
                ok = false;
                if (missing)
                    *missing = t.name + QStringLiteral("→") + t.replacedBy;
            }
        }
        return ok;
    }
};
