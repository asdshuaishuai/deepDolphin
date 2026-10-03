// AiSettingsDialog.h — 设置窗口（mac GeneralSettingsView 对位，min 480×400，三页签）。
//
// 结构：header「设置」+ DTabBar（实测 libdtk6widget 6.7.47 无 DTabWidget → DTabBar +
// QStackedWidget）/ pane / footer。
// 【滚动归属逐页写死】通用/自动化两页套 QScrollArea；**AI 页不套**（其内容自滚，
// 再套外层会滚不动且把页脚顶出窗口——mac 实测 sheet 页脚超出窗口底的教训）。
// 页脚语义随页签：AI =「取消/保存（aiDirty 才可用）」；另两页只有「关闭」。
// 保存失败：红字贴页脚、不关窗、tab 强切回 AI；original 存补过 baseURL 后的那份。
#pragma once
#include "../../ai/AIConfig.h"
#include <DDialog>
#include <dtabbar.h>

class QStackedWidget;
class QLabel;
class SecretStore;
class AutomationPane;

DWIDGET_USE_NAMESPACE

class AiSettingsDialog : public DDialog {
    Q_OBJECT
public:
    explicit AiSettingsDialog(QWidget *parent = nullptr);
    AutomationPane *automationPane() const { return m_automationWidget; } // 供外部接 restartAutoTimer

private:
    void switchTab(int index);
    void saveAi();
    void refreshFooter();
    bool aiDirty() const;

    DTabBar *m_tabs = nullptr;
    QStackedWidget *m_stack = nullptr;
    QWidget *m_generalPane = nullptr;
    AutomationPane *m_automationWidget = nullptr;
    QWidget *m_aiPane = nullptr;
    QLabel *m_footerError = nullptr;

    AIConfig m_original;      // **补过 baseURL 之后**的那份（否则一打开恒 dirty）
    bool m_loadedOnce = false; // 设置加载一次性守卫
    bool m_keyPending = false; // libsecret 读在 worker 飞着（M0-3）：回填前不允许保存
    SecretStore *m_store = nullptr;
};
