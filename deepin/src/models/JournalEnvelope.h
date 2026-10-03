// JournalEnvelope.h — `journal [项目] [--branch B] [--limit N] --json` 载荷（CONTRACT §2.4）。
//
// windowExhausted：true = 窗口读到了文件头（更早处可能还有 → 反过来读）。
// branchWindowExhausted：对象，键=项目名，值 "none-in-window"|"window-full"。
#pragma once
#include "StatusTypes.h"
#include <QJsonObject>
#include <QMap>
#include <vector>

struct JournalEnvelope {
    std::vector<JournalEntry> entries;
    int limit = 20;        // 默认 20（cli.cj:2178）
    QString branches;      // "*"（未过滤）或分支名
    int projects = 0;      // 目标项目数
    int unparsableLines = 0;
    bool windowExhausted = false;
    QMap<QString, QString> branchWindowExhausted;

    static std::optional<JournalEnvelope> fromJson(const QJsonObject &o)
    {
        static const char *kKeys[] = {
            "entries", "limit", "branches", "projects", "unparsableLines",
            "windowExhausted", "branchWindowExhausted",
        };
        for (const char *k : kKeys) {
            if (!o.contains(QLatin1String(k)))
                return std::nullopt;
        }
        JournalEnvelope e;
        e.limit = o.value(QLatin1String("limit")).toInt(20);
        e.branches = o.value(QLatin1String("branches")).toString();
        e.projects = o.value(QLatin1String("projects")).toInt(0);
        e.unparsableLines = o.value(QLatin1String("unparsableLines")).toInt(0);
        e.windowExhausted = o.value(QLatin1String("windowExhausted")).toBool();
        const QJsonObject bw = o.value(QLatin1String("branchWindowExhausted")).toObject();
        for (auto it = bw.begin(); it != bw.end(); ++it)
            e.branchWindowExhausted.insert(it.key(), it.value().toString());
        for (const QJsonValue &v : o.value(QLatin1String("entries")).toArray()) {
            if (v.isObject())
                e.entries.push_back(JournalEntry::fromJson(v.toObject()));
        }
        return e;
    }
};
