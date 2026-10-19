// ArchDialog.h — 架构图窗口（mac ArchPage 对位，批 D2）。
//
// 【为什么是独立窗口而不是页面】
// mac 用 sheet 挂在详情页上；DDE 无 sheet 对位物，且架构图要的是**大画布**
// （69 个 shape 的真实场景塞进详情页宽度会被压成看不清的缩略图）。
// 独立 DDialog 是本平台的等价承载（照 AiSettingsDialog 范式）。
//
// 【单仓库锁定】项目名在入口（详情页）锁定，窗内**没有**切仓库的选择器
// —— 与 mac 同款纪律：仓库选择是「面板入口」的事，不是图页内的事。
//
// 【渲染归属】本页用**客户端自己的 Canvas**（批 D1 的 Qt QPainter 内核）把
// scene 契约画在应用内 —— 不导出 HTML、不开浏览器。引擎的 `render arch`
// 落盘 HTML 是**引擎层交付物**，由「导出」按钮显式触发（mac 同款）。
#pragma once
#include <DDialog>
#include <QPointer>
#include <QString>

DWIDGET_USE_NAMESPACE

class QLabel;
class QComboBox;
class FlatButton;
class ArchCanvasWidget;
class AppModel;

class ArchDialog : public DDialog {
    Q_OBJECT
public:
    ArchDialog(const QString &projectName, AppModel *model, QWidget *parent = nullptr);

signals:
    /// 请求打开一个导出文件（HTML 绝对路径）；交给上层用系统默认程序打开。
    void openExportedFile(const QString &path);

private:
    void reload();
    void refreshScene();
    void refreshFooter();
    void showError(const QString &text);
    void showReceipt(const QString &text);

    QString m_project;
    AppModel *m_model = nullptr;

    ArchCanvasWidget *m_canvas = nullptr;
    QComboBox *m_viewBox = nullptr;
    QLabel *m_errorBar = nullptr;
    QLabel *m_receipt = nullptr;
    FlatButton *m_openExport = nullptr;
    QLabel *m_warnBar = nullptr;
    QLabel *m_droppedBar = nullptr;
    QLabel *m_boundsWarn = nullptr;
    QLabel *m_chips = nullptr;
    QLabel *m_selected = nullptr;
    QString m_exportedPath;
};
