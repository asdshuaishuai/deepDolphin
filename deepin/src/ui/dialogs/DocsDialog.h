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
//
// 【四语言 + 页内切换（批 AA）】本窗**自带语言选择器**（右上角）：
//   · 语言取值来自 `DocPages::Language`（zhCN / en / zhTW / ja，与 mac 的
//     `AppLanguage` 一一对齐），选完写进 `Settings` 的 `app.language` 键；
//   · 切换语言时，**随语言变的文案一起换**：类目分段名、窗口标题、底部出处、
//     按钮文字、正文本身 —— 不是只换正文（只换正文会留下「中文标题 + 英文正文」）。
//   · 存的语言键认不出时：回落到默认语言 + **说一句**（不静默吞掉），
//     判定在 `DocPages::resolveLanguage`（纯函数），提示语在判定层。
#pragma once
#include <DDialog>
#include <QPointer>
#include <QString>
#include <QStringList>

#include "../../logic/DocPages.h"

DWIDGET_USE_NAMESPACE

class QComboBox;
class QLabel;
class QTextBrowser;
class FlatButton;
class SegmentedButton;

class DocsDialog : public DDialog {
    Q_OBJECT
public:
    explicit DocsDialog(QWidget *parent = nullptr);

    /// 文档窗当前的**呈现值**（供无头探针用；**只读**，不改任何状态）。
    ///
    /// ⚠ 为什么要有这个出口：接线门是**源码扫描** —— 它能证明「代码里写了
    ///   `setButtonText`」，但**证明不了**「换语言后按钮真的变了」。这个出口
    ///   让探针能**真跑**一遍，看实际呈现（批 AA 的端到端判据）。
    ///
    /// ⚠ 顺序固定：**标题 / 关闭按钮 / 四个类目分段名 / 正文 / 底部说明**
    ///   （字段名与格式化归探针文件 `DocsDialogProbe` —— 文档窗里不许有
    ///   字符串字面量：用户可见文案全在判定层，四语言共用一份）。
    QStringList probeValues() const;

signals:
    /// 请求打开一个外部链接（仓库地址）。
    void openUrl(const QString &url);

private:
    void showKind(int index);
    void onSegment(int id);
    void onLanguagePicked(int index);

    /// 把「随语言变」的一切一起换掉（标题 / 分段名 / 按钮 / 正文 / 底部说明）。
    void applyLanguage();

    /// 底部说明行：语言设置坏掉时显示「已回落」提示，否则显示出处。
    void updateHint();

    SegmentedButton *m_segments = nullptr;
    QComboBox *m_langBox = nullptr;
    QTextBrowser *m_body = nullptr;
    QLabel *m_hint = nullptr;
    FlatButton *m_repo = nullptr;

    DocPages::Language m_language = DocPages::Language::zhCN;
    int m_kindIndex = 0;
    bool m_recovered = false;  ///< 存的语言键认不出，已回落到默认语言
    QString m_recoveredKey;    ///< 认不出的原值（提示里要把它说出来）
};
