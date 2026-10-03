#include "StatusEnvelope.h"
#include <QJsonArray>
#include <QJsonObject>

std::optional<StatusEnvelope> StatusEnvelope::decodeEnvelopeOrBare(const QJsonDocument &doc)
{
    if (!doc.isObject())
        return std::nullopt;
    const QJsonObject top = doc.object();

    StatusEnvelope env;

    // ── 恒三键 envelope（现行引擎）──
    if (top.contains(QLatin1String("projects"))) {
        if (!top.value(QLatin1String("projects")).isArray())
            return std::nullopt;
        for (const QJsonValue &v : top.value(QLatin1String("projects")).toArray()) {
            if (!v.isObject())
                return std::nullopt;
            auto p = ProjectStatus::fromJson(v.toObject());
            if (!p)
                return std::nullopt; // 任一条目缺键 = 整个 envelope 解码失败（CONTRACT §2.1）
            env.projects.push_back(std::move(*p));
        }
        const QJsonValue summary = top.value(QLatin1String("summary"));
        if (summary.isObject())
            env.summary = EngineSummary::fromJson(summary.toObject());
        const QJsonValue lang = top.value(QLatin1String("language"));
        if (lang.isString())
            env.language = lang.toString();
        return env;
    }

    // ── 旧引擎裸对象（SPEC §2）：单个 ProjectStatus 条目 ──
    auto single = ProjectStatus::fromJson(top);
    if (!single)
        return std::nullopt;
    env.projects.push_back(std::move(*single));
    return env;
}
