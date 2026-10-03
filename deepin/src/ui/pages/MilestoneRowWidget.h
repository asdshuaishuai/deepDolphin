// MilestoneRowWidget.h — 里程碑行（mac MilestonesView.swift:227-418 对位；详情页复用同一组件）。
//
// 图标五态：done 绿✓ / dropped ✗ / **unknown 橙 ?** / open 蓝 circle-dashed / overdue 红！
// 行内直达按钮**不用 Menu**（List 行内 Menu 命中率不可靠）：QPushButton 三枚。
// 达成/重开**不弹确认**（可逆）；删除/放弃弹确认（DestructiveGuard）；
// UI 词 "open" → CLI "reopen" 由 PanelWindow/页面层转换。
#pragma once
#include "../../models/Milestone.h"
#include <QWidget>

class QLabel;

class MilestoneRowWidget : public QWidget {
    Q_OBJECT
public:
    explicit MilestoneRowWidget(QWidget *parent = nullptr);

    void setMilestone(const Milestone &m, bool showProjectName);

signals:
    void doneClicked(const QString &project, const QString &name);
    void reopenClicked(const QString &project, const QString &name);
    void dropClicked(const QString &project, const QString &name);
    void removeClicked(const QString &project, const QString &name);
    void openProject(const QString &project);

protected:
    void contextMenuEvent(QContextMenuEvent *event) override;

private:
    QString m_project;
    QString m_name;
    bool m_isOpen = false;
    bool m_isUnknown = false;
    bool m_isDropped = false;
};
