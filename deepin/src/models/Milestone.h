// Milestone.h — `milestone list --json` / dashboard.milestones.items 的条目（CONTRACT §2.3）。
//
// 【红线】**无 id**：存储主键被引擎在只读出口剥掉，动作只认 project+name；
// 客户端不许自己编 id（mac 版注释：LLM 会拿它当句柄传回去，注定失败）。
// 17 键恒发；-1 口径：commitsSince/daysToTarget 的 -1 = 读不出来/未设置，不是 0。
#pragma once
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <optional>
#include <vector>

struct Milestone {
    // 存储主键。**只读出口不发光**（剥在 kernel）；仅 milestone add 的输出含 id。
    // std::optional 明示「读取路径恒 nullopt」——不许拿它当动作句柄（动作只认 project+name）。
    std::optional<QString> id;
    QString projectId;
    QString name;
    QString description;
    QString targetDate;   // YYYY-MM-DD 或空串
    QString tag;
    QString status;       // open|done|dropped|unknown（生效状态；unknown = 读不出来）
    QString createdAt;
    QString completedAt;
    QString projectName;
    QString tagName;
    bool tagReached = false;
    int commitsSince = -1;          // -1 = 读不出来
    bool commitsSinceReadable = false;
    int daysToTarget = -1;          // 正=剩余、负=逾期 N 天、-1 = 未设置或日期无效
    bool overdue = false;
    bool gitReadable = false;
    QString unverifiedReason;       // 恒发：可读时空串

    static std::optional<Milestone> fromJson(const QJsonObject &o)
    {
        static const char *kKeys[] = {
            "projectId", "name", "description", "targetDate", "tag", "status",
            "createdAt", "completedAt", "projectName", "tagName", "tagReached",
            "commitsSince", "commitsSinceReadable", "daysToTarget", "overdue",
            "gitReadable", "unverifiedReason",
        };
        for (const char *k : kKeys) {
            if (!o.contains(QLatin1String(k)))
                return std::nullopt;
        }
        Milestone m;
        const QJsonValue mid = o.value(QLatin1String("id"));
        if (mid.isString())
            m.id = mid.toString(); // 仅 milestone add 输出有；读取出口没有
        m.projectId = o.value(QLatin1String("projectId")).toString();
        m.name = o.value(QLatin1String("name")).toString();
        m.description = o.value(QLatin1String("description")).toString();
        m.targetDate = o.value(QLatin1String("targetDate")).toString();
        m.tag = o.value(QLatin1String("tag")).toString();
        m.status = o.value(QLatin1String("status")).toString();
        m.createdAt = o.value(QLatin1String("createdAt")).toString();
        m.completedAt = o.value(QLatin1String("completedAt")).toString();
        m.projectName = o.value(QLatin1String("projectName")).toString();
        m.tagName = o.value(QLatin1String("tagName")).toString();
        m.tagReached = o.value(QLatin1String("tagReached")).toBool();
        m.commitsSince = o.value(QLatin1String("commitsSince")).toInt(-1);
        m.commitsSinceReadable = o.value(QLatin1String("commitsSinceReadable")).toBool();
        m.daysToTarget = o.value(QLatin1String("daysToTarget")).toInt(-1);
        m.overdue = o.value(QLatin1String("overdue")).toBool();
        m.gitReadable = o.value(QLatin1String("gitReadable")).toBool();
        m.unverifiedReason = o.value(QLatin1String("unverifiedReason")).toString();
        return m;
    }
};

// 孤儿条目（所属项目已 remove）：形状另形，这里**有** id（CONTRACT §2.3）。
struct OrphanMilestone {
    QString id;
    QString projectId;
    QString name;
    QString description;
    QString targetDate;
    QString status;
    bool orphaned = true;

    static std::optional<OrphanMilestone> fromJson(const QJsonObject &o)
    {
        if (!o.contains(QLatin1String("id")) || !o.contains(QLatin1String("projectId"))
            || !o.contains(QLatin1String("name")))
            return std::nullopt;
        OrphanMilestone m;
        m.id = o.value(QLatin1String("id")).toString();
        m.projectId = o.value(QLatin1String("projectId")).toString();
        m.name = o.value(QLatin1String("name")).toString();
        m.description = o.value(QLatin1String("description")).toString();
        m.targetDate = o.value(QLatin1String("targetDate")).toString();
        m.status = o.value(QLatin1String("status")).toString();
        m.orphaned = o.value(QLatin1String("orphaned")).toBool(true);
        return m;
    }
};

// `milestone list [项目] --json` envelope：{milestones[], storeHealth, readCount, orphaned[], excludedDisabled}
struct MilestonesEnvelope {
    std::vector<Milestone> milestones;
    QString storeHealth;
    int readCount = 0;
    std::vector<OrphanMilestone> orphaned;
    int excludedDisabled = 0;

    // 对账等式（dashboard.cj:453-457）：
    //   readCount = open+done+dropped+unknown+excludedDisabled+orphaned
    // 由 scripts/contract-check.sh 在真实引擎输出上核对。
    static std::optional<MilestonesEnvelope> fromJson(const QJsonObject &o)
    {
        static const char *kKeys[] = {
            "milestones", "storeHealth", "readCount", "orphaned", "excludedDisabled",
        };
        for (const char *k : kKeys) {
            if (!o.contains(QLatin1String(k)))
                return std::nullopt;
        }
        MilestonesEnvelope e;
        e.storeHealth = o.value(QLatin1String("storeHealth")).toString();
        e.readCount = o.value(QLatin1String("readCount")).toInt();
        e.excludedDisabled = o.value(QLatin1String("excludedDisabled")).toInt();
        for (const QJsonValue &v : o.value(QLatin1String("milestones")).toArray()) {
            if (!v.isObject())
                return std::nullopt;
            auto m = Milestone::fromJson(v.toObject());
            if (!m)
                return std::nullopt;
            e.milestones.push_back(std::move(*m));
        }
        for (const QJsonValue &v : o.value(QLatin1String("orphaned")).toArray()) {
            if (!v.isObject())
                continue;
            auto m = OrphanMilestone::fromJson(v.toObject());
            if (m)
                e.orphaned.push_back(std::move(*m));
        }
        return e;
    }
};
