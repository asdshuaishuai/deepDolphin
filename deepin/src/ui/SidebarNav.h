// SidebarNav.h — 侧栏（视图/仓库 分组 + 底部动作区，PLAN §2.6 / §4.1）。
//
// 结构纪律（对位 mac PanelView.swift）：
// · 分组一「视图」：仪表盘 / 看板（行尾待处理数）/ 里程碑（行尾 open+done）
// · 分组二「仓库（x/y）」：项目行（状态点 + 名称 + ●N 橙计数）
//   —— ⚠️ 计数是行内 QLabel，行内子控件全部 WA_TransparentForMouseEvents，
//      点击落回列表项（复刻侧对「.badge 吃点击」缺陷的等价防御；禁用 .badge 等价物）
// · 底部「添加 / 扫描项目」在列表**外**（它是动作不是导航项，放里面会清掉选中）
// · SidebarStatusStrip 状态条四文案：正在采集…/空闲/引擎连接失败/尚未刷新
// · 计数口径：看板=attention 数（**不受时间窗筛选**）；里程碑=open+done；
//   读不出来 → nullopt **不显示**（读不出来 ≠ 0）
#pragma once
#include "../logic/Liveness.h"
#include "../logic/Scope.h"
#include "../models/ProjectStatus.h"
#include <optional>
#include <QWidget>

class QLabel;
class QListWidget;
class QListWidgetItem;
class QPushButton;

namespace Dtk {
namespace Widget {
class DSearchEdit; // DTK6：Dtk::Widget 命名空间内
}
}

class SidebarNav : public QWidget {
    Q_OBJECT
public:
    explicit SidebarNav(QWidget *parent = nullptr);

    // 数据接入
    void setProjects(const QVector<ProjectStatus> &projects, int shown, int total);
    void setAttentionCount(std::optional<int> n); // 看板行尾（不受时间窗筛选）
    void setMilestoneCount(std::optional<int> n); // 里程碑行尾（open+done；读不出 → 不显示）
    void setStatusStrip(const QString &text, Liveness dot);

    void focusSearch(); // Ctrl+F 直达（系统 searchable 收不到外部焦点 → 自建框）

    Selection selection() const { return m_selection; }
    void select(Selection sel, bool emitSignal = false); // 外部同步高亮（不回发信号）

signals:
    void selectionChanged(Selection sel);
    void addOrScanClicked();
    void searchQueryChanged(const QString &text);

private:
    void rebuildProjectRows();
    int rowIndexOfSelection(Selection sel) const;
    void rebuildViewRowLabels();

    Dtk::Widget::DSearchEdit *m_search = nullptr;
    QListWidget *m_list = nullptr;
    QPushButton *m_addOrScan = nullptr;
    QLabel *m_statusDot = nullptr;
    QLabel *m_statusText = nullptr;

    QVector<ProjectStatus> m_projects;
    int m_shown = 0;
    int m_total = 0;
    std::optional<int> m_attention;
    std::optional<int> m_milestones;
    QString m_query;
    QString m_statusTextCache = QStringLiteral("尚未刷新");
    Liveness m_statusLiveness = Liveness::unknown;
    Selection m_selection;
};
