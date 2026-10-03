// Scope.h — 更新范围（Selection → scope 推导）。**纯函数层**（mac Scope.swift 对位）。
//
// 【红线】范围由 selection 推导，**没有第二真相源**；看板/里程碑页恒 all。
// pendingFor 需要 logic/Derived::needsAction（PLAN 里程碑 2），届时补上——
// 不在本文件里内联第二份 needsAction 判定。
#pragma once
#include <QSet>
#include <QString>
#include <vector>

class ProjectStatus;

// 主区当前显示什么（路由与侧栏共用的 selection 载体）
struct Selection {
    enum class Kind {
        dashboard,
        board,
        milestones,
        project, // projectName 生效
    };
    Kind kind = Kind::dashboard;
    QString projectName; // kind==project 时非空

    static Selection dashboard() { return { Kind::dashboard, QString() }; }
    static Selection board() { return { Kind::board, QString() }; }
    static Selection milestones() { return { Kind::milestones, QString() }; }
    static Selection project(const QString &name) { return { Kind::project, name }; }

    bool operator==(const Selection &o) const
    {
        return kind == o.kind && projectName == o.projectName;
    }
};

enum class UpdateScopeKind {
    all,
    project,
};

struct UpdateScope {
    UpdateScopeKind kind = UpdateScopeKind::all;
    QString name; // kind==project 时 = 项目名
};

UpdateScope scopeFromSelection(Selection sel);

// 「浅更新 · 全部 / · <项目>」——双轨按钮标题的范围段（深更新同构）
QString scopeTitle(UpdateScope scope);

// 范围内的待记录提交数（浅更新按钮上的徽章）。pendingCommits 是引擎实时计算的
//（flow/status.cj），客户端只消费：project → 该项目各分支之和；all → 全部之和。
int pendingFor(UpdateScope scope, const std::vector<ProjectStatus> &projects);


// 该范围是否正忙：busyAll 单锁；项目级看 busyProjects 集合
bool busyFor(UpdateScope scope, bool busyAll, const QSet<QString> &busyProjects);
