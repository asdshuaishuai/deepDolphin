# deepDolphin — deepin/DTK6 客户端（deepin/）

moonGit（仓颉引擎，仓内别名 deepgit）项目群进度客户端的 Linux/deepin 复刻。
本目录是**新客户端专属目录**：不动 `linux/`（旧 Linux 仓颉客户端）、不动 `macos/`（1:1 功能基准）。

技术方案与逐文件设计：`/tmp/dd-deepin-port/PLAN.md`（下称 PLAN）；JSON 契约唯一来源：
`/tmp/dd-deepin-port/contract.md`（下称 CONTRACT）+ 引擎仓库 `/home/superShuai/code/moongit/`。

## Canvas 指定：Qt QPainter Canvas（scene 契约）

引擎契约（moonGit docs/graph-scene-schema.md）为本平台**指定**的图谱/架构图渲染实现是
**Qt/QPainter Canvas**（C++ 实现同一 Canvas2D 方法子集，以契约清单为移植验收清单），
消费 `graph arch/tree --format scene` 导出的 moongit-graph-scene v1 数据。
数据与渲染分离：引擎零实现时的 Web Canvas HTML 导出是兜底出口，本平台的正路是
scene 数据 + QPainter 本机绘制。（macOS 端对应实现 `ArchCanvasView.swift` 可作逐方法对照。）

---

## 功能清单与 mac 版对应关系

交互用 DTK 原生控件重做，信息架构与行为口径逐条对齐 mac 基准（`macos/README.md`）：

| mac 版（基准） | deepin 版实现 | 主要代码 |
|---|---|---|
| 主面板窗口（`PanelView`：侧栏导航 + 顶栏） | DMainWindow + 侧栏 + WorkBar + 页面栈，无占位页 | `src/ui/PanelWindow.cpp`、`SidebarNav`、`WorkBar` |
| 仪表盘（KPI / 语言分布 / 里程碑 / 活跃项目） | 同构四段：KPI 四卡 + 时间窗/提交类型筛选 + 项目卡 + 语言 + 里程碑 + 活跃 | `ui/pages/DashboardPage`、`DashboardFilterBar`、`ProjectProgressCard`；`logic/DashboardScope`、`DashFilter` |
| 看板（按健康状态分列） | 四 Section 树（行项目挂列头下，列头计数 = 列行数） | `ui/pages/BoardPage`；`logic/Derived`（boardColumn） |
| 里程碑页（行内直操作 + 新建 + 筛选） | 搜索 / 仓库筛选 / 按项目分组统计 / AddMilestoneDialog / 行内五态（达成/重开/放弃/删除） | `ui/pages/MilestonesPage`、`MilestoneRowWidget`、`ui/dialogs/AddMilestoneDialog` |
| 项目详情（脉搏 / 提交构成 / 分支 / 日志 / 文档平铺 / Git 操作） | 三态加载 + 页头 git 操作（唯一构造点）+ 提交改动卡 + 工程脉搏 + 提交构成 12 色 + 分支进度 + 里程碑 + 进度日志 + 托管文档四态 | `ui/pages/ProjectDetailPage`；`logic/CommitTypeComposition`（12 色不取模） |
| 菜单栏 bar + `.window` 富弹窗 | 托盘五态图标（tooltip = menuTitle）+ 速览弹窗（`●N` 橙 / pending 蓝数字 + 迷你条 / 副标题三级回退 / 平铺 12 行） | `tray/TrayController`、`TrayPopupWindow` |
| AI 助手（`AgentView`，≤4 轮工具循环） | AgentDialog：范围跟随 selection、transcript 三规则、过程事件行、Ctrl+Return 发送 | `ui/dialogs/AgentDialog`；`ai/AgentCore`、`AgentConversation`、`AgentOutcome` |
| AI 设置（provider / model / key / 测试连通） | 设置 AI 页签：「系统级 AI（默认）」与「mock」恒置顶 + 目录前 40 家 + 披露与模型徽标；key 只进 libsecret；测试连接 | `ui/dialogs/AiSettingsDialog`、`panes/AiSettingsPane`；`ai/AIConfig`、`SecretStore`、`ModelsDevCatalog`、`AIChannel` |
| models.dev 目录（vendor 快照 + 静默刷新） | qrc 快照 → `~/.local/share` 缓存，后台静默刷新（成功才置位），畸形 → 空目录 | `ai/ModelsDevCatalog`；`resources/models-dev.json` |
| ai-sdk 双协议通道（OpenAI 兼容 + Anthropic） | AIChannel 共用传输层（https 与 http://127.0.0.1/localhost 白名单、stream:false、120s、错误脱敏前 300 字、原生 tool_calls / tool_use 线格式） | `ai/AIChannel`、`OpenAiCompatEngine`、`AnthropicEngine` |
| mock 验证（defaults + 本地假 HTTP 服务） | MockEngine：Base URL `#` 片段即脚本（`#final` / `#tool=<名>;args=<json>` / `#fail`），无片段时状态机自动编排且刻意避开有副作用的工具 | `ai/MockEngine` |
| 系统通知（UNUserNotificationCenter） | DNotifySender + ActionInvoked → 叫醒面板；「新变差」去重（停滞按 (project,branch)、未提交 ≥10 十位分桶） | `app/Notifier.cpp` |
| 开机自启（SMAppService） | XDG autostart `.desktop` 写入 + 失败回滚开关 | `platform/AutostartManager.cpp`；`panes/GeneralPane` |
| Dock 菜单（打开面板 / 全部浅更新） | 托盘菜单：打开面板 / 全部浅更新 + **退出**（Linux 托盘必须有退出项） | `tray/TrayController` |
| 添加 / 扫描项目（`ScanSheet`） | ScanDialog + ScanCoverage 覆盖度披露接回主窗口说明条 | `ui/dialogs/ScanDialog`；`logic/ScanCoverage`、`PathInput` |
| 深链启动参数（`Route.swift`） | `--project <名>`、`--section board\|milestones\|dashboard`、`--open-settings`、`--agent-selftest`；pendingRoute 消费一次即置闩 | `logic/Route`、`Router`；`PanelWindow::maybeApplyPendingRoute` |
| 纯函数判定层（`client-check.sh` 单独编译断言） | `models/`、`logic/` 零 QWidget 头，判定收敛为二进制内置 `--selfcheck`（55 例） | `src/models/`、`src/logic/`、`app/SelfCheck` |
| 设置窗口（自动化 + AI） | 设置三页签（DTabBar+QStackedWidget）：通用 / 自动化（分段改完立即生效）/ AI | `ui/dialogs/panes/*` |
| 快捷键（CommandMenu + ShortcutMap.swift） | QShortcut 全量真绑（含深更新——mac 曾「声明未绑」的缺陷不重犯） | `ui/PanelWindow.cpp:516`；`logic/ShortcutMap.h`（唯一声明处） |
| 定时更新 + AI 简报 | autoHours 周期 + 首轮 600s；简报经通知；silent 场景不偷弹结果面板 | `app/AppModel.cpp:202`；`ai/AiDigests`（scheduledDigest） |
| 一键全量（agent 通道，覆盖由代码保证） | 先刷新注册表再冻结名单 / 逐仓库显式传名 / 一个失败不中断 / 结果面板 aiNote 永远有值 | `AppModel::updateAll`（AppModel.h:111）；`ai/AgentCore` 批量通道 |
| 双轨更新 + AI 变体（`UpdateActionMenu`） | WorkBar 双轨按钮（唯一入口）+ 详情页更新菜单「浅更新 + AI 摘要 / 深更新 + AI 报告」 | `ui/DualTrackButtons`；`AppModel::runUpdateDigest`（AppModel.h:110）、`AiResultDialog` |
| 引擎未装 → 安装引导 | SetupGuidePage + 「重新检测引擎」 | `ui/pages/SetupGuidePage` |

## 快捷键映射表

唯一声明处 `src/logic/ShortcutMap.h`（mac `ShortcutMap.swift` 对位），PanelWindow 全量真绑（`PanelWindow.cpp:516-536`）；
键位无重复有内置判定（`ShortcutMap::hasDuplicate`，selfcheck 覆盖）。

| mac 版 | deepin 版 | 动作 | 说明 |
|---|---|---|---|
| ⌘R | **Ctrl+R** | 刷新 | status→dashboard→milestones 顺序刷新 |
| ⇧⌘U | **Ctrl+Shift+U** | 浅更新（范围由 selection 推导） | 见决策 19：可能与输入法 Unicode 输入冲突，保持绑定、菜单显示实际序列 |
| ⌥⇧⌘D | **Ctrl+Alt+Shift+D** | 深更新 | **必须真绑**（mac 曾声明未绑是真缺陷；`PanelWindow.cpp:525` 实证已绑） |
| ⌘. | **Ctrl+.** | 停止更新 | 真 terminate，两步语义见决策 28 |
| ⌘F | **Ctrl+F** | 聚焦搜索 | 侧栏搜索框 |
| ⌘, | **Ctrl+,** | 设置 | 三页签设置窗 |
| ⌘W | **Ctrl+W** | 关闭面板 | = 隐藏到托盘（非退出） |
| ⌘1 / ⌘2 / ⌘3 | **Ctrl+1 / Ctrl+2 / Ctrl+3** | 仪表盘 / 看板 / 里程碑 | 固定三视图，**没有 Ctrl+5**——硬凑只会让用户按了没反应 |
| ⌘4 | **Ctrl+4** | 打开当前选中项目 | 在映射表里但不在 viewOrder（动态项目详情）；漏了它撞键检查查不出（`ShortcutMap.h:30`） |
| ⌘↩ | **Ctrl+Return / Ctrl+Enter** | Agent 发送 | `AgentDialog.cpp:227-230` 两个序列都绑 |

## 构建与运行

### 工具链（deepin 25 容器实测）

deepin 25（crimson）容器内没有编译器/cmake/Qt-dev/DTK-dev。用「user-space sysroot」方案搭自包含工具链，
未动系统目录、未装任何包，两步：

```sh
python3 scripts/bootstrap-deps.py --download   # 从 deepin 官方仓库（community-packages.deepin.com/beige，suite crimson）解析依赖闭包，
                                               # curl 下载 .deb 后逐个 dpkg-deb -x 抽到 ~/.local/dd-sysroot
sh scripts/setup-deps.sh                       # 在 ~/.local/bin 生成 cmake/g++/gcc/c++/ctest 包装脚本
                                               # （PATH 已含 ~/.local/bin 时无需 source 任何 env）
```

当前 sysroot（`~/.local/dd-sysroot`，本阶段经 CMakeCache 与包装脚本核实为**最终构建实际使用**的一代）：
g++ 13.2.0（Deepin 13.2.0-3deepin4）、cmake 3.31.4、Qt6 6.8.0、**Dtk6 dev 与运行库同为 6.7.47**、
libsecret-1、libspdlog/fmt（dtk6log 依赖）。
仓库没有 `libqt6svg6-dev`：CMake 编译期探测（`find_package(Qt6 QUIET COMPONENTS Svg)`），缺失时
`IconLoader` 自动降级 QPainter 占位图标并定义无 `DD_HAVE_QTSVG`；将来装上该包重新 configure 即自动启用
QSvgRenderer 染色通道，源码无需改动。

> 历史注记：`~/.dd-sysroot`（带 `env.sh`）是第一代 sysroot（g++ 12.3、Dtk6 dev 6.0.38 ≠ 宿主运行库
> 6.7.47），决策 13 的「6.0.38 实测差异」即测于它。第二代已把 dev 与运行库对齐到 6.7.47，
> 环境供给方式也从 `source env.sh` 改为 PATH 包装脚本。旧目录仍在盘上，但**不再是文档口径**。

### 构建 / 自检 / 运行 / 安装

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel 4
```

产物：`deepin/build/deepDolphin`（`CMAKE_RUNTIME_OUTPUT_DIRECTORY` 钉死源码树 build 根，
冒烟脚本按此硬路径断言）。

```sh
./build/deepDolphin --selfcheck   # 模型层 fixtures 自检（无 GUI、无引擎依赖；当前 55 例）
./build/deepDolphin --version
./build/deepDolphin --project <名>   # 深链（--section board|milestones|dashboard 同理）
./build/deepDolphin --agent-selftest [问题]   # 无头 agent 自测（默认「总结一下项目群现状」）
./build/deepDolphin --snapshot out.png --section dashboard   # 无头快照：离屏渲染整窗 PNG（mac render-harness 对位），
                                             # 等 2.5s 数据落地后抓整窗写盘即退；--project 同理可直达详情
                                     # mock 渠道即可全链路验证；stdout 打
                                     # [selftest] FINAL/ERROR + [selftest-done]；ERROR 退出码 1
scripts/smoke.sh                  # 配置+构建+selfcheck；引擎在位时追加 contract-check
```

**开发树内运行**（二进制无 rpath，Qt6/DTK6 运行库在 sysroot 里，环境变量缺一不可）：

```sh
export LD_LIBRARY_PATH=~/.local/dd-sysroot/usr/lib/x86_64-linux-gnu
export QT_PLUGIN_PATH=~/.local/dd-sysroot/usr/lib/x86_64-linux-gnu/qt6/plugins
export QT_QPA_PLATFORM=offscreen        # 无显示环境时；共享 X11 会话可去掉这行直接上真 DDE
./build/deepDolphin
```

安装：`cmake --install build --prefix /usr`（binary → bin，desktop →
share/applications/cn.deepdolphin.app.desktop，图标 → share/icons/hicolor/scalable/apps）。
安装后由系统 Qt6/DTK6 运行库满足链接，无需上述环境变量。

本阶段实测记录：`--selfcheck` 55 通过 0 失败；`--version` 输出 `deepDolphin 0.1.0`；
offscreen 启动探测 `timeout 8` 退出码 124（进程存活满 8 秒）；`ldd` 裸环境报 Qt6/DTK6 not found、
带上 `LD_LIBRARY_PATH` 后 0 个 not found。**运行期环境变量**（sysroot 方案的代价，打包后消失）：
`LD_LIBRARY_PATH=~/.local/dd-sysroot/usr/lib/x86_64-linux-gnu`（Qt/DTK 运行库）+
`QT_PLUGIN_PATH=~/.local/dd-sysroot/usr/lib/x86_64-linux-gnu/qt6/plugins`（xcb/offscreen 平台插件、
样式插件）；已拷入宿主的 `libchameleon.so`（DTK 样式）与 `libdxcb.so`（DTK 平台）到对应插件目录。

## 引擎安装前提

引擎是唯一业务核心，客户端零业务数据（进度库在引擎侧 `~/.deepgit/`）。deepin 客户端**不带引擎**，
按下述顺序发现（`src/app/EngineLocator.cpp:20-49`，探活 = `version` 子命令 8 秒内 exit 0）：

1. **`DEEPGIT_BIN`**：非空即必须可用，不可用 → 报错停止，**不静默跳到下一个候选**；
2. 仓内开发构建 `<工作区根>/moonGit/target/release/bin/main`（从可执行文件位置上溯三级推工作区根）；
3. `~/.local/bin`、`/usr/local/bin`、`/usr/bin` 上的 `moongit`（及兼容软链 `deepgit`）；
4. `PATH`（`QStandardPaths::findExecutable`）。

**安装引擎**（Linux 实测路径，2026-10-03 本机全链路跑通；仓内 `install.sh` 是 mac 导向的，Linux 按下述来）：

```sh
# 1. 仓颉 SDK LTS 1.0.5（linux-x64，约 269MB）。官方下载页的直链形如
#    https://cangjie-lang.cn/v1/files/auth/downLoad?nsId=142267&fileName=cangjie-sdk-linux-x64-1.0.5.tar.gz&objectKey=…
#    解到 ~/.local/share/cangjie/1.0.5/（内层还有一层 cangjie/），并：
ln -sfn ~/.local/share/cangjie/1.0.5 ~/.local/share/cangjie/current
# 2. 无系统 gcc 的容器里，cjpm 链接期要 crtbeginS.o/crtendS.o（GCC 内部对象，GNU ld
#    对裸文件名只搜当前目录与链接脚本 SEARCH_DIR）——从 sysroot 软链进引擎仓库根
#    （*.o 已被引擎仓 .gitignore 覆盖，不会弄脏 git status）：
ln -sf ~/.local/dd-sysroot/usr/lib/gcc/x86_64-linux-gnu/13/crtbeginS.o ~/code/moongit/
ln -sf ~/.local/dd-sysroot/usr/lib/gcc/x86_64-linux-gnu/13/crtendS.o   ~/code/moongit/
# 3. 构建。注意 cjpm.toml 的 link-option 是 darwin 专属（@executable_path 是 Mach-O 概念，
#    Linux ld.so 不认且 $ORIGIN 才是等价物）——因此不装裸二进制，改用第 4 步的启动器：
source ~/.local/share/cangjie/current/cangjie/envsetup.sh
(cd ~/code/moongit && cjpm build)
# 4. 安装 = 启动器脚本（~/.local/bin/moongit，deepgit 软链兼容旧脚本）+ 真实二进制
#    + 两个仓颉运行库，与 cwd / 调用方环境完全无关：
cp ~/code/moongit/target/release/bin/main ~/.local/libexec/deepdolphin/moongit.bin
mkdir -p ~/.local/runtime
cp "$HOME/.local/share/cangjie/current/cangjie/runtime/lib/linux_x86_64_cjnative/"libcangjie-runtime.so \
   "$HOME/.local/share/cangjie/current/cangjie/runtime/lib/linux_x86_64_cjnative/libboundscheck.so" \
   ~/.local/runtime/
cat > ~/.local/bin/moongit <<'EOF'
#!/bin/sh
exec env LD_LIBRARY_PATH="$HOME/.local/runtime${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$HOME/.local/libexec/deepdolphin/moongit.bin" "$@"
EOF
chmod +x ~/.local/bin/moongit && ln -sf moongit ~/.local/bin/deepgit
# 5. 验证
moongit doctor && deepgit list
```

装好后回到客户端点「重新检测引擎」（SetupGuidePage）。引擎缺席时客户端首启进入安装指引页并给明确报错
（本阶段 offscreen 实测原文：「引擎未找到：在 DEEPGIT_BIN、开发构建目录、~/.local/bin、/usr/local/bin
与 PATH 上都没有找到可用的 moongit/deepgit…」，**不静默失败**）。
`DEEPGIT_BIN` / `DEEPGIT_HOME` 环境变量名沿用旧名不改（外部调用方的既有接口，见根 README）。

## 系统级 AI：默认引擎与降级行为

AI 层归客户端（CHARTER C5–C7）。后端优先级（`ai/AIEngineFactory.cpp`）：

1. **显式渠道优先**：AIConfig.isConfigured（baseURL 非空 &&（ollama/mock 或 key 非空））→
   OpenAI 兼容 / Anthropic / Mock；
2. **否则 → 系统级 AI**（`SystemAiEngine`，默认后端，免端点免 Key）。

**系统级 AI 的真实能力与诚实边界**（实测依据见决策 20）：UOS AI（uos-ai）在会话总线
`com.deepin.copilot` 上的 `/org/deepin/copilot/chat` 只暴露 `inputPrompt(s, a{ss})` **无返回值**
（fire-and-forget 唤起对话窗口），**没有程序化补全出口**。因此：

- `isConfigured = probe()`（先 `isServiceRegistered`，再 `activatableServiceNames`，进程内缓存）；
- 唯一真实能力 `launchChat()` 唤起对话窗口，在 AgentDialog 底部以「用 UOS AI 打开这个问题」暴露；
- `generate()` **恒返回降级文案，不假装能补全**：服务在总线 → 「不支持程序化补全」类文案；
  服务缺席 → 「AI 未检测到服务 / AI 未配置：…」。两种状态分开说，不混为一谈。

**降级纪律**（CHARTER §3 验收项）：AI 未配置/不可用时**更新动作照常可用**（仅无摘要）；
每条 AI 出口都区分「跑成了 / 没跑成（附原因与下一步）/ 跑了但没产出」，永不静默。
key 只进 libsecret（service=cn.deepdolphin.app.ai / account=api-key），不进日志与配置文件明文；
空 key 保存 = 真删安全存储条目。

设置页 provider 下拉有两个**目录之外的恒置顶项**：「系统级 AI（默认）」（id=system，禁用模型/Key 区）、
「mock · 本地自测」（id=mock，Base URL 的 `#` 片段即自测脚本）。

## C1–C11 逐项实现位置

对照 `PLATFORM-CHARTER.md` 矩阵，逐项给出落点（均已在源码核对）：

| # | 能力 | 实现位置 |
|---|---|---|
| C1 | 引擎发现与拉起 | `app/EngineLocator.cpp:20-49`（发现链 + DEEPGIT_BIN 不可用即报错）；`app/EngineCli.{h,cpp}`（子进程拉起/超时收尾：SIGTERM→2s→SIGKILL→2.5s 兜底）；`ui/pages/SetupGuidePage`（未装引导 + 重新检测）；`app/ProcessRegistry.cpp`（进程账本与真停止） |
| C2 | 状态轮询 | `app/AppModel.cpp`：status→dashboard→milestones 顺序刷新（失败短路）、RefreshGate、`AppModel.cpp:109`（300s 轻刷新）、手动刷新（Ctrl+R / 菜单） |
| C3 | 面板四页 | `ui/pages/{DashboardPage,BoardPage,MilestonesPage,ProjectDetailPage}.cpp` + `PanelWindow` 页面栈；判定层 `logic/Derived`（liveness 六档顺序 / needsAction / boardColumn / pulseLine / branchScopeLine）、`DashboardScope`、`DashFilter`、`CommitTypeComposition`、`LanguageCoverage`、`MilestoneCardTitle`、`SearchFilter`（两种空态分开）；托管文档四态在 ProjectDetailPage |
| C4 | 更新动作 | `ui/DualTrackButtons`（浅/深双轨，唯一入口，读 selection 推导范围）；`AppModel::runUpdateInternal`（AppModel.h:173）与 `updateAll`（:111，先刷新再冻结 / 逐仓库显式传名 / 一个失败不中断）；停止更新真 terminate |
| C5 | AI 整合更新 | `AppModel::runUpdateDigest`（AppModel.h:110）+ 详情页更新菜单两个 AI 变体；`ai/AiDigests.{h,cpp}` 五入口（groupBrief/projectBrief/updateDigest/scheduledDigest/bulkDigest，AiDigests.h:21-26）；`ui/dialogs/AiResultDialog`（busy→正文/错误，错误可重新生成）；定时简报经通知 |
| C6 | AI 助手 | `ai/AgentCore.cpp`（上下文包 `context --budget 9000 --json` 60s + 工具清单 `tools --json` 30s + 工具循环 ≤4 轮：畸形参数先拦 → 必填校验在执行点 → 输出 16000 截断自报 → 三态收尾）；`ui/dialogs/AgentDialog`；`models/ContextEnvelope`、`ToolsEnvelope`；`ai/ToolArgs`；`ui/common/MarkdownView` 渲染 |
| C7 | AI 设置 | `ui/dialogs/AiSettingsDialog` + `panes/AiSettingsPane`（models.dev 目录驱动 provider/model 选择器 + 系统级 AI/mock 恒置顶）；`ai/AIConfig`（QSettings 身份 + libsecret key）、`ai/SecretStore`（同步 API，全面退出 GUI 线程）、`ai/ModelsDevCatalog`、`ai/AIChannel`（测试连接，双协议） |
| C8 | git 操作 | 详情页页头 `gitOpButtons` 唯一构造点（ProjectDetailPage.cpp:256，pull/push/fetch + stash/unstash，busy 禁用+转圈）+ 「提交改动」卡（--message）；`app/AppModel` git 操作走 `git <op> <项目> --json`；`models/GitOpResponse.h`；确认矩阵 `logic/DestructiveGuard.h`（删/放弃/批量/提交确认，达成/重开不确认） |
| C9 | 里程碑管理 | `ui/pages/MilestonesPage`（搜索/仓库筛选/按项目分组统计）+ `MilestoneRowWidget`（行内五态）+ `ui/dialogs/AddMilestoneDialog`（tag/date/desc）；`AppModel` milestone CRUD 走 `milestone <子命令> --json`；`models/Milestone{,Write}.h` |
| C10 | 系统集成 | 托盘：`tray/TrayController.cpp`（五态图标，refreshIcon(menuTitle, tint)，tooltip=menuTitle，:92-96）+ `TrayPopupWindow`（速览弹窗）；通知：`app/Notifier.cpp`（DNotifySender:42 + ActionInvoked→叫醒面板，replaceId 防堆积）；自启：`platform/AutostartManager.cpp`（XDG，:83 唯一文件写入点） |
| C11 | 文档完整性承诺 | 客户端**唯一的业务文件写入 = 没有**：全 src 检索 `QSaveFile/WriteOnly` 仅 `AutostartManager.cpp:83` 一处（写自启 `.desktop`，非项目文档）；一切文档/进度写操作只经 `EngineCli` 子进程打给引擎（备份与托管区域由引擎保证，`moongit verify` 可校验） |

## 取舍与已知边界

> 沿用 `macos/README.md` 的记录文化：拿不准时按最合理预案定，但**每个取舍写清「为什么这么定、已知代价」**。
> 以下是本仓库 deepin/ 从立项到交付实际发生的设计决定，按阶段全录。

### 基础框架阶段（决策 1–10）

1. **文件清单按阶段裁剪**：PLAN §3 的 `add_executable` 是全量终态清单；实现只列**已存在**
   的文件（models/app 逻辑/tray 壳/ui 壳），页面、AI、AppModel、Notifier、AutostartManager、
   SysOpen、DesignTokens 等随其实现阶段同步加入（CMakeLists 有显式提醒注释）。
   `tests/` 子目录随 PLAN 里程碑 2 加入；当前模型层冒烟判据由二进制内置 `--selfcheck`
   承担（55 例，含缺键拒绝/契约过旧判据/双形态 update/shallow-deep 分派等 CONTRACT 红线）。
   代价：CMakeLists 与 PLAN 清单阶段性地不一致，靠注释锚点防丢失。
2. **托盘数据对接用 `TraySnapshot` 纯结构体**，而非 PLAN 签名里的 `AppModel*`：
   AppModel 属里程碑 3，提前引入会迫使托盘壳依赖一个不存在的类型。AppModel 落地后由它
   填 snapshot（`TrayController::refreshFrom(snapshot)`），签名最终对齐。
3. **`logic/Liveness.h` 单独成头**：PLAN 把 `enum class Liveness` 放在 Derived.h 里；
   托盘/侧栏壳只消费枚举，提前拉入 Derived 全部判定会迫使本阶段实现里程碑 2 的逻辑层。
   Derived.h 实现时 include 本头收编。
4. **`logic/Scope` 只实现 scopeFromSelection/scopeTitle/busyFor**：`pendingFor` 需要
   `Derived::needsAction`，为不内联第二份判定而留待彼时——判定不许有两份真相源。
5. **EngineLocator 发现链取任务书与 PLAN 的并集**：`DEEPGIT_BIN`（非空且不可用 → 报错停，
   不静默跳过）→ 仓内开发构建 `<工作区根>/moonGit/target/release/bin/main`（从可执行文件
   位置上溯三级推工作区根）→ `~/.local/bin`、`/usr/local/bin`、`/usr/bin` 的
   moongit→deepgit → PATH（`QStandardPaths::findExecutable`）。探活 = `version` 8s exit 0。
6. **`EngineJson::take` 返回 `QJsonValue`**（PLAN 表格里写 QJsonObject，按语义修正——
   泛型取键必须能返回字符串/数组/布尔；仅签名微调，键名纪律不变）。
7. **EngineCli 超时收尾**：超时先 SIGTERM、2s 宽限后 SIGKILL、再 2.5s 兜底强制收尾分类；
   错误分类按 CONTRACT §4（exit≠0 + stdout JSON → failedWithPayload 载荷保留；
   stdout 非 JSON → stdout 主因 + stderr 补充；timeout 与 cancelled 文案分开）。
8. **主窗口壳的工具栏只挂操作菜单**（DTitlebar::setMenu）：浅更新/深更新/停止更新/设置
   以禁用态占位（对应实现属后续阶段，不画假按钮）；刷新动作真实可用，但 AppModel
   落地前只发信号并把状态条拨回「尚未刷新」——不假装刷新成功。
9. **「添加 / 扫描项目」按钮**当前发出信号并在后续阶段接 ScanDialog；
   侧栏项目行渲染已按 mac 语义实现（`●N` 橙计数、`仓库（x/y）`标题），AppModel 喂数据即生效。
10. **关闭面板 = 隐藏到托盘**（托盘常驻 + 菜单「退出」）；Linux 托盘必须有退出项，
    mac Dock 菜单的两项纪律照保（打开面板/全部浅更新，退出为 Linux 必要补充）。

### 页面层阶段（决策 11–19）

11. **AI 层边界**：PLAN §2.5 的 `ai/`（AgentCore 工具循环/AiDigests/AgentBulkUpdate/
    AgentPrompts）属后续阶段。该阶段先实现设置页 C7 所需最小集：`AIConfig`（QSettings 身份 +
    libsecret key + mock 明文）、`SecretStore`（libsecret 同步 API，schema
    service=cn.deepdolphin.app.ai/account=api-key）、`ModelsDevCatalog`（qrc 快照 →
    ~/.local/share 缓存；后台静默刷新，成功才置 `models-dev.refreshed`；畸形→空目录）、
    `AIChannel`（**仅测试连接**：OpenAI 兼容/Anthropic 双协议、stream:false、URL 只放行
    https 与 http://127.0.0.1/localhost、错误脱敏前 300 字）。工具栏「AI 助手」与各页
    「项目说明/项目群说明」按钮按下时**诚实降级**：未配置 → 「AI 未配置：…」；已配置但
    会话层未落地 → 明说「AI 会话层尚未在本构建中启用」。更新动作不受影响（CHARTER §3 验收项）。
12. **双轨按钮入口唯一**：PLAN §2.6 把 DualTrackButtons 同时列在「工具栏」与 WorkBar 两处；
    为守「同一个动作一屏两入口=复发缺陷」红线，只保留 WorkBar 一处（与范围选择器
    同排，读 selection 推导范围）。
13. **DTK6 dev 头文件的实测差异**（⚠️ 测于第一代 sysroot 的 dev 6.0.38，见「构建与运行」历史注记；
    第二代已对齐 6.7.47，下列 API 差异中因版本缺失的项随之消失，因产品形态缺失的项仍成立）：
    · 无 `DDualButton`/`DPushButton`/`DSegmentedControl`/`DTabWidget`/`DPlainTextButton`——
      分段条用 QButtonGroup+QPushButton(QSS 高亮)，页签用 DTabBar+QStackedWidget，
      里程碑行内直达按钮用 QPushButton(flat)；
    · DDialog 无 `clickedButtonIndex()`——确认框用 `setOnButtonClickedClose(false)` +
      `buttonClicked(int,QString)` 信号判别；破坏性确认按钮用 DWarningButton 顶插；
    · `DSwitchButton::checkedChanged(bool)`、`DSpinner`、`DSearchEdit`（textChanged 走基类
      DLineEdit）、`DNotifySender`（Dtk6::Core，`replaceId` 防速览中心堆积）均实证可用；
    · **`<libsecret/secret.h>` 必须先于任何 Qt 头**：glib 的 `GDBusInterfaceInfo.signals`
      成员会被 Qt 的 `signals` 宏改名，炸出 "expected unqualified-id before 'public'"。
14. **设计 tokens（PLAN §8 T1 的落地形态）**：`ui/DesignTokens.h/.cpp`——间距 6 档/圆角 3 档
    逐值对齐 mac DSSpacing/DSRadius；**语义色保留 mac 取值**（accent #3B82F6、shallow 绿
    #10B981、deep 紫 #8B5CF6、ai 青 #06B6D4、橙 #F59E0B、红 #DC2626、黄 #E8B01C、灰
    #9CA3AF）；表面/文字三级接 DTK 调色板（DGuiApplicationHelper::applicationPalette，亮暗
    自适应）；字体层级 6 档 px 常量（metric 20/cardTitle 13/sectionTitle 15/body/label 11/
    badge 10）。12 色序列色板在 `logic/CommitTypeComposition`（容量外不取模，越界返回无效
    QColor，调用方必须先切片）。
15. **编译期修掉的撞名**：`logic/CommitTypeComposition.h` 的脉冲行常量不叫 `LINE_MAX`
    （glibc limits.h 已有同名宏，展开后炸 QColor 链）→ `PULSE_LINE_MAX`。
16. **侧栏「看板/里程碑」行尾计数**与 **KPI/看板列**同源：attentionCount（needsAction 项目数，
    不受时间窗筛选）/ milestoneBadge（counts.open+done，unknown 不进）；读不出来 → nullopt
    不显示。侧栏行内计数全部 WA_TransparentForMouseEvents（「.badge 吃点击」的等价防御），
    计数控件经 row property 回取（绕开 findChildren 的 Q_OBJECT 约束）。
17. **进入详情页的取数时机**：selection 变更时 `loadProject`（go 内置）+ `loadDocs` 各一次；
    刷新周期/写操作回读不重触发详情取数（防 projectChanged→refreshChrome→navigate→
    loadProject 的信号环）。
18. **托盘速览弹窗位置**沿用 PLAN §8 T4（X11 贴 QSystemTrayIcon::geometry()，取不到落屏幕
    右上）；弹窗行内容按 SPEC §1.7 补齐（●N 橙、pending 蓝数字+44px 迷你条、副标题三级
    回退、busy「…」、子控件全透鼠标整行可点）。
19. **快捷键 Ctrl+Shift+U（浅更新）**：按 PLAN §8 T10 预案保持绑定；容器内无真实 IME 可测，
    真机 DDE 上如与 Unicode 输入冲突，不改语义、菜单显示实际序列（**待真机实测**）。

### AI 层阶段（决策 20–27）

20. **系统级 AI 默认后端 =「唤起 + 明确报错」，不假装能补全**（PLAN §5.1/§5.3，env.md §4
    实测）：UOS AI（uos-ai 3.3.0.001）在会话总线 `com.deepin.copilot` 上的
    `/org/deepin/copilot/chat` 只暴露 `inputPrompt(s, a{ss})` **无返回值**（fire-and-forget
    唤起对话窗口），主对象全是 UI 唤起/状态方法——**没有程序化补全出口**。因此
    `SystemAiEngine`：`isConfigured = probe()`（先 `isServiceRegistered`，再
    `activatableServiceNames`，进程内缓存）；`generate()` 恒返回 PLAN §5.3 逐字降级文案
    （服务缺席时给「AI 未配置：…」原文）；唯一真实能力 `launchChat()` 唤起对话窗口，
    在 AgentDialog 底部以「用 UOS AI 打开这个问题」暴露。`inputPrompt` 的 `a{ss} params`
    语义未公开文档化，首版只带 `{"source":"deepDolphin"}` 标记来源（实测：服务在
    总线且调用达即认为唤起成功；无返回值无法进一步验证窗口真已打开——如实记录此边界）。
21. **后端优先级**（AIEngineFactory，PLAN §5.2）：显式渠道（AIConfig.isConfigured：
    baseURL 非空 &&（ollama/mock 或 key 非空））→ OpenAI 兼容/Anthropic/Mock；
    否则 → SystemAiEngine。配置读取：providerID/model/baseURL 进 QSettings
    （ai.providerID/ai.model/ai.baseURL），key 只进 libsecret
    （service=cn.deepdolphin.app.ai / account=api-key），明文 ai.apiKey 仅 mock/无头自测。
    provider 下拉新增两个**目录之外的恒置顶项**：「系统级 AI（默认）」id=system（免端点
    免 Key，禁用模型/Key 区）、「mock · 本地自测」id=mock（基址只是脚本载体）。
    空 key 保存 = 真**删**安全存储条目（mac AISDK.save 对位）。
22. **OpenAI 兼容 / Anthropic 双协议**（PLAN §5.4，SPEC §4.2 逐条）：共用 `AIChannel`
    HTTP 传输层（https 与 http://127.0.0.1/localhost 白名单、stream:false、120s、
    Bearer / x-api-key + anthropic-version、错误体脱敏前 300 字、工具输出原生
    tool_calls / tool_use+tool_result 线格式）；网络错误按 QNetworkReply::NetworkError
    映射 13 支「中文 + 下一步建议」（mac AIErrorMessage 对位）；`hostOf` 只取 host:port
    防 URL 里的 key 外泄。模型 id 空时 OpenAI 兼容侧发请求由服务端决定默认模型——
    空模型 id 是用户要修的配置问题，测试连接会如实把 HTTP 错误带回来。
23. **agent 工具循环**（AgentCore，PLAN §5.6 对齐 mac AgentCore）：上下文包
    `context [名] --budget 9000 --json`（60s，解码失败的说明与正文一起给模型）；
    工具清单 `tools --json`（30s，**原文进系统提示词**）；ToolDef.params "a,b(c)" →
    全部 string 型必填（括号注记段剥掉）；必填校验**只从已发给模型的那份
    parametersJSON 取**（单一来源）。执行守卫顺序固定：畸形/空串/顶层非对象 → 执行前拦
    → 必填校验在 executeTool 内部（空白等同缺）→ 输出 >16000 截断自报 →
    onEvent「🔧 / ✓✗」。10 个工具与 CONTRACT §5.1 严格相等；`git_pull_push` 的 op 白名单
    pull|push（越界明说拒绝，PLAN §2.5 行 507）。撞 4 轮上限收尾 = AgentOutcome 三态；
    **一处对 mac 的有意修正**：executedSummary 只统计**真正执行成功**的工具名
    （mac 传的是本轮全部 toolCalls 名单，含被拒的——「已经执行完并且生效了」这句话
    不能点名没跑过的工具）。取消：QAtomicInt 逐轮检查；已 spawn 的引擎子进程由 CLI
    超时兜底（与 mac 同限制，如实记录）。
24. **AgentCore/AiDigests 全部同步阻塞、从 worker 线程进**：引擎调用走
    `EngineCli::runSync(args, timeout, bin)`（静态、QProcess 局部、线程安全，bin 空 →
    notFound 原文），HTTP 在 worker 内自建 QNAM+QEventLoop。**不进 ProcessRegistry**——
    「停止更新」杀不掉 agent 跑到一半的 update/deep 子进程，这是与 mac 相同的已知限制，
    靠 CLI 自身超时兜底。
25. **AI 助手页**（AgentDialog，PLAN §4.6）：固定 720×620；范围跟随 selection（成员复用
    一个对话框，selection 变化且未显示时 `retarget` 换范围并清历史——历史属于旧范围的
    上下文包）；transcript 三规则按 AgentConversation（tool 不显示、isError 必显、
    assistant 空 text →「（调用工具：…）」）；过程事件行 + busy 行 + 错误横幅（重发上一条
    把已发提问留回 history）；Ctrl+Return / Ctrl+Enter 发送；底部「用 UOS AI 打开」；
    空态示例群/项目两套（mac AgentView 逐字）；唯一动效 = 新消息自动滚动 0.20s。
26. **AI 简报接线**（AiDigests 五入口）：项目/项目群说明 → AiResultDialog（busy→正文/
    error，重新生成真传）；定时更新 → 简报经「定时更新简报」通知（≤180 字前缀；AI 失败 →
    「定时更新完成（AI 简报失败：<前 60>）」）；全量更新（UI 入口）→ bulkDigest 在
    worker 跑完后才交出报告（面板一次给出最终 aiNote）；定时场景不重复生成简报
    （silent 分支的 aiNote 指明简报走通知——对齐 mac：runScheduledUpdate 与
    UpdateActionMenu 是两条独立简报链）。`AgentBulkReport.rows` 升格为带 ok 位的
    AgentBulkRow（AI 简报表与结果面板共用同一份事实，不再丢「哪行失败」）。
27. **mock 通道自测脚本**（MockEngine，PLAN §8 T9）：假 provider 内置（mac 是外挂
    defaults+本地 HTTP 假服务，本实现简化为引擎内脚本）：Base URL 的 `#` 片段即脚本——
    `#final[=文本]` / `#tool=<名>[;args=<json>]` / `#fail[=原因]`；无片段时状态机自动编排
    （无 tool 结果 → 回第一个**无必填参数**的工具调用，收到结果 → 最终文本）——默认编排
    刻意避开有副作用的工具。全链路验证（AI 层阶段实测，桩引擎 + mock 渠道）：
    `DEEPGIT_BIN=<桩> ./build/deepDolphin --agent-selftest` → stdout
    `[selftest] FINAL: （mock）工具已执行（get_group_context）…` + `[selftest-done]`
    退出 0；`#tool=run_shallow_update`（args={}）→ 必填校验 4 轮全拒、空名从未到引擎，
    收尾 `已达工具调用轮次上限（4），且模型未产出任何文本` 退出 1。

### 评审修复阶段（决策 28–35）

28. **「停止更新」两步语义补全 + 批量链生命周期**：① `ProcessRegistry` 对
    `userStopped` 的清除延后一拍（`QTimer::singleShot(0)`）——本表在
    `registerProcess` 里先连接 finished/Crashed 槽，EngineCli 的收尾槽后连接，
    同一次 finished 派发里它还要读 `wasUserStopped`；当场清除使「被停」恒被
    误报成「引擎进程异常退出」（离屏对照实测：旧行为收尾槽读到 0，新行为读到 1）。
    ② `runBulkOverFrozenTargets` 的逐仓库循环见 `m_bulkStopRequested`（stopUpdate
    置位、updateAll 入口清除）即不再启动剩余仓库；**busyAll/busyProjects 不再在
    stopUpdate 里提前复位**——提前复位会让新一轮 updateAll 与残留旧链并发，真收尾
    在各回调里（cancelled 回调同样要走到，故 `runUpdateInternal` 被停时也调
    `onDone(false,nullptr)`，只是不写 lastError/不弹通知）。中途停止后
    `AgentBulkReport::toMarkdown` 的「实际执行」改按 `rows.size()`（attempted 只作
    「已注册」分母，账对得上）。
29. **updateAll 闸门连接存成员**（`m_bulkGate`，AppModel.h:203）：不能把
    `QMetaObject::Connection` 按值捕获进自身初始化器——lambda 是 connect 的实参，捕获到的是未初始化副本，
    `disconnect` 断不开真连接（UB），每轮 refreshCycleFinished（含 300s 轻刷新收尾）
    都会重跑全量更新。附带修掉 `shared->next` 收尾分支的 use-after-free：正在执行的
    就是 `shared` 持有的 functor，`delete shared` 后再调其捕获 `finalize` 读到的是
    被复用的内存（离屏桩引擎实测停止路径 `this` 变垃圾指针必现段错误）——先拷出
    `finalize`/report，`shared` 销毁延后一拍。
30. **结果面板只随 UI 入口弹**：`bulkReportReady` 移进 `finish` 的 `if (!silent)`
    分支（mac `updateAll(silent:)` 从不设 `agentBulkResult`）——定时更新与仪表盘
    「重新索引」不再在后台偷偷弹「浅/深更新 · 全量」结果对话框（离屏实测 silent 下
    信号发射数为 0）。
31. **路由闩**：`PanelWindow::maybeApplyPendingRoute` 消费一次即置 `m_routeConsumed`
    （pending 不消费、apply/missing 都算判过；二实例深链 `applyRoute` 重置）——否则
    每次 refreshCycleFinished（含 300s 轻刷新）都对空路由拿到 {apply, dashboard} 并
    navigate，用户当前页面被周期性打回仪表盘。落地改走 `AppModel::go`（setSelection
    + 信号），侧栏高亮与页面栈同源，不再各改各的。
32. **添加/扫描结果接回主窗口说明条**（ScanDialog.h 注释里承诺而未接的线）：
    `addFinished`/`scanFinished` 在 wireModel 里接 `showRouteNotice`——成功文案、
    ScanCoverage 覆盖度披露（depthCapped/truncated/unreadable/共发现 0 个语义）与
    失败原因不再发进真空。
33. **看板四分组的行项目挂列头下**：`header->addChild(item)`（原 `addTopLevelItem`
    把四列退化成「四个头 + 一串平铺行」，列头计数与列出行数严格一致被破坏）；
    非空列头同样 `setExpanded(true)`。离屏实测：顶层 4 头、顶层项目行 0、
    列头下项目行合计 2、声明计数与实际行数一致。
34. **C5「更新 + AI 摘要」入口**（mac UpdateActionMenu 的 AI 变体对位）：
    `AppModel::runUpdateDigest`（真更新走 runUpdateInternal 同一把 busy 锁；成功后
    worker 里取 key + `AiDigests::updateDigest`）+ 详情页「更新」菜单新增
    「浅更新 + AI 摘要 / 深更新 + AI 报告」两项，结果经 `updateDigestReady` 回填
    AiResultDialog（busy → 正文/错误，错误态重新生成真传，更新被停/失败也发信号撤
    busy 态——窗不悬死）。
35. **同步 libsecret 全面退出 GUI 线程**（PLAN §2.5）：定时更新回调的 key 读取 +
    「已配置」判定、批量收尾 `finalize`（含 targets 为空分支）、showBrief 的配置
    快照、AgentDialog 构造（先给无 key 的初判，worker 回填）、AiSettingsDialog 保存
    （QSettings 单例只在 GUI 线程写身份/明文策略，libsecret 同步写在 worker）——
    钥匙串迟缓不再冻结界面。设置窗打开时的一次性 key 读取仍在 GUI 线程（一次性入口，
    按代码内注释口径可接受，如实记录）。

### 文档阶段（本阶段）新增取舍

36. **构建环境一节按磁盘实测重写**：原文记载的是第一代 sysroot（`~/.dd-sysroot` + `env.sh`，
    g++ 12.3、Dtk6 dev 6.0.38）。本阶段核对 `build/CMakeCache.txt`（CMAKE_CXX_COMPILER=
    `~/.local/bin/c++`、Qt6_DIR 指向 `~/.local/dd-sysroot`）与 `~/.local/bin` 包装脚本证实，
    最终构建实际走第二代方案（`scripts/setup-deps.sh` → PATH 包装器 → `~/.local/dd-sysroot`：
    g++ 13.2.0、Dtk6 dev=运行库=6.7.47）。为什么：文档与磁盘不符，后来者会 source 错 env.sh
    还以为是自己错了。代价：两代 sysroot 都在盘上，旧代不再是文档口径——将来清理时别误删
    当前代；决策 13 的版本差异记录保留为历史注记。
37. **offscreen 运行环境变量写全为三个**：本阶段实测只设 `QT_QPA_PLATFORM=offscreen` 会
    `Could not find the Qt platform plugin "offscreen"`——sysroot 化部署没有 qt.conf，
    必须同时给 `QT_PLUGIN_PATH`（offscreen 插件在 sysroot 的 qt6/plugins 下）与
    `LD_LIBRARY_PATH`（二进制无 rpath，裸 `ldd` 报 Qt6/DTK6 not found）。为什么：
    少写一个变量，冒烟结论就从「能启动」变成「起不来」，还不知所措。代价：无——
    是把隐含前提显式化。

### 冒烟暴露的边界（本阶段实测，区分代码缺陷与环境限制）

| 现象（日志原文见本节） | 定性 | 处置 |
|---|---|---|
| offscreen 启动 `timeout 8` 退出码 124（存活满 8s），无段错误/断言 | 通过 | — |
| 引擎缺席：启动日志给「引擎未找到：在 DEEPGIT_BIN、开发构建目录、~/.local/bin、/usr/local/bin 与 PATH 上都没有找到可用的 moongit/deepgit…请运行 moonGit/scripts/install.sh 安装引擎…」 | 通过（C1 降级路径：明确报错 + 安装引导，不静默） | — |
| `--agent-selftest` 在引擎缺席且无 AI 配置时：`[selftest] WARN: 引擎未找到…` + `[selftest] ERROR: 找不到 moonGit 引擎。请运行 moonGit/scripts/install.sh 安装，或设置环境变量 DEEPGIT_BIN 指向引擎二进制，然后重新检测。`，退出码 1 | 通过（响亮失败） | **边界**：无头自测走完整 AI 链路的前提是引擎在位——决策 27 的 FINAL 路径是带桩引擎实测的；引擎缺席时它如实报 ERROR 而不是假装跑通 |
| `dtkwidget/qt/qtbase/deepDolphin can not find qm files for locales zh_CN` 四条告警 | 环境限制 | sysroot 未装翻译包；不影响功能，真机安装后由系统翻译文件补齐。如后续要消音，需把 Qt/DTK 翻译 .qm 纳入 sysroot |
| `dtk.core.dsg: AppId is fetched from AM, and value is "zcode"` | 环境限制 | 容器会话无应用商店注册项，DSG AppId 回退到宿主进程名；真机经 .desktop 安装后取 `cn.deepdolphin.app` |
| `QObject::connect: No such signal QPlatformNativeInterface::systemTrayWindowChanged(QScreen*)` | 环境限制 | offscreen 无系统托盘；真 DDE 走 SNI 协议（与「运行期事实」一致）。托盘真实表现仍**待真机验证** |
| `desktop-file-validate` 未跑 | 工具缺席 | 容器内无该工具（`command -v` 为空）。`.desktop` 内容已人工核对（Exec/Icon/StartupWMClass/X-Deepin-Vendor），装真机后建议补跑 |
| `ctest`：无目标可跑 | 设计如此 | CMakeLists.txt:134 注释：`enable_testing()+tests/` 缓建，模型层冒烟判据由 `--selfcheck`（55 例）承担 |
| Ctrl+Shift+U 与输入法的潜在冲突 | 待真机验证 | 决策 19 预案：保持绑定、菜单显示实际序列；容器内无真实 IME，无法在本阶段闭环 |

### 真机联调阶段（2026-10-03 收尾，决策 36–44）

引擎装好、契约与页面在**真实引擎数据**上对账后，离屏快照逐页复核抓到的缺陷与决定：

| # | 决定 / 缺陷 | 证据 | 处置 |
|---|---|---|---|
| 36 | **启动数据路径不发 `projectsChanged`**：`runRefreshAll→fetchStatus` 成功回调只走 `fetchDashboard`，首屏后看板永远收不到数据到达（探针实证 `projects=0` 早退后再无 rebuild）；侧栏「仓库（0/0）」同根 | `AppModel::runRefreshAll`（对照 `refreshLight` 的回调有 emit） | 模型在 status 落地处如实广播 + BoardPage 订阅集与 DashboardPage 对齐（补 `dashboardChanged`）——双侧都修 |
| 37 | **`QLatin1String("中文")` 恒假比较**（7 处）：`QLatin1String` 把 UTF-8 字面量按 Latin-1 逐字节解释，`startsWith/==` 中文**永远 false**。后果三连：侧栏「仓库」表头永不更新（恒 0/0）、项目行插入点搜索失败（全插到列表顶、骑在「视图」组头上）、设置/结果/扫描对话框的按钮文案分支全死 | 快照实证 + grep 全仓 7 处（SidebarNav×2、AiSettingsDialog、AiResultDialog×3、ScanDialog、AddMilestoneDialog） | 全部改 `QStringLiteral`；推广判据：**含非 ASCII 字面量一律禁止 QLatin1String** |
| 38 | **item 文本 + setItemWidget 双重绘制**：`QListWidgetItem(带文本)` 再 `setItemWidget(含同名 QLabel)`，两层错位叠画（放大 3 倍截图实锤「仪表盘仪表盘」「🟠at atlas」重影） | `SidebarNav::rebuildProjectRows` / 视图行构造 | 用行 widget 的行 item 文本一律置空，文本唯一出处 = 行内 QLabel |
| 39 | 里程碑「明细被截」披露**常亮**：`milestoneTally(shown, nullptr)` 令 complete 恒 false，只要有里程碑橙色警告就出现（1==1 也报「只给了 1 条」）——警告常亮 = 警告失效 | `MilestonesPage.cpp:208/227` | 对账对象改为**引擎信封**（`milestones.size() != readCount`），且不计入搜索/项目筛选（筛选是用户意图不是引擎截断） |
| 40 | 里程碑动作文案读引擎不发的 `message` 键（评审 low-2，本轮修）：载荷实为 `{project, milestone, requested, status, applied}` | contract-check 断言「无 message 键」钉住 | 改读 `status`：达成显示「已达成里程碑「名」，当前状态 X」；被 tag 压回时透出实际状态 |
| 41 | 通知（评审 low-3，本轮修）：`notify({})` 把默认「打开面板」动作覆盖没了；`replaceId` 让后发通知顶掉未读的前一条 | `Notifier.h` 头注与实现不符 | 空 actions = 补默认动作（mac 全部通知可点进面板的等价物）；去掉一刀切 replaceId，动作归属按已知 id 集合判定 |
| 42 | 退出期 UAF（评审 low-4，本轮修）：agent worker 裸持 `&m_cancelFlag`，析构只置位不等待 | `AgentDialog.cpp` | 旗标改 `QSharedPointer`：每次发送一枚新旗标，worker 持引用计数副本，析构置位当前旗标即可安全退出 |
| 43 | 契约对账占位（评审 low-1，本轮修）：`contract-check.sh` 只探活即绿 | — | 重写为 **10 组真断言**（隔离沙箱造 fixture 仓）：status 恒等式/项目键、dashboard mergeCandidates、milestone readCount 对账、done 载荷（无 message 键）、scan 差值、update 双形状（单项目逐仓 `{ok,docs,…}` / 多项目聚合 `{count,results,succeeded,failed}`——实测发现并如实断言）、托管标记+用户哨兵逐字节保留、docs 回读。**实测 10/10** |
| 44 | `DashboardFilterBar::segSheet` 占位符错位：未选中分支没有 `%2`，调用方仍二级 `.arg`（真机会话日志 6 条 `QString::arg: Argument missing`） | 真机启动日志 | 占位符在函数内就地填满，调用点删掉两级 `.arg` |

**本阶段新增验证**（全部实跑）：`--selfcheck` 55/55；`contract-check.sh` 10/10（真引擎）；四页离屏快照
（仪表盘 KPI 与真实 3 项目一致：待处理 1 = atlas 可合入分支；看板四列 待处理 1/活跃 0/久未更新 2/其他 0
与 liveness 口径一致；里程碑页 atlas(1) + 统计 + 无截断不亮警告；详情页脉搏/提交构成/双分支进度）；
真机会话（`:0` 共享 X11 + 宿主 DDE 总线）启动存活 8s、SIGTERM 干净退出、`Argument missing` 告警清零。

**仍未覆盖**（如实记录）：qm 翻译文件未编译（4 条 can-not-find-qm 告警，文案回退英文键）；`dxcb` 平台插件
不在 sysroot 插件集（回退 xcb，真机会话功能正常但未经 DTK 原生合成器路径验证）；仓库 (3/3) 与看板徽标在
**真实窗口**下的像素级观感（离屏快照已验布局，真实 WM 的深浅色主题与字体渲染待人工过目）；deb/linglong
**打包**按用户要求推迟到最后。

### 视觉与 DDE 集成阶段（2026-10-03 收尾，决策 45–48）

用户实机过目后点名「不像 DDE 设计风格，像纯 Qt，集成感低」。逐层排查出四个根因，全部修复：

| # | 根因（实证） | 处置 |
|---|---|---|
| 45 | **DTK 样式插件 `libchameleon.so` 不在 sysroot**（qt6/plugins/styles/ 空）：DSuggestButton 画成白底白字（真机截图），QComboBox/QSS 全是 Qt 原生观感——这是「纯 Qt 感」的最终元凶 | 从宿主只读根拷入 styles/；`libdxcb.so`（DTK 平台插件）同理。chameleon 在本容器仍可能加载失败（dxcb 告警在），因此**观感不能赌插件**，见 46 |
| 46 | **普通 QWidget 不吃主题**：内容卡（自绘 QSS）跟 `DS::themed()` 走对了深色，但侧栏 QListWidget/顶栏/菜单全按 Qt 默认亮色画——「白侧栏 + 深内容」缝合体（用户截图实锤） | `main` 里按 `DS::isDarkTheme()` **整体装配 qApp 调色板**（deepin 规范值：窗 #F8F8F8/#252525、基色 白/#2D2D2D、文本 黑/白、次文 #808080/#A6A6A6、Highlight=强调色）——全部原生控件自动跟随亮/暗 |
| 47 | **DPalette 扩展语义角色不可静态取**：`standardPalette(Dark).color(ItemBackground/TextTitle/TextTips)` 真机探针实测全返回默认 #ffffff（这些角色只在 DTK 样式插件 polish 控件时注入），`applicationPalette` 同病且亮暗缝合（Window=#252525 其余 #ffffff） | `DS::` 语义色改**手写双主题映射**（deepin 官方视觉值，`themed(light,dark)` 唯一构造点）；accent 从 mac #3B82F6 换成 deepin 强调色（浅 #0081FF / 深 #3B9EFF） |
| 48 | 主操作按钮依赖 DSuggestButton（在无样式插件环境白底白字不可读） | 浅更新/提交改**强调色实底 QPushButton**（不依赖插件加载，任何环境观感一致）；深更新/其余保持普通按钮。`DEEPDOLPHIN_THEME=light\|dark` 环境变量可强制主题（快照/测试用；正常会话跟随系统） |

**本阶段验证**：真机 DDE 会话（用户桌面，深色主题）截图复核——侧栏/顶栏/内容一体深色、
「浅更新 · 全部」deepin 蓝实底白字、KPI 与次级文字全部可读；浅色主题离屏快照同套观感成立；
看板四列（待处理 1 / 活跃 0 / 久未更新 2 / 其他 0）与真实引擎数据一致。`--selfcheck` 55/55、
`contract-check.sh` 10/10 回归通过。仅截取本应用窗口（`_NET_CLIENT_LIST` 定位，XGetWindowProperty
匹配标题），不触碰桌面其他内容。

### DDE/DTK 生态与真机可用性阶段（2026-10-03，决策 49–63）

依据 `docs/DDE-INTEGRATION-PLAN.md`（本文档 M0/M1/M2/M3 的任务表；**执行进度与日志见该文档 §9/§10**）。
本轮已完成项及其取舍：

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 49 | 引擎发现改**异步**（`EngineLocator::locateAsync`：QThreadPool worker + QueuedConnection 回 GUI 线程），启动先 `panel.show()` 再探活，引擎找到才 `model.start()` | 候选最多 ~10 个、每个最坏 ≈11s：同步探活放在 `show()` 前 = 白屏数十秒；点「重新检测引擎」= UI 冻结（窗口管理器判未响应） | 首启多一次「正在检测引擎…」忙态（SetupGuidePage 的 DSpinner）；无引擎时不起周期 timer（重探测是唯一入口） |
| 50 | 「重新检测引擎」必须把 bin **回灌** `EngineCli`（`AppModel::setEngineResult`）；`engineMissing` 按 `engineBin().isEmpty()` 分流「从未发现」与「运行中丢失」 | 原实现只改 UI 文案：提示"引擎已找到"后每次调用仍走 engineMissing → notFound，且 `m_engineFound` 被翻回 false（状态抖动，必须重启应用）——必现的功能缺陷 | 新增 `engineFoundChanged` 信号，主窗口据此重算侧栏/工作条/首页路由 |
| 51 | 设置窗的 libsecret 读挪进 worker（构造只读身份），`m_keyPending` 回填前禁用「保存」 | 密钥环未解锁/卡住时，第一次打开设置会冻结界面数秒（同步读） | key 与身份有几个 QUeued 帧的短暂不同步（窗口此时禁用保存，不会覆盖） |
| 52 | `--agent-selftest` **恒强制 mock 渠道**；`--snapshot` 改轮询稳定态（数据落地/轮次收尾/未找到/pending，上限 15s 超时失败）；`--version` 与 `setApplicationVersion` 由 CMake `configure_file(src/app/Version.h.in)` 单源 | 原自测会用用户真 provider 打 HTTP 烧额度；原快照写死 2500ms，引擎慢时拍到 loading 态且退出码仍 0（错误截图会固化成基线）；版本号两处各写一份 | `--snapshot` 缺参改 exit 2（headless 必须响亮失败）；自测不再覆盖真实渠道 |
| 53 | 关键路径补日志：`EngineCli::callJson` 收尾（命令名+退出码+耗时，**不含参数与 stdout**）、SecretStore 失败（不含 key 本体）、AIChannel 失败（host+status+脱敏）；`DLogManager::registerJournalAppender()`；设置·通用页「日志」卡 + 打开日志目录 | 真机报障时 `~/.cache/deepin/deepDolphin/deepDolphin.log` 此前基本为空，只能靠 stderr 抓 | 日志只打命令名——排障深挖需要时另行加临时开关 |
| 54 | 表面/文字色**接 DTK 运行期调色板**（`QPalette::Window/Base/Text/Mid` + `DPalette::PlaceholderText`），accent 接 `DPalette::LightLively`（DTK 推荐按钮底色）；**调色板与主题不自洽时**（offscreen/无 DTK 配置：探针实证 `applicationPalette(DarkType)` 仍返回 Window=#F8F8F8）退回 deepin 规范值，`main` 只在此时 `setPalette(applicationPaletteFallback())` | 接调色板 = 用户改系统主题/深浅时原生控件与我们一起变；DTK 推荐按钮底色 = 我们的强调色与 DSuggestButton 永远同色。直接信调色板 = 暗色主题拿浅色值（白底黑字缝合体） | 真机上不 `setPalette`（DTK 会警告 "Don't use it on DTK application"），由 DTK 自己管；容器内兜底整套 palette 只由 `DS::` 令牌构造 |
| 55 | 字号接 `DFontManager` 档位：metric=T4(18)/sectionTitle=T5(14)/cardTitle=T6(12)/body·label=T7(11)/badge=T8(10)；Markdown 标题 T3/T4/T5 派生 | 用户在控制中心放大字号时全应用一起放大。原先 6 档硬编码 px + 3 处 QSS 内联字号，字号档位切换对本应用无效 | 正文字号从"应用默认"收敛到 T7=11px（DDE 内建应用同档），观感比原先略小但更原生 |
| 56 | 主题/字号变化的树内传播：`DS::tagSecondaryStyle/tagFont` 登记意图 + `DS::repolish(root)` 重算；接 `paletteTypeChanged/themeTypeChanged/applicationPaletteChanged/fontChanged` | 先前只接 `newProcessInstance`——会话中切主题，整树 `setStyleSheet(...)` 是构建时拍的快照，大面积停在旧色（一眼可见） | 28 处 `color: %1` 已收编为 tag；**标签上另设的字号/自绘色仍要各自登记**（未登记者切换后不跟随，属渐进项） |
| 57 | desktop 项补全：`Version/GenericName/Keywords[zh_CN]/SingleMainWindow/MimeType=inode/directory;/Actions(open,scan)`；`main.cpp` `setDesktopFileName("cn.deepdolphin.app")`；`--scan` 开关 + 位置参数（目录 → 预填 ScanDialog 的添加模式） | 桌面身份不完整 = 启动器搜不到（中文无关键字）、Wayland 不分组、通知点不回、右键无快捷动作 | `%f` 只吃**已存在的目录**（别的文件名不吃，不假装能处理）；`DBusActivatable` 暂不加（还没有 `.service`，M2-3 再开） |
| 58 | AI 设置页改用 DTK 原生输入件：key → `DPasswordEdit`（含眼睛切换），过滤/手动模型/Base URL → `DLineEdit`，provider/模型 → `DComboBox`，测试连接 → `DPushButton` | 原 `QLineEdit` 与头文件注释承诺的 `DPasswordEdit` 不一致（注释与实现漂移）；原生件才有 DDE 的焦点环/右键菜单/明暗观感 | `DLineEdit` 不是 `QLineEdit` 子类：`setClearButtonEnabled/text/textChanged` 全部改用 DLineEdit 自己的 API（信号是 `&DLineEdit::textChanged`） |
| 59 | SetupGuidePage 有忙态（DSpinner + 标题「正在检测引擎…」），pending 期间禁用重探测按钮 | 发现链在跑时马上下结论会闪烁「未找到 → 已找到」；busy 状态必须说出来 | 无 |
| 60 | 日志/引擎超时/密钥环失败的定位入口进设置页（日志目录一键打开，路径不可用时按钮禁用） | 报障自助 | 无 |
| 61 | `scripts/ci.sh`（selfcheck + 截图矩阵 + desktop-file-validate + platform-probe + agent-selftest）与 `scripts/build-system.sh`（系统 Qt6/DTK6 无 sysroot 矩阵） | 视觉回归没有截图门 = 没有回归；`DD_HAVE_QTSVG` 分支在容器里从未编译过 | 截图基线需人工确认（防把 bug 固化成基线） |
| 62 | 新增 3 例 `--selfcheck`：`--scan` 开关、`%f` 位置参数（目录吃/`--project` 的值不吃/非目录不吃） | 路由是纯函数层，新语义必须锁死 | 例数 55 → 58 |
| 63 | 视觉基线入库 `docs/snapshots/{light,dark}-{dashboard,board,milestones}.png` + `dark-setupguide.png` | CI 比对需要基线 | 基线是"空数据 + 桩引擎"状态（本容器无真引擎），真机数据态需另拍一套 |

**本轮验证**：`--selfcheck` 58/58；`--version=0.1.0`（与 CMake `project()` 一致）、`--snapshot`
缺参 exit 2、`--agent-selftest` exit 0（mock 通道 FINAL 文案正确）、四张主题/页面截图字节互不相同
（dark 为 #252525 底、light 为 #F8F8F8 底，无白底黑字缝合）；`desktop-file-validate` 仅 1 条
`Categories` 多主类 hint（`Utility;Development;` 为刻意保留：既是工具也是开发件）。
**未做（如实记录，见 plan §9 看板）**：M1a 其余控件替换（QPushButton/QListWidget/QTreeWidget/
QProgressBar/QScrollArea/Notification hint/自启模板/SNI/Wayland）、M2-3 起的 DBus 激活/i18n/图标集/deb、
M3-2 的响应式与 HiDPI、M4 拆分大文件。

| 64 | **会话总线服务** `cn.deepdolphin.app`（`src/platform/AppService.*`，对象 `/cn/deepdolphin/app`）：`Ping()` 探活 / `Activate()` 叫醒 / `OpenProject(name)` / `OpenPath(dir)`；desktop 项 `DBusActivatable=true` + `data/cn.deepdolphin.app.service`（面板没起来时会话总线自动拉起） | 没有总线名字时外部只能"再启动一个进程"（靠单实例转发参数），既不能探活也不能激活；deepin 上被别的应用/脚本/启动器集成的前提就是有 app id 对应的总线服务 | 总线名与 DTK 单实例不冲突（后者用 `com.deepin.SingleInstance.<key>`，dtk6widget 符号实证）；名字被占用时如实告警不静默 |
| 65 | `locateAsync` 的 worker→GUI 回调**只做值捕获**：`QRunnable` 跑完即自动删除，把 `this` 捕获进 `QMetaObject::invokeMethod(app, [this, r]{…})` 是必然的 use-after-free | 实测段错误：主线程进事件循环后立刻崩、连回调第一行日志都打不出来；`--snapshot` 路径不建 CLI 级异步路径所以复现不了，只有 GUI 启动路径会崩（`DD_BISECT` 逐位二分定位） | 回调只在 GUI 线程跑一次（worker 内先 swap 出来）；无 qApp 时就地执行 |
| 66 | 节流与降级：无引擎时**不启动周期 timer**（`model.start()` 只在引擎找到后调），重探测是唯一入口 | 探不到的机器上每分钟重试毫无意义，还会把 UI 反复拨回 setup guide | 用户装完引擎要点一次「重新检测引擎」（SetupGuidePage 常驻该按钮） |

**本轮新增验证**：GUI 启动路径（offscreen，真实引擎经 PATH 发现）存活 10s+ 不崩（段错误已修）；
`qdbus cn.deepdolphin.app /cn/deepdolphin/app cn.deepdolphin.app.Ping` → `ok`（真总线探活通过）；
`--snapshot` 亮/暗四张 + setup guide 两张入库 `docs/snapshots/`（本机 DDE 主题为深色，
未加 `DEEPDOLPHIN_THEME` 时跟随系统，证明接的不是"写死的暗色"而是运行期调色板）。

| 67 | **通知 hint 与 replaceId 分类**（`src/app/Notifier.cpp`）：一律带 `desktop-entry=cn.deepdolphin.app`、`image-path=deepdolphin`；「失败/停滞」这类**状态型**通知按类别持有同一 replaceId（后一条顶替前一条），用户关掉则清归属；更新完成/定时简报不顶替 | 缺 `desktop-entry` 时通知中心「点通知回应用」在不同 DDE 版本行为不一致；状态型通知不顶替会在通知中心堆成一摞（"引擎连接失败"每分钟刷一条） | 状态型通知不再可回看历史——与通知中心对"当前状态"的表达一致 |
| 68 | **自启三条硬规矩**：① 模板补 `OnlyShowIn=Deepin;`+`X-GNOME-Autostart-enabled`+`X-GNOME-Autostart-phase=Desktop`+`X-Deepin-Autostart`；② 已安装构建 Exec 用**安装名**（`deepDolphin`，不写绝对路径）；③ 开发树构建（可执行路径含 `/build/`）**拒绝开启自启**并说明"请先安装" | 写绝对路径在迁移/升级后变悬空；开发树二进制依赖 sysroot 运行库，登录时必然起不来，还会把深链参数转给一个错误的实例——写一条注定失败的自启项比不给选项更糟 | 开发中想验证自启必须先 `cmake --install`（这是有意的门槛） |
| 69 | **应用元信息入库**：`data/metainfo/cn.deepdolphin.app.metainfo.xml`（appstream）装到 `share/metainfo`，含中英文摘要/描述/截图文案/发布记录/`<dbus>` 能力 | 软件中心与「关于」展示都读它；没有 metainfo 的应用在商店里只有一行裸名字 | metainfo 未过 `appstream-util validate`（本机无该工具，硬门留 CI） |
| 70 | **agent 工具的引擎子进程可被「停止」终止**（M0-5）：`EngineCli::runSync` 改切片等待（200ms 粒度），取消旗标置位 → terminate（2s 后 kill）+ cancelled 结果；`AgentCore` 把旗标穿透 context/tools 与全部 10 个工具；UI 文案改诚实：「正在停止…（运行中的引擎调用将被终止）」+ 停止按钮 tooltip 明说后果 | 原先取消旗标只在轮间检查——agent 跑 `deep`（预算 600s）时点「停止」，引擎子进程照跑到超时，「停止」形同虚设 | 写类工具（update/deep/git）半途被终止的残留风险与「停止更新」批量链同款（同款 terminate→kill 语义，引擎收尾兜底）；此点**优于** mac 基准（mac 的同位置子进程不可 kill，只能等超时） |

**决策 70 验证**：build 通过、`--selfcheck` 58/58；`--agent-selftest`（mock 渠道）exit 0。
真机「agent 跑 deep 途中点停止 ≤200ms 内子进程收到 SIGTERM」需真机复验（headless 无真实引擎写场景）。

| 71 | **worker 线程 0 处直接读写 Settings 单例**（M0-4 收口）：`AIConfig::loadKey` 去掉内部 Settings 明文回退（改调用方显式传入）；`AppModel` 新增 `loadAiConfigWithFallbackKey()`（GUI 线程：身份 + 明文回退键）与 `loadAiKeyInWorker()`（worker：仅同步 libsecret 读）；8 处 worker（定时简报/单项目摘要/批量 AI 简报×2、AgentDialog probe/send、PanelWindow brief、AiSettingsPane 测试连接、AiSettingsDialog key 回填）一律「GUI 线程快照按值带进 worker」 | Settings 的 QSettings（QObject）在 worker 首次触达会跨线程告警（`QObject::setParent: Cannot set parent…`），且 QSettings 同对象跨线程读写无同步保证——快照按值传递让 Settings 的访问面收敛回 GUI 线程 | 明文回退键随快照复制多一份进 worker（内存多几十字节，仅 mock/headless 有值）；真机告警消失需真机复验 |
| 72 | **M1a 控件批换 DTK 原生的落地口径**：① 本版 DTK6（libdtk6widget 6.7.47）里 `DScrollArea/DPushButton/DTreeView/DHeaderView` 是 Qt 类 **typedef**（dwidgetstype.h）——换名表意、行为不变，真 DTk 件是 `DTextEdit/DLineEdit/DComboBox/DSpinBox/DProgressBar/DWarningButton/DIconButton/DSuggestButton`；② `DWarningButton` 只有默认构造（setText 另行调用）、`DIconButton` 不开放 setText——工具栏图标钮做 `makeToolButton`：主题图标在位走 DIconButton，解析不到（无图标主题环境）退文字平钮，空按钮比非原生按钮更糟（R2）；③ 主操作 `DSuggestButton` + 仅容器内（`DS::paletteIsThemeConsistent()` 探针，与 main 调色板兜底同判据）上 DS:: 兜底 QSS——废弃的 `loadDXcbPlugin()` 不再作判据；④ tray 层色值清零（红/橙/第二蓝归并语义色），palette(mid/midlight/text) QSS 9 处收编 DS::*，AutomationPane segSheet 改自包含（计划坑 #3 的跨函数 .arg 告警模式清掉） | 「纯 Qt 感」的第一眼来源就是输入件与按钮；统一颜色语言后 D2 grep 门全仓命中 24→4（余 4 处为 M3-3 已登记字号项） | 「AI 助手」无 freedesktop 标准图标名恒文字钮（硬造图标名会静默空按钮）；容器/视图批（DListView/DTreeView/DBlurEffectWidget/DButtonBox）与徽章 DTipLabel 化待后续（模型重构/语义色不兼容，见 plan §9 M1a 行） |

### 计划批次执行阶段（2026-10-04，三轨道并行，决策 73–83）

本批按 `docs/DDE-INTEGRATION-PLAN.md` 分三轨道并行落地并全部合并回 main
（track-a = M3-5/M3-6/M3-7/M3b×3、track-b = M1-1/M1-6/M1-9/M4b/M4c、track-c = M2-6）；
主树构建 + `--selfcheck` 66 例全绿。执行日志见该文档 §10、看板勾选见 §9。
有实质取舍的任务按仓内「决策 + 为什么 + 已知代价」文化续录：

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 73 | **M3-5 几何收口：`DS::Height/Radius` 进 DesignTokens，窗口/控件圆角走运行期 metric**：Height 四档（bar=6/barMini=4/dot=8/dotLg=10）直接 constexpr；`Radius::window()/frame()` 走 `DStyle` pixelMetric（offscreen/fusion 探针实测 libdtk6widget 6.7.47 基类默认 18/8），**非正值退既有档位（card/control）绝不退 0**，真机 chameleon 下随 DDE 圆角设置走；按钮 padding 四档收成 `buttonPaddingQss()=「4px 16px」`（Spacing::xs×lg，不另立数值）单点、四处 QSS 自包含拼入；进度条统一 bar=6、托盘迷你条 barMini=4、圆点按「行内/汇总态」分 dot/dotLg 两档；游离圆角四处归位（错误条 4→control、徽章 8→pill、气泡 10→card、托盘弹窗顶层接 window()） | 「同类控件几种尺寸」的根因是字面量散落；window/frame 是运行期 metric，写死会背叛 R3（真机圆角应随系统设置） | 刻意视觉变更已随基线同 commit 固化：SegmentedBar 8→6、分段钮 padding 变大、侧栏行圆点 10→8、错误条圆角 4→6、托盘弹窗圆角 10→window()（offscreen 下 18px）；window()/frame() 每次走 pixelMetric 不缓存（托盘 paintEvent 调用量极低）；`Radius::frame()` 暂无消费点（M3b 预留）；setupguide 两张基线未随错误条圆角重拍（差 2px） |
| 74 | **M3-7 阈值/托盘几何 token：按真实语义命名，托盘几何留 tray/ 分册**：`logic/Thresholds.h` 里计划措辞的「未提交 10/分桶 10」实证是 AppModel 通知的**改动条数门槛与十位分桶宽**（AppModel.cpp:1110-1111，不是「天数」），按真实语义命名 `dirtyNotifyMinCount/dirtyBucketWidth` 并在头注释写明出处；本轨内可接通的消费（quiet 30 天线 `Derived.cpp:70`、7/30 时间窗 `DashFilter.cpp:30`）已改 `activeDays30/activeDays7` 并用边界 fixtures 锁死；`tray/TrayGeometry.h`（380/12/44/4/120）不并入 `DS::*`——弹窗宽/列宽/行距是托盘域私有几何，非全应用视觉语言 | 任务措辞与代码不符处如实对齐语义，防后来者按「天数」误用；R1「三个收口」的托盘分册就此落位 | AppModel 的 10/10 消费点在 app 层（本批范围外）暂未接线，魔数暂留（常量与 selfcheck 锁值就位）；Thresholds 头注释与 selfcheck 把 10/10/7/30 写死为期望值，未来调阈值须同步两处；托盘感叹三角/感叹点坐标不收编（单调用点占位绘制，dd-*.svg 就位后整个 painter 替换，逐点起名只添间接层） |
| 75 | **M3-6 `Card::kPadding` 构造即设置 + 调用点布局清零**：{lg,md,lg,md} 收进 `Card::kPadding`，12 个调用点一律 `setContentsMargins(0,0,0,0)`——探针实证 widget contentsMargins 与所在布局默认边距（fusion 11px）**叠加而非覆盖**，不清零会双份内距；docs 失败/空态两卡（ProjectDetailPage.cpp:827/835）历史上从未显式设边距、走样式默认 11px，构造 kPadding 会叠出双份，加 `clearPadding()` opt-out | 间距单点的正确形态是「组件自带 + 容器让位」；两卡 opt-out 是为守「观感零变化」硬目标（逐像素实证成立） | 覆盖 14 张卡中 12 张，两卡留在单点之外（进单点约 5px 观感变化，属产品决策）；每调用点多一行 setContentsMargins(0)（叠加语义下的必要动作，非新魔法值） |
| 76 | **M3b `SecondaryLabel`/`SegmentedButton` 单一实现，header-only**：29 处「new QLabel+tagSecondaryStyle」收进 SecondaryLabel（内部同机制，主题/字号经 repolish 跟随）；DashboardFilterBar/AutomationPane 双份 segSheet 收进 SegmentedButton（`sheet()` 纯函数自包含，计划坑 #3 不复活）；双态/三态着色站点（告警红橙、状态回显）刻意保留不收 | 次级色复制是漂移面；告警色站点收进构造会让 repolish 把语义色冲回次级色，语义反而变差 | header-only 是被迫的：CMakeLists 在轨外不能加新 .cpp，且 AUTOMOC 只收 target 源文件的配对 header（header-only Q_OBJECT 链接期 vtable 未定义实证）——SegmentedButton 因此无 Q_OBJECT、onClicked 走 `std::function`（无自动断连，挂在调用方对象树同生共死）；分段钮新观感（钮距 sm→2px、圆角档）无快照覆盖，真机需目检 |
| 77 | **M3b `BusyRow` 尊重 `HasAnimations`；`EmptyState` 按「空 / 读不出来」图标分档**：BusyRow = DSpinner 16px + 文案，构造即忙、`setBusy` 起停；`testAttribute(HasAnimations)` 为假不 start()——信息不丢、不伪造动画（R6）；5 处散装 busy 表达收编 + 标题栏刷新钮 busy 让位转圈（同位同语义，顺带消掉忙时误点一个注定被 busy 锁拒绝的刷新）；EmptyState 增 iconTone 两档（空=dialog-information / 读不出来=dialog-warning）+ 主 CTA 槽位（仪表盘空态「添加 / 扫描项目」接 openScanDialog）+ compact 卡内版收编 DashboardPage 4 处内联空态 | 忙态必须说出来（决策 59 同原则）；「没有语言」与「语言读不出来」是两种状态，图标上要分档（采集失败 ≠ 没有语言） | 仪表盘里程碑 degraded 空态原橙字让位给 Warning 图标（卡内正文少一层颜色警示）；「重新索引」按钮文字不再随忙态变化（忙感靠旁边 BusyRow，禁用态仍在）；busy 转圈是瞬态，无基线可拍，offscreen 只证不崩；标题栏 busy 时按钮排有一次轻微回流 |
| 78 | **M3b `FlatButton` 走 Card 范式：`paintEvent` 实时读 `DS::`，零 QSS 颜色**：QPushButton 子类（is-a，24 处调用点的 QPushButton* 成员/connect/返回值零接线改动），hover≈10%/pressed≈18% 透明叠加 textPrimary（Card.h setAlpha 同款先例），字号经 `tagFont` 登记 repolish 跟随，padding = DS:: 4×16 与 `buttonPaddingQss` 同源并被 selfcheck 锁死漂移；主操作/空态主 CTA/DDialog 行内钮/示例链接钮保留并逐处注记（决策 72「主操作不降平钮」） | M3-4 点名的长效方案：QSS 注色有「重建拍快照」与切主题残留问题，paintEvent 读 token 天然跟随，容器与真机观感一致 | 真机 DTK 自带 flat hover 表达被组件接管（M3-4 既定方向）；hover/pressed offscreen 无鼠标不可截图验证（人工审计位）；容器无图标主题时 fromTheme 图标为空不显示（与原 QPushButton 行为一致，真机经 CE_PushButtonLabel 正常画图标） |
| 79 | **M1-1 `QStandardPaths`→`DStandardPaths`：DTK6 已提供，默认模式逐字节等价**：本版 DTK6（libdtk6core 6.7.47）sysroot 实证提供 `DStandardPaths`（DCORE 命名空间，writableLocation/locate/findExecutable 签名兼容，枚举仍收 `QStandardPaths::StandardLocation`）；四文件 8 处调用整体替换（EngineLocator×2/SysOpen×3/AutostartManager/ModelsDevCatalog×2）；A/B 探针实证默认 Auto 模式下 writableLocation(GenericDataLocation)/findExecutable("moongit")/locate(ApplicationsLocation) 与 QStandardPaths **逐字节一致**（models-dev 缓存路径与引擎发现口径不变） | 口径与 DDE 一致（plan §3 M1-1）；路径结果是硬禁区——models-dev 缓存、引擎发现都不许变 | 结果依赖 DTK 运行期行为：未来若有人调 `setMode(Snap/Test)` 会整体重定向（本应用不调，风险仅在未来引入时存在）；枚举保留 Qt 前缀（DTK 签名本就收该枚举，文件内两个命名空间前缀属 API 形态）；真机安装态 locate 未复验 |
| 80 | **M1-6 UOS AI 调用异步化 + 探测加锁 + 接口 dump 哨兵**：`launchChat` 改 `asyncCall` + `QDBusPendingCallWatcher`——**只捕获 watcher 不捕获 this**（引擎本体是 AgentDialog lambda 栈上临时对象，捕获 this 必悬垂，决策 65 同款教训），回包 deleteLater 自清理、finished 在发起线程（GUI）派发；`probe()` 用 mutable QMutex 锁「查缓存→探测→dump」整段（AgentCore 在 worker、AgentDialog 在 GUI，并发探测只跑一次）；首次探测把 `org.deepin.copilot` 可 Introspect 的接口名 dump 进日志，**只在服务运行中分支做**（仅可激活时不 introspect，避免探测把服务拉起的唤醒副作用） | 原同步 call 卡 GUI 线程（构造 QDBusInterface 还隐含一次同步 Introspect）；dump 是哨兵——未来 UOS AI 冒出程序化补全出口时日志第一时间可见（决策 20 边界的复核手段） | 返回值语义诚实收窄为「已派发」：调用失败不再让 AgentDialog 错误横幅同步变红（该文件在轨外未改），失败只落日志；真发 inputPrompt 会在用户桌面弹 UOS AI 窗口（未经同意的状态副作用），异步回包路径只做编译级 + watcher 模式核对，未真机实测 |
| 81 | **M1-9/M4b 平台探针「只报告不伪造」+ ci.sh 断言转正**：`--platform-probe` 落 main.cpp 无头分支（GUI 构造前），backend/托盘 geometry/paletteType/五档字号逐行 key=value、恒 exit 0；**只读不写**（不 applyThemeOverride、不 setPalette 兜底）——报告平台现状而非伪造状态；字号档位走 `DS::font()` 与页面同一消费出处；托盘 geometry 按计划只报告不断言；退出用 `::_exit(0)`——常规 exit() 的静态析构在本容器 DTK/DBus 全局单例收尾 5/8 挂死（实测挂在 main 返回之后）；ci.sh 四处增强：selfcheck 输出正式断言、校验工具缺失显式 SKIP、探针正式断言、D2 grep 门（>4 判失败，阈值依据决策 72 存量 4 处） | 探针是 CI 断言的数据源，伪造状态的探针比没有更糟；挂死的探针会卡死 CI（M1a 期踩过：未知 flag 落 GUI 主路径单实例常驻） | `::_exit` 跳过 Qt/DTK 全局析构（一次性只读探针无影响）；托盘 geometry 真机应为 1 的断言需真机回归（无托盘管理器环境恒 0）；ci.sh 的 deb 构建/系统 Qt6 矩阵两步仍未做 |
| 82 | **M4c 崩溃 handler：最小实现 + re-raise 按信号语义终止**：SIGSEGV/SIGABRT handler 用 `backtrace_symbols_fd` 直接写 stderr（**不 malloc**——崩溃点若正持有分配锁，signal 内再 malloc 死锁；fd 变体是本家族最接近 async-signal-safe 的形态）；**默认处置恢复提前到 handler 入口**再打栈——回溯途中再崩按默认语义直落，绝不递归；观测效果 =「打栈 → 按信号语义终止」（SIGSEGV exit=139、SIGABRT exit=134 探针实证）；注册在 main() 最顶，GUI + 五条无头路径全覆盖（CI 崩溃不再只有一行 Segmentation fault） | 排障第一步是现场回溯；「最小」不等于「信号不安全地随便写」——两处与字面口径的偏差（fd 变体/提前恢复）都是把要求做成可辩护的等价实现 | 未开 -rdynamic（CMake 许可改动仅限新增源行）：主程序帧只有地址需 addr2line 人工解析（实测可按打印偏移定位函数名）；栈溢出型 SIGSEGV 无 sigaltstack 不救；backtrace() 栈展开不保证 async-signal-safe（「尽量」口径） |
| 83 | **M2-6 图标集：母版单源派生，树下不留手写文件**：hicolor 8 档位图严格由 mark.png 满幅缩放（与 out/linux 同几何）；矢量层母版派生不出来，就把 6 枚 SVG 源**内嵌进 `assets/icon/make-icons.py` 作为唯一源**（`--check` 逐字节校验「产物 == 脚本内源」），既有 deepdolphin.svg 原样收编进脚本消除混源；symbolic 装 `share/icons/hicolor/symbolic`——实测 deepin 系 hicolor/index.theme 声明 `[symbolic/apps]` 档（纯猜 `share/icons/symbolic` 会装了不生效）；qrc 只登记 5 枚 `dd-*`（`IconLoader::symbol` 免安装兜底通道），deepdolphin-symbolic 不进 qrc（代码无消费路径，登记死资源是负资产） | 一处改、处处改、可机检；安装目的地按实测而非文档猜 | 本容器无 Qt6Svg：染色通道整段编译不进，容器内 dd-* 走 tint 色圆点占位（SVG 合法含 currentColor，真机由 Qt6Svg 染色渲染）；deepin 树 8 档与 out/ 已入库产物 48px 以上逐字节差（Pillow 版本不同，out/ 已还原未动）；「托盘/菜单不再手绘占位方块」的最终目视按 plan 属 M3 后真机项 |

## 分层纪律（后续阶段必须延续）

- `models/`、`logic/` **不 include 任何 QWidget 头**，全部可被 QtTest 单测；
- JSON 键名字符串只出现在各模型 `fromJson` 一处（`static constexpr` 键表）；
- 「未知/读不到 = -1」用 `int` 原样承载，语义判断（读不出来 ≠ 0）归 logic 层；
- `ok:false` 不算失败（hasErrorOrCode 看键不看值）；缺失键 = 契约过旧，入口闸门判。

## 运行期事实（实测记录）

- 容器内 GUI 经共享 X11（`:0`）可达宿主 DDE；无显示环境时 `QT_QPA_PLATFORM=offscreen` 可跑
  （三个环境变量见「构建与运行」——本阶段实测缺 `QT_PLUGIN_PATH` 会直接起不来）。
- 引擎 moongit/deepgit 未安装 → 首启即「引擎未找到」安装指引路径（本阶段 offscreen 复测：
  告警与文案正确，退出码 124 存活）；`DEEPGIT_BIN` 指向探活通过的桩时不再报错（AI 层阶段
  实测；agent 工具循环全链路亦以桩引擎验证，见决策 27）。
- 托盘在无系统托盘的环境（offscreen）只有 Qt 告警，不影响运行；真实 DDE 上走 SNI 协议。
- 会话总线（共享宿主总线）上 `com.deepin.copilot` 在线 → SystemAiEngine probe=Present：
  AI 入口的降级文案为「不支持程序化补全」而非「未检测到服务」；两者都如实区分（已按
  busctl 实测口径实现，真机 DDE 上行为与容器一致）。
