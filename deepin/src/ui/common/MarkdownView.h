// MarkdownView.h — Markdown 渲染（PLAN §8 T7：QTextDocument::setMarkdown，不引第三方库）。
//
// 标题字号走 tokens（h1/h2/h3 = 22/18/15）；外链 QDesktopServices 打开
//（openExternalLinks=false 自管——链接点击先过本类，便于子类/调用方拦截）。
#pragma once
#include "../DesignTokens.h"
#include <QDesktopServices>
#include <QTextBrowser>
#include <QUrl>

class MarkdownView : public QTextBrowser {
    Q_OBJECT
public:
    explicit MarkdownView(QWidget *parent = nullptr)
        : QTextBrowser(parent)
    {
        setOpenExternalLinks(false);
        setOpenLinks(false);
        setFrameShape(QFrame::NoFrame);
        setStyleSheet(QStringLiteral(
            "QTextBrowser { background: transparent; }"));
        connect(this, &QTextBrowser::anchorClicked, this, [this](const QUrl &url) {
            if (url.scheme() == QLatin1String("http") || url.scheme() == QLatin1String("https"))
                QDesktopServices::openUrl(url);
            else
                emit linkActivated(url);
        });
    }

    void setMarkdownText(const QString &md)
    {
        document()->setDefaultStyleSheet(defaultSheet());
        setMarkdown(md);
    }

signals:
    void linkActivated(const QUrl &url);

private:
    static QString defaultSheet()
    {
        return QStringLiteral("h1 { font-size: %1px; font-weight: 600; }"
                              "h2 { font-size: %2px; font-weight: 600; }"
                              "h3 { font-size: %3px; font-weight: 600; }"
                              "h4, h5, h6 { font-size: 14px; font-weight: 600; }"
                              "code, pre { font-family: monospace; }")
            .arg(DS::MD_H1)
            .arg(DS::MD_H2)
            .arg(DS::MD_H3);
    }
};
