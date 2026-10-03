// AutomationPane.h — 设置·自动化页（定时更新分段：关闭/1/3/6/12/24h）。
// 改完立即生效（autoHoursChanged → AppModel::restartAutoTimer），不经过保存按钮。
#pragma once
#include <QWidget>

class QLabel;
class SegmentedButton;

class AutomationPane : public QWidget {
    Q_OBJECT
public:
    explicit AutomationPane(QWidget *parent = nullptr);

signals:
    void autoHoursChanged(int hours);

private:
    void reflect(int hours);

    SegmentedButton *m_seg = nullptr; // 定时分段（ui/common 单一实现，M3b）
    QLabel *m_current = nullptr;
};
