#include "ArchReceipt.h"

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

QString htmlPath(const QString &text)
{
    // 引擎回执的真实形态：「已重绘：<绝对路径> · 第 N 版」—— 路径与文案之间是
    // **全角冒号**（不是空格）。按空格切词会切出「已重绘：/path/arch.html」这种
    // 粘连块，纯路径取不出来（mac 的 extractHTMLPath 就栽在这里，导出后
    // 「打开」入口始终不出现）。
    // 所以不按空格切，直接扫「以 / 开头、以 .html 结尾、中间不含空白与全角
    // 分隔符」的一段。
    // ⚠ 还要卡**词边界**：路径的 / 前面必须是空白或全角分隔符 —— 否则
    // 「render/arch.html」这种相对路径会被从中间的 / 截成「/arch.html」，
    // 给用户一个打不开的「打开」入口。
    // 相对路径仍然不认（打不开的路径等于坏按钮）。
    static const QRegularExpression re(
        QStringLiteral("(?<=[\\s：·])(/[^\\s：·]*\\.html)"));
    const QRegularExpressionMatch m = re.match(text);
    return m.hasMatch() ? m.captured(1) : QString();
}

} // namespace ArchReceipt
