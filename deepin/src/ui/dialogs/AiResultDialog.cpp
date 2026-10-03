#include "AiResultDialog.h"
#include "../DesignTokens.h"
#include "../common/MarkdownView.h"
#include <QApplication>
#include <QClipboard>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>

AiResultDialog::AiResultDialog(QWidget *parent, const QString &title)
    : DDialog(parent)
{
    setWindowTitle(title);
    resize(720, 620);
    setMinimumSize(520, 420); // 固定尺寸曾让长报告读不完且关不掉——必须可缩放
    setOnButtonClickedClose(false);

    auto *content = new QWidget(this);
    auto *v = new QVBoxLayout(content);
    v->setContentsMargins(0, 0, 0, 0);
    v->setSpacing(DS::Spacing::sm);

    m_state = new QLabel(content);
    m_state->setWordWrap(true);
    m_state->hide();
    v->addWidget(m_state);

    m_view = new MarkdownView(content);
    v->addWidget(m_view, 1);

    addContent(content);
    // 复制 Markdown + 关闭（重新生成按钮按需插入）。
    // 不归 FlatButton（遗留，M3b-FlatButton）：此钮插进 DDialog 按钮行，观感由
    // DDialog/样式统一管（与「复制/关闭」同排同款），换成平钮会与邻钮割裂
    m_regen = new QPushButton(QStringLiteral("重新生成"), this);
    addButton(QStringLiteral("复制 Markdown"), false);
    insertButton(1, m_regen, false);
    addButton(QStringLiteral("关闭"), true);

    connect(this, &DDialog::buttonClicked, this, [this](int, const QString &text) {
        if (text == QStringLiteral("复制 Markdown")) {
            QApplication::clipboard()->setText(m_view->toPlainText());
        } else if (text == QStringLiteral("重新生成")) {
            if (m_regenFn)
                m_regenFn(); // **必须真传**（nil 会静默无反应——此处按钮已藏）
        } else if (text == QStringLiteral("关闭")) {
            accept();
        }
    });
    setRegenerate({});
}

void AiResultDialog::setState(const QString &state, const QString &text)
{
    if (state == QLatin1String("busy")) {
        m_state->setText(text.isEmpty() ? QStringLiteral("生成中…") : text);
        m_state->show();
        m_view->hide();
    } else if (state == QLatin1String("error")) {
        m_state->setText(QStringLiteral("✗ ") + text);
        m_state->setStyleSheet(
            QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::red).name()));
        m_state->show();
        m_view->hide();
    } else {
        m_state->hide();
        m_view->show();
        m_view->setMarkdownText(text);
    }
}

void AiResultDialog::setMarkdown(const QString &md)
{
    setState(QStringLiteral("body"), md);
}

void AiResultDialog::setRegenerate(std::function<void()> f)
{
    m_regenFn = f;
    m_regen->setVisible(f != nullptr);
}
