// AiSettingsPane.h — 设置·AI 页（纯呈现；草稿 AIConfig 由父层持有，只有一处真身）。
//
// 【红线】切 provider：清 model、清过滤词、baseURL 重置为目录 api；provider 只列
// 有端点前 40 家（PROVIDER_PICKER_MAX）+ 恒发披露原文 + 当前 provider 不在列表时追加兜底；
// key 用 DPasswordEdit（ollama placeholder「本地服务通常无需 Key」）；测试连接按钮转圈。
#pragma once
#include <DComboBox>
#include <DLineEdit>
#include <DPasswordEdit>
#include <DPushButton>
#include <QLabel>
#include "../../../ai/AIConfig.h"
#include <QWidget>

class QComboBox;
class QLineEdit;
class QLabel;
class QPushButton;

class AiSettingsPane : public QWidget {
    Q_OBJECT
public:
    explicit AiSettingsPane(QWidget *parent = nullptr);

    void setDraft(const AIConfig &draft); // 父层把草稿塞进来（UI 刷新）
    AIConfig draft() const;               // 从控件回读（含未保存的 key 输入）
    void setTestResult(bool ok, const QString &message);
    void setTestBusy(bool busy);

signals:
    void dirty();        // 任一字段变化（父层据以启用「保存」）
    void saveTested();   // 测试完成（父层据以刷新 draft）

private:
    void rebuildProviderOptions(const QString &currentId);
    void rebuildModelOptions();
    void reflectProviderMeta();

    DTK_WIDGET_NAMESPACE::DComboBox *m_provider = nullptr;
    QLabel *m_providerNote = nullptr;
    QLabel *m_endpoint = nullptr;
    DTK_WIDGET_NAMESPACE::DLineEdit *m_modelFilter = nullptr;
    DTK_WIDGET_NAMESPACE::DComboBox *m_model = nullptr;
    QLabel *m_badges = nullptr;
    DTK_WIDGET_NAMESPACE::DLineEdit *m_modelManual = nullptr;
    DTK_WIDGET_NAMESPACE::DPasswordEdit *m_key = nullptr; // key 用 DTK 原生密码框（含眼睛切换）
    DTK_WIDGET_NAMESPACE::DLineEdit *m_baseURLOverride = nullptr;
    DTK_WIDGET_NAMESPACE::DPushButton *m_test = nullptr;
    QLabel *m_testResult = nullptr;
    QString m_filterWord;
};
