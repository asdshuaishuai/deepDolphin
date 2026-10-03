// ScanResult.h — `scan [根目录...] [--depth N] [--git-only] --json`（CONTRACT §3.7）。
// truncated（20000 目录上限）/depthCapped（--depth 不够）/unreadable 三键恒发；
// depth 回显生效值；found − added = existing（contract-check.sh 对账等式）。
#pragma once
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <vector>

struct ScanCandidate {
    QString name;
    QString path;
    QString kind; // git|dir
    QString remote;
};

struct ScanResult {
    std::vector<ScanCandidate> candidates;
    int found = 0;
    int added = 0;
    int existing = 0;
    int dirsVisited = 0;
    bool truncated = false;
    bool depthCapped = false;
    QStringList unreadable;
    int depth = 0;

    static std::optional<ScanResult> fromJson(const QJsonObject &o)
    {
        static const char *kKeys[] = {
            "candidates", "found", "added", "existing", "dirsVisited",
            "truncated", "depthCapped", "unreadable", "depth",
        };
        for (const char *k : kKeys) {
            if (!o.contains(QLatin1String(k)))
                return std::nullopt;
        }
        ScanResult s;
        for (const QJsonValue &v : o.value(QLatin1String("candidates")).toArray()) {
            const QJsonObject c = v.toObject();
            ScanCandidate cand;
            cand.name = c.value(QLatin1String("name")).toString();
            cand.path = c.value(QLatin1String("path")).toString();
            cand.kind = c.value(QLatin1String("kind")).toString();
            cand.remote = c.value(QLatin1String("remote")).toString();
            s.candidates.push_back(cand);
        }
        s.found = o.value(QLatin1String("found")).toInt();
        s.added = o.value(QLatin1String("added")).toInt();
        s.existing = o.value(QLatin1String("existing")).toInt();
        s.dirsVisited = o.value(QLatin1String("dirsVisited")).toInt();
        s.truncated = o.value(QLatin1String("truncated")).toBool();
        s.depthCapped = o.value(QLatin1String("depthCapped")).toBool();
        for (const QJsonValue &v : o.value(QLatin1String("unreadable")).toArray())
            s.unreadable << v.toString();
        s.depth = o.value(QLatin1String("depth")).toInt();
        return s;
    }
};
