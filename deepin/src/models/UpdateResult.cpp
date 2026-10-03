#include "UpdateResult.h"
#include "EngineFailure.h"
#include "EngineJson.h"
#include <QJsonObject>

DocChange DocChange::fromJson(const QJsonObject &o)
{
    DocChange d;
    d.file = EngineJson::strAt(o, "file");
    d.changed = EngineJson::boolAt(o, "changed");
    d.created = EngineJson::boolAt(o, "created");
    const QJsonValue pv = EngineJson::take(o, "preview");
    if (pv.isString())
        d.preview = pv.toString();
    d.backup = EngineJson::strAt(o, "backup"); // 恒发，空串=没有备份（不是「不知道」）
    return d;
}

namespace {
// 共同基座 9 键：ok, mode, projectId, project, provider, providerLabel, docs, journalEntry, at
bool fillBase(const QJsonObject &o, UpdateResultBase &b)
{
    static const char *kKeys[] = {
        "ok", "mode", "projectId", "project", "provider", "providerLabel",
        "docs", "journalEntry", "at",
    };
    for (const char *k : kKeys) {
        if (!o.contains(QLatin1String(k)))
            return false;
    }
    b.ok = EngineJson::boolAt(o, "ok");
    b.mode = EngineJson::strAt(o, "mode");
    b.projectId = EngineJson::strAt(o, "projectId");
    b.project = EngineJson::strAt(o, "project");
    b.provider = EngineJson::strAt(o, "provider");
    b.providerLabel = EngineJson::strAt(o, "providerLabel");
    for (const QJsonValue &v : EngineJson::arrAt(o, "docs")) {
        if (v.isObject())
            b.docs.push_back(DocChange::fromJson(v.toObject()));
    }
    const QJsonValue je = EngineJson::take(o, "journalEntry");
    if (je.isObject())
        b.journalEntry = JournalEntry::fromJson(je.toObject());
    b.at = EngineJson::strAt(o, "at");
    return true;
}
} // namespace

UpdateResultAny decodeUpdateResultEntry(const QJsonObject &o)
{
    const QString mode = EngineJson::strAt(o, "mode");
    if (mode == QLatin1String("shallow")) {
        // shallow 专属四键必须齐：deep 载荷喂进来必须被拒（缺这四键 → 失败条目）
        static const char *kShallowOnly[] = {
            "branchCount", "repoBranchCount", "branchCountTruncated", "commitCount",
        };
        for (const char *k : kShallowOnly) {
            if (!o.contains(QLatin1String(k)))
                return UpdateFailureEntry{ EngineFailure::reason(QJsonDocument(o), 1) };
        }
        ShallowUpdateResult r;
        if (!fillBase(o, r))
            return UpdateFailureEntry{ EngineFailure::reason(QJsonDocument(o), 1) };
        r.branchCount = EngineJson::intAt(o, "branchCount", 0);
        r.repoBranchCount = EngineJson::intAt(o, "repoBranchCount", -1);
        r.branchCountTruncated = EngineJson::boolAt(o, "branchCountTruncated");
        r.commitCount = EngineJson::intAt(o, "commitCount", 0);
        return r;
    }
    if (mode == QLatin1String("deep")) {
        static const char *kDeepOnly[] = { "highlights" };
        for (const char *k : kDeepOnly) {
            if (!o.contains(QLatin1String(k)))
                return UpdateFailureEntry{ EngineFailure::reason(QJsonDocument(o), 1) };
        }
        DeepUpdateResult r;
        if (!fillBase(o, r))
            return UpdateFailureEntry{ EngineFailure::reason(QJsonDocument(o), 1) };
        r.highlights = EngineJson::strArrAt(o, "highlights");
        return r;
    }
    // 没有 mode：不是结果条目，按失败条目解读（§4.1 形状①②）
    return UpdateFailureEntry{ EngineFailure::reason(QJsonDocument(o), 1) };
}

UpdateAllEnvelope UpdateAllEnvelope::decode(const QJsonDocument &doc)
{
    UpdateAllEnvelope env;
    if (!doc.isObject())
        return env;
    const QJsonObject top = doc.object();

    // 单项目 → 裸结果对象（不包 envelope）
    if (!top.contains(QLatin1String("results"))) {
        env.results.push_back(decodeUpdateResultEntry(top));
        env.count = 1;
        if (std::holds_alternative<UpdateFailureEntry>(env.results.front()))
            env.failed = 1;
        else
            env.succeeded = 1;
        return env;
    }

    for (const QJsonValue &v : EngineJson::arrAt(top, "results")) {
        if (!v.isObject())
            continue;
        const QJsonObject entry = v.toObject();
        // 失败判定逐字对齐引擎 hasErrorOrCode（有 ok 键 → 永远不算失败）
        if (EngineJson::hasCodeOrError(entry) && !entry.contains(QLatin1String("mode"))) {
            env.results.push_back(
                UpdateFailureEntry{ EngineFailure::reason(QJsonDocument(entry), 1) });
            ++env.failed;
            continue;
        }
        UpdateResultAny r = decodeUpdateResultEntry(entry);
        if (std::holds_alternative<UpdateFailureEntry>(r))
            ++env.failed;
        else
            ++env.succeeded;
        env.results.push_back(std::move(r));
    }
    // 个数优先取引擎自己写的（引擎漏记时才退回本端计数）
    env.count = EngineJson::intAt(top, "count", static_cast<int>(env.results.size()));
    env.failed = EngineJson::intAt(top, "failed", env.failed);
    env.succeeded = EngineJson::intAt(top, "succeeded", env.succeeded);
    return env;
}
