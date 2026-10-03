#include "Scope.h"
#include "../models/ProjectStatus.h"


UpdateScope scopeFromSelection(Selection sel)
{
    UpdateScope s;
    if (sel.kind == Selection::Kind::project) {
        s.kind = UpdateScopeKind::project;
        s.name = sel.projectName;
    } else {
        s.kind = UpdateScopeKind::all; // 看板/里程碑/仪表盘页恒 all
    }
    return s;
}

QString scopeTitle(UpdateScope scope)
{
    if (scope.kind == UpdateScopeKind::project && !scope.name.isEmpty())
        return QStringLiteral("· %1").arg(scope.name);
    return QStringLiteral("· 全部");
}

bool busyFor(UpdateScope scope, bool busyAll, const QSet<QString> &busyProjects)
{
    if (busyAll)
        return true;
    if (scope.kind == UpdateScopeKind::project)
        return busyProjects.contains(scope.name);
    return false;
}

int pendingFor(UpdateScope scope, const std::vector<ProjectStatus> &projects)
{
    if (scope.kind == UpdateScopeKind::project) {
        for (const ProjectStatus &p : projects) {
            if (p.name != scope.name)
                continue;
            int sum = 0;
            for (const BranchStatus &b : p.branches)
                sum += qMax(0, b.pendingCommits);
            return sum;
        }
        return 0;
    }
    int total = 0;
    for (const ProjectStatus &p : projects) {
        for (const BranchStatus &b : p.branches)
            total += qMax(0, b.pendingCommits);
    }
    return total;
}

