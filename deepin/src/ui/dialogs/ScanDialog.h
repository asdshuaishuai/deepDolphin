// ScanDialog.h — 添加 / 扫描面板（mac ScanSheet 对位，480×440）。
//
// 顶部分段：添加单个项目 / 批量扫描目录；共用焦点绑定，切模式重送焦点。
// 路径判定走 logic/PathInput（橙 Label）；拖放取第一个**文件夹**；
// 完成后 refreshAll（AppModel::scan/addProject 内置）。
#pragma once
#include <DDialog>
#include <dtabbar.h>

class QLineEdit;
class QLabel;
class QStackedWidget;
class QSpinBox;

DWIDGET_USE_NAMESPACE

class ScanDialog : public DDialog {
    Q_OBJECT
public:
    explicit ScanDialog(QWidget *parent = nullptr);
    // 预填路径（desktop 项 MimeType=inode/directory：在面板中打开该目录）
    void presetPath(const QString &path);

signals:
    // addMode=true：add <path> [--name arg]；false：scan <path> --depth arg。
    // 调用方（PanelWindow）转 AppModel::addProject / AppModel::scan，并把
    // addFinished/scanFinished 的结果接回主窗口错误条。
    void submitted(bool addMode, const QString &path, const QString &arg);

private:
    void switchMode(int index);
    void submit();
    void pickPath();

    DTabBar *m_tabs = nullptr;
    QStackedWidget *m_stack = nullptr;
    QLineEdit *m_addPath = nullptr;
    QLineEdit *m_addName = nullptr;
    QLineEdit *m_scanRoot = nullptr;
    QSpinBox *m_depth = nullptr;
    QLabel *m_verdict = nullptr;
    QLabel *m_result = nullptr;
    bool m_addMode = true;
};
