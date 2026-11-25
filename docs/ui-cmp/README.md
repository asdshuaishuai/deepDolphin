# CMP 客户端真窗口实拍（2026-11-25）

全部取自**打包后的 deb 提取运行**（`gradle packageDeb` → `dpkg-deb -x` → `opt/deepdolphin/bin/deepdolphin`，
`DISPLAY=:0`，窗口 1270×830，打包态 `STARTUP_MS=864`）。截图前逐项确认焦点在本应用窗口，
截到别的窗口的图一律不入库。本目录之前的 48 张旧图已退役——其中至少 9 张截到的是 IDE，
还有一张标着「图谱页验证通过」的其实是空白页。

引擎为本机 `~/.local/bin/moongit`（0.2.0），项目是两个测试仓库 vtest / vtest2。

| 文件 | 内容 |
|---|---|
| `01-dashboard.png` | 仪表盘：Fluent 命令条（范围选择器 + 双轨按钮）、时间窗筛选、KPI、项目卡 |
| `02-board.png` | 看板：分区只留标题，项目行是唯一卡片层；右缘滚动条 |
| `03-milestones.png` | 里程碑：仓库下拉与搜索框同一套描边控件 |
| `11-milestone-repo-dropdown.png` | 仓库下拉展开：真正的浮出菜单，选中项带勾 |
| `04-confidence.png` | 代码置信度：六维度 + 疑点清单（真图标状态标记） |
| `05-patchcheck.png` | 补丁体检 |
| `06-detail.png` | 项目详情：页头动作 + 两个带图标的图谱入口按钮 |
| `09-code-graph.png` | **代码图谱（热力图）**：跟仓库走的独立页面，WebView 渲染引擎产物（置信度 51/100） |
| `10-arch.png` | **架构图**：同机制，暗色主题（产物按 prefers-color-scheme 选明暗，客户端垫了暗色） |
| `07-settings-general.png` | 设置 · 通用：Fluent Pivot 页签（下划线指示）、语言选择（accent 底配近黑字） |
| `08-settings-ai.png` | 设置 · AI 配置 |
| `12-menu-operations.png` | 窗口内菜单条「操作」下拉：跟随当前范围、描边 + 投影 |

没拍到但实测过的：侧栏 Fluent 图标、启动后不点击直接按 Ctrl+2/3（AWT 层接管快捷键）、
图谱页里 WebView 持有焦点时 Ctrl+1 / Ctrl+F、连续 12 次改窗口尺寸后图谱仍可交互、
SIGTERM 正常退出与「关闭钩子卡死时 4 秒硬退」兜底。
