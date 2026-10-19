# deepDolphin — deepin/DTK6 客户端（deepin/）

moonGit（仓颉引擎，仓内别名 deepgit）项目群进度客户端的 Linux/deepin 复刻。
本目录是**新客户端专属目录**：不动 `linux/`（旧 Linux 仓颉客户端）、不动 `macos/`（1:1 功能基准）。

技术方案与逐文件设计：`/tmp/dd-deepin-port/PLAN.md`（下称 PLAN）；JSON 契约唯一来源：
`/tmp/dd-deepin-port/contract.md`（下称 CONTRACT）+ 引擎仓库 `/home/superShuai/code/moongit/`。

## Canvas 指定：Qt QPainter Canvas（scene 契约）

引擎契约（moonGit docs/graph-scene-schema.md）为本平台**指定**的图谱/架构图渲染实现是
**Qt/QPainter Canvas**（C++ 实现同一 Canvas2D 方法子集，以契约清单为移植验收清单），
消费 `graph arch/tree --format scene` 导出的 moongit-graph-scene v1 数据。
数据与渲染分离：本平台的正路是 scene 数据 + QPainter 在应用内直接绘制；
引擎的 HTML 单文件导出是引擎层交付物（只有引擎/被 agent 驱动时消费），不是本平台的渲染路径。（macOS 端对应实现 `ArchCanvasView.swift` 可作逐方法对照。）

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
| 纯函数判定层（`client-check.sh` 单独编译断言） | `models/`、`logic/` 零 QWidget 头，判定收敛为二进制内置 `--selfcheck`（220 例） | `src/models/`、`src/logic/`、`app/SelfCheck` |
| 设置窗口（自动化 + AI） | 设置三页签（DTabBar+QStackedWidget）：通用 / 自动化（分段改完立即生效）/ AI | `ui/dialogs/panes/*` |
| 快捷键（CommandMenu + ShortcutMap.swift） | QShortcut 全量真绑（含深更新——mac 曾「声明未绑」的缺陷不重犯） | `ui/PanelWindow.cpp:516`；`logic/ShortcutMap.h`（唯一声明处） |
| 定时更新 + AI 简报 | autoHours 周期 + 首轮 600s；简报经通知；silent 场景不偷弹结果面板 | `app/AppModel.cpp:202`；`ai/AiDigests`（scheduledDigest） |
| 一键全量（agent 通道，覆盖由代码保证） | 先刷新注册表再冻结名单 / 逐仓库显式传名 / 一个失败不中断 / 结果面板 aiNote 永远有值 | `AppModel::updateAll`（AppModel.h:111）；`ai/AgentCore` 批量通道 |
| 双轨更新 + AI 变体（`UpdateActionMenu`） | WorkBar 双轨按钮（唯一入口）+ 详情页更新菜单「浅更新 + AI 摘要 / 深更新 + AI 报告」 | `ui/DualTrackButtons`；`AppModel::runUpdateDigest`（AppModel.h:110）、`AiResultDialog` |
| 引擎未装 → 安装引导 | SetupGuidePage + 「重新检测引擎」 | `ui/pages/SetupGuidePage` |
| **文档完整性校验（引擎 `verify`）——mac 端暂无对位** | 详情页「文档完整性」卡：四态（通过 / 不一致 / **无法判定** / 缺失）+ 引擎 note 原样转述（缺失档带备份路径） | `models/VerifyEnvelope.h`；`logic/DocumentIntegrity.{h,cpp}`；`AppModel::loadVerify` |
| **引擎自检（引擎 `doctor`）——mac 端暂无对位** | 设置·通用页「环境自检」卡：按引擎口径的 `problems` 判档（**退出码 1 也是有效报告**；`result` 是自由文本不按 `=="OK"` 判健康；缺 `problems` 键记「未知」） | `logic/EngineDoctor.{h,cpp}`；`AppModel::runDoctor`；`panes/GeneralPane` |
| **进度报告导出（引擎 `report`）——mac 端暂无对位** | 详情页页头「导出报告」入口 + 「进度报告」卡：回执 + 落盘 .md 路径 + 「打开报告」（抽不到路径就不给坏按钮） | `logic/ArchReceipt`（`filePath` / `plain`）；`AppModel::exportReport`；`pages/ProjectDetailPage` |
| **引擎配置（引擎 `config`）——mac 端暂无对位** | 设置·通用页「引擎配置」卡：浅更新分支上限 / 文档备份份数 / 受管文档 / 扫描根；前两项可改（经引擎 `config set`） | `logic/EngineConfig.{h,cpp}`；`AppModel::loadEngineConfig` / `setEngineConfig`；`panes/GeneralPane` |
| **Canvas font 简写解析**（判定层 `logic/CanvasFont`） | 浏览器 CSS 口径（`px` 与 `pt` 都认）；平台侧按串静态缓存 QFont + 同串跳过 —— 修掉了「`11pt` 被当成字体族名吞掉、字号根本没设上」的移植语义缩水 | `logic/CanvasFont.{h,cpp}`；`platform/Canvas2D` |
| **持久化索引状态**（引擎 `index overview` / `index update`）——mac 端暂无对位 | 代码图谱页「增量更新」钮 + 索引状态行（代数 / 节点 / 边 / 文件 / 探针时间）—— 与页头概览**不是一回事**（概览读实时扫描，这里读索引） | `logic/IndexStatus.{h,cpp}`；`AppModel::loadIndexOverview` / `updateIndex`；`dialogs/CodeGraphDialog` |

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
./build/deepDolphin --selfcheck   # 模型层 fixtures 自检（无 GUI、无引擎依赖；当前 148 例）
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

本阶段实测记录：`--selfcheck` 148 通过 0 失败；`--version` 输出 `deepDolphin 0.1.0`；
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

> 跨端差距的活账在 [`docs/PARITY-LEDGER.md`](docs/PARITY-LEDGER.md)：
> mac 端能力 → deepin 的对位结论、引擎命令面 → 客户端的消费点、本端 DDE 化剩余项、
> 以及「deepin 领先 mac」的跨端一致性债。改一处能力就改那张账。

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
| C11 | 文档完整性承诺 | 客户端**唯一的业务文件写入 = 没有**：全 src 检索 `QSaveFile/WriteOnly` 仅 `AutostartManager.cpp:83` 一处（写自启 `.desktop`，非项目文档）；一切文档/进度写操作只经 `EngineCli` 子进程打给引擎（备份与托管区域由引擎保证，`moongit verify` 可校验）——**引擎能力已接入**：`AppModel::loadVerify` 调 `verify <名> --json`，`logic/DocumentIntegrity` 收口四态（通过 / 不一致 / **无法判定** / 缺失），详情页「文档完整性」卡展示（`models/VerifyEnvelope.h`、`logic/DocumentIntegrity.{h,cpp}`、`ui/pages/ProjectDetailPage.cpp`） |

## 取舍与已知边界

> 沿用 `macos/README.md` 的记录文化：拿不准时按最合理预案定，但**每个取舍写清「为什么这么定、已知代价」**。
> 以下是本仓库 deepin/ 从立项到交付实际发生的设计决定，按阶段全录。

### 基础框架阶段（决策 1–10）

1. **文件清单按阶段裁剪**：PLAN §3 的 `add_executable` 是全量终态清单；实现只列**已存在**
   的文件（models/app 逻辑/tray 壳/ui 壳），页面、AI、AppModel、Notifier、AutostartManager、
   SysOpen、DesignTokens 等随其实现阶段同步加入（CMakeLists 有显式提醒注释）。
   `tests/` 子目录随 PLAN 里程碑 2 加入；当前模型层冒烟判据由二进制内置 `--selfcheck`
   承担（148 例，含缺键拒绝/契约过旧判据/双形态 update/shallow-deep 分派等 CONTRACT 红线）。
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
| `ctest`：无目标可跑 | 设计如此 | CMakeLists.txt:134 注释：`enable_testing()+tests/` 缓建，模型层冒烟判据由 `--selfcheck`（148 例）承担 |
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

### 引擎能力接入阶段（2026-10-19，决策 84–86）

本批把**引擎侧已有、客户端侧从未消费**的能力接进 deepin：`moongit verify`（文档完整性校验）。
起因是「引擎新能力上客户端」这条线：引擎的 `verify` 有严谨的四态判据
（逐字节一致 / 明确不一致 / **无法判定** / 缺失），而两个客户端都没调它 ——
C11「文档完整性承诺」当时只靠一条反向 grep（客户端没有业务文件写入）撑着，
**承诺成立但用户看不见**。接上之后，「引擎说这份文档对不上」才有一条出口。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 84 | **引擎 `verify` 接入 deepin，判定收口在 `logic/DocumentIntegrity`（纯函数层，零 QWidget 头）**：`AppModel::loadVerify` 调 `verify <名> --json`（**只读**，不碰用户数据）；`models/VerifyEnvelope.h` 按契约收六键（`checked/failures/undetermined/missing/verified/documents`，`note` 可选）——**缺任一键 → 解不出（契约可能过旧），不许回落成 0**；`DocumentIntegrity::stateOf` 定优先级 missing > failed > undetermined > none > verified；详情页「文档完整性」卡按档配色（通过=绿 / 不一致=红 / **无法判定=橙**（不是灰！没答案 ≠ 没事）/ 缺失=橙（备份仍在，可恢复）/ 无从校验=灰） | 引擎的四态是**引擎的判据**，客户端只负责「显示成哪一句话」，不重算；「无法判定」必须独立成档 —— 引擎在备份被删/权限被改/结构异常时明确拒绝替一次它没做的校验背书，客户端也不许把它显示成「通过」（仓内「缺字段不回落成 0」纪律的同一条纪律）；判定进 `logic/` 保住「纯函数判定层」分层（`models/`、`logic/` 零 QWidget 头） | **能力先行、mac 端暂未对位** —— 章程 C11「能力必须一致」要求另两端补齐，mac/linux 同步是后续批次（本批按「先搞定 dde」的次序落地，此债已记）；缺 `note` 的载荷在缺失档仍能显示计数，但少了引擎给的备份路径；`verify` 每进一次详情页发一次子进程（60s 超时），项目多时是可见的进程开销（当前只对选中项目发，不扫全群） |
| 85 | **`ci.sh` 新增第 7 道门：verify 接线源扫描（判定不许藏回视图，撤入口 ≠ 撤能力）**：剥注释后逐条钉住 6 个接线点（引擎命令调用 / `loadVerify` 声明 / `verifyChanged` 消费 / 进详情发起校验 / 详情页挂卡 / selfcheck 覆盖四态），任一缺失即失败退出 1 | 判定层判据全绿 ≠ 用户真能看见 —— 接线断了，判据照样全绿（仓内「判定藏回视图 = 运行时抓不到 = 缺陷漏网」）；源扫描是唯一能在无图形环境下钉住接线的手段 | 源扫描按**文件+正则**钉，挪动接线点位置会误报（改接线时须同步改门）；门只查「接线在不在」，不查「接线对不对」（对不对由 selfcheck 四态判据与 contract-check 真引擎断言负责）；门自身一度误报（`set -o pipefail` + `grep -q` 提前退出 → 剥注释的 perl 收 SIGPIPE → 管道判失败），已改为 grep 读完整流 —— **门自己坏了比门放水更糟** |
| 86 | **截图门强制离屏（`QT_QPA_PLATFORM=offscreen` 写死在第 2 步，不继承环境）**：原写法是全局 `${QT_QPA_PLATFORM:-offscreen}`——宿主若已设 `QT_QPA_PLATFORM=dxcb;xcb`（本机即如此）则沿用，快照会带 DTK 原生窗口装饰与 chameleon 样式，**同一份代码拍出另一张脸**，视觉 diff 被环境牵着走（实测同一提交在 dxcb 下 42501 字节、离屏下 36661 字节，差 5700+）；现只给第 2 步（截图矩阵）写死 offscreen，第 4 步平台探针**仍要**真实 backend 故不强制 | 离屏才是「同机位」可复现的前提；基线是离屏拍的，门就该按基线的机位拍 —— 门自己随环境漂移，等于没有基线 | 平台探针仍继承环境（有意为之：它要报真实 backend）；真机视觉回归仍需在 DDE 桌面真跑（离屏不代表真机观感）；基线里「上次刷新 HH:MM」时间戳本身每次都不同，视觉 diff 须忽略状态条那一行像素（实测差异恒定落在 y 699–708 的 32×9 区域） |

**本批验证**（全部实跑）：`--selfcheck` **77 通过 0 失败**（66 → 77，+11 例：契约六键/缺键拒绝/四态优先级/
「无法判定 ≠ 通过」/文案纪律/引擎 note 原样转述）；`contract-check.sh` **15/15**（真引擎沙箱，10 → 15，
+5 条 verify 契约断言含「删文档 → missing=1 且 verified=false 且 note 带备份路径」）；
`ci.sh` **7/7 门全绿**；**三处负控真红**：① `stateOf` 把 undetermined 当 verified → 「无法判定是独立一档」红；
② `VerifyEnvelope::fromJson` 缺键回落成 0 → 「缺键 → 解不出」红；③ 摘掉 `loadVerify` 调用 → 接线门红（退出码 1）。
**视觉零变化**（离屏同机位像素级比对：HEAD 与本批 6 张快照的差异恒定落在状态条 y 699–708 的
32×9 区域 —— 即「上次刷新 HH:MM」时间戳，其余逐像素相同，故基线未随本批改动）。

### 图谱 Canvas 阶段（2026-10-19，决策 87–89）

引擎 10-13 起了整族「代码图谱 / 交互架构图 / 符号热力图 / 补丁体检」能力，
mac 端 30 个提交（`d467a4f..d62e429`，7919 行）已具现化；章程同时新增
**§3.5 平台 Canvas 分派**：运行时渲染一律走平台 Canvas，**DDE = Qt QPainter Canvas**（指定实现）。
本批落 deepin 被指派的那一半：**契约层 + 渲染内核**（页面接线是下一批）。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 87 | **场景契约层 + Qt QPainter Canvas2D 内核落地（章程 §3.5 指派的 DDE 实现）**：`models/GraphScene.h` 收 `moongit-graph-scene v1`（`v` 必须为 1，**版本不认识就明说不兼容**，不静默兼容；`arch` 恒排第一；三个恒发字段 `edgesDropped`/`meta.warnings`/`chips[].count` 都读得出）；`logic/GraphToken` 落 token 四形态 + **`node:<id>` 二跳**，未知 token **洋红兜底**（引擎违约的显式信号，不静默当黑）；`logic/SceneRender` 把场景翻成一帧 Canvas2D 调用（纯函数层）；`platform/Canvas2D` 用 QPainter 实现契约清单**全部 26 个**标准方法；`logic/CanvasSink` 是渲染契约的**接缝端口**（判定层挂记录式接收端逐条断言调用序列，平台层只管翻译成 QPainter） | 章程把「平台 Canvas 必须实现同一子集，方法清单就是移植验收清单」写成了硬门，本批按门施工而不是按观感施工；判定层与平台层之间留端口，换栈（仓颉 Canvas / CoreGraphics）时判定层与契约层零改动 | **文字基线与 mac 差一档**：本端按 Canvas2D 语义（`fillText` 的 y 是**基线**，与引擎 Web 驱动 `y+22` 一致），mac 的 SwiftUI 驱动用的是**顶对齐** —— 引擎的 scene 数据是按基线设计的，故 deepin 跟契约、mac 是偏差方（差约一个字高，待真机目检）；`shadowBlur`/`shadowColor` QPainter **无原生阴影**，本批用「离屏绘制 + alpha 盒式模糊三遍≈高斯 + 着色合成」模拟（显式等价实现，不是糊弄）；Qt6 移除了 `QPainterPath::arcTo(点,点,半径)` 与 `strokePath`，圆角语义按 Canvas 规范**自己实现**（切线圆弧 + 半径夹取），不许拿直线凑；本批只到内核，**没有页面**（架构图页/下钻/命中测试是下一批） |
| 88 | **判据补强：圆角用「差分像素」判，不用「数调用次数」判**：原先只断言 `arcTo` 被调了 4 次 —— 负控把 arcTo 换成直线时判据**照样全绿**（灵敏度不足，等于没判）；补一条差分判据：同尺寸方块「圆角(r=8) vs 直角」的四角实心像素数差（实测直角 64 / 圆角 12），圆角实现才过 | 「判据全绿」不构成证据 —— 负控没红说明判据抓不住，不是实现没问题 | 像素判据对渲染后端敏感（当前 QPainter 离屏稳定）；未来换 Canvas 实现需复测阈值 |
| 89 | **`ci.sh` 新增第 8 道门：图谱 Canvas 契约门**（Canvas2D 逐个核契约清单 26 个方法是否声明为 override；`logic/` 与 `models/` 零 QWidget 头；四个新文件必须已登记进 CMake —— 漏登记 = 代码在仓里但没编进去）；`contract-check.sh` 加第 10 组真引擎断言（8 条：五键齐全 / `v==1` / themes 两套 / `edgesDropped` 恒发 / `warnings` 恒发 / `chips[].count` 是数字 / shape 类型只五种 / hits 带 id·x·y·w） | 移植验收清单是契约给的，不该靠人肉记得；「漏登记进构建」是源扫描能抓而编译抓不到的缺陷 | 门按**方法名**匹配声明行（返回类型随方法而变，`void` 写死会漏 `createLinearGradient`；方法名前可能是紧贴的指针星号 `QLinearGradient *foo`）—— 挪动声明格式会误报 |

**本批验证**（全部实跑）：`--selfcheck` **103 通过 0 失败**（77 → 103，+26 例：scene 契约四则 /
恒发字段 / token 四形态 + 二跳 + 洋红 / 渲染指令序列 / 阴影与圆角差分像素）；
`contract-check.sh` **23/23**（真引擎沙箱，15 → 23，+8 条 scene 契约断言）；
`ci.sh` **8/8 门全绿**；**三处负控真红**：① 未知 token 回落成黑 → 洋红判据红；
② 阴影模拟短路 → 阴影像素判据红；③ `arcTo` 换成直线 → **补强后**的圆角差分判据红。
**视觉零变化**（本批只加内核不加页面，快照基线未动）。

### 批 D2：架构图页（引擎 `graph` 能力的 GUI 具现化）

本批把批 D1 的内核接成**用户真能用的页面**：详情页入口 → 架构图窗 → 画布，
并补上 mac 端「生成 / 导出」两个动作。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 90 | **架构图页用独立 `DDialog` 承载**（不是详情页里的一个 tab）：`ui/dialogs/ArchDialog` 走 `AiSettingsDialog` 同款范式；页头 = 项目名 + 刷新/生成/导出，下方 = 画布，最底 = 披露行（违规/环边、被丢弃的边、分层 chips）；**项目名在详情页入口锁定**，窗内没有切仓库的选择器 | mac 用 sheet 挂详情页，DDE 无 sheet 对位物；且架构图要的是**大画布**（真实场景 69 个 shape，塞进详情页宽度会缩成看不清的缩略图）；「仓库选择在面板入口定」是 mac 既有纪律（`ArchPage` 无 `GraphProjectPicker`），照搬 | 深链能力弱于 sheet（无「返回」上下文）；同一项目重复点入口是**叫醒已有窗**而不是新开一个（两个窗抢同一份场景状态会让人搞不清谁在显示什么） |
| 91 | **视口与命中判定收进 `logic/ArchViewport`（纯函数层），场景按项目分开存**：`AppModel` 的场景状态改 `QMap<项目名, 状态/场景>`（原先是单一槽位，两个项目的窗会串台）；视口 `Viewport` 类型**只此一份**（`SceneRender` 原先自带的同构 struct 已删，改用 `ArchViewport::Viewport` —— 渲染与命中必须共用同一个换算式，两处各写一份迟早各自漂移）；场景几百 KB，故 `sceneFor()` 返回**指针**不按值复制 | 视口换算（屏幕↔世界）与命中是**最容易悄悄错**的两件事：缩放没跟上下标就「点不中」，命中区顺序错了就「选错节点」—— 都不该等到看图才发现，故抽成纯函数直接判；「单一真相源」在本仓是硬纪律，同一个概念不许两份定义 | 场景缓存在模型层（多项目各开一次窗会各留一份，几百 KB/份）；引擎侧重新生成后需重载才反映（本批「生成」动作已自动触发重载） |
| 92 | **引擎输出分两套契约（`Json` / `Text`），回执型命令走 `Text`**：`EngineCli` 新增 `OutputMode` 与 `callText`；`arch gen` / `render arch` 的 stdout 是**人话回执**（如「架构已生成：首版（第 0 版）」「已重绘：<路径> · 第 1 版」），不是 JSON —— 拿 `callJson` 去收，**exit==0 也会被判成「引擎输出不是合法 JSON」**，成功被报成失败；判定逻辑收在唯一出处 `EngineCli::stdoutSatisfies`（可无头判） | 引擎的输出本来就分两类，判据不同就不能共用一条；「空 stdout = 契约破坏」在两类里都成立（回执型命令空 stdout 同样是契约破坏） | 引擎将来若给回执型命令加 `--json`，客户端要按新契约改（现契约由 `contract-check.sh` 第 11 组钉住） |
| 93 | **回执里的导出路径按「词边界 + 全角分隔符」扫，不按空格切词**（`logic/ArchReceipt::htmlPath`）：引擎真实回执是「已重绘：`<绝对路径>` · 第 N 版」—— 路径与文案之间是**全角冒号**；按空格切词会切出「已重绘：/path/arch.html」这种粘连块，mac 的 `extractHTMLPath`（`hasPrefix("/")`）因此**抽不到路径、导出后「打开」入口始终不出现**；本端改为扫「以 / 开头、以 .html 结尾、中间不含空白与全角分隔符」的一段，并要求 `/` 前面是词边界（否则「render/arch.html」这种相对路径会被从中间的 `/` 截成「/arch.html」，给用户一个打不开的按钮） | 深色是「深于 mac」而非「同 mac」：功能对齐优先于逐字对齐（章程「能力必须一致」），且**相对路径打不开**，认了等于给坏按钮 | mac 端同一处仍抽不到路径 —— 属**跨端一致性债**，已记进 `docs/PARITY-LEDGER.md` D 节，本批未改 mac（当前次序是先搞定 dde） |
| 94 | **恒发字段加「在不在」标志（`edgesDroppedPresent` / `warningsPresent` / `chipsPresent` / `boundsPresent`），缺键不再静默回落成 0**：契约 §恒发字段明写「缺键不得当作『没有』」，但 `edgesDropped=0`、`violations=0`、`chips=[]` 与「引擎没发这个键」**在值上不可区分**；现补四个 present 标志 + `viewsMissingBounds` 计数，披露行据此说「被丢弃的边数未知（契约可能过旧）」「告警未知」「分层未知」「N 个视图缺包围盒（无法自适应）」 | 缺字段不回落成 0 是仓内硬纪律；批 D1 只把字段读进来，**没区分「确实 0」与「没发」** —— 本批把字段真正显示到用户面前，这个洞才暴露出来（不显示就没人看得见） | 引擎当前**无条件**发这四样（已用真引擎实测钉进 `contract-check.sh`），所以 present 标志在实践中恒为真；标志是给契约演进留的 honest 出口 |
| 95 | **顺手修批 D1 的两处真缺陷**：① `views` 排序的比较器不满足**严格弱序**（`comp(arch, arch)` 返回 true 违反自反性 → `std::sort` 是未定义行为），改为「先判谁是不是 arch，两者都是则按 id 字典序」；② `contract-check.sh` 的夹具项目**没有源码** → arch 视图是空的（0 shapes / 0 hits / 包围盒退化）→ scene 那 8 条断言整组**空转**（看着全绿其实什么都没验到）→ 夹件补一份 `src/main.c`，并补「arch 非空」「有 shape 的 view 包围盒非退化」两条断言 | 「判据全绿」不构成证据：判据跑在空数据上，等于没判；比较器违反严格弱序是 UB，哪天换个排序实现就会静默排错位置 | 夹具加源码后 `update`/`verify`/`dashboard` 那几组断言的输入也变了（多一个受管源文件），已复跑全绿 |

**本批验证**（全部实跑）：`--selfcheck` **125 通过 0 失败**（103 → 125，+22 例：视口 fit 三则 +
换算往返 + 命中三则 + 回执四则 + 输出契约四则 + 恒发字段 present 标志四则）；
`contract-check.sh` **30/30**（真引擎沙箱，23 → 30，+7 条：架构图回执四条 + 包围盒两条 +
「arch 非空」一条；夹具补源码后整组断言不再空转）；
`ci.sh` **9/9 门全绿**（新增第 9 门「架构图接线门」，19 项接线点）；
**七处负控真红**：① 摘掉详情页入口接线 → 第 9 门红（exit 1）；
② `genArch`/`exportArch` 改走 `callJson` → 第 9 门红；
③ 命中测试恒空 → selfcheck 红（2 例）；
④ 视口缩放夹取去掉 → selfcheck 红；
⑤ 回执改取首行 → selfcheck 红；
⑥ 输出契约恒真 → selfcheck 红（3 例）；
⑦ 摘掉「回执按项目路由」→ 第 9 门红。
**视觉零变化**（架构图是独立窗口，不进四页快照矩阵，快照基线未动）。
**本批还修了批 D1 的三处真缺陷**（决策 94/95）：排序比较器 UB、恒发字段缺键静默回落成 0、
契约夹具无源码导致整组断言空转。

### 批 E1：agent 工具面补齐（引擎 28 个工具全接）

批 D2 之后，引擎的图/架构/置信度能力 GUI 侧已通；**agent 侧还只会 10 个老工具** ——
模型在对话里想查代码图谱、想算补丁置信度，客户端只能回一句「未知工具：X」。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 96 | **工具 → 引擎 argv 的映射抽成纯函数表**（`logic/AgentToolPlan`），执行点只做 I/O：28 个工具的命令形态、flag 解析、白名单、超时预算全在表里；`knownToolNames()` 是「客户端能执行哪些工具」的**单一真相源** | 原来这层是 `AgentCore::executeTool` 的 if-else 链，每加一个工具多一段分支，长了就出三种毛病：① argv 拼错只有真跑到那个工具才看得出；② 「客户端支持哪些工具」说不清 → 契约无从比对；③ 参数校验散在分支里各自一套口径。抽成纯函数后可**无头判**（selfcheck 直接判 argv 形状、flag 解析、白名单） | 纯函数层不碰文件系统 —— 引擎 CLI 吃路径的那种（`graph patchconf --merge`）由表声明「哪个参数落盘 + argv 哪一格放路径」，落盘在 app 层做（`{{tmp:<参数>}}` 占位） |
| 97 | **开关型参数收字符串形态**（`"true"/"1"/"yes"/"on"` 与布尔 true 同等对待），数值型参数**只给真数**（非数不递给引擎，缺省交给引擎） | 引擎把 `params` 声明成**全 string 型必填**，模型多半发字符串；只认布尔会让 `--force`/`--violations` 永远不生效（形同虚设）。mac 侧 `as? Bool` 在这条路径上恒假 —— 属跨端债 | 数值参数若模型给了 `"3.0"`，按正则判为合法数字（与引擎的解析口径未必完全一致，但引擎会自己校验） |
| 98 | **超时预算常量下沉到 `logic/EngineTimeouts.h`**（数字一个没改，只是搬家），`app/EngineCli.h` include 它；**`contract-check.sh` 接进 `ci.sh` 成为第 10 门**（之前它是**游离脚本**，CI 从来没跑过） | 工具表与 app 层要用同一批超时数字 —— 同一件事两处字面量必然漂移（改了引擎调用忘了改工具表，症状是「大仓整图构建在 agent 里被砍成 120 秒」这类难查的问题）。契约脚本游离在 CI 之外，等于契约漂移不会被拦 | `logic/` 现在多了一个纯常量头（不违反「零 QWidget 头」纪律） |

**本批验证**（全部实跑）：`--selfcheck` **135 通过 0 失败**（125 → 135，+10 例：工具清单 28 个 /
每个都有 argv 与预算 / 未知工具明说 / argv 形状两则 / 开关参数收字符串 / 数值参数只给真数 /
op 越界被拒 / 临时文件声明 / format 决定 flag）；
`contract-check.sh` **32/32**（真引擎沙箱，30 → 32，+2 条：第 12 组「前提抓到两边清单」+
「客户端能执行的工具集 == 引擎声明的工具集」）；
`ci.sh` **10/10 门全绿**（第 9 门扩到 22 项接线点；新增第 10 门「引擎契约门」—— 把游离的
contract-check 收进 CI，引擎缺席时显式 SKIP 且**不算通过**）；
**六处负控真红**：① 工具清单少一个 → 契约第 12 组红（差集原样打出：`引擎有、客户端不会执行：
codegraph_patch_merge`）+ ci.sh 第 10 门红；② 摘掉 AgentCore 的工具表接线 → 第 9 门红
（且 agent 自测同时变红）；③ flag 只认布尔 → selfcheck 红；④ op 白名单去掉 → selfcheck 红；
⑤ 数值参数不校验 → selfcheck 红；⑥ 临时文件声明去掉 → selfcheck 红。
**视觉零变化**（agent 面板无 UI 改动，快照基线未动）。

### 批 E2：代码图谱页（引擎 `graph` 三源接成符号树 + 置信度 + 调用关系）

批 D2 把架构图画出来，批 E1 把 agent 的图能力接上；本批补上 mac 的**代码图谱页** ——
符号级树、置信度疑点、调用关系。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 99 | **三份引擎输出合成一棵树，规则抽成纯函数**（`logic/CodeGraphBuild`）：`graph tree`（文件骨架 + 符号清单 + 引用边）/ `graph confidence`（总分 + 维度 + 疑点）/ `graph functions`（函数级归属 + 源码片段 + 符号级调用边）；树用**扁平 arena + 索引**表达（父子关系用索引，不用裸指针 —— 嵌套 `QVector` 扩容会让指针失效） | 合成规则里藏着三处最容易悄悄错的地方：① `tree` 的 symbols **不带 id**，客户端要按 `f:<路径>:<行号>:<名字>` 构造，而 `functions` 的 id **带** —— 两者要对上靠的就是这个构造式；② 疑点归属：函数级那份已按符号体归属好，置信度侧那份是全仓疑点，要按「文件+行号+kind」去重，剩下才是孤儿挂到文件；③ 汇总卷积（子树疑点数 / 最高权重）自底向上算，算错会让徽标与详情页对不上 | 树规模大时合成是一次性 O(n)（引擎已经截断过，`truncated`/`skipped`/`oversizeSkipped` 都带披露） |
| 100 | **符号 id 构造式用「端到端」契约钉住**：新增无头 flag `deepDolphin --code-graph-symbol-id <路径> <行号> <名字>`，契约检查拿**引擎给的真实符号**去问客户端「同样三个输入你造什么 id」，逐条比对 | 原先只在契约里断言「引擎侧的 id 形如 f:路径:行号:名字」—— 那是**引擎自己跟自己比**，客户端改了构造式它照样全绿。症状极隐蔽：树能画、关系页签永远空 | 契约检查多一次子进程调用（每次 3 个符号，可忽略） |
| 101 | **代码图谱页用独立 `DDialog` 承载，两栏**（顶栏 + 左栏列表树 + 右栏详情三页签）：顶栏 = 项目名 + 刷新/生成/导出 + 置信度总分；左栏 = 搜索框 + 列表树（可见性以判定层 `visibleRows` 为准）；右栏 = 详情头 + 页签（源码 / 置信度 / 关系）+ 详情体；项目名在详情页入口锁定 | mac 的代码图谱页是**两栏**（`HSplitView`：treePane + detailPane），热力图是**左栏的另一种模式**（不是第三栏）—— 与其按台账旧措辞做三栏，不如按 mac 的实际形状做；画布类页面独立窗是本平台既有承载（架构图窗同款） | **热力图模式未做**（mac 的 `CodeGraphHeatmap.swift` 核心算法 ~380 行）—— 留批 E3，本批左栏只交列表树；`drill`/`jump` 下钻未接（mac 同款未接） |

**本批验证**（全部实跑）：`--selfcheck` **148 通过 0 失败**（135 → 148，+13 例：骨架合成 / 符号 id
构造式 / 疑点挂符号 / 去重不重复数 / 孤儿挂文件 / 汇总卷积 / 排序 / 边与片段 / 截断披露 /
总分与降级说明 / 缺源点名 / 可见行 / 搜索过滤）；
`contract-check.sh` **40/40**（真引擎沙箱，32 → 40，+8 条：代码图谱三源契约 + 符号 id 端到端）；
`ci.sh` **10/10 门全绿**（第 9 门扩到 **36 项**接线点）；
**五处负控真红**：① 符号 id 构造式改成不同形 → 契约端到端红（exit 1）+ selfcheck 4 例红；
② 疑点去重去掉 → selfcheck 2 例红；③ 符号排序改成按名字 → selfcheck 红；
④ 搜索过滤去掉 → selfcheck 红；⑤ 摘掉代码图谱入口接线 → 接线门红（exit 1）。
**判据灵敏度补强（决策 99）**：排序断言原先**抓不住** —— 夹具里「按声明行」与「按名字」
恰好同序，实现改成按名字排时判据照样全绿。已把夹具改成两种排序**分叉**
（worker@3 排前、helper@9 排后），补强后负控 ③ 才真红。
**视觉零变化**（代码图谱是独立窗口，不进四页快照矩阵，快照基线未动）。

### 批 E3：符号索引热力图（代码图谱左栏的另一种模式）

mac 的 `CodeGraphHeatmap.swift` 有 693 行，其中**核心算法约 380 行**（卡片铺排 + 重心扫描 +
通道车道走线），其余是 SwiftUI 外壳。本批把那 380 行移植成纯函数层（`logic/HeatLayout`），
外壳换成 Qt QPainter 画布（走批 D1 的 `Canvas2D` 内核）。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 102 | **热力图核心算法抽成纯函数**（`logic/HeatLayout`：`scopeCards` 作用域切分 / `layout` 铺排 / `routes` 走线 / `catmull` 平滑），控件（`ui/HeatmapWidget`）只负责画与收点击 | 铺排与走线是**最容易悄悄错**的一段：卡片重叠、走线不贴卡、颜色算错，看图才发现就晚了；抽成纯函数后可无头判（selfcheck 直接判几何与配色） | 纯函数层不碰 Qt 图形栈 —— 想在别的平台复用得再写一份外壳（与 D2 的 `SceneRender` 同款取舍） |
| 103 | **热力图是左栏的另一种模式**（`SegmentedButton` 切「列表 / 热力图」+ `QStackedWidget` 装两页），**不是第三栏** | mac 的代码图谱页是 `HSplitView` 两栏，热力图挂在左栏的 treePane 里换位；照台账旧措辞做三栏会与 mac 形状不一致 | 左栏宽度有限，热力图在窄栏里看不如全屏大 —— 但保持与 mac 同形优先（章程「能力必须一致」） |
| 104 | **跨作用域边界卡按「文件」聚合**（不是按符号），封顶 **9 张**，溢出并成「+N」 | mac 的注释写「按文件聚合」但**键其实是符号 id**（卡片名会带行号）；本端按文件聚合，名字更干净。封顶是防「一个大文件调遍全仓 → 铺出几百张卡」 | 溢出部分只剩一个计数（点不开具体是哪些）—— 与 mac 同款取舍 |
| 105 | **热色三档与身份色是「契约色」，不进 DS 令牌**；写成 `QColor(r,g,b)` 三元组而不是 `#RRGGBB` 字面量 | 热色要与 HTML 交付物逐字同色（两边是同一套契约色），走 DS 令牌就会被主题改写、两边对不上；而 D2 grep 门盯的正是 `#RRGGBB` 字面量 —— 契约色不是设计令牌，不该走那条路 | 契约色硬编码在 `HeatLayout` 里（不进 `DesignTokens`）—— 这是**有意的例外**，不是纪律破口 |
| 106 | **身份色相按黄金角 137.508° 散布，排序键是「节点 id 字典序」**（不是 arena 下标）；稳定哈希用 FNV-1a（不用 `qHash` —— 它不保证跨平台稳定） | 同一份数据在两台机器上必须画出**同一张脸**；按 arena 下标分配的话，节点顺序一变颜色全变，「同一份代码两种颜色」，排查时根本分不清是数据变了还是画法变了 | 颜色与节点**位置**无关（同一文件在不同树下可能撞色）—— 身份色是「是谁」不是「在哪」 |
| 107 | **符号 id 两源对齐在契约层钉死**（`contract-check.sh` 第 14 组：`graph tree` 与 `graph functions` 的 (文件,名字,行号) 集合必须逐条相等，且夹具必须造得出**跨文件**函数边）；客户端侧再按 (文件,行号,名字) 兜底解析 | 客户端用 tree 侧造符号 id、用 functions 侧的引擎 id 认调用边；两边对不上（哪怕只差一个行号）→「调用方在不在作用域内」就判错，跨作用域引用会**静默消失**：热力图少画几张卡，用户看不出是契约漂移还是数据就这样 | 兜底解析让「引擎 id 认不出」退化成「按三元组认」；真认不出时那条边被丢掉（不猜） |
| 108 | **布局与走线按「层级 + 画布尺寸 + 边数」缓存**（30fps 重绘只重画时变项，窗口不可见停表）；**内容高度按卡片包围盒实测算**，据此给滚动条 | 动画每帧重跑布局会让大仓卡住；内容高度若靠布局层估算，估不准就会出现「卡片铺到画布外、又没有滚动条」—— 仓库一大就复现，后半张图根本看不到 | 卡片多时仍要重算布局（换层级/换尺寸/换边数时） |

**本批验证**（全部实跑）：`--selfcheck` **166 通过 0 失败**（148 → 166，+18 例：分数公式 / 热色三档 /
身份色稳定与黄金角 / 色相与顺序无关 / 文件层作用域 / 下钻层作用域 / 边界卡封顶 / 作用域内边 /
文件层边 / 卡片不重叠 / 网格工整 / 序号连续 / 铺排与输入顺序无关 / 分带有序 / 重心扫描生效 /
走线不丢 / 曲线过端点）；
`contract-check.sh` **42/42**（真引擎沙箱，40 → 42，+2 条：符号对齐 + 跨文件调用边前提）；
`ci.sh` **10/10 门全绿**（第 9 门扩到 **49 项**接线点，+13 项热力图链路）。
**十四处负控真红**：① 摘掉重心扫描 → selfcheck 红；② 身份色相改成按 arena 下标分配 →
selfcheck 红；③ 不生成跨作用域边界卡 → selfcheck 红；④ 放开边界卡上限 → selfcheck 红；
⑤ 铺排让卡片同列（重叠）→ selfcheck 红；⑥ 走线恒空 → selfcheck 红；⑦ 热色档位挪档 → selfcheck 红；
⑧ 分数公式不摊薄 → selfcheck 红；⑨ 摘掉热力图的两条信号接线 → 接线门红（exit 1）；
⑩⑪ 契约对齐断言对「行号漂移（两侧各一次）」「多出符号」「tree 少符」「fns 清空」四种变异
全部变红（不蒙对）；⑫⑬ 跨文件边断言对「改成同文件」「清空边」两种变异变红。
**顺手修的两处既有缺陷**：
① `contract-check.sh` 的「符号 id 端到端」报「N 个真实符号」时，取的是 `COUNT` **行数**（恒为 1）
而不是符号数 —— 报告失真，已改成取 `COUNT` 行的**值**（现在报真数）；
② D2 grep 门抓到了 `HeatLayout` 里一句带 `#59f0b8` 的注释 —— 门是对的（契约色不该以 hex 落纸面），
已改成不含 hex 的写法（D2 命中回到 4/4，未超存量上限）。
**视觉零变化**（代码图谱是独立窗口，不进四页快照矩阵，快照基线未动）。

### 批 F：补丁体检（diff → 置信度 → 人工标注 → 合并终稿）

mac 的 `GraphPages.swift` 补丁段是一张 `PatchCheckPage`：**三层体检**
（Layer 1 算法 → Layer 2 人工裁决 → Layer 3 合并终稿）。
引擎侧对应 `graph patchconf` 的三个形态：`--patch`（算法层）、`--skill`（取 Layer 2
任务书）、`--merge`（合并终稿）—— 本批三个都接上了。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 109 | **补丁体检走「详情页入口 → 独立窗」**，不占面板第 N 段 | mac 把它挂在**面板级页**（`PanelView` 的 `.patchCheck`），但 deepin 面板是全局语境（仪表盘/看板/里程碑），而补丁体检天然是**单项目**语境（对某个仓库工作区未提交改动的体检）—— 按 deepin 既有纪律（仓库选择是面板入口的事）从详情页进、项目名在入口锁定，与架构图窗/代码图谱窗同款 | 与 mac 的**承载形态**不同（页 vs 窗），能力一致 —— 章程「交互 UI 各平台自由，能力必须一致」 |
| 110 | **`signals` 里的 null 单列成「算不出」，不回落成 0 分**；每个信号带 `hasValue` | 引擎把 null 明确定义为「分母为 0，词法层无法可靠计算」（S7 契约一致率要接口实现对照），并要求如实披露。回落成 0 的话，用户会把「算不出来」读成「得了 0 分」—— 两者含义完全相反 | 界面上「—（算不出）」比数字显眼，是故意的 |
| 111 | **契约形状不对时直接报错，不当 0 分放行**（缺 schema / schema 版本不认识 / 缺 signals，三种分别说清） | 「缺键 = 契约过旧」是本仓一贯纪律（README「分层纪律」节）。形状漂了就报错，比显示一个假的 0 分有用得多 | 引擎升契约版本时客户端会**显式红**（而不是悄悄显示旧口径）—— 这是要的行为，但升级时要同步改这里 |
| 112 | **低置信度实体：阈值 <0.75，**升序**（最不可信的排最前），且置信度未知（缺键）不参与** | mac 同款阈值与升序。低置信度清单的价值全在「第一个就是最该看的那个」；排反了就等于没有。置信度未知 ≠ 不可信，不能混进低置信度 | 阈值写死在判定层（mac 同款 0.75），没做成可调项 |
| 113 | **裁决 id 原样回填**；`uncertain.id` 与 `entity.id` **不是同一套 id 空间**（前者 `文件@行号:名字`，后者 `名字@文件:行号`），混用会让引擎认不出裁决、裁决被静默丢掉 | 引擎按 id 把裁决对回「拿不准的项」。id 改一个字，终稿里那条仍是「未裁决」，而界面看不出任何异常 | 无 |
| 114 | **终稿的复核数读 `diagnostics.reviewed_by_agent`**（**不是**顶层 `reviewed` 键 —— 引擎载荷里没有这个键） | 引擎实测：终稿顶层是 `schema/overall/signals/entities/alerts/sources/diagnostics`，复核数在 `diagnostics` 里。mac 读的是顶层 `reviewed` → 那句「已复核 N 条」永远不显示（本批已记进台账 D 节，未改 mac） | 无 |
| 115 | **工作区 diff 走本机 `git diff HEAD`**，不走引擎 | 引擎的 git 白名单里**没有** diff（它刻意不把任意 git 透传进白名单）。本机只读一次 `git diff HEAD`，不写不推 | diff 很大时 `git diff` 本身会慢（设了 30s 超时；超时如实报错，不给半截结果） |
| 116 | **低置信度实体默认收起**，点开才从 diff 里抽实码（惰性展开） | 「低置信度」不能只给一句元数据 —— 用户得看到代码本身才能判断该不该信。但全量展开会让长补丁把界面撑爆 | 抽不到实码时明说「（补丁里读不到这段实码）」，不给空壳 |
| 117 | 引擎的 `--patch` / `--merge` 都吃**文件路径**，落盘在 app 层（`QTemporaryDir`） | 引擎 CLI 吃路径不吃正文（正文走 stdin 会和引擎自己的重定向打架）。落盘位置在 app 层、判定层只管解析结果 —— 与批 E1 的 `{{tmp:}}` 占位同一套路 | 临时文件随作用域自动清；落盘失败会如实说「未执行」而不是静默跳过 |

**本批验证**（全部实跑）：`--selfcheck` **177 通过 0 失败**（166 → 177，+11 例：Layer 1 解析 /
null 与 0 分可区分 / 信号键列全 S1–S10 / 契约形状不对时报错 / 低置信度阈值与升序 / 默认裁决 /
agent.json 形状 / 终稿复核数 / diff 抽实码 / hunk 头解析 / 分数档位边界）；
`contract-check.sh` **54/54**（真引擎沙箱，42 → 54，+12 条：Layer 1 的 schema/总分/signals/entities/
uncertain/diagnostics 六项 + **夹具造得出真实「拿不准的项」**的前提断言 + Layer 3 的 schema/
alerts/sources/复核数四项）；
`ci.sh` **10/10 门全绿**（第 9 门扩到 **66 项**接线点，+17 项补丁体检链路）。
**十处负控真红**：① null 信号回落成 0 分 → selfcheck 红；② 低置信度改成降序 → selfcheck 红；
③ 低置信度阈值反向 → selfcheck 红；④ 裁决 id 不原样回填 → selfcheck 红；
⑤ 越界 verdict 不归一 → selfcheck 红；⑥ 复核数改读顶层 `reviewed` → selfcheck 红；
⑦ hunk 新起始行号算错 → selfcheck 红；⑧ 契约形状不对时不报错 → selfcheck 红；
⑨ diff 抽实码行号算错 → selfcheck 红；⑩ 摘掉详情页入口 → 接线门红（exit 1）。
**契约夹具独立**：补丁体检的夹具是**另一个项目**（`atlaspatch`）—— 改动必须留在工作区（不提交），
又不能污染主夹具（主夹具的 tree/arch 断言依赖它的原始内容）。
**顺手记进台账 D 节的一处 mac 缺陷**：mac 的终稿读顶层 `reviewed` 键，而引擎载荷里没有这个键
→ mac 的「已复核 N 条」永远不显示（deepin 读 `diagnostics.reviewed_by_agent`，已实现）。
**视觉零变化**（补丁体检是独立窗，不进四页快照矩阵，快照基线未动）。

### 批 G：固定文档页（关于 / 帮助 / 开源感谢 / 更新日志）

mac 的 `DocsPages.swift`（321 行）把四类长文**写死在源码里**（每类四种语言），
理由是「固定内容写在代码里（跨平台一致）」—— 文档不是数据、不随仓库变、不需要引擎供数。
本批把这四类接到 deepin。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 118 | **文档内容层 `logic/DocPages`（纯函数，写死在代码里，不取引擎）** | 文档不是引擎的事实，也不是仓库的数据 —— 引擎里没有「关于页」这种东西。写死最省事也最稳 | 内容改动要重新发版（这是写死的固有代价） |
| 119 | **内容按 deepin 的事实另写**，不抄 mac 的文案 | mac 的「关于」写的是「客户端（deepDolphin, Swift, AI 层）」「macOS ARM64 首发版」；deepin 是「Qt 6 + DDE / DTK」「deepin / UOS 桌面版」。照抄会让「关于」页**把本客户端说成另一个平台的** —— 文档撒谎比没有文档更糟 | 两端文案要各维护一份（结构一致，事实各写） |
| 120 | **判据盯「事实写对没有」，不是「有没有字」**：关于页必须含本平台词（Qt / DDE / deepin）且**不含** mac 的平台词（Swift / macOS）；帮助页提到的入口（架构图 / 代码图谱 / 补丁体检）必须**真的存在** | 文档最容易悄悄过期：功能改了、文案没改，用户按着过时文档点一个不存在的入口。判据把「文档吹牛」变成红灯 | 帮助页跟着功能走 —— 以后加能力要同步改文案（判据会提醒） |
| 121 | **仓库地址单一出处**（`clientRepo()` / `engineRepo()`），正文里出现的仓库 URL 必须都来自这两个函数 | 手抄地址迟早抄错（少个 `/tree/dev` 就是另一个地址）。判据用正则扫正文里所有 `github.com/asdshuaishuai/…`，逐条比对 | 无 |
| 122 | **认不出的类目/语言返回空串**，不回落成「关于」的正文 | 回落的话，加错了类目会静默显示一段「看着像那么回事」的关于页，用户根本分不清自己看的是哪一篇 | 无 |
| 123 | **mac 的两个原生窗（关于 / 帮助）在 deepin 合成为一个文档窗 + 顶部分段切四类目** | deepin 面板不是原生菜单栏应用，没有「关于 / 帮助」菜单项的对位物；且 mac 的两处内容本来就同源（`AboutHelpWindows.swift` 注释明写「两处内容必须同源」），分成两个窗反而容易写出两份 | 与 mac 的**承载形态**不同（两个原生窗 vs 一个窗 + 分段），能力一致 —— 章程允许 |
| 124 | **入口放面板菜单**（「关于 deepDolphin」/「帮助」） | 面板菜单是 deepin 现有的全局动作入口（更新 / 扫描 / 设置都在那儿），不另造入口 | 不是「原生菜单栏」（DDE 面板无此对位物） |

**本批验证**（全部实跑）：`--selfcheck` **186 通过 0 失败**（177 → 186，+9 例：四类目齐全与标识稳定 /
四类正文非空且互不相同 / 显示名互不相同 / 平台词写对且不含 mac 平台词 / 仓库地址只有两个出处 /
帮助页入口真实存在 / 致谢页点名引擎与模型目录 / 更新日志有版本号 / 认不出的语言返回空串）；
`ci.sh` **10/10 门全绿**（第 9 门扩到 **76 项**接线点，+10 项文档页链路）。
**八处负控真红**：① 抄 mac 的平台词（Swift）→ selfcheck 红；② 四类正文回落成同一篇 → selfcheck 红；
③ 正文里手抄第三个仓库地址 → selfcheck 红；④ 认不出的语言回落成中文 → selfcheck 红；
⑤ 帮助页提到不存在的入口 → selfcheck 红；⑥ 类目标识改名 → selfcheck 红；
⑦ 致谢页漏掉模型目录 → selfcheck 红；⑧ 摘掉面板菜单的文档入口 → 接线门红（exit 1）。
**负控抓出的两处真问题**：
① **判据太松**：查仓库地址的正则原先在 `/` 处截断，`https://…/moongit/tree/dev` 会被截成
`https://…/moongit` → 手抄第三个地址蒙对。已改成吃满路径段（负控 ③ 现真红）。
② **接线门太松**：门只盯 `showDocs` 方法与 `DocsDialog` 的存在，**盯不到菜单入口那一行** ——
摘掉菜单两行、留着方法，门照样全绿（用户却永远打不开文档）。已补两条**入口级**检查
（`addAction(QStringLiteral("关于 deepDolphin"))` / `…("帮助")`），负控 ⑧ 现真红。
**顺手更正台账一处错记**：B10「仪表盘项目卡片整卡可点」原记「未开始」，实际
`ProjectProgressCard::mouseReleaseEvent` → `goProject` 早已实现（`Card` 是 QFrame 不吞鼠标事件，
事件冒泡到卡片），另有 mac 同款的「进入管控 →」钮 —— 本批复核时更正为「已对位」。
**视觉零变化**（文档是独立窗，不进四页快照矩阵，快照基线未动）。

### 批 H：9 语言语法高亮（代码图谱页源码页签）

mac 用原生 `AttributedString` 给源码上色（关键字紫 / 字符串绿 / 注释灰 / 数字黄）。
本批把同一套语义接到 deepin 的 `QPlainTextEdit` 上。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 125 | **判定层 `logic/SyntaxHighlight`（纯函数）出「哪一段是什么 token」，涂色层 `ui/CodeHighlighter` 出「这种 token 用哪个 DS 令牌」** | 高亮的判定是纯字符串问题，与控件、主题都无关。抽出来可无头判 —— 分类错了（关键字染成字符串、字符串里的 `#` 当注释）在界面上只是「颜色怪了点」，不测就永远发现不了 | 多一层；跨进程传 token 段时不能直接传（暂不需要） |
| 126 | **九种语言与引擎 `detectLang` 逐条对齐**（swift / cangjie / ts / python / go / rust / java / kotlin / c），契约门第 16 组用真引擎跑九种扩展名比对 | 引擎报什么语言，客户端就得能高亮什么语言。少一种，那种语言的源码就是**一片纯色** —— 而「一片纯色」在界面上看不出是缺能力还是代码本来就长这样 | 引擎加第十种语言时，这门会红（提醒补） |
| 127 | **判定层不碰颜色**（颜色是主题的事） | 换主题只改涂色层，判定层一个字不动 | 无 |
| 128 | **整行注释单独特判**（trim 后以注释前缀开头 → 整行一段） | 否则 `//` 之后的 `int`、`return` 会被当关键字染紫 —— 一行注释里几块彩色，比不染色更花 | 无 |
| 129 | **字符串的着色吃到闭合引号** | 半截着色的字符串最难看（引号和内容不同色） | 无 |
| 130 | **python 的 `#` 只在字符串外才是注释** | 字符串里的 `#` 当注释会把后面整行涂灰 | 无 |
| 131 | **行首「行号 + 制表符」不参与着色**（`setGutterEnabled`） | 行号栏不是代码。着色它会让每行开头多一块黄/紫 | 无 |
| 132 | 加无头 flag **`--syntax-languages`** 暴露语言清单 | 契约门要拿**运行时真清单**与引擎比对 —— 靠源码解析会在改写法时静默空转（与 `--agent-tool-names` 同款理由） | 无 |

**本批验证**（全部实跑）：`--selfcheck` **198 通过 0 失败**（186 → 198，+12 例：九语言齐全且顺序对齐 /
九张关键词表都真能扫出 keyword / 不认识的语言回落仓颉 / 整行注释一整段 / 行尾注释吃到行尾 /
字符串吃到闭合引号 / 字符串里的 `#` 不当注释 / python 行尾 `#` 是注释 / 关键字与十六进制分得开 /
段升序不重叠不越界 / 行注释前缀 / 空行不产段 / 补的「python 行尾 #」一条）；
`contract-check.sh` **56/56**（真引擎沙箱，54 → 56，+2 条：客户端清单与引擎 `detectLang` 产物逐条相等 /
九种一个不少）；
`ci.sh` **10/10 门全绿**（第 9 门扩到 **85 项**接线点，+9 项语法高亮链路）。
**八处负控真红**：① 语言清单少一种 → selfcheck 红；② 整行注释不特判 → selfcheck 红；
③ 字符串不吃闭合引号 → selfcheck 红；④ 不认识的语言不回落 → selfcheck 红；
⑤ 段越界 → selfcheck 红；⑥ python 行尾 `#` 不当注释 → selfcheck 红；
⑦ 关键字识别失效 → selfcheck 红；⑧ 摘掉源码页签的高亮接线 → 接线门红（exit 1）。
**负控抓出的三处真问题**：
① **判据不敏感**：「字符串里的 `#` 不当注释」那条判据碰不到行尾 `#` 的分支（字符串分支先命中）——
   补了一条专测行尾 `#` 的判据（负控 ⑥ 现真红）。
② **变异写重**：有一条负控与「字符串不吃闭合引号」是同一处改动，期望却挂在另一条判据上
   （挂着的那条本就不该被它影响）—— 已删错配的那条。
③ **接线门太松（第三次同类）**：门盯的是「`CodeHighlighter` 这个词出现过」，而 include 与另一个
调用点还在 → 摘掉构造那一行、门照样全绿（用户看到的源码页签还是一片纯色）。已改成盯**构造点**
（`new CodeHighlighter`），负控 ⑧ 现真红。
**顺手更正台账两处错记**：B16「关系树 / 图谱的导出动作（查 + 生成 + 导出三件套）」原记「未开始
（依赖 B1/B2）」，实际批 D2/E2 已把三件套都做全（架构图页与代码图谱页各有查/生成/导出）；
B12 已按本批转绿。
**视觉变化**：代码图谱页源码页签现在有语法着色（该页是独立窗，不进四页快照矩阵，基线未动）。

### 批 I：图谱三件套（overview / symbol / impact）

引擎的 `graph` 有五个子命令，批 E2 接了 `tree` / `functions`，本批把剩下三个接上。
**mac 侧 `graph symbol` / `graph impact` 只有服务函数、UI 里没接**（只有 agent 工具能用）——
deepin 接进 GUI 属**领先 mac**。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 133 | **引擎的 `graph symbol` / `graph impact` 只认「符号名」** —— 客户端一律先用 `symbolNameFromId(id)` 取名字再问引擎 | 传符号 id（`f:路径:行号:名字`）进去，引擎返回 `{}` —— 那空结果**看着像「这个符号没有影响面」**，实际是有影响面的（客户端明明持有 id，却传错了形态）。这是「错得毫无声响」的一类坑：用户看到「无影响面」，不会怀疑是客户端传错了 | 引擎将来若同时接受 id，这层取名仍是安全的（名字是 id 的后缀） |
| 134 | **符号不存在不是错误**：引擎对查不到的符号返回空 `defs` 且**退出码 0** | 界面必须显示「没找到这个符号」，而不是一片空白；更不能当成契约坏了。判定层用 `found()`（defs 非空）区分「没找到」与「契约坏了」 | 无 |
| 135 | **影响面必须披露粒度与截断**（引擎自报 `granularity: lexical-file-level`，截断时 `refFilesCapped` / `impactedCapped`） | 影响面是**词法近似**，不是真正的调用图。不披露就成了「完整的影响面」，那是假的 | 用户可能误以为影响面很准 —— 已用粒度标签说明 |
| 136 | **`graph overview` 接到代码图谱页头**（文件数 · 符号数 · 语言分布 + 截断披露） | mac 把 overview 取了却**没显示**（ArchPage 里 `overview` 变量没被用到）；deepin 显示出来才算真接上 | 无 |
| 137 | 判据与契约门**两边都钉「只认名字」**：selfcheck 判 `symbolNameFromId`；契约门第 17 组用真引擎跑「传名字有结果 / 传 id 是空结果」 | 只在客户端侧判是不够的 —— 引擎哪天改了口径，客户端的取名逻辑就悄悄失配。契约门用真引擎对比，才是真口径 | 无 |
| 138 | 接线门盯**调用点**（`^[[:space:]]*showImpact\(\);[[:space:]]*$`）而不是方法名 | 方法定义还在时 grep 照样命中 —— 这是**第四次**同类漏洞（前面三次：构造点、菜单入口、菜单入口） | 无 |
| 139 | **引擎 doctor 的「发现问题」不是「命令失败」**：客户端读**载荷**判成败，**不看退出码** | 引擎 doctor 在 `problems>0` 时**退出码是 1**（引擎自己注释写了「自检命令必须能失败」—— 两条路径原来都恒返回 0，脚本/CI 判断不了环境可用性），但 stdout 仍是**合法 JSON**。按退出码判 → 用户看到「引擎调用失败」而不是「环境有 N 个问题」—— 自检工具最该说清的事反而没说 | 无 |
| 140 | **`result` 是自由文本**：按引擎口径的 `problems` 判健康，**不自己数「非 OK 的项」** | 引擎的检查项结果有「OK」「1 个失效」「0」「无」「项目外」「未创建」多种取值，后几种都是**正常**的。按 `result == "OK"` 判会把「注册项目 0 个」误报成故障；引擎的「临时残留」也**不计入** problems | 无 |
| 141 | **缺 `problems` 键记为「未知」（-1）而不是回落成 0** | 回落成 0 会把「引擎没发」说成「没问题」—— 缺字段不回落成 0 是全项目纪律 | 契约过旧时摘要显示「问题数未知（契约可能过旧）」而不是「0 个问题」 |
| 142 | **回执通道 = stdout 优先，stdout 空时取 stderr**（`EngineCli::receiptText`） | 引擎的 `report` 把「报告已生成：<路径>（N 个项目）」写在 **stderr**（`arch gen` / `render arch` / `index gen` / `confidence gen` / `render index` 才在 stdout —— 实测 2026-10-19）。只认 stdout 的话 `report` 会被判成「引擎没有回执（退出码 0）」——**明明成功却说失败**，而报告其实已经落盘了 | exit==0 时 stderr 不是错误通道（引擎的失败文案走 stdout，CONTRACT §4）；引擎若把 report 改回 stdout，行为不变 |
| 143 | **回执显示前剥 ANSI**（`ArchReceipt::plain`） | 引擎的 report 回执带颜色码（`\x1b[32m✓\x1b[0m`），而引擎**不认 NO_COLOR**（实测设了照样带码 —— 客户端注入了 `NO_COLOR=1` 也没用）。裸塞进 QLabel，用户看到的是「[32m✓[0m 报告已生成：…」—— 回执里的关键信息被乱码埋了 | 无 |
| 144 | **报告回执走独立信号 `reportExported`**，不与 `archActionFinished` 合流 | 架构图窗按项目路由地收 `archActionFinished`（还会在「架构已生成」时重载画布）。合流会让架构图窗显示报告的回执，甚至把「报告已生成」当成「架构已生成」而重载画布；两个项目的窗还会串台 | 多一个信号（无） |
| 145 | **「导出报告」入口放项目详情页页头**，报告卡给回执 + 落盘路径 + 「打开报告」 | 报告是**可交付物**（要能给人看/存档），路径必须露出来 —— 只给一句「已导出」用户找不到文件。抽不到路径就**不给**「打开」入口（坏按钮比没按钮更糟） | 无 |
| 146 | **「环境自检」放设置·通用页** | 「环境坏了」是最难自查的一类问题：界面看着好好的，引擎在后台早就跑不动了。设置页是用户找配置的地方，自检是环境配置的一部分 | 设置窗必须把 `AppModel` 传下去（通用页经它调引擎） |
| 147 | **回执路径抽取按后缀分桶缓存**（`ArchReceipt::filePath(text, suffix)`） | 泛化那一步把正则放进了函数级 `static` 里 —— **第一次调用用哪个后缀就把模式焊死**，之后传 `.md` 也按 `.html` 找，报告路径永远抽不到（「打开报告」入口永不出现）；反向还会在 `.html` 文本里抽出别的路径。症状极隐蔽：调用点与参数看着全对，只有行为不对 | 无 |
| 148 | **新增两个无头 flag**（`--doctor-parse` / `--receipt-file-path`） | 契约门第 18 组要拿**真引擎**的载荷/回执喂客户端逐条对判定结果 —— 自造夹具验的是另一回事（引擎形状变了、客户端没跟上，自造夹具照样全绿）。与 `--agent-tool-names` / `--syntax-languages` 同款理由 | 无 |
| 149 | **接线门抽成独立脚本 `scripts/ci-wiring.sh`**（ci.sh 第 9 门调它） | 改接线时要能秒级验（不用跑完整个 ci.sh —— 截图矩阵最慢）；更要紧的是**负控能精确打这一门**（门内嵌在 ci.sh 里时，负控得跑整条 CI 才看得到红） | 多一个脚本（无） |
| 150 | **构建登记检查改整词匹配**（`grep -qE "(^|\s)$f(\s|$)"` 而不是 `grep -qF "$f"`） | `grep -qF` 是**子串**匹配：把登记项改成 `src/logic/EngineDoctor.cpp.disabled` 照样命中 —— 门绿着，文件却没编进去。负控实测出的假阴性 | 无 |
| 151 | **引擎配置（`config list`）接进设置·通用页**：展示「浅更新只记前 N 个分支」「文档备份留 N 份」「受管文档」「扫描根」 | 这两条是**用户能直接看到后果**的策略：「这个分支怎么没更新」= 撞上了上限，「备份怎么不见了」= 留份数到了。用户此前只能靠猜，而猜错就会去改代码。mac 侧的注释（`Models.swift`）已经点出「按 `backupKeep` 裁剪，而用户从不知道它存在」，但 mac 也没接 `config list` —— deepin 补上 | 无 |
| 152 | **引擎配置与客户端设置刻意分开**（不许形成两个真相源） | 客户端的 AI 设置在 `app/Settings`；引擎的 `config.ai` **恒为空对象**（引擎自报「AI 由客户端层负责，引擎保持 AI 无关」）。客户端**不许**从引擎 config 读 AI 设置 —— 两边各有一份，用户改哪边都可能不生效。判定层连 `ai` 键都不解析 | 无 |
| 153 | **缺字段用 -1 哨兵 + present 标志，不拿 0 当缺失** | `backupKeep: 0` 是**合法值**（明确不保留备份）。拿 0 当缺失 → 界面把「明确不要备份」说成「不知道留几份」，两句话意思完全相反。缺 `update` 键则整份配置判为「读不出来」，不当空配置放行 | 无 |
| 154 | **可写键白名单在客户端也卡一道**（`EngineConfig::writableKeys`） | 引擎对未知键会报错，但那是**事后**（用户看到的是一句引擎报错）。客户端先拦一道，界面就不会给用户一个必然失败的键 | 无 |
| 155 | **可写项只给「数量」语义的两个键**（`update.maxShallowBranches` / `update.backupKeep`），`language` 与 `roots` **只读** | ① `language` 是**引擎侧**的语言 —— 客户端自己没有 i18n（台账 B8 未做），让用户改引擎语言只会造成中英混排；② `roots` 是数组语义，而客户端已有「添加/扫描项目」入口（`scan <根>`），两个入口改同一件事会打架 | 这两个键仍可从命令行改（`moongit config set language en`）—— 客户端只是不在界面上给入口 |
| 156 | **改动在下次更新/备份时生效**，界面明说 | 引擎配置是引擎读配置时生效的，改完当前行为不变。界面若不说清，用户会以为「改了没用」而反复点 | 无 |
| 157 | **`config set` 走 Text 契约**（回执在 stderr，与 `report` 同款） | 拿 callJson 去收，exit==0 也会被判成「引擎输出不是合法 JSON」—— 成功被报成失败。批 J 修的 `EngineCli::receiptText`（stdout 优先、空则 stderr）正好覆盖 | 无 |
| 158 | **判定不接 GUI 的引擎能力**：`confidence query` / `graph db` / `confidence db` / `arch query|update` / `track` / `hook` / `mcp` / `skill` | ① `confidence query` 是 `graph confidence` 的**子集**（少了 `findings[]` 逐条疑点，多了 `indexUpdateCount`/`generatedAt`）—— 接了反而丢信息；② `graph db` / `confidence db` 是给 agent 用 SQL 查的单文件 SQLite，GUI 无对应物；③ `arch query` 与架构图页的 scene 数据重叠，会造出第二个真相源；④ `track`/`hook`/`mcp`/`skill` 是钩子/宿主/教学包，无 GUI 对位物 | 这些能力**仍可经 agent 工具面使用**（28 个工具里已含 `arch query` / `index query` / `confidence query`）—— 判定不接 GUI ≠ 判定不接能力 |
| 159 | **代码图谱页显性化「持久化索引」的状态**（`index overview`）：代数 / 节点 / 边 / 文件 / 探针时间 | 页头概览读的是**实时扫描**（`graph overview`），而「生成」按钮写的是**持久化索引**（`index gen`）—— 两套数据源。用户点完「生成」**看不到任何变化**（索引写进去了，界面没读它），按钮形同虚设，用户只会以为坏了 | 无 |
| 160 | **新增「增量更新」钮**（`index update`） | 引擎有源状态探针：源文件没动时只跑探针、不重建。改了代码不必全量 `index gen` | 无 |
| 161 | **「已最新」≠「已更新」**：源文件没动（`fresh: true`）时界面明说「索引已是最新」，不说「更新好了」 | `fresh: true` 时引擎**什么都没重建**。说成「更新好了」就是骗人 | 无 |
| 162 | **`rebuilt` 是条件键**（fresh 时引擎不发）→ 加 present 标志 | 按 `false` 读会把「这次没重建」说成「从来没重建过」（后者是历史事实） | 无 |
| 163 | **判定不接 GUI：`index query`** | 与已接的 `graph functions`（关系页签在用）**高度重叠** —— `tier` / `findings` / `weight` 两边都有，`index query` 的 `defs[]` 只是 `functions[]` 的重排。接它会造出**第二个真相源**（同一份调用关系两个来源） | 该能力**仍可经 agent 工具面使用**（28 个工具里含 `index query`）—— 判定不接 GUI ≠ 判定不接能力 |
| 164 | **Canvas font 简写按**浏览器 CSS 口径**解析**（`px` 与 `pt` **都认**），解析抽到判定层 `logic/CanvasFont` | 移植时把解析器写成「只认 px」—— 于是 `"11pt sans-serif"` 里的 `11pt` 被当成**字体族名**吞掉，**字号根本没设上**（渲染成默认字号）。界面上看着「字号不太对」，没人知道是单位没被识别。这违背 CanvasSink 头注释的红线：「语义是浏览器 Canvas2D 的语义，不是『差不多就行』」 | 无 |
| 165 | **不认的单位不当成别的单位**（`11em` ≠ `11px`） | 悄悄按 px 算会让字号与预期差一截还看不出来 | 无 |
| 166 | **Canvas2D 的 QFont 按串**静态缓存** + 同串跳过 | 30fps 下每帧每张卡片都要 setFont：热力图 50 卡 × 4 次 = **每次重绘 200 次** setFont，每次都要 split + 构造 QFont + 字体族匹配。缓存必须**静态** —— Canvas2D 每帧新建（paintEvent 里局部构造），实例级缓存等于每帧重建 | 无 |
| 167 | **热力图三处每帧分配收掉**：`id→卡片` 索引随布局建（不是每帧建 QHash）、字体串改静态常量、缓存判据逐项比较成员（不是拼四参数字符串键） | 同上：30fps 下每帧 50 次哈希插入 + 200 次 QString 拼接 + 1 次字符串键 —— 全是纯浪费 | 无 |
| 168 | **日期格式化走 `Qt::ISODate` 枚举**（mac 性能审计 `21c7082` 的 Qt 对应） | `QDate::toString(格式串)` 每次调用都要**新建一个 QDateTimeFormat**（解析格式串 + 建缓存）。`Qt::ISODate` 对 QDate 就是 `yyyy-MM-dd`，且 Qt 内部走现成的 ISO 快速路径。⚠ `QDateTimeFormat` 在 **Qt 6.9 之前不是公开类**，deepin 用的这版没有 | 无 |
| 169 | **台账 B13 的「deepin 无可见性暂停」是过期描述** —— 实测已具备 | 实测（2026-10-19，Qt 6）：**父窗口隐藏会给子控件发 `hideEvent`**（`QWidget::setVisible(false)` → 子控件收到 `QHideEvent`），所以 `hideEvent → m_anim->stop()` 真的停得住；架构图与热力图都是 33ms（≈30fps）+ 停表，与 mac 修完后的口径一致 | 无 |
| 170 | **CanvasSink 的方法集不扩**（26 个标准方法，红线「多一个私有 API → 契约被污染」） | 性能优化走**内部缓存**而不是加 `setFontPx` 之类的新方法 —— 契约清单是移植验收清单，不该被性能需求污染 | 无 |
| 171 | **D2 grep 门改为先剥注释再扫**（与门 7 同一份 `strip_comments`） | 注释里提到 API 名（如 `setPixelSize`）**不是散值** —— 把它算进命中只会逼人改措辞而不是改代码。存量 4 处都在**真实代码**里，剥注释不减少它们（实测剥前后都是 4/4） | 无 |
| 172 | **QSS 字号散值收进 `DS::FontPx` token**（徽章 11 / 等宽 13），D2 门上限 **4 → 0** | QSS 里的 `font-size` 只能写字面量，没法走 DFontManager 档位 —— 于是「徽章 11px」在 3 个文件里各写一遍。改字号要翻 3 处，且其中一处忘了改就看不出来。收成一处可调常量后，**上限直接降到 0**：此后任何一处新散值当场红 | QSS 字号**不随系统字号缩放**（`FontT` 档位会缩放，QSS 字面量不会）—— 这是 QSS 表达力的固有限制，不是本决策造成的 |
| 173 | **`DS::FontPx` 明确不是「档位」**（注释写死） | `FontT` 走 DFontManager 档位、**会随控制中心放大字号变**；`FontPx` 只是把字面量收口成一处常量。两者混称「字号档位」会让人以为 QSS 字号也跟着缩放 | 想「随系统缩放」就别用 QSS 写字号，走 `DS::font(FontT)` 设 QFont |
| 174 | **alpha 与 RGB 同权**：强调底透明度入 token（`DS::Alpha::accentTint = 0.18`），rgba 由 `DS::accentTintRgba()` 拼 | 色进了 DS 而透明度没进 —— 同一个「18% 强调底」散成 N 个真相源。alpha 是色的第四维，和 RGB 一样是设计决策 | 无 |
| 175 | **热力图画布配色收进 `HeatLayout::Canvas`**（卡底/文字/标签/注释/描边五档） | 原来散在 `HeatmapWidget` 的 **7 处** —— 改一处配色要翻 7 个地方。⚠ **不进 DS**：DS 是通用设计令牌（表面/文字/语义色），组件专属色塞进去 DS 就成杂物袋；但**必须有唯一出处**，而热力图的色职责本来就在判定层（`heatColor`/`idColor`） | 五档色值是热力图专属，改热力图配色仍要动 `logic/HeatLayout`（这是有意的：唯一出处） |
| 176 | **D2 门的检测形式必须全**（6/8 位 hex、3 位 hex、`QColor(r,g,b)`、`QColor(0x..)`、`rgb()`、带裸 alpha 的 `rgba()`、`setPixelSize`/`setPointSizeF` 的数字参数、QSS `font-size` 字面量、**含 `font-size:` 文件里的裸数字 `.arg(N)`**） | ⚠ **同一个值换个写法就溜过去 = 门是假的**。旧门只盯 `#RRGGBB` —— 于是 `QColor(0x10, 0xB9, 0x81)`、`rgb(255,0,204)`、`QColor(89, 240, 184)` 全都合法，而它们**就是同一批色值**。本批把形式补全后，又照出 **9 处真散值**（热力图 7 处 + 底轨遮罩 1 处 + 契约色形态 1 处） | 形式补全后，门对「写成非 hex 形态的契约色」会报红 —— 这正是它该做的（契约色走**显式豁免**，见决策 177） |
| 177 | **豁免必须逐条登记，且不许腐化**（`scripts/ci-d2.sh` 的 `D2_EXEMPT` 清单：路径 + `keep`/`fix` + 理由） | 旧门靠「契约色用 `rgb()` 不用 `#hex`」**碰巧躲过**检测 —— 换个写法就溜了。豁免要**登记出来**（进 git diff，评审可见），不能靠写法差异隐性获得。另：`fix` 模式（已立项待收敛的豁免）**命中数归零时门必须红** —— 「这一条已经收敛了，把它从清单里删掉」，白名单不许越积越多 | 豁免清单要人工维护；路径写错（文件不存在）门直接红，逼着当场改对 |
| 178 | **接线门的 `strip_comments` 必须按文件类型分派**（C++ 的 `//` / shell 的 `#`） | ⚠ 负控实测抓到：旧 `strip_comments` 只剥 `//`，扫 `ci.sh` 时**整份 shell 注释都留着** —— 于是「注释里提过 `ci-d2.sh`」被当成「`ci.sh` 调了 `ci-d2.sh`」，**门被骗过**（第七次「同名/子串互相顶替」）。已按扩展名分派 | 无 |
| 179 | **固定色下沉到判定层 `logic/SemColors.h`**（`DS::semColor` 转发它） | 批 N 把散值门补全后照出：状态语义色在 `DS::semColor` 与 `logic/Derived` / `tray/TrayController` / `tray/TrayPopupWindow` / `platform/IconLoader` **各有一份**（绿 `#10B981` / 紫 `#8B5CF6` / 橙 `#F59E0B` / 灰 `#9CA3AF` 同值散落）—— 同一语义多份定义。**下沉到判定层**是因为：判定层要返回 QColor，它**不能依赖 ui 层**；托盘与平台层也要用同一批色 | 色值住在 `logic/`，改它要动判定层（这是有意的：唯一出处）。`accent` 例外 —— 它接 DTK 运行期主题强调色，天然住 ui 层 |
| 180 | **`DS::semColor()` 变成转发层**（不再自己写色值） | 否则 DS 与 `SemColors` 又成两份定义 —— 转发的意义就是**只有一个地方能改**。接线门用 `arch_forbid` 盯「DS 不再自己写语义色字面量」 | 无 |
| 181 | **陈旧红 `#EF4444` 与危险红 `#DC2626` 是两档，不合并** | 语义不同：`red` = 错误/危险（量级高档、读不出来）；`stale` = 陈旧/停滞（分支 `stale` / 引擎停滞 / 久未更新）。mac 的 `StatusColor.systemColor` 把 `stale` 映射成 red —— 故这档红是**语义**不是皮肤。合并成一个红 = 「停滞」和「出错」看起来一样 | 同一屏上会出现两档红（不算缺陷，但看久了要能分清） |
| 182 | **提交类型的 12 色序列色刻意与状态语义色分开** | 有几档**同值**（red/orange/purple/teal/mint/yellow/gray），但**语义不同**：序列色是「序号 → 颜色」的映射（提交构成卡 / 语言分布卡），mac 的 `DSColor.sequence` 也是这么做的（用 SwiftUI 标准色，与状态色刻意不同）。共用一份定义 = 改状态色会连累序列卡 | 仓内仍有两处同值色（序列色 vs 状态色），但**语义与改动机都不同**，不合并 |
| 183 | **接线门加 `arch_forbid`**（盯「**不该有的东西没了**」） | 收敛类改动光靠 `arch_need`（查「在」）看不出回退：把写死的色值又写回去，「它还在」这件事没有任何正向条目能抓。`arch_forbid` 反过来盯「**不该出现的字面量又出现了**」 | 负向条目容易误报（文件重命名/挪走时旧路径不存在 → 报「文件不存在」红）；挪文件时要同步改门条目 |
| 184 | **跨端状态色取值差异另立一批**（本批不吞） | 查 mac 时发现两端**取值口径不同**：`DSColor.color(DSStatus)` 把 `stale` 映射成**橙**，而 mac 自己的 `StatusColor.systemColor` 映射成**红**（deepin 对齐的是后者）；Liveness 侧 mac 的 `engineStale`/`quiet` 是**灰**、`notGit` 是灰，deepin 是红/紫；`idle` 黄档、unknown 灰档也不同档。改这些**会动视觉基线**，且 mac 自己就有两套映射 —— 需要逐点核对 + 视觉评审，不能顺手改 | deepin 暂沿用现取值（与 mac 的 `StatusColor.systemColor` 语义一致）；差异已记进台账 D 节 |
| 185 | **引擎获取链走「查 GitHub API + 按平台挑资产」，不用固定 URL** | ⚠ **实测（2026-10-19）**：引擎 release 的资产名**带版本号**（`moongit-v0.1.0-linux-x64.tar.gz`），而 GitHub 的 `releases/latest/download/<name>` 要求**资产名精确匹配** —— mac 侧用的固定 URL `releases/latest/download/moongit-darwin-arm64.tar.gz` **实测 404**（不带版本号），带版本号的才 200。固定 URL 是脆的（引擎改一次打包命名就断） | 多一次 API 请求（且受 GitHub 匿名限流）；换来的是「引擎改了打包命名也不会断」 |
| 186 | **客户端可以写盘，但只限「程序自身的依赖」，业务数据仍一律经引擎子进程** | 「客户端零业务数据写入，一切经引擎子进程」说的是**业务数据**（项目状态 / 里程碑 / 文档 / 日志）。引擎二进制是**程序依赖** —— 不装它客户端根本跑不起来。mac 侧同样有这条下载链 | 无 |
| 187 | **引擎装到用户目录 `~/.local/libexec/deepdolphin/moongit`**（不碰系统目录、不要 sudo） | 落进 `/usr/local/bin` 要 root，桌面应用不该要 root；也不该覆盖用户用 `install.sh` 手动装的那份。**用户目录 = 用户自己就能删能改** | 这条路径不在引擎 `install.sh` 的约定里（那是 `~/.local/bin`）—— 两条路径各有其主，见决策 191 |
| 188 | **落盘名是 `moongit`，包内文件叫 `moongit-cli`**（引擎打包时改的名） | 引擎发现链认的是 `moongit`；不改名的话装好了也找不到。**改名不改身份**：二进制对外的名字仍是 moongit | 无 |
| 189 | **sha256：有校验和必须核对；没有校验和要说「未校验」，不冒充「已校验」** | GitHub 的 release 资产带 `digest`（sha256）—— 核对它是「下载到的文件确实是发布方声明的那个」的唯一手段。校验和不匹配 = **拒绝安装**（半个坏引擎比没引擎更糟）。但旧 release 可能没有这个字段 —— 那就**如实说「未校验」**，不能装作验过了 | 无校验和时用户拿到的是「未核对」的引擎（界面明说） |
| 190 | **下载失败分七类，各说各的** | 「失败要说清是哪一种」：网络不可达 / 载荷读不懂 / 本平台没资产 / 下载中断 / 校验和不匹配 / 解压失败 / 装完跑不起来 —— 这七种对用户的下一步**完全不同**（换网 / 等发版 / 换源 / 报障）。笼统一句「下载失败」等于让用户自己猜 | 界面文案变长（分七种）—— 但每种都能直接指导下一步 |
| 191 | **发现链要认得下载链装的位置，且排在 `~/.local/bin` 之前** | 装到 `~/.local/libexec/deepdolphin/` 后**发现链根本找不到它**（候选里没这一项）—— 装好了等于没装。顺序也有讲究：mac 的 `build.sh` 注释记着同一个教训 ——「顺序必须是客户端自带的优先，否则永远选到 `~/.local/bin` 那个**过期安装版**」 | 客户端下载的版本会**优先于**用户手动装的（对一般用户是对的：跟 latest 走） |
| 192 | **当下这条链还下载不到东西** —— 引擎 latest release（v0.1.0）**只有 darwin-arm64 资产，没有 Linux x64** | 引擎的 release workflow **已经产出** Linux 包（`moongit-*-linux-x64.tar.gz`），但 v0.1.0 发布时 linux job 还不存在于 workflow，所以那一次**没上传**。⇒ 引擎侧**下一次发版**就有了，**引擎仓不需要改**。客户端这边如实报「该版本没有 Linux x64 安装包（现有：…）」，不静默失败 | 现在真机上点「下载引擎」会得到「该版本没有 Linux x64 安装包」；这是**引擎仓的资产缺口**，不是客户端的缺陷 |
| 193 | **引擎 post-commit / post-merge 钩子接进客户端**（设置·自动化页「提交后自动记录进度」卡） | 引擎有 `hook install/uninstall/status`，但**两端都没接**（mac 侧 `macos/Sources/` 一处 `hook` 调用都没有）—— 用户 commit 完得自己回客户端点「更新」。钩子是**自动化**（装一次、全程受益），故放设置·自动化页而不是详情页 | 钩子装在**每个项目的 .git/hooks** 里（经引擎写，客户端零业务数据写入的纪律不受影响）；mac 侧未接（两端都缺 → 接了是 deepin 领先） |
| 194 | **「卸载」按钮敢提供的安全前提**：引擎的托管块机制**实测**不吞用户内容 | 实测（2026-10-19）：install 把托管块插到**前面**、用户原有钩子内容**追加在后面**（不覆盖）；uninstall **只删托管块**，用户自己的逻辑原样留着。⇒ 客户端的「卸载」不是删用户数据 | 契约门第 22 组把这两条**钉成断言**（一旦引擎改了行为，门立刻红） |
| 195 | **引擎 `hook status --json` 的 `installed` 是数组按位置**（`[0]`=post-commit、`[1]`=post-merge），位置约定**显式写死**在判定层 | 引擎的 `installed` **没有键名** —— 位置即语义。这个约定若在两处各解释一遍就会漂。判定层写死 + 接线门钉住「`arr.at(0)` 恰好一处、`arr.at(1)` 恰好一处」 | 引擎若改成对象（`{"postCommit":true}`）→ 判定层记「读不出来」，**不猜** |
| 196 | **缺 `installed` 键 = 契约漂移，不是「没装」** | 把漂移当「没装」会让人去**重装一个已装的钩子**（而重装会再插一个托管块）。同理：数组长度不够 = 漂移，不是「那一项没装」 | 状态行会明说「状态读不出来」，并把它与「没装」**分开列** |
| 197 | **批量结果要点名失败的项目**（「N 个成功」≠「全成功」） | 装 5 个项目失败 1 个，只报「5 个成功」是骗人。汇总句必须把失败的项目**逐个点名**并带上原因 | 无 |
| 198 | **中文匹配串不能用 `QLatin1String`**（Latin-1 每字符 1 字节，装不下中文） | 判据里 `QLatin1String("引擎退出码 1")` 会被截断 → `contains` 恒假 → **判据看着在、实际抓不住任何东西**（本批实测踩到）。中文一律 `QStringLiteral` | 无 |
| 199 | **台账 C.1 的「仍可经 agent 工具面使用」对 6 条命令是失真描述** —— 修正 | 实测引擎的 28 个 agent 工具里**没有** `graph db` / `confidence db` / `track` / `hook` / `mcp` / `skill`。台账原话「多数仍可经 agent 工具面用」对这几条**不成立**（它们只能走命令行/宿主）。文档失真要修 —— 台账是判断依据，失真比缺项更糟 | 无 |

**本批验证**（全部实跑）：`--selfcheck` **205 通过 0 失败**（198 → 205，+7 例：id 取名字 / 概览解析 /
概览契约不对时报错 / 符号详情解析 / 符号不存在是「没找到」不是错误 / 影响面解析 / 影响面契约不对时报错）；
`contract-check.sh` **65/65**（真引擎沙箱，56 → 65，+9 条：overview 键齐全 + 截断键恒发 /
symbol 键齐全 / impact 键齐全 / 受影响符号字段 / **传名字才有结果** / **传 id 是空结果** /
符号不存在返回空 defs + **退出码 0**）；
`ci.sh` **10/10 门全绿**（第 9 门扩到 **96 项**接线点，+11 项图谱三件套链路）。
**八处负控真红**：① id 取名字改成取第二段 → selfcheck 红；② id 取名字改成原样返回（客户端会传 id
给引擎）→ selfcheck 红；③ 概览不读截断披露键 → selfcheck 红；④ 符号「没找到」被当成找到了 →
selfcheck 红；⑤ 影响面不读截断标志 → selfcheck 红；⑥ 影响面缺 name 时不报错 → selfcheck 红；
⑦ 影响面不读粒度 → selfcheck 红；⑧ 摘掉关系页签的影响面**调用点** → 接线门红（exit 1）。
**负控抓出的真问题**：接线门盯的是「`showImpact` 这个词出现过」，而**方法定义还在** → 摘掉调用点、
门照样全绿（影响面永远不会被加载）。已改成盯**调用点**的正则（`^[[:space:]]*showImpact\(\);$`）。
**视觉变化**：代码图谱页页头多一行项目级概览；关系页签多「引用来源」「影响面」两段
（该页是独立窗，不进四页快照矩阵，基线未动）。

### 批 J：引擎自检（doctor）+ 进度报告导出（report）

决策见上表 **139–150**（自检口径三处 + 回执通道 + 承载形态 + 两个无头 flag + 接线门抽离 + 构建登记检查改整词匹配）。

**本批验证**（全部实跑）：`--selfcheck` **220 通过 0 失败**（205 → 220，+15 例：自检载荷解析 /
**result 是自由文本** / 摘要按引擎口径 / **有问题时仍是一份有效报告** / **缺 problems 键记「未知」** /
缺 checks 键报错 / 检查项行文 / 剥 ANSI / 抽 .md 路径 / 相对路径不抽 / 后缀不对不抽 /
**后缀不同的两次抽取互不污染** / 回执通道 stdout 优先 / **stdout 空时取 stderr** / 两路都空=没有回执）；
`contract-check.sh` **76/76**（真引擎沙箱，65 → 76，+11 条 = **契约门第 18 组**：doctor 载荷键齐全 /
**result 是自由文本** / **临时残留不计入 problems** / 客户端端到端判成 ok 档 / report 回执给 .md 路径 /
**引擎把 report 回执写在 stderr** / 客户端抽出的路径真实存在 / 注册路径失效 → problems>0 /
**有问题时退出码非 0** / **有问题时 stdout 仍是合法 JSON** / 客户端端到端判成 problem 档）；
`ci.sh` **10/10 门全绿**（第 9 门扩到 **129 项**接线点，+33 项：自检链路 13 项 + 报告链路 20 项）。
**二十处负控真红**：判定层 8 处 —— ① problems 缺键回落成 0 → selfcheck 红；② 把「result != OK」
当成有问题 → selfcheck 红；③ 缺 checks 键不当空报告放行 → selfcheck 红；④ 问题数未知判成「没问题」→
selfcheck 红；⑤ 检查项行文留悬空「·」 → selfcheck 红；⑥ **回执路径正则被第一个后缀焊死**
→ selfcheck 红；⑦ 回执不剥 ANSI → selfcheck 红；⑧ **回执通道只认 stdout** → selfcheck 红；
接线 12 处 —— ⑨ 摘掉「运行自检」按钮构造点 → 接线门红；⑩ 摘掉 `m_model->runDoctor()` 调用 →
接线门红；⑪ 摘掉设置页的 `doctorFinished` 接线 → 接线门红；⑫ 设置窗不再把模型传给通用页 →
接线门红；⑬ 面板不再把模型传给设置窗 → 接线门红；⑭ 摘掉详情页「导出报告」入口 → 接线门红；
⑮ 摘掉详情页的 `reportExportRequested` 发信号 → 接线门红；⑯ 摘掉面板的入口接线 → 接线门红；
⑰ 摘掉面板调 `exportReport` → 接线门红；⑱ 摘掉面板的报告回执接线 → 接线门红；
⑲ 自检改成按退出码判成败 → 接线门红；⑳ **`EngineDoctor.cpp` 没进构建** → 接线门红。
**负控抓出的三个真问题**：
① **`filePath` 的正则被函数级 `static` 焊死**（泛化那一步引入的静默缺陷）—— 第一次调用用哪个后缀，
之后传 `.md` 也按 `.html` 找，报告路径永远抽不到；已改成按后缀分桶缓存，并加判据钉死。
② **引擎的 `report` 把回执写在 stderr**（`arch gen` / `render arch` 才在 stdout）—— 客户端只认 stdout
会把「报告已生成」判成「引擎没有回执」；已改成 `EngineCli::receiptText`（stdout 优先、空则 stderr）。
③ **构建登记检查是子串匹配**（`grep -qF`）—— 把登记项改成 `.disabled` 照样命中，门绿着文件却没编进去；
已改成整词匹配（门 8 与门 9 两处都改了）。
**视觉变化**：设置·通用页多一张「环境自检」卡（按钮 + 摘要 + 逐项检查行）；项目详情页页头多
「导出报告」钮、页头下多一张「进度报告」卡（回执 + 落盘路径 + 「打开报告」）。**两处都不在
四页快照矩阵里**（设置窗与详情页都不进矩阵），基线未动。

### 批 K：引擎配置面（config list / get / set）接进设置页

决策见上表 **151–158**（引擎配置接进设置页 / 与客户端设置分开 / -1 哨兵 / 键白名单 /
只给「数量」语义的两个键 / 生效时机说明 / Text 契约 / 判定不接的引擎能力清单）。

**本批验证**（全部实跑）：`--selfcheck` **226 通过 0 失败**（220 → 226，+6 例：配置载荷解析 /
摘要只报有值的项 / 缺 update 键报错 / **缺 backupKeep 记「未知」而不是 0** /
**0 是合法值** / 可写键恰好四个）；`contract-check.sh` **87/87**（真引擎沙箱，76 → 87，
+11 条 = **契约门第 19 组**：顶层键齐全 / update 四键齐全 / 两个数字是数字 / roots 与 docs 是数组 /
**引擎的 ai 恒为空对象** / `config get` 返回 JSON 值 / **`config set` 的回执写在 stderr** /
引擎拒绝非整数值 / 引擎拒绝未知键并列出可用键 / 客户端端到端解析真载荷 /
客户端端到端把真回执净化成干净的一句话）；
`ci.sh` **10/10 门全绿**（第 9 门扩到 **154 项**接线点，+25 项）。
**十七处负控真红**：判定层 5 处 —— ① 缺 update 键不当空配置放行 → selfcheck 红；
② **backupKeep 缺键回落成 0** → selfcheck 红；③ **0 被当成「引擎没发」** → selfcheck 红；
④ 可写键清单多给引擎不认的键 → selfcheck 红；⑤ 受管文档读错键 → selfcheck 红；
接线 12 处 —— ⑥ 摘掉「读取引擎配置」按钮构造点 → 接线门红；⑦ 按钮不再接读 → 接线门红；
⑧ 打开设置页不再自动读 → 接线门红；⑨ 不再写回分支上限 → 接线门红；⑩ 不再写回备份份数 →
接线门红；⑪ 摘掉配置变化信号接线 → 接线门红；⑫ 摘掉配置写入回执接线 → 接线门红；
⑬ **`config set` 改成 callJson**（回执型命令走 Json 契约 = 成功报成失败）→ 接线门红；
⑭ 键白名单被摘掉 → 接线门红；⑮ **配置写入读 stdOut 而不是 receipt**（回执在 stderr，读不到）
→ 接线门红；⑯ 读取引擎配置的方法不再调引擎 → 接线门红；⑰ 摘掉 CMake 登记 → 接线门红。
**负控抓出并已修的四处「门太松」**（**第五次**同类漏洞：同名调用点互相顶替）：
① 门盯 `m_model->loadEngineConfig()` 而该调用有**两处**（按钮 / 打开本页自动读）→ 摘掉一处
门照样绿；已拆出 `reloadEngineConfig()`，门改成分别盯「按钮→读」（单行 connect 正则）与
「打开本页→读」（整行独占正则）。② 门盯 `m_model->setEngineConfig(` 而写回有**两次**调用
（两个键）→ 改成按键分别盯。③ 门盯泛化的 `res\.receipt` 而 AppModel 里有多处读它 → 改成盯
`emit engineConfigSaved(true, res.receipt);` 本行。④ 负控驱动器自身 expect 串扰
（「载荷解析」撞上批 J 的同名行）→ 改成带前缀的精确串。
**另修一个自己发现的缺陷**：点「应用」写回第一个键会触发一次配置重读，把用户**刚填的第二个
还没写回的值冲掉**（用户以为「改了没用」而反复点）→ 加 `m_configInputsDirty` 脏标志，
手改未写回时重读不回填。
**视觉变化**：设置·通用页多一张「引擎配置」卡（读取引擎配置钮 + 只读行 + 两个数字输入 + 应用钮）。
该页不在四页快照矩阵内，基线未动。

### 批 L：持久化代码索引的状态接进代码图谱页

决策见上表 **159–163**（索引状态显性化 / 增量更新钮 / 「已最新」≠「已更新」 /
`rebuilt` 条件键 / 判定不接 `index query`）。

**本批验证**（全部实跑）：`--selfcheck` **236 通过 0 失败**（226 → 236，+10 例：概览解析 /
摘要 / 缺 nodes 键报错 / 缺 updateCount 记「未知」 / **缺 edges/files 记「未知」** /
**0 是合法值** / **缺探针字段记「未知」** / fresh 时不发 rebuilt 键 /
源文件变了 fresh 假 rebuilt 真 / 缺 fresh 键报错）；
`contract-check.sh` **96/96**（真引擎沙箱，87 → 96，+9 条 = **契约门第 20 组**：
概览键齐全 / 三个计数是数字 / 探针三字段齐全 / **fresh 时引擎不发 rebuilt 键** /
源文件没动 fresh 为真 / 源文件变了 fresh 假 rebuilt 真 / 代数递增 /
**重建后的 indexJson 落盘路径真实存在** / 客户端端到端解析真概览）；
`ci.sh` **10/10 门全绿**（第 9 门扩到 **172 项**接线点，+18 项）。
**十六处负控真红**：判定层 7 处 —— ① 缺 nodes 键不当空索引放行 → selfcheck 红；
② **updateCount 缺键回落成 0** → selfcheck 红；③ **edges/files 缺键回落成 0** → selfcheck 红；
④ **0 被当成「引擎没发」** → selfcheck 红；⑤ **rebuilt 的 present 标志被抹掉** →
selfcheck 红；⑥ 缺 fresh 键不当契约漂移报错 → selfcheck 红；⑦ **探针字段缺失回落成 0**
→ selfcheck 红；
接线 9 处 + 构建登记 1 处 —— ⑦ 摘掉「增量更新」按钮构造点 → 接线门红；⑧ 摘掉
`updateIndex` 调用 → 接线门红；⑨ 摘掉 `loadIndexOverview` 调用 → 接线门红；
⑩ 摘掉 `indexStatusChanged` 接线 → 接线门红；⑪ 摘掉 `indexUpdated` 接线 → 接线门红；
⑫ **不再区分「已最新」与「已重建」** → 接线门红；⑬ 改掉 `index overview` 调用 → 接线门红；
⑭ 改掉 `index update` 调用 → 接线门红；⑮ **`IndexStatus.cpp` 没进构建** → 接线门红。
**负控抓出并已修的四处「判据不够分叉」**：① 变异落在 `nodes` 的 `contains` 守卫上 ——
但**那是死代码**（缺 `nodes` 早已退报错），变异根本不生效；已把变异改指 `updateCount`，
并**删掉那个死守卫**（写个 `if` 反而让人以为「缺了会回落成 0」）。② 「fresh 时 rebuilt 键
不发出」那条判据只断言 `!rebuiltPresent` —— 变异把 present 标志抹掉照样 PASS；已补上
「rebuilt 键存在时 present 必须为真」。③ 探针 `maxMtime` 的变异落在**有该键的夹具**上；
已补一条「缺探针字段记为「未知」而不是 0」的判据。④ `edges` 缺键的变异同样落在**有该键的
夹具**上；已补一条「缺 edges/files 键记为「未知」而不是 0」的判据。
**修掉一个真缺陷**：代码图谱页的「生成」写的是**持久化索引**（`index gen`），而页头概览
读的是**实时扫描**（`graph overview`）—— 两套数据源，用户点完「生成」**看不到任何变化**
（索引写进去了，界面没读它），按钮形同虚设。批 L 把索引状态显性化，两者界面分开摆。
**判定不接 GUI**：`index query` 与已接的 `graph functions`（关系页签在用）高度重叠
（`tier`/`findings`/`weight` 两边都有），接它会造出第二个真相源；仍可经 agent 工具面使用。
**实测补充**：引擎在索引缺失/过期时会**自愈**（`selfHealed: true`，实测 2026-10-19：
从没点过「生成」的项目，`index overview` 照样返回完整载荷且 `selfHealed: true`）——
所以索引状态行在用户点「生成」之前就有内容，且会明说「引擎自愈过索引」。
**视觉变化**：代码图谱页顶栏下多一行「增量更新」钮 + 索引状态行。该页是独立窗，
不进四页快照矩阵，基线未动。

### 批 M：性能审计（B13）—— 动画时钟、字体路径、每帧分配

决策见上表 **164–170**（CSS 口径的 font 简写 / 不认的单位不当别的单位 / QFont 静态缓存 /
热力图三处每帧分配 / `Qt::ISODate` / 台账 B13 过期描述修正 / 契约方法集不扩）。

**本批验证**（全部实跑）：`--selfcheck` **244 通过 0 失败**（236 → 244，+8 例：pt 单位被识别 /
px 单位被识别 / 字重 + 像素字号 / 缺字重时不误认 / 多段字体族按空格分开 /
**不认的单位不当成别的单位** / **不认识的段不被当成字重** / 空串不崩）；
`contract-check.sh` **96/96**（不变 —— 本批不涉引擎契约）；`ci.sh` **10/10 门全绿**
（第 9 门扩到 **183 项**接线点，+11 项）。
**十四处负控真红**：判定层 5 处 —— ① 不认 pt 单位 → selfcheck 红；② **不认的单位悄悄
当成 px** → selfcheck 红；③ 字重从不标记 → selfcheck 红；④ 多段字体族只取第一段 →
selfcheck 红；⑤ **字重范围放宽（"12px" 被当字重）** → selfcheck 红；
接线 9 处 —— ⑥ Canvas2D 不走判定层（自己再 split 一份 = 第二个真相源）→ 接线门红；
⑦ **静态字体缓存被摘掉** → 接线门红；⑧ **同串跳过被摘掉** → 接线门红；
⑨ **热力图字体串改回每帧拼** → 接线门红；⑩ **热力图索引改回每帧建** → 接线门红；
⑪ 热力图缓存判据改回拼字符串键 → 接线门红；⑫ 日期格式化改回格式串 → 接线门红；
⑬ `CanvasFont.cpp` 没进构建 → 接线门红。
**负控抓出并已修的四处「门太松 / 判据不够分叉」**（**第六次**同类问题）：
① 门盯 `m_fontKey` 这个**名字** —— 变异把 `if (f == m_fontKey) return;` 换成注释
（名字还在）门照样绿 → 门改成盯**跳过的那一行**。② 门盯「有 `kFontCard` 这个常量」——
变异把它改回 `QStringLiteral("%1pt sans-serif")`（**恰恰是每帧拼的写法**）门照样绿
→ 门改成盯**值里没有 % 占位**。③ 门盯「`m_cardById` 出现过」—— 变异把绘制路径改回每帧
建 QHash（成员还在 rebuild 里）门照样绿 → 门改成盯**绘制路径引用缓存索引那一行**。
④ 判据用 `"12px"` 夹具验「缺字重时不误认」—— 但 `"12px"` 的 `toInt` 本来就失败，
范围放宽也误认不了 → 改用**无单位的 `"12"`** 夹具（「12」既不是字重（<100）也不是字号
（无单位）→ 不当字重吃掉），分叉点才立住。
**顺带修掉一个移植语义缩水**：热力图的字体写的是 `"11pt sans-serif"`，而解析器只认 `px`
—— `11pt` 被当成**字体族名**吞掉，**字号根本没设上**（渲染成默认字号）。Canvas 的 font
简写是**浏览器 CSS 口径**（`px` 与 `pt` 都认），这违背 CanvasSink 头注释的红线
「语义是浏览器 Canvas2D 的语义，不是『差不多就行』」。现由 `logic/CanvasFont` 按 CSS
口径解析，`pt` 如实生效（热力图文字恢复到设计要的 11pt / 9pt）。
**顺带改进 D2 门**：门 5 原先直接 `grep -rn`，**注释里提到 API 名也算命中** —— 本批新增的 `logic/CanvasFont.h` 注释里写了 `setPixelSize` 就把命中数从 4 顶到 5，门红。已改成**先剥注释再扫**（与门 7 同一份 `strip_comments`），存量 4 处都在真实代码里，剥前后都是 4/4 —— 门从此只拦**代码里的**散值。
**实测修正一处过期描述**：台账原记「deepin 有 HasAnimations 纪律但**无可见性暂停**」——
实测（2026-10-19，Qt 6）**父窗口隐藏会给子控件发 `hideEvent`**，所以架构图与热力图的
`hideEvent → m_anim->stop()` **真的停得住**，两处都是 33ms（≈30fps），与 mac 修完后的
口径一致。台账已改。
**视觉变化**：热力图的卡片文字/次级文字字号从「默认字号」变成设计要的 11pt / 9pt。
代码图谱页是独立窗，不进四页快照矩阵，基线未动。

### 批 N：设计系统存量清零（B14）—— 散值清零 + 门补盲区

决策见上表 **172–178**（QSS 字号 token / `FontPx` 不是档位 / alpha 与 RGB 同权 /
热力图画布色收进 `HeatLayout::Canvas` / 门的检测形式要全 / 豁免显式登记且不腐化 /
`strip_comments` 按文件类型分派）。

**做了什么**：① M3-3 登记的 **4 处字号散值**全收进 `DS::FontPx`（徽章 11 / 等宽 13），
D2 门上限 **4 → 0**；② 修 `DesignTokens.h` 里 `MD_H3` 注释自相矛盾（写 15 实为 14）；
③ 强调底透明度 `0.18` 进 `DS::Alpha`（**alpha 与 RGB 同权**），rgba 由
`DS::accentTintRgba()` 拼；④ 底轨遮罩进 `DS::trackMask()`；⑤ 热力图**深色画布配色**
（卡底/文字/标签/注释/描边五档）收进 `logic/HeatLayout` 的 `HeatLayout::Canvas`
（组件专属色不进 DS 杂物袋，但要有唯一出处）。

**门的盲区是这批的真正收获**：旧 D2 门只盯 `#RRGGBB` —— 于是 `QColor(0x10,0xB9,0x81)`、
`rgb(255,0,204)`、`QColor(89,240,184)` 全都合法，而它们**就是同一批色值**。
把检测形式补全（6/8 位 hex、3 位 hex、`QColor(r,g,b)`、`QColor(0x..)`、`rgb()`、
带裸 alpha 的 `rgba()`、`setPixelSize`/`setPointSizeF` 数字参数、QSS `font-size` 字面量、
**含 `font-size:` 文件里的裸数字 `.arg(N)`**）后，一口气照出 **9 处真散值**
（热力图 7 处 + 底轨遮罩 1 处 + 契约色形态 1 处）—— 全部在本批收口。
**门的形式不全 = 门是假的**：旧门的「4 处存量」其实只是「4 处**写成 hex 形态**的存量」。

**豁免从「碰巧躲过」改成「登记出来」**：`scripts/ci-d2.sh` 的 `D2_EXEMPT` 清单逐条登记
（路径 + `keep`/`fix` + 理由）。`keep` = 永久豁免（契约层 / 令牌定义处 / 判据夹具）；
`fix` = **已立项待收敛**的豁免（`Derived` / `TrayController` / `TrayPopupWindow` /
`IconLoader` 的**状态语义色第二份定义**），**命中数归零时门必须红** —— 「这一条已经
收敛了，把它从清单里删掉」，白名单不许腐化。登记的路径若不存在，门直接红。

**本批验证**（全部实跑）：`--selfcheck` **249 通过 0 失败**（246 → 249，+3 例：
透明度 token + rgba 拼装 / 底轨遮罩 / 热力图五档画布色）；`contract-check.sh` **96/96**
（不变 —— 本批不涉引擎契约）；`ci.sh` **10/10 门全绿**（第 9 门扩到 **201 项**接线点，
+18 项）；`scripts/ci-d2.sh` **0/0**（存量已清零）。
**二十五处负控真红**：D2 散值门 10 处 —— ① QSS 字号改回 `.arg(11)`（占位符喂字号那条路）
→ 门红；② 改回 `font-size: 11px` → 门红；③ Markdown 改回 `.arg(14)` → 门红；
④ 等宽字号改回 `setPixelSize(13)` → 门红；⑤ 强调底改回 `rgba(...,0.18)` → 门红；
⑥ 底轨遮罩改回 `QColor(128,128,128,40)` → 门红；⑦ 热力图卡底改回 `QColor(19,31,48)`
→ 门红；⑧ 塞一个 `rgb()` 字面量 → 门红；⑨ 豁免清单写不存在的路径 → 门红；
⑩ 豁免清单漏掉一个真散值文件 → 门红。
接线门 9 处 —— ⑪ 字号 token 命名空间被摘掉 → 门红；⑫ 胶囊徽章改回字面量 → 门红；
⑬ 小标签改回字面量 → 门红；⑭ Markdown h4-h6 的字号被摘掉 → 门红；⑮ 热力图卡底色
改回字面量 → 门红；⑯ 分段条底轨改回字面量 → 门红；⑰ CI 流程不再调用独立散值门
→ 门红；⑱ 散值门自检豁免腐化的那行被摘掉 → 门红；⑲ 豁免清单首行被改 → 门红。
判定层 6 处 —— ⑳ 字号 token 值被改 → selfcheck 红；㉑ Markdown 档位值被改 → red；
㉒ 透明度 token 值被改 → red；㉓ 底轨遮罩值被改 → red；㉔ 热力图卡底色值被改 → red；
㉕ **判据里的期望值被「顺手改掉」**（token 纪律最常见的破口）→ red。

**负控抓出并已修的三处「门太松 / 判据不够分叉」**（**第七次**同类问题）：
① 门盯 `namespace FontPx` 这个**名字** —— 变异把它改成 `namespace FontPxRemoved`
（**子串仍匹配**）门照样绿 → 门改成盯**带词边界**的 `namespace FontPx\b`。
② 门盯 `ci-d2\.sh` —— 但 `strip_comments` 只剥 C++ 的 `//`，扫 `ci.sh` 时**整份 shell
注释都留着**，于是「注释里提过 `ci-d2.sh`」被当成「`ci.sh` 调了 `ci-d2.sh`」，
**门被骗过** → `strip_comments` 改成**按文件类型分派**（C++ 的 `//` / shell 的 `#`），
门同时改成盯**调用那一行**（`sh "$SRC/scripts/ci-d2.sh"`）。
③ 门盯 `豁免已失效` —— 变异改成 `豁免已失效XX`（**子串仍匹配**）门照样绿 → 门改成
盯**具体那一行**（`豁免已失效：$_p`）。
另补两条分叉点：④ `DS::MD_H3` 在 `MarkdownView.h` 里有**两次** `.arg()`（h3 一次、
h4-h6 一次）—— 门盯名字会放过「只摘掉 h4-h6 那次」→ 改成盯**带分号的那次**
（只有 h4-h6 喂的那个带分号）；⑤ 豁免清单的 `D2_EXEMPT` 在脚本里出现多次 ——
门盯词会放过「只改首行」→ 改成盯**清单首行那一行**。

**已知边界（留给下一批）**：`logic/Derived.cpp`、`tray/TrayController.cpp`、
`tray/TrayPopupWindow.cpp`、`platform/IconLoader.cpp` 里的**状态语义色是第二份定义**
（与 `DS::semColor` 同值：绿 `#10B981` / 紫 `#8B5CF6` / 橙 `#F59E0B` / 灰 `#9CA3AF`），
且 `Derived` 另有一档 `0xEF4444` 红是 DS 没有的（值要跟 mac 逐档核对）。
本批**不吞**它 —— 那是**取值核对 + 架构归属**（状态色该住 `logic` 还是 `ui`）的事，
已登记为 D2 门的 `fix` 豁免项（命中归零即门红，逼着收敛）。

**视觉变化**：无。字号/色值的**取值全部逐字不变**（11px/13px/0.18/热力图五档原值），
只是从散落各处收进 token —— 四页快照矩阵基线未动。

### 批 O：状态语义色单一真相源（台账 E.1）—— 固定色下沉到判定层

决策见上表 **179–184**（固定色下沉 `logic/SemColors` / `DS::semColor` 变转发层 /
陈旧红与危险红是两档 / 序列色刻意与状态色分开 / 接线门加 `arch_forbid` /
跨端取值差异另立一批）。

**做了什么**：批 N 把散值门补全后照出 —— 状态语义色在 `DS::semColor` 与
`logic/Derived`（`livenessColor` / `branchStatusColor` / `statTint`）、
`tray/TrayController`、`tray/TrayPopupWindow`、`platform/IconLoader` **各有一份**
（绿 `#10B981` / 紫 `#8B5CF6` / 橙 `#F59E0B` / 灰 `#9CA3AF` 同值散落）。
本批新增 `src/logic/SemColors.h`（判定层纯色、零 UI 依赖）作为**唯一出处**，
`DS::semColor()` 改为**转发**它；判定层 / 托盘 / 平台层一律从它取值。
**取值一字未改** → 视觉零变化。

**为什么固定色住判定层而不是 `ui/DesignTokens.h`**：① `accent` 要接 **DTK 运行期主题**
（`DGuiApplicationHelper` = ui 层），判定层碰不到；② 判定层（`logic/Derived`）要返回
QColor，它**不能依赖 ui 层**；③ 托盘与平台层也要用同一批色。⇒ 纯色值下沉，
`DS::semColor()` 转发 —— 对位 mac 的分层（mac 的 `DesignTokens.swift` 是**纯函数层**，
`DesignSystem.swift` 才是视图层）。

**两档红不是笔误**：`red`（`#DC2626`）= 错误/危险；`stale`（`#EF4444`）= 陈旧/停滞
（分支 `stale` / 引擎停滞 / 久未更新）。mac 的 `StatusColor.systemColor` 把 `stale`
映射成 red —— 故这档红是**语义**不是皮肤，**不合并**。

**门与判据的分工（本批的关键认识）**：
- **源码门**（`arch_need_count` + `arch_forbid`）抓**结构**：「这个 token 恰好出现 N 次」
  「这个文件里不许再出现色值字面量」。⚠ 「出现过的名字」抓不住回退 ——
  同名 token 在一个文件里常有多处（`SemColors::shallow()` 在 `Derived.cpp` 有 2 处、
  `FixedColors::iconFallback()` 在 `IconLoader.cpp` 有 2 处），变异只摘掉其中一处时
  「出现过」照样绿 → 新增 `arch_need_count`（**必须恰好 N 次**，少一处多一处都红）。
- **判定层断言**抓**值与错位**：「`DS::semColor(shallow) == SemColors::shallow()`」
  能抓住**转发错位**（shallow 转发成 deep），抓不住「改回**同值**字面量」——
  值一样，断言自然成立。**同值副本归源码门管**（`arch_forbid` 盯「DS 里不许有
  `QColor(0x`」）。分工写清楚，才不会误以为「判据绿 = 没问题」。

**本批验证**（全部实跑）：`--selfcheck` **253 通过 0 失败**（249 → 253，+4 例：
DS 与唯一出处同源 / 陈旧红与危险红是两档 / 固定色三档 / 判定层与唯一出处同源）；
`contract-check.sh` **96/96**（不变 —— 本批不涉引擎契约）；`ci.sh` **10/10 门全绿**
（第 9 门扩到 **214 项**接线点，+13 项）；`scripts/ci-d2.sh` **0/0**。
D2 门里那四条 `fix` 豁免（`Derived` / `TrayController` / `TrayPopupWindow` /
`IconLoader`）**因命中归零而删掉** —— 门本来就会红（`fix` 模式「归零即红」），
是它在逼着收敛。

**视觉变化**：无。**所有色值逐字不变**（含两档红、托盘强调蓝、图标兜底灰），
只是把「散落 5 处」改成「1 处 + 4 处引用」。四页快照矩阵基线未动。

### 批 P：引擎获取链（GitHub Releases 下载安装）—— 台账 B15

决策见上表 **185–192**（查 API 不抄固定 URL / 客户端可写程序依赖不写业务数据 /
装用户目录不碰系统目录 / 落盘名 moongit / 校验和要么核对要么说「未校验」 /
七类失败各说各的 / 发现链要认得且优先 / 当下引擎侧还没有 Linux 资产）。

**做了什么**：判定层 `logic/EngineDownload`（查 API → 按平台挑资产 → sha256 校验 →
落盘路径 → **七类失败各说各的**）+ 执行层 `app/EngineInstaller`（网络与解压**全异步**，
不卡 GUI）+ `AppModel::downloadEngine()` + 设置·通用页新增「引擎」卡（下载并安装引擎）。

**顺带修掉一个真缺陷**：引擎装到 `~/.local/libexec/deepdolphin/` 后，**发现链根本找不到
它**（候选列表里没这一项）—— 装好了等于没装。已补这一步，且**排在 `~/.local/bin`
之前**（mac 的 `build.sh` 注释记着同一个教训：「顺序必须是客户端自带的优先，否则永远
选到 `~/.local/bin` 那个**过期安装版**」）。

**实测发现 mac 侧的引擎下载链 URL 已失效**：`build.sh` 用固定 URL
`releases/latest/download/moongit-darwin-arm64.tar.gz`，而引擎的资产名**带版本号**
（`moongit-v0.1.0-darwin-arm64.tar.gz`）⇒ **实测 404**（带版本号的才 200）。
⇒ deepin 侧**不抄这个固定 URL**，改走「查 API + 按平台挑资产」（引擎改一次打包命名也不会断）。
已记进台账 D 节；**mac 侧本轮未改**（次序先搞定 dde）。

**本批验证**（全部实跑）：`--selfcheck` **260 通过 0 失败**（249 → 260，+11 例）；
`contract-check.sh` **103/103**（96 → 103，**+7 条 = 契约门第 21 组**：file:// 打桩
端到端跑通「下载→校验→解压→落盘→探活」/ 落盘的引擎可执行且改名成 moongit /
**校验和不匹配 → 拒绝安装且不落盘** / 本平台没资产 → 说清是哪一种 /
**真 GitHub API** 的 latest release 能被判定层读懂）；`ci.sh` **10/10 门全绿**
（第 9 门扩到 **229 项**接线点，+15 项）。

**⚠ 当下这条链还下载不到东西**（如实记录，不是缺陷）：引擎 latest release（v0.1.0）
**只有 darwin-arm64 资产，没有 Linux x64** —— 引擎的 release workflow **已经产出**
Linux 包（`moongit-*-linux-x64.tar.gz`），但 v0.1.0 发布时 linux job 还不存在于
workflow，所以那一次**没上传**。⇒ **引擎仓不需要改**，下次发版即生效。
现在真机上点「下载引擎」会如实得到「该版本没有 Linux x64 安装包（现有：…）」，
**不静默失败**。

**视觉变化**：设置·通用页多一张「引擎」卡（该页**不在**四页快照矩阵里，基线未动）。

### 批 Q：引擎 post-commit 钩子接进客户端 —— 提交后自动记进度

决策见上表 **193–199**（钩子接进客户端 / 卸载的安全前提已实测 / `installed` 数组按位置 /
缺键是漂移不是「没装」 / 批量要点名失败项目 / 中文不能用 `QLatin1String` /
台账失真描述要修）。

**做了什么**：判定层 `logic/EngineHook`（解析 `hook status --json` + 状态文案 + 批量汇总）
+ `AppModel::loadHookStatus / installHooksAll / uninstallHooksAll`（**串行**逐项目跑，
不并发、不卡 UI）+ 设置·**自动化**页新增「提交后自动记录进度」卡（概览 + 逐项目明细 +
「为所有项目安装」/「全部卸载」两个钮）。

**为什么放在自动化页而不是详情页**：钩子是「装一次、全程受益」的事（每个项目都要装），
放自动化页一次办完；放详情页的话用户得进 N 个项目点 N 次。

**安全前提是实测出来的，不是假设的**（这一步决定「卸载」按钮敢不敢给）：引擎的托管块
机制 —— install 把托管块插到**前面**、用户原有的钩子内容**追加在后面**（不覆盖）；
uninstall **只删托管块**，用户自己的逻辑原样留着。⇒ 界面的「卸载」不是删用户数据。
契约门第 22 组把这两条**钉成断言**（引擎哪天改了行为，门立刻红）。

**顺带修掉台账一处失真描述**：原文「判定不接 GUI ≠ 判定不接能力 —— 多数仍可经 agent
工具面用」。实测引擎的 28 个 agent 工具清单后确认：`arch query` / `arch update` /
`index query` / `confidence query` **确实在**工具面里；而 `graph db` / `confidence db` /
`track` / `mcp` / `skill` **不在** —— 台账原话对这几条不成立，已改。文档失真比缺项更糟
（台账是判断依据）。

**本批验证**（全部实跑）：`--selfcheck` **267 通过 0 失败**（260 → 267，+7 例）；
`contract-check.sh` **109/109**（103 → 109，**+6 条 = 契约门第 22 组**：真引擎装上后两个
钩子都报已安装 / 载荷带日志路径 / 客户端判定层把真载荷读成「两个都装了」 /
**装上后用户原有钩子逻辑仍在** / 卸载后都报未安装 / **卸载后用户原有钩子逻辑仍在**）；
`ci.sh` **10/10 门全绿**（第 9 门扩到 **242 项**接线点，+13 项）。

**视觉变化**：无（设置页不在四页快照矩阵里，基线未动）。

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
