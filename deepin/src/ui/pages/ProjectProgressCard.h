// ProjectProgressCard.h — 仪表盘逐项目卡（mac DashboardParts.swift:146-395 对位）。
//
// 五行：名+状态词 / headline（unreadable 红）/ 里程碑完成度+分支名（primaryBranch→
// currentBranch 字符串→「无分支记录」三级回退）/ 提交结构（受类型筛选，空→「该筛选下
// 这个项目没有匹配的提交类型」，truncated→「样本」橙标）/ 最近提交+「进入管控 →」。
#pragma once
#include "../../logic/DashFilter.h"
#include "../../logic/DashboardScope.h"
#include <QWidget>

class QLabel;
class ProjectStatus;

class ProjectProgressCard : public QWidget {
    Q_OBJECT
public:
    explicit ProjectProgressCard(QWidget *parent = nullptr);

    // ms 为空指针 = 仪表盘里程碑明细里没有该项目的条目（渲染「未设里程碑」）。
    void setProject(const ProjectStatus &p, const DashFilter &filter, const MsTally *ms);

signals:
    void goProject(const QString &name);

protected:
    void mouseReleaseEvent(QMouseEvent *event) override;

private:
    QString m_name;
};
