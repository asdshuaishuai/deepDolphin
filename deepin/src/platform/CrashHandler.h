// CrashHandler.h — SIGSEGV/SIGABRT 最小崩溃 handler（PLAN M4c）。
//
// 崩溃时向 stderr 打 glibc 栈回溯（execinfo），随后恢复默认处置并 re-raise：
// 退出码、信号语义与 core dump 行为与未装 handler 完全一致——只加观测，不改终局。
#pragma once

namespace CrashHandler {

// 进程最早期调用一次（main 各路径在应用对象构造之前）；重复调用幂等。
// 纯 POSIX 实现、零 Qt 依赖：任何线程/路径崩了都能用，也无从拖累应用构造。
void install();

} // namespace CrashHandler
