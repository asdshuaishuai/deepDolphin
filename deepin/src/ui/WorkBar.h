// WorkBar.h — 主工作条（内容区顶部；mac WorkBar.swift 对位）。
//
// 左段：范围选择器（图标 + DComboBox maxWidth 320，**不持状态**：激活 → go 回调）；
// 右段：DualTrackButtons。只在「引擎就绪且有项目」时出现。
#pragma once
#include "../logic/Scope.h"
#include <QWidget>
#include <functional>

namespace Dtk {
namespace Widget {
class DComboBox;
}
}
class DualTrackButtons;
class AppModel;

class WorkBar : public QWidget {
    Q_OBJECT
public:
    explicit WorkBar(QWidget *parent = nullptr);

    void refreshFrom(AppModel *model); // 范围选择器与双轨徽章回读（不持状态）
    void setGoHandler(std::function<void(Selection)> go) { m_go = go; }
    DualTrackButtons *dualTrack() const { return m_dual; }

private:
    Dtk::Widget::DComboBox *m_range = nullptr;
    DualTrackButtons *m_dual = nullptr;
    std::function<void(Selection)> m_go;
};
