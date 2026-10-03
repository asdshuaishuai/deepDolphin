#include "DashboardData.h"
#include "EngineJson.h"
#include <QJsonObject>

namespace {
DashboardProjects parseProjects(const QJsonObject &o)
{
    DashboardProjects p;
    p.total = EngineJson::intAt(o, "total", 0);
    p.listed = EngineJson::intAt(o, "listed", 0);
    p.registered = EngineJson::intAt(o, "registered", 0);
    p.excludedDisabled = EngineJson::intAt(o, "excludedDisabled", 0);
    p.failed = EngineJson::intAt(o, "failed", 0);
    p.dirty = EngineJson::intAt(o, "dirty", 0);
    p.active7d = EngineJson::intAt(o, "active7d", 0);
    p.active30d = EngineJson::intAt(o, "active30d", 0);
    return p;
}

DashboardWork parseWork(const QJsonObject &o)
{
    DashboardWork w;
    w.branches = EngineJson::intAt(o, "branches", 0);
    w.mergeCandidates = EngineJson::intAt(o, "mergeCandidates", 0);
    w.untrackedFiles = EngineJson::intAt(o, "untrackedFiles", 0);
    w.stashes = EngineJson::intAt(o, "stashes", 0);
    return w;
}

MilestoneCounts parseMsCounts(const QJsonObject &o)
{
    MilestoneCounts c;
    c.open = EngineJson::intAt(o, "open", 0);
    c.done = EngineJson::intAt(o, "done", 0);
    c.dropped = EngineJson::intAt(o, "dropped", 0);
    c.unknown = EngineJson::intAt(o, "unknown", 0);
    c.other = EngineJson::intAt(o, "other", 0);
    c.storeHealth = EngineJson::strAt(o, "storeHealth");
    c.degraded = EngineJson::boolAt(o, "degraded");
    c.readCount = EngineJson::intAt(o, "readCount", 0);
    c.excludedDisabled = EngineJson::intAt(o, "excludedDisabled", 0);
    c.orphaned = EngineJson::intAt(o, "orphaned", 0);
    return c;
}
} // namespace

std::optional<DashboardData> DashboardData::fromJson(const QJsonObject &o)
{
    // dashboard 顶层必需键：projects/work/languages/milestones/activeProjects/fetchedAt
    // + 恒发披露四键 languagesTruncated/languagesTopCut/languagesFailed/languagesFailedReasons
    static const char *kKeys[] = {
        "projects", "work", "languages", "languagesTruncated", "languagesTopCut",
        "languagesFailed", "languagesFailedReasons", "milestones", "activeProjects",
        "fetchedAt",
    };
    for (const char *k : kKeys) {
        if (!o.contains(QLatin1String(k)))
            return std::nullopt;
    }

    DashboardData d;
    d.projects = parseProjects(o.value(QLatin1String("projects")).toObject());
    d.work = parseWork(o.value(QLatin1String("work")).toObject());

    for (const QJsonValue &v : EngineJson::arrAt(o, "languages")) {
        const QJsonObject l = v.toObject();
        d.languages.push_back(LanguageStat{ EngineJson::strAt(l, "language"),
                                            EngineJson::intAt(l, "count", 0) });
    }
    d.languagesTruncated = EngineJson::boolAt(o, "languagesTruncated");
    d.languagesTopCut = EngineJson::boolAt(o, "languagesTopCut");
    d.languagesFailed = EngineJson::intAt(o, "languagesFailed", 0);
    d.languagesFailedReasons = EngineJson::strArrAt(o, "languagesFailedReasons");

    const QJsonObject ms = o.value(QLatin1String("milestones")).toObject();
    d.milestones.counts = parseMsCounts(ms.value(QLatin1String("counts")).toObject());
    for (const QJsonValue &v : EngineJson::arrAt(ms, "items")) {
        auto m = Milestone::fromJson(v.toObject());
        if (!m)
            return std::nullopt; // 里程碑条目缺键 = 契约漂移
        d.milestones.items.push_back(std::move(*m));
    }

    for (const QJsonValue &v : EngineJson::arrAt(o, "activeProjects")) {
        const QJsonObject a = v.toObject();
        d.activeProjects.push_back(DashboardActiveProject{ EngineJson::strAt(a, "name"),
                                                           EngineJson::strAt(a, "lastCommitAgo"),
                                                           EngineJson::strAt(a, "headline") });
    }
    d.fetchedAt = EngineJson::strAt(o, "fetchedAt");
    return d;
}
