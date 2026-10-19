#include "ArchReceipt.h"

#include <QHash>
#include <QRegularExpression>
#include <QStringList>

namespace ArchReceipt {

QString receipt(const QString &text)
{
    const QStringList lines = text.split(QLatin1Char('\n'));
    // 从末尾往前找第一个非空行：引擎回执的最后一行才是结论
    // （如「架构已生成：首版（第 0 版）」），前面几行是明细。
    for (int i = lines.size() - 1; i >= 0; --i) {
        const QString t = lines.at(i).trimmed();
        if (!t.isEmpty())
            return t;
    }
    return QString();
}

QString filePath(const QString &text, const QString &suffix)
{
    // 引擎回执的真实形态：「已重绘：<绝对路径> · 第 N 版」—— 路径与文案之间是
    // **全角冒号**（不是空格）。按空格切词会切出「已重绘：/path/arch.html」这种
    // 粘连块，纯路径取不出来（mac 的 extractHTMLPath 就栽在这里，导出后
    // 「打开」入口始终不出现）。
    // 所以不按空格切，直接扫「以 / 开头、以给定后缀结尾、中间不含空白与全角
    // 分隔符」的一段（后缀由调用方给：render arch 出 .html、report 出 .md）。
    // ⚠ 还要卡**词边界**：路径的 / 前面必须是空白或全角分隔符 —— 否则
    // 「render/arch.html」这种相对路径会被从中间的 / 截成「/arch.html」，
    // 给用户一个打不开的「打开」入口。
    // 相对路径仍然不认（打不开的路径等于坏按钮）。
    if (suffix.isEmpty())
        return QString();
    // ⚠ 缓存必须**按后缀分桶**。这坑踩过一次：正则原本放在函数级 `static` 里，
    //   「第一次调用用哪个后缀，模式就焊死成哪个」—— 之后传 .md 也按 .html 找，
    //   报告路径永远抽不到（「打开报告」入口永不出现）；反向还会在 .html 文本里
    //   抽出 .md 之外的路径。症状极隐蔽：调用点、参数看着全对，只有行为不对。
    //   判据见 SelfCheck「后缀不同的两次抽取互不污染」。
    static QHash<QString, QRegularExpression> cache;
    auto it = cache.find(suffix);
    if (it == cache.end())
        it = cache.insert(suffix,
            QRegularExpression(QStringLiteral("(?<=[\\s：·])(/[^\\s：·]*%1)").arg(
                QRegularExpression::escape(suffix))));
    const QRegularExpressionMatch m = it->match(text);
    return m.hasMatch() ? m.captured(1) : QString();
}

QString htmlPath(const QString &text)
{
    return filePath(text, QStringLiteral(".html"));
}

QString plain(const QString &text)
{
    // ESC [ <参数> <终局字母> —— 引擎只发 SGR（m）终局，参数是数字与分号。
    static const QRegularExpression re(QStringLiteral("\x1b\\[[0-9;]*[A-Za-z]"));
    QString out = text;
    return out.remove(re);
}

} // namespace ArchReceipt
