// SetupGuidePage.h — 引擎未找到页（CONTRACT §1.1 安装指引 + 「重新检测引擎」）。
// busy = 引擎发现链在跑（M0-2 异步 locate）：马上下结论会闪烁，用忙态如实表达"还在探"。
#pragma once
#include <QWidget>
#include <dspinner.h>

class QLabel;
class QPushButton;

DWIDGET_USE_NAMESPACE

class SetupGuidePage : public QWidget {
    Q_OBJECT
public:
    explicit SetupGuidePage(const QString &problem, QWidget *parent = nullptr);
    void setProblem(const QString &problem);
    void setBusy(bool busy);

signals:
    void redetectClicked();

private:
    QLabel *m_icon = nullptr;
    DSpinner *m_spinner = nullptr;
    QLabel *m_title = nullptr;
    QLabel *m_problem = nullptr;
    QPushButton *m_redetect = nullptr;
};
