# 交接说明（HANDOFF）

本目录的 `DDE-INTEGRATION-PLAN.md` 是 **deepin/DDE 版修复计划 + 执行手册**（含任务 ID、精确落点、验证命令、进度看板、执行日志、常见坑）。

## 接手的智能体请按这个顺序读

1. `DDE-INTEGRATION-PLAN.md` §0 完成定义（DoD）
2. §11 环境与构建速查（怎么编译 / 怎么跑无头截图）
3. §12 交接须知与不变量（红线 + 文档同步纪律 + grep 门）
4. §9 执行进度看板 → 找第一个 `□` 开做；做完改 `☑`，在 §10 追加一行执行日志，再 commit（消息含任务 ID）

## 当前状态

- 计划文档已写入，**执行中**：见 `DDE-INTEGRATION-PLAN.md` §9 看板（`[x]`=已完成、`[~]`=部分、`□`=未做）与 §10 执行日志。
- 已完成（按序）：M0-1/2/3/4/5/6/7/9（M0-8 脚本就绪待干净容器）、M1a 的 AI 设置页一行 + **输入件批 + 按钮批 + palette QSS 收编**、M1-4/M1-5、M2-1~M2-4、M3-1~M3-4；
  **2026-10-04 批次（三轨道并行，已合并回 main）**：M3-5（几何/metric 收口）、M3-6（Card::kPadding）、M3-7（Thresholds/TrayGeometry）、M3b 三批（SecondaryLabel/SegmentedButton、BusyRow/EmptyState、FlatButton）、M1-1（DStandardPaths）、M1-6（UOS AI 异步化 + 接口 dump）、M1-9（--platform-probe）、M4b（ci.sh 四处增强）、M4c（SIGSEGV/SIGABRT handler）、M2-6（图标集 hicolor 8 档 + dd-* 五枚）。取舍全录见 README 决策 73–83。
- 合并后主树状态（2026-10-04 实跑复核）：`cmake --build` 产物在位，`./build/deepDolphin --selfcheck` **66 passed, 0 failed**（58 → 66，本批 +8）。
- 合并验收注意：`scripts/ci.sh` 在 `deepin/scripts/` 下，**必须在 `deepin/` 目录内跑**——2026-10-04 合并验收时从仓库根跑报 `No such file or directory`，CI 全量验收实际未执行（主树构建+selfcheck 已单独复核绿）；ci.sh 的 deb 构建/系统 Qt6 矩阵两步仍未做。
- **重大发现与修复**：M0-2 的 `locateAsync` 曾把 `this` 捕获进 `QMetaObject::invokeMethod`，QRunnable 自动删除 → use-after-free，**GUI 启动路径进事件循环即段错误**（`--snapshot` 路径不复现，极易漏到真机）。已改为 worker 内 swap 回调 + 值捕获投递；README 决策 65 记录了用 `DD_BISECT` 逐位二分的定位过程。
- 2026-10-04 批注（更新）：M1-9 已落地，main.cpp 无头分支的 `--platform-probe` 位置现在是真探针（返回探针事实，不再快速失败 exit 2）。教训保留：**新无头夹具一律挂在 GUI 构造前的无头分支**——未知/未实现 flag 落进 GUI 主路径会单实例常驻，无头 ci.sh 挂死（踩过一次）。
- 已知遗留（本批）：M3b 仅剩 KPI 骨架屏；`AppModel::postNotificationsIfNeeded` 未接 `Thresholds::dirtyNotifyMinCount/dirtyBucketWidth`（10/10 常量与 selfcheck 锁值已就位，留 app 轨）；`--snapshot` 轮询判稳对 milestones 页时序敏感（两批均拍到过加载态，现基线已换稳态，建议 M4 CI 稳定性关注）；分段钮/hover/busy 转圈等新观感需真机目检（offscreen 只证不崩与稳态正确）；setupguide 基线已随 M3b-FlatButton 重拍至当前 HEAD。
- 未做（按 §7 的"第 2/3 波"继续）：M1a 容器/视图批（SidebarNav DListView、QTreeWidget→DTreeView、DBlurEffectWidget/DButtonBox——模型重构）、M1-2/M1-3/M1-7/M1-8、M2-5（i18n）/M2-7（deb）/M2-8、M3b KPI 骨架屏、M3c（第二套色板/两种蓝/图标名/动效/响应式/HiDPI/托盘 busy 帧）、M4a（大文件拆分）。
- 如果额度不足：优先 M3c（一致性/HiDPI/动效——观感质变的收尾）或 M2-7/M2-8（deb 出包——D7 达标必经）；两者都不动能力基准，其余可以等。

## 相关文档

- `deepin/README.md`：功能清单、快捷键映射、C1–C11 落点、决策 1–27、引擎安装与构建
- 仓库根 `PLATFORM-CHARTER.md`：跨平台能力基准（C1–C11）
- 引擎契约：`deepin/scripts/contract-check.sh`、引擎仓库 `~/code/moongit`
