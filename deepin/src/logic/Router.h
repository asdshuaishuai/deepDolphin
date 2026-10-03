// Router.h — 路由裁决：深链意图 × 当前数据 → 目标（mac Router.swift 对位）。
//
// 区分「不知道」（pending：项目群还没加载完，加载完补判）
// 与「确实没有」（missing：改道 dashboard + routeNotice 说明）。
#pragma once
#include "Route.h"
#include <vector>

class ProjectStatus; // models/ProjectStatus.h（避免逻辑层反向拉模型头）
struct LaunchRoute;

enum class RouteVerdict {
    apply,   // 可落地
    pending, // 还没加载完，不能判（加载完后再来问一次）
    missing, // 加载完了且目标不存在（改道 dashboard + notice）
};

struct RouteTarget {
    RouteVerdict verdict = RouteVerdict::apply;
    QString project;   // verdict==apply 且目标是项目时非空
    QString section;   // "dashboard"|"board"|"milestones"（归一后）
    QString notice;    // verdict==missing 时的改道说明
};

RouteTarget routeTarget(const LaunchRoute &route, const std::vector<ProjectStatus> &projects,
                        bool loadedOnce);
