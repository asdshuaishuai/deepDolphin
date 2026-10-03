// TrayPopupWindow.h — 托盘速览弹窗壳（mac MenuBarExtra 富弹窗对位，宽 TrayGeometry::popupWidth，PLAN §6/§2.7）。
//
// 结构（SPEC §1.7）：header「项目群进度」+ summaryLine + 刷新按钮
//   → 三态主体（引擎未找到→说明+重新检测；空/错误→原因+重试；项目行平铺 prefix(12)）
//   → footer「打开面板」「全部浅更新」（busy/空禁用）+「退出」。
//
// 【教训对位】mac 弹窗内 ScrollView 会塌缩成 0 高——本壳同样用**平铺**（不套滚动区）。
// 位置：X11 贴 QSystemTrayIcon::geometry()，取不到几何时落屏幕右上（PLAN §8 T4）。
#pragma once
#include "TrayController.h"
#include <QPushButton>
#include <QWidget>

class QLabel;
class QVBoxLayout;

class TrayPopupWindow : public QWidget {
    Q_OBJECT
public:
    explicit TrayPopupWindow(QWidget *parent = nullptr);

    void refreshFrom(const TraySnapshot &snapshot);

    // 弹出定位：贴托盘几何；geometry 无效（X11 之外）→ 屏幕右上
    void popupNear(const QRect &trayIconGeometry);

signals:
    void openProject(const QString &name);
    void openPanelRequested();
    void updateAllClicked();
    void refreshClicked();
    void quitClicked();

protected:
    void paintEvent(QPaintEvent *event) override;
    bool event(QEvent *event) override; // 失焦自动收起
    bool eventFilter(QObject *watched, QEvent *event) override; // 项目行点击

private:
    void rebuildBody(const TraySnapshot &snapshot);

    QLabel *m_title = nullptr;
    QLabel *m_summary = nullptr;
    QPushButton *m_refreshBtn = nullptr;
    QWidget *m_body = nullptr;
    QVBoxLayout *m_bodyLayout = nullptr;
    QPushButton *m_openPanelBtn = nullptr;
    QPushButton *m_updateAllBtn = nullptr;
    QPushButton *m_quitBtn = nullptr;
    TraySnapshot m_snapshot;
};
