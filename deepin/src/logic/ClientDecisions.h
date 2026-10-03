// ClientDecisions.h — 客户端侧失败决策（mac ClientDecisions.swift 对位，纯函数层）。
//
// 开机自启注册/注销失败：**回滚开关到系统真实状态** + 红字说明——不假装成功。
#pragma once
#include <QString>

namespace ClientDecisions {

struct AutostartRollback {
    bool rolledBack = false;
    QString message;
};

inline AutostartRollback autostartFailure(bool registered, bool systemState)
{
    AutostartRollback r;
    if (registered && !systemState) {
        r.rolledBack = true;
        r.message = QStringLiteral("开机自启注册失败，系统实际仍是关闭的 —— 开关已回滚");
    } else if (!registered && systemState) {
        r.rolledBack = true;
        r.message = QStringLiteral("开机自启注销失败，系统实际仍是开启的 —— 开关已回滚");
    }
    return r;
}

} // namespace ClientDecisions
