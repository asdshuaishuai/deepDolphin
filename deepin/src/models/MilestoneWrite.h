// MilestoneWrite.h — `milestone add|done|drop|reopen|remove --json` 输出（CONTRACT §3.8）。
//
// · add → {project, milestone(9 键 Milestone.toJson **含 id**), created}
//   —— 只有这条路径的里程碑带 id；读取出口剥掉它。
// · done|drop|reopen → {project, milestone:<名称字符串>, requested, status(实际生效), applied}
//   applied:false = 写入被「同名 tag 已存在即自动 done」规则压回（如请求 reopen 仍 done）。
// · remove → {project, milestone, removed:true}
// · 目标不存在 → stdout 打 {error:true, code:"MILESTONE_NOT_FOUND", message} + exit 1
//   （errJson：error 是布尔 true，不是字符串）—— 由 EngineFailure/EngineError 分类。
#pragma once
#include "Milestone.h"
#include <QJsonObject>
#include <QString>

struct MilestoneAddResult {
    QString project;
    Milestone milestone;  // 9 键含 id（id 在 Milestone::fromJson 里顺带收）
    bool created = false;

    static std::optional<MilestoneAddResult> fromJson(const QJsonObject &o)
    {
        if (!o.contains(QLatin1String("project")) || !o.contains(QLatin1String("milestone"))
            || !o.contains(QLatin1String("created")))
            return std::nullopt;
        auto m = Milestone::fromJson(o.value(QLatin1String("milestone")).toObject());
        if (!m)
            return std::nullopt;
        MilestoneAddResult r;
        r.project = o.value(QLatin1String("project")).toString();
        r.milestone = std::move(*m);
        r.created = o.value(QLatin1String("created")).toBool();
        return r;
    }
};

struct MilestoneActionResult {
    QString project;
    QString milestone;     // 里程碑**名称字符串**
    QString requested;     // 请求的动作（done|drop|reopen）
    QString status;        // 实际生效状态
    bool applied = false;  // false = 被 tag 自动达成规则压回

    static std::optional<MilestoneActionResult> fromJson(const QJsonObject &o)
    {
        static const char *kKeys[] = { "project", "milestone", "requested", "status", "applied" };
        for (const char *k : kKeys) {
            if (!o.contains(QLatin1String(k)))
                return std::nullopt;
        }
        MilestoneActionResult r;
        r.project = o.value(QLatin1String("project")).toString();
        r.milestone = o.value(QLatin1String("milestone")).toString();
        r.requested = o.value(QLatin1String("requested")).toString();
        r.status = o.value(QLatin1String("status")).toString();
        r.applied = o.value(QLatin1String("applied")).toBool();
        return r;
    }
};

struct MilestoneRemoveResult {
    QString project;
    QString milestone;
    bool removed = false;

    static std::optional<MilestoneRemoveResult> fromJson(const QJsonObject &o)
    {
        if (!o.contains(QLatin1String("project")) || !o.contains(QLatin1String("milestone"))
            || !o.contains(QLatin1String("removed")))
            return std::nullopt;
        MilestoneRemoveResult r;
        r.project = o.value(QLatin1String("project")).toString();
        r.milestone = o.value(QLatin1String("milestone")).toString();
        r.removed = o.value(QLatin1String("removed")).toBool();
        return r;
    }
};
