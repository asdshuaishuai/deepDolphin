// GeneralPane.h — 设置·通用页（开机自启 DSwitchButton；失败回滚开关到系统真实状态）。
//
// 【环境自检卡】引擎 `doctor --json` 的展示面。三处口径与判定层
//   logic/EngineDoctor 一一对应，**不许在视图层另立一套**：
//   · 「发现问题」不是「命令失败」—— 引擎 doctor 有问题时退出码是 1，
//     但 stdout 仍是合法 JSON。界面要显示的是「环境有 N 个问题」，
//     不是「引擎调用失败」。
//   · `result` 是自由文本（「OK」/「1 个失效」/「无」/「项目外」）——
//     界面上原样显示，**不判「非 OK 即坏」**。
//   · 引擎没发 `problems` 键时显示「问题数未知」，不回落成「0 个问题」。
#pragma once
#include "../../../logic/EngineConfig.h"
#include "../../../logic/EngineDoctor.h"
#include <QWidget>
#include <DPushButton>

class QLabel;
class QWidget;
class AppModel;
namespace Dtk {
namespace Widget {
class DSwitchButton;
class DLineEdit;
}
}

class GeneralPane : public QWidget {
    Q_OBJECT
public:
    explicit GeneralPane(AppModel *model, QWidget *parent = nullptr);
    void reflectSystemState(bool enabled);

signals:
    void autostartToggled(bool enabled);

protected:
    void showEvent(QShowEvent *event) override;

private:
    /// 自检报告落地到界面（判定层给档，视图层上色）。
    void applyDoctorReport(const EngineDoctor::Report &r);
    /// 引擎配置落地到界面（逐行重建 + 回填可改项）。
    void applyEngineConfig();
    /// 读取引擎配置（按钮与「打开本页自动读」共用一个入口）。
    /// ⚠ 单独抽成方法是有原因的：接线门要**分别**盯住「按钮接上了」与
    ///   「打开本页会自动读」两个调用点 —— 若两处都直接写
    ///   `m_model->loadEngineConfig()`，摘掉其中一处门照样绿（同名调用点互相顶替）。
    void reloadEngineConfig();

    AppModel *m_model = nullptr;
    Dtk::Widget::DSwitchButton *m_switch = nullptr;
    QLabel *m_status = nullptr;
    QLabel *m_logPath = nullptr;
    Dtk::Widget::DPushButton *m_logButton = nullptr;
    Dtk::Widget::DPushButton *m_doctorButton = nullptr;
    QLabel *m_doctorSummary = nullptr;
    QWidget *m_doctorBody = nullptr; ///< 检查项逐行容器（由 applyDoctorReport 重建）
    Dtk::Widget::DPushButton *m_configButton = nullptr;
    QLabel *m_configError = nullptr;
    QWidget *m_configBody = nullptr;    ///< 只读项逐行容器（由 applyEngineConfig 重建）
    Dtk::Widget::DLineEdit *m_shallowInput = nullptr; ///< 浅更新分支上限（可改）
    Dtk::Widget::DLineEdit *m_backupInput = nullptr;  ///< 文档备份份数（可改）
    /// 用户**手改过**输入框（还没写回引擎）。
    /// ⚠ 不记这个的话：点「应用」写回第一个键 → 引擎配置重读 → 把用户刚填的
    ///   **第二个还没写回去的值冲掉** → 用户以为「改了没用」而反复点。
    bool m_configInputsDirty = false;
};
