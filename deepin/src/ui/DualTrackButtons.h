// DualTrackButtons.h — 浅/深双轨按钮（mac AIIntegration.swift:306-374 对位）。
//
// 【红线】标题**必须带范围**（「浅更新 · 全部 / · <项目>」）；浅更新 pending>0 时显示
// 待记录徽章（白字绿底胶囊，实时值按范围取）；深更新 tooltip 写明「重写托管文档：
// README · AGENTS · CLAUDE。这一步会改写你的文件」；disabled = busyFor(范围)。
// 实测 libdtk6widget 6.7.47 无 DDualButton/DPushButton → 两枚 QPushButton（flat），
// 需要强调色用 DSuggestButton（已实测存在）——结论记入 deepin/README.md。
#pragma once
#include "../logic/Scope.h"
#include <QPushButton>
#include <DPushButton>
#include <DSuggestButton>
#include <QWidget>

class QLabel;
class BusyRow;

DWIDGET_USE_NAMESPACE

class DualTrackButtons : public QWidget {
    Q_OBJECT
public:
    explicit DualTrackButtons(QWidget *parent = nullptr);

    void setScope(UpdateScope scope);
    void setPending(int pending);
    void setBusy(bool busy);

signals:
    void shallowClicked();
    void deepClicked();

private:
    void reflect();

    UpdateScope m_scope;
    int m_pending = 0;
    bool m_busy = false;
    DSuggestButton *m_shallow = nullptr;
    DPushButton *m_deep = nullptr;
    QLabel *m_badge = nullptr;
    BusyRow *m_busyRow = nullptr; // 忙态行（BusyRow 单点）：转圈 + 文案，原「静默禁用」收编
};
