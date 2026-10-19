# 跨端能力差距台账（PARITY-LEDGER）

**用途**：把「mac 端有什么 / 引擎有什么 / deepin 还差什么」摊成一张可勾选的账，
免得每批都靠记忆重新比一遍。**每落一项就改本表**（状态 + 落点 + 判据）。

- 最近审计：2026-10-19（第二次，**基线已更新**）
- 审计基准：引擎仓 `../moongit` **`dev` 分支**（`d363b6a`）、mac 端 `macos/`（`d62e429`）、deepin 端 `deepin/`
- 审计方法：① mac 源文件 → deepin 源文件逐个对位 + 判定层逐条比对；
  ② 引擎命令面枚举（CLI 24 命令 / `tools --json` 28 工具 / MCP `tools/list` 33 工具）反查客户端消费点；
  ③ 引擎 `docs/graph-scene-schema.md` 契约清单逐条对 deepin 实现。

> ⚠ **第一次审计（2026-10-19 上午）作废**：当时误判「网络不通」，没拉远端，
> 漏掉了 mac 端 10-07→10-13 的 **30 个提交 / 7919 行**与引擎 `dev` 分支的 **49 个提交**。
> 本表是拉齐后重做的版本。

---

## A. mac → deepin：**已对位，无需动作**

判定层逐条比对（不是「有同名文件」，是**口径逐字对齐**）：

| 能力 | mac 落点 | deepin 落点 | 核对结论 |
|---|---|---|---|
| 刷新合并门闩 | `ClientDecisions.swift` | `logic/ClientDecisions` | 一致 |
| 提交构成 12 色 | `CommitTypeComposition.swift` | `logic/CommitTypeComposition` | 一致 |
| 仪表盘 KPI 口径 | `DashboardScope.swift` | `logic/DashboardScope` | 一致：**项目总数用 `listed` 不是 `total`**；里程碑分母不含 `unknown`；分支数用 `repoBranchCount` |
| 「等我动手」判定顺序 | `Model.swift` | `logic/Derived.cpp:56` | 一致：**`needsAction` 必须在 `engineStale` 之前** |
| 可合入分支判据 | 引擎 `aheadOfDefault` | `logic/Derived.cpp:32` | 一致 |
| 状态词档位 | `Models.swift` | `logic/Derived.cpp:74` | 一致（`activeDays30` 线） |
| 里程碑未知态 | `MilestoneCard.swift` | `logic/Derived.cpp:217` | 一致（`unknown` 不进徽标/分母） |
| 引擎错误五类文案 | `EngineFailure.swift` | `models/EngineFailure` | 一致 |
| URL 错误脱敏 + host:port | `AIErrorMessage.swift` | `ai/AIChannel.cpp` | 一致（deepin 把三者并进 AIChannel） |
| 提交数分母口径 | `CommitCountScope.swift` | `models/StatusTypes.h:103` | 一致 |
| 侧栏「视图 / 仓库」两组 + 计数 | `SidebarView` | `ui/SidebarNav` | 一致 |
| 设置三页签 | `AISettingsView.swift` | `ui/dialogs/panes/*` | 一致 |
| 快捷键（13 个，撞键内置判定） | `ShortcutMap.swift` | `logic/ShortcutMap.h` + PanelWindow 全量真绑 | 一致（Ctrl 代替 ⌘） |
| 文档平铺 / Markdown | `MarkdownView.swift` | `ui/common/MarkdownView` | 一致 |
| 一键全量 | `AgentBulkUpdate.swift` | `AppModel::updateAll` | 一致 |
| 双轨更新 + AI 变体 | `UpdateActionMenu` | `ui/DualTrackButtons` + `runUpdateDigest` | 一致 |
| 引擎未装 → 安装引导 | `DeepDolphinApp.swift` | `ui/pages/SetupGuidePage` | 一致 |
| 托盘 / 通知 / 开机自启 | `BarView` / `AppDelegate` | `tray/` / `app/Notifier` / `platform/AutostartManager` | 一致（平台 API 不同，能力口径同） |
| 外部打开（git remote → 浏览器） | `SysOpen.swift` | `platform/SysOpen` | 一致 |
| **文档完整性校验**（引擎 verify 四态） | ⬜ 未接 | ✅ 2026-10-19 | **deepin 领先**（见 D 节债） |
| **交互架构图页**（scene 契约 + 平台 Canvas + 视口/命中 + 生成/导出） | ✅ sheet 版（`ArchPage` + `ArchCanvasView`） | ✅ 批 D1 内核 + 批 D2 页面（独立 `DDialog`） | **能力已对齐**；承载形态不同（DDE 无 sheet，且架构图要大画布 → 独立窗）；deepin 另有**回执路径提取更准**一处（见 D 节债） |

---

## B. 新 mac 基线（`d467a4f..d62e429`，30 提交）带来的能力 —— **本轮主战场**

mac 端这 30 个提交**只动了 `macos/`（46 文件）+ `website/`**，`deepin/` 与 `linux/` 一行未动。
逐项拆开：

| # | 新能力 | mac 落点 | deepin 现状 | 优先级 |
|---|---|---|---|---|
| B1 | **交互架构图（scene 契约 + 平台 Canvas）** | `GraphScene.swift` + `ArchCanvasView.swift` + `ArchPage.swift` | 🟢 **已对位（批 D1 内核 + 批 D2 页面）**：契约层 + Qt QPainter Canvas2D 26 方法 + 渲染指令层 + 视口/命中判定 + 架构图窗（页头/回执/画布/披露行）+ 详情页入口 + 生成/导出动作 | **P0** |
| B2 | **代码图谱页** | `CodeGraphPage.swift`（1156 行）+ `CodeGraphHeatmap.swift`（693 行） | 🟢 **已对位（批 E2 两栏 + 批 E3 热力图模式）**：顶栏 + 左栏（列表树 **⇄ 热力图** 两模式，mac 同款形状）+ 右栏详情三页签（源码/置信度/关系）+ 搜索 + 生成/导出 + 分数 + 截断披露 | ~~P0~~ 已完成 |
| B3 | **符号热力图（treemap → 力导向气泡，Canvas 驱动）** | `CodeGraphHeatmap.swift`（693 行，核心算法 ~380 行） | 🟢 **已对位（批 E3）**：核心算法 ~380 行移植成纯函数 `logic/HeatLayout`（作用域切分 / 分带铺排 / 3 轮重心扫描 / 通道车道走线 + Catmull-Rom / 契约热色 / 黄金角身份色），外壳换成 `ui/HeatmapWidget`（走 D1 的 `Canvas2D` 内核，30fps 动画可见性停表，按实测算内容高度给滚动条）；左栏点文件卡下钻到符号层、点符号卡联动右栏详情 | ~~P1~~ 已完成 |
| B4 | **补丁体检（diff → 置信度 → 人工标注）** | `GraphPages.swift` 补丁段 | 🟢 **已对位（批 F）**：三层体检全接 —— Layer 1 算法层（引擎 `graph patchconf <项目> --patch <diff>`：总分 + S1–S10 信号 + 实体 + 拿不准的项 + 诊断披露）、Layer 2 人工裁决（逐项选「已确认/未确认/存疑」，默认存疑 0.5）、Layer 3 合并终稿（引擎 `graph patchconf --merge`）；另接 `--skill` 取 Layer 2 任务书（markdown，Text 契约）；低置信度实体默认收起、点开给 diff 实码 | ~~P1~~ 已完成 |
| B5 | **关系树（`graph tree`）** | `GraphService.loadTree` | 🟢 批 E2 已接（三源之一 → 文件/目录/符号树骨架，排序/汇总/可见行都在 `logic/CodeGraphBuild`） | ~~P1~~ 已完成 |
| B6 | **函数级图谱 + 置信度**（`graph functions` / `graph confidence`） | `GraphService.loadFunctions` | 🟢 批 E2 已接（函数级疑点归属到符号、置信度孤儿疑点归属到文件、置信度总分与语法树降级说明、详情页「置信度」页签） | ~~P1~~ 已完成 |
| B7 | **固定文档页** | `DocsPages.swift`（321 行） | 🟢 **已对位（批 G）**：四类目（关于 / 帮助 / 开源感谢 / 更新日志）内容层 `logic/DocPages`（写死在代码里，不取引擎）→ 文档窗 `ui/DocsDialog`（顶部分段切类目 + markdown 渲染）→ 面板菜单「关于 / 帮助」入口；内容按 **deepin 的事实**另写（Qt 6 + DDE / DTK），不抄 mac 的 Swift / macOS 文案 | ~~P2~~ 已完成 |
| B8 | **四语言本地化（全应用接入）** | `L10n.swift`（2108 行） | ⬜ 未开始（deepin 现无 i18n；引擎侧 CLI 已双语） | P2（量大） |
| B9 | **原生菜单栏三件套（关于/帮助/设置）+ 设置统一为系统原生窗口** | `DeepDolphinApp.swift` | 🟡 **批 G 已接「关于 / 帮助」**（面板菜单 → 文档窗；DDE 无原生菜单栏对位物，改为面板菜单承载）；**「设置」仍是对话框**（`AiSettingsDialog`，三页签），非「原生独立设置窗口」 | P2（剩设置窗） |
| B10 | **仪表盘项目卡片整卡可点** | `DashboardParts.swift` | 🟢 **已对位（台账原记「未开始」有误，批 G 复核时更正）**：`ProjectProgressCard::mouseReleaseEvent` → `goProject`（`Card` 是 QFrame 不吞鼠标事件，事件冒泡到卡片）；另有 mac 同款的「进入管控 →」钮 | ~~P3~~ 已完成 |
| B11 | **Agent 补齐 18 个图能力工具**（契约检查第 12 组抓到的清单漂移） | `AgentCheck` | 🟢 **已对位（批 E1）**：28 个工具全接（命令形态抽成纯函数表 `logic/AgentToolPlan`，可无头判）；`deepDolphin --agent-tool-names` 出客户端权威清单，contract-check 第 12 组与真引擎 `tools --json` 严格对位（**CI 第 10 门**） | ~~P0~~ 已完成 |
| B12 | **9 语言语法高亮** | mac 原生 `AttributedString` | 🟢 **已对位（批 H）**：判定层 `logic/SyntaxHighlight`（九语言关键词表 + 单遍扫描 → 关键字/字符串/注释/数字四类 token 段）、涂色层 `ui/CodeHighlighter`（QSyntaxHighlighter，颜色取自 DS 令牌）、接到代码图谱页源码页签（高亮语言跟着选中符号的 `lang` 走）；**九种语言与引擎 `detectLang` 逐条对齐**（契约门第 16 组用真引擎跑九种扩展名比对） | ~~P2~~ 已完成 |
| B13 | **性能审计**：动画时钟可见性暂停 + formatter 静态化 | `21c7082` | 🟢 **批 M 已对位**（且补上 mac 侧没有的项）：**可见性暂停**deepin **本来就有** —— 实测（2026-10-19，Qt 6）**父窗口隐藏会给子控件发 `hideEvent`**，所以架构图与热力图的 `hideEvent → m_anim->stop()` 真的停得住，两处都是 33ms（≈30fps），与 mac 修完后的口径一致；**formatter 静态化**已做（日期格式化走 `Qt::ISODate` 枚举，不建格式串）；**另补 mac 没做的三项**：Canvas font 简写按 CSS 口径解析（`pt` 也不再被吞）、Canvas2D 的 QFont 按串静态缓存 + 同串跳过、热力图三处每帧分配收掉 | ~~P3~~ 已完成 |
| B14 | **设计系统存量清零**（字号/散值收进 token，基线 87→95） | `e9d6074` | 🟢 **批 N 已对位**：M3-3 登记的 **4 处字号散值**全收进 `DS::FontPx`（徽章 11 / 等宽 13），D2 门上限 **4 → 0**；另收口 3 处门形式不全才照出的真散值（alpha `0.18` → `DS::Alpha`、底轨遮罩 → `DS::trackMask()`、热力图深色画布五档 → `HeatLayout::Canvas`）。**门从「只盯 `#RRGGBB`」补成全形式检测**（3/6/8 位 hex、`QColor(r,g,b)`、`QColor(0x..)`、`rgb()`、带裸 alpha 的 `rgba()`、`setPixelSize`/`setPointSizeF` 数字参数、QSS `font-size` 字面量、含 `font-size:` 文件里的裸数字 `.arg(N)`）—— 旧门的「4 处存量」其实只是「4 处**写成 hex 形态**的存量」。**豁免改为显式登记**（`D2_EXEMPT` 清单：`keep` 永久 / `fix` 待收敛且**归零即红**，白名单不许腐化） | ~~P3~~ 已完成（**状态语义色第二份定义**另立批 O，见下） |
| B15 | **引擎获取链新增 GitHub Releases 自动下载** | `macos/build.sh` | 🟡 **批 P 已接（deepin 侧完整，mac 侧有缺陷）**：判定层 `logic/EngineDownload`（查 API → 按平台挑资产 → sha256 校验 → 落盘路径 → **七类失败各说各的**）+ 执行层 `app/EngineInstaller`（网络/解压全异步，不卡 GUI）+ 设置·通用页「引擎」卡（下载并安装引擎）+ 发现链认得新落盘位 `~/.local/libexec/deepdolphin/moongit`（排在 `~/.local/bin` **之前**，mac 的教训：客户端自带的优先，否则永远选到过期安装版）；契约门第 21 组端到端验（file:// 打桩跑完整链 + 校验和不匹配**拒绝安装且不落盘** + 真 GitHub API 解析） | P2（**待引擎侧发版**：latest v0.1.0 **只有 darwin-arm64 资产**，无 Linux x64 ⇒ 当下真机上点「下载引擎」会得到「该版本没有 Linux x64 安装包」。引擎的 release workflow **已产出** Linux 包，**引擎仓不用改**，下次发版即生效） |
| B16 | **关系树 / 图谱的导出动作**（查 + 生成 + 导出三件套） | `d62e429` | 🟢 **已对位（台账原记「未开始」有误，批 G 复核时更正）**：架构图页 = 查（`graph arch --format scene`）+ 生成（`arch gen`）+ 导出（`render arch`）；代码图谱页 = 查（`graph tree`/`confidence`/`functions`）+ 生成（`index gen --stats` + `confidence gen`）+ 导出（`render index --confidence`） | ~~P1~~ 已完成 |

**引擎侧对应的新能力**（deepin 消费点）：

| 引擎命令 / 工具 | 用途 | deepin 现状 |
|---|---|---|
| `graph arch --format scene` | 场景 JSON（B1 的数据源） | ✅ 批 D1 已接（内核）+ 批 D2 已接（页面） |
| `graph overview` / `symbol` / `impact` / `tree` / `functions` | 图谱五件套（B2/B5/B6） | 🟢 **五件套全接**：批 E2 接 `tree` / `functions`（代码图谱页三源之二）；批 I 接 `overview`（页头项目级概览）、`symbol`（关系页签「引用来源」）、`impact`（关系页签「影响面」）—— ⚠ 后两者**mac 侧只有服务函数、UI 没接**（仅 agent 工具能用），deepin 接进 GUI 属**领先 mac** |
| `graph confidence` / `patchconf` | 置信度与补丁体检（B4/B6） | 🟢 批 E2 已接 `confidence`（置信度总分/维度/疑点 → 详情页「置信度」页签 + 热力图热色输入）；批 F 已接 `patchconf` 三形态（`--patch` / `--skill` / `--merge` → 补丁体检窗三层） |
| `arch gen` / `graph gen` / `index gen` | 生成（B16） | 🟡 批 D2 已接 `arch gen`（架构图页「生成」钮）；`graph gen`/`index gen` ⬜ |
| `render arch` | 导出交互 HTML（B16） | 🟡 批 D2 已接（架构图页「导出」钮；落盘 HTML 是引擎层交付物，**不是**本平台的渲染路径） |
| `codegraph_*`（CLI 清单 18 个新工具） | agent 工具循环（B11） | 🟢 批 E1 已接 |
| `render` 工具 | 渲染交付物 | 🟢 批 D2 已接 `render arch`、批 E2 已接 `render index --confidence`（回执型命令走 Text 契约） |
| `index_*` 家族 | 代码索引（`graph` 的新家） | 🟡 批 E2 已接 `index gen --stats`（代码图谱页「生成」钮）；**批 L 已接 `index overview`（索引状态行）+ `index update`（增量更新钮）**；`index query` ⬜ **判定不接 GUI**（与已接的 `graph functions` 高度重叠 —— `tier`/`findings`/`weight` 两边都有，接它会造出第二个真相源；仍可经 agent 工具面用） |
| `doctor --json` | 环境自检（**退出码 1 但 stdout 是合法 JSON**） | 🟢 **批 J 已接**（设置·通用页「环境自检」卡；`result` 是自由文本；`problems` 缺键记「未知」） |
| `report <项目>` | 进度报告导出（**回执型命令，回执在 stderr**） | 🟢 **批 J 已接**（详情页「导出报告」入口 + 报告卡 + 「打开报告」） |
| `config list` / `config get` / `config set` | 引擎配置（**策略面**：浅更新分支上限 / 文档备份份数 / 受管文档 / 扫描根） | 🟢 **批 K 已接**（设置·通用页「引擎配置」卡；`config set` 回执也在 stderr） |
| `confidence query` | 置信度只读快照 | ⬜ **判定不接 GUI** —— 是 `graph confidence` 的**子集**（少了 `findings[]` 逐条疑点），接了反而丢信息；仍可经 agent 工具面用 |
| `index overview` / `index update` / `index query` | 持久化代码索引 | ⬜ 未接 GUI（`index query` 带调用方/被调方 + `tier`，是 `graph symbol` 之外的**新维度** —— 下一批候选） |
| `arch query` / `arch update` | 架构索引 | ⬜ 未接 GUI（与架构图页的 scene 数据重叠，接了会造出第二个真相源） |
| `graph db` / `confidence db` | 单文件 SQLite（给 agent 用 SQL 查） | ⬜ **判定不接 GUI** —— 无 GUI 对位物；客户端零业务数据写入的纪律已满足（经引擎写） |
| `track` / `hook` / `mcp` / `skill` | 钩子 / MCP 宿主 / 教学包 | ⬜ **判定不接 GUI** —— 无 GUI 对位物 |

---

## C. 引擎能力面（`dev` 分支，2026-10-19 实测）

| 面 | 数量 | 说明 |
|---|---|---|
| CLI 命令 | 24 | 另有 `graph`/`index` 子命令族（`dev` 分支新增，main 上没有） |
| `tools --json`（agent 工具清单） | **28** | 原 10 + 18 个图/置信度工具（mac 的 B11 就是补这 18 个） |
| MCP `tools/list` | **33** | 进度 14 + 图谱 6 + 补丁置信度 3 + 其他 |
| 契约文档 | `docs/graph-scene-schema.md` | 两层契约：Canvas2D 子集（26 方法）+ scene JSON v1 |

> ⚠ 章程 §4 写的「23 工具」也已过期（dev 分支实测 33）—— 属引擎仓的账，本仓只记事实。

### C.1 引擎命令逐条判定（2026-10-19 实测后全表覆盖）

**接了 = deepin 端有 GUI 入口；判定不接 = 明确记了理由**。
⚠ **但「判定不接 GUI」≠「判定不接能力」这句话要分情况**（2026-10-19 实测引擎的 28 个
agent 工具清单后修正，README 决策 199）：
- **在 agent 工具面里**（客户端能经模型调）：`arch query` / `arch update` / `index query` /
  `confidence query` —— 引擎的 `tools --json` 里确实有这四个。
- **也不在 agent 工具面里**（只能走命令行/宿主）：`graph db` / `confidence db` / `track` /
  `mcp` / `skill` —— 引擎的 28 个工具里**没有**它们。`graph db` / `confidence db` 本来就是
  「给 agent 用 SQL 查的单文件 SQLite」，但那是指**让 agent 自己写 SQL 查库**，不是
  引擎把命令暴露成工具。台账原话「多数仍可经 agent 工具面使用」对这几条**不成立**。

| 命令 | 判定 | 落点 / 理由 |
|---|---|---|
| `list` | ✅ | 项目列表（主界面） |
| `add` | ✅ | 项目列表「添加」 |
| `remove` | ✅ | 项目列表「移除」 |
| `scan` | ✅ | 项目列表「扫描」 |
| `status` | ✅ | 详情页现状 |
| `update` / `deep` | ✅ | 详情页「更新」/「深度更新」 |
| `journal` | ✅ | 进度日志（详情页） |
| `git pull/push/commit/stash/unstash/fetch` | ✅ | 详情页提交区 + 顶栏 fetch/pull/push |
| `milestone add/list/done/drop/remove/reopen` | ✅ | 里程碑页（增删改完成） |
| `dashboard` | ✅ | 仪表盘页 |
| `context` | ✅ | agent 上下文包（agent 侧） |
| `docs` | ✅ | 详情页「项目说明」 |
| `tools` | ✅ | agent 工具面（28 工具） |
| `verify` | ✅ | 详情页「文档完整性」卡（四态） |
| `report` | ✅ | **批 J**：详情页「导出报告」+ 报告卡 |
| `doctor` | ✅ | **批 J**：设置·通用页「环境自检」卡 |
| `config list/get/set` | ✅ | **批 K**：设置·通用页「引擎配置」卡 |
| `graph overview` | ✅ | **批 I**：代码图谱页页头概览 |
| `graph tree` | ✅ | 批 E2：左栏符号树 |
| `graph symbol` | ✅ | **批 I**：关系页签「引用来源」 |
| `graph impact` | ✅ | **批 I**：关系页签「影响面」 |
| `graph arch --format scene` | ✅ | 批 D2：架构图页（Qt QPainter Canvas） |
| `graph confidence` | ✅ | 批 E2：置信度页签 |
| `graph patchconf` | ✅ | 批 F：补丁体检（三形态） |
| `graph db` | ⬜ **判定不接 GUI** | 给 agent 用 SQL 查的单文件 SQLite；GUI 无对应物（客户端零业务数据写入的纪律已满足 —— 经引擎写）。⚠ **不在 agent 工具面里**（决策 199 实测：28 个工具里没有它）⇒ 只能走命令行，不是「agent 能用」 |
| `arch gen` | ✅ | 批 D2：`graph arch --format scene` 走的是同一份 arch.json |
| `arch update` / `arch query` | ⬜ **判定不接 GUI** | `query` 与架构图页的 scene 数据重叠，接了会造出**第二个真相源**；`update` 是探针增量，无 GUI 对位物 |
| `index gen` | ✅ | 批 E2：代码图谱页「生成」 |
| `index overview` | ✅ | **批 L**：代码图谱页索引状态行 |
| `index update` | ✅ | **批 L**：代码图谱页「增量更新」钮 |
| `index query` | ⬜ **判定不接 GUI** | 与已接的 `graph functions`（关系页签在用）**高度重叠**（`tier`/`findings`/`weight` 两边都有，`defs[]` 只是 `functions[]` 的重排）→ 接它会造出第二个真相源；仍可经 agent 工具面用 |
| `confidence gen` | ✅ | 批 E2：置信度生成 |
| `confidence query` | ⬜ **判定不接 GUI** | 是 `graph confidence` 的**子集**（少了 `findings[]` 逐条疑点，多了 `indexUpdateCount`/`generatedAt`）→ 接了反而丢信息；仍可经 agent 工具面用 |
| `render arch` | ✅ | 批 D2：架构图导出 HTML（引擎层交付物） |
| `render index` | ✅ | 批 E2：代码图谱导出（交互 HTML） |
| `config` 的 `ai` 段 | ⬜ **刻意不接** | 引擎自报「AI 由客户端层负责」，`config.ai` 恒为 `{}` —— 客户端的 AI 设置在 `app/Settings`，两处各有一份会形成**两个真相源** |
| `track` | ⬜ **判定不接 GUI** | 进度快照（**钩子的内部实现**：批 Q 装的钩子跑的就是 `moongit track --quiet --source hook`），无 GUI 对位物；**不在 agent 工具面里** |
| `hook` | 🟢 **批 Q 已接** | 设置·自动化页「提交后自动记录进度」卡（装/卸 + 逐项目状态）。**mac 侧未接**（`macos/Sources/` 一处 `hook` 调用都没有）→ 两端都缺，接了是 deepin 领先。⚠ 实测确认引擎的托管块机制**不吞用户内容**：install 追加在用户钩子之后、uninstall 只删托管块（契约门第 22 组钉成断言） |
| `mcp` | ⬜ **判定不接 GUI** | 以 MCP 服务器运行（供 Claude 等**宿主**接入）—— 客户端是 GUI，不是宿主 |
| `skill` | ⬜ **判定不接 GUI** | agent Skill 教学包，给 agent 用 |

---

## D. 跨端一致性债（**deepin 领先 mac / linux 的部分**）

章程 `PLATFORM-CHARTER.md`：「交互 UI 各平台自由，**能力必须一致**」。

| 能力 | deepin | mac | linux | 补齐批次 |
|---|---|---|---|---|
| 文档完整性校验（引擎 `verify` 四态） | ✅ 2026-10-19 | ⬜ 未接 | ⬜ 未接 | 后续批次 |
| 图谱 Canvas 内核（26 方法 + scene 契约） | ✅ 批 D1 | ✅（SwiftUI 版） | ⬜ 未接 | 后续批次（仓颉 Canvas 移植） |
| 交互架构图页（窗口 + 视口/命中 + 生成/导出） | ✅ 批 D2 | ✅（sheet 版） | ⬜ 未接 | 后续批次 |
| 导出回执里的 HTML 路径提取 | ✅ 批 D2（按词边界 + 全角分隔符扫） | ⬜ **抽不到** —— `extractHTMLPath` 按空格切词，而引擎真实回执是「已重绘：`<路径>` · 第 N 版」（路径与文案用**全角冒号**粘连），切出来的 token 不以 `/` 开头 → 判定恒假 → 导出后「打开」入口**始终不出现** | ⬜ 未接 | mac 侧后续批次（**本轮次序是先搞定 dde**，未改 mac） |
| agent 开关型参数（`--force`/`--violations`） | ✅ 批 E1（字符串形态与布尔同等对待） | ⬜ **恒假** —— 引擎把 `params` 声明成**全 string 型必填**，模型发的是字符串；mac 用 `as? Bool` 判定 → 恒不成立 → `--force`/`--violations`/`--confidence` 实际从未生效 | ⬜ 未接 | mac 侧后续批次 |
| agent `git_pull_push` 的 op 白名单 | ✅ 只放行 `pull\|push`（**与引擎工具契约一致**：`op(pull\|push)`） | ⬜ 放行 `fetch`（**超出引擎契约** —— 引擎的 git 白名单里没有 fetch，模型要 fetch 也给不了） | ⬜ 未接 | mac 侧后续批次 |
| 补丁体检（引擎 `patchconf` 三层） | ✅ 批 F | ✅（`PatchCheckPage`） | ⬜ 未接 | linux 侧后续批次 |
| 终稿的「已复核 N 条」 | ✅ 批 F（读 `diagnostics.reviewed_by_agent`） | ⬜ **永远不显示** —— mac 读顶层 `reviewed` 键，但引擎的终稿载荷里**没有**这个键（实测：复核数在 `diagnostics.reviewed_by_agent`）→ mac 的「已复核 N 条」恒不出现 | ⬜ 未接 | mac 侧后续批次（**本轮次序先搞定 dde**，未改 mac） |
| 补丁体检的承载形态 | ✅ 批 F：详情页入口 → 独立窗（项目名在入口锁定） | ✅ 面板级页（`PanelView` 的 `.patchCheck`） | ⬜ 未接 | —— 形态不同、**能力一致**（章程：交互 UI 各平台自由） |
| **引擎自检**（引擎 `doctor --json`） | ✅ 批 J：设置·通用页「环境自检」卡（判定层 `logic/EngineDoctor`，按引擎口径的 `problems` 判档；`result` 是自由文本不按 `=="OK"` 判健康；缺 `problems` 键记「未知」不回落成 0） | ⬜ **完全未接** —— `macos/Sources/` 里**一处 `doctor` 调用都没有**（2026-10-19 复核） | ⬜ 未接 | mac 侧后续批次（**本轮次序先搞定 dde**，未改 mac） |
| **进度报告导出**（引擎 `report`） | ✅ 批 J：详情页页头「导出报告」入口 → 报告卡（回执 + 落盘 .md 路径 + 「打开报告」） | ⬜ **完全未接** —— 同上，`macos/Sources/` 无 `report` 调用 | ⬜ 未接 | mac 侧后续批次（**本轮次序先搞定 dde**，未改 mac） |
| 回执通道（stdout 优先 / 空则 stderr） | ✅ 批 J：`EngineCli::receiptText` | ⬜ 未知（mac 侧没有 `report` 这类回执在 stderr 的命令，暂不构成差异） | ⬜ 未接 | —— |
| 回执里的 ANSI 颜色码 | ✅ 批 J：判定层 `ArchReceipt::plain` 剥掉再显示（引擎**不认 NO_COLOR**，实测 2026-10-19） | ⬜ 未知（mac 未接 report） | ⬜ 未接 | —— |
| **引擎配置**（引擎 `config list`/`set`） | ✅ 批 K：设置·通用页「引擎配置」卡（浅更新分支上限 / 文档备份份数 / 受管文档 / 扫描根；前两项可改） | ⬜ **未接** —— `macos/Sources/` 无 `config` 调用；但 mac 的 `Models.swift` 注释已点出「按 `backupKeep` 裁剪，而用户从不知道它存在」 | ⬜ 未接 | mac 侧后续批次（**本轮次序先搞定 dde**，未改 mac） |
| 引擎配置的 `ai` 段 | ✅ 批 K：**不解析**（引擎自报 AI 由客户端层负责，`config.ai` 恒为 `{}`） | ⬜ 未接 | ⬜ 未接 | —— 引擎 AI 无关，客户端不许从引擎读 AI 设置（两个真相源） |
| **持久化索引状态**（引擎 `index overview` / `index update`） | ✅ 批 L：代码图谱页「增量更新」钮 + 索引状态行（代数 / 节点 / 边 / 文件 / 探针时间） | ⬜ **未接** —— `macos/Sources/` 无 `index overview`/`index update` 调用 | ⬜ 未接 | mac 侧后续批次（**本轮次序先搞定 dde**，未改 mac） |
| 索引状态与页头概览的口径 | ✅ 批 L：两者**不是一回事**且界面分开摆 —— 概览读实时扫描（`graph overview`），索引状态行读持久化索引（`index overview`）。此前「生成」写索引但界面不读它，点完看不到变化 | ⬜ 未接 | ⬜ 未接 | —— |
| **Canvas font 简写按 CSS 口径解析** | ✅ 批 M：判定层 `logic/CanvasFont`（`px` 与 `pt` 都认）—— 修掉「`11pt` 被当成字体族名吞掉、字号根本没设上」的**移植语义缩水**；平台侧按串静态缓存 QFont + 同串跳过 | ⬜ 未接（mac 侧用浏览器原生 font 简写，无此坑） | ⬜ 未接 | —— |
| **引擎获取链（GitHub Releases 下载安装）** | 🟡 批 P：判定层 + 执行层 + 设置页入口 + 契约门第 21 组端到端（file:// 打桩）；⚠ **当下 latest v0.1.0 没有 Linux x64 资产** ⇒ 真机上暂时下载不到（引擎侧下次发版即生效，**引擎仓不用改**） | ⬜ **URL 已失效** —— `build.sh` 用固定 URL `releases/latest/download/moongit-darwin-arm64.tar.gz`，而引擎的资产名**带版本号**（`moongit-v0.1.0-darwin-arm64.tar.gz`）⇒ **实测 404**（不带版本号的才 404，带版本号的 200） | ⬜ 未接 | mac 侧后续批次（**本轮次序先搞定 dde**，未改 mac） |
| 引擎索引自愈（`selfHealed`） | ✅ 批 L：索引缺失/过期时引擎会**自愈**（实测 2026-10-19：`selfHealed: true`）→ 索引状态行在用户点「生成」前就有内容，并明说「引擎自愈过索引」 | ⬜ 未接 | ⬜ 未接 | —— 条件键，需 present 标志 |

### D.1 跨端状态色**取值口径**差异（批 O 照出，**批 R 逐点核对后照实修正**）

批 O 把状态语义色收敛成单一真相源（E.1 节）时，顺手核了 mac 的着色口径，发现**两端取值不一致**。
这属于「取值对齐」，**会动视觉基线**，需专门评审，不在批 O 顺手改。

> **⚠ 本节原描述有失真，批 R 逐点核对后照实修正**（原文说「mac 自己就有两套映射：
> `StatusColor.systemColor` 与 `DSColor.color(DSStatus)`」）——
> **事实是 `StatusColor.systemColor` 在整个 mac 仓零调用，是死代码**。
> 也就是说 deepin 的 stale 红**对标的是一段没人用的代码**；mac 实际在用的那套是
> `DSColor.color(DSStatus)`（`Components.swift:18` 状态点 / `DetailViews.swift:667` 分支行）。
> 真正在 mac 里分叉的不是 `StatusColor` vs `DSColor`，而是**Liveness 层的三处副本**。

#### D.1.1 分支状态层（引擎 `branch status`）

引擎取值域**只有 5 档**（`moongit/src/kernel/progress.cj:14-37` 的 `computeBranchStatus`）：
`merged` / `unknown` / `active` / `idle` / `stale`。
（`unknown` = 时间戳无效或**时钟不可信**（`d < -1.0`），不是「不知道状态」。）

| 语义档 | deepin（现值） | mac 活代码 | 差异 |
| --- | --- | --- | --- |
| `active` | 绿 `#10B981` | `DSPalette.shallow` `#10B981` | ✅ 同值 |
| `merged` | 紫 `#8B5CF6` | `DSPalette.deep` `#8B5CF6` | ✅ 同值 |
| `idle` | 黄 `#E8B01C`（tailwind yellow-400） | SwiftUI `.yellow`（**系统色**） | 色源不同（见 D.1.3） |
| `stale` | **红 `#EF4444`** | **SwiftUI `.orange`（系统橙）** | ❌ **口径冲突** |
| `unknown` | 灰 `#9CA3AF` | `.secondary`（系统灰） | 色源不同 |
| `dirty` | —（**引擎不产出**） | `.red` | mac 的这一档是**死路径**（引擎永不返回 `dirty`） |

#### D.1.2 Liveness 层（项目活跃度，7 档）

deepin 的 `Liveness` 枚举与 mac **逐档一一对应**（`deepin/src/logic/Liveness.h` ↔ `macos/Sources/deepDolphin/Models.swift:524-538`），
差别只在**着色**。mac 侧着色在**三处各写一遍**（`BoardView.swift:156-164`、`DashboardParts.swift:212-218`、
`DetailViews.swift:508-516`），其中 `notGit` 一档 `DetailViews` 用 `.gray`、另两处用 `.secondary`
—— **mac 自己的第二套口径**（多数派是 `.secondary`）。

| 语义档 | deepin（现值） | mac（两处多数派） | 差异 |
| --- | --- | --- | --- |
| `recent` | 绿 `#10B981` | `.green` | 色源不同 |
| `needsAction` | 橙 `#F59E0B` | `.orange` | 色源不同 |
| `engineStale` / `quiet` | **红 `#EF4444`** | **`.secondary`（灰）** | ❌ **口径冲突** |
| `notGit` | **紫 `#8B5CF6`** | **`.secondary`（灰）**（`DetailViews` 是 `.gray`） | ❌ **口径冲突** |
| `unreadable` | 红 `#DC2626` | `.red` | 色源不同 |
| `unknown` | 灰 `#9CA3AF` | **`.red`（与 `unreadable` 同档）** | ❌ **口径冲突** |

#### D.1.3 差异的本质（不是「档位不同」，是**色源不同**）

deepin 用 **tailwind 固定色值**（`#10B981` / `#F59E0B` / `#9CA3AF` …），mac 混用两种：
- **设计稿色**：`DSPalette`（`DesignTokens.swift:13-36`）—— 绿/紫/青/蓝四档，**与 deepin 同值**；
- **SwiftUI 系统色**：`.orange` / `.red` / `.yellow` / `.secondary` / `.green` —— 橙/红/黄/灰四档，
  **在 deepin 侧物理上不存在对应物**（Linux/DDE 没有 macOS 系统色，系统色会随外观/强调色变，
  固定色不会）。

⇒ **「对齐 mac 的色值」在橙/红/黄/灰四档上不成立**，只能对齐**语义分档**（哪一档该是警示色、
哪一档该是静默色）。绿/紫/青/蓝四档已同值，不动。

#### D.1.4 其他

| 项 | deepin | mac | 差异 |
| --- | --- | --- | --- |
| 分段条底轨遮罩 | 灰 **40**/255 | — | 与托盘迷你条底轨（灰 **60**/255）**同语义不同档**；mac 侧无对应物（`CodeGraphHeatmap.swift:484` 的画布底轨是 `white.opacity(0.10)`，属另一层） |

**待办（批 R-2）**：按 D.1.3 的口径定案后统一取值 —— 动四页快照基线 + 需视觉评审。
**本轮次序是先搞定 dde**；mac 侧那三处 Liveness 副本与 `StatusColor` 死代码一并记为 mac 自身债（不改 mac）。

#### D.1.5 批 R-2 定案（已落地）

| 语义档 | 改前 | 改后 | 依据 |
| --- | --- | --- | --- |
| 分支 `stale` | 陈旧红 `#EF4444` | **橙 `#F59E0B`** | mac 活代码 `DSColor.color(.stale)` = `.orange` |
| Liveness `engineStale` / `quiet` | 陈旧红 `#EF4444` | **灰 `#9CA3AF`** | mac 两处多数派 = `.secondary`（静默 ≠ 坏了） |
| Liveness `notGit` | 紫 `#8B5CF6` | **灰 `#9CA3AF`** | mac 两处多数派 = `.secondary`；且紫已被「深更新轨 / 已合并」占用，notGit 用紫会误读 |
| Liveness `unknown` | 灰 `#9CA3AF` | **红 `#DC2626`** | mac = `.red`（与 `unreadable` 同档）—— 「读不出来」是真有问题，不该装成「不活跃」的灰 |
| Liveness `unreadable` | 红 `#DC2626` | 不变 | |
| Liveness `needsAction` / `recent` | 橙 / 绿 | 不变 | |
| 分支 `active` / `merged` / `idle` / `unknown` | 绿 / 紫 / 黄 / 灰 | 不变 | 绿紫已同值；黄灰是色源差异（见 D.1.3） |

**陈旧红 `#EF4444` 改为托盘专用档**：
它与危险红 `#DC2626` **肉眼几乎分不出**，UI 层同时出现两个红 = 读者分不出谁是谁。
但**托盘不参与压档** —— 托盘图标无文字，形状只分「告警三角 / 普通环形」两档，
`notGit` / `quiet` 之间**没有形状差别**，颜色是它区分档位的**唯一手段**。
⇒ 判定层（UI 层语义）不挂这一档；托盘保留（`tray/TrayController.cpp` 的 `tintColor`）。
分界是「**颜色是不是唯一信号**」，不是「哪个界面」。

**⚠ 批 R 照出的基线盲区（批 T 已补上）**：
4 页面板快照拍的是**空态** —— 本机引擎注册项目数 0，快照里只有「仪表盘还没有数据」，
**状态点一个都没画进去**。⇒ **面板快照对状态色是空门**：改色它不红，
说「视觉已评审」是假的（这是第 11 次同类问题：空门比没门更糟）。
⇒ 批 R 新增**状态色样张**（`ui/ColorSampleSheet` + 无头入口 `--color-sample`），
把 liveness 7 档 + 分支状态 5 档 + 托盘专用档 + 固定色**每一档都画出来**，
纳入 CI 截图矩阵（`light-colors.png` / `dark-colors.png`）—— 改色 ⇒ 色卡 diff 红。
样张颜色**全部走判定层**（接线门钉住），判定层改色它自动跟着变。

**⇒ 批 T 补掉空态那一半**：面板快照改走**固定夹具**（`logic/SnapshotFixture`，
走同一段解析路径），基线里现在有 **7 个项目**（一档一个 Liveness）、
**分支状态 5 档**、**里程碑 4 态** ⇒ 面板快照对状态色不再是空门。
且基线被做成**逐字节可重现**（固定刷新时刻 + 快照进程固定 `TZ=UTC` +
绝对日期锚定故事基准日）⇒ CI 新增「重拍比字节」门（连拍两次 + 换时区再拍一次）。

**档位清单单一真相源**：判定层导出 `Derived::livenessKinds()`（7 档）与
`Derived::branchStatusKinds()`（5 档，与引擎 `computeBranchStatus` 的产出**严格相等**）——
样张按清单画、判据按清单断言。加一档 `Liveness` ⇒ 样张自动多画一格，不会漏画。
⚠ **不列引擎不产出的档**（如 mac 的 `dirty`）：列了就是永远画不出来的一格。

---

## E. deepin 自身 DDE/DTK 化剩余项（`docs/DDE-INTEGRATION-PLAN.md` §9 看板）

不属于「同步 mac」，是 deepin 客户端自身的收尾：

| 任务 | 内容 | 状态 |
|---|---|---|
| M1-2 | 统一 `platform::icon()`（fallback 链 + 缺失告警 + DDciIcon 优先） | ✅ **批 U 已做**：判定层 `logic/IconNames`（`enum class Id` 27 个逻辑图标 → **候选名链**，唯一出处）+ 平台层 `platform/IconResolver`（**DDci → 主题 → qrc 染色 → 缺失告警 + 占位**）；**11 处**散落的 `QIcon::fromTheme` 全改走统一入口；**删掉零调用点的 `IconLoader`（170 行死代码）**。探针实测：27 个逻辑图标 **8 个走 DDci / 19 个走主题 / 0 个解析不到**（bloom 主题）；离屏（无图标主题）27 个全 `none`、0 告警。**视觉零变化**（基线逐字节未变） |
| M1-3 | 托盘迁移 SNI | ⬜ |
| M1-7 | `platform/Backend` 平台层 | ✅ **批 V 已做**：判定层 `logic/Backend`（纯结论：`enum class Kind {X11,Wayland,Other}` + `classify()` **带 token 边界** / `activationFor()` / `reservedInsets()` / `placePopup()` / `trayGeometryUsable()`）+ 平台层 `platform/Backend`（`activate()` / `availableGeometryAt()` / `taskbarInsetsAt()` / `trayIconGeometry()` / `trayPopupTarget()`）；**8 处**散落的 `show/raise/activateWindow` 收编成**一个入口**；**修掉真缺陷**：`show()` 不恢复最小化窗口（实测）⇒ 最小化态从托盘叫不醒面板；托盘弹窗**右/上两边**旧实现不夹紧 ⇒ 右上角托盘时溢出屏幕 |
| M1-8 | Wayland 分支 | ⬜ |
| M2-5 | i18n | ⬜（与 B8 合并做更省） |
| M2-7 | deb 打包 | 🟡 **批 S 已做**（`scripts/build-deb.sh` + 依赖清单 `scripts/deb-deps.txt` + **依赖清单↔二进制实际 DT_NEEDED 双向校验** + CI 第 11 门）；⚠ **真机 clean deepin 25 容器验收未跑**（本机无 docker/podman）—— D7 的最终验收仍待真机 |
| M2-8 | 安装后零环境变量 | ✅ **批 S 实测达标**：二进制**无 RPATH/RUNPATH**、`DT_NEEDED` 全是 soname；宿主自带 Qt6/DTK6 ⇒ 裸环境 `--selfcheck` 269/0、**deb 解包后的二进制**裸环境同样 269/0 且能拍快照。⚠ README 原写「运行库在 sysroot 里，环境变量缺一不可」是**失真描述**，已改 |
| M3c | 清第二套色板 + 一致性 / HiDPI / 动效收尾 | ⬜（与 B13/B14 同批更省） |
| M1a / M0-8 / M3b / M4a / M4b | 容器批 / 干净容器 / KPI 骨架屏 / 拆分 / deb 矩阵 | ◐ 部分落地 |

### E.1b 图标资源的真实使用情况（批 U 照出 —— **PLAN M2-6 的描述是失真的**）

PLAN §10 里 M2-6 的日志写「托盘/菜单『不再手绘占位方块』」——
实测**托盘至今仍是手绘**（`tray/TrayController.cpp` 用 QPainter 画三态符号：
感叹三角 / 双圆 / 感叹点），**菜单图标也还没用上 `dd-*`**。

更关键的是：`platform/IconLoader.{h,cpp}`（170 行，负责「主题图标 + qrc `dd-*` 染色兜底」）
**零调用点** —— 托盘只 `#include` 了它的头文件，从没调用过任何函数。
⇒ qrc 里登记的 `dd-git.svg` / `dd-milestone.svg` / `dd-warning.svg` / `dd-circle-double.svg` /
`dd-ai.svg` 与 `deepdolphin.svg` **其实从来没被消费过**
（`deepdolphin.svg` 另有 hicolor 安装路径，图标本身没丢）。

⇒ **批 U 已收编**：删除死代码 `IconLoader`，其职责并入 `platform::icon()`
（`dd-*` 仍是候选名之一，qrc 染色作免安装兜底；本构建环境无 Qt6Svg ⇒ 染色通道编译不进）。
⇒ 托盘图标改为手绘仍是**遗留项**（真机观感项，见 M1-3 / M3c）。

### E.1 状态语义色第二份定义（批 N 照出 → **批 O 已收敛**）

批 N 把 D2 散值门的**检测形式补全**后（不再只盯 `#RRGGBB`），照出状态语义色在**两处**定义：

| 位置 | 色值 | 与 `DS::semColor` 的关系 |
| --- | --- | --- |
| `logic/Derived.cpp`（`livenessColor` / `branchStatusColor` / `statTint`） | 绿 `0x10B981` / 紫 `0x8B5CF6` / 橙 `0xF59E0B` / 灰 `0x9CA3AF` | **同值** → 同一个语义的第二份定义 |
| `tray/TrayController.cpp`（`tintColor`） | 同上一批 | **同值** → 同上 |
| `tray/TrayPopupWindow.cpp` | 灰 `0x9CA3AF` | **同值** → 同上 |
| `platform/IconLoader.cpp` | 灰 `0x888888` / 蓝 `0x1E6FEB` | 图标 tint 兜底 + 托盘强调蓝（**独立语义**，DS 里没有） |
| `logic/Derived.cpp` 另有一档红 `0xEF4444` | `engineStale` / `quiet` / `stale`（分支状态） | **DS 没有这一档**（DS 的 `red` 是 `0xDC2626`）→ 批 O 补为 `SemColors::stale()`（**两档红语义不同，不合并**） |

**批 O 已收敛**：新增 `src/logic/SemColors.h`（判定层纯色、零 UI 依赖）作为**唯一出处**，
`DS::semColor()` 改为**转发**它；判定层 / 托盘 / 平台层一律从它取值。
D2 门里的四条 `fix` 豁免（`Derived` / `TrayController` / `TrayPopupWindow` / `IconLoader`）
**因命中归零而删掉** —— 门本来就会红（`fix` 模式「归零即红」），是它在逼着收敛。
**取值一字未改** → 视觉零变化。
⚠ **剩下的跨端取值差异不在本批**，见 D.1 节。

### E.1c 平台后端差异（批 V 照出 —— **两处真缺陷 + 三个平台事实**）

批 V（M1-7）把「后端分档 / 窗口激活 / 托盘弹窗定位 / 任务栏几何」收进平台层时，
**实测**（不是推理）照出两处真缺陷：

| 缺陷 | 实测结论 | 影响的用户动作 | 修法 |
| --- | --- | --- | --- |
| **最小化的窗口叫不醒** | `QWidget::show()` **不恢复**最小化窗口 —— 离屏与 xcb **两种后端实测**，`show()` 之后 `windowState()` 仍带 `WindowMinimized` | 面板被最小化后，从托盘点「打开面板」**点了跟没点一样** | 激活前**只摘最小化位**：`setWindowState(state & ~Qt::WindowMinimized)`。⚠ **不能用 `showNormal()`** —— 实测它**顺带清掉最大化位**（`WindowMaximized` → `WindowNoState`）⇒ 用户最大化着的面板会被打回普通大小 |
| **托盘弹窗两处越界** | 旧实现只夹**下边与左边** | 托盘在屏幕**右上角**（DDE 顶栏的托盘就在那儿）⇒ 弹窗右边缘 = 图标右边缘 + `dockGap` ⇒ **溢出屏幕右边**；弹窗比可用区还高 ⇒ **顶部溢出**（标题栏被切掉） | 四边都夹；**边距只在越界时生效**（无条件留边距会把弹窗从托盘图标底下推下来十几像素） |

三个平台事实（探针实测，写在这里备查）：

- `QRect` 表达不出「宽 0 但有效」的矩形 ⇒ `isValid()` 与 `width()>0 && height()>0` **语义等价**。
  （这条是负控的教训：拿 `isValid()` 替换 `w>0&&h>0` 的变异**抓不住任何东西**。）
- **`raise()` 在 Wayland 上是空操作**（叠放次序由合成器决定）⇒ Wayland 分支不调它。
- xcb 会话下**任务栏占 41px**（`taskbarInsets=0,0,0,41`）—— 这正是 M1-8 要用的那组数
  （Wayland 侧 QPA 未必扣面板 ⇒ 要问 `org.deepin.dde.Panel`）。

---

## F. linux 端

**本轮明确暂缓**（用户 2026-10-19 定：「linux 通用再说」）。
linux 侧已知独立缺口记在 `linux/README.md` 的「与 macOS 端的已知差异」与 `linux/VERIFY-ON-LINUX.md`。
注意：章程 §3.5 把 linux 的实现指定为**仓颉 Canvas 移植** —— 与 deepin 的 Qt QPainter 同款内核需求，
将来做 linux 时**可复用本批的契约层与判据思路**（端口式 CanvasSink 是为这一步留的）。
