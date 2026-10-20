// SelfCheckInternal.h — `--selfcheck` 各**分片**之间的共享底座（批 AJ · M4a 拆分）。
//
// 【为什么要这个文件】⚠ `SelfCheck.cpp` 原本是**一个 3800 多行的函数**（M4a 的遗留债）。
//   拆成多个 `SelfCheck*.cpp` 时，「记一条判据」这件事**必须只有一份实现** ——
//   各文件各写一份 `check()` ⇒ 计数会各数各的 ⇒ 汇总出来是错的
//   ⇒ 而且是「同名两处互相顶替」的老坑（台账的通用教训）。
//   ⇒ 把 `check()` / 计数 / JSON 小工具放这里，**inline**（C++17 的 inline 变量）。
//
// 【分片怎么用】
//   · 在自己的 .cpp 里写 `using SelfCheckInternal::check;`
//     ⇒ 现有的裸调用 `check(log, "…", ok)` **一个字都不用改**。
//   · 计数是 inline 变量 ⇒ 所有分片共享同一份 `g_pass` / `g_fail`。
//
// 【分片清单】
//   · SelfCheck.cpp        —— 主片（夹具 / envelope / 引擎契约 / 托盘 / 面板几何 …）
//   · SelfCheckDocs.cpp    —— 固定文档页 + 四语言 + 语法高亮
#pragma once
#include <QJsonDocument>
#include <QJsonObject>
#include <QStringList>

namespace SelfCheckInternal {

/// 判据计数（**inline 变量**：多个分片共享同一份，不许各数各的）。
inline int g_pass = 0;
inline int g_fail = 0;

/// 记一条判据（**所有分片共用这一份实现** —— 各写一份就出现两个真相源）。
inline void check(QStringList &log, const QString &name, bool ok, const QString &detail = QString())
{
    if (ok) {
        ++g_pass;
        log << QStringLiteral("PASS  %1").arg(name);
    } else {
        ++g_fail;
        log << QStringLiteral("FAIL  %1%2").arg(
            name, detail.isEmpty() ? QString() : QStringLiteral(" —— ") + detail);
    }
}

/// JSON 解析小工具（分片共用；`JO` = 取对象）。
inline QJsonDocument J(const QString &json)
{
    return QJsonDocument::fromJson(json.toUtf8());
}
inline QJsonObject JO(const QString &json)
{
    return J(json).object();
}

/// 分片入口（主片按顺序调用）。
void checkDocs(QStringList &log);
void checkEngine(QStringList &log);

} // namespace SelfCheckInternal
