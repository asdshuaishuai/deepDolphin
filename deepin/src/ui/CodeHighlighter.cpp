#include "CodeHighlighter.h"

#include "../logic/SyntaxHighlight.h"
#include "DesignTokens.h"

CodeHighlighter::CodeHighlighter(QObject *parent)
    : QSyntaxHighlighter(parent)
{
    // 四类 token 的颜色取自 DS 令牌（mac 同款语义：紫=关键字 / 绿=字符串 /
    // 灰=注释 / 黄=数字）—— 契约色不参与（这是界面色，不是引擎契约色）。
    m_keyword.setForeground(DS::semColor(DS::SemColor::deep));
    m_string.setForeground(DS::semColor(DS::SemColor::shallow));
    m_comment.setForeground(DS::textSecondary());
    m_number.setForeground(DS::semColor(DS::SemColor::yellow));
}

void CodeHighlighter::setLanguage(const QString &lang)
{
    if (m_lang == lang)
        return;
    m_lang = lang;
    rehighlight();
}

void CodeHighlighter::setGutterEnabled(bool on)
{
    if (m_gutter == on)
        return;
    m_gutter = on;
    rehighlight();
}

void CodeHighlighter::highlightBlock(const QString &text)
{
    if (m_lang.isEmpty() || !SyntaxHighlight::supportsLanguage(m_lang))
        return; // 语言不认识 → 不着色（别把代码涂成一片颜色）

    // 行号栏（"行号 + 制表符"）不算代码：跳过制表符之前的段
    int codeStart = 0;
    if (m_gutter) {
        const int tab = text.indexOf(QLatin1Char('\t'));
        codeStart = tab >= 0 ? tab + 1 : 0;
    }

    const QVector<SyntaxHighlight::Span> spans = SyntaxHighlight::highlight(text, m_lang);
    for (const SyntaxHighlight::Span &s : spans) {
        if (s.start < codeStart)
            continue;
        const QTextCharFormat &fmt = s.kind == SyntaxHighlight::Kind::keyword ? m_keyword
            : s.kind == SyntaxHighlight::Kind::string                       ? m_string
            : s.kind == SyntaxHighlight::Kind::comment                       ? m_comment
                                                                             : m_number;
        setFormat(s.start, s.len, fmt);
    }
}
