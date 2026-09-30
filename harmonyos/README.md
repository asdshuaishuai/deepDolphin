# 鸿蒙 PC 客户端（规划中）

- 技术：ArkUI（ArkTS），面向 HarmonyOS PC
- 职责：消费 deepGit Engine 的本地 HTTP API（与 macOS 客户端同构）
- 引擎侧：仓颉是鸿蒙生态一等语言，引擎可走仓颉鸿蒙工具链编译为鸿蒙 PC 目标；
  服务以应用内后台进程形式拉起，端口与 API 契约不变
- 系统集成：应用常驻 + 原生窗口面板

> 契约（API 键名）以 deepgit-engine 仓库为准，三端保持一致。
