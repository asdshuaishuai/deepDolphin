// AgentToolPlan.h — agent 工具 → 引擎 argv 的**计划表**（纯函数层，零 QWidget 头）。
//
// 【为什么要抽成表】
// 原来这层是 `AgentCore::executeTool` 里一条 if-else 链，每加一个工具就多一段
// 分支，分支一长就会出现三种坏毛病：
//   ① 某个工具的 argv 拼错了，只有真跑到那个工具才看得出（模型不会替你验）；
//   ② 工具一多，「客户端会执行哪些工具」这件事说不清 —— 于是契约检查没法比；
//   ③ 参数校验（白名单、flag 形态）散在分支里，各自一套口径。
// 抽成纯函数表之后：argv 形状、参数校验、拒绝理由全部可**无头判**，
// 且「客户端支持哪些工具」有了一个**单一真相源**（knownToolNames）。
//
// 【与引擎契约的关系】
// 引擎 `tools --json` 声明 28 个工具，客户端必须**能执行全部 28 个**。
// 两份清单漂移的症状很隐蔽：模型调了一个客户端不会执行的工具，界面上只显示
// 「未知工具：X」—— 很容易被当成模型乱调，而真因是清单已经不一致。
// 对位由 contract-check 第 12 组钉住（真引擎清单 ⇄ 客户端清单，严格相等）。
//
// 【argv 里为什么有 {{tmp:<参数>}} 占位】
// 引擎 CLI 的 `graph patchconf --merge <algorithm.json> <agent.json>` 吃的是
// **文件路径**，而工具参数是两段 JSON 文本 —— 落盘是 I/O，不属于纯函数层。
// 所以本层只声明「哪个参数要落临时文件 + argv 里哪一格放它的路径」，
// 由执行方（app 层）替换占位符。纯函数层不碰文件系统。
#pragma once
#include <QJsonObject>
#include <QString>
#include <QStringList>

namespace AgentToolPlan {

/// 一次工具执行的计划。
struct Plan {
    bool known = false;     ///< 客户端会执行这个工具（false = 未知工具）
    QStringList argv;       ///< 引擎子进程 argv（含 {{tmp:<参数>}} 占位）
    QStringList tempParams; ///< 需要落临时文件的参数（引擎 CLI 吃路径的那种）
    int timeoutMs = 0;      ///< 超时预算（0 = 用调用方默认）
    QString reject;         ///< 非空 = 拒绝执行，原因回报给模型
};

/// 工具名 + 模型给的参数 → 执行计划。
/// 未知工具 → known=false（不猜、不静默成功）。
Plan planFor(const QString &name, const QJsonObject &params);

/// 客户端能执行的全部工具名（**单一真相源**，与引擎 `tools --json` 严格对位）。
QStringList knownToolNames();

} // namespace AgentToolPlan
