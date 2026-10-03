// ScanCoverage.h — 扫描覆盖度披露（mac ScanCoverage.swift 对位，纯函数层）。
//
// 【红线】三种「没看完」分开说（撞深度→加深度；撞目录上限→分根扫；读不出来→查权限）；
// 「—— 该目录树里没有 git 仓库」只在**真扫完**（found==0 且无任何 note）时才说。
#pragma once
#include <QString>
#include <QStringList>

namespace ScanCoverage {

struct Input {
    int found = 0;
    bool truncated = false;
    bool depthCapped = false;
    int unreadable = 0;
};

// 附加披露；空串 = 没什么要说的（不返回形似残缺的空白）。
inline QString note(const Input &i)
{
    QStringList why;
    if (i.depthCapped)
        why << QStringLiteral("撞到扫描深度上限，下面还有目录没看");
    if (i.truncated)
        why << QStringLiteral("撞到目录数量上限");
    if (i.unreadable > 0)
        why << QStringLiteral("%1 个目录读不出来（无权限或 I/O 错误）").arg(i.unreadable);
    if (why.isEmpty())
        return QString();
    if (i.found == 0)
        return QStringLiteral("本次未扫完（%1）—— 上面「共发现 0 个」只代表已访问的那部分里没有，不是这棵树里没有")
            .arg(why.join(QStringLiteral("，")));
    return QStringLiteral("本次未扫完（%1）—— 上面列出的不是全部").arg(why.join(QStringLiteral("，")));
}

} // namespace ScanCoverage
