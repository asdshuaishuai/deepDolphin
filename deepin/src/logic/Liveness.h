// Liveness.h — 项目「还在不在动」的档位枚举（判定实现在 logic/Derived，PLAN 里程碑 2）。
//
// 单独放一个头：托盘图标染色与侧栏状态点只消费枚举本身，不该为它拉进
// Derived 的全部判定实现（Derived 实现落地的阶段再由 Derived.h include 本头）。
// 判定顺序（error→unreadable；kind≠git→notGit；needsAction→needsAction【必须在
// engineStale 前】；primaryBranch stale→engineStale；age≤30→recent else quiet；
// 读不出→unknown）属于正确性红线，见 mac Models.swift:557-583 与 PLAN §2.4。
#pragma once

enum class Liveness {
    unreadable,   // 采集失败：所有计数都是未知
    notGit,       // 非 git 项目
    needsAction,  // 有东西等着动手
    engineStale,  // 引擎判定停滞（只有追踪到基线的分支才可能）
    recent,       // 30 天内有新提交
    quiet,        // 30 天以上没有新提交（说「N 天没更新」，不说「停滞」）
    unknown,      // 提交时间读不出来——「不知道」，不许折进任何一档
};
