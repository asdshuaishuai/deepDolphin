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
#include "../../../logic/EngineDoctor.h"
#include <QWidget>
#include <DPushButton>

class QLabel;
class QWidget;
class AppModel;
namespace Dtk {
namespace Widget {
class DSwitchButton;
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

    AppModel *m_model = nullptr;
    Dtk::Widget::DSwitchButton *m_switch = nullptr;
    QLabel *m_status = nullptr;
    QLabel *m_logPath = nullptr;
    Dtk::Widget::DPushButton *m_logButton = nullptr;
    Dtk::Widget::DPushButton *m_doctorButton = nullptr;
    QLabel *m_doctorSummary = nullptr;
    QWidget *m_doctorBody = nullptr; ///< 检查项逐行容器（由 applyDoctorReport 重建）
};
