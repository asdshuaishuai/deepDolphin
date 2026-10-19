// DocsDialog.h — 固定文档页窗（关于 / 帮助 / 开源感谢 / 更新日志）。
//
// 【对应 mac 的两处】mac 的「关于 / 帮助」是原生菜单栏开的两个独立窗口
// （`AboutHelpWindows.swift`），设置面板里另有四个文档区（`AppSettingsView`）。
// deepin 侧合成为一个窗 + 顶部分段切换四类目：
//   · mac 的两个原生窗口在 DDE 下没有对位物（deepin 面板不是原生菜单栏应用）；
//   · 四类内容**同源**（同一个 `DocPages::content`），分两个窗反而容易写出两份。
// 能力一致：四类文档都能读、能切换、能跳仓库。
//
// 【内容不在这里】正文全部来自 `logic/DocPages`（纯函数层）——
// 窗口只负责「取哪一类 + 怎么渲染」，不持有文案。
#pragma once
#include <DDialog>
#include <QPointer>
#include <QString>

DWIDGET_USE_NAMESPACE

class QLabel;
class QTextBrowser;
class FlatButton;
class SegmentedButton;

class DocsDialog : public DDialog {
    Q_OBJECT
public:
    explicit DocsDialog(QWidget *parent = nullptr);

signals:
    /// 请求打开一个外部链接（仓库地址）。
    void openUrl(const QString &url);

private:
    void showKind(int index);
    void onSegment(int id);

    SegmentedButton *m_segments = nullptr;
    QTextBrowser *m_body = nullptr;
    QLabel *m_hint = nullptr;
    FlatButton *m_repo = nullptr;
};
