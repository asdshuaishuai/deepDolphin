#include "Router.h"
#include "../models/ProjectStatus.h"

RouteTarget routeTarget(const LaunchRoute &route, const std::vector<ProjectStatus> &projects,
                        bool loadedOnce)
{
    RouteTarget t;

    // 没给深链：默认视图（不依赖加载状态）
    if (route.project.isEmpty() && route.section.isEmpty()) {
        t.verdict = RouteVerdict::apply;
        t.section = QStringLiteral("dashboard");
        return t;
    }

    // --project 与 --section 同现以 project 为准（PLAN §2.4）
    if (!route.project.isEmpty()) {
        if (!loadedOnce) {
            t.verdict = RouteVerdict::pending; // 「不知道」，加载完补判
            return t;
        }
        for (const ProjectStatus &p : projects) {
            if (p.name == route.project) {
                t.verdict = RouteVerdict::apply;
                t.project = route.project;
                return t;
            }
        }
        // 「确实没有」：改道 dashboard + 说明（不许装作无事发生）
        t.verdict = RouteVerdict::missing;
        t.section = QStringLiteral("dashboard");
        t.notice = QStringLiteral("没有找到项目「%1」，已回到仪表盘。").arg(route.project);
        return t;
    }

    // 只有 --section：不依赖项目数据，直接落
    t.verdict = RouteVerdict::apply;
    t.section = Route::resolveSection(route.section);
    return t;
}
