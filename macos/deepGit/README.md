# deepGit — macOS 客户端

> 双形态原生客户端：**主面板窗口**（完整 git 项目管理面板）+ **菜单栏 bar**（辅助速览）。
> 本项目是纯客户端，独立于引擎构建与发布。

## 形态

| 形态 | 入口 | 内容 |
|---|---|---|
| **主面板**（主体） | 菜单栏「打开面板」、点击 bar 项目行、或 `deepGit --open-panel` | 侧栏导航：**仪表盘**（项目群脉搏 hero + 一键说明 + 图标统计卡/语言分布/里程碑/活跃项目）、**看板**（独立页面：按健康状态分列——活跃/待处理/停滞/其他，卡片带快捷动作）、**里程碑**（行内直操作：点击行跳项目、··· 菜单达成/重开/放弃/删除）、**项目详情**（工程脉搏、提交构成、分支进度、Git 操作、进度日志、README/AGENTS/CLAUDE 平铺） |
| **菜单栏 bar**（辅助） | 常驻状态项（如 `15 ⚠︎1`） | `.window` 富弹窗：汇总行 + 项目速览行（状态点/未提交徽标/待记录迷你进度条）+ 全部浅更新 + 退出 |

状态项标题即健康度：项目数 + `⚠︎N`（有停滞分支）或 `●N`（有未提交改动），图标颜色随状态变化（绿/橙/红）。

## AI 助手（客户端 AI 层，deepDesign 模式 · models.dev + ai-sdk）

引擎是 **AI 无关**内核；AI 的目录、通道、配置与 agent 循环全部在本客户端，
实现方式与 deepOrca 同构：**models.dev 目录 + ai-sdk 通道**。

- **models.dev 目录**（`ModelsDev.swift`）：vendor 快照 `Resources/models-dev.json`
  （从 deepOrca 的 models-dev/api.json 瘦身，225 家 provider）+ 启动后静默刷新最新目录。
  数据仅作选择器与通道元数据：模型 id、tool_call、reasoning、上下文窗口、成本、provider api 端点。
- **ai-sdk 通道**（`AISDK.swift`）：`LanguageModel.generateText` ——
  OpenAI 兼容（deepseek/openai/ollama/openrouter/网关…）与 Anthropic 双协议，
  **原生 tool_calls / tool_use 线格式**（不是文本协议）；baseURL 默认取目录 `api` 字段。
- **设置**（AI 助手页 ⚙️）：provider/model 选择器由目录填充（⚡︎=tool_call、🧠=reasoning、
  上下文窗口徽标），Base URL 默认目录端点可覆盖；**key 存 macOS 钥匙串**；一键测试连通。
- **AI 助手**（侧栏 ✦）：选范围提问 → 引擎 `context --json` 上下文包 + `tools --json` 工具清单 →
  模型原生调用引擎工具（更新/读文档/提交改动…），客户端执行后回喂，≤4 轮 → Markdown 渲染。
- 无头自测（CI/排查）：`deepGit --agent-selftest "总结一下项目群现状"`；
  本地 mock 验证：`defaults write cn.deepgit.app ai.providerID mock` +
  `ai.baseURL http://127.0.0.1:5999/v1` + `ai.apiKey mock-key`（配一个回 tool_calls 的假 provider）。

## 引擎 / 客户端边界（重要）

| 职责 | 归属 | 说明 |
|---|---|---|
| 项目注册、进度记录、文档写入 | **引擎** | `deepgit scan/update/deep/track --json`（CLI 子进程） |
| 状态 / 仪表盘 / 里程碑 / 日志数据 | **引擎** | `deepgit status/dashboard/milestone list --json` |
| 更新 / 里程碑 / git 操作 | **引擎** | `deepgit update/deep --json`、`deepgit milestone <子命令> --json`、`deepgit git <op> <项目> --json`（pull/push/commit/stash/unstash/fetch 白名单，无破坏性命令） |
| agent 喂养（上下文包/工具清单） | **引擎** | `deepgit context --json`、`deepgit tools --json`（或 MCP `tools/list`）——引擎 AI 无关，只供事实与动作 |
| **AI 目录/通道/配置、工具循环** | **客户端** | models.dev 目录（快照+刷新）选型；ai-sdk 风格通道（OpenAI 兼容 + Anthropic 原生 tool_calls）；key 存钥匙串；agent 循环在 AgentView |
| 文档内容 | **引擎** | `deepgit docs <项目> --json` 返回 README/AGENTS/CLAUDE 原文（单文件 200KB 截断），客户端本地渲染 |
| 进度存储（`~/.deepgit/store/`） | **引擎** | 客户端不落任何业务数据 |
| 引擎发现与拉起 | **客户端** | `DEEPGIT_BIN` → app 内嵌副本（`Contents/Resources/deepgit`）→ `~/.local/bin` → `/usr/local/bin` → 登录 shell PATH；找到后按需拉起 CLI 子进程 |
| 数据获取与渲染、通知、自启 | **客户端** | 本仓库全部代码 |
| 退出清理 | **客户端** | 若引擎服务是本 app 拉起的，退出时一并停止 |

契约：引擎 `--json` 的键名是**唯一耦合面**，改动必须同步
`Sources/deepGit/Models.swift` 与引擎 `flow/*.cj`。
（传输层只有 CLI 子进程与 MCP，**没有 HTTP 服务**；客户端不走网络取引擎数据。）

## 系统集成

- **开机自启**：`SMAppService`（bar 或面板内开关，macOS 13+）
- **添加项目 UI**：侧栏「+ 添加 / 扫描项目」——单个添加（路径）或批量扫描（根目录+深度），引擎 CLI 子进程驱动
- **正经 Mac 应用形态**：SwiftUI Window Scene 管理（Dock 图标 + 标准标题栏工具栏 + 副标题 + 中文本地化菜单）；
  主面板带**统一标题栏工具栏**（刷新 / 全部浅更新 / 定时更新菜单 / AI 设置）与动态副标题（项目群摘要）；
  点 Dock 图标重新打开面板
- **设置窗口**（⌘, / 工具栏）：自动化（定时更新间隔）+ AI 配置，分区呈现
- **系统通知**：分支停滞 / 未提交过多 / 更新完成 / 定时简报（只在状态「新变差」时提醒）；**点击通知 = 打开面板**，通知自带「打开面板」动作按钮
- **Dock 菜单**：右键 Dock 图标 = 打开面板 / 全部浅更新。
  刻意只放这两项 —— Dock 菜单在 macOS 里的定位是「高频动作的快捷入口」，
  完整动作表在应用内「操作」菜单里。「全部浅更新」会**先叫醒主面板再弹确认框**：
  确认框挂在面板上，窗口没开就没人呈现，只设 pending 会表现为「点了没反应」。
- **引擎发现**：打开面板时定位引擎二进制（`DEEPGIT_BIN` → 内嵌副本 → 常见安装路径 → PATH），
  之后所有数据操作都以 CLI 子进程方式调用；**没有本地服务、没有端口**
- **应用图标**：`AppIcon.png`（PIL 生成的 git 分支拓扑 + ◆ 记号）→ `AppIcon.icns`，
  build.sh 自动拷入 bundle（CFBundleIconFile）。
- **深链启动参数**（解析规则在 `Route.swift`，纯函数可单测）：
  - `deepGit --open-panel` 启动即开主面板
  - `--project <名称>` 直达项目详情
  - `--section dashboard|board|milestones` 直达对应页
  - `--agent-selftest [问题]` 无头跑一次 agent 并打印结果（问题可省）
  - **这些开关彼此独立**：以前 `--project` 必须搭 `--open-panel` 的便车才生效，
    少加了就静默停在默认页。现在任意一个都能单独用；
    `--project` 与 `--section` 同现时以 `--project` 为准。
  - 指向一个不存在的项目时不会打开空详情页：改道仪表盘并在顶部说明一句。

## 构建

```sh
sh build.sh        # swift build -c release + 组装 deepGit.app + ad-hoc 签名
open deepGit.app
# 安装：cp -R deepGit.app /Applications/
```

`build.sh` 会尝试把引擎二进制与仓颉运行时 dylib 内嵌进 .app（~59MB），
使其可独立分发；不内嵌则按上面的发现链找系统里的引擎。

## 代码结构

```
Sources/deepGit/
  A11yLabel.swift               纯函数：无障碍标签与 `SearchFilter`（空态两态可区分）
  AIClient.swift                引擎/上下文/工具清单的客户端门面
  AIErrorMessage.swift          纯函数：URLError → 可执行中文 + 地址脱敏到 host:port
  AIIntegration.swift           AI 开关、集成接线、`AIResultSheet` 结果弹窗与顶栏双轨按钮
  AISDK.swift                   ai-sdk 风格通道：generateText + 原生 tool_calls/tool_use；配置（钥匙串）
  AISettingsView.swift          AI 设置页（provider/模型/密钥/测试连接）+ 开源自启
  AgentConversation.swift       纯函数：会话（seed/trim/transcript/canSend/canStop）
  AgentCore.swift               AI 工具循环：引擎 context/tools --json → ai-sdk 工具定义 + executeTool
  AgentOutcome.swift            纯函数：撞轮次上限时怎么收尾（工具已执行 ≠ 失败）
  AgentView.swift               AI 助手：会话 UI + 工具调用循环（多轮上下文）
  BarView.swift                 菜单栏弹窗 UI
  BoardView.swift               项目看板卡片（渲染 warnings）
  ChatMessage.swift             聊天消息模型（零依赖，供 agent-check 编译）
  ClientDecisions.swift         纯函数：刷新合并门闩等（撞上不丢弃，排队补跑）
  CommitCountScope.swift        纯函数：提交数分母口径
  CommitTypeComposition.swift   纯函数：提交类型构成 + 截断披露
  Components.swift              StatusDot / StatCard / SegmentedBar / Card 等基础件
  ContextEnvelope.swift         纯函数：agent 上下文包裁剪
  DeepGitApp.swift              入口：MenuBarExtra(.window) + AppDelegate（深链/退出清理）+ CommandMenu（双轨动作 ⇧⌘U / ⌥⇧⌘D）
  DesignSystem.swift            设计系统视图层：DSColor / DSSpacing / DSRadius / DSTypography / Surface
  DesignTokens.swift            纯函数：色板（逐值等于设计稿 tailwind.config）/ 状态与量级分档
  DestructiveGuard.swift        纯函数：破坏性动作的确认文案与「可逆动作不弹确认」
  DetailViews.swift             项目详情页 + 仪表盘页（渲染 warnings / dirty / highlights / nextSteps）
  EngineCLI.swift               引擎发现 + 按需拉起 CLI 子进程 + ProcessRegistry（批量更新可真停）
  EngineFailure.swift           纯函数：引擎失败分类与文案
  LanguageCoverage.swift        纯函数：语言分布占比
  LoadState.swift               纯函数：一个数据源的加载四态 → 该画加载/空/错误哪一种
  MarkdownParser.swift          Markdown 解析（独立于视图，便于单测）
  MarkdownView.swift            轻量 Markdown 渲染（文档平铺与 AI 回答共用，解析结果记忆化）
  MilestoneCard.swift           纯函数：里程碑卡切片 + 截断披露
  MilestonesView.swift          里程碑管理页（含新建 Sheet + 搜索 + 破坏性确认）
  Model.swift                   AppModel（数据编排/动作/提醒策略）+ 路由入口 `go(_:)` + 通知 + SMAppService
  Models.swift                  CLI `--json` 契约 Codable 模型（与引擎 flow 层 JSON 严格同名）
  ModelsDev.swift               models.dev 目录（vendor 快照 + 静默刷新）→ provider/model 元数据
  PanelView.swift               主面板骨架（NavigationSplitView 侧栏 + 路由 + 顶栏）
  PathInput.swift               纯函数：路径三态判定（missing/file/directory）
  ProviderPickerSlice.swift     纯函数：模型选择器的截断披露
  Route.swift                   纯函数：启动参数 → 路由意图（各开关彼此独立）
  Router.swift                  纯函数：路由的唯一决策处（区分「不知道」与「确实没有」）
  ScanCoverage.swift            纯函数：扫描覆盖披露
  ScanSheet.swift               扫描面板（NSOpenPanel 选目录 + 拖放 + 实时判定）
  Scope.swift                   纯函数：顶栏双轨动作的范围与标题规则（范围由 selection 推导）
  ShortcutKey.swift             `Shortcut` → SwiftUI `KeyEquivalent` / `EventModifiers` 换算
  ShortcutMap.swift             纯函数：快捷键唯一声明处 + 撞键判定
  StopDecision.swift            纯函数：停止按钮可用性与文案
  SysOpen.swift                 外部打开（git remote → 浏览器）
  ToolArgs.swift                纯函数：工具入参解析与必填校验（畸形 ≠ 没有参数）
  UpdateOutcome.swift           纯函数：更新结果通知文案（备份路径必须说清）
```

> 带「纯函数」的都是**零 SwiftUI 依赖**的判定层，被 `scripts/client-check.sh`
> 单独编译并断言 —— 它们能被单测，是因为它们没有把判定藏回视图里。

> ⚠️ 原来这里列的是 `PanelWindow.swift` 和 `Engine.swift` —— 两个文件都已删除，
> 后者描述的还是「serve 托管 + APIClient（URLSession）」这套 HTTP 架构。
> 留着会让人去找不存在的文件、不存在的传输层。

## 已知边界 · 按最佳预案定的取舍（2026-10-02 起）

> 协作规约见 `engine/AGENTS.md` 的「协作规约」节：拿不准时按预案定、不停下来提问，
> 但**必须把决定写进文档**。以下是本轮落档的具体取舍与它的已知代价。
> 通用判据（可复用的那部分）已提炼为 `engine/AGENTS.md` 不变量 95。

| 决定 | 为什么这么定 | 已知代价 / 什么情况下要改 |
|---|---|---|
| 顶栏双轨按钮**带文字** | 设计稿原文如此，图标 + 文字混排 | **未经人眼验证**：默认窗口 1100 宽下是否挤得下未知。挤不下时先丢副标题，再把双轨按钮退成纯图标 |
| **不铺 entitlements** | 当前 ad-hoc 签名且未启用 hardened runtime，写了也是空操作 | 将来要**公证或上架**时必须补 sandbox / 网络 / 助手权限声明；到那一步要重新评估并实测 |
| **不另造范围选择器** | 设计稿顶栏有范围下拉，但侧栏导航已承担同角色；再存一份就是两个真相源 | `Scope` 的范围由 `selection` 推导。哪天侧栏导航被去掉，这条要跟着回退 |
| 规范与设计稿冲突时**以设计稿原文为准** | 已四次撞上（看板是否删、`MarkdownView` 缓存、⌘N 数量、侧栏三分组 IA） | 例：规范写侧栏分「引擎/协作/智能」，设计稿原文里根本没有这个分组；照表实现只会造一个空壳入口 |
| 代码结构清单**按磁盘重建** | 原清单 1 个文件不存在、18 个漏列 | 已加双向判据（`client-check.sh`），以后清单与磁盘不符会红 |
| 文档区四态的**措辞由客户端定** | 引擎只给内容与 `unreadable` 列表，不给文案 | 判据卡的是「空与失败必须是两句不同的话」，不卡具体字词 —— 改文案不会红，改成同一句会红 |
| stale 阈值**跟引擎，不在客户端自造** | 引擎是 3/14 天（`kernel/progress.cj`），客户端原来自造 30 天 | 引擎改阈值时客户端自动跟随；反过来客户端不许再推导 |
| 颜色映射提到**视图层共享**（`DSColor.sequence`） | 原来 `commitTypeColor` 是 `ProjectDetailView` 的私有方法，`DashboardView` 里的语言卡够不着，只好自己内联 8 色 ⇒ 两套调色板 | 色板序列仍在纯函数层（`CommitTypeColor.palette`，可单测）；映射必须在视图层，因为 `Color` 属 SwiftUI，纯函数层不许 import |
| spacing 只做**等值替换**（45 处） | 刻度值字面量与 token 同值不同源，改 token 时不跟着动（真缺陷） | 51 处散值**故意保留**：收进刻度是改布局，视觉未验证前不擅自做。见下方待确认清单 |
| 圆角统一到**连续曲率**（`DSRect.shape` 唯一构造点） | 9 处 `RoundedRectangle` 里只有 `surface` 内部写了 `style: .continuous`，其余 8 处是默认 circular ⇒ 同一张 Card 里 Chip / 描边 / 彩色底接缝对不上 | **这是视觉改动，未验证**：连续曲率是 macOS 原生控件的做法，方向确定，但实际观感要人眼看。另有 `.quaternary` 等层级色走 `tinted` 的泛型参数，抹掉颜色会把「出错」和「中性」画成同一张卡 |
| 动效**保持极少**（全项目只有 1 处） | §3.3 要求「统一缓动与时长，遵循 macOS 观感（**不过度**）」—— 不加错动效比加动频更重要 | 那唯一一处（agent 新消息自动滚动）已从裸 `withAnimation`（SwiftUI 默认 0.25s / default 缓动）改为 `DSMotion.standard`（0.20s easeInOut）。判据卡住「不许新增裸动效」，所以以后加动效必须走 token |

### 还没做的（需要人眼或需要授权）

- **视觉渲染未验证**：顶栏新增了带文字的双轨按钮，1100 宽默认窗口下挤不挤得下，只能人眼看。
- **真机/真数据未跑**：本轮所有验证都在沙箱 `DEEPGIT_HOME=/tmp/...` 里做，
  `~/.deepgit/registry.json` 未动（保持 4710 字节 / sha `b61aaa5a…`）。

### 待人工确认：spacing 的 51 处散值

刻度值（4/8/12/16/20/24）已全部换成 `DSSpacing` token（45 处，**零视觉变化**，
因为数值本来就相等）。剩下 51 处**故意保留**：

| 值 | 处数 | 涉及文件 |
|---|---|---|
| 10 | 13 | AIIntegration / AISettingsView / BoardView / Components / DetailViews / MilestonesView |
| 14 | 8 | BoardView / DetailViews / PanelView |
| 2 | 7 | BarView / Components / DetailViews / MarkdownView / MilestonesView |
| 6 | 7 | AgentView / BarView / BoardView / DetailViews / PanelView |
| 3 | 6 | DeepGitApp / DetailViews / MarkdownView / MilestonesView |
| 5 | 6 | AIIntegration / BoardView / DetailViews |
| 7 | 4 | BoardView / DetailViews / MarkdownView |

**为什么不一刀切收进刻度**：那是**改布局**、不是重构。14→16 挤不挤、
10 该变 8 还是 12，都得看着窗口才知道，而本项目至今没做过任何视觉验证 ——
擅自收敛等于把猜测写进布局。判据把基线钉死在 51 处（`client-check.sh` 不许它增长），
等有人真正看过窗口，再逐档收掉。通用判据见 `deepgit-engine` 的不变量 96。
