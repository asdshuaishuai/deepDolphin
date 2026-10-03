// BoardPage.h — 看板页（mac BoardView 对位，PLAN §4.3）。
//
// 「现在哪些项目要我动手」。QTreeWidget 四个 Section（待处理/活跃中/久未更新/其他）
// **不是横向四列**；列头计数与列出行数严格一致（同一份数据渲染两处，不许 prefix 截断）；
// 空列显示 BoardColumn.basis 判定依据原文；映射只读 liveness。
// 项目集合 = model.dashFilter.keeps（与仪表盘共用同一份筛选状态）。
#pragma once
#include <QTreeWidget>
#include <QWidget>

class AppModel;
class QLabel;

class BoardPage : public QWidget {
    Q_OBJECT
public:
    explicit BoardPage(QWidget *parent = nullptr);
    void setModel(AppModel *model);

signals:
    void goProject(const QString &name);
    void shallowFor(const QString &name);
    void briefFor(const QString &name);

private:
    void rebuild();

    AppModel *m_model = nullptr;
    QTreeWidget *m_tree = nullptr;
};
