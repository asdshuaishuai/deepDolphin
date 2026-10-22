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

**开发树内运行**（⚠ **批 S 实测修正**：运行期**不需要**任何环境变量 —— 宿主自带 Qt6/DTK6）：

```sh
# 裸环境直接跑（实测：`env -u LD_LIBRARY_PATH -u QT_PLUGIN_PATH ./build/deepDolphin --selfcheck`
#       → 269 通过 0 失败；`ldd` 0 个 not found；加载的是 /lib/x86_64-linux-gnu 下的系统库）
QT_QPA_PLATFORM=offscreen        # 无显示环境时；共享 X11 会话可去掉这行直接上真 DDE
./build/deepDolphin
```

> **原文失真已修**（批 S）：这里原写着「Qt6/DTK6 运行库在 sysroot 里，环境变量缺一不可」，
> 并说「`ldd` 裸环境报 Qt6/DTK6 not found」。**实测不成立** —— 宿主 `/lib/x86_64-linux-gnu`
> 里本来就有 `libdtk6widget.so.6` / `libQt6Widgets.so.6`，插件目录里也有
> `libchameleon.so`（DTK 样式）与 `libdxcb.so`（DTK 平台插件）。
> sysroot 是**编译期**用来装 dev 头文件的（宿主没有 `-dev` 包），**不是运行期依赖**。
> ⚠ 二进制**无 RPATH/RUNPATH**，`DT_NEEDED` 全是 soname ⇒ 换台机器只要系统有这些库就能跑。
> 实测：裸环境与带 sysroot 环境**拍出的快照逐像素 0 差异**（两种环境观感相同）。

安装：`cmake --install build --prefix /usr`（binary → bin，desktop →
share/applications/cn.deepdolphin.app.desktop，图标 → share/icons/hicolor/scalable/apps）。
**打 deb（批 S 新增，D7 达分的必经）**：`sh scripts/build-deb.sh` → `build/deb/cn.deepdolphin.app_<版本>_amd64.deb`。
安装后由系统 Qt6/DTK6 运行库满足链接，**无需任何环境变量**（deb 的 `Depends` 已实测列出，
且构建时会拿二进制的实际 `DT_NEEDED` 与 `scripts/deb-deps.txt` **双向核对**，漏一项就构建失败）。

本阶段实测记录：`--selfcheck` 269 通过 0 失败；`--version` 输出 `deepDolphin 0.1.0`；
offscreen 启动探测 `timeout 8` 退出码 124（进程存活满 8 秒）；
**批 S 实测**：裸环境 `ldd` **0 个 not found**；deb 解包后的二进制在裸环境下
`--selfcheck` 269/0 通过、快照能拍出 ⇒ D7 的「装后零环境变量」在本机达成。
（真机 clean deepin 25 容器的 `dpkg-deb -b` + 安装 + 启动仍是 D7 的最终验收，
本机**无 docker/podman**，该步未实跑。）

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
| `QObject::connect: No such signal QPlatformNativeInterface::systemTrayWindowChanged(QScreen*)` | 环境限制 | offscreen 无系统托盘；真 DDE 走 **deepin 托盘窗口协议**（批 Y 实测，与「运行期事实」一致）。托盘真实表现仍**待真机验证** |
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
| 163 | **判定不接 GUI：`index query`** | 与已接的 `graph functions`（关系页签在用）**同维度** —— 两边给的都是**函数级调用边 + 边的确信度档位 `tier`**（⚠ 批 AA 实测：`graph functions` 的 `functionEdges` **5274 条、每条带 `tier`**，`index query` 的 `callers[]` 也每条带 `tier`）。差别只在**取数形态**（`index query` 能**按符号反查**，`defs[]` 是单符号定义，**不是** `functions[]` 全项目列表的重排）⇒ 接它会造出**第二个真相源**（同一份调用关系两个来源） | 该能力**仍可经 agent 工具面使用**（28 个工具里含 `index query`）—— 判定不接 GUI ≠ 判定不接能力；⚠ 批 Z 曾把它说成「新维度」，**批 AA 已实测更正并撤回** |
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
| 200 | **对齐的是 mac 的「活代码」，不是它的死代码** | 台账 D.1 原说「mac 有两套映射：`StatusColor.systemColor` 与 `DSColor.color(DSStatus)`」—— 实测 `StatusColor.systemColor` 在整个 mac 仓**零调用**，是死代码。⇒ deepin 的 stale 红**对标的是一段没人用的代码**；mac 真正在用的是 `DSColor.color(DSStatus)`（`Components.swift:18` 状态点 / `DetailViews.swift:667` 分支行） | 台账失真已修（决策 199 是同一条纪律的又一次应用）；对齐对象选错 = 整个批次白做 |
| 201 | **UI 层按 mac 的「语义分档」对齐，不是按「色值」对齐** | mac 的橙/红/黄/灰是 **SwiftUI 系统色**（随系统外观/强调色变），Linux/DDE 侧**物理上不存在对应物**；能对齐的只有「哪一档该是警示色、哪一档该是静默色」。mac 的绿/紫/青/蓝来自设计稿 `DSPalette`，**已与 deepin 同值**（`#10B981` / `#8B5CF6` / `#06B6D4`） | deepin 保留自己的 tailwind 固定色 —— 这是**必然**不是欠账；系统色那套搬不动也不该搬 |
| 202 | **陈旧红 `#EF4444` 改为托盘专用档；判定层（UI 层语义）一律不挂** | 它与危险红 `#DC2626` **肉眼几乎分不出**，UI 层同时出现两个红 = 读者分不出谁是谁。⇒ UI 层只留一档红（读不出来 / 危险） | **托盘仍用陈旧红** —— 托盘图标无文字，形状只分「告警三角 / 普通环形」两档，`notGit` 与 `quiet` 之间**没有形状差别**，颜色是它区分档位的**唯一手段**。分界是「**颜色是不是唯一信号**」，不是「哪个界面」 |
| 203 | **「静默」与「不适用」归灰，「读不出来」归红** | 停滞/久未更新是**静默**不是坏了；非 git 目录是**不适用**（且紫已被「深更新轨 / 已合并」占用，notGit 用紫会误读）；读不出来是真有问题，不该装成「不活跃」的灰 | deepin 的状态点**带 tooltip 文字**、多处 UI 还有状态词 —— 颜色只做辅助，压档**不丢信息**（mac 同样如此） |
| 204 | **面板快照对状态色是「空门」** —— 补拍状态色样张 | 4 页面板快照拍的是**空态**（本机引擎注册项目数 0，快照里只有「仪表盘还没有数据」），**状态点一个都没画进去** ⇒ 改状态色它不红，说「视觉已评审」是假的。**空门比没门更糟**（给虚假安全感） | 多拍两张色卡（900×720，16 行）；纳入 CI 截图矩阵，改色 ⇒ 色卡 diff 红 |
| 205 | **档位清单单一真相源**（`Derived::livenessKinds()` / `branchStatusKinds()`） | 样张按清单画、判据按清单断言 ⇒ 加一档 `Liveness` 自动多画一格，**不会漏画**（漏画 = 基线里没有那一格 = 又一个空门） | 清单必须是**引擎真实产出**的档 —— 引擎 `computeBranchStatus` 只有 5 档，**没有 `dirty`**（mac 的 `.dirty`→红是死路径）。列出引擎不产出的档 = 永远画不出来的一格 |
| 206 | **门项正则一律带 token 边界**（本批给 **171 条**门项追加 `\b`） | 负控实测：`--color-sample` 被改成 `--color-sampleX` 后，子串正则**照样匹配** ⇒ 门是假的（**第十二次**「子串互相顶替」）。通用规则：正则尾部是词字符就加 `\b` | ⚠ **规则有反例**：尾部是**前缀形态**时不能加 `\b` —— `QColor\(0x` 的 `x` 后面紧跟十六进制数字（两边都是词字符 ⇒ 无词边界），加了 `\b` 门反而**抓不住**。6 条门因此被改坏，已改成 `QColor\(0[xX][0-9A-Fa-f]`（盯 hex **首字符**）。⚠ **引号形式必须统一用单引号** —— 批量加固按形式分派，双引号那批会被漏掉（门脚本里两种写法混用 = 「形式互相顶替」的又一次变体）；已加自检门项禁止混用 |
| 207 | **深色色卡与浅色色卡都进基线** | 状态色是**固定色**（不随主题改写），但**表面/文字色**随主题变 —— 两张都要拍，否则暗色下的对比度问题看不见 | 快照文件从 6 张（+2 setupguide）增到 8 张 |
| 208 | **deb 的依赖清单是唯一出处，且构建时与二进制实际依赖**双向**核对** | Depends 写错 = 装不上（包名不存在）；漏声明 = 装上跑不起来；漏 DTK 的两个插件包更隐蔽 —— `dde-qt6integration` 缺了 → chameleon 样式加载失败 → 控件**静默退回「纯 Qt 感」**（白底白字那类），不报错、只是不像 deepin 应用。⇒ `scripts/deb-deps.txt` 是唯一出处，`build-deb.sh` 拿 `readelf -d` 的 `DT_NEEDED` 逐条反查包名，与清单**双向比对**，差集非空即构建失败 | 包名随发行版版本变（实测于本机 UOS）—— 脚本每次构建都重新核对，换发行版只需改这一份清单 |
| 209 | **刻意不声明 `qt6-wayland`** | Wayland 分支（M1-8）**未做、未验证** —— 声明它等于承诺「Wayland 下可用」，那是虚假承诺（与决策 68「写一条注定失败的自启项比不给选项更糟」同一逻辑） | Wayland 用户装上可能起不来 —— 已在依赖清单里写明原因 |
| 210 | **D7 的核心是「装后零环境变量」—— 实测发现 M2-8 其实早就达标** | README 原写「运行库在 sysroot 里，环境变量缺一不可」「裸环境 `ldd` 报 not found」—— **实测不成立**：宿主 `/lib/x86_64-linux-gnu` 本来就有 `libdtk6widget.so.6` / `libQt6Widgets.so.6`，插件目录里也有 `libchameleon.so`（DTK 样式）与 `libdxcb.so`（DTK 平台插件）。二进制**无 RPATH**、`DT_NEEDED` 全是 soname ⇒ 换台机器只要系统有这些库就能跑 | 文档失真已修。顺带查出**此前所有「视觉零变化」的结论仍然有效**：裸环境与带 sysroot 环境拍出的快照**逐像素 0 差异**（两种环境观感相同）。sysroot 是**编译期**装 dev 头文件用的，不是运行期依赖 |
| 211 | **面板快照基线必须走固定夹具，不走真引擎** | 真引擎取数让基线取决于「本机注册了什么项目」⇒ 同一份代码在不同机器上拍出不同的图；且本机注册 0 个项目时拍的是**空态** ⇒ 面板快照对状态色/布局/排版全是**空门**（改界面它不红，说「视觉已评审」是假的）。**空门比没门更糟** —— 给的是虚假安全感 | 夹具是**编的**数据（7 个虚构项目）—— 真实项目长什么样基线不承诺；它承诺的是「这一屏长这样」 |
| 212 | **夹具走同一段解析路径**（`applyStatusPayload` / `applyDashboardPayload` / `applyMilestonesPayload`） | 夹具若自己造模型对象，就**测不到契约解析** ⇒ 契约坏了基线不红。取数与判定**分层**：夹具与引擎共用解析层，判定层仍是纯数据（零 UI 头） | 无 |
| 213 | **夹具的时间戳分两类**：会被算天数的跟真实 now 走，只会被显示成绝对字符串的锚定固定基准日 | ① `lastCommitAt` 写死 ⇒「N 天没更新」的 N 每天变 ⇒ 基线天天漂；② `targetDate` 跟「今天」走 ⇒ UTC 午夜一过基线就变 ⇒ 同样天天漂。**两类都要真**才算对：① 不跟真实 now 走，liveness 的天数判定就跟生产不是一回事；② 夹具里的日期本来就是编的，锚到基准日反而更诚实 | 夹具的「今天」是 **2026-01-15**（故事基准日），与真实今天无关 —— 看基线时别把它当今天 |
| 214 | **基线必须逐字节可重现**：刷新时刻固定 + 快照进程固定 `TZ=UTC` | 侧栏「上次刷新 HH:mm」是 epoch 的**本地时区**渲染 ⇒ 用墙钟就每分钟变一次、换台机器（时区不同）也变 ⇒ CI 天天有 diff ⇒ 人就学会忽略 diff ⇒ 基线退化成空门 | 快照进程固定 TZ=UTC **只影响无头快照路径** —— 正常桌面会话仍用用户本地时区 |
| 215 | **CI 加「重拍比字节」门**（连拍两次 + 换时区再拍一次） | 门要盯**行为**（同一份代码两次拍出同一张图），不是「我改的这两个文件看着对」—— 将来谁往渲染路径里塞了墙钟，它就红 | ⚠ 墙钟只有**分钟精度** ⇒ 同一分钟内的漂移抓不到 ⇒ 那一格由**接线门盯具体那一行**（`m_lastRefreshedMs = SnapshotFixture::fixedRefreshedMs()`）兜底 |
| 216 | **拍到空态 = 响亮失败**（退出码 1 + 删掉那张空图） | 夹具没生效 / 被改坏 ⇒ 画面是空的 ⇒ 提交进去的基线又变成空门。**宁可构建失败，也不能把空图固化成基线** | 无 |
| 217 | **夹具内部必须自洽**（同一批里程碑只写一份文本；计数必须与条目对得上） | 之前 dashboard 与 milestone list 各写一份里程碑 ⇒ 同一件事两套说法（cygnus 的目标日期一边有一边空）；`counts` 写 `open:2` 而条目只有 1 条 open ⇒ 侧栏「里程碑 ●3」与列表里的「2 个未完成」打架 ⇒ **基线把矛盾固化了** | 无 |
| 218 | **图标逻辑名用 `enum class Id`，不用字符串** | 字符串拼错是**编译期发现不了**的运行时事故 —— 图标空掉，界面还「看着没事」。用枚举 ⇒ 拼错**编译不过**；漏登记候选链 ⇒ 判据红（候选表与枚举必须严格一一对应） | 逻辑名 ↔ 候选名的映射仍在判定层（`logic/IconNames`），枚举只是它的入口形式 |
| 219 | **图标取用只有一个入口**（`platform::icon()`），候选链在判定层 | 之前图标名散在 **11 处** UI 代码里（`QIcon::fromTheme("list-add")` 这种）：换主题名要改 11 个地方；某个名字在主题里解析不到时，界面**静默变成空图标**，没人知道是哪个名字没的 | 候选链的**第一个候选 = 今天在用的主题名** ⇒ 视觉不变（链是「多几条路」，不是「换个图标」） |
| 220 | **图标解析顺序：DDci → 主题 → qrc 染色 → 缺失告警 + 占位** | deepin 自己的图标集（DDci）观感最好 ⇒ 优先；freedesktop 主题次之；`dd-*` 的 currentColor SVG 作免安装兜底（需 Qt6Svg，本构建环境无 ⇒ 整段编译不进） | 本机实测（bloom 主题）：27 个逻辑图标 **8 个走 DDci / 19 个走主题 / 0 个解析不到** |
| 221 | **「这台机器没有图标主题」是环境事实，不算缺失** | `QIcon::themeName()` 为空（offscreen 就是）⇒ 解析不到**不是图标名错了**。此时既不逐个告警（否则日志被刷屏），也**不画占位圆点** —— 圆点会把离屏基线污染成「到处都是圆点」，反而看不出真问题 | 无图标主题的环境里，界面上的图标位是空的（与旧行为一致）；有主题但某个名字解析不到时 ⇒ **告警 + 占位圆点**（我们的问题，必须显形） |
| 222 | **删掉零调用点的 `IconLoader`（170 行死代码）** | 实测 `IconLoader::` **零调用点**（托盘只 include 了头文件，从没用过它）；qrc 里的 `dd-*.svg` / `deepdolphin.svg` 只被它消费 ⇒ 那些资源其实**从来没被用上**。⇒ 收编进 `platform::icon()`，死代码删除 | ⚠ PLAN M2-6 写的「托盘/菜单不再出现手绘占位方块」是**失真**：托盘至今仍是手绘，菜单图标也还没用上 dd-*。已照实记进批 U 日志 |
| 223 | **平台差异分两层：判定层 `logic/Backend`（纯结论）+ 平台层 `platform/Backend`（执行）** | `--selfcheck` 跑在 `QGuiApplication` 构造**之前**（main.cpp 无头分支）⇒ 落点算法、激活动作计划这类**结论**必须能在无应用对象时算出来（放判定层）；真碰 `QWidget`/`QScreen` 的**动作**放平台层。⇒ 结论可离线测（判据），动作靠探针 + 接线门（可见面） | 同一件事要跨两个文件看；平台层那部分**判据落不到**（要应用对象） |
| 224 | **窗口激活只走 `platform::activate()` 一个入口**（8 处散落的 `show/raise/activateWindow` 收编） | 8 处各写一遍 ⇒ 修一处只修一处（8 个窗各叫各的）；而且**全都叫不醒最小化的窗口**（实测 `show()` **不恢复**最小化态）⇒ 面板被最小化后从托盘点「打开面板」，**点了跟没点一样** | 无（调用点从 3 行变 1 行）；新增的 `platform/Backend.cpp` 要登记进构建 |
| 225 | **恢复最小化只摘最小化位，**不用 `showNormal()`** | 实测 `showNormal()` 会**顺带清掉最大化位**（`WindowMaximized` → `WindowNoState`）⇒ 用户把面板最大化着，从托盘叫醒时会被**打回普通大小**。⇒ 只 `setWindowState(state & ~Qt::WindowMinimized)` | 多一行 `setWindowState` 代码；`~Qt::WindowMinimized` 的用法不常见（要在注释里说清为什么） |
| 226 | **Wayland 分支不调 `raise()`** | Wayland 上 `raise()` 是**空操作**（叠放次序由合成器说了算）—— 调它没坏处，但会**误导**：让人以为叠放次序被管了。⇒ Wayland 改走 `windowHandle()->requestActivate()` | Wayland 上叠放次序**不由我们决定**（M1-8 再说）；X11 行为不变 |
| 227 | **托盘弹窗落点：四边都夹，且边距只在越界时生效** | 旧实现只夹**下边与左边** ⇒ 托盘在屏幕**右上角**（DDE 顶栏的托盘就在那儿）时弹窗右边缘 = 图标右边缘 + `dockGap` ⇒ **溢出屏幕右边**；弹窗比可用区还高时**顶部溢出**（标题栏被切掉）。而边距若改成「无条件保持」，弹窗会被从托盘图标底下推下来十几像素 —— 那是「离屏幕边留白」被误当成「离图标留白」 | 落点判定多两个分支；**兜底落点（托盘几何不可用 ⇒ 屏幕右上）与旧实现逐字一致**（行为不变，只补了越界那两条边） |
| 228 | **弹窗定位的四个数值只有托盘域一个出处**（`TrayGeometry::popupGeometry()`） | 判定层只管「拿到这组数之后怎么落」，**不拥有数值** —— 两处各写一份，改一处忘另一处就是「弹窗贴着屏幕边」这种没人说得清来源的毛病。判定层的 `PopupGeometry` 默认值全 0（= 调用方没给），真实值由托盘域 token 打包 | 判定层入参是个结构体，调用方要打包一次 |
| 229 | **任务栏几何先做成只读事实（探针可见），M1-8 才当输入用** | X11/DDE 下 `availableGeometry()` 已扣掉面板；Wayland 下 QPA **未必**扣 ⇒ 这行正是 M1-8 接 `org.deepin.dde.Panel` 的输入口。现在先让它**看得见**（探针报 `taskbarInsets=l,t,r,b`），别等要用时才发现没这份数据 | 现在只是读出，没有消费者去**用**它（探针是消费者）；Wayland 侧仍要等 M1-8 |
| 230 | **后端分档带 token 边界**（`wayland` / `wayland-egl` 命中，`mywayland` / `xwayland` **不**命中） | 朴素前缀比较会把 `mywayland` 也判成 Wayland ⇒ 走错激活动作分支（Wayland 分支不调 `raise`）。这是「子串互相顶替」在**协议名**上的同款形态（累计第 17 次） | 无 |
| 231 | **面板几何的真值源 = 面板自己报（D-Bus），不是 QPA 推算** | 批 V 的任务栏边距是「QPA 可用区与整屏的差值」——**推算**的。Wayland 下 QPA **未必**扣面板 ⇒ 推算值在 Wayland 上可能是错的。而 DDE 面板**自己**报 `geometry`（QRect）与 `position`（在哪条边）⇒ 不用猜。实测：面板报 (0,1039,1920,41)/bottom，与 QPA 推算出的边距 **0,0,0,41** **完全吻合**（两套独立来源对上了） | 多一条 D-Bus 依赖；服务不在时自动退回报缺，**不影响非 DDE 桌面**（实测服务不存在时**立刻**返回错误，不等超时） |
| 232 | **PLAN 里写的 `org.deepin.dde.Panel` 不存在 —— 真实接口是 `org.deepin.ds.Dock`（新）/ `org.deepin.dde.Dock1`（旧）的 `org.deepin.dde.Dock1` 接口** | 实测本机会话总线上 `org.deepin.ds.Dock`、`org.deepin.dde.Dock1`、`org.deepin.dde.daemon.Dock1` **三个都在**，Introspect 出 `geometry`（`(iiii)`，只读）、`position`（`i`：0上 1右 2下 3左，**只有新服务有**）、`showInPrimary`（`b`）；而 `org.deepin.dde.Panel` **没有任何服务**。⇒ PLAN §9 M1-8 的描述按实际接口改写（照实记，不假装原计划能直接做） | 三个服务名都要试（新服务才带 `position`）；旧服务只有 `geometry` ⇒ 位置读不到时按几何猜边 |
| 233 | **D-Bus 属性读必须带超时**（`QDBusConnection::call(..., QDBus::Block, 2000)`），**不用** `QDBusInterface::property()` | `property()` **没有超时参数** ⇒ 面板服务卡住时会把 GUI 线程一起卡住（最深 25s）。带超时的 `call` 在服务**不存在**时实测**立刻**返回错误 ⇒ 非 DDE 桌面零成本 | `Get` 的回包裹在 `QDBusVariant` 里 ⇒ 要多拆一层；位置与矩形要分两次读 |
| 234 | **D-Bus 的 `(iiii)` 只能用 `qdbus_cast<QRect>` 解档，裸 `arg >> int` 会 abort** | 存进 QVariant 的 `QDBusArgument` **丢掉了类型上下文**（它带着「当前类型」，而那个上下文在变体里存不住）⇒ 裸拆会走进 libdbus 的「type struct 114 not a basic type」并 **abort**。**本批实测崩过一次**（探针直接 SIGABRT）⇒ `qdbus_cast` 走**注册过的类型解档器**（QRect 的布局它知道） | 需要 `qDBusRegisterMetaType<QRect>()` 注册一次 |
| 235 | **面板读放 worker 线程 + 缓存**（交互路径不阻塞 GUI） | D-Bus 的属性读是**同步往返**。放在「用户点托盘」那一刻读，面板服务卡住就卡 GUI（最深 2s 冻结）。⇒ 启动时异步读一次，结果回 GUI 线程存缓存 | 弹窗用的是**上一次**读到的值 ⇒ 面板挪边后**第一次**弹可能偏（低频动作，可接受）；缓存只写在 GUI 线程 ⇒ 无需加锁 |
| 236 | **托盘弹窗落点按面板位置定**：面板在下 ⇒ 弹窗在面板**上方**、右对齐 | DDE 的系统托盘是 **SNI**（宿主是 `org.deepin.dde.TrayManager1`）⇒ `QSystemTrayIcon::geometry()` **恒为无效矩形** ⇒ 托盘坐标**一直**拿不到（不是边角情况，是常态）⇒ 旧实现只能瞎猜「屏幕右上」。而托盘在**底部**任务栏里（DDE 默认布局，position=2）⇒ 弹窗落在**离托盘图标很远**的屏幕右上角。实测：旧落点 (1523,32) ⇒ 新落点 (1524,731)（面板正上方） | 多一个面板分支；**读不到面板时退回旧行为（一字未改）** |
| 237 | **弹窗失焦收起加应用级兜底**（`applicationStateChanged`），且**只在转成 Inactive 时**收起 | Wayland 上失焦事件可能**不送达**（合成器不给 focus 变化）⇒ 弹窗赖在屏幕上不走。应用级失焦是一定会来的信号 ⇒ 用它兜底。⚠ 判据：只在**转成 Inactive** 时收起 ⇒ 弹窗刚弹出、应用还没被激活时**不会**被误收起 | ⚠ **已知局限**：若应用从未被激活（Wayland 下 `requestActivate` 失败），应用级状态**没有变化** ⇒ 兜底不触发（仍靠 `WindowDeactivate` 或用户点到别处） |
| 238 | **托盘图标画圆必须用 `QRect` 重载**：`drawEllipse(qreal,qreal,qreal,qreal)` 的**前两参是圆心**不是左上角 ⇒ 旧写法把圆画到画布外 ⇒ **托盘图标一直是空白** | 测**中心与环上两个像素**（不是眼睛看图：圆心语义与画到画布外，肉眼分不出）；实测旧写法中心 `0x00000000`、改后中心 `ffffffff`、环上 `f3959ba7` | ⚠ **与桌面无关** ⇒ mac/Linux 托盘图标此前**一直是空白**；门项盯「**两处**都是 QRect」（只盯「至少一处」的话，改坏其中一处门照样绿） |
| 239 | **像素编码必须先转非预乘 ARGB32 再按 `pixel()` 取 0xAARRGGBB** | `QIcon::pixmap().toImage()` 是**预乘**格式（`Format_ARGB32_Premultiplied`），按非预乘去解释**读出来的不是那个颜色** ⇒ 半透明图标**颜色全错**（而长度不变 ⇒ 肉眼看图只觉得「颜色怪」，发现不了是协议层错了）⇒ 先 `convertToFormat(Format_ARGB32)` 再取值，**不依赖平台字节序** | 判据用**非对称**夹具（四通道互不相等）且**预乘/非预乘两种源格式都测**（只测非预乘的话，这个错法分叉不出来）；⚠ 夹具必须用 `QPainter` 造 —— `QImage::setPixel` 往预乘图里写的是**未预乘**数值 |
| 240 | **判据分层：字节级判据只能放真机端到端探针**（`scripts/probe-sni-icon.sh`） | `--selfcheck` 跑在 QApplication 构造**之前** ⇒ 没有总线；且 `QDBusArgument` 一旦写入就是**只写**的（「read from a write-only object」）⇒ 同一份数据在进程内**读不回来** ⇒ 放 selfcheck 里只会得到一个「永远红/永远绿」的假判据 ⇒ 判据必须**从总线另一端**（外部进程 `gdbus`）读 `IconPixmap` | 探针统计**整张图**的非零字节（只看开头几行会误判：圆形图标**边缘像素本来就是透明的** —— 批 X 据此误判过一次「整张全 0」）；另外**接线门脚本必须以门的结果退出**（批 X 照出：门项打 ✗ 但脚本退出码仍是 0 ⇒ 这一门在 CI 里形同虚设） |

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
**判定不接 GUI**：`index query` 与已接的 `graph functions`（关系页签在用）**同维度**
（两边给的都是函数级调用边 + 边的确信度档位 `tier`；⚠ 批 AA 实测复核：批 Z 说
「`graph functions` 没有 tier」是**错的** —— 实测 5274 条边**每条都带 `tier`），
接它会造出第二个真相源；仍可经 agent 工具面使用。
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

### 批 R：跨端状态色取值对齐 —— 对齐 mac 活代码，并补上视觉基线的空门

决策见上表 **200–207**（对齐活代码而非死代码 / 按语义分档而非色值对齐 /
陈旧红改托盘专用 / 静默与不适用归灰、读不出来归红 / 面板快照是空门 →
补拍状态色样张 / 档位清单单一真相源 / 门项正则一律带 token 边界 / 深浅两张色卡都进基线）。

**这一批的起点是台账 D.1 的一处失真**：原文说「mac 有两套映射：`StatusColor.systemColor`
与 `DSColor.color(DSStatus)`」。逐点核对后发现 —— **`StatusColor.systemColor` 在整个 mac 仓
零调用，是死代码**。也就是说 deepin 的 stale 红**对标的是一段没人用的代码**；
mac 真正在用的那套是 `DSColor.color(DSStatus)`（stale 落**橙**）。
真正在 mac 里分叉的不是「`StatusColor` vs `DSColor`」，而是 **Liveness 层的三处副本**
（`BoardView` / `DashboardParts` / `DetailViews` 各写一遍，且 `notGit` 在 `DetailViews`
用 `.gray`、另两处用 `.secondary` —— mac 自己的第二套口径）。台账 D.1 已照实重写。

**改了什么**（`logic/Derived.cpp` + `logic/SemColors.h`）：

| 语义档 | 改前 | 改后 |
| --- | --- | --- |
| 分支 `stale` | 陈旧红 `#EF4444` | **橙 `#F59E0B`** |
| Liveness `engineStale` / `quiet` | 陈旧红 `#EF4444` | **灰 `#9CA3AF`** |
| Liveness `notGit` | 紫 `#8B5CF6` | **灰 `#9CA3AF`** |
| Liveness `unknown` | 灰 `#9CA3AF` | **红 `#DC2626`** |

**陈旧红 `#EF4444` 改为托盘专用档**（判定层不再挂它，UI 层只留一档红）——
它与危险红 `#DC2626` 肉眼几乎分不出，UI 层同时出现两个红 = 读者分不出谁是谁。
**但托盘不参与压档**：托盘图标无文字，形状只分「告警三角 / 普通环形」两档，
`notGit` 与 `quiet` 之间没有形状差别 ⇒ 颜色是托盘区分档位的唯一手段。
分界是「**颜色是不是唯一信号**」，不是「哪个界面」。

**顺带照出基线的一个盲区（重要）**：4 页面板快照拍的是**空态** —— 本机引擎注册项目数 0，
快照里只有「仪表盘还没有数据」，**状态点一个都没画进去**。⇒ **面板快照对状态色是空门**：
改状态色它不红，说「视觉已评审」是假的（**空门比没门更糟** —— 给虚假安全感）。
⇒ 新增**状态色样张**（`ui/ColorSampleSheet` + 无头入口 `--color-sample`），
把 liveness 7 档 + 分支状态 5 档 + 托盘专用档 + 固定色**每一档都画出来**（900×720，16 行），
纳入 CI 截图矩阵（`light-colors.png` / `dark-colors.png`）—— 改色 ⇒ 色卡 diff 红。
样张颜色**全部走判定层**（接线门钉住），判定层改色它自动跟着变。

**档位清单单一真相源**：判定层导出 `Derived::livenessKinds()`（7 档）与
`Derived::branchStatusKinds()`（5 档，与引擎 `computeBranchStatus` 的产出**严格相等**）。
样张按清单画、判据按清单断言 ⇒ 加一档 `Liveness` 自动多画一格，**不会漏画**
（漏画 = 基线里没有那一格 = 又一个空门）。

**门项加固**：负控实测抓出 `--color-sample` 被改成 `--color-sampleX` 后子串正则照样匹配
（**第十二次**「子串互相顶替」）⇒ 本批给 **171 条**门项的正则追加词边界 `\b`
（通用规则：正则尾部是词字符就加）。`\b` 不改变门的语义，只堵住「加后缀逃逸」这一整类。

⚠ **这条规则有两个反例，本批都踩了**（都记在决策 206）：
① **尾部是前缀形态的不能加 `\b`** —— `QColor\(0x` 的 `x` 后面紧跟十六进制数字，
两边都是词字符 ⇒ 没有词边界，加了 `\b` 门反而**抓不住**（6 条门被改坏，
已改成 `QColor\(0[xX][0-9A-Fa-f]` 盯 hex 首字符）。
② **引号形式必须统一用单引号** —— 批量加固按形式分派，**双引号那一批会被漏掉**
（同一个门脚本里两种写法混用 = 「形式互相顶替」的又一次变体）；
已加自检门项禁止混用。

**本批验证**（全部实跑）：`--selfcheck` **269 通过 0 失败**（267 → 269，+2 例：
「陈旧红是托盘专用档」「档位清单齐全」）；`ci-wiring.sh` **250 项**（242 → 250，+8 项）；
`ci-d2.sh` **0/0**；`contract-check.sh` **109/109**（不变，本批不碰引擎契约）；
`ci.sh` **10/10 门全绿**。

**视觉变化**：4 页面板快照**零变化**（基线是空态，状态点没画进去 —— 这正是空门本身）；
**新增两张色卡**（浅/深），是本批唯一落到基线上的像素变化。

### 批 S：deb 打包 —— D7 达分的必经（顺带查出 M2-8 其实早就达标）

决策见上表 **208–210**（依赖清单唯一出处 + 与二进制实际依赖双向核对 /
刻意不声明 `qt6-wayland` / D7 的核心是「装后零环境变量」，实测 M2-8 早就达标）。

**做了什么**：新增 `scripts/build-deb.sh` + `scripts/deb-deps.txt`（依赖清单唯一出处），
产出 `build/deb/cn.deepdolphin.app_<版本>_amd64.deb`；接入 CI 作为**第 11 门**
（PLAN §CI 流程早就列了「⑥ deb 构建」，这一门此前根本不存在 ⇒「能不能出包装进 deepin」
从没被验证过）。包内容：二进制 / desktop / D-Bus service / hicolor 多尺寸图标 + symbolic 图标 /
metainfo / `control` / `postinst`（DBus 激活环境）。版本号取 **CMakeLists 的 `project(VERSION …)`**
（单一真相源，不手抄）。

**依赖清单与二进制实际依赖双向核对**（本批的核心，不是「写个 Depends 就完」）：
`readelf -d` 读出 15 个 `DT_NEEDED` → `ldconfig` 定位真实路径 → `dpkg -S` 反查包名 →
与清单**双向求差集**：清单缺项（装上跑不起来）/ 多项（包名不存在装不上）**一律构建失败**。
⇒「加了新依赖忘改清单」在这一步就红，而不是等用户装完才发现。
⚠ 漏声明 DTK 的两个插件包最隐蔽：`dde-qt6integration`（chameleon 样式）缺了 →
控件**静默退回「纯 Qt 感」**，不报错、只是不像 deepin 应用。

**顺带查出一处 README 失真并修掉**：原文说「Qt6/DTK6 运行库在 sysroot 里，环境变量缺一不可」、
「裸环境 `ldd` 报 not found」—— **实测不成立**：宿主 `/lib/x86_64-linux-gnu` 本来就有
`libdtk6widget.so.6` / `libQt6Widgets.so.6`，插件目录里也有 `libchameleon.so`（DTK 样式）
与 `libdxcb.so`（DTK 平台插件）。二进制**无 RPATH/RUNPATH**、`DT_NEEDED` 全是 soname
⇒ sysroot 是**编译期**装 dev 头文件用的，不是运行期依赖。
⇒ **M2-8 实测早就达标**，台账状态从 ⬜ 改成 ✅。
⚠ 顺带确认：**此前所有「视觉零变化」的结论仍然有效** —— 裸环境与带 sysroot 环境拍出的
快照**逐像素 0 差异**（两种环境观感相同，此前担心的「基线在两种观感之间漂移」不成立）。

**本批验证**（全部实跑）：`--selfcheck` **269 通过 0 失败**（不变）；`ci-wiring.sh`
**257 项**（251 → 257，+6 项）；`ci.sh` **11/11 门全绿**（10 → 11，新增 deb 门）；
**负控 10 处全部真红**（打包脚本 5 + 接线门 5）；
**deb 产物实测**：解包后 `ldd` **0 个 not found**、裸环境 `--selfcheck` **269/0** 通过、
快照能拍出 ⇒「装出来的样子能跑」成立。

**本批踩到的两个坑（都是「门太松」的老毛病，第 13 次）**：
① `strip_comments` **不剥 `.txt` 的 `#` 注释** ⇒ 依赖清单**注释里提到的包名**顶替了真条目，
「清单里有 `dde-qt6integration`」在真条目被删后照样绿 ⇒ `.txt` 也归到「剥 `#` 注释」那一支。
② `not found` 在脚本里出现**两次**（调用 + die 消息）⇒ 只改调用那行时「出现过」照样绿
⇒ 门项改成盯**具体那一行调用**（`grep -c .not found\b`）。

**未完成**：真机 clean deepin 25 容器的 `dpkg-deb -b` + 安装 + 启动（**本机无 docker/podman**）
—— D7 的最终验收仍待真机，本批只做到「本机可复现的等价验证」。

### 批 T：面板快照基线补真实内容 —— 并把基线变成**逐字节可重现**的门

决策见上表 **211–217**（快照走固定夹具 / 夹具走同一段解析路径 / 时间戳分两类 /
基线逐字节可重现 / CI 加「重拍比字节」门 / 拍到空态响亮失败 / 夹具内部必须自洽）。

**做了什么**：新增判定层 `src/logic/SnapshotFixture.{h,cpp}`（纯数据、零 UI 头），
产出 status / dashboard / milestones 三份载荷；`AppModel` 抽出「载荷应用」层
（`applyStatusPayload` / `applyDashboardPayload` / `applyMilestonesPayload`），
**引擎与夹具共用同一段解析**；`--snapshot` 改走夹具（不再 `model.start()`），
`panel.show()` 之后同步喂 ⇒ UI 一定收到信号再拍。

**基线从空态变成有内容**（这是本批的起点问题）：此前 4 页面板快照拍的是**空态**
（本机引擎注册项目数 0，画面上只有「仪表盘还没有数据」，**状态点一个都没画进去**）
⇒ 面板快照对状态色/布局/排版全是**空门** —— 改界面它不红，说「视觉已评审」是假的。
批 T 之后基线里有 **7 个项目**（一档一个 Liveness：绿/橙/灰/灰/红/灰/红）、
**分支状态 5 档**、**里程碑 4 态**（进行中/已达成/已放弃/无法核验）。

**顺带修掉一个真缺陷**：`ProjectProgressCard.cpp` 里
`QStringLiteral("%1 ×%2").arg(QString, int)` 命中了 Qt 的 **arg(a1, fieldWidth) 重载**
（int → qsizetype 是标准转换，比 int → QString 更匹配）⇒ 第二个占位符**原样留在界面上**。
⇒ 提交构成的图例**一直显示「feat ×%2」**，从来没显示过数量。改为链式 `.arg(a).arg(b)`；
全仓排查确认**只此一处**。

**基线必须逐字节可重现**（本批真正的硬骨头）：基线一旦带墙钟，
CI **每次**都出 diff ⇒ 人就学会忽略 diff ⇒ 基线退化成空门（**比没门更糟**）。
墙钟有两处出口，各钉一处：
① 侧栏「空闲 · 上次刷新 HH:mm」= epoch 的**本地时区**渲染 ⇒ 固定刷新时刻
（`SnapshotFixture::fixedRefreshedMs()`）+ 快照进程内固定 `TZ=UTC`；
② 里程碑「目标 YYYY-MM-DD」= 绝对日期 ⇒ 锚定固定**故事基准日 2026-01-15**。
⚠ 夹具的时间戳**分两类**：会被 `Derived::daysSinceLastCommit` 算天数的 `lastCommitAt`
**必须跟真实 now 走**（写死的话「40 天没更新」的 N 每天变 ⇒ 基线天天漂）；
只会被显示成绝对字符串的（`targetDate` / `headDate` / `updatedAt` / `fetchedAt`）
**必须锚定基准日**（跟着「今天」走 ⇒ UTC 午夜一过基线就变）。

**新增 CI 门「重拍比字节」**：拍两张比字节（同一份代码两次拍必须一模一样），
再换**另一个时区**拍第三张比字节（抓「渲染跟着宿主时区走」）。
⚠ 对比的必须是**两个互相不同**的时区（UTC 与 America/New_York）——
拿「宿主时区」当其中一个时，宿主恰好就是那个时区（实测本机就是 Asia/Shanghai）
⇒ 两张必然相同 ⇒ 门永远绿 ⇒ 又一个空门。

**本批验证**（全部实跑）：`--selfcheck` **282 通过 0 失败**（276 → 282，+6 例）；
`ci-wiring.sh` **275 项**（265 → 275，+10 项）；`ci.sh` **11/11 门全绿**；
`contract-check.sh` **109/109**；D2 **0/0**；
**负控 20 处全部真红**（判据 10 + 接线门 9 + 行为门 1）。
**基线实测**：10 张快照（6 面板 + 2 色卡 + 2 setupguide）**重拍后字节完全一致**；
三个时区（UTC / +08 / −05）拍出的快照**字节完全相同**。

**负控抓出并已修的三处「门太松」（第十五次同类问题）**：
① 「天数恒定」判据**只看第一个 quiet 项目** ⇒ 把**别的**项目（cygnus）的 40 天改成 41 天
它照样绿，而界面上「41 天前提交」已经变了 ⇒ 判据改为**逐个项目钉死**
（0/0/40/40，其余三个读不出来且**不许回落成 0 天**）；
② ci.sh 里 `cmp -s` 出现**两处**（比基线 / 比换时区那张）⇒ 只拿掉一处时「出现过」照样绿
⇒ 门项改**精确计数**（恰好 2 处）；
③ 跨时区对比原本拿「宿主时区」当其中一个 ⇒ 宿主恰好就是 Asia/Shanghai 时
两张必然相同 ⇒ 门永远绿 ⇒ 改为 UTC 与 America/New_York 两个**互不相同**的时区。

### 批 U：M1-2 图标统一入口 —— 候选链单一出处 + DDci 优先 + 缺失看得见

决策见上表 **218–222**（逻辑名用枚举 / 图标取用只有一个入口 / DDci 优先 + 缺失告警 /
「没有图标主题」是环境事实不算缺失 / 删掉零调用点的 `IconLoader`）。

**做了什么**：新增判定层 `src/logic/IconNames.{h,cpp}`（纯数据、零 UI 依赖）——
`enum class Id`（27 个逻辑图标）→ **候选名链**（唯一出处）；
新增平台层 `src/platform/IconResolver.{h,cpp}` —— `platform::icon(IconNames::Id, size, tint)`：
**DDci 优先 → freedesktop 主题 → qrc 染色兜底 → 缺失告警 + 占位**。
**11 处**散落的 `QIcon::fromTheme("…")` 全部改走统一入口（`SidebarNav` / `WorkBar` /
`PanelWindow` / `ProjectDetailPage` / `MilestonesPage` / `SetupGuidePage` /
`DashboardFilterBar` / `DashboardPage` / `AiSettingsDialog` / `EmptyState`）。
`--platform-probe` 增报每个逻辑图标的**解析来源**（`dci` / `theme` / `qrc` / `none` / `missing`）。

**顺带查出并删掉 170 行死代码**：`src/platform/IconLoader.{h,cpp}` **零调用点**
（托盘只 include 了头文件，从没用过它）—— 连带 qrc 里的 `dd-*.svg` / `deepdolphin.svg`
其实**从来没被消费过**。⇒ 收编进 `platform::icon()`，死代码删除
（接线门加「IconLoader 不许复活」）。

**为什么用枚举而不是字符串**：字符串拼错是**编译期发现不了**的运行时事故 ——
图标空掉，界面还「看着没事」。枚举 ⇒ 拼错**编译不过**；
漏登记候选链 ⇒ 判据红（候选表与枚举必须严格一一对应）。

**「这台机器没有图标主题」是环境事实，不算缺失**（这层区分是本批的关键）：
`QIcon::themeName()` 为空（offscreen 就是）⇒ 解析不到**不是图标名错了**。
此时既不逐个告警（否则日志刷屏），也**不画占位圆点** ——
圆点会把离屏基线污染成「到处都是圆点」，反而看不出真问题。
有主题但某个名字解析不到时 ⇒ **告警 + 占位圆点**（我们的问题，必须显形）。

**本批验证**（全部实跑）：`--selfcheck` **287 通过 0 失败**（282 → 287，+5 例）；
`ci-wiring.sh` **285 项**（275 → 285，+10 项）；`ci.sh` **11/11 门全绿**；
`contract-check.sh` **109/109**；D2 **0/0**；**负控 16 处全部真红**。
**平台探针实测**（真 backend，bloom 主题）：27 个逻辑图标
**8 个走 DDci / 19 个走主题 / 0 个解析不到**；离屏（无图标主题）：27 个都报 `none`、
**0 条告警刷屏**。

**视觉变化**：**无** —— 6 张面板快照与 2 张色卡**逐字节未变**。
理由：候选链的第一个候选就是**今天在用的主题名**，且离屏环境本就取不到图标
（旧行为也是空的）；真机上的图标**从"空"变成"有"**（旧代码那 3 个在本机就不存在的名字
——`applications-engineering` / `view-tree` / `preferences-system-time` ——
一直是空图标，现在有替代候选了）。

**顺带照实修正一处失真**：PLAN M2-6 的日志写「托盘/菜单『不再手绘占位方块』」——
**托盘至今仍是手绘**（`TrayController` 用 QPainter 画），菜单图标也还没用上 `dd-*`。
那句话描述的是**计划**，不是**已发生的**；本批已把它记进台账，不再当作既成事实。

### 批 V：M1-7 平台层 —— 后端差异收口一处，顺带修掉两个真缺陷

决策见上表 **223–230**（判定层/平台层分开 / 激活只走一个入口 / 只摘最小化位 /
Wayland 不调 `raise` / 弹窗四边都夹且边距只在越界时生效 / 定位数值只有托盘域一个出处 /
任务栏几何先做成只读事实 / 分档带 token 边界）。

**做了什么**：新增判定层 `src/logic/Backend.{h,cpp}`（**纯结论、零 QWidget**）——
`enum class Kind { X11, Wayland, Other }` + `classify()`（带 token 边界）+
`activationFor()`（激活动作计划）+ `reservedInsets()`（任务栏边距）+
`placePopup()`（托盘弹窗落点）+ `trayGeometryUsable()`；
新增平台层 `src/platform/Backend.{h,cpp}`（**执行**）——
`current()` / `activate(QWidget*)` / `availableGeometryAt()` / `taskbarInsetsAt()` /
`trayIconGeometry()` / `trayPopupTarget()`。
**8 处**散落的 `show(); raise(); activateWindow();` 全部收编成**一个入口**
`platform::activate()`（面板 7 处 + 托盘弹窗 1 处）；
`TrayPopupWindow::popupNear` 的落点改走平台层（顺手删掉写死的 `1280×720` 兜底
与一行 `moveCenter` 死代码）；`--platform-probe` 增报 `backendKind=` 与
`taskbarInsets=l,t,r,b`。

**为什么判定层与平台层要分开**：`--selfcheck` 跑在 `QGuiApplication` 构造**之前**
⇒ 落点算法、激活动作计划这类**结论**必须能在无应用对象时算出来（放判定层）；
真碰 `QWidget`/`QScreen` 的**动作**放平台层。
⇒ 结论可离线测（判据），动作靠探针 + 接线门（可见面）。

**修掉一个真缺陷（实测得来的，不是推理）**：`QWidget::show()` **不恢复**最小化窗口 ——
离屏与 xcb **两种后端实测**，`show()` 之后 `windowState()` 仍带 `WindowMinimized`。
⇒ 面板被最小化后，从托盘点「打开面板」**点了跟没点一样**。
修法是**只摘最小化位**（`setWindowState(state & ~Qt::WindowMinimized)`），
**不用 `showNormal()`** —— 实测 `showNormal()` 会**顺带清掉最大化位**
（`WindowMaximized` → `WindowNoState`）⇒ 用户把面板最大化着，从托盘叫醒时会被
**打回普通大小**。

**顺带修掉托盘弹窗两处越界**：旧实现只夹**下边与左边** ⇒
① 托盘在屏幕**右上角**（DDE 顶栏的托盘就在那儿）时，弹窗右边缘 =
图标右边缘 + `dockGap` ⇒ **溢出屏幕右边**；
② 弹窗比可用区还高时**顶部溢出**（标题栏被切掉）。
⇒ 改四边都夹；而**边距只在越界时生效**（无条件留边距会把弹窗从托盘图标底下
推下来十几像素 —— 那是「离屏幕边留白」被误当成「离图标留白」）。
**兜底落点（托盘几何不可用 ⇒ 屏幕右上）与旧实现逐字一致** —— 行为不变，
只补了越界那两条边。

**本批验证**（全部实跑）：`--selfcheck` **305 通过 0 失败**（287 → 305，+18 例）；
`ci-wiring.sh` **315 项**（285 → 315，+30 项）；`ci.sh` **11/11 门全绿**；
`contract-check.sh` **109/109**；D2 **0/0**；**负控 30 处全部真红**。
**平台探针实测**：xcb 会话下 `backendKind=x11`、**任务栏占 41px**
（`taskbarInsets=0,0,0,41`）；离屏 `backendKind=other`、边距全 0。

**负控抓出并已修四处「判据与错误实现不分叉」**（第十八次同类问题）：
① token 边界的夹具只测了**朴素前缀比较也判对**的名字（`mywayland`）⇒
去掉边界照样绿 ⇒ 补 `waylandland` / `xcbfoo` 两个**分叉夹具**；
② 「托盘几何可用性」的变异把 `w>0&&h>0` 换成 `isValid()` —— 两者在 QRect 里
**语义等价**（Qt 的 `QRect` 表达不出「宽 0 但有效」的矩形）⇒ 那个变异
**抓不住任何东西** ⇒ 换成真的错误实现（`return true`）；
③ 弹窗落点只断言「不越界」⇒ 去掉「留边距那一夹」而留着「硬夹紧兜底」时照样绿
⇒ 断言加带边距 + 补「与可用区等高」用例（专盯硬夹紧兜底）；
④ 一处**期望串写错**（门红了但不是那一项）⇒ 改正期望并补一条
「托盘域外另抄一份数值」的变异。

**未完成**：**本机无 Wayland 会话** ⇒ Wayland 分支（`requestActivate` /
托盘几何无效时的落点）**无法实跑验证**；真机 DDE 桌面上的托盘弹窗观感未复核
（本批全部离屏/探针验证）。M1-8 的**输入口已就位**（`taskbarInsets` 正是
Wayland 侧接 `org.deepin.dde.Panel` 要用的那组数）。

### 批 W：M1-8 Wayland 分支 —— 面板几何真值源 + 托盘弹窗落回托盘旁边

决策见上表 **231–237**（面板几何以面板自报为准 / PLAN 写的 `org.deepin.dde.Panel`
不存在 / D-Bus 读必须带超时 / `(iiii)` 只能用 `qdbus_cast` 解档 / 面板读放 worker
线程 + 缓存 / 弹窗落点按面板位置定 / 失焦收起加应用级兜底）。

**做了什么**：新增判定层 `src/logic/PanelGeometry.{h,cpp}`（纯函数）——
`enum class Edge { Unknown, Top, Right, Bottom, Left }` + `edgeFromPosition()`
+ `usableArea()`（屏幕扣掉面板）+ `effectiveAvailable()`（QPA 可用区 × 面板真几何）；
新增取数层 `src/platform/DdePanel.{h,cpp}` —— D-Bus 读面板几何（**2s 超时**、
worker 线程读 + 缓存）；`logic/Backend::placePopup()` 增加面板参数（面板在下 ⇒
弹窗落在**面板上方**、右对齐）；`platform::trayPopupTarget()` 在托盘坐标不可用时
改用**光标所在屏**；`TrayPopupWindow` 失焦收起加 `applicationStateChanged` 兜底；
`--platform-probe` 增报 `panelService` / `panelValid` / `panelRect` / `panelEdge` /
`screenRect` / `usableRect` / `trayPopupTarget`。
**探针断言抽成独立脚本** `scripts/ci-platform-probe.sh`（与 `ci-d2.sh`/`ci-wiring.sh`
同款做法：可单独跑，负控能精确打这一门）。

**照实修正 PLAN 的一处失真**：PLAN §9 M1-8 写「`org.deepin.dde.Panel` 位置」——
**这个服务不存在**（实测本机会话总线上没有它）。真实接口是
`org.deepin.ds.Dock`（新）/ `org.deepin.dde.Dock1`（旧）的 `org.deepin.dde.Dock1`
接口，属性 `geometry`（QRect）+ `position`（边）。已按真实接口做完，并把 PLAN
那一行改成实测结论。

**修掉一个真缺陷**：DDE 的系统托盘是 **SNI**（宿主 `org.deepin.dde.TrayManager1`）
⇒ `QSystemTrayIcon::geometry()` **恒为无效矩形** ⇒ 托盘坐标**一直**拿不到
（不是边角情况，是常态）⇒ 旧实现只能瞎猜「屏幕右上」。而托盘在**底部**任务栏里
（DDE 默认布局，position=2）⇒ 弹窗落在**离托盘图标很远**的屏幕右上角。
实测：旧落点 **(1523, 32)** ⇒ 新落点 **(1524, 731)**（面板正上方）。

**两套独立来源对上了**：面板自报 `geometry = (0,1039,1920,41)` / `position = 2`（下），
QPA 推算出的任务栏边距是 `0,0,0,41` ⇒ **两套来源完全吻合** ⇒ 这条链路可信。

**本批验证**（全部实跑）：`--selfcheck` **322 通过 0 失败**（305 → 322，+17 例）；
`ci-wiring.sh` **337 项**（315 → 337，+22 项）；`ci.sh` **11/11 门全绿**；
`contract-check.sh` **109/109**；D2 **0/0**；**负控 28 处全部真红**
（判据 11 + 接线门 14 + 探针门 3）。

**本批踩到并修掉的三个坑**（都是实测撞出来的，不是推理）：
① D-Bus 的 `(iiii)` 存进 QVariant 后**丢了类型上下文** ⇒ 裸 `arg >> int` 会走
libdbus 的「type struct 114 not a basic type」并 **abort**（探针直接 SIGABRT）⇒
改用 `qdbus_cast<QRect>`（需先 `qDBusRegisterMetaType<QRect>()`）；
② `QDBusInterface::property()` **没有超时参数** ⇒ 面板服务卡住会把 GUI 线程
一起卡住（最深 25s）⇒ 改用 `QDBusConnection::call(..., QDBus::Block, 2000)`
（实测**服务不存在时立刻**返回错误 ⇒ 非 DDE 桌面零成本）；
③ 我自己写的注释**是错的** —— 原写「`setTop/setBottom` 会把另一边撑大」，
实测 Qt6 的 setter 是「设这一条边、另一边不动」（**改变**可用区大小）⇒ 注释按实测改写。

**负控抓出并已修五处**（第十九次「判据与错误实现不分叉」）：
① `setBottom` 与 `adjust` 在「面板贴着屏边」时**完全等价** ⇒ 那个变异抓不住任何
东西 ⇒ 补「**面板悬空**」的夹具（正确可用区按面板**上沿**算，不是减厚度）；
② 「位置未知时猜边」的夹具只堵住了「先命中」这种错实现，**没堵住「后命中」**
⇒ 补「通栏顶部面板」夹具，两条合起来才把两种错实现都堵住；
③ 一处变异在当前夹具下是**语义等价**的（QPA 已扣过面板时再扣一次恰好无变化）
⇒ 换成真会改结果的写法；
④ 门项盯 `applicationStateChanged` 这个**字符串** ⇒ 把守卫改成拿不到实例，
那行字还在、兜底却永远不执行 ⇒ 门加「必须用 `qobject_cast` 拿 QGuiApplication」；
⑤ 门项 `const PanelGeometry::Panel &panel` **缺 token 边界** ⇒ 改名成
`&panelIgnored` 照样匹配（子串顶替，累计第十八次）⇒ 门改盯 `&panel =`。

**未完成**：**本机无 Wayland 会话** ⇒ Wayland 侧（`requestActivate` 真机效果、
失焦事件是否真的不送达）**无法实跑验证**；真机 DDE 桌面上的弹窗观感未复核
（本批全部离屏/探针验证）。已知局限：若应用从未被激活（Wayland 下激活可能失败），
应用级状态**没有变化** ⇒ 失焦兜底不触发（仍靠 `WindowDeactivate` 或用户点到别处）。

### 批 X：M1-3 迁 SNI —— 实现做成了，**但端到端没达成**（并照实推翻批 W 的一个结论）

决策见上表 **238–240**（托盘图标画圆要用 `QRect` 重载 / 像素编码要先转非预乘 /
判据分层：字节级判据只能放真机端到端探针）。

**做了什么**：新增判定层 `src/logic/TraySni.{h,cpp}`（纯结论、零 QWidget、零 QDBus）——
`enum class Host { None, Ayatana, Kde }` + `classifyHost()`（ayatana 变体的判据是
「单参数注册 + 已注册项是属性 + ProtocolVersion 0」）+ 注册方式判定 + **必填属性表**
（三个 pixmap 是**入场券**，缺一个当场被注销）+ 像素编码（ARGB32、**网络字节序**）；
新增平台层 `src/platform/TraySni.{h,cpp}` —— `QDBusVirtualObject` 导出的最小
`org.kde.StatusNotifierItem`（手写 introspect XML + `Properties.Get/GetAll` +
`Activate/ContextMenu`）、注册到 watcher、补发 `NewIcon`/`PropertiesChanged`；
`TrayController` 改成**探到 SNI 就走 SNI、不建 `QSystemTrayIcon`**（二选一，不并存）；
`--platform-probe` 增报 `sniWatcher` / `sniHost` / `sniHostItems` / `sniError`；
新增真机端到端探针 `scripts/probe-sni-icon.sh`。

**照实推翻批 W 的一个结论**：批 W 记的是「DDE 走**旧托盘协议**，我们**没有**注册成
SNI 项」⇒ 据此把 M1-3 判成「迁 SNI 只剩保住图标颜色」。批 X 实测：
**我们能注册成 SNI 项**（watcher 的 `RegisteredStatusNotifierItems` 里有
`org.deepin.deepDolphin/StatusNotifierItem`），宿主也**确实**按标准 SNI 读了 8 个属性
（Id → Menu → IconPixmap → AttentionIconPixmap → OverlayIconPixmap → ToolTip →
IconName → IconThemePath，`dbus-monitor` 全量抓包）并订阅了变化信号 ⇒ 批 W 那条观察
**只对当时的测试程序成立**。但**端到端仍未达成**：DDE 25 托盘区画出来的是**应用自绘的
X11 窗口**（`org.deepin.dde.TrayManager1.TrayIcons` 里是两个 16×16 的窗口 id，
窗口名 = 应用名）⇒ 我们的项注册成功却**不显示**（全屏差分 0 像素，已排除鼠标光标位移）。
⇒ M1-3 的正确解法**不是**「迁 SNI」，而是**按 deepin 的托盘窗口协议注册**
（自绘 16×16 X11 窗口 + `TrayManager1.Manage`）⇒ 风险由「中」**回升为「高（路径要重做）」**。
详见 `docs/PARITY-LEDGER.md` E.1g。

**修掉两个真缺陷**（都与桌面无关 ⇒ 各平台都受益）：① `drawEllipse(qreal,qreal,qreal,qreal)`
的**前两参是圆心** ⇒ 旧写法把圆画到画布外 ⇒ **托盘图标一直是空白**（实测中心像素
`0x00000000`，改后 `ffffffff`）；② 像素编码按非预乘去读**预乘**数据（`QIcon::pixmap().toImage()`
就是 `Format_ARGB32_Premultiplied`）⇒ 半透明图标**颜色全错**（长度不变 ⇒ 肉眼看图只觉得
「颜色怪」，发现不了是协议层错了）。

**本批验证**（全部实跑）：`--selfcheck` **338 通过 0 失败**（322 → 338，+16 例）；
`ci-wiring.sh` **375 项**（337 → 375，+38 项）；`ci.sh` **11/11 门全绿**
（`contract-check` 109/109、deb 打包通过）；真机端到端探针
`scripts/probe-sni-icon.sh` 通过（总线 `IconPixmap` 32×32 / 4096 字节 / **非零 1936**）；
**负控 13 处真红**（接线门 8 + selfcheck 2 + 端到端探针 3）。
**视觉零变化**（`docs/snapshots` 逐张未动 ⇒ 本批只加托盘接线与判据，不动面板像素）。

**本批踩到并修掉的坑**（实测撞出来的，含**我自己的误判**）：
① **我自己的期望串写错了** —— 盯着 `dbus-monitor` 输出的**开头几行**看到一片 `00` 就断言
「`IconPixmap` 被编成全 0」；**错**：圆形图标的**边缘像素本来就是透明的**，把**整张图**的
非零字节数统计出来是 **1948/4096**（真图）⇒ 「全 0」结论作废，还差点照着它去改
marshaller（改完对照实测**没有区别**）。⇒ 判据必须统计**整张**，不能看开头几行；
⚠ 顺带记一笔：这个数是**取样值**，不是定值 —— 抗锯齿的边缘像素会让它在**十几个字节**范围内
浮动（另一轮实测是 1936）⇒ 探针判的是「非零 **> 0**」而不是「= 某个数」，
这才是该写的判据（把取样值写死成期望值 ⇒ 换个环境必假红）；
② **接线门脚本红了却不报失败** —— 批 X 的门项在「接线完整（…）」那段**之后**，而那段自己
`exit 1` ⇒ 门项打 ✗ 但**脚本退出码仍是 0** ⇒ 这一门在 CI 里形同虚设（负控判定读成
「没红」才暴露）⇒ 末尾补 `exit $ARCH_FAIL`；
③ **同名多处互相顶替**（累计第九次）—— 三个 pixmap 属性名在判定层/平台层**各有多处**，
全文计数门必然对不上 ⇒ 新增 `arch_need_count_in_fn`（按「签名行 + 花括号配平」切出
**具体函数体**再数）；
④ **门项盯「至少一处」不够** —— `drawEllipse(QRect(` 只盯「出现过」的话，把**其中一处**改回
圆心语义门照样绿 ⇒ 改成「**两处**都是」；
⑤ **`QDBusArgument` 写完就是只写的**（「read from a write-only object」）⇒ 同一份数据在
进程内**读不回来** ⇒ 字节级判据**放 selfcheck 里只会得到假判据** ⇒ 只能做**真机端到端探针**
（外部进程 `gdbus` 从总线另一端读）；
⑥ **`QDBusMetaType::registerCustomType` 的签名必须显式声明** —— 结构体签名推不出来，
不声明宿主会按 `av` 解，拿到一堆 variant 而不是像素数组；
⑦ **负控的变异点也必须命中「真代码」那一行** —— `registerVirtualObject` 在
`src/platform/TraySni.cpp` 里出现 **2 次**：第 1 次在**注释**（「见头文件约束①」）、
第 2 次才是 `bus.registerVirtualObject(...)` 真调用。负控原先写
`replace('registerVirtualObject', 'registerObject')` ⇒ **只换第一处** ⇒ 动的是注释、
真代码**没动** ⇒ 接线门照样全绿（门会 `strip_comments`）⇒ 差点把「门被骗过」误判成
「门没问题」（**门是对的，是负控自己没打到点上**）⇒ 变异必须用**精确代码串**定位；
⚠ 而且**不能**直接换名：`registerObject(path, obj, SingleNode)` **编不过**
（`SingleNode` 是 `VirtualObjectRegisterOption`，而 `registerObject` 收的是
`RegisterOptions`）⇒ 那不是「真的错误实现」而是编译错误，负控无效
⇒ 改成**编得过但真的错**的 `registerObject(path, obj)`：走普通 QObject 导出
（我们的 `SniItemObject` 没有 `Q_PROPERTY` ⇒ 导出的是**空接口**）
⇒ 宿主读不到任何属性 ⇒ 注册了也白注册（正是门项要防的那条路）；
⑧ **门自己报的项数不可信 ⇒ 文档里的「N 项」就不可核** —— `ci-wiring.sh` 的
「接线完整（…，N 项）」那行打在**中途**，报的是**批 X 段之前**的计数；批 X 段又加了
38 项却没报总账 ⇒ 我先前写进文档的「371 项」**实测是 375 项**（差 4），
而**光看门输出永远发现不了这个差**（中途那行和末尾那行都"看着像"总数）
⇒ 末尾改成报**总项数**（`门项合计 ${ARCH_N} 项（含前段）`），文档改成 375。
⚠ 这条是**自己写文档时核出来的**：门全绿、负控全红，**都不能保证文档里的数对**。
⑨ **量「X11 选区」不能用 `xprop -root`** —— 批 X 写「`_NET_SYSTEM_TRAY_S0` 与 `_NET_SYSTEM_TRAY` 选区**都不存在** ⇒ X11 上没有 XEmbed 选区」，据此把 M1-3 判成「路径要重做」。
**错**：`xprop -root <名字>` 查的是**窗口属性**，而**选区**要用 `XGetSelectionOwner()` 查 ⇒ 「not found」只说明「没有哪个窗口**有这个名字的属性**」，跟选区有没有主毫无关系。
批 Y 用 `XGetSelectionOwner` 实测：`_NET_SYSTEM_TRAY_S0` **有持有者**（`0xe00000`，daemon 建的 1×1 未映射 InputOnly 窗口）⇒ X11 上**有** XEmbed 选区，dock 插件就是靠它接图标的。
⇒ **同一个量具用错一次，整条结论就歪**（这次歪的是「路径未知」这件事本身）。

**未完成（照实记录）**：**M1-3 端到端未达成**（本批交付的是**跨平台正确**的 SNI 实现 +
两个真缺陷修复；DDE 侧下一步是改走 `TrayManager1` 窗口注册）。
⚠ 另有一个**独立于本批**的环境事实：托盘区那 3 个圆是**空的深灰占位圆**（图标内容没
渲染出来）⇒ **本机 deepin 25 的托盘图标渲染本身也是坏的** ⇒ 「图标有没有出现」这个
判据在本机**不能单独采信**，必须与 `TrayManager1.TrayIcons` 列表 / `Added` 信号一起看。

### 批 Y · M1-3 改走 deepin 托盘**窗口协议** —— 端到端**达成到 daemon 侧**（像素仍受本机缺陷阻塞）

批 X 结束时 M1-3 卡在「正确路径要重做」。批 Y 先把路径**逐段测通**，再按它实现。

**做了什么**：新增判定层 `src/logic/DeepinTray.{h,cpp}`（纯结论、零 X11）—— dock 报文的
**字段偏移**、选区名、操作码、**后端选择**（deepin 选区优先于 SNI watcher）、**后端强制指定**的解析；
新增平台层 `src/platform/DeepinTray.{h,cpp}`（xcb：查选区持有者 → 用 daemon 广告的
`_NET_SYSTEM_TRAY_VISUAL` 建 **32 位 ARGB** 图标窗口 → 画图标 → 发 `REQUEST_DOCK` →
用 daemon 的 `GetName` 验证是否真被认领）与 `src/platform/TrayBackend.{h,cpp}`（读后端强制开关）；
`TrayController` 改成**三态后端**（deepin 窗口 / SNI / 旧协议，**互斥**）；
新增真机端到端探针 `scripts/probe-deepin-tray.sh`；
`--platform-probe` 增报 `deepinTraySelection`；selfcheck +14 例；接线门 +43 项。

**三方分工（批 Y 实测厘清，批 X 弄错了其中一环）**：

| 方 | 是谁 | 干什么 |
|---|---|---|
| 托管方 | `org.deepin.dde.TrayManager1` 的 owner = **`:1.20` = `dde-session-daemon`**（**不是** dock 插件） | 持有 `_NET_SYSTEM_TRAY_S0`、登记图标窗口、盯 damage、发 `Added/Removed/Changed`、维护 `TrayIcons` |
| 绘制方 | dde-dock 托盘插件（`trayplugin-load` + `libapplication-tray.so`） | 读 `TrayIcons` → 为每个窗口建 32 位 ARGB 容器 → **reparent 图标窗口进去** → 抓窗口图像当图标 |
| 我们 | 客户端 | 造 X11 窗口画图标 → 向选区持有者发 `REQUEST_DOCK` |

**注册协议（实测可复现，权威来源 `linuxdeepin/dde-daemon` → `trayicon1/traymanager.go`）**：

1. 查持有者：**`XGetSelectionOwner(dpy, "_NET_SYSTEM_TRAY_S0")`** ⇒ 实测 `0xe00000`
   （daemon 自建的 1×1 未映射 InputOnly 窗口）。
   ⚠ `_NET_SYSTEM_TRAY`（无后缀）**没有**持有者；选错选区 ⇒ daemon 收不到。
2. 发 `ClientMessage`：`type=_NET_SYSTEM_TRAY_OPCODE`，
   **`data.l[1]=0`（REQUEST_DOCK）、`data.l[2]=窗口 id`**。
   ⚠⚠ **比经典 XEmbed 偏移一位**（经典是 `l[0]`=opcode、`l[1]`=窗口、`l[2]`=版本）。
   ⇒ **实测**：按经典布局发 ⇒ daemon 读到的 opcode 是窗口 id ≠ 0 ⇒ **静默忽略**
   （`TrayIcons` 不变、也不报错）；按 deepin 布局发 ⇒ **注册成功**。
   ⇒ 顺带说明批 X 结论「交给 `TrayManager1.Manage`」**是错的**：`Manage()` 只是让 daemon
   **重新 claim 选区**，**不注册任何图标**（实测调了它，我们的窗口照样没进 `TrayIcons`）。

**批 Y 实测结果**（造 22×22 窗口，`WM_CLASS` 照 `cc-switch` 抄 `"tray-icon tray app <名>"`）：

- ✅ `TrayIcons` 从 2 个变 3 个（多出我们的 `0x6E00001`）⇒ **注册协议跑通**；
- ✅ `GetName(0x6E00001)` → `'deepDolphin'` ⇒ daemon 认得我们；
- ✅ **dock 真的 reparent 了它**（窗口被改成 22×40、状态 `IsViewable`）；
- ❌ **托盘区 0 像素变化**。

**为什么没显示（批 X 只知道「渲染是坏的」，批 Y 知道了机制）**：dock 显示图标的门是
`handler->enabled()`，而 `enabled` 由 `getX11WindowImageNonComposite(窗口)` 决定 ——
**抓不到窗口图像 ⇒ `enabled=false` ⇒ `itemRemoved` ⇒ 干脆不显示**（连占位圆都没有）。
本机托盘区那 3 个圆**本来就是空的深灰占位圆** ⇒ **dock 抓图标图像这条路整体是坏的**
（`cc-switch` / `clash-verge` 这两个正经托盘应用也只显示占位圆）⇒ **不是客户端能修的**。

**⇒ 对 M1-3 的结论**：路径**已查明并已实现** ⇒ 风险由「高（路径要重做）」回落为
「**中（实现完成；剩真机/容器的像素级验收）**」。
**实现后的实测（批 Y 代码落地）**：

- ✅ **窗口被 daemon 认领**：`TrayIcons` 里出现我们的窗口 id，
  `GetName(我们的窗口)` → `'deepDolphin'`（应用自己的校验也是这一条）；
- ✅ **窗口被 dock 接管**：窗口从 22×22 被改成 **22×40**、状态 `IsViewable`、
  **不在 root 的子窗口里** ⇒ dock 把它 reparent 进了自己的托盘容器；
- ❌ **托盘区仍 0 像素**：dock 侧 `getX11WindowImageNonComposite()` 抓不到窗口图像
  ⇒ `enabled=false` ⇒ 干脆不显示（连占位圆都没有）。
  ⇒ **这不是我们客户端能修的**：本机连 `cc-switch` / `clash-verge` 这两个正经托盘应用
  也只显示**空的深灰占位圆** ⇒ 是**本机 dock 的渲染缺陷**。
  ⇒ 端到端**像素**验收要等真机/容器（与 D7 同批做）。

**本批实现中踩到并修掉的坑**（都是实测撞出来的）：

1. ⚠⚠ **`xcb_create_window` 的 `values[]` 必须按 mask 位升序** ——
   `XCB_CW_BORDER_PIXEL`(bit3) → `values[0]`、`XCB_CW_EVENT_MASK`(bit11) → `values[1]`、
   `XCB_CW_COLORMAP`(bit13) → `values[2]`。写反了 ⇒ 边界像素被当成 colormap、
   colormap 传成 None ⇒ **32 位 ARGB 窗口「建了却不存在」**
   （`GetWindowAttributes` 报 **BadWindow(3)**、窗口不在 root 的子窗口里）
   ⇒ daemon 认不出它。⚠ **24 位那条当时「能用」纯属侥幸**：传错的字段恰好无害。
2. ⚠ **X 错误码别记反**：**3 = BadWindow**、**2 = BadValue**（我一度记成反的，
   差点把「窗口没建成」误判成「参数不合法」）。
3. ⚠ **xcb 的 void 请求没法逐个查错**：`xcb_request_check` 对**成功**的 void 请求
   会**阻塞等下一个错误** ⇒ 前一个检查会把**后一个请求的错误吃掉**
   ⇒ 「建窗没报错」是**假阴性**。⇒ 要么一次只发一个请求，要么用 `XSetErrorHandler`。
4. ⚠ **每次刷新都新建窗口**：刷新图标时又建一个 ⇒ 窗口 id 一路涨
   （0x7000000 → 0x7000002 → …）且反复发 dock 请求 ⇒ 改成「已建过就只重画」。
5. ⚠ **xcb 走不通 pkg-config**：本机构建环境的 pkg-config（2.5.1）解不开
   `xcb → xau → xproto` 的 `Requires.private` 链（新的 pkgconf 正常）
   ⇒ 改用 `find_path`/`find_library` 直接找（与 Qt 的查找方式一致）。
6. ⚠⚠ **改了后端优先级 ⇒ 旧的端到端判据会「永远假红」** —— 本批把 DDE 的后端从 SNI
   改成 deepin 窗口协议 ⇒ `scripts/probe-sni-icon.sh`（批 X 的 IconPixmap 字节级判据）
   在 DDE 上**再也跑不起来**了：应用压根不注册 SNI 项 ⇒ 「服务没上线」。
   ⇒ 这不是「判据坏了」，是**判据的前提被改掉了**；两条路都得留着可验。
   ⇒ 解法：加**后端强制开关**（`DEEPDOLPHIN_TRAY_BACKEND`，测试钩子、默认不强制），
   探针强制走要验的那条路，**并核对应用自报的后端**（见下条）。
7. ⚠ **`qInfo` 逐参数打印会给 QString 加引号** —— `qInfo() << QStringLiteral("托盘后端 = %1（%2）")`
   出来是 `"托盘后端 = deepin-window（自动）"`（**整条带引号**）；
   逐参数打更糟：`托盘后端 = "deepin-window" "（自动）"`（每个参数各带一对引号）
   ⇒ 探针按空格切字段会切错 ⇒ 判据**假红**。
   ⇒ 结论：**给机器读的日志行**要打成**单条**字符串（不要多参数拼接），
   探针再按固定前缀正则取（`托盘后端 = \([a-z-]*\)`）。

**判据分层（批 Y 继续沿用批 X 的结论）**：

- `--selfcheck`（判定层纯函数，+14 例）：字段偏移 / 选区名 / 操作码 / 请求组装 /
  **后端优先级**（选区在场 ⇒ 走窗口协议，**哪怕 watcher 也在**）/
  **后端强制开关**（认得的值、认不出 ⇒ 判成「没指定」、强制**优先于**自动选择）。
- 真机端到端探针 `scripts/probe-deepin-tray.sh`（**不强制后端** ⇒ 验的是「自动选路对不对」）：
  ⓪ 应用自报后端 = `deepin-window` → ① 应用自报「已认领」（它自己先验过 `GetName`）→
  ② 窗口 id 在 `TrayIcons` 里 → ③ X 侧 `WM_NAME` 是我们的名字。
  ⚠ **不看「图标有没有画出来」**（本机 dock 渲染坏的）。
  ⚠ 探针自己也踩过坑：gdbus 的数组输出**只有第一个元素带 `uint32 ` 前缀**
  ⇒ 只按 `uint32 (\d+)` 抓会漏掉排在后面的我们的窗口（负控实测）。
- 真机端到端探针 `scripts/probe-sni-icon.sh`（批 X 那个，**现在强制走 SNI**）：
  ① 应用自报后端 = `sni`（**强制开关生效了吗**）→ ② 服务上线 → ③ `IconPixmap` 32×32 /
  4096 字节 / 非零字节 > 0。⚠ 强制开关是**测试钩子**（默认不强制 ⇒ 生产行为零变化），
  解析规则在判定层、平台层只读环境变量（单一真相源）。
- **负控 14 条全红**（含「强制开关被忽略」「应用不报后端」「平台层自己硬判环境变量」）。

### 批 Z：**引擎侧** C++ 图谱/置信度修复 —— deepin 自己身上照出两个一直没人注意的缺口

批 Z 去看「`index query` 到底该不该接 GUI」，顺手把引擎在 **deepin 客户端自己身上**
量了一遍 ⇒ 照出**两个一直没人注意的引擎侧缺口**（**客户端一行代码都不用改**）。

**缺口 ①：C++ 自由函数几乎全扫不出来。**
图谱扫描器是**关键字 + 形态**驱动的（`func`/`def`/`class`/`struct`/…）。
C++ **没有函数声明关键字**，只有 C 系的形态兜底（`返回类型 name(` + 行内含 `{`）；
而 deepin 用 **Allman 风格**（`{` 另起一行）⇒ 签名行里没有 `{` ⇒ 判否。
实测：`deepin/src/**/*.cpp` 顶层自由函数 **364 个，引擎只认出 1 个**（漏 99.7%）。
`class` 也不在 C 系的声明词表里 ⇒ C++ 的类**一个都不认**
（`TrayController` / `PanelWindow` / `AppModel` 在图谱里根本不存在）。

**缺口 ②：未解析调用的「接收者豁免」差一位。**
代码注释承诺「接收者调用（`a.b()`）豁免」，实现却读**前一个 token** 的标记
⇒ 对最常见的一层成员调用**不生效**（只有链式 `a.b.c(` 恰好命中，把 bug 掩盖了）；
`->` 与 `::` 两种隔断**根本没有豁免规则**。

**为什么这不只是「少几个符号」**：

1. 符号漏扫 ⇒ 置信度的「幻觉调用」判据是「调用了全仓没有定义的名字」
   ⇒ **对真实自由函数的调用被误报成「幻觉 API」**。实测 295 条里
   `clipNote` / `runOne` / `defaultToolName` 这些**确实存在**的函数被逐条点名。
2. 符号漏扫 ⇒ **函数体边界**（= 本符号行 → 下一个符号行）算错 ⇒ 中间那些没被
   认出的定义不占边界 ⇒ 前一个函数的「函数体」把中间函数的 if/for 全吞进去
   ⇒ **凭空多出高复杂度告警**（`clipNote`（2 行）被判「圈复杂度 13」）。

**已修（引擎仓 `fix/cpp-graph-symbols`，提交 `64decd1`）**：C 系函数名**统一**按
「紧跟参数列表 `(` 的那个标识符」取（修掉限定返回类型 / const 限定 / 限定名成员函数
定义三种形态，两种写法口径一致）；新增 Allman 风格签名识别（区分**原型声明**）；
`tables["c"]` 补 `class`；接收者豁免修 off-by-one 并补 `->` / `::`。

**实测效果（deepin 客户端 369 文件）**：

| 指标 | 修前 | 修后 |
|---|---|---|
| 符号总数 | 2180 | **3232**（+1052） |
| deepin 模块符号 | 489 | **1541**（3.2 倍） |
| 幻觉调用 | 295 | **159**（-46%） |
| 其中「成员/限定调用」类误报 | 106 | **0** |
| 高复杂度 | 49 | 179（**都是此前压根没被扫到、因而没被检查的真实函数**） |
| 置信度得分 | 68 | 68（幻觉调用减掉的罚分与复杂度增多的罚分抵消） |

⇒ **分数没动，但内容从「一半是假的」变成「基本可信」**。抽查 `executeTool`（21）/
`fromScript`（12）与源码分支数相符 ⇒ 新增告警成立。

**⚠ 仍然存在的结构性局限（诚实记录，本次不修）**：C++ **没有 import 机制**
⇒ 标准库/第三方库的名字永远不会出现在仓里 ⇒「全仓无定义 ⇒ 幻觉 API」这条判据
在 C/C++ 上**天然有误报**。实测剩下的 91 条里，glib/Qt 的外部自由函数与**局部变量
声明形态**（`QFile tar(path);`）占大头 —— 要消只能靠「库白名单」（追不上所有库）
或「声明形态」判定（有放过真幻觉的风险）⇒ **交给展示层说明**，不在引擎里堆启发式。

**⚠ 跨仓顺序依赖**：修复在**引擎仓**，客户端拿到的引擎由**发行版**决定 ⇒
批 P 那条「引擎 release 带 Linux x64 资产」因此更紧迫（否则用户拿到的还是旧引擎）。
本机已把新引擎装到 `~/.local/libexec/deepdolphin/moongit.bin`（旧版备份
`moongit.bin.bak-20261020`）⇒ 客户端的置信度页签/热力图**立刻受益**。

**⚠ 顺带更正（批 AA 实测复核，**撤回批 Z 的「推翻」**）**：台账里 `index query` 有
**两处互相矛盾的**定性（一边「判定不接 GUI」、一边「下一批候选」）。批 Z 判「不接 GUI
是错的」⇒ **批 AA 实测发现这半句推过头了**：`moongit graph functions ddTest --json`
的 `functionEdges` **5274 条、每条都带 `tier`**（direct/guessed/resolved），
`index query chooseBackend` 的 `callers[]` **也每条带 `tier`** ⇒ **两者同维度**
（函数级调用边 + 边的确信度档位）⇒ 台账原判据「**重叠 ⇒ 不接 GUI**（接了会造出第二个
真相源）」**基本正确**。批 Z 说对的两点仍成立（`defs[]` 按符号查 vs `functions[]` 全项目
列表；`findings` 计数 vs 数组）—— 那是**取数形态**差异，不是**数据维度**差异。
⚠ 批 Z 的引擎修复**确实解锁**了它（修前 C++ 符号压根不在索引里 ⇒「符号不在索引中」，
修后返回 3 个 callers 带 `tier: resolved`）—— **解锁 ≠ 该接 GUI**。
⇒ **教训**：要比「重叠」必须**两侧都实测**；批 Z 拿 `graph symbol`（文件级）去比
`index query` ⇒ 比错了对象（详见台账 E.1i「批 AA 勘误」）。

### 批 AA：固定文档页四语言 + 页内语言切换（B8 的第一块）

批 G 把四类文档页的**类目结构**做完了，正文写死在代码里（不取引擎）⇒ 扩语言
**只加常量、不改结构**。本批把判定层 `logic/DocPages` 从「只有 zhCN」扩到
**zhCN / en / zhTW / ja**（与 mac 的 `AppLanguage` 一一对齐），四类文档各四种语言的
正文**全部给全**，文档窗内加**语言选择器**，选完写进 `Settings` 的 **`app.language`** 键（与 mac UserDefaults 同名键逐字对齐）。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 201 | **不抄 mac 的残缺译文，按 deepin 的中文底本逐篇写全** | mac `DocsPages.swift` 的 zhTW / ja **比 zhCN 少好几节**（它自己没写全）⇒ 抄过来就是「四语言里两语言是残的」 | 12 篇正文是新写的（人工成本） |
| 202 | **文案全在判定层：文档窗里一个中文字面量都不许有**（接线门 `arch_forbid_han` 盯**内容**；另有 `arch_forbid` 盯 `QStringLiteral(` 这一种写法） | 只换正文不换外壳 ⇒ 界面变成「中文分段名 + 英文正文 + 中文按钮」的**中英混杂**，比不做更糟 | 加新文案要改判定层（这是有意的）；⚠ **范围仅限文档窗** —— 「全应用 UI 零中文字面量」是 M2-5 的待办（1019 条要人工翻译），**不是已达成** |
| 203 | **不静默回落**：语言键认不出 ⇒ `languageFromKey` 返回 `std::nullopt`（不猜）；落地方案在 `resolveLanguage`（回落 + 标记），UI 据此**说一句**并把坏键改回 | 猜错的话，用户改了设置却看不到变化，且**永远不知道为什么** | 多一个提示分支 |
| 204 | **提示函数「入参给值、出口即成品」**（不留 `%1` 给调用方填） | 留半成品模板出去 ⇒ 调用方忘了 `.arg` 就把「%1」原样显示给用户（这正是本批 selfcheck 第一次跑时抓到的问题） | 无 |
| 205 | **不做全应用 i18n，只做固定文档页** | 半吊子本地化会中英混杂；且全应用 1008 串里 85% 要新译（见下），**没有翻译来源就不铺开** | B8 仍是 P2 |

**实测（四语言正文的自动扫描，脚本量而不是眼估）**：

| 检查 | 结果 |
|---|---|
| 16 篇正文（4 类 × 4 语言）齐全、非空 | ✅ |
| 同类目四语言**两两不同** | ✅ |
| 英文正文**不含任何汉字**（回落成中文的直接信号） | ✅ |
| 日文正文**都含假名** | ✅（156–459 个/篇） |
| 繁中正文**不含简体独有汉字** | ✅ |
| 四语言**小节数一致**（不许某语言残缺） | ✅（关于 2 / 帮助 6 / 致谢 3 / 日志 2） |
| 四语言关于页都写本平台事实（Qt / DDE / deepin），都不含 Swift / macOS | ✅ |

**本批验证**：`--selfcheck` **374 通过 0 失败**（352 → 374，+22 例：语言枚举与顺序 /
key 稳定性 / 认不出 ⇒ nullopt / 解析三态 / 16 篇非空 / 同类目两两不同 / 英文无汉字 /
日文有假名 / 小节数一致 / 四语言平台事实 / 英文类目名无汉字 / 语言显示名互不相同 /
外壳文案齐全 / 出口即成品 / 作用域提示齐全且英文档无汉字）；
`ci-wiring.sh` **466 项全绿**（418 → 466，+48 项）；`ci.sh` **11/11 门**。

**⚠ 键名与 mac 逐字对齐**：持久化键是 **`app.language`**（mac UserDefaults 同名键，
`L10n.swift:2042`），取值也是同一套 `zh-CN` / `en` / `zh-TW` / `ja`。
⚠ deepin 目前**只有固定文档页**跟它走（全应用 i18n 是台账 B8）⇒ 文档窗的语言
选择器**悬浮提示如实说明这一点**（「目前只影响这一窗，其余界面仍是简体中文」）
—— 不说的话就是**不诚实的承诺**。
⇒ 全应用化之后**还是同一个键**，不必迁移，也不会出现两个「语言设置」打架。

**⚠ 补了一道**行为**门（接线门是源码扫描，证不了「界面真换了」）**：
新增无头探针 `--docs-lang-probe`（`src/ui/dialogs/DocsDialogProbe.{h,cpp}` + `main.cpp`
的无头分支）：**真跑**一遍四语言切换，逐语言报出文档窗的**实际呈现**
（标题 / 关闭按钮 / 四个类目分段名 / 正文 / 底部说明），断言脚本
`scripts/ci-docs-lang-probe.sh`（CI 第 4 门）逐条核对：四种语言**两两不同**
（相同 = 换语言没生效）、英文档**不含汉字**、呈现里**不许出现字面量 `%1`**。
⚠ 探针会切语言 ⇒ 会写 `app.language` ⇒ 探针走 `QStandardPaths` **测试模式**
且以 `::_exit` 收尾（QSettings 根本不落盘）⇒ **绝不碰用户的真实设置**（实测：
探针跑完 `~/.config/deepin/deepDolphin.conf` 的 mtime 没变）。
⚠ 探针的「字段名」是**机器格式**，不属于用户可见文案 ⇒ 单独放探针文件
（`DocsDialogProbe`），不去破「文档窗里一个字符串字面量都不许有」那条纪律。

**⚠ B8 的真实规模（这一条比上面的实现都重要）**：deepin 用户可见中文串
**1008 个去重 / 1186 次出现**；mac `L10n.swift` 的 zh-CN 表只有 **483 键** ⇒
把 mac 的译文**逐字**搬过来只命中 **155 个（15%）**，**85% 要新写**（尤其中日）
⇒ 台账原记「P2（量大）」**低估**了 ⇒ 全应用 i18n **不是一批能做完的活**，
要先解决「谁来翻」。

**⚠ B9 判定：不做**（实质只是「设置从对话框变独立窗口」；deepin 的 `AiSettingsDialog`
已是 `DDialog` 且**有「关闭」按钮**，mac 那个 sheet **无关闭按钮**的问题在 DDE 下
**根本不存在** ⇒ 价值低）。

**顺带照出并已更正的一处我自己的错**：批 Z 把 `index query` 说成「新维度」是
**推过头了** ⇒ 批 AA 实测 `graph functions` 的 `functionEdges` **5274 条、每条带
`tier`** ⇒ 两者**同维度** ⇒ 台账原判据「重叠 ⇒ 不接 GUI」**基本正确**，
已把台账与本文两处「推翻」**撤回**（详见上文批 Z 节的「顺带更正」）。

**视觉变化**：固定文档窗多一个语言选择器（右上角），不进四页快照矩阵，快照基线未动。

### 批 AB：引擎发版链打通 + 下载链接真实布局 + 工具面收敛

批 Z 之后引擎侧攒了 4 个提交一直**只在本机**（用户装的仍是 `v0.1.0`，**只有 darwin-arm64
资产、无 Linux x64**）⇒ 批 P 的「下载引擎」在真机上仍然拿不到引擎。本批把**发版**这件事
真做掉，顺带把客户端的下载链和工具面对齐真实发布物。

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| 206 | **发版从 `dev` 不从 `main`** | `main` 落后 `dev` **49 个提交** ⇒ 从 `main` 发的包**比客户端本机装的还旧**，下载完反而降级 | `main` 与 `dev` 的差距要另外收敛 |
| 207 | **发布产物必须自包含**：`moongit` 启动器 + `bin/moongit-cli` + `runtime/lib/`；验收口径 = `tar xzf … && env -i …/moongit --help` | 裸二进制离开构建机就 `Library not loaded`（仓颉 runtime 没跟过去）；`env -i` 才能暴露「靠构建机绝对路径才跑得起来」的包 | 包更大（Linux 资产 7.5MB） |
| 208 | **工具面收敛 = 模型可见面剔除废弃别名，可执行集不变** | 契约门第 12 组要求「可执行集 == 引擎声明集」⇒ 收敛的只能是「**推荐给模型**的那一面」 | 模型不再看到旧名（用户手打旧名仍能执行） |
| 209 | **缺省不是废弃**：老引擎没给 `deprecated` 标记 ⇒ 不收敛 | 老引擎兼容（引擎 0.2.0 起才有标记） | 老引擎下旧名仍会推荐给模型 |
| 210 | **落盘按真实布局「整包」落**（启动器 + `bin/` + `runtime/`） | 只拷启动器 ⇒ 装下来的引擎 exec 不到二进制 / 加载不到运行库 ⇒ **装了个跑不起来的引擎** | 安装目录变大 |
| 211 | **引擎缺失时，首屏必须给得出路**（不许让用户绕到设置页去找下载入口） | 引擎缺失时用户**第一眼**看到的就是首屏；下载链只在设置页 ⇒ 用户得先知道「设置里有」才用得上 ⇒ 这条链在**最需要它的时刻是找不到的** | 首屏多一个主操作按钮 |
| 212 | **视觉基线必须「被某道门拍」且「被某道门比」** | 存着一张**拍不出、没人比**的基线 ⇒ 让人以为有保障，实际没有 ⇒ **死基线比没基线更隐蔽** | 基线目录多两张 + CI 多拍两张 |
| 213 | **注释/文档描述行为时，要有一条门让实现来对质**（不靠人记得回头改） | 头注释写「不用 replaceId」、实现一直用着 ⇒ **说法与实现相反**比「说法缺失」更危险：缺失会引人去查代码，相反的说法会让人**照着它改代码** | 门项多几道（含一道不剥注释的） |

**实测**：

| 项 | 结果 |
|---|---|
| v0.2.0 release | ✅ Linux x64（7.5MB）+ mac arm64（7.8MB）资产齐；`releases/latest` 正确指向 v0.2.0；GitHub 侧 sha256 与本地实测**一致** |
| ⚠ v0.2.0 的 Linux 资产 | ❌ **坏包**（`runtime/lib/` 是空的）⇒ 已在 **v0.2.1** 修好并在 release 说明里标注 |
| 模型可见工具面 | **22** 个（6 个旧名别名已剔除）；可执行 / 可校验 **28** 个（别名仍在，仍能调用） |
| 提示词清单 | 与模型面**同一口径**（否则模型会去调「提示词里有、工具表里没有」的名字） |
| 判据 | selfcheck **379/0**、contract-check **110/0**、ci.sh **11/11**、接线门 **466** 项、工具面探针 ✅、文档语言探针 ✅；**负控 15/15 真红** |

**⚠ 照出并修掉一个「只会在 CI 上炸」的坑（引擎仓）**：
客户端端到端把 v0.2.0 的 Linux 资产装下来 ⇒ **引擎跑不起来**
（`exec: …/bin/moongit-cli: not found`）⇒ 查出来 CI 产物的 `runtime/lib/` 是**空的**
（本地打的同一个包是好的）。根因：引擎打包脚本的 Linux 分支用 **`ldd`** 找仓颉库 ——
而 `ldd` 解析依赖靠的是**运行时的库搜索路径**（`LD_LIBRARY_PATH`）：本地同一个 shell 里
source 过 `envsetup.sh` 所以找得到，**CI 的每个 step 是独立 shell**（打包步骤没 source）
所以全部 `not found` ⇒ 脚本**静默**一个库都不拷、照样打印「✓」、流水线全绿、release 照发。
⇒ 改法（引擎仓 AGENTS.md 不变量 140）：依赖清单改用 `readelf -d` 的 `DT_NEEDED`
（读二进制本身，不看运行时环境）、库来源改用 SDK 目录（找不到就 `exit 1`）、
**打包后真的解包跑一次**（原来脚本只**打印**自验口令、从不执行 ⇒ 等于没有自验）。
⇒ 同族另一个：release job **403**（仓库默认 `GITHUB_TOKEN` 权限是 read-only）⇒
workflow 显式 `permissions: contents: write`；并把 `workflow_dispatch` 补成**显式传 tag**
（手动触发时 `github.ref` 是分支，不处理会 checkout 到分支代码、还把 release 建在分支上）。

**⚠ 客户端侧照出的一处「虚构布局」**：客户端的 `logic/EngineDownload` 一直假设
「发布包根部只有一个 `moongit-cli`」⇒ 真实包根是**启动器 `moongit`**，真二进制在
`bin/moongit-cli`、运行库在 `runtime/lib/` ⇒ 改为**整包落盘**，
并把契约门第 21 组的夹具**同步改成真实布局**（原来那个夹具是虚构的 ⇒
测过的路径真实资产根本走不到）。

**⚠ 判据要跟着真相走（第二轮收紧，照出两个真问题）**：
初版探针脚本把 6 个别名名**硬编码**在脚本里 ⇒ 引擎将来增减别名时这道门就跟不上真相
（**新增**别名 ⇒ 漏检，别名还在模型面里而门是绿的；**取消**标记 ⇒ 假红）。
⇒ 改成：探针从引擎**原始清单**里解析出「**被标记的是哪些**」（新增输出行
`engine_deprecated_names=`），脚本**按引擎给的名字**断言；并加一条**数量自洽**断言
（校验表个数 − 模型面个数 == 被标记的别名个数）⇒ **只剔了一部分**、或**多剔了非别名工具**，
都会被抓住（逐个名字的断言抓不到前者）。
⚠ 顺带照出：**并非所有 `codegraph_*` 都是废弃别名** ——
`codegraph_patch_confidence` / `codegraph_patch_merge` 是**新功能**（引擎没标废弃），
它们**应该**留在模型可见面 ⇒「按前缀一刀切」是错的判据。
⇒ 同一轮还照出「**收敛口径有两处实现**」：模型面在 `ai/AgentCore` 里自己写了一遍
`!t.deprecated`，而提示词用判定层的 `activeJson()` ⇒ **两处实现、碰巧一致**，
改一处忘另一处就漂（模型会去调「提示词里有、工具表里没有」的名字）
⇒ 统一到判定层 `ToolsEnvelope::activeTools()`（**单一真相源**），模型面与提示词都按它来。

**⚠ 一条工程纪律（本批真踩到，差点误判成产品 bug）**：
做负控要**改源码**再还原。`cp` 备份 + `mv` 还原时 **`mv` 保留 mtime** ⇒ 还原后的文件
mtime **比 `.o` 旧** ⇒ `make` 按 mtime 判「无需重编」⇒ **跳过了重编** ⇒
**二进制里留着负控那版实现** ⇒ 判据结果失真（本次表现为 `packagedDirs()` 只剩 `bin`，
而源码明明是 `{bin, runtime}`）。
⇒ **负控还原后必须 `touch`（或强制重编）再跑判据** —— 否则「判据红了」可能只是在测一个
**不存在的二进制**。判据结果只有在「源码 == 二进制」时才作数。

**⚠ 本机网络事实（影响验收方式，不影响产品）**：
`github.com/…/releases/download/…`（302 到 `objects.githubusercontent.com`）在本机
**TCP 通但数据流卡死**（curl 与客户端都卡），而 `api.github.com` 与 `gh release download`
路径可用 ⇒ 端到端验收改用**本地 fixture**（`python3 -m http.server` 提供 release JSON +
**真实发布的资产文件**）⇒ 验的是客户端的**真实逻辑**：查 API → 下载 → sha256 校验 →
解包 → **整包落盘** → 探活。

**视觉变化**：无（本批全在判定层 / 执行层 / 发版链，界面未动）。

### 批 AC：引擎下载链的网络韧性（一次抖动不该让用户手动再点一次）

批 AB 第一次下载 v0.2.0 资产时，客户端直接报
`{"ok":false,"stage":"downloadFailed","message":"下载中断：Connection closed"}`，
**同时 curl 也卡死 90 秒无数据**；**稍后重试同一个 URL 1.17 秒就下完 7.5MB**。
⇒ **网络瞬断是常态**，不是「没网」⇒ 一次失败就放弃，等于把**可恢复的故障**变成
「用户必须手动再点一次」—— 而引擎获取是「**引擎缺失时用户唯一的出路**」。

| # | 决策 | 为什么 |
|---|---|---|
| 211 | **只重试「再试一次可能成」的故障**（白名单：连接被关 / 超时 / 未知网络错 / 服务端 5xx） | HTTP 404/403、主机不存在、连接被拒**重试没意义**，只是让用户干等 |
| 212 | 判定用**白名单**而不是黑名单 | Qt 将来新增的错误码默认**不**重试 ⇒「漏重试」只是慢一点，「乱重试」是把 404 试三遍 |
| 213 | **重试有上限**（3 次）且**退避递增**（1s→3s→9s） | 无限重试 = 用户干等；不退避 = 立刻再撞同一个坏网络 |
| 214 | 两个阶段（查发布信息 / 下载资产）**都**能重试 | 实测里 GitHub 侧 443 抖动会让**查询**也失败，不是只有下载会 |
| 215 | 最终仍失败时，文案带「**已重试 N 次仍失败**」 | 不许只给一句「下载失败」—— 用户要知道已经试过几次 |

**判据**：
- selfcheck **381/0**（+2）：可重试判定（**含明确排除**永久故障）；重试有上限且退避递增、越界输入要防御。
- 契约门第 21 组 **113/0**（+3 **行为门**）：本地 HTTP 打桩 ——
  ①「前 2 次请求**直接断开连接**（不发响应）⇒ 重试后**仍装成功**」；
  ②「一直断连 ⇒ 到上限后**最终失败**（不是无限重试）」。
  ⚠ 打桩的 `release.json` 必须由**服务器自己生成**（端口运行时才定 ⇒ 预置 JSON 里 URL 写不对）。
- 负控 **3/3 真红**（不重试 / 不认可重试 / 重试无上限）；**累计 18/18 真红**。

**视觉变化**：无（判定层 + 执行层，界面未动；只有下载过程中的 progress 文案多了「正在重试（2/3）…」）。

### 批 AD：D7 的**准**验收 —— deb 产物的「装完能不能用」（照出一个真 bug）

D7 的最终验收是「干净 deepin 25 容器里 `dpkg-deb -b` + 安装 + 启动」，本机**没有容器
运行时**（无 docker/podman）⇒ 那一段做不了。但「装完能不能用」里**不依赖容器**的那一半
可以做：把 deb **解包**到临时目录（**不装进系统、不污染本机**），按**包内的真实布局**
逐项查「装完之后点图标能不能起来」。

**⚠ 这一门第一跑就抓到一个真 bug（两条叠在一起）**：
`data/cn.deepdolphin.app.service` 原来写的是 `Exec=deepDolphin --dbus-service` ——
① **裸命令名**：**实测**（本机 dbus 1.16.2）dbus-daemon 激活服务时**不做 PATH 搜索** ——
   裸名 `true`（明明在 `/usr/bin` 里）也报 `Spawn.ExecFailed: No such file or directory`，
   而绝对路径 `/bin/false` 能 exec 成功（报的是 `ChildExited`）
   ⇒ **从启动器点图标 ⇒ 总线 exec 不到 ⇒ 激活失败、应用起不来**；
② **`--dbus-service` 这个 flag 客户端根本不认识**（全项目 grep 无此 flag）。
⇒ 两条合起来 = **deb 装上、图标在启动器里、点了没反应**。

**修**：`Exec=/usr/bin/deepDolphin`（**绝对路径**、**无参数**）—— D-Bus 激活 = 正常启动客户端，
它在 GUI 主路径里自己注册 `cn.deepdolphin.app`（`AppService::registerOnBus`）。
⚠ 绝对路径与安装路径必须一致 ⇒ `scripts/build-deb.sh` **打包期校验**：路径不一致、或 Exec 带了参数
⇒ **直接构建失败**（不让两处悄悄漂）。

**新门** `scripts/check-deb-layout.sh`（**ci.sh 第 12 门**），10 项：
可执行在包内且可执行 / service 的 Exec 是绝对路径 / service 的 Exec 指向的可执行在包内存在 /
service 的 Exec 不带参数 / desktop 的 Exec 指向的可执行在包内存在 / desktop 的 Icon 在包内有图标 /
`DBusActivatable=true` ⇒ service 文件存在 / metainfo 的 `<id>` 与 desktop 文件名一致 /
可执行在**空环境**下能跑 `--version` / 包内图标都非空。
⇒ 负控 **6/6 真红**（service 裸名 / 带假 flag / 指向不存在的可执行 —— 三条都被**打包期校验**拦住；
**绕过**校验后门 12 **自己**也能抓住 ⇒ 两道防线；Icon 指向不存在的图标 / 零字节图标 —— 门 12 抓住）。
⇒ 累计负控 **24/24 真红**。

**⚠ 顺带订正 M3c 的一处过时描述**（实测，非推测）：M3c 写着「清第二套色板、两种红/两种蓝」，
但 **D2 门的 `fix` 豁免清单已经空了**（只剩 `keep`）⇒ **色值散值已归零**；且
`logic/SemColors.h` 里那**两档红是有意区分的**（`red` #DC2626 = 危险/读不出来；
`stale` = 停滞告警、托盘专用），注释里**明写「不是笔误」** ⇒ 「修两种红」是**过时**的要求，
真合并反而丢语义。⇒ M3c 剩下真正未做的是：图标名 / 动效 / 响应式 / HiDPI / 分隔线 / 托盘 busy 态。
（**托盘 busy 态暂不做**：deepin 托盘是**自创**的 —— **mac 侧根本没有托盘**（无 `NSStatusItem` 引用）
⇒ 无对位可抄；且托盘**弹窗**里的 busy 态**已经有了**（`BusyRow` 转圈）。）

**视觉变化**：无（打包与验收层，界面未动）。

### 批 AE：D7 的另一半「装得上」+ PLAN 入口校准

**① D7 的「装得上」那一半**（批 AD 的准验收只覆盖了「产物自洽」）：
`build-deb.sh` 原有的 **2f** 验的是「依赖清单里的包**本机装着**」（`dpkg-query`）——
那**不等于**「**目标机装得上**」：开发机装着的包可能来自私有源、或已从源里移除
⇒ 目标机（干净 deepin 25）会「找不到包」⇒ **deb 装了却用不了**。
⇒ 新增 **2h**：「每个依赖包在 **apt 仓库**里都有候选（`Candidate:` 不是 `(none)`）」。
⇒ 实测：本机 deepin 25 源里 **17 个依赖包候选齐全，缺失 0** ✓。

**⚠⚠ 踩坑：apt 的输出是「本地化」的** —— 本机是中文「候选：」而不是 `Candidate:`。
只按英文写脚本，换台机器/换 locale 就**全部误判成缺失**（实测：17 个明明存在的包全被判「查不到」）。
⇒ **判据脚本里凡碰 apt 输出，必须 `LC_ALL=C`**。
⚠ **2h 与 2f 的分工**：2f 抓「包名写错 / 本机没装」；2h 抓「本机装着、但目标机源里没有」。

**② PLAN 入口校准（5 条，每条附实测证据）** ——
⚠ **台账是对的、PLAN 是错的**（M1-3 那条台账早就写明「正解不是迁 SNI」，PLAN 标题还写着
「托盘迁移 SNI」）⇒ **照 PLAN 做事会走错方向**：

| 条目 | 校准 | 实测证据 |
|---|---|---|
| M0-11 固定文档页四语言 | `[~]` → **`[x]`** | 16 篇正文齐全 / 同类目两两不同 / 英文无汉字 / 日文有假名 / 小节数一致；接线门 466 项；四语言**行为**探针本轮重跑仍绿 |
| M1-3 托盘 | **方向订正**：deepin 走**托盘窗口协议**，不是 SNI | 批 Y 实测 + 本轮读到 `m_sniMode` 分支；**mac 侧根本没有托盘**（无 `NSStatusItem`/`NSStatusBar` 引用）⇒ 无对位可抄 |
| M3b 组件化 | 标注**主体已全部完成**，只剩 KPI 骨架屏 + 真机目检 | 本轮实测：`src/ui/common/` **17 个组件**、散落的次级标签样式 **0 处**、`SegmentedButton` **只一份** |
| M4b `scripts/ci.sh` | 「deb 构建未做」**已过时** | 本轮实测：ci.sh **12 门**（第 11 门 deb 构建、第 12 门 deb 布局验收）全绿；只剩「系统 Qt6/DTK6 矩阵」 |
| M2-7 deb 打包 | 补批 AD 的准验收与批 AE 的 2h | 见上文批 AD 与本节 ① |

⇒ 负控 **3/3 真红**（2h 判成「源里没有」⇒ 构建失败；禁用 2h ⇒ 那行输出消失；复原后恢复），
**累计 27/27 真红**。

**③ 元教训**：台账与 PLAN 是**两个入口**，「台账对、PLAN 错」真实存在 ⇒ 纪律：
**每批动手前先用代码/门实测核对 PLAN 那一行的现状**，并把核对结果**写回 PLAN**
（否则下一批还会照着过时描述做）。

**视觉变化**：无（打包与文档层，界面未动）。

### 批 AF：引擎安装改「旁路构建 + 探活通过后切换」（装坏包不许毁掉已有引擎）

**① 这是批 AB 埋下的、当时没看见的代价**：批 AB 修了「坏包」（`runtime/lib/` 空）本身，
但**没问「坏包装上去会怎样」**。⚠ 实测（原实现）：

```
旧引擎 version → "old 0.9.9"     （用户已装好的、能跑的）
--engine-download <坏包>
旧引擎 version → "boom"          （被顶替成跑不起来的了）
```

⚠ **不是「删掉」，是「顶替」** —— 而且**没有备份、无法回滚**。
原实现的顺序是 **「先删旧引擎 → 再解包新的 → 最后才探活」**：
`onExtracted()` 里 `QFile::remove(moongit)` + `removeRecursively(bin/)` + `removeRecursively(runtime/)`
**先于**新包落盘，而探活（`onInstalled()` → `onProbed()`）**在其后**。
⚠ 这在 v0.2.0 那个坏包上是**真实发生过**的。
⚠ 更隐蔽的后果：坏引擎**占着 `~/.local/libexec/deepdolphin/moongit` 这个位置**
⇒ 引擎发现链会找到它 ⇒ 应用以为「引擎在」⇒ 一调用就报错。

**② 改成「旁路构建 + 通过后切换」**：

| 步骤 | 旧 | 新 |
|---|---|---|
| 解包去向 | 目标目录（**先删旧**） | **旁路目录** `<dir>.staging`（**不碰**目标目录） |
| 探活 | 切过去之后才探活 | 在**旁路**里探活 |
| 切换 | 解包即覆盖（非原子，中途失败留半个引擎） | **改名**（同一父目录 ⇒ 同一文件系统 ⇒ 原子） |
| 失败后果 | 旧引擎被顶替成坏的 | **旧引擎原封不动** |

切换序列：旧的挪进 `<dir>.backup` → 旁路**改名**成目标目录 → 确认成功才删 backup；
中途失败 ⇒ 从 backup **回滚**（不让用户落到「没有引擎」的状态）。

**③ 顺带补上「拒绝降级」**：下载到的版本比已装的**旧** ⇒ 拒绝（`stage=versionDowngrade`）。
⚠ `releases/latest` 理论上不会降级，但**用户自己装过更新的版本**（或 owner 撤回了 release）
就会降级 ⇒ 把能用的换成不能用的。
⚠ **版本未知时不判降级**（解析失败不该挡掉一次合法升级 —— 挡错的代价更大）。

**④ 判定层新增的纯函数**（`logic/` 零 QWidget 头 ⇒ 可单测）：
`stagingDir()` / `backupDir()` / `hasInstalledEngine()` / `engineFingerprint()` /
`parseEngineVersion()` / `compareVersions()` / `isDowngrade()` / `preserveNote()`。
⚠ `parseEngineVersion()` 必须**锚定 "Engine" 且中间不许跨词**：
探活输出是 `moonGit Engine 0.2.1 (Cangjie 1.0.5 LTS)` —— 括号里的 `1.0.5` 是**仓颉 SDK** 的版本；
`engine[^0-9]*` 会跨过 " (Cangjie " 抓到它（**负控照出来的真 bug**）⇒ 改成 `engine[^0-9a-zA-Z]*`，
且**文本里有 "Engine" 时不许再退回「全文第一个 x.y」**。
⚠ `compareVersions()` 必须按**数字段**比：`0.2.10 > 0.2.9`（字符串比会判反）。

**⑤ 「原引擎保住了」是实测，不是承诺**：
新增 `engineFingerprint()`（mtime + 大小）⇒ 安装开始时记一份、失败时复查一遍。
⚠ 单看「文件还在」证明不了「没被动过」（负控照出「还在但内容已被顶替」）⇒ 用指纹比对。
⇒ `--engine-download` 的输出多了 `installedVersion` / `keptPrevious` 两个字段。

**⑥ 判据**：
- selfcheck **388/0**（+7）
- 契约门第 21 组 **120/0**（+7 **行为门**：装坏包⇒旧引擎原样保留 / 装坏包后无旁路残留 /
  拒绝降级且旧引擎不动 / 版本更高⇒升级成功且跑的是新版本）
- ⚠ 新增失败分类 `versionDowngrade` ⇒ 「失败要说清是哪一种」从 **7 种变 8 种**（判据同步改）

**⑦ 负控 6/6 真红**（累计 **33/33**）：执行层改回「就地覆盖」⇒ 旧引擎被毁 /
版本解析不锚定 ⇒ 取到 SDK 版本 / 版本比较改成字符串比 ⇒ `0.2.10 < 0.2.9` /
版本未知也判降级 ⇒ 误挡合法升级 / 旁路目录改成目标目录的**子目录** ⇒ 切换不原子 /
去掉降级拦截 ⇒ 能用的被换成不能用的。
⚠ **其中 2 项负控第一轮是「无效」的**（判据没红）⇒ 照出两个真问题：
① 复现脚本只查「文件还在不在」，漏掉「还在但被顶替」（⇒ 改成查**内容**）；
② `parseEngineVersion` 的 fallback 太宽松，负控改动**蒙对**了 ⇒
补了能分叉的夹具 `moonGit Engine (Cangjie 1.0.5 LTS)`（期望：**认不出来**），
**并因此照出真 bug**（`engine[^0-9]*` 跨词抓到了 SDK 版本）⇒ 收紧正则。
⚠ **第二轮又有 1 项无效** ⇒ 真相是**负控补丁编译失败被静默吞掉**（给 `const QString&`
形参赋值 ⇒ 编译不过 ⇒ 二进制根本没换 ⇒ 负控「假跑」）⇒ 负控脚本加 `build_or_die`
（**编译必须检查退出码**，否则「判据不够强」与「负控根本没生效」会被混为一谈）。
⇒ **负控无效不是白跑**：它照出的是「判据不够强」或「实现有 bug」，两条都真。

**⑧ 元教训**：**「装得上」不等于「装得安全」** ——
批 AE 补的 2h（依赖在 apt 源里有候选）验的是「**装得上**」，
批 AF 这条验的是「**装坏了会怎样**」。
⇒ 交付一条「装」字头的链，要问两个问题：**装得上吗？装坏了会毁掉已有的东西吗？**

**视觉变化**：无（引擎获取链层，界面未动）。

### 批 AG：让「文案全在判定层」这条纪律**有牙**（门盯的东西与文档说的不是一回事）

**① 起因**：批 AE 立了纪律「每批动手前先用代码/门**实测核对**台账与 PLAN 那一行」。
本批照做，从批 AA 那条纪律入手查 ⇒ **两处文档**（README 决策 202、台账 E.1j 纪律 2）
都写着「UI 里一个中文字面量都不许有，接线门 `arch_forbid` 盯」——
⚠ **而那道门盯的是 `QStringLiteral(`**：**说法比门宽** ⇒
`QString::fromUtf8("中文")` / `tr("中文")` / 直接字面量**全都绕得过去**。

⚠⚠ **元教训 1：「门有没有」和「门盯的是什么」是两件事** ——
本批一度以为「门根本不存在」（grep 只搜了 `arch_forbid_tree`，漏了单文件版 `arch_forbid`），
查证后才发现门**在**，只是**盯的东西与文档说的不是一回事**。
⇒ **断言「门不存在」之前，要把同类门（单文件版 / 整树版）都搜一遍**。
⚠ 而且**文档写得比门宽**这件事，**比门缺失更隐蔽**：门在、门绿、文档说「有门管着」。

**② 补门（盯内容，不是盯写法）**：新增 `arch_forbid_han` ——
- 盯**字符本身**（汉字与中文标点，UTF-8 U+3000–U+9FFF），不盯任何 API 名字
  ⇒ 换写法绕不过去；
- ⚠ **必须剥块注释**：现有 `strip_comments` 只剥**行注释**（perl `-p` 逐行）
  ⇒ 块注释里的中文说明会**假红**（门一加就红 ⇒ 门会被当噪音关掉）⇒ 新函数自己剥块+行；
- ⚠ 没有 perl 时**显式 SKIP**（不算通过）—— 宁可少一道门，不要一道会假红的门；
- 范围：**文档窗四件套**（`DocsDialog.{cpp,h}` + `DocsDialogProbe.{cpp,h}`）；
  判定层 `logic/DocPages.cpp` 里的中文是**16 篇正文**，本来就该在那儿。

**③ 文档订正（3 处）**：README 决策 202 / 台账 E.1j 纪律 2 / 台账 E.1j 判据段 ⇒
说清「门盯的是**内容**」+ **范围仅限文档窗**；
⚠ 并明确写下：**「全应用 UI 零中文字面量」是 M2-5 的待办**（要人工翻译），
**不是已达成** —— 不许把待办写成纪律。

**④ 顺带核实 M2-5 的规模数字（口径要写清）**：

| 口径 | 去重数 |
|---|---|
| 剥注释后**全部**中文字符串字面量（含判据描述 437 / 夹具 23 / 16 篇正文 56） | **1520**（91 个文件） |
| 再排除上面三处**非用户可见**的 | **1019** |
| 台账原记 | **1008** |

⇒ **原数字是对的**（差 11 是口径微差）⇒ **不改数字**，但**把口径写进台账**：
⚠ 否则下一个人按「全量 1520」去对照台账，**会以为台账错了** ⇒ 照着做会走错方向。

**⑤ 判据**：接线门 **470 项**（+4）、负控 **2/2 真红**（累计 **35/35**）：
塞 `QString::fromUtf8("中文")` ⇒ 新门红（**旧门抓不到**）；
塞含中文的**块注释** ⇒ 门**不红**（证明它不假红）。

**⑥ 元教训 2**：**纪律的强度要看「门盯的是什么」，不看「门在不在」** ——
一道盯写法的门和一道盯内容的门，在「有没有门」这个粒度上看起来一样，
在**能不能守住**这件事上差一个量级。

**视觉变化**：无（门与文档层，界面未动）。

### 批 AH：引擎缺失首屏接上下载入口 + 安装指引文案归判定层（顺带照出一批**死基线**）

**① 起因（实测）**：引擎缺失时，用户**第一眼**看到的是首屏 `SetupGuidePage`。
而那时的首屏**只有**一个「重新检测引擎」——
⚠ **下载链只在设置页**（`GeneralPane`）⇒ 用户得先知道「设置里有」才用得上；
⚠ 首屏的提示文案还让用户去跑 `moonGit/scripts/install.sh` ——
那是**仓库里**的脚本，拿到 deb 的普通用户**根本没有那个仓库** ⇒ **指了一条走不通的路**。

**② 改法**：
- 首屏加**主操作**「下载并安装引擎」（`DPushButton`），
  `downloadClicked` → 面板 → `m_model->downloadEngine()`；次操作仍是「重新检测引擎」；
- ⚠ **互斥禁用**：探测中/下载中两个按钮都不许点
  （两条链都在动引擎目录 ⇒ 互相干扰；下载中重探会探到**半装**的目录 ⇒ 结论是假的）；
- 判定层 `logic/EngineDownload` 持有全部下载文案：
  `installHint()`（中性措辞，不提「上面/下面」——判定层不知道界面长什么样）、
  `downloadActionLabel()` / `downloadActionTooltip()` / `downloadBusyLabel()` /
  `downloadStatusText(found, pending, downloading)`（**四态**）；
- `AppModel` 转发 4 个 getter（**界面不自己读判定层**，与 `GeneralPane` 同一纪律）；
- `EngineLocator::installHint()` 改为**转发**判定层（旧文案弃用）。

**③ ⚠⚠ 照出的真问题：同一句文案三处各写一遍** ——
动手前先 grep，发现动作标签「下载并安装引擎」在**三处**硬编码
（首屏 1 + 设置页 2），悬停说明**逐字**抄了两遍。
⇒ **同一句话两个真相源 ⇒ 改一处漏一处** ⇒ **本批自己差点违反批 AG 刚立的纪律**。

**④ 补门 `arch_forbid_text_dup`（盯内容，不是盯写法）**：
- 清单 = 判定层 `logic/EngineDownload.cpp` 里的**中文串字面量**（≥4 字符）
  ⇒ **判定层改了文案，界面层的副本自动进清单**（不手工维护名单 ——
  手工名单会漏，漏了就等于没门）；
- 扫 `src/ui/` 全树，**先剥块注释 + 行注释**（注释里提到这句话**不算**抄）；
- 盯**逐字相同**，不盯任何 API 名字（与批 AG 同款道理）；
- ⚠ **范围要写清**：只取 `EngineDownload.cpp`（本批的下载文案真相源），
  其它判定层的中文串（失败分类文案等）**不在**本门范围里；
- ⚠ 没有 perl ⇒ **显式 SKIP**（取不到清单就跑 = **假绿**，比假红更坏）。

**⑤ ⚠⚠ 照出「死基线」**：`docs/snapshots/{dark,light}-setupguide.png` 是**死基线** ——
`--snapshot` 只支持 `dashboard|board|milestones`，**拍不出 setupguide**；
`ci.sh` 第 2 门也只拍那 6 张 ⇒ **引擎缺失首屏从来没被任何门覆盖过**
（git log：这两张最后一次重拍在 `73b48d5`）。
⚠ **死基线比没基线更隐蔽** —— 它让人以为「首屏有视觉保障」。
⇒ 改法：`--section setupguide`（**强制无引擎态**：不调 `locate()` ——
它的结果**依赖本机环境** ⇒ 基线不可逐字节重现；显式构造**通用缺失态**）；
⇒ `ci.sh` 纳入 2 张 ⇒ 「重拍比字节」「换宿主时区比字节」两道覆盖它；
⚠ 该段**不喂夹具**（要拍的是「没有引擎、没有项目」的样子）；
⚠ 该段**跳过「空态=失败」检查**（必然没项目）⇒ 改用
**「拍到的确实是首屏」**（新增 `PanelWindow::showingSetupGuide()`）来防空门 ——
⚠ **文件名对不等于内容对**。

**⑥ 判据**：selfcheck **391/0**（**+3**）、接线门 **488 项**（**+18**）、
ci.sh **12/12**、契约门 **120/0**、快照 **8 张**两次重拍逐字节一致 + 换宿主时区后仍一致
（⚠ 快照**只有那两张**变化，其余 6 张**零变化**）；
负控 **6/6 真红**（累计 **41/41**）。

**⑦ 元教训 1：纪律立下后，下一批就要用它检查自己** ——
批 AG 刚把「文案全在判定层」立成纪律，批 AH 动手第一件事就是 grep，
结果**三处重复** ⇒ 差点自己违反。
⇒ 纪律不是写给下一批看的，是**每批开工前用来检查自己**的。

**⑧ 元教训 2：死基线比缺基线更隐蔽** ——
「没有基线」是明摆着的缺口；「**有一张没人比、拍不出来的基线**」看起来像有保障。
⇒ 每次动基线都要问一句：**这张图现在真的被某道门拍、真的被某道门比吗？**

**视觉变化**：**有** —— 首屏多了「下载并安装引擎」主操作按钮
（明/暗两张首屏基线重拍，其余 6 张零变化）。

### 批 AI：M1-4 收尾（通知时长可配）+ 通知顶替规则下沉判定层 + **M1a 入口校准**

**① 起因**：PLAN M1-4 的四个子项里三个已做
（`desktop-entry` hint / `image-path` / `replaceId` 按类别顶替），
只剩**「`timeOut` 由 Settings 驱动」** ⇒ 实现里硬编码 `.timeOut(5000)`。

**② ⚠⚠ 顺带照出「说法与实现相反」**：`app/Notifier.h` 的头注释写着
「每条通知独立送达、互不顶替、**不用 replaceId**」——
而实现**一直用着** `replaceId` 顶替状态型通知（M1-4 改 `Notifier.cpp` 时没回头改头注释）。
⚠ **「说法与实现相反」比「说法缺失」更危险**：缺失会引人去查代码，
相反的说法会让人**照着它改代码**（把顶替逻辑删掉，理由是「注释说不用」）。

**③ 顶替规则下沉判定层**（`logic/Notifications`，零 QWidget 头）：
`categoryOf(title)` / `replacesPrevious(title)` / `normalizeTimeoutMs(ms)`。
⚠ 原来规则写在执行层（要 **D-Bus 会话**才跑得到 ⇒ **无头测不到**）⇒ 规则改了没人发现。

**④ ⚠ 时长必须归一**：D-Bus `expire_timeout` 的语义是
「毫秒；**0 = 永不消失**；-1 = 服务器缺省」
⇒ 0 绝不能原样传（通知赖在通知中心不走）；
越界值会让「设定的」与「看到的」不一致 ⇒ 一律夹进 `[1s, 10min]`，非正取缺省 5s。

**⑤ 设置页加「通知」卡**（下拉 5/10/30/60 秒，选中即写回）：
⚠ 回填时若设置里的值**不在档位里**（手工改过配置文件）⇒ **如实加一项显示它**，
绝不「显示 5 秒、实际是别的」；⚠ 回填**不写回**（否则「打开这一页」本身就会改设置）。

**⑥ ⚠⚠ M1a 入口校准（照批 AE 纪律：动手前先实测核对 PLAN 那一行）**：

| PLAN 点名 | 实测（DTK6 6.7.47） | 落点 |
|---|---|---|
| `DListView` | ✅ 存在（**57 符号**） | 侧栏用的是 `QListWidget`（**item-based**）⇒ 换过去要**重写数据模型** |
| `DTreeView` | ❌ **不存在**（**0 符号**、无头文件） | **8 处 `QTreeWidget`** ⇒ **换不了** |
| `DBlurEffectWidget` | ✅ 存在（76 符号） | 托盘弹窗自绘窗口（代码里已标「模糊留给后续」）⇒ 需真机验收 |
| `DButtonBox` | ✅ 存在（28 符号） | 对话框用 `DDialog::addButton` ⇒ **当前无落点** |

⇒ ⚠ **PLAN M1a 那一行是失真的**：四个里**一个不存在**、**一个没落点**、
**一个要重写架构** ⇒ 已写回 PLAN。
⚠ **命名坑**：DTK 的 `DTreeWidget/`、`DListWidget/` 是**主题资源目录，不是类**
⇒ 只 `ls` 目录会误以为组件存在（本批第一轮就差点这么信）。

**⑦ ⚠⚠ 照出「空门」**：那道「过时说法不许复活」的门若用现成的 `arch_forbid`
（它**剥行注释**）⇒ 过时说法住在**注释**里 ⇒ 门**永远绿** ⇒ **空门**
（空门比没门更糟：给人虚假的安全感）⇒ 补 `arch_forbid_raw`（**不剥注释**），
并用负控证明它有牙。

**⑧ 判据**：selfcheck **393/0**（**+2**）、接线门 **503 项**（**+15**）、ci.sh **12/12**、
契约门 **120/0**、快照**零变化**；
**⑨ 负控 6/6 真红**（累计 **47/47**）。
⚠ **顺带订正批 AH 的负控计数口径**（脚本末尾「工作区已还原」的自检被算进了负控项
⇒ 数字偏大）⇒ 统一口径 = **只数变异项**。

**⑩ 元教训**：**「说法与实现相反」比「说法缺失」更危险** ——
凡是「注释/文档描述行为」的场合，**要有一条门让实现来对质**，
而不是靠人记得回头改注释。

**视觉变化**：设置·通用页多一张「通知」卡（下拉选时长）。

### 批 AJ：判据只许增不许减 + **拆掉 3800 行大函数**（M4a 的第一步）

**① 起因（两件事都是「承诺没有牙」）**：
- ⚠ **「判据不许被删」这句话，从来没有门**：`ci.sh` 第 1 门只断言
  「`0 failed` 且 **`≥58 passed`**」—— 58 是 2024 年的老数字
  ⇒ **删掉 300 条判据照样全绿**。判据是「契约的牙齿」，删一条就少一颗牙。
- ⚠ `src/app/SelfCheck.cpp` 是**一个 3800 多行的函数**（M4a 记的遗留债）。

**② 补门「判据数不许变少」**（`scripts/ci.sh`）：
基线 `SC_MIN=393` **写死在脚本里**（与既有「≥58」同一做法）⇒ 改基线 = 改脚本 = 评审看得见。
⚠ **刻意不用单独的基线文件**：那个文件会被顺手改小 ⇒ 门跟着一起松 ⇒ 等于没门。
⚠ 加判据时**同步把 `SC_MIN` 加一**（忘了加只是门**偏严**，不会偏松 ⇒ 安全方向）。
⚠ 口径 = **判据条数** ⇒ 抓不到「删一条又加一条」那种换名操作（少见）。

**③ 拆分（基础设施先行）**：新增 `src/app/SelfCheckInternal.h` ——
⚠ 关键点：**「记一条判据」必须只有一份实现**
（`check()` + `g_pass`/`g_fail` + `J`/`JO`，C++17 的 inline 变量/函数）。
⚠ 各分片各写一份 `check()` ⇒ 计数各数各的 ⇒ 汇总出来是错的
⇒ 而且是「**同名两处互相顶替**」的老坑。
⇒ 分片里写 `using SelfCheckInternal::check;`
⇒ 现有的裸调用 `check(log, "…", ok)` **一个字都不用改**。
- `SelfCheck.cpp` **3832 → 2547 行**；新分片：
  `SelfCheckDocs.cpp`（572 行：固定文档页 + 四语言 + 语法高亮）、
  `SelfCheckEngine.cpp`（903 行：图谱三件套 + 引擎获取 + 通知 + 引擎钩子）。
- ⚠ **依赖检查靠编译器**：搬段时缺 include / 缺变量，编译器立刻报
  ⇒ 不用通读三千行去核对依赖。

**④ 判据**：selfcheck **393/0**（**一条不少、一条不多** ⇒ 拆分无损）、
ci.sh **12/12**、接线门 **517 项**（**+14**）、契约门 **120/0**、快照**零变化**。
**⑤ 负控 3/3 真红**（累计 **50/50**）：删掉一条判据 ⇒ **ci.sh 第 1 门红**（`392 < 393`）／
删掉一条判据 ⇒ **接线门的覆盖门项也红**／分片自己写一份 `check()` ⇒ 接线门红。

**⑤b ⚠⚠ 拆分顺带照出三笔「门与文件绑死」的旧账**（都是拆完**当场变红**的）：
1. ⚠ **44 条接线门项**盯的是「判据在 **`SelfCheck.cpp` 这个文件**里」，
   而**意图**是「**判据覆盖了某个判定层**」⇒ 搬到分片后**集体变红**
   ⇒ 逼人「把代码搬回去」而不是「把门改对」⇒ 新增 `arch_need_any`
   （任一 `SelfCheck*.cpp` 命中即绿；**强度不变**：`SC_MIN` 盯着条数）。
   ⚠⚠ **批 AV 起该门型已被换掉**：`arch_need_any` **没有次数维度** ⇒ 改一处骗得过门
   ⇒ 换成 `arch_need_any_count`（恰好 N 次）/ `arch_need_any_min`（至少 N 次）。
2. ⚠ **D2 散值门的豁免清单绑死了 `SelfCheck.cpp`**
   ⇒ 判据夹具里的**期望色值**搬到分片后 **D2 门红**
   ⇒ 按「豁免必须**逐条登记**」的规矩登记两处 `keep`。
3. ⚠ **我自己的新门项正则太窄**：`^\s*void check\(` **抓不到** `static void check(`
   ⇒ **负控没抓到**（负控红不了 ⇒ 那道门等于没门）⇒ 放宽为 `void check\(`。
   ⚠ 这是本批第三次「负控照出真问题」。

**⑤c 元教训 3：门要盯「意图」，不是盯「位置」** ——
「判据覆盖了 X」是意图，「X 在哪个文件」是位置；
把位置当门 ⇒ 结构一变动门就集体变红 ⇒ 门从「守护」变成「阻拦」。

**⑥ 元教训 1：承诺没有门 = 承诺不存在** ——
凡是**承诺**（不许删、不许退化、不许变慢），都要有一条**能红**的门顶住；
否则它只是**让人放心**的句子。

**⑦ 元教训 2：拆分的验收标准是「条数不变」，不是「编译通过」** ——
编译通过只能证明「没搬坏语法」，搬漏一条判据照样编译通过。
⇒ 拆分**必须**配一条「条数不许少」的门，两者一起才是完整验收。

**⑧ 遗留（如实记，不假装做完）**：`SelfCheck.cpp` 仍有 **2547 行**
（段 15「图谱/架构图/Canvas2D/热力图/补丁体检」约 1100 行仍在里面）
⇒ **M4a 未完成**；`AppModel.cpp` 仍 1948 行 ⇒ 同样待拆。

**视觉变化**：无（判据与文件结构层，界面未动）。
### 批 AK：M4a 第二步 —— 图谱/热力图/补丁体检再拆一片（主文件降到 1451 行）

**① 起因**：批 AJ 把 `SelfCheck.cpp` 从 3832 行降到 2547 行，但**最大的一块还在里面**
—— 段 15「图谱/架构图 + 符号索引热力图 + 补丁体检」约 **1100 行**。

**② 改动**：段 15 整体搬进新分片 `src/app/SelfCheckGraph.cpp`（**1196 行**）
⇒ `SelfCheck.cpp` **2547 → 1451 行**（与 `AppModel.cpp` 1948 行同一量级
⇒ **单文件过大**这个债基本还清）。
⚠ 沿用批 AJ 的共享底座（`check()` + 计数 + `J`/`JO` 各只有一份实现）
⇒ 新分片 `using SelfCheckInternal::check;` ⇒ 裸调用一个字没改；
⚠ 依赖检查仍**靠编译器**（缺 include/缺变量编译器立刻报）⇒ 没通读那一千行去核对。

**③ ⚠ 顺带照出并修掉：「判据夹具的 D2 豁免」也绑死了文件** ——
判据夹具里写着**期望色值**（`HeatLayout::heatColor(79) == QColor(255,200,87)` 之类），
搬到分片后 **D2 散值门红** ⇒ 按「豁免必须**逐条登记**」的规矩登记 `keep`。
⚠ 这是批 AJ 同一笔账的**第二次**复发 ⇒ 「绑死文件」是**一类问题**，不是一处笔误。

**④ 判据**：selfcheck **393/0**（**一条不少、一条不多** ⇒ 拆分无损）、
接线门 **523 项**（**+6**）、ci.sh **12/12**、契约门 **120/0**、快照**零变化**。
**⑤ 负控 3/3 真红**（累计 **53/53**）：**在图谱分片里**删一条判据 ⇒ ci.sh 红／
图谱分片自己写 `check()` ⇒ 接线门红／**主片忘了调用图谱分片** ⇒ 接线门红。
⚠ N3 是新增的：代码搬走了**就忘接** ⇒ 判据凭空消失 ⇒ 必须有门顶住。

**⑤b ⚠ 负控脚本自己踩的坑：变异失败必须立刻退出** ——
N1 第一次跑「没抓到」，原因不是门坏了，而是**变异脚本没找到目标判据**
⇒ 脚本抛了异常，但 shell 没检查退出码 ⇒ 继续跑 ci.sh（当然绿）⇒ **负控「假跑」**
（批 AF 记的是「编译失败被吞」，这次是**变异失败被吞」——同一类病）。
⇒ 已加 `|| { echo "变异失败 ⇒ 负控无效"; exit 2; }`。
⚠ **凡是「让判据红」的步骤，失败必须让整个负控失败** ——
否则「负控没抓到」会被误读成「门有洞」。

**⑥ 元教训 1：「绑死文件」是一类问题，不是一处笔误** ——
连续两次（批 AJ 的接线门 44 条 + D2 豁免；批 AK 的 D2 豁免）都是
「门/豁免绑死某个文件名」⇒ 结构一变动就集体变红。
⇒ 纪律：**凡是「覆盖类」的承诺与豁免，一律写成「任一相关文件」**；
真正需要绑死单个文件的地方（比如「这个文件不许自己写 check」）才写死。

**⑦ 元教训 2：拆分的最后一步要单独有门** ——
「搬走就忘接」比「搬漏一行」更隐蔽：它编译通过、selfcheck 少几条、
门若没盯就会**静悄悄少掉一批判据** ⇒ 接线门专门加一条「主片调用了 X 分片」。

**⑧ 遗留（如实记）**：`AppModel.cpp` 仍 **1948 行** ⇒ **M4a 未完**；
但它比 `SelfCheck.cpp` **好拆**（它是**类**的实现 ⇒ 成员函数天然可分文件定义）⇒ 下一批按同一套路拆。

**视觉变化**：无（判据与文件结构层，界面未动）。
### 批 AL：M4a 收官 —— 拆 `AppModel.cpp` ⇒ **最大文件从 3832 降到 1451**

**① 起因**：M4a 记的两笔大文件债，`SelfCheck.cpp` 已在批 AJ/AK 拆完，只剩
`AppModel.cpp` **1948 行**（全仓第二）。

**② 改动**：`AppModel.cpp` **1948 → 1052 行**，拆成三片：
- `AppModel.cpp`（主片：生命周期/刷新/状态/仪表盘/里程碑/项目与文档/引擎配置）
- `AppModelGraph.cpp`（**161 行**：概览/符号详情/影响面/patch 技能）
- `AppModelUpdate.cpp`（**805 行**：更新/批量/git 操作/扫描/里程碑写入）
- 跨片共用的文件内辅助函数上 `src/app/AppModelInternal.h`（**inline ⇒ 只有一份实现**）

**③ ⚠ 与 SelfCheck 拆分的关键差别：这次零风险** ——
同一类的成员函数**天然可以分文件定义**（不像那个 3800 行大函数要拆成多个自由函数
+ 共享底座）。⚠ 前提只有一条：**分片之间不共享文件内静态**。

**④ ⚠⚠ 踩到的三个坑**：
1. ⚠ **匿名 namespace 的闭合行被漏掉** ⇒ 后面代码全落进匿名 namespace
   ⇒ 报「definition … is not in namespace enclosing 'AppModel'」
2. ⚠ **4 个文件内辅助函数两边都在用**（`kQuiet` / AI 配置快照 / `sortProjects`）
   ⇒ 只能上内部头；⚠ 但 `milestoneActionLabel` **只有更新分片用**
   ⇒ **留在分片里、不进共享头**（**能不放共享头就不放** —— 共享面越小越好）
3. ⚠ **辅助函数的搬走范围要按函数整体算**（只搬签名行 ⇒ 编译报「未声明」）

**⑤ ⚠⚠ 「绑死文件」第三笔账（同一类问题的第三次复发）**：
**38 条接线门项**盯的是「调用形态在 `AppModel.cpp` 里」⇒ 拆完**集体变红**
⇒ 把 `arch_need_any` 泛化出**可选的文件通配参数**（默认 `SelfCheck*.cpp`），
38 条改写。⚠ **强度不变**：any 化只放宽「在哪个文件」，不放宽「调用形态还在不在」
⇒ 负控 N2 证明（`callText` 换成 `callJson` ⇒ 门照样红）。
⚠⚠ **批 AV 补上了一个当时漏掉的洞**：any 化放宽了「在哪个文件」，
但**没有**引入「有几处」⇒ 跨文件多现仍能顶替 ⇒ 换成带次数维度的两个门型
（`arch_need_any_count` / `arch_need_any_min`）。

**⑥ 判据**：selfcheck **393/0**、接线门 **523 项**（**数量不变**：38 条是改写不是新增）、
ci.sh **12/12**、契约门 **120/0**、快照**零变化**。
**⑦ 负控 3/3 真红**（累计 **56/56**）：删掉分片里的成员函数定义 ⇒ **链接红**（漏搬必被抓）／
主片的契约调用形态走错 ⇒ **接线门红**（any 化后强度不变）／
分片里重复定义主片已有成员函数 ⇒ **链接红**（同名两处互相顶替）。

**⑧ 🎉 M4a 达成**：全仓最大文件从 **3832 行**降到 **1451 行**
⇒ 「单文件占全仓近 10%」这个债**还清**。

**视觉变化**：无（判据与文件结构层，界面未动）。
### 批 AM：M3c「响应式」—— AgentDialog 可缩放 + 定宽截断改省略号

**① 起因**：M3c 剩「响应式」这一项 ⇒ 动手前先实测核对 PLAN §3c 原文
（照批 AE 纪律）⇒ **三处对不上**。

**② ⚠ PLAN §3c 的「KPI 网格按窗宽 1/2/4 列（`resizeEvent` 改写列数）」是失真的**：
实测 deepin 侧**根本没有 `resizeEvent`**（4 张卡写死在 (0,0)(0,1)(1,0)(1,1)），
mac 侧是**固定 4 列**（`macos/.../DetailViews.swift:902-903` `LazyVGrid(count: 4)`）
⇒ 「1/2/4」是 deepin 侧的**无对位**设计 ⇒ **不做**，改记录实测结论（已写回 PLAN）。
⚠ 顺带照出 `DashboardPage` 的注释写着「宽 <980 由 resizeEvent 折 2 列」——
**与实现相反** ⇒ 已订正 + 加门盯住。

**③ ⚠ `AgentDialog` 固定尺寸 → 可缩放**：它是全仓**最后一个**固定尺寸的对话框
（其余 8 个都用 `setMinimumSize`），而 AI 助手的回复一长就被裁掉、也调不大
⇒ 照**同仓先例** `AiResultDialog.cpp:15`（「固定尺寸曾让长报告读不完且关不掉——必须可缩放」）改。

**④ ⚠⚠ PLAN 那句话的另一半「定宽截断改 `elidedText`」是真缺口** ——
实测全仓 `elidedText` **零命中** ⇒ 完全没做。
侧栏项目名原来只 `setMaximumWidth(120)` ⇒ QLabel 默认**直接切掉后半截**（半个字、无提示）
⇒ 改为 `elidedText` 省略 + **完整名进 tooltip**。
⚠ **零视觉变化**：现有快照基线**零变化**（夹具里的项目名短，省略号不触发）
⇒ 也说明**基线覆盖不到「长项目名」这一档**（记作遗留）。

**⑤ 判据**：selfcheck **393/0**、接线门 **529 项**（**+6**）、ci.sh **12/12**、
契约门 **120/0**、快照**零变化**。
**⑥ 负控 4/4 真红**（累计 **60/60**）：对话框改回固定尺寸 ⇒ 门红／
注释里写回那句过时话 ⇒ 门红／KPI 网格少入一张卡 ⇒ 门红／侧栏改回硬截断 ⇒ 门红。

**⑦ 元教训 1：PLAN 里的「行号 + 做法」是最容易失效的一类描述** ——
核对时发现 `ProjectProgressCard.cpp` **文件已不存在**（PLAN 引的 4 处里有一处是幽灵文件）
⇒ 照 PLAN 逐条做之前，**先 `ls` 那个文件还在不在**。

**⑧ 元教训 2：定宽截断在 Qt 里默认是「硬裁」** ——
`setMaximumWidth` 只限制宽度，QLabel **不会**自动加省略号
⇒ 凡是定宽显示长文本，都得**显式** `elidedText`。

**⑨ 遗留**：PLAN §3c 点名的另几处定宽截断**行号已漂移**，
本批只改了能定位到的**侧栏项目名**一处。

**视觉变化**：侧栏长项目名由硬裁改为省略号（**现有基线零变化**，夹具里名字短）。


### 批 AN：快照基线「逐字节可重现」是**假的** —— 修掉三个叠在一起的洞

**① 起因**：批 AH 修好 setupguide 死基线后留了个尾巴——
「一次 `ci.sh` 在快照段报『✗ 重拍失败：dark-setupguide』⇒ 偶发」。
本批按「拿不准就查」的规约**一路查到底** ⇒ 照出的东西比那个偶发失败大得多。

**② ⚠⚠ 洞一：同一份代码会拍出多种字节**（不是「偶发失败」，是「结果不确定」）。
压力实测：同机**并发混主题** 120 次 ⇒ **4 种**不同字节；纯主题并发 60 次 ⇒ 1 种；
**串行** 200 次 ⇒ 也有 ≈0.5% 出变体 ⇒ 基线会**悄悄漂**
⇒ 「基线必须逐字节可重现」这句承诺**当时是假的**。

**③ ⚠⚠ 根因（逐层实测，不是猜的）**：
1. 两张变体图**逐像素** diff ⇒ 差异 **100% 集中在 y[50..69]**（带外 **0 行**不同）；
2. 那 20px 正是 DTK 的**标题栏下沿阴影带** —— `DShadowLine::paintEvent` 读内嵌 SVG
   `titlebar_shadow_20px.svg`（渐变 `stop-opacity .1 → 0`）；
   实测**关掉阴影带后该区域变成纯背景色** ⇒ 坐实；
3. SVG 渐变带在不同负载下**铺开的高度不同**（整条渐变被压短/拉长）
   ⇒ **不是「还没画完」，是渲染结果本身不确定** ⇒ **等多久都没用**。
⚠ 排除过的假设（记下来免得后人重走）：D-Bus 共享配置
（`org.deepin.dtk.preference` 确实存在，但 `dbus-monitor` 实测**零调用**）、
dconf 写入（`dconf dump /org/deepin/dtk/` 为空、`user` 文件 mtime 长期不变）、
跨进程主题串扰（**串行**混主题也出变体 ⇒ 不是共享状态）。

**④ ⚠⚠ 洞二：「重拍比字节」门是「自己跟自己比」**。
`ci.sh` 第 2 步把新图**直接拍进 `docs/snapshots/*.png`**（**覆盖基线**），
后面的门再拿「刚覆盖完的基线」跟新拍的一张比 ⇒ **恒绿**
⇒ 「基线漂了」这道门**结构上就抓不到**（比的是本次产物 vs 本次产物）。
⚠ 连带后果：那句「CI 通过后请 `git diff docs/snapshots` 人工确认」也是空的
（基线刚被覆盖 ⇒ diff 永远为空）。

**⑤ ⚠ 洞三：拍后断言 ⇒ 偶发失败报成假红**。
setupguide 段的「拍到的确实是首屏」断言写在**拍完之后**
⇒ 万一那一刻还没切到首屏，报的是「重拍失败」（**红**），而**本可以**继续等它切过去
⇒ 判据**前移到拍前**（`settle.elapsed() >= 300 && showingSetupGuide()`），
拍后断言**保留**作最后一道防空门。

**⑥ 修法（三处都动了）**：
- `src/main.cpp`：快照路径调 `panel.setTitlebarShadowEnabled(false)`
  （**公开** API：`dmainwindow.h:108` public 段 ⇒ DTK 升级不会断）；
  为什么可以关：阴影带是**标题栏的装饰**，不承载任何信息，
  而基线的价值在「界面改了它会红」——装饰带的像素抖动只会制造**假红**；
- `scripts/ci.sh`：基线改为从 **git 里取**（`git show HEAD:deepin/docs/snapshots/...`），
  本次产物另存临时目录，两者比 ⇒ **视觉改动必须有人看过并提交**（不一致 ⇒ 退出码非 0）；
- `scripts/ci.sh`：加「**跨运行复拍**」段（新进程再拍一轮比基线）⇒ 抓跨进程漂移。

**⑦ ⚠ 快照基线重拍（8 张）**：差异**100% 集中在 y[50..69]** 那条阴影带，
带外**逐像素相同** ⇒ 画面内容零变化，只是去掉了那条会漂的装饰带。
色卡（`*-colors.png`）**零变化**（它不画标题栏）。

**⑧ 判据**：selfcheck **393/0**、接线门 **534 项**（**+5**）、ci.sh **12/12**、
契约门 **120/0**。
⚠ `cmp -s` 的**精确计数门**从 2 改成 **4**（批 AG 纪律：门盯的东西变了，强度要跟着变）。

**⑨ 负控 5/5 真红**（累计 **65/65**）：删掉「关阴影」⇒ 拍出 4 种字节（缺陷回来）／
删掉「关阴影」⇒ 接线门红／把拍前条件退回「只等 300ms」⇒ 接线门红／
**基线换成变体图 ⇒ ci.sh 跨运行复拍段红**（这条抓出的是洞二本身）／
快照命令改回「| tail -1」⇒ 接线门红（这条盯住洞四）。

**⑩ 元教训 1：「基线必须可重现」这句承诺，要用**跨运行**的证据来验** ——
同一次运行内拍两次一致，只能证明「这次没飘」。
⚠ 洞二的形状是「每次都一致，但每次一致的东西不一样」⇒ 只有新进程比才抓得到。

**⑪ 元教训 2：⚠ 门会拿「自己要比较的东西」当输入** ——
门比的是「基线 vs 新拍」，可基线**被门自己前面的步骤覆盖了** ⇒ 门在自证。
⇒ 凡是「拿 X 比 Y」的门，要先确认 **X 不是被这道门自己改出来的**。

**⑭ 元教训 4：⚠ 负控改完源码**必须重编**，否则测的是**旧代码**。
本批在收尾时用旧二进制拍基线，拍出的是**带阴影带的旧图**（59273 字节），
而 git 里的基线是关阴影后的新版（59257 字节）⇒ 一度以为「修法没生效」，
实际是**二进制没更新**（负控还原了源码但没重编）。
⇒ 负控脚本的 `restore` 现在**还原即重编**，且还原后**复核基线与 git 一致**。
⚠ 这条与「还原后必须 `touch`」是**两件事**：`touch` 只改 mtime（让 make 愿意重编），
**重编**才真的换了二进制。

**⑮ ⚠ 负控脚本**自己**的三条教训（本批踩的，写下来免得后人重走）**：
1. ⚠ **负控不许动主分支历史** —— 上一版负控用 `git reset --soft HEAD~1` 撤销
   「故意漂的基线」那个提交 ⇒ **把更早的、已推送的提交也一起回退了**
   （`b3468f7` 差点丢，靠 `git reflog` 找回）⇒ 改用**临时分支**
   （`git checkout -B`）⇒ 主分支历史一点不动。
   ⚠ 同理 `git reset --hard` 会**冲掉工作区里未提交的其它改动** ⇒ 一律不用。
2. ⚠ **还原源码后必须重编**（见元教训 4）⇒ `restore` 里直接 build。
3. ⚠ **判定「门红了没」不要 grep 门项的说明文字** —— 说明文字会随措辞变
   （本批门项说明改过一次 ⇒ 负控 grep 不到 ⇒ 明明门红了却判成「没红」）
   ⇒ 改成**数「✗」行**（`grep -q "✗.*<关键字>"`）⇒ 与措辞无关。

**⑫ 元教训 3：⚠ 第三方组件的**装饰性绘制**也会毁掉基线** ——
DTK 的阴影带是内嵌 SVG 渐变，渲染不确定 ⇒ 与我们代码无关，但**基线是我们的事**。
⇒ 找基线漂移时，先做**逐像素 diff 定位区域**，再问「这块是谁画的」。

**视觉变化**：8 张面板基线**去掉了标题栏下沿阴影带**（带外逐像素相同；色卡零变化）。

### 批 AO：PLAN §3c 点名的定宽截断 —— **逐处实测**后 4 处行为各不相同

**① 起因**：批 AM 把 PLAN §3c 点名的 4 处定宽截断留给后续（PLAN 里的行号已漂移）。
本批按「拿不准就查」的规约**逐处实测核对** ⇒ 结论**不是「4 处都改」**——
**4 处的行为各不相同**，一刀切会改错。

| 处 | 原来的做法 | 实测行为 | 本批 |
|---|---|---|---|
| `src/ui/pages/ProjectProgressCard.cpp` 项目名 | 手工掐中间（**按字符数 24**）+ `setMaximumWidth(220)`（**按像素**）**同时**存在 | **两条截断互相打架** ⇒ 仍硬裁（半个字） | **改**（只留按像素的 `elidedText(ElideMiddle, 220)`） |
| `src/ui/pages/DashboardPage.cpp` 活跃项目 headline | `setMaximumWidth(300)` | **真硬裁**（内容来自引擎，长度不受控） | **改**（省略号 + tooltip） |
| `src/tray/TrayPopupWindow.cpp` 项目名 | `setFixedWidth(120)` | **真硬裁**（弹窗宽固定、项目名长度不受控） | **改**（省略号 + tooltip） |
| `src/ui/SidebarNav.cpp` **固定视图行** | `setMaximumWidth(120)` | 文本短、**永不溢出** ⇒ 是兜底上限 | **不改**，但**原注释是错的**（已订正） |

**② ⚠⚠ 「两条截断打架」的实测**（13px monospace DemiBold）：
手工掐完的 **24 个中文**字仍 **268px > 220px** ⇒ `setMaximumWidth` 照样**硬裁**
⇒ 用户看到的是**半个字**（不是省略号）；纯 ASCII 时 164px 不超宽
⇒ **这个缺陷只在中文项目名下出现**（中文项目名很常见）。
⇒ 删掉手工截断，只留**一条按像素**的 `elidedText(ElideMiddle, …)`：
中段省略的意图保留（`/path/to/project` 的尾部目录名比掐尾部更有用），
按**像素**算 ⇒ 任何文字（中文/ASCII/emoji）都不会溢出成半个字；
完整名进 tooltip（原来手工截断后**看不到全名**）。

**③ ⚠⚠⚠ 顺带照出并修好一个旧布局缺陷（本批最大发现）**：
删掉 `name->setMaximumWidth(220)` 后**仪表盘快照变了** ⇒ 逐像素 diff 定位到
差异 100% 落在**两张项目卡的行 1**（行段 y[521..533] 与 y[693..705]）⇒ 查实：
名字标签**既是拉伸项（`addWidget(name, 1)`）又限宽** ⇒
Qt 把**多出来的空间塞给下一个 Preferred 标签**（那个 8px 的状态点标签被撑成 **88px** 宽，
而 pixmap 画在它**左边**）⇒ 视觉上「●」与状态词之间**裂开 ~86px 的缝**，
且整组**没贴到卡内右缘**。

**最小复现实测**（408px 行宽，同一控件结构）：
- 有 `maxWidth(220)`：name w=220 / dot w=**88** / state x=320 ⇒ 组未贴右、圆点与状态词脱开
- 无 `maxWidth`   ：name w=364 / dot w=**8**  / state x=384 ⇒ 贴右

⇒ 现在 name 吃掉全部余量，dot+state 自然贴右，
与 mac 侧 `DashboardParts.swift:247-258`（`Text` + `.truncationMode(.middle)` + `Spacer`）**一致**
⇒ 这条原来是 deepin 侧**单方面偏离 mac** 的地方。

**④ ⚠ 不用改的 3 处也留了注释**（免得下次误改）：
`WorkBar` 的 **DComboBox**（控件**自带**按宽度省略）／
`GeneralPane` 与 `MilestonesPage` 的 **DLineEdit**（超宽是**横向滚动**，不是硬裁）
⇒ 加省略号反而是倒退 ⇒ 「定宽截断改 `elidedText`」只针对 **QLabel**。

**⑤ ⚠ 订正一处过时说法**（批 AI 教训：说法与实现相反比说法缺失更危险）：
侧栏固定视图行的原注释写着「60 字项目名在最窄窗口截断**带省略号为预期行为**」——
① 那行**不是项目名**（项目名在 `rebuildProjectRows`，批 AM 已改）
② `setMaximumWidth` **不会**加省略号（Qt 默认是硬裁）⇒ 已按**实际行为**重写，
并加 `forbid_raw` 门不许复活。

**⑥ 门项 +10（接线门 534 → 544）**：
- 新增**跨行门** `arch_need_ml`（grep -E **按行**匹配 ⇒ 代码折行时 `elidedText(` 与参数
  不在同一行 ⇒ 门**匹配不到** ⇒ 门没牙 ⇒ 压成一行再匹配）；
- 新增「`name->setMaximumWidth` **不许复活**」+「名字标签**仍是拉伸项**」两道门
  （源码层提前拦「限宽 + 拉伸」这个组合；**视觉层由仪表盘快照基线兜底** ——
  重放这处改动 ⇒ 仪表盘快照变 ⇒ 视觉 diff 门红）；
- 加一道 `forbid_raw`：那句过时话不许复活。

**⑦ 判据**：selfcheck **393/0**、接线门 **544 项**、ci.sh **12/12**、契约门 **120/0**、
ci-d2 **0/0**；快照基线更新 `dark/light-dashboard.png`
（差异 1472 / 1488 像素，包围盒 x[540..719]，**只有两行段** ⇒ 全部是项目卡行 1 的重排）。
可重现性复核：每主题连拍 4 次 ⇒ **各 1 个唯一 md5**（逐字节可重现）。

**⑧ 负控 5/5 真红**（累计 **70/70**）：
项目名改回「按字符数 + 限宽」⇒ 接线门红／
headline 改回 `setMaximumWidth` ⇒ 接线门红／
托盘项目名改回 `setFixedWidth` ⇒ 接线门红／
侧栏注释写回那句过时话 ⇒ 接线门红／
**单独加回 `name->setMaximumWidth`（其余不动）⇒ 接线门红**（隔离「限宽 + 拉伸」这个组合）。

**⑨ 元教训 1：⚠ 「定宽截断」不是一个动作，是**一族行为** ——
`QLabel`（硬裁）、`DComboBox`（自带省略号）、`DLineEdit`（横向滚动）三者**都**「限宽」，
但**只有 QLabel 需要改**。⇒ 一条规则套到一族控件上，会把两个正常的控件改坏。

**⑩ 元教训 2：⚠ 限宽 + 拉伸 是个**会传染的组合** ——
限宽把余量从拉伸项身上挤走，Qt 会把它塞给**下一个 Preferred 标签**（本例是那个 8px 的状态点标签）
⇒ 受害的是**别的控件**（圆点与状态词脱开 86px），
而**改的人以为自己只改了名字标签**。
⇒ 「限宽」和「拉伸」不许同时出现在同一个标签上；余量要靠**显式的 stretch** 留白。

**⑪ 元教训 3：⚠ 改一处 UI 却看到**别处**的快照变了** —— 先别急着怀疑新代码 ——
逐像素 diff 定位到**行段**（本例只有 2 个行段，落在两张同类卡的同一行）⇒
立刻指向「同一个组件的同一行布局」，而不是「快照基线漂了」。
⚠ 本批顺手发现：仓里自带的 PNG 裁剪脚本**写 PNG 的长度字段把 chunk type 也算进去了**
⇒ 产出根本不是合法 PNG（`file` 报 `data`）⇒ 改用 PIL 重写裁剪器后才能肉眼比对。
⇒ **诊断工具本身也要验**（它给出的「差异包围盒」是对的，但「放大图」是坏的）。

**视觉变化**：仪表盘两张项目卡的**行 1 重排** —— 状态词（「正常」/「有未提交改动」）
从**脱离圆点 ~86px 且不贴右**变成**贴着卡内右缘**（与 mac 侧 `Text`+`Spacer` 一致）；
项目名由硬裁改省略号；深色 1472 像素 / 亮色 1488 像素，
差异**只在** y[521..533] 与 y[693..705] 两行段。

### 批 AP：M3c HiDPI —— 自绘位图按 dpr 放大（11 处 1x 自绘在 125%/150%/200% 下发虚）

**① 起因**：PLAN §3c 写着「9 处 1x 自绘 ⇒ 改 `platform::dpiPixmap()`」。
但那份名单**写在 `IconResolver` 存在之前**（`IconLoader.cpp` 早已被批 AI 当死代码删掉）
⇒ 照 PLAN 做会**漏**。本批**实测扫全**（grep 全部 `QPixmap` 构造 + 全部 `QPainter` 用法），
发现真正要改的是 **11 处**，且它们分成**两类**：

| 类 | 处数 | 判据 | 处置 |
|---|---|---|---|
| **离屏画到 pixmap**（`QPixmap pm(8,8)` + `QPainter p(&pm)`） | **11** | 位图缓冲区是**设备**像素，控件按**逻辑**像素画 ⇒ 缩放时被放大 ⇒ **发虚** | 改走 `platform::dpiPixmap()` |
| **直接画在控件上**（`QPainter p(this)`） | 8 | 控件的画布**本身就是** dpr 分辨率 ⇒ 画出来天然清晰 | **不用改** |

11 处明细：状态点 5（`LegendRow` / `ProjectProgressCard` / `DashboardPage` /
`ProjectDetailPage` / `SidebarNav` 汇总点）、托盘 3（`TrayPopupWindow` 大点 + 迷你条 +
`TrayController` 图标）、里程碑五态图标 1（`MilestoneRowWidget`）、
`IconResolver` 2（qrc 染色 SVG + 占位圆点）。
⚠ `Canvas2D` 的阴影**不用改**：它按**设备像素**画（`dev->width()` + 继承 transform）。

**② ⚠⚠ 为什么 1x 位图会发虚（实测，不是猜）**：
原来都是 `QPixmap pm(8, 8)` ⇒ 8×8 **设备**像素；
缩放到 200% 时控件要画 8 **逻辑**像素（= 16 设备像素）⇒ 位图被**放大** ⇒ 锯齿。
**实测**（同一个 8×8 逻辑圆点，dpr=2）：1x 路径的边缘只有 **6 层**半透明过渡，
dpr 感知的是 **11 层** ⇒ 差别**可量化**。

**③ 修法**：新增 `src/platform/DpiPixmap.{h,cpp}` ——
`platform::dpiPixmap(logicalSize)` 按 `logicalSize × dpr` 开缓冲区并
`setDevicePixelRatio(dpr)` ⇒ QPainter 在其上**仍用逻辑坐标**画
（Qt 自动按 dpr 缩放坐标系）⇒ 图形**尺寸不变、像素密度对了**。
⚠ 与 `platform::icon()` 的**分工**：`icon()` 走**图标主题**（那边自己按 dpr 取图）；
本助手只管**我们自己用 QPainter 画**的那些。

**④ ⚠ 判据分两层（第二层差点是空门）**：
- **结构事实**（探针 + CI 门）：`dpiPixmap=` 那行必须满足
  **缓冲区 = logical × dpr** 且 pixmap 的 `devicePixelRatio` **== 应用 dpr**。
- **效果事实**：`dpiEdgeLevels=` 的 aware 必须**多于** legacy。
  ⚠⚠ **dpr=1 时两列必然相同**（同一张 8×8 图）⇒ 那一跑**不比较**；
  ⇒ **另用 `QT_SCALE_FACTOR=2` 再跑一次**（dpr=2，实测 `devicePixelRatio=2`）来执行这一条。
  **不然这条断言永远是空的**（批 AJ 教训：承诺没有门 = 承诺不存在）。
  ⇒ 并加一道门：**`QT_SCALE_FACTOR=2` 那一跑不许被删**（掏空它 = 效果断言变空门）。

**⑤ 源扫描门 +24（接线门 544 → 568）**：11 个调用点必须走 DPI 助手、
9 个文件里**不许**再开 1x 位图、探针必须报出 dpi 事实、
以及上面那条「dpr=2 那一跑不许被删」。另把 `DpiPixmap.cpp` 加进 ci.sh 的
「新文件必须进构建」登记门。

**⑥ 影响面**：只改**自绘位图的分辨率**，不改任何逻辑、布局与配色。
**dpr=1（100%）下 `dpiPixmap` 与原写法逐字节等价 ⇒ 快照零变化**（已复核）。
⚠ `IconResolver` 的 qrc 染色 SVG 那条路径本机**编不到**
（无 Qt6Svg 开发头 ⇒ `DD_HAVE_QTSVG` 未开）⇒ 它的正确性靠**评审**，不靠本地构建。

**⑦ 判据**：selfcheck **393/0**、接线门 **568 项**、ci.sh **12/12**、契约门 **120/0**、
ci-d2 **0/0**；快照**零变化**。

**⑧ 负控 5/5 真红**（累计 **75/75**）——⚠ **头一次跑只有 3/5**，两条没红，
查出的是**真问题**（见⑫）：调用点退回裸 `QPixmap` ⇒ 接线门红／
助手不按 dpr 放大缓冲区 ⇒ **运行时门**红／
助手不设 `devicePixelRatio` ⇒ **运行时门**红／
探针**代码里**的格式串改掉 ⇒ 接线门红／
**把 `dpr=2` 那一跑改成 1x（门被掏空）⇒ 接线门红**。

**⑨ 元教训 1：⚠ 「HiDPI 有问题」这句话，在 dpr=1 的机器上**永远看不出来** ——
本机默认 dpr=1 ⇒ 改前改后**像素完全一样** ⇒ 任何「跑一遍看看」的验证都是空的。
⇒ 判据必须能**主动把 dpr 抬上去**（`QT_SCALE_FACTOR=2`，实测 `devicePixelRatio=2`）
⇒ 且「抬 dpr 那一跑」本身也要有门盯着（不然会被当成冗余删掉）。

**⑩ 元教训 2：⚠ 诊断「自绘」要先分清**画到哪里** ——
画到 **pixmap** 的要按 dpr 放大；画到**控件**上的**本来就对**。
⇒ 11 处改、8 处不改 —— 把「所有 QPainter 都改一遍」会**改坏本来正确的 8 处**。

**⑪ 元教训 3：⚠ 探针里的色值也要守 D2（色值单一真相源）** ——
本批探针第一版写了 `QColor(80, 160, 255)` ⇒ **D2 门当场抓红**
⇒ 改走 `DS::semColor(DS::SemColor::accent)`。
⇒ 纪律**不因「只是探针」而破**。

**⑫ 元教训 4：⚠⚠ 门盯的**字面串**也可能出现在注释与提示语里** ——
本批负控**头一次只有 3/5**：两道门盯的是 `QT_SCALE_FACTOR=2` 与 `dpiEdgeLevels=`，
而这两个串**在注释与错误提示语里也出现** ⇒ 把真正的那行改掉，**门照样绿**
⇒ 门被**措辞**满足了。⇒ 收紧成盯**代码构造**（格式串 / 那一跑的命令）后 5/5。
⚠ 另一条同源的坑：变异脚本若只替换**文件里第一次出现**的字面串，
很可能改到**注释**上 ⇒ 等于没改 ⇒ 负控会给出「门没红」的**假结论**。

### 批 AQ：mac 侧引擎下载链**从来没成功过** —— 三个叠在一起的错

**① 起因**：mac 侧 `build.sh` 的「本地没有引擎就从 GitHub Releases 下载」那条路径
**从来没成功过** ⇒ 因为**没人见过它成功的样子**。
批 AQ 用 **GitHub API + 真包**把它照了出来 ⇒ 三个错**叠在一起**：

| # | 原来的做法 | 实测事实 | 后果 |
|---|---|---|---|
| ① | URL 写死 `releases/latest/download/moongit-darwin-arm64.tar.gz` | release 资产名**带版本号**（v0.2.1 叫 `moongit-v0.2.1-darwin-arm64.tar.gz`），而 `latest/download` 要求**资产名精确匹配** | **必然 404** |
| ② | 找「包根的 `moongit-cli`」 | 实测 tar 清单：包根是**启动器** `moongit`（POSIX shell 脚本），真二进制在 `bin/moongit-cli` | 就算 URL 修好也**找不到** |
| ③ | 只复制那一个文件 | 仓颉运行库在 `runtime/lib/`，被**丢掉了** | 装下来的引擎**根本起不来** |

⚠ 三个错是**同一个症状**下的**三个独立原因** ⇒ 只修 URL 仍然拿不到可用的引擎。
⇒ 根因是**同一条**：「**发布包被当成了单个裸二进制**」——
启动器按**自身所在目录**（`ROOT=$(dirname "$0")`）去找 `bin/` 与 `runtime/`，
且**不解析软链** ⇒ 三样必须**一起**落盘。
（deepin 侧早就踩过同一族坑，写在 `deepin/src/logic/EngineDownload.h` 里。）

**② 修法**：
- 新增 `macos/scripts/fetch-engine.sh`（**不依赖 macOS**，只用 curl/tar/grep）：
  查 API 拿最新 release 的资产列表 → 按**后缀**挑（架构差异由资产名表达，
  **不写死版本号**）→ 整包下载 → 整包解包 →
  验「启动器 / `bin/moongit-cli` / `runtime/lib` **非空**」三样齐全 → **整包**落盘。
- `macos/build.sh`：改调它；把下载目录（`~/.local/share/deepDolphin/engine`）
  加进候选清单；**内嵌引擎分两种形状**：
  A. **发布包**（启动器 + `bin/` + `runtime/`）；B. **裸二进制**（仓内 cjpm 产物）。
  ⚠ **内嵌进 bundle 的必须是 Mach-O**（rpath 重写与补签只对 Mach-O 有意义，
  `otool -l` 对 shell 脚本直接失败 ⇒ 会误报「rpath 被清空了却没写回来」）
  ⇒ 形状 A 内嵌**真二进制** `bin/moongit-cli`，并把它自带的运行库一起放进
  `Contents/Frameworks/`（rpath 里已有 `@executable_path/../Frameworks`）。
  ⚠ 形状 A **不用** SDK 那份运行库 —— 两个版本的 `libcangjie-runtime.dylib`
  混在同一目录里，后拷的盖掉先拷的 ⇒ 引擎与运行库版本对不上 ⇒ 起来就崩。

**③ 判据**：
- **行为判据**（新增 `macos/scripts/engine-fetch-check.sh`）：**不依赖 macOS**
  ⇒ **Linux 上就能跑**（资产选择与包布局都是平台无关的）。
  查 API → 验 URL 不是写死的 `latest/download` → 验 URL **带版本号** →
  验资产可达（HEAD 200/302）→ `--full` 再**真下载 + 解包 + 验三样齐全 +
  跑一次启动器**（实测输出 `moonGit Engine 0.2.1 (Cangjie 1.0.5 LTS)`）。
- **静态门 +10**（进 deepin 的 CI，跨目录盯 `macos/`，无网络依赖）。

**④ 负控 5/5 真红**（累计 **80/80**）——⚠ **头一次只有 4/5**：
build.sh 写死 URL ⇒ 静态门红／`fetch-engine.sh` 写死 `latest/download` ⇒ 静态门红／
`fetch-engine.sh` 不认 `runtime/lib` ⇒ 静态门红／
**只落启动器、不落 `bin/` 与 `runtime/`** ⇒ **行为门红**／
build.sh 内嵌只拷一个文件 ⇒ 静态门红。

**⑤ 元教训 1：⚠ 一条「从来没成功过」的路径 = 一整条**没人见过成功样子**的路径** ——
它能同时藏着好几个错而**一个都不会被发现**（没有失败日志、没有报错、
只是「下载不到」然后静默回退）。
⇒ 这类路径要**专门拿真数据走一遍**（API + 真包 + 真跑一次），而不是读代码猜。

**⑥ 元教训 2：⚠ 门盯的串，必须**只出现在干活的那一行** ——
本批两道门各栽了一次，方向相反：
① 批 AP：门盯的串**被注释/提示语满足**（把代码改坏，门照样绿）；
② 本批：门盯的 `runtime/lib` **在无关的另一行也出现**（形状判定那行）
   ⇒ 把真正干活的那句删掉，门照样绿。
⇒ 共同结论：**门必须盯「真正干活的代码构造」** ——
既不能盯一个会出现在注释里的裸串，也不能盯一个会在别处重复出现的串。

**⑦ 元教训 3：⚠ 负控判「门红了没」**不要 grep 门项的说明文字** ——
本批负控脚本按说明文字找那一条门，而我**刚把那句话改了措辞** ⇒
门明明红了，负控却判成「没红」（批 AN 就栽在同一件事上）。
⇒ 改成**数「✗」行**（并先量**基线**：变异前必须是 0 条，否则这个判据没有基线）。

**视觉变化**：无（本批只动 mac 构建脚本、新增两支 shell 脚本、deepin 侧门项 +10）。

### 批 AR：mac 侧「导出后打不开」—— 回执里的路径抽不出来

**① 起因**：deepin 侧 `deepin/src/logic/ArchReceipt.cpp` 的注释里**早就写着**这个 mac 缺陷
（「mac 的 extractHTMLPath 就栽在这里，导出后「打开」入口始终不出现」），
但那只是一句**注释** —— **注释不是修复**，mac 侧那份实现**一直没动**。

**② ⚠⚠ 用引擎实跑把形态坐实**（不能照着注释里的示例改）：
2026-10-20 真跑 `moongit render arch`，回执**原文**是：

```
已写入：/home/superShuai/.deepgit/store/p_f80de38f6095/render/arch.html · 共 0 个文件，0 个函数（语法未通过则不计入）
```

⇒ 路径与文案之间是**全角冒号**（**没有空格**），路径后面跟**中点**。
⚠ deepin 侧注释里的示例是「已重绘：… · 第 1 版」，**实跑是「已写入：… · 共 N 个文件」**
—— **文案不一样**（分隔符一样，所以老注释没把修复带歪 —— 但这是**运气**，不是依据）。

**③ 缺陷**：mac 侧那份实现按**空格**切词 ⇒ 切出「已写入：/path/arch.html」这种**粘连块**
⇒ `hasPrefix("/")` 恒假 ⇒ **抽不出路径** ⇒ 导出后「打开」入口**始终不出现**（死按钮）。
⚠ 而且它是**两份同名复制**（`ArchPage` + `CodeGraphPage`）⇒ 改一处漏一处、也**测不到**。

**④ 修法**：新增 mac 侧纯函数 `macos/Sources/deepDolphin/ArchReceipt.swift`
（零 SwiftUI/AppKit 依赖），口径与 deepin 侧 `logic/ArchReceipt` **逐条对位**：
边界 = 空白 + **全角冒号**「：」+ **中点**「·」（deepin 侧正则是 `(?<=[\s：·])`）；
只认**绝对路径**（相对路径打不开 ⇒ 宁可不给入口，也不要坏按钮）；后缀由调用方给；
⚠ **不缓存**任何按后缀构造的东西 ⇒ 不会踩 deepin 侧踩过的那个坑
（正则放函数级 static ⇒「第一次调用用哪个后缀，模式就焊死成哪个」）。
两处 ViewModel 删掉各自的私有复制，改调共享纯函数。

**⑤ 判据**：
- **跨目录静态门 +12**（进 deepin 的 CI，每次都跑、盯 `macos/`）：
  纯函数文件存在 / 边界认全角冒号 / 边界认中点 / 只认绝对路径 /
  两个 ViewModel **不许**再自带复制 / 必须走共享纯函数 /
  `client-check.sh` 的 **swiftc 那一行**必须编译它（只声明不编 ⇒ 断言永远绿）/
  mac 判据必须真的断言 / deepin 侧自检必须钉住**引擎实跑原文**的形态。
- **行为夹具**（deepin 侧 selfcheck **393 → 394**）：把**实跑**出来的回执原文照抄进自检。
- **mac 侧纯函数判据**：`client-check.sh` 编译清单 +`ArchReceipt.swift`，
  `Tests/ClientCheck/main.swift` 加四条断言（实跑形态 / 结论行 / 相对路径不认 /
  后缀不同的两次抽取互不污染）。
  ⚠⚠ **本机没有 Swift 工具链** ⇒ 这四条**未在本机跑过**，由 mac 侧跑该脚本时验；
  本批**可判**的部分（静态门 + deepin 侧行为夹具）已全部覆盖。

**⑥ 负控 5/5 真红**（累计 **85/85**）——⚠ **头一次只有 4/5**：
mac 侧边界不认全角冒号 ⇒ 静态门红／
**把 swiftc 那行里的 `$ARCHRECEIPT` 删掉**（只声明不编译）⇒ 静态门红／
`ArchPage` 又自带一份复制 ⇒ 静态门红／
`ArchPage` 绕过共享纯函数 ⇒ 静态门红／
**改坏 deepin 侧参考实现的边界** ⇒ **selfcheck 红**（这条是**行为级**的）。

**⑦ 元教训 1：⚠⚠ 对位侧注释里写着的「某某的 bug」**不是修完了，是记下了** ——
`ArchReceipt.cpp` 里那句注释我读过很多遍，一直当成「已知差异」；**其实它是待办**。
⇒ **跨端缺陷要在对端修**，不能在对位侧留句注释了事。
⇒ 而且注释**不会触发任何门** ⇒ 不改代码 ⇒ 缺陷**一直在**。

**⑧ 元教训 2：⚠ 引擎的输出形态要**实跑取证**，不能照着注释里的示例改 ——
注释写「已重绘：… · 第 1 版」，实跑是「已写入：… · 共 N 个文件」⇒ **文案不同**。

**⑨ 元教训 3：⚠ 门盯的串必须**只出现在干活的那一行** ——
批 AP（被注释满足）、批 AQ（在无关的另一行也出现）、本批（**只声明不编译**也算出现）
⇒ **三次都是同一个形状：盯一个会到处出现的串**。
⇒ 以后新门的默认写法：盯**那一句真正干活的代码**，别盯文件名、别盯声明。

**视觉变化**：无（mac 侧逻辑修正 + deepin 侧加一条自检；快照零变化）。
### 批 AS：mac 侧布尔旗标只认 `as? Bool` —— 模型把旗标写成字符串时**恒为假**（且**两端都漏了「数字」形态**）

**① 起因**：`macos/Sources/deepDolphin/AgentCore.swift` 的注释里**本来就写着**
「模型给的布尔/数字经 JSONSerialization 可能落成 Bool/Int/Double/String」，
而**实现只有 `as? Bool`** ⇒ **说法与实现相反**（批 AI 的教训：
说法与实现相反比说法缺失更危险）。
⇒ 注释早就知道会落成字符串，代码却只认布尔。
⚠ 且 deepin 侧**早就修过同一洞**（`AgentToolPlan.cpp` 的 `flag()` 注释：
「只认布尔会让 flag 永远不生效（--force / --violations 形同虚设）」）
⇒ **mac 侧是漏改的那一侧**。

**② 症状**：模型把旗标写成**字符串**（`"force": "true"`）或非 0/1 的数（`2`）
⇒ `as? Bool` 落空 ⇒ 旗标**恒为假** ⇒ AI 说「强制重跑」，
`render arch --force` / `arch gen --force` **静默不生效**（命令照发、旗标没了），
界面上还显示「✓ 执行成功」。

**③ ⚠⚠⚠ 本批新发现：不是「漏改」，是「**改了一半**」** ——
实测 `QJsonValue::toString()` 对**数字**返回的是**空串**（**不是 `"1"`**）：

```
QJsonValue(1).toString()  →  ""      ← 空串，不是 "1"
QJsonValue(1).isDouble()  →  true
```

⇒ deepin 侧那版「补了字符串分支」的 `flag()` 走 `toString()` ⇒ 数字形态**必然落空**
⇒ JSON `{"force": 1}` 在 **deepin 侧也判假** ⇒ **两端都漏了数字形态**。

**④ 修法**：
- **deepin 侧** `src/logic/AgentToolPlan.cpp` 的 `flag()` 补数字分支：
  `if (v.isDouble()) return v.toDouble() == 1.0;`
  ⚠ **只有 1 为真**（不是「非 0 即真」）；`isDouble()` **必须先判**
  （Qt 里 `true`/`false` 存 bool 型、`1`/`0` 存 double 型 ⇒ 顺序反了会把 `true` 判成假）。
- **mac 侧** 新增 `macos/Sources/deepDolphin/ToolArgs.swift` 的
  `static func flag(_ params: [String: Any], _ key: String) -> Bool`
  （该文件**本就在** `agent-check.sh` 的编译清单里 ⇒ 判据脚手架现成），
  `AgentCore` 内联闭包改调它 ⇒ 口径**只有一处**。
  口径逐条照抄 deepin 侧：Bool 本身；Int/Double **== 1**；
  字符串 `true`/`1`/`yes`/`on`（**trimmed + lowercased**）；其余假。

**⑤ 判据**：
- **跨目录静态门 +6**（进 deepin 的 CI，盯 `macos/`）：
  `AgentCore` 不许再只用 `as? Bool` 判旗标 / 必须走共享纯函数 /
  `ToolArgs` 必须提供纯函数版旗标解析 / 必须认**字符串**形态的 `true` /
  `agent-check.sh` 的 **swiftc 那一行**必须编译 `ToolArgs.swift`（只声明不编 ⇒ 断言永远绿）/
  mac 判据必须真的断言旗标的多种形态。
- **行为夹具**（deepin 侧 selfcheck **394 → 395**）：钉死**共享口径** ——
  「on」为真、大小写与首尾空白**不算数**、数字**只有 1 为真**。
  ⚠ 这条断言**第一版是红的** ⇒ 红灯直接指出要补什么。
- **mac 侧判据**：`Tests/AgentCheck/main.swift` 加四条断言
  （字符串形态 / 数字只有 1 为真 / 假值与缺省 / 源码 lint 不许退回 `as? Bool`）。
  ⚠⚠ **本机没有 Swift 工具链** ⇒ 这四条**未在本机跑过**，由 mac 侧跑 `agent-check.sh` 时验；
  本批**可判**的部分（静态门 + deepin 侧行为夹具）已全部覆盖，**没验的部分照实写明**。
- **门自审计**（本批新增，见下面 ⑥⑦）：接线门 **600 项**、selfcheck **395/0**、
  ci.sh **12/12**、契约门 **120/0**、ci-d2 **0/0**、快照**零变化**。

**⑥ ⚠⚠ 负控头一次只有 4/5 ⇒ 当场查出「第四次同一形状」** ——
第 4 条变异（掏空 mac 侧断言里的 `ToolArgs.flag(p, "force")`）**门没红**。
⇒ 查出来：门盯的是 `ToolArgs\.flag\(`，而它在 mac 侧测试文件里出现 **8 处**
⇒ 变异只动其中 1 处 ⇒ **别处还顶着呢** ⇒ 门没牙。
⇒ 这是同一形状的**第四次**（批 AP 被注释满足 / 批 AQ 在无关的另一行也出现 /
批 AR 只声明不编译也算出现）⇒ 前三次都是**事后人工发现**。

**⑦ 修法（把「事后人工发现」变成「机器当场审」）**：
- 那条宽松门换成 **5 条盯唯一构造**的门（实测每个在 `macos/` 下**只命中 1 次**）
  ＋ 新增 `arch_need_min`（「**至少** N 次」语义：削减红、增加绿；
  `arch_need_count` 盯「恰好 N 次」会让将来**正常加一条断言反而变红**）。
- 新增 `deepin/scripts/ci-wiring-audit.py`（**门自审计**）：
  逐条数每个 `arch_need` 门项的正则在目标文件里命中几次，
  **豁免基线之外**只要还有一条命中 >1 ⇒ **硬门红**。
- 新增 `deepin/scripts/wiring-multi-hit.exempt`：**历史 53 条已知隐患显式入账**
  ⇒ **新加的门不许落进去**；某条门收紧后审计器会报「已失效」⇒ 可清。
  ⚠ 其中两条正是**前面批次的老门**：批 AQ 的 `runtime/lib`、批 AR 的 `ArchReceipt\.htmlPath\(`
  —— 当时的负控**只是恰好打在被抓住的那一处**，门本身**一直不唯一**。
- 审计器**自报盲区**且**盲区必须红**（否则「没审到的门项」就成了逃逸口）。

**⑧ 负控 8/8 真红**（累计 **93/93**）：退回 `as? Bool` ⇒ 门红／
不认字符串形态 ⇒ 门红／`swiftc` 那行不编 `ToolArgs.swift` ⇒ 门红／
掏空**字符串真值表**断言 ⇒ 门红／掏空**数字形态**断言 ⇒ 门红／
**删掉 deepin 侧数字分支** ⇒ **selfcheck 红**（这条是**行为级**的）／
**加一条串不唯一的新门** ⇒ **门自审计红**／
**把门项写成审计器解析不了的样子** ⇒ **审计器盲区 ⇒ 硬门红**。

**⑨ 元教训**：
- ⚠⚠ **对位实现必须照抄对位的口径** —— 我第一版 mac 侧写「**非 0 即真**」，
  而 deepin 侧是「**只有 1 为真**」⇒ 照抄后才对齐。跨端同一语义，口径要**逐条对**。
- ⚠⚠ **两端都漏了同一个洞 ⇒ 那不是「漏改」，是「改了一半」** ——
  deepin 侧看起来「早就修好了」⇒ 实测才发现**数字形态两端都漏**
  ⇒ 对齐工作必须**同时**检查两端。
- ⚠⚠ **`QJsonValue::toString()` 对数字返回空串** ⇒ 任何「先转字符串再比」的写法，
  对**数字**都是**恒假** ⇒ 数字形态必须**先判 `isDouble()`**。
- ⚠⚠ **「门盯的串不唯一」第四次同形状 ⇒ 这次上机器** ——
  前三次都是**事后人工发现**（撞上了才知道）⇒ 这次让审计器**当场**数命中次数。
  ⇒「门要唯一」这条纪律**也得有门**（承诺没有门 = 承诺不存在）。
- ⚠ **「恰好 N 次」与「至少 N 次」是两个语义** —— 计数类门要分清，
  否则门会被人随手调数字 ⇒ 门就废了。

**视觉变化**：无（mac 侧逻辑修正 + deepin 侧加一条自检 + 判据层新增两个脚本；快照零变化）。

### 批 AT：门自审计豁免基线清账（第一轮）——「盯名字」的门改成「盯接线点」

**① 起因**：批 AS 的**门自审计**（`scripts/ci-wiring-audit.py`）报出 **53 条**
「同一串在目标文件里命中 >1 次」的历史门 ⇒ 它们的形态**全都是**「盯名字不盯接线点」
⇒ **改一处骗得过门**（别处还顶着呢）。

**② ⚠ 仓库里其实早就有这个认识** —— 语法高亮那段门项的注释写着：
> 「⚠ 盯**构造点**（`new CodeHighlighter`）而不是『CodeHighlighter 这个词出现过』——
> 负控实测：只删掉构造那一行、留着 include 与另一个调用点时，后者照样全绿。
> **这已是第三回「门盯名字不盯接线点」**。」

⇒ 这个洞**历史上踩了三次**，每次只补了**当次那一处**，其余「盯名字」的门留在原地。
批 AT 把它**逐条**补齐。

**③ 改法：取「改」不取「另加」** —— 「改」= 弱门**本身**改成盯接线点
⇒ 门项数不变、意图**更强**（存在 ⇒ 必有构造点）、且**豁免基线能缩小**；
「另加」= 弱门留着 + 新增强门 ⇒ 门项 +1、基线**不缩**（弱门继续留在暗处）。

**④ 本轮 9 条**（全在接线层，每条新正则实测**在目标文件里只命中 1 次**）：
`showArch` / `showCodeGraph` / `showPatchCheck` / `showDocs` 四条
从「有这个方法」改成盯**接线那一行**（`showArch(p);` 等）；
`ArchDialog` / `CodeGraphDialog` / `PatchCheckDialog` / `DocsDialog` 四条
从「类名出现过」改成盯**构造点**（`new XxxDialog(`）；
`ArchCanvasWidget` 改成盯 `new ArchCanvasWidget(`。
⇒ 豁免基线 **53 → 44 条**（审计器主动报出「已失效 9 条」，已清掉）。

**⑤ 判据**：接线门 **600 项**（不变）全绿、门自审计硬门 **rc=0**、
selfcheck **395/0**、ci.sh **12/12**、契约门 **120/0**、ci-d2 **0/0**、快照**零变化**。

**⑥ 负控 9/9 真红**（累计 **102/102**）：把「干活的那一行」改坏（改名）⇒ 门必须红。
⚠ 实测每次是 **1 条真门红**（另一条「✗」是脚本汇总行，不是门项）。

**⑦ 元教训**：
- ⚠⚠ **静态门类的负控不要编译** —— 本批变异**故意把源码改坏** ⇒ 编译必失败；
  而接线门是**源扫描**，不需要编译 ⇒ 编译失败会让负控**提前退出** ⇒ **反而测不到门**。
  ⇒ 静态门负控只跑 `ci-wiring.sh`；**行为级**负控才编译。
  （前面几批的负控脚本都无条件编译 ⇒ 那是**因为它们的变异不改 C++**，没暴露这个坑。）
- ⚠⚠ **负控要双断言**：门红 **且** 目标串已消失** ——
  只判「门红了」不够（可能是别的门碰巧红了）⇒ 变异脚本额外断言目标串已消失。
  ⚠⚠⚠ **但「目标串消失」这个断言本身会被**子串顶替**骗过** ⇒ 见第二轮的教训 3。
- ⚠⚠ **「复刻一份实现」= 两套口径迟早漂移** ——
  审计器原用 Python 正则复刻 `ci-wiring.sh` 的 `strip_comments`；
  实测撞到过「临时工具报 2 次、手测与 shell 口径都是 4 次」
  ⇒ 已改成**直接调与 `ci-wiring.sh` 逐字相同的那条 perl/sed**（单一真相源），
  并对**全部 414 条**门项做**两套口径对拍** ⇒ 不一致 **0 条**。
- ⚠ **审计器要自报盲区，且盲区必须红**（否则「没审到的门项」成了逃逸口）。

**⑧ 第二轮（脚本类 / mac 侧，10 条）** ——
第一轮清完 9 条后基线里还有 44 条 ⇒ 本轮清**脚本类**与 **mac 侧**那批：

| 门 | 原来盯 | 现在盯 |
| --- | --- | --- |
| `build-deb.sh` | `rpath\|runpath` | 那行 `readelf -d … \| grep -qiE "rpath\|runpath"` |
| `ci.sh` | `stderr\.txt` | `2>"$REPRO_DIR/stderr\.txt"`（**落盘**那一行） |
| `fetch-engine.sh` | `browser_download_url` | **取**那一行 / **洗**那一行（各一条） |
| `fetch-engine.sh` | `bin/moongit-cli` | `[ -x "$pkg_root/bin/moongit-cli" ]` |
| `fetch-engine.sh` | `runtime/lib` | 拆两条：「验目录存在」+「验非空」 |
| `engine-fetch-check.sh` | `moongit-cli` | `[ -x "$DEST/bin/moongit-cli" ]` |
| `engine-fetch-check.sh` | `runtime/lib` | `if [ -d "$DEST/runtime/lib" ] &&` |
| `macos/build.sh` | `ENGINE_ROOT/bin/moongit-cli` | `cp "$ENGINE_ROOT/bin/moongit-cli"`（**拷贝**那一行） |
| mac 判据 | `ArchReceipt\.htmlPath\(` | 拆三条，各盯一条断言 |
| `probe-sni-icon.sh` | `IconPixmap` | `Properties.Get org.kde.StatusNotifierItem IconPixmap` |

⇒ 门项 600 → **604**、豁免基线 44 → **34**、门自审计硬门 **rc=0**。
**负控 13/13 真红**（累计 **115/115**）。

**⑨ 第二轮的三条新教训**：
- ⚠⚠ **「同一行里出现两次」也是隐患** ——「命中次数」口径下，
  `build-deb.sh` 的 `rpath|runpath` 就在**同一行** ⇒ 收紧必须用**行级构造**
  （把整行的独特部分作为正则），不能只盯一个词。
- ⚠⚠⚠ **「目标串消失」这个断言会被**子串顶替**骗过** ——
  第二轮第 3 条负控**门没红** ⇒ 查出来**不是门没牙，是变异没生效**：
  把 `browser_download_url` 改成 `browser_download_url_DISABLED` 后，
  目标串**仍是新串的前缀** ⇒ grep -o 照样匹配 ⇒ **命中数没变** ⇒ 门当然不红。
  ⇒ 断言必须盯**门依赖的那个量**（**命中次数减少**），不是「某个字符串不见了」。
  ⇒ 也正因如此，那条门不该用 `arch_need_min`（盯一个**可能被更长词包含**的串）——
  `arch_need_min` 还**不被审计器覆盖** ⇒ 改回两条 `arch_need`（各盯一处），
  既强又**重新进入审计覆盖**。
- ⚠⚠ **判门要用「数「✗」行」，不要用 `grep "✗"`** ——
  `grep` 找到匹配也返回 0 ⇒ **门红着也能通过 `&&` 链** ⇒
  我据此**提交过一版红门的门**（当场发现并 amend）。
  ⇒ 以后判门一律先数「✗」行，为 0 才允许提交。

**⑩ 第三轮（托盘探针 / 脚本 / 平台层，10 条）** ——
清完第二轮后基线里还有 34 条 ⇒ 本轮清**托盘探针**与**脚本/平台层**那批：
`probe-deepin-tray.sh` 的四条（TrayIcons / WM_NAME / GetName / deepin-window）
各盯**读的那一处**；`ci-platform-probe.sh` 的 `dpiEdgeLevels` 拆成「解析 legacy 列」
+「解析 aware 列」；`ci-docs-lang-probe.sh` 的 `docs-lang-probe` 盯**真的去跑探针**那一行；
`main.cpp` 的 `headlessDocsLangProbe` 盯**调用**那一行（盯函数名的话，定义还在、
调用被摘了，门照样绿）；`main.cpp` 的 `--receipt-file-path` 拆成「认得 flag」+「取到位置」；
`Settings.cpp` 的 `app.language` 拆成**读 / 删 / 写**三条；
`IconResolver.cpp` 的 `platform::dpiPixmap(` ⚠ **两处源码一字不差** ⇒ 行级构造分不开
⇒ 改用 `arch_need_min`（至少 2 次）⇒ **这条门不受「串唯一」检查覆盖**
  （弱一档，已写明；⚠ 但它的**下限配准**由审计器校准 ⇒ 定低了门没牙会被抓出来）。
⇒ 门项 604 → **608**、豁免基线 34 → **24**、硬门 **rc=0**。
**负控 14/14 真红**（累计 **129/129**）。

**⑪ 第三轮的教训**：
- ⚠ **意图天然是「多处」的门只能用「至少 N 次」** ⇒ 且要说清它**比别门弱一档**
  （不被审计覆盖 + 「删一处加一处」骗得过）。
- ⚠⚠ **「子串顶替」在负控里也会咬人** —— 把 `TrayIcons` 改成 `TrayIcons_DISABLED`
  ⇒ 目标串**仍是前缀** ⇒ 匹配还在 ⇒ **命中数没变** ⇒ 门不红。
  ⚠ 第一版断言（目标串「消失」）**抓不到**（它确实不再出现，只是**匹配**还在）
  ⇒ 会误判成「门没牙」；**第二版断言（命中次数必须减少）当场抓住**。

**⑫ 剩余**：豁免基线里**还有 24 条**未清（判定层 / UI 层 / 平台层 / 托盘探针剩下的）⇒ 分批做。

**视觉变化**：无（只动判据层；快照零变化）。

### 批 AU：豁免基线**清到 0** —— 「改一处骗得过门」这个洞一个不剩

**① 起因**：批 AT 三轮清完 29 条后基线里还剩 **24 条**（判定层 / app 层 / UI 层 / 平台层 /
CodeGraphDialog）⇒ 本轮**一次清完**。

**② 手法**（比前几轮多了三种新形态）：
- **盯调用/构造那一行**：`symbolId`、`keywords`、`kindKey`、`categoryOf`（读/写两处）、
  `packagedBinName`（拼落盘路径那行）、`DS::semColor`（三种语法元素三条）、
  `QComboBox`、`m_leftStack`、`m_heat->setData`（清空/喂数据两处）、
  `requiredProperties`（读名/取表两处）、`registerCustomType`（三种类型三条）、
  `xcb_get_selection_owner`、`advertisedVisual`、`HeatmapWidget`；
- **盯定义那一行**（意图本就是「有这个函数」）：`writableKeys`、`content`
  （⚠ 之前盯「content」这个词，**英文错误消息里也有** ⇒ 改一处骗得过门）；
- **盯夹具那一行**：引擎实跑原文（⚠ 之前盯「已写入：」⇒ 改**说明文字**也会红 ⇒ 盯错了地方）；
- **意图天然是多处**（同一构造**一字不差** ⇒ 行级构造分不开）⇒ 改用 `arch_need_min`
  （`Canvas2D`/`visibleRows`/`QDBus::Block`/`m_backend`）⇒ ⚠ 这几条**不受「串唯一」检查覆盖**
  （但**下限配准**已由审计器校准，批 AU 起）；
- **删掉两条弱门**（意图已被更强的门覆盖）：`DocsDialog.cpp` 的 `setButtonText`
  （已被两条 `arch_need_count_in_fn` 覆盖）、`CodeGraphDialog.cpp` 的
  `ArchCanvasWidget|CodeGraphBuild`（已被 `visibleRows` + `setData` 从两个方向覆盖）。

**③ ⚠⚠⚠ 抓到一个真问题：`arch_need_min` 的下限定低了 ⇒ 门没牙** ——
`Canvas2D` 那条下限写 **3**，而该串在 `HeatmapWidget.cpp` 里命中 **4** 次
（1 处 `include` + 3 处构造）⇒ **删掉一处构造仍剩 3** ⇒ 门照样绿。
⇒ 改成 4（= 实际命中数）；并给审计器加**下限校准**（必须 == 当前命中数）
⇒ 硬门失准 ⇒ **退出码 4**（红）。实测有牙：改回 3 ⇒ rc=4 并指出「门没牙」。

**④ 成果**：
- 门自审计「**命中 >1**」从 11 条降到 **0 条**
  ⇒ 全部 `arch_need` 门项的正则在目标文件里**只出现一次**；
- 豁免基线 **24 → 0 条**（文件保留，改为带说明的空基线）
  ⇒ **今后新加的门只要串不唯一，硬门立刻红**（没有基线可躲）；
- 接线门 610 → **613** 项全绿、selfcheck **395/0**、ci.sh **12/12**、
  契约门 **120/0**、ci-d2 **0/0**、快照**零变化**；
- **负控 29/29 真红**（累计 **158/158**）。

**⑤ 教训**：
- ⚠⚠ **「至少 N 次」的下限必须 == 当前命中数** —— 否则要么没牙、要么恒红；
  这类门**不被「串唯一」检查覆盖** ⇒ 必须**另加校准**才有牙。
- ⚠⚠ 要让**计数类**门红，必须让那个**模式串整体不再出现** ——
  改成「原串 + 后缀」**没用**（grep 照样匹配前缀）⇒ 变异必须**打断模式串本身**。

**⑥ 遗留**：审计器**不覆盖** `arch_need_ml` / `arch_need_count_in_fn` /
`arch_need_any` / `arch_need_count` ⇒ 其中 `arch_need_count_in_fn`（范围已收窄）
本**可以**是唯一的 ⇒ **待补**（批 AV）。
⚠ **批 AV 已补**：五类「要出现」的门（`_ml` / `_any_count` / `_any_min` / `_count` /
`_count_in_fn`）现在**全部在校** ⇒ 覆盖缺口**清零**（详见批 AV 段）。

**视觉变化**：无（只动判据层；快照零变化）。

### 批 AV：审计器**覆盖缺口清零** ——「任一文件里有」这种门**根本没有次数**

**① 起因**：批 AU 收尾时把「审计器不覆盖哪些门」如实写进台账 ⇒ 本轮去补。
先做**只读探针**把四类门的洞摸清，再决定补哪类、怎么补。

**② 探针实测（4 类门逐条扫）**：

| 门型 | 条数 | 有没有「改一处骗得过门」的洞 | 结论 |
|---|---|---|---|
| `arch_need_ml`（单文件、压行后匹配） | 3 | **有 1 条**（`platform::dpiPixmap(` 压行后 2 次） | **要补** |
| `arch_need_any`（跨文件、「任一文件里有」） | 82 | **有 42 条**（glob 范围总命中 >1） | **要补**（换门型） |
| `arch_need_count`（单文件、恰好 N 次） | 23 | **0 条失准** | 不用补（自己数次数） |
| `arch_need_count_in_fn`（函数体内恰好 N 次） | 10 | **0 条失准** | 不用补（自己数次数） |

⚠⚠ **判据细化（关键）**：`arch_need_any` 门红 = 「**所有**匹配文件里都没有」
⇒ **跨文件多现同样是洞** ⇒ 判据必须是「glob 范围内**总命中数 > 1**」
（不是「某文件内 >1」）⇒ 有洞条数 8 → **42**。

**③ ⚠⚠⚠ 老 `arch_need_any` 的两个洞（实测）**：
- **次数维度缺失**：只判「有没有」不判「有几处」⇒ `res.receipt` 在 glob 范围里 **7 处**
  ⇒ 删掉一处、别的还在 ⇒ 门照样绿。
- **口径不一致**：它用 `grep -lE` ⇒ **不剥注释** ⇒ 注释里提一嘴就顶替（批 AP 同形状）
  ⇒ 实测 `applyStatusPayload` 老口径命中 **4** 次、真实 **3** 次
  ⇒ 而 `arch_need` / `_ml` / `_count` / `_count_in_fn` **全都剥注释**。

**④ 手法：换门型（不是「另加一条」）** —— `arch_need_any` **整个删掉**，82 条按**意图**分两类：
- `arch_need_any_count <正则> <恰好 N 次> [glob]`（31 条）—— **接线点**类：
  接线**应当唯一** ⇒ 重复接线 = 隐患 ⇒ 「恰好一次」才能同时抓「删掉」和「多了一处」。
- `arch_need_any_min <正则> <至少 N 次> [glob]`（51 条）—— **判据**类：
  同一判定层被**多条断言**覆盖是**正常**的 ⇒ 删一条红、加一条仍绿（**不拦正常演进**）。
⚠ 两个新门型都数「**glob 范围总命中数**」（跨文件加总）且**剥注释** ⇒ 两个洞一并堵死。
⚠ 分派依据是**意图**不是现象：判据会正常增删（不许拦），接线应当唯一（重复即隐患）。

**⑤ 顺手抓到两条「盯错」的门**：
- `QStringLiteral\("overview"\)` 说明写「调引擎 **graph** overview」，
  却同时命中 AppModel.cpp 的 **index** overview ⇒ **盯错了对象**
  ⇒ 照 414/415 的对位写法收窄成 `QStringLiteral\("graph"\), *QStringLiteral\("overview"\)`。
- `arch_need_ml` 的 `platform::dpiPixmap\(` 压行后 **2** 次（大点 / 迷你条）
  ⇒ 拆成**两条各自唯一**（盯「变量名 + 调用」那一行）⇒ 门项 613 → **614**。

**⑥ 审计器扩覆盖**：`arch_need_ml`（查压行后唯一性）、
`arch_need_any_count`（校准实际 == 期望）、`arch_need_any_min`（校准**下限 == 实际命中数**）、
`arch_need_count`（校准实际 == 期望）、`arch_need_count_in_fn`（校准函数体内实际 == 期望）
⇒ **五类「要出现」的门全部在校** ⇒ 覆盖缺口**清零**。
⚠⚠ **口径绝不复刻**：审计器**从 `ci-wiring.sh` 里 `sed` 抽出** `strip_comments` /
`any_hits` / 切函数体那段 **awk 原文**，拼成临时脚本再调
⇒ 门侧改口径时审计侧**自动跟着变** ⇒ 零漂移。
⚠ **三套口径对拍实测**（审计器 / Python 独立实现 / 门自己的 `any_hits`）
⇒ 82 条门项**逐条一致，0 条不一致**。

**⑦ 成果**：门项 **614** 全绿；审计器「命中 >1」= **0 条**；所有配准 **0 条失准**；
豁免基线仍 **0 条**；selfcheck **395/0**、契约门 **120/0**、ci.sh **12/12**、
ci-d2 **0/0**、快照**零变化**；**负控 10/10 真红**（累计 **168/168**）。

**⑧ 元教训**：
- ⚠⚠ **「有没有」和「有几处」是两种门** —— 「任一文件里有」**结构上**就没有次数维度
  ⇒ 必然被别处顶替 ⇒ 想有牙只能**把次数加进语义**。
- ⚠⚠ 同一脚本里**各门口径必须一致** —— 两种剥注释口径 ⇒ 报告里的次数不可信。
- ⚠⚠ 负控的**每个 case 必须是「原始状态 + 本 case 的变异」** ——
  本批第一版忘在 case 之间还原 ⇒ 前面 case 改了门项数字且一直没还原
  ⇒ 后面 case 的审计器**一直**返回 rc=4（配准失准**抢先于**隐患检查）⇒ 报的是错码。
  ⇒ 负控要加 `restore_now`（**备份式**还原；⚠ **不能用 `git checkout`** ——
  被测文件此刻有**未提交**的改动 ⇒ 会把工作整个回滚掉）。

**视觉变化**：无（只动判据层；快照零变化）。

### 批 AW：分隔线是**真线** —— 顺带否掉一个想当然的修法

**① 起因**：M3c 剩余项之一 —— `ProjectDetailPage.cpp` 两处 `QLabel(QStringLiteral("|"))`。

**② ⚠ 先查对位，别自创**：mac 侧 `DetailViews.swift` 用 **SwiftUI 原生 `Divider().frame(height: 14)`**
（1pt 宽、限高 14 的真线）⇒ deepin 侧的 `QLabel("|")` 是**自创的降级写法**，不是「另一种风格」。

**③ ⚠⚠ 实测证据**（独立小程序只依赖 Qt6Widgets）：

| | 逻辑尺寸 | 物理 @dpr=1 | 物理 @dpr=2 |
|---|---|---|---|
| 旧写法 `QLabel("\|")` | **4 × 18** | 4 × 18 | **8 × 36** |
| 真线 | 1 × 14 | 1 × 14 | 2 × 28 |

⇒ 旧写法四个问题都出在「用文字冒充线」：宽 4（QLabel 文本边距）不是 1px；
高 18（字体高）不是 14；是**字形**（HiDPI 下变形）；颜色是 QSS 写死的**构建时快照**
⇒ 切主题不更新。

**④ ⚠⚠⚠ 实测否掉一个想当然的修法**：本想直接用 `QFrame::VLine` + `QFrame::Plain`
⇒ **实测它画的是 `QPalette::Text` 色**（#ff000000），**不是** `QPalette::Mid`
⇒ 深色主题下是一条**看不见的黑线**（而 `DS::surfaceBorder()` 正是 Mid 口径）
⇒ **只能自绘**（颜色取 `DS::surfaceBorder()`）。

**⑤ 修法**：新增 `src/ui/common/VDivider.h`（自绘 1 逻辑像素宽 × `DS::Height::divider` 高、
**不开抗锯齿**、**每次 paint 重取 token**、主题变化时 `update()`）；
`DS::Height::divider = 14` 新增一档（对位 mac `frame(height: 14)`）；
详情页两处改走**唯一构造点** `vDivider(parent)`（两处各写一遍 ⇒ 宽/高/色三处口径会分叉）。

**⑥ ⚠ 判据分两层，缺一不可**：
- **静态门 13 条**（批 AW 段）：DS token / `setFixedWidth(1)` / 高度走 token /
  颜色走 token / 主题变化重绘 / 唯一构造点的**定义行** / `vDivider(` **恰好 3 次** /
  `arch_forbid_tree`（全仓不许用文字当分隔线）/ 探针**调用行** / flag / 断言取值行 / CI 真跑。
- **行为探针**（`--divider-probe` + `scripts/ci-divider-probe.sh`）：**真渲染**一次量墨迹 ——
  逻辑宽 1 / 高 14 / `inkWidth == round(dpr)` / `inkHeight == round(14*dpr)` /
  `inkColor == tokenColor` / `opaque == 1`。
⚠⚠ **两层缺一不可**：探针测**组件本身** ⇒ 页面改回 `QLabel("|")` 它照样绿；
静态门测**页面用的是不是它** ⇒ 但证明不了「画出来真是 1px」。

**⑦ ⚠⚠ 快照抓不到它**：详情页**不在快照矩阵**（拍 dashboard/board/milestones/setupguide）
⇒ 本批快照**零变化** ⇒ 也意味着**快照证明不了这次修复** ⇒ 探针门是唯一行为证据。

**⑧ ⚠⚠ `--selfcheck` 里放不了这类判据**：`--selfcheck` 在 **GUI 应用构造之前**就 return
⇒ 那个模式下**没有 QApplication** ⇒ **建不了 QWidget** ⇒ 几何类判据只能走**无头探针**
（探针自己构造 `DApplication`）。

**⑨ 成果**：门项 614 → **627**（+13）全绿；selfcheck **395/0**、契约门 **120/0**、
ci.sh **12/12**、ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**；
**负控 6/6 真红**（累计 **174/174**）。

**⑩ 元教训**：
- ⚠⚠ **「用文字/字符冒充一个图元」是一类缺陷** ⇒ 该改的是**载体**（换成真图元），
  不是去调字号/颜色/间距把它「调得像」。
- ⚠⚠ **组件库的原生外观不能靠记忆** ⇒ `QFrame::VLine` 画 `Text` 色这件事只有实测才知道
  ⇒ 凭印象改 ⇒ 深色主题下出一条看不见的黑线。
- ⚠⚠ **探针自己也会犯批 AP 的坑** ⇒ 本批探针**第一版**把 pixmap 按逻辑尺寸建
  ⇒ dpr=2 时量的是逻辑像素 ⇒ 会把「2 物理像素的线」误判成「1 物理像素」
  ⇒ 写渲染探针先问「我量的是逻辑还是物理」。
- ⚠⚠ **第六次同形状**（门盯的串在别处也出现）：新门项 `inkWidth` 命中 **2** 次
  （取值行 + **缺字段的错误消息**里也列了它）⇒ 审计器**当场抓到** ⇒ 改盯 `field inkWidth`。

**⑪ 未验（照实写明）**：⚠ 真机 DDE 上的**目视观感**（变窄变矮后与按钮的间距观感、
深色主题下够不够明显）需真机；⚠ 详情页**没有像素级证据**（不在快照矩阵）；
⚠ HiDPI 125%/150% 的目视未验（本机只测到 1/1.5/2 的**几何**）。

**视觉变化**：详情页两处分隔线由「文字竖线（4×18）」改为「真线（1×14）」；
快照矩阵**不含详情页** ⇒ 快照零变化。

### 批 AX：门可以**永远绿** —— 正则里的写法不被 `grep -E` 认 ⇒ 门形同虚设

**① 起因**：M3c 剩「图标名 / 动效」⇒ 先做**只读实测体检**。
⚠⚠⚠ 体检过程中挖出的东西**比 M3c 本身重要得多**。

**② M3c 的实测结论（全树扫）**：
- **图标名零绕过**：`QIcon::fromTheme("…")` **0 处**、`QIcon("…")` **0 处**
  ⇒ 图标名真的只走 `logic/IconNames` 这一个出处（批 U 没退化）。
- 清单 **27 个**逻辑图标：**零使用 0 个**、清单外使用 **0 个**。
- **动效全项目只有一处**（`AgentDialog` 的新消息自动滚动）⇒ 时长走 `DS::MotionStandardMs`、
  缓动 `QEasingCurve::InOutQuad`。
⇒ 这三条**已达成** ⇒ 落成 8 条门钉住（627 → **635**）。

**③ ⚠⚠⚠ 我差点做出一个错误判断（幸好实测了）**：
写负控时门不红 ⇒ 顺着查 ⇒ 我**凭印象**认定「GNU `grep -E` 不支持 `\s`（那是 `-P` 的扩展）」
⇒ 准备把仓里 **14 处**用 `\s` 的门全改成 `[[:space:]]`。
⇒ ⚠ **实测推翻**（GNU grep 3.11）：

| 写法 | `grep -E` |
|---|---|
| `\s` `\S` `\w` `\W` `\b` | **都有效**（GNU 扩展） |
| ⚠ `\d` `\D` | **无效**（只有 `grep -P` 认） |

⇒ ⇒ 照那个印象改会**白改 14 条门**（且改完行为不变 ⇒ 察觉不到）。
⚠⚠ **与批 AW「组件库的原生外观不能靠记忆」同款**：
**凭印象判断「某个工具认不认某种写法」＝ 给自己埋雷** ⇒ 必须实测。
⚠ 顺带**好消息**：批 AP 那 11 条「不许再开 1x 位图」的 forbid 门**是真门**
（`\s` 有效 + 逐条实测零命中 = 绿）⇒ 那个承诺有门守着 ✔

**④ ⚠⚠⚠ 真发现：我自己新加的门里就有一条「永远绿」的门** ——
`arch_forbid_tree 'setDuration\(\s*\d'` 的 `\d` 不被认 ⇒ 那条门**永远匹配不到** ⇒ 形同虚设。
⚠⚠ 它是**负控当场抓到的**（第一版负控报「命中数没按预期变 ⇒ 变异没生效」）
⇒ 顺着报错往下查 ⇒ 挖出门自己的洞（**报错指向变异，根因在门**）。

**⑤ ⚠⚠⚠⚠ 「门形同虚设」有两种形态，后一种才是真洞**：
- `arch_need` 类写坏 ⇒ 匹配不到 ⇒ **门自己会红** ⇒ CI 能发现（**不静默**）。
- ⚠⚠⚠ **`arch_forbid` 类**写坏 ⇒ 永远零命中 ⇒ **永远绿** ⇒ **没有任何信号**
  ⇒ 而 forbid 门判的正是「不该有的东西没了」⇒ 它**本来就常年绿** ⇒ **静默失效**。
- ⚠⚠⚠ 且 **forbid 门不在审计覆盖内**（批 AS 有意为之）⇒ 它们的正则有效性**从没被审过**。

**⑥ 修法：审计器补第 2、第 3 个盲区**（批 AS 补过第 1 个「解析失败」）：
- **① 正则写法体检**：逐条检查**所有**门型（**含 forbid**）的正则参数，
  有没有 `grep -E` **不认**的转义 ⇒ **硬门红（rc=5）** 并指出改法。
  ⚠ 危险清单**只列实测确认无效的**（`\s`/`\S`/`\w`/`\W`/`\b` 都有效 ⇒ 不许误报）。
  ⚠ 判「单个反斜杠」：连续反斜杠数为**奇数**才算转义（`\\d` 是字面反斜杠+d ⇒ 合法）。
- **② 「命中 0 次 ⇒ 红」**：`arch_need`/`arch_need_ml` 命中 0 ⇒ 门永远匹配不到 ⇒ **rc=5**。

**⑦ ⚠ 一个查出来的真事实，但**决定不修**：`refresh` 一个图标被用于**四种语义**
（「刷新」/「重新索引」/「git **fetch**」/「更新」）。
⇒ **不修**的理由：① mac 侧是 **SF Symbols**、deepin 侧是 **freedesktop 主题名**
⇒ **不是同一套图标系统** ⇒「逐字对位」在图标层**不成立**；
② 两条都是循环箭头 ⇒ **用户分辨不出** ⇒ 改动**实际收益接近零**；
③ 新候选名能否在**真机主题**解析，本机**测不全** ⇒ 风险不为零（缺名 ⇒ 静默空图标）。
⇒ 保留现状 + 如实记下（**已知事实**，不是缺陷）；
**将来若要区分，判定标准是「用户能否分辨」，不是「mac 用了哪个符号」**。

**⑧ 成果**：门项 627 → **635**（+8）全绿；selfcheck **395/0**、契约门 **120/0**、
ci.sh **12/12**、ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**；
**负控 8/8 真红**（累计 **182/182**）—— 含两条**审计器自身**的负控。

**⑨ 元教训**：
- ⚠⚠ **凭印象判断「某个工具认不认某种写法」＝ 给自己埋雷**（我差点改坏 14 条好门）。
- ⚠⚠ **「门形同虚设」有两种形态**：`need` 类写坏了会自己红；**`forbid` 类永远绿**（静默）
  ⇒ 后者才是真洞 ⇒ 审计器**必须覆盖 forbid 门的正则**。
- ⚠⚠ **负控的报错可能指向别处**（报「变异没生效」，根因却是「门自己写坏了」）
  ⇒ 顺着报错往下查，能挖出门自己的洞。
- ⚠⚠ **审计器的盲区不止一处** ⇒ 审计器自己也要被审。

**⑩ 遗留**：forbid 门的「零命中」与「正则写坏」**语义上无法区分**
⇒ 只能靠「危险转义」**静态**判定 ⇒ 合法但无效的写法（字符类写错等）仍要靠负控/人工；
「清单里**零使用**的逻辑图标」**没有门**（需跨文件统计，静态门做不了）。

## 分层纪律（后续阶段必须延续）

- `models/`、`logic/` **不 include 任何 QWidget 头**，全部可被 QtTest 单测；
- JSON 键名字符串只出现在各模型 `fromJson` 一处（`static constexpr` 键表）；
- 「未知/读不到 = -1」用 `int` 原样承载，语义判断（读不出来 ≠ 0）归 logic 层；
- `ok:false` 不算失败（hasErrorOrCode 看键不看值）；缺失键 = 契约过旧，入口闸门判。
- **门盯的串必须只出现在干活的那一行**（批 AP「被注释满足」/ 批 AQ「在别处也出现」/
  批 AR「只声明不编译也算出现」/ 批 AS「测试文件里 8 处同形调用」⇒ **四次同形状**）——
  ⇒ 现在**有机器审**：`scripts/ci-wiring-audit.py` 逐条数每个 `arch_need` 门项的正则在
  目标文件里命中几次，**豁免基线之外**只要还有一条命中 >1 ⇒ **硬门红**；
  历史 53 条已知隐患在 `scripts/wiring-multi-hit.exempt` 里**显式入账**（不再藏在暗处），
  **新加的门不许落进去**；审计器**自报盲区**且**盲区必须红**（否则「没审到的门项」成了逃逸口）。
- **判门一律用「数「✗」行」** —— `grep "✗"` 找到匹配也**返回 0**
  ⇒ 门红着也能通过 `&&` 链 ⇒ 我据此**提交过一版红门的门**（当场发现并 amend）。
- **负控脚本必须用 `trap` 还原** —— 变异脚本失败时的 early-exit 会把变异**留在工作区**
  ⇒ 挡住下一次负控，更要命的是那次变异**差点被提交**。
- **负控断言要盯「门依赖的那个量」** —— 断言「目标串消失」会被**子串顶替**骗过
  （`x` → `x_DISABLED` 后目标串**仍是前缀** ⇒ 命中数没变 ⇒ 门不红是**变异没生效**，
  不是门没牙）⇒ 断言必须是「**命中次数减少**」。
- **「有没有」和「有几处」是两种门，混用必然有洞**（批 AV 实测）——
  「任一文件里有」这种语义**结构上**就没有次数维度 ⇒ 必然被别处顶替
  ⇒ 跨文件门必须用 `arch_need_any_count`（恰好 N 次）或 `arch_need_any_min`（至少 N 次）。
  ⇒ 分派依据是**意图**：**判据**会正常增删 ⇒ 用「至少」（不拦演进）；
  **接线**应当唯一 ⇒ 用「恰好」（重复即隐患）。
- **次数类门的数字必须校准** —— 下限/期望**必须 == 当前命中数**：
  定低了**没牙**（删一处仍够 ⇒ 不红），定高了**恒红** ⇒ 审计器**硬门红**（rc=4）。
- **同一脚本里各门的口径必须一致**（批 AV 实测踩到）—— 曾经四种门剥注释、
  一种不剥 ⇒ 报告里的次数不可信 ⇒ 人会据此做错判断。
  ⇒ 审计器**绝不复刻口径**：一律**从 `ci-wiring.sh` 里 `sed` 抽出函数原文**再调
  ⇒ 门侧改口径时审计侧自动跟着变 ⇒ 零漂移。
- **负控的每个 case 必须是「原始状态 + 本 case 的变异」**（批 AV 实测踩到）——
  case 之间不还原 ⇒ 前面 case 改的门项数字会**一直留着**
  ⇒ 后面 case 的审计器**一直**返回错码（rc=4 配准失准**抢先于** rc=3 隐患检查）
  ⇒ 报的是错码，测的也不是那条门。
  ⇒ 负控要加 `restore_now`，且**备份式**还原（⚠ **不能用 `git checkout`** ——
  被测文件此刻有**未提交**的改动 ⇒ 会把工作整个回滚掉）。
- **不许用文字/字符冒充一个图元**（批 AW 实测）—— 分隔线用 `"|"`、分隔符用 `"-"`、
  图标用 emoji ⇒ 看着像、实际不是（实测 `QLabel("|")` 是 **4×18 逻辑像素**的**字形**，
  HiDPI 下占 8×36 物理像素）⇒ 该改的是**载体**（换成真图元），
  不是去调字号/颜色/间距把它「调得像」。
- **组件库的原生外观不能靠记忆**（批 AW 实测）—— `QFrame::VLine` 画的是
  **`QPalette::Text` 色**（不是 Mid）⇒ 深色主题下是一条看不见的黑线
  ⇒ 凭印象改会踩 ⇒ 这类「大家都这么写」的写法要**实测**再落。
- **几何类判据只能走无头探针**（批 AW 实测约束）—— `--selfcheck` 分支在
  **GUI 应用构造之前**就 return ⇒ 那个模式下**没有 QApplication** ⇒
  **建不了 QWidget** ⇒ 「要真渲染才量得到」的判据（宽/高/像素/颜色）
  必须自己构造 `DApplication`（与 `--docs-lang-probe` 同款）。
- **判据要分两层**：**静态门**守「用的是不是这个组件」，
  **行为探针**守「这个组件画出来真的是不是这样」⇒ 缺一层就有洞
  （探针测组件 ⇒ 页面改回旧写法它照样绿）。
- **写渲染探针先问「我量的是逻辑还是物理」**（批 AP 已踩过一次，批 AW 又踩了一次）——
  pixmap 必须按 dpr 放大并 `setDevicePixelRatio` ⇒ 否则 dpr=2 时量到的是逻辑像素。
- **凭印象判断「某个工具认不认某种写法」＝ 给自己埋雷**（批 AX 实测）——
  我曾认定「GNU `grep -E` 不支持 `\s`」⇒ 准备改 14 条好门 ⇒ 实测被推翻
  （`\s`/`\S`/`\w`/`\W`/`\b` **都有效**，只有 `\d`/`\D` 无效）⇒ **必须实测**。
- **「门形同虚设」有两种形态**（批 AX 实测）—— `arch_need` 类写坏了**自己会红**
  （CI 能发现）；⚠ **`arch_forbid` 类写坏了永远绿**（静默失效，且它本来就常年绿）
  ⇒ 后者才是真洞 ⇒ **审计器必须覆盖 forbid 门的正则**。
- **负控的报错可能指向别处**（批 AX 实测）—— 报「变异没生效 ⇒ 门没牙」，
  **根因却是「门自己写坏了」** ⇒ 顺着报错往下查，能挖出门自己的洞。
- **绝不用 `| tail -N` / `| head -N` 跑长输出命令**（批 AX 实测）——
  下游**提前退出** ⇒ 上游 stdout 断管 ⇒ 上游收到 **SIGPIPE**
  ⇒ 实测 `git push | tail -2` 把 push **杀掉**、脚本报「成功」而远端**没变**
  ⇒ 长输出**落盘再读**；`$(cmd | awk ...)`（下游读完全部）是安全的。

## 运行期事实（实测记录）

- 容器内 GUI 经共享 X11（`:0`）可达宿主 DDE；无显示环境时 `QT_QPA_PLATFORM=offscreen` 可跑
  （三个环境变量见「构建与运行」——本阶段实测缺 `QT_PLUGIN_PATH` 会直接起不来）。
- 引擎 moongit/deepgit 未安装 → 首启即「引擎未找到」安装指引路径（本阶段 offscreen 复测：
  告警与文案正确，退出码 124 存活）；`DEEPGIT_BIN` 指向探活通过的桩时不再报错（AI 层阶段
  实测；agent 工具循环全链路亦以桩引擎验证，见决策 27）。
- 托盘在无系统托盘的环境（offscreen）只有 Qt 告警，不影响运行；真实 DDE 上走 **deepin 托盘窗口协议**
  （自绘 X11 窗口 + `REQUEST_DOCK`，批 Y 实测查明的正解；SNI 那条路 DDE 上不画图标）。
- 会话总线（共享宿主总线）上 `com.deepin.copilot` 在线 → SystemAiEngine probe=Present：
  AI 入口的降级文案为「不支持程序化补全」而非「未检测到服务」；两者都如实区分（已按
  busctl 实测口径实现，真机 DDE 上行为与容器一致）。
- ⚠ **CI 偶发段错误**（2026-10-20）：共 **2 次**实测到（批 AT 收尾一次、批 AX 期间一次）
  ⇒ 现象：`ci.sh` 输出里出现 glibc 的段错误回溯（栈在 `libQt6Core`），
  ⚠ **而 `ci.sh` 的退出码仍是 0** ⇒ ⇒ 那个崩掉的子进程**退出码没人看** ⇒ **CI 会误判通过**。
  ⇒ ⚠⚠⚠ **两条旧假设已被实测推翻**（批 AX 查）：
  - ❌「**并发**跑导致」⇒ 实测 **3 轮 × 2 个 `ci.sh` 同时跑**（输出重定向到文件、无管道）
    ⇒ **零复现** ⇒ 并发**不是**根因。
  - ❌「`| tail -N` 的 SIGPIPE 导致」⇒ 实测 **3 轮 `ci.sh | tee | tail -2`** ⇒ **零复现**。
  ⇒ ⚠ **崩溃本身的成因仍未定位**（2 次都未复现；批 AZ 又跑了 **600 轮**压测 ⇒ **零复现**）⇒ **不再猜**。
  ⇒ ✅ **但「为什么 CI 会放行」已定位并修掉（批 AZ）**：是 ci.sh 里那行
  `SELFCHECK_OUT="$("$BIN" --selfcheck || true)"` ⇒ `|| true` 写在**命令替换内部**
  ⇒ 把 selfcheck 的退出码变成 0 ⇒ **崩在汇总行之后时**解析照样成功 ⇒ **门放行**
  ⇒ 正是批 AY 那两次「段错误回栈 + 退出码 0」的机制。
  ⇒ 现在：**退出码单独收**、**信号退出（≥128）显式判红**（打信号名 + core 路径 + stderr 全文）、
  agent 自测补**三断言**（退出码 / `[selftest] FINAL:` / `[selftest-done]`）。
  ⇒ 崩点可诊断性三件套已就位：**完整输出落盘** + **留 core**（`ulimit -c`，
  ⚠ 实测 `core_pattern` 是相对名 `core` + `core_uses_pid=1` ⇒ 文件名 `core.<pid>`、
  **落在崩溃进程的 cwd** ⇒ 故在 `build/crash/` 专用目录里跑）+ **崩了说清信号名与 core 路径**。
  ⇒ **下次复现时该做的两件事**（现在真的做得到）：
  ① 完整输出落盘（⚠ 那次只看到 `tail -2` 的最后两行 ⇒ **栈被截断了** ⇒ 白丢线索）
  ② core 落在 `deepin/build/crash/core.<pid>`（⚠ 本机无 gdb ⇒ 用 `strings core` 看符号）
  ⇒ 记在此处待查（**待查的是崩溃本身，不是「CI 会不会放行」**——后者已修）。
- ⚠⚠⚠ **两种「吞退出码」必须分清**（批 AZ 实测踩出来的，**纠正了一个想当然的判断**）：
  - `cmd | tail -2`（**管道**）⇒ **不吞**退出码 —— 在 `set -euo pipefail` 下，
    `false | tail -2` 会让**整个脚本以 1 退出**（**dash 与 bash 都实测过**）
    ⇒ ⚠ 网上常见的「管道的退出码是 tail 的」在本仓**不成立**。
  - `$( cmd || true )`（**命令替换内部的 `|| true`**）⇒ **吞** ——
    `|| true` 在替换**内部** ⇒ 替换整体成功 ⇒ **外层什么也看不出来** ⇒ 门放行。
    ⚠ 这才是批 AY 那次「ci.sh 退出码仍是 0」的真正机制（`ci.sh` 第 35 行那个 `|| true`）。
  ⇒ 推论：**写「这一行会不会吞退出码」时，必须区分是在管道里还是在命令替换里**。
- ⚠⚠⚠ **绝不用 `| tail -N` / `| head -N` 跑长输出命令**（批 AX 实测踩到，代价很实在）——
  下游**提前退出** ⇒ 上游的 stdout 变成断管 ⇒ 上游收到 **SIGPIPE**：
  - `git push origin "$BRANCH" | tail -2` ⇒ **push 被杀** ⇒ 推送**中途夭折**，
    ⚠ 而脚本只看 `git ls-remote` 的结果 ⇒ 那一轮恰好读到已更新的远端 SHA
    ⇒ **脚本报「✓ 推送成功」而远端其实没变** ⇒ 我据此以为推上去了，**实际没有**
    （实测：`15448f9..be2280e` 那一推在旧脚本下**几十轮都没推上去**；
    去掉管道后**一次就成**）。
  ⇒ 规矩：**长输出落盘再读**（`> "$LOG" 2>&1`），要截尾就 `tail` **落盘的那份**；
  `$(cmd | awk ...)` 这种**下游读完全部**的管道是安全的（不会 SIGPIPE）。
  ⚠⚠ **注意这条与上面那条是两回事**：本条说的是「**上游被杀**」（SIGPIPE），
  不是说「管道吞退出码」——后者在 `set -o pipefail` 下**不成立**（见上）。
- ⚠⚠⚠ **「CI 里跑的每个断言脚本」这件事本身也要有门**（批 BD 实测）：
  - `scripts/probe-agent-tool-surface.sh`（agent 工具面收敛，**9 条断言**）**本来根本不在 CI 里**
    ⇒ ⚠⚠⚠ **把它整个从仓库删掉，接线门 rc=0、审计器 rc=0 ⇒ 两个都全绿**
    ⇒ **「仓库里少了一份断言」没有任何门会说一个字**。
  - 对照实测（用来定位洞的位置）：删掉**已经接进 CI** 的探针（文件或调用）⇒ 门**红**
    ⇒ 洞不在「已接管的」，在「**没人接管的**」。
  - 现在：① 它**接进 CI**（`ci.sh` 第 13 步，退出码 **3=SKIP** 表示引擎缺席/太老 ⇒ **未验证，不算通过**）；
    ② 新增 `scripts/ci-orphan-probe.sh`（`ci.sh` 第 14 步）——
    `scripts/` 下**每个断言脚本**要么在 CI 里**可达**（ci.sh 直接调用，或被 CI 可达的脚本调用），
    要么在**带理由的白名单**里（当前 4 条：`ci.sh` / `smoke.sh` / 两个**需真机**的托盘探针）。
  - ⚠ **口径实测**：可达性按**真调用点**判定，**不是**「文件名出现过」
    （实测 `scripts/ci.sh` 在 ci.sh 里出现 3 次，全是注释 ⇒ 会把 ci.sh 误判成「自己调用了自己」）；
    **门项行不算调用点**（ci-wiring.sh 里的 `arch_need ... 'sh "\$SRC/scripts/x.sh"' …` 长得像调用）。
  - ⚠⚠ **「文件被整个删掉」要靠另一条门**：无游离门扫的是**目录里现存的文件** ⇒ 文件没了它就扫不到
    ⇒ 另有「盯文件本身的条数基线门」（删文件 ⇒ 门报「文件不存在」⇒ 红）。
- ⚠⚠⚠ **「这一项还在」与「这一项还在**该在的地方**」是两件事**（批 BE 实测）：
  - 批 BA 的 per-step 门盯的是「该标记串在**整个 ci.sh** 里恰好出现 1 次」⇒
    ⚠⚠⚠ **实测：把第 8 步的 `CANVAS_METHODS=` 整行挪到第 12 步** ⇒ 命中数仍是 1
    ⇒ 接线门 **rc=0（绿）** ⇒ **CI 可以悄悄少做第 8 步的事**（Canvas 契约清单检查）而无人知晓。
  - 现在有新门型 `arch_need_count_in_step`（批 BE 段 14 条）：按打点行
    `^echo "› N/M ` 把 ci.sh 切段，**在第 N 步的正文里**数那个串 ⇒ 挪走就红。
    ⚠ 与文件级门**互补**：文件级「恰好 1 次」抓「被**复制**到别处」，步内抓「被**挪**到别处」。
  - ⚠ **口径实测**：打点行必须紧锚定 `› `（宽松写法 `^echo "[^"]*[0-9]+/[0-9]+ `
    会把 `echo "普通行 3/4 不是打点"` 也算进去）；本机 awk 是 **mawk 1.3.4**，
    认得多字节 `›` 的正则与 `sub`。
  - ⚠⚠ **新门型 ⇒ 审计器跟着扩**（否则新门型自己就是盲区）：切段用的 awk
    **从 `ci-wiring.sh` 原文抽取**（零漂移），并新增该门型的**配准校准**
    （期望次数必须 == 该步正文里的实际命中数 ⇒ 「把期望从 1 改成 2 来躲变异」也躲不掉）。
    ⚠ 顺带补上一个旧盲区：`arch_need\b` 匹配不到 count 族 ⇒ **写坏的 count 门项以前是静默忽略**，
    现在会记成盲区 ⇒ 硬门红。
- ⚠⚠⚠ **「判据条数没变」不等于「判据没被削弱」**（批 BF 实测）：
  - 批 BB/BC 的门盯的是**条数**（selfcheck 的 `SC_MIN`、各断言脚本的条数基线）⇒
    ⚠⚠⚠ **实测：把一条判据的条件改成 `true`** ⇒ selfcheck 仍 **395 passed, 0 failed**
    ⇒ 条数基线**不红**、接线门 **rc=0（绿）** ⇒ 那条判据**从此永远不会红**。
  - 现在有新探针 `scripts/ci-tautology-check.py`（`ci.sh` 第 15 步）：
    ① 判定层 C++ 的 `check(…)` 条件**必须含被测标识符**（抓 `true` / `1 == 1` / `"a" == "a"`），
       另禁「捷径」`|| true` / `&& false`；② shell 脚本的 `if` 条件不许恒真/恒假；
       ③ python 脚本不许 `if True:`。
    ⚠ 抽 `check(…)` 的第三参用**括号配平**（不用正则猜）；基线实测零误报
    （396 条判据 + 271 个 `if` 条件今天全部合规）。
  - ⚠⚠ **门自己证明自己有牙**：探针**自带自检**（9 条合成样例，既含该判为恒真的、
    也含不该判为恒真的）⇒ 判定逻辑被掏空 ⇒ 探针当场报「自检失败」并判红。
    ⇒ 静态门盯「代码在不在」，**自检**盯「代码判得对不对」。
- ⚠⚠⚠ **判据不只在 `if` 条件里，也在断言函数的实参里**（批 BG 实测）：
  - 批 BF 的恒真探针扫的是「**条件**」（判定层 C++ 的 `check(…)` 条件、shell 的 `if`、
    python 的 `if`）⇒ ⚠⚠⚠ **但契约门的判据根本不在 `if` 条件里** —— 它的形态是
    `check <名称> <python表达式> [json]` / `check_text <名称> <ERE> <文本>`
    ⇒ **判据就藏在第二个实参里** ⇒ 批 BF 的三类扫描**一条都够不着**。
  - ⚠⚠⚠ **实测：把其中一条 `check` 的表达式掏空成 `True`** ⇒ 契约门仍 **120 passed, 0 failed**
    ⇒ 批 BC 的「93 处 `check` 调用不许被删」**不红**（调用点数没变）⇒ 接线门 **rc=0（全绿）**
    ⇒ 那条断言**从此永远不会红**。
  - 现在探针扫**第 ④ 类：实参层** ——
    ① `check` 的 python 表达式**必须引用 `d`**（被测 JSON）⇒ 抓 `True` / `1 == 1`；
    ② `check_text` 的 ERE**必须含至少一个字面字符** ⇒ 抓 `.*` / `^$` / 空串。
    ⚠ 实参**自己写解析器**（不用正则：实测 `contract-check.sh:555` 的**描述**里含 `==\"OK\"`
    ⇒ 正则会把描述与表达式粘成一块 ⇒ 判据抽错）。
    ⚠⚠ **条数交叉校验**：解析出的调用点数必须 == 基线（`check` **93** / `check_text` **6**）
    ⇒ 解析器漂了（悄悄少看几条）或断言被增删 ⇒ 当场红。
  - ⚠⚠⚠ **负控里又撞出两个「门形同虚设」的经典形态**：
    - ⚠ **盯函数名的门挡不住「改名」**：`arch_need_count … 'def assertion_arg_is_tautology' 1`
      是**子串**匹配 ⇒ 把它改成 `def assertion_arg_is_tautology_disabled`
      ⇒ **命中仍是 1** ⇒ 门照样绿 ⇒ 那个入口已经不存在了，门却还说「在」。
      ⇒ 现在凡是以函数名做判据的门都**带左括号**（`def X\(`）⇒ 改名就红
      （**4 条**：含批 BF 段的 `def tautology_reason`）。
    - ⚠ **解析器吞掉空实参 ⇒ 判据错位**：判据是「**第二个**实参」⇒ `''` 被吞
      ⇒ `tokens[2]` 变成**第三个**实参 ⇒ **恒真的空 ERE 被判成合法** ⇒ 漏判。
      ⇒ 解析器现在用 `started` 标志区分「没开始一个 token」与「token 内容为空」，
      且**自检里有合成样例**证明它（**注释不算证据**）。
  - ⚠ 探针自检表 9 → **16** 条（批 BF 9 条 + 批 BG 6 条「实参」样例 + 1 条「解析器」样例）。
- ⚠⚠⚠ **「门」本身也要被当成要被门守的事**（批 BH 实测）：
  - 批 BA 钉的是「**ci.sh 的每一步**」（12 条 per-step 门）
    ⇒ ⚠⚠⚠ 但**没有人钉「接线门自己的每一条门」**
    ⇒ ⚠⚠⚠ **实测：把 `ci-wiring.sh` 里任意一条门项改成注释**
      ⇒ 接线门 **rc=0**、审计器 **rc=0**、**CI 全流程 rc=0（15/15 全绿）**
      ⇒ 「**门项被悄悄删**」这件事，**没有任何机制会发现**。
    ⇒ ⚠ 接线门自己的输出里就印着「门项合计 722 项」（比基线少 1）
      ⇒ **数字就在眼前，但没人拿它跟基线比**。
  - 现在有两条互补的核对（都在 `ci-wiring-audit.py` 里）：
    ① **门项行总数基线**（新文件 `scripts/ci-wiring-gates.baseline`）
      ⇒ 审计器数「文件里实际的门项行数」⇒ 必须 == 基线 ⇒ 删一条 ⇒ 红。
      ⇒ ⚠ **基线放独立文件**（不写死在审计器里）⇒ 写死的话审计器既是**执行者**
        又是**裁判** ⇒ 改审计器就能同时改标准；独立文件 ⇒ 删基线文件 ⇒
        门与审计器**双双红**。
      ⇒ ⚠ **「恰好」口径是双向的**（基线改小改大都红）⇒ 基线是**锚点**不是门槛。
      ⇒ ⚠ **基线文件里不许写注释**（门项会管）。
      ⇒ ⚠⚠ **「行数」与「执行次数」不是一回事**：实测行数 732、接线门报 735
        （差 3 = 有门项在文件列表循环里被多次执行）⇒ 基线盯的是**行数**。
    ② **审计器门型覆盖对拍**（「认领数 == 物理行数」）
      ⇒ 按**自己登记的门型清单**数一遍，再按**不认识门型**的物理口径数一遍
      ⇒ 不等 ⇒ **有一种门型没被登记** ⇒ 那些门项**根本没被审** ⇒ 红。
      ⇒ ⚠ 今天两边都是 732（恒等）⇒ 防的是**将来新增门型忘了登记**。
      ⇒ ⚠ 这条对拍**当场抓出过一个真问题**：`ANY_NEED_LINE`（`arch_need\b`）的
        `\b` 允许后接 `(` ⇒ **函数定义行会被它命中** ⇒ 认领数多 1。
  - ⚠⚠⚠ **「盯串」不够，要「盯整行」**：
    ⇒ 把审计器的判定掏空但**保留判定串**（`elif … and False:`）
    ⇒ 「恰好 1 次」的门**照样绿**（串还在）
    ⇒ ⚠⚠⚠ **恒真探针也抓不到**（python 侧的「`and False` 捷径」不在它的规则里）
    ⇒ ⇒ **没有任何机制会发现** ⇒ 现在用**整行锚定**（含缩进与行尾）堵住。
  - ⚠⚠⚠ **同名常量 ⇒ 死代码 ⇒ 没有任何门会红**（串还在，只是不生效了）：
    ⇒ 本批加常量时撞了下方已有的同名常量 ⇒ 后者覆盖前者 ⇒ 前者成死代码
    ⇒ ⇒ 审计器新增**模块级重名自检**（用 `ast` 判定，不用正则）⇒ 重名 ⇒ 红。
  - ⚠⚠⚠ **注释里重复写被门盯的串 ⇒ 期望值会漂**：
    ⇒ `strip_comments` 对 `.py` **只剥 `//`、不剥 `#`** ⇒ 注释里的命中**算数**
    ⇒ 本批自己踩了（期望 2、实际 4）⇒ **审计器的配准校准当场报失准**。
- ⚠⚠⚨ **「门自己的工具坏了」也必须看得见**（批 BI 实测）：
  - forbid 门判的是「**不该有的东西没了**」⇒「没找到」是常态、是绿
    ⇒ ⚠⚠⚨ **工具坏了也长成「没找到」的样子**（输出为空 ⇒ grep 无命中 ⇒ 退出码 1）。
  - ⚠⚠⚨ **实测**：把中文门里剥注释的 perl 改成语法错误
    ⇒ 文件里**确实有中文** ⇒ 门仍输出「✓」⇒ 接线门 **rc=0**
    ⇒ **这道门静默变绿**（比没门更糟：给人虚假的安全感）。
    ⇒ ⚠ 不只这一道：`arch_forbid` / `_ml` / `_raw` / `_tree` 都是
      「grep 退出码 2（正则坏）⇒ 当作没找到 ⇒ 绿」。
  - 现在 forbid 家族 6 道门全部走**公共三态判定**
    （`probe_scan_state_of`：0 = 命中 / 1 = 没命中 / 其它 = **工具坏了 ⇒ 红**）
    ⇒ 「退出码 → 状态」的映射**只有一份**（复制两份迟早漂 ⇒ 一份坏了门还是绿）。
  - ⚠⚠ **管道下看不见上游退出码** ⇒ 加**存活探测**（`probe_strip_alive`，懒探一次）
    ⇒ 探测失败 ⇒ 走剥注释的门一律判「工具坏了」⇒ 红。
  - ⚠⚠⚨ **实测踩到的大坑（负控抓到的真回归）**：中文门的 perl 从 `grep -P`
    换成 perl 后**没解码 UTF-8** ⇒ `\x{3000}` 按**字节**匹配
    ⇒ **中文永远抓不到** ⇒ 门被改瞎 ⇒ 负控当场报「塞中文门没红」
    ⇒ 现在用 `perl -CSD`（⚠ `-Mopen=':std,:encoding(UTF-8)'` 在这段代码上返回
    **255** ⇒ 不可用 ⇒ **编码层必须实测，不能凭印象**）。
  - ⚠⚠⚨ **性能必须实测**：第一版落盘再 grep ⇒ 落盘到 tmpfs 比管道慢 **20 倍**
    （30ms vs 1.5ms/次）⇒ 2511 次调用 ⇒ **84 秒** ⇒ 改回管道 + 探测 ⇒ **7.2 秒**。
  - ⚠⚠⚨ **自检放在门项之前**（不是段末尾）：放在末尾 ⇒ 前面的门一红就 `exit 1`
    ⇒ 自检永远没机会跑 ⇒ 自检形同虚设（批 BG 教训）。
  - ⚠⚠ **负控要用段抽取器**：完整接线门里**审计器先跑会短路**后面段落的门项
    ⇒ 负控必须**从 `ci-wiring.sh` 原文现抽那一段单独跑**（零漂移）⇒ 红才能归因到本段。
- ⚠⚠⚨ **恒真探针要看得见「脚本侧」与「heredoc 内嵌脚本」**（批 BJ 实测）：
  - 批 BF 的捷径规则（`|| true` / `&& false` / `or true` / `and false`）
    **只用在判定层 C++** ⇒ shell 与 python 侧**一条捷径规则都没有**。
  - ⚠⚠⚨ **实测 5 个洞**（fixture + 真探针）：
    shell `if cmd || true` / `if cmd && false` / `while cmd || true` /
    python `if x and False:` / **heredoc 里内嵌 python** 的 `if True:` 与
    `if x and False:` ⇒ 全部**漏判**；且 heredoc 里内嵌 python 的 `if …:`
    被**误当 shell 条件**。
    ⇒ ⚠⚠⚨ **恒假方向最危险**：`&& false` / `and False` ⇒ 体永不执行
      ⇒ 体里那条断言**从此不会红**。
  - 现在四种场景（判定层 / shell / python / heredoc 内嵌）**全部**走同一个
    入口 `shortcut_reason` ⇒ 判定只有一份（批 BF/BG 纪律）。
    ⇒ ⚠ 匹配前先**剥字符串字面量** ⇒ 否则 `[ "$x" = "true" ]` 里的 `"true"`
      会被当成捷径 ⇒ 假红。
  - ⚠⚠⚨ **heredoc 是「另一种语言」的藏身处**：
    ① 先**摘出来**（`heredoc_spans`）⇒ 里面的 `if` 不再被误当 shell 条件；
    ② 摘出来后再用 **python 规则 + shell 规则各扫一遍**
      ⇒ python 收尾是 `:`、shell 收尾是 `then` ⇒ **天然不冲突** ⇒ 不用判语言。
  - 条件集合扩到 `if` / `elif` / `while` / `until`（后两者的条件同样是条件）。
  - ⚠⚠⚨ **「盯串不够」还有第二头：注释能顶替代码**（批 BH 教训的反面）：
    把真代码 `skip.add(k)` 换成 `pass  # skip.add(k)`
    ⇒ **盯串的门项计数仍是 1 ⇒ 门假绿** ⇒ 真代码已删而门看不出来。
    ⇒ 批 BH 说的是「盯串不够，要盯整行」（判定被掏空但串还在）；
      本批撞到的是**同一形状的另一头**（代码被删但串还在）
      ⇒ **两条合起来 ⇒ 关键判定必须整行锚定**（含缩进与行尾）
      ⇒ 本批把新增/升级的 9 条门项全部改成整行锚定
      ⇒ ⚠ **既有 18 条探针门项仍是盯串**（已知边界）。
  - ⚠ 自检样例 16 → **28** 条（新增 12 条「脚本侧捷径」样例，
    含「该判为捷径」与「不该判为捷径」两边）。
- ⚠⚠⚨ **剥注释必须覆盖 `.py`**（批 BK 实测 ⇒ 根治「注释顶替真代码」这一整类洞）：
  - ⚠⚠⚨ **起因**：把真代码 `skip.add(k)` 换成 `pass  # skip.add(k)`
    ⇒ **盯串**的门项命中数**仍是 1** ⇒ **门假绿** ⇒ 真代码已删而门看不出来。
    ⇒ 批 BJ 说的是「盯串不够，要盯整行」（判定被掏空但串还在）；
      本批说的是**同一形状的另一头**（代码被删但串还在）
    ⇒ 批 BJ 的修法（逐条改整行锚定）**只治了 9 条**，
      ⚠ **既有 18 条仍是盯串** ⇒ **逐条治标治不完**（以后每加一条都得记得改）⇒ 治标本身不可持续。
  - ⚠⚠⚨ **判据先行：先量影响面再动手**：让 `.py` 也剥 `#`
    ⇒ 审计器 **rc=0，零条门项失准**（命中数在「剥/不剥」两种口径下**都是 2**）
    ⇒ **零代价根治** ⇒ **改载体（根治）优于改判据形状（治标）**。
  - **门侧与审计器两侧同步改**（批 AS 纪律：审计器必须调**同一条**命令）
    ⇒ 不一致 ⇒ 同一串两侧算得不一样 ⇒ **配准校准失准**（会被当场抓到）。
  - ⚠ **行首锚定**（`^[[:space:]]*#`）⇒ 字符串字面量里的 `#` 不受影响 ⇒ 安全。
  - ⚠⚠⚨ **附带修掉一个隐藏问题**：python 的 `//` 是**整除运算符**
    ⇒ `.py` 原来走默认分支（perl 剥 `//`）⇒ `a // b` 的**后半截被当注释剥掉**
    ⇒ 剥出来的文本是**坏的**。
  - ⚠⚠⚨ **审计器自己抓到了新门项**（批 BH 的门型对拍当场生效）：
    正则参数用**双引号** ⇒ `COUNT_LINE`（**只认单引号**）解析不到
    ⇒ 落进 count-family 兜底 ⇒ **门型盲区 rc=2** ⇒ 改成单引号。
  - ⚠⚠⚨ **负控踩了两次（都改了）**：
    ① **变异写出了语法错** ⇒ 审计器崩 rc=1（而非预期的 rc=4）⇒ **归因不清**
      ⇒ 变异必须**语法正确**；
    ② **`restore()` 漏了探针文件** ⇒ 上个 case 的变异残留 ⇒ 探针抛异常
      ⇒ `restore()` **必须覆盖所有被变异文件**。
  - ⚠ **元教训**：**根治优于逐条治标**；**两侧必须同步**；
    **变异必须语法正确**；**restore 必须覆盖全部被变异文件**。
- ⚠⚠⚨ **盯「门自己的工具」的门项必须整行锚定**（批 BL 实测）：
  - ⚠⚠⚨ **起因**：批 BK 已根治「**注释顶替代码**」（`.py` 也剥 `#`）
    ⇒ 但「**判定被掏空、串还在**」这一头**仍只靠整行锚定挡**
    ⇒ 批 BJ 只把**新增/升级的 9 条**改成整行锚定
    ⇒ ⚠ **既有 24 条探针门项仍是盯串**。
  - ⚠⚠⚨ **实测取证的增量价值（如实记着，不吹）**：
    - 「**行内插入** `or True`」⇒ 旧盯串门**也会红**（连串都没了）
      ⇒ **不构成增量证据**；
    - 「**行尾被追加**」（`or True` / `or None` / 注释尾巴）
      ⇒ **旧门假绿、新门红** ⇒ 整行锚定**只多挡这一类**。
  - ⚠⚠⚨ **一个硬约束（实测坐实）**：正则参数用**单引号**包裹
    ⇒ 正则里不能有字面单引号（⇒ 参数被截断 ⇒ 审计器 `COUNT_LINE` 解析不到
    ⇒ 落进 count-family 兜底 ⇒ **门型盲区**，批 BK 教训）。
    ⚠ 实测 GNU grep 3.11 的 `-E` **不认** `[\x27]`、**不认** `\047`
    ⇒ 没有精确匹配单引号的 ERE 写法
    ⇒ 只能沿用既有约定**引号位置写 `.`**
    ⇒ ✅ 但**整行锚定让这个弱点被大幅削弱**（行首行尾都锚死 ⇒ 中间只剩一处 `.`）。
  - **修法**：
    - 探针门项逐条改整行锚定：24 条 ⇒ **30 条**
      （3 处拆分：定义与使用形态不同 ⇒ 一条罩不住；
      1 处合并：两个基线数字在**同一行** ⇒ 合并成一条整行锚定 ⇒ **更强**；净 **+3**）；
    - **审计器新增一条硬门**：盯探针文件的 `arch_need_count` 门项必须整行锚定
      ⇒ **第 8 种失败态**（rc=8）
      ⇒ ⚠ **判定逻辑只有一份**（实扫与自检都走它）
      ⇒ ⚠ **返回「原因」而不是布尔**（⇒ 调用方不再算一遍 ⇒ 判定串不会在源码里出现两次）
      ⇒ ⚠ **自检放最前**（前面的检查一红就 exit ⇒ 自检形同虚设）
      ⇒ ⚠ **适用范围只限探针文件**（探针是「门自己的工具」⇒ 被掏空 = 门**集体**失效）。
  - ⚠⚠⚨ **负控踩了三次（都改了）**：
    ① 测「旧口径命中」时传的是**代码行**、不是**门项正则** ⇒ 结论全错；
    ② 误以为「行内插入类变异旧门会假绿」⇒ 实测旧门**也会红**
      ⇒ **增量证据必须用「旧串是子串」的变异**（行尾追加）；
    ③ **变异写出了语法错** ⇒ 审计器崩 rc=1 ⇒ **归因不清**
      ⇒ 掏空改成整体替换函数体 + 变异后 `ast.parse` 断言语法正确。
  - ⚠ **已知边界**：**「锚定」≠「内容」**（`^.*$` 也算整行锚定 ⇒ 靠次数门配准兜）；
    **判定「体」被掏空、判定行本身没变** ⇒ 整行锚定**照样绿**；
    ⚠ **全仓其余门项仍是盯串**（`arch_need_count` 共 117 条 ⇒ 整行锚定仅 11 条
    ⇒ 纯盯串 98 条、半锚定 8 条；`ci.sh` 34 条、审计器自身 10 条 ⇒ **逐批推进**）。
- ⚠⚠⚨ **锚定形态检查要扩到「门自己的工具」全集**（批 BM 实测）：
  - ⚠⚠⚨ **起因**：批 BL 把「盯探针的门项必须整行锚定」做成硬门
    ⇒ 但**适用范围只限探针文件**
    ⇒ ⚠ **审计器自身的 11 条门项仍是盯串**
    ⇒ 而审计器同样是「**门自己的工具**」⇒ 它被掏空 = 门**集体**失效。
  - **改法**：审计器自身的 11 条 ⇒ 17 条（6 处拆分：定义与使用形态不同
    ⇒ 一条整行正则罩不住）；⚠ 跟着改名的 2 条门项**原地替换**（不增行）；
    ⚠ 适用范围**集合化**成一个常量（`str.endswith(元组)` 是 python 原生
    ⇒ 判据一行就够 ⇒ 范围由**一个常量**说了算）。
  - ⚠⚠⚨ **自证**：范围一扩，审计器**当场报出 11 条违规** ⇒ 新检查不是摆设。
  - ⚠⚠⚨ **一个退出码有两种原因**（负控撞出）：把审计器「门型覆盖对拍」的判定行
    追加内容 ⇒ 实测 rc=2，但**真实情况根本没有盲区**
    ⇒ 根因：判定被掏空成恒真 ⇒ **恒走 blind 分支**
    ⇒ 只报一种 ⇒ **把排障带偏**（批 AZ 老问题换了形状）
    ⇒ 消息里**同时**点出第二种可能，并指路「看 rc=4（次数门配准，指名道姓是哪条命中 0）」。
  - ⚠ **本批没有新增门项** ⇒ 它的自护**就是**新检查本身：
    任何把审计器门项改回盯串 ⇒ 红；**适用范围被缩小** ⇒ 范围门项命中 0 ⇒ 红。
  - ⚠⚠⚨ **实测盘点（重新数）**：`arch_need_count` 共 **134** 条
    ⇒ 整行锚定 **65** 条、半锚定 **5** 条、纯盯串 **64** 条
    ⇒ 探针与审计器已**全部**整行锚定
    ⇒ 剩下的最大头是 **`ci.sh` 的 34 条**（下一批）。
- ⚠⚠⚨ **`ci.sh` 的门项要进整行锚定检查，但得先有豁免机制**（批 BN 实测）：
  - ⚠⚠⚨ **起因**：批 BM 盘点指出 `ci.sh` 的 34 条是最后一大块盯串
    ⇒ 而 `ci.sh` 是 **CI 入口** ⇒ 它的门项**必须**钉死。
  - ⚠⚠⚨ **实测有 6 条不能整行锚定**（**语义不许**，不是偷懒）：
    `ci.sh` 里 `--color-sample` 那条是 **shell 续行**（锚第一行挡不住下一行的真正动作）；
    `› [0-9]+/15 ` 是 15 个步骤打点行（后半段各不相同 ⇒ 只能通配 ⇒ 锚定**无增量价值**）；
    另外 4 条是「**期望 0 次**」的白名单门（语义是「不许出现在任何位置」
    ⇒ 整行锚定会把它**改窄**成「不许出现在某一种整行形态」）。
  - ⇒ **豁免机制**：独立文件 + **每行必写理由** + **坏行不豁免**（fail closed）；
    **键 =（门型, 相对路径, 门项正则）** 三者合起来才唯一
    （只用「路径+正则」⇒ 同一个正则被**不同门型**用时会**跨门型漏过去**）；
    **TAB 分隔**（正则含 `|`）；**比较时 rstrip**；豁免正则**只 rstrip 不 strip**。
  - ⚠⚠⚨ **「豁免表不许悄悄变长」怎么钉死**（第一版有洞，被自己抓住）：
    第一版反向配准是「豁免行对得上**任何**现存门项」⇒ ⚠ **有洞**：
    给一条**已经锚定**的门项加一行豁免 ⇒ 照样混过去
    ⇒ 「表里的条数 = 弱化点数」这条等式被破坏。
    ⇒ **改法**：双向配准**都对标「非锚定门项」集合**
    （正向：不豁免就红 rc=8；反向：对不上就红 rc=9）
    ⇒ 两者合起来 ⇒ **豁免表 ≡「非锚定门项」集合** ⇒ **条数是推导出来的**
    ⇒ **不必另写一个条数基线**（少一处可以被人偷偷改的地方）。
  - ⚠⚠⚨ **「判定体」也要单独钉**：只盯**调用点**盯不住**判定体**
    ⇒ 把 `return (kind, relpath, rx.rstrip()) in exempt` 掏空成 `return True`
    ⇒ **所有**门项都被豁免 ⇒ 门集体失效（比没豁免还糟）。
  - ⚠⚠⚨ **批 BM 留下一个真 bug，本批修掉**（**推送到已推送 HEAD 的真回归**）：
    批 BM 改名 `check_probe_gate_anchoring` → `check_gate_tool_anchoring` 时
    **漏改了报告模式（无参）那处调用点** ⇒ 报告模式一跑就 `NameError` 崩掉
    ⇒ 而 **CI 只跑 `--list`** ⇒ 这条路径**根本没人跑** ⇒ 崩了**没人发现**
    ⇒ 一路带到了已推送的 `1ef6b32`。
    ⇒ **三重修法**：① 报告模式改调**同一个**函数；
    ② 新增 `check_undefined_names()`（**symtable 实测能精确抓到那个名字**）作静态兜底；
    ③ 报告段把「未定义名清单」打印出来。
    ⇒ 审计器新增**第 9 种失败态**（rc=9）。
  - ⚠ **明确排除的两类**（如实记着，不是漏掉）：
    裸 `arch_need`（「至少 1 次」门）**不纳入**（语义是「串出现在任何位置」
    ⇒ 锚定会改窄；且每条都有**对位的 `arch_need_count` 整行锚定门** ⇒ 覆盖面不丢）；
    `arch_need_count_in_fn` / `_in_step` 不纳入（跨行是常态）。
  - **落门 / 判据**：批 BN 段 **13 条**；门项物理行数 761 → **779**
    （**+18** ＝ `ci.sh` 改整行锚定时拆出 5 条 ＋ 批 BN 段 13 条；其余原地替换）、
    执行次数 764 → **782**（⚠ 差 3 仍来自批 BH 的循环执行）；
    接线门 **782** 项全绿、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
    ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、**报告模式 rc=0**（批 BM 的崩已修）、
    恒真探针 **rc=0**、孤儿探针 **rc=0**；
    **负控 14/14 真红**（含 **H9 改名漏改复现** ⇒ 静态兜底抓到）。
  - ⚠⚠⚨ **批 BN 后重新盘点（不照抄二手数）**：`arch_need_count` 真实 **152** 条
    （⚠ `grep` 会多算 1 条 —— 那是 `arch_need_count()` 的**函数定义行**，
    审计器用 `FUNC_DEF_LINE` 排除它）⇒ 整行锚定 **111**、半锚定 **5**、**纯盯串 36**
    ⇒ 对比批 BM（134 ⇒ 65/5/64）：纯盯串 **−28**、整行锚定 **+46**。
    ⇒ 剩下的 36 条：`ci.sh` **6**（= 全部豁免）、`DocPages.cpp` 5、
    `ci-orphan-probe.sh` 3、其余 C++ 侧与探针脚本零散 ⇒ **逐批推进**。

- ⚠⚠⚨ **接线门脚本自己的「失败上报路径」必须有门**（批 BO 实测）：
  - ⚠⚠⚨ **起因**：批 BL/BM/BN 一路把「**判定被掏空、串还在**」往上收
    （探针 → 审计器 → `ci.sh`）⇒ 但**门脚本自己**（`ci-wiring.sh`）的
    **失败上报路径**从来没被任何门盯过。
  - ⚠⚠⚨ **实测坐实的洞**：`ARCH_FAIL=1` 是「**门型判定失败 → 整道门红**」的
    **唯一通路** ⇒ 把它改成 `ARCH_FAIL=0` ⇒ **那个门型的所有失败都静默**
    ⇒ 而审计器**自己重算命中数** ⇒ 期望与实际仍一致 ⇒ **审计器也抓不到**
    ⇒ 这是「判定被掏空」的最严重形态，而且是**批量**的。
  - **实测盘子**（门侧同口径量）：全文失败上报 **35** 处（**28** 处在 16 个
    门型/上报函数体内、**7** 处在顶层）；`arch_` 门型函数 **14** 个
    （**10** 个直接写上报、**4** 个 forbid 族**转发**给上报函数）。
  - **三层钉法**（不用新门型 ⇒ 审计器零改动）：
    - **per-函数**（16 条）—— 用现成的 `arch_need_count_in_fn`（它**认识函数体结构**）
      盯每个门型/上报函数体内**有几处上报** ⇒ **指名道姓**；
      转发型门型盯「**必须调用上报函数**」⇒ **转发关系被摘掉也红**。
    - **总数**（1 条）—— 全文 **35** 处 ⇒ 覆盖**顶层**那 7 处
      （⚠ 顶层块**没有花括号** ⇒ 提不出「函数体」⇒ 只能靠总数兜）。
    - **注册表**（1 条）—— `arch_` 门型函数**恰好 14 个** ⇒ **新增门型**必须改基线
      ⇒ 改的时候就会看到「**新门型也得有失败上报**」。
  - ⚠ **判据要避开自引**（批 BI 纪律）：总数与注册表的正则都**行首锚定**
    ⇒ 门项行自己不会被数进去 ⇒ 期望值里不混着「自己」。
  - ⚠⚠⚨ **实施踩的坑（值得记）**：插入锚点取的是那一行门项的**前缀**
    ⇒ 段被插进**行中间** ⇒ 那一行的第 4 个参数被**截断到段尾**
    ⇒ 门只收到 3 个参数 ⇒ `set -u` 下崩 rc=2 ⇒ **门项一条都没跑到**
    ⇒ **插入点必须落在整行之后**。
  - **落门 / 判据**：批 BO 段 **18 条**；门项物理行数 779 → **797**、
    执行次数 782 → **800**；接线门 **800** 项全绿、ci.sh **15/15**、
    selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、
    审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 14/14 真红**（含「顶层少一处 ⇒ 只有总数兜得住」与「新增门型 ⇒ 注册表红」）。

- ⚠⚠⚨ **恒真探针自己的「扫描范围」不许被改窄**（批 BP 实测）：
  - ⚠⚠⚨ **起因**：批 BJ 建了「**判据不许被掏空成恒真**」这一整类洞的探针
    （`ci-tautology-check.py`），批 BK/BM/BN 一路把「**判定被掏空、串还在**」
    往上收（探针 → 审计器 → `ci.sh`）⇒ 但**探针自己的扫描范围**从来没被任何门盯过。
  - ⚠⚠⚨ **实测坐实的洞**（不是推演）：把探针里「扫 `.sh` 脚本」那一行改掉
    （`fn.endswith('.sh')` → `fn.endswith('.shX')`）⇒ **所有 shell 脚本的 if 条件
    都不再被查恒真** ⇒ 而探针**自己没有条数基线** ⇒ 少扫了它也照样输出「✓」并
    **rc=0** ⇒ ⇒ 探针**静默变成半个空门** ⇒ 批 BJ 建立的「脚本侧捷径」
    **整类洞失守** ⇒ 而 CI **只跑这一个入口** ⇒ 没人会发现。
  - **实测盘子**（扫面盘点，不靠印象）：探针的**四个「范围」要素一个都没有门** ——
    判定层目录 `appdir` / 脚本目录 `scripts` / shell 范围 `.sh` / python 范围 `.py`；
    而 `JUDGEMENT_PREFIX`（批 BJ 段）、审计器侧 4 个常量（批 BM/BN 段）、
    孤儿探针白名单（批 BH 段）、契约门 93 处 `check` 调用点（批 BG 段）**都已有门**
    ⇒ ⇒ 缺口精确到这 4 行。
  - **两层修法**：
    - **范围行逐条钉住**（4 条，**整行锚定**）⇒ 改范围常量 / 改扩展名 ⇒ 必红
      （⚠ 判定层前缀那 2 条已在批 BJ 段 ⇒ 不重复落门）。
    - **扫到的文件数必须有基线** —— 新建独立文件 `scripts/ci-tautology-scope.baseline`
      （3 行纯数字：判定层 **4** / shell **18** / python **3**）
      ⇒ ⚠ **恰好**相等（批 BB 口径：「不少于」天生带余量 ⇒ 少一个还绿 ⇒ 没牙）
      ⇒ ⚠ **fail closed**（基线读不到 / 有坏行 ⇒ **照红**）
      ⇒ ⚠ **基线是自锚的**（批 BH 纪律的关键差别）：期望值写在**独立文件**里、
        实际值来自**文件系统** ⇒ 改基线单独就红 ⇒ **裁判改不了标准**
      ⇒ ⚠ 基线自己的行数也有门 ⇒ 基线被塞进第 4 行也红。
  - ⚠ **探针侧顺带修的两处**：**目录不存在 ⇒ 明确报错**（不许崩成 traceback ——
    崩掉的退出码也是 1 ⇒ CI 照样红但看不出是哪一步坏了 ⇒ 排障被带偏，批 AZ 纪律）；
    **检查必须复用变量** ⇒ 不另写字面量 ⇒ **两套口径必然漂**。
  - ⚠⚠⚨ **实施踩的三个坑（自己抓到的）**：
    ① **插入点必须用 `rindex`（最后一个）** —— `ci-wiring.sh` 里有**十三个**
    `if [ "$ARCH_FAIL" -ne 0 ]; then` ⇒ 用 `index` 会插到中间某段
    ⇒ 那一段前面的收尾会**提前 exit** ⇒ 新段的门项**根本跑不到**；
    ② **段序被搬乱** ⇒ 从备份恢复重做；
    ③ **门项正则与落盘文本不一致** ⇒ 校准用 `.\.sh.` 而落盘写 `.*\.sh.*`
    ⇒ 门项**抓不到变异** ⇒ 「整行锚定」名存实亡
    ⇒ **校准用的正则必须与落盘的正则完全一致**。
  - **落门 / 判据**：批 BP 段 **12 条**；门项物理行数 797 → **809**、
    执行次数 800 → **812**（⚠ 差 3 仍来自批 BH 的循环执行）；
    门项总数基线 `ci-wiring-gates.baseline` = **809**；
    接线门 **812** 项全绿、ci.sh **15/15**、selfcheck **395/0**、
    契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式 **rc=0**、
    恒真探针 **rc=0**（判定层 396 / if 498 / 实参 99 / 扫描范围 4-18-3 与基线一致）、
    孤儿探针 **rc=0**；**负控 14/14 真红**（含「四种范围被改窄 ⇒ 探针自己红
    **且** 门项红」与「基线被删 / 被改小 / 多一行 / 非数字行 ⇒ 全部照红」）。
  - ⚠ **已知边界（如实记着）**：⚠ **「范围」靠逐条钉住源码行挡住** ⇒ 探针若改成
    「按配置/环境变量决定范围」⇒ 那几行源码还在 ⇒ 门不红 ⇒ **范围仍可被改窄**；
    ⚠ **文件数基线挡不住「换了内容、没换数量」**；⚠ **基线是锚点 ⇒ 改基线 + 改探针
    同时做就躲得过**（批 BH 固有代价：diff 看得见）。

- ⚠⚠⚨ **「整行锚定」不许名存实亡：中间不许无界通配**（批 BQ 实测）：
  - ⚠⚠⚨ **起因**：批 BL/BM/BN 一路用**整行锚定**挡「**判定被掏空、串还在**」
    （探针 → 审计器 → `ci.sh`）⇒ 但**整行锚定只看「行首 `^`」+「行尾 `$`」**
    ⇒ 中间放一个**点星**（无界通配）⇒ 行首行尾锚死、**中间什么都能吃**
    ⇒ ⇒ 判定被掏空、串还在 ⇒ 门照样绿 ⇒ 「整行锚定」**名存实亡**。
  - ⚠⚠⚨ **实测坐实的洞**（不是推演）：探针的样例表门项
    `^\s+\(.*,\s*(True|False)\),$`（28 条）就是这种写法
    ⇒ 样例表内容**随便改都照样命中** ⇒ 那道门是**假的**
    ⇒ 这正是批 BL 留下的「**锚定 ≠ 内容**」那条边界，在本批**收掉一半**。
  - **实测盘子**（适用范围内逐条扫，不靠印象）：探针 / 审计器 / `ci.sh` 的
    `arch_need_count` 共 **124** 条 ⇒ 中间含无界通配的 **2** 条
    ⇒ 改造前整行锚定 **122**、**名存实亡 2** ⇒ 改造后 **124** 条**全部**名副其实。
  - **修法（三层）**：
    - **审计器加一条判定** `has_unbounded_wildcard()` —— 只认**未被转义**的点星
      （点号前**偶数**个反斜杠 ⇒ 是通配；**奇数**个 ⇒ 被转义 ⇒ 是字面点 ⇒ 放行）
      ⇒ 适用范围仍是「门自己的工具」⇒ 不扩大 ⇒ 违规 ⇒ 审计器**第 8 种失败态**（rc=8）
      ⇒ ⚠ **副作用（好事）**：`^.*$` 这种「锚定但极宽」的写法现在**也会被报出来**。
    - **自检必须含正反两面**（批 BF 纪律）：含点星的**必判违规** /
      有界通配的**必判合规** / 转义点星的**必判合规**
      ⇒ 判定被掏空时**当场红**（实测：审计器判定被改 ⇒ rc=8，**自检**抓的）。
    - **那 2 条「名存实亡」的门项改成精确形式**（本批同批改）：按「**类别 + 期望**」
      拆成 **9 条**（cond 6+3 / shortcut 8+4 / assert_arg 2+1+2+1 / shell_scan 1）
      ⇒ 中间用**有界**通配（`[^,]*` / `[^)]*` / `[^]]*`）⇒ 吃不掉结构分隔符
      ⇒ 行结构仍被钉住 ⇒ 整行锚定**名副其实**。
  - ⚠⚠⚨ **实施踩的三个坑（自己抓到的）**：
    ① **字符类不能写 `[^)]`** —— 样例 `('check', "d.get('x')==1")` 的实参里
    **带右括号** ⇒ `[^)]*` 提前停 ⇒ 实测命中 **0**（不是 1）⇒ 改用 `[^,]` 才罩住；
    ② **结构顺序不能想当然** —— `('shell_scan', (<文本>, [<列表>]), True)` 的
    **列表在右括号之前** ⇒ 正则必须写成 `\([^)]*, \[[^]]*\]\)` ⇒ 写反了实测命中 **0**；
    ③ **正则里不能有字面单引号**（批 BL 既有约束：shell 单引号包裹 ⇒ 会被截断
    ⇒ 落进 count-family 兜底 ⇒ **门型盲区**）⇒ 字符类里只能挑**不含引号**的
    结构分隔符 ⇒ 连带影响：审计器**自检样例的文本里也不能有逗号**
    （否则「数样例条数」那条门项的 `[^,]*` 会被逗号截断 ⇒ 计数失准 —— 实测踩到）。
  - ⚠⚠⚨ **新规则自己也要有门**（否则「规则被掏空」就白改）：批 BQ 段 **5 条** ——
    判定函数的**定义** / **转义计数判定行** / **「判违规」返回** / **调用点** /
    **自检样例条数（恰好 7）**。
  - **落门 / 判据**：门项物理行数 809 → **821**（-2 +9 +5）、执行次数 812 → **824**
    （⚠ 差 3 仍来自批 BH 的循环执行）；门项总数基线 `ci-wiring-gates.baseline` = **821**；
    接线门 **824** 项全绿、ci.sh **15/15**、selfcheck **395/0**、契约门 **120/0**、
    ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 14/14 真红**（含 ⚠ **「真实门项的中间被塞回点星 ⇒ rc=8」** ——
    本批核心证据，且命中数不变 ⇒ 唯一失败原因就是锚定形态）。
  - ⚠ **已知边界（如实记着）**：⚠ **本规则只认「未转义的无界通配」** ⇒ 字符类**内部**的
    点星（如 `[.*]`）会被误判成通配 ⇒ **假红**（fail closed 方向 ⇒ 不漏 ⇒ 只是误报）；
    ⚠ **有界通配放行** ⇒ 中间内容仍可变（只钉住「行结构」）⇒ 「换掉一条同类别同样例」
    这类变异**仍躲得过**（内容级保护靠**自检的期望**与**条数门**）；
    ⚠ **自检样例条数门用 `[^,]*`** ⇒ 将来加的样例文本里**不许有逗号**。

- ⚠⚠⚨ **把「门脚本本体」纳入「整行锚定」适用范围**（批 BR 实测）：
  - ⚠⚠⚨ **起因**：批 BL/BM/BN 把适用范围从「探针」扩到「审计器自身」
    再扩到「`ci.sh`（CI 入口）」⇒ 但**门脚本本体 `ci-wiring.sh` 自己**的门项
    **从来没进过适用范围**。
  - ⚠⚠⚨ **为什么这是洞**：`ci-wiring.sh` 的门项就是「**判定层不许被掏空**」
    这一整类承诺的**载体** ⇒ 载体自己的门项被掏空 ⇒ 那一整类承诺**集体失效**
    ⇒ 而且是**静默**的（没人会因为「门项变成盯串」而收到任何通知）。
  - **实测盘子**（重新数，不照抄二手数）：全仓 `arch_need_count` 共 **178** 条
    ⇒ 整行锚定 **134** / 半锚定 **8** / 纯盯串 **36**；
    目标 = `ci-wiring.sh` 的门项共 **7** 条 ⇒ 其中 **5** 条不是整行锚定
    （2456/2457 行尾缺 `$`、2514/2544 中间有**无界通配**、2567 行尾缺 `$`）。
  - **修法**（门项数不变 ⇒ 基线不变）：
    - 5 条改成**精确**形式（中间用**有界**通配 `[^$]*` / `[^"]*`
      ⇒ 吃不掉行尾 ⇒ 整行锚定**名副其实**）。
    - 审计器的 `ANCHOR_SCOPE_SUFFIXES` 加进 `'ci-wiring.sh'`
      ⇒ **必须单行**（⚠ 多行定义 ⇒ 守着它的门项是整行锚定 ⇒ 命中 0 ⇒ 自相矛盾）。
    - 守着那个常量的门项**原地替换**（批 BM 纪律：不增行）⇒ 门项数 **821** 不变。
  - ⚠⚠⚨ **实测：范围是「三重保护」**（与预想不同，如实记着）：
    预想「范围被改窄 ⇒ 审计器静默 ⇒ 门项才是唯一证据」⇒ **实测不是** ——
    范围**常量**被改 ⇒ 它本身被**次数门**钉着 ⇒ 审计器**次数配准**红（rc=4）；
    范围**使用点**被改（改成只看探针）⇒ 豁免表的**反向配准**对不上 ⇒ rc=9。
    ⇒ ⇒ 范围是三重保护（常量被次数门钉 + 使用点被次数门钉 + 被纳入的门项逐条查形态）
    ⇒ **三道线任一失效都还有别的线** ⇒ 但**门项那条线仍要单独断言**。
  - ⚠⚠⚨ **顺带把「哪些门项该锚定」写成判据**（不再是一句含糊的待办）：
    ⚠ **C++ 判定层的门项刻意保持「盯串」** —— 那些门项的承诺是
    「**这个 API 必须在某处被调用**」（**调用点**承诺）⇒ 整行锚定会把它
    **改窄**成「这一种整行形态」⇒ **合法重构就会断门**
    ⇒ ⇒ **锚定只对「判定行 / 定义行」承诺有意义**，不对「调用点」承诺有意义；
    且 C++ 侧「判定被掏空」的另一半（`|| true` 之类）**另有探针**兜着
    （恒真探针的捷径规则）⇒ 不是没有防线。
    ⇒ 所以「纯盯串 36 条」**不是待办清单**，而是**分两类**：
    ① 判定行/定义行 ⇒ 该锚定 ⇒ 逐批收（批 BN 收 `ci.sh`、批 BR 收 `ci-wiring.sh`）；
    ② 调用点承诺 ⇒ **不该**锚定 ⇒ 保持盯串（并写明理由）。
  - **落门 / 判据**：门项物理行数 **821**（不变）、执行次数 **824**（不变）、
    门项总数基线 = **821**（不变）；接线门 **824** 项全绿、ci.sh **15/15**、
    selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、
    审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 11/11 真红**（含 ⚠ **「新纳入的门项中间塞回点星 ⇒ rc=8」** ——
    本批核心证据）。
  - ⚠ **已知边界（如实记着）**：⚠ **范围是「后缀」判定的** ⇒ 将来若有
    **同名不同目录**的脚本会被**一并**纳入 ⇒ 只能放大不能缩小
    ⇒ 属 fail closed 方向 ⇒ 不漏 ⇒ 只是误报；
    ⚠ **`[^$]*` 依赖「注释里没有 `$`」** ⇒ 将来给那几行的注释里写 `$`
    ⇒ 命中数变 ⇒ 红 ⇒ 会显眼，但要改门项。

- ⚠⚠⚨ **「CI 里跑的断言脚本（探针们）」纳入「整行锚定」适用范围**（批 BS 实测）：
  - ⚠⚠⚨ **起因**：批 BL/BM/BN/BR 把适用范围从「探针」一路扩到
    「审计器自身 → `ci.sh` → `ci-wiring.sh`」
    ⇒ 但**CI 里真正跑的那些断言脚本**（`ci-platform-probe.sh` /
    `ci-docs-lang-probe.sh` / `ci-divider-probe.sh` /
    `probe-agent-tool-surface.sh` / `ci-orphan-probe.sh`）**自己的门项从来没进过适用范围**
    ⇒ 而它们的门项盯的正是**探针的判定行**。
  - ⚠⚠⚨ **实测的洞（每条都实测坐实，不是推演）**：盯探针判定行的那 **7 条**门项
    原来是**裸 `arch_need`（盯串）** ⇒ 判定被掏空但串还在 ⇒ 门假绿。
    实测能骗过它们的变异：
    - 把 `QT_SCALE_FACTOR=2` 挪进行尾注释
      ⇒「HiDPI 的效果断言必须真在 dpr=2 下跑」**退化成 dpr=1 的空断言**
      ⇒ ⚠ **正是那条门自己声称要防的** ⇒ 而旧门**看不出来**；
    - 把 `--docs-lang-probe` / `--divider-probe` 挪进行尾注释
      ⇒ 两个断言脚本「不再真的跑那个探针」也没人管；
    - 把 `field inkWidth` 挪进行尾注释 ⇒ 分隔线**不再真量墨迹宽**也没人管；
    - 把 `grep -Pq` 挪进行尾注释 ⇒ 文档语言**不再真查汉字**也没人管；
    - 把 `dpiEdgeLevels=legacy:` / `=.*aware:` 挪进行尾注释
      ⇒ HiDPI **边缘过渡层数**断言瞎了。
  - ⚠⚠⚨ **为什么这批变异能骗过旧门**：`.sh` 的 `strip_comments` 只剥**整行**注释
    （批 BK 既有约束）⇒ **行尾注释里的串照样被数到** ⇒ 旧口径「串还在就算数」。
  - **实测盘子**（重新数，不照抄二手数）：5 个探针脚本的门项共 **15** 条
    ⇒ **7 条**裸 `arch_need`（判定行）+ **5 条**「`✗ ` 条数门」
    + **3 条**孤儿探针自己的门项（2 条判定行 + 1 条白名单条数门）。
  - **修法（三层）**：
    - **7 条判定行门项 → 整行锚定的 `arch_need_count`（恰好 1 处）**
      （`^…$` + 中间不许无界通配，批 BQ 口径）⇒ 正则**全部由脚本生成**；
    - **5 条条数门 → 口径从「含标记的行」收紧成「真报错行」**
      （`^[[:space:]]*echo "[ ]*✗`）⇒ **行尾注释里的标记不再算数**
      ⇒「删一条真报错 + 在行尾注释里补一个标记」骗不过门了
      ⇒ ⚠ 行尾是**自由文本** ⇒ 整行锚定会**改窄语义**
      ⇒ ⇒ **显式登记在豁免表**（批 BN 机制，不是漏网）
      ⇒ 豁免表 **6 → 11** 条、**反向配准仍是自动推导**；
    - **适用范围常量 `ANCHOR_SCOPE_SUFFIXES` 加 5 个探针**（**必须单行**，批 BR 教训）
      ⇒ 守着它的门项**原地替换**（批 BM 纪律：不增行）
      ⇒ 以后谁给这些脚本加盯串门项 ⇒ **审计器当场红**（rc=8）。
  - ⚠⚠⚨ **顺带修掉审计器的一个「假红」（本批自己撞出来的）**：
    有一条新门项要钉住 `ci-orphan-probe.sh` 里那行「排除门项行」的规则，
    而那行**行尾是反斜杠**（shell 续行）⇒ 整行锚定的正则必须以 `\\$` 结尾
    ⇒ 审计器原判据 `rx.endswith('\\$')`
    ⇒ ⚠⚠⚨ **把 `\\$`（转义反斜杠 + 行尾锚点）也误判成「`$` 被转义」**
    ⇒ 合法门项被红 ⇒ **逼着人把门项写弱**
    ⇒ 改成**数反斜杠个数**（**奇数** = 被转义；**偶数** = 是锚点）
    ⇒ 与批 BQ 的 `has_unbounded_wildcard` **同款奇偶口径**
    ⇒ ⚠ **假红比假绿更坏**：假绿是承诺悄悄消失；假红是**逼人把承诺改弱**
    ⇒ 自检补 **2 条**样例 ⇒ 样例条数 **7 → 9**。
  - ⚠⚠⚨ **实施踩到的坑（自己抓到的）**：
    ⚠ **正则不许手写** —— 本批**手写三次、三次都错**（`ci-platform-probe.sh` 误写成 `.py`；
    「单引号位置写 `.`」在 heredoc 里被误写成 `\.`；改 L2512 时又手写一遍同样的 `.py`）
    ⇒ ⇒ 全部正则改由**名字列表脚本生成**（校准脚本是唯一真相源、落盘从它 import
    ⇒ 校准用的正则与落盘用的正则**逐字节相同**，批 BP 纪律）；
    ⚠ **标签别用 `split("' '")` 取** —— 门项行里没有 `' '` 这个分隔符
    ⇒ 取到**整行** ⇒ 落盘后 `sh -n` 报语法错。
  - **落门 / 判据**：门项物理行数 **821 → 823**（+2 = 批 BS 段那 2 条自护门项）、
    执行次数 **824 → 826**、门项总数基线 = **823**；接线门 **826** 项全绿、
    ci.sh **15/15**、selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、
    快照**零变化**、审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 25/25 真红**（51 条断言全绿；核心证据 =
    **旧门（从备份现抽）在变异后仍绿 + 新门（现抽）在变异后红**）。
  - ⚠ **已知边界（如实记着）**：⚠ 「真报错行」口径只认 `echo "✗ ` 开头的行
    ⇒ 将来改成 `printf` ⇒ 计数会掉 ⇒ 红 ⇒ 会显眼，但要改门项；
    ⚠ **整行锚定 ≠ 内容**（中间仍有有界通配 ⇒ 「换掉一条同形态的判定」仍可能躲过）；
    ⚠ **合同门 / deb 布局门**没进适用范围 —— 它们的门项数的是**调用点**、
    行尾还有实参 ⇒ 行尾锚定会**改窄语义** ⇒ 有意保持现状；
    ⚠ **真机探针**（`probe-deepin-tray.sh` / `probe-sni-icon.sh`）不在 CI 里跑 ⇒ 也没进范围。

- ⚠⚠⚨ **探针脚本的「失败上报」不许被摘掉**（批 BT 实测）：
  - ⚠⚠⚨ **起因**：批 BS 把 5 个探针脚本**纳入「整行锚定」适用范围**
    ⇒ 它们的**判定行**不许被掏空了
    ⇒ 但**「失败上报」这条链**一直没人管：
    `✗ ` 报错行 → `exit N` / `return 1` / `fail=1` → 脚本退出码 → CI 判红
    ⇒ 中间那一环被摘掉 ⇒ **断言变空转**。
  - ⚠⚠⚨ **实测坐实的洞（行为级，不是推演）**：
    - 造一个「**只让最后一条断言失败**」的假探针（平台探针要的字段全报对，
      只让「有图标主题但有图标解析不到」那条失败）；
    - **未变异**时：探针 **exit 1**（失败会传出去）✅；
    - 把 `ci-platform-probe.sh` **最后一条** `✗ ` 后面的 `exit 1` 摘掉
      ⇒ 探针 **exit 0**、照样打印「**✓ 平台探针通过**」
      ⇒ ⇒ **CI 假绿**（断言失败了，CI 报通过）；
    - 而**现有门全绿** —— `✗ ` 条数门数的是 **20 条报错行**，一条没少 ⇒ 绿。
    ⇒ ⇒ 「**探针的失败必须真的让 CI 失败**」这个承诺，**从来没有门**。
  - ⚠⚠⚨ **为什么现有门看不见它**：那两条门数的是**不同的东西**
    —— 「`✗ ` 条数门」数**报错文案行**、「失败上报」数**退出语句**
    ⇒ 报错行还在、退出语句没了 ⇒ 前者绿、后者（不存在）
    ⇒ **中间缺一环，整条链断**。
  - **修法（一层）**：给每个探针脚本加一条「**失败上报语句的条数**」门项
    （正则 `^[[:space:]]*(exit [1-9]|return 1|fail=1)$` ⇒ **整行锚定**
    ⇒ 审计器会查 ⇒ 改回盯串就 rc=8）
    ⇒ 期望值**逐脚本校准**：`ci-platform-probe.sh` **22** /
    `ci-docs-lang-probe.sh` **10** / `ci-divider-probe.sh` **9** /
    `probe-agent-tool-surface.sh` **11** / `ci-orphan-probe.sh` **6**
    ⇒ 摘掉任何一条、或改成 `exit 0` / `fail=0` ⇒ 条数变少 ⇒ **必红**。
  - ⚠⚠⚨ **口径必须说清楚（不是 1:1 配对）**：`ci-platform-probe.sh` 的 22 条里有
    辅助函数的**内层 + 外层**报错（多出来）、**awk 程序内部**的 `exit 1`
    （也属结构断言的失败链）；`probe-agent-tool-surface.sh` 的 11 条里有 2 条
    `exit 3`（**SKIP**，语义是「未验证，不算通过」⇒ 也是失败）
    ⇒ ⇒ **只钉总数，不钉配对** ⇒ 标签里如实写明
    ⇒ 后果：「把一条 `✗ ` 改成**两个**失败上报」**总数会变** ⇒ 仍红。
  - **落门 / 判据**：门项物理行数 **823 → 828**（+5）、执行次数 **826 → 831**、
    门项总数基线 = **828**；豁免表**不变**（11 条 —— 新门项是整行锚定的）；
    接线门 **831** 项全绿、ci.sh **15/15**、selfcheck **395/0**、契约门 **120/0**、
    ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式 **rc=0**、
    恒真探针与孤儿探针 **rc=0**；
    **负控 11/11 真红**（24 条断言全绿；核心证据 =
    **行为级**：变异后探针仍会报错且 **exit 0** ⇒ 假绿坐实；未变异时 exit 1）。
  - ⚠ **已知边界（如实记着）**：⚠ **只覆盖批 BS 范围内的 5 个探针**
    ⇒ `scripts/` 下还有 **11** 个断言脚本（共 16 个）没被覆盖 ⇒ 逐批推进；
    ⚠ **静态口径**：失败上报若写成别的花样（`exit $RC`、`command || exit`）
    ⇒ 计数会掉 ⇒ 红 ⇒ 会显眼，但要改门项；
    ⚠ **总数口径不是配对口径** ⇒ 「总数不变地把一条失败上报换成另一条」这类改法躲得过。

- ⚠⚠⚨ **helper 型断言脚本：「失败助手」与「断言清单」都要有门**（批 BU 实测）：
  - ⚠⚠⚨ **起因**：批 BT 给 5 个探针脚本补了「失败上报不许被摘掉」的门
    ⇒ 但 `scripts/` 下共 **16** 个断言脚本
    ⇒ 逐个盘点（**实测，不靠印象**）后发现 **`build-deb.sh` /
    `probe-deepin-tray.sh` / `probe-sni-icon.sh` 的失败上报写法与别的不同**
    —— 它们用**助手**统一报错（`die()` / `fail()`）
    ⇒ `✗ ` 标记**只在助手体内**（三者的 `✗ ` 标记数都只有 **1**，
      而 `die`/`fail` 调用分别是 **20 / 7 / 10** 处）。
  - ⚠⚠⚨ **实测坐实的两个洞**：
    - **「`✗ ` 条数门」对它们形同虚设** —— 数出来只有 1（助手在 ⇒ 绿）
      ⇒ 删掉任意一条断言调用，门照样绿
      ⇒ ⇒ 批 BC 承诺的「**清单不许被删**」对它们**从来没兑现过**；
    - **助手里的 `exit 1` 被摘掉 ⇒ 所有断言变空转**（同批 BT 的洞）
      ⇒ **行为级实测**：把 `probe-deepin-tray.sh` 的 `fail` 助手改成 `exit 0`
      ⇒ 喂一个不存在的程序 ⇒ **未变异 exit 1**（失败传出去）、
      **变异后 exit 0** ⇒ 而且**照样打印 `✗` 报错**
      ⇒ 「**报了错却报成功**」⇒ **CI 假绿**。
  - **修法（两层）**：
    - **助手定义行必须整行锚定**
      （`^die\(\) \{ echo "✗ build-deb: \$\*" >&2; exit 1; \}$` /
      `^fail\(\) \{ echo "✗ \$1" >&2; exit 1; \}$`）⇒ 助手被掏空 ⇒ 红；
    - **助手调用点数必须恰好 N**（20 / 7 / 10）⇒ 删掉任意一条断言调用 ⇒ 红。
  - ⚠⚠⚨ **口径为什么不能行首锚定（实测）**：助手调用常写在行中
    （`[ -f "$BIN" ] || die "..."`）⇒ 只用 `^` 锚行首会**少数**
    （实测 build-deb.sh **20 → 5**）⇒ 计数必须按**调用点**计
    ⇒ ⚠ **强度弱于行首锚定** ⇒ **如实记为已知边界**（行尾注释理论上能冒充）
    ⇒ 试过「语句起始锚」（`(^|‖|&&|;)`）⇒ **行数对不上**
    （`probe-sni-icon.sh` 的 `PARSE_FAIL*) fail "…"` 是 `case` 分支 ⇒ 漏 1 处）
    ⇒ ⇒ 只能用**词边界**口径（`\b(die|fail) "`）。
  - ⚠⚠⚨ **这次只收了哪 3 个、其余为什么没收（如实记着）**：
    - ✅ 收 `build-deb.sh` / `probe-deepin-tray.sh` / `probe-sni-icon.sh`
      （断言清单**从来没门**、失败上报**从来没门**）；
    - ❌ 不收 `ci.sh` / `ci-d2.sh` / `smoke.sh`：它们的 `✗ ` 是**错误消息**，
      不是「每个错误消息对应一条断言」的分支
      ⇒ 删一条消息**不等于**删一条断言 ⇒ 这条承诺对它们不成立；
    - ❌ 不收 `ci-wiring.sh`：它的 `✗ ` 是**门项自己的失败文案**，
      且失败上报路径**已由批 BO 三层钉法**管着 ⇒ **不重复覆盖**；
    - ❌ 不收两个 `.py`：输出标记不是「一条断言一个标记」形态；
      且 `ci-tautology-check.py` 的自检样例**已由批 BQ 的 9 条样例条数门**管着。
  - **落门 / 判据**：门项物理行数 **828 → 834**（+6）、执行次数 **831 → 837**、
    门项总数基线 = **834**；豁免表**不变**（11 条 —— 这 3 个文件不在适用范围
    ⇒ 盯串门项不需要豁免）；接线门 **837** 项全绿、ci.sh **15/15**、
    selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、
    审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 11/11 真红**（20 条断言全绿；核心证据 =
    **行为级**：未变异 exit 1、变异后 exit 0 且**仍打印 `✗` 报错**
    ⇒ 「报了错却报成功」⇒ CI 假绿）。
  - ⚠ **已知边界（如实记着）**：⚠ **调用点数门强度弱于行首锚定**
    ⇒ 更强做法是把助手调用**改成每条单独一行**（那样就能行首锚定）⇒ **本批不做**；
    ⚠ 这 3 个脚本**不在**「整行锚定」适用范围里 ⇒ 那 3 条调用点数门是**盯串**形态
    ⇒ 将来纳入范围需**显式豁免**；⚠ 只覆盖这 3 个 ⇒ 其余脚本的「清单」形态各不相同
    ⇒ 逐批推进。
- ⚠⚠⚨ **无头路径的收尾：「退出时 QApplication 必须还活着」——CI 偶发段错误的真身**（批 BV 实测）：
  - ⚠⚠⚨ **起因**：CI 偶发段错误（探针退出码 **139**）一直只知其然不知其所以然
    ⇒ 前几批只做到「崩了要说清是什么信号」⇒ 但**崩在哪**没人知道
    ⇒ 本批把它挖到根因，并给「不许回到那个坑」落门。
  - ⚠⚠⚨ **取证（全部实测，不是推演）**：
    - 崩溃那次的 CI 日志 = **完整 `ci.sh` 运行**，崩在第 4 步的
      `--platform-probe` 脚本里 **dpr=2 那趟**；
    - 自写 core 解析器 ⇒ 崩溃线程 rip 落在 **libQt6Core 的
      `QCoreApplication::notifyInternal2`**，故障指令 `mov (%rdi),%rax`，**rdi = 0**；
    - 探针进程实测**正好 3 个线程**（`deepDolphin` / **`QDBusConnection`** /
      `DConfigGlobalTh`），与 core 里的 3 个 NT_PRSTATUS 一一对应
      ⇒ 崩溃的是 **`QDBusConnection` 线程**（栈上有 `QEventLoop::exec`）；
    - 反汇编逐条对上：`159d91 lea ...,%rbp`（rbp = `&QCoreApplication::self`）
      → `159d98 cmpq $0x0,0x0(%rbp)`（**第一次读：非空，通过**）
      → `159dc3 call QInternal::activateCallbacks`（**这里主线程把 self 置空**）
      → `159de1 mov 0x0(%rbp),%rdi`（**第二次读：已是 NULL**）
      → `159dec mov (%rdi),%rax`（**崩**）；
    - `QCoreApplication::~QCoreApplication()` 里 `15beee: movq $0x0,(%rax)`
      写的**正是** `QCoreApplication::self`
      ⇒ **析构 QApplication 会把 self 置空**；
    - NT_SIGINFO 的 `si_code = -6 (SI_TKILL)` + `si_pid = 自己的 pid`
      ⇒ core 里的信号是**我们自己**的 `CrashHandler` 在 handler 里 `raise(sig)` 重发的
      （handler 里信号被自动屏蔽 ⇒ `raise` 只挂起 ⇒ 恢复时按**原故障现场**落 core
      ⇒ 崩点寄存器仍在 core 里，但 `si_addr`/`si_code` 被顶掉）。
  - ⚠⚠⚨ **根因（一句话）**：**主线程析构 `DApplication` 的同一时刻，
    `QDBusConnection` 后台线程正在 `notifyInternal2()` 里派发事件**
    ⇒ 它第二次读 `self` 时拿到 NULL ⇒ 空指针解引用 ⇒ **SIGSEGV**；
    而平台探针的收尾**正好**踩在这个窗口上（`::_exit` 写在 app 作用域**之外**）
    ⇒ ⚠ 旁证：另两个无头探针的 `::_exit` 写在作用域**之内** ⇒ 一直安全
    ⇒ **只有平台探针是那个形状**。
  - **修法（三层）**：
    - **产品侧**：所有无头路径（快照 / 色样张 / 平台探针 / 文档语言探针 / 分隔线探针）
      统一走**唯一收尾出口 `probeExit()`** —— 它在**退出那一刻**报
      **可断言的事实** `appAlive=<0|1>` 再 `_exit`
      ⇒ **退出时 QApplication 还活着**（app 永不析构）⇒ 竞态不存在
      （平台探针的 `QSystemTrayIcon` 单独一个作用域 ⇒ 托盘图标**仍在退出前被摘掉**，
      真机不留残影）；
    - **CI 侧**：三个探针脚本**各断言** `appAlive=1`（平台探针**两跳**都断言）
      ⇒ 那个竞态**从「偶发」变成「必红」**（退出点一旦挪回 app 作用域之外
      ⇒ 事实变 0 ⇒ 门立刻红）；
    - **顺带**：三个探针脚本里探针调用的 **`2>/dev/null` 全去掉**
      ⇒ 崩了时 `CrashHandler` 的**栈回溯（崩点）**能进 CI 日志
      （以前只剩一句「退出码 139」）。
  - **落门 / 判据**：新增 **9** 条 ——
    3 条「`appAlive=1` 断言不许被删」（平台 **2** / 文档语言 **1** / 分隔线 **1**，
    **整行锚定**）+ 3 条「`appAlive` 事实不许被删（恰好 1）/ `_exit` 只许在 `probeExit`
    里（恰好 1）/ 收尾必须走 `probeExit`（恰好 8）」（`src/main.cpp`）+
    3 条「探针的 **stderr 不许被扔掉**」（`arch_forbid`）。
    跟着改的门项**原地替换、不增行**（批 BM）：3 条「探针调用行」正则去掉
    `2>/dev/null`、3 条「真报错行」条数门 **20→22 / 10→11 / 9→10**、
    3 条「失败上报语句」条数门 **22→24 / 10→11 / 9→10**
    ⇒ 说明文字数字**同步改**（批 BB）。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ **本机没能复现那个段错误**（8 worker × 400 轮 × 2 跳 =
      **6400 次启动，0 次崩溃**）⇒ ⇒ 修复效果**不是**用「复现率下降」证明的，
      而是用**行为级负控**证明的（「把退出点挪回 app 作用域之外 ⇒ `appAlive=0`
      ⇒ CI 必红」）⇒ 即「竞态被消除」+「万一它回来必红」两件事都由负控钉住；
    - ⚠ **`probe-agent-tool-surface.sh` 没收**：它不构造 QApplication（无本竞态），
      但它**探针退出码没被检查** ⇒ 崩了会被当成「引擎未找到」的 **SKIP（exit 3）**
      ⇒ 「**崩了不许被当成 SKIP**」这条承诺**还没有门** ⇒ 下一批；
    - ⚠ **本批是「判据层批次」里的例外**：**有产品代码改动**（`src/main.cpp` 的收尾口径）
      —— 那个竞态**在产品代码里**，判据层改不掉它 ⇒ 改产品 + 落门一起做；
      改动面只动**无头路径的收尾**，**不碰业务逻辑与界面**。
  - **数字**：门项物理行数 **834 → 843**（+9）、执行次数 **837 → 846**、
    门项总数基线 = **843**；豁免表**不变**（11 条 —— 新门项是整行锚定的，
    `arch_forbid` 族按惯例不审锚定形态）；接线门 **846** 项全绿、ci.sh **15/15**、
    selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、
    审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 20/20 真红**（20 条断言全绿；核心证据 =
    **行为级**：退出点挪回 app 作用域之外 ⇒ 探针报 **`appAlive=0`** ⇒ **CI 必红**
    ⇒ 那个竞态**从「偶发」变成「必红」**）。
- ⚠⚠⚨ **「探针崩了」不许被当成「未验证」（SKIP）**（批 BW 实测）：
  - ⚠⚠⚨ **起因**：批 BV 把「崩点不许被吞」做进了三个探针脚本，
    但 `probe-agent-tool-surface.sh` 当时**没收**（如实记成了已知边界）
    ⇒ 顺手查了一遍，发现**更糟**。
  - ⚠⚠⚨ **实测坐实的洞**：那个脚本的探针调用**根本没接退出码**
    （`OUT="$(… --agent-tool-surface 2>/dev/null)"` + `if [ -z "$OUT" ]; then … exit 3; fi`）
    ⇒ 它**只看「stdout 空不空」** ⇒ 三种完全不同的事被塞进同一支：

    | 实际情况 | stdout | 旧脚本的判法 | CI 看到什么 |
    |---|---|---|---|
    | 引擎真的没找到 | 空 | SKIP（exit 3） | ‣ SKIP（未验证）—— **对** |
    | **探针崩了（139）** | 空 | **SKIP（exit 3）** | ‣ SKIP（未验证）—— **错！** |
    | **探针说成功却没输出** | 空 | **SKIP（exit 3）** | ‣ SKIP（未验证）—— **错！** |

    ⇒ `ci.sh` 第 13 步看到 exit 3 ⇒ 打印「‣ SKIP …未验证」⇒ **CI 整体照样绿**
    ⇒ ⇒ 「**崩了**」被伪装成「**环境不具备**」⇒ 崩点彻底看不见。
  - **修法（三层）**：
    - **产品侧**：「引擎未找到」用**专属退出码 3**（= 未验证），其它失败用 1
      ⇒ 「未验证」与「失败」在**退出码**这一层就分开了；
    - **CI 侧**：脚本**接住退出码**并分诊（**3 = SKIP / 其它非 0 = 失败**），
      且 stderr **落盘、失败时原样吐出** ⇒ 崩点（`CrashHandler` 的栈回溯）看得见；
    - **顺带**：工具面探针的收尾也收口到 `probeExit`（批 BV 的口径）
      ⇒ ⇒ 「**所有无头路径统一走 `probeExit`**」这句话**这才真的成立**。
  - ⚠⚠⚨ **行为级实测（假探针，三种形态）**：
    - `kill -SEGV $$`（139）⇒ **旧形态 exit 3（SKIP）⇒ 假绿坐实** /
      **新形态 exit 1（失败）**，并把 stderr（崩点）吐出来；
    - `exit 3`（引擎未找到）⇒ **仍 exit 3（SKIP）**（语义**没变**）；
    - `exit 0` 但无输出 ⇒ **exit 1**（假绿被抓住）。
  - **落门 / 判据**：新增 **5** 条 —— 3 条「**退出码分诊**必须原样存在」
    （**整行锚定**：探针调用行必须是 `… 2>"$ERR_FILE")" || PROBE_RC=$?`、
    必须有 `-eq 3`（SKIP 支）与 `-ne 0`（失败支））+ 1 条「退出码 0 却无输出
    ⇒ 必须判失败」（盯那条 `✗` 报错行，**整行锚定**）+ 1 条（产品侧）
    「引擎未找到 ⇒ 必须用**专属退出码 3**」（`src/main.cpp` 里 `probeExit(3);` 恰好 1）。
    跟着改的门项**原地替换、不增行**（批 BM）：「真报错行」条数门 **9→11**、
    「失败上报语句」条数门 **11→13**、批 BV 的「收尾必须走 `probeExit`」**8→11**
    ⇒ 说明数字**同步改**（批 BB）。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ 这个脚本**没有**「`2>/dev/null` 一律不许」的门 —— 它**有两处合法用法**
      （`mktemp 2>/dev/null`、`[ … ] 2>/dev/null`）⇒ 加 forbid 门会**假红**
      ⇒ 改用「盯住探针调用那一行」的整行锚定门 ⇒ ⚠ **强度弱于全文件 forbid**；
    - ⚠ 「崩了 vs 未验证」的区分**依赖探针自己用 3 表示未验证**
      ⇒ 将来新增别的「未验证」情形必须**同样用 3**，否则会被判成失败（可接受）；
    - ⚠ 其余断言脚本（`scripts/` 下共 16 个）**还有多少没接探针退出码**，
      本批**没逐个查** ⇒ 这条承诺目前**只对这一个脚本有门** ⇒ 逐批推进。
  - **数字**：门项物理行数 **843 → 848**（+5）、执行次数 **846 → 851**、
    门项总数基线 = **848**；豁免表**不变**（11 条）；接线门 **851** 项全绿、
    ci.sh **15/15**、selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、
    快照**零变化**、审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 16/16 真红**（16 条断言全绿；核心证据 =
    **行为级**：旧形态下崩了被报成 SKIP（**假绿坐实**）、新形态下 **exit 1（失败）**
    + 报出「退出码 139」+ **崩点被吐出来**）。
- ⚠⚠⚨ **「崩了」必须被判成「崩了」：退出码不许被吞、stderr 不许顶替 stdout**（批 BX 实测）：
  - ⚠⚠⚨ **起因**：批 BW 标了「其余断言脚本还没逐个查」
    ⇒ 本批**逐个盘点**了 `scripts/` 下全部 **16** 个断言脚本对
    「我们自己的二进制 / 探针脚本」的调用（逐行看的，不是印象）
    ⇒ 盘出**两处具体的洞**。
  - ⚠⚠⚨ **洞 ①（行为级·假绿）**：`check-deb-layout.sh` ⑧「空环境下能跑 --version」
    原来是 `VOUT="$(env -i "$BIN" --version 2>&1 | head -3)"` + 「**有输出就算过**」
    ⇒ ① **退出码完全没查** ② **`2>&1` 把 stderr 合并进 stdout**
    ③ 判据只是「有输出」
    ⇒ **实测**：造一个「先往 stderr 打一行警告、再 `kill -SEGV` 崩掉」的假二进制
    ⇒ 这一门判 **✓ 可执行在空环境下能跑起来** ⇒ **假绿**
    ⇒ 换句话说：**D7 的「装完能不能用」准验收，对一个段错误崩掉的包判「能跑」**。
  - ⚠⚠⚨ **洞 ②（形态级·诊断失真）**：`ci-platform-probe.sh` 的 dpr=2 那跳用
    「**下一行**再取 `$?`」⇒ `$?` 只对**紧邻的上一条**命令有效
    ⇒ 中间插一行 ⇒ 退出码被换成**别人的**
    ⇒ 崩溃被伪装成「探针没输出」⇒ 门虽然还是红的但**诊断失真**。
  - **修法**：
    - `check-deb-layout.sh` ⑧：**查退出码**（非 0 ⇒ 判失败）+
      **stderr 不混进 stdout**（stdout 单独取、stderr 原样透出 ⇒ 崩点看得见）；
    - `ci-platform-probe.sh`：**退出码改成同行取**（`|| VAR=$?`）⇒ 形态固定，
      插一行也断不了（批 BV 已在另外三跳用同一形态）；
    - 同理 `dpi_struct_assert()` 里那处 `dpi_a_rc=$?` 也改成同行取。
  - ⚠⚠⚨ **盘点结论（哪些本来就是安全的）**：
    - `smoke.sh`（`if "$BIN" --selfcheck`）**查** ⇒ 安全；
    - 三个探针脚本（批 BV/BW）**查** ⇒ 安全；
    - `contract-check.sh` 的 20+ 处都是「解析型」探针 ⇒ 判据是**输出内容**
      ⇒ 崩了 ⇒ 内容空 ⇒ 比对失败 ⇒ **响亮失败** ⇒ 安全；
    - `ci.sh` / `ci-wiring.sh` 的步与门**查** ⇒ 安全；
    - `build-deb.sh` / `build.sh` / `dev-run.sh` / `setup-deps.sh` /
      `probe-deepin-tray.sh` / `probe-sni-icon.sh` **不跑我们的二进制** ⇒ 不适用。
  - **落门 / 判据**：新增 **2** 条（`check-deb-layout.sh`，**整行锚定**）：
    ① 「`--version` **必须查退出码**且 **stderr 不许混进 stdout**」
    （盯 `VOUT="$(env -i "$BIN" --version)" || VRC=$?` 那一行
    ⇒ **一条门同时排除掉 `2>&1` 那种写法**）+ ②「退出码非 0 **必须判失败**」。
    **原地替换**（批 BM，不增行）：批 BS 的「dpr=2 那跳」门项正则改成
    「那一行 + **同行取退出码**」、说明文字同步；「ok/no 清单」条数门 **14 → 15**
    ⇒ 说明同步（批 BB）。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ 盘点口径是「调用**我们自己的**二进制 / 探针脚本」
      ⇒ 「调用外部工具（`readelf` / `xprop` / `dpkg-deb` …）后拿它的退出码当判据」
      **不在本批范围**（失败通常直接进 `die` / `no`，风险形态不同）⇒ 下一批可议；
    - ⚠ `check-deb-layout.sh` **不在**「整行锚定」适用范围里
      ⇒ 本批那 2 条门**恰好**写成整行锚定（更强），
      但**审计器不会**因为将来有人写弱而红 ⇒ **如实记着**；
    - ⚠ 「stderr 原样透出」⇒ CI 日志会多出 DTK 噪声行
      ⇒ 可接受（崩点可见 > 日志干净），但**没有门管住噪声量**。
  - **数字**：门项物理行数 **848 → 850**（+2）、执行次数 **851 → 853**、
    门项总数基线 = **850**；豁免表**不变**（11 条）；接线门 **853** 项全绿、
    ci.sh **15/15**、selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、
    快照**零变化**、审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 9/9 真红**（9 条断言全绿；核心证据 =
    **行为级**：崩掉的假二进制在**旧形态**下被判 **✓「能跑起来」**（假绿坐实）、
    在**新形态**下被判 **✗「退出码 139」**）。
- ⚠⚠⚨ **「失败计数不许被掏空」：计数器型断言脚本的 fail 计数必须真的有门**（批 BY 实测）：
  - ⚠⚠⚨ **起因**：批 BT/BU 把「失败上报」的门型收进了 `exit N` 形态的脚本
    ⇒ **计数器型**（`fail=$((fail+1))` + 末尾 `[ "$fail" -eq 0 ]`）的脚本**从来没被收过**。
  - ⚠⚠⚨ **盘点**（逐个 grep 的，不是印象）⇒ **全仓只有 2 个脚本是计数器型**：
    - `check-deb-layout.sh`：**1** 处计数（唯一的 `no()` 助手）；
    - `contract-check.sh`：**39** 处计数（2 个助手 + 37 处行内）；
    - 其余 14 个断言脚本全是 `exit N` 形态 ⇒ 批 BT/BU 已收 ⇒ 本批一次收干净。
  - ⚠⚠⚨ **洞（行为级·假绿）**：失败判定链是三环 ——
    **① 报错**（`echo "  ✗ …"`）⇒ **② 计数**（`fail=$((fail+1))`）⇒
    **③ 末尾判定**（`[ "$fail" -eq 0 ]` 决定退出码）
    ⇒ **中间那一环被摘掉** ⇒ **报错照打**（stderr 里明明写着「✗」）
    但**永远不计数** ⇒ 末尾判定恒真 ⇒ 脚本 `exit 0` ⇒ **CI 假绿**。
    - ⚠⚠⚨ 「**复位**」尤其阴：计数**一条不少**
      ⇒ 任何「数计数点」的门都抓不到 ⇒ 必须另有一条「**写 `fail` 的行数**」的门。
  - ⚠⚠⚨ **行为级实测（假绿坐实）**：
    - **A1**：用 `dpkg-deb -b` 造一个**真会失败**的假包（可执行一启动就 `exit 1`
      + 缺 desktop/service/metainfo + 零字节图标）⇒ 真跑 ⇒ **rc=1、5 条失败**
      ⇒ 摘掉 `no()` 里的计数 ⇒ **rc=0、0 条失败**而 stderr **照样打着「✗」**；
    - **A2**：在 `contract-check.sh` 副本里注入一条真失败
      （走**真实** `check()` 助手）⇒ **rc=1、1 条失败**
      ⇒ 摘掉助手的计数 ⇒ **rc=0** 而输出**照样打着「✗ 注入失败」**；
    - **A3**：判定之前插 `fail=0` 复位 ⇒ **rc=0** 而摘要**照样打印「5 failed」**
      ⇒ **摘要与退出码当场打架**。
  - **修法**（本批只动判据层 ⇒ **零产品代码改动**）：
    - 两个脚本的**失败计数点 / 成功计数点 / 末尾判定行**逐条**整行锚定**；
    - 计数点按**形态**分组钉住（助手行 / 独立成行 / 带 `>&2` 的自由文案 /
      `|| { …; }`）⇒ 「删一处 + 补一处同形态」也躲不过（**总数不变也红**）；
    - 加「**写 `fail` 的行数**」门 ⇒ 「判定前复位」也红；
    - 两个脚本**纳入审计器的「整行锚定」适用范围** ⇒ 将来这些门被写弱
      审计器就会红（**收掉批 BX 留下的已知边界**）。
  - **落门 / 判据**：新增 **12** 条（**全部整行锚定**）——
    `check-deb-layout.sh` **5** 条（`no()` 定义行 / `ok()` 定义行 / 末尾判定行 /
    **写 `fail` 的行数 2** / 失败增量行数 1）+
    `contract-check.sh` **7** 条（两个助手的失败计数行 2 / 独立成行的增量 31 /
    带 `>&2` 的自由文案增量 4 / `|| { …; }` 形态的增量 2 / 增量**总数** 39 /
    末尾判定行 1 / **写 `fail` 的行数 40**）；
    **原地替换**（批 BM，不增行）：批 BR 那条「锚定形态适用范围常量」的门项
    正则与说明文字同步（范围 +2 个脚本）；
    ⚠ **豁免表 11 → 13**（+2：两个脚本既有的「清单调用数」门数的是**调用点**、
    后面是自由文本 ⇒ 天生不能整行锚定 ⇒ 显式豁免并逐条写理由）。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ 「写 `fail` 的行数」是**行数**口径（一行里写两次 `fail=` 只算 1 行）
      ⇒ 但三条门口径一致；
    - ⚠ 计数点**总数**是**不许增不许减**的基线 ⇒ 将来合法新增失败路径
      必须同步更新期望值（批 BB 口径）；
    - ⚠ 本批**没覆盖**「新增一条**不带计数**的失败路径」
      ⇒ 抓得到它的是**报错行数 vs 计数行数**的**配对**关系
      ⇒ 需要一个跨行配对门型 ⇒ **下一批**；
    - ⚠ `contract-check.sh` 自己的两个 **SKIP 分支**（引擎缺席 / 缺 python3）
      是 `exit 0` 形态 ⇒ 属批 BW 的「SKIP 不许被当成通过」家族 ⇒ 本批**没收**。
  - **数字**：门项物理行数 **850 → 862**（+12）、执行次数 **853 → 865**、
    门项总数基线 = **862**；豁免表 **11 → 13**；接线门 **865** 项全绿、
    ci.sh **15/15**、selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、
    快照**零变化**、审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 17/17 真红**（17 条断言全绿；核心证据 =
    **行为级**：摘掉 `no()` 的计数 ⇒ 假包检查 **rc=0 而 stderr 仍打「✗」**、
    摘掉 `check()` 助手的计数 ⇒ **rc=0 而仍打「✗ 注入失败」**、
    判定前复位 ⇒ **rc=0 而摘要写着「5 failed」** ⇒ 三处**假绿坐实**；
    另 12 条门项逐条变异 + **从 `ci-wiring.sh` 原文现抽那一条单独跑** ⇒ **12 条全红**）。
- ⚠⚠⚨ **「新增失败路径必须带计数」：报错行数 == 计数行数**（批 BZ 实测）：
  - ⚠⚠⚨ **起因**：批 BY 给计数器型脚本的「失败计数点 / 末尾判定行」都落了
    整行锚定的门，**但明确记下了一类它抓不到的洞**（如实记为已知边界）。
  - ⚠⚠⚨ **洞**：批 BY 的门保证「**已有的**计数点不被摘、不被复位」
    ⇒ 但**新增**一条失败路径时，若新代码只写了 `echo "  ✗ …" >&2`
      却**忘了** `fail=$((fail+1))`
    ⇒ 末尾判定 `[ "$fail" -eq 0 ]` **看不到**这条失败
    ⇒ 脚本 `exit 0` ⇒ **CI 假绿**。
  - ⚠⚠⚨ **为什么两条独立的「恰好 N 次」门抓不到它**：
    「报错行数 == 39」与「计数行数 == 39」**互不知情**
    ⇒ 新增一条不带计数的报错行 ⇒ 报错门红（40 ≠ 39）、计数门绿（39 == 39）
    ⇒ 人把**报错门**的期望值改成 40 ⇒ 两门都绿
    ⇒ 但那条新报错**永远不计数** ⇒ **假绿**
    ⇒ 必须有**一条**门**同时**盯住两个数 ⇒ 它们的**差恒为 0**。
  - ⚠⚠⚨ **行为级实测（假绿坐实）**：用 `dpkg-deb -b` 造一个
    **全部 9 项检查都通过**的假包 ⇒ 真跑 ⇒ **rc=0、0 条失败**
    ⇒ 注入一条只报错不计数的失败路径 ⇒ **rc=0、0 条失败**
    而 stderr **照样打着一行「✗」** ⇒ **假绿坐实**。
  - **修法**：新增**门型** `arch_need_count_pair`
    （**报错行数 == 计数行数 == 期望**）
    ⇒ ⚠⚠⚨ **新门型必须进审计覆盖**（批 AR/AV 纪律）⇒ 三处都做：
    ① **门项行正则** `PAIR_COUNT_LINE`（属 count 族 ⇒ 被 `COUNT_FAMILY_LINE`
      兜底 ⇒ 写坏了报「盲区」而不是静默失效）；
    ② **门型清单登记**（`GATE_TYPES`）⇒ 「门型对拍」算上它；
    ③ **期望校准**（`check_pair_count_gates`）⇒ 期望值必须 == 实际两个数。
  - ⚠ **口径**：数的是**行数**（`grep -cE`）⇒ 一行写两次只算 1 行；
    报错行用 `echo "  ✗`（**两格缩进**）⇒ `exit N` 形态的报错行
    （`echo "✗ …"`，**无缩进**）**自然被排除** ⇒ 只盯**计数器型**的失败路径。
  - **落门 / 判据**：新增 **2** 条（`check-deb-layout.sh` 报错 1 == 计数 1 +
    `contract-check.sh` 报错 39 == 计数 39）；
    **原地替换**（批 BM，不增行；批 BB：说明与期望值**一起改**）：
    ① 「`arch_` **门型函数注册表**」**14 → 15**；
    ② 「**全文失败上报总数**」**35 → 37**。
  - ⚠⚠⚨ **负控 6/6 真红**：
    A0 未变异对照 / A1 ⚠ **行为级（旗舰）**：注入一条只报错不计数的失败路径
    ⇒ **rc=0 而 stderr 仍打「✗」**（假绿坐实）/ P1 P2 两条配对门 ⇒ **都红** /
    P1 P2 **增量价值**：**同一个变异**下批 BY 的 4 条门**仍全绿**
    ⇒ 证明**只有配对门**能抓这一类洞。累计 **529/529**。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ 配对门保证「**总数相等**」，**不是**「**逐条相邻**」
      ⇒ 一条报错行与一条计数行**错位配对**它照样绿
      ⇒ 要真正的相邻保证，得让脚本侧把「报错 + 计数」**收进同一行**
      （结构保证）或引入跨行门型 ⇒ **下一批可议**；
    - ⚠ 期望值是**不许增不许减**的基线 ⇒ 将来合法新增失败路径必须同步更新；
    - ⚠ 配对门数的是**行数** ⇒ 一行里 1 条报错 + 2 次计数仍算 1 == 1
      ⇒「一次失败被数两次」这类错配抓不到（由批 BY 的增量行数门间接兜着）。
  - **数字**：门项物理行数 **862 → 864**（+2）、执行次数 **865 → 867**、
    门项总数基线 = **864**；豁免表**不变**（13 条 —— 新门型的两个行模式正则
    **天然不能**整行锚定 ⇒ **按设计不审锚定形态**）；接线门 **867** 项全绿、
    ci.sh **15/15**、selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、
    快照**零变化**、审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 6/6 真红**。
- ⚠⚠⚨ **「失败上报出口」不许被摘掉：判据层与 CI 自己的出口都要有门**（批 CA 实测）：
  - ⚠⚠⚨ **起因（实测盘点，不是印象）**：批 BT 收了 **5** 个探针脚本、
    批 BU 收了 **3** 个 helper 型脚本、批 BY/BZ 收了 **2** 个计数器型脚本
    ⇒ 但「**失败上报出口**」这个承诺本身（脚本失败时**必须真的报出去**，
      不许被摘掉、不许 fall through 到 0）
    **从来没在「判据层与 CI 自己身上」收过**。
  - ⚠⚠⚨ **洞 ①（行为级·假绿·旗舰）**：`ci-wiring-audit.py` 是**判据层的裁判**
    ⇒ 它的每个失败出口都是「某一类判据失配 ⇒ 必须红」的**唯一通路**
    ⇒ **实测**：把 `return 4`（「次数门没配准 ⇒ rc=4」）**整行摘掉**，
      再让某条次数门失准 ⇒ 审计器**不再报 4**
      ⇒ fall through 到 `return 3 if outside else 0` ⇒ `outside` 为空
      ⇒ **rc=0** ⇒ **审计器对失准的门项报「全绿」** ⇒ **假绿坐实**。
  - ⚠⚠⚨ **洞 ②（行为级·假绿·实测）**：`ci-d2.sh` 的最终判定
    `if [ "$FAIL" != "0" ]; then exit 1; fi`
    ⇒ 摘掉那个 `exit 1` ⇒ 脚本**明明已经检出失败**
      （打印了「✗ 豁免路径不存在」）却照样打印
      「**✓ D2 命中 0/0（存量已清零，DS 单一真相源）**」并 **exit 0**
      ⇒ **假绿坐实**（一个**失败的门自己说「✓」**）。
  - ⚠⚠⚨ **洞 ③（形态级）**：`ci.sh` 的失败**已被 `if` 分支消化**
    （`set -e` 救不了：失败命令的退出码被 `if` 的条件消费掉了）
    ⇒ 只剩那些**显式 `exit 1`** 兜底 ⇒ 摘掉一个
    ⇒ 那一步的失败**不再中止 CI** ⇒ CI 继续往下跑 ⇒ 假绿。
  - **修法**（本批只动判据层 ⇒ **零产品代码改动**）：
    - 每个脚本的**失败出口条数**逐个钉住（**整行锚定**）；
    - 审计器额外钉「**成功出口**条数」⇒ 与「失败出口条数」**合看**：
      任何一个失败出口被改成 `return 0` ⇒ 失败出口掉 1、成功出口涨 1
      ⇒ **两条都红**；
    - 三个 `.py` 的**入口行**（`sys.exit(main())`）单独钉住
      ⇒ 入口被摘 ⇒ `main()` 的返回值被丢弃 ⇒ **rc 恒 0** ⇒ 工具永远绿；
    - `ci-d2.sh` / `smoke.sh` / `bootstrap-deps.py` **纳入**审计器的
      「整行锚定」适用范围（这 3 个文件**没有**非锚定门项 ⇒ **豁免表不变**）。
  - **落门 / 判据**：新增 **13** 条（**全部整行锚定**）——
    `ci-wiring-audit.py` **4** 条（失败出口 16 / 条件出口 1 / 成功出口 2 / 入口 1）+
    `ci.sh` **1** 条（整行 `exit N` 27）+ `ci-d2.sh` **1** 条（2）+
    `smoke.sh` **3** 条（**行内**形态 2 + 整行 1）+
    `ci-tautology-check.py` **2** 条 + `bootstrap-deps.py` **2** 条；
    **原地替换**（批 BM，不增行）：批 BR 那条「锚定形态适用范围常量」的门项
    正则与说明文字同步（范围 +3 个脚本；⚠ 范围常量**必须单行** —— 批 BR）。
  - ⚠⚠⚨ **负控 19/19 真红**：
    A1.0/A1.1 ⚠ **行为级（旗舰）**：次数门失准 ⇒ 必须报 **rc=4**；
    摘掉 `return 4` ⇒ **rc=0**（假绿坐实）/
    A2.0/A2.1 ⚠ **行为级**：摘掉 `ci-d2.sh` 最终判定的 `exit 1`
    ⇒ **rc=0 且照样打印「✓ D2 命中 0/0」**（假绿坐实）/
    A3.0/A3.1：摘掉 `ci.sh` 第 1 步的 `exit 1` ⇒ **第 2 步照样开跑**/
    ① ~ ⑬：13 条门项**各变异一次** ⇒ **13 条全红**。累计 **548/548**。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ 「失败出口」= **整行**的 `exit <非0数字>` / `return <非0数字>`
      ⇒ **行内**形态**数不到** ⇒ `smoke.sh` 的两处行内失败上报**单钉**；
    - ⚠ 「失败出口被改成**另一个非 0 码**」⇒ 出口数不变 ⇒ 这几条门**抓不到**
      ⇒ 抓得到的是**诊断不失真**（需另钉具体码值）或**下一批**；
    - ⚠ `bootstrap-deps.py` **不在 CI 里**（手动引导用）；
    - ⚠ 收的是**出口条数** ⇒ 「多了一个失败出口」会红 ⇒ **不许增**的基线。
  - **数字**：门项物理行数 **864 → 877**（+13）、执行次数 **867 → 880**、
    门项总数基线 = **877**；豁免表**不变**（13 条）；接线门 **880** 项全绿、
    ci.sh **15/15**、selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、
    快照**零变化**、审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 19/19 真红**。
- ⚠⚠⚨ **「未验证」不许被当成「通过」：契约门的 SKIP 必须用专属退出码 3**（批 CB 实测）：
  - ⚠⚠⚨ **起因（实测盘点，不是印象）**：批 CA 把「失败上报出口」逐个钉住了
    ⇒ 顺带盘出**唯一**一处「用 `exit 0` 表示**未验证**」的地方 ——
    `contract-check.sh` 的两个 SKIP 分支（引擎缺席 / 缺 python3）。
  - ⚠⚠⚨ **而批 BW 早就在探针侧立了这条口径**
    （`0=通过 / 1=失败 / **3=SKIP**`），**它的注释里还早就写着**
    「与第 10 步契约门**同款口径**」⇒ 但契约门脚本一直用的是 `exit 0`
    ⇒ **注释与实际行为不一致**（批 BB 纪律）⇒ 本批把脚本侧对齐。
  - ⚠⚠⚨ **洞（行为级·假绿）**：`ci.sh` 第 10 步原为
    `if cmd; then …「✓ 引擎契约门通过」… else … exit 1; fi`
    ⇒ 脚本 `exit 0`（**未验证**）也走「**通过**」那一支
    ⇒ ⚠⚠⚨ **实测**：缺 python3 时**120 条契约断言一条都没跑**，
      CI 却打印「**✓ 引擎契约门通过**」⇒ **假绿**。
  - ⚠⚠⚨ **根因链有两环**：① 脚本用 `exit 0` 表示未验证；
    ② CI 不分诊退出码 ⇒ **两环都要修**，只修一环仍然是假绿。
  - **修法**（照批 BW 的口径）：
    - **脚本侧**：两个 SKIP 分支 `exit 0` → **专属未验证码 3**
      （引擎缺席支**独立成行** `exit 3`；缺 python3 支为**行内**
      `|| { …; exit 3; }`）；
    - **CI 侧**：第 10 步**接住退出码**并分诊
      （**0 = 通过 / 3 = 未验证(SKIP) / 其它非 0 = 失败**）
      ⇒ SKIP 支**如实打印「本组未验证，不算通过」**
      （与第 13 步 agent 工具面门**同款口径**）；失败支**报出退出码**；
    - ⚠ 刻意**不用** `if ! cmd; then $?`（`!` 会把退出码**取反**
      ⇒ 分不清 SKIP 与失败）。
  - **落门 / 判据**：新增 **7** 条（**全部整行锚定**）——
    `contract-check.sh` **2** 条 + `ci.sh` **5** 条
    （`_cc_rc=0` 初始化 / 分诊 `-eq 0` / 分诊 `-eq 3` /
    SKIP 支必须打印「**未验证**」/ 失败支必须报出**退出码**）；
    **原地替换**（批 BM，不增行）：第 10 步那条既有门项的**形态**从
    `if cmd; then` 改成「**接住退出码 + 分诊**」
    ⇒ 「必须接住退出码」这条承诺**就落在它身上**（**不另加一条** ——
    否则同（门型, 文件, 正则, 次数）会出现**两条一模一样的门** ⇒ 纯冗余）。
  - ⚠⚠⚨ **负控 12/12 真红**：
    A1 ⚠ **行为级**：缺 python3 ⇒ 旧形态 exit 0 / 新形态 **exit 3** /
    A2.0/A2.1/A2.2 ⚠ **行为级**：从 `ci.sh` **原文现抽**第 10 步块
    （零漂移）⇒ 旧块 + exit 0 ⇒ **谎称「✓ 引擎契约门通过」**；
    新块 + exit 3 ⇒ **诚实 SKIP 且不谎称通过**；
    新块 + exit 1 ⇒ 判失败且 rc≠0 /
    ① ~ ⑦：7 条门项**各变异一次** ⇒ **7 条全红**。累计 **560/560**。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ 引擎缺席那一支在 CI 里**走不到**（外层守卫先判）
      ⇒ 收它是为了「脚本**单独**跑时也诚实」+ 与第 13 步口径一致；
    - ⚠ CI 里**实际可达**的是「缺 python3」那一支 ⇒ **两条门都收**；
    - ⚠ SKIP 之后 CI **仍然绿**（沿用本仓既有立场：环境不具备 ⇒ SKIP、
      不算通过、但**不判失败**）⇒ 与第 13 步**同款口径**；
      若将来认为「核心门未验证 ⇒ 必须判红」，那是**另一条决策**，本批未做。
  - **数字**：门项物理行数 **877 → 884**（+7）、执行次数 **880 → 887**、
    门项总数基线 = **884**；豁免表**不变**（13 条）；接线门 **887** 项全绿、
    ci.sh **15/15**、selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、
    快照**零变化**、审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 12/12 真红**。
- ⚠⚠⚨ **「失败出口的码值」是判据的一部分：不许被悄悄改**（批 CC 实测）：
  - ⚠⚠⚨ **起因（实测盘点，不是印象）**：批 CA 把「失败上报出口」逐个钉住了
    ⇒ 但它钉的是**总数**（`ci-wiring-audit.py` 的 `return [1-9]` == 16）
    ⇒ 而**退出码是判据的一部分**（每个码值承载一类语义）。
  - ⚠⚠⚨ **实测盘出的码值分布**（从 `ci-wiring.sh` 原文现抽 `strip_comments`）：
    - `ci-wiring-audit.py`：**9 个不同的失败码**
      （`return` 2×5 / 4×1 / 5×2 / 6×1 / 7×1 / 8×2 / 9×4，**各对应一类失配**）；
    - `check-deb-layout.sh`：`exit` 1×1 / 2×1 / 3×1
      （**1=失败 / 2=用法错 / 3=未验证**）；
    - `probe-agent-tool-surface.sh`：`exit 3`×2（**SKIP**）；
    - 3 个探针 + 恒真探针：`exit 2`（**用法错**）。
  - ⚠⚠⚨ **而批 CA 段自己的注释里就写着这条已知边界**
    （「失败出口被改成**另一个非 0 码** ⇒ 出口数不变 ⇒ 这两条门**抓不到**
    ⇒ 抓得到的是**诊断不失真**或**下一批**」）⇒ **本批就是那个「下一批」**。
  - ⚠⚠⚨ **洞 ①（行为级·假绿·旗舰）**：`check-deb-layout.sh` 的 SKIP 分支
    （没有 `dpkg-deb` ⇒ 本门**未验证**）用 `exit 3`
    ⇒ ⚠⚠⚨ **实测**：改成 `exit 0` ⇒ 脚本 **rc=0** 而输出**仍写着**
      「SKIP: 没有 dpkg-deb（本门**未验证**，不算通过）」
      ⇒ CI 第 12 步打印「**✓ deb 布局验收通过**」⇒ **假绿坐实**
      ⇒ ⚠⚠⚨ 而**现有门全绿**（实测接线门 rc=0）
      ⇒ `exit 3` **一条门都没有** ⇒ 没人看得见。
  - ⚠⚠⚨ **洞 ②（行为级·误判）**：`ci.sh` 第 12 步**不分诊**退出码
    ⇒ ① 脚本 `exit 3`（**正确的未验证**）⇒ CI 判「✗ 失败」并 exit 1
      ⇒ **未验证被当成失败**；
    ⇒ ② 脚本 `exit 0`（**未验证**）⇒ CI 打印「✓ 通过」⇒ **假绿**
    ⇒ 与批 CB 修的第 10 步（契约门）**同款洞**。
  - ⚠⚠⚨ **洞 ③（行为级·诊断被带偏）**：审计器的失败码**每个都有语义**
    （2=盲区 / 3=豁免之外有隐患 / **4=次数门没配准** / 5=正则坏 / 6=总数失配
    / 7=重名 / 8=锚定形态 / 9=未定义名）
    ⇒ ⚠⚠⚨ **实测**：把 `return 4` 改成 `return 3`
      ⇒ 次数门失准时审计器报 **rc=3**
      ⇒ **撞上「豁免之外有隐患」的码**
      ⇒ **按 rc 分派的自动化处理会走错分支**（诊断文本还在，
        但自动化读的是**退出码**）。
  - **修法**（只动判据层与 CI 脚本 ⇒ **零产品代码改动**）：
    - **按码值分桶**逐个钉住（不再是「非 0 的总数」）
      ⇒ 改一个码值 ⇒ **旧桶 −1 + 新桶 +1** ⇒ **两条都红**；
    - `ci.sh` 第 12 步**接住退出码**并分诊
      （0=通过 / **3=未验证(SKIP)** / 其它非 0=失败）
      ⇒ SKIP 支**如实打印「未验证、不算通过」**
      （与第 10 步、第 13 步**同款口径**）；
    - 批 CA 的 `return [1-9]` **宽门原地替换**成第一条分桶门
      ⇒ 7 条分桶门**完全蕴含**那条宽门 ⇒ 删宽门不降低保护。
  - **落门 / 判据**：新增 **21** 条（**全部整行锚定**）——
    `check-deb-layout.sh` **3** 条 + `ci-wiring-audit.py` **6** 条 +
    `ci.sh` 第 12 步 **6** 条 + 3 个探针 `exit 2` **3** 条 +
    `probe-agent-tool-surface.sh` **2** 条 + `ci-tautology-check.py` **1** 条；
    **原地替换**（批 BM，不增行）：批 CA 的审计器宽门 → 第一条码值桶门；
    第 12 步那条既有门项的**形态**从 `elif sh …; then`
    改成「**接住退出码 + 分诊**」⇒ 说明文字同步。
  - ⚠⚠⚨ **负控 23/23 真红**：
    **A（行为级 11 条）**：A1.1 变异 `exit 3 → exit 0`
    ⇒ **rc=0 且仍打「SKIP」⇒ 假绿坐实**；A1.2 同一变异下**现有门全绿**；
    A2.1 脚本 exit 3 ⇒ CI 判 **SKIP「未验证」且 rc=0**；
    A2.3 脚本 exit 1 ⇒ 判失败 rc≠0；
    A3.1 次数门失准 ⇒ 必须报 **rc=4**；A3.2 变异 `return 4 → return 3`
    ⇒ 报 **rc=3**（**撞码**）/
    **B（门项级 12 条）**：① ~ ⑫ 各变异一次 ⇒ **12 条全红**
    （每条**从 `ci-wiring.sh` 原文现抽单独跑** ⇒ 零漂移）。累计 **583/583**。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ 只收**整行**的 `exit N` / `return N` ⇒ **行内**形态数不到
      ⇒ `smoke.sh` 的两处行内失败上报由批 CA 单钉、
      `contract-check.sh` 的行内 `exit 3` 由批 CB 单钉；
    - ⚠ 单一码的文件（`ci.sh` 的 27 个 `exit 1` 等）**不分桶**
      ⇒ 改那些码值**无语义损失** ⇒ 不值得为它加门（避免噪音门）；
    - ⚠ 审计器 rc=3 的**正常可达性存疑**（实测「次数门失准」先走 rc=4）
      ⇒ 但「两个语义撞在同一码」的**风险依然成立**
      ⇒ 本批的价值是**不让任何码值被悄悄改**；
    - ⚠ 分桶门与总数门**并存**（总数门管「不许少」，
      分桶门管「不许改码值」）⇒ 只有审计器那一条**宽门被删**；
    - ⚠ 探针的 `exit 2` 在 CI 里**不会触发** ⇒ 收它是为了
      「**单独**跑探针时诊断不失真」。
  - **数字**：门项物理行数 **884 → 905**（+21）、执行次数 **887 → 908**、
    门项总数基线 = **905**；豁免表**不变**（13 条）；接线门 **908** 项全绿、
    ci.sh **15/15**、selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、
    快照**零变化**、审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    **负控 23/23 真红**。
- ⚠⚠⚨ **「工具读不了」不许被当成「没问题」：扫描前先验可读性**（批 CD 实测）：
  - ⚠⚠⚨ **起因（实测盘点，不是印象）**：批 AZ 早就记下过「真正吞退出码的是
    **命令替换内部的 `|| true`**」⇒ 但**从未收过**这些站点。
    本批**逐个盘点**了 `scripts/` 下的**外部工具调用站点**（**419 处**）⇒ 三类：
    - ⚠ **危险方向**（`if 外部工具; then <不通过>; else <通过>; fi`）⇒ **0 处**；
    - **命令替换内 `|| true`** ⇒ 多处，但多数**输入是字符串**
      （grep 读的是管道 ⇒ 崩不了）⇒ 无害；
    - ⚠⚠⚨ **输入是文件**的 `|| continue` / `|| true` ⇒ **2 处** ⇒ **真洞**。
  - ⚠⚠⚨ **洞 ①（行为级·假绿·旗舰）**：`ci-d2.sh` 的**双重吞**
    （外层 `grep -rl … 2>/dev/null` + 内层 `grep -n … || true`）
    ⇒ ⚠⚠⚨ **实测**：造一个**含散值**的源文件
      （`src/zzAzCdProbe.cpp`，内容 `#FF00AA`）让它对 grep **不可读**
      （`chmod 000` ⇒ grep rc=2）
      ⇒ 外层 `grep -rl` **静默跳过**它 ⇒ 命中数变 0
      ⇒ 脚本打印「**✓ D2 命中 0/0（存量已清零，DS 单一真相源）**」并 **exit 0**
      ⇒ ⚠⚠⚨ **门自己说「✓」⇒ 假绿坐实**
      ⇒ 而**接线门全绿**（实测 rc=0）⇒ 没人看得见。
  - ⚠⚠⚨ **洞 ②（行为级·假绿）**：`ci-orphan-probe.sh` 的
    「什么算断言脚本」判定 `grep -q '✗ ' "$_f" 2>/dev/null || continue`
    ⇒ grep **崩了**（rc=2）与「没找到」（rc=1）**混为一谈**
      ⇒ 游离断言脚本**被静默跳过**
      ⇒ 脚本打印「**✓ 无游离断言脚本：scripts/ 下 16 个断言脚本全部在 CI 里可达**」
        并 exit 0 ⇒ **漏检坐实**。
    ⇒ 两洞的**共同形态**：「**工具读不了**」被当成「**没问题**」
      ⇒ 与批 CB/CC 同款口径：**未验证不许被当成通过**。
  - **修法**（只动判据层 ⇒ **零产品代码改动**）：
    在**扫描之前**先验**可读性** ⇒ 读不了 ⇒ 判失败 ——
    - `ci-d2.sh`：`find "$SRC/src" -type f ! -readable -print`（退出码一并接住）
      ⇒ 不可读 ⇒ `FAIL=1` ⇒ 末尾的 `exit 1` 在「✓ 命中 0/0」**之前**
      ⇒ **那个「✓」永远打不出来**；
    - `ci-orphan-probe.sh`：对 `scripts/*.sh` + `*.py` 逐个 `[ -r ]`
      ⇒ 不可读 ⇒ `fail=1` ⇒ 末尾统一 `exit 1`。
    - ⚠ **为什么选「扫描前验可读性」而不是「逐个接 grep 的 rc」**：
      ① **一次挡住整类**（同一批文件的所有 grep 调用都受益）；
      ② 被扫集合与被验集合**完全一致**（不漏一个文件）；
      ③ 失败信息**指名道姓**是哪个文件读不了（排障不用猜）。
  - **落门 / 判据**：新增 **4** 条（**全部整行锚定**）——
    `ci-d2.sh` **2** 条（可读性检查那一行 —— **同时**保证
    `|| _d2_find_rc=$?` 在 ⇒ 整行锚定 ⇒ 摘掉退出码接住也红 /
    不可读时**必须判失败**）+ `ci-orphan-probe.sh` **2** 条；
    **原地替换**：孤儿探针的「断言清单（报错行数）」**6 → 7**（说明同步）；
    ⚠ **删掉 1 条纯冗余**：D2 那行同时含「检查」与「接住退出码」，
    一度落成**两条一模一样的门** ⇒ 同（门型, 文件, 正则, 次数）⇒ **去重**
    ⇒ 两条承诺合并进一条的说明文字。
  - ⚠⚠⚨ **负控 13/13 真红**：
    **A（改前取证 6 条，已在改前的代码上实测通过）**：
    A1.1 变异「文件不可读」⇒ **rc=0 且打印「✓ D2 命中 0/0」⇒ 假绿坐实**；
    A1.2 同一变异下**现有门全绿**；
    A2.1 变异「文件不可读」⇒ **rc=0 且打印「✓ 无游离断言脚本」⇒ 漏检坐实**；
    A3.1 同一变异下**接线门仍全绿**/
    **B（改后 7 条，全红）**：B1.1 文件不可读 ⇒ ci-d2.sh **必须判红**且
    **不许**打印「0/0」；B2.1 ⇒ ci-orphan-probe.sh **必须判红**；
    ① ~ ⑤ 4 条门项**各变异一次** ⇒ **4 条全红**（每条**从 `ci-wiring.sh`
    原文现抽单独跑** ⇒ 零漂移）。累计 **596/596**。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ 「扫描前验可读性」只挡住「**文件不可读**」这一种原因
      ⇒ grep 的**其它**失败仍可能被静默跳过
      ⇒ 本批**只收了实测坐实的这一类**（不推演）；
    - ⚠ `ci-orphan-probe.sh` 的 `calls_of()` 里也有 `2>/dev/null`
      ⇒ 但失败方向是「REACH 变小 ⇒ **误报**（不是假绿）」⇒ 安全方向 ⇒ 不改；
    - ⚠ 本批只改了 **2 个脚本** ⇒ 其余同类站点**待再盘**；
    - ⚠ 负控 A 是**改前**的一次性取证 ⇒ 在**改后**代码上**必然失败**
      ⇒ 那正是「修好了」的证据 ⇒ **不可复现**（留档，不做门）。
  - **数字**：门项物理行数 **905 → 909**（+4：新增 4 条、删 1 条纯冗余）、
    执行次数 **908 → 912**、门项总数基线 = **909**；豁免表**不变**（13 条）；
    接线门 **912** 项全绿、ci.sh **15/15**、selfcheck **395/0**、
    契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式
    **rc=0**、恒真探针与孤儿探针 **rc=0**；**负控 13/13 真红**。
- ⚠⚠⚨ **「外部工具的失败」不许被当成「检查通过」：接住退出码 + 拆开管道**（批 CE 实测）：
  - ⚠⚠⚨ **起因（实测盘点 + 方法论修正）**：批 CD 盘过 `scripts/` 下的
    **外部工具调用站点**（**419 处**）⇒ 结论写着「**危险方向 0 处**」
    ⇒ ⚠⚠⚨ **但那个口径有盲区**（本批实测坐实）：它只找**字面形态**
    `if 外部工具; then <不通过>; else <通过>; fi` ⇒ **漏了两种形态**——
    ① **工具输出 → 变量 → 判定**
      （`N="$(工具 | grep -c … || true)"` ⇒ `[ "$N" = "0" ] || die`）；
    ② **无 else 分支**的 `if 工具; then <失败支>; fi`
      ⇒ 工具失败 ⇒ 条件为假 ⇒ **什么都不做 ⇒ 隐式通过**。
    ⇒ 本批用**更宽的口径**重盘 ⇒ 盘出 **3 处真洞**
      （另 4 处输入是字符串 ⇒ grep 读管道 ⇒ 崩不了 ⇒ 无害；
      条件带 `!` 的那批失败方向是「误报」⇒ 安全方向不动）。
  - ⚠⚠⚨ **洞 ①（行为级·假绿·旗舰·D7 核心验收）**：
    `build-deb.sh` 的 ldd 缺库检查——
    `_nf="$(env -u LD_LIBRARY_PATH ldd … 2>&1 | grep -c 'not found' || true)"`
    ⇒ ldd **失败**（二进制不存在 / 不可读 / 工具崩了 ⇒ 报 "cannot open"）
    ⇒ 计数 **0** ⇒ 「无缺失库」⇒ **判通过** ⇒ **假绿**
    ⇒ ⚠⚠⚨ **实测**（stub 一个失败的 ldd，从脚本原文现抽那 3 行跑）：
    旧形态 **rc=0 走到末尾**
    ⇒ ⚠⚠⚨ 假绿的代价：**发出一个装不起来的 deb**
      （`build-deb.sh` 在 **CI 第 11 步**里跑 ⇒ CI 照样报「✓」）。
  - ⚠⚠⚨ **洞 ②（行为级·假绿）**：`build-deb.sh` 的 readelf RPATH 检查
    （`if readelf -d … | grep -qiE "rpath|runpath"; then die …; fi`）
    ⇒ **无 else 分支** ⇒ readelf 失败 ⇒ 不进 then
    ⇒ **静默判「没带 RPATH」⇒ 通过**
    ⇒ ⚠⚠⚨ **实测**（stub 一个失败的 readelf）：旧形态 **rc=0 走到末尾**。
  - ⚠⚠⚨ **洞 ③（行为级·假绿·判据层自身）**：`ci-wiring.sh` 的图标收口检查
    （`if strip_comments "$f" | grep -qE 'QIcon::fromTheme'; then …; fi`
    ⇒ then 分支是失败支、**无 else**）
    ⇒ 某个 `src/ui/*.cpp` 对工具**不可读** ⇒ grep 无输出
    ⇒ **裸 `QIcon::fromTheme` 漏检** ⇒ 门照样绿
    ⇒ ⚠⚠⚨ **判据层自身的假绿**（不是门坏了，是**门没看见**）。
  - **修法**（只动判据层与构建脚本 ⇒ **零产品代码改动**）：
    ① **接住工具的退出码** ⇒ 非 0 ⇒ **判失败**（工具失败 = 没验过
      ⇒ 与批 CB/CC/CD **同款口径**：**未验证不许被当成通过**）；
    ② **拆开管道**（工具输出先落进变量再加工）
      ⇒ 否则**管道里拿不到**工具自己的退出码（管道退出码是最后一条的）；
    ③ `dpkg-deb -x` 的失败**改成响亮 die**（以前靠 `set -e` 静默中止
      ⇒ 没有 die 消息 ⇒ 看着像「跑到一半没了」⇒ **诊断失真**）；
    ④ 洞 ③ 用批 CD 同款：**扫描之前先验可读性**
      ⇒ 读不了 ⇒ 判失败，**不许当成「没有裸图标」**。
  - **落门 / 判据**：新增 **4** 条（**全部整行锚定**）——
    `build-deb.sh` **3** 条（ldd 失败**必须 die** / readelf 失败**必须 die** /
    解包失败**必须响亮 die**）+ `ci-wiring.sh` **1** 条
    （图标收口检查**必须先验可读性**）；
    **原地替换**（批 BM 纪律）：批 CD 之前那条盯
    `readelf … | grep -qiE "rpath\|runpath"` 的 `arch_need`
    ⇒ 形态已变 ⇒ 正则改盯「接住 readelf 退出码」那一行
    + **说明文字同步改写**（批 BB）+ 删掉「同一行出现两次」的旧尾巴；
    **同步**：helper 型脚本的「断言清单（die/fail 调用点）」**20 → 23**
    （+3 是**诊断增强**的 die ⇒ 不是新断言，但计数要如实改）。
  - ⚠⚠⚨ **负控 8/8 真红**：
    **A（行为级·改前取证 2 条）**：A1.1 ldd 失败 ⇒ 旧形态 **rc=0 走到末尾**
    （假绿坐实）；A2.1 readelf 失败 ⇒ 旧形态 **rc=0 走到末尾**
    ⇒ ⚠⚠⚨ 这两条断言的是「**必须判失败**」
    ⇒ **同一份脚本改前红、改后绿** ⇒ 比批 CD 的负控 A **更可复现**；
    **B（门项级 4 条）**：① ldd 失败不 die ⇒ 红；② readelf 失败不 die ⇒ 红；
    ③ 解包失败不 die ⇒ 红；
    ④ ⚠⚠⚨ **增量价值**：变异「ldd 失败不 die」下**旧门全绿**
    （盯串的）⇒ 而**只有批 CE 的门红**（旧门红=False，新门红=True）；
    **C（洞 ③ 2 条）**：C1.1 `src/ui/` 有不可读文件 ⇒ 接线门**必须红**
    且红的原因含「不可读」（⚠ 造的文件**不含**任何被别的门盯的串
    ⇒ 红的原因唯一）；C2.1 删掉那处可读性验证 ⇒ 门必须红。累计 **604/604**。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ **批 CD 的「危险方向 0 处」是错的**（口径有盲区）⇒ 本批已修正并记此
      ⇒ 但「**盘点方法本身也要被门守**」（否则下一次盘点还会漏）**本批未做**；
    - ⚠ 本批只收「**工具失败 ⇒ 判通过**」这一类
      ⇒ 「工具失败 ⇒ 误报」（条件带 `!` 的那批）**方向安全** ⇒ 不动；
    - ⚠「输入是字符串」的 4 处 ⇒ grep 读管道 ⇒ 崩不了 ⇒ 不动；
    - ⚠ `ci-wiring.sh` 里其余几十处 `strip_comments` 用法方向都是
      「工具失败 ⇒ 门红」⇒ 安全 ⇒ 只收危险方向那两处；
    - ⚠ ldd 对**静态二进制**返回 1 ⇒ 会被判失败 ⇒ 这是**故意的**
      （静态产物本就不该走依赖检查，且判失败比静默通过安全）；
    - ⚠ 负控 A/B/C 都用 **stub 工具**（PATH 前置）⇒ 不依赖本机环境，
      但验的是**抽出来的片段**而非整脚本
      ⇒ 整脚本的其余部分由 CI 第 11 步兜。
  - **数字**：门项物理行数 **909 → 913**（+4）、执行次数 **912 → 916**、
    门项总数基线 `ci-wiring-gates.baseline` = **909 → 913**；豁免表**不变**（13 条）；
    接线门 **916** 项全绿、ci.sh **15/15**、selfcheck **395/0**、
    契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式
    **rc=0**、恒真探针与孤儿探针 **rc=0**；**负控 8/8 真红**。
- ⚠⚠⚨ **「判据层自己的剥注释」不许有三份实现、三种口径**（批 CF 实测）：
  - ⚠⚠⚨ **起因（实测盘点 + 对照实验，不是推演）**：本批原计划盘
    「命令替换内的 `|| true`」与「无 pipefail 的管道」
    （实测：`scripts/` 下 **18/18** 个 shell 脚本**都没开** `pipefail`；
    命令替换内带 `|| true` 的站点 **26** 处）⇒ 盘点中发现一个**更硬的洞**：
    ⚠⚠⚨ 剥注释函数 `strip_comments` 在仓里有 **3 份 shell 实现
    + 1 份 python 实现 ⇒ 3 种不同口径**——
    - `ci-wiring.sh` = `s{(?<!:)(//)(?!:).*$}{}`
      + `.sh/.txt/.py` 走 sed 剥 `#` ⇒ **最全**；
    - `ci-d2.sh` = 同款 perl 正则但**缺 `.py` 分支**
      ⇒ 批 BK 的洞「注释里的串顶替真代码」在这里仍在；
    - `ci.sh` = `s{//(?!:).*$}{}` —— **旧口径**（**没有** `(?<!:)`）；
    - 审计器（python）= 同新口径。
    ⇒ ⚠⚠⚨ 批 AS 早就定过「**复刻 = 两套口径 ⇒ 一律改成调同一条命令**」，
      **审计器已经这么做了** ⇒ 但**两个 shell 脚本根本没遵守**：
      自己复刻了，**而且各自漂了**。
  - ⚠⚠⚨ **洞 ①（口径分裂 · 旗舰 · 实测坐实）**：
    - **对照实验**：① 同一份源码、同一个门项（`QStringLiteral("verify")`）
      ⇒ **`ci.sh` 口径命中 0**、**`ci-wiring.sh` 口径命中 1**
      ⇒ **相反结论**；
    - ② 仓里已有 **12** 个真实源文件在两套口径下**输出已经不同**
      （根因：sed 兜底把 `https://…` 整段剥掉，perl 口径不会
      ⇒ `(?<!:)` 正是为这个加的）。
    ⇒ **不是假想，现在就能咬人**：`ci.sh` 的 verify 接线门会**误报红**
      （假红，批 BS：假红逼人把承诺改弱）；换个构造就是**漏检**（假绿）。
    ⇒ ⚠⚠⚨ **没有任何门守它**。
  - ⚠⚠⚨ **洞 ②（静默降级 + 诊断失真）**：三份实现都有 perl→sed 的
    **静默兜底** ⇒ perl 缺席 ⇒ **口径变成第四种**。
    ⚠⚠⚨ **实测**（造一个不含 perl 的 PATH）：
    - **审计器**：`FileNotFoundError: 'perl'` ⇒ **未捕获异常崩掉**
      ⇒ 退出码 **1** ⇒ 门侧报「**未知的失败码**」
      ⇒ 真实原因**没有任何一条消息提到**；
    - **接线门**：红了，但红因是「**取数/判定/渲染/接线任一段被摘掉**」
      —— ⚠⚠⚨ **与真实原因毫无关系** ⇒ 排障被带偏；
    - ⚠⚠⚨ **`ci-d2.sh` 更是假绿**：剥注释失败 ⇒ 命中数 0
      ⇒ **照样打印「✓ D2 命中 0/0」并 exit 0**。
  - **修法**（只动判据层 ⇒ **零产品代码改动**）：
    - ① **口径单一真相源**：`ci.sh` / `ci-d2.sh` **不再自己定义**
      ⇒ 改为**从 `ci-wiring.sh` 原文抽取**（批 AV 纪律：抽取而非复刻）
      ⇒ 一次挡住整类（改一处就跟着变）；
    - ② **静默降级 ⇒ 响亮失败**：三个脚本**顶层前置检查 perl 在不在**
      ⇒ 缺 ⇒ **响亮失败**（工具失败 = 没验过；批 CB/CC/CD/CE 同款口径）；
      判据层的 `strip_comments` 默认分支**去掉 sed 兜底**；
    - ③ **审计器前置检查**：缺 perl ⇒ 指名道姓 + 退出码 **2**
      （2 = 审计器有盲区或缺文件 ⇒ C++ 侧的门项**根本没被审** ⇒ 正是盲区）
      ⇒ `ci-wiring.sh` 的 rc=2 分派消息**同步补一句**（批 BB）；
    - ④ ⭐ **抽取自检**：`sed -n '/^strip_comments() {/,/^}/p'` 会在
      **第一个独占 `}` 行**处结束 ⇒ 函数体里若有这样的行
      ⇒ **抽到残缺函数** ⇒ 行为错乱
      ⇒ 抽取失败/抽出来不可用 ⇒ **指名道姓地失败**（不许静默用半个函数）。
  - **落门 / 判据**：新增 **10** 条（**2 forbid + 8 条全整行锚定**）——
    `ci.sh` / `ci-d2.sh` **不许自己实现**剥注释（`perl -pe`）+
    两处「抽取+自检那一行必须在」+ 三处「perl 前置检查那一行必须在」+
    判据层「剥注释**必须直接走 perl**」（整行锚定 ⇒ 兜底一旦加回就红）+
    审计器「`def require_perl():`」（**带左括号** ⇒ 改名躲不过）
    与「**必须被调用**」；
    ⚠ **删掉 1 条纯冗余**（批 CB 纪律）：原计划的 forbid 门
    （盯旧兜底指纹）与「必须直接走 perl」的整行锚定门覆盖同一件事
    ⇒ **去重**；
    **同步**（批 BY/BS：期望值与说明都要如实改）：审计器 `return 2` **5→6**、
    审计器 `return 0` **2→3**、`ci.sh` 失败上报出口 **27→30**、
    `ci-d2.sh` **2→5**、门项总数基线 **913→923**；豁免表**不变**（13 条）。
  - ⚠⚠⚨ **负控 14/14 真红**：
    **A（行为级 · 3 条 · 可复现）**：A1.1 无 perl ⇒ 三个脚本**必须红**
    且**红因指名道姓含 perl**；A2.1 无 perl ⇒ 审计器**必须 rc=2**
    + 消息含 perl（改前是 rc=1 未捕获异常）；A3.1 `ci.sh` 抽出来的口径
    与 `ci-wiring.sh` **必须逐字节一致**（改前：12 个真实源文件不一致）
    ⇒ **实测差异文件数 = 0 / 共 279**
    ⇒ ⚠⚠⚨ 这三条断言的是「**必须判失败并指名道姓**」
    ⇒ **同一份脚本改前红、改后绿** ⇒ 比批 CD 的负控 A **更可复现**；
    **B（门项级 · 10 条 · 各变异一次 ⇒ 全红）**：① `ci.sh` 加回自己的
    perl 实现 ⇒ 红 / ② `ci-d2.sh` 加回 ⇒ 红 / ③ `ci.sh` 抽取+自检行
    改掉 ⇒ 红 / ④ `ci-d2.sh` 同 ⇒ 红 / ⑤ `ci-wiring.sh` 前置检查
    被摘掉 ⇒ 红 / ⑥ `ci.sh` 前置检查被摘掉 ⇒ 红 / ⑦ `ci-d2.sh` 前置检查
    被摘掉 ⇒ 红 / ⑧ 剥注释加回 sed 兜底 ⇒ 红 / ⑨ 审计器的前提检查
    被改名 ⇒ 红 / ⑩ 审计器的前提检查**没被调用** ⇒ 红
    ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）；
    **C（增量价值 · 1 条）**：变异「`ci.sh` 改回自己的旧口径实现」下
    **改前的所有门全绿**（口径分裂**没人守**）
    ⇒ 而**只有批 CF 的 forbid 门红**（旧门红=False，新门红=True）。累计 **618/618**。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ **「抽取」对独占 `}` 行敏感** —— ⚠⚠⚨ **本批自己踩到了**：
      第一版实现给 `strip_comments` 加了 `|| { … }` ⇒ 引入**独占的 `}` 行**
      ⇒ `ci.sh` / `ci-d2.sh` 抽到**残缺函数**
      ⇒ `ci.sh` 的 verify 接线门**误报红 2 条**
      ⇒ ⚠ **教训：复用实现的方式本身要有自检**
      ⇒ 已加「抽取自检」（行为级挡住后果），但**成因**只靠注释提醒
      ⇒ 「独立 lib 文件 + source」会更稳（**本批未做**）；
    - ⚠ **剥注释工具本身失败**（文件不可读 / perl 崩）⇒ 管道仍会掩盖退出码
      ⇒ 本批**只收了「perl 缺席」这一类** ⇒ 「文件不可读」类留给下一批；
    - ⚠ **本批原计划的盘点**（18/18 无 `pipefail`、26 处命令替换内
      `|| true`）**没有变成常驻判据**
      ⇒ 「**盘点方法本身也要被门守**」仍未做；
    - ⚠ **影响面实测为零**（6 条 `wire_need` 命中数新旧口径全同、
      D2 命中数全同、`.py` 无差异）⇒ 本批是**纯隐患收口**；
    - ⚠ `perl` 缺席时**整个 CI 会红**（而不是降级跑完）⇒ 这是**故意的**
      （口径无法确定 ⇒ 未验证不许被当成通过）。
  - **数字**：门项物理行数 **913 → 923**（+10）、执行次数 **916 → 926**、
    门项总数基线 `ci-wiring-gates.baseline` = **913 → 923**；豁免表**不变**（13 条）；
    接线门 **926** 项全绿、ci.sh **15/15**、selfcheck **395/0**、
    契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式
    **rc=0**、恒真探针与孤儿探针 **rc=0**；**负控 14/14 真红**。
- ⚠⚠⚨ **「剥注释失败」不许被当成「没找到」**（批 CG 实测）：
  - ⚠⚠⚨ **起因（实测盘点，不是推演）**：本批原计划盘
    「命令替换内的 `|| true`」与「无 pipefail 的管道」
    （实测：`scripts/` 下 **18/18** 个 shell 脚本**都没开** `pipefail`；
    命令替换内带 `|| true` 的站点 **26** 处）⇒ 盘点中先坐实一个
    **更硬的洞**，先收它：
    - `strip_comments` 的调用点共 **13** 处
      ⇒ 其中 **3** 处在 `probe_scan_find` 内（已被批 BI 的懒探测覆盖）
      ⇒ **11 处未覆盖**；
    - `arch_need_any_min` 的 N **必须配准**（余量恒为 0）
      ⇒ 那条路**不假绿** ⇒ 用**排除法**排除了「靠它兜住」的可能。
    ⇒ 剩下的口子只有一个：**剥注释工具**自己失败时，下游看不出来。
  - ⚠⚠⚨ **旗舰洞（实测坐实）**：批 CE 只在「**图标收口那一个**扫描点」
    加了「文件不可读 ⇒ 判失败」⇒ 其余调用点
    （forbid / need / count / any …）**都没有这层保护**。
    ⚠⚠⚨ **对照实验（同一个文件、同一份内容，只改权限）**：
    - 文件**可读** ⇒ `✗ raise 不再散落在界面代码里：… —— src/…/zzAzCgProbe.cpp`
      ⇒ 门**红**（违例被抓到）；
    - 文件**不可读**（`chmod 000`）⇒ 那一行**整个消失**
      ⇒ 该 forbid 门**静默变绿**。
    ⇒ ⚠⚠⚨ **彻底假绿**：探针放 `src/logic/`
      （**不在**批 CE 那一处的保护范围内）
      ⇒ **接线门 rc=0 全绿**、✗ 行数 0 ⇒ 违例**完全没被看见**。
  - ⚠⚠⚨ **根因实测（关键）**：
    - ⚠⚠⚨ **`perl` 打不开文件时，退出码仍是 0**
      （只往 stderr 打一句「Can't open …: 权限不够」）
      ⇒ **靠退出码抓不住「读不了」**
      ⇒ ⚠ **对照**：`sed` 读不了是 **2**、`grep` 读不了是 **2**
      ⇒ **只有 perl 是 0**；
    - 根因之二：管道里**拿不到** `strip_comments` 的退出码
      （管道退出码 = 最右命令的）⇒ 「输出为空」与「工具失败」
      在下游**长得一模一样** ⇒ forbid 门判「没找到」⇒ 绿。
  - **修法**（只动判据层 ⇒ **零产品代码改动**）：
    - ① `strip_comments` **先验可读性**（`[ ! -r "$1" ]`）
      ⇒ 读不了 ⇒ **写标记文件**
      （⚠ 跨子 shell ⇒ **变量传不出去** ⇒ 只能落文件）
      ⇒ 正常路径**零开销**；
    - ② 三个脚本（`ci-wiring.sh` / `ci.sh` / `ci-d2.sh`）
      **末尾统一检查标记** ⇒ 有 ⇒ **判红 + 指名道姓**列出失败的文件；
    - ③ 末尾检查放在「✓ 全绿」**之前** ⇒ 那个「✓」**永远打不出来**。
    ⇒ ⚠⚠⚨ 一次挡住**整类**（批 CD 纪律）：forbid / need / count / any …
      **全部**剥注释调用点都受益；
    - ⚠ 为什么**不用落盘重写**（批 BI 已实测否决）：管道 → 落盘慢 **20 倍**
      （30ms vs 1.5ms）⇒ 2511 次调用 ⇒ 84 秒 ⇒ CI 不可接受；
    - ⚠ 为什么**不用懒探测**（批 BI 已有）：它只验「工具活着」，
      **盖不住「这一次调用」失败**（文件不可读时工具是活的）。
  - **落门 / 判据**：新增 **8** 条（**全整行锚定**）——
    `ci-wiring.sh` 的「写标记」**恰好 1 处**（可读性先验支）
    +「写标记」**恰好 2 处**（sed 支 + perl 支）
    +「标记文件定义」+「末尾检查那一行」+ `ci.sh` 的「标记文件定义」
    +「末尾检查那一行」+ `ci-d2.sh` 的「标记文件定义」+「末尾检查那一行」；
    **原地替换 1 条**：批 CF 的「剥注释**必须直接走 perl**」
    （形态改成「`if ! perl …; then`」⇒ **失败要接住**）⇒ **不增行**；
    - ⚠ ⚠⚠ **同内容不同缩进是常态** ⇒ 整行锚定必须**按缩进拆成两条门**
      （⚠ **本批自踩**：一条正则罩不住多缩进
      ⇒ 审计器报「期望 3 ≠ 实际命中 1」）；
    - **同步**（批 BY/BS：期望值与说明都要如实改）：
      `ci.sh` 失败上报出口 **30→31**、`ci-d2.sh` **5→6**、
      门项总数基线 **923→931**；豁免表**不变**（13 条）。
  - ⚠⚠⚨ **负控 16/16 真红**：
    **A（行为级 · 6 条 · 可复现）**：A0.1 **基线**（干净工作区
    ⇒ 接线门 rc=0）/ A1.1 **改后**（源文件不可读 ⇒ 接线门**必须红**
    且**红因指名道姓**，实测点名了 `src/logic/zzAzCgProbe.h`）/
    A2.1 **对照实验（只改权限）**：可读 ⇒ forbid 门红在「违例被检出」；
    不可读 ⇒ forbid 门**绿**（违例看不见）⇒ **违例本身仍然漏检** /
    A3.1 ⚠⚠⚨ **改前对照**：三个脚本**回退到 HEAD**（批 CF 状态）
    ⇒ 同一场景 **rc=0 全绿** ⇒ **假绿坐实** ⇒ 证明这批改动正是堵它的 /
    A4.1 **单元级**：三个脚本**各自**的标记变量 + 抽出来的 `strip_comments`
    ⇒ 对不可读文件**必须真的写标记**（变量不在就写不进去
    ⇒ 失败被静默吞掉）/ A5.1 **回归**：`ci-d2.sh` 遇到不可读源文件
    ⇒ 必须红且**不许**打印「✓ D2 命中 0/0」
    （⚠ **如实标注**：这条主要是批 CD 的先验可读性兜住的，批 CG 是第二道）；
    **B（门项级 · 9 条 · 各变异一次 ⇒ 全红）**：① 可读性先验支的写标记
    被摘掉 ⇒ 红 / ② sed 支的写标记被摘掉 ⇒ 红（**恰好 2 处少一处就红**）/
    ③ `ci-wiring.sh` 的标记变量定义被改名 ⇒ 红 /
    ④ `ci-wiring.sh` 末尾的标记检查被改掉 ⇒ 红 /
    ⑤ `ci.sh` 的标记变量定义被改名 ⇒ 红 /
    ⑥ `ci.sh` 末尾的标记检查被改掉 ⇒ 红 /
    ⑦ `ci-d2.sh` 的标记变量定义被改名 ⇒ 红 /
    ⑧ `ci-d2.sh` 末尾的标记检查被改掉 ⇒ 红 /
    ⑨ 剥注释的 perl 调用行被改回旧形态（失败不再接住）⇒ 红
    ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）；
    **C（增量价值 · 1 条）**：不可读文件下，**forbid 违例门仍然是绿的**
    （违例仍不可见）⇒ 唯一把问题喊出来的是批 CG 的
    「失败留标记 + 末尾统一判红」机制。累计 **634/634**。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ **「读不了」靠先验可读性挡住**；`strip_comments` 若在**别的**原因上
      失败（perl 崩等）⇒ 退出码能抓到（这一类不靠退出码）；
    - ⚠ 「独立 lib 文件 + source」比「抽取」更稳（**本批未做**）；
    - ⚠ 批 CE 在 `src/ui/` 那一处的可读性验证现在与批 CG 机制**双重保护**
      （批 CE 那条门**保留未动**）；
    - ⚠ **本批原计划的盘点**（18/18 无 `pipefail`、26 处命令替换内
      `|| true`）**没有变成常驻判据**
      ⇒ 「**盘点方法本身也要被门守**」仍未做；
    - ⚠ **影响面实测为零**（只动判据层脚本 ⇒ 零产品代码改动
      ⇒ 快照零变化）；
    - ⚠ 负控里「改前世界」必须**连基线文件一起回退**
      ⇒ 否则「门自审计」会因「门项行数与基线不符」而红
      ⇒ **红因指错方向** ⇒ 拿不到「假绿」这个结论（⚠ **本批踩到**）。
  - **数字**：门项物理行数 **923 → 931**（+8）、执行次数 **926 → 934**、
    门项总数基线 `ci-wiring-gates.baseline` = **923 → 931**；豁免表**不变**（13 条）；
    接线门 **934** 项全绿、ci.sh **15/15**、selfcheck **395/0**、
    契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式
    **rc=0**、恒真探针与孤儿探针 **rc=0**；**负控 16/16 真红**。
- ⚠⚠⚨ **「盘点方法本身」也要被门守：审计器自己读不了不许当成「没问题」**（批 CH 实测）：
  - ⚠⚠⚨ **起因（实测盘点 + 对照实验，不是推演）**：批 CG 收了 **shell 侧三处**的
    「剥注释失败」⇒ 但**判据层自己**还有**第四份**剥注释实现 = **审计器**（python 侧）
    ⇒ 它把「源文件读不了」当成「**这个文件里没有**」。
    ⇒ ⚠⚠⚨ 批 CD 早就把这件事摆到台面上过：「**盘点方法本身也要被门守**」
    （批 CD 的错误结论「危险方向 0 处」就是这么来的：口径有盲区 ⇒ 结论错
    ⇒ 而没人守这个口径）⇒ 批 CH 就是那块砖：
    **审计器就是判定层常驻的「盘点方法」**。
  - ⚠⚠⚨ **洞 ①（诊断失真 · 实测坐实）**：被盯的源文件不可读（`chmod 000`）
    ⇒ 审计器 `--list` 退出码 **5**、消息是
    「**有门项命中 0 次（3 条）⇒ 那些门永远匹配不到（形同虚设）**」
    ⇒ ⚠⚠⚨ **完全不提「不可读 / 权限」**（实测 grep 计数 = **0**）
    ⇒ 真实原因是**权限**，报告说的是「**门写错了**」⇒ 排障被带偏。
  - ⚠⚠⚨ **洞 ②（崩在栈里 · 实测坐实）**：审计器自己依赖的文件
    （门脚本 / 豁免基线 / 门项总数基线）不可读 ⇒ **未捕获 `PermissionError`**
    ⇒ 退出码 **1** ⇒ 门侧只能报「**未知的失败码**」
    ⇒ 真实原因没有任何一条消息提到
    ⇒ ⚠ 批 CF 修过「**缺 perl**」的**同一形状**，**但没管「文件读不了」**。
  - ⚠⚠⚨ **洞 ③（假绿的机制缺口 · 单元级坐实）**：审计器用「**命中数 == 期望数**」
    判绿 ⇒ 而「读不了」产生的命中数恰好是 **0**
    ⇒ **凡是期望 0 次的门**，被盯文件读不了时 ⇒ 命中 0 == 期望 0
    ⇒ 校准说「0 条失准」⇒ **审计器判绿** ⇒ 而那个文件**根本没被审**。
    - ⚠ **如实记**：仓里有 **36** 条「期望 0 次」的门，但**当前仓里**每个
      被期望-0 门盯着的文件**同时**被别的门盯着 ⇒ 端到端实测 rc=5
      （红，但**红因指错**）⇒ **彻底假绿尚未落地**；
    - ⇒ 但**机制缺口是真的**（单元级实测：旧版 `count_hits` 对不可读文件
      返回 **0**）⇒ 必须先挡住。
  - ⚠⚠⚨ **洞 ④（门侧 · 负控 A6.1 逮到）**：批 CG 把诊断放在**脚本末尾**
    ⇒ 而段落末尾的 `if [ "$ARCH_FAIL" -ne 0 ]; then … exit 1` 会**提前 exit**
    ⇒ 末尾的标记检查**根本跑不到** ⇒ 「剥注释失败」诊断**打不出来**
    ⇒ 门侧只报「**出现 0 次（期望 2 次）**」⇒ **真话被藏了**。
  - **修法**（只动判据层 ⇒ **零产品代码改动**）：
    - ① **统一读入口** `read_source()`：读不了 ⇒ 抛 `UnreadableSource`
      ⇒ 所有读源文件的地方都走它 ⇒ 一次挡住整类（批 CD 纪律）；
    - ② **先验可读性**（`os.access` 用**真实 uid** ⇒ 与 shell 的 `-r` 同口径
      ⇒ **两侧口径一致**，不会一边绿一边红）；
    - ③ **接住工具的退出码**（批 CG 纪律：工具失败 ≠ 没找到）
      ⇒ ⚠⚠⚨ 实测 `perl` 打不开文件时退出码仍是 **0**
      ⇒ 只靠退出码抓不住 ⇒ 必须先验；
    - ④ **顶层兜底** ⇒ 指名道姓 + **rc=2**（盲区：那些门项**根本没被审**）
      ⇒ 与「缺 perl」同款 ⇒ 门侧的 rc=2 分派消息**同步补一句**（批 BB）；
    - ⑤ **门侧诊断搬进退出 trap** ⇒ 无论从哪退出都会打出来并点名那个文件
      ⇒ 末尾的显式检查只负责 `exit 1`（诊断不再重复打）。
  - **落门 / 判据**：新增 **14** 条（**1 forbid + 13 条全整行锚定**）——
    审计器「**不许再直接用 open 读源文件**」（forbid ⇒ 盯**写法**
    ⇒ 将来新增的读文件点自动被约束）+「异常类定义」（**带左括号**）
    +「统一读入口定义」（**带左括号**）+「先验可读性」+「接住工具退出码」
    + 三处 `raise UnreadableSource`（**失败点逐条钉住**）+「顶层兜底」
    +「顶层入口」+「rc=2 的分派消息**必须提到「源文件读不了」**」
    + 三个脚本的「退出 trap **必须带剥注释失败的诊断**」；
    **原地替换 5 条**（批 BM 纪律：不增行）：审计器 `return 2` 条数 **6→7**、
    rc=2 的分派消息、批 CG 那 3 条「末尾检查」门的**说明文字**
    （机制变了 ⇒ 说明要跟着改，批 BB）；
    - ⚠⚠⚨ **门项正则一律由现抽实际行生成**（批 BS 纪律：绝不手写）
      —— 包括 trap 那 3 条：**结构钉死、措辞自由**
      （`[^;]*剥注释失败[^;]*` ⇒ 只锁「必须提到这一类」⇒ 改文案不会假红）；
    - **同步**：门项总数基线 **931→945**；豁免表**不变**（13 条）。
  - ⚠⚠⚨ **负控 23/23 真红**：
    **A（行为级 · 7 条 · 可复现）**：A0.1 **基线**（干净工作区 ⇒ rc=0）/
    A1.1 **改后**（不可读 ⇒ 审计器**必须 rc=2** 且**指名道姓**）/
    A2.1 **改前对照·诊断失真**（旧版 rc=5 且**完全不含任何权限字样**）/
    A3.1 **改前对照·崩在栈里**（旧版 rc=1 `PermissionError`
    ⇒ 新版 rc=2 且点名）/
    A4.1 **假绿的机制缺口（单元级）**（旧版 `count_hits` 返回 **0**
    ⇒ 与「期望 0 次」**配平**；新版必须**抛**）/
    A5.1 豁免基线 / 门项总数基线不可读 ⇒ rc=2 且指名道姓/
    A6.1 **两侧口径一致**（门侧说「剥注释失败」+ 审计器说「读不了」
    ⇒ 两边都红、都说真话）；
    **B（门项级 · 16 条 · 各变异一次 ⇒ 全红）**：① 加回直接 `open` 读源文件
    ⇒ 红 / ②③ 异常类与统一读入口被改名 ⇒ 红 /
    ④⑤ 不再先验可读性、不再接住工具退出码 ⇒ 红 /
    ⑥⑦⑧ 三处 `raise` 改成静默返回空 ⇒ 红 / ⑨ 顶层不再兜底 ⇒ 红 /
    ⑩ 顶层入口被改名 ⇒ 红 / ⑪ rc=2 分派消息里删掉「源文件读不了」⇒ 红 /
    ⑫ 新增的那处 `return 2` 改成别的码 ⇒ 红（批 CC 口径：按码值分桶
    ⇒ 旧桶 7→6）/ ⑬ **正向**（「直接 open 读源文件」恰好 0 处
    ⇒ forbid 门必须绿）/ ⑭⑮⑯ 三个脚本的 trap 里去掉诊断 ⇒ 红
    ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）。
    累计 **657/657**。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ **假绿尚未端到端落地**（当前仓里落的是「红因指错」，
      机制缺口单元级已坐实）；
    - ⚠ 审计器的 `return 2` 现在有**两种来源**（「缺 perl」/「源文件读不了」）
      ⇒ 门侧分派消息必须把两种都说清楚（已同步）；
    - ⚠ 门侧 trap 的诊断**只覆盖「剥注释失败」** ⇒ 其它失败态仍各自报各自的
      （故意：批 CE 诊断不许失真 ⇒ 一个失败态一条消息）；
    - ⚠ 审计器只审「门项涉及的文件」⇒ 那些文件之外的不可读由门侧管
      ⇒ **两侧互补**，不是重复；
    - ⚠ **本批原计划的盘点**（18/18 无 `pipefail`、26 处命令替换内
      `|| true`）**仍未变成常驻判据**
      ⇒ 「**盘点方法本身也要被门守**」只做了**第一块砖**；
    - ⚠ **影响面实测为零**（只动判据层脚本 ⇒ 零产品代码改动
      ⇒ 快照零变化）；
    - ⚠⚠⚨ **本批自踩两处**：
      ① 用 `rfind("'")` 找标签的**开引号** ⇒ 拿到的是**闭引号**
      ⇒ 新标签被接在旧标签后面 ⇒ 每行 5 个引号 ⇒ **shell 语法坏掉**
      ⇒ ⚠ **教训：门项行的引号定位要用「第 3 个单引号」**，不要用 `rfind`；
      ② 负控里「改前对照」的**测量时机**踩了坑（还原权限后才测新版
      ⇒ 新版当然 rc=0）⇒ ⚠ **教训：两次测量必须在同一权限状态下**。
  - **数字**：门项物理行数 **931 → 945**（+14）、执行次数 **934 → 948**、
    门项总数基线 `ci-wiring-gates.baseline` = **931 → 945**；豁免表**不变**（13 条）；
    接线门 **948** 项全绿、ci.sh **15/15**、selfcheck **395/0**、
    契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式
    **rc=0**、恒真探针与孤儿探针 **rc=0**；**负控 23/23 真红**。
- ⚠⚠⚨ **「未验证」不许被当成「通过」**（批 CI 实测）：
  - ⚠⚠⚨ **起因（实测盘点 + 对照实验，不是推演）**：
    ⚠⚠⚨ 盘点 `scripts/` 下**命令替换内带 `|| true`** 的站点 **21 处**
    ⚠⚠⚨ **批 CJ 实测订正**（台账 E.2as）：此处原写「**24 处**」⇒ **多了 3 处假阳性**（原盘点器**跨行合并把注释并进块**⇒ 跨度配对错乱）；⚠ **三个盘点器给出 24 / 26 / 21 三个数** ⇒ 一次性盘点的数字**不可信** ⇒ 批 CJ 已把盘点**搬进仓内常驻脚本 + 逐处带理由的登记册**
    （批 CG/CE 的原盘点说 26 处 ⇒ **本批实测口径是 24**）
    ⇒ 这 21 处正是「**命令替换内部把退出码吞掉**」的形状
    （批 AZ 纪律：`|| true` 才是真正吞退出码的东西，管道本身不吞）。
  - ⚠⚠⚨ **洞 ①（内层 SKIP 不计数 · 实测坐实）**：契约门里 **14 处内层 SKIP**
    （客户端二进制缺席 / 打桩服务器没起来 / GitHub API 不可达 / 没有 curl /
    没有 python3 …）**只打印、不计数** ⇒ 末尾判 `fail` ⇒ **exit 0**
    ⇒ ⚠⚠⚨ **「这些组根本没验」被当成「通过」**。
    - ⚠⚠⚨ **实测（客户端缺席场景）**：
      旧版汇总行 = `85 passed, 1 failed`（**没有「未验证」这一项**）
      ⇒ 新版 = `85 passed, 1 failed, 9 unverified`
      （实际 `grep -c SKIP` = **9**，与计数对得上）
      ⇒ 旧版里那 **9 组**既没算失败、也没算未验证
      ⇒ 只要别的都过 ⇒ **exit 0**；
    - ⇒ 而**每条 SKIP 消息里都写着「本项**未验证**，不算通过」**
      ⇒ ⚠⚠⚨ **说法比门宽**（批 AA 教训：承诺写在那儿，判据却不认它）。
  - ⚠⚠⚨ **洞 ②（取数失败落进「判通过」那一支 · 实测坐实）**：
    `E2E_OUT` 取数失败 ⇒ `E2E_N=""` ⇒ `[ "" -eq 0 ]` 在 **dash** 里
    报「**Illegal number**」并返回 **2** ⇒ `if` 判假 ⇒ 落到 elif
    ⇒ `[ 0 -ne 0 ]` 假 ⇒ **else ⇒ 判通过**
    ⇒ ⚠⚠⚨ **取数失败被当成「没有问题」** ⇒ 假绿。
    - ⚠ **教训（通用）**：`[ "" -eq 0 ]` 不是「假」，它是**类型错误**
      ⇒ 退出码 **2** ⇒ 条件落空 ⇒ 落进**下一个分支**
      ⇒ **空值必须先判空**（`-z`），不许直接进数值比较。
  - ⚠⚠⚨ **洞 ③（CI 层「未验证」仍绿）**：CI 第 10 步收到契约门的 rc=3 时
    **只打印「不算通过」** ⇒ **CI 继续** ⇒ 最后照样打「**✓ CI 门通过**」
    ⇒ **核心门根本没验，却说 CI 通过** ⇒ 假绿
    （引擎缺席那一支同理 ⇒ 连契约门都没跑起来）
    ⇒ ⚠ 这是**批 CB 明知并记下的边界**（「SKIP 后 CI 仍绿」）⇒ 本批收口。
  - **修法**（只动判据层 ⇒ **零产品代码改动**）：
    - ① 契约门加**未验证计数器** `skip`；**14 处内层 SKIP 各加**
      `skip=$((skip+1))`（缩进分布：4 空格 **4** 处 / 8 空格 **7** 处 /
      12 空格 **3** 处）；
    - ② 末尾按未验证判
      `if [ "$skip" -ne 0 ] && [ "$fail" -eq 0 ]; then … exit 3; fi`
      ⇒ ⚠ **失败优先**（真有失败 ⇒ 仍报 1 ⇒ 未验证**不掩盖**失败）
      ⇒ ⚠ 该写法**不含 `fail=`** ⇒「写 fail 变量的行数」那条门不受影响
      ⇒ ⚠ 末尾判定行 `[ "$fail" -eq 0 ]` **原样保留** ⇒ 那条门也不受影响；
    - ③ **取数失败先判空** `[ -z "$E2E_N" ] || [ "$E2E_N" -eq 0 ]`
      ⇒ 空 ⇒ 走「没取到可比对的符号」那一支（**判红**）；
    - ④ **CI 第 10 步**：**rc=3 ⇒ 判红**、**引擎缺席 ⇒ 判红**
      ⇒ ⚠ 批 CB 已给契约门留了专属码 3 ⇒ 这一层能分清「未验证」与「失败」。
  - **落门 / 判据**：新增 **7** 条（**全整行锚定**）—— 契约门
    「**必须有未验证计数器**」+ 三种缩进的 `skip=$((skip+1))`
    （**恰好 4 / 7 / 3 处**）+「末尾**按未验证判**」+
    「**取数失败不许落进「判通过」那一支**」+ `ci.sh`
    「**引擎缺席支必须判红**」；
    **原地替换 3 条**（批 BM 纪律：不增行）：`ci.sh` 的 `exit [1-9]` 条数
    **31→33**、契约门 `^    exit 3$` 条数 **1→2**、CI 第 10 步 SKIP 支门
    改成**盯判红那行**（措辞变了 ⇒ **说明文字必须同步改**，批 BB）；
    - ⚠⚠⚨ **门项正则一律由现抽实际行生成**（批 BS 纪律：绝不手写）
      ⇒ 三种缩进**各成一条门**
      （批 CG 教训：同内容不同缩进是常态 ⇒ 一条整行正则罩不住）；
    - **同步**：门项总数基线 **945→952**；豁免表**不变**（13 条）。
  - ⚠⚠⚨ **负控 15/15 真红**：
    **A（行为级 · 5 条 · 可复现）**：A0.1 **基线**（rc=0 且
    `120 passed, 0 failed, 0 unverified`）/
    A1.1 **改前对照**（客户端缺席 ⇒ 旧版汇总行**无「未验证」项**
    ⇒ 新版**看得见** ⇒ 坐实「内层 SKIP 不计数」）/
    A2.1 **单元级·末尾判定三情形**（只有未验证 ⇒ **exit 3** /
    有未验证且有失败 ⇒ **exit 1** 失败优先 / 都没发生 ⇒ 0）/
    A3.1 **单元级·取数失败**（`E2E_N` 为空 ⇒ **必须落进「判红」那一支**
    ⇒ 不许落进「判通过」）/
    A4.1 **CI 层**（rc=3 与引擎缺席**两处都判红**且
    **后面真的跟着 `exit 1`**）；
    **B（门项级 · 10 条 · 各变异一次 ⇒ 全红）**：① 去掉未验证计数器 ⇒ 红 /
    ②③④ 三种缩进的计数**各少一处** ⇒ 红 /
    ⑤ 末尾不再按未验证判 ⇒ 红 / ⑥ 取数失败不再判空 ⇒ 红 /
    ⑦ `ci.sh` 引擎缺席支改回只打印 ⇒ 红 /
    ⑧ `ci.sh` 有一处失败上报出口被改成 `exit 0`（**离开失败桶**）⇒ 红 /
    ⑨ 契约门新增的那处 `exit 3` 被改掉 ⇒ 红 /
    ⑩ `ci.sh` 的 rc=3 分支改回只打印 ⇒ 红
    ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）。
    累计 **672/672**。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ 端到端「**只有未验证、无失败 ⇒ exit 3**」只有**单元级覆盖**
      （端到端实测时第 16 组先失败 ⇒ 失败优先那一支**抢先判红**
      ⇒ 端到端看到 rc=1）⇒ ⚠ **设计使然**，不是漏网；
    - ⚠ **假绿在当前仓落的是「红因指错」**（端到端结果是红，
      但报的是那 1 条失败，不是 9 组没验）
      ⇒ ⚠ 机制缺口是真的（单元级已坐实旧版退出码 0）；
    - ⚠ **21 处 `|| true` 盘点**本批**仍未变成常驻判据**
      ⇒ 本批做的是「**内层 SKIP 计数 + 末尾判 + CI 判红**」这条具体链路
      ⇒ 「**盘点方法本身也要被门守**」**第二块砖**待落；
    - ⚠ 本批只收「**未验证 ⇒ 通过**」这一类 ⇒ 其余形状
      （批 CD/CG/CH/CE 已收）不在本批范围；
    - ⚠ **影响面实测为零**（只动判据层脚本 ⇒ 零产品代码改动
      ⇒ 快照零变化）；
    - ⚠⚠⚨ **本批自踩一处**：负控的「改前对照」必须用
      **HEAD 版契约门**跑 ⇒ 否则「旧版」其实也是新版
      ⇒ 对照实验作废（批 CH 同款教训：两次测量要在同一口径下）。
  - **数字**：门项物理行数 **945 → 952**（+7）、执行次数 **948 → 955**、
    门项总数基线 `ci-wiring-gates.baseline` = **945 → 952**；豁免表**不变**（13 条）；
    接线门 **955** 项全绿、ci.sh **15/15**、selfcheck **395/0**、
    契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式
    **rc=0**、恒真探针与孤儿探针 **rc=0**；**负控 15/15 真红**。
- ⚠⚠⚨ **「一次性盘点的数字」不许被当成事实**（批 CJ 实测）：
  - ⚠⚠⚨ **起因（实测坐实，不是推演）**：批 CG / 批 CE / 批 CI 的结论都引用过
    同一个数字「`scripts/` 下**命令替换内带 `|| true`** 的站点 **N** 处」
    ⇒ 那个数字来自**一次性盘点脚本**（还放在 `/tmp` 里，**不在仓内**）
    ⇒ ⚠⚠⚨ **仓内没有任何东西能重算出它** ⇒ 数字不可复核、不可 review。
  - ⚠⚠⚨ **实测：三个盘点器给出三个数**：
    | 盘点器 | 口径 | 结果 |
    |---|---|---|
    | 批 CI 原盘点器（一次性） | **跨行合并把注释并进块** ⇒ 跨度配对错乱 | **24**（多 **3** 处**假阳性**） |
    | 逐行 + **不剥注释** | 注释里的 `|| true` 也算 | **26** |
    | **仓内常驻脚本**（批 CJ 新增） | 剥注释 + 正确 shell 词法 + 嵌套括号 | **21（真值）** |
    - ⇒ ⚠⚠⚨ **批 CI 已推送的文档里写的是「24 处」⇒ 错了**
      ⇒ 本批一并**订正并留痕**（批 BB：说明必须与实际一致）。
  - ⚠⚠⚨ **洞（真洞 · 逐处才发现 · 实测坐实）**：`ci.sh` 的**分层纪律门**
    （判定层 `logic/` `models/` 零 QWidget 头）原先是
    `grep -rlE … "$SRC/src/logic" "$SRC/src/models" 2>/dev/null || true`
    ⇒ ⚠⚠⚨ 源文件对 grep **不可读** ⇒ grep **静默跳过**它
    ⇒ 若那个文件里**有** QWidget 头 ⇒ `GW_HITS` 仍为空
    ⇒ **分层纪律门放行** ⇒ **假绿**；
    - ⇒ ⚠⚠⚨ **同一个洞在 `ci-d2.sh` 里已经被批 CD 堵上**
      ⇒ ⚠⚠⚨ **同一个洞堵一半比不堵更坏**（以为有门 ⇒ 实际没有）。
  - **修法**（只动判据层 ⇒ **零产品代码改动**）：
    - ① **仓内常驻盘点脚本** `scripts/ci-true-audit.py`：
      **复用判据层自己的剥注释**（直接 import `ci-wiring-audit.py` 的
      `strip_comments` ⇒ **单一真相源**，批 CF：绝不复刻）
      + ⚠⚠⚨ **抽取自检**（批 CF 教训：「**复用实现的方式本身要有自检**」
      ⇒ 从 `ci-wiring.sh` **原文抽取** `strip_comments` 跑一遍，
      与审计器侧**逐字节对拍** ⇒ 口径漂移当场红）
      + ⚠⚠⚨ **正确的 shell 词法**（**单引号内不做替换**、**双引号内照样做替换**）
      + **嵌套括号**正确配对；
    - ② **登记册** `scripts/ci-true-audit.baseline`（**独立文件**，批 BH）：
      **21 条**、每条 **6 段**、**逐条带理由**（批 BN）
      ⇒ ⚠⚠⚨ **分隔符用 TAB 而不是 `|`**（理由里要写「`|| true`」
      ⇒ 用竖线分隔会把行**劈开** ⇒ 段数对不上 ⇒ 登记册**永远读不出来**）
      ⇒ **指纹不含行号**（行号漂移 ⇒ **假红** ⇒ 批 BS：假红比假绿更坏）
      ⇒ 指纹含**同指纹序号**（区分同款代码的两份拷贝）；
    - ③ **双向红**（批 BH：恰好口径双向红）：
      「实测有、登记册没有」⇒ **红**（新增未登记）
      /「登记册有、实测没有」⇒ **红**（登记册腐化 ⇒ 修好后请删那一行）；
    - ④ **堵洞**：`ci.sh` 加 `find … ! -readable` 预检（照批 CD 同款口径）
      ⇒ 读不了 ⇒ **判失败** ⇒ 末尾的 `exit 1` 触发 ⇒ 「✓」永远打不出来。
  - **落门 / 判据**：新增 **15** 条（**14 条全整行锚定 + 1 条 forbid**）——
    登记册**条数基线常量** + 条数**必须恰好等于**基线 + 每行**恰好 6 段**
    + 每行**必须写清理由** + 判「**登记册有、实测没有**」
    + 判「**实测有、登记册没有**」+ **必须跑抽取自检**
    + 失败上报出口 `return 1`（批 CA 口径）+ 入口 `sys.exit(main())`（批 CA）
    + **必须复用**判据层自己的剥注释 + 接线门**必须真的跑一次盘点**（批 BD）
    + `ci.sh` **必须先验可读性** + 读不了时**必须判失败**
    + **必须真的置失败位** + forbid「**不许自己实现剥注释**」；
    **原地替换 2 条**（批 BM：不增行）：`ANCHOR_SCOPE_SUFFIXES` 那条门项
    **把整个常量写死**了 ⇒ 跟着改（现抽生成）；`ARCH_FAIL=1` 的条数门
    **37 → 38**（⚠ **说明文字里的「恰好 37 处」同步改成 38**，批 BB）；
    - ⇒ **同步**：门项总数基线 **952 → 967**；豁免表**不变**（13 条）；
      恒真探针的**扫描范围基线**（python 文件数 **3 → 4**，独立文件）；
    - ⇒ ⚠⚠⚨ **门项正则一律由现抽实际行生成**（批 BS：绝不手写）
      —— 含**尾注释**的门项也照抄整行 ⇒ 与批 CD 段既有形态**完全同款**。
  - ⚠⚠⚨ **负控 22/22 真红**：
    **A（行为级 · 7 条 · 可复现）**：基线（rc=0 + 21 处 + 逐条相等）/
    **三个盘点器给出三个数**（24 / 26 / 21 ⇒ 坐实数字不可信；⚠ 实测原盘点器
    **现在给 27** ⇒ 它的数**还会漂**）/
    **真洞**（源文件对 grep 不可读 ⇒ **改前放行**（假绿坐实）
    ⇒ **改后判红**；两段都**现抽**：改前取 `git show HEAD:…ci.sh`）/
    **双向红** / 登记册**条数基线**（删一行 ⇒ 红）/ 登记册**理由不许空** /
    **正向**（自实现剥注释的写法恰好 0 处 ⇒ forbid 门绿）；
    **B（门项级 · 15 条 · 各变异一次 ⇒ 全红）**
    ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）
    ⇒ 累计 **694/694**。
  - ⚠⚠⚨ **负控还逮到两个「门形同虚设」（本批最有价值的副产物）**：
    - ① `load_baseline` 原来用 `strip()` ⇒ **行尾空白被吃掉**
      ⇒ 「理由为空」先变成「5 段」⇒ **「没有理由」那条判定永远到不了**
      ⇒ **门在，牙没有**（批 AX 的形状）
      ⇒ 修法：**只去换行符**（`rstrip('\r\n')`）；
    - ② **条数检查提前 `return 1`** ⇒ 「登记册多/少一行」会**先**被条数拦下
      ⇒ **「登记册腐化」那条判定永远到不了** ⇒ 又一个**门在、牙没有**
      ⇒ 修法：两个判定**都报、都不提前 return**（批 AZ：一个退出码可能对应
      两种原因 ⇒ 诊断不许只报一个）；
    - ⇒ ⚠ **教训：一条判定「在」不等于「能被触发」**（门项盯的是前者）。
  - ⚠ **已知边界（如实记着）**：
    - ⚠ **行尾注释里的 `|| true` 也会被算成站点**（判据层的剥注释只剥**整行**
      注释）⇒ 将来谁在**行尾注释**里写 `|| true` ⇒ 盘点多一处
      ⇒ **假红风险**（写行尾注释时避开）；
    - ⚠ **登记册的维护成本**（每动一处要改登记册 **+** 改条数基线）；
    - ⚠ **「理由写得对不对」机器判不了**（机器只校验「非空」
      ⇒ **本批最弱的一环**）；
    - ⚠ **危险方向是逐处人工判的**（21 处里 **1 处是真洞** ⇒ 已堵；
      新增站点由写理由的人负责）；
    - ⚠ 本批只收「命令替换内 `|| true`」这一类；
    - ⚠ **批 CI 的三份文档已订正**（「24 处」⇒ **21 处**）并**留痕**；
    - ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动
      ⇒ 快照零变化）；
    - ⚠⚠⚨ **本批自踩六处**（后两处是负控逮到的「门形同虚设」）：
      ① 扫描器把**双引号**也当「跳过」⇒ 只认出 **2** 处
      （⚠ **教训：shell 词法规则不许凭印象写，必须实测**）；
      ② 扫描器用**递归**处理引号状态 ⇒ **无限递归**
      （⚠ **教训：引号状态用状态机，不许递归**）；
      ③ 登记册用 `|` 分隔 ⇒ 理由里写「`|| true`」⇒ 行被劈开（⇒ 改用 **TAB**）；
      ④ 原地替换脚本**按分隔符切数字时切错**（37 → 387）
      （⚠ **教训：改期望值要按「词」切**）；
      ⑤⑥ 见上（**判定「在」≠「能被触发」**）。
  - **数字**：门项物理行数 **952 → 967**（+15）、执行次数 **955 → 970**、
    门项总数基线 `ci-wiring-gates.baseline` = **952 → 967**；豁免表**不变**（13 条）；
    登记册 **21** 条；接线门 **970** 项全绿、ci.sh **15/15**、selfcheck **395/0**、
    契约门 **120/0**、ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式
    **rc=0**、恒真探针与孤儿探针 **rc=0**；**负控 22/22 真红**。

- **批 CK（2026-10-21）· 「未验证」不许被当成「通过」（CI 自己这一层）**
  （台账 **E.2at**）——
  - ⚠⚠⚨ **起因（实测盘点）**：`ci.sh` 自己就有 **6 处**「跳过 / 未验证」出口
    **只打印、不计数**（desktop-file-validate 缺席 / appstream-util 缺席 /
    没有 `dpkg-deb`（**D7 必经**）/ 没有 deb 产物（**D7 准验收**）/
    deb 布局验收**脚本自报 SKIP**（rc=3）/ agent 工具面门报 SKIP（rc=3））
    ⇒ CI 继续 ⇒ 最后照样打「**✓ CI 门通过**」
    ⇒ ⚠⚠⚨ **未验的组被当成「通过」** ⇒ **假绿**
    ⇒ 旧立场还写死在第 12 步注释里（「不算通过，但**不判失败**」）⇒ 本批收掉；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：`ci.sh` 加**未验证计数器** `skip`
    （6 处各 `skip=$((skip+1))`）⇒ 末尾 `if [ "$skip" -ne 0 ]; then … exit 3; fi`
    ⇒ ⚠ **专属退出码 3**（与契约门、agent 工具面门同款口径）
    ⇒ ⚠ **失败优先**（`set -e` 逐步执行 ⇒ 真失败当场 `exit 1`）
    ⇒ ⚠ 判定块**紧挨着**「✓ CI 门通过」**之前**（顺序反了 ⇒ 「✓」先打出来）；
  - **落门**：**新增 12 条**（**5 条整行锚定 + 7 条跨行锚定**）
    + **原地替换 1 条**（`ci.sh` 的 `exit [1-9]` 条数 **33 → 34**，说明文字同步改）
    ⇒ 门项总数基线 **967 → 979**；豁免表**不变**（13 条）
    ⇒ ⚠⚠⚨ **门项正则一律由现抽实际行生成**（绝不手写）；
  - ⚠⚠⚨ **负控 16/16 真红**：A（行为级 · 4 条：端到端正控 / 对照实验（单元级）/
    判定块双向 / 计数有牙（单元级））+ B（门项级 · 12 条：每条从 `ci-wiring.sh`
    原文现抽单独跑 ⇒ **双断言**：门红 **且** 命中数减少）⇒ 累计 **710/710**；
  - ⚠⚠⚨ **负控逮到三个坑**：① **端到端跑 `ci.sh` 必须带三个环境变量**
    ⇒ 少了它们 ⇒ 早期就 `exit 1` ⇒ 对照实验 rc 恒 1 ⇒ **分不出原因**
    ⇒ 结论全假；② ⚠⚠⚨ **不许用子串判「✓ CI 门通过」** ⇒ `ci.sh` 的**注释里**有
    **4 处**提到这句话 ⇒ **被注释骗过** ⇒ 必须**行首**匹配；
    ③ ⚠⚠⚨ **对 `ci.sh` 做变异 ⇒ 接线门先红 ⇒ 端到端对照实验做不了**
    ⇒ ⇒ **对照实验必须放单元级**（现抽原文跑）；
  - ⚠⚠⚨ **本机 CI 现在是红的（rc=3）**：本机**缺 `appstream-util`**
    ⇒ metainfo 合法性**没验** ⇒ 新逻辑**如实判红**
    ⇒ ⚠⚠⚨ **这不是回归，这正是本批要的效果**（以前这里是绿的）
    ⇒ 要绿须 `apt install appstream-util`（⚠ **sudo 需密码 ⇒ agent 装不了**）；
  - ⚠ **已知边界**：段落 `ARCH_FAIL` 提前 exit ⇒ 后面的段跑不到（既有结构问题）；
    **ml 门项不在整行锚定的适用范围检查内**；6 处计数的**位置**靠 ml 门项钉；
    本批只收「CI 自己这一层」；⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **967 → 979**（+12）、执行次数 **970 → 982**（+12）、
    门项总数基线 **967 → 979**；接线门 **982** 项全绿、selfcheck **395/0**、
    契约门 **120/0**、ci-d2 **0/0**、审计器 **rc=0**、恒真探针与孤儿探针 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完但 rc=3**（1 组未验证）⇒ **如实记录，不粉饰**；
    **负控 16/16 真红**。

- **批 CL（2026-10-21）· 「未验证」不许被当成「通过」（子脚本层：打包脚本 / 冒烟脚本）**
  （台账 **E.2au**）——
  - ⚠⚠⚨ **起因（实测盘点 + 逐处人工判）**：盘点判据层所有脚本的「跳过 / 未验证」
    出口 ⇒ **盘点时（改动前）68 处**带「未验证」字样的打印行 ⇒ 逐处判
    （批 CJ 纪律：危险方向靠**人工**判）⇒ ⚠⚠⚨ **3 处真洞**：
    ① `build-deb.sh` 第 2h 步「**apt 查不到候选版本**」⇒ 只打印、不计数；
    ② `build-deb.sh` 第 2h 步「**没有 apt-cache**」⇒ 只打印、不计数；
    ③ `smoke.sh`「**引擎缺席**」⇒ 只打印 ⇒ 脚本 exit 0 ⇒ 冒烟脚本说「全绿」。
    ⇒ 全部 exit 0 ⇒ CI 第 11 步照样打「**✓ deb 构建通过**」
    ⇒ ⚠⚠⚨ **说法比门宽**（批 AA 教训）；
  - ⚠⚠⚨ **另两处**：① `smoke.sh` 的 `|| exit 1` 把契约门的「未验证」(**3**)
    **压成 1（失败）** ⇒ **码值语义被顶替**（批 CC 纪律）；
    ② CI 第 11 步 `if sh … ; then` **接不住退出码** ⇒ 3 落进 else ⇒ 被当成失败；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：`build-deb.sh` 加**未验证计数器**
    `skip` + 末尾 `exit 3`（专属码）且**紧挨着**「✓ 已生成」**之前**；
    `smoke.sh` 引擎缺席 ⇒ `exit 3`、契约门 rc=3 ⇒ **原样传出**；
    `ci.sh` 第 11 步**分诊三态**（0=通过 / 3=未验证⇒计入 `skip` / 其它非 0=失败）；
    ⚠ **不用 `die`**（die 调用点有门钉住**恰好 23 处**，批 BU ⇒ 用独立计数器）；
  - **落门**：**新增 13 条**（8 条整行锚定 + 5 条跨行锚定）
    + **原地替换 5 条**（批 BM：不增行）
    ⇒ 门项总数基线 **979 → 992**；豁免表 **13 → 14 条**；
    ⚠⚠⚨ **适用范围纳入 `build-deb.sh`**（批 BS 纪律：它是 CI 第 11 步跑的断言脚本）
    ⇒ 审计器锚定形态适用范围 **15 → 16 个脚本**；
  - ⚠⚠⚨ **负控 17/17 真红**：A（行为级 · 4 条 · 全部单元级 · 现抽原文跑：
    引擎缺席 rc=3 / 计数有牙 / CI 第 11 步分诊三态 / 契约门 rc=3 原样传出）
    + B（门项级 · 13 条：每条从 `ci-wiring.sh` 原文现抽单独跑
    ⇒ **双断言**：门红 **且** 命中数减少）⇒ 累计 **727/727**；
  - ⚠ **已知边界**：⚠ **本机 CI 仍是 rc=3（1 组未验证：缺 `appstream-util`）**
    ⇒ 本批**没让它更红**（实测 17 个依赖**全部有候选版本** ⇒ 那两处**不命中**）；
    ⚠ `smoke.sh` **不许被 CI 调用** ⇒ 改动只影响本地入口的退出码语义；
    ⚠ `build-deb.sh` 那两处**是「有意不误红」**（批 AE）⇒ **不能**改成判失败；
    ⚠ deb 产物**已经写好了** ⇒ `exit 3` **不删产物**；
    ⚠⚠⚨ **本批自踩七处**（最要紧的三条）：① **门项说明文字太短 ⇒ 与批 CK 同名门项
    撞名** ⇒ 负控定位命中 2 条 ⇒ 必须重写成**唯一**且点名文件与行为；
    ② **旧门项盯的是旧形态** ⇒ 改了形态**必须**原地替换那条门项
    ⇒ 否则审计器报「次数门没配准 ⇒ 门恒红」（rc=4）；
    ③ ⚠⚠⚨ **数字漂移**：那个「**68 处**」是**改动前**的口径 ⇒ 本批**自己的改动**
    又新增 **4 处**带「未验证」字样的**提示消息**（build-deb.sh 判定块 / ci.sh 的
    deb 构建分诊 / smoke.sh 的契约门 rc=3 / ci-wiring.sh 的批 CL 段汇总消息）
    ⇒ **改动后现为 72 处**（实测 `37f8ce5`=68 ⇒ `d540a9b`=72）
    ⇒ ⚠ 那 4 处**恰恰是本批修好的东西**（已计数/已判红）⇒ **不是新洞**；
    ⇒ ⚠⚠⚨ **但这暴露一条更深的洞**：「未验证出口」的盘点口径
    **会把自己的修复也算成出口** ⇒ 数字**永远在涨** ⇒ 「N 处未验证出口」
    **本身就不可靠** ⇒ ⇒ **下一批必须把盘点搬进仓内常驻脚本 + 逐处带理由的登记册**
    （批 CJ 的教训**升级**了一版：不只是「三个盘点器三个数」，
    而是「**修一次数字就涨**」）；
  - **数字**：门项物理行数 **979 → 992**（+13）、执行次数 **982 → 995**（+13）、
    门项总数基线 **979 → 992**；豁免表 **13 → 14 条**；接线门 **995** 项全绿、
    selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、审计器 **rc=0**、
    恒真探针与孤儿探针 **rc=0**；⚠ `ci.sh` **15/15 步跑完但 rc=3**（1 组未验证）
    ⇒ **如实记录，不粉饰**；**负控 17/17 真红**。
- **批 CM（2026-10-21）· 「未验证出口」的盘点搬进仓内常驻脚本 + 逐组带理由的登记册**
  （台账 **E.2av**）——
  - ⚠⚠⚨ **起因（批 CL 实测坐实，不是推演）**：批 CK / CL 的结论都引用
    「判据层有 **N 处**『未验证 / 跳过』提示」⇒ 那个数字来自**一次性盘点脚本**
    （放在 `/tmp` 里）⇒ ⚠⚠⚨ **仓内没有任何东西能重算出它** ⇒ 数字不可复核；
    且实测：批 CL 的**修复本身**又新增了带「未验证」字样的提示消息
    ⇒ 「**修一次，数字就涨**」⇒ 「N 处未验证出口」这个说法**本身就不可靠**；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    ① **新增仓内常驻盘点脚本** `scripts/ci-unverified-audit.py`
    （口径 = 打印行且含未验证关键词；排除表**四类**：成功消息 / 步骤标题 /
    辅助提示 / 成功汇总行；分类两类：`失败上报` / `跳过提示`；
    ⚠ **剥注释复用**判据层自己的实现 ⇒ **不复刻**；⚠ 失败路径 `return 1`
    + 入口 `sys.exit(main())`）；
    ② **新增登记册** `scripts/ci-unverified-audit.baseline`
    （**15 行**、4 段 TAB 分隔：文件 \| 分类 \| 处数 \| **理由**）；
    ③ **接线门必须真的跑一次盘点**（`ci-wiring.sh` 的**第一条门项行之前**）
    ⇒ ⚠⚠⚨ 位置错了 ⇒ 前面某段红 ⇒ 提前 `exit` ⇒ **盘点根本没人跑**
    ⇒ 盘点失败 ⇒ `ARCH_FAIL=1` **紧跟 `exit 1`** ⇒ 立刻带准确诊断退出
    （⚠ 只打不退出 ⇒ 落到后面那句通用守卫 ⇒ **指错方向**）；
  - **落门**：**新增 21 条**（**20 条整行锚定 + 1 条 forbid**）
    + **原地替换 2 条**（批 BM：不增行）
    ⇒ 门项总数基线 **992 → 1013**；审计器锚定形态适用范围 **16 → 17 个脚本**；
    ⚠ **恒真探针的扫描范围基线 python 4 → 5**（⚠ 探针 fail closed ⇒
    新增判定脚本 ⇒ 它当场报红 ⇒ 必须同步基线，**这是它的设计意图**）；
  - ⚠⚠⚨ **负控 27/27 真红**：A（行为级 · 4 条 · 全部单元级：
    处数对不上 / 清单不许被删 / 实测有登记册没有 / 登记册有实测没有）
    + B（门项级 · 23 条：每条从 `ci-wiring.sh` 原文现抽单独跑
    ⇒ **双断言**：门红 **且** 命中数减少；forbid 门是危险方向 ⇒ 命中数**增加**）
    ⇒ 累计 **754/754**；
  - ⚠ **已知边界**：⚠⚠⚨ **本批最弱的一环** = 登记册按 (文件, 分类)
    **聚合计数** ⇒ 改文案不漂、只有数量变了才红 ⇒ ⚠ **代价 = 组级理由**
    ⇒ 「这一组里某一处没判红」**机器判不出来** ⇒ 危险方向靠人工逐处判；
    ⚠ 盘点脚本自己的失败消息被计入（**自指**）⇒ 改文案要改登记册；
    ⚠ 口径数的是「提示行」不是「逻辑出口数」；
    ⚠ `ci-wiring.sh` 两处「没有 perl」是 `return`（无参 ⇒ 返回 0）⇒ **潜伏洞**
    ⇒ 建议下一批收；
    ⚠ **段落 `ARCH_FAIL` 提前 exit** ⇒ 后面的段跑不到 ⇒ ⚠⚠⚨ 本批实测坐实其代价：
    审计器 **rc=6** 会**遮住** **rc=4**；
    ⚠ 盘点脚本**没有独立的 CI 步骤**（它是接线门的一部分）⇒ CI 步骤数不变；
    ⚠ 恒真探针只查 `if` 条件的恒真/恒假 ⇒ 「条件合法但恒真」抓不到
    ⇒ 需变异测试（成本高，明确不做）；
    ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）；
  - ⚠⚠⚨ **本批自踩十处**（最要紧的四条）：
    ① **手写原地替换的正则** ⇒ 把 `ANCHOR_SCOPE_SUFFIXES` 那条门改成**恒红**
    ⇒ **差点把红门推上远端** ⇒ 改法：**现抽定义行** ⇒ 程序化构造
    ⇒ **写盘前实测命中数**（本批**新增**纪律）；
    ② **行尾注释** ⇒ 审计器 `count_hits` **先剥注释再 grep**
    ⇒ 4 个带行尾注释的常量行 ⇒ 锚定后**匹配不上** ⇒ **门恒红**
    ⇒ 解释挪到**上一行**；
    ③ **生成器写盘前重读**被改的文件 ⇒ 前面步骤的内存修改**全丢**
    ⇒ 写盘前不再重读；
    ④ **盘点段插入点选错** ⇒ 盘点可能跑不到 ⇒ 插到**第一条门项行之前**
    （实测：接线门输出**第 2 行**就是盘点结果）；
    ⚠ 另六处：⑤ 盘点脚本里有一段复制粘贴的**死代码**（清掉）；
    ⑥ **负控变异只改 `if` 行** ⇒ 留下悬空的 `fi` ⇒ 整个脚本**语法错**
    ⇒ 门**根本没被执行** ⇒ **结论全假** ⇒ 改**摘整段** + 加 `sh -n` 守卫；
    ⑦ 负控「登记册**加**一行」够不着 `dead` 判定 ⇒ 「条数 ≠ 基线」先拦下
    ⇒ 该方向**只能靠替换一行**触发（**判定顺序有讲究**）；
    ⑧ 恒真探针的**扫描范围基线**没同步 ⇒ fail closed 报红 ⇒ 同步（4 → 5）；
    ⑨ 门项说明文字里的「恰好 38 处」没跟着改 ⇒ 违反批 BB ⇒ 已改；
    ⑩ 盘点失败若只 `ARCH_FAIL=1` 不退出 ⇒ 落到后面那句通用守卫 ⇒
    **指错方向** ⇒ 改成**紧跟 `exit 1`**；
  - **数字**：门项物理行数 **992 → 1013**（+21）、执行次数 **995 → 1016**（+21）、
    门项总数基线 **992 → 1013**；豁免表 **14 条不变**；盘点 **15 组 / 61 处**
    （登记册 15 行）；接线门 **1016** 项全绿、selfcheck **395/0**、D2 **0/0**、
    契约门 **120** 条真引擎断言、审计器硬门与报告模式 **rc=0**、
    恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完但 rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 27/27 真红**。
- **批 CN（2026-10-21）· 「没有 perl ⇒ 这道门没跑」必须**判红**，不许回退成 SKIP 口径**
  （台账 **E.2aw**）——
  - ⚠⚠⚨ **起因（批 CM 登记册里明写「建议下一批收」，不是推演）**：批 CM 的盘点在
    `ci-wiring.sh` 里找到 **2 处**「跳过提示」，逐处人工判 ⇒「两处都**不可达**
    （顶部已 preflight「没有 perl ⇒ exit 1」）⇒ 不是活洞；⚠ **但潜伏**：这两处是
    `return`（**无参数** ⇒ 返回上一步的退出码，通常 0）⇒ **preflight 被摘 ⇒
    静默放行 ⇒ 假绿**」
    ⇒ 逐处核对后确认：那是 `arch_forbid_han` 与 `arch_forbid_text_dup` 里
    「**没有 perl ⇒ 显式 SKIP（不算通过）**」那一支 ⇒ ⚠⚠⚨ **批 CB / CC 之前的旧口径**
    （工具坏了 ⇒ 只打印 ⇒ 继续 ⇒ 绿）；
  - ⚠⚠⚨ **更要紧的是另一条**：那两处的**唯一活路**是脚本**顶部**的
    `command -v perl … || { …; exit 1; }` ⇒ ⚠ **实测：它此前没有任何门**
    ⇒ 摘掉它 ⇒ 那两处就静默放行 ⇒ **假绿** ⇒ ⇒ **它自己必须被门盯住**；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    ① 那两处「没有 perl」分支改成**判红**（`✗` 消息 + `ARCH_FAIL=1` + `return 1`）
    ⇒ 与批 CB / CC / BI 口径统一；
    ② **给顶部 preflight 加门**（`arch_need_ml`，压行后匹配整块）
    ⇒ ⚠ 正则**现抽** ⇒ **改文案不假红、删行必红**；
    ③ **登记册跟着改**（⚠ 批 CM 的机制**自己咬了一口**，实测走通）：
    `ci-wiring.sh` 的「跳过提示」那一组**归零** ⇒ 0 处 ⇒ 登记腐化 ⇒ **删那一行**
    ⇒ 登记册 **15 → 14 行** ⇒ 盘点脚本的条数常量 **15 → 14**
    ⇒ 那条门项的期望值**原地替换**；
  - **落门**：**新增 1 条**（`arch_need_ml`）+ **原地替换 4 条**（批 BM：不增行）
    ⇒ 门项总数基线 **1013 → 1014**；豁免表 **14 条不变**；
  - ⚠⚠⚨ **负控 11/11 真红**：A（行为级 · 4 条 · 全部单元级：
    新形态现抽跑 ⇒ rc=1 / ARCH_FAIL=1 / 打出 ✗ 且无 SKIP
    + ⚠⚠⚨ **对照实验**用 **git 里现抽的真实旧代码** ⇒ rc=0 / ARCH_FAIL=0
    ⇒ **坐实「静默放行 ⇒ 假绿」**）
    + B（门项级 · 7 条：preflight 整块被删 / preflight 的 `exit 1` 被删 /
    两处体内 `ARCH_FAIL=1` 被删 / 全文总数少一处 / 盘点常量被改 /
    登记册处数被改错 ⇒ **盘点判红** ⇒ 每条从 `ci-wiring.sh` 原文现抽单独跑
    ⇒ **双断言**：门红 **且** 命中数减少）⇒ 累计 **765/765**；
  - ⚠ **已知边界**：⚠ **门项的参数个数没人管** ⇒ `arch_need_ml` 多传一个参数
    ⇒ 那个参数**变成标签** ⇒ 门仍绿但**说明文字被吞** ⇒ **诊断失真**
    （⚠ **不是假绿**）⇒ 建议下一批加「门项参数个数」检查；
    ⚠ 本批改的那两处**依然不可达** ⇒ 本批是**消除对 preflight 的依赖** +
    **给 preflight 加门** ⇒ 属「**纵深防御**」，不是「修一个活的洞」；
    ⚠ 盘点口径数的是「**提示行**」⇒ 本批消息从「‣ SKIP」改成「✗」
    ⇒ **分类变了** ⇒ 处数总数不变（61）但**分组变了** ⇒ 登记册必须跟着改
    ⇒ ⚠ 这正是批 CM 登记册机制**实测走通**的效果；
    ⚠ 段落 `ARCH_FAIL` 提前 exit（既有结构问题，未变）；
    ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）；
  - ⚠⚠⚨ **本批自踩八处**（最要紧的三条）：
    ① **`arch_need_ml` 多传了一个参数**（照 `arch_need_count` 的形态写了 4 参）
    ⇒ 那个多出来的**成了标签** ⇒ 门仍绿但**说明文字被吞**
    ⇒ ⚠ **发现方式**：接线门输出里那条门打的是「**✓ 1**」
    ⇒ ⇒ **门项的标签必须看得懂**；
    ② **删参数时把两个引号粘在了一起**（`'regex''desc'`）⇒ 审计器**认不出这条门**
    ⇒ 报 rc=2「**门型盲区**」⇒ ⇒ ⚠⚠⚨ **这正是 fail-closed 在起作用**
    （一条写坏的门项 ⇒ 审计器当场报「它根本没被审」⇒ 门自审计红 ⇒ 拦住）；
    ③ **两个函数的「没有 perl」分支首行文本完全相同** ⇒ 靠**文本搜索**定位
    ⇒ **永远命中第一个** ⇒ 改按**函数内锚点行号**定位；
    ⚠ 另五条：④ 原地替换要**按门型区分参数位置**（期望值在第 2 / 第 4 个引号段）
    ⑤ 负控 harness 的三个口径错误（ml 门要用**压行后**口径 / in-function 门取错
    正则段 / in-function 命中数要在**函数体内**数）
    ⑥ **门项参数个数没人管**（⇒ 建议下一批收）
    ⑦ 说明文字唯一性检查**误伤历史门项**（全文本来就有 3 处重名）
    ⇒ 检查必须**只查本批新增**的门项
    ⑧ 盘点脚本的条数常量与那条门项是**一对** ⇒ 改了常量**必须**原地替换那条门项
    ⇒ 否则审计器报「次数门没配准 ⇒ 门恒红」（rc=4）；
  - **数字**：门项物理行数 **1013 → 1014**（+1）、执行次数 **1016 → 1017**（+1）、
    门项总数基线 **1013 → 1014**；豁免表 **14 条不变**；
    盘点 **14 组 / 61 处**（登记册 14 行）；接线门 **1017** 项全绿、
    selfcheck **395/0**、D2 **0/0**、审计器硬门与报告模式 **rc=0**、
    恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完但 rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 11/11 真红**。
- **批 CO（2026-10-21）· 门项行的「**实参数个数**」必须与门型签名对得上（不许一行藏两条门）**
  （台账 **E.2ax**）——
  - ⚠⚠⚨ **起因（实测逮到的洞，不是推演）**：批 CL 把 `ci.sh` 第 11 步 deb 打包的门
    从「旧形态」原地替换成「新形态」时 ⇒ ⚠⚠⚨ **新门项行被追加到了旧门项行的尾巴上，
    中间连空格都没有** ⇒ shell 解析时**后一条的整个调用被并进了前一条的 label**
    （说明文字）⇒ ⇒ ⚠⚠⚨ **后一条从来没被执行过** ⇒ 而它盯的旧形态**早已不存在**
    （批 CL 改掉了）⇒ 它**真跑起来就该是红的** ⇒ ⚠⚠⚨ **CI 一直是假绿**
    （一条本该红的门，从落地起就没跑过一天）⇒ 且批 CL 的**负控也被骗了**：
    定位串**命中 2 条**却只跑了其中一条 ⇒ ⇒ ⚠⚠⚨ **负控必须确认定位到的是
    「恰好一条」门项行**（本批新增纪律）；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    ① **把粘连拆开**（`ci-wiring.sh` 第 2226 行）：**新形态**独立成行
      （`arch_need_count`）⇒ 说明文字**合并、一字不丢**（用 B 的说明，因为 B 以 A 开头
      ⇒ A 的内容整段含在里面）；**旧形态**改成 **forbid 门**（`arch_forbid`）
      ⇒ ⚠ forbid 门判「**不该有的东西没了**」⇒ 命中 >0 ⇒ 红 ⇒ **旧形态绝迹**才算数
      ⇒ 正则**从粘连文本现抽**（不手写，批 BM 纪律）；
    ② **结构性兜底**：审计器新增「门项行的**实参数个数**必须与门型签名对得上」
      ⇒ 实参个数对不上 ⇒ 那行**藏着东西** ⇒ 报 ⇒ 归入 **rc=2「盲区」**那一支
      （「那条门**根本没被审**」正是盲区的定义 ⇒ ⇒ **不用新增失败码**
      ⇒ 但 rc=2 的消息文本要同步扩充）；门型签名**现抽** `ci-wiring.sh` 的**函数定义**
      （批 AV 纪律：不复刻）⇒ 支持**定长**（必须**恰好**相等）/ **可选参**（`${N:-…}`）/
      **变参**（`shift`）三种形态 ⇒ ⚠ 切分必须按**引号配对**
      （按**词位**切 ⇒ 粘连段被当成**独立参数** ⇒ 反而测不出来）；
  - **落门**：**新增 2 条**（**整行锚定**，钉住审计器新检查的**定义行**与**调用点**）
    **+** 拆开粘连那一行（1 条 count 门 + 1 条 forbid 门）⇒ 门项总数基线
    **1014 → 1017**；豁免表 **14 条不变**；盘点登记册 **14 行不变**；
  - ⚠⚠⚨ **负控 5/5 真红**：A（行为级 · 2 条 · 单元级：
    ⚠⚠⚨ **对照实验**把**粘连行放回**（**git 现抽真实旧代码**）⇒ 审计器**指名道姓**报
    「实参数个数对不上」⇒ **rc=2**；**新形态**⇒ 审计器**不报**⇒ **rc=0**
    ⇒ 坐实「**有牙且不误红**」）
    + B（门项级 · 3 条：forbid 门把**旧形态放回**（命中 0 → 1）/
    `check_gate_arity` **定义**被删（1 → 0）/ **调用点**被删（1 → 0）
    ⇒ 每条**从原文现抽单独跑** ⇒ **双断言**：门红 **且** 命中数减少）⇒ 累计 **770/770**；
  - ⚠ **已知边界**：⚠⚠⚨ **本批修的是一条「已经假绿」的门** ⇒ 意味着**批 CL 落地后
    那条门本该是红的** ⇒ 批 CL 的负控被「定位串**命中 2 条**却只跑了一条」骗过；
    ⚠ **arity 检查只覆盖「参数个数」这一种粘连形态** ⇒ 粘连的**另一种**形态
    （两条门之间**有**空格 ⇒ 变成**多传参数**）**同样**被覆盖 ⇒ 但
    「**粘连在一条说明文字里**」这类**更隐蔽**的形态**未覆盖**；
    ⚠ **「实参数个数」检查不替代「说明文字唯一」检查** ⇒ 两者**互补**；
    ⚠ **arity 现抽自函数定义** ⇒ 抽不到签名 ⇒ **fail closed**（报「没抽到签名」⇒ 红）
    ⇒ ⚠ 代价：门型签名一旦挪出 `ci-wiring.sh` ⇒ 全部报红；
    ⚠ 段落 `ARCH_FAIL` 提前 exit（既有结构问题，未变）⇒ ⚠⚠⚨ **本批实测坐实其代价**：
    审计器 **rc=6** 会**遮住** **rc=4**；
    ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）；
  - ⚠⚠⚨ **本批自踩六处**（最要紧的三条）：
    ① **「实参数个数 == max($N)」这条规则是错的** ⇒ `arch_need_any_min` 的**第 4 参可选**
    ⇒ `arch_forbid_tree` 是**变参** ⇒ **45 条误报** ⇒ 正确定义 = **必填数 =
    「没有默认值的那些参数里的最大序号」** + `shift`；
    ② **切分必须按引号配对** ⇒ 按**词位**切 ⇒ 粘连段被当成**独立参数** ⇒ 测不出来
    ⇒ ⇒ 自己写 shell 顶层分词器（`split_shell_args`）；
    ③ **旧形态的原文要从批 CL 的父提交现抽**（`git show 75e212b:…`）
    ⇒ ⚠ **HEAD 已是新形态** ⇒ 从 HEAD 取不到旧形态；
    ⚠ 另三条：④ 说明文字合并用 **B 的说明**（B 以 A 开头 ⇒ **一字不丢**）
    ⑤ 粘连处形态是 `arch_need_count "FILE" `（**无空格**）⇒ 正则只能靠**行首**锚定
    ⑥ 审计器新增检查归入 **rc=2** ⇒ 不用新增失败码 ⇒ 但 **rc=2 的消息文本要同步扩充**
    （审计器侧 + `ci-wiring.sh` 门自审计文案）⇒ 否则「报的是什么」与「为什么报」对不上；
  - **数字**：门项物理行数 **1014 → 1017**（+3）、执行次数 **1017 → 1020**（+3）、
    门项总数基线 **1014 → 1017**；豁免表 **14 条不变**；
    盘点 **14 组 / 61 处**（登记册 14 行）；接线门 **1020** 项全绿、
    selfcheck **395/0**、D2 **0/0**、契约门 **120** 条真引擎断言、
    审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**（扫描范围 判定层 4 / shell 18 /
    python 5）、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完但 rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 5/5 真红**。

- **批 CP（2026-10-21）· 判据层「**先红遮后红**」不许再遮：一处红 ⇒ 全部门项照跑 ⇒ 末尾统一判红**
  （台账 **E.2ay**）——
  - ⚠⚠⚨ **起因（实测坐实，不是推演）**：判据层的「段级 trailer」原来长这样
    —— `if [ "$ARCH_FAIL" -ne 0 ]; then … exit 1; fi` ——
    而 `ARCH_FAIL` 是**全局**的（只置 1、**从不清零**）⇒ ⇒ ⚠⚠⚨ **任何一段红了，
    后面每一段的 trailer 都会 `exit 1`** ⇒ ⇒ ⚠⚠⚨ **实测：540/1017 条门项根本没跑**
    （变异后只跑到第 477 条）⇒ ⇒ 排障被迫「**改一个 ⇒ 跑一次 ⇒ 再改一个**」
    ⇒ 一次只看得见一个洞；
  - ⚠⚠⚨ **第二层（审计器侧 · 本批未收 · 明写为批 CQ）**：
    `ci-wiring-audit.py --list` 内部是 **15 个顺序早退**（**14** 个 `return N` + **1** 个统一出口）
    ⇒ 同时有两处问题时**先红的 rc 遮住后面的**
    （实测 rc=6「条数与基线不符」**遮住** rc=4「次数失准」）
    ⇒ ⚠⚠⚨ **台账订正**：批 CM / CN 台账把这条的归因写成「段落 `ARCH_FAIL` 提前 exit」
    ⇒ **实测不成立**（那是**审计器内部**的顺序早退）⇒ 段级 exit 是**另一个更大**的遮蔽；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    ① **段级 trailer 不再提前 exit** ⇒ 改成「判红 ⇒ 记全局红过（新增 `ARCH_ANY_FAIL`）
      ⇒ **继续跑**」；**37 处** trailer 统一改成 6 行形态
      （判红支 / `ARCH_ANY_FAIL=1` / `else` / 里程碑 / `fi` / 段末 `ARCH_FAIL=0`）
      ⇒ 段级 `ARCH_FAIL` 变成**段内作用域** ⇒ 「批 X 段有门项红」**仍然指名道姓**
      （段归属不失真）；**末尾统一判红** ⇒ **退出码语义不变**（红 = 1）⇒ CI 侧零改动；
    ② **另外两处「提前 exit」也收了**（同款遮蔽）：顶部**自检**（自己成段 ⇒ 它的红不许混进
      后面任何一段的归属里）+ **盘点脚本**那一处 `exit 1`（批 CM 加的 ⇒ 同样会让后面
      1000 多条门项不跑 ⇒ 盘点**自己成段** ⇒ 文案指名道姓 ⇒ **诊断精度不丢**）；
    ③ ⚠⚠⚨ **顺带收掉一颗「假红」时间炸弹**（本批实测当场引爆）：
      `strip_comments` 用 sed/perl 的**退出码**判「工具失败」，但
      `arch_need_count_in_fn` / `arch_need_count_in_step` 的 **awk 读完函数体/步正文就 `exit`**
      ⇒ 消费者**提前收工** ⇒ sed 还在写 ⇒ 被 **SIGPIPE（141）** 打断
      ⇒ 以前把 141 也当成「剥注释失败」⇒ 写标记 ⇒ 末尾判红 ⇒ ⚠⚠⚨ **假红**
      （批 BS：**假红比假绿更坏** ⇒ 逼人把承诺改弱）⇒ ⚠ **门项文件越写越大 ⇒ 越容易触发**
      ⇒ 修法：**141 一律不算工具失败**（那些消费者**故意**只取一部分 ⇒ 截断是预期的）
      ⇒ 其余非 0（sed/perl 崩了、文件读不了）⇒ **照旧判红**（fail-closed 不动）
      ⇒ 顺带**原地替换**批 CG 那条「剥注释**必须直接走 perl**」的门
      （形态从「`if ! perl …; then`」改成「`perl …` + **接住退出码**」
      ⇒ 否则**拿不到原始退出码** ⇒ 分不清 141 与真失败）；
  - **落门**：**新增 7 条**（**全整行锚定**）—— ① 全局红过标志的声明（**恰好 1 处**）
    ② 每个段级 trailer 都要记全局红过（**恰好 40 处**）
    ③ 失败位的声明 + 每段末清零（**恰好 41 处** = 1 + 40）
    ④ 末尾必须统一按全局红过判红（**恰好 1 处**）
    ⑤ 段级 trailer **不许再提前 exit**（**forbid 门** · 跨行锚定 · 正则**从旧形态现抽**
    ⇒ ⚠ 口径锚在 trailer **自己的** `>&2` 之后 ⇒ **不会**误伤门项说明文字里的散文「exit 1」
    ⇒ ⚠ 压行后散文与代码同处一行 ⇒ 宽正则会**假红** ⇒ 本批实测撞到过 ⇒ 已收窄）
    ⑥ 整行的 `exit 1` 必须**恰好 3 处**（顶部 preflight + 末尾剥注释检查 + 末尾统一判红
    ⇒ **段级 trailer 里一处都不许有**）
    ⑦ 剥注释的失败判定必须**容忍 141**（**恰好 2 处**：sed 支 + perl 支）；
    **原地替换 1 条**（批 CG 那条 ⇒ 期望值不变 ⇒ 门项**数**不变 ⇒ 但**行**变了 ⇒ 批 BM 纪律）
    ⇒ **同步**：门项总数基线 **1017 → 1024**（+7）；豁免表 **14 条不变**；
    盘点登记册 **14 行不变**；
  - ⚠⚠⚨ **负控 30/30 真红（6 组控制）**：
    **A（行为级 · 3 条）** ① ⚠⚠⚨ **一处真红 ⇒ 后面所有门项仍然全跑**：把最早一段的某条
    `arch_need_count` 期望值 **+5**（按行号整行改）⇒ 退出码 1 **且** 末尾里程碑仍报
    **总项数 1027** ⇒ ⇒ 1027 条门项**全跑完了**（旧形态这里只到 477）⇒ ⇒ **遮蔽已消除**
    ② **末尾统一判红被摘掉 ⇒ 假绿复现**：同一条真红 + 删掉末尾判红块 ⇒ 脚本 **exit 0**
    ⇒ ⚠⚠⚨ **明明有红却报通过** ⇒ 门红把它逮住
    ③ **剥注释工具真的坏了 ⇒ 必须判红**：把 sed 支改成非法选项 ⇒ 退出码 1 + 打出
    「剥注释失败（工具失败 ≠ 没找到）」⇒ ⇒ **141 容忍没有把真失败放过**；
    **B（门项级 · 3 条 · 各变异一次 ⇒ 全红）** ① 摘掉某处 trailer 的「记全局红过」⇒ 门红
    （命中 **40 → 39**）② 把段级 trailer 塞回旧的「提前 exit」形态 ⇒ forbid 门红
    （命中 **0 → 1**）⇒ ⇒ **两类回退形态都盯得住**（完整旧形态 + 部分回退）
    ③ 把 141 容忍改成 142 ⇒ ⚠⚠⚨ **假红复现** ⇒ 且门红（命中 **2 → 0**）
    ⇒ ⇒ **证明这条容忍是必需的**（不是可有可无的宽松）
    ⇒ ⇒ 每条**按行号整行改**、变异后 `sh -n` 过、`restore()` **刷新 mtime** ⇒ ⇒ 累计 **776/776**；
  - ⚠ **已知边界（如实记着）**：
    ⚠⚠⚨ **审计器侧那一层本批没收**（`--list` 仍是 15 个顺序早退（**14** 个 `return N` + **1** 个统一出口） ⇒ rc=6 仍会遮住 rc=4
    ⇒ **明写为批 CQ**）；
    ⚠ 「✓ 段门项全绿」现在只表示「**本段**全绿」（旧口径是「到这儿为止全绿」）
    ⇒ 文案本来就写的是「批 X 段」⇒ **语义更准**
    ⇒ 但末尾那句「✗ 接线门失败：有门项红」是**唯一的总判**；
    ⚠ **141 容忍有代价**：若将来出现「**意外**提前收工」的消费者 ⇒ 输出被截断而
    **不再报剥注释失败** ⇒ 当前所有提前收工的消费者（两个 awk + `grep -q`）都是**故意**的；
    ⚠ **本批顺带修的「假红」不是批 CP 的主题** ⇒ 但被批 CP 的改动**当场引爆**
    ⇒ 必须同批修（否则判据层直接红）；
    ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **1017 → 1024**（+7）、执行次数 **1020 → 1027**（+7）、
    门项总数基线 **1017 → 1024**；段级 trailer **37 → 40**；整行 `exit 1` **40 → 3**；
    豁免表 **14 条不变**；盘点 **14 组 / 61 处**（登记册 14 行）；
    接线门 **1027** 项全绿、selfcheck **395/0**、D2 **0/0**、契约门 **120** 条真引擎断言、
    审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**（扫描范围 判定层 4 / shell 18 /
    python 5）、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 30/30 真红**。

- **批 CQ（2026-10-21）· 判据层「先红遮后红」不许再遮（第二层 · 审计器侧）：失败态**收集**、一次报全**
  （台账 **E.2az**）——
  - ⚠⚠⚨ **起因（实测 + 对照实验，不是推演）**：批 CP 收了**脚本侧**那一层
    （段级 trailer 提前 `exit 1` ⇒ 540/1017 条门项被遮蔽）并在台账里**明写**
    「第二层（审计器侧）留作批 CQ」；第二层 = `ci-wiring-audit.py --list` 的硬门模式里
    **15 个顺序早退**（14 个 `return N` + 1 个统一出口）⇒ 同时有两处问题时
    **先红的 rc 遮住后面的** ⇒ 排障被迫「**改一个 ⇒ 跑一次 ⇒ 再改一个**」
    ⇒ 一次只看得见一个洞；
  - ⚠⚠⚨ **实测坐实（负控 N1 的对照实验 · 两个变异同时在场）**：
    ① 基线改错（⇒ rc=6「条数与基线不符」）② 某条次数门期望值 +5（⇒ rc=4「次数门没配准」）
    ⇒ **旧审计器**（HEAD 版）退出码 **6**、输出里**只有** rc=6 那条消息
    ⇒ ⚠⚠⚨ **rc=4 的消息完全不在**（遮蔽坐实）；
    ⇒ **新审计器**（本批）退出码**仍是 6**（码值语义不变）
    ⇒ ⚠⚠⚨ **但 rc=4 的消息也在**（遮蔽消除）；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    ① **失败态改「收集」**（`FAILS.append(N)`）⇒ 每处失败**记下来、继续跑**
      ⇒ 末尾**一次报全**；模块级 `FAILS = []`（`main_body()` 开头 `del FAILS[:]` ⇒ 幂等；
      ⚠ **模块级是故意的** ⇒ `main()` 的兜底 `except` 也要看得见它）；
    ② ⚠⚠⚨ **rc 仍取最先失败的那个**
      （`FAILS[0] if FAILS else (3 if outside else 0)`）⇒ **码值语义完全不变**
      ⇒ **门侧按 rc 分诊的文案表零改动**（2/3/4/5/6/7/8/9 九个分支一个字没改）
      ⇒ 差别只在「**其余失败也一并报出来**」；
    ③ **崩了也判红**：`main()` 加通用 `except Exception` ⇒ 崩 ⇒ 记 **rc=2**（盲区/未验证）
      ⇒ ⚠ **不是**「未知的失败码 1」⇒ 且**已报出来的失败态不丢**；
      ⇒ ⚠ 崩溃消息关键词落在 `print(` **同一行**（批 CM 口径数的是「提示行」
      ⇒ 落在续行上 ⇒ **盘点数不到** = 漏登记）；
    ④ ⚠ **4 处仍然是早退**（源文件读不了 / git diff 拿不到 / 跨文件命中数算不出来 /
      统一出口）⇒ 那时**后面确实不可信** ⇒ 早退是**语义正确**的
      ⇒ ⚠ 但「不跑」必须**明说** ⇒ 依赖失败的两项检查（豁免基线坏了 / 锚定自检不过
      ⇒ 整行锚定不可信）现在**明确跳过并说明**（`scope_skip`）⇒「不是没问题，是没验」；
    ⑤ ⚠ **门项总数三兄弟仍写成三段显式**（不许循环成动态 rc）
      ⇒ 保住批 CA/CC 的「**按码值分桶**」纪律（改一个码值 ⇒ 旧桶 -1 + 新桶 +1
      ⇒ **两条都红**）⇒ 为此 `check_gate_totals()` 新增 `msgs_by_kind`
      （dups / blind / total 分开；⚠ 报告模式仍用合并的 `msgs`、硬门模式用分类的
      ⇒ **两份** ⇒ 后续若加第四类**须同步两处**）；
  - **落门 / 判据**：
    - **原地替换 13 条**（`return N` → `FAILS.append(N)`，**分桶期望值不变**；
      只有 rc=2 那条 **7 → 4**：4 处**前置**早退保留 ⇒ 后面确实不可信）；
    - **新增 2 条**（**全整行锚定**）：
      ① 「失败态**收集器**的声明必须在」（`^FAILS = \[\]$`，恰好 1 处）
      ② 「rc=2（盲区 / 豁免基线不在 / 审计器崩了）**收集处**恰好 4 处」；
    - **同步**：门项总数基线 **1024 → 1026**；段级 trailer **40 → 41**；
      `ARCH_ANY_FAIL=1` = **41**、`ARCH_FAIL=0` = **42**；
      盘点登记册 **14 → 15 行**（⚠ 批 CM 纪律：新增的「未验证/跳过」提示
      **必须显式登记**）⇒ `UNVERIFIED_EXPECTED_ROWS` **14 → 15**（门项同步）；
      豁免表 **14 条不变**；锚定形态适用范围 **17 个脚本不变**；
    - ⚠⚠⚨ **顺带订正一处「说明文字与实际行为不一致」**（批 BA/BB 纪律）：
      「成功出口」那条门的说明里写着失败出口 `return N` 家族「**16 处**」
      ⇒ 改后实际是 **5 处**（4 前置早退 + 1 统一出口）
      ⇒ **已订正为 5 + 15 = 20 处**（不订正 ⇒ 门在骗人）；
    - ⚠⚠⚨ **顺带订正批 CP 文档里一个「与实测不符」的数字**：
      批 CP 的台账 / PLAN / README 写的是「`--list` 内部是 **17 个顺序 `return N` 早退**」
      ⇒ ⚠ **实测（对 HEAD 版逐行数）是 15 处**（14 个 `return N` + 1 个统一出口）
      ⇒ **已订正 6 处**（台账 2 + PLAN 2 + README 2）⇒ 如实记着，不粉饰；
  - ⚠⚠⚨ **负控 28/28 真红（5 组控制 + 9 条基线口径）**：
    - **基线（9 条）**：审计器 `--list` rc=0；`FAILS.append(4)`=1 / `FAILS.append(2)`=4 /
      `return 2`=4 / 收集处共 15 / `return 0`=3 / 统一出口=1 / 收集器声明=1 / 新门在位=1；
    - **N1（行为级 · 核心 · 5 条）**：⚠⚠⚨ **同时造 rc=6 + rc=4**
      ⇒ **两条消息都在输出里**（rc=4 旧行为完全不在）
      ⇒ **对照实验**：HEAD 版旧审计器 + 同样两个变异 ⇒ rc=6 且**只有** rc=6 的消息
      ⇒ ⇒ **坐实「先红遮后红」并证明本批消除了它**；
    - **N2（回退 · 3 条）**：把 `FAILS.append(4)` 改回 `return 4` ⇒ 目标串命中 **1 → 0**
      ⇒ 门红（退出码 1）⇒「rc=4 失败态」那条门打出 ✗；
    - **N3（统一出口 · 3 条）**：把统一出口改成 `return 0` ⇒ 命中 **1 → 0** ⇒ 门红；
    - **N4（崩了 · 3 条）**：把 `check_rx_syntax()` 改成 `check_rx_syntax(1, 2)` ⇒ 真崩
      ⇒ 退出码 **2**（**不是** 1「未知失败码」）
      ⇒ 打出「审计器**崩了**（未验证不许被当成通过）」
      ⇒ ⚠ **没有 traceback**（诊断不许失真）；
    - **N5（新门有牙 · 3 条）**：把 `FAILS = []` 改成 `FAILS = list()` ⇒ 命中 **1 → 0**
      ⇒ 门红 ⇒ ⇒ 证明**新增的**那条门不是摆设；
    - ⚠ 全部**按行号整行改**、变异后语法过、`restore()` **刷新 mtime**；
  - ⚠ **已知边界（如实记着）**：
    - ⚠⚠⚨ 审计器仍有 **4 处前置早退**（源文件读不了 / git diff 拿不到 /
      跨文件命中数算不出来 / 统一出口）⇒ 后面确实不可信 ⇒ 早退是**语义正确**的
      ⇒ ⚠ 但「不跑」必须**明说**（依赖失败的那两项现在会明确说「跳过」）；
    - ⚠ `msgs`（合并）与 `msgs_by_kind`（分类）**两份** ⇒ 加第四类须同步两处；
    - ⚠⚠⚨ 审计器崩了 ⇒ rc=2 ⇒ 但 `FAILS` 里若已有**更早**失败态 ⇒ rc 取更早那个
      ⇒ 「崩了」的码值**会被顶替**（如实记录，不粉饰）；
    - ⚠ 收齐之后**一次能看见全部问题** ⇒ 输出变长 ⇒ 仍需按 rc 分诊表定位
      ⇒ 但**不用再「改一个跑一次」**；
    - ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **1024 → 1026**（+2）、执行次数 **1027 → 1029**（+2）、
    门项总数基线 **1024 → 1026**；段级 trailer **40 → 41**；整行 `exit 1` **3 不变**；
    `ARCH_ANY_FAIL=1` = **41**、`ARCH_FAIL=0` = **42**；
    审计器失败态出口：`return N` 家族 **16 → 5**、`FAILS.append(N)` 家族 **0 → 15**
    ⇒ 失败出口共 20 处（码值分桶期望值全部不变）；
    豁免表 **14 条不变**；盘点 **15 组 / 63 处**（登记册 **15 行**）；
    接线门 **1029** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**、
    孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 28/28 真红**。

- **批 CR（2026-10-21）· 门项条数记三遍：改一边必红（不许拿「改基线」当删门项的掩护）**
  （台账 **E.2ba**）——
  - ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：判据层有条承诺
    「门项被删了 ⇒ 没人发现 ⇒ 那些承诺没人守了」⇒ 落地机制是「门项行数基线」
    ⇒ 审计器核对「文件里的门项行数 == 基线里的数字」⇒ 不等 ⇒ **rc=6**；
    ⇒ ⚠⚠⚨ **实测坐实的洞**：把 `ci-wiring.sh` 里**一条门项行删掉**
    **且** 把基线文件 **-1** ⇒ **审计器 rc=0、接线门 rc=0、✗ 行数 0**
    ⇒ ⚠⚠⚨ **全绿** ⇒ **一条承诺就这么悄悄消失了**；
  - ⚠⚠⚨ **为什么这是真洞不是理论洞**：「改基线」是**每批都要做的惯常动作**
    （批 CQ 就改了 1024 → 1026）⇒ ⇒ **惯常动作正好是最好的掩护**
    ⇒ 「删门项 + 改基线」只需**两个协同编辑** ⇒ 躲得过；
  - ⚠ **为什么「基线放独立文件」这个老设计不够**（批 BH 原意是
    「写死在审计器里 ⇒ 改审计器就能同时改标准」）
    ⇒ ⚠ **基线文件自己也是可改的** ⇒ 独立文件挡住了「改审计器」，
    却挡不住「**改基线文件**」；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：**同一件事记三遍**
    ⇒ 改任意一边 ⇒ 另外两边对不上 ⇒ **红** ——
    ① **基线文件**（`scripts/ci-wiring-gates.baseline`）
    ② **审计器源码里的新常量** `GATE_LINES_EXPECTED`
      （审计器在 `check_gate_totals()` 里核对「基线文件 == 这个常量」
      ⇒ 不一致 ⇒ **rc=6** ⇒ **码值语义不变** ⇒ 门侧分诊表零改动
      ⇒ 消息指名道姓「两个记录**只改了一边** ⇒ 有人删了门项又顺手改了基线」）
    ③ **两条整行锚定的门**（门 ③ 钉 ② 的**值**、门 ④ 钉 ② 的**判定行**
      ⇒ 判定被掏空成 `==` 就躲过了 ⇒ 交叉核对形同虚设 ⇒ 批 BL 纪律）；
  - ⚠⚠⚨ **三处必须一起动** ⇒ 「改门项条数」这个**惯常动作**从此要改 3 个地方
    ⇒ **维护负担 +1 处** ⇒ ⚠ **这是故意付的代价**；
  - **落门 / 判据**：
    - **新增 2 条**（**全整行锚定**）：门 ③（`^GATE_LINES_EXPECTED = 1028$`）
      + 门 ④（交叉核对的判定行）；
    - **原地替换 2 条**（**期望值 +1**、**不增行**）：`ARCH_ANY_FAIL=1` **41 → 42**、
      `ARCH_FAIL=0` **42 → 43** ⇒ ⚠ **说明文字里的数字也同步改**
      ⇒ 段级 trailer **41 → 42**、整行 `exit 1` **3 不变**；
    - **同步**：门项总数基线 **1026 → 1028**
      ⇒ ⚠⚠⚨ **同一个数字要写三处**（基线文件 / 审计器常量 / 门 ③ 的正则）
      ⇒ 这就是本批的机制本身；
    - 盘点登记册 **15 行不变**（本批**没有新增**「未验证/跳过」提示
      ⇒ 新消息不含那两个关键词 ⇒ 盘点处数不变 ⇒ 登记册不用动）；
      豁免表 **14 条不变**；锚定形态适用范围 **17 个脚本不变**；
    - ⚠ **批 CQ 的分桶门零改动**（`FAILS.append(6)` 仍 **1** 处）
      ⇒ 交叉核对加在**同一个** `if g['total_bad']:` 块里 ⇒ 分桶期望值不变
      ⇒ 批 CA/CC 的「按码值分桶」纪律不受影响；
  - ⚠⚠⚨ **负控 22/22 真红（4 组控制 + 6 条基线口径）**：
    - **基线（6 条）**：审计器 `--list` rc=0；基线文件 = 1028；审计器常量 = 1028；
      门 ③ 在位（定长串查）；门 ④ 在位；接线门 rc=0；
    - **N1（核心 · 对照实验 · 5 条）**：⚠⚠⚨ **删一条门项 + 基线 -1**
      ⇒ 新审计器 **rc=6** + 消息含「只改了一边」
      ⇒ ⚠ 「与基线不符」**没有**触发（证明抓住它的是**新加的交叉核对**、不是老机制）
      ⇒ ⇒ **对照实验**：**HEAD 版旧审计器 + 同样两个变异 ⇒ rc=0 全绿**
      ⇒ ⇒ **两头都有证据**：旧行为**确实**躲得过（洞坐实）、本批**确实**堵住了；
    - **N2（只改一边 · 2 条）**：只把基线文件 -1（不删门项）⇒ rc=6 +「只改了一边」；
    - **N3（只改常量 · 4 条）**：常量 1028 → 1027 ⇒ 审计器 rc=6 + 门 ③ 命中 0
      ⇒ **双红**；
    - **N4（判定掏空 · 2 条）**：把交叉核对的判定行 `!=` 改成 `==` ⇒ 门 ④ 红
      ⇒ ⇒ 证明「交叉核对的判定不许被掏空」这条门有牙；
    - **回归（2 条）**：还原后审计器 rc=0 + 接线门 rc=0；
    - ⚠ 全部**按行号**整行改/整行删、变异后语法过、`restore()` **刷新 mtime**；
  - ⚠ **已知边界（如实记着，不粉饰）**：
    - ⚠⚠⚨ **不宣称完全堵死**：同时改**四处**（删门项 / 基线文件 / 审计器常量 /
      门 ③ 的正则）仍能躲过 ⇒ **批 CR 把成本从 2 处升到 4 处、跨 2 个文件**
      ⇒ ⇒ **极显眼**（同一个数字在三处联动变 ⇒ 评审必看见）
      ⇒ ⇒ **惯常动作不再是掩护**，但**协同编辑仍可能**；
    - ⚠ **真正的完全堵死做不到**：任何**仓内**记录都是可改的
      ⇒ 要完全堵死只能靠仓外的真值（评审 / CI 配置）⇒ 本批不做
      ⇒ ⚠ 曾考虑用 **git 历史**（对比基线分支的门项条数 ⇒「判据只许增不许减」）
      ⇒ ⚠ **否决**：仓内**没有 CI 配置**（CI 在仓外）⇒ 拿不到稳定的「基线分支」参照
      ⇒ ⇒ 且**浅克隆**下 `git merge-base` 可能拿不到 ⇒ 按批 CN 纪律
      （「没跑 ⇒ 必须判红」）⇒ 浅克隆会**误红** ⇒ 不用；
    - ⚠ **交叉核对只覆盖「条数」这一个量** ⇒「门项的**内容**被改弱」仍是老边界
      ⇒ 本批只堵「**数量**对不上」这一类，不扩大宣称；
    - ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **1026 → 1028**（+2）、执行次数 **1029 → 1031**（+2）、
    门项总数基线 **1026 → 1028**（⚠ **同一个数字记三遍**）；
    段级 trailer **41 → 42**；整行 `exit 1` **3 不变**；
    `ARCH_ANY_FAIL=1` = **42**、`ARCH_FAIL=0` = **43**；
    `FAILS.append(6)` 仍 **1** 处；豁免表 **14 条不变**；
    盘点 **15 组 / 63 处**（登记册 **15 行**，本批未变）；
    接线门 **1031** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**
    （判定层 396 条判据 / shell 与 python **652** 个 if 条件（650 → 652：
    批 CR 段 trailer 的 `if` + 审计器交叉核对的 `if` ⇒ **两个都被判非恒真**）/
    断言实参 99 条）、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 22/22 真红**。

- **批 CS（2026-10-21）· 配对门不许只比「总数」：必须**逐段**配对**
  （台账 **E.2bb**）——
  - ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：判据层有条「**失败必须真的报出去**」
    的承诺，落地在 `arch_need_count_pair` 配对门（`check-deb-layout.sh` 1 对、
    `contract-check.sh` 39 对）⇒ 它保证「**报错行数 == 计数行数** == 期望」
    ⇒ 批 BZ 原意是堵「新增一条**只报错不计数**的失败路径」（总数不等 ⇒ 红 ✓）；
  - ⚠⚠⚨ **实测坐实的洞（批 BZ 遗留 ①）**：把某处的计数行**挪到别的一段**
    ⇒ 报错 **39** / 计数 **39**（**总数不变**）且 ⚠ **脚本语法仍合法**（`sh -n` 过）
    ⇒ ⇒ **审计器 rc=0、接线门 rc=0、✗ 行数 0** ⇒ ⚠⚠⚨ **全绿**
    ⇒ ⇒ 而那一处报错**不再被计数** ⇒ 它的失败**不会**被计入 `fail`
    ⇒ ⇒ 末尾判定恒真 ⇒ ⚠⚠⚨ **CI 假绿**
    ⇒ ⇒ **总数相等 ≠ 逐条对应** ⇒ 老门**抓不到**；
  - ⚠ **为什么不是理论洞**：重构时把计数挪错位置是**很普通的手滑**
    （39 段里挪一处 ⇒ 两侧数字都不变 ⇒ 没有任何现有判据会响）；
  - ⚠⚠⚨ **负控自己先写错过两版（如实记，因为第一版结论是错的）**：
    - **第 1 版**：搬**整行**（报错与计数同行）⇒ 那处的 `else` 分支被掏空
      ⇒ ⚠ **shell 语法坏了** ⇒ 「门全绿」是因为**脚本坏了**、不是因为洞
      ⇒ **结论不可靠** ⇒ 必须重做；
    - **第 2 版**：只搬计数动作、**追加**到另一条**已有**计数的行
      ⇒ 那一行变成「一行两个计数」⇒ **行数口径**下仍算 1 行
      ⇒ 计数行数 39 → **38** ⇒ ⚠ **总数变了** ⇒ 被**老门**抓到
      ⇒ 测的根本不是本批这件事；
    - **第 3 版（算数）**：搬**独立成行**的计数行（整行搬）到另一段的独立计数行之后
      ⇒ 计数行数 **39 → 39**（一减一加）⇒ **总数不变** ✔
      ⇒ 源段计数 1 → **0**、目标段 1 → **2** ⇒ 逐段配对必然违规 ✔
      ⇒ 两行**形状相同** ⇒ **语法必然仍合法** ✔；
    - ⇒ **教训**：负控的变异必须**自己先自证**：① 语法仍合法
      ② **要测的那个量**（总数）真的没变 ⇒ 否则「门全绿」可能只是因为**脚本坏了**；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    - **审计器侧逐段核对**（**零新门型** ⇒ 门型注册表不变 ⇒ 「门型覆盖对拍」不受影响
      ⇒ **豁免表也不变**）：
      - 新增 `pair_segment_bad(path, ra, rb)`：按**报错行**分段
        （从一处报错行含，到下一处报错行不含；**最后一段**到文件末）
        ⇒ **每段必须恰好 1 处计数行**；
      - 接进**已有的** `check_pair_count_gates()` ⇒ 违规 ⇒ 归入 **rc=4**
        （次数门没配准家族 ⇒ **码值语义不变** ⇒ 门侧分诊表零改动）
        ⇒ 消息自带：目标文件名、那一段起始行号、**段内计数数**、为什么是红
        ⇒ ⚠⚠⚨ **6 字段形态的打印器只打 `why`**（`got` 被丢）
        ⇒ ⇒ 关键信息**必须写进消息本身**（这是负控撞出来的）；
      - ⚠ 口径：行号用 `grep -nE`（**同一份正则、同一份剥注释文本**）
        ⇒ 与门侧 `grep -cE` **完全一致** ⇒ 零漂移；
    - 门侧那两条配对门的**语义变强了** ⇒ ⇒ **说明文字必须同步改**
      （批 BA/BB 纪律）⇒ **原地替换**；
  - **落门 / 判据**：
    - **新增 3 条**（**全整行锚定**，批 CS 独立段）：① 逐段配对的**检查函数**必须存在
      ② 逐段配对检查**必须真的被调用** ③ 逐段配对的**判定行**必须**是那一行原样**
      （批 BL 纪律：判定被掏空成 `and False:` 就躲不过）；
    - **原地替换 2 条**：两条配对门的说明文字；
    - **原地替换 2 条**：段级计数 `ARCH_ANY_FAIL=1` **42 → 43**、
      `ARCH_FAIL=0` **43 → 44** ⇒ 段级 trailer **42 → 43**、整行 `exit 1` **3 不变**；
    - **同步**：门项总数基线 **1028 → 1031**
      ⇒ ⚠⚠⚨ **同一个数字要写三处**（基线文件 / 审计器常量 / 门 ③ 的正则）
      ⇒ 这是**批 CR** 立的机制，本批照办；
    - 盘点登记册 **15 行不变**（本批**没有新增**「未验证/跳过」提示 ⇒ 新消息不含
      那两个关键词 ⇒ 盘点处数不变）；豁免表 **14 条不变**；
      锚定形态适用范围 **17 个脚本不变**；
    - ⚠ **批 CQ 的分桶门零改动**（`FAILS.append(4)` 仍 **1** 处
      ⇒ 违规归入**同一个** minbad 家族 ⇒ 分桶期望值不变）；
  - ⚠⚠⚨ **负控 18/18 真红（3 组控制 + 5 条基线口径）**：
    - **基线（5 条）**：审计器 `--list` rc=0；逐段检查的**定义行 / 使用点 / 判定行**
      三条都在位（各恰好 1 处）；接线门 rc=0；
    - **N1（核心 · 对照实验 · 7 条）**：⚠⚠⚨ 计数被挪（39/39 **总数不变**
      ⇒ 双断言前提成立）⇒ 审计器 **rc=4** + 消息含「**段内计数 N**」与「**没被计数**」
      ⇒ ⇒ **对照实验**：**HEAD 版旧审计器 + 同样变异 ⇒ rc=0 全绿**
      ⇒ ⇒ **两头都有证据**：旧行为**确实**躲得过（洞坐实）、本批**确实**堵住了；
    - **N2（判定掏空 · 3 条）**：`if seg_n != 1 and False:` ⇒ 门 ③ 红；
    - **N3（使用点掏空 · 3 条）**：`seg = None` ⇒ 门 ② 红
      ⇒ ⇒ 证明「定义了不调 ⇒ 形同虚设」也被堵；
    - **回归（2 条）**：还原后审计器 rc=0 + 接线门 rc=0；
  - ⚠ **已知边界（如实记着，不粉饰）**：
    - ⚠ **段的定义**依赖**报错行正则**的准确 ⇒ 某处报错**换写法**（不再匹配）
      ⇒ 就不在配对范围内 ⇒ **报错行正则被改弱**这条老边界**不在本批范围内**
      （但那会同时改到「报错行数」⇒ 总数校准会红 ⇒ 至少不会被静默放过）；
    - ⚠ **最后一段到文件末** ⇒ 尾部若有一处**不属于任何报错**的计数行
      ⇒ 会被算进最后一段 ⇒ 红（**故意**：孤儿计数行也值得看一眼）；
    - ⚠ 本批只覆盖 **2 个配对门** ⇒ 其它脚本里的「报错 + 计数」形态**没**被逐段核对
      ⇒ 全仓**收口到同一个 helper**（像 `build-deb.sh` 的 `die`）是更彻底的路子
      ⇒ **本批不做**（改动面大 ⇒ 风险收益不划算）⇒ 如实记为待办；
    - ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **1028 → 1031**（+3）、执行次数 **1031 → 1034**（+3）、
    门项总数基线 **1028 → 1031**（**三处**同步）；段级 trailer **42 → 43**；
    整行 `exit 1` **3 不变**；`ARCH_ANY_FAIL=1` = **43**、`ARCH_FAIL=0` = **44**；
    豁免表 **14 条不变**；盘点 **15 组 / 63 处**（登记册 **15 行**，本批未变）；
    接线门 **1034** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**
    （判定层 396 条判据 / shell 与 python **660** 个 if 条件（652 → 660：
    新增的逐段核对里有 8 个 if ⇒ **全部被判非恒真**）/ 断言实参 99 条）、
    孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 18/18 真红**。

- **批 CT（2026-10-21）· 崩了 ⇒ rc 强制 2（不许被更早的失败态顶替）**
  （台账 **E.2bc**）——
  - ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：批 CQ 把审计器崩了改成
    「记 rc=2」（盲区/未验证）⇒ 但当时 rc 取的是「**最先失败的那个**」
    ⇒ ⇒ 崩了这件事**只活在 stderr 的一行里**，而 **rc 才是 CI 的分诊依据**；
  - ⚠⚠⚨ **实测坐实**：先造一处**别的**失败（基线改错 ⇒ rc=6「条数与基线不符」）
    **且**让审计器随后崩（`check_rx_syntax()` → `check_rx_syntax(1, 2)`）
    ⇒ 输出里**两条消息都在**（批 CQ 的一次报全 ✓）⇒ 但 **rc=6**
    ⇒ 门侧分诊表第 6 档说的是「**门项行数与基线不符**（有门项被删了 / 被改成注释了
    ⇒ 那些承诺没人守了）」⇒ ⇒ 而真实原因是**审计器崩了**
    ⇒ ⚠⚠⚨ **排障被带偏**（人先去看「谁删了门项」，而真正的问题是审计器自己崩了）；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    - **崩了 ⇒ rc 强制 2**（不再取「最先失败的那个」）：新增模块级常量
      `CRASH_RC = 2`，兜底 `except` 分支改成 `return CRASH_RC`
      ⇒ **rc=2**（盲区家族：那些检查**没跑完** ⇒ 那些门项根本没被审）
      ⇒ **分诊依据不再被顶替**；
      ⇒ ⚠ **已报出来的失败态不丢**（批 CQ 的一次报全照旧）⇒ 别的失败照样看得见；
    - **为什么单独一个常量**（不是就地写 2）：就地写 2 ⇒ 整行锚定的门**分不出**
      「这处 `return 2` 是崩了、还是那 4 处**前置**早退」⇒ 单独一个常量
      ⇒ 门能**指名道姓**地盯住崩了的那一处；
    - **rc=2 的分诊文案补一句**（「也可能是**审计器崩了**」）
      ⇒ ⚠ 批 AZ/CC 纪律：**按退出码说原因** ⇒ 不然 rc=2 那一档**不包含**「崩了」
      ⇒ ⇒ 照样被带偏；
  - **落门 / 判据**：
    - **新增 2 条**（**全整行锚定**，批 CT 独立段）：① 「崩了的**退出码常量**必须被钉死」
      （`^CRASH_RC = 2$`）② 「崩了的**出口**必须走这个常量」
      （`^\s+return CRASH_RC$` ⇒ ⚠ 盯着「别改回 `return FAILS[0] if FAILS else 2`」
      ⇒ 否则**顶替的洞原样回来**）；
    - **原地替换 1 条**：rc=2 的**分诊文案**（补「也可能是**审计器崩了**」）；
    - **原地替换 2 条**：段级计数 `ARCH_ANY_FAIL=1` **43 → 44**、
      `ARCH_FAIL=0` **44 → 45** ⇒ 段级 trailer **43 → 44**、整行 `exit 1` **3 不变**；
    - **同步**：门项总数基线 **1031 → 1033**
      ⇒ ⚠⚠⚨ **同一个数字要写三处**（基线文件 / 审计器常量 / 门 ③ 的正则）
      ⇒ 沿用**批 CR** 立的机制；
    - 盘点登记册 **15 行不变**（本批**没有新增**「未验证/跳过」提示
      ⇒ 新消息不含那两个关键词）；豁免表 **14 条不变**；
      锚定形态适用范围 **17 个脚本不变**；
    - ⚠ **批 CQ 的分桶门零改动**（`FAILS.append(2)` 仍 **4** 处
      ⇒ 崩了那条仍然记 2，只是**不再参与 rc 的选取**）；
  - ⚠⚠⚨ **负控 16/16 真红（3 组控制 + 5 条基线口径）**：
    - **基线（5 条）**：审计器 `--list` rc=0；`CRASH_RC = 2` 在位；
      `return CRASH_RC` 在位；rc=2 的分诊文案已提到「崩了」；接线门 rc=0；
    - **N1（核心 · 对照实验 · 6 条）**：⚠⚠⚨ 先造 rc=6 **且**让审计器崩
      ⇒ **rc=2**（不再被顶替）⇒ ⚠ 别的失败（rc=6 那条）**照样报出来**
      ⇒ 「审计器**崩了**」那条也在输出里
      ⇒ ⇒ **对照实验**：**HEAD 版旧审计器 + 同样两个变异 ⇒ rc=6**
      ⇒ ⇒ **两头都有证据**：旧行为**确实**顶替（洞坐实）、本批**确实**堵住；
    - **N2（出口被改 · 3 条）**：`return CRASH_RC` → `return FAILS[0] if FAILS else 2`
      ⇒ 门 ② 红；
    - **N3（常量值被改 · 3 条）**：`CRASH_RC = 2` → `CRASH_RC = 3` ⇒ 门 ① 红；
    - **回归（2 条）**：还原后审计器 rc=0 + 接线门 rc=0；
  - ⚠ **已知边界（如实记着，不粉饰）**：
    - ⚠ **rc=2 现在有两种成因**（审计器自己有盲区 / 审计器崩了）⇒ 分诊表那一档
      只能**同时**说两种可能 ⇒ 人还得看 stderr 才知道是哪种
      ⇒ ⇒ **这不是完全的信息分离**；完全分离要**新增专属码**（如 rc=10）
      ⇒ ⇒ 本批**不做**（要动分诊表 + 码值语义 ⇒ 改动面更大）⇒ 记为待办；
    - ⚠ 崩了时**别的失败态照样报出来**（批 CQ 的一次报全）⇒ 但 **rc 只反映「崩了」**
      ⇒ 人可能**先**去修崩了、**后**才看到别的失败 ⇒ 这是**刻意的取舍**
      （崩了 ⇒ 后面那些检查根本没跑完 ⇒ 先修崩了才看得准别的失败）；
    - ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **1031 → 1033**（+2）、执行次数 **1034 → 1036**（+2）、
    门项总数基线 **1031 → 1033**（**三处**同步）；段级 trailer **43 → 44**；
    整行 `exit 1` **3 不变**；`ARCH_ANY_FAIL=1` = **44**、`ARCH_FAIL=0` = **45**；
    豁免表 **14 条不变**；盘点 **15 组 / 63 处**（登记册 **15 行**，本批未变）；
    接线门 **1036** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**
    （判定层 396 条判据 / shell 与 python **661** 个 if 条件（660 → 661：
    批 CT 段 trailer 的 `if` ⇒ **被判非恒真**）/ 断言实参 99 条）、
    孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 16/16 真红**。

- **批 CU（2026-10-22）· 「校验失败」不许被 `&&` 吞掉（ci.sh 第 3 步 ⇒ 假绿）**
  （台账 **E.2bd**）——
  - ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：批 CU 立项前先查了一条此前
    没人查过的线 —— 「**CI 的 15 步是不是都接住了退出码**」
    ⇒ 15 步**都**接住了（第 1/6/10/11/12/13 步都是 `|| _xxx_rc=$?` 的形态）
    ⇒ 但查到一个**没人接住的地方**：**第 3 步**（desktop / metainfo 校验）；
  - ⚠⚠⚨ **实测坐实**：把 desktop 的 `Type` 写成非法值 ⇒ `desktop-file-validate`
    **判红**（rc=1、错误打在 stdout）⇒ 但旧版 ci.sh **rc=0**、末尾照样打
    「**✓ CI 门通过**」、**15 步全部跑完** ⇒ ⇒ **假绿坐实**
    （desktop 非法 ⇒ 图标进不了启动器 / 点不起来；metainfo 非法 ⇒ 软件中心里
    没有这个应用）；
  - ⚠ **根因**：`set -euo pipefail` 对 `&&` 列表里**非末位**命令的失败
    **不触发退出**（bash / dash 实测：`false && echo OK` ⇒ 继续往下跑、rc=0）
    ⇒ ⇒ 旧形态把**校验命令的成败**挂在 `&&` 后面 ⇒ **失败不影响 CI 的结论**；
  - ⚠ **为什么没有第二道门兜底**：`desktop-file-validate` / `appstream-util`
    **全仓只在 ci.sh 那一处被调用** ⇒ 那个 `&&` 就是**唯一**的那道门
    ⇒ 它形同虚设；
  - **修法（只动 CI 脚本 + 判据层 ⇒ 零产品代码改动）**：
    - **ci.sh 第 3 步两处校验改成「接住退出码 ⇒ 失败即判红」**
      （`_dfv_rc=0` + `|| _dfv_rc=$?` + `-ne 0` ⇒ 报错并**原样报出退出码**
      + `exit 1`；与第 10/11/12/13 步**同款口径**
      ⇒ ⚠ 校验器自己的错误信息**原样留在输出里** ⇒ 诊断不失真）；
    - **判据层加 3 条门**（批 CU 独立段）：**2 条跨行锚定**（desktop / metainfo
      各自把「初始化 → 接退出码 → 判红 → `exit 1`」**整块钉住**）
      + **1 条 forbid**（ci.sh 里不许再出现「`&&` 挂着的 echo」
      ⇒ **一次挡住整类**，批 CD 纪律）；
  - **落门 / 判据**：
    - **新增 3 条**（**2 条跨行锚定 + 1 条 forbid**，批 CU 独立段）；
    - **原地替换 4 条**（批 BM 不增行）：① 批 BA 段「第 3 步 desktop/metainfo
      校验的动作还在」⇒ 正则改成新的调用行形态 ② ci.sh 的 `exit N` 计数
      **34 → 36**（本批在 ci.sh 多了 2 处失败出口）③ `ARCH_ANY_FAIL=1` **44 → 45**
      ④ `ARCH_FAIL=0` **45 → 46** ⇒ 段级 trailer **44 → 45**；
    - **同步**：门项总数基线 **1033 → 1036**
      ⇒ ⚠⚠⚨ **同一个数字要写三处**（基线文件 / 审计器常量 / 门 ③ 的正则）
      ⇒ 沿用**批 CR** 立的机制；
    - 盘点登记册 **15 行不变**（本批**没有新增**「未验证/跳过」提示
      ⇒ 新消息不含那两个关键词）；豁免表 **14 条不变**；
      锚定形态适用范围 **17 个脚本不变**；
  - ⚠⚠⚨ **负控 5/5 真红**：
    - **N1（行为级 · 对照实验）**：同一个变异 ⇒ **HEAD 版 ci.sh rc=0 +
      「✓ CI 门通过」+ 15/15 步跑完** ⇒ **本批版 rc=1 + 「✗ desktop 文件不合法
      （退出码 1）」+ 第 3 步就停** ⇒ ⇒ **两头都有证据**（旧行为**确实**放行
      ⇒ 洞坐实；本批**确实**堵住）
      ⇒ ⚠ 对照实验用了 `appstream-util` 的 **stub**（本机缺该工具 ⇒ 第 3 步走
      SKIP 支路 ⇒ `skip≠0` ⇒ 末尾恒 rc=3 ⇒ 假绿会被「未验证」这层红盖住
      ⇒ 证不出「第 3 步没停」⇒ 用 stub 补齐环境；**stub 只影响实验环境**）；
    - **N2～N6（门项级 · 逐条隔离 · 5 条）**：① 失败分支的报错文案被改
      ⇒ **恰好 1 条**门红 ② 在 ci.sh 里加一行「`&&` 挂着的 echo」
      ⇒ **恰好 1 条**门红（形态 forbid）③ metainfo 的退出码没接住
      ⇒ **恰好 1 条**门红 ④ desktop 调用行**退回旧形态** ⇒ **3 条**门红
      （形态回退被多处抓住）⑤ desktop 调用行被**追加行尾注释**
      ⇒ 整行锚定门红（批 BN 的牙）
      ⇒ ⚠ 全部**按行号**整行改、变异后 `sh -n` 过、**变异自己先自证**
      （要测的那个量**真的变了**）、`restore()` **刷新 mtime**；
  - ⚠ **已知边界（如实记着，不粉饰）**：
    - ⚠ **forbid 门只覆盖 ci.sh**（`arch_forbid` 是单文件门型）⇒ 别的文件里同款
      形态**不会被这条门抓住**（⚠ 全仓 grep 过：`&& echo` 在判据层脚本里
      **只有 ci.sh 这 2 处** ⇒ 类已封边；但 **macos 侧未逐个查**）；
    - ⚠ **metainfo 那一处本机没真跑过**（缺 `appstream-util` ⇒ 走 SKIP 支路）
      ⇒ 负控用 **stub** 验证通路 ⇒ **stub ≠ 真实工具** ⇒ 装上工具后应再跑一次；
    - ⚠ **批 CT 遗留的「rc=2 有两种成因」没解决**（专属码 rc=10）⇒ 仍是待办；
    - ⚠ **影响面实测为零**（只动 CI 脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **1033 → 1036**（+3）、执行次数 **1036 → 1039**（+3）、
    门项总数基线 **1033 → 1036**（**三处**同步）；段级 trailer **44 → 45**；
    整行 `exit 1`（判据层）**3 不变**；`ARCH_ANY_FAIL=1` = **45**、
    `ARCH_FAIL=0` = **46**；⚠ **ci.sh 自己的 `exit N`** **34 → 36**；
    豁免表 **14 条不变**；盘点 **15 组 / 63 处**（登记册 **15 行**，本批未变）；
    接线门 **1039** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**
    （判定层 396 条判据 / shell 与 python **664** 个 if 条件（661 → 664：
    本批 ci.sh 新增 2 个 `if` + 判据层新增 1 个段 trailer `if`）/
    断言实参 99 条）、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 5/5 真红**；累计 **865/865**。

- **批 CV（2026-10-22）· 「可达」判定不许被**注释**顶替（孤儿探针 ⇒ 假绿）**
  （台账 **E.2be**）——
  - ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：批 CU 顺着「判据层自己的门有
    几道是用文本模式匹配某样东西 ⇒ 它就一定在」这条线往下查
    ⇒ 全仓盘下来，**判据层里唯一的「假绿方向」命中**在
    `scripts/ci-orphan-probe.sh`（批 BD 立的「断言脚本不许游离在 CI 之外」门）
    —— 它的 `calls_of()` 在**原始文本**里找调用点 ⇒ ⚠⚠⚨ **不剥注释**；
  - ⚠⚠⚨ **实测坐实**（同一个脚本，两种写法）：
    - 造一个**没有任何真调用点**的断言脚本 ⇒ 探针 **rc=1**（报「游离」）✓；
    - **只**在 ci.sh 里加一行**注释**（`# sh "$SRC/scripts/<那个脚本>.sh"`）
      ⇒ 探针 **rc=0**（「全部可达」）⇒ ⚠⚠⚨ **假绿**；
  - ⇒ ⇒ **批 BD 的承诺（「仓库里少了一份断言 ⇒ 必须红」）可被一行注释破掉**
    ⇒ ⚠ 这一处**特别刺眼**：那道门是**专门为「承诺不许悄悄消失」而建**的
    ⇒ 它自己形同虚设 ⇒ **比没有门更坏**（给人虚假的安全感）；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    - `calls_of()` **先剥注释**再找调用点 ⇒ ⚠ **抽取**而非复刻（批 CF / AV 纪律：
      判据层只有**一份**剥注释实现）⇒ 与 `ci.sh` / `ci-d2.sh` **同款现成写法**
      ⇒ **零漂移**；
    - **抽取失败 ⇒ 指名道姓地失败**（不许静默降级成「不剥注释」
      ⇒ 那等于把本批收掉的洞原样放回去 ⇒ 假绿）；
    - **剥注释失败**（工具失败 ≠ 没找到）⇒ **判红**
      （不许当成「没有游离脚本」⇒ 判据不可信时必须说不可信，批 CG 同款口径）；
  - **落门 / 判据**：
    - **新增 4 条**（批 CV 独立段）：① 「**剥注释必须从 ci-wiring.sh 抽取**」
      （整行锚定）② 「抽取失败**必须指名道姓地失败**」（整行锚定）
      ③ 「**不许自己实现剥注释**」（forbid 门：sed 那一支与 perl 那一支
      **一起禁掉**）④ 「**剥注释失败必须当成失败**」（整行锚定，钉住 trap 里那一段）；
    - **原地替换 2 条**（批 BM 不增行）：① 批 BD 段「**排除门项行**」那条
      ⇒ 正则改成新形态（**一条门同时守住「先剥注释」+「排除门项行」**）
      ② 批 BD 段「孤儿探针自己的报错行计数」**7 → 8**
      ⇒ ⚠ **批 BT 的「失败上报条数」**也 **6 → 7**
      ⇒ ⚠⚠⚨ **两处「恰好 N 处」的说明文字同步改**（批 BB 纪律）；
    - **同步**：门项总数基线 **1036 → 1040**
      ⇒ ⚠⚠⚨ **同一个数字要写三处**（基线文件 / 审计器常量 / 门 ③ 的正则）
      ⇒ 沿用**批 CR** 立的机制；
    - 盘点登记册 **15 行不变**；豁免表 **14 条不变**；
      锚定形态适用范围 **17 个脚本不变**；
  - ⚠⚠⚨ **负控 5/5 真红**：
    - **N1（行为级 · 对照实验）**：同一个变异 ⇒ **修复前 rc=0（假绿）**
      ⇒ **修复后 rc=1**（「断言脚本游离在 CI 之外」）⇒ ⇒ **两头都有证据**；
    - **N2～N6（门项级 · 逐条隔离 · 5 条）**：① `calls_of` 退回旧形态
      ⇒ **恰好 1 条**门红 ② 「抽取」被摘掉 ⇒ **恰好 1 条**门红
      ③ 抽取失败的诊断被删 ⇒ **恰好 1 条**门红
      ④ 孤儿探针**自己实现剥注释** ⇒ **恰好 1 条**门红（forbid）
      ⑤ trap 里「剥注释失败 ⇒ 判红」被摘 ⇒ **恰好 1 条**门红
      ⇒ ⚠ 全部**按行号**整行改、变异后 `sh -n` 过、**变异自己先自证**
      （要测的那个量**真的变了**）、`restore()` **刷新 mtime**；
  - ⚠ **已知边界（如实记着，不粉饰）**：
    - ⚠ **剥注释口径对 `.sh` 只剥「整行注释」**（判据层既有的单一真相源口径）
      ⇒ **行尾注释**里的同形文本**仍可能**被当成调用点
      ⇒ 全仓同款口径的已知边界；
    - ⚠ **「什么算断言脚本」那条判定**（`grep -q '✗ '`）**仍不剥注释**
      ⇒ 方向是**假红**（多查一个脚本）⇒ 本批**不动它**
      （改了会动「断言脚本条数」这个口径）；
    - ⚠ **孤儿探针现在依赖 `ci-wiring.sh` 存在**（要抽它那份剥注释）
      ⇒ 路径给错 ⇒ **判红**（fail closed）⇒ 已把抽取挪到「找不到 CI 入口」检查
      **之后** ⇒ 诊断指得准；
    - ⚠ **批 CT 遗留的「rc=2 有两种成因」没解决**（专属码 rc=10）⇒ 仍是待办；
    - ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **1036 → 1040**（+4）、执行次数 **1039 → 1043**（+4）、
    门项总数基线 **1036 → 1040**（**三处**同步）；段级 trailer **45 → 46**；
    整行 `exit 1`（判据层）**3 不变**；`ARCH_ANY_FAIL=1` = **46**、
    `ARCH_FAIL=0` = **47**；⚠ **孤儿探针自己的**报错行 **7 → 8**、
    失败上报 **6 → 7**；豁免表 **14 条不变**；盘点 **15 组 / 63 处**
    （登记册 **15 行**，本批未变）；接线门 **1043** 项全绿、审计器硬门与报告模式
    **rc=0**、恒真探针 **rc=0**（判定层 396 条判据 / shell 与 python **666** 个 if
    条件（664 → 666）/ 断言实参 99 条）、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 5/5 真红**；累计 **870/870**。

- **批 CW（2026-10-22）· 崩了 ⇒ **专属码 rc=10**（与「盲区 rc=2」完全分离）**
  （台账 **E.2bf**）——
  - ⚠⚠⚨ **起因（批 CT 留下的已知边界，不是推演）**：批 CT 让「崩了」不再被更早的
    失败态顶替 ⇒ ⚠ 但当时把崩了归进 **rc=2（盲区）** ⇒ ⇒ **rc=2 有两种成因**
    （「真有盲区」/「审计器自己崩了」）⇒ 分诊那一档**说不出到底是哪一种**
    ⇒ ⇒ 人看到 rc=2 ⇒ 先去查盲区 ⇒ 若盲区清单看不出问题
    ⇒ **就不会想到是崩了** ⇒ ⚠⚠⚨ **排障还是会被带偏**；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    - 审计器 `CRASH_RC = 2` ⇒ **`CRASH_RC = 10`**（崩了时**强制**这个码）；
    - 门侧分诊表**加一档** `10) _audit_why="审计器**崩了**…"`；
    - **rc=2 的分诊文案改写**（去掉「也可能是审计器崩了」那半句
      ⇒ 现在 rc=2 **只**表示盲区 ⇒ ⚠ **说明文字必须与实际行为一致**）；
    - ⇒ ⚠⚠⚨ **rc 语义只加不改**（rc=2..9 的含义**一个字都没动**
      ⇒ 既有各档**零改动** ⇒ 只**多**一档）
      ⇒ ⚠ **别的一律不动**（`FAILS.append(2)` **照旧** ⇒ 性质分桶不变
      ⇒ 只改**分诊用的 rc**）；
  - **落门 / 判据**：
    - **新增 2 条**（批 CW 独立段）：① 「必须**按第 10 种失败态说原因**」
      （整行锚定 ⇒ 少了它 ⇒ `case` 落到 `*)` ⇒ 报「未知的失败码」
      ⇒ 排障被带偏）② 「**rc=2 的分诊文案不许再提「崩了」**」（forbid 门）；
    - **原地替换 4 处**（批 BM 不增行）：① 批 CT 段钉 `CRASH_RC` 值那条
      ⇒ 正则 `2` → **`10`**（说明文字同步改）② 批 CT 段钉「崩了的出口必须走这个常量」
      那条（形态未变，说明补批 CW 注）③ `ARCH_ANY_FAIL=1` **46 → 47**
      ④ `ARCH_FAIL=0` **47 → 48** ⇒ 段级 trailer **46 → 47**；
    - **同步**：门项总数基线 **1040 → 1042**
      ⇒ ⚠⚠⚨ **同一个数字要写三处** ⇒ 沿用**批 CR** 立的机制；
    - 盘点登记册 **15 行不变**；豁免表 **14 条不变**；
  - ⚠⚠⚨ **负控 3/3 真红**：
    - **N1（行为级 · 对照实验）**：把 `check_rx_syntax()` 改成 `check_rx_syntax(1)`
      ⇒ 必然 TypeError ⇒ 崩 ⇒ ⚠⚠⚨ **HEAD 版（整树 `git archive HEAD`）⇒ rc=2**
      ⇒ **本批版 ⇒ rc=10** ⇒ ⇒ **两头都有证据**；
    - **N2～N4（门项级 · 逐条隔离 · 3 条）**：① 分诊表的 `10)` 那一档被摘
      ⇒ **恰好 1 条**门红 ② rc=2 的文案里又混进「崩了」⇒ **恰好 1 条**门红
      （forbid）③ `CRASH_RC` 被改回 2 ⇒ **恰好 1 条**门红
      ⇒ ⚠ 全部**按行号**整行改、变异后语法过、**变异自己先自证**、
      `restore()` **刷新 mtime**；
  - ⚠ **已知边界（如实记着，不粉饰）**：
    - ⚠ **rc=10 只在「审计器崩了」这一种情形出现** ⇒ 将来别的成因要进这一档
      得逐个点名（否则又是一码多因）；
    - ⚠ **`FAILS.append(2)` 照旧** ⇒ 性质分桶仍记作盲区 ⇒ **有意**
      （性质与分诊依据分开记）；
    - ⚠ **分诊表按码值分档** ⇒ 新增一档要在**别处**同步（本批已同步）；
    - ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **1040 → 1042**（+2）、执行次数 **1043 → 1045**（+2）、
    门项总数基线 **1040 → 1042**（**三处**同步）；段级 trailer **46 → 47**；
    整行 `exit 1`（判据层）**3 不变**；`ARCH_ANY_FAIL=1` = **47**、
    `ARCH_FAIL=0` = **48**；豁免表 **14 条不变**；盘点 **15 组 / 63 处**
    （登记册 **15 行**，本批未变）；接线门 **1045** 项全绿、审计器硬门与报告模式
    **rc=0**、恒真探针 **rc=0**（判定层 396 条判据 / shell 与 python **667** 个 if
    条件（666 → 667：本批新增的段 trailer 那一个 `if`）/ 断言实参 99 条）、
    孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 3/3 真红**；累计 **873/873**。

- **批 CX（2026-10-22）· 「未验证的逻辑出口」也要进登记册（盘点口径不只数提示行）**
  （台账 **E.2bg**）——
  - ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：盘点脚本的口径是
    **「带未验证关键词的打印行」** ⇒ ⇒ 判据层里一处 `exit 3`（未验证的
    **逻辑出口**）若**没带提示** ⇒ **登记册看不见它**
    ⇒ ⇒ 「**未验证出口必须明示**」这条纪律**没有牙**；
  - ⚠⚠⚨ **实测坐实**（同一个变异，两个版本）：
    - HEAD 版：加一处**没提示**的 `exit 3` ⇒ 盘点 **rc=0**（假绿）；
    - 本批版：**同一个**变异 ⇒ **rc=1**
      （「实测有、登记册没有（新增未登记）1 条：ci-d2.sh/未验证逻辑出口=1」）；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    - 盘点口径**多算一类**「未验证逻辑出口」（`exit 3`
      ⇒ 排除表**不适用**于它 ⇒ 命中即计入）；
    - 登记册**逐文件**登记这一类的处数（+6 行）⇒ 新增一处出口
      （**带不带提示都一样**）⇒ 处数对不上 ⇒ **必红**；
    - 成功消息把「其中 N 处是未验证的逻辑出口」**说出来**（不许混在总数里）；
    - ⇒ ⚠⚠⚨ **为什么「逐文件登记处数」而不是「逐处登记」**（批 CM 遗留① 已否决）：
      逐处化会因为**同款文案**导致集合比对塌陷 ⇒ 假红；此处登记的是**条数**
      （按文件聚合）⇒ **不碰文案** ⇒ **不撞那个否决理由**；
  - **落门 / 判据**：
    - **新增 2 条**（批 CX 独立段）：① 「盘点口径必须**把「未验证的逻辑出口」
      算进来**」（整行锚定）② 「盘点必须**真的按这一类计站点**」（整行锚定）
      ⇒ ⚠⚠⚨ 两条门的正则**从真实行现抽构造**（手抄转义已踩两次坑：
      `"` 被解成字面 `"`、`` 被解成**退格符**）；
    - **原地替换 4 处**（批 BM 不增行）：① 登记册条数基线常量那条门 **15 → 21**
      （说明文字同步改）② `ARCH_ANY_FAIL=1` **47 → 48** ③ `ARCH_FAIL=0` **48 → 49**
      ④ 门项条数第三处 **1042 → 1044**；
    - **同步**：门项总数基线 **1042 → 1044**
      ⇒ ⚠⚠⚨ **同一个数字要写三处** ⇒ 沿用**批 CR** 立的机制；
    - 盘点登记册 **15 行 → 21 行**；豁免表 **14 条不变**；
  - ⚠⚠⚨ **负控 3/3 真红**：
    - **N1（行为级 · 对照实验）**：加一处**没提示**的 `exit 3`
      ⇒ ⚠⚠⚨ **HEAD 版（整树 `git archive HEAD`）⇒ rc=0**（假绿）
      ⇒ **本批版 ⇒ rc=1** ⇒ ⇒ **两头都有证据**；
    - **N2** 扫描时不再判这一类 ⇒ **恰好 1 条**门红；
    - **N3** 口径常量被改掉 ⇒ **恰好 1 条**门红；
    - **N4** 登记册少登记一个文件的未验证出口 ⇒ **盘点红**
      ⇒ ⚠ 实际先响的是「**登记册条数 ≠ 基线**」那条（批 BC）⇒ 比双向红**更早**更严；
  - ⚠ **已知边界（如实记着，不粉饰）**：
    - ⚠ 口径只认 shell 的 `exit 3`（未验证的专属码）；
    - ⚠ 盘点范围仍只是 `deepin/scripts/`（批 BX 已知边界）
      ⇒ `macos/scripts/` 的未验证出口**仍不在册**；
    - ⚠ 这一类按文件聚合 ⇒ 同一文件里**哪一处**新增的**机器看不出**
      （批 CM 遗留① 那一族的边界）；
    - ⚠ 判据层之外的 `exit 3` **不在盘点范围**；
    - ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **1042 → 1044**（+2）、执行次数 **1045 → 1047**（+2）、
    门项总数基线 **1042 → 1044**（**三处**同步）；段级 trailer **47 → 48**；
    整行 `exit 1`（判据层）**3 不变**；`ARCH_ANY_FAIL=1` = **48**、
    `ARCH_FAIL=0` = **49**；⚠ **盘点**：**15 组 / 63 处 → 21 组 / 72 处**
    （登记册 **15 行 → 21 行**；其中 **9 处**是未验证的逻辑出口）；
    豁免表 **14 条不变**；接线门 **1047** 项全绿、审计器硬门与报告模式 **rc=0**、
    恒真探针 **rc=0**（判定层 396 条判据 / shell 与 python **669** 个 if 条件
    （667 → 669）/ 断言实参 99 条）、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 3/3 真红**；累计 **876/876**。

- **批 CY（2026-10-22）· 「未验证出口登记册」的覆盖面不许只覆盖一半（范围 + 键唯一）**
  （台账 **E.2bh**）——
  - ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：盘点脚本的扫描范围**写死**在
    `SCRIPTS = HERE`（= `deepin/scripts/`）⇒ ⇒ `macos/scripts/` 里那 **12 个判据脚本**
    的未验证出口**完全不在册** ⇒ ⇒ 而判据层**早已有门项盯着 `macos/scripts/*.sh`**
    （批 AJ 起）⇒ ⇒ 「**未验证出口必须登记**」这条纪律的覆盖面**比门项覆盖面窄**；
  - ⚠⚠⚨ **实测坐实**（同一个变异，两个版本）：

    | | 盘点脚本的结论 |
    |---|---|
    | HEAD 版：在 mac 侧判据脚本里加一处**没提示**的专属码 3 出口 | ⚠⚠⚨ **rc=0**（假绿）|
    | 本批版：**同一个**变异 | **rc=1**（「实测有、登记册没有（新增未登记）1 条：macos/scripts/contract-check.sh/未验证逻辑出口=1」）|

  - ⚠⚠⚨ **第二个洞（扩范围时必踩）**：两个目录里**都有** `contract-check.sh`
    ⇒ 若登记册仍用**裸文件名**做键 ⇒ 两个文件的处数**合并**
    ⇒ ⇒ **一处新增 + 一处减少 = 净 0** ⇒ 登记册照样相等 ⇒ **假绿**
    ⇒ **两臂对照实测坐实**：臂 A（裸名键）mac +1 / deepin -1 ⇒ 盘点 **rc=0**（假绿）
    ⇒ 臂 B（路径键）**同一个**净 0 变异 ⇒ 盘点 **rc=1**（真红）；
  - ⚠⚠⚨ **第三个洞（登记册自身撞车）**：同一 (文件, 分类) 出现两行
    ⇒ 字典里**静默塌陷** ⇒ 行数对了、组数少了 ⇒ 「登记册条数基线」**名不副实**；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    - 范围改成**一个常量** `UNVERIFIED_SCOPE = ("deepin/scripts", "macos/scripts")`
      （**相对仓库根**）⇒ 递归扫（跳过 `__pycache__`）；
    - 键改成**相对仓库根的路径**（`os.path.relpath(path, REPO_ROOT)`）⇒ **唯一**
      ⇒ 登记册 **21 行**的文件列**全部**改成路径（条数不变）；
    - **fail-closed**：范围目录**不存在** / 里面**一个判据脚本都没有**
      ⇒ 当场判红（`os.walk` 对不存在的目录**不报错**、直接产出空
      ⇒ 不判红 ⇒ 范围被悄悄掏空 ⇒ 盘点等于没跑 ⇒ **假绿**）；
    - 登记册的 (文件, 分类) 键**不许重复** ⇒ 当场判红（**指名道姓**）；
    - 成功消息把**范围**说出来；
  - ⚠⚠⚨ **实测影响面为零**：mac 侧用同一套口径实测 ⇒ **当前 0 处**
    ⇒ 登记册**行数不变**（21 行）、**处数不变**（72 处）
    ⇒ ⚠ 登记册里**没有** `macos/scripts/` 的行 ⇔ **实测那边当前 0 处**；
  - **落门 / 判据**：
    - **新增 6 条**（批 CY 独立段）：
      ① 「盘点范围**必须同时含两个判据脚本目录**」（整行锚定）
      ② 「盘点**必须真的遍历**那个范围常量」（整行锚定）
      ③ 「范围目录**不存在**时必须**当场判红**」（整行锚定）
      ④ 「登记册的**键必须用相对仓库根的路径**」（整行锚定）
      ⑤ 「登记册的 **(文件, 分类) 键不许重复**」（整行锚定）
      ⑥ 「登记册**每一行的文件列都必须带目录**」（`arch_need_min` ⇒ 下限**恰好 21**
      ⇒ 与登记册条数基线 21 合起来 ⇒ **一条都不许是裸名**）
      ⇒ ⚠⚠⚨ 5 条 `arch_need_count` 的正则**从真实行现抽构造**
      ⇒ ⚠ 登记册那条**不用 POSIX 空白类**（`[[:blank:]]`）
      ⇒ ⚠⚠⚨ **Python `re` 不认 POSIX 类** ⇒ 审计器与门侧口径会分叉
      ⇒ 改用「键前缀」形态 ⇒ GNU `grep -E` 与 Python `re` **实测一致**；
    - **原地替换 6 处**（批 BM 不增行）：① 批 CM 那条钉 `selftest_strip_parity`
      调用形态的门 ② `ARCH_ANY_FAIL=1` **48 → 49** ③ `ARCH_FAIL=0` **49 → 50**
      ⇒ 段级 trailer **48 → 49** ④ 门项条数第三处 **1044 → 1050**；
    - **同步**：门项总数基线 **1044 → 1050** ⇒ ⚠⚠⚨ **三处同改**；
      盘点登记册 **21 行不变**；豁免表 **14 条不变**；
  - ⚠⚠⚨ **负控 8/8 真红**：
    - **N1（行为级 · 对照实验）**：在 mac 侧判据脚本里加一处**没提示**的
      专属码 3 出口 ⇒ ⚠⚠⚨ **HEAD 版（整树 `git archive HEAD`）⇒ 盘点 rc=0**（假绿）
      ⇒ **本批版 ⇒ rc=1** ⇒ ⇒ **两头都有证据**；
    - **N2** 范围常量被改窄 ⇒ **恰好 1 条**门红；
    - **N3** 范围常量在、但扫描时不遍历它 ⇒ **恰好 1 条**门红；
    - **N4** fail-closed 的判定行被改 ⇒ **恰好 1 条**门红；
    - **N5** 键被改成裸文件名 ⇒ **恰好 1 条**门红 **且**盘点红；
    - **N6** 登记册里出现裸名键 ⇒ **恰好 1 条**门红 **且**盘点红；
    - **N7** 登记册出现重复键 ⇒ 盘点红 **且**输出**指名道姓**
      报出「重复的 (文件, 分类) 键」；
    - **N8（两臂对照）**：跨目录处数**互相抵消** ⇒ 臂 A（裸名键）盘点 **rc=0**（假绿）
      ⇒ 臂 B（路径键）**同一个**变异 ⇒ 盘点 **rc=1**（真红）
      ⇒ ⇒ **证明「键必须唯一」不是洁癖**；
  - ⚠ **已知边界（如实记着，不粉饰）**：
    - ⚠ 重复键检查**独立于**双向红（双向红**也会**红，但它指的是
      「实测有、登记册没有」⇒ **指错了方向**）⇒ 这条门的作用是**指名道姓**；
    - ⚠ mac 侧**当前实测 0 处** ⇒ ⚠「mac 侧到底有没有未验证出口」
      **只能靠实测**，不能靠登记册反推；
    - ⚠ 盘点口径**仍只认 shell / python** ⇒ `macos/Tests/*.swift` 里的判据
      **不在盘点范围**；
    - ⚠ 口径只认 shell 的 `exit 3`；
    - ⚠ 这一类按文件聚合 ⇒ 同一文件里**哪一处**新增的机器看不出；
    - ⚠ 判据层之外的 `exit 3` **不在盘点范围**；
    - ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **1044 → 1050**（+6）、执行次数 **1047 → 1053**（+6）、
    门项总数基线 **1044 → 1050**（**三处**同步）；段级 trailer **48 → 49**；
    整行 `exit 1`（判据层）**3 不变**；`ARCH_ANY_FAIL=1` = **49**、
    `ARCH_FAIL=0` = **50**；⚠ **盘点**：**21 组 / 72 处不变**（登记册 **21 行不变**；
    ⚠ 文件列从裸名改成路径；⚠ 范围扩到两个目录后 **mac 侧实测 0 处** ⇒ 处数不变）；
    豁免表 **14 条不变**；接线门 **1053** 项全绿、审计器硬门与报告模式 **rc=0**
    （门项 1050/1050 对基线）、恒真探针 **rc=0**（判定层 396 条判据 /
    shell 与 python **673** 个 if 条件（669 → 673）/ 断言实参 99 条）、
    孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 8/8 真红**；累计 **884/884**。

- **批 CZ（2026-10-22）· 「判定不许被掏空成恒真」在 mac 侧**没有牙**（恒真探针的范围只盖一边）**
  （台账 **E.2bi**）——
  - ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：恒真探针（批 BG/BJ 立的）的
    shell 扫描范围**只有 `deepin/scripts/`**（`os.listdir(scripts)` ⇒ **单目录、
    只看顶层**）⇒ ⇒ `macos/scripts/` 里那 **12 个判据脚本**上的 if 条件
    **从来没被查过** ⇒ ⇒ 而 mac 侧 `macos/build.sh` **确实会跑**它们
    （`contract-check.sh` / `agent-check.sh` / `client-check.sh` /
    `catalog-check.sh` / `markdown-check.sh` …）⇒ ⇒ 它们就是 **mac 平台的判定层**
    ⇒ ⇒ 那里出现恒真条件 ⇒ **mac 构建的判定静默通过** ⇒ 没人发现；
  - ⚠⚠⚨ **实测坐实**（同一个变异，两个版本）：

    | | 恒真探针的结论 |
    |---|---|
    | HEAD 版：在 mac 侧判据脚本里加一处**恒真条件** | ⚠⚠⚨ **rc=0**（「✓ 判据非恒真」照样打出来 ⇒ **假绿**）|
    | 本批版：**同一个**变异 | **rc=1**（指名道姓报出 `macos/scripts/catalog-check.sh:64 if 的条件是恒真/恒假：true`）|

  - ⚠⚠⚨ **顺带量出来的第二个洞**：`render-harness/run.sh` 在**子目录**里
    ⇒ `os.listdir`（顶层）**够不着** ⇒ 它上面的 4 处 if 条件也不被查；
  - ⚠⚠⚨ **第三点（先量后改）**：用探针**自己的判定函数**把那 12 个脚本套一遍
    ⇒ **59 处 if 条件、0 处会被判红** ⇒ ⇒ 扩范围**不会**立刻假红
    ⇒ ⇒ 「扩范围」是**净收益**，不是「搬出一堆新债」；
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    - 范围扩成**两个目录**（`sh_scope`）⇒ mac 侧目录从**仓库根**算
      （`os.path.dirname(os.path.abspath(root))` ⇒ ⚠ 必须用**绝对路径**
      ⇒ `root` 可能是相对路径 `.` ⇒ `dirname('.')` 是**空串** ⇒ 目录会找错）；
    - **递归**收 `.sh`（`os.walk`）⇒ 子目录里的 `render-harness/run.sh` 也被扫
      ⇒ ⚠ deepin 侧**没有**子目录 `.sh` ⇒ 计数不变（18）⇒ **两平台口径对称**；
    - **判定逻辑只有一份**：两个平台走**同一个循环、同一个函数**
      ⇒ 抽出 `scan_shell_file(path, label)` ⇒ ⚠ 这样「**四个实扫点**」那条门
      （恰好 4 处）**不用改** ⇒ 口径零漂移；
    - 范围基线从 **3 行扩到 4 行** ⇒ 值 **4 / 18 / 12 / 5**；
    - 成功消息把范围**拆开说**（`shell 30（deepin 18 + macos 12）`）；
  - **落门 / 判据**：
    - **新增 6 条**（批 CZ 独立段）：
      ① 「mac 侧判据脚本目录**必须在**」（整行锚定）
      ② 「shell 侧范围**必须同时含两个平台**」（整行锚定）
      ③ 「shell 侧判定**必须是共用函数**」（整行锚定 ⇒ 口径零漂移）
      ④ 「两个平台**必须真的走那个共用函数**」（整行锚定）
      ⑤ 「扫描范围**口径序**必须在」（整行锚定 ⇒ fail closed）
      ⑥ 「范围基线里 **mac 侧的判据脚本数必须恰好是 12**」（整行锚定
      ⇒ 这个数字**记两遍** ⇒ 改任意一边 ⇒ 另一边对不上 ⇒ **红**）
      ⇒ ⚠⚠⚨ 5 条 `arch_need_count` 的正则**从真实行现抽构造**
      ⇒ ⚠ **引号位置写 `.`**（批 BL 约定）；
    - **原地替换 5 处**（批 BM 不增行）：① 范围基线那条门 **3 → 4 行**
      ② `ARCH_ANY_FAIL=1` **49 → 50** ③ `ARCH_FAIL=0` **50 → 51**
      ⇒ 段级 trailer **49 → 50** ④ 门项条数第三处 **1050 → 1056**；
    - **同步**：门项总数基线 **1050 → 1056** ⇒ ⚠⚠⚨ **三处同改**；
      盘点登记册 **21 行不变**；豁免表 **14 条不变**；
  - ⚠⚠⚨ **负控 8/8 真红**：
    - **N1（行为级 · 对照实验）**：在 mac 侧判据脚本里加一处**恒真条件**
      ⇒ ⚠⚠⚨ **HEAD 版（整树 `git archive HEAD`）⇒ 探针 rc=0**（假绿）
      ⇒ **本批版 ⇒ rc=1** ⇒ ⇒ **两头都有证据**；
    - **N2** 范围里去掉 mac 侧那一项 ⇒ **恰好 1 条**门红 **且**探针红；
    - **N3** mac 侧目录算错 ⇒ **恰好 1 条**门红 **且**探针红；
    - **N4** 共用函数不被调（mac 侧不被扫）⇒ **恰好 1 条**门红
      ⇒ ⚠⚠⚨ **探针仍绿**（恒真条件看不见）⇒ ⇒ **假绿复现** ⇒ 门④抓住；
    - **N5** 口径序被改 ⇒ **恰好 1 条**门红 **且**探针红（fail closed）；
    - **N6** 基线里 mac 侧那行被改小 ⇒ **恰好 1 条**门红 **且**探针红；
    - **N7** 共用函数的**定义形态**被改 ⇒ **恰好 1 条**门红
      ⇒ ⚠ 探针**仍绿**（行为没变）⇒ ⇒ **只有门能抓住**；
    - **N8** 递归下钻被摘 ⇒ **探针红**（mac 侧少扫 1 个 ⇒ 11 ≠ 12）；
  - ⚠ **已知边界（如实记着，不粉饰）**：
    - ⚠ **`.py` 口径仍只看顶层** ⇒ 子目录里的 `.py` 不在范围
      （⚠ 当前两个平台**没有**子目录 `.py` ⇒ 影响实测为零）；
    - ⚠ **Swift 判据（`macos/Tests/*.swift`）仍不在探针范围**
      （条件抽取口径不同 ⇒ 要另立一条）；
    - ⚠ 「条件合法但恒真」静态分析抓不到 ⇒ 需变异测试 ⇒ 本批不动；
    - ⚠ 范围基线里的数字可被**协同改掉** ⇒ ⚠ 真正的防线是**门 ②**；
    - ⚠ **恒真探针由 `ci.sh` 第 15 步跑**（不在接线门里）
      ⇒ 接线门只保证「探针的**口径**没被改弱」；
    - ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）；
  - **数字**：门项物理行数 **1050 → 1056**（+6）、执行次数 **1053 → 1059**（+6）、
    门项总数基线 **1050 → 1056**（**三处**同步）；段级 trailer **49 → 50**；
    整行 `exit 1`（判据层）**3 不变**；`ARCH_ANY_FAIL=1` = **50**、
    `ARCH_FAIL=0` = **51**；⚠ **恒真探针**：判定层 396 条判据不变、
    shell 与 python **673 → 744** 个 if 条件（**+71**）、断言实参 99 条不变；
    ⚠ **扫描范围**：判定层 4 / shell **18 → 30**（deepin 18 + macos **12**）/
    python 5；范围基线 **3 行 → 4 行**（4 / 18 / **12** / 5）；
    盘点 **21 组 / 72 处不变**；豁免表 **14 条不变**；接线门 **1059** 项全绿、
    审计器硬门与报告模式 **rc=0**（门项 1056/1056 对基线）、恒真探针 **rc=0**、
    孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 8/8 真红**；累计 **892/892**。

- **批 DA（2026-10-22）· 「恒真」判定不许把 shell 的**惯用无限循环**当成判据被掏空**（恒真判定只对 `if`/`elif` 生效）
  - **起因（实测坐实 + 反向对照实验，不是推演）**：
    - 恒真探针（批 BF/BJ 立的「判据不许被掏空成恒真」）把 shell 条件的
      「恒真/恒假」判定**一刀切**地套在**所有**条件上
      ⇒ `while :; do` / `while true; do`（**shell 的惯用无限循环**）
      也被报成「if 的条件是恒真/恒假」⇒ **CI 假红**；
    - ⚠⚠⚨ **实测坐实（同一个变异，两个版本）**：
      | | 恒真探针的结论 |
      |---|---|
      | HEAD 版：在**范围内**的判据脚本里加一处 `while :; do` | ⚠⚠⚨ **rc=1**（报 `scripts/ci-orphan-probe.sh:39 if 的条件是恒真/恒假：:` ⇒ **假红**）|
      | 本批版：**同一个**变异 | **rc=0**（惯用无限循环被放过）|
    - ⚠⚠⚨ **为什么「假红」比「假绿」更坏**（批 BS 纪律）：假绿是承诺**悄悄消失**；
      假红是**逼人把承诺改弱**（人为了让 CI 变绿，会把 `while :; do` 改成怪写法
      来「求绿」⇒ 判据层被迫写出**更糟**的代码）；
    - ⚠ 全仓唯一的 `while :; do` 现在在 `macos/build.sh:236`（**不在**探针范围内）
      ⇒ 假红目前是**潜在**的 ⇒ 但只要有人往**范围内**脚本里写这个极常见惯用法
      就会**当场假红** ⇒ 属于「迟早会踩」的坑；
    - ⚠⚠⚨ **反向护栏也要在**：`if :` / `if true` / `if false` 是**真掏空**
      （`false` ⇒ 体永不执行）⇒ **仍要判红** ⇒ 本批**不许**变成「整体放水」。
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    ① `shell_if_conds()` 返回值带上**种类**（`if` / `while`）；
    ② 恒真/恒假判定**只对 `if`/`elif`** 生效 ⇒ `while` / `until` 放过；
    ③ 判定抽成 `shell_tautology_reason(kind, cond)` ⇒ **自检与实扫同一条路径**；
    ④ 扫描拆出 `scan_shell_text(text, label)`（**文本入口**）⇒ 自检能拿合成样例
    走**同一条**扫描 ⇒ 「while 不判 / if 判」由**探针自己**证明有牙；
    ⑤ `scan_shell_file()` 变**薄封装** ⇒ ⚠ 批 CZ 那两条门**不用改**；
    ⑥ 成功消息改成「**747 个条件**都非恒真（⚠ while/until 的惯用无限循环按批 DA
    规矩不判恒真）」⇒ 说明文字必须与实际行为一致（批 BA/BB 纪律）。
  - **落门 / 判据**：
    - **新增 18 条**（批 DA 独立段，全部**整行锚定**）：判定入口 /
      「恒真判定**只对 `if`/`elif`** 生效」/ 实扫走统一入口 / 自检走同一函数 /
      四个关键字各一条 / 种类映射 / 提取带上种类 / 实扫解包出种类 /
      文本入口扫描函数 / 文件入口真的交给它 /
      自检样例四条（`if` 家族该判红的 2 条 + `while` 家族**不该**判红的 2 条
      + 判定级正反各 1 条）⇒ ⚠ **只测一边 ⇒ 判反了也能过**；
    - **原地替换 5 处**（批 BM 不增行）：`ARCH_ANY_FAIL=1` **50 → 51**、
      `ARCH_FAIL=0` **51 → 52**、门项条数第三处 **1056 → 1074**，
      以及两条说明文字里的数字；
    - **同步**：门项总数基线 **1056 → 1074** ⇒ ⚠⚠⚨ **三处同改**。
  - ⚠⚠⚨ **负控 12/12 真红**：
    - **N1（反向对照 · 核心）** 只注入 `while :; do`
      ⇒ ⚠⚠⚨ **HEAD 版探针 rc=1（假红）** ⇒ **本批版 rc=0**
      ⇒ 坐实「假红被收掉」且**不是**靠「整体不判」实现的；
    - **N2** 只注入 `if :` ⇒ 本批版**仍红**；
    - **N3** 只注入 `if true` ⇒ 本批版**仍红**；
    - **N4** 只注入 `while true` ⇒ 本批版**绿**；
    - **N5** 只注入 `if false` ⇒ 本批版**仍红**（恒假也是掏空）；
    - **N6** 放过 `while` 的同时**范围基线仍被核对**（不许借放水把范围也放掉）；
    - **N7** 种类映射**写反** ⇒ **恰好 1 条**门红且指名道姓；
    - **N8** 删掉「恒真只对 if 生效」的闸门 ⇒ 门红；
    - **N9** 提取时**不带种类** ⇒ 门红；
    - **N10** 删掉 `until` 关键字 ⇒ 门红；
    - **N11** 把自检样例的期望改错 ⇒ **探针自检当场红**；
    - **N12** 还原后与 harness 启动时的 `git diff` **逐字节相同**（洁净度）。
  - ⚠ **已知边界（如实记着，不粉饰）**：
    - ⚠ **`until true`（体永不执行）也被放过**（本批不判）
      ⇒ 批 BJ ③「体永不执行 ⇒ 断言永不跑」仍靠**人读**兜着；
    - ⚠ **捷径判定（`|| true` / `&& false`）对 `while` 仍然生效**
      ⇒ `while cmd || true` 其实是**死循环**（不是掏空）⇒ 本批**没收**这一档；
    - ⚠ **Swift 判据**仍不在探针范围（批 CZ 遗留）；
    - ⚠ 恒真探针由 `ci.sh` 第 15 步跑（不在接线门里）
      ⇒ 接线门只保证「探针的**口径**没被改弱」；
    - ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）。
  - **数字**：门项物理行数 **1056 → 1074**（+18）、执行次数 **1059 → 1077**（+18）、
    门项总数基线 **1056 → 1074**（**三处**同步）；段级 trailer **50 → 51**；
    整行 `exit 1`（判据层）**3 不变**；`ARCH_ANY_FAIL=1` = **51**、
    `ARCH_FAIL=0` = **52**；⚠ **恒真探针**：判定层 396 条判据不变、
    shell 与 python **744 → 747** 个条件（**+3** = 探针源码自身新增 2 处 `if`
    + 批 DA 段的段末 trailer 在 `ci-wiring.sh` 里新增 1 处 `if`
    ⇒ ⚠ **探针会数到自己的 CI 接线文件** ⇒ **自指**，知情取舍）、
    断言实参 99 条不变；⚠ **扫描范围不变**：判定层 4 / shell 30（deepin 18 +
    macos 12）/ python 5；范围基线 **4 行不变**（4 / 18 / 12 / 5）；
    盘点 **21 组 / 72 处不变**；豁免表 **14 条不变**；接线门 **1077** 项全绿、
    审计器硬门与报告模式 **rc=0**（门项 1074/1074 对基线）、恒真探针 **rc=0**、
    孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 12/12 真红**；累计 **904/904**。

- **批 DB（2026-10-22）· 恒真探针的 shell 范围不许只盖「两个平台的判据脚本目录」**（扩到仓内自有 .sh 的四个口径）
  - **起因（实测坐实 + 反向对照实验，不是推演）**：
    - 恒真探针（批 BF 立的）的 shell 范围 = **两个平台的判据脚本目录**
      ⇒ 仓内自有 .sh 的**其余角落从来没被查过**：
      | 目录 | .sh 数 | if 条件 | 说明 |
      |---|---|---|---|
      | `macos/build.sh` | 1 | 38 | **被 4 条门项盯着**（批 AJ 起）⇒ **门项覆盖面比探针覆盖面宽** |
      | `assets/icon/check-icon.sh` | 1 | 10 | 图标校验脚本（判据脚本） |
      | `linux/scripts/*.sh` | 9 | 53 | 含 `ai-e2e.sh` / `ci-local.sh` 这类判据脚本 |
      | **合计** | **11** | **101** | |
    - ⇒ **同一族洞**（批 CY 的题）：**纪律覆盖面不许比门项覆盖面窄**；
    - ⚠⚠⚨ **实测坐实（同一个注入，两棵树各自自洽 + 各自的探针）**：
      | | 恒真探针的结论 |
      |---|---|
      | 旧版（批 DA，`git archive HEAD` 整树）：在 `macos/build.sh` 里加一处恒真条件 | ⚠⚠⚨ **rc=0**（假绿）|
      | 本批版：**同一个**注入 | **rc=1**（指名道姓报出 `macos/build.sh:<行号> if 的条件是恒真/恒假：true`）|
    - ⚠⚠⚨ **前置依赖（批 DA 收了它，本批才敢扩）**：用**批 DA 之前**的口径量候选范围
      ⇒ **160 处 if、1 处会被判红**（`macos/build.sh:236` 的 `while :; do`）
      ⇒ **不先修假红就扩范围 ⇒ 当场假红**（批 BS：假红逼人把承诺改弱）；
      用**批 DA 之后**的口径量同一范围 ⇒ **0 处判红** ⇒ **扩范围是净收益**。
  - **修法（只动判据层 ⇒ 零产品代码改动）**：
    ① 范围从两个目录扩成**四个口径**：`deepin/scripts`（18）/ `macos/` **整棵树**
    （13 ⇒ **含 build.sh**）/ `assets/`（1）/ `linux/scripts/`（9）；
    ② ⚠ **显式目录清单，不靠排除表** ⇒ `linux/vendor`（第三方）**不进范围**；
    ③ 四个口径**写在同一行**（`sh_scope`）⇒ 改一边就看得出来；
    ④ 四个口径**走同一个循环、同一个判定函数** ⇒ 口径零漂移；
    ⑤ **存在性检查**覆盖四个目录（不存在 ⇒ 明确判红 ⇒ fail closed）；
    ⑥ 对拍字典覆盖四个口径（漏一个 ⇒ 范围检查漏一整片）；
    ⑦ 范围基线从 **4 行扩到 6 行** ⇒ 值 **4 / 18 / 13 / 1 / 9 / 5**；
    ⑧ ⚠ **每个基线数字都记两遍**（基线文件 + 门）⇒ 改任意一边 ⇒ **红**
    （原先只有基线文件记着 ⇒ 「改范围 + 改基线」就能收窄范围）；
    ⑨ 成功消息把范围**拆开说**（`shell 41（deepin 18 + macos 13 + assets 1 + linux 9）`）。
  - **落门 / 判据**：
    - **新增 13 条**（批 DB 独立段，全部**整行锚定**）：三个新目录定义行各一条 /
      **存在性检查**那行 / **遍历循环**那行（批 CX 同款教训）/ **计数字典**那行 /
      对拍字典里 `assets_shell`+`linux_shell` 两行 /
      范围基线的**五个数字各记两遍**；
    - **原地替换 5 处**（批 BM 不增行）：批 CZ 的「mac 侧目录定义」门（→ 仓库根行）/
      「`sh_scope`」门（→ 四口径）/「`SCOPE_KEYS`」门（→ 六口径）/
      「基线里 mac 侧 12」门（→ 13）/ 批 BP 的「基线 4 行」门（→ 6 行）
      ⇒ 五处的**说明文字**同步改；
    - **同步**：门项总数基线 **1074 → 1087** ⇒ ⚠⚠⚨ **三处同改**；段级 trailer **51 → 52**。
  - ⚠⚠⚨ **负控 12/12 真红**：
    - **A 组 · 行为级（两棵树各自自洽 + 各自的探针 + 同一处注入）**：
      - **A1** `macos/build.sh` ⇒ 旧版 rc=0（假绿）/ 本批版 rc=1；
      - **A2** `assets/icon/check-icon.sh` 同款；**A3** `linux/scripts/ci-local.sh` 同款；
      - **A4** `macos/build.sh` 注入 `while :; do` ⇒ 旧版**看不见**（不在范围）/
        本批版**绿**（⇒ 批 DA 的口径在扩范围后仍然生效）；
      - ⇒ ⚠ **为什么用两棵树**：旧版探针的**范围基线是 4 行**、新树是 6 行
        ⇒ 旧探针在新树上会因「基线行数对不上」而红 ⇒ **红因指错**；
    - **B 组 · 门级逐条隔离**：B1 范围里去掉 assets 那项 ⇒ 门红**且**探针红；
      B2 遍历循环只走第一项 ⇒ 门红**且**探针红；
      B3 存在性检查里去掉 linux 目录 ⇒ **门红而探针仍绿**（⇒ 只有门能抓住）；
      B4 对拍字典里 assets 键改成常量 0 ⇒ 门红**且**探针红；
      B5 `mac_dir` 被改窄 ⇒ 门红**且**探针红；
      B6/B7 范围基线里 assets（1→2）/ linux（9→8）被改小 ⇒ 门红**且**探针红；
    - **C1** 还原后与 harness 启动时的 `git diff` **逐字节相同**（洁净度）。
  - ⚠ **已知边界（如实记着，不粉饰）**：
    - ⚠ **`got_scope` 少一个键 ⇒ 探针崩（traceback）而不是「判红」**
      ⇒ 红是真的红，但**诊断是指纹不是解释** ⇒ 由门兜住；
    - ⚠ `linux/vendor`（第三方）**不在范围**（显式目录清单 ⇒ 将来长出 .sh 不会被自动查）；
    - ⚠ **`.py` 口径仍只看 `deepin/scripts/` 顶层**（批 CZ 遗留）
      ⇒ `linux/scripts/bmp2png.py` 不在范围；
    - ⚠ **Swift 判据**仍不在探针范围（批 CZ 遗留）；
    - ⚠ 恒真探针由 `ci.sh` 第 15 步跑（不在接线门里）；
    - ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）。
  - **数字**：门项物理行数 **1074 → 1087**（+13）、执行次数 **1077 → 1090**（+13）、
    门项总数基线 **1074 → 1087**（**三处**同步）；段级 trailer **51 → 52**；
    整行 `exit 1`（判据层）**3 不变**；`ARCH_ANY_FAIL=1` = **52**、
    `ARCH_FAIL=0` = **53**；⚠ **恒真探针**：判定层 396 条判据不变、
    shell 与 python **747 → 849** 个条件（**+102** = 新纳入 11 个 .sh 的 101 处
    + 批 DB 段的段末 trailer 在 `ci-wiring.sh` 里新增 1 处 `if`
    ⇒ ⚠ **探针会数到自己的 CI 接线文件** ⇒ **自指**，知情取舍）、
    断言实参 99 条不变；⚠ **扫描范围**：判定层 4 / shell **30 → 41**（deepin 18 +
    macos **13** + assets **1** + linux **9**）/ python 5；
    范围基线 **4 行 → 6 行**（4 / 18 / **13** / 1 / 9 / 5）；
    盘点 **21 组 / 72 处不变**；豁免表 **14 条不变**；接线门 **1090** 项全绿、
    审计器硬门与报告模式 **rc=0**（门项 1087/1087 对基线）、恒真探针 **rc=0**、
    孤儿探针 **rc=0**、盘点对拍 **rc=0**；
    ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
    ⇒ **如实记录，不粉饰**；**负控 12/12 真红**；累计 **916/916**。

### 批 DC · Swift 判据（`macos/Tests/*.swift`）也不许被掏空（2026-10-22）

**起因（实测坐实 + 反向对照实验）**：恒真探针查的是 **C++ 判定层**
（`check(…)` 的第三个实参）+ shell + python 三个口径，而 **mac 侧的判据脚本是
Swift**（`macos/Tests/*/main.swift`：5 个文件、9265 行、**469 条 `check` 断言**）
⇒ 断言形态是 `check("标签") { …guard… else { throw … } }`
⇒ **判据藏在闭包体里** ⇒ C++ 侧那条口径**够不着**
⇒ ⚠⚠⚨ **那 469 条断言一条都没被查过**（假绿）。

**修法（只动判据层 ⇒ 零产品代码改动）**：
- 新增 **Swift 口径**（`swift_dir` = 仓库根 `macos/Tests`，递归收 `.swift`）；
- 两种掏空形态都要判红：① **闭包里没有失败路径**（`throw` / `try` /
  `fatalError` / `precondition` / `assert`）⇒ 这条断言永远不会失败；
  ② **`if` 条件恒真/恒假或带捷径**（`|| true`）⇒ 复用 `tautology_reason`
  ⇒ **判定只有一份**；
- ⚠ **`try?` 不算失败路径**（它把错误吞掉 ⇒ 实测仓里有 15 处 `try?`）⇒ `(?!\?)` 排除；
- 闭包提取靠**括号/花括号配平**（不用正则猜边界）；注释/字符串剥离是**状态机**
  ⇒ ⚠ **`"""` 多行字符串单独一档**（当成普通字符串 ⇒ 引号状态机跑偏 ⇒ **假红**）；
- 扫描拆成**文本入口 + 文件入口** ⇒ 自检走**同一条**路径 ⇒ 探针自己证明有牙；
- ⚠⚠⚨ **顺带收掉第二个洞**：范围基线原是**纯数字**、靠**行序**对应口径
  ⇒ `python 5` / `swift 5` 撞车 ⇒ 「每个口径都记两遍」立不住
  ⇒ 改成每行 `<口径名> <数字>` ⇒ 口径名/个数/顺序必须与 `SCOPE_KEYS` 完全一致
  ⇒ 否则 **fail closed**（探针当场红）。

**落门 / 判据**：**新增 20 条**（批 DC 独立段，全部整行锚定）+ **原地替换 9 处**
（批 BM 不增行）；⚠⚠⚨ **顺带修了 4 条「说明文字与实际行为不一致」的门**（批 BB 纪律
⇒ 本批自己踩到）；门项总数基线 **1087 → 1107** ⇒ **三处同改**；段级 trailer **52 → 53**。

**负控 26/26 真红**：
- **A 组 · 行为级（两棵树各自自洽 + 各自的探针 + 同一处注入）**：旧版（批 DB 整树）
  在 Swift 判据里加一条**闭包里没有失败路径**的 `check` ⇒ 探针 **rc=0**（假绿）
  ⇒ 本批版**同一个**注入 ⇒ **rc=1**；`if true` / `if false` / `|| true` / 只剩 `try?`
  四档同款；**反向护栏**：闭包里有**真的失败路径** ⇒ 两边都绿。
- **B 组 · 门级逐条隔离**：11 条变异探针源码 + 3 条自检样例 + 3 条范围基线
  ⇒ **每条都是「接线门红且指名道姓」**；其中 **4 条「门红而探针仍绿」**
  ⇒ 如实标为 **只有门能抓住**（探针自己看不出来）。
- **C1** 还原后与 harness 启动时的 `git diff` **逐字节相同**（洁净度）。

**数字**：门项物理行数 **1087 → 1107**（+20）、执行次数 **1090 → 1110**（+20）；
门项总数基线 **1087 → 1107**（**三处**同步）；段级 trailer **52 → 53**；
整行 `exit 1`（判据层）**3 不变**；`ARCH_ANY_FAIL=1` = **53**、`ARCH_FAIL=0` = **54**；
⚠ **恒真探针**：判定层 396 条判据不变、shell 与 python **849 → 875** 个条件
（**+26** = 探针源码自身新增的 Swift 解析函数里的 `if`/`elif` + 批 DC 段末 trailer
在 `ci-wiring.sh` 里新增 1 处 `if` ⇒ ⚠ **探针会数到自己的 CI 接线文件** ⇒ **自指**，
知情取舍）、断言实参 99 条不变；⚠ **Swift 侧**：**469 条断言**（闭包都有失败路径）
+ **144 处 if 条件**都非恒真；⚠ **扫描范围**：判定层 4 / shell 41（deepin 18 +
macos 13 + assets 1 + linux 9）/ python 5 / **swift 5**；范围基线 **6 行 → 7 行**
（4 / 18 / 13 / 1 / 9 / 5 / **5**，且每行带口径名）；盘点 **21 组 / 72 处不变**；
豁免表 **14 条不变**；接线门 **1110** 项全绿、审计器硬门与报告模式 **rc=0**
（门项 1107/1107 对基线）、恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（1 组未验证：本机缺 `appstream-util`）
⇒ **如实记录，不粉饰**；**负控 26/26 真红**；累计 **942/942**。

### 批 DD · 判据层的「判定口径表」不许被悄悄改弱（2026-10-22）

**起因（实测坐实 + 完整枚举）**：恒真探针里有**六张「判定口径表」**——
`KEYWORDS`（哪些词不算标识符，27 档）/ `SHORTCUT`（哪些写法算恒真捷径，10 档）/
`SH_CONST`（shell 恒真字面量，3 档）/ `PY_CONST_IF`（python 恒真条件，4 档）/
`LITERAL_CHAR`（ERE 里哪些字符算字面字符，14 档）/ `SWIFT_FAIL_RE`（Swift 失败路径，
5 档）。⚠⚠⚨ **它们的内容被削弱 ⇒ 没有任何东西会红**：实测把每张表的**每一个分支**
逐个删掉（**78 次削弱**）⇒ **接线门 / 探针 / 审计器「三样全绿」**
= 削弱没人发现 = 承诺悄悄变弱 ⇒ **53 个洞**。

**修法（两腿，互不依赖 ⇒ 改一处必红）**：
- **腿 1 · 内容级门**（12 条）：五张表的**每一行**整行锚定 ⇒ 改一行 ⇒ 那条门红；
  ⚠ 正则一律**从真实行现抽** ⇒ 不手抄；
- **腿 2 · 补自检**（在探针里）：**63 个有效档全部有自检覆盖** ⇒ 改口径 ⇒ 探针自检红。
  ⚠ 关键手法：**一条样例覆盖一整张表**——`KEYWORDS` 的 27 个词用**一条** `cond` 样例
  全列出来；`LITERAL_CHAR` 的 14 个元字符用**一条** `assert_arg` 样例全列出来；
  ⚠ 反过来，**一条里混多档就盖不住** ⇒ `SHORTCUT` / `PY_CONST_IF` **每档单独一条**
  ⇒ `PY_CONST_IF` 新增一个自检类别（走同一条判定路径）。

**落门 / 判据**：**新增 15 条**（批 DD 独立段，全部整行锚定）+ **原地替换 3 处**
（`shortcut` 8→10 / `cond` 6→7 / `check_text` 2→3，说明文字同步改）；
门项总数基线 **1107 → 1122** ⇒ **三处同改**；段级 trailer **52 → 53**。

**负控 26/26 真红**：**A 组 · 两棵树对照**（旧版 = 批 DC 整树）三个代表削弱 ⇒
**旧版探针绿 + 旧版接线门绿（假绿）** ⇒ **本批探针红 + 本批接线门红**；
**B 组 · 逐档削弱**（12 档）⇒ 每档 **门红 且 探针自检红**；
**C 组 · 门级隔离**（8 条）⇒ 接线门红且指名道姓；
**D 组 · 洁净度** ⇒ 还原后与 harness 启动时的 `git diff` **逐字节相同**。

**数字**：门项物理行数 **1107 → 1122**（+15）、执行次数 **1110 → 1125**（+15）；
门项总数基线 **1107 → 1122**（**三处**同步）；段级 trailer **52 → 53**；
整行 `exit 1`（判据层）**3 不变**；`ARCH_ANY_FAIL=1` = **54**、`ARCH_FAIL=0` = **55**；
⚠ **恒真探针**：判定层 396 条判据不变、shell 与 python **875 → 876** 个条件
（**+1** = 批 DD 段末 trailer 在 `ci-wiring.sh` 里新增 1 处 `if` ⇒ ⚠ **探针会数到
自己的 CI 接线文件** ⇒ **自指**，知情取舍）、断言实参 99 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**
（判定层 4 / shell 41 / python 5 / swift 5）；范围基线 **7 行带口径名不变**；
盘点 **21 组 / 72 处不变**；豁免表 **14 条不变**；接线门 **1125** 项全绿、
审计器硬门与报告模式 **rc=0**（门项 1122/1122 对基线）、恒真探针 **rc=0**、
孤儿探针 **rc=0**、盘点对拍 **rc=0**；⚠ `ci.sh` **15/15 步跑完**但 **rc=3**
（1 组未验证：本机缺 `appstream-util`）⇒ **如实记录，不粉饰**；
**负控 26/26 真红**；累计 **968/968**。

---

## 批 DE · mac 侧判据脚本不许游离 / 失败计数不许被摘掉

**起因（实测坐实，不是推演）**

- **失败计数被摘掉 ⇒ 假绿**：全仓「报错 + 失败计数」形态的**判据脚本 7 个**，
  配对门只罩住 **2 个** ⇒ **5 个未罩住**。
  `assets/icon/check-icon.sh` 的失败助手是**报错与计数同行**
  （`bad() { echo "  ✗ $1"; fail=$((fail + 1)); }`）
  ⇒ 摘掉计数点 ⇒ 末尾 `[[ $fail -eq 0 ]]` **恒真** ⇒ **恒 exit 0**。
  同款形态还有 mac 侧 **4 个 nc8x 负控脚本**。
- **mac 侧判据脚本可以整组游离**：孤儿探针的范围**只有 `deepin/scripts/`**
  ⇒ `macos/scripts/` 里那 **12 个判据脚本**从来没被查过
  ⇒ 有人把 `macos/build.sh` 里对某个判据脚本的**调用**摘掉 ⇒ **没有任何门会说一个字**。
  ⚠ 实测坐实：`nc88…nc91` **4 个负控脚本全仓无人调用**
  ⇒ 这 4 组「判据坏了会红」的负控**从来没跑过**。

**关键口径坑（实测；直接扩范围会假红）**

mac 构建的调用形态是**裸可执行**（`if "$DIR/scripts/x.sh"; then`），
**不是** `sh x.sh` ⇒ 孤儿探针现口径**认不出** ⇒ 直接扩范围会**假红**。
⇒ 本批给 mac 侧**一份自己的调用点口径**，两份口径都**整行钉住**。
⚠⚠⚨ **而且必须排除「可执行性守卫」**（`if [ -x "$DIR/scripts/x.sh" ]; then`）——
守卫**不是调用** ⇒ 若算成调用 ⇒ 有人把真调用删掉、只留守卫 ⇒ 探针仍判「可达」⇒ **假绿**
⇒ 口径：**引号路径之后到行尾不得出现 `]`**。

**落门 / 判据**：**新增 31 条**（批 DE 独立段）+ **原地替换 9 处**
（含**修掉两处「说明文字与实际行为不一致」**）；
门项总数基线 **1122 → 1153** ⇒ ⚠⚠⚨ **三处同改**；段级 trailer **53 → 54**。

**负控 28/28 真红**：**A 组 · 两棵树对照**
（HEAD 版探针/接线门**绿** = 假绿坐实 ⇒ 本批版**红**）、
**B 组 · 腿 1**（5 条）、**C 组 · 腿 2**（15 条，含 1 条「探针仍绿 ⇒ 只有门能抓住」）、
**D 组 · 洁净度**（4 条）。

**数字**：门项物理行数 **1122 → 1153**、执行次数 **1125 → 1156**；
`ARCH_ANY_FAIL=1` = **55**、`ARCH_FAIL=0` = **56**；
孤儿探针断言脚本 deepin **18** + macos **12**；白名单 **4 → 10**；
接线门 **1156** 项全绿、审计器 rc=0、恒真探针 rc=0、孤儿探针 rc=0、盘点对拍 rc=0；
⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 28/28 真红**；累计 **996/996**。

---

## 批 DF · 恒真探针的「条件抽取器」不许被掏空

**起因（实测坐实 + 对照实验，不是推演）**

恒真探针里有两个**条件抽取器**，它们决定「哪些条件会被拿去判恒真」：
`extract_check_conds`（C++ 判定层，抽 `check(...)` 的**第三个实参**）与
`_shell_cond_at`（shell 侧，抽每个 `if` 的条件文本）。
⚠ **两个都是零门**；且 `extract_check_conds` **连自检都覆盖不到** ——
自检的 `cond` 那一档喂的是**裸条件串** ⇒ **压根不经过抽取器**。

⇒ **实测**：把 `if len(args) >= 3` 改成 `>= 99` ⇒
判定层 **396 条判据 ⇒ 0 条**（探针照样打印「✓ 判据非恒真」），
而**接线门 rc=0 / 探针 rc=0 / 审计器 rc=0** ⇒ ⚠⚠⚨ **三样全绿** ⇒ **假绿坐实**。

**修法（两腿，互不依赖 ⇒ 改一边必红）**

- **腿 1 · 内容级门 14 条**：C++ 侧 5 条（含**调用点**门：批 CX 同款教训
  「常量在、但扫描时不判」⇒ 定义了不用 ⇒ 等于没定义）+ shell 侧 3 条 + 自检侧 6 条；
  ⚠ 门项正则**程序化生成** ⇒ 不手抄 ⇒ 零漂移。
- **腿 2 · 补自检（新增自检档 `cpp_e2e`）**：样例**必须经过 `extract_check_conds`**
  ⇒ 抽取器被掏空 ⇒ **自检当场红**；⚠ 同时含「该判红」与「不该判红」。

**落门 / 判据**：**新增 14 条**（批 DF 独立段）；
门项总数基线 **1153 → 1167** ⇒ ⚠⚠⚨ **三处同改**；段级 trailer **54 → 55**。

**负控 28/28 真红**：A 组两棵树对照（HEAD 探针**绿** = 假绿坐实 ⇒ 本批**红**）、
B 组内容门逐条隔离 8 条（含 2 条「探针**仍绿** ⇒ 只有门能抓住」）、
C 组门级隔离 4 条、D 组洁净度 4 条。

**数字**：门项物理行数 **1153 → 1167**、执行次数 **1156 → 1170**；
恒真探针 shell+python **881 → 882** 个条件；判定层 396 不变；盘点 21 组 / 72 处不变；
孤儿探针 30 个断言脚本 / 白名单 10 条不变；
接线门 **1170** 项全绿、审计器 rc=0、恒真探针 rc=0、孤儿探针 rc=0、盘点对拍 rc=0；
⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 28/28 真红**；累计 **1024/1024**。

**已知边界**：真实语料上的「抽取覆盖率」**没有基线钉住**（实测 `check(` 出现 397 次 vs
抽出 396 条 ⇒ 差的 1 处是**注释里**的提及 ⇒ 严格交叉校验会**假红**⇒ 本批**不做**判据数基线；
且判据数会随产品代码变动 ⇒ 钉它与「判据层不随产品代码变动」相悖
⇒ 抽取器本身由「**内容门 + 合成自检**」保证 ⇒ **零维护成本**）。

---

## 批 DG · assets 侧判据脚本不许游离（图标那一套真的进 CI）

**起因（实测坐实，不是推演）**

`assets/icon/` 下有**两个判据脚本**：`check-icon.sh`（图标一致性验收）与
`make-icons.py --check`（产物与母版一致性的**只校验**模式）。
⚠⚠⚨ **实测坐实：它们不在任何 CI 里** ⇒ 它们的断言**从来没人执行** ⇒
有人改了图标体系、忘了重跑产物 ⇒ **没有任何门会说一个字**。

⚠ **与 mac 侧那 6 条白名单不同款**：那两个要 macOS + Swift 工具链 ⇒ 本机不可验 ⇒
只能「只登记」；而这两个**本机可跑可验**（Pillow 在、产物入库）⇒ **真的接进 CI**。

**修法（两腿）**

- **腿 1 · 接进 CI（`ci.sh` 新增第 15 步 ⇒ 步数 15 → 16）**：
  ⚠⚠⚨ **工具缺席 ⇒ 未验证（专属码 3）** —— 这两个都要 Pillow ⇒ 缺席时
  `check-icon.sh` 会把「PIL-缺」当成「母版不合法」⇒ **把「工具没装」说成「图标不一致」**
  ⇒ 码值语义被顶替 ⇒ 先探工具 ⇒ 缺席 ⇒ `skip++` ⇒ 末尾 `exit 3`。
- **腿 2 · 孤儿探针扩到第三个平台 `assets`**：范围 / 入口 / 调用口径 / 路径前缀**各一份**；
  ⚠ assets 侧**没有自己的 CI** ⇒ 入口就是 deepin 的 `ci.sh` ⇒
  ⚠ **入口共用 ≠ 口径共用**（assets 只认 `/assets/` 下的路径）⇒ 分平台纪律没被破坏。

**落门 / 判据**：**新增 13 条**（批 DG 独立段）；
门项总数基线 **1167 → 1180** ⇒ ⚠⚠⚨ **三处同改**；段级 trailer **56 → 57**。

**负控 28/28 真红**：A 组两棵树对照（HEAD 树 `ci.sh` 里**零** assets 图标调用
⇒ 判据层全绿 = **假绿坐实**）、B 组内容门逐条隔离 13 条、C 组门级隔离 6 条、D 组洁净度 5 条。

**数字**：门项物理行数 **1167 → 1180**、执行次数 **1170 → 1183**；
恒真探针 shell+python **882 → 886** 个条件；判定层 396 不变；
盘点 21 组 / **72 → 73 处**；孤儿探针 **30 → 32** 个断言脚本（+assets 2）、白名单 10 条不变；
ci.sh 步数 15 → **16**、失败上报 36 → **38**、未验证计数点 5 → **6**；
接线门 **1183** 项全绿、审计器 rc=0（**1180/1180**、**0 盲区**）、恒真探针 rc=0、
孤儿探针 rc=0、盘点对拍 rc=0；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 28/28 真红**；累计 **1052/1052**。

**已知边界**：`make-icons.py` 的**生成**路径不在 CI 里（只接了 `--check`）；
恒真探针的 python 范围仍不含 `make-icons.py`（本批未扩范围）；
Pillow 缺席 ⇒ 整组 SKIP（保守口径，但**如实报未验证**并让 CI 末尾 rc=3）。

---

## 批 DH · 判据脚本的「判定口径常量」不许被掏空

**起因（实测坐实，不是推演）**

判据脚本里有一类东西决定「**什么算违规**」—— 散值口径、四语言清单、`.arg(数字)`。
⚠ 逐个做**变异实测** ⇒ 三个被改弱后 ⚠⚠⚨ **接线门 rc=0 + 审计器 rc=0**
（两套判据层全绿）⇒ **假绿坐实**：

- `D2_PATTERN`（`ci-d2.sh`）⇒ 改弱 ⇒「散值即缺陷」**彻底消失**；
- `D_ARG_PATTERN`（`ci-d2.sh`）⇒ 改弱 ⇒「`Q_ARG` 里的数字也是散值」**消失**；
- `EXPECTED`（`ci-docs-lang-probe.sh`）⇒ 少 `ja` ⇒「四种语言都要真跑」**悄悄变弱**。

⚠⚠⚨ **为什么三套机制都抓不到**：恒真探针盯「条件本身是不是恒真」（这些是
「条件**匹配什么**」）；孤儿探针盯「脚本在不在 CI 里」（脚本在）；审计器审
「门项有没有命中 0 次」（被改弱的**不是门项**）⇒ **三个都绿**。

**修法**：给这三个口径**逐字钉住**（整行锚定）⇒ 改一个字就红；
门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条回验命中数 == 1。

**落门 / 判据**：**新增 3 条**（批 DH 独立段）；
门项总数基线 **1180 → 1183** ⇒ ⚠⚠⚨ **三处同改**；段级 trailer **57 → 58**。

**负控 12/12 真红**：A 组两棵树对照（HEAD 树改弱 `D2_PATTERN`
⇒ 判据层全套全绿 = **假绿坐实** ⇒ 本批树同一变异 ⇒ 红且指名道姓）、
B 组内容门逐条隔离 3 条、C 组门级隔离 4 条、D 组洁净度 3 条。

**数字**：门项物理行数 **1180 → 1183**、执行次数 **1183 → 1186**；
恒真探针 shell+python **886 → 887** 个条件；判定层 396 不变；
盘点 21 组 / 73 处不变；孤儿探针 32 个断言脚本 / 白名单 10 条不变；
接线门 **1186** 项全绿、审计器 rc=0（**1183/1183**）、恒真探针 rc=0、
孤儿探针 rc=0、盘点对拍 rc=0；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 12/12 真红**；累计 **1064/1064**。

**已知边界**：本批只收了**已实测坐实**的三个口径 ⇒「新增口径却忘了加门」这一类
**抓不到** ⇒ 下一步把「口径表枚举器」搬进仓内常驻。

---

## 批 DI · 判据层的「阈值 / 抽取口径」不许被掏空

**起因（实测坐实，不是推演）**

判据脚本里有两类东西决定「**判据有多松**」：
**阈值 / 上限**（`D2_COUNT=0` ⇒ 改成 5 ⇒ ≤5 处散值就被放过）与
**抽取口径**（`s/^panelValid=//p` ⇒ `s/^panel//p` ⇒ 抽到 `Valid=1`）。
⚠ 逐个做**变异实测** ⇒ 四个被改弱后 ⚠⚠⚨ **接线门 rc=0 + 审计器 rc=0**
（两套判据层全绿）⇒ **假绿坐实**。

⚠⚠⚨ **关键区分（负控逼出来的）**：抽取口径被改弱后**那个探针脚本自己**红不红
必须**实测** —— `screenRect` / `appAlive` **红**（有格式校验 ⇒ 有牙，牙在 CI 步骤里）；
`panelValid` / `validated` / `iconMissing` **绿**（抽错 ⇒ 值非空 ⇒ 检查通过 ⇒
断言被跳过）⇒ ⚠⚠⚨ **真洞** ⇒ ⇒ **「接线门绿」本身不能作为「没洞」的证据**。

**修法**：四个口径**逐字钉住**（整行锚定）⇒ 改一个字就红；
门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条回验命中数 == 1。

**落门 / 判据**：**新增 4 条**（批 DI 独立段）；
门项总数基线 **1183 → 1187** ⇒ ⚠⚠⚨ **三处同改**；段级 trailer **58 → 59**。

**负控 13/13 真红**：A 组两棵树对照（HEAD 树把散值上限放宽 ⇒
判据层全绿 = **假绿坐实** ⇒ 本批树同一变异 ⇒ 红）、B 组内容门逐条隔离 4 条、
C 组门级隔离 4 条、D 组洁净度 3 条。

**数字**：门项物理行数 **1183 → 1187**、执行次数 **1186 → 1190**；
恒真探针 shell+python **887 → 888** 个条件；判定层 396 不变；
盘点 21 组 / 73 处不变；孤儿探针 32 个断言脚本 / 白名单 10 条不变；
接线门 **1190** 项全绿、审计器 rc=0（**1187/1187**）、恒真探针 rc=0、
孤儿探针 rc=0、盘点对拍 rc=0；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 13/13 真红**；累计 **1077/1077**。

**已知边界**：本批只把口径**钉住**（接线门层有牙）⇒ 治本的第二步
「给那三处抽取值补**格式校验**」留到下一批 ⇒ 在那之前「抽取口径被改弱 ⇒
**探针脚本自己也绿**」这一类**只有接线门能抓住**。
另：「口径表枚举器」候选经实测后**降级**（机械判定标准实测命中 **237 条**，
绝大多数是路径常量 ⇒ 登记册不可维护 ⇒ 暂不做）。
## 批 DJ · 判据脚本的「抽取值」不许被改弱到「静默失效」

**起因（实测坐实，不是推演）**

批 DI 把「**抽取口径**」逐字钉住了（接线门层有牙），并在「已知边界」里
记下治本第二步：**给那三处抽取值补格式校验，让探针脚本自己也有牙**。
⇒ 本批就是那一步。

⚠⚠⚨ **批 DI 已经把洞的形状测出来了**（本批据此动手，不是推演）：
`panelValid` → 抽到 `Valid=1` ⇒ 非空检查通过 ⇒
**面板几何那一整段断言被静默跳过**；
`iconMissing` → 抽到 `Missing=0` ⇒ 非空通过 ⇒ 在**无图标主题**的离屏环境里
那条断言**根本不触发**；
`validated` → 抽到 `ated=…` ⇒ 非空通过 ⇒
「每个废弃别名都要在校验表里」**逐条比的都是错值**。
⚠⚠⚨ **关键点**：三处抽到的都是「**前缀残留**」⇒ **全都含 `=`** ⇒
只要格式正则的字符类**排除 `=`** ⇒ 它们一律被抓。

**修法（治本）**：`panelValid` ⇒ `^[01]$`；`iconMissing` ⇒ `^[0-9]+$`；
`validated` ⇒ `^[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*$`。
⚠ **`validated` 的校验必须在「引擎太老 ⇒ SKIP」之后** ⇒ 否则老引擎那条路径会被
**误判红** ⇒ SKIP 语义被破坏。
⚠ **新增报错文案避开盘点关键词** ⇒ 否则「未验证出口盘点」登记册对不上 ⇒ **假红**
⇒ 本批用「**判定失效**」「**没人知道**」「**比的都是错值**」措辞。

**落门 / 判据**：**新增 3 条**内容级门（整行锚定那三行校验 ⇒ 被删/被改弱 ⇒ 接线门红）；
门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条自检（命中 1 次 + 整行锚定 + 无无界通配）；
原地替换 **6 处**（platform 断言清单 22 → 24、platform 失败上报 24 → 26、
agent 断言清单 11 → 12、agent 失败上报 13 → 14、
`ARCH_ANY_FAIL=1` 59 → 60、`ARCH_FAIL=0` 60 → 61、门项条数 1187 → 1190）；
门项总数基线 **1187 → 1190** ⇒ ⚠⚠⚨ **三处同改**。

**负控 22/22 真红**：⚠⚠⚨ **A 组两棵树对照 + 脚本层对照（本批核心）** ——
⚠ **判据的关键（第一版写反了，被自己的负控抓住）**：批 DI 已把口径钉住 ⇒
口径变异在**两棵树上都让接线门红**（那是批 DI 的成果，**不是**本批的对照组）⇒
⇒ 真正的区分点是「**探针脚本自己**」：树 A（HEAD）**绿** = ⚠⚠⚨ **脚本层没牙** ⇒
树 B（本批）**红** = ⚠⚠⚨ **牙补上了**；
B 组内容门隔离 2 条（⚠ 审计器要用 **`--list` 模式**跑 ⇒ 总条数核对**只在 `--list` 模式跑**）、
C 组门级隔离 1 条、D 组洁净度 1 条。

**数字**：门项物理行数 **1187 → 1190**、执行次数 **1190 → 1193**；
恒真探针 shell+python **888 → 892** 个条件（+4 = 三处新 `if` + 段末 trailer 自指）；
判定层 396 不变；盘点 21 组 / 73 处不变；孤儿探针 32 个断言脚本 / 白名单 10 条不变；
接线门 **1193** 项全绿、审计器 rc=0（**1190/1190**）、恒真探针 rc=0、
孤儿探针 rc=0、盘点对拍 rc=0；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 22/22 真红**；累计 **1099/1099**。

**已知边界**：本批收的是「**脚本自己那层牙**」⇒ 口径被改弱 ⇒ 探针脚本**自己**会红
⇒ 但**接线门那层牙是批 DI 给的**（本批没动它）。
⚠ **格式校验只覆盖这三处** ⇒ 别处若还有「**只有非空检查**」的抽取值，
同款洞**依然存在** ⇒ ⚠ **不做「抽取值枚举器」**（机械标准会命中 237 条路径常量
⇒ 登记册不可维护 ⇒ 批 DI 已降级）。
⚠ `ICON_MISSING` 在**有图标主题的真机**上本来就会红 ⇒ 本批记的是**离屏 CI 环境**
里的覆盖面缺口。
## 批 DK · D2 散值豁免表不许被悄悄加宽

**起因（实测坐实，不是推演）**

`ci-d2.sh` 的 `D2_EXEMPT` 豁免表**只自检两件事**：① 每条路径**存在**；
② `fix` 项**命中数 > 0**（归零 = 该删了）。
⇒ ⚠⚠⚨ **`keep` 项的条数与内容完全没人管** ⇒
⚠⚠⚨ **实测坐实**：加宽一条（加一条**存在**的路径）⇒ **11 条 → 12 条** ⇒
**`ci-d2.sh` 自己仍然 rc=0**（还打印「✓ D2 命中 0/0」）⇒ **真洞坐实** ⇒
那个文件从此**整份**被豁免 ⇒ 里面的散值**没人查**。

⚠⚠⚨ **五套机制全都抓不到**：恒真探针盯「条件是不是恒真」；孤儿探针盯
「脚本在不在 CI 里」；审计器审「门项有没有命中 0 次」；盘点盯「未验证出口」；
D2 门自己盯「散值命中数」⇒ 被改弱的**既不是门项、也不是判定逻辑，
是「豁免表本身」** ⇒ 只能**逐条钉住**。

**修法（12 条门：11 条逐条 + 1 条总数）**

- **逐条 11 条**：每条钉住「`路径|模式|`」前缀（**整行锚定**）
  ⇒ 路径被换 / 被删 ⇒ 命中 0 ⇒ 红；
- **总数 1 条**：数「`^[^|]*\|keep\|[^|]*$`」⇒ **恰好 11 处**
  ⇒ ⚠ **两道腿互补**：总数门兜住「**同时删一条又加一条**」；
- ⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条自检
  （命中 1 次 + 整行锚定 + 中段无**无界通配**）；
- ⚠⚠⚨ **踩到的坑**：逐条正则**只锚前缀不锚行尾** ⇒ 审计器的**锚定形态检查**
  判红（rc=8）⇒ 逐条也要锚行尾（理由实测不含 `|` ⇒ 用**有界**通配 `[^|]*`）。

**落门 / 判据**：**新增 12 条**（批 DK 独立段）；
原地替换 3 处（`ARCH_ANY_FAIL=1` 60 → 61、`ARCH_FAIL=0` 61 → 62、
门项条数 1190 → 1202）；门项总数基线 **1190 → 1202** ⇒ ⚠⚠⚨ **三处同改**。

**负控 11/11 真红**：A 组两棵树对照 —— 树 A（HEAD）接线门 / 审计器 /
`ci-d2.sh` **三样全绿** = ⚠⚠⚨ **假绿坐实**（豁免表被加宽而没人知道）；
树 B（本批）接线门**红** = ⚠⚠⚨ **洞被堵住了**；
B 组门级隔离（删一条豁免路径 ⇒ 接线门红 + 审计器（`--list`）红）；
C 组门项条数三处同改；D 组洁净度（**只盯 harness 自己变异过的文件**）。

**数字**：门项物理行数 **1190 → 1202**、执行次数 **1193 → 1205**；
恒真探针 shell+python **892 → 893** 个条件（+1 = 段末 trailer 自指）；
判定层 396 不变；盘点 21 组 / 73 处不变；孤儿探针 32 个断言脚本 / 白名单 10 条不变；
接线门 **1205** 项全绿、审计器 rc=0（**1202/1202**）、恒真探针 rc=0、
孤儿探针 rc=0、盘点对拍 rc=0；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 11/11 真红**；累计 **1109/1109**。

**已知边界**：本批只钉了 `keep` 项的**路径与模式** ⇒ ⚠ **豁免理由（自由文本）**
没被钉 ⇒ 理由被改成误导性文字 ⇒ 门不会红（⚠ 理由写得对不对**机器判不了**
⇒ 批 CJ 同款取舍）；⚠ **同款洞可能还在别处** ⇒ 不做「清单枚举器」
（机械标准会命中 237 条路径常量 ⇒ 登记册不可维护 ⇒ 批 DI 已降级）。

## 批 DL · 审计器的「正则体检覆盖面」不许被悄悄缩小

**起因（实测坐实，不是推演）**：审计器的「门项正则写法体检」（`check_rx_syntax`）
只体检**登记册 `RX_ARG_IDX` 里有的门型** ⇒ 覆盖面 = **那份手写登记册**
⇒ 而那份登记册**全仓零门在盯** ⇒ ⚠⚠⚨ **实测坐实的假绿链**：

| 步骤 | 树 A（HEAD） | 树 B（本批） |
|---|---|---|
| 坏正则（`\d` ⇒ 门永远匹配不到）+ 协同把期望次数改成 0 | 审计器 **rc=5** **红** ⇒ 体检**有牙** | 审计器 **rc=5** **红** ⇒ 牙没被改弱 |
| 再**删登记册里那一行** | ⚠⚠⚨ **审计器 rc=0 + 接线门 rc=0 ⇒ 全绿** ⇒ **假绿坐实** | 审计器 **rc=2** **红** ⇒ 洞被堵住 |

⇒ 而且登记册**已经漂移**：在用门型 15 个、登记册只覆盖 12 个 ⇒
`arch_need_count_pair`（在用 7 条门项 / **14 个**正则实参）**从来没被登记**
⇒ 那 14 个正则**从来没被体检过** ⇒ 旧代码靠「取不到就跳过」把两个
「本来就没有正则参数」的门型也一起跳过 ⇒ ⚠ **「显式没有」与「漏登记」被混为一谈**
⇒ 这是 fail closed 一直做不起来的根因。

**修法（三腿 + 一处自洽）**：① **补齐**登记册（`arch_need_count_pair` ⇒ 值是**元组**
`(1, 2)` ⇒ 登记册从「一个下标」升级为「多个下标」）；② 两个「没有正则参数」的门型
**显式**登记为 `None`；③ **fail closed**（取不到 ⇒ 不许静默跳过 ⇒ 审计器 **rc=2 盲区**）；
④ **两份登记册自洽自查**（门型清单 vs 登记册键集合 ⇒ 双向 ⇒ 漏登记 ⇒ **rc=9** ⇒ 漂移即红）。
⚠ **rc 语义只增不改**：既有码值一个没动，只补语义。

**落门 / 判据**：**新增 8 条**（批 DL 独立段：逐字钉住 登记册定义行 / 配对门登记 /
两个「显式没有」的登记 / fail-closed 判定分支 / 多下标支持 / 下标解析函数 / 自洽自查 /
自洽自查的**调用点**）；原地替换 9 处（门项条数 **1202 → 1210** **三处同改**、
`FAILS.append(9)` 计数 4 → 5、`FAILS.append(2)` 计数 4 → 5、段级 trailer 计数
`ARCH_ANY_FAIL=1` 61 → 62 与 `ARCH_FAIL=0` 62 → 63、rc=2 与 rc=9 的**分诊文案**对齐）；
⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条回验（命中 1 次 + 整行锚定 +
中段无**无界通配** + **真 `grep -oE` 复核**）。

**负控 22/22 真红**：A 组两棵树对照（树 A 删登记册一行 ⇒ 审计器 **rc=0** 假绿坐实；
树 B **rc=2**）；B 组牙没被改弱（坏正则 ⇒ 两棵树都 rc=5）；C 组双重失守
（坏正则 + 删登记册 ⇒ 树 A rc=0 / 树 B rc=2）；D 组门级隔离（换删另一族 ⇒ 指名道姓）；
E 组接线门侧隔离（删 fail-closed 分支 / 多下标改单下标 / 删自洽自查调用点 ⇒
各自红在批 DL 那条门）；F 组门项条数三处同改；G 组洁净度。

**数字**：门项物理行数 **1202 → 1210**、执行次数 **1205 → 1213**；
恒真探针 shell+python **893 → 900** 个条件（+7 = 审计器 5 处 `if` + 段末 trailer 1 处 ⇒
⚠ **自指**，知情取舍）、判定层 396 不变；盘点 21 组 / 73 处不变；
孤儿探针 32 个断言脚本 / 白名单 10 条不变；
接线门 **1213** 项全绿、审计器 rc=0（**1210/1210**）、恒真探针 rc=0、孤儿探针 rc=0、
盘点对拍 rc=0；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 22/22 真红**；累计 **1131/1131**。

**已知边界**：⚠ 配对门**不在**「整行锚定」检查范围内（**语义使然**：前缀式正则要满足
整行锚定就得带 `.*` ⇒ 批 BQ 禁止 ⇒ 靠次数校准 + 逐段配对保证）；⚠ 陈旧登记**只报不红**
（多登记 = 体检更广 = 安全方向 ⇒ 假红比假绿更坏）；⚠ 门项**说明文字**不体检
（机器判不了）；⚠ 登记册与 arity 是**两处口径**（下标指错 ⇒ 体检会扫到别的实参 ⇒
不会静默失效 ⇒ 不单开一批）；⚠ 同款洞可能还在别处 ⇒ **不做「清单枚举器」**
（批 DI 已降级）。

## 批 DM · 审计器的「判定函数」不许被掏空

**起因（实测坐实，不是推演）**：把审计器的判定函数逐个掏空成恒真
（`return []` / `return None`）⇒ 跑审计器与接线门 ⇒ ⚠⚠⚨ **16 个候选里 13 个**：
**审计器 rc=0 + 接线门 rc=0 ⇒ 全绿假绿** ⇒ 那一族门项的**校准静默失效**
⇒ 门被改弱时**没人发现** ⇒ 承诺**悄悄消失**。
只有 3 个被守住：`anchoring_violation`（靠它自己的**自检**）、`check_anchor_scope`
（靠**反向配准**）、`rx_arg_indices`（靠**批 DL 的 fail closed**）——
⚠ **唯一靠「自检」守住的就是 `anchoring_violation`** ⇒ 「自检」是本项目**已验证有效**的机制。

**修法（一条规则挡住整类）**：判定函数（**名字以 `check_` 开头**）的 `return` 表达式里
**必须至少有一个「名字」** ⇒ 返回字面量（`[]` / `None` / `True`）⇒ 就是被掏空 ⇒ **必红**。
⚠ **自动纳入**（`check_` 前缀 ⇒ 零名单维护 ⇒ 新增判定函数自动受管）；
⚠ **嵌套函数也算**（为此把逐段配对里的嵌套 `line_numbers` 改成返回 `(err, res)`）；
⚠ 两个判定函数**改名**以进入口径（`bad_escapes` → `check_bad_escapes`、
`pair_segment_bad` → `check_pair_segment_bad`）；⚠ **自检必须放最前**（批 BI）；
⚠ **fail closed**（解析自己失败 ⇒ 判红）；rc=**2（盲区）**。

**连带修掉两处「工具失败 ⇒ 静默跳过」**（批 CD/CH 纪律）：逐段配对（以前返回 `None`
⇒ 调用方跳过 ⇒ 那一族静默失效）与「切不出函数体 / 切不出步骤正文」
（以前 `return []` ⇒ 整族校准静默消失）⇒ **都改成判红**。

**落门 / 判据**：**新增 9 条**（批 DM 独立段）；原地替换 2 条因改名失准的门
（定义 + 调用点，**说明文字同步**）；原地替换 5 处（门项条数 **1210 → 1219**
**三处同改**、`ARCH_ANY_FAIL=1` 62 → 63、`ARCH_FAIL=0` 63 → 64、
`FAILS.append(2)` 计数 5 → 6）+ 1 处 rc=2 **分诊文案**；
⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条回验（命中 1 次 + 整行锚定 +
中段无**无界通配** + **真 `grep -oE` 复核**）。

**负控 26 真红**：A 组两棵树对照（**13 个**判定函数逐个掏空 ⇒ 树 A **双双全绿**
（假绿坐实）/ 树 B **双双红**）；B 组门级隔离（只掏空 `check_count_gates` ⇒ 指名那一族）；
C 组「工具失败 ⇒ 判红」（注入 grep 失败 ⇒ 树 A 仍全绿 / 树 B 红）；
D 组门项条数三处同改；E 组洁净度。

**数字**：门项物理行数 **1210 → 1219**、执行次数 **1213 → 1222**；
恒真探针 shell+python **900 → 907** 个条件（+7 = 审计器里新增的 `if` 条件 ⇒
⚠ **自指**，知情取舍）、判定层 396 不变；盘点 21 组 / 73 处不变；
孤儿探针 32 个断言脚本 / 白名单 10 条不变；
接线门 **1222** 项全绿、审计器 rc=0（**1219/1219**）、恒真探针 rc=0、孤儿探针 rc=0、
盘点对拍 rc=0；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 26 真红**；累计 **1157**。

**已知边界**：⚠ 规则只抓「返回字面量」这一种掏空形态（`return bad if x else []`
不被抓 ⇒ 但恒真探针能抓 `if False` 那类 ⇒ 两层仍有残余）；⚠ 规则只覆盖**审计器自己**的
`check_*` 函数 ⇒ 其它判据脚本**不在口径内**（**下一批候选**）；⚠ 嵌套函数也算 ⇒
将来写「返回字面量」的合法辅助函数会被红（fail closed 方向）；⚠ 规则不管
「判定体被逐点改弱」（多数这类改动**会被门自身报红** ⇒ 残余风险有限）；
⚠ 判定函数改名 ⇒ 旧名的门会红（**有意** ⇒ 逼着人同步说明文字）。

## 批 DN · 判据脚本的「抽取器 / 自检」不许被静默关掉

**起因（实测坐实，不是推演）**：把**其它**判据脚本的判定函数逐个掏空
（在函数体首行插一句提前 `return`）⇒ 跑该脚本与接线门 ⇒ ⚠⚠⚨ **27 个候选里 3 个**：
**脚本 rc=0 + 接线门 rc=0 ⇒ 全绿假绿** ⇒ 那一族检查**静默失效** ⇒ 没人报警 ⇒
承诺**悄悄消失**。三个真洞：

- `ci-tautology-check.py::python_if_conds`（python 侧条件抽取器）
- `ci-tautology-check.py::heredoc_spans`（heredoc 体抽取器）
- `ci-true-audit.py::selftest_strip_parity`（那道自检**本身**）

⚠⚠⚨ **洞的形状 = 批 DF 同款**：**自检没有一条样例真的经过被测的抽取器** ⇒
抽取器坏了 ⇒ 自检照样绿 ⇒ 那一整片**不被查**而门全绿。

**修法（两腿）**：

- **腿 1 · 两个抽取器补上「自检真的经过它」的两档样例**（批 DF 同款）
  ⇒ 新增 `py_extract` / `heredoc_extract` 两档 ⇒ 每档**两条**样例
  （「该抽到 N 条」+「不该抽到 0 条」⇒ ⚠ 批 BF 纪律：只测一边 ⇒ 判反了也能过）；
- **腿 2 · 审计器新增「自检函数不许被掏空」的跨脚本体检**
  （`check_self_test_funcs`）⇒ 口径三条腿：**自检函数**（名字含 `selftest` /
  `self_test`）**不许有提前 return**；**自检的宿主**（`check_` 前缀**且调用了**
  自检函数）**同样不许**；**一条 return 都没有**也算被掏空
  ⇒ ⚠ **跨脚本** ⇒ **零名单维护** ⇒ 别的判据脚本里的自检自动受管
  ⇒ ⚠ **fail closed**、⚠ **规则自己也被规则保护**。

**连带改掉一处提前 return**：`check_judge_funcs` 原来在 except 分支里提前
`return bad` ⇒ 它是自检的**宿主** ⇒ 按新口径必须**不许提前 return**
⇒ 改成 `try/except/else` ⇒ ⚠ 这一处**不是顺手重构** ⇒ 不改 ⇒ 规则自己先失效。

**落门 / 判据**：**新增 15 条**（批 DN 独立段：8 条盯两个档位的分派行 + 两个抽取器
调用行 + 4 条样例行；7 条盯名字口径常量 + 判定函数定义 + 适用范围判定行 +
名字口径判定行 + 「提前 return」判定行 + 两个调用点）；原地替换 5 处
（门项条数 **1219 → 1234** **三处同改**、`ARCH_ANY_FAIL=1` 63 → 64、
`ARCH_FAIL=0` 64 → 65、`FAILS.append(2)` 计数 6 → 7）+ ⚠ **1 处 rc=2 的分诊文案**（补「**有自检函数被掏空**」⇒ 第 ⑦ 种失败态也落在盲区那一档 ⇒ 不补 ⇒ 排障被带偏 ⇒ 批 DM 当年同款口径）
+ 1 处段级计数说明文字
**顺带订正**（原文「清零 59 处」早已与实际 64/64 不符 ⇒ ⚠ 说明与实际行为不一致
⇒ 假红比假绿更坏）；⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条回验
（命中 1 次 + 整行锚定 + 中段无**无界通配** + **真 `grep -oE` 复核**）。

**负控 11 真红**：A 组 3 个洞逐个（掏空两个抽取器 ⇒ **恒真探针 rc=1**；掏空那道
自检 ⇒ **审计器 rc=2 + 接线门 rc=1** 且指名道姓）；B 组**门级隔离**（把两个抽取器
自检档写成 `got = True` ⇒ ⚠⚠⚨ **探针照样绿**（假绿坐实）⇒ **只有**批 DN 段那两条门红）；
C 组**规则自己被掏空**（「提前 return」判定行改成 `early = []` ⇒ 审计器不再报 ⇒
**只有**那条门红）；D 组**口径被改窄**（名字常量只留 `self_test` ⇒ 那道自检掉出口径
⇒ ⚠⚠⚨ **实测比预想更强**：审计器**照样红**（rc=4 次数失准 ⇒ 那条门钉的是**常量的确切内容**）
⇒ 口径没法被悄悄改窄）；E 组**宿主调用点被摘** ⇒ 审计器红 + 调用点门红；
F 组**门项条数三处同改**（只改三处中的任意一处 ⇒ 红）；G 组**洁净度**（变异文件还原后
与原始字节逐字节相同 + 真仓未被碰过）。

**数字**：门项物理行数 **1219 → 1234**、执行次数 **1222 → 1237**；
恒真探针 shell+python **907 → 919** 个条件（+12 = 审计器里新增的 `if` 条件 ⇒
⚠ **自指**，知情取舍）、判定层 396 不变；盘点 21 组 / 73 处不变；
孤儿探针 32 个断言脚本 / 白名单 10 条不变；
接线门 **1237** 项全绿、审计器 rc=0（**1234/1234**）、恒真探针 rc=0、
孤儿探针 rc=0、盘点对拍 rc=0；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 11 真红**；累计 **1168/1168**。

**已知边界**：⚠ 腿 1 的两档只数「抽到几条」⇒ 「**抽错内容但条数不变**」**不被抓**
⇒ ⚠ 那种改动也让**实扫**判错而**不被报** ⇒ 残余风险有限 ⇒ ⚠ 要彻底堵住得让自检走
**整条实扫路径**（批 DA/DF 口径）⇒ ⚠ **本批不做**（改动面大 ⇒ 引入新错的概率高）
⇒ **不假装已经堵死**；⚠ 腿 1 只覆盖这两个抽取器 ⇒ 别的抽取器**没有**同款自检 ⇒
**不做「抽取值枚举器」**（批 DI 已降级）；⚠ 腿 2 的口径是**名字** ⇒ 自检函数改名到不含
`selftest` / `self_test` ⇒ 自动掉出口径（只能靠别的门发现）；⚠ 腿 2 只抓「提前 return」
与「没有 return」两种掏空形态 ⇒ 「判定体改成恒真」**不被腿 2 抓** ⇒ 但**批 DN 段那几条门**
逐字钉住判定行 ⇒ 残余风险有限；⚠ 腿 2 只覆盖 `deepin/scripts/*.py` ⇒ `linux/` 与 `macos/`
侧**不在口径内**（**下一批候选**）；⚠ 「宿主」靠「函数体里出现自检函数名」判定 ⇒
**间接**调用不被识别（当前仓内无此写法）；⚠ 「不许提前 return」会误伤「合法早退」
（fail closed 方向）；⚠ 探针的 `python_if_conds` 只看顶层 `if` ⇒ 腿 1 的自检档**本身**
不被探针检查到 ⇒ 但**腿 1 的门**逐字钉住了那几行。


## 批 DO · 审计器自己的「失败态上报」不许被静默关掉

**起因（实测坐实，不是推演）**：批 DM 的规则只管 `check_` 前缀**函数**里的 `return`
⇒ **main_body 里的内联判定是一个逃逸口**。实测三步：

| 步骤 | 审计器 | 接线门 |
|---|---|---|
| 基准 | rc=0 | rc=0 |
| 制造一个**真盲区**（从门型登记册摘一条） | **rc=2** | rc=1 |
| ⚠⚠⚨ **真盲区 + 把守卫改成恒假** | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **rc=0** |

⇒ 「**审计器自己有盲区**」这件事可以**被无声地关掉** ⇒ 那类门项**从来没被审**
⇒ 彻底没人知道 ⇒ 承诺**悄悄消失**。

⚠⚠⚨ **洞的形状**：main_body 里的失败态判定是**内联**的 ⇒ **四道机制全都够不着**
（批 DM 只管函数里的 `return`、批 DN 只管自检函数、恒真探针只查**恒真**不查**恒假**、
`ci-wiring.sh` **没有门**钉住那几行）。

**修法（两腿）**：

- **腿 1 · 一条零名单维护的 AST 规则**（`check_fail_guards`）
  ⇒ 每个 `FAILS.append(rc)` **必须有守卫**（最内层 `if` 的条件；或处在 `except` 里
  —— 崩了的兜底）⇒ 没有 ⇒ 那个失败态**恒定触发** ⇒ 必红；
  ⇒ 守卫条件**只许「名字 / 下标」** ⇒ **不许**取反（判定被**反过来**）/ 与或
  （判定被**改窄**）/ 比较 / 调用 / 布尔字面量（判定被**关掉**）
  ⇒ 守卫的职责是「**取出一个判定结果**」⇒ 写成常量或表达式 ⇒ 就是在**改判定**
  ⇒ 必须走门 ⇒ **逼着人同步**；
  ⇒ ⚠ **零名单维护**、⚠ **fail closed**、⚠ **规则自己也被规则保护**；
- **腿 2 · 口径 ③ 与口径 ④**（把「换指向」与「挪走」也挡住）
  ⇒ **口径 ③ · 守卫不许重复** ⇒ 两个收集点用同一个守卫 ⇒ 其中的一个**指错了判定**
  ⇒ 那一类失败**不再上报**而没人知道 ⇒ 必红；
  ⇒ **口径 ④ · 守卫登记册**（**双向红**）⇒ 「用到的守卫」不在册里 ⇒ 新增失败态忘了
  登记；「册里的守卫」没被用到 ⇒ 那个收集点**被挪走 / 删了** ⇒ 红
  ⇒ ⚠ 这一条抓的是「挪进一个**以变量为条件**的少真分支」
  （新守卫**仍是名字** ⇒ ② ③ 都抓不到 ⇒ 只有它抓得住）；
- ⚠⚠⚨ **本批原设计的「腿 2：各 rc 的收集处计数门」⇒ 撤掉**：实测发现**批 CQ 早就有**
  ⇒ ⇒ 本批那几条是**重复门** ⇒ ⇒ **判定逻辑只有一份 ⇒ 不重复加** ⇒ 撤掉
  （那一腿的**牙本来就有**）。

**连带改掉两处「取反的守卫」**（口径 ② 的前提，不是顺手重构）⇒ 改成先算好 missing
变量再守卫 ⇒ 语义等价 ⇒ ⚠ 不改 ⇒ 规则自己先失效。

**落门 / 判据**：**新增 10 条**（批 DO 独立段：6 条盯新规则 + 1 条盯口径 ③ + 3 条盯
口径 ④；⚠ **各 rc 的收集处计数门本来就有**（批 CQ）⇒ **不重复加** ⇒ 本批原设计的
「腿 2」**撤掉**；rc=2 那条**已存在** ⇒ 原地改 7 → 8 ⇒ 并**顺带订正**批 CQ 那条 rc=9
的门（说明写「恰好 4 处」而实际 **5** 处 ⇒ 说明与实际行为不一致））；
原地替换 5 处（门项条数 **1234 → 1244** **三处同改**、`ARCH_ANY_FAIL=1` 64 → 65、
`ARCH_FAIL=0` 65 → 66、`FAILS.append(2)` 计数 7 → 8）+ rc=2 那条门说明**补第 ⑧ 种
失败态**；⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条回验；⚠ **字面单引号写成 `.`**。

**负控 14 真红**：A 组**核心**（真盲区 + 守卫被掏空 ⇒ 审计器 rc=2，指名道姓）；
B 组**掏空形态全抓**（`if False:` / `g.get(...)` / `a and b` / `not x` /
`x == 0` / `if 0:` ⇒ 实测 8/8）；C 组**收集点被删**（rc=9 / rc=4；⚠ rc=4 那次实测到
**自指**：审计器报得出「次数门没配准」但**报不出 rc=4** ⇒ 抓它的是**口径 ④**
（那个守卫没被用到）+ **接线门**的计数门）；
D 组**守卫换指向** ⇒ 口径 ③ 红；E 组**收集点挪进少真分支** ⇒ 口径 ④ 红；
F 组**挪到外层 if** ⇒ **恒定触发 ⇒ 假红**（不是假绿）⇒ 会被立刻发现；
G 组**门项条数三处同改**；H 组**洁净度**。

⚠⚠⚨ **本批 harness 自己踩了三个坑并已修**：① 「有牙自证」按 `find()` 定位 ⇒ 改到了
**新规则 docstring 里的同名串** ⇒ 看起来「没抓到」⇒ 真相是**改错了地方**
⇒ ⚠ **假红比假绿更坏**；② 门项说明文字里写了**字面单引号** ⇒ shell 包裹会破 ⇒
措辞绕开；③ 新代码里的 `return True` / `return False` **撞上**了「全文件恰好 1 处
`return True`」那条门 ⇒ 失准 ⇒ 改成标志变量 ⇒ ⚠ **计数门是别人的承诺 ⇒ 改代码前
必须先看它盯着什么**；④ 恢复备份时**手工改过的文件被覆盖**（`return True` 那处修复
丢了）⇒ 又一次失准 ⇒ ⇒ ⚠ **备份恢复后必须重跑门**。

**数字**：门项物理行数 **1234 → 1244**、执行次数 **1237 → 1247**；
各 rc 的收集处：rc=2 **8**、4 **1**、5 **2**、6 **1**、7 **1**、8 **2**、9 **5**
（合计 **20** 处；⚠ **这些计数门本来就是批 CQ 的**）；**守卫登记册 19** 个守卫；
恒真探针 shell+python **919 → 928** 个条件（+9 ⇒ ⚠ **自指**，知情取舍）、
判定层 396 不变；接线门 **1247** 项全绿、审计器 rc=0（**1244/1244**）；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；**负控 14 真红**；累计 **1182/1182**。

**已知边界**：⚠⚠⚨ **口径 ① 当前触发不到**（现有 20 处收集点全都嵌在某个 `if` 里）⇒
**现在没有牙** ⇒ 面向将来 ⇒ 现在的牙在 ② ③ ④ 三条腿上；⚠ 口径 ② 只管
`FAILS.append` 的守卫 ⇒ **报告模式**的打印点（不设 rc、只给人看）**不在口径内** ⇒
硬门模式不受影响 ⇒ 残余风险有限；⚠ 口径 ② 是**形态**判定不是**语义**判定 ⇒ 守卫是
名字但**那个值被改坏** ⇒ 抓不到 ⇒ 但值来自 `check_` 前缀函数（批 DM 口径管着）；
⚠ **登记册（口径 ④）本身是「名单」** ⇒ 协同编辑（改登记册 + 挪收集点）⇒ 抓不到 ⇒
⚠ **批 CR 同款已知边界**；⚠ **口径 ③** 要求「每个失败态各有自己的判定」⇒ 将来两个
失败态合法共用一个守卫 ⇒ 会被红 ⇒ 有意的；⚠ **腿 1 只管审计器自己** ⇒ **别的判据
脚本**的内联失败态判定仍不在口径内（**下一批候选**）；⚠ 口径 ② 会误伤将来合法的写法
⇒ 有意的（fail closed 方向）；⚠ 口径 ① 允许 `except` 里的收集点无守卫 ⇒ 把
`except` 改成 `except Exception: pass` ⇒ 那条兜底就没了 ⇒ 未被口径覆盖。

## 批 DP · 判据脚本（审计器之外）的「失败态上报」不许被静默关掉

批 DO 把「失败态上报不许被静默关掉」这件事**只管到审计器自己**
⇒ **别的判据脚本**的内联失败态判定仍在口径外（批 DO 台账里写明的已知边界）
⇒ 本批把它**扩出去**。

**⚠⚠⚨ 起因（实测坐实，不是推演）** —— 4 组对照实验（scratch 树复制整个仓根）：

- ⚠⚠⚨ **E1**：`ci-tautology-check.py` 的 **16 处 `bad += 1`** 全改成 `bad += 0`
  ⇒ 探针**不再计数** ⇒ 真洞（注入的 `if True:` 恒真判据）**照样打印到 stderr**，
  但**退出码是 0** ⇒ 探针 rc=0 + 接线门 rc=0 ⇒ ⚠⚠⚨ **全绿假绿**
  ⇒ CI 第 16 步照样绿 ⇒ 那批判据**不再被查**而**彻底没人知道**；
- ⚠⚠⚨ **E2**：`ci-true-audit.py` 的 `sys.exit('✗ 登记册不存在…')` 改成 `sys.exit(0)`
  ⇒ 登记册真被藏起来时盘点**静默退出 0**（**输出完全为空**）⇒ 盘点 rc=0 + 接线门 rc=0
  ⇒ ⚠⚠⚨ **全绿假绿**；
- **E3 / E4**：`ci-unverified-audit.py` 的两处 fail-closed 退出被改成 `sys.exit(0)`
  ⇒ 目标脚本**静默退出 0**（⚠ 接线门**另有门项**钉住那两个真洞 ⇒ 仍红 ⇒ 残余风险更小）。

⇒ 洞的形状**不是**「恒真」，是「**失败态上报被改弱 / 被摘掉**」：
① 失败**计数**被加 0；② 失败**出口**被改成 0 退出码；③ 决定退出码的**守卫被取反**
⇒ 三种形态**都不在**任何现有机制口径内（恒真探针只查条件的恒真/恒假、批 DN 只管
自检函数、批 DM 只管 `check_` 函数里的 `return`、批 DO 只管审计器自己、
`ci-wiring.sh` **没有一条门**钉住这些失败上报点）。

**修法（一条零名单维护的跨脚本 AST 规则 `check_fail_report_points`）** ——
扫 `deepin/scripts/*.py` 全部（**审计器自己除外** ⇒ 排除项由**本文件名现算**）：

1. **失败出口不许以 0 退出** —— `sys.exit(0/False/None)` ⇒ 退出码 0 ⇒ 失败被报成成功；
2. **失败计数增量不许是 0** —— **失败累加器**（出现在「失败守卫」测试里的名字）
   上的 `X += <整数字面量>` 增量必须 ≠ 0；
3. **决定退出码的守卫不许被改形** —— `return 1` 所在的最内层 `if` 守卫必须存在，
   且测试**只许「名字 / 下标」** ⇒ 取反 / 比较 / 与或 / 布尔字面量 一律红
   （⚠ **复用批 DO 的 `_guard_shape_ok`** ⇒ 判定逻辑**只有一份**）；
4. **失败上报点不许被摘掉** —— 登记册 `FAIL_REPORT_COUNTS` **双向红**
   （数量**现抽生成** ⇒ 不手抄 ⇒ 零漂移）。

⚠ **规则自己也被规则保护**（批 DM/DN/DO 同款）；⚠ **fail closed**；
⚠ 新增的失败态收集点 `fr_bad` ⇒ 按批 DO 的纪律**必须登记**
⇒ `FAIL_GUARDS` **19 → 20**；rc=2 的收集处 **8 → 9**。

⚠⚠⚨ **本批自己踩到并已修的两个真缺口**（**关键判定必须整行锚定**）：
① 口径①的**退出码判定算式**没被门钉住 ⇒ 改成 `v == 99` ⇒ 规则**静默失去牙**
⇒ 三个形态**收成一行** ⇒ 一条门钉住它；
② 口径②的**失败累加器推导行**同样没被钉住 ⇒ 删掉它 ⇒ 口径②**作用域归零**
⇒ 一条门钉住它。

**⚠⚠⚨ 本批在门项正则上栽了两次**（都靠「**从真实行现抽 + 逐条 `grep -cE` 回验**」
抓出来）：① 漏转义一个左括号 ⇒ `grep: 不匹配的 ( 或 \(` ⇒ 门红
⇒ ⚠ **Python 的 `re` 能编译**（把它当分组）⇒ **审计器侧看不出来** ⇒ 只有 `grep -E` 才报错；
② 手抄缩进（12 空格 vs 真实 8 空格）⇒ 期望 1 ≠ 实际 0 ⇒ 门恒红。

**落门 / 判据**：**新增 14 条**（批 DP 独立段）；原地替换 7 处（门项条数
**1244 → 1258** **三处同改**、`ARCH_ANY_FAIL=1` 65 → 66、`ARCH_FAIL=0` 66 → 67、
`FAILS.append(2)` 8 → 9、`FAIL_GUARDS` 门加 `fr_bad`、rc=2 **分诊文案**补第 ⑨ 种失败态）。

**负控 16 真红**：A 组四条口径各 1–4 例（审计器 rc=2 且**指名道姓**）；
B 组**关键判定门 + 门级隔离** 6 例（**只有**对应那条门红）；
C 组**门项条数三处同改**；D 组**对照实验**（真洞 + 掏空全部 `bad += 1`
⇒ **恒真探针仍 rc=0（仍是假绿 ⇒ 这就是被测的那个洞）** ⇒ 而**审计器 rc=2 报警**
⇒ 洞被抓住）；E 组**洁净度** 16/16。

⚠⚠⚨ **本批 harness 自己踩了四个错并已修**（⚠ **假红比假绿更坏** ⇒ 期望写错 = 自己骗自己）：
① **审计模式用错了**（v1 跑的是**报告模式** ⇒ rc **恒 0**；CI 真正跑的是 `--list`）；
② NC3 锚点**打偏**（改到的是 `load_baseline()` 里那个 `if bad:`）；
③ NC5 的变异**破坏了语法**（删掉 `if` 块里唯一那行）⇒ 改成替成 `pass`；
④ NC7 **期望文案写错**（命中的是「数量 8 ≠ 实测 9」⇒ **不是**「不在登记册里」）。

**数字**：门项物理行数 **1244 → 1258**、执行次数 **1247 → 1261**；
`ARCH_ANY_FAIL=1` **66**、`ARCH_FAIL=0` **67**、`FAILS.append(2)` **9**、
**守卫登记册 20** 个守卫；恒真探针 shell+python **928 → 948** 个条件
（+20 ⇒ ⚠ **自指**，知情取舍）、判定层 **396** 不变、断言实参 99 不变、
Swift 469/144 不变；盘点 **21 组 / 73 处** 不变；孤儿探针 32 脚本 / 白名单 10 条 不变；
接线门 **1261** 项全绿、审计器 `--list` rc=0（**1258/1258**）、报告模式 rc=0
（判据脚本的「失败态上报被静默关掉」**0 处**）、恒真探针 rc=0、两个盘点 rc=0、
孤儿探针 rc=0、D2 散值门 rc=0；⚠ `ci.sh` **16/16 步跑完**但 **rc=3**
（**1 组未验证**：本机缺 `appstream-util`）⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 16 真红**；累计 **1198/1198**。

**已知边界**：⚠ **登记册（口径 ④）是「名单」** ⇒ 协同编辑抓不到
⇒ ⚠ **批 CR / 批 DO 同款已知边界**；⚠ 口径 ④ 只数「**追加型写****
⇒ 累加器的**布尔标志赋值**（`bad = True` → `bad = False`）不在口径内；
⚠ 口径 ① 判不了「退出码不静态可知」的写法；⚠ 口径 ③ 只管「**决定退出码的那个守卫**」
⇒ **fail-closed 出口的守卫**（`if not os.path.isdir(…)`）的取反/改形**不被抓**
（那些守卫形态多样 ⇒ 统一约束会误伤）⇒ 有意的；⚠ 口径 ③ 按 **rc 语义**划界
（rc=1 = 失败；rc=2 = 用法错）⇒ 将来用 rc=3 表达失败 ⇒ 自动在口径内；
⚠ 范围只含 `deepin/scripts/*.py` ⇒ `linux/` 与 `macos/` 侧**不在口径内**
（当前那两边**没有**判据用 python ⇒ 残余风险小 ⇒ **下一批候选**）；
⚠ 口径 ③ 会误伤将来合法的写法 ⇒ 有意的（fail closed 方向）；
⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

## 批 DQ · 「命令替换内带 `|| true` 必须逐条登记」这条承诺不许只覆盖一半

批 CJ 立了常驻盘点 `ci-true-audit.py`：「shell 脚本里**命令替换内部**的 `|| true`
必须**逐条登记**」⇒ 登记册与实测**逐条相等** ⇒ 少一条 / 多一条都红。
本批把这条承诺**扩到全仓判据层的 shell 脚本**。

**⚠⚠⚨ 起因（实测坐实，不是推演）** —— 对照实验（scratch 树复制整个仓根）：

- ⚠⚠⚨ **D1**：往 `macos/scripts/catalog-check.sh` 新增一处**命令替换内**的 `|| true`
  ⇒ `ci-true-audit.py` **rc=0** + 接线门 **rc=0** ⇒ ⚠⚠⚨ **全绿假绿**
  ⇒ 「新增未登记 ⇒ 红」这条承诺在 **mac / linux 侧根本没有牙**
  ⇒ 那条承诺**只覆盖了四个目录里的一个**。

⚠ **缺口实测**（用盘点器**自己的抽取器**量，不是另写一个 ⇒ 口径一致）：

| 范围 | `|| true` 站点数 | 原盘点器覆盖？ |
|---|---|---|
| `deepin/scripts` | **21** | ✅ 覆盖（对得上登记册） |
| `macos/` | **7** | ❌ **不覆盖** |
| `linux/scripts` | **5** | ❌ **不覆盖** |
| `assets/` | **0** | ❌ **不覆盖**（本来就没有） |

⇒ 缺 **12** 处 ⇒ **一条本该被登记的承诺，在三个目录上从未生效**。

**修法（范围对齐 + 键改相对路径 + 双向对账）**：

1. **范围对齐恒真探针的 shell 范围**（批 CZ / 批 DB 立的判据层面）——
   `TRUE_SCOPE = (('shell','deepin/scripts'), ('macos_shell','macos'),
   ('assets_shell','assets'), ('linux_shell','linux/scripts'))`
   ⇒ ⚠ **单行**（批 AH~AX 纪律：多行元组 ⇒ 门项只能钉首行 ⇒ 内容被改窄门不会红）；
2. **递归遍历**——`macos/scripts/render-harness/run.sh` 在**子目录**里
   ⇒ 不递归 ⇒ 那批脚本上的 `|| true` 永远不被查；
3. **fail closed**——范围目录**不存在** / 范围内**一个 `.sh` 都没有** ⇒ 当场判红
   ⇒ 否则范围被悄悄掏空 ⇒ 盘点等于没跑 ⇒ **承诺的覆盖面是空的**；
4. **登记册的键改成「相对仓库根的路径」**（批 CY 教训）——
   `deepin/scripts/contract-check.sh` 与 `macos/scripts/contract-check.sh` **同名**
   ⇒ 若用裸文件名做键 ⇒ 两边的处数**合并**
   ⇒ 「一处新增 + 一处减少 = 净 0」⇒ 登记册照样相等 ⇒ **假绿**；
5. **与恒真探针的扫描范围基线逐范围对账**——两个盘点**共用**一份
   `ci-tautology-scope.baseline` ⇒ 任何一边把范围改窄 ⇒ **文件数对不上** ⇒ 红；
6. **反向对账**——基线里凡是 **shell 口径**的键（`shell` / `*_shell`）
   必须在本盘点的范围里 ⇒ 「恒真探针扩了范围而本盘点没跟上」⇒ 红
   ⇒ ⚠ **只做正向对账不够**：正向只保证「本盘点有的，基线也得有」
   ⇒ 基线**多出来**的 shell 口径（恒真探针新加的那块目录）⇒ 本盘点**看不见**；
7. **登记册重建**：21 → **33 行**（21 行键改路径 + **12 行新增**，逐条写理由）。

**⚠⚠⚨ 本批自己踩到并已修的两个真缺口**（**关键判定必须整行锚定**）：

- **反向对账那 5 行一开始一条门都没钉** ⇒ 改成 `if extra_shell and False:`
  ⇒ 那道检查**恒不触发** ⇒ **静默失去牙**而没人知道
  ⇒ ⇒ **每一条可锚定的物理行各钉一条门**
  （范围键集合 / 待查键来源 / shell 口径识别 / 排除方向 / 判定行）；
- **重生成 `FAIL_REPORT_COUNTS` 那条门时，正则漏了整行锚点**
  ⇒ 审计器 **rc=8**（锚定形态）当场判红 ⇒ ⚠ **不是推演**：审计器自己抓到了。

**落门 / 判据**：**新增 17 条**（批 DQ 独立段，插在批 DP 段之后、批 CG 块之前）；
原地替换 4 处（门项条数 **1258 → 1275** **三处同改**、`FAIL_REPORT_COUNTS` 门
**重生成**（`ci-true-audit.py` 的 `fail_exit` **14 → 15**）、
`TRUE_AUDIT_EXPECTED_ROWS` 门的说明文字补「21 → 33」、
`ci-wiring.sh` 里那条 `GATE_LINES_EXPECTED` 门项的数字与说明文字同步）。
⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条 `grep -cE` 回验；
⚠ **字面单引号写成 `.`**（批 BL 约定）。

**负控 19 真红**：A 组**覆盖面** 2 例（mac / linux 侧新增一处 `|| true`
⇒ 盘点 rc=1「新增未登记」；⚠⚠⚨ NC1 就是**改前是全绿假绿**的那个核心对照）；
B 组**范围不许被改窄** 2 例；C 组**对账不许被摘 + fail closed** 3 例；
D 组**键不许撞车 + 定义了不等于用了** 2 例；E 组**清单不许被删 + 条数基线** 2 例；
F 组**门项条数三处同改** 1 例；G 组**反向对账 6 例**（基线新增 `*_shell` 键 ⇒ 盘点红 /
判定行 → `and False` / 排除方向 `k not in` → `k in` / shell 口径识别改窄 /
范围键集合被改宽 / 待查键来源被改 ⇒ 各自指名道姓）；
H 组**双向对账** 1 例（基线里 `macos_shell` 键被删 ⇒ 盘点红「范围不再一致」）；
I 组**洁净度** 19/19（与**原始字节**逐字节相同）。

**数字**：门项物理行数 **1258 → 1275**、执行次数 **1261 → 1278**；
`ARCH_ANY_FAIL=1` **67**、`ARCH_FAIL=0` **68**、`FAILS.append(2)` **9**、
**守卫登记册 20** 个守卫；`|| true` 盘点 **21 → 33 处**、登记册 **21 → 33 行**；
恒真探针 shell+python **948 → 957** 个条件（+9 ⇒ ⚠ **自指**，知情取舍）、
判定层 **396** 不变、断言实参 99 不变、Swift 469/144 不变；
未验证出口盘点 **21 组 / 73 处** 不变；孤儿探针 32 脚本 / 白名单 10 条 不变；
接线门 **1278** 项全绿、审计器 `--list` rc=0（**1275/1275**）、报告模式 rc=0；
恒真探针 rc=0、两个盘点 rc=0、孤儿探针 rc=0；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；**负控 19 真红**；累计 **1217/1217**。

**已知边界**：⚠ **登记册是「名单」** ⇒ 协同编辑抓不到
⇒ ⚠ 批 CR / 批 DO / 批 DP 同款边界；⚠ **反向对账按 `shell` / `*_shell` 键名识别
shell 口径** ⇒ 将来若新增**不带 `_shell` 后缀**的 shell 口径键 ⇒ **漏**
（当前基线里的 shell 口径全部带 `_shell` 且 `shell` 本身被特判 ⇒ 当前够用）；
⚠ **「段」启发式对单行函数定义会误判**（`die() { … }` ⇒ 段判成 `die`）
⇒ 只影响**说明文字** ⇒ **指纹仍稳定唯一**；⚠ `assets` 侧当前 **0 处**
⇒ 那条范围**看起来是空的** ⇒ 但仍被 fail closed 守着 ⇒ 将来出现第一处就会被要求登记；
⚠ **python / swift 侧不在本盘点范围**（那两边没有 `|| true` 这个语法 ⇒ 不是洞）；
⚠ **行尾注释里的 `|| true` 也会被算成站点**（假红风险，知情取舍）；
⚠ **两个盘点共用同一份范围基线** ⇒ 改那份基线是**一处协同编辑**；
⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

## 批 DR · 失败出口的守卫不许被悄悄改弱

批 DP 台账里**写明的已知边界**：「口径 ③ 只管『决定退出码的那个守卫』⇒
**fail-closed 出口的守卫**（`if not os.path.isdir(…)`）的**取反 / 改形不被抓**」
⇒ 也就是说，判据脚本里那些「失败就不许放过」的守卫，**一个门都没钉住**。

**⚠⚠⚨ 起因（实测坐实，不是推演）** —— 3 组对照实验（scratch 树复制整个仓根）：

- ⚠⚠⚨ **B 组 · 只造真洞**：在 `ci-true-audit.baseline` 的**注释行**里塞一个**真的
  U+FFFD 字符** ⇒ 盘点 **rc=1** + 接线门 **rc=1** ⇒ **红**
  （真洞**被报出来**：文案「登记册里有 U+FFFD ⇒ 拒绝落盘/判读」）；
- ⚠⚠⚨ **C 组 · 真洞 + 中和守卫**：`if '\ufffd' in raw:` 改成
  `if '\ufffd' in raw and False:` ⇒ 盘点 rc=0 + 审计器 rc=0 + 接线门 rc=0
  ⇒ ⚠⚠⚨ **全绿假绿**。

⇒ **C 组的要害**：守卫一被中和，那个失败出口**恒不触发** ⇒ 真洞**不再被报出来**，
而三个门**全绿**。

⚠ **为什么现有机制全都抓不到**（逐条对着口径查过）：

1. **恒真探针**只抓「条件里去掉字面量与关键字后**一个标识符都不剩**」
   + `if True:` / `if False:` / `if 1:` ⇒ `X and False` **还有标识符** ⇒ **不抓**；
2. **批 DP 口径 ③**只管 `return 1` 站点 ⇒ fail-closed 的 `sys.exit(…)` **不在口径内**；
3. **批 DO / 批 DM**只管**审计器自己** ⇒ 判据脚本**不在口径内**；
4. `ci-wiring.sh` ⇒ **没有一条门**钉住这些守卫行。

⇒ ⚠⚠⚨ **实测统计**：判据脚本里共 **23 处失败出口**，其中**只有 9 处**的守卫行被门钉住
⇒ **14 处裸奔**。

**修法（两条腿 + 零名单维护）**：

1. **腿 ① · 守卫登记册（双向红 · 表达式级）** —— 新增
   `deepin/scripts/ci-fail-guard.baseline`（**23 行**，
   每行 `脚本<TAB>守卫表达式<TAB>理由`）
   ⇒ 审计器算出所有失败出口的 **(脚本, 守卫表达式) 多重集** ⇒ 与登记册**双向红**
   ⇒ 守卫被改弱（`and False` / `or True` / **换形态** / **换比较值** / **换标识符**）
   ⇒ 表达式对不上 ⇒ **红**；失败出口被**删 / 被挪 / 被加** ⇒ 对不上 ⇒ **红**；
   ⚠ 非 ASCII 一律写成 `\uXXXX` ⇒ 登记册里**不会有真 U+FFFD**
   （否则那份登记册自己就被判据拒了 ⇒ 鸡生蛋）；
   ⚠ **逐条理由**（批 BN 纪律）⇒ 第 3 段不许为空；
   ⚠ 哨兵：`(except 兜底)` / `(无 if 守卫)`。
2. **腿 ② · 守卫里不许有布尔字面量** ⇒ 布尔字面量 ⇒ 守卫要么**恒假**
   （死代码 ⇒ 失败永远不被报出）要么**恒真**（永远被报出）
   ⇒ 两种都不是「失败条件的忠实表达」⇒ 一律红
   ⇒ **一次挡住整类**（批 CD 纪律）且**不依赖登记册** ⇒ 协同编辑躲不过这一腿；
   ⚠ 判定**收成单行** ⇒ 可**整行钉住**（批 AH~AX 纪律）。

⚠ **判定口径与批 DP 完全一致**（复用 `_dp_is_sys_exit` + `_dp_is_main_call`）
⇒ 两批口径**不会各算各的**（批 BF：判定逻辑只有一份）；
⚠ **fail closed**（列不出目录 / 解析失败 / 读不了登记册 ⇒ 判红）。

**落门 / 判据**：**新增 22 条**（批 DR 独立段，插在批 DQ 段之后）；
原地替换 5 处（门项条数 **1275 → 1297** **三处同改**、`ARCH_ANY_FAIL=1` 67 → 68、
`ARCH_FAIL=0` 68 → 69、`FAILS.append(2)` 收集处 **9 → 10**、
`FAIL_GUARDS` 登记册 **20 → 21** + 那条门项**重生成**）。
⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条 `grep -cE` 回验。

⚠⚠⚨ **本批自己踩到的两个坑**（都靠现成机制当场抓住）：

- **重生成门项正则时漏了整行锚点** ⇒ 审计器 **rc=8**（锚定形态）当场判红
  ⇒ ⚠⚠⚨ **第二次踩同一个坑**（批 DQ 也栽在重生成 `FAIL_REPORT_COUNTS` 那条门上）
  ⇒ ⇒ **纪律升级**：程序化重生成正则时**必须自带 `^…$`**；
- 加了新段 ⇒ 两个段级 trailer 计数要跟着改 ⇒ 漏了 ⇒ 审计器报「次数门没配准」。

**负控 19 真红**：A 组**核心对照 + 改弱形态** 4 例；B 组**出口增减** 3 例；
C 组**登记册** 3 例；D 组**关键判定门** 6 例（条数基线常量 / 腿②判定行 /
腿①对拍判定行 / **守卫表达式的推导行** / 两个调用点）；E 组**门级隔离** 2 例；
F 组**条数三处同改** 1 例；G 组**洁净度** 20/20。

**数字**：门项物理行数 **1275 → 1297**、执行次数 **1278 → 1300**；
`ARCH_ANY_FAIL=1` **68**、`ARCH_FAIL=0` **69**、`FAILS.append(2)` **10**、
**守卫登记册 21** 个守卫；**失败出口守卫登记册 23 行**；
恒真探针 shell+python **957 → 971** 个条件（+14 ⇒ ⚠ **自指**，知情取舍）、
判定层 **396** 不变、断言实参 99 不变、Swift 469/144 不变；
`|| true` 盘点 **33 处** 不变、未验证出口盘点 **21 组 / 73 处** 不变、
孤儿探针 32 脚本 / 白名单 10 条 不变；
接线门 **1300** 项全绿、审计器 `--list` rc=0（**1297/1297**）、报告模式 rc=0；
恒真探针 rc=0、两个盘点 rc=0、孤儿探针 rc=0、D2 散值门 rc=0；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；**负控 19 真红**；累计 **1236/1236**。

**已知边界**：⚠ **登记册是「名单」** ⇒ 「改代码 + 改登记册」的**协同编辑**抓不到
⇒ ⚠ **批 CR / 批 DO / 批 DP 同款边界**；⇒ ⚠ **但腿②不依赖登记册**
⇒ 布尔字面量那一类协同编辑也躲不过；
⚠ 登记册比的是「守卫表达式」不是「失败出口本身」⇒ 两个出口的守卫**对调**
⇒ 表达式集合不变 ⇒ **抓不到**（边缘）；
⚠ 表达式规范化靠 `ast.unparse` ⇒ 同一段代码换个写法（`a is None` vs `None is a`）
表达式就不同 ⇒ 要更新登记册 ⇒ **偏严**方向；
⚠ **审计器自己除外**（`DP_SELF`）⇒ 审计器自己的失败出口由批 DO 的 `FAIL_GUARDS` 管
⇒ 两批口径**不重叠**；
⚠ **腿②只抓布尔字面量** ⇒ 「换形态 / 换比较值」只能靠腿① ⇒ 腿①是名单
⇒ 协同编辑**躲得过**；
⚠ **只管 `deepin/scripts/*.py`** ⇒ `linux/` 与 `macos/` 侧**不在口径内**
（当前那两边**没有**判据用 python ⇒ 残余风险小 ⇒ **下一批候选**）；
⚠ `_fg_collect_exits` 自己重走了一遍 AST ⇒ 与批 DP 的 `scan` 有**同款约定**
⇒ 口径一致但**实现是两处** ⇒ 将来其中一处改约定 ⇒ 两批口径会**漂**；
⚠ 登记册是 3 段 ⇒ 理由里**不许有 TAB**；
⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

## 批 DS · 判据脚本的抽取器必须被 e2e 自检覆盖

批 DN / 批 DF 的纪律：**自检必须真的经过被测的抽取器**。
⇒ 当时只给**两个**抽取器补了 e2e 自检（`ci-tautology-check.py` 的
`python_if_conds` 与 `heredoc_spans`）⇒ 台账里**写明的已知边界**：
「⚠ 腿 1 只覆盖这两个抽取器 ⇒ 别的抽取器**没有**同款自检
⇒ **不做「抽取值枚举器」**（批 DI 已降级）」。

**⚠⚠⚨ 起因（实测坐实，不是推演）** —— 3 组对照实验（scratch 树复制整个仓根）：

| 组 | 变异 | 盘点 rc | 审计器 rc | 接线门 rc | 结论 |
|---|---|---|---|---|---|
| A | —（基准） | 0 | 0 | 0 | 绿 |
| ⚠⚠⚨ **B** | **只造真洞**：在 `macos/scripts/catalog-check.sh` 末尾新增一处**反引号形态**的 `\|\| true` | **1** | 0 | **1** | 红（真洞**被报出来**：文案「新增未登记」） |
| ⚠⚠⚨ **C** | **真洞 + 抽坏抽取器**：`find_subst_spans` 的**反引号分支**被摘 | 0 | 0 | 0 | ⚠⚠⚨ **全绿假绿** |

⇒ **C 组的要害**：命令替换跨度扫描被抽坏后，**反引号形态**的新增站点
**不再被发现** ⇒ 「新增未登记 ⇒ 红」这条承诺**只对 `$(` 形态有效**
⇒ 而盘点 / 审计器 / 接线门**三个门全绿**。

⚠⚠⚨ **为什么这条形态能「静默」**（实测统计，不是推演）：

- 实测当前登记册里**反引号形态站点 = 0** ⇒ 抽坏反引号分支
  **不会**让登记册对不上 ⇒ 对照样「相等」⇒ **绿**；
- **恒真探针**抓不到（那是**条件**恒真，不是**抽取器**坏）；
- **批 DR 的守卫登记册**抓不到（守卫没被改，是**抽取器**坏了）；
- ⇒ 结论：**抽取器本身必须被 e2e 自检覆盖**，否则它坏了没人知道。

⚠ **实测统计**：判据脚本里以抽取器前缀开头（`extract_` / `find_` / `scan_` /
`parse_` / `collect_` / `strip_`）的函数，**只有 5 个**（另 1 个嵌套）
有 e2e 自检覆盖 ⇒ **6 个**裸奔。

**修法（一条零名单维护的规则 + 逐个补样例）**：

1. **审计器新增 `check_extractor_self_tests()`**（零名单维护）：
   - **前缀是单一真相源**：`EXTRACTOR_PREFIXES = ('extract_', 'find_', 'scan_',
     'parse_', 'collect_', 'strip_')`
     ⇒ 新抽取器**自动纳入** ⇒ 将来新增一个没自检的抽取器 ⇒ **立即红**；
   - **「被覆盖」= 能从某个自检函数沿调用图**传递**到达**
     ⇒ 薄封装（`scan_shell_file` → `scan_shell_text`）也算覆盖
     ⇒ **嵌套函数**（`scan_one`）同样传递覆盖；
   - **fail closed**（列不出目录 / 解析失败 ⇒ 判红）；
   - ⚠ **规则自己也被规则保护**（批 DM/DN/DO/DP 同款）：名字以 `check_` 开头
     ⇒ 批 DM 管它 ⇒ **只有一条 return**。
2. **给当前缺自检的 6 个抽取器逐个补 e2e 样例**
   （⚠ 批 DF / 批 DN 纪律：自检必须**真的经过被测的抽取器**；
   ⚠ 每档**两条**样例：「该抽到 N 条」+「不该抽到 0 条」
   ⇒ 只测一边 ⇒ 判反了也能过）：

   | 脚本 | 抽取器 | 样例 |
   |---|---|---|
   | `ci-true-audit.py` | `find_subst_spans` | `$(` 形态抽到 1 / **反引号形态抽到 1**（★ 批 DS 的洞就在这里）/ 单引号内抽到 0 |
   | `ci-true-audit.py` | `scan_file` | 含 `$(cmd \|\| true)` 抽到 **1** 处（且分类 `other`）/ 不含的抽到 **0** 处 |
   | `ci-unverified-audit.py` | `scan_file` | 含 `exit 3` 抽到 **1** 处（且分类「未验证逻辑出口」）/ 不含的抽到 **0** 处 |
   | `ci-tautology-check.py` | `find_assert_calls` | `check "标签" "模式"` 抽到 **1** 个调用点 / `echo hi` 抽到 **0** 个 |
   | `ci-tautology-check.py` | `scan_shell_file` | 一条 `if` ⇒ **1** 个条件 / 空 ⇒ **0** 个 |
   | `ci-tautology-check.py` | `scan_swift_file` | 一个 `check(…) { }` ⇒ **1** 个断言 / 空 ⇒ **0** 个 |

   ⇒ ⚠ 恒真探针侧**不新增失败出口**（它的 `self_test()` 本来就是一个出口）
   ⇒ 它的 `fail_exit` / `fail_ret` 计数**不变**；
   ⇒ ⚠ 两个盘点脚本各自新增 `selftest_extractors()` + 一个失败出口
   ⇒ 两份登记册（批 DP 的 `FAIL_REPORT_COUNTS` + 批 DR 的守卫登记册）**都要更新**。

**⚠⚠⚨ 负控跑出来的「真洞」：覆盖判定只认「名字像自检」，不认「自检会跑」**

⚠⚠⚨ 第一轮负控 17 例全红，但**有两个用例的「红」来路不对**：

| 用例 | 期望 | 实测 | 判读 |
|---|---|---|---|
| NC8 真盘点的抽取器自检**不被调用** | 审计器 rc=2「没有 e2e 自检覆盖」 | ⚠⚠⚨ **rc=4**（次数门）＋ **文案缺失** | ⚠⚠⚨ **规则自己没红** |
| NC9 未验证盘点的抽取器自检**不被调用** | 同上 | ⚠⚠⚨ **rc=4** ＋ **文案缺失** | ⚠⚠⚨ **规则自己没红** |

⇒ ⚠⚠⚨ **判读（批 DR 的教训：先问「这条变异到底改了什么」）**：
变异是「把 `_ex_bad = selftest_extractors()` 改成 `_ex_bad = []`」⇒
**自检函数从此不被调用** ⇒ 自检**永远不会执行** ⇒ 抽取器坏了**没人发现**
⇒ 而红是**批 DP 的 `FAIL_REPORT_COUNTS` 次数门**报的（`fail_count` 7 → 6）
⇒ 那是**副作用**，不是**设计** ⇒ ⇒ **规则本身有洞**。

⚠⚠⚨ **洞的根因**：`selftest_extractors` **自己的名字就含 `selftest`**
⇒ 「从自检函数出发做传递闭包」把它**当成起点**
⇒ ⇒ 它**从不被调用**时，「抽取器被自检覆盖」**照样成立**
⇒ ⇒ **覆盖判定失效**（自检是**死的**，覆盖是**假的**）。

⇒ **修法（收紧覆盖判定，不是加名单）**：

- 新增 `_ds_module_calls(tree)`：收集**模块级**语句里**直接调用**到的函数名
  ⇒ ⚠ **不进入**函数体 / 类体 / lambda 体（否则 `ast.walk` 会走进函数体
  ⇒ 函数体内的调用被**误当成**顶层入口 ⇒ live 集合被算宽）；
  ⇒ ⚠ 顶层 `if __name__ == '__main__': sys.exit(main())` 里的调用**算**入口
  ⇒ ⇒ 递归进 If / For / While / Try / With 的体里找；
- 新增 `_ds_live_funcs(tree, callees)`：**live** = 从模块级入口沿调用图
  **反向**可达的函数集合（不动点）；
- **传递闭包的起点**收紧为 `[n for n in funcs if _ds_is_selftest(n) and n in live]`
  ⇒ ⇒ 「这个自检函数**真的会被执行**」成为覆盖的**必要条件**。

⚠⚠⚨ **本批自己踩到的四个坑**（都靠现成机制当场抓住）：

1. **不动点的方向反了** —— `callees[X]` = X **调用了谁**
   ⇒ 「X 调用了 live 的 Y」**推不出** X 会执行（那是**反向**关系）
   ⇒ 第一版写成 `cs & live` ⇒ live 恒空 ⇒ 审计器立刻报
   `ci-unverified-audit.py` 的 `scan_file` **失去覆盖** ⇒ **当场抓住**
   ⇒ ⇒ **纪律**：反向可达必须先建**反向边** `callers[Y] = {X}`；
2. ⚠⚠⚨ **收紧后立刻暴露了一个真缺口** —— `ci-unverified-audit.py` 的
   `scan_file`（行 173）在收紧后**失去覆盖** ⇒ ⇒ 这**反证**了
   收紧前那条规则**确实是松的**（否则这个缺口早该被报出来）
   ⇒ ⚠ 但修好反向边后它恢复覆盖（它的 `selftest_extractors` 被 `main()` 调用
   ⇒ `main()` 是模块级入口 ⇒ live ✓）；
3. **批量替换把门改错了** —— 用「第一个含 `' 10 '` 的门项」去改
   `FAILS.append(2)` 的计数 ⇒ 命中的是 `SyntaxHighlight::highlight` 那条
   ⇒ 审计器立刻报「次数门没配准 ⇒ 门恒红」⇒ **当场抓住**
   ⇒ ⇒ **纪律**：改计数门**必须按门型 + 目标文件定位**，不许按数字猜；
4. **「grep 命中数」与「审计器命中数」口径不同** —— 审计器 `count_hits`
   **先剥注释再 grep** ⇒ 注释里出现的 `ARCH_FAIL=0` **不算**
   ⇒ 用裸 `grep -cE` 数出 72（比实际多 2）⇒ 差点把门项数改错
   ⇒ ⚠ **验证门项命中数必须用审计器的口径**（或至少记得剥注释）。

**落门 / 判据**：**新增 31 条**（批 DS 独立段，插在批 DR 段之后、批 CG 块之前）；
原地替换 8 处（门项条数 **1297 → 1328** **三处同改**、
**传递闭包的起点**那条门项**重生成**、
`ARCH_ANY_FAIL=1` 68 → 69、`ARCH_FAIL=0` 69 → 70、
`FAILS.append(2)` 收集处 **10 → 11**、`FAIL_GUARDS` 登记册 21 → **22**（加 `es_bad`）、
`FAIL_REPORT_COUNTS` **重新生成**、守卫登记册 **23 → 25 行**）。
⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条回验
（⚠ 审计器自己会校准每条门项的命中数 ⇒ `--list` rc=0 即等于逐条验过）
⚠ 转义只用 **POSIX ERE 元字符**（Python `re` 同样认）
⇒ **不用** `re.escape`（它会转义空格 / `#` / `&`
⇒ Python 3.12 对 `\#` / `\&` 这类「非字母标点转义」**直接报 error**）
⚠ 生成器自带**自证**：说明文字里有**单引号 / 反引号** ⇒ 拒绝生成
（⚠ 反引号在双引号内会被当命令替换 ⇒ `sh -n` 语法错 —— 本批生成器**当场拦下 2 处**）

**负控 20 真红**：A 组**抽坏 ⇒ 脚本自己红** 4 例；B 组**失去覆盖 ⇒ 审计器红** 5 例
（★ NC8 / NC9 在**收紧前**是 rc=4 ⇒ 规则自己没红 ⇒ **收紧后** rc=2）；
C 组**关键判定门 / 门级隔离** 6 例；D 组**样例不许被删** 1 例；
E 组**条数三处同改** 1 例；F 组**live 判定的牙** 3 例；
G 组**洁净度** 20/20（与**原始字节**逐字节相同）。

⚠ harness 纪律：scratch 树复制**整个仓根**；备份**在变异之前**取且备份路径与内容分开存；
**每个用例一棵新树** ⇒ 天然满足「变异前先还原到原始字节」；
**变异前先跑一遍确认是绿的**（否则用例无效）；
变异后**自己先自证**语法（`py_compile`）⇒ 变异不得破坏被测文件的语法；
退出码**不经管道读**；**启动前自检**；**atexit 兜底还原**；
洁净度判据 = **与原始字节逐字节相同**；
⚠ 审计模式必须用 **`--list`**（CI 真正跑的硬门模式；无参 = 报告模式 ⇒ rc **恒 0**）。

**数字**：门项物理行数 **1297 → 1328**、执行次数 **1300 → 1331**；
`ARCH_ANY_FAIL=1` **69**、`ARCH_FAIL=0` **70**、`FAILS.append(2)` **11**、
**守卫登记册 22** 个守卫；**失败出口守卫登记册 25 行**；
恒真探针 shell+python **971 → 996** 个条件（+25 ⇒ ⚠ **自指**，知情取舍）、
判定层 **396** 不变、断言实参 99 不变、Swift 469/144 不变；
`|| true` 盘点 **33 处** 不变、未验证出口盘点 **21 组 / 73 处** 不变、
孤儿探针 32 脚本 / 白名单 10 条 不变；
接线门 **1331** 项全绿、审计器 `--list` rc=0（**1328/1328**）、报告模式 rc=0
（门项条数 1328 / 基线 1328 / 危险正则 0 / 锚定违规 0）；
恒真探针 rc=0、两个盘点 rc=0、孤儿探针 rc=0、D2 散值门 rc=0；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；**负控 20 真红**；累计 **1256/1256**。

**已知边界**：⚠ **「抽取器」靠前缀识别** ⇒ 一个抽取器若**不叫**这些前缀 ⇒ **不在口径内**
⇒ ⚠ 例如 `classify` / `enclosing_func` / `load_baseline` 就**不在口径内**
⇒ ⚠ 但它们**改了会红**（指纹变了 ⇒ 登记册对不上 ⇒ 假红方向）⇒ 残余风险小；
⚠ **「被覆盖」= 能从自检函数沿调用图到达** **且** 那个自检函数
**真的会被执行**（live）⇒ ⚠ **live 的口径是「从模块级入口反向可达」**
⇒ 一个**只在 `__main__` 保护之外**被调用的自检**不算 live**（= 不算覆盖）
⇒ ⚠ 若将来把入口改成 `argparse` / 信号处理 ⇒ live 口径可能**偏严**（假红方向）；
⚠ **live 只看「调用关系」不看「条件分支」** ⇒ 一个自检函数
**永远走不到的那条分支**里调用了抽取器 ⇒ 仍算覆盖（边缘）；
⚠ **样例覆盖的是「抽取器输出的形状」不是「全部形态」**
⇒ 抽取器在**样例没涉及的形态**上坏了 ⇒ 自检**照样绿**
⇒ ⚠ 这是 e2e 自检的**固有上限**（批 DF 同款）；
⚠ **审计器自己除外**（`DP_SELF`）⇒ 审计器自己的抽取器
（`extract_fn_body_awk` / `extract_step_awk` / `split_shell_args`）
**不在口径内** ⇒ ⚠ 但它们**工具失败即判红**（批 DM 的 fail closed）⇒ 残余风险小；
⚠ **只管 `deepin/scripts/*.py`** ⇒ `linux/` 与 `macos/` 侧**不在口径内**
⇒ 当前那两边**没有**判据用 python ⇒ 残余风险小 ⇒ **下一批候选**；
⚠ **恒真探针侧不新增失败出口** ⇒ 它的抽取器自检**失败时**由既有 `self_test()`
的出口上报 ⇒ 但那条出口**不在**批 DR 的守卫登记册里（审计器自己除外）⇒ **无妨**
（它由批 DN 的门盯住）；
⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

## 批 DT · 判据结果的诊断输出不许随执行 shell 变

**⚠⚠⚨ 起因（实测坐实，不是推演）** —— POSIX 规定：

| shell | `echo` 对反斜杠的处理 | 实测 |
|---|---|---|
| **dash**（`/bin/sh`） | **解释**（`\\` → `\`） | `echo` 里的 `\\$` ⇒ 输出 `\$` |
| **bash** | **不解释**（原样输出） | 同一句 ⇒ 输出 `\\$` |

⇒ ⇒ **同一份判据脚本，在 `sh` 与 `bash` 下输出不同**。

⚠⚠⚨ **实测坐实的分叉**（`ci-wiring.sh`）：

- 门项的**说明文字**（label）里含**反斜杠**的门项共 **11 条**
  （例：「末尾 \$ 有没有被转义」那条 ⇒ label 里是 **3 个**反斜杠）；
- 实测：源文件 label = **3 个**反斜杠 ⇒
  **dash 下输出 2 个**（被解释掉一级）/ **bash 下输出 3 个**（原样）
  ⇒ ⇒ **同一份脚本、同一段文字、两种 shell、两个结果** ⇒ ⚠⚠⚨ **分叉坐实**。

⚠⚠⚨ **为什么这件事是「承诺」层面的事**（不是「洁癖」）：

⇒ **负控的「真红」判定靠的是**文案命中**（批 DP / 批 DR / 批 DS 的负控全都如此）
⇒ ⇒ 文案随 shell 变 ⇒ ⇒ **负控的真红判定不可信**

⚠⚠⚨ **核心对照实验（刻意造真洞 + 从真实输出抽关键词，绝不手抄）**：

| 组 | 树 | 关键词来源 | dash 下 | bash 下 |
|---|---|---|---|---|
| ⚠⚠⚨ **修前** | 批 DT 之前的状态 | **dash 的真实输出** | ✅ 命中 | ❌ **不命中** |
| ⚠⚠⚨ **修后** | 批 DT 之后的状态 | **dash 的真实输出** | ✅ 命中 | ✅ 命中 |

⇒ ⚠⚠⚨ **「修前」那组 = 假红坐实**：同一个真洞、同一个脚本，
dash 下文案对得上、**bash 下对不上** ⇒ ⇒ **按文案判定的消费者会误判「文案缺失」**
⇒ ⇒ 负控若在 bash 下跑 ⇒ **真红判不出来**（红判成不红）。

⚠ **全量双跑（12 个判据脚本，各自 dash / bash 各跑一遍）**：

- ⚠⚠⚨ **真分叉 1 个**：`ci-wiring.sh`（如上）；
- ⚠ `contract-check.sh` 的差异是**随机沙箱目录名**（`mktemp -d`）⇒ **不是分叉**
  ⇒ ⚠ **教训：「输出逐字节比对」会被随机量污染** ⇒ 比对时必须排除随机量；
- 其余 10 个脚本**一致**（rc 也一致）；
- ⚠⚠⚨ **判定结论（红绿）在两种 shell 下相同**（实测）⇒
  ⇒ ⚠⚠⚨ **如实记录：本批坐实的是「诊断输出分叉」，不是「红绿分叉」**
  ⇒ ⇒ 但红绿分叉的**前提**（文案不稳定）**已经坐实** ⇒ ⇒ 必须堵。

**修法（一条零名单维护的规则 + 逐处换输出机制）**：

1. **腿 ① · 输出机制换成 `printf '%s\n'`**：
   - 门型函数（`arch_*()`）体内共 **37 处** `echo` ⇒ 全部换成 `printf '%s\n'`；
   - ⚠⚠⚨ **`printf` 不解释参数里的转义** ⇒ ⇒ **两种 shell 输出一致**；
   - ⚠⚠⚨ 而且改后输出 = **源文件字面** = **作者意图**
     （源文件 label 本来就写 3 个反斜杠 ⇒ dash 把它解释成 2 个才是**失真**）；
   - ⚠ **改动口径精确**：只改**第一个 token 是 `echo`** 的行
     ⇒ ⚠ **不动** awk 程序里的 `/^echo "› …/ {` 与 `sub(/^echo "› /, "", s)`
     ⇒ ⚠ **那是 awk 的正则字面量**，改了会**坏掉 awk 程序**
     ⇒ ⚠ 也**不动**其它地方（进度信息等）的 `echo` ⇒ 那不是判据结果；
2. **腿 ② · 审计器新规则 `check_gate_output_shell()`（零名单维护）**：
   - **口径 = 函数名以 `GATE_FN_PREFIX = 'arch_'` 开头**（**单行常量**，批 AH~AX 纪律）
     ⇒ ⇒ 新门型**自动纳入** ⇒ ⇒ 新门型若用 `echo` ⇒ **立即红**；
   - **判定口径**：`echo` 前面是**行首或空白**（= 独立的命令 token）
     ⇒ ⇒ awk 里的 `/^echo` / `sub(/^echo` **不算**（前面是 `/` 或 `(`）；
   - ⚠ **fail closed**：列不出门型 / 抽不出函数体 / 函数体**抽不全** ⇒ **判红**；
   - ⚠ **规则自己也被规则保护**（批 DM/DN/DO/DP/DS 同款）：名字以 `check_` 开头
     ⇒ 批 DM 管它 ⇒ **只有一条 return**；
   - ⚠ **复用现成能力**（批 AV「抽取而非复刻」纪律）：函数体用审计器**自己**的
     `extract_shell_func()` 取 ⇒ ⇒ 不另造一套切段逻辑 ⇒ ⇒ 口径不会漂。

**落门 / 判据**：**新增 7 条**（批 DT 独立段，插在批 DS 段之后）；
原地替换 3 处（`FAIL_GUARDS` 登记册 **22 → 23** ⇒ 那一行是单行元组
⇒ 门项正则**必须重生成**、`FAILS.append(2)` 收集处 **11 → 12**
⇒ 说明文字同步（「九种失败」⇒ **「十种失败」**＋ 加第 ⑩ 项）、
门项条数 **1328 → 1335**（**三处同改**））。
⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条回验
⇒ ⚠ 转义只用 **POSIX ERE 元字符**（Python `re` 也认）⇒ **不用** `re.escape`
⇒ ⚠ 生成器**自带自证**：正则里有**字面单引号** ⇒ 写成 `.`（批 BL 约定）；
说明文字里有**单引号 / 反引号** ⇒ **拒绝生成**。

**本批踩到的五个坑**（都靠现成机制当场抓住）：

1. ⚠⚠⚨ **门项正则里混进了真单引号** ⇒ 门项行的引号配对坏掉
   ⇒ **审计器的门型盲区检测当场判红**（rc=2「有门项没解析到 ⇒ 它们根本没被审」）
   ⇒ ⇒ **纪律**：门项正则里的字面单引号**必须写成 `.`**（批 BL 约定）
   ⇒ ⇒ 生成器必须**自带这条自证**；
2. ⚠ **我新增的 `except UnreadableSource as e:` 与既有**顶层**那行**同形**
   ⇒ 次数门失配（期望 1 实际 2）⇒ **当场抓住**
   ⇒ ⇒ **纪律**：新代码的形态**不许撞**既有门项盯着的形态 ⇒ 改自己的写法，
   **不改**门项；
3. ⚠ **新规则的判定行必须独特** ⇒ 否则门项「恰好 1 处」会因别处同形而失配
   ⇒ ⇒ 把 fail closed 的两处判定**合并成一条独特形态**；
4. ⚠ **对照实验的「旧状态树」只换了旧脚本、审计器还是新的**
   ⇒ ⇒ 新审计器把旧脚本判红 ⇒ ⇒ A/B 对比**失效**
   ⇒ ⇒ **纪律**：对照组必须是**批 DT 之前的完整状态**；
5. ⚠ **「输出逐字节比对」会被随机量污染** ⇒ `contract-check.sh` 的沙箱名是随机的
   ⇒ ⇒ 那不是分叉 ⇒ ⇒ 比对前必须排除随机量（**如实判读**）。

**⚠ 负控 NC11 的判读教训**（批 DR：先问「这条变异到底改了什么」）：
第一版 NC11 只把 `check_gate_output_shell` **改名** ⇒ 实测 **rc=10**（**审计器崩了**
—— 调用点还在调旧名字 ⇒ NameError）⇒ **真红成立但没有任何文案**
⇒ ⚠⚠⚨ 「期望写错」与「规则有洞」在 harness 里**长得一模一样**
⇒ ⇒ 修正成「改名 **且** 同步改两个调用点」⇒ 审计器不崩
⇒ ⇒ 门项「判定函数定义行」命中 0 ⇒ **rc=4「次数门没配准」** ⇒ 测的正是「改名 ⇒ 门红」。
⇒ ⚠ 顺带坐实：「改名」被**两道机制**抓住（崩了 + 门项失配）⇒ 承诺没漏，但**红因不同**。

6. ⚠⚠⚨ **提交信息里把文件数写成了「10 个」** —— 那是**从批 DS 抄来**的
   ⇒ 批 DT 实际只动了 **6 个**（3 个判据脚本 + 3 个文档）
   ⇒ ⚠ **说明文字必须与实际行为一致** ⇒ **当场订正**：
   `git commit --amend` + `git push --force-with-lease` ⇒ ⚠⇒ **留痕比悄悄改掉更重要**。

**负控 12 真红**：A 组**输出机制被改回** 2 例；B 组**规则不许被改弱** 4 例；
C 组**门级隔离** 2 例；D 组**失败态不许忘登记** 1 例；
E 组**条数记三遍** 2 例；F 组**判定函数不许被掏空** 1 例（改名 + 同步改调用点 ⇒ rc=4「次数门没配准」）；
G 组**洁净度** 12/12（与**原始字节**逐字节相同）。

⚠ harness 纪律：scratch 树复制**整个仓根**；备份**在变异之前**取；
**每个用例一棵新树** ⇒ 天然满足「变异前先还原到原始字节」；
**变异前先跑一遍确认是绿的**；变异后**自己先自证**语法；
退出码**不经管道读**；**启动前自检**；**atexit 兜底还原**；
洁净度判据 = **与原始字节逐字节相同**；
⚠ 审计模式必须用 **`--list`**（CI 真正跑的硬门模式）。

**数字**：门项 **1328 → 1335**（**三处同改**）、执行次数 **1335 → 1338**；
`FAILS.append(2)` **11 → 12**、**守卫登记册 22 → 23**；
`ARCH_ANY_FAIL=1` **69** / `ARCH_FAIL=0` **70**（**不变**）；
**失败出口守卫登记册 25 行**（**不变**）；`FAIL_REPORT_COUNTS`（**不变**）；
恒真探针 shell+python **996 → 999** 个条件（+3 ⇒ ⚠ **自指**，知情取舍）、
判定层 **396** 不变、断言实参 99 不变、Swift 469/144 不变；
`|| true` 盘点 **33 处** 不变、未验证出口盘点 **21 组 / 73 处** 不变、
孤儿探针 32 脚本 / 白名单 10 条 不变；
接线门 **1338** 项全绿、审计器 `--list` rc=0（**1335/1335**）、报告模式 rc=0；
恒真探针 rc=0、两个盘点 rc=0、孤儿探针 rc=0、D2 散值门 rc=0；
⚠⚠⚨ **双跑输出逐字节一致**：改后 dash **264853** / bash **264853** ⇒ **完全相同** ✓
⇒ 改前 dash 与 bash **字节数相同但内容不同**（反斜杠数不同）；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；**负控 12 真红**；累计 **1268/1268**。

**已知边界**：⚠⚠⚨ **CI（dash）的诊断输出有 2 行变了** —— 那 2 条含反斜杠的门项文案
（源文件 label = **3 个**反斜杠 ⇒ 改前 dash 解释成 **2 个** ⇒ 改后原样 **3 个**）
⇒ ⇒ 改后 = **源文件字面 = 作者意图** ⇒ ⇒ **判定结论 / 门项期望 / 条数全部不变**
⇒ ⇒ 但**输出确实变了** ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
⚠ **历史负控的关键词全部不含反斜杠**（实测逐个扫过）⇒ ⇒ 那 2 行文案变化
**不影响**它们 ⇒ ⇒ 但这**是运气**，不是设计 ⇒ ⇒ 本批把它**变成设计**；
⚠ **只管 `ci-wiring.sh` 的门型函数** ⇒ 其它判据脚本的 `echo` 仍可能分叉
⇒ 实测当前一致 ⇒ ⇒ 且**负控靠文案的只有 python 脚本** ⇒ ⇒ 残余风险小；
⚠ **判定口径只抓「第一个 token 是 `echo`」** ⇒ `then echo …` 那种形态
**不在口径内** ⇒ ⇒ 已知边界（**假红方向**的漏）；
⚠ **注释里写 `echo` 也会被抓**（当前 **0** 处）⇒ ⇒ 假红风险（知情取舍）；
⚠ **shebang 仍是 `#!/usr/bin/env bash`（16 个脚本）** ⇒ ⇒ 「直接执行」与「CI 调用」
仍是两种 shell ⇒ ⇒ **但门型输出已跨 shell 一致** ⇒ ⇒ **「统一 shebang」判为暂不做**；
⚠ **CI 里没有「双跑一致性」这道门** ⇒ ⇒ 它是**验收标准**（本批实测）不是自动门
⇒ ⇒ ⚠ 做成自动门会**自引用**（审计器跑接线门 ⇒ 接线门又跑审计器 ⇒ 递归）
⇒ ⇒ 若要自动化**只能放在 `ci.sh` 里** ⇒ ⇒ **下一批候选**；
⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。
