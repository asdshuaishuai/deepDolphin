// AutomationPane.h — 设置·自动化页（定时更新分段：关闭/1/3/6/12/24h + 提交后自动记进度）。
// 改完立即生效（autoHoursChanged → AppModel::restartAutoTimer），不经过保存按钮。
//
// 【钩子卡】引擎 `hook` 命令管的是往项目 .git/hooks 里装一段**托管块**：
//   块内由引擎维护，**块外是用户自己的逻辑**（实测 2026-10-19：install 保留用户
//   原有内容并追加在后面，uninstall 只删托管块）—— 所以这里能放心提供装/卸入口。
#pragma once
#include "../../../logic/EngineHook.h"
#include <DPushButton>
#include <QWidget>

class QLabel;
class AppModel;
class SegmentedButton;

class AutomationPane : public QWidget {
    Q_OBJECT
public:
    explicit AutomationPane(AppModel *model, QWidget *parent = nullptr);

signals:
    void autoHoursChanged(int hours);

private:
    void reflect(int hours);

protected:
    void showEvent(QShowEvent *event) override;
    /// 钩子状态落地到界面（概览 + 逐项目明细）。
    void applyHookStatus();
    /// 批量动作进行中 → 按钮禁用 + 状态行说「正在…」。
    void applyHookBusy();

    AppModel *m_model = nullptr;
    SegmentedButton *m_seg = nullptr; // 定时分段（ui/common 单一实现，M3b）
    QLabel *m_current = nullptr;
    // ── 钩子卡 ──
    QLabel *m_hookSummary = nullptr;
    QLabel *m_hookDetail = nullptr;
    Dtk::Widget::DPushButton *m_hookInstallButton = nullptr;
    Dtk::Widget::DPushButton *m_hookUninstallButton = nullptr;
};
