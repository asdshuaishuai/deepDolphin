// TrayController.h — 托盘图标与速览弹窗的编排（mac MenuBarExtra/Dock 菜单对位，PLAN §6.1）。
//
// 纪律（对位 mac 的刻意设计）：
// · 右键菜单**只有两项动作**：「打开面板」「全部浅更新」+分隔+「退出」
//  （Linux 托盘必须补退出项——mac 弹窗 footer 有，记入 README）；
// · 「全部浅更新」先 bringToFront 再确认框（确认框在 AppModel 阶段接上）；
// · tooltip = menuTitle（「<N> ⚠︎<S>」/「<N> ●<D>」互斥、⚠︎ 优先，SPEC §1.7）。
//
// 数据对接：PLAN 签名是 refreshFrom(AppModel*)；AppModel 属 PLAN 里程碑 3。
// 本阶段以 TraySnapshot 纯数据承接，AppModel 落地后由它填 snapshot（见 README「偏差」）。
#pragma once
#include "../logic/Liveness.h"
#include <QColor>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QSystemTrayIcon>

class QSystemTrayIcon;
class QMenu;
class TrayPopupWindow;

// 速览弹窗的数据快照（AppModel 落地前由调用方直接填）
struct TraySnapshot {
    bool engineFound = true;
    QString engineProblem;   // engineFound=false 时的说明（安装指引文案）
    QString summaryLine;     // header 副标题（logic/DashboardScope 阶段产出）
    bool busy = false;       // 全量采集/更新中
    struct Row {
        QString name;
        QString subtitle;    // pulseLine /「<headAgo> · <statusLabel>」/ lastCommitAgo /「非 git 项目」
        int pending = 0;     // pendingCommits（蓝数字 + 迷你进度条）
        int dirty = -1;      // userDirtyCount（>0 → ●N 橙 chip；-1 读不出来不显示）
        QColor dot;          // 状态点颜色（红橙绿灰黄）
        bool unreadable = false; // 错误桩行：subtitle 显示红色原因
        bool rowBusy = false;    // 该项目正忙（busy 转圈）
    };
    QVector<Row> rows;       // 弹窗平铺 prefix(12)，>12 由弹窗加尾行
    int totalProjects = 0;   // 用于尾行「还有 N 个项目，打开面板查看…」
    Liveness refreshState = Liveness::unknown; // 弹窗状态条（正在采集/空闲/引擎连接失败/尚未刷新）
};

class TrayController : public QObject {
    Q_OBJECT
public:
    explicit TrayController(QObject *parent = nullptr);
    ~TrayController() override;

    // 刷新托盘：tooltip=menuTitle；图标按 tint 染色
    void refreshIcon(const QString &menuTitle, Liveness tint);

    // 刷新弹窗内容（壳阶段：直接填快照）
    void refreshFrom(const TraySnapshot &snapshot);

    bool isVisible() const;

signals:
    void openPanelRequested();   // 托盘激活/「打开面板」
    void updateAllRequested();   // 「全部浅更新」（先 bringToFront 再确认框）
    void openProjectRequested(const QString &name); // 弹窗项目行点击 → go(.project)+叫醒面板
    void refreshLightRequested(); // 弹窗打开时触发轻刷新（onShow 语义）
    void quitRequested();        // 退出（Linux 托盘必要补充）

private slots:
    void onActivated(QSystemTrayIcon::ActivationReason reason);

private:
    void buildMenu();

    QSystemTrayIcon *m_icon = nullptr;
    QMenu *m_menu = nullptr;
    TrayPopupWindow *m_popup = nullptr;
    QColor m_tint;
};
