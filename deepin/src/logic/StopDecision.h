// StopDecision.h —「停止更新」的判定与文案（mac StopDecision.swift 对位，纯函数层）。
//
// 【红线】三态都要说实话：被停不是失败；「早结束了」不许说成「已停止」；
// 唯一算警告的是 cancelled（进程还活着，界面已不认这次操作）。
#pragma once
#include <QString>

namespace StopDecision {

struct Outcome {
    enum K { killed1, killedN, alreadyFinished, cancelled } k = alreadyFinished;
    int n = 0;
};

inline Outcome decide(int killedCount, bool stillAliveAfterStop)
{
    if (killedCount == 1)
        return { Outcome::killed1, 1 };
    if (killedCount > 1)
        return { Outcome::killedN, killedCount };
    if (stillAliveAfterStop)
        return { Outcome::cancelled, 0 };
    return { Outcome::alreadyFinished, 0 };
}

inline QString message(Outcome o, int itemCount)
{
    switch (o.k) {
    case Outcome::killed1:
        return QStringLiteral("已停止 1 个正在进行的更新");
    case Outcome::killedN:
        return QStringLiteral("已停止 %1 个正在进行的更新").arg(o.n);
    case Outcome::alreadyFinished:
        return QStringLiteral("停止时更新已经跑完了（%1 个项目）").arg(itemCount);
    case Outcome::cancelled:
        break;
    }
    return QStringLiteral("已取消等待（更新可能仍在后台收尾）");
}

inline bool shouldWarn(Outcome o)
{
    return o.k == Outcome::cancelled;
}

} // namespace StopDecision
