// Thresholds.h — 客户端阈值的唯一收口（M3-7；plan R1：阈值只准落在
// ui/DesignTokens.*、src/platform/*、本头三处之一，其余地方只准消费）。
//
// 【红线】
// · 全是 constexpr 数值：零 QWidget、零颜色——可被 QtTest 无头单测；
// · 引擎的 3/14 天档位线（active/idle/stale 分档）**不在这里**——那两根线归引擎，
//   客户端不许拿 staleDays 自推（Derived.h 文件头同款纪律）；
// · 改任何一个值都要同步 SelfCheck 的 Thresholds fixtures（例数只增不减）。
#pragma once

namespace Thresholds {

// ── 「未提交改动较多」通知（消费方：app/AppModel::postNotificationsIfNeeded）──
// 审计口径 10/10（2026-10-04 grep 实证：AppModel.cpp「userDirtyCount >= 10，按十位分桶去重」）：
// · 未提交改动满 10 处才报通知（9 处以下不打扰）；
// · 去重键按十位分桶（10–19 是桶 1、20–29 是桶 2……涨一档才再报一次）。
// 单位是**改动条数**不是天数——计数阈值 + 计数分桶，勿与下面的时间窗混淆。
constexpr int dirtyNotifyMinCount = 10;
constexpr int dirtyBucketWidth = 10;

// ── 引擎 active7d / active30d 两根时间桶线 ──
// liveness 的 recent/quiet 分界（Derived::liveness「age≤30→recent else quiet」）与
// 仪表盘时间窗（DashFilter 近 7 天 / 近 30 天）对齐的都是这两根线；
// 算术同引擎：毫秒差整除 86400000（Derived::daysSinceLastCommit）。
constexpr int activeDays7 = 7;
constexpr int activeDays30 = 30;

} // namespace Thresholds
