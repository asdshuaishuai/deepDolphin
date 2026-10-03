// DashboardPage.h — 仪表盘页（mac DashboardView 对位，PLAN §4.2）。
//
// 区块：页头+summaryLine、DashboardFilterBar、KPI 网格（4 卡，宽 <980 折 2 列）、
// 项目卡网格（FlowLayout min 300）、语言分布卡、里程碑卡、近 7 天活跃卡。
// 四分支相位：failed →「仪表盘读不出来」；empty → 引导注册；loading → 「汇总项目群…」；
// content → 全量渲染。判定/披露全部走 logic 层产物，不内联口径。
#pragma once
#include "../../logic/DashFilter.h"
#include "../common/Card.h"
#include <QScrollArea>
#include <QWidget>

class QLabel;
class QPushButton;
class QGridLayout;
class QVBoxLayout;
class FlowLayout;
class SegmentedBar;
class LegendRow;
class DashboardFilterBar;
class ProjectProgressCard;
class AppModel;

class DashboardPage : public QWidget {
    Q_OBJECT
public:
    explicit DashboardPage(QWidget *parent = nullptr);
    void setModel(AppModel *model); // 挂信号自刷新

signals:
    void goProject(const QString &name);
    void briefRequested(); // 「项目群说明」（AI 层落地前的诚实降级在 PanelWindow 接）

private:
    void rebuild();
    QWidget *buildKpiCard(const QString &title, const QString &value, const QStringList &sub,
        bool tinted, QWidget *progressHost = nullptr);
    QWidget *buildLanguagesCard();
    QWidget *buildMilestonesCard();
    QWidget *buildActiveCard();

    AppModel *m_model = nullptr;
    DashFilter m_filter;

    QScrollArea *m_scroll = nullptr;
    QWidget *m_content = nullptr;
    QVBoxLayout *m_contentLayout = nullptr;

    QLabel *m_summary = nullptr;
    DashboardFilterBar *m_filterBar = nullptr;
    QGridLayout *m_kpiGrid = nullptr;
    QWidget *m_kpiHost = nullptr;
    FlowLayout *m_projectFlow = nullptr;
    QLabel *m_projectCount = nullptr;
    bool m_reindexing = false;
};
