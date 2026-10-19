// CodeHighlighter.h — 把 `logic/SyntaxHighlight` 的判定结果涂到 QTextDocument 上。
//
// 【为什么不让判定层直接管颜色】颜色是主题的事（DS 令牌），判定是语言的事。
// 判定层出「哪一段是什么 token」，这里出「这种 token 用哪个 DS 令牌」——
// 换主题时只改这里，判定层一个字都不用动。
#pragma once
#include <QSyntaxHighlighter>
#include <QTextCharFormat>
#include <QString>

class CodeHighlighter : public QSyntaxHighlighter {
    Q_OBJECT
public:
    explicit CodeHighlighter(QObject *parent = nullptr);

    /// 切换语言（引擎 `detectLang` 的原样值；不认识的语言 → 不高亮）。
    void setLanguage(const QString &lang);

    /// 源码视图的行首是「行号 + 制表符」——那一段是行号栏，不是代码，不该着色。
    /// 打开这个开关后，高亮从制表符之后开始（判定层仍按整行算，界面只跳过前半段）。
    void setGutterEnabled(bool on);

protected:
    void highlightBlock(const QString &text) override;

private:
    QString m_lang;
    bool m_gutter = false;
    QTextCharFormat m_keyword;
    QTextCharFormat m_string;
    QTextCharFormat m_comment;
    QTextCharFormat m_number;
};
