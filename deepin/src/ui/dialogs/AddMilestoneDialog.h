// AddMilestoneDialog.h — 新建里程碑（mac AddMilestoneSheet 对位，440×340）。
//
// 红线：名称框 setFocus() 默认；日期默认今天+30 天；空 tag/date/desc **不发键**；
// 失败红字贴表单下**不关窗**；日期格式 yyyy-MM-dd。
#pragma once
#include <DDialog>
#include <QDate>

class QComboBox;
class QLineEdit;
class QTextEdit;
class QCheckBox;
class QDateEdit;
class QLabel;

DWIDGET_USE_NAMESPACE

class AddMilestoneDialog : public DDialog {
    Q_OBJECT
public:
    AddMilestoneDialog(QWidget *parent, const QStringList &projects, const QString &defaultProject);

    QString project() const;
    QString name() const;
    QString tag() const;      // 空串 = 不发键
    QString targetDate() const; // 空串 = 不发键（未勾选目标日期）
    QString desc() const;       // 空串 = 不发键

    // 失败红字贴表单下方（调用方不关窗重试）
    void setError(const QString &message);

private:
    QComboBox *m_project = nullptr;
    QLineEdit *m_name = nullptr;
    QLineEdit *m_tag = nullptr;
    QCheckBox *m_hasDate = nullptr;
    QDateEdit *m_date = nullptr;
    QTextEdit *m_desc = nullptr;
    QLabel *m_error = nullptr;
};
