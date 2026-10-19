// EngineHook.h — 引擎 post-commit / post-merge 钩子的**判定层**（纯函数，零 QWidget 头）。
//
// 【这是什么】引擎的 `hook` 命令管的是「往项目的 .git/hooks 里装一段**托管块**」：
//   块内由引擎维护（会被覆盖），**块外是用户自己的逻辑，必须留着**。
//   实测（2026-10-19，moongit dev d363b6a）：
//     · install → 托管块插到**前面**，用户原有钩子内容**追加在后面**（不覆盖）；
//     · uninstall → **只删托管块**，用户自己的逻辑原样留着；
//   ⇒ 客户端提供「装/卸」入口是安全的（不会吞掉用户自己的 git 钩子）。
//
// 【⚠ `installed` 是数组按位置，不是对象】
//   引擎 `hook status <项目> --json` 返回：
//     {"project":"x","installed":[true,true],"log":"…"}
//   `installed` **没有键名** —— 位置即语义：[0]=post-commit、[1]=post-merge。
//   这个位置约定在这里**显式写死**（别处不许再解释一遍）。
#pragma once
#include <QByteArray>
#include <QString>
#include <QVector>

namespace EngineHook {

/// 钩子状态（来自引擎 `hook status <项目> --json`）。
struct Status {
    bool parsed = false;          ///< 载荷读懂了（不是「没装」）
    QString project;
    /// `installed` 键在、且数组够长（≥2）。
    /// ⚠ 缺这个键 = **契约漂移**（不是「没装」—— 把漂移当「没装」会让人去重装一个已装的钩子）。
    bool installedPresent = false;
    bool postCommit = false; ///< installed[0]
    bool postMerge = false;  ///< installed[1]
    QString log; ///< 钩子日志路径（引擎把钩子的输出写这里）
};

/// 从 `hook status --json` 的载荷解析。
Status parseStatus(const QByteArray &json);

/// 面向用户的一句话（说清是「都装了 / 只装了一半 / 都没装 / 读不出来」）。
QString summary(const Status &s);

/// 已装了几个（0/1/2）。
int installedCount(const Status &s);

/// 批量动作的逐项目结果。
struct Item {
    QString project;
    bool ok = false;
    QString detail; ///< 失败原因 / 引擎回执
};

/// 批量结果汇总成一句话：「N 个项目成功，M 个失败：<逐条>」。
/// ⚠ 「N 个成功」**不等于**「全成功」—— 汇总句必须把失败的那几个**点名**。
QString batchSummary(const QVector<Item> &items);

} // namespace EngineHook
