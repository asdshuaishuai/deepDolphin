# deepDolphin — macOS 客户端

> 双形态原生客户端：**主面板窗口**（完整 git 项目管理面板）+ **菜单栏 bar**（辅助速览）。
> 本项目是纯客户端，独立于引擎构建与发布。

## 形态

| 形态 | 入口 | 内容 |
|---|---|---|
| **主面板**（主体） | 菜单栏「打开面板」、点击 bar 项目行、或 `deepDolphin --open-panel` | 侧栏导航：**仪表盘**（项目群脉搏 hero + 一键说明 + 图标统计卡/语言分布/里程碑/活跃项目）、**看板**（独立页面：按健康状态分列——活跃/待处理/停滞/其他，卡片带快捷动作）、**里程碑**（行内直操作：点击行跳项目、··· 菜单达成/重开/放弃/删除）、**项目详情**（工程脉搏、提交构成、分支进度、Git 操作、进度日志、README/AGENTS/CLAUDE 平铺） |
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
- 无头自测（CI/排查）：`deepDolphin --agent-selftest "总结一下项目群现状"`；
  本地 mock 验证：`defaults write cn.deepdolphin.app ai.providerID mock` +
  `ai.baseURL http://127.0.0.1:5999/v1` + `ai.apiKey mock-key`（配一个回 tool_calls 的假 provider）。

## 引擎 / 客户端边界（重要）

| 职责 | 归属 | 说明 |
|---|---|---|
| 项目注册、进度记录、文档写入 | **引擎** | `moongit scan/update/deep/track --json`（CLI 子进程） |
| 状态 / 仪表盘 / 里程碑 / 日志数据 | **引擎** | `moongit status/dashboard/milestone list --json` |
| 更新 / 里程碑 / git 操作 | **引擎** | `moongit update/deep --json`、`moongit milestone <子命令> --json`、`moongit git <op> <项目> --json`（pull/push/commit/stash/unstash/fetch 白名单，无破坏性命令） |
| agent 喂养（上下文包/工具清单） | **引擎** | `moongit context --json`、`moongit tools --json`（或 MCP `tools/list`）——引擎 AI 无关，只供事实与动作 |
| **AI 目录/通道/配置、工具循环** | **客户端** | models.dev 目录（快照+刷新）选型；ai-sdk 风格通道（OpenAI 兼容 + Anthropic 原生 tool_calls）；key 存钥匙串；agent 循环在 AgentView |
| 文档内容 | **引擎** | `moongit docs <项目> --json` 返回 README/AGENTS/CLAUDE 原文（单文件 200KB 截断），客户端本地渲染 |
| 进度存储（`~/.deepgit/store/`） | **引擎** | 客户端不落任何业务数据 |
| 引擎发现与拉起 | **客户端** | `DEEPGIT_BIN` → app 内嵌副本（`Contents/Resources/moongit`）→ `~/.local/bin` → `/usr/local/bin` → 登录 shell PATH；找到后按需拉起 CLI 子进程 |
| 数据获取与渲染、通知、自启 | **客户端** | 本仓库全部代码 |
| 退出清理 | **客户端** | 若引擎服务是本 app 拉起的，退出时一并停止 |

契约：引擎 `--json` 的键名是**唯一耦合面**，改动必须同步
`Sources/deepDolphin/Models.swift` 与引擎 `flow/*.cj`。
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
- **应用图标**：来自**全平台共用的公共资源** `assets/icon/`（海豚 + Git 章鱼，
  唯一母版 `mark.png`），`build.sh` 从 `assets/icon/out/macos/AppIcon.icns`
  拷入 bundle（CFBundleIconFile）。macOS 目录里不再放自己的那一份 ——
  三平台同一套图标，母版与派生关系见 [../assets/icon/README.md](../assets/icon/README.md)。
- **深链启动参数**（解析规则在 `Route.swift`，纯函数可单测）：
  - `deepDolphin --open-panel` 启动即开主面板
  - `--project <名称>` 直达项目详情
  - `--section dashboard|board|milestones` 直达对应页
  - `--agent-selftest [问题]` 无头跑一次 agent 并打印结果（问题可省）
  - **这些开关彼此独立**：以前 `--project` 必须搭 `--open-panel` 的便车才生效，
    少加了就静默停在默认页。现在任意一个都能单独用；
    `--project` 与 `--section` 同现时以 `--project` 为准。
  - 指向一个不存在的项目时不会打开空详情页：改道仪表盘并在顶部说明一句。

## 构建

```sh
sh build.sh        # swift build -c release + 组装 deepDolphin.app + ad-hoc 签名
open deepDolphin.app
# 安装：cp -R deepDolphin.app /Applications/
```

`build.sh` 会尝试把引擎二进制与仓颉运行时 dylib 内嵌进 .app（~59MB），
使其可独立分发；不内嵌则按上面的发现链找系统里的引擎。

## 代码结构

```
Sources/deepDolphin/
  A11yLabel.swift               纯函数：无障碍标签与 `SearchFilter`（空态两态可区分）
  AIClient.swift                引擎/上下文/工具清单的客户端门面
  AIErrorMessage.swift          纯函数：URLError → 可执行中文 + 地址脱敏到 host:port
  AIIntegration.swift           AI 开关、集成接线、`AIResultSheet` 结果弹窗与顶栏双轨按钮
  AISDK.swift                   ai-sdk 风格通道：generateText + 原生 tool_calls/tool_use；配置（钥匙串）
  AISettingsView.swift          AI 设置页（provider/模型/密钥/测试连接）+ 开源自启
  AgentBulkUpdate.swift        纯函数：一键全量的逐仓库执行（走 agent 工具通道，覆盖由代码保证）
  AgentBulkView.swift          顶栏「全量浅 / 全量深」两个一键入口 + 结果面板接线
  AgentConversation.swift       纯函数：会话（seed/trim/transcript/canSend/canStop）
  AgentCore.swift               AI 工具循环：引擎 context/tools --json → ai-sdk 工具定义 + executeTool
  AgentOutcome.swift            纯函数：撞轮次上限时怎么收尾（工具已执行 ≠ 失败）
  AgentView.swift               AI 助手：会话 UI + 工具调用循环（多轮上下文）
  BarView.swift                 菜单栏弹窗 UI
  BoardView.swift               看板页（按可执行性分列的原生分组列表）
  ChatMessage.swift             聊天消息模型（零依赖，供 agent-check 编译）
  ClientDecisions.swift         纯函数：刷新合并门闩等（撞上不丢弃，排队补跑）
  CommitCountScope.swift        纯函数：提交数分母口径
  CommitTypeComposition.swift   纯函数：提交类型构成 + 截断披露
  Components.swift              StatusDot / StatCard / SegmentedBar / Card 等基础件
  ContextEnvelope.swift         纯函数：agent 上下文包裁剪
  DashboardParts.swift          仪表盘四段式零件：筛选行 / KPI 宽卡 / 逐项目进度卡（设计稿布局）
  DashboardScope.swift          纯函数：时间窗 + 提交类型筛选、4 张 KPI 的归并口径
  DeepDolphinApp.swift              入口：MenuBarExtra(.window) + AppDelegate（深链/退出清理）+ CommandMenu（双轨动作 ⇧⌘U / ⌥⇧⌘D）
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
  MilestonesView.swift          里程碑管理页（仓库筛选 + 搜索 + 按项目分组 + 新建/破坏性确认）
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
  WorkBar.swift                 主工作条（范围选择器 + 双轨链路）+ 侧栏状态条
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

## 待验证 · 「项目卡里程碑行恒空」这一疑点（2026-10-03 记）

Linux 端对齐仪表盘时顺带看了一眼 `ProjectProgressCard` 的这条：

```swift
milestones: d.milestones.items.filter { $0.projectId == p.id }
```

**疑点**：真实载荷里 `milestones.items` 恒为空数组（实测 15 个项目时
`items: []`，而 `counts.readCount=1` / `orphaned=1`），
所以卡片上的里程碑行从来没有任何数据可画 —— 看起来像恒空。

**已排除的怀疑**：「引擎不发 `projectId`」是**错的**（我一度这么断言并推上去了，
在此更正）。`kernel/milestoneJson` = 存储侧 `toJson()` 全字段（**含 projectId**）
+ 一组补充键，三个出口共用这一份形状。`ProjectProgressItem` 把它建模成必填非可选是对的。

**仍未验证**：`projectId`（存储侧 `ProjectEntry.id`）与 `ProjectStatus.id`
（载荷里的项目 `id`）是否**逐字相等**。相等则这行代码是对的，
不相等则卡片恒空。真实数据 `items` 为空，验不了。

Linux 端的处理是**取能验证的那条路**：项目归属按 `projectName` 匹配
（引擎恒发，且与 `Project.name` 同源，必然匹配）。等有非空 items 时，
两边都应该用判据确认一次，而不是继续猜。

---

## 已知边界 · 按最佳预案定的取舍（2026-10-02 起）

> 协作规约见 `moonGit/AGENTS.md` 的「协作规约」节：拿不准时按预案定、不停下来提问，
> 但**必须把决定写进文档**。以下是本轮落档的具体取舍与它的已知代价。
> 通用判据（可复用的那部分）已提炼为 `moonGit/AGENTS.md` 不变量 95。
> 本轮新增的通用判据：**114**（引擎修过的口径，客户端必须逐字对齐）、
> **115**（同一个量在同一屏里只许有一个算法）、**116**（撤入口 ≠ 撤能力）、
> **117**（交叉验证必须拿非空样本）、**118**（负控要按判据的实际位置选套件）。

| 决定 | 为什么这么定 | 已知代价 / 什么情况下要改 |
|---|---|---|
| 顶栏双轨按钮**带文字** | 设计稿原文如此，图标 + 文字混排 | **已用离屏快照验证**（`run.sh <目录> panel`，1100×760）：双轨（⚡ AI / 法杖 agent）与右簇（✦ / ⚙ / 🔍）在 1100 宽下**不挤**，中间到窗口右缘全是空 ⇒ 无需退成纯图标。仍值得人眼确认一次的是**真窗口下的按钮命中区与深浅色主题**（快照拍不到 chrome） |
| **不铺 entitlements** | 当前 ad-hoc 签名且未启用 hardened runtime，写了也是空操作 | 将来要**公证或上架**时必须补 sandbox / 网络 / 助手权限声明；到那一步要重新评估并实测 |
| **保留顶栏范围选择器**（推翻本文件此前「不另造」的结论） | 此前论证是「侧栏导航已承担同角色，再存一份就是两个真相源」。**那条论证是错的**：侧栏管的是「看哪个视图」，顶栏范围管的是「看哪些仓库」，两者**正交**；而且推导式绑定（读 `selection`、写 `go(_:)`）**不是**第二真相源 —— 它没有自己的状态，只是 selection 的一个视图。设计稿里这条下拉正是「全局看板 ↔ 单仓库」的切换器，也就是用户点名要保留的两点之间的那座桥 | 范围选择器只在**有项目时**出现（没项目时它是根装饰条）。它不持有状态，所以切视图时不会丢；代价是「切到里程碑页时范围必然回到全局」—— 这也是里程碑页必须**自己**带仓库筛选的原因（见下） |
| **D8：菜单栏弹窗不做成「纯启动器」** | 计划书问 BarView 与主面板重复约 60% 是否收敛为纯启动器。实测重复的是**内容**（项目行、刷新、批量更新、空/错三态），而菜单栏弹窗的价值恰恰是「不打开窗口就扫一眼」—— 收成纯启动器等于让菜单栏只剩一个「打开面板」按钮，用户还不如点 Dock 图标。macOS 平台惯例（Stats / Bartender 类）也是弹窗内要有内容 | **代价照实说**：两份渲染仍要各自维护外观。所以本轮不去「合并视图」（那是改布局），而是**把重复的领域规则收到唯一出处**：`ProjectStatus.primaryBranch`（原来被抄 3 份，其中 PanelView 一份还是内联的不同拼法）。已修的部分见下一行；未修的部分（刷新/批量更新各存一份 action、两个空/错态视图）**如实记为已知重复**，收敛它们要动交互，不在视觉验证可覆盖的范围内 |
| 「当前分支」规则**只留一个出处** | 原来 `branches.first { $0.isCurrent } ?? branches.first` 被抄在 BarView / BoardView 的私有 computed property 与 PanelView 的内联 `else if` 里，共 3 份 | 规则提到 `ProjectStatus.primaryBranch`（模型层，不 import SwiftUI）。判据卡结构（`client-check.sh`「只能有一个出处」+ `contract-check.sh` 用**真 fixture** 验行为，含与引擎声明的 `currentBranch` 名字交叉验证），负控 NC82 5/5。**不叫 `currentBranch`** 是因为那个名字已被引擎给的分支名字符串占了 |
| 规范与设计稿冲突时**以设计稿原文为准** | 已四次撞上（看板是否删、`MarkdownView` 缓存、⌘N 数量、侧栏三分组 IA） | 例：规范写侧栏分「引擎/协作/智能」，设计稿原文里根本没有这个分组；照表实现只会造一个空壳入口 |
| 代码结构清单**按磁盘重建** | 原清单 1 个文件不存在、18 个漏列 | 已加双向判据（`client-check.sh`），以后清单与磁盘不符会红 |
| 文档区四态的**措辞由客户端定** | 引擎只给内容与 `unreadable` 列表，不给文案 | 判据卡的是「空与失败必须是两句不同的话」，不卡具体字词 —— 改文案不会红，改成同一句会红 |
| stale 阈值**跟引擎，不在客户端自造** | 引擎是 3/14 天（`kernel/progress.cj`），客户端原来自造 30 天 | 引擎改阈值时客户端自动跟随；反过来客户端不许再推导 |
| 颜色映射提到**视图层共享**（`DSColor.sequence`） | 原来 `commitTypeColor` 是 `ProjectDetailView` 的私有方法，`DashboardView` 里的语言卡够不着，只好自己内联 8 色 ⇒ 两套调色板 | 色板序列仍在纯函数层（`CommitTypeColor.palette`，可单测）；映射必须在视图层，因为 `Color` 属 SwiftUI，纯函数层不许 import |
| spacing 只做**等值替换**（45 处） | 刻度值字面量与 token 同值不同源，改 token 时不跟着动（真缺陷） | 51 处散值**故意保留**：收进刻度是改布局，视觉未验证前不擅自做。见下方待确认清单 |
| 圆角统一到**连续曲率**（`DSRect.shape` 唯一构造点） | 9 处 `RoundedRectangle` 里只有 `surface` 内部写了 `style: .continuous`，其余 8 处是默认 circular ⇒ 同一张 Card 里 Chip / 描边 / 彩色底接缝对不上 | **这是视觉改动，未验证**：连续曲率是 macOS 原生控件的做法，方向确定，但实际观感要人眼看。另有 `.quaternary` 等层级色走 `tinted` 的泛型参数，抹掉颜色会把「出错」和「中性」画成同一张卡 |
| 动效**保持极少**（全项目只有 1 处） | §3.3 要求「统一缓动与时长，遵循 macOS 观感（**不过度**）」—— 不加错动效比加动频更重要 | 那唯一一处（agent 新消息自动滚动）已从裸 `withAnimation`（SwiftUI 默认 0.25s / default 缓动）改为 `DSMotion.standard`（0.20s easeInOut）。判据卡住「不许新增裸动效」，所以以后加动效必须走 token |
| **看板保留，但重做成原生分组列表** | 看板回答的是仪表盘不回答的问题：「现在哪些项目要我动手」。它不是仪表盘的另一种排版。设计稿里没有看板页，按「规范优先」应当删掉 —— 但那是照着过期规范删可用功能，判据已明确不许（不变量 69） | 横向四列改成 `List` + `Section`：实测 1100pt 窗口下四列挤在左边约 1/3、右边整片空白还要横向滚动。同时删掉 `prefix(4)` 静默截断（列头写 7、只列 4 张，**另外 3 个永远点不到**）与 `BoardSection`（HEAD 起就无调用点的死代码） |
| **里程碑页保留，并加自己的仓库筛选条** | 它是**唯一能改数据**的视图（新建/达成/放弃/删除），仪表盘与项目卡上的里程碑全是只读副本 | ⚠️ 我第一版把筛选写成「从 `model.selection` 读当前范围」，**那是个恒为 nil 的控件**：本页只在 `selection == .milestones` 时才渲染，那个分支永不成立。实测选中 atlas 再进里程碑页，3 个仓库照旧全列。**这是我亲手做出来的第二个「摆而不动」**，已改成页面自己的 `@State` 并配判据钉住。筛选条放**内容区顶部**不放工具栏：实测 SwiftUI 在 1100pt 下会把工具栏 `Label` 的标题压成纯图标，「正在筛 atlas」和「没筛」会长得一模一样 |
| 状态词与看板分列**只推一份**（`ProjectStatus.liveness`） | 同一问题「这项目怎么样」被算过三遍，三遍都错：`boardColumn(for:)` 与 `stateWord` 都依赖 `branches`（**追踪数组**，无远端仓库恒空）。实测 47 天没提交的仓库：看板落进「活跃中」、「停滞」列**恒为 0**，项目卡显示「**正常**」 | 判据钉「视图层不许出现 `status == "stale"` 这类档位字面量」。`liveness` 的两条证据：引擎的 `b.status`（有追踪分支时最精确）+ `daysSinceLastCommit`（30 天线取自引擎自己的 `active30d` 桶，`dashboard.cj:224`，**不是客户端新造的阈值**）。措辞跟着依据走：30 天那条线说「N 天没更新」而不是「停滞」，因为「停滞」是引擎 14 天档位的词 |
| 筛选状态放 `AppModel.dashFilter`，**不放视图 `@State`** | 仪表盘与看板是**两个消费方**。放 `@State` 会有两个后果：视图重建即丢失（切到看板再切回来，筛选悄悄弹回「全量」），以及看板根本读不到（实测仪表盘筛到 1 个时看板还是 3 个） | 判据钉住「`DashboardView` 里不许再出现 `@State private var filter`」且「看板必须真的消费 `model.dashFilter`」 |
| 侧栏行**不许用 `.badge()`** | 实测（本机 macOS 26）侧栏「里程碑」带 `.badge(...)` 时连点 5 次，`selection` 的 didSet **一次都没触发** —— `go()` 根本没被调用。去掉后同一次点击立刻生效。`.badge()` 在 `List(selection:)` 的行上会接管命中测试，点击与选中高亮一起失效，而**外观完全正常** | 症状极隐蔽：那一行看着没毛病、⌘3 也能进。对鼠标用户来说进不去的导航项等于该视图不存在。计数改用行内文字（与「项目（3/3）」同一套做法） |
| `let x: T? = nil` 的存储属性**必须写 `var`** | Swift 合成的 `init(from:)` 对「带初值的不可变存储属性」**直接跳过**，编译期有一句 `immutable property will not be decoded because it is declared with an initial value`。写成 `let` ⇒ 引擎恒发也解不出来，字段永远是默认值 | 本项目因此白丢 **5 个引擎键**（`JournalEntry` 四个 + `ProjectStatus.lastCommitAt`）。其中 `lastCommitAt` 直接让时间窗筛选**在任何数据下都是死控件**。判据改成**按写法**覆盖整族（原来那条是按字段点名，测的三个恰好不是这么写的，于是另外 4 个死键从头到尾没人看见） |
| 时间窗判定挂 **`lastCommitAt`**，不挂 `staleDays` | 原来读 `primaryBranch?.staleDays`，而 `branches` 是追踪数组 ⇒ 无远端仓库恒判「保留」⇒ 「近 7 天」筛不掉任何项目。引擎自己算 `active7d/active30d` 用的是 `lastCommitAt`（`dashboard.cj:213-226`），客户端跟着走才是同一口径 | 算术逐字对齐引擎（毫秒差整除，不用浮点秒），否则边界上差一天。判据加了**与引擎 `active7d` 的交叉验证**，两端数字必须相等。`staleDays == -1`（读不出来）在任何窗口都保留 —— 滤掉等于把「不知道」说成「不在范围内」 |
| 里程碑**分母不含 `unknown`**、明细被截时**必须说出来** | `unknown` 是「仓库读不出来」，算作「没达成」就是把无知说成事实。`items` 没有截断标志而 `readCount` 有，两者不等时按明细算出的分组统计只是**下界** | 里程碑页与管控页都按明细统计并按当前范围统计，**不读全局 `counts`** —— 那个没有项目维度，收窄到单仓库后继续报它就是把全局完成率说成这个仓库的 |
| 侧栏按本应用真有的东西重组为「视图 / 仓库」两组 | 设计稿侧栏是**三**组（双轨协同管道 / Git 结构与进度分析 / 受管 Git 仓库），但它第一组的四个入口 —— 变动管道、AGENT.md 记忆治理、动态 README、Release —— **本项目没有这些功能**。照抄会造一排点进去是空页的入口（与「规范 vs 设计稿冲突时以设计稿为准」同源：那一条的判据就是「不许造空壳入口」） | 对应关系：「视图」≈ 设计稿的「Git 结构与进度分析」，「仓库」≈「受管 Git 仓库」。**没做的**：设计稿第一组那四个入口对应的功能本轮仍未实现（不在改造范围），等真要做时再按「有实现才有入口」补回来 |
| 「添加 / 扫描项目」移出 `List`，进底部动作区 | 它是**动作**不是导航项。原来的写法是侧栏 `List(selection:)` 里一个**没有标题的单项 Section**，正好卡在两组中间，把信息架构切成三段；而且它**没有 `.tag(...)`** ⇒ 实测点击后 Sheet 正常弹开，但 `selection` 被清掉、侧栏跳回「项目详情」那行 —— 这是「点了没反应」的另一种形态。移到 `safeAreaInset`（状态条之上）后两件事一起消失 | 判据加了子断言「动作项不许留在侧栏 `List` 的分组里」。**代价**：它不再随 `List` 一起滚动（滚到底它固定可见）—— 对一个主要入口来说这是想要的 |
| 带计数的侧栏行**只有 `countedRow(...)` 一个构造点** | 视图行有三种写法（`viewShortcut` / 旧的 `.badge()` / 手写 `HStack`）时，只要某个行用 `.badge()`，**它的点击行为就与别的行分叉**，而外观完全正常 ⇒ 只有真点一次才发现。统一到 `countedRow(title:icon:route:target:count:)` 后，分叉在结构上不再可能 | `count == nil` 时**不显示**（读不出来 ≠ 0）；计数为 0 用 `.tertiary` 淡显，避免「0」和「没数」都像在报警 |
| 侧栏徽标报「**有几件事等我做**」，不是「有几样东西」 | 设计稿给「变动管道」打的徽标是 `totalPendingShallowCommits`，也是待办语义。报总数的话每个视图行都是同一个数字，徽标就成了装饰。⇒ 看板报**待处理项目数**（`boardColumn == .attention`），里程碑报 `open + done` | 徽标**不受仪表盘时间窗筛选影响**：徽标回答「**现在**」，筛选回答「我在看哪段时间」。把筛选套上去会让徽标随筛选跳变，而它并不属于任何一个时间窗。判据钉住 `attentionCount` 读的是 `boardColumn` 而不是 `projects.count` |
| **全量更新的「覆盖」由代码保证，不交给模型** | 用户要求「一键全量，对所有仓库，基于 AI agent 执行」。这里把「基于 AI agent 执行」拆成两半：**执行**走 agent 工具通道（`AgentCore.executeTool`，与 agent 对话同一个执行点、同一份工具清单、同一套必填校验），**决定跑哪些**由代码逐个显式传项目名 | 理由：全量卖的就是「一个不漏」这一条。把覆盖交给模型 ⇒ 可能少跑一个，而界面照样显示「全量完成」，用户没有任何线索（**看起来对**是最坏的一类失败）。判据钉住遍历里不许出现 `prefix(` / `.filter` / `.dropFirst`，且必须逐个记账。**代价**：agent 在这一步没有自由裁量权 —— 它不能在发现某个仓库状态特殊时改主意跳过，那是刻意的，见不变量 108 |
| 每一页**各自声明滚动归属**：AI 页不套 `ScrollView` | 切浅色验主题时撞上的真缺陷。`AISettingsPane` 的 `Form` 在 macOS 是 List-backed：套进外层 `ScrollView` 之后，它报给外层的是**整份内容高度**而不是视口高度，于是两件事同时坏 —— ① 外层永远判定「装得下」，滚轮纹丝不动，`Base URL 覆盖` / `测试连接` / 数据说明段**根本够不着**；② sheet 被内容撑到比窗口还高，**页脚被顶出窗口框**。实测（窗口 940×672）：sheet 776×689、位置 y=152；页脚两个按钮落在 y=809，而窗口底边在 772 —— 保存按钮被画在窗口外面、压在桌面上。改法是让 `Form` 自己滚，另两页（普通 `VStack`）照旧套 `ScrollView` | **判据按分支分别钉**，不钉「有没有 `ScrollView`」这个字面量 —— 另两页套它才是对的，只断言总数会把这三条一起判死。外侧（AI 分支 0 层）与内侧（`AISettingsPane` 里有 `Form`）两半都要钉：不套但也没有的话这一页直接退化成不可滚的静态布局。负控 NC91 变体 1 就是**把本轮修掉的缺陷原样改回去**，它必须红 —— 缺陷版和修复版长得极像（都有一层 `ScrollView`），不实测分不出谁是谁 |
| 设置面板尺寸下限 **480×400** | 用户 2026-10-03 原话：「设置窗口有些大，可以小一些」。前提是上一行先修好 —— 内容不再反过来撑大 sheet 之后，`minWidth/minHeight` 才是它的**实际**大小（改之前实测 sheet 就是 776×689） | 判据把 `minHeight` 钉在 **320...520**：上界来自实测（窗口最小 940×672、去掉工具栏约剩 620，超了页脚就会被顶出窗口框），下界是可用性（低于 320 页签栏和页脚要挤在一起）。真 app 已验：三页在 480×400 下都正常，AI 页可滚到最底（`/tmp/ai-end.png`：测试连接 + 数据说明都在，页脚钉住不动），改完模型 id 点进「过滤模型」失焦后「保存」变蓝底亮起 |
| ~~一键全量与顶栏双轨**并存**~~ → **2026-10-02 推翻：撤掉那两个按钮，能力留着** | 上一版的理由是「双轨的范围由 `selection` 推导，停在某个项目上就是「浅更新 · deepDolphin」，所以它没有指向全群的入口」。**用户当场指出这条理由不成立**：「仪表盘那边有浅更新、深更新 全部，所以没必要再多两个」—— 全局范围下双轨的标题**本来就是**「浅更新 · 全部 / 深更新 · 全部」。四个措辞不同、长相差不多的按钮摆在一起，用户按下之前判断不出会动哪些仓库 | **删的是按钮，不是能力**：「全量基于 AI agent 执行」那条要求仍然成立，改由 `AppModel.updateAll` 走 `AgentBulkUpdate.run`（agent 工具通道），入口就是已有的双轨按钮。顺带得到逐仓库结果面板（以前只有一条聚合通知）。判据改成钉**背后那条**：「同一个动作在同一屏里只能有一个入口」+「这一处真能走通到 `updateAll`」—— 按钮可以换位置换措辞，但两处并排就是复发。推广：入口数是**排版问题**，能力是**通路问题**，撤入口时先确认通路还在 |
| 单一仓库的 git 操作**挪到页头**，与「项目说明」并排 | 用户 2026-10-02 原话：「把单一仓库的 git 操作放到顶部吧」+「项目说明平齐吧」。原来那排按钮（拉取/推送/抓取/暂存/恢复）在页面中下部的「Git 操作」卡里，而页头右侧只有「项目说明 + 更新」—— **最常用的两个动作被埋在分支进度、里程碑、日志、托管文档四张卡下面，第一屏根本看不到** | **提交不塞进页头按钮排**：它要一个提交信息输入框，硬塞会让页头多出一整行输入框把标题挤掉。它留在下面的「提交改动」卡里，并**紧跟**按钮排那一组（不隔四张卡）。卡标题随之从「Git 操作」改成「提交改动」—— 只讲提交的卡顶着「Git 操作」的名字会与页头那排对不上。判据钉「按钮排唯一构造点」：两处各写一份，可用性判定（`busyProject`）就会分叉，而那只有真点一次才发现 |
| 「可合入分支」判据**逐字对齐引擎**，客户端不许自己发明 | 引擎 `flow/dashboard.cj:200-208` 早就把 `mergeCandidates` 的判据从 `pendingCommits` 换成 `aheadOfDefault`，还专门写了回归测试 `testDashboardMergeCandidatesUsesAheadOfDefaultNotPending`。**客户端把引擎刚修掉的错误又犯了一遍**（`needsAction` 里写着 `branches.contains { $0.pendingCommits > 0 && !$0.isDefault }`）。真 app 实测：5 个分支 `ahead=1 / pending=0` ⇒ 引擎 `work.mergeCandidates` = 5，客户端判 0 个项目要动手 ⇒ 侧栏「看板 0」而仪表盘「待处理 6」 | 提成有名字的派生属性 `BranchStatus.isMergeCandidate`（三处都要用，抄三份必然漂移）。模型补上 `merged` 键（引擎恒发，模型原来没有）—— 写成 `let merged: Bool` 而不是 `= false`，后者会被合成解码跳过、永远是 false。判据分两层：**源码级**钉三条条件齐全 + `pendingCommits` 不许出现，**行为级**拿契约沙箱的真实 fixture 交叉验证「客户端判的条数 == 引擎 `work.mergeCandidates`」。⚠️ 后者**要求沙箱里有非空样本**：旧沙箱所有仓库都没远端 ⇒ `branches` 恒空 ⇒ 断言 0 == 0 空转着变绿，客户端判据错着也是绿的。为此专门造了一个有远端、且已跑过 update 的仓库（旧判据在它上面判 0、新判据判 1） |
| KPI「项目总数」用 `listed`，「待处理」用**项目数** | 两处都是「同一件事在一屏里给了两个答案」：`total` 只数**采集成功**的（注册 6 个、3 个采集失败 ⇒ 大数字写 3，而侧栏写「仓库（6/6）」、范围选择器写「全部 6 个项目」）；「待处理」原来是 `dirty + mergeCandidates + (untracked>0?1:0)` —— **项目数 + 分支数 + 布尔**三种单位相加。引擎测试注释早就点名过第一个坑（`dashboard.cj:721-722`：「必须钉住『listed 才是注册表条数』，否则下一个人又会去用 total」） | 失败数**不许跟着消失**：降级到副说明（「可读取 3/6 · 采集失败 3 个」），改用 `listed` 是对的，只改一半等于把坏掉的项目藏起来。「待处理」主数字取「有多少个项目要我动手」，与侧栏徽标、看板「待处理」列**同源**（`needsAction`）；分支数进副说明并写清单位（「待合入分支 5 条」）。**页头那一行摘要原来自己又算了一遍**（第四处分叉），现在没有自己的算法 —— `DashKPIBuilder.summaryLine` 只从 `kpis` 数组里读 |
| 「等我动手」的判定必须排在「多久没动」**前面** | 前三处修完、判据全绿之后，真 app 上仍然是侧栏「看板 **1**」而仪表盘「待处理 **3**」。根因不是两处用了不同算法 —— 它们**都**走 `liveness`，链条是通的；是 `liveness` **内部**把 `engineStale` 排在 `needsAction` 前面，于是「又停滞又有活要干」的项目一命中 `return` 就再没机会问 `needsAction`（沙箱里 beacon / legacy 正是这种项目） | **「同一个谓词」不保证「同一个结果」**，中间任何一层都可能短路。所以判据不钉「这几行都在」，钉**判定顺序**。依据有两条：两者不互斥，先命中哪个不该由书写顺序决定；且 `.attention` 列的表头本来就写着「待合入的分支」，按列自己的定义，有待合入分支的项目无论主分支多停滞都该进这一列。**代价照实说**：「停滞」列会因此变小 —— 但信息没丢，每张项目卡仍单独写着「main: 停滞」（那一行与 `liveness` 无关）。推广：每修一处「同一件事两个答案」都要回头找第五处，分叉往往是同一个习惯散在四个地方 |
| 设置**分三个页签**（通用 / 自动化 / AI），不再三张卡平铺 | 原来 `GeneralSettingsView` 是一个 `ScrollView` 里依次放开机自启、定时更新、AI 配置三张卡。窗口 640 高，AI 那张（Provider + 模型 + Key + 测试连接，是设置里最常改的一块）要滚很久才看得到 | **分类按「用户想找哪一块」分，不按卡片分**。页签用分段控件而不是侧栏：窗口最小宽 540，侧栏（~180）会把 AI 表单的两个 `Picker` 挤到换行。窗口最小高从 640 降到 520 —— 分页后每页都短，沿用 640 会让「通用」页下方空一大片 |
| 页脚**按页签切换语义**：AI 页是「取消 / 保存」，另两页只有「关闭」 | 页脚提到所有页共用之后冒出两类坑：①另两页是**即时写入**的（开机自启写系统登录项、定时更新写 `AppModel`），那里没有未保存的改动可保存，摆一个「保存」就是死控件；②「取消」承诺能撤销，可即时写入的两页根本没有可撤销的东西 | 按钮**文案随页签走**（`tab == .ai ? "取消" : "关闭"`）—— 让标签说实话比让标签统一更要紧。判据钉「保存按钮只在 AI 页」+「按 dirty 禁用」+「文案随页签」三条。**代价照实说**：这不是常见的「设置有草稿」模型 —— 要那样得把开机自启与定时更新也改成草稿式（Toggle 拨动不立即写系统），那是行为变更，不在「加个分类 tab」的范围内 |
| 「保存」按**有没有改动**禁用 | 打开设置什么都不改也能点保存 = 一个点下去什么都不会发生的按钮（本项目反复在修的「摆而不动」那族） | 判据钉 `original` 存的是**补过 baseURL 之后**的那一份 —— 拿没补过的那份当基准的话，一打开就恒为「有改动」，按钮永远亮着 |
| 保存失败的消息贴在**页脚**，且失败后送回 AI 页 | 失败可能发生在用户已经切到别的页签之后。消息跟着页签走就看不见，而「点了保存但什么都没发生」是最坏的一种反馈 | 失败一定发生在 AI 页（只有它有 save），所以失败时 `tab = .ai` 把用户送回出问题的那一页，否则他可能停在「自动化」上看着一条与自己无关的报错 |
| 面板里的仓库数**只能有一处来源** | 标题写「· 4 个仓库」（点击时的 `model.projects.count`）而正文写「已注册项目 5 个」（结果里的真值）—— 面板自己跟自己打架，用户没线索该信哪个 | 标题改为取 `report.attempted`。凡是同一个概念在界面上出现两处，两处必须同源 |
| AI 简报那一层**没跑成时必须说出口** | 本机 AI 未配置（`defaults read cn.deepdolphin.app.ai` 不存在）。若静默，界面上「没生成简报」与「生成了空的」长得一样 | 措辞区分三态：跑成了 / 没跑成（附原因与下一步）/ 跑了但没产出。**并且不许把整件事报成失败** —— 更新已经执行完了，报失败会让人以为仓库没被动过。判据只卡「有没有把原因说给用户」，不卡具体措辞 |
| 逐仓库「说明」**复用 `updateOutcomeSummary`** | 工具返回的是引擎原始 JSON。第一版整段塞进结果表格，真 app 一跑就暴露：表格被撑爆，且「哪个文档改了、有没有备份」被埋在 `projectId` / `journalEntry` 里 | 转调项目已有的唯一口径（为缺陷 #211 写的，三态区分 + 备份必须说清在哪），**不另写一份措辞**。明细用**列表**不用 markdown 表格 —— 表格单元不换行，备份路径一长右侧就截断。这条是**截图抓到的，不是想出来的** |
| 全量**先刷新注册表再冻结名单** | 「冻结名单」本来是为了防「跑到一半换名单」，但冻结得太早就是拿**陈旧数据**当全集：app 不知道别的进程（CLI / 另一个终端）改过注册表。实测：用 CLI 加一个仓库后不刷新 app 直接点全量，面板写「已注册项目 3 个，成功 3 个，失败 0 个」，而侧栏已是「仓库（4/4）」—— 第 4 个整行消失，面板还说「全量完成」 | 正确顺序：**占锁仍在任何 `await` 之前**（否则并发会同时改写多个仓库），但名单要在 Task 里、刷新之后取。推广：承诺「覆盖某个全集」的动作，名单必须在**发起时**重新取，界面那份是为了显示不是为了执行 |

### 视觉验证：真 app 截图（本机可直接自证，不必等人眼）

⚠️ 本节此前的前提「无 UI session / 需要人眼」**是错的**，且已推翻：
`launchctl managername` = `Aqua`，`osascript` 可用，`screencapture -x` 能拿到真实屏幕。
所以现在**直接启动真 app、真实点击、截真窗口**：

```sh
export DEEPGIT_HOME=/tmp/dg-rich                      # 沙箱化，不碰用户数据
export DEEPGIT_BIN="$PWD/../../moonGit/target/release/bin/main"
nohup ./deepDolphin.app/Contents/MacOS/deepDolphin > /tmp/dg.log 2>&1 &
osascript -e 'tell application "System Events" to tell process "deepDolphin" to set position of window 1 to {1750, 120}'
osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "deepDolphin") to true'
screencapture -x -R1750,120,1100,720 /tmp/shot.png
# 真实点击：AX click 无响应，必须走 CGEvent（先 move 再 down/up）
```

**靠它抓到的缺陷，离屏 harness 一个都抓不到**（离屏渲染不跑命中测试、
不执行点击、也不加载真实 `NSToolbar`）：

| 缺陷 | 离屏 harness | 真 app |
|---|---|---|
| 侧栏「里程碑」点不动（`.badge()` 吃掉点击） | 拍得到外观，看不出点不动 | 连点 5 次 `selection` 一次没变 ⇒ 抓到 |
| 「近 7 天」筛不掉任何项目（判定挂在追踪分支数组上） | 拍得到筛选行，看不出点了没反应 | 截图对比：全量 3 张卡 → 近 7 天 1 张 |
| 看板「停滞」列恒为 0、47 天的仓库落进「活跃中」 | 拍得到列，看不出分类是错的 | 同上 |
| 侧栏「添加 / 扫描项目」清掉当前选中（无 `.tag` 的行在 `List(selection:)` 里） | 拍得到那一行，看不出点它会跳走 | 点它 → Sheet 弹开但 `selection` 变回「项目详情」⇒ 抓到 |
| 侧栏行三种写法（`viewShortcut` / `.badge` / 手写 HStack）导致点击行为分叉 | **拍不到** —— 离屏不跑命中测试 | 逐个点：看板 / 项目 / 里程碑行各自表现一致才收工 |
| 侧栏行坐标随选中态位移（选项目后项目列表下移 ~28px） | 拍不到（离屏没有选中态） | 每次点击前按**最新截图**用标尺重测坐标，脚本里写死旧坐标会点空 |
| 一键全量的结果面板**把引擎原始 JSON 灌进表格** | 拍得到表格，看不出内容不可读 | 「说明」列是 `{ok, mode, projectId, journalEntry…}`，撑爆面板且把「改了哪个文档」埋掉 ⇒ 抓到 |
| 一键全量**冻结陈旧名单**（漏仓库且报告说「全量完成」） | 完全拍不到（离屏没有「注册表被别的进程改过」这件事） | 用 CLI 往注册表加一个仓库后**不刷新 app** 直接点全量：面板写「已注册项目 3 个，成功 3 个」，侧栏已是「4/4」⇒ 抓到 |
| 同一面板里仓库数**出现两个来源** | 拍得到两个数字，看不出哪个可信 | 标题「· 4 个仓库」vs 正文「已注册项目 5 个」⇒ 抓到 |
| **一屏里三处数字自相矛盾**（侧栏「看板 0」/ 仪表盘「待处理 6」/ KPI「项目总数 3」） | **拍不到** —— 离屏 harness 拿的是固定 fixture，造不出「注册 6 个、3 个采集失败」这种注册表形状 | 打开面板第一眼就看到：侧栏徽标与 KPI 打的不是同一个数，而且大数字（3）比侧栏（6/6）小。三处各自都「有依据」，合起来是三个答案 ⇒ 抓到 |
| 5 个可合入分支被客户端判成 0 个待处理项目 | 拍得到分支列表，看不出「可合入」判成了什么 | 3 个仓库 5 个分支 `ahead=1`，仪表盘「待处理」6 而侧栏「看板」**0** ⇒ 抓到（引擎已修过的错，客户端又犯了一遍） |
| 顶栏「全量浅 / 全量深」与双轨「· 全部」是同一个动作的第二个入口 | 拍得到两个入口，**看不出它们是同一个** | 用户直接指出：「仪表盘那边有浅更新和深更新 全部，所以没必要再多两个」⇒ 撤掉按钮 |
| **前两处都修完之后，仍然是侧栏「看板 1」/ 仪表盘「待处理 3」** | 拍不到 —— 离屏与判据都看不出 | 前两处修完、277 项判据全绿，真 app 上**还有第三处**。根因是 `liveness` 内部把 `engineStale` 排在 `needsAction` 前面，「又停滞又有活要干」的项目被 `return` 短路掉。**这一处是截图逼出来的，判据当时是绿的** |
| 逐仓库面板里「成功 3 个，失败 3 个」下一行却写「**3/6 完成**」 | 拍得到两行字，**看不出是两个词** | 同一个量两套措辞（「成功」/「完成」），用户容易以为分母不同。数字一个都没错，措辞分叉 ⇒ 抓到 |

> ⇒ **判据与真 app 截图是互补的，不是二选一**。判据能钉住「换一份变量名也逃不掉」，
> 截图能钉住「只有真跑起来才暴露」。两边都要。
>
> ⚠️ 本轮还额外确认了一条：**措辞是答案的一部分**。上面最后一行数字全对、
> 判据全绿，却仍然是一处分叉 —— 「一屏之内不许出现两个答案」管的不只是数值。

### 离屏 harness：三种模式（`scripts/render-harness/`）

`scripts/render-harness/run.sh <输出目录> [模式]` 会造沙箱项目、把真实视图
**离屏渲染成 PNG** —— 于是「视觉未验证」不再是永久待办。已用它确认：三态空态文案、
EmptyState、卡片圆角与接缝、分段条配色、间距等值替换后的观感、仪表盘完整内容。

| 模式 | 产出 | 用途 |
|---|---|---|
| 不带参数 | `detail.png` `dashboard.png` | **验内容排版**（顶栏完整、卡片间距与圆角） |
| `window` | 同上，但宿主是 NSWindow | 对照用，内容与默认模式一致 |
| `panel` | `panel.png` | **验顶栏**：侧栏 + 顶栏 + 主区一次拍全 |

**它验不了的**（每条都做过对照实验，细节见 `scripts/render-harness/main.swift` 顶部）：
- **窗口 chrome 的拖拽/缩放、动画、真实交互、真实光标**
- **按钮文字**：快照里 header 位置的按钮只画得出空白底（改成 `Label` 后依旧，
  而同图 `gitOpButton` 正常 ⇒ 是位置/样式的离屏限制）
- **个别行距**：detail header 的两行文字在快照里重叠，改 `spacing: 6`→`8` 后依旧
  ⇒ 不是间距不够，是未挂窗口时行高算不准
- **`panel` 模式顶栏下方不施加安全区**：detail 首行会被顶栏裁掉。同一份视图在
  默认模式下顶栏完整 ⇒ 这是 window 路径的代价，不是布局缺陷。
  ⇒ panel 模式只看顶栏，内容排版回默认模式看

> ⚠️ 本节此前写着「整窗渲染会 SIGSEGV ⇒ 顶栏只能人眼看」，**那条结论是错的**：
> 那次崩溃是 harness 自己的一个无限递归 `log()` 造成的，与 `orderFront` 无关。
> 修正后顶栏已可自动验证（见 `moonGit/AGENTS.md` 不变量 101）。

### 还没做的

- ~~**AI 设置的输入框要失焦才提交**~~ → **2026-10-03 推翻：绑定一直是对的，
  症状来自中文输入法的组字缓冲区**。`或手动输入模型 id` 框里能连续打字，
  但 `draft.model` **看起来**在焦点离开那一刻才更新 —— 表现是「模型」Picker
  与页脚「保存」在打字过程中不动，点了别处才一起变。
  **它不是这个 app 的缺陷。** 逐个排除（全部在 `/tmp/tfrepro` 最小 app 上实测，
  用「模型」Picker 当读数，它读的就是 `draft.model`）：跨视图 `@Binding`
  实时提交；`Picker` 与 `TextField` 共用同一份绑定实时提交；`Form` 套在
  `ScrollView` 里（修复前形态）也实时提交。把 AI 页改回旧形态重新构建整个 app
  再测，**照样实时提交**。
  **真因**：中文输入法把字母扣在**组字缓冲区**里 —— 输入框里看到的是组字预览，
  文本还没交给 app，于是 `draft.model` 自然不动；组字在空格/回车/选中候选
  **或失焦**时才提交，所以看着像「要失焦才提交」。实测：切到 ABC 打字立刻提交；
  切回拼音输入法打 `test`，框里有 `test` 而 Picker 纹丝不动，右下角是候选条
  「1 test」；按一下空格，Picker 立刻变 `test` 而**焦点没动**。
  ⇒ **不需要改代码**。这是所有 macOS 文本框在中文输入法下的共同行为，
  SwiftUI 拿不到组字缓冲区（它归输入法所有），也没有绕过它的正经 API。
  打模型 id 时切英文输入（或按空格确认）即可。
  真 app 已用 mock 数据验完整链路：打 `qwen2-mock` 时 Picker 实时跟随、
  页脚「保存」当场变蓝；切到「通用」再切回来草稿仍在；点「取消」后
  `defaults read cn.deepdolphin.app.ai` 报 Domain not found（确实没落盘）。

- **本轮踩到并纠正的一次误判，值得单独记**：`osascript` 合成按键之后**立刻**读
  AX，拿到的是**滞后一次交互**的界面。头几轮据此得出「`TextField` 绑
  `$draft.x`（乃至跨视图 `@Binding`）不提交」，还照着这个结论改了设计
  （拆成四个 `@State`、拆开 Picker 与输入框的绑定）。加上「点进另一个框」
  之后再读，值**立刻**出现了 —— 绑定一直是对的。
  代价：白白多烧了四轮构建，还把一个**不存在的缺陷**写进了注释和判据。
  教训落成两条：①合成事件驱动界面时，读状态前先泵一次事件循环（挪鼠标或点一下）
  再读；②**探针一次只动一个变量**，否则会把两个原因混成一个 ——
  第一版「跨视图 `@Binding`」和第二版「结构体成员绑定」两个解释，
  都是被同一个测量错误造出来的。
- **同一个症状被量了三次才量对，这条比上面那条更值得记**：
  「打字时下游不动」这个症状，先后被归因给 ① 合成按键读得太早、
  ② `Form` 里 `TextField` 的提交时机、③ `Picker` 与 `TextField` 共用一份绑定。
  **三个都不对。** 两个方法论错误叠在一起：
  - **对照组的两个控件绑同一份状态**。想验证「是不是 `Form` 的锅」，
    就放一个框在 `Form` 内、一个在 `Form` 外 —— 但**两个框都绑 `$draft.model`**。
    两个控件抢同一份存储，互相回写，于是**两个一起坏**，
    看起来「`Form` 内外表现一致 ⇒ 不是 `Form` 的问题」。
    被测的变量压根没被动过，而对照还自带一个额外缺陷。
    ⇒ **A/B 两组必须各有各的状态**，共用被测状态就等于没做对照。
  - **输入法把「没提交」伪装成「绑定坏了」**。中文输入法开着时，
    字母进的是**组字缓冲区**，输入框显示预览但文本没交给 app ——
    症状与「`TextField` 忘了提交绑定」**逐字相同**。
    我在切到 ABC 之后才做的所有探针，全都测不出这条；
    而切 ABC 之前做的那些「测量」，量的是输入法。
  ⇒ 判据（本项目的做法）：**复现一个疑似绑定缺陷之前，先把输入源切成 ABC
  再测一遍**；两者表现不同就说明量到的是输入法。

- ~~**侧栏分组计数徽标**~~ —— **已做**：侧栏重组为「视图 / 仓库」两组（设计稿第一组那
  四个入口本项目没有实现，照抄会造一排空壳入口），看板与里程碑统一走 `countedRow`
  一个构造点，「添加 / 扫描项目」移到底部动作区。真 app 已验（`/tmp/p1-side.png`、
  `/tmp/p4-scan.png`）：点它 Sheet 正常弹开且 `selection` **未变**（移出前会被清回
  「项目详情」）。取舍见上表五行。
- ~~**侧栏窄宽度下的截断未验**~~ —— **已验（2026-10-03）**：在**窗口最小尺寸 940×672**
  下、且沙箱里放一个 60 字长的项目名（`一个名字特别长的项目-用于测试侧栏最小宽度下的截断行为…`），
  侧栏截断成「一个名字特别长的项…」带省略号，底部「添加 / 扫描项目」与搜索框完好，
  计数同步为 7/7（`/tmp/bs-long.png`）。**不是缺陷**。
  - **一处要记的工具坑**：侧栏分隔条（`AXSplitter`）**合成拖拽推不动** ——
    注入的 `LeftMouseDragged` 走不进 AppKit divider 的 tracking loop，试过慢速拖拽、
    带阈值微移、精确命中分隔条的 1pt 宽度，三次全是 0 位移；
    而 `AXValue` 读出来是侧栏宽度（210.0）且**写入返回成功、布局纹丝不动** ——
    又一个「报成功但什么都没做」。
  - ⇒ 所以这个盲区是**用等价条件**验的（窗口最窄 + 最长内容），
    不是靠把侧栏拖窄。两者覆盖的是同一件事：侧栏可用宽度的下界。
- ~~**全量并发的真 app 表现未验**~~ —— **已验（2026-10-03）**：确认框上连点两次「全部更新」，
  结果面板写的是「已注册项目 6 个，本次实际执行 **6** 个，成功 3 个，失败 3 个」——
  **没有跑成两轮**（两轮会是 12 个）。跑完后两个更新按钮底色**精确回到基线**
  （`浅更新 (115,120,131)` / `深更新 (121,125,136)`，与跑之前逐字节相同），
  侧栏 6 个仓库全部还在。逐项目失败原因也分得开：
  atlas / beacon / legacy 成功（带备份路径），fresh / gone / newbie 是 `VOLUME_BLOCKED`
  （外置卷 `/tmp/dg-bad-src` 没挂载），**整批不中断**。
  - **没验到的**：运行**途中**按钮的禁用态。这轮 6 个项目 4 秒内就跑完了
    （3 个在未挂载卷上瞬间失败），禁用窗口太短没抓住；
    跑完后恢复是实测到的，途中只有代码依据（`DualTrackButtons` 上的
    `.disabled(model.updateScopeBusy)`）。想抓它得让真项目慢下来。
- ~~**窗口缩到最小时的 chrome 未验**~~ —— **已验（2026-10-03）**：窗口最小 **940×672**
  （`PanelView` 的 `.frame(minWidth: 940, minHeight: 620)` 加标题栏）。
  逐级请求 800/700/640/600/560/520/500/400 宽，全部被夹回 940×672 —— 下限由代码定死，
  拖不到更小。在这个尺寸下：工具栏 7 个按钮（刷新 / 双轨 / ⋯更多 / AI 助手 / AI 设置 / 搜索）
  全部完整无裁切，「浅更新 · 全部」「深更新 · 全部」两个按钮右边缘还留 20pt 余量，
  四张 KPI 卡与项目卡都退到两列且文字完整（`/tmp/bs-min.png`）。**不是缺陷**。

- ~~**深浅色主题自动切换未验**~~ —— **已验（2026-10-03）**：之前那条写的是「没切过系统深色」，
  实际情况是**深色验透了、浅色一次没验**。切到浅色逐页拍过：仪表盘正常
  （待处理 3 与侧栏「看板 3」一致，`/tmp/light2.png`），设置三页均可读
  （`/tmp/light-set-general.png` / `light-set-auto.png` / `light-set-ai.png`），
  `DSColor.surfaceAlt` 与 `Color.red/green` 在浅色下都正常。
  浅色下暴露出的唯一新问题（AI 页下半段够不着）已修，见上表「每一页各自声明滚动归属」一行。
  窗口最小尺寸下的侧栏截断也已验（见下一条）。
- **一键全量的 AI 简报从未真跑过**：本机 AI 未配置
  （`defaults read cn.deepdolphin.app.ai` 不存在），所以「未生成 AI 简报」那条分支验过了，
  **「生成成功」那条分支没有** —— 简报正文的质量、长度，以及它有没有把逐仓库表
  复读一遍，都还没看过。配好 AI 后必须补跑一次。
- ~~**一键全量没在有失败仓库的数据上跑过**~~ —— 已验：沙箱里放了一个路径被删掉的
  项目，真 app 点全量后那一行单独标 ❌（`gone` 路径失效），**整批不中断**，
  面板标题取的是结果里的真实条数。
- ~~**深更新那一轨没跑过**~~ —— 已验：全量深更新同样 3/3 完成，
  且 atlas 那一轮同时更新了 README.md 与 AGENTS.md（深轨托管范围比浅轨宽，符合语义）。
- **全量的并发没在真 app 上试过**：占锁逻辑有判据（NC88 变体 6），
  但真 app 上连点两次的实际表现没看过（跑批时按钮变灰，
  但那只验了「不能并发发起」，没验「跑完之后按钮恢复」）。
- ~~**顶栏撤掉全量按钮后的双轨入口没在真 app 上点过**~~ —— 已验：顶栏只剩
  「范围选择器 + 浅更新 · 全部 / 深更新 · 全部」，点后者弹确认框
  「将对 **6** 个项目 执行浅更新」，确认后出**逐仓库结果面板**：
  标题「全量浅更新 · 6 个仓库」与正文「已注册项目 6 个」取的是同一个真值；
  atlas / beacon 成功（各自列出改了哪个文档、备份路径在哪），
  legacy「文档没有变化」，fresh / gone / newbie 三条路径已失效各自单独 ❌
  而**整批不中断**；「AI 简报」如实写「未生成：AI 未配置…」并声明
  「更新本身已经执行完毕，结果以上表为准」，不静默也不谎报整件事失败。
- ~~**`liveness` 判定顺序那一处修复没在真 app 上复验**~~ —— 已验
  （`/tmp/v2b-dash.png`）：侧栏「看板 **3**」、页头摘要「6 个项目 · **3** 个项目待处理」、
  KPI「待处理 **3**」三处一致；侧栏「仓库（6/6）」、范围选择器「全部 6 个项目」、
  KPI「项目总数 6」四处一致。beacon / legacy 的卡片状态词从「停滞」变成
  「有未提交改动」，而「main: 停滞」那一行仍在（停滞信息没丢）。
- ~~**详情页页头 git 操作与项目说明并排没验过**~~ —— 已验（`/tmp/v3b.png`）：
  页头右侧一行是「项目说明 | 拉取 | 推送 | 抓取 | 暂存 | 恢复 | 更多」，
  「提交改动」卡紧跟其下不隔卡。
- ~~**一条「声明了却一次没用」的同类缺陷**~~ —— **已修**（2026-10-02，用户「继续」后）：
  `AppDelegate.openPanel()` 里那条「窗口已经开着就直接 focus」的快路径判的是
  `w.title == "deepDolphin"`，而 `PanelView.swift:41` 的 `.navigationTitle("deepDolphin 面板")`
  会覆盖窗口标题（真 app 的 AX 窗口名读到的正是「deepDolphin 面板」）
  ⇒ **那个比较永不成立**，每次都落到下面的通知转发。
  功能没坏（`openWindow(id: "panel")` 同样会把已开的窗口带到前面），
  但注释里写着「NSApp.windows **兜底**」，实际上**只有兜底那条在跑** ——
  与本项目反复修过的「声明了 dismiss 却一次没用」是同一族。
  - 顺带发现**同一段实现被逐字抄了两份**：`AppDelegate` 与 `DockMenuTarget`
    各一份「activate → 找同名窗口 → 前置 → 否则发通知」。标题只是这两份会
    一起漂移的那一部分 —— 换个别的字符串，它们照样会分叉。
  - 修法两条一起走：标题收进 `PanelWindow.title` **一个出处**
    （场景标题、导航标题、窗口识别三处都走它），
    实现收进 `PanelWindow.bringToFront()` **一份**（两个调用点）。
  - 隔离处理照抄本文件既有做法：`applicationDidFinishLaunching` 与
    `NSMenuItem` 的 action 都不是 `@MainActor` 隔离的，而实现是
    ⇒ 用 `MainActor.assumeIsolated`，理由与 `buildDockMenu` / `shallowUpdateAll`
    相同（这些回调必在主线程；`assumeIsolated` 在非主线程会直接断言，
    正好是「别这么用」的提示）。
  - 推广：**一段代码长得像「保险起见的多余代码」时，先问它到底走不走** ——
    走不上的分支不会报错、不会崩，只是让旁边的兜底一直在跑。
- **真机/真数据未跑**：本轮所有验证都在沙箱 `DEEPGIT_HOME=/tmp/...` 里做，
  `~/.deepgit/registry.json` 未动（保持 4710 字节 / sha `b61aaa5a…`）。
- ⚠️ **验证环境的一条记录**：中途出现过「app 进程活着、主线程空闲、无崩溃报告，
  但 AX `count of windows` = 0、全屏截图只有壁纸、`System Events` 连 frontmost
  process 都取不到」。当时判成**屏幕锁定**，其实显示器只是进了睡眠
  （`displaysleep 180`）—— 两者症状一样，判据不同。
  ⇒ 下次再遇到先读 `ioreg -n Root -d1` 的 `kCGSessionScreenIsLocked`，
    再看 `pmset -g` 的 `displaysleep` 与 `screencapture` 能不能按区域截图；
    两者都指向前台/窗口不可达时，**别去改代码**，先判环境。

### 待人工确认：spacing 的 87 处散值

刻度值（4/8/12/16/20/24）已全部换成 `DSSpacing` token（**73 处，零视觉变化**，
因为数值本来就相等）—— 其中 45 处是 Stack 的 `spacing:`，28 处是 `.padding(...)`。

剩下 87 处**故意保留**：

| 值 | 处数 | 分布（文件:处数） |
|---|---|---|
| 40 | 2 | DetailViews(2) |
| 30 | 1 | PanelView(1) |
| 18 | 3 | DetailViews(3) |
| 14 | 13 | DetailViews(6) / AISettingsView(2) / AgentView(2) / AIIntegration(1) / BoardView(1) / PanelView(1) |
| 11 | 1 | BoardView(1) |
| 10 | 20 | DetailViews(7) / BoardView(3) / AIIntegration(2) / AISettingsView(2) / AgentView(2) / MarkdownView(2) / Components(1) / MilestonesView(1) |
| 7 | 5 | MarkdownView(2) / BoardView(1) / Components(1) / DetailViews(1) |
| 6 | 15 | BarView(5) / PanelView(5) / DetailViews(3) / AgentView(1) / BoardView(1) |
| 5 | 9 | AIIntegration(3) / BoardView(3) / DetailViews(2) / BarView(1) |
| 3 | 8 | MilestonesView(3) / DetailViews(2) / MarkdownView(2) / DeepDolphinApp(1) |
| 2 | 8 | BarView(3) / Components(2) / DetailViews(1) / MarkdownView(1) / MilestonesView(1) |
| 1 | 2 | AIIntegration(1) / DetailViews(1)　— 发丝线，不是节奏值 |

> ⚠️ **本节此前写的是「51 处 / 7 档」，那个数是漏算的。**
> 旧判据的正则只匹配 `spacing: (\d+)`（Stack 参数），**完全不匹配
> `.padding(.edge, N)` 与 `.padding(N)`** ⇒ 28 处刻度值 padding 逃过检查，
> 1/11/18/30/40 五档散值也从未被计入，基线 51 其实是「被看见的数」不是「实际的数」。
> 覆盖面补齐后重算为 87 处 / 12 档（**不是新增违规，是第一次被看见**）。
> 30/40 明显不是节奏值而是结构性留白（面板分隔、hero 区），
> 记在这里是为了将来收敛时知道它们存在。通用判据见 `moongit` 不变量 102。

**为什么不一刀切收进刻度**：那是**改布局**、不是重构。14→16 挤不挤、
10 该变 8 还是 12，得看着窗口才知道。离屏 harness 现在能给出**快照级**的观感
（它已验过顶栏不挤、卡片间距与圆角接缝没问题），但**快照不是真窗口**：
深浅色主题、窗口缩到最小时的截断、真实字体渲染都拍不到 ⇒ 仍不擅自收敛。
等有人真正看过窗口，再逐档收掉。判据把基线钉死在 87 处
（`client-check.sh` 不许它增长，负控 NC81 5/5），通用判据见不变量 96。
