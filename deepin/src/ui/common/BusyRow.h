// BusyRow.h — 忙态行（plan §3b 组件化：把「同一件事 N 种写法」收敛）。
//
// 原 5 处散装 busy 表达收成同一形状「DSpinner 转圈 + 一句正在做什么」（文案走
// SecondaryLabel 单点）：DualTrackButtons 的静默禁用、DashboardFilterBar 的按钮
// 换字「重新索引…」、TrayPopupWindow 的「读取中…」与行内「…」、PanelWindow 状态
// 条的「正在采集…」。文案传空 = 只转圈不说话（托盘行内/标题栏刷新钮等紧凑位）。
//
// 【动效纪律（plan §3c）】DGuiApplicationHelper::testAttribute(HasAnimations) 为假
// （系统关动画）时不 start()——转圈退化为静态弧，文案仍在，信息不丢；不另造
// 定时器伪造动画。
// 【口径边界】SetupGuidePage 的整页忙态（M0-2「正在检测引擎…」，28px spinner）不归
// 本组件，原样保留——那是安装指引的独立语义，不是行内忙。
// 【无 Q_OBJECT】纯呈现（EmptyState 同款）；有配对 .cpp，构造逻辑收在实现里。
#pragma once
#include <DSpinner> // 直接带头：DSpinner 在 using-namespace 下前向声明有歧义（AgentDialog.h 同款结论）
#include <QWidget>

class SecondaryLabel;

class BusyRow : public QWidget {
public:
    // 构造即忙（忙态件天生在忙）；text 为空 = 紧凑位只转圈。
    explicit BusyRow(const QString &text = QString(), QWidget *parent = nullptr);

    // true：显示并起转；false：停转并隐藏（调用方 reflect 回路逐次拨）。
    void setBusy(bool busy);

private:
    Dtk::Widget::DSpinner *m_spinner = nullptr;
    SecondaryLabel *m_label = nullptr;
};
