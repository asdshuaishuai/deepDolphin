// DashboardFilterBar.h — 仪表盘筛选行（时间跨度三档 / 提交类型 / 重新索引）。
//
// 【红线】时间窗按 lastCommitAt 分档，help 写明口径；提交类型只影响卡内结构条不改 KPI；
// 无类型时禁用 + 说明原因（tooltip）。
#pragma once
#include "../../logic/DashFilter.h"
#include <QPushButton>
#include <QWidget>

#include <DComboBox>

DWIDGET_USE_NAMESPACE

class SegmentedButton;

class DashboardFilterBar : public QWidget {
    Q_OBJECT
public:
    explicit DashboardFilterBar(QWidget *parent = nullptr);

    void setFilter(const DashFilter &f);
    // 提交类型选项（排序去重，含首项「所有提交类型」）；无类型时禁用并给原因。
    void setTypeOptions(const QStringList &types, bool enabled, const QString &whyDisabled);
    void setReindexBusy(bool busy);

signals:
    void windowChanged(TimeWindow w);
    void typeChanged(const QString &type); // 空串 = 所有提交类型
    void reindexClicked();

private:
    void reflectWindow();

    SegmentedButton *m_windowSeg = nullptr; // 时间跨度三档（ui/common 单一实现，M3b）
    DComboBox *m_typeBox = nullptr;
    QPushButton *m_reindex = nullptr;
    TimeWindow m_window = TimeWindow::all;
};
