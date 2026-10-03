# 交接说明（HANDOFF）

本目录的 `DDE-INTEGRATION-PLAN.md` 是 **deepin/DDE 版修复计划 + 执行手册**（含任务 ID、精确落点、验证命令、进度看板、执行日志、常见坑）。

## 接手的智能体请按这个顺序读

1. `DDE-INTEGRATION-PLAN.md` §0 完成定义（DoD）
2. §11 环境与构建速查（怎么编译 / 怎么跑无头截图）
3. §12 交接须知与不变量（红线 + 文档同步纪律 + grep 门）
4. §9 执行进度看板 → 找第一个 `□` 开做；做完改 `☑`，在 §10 追加一行执行日志，再 commit（消息含任务 ID）

## 当前状态

- 计划文档已写入，**执行中**：见 `DDE-INTEGRATION-PLAN.md` §9 看板（`[x]`=已完成、`[~]`=部分、`□`=未做）与 §10 执行日志。
- 已完成（按序）：M0-1/2/3/7/8/9、M1a 的 AI 设置页一行、M2-1~M2-4、M3-1~M3-4。
- **重大发现与修复**：M0-2 的 `locateAsync` 曾把 `this` 捕获进 `QMetaObject::invokeMethod`，QRunnable 自动删除 → use-after-free，**GUI 启动路径进事件循环即段错误**（`--snapshot` 路径不复现，极易漏到真机）。已改为 worker 内 swap 回调 + 值捕获投递；README 决策 65 记录了用 `DD_BISECT` 逐位二分的定位过程。
- 未做（按 §7 的"第 2/3 波"继续）：M1a 其余控件替换、M1-1~M1-9、M2-5~M2-8、M3-5/M3b/M3c、M4。
- 如果额度不足：先做 §7「极限最小可交付」剩余项（M3-5 几何收口 + M3b 组件化），它们不动架构、见效最快。

## 相关文档

- `deepin/README.md`：功能清单、快捷键映射、C1–C11 落点、决策 1–27、引擎安装与构建
- 仓库根 `PLATFORM-CHARTER.md`：跨平台能力基准（C1–C11）
- 引擎契约：`deepin/scripts/contract-check.sh`、引擎仓库 `~/code/moongit`
