// SnapshotFixture.h — **面板快照夹具**（判定层，纯数据、零 UI 依赖）。
//
// 【为什么要有它】
//   批 R 照出：4 页面板快照拍的是**空态**（本机引擎注册项目数 0，快照里只有
//   「仪表盘还没有数据」）—— **状态点一个都没画进去**。
//   ⇒ 面板快照对状态色/布局/排版全是**空门**：改界面它不红，说「视觉已评审」是假的。
//   根因是快照用**真引擎**取数 ⇒ 基线取决于「本机注册了什么项目」，不可重现。
//   ⇒ 改用**固定夹具**：走**真实的解析路径**（StatusEnvelope / DashboardData /
//     MilestonesEnvelope 的 fromJson），但数据是写死的 ⇒ 每次拍出同一张图。
//
// 【⚠ 时间戳分两类，别混】
//   ① **会被用来算天数**的（`lastCommitAt`）⇒ 必须**相对真实 now**。
//      `Derived::daysSinceLastCommit` 用 `QDateTime::currentDateTime()` 与它的
//      epoch 差算天数。写死 `2026-10-01` 的话，「N 天没更新」里的 N **每天都在变**
//      ⇒ 快照每天都不一致 ⇒ 基线每天都在漂。
//      相对 now 生成 ⇒ 同一次运行内天数**恒定**（0 天 / 40 天），跨天也不变。
//   ② **只会被显示成绝对字符串**的（`targetDate` / `headDate` / `updatedAt` /
//      `fetchedAt` / `generatedAt`）⇒ 必须**锚定到固定基准日**
//      （`anchorDate()`），不许跟着「今天」走。
//      否则 UTC 午夜一过，基线里的「目标 2026-10-19」就变成「2026-10-20」
//      ⇒ CI 天天有 diff ⇒ 人就学会忽略 diff ⇒ 基线又变成空门（同一个病）。
//   判据会盯住这条分界：SelfCheck 断言绝对日期 == 锚点派生值。
//
// 【夹具覆盖什么】
//   · Liveness **全部 7 档**（recent / needsAction / engineStale / quiet /
//     notGit / unreadable / unknown）—— 一个项目一档，状态点与状态词全覆盖；
//   · 分支状态 5 档（active / idle / stale / merged / unknown）；
//   · 里程碑 open / done / dropped / unknown 四态。
//   ⇒ 加一档 Liveness 时，这个文件必须跟着改（判据会盯住，见 SelfCheck）。
#pragma once

#include <QByteArray>
#include <QString>
#include <QtGlobal>

namespace SnapshotFixture {

/// status envelope 的载荷（`status --json` 的形状）。
QByteArray statusJson();

/// dashboard 的载荷（`dashboard --json` 的形状）。
QByteArray dashboardJson();

/// milestone list 的载荷（`milestone list --json` 的形状）。
QByteArray milestonesJson();

/// **固定刷新时刻**（epoch ms）—— 快照不许用墙钟。
///   侧栏状态条渲染「空闲 · 上次刷新 HH:mm」，那是 `lastRefreshedMs` 的**本地时区**
///   渲染 ⇒ 用墙钟就意味着基线**每分钟变一次**、且**换台机器就变**。
///   配合快照进程固定 `TZ=UTC`（见 main.cpp）⇒ 渲染成固定的「12:00」。
qint64 fixedRefreshedMs();

} // namespace SnapshotFixture
