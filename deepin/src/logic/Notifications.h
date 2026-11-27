// Notifications.h — 系统通知的**判定层**（纯函数，零 QWidget 头）。
//
// 【为什么把「顶替规则」下沉到判定层】⚠ 原来规则写在 `app/Notifier.cpp` 里
//   （「标题含『失败』或『停滞』就算状态型」）⇒ **无头测不到**（发通知要 D-Bus 会话）
//   ⇒ 规则改了没人发现。纯函数化 ⇒ selfcheck 能把规则**钉死**。
//
// 【为什么规则是「按标题关键词」】⚠ **已知的脆弱点**：调用方没有显式传类别，
//   判定层只能从标题认「状态型」⇒ 标题一改就可能不再顶替。
//   ⇒ 显式写在这里 + 判据钉死（别让它悄悄变）。
//   将来若调用方改成显式传类别 ⇒ 本文件可以删，判定层唯一真相源随之迁走。
//
// 【为什么时长也要归一】⚠ D-Bus 通知服务器的 `expire_timeout` 语义是
//   「毫秒；-1 = 用服务器缺省；0 = 永不消失」⇒ 传 0 会让通知**赖在通知中心不走**，
//   传负数会被服务器当成缺省 ⇒ 用户看到的时长与设定的不一致。
//   ⇒ 越界夹进范围、非正取缺省（5s，与历史硬编码一致）。
#pragma once
#include <QString>

namespace Notifications {

/// 通知显示时长缺省（毫秒）—— 与历史硬编码的 5000 一致。
constexpr int kDefaultTimeoutMs = 5000;
/// 下限 1s（别一闪而过）；上限 10 分钟。
constexpr int kMinTimeoutMs = 1000;
constexpr int kMaxTimeoutMs = 600000;

/// 时长归一：越界夹进范围；<=0 ⇒ 缺省。
int normalizeTimeoutMs(int ms);

/// 通知类别（决定 `replaceId` 归属）：状态型同一类别互相顶替，其余并存。
/// ⚠ 空串 = 无类别（**不顶替**前一条）。
QString categoryOf(const QString &title);

/// 该条通知是否顶替同类别的前一条（只有状态型顶替；其余并存）。
bool replacesPrevious(const QString &title);

} // namespace Notifications
