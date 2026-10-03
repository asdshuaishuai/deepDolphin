// AiResultDialog.h — AI 结果统一弹窗（mac AIResultSheet 对位）。
//
// min 520×420 / ideal 720×620 **可缩放**；busy/error/正文三态；
// 复制 Markdown + 重新生成（onRegenerate 空 = 无重新生成按钮）+ 关闭。
#pragma once
#include <DDialog>
#include <functional>

class QLabel;
class MarkdownView;
class QPushButton;

DWIDGET_USE_NAMESPACE

class AiResultDialog : public DDialog {
    Q_OBJECT
public:
    AiResultDialog(QWidget *parent, const QString &title);

    void setState(const QString &state /*busy|error|body*/, const QString &text);
    void setMarkdown(const QString &md);
    void setRegenerate(std::function<void()> f); // 空 = 无重新生成按钮

private:
    QLabel *m_state = nullptr;
    MarkdownView *m_view = nullptr;
    QPushButton *m_regen = nullptr;
    std::function<void()> m_regenFn;
};
