// DestructiveGuard.h — 破坏性确认判据与文案（mac DestructiveGuard.swift 对位，纯函数层）。
//
// 【红线】确认矩阵（SPEC §3.4）：
//   删除/放弃/批量更新/提交全部 → 确认；**达成/重开不确认**（可逆，弹确认教会确认疲劳）。
//   确认按钮说**会发生什么**（不是「确定」）；删除/放弃/提交染红，批量更新不染红（有备份可回滚）。
//   commitScope 的 staged 恒 0（引擎没有已暂存口径，不编造）。
#pragma once
#include "../models/ProjectStatus.h"
#include <QString>

namespace DestructiveGuard {

enum class Action { removeMilestone, dropMilestone, bulkUpdate, commitAll };

struct Spec {
    QString title;        // 必须点名具体对象
    QString body;         // 必须说清代价
    QString confirmLabel; // 「删除 / 放弃 / 全部更新 / 全部提交」
    bool destructive = true; // 确认按钮染红（批量更新不染红）
};

inline bool needsConfirmation(Action a)
{
    switch (a) {
    case Action::removeMilestone:
    case Action::dropMilestone:
    case Action::bulkUpdate:
    case Action::commitAll:
        return true;
    }
    return false;
}

// 主体（里程碑名/项目名）的安全写法：空名渲染「未命名」。
inline QString safeSubject(const QString &raw)
{
    const QString t = raw.trimmed();
    return t.isEmpty() ? QStringLiteral("未命名") : t;
}

inline QString titleFor(Action a, const QString &subject)
{
    switch (a) {
    case Action::removeMilestone:
        return QStringLiteral("删除里程碑「%1」？").arg(safeSubject(subject));
    case Action::dropMilestone:
        return QStringLiteral("放弃里程碑「%1」？").arg(safeSubject(subject));
    case Action::bulkUpdate:
        return QStringLiteral("更新全部项目？");
    case Action::commitAll:
        break;
    }
    return QStringLiteral("提交全部改动？");
}

inline QString confirmLabelFor(Action a)
{
    switch (a) {
    case Action::removeMilestone:
        return QStringLiteral("删除");
    case Action::dropMilestone:
        return QStringLiteral("放弃");
    case Action::bulkUpdate:
        return QStringLiteral("全部更新");
    case Action::commitAll:
        break;
    }
    return QStringLiteral("全部提交");
}

inline bool isDestructiveRole(Action a)
{
    switch (a) {
    case Action::removeMilestone:
    case Action::dropMilestone:
    case Action::commitAll:
        return true;
    case Action::bulkUpdate:
        break;
    }
    return false; // 有备份可回滚，不染红
}

inline QString messageFor(Action a, const QString &subject)
{
    switch (a) {
    case Action::removeMilestone:
        return QStringLiteral("「%1」会被直接删除。引擎不留备份、也没有回收站，删除后无法恢复。")
            .arg(safeSubject(subject));
    case Action::dropMilestone:
        return QStringLiteral("「%1」会被标记为已放弃，日后不再计入进行中的里程碑。之后可以重开，"
                              "但这次操作本身不会被记录成历史。")
            .arg(safeSubject(subject));
    case Action::bulkUpdate:
        return QStringLiteral("所有已注册项目的 README / AGENTS.md 等托管区域都会被改写。"
                              "每个文件在改写前会留备份，但这一步会覆盖多个仓库。");
    case Action::commitAll:
        break;
    }
    return QStringLiteral("工作区里所有未提交的内容会被合成一次提交，未跟踪文件也会包含在内。"
                          "提交信息可在之后 amend，但此刻它们会被写进历史。");
}

inline Spec spec(Action a, const QString &subject)
{
    return { titleFor(a, subject), messageFor(a, subject), confirmLabelFor(a),
        isDestructiveRole(a) };
}

// ── 提交范围（确认框里的具体数字）──
struct CommitScope {
    int trackedModified = 0;
    int untracked = 0;
    int staged = 0; // 恒 0：引擎没有已暂存口径，不编造
    int willCommit() const { return qMax(trackedModified + untracked, staged); }
};

inline CommitScope commitScope(const ProjectStatus &p)
{
    CommitScope s;
    s.trackedModified = qMax(0, p.userDirtyCount);
    s.untracked = qMax(0, p.untrackedCount);
    return s;
}

inline QString commitScopeText(const CommitScope &s)
{
    if (s.willCommit() == 0)
        return QStringLiteral("当前没有待提交的内容");
    QStringList parts;
    if (s.trackedModified > 0)
        parts << QStringLiteral("%1 个已改动").arg(s.trackedModified);
    if (s.untracked > 0)
        parts << QStringLiteral("%1 个未跟踪").arg(s.untracked);
    if (s.staged > 0)
        parts << QStringLiteral("%1 个已暂存").arg(s.staged);
    const QString list = parts.join(QStringLiteral("、"));
    if (s.untracked > 0)
        return QStringLiteral("将提交 %1 个文件（%2）。未跟踪文件会**首次进入版本历史**，"
                              "其中可能包含本不该提交的内容（如密钥、构建产物）。")
            .arg(s.willCommit())
            .arg(list);
    return QStringLiteral("将提交 %1 个文件（%2）。").arg(s.willCommit()).arg(list);
}

inline QString commitTitle(const QString &project)
{
    return QStringLiteral("在「%1」里提交全部改动？").arg(safeSubject(project));
}

inline QString commitMessage(const CommitScope &s)
{
    return commitScopeText(s)
        + QStringLiteral("提交之后可以用 amend 修改信息，但文件内容已进入历史。");
}

// 批量更新的范围描述（报范围，不按不可逆处理）。
inline QString bulkUpdateMessage(int projectCount, bool deep)
{
    const int n = qMax(projectCount, 0);
    if (n == 0)
        return QStringLiteral("当前没有已注册的项目，不会做任何事。");
    const QString one = n == 1 ? QStringLiteral("1 个项目") : QStringLiteral("%1 个项目").arg(n);
    const QString what = deep ? QStringLiteral("除浅更新外还会调用 AI 重新生成内容")
                              : QStringLiteral("读取 git 历史并改写托管区域（README / AGENTS.md 等）");
    return QStringLiteral("将对 %1 执行%2：%3。每个被改写的文件都会先留备份，所以可以回滚。")
        .arg(one, deep ? QStringLiteral("深更新") : QStringLiteral("浅更新"), what);
}

} // namespace DestructiveGuard
