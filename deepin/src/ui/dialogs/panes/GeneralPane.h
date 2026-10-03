// GeneralPane.h — 设置·通用页（开机自启 DSwitchButton；失败回滚开关到系统真实状态）。
#pragma once
#include <QWidget>
#include <DPushButton>

class QLabel;
namespace Dtk {
namespace Widget {
class DSwitchButton;
}
}

class GeneralPane : public QWidget {
    Q_OBJECT
public:
    explicit GeneralPane(QWidget *parent = nullptr);
    void reflectSystemState(bool enabled);

signals:
    void autostartToggled(bool enabled);

protected:
    void showEvent(QShowEvent *event) override;

private:
    Dtk::Widget::DSwitchButton *m_switch = nullptr;
    QLabel *m_status = nullptr;
    QLabel *m_logPath = nullptr;
    Dtk::Widget::DPushButton *m_logButton = nullptr;
};
