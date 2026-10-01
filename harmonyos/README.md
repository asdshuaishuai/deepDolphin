# 鸿蒙 PC 客户端（规划中）

- 技术：ArkUI（ArkTS），面向 HarmonyOS PC
- 职责：通过 CLI 子进程调用 deepGit Engine（与 macOS 客户端同构）
- 引擎侧：仓颉是鸿蒙生态一等语言，引擎可走仓颉鸿蒙工具链编译为鸿蒙 PC 目标；
  引擎以应用内后台子进程形式拉起，CLI `--json` 契约不变
- 系统集成：应用常驻 + 原生窗口面板

> 契约（`--json` 键名）以 deepgit-engine 仓库为准，三端保持一致。
