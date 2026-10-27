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
| B8 | **四语言本地化（全应用接入）** | `L10n.swift`（2108 行） | 🟡 **批 AA 只做了「固定文档页」这一块**（判定层 `logic/DocPages` 扩到 zhCN/en/zhTW/ja 四语言 · 16 篇正文全给全 + 文档窗内语言选择器 + 持久化 `app.language`（与 mac UserDefaults 同名键逐字对齐））；**全应用 i18n 仍未做**（⚠ 真实规模实测：deepin 用户可见中文串 **1008 个去重 / 1186 次出现**，在 mac `L10n.swift` 的 zh-CN 表（483 键）里**逐字命中仅 155 个（15%）** ⇒ 「搬 mac 译文」这条路基本走不通，**85% 要新写**，尤其中日；台账原记「P2（量大）」**低估**了） | P2（量大，且**需人工翻译**） |
| B9 | **原生菜单栏三件套（关于/帮助/设置）+ 设置统一为系统原生窗口** | `DeepDolphinApp.swift` | 🟡 **批 G 已接「关于 / 帮助」**（面板菜单 → 文档窗；DDE 无原生菜单栏对位物，改为面板菜单承载）；**「设置」仍是对话框**（`AiSettingsDialog`，三页签），非「原生独立设置窗口」 | ⚠ **批 AA 判定：不做**（实质只是「设置从对话框变独立窗口」；deepin 的 `AiSettingsDialog` 已是 `DDialog` 且**有「关闭」按钮** —— mac 那个 sheet **无关闭按钮**的问题在 DDE 下**不存在** ⇒ 价值低） |
| B10 | **仪表盘项目卡片整卡可点** | `DashboardParts.swift` | 🟢 **已对位（台账原记「未开始」有误，批 G 复核时更正）**：`ProjectProgressCard::mouseReleaseEvent` → `goProject`（`Card` 是 QFrame 不吞鼠标事件，事件冒泡到卡片）；另有 mac 同款的「进入管控 →」钮 | ~~P3~~ 已完成 |
| B11 | **Agent 补齐 18 个图能力工具**（契约检查第 12 组抓到的清单漂移） | `AgentCheck` | 🟢 **已对位（批 E1）**：28 个工具全接（命令形态抽成纯函数表 `logic/AgentToolPlan`，可无头判）；`deepDolphin --agent-tool-names` 出客户端权威清单，contract-check 第 12 组与真引擎 `tools --json` 严格对位（**CI 第 10 门**） | ~~P0~~ 已完成 |
| B12 | **9 语言语法高亮** | mac 原生 `AttributedString` | 🟢 **已对位（批 H）**：判定层 `logic/SyntaxHighlight`（九语言关键词表 + 单遍扫描 → 关键字/字符串/注释/数字四类 token 段）、涂色层 `ui/CodeHighlighter`（QSyntaxHighlighter，颜色取自 DS 令牌）、接到代码图谱页源码页签（高亮语言跟着选中符号的 `lang` 走）；**九种语言与引擎 `detectLang` 逐条对齐**（契约门第 16 组用真引擎跑九种扩展名比对） | ~~P2~~ 已完成 |
| B13 | **性能审计**：动画时钟可见性暂停 + formatter 静态化 | `21c7082` | 🟢 **批 M 已对位**（且补上 mac 侧没有的项）：**可见性暂停**deepin **本来就有** —— 实测（2026-10-19，Qt 6）**父窗口隐藏会给子控件发 `hideEvent`**，所以架构图与热力图的 `hideEvent → m_anim->stop()` 真的停得住，两处都是 33ms（≈30fps），与 mac 修完后的口径一致；**formatter 静态化**已做（日期格式化走 `Qt::ISODate` 枚举，不建格式串）；**另补 mac 没做的三项**：Canvas font 简写按 CSS 口径解析（`pt` 也不再被吞）、Canvas2D 的 QFont 按串静态缓存 + 同串跳过、热力图三处每帧分配收掉 | ~~P3~~ 已完成 |
| B14 | **设计系统存量清零**（字号/散值收进 token，基线 87→95） | `e9d6074` | 🟢 **批 N 已对位**：M3-3 登记的 **4 处字号散值**全收进 `DS::FontPx`（徽章 11 / 等宽 13），D2 门上限 **4 → 0**；另收口 3 处门形式不全才照出的真散值（alpha `0.18` → `DS::Alpha`、底轨遮罩 → `DS::trackMask()`、热力图深色画布五档 → `HeatLayout::Canvas`）。**门从「只盯 `#RRGGBB`」补成全形式检测**（3/6/8 位 hex、`QColor(r,g,b)`、`QColor(0x..)`、`rgb()`、带裸 alpha 的 `rgba()`、`setPixelSize`/`setPointSizeF` 数字参数、QSS `font-size` 字面量、含 `font-size:` 文件里的裸数字 `.arg(N)`）—— 旧门的「4 处存量」其实只是「4 处**写成 hex 形态**的存量」。**豁免改为显式登记**（`D2_EXEMPT` 清单：`keep` 永久 / `fix` 待收敛且**归零即红**，白名单不许腐化） | ~~P3~~ 已完成（**状态语义色第二份定义**另立批 O，见下） |
| B15 | **引擎获取链新增 GitHub Releases 自动下载** | `macos/build.sh` | 🟡 **批 P 已接（deepin 侧完整，mac 侧有缺陷）**：判定层 `logic/EngineDownload`（查 API → 按平台挑资产 → sha256 校验 → 落盘路径 → **七类失败各说各的**）+ 执行层 `app/EngineInstaller`（网络/解压全异步，不卡 GUI）+ 设置·通用页「引擎」卡（下载并安装引擎）+ 发现链认得新落盘位 `~/.local/libexec/deepdolphin/moongit`（排在 `~/.local/bin` **之前**，mac 的教训：客户端自带的优先，否则永远选到过期安装版）；契约门第 21 组端到端验（file:// 打桩跑完整链 + 校验和不匹配**拒绝安装且不落盘** + 真 GitHub API 解析） | P2（**批 AB 已解**：latest 已到 **v0.2.1**（Linux x64 + mac arm64 资产齐，v0.2.0 是 v0.1.0 之后第一个带 Linux 资产的版本）｜⚠ **v0.2.0 的 Linux 资产是坏包**（`runtime/lib/` 空 —— 引擎打包脚本用 `ldd` 探测依赖，在 CI 里全部 `not found` ⇒ 静默漏掉仓颉运行库），**v0.2.1 已修**，真机上点「下载引擎」拿到的是 v0.2.1｜客户端侧同时把落盘从「只拷一个文件」改成**整包**（启动器 `moongit` + `bin/` + `runtime/`），只拷启动器的话装下来的引擎 exec 不到二进制、加载不到运行库 ⇒ **跑不起来**） |
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
| `index_*` 家族 | 代码索引（`graph` 的新家） | 🟡 批 E2 已接 `index gen --stats`（代码图谱页「生成」钮）；**批 L 已接 `index overview`（索引状态行）+ `index update`（增量更新钮）**；`index query` ⬜ **判定不接 GUI**（⚠ **批 AA 复核：批 Z 说它是「新维度」是推过头了**，见 E.1i）：实测 `graph functions` 的 `functionEdges` **5274 条、每条带 `tier`**（direct/guessed/resolved），`index query` 的 `callers[]` **也每条带 `tier`** ⇒ **同一维度**（函数级调用边 + 边的确信度档位），只是**取数路径不同**（前者给全项目边列表、后者按符号反查）⇒ 原判据「重叠 ⇒ 接了会造出第二个真相源」**成立** |
| `doctor --json` | 环境自检（**退出码 1 但 stdout 是合法 JSON**） | 🟢 **批 J 已接**（设置·通用页「环境自检」卡；`result` 是自由文本；`problems` 缺键记「未知」） |
| `report <项目>` | 进度报告导出（**回执型命令，回执在 stderr**） | 🟢 **批 J 已接**（详情页「导出报告」入口 + 报告卡 + 「打开报告」） |
| `config list` / `config get` / `config set` | 引擎配置（**策略面**：浅更新分支上限 / 文档备份份数 / 受管文档 / 扫描根） | 🟢 **批 K 已接**（设置·通用页「引擎配置」卡；`config set` 回执也在 stderr） |
| `confidence query` | 置信度只读快照 | ⬜ **判定不接 GUI** —— 是 `graph confidence` 的**子集**（少了 `findings[]` 逐条疑点），接了反而丢信息；仍可经 agent 工具面用 |
| `index overview` / `index update` / `index query` | 持久化代码索引 | ⬜ 未接 GUI（⚠ 批 AA 实测复核：`index query` 与已接的 `graph functions` **同维度** —— 两边的边**都带 `tier`** ⇒ 原判据「重叠 ⇒ 不接 GUI」**成立**；差别只在取数形态：它能**按符号反查**） |
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
| `index query` | ⬜ **判定不接 GUI** | ⚠ **批 AA 复核推翻了批 Z 的「推翻」**（见 E.1i）：批 Z 说「`graph functions` 根本没有 tier ⇒ `index query` 是新维度」—— **这半句是错的**。实测 `graph functions` 的 `functionEdges` **5274 条、每条都带 `tier`**（direct/guessed/resolved）⇒ 原判据「`tier` 两边都有」**成立** ⇒ **同一维度**（函数级调用边 + 边的确信度档位），结论「接了会造出第二个真相源」**站得住**。批 Z 说对的两点仍然成立：① `defs[]` 是**按符号查**（单符号），`functions[]` 是**全项目列表**；② `findings` 在 `index query` 是**计数**（int）、在 `graph functions` 是**数组** ⇒ 这是**取数形态**差异，不是**数据维度**差异。⚠ 批 Z 的引擎修复**确实解锁**了它（修前 C++ 符号压根不在索引里 ⇒ 「符号不在索引中」；修后 `index query chooseBackend` 返回 3 个 callers 带 `tier: resolved`）—— 解锁 ≠ 该接 GUI |
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
| **引擎获取链（GitHub Releases 下载安装）** | 🟢 批 P + 批 AB：判定层 + 执行层 + 设置页入口 + 契约门第 21 组端到端（file:// 打桩）；**latest 已带 Linux x64 资产**（v0.2.1；v0.2.0 的 Linux 资产是坏包，已修）；落盘改为**整包**（真实布局：启动器 + `bin/` + `runtime/`），契约门第 21 组的夹具**同步改成真实布局**（原来那个夹具是虚构的，测过的路径真实资产根本走不到） | ⬜ **URL 已失效** —— `build.sh` 用固定 URL `releases/latest/download/moongit-darwin-arm64.tar.gz`，而引擎的资产名**带版本号**（`moongit-v0.1.0-darwin-arm64.tar.gz`）⇒ **实测 404**（不带版本号的才 404，带版本号的 200） | ⬜ 未接 | mac 侧后续批次（**本轮次序先搞定 dde**，未改 mac） |
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
| M1-3 | 托盘迁移 SNI | 🟡 **解法已查明并落地；剩真机/容器的像素级验收**（批 Y，详见 E.1h）：⚠⚠ **正解不是「迁 SNI」**，而是 **deepin 的托盘窗口协议** —— 自绘 X11 窗口 → 向 `_NET_SYSTEM_TRAY_S0` 选区持有者发 `REQUEST_DOCK`（⚠ 字段**比经典 XEmbed 偏移一位**：`l[1]`=opcode、`l[2]`=窗口 id）→ daemon 登记进 `TrayIcons` → dock reparent 并画。批 X 那句「迁 SNI 解决不了弹窗定位、真实价值只剩保住图标颜色」**成立**（SNI 确实没位置字段），但**方向**错了。**已落地**：判定层 `logic/DeepinTray` + 平台层 `platform/DeepinTray`（xcb、32 位 ARGB 窗口）+ 三态后端（deepin 窗口 / SNI / 旧协议，互斥）+ 后端强制开关（测试钩子）；**实测**：窗口进了 `TrayIcons`、`GetName` → `'deepDolphin'`、dock 真的 reparent 了它 ⇒ **daemon 侧与 dock 侧都通**；**托盘区仍 0 像素** —— dock 侧 `getX11WindowImageNonComposite` 抓不到窗口图像（本机连 `cc-switch`/`clash-verge` 也只显示空占位圆）⇒ **dock 侧缺陷，客户端改不了** ⇒ 像素级验收待真机/容器 |
| M1-7 | `platform/Backend` 平台层 | ✅ **批 V 已做**：判定层 `logic/Backend`（纯结论：`enum class Kind {X11,Wayland,Other}` + `classify()` **带 token 边界** / `activationFor()` / `reservedInsets()` / `placePopup()` / `trayGeometryUsable()`）+ 平台层 `platform/Backend`（`activate()` / `availableGeometryAt()` / `taskbarInsetsAt()` / `trayIconGeometry()` / `trayPopupTarget()`）；**8 处**散落的 `show/raise/activateWindow` 收编成**一个入口**；**修掉真缺陷**：`show()` 不恢复最小化窗口（实测）⇒ 最小化态从托盘叫不醒面板；托盘弹窗**右/上两边**旧实现不夹紧 ⇒ 右上角托盘时溢出屏幕 |
| M1-8 | Wayland 分支 | ✅ **批 W 已做**（本机无 Wayland 会话 ⇒ Wayland 侧未实跑）：判定层 `logic/PanelGeometry` + 取数层 `platform/DdePanel`（D-Bus 读 `org.deepin.ds.Dock` 的 `geometry`/`position`）；`placePopup()` 加面板参数（面板在下 ⇒ 弹窗落面板上方右对齐）；托盘坐标不可用时按**光标所在屏**；失焦收起加 `applicationStateChanged` 兜底。**修掉真缺陷**：DDE 上 `QSystemTrayIcon::geometry()` 恒无效 ⇒ 弹窗飞到离托盘很远的屏幕右上（实测 (1523,32) → (1524,731)）。⚠ **批 Y 更正这里的因**：批 W 写「DDE 托盘是 SNI ⇒ 坐标恒无效」，**说反了**——DDE 托盘画的是**应用自绘的 X11 窗口**（批 Y 查明，见 E.1h），`QSystemTrayIcon` 在 DDE 上**根本没有宿主**；坐标取不到不是因为「SNI 没位置字段」，而是**压根没有旧协议托盘可问** |
| M2-5 | i18n | ⬜（与 B8 合并做更省） |
| M2-7 | deb 打包 | 🟡 **批 S 已做**（`scripts/build-deb.sh` + 依赖清单 `scripts/deb-deps.txt` + **依赖清单↔二进制实际 DT_NEEDED 双向校验** + CI 第 11 门）；⚠ **真机 clean deepin 25 容器验收未跑**（本机无 docker/podman）—— D7 的最终验收仍待真机 |｜⚠ **批 AD 补了 D7 的「准验收」**（新门 `scripts/check-deb-layout.sh`，CI 第 12 门）—— 当场抓出真 bug：D-Bus service 的 `Exec=deepDolphin --dbus-service`（裸名 ⇒ dbus 激活不做 PATH 搜索；`--dbus-service` 客户端根本不认识）⇒ **点图标起不来**；已修为绝对路径 + 打包期校验｜⚠ **批 AE 再补一层**：「依赖包在 **apt 仓库**里存在」的校验（原先只验「本机装着」⇒ 不等于「目标机装得上」）；实测 17 个依赖包在 deepin 25 仓库候选齐全
| M2-8 | 安装后零环境变量 | ✅ **批 S 实测达标**：二进制**无 RPATH/RUNPATH**、`DT_NEEDED` 全是 soname；宿主自带 Qt6/DTK6 ⇒ 裸环境 `--selfcheck` 269/0、**deb 解包后的二进制**裸环境同样 269/0 且能拍快照。⚠ README 原写「运行库在 sysroot 里，环境变量缺一不可」是**失真描述**，已改 |
| M3c | 一致性 / HiDPI / 动效收尾（⚠ **批 AD 实测订正**：「清第二套色板、两种红/两种蓝」**已过时** —— D2 门的 `fix` 豁免清单**已空**＝色值散值归零；且 `logic/SemColors.h` 里**两档红是有意区分的**（`red`=危险/读不出来、`stale`=停滞告警/托盘专用，注释明写「不是笔误」）⇒ 合并反而丢语义） | ⬜ 剩：图标名 / 动效 / 响应式 / HiDPI / 分隔线 / 托盘 busy 态（⚠ 托盘 busy 态：deepin 托盘是**自创**的 —— **mac 侧根本没有托盘** ⇒ 无对位可抄；且托盘**弹窗**的 busy 态已有 `BusyRow` 转圈 ⇒ 排在有对位的项之后） |
| M1a / M0-8 / M3b / M4a / M4b | 容器批 / 干净容器 / KPI 骨架屏 / 拆分 / deb 矩阵 | ◐ 部分落地（⚠ **批 AE 实测核对**：**M3b 组件化主体已全部完成**（`src/ui/common/` 17 个组件、散落的次级标签样式 **0 处**、`SegmentedButton` **只一份**）⇒ 只剩 KPI 骨架屏 + 真机目检；**M4b 的「deb 构建未做」已过时** ⇒ 现在 ci.sh **12 门**（第 11 门 deb 构建、第 12 门 deb 布局验收），只剩「系统 Qt6/DTK6 矩阵」那一步）；⚠ **M4a 拆分（批 AJ）已动第一步**：「判据不许被删」**补上了门**（`ci.sh` 的 `SC_MIN`（**批 BB 起为 395**），以前只断言「≥58」⇒ 删 300 条判据照样全绿）+ `SelfCheck.cpp` **3832 → 2547 行**（拆出 `SelfCheckDocs.cpp` 513 行、`SelfCheckEngine.cpp` 864 行）⇒ **M4a 仍未完**；⚠ **批 AK 又拆一片**：段 15（图谱/热力图/补丁体检，**1100 行**）搬进 `SelfCheckGraph.cpp` ⇒ `SelfCheck.cpp` **2547 → 1451 行**（⇒ **单文件过大**这笔债基本还清）；⚠ **批 AL 收官**：拆 `AppModel.cpp` ⇒ **1948 → 1052 行**（拆成主片 + `AppModelGraph.cpp` + `AppModelUpdate.cpp`，跨片辅助函数上 `AppModelInternal.h`）⇒ 🎉 **M4a 达成**：全仓最大文件 **3832 → 1451 行** ⇒「单文件占全仓近 10%」这个债**还清**） |

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

### E.1d DDE 面板的 D-Bus 接口（批 W 照出 —— **PLAN 写的接口名不存在**）

PLAN §9 M1-8 写的是「`org.deepin.dde.Panel` 位置/光标位置定位」。
**批 W 在本机总线上逐个探测后确认：`org.deepin.dde.Panel` 这个服务根本不存在。**
真实的面板几何接口是：

| 服务名 | 对象路径 | 接口 | 说明 |
|---|---|---|---|
| `org.deepin.ds.Dock`（新） | `/org/deepin/ds/Dock` | `org.deepin.dde.Dock1` | **只有它带 `position`**（面板在哪条边） |
| `org.deepin.dde.Dock1`（旧） | `/org/deepin/dde/Dock1` | `org.deepin.dde.Dock1` | 只有 `geometry` + `showInPrimary` |
| `org.deepin.dde.daemon.Dock1`（旧） | `/org/deepin/dde/daemon/Dock1` | `org.deepin.dde.Dock1` | 同上 |

接口属性（Introspect 实测）：

| 属性 | 类型 | 权限 | 含义 |
|---|---|---|---|
| `geometry` | `(iiii)` = QRect | 只读 | 面板在**屏幕坐标系**里的矩形 |
| `position` | `i` | 读写 | 0=上 1=右 2=下 3=左（**只有新服务名有**） |
| `showInPrimary` | `b` | 读写 | 面板是否只在主屏 |

**本机实测**：`geometry = (0, 1039, 1920, 41)`、`position = 2`（下）——
与 QPA 的 `availableGeometry()` 扣出来的边距 **0,0,0,41** **完全吻合**
（两套独立来源对上了 ⇒ 这条链路可信）。

另附两个**踩过的坑**（都在本批修掉了）：

- D-Bus 的 `(iiii)` 存进 QVariant 后**丢了类型上下文** ⇒ 裸 `arg >> int` 会走
  libdbus 的「type struct 114 not a basic type」并 **abort**（探针直接 SIGABRT）。
  正确姿势是 `qdbus_cast<QRect>`（需先 `qDBusRegisterMetaType<QRect>()`）。
- `QDBusInterface::property()` **没有超时参数** ⇒ 面板服务卡住会把 GUI 线程
  一起卡住（最深 25s）。改用 `QDBusConnection::call(..., QDBus::Block, 2000)`；
  实测**服务不存在时立刻**返回错误（非 DDE 桌面零成本）。

### E.1e DDE 托盘图标为什么「没有位置」（批 W 照出 —— **这重写了 M1-3 的风险评估**）

批 W 顺手查了「托盘图标在 DDE 上到底什么状态」，实测三件事：

| 事实 | 实测 |
|---|---|
| 托盘**可用** | `QSystemTrayIcon::isSystemTrayAvailable()` = **true**（平台插件认到系统托盘） |
| 但**位置永远不报** | `QSystemTrayIcon::geometry()` = (0,0,0×0)，等 2s 也不变 ⇒ **托盘几何恒为无效** |
| 我们**当时没有**注册成 SNI 项 | 我们的测试程序跑着时，`org.kde.StatusNotifierWatcher` 的已注册项里**只有 3 个 ayatana 项**，没有我们 ⇒ 当时只能看到旧托盘协议。⚠ **批 X 照实修正**：注册进 SNI 是**做得到的**（批 X 做成了，宿主也确实读了我们的属性）⇒ 「DDE 走旧托盘协议」这个**结论**不成立；真正的原因是 DDE 25 托盘区画的是**另一种东西**（见 E.1g） |

⇒ **两条结论**：

1. **迁 SNI 解决不了「弹窗定位」问题** —— SNI 的 `IconName`/`IconThemePath`
   **同样没有位置字段**。原先把 M1-3 判成「高风险：迁过去会丢托盘状态染色」
   的**前提**（迁过去能顺带解决定位）**不成立**。
2. **M1-3 的真实价值只剩「图标颜色」**：SNI 允许 `IconName` 指向**绝对路径**，
   所以把五态彩色图标预先渲成文件、`IconName` 指过去，颜色**能**保住 ——
   代价是往缓存目录写文件（属「程序自身依赖」，纪律允许）。
   ⇒ M1-3 的风险等级应从「高风险」下调为「中等：有明确解法，但要在真机 DDE 上验」。

⇒ 弹窗定位的正确解法**不是** SNI，而是**面板几何**（批 W 已做）。

---

### E.1g DDE 25 的托盘到底认什么（批 X 照出 —— **推翻了批 W 的「DDE 走旧托盘协议」**）

批 X 把「托盘图标为什么不出来」查到底。**先纠正一次自己的误判**：中途曾盯着
`dbus-monitor` 输出的**开头几行**看到一片 `00` 就断言「IconPixmap 被编成全 0」——
**错**。圆形图标的**边缘像素本来就是透明的**；把**整张图**的非零字节数统计出来是
**1948/4096**（真图）。⇒ 「字节全 0」这个结论作废，下列均为逐条实测。
（⚠ 1948 是**取样值**，不是定值：抗锯齿边缘像素会让它在十几个字节内浮动，另一轮实测 1936
⇒ 判据只能写「非零 **> 0**」，不能写「= 某个数」。）

| 事实 | 实测 |
|---|---|
| 我们**能**注册成 SNI 项 | watcher 的 `RegisteredStatusNotifierItems` 出现 `org.deepin.deepDolphin/StatusNotifierItem` |
| watcher 是 **ayatana 变体** | 单参数 `RegisterStatusNotifierItem(serviceOrPath)`、已注册项是**属性**、`ProtocolVersion=0`；源码在 `linuxdeepin/dde-daemon/trayicon1` |
| 宿主会**主动读**我们的 8 个属性 | Id → Menu → IconPixmap → AttentionIconPixmap → OverlayIconPixmap → ToolTip → IconName → IconThemePath（`dbus-monitor` 全量抓包） |
| 缺 pixmap 属性**当场被注销** | 读不到 `IconPixmap` ⇒ host 立刻发 `StatusNotifierItemUnregistered`（实测） |
| 宿主会订阅我们的变化信号 | `NewIcon` / `NewOverlayIcon` / `NewAttentionIcon` / `NewTitle` / `NewStatus` / `NewToolTip` + `PropertiesChanged`（AddMatch 规则实测） |
| **但宿主不画我们** | 全屏差分 **0 像素**（已排除鼠标光标位移：把光标移开重测仍是 0） |
| 托盘区里显示的是**另一种东西** | `org.deepin.dde.TrayManager1.TrayIcons` = 2 个 **X11 窗口 id**：`0x8000032 "clash-verge"`、`0x7c0001e "cc-switch"`（各 16×16，**窗口名 = 应用名**） |
| 画托盘的不是 watcher 宿主 | 读我们属性的是 `trayplugin-load`（`:1.151`），加载 `libapplication-tray.so`（**dde-dock 的托盘插件**）；watcher 由 `dde-session-daemon`（`:1.20`）提供 |
| 该插件同时实现**三套**协议 | `SniTrayProtocol` / `XembedProtocol` / `DDEindicatorProtocol`（deepin 私有接口 `dde.shell.tray.indicator`，配置目录 `/etc/dde-dock/indicator/`） |
| ⚠ **旧协议选区「不存在」是量错了**（批 Y 更正） | 批 X 用 `xprop -root _NET_SYSTEM_TRAY_S0` 查到 "not found" ⇒ 判「没有 XEmbed 选区」。**错**：`xprop` 查的是**窗口属性**，而选区要用 `XGetSelectionOwner` 查。**批 Y 实测：`_NET_SYSTEM_TRAY_S0` 有持有者**（`0xe00000` = 1×1 未映射的 InputOnly 窗口，root 的子窗口）⇒ X11 上**有** XEmbed 选区，dock 插件就是靠它接图标的 |
| 标准 SNI 项**也不进**托盘区 | fcitx5 的 SNI 项注册在 watcher 里；杀掉重启后托盘区**全屏差分 0 像素** |
| 已排除的变量 | IconPixmap 空/非空、IconName 指绝对路径/指主题图标名、注册传服务名/传对象路径、Menu 指向不存在的对象 —— **都不是根因** |

⇒ **三条结论（改写 M1-3 的定性）**：

1. **批 W 的「DDE 走旧托盘协议」不成立** —— 我们注册进 SNI 是做得到的，宿主也确实
   按标准 SNI 读了属性、订了信号。
2. **但「迁 SNI」在 DDE 25 上仍不达成端到端**：托盘区画出来的是**应用自绘的 X11 窗口**
   （经 `org.deepin.dde.TrayManager1` 注册 → dock 嵌入），**不是**宿主按 SNI 替你画图标。
   ⇒ M1-3 的正确解法**不是**「迁 SNI」，而是**按 deepin 的托盘窗口协议注册**
   （自绘一个 X11 窗口当图标 → 向选区持有者发 `REQUEST_DOCK`）。
   ⚠⚠ **批 Y 更正**：这里写的「交给 `TrayManager1.Manage`」**是错的** ——
   `Manage()` 只是让 daemon **重新 claim 选区**，**它不注册任何图标**；
   实测调了 `Manage()` 我们的窗口**照样没进** `TrayIcons`。
   真正的注册动作见 E.1h。
3. ⚠ **本机还有一个独立问题，限制了判据的可信度**：托盘区那 3 个圆是**空的深灰占位圆**
   （图标内容没渲染出来）⇒ **本机 deepin 25 的托盘图标渲染本身也是坏的** ⇒
   「图标有没有出现」这个判据在本机**不能单独采信**，必须与
   `TrayManager1.TrayIcons` 列表 / `Added` 信号一起看。

⇒ 批 X 据此交付的**可复用**部分：SNI 实现本身是**跨平台正确**的（KDE 系桌面可用），
并顺带修掉两个**与桌面无关**的真缺陷（见 README 变更日志 238/239）——
`drawEllipse` 的圆心语义让**所有平台**的托盘图标一直是空白；像素编码按非预乘读预乘数据
会让半透明图标**读错颜色**。这两条与 DDE 无关，**各平台都受益**。

---

### E.1h DDE 25 托盘窗口协议**到底怎么走**（批 Y 查明 —— 把「路径未知」变成「逐步可测」）

批 X 结束时 M1-3 的状态是「正确路径要重做」。批 Y 把这条路径**逐段测通**，
结论是**协议本身就是经典 XEmbed + deepin 一处偏移**，不需要私有 SDK。

**参与方（三方，批 Y 实测厘清）**：

| 方 | 是什么 | 干什么 |
|---|---|---|
| **注册/托管方** | `org.deepin.dde.TrayManager1` 的 owner 是 **`:1.20` = `dde-session-daemon`**（**不是** dock 插件） | 持有 `_NET_SYSTEM_TRAY_S0` 选区、登记图标窗口、盯 damage、发 `Added/Removed/Changed`、维护 `TrayIcons` 属性 |
| **嵌入/绘制方** | dde-dock 的托盘插件（`trayplugin-load` PID 2964，加载 `/usr/lib/dde-dock/plugins/libapplication-tray.so`） | 读 `TrayIcons` → 为每个窗口建 32 位 ARGB 容器 → **reparent 图标窗口进去** → 抓窗口图像当图标 |
| **应用（我们）** | 自己 | 造一个 X11 窗口画图标 → 向选区持有者发 `REQUEST_DOCK` |

**注册协议（实测可复现）**：

1. 查选区持有者：**`XGetSelectionOwner(dpy, "_NET_SYSTEM_TRAY_S0")`** ⇒ 实测 `0xe00000`
   （1×1 未映射的 InputOnly 窗口，root 的子窗口 —— daemon 自己建的占位窗口）。
   ⚠ `_NET_SYSTEM_TRAY`（无后缀那个）**没有**持有者；用错选区发请求 ⇒ daemon 收不到。
2. 向该持有者窗口发 `ClientMessage`：`type = _NET_SYSTEM_TRAY_OPCODE`，
   **`data.l[1] = 0`（`SYSTEM_TRAY_REQUEST_DOCK`）、`data.l[2] = 我们的窗口 id`**。
   ⚠⚠ **比经典 XEmbed 偏移一位**：经典布局是 `l[0]=opcode, l[1]=窗口, l[2]=版本`；
   deepin 的 daemon 读的是 `opcode := data32[1]`、`win := data32[2]`
   （权威来源 `linuxdeepin/dde-daemon` → `trayicon1/traymanager.go`）。
   ⇒ **实测**：按经典布局发 ⇒ daemon 读到的 opcode 是窗口 id ≠ 0 ⇒ **静默忽略**
   （`TrayIcons` 不变）；按 deepin 布局发 ⇒ **注册成功**。
3. daemon 收到后：`addIcon` ⇒ 建 damage 监听 + `composite.RedirectWindow` +
   发 `Added` + 把窗口 id 写进 `TrayIcons` 属性。

**批 Y 的实测结果**（造一个 22×22 窗口，照 `cc-switch` 的 `WM_CLASS` 抄
`"tray-icon tray app <名>"`，画洋红底白点）：

- ✅ **`TrayIcons` 从 2 个变成 3 个**（`130023454, 134217778, 115343361`）——
  第三个 `0x6E00001` 就是我们的窗口 ⇒ **注册协议已跑通**；
- ✅ **`GetName(0x6E00001)` 返回 `'deepDolphin'`** ⇒ daemon 认得这是谁；
- ✅ **dock 侧真的 reparent 了它**（窗口被改成 22×40、状态 `IsViewable`）⇒
  dock 的 `XembedProtocolHandler::initX11resources()` 走完了（建容器 → reparent →
  composite redirect → 发 XEmbed 握手）；
- ❌ **托盘区 0 像素变化，图标没显示**。

**为什么没显示（机制层面的解释，批 X 只知道「渲染是坏的」，批 Y 知道了为什么）**：
dock 侧显示一个图标的门是 `handler->enabled()`，而 `enabled` 由
`getX11WindowImageNonComposite(窗口)` 决定 —— **抓不到窗口图像 ⇒ `enabled=false`
⇒ `itemRemoved` ⇒ 干脆不显示**（连占位圆都没有）。而本机托盘区那 3 个圆**本来就是
空的深灰占位圆**，说明 **dock 抓图标图像这条路整体是坏的**
（`cc-switch` / `clash-verge` 这两个正经托盘应用也只显示占位圆）⇒
**这不是我们客户端能修的**，是本机 deepin 25 托盘渲染的缺陷。

⇒ **对 M1-3 的影响**：
- **路径已查明并已实现**（不再是「路径要重做」）：自绘 X11 窗口 + `_NET_SYSTEM_TRAY_S0` +
  `REQUEST_DOCK`（偏移一位）⇒ daemon 登记 ⇒ dock 嵌入。
  **批 Y 实现后的实测**：窗口进了 `TrayIcons`、`GetName` → `'deepDolphin'`、
  **dock 把它 reparent 进了托盘容器**（22×40、IsViewable、不在 root 的子窗口里）
  ⇒ **daemon 侧与 dock 侧都通了**；**只剩像素没画出来**（dock 抓不到窗口图像，
  本机所有托盘应用都只显示空占位圆 ⇒ 缺陷在 dock 侧，不在客户端）⇒
  **像素级验收待真机/容器**。
- **可自动化的判据**（不等图标显示）：**「我们的窗口 id 出现在 `TrayIcons` 里」
  且 `GetName(我们的窗口) == 我们的名字」** —— 这两条在 daemon 侧，可脚本化、可在真机跑。
- ⚠ **改后端优先级的副作用（批 Y 一并修掉）**：DDE 上改走窗口协议 ⇒ 批 X 的 SNI 字节级
  判据 `scripts/probe-sni-icon.sh` 在 DDE 上**永远假红**（应用压根不注册 SNI 项
  ⇒「服务没上线」）⇒ 这不是判据坏了，是**判据的前提被改掉了**。
  ⇒ 加**后端强制开关** `DEEPDOLPHIN_TRAY_BACKEND`（**测试钩子**、默认不强制 ⇒ 生产行为零变化；
  解析规则在判定层 `logic/DeepinTray`（`parseBackendOverride`，纯函数）、
  平台层 `platform/TrayBackend` 只读环境变量 ⇒ 单一真相源）
  ⇒ 探针强制走要验的那条路，**并核对应用自报的后端**（`托盘后端 = deepin-window|sni`）
  ⇒ 强制没生效 ⇒ 判据必须红。
  ⇒ ⚠ **认不出的值一律判成「没指定」**（按平台能力自动选）：把「打错字」变成「换了一条路」
  会让判据在**没测到想测的东西**的情况下变绿（假绿）。
- **仍然受阻的**：图标**像素**在本机显示不出来（dock 侧缺陷）⇒ 端到端视觉验收
  与 D7 一样**要等真机/容器**；本机只能验到「注册成功 + 被 dock 接管」。
- **另一条备选路（本机不可用）**：deepin 私有 indicator 协议
  （`dde.shell.tray.indicator` + `/etc/dde-dock/indicator/*.json`，配置项
  `dbus_service/dbus_path/dbus_interface/system_dbus/dbus_method/dbus_properties`）
  —— 本机**没有** `/etc/dde-dock/indicator/` 目录 ⇒ 要新建 `/etc` 下的文件（需 root），
  不适合普通用户应用 ⇒ **不走这条**。

### E.1i C++ 项目的图谱/置信度**长期是残的**（批 Z 查明并已修引擎侧 —— **deepin 是 C++ 项目，吃亏最大**）

批 Z 去查「`index query` 到底该不该接 GUI」，顺手量了一次引擎在 **deepin 自己身上**
的表现 ⇒ 照出**两个一直没人注意的引擎侧缺口**。

**缺口 ①：C++ 自由函数几乎全扫不出来。**
图谱扫描器是**关键字 + 形态**驱动的（`func`/`def`/`class`/`struct`/…）。
C++ **没有函数声明关键字**，只有 C 系的形态兜底（`返回类型 name(` + 行内含 `{`）。
而 deepin 用的是 **Allman 风格**（`{` 另起一行）⇒ 签名行里没有 `{` ⇒ 判否。
实测：`deepin/src/**/*.cpp` 顶层自由函数 **364 个，引擎只认出 1 个**（漏 99.7%）。
`class` 也不在 C 系的声明词表里 ⇒ C++ 的类**一个都不认**
（`TrayController` / `PanelWindow` / `AppModel` 在图谱里根本不存在）。

**缺口 ②：未解析调用的「接收者豁免」差一位。**
代码注释承诺「接收者调用（`a.b()`）豁免」，实现却是读**前一个 token** 的标记
（`dotBuf[ti - 1]`）⇒ 对最常见的一层成员调用**不生效**（只有链式 `a.b.c(` 恰好命中，
把 bug 掩盖了）；`->` 与 `::` 两种隔断**根本没有豁免规则**。

**后果链（为什么这不只是「少几个符号」）**：

1. 符号漏扫 ⇒ 置信度的 `unresolved-call` 判据是「调用了全仓没有定义的名字」
   ⇒ **对真实自由函数的调用被误报成「幻觉 API」**。实测 deepin 客户端
   **295 条「幻觉调用」**里，`clipNote`（`ai/AgentCore.cpp`）、
   `runOne`（`ai/AiDigests.cpp`）、`defaultToolName`（`ai/MockEngine.cpp`）
   这些**确实存在**的函数被逐条点名。
2. 符号漏扫 ⇒ **函数体边界**（= 本符号行 → 下一个符号行）算错 ⇒ 中间那些没被
   认出的定义不占边界 ⇒ 前一个函数的「函数体」把中间函数的 if/for 全吞进去
   ⇒ **凭空多出高复杂度告警**（`clipNote`（2 行）被判「圈复杂度 13」）。
3. 接收者豁免失效 ⇒ `QDateTime::currentMSecsSinceEpoch()` 这类标准库静态调用
   被逐条指控。

**已修（引擎仓 `fix/cpp-graph-symbols`，提交 `64decd1`）**：
C 系函数名**统一**按「紧跟参数列表 `(` 的那个标识符」取（修掉限定返回类型
`EngineCli::EngineResult classifyResult(…)`、const/指针限定
`const EngineDoctor::Report *doctorReport() const`、限定名成员函数定义
`bool AgentCore::runEngineRaw(…)` 三种形态）⇒ 两种写法（`{` 同行 / 另起一行）
口径一致；新增 Allman 风格签名识别 + `pendingCSig` 待定状态（区分**原型声明**）；
`tables["c"]` 补 `class`；接收者豁免修 off-by-one 并补 `->` / `::`。

**实测效果（deepin 客户端 369 文件）**：

| 指标 | 修前 | 修后 |
|---|---|---|
| 符号总数 | 2180 | **3232**（+1052） |
| deepin 模块符号 | 489 | **1541**（3.2 倍） |
| unresolved-call（幻觉调用） | 295 | **159**（-46%） |
| 其中「成员/限定调用」类误报 | 106 | **0** |
| high-complexity | 49 | 179（**都是此前压根没被扫到、因而没被检查的真实函数**） |
| 置信度得分 | 68 | 68（幻觉调用减掉的罚分与复杂度增多的罚分抵消） |

⇒ **分数没动，但内容从「一半是假的」变成「基本可信」**。抽查 `executeTool`（21）/
`fromScript`（12）/`run`（23），与源码分支数相符 ⇒ 新增告警成立。

**⚠ 仍然存在的结构性局限（诚实记录，本次不修）**：
C++ **没有 import 机制** ⇒ 标准库/第三方库的名字永远不会出现在仓里 ⇒
「全仓无定义 ⇒ 幻觉 API」这条判据在 C/C++ 上**天然有误报**。
实测剩下的 91 条里，**glib / Qt 的外部自由函数**（`secret_password_*`、
`g_error_free`）与**局部变量声明形态**（`QFile tar(path);`）占大头。
这两类要靠「库白名单」或「声明形态」判定才能消：白名单追不上所有库，
声明形态判定有放过真幻觉的风险 ⇒ **交给使用方在展示层说明**，不在引擎里堆启发式。

**⇒ 对 deepin 的影响**：**不需要改客户端一行代码** —— 客户端的置信度页签/热力图
直接受益（已把新引擎装到 `~/.local/libexec/deepdolphin/moongit.bin`，
旧版备份 `moongit.bin.bak-20261020`）。
⚠ 但**引擎仓与客户端仓是两个仓**：引擎修复要**先合进引擎再发版**，否则客户端
拿到的还是旧引擎 ⇒ 批 P 那条「引擎 release 带 Linux x64 资产」的需求因此更紧迫。

#### ⚠ 批 AA 勘误：我在批 Z 把 `index query` 说成「新维度」，**推过头了**

批 Z 为了论证「`index query` 该接 GUI」，顺手写了三句「原判据不成立」。
批 AA 复核时**实测发现其中一句是错的**，并据此**撤回「推翻」**：

| 批 Z 的说法 | 批 AA 实测 | 判定 |
|---|---|---|
| ① 「`graph functions` **根本没有 tier**」 | `moongit graph functions ddTest --json` ⇒ `functionEdges` **5274 条，每条都带 `tier`**（值域 direct / guessed / resolved） | ❌ **错** ⇒ 原判据「`tier` 两边都有」**成立** |
| ② 「`defs[]` 是按符号查，`functions[]` 是全项目列表，不是重排」 | 成立（`index query chooseBackend` 给 1 条 defs + 3 条 callers；`graph functions` 给全项目函数列表） | ✅ 对（但这是**取数形态**差异） |
| ③ 「`findings` 在 `index query` 是计数、`graph functions` 是数组」 | 成立（`defs[].findings` 是 int） | ✅ 对（同样是**载荷形状**差异） |

⇒ **结论回到原处**：`index query` 与已接的 `graph functions` **同维度**
（都是「函数级调用边 + 边的确信度档位 tier」），只是**取数路径不同**
（一个给全项目边列表，一个按符号反查）⇒ 台账原判据「**重叠 ⇒ 判定不接 GUI**
（接了会造出第二个真相源）」**基本正确**，C 节那两行「未接 GUI（候选）」已改回。

⚠ **批 Z 唯一仍然成立的收获**：引擎修复**解锁**了 `index query` ——
修前 C++ 符号压根不在索引里（`index query chooseBackend` ⇒ 「符号不在索引中」），
修后能返回 3 个函数级调用方（带 `tier: resolved`）。
⇒ **解锁 ≠ 该接 GUI**。

**教训（记在这里，不只记在脑子里）**：我犯的错不是「没查」，是**查了 `index query`
就以为把 `graph functions` 的载荷也一起量了**。批 Z 里我**没跑 `graph functions`**，
是拿 `graph symbol`（**文件级** `referencedBy`）和 `graph impact`
（自报 `granularity: "lexical-file-level"`）去对比 ⇒ 比错了对象。
⇒ **判据纪律**：要比「重叠」，就得**两侧都实测**；拿**另一个已接能力**去比，
比出来的「新维度」是假的。

---

### E.1j 固定文档页的四语言（批 AA —— **B8 的第一块**，也是 mac 抄不动的那块的证明）

**批 AA 要干的事**：把 B8（全应用四语言本地化）**整块做完一块** ——
先做**固定文档页**（关于 / 帮助 / 开源感谢 / 更新日志）：判定层 `logic/DocPages`
从「只有 zhCN」扩到 **zhCN / en / zhTW / ja**（与 mac 的 `AppLanguage` 一一对齐），
四类文档各四种语言的正文**全部给全**，文档窗内加**语言选择器**，选完持久化。

**为什么敢先做这一块**：B7（批 G）已经把四类文档页的**类目结构**做完了，
正文是**写死在代码里**的长文（不取引擎）⇒ 扩语言**只加常量、不改结构**。

**⚠ 三条纪律（本批的判据都从这三条来）**：

1. **不抄 mac 的残缺译文**。mac 的 `DocsPages.swift` 的 zhTW / ja **比 zhCN 少好几节**
   （它自己就没写全）⇒ 抄过来就是「四语言里两语言是残的」⇒
   **按 deepin 的中文底本逐篇写全**，事实按 deepin 写对（Qt 6 + DDE / DTK、
   deepin / UOS 桌面版、仓颉/Cangjie）。
2. **文案全在判定层**。**文档窗里**一个中文字面量都不许有 ——
   ⚠ **批 AG 订正**：原文写的是「UI 里一个中文字面量都不许有（接线门用 `arch_forbid` 盯）」，
   而当时那道门盯的是 **`QStringLiteral(`** —— **说法比门宽**：
   `QString::fromUtf8("中文")` / `tr("中文")` / 直接字面量**都绕得过去**。
   ⇒ 批 AG 补了 `arch_forbid_han`（盯**内容**：汉字/中文标点本身）。
   ⚠ **范围必须说清**：「文档窗零中文字面量」是**已达成且有门**的；
   **「全应用 UI 零中文字面量」是 M2-5 的待办**（1019 条要人工翻译）——
   **不许把后者当既成事实**（那正是「说法比门宽」的另一种形态）。
   否则「四语言」只是换了个标题，正文和按钮还是中文 ⇒ **中英混杂，比不做更糟**。
3. **不静默回落**。语言键认不出 ⇒ 判定层 `languageFromKey` 返回 **`std::nullopt`**
   （不猜、不回落成中文）；落地方案在 `resolveLanguage`（**回落 + 标记**），
   UI 据此**说一句**（并把坏键改回落到的语言）。

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

**判据**：selfcheck **+22 条**（374/0）、接线门 **+48 项**（466 项全绿）。
门项里有一条是 `arch_forbid "DocsDialog.cpp" 'QStringLiteral\('` ——
**文档窗里不许自己写死任何文案**（全在判定层，四语言共用一份）。

**⚠ 持久化键是 `app.language`**（与 mac UserDefaults 的同名键**逐字对齐**，
`L10n.swift:2042`），取值同一套 `zh-CN` / `en` / `zh-TW` / `ja`。
⚠ deepin 目前**只有固定文档页**跟它走 ⇒ 文档窗的语言选择器**悬浮提示如实说明**
（「目前只影响这一窗，其余界面仍是简体中文」）—— 不说的话就是不诚实的承诺。
⇒ 全应用化之后**还是同一个键**，不迁移、也不会有两个「语言设置」打架。

**⚠ 补了一道**行为**门**：接线门是**源码扫描** —— 它能证明「代码里写了
`setButtonText`」，但**证明不了**「换语言后按钮真的变了」（扫描看得见调用，看不见结果）。
⇒ 新增无头探针 `--docs-lang-probe`（`src/ui/dialogs/DocsDialogProbe.{h,cpp}`）：
**真跑**一遍四语言切换，逐语言报出文档窗的**实际呈现**（标题 / 关闭按钮 / 四个类目
分段名 / 正文 / 底部说明），断言脚本 `scripts/ci-docs-lang-probe.sh`（CI 第 4 门）核对
「四种语言两两不同 / 英文档无汉字 / 呈现里无 `%1` 残留」。
⚠ 探针会切语言 ⇒ 会写 `app.language` ⇒ 走 `QStandardPaths` **测试模式**且以
`::_exit` 收尾（QSettings 根本不落盘）⇒ **绝不碰用户的真实设置**（实测：探针跑完
`~/.config/deepin/deepDolphin.conf` 的 mtime 没变）；探针的「字段名」是机器格式 ⇒
单独放探针文件，不去破「文档窗零字面量」那条纪律。

**⚠ B8 的真实规模（这一条比上面所有实现都重要）**：
deepin 用户可见中文串 **1008 个去重 / 1186 次出现**；而 mac `L10n.swift` 的
zh-CN 表只有 **483 键** ⇒ 把 mac 的译文**逐字**搬过来，只命中 **155 个（15%）**，
**85% 要新写**，其中中日尤甚 ⇒ 台账原记「P2（量大）」**低估**了。
⇒ 全应用 i18n **不是一批能做完的活**，要做也得**先解决「谁来翻」**（人工翻译）。
⇒ 本批只做固定文档页（内容自写、可控），**不铺开**（半吊子本地化会中英混杂）。

⚠⚠ **「1008」这个数的口径（批 AG 补 —— 不写清口径，下一个人会量出别的数）**：
批 AG 用脚本重算了一遍，得到**三组数**：
| 口径 | 去重数 |
|---|---|
| 剥注释后**全部**中文字符串字面量（含判据描述、夹具、16 篇正文） | **1520**（91 个文件） |
| 再排除**非用户可见**的三处（`app/SelfCheck.cpp` 判据描述 437 / `logic/DocPages.cpp` 16 篇正文 56 / `logic/SnapshotFixture.cpp` 夹具 23） | **1019** |
| 台账原记 | **1008** |
⇒ **原数字是对的**（1019 vs 1008，差 11 是口径微差：`tr()` 包裹的、
`QString::fromUtf8` 的、个别归类不同）⇒ **不改数字**，但**要把口径写清**：
否则下一个人按「全量 1520」去对照台账，会以为台账错了 ⇒ **照着做会走错方向**
（这正是批 AE 立下的纪律：入口失真必须先核对再动手）。

**⚠ B9（设置改原生独立窗口）判定：不做** —— 实质只是「设置从对话框变独立窗口」；
deepin 的 `AiSettingsDialog` 已是 `DDialog` 且**有「关闭」按钮**，
mac 那个 sheet **无关闭按钮**的问题在 DDE 下**根本不存在** ⇒ 价值低。

**顺带照出的一处台账失真**：批 AA 复核时发现我在批 Z 把 `index query` 说成「新维度」
是**推过头了** —— 已在本节上方的「批 AA 勘误」里实测更正并**撤回「推翻」**。

### E.1k 发版链打通 + 工具面收敛（批 AB —— **「引擎发版」这件事第一次真的跑通，也第一次照出坏包**）

**背景**：批 Z 之后引擎侧攒了 4 个提交（版本号单一真相源、旧名别名的机器可读废弃标记、
发版规矩落文档、发版 workflow 修好）一直**只在本机** —— 客户端本机装的是手工编译的引擎，
用户装的仍是 `v0.1.0`（**只有 darwin-arm64 资产，无 Linux x64**）⇒ 批 P 的下载链
在真机上仍然拿不到引擎。⇒ 本批把「发一个带 Linux x64 资产的 release」做掉。

**① 发版链第一次真跑通**（引擎仓 `dev`）：v0.2.0 发布，两个资产齐
（`moongit-v0.2.0-linux-x64.tar.gz` 7.5MB / `moongit-v0.2.0-darwin-arm64.tar.gz` 7.8MB），
`releases/latest` 正确指向 v0.2.0，GitHub 侧 sha256 与本地实测一致。
⇒ 过程中修掉**两个只会在 CI 上炸**的问题（引擎仓 AGENTS.md 不变量 139/140）：
· **release job 403**：仓库默认 `GITHUB_TOKEN` 权限是 read-only ⇒ 建 release 被 API 拒
  （两个构建 job 全绿，就挂在「Create Release」）⇒ workflow 显式 `permissions: contents: write`；
  顺带把 `workflow_dispatch` 补成**显式传 tag**（手动触发时 `github.ref` 是分支，
  不处理会 checkout 到分支代码、还把 release 建在分支上）。
· **Linux 产物是坏包**：客户端端到端装完**引擎跑不起来**（`exec: .../bin/moongit-cli: not found`）
  ⇒ 查出来 CI 产物的 `runtime/lib/` 是**空的**（本地打的同一个包是好的）
  ⇒ 根因：`package-release.sh` 的 Linux 分支用 **`ldd`** 找仓颉库，而 `ldd` 解析依赖靠
  **运行时的库搜索路径**（`LD_LIBRARY_PATH`）—— 本地同一个 shell 里 source 过 `envsetup.sh`
  所以找得到，**CI 的每个 step 是独立 shell**（`Package` 步骤没 source）所以全部 `not found`
  ⇒ 脚本**静默**一个库都不拷，照样打印「✓」、流水线全绿、release 照发。
  ⇒ 改法：依赖清单用 `readelf -d` 的 `DT_NEEDED`（读二进制本身，不看运行时环境）、
  库来源用 SDK 目录（找不到就 `exit 1`）、**打包后真的解包跑一次**（`env -i`）——
  原来脚本只**打印**自验口令、从不执行，等于没有自验。
  ⇒ **v0.2.0 的 Linux 资产因此是坏包，用 v0.2.1**（已在引擎 README 与 release 说明里标注）。

**② 客户端下载链按真实布局落盘**（原来那套是**虚构布局**）：
客户端的 `logic/EngineDownload` 假设「包根只有一个 `moongit-cli`」⇒ 真实发布包的根部是
**启动器 `moongit`**，真二进制在 `bin/moongit-cli`、仓颉运行库在 `runtime/lib/`
（启动器按**自身所在目录**找后两样）⇒ 三样必须**一起**落盘。
⇒ 改：`packagedBinName()` = `moongit`、新增 `packagedDirs()` = {bin, runtime}；
`app/EngineInstaller` 改为**整包**解到安装目录（原来只拷一个文件）
⇒ 只拷启动器的话装下来的引擎 exec 不到二进制 / 加载不到运行库。
⇒ 契约门第 21 组的夹具**同步改成真实布局**（原来那个夹具是虚构的 ⇒ 测过的路径真实资产根本走不到）。

**③ 工具面收敛（模型可见面剔除旧名别名，可执行集不变）**：
引擎 0.2.0 起给旧名别名**机器可读**的 `deprecated:true` + `replacedBy`（6 个别名）
⇒ 客户端 `models/ToolsEnvelope` 读这两个字段，`ai/AgentCore` 只把**非废弃**的给模型，
而**必填校验表仍收全部 28 个**（契约门第 12 组要求「可执行集 == 引擎声明集」，
收敛的只是「**推荐给模型**的那一面」）。
⇒ 实测：模型可见 **22** 个（引擎标的 6 个别名已剔除）、可执行/可校验 **28** 个（别名仍可调用），
系统提示词里的清单与模型面**同一口径**（否则模型会去调「提示词里有、工具表里没有」的名字）。
⇒ 缺省**不是**废弃（老引擎没给标记 ⇒ 不收敛）；继任者缺席 ⇒ 判成**收敛不自洽**（不静默放过）。

**⚠ 判据跟着真相走（第二轮收紧，又照出两个真问题）**：
初版探针脚本把 6 个别名名**硬编码**在脚本里 ⇒ 引擎将来增减别名时这道门就跟不上真相
（新增别名 ⇒ **漏检**；取消标记 ⇒ **假红**）⇒ 改成探针从引擎**原始清单**解析出
「被标记的是哪些」（`engine_deprecated_names=`）、脚本**按引擎给的名字**断言，
并加**数量自洽**断言（校验表数 − 模型面数 == 被标记的别名数 ⇒ 只剔一部分/多剔非别名都抓住）。
⇒ 顺带照出：**并非所有 `codegraph_*` 都是废弃别名** ——
`codegraph_patch_confidence` / `codegraph_patch_merge` 是**新功能**（引擎没标废弃），
它们**应该**留在模型面 ⇒「按前缀一刀切」是错的判据。
⇒ 还照出「**收敛口径有两处实现**」：模型面在 `ai/AgentCore` 自己写了一遍 `!t.deprecated`，
提示词却用判定层的 `activeJson()` ⇒ **两处实现、碰巧一致** ⇒ 统一到判定层
`ToolsEnvelope::activeTools()`（**单一真相源**）。
⇒ 负控累计 **15 项真红 / 0 未红**。

**④ 一条工程纪律（本批真踩到，差点误判成产品 bug）**：
做负控要**改源码**再还原。用 `cp` 备份 + `mv` 还原时，**`mv` 保留 mtime** ⇒ 还原后的文件
mtime **比 .o 旧** ⇒ `make` 按 mtime 判断「无需重编」⇒ **跳过了重编** ⇒
**二进制里留着负控那版实现** ⇒ 判据结果失真（本次表现为 `packagedDirs()` 只剩 `bin`，
而源码明明是 `{bin, runtime}`）。
⇒ 纪律：**负控还原后必须 `touch`（或强制重编）再跑判据**；否则「判据红了」可能只是在测一个
**不存在的二进制**。判据结果只有在「源码 == 二进制」时才作数。

**⑤ 本机网络事实（影响验收方式，不影响产品）**：
`github.com/.../releases/download/...`（302 到 `objects.githubusercontent.com`）在本机
**TCP 通但数据流卡死**（curl 与客户端都卡），而 `api.github.com` 与 `gh release download` 路径可用
⇒ 端到端验收改用**本地 fixture**（`python3 -m http.server` 提供 release JSON + **真实发布的资产文件**）
⇒ 验的是客户端的**真实逻辑**：查 API → 下载 → sha256 校验 → 解包 → **整包落盘** → 探活。

### E.1l 引擎下载链的网络韧性（批 AC —— **批 AB 的实测直接带出来的**）

批 AB 第一次下载 v0.2.0 资产时，客户端直接报
`{"ok":false,"stage":"downloadFailed","message":"下载中断：Connection closed"}`，
**同时 curl 也卡死 90 秒无数据**；**稍后重试同一个 URL 1.17 秒就下完 7.5MB**。
⇒ **网络瞬断是常态**，不是「没网」⇒ 一次失败就放弃，等于把**可恢复的故障**变成
「用户必须手动再点一次」⇒ 下载链**必须能重试**。
（引擎获取是「引擎缺失时用户唯一的出路」—— 这一条路径上的一次抖动，代价是用户装不上引擎。）

**改动**（判定层 `logic/EngineDownload` + 执行层 `app/EngineInstaller`）：

| # | 决策 | 为什么 |
|---|---|---|
| 211 | **只重试「再试一次可能成」的故障**（白名单：连接被关 / 超时 / 未知网络错 / 服务端 5xx） | HTTP 404/403、主机不存在、连接被拒**重试没意义**，只是让用户干等 |
| 212 | 判定用**白名单**而不是黑名单 | Qt 将来新增的错误码默认**不**重试 ⇒「漏重试」只是慢一点，「乱重试」是把 404 试三遍 |
| 213 | **重试有上限**（3 次）且**退避递增**（1s→3s→9s） | 无限重试 = 用户干等；不退避 = 立刻再撞同一个坏网络 |
| 214 | 两个阶段（查发布信息 / 下载资产）**都**能重试 | 实测里 GitHub 侧 443 抖动会让**查询**也失败，不是只有下载会 |
| 215 | 最终仍失败时，文案带「**已重试 N 次仍失败**」 | 不许只给一句「下载失败」——用户要知道已经试过几次 |

**判据**：
· selfcheck **+2**：可重试判定（含**明确排除**永久故障）；重试有上限且退避递增、越界输入要防御。
· 契约门第 21 组 **+3（行为门）**：本地 HTTP 打桩 ——
  ①「前 2 次请求**直接断开连接**（不发响应）⇒ 重试后**仍装成功**」；
  ②「一直断连 ⇒ 到上限后**最终失败**（不是无限重试）」。
  ⚠ 打桩的 `release.json` 必须由**服务器自己生成**（端口是运行时才定的 ⇒ 预置 JSON 里 URL 写不对）。
⇒ 负控 **3/3 真红**（不重试 / 不认可重试 / 重试无上限）；累计负控 **18/18 真红**。

### E.1m D7 的**准**验收：deb 产物的「装完能不能用」（批 AD —— **照出一个真 bug**）

**背景**：D7 的最终验收是「干净 deepin 25 容器里 `dpkg-deb -b` + 安装 + 启动」，
本机**没有容器运行时**（无 docker/podman）⇒ 那一段做不了。
⇒ 但「装完能不能用」里**不依赖容器**的那一半是可以做的：把 deb **解包**到临时目录
（**不装进系统、不污染本机**），按**包内的真实布局**逐项查「装完之后点图标能不能起来」。

**⚠ 这一门第一跑就抓到一个真 bug（而且是两条叠在一起的）**：
`data/cn.deepdolphin.app.service` 原来写的是 `Exec=deepDolphin --dbus-service` ——
① **裸命令名**：**实测**（本机 dbus 1.16.2）dbus-daemon 激活服务时**不做 PATH 搜索**：
   裸名 `true`（明明在 `/usr/bin` 里）也报 `Spawn.ExecFailed: No such file or directory`，
   而绝对路径 `/bin/false` 能 exec 成功（报的是 `ChildExited`）
   ⇒ **从启动器点图标 ⇒ 总线 exec 不到 ⇒ 激活失败、应用起不来**；
② **`--dbus-service` 这个 flag 客户端根本不认识**（全项目 grep 无此 flag）
   ⇒ 即使 exec 到了，参数也被忽略。
⇒ 两条合起来 = **deb 装上、图标在启动器里、点了没反应**。

**修**：`Exec=/usr/bin/deepDolphin`（**绝对路径**、**无参数**）——
D-Bus 激活 = 正常启动客户端，它在 GUI 主路径里自己注册 `cn.deepdolphin.app`
（`main.cpp` 的 `AppService::registerOnBus`）。
⚠ 绝对路径与安装路径必须一致 ⇒ `scripts/build-deb.sh` **打包期校验**：
路径不一致、或 Exec 带了参数 ⇒ **直接构建失败**（不让两处悄悄漂）。

**新门** `scripts/check-deb-layout.sh`（**ci.sh 第 12 门**），10 项：
可执行在包内且可执行 / service 的 Exec 是绝对路径 / service 的 Exec 指向的可执行在包内存在 /
service 的 Exec 不带参数 / desktop 的 Exec 指向的可执行在包内存在 / desktop 的 Icon 在包内有图标 /
`DBusActivatable=true` ⇒ service 文件存在 / metainfo 的 `<id>` 与 desktop 文件名一致 /
可执行在**空环境**下能跑 `--version` / 包内图标都非空。
⇒ 负控 **6/6 真红**（service 裸名 / 带假 flag / 指向不存在的可执行 —— 三条都被**打包期校验**拦住；
绕过校验后**门 12 自己**也能抓住 ⇒ 两道防线；Icon 指向不存在的图标 / 零字节图标 —— 门 12 抓住）。
⇒ 累计负控 **24/24 真红**。

**⚠ 顺带订正 M3c 的一处过时描述**（实测，不是推测）：
M3c 写着「清第二套色板、两种红/两种蓝」，但 **D2 门的 `fix` 豁免清单已经空了**
（只剩 `keep`：令牌定义处、判据夹具、Canvas 契约层等）⇒ **色值散值已归零**。
且 `logic/SemColors.h` 里那**两档红是有意区分的**（`red` #DC2626 = 读不出来/危险；
`stale` = 停滞告警、托盘专用），注释里**明写「不是笔误」** ⇒ 「修两种红」是**过时**的要求，
真要合并反而会丢掉语义。⇒ M3c 剩下真正未做的是：图标名 / 动效 / 响应式 / HiDPI / 分隔线 / 托盘 busy 态。
⚠ **批 AM 实测校准「响应式」**：KPI 网格**固定 2×2**（无 resizeEvent）、mac 侧**固定 4 列** ⇒ PLAN 原提案「1/2/4 列」是**无对位**设计 ⇒ 不做（已写回 PLAN）；**`AgentDialog` 固定尺寸已改可缩放**（全仓最后一个，现已归一）⇒ 响应式这条**只剩「KPI 网格列数判定归判定层」这一件**将来**要做的事（现在没有判定可下沉）。

**⚠ 托盘 busy 态为何暂不做**：deepin 托盘是**自创**的（**mac 侧根本没有托盘** ——
`macos/Sources/deepDolphin/` 里无任何 `NSStatusItem`/`NSStatusBar` 引用）
⇒ 没有 mac 对位可抄，也不是用户提过的需求；而托盘**弹窗**里的 busy 态**已经有了**
（`BusyRow` 转圈 + 「读取中…」）。⇒ 排在真正有 mac 对位/用户提过的项之后。

### E.1n D7 的另一半「装得上」+ **PLAN 入口校准**（批 AE —— 校准比做事更要紧）

**① D7 的另一半：D7 的「准验收」（批 AD）只覆盖了「产物自洽」，没覆盖「目标机装得上」**：
`build-deb.sh` 原有的 **2f** 验的是「依赖清单里的包**本机装着**」（`dpkg-query`）——
⚠ 那**不等于**「**目标机装得上**」：开发机装着的包可能来自私有源、或已从源里移除
⇒ 目标机（干净 deepin 25）会「找不到包」⇒ **deb 装了却用不了**。
⇒ 新增 **2h**：「依赖清单里的每个包在 **apt 仓库**里都有候选（`Candidate:` 不是 `(none)`）」。
⇒ 实测：本机 deepin 25 源里 **17 个依赖包候选齐全，缺失 0** ✓（含 `dde-qt6integration` /
`dde-qt6xcb-plugin` / `libdtk6*` / `libqt6*` / `libsecret-1-0` / `libxcb1`）。
⚠ **2h 与 2f 的分工**（别以为 2h 能单独抓包名错误）：
2f 抓「包名写错 / 本机没装」；2h 抓「本机装着、但目标机源里没有」。
⚠ 「apt 查不到该包」会输出**空**（与「本机没配源/离线」无法区分）⇒ 那种情况 2h 判 SKIP
（不误红）⇒ 由 **2f** 兜住。

**⚠⚠ 踩坑：apt 的输出是「本地化」的**（本机是中文「候选：」而不是 `Candidate:`）——
只按英文写脚本，换台机器/换 locale 就**全部误判成缺失**。
⚠ 实测踩过：17 个明明存在的包全被判「查不到」。
⇒ 判据脚本里凡碰 apt 输出，**必须 `LC_ALL=C`**（同理适用于任何按英文关键字匹配的输出）。

**② PLAN 入口校准（5 条，每条附实测证据）** ——
⚠ **台账是对的、PLAN 是错的**（M1-3 那条台账早就写明「正解不是迁 SNI」，PLAN 标题还写着
「托盘迁移 SNI」）⇒ **照 PLAN 做事会走错方向** ⇒ 入口失真必须定期核对：

| 条目 | 校准 | 实测证据 |
|---|---|---|
| M0-11 固定文档页四语言 | [~] → **[x]** | 16 篇正文齐全/同类目两两不同/英文无汉字/日文有假名/小节数一致；接线门 466 项；四语言**行为**探针本轮重跑仍绿 ⇒ 主体已全部完成（全应用 i18n 属 M2-5，不在这条） |
| M1-3 托盘 | **方向订正**：deepin 走**托盘窗口协议**，不是 SNI | 批 Y 实测 + 本轮读到 `m_sniMode` 分支；**mac 侧根本没有托盘**（`macos/Sources/deepDolphin/` 无 `NSStatusItem`/`NSStatusBar` 引用）⇒ 无对位可抄 |
| M3b 组件化 | 标注**主体已全部完成**，只剩 KPI 骨架屏 + 真机目检 | 本轮实测：`src/ui/common/` **17 个组件**、散落的次级标签样式 **0 处**、`SegmentedButton` **只一份** |
| M4b `ci.sh` | 「deb 构建未做」**已过时** | 本轮实测：ci.sh **12 门**（第 11 门 deb 构建、第 12 门 deb 布局验收），全绿；只剩「系统 Qt6/DTK6 矩阵」那一步 |
| M2-7 deb 打包 | 补批 AD 的准验收与批 AE 的 2h | 见 E.1m 与本节 ① |

⇒ 负控 **3/3 真红**（2h 判成「源里没有」⇒ 构建失败；禁用 2h ⇒ 那行输出消失；复原后恢复）。
⇒ 累计负控 **27/27 真红**。⇒ ⇒ ⚠⚠⚨ **根因已在批 ED 定位**（⇒ 见 `E.2cm`）：真因是**双跑覆盖面门把契约门的退出码 + 措辞写进自己的输出**，而契约门 rc 随**网络可达性**在 0/3 之间摆 ⇒ ⇒ 输出措辞随之摆 ⇒ ⇒ 「4 例附加断言间歇不过」**不是**环境抖动 ⇒ ⇒ 本条**订正**。

**③ 元教训**：**台账与 PLAN 是两个入口，谁错了都会带偏下一批** ——
台账 E.1b 早就照出「PLAN M2-6 的描述是失真的」，本轮又照出「PLAN M1-3 的方向与台账相反」
⇒ 纪律：**每批动手前先核 PLAN 那一行的现状**（用代码/门实测，不是凭记忆），
并把核对结果**写回 PLAN**（否则下一批还会照着过时描述做）。

### E.1o 引擎安装的「先破坏后验证」（批 AF —— **批 AB 那个坏包的真正代价**）

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
⇒ 装到一个跑不起来的包时，**原来能用的引擎已经被顶替成坏的了**。
⚠ 这在 v0.2.0 那个坏包上是**真实发生过**的（`runtime/lib/` 是空的 ⇒ 启动器加载不到仓颉运行库）。
⚠ 更隐蔽的后果：坏引擎**占着 `~/.local/libexec/deepdolphin/moongit` 这个位置**
⇒ 引擎发现链会找到它 ⇒ 应用以为「引擎在」⇒ 一调用就报错。

**② 改成「旁路构建 + 通过后切换」**（判定层 `logic/EngineDownload` + 执行层 `app/EngineInstaller`）：

| 步骤 | 旧 | 新 |
|---|---|---|
| 解包去向 | 目标目录（**先删旧**） | **旁路目录** `<dir>.staging`（**不碰**目标目录） |
| 探活 | 切过去之后才探活 | 在**旁路**里探活 |
| 切换 | 解包即覆盖（非原子，中途失败留半个引擎） | **改名**（同一父目录 ⇒ 同一文件系统 ⇒ 原子） |
| 失败后果 | 旧引擎被顶替成坏的 | **旧引擎原封不动** |

切换序列：旧的挪进 `<dir>.backup` → 旁路**改名**成目标目录 → 确认成功才删 backup；
中途失败 ⇒ 从 backup **回滚**（不让用户落到「没有引擎」的状态）。

**③ 顺带补上「拒绝降级」**：下载到的版本比已装的**旧** ⇒ 拒绝（`stage=versionDowngrade`）。
⚠ 这不是「版本越高越好」的洁癖 —— `releases/latest` 理论上不会降级，但
**用户自己装过更新的版本**（或 owner 撤回了 release）就会降级 ⇒ 把能用的换成不能用的。
⚠ **版本未知时不判降级**（解析失败不该挡掉一次合法升级 —— 挡错的代价更大）。

**④ 判定层新增的纯函数**（`models/`、`logic/` 零 QWidget 头 ⇒ 可单测）：
`stagingDir()` / `backupDir()` / `hasInstalledEngine()` / `parseEngineVersion()` /
`compareVersions()` / `isDowngrade()` / `preserveNote()`。
⚠ `parseEngineVersion()` 必须**锚定 "Engine"**：探活输出是
`moonGit Engine 0.2.1 (Cangjie 1.0.5 LTS)` —— 括号里的 `1.0.5` 是**仓颉 SDK** 的版本，
不锚定就会把 SDK 版本当成引擎版本去比大小。
⚠ `compareVersions()` 必须按**数字段**比：`0.2.10 > 0.2.9`（字符串比会判反）。

**⑤ 判据**：
- selfcheck **388/0**（+7：旁路目录与目标同级/版本解析/数字段比较/降级判定/失败说明三态/半个文件不算已装/引擎指纹能分辨「被换过」）
- 契约门第 21 组 **120/0**（+7 **行为门**：装坏包⇒旧引擎原样保留 / 装坏包后无旁路残留 /
  拒绝降级且旧引擎不动 / 版本更高⇒升级成功且跑的是新版本）
- ⚠ 新增失败分类 `versionDowngrade` ⇒ 「失败要说清是哪一种」从 **7 种变 8 种**（判据同步改）
- 新增 `--engine-download` 输出字段 `installedVersion` / `keptPrevious`（判据拿它们断言）

**⑥ 负控 6/6 真红**（累计 **33/33**）：
执行层改回「就地覆盖」⇒ 旧引擎被毁 / 版本解析不锚定 "Engine" ⇒ 取到 SDK 版本 /
版本比较改成字符串比 ⇒ `0.2.10 < 0.2.9` / 版本未知也判降级 ⇒ 误挡合法升级 /
旁路目录改成目标目录的**子目录** ⇒ 切换不原子 / 去掉降级拦截 ⇒ 能用的被换成不能用的。

⚠ **「负控无效」两次都照出了真东西**（这一条比「6/6」本身更值得记）：
- **第一轮 2 项无效** ⇒ 两个真问题：① 复现脚本只查「**文件还在不在**」，
  漏掉「**还在、但内容已被顶替**」（bug 的真实表现是顶替不是删除）⇒ 改成查**内容**；
  ② `parseEngineVersion` 的「锚定失败就退回全文第一个 x.y」这个兜底**太宽松**，
  负控改动**蒙对**了 ⇒ 补能分叉的夹具 `moonGit Engine (Cangjie 1.0.5 LTS)`
  （期望：**认不出来**）⇒ **并因此照出一个真 bug**：
  `engine[^0-9]*` 会跨过 " (Cangjie " 抓到 SDK 的 `1.0.5` ⇒ 收紧成 `engine[^0-9a-zA-Z]*`，
  且**文本里有 "Engine" 时不许再退回 loose**。
- **第二轮 1 项无效** ⇒ 真相是**负控补丁编译失败被静默吞掉**（给 `const QString&`
  形参赋值 ⇒ 编译不过 ⇒ 二进制根本没换 ⇒ 负控「假跑」，判据当然不会红）。
  ⇒ **负控脚本必须检查编译退出码**（`build_or_die`）—— 否则「判据不够强」与
  「负控根本没生效」两件事会被混为一谈。

⇒ **负控无效不是白跑**：它照出的是「判据不够强」或「实现有 bug」，两条都真。

### E.1p 让「文案全在判定层」这条纪律**有牙**（批 AG —— 门盯的东西与文档说的不是一回事）

**① 起因**：批 AE 立了纪律「每批动手前先用代码/门**实测核对**台账与 PLAN 那一行」。
本批照做，从批 AA 那条纪律入手查 ⇒ **两处文档（README 决策 202、台账 E.1j 纪律 2）都写着**
「UI 里一个中文字面量都不许有，接线门 `arch_forbid` 盯」——
⚠ **而那道门盯的是 `QStringLiteral(`**（`ci-wiring.sh` 的批 AA 段）：
**说法比门宽** ⇒ `QString::fromUtf8("中文")` / `tr("中文")` / 直接字面量**全都绕得过去**。

⚠⚠ **元教训 1：「门有没有」和「门盯的是什么」是两件事** ——
本批一度以为「门根本不存在」（grep 只搜了 `arch_forbid_tree`，没搜 `arch_forbid`），
查证后才发现门**在**，只是**盯的东西与文档说的不是一回事**。
⇒ **断言「门不存在」之前，要把同类门（单文件版 / 整树版）都搜一遍**。
⚠ 而且**文档写得比门宽**这件事，**比门缺失更隐蔽**：门在、门绿、文档说「有门管着」。

**② 补门（盯内容，不是盯写法）**：新增 `arch_forbid_han` ——
- 盯**字符本身**（汉字与中文标点，UTF-8 U+3000–U+9FFF），
  不盯任何 API 名字 ⇒ 换写法绕不过去；
- ⚠ **必须剥块注释**：现有 `strip_comments` 只剥**行注释**（perl `-p` 逐行）
  ⇒ 块注释里的中文说明会**假红**（门一加就红 ⇒ 门会被当噪音关掉）⇒ 新函数自己剥块+行；
- ⚠ 没有 perl 时**显式 SKIP**（不算通过）—— 宁可少一道门，不要一道会假红的门。
- 范围：**文档窗四件套**（`DocsDialog.{cpp,h}` + `DocsDialogProbe.{cpp,h}`）——
  判定层 `logic/DocPages.cpp` 里的中文是**16 篇正文**，本来就该在那儿。

**③ 文档订正（3 处）**：README 决策 202 / 台账 E.1j 纪律 2 / 台账 E.1j 判据段 ⇒
说清「门盯的是**内容**」+ **范围仅限文档窗**；
⚠ 并明确写下：**「全应用 UI 零中文字面量」是 M2-5 的待办**（要人工翻译），
**不是已达成** —— 不许把待办写成纪律（这跟「说法比门宽」是同一种病）。

**④ 顺带核实 M2-5 的规模数字（口径要写清）**：
批 AE 记的是「用户可见中文串 **1008** 个去重 / 1186 次出现」。本批用脚本重算：

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
一道盯写法的门（`QStringLiteral(`）和一道盯内容的门（汉字），
在「有没有门」这个粒度上看起来一样，在**能不能守住**这件事上差一个量级。
⇒ 写纪律时，「靠什么守住」这句要写得**和门实现一样细**。

**⑦ 元教训**：**「装得上」不等于「装得安全」** ——
批 AE 补的 2h（依赖在 apt 源里有候选）验的是「**装得上**」，
批 AF 这条验的是「**装坏了会怎样**」。⇒ 交付一条「装」字头的链，
要问两个问题：**装得上吗？装坏了会毁掉已有的东西吗？**

### E.1q 引擎缺失首屏接上下载入口 + 安装指引文案归判定层（批 AH —— **照出一批死基线**）

**① 起因（实测）**：引擎缺失时，用户**第一眼**看到的是首屏 `SetupGuidePage`。
而那时的首屏**只有**一个「重新检测引擎」——
⚠ **下载链只在设置页**（`GeneralPane`）⇒ 用户得先知道「设置里有」才用得上；
⚠ 首屏的提示文案还让用户去跑 `moonGit/scripts/install.sh` ——
那是**仓库里**的脚本，拿到 deb 的普通用户**根本没有那个仓库** ⇒ **指了一条走不通的路**。
⇒ 引擎缺失时**用户唯一的出路**必须在这块屏幕上，不许绕到设置页去找。

**② 改动**：
- 首屏加**主操作**「下载并安装引擎」（`DPushButton`），
  `downloadClicked` 信号 → 面板 → `m_model->downloadEngine()`；
  次操作仍是「重新检测引擎」；
- ⚠ **互斥禁用**：探测中/下载中两个按钮都不许点
  （两条链都在动引擎目录 ⇒ 互相干扰；下载中重探会探到**半装**的目录 ⇒ 结论是假的）；
- 判定层 `logic/EngineDownload` 新增文案真相源：
  `installHint()`（中性措辞，不提「上面/下面」——判定层不知道界面长什么样）、
  `downloadActionLabel()` / `downloadActionTooltip()` / `downloadBusyLabel()` /
  `downloadStatusText(found, pending, downloading)`（**四态**）；
- `AppModel` 转发 4 个 getter（**界面不自己读判定层**，与 `GeneralPane` 同一纪律）；
- `EngineLocator::installHint()` 改为**转发**判定层（旧文案弃用）。

**③ ⚠⚠ 照出的真问题：同一句文案三处各写一遍** ——
动手前先 grep，发现动作标签「下载并安装引擎」在**三处**硬编码
（首屏 1 + 设置页 2），悬停说明**逐字**抄了两遍。
⇒ **同一句话两个真相源 ⇒ 改一处漏一处** ⇒ **本批自己差点违反批 AG 刚立的纪律**。
⇒ 全部收进判定层，界面只取不改。

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
⚠ **死基线比没基线更隐蔽** —— 它让人以为「首屏有视觉保障」
（与批 AG 的「说法比门宽」同源：**看起来有保障，其实没有**）。
⇒ 改法：`--section setupguide`（**强制无引擎态**：不调 `locate()` ——
它的结果**依赖本机环境**（装没装引擎、`DEEPGIT_BIN` 指向）⇒ 基线不可逐字节重现；
显式构造**通用缺失态**，与 `locate()` 失败时同款）；
⇒ `ci.sh` 纳入 2 张 ⇒ 「重拍比字节」「换宿主时区比字节」两道覆盖它；
⚠ setupguide 段**不喂夹具**（要拍的正是「没有引擎、没有项目」的样子）；
⚠ setupguide 段**跳过「空态=失败」检查**（必然没有项目）⇒ 改用
**「拍到的确实是首屏」**（新增 `PanelWindow::showingSetupGuide()`）来防空门 ——
⚠ **文件名对不等于内容对**（又一个「说法比门宽」的变体）。

**⑥ 判据**：
- selfcheck **391/0**（**+3**）：安装指引**不含** `install.sh` 且给得出**可执行**的下一步
  （`DEEPGIT_BIN` / `~/.local/bin`）；动作标签/悬停/忙态**齐备且互不相同**；
  状态**四态互不相同**且下载中不说「没找到」；
- 接线门 **488 项**（**+18**）、ci.sh **12/12**、契约门 **120/0**（不变）、
  快照 **8 张**两次重拍逐字节一致 + 换宿主时区后仍一致；
- ⚠ 快照**只有那两张**变化（其余 6 张**零变化** ⇒ 改动没碰到别的页）；
- 负控 **6/6 真红**（累计 **41/41**）：界面抄文案 ⇒ 新门红／首屏直连判定层 ⇒ 门红／
  首屏下载入口被摘掉 ⇒ 门红／指引退回 `install.sh` ⇒ selfcheck 红／
  状态四态撞车 ⇒ selfcheck 红／setupguide 段没停在首屏 ⇒ 快照门红。

**⑦ 元教训 1：纪律立下后，下一批就要用它检查自己** ——
批 AG 刚把「文案全在判定层」立成纪律，批 AH 动手第一件事就是 grep，
结果**三处重复** ⇒ 差点自己违反。
⇒ 纪律不是写给下一批看的，是**每批开工前用来检查自己**的。

**⑧ 元教训 2：死基线比缺基线更隐蔽** ——
「没有基线」是明摆着的缺口（一看就知道要补）；
「**有一张没人比、拍不出来的基线**」看起来像有保障 ⇒ 更难被发现。
⇒ 每次动快照/基线，都要问一句：**这张图现在真的被某道门拍、真的被某道门比吗？**
（`docs/snapshots/` 里每一张都要能被 `ci.sh` 指名。）

**⑨ 未做 / 遗留**：
- 首屏里「重新检测引擎」等**非下载**文案仍是 UI 层硬编码中文 ⇒ 属 **M2-5**（人工翻译），
  本批只收编了**下载动作相关**的那一组；
- 引擎缺失时侧栏状态条显示「引擎连接失败」⇒ **实为既有口径**（`!engineFound()` 分支），
  非快照假象（已核 `PanelWindow::refreshChrome`）。

### E.1r M1-4 收尾（通知时长可配）+ 通知顶替规则下沉判定层 + **M1a 入口校准**（批 AI）

**① 起因**：PLAN M1-4 的四个子项里三个已做
（`desktop-entry` hint / `image-path` / `replaceId` 按类别顶替），
只剩**「`timeOut` 由 Settings 驱动」** ⇒ 实现里硬编码 `.timeOut(5000)`。

**② ⚠⚠ 顺带照出「说法与实现相反」**：`app/Notifier.h` 的头注释写着
「每条通知独立送达、互不顶替、**不用 replaceId**」——
而实现**一直用着** `replaceId` 顶替状态型通知。
⇒ 头注释是过时的（M1-4 改 `Notifier.cpp` 时没回头改 `Notifier.h`）。
⚠ **「说法与实现相反」比「说法缺失」更危险**：缺失会引人去查代码，
相反的说法会让人**照着它改代码**（把顶替逻辑删掉，理由是「注释说不用」）。
⇒ 已订正，并加门盯住（见 ⑦）。

**③ 顶替规则下沉判定层**（`logic/Notifications`，零 QWidget 头）：
`categoryOf(title)` / `replacesPrevious(title)` / `normalizeTimeoutMs(ms)`。
⚠ 原来规则写在执行层（要 **D-Bus 会话**才跑得到 ⇒ **无头测不到**）
⇒ 规则改了没人发现。纯函数化 ⇒ selfcheck 能钉死。

**④ ⚠ 时长必须归一**：D-Bus `expire_timeout` 的语义是
「毫秒；**0 = 永不消失**；-1 = 服务器缺省」
⇒ 0 绝不能原样传（用户会看到通知赖在通知中心不走）；
越界值会让「设定的」与「看到的」不一致 ⇒ 一律夹进 `[1s, 10min]`，非正取缺省 5s。

**⑤ 设置页加「通知」卡**（下拉 5/10/30/60 秒，选中即写回）：
⚠ 回填时若设置里的值**不在档位里**（手工改过配置文件）⇒ **如实加一项显示它**，
绝不「显示 5 秒、实际是别的」—— 那是在骗用户；
⚠ 回填**不写回**（否则「打开这一页」本身就会改设置）。

**⑥ ⚠⚠ M1a 入口校准（照批 AE 的纪律：动手前先实测核对 PLAN 那一行）**：
PLAN M1a 点名「容器/视图批（DListView/DTreeView/DBlurEffectWidget/DButtonBox）」，
本批**实测 DTK6 6.7.47**（头文件 + `nm -DC` 符号表双向核对）：

| PLAN 点名 | 实测 | 当前代码的落点 |
|---|---|---|
| `DListView` | ✅ 存在（**57 个符号**） | 侧栏 `SidebarNav` 用的是 `QListWidget`（**item-based**）⇒ 换过去要**重写数据模型**（model/view 架构） |
| `DTreeView` | ❌ **不存在**（**0 个符号**、无头文件） | **8 处 `QTreeWidget`**（`PatchCheckDialog` 3 + `CodeGraphDialog` 5）⇒ **换不了** |
| `DBlurEffectWidget` | ✅ 存在（76 个符号） | `TrayPopupWindow` 是**自绘窗口**，`paintEvent` 里已标「模糊留给后续」⇒ 要接，但**需真机验收**（本机托盘渲染本身是坏的） |
| `DButtonBox` | ✅ 存在（28 个符号） | 对话框用 `DDialog::addButton` ⇒ **当前无落点** |

⇒ ⚠ **PLAN M1a 那一行是失真的**：四个组件里**一个不存在**、**一个没落点**、
**一个要重写架构**。⇒ 已写回 PLAN（照批 AE 纪律：入口失真要校准，否则下批照着做会走错方向）。
⚠ **命名坑**：DTK 的 `DTreeWidget/`、`DListWidget/` 是**主题资源目录**，
**不是类** ⇒ 只 `ls` 目录会以为组件存在（本批第一轮就差点这么信）⇒ 必须查头文件 + 符号表。

**⑦ ⚠⚠ 照出「空门」**：那道「过时说法不许复活」的门若用现成的 `arch_forbid`
（它**剥行注释**）⇒ 过时说法住在**注释**里 ⇒ 门**永远绿** ⇒ **空门**
（空门比没门更糟：给人虚假的安全感）。
⇒ 补 `arch_forbid_raw`（**不剥注释**）⇒ 并用负控证明它有牙（把那句写回去 ⇒ 门红）。

**⑧ 判据**：selfcheck **393/0**（**+2**：时长归一四态 / 顶替规则四态
+「两个状态型归同一类」）、接线门 **503 项**（**+15**）、ci.sh **12/12**、
契约门 **120/0**（不变）、快照**零变化**（设置窗不在快照范围）。
**⑨ 负控 6/6 真红**（累计 **47/47**）：时长退回硬编码 ⇒ 门红／
顶替判定绕开判定层 ⇒ 门红／时长归一失效 ⇒ selfcheck 红／
「停滞」被单独归类 ⇒ selfcheck 红／过时说法复活 ⇒ 门红（证明 `arch_forbid_raw` 有牙）／
选择器被摘掉 ⇒ 门红。
⚠ **计数口径**：只数**变异项**（负控脚本末尾另有「工作区已还原」的自检，不算负控项）。

**⑩ 元教训**：**「说法与实现相反」比「说法缺失」更危险** ——
缺失会引人去查代码；相反的说法会让人**照着它改代码**。
⇒ 凡是「注释/文档描述行为」的场合，**要有一条门让实现来对质**，
而不是靠人记得回头改注释。

**⑪ 遗留**：`image-path` 仍是**单套图标名**（PLAN 写「亮/暗两套」）
⇒ ⚠ deepin 通知服务器对 `image-path` 的**路径 vs 图标名**语义未查证
⇒ 需真机/容器才能定，本批**不猜**（记在 M1-4 剩余项里）。

### E.1s 判据只许增不许减 + **拆掉 3800 行大函数**（批 AJ —— M4a 的第一步）

**① 起因（两件事都是「承诺没有牙」）**：
- ⚠ **「判据不许被删」这句话，从来没有门**：`ci.sh` 第 1 门只断言
  「`0 failed` 且 **`≥58 passed`**」—— 58 是 2024 年的老数字
  ⇒ **删掉 300 条判据照样全绿**。
  ⇒ 判据是「契约的牙齿」，删一条就少一颗牙，而门**看不见**。
- ⚠ `src/app/SelfCheck.cpp` 是**一个 3800 多行的函数**（M4a 记的遗留债）：
  改一条判据要跟三千多行代码挤在一个文件里 ⇒ 冲突面大、review 难。

**② 补门「判据数不许变少」**（`scripts/ci.sh`）：
- 基线 `SC_MIN`（批 AJ 时 393，**批 BB 起 395**）**写死在脚本里**（与既有「≥58」同一做法）
  ⇒ 改基线 = 改脚本 = 评审看得见。
- ⚠ **刻意不用单独的基线文件**：那个文件会被顺手改小 ⇒ 门跟着一起松
  ⇒ 等于没门（这正是批 AF 的教训：**门形同虚设比没门更坏**）。
- ⚠⚠⚠ **原记「加判据时同步把 `SC_MIN` 加一；忘了加只是门偏严，不会偏松 ⇒ 安全方向」
  —— 这句把方向写反了**（批 BB 实测推翻，⚠ **同一句错在 ci.sh 注释与 PLAN §10 里也各有一份**）：
  - 当时门是 `-lt`（**不少于**基线就算过）⇒ **余量 = 基线与实际判据数之差**，
    而那个差**没人盯** ⇒ 忘了加 `SC_MIN` ⇒ 基线**落后**于实际 ⇒ **门偏松** ⇒ **正是不安全的那一侧**。
  - ⚠ **实测后果**：此后加了 2 条判据（393 → 395）而基线没加 ⇒ 余量变 2
    ⇒ **删 2 条判据门照样绿** ⇒ 「判据不许被删 ⇒ 红」这个承诺**当时是假的**。
  - ⇒ 批 BB 已把判定改成**完全相等**（`-ne`）⇒ 余量恒为 0；本条**留作历史记录**。
- ⚠ 口径 = **判据条数**（`passed` 数）⇒ 抓不到「删一条又加一条」那种换名操作（少见）。

**③ 拆分（基础设施先行）**：新增 `src/app/SelfCheckInternal.h`
—— ⚠ 关键点：**「记一条判据」必须只有一份实现**
（`check()` + `g_pass`/`g_fail` + `J`/`JO`，C++17 的 inline 变量/函数）。
⚠ 各分片各写一份 `check()` ⇒ 计数各数各的 ⇒ 汇总出来是错的
⇒ 而且是「**同名两处互相顶替**」的老坑（台账通用教训）。
⇒ 分片里写 `using SelfCheckInternal::check;`
⇒ 现有的裸调用 `check(log, "…", ok)` **一个字都不用改**。
- `SelfCheck.cpp` **3832 → 2547 行**；新分片：
  `SelfCheckDocs.cpp`（572 行：固定文档页 + 四语言 + 语法高亮）、
  `SelfCheckEngine.cpp`（903 行：图谱三件套 + 引擎获取 + 通知 + 引擎钩子）。
- ⚠ **依赖检查靠编译器**：搬段时若缺 include / 缺变量，编译器立刻报
  ⇒ 不用通读三千行去核对依赖。

**④ 判据**：selfcheck **393/0**（**一条不少、一条不多** ⇒ 拆分无损）、
ci.sh **12/12**、接线门 **517 项**（**+14**）、契约门 **120/0**、快照**零变化**。
**⑤ 负控 3/3 真红**（累计 **50/50**）：删掉一条判据 ⇒ **ci.sh 第 1 门红**（`392 < 393`）／
删掉一条判据 ⇒ **接线门的覆盖门项也红**／分片自己写一份 `check()` ⇒ 接线门红。

**⑤b ⚠⚠ 拆分顺带照出三笔「门与文件绑死」的旧账**（都是拆完**当场变红**的）：
1. ⚠ **44 条接线门项**盯的是「判据在 **`SelfCheck.cpp` 这个文件**里」，
   而它们的**意图**是「**判据覆盖了某个判定层**」⇒ 判据搬到分片后**集体变红**
   ⇒ 逼着人「把代码搬回去」而不是「把门改对」。
   ⇒ 新增 `arch_need_any`（任一 `SelfCheck*.cpp` 命中即绿）；
   ⚠ **强度不变**：判据集合没变（`SC_MIN` 盯着条数）⇒ 真删掉一条判据，这里照样红。
   ⚠⚠⚠ **但这句话在批 BB 查出来当时是假的**：`SC_MIN` 的判定是「**不少于**」，
     而基线落后实际 **2 条** ⇒ **删 1 条判据这里不会红** ⇒ 批 BB 已把判定改成**完全相等**。
2. ⚠ **D2 散值门的豁免清单绑死了 `SelfCheck.cpp`**
   ⇒ 判据夹具里的**期望色值**（`QColor(0x1E,0x6F,0xEB)` 之类）搬到分片后 **D2 门红**
   ⇒ 按「豁免必须**逐条登记**」的规矩登记两处 `keep`（路径写错 ⇒ 门红 ⇒ 豁免不会静默失效）。
3. ⚠ **我自己的新门项正则太窄**：`^\s*void check\(` **抓不到** `static void check(`
   ⇒ **负控没抓到**（负控红不了 ⇒ 那道门等于没门）⇒ 放宽为 `void check\(`。
   ⚠ 这是本批的第三次「负控照出真问题」（前两次：门项绑死文件、D2 豁免绑死文件）。

**⑤c 元教训 3：门要盯「意图」，不是盯「位置」** ——
「判据覆盖了 X」是意图，「X 在哪个文件」是位置；
把位置当门 ⇒ 结构一变动门就集体变红 ⇒ 门从「守护」变成「阻拦」。
⇒ 凡是「覆盖类」门项，一律写成「**任一相关文件**里有」。

**⑥ 元教训 1：承诺没有门 = 承诺不存在** ——
「判据不许被删」写在文档里很多年，门却只查「≥58」。
⇒ 凡是**承诺**（不许删、不许退化、不许变慢），都要有一条**能红**的门顶住；
否则它只是**让人放心**的句子。

**⑦ 元教训 2：拆分的验收标准是「条数不变」，不是「编译通过」** ——
编译通过只能证明「没搬坏语法」，搬漏一条判据照样编译通过。
⇒ 拆分**必须**配一条「条数不许少」的门，两者一起才是完整验收。

**⑧ 遗留（如实记，不假装做完）**：
- `SelfCheck.cpp` 仍有 **2547 行**（段 15「图谱/架构图/Canvas2D/热力图/补丁体检」
  约 1100 行仍在里面）⇒ **M4a 未完成**，下一步按同一套路再搬；
- `AppModel.cpp` 仍 1948 行 ⇒ 同样待拆。

**⑨ ⚠⚠ 元教训 4：负控的「累计数」是跨批的二手数，最易失真** ——
本批写文档时，把**批 AI** 的累计写成了 `41/41`（**照抄了批 AH 的数，忘了加自己那 6 项**）
⇒ 订正为 `47/47`；批 AJ = `50/50`（27 → AF +6 = 33 → AG +2 = 35 → AH +6 = 41
→ AI +6 = 47 → AJ +3 = 50）。
⚠ 讽刺点：这已是**本轮第二次**因累计数翻车（第一次是批 AH 把「工作区已还原」的自检
算进了负控项）⇒ 两次都是**照抄上一批**出的错。
⇒ **累计数每批都要重新加一遍**，别复制粘贴；单批数（`6/6`、`3/3`）才是可靠的那个。

### E.1t M4a 第二步：图谱/热力图/补丁体检再拆一片（批 AK —— **主文件降到 1451 行**）

**① 起因**：批 AJ 把 `SelfCheck.cpp` 从 3832 行降到 2547 行，
但**最大的一块还在里面** —— 段 15「图谱/架构图 + 符号索引热力图 + 补丁体检」约 **1100 行**。

**② 改动**：
- 段 15 整体搬进新分片 `src/app/SelfCheckGraph.cpp`（**1196 行**）
  ⇒ `SelfCheck.cpp` **2547 → 1451 行**（与 `AppModel.cpp` 1948 行同一量级 ⇒ **单文件过大**这个债基本还清）。
- ⚠ 沿用批 AJ 的基础设施：`SelfCheckInternal.h` 共享底座
  （`check()` + 计数 + `J`/`JO` 各只有一份实现）⇒ 新分片里
  `using SelfCheckInternal::check;` ⇒ 裸调用一个字没改；
- 依赖检查仍**靠编译器**（缺 include/缺变量编译器立刻报）⇒ 没通读那一千行去核对。

**③ ⚠ 顺带照出并修掉：「判据夹具的 D2 豁免」也绑死了文件** ——
判据夹具里写着**期望色值**（`HeatLayout::heatColor(79) == QColor(255,200,87)` 之类），
搬到分片后 **D2 散值门红** ⇒ 按「豁免必须**逐条登记**」的规矩登记 `keep`。
⚠ 这是批 AJ 同一笔账的**第二次**复发 ⇒ 说明「绑死文件」是**一类问题**，不是一处笔误。

**④ 判据**：selfcheck **393/0**（**一条不少、一条不多** ⇒ 拆分无损）、
接线门 **523 项**（**+6**：图谱分片声明/实现/主片调用/构建登记/D2 豁免登记 + 分片禁自写 `check`）、
ci.sh **12/12**、契约门 **120/0**、快照**零变化**。
**⑤ 负控 3/3 真红**（累计 **53/53**）：**在图谱分片里**删一条判据 ⇒ ci.sh 红／
图谱分片自己写 `check()` ⇒ 接线门红／**主片忘了调用图谱分片** ⇒ 接线门红。
⚠ N3 这条是新增的：代码搬走了**就忘接** ⇒ 判据凭空消失 ⇒ 必须有门顶住。

**⑤b ⚠ 负控脚本自己踩的坑：变异失败必须**立刻退出** ——
N1 第一次跑「没抓到」，原因不是门坏了，而是**变异脚本没找到目标判据**
（目标判据的 `check(log,` 在上一行、`heatColor` 在续行 ⇒ 按「同一行含 heatColor」找不到）
⇒ 脚本 `raise SystemExit` 了，但 shell 没检查退出码 ⇒ 继续跑 ci.sh（当然绿）
⇒ **负控「假跑」**（正是批 AF 记的那条教训的变体：那次是编译失败被吞，这次是**变异失败**被吞）。
⇒ 已加 `python3 … || { echo "变异失败 ⇒ 负控无效"; exit 2; }`（三处变异全加）。
⚠ **凡是「让判据红」的步骤，失败必须让整个负控失败** —— 否则「负控没抓到」会被误读成「门有洞」。

**⑥ 元教训 1：「绑死文件」是一类问题，不是一处笔误** ——
本轮连续两次（批 AJ 的接线门 44 条 + D2 豁免；批 AK 的 D2 豁免）都是
「门/豁免绑死某个文件名」⇒ 结构一变动就集体变红。
⇒ 纪律：**凡是「覆盖类」的承诺与豁免，一律写成「任一相关文件」**；
   真正需要绑死单个文件的地方（比如「这个文件不许自己写 check」）才写死。

**⑦ 元教训 2：拆分的最后一步要单独有门** ——
「搬走就忘接」（主片不调用分片）比「搬漏一行」更隐蔽：
它编译通过、selfcheck 少几条、门若没盯就会**静悄悄少掉一批判据**
⇒ 接线门专门加一条「主片调用了 X 分片」。

**⑧ 遗留（如实记）**：`AppModel.cpp` 仍 **1948 行** ⇒ **M4a 未完**；
但它比 `SelfCheck.cpp` **好拆**（它是**类**的实现 ⇒ 成员函数天然可分文件定义，
不像那个 3800 行的大函数要拆成多个自由函数）⇒ 下一批按同一套路拆。

### E.1u M4a 收官：拆 `AppModel.cpp` ⇒ **最大文件从 3832 降到 1451**（批 AL）

**① 起因**：M4a 记的两笔大文件债，`SelfCheck.cpp` 已在批 AJ/AK 拆完，
只剩 `AppModel.cpp` **1948 行**（全仓第二）。

**② 改动**：`AppModel.cpp` **1948 → 1052 行**，拆成三片：
- `AppModel.cpp`（主片：生命周期/刷新/状态/仪表盘/里程碑/项目与文档/引擎配置）
- `AppModelGraph.cpp`（**161 行**：概览/符号详情/影响面/patch 技能）
- `AppModelUpdate.cpp`（**805 行**：更新/批量/git 操作/扫描/里程碑写入）
- 跨片共用的文件内辅助函数上 `src/app/AppModelInternal.h`（**inline ⇒ 只有一份实现**）。

**③ ⚠ 与 SelfCheck 拆分的关键差别：这次**零风险** ——
同一类的成员函数**天然可以分文件定义**（不像那个 3800 行大函数要拆成多个自由函数
+ 共享底座）。⚠ 前提只有一个：**分片之间不共享文件内静态**。

**④ ⚠⚠ 踩到的三个坑（记在这里，免得下批再踩）**：
1. ⚠ **匿名 namespace 的闭合行被漏掉** ⇒ 后面所有代码落进匿名 namespace
   ⇒ 报「definition … is not in namespace enclosing 'AppModel'」（一堆 `-fpermissive`）。
   ⇒ 搬段时**必须连带 `} // namespace` 一起处理**。
2. ⚠ **4 个文件内辅助函数两边都在用**（`kQuiet` / AI 配置快照 / `sortProjects`）
   ⇒ 只能上内部头；⚠ 但 `milestoneActionLabel` **只有更新分片用**
   ⇒ **留在分片里、不进共享头**（**能不放共享头就不放** —— 共享面越小越好）。
3. ⚠ **辅助函数的「搬走范围」要按函数整体算**：
   第一次只搬了函数签名行、漏了函数体 ⇒ 编译报「未声明」。

**⑤ ⚠⚠ 「绑死文件」第三笔账（同一类问题的第三次复发）**：
**38 条接线门项**盯的是「调用形态在 `AppModel.cpp` 里」⇒ 拆完**集体变红**。
⇒ 把 `arch_need_any` 泛化出**可选的文件通配参数**（默认 `SelfCheck*.cpp`），
38 条改成 `arch_need_any '<正则>' '<说明>' 'src/app/AppModel*.cpp'`。
⚠ **强度不变**：any 化只是把「在哪个文件」放宽，「**这个调用形态还在不在**」没放宽
⇒ 负控 N2 证明（把 `callText` 换成 `callJson` ⇒ 门照样红）。

**⑥ 判据**：selfcheck **393/0**、接线门 **523 项**（**数量不变**：38 条是改写不是新增）、
ci.sh **12/12**、契约门 **120/0**、快照**零变化**。
**⑦ 负控 3/3 真红**（累计 **56/56**）：删掉分片里的成员函数定义 ⇒ **链接红**
（漏搬必被抓）／主片的契约调用形态走错 ⇒ **接线门红**（any 化后强度不变）／
分片里重复定义主片已有成员函数 ⇒ **链接红**（同名两处互相顶替）。


### E.1v M3c「响应式」：AgentDialog 可缩放 + 定宽截断改省略号（批 AM —— **照出 PLAN 描述失真**）

**① 起因**：M3c 剩「响应式」这一项 ⇒ 动手前先实测核对 PLAN §3c 的原文
（照批 AE 纪律）⇒ **三处对不上**。

**② ⚠ PLAN §3c 的「KPI 网格按窗宽 1/2/4 列（`resizeEvent` 改写列数）」是失真的**：
实测 deepin 侧**根本没有 `resizeEvent`**（4 张卡写死在 (0,0)(0,1)(1,0)(1,1)，`DashboardPage.cpp:199-210`），
且 mac 侧是**固定 4 列**（`macos/Sources/deepDolphin/DetailViews.swift:902-903` `LazyVGrid(count: 4)`）
⇒ 「1/2/4」是 deepin 侧的**无对位**设计 ⇒ **不做**，改为记录实测结论（已写回 PLAN）。
⚠ 顺带照出：`DashboardPage` 的注释写着「宽 <980 由 resizeEvent 折 2 列」——
**与实现相反**（与批 AI 的 `Notifier.h` 同类：注释比实现还自信）⇒ 已订正 + 加门盯住。

**③ ⚠ `AgentDialog` 固定尺寸 → 可缩放**：
它是全仓**最后一个**固定尺寸的对话框（其余 8 个都用 `setMinimumSize`），
而 AI 助手的回复一长就被裁掉、也调不大 ⇒ 照**同仓先例**
`AiResultDialog.cpp:15`（「固定尺寸曾让长报告读不完且关不掉——必须可缩放」）改：
`setFixedSize(720,620)` → `resize(720,620)` + `setMinimumSize(720,620)`（可放大、不可缩到读不了）。

**④ ⚠⚠ PLAN §3c 那句话的另一半「定宽截断改 `elidedText`」是**真缺口** ——
实测全仓 `elidedText` **零命中** ⇒ 完全没做。
侧栏项目名原来只 `setMaximumWidth(120)` ⇒ QLabel 默认**直接切掉后半截**
（半个字、无提示）⇒ 长项目名看不出是哪个 ⇒ 改为 `elidedText` 省略 + **完整名进 tooltip**。
⚠ **零视觉变化**：现有快照基线**零变化**（夹具里的项目名短，省略号不触发）
⇒ ⚠ 也说明**基线覆盖不到「长项目名」这一档**（记作遗留）。

**⑤ 判据**：selfcheck **393/0**、接线门 **529 项**（**+6**：对话框不许固定尺寸 /
最小尺寸恰好一处 / KPI 入格恰好 4 处 / 过时说法不许复活 / 侧栏用省略号 / 完整名进 tooltip）、
ci.sh **12/12**、契约门 **120/0**、快照**零变化**。
**⑥ 负控 4/4 真红**（累计 **60/60**）：对话框改回固定尺寸 ⇒ 门红／
注释里写回那句过时话 ⇒ 门红（`arch_forbid_raw` 不剥注释 ⇒ 有牙）／
KPI 网格少入一张卡 ⇒ 门红（`arch_need_count` 恰好 4 处）／
侧栏改回硬截断 ⇒ 门红。

**⑦ 元教训 1：PLAN 里的「行号 + 做法」是最容易失效的一类描述** ——
本批核对时发现 `ProjectProgressCard.cpp` **文件已不存在**（PLAN 引的 4 处里有一处是幽灵文件）
⇒ 照 PLAN 逐条做之前，**先 `ls` 那个文件还在不在**。

**⑧ 元教训 2：定宽截断在 Qt 里默认是「硬裁」** ——
`setMaximumWidth` 只限制宽度，QLabel **不会**自动加省略号 ⇒
文字被直接切掉后半截（半个字）⇒ 凡是定宽显示长文本，都得**显式** `elidedText`。

**⑨ 遗留**：PLAN §3c 点名的另几处定宽截断（`SidebarNav.cpp:42/236`、
`DashboardPage.cpp:396`、`TrayPopupWindow.cpp:184`）**行号已漂移**，
本批只改了能定位到的**侧栏项目名**一处 ⇒ 其余待逐处定位后再改（如实记，不假装做完）。

**⑧ 🎉 M4a 达成**：全仓最大文件从 **3832 行**降到 **1451 行**
（`SelfCheck.cpp` **1451** / `SelfCheckGraph.cpp` 1170 / `AppModel.cpp` 1052）
⇒ 占全仓从 **9.8%** 降到 **3.7%** ⇒「单文件占全仓近 10%」这个债**还清**。
⚠ **这里踩了个数**：本批写文档时按**主片** 1052 行写了「最大文件降到 1052」，
而**分片** `SelfCheckGraph.cpp` 其实是 **1170 行**（比主片还大）⇒ 写完才 `wc` 出来。
⇒ **教训：写「最大文件」这种数之前先 `wc` 全仓** ——
   拆完之后「最大文件」是**分片的最大值**，不是主片的大小（拆了也白拆的那种假达成）。
⚠ 后续若再长大，按本批与批 AJ/AK 的同一套路拆即可（分片 + 内部头 + 门项 any 化）。

---

### E.1w 快照基线「逐字节可重现」是**假的** —— 照出三个叠在一起的洞（批 AN）

**① 起因**：批 AH 修好了 setupguide 死基线，但留了个尾巴——
「一次 `ci.sh` 在快照段报『✗ 重拍失败：dark-setupguide』⇒ 偶发」。
本批按「拿不准就查」的规约**一路查到底**，结果照出的东西比那个偶发失败大得多。

**② ⚠⚠ 洞一：同一份代码会拍出**多种字节**（不是「偶发失败」，是「结果不确定」）**
- 压力实测：同机**并发混主题**跑 120 次 ⇒ 拍出 **4 种**不同字节；
  纯主题并发 60 次 ⇒ 1 种；**串行** 200 次 ⇒ 也有 ≈0.5% 出变体（1/200）。
- ⇒ 基线会**悄悄漂** ⇒ 「基线必须逐字节可重现」这句承诺**当时是假的**。

**③ ⚠⚠ 根因（逐层实测，不是猜的）**：
1. 两张变体图**逐像素** diff ⇒ 差异 **100% 集中在 y[50..69]**（带外 **0 行**不同）；
2. 那 20px 正是 DTK 的**标题栏下沿阴影带**——`DShadowLine::paintEvent` 读内嵌 SVG
   `titlebar_shadow_20px.svg`（渐变 `stop-opacity .1 → 0`）；
   实测**关掉阴影带后该区域变成纯背景色** ⇒ 坐实；
3. SVG 渐变带在不同负载下**铺开的高度不同**（整条渐变被压短/拉长），
   ⇒ **不是「还没画完」，是渲染结果本身不确定** ⇒ **等多久都没用**。
⚠ 排除过的假设（都记下来，免得后人重走）：D-Bus 共享配置（`org.deepin.dtk.preference`
确实存在，但 `dbus-monitor` 实测**没有任何** dtk.preference 调用）、
dconf 写入（`dconf dump /org/deepin/dtk/` 为空、`user` 文件 mtime 长期不变）、
跨进程主题串扰（串行混主题也出变体 ⇒ 不是共享状态）。

**④ ⚠⚠ 洞二：ci.sh 的「重拍比字节」门是**自己跟自己比****
第 2 步把新图**直接拍进 `docs/snapshots/*.png`（**覆盖基线**），
后面的门再拿「刚覆盖完的基线」跟新拍的一张比 ⇒ **恒绿**。
⇒ 「基线漂了」这道门**结构上就抓不到**（比的是本次产物 vs 本次产物）。
⚠ 连带后果：那句「CI 通过后请 `git diff docs/snapshots` 人工确认」也是空的
（基线刚被覆盖 ⇒ diff 永远为空）。

**⑤ ⚠ 洞三：拍后断言 ⇒ 偶发失败报成假红**
setupguide 段的「拍到的确实是首屏」断言写在**拍完之后** ⇒
万一那一刻还没切到首屏，报的是「重拍失败」（**红**），
而**本可以**继续等它切过去 ⇒ 判据前移到**拍前**（`settle.elapsed() >= 300 && showingSetupGuide()`），
拍后断言**保留**作最后一道防空门。

**⑥ 修法（三处都动了）**：
- `src/main.cpp`：快照路径调 `panel.setTitlebarShadowEnabled(false)`
  （**公开** API：`dmainwindow.h:108` public 段 ⇒ DTK 升级不会断）；
  为什么可以关：阴影带是**标题栏的装饰**，不承载任何信息，
  而基线的价值在「界面改了它会红」——装饰带的像素抖动只会制造**假红**。
- `scripts/ci.sh`：基线改为从 **git 里取**（`git show HEAD:deepin/docs/snapshots/...`），
  本次产物另存临时目录，两者比 ⇒ **视觉改动必须有人看过并提交**（不一致 ⇒ 退出码非 0）。
- `scripts/ci.sh`：加「**跨运行复拍**」段（新进程再拍一轮比基线）⇒ 抓跨进程漂移。

**⑦ ⚠ 快照基线重拍（8 张）**：差异**100% 集中在 y[50..69]** 那条阴影带，
带外**逐像素相同** ⇒ 画面内容零变化，只是去掉了那条会漂的装饰带。
色卡（`*-colors.png`）**零变化**（它不画标题栏）。

**⑧ 判据**：selfcheck **393/0**、接线门 **534 项**（**+5**：
快照必须显式关阴影带 / 拍前就要求「已停在首屏」/ CI 有「跨运行复拍」段 /
快照命令不许用「| tail -1」/ 快照失败时 stderr 要落盘）、
ci.sh **12/12**、契约门 **120/0**。
⚠ `cmp -s` 的**精确计数门**从 2 改成 **4**（批 AG 纪律：门盯的东西变了，强度要跟着变）。

**⑨ 负控 5/5 真红**（累计 **65/65**）：
删掉「关阴影」⇒ 拍出 4 种字节（缺陷回来）／
删掉「关阴影」⇒ 接线门红／
把拍前条件退回「只等 300ms」⇒ 接线门红／
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

### E.1x PLAN §3c 点名的定宽截断：**逐处实测**后 4 处行为各不相同（批 AO —— 顺带修好一个旧布局缺陷）

**① 起因**：批 AM 把 PLAN §3c 点名的 4 处定宽截断留给后续（且 PLAN 里的行号已漂移）。
本批按「拿不准就查」的规约**逐处实测核对** ⇒ 结论**不是「4 处都改」**——
**4 处的行为各不相同**，一刀切会改错：

| 处 | 原来的做法 | 实测行为 | 本批 |
|---|---|---|---|
| `src/ui/pages/ProjectProgressCard.cpp` 项目名 | 手工掐中间（**按字符数 24**）+ `setMaximumWidth(220)`（**按像素**）**同时**存在 | **两条截断互相打架** ⇒ 仍硬裁（半个字） | **改**（只留按像素的 `elidedText(ElideMiddle, 220)`） |
| `src/ui/pages/DashboardPage.cpp` 活跃项目 headline | `setMaximumWidth(300)` | **真硬裁**（内容来自引擎，长度不受控） | **改**（省略号 + tooltip） |
| `src/tray/TrayPopupWindow.cpp` 项目名 | `setFixedWidth(120)` | **真硬裁**（弹窗宽固定、项目名长度不受控） | **改**（省略号 + tooltip） |
| `src/ui/SidebarNav.cpp` **固定视图行**（仪表盘/看板/里程碑） | `setMaximumWidth(120)` | 文本短、**永不溢出** ⇒ 是兜底上限 | **不改**，但**原注释是错的**（已订正） |

**② ⚠⚠ 「两条截断打架」的实测（13px monospace DemiBold）**：
手工掐完的 **24 个中文**字仍 **268px > 220px** ⇒ `setMaximumWidth` 照样**硬裁** ⇒
用户看到的是**半个字**（不是省略号）；纯 ASCII 时 164px 不超宽 ⇒
**这个缺陷只在中文项目名下出现**（中文项目名很常见）。
⇒ 删掉手工截断，只留**一条按像素**的 `elidedText(ElideMiddle, …)`：
中段省略的意图保留（`/path/to/project` 的尾部目录名比掐尾部更有用），
且按**像素**算 ⇒ 任何文字（中文/ASCII/emoji）都不会溢出成半个字；
完整名进 tooltip（原来手工截断后**看不到全名**）。

**③ ⚠⚠⚠ 顺带照出并修好一个旧布局缺陷（本批最大发现）**：
删掉 `name->setMaximumWidth(220)` 后**仪表盘快照变了** ⇒ 逐像素 diff 定位到
差异 100% 落在**两张项目卡的行 1**（行段 y[521..533] 与 y[693..705]）⇒ 查下去发现：
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
`WorkBar` 的 **DComboBox**（控件**自带**按宽度省略，viewDelegate 走 `QFontMetrics::elidedText`）／
`GeneralPane` 与 `MilestonesPage` 的 **DLineEdit**（超宽是**横向滚动**，不是硬裁）
⇒ 加省略号反而是倒退 ⇒ 「定宽截断改 `elidedText`」只针对 **QLabel**。

**⑤ ⚠ 订正一处过时说法**（批 AI 教训：说法与实现相反比说法缺失更危险）：
侧栏固定视图行的原注释写着「60 字项目名在最窄窗口截断**带省略号为预期行为**」——
① 那行**不是项目名**（项目名在 `rebuildProjectRows`，批 AM 已改）② `setMaximumWidth`
**不会**加省略号（Qt 默认是硬裁）⇒ 已按**实际行为**重写，并加 `forbid_raw` 门不许复活。

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
⇒ 受害的是**别的控件**（圆点与状态词脱开 86px），而**改的人以为自己只改了名字标签**。
⇒ 「限宽」和「拉伸」不许同时出现在同一个标签上；余量要靠**显式的 stretch** 留白。

**⑪ 元教训 3：⚠ 改一处 UI 却看到**别处**的快照变了** —— 先别急着怀疑新代码 ——
逐像素 diff 定位到**行段**（本例只有 2 个行段，落在两张同类卡的同一行）⇒
立刻指向「同一个组件的同一行布局」，而不是「快照基线漂了」。
⚠ 本批顺手发现：仓里自带的 PNG 裁剪脚本**写 PNG 的长度字段把 chunk type 也算进去了**
⇒ 产出根本不是合法 PNG（`file` 报 `data`）⇒ 改用 PIL 重写裁剪器后才能肉眼比对。
⇒ **诊断工具本身也要验**（它给出的「差异包围盒」是对的，但「放大图」是坏的）。

### E.1y M3c HiDPI：自绘位图按 dpr 放大（批 AP —— **PLAN 的名单已经过时**）

**① 起因**：PLAN §3c 写着「9 处 1x 自绘 ⇒ 改 `platform::dpiPixmap()`」。
但那份名单**写在 `IconResolver` 存在之前**（`IconLoader.cpp` 早已被批 AI 当死代码删掉）
⇒ 照 PLAN 做会**漏**（照批 AM 教训：PLAN 里的「行号 + 做法」最易失效）。
⇒ 本批**实测扫全**（grep 全部 `QPixmap` 构造 + 全部 `QPainter` 用法），
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
dpr 感知的是 **11 层** ⇒ 差别**可量化**，不是「看着有点糊」。

**③ 修法**：新增 `src/platform/DpiPixmap.{h,cpp}` ——
`platform::dpiPixmap(logicalSize)` 按 `logicalSize × dpr` 开缓冲区并
`setDevicePixelRatio(dpr)` ⇒ QPainter 在其上**仍用逻辑坐标**画
（Qt 自动按 dpr 缩放坐标系）⇒ 图形**尺寸不变、像素密度对了**。
⚠ 与 `platform::icon()` 的**分工**：`icon()` 走**图标主题**（那边自己按 dpr 取图，
见 `IconResolver.cpp` 的 `fromDci`）；本助手只管**我们自己用 QPainter 画**的那些。

**④ ⚠ 判据分两层（第二层差点是空门）**：
- **结构事实**（探针 + CI 门）：`dpiPixmap=` 那行必须满足
  **缓冲区 = logical × dpr** 且 pixmap 的 `devicePixelRatio` **== 应用 dpr**
  ⇒ 这是「不发虚」的**充要**结构条件。
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
**dpr=1（100%）下 `dpiPixmap` 与原写法逐字节等价 ⇒ 快照零变化**（已复核：8 张逐字节一致）。
⚠ `IconResolver` 的 qrc 染色 SVG 那条路径本机**编不到**
（无 Qt6Svg 开发头 ⇒ `DD_HAVE_QTSVG` 未开）⇒ 它的正确性靠**评审**，不靠本地构建。

**⑦ 判据**：selfcheck **393/0**、接线门 **568 项**、ci.sh **12/12**、契约门 **120/0**、
ci-d2 **0/0**；快照**零变化**。

**⑧ 负控 5/5 真红**（累计 **75/75**）——⚠ **头一次跑只有 3/5**，两条没红，
查出的是**真问题**（见⑫）：
调用点退回裸 `QPixmap` ⇒ 接线门红／
助手不按 dpr 放大缓冲区 ⇒ **运行时门**红（缓冲区 ≠ logical×dpr）／
助手不设 `devicePixelRatio` ⇒ **运行时门**红／
探针**代码里**的格式串改掉、不报 dpi 事实 ⇒ 接线门红／
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
（「src/ 下不许有色值字面量」）⇒ 改走 `DS::semColor(DS::SemColor::accent)`。
⇒ 纪律**不因「只是探针」而破**；顺带证明 D2 门对**新增代码**同样有牙。

**⑫ 元教训 4：⚠⚠ 门盯的**字面串**也可能出现在注释与提示语里** ——
本批负控**头一次只有 3/5**：两道门盯的是 `QT_SCALE_FACTOR=2` 与 `dpiEdgeLevels=`，
而这两个串**在注释与错误提示语里也出现**（`echo "✗ QT_SCALE_FACTOR=2 没生效…"`）
⇒ 把真正的那行改掉，**门照样绿** ⇒ 门被**措辞**满足了。
⇒ 收紧成盯**代码构造**：
`arch_need 'dpi_b_out=.*QT_SCALE_FACTOR=2'`（盯那一跑的**命令**）、
`arch_need 'dpiEdgeLevels=legacy:%d'`（盯**格式串**）、
`arch_need 'devicePixelRatio=%g'`（盯格式串）⇒ 再跑负控 **5/5 真红**。
⇒ 与批 AH「文件名对不等于内容对」、批 AI「说法与实现相反更危险」同源：
**门必须先确认「它盯的那个串只被代码满足」**。
⚠ 另一条同源的坑：变异脚本若只替换**文件里第一次出现**的字面串，
   很可能改到**注释**上 ⇒ 等于没改 ⇒ 负控会给出「门没红」的**假结论**
   ⇒ 变异脚本必须盯**代码构造**（本批 `nodpi` 改成替换 fprintf 的格式串）。

### E.1z mac 侧引擎下载链**从来没成功过** —— 三个叠在一起的错（批 AQ）

**① 起因**：mac 侧 `build.sh` 的「本地没有引擎就从 GitHub Releases 下载」那条路径
**从来没成功过** ⇒ 因为**没人见过它成功的样子**。
批 AQ 用 **GitHub API + 真包**把它照了出来 ⇒ 三个错**叠在一起**：

| # | 原来的做法 | 实测事实 | 后果 |
|---|---|---|---|
| ① | URL 写死 `releases/latest/download/moongit-darwin-arm64.tar.gz` | release 资产名**带版本号**（v0.2.1 叫 `moongit-v0.2.1-darwin-arm64.tar.gz`），而 `latest/download` 要求**资产名精确匹配** | **必然 404** |
| ② | 找「包根的 `moongit-cli`」 | 实测 tar 清单：包根是**启动器** `moongit`（POSIX shell 脚本），真二进制在 `bin/moongit-cli` | 就算 URL 修好也**找不到** |
| ③ | 只复制那一个文件 | 仓颉运行库在 `runtime/lib/`，被**丢掉了** | 装下来的引擎**根本起不来** |

⚠ 这三个错是**同一个症状**（下载不到）下的**三个独立原因**
⇒ 只修 URL 仍然拿不到可用的引擎。
⇒ 根因是**同一条**：「**发布包被当成了单个裸二进制**」——
启动器按**自身所在目录**（`ROOT=$(dirname "$0")`）去找 `bin/` 与 `runtime/`，
且**不解析软链** ⇒ 三样必须**一起**落盘。
（deepin 侧早就踩过同一族坑并写在 `deepin/src/logic/EngineDownload.h` 里，
连「原实现按『包根只有一个 moongit-cli』设计 —— 那是**虚构的布局**」这句都在。）

**② 修法**：
- 新增 `macos/scripts/fetch-engine.sh`（**不依赖 macOS**，只用 curl/tar/grep）：
  查 API 拿最新 release 的资产列表 → 按**后缀**挑（架构差异由资产名表达，
  **不写死版本号**）→ 整包下载 → 整包解包 →
  验「启动器 / `bin/moongit-cli` / `runtime/lib` **非空**」三样齐全 → **整包**落盘。
- `macos/build.sh`：改调它；把下载目录（`~/.local/share/deepDolphin/engine`）
  加进候选清单；**内嵌引擎分两种形状**：
  A. **发布包**（启动器 + `bin/` + `runtime/`）—— 下载来的就是它；
  B. **裸二进制**（仓内 cjpm 产物 / 手工装的 CLI）。
  ⚠ **内嵌进 bundle 的必须是 Mach-O**（下面的 rpath 重写与补签都只对 Mach-O 有意义，
  `otool -l` 对 shell 脚本直接失败 ⇒ 会误报「rpath 被清空了却没写回来」）
  ⇒ 形状 A 内嵌**真二进制** `bin/moongit-cli`，并把它自带的运行库一起放进
  `Contents/Frameworks/`（rpath 里已有 `@executable_path/../Frameworks`）。
  ⚠ 形状 A **不用** SDK 那份运行库 —— 两个版本的 `libcangjie-runtime.dylib`
  混在同一个目录里，后拷的盖掉先拷的 ⇒ 引擎与运行库版本对不上 ⇒ 起来就崩。

**③ 判据**：
- **行为判据**（新增 `macos/scripts/engine-fetch-check.sh`）：**不依赖 macOS**
  ⇒ **Linux 上就能跑**（资产选择与包布局都是平台无关的）。
  查 API → 验 URL 不是写死的 `latest/download` → 验 URL **带版本号** →
  验资产可达（HEAD 200/302）→ `--full` 再**真下载 + 解包 + 验三样齐全 +
  跑一次启动器**（实测输出 `moonGit Engine 0.2.1 (Cangjie 1.0.5 LTS)`）。
- **静态门 +10**（进 deepin 的 CI，跨目录盯 `macos/`，无网络依赖）：
  build.sh 不许再写死那个 URL、必须走 `fetch-engine.sh`；`fetch-engine.sh`
  不许写死 `latest/download`、必须从 API 挑资产、必须认得
  `bin/moongit-cli` 与 `runtime/lib` 的真实位置；判据脚本必须验三样齐全；
  build.sh 内嵌时必须**把运行库一起拷进 Frameworks**（盯**干活的那一行**）。

**④ 负控 5/5 真红**（累计 **80/80**）——⚠ **头一次只有 4/5**，
查出来的是**真问题**（见⑬）：build.sh 写死 URL ⇒ 静态门红／
`fetch-engine.sh` 写死 `latest/download` ⇒ 静态门红／
`fetch-engine.sh` 不认 `runtime/lib` ⇒ 静态门红／
**只落启动器、不落 `bin/` 与 `runtime/`** ⇒ **行为门红**／
build.sh 内嵌只拷一个文件 ⇒ 静态门红。

**⑤ 元教训 1：⚠ 一条「从来没成功过」的路径 = 一整条**没人见过成功样子**的路径** ——
它能同时藏着好几个错而**一个都不会被发现**（没有失败日志、没有报错、
只是「下载不到」然后静默回退）。
⇒ 这类路径要**专门拿真数据走一遍**（API + 真包 + 真跑一次），而不是读代码猜。

**⑥ 元教训 2：⚠ 「发布包」不是「一个二进制」** ——
落盘时必须**整包**：启动器 / 真二进制 / 运行库三样**一起**，
因为启动器按**自身所在目录**找后两样。⇒ 「下载下来能用」和「只拷一个文件」是两回事。

**⑦ 元教训 3：⚠ 门盯的串，必须**只出现在干活的那一行** ——
本批两道门各栽了一次，方向相反：
① 批 AP：门盯的串**被注释/提示语满足**（把代码改坏，门照样绿）；
② 本批：门盯的 `runtime/lib` **在无关的另一行也出现**（形状判定那行）
   ⇒ 把真正干活的那句删掉，门照样绿。
⇒ 共同结论：**门必须盯「真正干活的代码构造」** ——
既不能盯一个会出现在注释里的裸串，也不能盯一个会在别处重复出现的串。

**⑧ 判据**：selfcheck **393/0**、接线门 **578 项**、ci.sh **12/12**、契约门 **120/0**、
ci-d2 **0/0**；快照**零变化**（本批只动 mac 构建脚本与新脚本）。

### E.2a mac 侧「导出后打不开」：回执里的路径抽不出来（批 AR —— 一条**记在注释里两年**的缺陷）

**① 起因**：deepin 侧 `deepin/src/logic/ArchReceipt.cpp` 的注释里**早就写着**这个 mac 缺陷 ——
> 「mac 的 extractHTMLPath 就栽在这里，导出后「打开」入口始终不出现」

⇒ 但那只是一句**注释**。**注释不是修复** —— mac 侧那份实现**一直没动**，
缺陷**一直在**。批 AR 把它真正修掉了。

**② ⚠⚠ 用引擎实跑把形态坐实**（不能照着注释里的示例改）：
2026-10-20 真跑 `moongit render arch`，回执**原文**是：

```
已写入：/home/superShuai/.deepgit/store/p_f80de38f6095/render/arch.html · 共 0 个文件，0 个函数（语法未通过则不计入）
```

⇒ 路径与文案之间是**全角冒号**（**没有空格**），路径后面跟**中点**。
⚠ 注意：deepin 侧注释里的示例是「已重绘：… · 第 1 版」，**实跑是「已写入：… · 共 N 个文件」**
—— **文案不一样**（但分隔符一样）⇒ 照注释改文案会改错。

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
  `client-check.sh` 的编译清单必须含它（不编 ⇒ 断言永远绿）/ mac 判据必须真的断言 /
  deepin 侧自检必须钉住**引擎实跑原文**的形态。
- **行为夹具**（deepin 侧 selfcheck **393 → 394**）：把**实跑**出来的回执原文照抄进自检
  （原文里路径粘在全角冒号后、后面跟中点、尾部还跟一句统计 ⇒ 两个分隔符都得认）。
- **mac 侧纯函数判据**：`scripts/client-check.sh` 编译清单 +`ArchReceipt.swift`，
  `Tests/ClientCheck/main.swift` 加四条断言（实跑形态 / 结论行 / 相对路径不认 /
  后缀不同的两次抽取互不污染）。
  ⚠⚠ **本机没有 Swift 工具链** ⇒ 这四条**未在本机跑过**，由 mac 侧跑该脚本时验；
  本批**可判**的部分（静态门 + deepin 侧行为夹具）已全部覆盖，**没验的部分照实写明**。

**⑥ 负控 5/5 真红**（累计 **85/85**）：
mac 侧边界不认全角冒号 ⇒ 静态门红／
mac 判据的编译清单里不编它 ⇒ 静态门红／
`ArchPage` 又自带一份复制 ⇒ 静态门红／
`ArchPage` 绕过共享纯函数 ⇒ 静态门红／
**改坏 deepin 侧参考实现的边界** ⇒ **selfcheck 红**（这条是**行为级**的）。

**⑦ 元教训 1：⚠⚠ 对位侧注释里写着的「某某的 bug」**不是修完了，是记下了** ——
`ArchReceipt.cpp` 里那句注释我读过很多遍，一直当成「已知差异」；
**其实它是待办**。⇒ **跨端缺陷要在对端修**，不能在对位侧留句注释了事。
⇒ 而且注释**不会触发任何门** ⇒ 不改代码 ⇒ 缺陷**一直在**。

**⑧ 元教训 2：⚠ 引擎的输出形态要**实跑取证**，不能照着注释里的示例改 ——
注释写「已重绘：… · 第 1 版」，实跑是「已写入：… · 共 N 个文件」⇒ **文案不同**。
（分隔符一样，所以老注释没把修复带歪 —— 但这是**运气**，不是依据。）

**⑨ 元教训 3：⚠ 本机没有目标语言的工具链时，那侧代码只能靠
「静态门 + 对位侧的行为夹具」兜底，且**必须明说哪部分没验** ——
本批 mac 的四条 Swift 断言**没在本机跑过**；台账/提交信息里都写明了。
⇒ 不把「写完了」说成「验过了」。

### E.2b mac 侧布尔旗标只认 `as? Bool`：模型把旗标写成字符串时**恒为假**（批 AS —— 且**两端都漏了「数字」形态**）

**① 起因**：`macos/Sources/deepDolphin/AgentCore.swift` 的注释里**本来就写着**
> 「模型给的布尔/数字经 JSONSerialization 可能落成 Bool/Int/Double/String」

⇒ 而**实现只有 `as? Bool`** ⇒ **说法与实现相反**（批 AI 的教训：
说法与实现相反比说法缺失更危险）。⇒ 注释早就知道会落成字符串，代码却只认布尔。

**② ⚠⚠ 症状**：模型把旗标写成**字符串**（`"force": "true"`）或非 0/1 的数（`2`）
⇒ `as? Bool` 落空 ⇒ 旗标**恒为假** ⇒
AI 说「强制重跑」，`render arch --force` / `arch gen --force` **静默不生效**
（命令照发、旗标没了），界面上还显示「✓ 执行成功」。
⚠ 且 deepin 侧**早就修过同一洞**（`AgentToolPlan.cpp` 的 `flag()` 注释：
「只认布尔会让 flag 永远不生效（--force / --violations 形同虚设）」）
⇒ **mac 侧是漏改的那一侧**。

**③ ⚠⚠⚠ 本批新发现：不是「漏改」，是「**改了一半**」** ——
本批实测 `QJsonValue::toString()` 对**数字**返回的是**空串**（**不是 `"1"`**）：

```
QJsonValue(1).toString()  →  ""      ← 空串，不是 "1"
QJsonValue(1).isDouble()  →  true
```

⇒ deepin 侧那版「补了字符串分支」的 `flag()` 走 `toString()` ⇒ 数字形态**必然落空**
⇒ JSON `{"force": 1}` 在 **deepin 侧也判假** ⇒ **两端都漏了数字形态**。
⇒ 修法：deepin 侧补**数字分支**（**只有 1 为真**），mac 侧新增纯函数 `ToolArgs.flag`
（口径**逐条照抄** deepin 侧）。

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
  ⚠ 这条断言**第一版是红的** ⇒ 红灯直接指出要补什么（这正是行为夹具该有的作用）。
- **mac 侧判据**：`Tests/AgentCheck/main.swift` 加四条断言
  （字符串形态 / 数字只有 1 为真 / 假值与缺省 / 源码 lint 不许退回 `as? Bool`）。
  ⚠⚠ **本机没有 Swift 工具链** ⇒ 这四条**未在本机跑过**，由 mac 侧跑 `agent-check.sh` 时验；
  本批**可判**的部分（静态门 + deepin 侧行为夹具）已全部覆盖，**没验的部分照实写明**。

**⑥ ⚠⚠ 负控头一次只有 4/5 ⇒ 当场查出「第四次同一形状」** ——
第 4 条变异（掏空 mac 侧断言里的 `ToolArgs.flag(p, "force")`）**门没红**。
⇒ 查出来：门盯的是 `ToolArgs\.flag\(`，而它在 mac 侧测试文件里出现 **8 处**
⇒ 变异只动其中 1 处 ⇒ **别处还顶着呢** ⇒ 门没牙。
⇒ 这是同一形状的**第四次**（批 AP 被注释满足 / 批 AQ 在无关的另一行也出现 /
批 AR 只声明不编译也算出现）⇒ 前三次都是**事后人工发现**。
⇒ **收口后负控 8/8 真红**（累计 **93/93**）：退回 `as? Bool` ⇒ 门红／
不认字符串形态 ⇒ 门红／`swiftc` 那行不编 `ToolArgs.swift` ⇒ 门红／
掏空**字符串真值表**断言 ⇒ 门红／掏空**数字形态**断言 ⇒ 门红／
**删掉 deepin 侧数字分支** ⇒ **selfcheck 红**（这条是**行为级**的）／
**加一条串不唯一的新门** ⇒ **门自审计红**／
**把门项写成审计器解析不了的样子** ⇒ **审计器盲区 ⇒ 硬门红**。

**⑦ 修法（把「事后人工发现」变成「机器当场审」）**：
- 批 AS 那条宽松门换成 **5 条盯唯一构造**的门（实测每个在 `macos/` 下**只命中 1 次**）
  ＋ 新增 `arch_need_min`（「**至少** N 次」语义：削减红、增加绿；
  `arch_need_count` 盯「恰好 N 次」会让将来**正常加一条断言反而变红**）。
- 新增 `deepin/scripts/ci-wiring-audit.py`（**门自审计**）：
  逐条数每个 `arch_need` 门项的正则在目标文件里命中几次，
  **豁免基线之外**只要还有一条命中 >1 ⇒ **硬门红**。
- 新增 `deepin/scripts/wiring-multi-hit.exempt`：**历史 53 条已知隐患显式入账**
  （不再藏在暗处）⇒ **新加的门不许落进去**；某条门收紧后审计器会报「已失效」⇒ 可清。
  ⚠ 其中两条正是**前面批次的老门**：批 AQ 的 `runtime/lib`、批 AR 的 `ArchReceipt\.htmlPath\(`
  —— 当时的负控**只是恰好打在被抓住的那一处**，门本身**一直不唯一**。
- 审计器**自报盲区**：解析不到的门项会报出来 ⇒ 且**盲区必须红**
  （否则「没审到的门项」就成了逃逸口 —— 与批 AR「只声明不编译也算出现」同构）。

**⑧ 元教训 1：⚠⚠ 对位实现必须照抄对位的口径** ——
我第一版 mac 侧写的是「**非 0 即真**」，而 deepin 侧是「**只有 1 为真**」
⇒ 照抄后才对齐。⇒ 跨端同一语义，**口径要逐条对**，不是「差不多」。

**⑨ 元教训 2：⚠⚠ 两端都漏了同一个洞 ⇒ 那不是「漏改」，是「改了一半」** ——
deepin 侧早就补过字符串分支，看起来「那边已经修好了」；
实测才发现**数字形态两端都漏**。⇒ 对齐工作必须**同时**检查两端，
不能因为「对面有这条分支」就以为口径一致。

**⑩ 元教训 3：⚠⚠ `QJsonValue::toString()` 对数字返回**空串**（不是 `"1"`）** ——
⇒ 任何「先转字符串再比」的写法，对**数字**都是**恒假**。
⇒ 数字形态必须**先判 `isDouble()`**（且注意 Qt 里 `true`/`false` 存 bool 型
⇒ `isBool()` 也要先判，顺序反了会把 `true` 判成假）。

**⑪ 元教训 4：⚠⚠ 「门盯的串不唯一」第四次同形状 ⇒ 这次上机器** ——
前三次都是**事后人工发现**（撞上了才知道）⇒ 这次让审计器**当场**数命中次数。
⇒ **承诺没有门 = 承诺不存在**（批 AJ）：「门要唯一」这条纪律，也得有门。

**⑫ 元教训 5：⚠ 「恰好 N 次」与「至少 N 次」是两个语义** ——
`arch_need_count` 盯「恰好 N 次」⇒ 将来**正常加一条断言反而变红**
⇒ 门会被人随手调数字 ⇒ 门就废了。⇒ 计数类门要分清这两种语义。

### E.2c 门自审计豁免基线清账（批 AT ——「盯名字」的门改成「盯接线点」）

**① 起因**：批 AS 的**门自审计**（`scripts/ci-wiring-audit.py`）报出 **53 条**
「同一串在目标文件里命中 >1 次」的历史门 ⇒ 它们的形态**全都是**「盯名字不盯接线点」
⇒ **改一处骗得过门**（别处还顶着呢）。

**② ⚠ 仓库里其实早就有这个认识** —— 语法高亮那段门项的注释写着：
> 「⚠ 盯**构造点**（`new CodeHighlighter`）而不是『CodeHighlighter 这个词出现过』——
> 负控实测：只删掉构造那一行、留着 include 与另一个调用点时，后者照样全绿
> （用户看到的源码页签还是一片纯色）。**这已是第三回「门盯名字不盯接线点」**。」

⇒ 也就是说：**这个洞历史上踩了三次**，每次都只补了**当次那一处**，
其余的「盯名字」的门**留在原地**。批 AT 把它**逐条**补齐。

**③ 改法：取「改」不取「另加」** ——
- 「改」= 弱门**本身**改成盯接线点 ⇒ 门项数不变、意图**更强**
  （存在 ⇒ 必有构造点）、且**豁免基线能缩小**（不再命中 >1）；
- 「另加」= 弱门留着 + 新增强门 ⇒ 门项 +1、基线**不缩**（弱门继续留在暗处）。

⇒ **本轮 9 条**（全在接线层），每条新正则实测**在目标文件里只命中 1 次**：

| 门 | 原来盯 | 现在盯 |
| --- | --- | --- |
| PanelWindow 架构图 | `\bshowArch\b` | `showArch\(p\);`（**接线那一行**） |
| PanelWindow 架构图窗 | `\bArchDialog\b` | `new ArchDialog\(`（**构造点**） |
| PanelWindow 代码图谱 | `\bshowCodeGraph\b` | `showCodeGraph\(p\);` |
| PanelWindow 代码图谱窗 | `\bCodeGraphDialog\b` | `new CodeGraphDialog\(` |
| PanelWindow 补丁体检 | `\bshowPatchCheck\b` | `showPatchCheck\(p\);` |
| PanelWindow 补丁体检窗 | `\bPatchCheckDialog\b` | `new PatchCheckDialog\(` |
| PanelWindow 文档窗 | `\bshowDocs\b` | `showDocs\(0\);` |
| PanelWindow 文档窗 | `\bDocsDialog\b` | `new DocsDialog\(` |
| 架构图窗挂画布 | `\bArchCanvasWidget\b` | `new ArchCanvasWidget\(` |

⇒ 豁免基线 **53 → 44 条**（审计器主动报出「已失效 9 条」，已清掉）。

**④ 判据**：接线门 **600 项**（不变）全绿、门自审计硬门 **rc=0**（豁免外隐患 0 条）、
selfcheck **395/0**、ci.sh **12/12**、契约门 **120/0**、ci-d2 **0/0**、快照**零变化**
（本轮只动判据层）。

**⑤ 负控 9/9 真红**（累计 **102/102**）：把「干活的那一行」改坏（改名）⇒ 门必须红。
⚠ 实测每次是 **1 条真门红**（另一条「✗」是脚本的汇总行，不是门项）。

**⑥ 元教训 1：⚠⚠ 静态门类的负控**不要编译** ——
本批的变异会**故意把源码改坏** ⇒ 编译必然失败；
而接线门是**源扫描**，压根不需要编译 ⇒
**编译失败会让负控提前退出**（`build_or_die`）⇒ **反而测不到门**。
⇒ 静态门负控只跑 `ci-wiring.sh`；**行为级**负控（跑 selfcheck）才编译。
（前面几批的负控脚本都无条件编译 ⇒ 那是**因为它们的变异不改 C++**，没暴露这个坑。）

**⑦ 元教训 2：⚠⚠ 负控要**双断言**：门红 **且** 目标串已消失** ——
只判「门红了」不够：可能是**别的门碰巧红了**（比如审计器因为豁免键失效而红）。
⇒ 变异脚本额外断言「目标串在变异后已消失」⇒ 门红**只可能**是因为它盯的就是那个串。

**⑧ 元教训 3：⚠⚠ 「复刻一份实现」= 两套口径迟早漂移** ——
审计器一开始用 **Python 正则复刻**了 `ci-wiring.sh` 的 `strip_comments`；
实测撞到过：临时工具报「命中 2 次」，而手测与 shell 口径都是 **4 次**
⇒ 差点据此做出错误判断（「4 行 vs 2 次」看着像矛盾）。
⇒ 已改成**直接调与 `ci-wiring.sh` 逐字相同的那条 perl/sed** ⇒ 单一真相源。
⇒ 并对**全部 414 条**门项做了**两套口径对拍** ⇒ 不一致 **0 条**。

**⑨ 元教训 4：⚠ 审计器要**自报盲区**，且**盲区必须红** ——
解析不到的门项 = 那些门**根本没被审** ⇒ 只打印警告就是留了逃逸口
（与批 AR「只声明不编译也算出现」同构）⇒ 盲区存在时硬门红。

**⑩ 第二轮（脚本类 / mac 侧 / 平台层，10 条）** ——
第一轮清完 9 条后基线里还有 44 条 ⇒ 本轮清**脚本类**与 **mac 侧**那批。

⚠⚠ **本轮的新发现：「命中次数」口径下还有一种隐患** ——
**同一行里出现两次**也算「>1」（例：`build-deb.sh` 的 `rpath|runpath` 就在**同一行**）
⇒ 收紧时必须用**行级构造**（把整行的独特部分作为正则），不能只盯一个词。

| 门 | 原来盯 | 现在盯 |
| --- | --- | --- |
| `build-deb.sh` | `rpath|runpath` | 那行 `readelf -d … \| grep -qiE "rpath\|runpath"` |
| `ci.sh` | `stderr\.txt` | `2>"$REPRO_DIR/stderr\.txt"`（**落盘**那一行） |
| `fetch-engine.sh` | `browser_download_url` | 改 `arch_need_min`（**至少 2 次**：「取 + 洗」两处都要在） |
| `fetch-engine.sh` | `bin/moongit-cli` | `[ -x "$pkg_root/bin/moongit-cli" ]`（**验可执行**那一行） |
| `fetch-engine.sh` | `runtime/lib` | 拆两条：「验目录存在」+「验非空」 |
| `engine-fetch-check.sh` | `moongit-cli` | `[ -x "$DEST/bin/moongit-cli" ]` |
| `engine-fetch-check.sh` | `runtime/lib` | `if [ -d "$DEST/runtime/lib" ] &&`（**存在且非空**那一行） |
| `macos/build.sh` | `ENGINE_ROOT/bin/moongit-cli` | `cp "$ENGINE_ROOT/bin/moongit-cli"`（**拷贝**那一行，不是「判断形状」那一行） |
| mac 判据 | `ArchReceipt\.htmlPath\(` | 拆三条，各盯一条断言（实跑原文 / 结论行 / 相对路径不认） |
| `probe-sni-icon.sh` | `IconPixmap` | `Properties.Get org.kde.StatusNotifierItem IconPixmap`（**D-Bus 调用**那一行） |

⇒ 门项 600 → **603**（两条各拆成多行 ⇒ 净增 3）、豁免基线 44 → **34**、
门自审计硬门 **rc=0**（豁免外隐患 0 条）。
**负控 13/13 真红**（累计 **115/115**）。

**⑪ 元教训 6：⚠⚠ 审计器是「**门视角**」，不是「文件视角」** ——
它只检查**门项的正则**在目标文件里是否唯一，**不检查**「文件里有没有别处也有这个词」。
⇒ 这正是我们要的（要盯的是「门盯的串唯一」）；
⇒ 但也意味着**把弱门换成行级门后，那个词在文件里出现几次就不再有人管** ——
好在行级门抓的是**结构**（那一行还在不在），比抓词强 ✓。

**⑫ 元教训 7：⚠ 拆成多条行级门时，门项数会变** ——
本轮 10 条门改完变成 13 条（603 项）⇒ **门项数不是目标，门强度才是**。
⚠ 但**别忘了同步**：审计器的「已失效」清单要用**审计器自己算出来的键**去清
（`scripts/ci-wiring-audit.py` 的 `read_exempt` + `parse_wiring`）⇒ **不手抄** ⇒ 不会抄错。

**⑬ 第三轮（托盘探针 / 脚本 / 平台层，10 条）** ——
清完第二轮后基线里还有 34 条 ⇒ 本轮清**托盘探针**与**脚本/平台层**那批：

| 门 | 原来盯 | 现在盯 |
| --- | --- | --- |
| `probe-deepin-tray.sh` | `TrayIcons` | `Properties.Get "$TRAY_SERVICE" TrayIcons`（**D-Bus 调用**那一行） |
| `probe-deepin-tray.sh` | `WM_NAME` | `xprop -id "$WID" WM_NAME` |
| `probe-deepin-tray.sh` | `GetName` | `"$TRAY_SERVICE.GetName" "$WID"` |
| `probe-deepin-tray.sh` | `deepin-window` | `[ "$BACKEND" = "deepin-window" ]`（**判定**那一行） |
| `ci-platform-probe.sh` | `dpiEdgeLevels` | 拆两条：解析 **legacy 列** / 解析 **aware 列** |
| `ci-docs-lang-probe.sh` | `docs-lang-probe` | `--docs-lang-probe`（**真的去跑那个探针**那一行） |
| `main.cpp` | `headlessDocsLangProbe` | `return headlessDocsLangProbe(argc, argv);`（**调用**那一行） |
| `main.cpp` | `--receipt-file-path\b` | 拆两条：**认得**这个 flag / **取到**它的位置 |
| `Settings.cpp` | `app\.language` | 拆三条：**读** / **删** / **写** |
| `IconResolver.cpp` | `platform::dpiPixmap\(` | ⚠ **两处源码完全相同** ⇒ 行级构造分不开 ⇒ 改 `arch_need_min`（至少 2 次） |

⇒ 门项 604 → **608**、豁免基线 34 → **24**、门自审计硬门 **rc=0**。
**负控 14/14 真红**（累计 **129/129**）。

**⑭ 元教训 8：⚠ 意图天然是「多处」的门，只能用「至少 N 次」** ——
`IconResolver` 的两处 `platform::dpiPixmap(size);` **源码一字不差** ⇒ 行级构造**分不开**
⇒ 只能用 `arch_need_min`（至少 2 次）。
⚠ **代价要说清**：`arch_need_min` **不被审计器覆盖**（审计器只审 `arch_need`），
且「删一处 + 在别处加一处」**骗得过**它 ⇒ 这条门比其它清过的门**弱一档**。
⇒ 台账/提交信息里都写明，不假装它跟别的一样强。

**⑮ 元教训 9：⚠⚠ 「子串顶替」在负控里也会咬人（第二轮就撞过，第三轮又撞到 3 条）** ——
把 `TrayIcons` 改成 `TrayIcons_DISABLED` ⇒ **目标串仍是新串的前缀** ⇒
grep 照样匹配 ⇒ **命中数没变** ⇒ 门不红。
⚠ **第一版断言（目标串「消失」）抓不到这个**（目标串确实不再出现，只是**匹配**还在）
⇒ 会误判成「门没牙」⇒ 白查一轮。
⇒ **第二版断言（命中次数必须减少）当场抓住** ⇒ 这就是「断言要盯门依赖的那个量」的价值。

**⑯ 剩余**：豁免基线里**还有 24 条**未清（判定层 / UI 层 / 平台层 / 托盘探针剩下的）。
清账要**逐条读代码**才能确定「干活的那一行」⇒ 分批做，不赶。

### E.2d 豁免基线**清到 0**（批 AU —— 「改一处骗得过门」这个洞一个不剩）

**① 起因**：批 AT 三轮清完 29 条后，基线里还剩 **24 条**（判定层 / app 层 / UI 层 / 平台层 /
CodeGraphDialog）⇒ 本轮**一次清完**。

**② 手法**（与前几轮一致，但多了三种新形态）：
- **盯调用/构造那一行**（不是盯名字、不是盯定义）：
  `symbolId`（调用）、`keywords`（调用）、`kindKey`（调用）、`categoryOf`（读/写两处）、
  `packagedBinName`（拼落盘路径那行）、`DS::semColor`（关键字/字符串/数字三处）、
  `QComboBox`（造下拉框那行）、`m_leftStack`（造堆叠页那行）、
  `m_heat->setData`（清空/喂数据两处）、`requiredProperties`（读名/取表两处）、
  `registerCustomType`（三种类型三条）、`xcb_get_selection_owner`（**真的去查**那行）、
  `advertisedVisual`（调用）、`HeatmapWidget`（造热力图那行）。
- **盯定义那一行**（意图本就是「有这个函数」）：
  `writableKeys`、`content`（⚠ 之前盯「content」这个词，**英文错误消息里也有** ⇒ 改一处骗得过门）。
- **盯夹具那一行**：`SelfCheckGraph.cpp` 的引擎实跑原文
  （⚠ 之前盯「已写入：」⇒ 改**说明文字**也会红 ⇒ **盯错了地方**）。
- **意图天然是多处**（同一构造**一字不差** ⇒ 行级构造根本分不开）⇒ 改用 `arch_need_min`：
  `Canvas2D`(4)、`CodeGraphBuild::visibleRows`(2)、`QDBus::Block, 2000`(4)、
  `m_backend == …::DeepinWindow`(3)。
- **删掉两条弱门**（意图已被更强的门覆盖）：
  · `DocsDialog.cpp` 的 `setButtonText` ⇒ 已被两条 `arch_need_count_in_fn`
    （盯 `applyLanguage` 函数体内**恰好一次**）完全覆盖；
  · `CodeGraphDialog.cpp` 的 `ArchCanvasWidget|CodeGraphBuild` ⇒ 已被
    `visibleRows` + `m_heat->setData` 两条**从两个方向**覆盖。

**③ ⚠⚠⚠ 本轮抓到一个真问题：`arch_need_min` 的下限**定低了 ⇒ 门没牙** ——
写负控时发现 `Canvas2D` 那条下限写的是 **3**，而该串在 `HeatmapWidget.cpp` 里命中 **4** 次
（1 处 `include` + 3 处 `Canvas2D canvas(&p);`）
⇒ **删掉一处构造仍剩 3** ⇒ 门照样绿 ⇒ **门没牙**。
⇒ 改成 4（= 实际命中数）⇒ 删一处即红。
⇒ 并给审计器加了一条**校准**：`arch_need_min` 的**下限必须 == 当前命中数**
（定低了没牙、定高了恒红）⇒ 硬门模式下失准 ⇒ **退出码 4**（红）。
⚠ 实测有牙：故意把下限改回 3 ⇒ 硬门 rc=4 并指出
「下限 3 ≠ 实际命中 4 ⇒ 门没牙（删一处仍够）」。
⇒ 这把「`arch_need_min` 不在审计覆盖内」那个缺口**补上了一半**：
它的「串不唯一」是**语义允许**的，但**下限必须配得准**。

**④ 成果**：
- 门自审计报的「**命中 >1**」从 11 条降到 **0 条**
  ⇒ **全部 `arch_need` 门项的正则在目标文件里都只出现一次**；
- 豁免基线 **24 → 0 条**（文件保留，改为带说明的空基线）⇒
  **今后新加的门只要串不唯一，硬门立刻红**（没有基线可躲）；
- 接线门 610 → **613** 项全绿；selfcheck **395/0**、ci.sh **12/12**、
  契约门 **120/0**、ci-d2 **0/0**、快照**零变化**。
- **负控 29/29 真红**（累计 **158/158**）。

**⑤ 元教训 1：⚠⚠ 「至少 N 次」的下限必须 == 当前命中数** ——
否则门要么没牙（删一处仍够）要么恒红（定高了）。
⚠ 这类门**不被审计器的「串唯一」检查覆盖** ⇒ 必须**另加一条校准**才能有牙。

**⑥ 元教训 2：⚠⚠ 要让「计数类」门红，必须让那个**模式串整体不再出现** ——
把它改成「原串 + 后缀」**没用**（grep 照样匹配前缀）⇒
变异的替换必须**打断模式串本身**（改前缀/中间）。
⚠ 这也是「子串顶替」在负控里的第四种形态。

**⑦ 遗留（缺口，如实记着）**：审计器**不覆盖**这几类门 ⇒
`arch_need_ml`（跨行）、`arch_need_count_in_fn`（收窄到函数体）、
`arch_need_any`（跨文件）、`arch_need_count`（恰好 N 次）⇒
其中 `arch_need_count_in_fn`（范围已收窄）本**可以**是唯一的 ⇒ **待补**（批 AV）。

### E.2e 审计器**覆盖缺口清零**（批 AV —— 「任一文件里有」这种门**根本没有次数**）

**① 起因**：批 AU 收尾时把「审计器不覆盖哪些门」如实写进了台账 ⇒ 批 AV 就去补。
先做**只读探针**，把四类门的「洞」摸清楚，再决定补哪一类、怎么补。

**② 探针实测（4 类门逐条扫）**：
| 门型 | 条数 | 有没有「改一处骗得过门」的洞 | 结论 |
|---|---|---|---|
| `arch_need_ml`（单文件、压行后匹配） | 3 | **有 1 条**（`platform::dpiPixmap(` 压行后命中 2 次） | **要补**（查压行后唯一性） |
| `arch_need_any`（跨文件、「任一文件里有」） | 82 | **有 42 条**（glob 范围总命中 >1） | **要补**（换门型） |
| `arch_need_count`（单文件、恰好 N 次） | 23 | **0 条失准** | **不用补**（它自己数次数） |
| `arch_need_count_in_fn`（函数体内恰好 N 次） | 10 | **0 条失准** | **不用补**（它自己数次数） |

⚠⚠ **判据的细化（关键）**：`arch_need_any` 门红 = 「**所有**匹配文件里都没有」
⇒ **跨文件多现同样是洞** ⇒ 判据必须是「glob 范围内**总命中数 > 1**」
（不是「某个文件里 >1」）。这个细化把「有洞」的条数从 8 条拉到 **42 条**。

**③ ⚠⚠⚠ 老 `arch_need_any` 的两个洞（实测，不是推演）**：
- **洞 1（次数维度缺失）**：它只判「有没有」，不判「有几处」
  ⇒ glob 范围里 `res.receipt` 出现 **7 处** ⇒ 删掉其中一处、别的还在 ⇒ 门照样绿。
- **洞 2（口径不一致）**：它的实现是 `grep -lE` ⇒ **不剥注释**
  ⇒ 注释里提一嘴就顶替（批 AP 同形状）。
  ⚠ 实测：`AppModel.cpp` 的 `applyStatusPayload` 在**注释**里也有一处
  ⇒ 老口径命中 **4** 次、真实命中 **3** 次
  ⇒ 而 `arch_need` / `_ml` / `_count` / `_count_in_fn` **全都剥注释** ⇒ **四类门口径不一致**。

**④ 手法：换门型（不是「另加一条」）** ——
`arch_need_any` **整个删掉**，82 条按**意图**分两类迁走：
- **`arch_need_any_count <正则> <恰好 N 次> <说明> [glob]`**（31 条）——
  用于**接线点**类（「AppModel 调引擎 X」）：接线**应当唯一** ⇒ 重复接线 = 隐患
  ⇒ 「恰好一次」才能同时抓「删掉」和「多了一处」。
- **`arch_need_any_min <正则> <至少 N 次> <说明> [glob]`**（51 条）——
  用于**判据**类（「SelfCheck 覆盖了 X」）：同一判定层被**多条断言**覆盖是**正常**的
  ⇒ 用「至少 N 次」：删一条断言 ⇒ 红；加一条断言 ⇒ 仍绿（**不拦正常演进**）。
⚠ 两个新门型都**数「glob 范围内总命中数」**（跨文件加总）且**剥注释**
⇒ 洞 1 与洞 2 一并堵死。
⚠ 分派的依据是**意图**不是现象：SelfCheck 判据**会正常增删**（不许拦），
AppModel 接线**应当唯一**（重复即隐患）⇒ 两者不能用同一套语义。

**⑤ 顺手抓到一条「盯错了对象」的门**：
`arch_need_any 'QStringLiteral\("overview"\)'` 说明写的是「AppModel 调引擎 **graph** overview」，
但它同时命中 AppModel.cpp 的 **index** overview ⇒ **盯错了**。
⇒ 照 414/415 的对位写法收窄成 `QStringLiteral\("graph"\), *QStringLiteral\("overview"\)`
⇒ 命中 1 次（批 AS 纪律：对位实现必须照抄对位的口径）。

**⑥ 顺手抓到一条「压行后多现」的门**：
`arch_need_ml` 的 `platform::dpiPixmap\(` 压行后命中 **2** 次
（`QPixmap pm =` 大点 / `QPixmap barPm =` 迷你条）⇒ 改一处骗得过门
⇒ 拆成**两条各自唯一**的门（盯「变量名 + 调用」那一行）
⇒ 门项数 613 → **614**。

**⑦ 审计器扩覆盖（批 AU 的校准扩到跨文件版）**：
- `arch_need_ml` ⇒ 查「**压行后**命中 >1」；
- `arch_need_any_count` ⇒ 校准「实际总命中 == 期望」；
- `arch_need_any_min` ⇒ 校准「**下限 == 实际总命中**」（下限低了没牙、高了恒红）；
- `arch_need_count` ⇒ 校准「实际 == 期望」；
- `arch_need_count_in_fn` ⇒ 校准「函数体内实际 == 期望」。
⇒ **五类「要出现」的门全部在校** ⇒ 覆盖缺口**清零**。
⚠⚠ **口径绝不复刻**：审计器**从 `ci-wiring.sh` 里 `sed` 抽出** `strip_comments` /
`any_hits` / 那段切函数体的 **awk 原文**，拼成临时脚本再调
⇒ 门侧改口径时审计侧**自动跟着变** ⇒ 零漂移（批 AS 纪律的延续）。
⚠ **三套口径对拍实测**：审计器（抽原文）/ Python 独立实现 / 门自己的 `any_hits`
⇒ 82 条门项**逐条一致，0 条不一致**。

**⑧ 成果**：
- 门项 **614** 项全绿（`arch_need` 422 / `_ml` 4 / `_any_count` 31 / `_any_min` 51 /
  `_count` 23 / `_count_in_fn` 10）；
- 审计器报的「命中 >1」= **0 条**（`need` 与 `_ml` 都是）；
- **所有配准校准 0 条失准**；豁免基线仍是 **0 条**；
- selfcheck **395/0**、契约门 **120/0**、ci.sh **12/12**、ci-d2 **0/0**、快照**零变化**；
- **负控 10/10 真红**（累计 **168/168**）。

**⑨ 元教训 1：⚠⚠ 「有没有」和「有几处」是两种门，混用必然有洞** ——
「任一文件里有」这种语义**结构上**就没有次数维度 ⇒ 必然被别处顶替。
⇒ 想让它有牙，只能**把次数加进语义**（恰好 N 次 / 至少 N 次）。

**⑩ 元教训 2：⚠⚠ 门型之间的**口径必须一致** ——
同一个脚本里四种门用两种剥注释口径 ⇒ 报告里的次数不可信
⇒ 人会据此做错判断（本次实测：老口径 4 次 / 真实 3 次）。

**⑪ 元教训 3：⚠⚠ 负控的**每个 case 必须是「原始状态 + 本 case 的变异」** ——
本批第一版负控忘了在 case 之间还原 ⇒ N6/N7 改了**门项里的数字**且一直没还原
⇒ 后续 case 的审计器**一直**返回 rc=4（配准失准**抢先于**隐患检查）
⇒ 两条本该红的 case 报的是错码。
⇒ 负控脚本要加 `restore_now`（**备份式**还原，
⚠ **不能用 `git checkout`** —— 被测文件此刻有**未提交**的改动 ⇒ 会把工作整个回滚掉）。

**⑫ 遗留（缺口，如实记着）**：
- `arch_need_any_min` 弱一档：下限 == 当前命中数 ⇒ 「删一处 + 加一处」（子串顶替）骗得过它
  ⇒ 这与 `arch_need_min` 同款，是「意图天然多处」这一类门的**共同代价**，已在 README 记着。
- 审计器**不审** `arch_forbid`（有意：它判「不该有的东西没了」，出现 >0 本来就红）。
- 跨目录门（`deepin/scripts/ci-wiring.sh` 从仓根跑）里那部分 `arch_need_any*`
  的 glob 相对 `SRC` 解析，跨目录调用时 `SRC` 仍指向 `deepin/` ⇒ 口径一致。

### E.2f 分隔线是**真线**，不是用文字冒充（批 AW —— 顺带否掉一个想当然的修法）

**① 起因**：M3c 剩余项之一（`ProjectDetailPage.cpp` 两处 `QLabel(QStringLiteral("|"))`）。

**② ⚠ 先查对位，别自创**（批 AS 纪律）：mac 侧 `DetailViews.swift` 的
`gitOpButtons` 里是 **SwiftUI 原生 `Divider().frame(height: 14)`**
⇒ 1pt 宽、限高 14 的**真线**。
⇒ deepin 侧的 `QLabel("|")` 是**自创的降级写法**（不是「另一种风格」）⇒ 该改。

**③ ⚠⚠ 实测证据**（`/tmp/aw-probe2.cpp`，独立小程序只依赖 Qt6Widgets）：
| | 逻辑尺寸 | 物理像素 @dpr=1 | 物理像素 @dpr=2 |
|---|---|---|---|
| 旧写法 `QLabel("\|")` | **4 × 18** | 4 × 18 | **8 × 36** |
| 真线（1 逻辑宽 × 14 高） | 1 × 14 | 1 × 14 | 2 × 28 |

⇒ 旧写法有**四个**问题，且都出在「用文字冒充线」上：
① 宽 **4** 逻辑像素（QLabel 带文本边距）而不是 1px ⇒ 分隔线离两侧按钮更远；
② 高 **18**（字体高）而不是 14 ⇒ 与旁边按钮不对齐；
③ 它是**字形** ⇒ 随字体/字号缩放变形，HiDPI 下实测占 8×36 物理像素；
④ 颜色用 QSS 写死 ⇒ 是**构建时快照** ⇒ 切主题后不更新。

**④ ⚠⚠⚠ 实测否掉了一个想当然的修法**：
本来打算直接用 `QFrame::VLine` + `QFrame::Plain`（Qt 里画竖线的标准做法）。
⇒ **实测它画出来的是 `QPalette::Text` 色**（#ff000000），**不是** `QPalette::Mid`
⇒ 深色主题下那是一条**看不见的黑线**（而 `DS::surfaceBorder()` 走的正是 Mid 口径）。
⇒ **只能自绘**（颜色取 `DS::surfaceBorder()`）。
⚠⚠ **教训：组件库的原生外观不能靠记忆** —— 「`QFrame::VLine` 画分隔线」这种
「大家都知道」的写法，在本项目的**深色主题**下是错的。

**⑤ 修法**：
- 新增 `src/ui/common/VDivider.h`：**自绘**真线（`setFixedWidth(1)` +
  `setFixedHeight(DS::Height::divider)` + `p.setBrush(DS::surfaceBorder())`），
  **不开抗锯齿**（1px 线开了 AA 边缘会半透明，看着像灰边而不是线），
  **每次 paint 都重取 token**（切主题后重绘就拿到新色），
  并在 `QEvent::ThemeChange` / `PaletteChange` 时 `update()`。
- `DS::Height::divider = 14` 新增一档（**对位** mac 的 `frame(height: 14)`）⇒ 单一真相源。
- `ProjectDetailPage.cpp`：两处改走**唯一构造点** `vDivider(parent)`
  （为什么唯一：分隔线一旦在两处各写一遍 `new VDivider(...)`，
  宽度/高度/颜色三处口径就会分叉）。

**⑥ ⚠ 判据分两层，缺一不可**：
- **静态门 13 条**（`ci-wiring.sh` 批 AW 段）：盯 `DS::Height::divider` / `setFixedWidth(1)` /
  `setFixedHeight(DS::Height::divider)` / `p.setBrush(DS::surfaceBorder())` /
  `QEvent::ThemeChange` / 唯一构造点的**定义行** / `vDivider(` **恰好 3 次** /
  `arch_forbid_tree 'QStringLiteral\("\|"\)'`（全仓不许用文字当分隔线）/
  探针的**调用行** / `--divider-probe` flag / 断言脚本的取值行 / CI 真跑那一门。
- **行为探针**（`--divider-probe` + `scripts/ci-divider-probe.sh`）：**真渲染**一次，量墨迹 ——
  逻辑宽 **1**、逻辑高 **14**、`inkWidth == round(dpr)`、`inkHeight == round(14*dpr)`、
  `inkColor == tokenColor`、`opaque == 1`。
⚠⚠ **两层缺一不可**：探针测的是**组件本身** ⇒ 页面改回 `QLabel("|")` 它照样绿；
静态门测的是**页面用的是不是这个组件** ⇒ 但它证明不了「画出来真是 1px」。
⇒ 合起来才守得住。

**⑦ ⚠⚠ 快照抓不到它**（必须写明）：详情页**不在快照矩阵里**
（快照拍 dashboard / board / milestones / setupguide）
⇒ 本批**快照零变化** ⇒ 也意味着**快照证明不了这次修复**
⇒ 探针门是它**唯一**的行为证据。

**⑧ ⚠⚠ `--selfcheck` 里放不了这类判据**（实测踩出来的约束）：
`--selfcheck` 分支在 **GUI 应用构造之前**就 `return`
⇒ 那个模式下**没有 QApplication** ⇒ **建不了 QWidget**（建了会崩）
⇒ 几何这类「要真渲染才量得到」的判据只能走**无头探针**路线
（探针自己构造 `DApplication`，与 `--docs-lang-probe` 同款）。

**⑨ 成果**：门项 614 → **627**（+13）全绿；selfcheck **395/0**、契约门 **120/0**、
ci.sh **12/12**、ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、
三套口径对拍 **0 条不一致**；**负控 6/6 真红**（累计 **174/174**）。

**⑩ 元教训 1：⚠⚠ 「用文字/字符冒充一个图元」是一类缺陷** ——
分隔线用 `"|"`、分隔符用 `"-"`、图标用 emoji ⇒ 看着像、实际不是
⇒ 该改的是**载体**（换成真图元），不是去调字号/颜色/间距把它「调得像」。

**⑪ 元教训 2：⚠⚠ 组件库的原生外观不能靠记忆** ——
`QFrame::VLine` 画的是 `Text` 色这件事，**只有实测才知道**；
凭印象改 ⇒ 深色主题下出一条看不见的黑线。

**⑫ 元教训 3：⚠⚠ 探针自己也会犯批 AP 的坑** ——
本批探针**第一版**就是把 pixmap 按**逻辑**尺寸建（没按 dpr 放大）
⇒ dpr=2 时量到的是逻辑像素 ⇒ 会把「2 物理像素的线」误判成「1 物理像素」。
⇒ 写渲染探针时**先问「我量的是逻辑还是物理」**（批 AP 已踩过一次，这里又踩了一次）。

**⑬ 元教训 4：⚠⚠ 第六次同形状（门盯的串在别处也出现）** ——
新增的门项 `inkWidth` 命中 **2** 次（取值那一行 + **缺字段的错误消息**里也列了它）
⇒ 审计器**当场抓到**（批 AS 上机器审的价值）⇒ 改成盯 `field inkWidth`（取值那一行）。
⇒ 形态与批 AP「被注释满足」/ 批 AQ「在无关的另一行也出现」/ 批 AR「只声明不编译」/
批 AS「测试文件里 8 处同形」/ 批 AV「glob 范围跨文件多现」**同构**。

**⑭ 未验（照实写明）**：
- ⚠ **真机 DDE 上的目视观感**没验：分隔线变窄变矮（4×18 ⇒ 1×14）之后，
  按钮排里它与两侧按钮的**间距观感**、深色主题下**够不够明显**，需真机目视。
- ⚠ **详情页的像素级证据**没有：详情页不在快照矩阵 ⇒ 本批**只有几何/颜色**的量化证据，
  没有「整页长什么样」的证据。
- ⚠ **HiDPI 125%/150%** 下的目视未验（本机只能测到 1 / 1.5 / 2 的**几何**）。

### E.2g 门可以**永远绿**：正则里的写法不被 `grep -E` 认 ⇒ 门形同虚设（批 AX）

**① 起因**：M3c 剩「图标名 / 动效」两项 ⇒ 本批先做**只读实测体检**，再决定做不做。
⚠⚠⚠ **体检过程中挖出的东西比 M3c 本身重要得多**（下面第 ③～⑥ 条）。

**② M3c 的实测结论（全树扫）**：
- **图标名零绕过**：全树 `QIcon::fromTheme("…")` **0 处**、`QIcon("…")` **0 处**
  ⇒ 图标名真的只走 `logic/IconNames` 这一个出处（批 U 做的事没退化）。
- 清单 **27 个**逻辑图标：**零使用 0 个**、清单外使用 **0 个**。
- **动效全项目只有一处**：`AgentDialog.cpp` 的新消息自动滚动
  （`new QPropertyAnimation(` 命中 1 处；`QVariantAnimation` / `QAnimationGroup` 全树 0 处）
  ⇒ 时长走 `DS::MotionStandardMs`（200ms）、缓动 `QEasingCurve::InOutQuad`。
⇒ 这三条都**已达成** ⇒ 落成 8 条门钉住（承诺没有门 = 承诺不存在）。

**③ ⚠⚠⚠ 我差点做出一个错误判断（幸好实测了）**：
写负控时发现新加的门不红 ⇒ 顺着查下去，我**凭印象**认定
「GNU `grep -E` 不支持 `\s`（那是 `-P` 的扩展）」⇒ 准备把仓里 **14 处**用 `\s` 的门
全部改成 `[[:space:]]`。
⇒ ⚠ **实测推翻了这个判断**（GNU grep 3.11）：
| 写法 | `grep -E` |
|---|---|
| `\s` `\S` `\w` `\W` `\b` | **都有效**（GNU 扩展） |
| ⚠ `\d` `\D` | **无效**（只有 `grep -P` 认） |

⇒ ⇒ 若照那个印象改，会**白改 14 条门**（而且改完行为不变，察觉不到）。
⚠⚠ **教训与批 AW「组件库的原生外观不能靠记忆」同款**：
**凭印象判断「某个工具认不认某种写法」＝ 给自己埋雷** ⇒ 必须**实测**。
⚠ 顺带一个**好消息**：批 AP 那 11 条「不许再开 1x 位图」的 `arch_forbid` 门
（`QPixmap\s+(pm|barPm)\(`）**是真门**（`\s` 有效 + 逐条实测零命中 = 绿）⇒ 那个承诺有门守着 ✔

**④ ⚠⚠⚠ 真发现：我自己新加的门里就有一条「永远绿」的门** ——
`arch_forbid_tree 'setDuration\(\s*\d'` 里的 `\d` **不被 `grep -E` 认**
⇒ 那条门**永远匹配不到任何东西** ⇒ **永远绿** ⇒ **形同虚设**。
⚠⚠ 它是**负控当场抓到的**（第一版负控报「命中数没按预期变 ⇒ 变异没生效」）
⇒ 顺着这条报错往下查 ⇒ 挖出门自己的洞（**报错指向的是变异，根因却在门**）。

**⑤ ⚠⚠⚠⚠ 「门形同虚设」有两种形态，后一种才是真洞**：
- `arch_need` 类（出现过即可）：正则写坏 ⇒ 匹配不到 ⇒ **门自己会红** ⇒ CI 能发现（**不静默**）。
- ⚠⚠⚠ **`arch_forbid` 类**（不该有的东西没了）：正则写坏 ⇒ 永远零命中 ⇒ **永远绿**
  ⇒ **没有任何信号** ⇒ 而 forbid 门判的正是「不该有的东西没了」⇒ 它**本来就常年绿**
  ⇒ **写坏了跟没写一样** ⇒ **静默失效**。
- ⚠⚠⚠ 而且 **forbid 门不在审计覆盖内**（批 AS 有意为之：它判「不该有的东西没了」，
  出现 >0 本来就红，不属于「被别处顶替」的隐患）
  ⇒ ⇒ **它们的正则有效性从来没被审过** ⇒ 这就是那个洞的完整形状。

**⑥ 修法：给审计器补上第 2、第 3 个盲区**（批 AS 补过第 1 个「解析失败」）：
- **① 门项正则的「写法体检」**：逐条检查**所有**门型（**含 forbid**）的正则参数，
  有没有 `grep -E` **不认**的转义 ⇒ 有 ⇒ **硬门红（rc=5）** 并指出改法
  （`\d` → `[0-9]`、`\D` → `[^0-9]`）。
  ⚠ 危险清单**只列实测确认无效的**（`\s`/`\S`/`\w`/`\W`/`\b` 都有效 ⇒ 不许误报）。
  ⚠ 判「单个反斜杠」：连续反斜杠数为**奇数**才算转义（`\\d` 是「字面反斜杠 + d」⇒ 合法）。
- **② 「命中 0 次 ⇒ 红」**：`arch_need` / `arch_need_ml` 的语义是「**必须存在**这个串」
  ⇒ 命中 0 次 = 门永远匹配不到 = 门是空的 ⇒ **rc=5**。
  （这两类门在 `ci-wiring.sh` 里自己就会红 ⇒ 不是静默；但在**提交前**由审计器
  明确指出「哪条门是空的」比让 CI 报一堆 ✗ 更好。）

**⑦ M3c 收口：8 条新门**（627 → **635**）：
- 图标名唯一出处：`arch_forbid_tree` × 2
  （`QIcon::fromTheme\(\s*(QStringLiteral\()?"` 与 `QIcon\(\s*(QStringLiteral\()?"`
  ⇒ **两种形态都盖**：字面量直给 与 `QStringLiteral(...)` 包裹
  —— ⚠ 第一版只盖了前者 ⇒ 负控 N1/N2 当场抓到漏网形态）。
- 动效：全项目只有一处动画（`arch_forbid_tree` + 允许 `AgentDialog.cpp`）、
  时长不许散写数字、只用一种动画机制、那唯一一处走了 token、缓动统一、token 的唯一取值。

**⑧ ⚠ 一个查出来的真事实，但**决定不修**：`refresh` 一个图标被用于**四种语义** ——
「刷新（Ctrl+R）」/「重新索引」/「git **fetch**」/「更新（浅/深更新）」。
⇒ **不修**的理由（写清楚，免得下一个人重复调研）：
① mac 侧是 **SF Symbols**（`arrow.clockwise` 刷新 vs `arrow.triangle.2.circlepath` fetch，
   两者**确实**区分），deepin 侧是 **freedesktop 主题名** ⇒ **不是同一套图标系统**
   ⇒「逐字对位」在图标这一层**不成立**；
② 两条都是「循环箭头」⇒ **用户分辨不出** ⇒ 改动的**实际收益接近零**；
③ 新候选名能否在**真机主题**里解析，本机**测不全**（本机主题 ≠ 真机主题）
   ⇒ 风险不为零（IconNames 注释写明：链里只有一个名字 ⇒ 缺名时**静默空图标**）。
⇒ ⇒ 保留现状，把这条**实测事实**记在这儿（是**已知事实**，不是缺陷）；
⇒ **将来若要区分，判定标准是「用户能否分辨」，不是「mac 用了哪个符号」**。

**⑨ 成果**：门项 627 → **635**（+8）全绿；selfcheck **395/0**、契约门 **120/0**、
ci.sh **12/12**、ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**；
**负控 8/8 真红**（累计 **182/182**）—— 含两条**审计器自身**的负控
（正则写坏 ⇒ rc=5；门命中 0 次 ⇒ rc=5）。

**⑩ 元教训 1：⚠⚠ 凭印象判断「某个工具认不认某种写法」＝ 给自己埋雷** ——
我差点把 14 条好门改坏（而且改完行为不变 ⇒ 察觉不到）⇒ **实测**。

**⑪ 元教训 2：⚠⚠ 「门形同虚设」有两种形态** ——
`need` 类写坏了会**自己红**（CI 能发现）；**`forbid` 类写坏了永远绿**（静默）
⇒ 后者才是真洞 ⇒ 审计器**必须覆盖 forbid 门的正则**。

**⑫ 元教训 3：⚠⚠ 负控的报错可能指向别处** ——
N4 报「变异没生效 ⇒ 门没牙」，**根因却是「门自己写坏了」**
⇒ 顺着报错往下查，能挖出门自己的洞（这条洞就是这么挖出来的）。

**⑬ 元教训 4：⚠⚠ 审计器的盲区不止一处** ——
批 AS 补了「解析失败」（盲区 1），本批补了「正则写法不认」（盲区 2）与
「命中 0 次」（盲区 3）⇒ **审计器自己也要被审**。

**⑭ 遗留（缺口，如实记着）**：
- forbid 门的「零命中」与「正则写坏」在**语义上无法区分**
  ⇒ 只能靠「危险转义」**静态**判定 ⇒ 若有人用**合法但无效**的写法
  （如字符类写错、锚点用错），仍要靠负控/人工发现。
- 「清单里**零使用**的逻辑图标」**没有门**：那需要「清单 × 使用点」的**跨文件**统计，
  静态门做不了 ⇒ 已知缺口（本批实测为 0 个）。

### E.2h 「CI 偶发段错误」：两条旧假设被**实测推翻**，顺带挖出**推送被 SIGPIPE 杀掉**（批 AY）

**① 现象**：2026-10-20 共 **2 次**实测到 —— `ci.sh` 的输出里出现 glibc 的段错误回溯
（栈在 `libQt6Core`），⚠ **而 `ci.sh` 的退出码仍是 0**。
⇒ ⇒ 那个**崩掉的子进程退出码没人看** ⇒ **CI 会误判通过**（这本身就是缺陷，与根因无关）。

**② ⚠⚠⚠ 两条旧假设被实测推翻**（不是猜，是跑了）：
- ❌「**并发**跑导致」⇒ 实测 **3 轮 × 2 个 `ci.sh` 同时跑**
  （输出重定向到文件、**无管道**）⇒ **零复现** ⇒ 并发**不是**根因。
  ⚠ 旧记录里「并发 ⇒ 资源竞争」的推测据此**作废**（README「运行期事实」已订正）。
- ❌「`| tail -N` 的 SIGPIPE 导致」⇒ 实测 **3 轮 `ci.sh | tee | tail -2`** ⇒ **零复现**。
⇒ ⇒ **仍未定位**（2 次都未复现）⇒ 按本仓纪律「**不猜**」⇒ 记为待查，
并写清「下次复现时该做的两件事」：
① **完整输出落盘**（⚠ 那次只看到 `tail -2` 的最后两行 ⇒ **栈被截断** ⇒ 白丢线索）；
② 开 `ulimit -c unlimited` 留 core（⚠ 本机**无 gdb** ⇒ 只能用 `strings core` 看符号）。

**③ ⚠⚠⚠⚠ 顺带挖出的真发现（代价很实在）：`| tail -N` 会把 `git push` 杀掉** ——
推送脚本第一版写的是 `timeout 60 git push origin "$BRANCH" 2>&1 | tail -2`
⇒ **`tail` 读够 2 行就退出** ⇒ `git push` 的 stdout 变成断管 ⇒ **git 收到 SIGPIPE 被杀**
⇒ 推送**中途夭折**。
⚠⚠⚠ **而脚本仍然报「✓ 推送成功」** —— 因为它的判据是 `git ls-remote`，
那一轮恰好读到**推送过程中途**的远端 SHA ⇒ ⇒ **时序上不可靠**：
⚠ **「push 过程中」的状态 ≠ 「push 结束后」的状态**。
⇒ 实测证据：旧脚本跑**几十轮**都没把 `be2280e` 推上去，却**每一轮都报成功**；
去掉管道后**一次就成**（`15448f9..be2280e`），
且我事后用**独立命令** `git ls-remote` 核验 ⇒ 远端**确实**还是旧的 ⇒ **我差点被骗过去**。
⇒ **修法**（已落）：① push 的输出**落盘**（`> "$LOG" 2>&1`）**不接管道**；
② **push 结束后**再独立校验一次（与 push **隔开时序**）。

**④ ⚠⚠⚠ 元教训：「工具报成功」与「结果真的对」是两件事** ——
⇒ 必须用**独立手段**校验（`ls-remote` 而非 push 的退出码），
⚠ 且**校验必须在动作结束之后**（动作进行中读到的状态会骗人）。

**⑤ ⚠⚠⚠ 元教训：`| tail -N` 是「看起来无害、实际会杀人」的写法** ——
它同时坑了**两处**：① 推送（已修）；② 那次段错误的**栈被它截断** ⇒ 丢了唯一的线索。
⇒ 落成**通用纪律**（README「分层纪律」）：**长输出落盘再读**，
`$(cmd | awk ...)` 这种**下游读完全部**的管道是安全的（不会 SIGPIPE）。

**⑥ 本批成果**：**零代码改动**（只落文档 + 修好本地的推送脚本）⇒
门项 **635** 全绿、selfcheck **395/0**、契约门 **120/0**、ci.sh **12/12**、ci-d2 **0/0**、
快照**零变化**、审计器硬门 **rc=0**；远端已核验 == 本地（`be2280e`）。

**⑦ 未做（下批的方向，如实记着）**：
- ⚠ **CI 的「子进程异常退出码」显式检查**（139 = SIGSEGV / 134 = SIGABRT / 141 = SIGPIPE）
  —— 扫描 ci.sh 后**未能定位**具体是哪一步的退出码没被看（23 处候选全是误报或无害）
  ⇒ 需要**下次复现时的完整日志**才能定位 ⇒ 不瞎改。
  ⚠⚠ **本批（批 AZ）已把这句「未能定位」翻案了** ⇒ 见 **E.2i**：定位到了，
  而且**不是**「异常退出码没显式检查」，是**退出码被 `|| true` 整个吞掉**。
- ⚠ **崩点可诊断性**：ci.sh 每步已有 `› N/12 步骤名` 打点 ✔，但**子进程输出没全量落盘**
  ⇒ 崩了只知道「哪一步」不知道「栈在哪」。
  ⚠⚠ **本批（批 AZ）已做** ⇒ 见 **E.2i**。

---

### E.2i CI 的两个**真实检查盲区** + 崩点可诊断性（批 AZ —— 把批 AY「未能定位」的那件事定位了）

**① ⚠⚠⚠ 批 AY 记的「未能定位」，本批定位到了 —— 是 `|| true`，不是管道**

批 AY 记的现象：2026-10-20 共 **2 次**，`ci.sh` 输出里出现 glibc 段错误回溯（栈在 `libQt6Core`），
⚠ **而 `ci.sh` 的退出码仍是 0**。
⇒ 本批**只读勘查**把 ci.sh 逐行扫了一遍，找到**唯一一个**能造成「崩了但退出码 0」的地方：

```
SELFCHECK_OUT="$("$BIN" --selfcheck || true)"      # ← 第 35 行（批 AZ 时的行号）
```

⚠ **机制**：`|| true` 是写在**命令替换内部**的 ⇒ 它把 `$BIN --selfcheck` 的退出码变成 0
⇒ **命令替换整体成功** ⇒ 外层 `set -e` 看不出任何异常 ⇒ 脚本继续往下跑、最后 `exit 0`。
⚠ **而崩掉的时机会决定门放不放行**：
- 崩在汇总行**之前** ⇒ stdout 解析不出 `N passed, M failed` ⇒ 门红（**碰巧**抓到了）；
- **崩在汇总行之后**（stdout 已完整打出 `selfcheck: 395 passed, 0 failed`，随后才段错误）
  ⇒ **解析照样成功** ⇒ **门放行** ⇒ CI 误判通过。
⇒ **批 AY 那两次正好落在后一种** ⇒ 这就是「段错误回栈 + ci.sh 退出码 0」的确切机制。

⚠⚠⚠ **实测复现**（假二进制，不是推测）：写一个「打印完汇总行再 `kill -SEGV`」的假二进制，
把**旧版**第 1 步原样抽出来跑 ⇒ **rc=0（放行）**；把**新版**原样抽出来跑 ⇒ **rc=1（判红）**。
⇒ 这个洞**真的存在过**，不是假想。

**② ⚠⚠⚠ 实测纠正一个想当然的判断：「`| tail -2` 吞退出码」在本仓**不成立****

⚠ 这条纠正很关键：批 AY 的工作笔记里曾把「第 308 行 `| tail -2`」判成「真正的空门」，
本批**实测推翻**（**dash 与 bash 都试过**，本机 `/bin/sh` 就是 dash）：
`ci.sh` 顶部有 `set -euo pipefail` ⇒ `false | tail -2` 会让**整个脚本以 1 退出**
⇒ **管道没有吞退出码**。

⇒ ⇒ **两种「吞退出码」必须分清**（这条已落成通用纪律）：
| 写法 | 退出码 | 为什么 |
|---|---|---|
| `cmd \| tail -2`（管道） | **不吞**（在 `set -o pipefail` 下） | 管道码 = 第一个非 0 的命令码 ⇒ `set -e` 照样退出 |
| `$( cmd \|\| true )`（命令替换内的 `\|\| true`） | **吞** | `\|\| true` 在替换**内部** ⇒ 替换整体成功 ⇒ 外层看不出来 |

⚠ 顺带纠正 `ci-wiring.sh` 的一处**消息失准**（批 AZ 顺带修的）：
门自审计失败时，那一行**只说一种原因**（「新加的门盯的串不唯一」），
可审计器有 **5 种**失败态（2=审计器自己有盲区 / 3=豁免基线外有隐患 / 4=次数门配准失准 /
5=正则写法体检不过或**门项命中 0 次**）⇒ 真实原因不是「串不唯一」时那句话**指错方向**
⇒ 现在**按审计器的退出码说原因**。

**③ ⚠⚠⚠ 盲区 2：agent-selftest 那一门**零断言****

原来是 `"$BIN" --agent-selftest | tail -2` ⇒ **只打两行输出，一句断言都没有**。
⚠ 这里的洞**不是**「退出码被管道吞掉」（见 ②），而是「**退出码之外没有别的断言**」：
退出码只能区分「0=FINAL / 1=ERROR」（`src/main.cpp:68-72`），
**区分不了「链路坏了但恰好返回 0」** —— `src/main.cpp:191-197`：
没有 assistant 消息时 `finalText` 是空串，**仍会**打印 `[selftest] FINAL: ` 并 `return 0`。
⇒ ⇒ agent 链路**整条坏掉**（工具循环断了、模型不回应、进程早退）时，
只要进程退出码是 0，这一门照样绿 ⇒ **CI 判「agent 链路是好的」而它其实坏了**。
⚠ 实测复现：假二进制 `echo "some noise"; exit 0` ⇒ **旧版 rc=0（放行）**、**新版 rc=1（判红）**。

⇒ **改法**（三件事都要查，契约见 `src/main.cpp:68-72`）：
① 退出码 == 0；② stdout 含 `^\[selftest\] FINAL:`；③ stdout 含 `^\[selftest-done\]$`。
⚠ 对位：mac 侧 `macos/Sources/deepDolphin/DeepGitApp.swift:380-384` 同样打这两个标记。

**④ 崩点可诊断性：三件套（下次复现时能查）**

批 AY 的根因**仍未定位**（2 次都未复现；本批又跑了 **600 轮** `--selfcheck` 压测 ⇒ **零复现**）
⇒ 唯一能推进的是「**下次复现时要能查**」：
1. **完整输出落盘**：`selfcheck.out|err`、`agent-selftest.out|err` ⇒ 批 AY 的栈被 `| tail -2` 截断 ⇒ 白丢线索。
2. **core dump 开着**：`ulimit -c 262144` ⇒ 本机**无 gdb**，但 `strings core` 还能看出是哪个库/符号。
   ⚠ **实测**：`core_pattern` 是**相对名** `core`、`core_uses_pid=1` ⇒ 实际文件名是 **`core.<pid>`**
   （实测 `core.1565590`）⇒ core 落在**崩溃进程的 cwd** ⇒ 必须**在专用目录里跑**；
   ⚠ `/proc/sys/kernel/core_pattern` **不可写**（权限不够）⇒ 只能靠 cwd。
   ⚠ 实测单位：`ulimit -c` 在 bash 下是 1024 字节/单位、dash 下是 512 字节/单位
   ⇒ 这个值在两种 shell 下分别是 256MB / 128MB 上限（都够用，也不会撑爆磁盘）。
3. **崩了要说清「哪一步、什么信号、core 在哪、stderr 全文」**：退出码 ≥ 128 ⇒ 显式判红，
   并用 `kill -l` 打出信号名（139=SEGV / 134=ABRT / 141=PIPE）。

⚠⚠ **实测踩到的两个坑（都写在代码注释里了）**：
- ⚠ **`latest_core()` 末尾必须 `|| true`**：「没有 core 时 `ls` 退出码非 0」在 `set -euo pipefail` 下会**反噬**
  —— 命令替换 `_core="$(latest_core)"` 拿到非 0 ⇒ **赋值语句本身失败** ⇒ `set -e` 直接把脚本带走
  （实测 dash/bash 都是 rc=2，**后面那句诊断根本打不出来**）⇒ 「没有 core」必须是**正常分支**。
- ⚠ **`BUILD` 必须绝对化**：一旦 `cd` 进 core 目录，相对路径的 `$BIN` 就找不到了
  ⇒ 用户传 `scripts/ci.sh build` 这种相对路径时自测步直接起不来。

**⑤ 元教训：「崩了」与「门会不会放行」是两件事**

- ⚠ **崩了不一定会被门抓到** —— 崩在**汇总行之后**就抓不到（本文 ①）。
  ⇒ 「门会红」这件事**要按崩溃时机逐种验**，不能靠直觉。
- ⚠ **退出码之外还要有别的断言** —— 退出码只区分「0 / 1」，区分不了「坏了但恰好 0」（本文 ③）。
- ⚠ **判据必须按实测写，不能按想当然写** —— 本文 ② 就是「想当然（管道吞退出码）」被实测推翻的。
  ⇒ 代码注释里已**显式写明这次纠正**，避免下一个人再照着旧结论改。

**⑥ 本批成果**

- 改法：① selfcheck 步 —— 删 `|| true`、退出码单独收、**信号退出显式判红** + 打信号名 + 打 core 路径 + 打 stderr 全文；
  ② agent-selftest 步 —— **三断言** + 同样崩点可诊断；③ 两步都在 **`build/crash/` 专用目录**里跑（core 有归处）；
  ④ `BUILD` 绝对化；⑤ `.gitignore` 加**锚定**的 `core.*` 规则（⚠ **不许写无锚定的 `core.*`** ——
  那会把将来的 `src/core.cpp` 这类真源码静默忽略掉；仓里也已有 `linux/vendor/CangjieGUI/src/core` 同名目录）；
  ⑥ `ci-wiring.sh` 门自审计失败消息**按退出码说原因**。
- **门项 647**（635 → **+12**，新增「批 AZ 段」）、**负控 15/15 真红**
  （11 条静态负控 + 4 条行为负控；累计 **197/197**）。
- 其余基线：selfcheck **395/0**、契约门 **120/0**、ci.sh **12/12**、ci-d2 **0/0**、
  快照**零变化**、审计器硬门 **rc=0**。

**⑦ 边界（没做 / 做不到的，如实记着）**

- ⚠ **core 只覆盖自测两步**（selfcheck / agent-selftest）。快照与探针那几步**崩了必红**
  （它们都有 `if !` 判退出码 ⇒ 非 0 即退出）⇒ **不会误判通过**，只是**没有 core 可查**；
  它们的 stderr 早已落盘并原样打出（批 AN 做的）⇒ 栈能拿到。
  ⇒ 不给它们套 CRASH_DIR：改了它们的 cwd 得**重验 8 张快照的逐字节基线**，
  而它们崩了本来就不会放行 ⇒ 收益不抵风险。
- ⚠ **崩溃本身的成因仍未定位**（2 次未复现 + 600 轮压测零复现）⇒ 本批的进展是
  **把「误判通过的机制」定位并修掉**，让**下次复现能查**（core + 完整日志 + 信号名），
  **不是**把崩溃本身修好了。
- ⚠ 本机**无 gdb** ⇒ core 只能用 `strings` 看符号 ⇒ 拿到 core 后的深度定位仍需真机/带调试器的环境。

---

### E.2j CI 的**每一步**都必须有门（批 BA —— 门自己被删了，门还是绿的）

**① ⚠⚠⚠ 起因：批 AZ 给 ci.sh 的**内部**加了门，但「ci.sh 一共有哪 12 步」这件事本身没有门**

⇒ 即：**CI 清单上写着 12 步，少做一步却没有任何信号。**
⇒ 这是「承诺没有门 = 承诺不存在」在**清单层面**的形态 —— 前面的门盯的是「某件事做没做」，
这一批盯的是「**这件事清单本身**」。

**② ⚠⚠⚠ 实测取证（不是推演）**

写脚本**逐个删掉** ci.sh 的 12 步，每删一步跑一遍接线门 + 审计器 ⇒
**12 步里有 6 步删了门照样全绿**：

| 删掉的步 | 门 |
|---|---|
| 1 selfcheck / 2 截图矩阵 / 4 无头探针 / 5 D2 / 6 agent 自测 / 11 deb 打包 | 🔴 红 |
| **3 desktop/metainfo 校验** | 🟢 **全绿** |
| **7 verify 接线扫描** | 🟢 **全绿** |
| **8 图谱 Canvas 契约清单** | 🟢 **全绿** |
| **9 接线门** | 🟢 **全绿** |
| **10 引擎契约门** | 🟢 **全绿** |
| **12 deb 布局验收** | 🟢 **全绿** |

⚠⚠⚠ **最刺眼的是第 9 步**：把「接线门」这一步从 ci.sh 里删掉，**门还是绿的**
⇒ **门把自己的存在也丢了，没人管。**
⚠⚠ **另外 6 步之所以被抓住，是「别的段落的门恰好盯到了它们的串」** ——
那是**偶然**，不是「每一步都有门」：哪天那几条门改了写法，这 6 步立刻变成没人管。

**③ 修法：每一步一个「全文件唯一」的专属门**

12 条 `arch_need_count`（各 **恰好 1 次**）—— 每一步挑一个**只出现在那一步里**的串：

| 步 | 专属串 | 步 | 专属串 |
|---|---|---|---|
| 1 selfcheck | `--selfcheck` | 7 verify 接线扫描 | `QStringLiteral\("verify"\)` |
| 2 截图矩阵 | `--color-sample` | 8 Canvas 契约清单 | `CANVAS_METHODS=` |
| 3 desktop/metainfo | `cn.deepdolphin.app.desktop` | 9 **接线门** | `scripts/ci-wiring.sh` |
| 4 无头探针 | `ci-platform-probe.sh` | 10 引擎契约门 | `contract-check.sh` |
| 5 D2 散值门 | `ci-d2.sh` | 11 deb 打包 | `build-deb.sh` |
| 6 agent 自测 | `--agent-selftest` | 12 deb 布局验收 | `check-deb-layout.sh` |

外加 2 条清单层面的门：**步骤打点恰好 12 个**（多一步/少一步/散写分母都红）
+ **编号 1..12 连续**（压行后匹配 ⇒ 跳号/重号/乱序都红）。

⚠ **串的选择口径**（批 AP/AQ/AR/AS/AX 连续六次同形状的纪律）：
必须**只出现在那一步里**（全文件命中数 == 本步内命中数），否则会被**别处顶替**。

**④ ⚠⚠ 已知边界（如实记着，本批不做）**

本段保证的是「**这一步还在**」，**不**保证「这一步的代码没被挪到别处」——
把那个串挪到别的步里，命中数仍是 1 ⇒ **门不红**。
⚠ 要更强的保证，得让门**认识步骤边界**（按 `› N/12` 打点切出每一步的正文再找标记）
⇒ 那是一个**新门型** ⇒ 审计器也要跟着扩（批 AR 的纪律：「审计器自己有盲区 ⇒ 那些门根本没被审」）
⇒ 本批**不扩**，**如实记为已知边界**。

**⑤ ⚠ 顺带修回一个我自己造成的回归**

批 AZ 加「批 AZ 段」时，把**批 AX 段自己的收尾块**顶掉了 ⇒ 日志少了「✓ 批 AX 段门项全绿」那行
⇒ 本批**修回**（按批 X / 批 Y 的结构；⚠ 那里**不能带末尾的 `exit 0`** ——
原批 AX 段是最后一段才带，后面还有段 ⇒ 带了就把后面的段跳过）。

**⑥ ⚠⚠ 元教训**

- ⚠ **「门自己被删了」是这类洞的极端形态** —— 门能证明「源码里的接线在不在」，
  却证明不了「**门自己**在不在」⇒ 清单本身必须被当成一件**要被门守的事**。
- ⚠ **「别的门恰好盯到了」不是保护，是偶然** —— 保护必须是**有意的**、指向那件事的。
- ⚠ **「少做一件事」比「做错一件事」更难被发现** —— 做错了会红，少做了没人知道。

**⑦ 本批成果**

- 门项 647 → **661**（**+14**：12 条 per-step + 总数门 + 编号连续门）；批 AX 段收尾块修回。
- **负控 14/14 真红**：**12 步逐个删**（每删一步 ⇒ 门红 **且** 目标串命中数 1 → 0）
  + 2 例清单层面变异（**步骤编号乱序**、**多加一步**）⇒ 累计 **211/211**。
- 其余基线：selfcheck **395/0**、契约门 **120/0**、ci.sh **12/12**、ci-d2 **0/0**、
  快照**零变化**、审计器硬门 **rc=0**。
- **零产品代码改动**（只动 `ci-wiring.sh` 与文档）。

**⑧ 顺带：批 AY 那个段错误的取证进度**

本批又跑了 **2000 轮 × 16 并发**的 `--selfcheck` 压测 ⇒ **异常退出 0 次**
（连同批 AY 的 600 轮 ⇒ 共 **2600 轮零复现**）⇒ **崩溃成因仍未定位**，
按纪律**不猜**；批 AZ 的三件套（core + 完整日志 + 信号名）让**下次复现能查**。

---

### E.2k 「判据不许被删」这条承诺**当时是假的**（批 BB —— 余量 2 条，且注释把方向写反了）

**① 起因**：批 AZ 的取证让本批去查 ci.sh 里的其它「基线数字」⇒ 撞上一个**正在失守**的承诺。

**② ⚠⚠⚠ 实测取证（修前，负控跑出来的）**

- `SC_MIN=393` 而实际判据数 **395** ⇒ **余量 = 2** ⇒ **可以删 2 条判据，门照样绿**。
- ⚠⚠⚠ **行为负控实测**：删掉 1 条判据 ⇒ 第 1 步**真实门 rc=0（绿）**；
  加 1 条判据 ⇒ 也绿（基线与实际已脱钩）。
- ⇒ 「判据只许增不许减 ⇒ 有判据被删了 ⇒ 红」（批 AJ 立的门）**当时是假的**。

**③ ⚠⚠⚠ 为什么会有余量：判定写的是「不少于」**

批 AJ 立的门是 `if [ "$SC_PASSED" -lt "$SC_MIN" ]` ⇒ **只要不少于基线就算过**
⇒ **余量 = 基线与实际判据数之差**，而那个差**没人盯**。
批 AJ 时基线 393 = 实际 393（严丝合缝）⇒ 此后**加了 2 条判据**（393 → 395）
而**基线没跟着加** ⇒ 余量变成 **2** ⇒ 洞就是这么来的。

**④ ⚠⚠⚠ 原注释把方向写反了（同一句错在四处）**

原话：「加判据时同步把 `SC_MIN` 加一（忘了加只是门**偏严**，不会偏**松** ⇒ 安全方向）」。
⚠ **恰恰相反**：门是「不少于」时，忘了加 ⇒ 基线**落后**于实际 ⇒ **门偏松**
⇒ **正是不安全的那一侧**。
⚠ 同一句错在 **ci.sh 的注释**、**台账 E.1s**、**PLAN §10（两个变体）** ⇒ 本批一并订正。

**⑤ 修法：判定改成「完全相等」⇒ 余量恒为 0**

- `if [ "$SC_PASSED" -ne "$SC_MIN" ]` ⇒ 加判据忘了同步 ⇒ **红**；删判据 ⇒ **红**；基线被调小 ⇒ **红**。
- `SC_MIN` 393 → **395**（补上欠的 2 条）。
- ⚠ 代价明写（别当成 surprise）：**每次加判据要同步改 `SC_MIN`**
  —— 这正是「承诺要有牙」的成本；批 AJ 当年也是这个成本，**只是它把方向写反了**。

**⑥ 落门（批 BB 段，3 条）**

| 门 | 盯什么 | 挡住的退化 |
|---|---|---|
| `arch_need_count 'SC_PASSED" -ne "\$SC_MIN' 1` | 判定形式 | 改回 `-lt` ⇒ 余量又回来 |
| `arch_need_count 'SC_MIN=[0-9]+' 1` | 基线有且只有一处 | 基线散在两处 ⇒ 改一处就废掉另一处 |
| `arch_need_count 'SC_FAILED" -ne 0' 1` | failed 恒为 0 | 牙不在了还装作在 |

⚠ **顺带**：删掉了批 AJ 段那条盯**错误消息文案**的门（「有判据被删了」）
⇒ **改个措辞就断**（脆）⇒ 改成盯**判定本身**。
⚠⚠ **这次断裂是被审计器的「命中 0 ⇒ 红」当场抓到的**（批 AX 建的那道防静默失效的门在干活 ✔）。

**⑦ 负控 5/5（累计 216/216）**

| 例 | 变异 | 该红的门 |
|---|---|---|
| A1 | 把「必须相等」改回「小于」 | 接线门（静态） |
| A2 | 把 `SC_MIN` 调小 1 | 第 1 步（运行期） |
| A3 | 把整条基线检查删掉 | 接线门（静态） |
| B1 | 删掉 1 条判据（**要编译**） | 第 1 步（运行期） |
| B2 | 加 1 条判据（**要编译**） | 第 1 步（运行期） |

⚠ **负控脚本自己也踩过一个坑（记下来）**：第 1 步的抽取脚本里**烘焙了 `SC_MIN` 的值**
⇒ 负控跑的是**旧抽取物** ⇒ A2 假绿（rc=0）⇒ 改成「每次从当前 ci.sh 重新抽取」才真红。
⚠ **教训**：负控跑的是**抽取物**时，抽取物必须在**每次运行前重建**（否则测的是旧判据）。

**⑧ ⚠⚠ 元教训**

- ⚠⚠ **「不少于」型基线天生带余量** ⇒ 余量 = 基线与实际的差 ⇒ **差没人盯** ⇒ 天生可被悄悄删。
  ⇒ **要「不许减」这个承诺有牙，基线判定必须用「完全相等」。**
- ⚠⚠ **注释里的「安全方向」判断必须能被实测推翻** —— 本批就是靠**实测**发现注释写反了。
  ⇒ 「凭直觉论证方向」与「凭印象判断工具行为」是同一类错误（批 AX 已记过后者）。
- ⚠⚠ **门盯错误消息文案 ⇒ 改个措辞就断** ⇒ 门要盯**判定本身**。
- ⚠⚠ **基线类承诺要定期重算「基线 vs 实际」** —— 本批的洞就是这么攒出来的
  （两次加判据、两次没加基线 ⇒ 余量 2）。

**⑨ 本批成果**

- 门项 660 → **663**（**+3**）；selfcheck **395/0**、契约门 **120/0**、ci.sh **12/12**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**。
- **零产品代码改动**（只动 `ci.sh` / `ci-wiring.sh` 与文档）。

**⑩ 遗留（如实记着）**

- ⚠ **契约门 `contract-check.sh` 没有条数基线** ⇒ 那 120 条断言可以被悄悄删。
  ⚠ **不能照抄 SC_MIN 的口径**：契约门有**随环境变化的 SKIP 分支**
  （找不到客户端二进制 ⇒ 第 12/18 组 SKIP）⇒ 条数会变 ⇒ 只能用**下限**（floor）⇒ 强度不同
  ⇒ 需另想口径 ⇒ **本批不做**，记为待办。
- ⚠ **判据数基线只管「条数」** ⇒ 抓不到「删一条又加一条」的换名操作（批 AJ 已记，本批沿用）。

---

### E.2l CI 里跑的**每个断言脚本**，它的断言清单都要有门（批 BC）

**① 起因**：批 BB 修完 selfcheck 的判据基线，顺手查了别的脚本 ⇒ 撞出同一族的洞。

**② ⚠⚠⚠ 实测取证：CI 里跑的 5 个断言脚本，有 2 个一条门都没有**

CI 实际会跑的断言脚本是这 5 个（`build-deb.sh` 靠**依赖清单双向校验**顶住，已被门覆盖）：

| 脚本 | 断言条数 | 修前有几条门盯它的清单 |
|---|---|---|
| `contract-check.sh` | **120 条真引擎断言**（93 处 `check` 调用，部分在循环里） | **0 条** ⚠ |
| `check-deb-layout.sh` | 10 条验收（14 处 `ok`/`no` 调用） | **0 条** ⚠ |
| `ci-platform-probe.sh` | 20 条断言 | 只盯了 3 条（批 AX/AW 段） |
| `ci-docs-lang-probe.sh` | 10 条断言 | 只盯了 2 条（批 AA 段） |
| `ci-divider-probe.sh` | 9 条断言 | 只盯了 3 条（批 AW 段） |

⇒ **删掉 `contract-check.sh` 里的任意一条断言 ⇒ 没有任何门会红**
⇒ 契约门被悄悄削弱（少了几条真引擎断言）**无人知晓**。

**③ 修法：每个脚本一条「断言清单不许被删」的条数基线门（5 条）**

⚠⚠ **每个脚本的可数口径不同，别混用**（实测）：

| 脚本 | 口径 | 命中数 | ⚠ 为什么不能用别的口径 |
|---|---|---|---|
| `contract-check.sh` | `^[[:space:]]*check `（**调用点**） | 93 | ⚠ **不能用「✗ 数」**：它的 `check()` 函数体内只有**一条**报错语句 ⇒ ✗ 数 = 133 ≠ 断言数 |
| `check-deb-layout.sh` | `^[[:space:]]*(no\|ok) "` | 14 | — |
| 三个探针脚本 | **报错行数**（`✗ `） | 20 / 10 / 9 | 每条断言失败时打一条 `✗` ⇒ 数 = 断言数 |

⚠ **契约门为什么只能钉静态调用数**：它有**随环境变化的 SKIP 分支**
（找不到客户端二进制 ⇒ 第 12/18 组 SKIP）⇒ **运行期条数会变** ⇒ 钉运行期数会误报。
⇒ 静态调用数是**与环境无关**的代理量 ⇒ 删一条调用 ⇒ 门红 ✓。

**④ 负控 5/5（累计 221/221）**

每个脚本**删掉一条断言** ⇒ 对应门必须红 **且** 目标串命中数减少：
`contract-check.sh` 93→92、`check-deb-layout.sh` 14→13、
`ci-platform-probe.sh` 20→19、`ci-docs-lang-probe.sh` 10→9、`ci-divider-probe.sh` 9→8。

**⑤ ⚠⚠ 已知边界（如实记着）**

条数基线只挡「**删断言**」，挡不住「**把断言掏空成恒真**」
（把断言的判定表达式改成恒真 ⇒ 条数不变 ⇒ 门不红）。
⇒ 那要**逐条钉住断言的表达式**，成本远高于收益 ⇒ **本批不做**，记为待办。
⚠ 同款边界：批 BA 的 per-step 门挡不住「把标记串挪到别处」。

**⑥ 本批成果**

- 门项 663 → **668**（**+5**）；selfcheck **395/0**、契约门 **120/0**、ci.sh **12/12**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**。
- **零产品代码改动**（只动 `ci-wiring.sh` 与文档）。

**⑦ ⚠ 元教训**

- ⚠⚠ **同一族的洞要一次扫干净**：批 BB 撞出「判据基线有余量」，顺着查就撞出
  「**别的断言脚本一条门都没有**」⇒ **别修一个就停**。
- ⚠⚠ **「清单不许被删」这件事，每个带清单的脚本都要单独有门** ——
  判据（selfcheck）、契约断言、探针断言、deb 验收断言 ⇒ **四种不同的清单，四种不同的口径**。
- ⚠⚠ **可数口径必须逐脚本实测**：同一个脚本里「报错条数」与「断言条数」就可能不等
  （`contract-check.sh`：133 vs 93）⇒ 照抄别处的口径会钉错数。


### E.2m 断言脚本不许游离在 CI 之外（批 BD —— 「少了一份断言」此前不可能被任何人发现）

**① 起因**：批 BC 给「CI 里跑的脚本」加了断言清单的条数基线门，顺手查「CI 到底跑了哪些脚本」⇒ 撞出同一族的洞，而且是**最后一块**。

**② ⚠⚠⚠ 实测取证：把一份断言脚本整个删掉，门与审计器**双双全绿**

`scripts/probe-agent-tool-surface.sh`（批 AB 写的 agent 工具面收敛断言，**9 条断言**）**根本不在 CI 里**。

| 变异 | 接线门 | 审计器 |
|---|---|---|
| **删掉 `probe-agent-tool-surface.sh` 整个文件** | **rc=0（绿）** ⚠ | **rc=0（绿）** ⚠ |
| 删掉 ci.sh 里 `ci-docs-lang-probe.sh` 的调用 | rc=1（红） | rc=5（红） |
| 删掉 ci.sh 里 `ci-divider-probe.sh` 的调用 | rc=1（红） | rc=5（红） |
| 删掉 ci.sh 里 `ci-platform-probe.sh` 的调用 | rc=1（红） | rc=4（红） |
| 删掉 `ci-docs-lang-probe.sh` 整个文件 | rc=1（红） | rc=5（红） |
| 删掉 `ci-divider-probe.sh` 整个文件 | rc=1（红） | rc=5（红） |

⇒ **对照实测把洞的位置钉死了**：洞**不在**「已接管的脚本」（删它们是红的），**在**「**没人接管的**」。
⇒ 而「没人接管」这一类，以前**连一条门都没有** ⇒ **仓库里少了一份断言，没有任何门会说一个字**。

**③ 修法：两头都堵**

① **接进 CI**（`ci.sh` 第 13 步）：`probe-agent-tool-surface.sh` 从此有人执行 ——
它的 9 条断言是「引擎标的废弃别名**不得**出现在模型可见面/系统提示词里，
但**仍要留在必填校验表**里」（收敛的是「推荐谁」，不是「还能不能用」）。
⚠ 退出码语义：0=通过 / 1=失败 / 2=用法错 / **3=SKIP**（引擎缺席或 < 0.2.0 ⇒ **未验证，不算通过**）。
⚠⚠ **别写成 `if ! cmd; then $?`**：`!` 会把退出码**取反** ⇒ then 分支里的 `$?` 恒为 0 ⇒
分不清「SKIP」和「失败」⇒ 必须先原样收下退出码。

② **从「集合」这一层堵**（`ci.sh` 第 14 步 + 新脚本 `scripts/ci-orphan-probe.sh`）：
`scripts/` 下**每个断言脚本**，要么在 CI 里**可达**（ci.sh 直接调用，或被 CI 可达的脚本调用 ⇒ 传递闭包），
要么在**带理由的白名单**里；白名单条目**必须确实不可达**（不许把已在 CI 里的脚本塞进白名单走后门）。

**④ 口径（实测，不是猜）**

| 口径 | 取值 | 依据 |
|---|---|---|
| 「什么算断言脚本」 | 文件里**含报错标记行** | 实测：build.sh / build-system.sh / dev-run.sh / setup-deps.sh / bootstrap-deps.py 都是 0 条 ⇒ 不做断言 |
| 「可达」 | **真调用点**（`sh "$SRC/scripts/x.sh"`），传递闭包 | ⚠ 不能用「文件名出现过」：实测 `scripts/ci.sh` 在 ci.sh 里出现 3 次，全是注释/用法说明 ⇒ 会把 ci.sh 误判成「自己调用了自己」 |
| 「门项行不算调用点」 | 排除 `arch_*` 开头的行 | ⚠ ci-wiring.sh 里 `arch_need ... 'sh "\$SRC/scripts/ci-d2\.sh"' …` 这类**门项字符串**长得像调用 ⇒ 不排除就会把门架空 |
| 白名单 | 4 条：`ci.sh` / `smoke.sh` / `probe-deepin-tray.sh` / `probe-sni-icon.sh` | 前两个是入口（入口不调用自己；smoke.sh 是本地冒烟入口），后两个**需真机**（图形会话 + deepin 托盘 daemon / 会话总线） |

**⑤ 落门（批 BD 段 9 条 + 批 BA 段 +2）**

- 批 BA 段：ci.sh **12 步 → 14 步**（新增两条 per-step 门 + 步骤打点基线 12→14 + 编号连续门）。
  ⚠ **两条新门盯的是「调用点」那串**（`sh "$SRC/scripts/…"`），**不是文件名** ——
  文件名在 ci.sh 的**注释**里也出现过（讲这个洞的来由）⇒ 盯短名会命中 2 次而恒红。
- 批 BD 段 9 条：探针自己的断言清单（7）/ 「什么算断言脚本」的判定行（1）/「排除门项行」的规则（1）/
  白名单条数基线（4 条，**完全相等** ⇒ 余量恒为 0）/ 白名单条目**不许被 CI 调用**（4 条，期望 0 次）/
  agent 工具面探针的断言清单基线（9 条）。
  ⚠⚠ **最后那一条是「文件被整个删掉」的唯一防线**：无游离门扫的是**目录里现存的文件** ⇒
  文件没了它就**扫不到**、也就不会报 ⇒ 必须另有一条盯文件本身的条数基线门（删文件 ⇒ 门报「文件不存在」⇒ 红）。
  ⚠⚠ **探针自己的「判定行」也要有门**：少了「什么算断言脚本」那行 ⇒ 探针扫到 0 个 ⇒
  报「0 个断言脚本，全部可达」⇒ **空转恒绿**（与批 BC 记的已知边界同形状）。

**⑥ 判据**

- 门项 668 → **679**（**+11**）；selfcheck **395/0**、契约门 **120/0**、ci.sh **14/14**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**。
- **负控 14/14 真红**（累计 **235/235**）。
- **零产品代码改动**（只动 `ci.sh` / `ci-wiring.sh` / 新增 `ci-orphan-probe.sh` 与文档）。

**⑦ ⚠ 元教训**

- ⚠⚠ **「多了一份没人跑的断言」和「少了一份断言」是同一个洞的两头** —— 前者浪费，后者**悄悄失效**；
  两者都只有从**集合**这一层看才看得出来 ⇒ 逐个脚本盯（「它有门吗」）永远盯不到「**它压根没被跑**」。
- ⚠⚠ **门只能盯「还在的文件」** ⇒ 「文件被删」这件事**必须另有一条门**（盯文件本身的条数基线），
  否则新加的「集合门」会给人**虚假的安心感**。
- ⚠⚠ **白名单是后门** ⇒ 白名单条目必须「**确实不可达**」（否则等于给某个脚本开了随时能溜走的后门）
  ⇒ 且白名单**条数**要有**完全相等**的基线（批 BB 口径）⇒ 增删必须显式。
- ⚠⚠ **「以为某个工具认不认某种写法」必须实测** —— 本批开工时我**以为**「第 4 步里另两个探针没有
  per-step 门 ⇒ 删掉它们的调用没人管」⇒ **实测被前段的门抓住**（rc=1）⇒ 假设被推翻。
- ⚠ **负控脚本自己也要有备份式还原** —— 本批第一版勘查脚本只备份了 2 个文件，
  却在「删文件」类 case 里删了另外 2 个 ⇒ **勘查脚本把自己的工作区弄坏了**
  ⇒ 还原函数必须覆盖**所有**会被删的文件（`git checkout` 也不能用在本仓的负控里）。

### E.2n per-step 门要认识**步骤边界**（批 BE —— 「标记串被挪到别的步」此前抓不到）

**① 起因**：批 BA 立了 12 条 per-step 门（批 BD 扩到 14 条），批 BA 当时把一个边界**如实记着**：「本段保证『这一步还在』，**不**保证『这一步的代码没被挪走』」⇒ 本批把它补上。

**② ⚠⚠⚠ 实测取证（修前）**：把第 8 步的标记串 `CANVAS_METHODS=` **整行挪到第 12 步**

| 变异 | 接线门 | 审计器 |
|---|---|---|
| **把 `CANVAS_METHODS=` 从第 8 步挪到第 12 步** | **rc=0（绿）** ⚠ | rc=0（绿）⚠ |

⇒ 命中数**仍是 1**（文件级门盯的是「全文件恰好 1 次」）⇒ 门只证明了「**这个串还在**」，
**没证明「它还在这一步里**」⇒ **CI 可以悄悄少做第 8 步的事**（Canvas 契约清单检查）而无人知晓。

**③ 修法：新门型 `arch_need_count_in_step`**

| 项 | 取值 | 依据 |
|---|---|---|
| 切段口径 | 打点行 `^echo "› N/M ` | 实测 ci.sh 里**恰好 14 行**命中；⚠ **宽松写法会误匹配**（`^echo "[^"]*[0-9]+/[0-9]+ ` 会把 `echo "普通行 3/4 不是打点"` 也算进去）⇒ 必须紧锚定 `› ` |
| 第 N 步正文 | 从第 N 个打点行开始，到下一个打点行之前 | — |
| 注释 | 沿用 `strip_comments`（对 `.sh` 剥**整行** `#` 注释） | 与既有门型同口径，审计器同一条命令 ⇒ 零漂移 |
| awk | **mawk 1.3.4**（实测认得多字节 `›` 的正则与 `sub`） | 本机实测，不靠记忆 |

⚠ **与已有的文件级门互补，两个都要**：
文件级「恰好 1 次」⇒ 抓「被**复制**到别处」；步内「恰好 1 次」⇒ 抓「被**挪**到别处」。

**④ ⚠⚠ 新门型 ⇒ 审计器必须跟着扩**（批 AR/AV 纪律：「审计器自己有盲区 ⇒ 那些门**根本没被审**」）

- `ci-wiring-audit.py` 新增 `arch_need_count_in_step` 的解析 + **配准校准**
  （期望次数必须 == **该步正文里**的实际命中数 ⇒ 「把期望从 1 改成 2 来躲变异」也躲不掉）；
- ⚠ **切段用的 awk 是从 `ci-wiring.sh` 原文抽取**的（不是复刻）⇒ 门侧改口径，审计侧自动跟着变；
- ⚠ **顺带补上一个审计器盲区**：`ANY_NEED_LINE`（`arch_need\b`）**匹配不到 count 族**
  （`_` 是单词字符 ⇒ 没有词边界）⇒ 以前一条**写坏**的 `arch_need_count*` 门项会**静默被忽略**
  ⇒ 没人知道它没被审 ⇒ 新增 **count 族兜底盲区检测**（解析不到 ⇒ 记成盲区 ⇒ 硬门红，退出码 2）。

**⑤ 落门（批 BE 段 14 条）**

ci.sh 的 14 个步骤各一条「标记串**还在这一步里**」；⚠ 两条新门（13/14 步）盯的仍是
「**调用点**」那串（`sh "$SRC/scripts/…"`），**不是文件名** —— 文件名在 ci.sh 注释里也出现过
（讲那个洞的来由）⇒ 盯短名会命中 2 次而恒红。

**⑥ 判据**

- 门项 679 → **693**（**+14**）；selfcheck **395/0**、契约门 **120/0**、ci.sh **14/14**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**。
- **负控 17/17 真红**（累计 **252/252**）。
- **零产品代码改动**（只动 `ci-wiring.sh` / `ci-wiring-audit.py` 与文档）。

**⑦ ⚠ 元教训**

- ⚠⚠ **「这一项还在」与「这一项还在**该在的地方**」是两件事** —— 文件级门型天生看不见后者
  ⇒ 门要盯**位置**时，就必须让门**认识位置的结构**（这里是：打点行切出来的步骤边界）。
- ⚠⚠ **新门型必须同步扩审计器** —— 否则新门型**自己就是盲区**（批 AR 早就说过这条）。
- ⚠⚠ **审计器自己的盲区也要清**：`ANY_NEED_LINE` 匹配不到 count 族 ⇒ 写坏的 count 门项
  **静默被忽略** ⇒ 「没人知道它没被审」⇒ 本批补了兜底。
- ⚠⚠ **负控自己也会写错，且写错时是「假红」** —— 本批第一版负控 0/17：
  ① 「before 命中数」在**变异之后**才测（批 BB 踩过的同款坑）；
  ② 审计器**无参模式只出报告、退出码恒 0** ⇒ 判红必须用**硬门模式 `--list`**；
  ③ 完整接线门里**审计器先跑** ⇒ 审计器一红就 exit ⇒ 后面 批 BE 段的门项**根本没执行**
  ⇒ 负控改为**单独跑门函数**（每次现抽）来证明「新门型自己能抓住挪位」。
### E.2o 判据不许被「掏空成恒真」（批 BF —— 条数基线门抓不到的那一类）

**① 起因**：批 BC 留下的已知边界之一：「**条数基线只挡『删断言』，挡不住『把断言掏空成恒真』**」
（把判定表达式改成恒真 ⇒ 条数不变 ⇒ 门不红）⇒ 本批把它补上。

**② ⚠⚠⚠ 实测取证（修前）：掏空一条判据 ⇒ 全绿**

变异：`check(log, "快照夹具：每个项目的「N 天前提交」被钉死…", ok);` ⇒ `…, true);`

| 观测 | 结果 |
|---|---|
| selfcheck | **395 passed, 0 failed**（判据**条数没变**） |
| 批 BB 的「判据数 == `SC_MIN`(395)」判定 | **不红**（它只看条数） |
| 接线门 | **rc=0（全绿）** |
| ⇒ 结论 | 那条判据**从此永远不会红** ⇒ 判据被悄悄削弱**无人知晓** |

**③ 修法：新增 `scripts/ci-tautology-check.py`（`ci.sh` 第 15 步，ci.sh 14 → 15 步）**

| 面 | 规则 | 抓什么 |
|---|---|---|
| 判定层 C++（`src/app/SelfCheck*.cpp`） | `check(…)` 的**条件**里，去掉字面量与关键字后**至少剩一个被测标识符** | `true` / `false` / `1 == 1` / `"a" == "a"` |
| 同上 | 条件**不许**含「捷径」`\|\| true` / `&& false` / `or true` / `and false` | 条件里带恒真项 ⇒ 整条判据被短路 |
| shell 断言脚本（`scripts/*.sh`） | `if` 的条件**不许**是 `true` / `false` / `:` | `if true; then` 掏空 |
| python 工具脚本（`scripts/*.py`） | `if True:` / `if False:` / `if 1:` 这类恒真条件 | 同上（python 侧） |

⚠ **口径（实测，不是猜）**：
- 抽 `check(…)` 的第三个参数用**括号配平**，**不用正则猜** —— 条件里可能有逗号、嵌套括号、
  字符串里的逗号 ⇒ 正则会抽错。
- 「恒真」的判据是「**至少有一个被测标识符**」，**不是**「不许出现 `true`」——
  后者只能抓最浅的手改形态，抓不到 `1 == 1`。
- ⚠ **基线实测零误报**：判定层 396 条判据 + shell/python 271 个 `if` 条件，**今天全部合规**。

**④ ⚠⚠ 门自己证明自己有牙（这批的另一半价值）**

探针**自带自检**：每次运行先拿 **9 条合成样例**跑一遍自己的判定逻辑
（**既含「该判为恒真」也含「不该判为恒真」的样例** ⇒ 只测一边 ⇒ 判反了也能过）
⇒ 判定逻辑被掏空 ⇒ 探针**当场报「自检失败」并判红**。

⇒ 这是**比静态门更硬的保证**：静态门只能盯「那行代码在不在」，
自检盯的是「**那行代码判得对不对**」。

**⑤ 落门（批 BF 段 11 条 + 批 BA/BB 段各 +1）**

批 BF 段的 11 条全部是「**门自己不许被掏空**」：
统一判定入口在 / 实扫走同一条路径 / 四条判定规则在 / 自检在 / 自检失败判红 /
**自检样例表 9 条不许被掏空** / 判定层范围单一出处 / 「违规 ⇒ 判红」在。

⚠⚠ **实测踩到并修掉的一个坑**：探针最初把「恒真」判定写成布尔返回，
调用方为出报告**又算了一遍** ⇒ 那个判定表达式在文件里出现**两次**
⇒ 门按「恰好 1 次」钉它 ⇒ **审计器立刻报配准失准**（期望 1 ≠ 实际 2）。
⇒ 改成「判定函数**返回原因**」⇒ 只算一次 ⇒ 口径不漂。
⇒ **这是批 BB 口径（期望 == 实际，余量恒为 0）又一次在干活。**

**⑥ 判据**

- 门项 693 → **706**（**+13**）；selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**。
- **负控 10/10 真红**（累计 **262/262**）：3 例行为类（要编译、跑完重编译恢复）
  + 7 例静态类。
- **零产品代码改动**（只动 `ci.sh` / `ci-wiring.sh` / 新增 `ci-tautology-check.py` 与文档）。

**⑦ ⚠ 元教训**

- ⚠⚠ **「条数不变」不等于「判据没变」** —— 条数基线门只保证「**没少**」，
  不保证「**没被掏空**」⇒ 两者必须**各有一道门**。
- ⚠⚠ **门自己证明自己有牙，比门盯着门更硬** —— 静态门盯「代码在不在」，
  **自检**盯「代码判得对不对」⇒ 两者互补。
- ⚠⚠ **判定逻辑只能有一份** —— 调用方再算一遍 ⇒ 两份判定迟早漂
  （本批是审计器的配准校准当场抓住的）。
- ⚠⚠ **判据的「形状」也要有门** —— 本批测的是**判据条件**的形状（恒真/捷径），
  而不只是**判据条数**。
- ⚠ **已知边界（如实记着）**：本门抓的是**语法层**的恒真（`true` / `1 == 1` / `|| true`）；
  「条件本身合法但恒真」的情形（例如 `ok` 恰好是个恒真的局部变量）**静态分析抓不到**
  ⇒ 那要靠**变异测试**（把被测实现改坏 ⇒ 相应判据必须变红）⇒ 成本高，本批不做。

### E.2p 断言函数**实参里**的判据也不许恒真（批 BG —— 批 BF 够不着的那一类）

**① 起因**：批 BF 把「判据掏空成恒真」管住了（判定层 C++ 的 `check(…)` **条件**
+ shell 脚本的 `if` **条件** + python 脚本的 `if`）
⇒ ⚠⚠⚠ **但契约门的判据根本不在 `if` 条件里** —— 它的形态是：

```
check      <名称> <python表达式（stdin 为 JSON 文本）> [json]
check_text <名称> <ERE> <文本>
```

⇒ **判据就藏在第二个实参里** ⇒ 批 BF 的三类扫描**一条都够不着**。

**② ⚠⚠⚠ 实测取证（修前）：掏空一条契约门判据 ⇒ 全绿**

变异：把其中一条 `check` 的 python 表达式掏空成 `True` ⇒

| 观测 | 结果 |
|---|---|
| 契约门 | **120 passed, 0 failed**（rc=0） |
| 批 BC 的「93 处 `check` 调用不许被删」 | **不红**（调用点数没变） |
| 接线门 | **rc=0（全绿）** |
| ⇒ 结论 | 那条断言**从此永远不会红** ⇒ 判据被悄悄削弱**无人知晓** |

⚠ 暴露面实测：`check` **93** 处 + `check_text` **6** 处 = **99 条判据**藏在实参里。

**③ 修法：恒真探针（`ci-tautology-check.py`）新增第 ④ 类扫描**

| 面 | 规则 | 抓什么 |
|---|---|---|
| `check` 的 python 表达式 | **必须引用 `d`**（被测 JSON，作用域里的变量） | `True` / `1 == 1` / `'a' == 'a'`（压根没碰被测数据） |
| `check_text` 的 ERE | **必须含至少一个字面字符** | `.*` / `^$` / 空串（匹配一切） |
| 实参**解析器** | ⚠ **自己写**（不用正则） | 正则会因转义引号把描述与表达式粘成一块 ⇒ 判据抽错 |
| **条数交叉校验** | 解析出的调用点数 **必须 == 基线**（93 / 6） | 解析器漂了（悄悄少看几条）/ 断言被增删 |

⚠ **口径（实测，不是猜）**：
- ⚠⚠ **不能用正则抽实参** —— 实测 `contract-check.sh:555` 的**描述**里含 `==\"OK\"`
  ⇒ 正则会把描述与表达式粘成一块 ⇒ 判据抽错 ⇒ 门判错。
- ⚠⚠ **基线是两份独立基线**：批 BC 段钉的是「`ci-wiring.sh` 里 93 处 `check` 调用」，
  探针自己钉的是「`contract-check.sh` 里**解析出** 93 处」⇒ 一份被改而另一份没改
  ⇒ **交叉校验当场红**。

**④ ⚠⚠ 负控里又撞出**两个**「门形同虚设」的经典形态（本批的另一半价值）**

⚠ **洞 1：盯函数名的门挡不住「改名」**（负控 B10 实测）

`arch_need_count … 'def assertion_arg_is_tautology' 1` 是**子串**匹配
⇒ 把它改成 `def assertion_arg_is_tautology_disabled` ⇒ **命中仍是 1** ⇒ **门照样绿**
⇒ 那个入口已经不存在了，门却还说「在」。

⇒ **修法**：凡是**以函数名做判据**的门，都必须带**左括号**（`def X\(`）⇒ 改名就红。
⚠⚠ **这不是批 BG 独有**：批 BF 段的 `def tautology_reason` **同样中招** ⇒ 一并改紧
（**4 条**：`tautology_reason` / `assertion_arg_is_tautology` / `scan_shell` / `find_assert_calls`）。

⚠ **洞 2：实参解析器把「空实参」吞了 ⇒ 判据错位**（负控 B4 实测）

判据是「**第二个**实参」⇒ 若解析器把空实参（`''`）吞掉
⇒ `tokens[2]` 变成**第三个**实参 ⇒ 判据抽成别的东西
⇒ **恒真的空 ERE 被判成合法** ⇒ 漏判。

⇒ **修法**：解析器必须区分「**没开始一个 token**」与「**token 内容为空**」
（`started` 标志）⇒ 且**自检里要有合成样例**证明它（**注释不算证据**）。

**⑤ 落门（批 BG 段 11 → 17 条；批 BF 段 1 条改紧）**

批 BG 段的 17 条全部是「**新规则自己不许被掏空**」：
判定入口（**定义带 `\(`** + 调用点）/ 真正判定函数 `assert_arg_reason`（定义 + 调用点）/
两条规则 / 字面字符判定 / 解析器（定义 + 调用点 + **`started` 保留空实参**）/
调用点扫描（定义 + 调用点）/ 基线表有且只有两处 / 基线 93 / 基线 6 /
条数交叉校验 / 自检 `assert_arg` 组 6 条。

⚠⚠ **「定义 + 调用点」各钉一条的理由**：定义钉「入口还在」，
调用点钉「**真的被走**」⇒ 只钉定义 ⇒ 入口还在但没人调它 ⇒ 又是空门。

**⑥ 判据**

- 门项 706 → **723**（**+17**）；selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**。
- **负控 12/12 真红**（累计 **274/274**）：
  - B1/B2 掏空契约门一条 `check` 的表达式（`True` / `1 == 1`）⇒ 探针红 **且**
    **契约门仍 120/0**（证明补的是别的门补不了的缺口）。
  - B3/B4 掏空一条 `check_text` 的 ERE（`.*` / **空串**）⇒ 探针红。
  - B5 删掉契约门一条 `check` 调用 ⇒ **条数交叉校验**红。
  - B6 把基线里的 93 改成 92 ⇒ **条数交叉校验**红（两份基线互相看住）。
  - B7/B8 改坏两条判定规则 ⇒ **自检**红（报的是「自检失败」，不是随便什么红）。
  - B9 把实参解析器改坏（抽不出实参）⇒ **条数交叉校验**红。
  - B10/B11/B12 给三个函数**改名**（`assertion_arg_is_tautology` /
    `tautology_reason` / `scan_shell`）⇒ **对应段的门**红。
- **零产品代码改动**（只动 `ci-tautology-check.py` / `ci-wiring.sh` 与文档）。

⚠⚠⚠ **负控的第一次跑是 8/12 —— 红的两个 case 都是真洞，不是负控写错**：
B4（空实参被吞 ⇒ 漏判）与 B10（改名躲过子串门）⇒ **这正是负控存在的意义**。

⚠⚠⚠ **负控自己也踩了两次坑**（如实记着）：
- ⚠ **段内脚本的退出码**：抽取「某一段的门项」单独跑时，脚本最后一行是
  `echo "SEG_FAIL=$ARCH_FAIL"` ⇒ **sh 的退出码 = echo 的退出码 = 恒 0**
  ⇒ 负控永远读到「段内 rc=0」⇒ **门红了也看不出来**
  ⇒ 与批 BF「审计器无参模式只出报告、退出码恒 0 ⇒ 判红必须用硬门模式」**同款**。
  ⇒ 修法：段内脚本结尾 `exit $ARCH_FAIL`。
- ⚠ **完整接线门不能当「某一段的门抓到了」的证据**：接线门里**审计器先跑**
  （`ci-wiring.sh:1297`）⇒ 审计器一红就 `exit` ⇒ **后面段落的门项根本没执行**
  ⇒ 负控改为**单独跑那一段**（门函数本体从 `ci-wiring.sh` **原文现抽** ⇒ 零漂移，
  批 AV 纪律）+ 完整接线门的退出码作**第二重**断言。

**⑦ ⚠ 元教训**

- ⚠⚠ **判据不只在 `if` 条件里，也在断言函数的实参里** ⇒ 扫恒真必须按
  **断言函数的调用形态**分层扫（条件层 / 实参层）⇒ 少扫一层就是一片空白。
- ⚠⚠ **盯函数名的门挡不住改名** ⇒ 名字类判据必须**带左括号**或改盯**调用点**
  ⇒ 「恰好 N 次」的语义是「不许增不许减」,**但子串匹配会让「换名」变成「没变」**。
- ⚠⚠ **解析器吞掉空实参 ⇒ 判据会错位** ⇒ 判据是「第 N 个实参」时,
  解析器**必须保留空实参**,且要有**合成样例**证明它（注释不算证据）。
- ⚠⚠ **「门自己证明自己有牙」两次救了场** —— 探针的行为（判定逻辑、解析器行为）
  只能靠**合成样例**证明 ⇒ 静态门盯「代码在不在」,合成样例盯「**代码对不对**」。
- ⚠⚠ **负控要能区分「门没红」与「变异没做成功」** —— 本批每个 case 都先断言
  「替换文本确实写进去了」⇒ 否则「编译/解析失败」与「门没红」长得一样。

**⑧ 已知边界（如实记着）**

- 「条件本身合法但恒真」静态分析抓不到 ⇒ 需**变异测试**（批 BF 已记，本批不做）。
- ⚠ **「合法但恒真」的实参同样抓不到** —— 例如 `d.get('x') == 1` 而 `d` 里恒有 `x`
  ⇒ 静态分析无能为力 ⇒ 同上。
- ⚠ **删掉一条门项本身不会让门红**（审计器不盯「门项总数」）⇒ **批 BH 已解**（见 E.2q：门项行总数基线 + 审计器门型对拍）。

### E.2q 门项总数不许被悄悄删（批 BH —— 批 BA 留下的洞）

**① 起因**：批 BA 落了 12 条 per-step 门（钉「**ci.sh 的每一步**」）
⇒ ⚠ 但**没有人钉「接线门自己的每一条门」**
⇒ 批 BG 的负控脚本里有个 case 明确写着「删掉批 BG 段的一条门项 ⇒ 审计器盲区检测必须红」
⇒ ⚠⚠⚠ **实测做不到**（审计器不盯「门项总数」）⇒ 当时如实记为已知边界。

**② ⚠⚠⚠ 实测取证（修前）：删一条门项 ⇒ 全绿**

变异：把 `ci-wiring.sh` 里任意一条门项**改成注释** ⇒

| 观测 | 结果 |
|---|---|
| 接线门 | **rc=0（全绿）** |
| 审计器 | **rc=0** |
| **CI 全流程** | **rc=0（15/15 全绿）** |
| ⇒ 结论 | 「**门项被悄悄删**」这件事，**没有任何机制会发现** |

⚠⚠⚠ 接线门自己的输出里就印着「门项合计 **722** 项」（比基线少 1）
⇒ ⚠ **数字就在眼前，但没人拿它跟基线比**。

**③ 修法：两条互补的核对（都在审计器里）**

**① 门项行总数基线**（新文件 `scripts/ci-wiring-gates.baseline`）
- 审计器数「文件里实际的门项行数」（**不认识门型**的口径）⇒ 必须 == 基线。
- ⚠ **基线放独立文件**（不写死在审计器里）⇒ 写死的话审计器既是**执行者**
  又是**裁判** ⇒ 改审计器就能同时改标准；独立文件 ⇒ 删基线文件 ⇒
  门与审计器**双双红**。
- ⚠ **「恰好」口径是双向的**：基线改小（实际 > 基线）也红、改大（实际 < 基线）也红
  ⇒ 基线成了**锚点**，不是「可以随手改的门槛」。
- ⚠ **基线文件里不许写注释**（门项会管）⇒ 门侧 `strip_comments` 与审计侧读原文
  看到的是同一行。
- ⚠⚠ **两个口径不是一回事**（实测）：「门项**行**数」= 732，
  而接线门报的「门项合计」= **735**（执行次数）⇒ 差 3 是因为**有门项在文件列表
  循环里被多次执行** ⇒ ⚠ **基线盯的是「行数」**（源码层），不是执行次数。

**② 审计器门型覆盖对拍**（「认领数 == 物理行数」）
- 审计器按**自己登记的门型清单**（`GATE_TYPES`，14 种）数一遍，
  再按**不认识门型**的物理口径数一遍 ⇒ 两个数不等 ⇒ **有一种门型没被登记**
  ⇒ 那些门项**根本没被审**（批 AR 说的「审计器自己有盲区」）⇒ 退出码 2。
- ⚠ 今天两边都是 732（恒等）⇒ 这条防的是**将来新增门型时忘了登记**。

⚠⚠⚠ **⚠ 实测踩到的一个坑（也是对拍的价值）**：`ANY_NEED_LINE`（`arch_need\b`）
里 `\b` 允许后接 `(` ⇒ **函数定义行会被它命中** ⇒ 审计器「认领数」比物理行数多 1
⇒ **对拍当场红** ⇒ 修法：计数时排除定义行（`FUNC_DEF_LINE` 已改成通用版
`arch_\w+` ⇒ 覆盖**所有**门型的定义行）。

**④ ⚠⚠⚠ 负控里又撞出一个洞：「盯串」不够，要「盯整行」**

把审计器的判定掏空但**保留判定串**（`elif gphysical != gbase and False:`）⇒
- 「恰好 1 次」的门**照样绿**（串还在）；
- ⚠⚠⚠ **恒真探针也抓不到**（实测：python 侧的「`and False` 捷径」不在它的规则里
  —— 批 BF 的捷径规则只覆盖**判定层 C++**）；
- ⇒ **没有任何机制会发现** ⇒ 审计器永远不报总数失配 ⇒ 删门项又没人管。

⇒ **修法**：**锚定那一行原样**（含缩进与行尾）⇒ 判定被掏空 ⇒ 命中 0 ⇒ 红。
⚠ 这个手段**不推广**到所有门项（太脆）⇒ 只用于**关键判定**。

**⑤ ⚠⚠⚠ 本批还撞出一个洞，并顺手补上：审计器自己有**重名常量** ⇒ 那个常量是死代码**

本批加「物理门项行」口径时用的常量名**撞了**文件下方已有的同名常量
⇒ 后者覆盖前者 ⇒ 前者成了**死代码**
⇒ ⚠⚠⚠ **没有任何门会红**（串还在，只是不生效了）⇒ 差点让**对拍口径**与实现脱节。
⇒ 这一族（「同名互相顶替」）从批 AS 起反复出现 ⇒ 交给机器盯：
审计器新增**模块级重名自检**（用 `ast` 精确判定「模块级赋值名」，不用正则
—— 正则分不清「赋值」和「比较」）⇒ 重名 ⇒ 退出码 **7**（与「盲区(2)/
豁免外(3)/次数失准(4)/正则坏(5)/总数失配(6)」区分开 ⇒ 不然排障会被带偏）。

⚠⚠⚠ **⚠ 本批自己又踩了一次「判定串在注释里重复出现」**：
审计器源码里我**注释**中重复写了 2 次被门盯的常量名 ⇒ 因为
`strip_comments` 对 `.py` **只剥 `//`、不剥 `#`** ⇒ 命中数从 2 变成 4
⇒ **审计器的配准校准当场报失准**（rc=4）⇒ 门自己抓到了我。
⇒ 教训：**注释里千万别重复写被门盯的串**（期望值会漂）。

**⑥ 落门（批 BH 段 12 条）**

基线文件必须在且是纯数字单行（1）/ 审计器必须读基线（2）/ 物理行数口径在（2）/
门型登记处在（2）/ forbid 家族逐门型登记在（2）/ 覆盖对拍的判定在（1）/
总数核对的判定在（1）/ 第 6 种失败态在（1）/ **两条整行锚定**（关键判定不许被掏空）/
**模块级重名自检在**（2）/ 第 7 种失败态在（1）。
⇒ 门项 723 → **735**（+12）。

⚠⚠ **诚实记一条**：审计器在 `ci-wiring.sh` 的**前段** ⇒ 它一红就 `exit`
⇒ **后面段落的门项根本不执行**（批 BE 的坑）⇒ ⇒ **批 BH 段这 12 条门项，
在多数情形下是由「审计器的配准校准」先抓的**（审计器自己校准 `ci-wiring.sh` 里
count 门项的期望数）⇒ 批 BH 段是**第二道防线**（审计器自身被改坏/被掏空时生效）
⇒ ⚠ 不是白写，但要**说清楚它平时不生效**。

**⑦ 判据**

- 门项 723 → **735**（**+12**）全绿；selfcheck **395/0**、契约门 **120/0**、
  ci.sh **15/15**、ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**。
- **负控 12/12 真红**（累计 **286/286**）。
- **零产品代码改动**（只动 `ci-wiring-audit.py` / `ci-wiring.sh` /
  新增 `ci-wiring-gates.baseline` 与文档）。

**⑧ ⚠ 元教训**

- ⚠⚠ **「清单本身」也要被当成要被门守的事** —— 批 BA 钉的是「CI 的每一步」，
  **没人钉「门自己的每一条门」** ⇒ 对象一换，洞就换。
- ⚠⚠ **基线要放独立文件** ⇒ 写死在裁判手里 = 裁判可以改标准。
- ⚠⚠ **「恰好」口径是双向的** ⇒ 基线是**锚点**，不是门槛。
- ⚠⚠ **两份独立口径对拍**（认领数 vs 物理行数）⇒ 当场抓出「多算 1 条（定义行）」。
- ⚠⚠⚠ **「盯串」不够，要「盯整行」** —— 判定被掏空但串还在 ⇒ 什么门都抓不到。
- ⚠⚠⚠ **同名常量 ⇒ 死代码 ⇒ 没有任何门会红**（串还在，只是不生效）⇒ 机器盯。
- ⚠⚠⚠ **注释里重复写被门盯的串 ⇒ 期望值漂**（`.py` 不剥 `#` 注释）⇒ 本批自己踩了。
- ⚠⚠ **负控的失败原因要能区分**（审计器 7 种失败态）⇒ 负控**按 rc 判**，
  不按「rc≠0」。
- ⚠ **负控自己也会写错**：H2/H3/H5 第一版把基线数字**硬编码**成 730
  ⇒ 而基线已变成 732 ⇒ 负控**假失败**（好在断言先报了「变异没做成功」）
  ⇒ 改成**动态读基线**后 12/12。
  ⚠ 另：H7/H8 第一版把「掏空」写成 `elif True:` / `if True:`（让判定**永远成立**）
  ⇒ 变异后审计器报的是别的原因 ⇒ 8/11 ⇒ 改成「永不成立」后 12/12。

**⑨ 已知边界（如实记着）**

- ⚠ **「同时改基线 + 删门项」这个组合躲得过**（要改两处 ⇒ `git diff` 看得见，
  但门不管）⇒ 锚点设计的固有代价。
- ⚠ **恒真探针的 python/shell 侧不查「捷径」**（`and False` / `|| true`）
  ⇒ 判定层 C++ 有、脚本侧没有 ⇒ 本批用「整行锚定」补了关键处，其余仍是洞。
- ⚠ **审计器源码此前一条门都没有盯** ⇒ 本批只盯了新加的这几处，其余仍是洞。
- ⚠ **forbid 家族变体的正则没被写法体检扫**（`RX_ARG_IDX` 里没有
  `arch_forbid_han` / `arch_forbid_text_dup`）⇒ 那 5 条门项写坏了仍可能永远绿。
- ⚠ **每加一条门项都要改基线**（维护负担）⇒ 但「基线与实际不符」双向红
  ⇒ 改基线时会显眼。

---

### E.2r forbid 门族不许「静默变绿」（批 BI —— 门自己的工具坏了也没人知道）

**① 起因**：批 AX 落了「正则写法体检 + 命中 0 ⇒ 红」⇒ 管住了**门项参数里的正则**
⇒ 但 forbid 家族里有两道门（`arch_forbid_han` / `arch_forbid_text_dup`）**没有正则参数**
⇒ 它们的判据**内建在函数体里**（一行 perl + 一行 grep）⇒ **零审计**。

**② ⚠⚠⚠ 实测取证（修前）：内建判据一坏 ⇒ 门静默变绿**

变异：把 `arch_forbid_han` 里剥注释的 perl 改成语法错误 ⇒

| 观测 | 结果 |
|---|---|
| 被盯文件里**确实有中文**（负控注入的字面量还在） | 是 |
| 接线门 | **rc=0** |
| 接线门输出 | **「✓ 文档窗不许有中文字面量」** |
| ⇒ 结论 | **这道门静默变绿** ⇒ 形同虚设（比没门更糟：给人虚假的安全感） |

⇒ 根因：forbid 门判的是「**不该有的东西没了**」⇒ 「没找到」是常态、是绿
⇒ **工具坏了也长成「没找到」的样子**（输出为空 ⇒ grep 无命中 ⇒ 退出码 1
⇒ 看着像「没找到」）。
⇒ ⚠⚠⚠ **不只这一道**：`arch_forbid` / `arch_forbid_ml` / `arch_forbid_raw` /
`arch_forbid_tree` 都是「grep 退出码 2（正则坏）⇒ 当作没找到 ⇒ 绿」。

**③ 修法：三态判定（found / absent / broken）+ 自检 + 自护门**

- 公共件 `probe_scan_state_of`：**退出码 → 状态**的映射**只有这一份**
  （0 = 命中；1 = 没命中；其它 = **工具坏了** ⇒ **红**，不是绿）。
- 6 个 forbid 门全部改走公共查找 `probe_scan_find` ⇒ 不许各自写一遍判定
  （批 BF/BG 纪律：判定逻辑只能有一份 ⇒ 复制两份迟早漂 ⇒ 一份坏了门还是绿）。
- ⚠ **管道下看不见剥注释工具的退出码** ⇒ 加**存活探测**（`probe_strip_alive`，
  懒探一次）⇒ 探测失败 ⇒ 走剥注释的门一律 broken ⇒ 红。
- ⚠⚠⚠ **实测踩到的一个大坑（负控抓到的真回归）**：把中文门的 perl 从
  `grep -P` 换成 perl 后，**perl 没解码 UTF-8** ⇒ `\x{3000}` 按**字节**匹配
  ⇒ **中文永远抓不到** ⇒ 门被改瞎 ⇒ 负控 H5 当场报「塞中文门没红」。
  ⇒ 修法：`perl -CSD`（实测 rc=0 ✅；⚠ `-Mopen=':std,:encoding(UTF-8)'`
  在这段代码上返回 **255** ⇒ 不可用 ⇒ **编码层必须实测，不能凭印象**）。
- **自检**：`probe_scan_selftest` 用合成样例（命中 / 没命中 / **工具坏了** 三档）
  ⇒ 判定逻辑被掏空 ⇒ 立刻红。⚠ **自检放在门项之前**：放在段末尾 ⇒
  前面的门一红就 `exit 1` ⇒ 自检永远没机会跑 ⇒ 自检形同虚设（批 BG 教训）。
- ⚠⚠⚠ **性能必须实测**：第一版把剥完的内容**落盘**再 grep ⇒ 落盘到 tmpfs
  比管道慢 **20 倍**（30ms vs 1.5ms/次）⇒ 2511 次调用 ⇒ **84 秒**
  ⇒ 改回管道 + 存活探测 ⇒ 接线门 **7.2 秒**（原版 3.9 秒）。

**④ 自护门 4 条（批 BI 段，落在 `ci-wiring.sh` 里）**

| 门 | 盯什么 | 挡住谁 |
|---|---|---|
| `arch_need_count_in_fn` | 三态映射的**三个赋值全在同一个函数里** | 判定被复制成两份 |
| `arch_need_count` | 三态映射**只允许有一个函数定义** | 同上（改名复制也挡住） |
| `arch_need_count` | 公共查找**只允许有一个函数定义** | 同上 |
| `arch_need_min` | 公共查找的**调用点数**（7 = 4 个门 + 自检 3 处） | 公共件被绕开 |

⚠ 判据**行首锚定** ⇒ 门项行以 `arch_` 开头 ⇒ 天然**不匹配自己** ⇒ 期望值不含自引
（批 BH 教训：被盯的串若写在门项行里 ⇒ 门项自己给自己贡献一次命中）。

**⑤ 负控 13/13 真红**（每条都区分「门没红」与「变异没做成功」）

H0 健全性 / H1 中文门的 perl 语法错 ⇒ 红 / H2 文案重门的扫描 perl 改坏 ⇒ 红 /
H3 剥注释的 perl 改坏 ⇒ **存活探测**当场发现 ⇒ 红 / H4 forbid 门项正则写坏
（grep 退出码 2）⇒ 红 / H5 界面层塞中文 ⇒ 门**仍**红（没被改瞎）/
H6 界面层抄判定层文案 ⇒ 门**仍**红 / H7 改自护门期望值 ⇒ 红 /
H8 复制第二份三态映射 ⇒ 红 / H9 掏空三态映射 ⇒ **自检**红 /
H10 删一条门项 ⇒ 门项总数基线红 / H11 删基线文件 ⇒ 红 / H12 改基线数字 ⇒ 红。

⚠⚠⚠ **负控自己也踩了两次**（都改了）：
- **审计器先跑会短路**（批 BG 教训）⇒ H7/H8/H9 的红来自**审计器**而不是批 BI 段的门
  ⇒ 负控改为**从 `ci-wiring.sh` 原文现抽批 BI 段单独跑**（零漂移）⇒ 归因才精确。
- H1 的 perl 变异写成「加一个裸词」⇒ **perl 不报错**（裸词当字符串）
  ⇒ 变异根本没造成失败 ⇒ 改成**缺一个右括号**（真语法错）⇒ 才是真负控。

**⑥ 遗留**

- ⚠ **判据内建在函数体里的门仍然零审计**（本批只把 forbid 家族这 6 道收进公共判定；
  其它「内建 perl/grep」的门若出现，要照样收进公共件）。
- ⚠ **「同时改基线 + 删门项」这个组合躲得过**（批 BH 固有代价）。
- ⚠ **每加一条门项都要改基线**（维护负担）⇒ 但双向红 ⇒ 改基线时会显眼。


### E.2s 恒真探针要看得见「脚本侧捷径」与「heredoc 内嵌脚本」（批 BJ）

**① 起因**：批 BF 的「捷径」规则（`|| true` / `&& false` / `or true` / `and false`）
**只用在判定层 C++**（`tautology_reason`）⇒ shell 与 python 侧**一条捷径规则都没有**
⇒ 脚本里的恒真/恒假条件**全部漏判**。

**② ⚠⚠⚠ 实测取证（修前）：5 个洞**

用一份 fixture（真探针 + 真 `contract-check.sh`）跑：

| 洞 | 现状 |
|---|---|
| shell `if cmd \|\| true; then` | **★ 漏判** |
| shell `if cmd && false; then`（恒假 ⇒ 体永不执行） | **★ 漏判** |
| `while cmd \|\| true; do` | **★ 漏判** |
| python `if x and False:` | **★ 漏判** |
| **heredoc 里内嵌 python** 的 `if True:` / `if x and False:` | **★ 漏判**（压根没扫） |
| heredoc 里内嵌 python 的 `if …:` | **★ 误当 shell 条件**（实测 2 处） |

⇒ ⚠⚠⚨ **恒假方向最危险**：`&& false` / `and False` ⇒ 条件恒假 ⇒ **体永不执行**
⇒ 体里那条断言**从此不会红**。

**③ 修法**

- **统一入口 `shortcut_reason(cond)`**：四种场景（判定层 / shell / python /
  heredoc 内嵌）**全部**走它 ⇒「退出码 → 状态」的映射只有一份（批 BF/BG 纪律）。
- ⚠ **匹配前先剥字符串字面量**（`strip_literals`）⇒ 否则 `[ "$x" = "true" ]`
  里的 `"true"` 会被当成捷径 ⇒ 假红。
- **heredoc 感知**（`heredoc_spans`）：先摘出 heredoc 体
  ⇒ 里面的 `if` 不再被误当 shell 条件；再用 **python 规则 + shell 规则各扫一遍**
  （python 收尾是 `:`、shell 收尾是 `then` ⇒ **天然不冲突** ⇒ 不用判语言）。
- **python 条件提取器**（`python_if_conds`）：**括号配平 + 引号感知** ⇒ 支持跨行。
- 条件集合扩到 `if` / `elif` / `while` / `until`（`elif`/`while` 的条件同样是条件）。

**④ ⚠⚠⚨ 负控撞出一个真洞：「盯串」会被**注释里的同名串**顶替**（批 BH 教训的**反面**）**

把真代码 `skip.add(k)` 换成 `pass  # skip.add(k)` ⇒
**盯串的门项计数仍是 1 ⇒ 门假绿** ⇒ 真代码已经被删了，门却看不出来。

⇒ ⚠⚠⚨ 批 BH 说的是「**盯串不够，要盯整行**」（判定被掏空但串还在）；
⚠⚠⚨ 本批撞到的是**同一形状的另一头**：「**盯串会被注释顶替**」（代码被删但串还在）。
⇒ **两条合起来 ⇒ 关键判定必须整行锚定**（含缩进与行尾）。

⇒ 本批把**新增/升级的 9 条门项全部改成整行锚定**；
⚠⚠⚨ **既有 18 条探针门项仍是盯串** ⇒ 注释仍能顶替它们（**已知边界，如实记着**）。

**⑤ 落门**：批 BJ 段 **6 条**（统一入口定义 / 四个实扫点 / 自检那处 / heredoc 感知 /
python 条件提取器 / shell 扫描跳过 heredoc 体）＋ 升级 3 条
（`SHORTCUT.search` 改整行锚定 / `PY_CONST_IF` 改整行锚定且期望 1→2 / 自检样例 16→28）
⇒ 门项 739 → **745**；基线 736 → **742**。

**⑥ 负控 13/13 真红**

H0 健全性（真实仓探针 rc=0 / 审计器 rc=0 / 接线门 rc=0）/
H1 shell `|| true` / H2 shell `&& false` / H3 python `and False` /
H4 heredoc 内 `if True:` / H5 heredoc 内 `and False` / H6 `while` 里的 `|| true` /
H7 掏空捷径判定（**判定串还在** ⇒ 门挡不住 ⇒ **自检**红）/
H8 复制第二份统一入口 ⇒ 次数门红 / H9 整行真删 heredoc 跳过 ⇒ 次数门红 /
H10 改自检样例条数 / H11 改 `PY_CONST_IF` 期望次数 / H12 掏空探针的判红判定。

⚠⚠⚨ 负控自己踩了一次（H0）：**fixture 里故意放了捷径** ⇒ 探针 rc=1 是**正确的**
⇒ H0 改成「**真实仓**探针 rc=0 + 审计器 rc=0 + 接线门 rc=0」。

**⑦ 遗留**

- ⚠ **既有 18 条探针门项仍是盯串** ⇒ 注释仍能顶替 ⇒ 将来逐条改整行锚定。
- ⚠ **python 的「合法但恒真」仍抓不到**（`if d.get('x')==1:` 而 `d` 里恒有 `x`）
  ⇒ 同「变异测试」那条已知边界。
- ⚠ **shell 侧的「合法但恒真」同样抓不到**（`if [ "$a" = "$b" ]` 恒成立）⇒ 同上。


### E.2t 剥注释必须覆盖 `.py`（根治「注释顶替真代码」这一整类洞）（批 BK）

**① 起因**：批 BJ 负控撞出「**盯串会被注释里的同名串顶替**」这一类洞 —— 把真代码
`skip.add(k)` 换成 `pass  # skip.add(k)` ⇒ **盯串**的门项命中数**仍是 1**
⇒ **门假绿** ⇒ 真代码已经被删了，门却看不出来。

⚠⚠⚨ 批 BJ 给的修法是「**逐条改整行锚定**」⇒ 那只治了**新增/升级的 9 条**
⇒ ⚠ **既有 18 条探针门项仍是盯串** ⇒ 注释仍能顶替它们
⇒ **逐条治标治不完，且以后每加一条都要记得改整行** ⇒ 治标方案本身不可持续。

**② ⚠⚠⚨ 判据先行：先量影响面，再动手**

不先改，先做实验：让 `strip_comments` 对 `.py` 也剥 `#` 注释 ⇒
跑审计器 ⇒ **rc=0，零条门项失准**（批 BH 那处当时已一并修好，
命中数在「剥/不剥」两种口径下**都是 2**）⇒ **零代价根治**。

⇒ 结论：**根治**（改载体）优于**逐条治标**（改判据形状）。

**③ 修法**

- **门侧 `ci-wiring.sh` 的 `strip_comments`**：`*.sh|*.txt)` → `*.sh|*.txt|*.py)`
  ⇒ **所有**盯 `.py` 的门项一次性不再被注释顶替。
- ⚠⚠⚨ **两侧必须同步**（批 AS 纪律：审计器必须调**同一条**命令）：
  **审计器 `ci-wiring-audit.py` 的 `strip_comments` 同步加 `.py` 分支**
  ⇒ 不一致 ⇒ 同一串在两侧算得不一样 ⇒ 配准校准失准（会被当场抓到）。
- ⚠ **行首锚定**（`^[[:space:]]*#`）⇒ 字符串字面量里的 `#` 不受影响 ⇒ 安全。

**④ ⚠⚠⚨ 附带修掉一个隐藏问题：python 的 `//` 是**整除运算符****

`.py` 原来走默认分支（perl 剥 `//`）⇒ 表达式 `a // b` 的**后半截会被当注释剥掉**
⇒ 剥出来的文本是**坏的**。⇒ 归到 `.py` 分支后一并消失。

**⑤ ⚠⚠⚨ 审计器自己抓到了新门项（批 BH 的门型对拍当场生效）**

批 BK 落门时，审计器报 **rc=2（门型盲区）**：新门项的正则参数用了**双引号** ⇒
审计器的 `COUNT_LINE`（只认**单引号**包的正则参数）**解析不到**
⇒ 落进 count-family 兜底 ⇒ **门型盲区**。⇒ 改成**单引号** `'endswith.*\.py'`。

⇒ ⚠ **「门型对拍」这道自护门真的在干活**（不是摆设）。

**⑥ 落门**：批 BK 段 **2 条**（门侧 `.py` 分支 / 审计器侧 `.py` 分支）
⇒ 门项 745 → **747**；基线 742 → **744**。

**⑦ 负控 10/10 真红**

H0 健全性（审计器 rc=0 / 接线门 rc=0 / 探针 rc=0）/
H1 门侧不再剥 `.py` 的 `#` ⇒ 两侧口径不一致 ⇒ 失准必须红 /
H2 审计器侧不再剥 `.py` 的 `#` ⇒ 同上 /
H3 探针真代码换成注释形态 ⇒ 盯串的门项**必须红**（批 BJ 时它是**假绿**）/
H4 探针另一处真代码换成注释形态 ⇒ 必须红（证明不是碰巧）/
H5 批 BJ 那条整行锚定门项的真代码换成注释 ⇒ 必须红 /
H6 删掉批 BK 段一条门项 ⇒ 门项总数基线必须红 /
H7 改基线数字 ⇒ 审计器必须红（基线是锚点，**双向红**）/
H8 删基线文件 ⇒ 审计器必须红 /
H9 掏空探针的捷径判定（判定串还在）⇒ 自检必须红。

累计 **322/322**；**零产品代码改动**。

**⑧ ⚠⚠⚨ 负控自己踩了两次（都改了）**

1. **变异写出了语法错** ⇒ 审计器直接崩 **rc=1**（而不是预期的 rc=4）
   ⇒ **归因不清**（分不清是「门没红」还是「变异本身坏了」）
   ⇒ 改成**语法正确**的版本（改成「不再剥 `.py` 的 `#`」而不是「删掉一块」）。
2. **`restore()` 漏了探针文件** ⇒ 上一个 case 的变异**残留** ⇒
   下一个 case 的探针**抛异常** ⇒ 归因全乱
   ⇒ `restore()` **必须覆盖所有被变异文件**（补上探针）
   ⇒ 用 `git show HEAD:…` 恢复工作区探针（已确认探针 rc=0）。

**⑨ 遗留**

- ⚠ **既有 18 条探针门项仍是盯串** ⇒ 现在靠「`.py` 剥 `#`」**根治**了「注释顶替」
  ⇒ 但「**判定被掏空但串还在**」仍只靠**整行锚定**挡 ⇒ 既有门项**尚未逐条**改整行锚定。
- ⚠ **「同时改基线 + 删门项」躲得过**（批 BH 固有代价）。
- ⚠ **每加一条门项都要改基线**（维护负担）⇒ 双向红 ⇒ 改基线时会显眼。


### E.2u 盯「门自己的工具」的门项必须整行锚定（批 BL）

**① 起因**：批 BJ 负控坐实「**盯串会被注释顶替**」，批 BK 已用「`.py` 也剥 `#`」根治。
⇒ 但「**判定被掏空、串还在**」这一头**仍只靠整行锚定挡**，而批 BJ 只把**新增/升级的 9 条**
改成整行锚定 ⇒ ⚠ **既有 24 条探针门项仍是盯串**。

**② ⚠⚠⚨ 实测取证的增量价值（负控量出来的，如实记着）**

把探针的判定行掏空，看**旧盯串口径**与**新整行锚定口径**分别怎么反应：

| 变异 | 旧盯串口径 | 新整行锚定口径 | 结论 |
|---|---|---|---|
| `if bad:` → `if bad or True:` | **命中 0** ⇒ 旧门**也会红** | 命中 0 ⇒ 红 | ⚠ 本例**不构成增量证据**（连串都没了） |
| `st_bad = self_test()` → `… or True` | **仍命中** ⇒ 旧门**假绿** | 命中 0 ⇒ 红 | ✅ **增量价值在这里** |
| `why = shortcut_reason(…)` → `… or None` | **仍命中** ⇒ 旧门**假绿** | 命中 4→3 ⇒ 红 | ✅ |
| `if st_bad:` → `if st_bad:  # 掏空` | **仍命中** ⇒ 旧门**假绿** | 命中 0 ⇒ 红 | ✅ |

⇒ ⚠⚠⚨ **整行锚定的真实增量价值 = 挡住「同一行的判定在**行尾被追加东西**」**
（`or True` / `or None` / 注释尾巴）。
⇒ ⚠⚠⚨ **「行内插入」类变异旧盯串门也会红** ⇒ 如实记着，不吹。

**③ ⚠⚠⚨ 一个硬约束（实测坐实）：正则参数里**不能有单引号****

`arch_need_count` 的正则参数用**单引号**包裹 ⇒ 正则里出现字面单引号 ⇒ 参数被截断
⇒ 审计器的 `COUNT_LINE` 解析不到 ⇒ 落进 count-family 兜底 ⇒ **门型盲区**（批 BK 教训）。
⚠ 实测 GNU grep 3.11 的 `-E`：**不认** `[\x27]`、**不认** `\047` ⇒ **没有精确匹配单引号的 ERE 写法**
⇒ 只能沿用既有约定：**引号位置写 `.`**（任意单字符）。
⇒ ✅ 但**整行锚定让这个弱点被大幅削弱**（行首 + 行尾都锚死 ⇒ 中间只剩一处 `.`）。

**④ 修法**

- **探针门项逐条改整行锚定**：24 条 ⇒ **30 条**
  （3 处拆分：定义与使用形态不同 ⇒ 一条正则罩不住 ⇒ 各拆一条；
  1 处合并：`.check.: 93` 与 `.check_text.: 6` 在**同一行** ⇒ 合并成一条整行锚定
  ⇒ 两个数**都**被钉死 ⇒ 比原来**更强**；净 **+3**）。
- **审计器新增一条硬门**：盯探针文件的 `arch_need_count` 门项必须整行锚定
  ⇒ **第 8 种失败态**（rc=8）＝「锚定形态违规」/「锚定形态自检不过」。
  - ⚠ **判定逻辑只有一份**（批 BF/BG 纪律）：`anchoring_violation(rx)` ⇒ 实扫与自检都走它。
  - ⚠⚠⚨ **返回「原因」而不是布尔**（批 BJ 纪律）⇒ 调用方不再算一遍
    ⇒ 判定串不会在源码里出现两次 ⇒ 门项盯它时不会「命中两次」。
  - ⚠ **自检放最前**（批 BI 纪律）：前面的检查一红就 exit ⇒ 自检永远没机会跑。
  - ⚠ **自检样例既含「该判违规」也含「不该判违规」**（批 BF 纪律）。
  - ⚠ **适用范围只限探针文件**：探针是「**门自己的工具**」⇒ 它被掏空 = 门**集体**失效
    ⇒ 风险最高 ⇒ 先收这一处；⚠ 全仓逐批推进（已知边界）。
- **落门**：批 BL 段 **8 条**（判定函数定义 / 自检函数定义 / **自检被调用** /
  实扫函数定义 / **实扫被调用** / 第 8 种失败态 / 适用范围常量 / 接线门按 rc 说原因）
  ⇒ 门项物理行数 747 → **755**；执行次数 747 → **758**；
  ⇒ ⚠ **物理行数 ≠ 执行次数（差 3）**：差值来自批 BH 的「门项在文件列表循环里被多次执行」
  ⇒ ⚠ **拆分不改变这个差值**（1 行换 2 行 ⇒ 物理 +1、执行 +1）。

**⑤ 负控 14/14 真红**

H0 健全性（审计器 rc=0 / 探针门项段 rc=0）/
H1 探针门项改回盯串 ⇒ 审计器红 rc=8 /
H2 `if bad` 行内插 `or True` ⇒ 新口径红 /
H3 `if not meaningful_idents(cond)` 行内插 `or True` ⇒ 新口径红 /
H4 `st_bad = self_test()` 行尾追加 `or True` ⇒ **旧门假绿**、新门红 /
H5 `why = shortcut_reason(…)` 行尾追加 `or None` ⇒ **旧门假绿**、新门红 /
H13 `if st_bad:` 行尾追加注释 ⇒ **旧门假绿**、新门红 /
H12 真代码换成注释形态 ⇒ 红（批 BK 根治复验）/
H6 审计器的锚定判定被掏空 ⇒ **自检**红 rc=8 /
H7 自检不再被调用 ⇒ 门红（配准失准 rc=4）/
H8 实扫不再被调用 ⇒ 门红（配准失准 rc=4）/
H9 改基线数字 ⇒ 红（双向红）/
H10 删基线文件 ⇒ 红 /
H11 门项改成「锚定但极宽」（`^.*$`）⇒ 配准红（**锚定 ≠ 内容**的边界）。

累计 **336/336**；**零产品代码改动**。

**⑥ ⚠⚠⚨ 负控自己踩了三次（都改了，这一版才是对的）**

1. ⚠⚠⚨ **测「旧口径命中」时传的是代码行、不是门项正则** ⇒ 结论全错
   ⇒ 负控必须传**门项实际盯的正则**。
2. ⚠⚠⚨ **误以为「行内插入类变异旧门会假绿」** ⇒ 实测旧门**也会红**
   ⇒ ⇒ **增量证据必须用「旧串是子串」的变异**（行尾追加）⇒ 断言分 (a) 新口径必须红 /
   (b) 旧口径仍命中（增量证据）两类。
3. ⚠⚠⚨ **变异写出了语法错**（删掉 `return` ⇒ `IndentationError`）⇒ 审计器崩 rc=1
   ⇒ **归因不清**（分不清是「门没红」还是「变异本身坏了」）⇒ 掏空改成**整体替换函数体**
   ⇒ 并在变异后跑 `ast.parse` 断言语法正确。

**⑦ 遗留（已知边界，如实记着）**

- ⚠ **「锚定」≠「内容」**：`^.*$` 这种极宽正则**也算整行锚定** ⇒ 新的锚定检查抓不到它
  ⇒ 只能靠**次数门配准**兜（实测 H11 ⇒ rc=4）。
- ⚠ **判定「体」被掏空、判定行本身没变** ⇒ 整行锚定**照样绿**
  ⇒ 同「变异测试」那条已知边界。
- ⚠ **全仓其余门项仍是盯串**（实测盘点：`arch_need_count` 共 **117** 条，
  整行锚定仅 **11** 条 ⇒ 纯盯串 **98** 条、半锚定 **8** 条；其中 `ci.sh` 34 条、
  审计器自身 10 条、探针 24 条（本批已收）⇒ **逐批推进**）。
- ⚠ **「同时改基线 + 删门项」躲得过**（批 BH 固有代价）。
- ⚠ **每加一条门项都要改基线**（维护负担）⇒ 双向红 ⇒ 改基线时会显眼。
- ⚠ **门侧的正则参数含单引号会被截断** ⇒ 落进 count-family 兜底 ⇒ **门型盲区**
  ⇒ 落门脚本里加了「正则不得含单引号」的**门禁**（本批当场抓到一次）。


### E.2v 锚定形态检查扩到审计器自身（批 BM）

**① 起因**：批 BL 把「盯探针的门项必须整行锚定」做成了硬门（审计器第 8 种失败态），
⇒ 但**适用范围只限探针文件** ⇒ ⚠ **审计器自身的 11 条门项仍是盯串**
⇒ 而审计器同样是「**门自己的工具**」⇒ 它被掏空 = 门**集体**失效。

⚠⚠⚨ 实测盘点（批 BM 后重新数，**不照抄二手数**）：
`arch_need_count` 共 **134** 条 ⇒ 整行锚定 **65** 条、半锚定 **5** 条、纯盯串 **64** 条；
探针与审计器已**全部**整行锚定 ⇒ 剩下的最大头是 **`ci.sh` 的 34 条**（⇒ 下一批）。

**② 改法**

- **审计器自身的 11 条 ⇒ 17 条**（6 处拆分：定义与使用**形态不同** ⇒ 一条整行正则罩不住）：
  `GATE_BASELINE` / `GATE_CALL_LINE` / `GATE_TYPES` / `FORBID_FAMILY` /
  `check_dup_module_names` / `PROBE_GATE_SUFFIX` 各拆成「定义 + 使用」两条；
  `gtotal != gphysical` / `gphysical != gbase` / `return 6` / `return 7` /
  `endswith.*\.py` 原地改成整行锚定（**不增行**）。
- ⚠ **批 BL 加的 2 条「函数名」门项跟着改名**（**原地替换**，不增行）：
  `check_probe_gate_anchoring` → `check_gate_tool_anchoring`。
- ⚠ **适用范围集合化**：`PROBE_GATE_SUFFIX`（单值）→ `GATE_TOOL_SUFFIXES`（**元组**，
  含探针与审计器）⇒ ⚠ `str.endswith(元组)` 是 python 原生支持 ⇒ 判据**一行**就够
  ⇒ 范围由**一个常量**说了算（单一真相源）。

**③ ⚠⚠⚨ 自证：范围一扩，审计器当场报出 11 条违规**

把适用范围扩到审计器自身的**那一刻**，审计器立刻报出 **11 条**「不是整行锚定」
⇒ ⇒ 新检查**不是摆设**，它在真的干活。

**④ ⚠⚠⚨ 负控撞出一个真问题：一个退出码有两种原因**

H2（把审计器的「门型覆盖对拍」判定行追加内容）实测 **rc=2**，但**真实情况根本没有盲区**。
⇒ 根因：`if gtotal != gphysical:` 被掏空成 `if gtotal != gphysical or True:`
⇒ **恒真** ⇒ **恒走 blind 分支** ⇒ 明明没盲区也报「盲区」。
⇒ ⇒ 「**一个退出码对应两种完全不同的原因**」⇒ 只报一种 ⇒ **会把排障带偏**
（正是批 AZ「不按退出码说原因 ⇒ 排障会被带偏」的老问题，换了个形状）。
⇒ **修法**：rc=2 的消息里**同时**点出第二种可能，并指路「这时看 rc=4（次数门配准，
指名道姓是哪条门项命中 0）」。⇒ ⚠ **没动检查顺序**（改顺序的风险 > 收益 ⇒ 记为已知边界）。

**⑤ ⚠⚠⚨ 实施时踩的一个坑（自己抓到的）**

「跟着改名的 2 条门项」第一版被写成**新增** ⇒ 门项数多出 **2 条重复门项**
⇒ 被**条数自检**当场抓到（期望 17 条、实际 19 条）⇒ 改成**原地替换**（不增行）。

**⑥ 落门 / 判据**

- 门项物理行数 755 → **761**；执行次数 758 → **764**（⚠ 差 3 仍来自批 BH 的循环执行）。
- 接线门 **764** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、恒真探针 **rc=0**、孤儿探针 **rc=0**。
- ⚠ **本批没有新增门项** ⇒ 它的自护**就是**新检查本身
  （任何把审计器门项改回盯串 ⇒ rc=8 ⇒ 红；范围被缩小 ⇒ 范围门项命中 0 ⇒ 红）。

**⑦ 负控 11/11 真红**

H0 健全性（审计器 rc=0 / 接线门 rc=0）/
H1 **审计器自身**的门项改回盯串 ⇒ rc=8（**范围扩展的直接证据**：批 BM 之前没人发现）/
H2 审计器「门型对拍」判定被追加内容 ⇒ 红（**假盲区** ⇒ 见 ④）/
H3 审计器「第 6 种失败态」被改掉 ⇒ 红 /
H4 ⚠ **锚定检查的适用范围被缩小**（去掉审计器自身）⇒ 红（**核心自护**：范围悄悄变小没人知道）/
H5 范围判据行被改成「只看探针」⇒ 红 /
H6 审计器的锚定判定被掏空 ⇒ **自检**红 rc=8 /
H7 改基线数字 ⇒ 红（双向红）/ H8 删基线文件 ⇒ 红 /
H9 审计器门项改成「锚定但极宽」（`^.*$`）⇒ 配准红 /
H10 探针门项改回盯串 ⇒ rc=8（扩范围后探针仍被罩住）。

累计 **347/347**；**零产品代码改动**。

**⑧ 遗留（已知边界，如实记着）**

- ⚠ **rc=2 的两种原因只靠消息提示区分**（没改检查顺序）⇒ 排障仍需看 rc=4 的消息。
- ⚠ **「锚定」≠「内容」**：`^.*$` 也算整行锚定 ⇒ 靠次数门配准兜。
- ⚠ **判定「体」被掏空、判定行本身没变** ⇒ 整行锚定照样绿 ⇒ 同「变异测试」那条边界。
- ⚠ **「同时改基线 + 删门项」躲得过**（批 BH 固有代价）。

### E.2w 整行锚定的豁免机制 + 改名漏改的静态兜底（批 BN）

**① 起因**：批 BL/BM 把「整行锚定」做成了硬门（审计器第 8 种失败态），适用范围 = 探针 + 审计器自身。
⇒ 批 BM 的盘点指出：**`ci.sh` 的 34 条**是下一块最大的盯串 ⇒ 本批收它。
⇒ 但 `ci.sh` 是 **CI 入口** ⇒ 它的门项**必须**钉死 ⇒ 这才有了本批。

**② ⚠⚠⚨ 本批实测坐实的一个真 bug（推送到已推送 HEAD 的真回归）**

批 BM 把 `check_probe_gate_anchoring` 改名成 `check_gate_tool_anchoring` 时
**漏改了报告模式（无参）那处调用点** ⇒ 报告模式一跑就 `NameError` 崩掉（rc=1）。

- ⚠ **CI 只跑 `--list`** ⇒ 报告模式**根本没人跑** ⇒ 这个崩**没人发现**
  ⇒ 一路带到了已推送的 `1ef6b32`。
- ⇒ 根因不是「改名」本身，而是「**改名漏改的路径没人跑**」⇒ **没人跑的路径 ⇒ 没人发现它坏了**。
- ⇒ **三重修法**：① 报告模式改调**同一个**函数（不再各写各的）；
  ② 新增 `check_undefined_names()`（**symtable 实测能精确抓到那个名字**）作**静态兜底**；
  ③ 报告段把「未定义名清单」打印出来。
- ⇒ 审计器新增**第 9 种失败态**（rc=9）＝「引用了未定义的名字」/「豁免基线有坏行」。

**③ ⚠⚠⚨ 为什么必须有「豁免机制」（不是偷懒，是语义不许）**

把 `ci.sh` 纳入整行锚定适用范围后，实测有 **6 条**门项**不能**整行锚定：

| 门项 | 为什么不能整行锚定 |
|---|---|
| `--color-sample` | `ci.sh` 里这条命令是 **shell 续行**（行尾是 `\`）⇒ 锚第一行挡不住下一行的真正动作 |
| `› [0-9]+/15 ` | 15 个步骤打点行的**后半段各不相同** ⇒ 一条正则只能通配 ⇒ 整行锚定**无增量价值** |
| 4 条「期望 0 次」白名单门 | 语义是「这个模式**不许出现在任何位置**」⇒ 整行锚定会把它**改窄**成「不许出现在某一种整行形态」 |

⇒ ⇒ 豁免 = 「**被允许弱化的门项**」白名单 ⇒ 独立文件 + **每行必写理由** + **坏行不豁免**（fail closed）。
⇒ **豁免键 =（门型, 目标相对路径, 门项正则）** ⇒ 三者合起来才唯一
（只用「路径+正则」⇒ 同一个正则被**不同门型**用时会**跨门型漏过去**）。
⇒ **TAB 分隔**（正则里含 `|` ⇒ 不能用 `|` 分隔）；**比较时 rstrip**（正则尾部空格在文本里极易丢失）；
⇒ 豁免正则**只 rstrip 不 strip**（**前导空格有意义**：`^ foo` 与 `foo` 是两条不同的正则）。

**④ ⚠⚠⚨ 「豁免表不许悄悄变长」怎么钉死（第一版有洞，被自己抓住）**

第一版反向配准是「豁免行必须对得上**任何**现存门项」⇒ ⚠ **有洞**：
给一条**已经锚定**的门项加一行豁免 ⇒ 它对得上 ⇒ **照样混过去**
⇒ 「表里的条数 = 弱化点数」这条等式被破坏 ⇒ **豁免表可以无限变长**。

⇒ **改法**：双向配准**都对标「非锚定门项」集合**：
- 正向（`check_anchor_scope`）：适用范围内**没锚定**的门项若没被豁免 ⇒ 照红（rc=8）。
- 反向（`check_anchor_exempt_reconcile`）：豁免表里每一行必须对得上**一条非锚定门项**
  ⇒ 否则红（rc=9）⇒ 门项被删却忘了清豁免 / 空豁免 / **给已锚定门项白占一行** 三种都抓得住。
- ⇒ 两者合起来 ⇒ **豁免表 ≡「非锚定门项」集合** ⇒ **条数是推导出来的**
  ⇒ **不必另写一个条数基线**（少一处可以被人偷偷改的地方）。

**⑤ ⚠⚠⚨ 落门（13 条）**

批 BN 段 13 条：豁免表路径常量 / 豁免读取函数（定义 + 被调用） / 豁免判定（定义 + 调用点 + **判定体**） /
未定义名检查（定义 + 被调用） / 反向配准（定义 + 调用点 + **判定体**） / 第 9 种失败态（`return 9` 恰好 4 处） /
接线门按 rc=9 说原因。

⚠ **「判定体」也要单独钉**：只盯**调用点**盯不住**判定体** ⇒
把 `return (kind, relpath, rx.rstrip()) in exempt` 掏空成 `return True`
⇒ **所有**门项都被豁免 ⇒ 门集体失效（比没豁免还糟）⇒ 负控 H7 实测确认。

**⑥ ⚠⚠⚨ 适用范围里明确排除的两类（如实记着，不是漏掉）**

- ⚠ **裸 `arch_need`（「至少 1 次」门）不纳入**：它的语义是「串**出现在任何位置**」
  ⇒ 整行锚定会把它**改窄** ⇒ 与「期望 0 次」的白名单门**同一类**；
  ⇒ 且 `ci.sh` 上每条 `arch_need` 都已有**对位的 `arch_need_count` 整行锚定门** ⇒ 覆盖面不丢。
- ⚠ `arch_need_count_in_fn` / `_in_step` 不纳入（跨行是常态）⇒ 同批 BL 的口径。

**⑦ 落门 / 判据**

- 门项物理行数 761 → **779**（**+18** ＝ `ci.sh` 的门项改整行锚定时**拆出 5 条**
  （一条正则罩不住两种形态 ⇒ 各钉一条：`arch_need_count` 34 → 39）＋ 批 BN 段**新增 13 条**；
  ⚠ 其余改动都是**原地替换**，不增行）；
  执行次数 764 → **782**（⚠ 差 3 仍来自批 BH 的循环执行）。
- 接线门 **782** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**（批 BM 的崩已修）、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 14/14**（H0 健全性 + H1 豁免表变长 + H2 正则写错 + H3 理由为空 + H4 字段数不对 +
  H5 文件不存在 + H6 已锚定门项改成盯串 + H7 判定体掏空 + H8 静态检查不被调用 +
  H9 **改名漏改复现** + H10 路径常量被改 + H11 rc=9 分支被删 + H12 rc=9 少一处 + H13 键少一个维度）。

**⑧ 遗留（已知边界，如实记着）**

- ⚠ **豁免表**也是**基线**：同时「加一行豁免 + 让对应门项不锚定」⇒ 双向配准都过 ⇒ 只能靠 diff 看得见。
- ⚠ **反向配准只在全量模式下做**（`--changed` 只审新增门项 ⇒ 「非锚定门项」集合不全 ⇒ 会误报）。
- ⚠ **`arch_need` 家族仍是盯串**（语义不许整行锚定 ⇒ 不是洞，是取舍）。
- ⚠ **判定「体」被掏空但判定行没变** ⇒ 整行锚定照样绿 ⇒ 同「变异测试」那条边界。
- ⚠⚠⚨ **批 BN 后重新盘点（不照抄二手数）**：`arch_need_count` 真实 **152** 条
  （⚠ 注意：`grep` 出来会多 1 条 —— 那是 `arch_need_count()` 的**函数定义行**，
  审计器用 `FUNC_DEF_LINE` 排除它）⇒ 整行锚定 **111**、半锚定 **5**、**纯盯串 36**。
  ⇒ 对比批 BM（134 条 ⇒ 65/5/64）：纯盯串 **−28**（正是 `ci.sh` 那批改写）、
  整行锚定 **+46**（28 条改写 + 18 条新增）。
  ⇒ 剩下的 **36** 条分布：`ci.sh` **6**（= **全部豁免**，语义不许锚定）、
  `DocPages.cpp` 5、`ci-orphan-probe.sh` 3、其余 C++ 侧与探针脚本零散 ⇒ **逐批推进**。

### E.2x 接线门脚本自己的「失败上报路径」必须有门（批 BO）

**① 起因**：批 BL/BM/BN 一路把「**判定被掏空、串还在**」这一类洞往上收
（探针 → 审计器 → `ci.sh`），⇒ 但**门脚本自己**（`ci-wiring.sh`）的
**失败上报路径**从来没被任何门盯过。

**② ⚠⚠⚨ 本批实测坐实的洞（不是推演）**

`ARCH_FAIL=1` 是「**门型判定失败 → 整道门红**」的**唯一通路**。
⇒ 把它改成 `ARCH_FAIL=0` ⇒ **那个门型的所有失败都静默**。
⇒ 而审计器**自己重算命中数**（次数配准）⇒ 期望与实际仍然一致 ⇒ **审计器也抓不到**。
⇒ ⇒ 这是「**判定被掏空、串还在**」的**最严重形态**，而且是**批量**的：
改一处 ⇒ **一个门型的全部承诺同时失效**。

**③ ⚠⚠⚨ 实测盘子（门侧同口径量，重新数）**

- 全文失败上报 **35** 处：**28** 处在 16 个门型/上报函数体内，**7** 处在**顶层**。
- `arch_` 门型函数 **14** 个：**10** 个**直接**写上报、
  **4** 个 forbid 族（`arch_forbid` / `_ml` / `_raw` / `_tree`）**转发**给上报函数。
- 上报函数 2 个：`probe_scan_report`（**3** 处上报）、`probe_scan_report_many`（**2** 处）。

**④ ⚠⚠⚨ 三层钉法（不用新门型 ⇒ 审计器零改动）**

- ① **per-函数**（16 条）：每个门型/上报函数体内**到底有几处上报** ⇒ **指名道姓**
  ⇒ 用现成的 `arch_need_count_in_fn`（它**认识函数体结构** ⇒ 批 BE 纪律）
  ⇒ 转发型门型盯的是「**必须调用上报函数**」⇒ **转发关系被摘掉也红**。
- ② **总数**（1 条）：全文 **35** 处 ⇒ 覆盖**顶层**那 **7** 处
  ⇒ ⚠ 顶层块**没有花括号** ⇒ `arch_need_count_in_fn` 提不出「函数体」⇒ 只能靠总数兜。
- ③ **注册表**（1 条）：`arch_` 门型函数**恰好 14 个**
  ⇒ **新增门型** ⇒ 必须改基线 ⇒ 改的时候就会看到「**新门型也得有失败上报**」
  ⇒ 集合层把新成员挡住。

**⑤ ⚠⚠⚨ 判据要避开自引**（批 BI 纪律）：总数与注册表的正则都**行首锚定**
（`^\s+ARCH_FAIL=1( ;;)?$` / `^arch_\w*\(\) \{`）⇒ 门项行自己不会被数进去
⇒ 期望值里不混着「自己」（负控 H0 实测两个自引口径命中数均为 **0**）。

**⑥ ⚠⚠⚨ 实施时踩的一个坑（自己抓到的，值得记）**

批 BO 段第一次落盘时，插入锚点取的是那一行门项的**前缀** ⇒ 批 BO 段被插进**行中间**
⇒ 那一行的第 **4** 个参数（说明）被**截断到段尾** ⇒ `arch_need_count` 只收到 **3** 个参数
⇒ `set -u` 下 `$4` 未设置 ⇒ 脚本崩 rc=2 ⇒ 门项**一条都没跑到**。
⇒ **教训**：插入点必须落在**整行之后**（锚点要含行末换行），
否则会**截断那一行的参数** ⇒ 而且症状是「脚本崩」而不是「某条门红」⇒ 归因绕远。

**⑦ 落门 / 判据**

- 门项物理行数 779 → **797**（+18）；执行次数 782 → **800**（⚠ 差 3 仍来自批 BH 的循环执行）。
- 接线门 **800** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- ⚠ **审计器**独立校准了这 18 条（`check_count_in_fn_gates` 自己提函数体、自己数）
  ⇒ 期望次数**不是**我拍脑袋写的。
- **负控 14/14**（H0 健全性 / H1 `arch_need_count` 少一处上报 ⇒ 红 /
  H2 上报函数少一处 ⇒ 红 / H3 forbid 的**转发调用**被摘掉 ⇒ 红 /
  H4 转发到**错的上报函数** ⇒ 红 / H5 / H9 / H10 各门型少一处 ⇒ 红 /
  H6 **顶层**少一处 ⇒ per-函数命中数**不变**（证明它管不到顶层）而总数变 ⇒ 红 /
  H7 **新增门型**（自己没上报）⇒ 注册表红 / H8 **多**一处上报 ⇒ 红 /
  H11 改基线 ⇒ 红 / H12 删门项 ⇒ 红 / H13 sig 指向不存在的函数 ⇒ 红）。

**⑧ 遗留（已知边界，如实记着）**

- ⚠ **总数门项与 per-函数门项是两道独立的门** ⇒ 「从 A 挪一处到 B」总数不变
  ⇒ 靠 **per-函数**那层抓（负控 H8 实测能抓「多一处」）。
- ⚠ **新增门型**只被**注册表**挡（改基线就过）⇒ 而**同时改基线 + 不加上报门项**
  ⇒ 躲得过（批 BH 固有代价：基线是锚点，diff 看得见）。
- ⚠ **顶层那 7 处**只有**总数**兜 ⇒ 不指名 ⇒ 排障要自己看是哪儿少了一处。
- ⚠ **`arch_need_count_in_fn` 提不出没有花括号的块** ⇒ 顶层块天然进不了 per-函数层。

### E.2y 恒真探针自己的「扫描范围」不许被改窄（批 BP）

**① 起因**：批 BJ 建了「**判据不许被掏空成恒真**」这一整类洞的探针
（`ci-tautology-check.py`），批 BK/BM/BN 一路把「**判定被掏空、串还在**」往上收
（探针 → 审计器 → `ci.sh`）。⇒ 但**探针自己的扫描范围**从来没被任何门盯过。

**② ⚠⚠⚨ 本批实测坐实的洞（不是推演）**

把探针里「扫 `.sh` 脚本」那一行改掉（`fn.endswith('.sh')` → `fn.endswith('.shX')`）⇒
**所有 shell 脚本的 if 条件都不再被查恒真**。
⇒ 而探针**自己没有条数基线** ⇒ 少扫了它也照样输出「✓」并 **rc=0**
⇒ ⇒ 探针**静默变成半个空门** ⇒ 批 BJ 建立的「脚本侧捷径」**整类洞失守**。
⇒ 而 CI **只跑这一个入口** ⇒ 没人会发现。

**③ ⚠⚠⚨ 实测盘子（扫面盘点，不靠印象）**

| 探针的「范围」要素 | 原文 | 原先有没有门 |
| --- | --- | --- |
| 判定层目录 | `appdir = os.path.join(root, 'src', 'app')` | **无** |
| 脚本目录 | `scripts = os.path.join(root, 'scripts')` | **无** |
| shell 脚本范围 | `if not fn.endswith('.sh'):` | **无** |
| python 脚本范围 | `if not fn.endswith('.py'):` | **无** |
| 判定层前缀常量 | `JUDGEMENT_PREFIX` | **有**（批 BJ 段） |
| 审计器侧 4 个常量 | `ANCHOR_SCOPE_SUFFIXES` / `GATE_BASELINE` / `GATE_TYPES` / `ANCHOR_EXEMPT` | **有**（批 BM/BN 段） |
| 孤儿探针白名单 | 4 条数基线 + 7 处断言清单 | **有**（批 BH 段） |
| 契约门清单 | 93 处 `check` 调用点 | **有**（批 BG 段） |

⇒ **四个「范围」要素一个都没有门** ⇒ 探针的覆盖面是可以被静默改窄的。

**④ ⚠⚠⚨ 两层修法**

- ① **范围行逐条钉住**（4 条，**整行锚定**）⇒ 改范围常量 / 改扩展名 ⇒ 必红。
  ⚠ 判定层前缀那 2 条已在批 BJ 段（不重复落门）。
- ② **扫到的文件数必须有基线**：新建独立文件 `scripts/ci-tautology-scope.baseline`
  （3 行纯数字：判定层 **4** / shell **18** / python **3**）。
  - ⚠ **恰好**相等（批 BB 口径：「不少于」天生带余量 ⇒ 少一个还绿 ⇒ 没牙）。
  - ⚠ **fail closed**：基线读不到 / 有坏行 ⇒ **照红**（不许「读不到就当没有基线」）。
  - ⚠ **基线是自锚的**（批 BH 纪律的关键差别）：期望值写在**独立文件**里，
    实际值来自**文件系统** ⇒ 改基线单独就红 ⇒ **裁判改不了标准**。
  - ⚠ **基线自己的行数也有门**（`^[0-9]+$` 恰好 3 行）⇒ 基线被塞进第 4 行也红。

**⑤ ⚠⚠⚨ 探针侧顺带修的两处**

- **目录不存在 ⇒ 明确报错**（不许崩成 traceback）—— 崩掉的退出码也是 1 ⇒
  CI 照样红，但**看不出是哪一步坏了** ⇒ 排障被带偏（批 AZ 纪律）。
- **检查必须复用变量**（`scripts = os.path.join(root, 'scripts')` 提前到 appdir 之后）
  ⇒ 不另写字面量 ⇒ **两套口径必然漂**。

**⑥ ⚠⚠⚨ 实施时踩的三个坑（自己抓到的）**

- ① **插入点必须用 `rindex`（最后一个）**：`ci-wiring.sh` 里有**十三个**
  `if [ "$ARCH_FAIL" -ne 0 ]; then` ⇒ 用 `index` 会插到中间某段
  ⇒ 那一段前面的收尾会**提前 exit** ⇒ 新段的门项**根本跑不到**。
- ② **段序被搬乱** ⇒ 从备份恢复重做（脚本一次做完，不要边做边搬）。
- ③ **门项正则与落盘文本不一致** ⇒ 校准用的正则写成 `.\.sh.` 而落盘写成 `.*\.sh.*`
  ⇒ 门项实际**抓不到变异** ⇒ 「整行锚定」名存实亡。
  ⇒ **校准用的正则必须与落盘的正则完全一致**。

**⑦ 落门 / 判据**

- 门项物理行数 797 → **809**（+12）；执行次数 800 → **812**
  （⚠ 差 3 仍来自批 BH 的循环执行）；门项总数基线 `ci-wiring-gates.baseline` = **809**。
- 接线门 **812** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**（判定层 **396** 条 / shell+python **498** 个 if / 实参 **99** 条）、
  孤儿探针 **rc=0**。
- **负控 14/14 真红**：H0 健全性 / H1-H4 四种范围被改窄
  （**探针自己红** 且 **门项红**）/ H5 判定层前缀被改（**探针自己红**；
  门项那一层由批 BJ 段负责 ⇒ 归因要分清是哪一层抓的）/
  H6 fail closed 判定**整行**被改 / H7 基线文件被删 / H8 基线被改小 /
  H9 基线多一行 / H10 基线非数字行 / H11 基线行数门 / H12 改门项总数基线 /
  H13 删门项。

**⑧ 遗留（已知边界，如实记着）**

- ⚠ **「范围」是靠逐条钉住源码行挡住的** ⇒ 探针若改成「按配置/环境变量决定范围」，
  那几行源码还在 ⇒ 门不红 ⇒ **范围仍可被改窄**（形态变了，门跟不上）。
- ⚠ **文件数基线挡不住「换了内容、没换数量」**（比如把判定层目录指向另一个同样有 4 个文件的目录）。
- ⚠ **基线是锚点 ⇒ 改基线 + 改探针同时做，就躲得过**（批 BH 固有代价：diff 看得见）。
- ⚠ **全仓其余门项仍是盯串**（批 BN 后重新盘点：纯盯串 **36** 条）⇒ 逐批推进。

### E.2z 「整行锚定」不许名存实亡：中间不许无界通配（批 BQ）

**① 起因**：批 BL/BM/BN 一路用**整行锚定**挡「**判定被掏空、串还在**」
（探针 → 审计器 → `ci.sh`）。⇒ 但**整行锚定只看「行首 `^`」+「行尾 `$`」**
⇒ 中间放一个**点星**（无界通配）⇒ 行首行尾锚死、**中间什么都能吃**
⇒ ⇒ 判定被掏空、串还在 ⇒ 门照样绿 ⇒ 「整行锚定」**名存实亡**。

**② ⚠⚠⚨ 本批实测坐实的洞（不是推演）**

探针的样例表门项 `^\s+\(.*,\s*(True|False)\),$`（28 条）就是这种写法
⇒ 样例表的内容**随便改都照样命中** ⇒ 那道门是**假的**。
⇒ 这正是批 BL 留下的那条已知边界（「**锚定 ≠ 内容**」：`^.*$` 也算整行锚定）
在本批被**收掉一半**。

**③ ⚠⚠⚨ 实测盘子（适用范围内逐条扫，不靠印象）**

- 适用范围内（探针 / 审计器 / `ci.sh`）`arch_need_count` 共 **124** 条。
- 其中**中间含无界通配**的：**2** 条 ⇒ 就是上面那两条表形态门项
  （`^\s+\(.*,\s*(True|False)\),$` 与 `^\s+\(.assert_arg.,.*\),$`）。
- ⇒ 改造前：整行锚定 **122** 条、**名存实亡 2** 条。
- ⇒ 改造后：**124** 条**全部**名副其实。

**④ ⚠⚠⚨ 三层修法**

- ① **审计器加一条判定** `has_unbounded_wildcard()`：
  - 只认**未被转义**的点星 ⇒ 点号前**偶数**个反斜杠 ⇒ 是通配；
    **奇数**个 ⇒ 被转义 ⇒ 是字面点（`\.\*`）⇒ **放行**。
  - 适用范围仍是「门自己的工具」（探针 / 审计器 / `ci.sh`）⇒ 不扩大。
  - 违规 ⇒ 审计器**第 8 种失败态**（rc=8）。
  - ⚠ **副作用（好事）**：`^.*$` 这种「锚定但极宽」的写法现在**也会被报出来**
    ⇒ 批 BL 负控 H11「锚定但极宽 ⇒ 配准红」现在**多一道**独立的抓法。
- ② **自检必须含正反两面**（批 BF 纪律）：含点星的**必判违规** /
  有界通配的**必判合规** / 转义点星的**必判合规**
  ⇒ 判定被掏空时**当场红**（实测：审计器的判定被改 ⇒ rc=8，**自检**抓的）。
- ③ **那 2 条「名存实亡」的门项改成精确形式**（本批同批改）：
  按「**类别 + 期望**」拆成 **9 条**（cond 6+3 / shortcut 8+4 /
  assert_arg 2+1+2+1 / shell_scan 1）⇒ 中间用**有界**通配
  （`[^,]*` / `[^)]*` / `[^]]*`）⇒ 吃不掉结构分隔符 ⇒ 行结构仍被钉住
  ⇒ 整行锚定**名副其实**。

**⑤ ⚠⚠⚨ 实施时踩的三个坑（自己抓到的，都记着）**

- ① **字符类不能写 `[^)]`**：样例 `('check', "d.get('x')==1")` 的实参里
  **带右括号** ⇒ `[^)]*` 提前停 ⇒ 实测命中 **0**（不是 1）⇒ 改用 `[^,]` 才罩住。
- ② **结构顺序不能想当然**：`('shell_scan', (<文本>, [<列表>]), True)`
  的**列表在右括号之前** ⇒ 正则必须写成 `\([^)]*, \[[^]]*\]\)`
  ⇒ 写反了实测命中 **0**。
- ③ **正则里不能有字面单引号**（批 BL 既有约束：shell 单引号包裹 ⇒ 会被截断
  ⇒ 落进 count-family 兜底 ⇒ **门型盲区**）⇒ 字符类里只能挑**不含引号**的
  结构分隔符（逗号 / 右括号 / 右方括号）。
  ⇒ 连带影响：审计器**自检样例的文本里也不能有逗号**
  （否则「数样例条数」那条门项的 `[^,]*` 会被逗号截断 ⇒ 计数失准 —— 实测踩到）。

**⑥ ⚠⚠⚨ 新规则自己也要有门（否则「规则被掏空」就白改）**

批 BQ 段 **5 条**：判定函数的**定义** / **转义计数判定行** / **「判违规」返回**
/ **调用点** / **自检样例条数（恰好 7）**
⇒ 规则被掏空 ⇒ 门项红 ⇒ 「整行锚定」不会悄悄退回名存实亡。

**⑦ 落门 / 判据**

- 门项物理行数 809 → **821**（-2 +9 +5）；执行次数 812 → **824**
  （⚠ 差 3 仍来自批 BH 的循环执行）；门项总数基线 `ci-wiring-gates.baseline` = **821**。
- 接线门 **824** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 14/14 真红**：H0 健全性 / H1 点星判定**调用点**被掏空 / H2 **转义计数**判定被改 /
  H3 **「判违规」返回**被改 / H4 **自检样例被改**（rc=8 自检抓）/
  H5 **自检样例被删**（条数 7→6）/ H6 ⚠ **真实门项的中间被塞回点星 ⇒ rc=8**
  （**本批核心证据**，且命中数不变 ⇒ 唯一失败原因就是锚定形态）/
  H7 豁免表塞**假豁免**（rc=9 反向配准抓）/ H8 改门项总数基线（rc=6）/
  H9 删门项（rc=6）/ H10 正则塞**字面单引号**（rc=2 门型盲区）/
  H11 审计器**报告模式** rc=0（批 BM 回归）/ H12 删样例（rc=4 次数配准）/
  H13 **豁免文件被删**（rc=9 fail closed）。
- 累计 **403/403**；**零产品代码改动**。

**⑧ 遗留（已知边界，如实记着）**

- ⚠ **本规则只认「未转义的无界通配」** ⇒ 字符类**内部**的点星（如 `[.*]`）
  会被误判成通配 ⇒ **假红**（fail closed 方向 ⇒ 不漏 ⇒ 只是误报）。
- ⚠ **有界通配放行** ⇒ 中间内容仍可变（只钉住「行结构」）⇒
  「换掉一条同类别同样例」这类变异**仍躲得过**（样例表内容级的保护靠
  **自检的期望**与**条数门**，不是靠内容锚定）。
- ⚠ **本规则只管「中间」** ⇒ 行首/行尾的锚点**被改**（如 `^` 变 `\A`）仍是别的判定管的事。
- ⚠ **自检样例条数门用 `[^,]*`** ⇒ 将来加的样例文本里**不许有逗号**
  （否则计数失准 ⇒ 门红 ⇒ 会显眼，但要改门项）。
- ⚠ **全仓其余门项仍是盯串**（批 BN 后盘点：纯盯串 **36** 条）⇒ 逐批推进。

### E.2aa 把**门脚本本体**纳入「整行锚定」适用范围（批 BR）

**① 起因**：批 BL/BM/BN 把「整行锚定」的适用范围从「探针」扩到「审计器自身」
再扩到「`ci.sh`（CI 入口）」⇒ 但**门脚本本体 `ci-wiring.sh` 自己**的门项
**从来没进过适用范围**。

**② ⚠⚠⚨ 为什么这是洞（不是「漏了也无所谓」）**

`ci-wiring.sh` 的门项，就是「**判定层不许被掏空**」这一整类承诺的**载体**。
⇒ 载体自己的门项被掏空 ⇒ 那一整类承诺**集体失效**
⇒ 而它是**静默**的（没人会因为「门项变成盯串」而收到任何通知）。

**③ ⚠⚠⚨ 实测盘子（重新数，不照抄二手数）**

全仓 `arch_need_count` 共 **178** 条 ⇒ 整行锚定 **134** / 半锚定 **8** /
纯盯串 **36**。

目标 = `ci-wiring.sh` 的门项共 **7** 条 ⇒ 其中 **5** 条不是整行锚定：

| 行 | 原正则 | 形态问题 |
| --- | --- | --- |
| 2456 | `^probe_scan_state_of\w*\(\) \{` | 行尾缺 `$` |
| 2457 | `^probe_scan_find\w*\(\) \{` | 行尾缺 `$` |
| 2514 | `^\s+8\) _audit_why=.*$` | 中间有**无界通配**（批 BQ 的新判定） |
| 2544 | `^\s+9\) _audit_why=.*$` | 中间有**无界通配** |
| 2567 | `^arch_\w*\(\) \{` | 行尾缺 `$` |

**④ ⚠⚠⚨ 修法（门项数不变 ⇒ 基线不变）**

- 5 条改成**精确**形式：
  `^probe_scan_state_of\(\) \{ # [^$]*$` / `^probe_scan_find\(\) \{ # [^$]*$` /
  `^\s+8\) _audit_why="[^"]*" ;;$` / `^\s+9\) _audit_why="[^"]*" ;;$` /
  `^arch_\w*\(\) \{ # [^$]*$`
  ⇒ 中间用**有界**通配（吃不掉行尾）⇒ 整行锚定**名副其实**。
- 审计器的 `ANCHOR_SCOPE_SUFFIXES` 加进 `'ci-wiring.sh'`
  ⇒ **单行**（⚠ 多行定义 ⇒ 守着它的门项是整行锚定 ⇒ 命中 0 ⇒ 自相矛盾）。
- 守着那个常量的门项**原地替换**（批 BM 纪律：不增行）⇒ 门项数 **821** 不变。

**⑤ ⚠⚠⚨ 实测：范围是「三重保护」**（与预想不同，如实记着）

预想「范围被改窄 ⇒ 审计器静默 ⇒ 门项才是唯一证据」⇒ **实测不是**：
- 范围**常量**被改 ⇒ 它本身被**次数门**钉着 ⇒ 审计器**次数配准**红（rc=4）。
- 范围**使用点**被改（改成只看探针）⇒ 豁免表的**反向配准**对不上 ⇒ rc=9。
⇒ ⇒ 范围是三重保护：常量被次数门钉 + 使用点被次数门钉 + 被纳入的门项逐条查形态
⇒ **三道线任一失效都还有别的线** ⇒ 但**门项那条线仍要单独断言**
（它才是「指名道姓」的那条）。

**⑥ ⚠⚠⚨ 顺带把「哪些门项该锚定」写成判据（不再是一句含糊的待办）**

⚠ **C++ 判定层的门项刻意保持「盯串」**：
那些门项的承诺是「**这个 API 必须在某处被调用**」（**调用点**承诺）
⇒ 整行锚定会把它**改窄**成「这一种整行形态」⇒ **合法重构就会断门**
⇒ ⇒ **锚定只对「判定行 / 定义行」承诺有意义**，不对「调用点」承诺有意义。
⇒ 且 C++ 侧「判定被掏空」的另一半（`|| true` 之类）**另有探针**兜着
（恒真探针的捷径规则）⇒ 不是没有防线。
⇒ ⚠ 所以「纯盯串 36 条」这个数**不是待办清单**，而是**分两类**：
① 判定行/定义行 ⇒ 该锚定 ⇒ 逐批收（批 BN 收 `ci.sh`、批 BR 收 `ci-wiring.sh`）；
② 调用点承诺 ⇒ **不该**锚定 ⇒ 保持盯串（并写明理由）。

**⑦ 落门 / 判据**

- 门项物理行数 **821**（不变）；执行次数 **824**（不变）；
  门项总数基线 `ci-wiring-gates.baseline` = **821**（不变）。
- 接线门 **824** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 11/11 真红**：H0 健全性 / H1 **范围常量被缩小**（门项红 + 审计器 rc=4）/
  H2 **范围使用点被掏空**（门项红 + 审计器 rc=9）/
  H3 ⚠ **新纳入**（`ci-wiring.sh`）的门项中间塞回点星 ⇒ **rc=8**（本批核心证据）/
  H4 精确门项的**期望次数**被改 ⇒ rc=4 / H5 改门项总数基线 ⇒ rc=6 /
  H6 删门项 ⇒ rc=6 / H7 豁免表塞**假豁免** ⇒ rc=9 /
  H8 正则塞**字面单引号** ⇒ rc=2（门型盲区）/ H9 审计器**报告模式** rc=0 /
  H10 精确门项的**正则**被改坏 ⇒ rc=4。
- 累计 **414/414**；**零产品代码改动**。

**⑧ 遗留（已知边界，如实记着）**

- ⚠ **范围是「后缀」判定的** ⇒ 将来若有**同名不同目录**的脚本
  （如 `x/scripts/ci-wiring.sh`）⇒ 会被**一并**纳入 ⇒ 范围只能放大不能缩小
  ⇒ 属 fail closed 方向 ⇒ 不漏 ⇒ 只是误报。
- ⚠ **`[^$]*` 依赖「注释里没有 `$`」** ⇒ 将来给那几行的注释里写 `$`
  ⇒ 门项命中数变 ⇒ 红 ⇒ 会显眼，但要改门项。
- ⚠ **C++ 侧仍是「盯串」**（**有意为之**，理由见 ⑥）⇒ 那条洞靠恒真探针的
  捷径规则兜 ⇒ 探针本身被掏空的风险由批 BP 段与批 BQ 段盯着。


### E.2ab 把「CI 里跑的断言脚本（探针们）」纳入「整行锚定」适用范围（批 BS）

**① 起因**：批 BL/BM/BN/BR 把「整行锚定」的适用范围从「探针」一路扩到
「审计器自身 → `ci.sh`（CI 入口）→ `ci-wiring.sh`（门脚本本体）」
⇒ 但**CI 里真正跑的那些断言脚本**（`ci-platform-probe.sh` / `ci-docs-lang-probe.sh` /
`ci-divider-probe.sh` / `probe-agent-tool-surface.sh` / `ci-orphan-probe.sh`）
**自己的门项从来没进过适用范围**
⇒ 而它们的门项盯的正是**探针的判定行**。

**② ⚠⚠⚨ 为什么这是洞（实测能骗过门的变异，不是推演）**

那 **7 条**盯探针判定行的门项原来是**裸 `arch_need`（盯串）**
⇒ 判定被掏空但串还在 ⇒ 门假绿。实测能骗过它们的变异（**每条都实测坐实**）：

- 把 `QT_SCALE_FACTOR=2` 挪进行尾注释
  ⇒ 「HiDPI 的效果断言必须真在 dpr=2 下跑」**退化成 dpr=1 的空断言**
  ⇒ ⚠ **正是那条门自己的说明文字所声称要防的** ⇒ 而旧门**看不出来**；
- 把 `--docs-lang-probe` / `--divider-probe` 挪进行尾注释
  ⇒ 两个断言脚本「不再真的跑那个探针」也没人管；
- 把 `field inkWidth` 挪进行尾注释
  ⇒ 分隔线断言**不再真的量墨迹宽**（⇒「1 逻辑像素」那条证明失效）也没人管；
- 把 `grep -Pq` 挪进行尾注释
  ⇒ 文档语言断言**不再真的查汉字**（⇒ 英文档回落成中文抓不住）也没人管；
- 把 `dpiEdgeLevels=legacy:` / `dpiEdgeLevels=.*aware:` 挪进行尾注释
  ⇒ HiDPI 的**边缘过渡层数**断言瞎了（少一列就抓不到「dpr 感知更细腻」）。

⚠⚠⚨ **为什么这批变异能骗过旧门**：`.sh` 的 `strip_comments` 只剥**整行**注释
（批 BK 既有约束）⇒ **行尾注释里的串照样被数到** ⇒ 旧口径「串还在就算数」。

**③ ⚠⚠⚨ 实测盘子（重新数，不照抄二手数）**

目标 = 5 个探针脚本的门项共 **15** 条：

- **7 条**是「盯探针判定行」的**裸 `arch_need`**
  ⇒ 本批改成**整行锚定的 `arch_need_count`（恰好 1 处）**；
- **5 条**是「断言清单条数门」（数 `✗ ` 出现次数）
  ⇒ 口径从「**含标记的行**」收紧成「**真报错行**」（`^[[:space:]]*echo "[ ]*✗`）
  ⇒ **行尾注释里的标记不再算数**
  ⇒ 「删一条真报错 + 在行尾注释里补一个标记」骗不过门了；
- **3 条**是孤儿探针**自己**的门项（2 条判定行 + 1 条白名单条数门）⇒ 全部改成**整行锚定**。

**④ 修法（三层）**

1. **7 条判定行门项 → 整行锚定**（`^…$` + 中间不许无界通配，批 BQ 口径）
   ⇒ 正则**全部由脚本生成**（见 ⑥ 的教训）；
2. **5 条条数门 → 口径收紧成「真报错行」** + **显式豁免**
   （⚠ 行尾是**自由文本** ⇒ 整行锚定等于把每条报错文案逐字写进正则 ⇒ **语义被改窄**
   ⇒ ⇒ 走批 BN 的豁免机制登记，**不是漏网**）
   ⇒ 豁免表 **6 → 11** 条（反向配准仍是自动推导）；
3. **适用范围常量 `ANCHOR_SCOPE_SUFFIXES` 加 5 个探针**（**必须单行**，批 BR 教训）
   ⇒ 守着它的门项**原地替换**（批 BM 纪律：不增行）
   ⇒ 以后谁给这些脚本加「盯串」门项 ⇒ **审计器当场红**（rc=8）。

**⑤ ⚠⚠⚨ 顺带修掉审计器的一个「假红」（本批自己撞出来的，不是推演）**

新门项里有一条要钉住 `ci-orphan-probe.sh` 里那行「排除门项行」的规则，
而那行**行尾是一个反斜杠**（shell 续行）⇒ 整行锚定的正则必须以 `\\$` 结尾
⇒ 审计器原判据 `rx.endswith('\\$')`（末两字符是 `\$`）
⇒ ⚠⚠⚨ **把 `\\$`（转义反斜杠 + 行尾锚点）也误判成「`$` 被转义」**
⇒ 合法的整行锚定门项被红 ⇒ **逼着人把门项写弱**。

⇒ 改成**数反斜杠个数**（**奇数** = 这个 `$` 被转义；**偶数** = 它是行尾锚点）
⇒ 与批 BQ 的 `has_unbounded_wildcard` **同款奇偶口径**。
⇒ ⚠⚠⚨ **假红比假绿更坏**：假绿是承诺悄悄消失；假红是**逼人把承诺改弱**。
⇒ 自检补 **2 条**样例（末尾 `\$` 必判违规 / `\\$` 必判合规）⇒ 样例条数 **7 → 9**。

**⑥ ⚠⚠⚨ 实施踩到的坑（自己抓到的，记下来）**

⚠ **正则不许手写** —— 本批**手写三次、三次都错**：
① `ci-platform-probe.sh` 误写成 `.py`；
② 「单引号位置写 `.`」那条规矩在 heredoc 里被误写成 `\.`（⇒ 要求真的出现一个点）；
③ 改 L2512 时又手写了一遍同样的 `.py`。
⇒ ⇒ **全部正则改由「名字列表」脚本生成**（校准脚本是唯一真相源，落盘从它 import）
⇒ ⇒ **校准用的正则与落盘用的正则逐字节相同**（批 BP 纪律）。

⚠ **标签别用 `split("' '")` 取** —— 门项行里没有 `' '` 这个分隔符
⇒ 取到的是**整行** ⇒ 落盘后 `sh -n` 直接报语法错。
⇒ 标签要用正则 `^arch_need_count "…" '…' N '(.*)'$` 取。

**⑦ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **「真报错行」的口径只认 `echo "✗ ` 开头的行** ⇒ 将来把报错输出改成
  `printf` / `>&2` 别的写法 ⇒ 计数会掉 ⇒ 红 ⇒ 会显眼，但要改门项；
- ⚠ **整行锚定 ≠ 内容**：中间仍有**有界通配**（`[^;]*`）⇒
  「换掉一条同形态的判定」仍可能躲过（批 BQ 既有边界，不变）；
- ⚠ **合同门 / deb 布局门**（`contract-check.sh` / `check-deb-layout.sh`）
  **没进适用范围** —— 它们的门项数的是**调用点**（`check ` / `ok|no `），
  行尾还有实参 ⇒ 行尾锚定会**改窄语义** ⇒ 有意保持现状（判据同批 BR 的分类 ②）；
- ⚠ **真机探针**（`probe-deepin-tray.sh` / `probe-sni-icon.sh`）**没进适用范围**
  ⇒ 它们不在 CI 里跑（白名单已登记）⇒ 逐批推进；
- ⚠ **门项被改弱就得改门项** —— 整行锚定是「故意让合法重构会红」换来的
  ⇒ 改门项是显式动作 ⇒ 会被 review 看见（批 BR 已知边界，不变）。

**⑧ 落门 / 判据**

- 门项物理行数 **821 → 823**（+2 = 批 BS 段那 2 条自护门项）；
  执行次数 **824 → 826**（⚠ 差 3 仍来自批 BH 的循环执行）；
  门项总数基线 `ci-wiring-gates.baseline` = **821 → 823**。
- 豁免表 **6 → 11** 条（反向配准 **0** 不匹配）。
- 接线门 **826** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 25/25 真红**（51 条断言全绿）：
  H0/H0b 基线（15 条新门项全绿 + 审计器绿）/
  H1–H7 **7 条判定行**：每条都断言「**旧门（从备份现抽）在变异后仍绿**（证明旧门有洞）
  **且新门（现抽）在变异后红**（证明新门有牙）**」/
  H8–H12 **5 条真报错行条数门**：「掏空真报错 + 标记挪进尾注释」⇒ 旧口径绿 / 新口径红 /
  H13–H15 **3 条孤儿探针自己的门项**（旧门绿 / 新门红）/
  H16 范围被改窄 ⇒ 审计器红（**rc=9 反向配准**，⚠ 与预想不同，如实记着）/
  H17 范围常量被改 ⇒ 次数门红（rc=4）/
  H18 豁免表少一行 ⇒ 审计器红（**rc=8 正向先红**，⚠ 与预想不同）/
  H19 豁免表塞**假豁免** ⇒ rc=9 /
  H20 **奇偶判定被掏空** ⇒ 自检红（rc=8）/
  H21 自检样例被删 ⇒ 样例条数门红（rc=4）/
  H22 改门项总数基线 ⇒ rc=6 /
  H23 删门项 ⇒ rc=6 /
  H24 审计器**报告模式** rc=0。
  累计 **439/439**；**零产品代码改动**。
- **视觉变化**：无（只动判据层与文档；快照零变化）。

### E.2ac 探针脚本的「失败上报」不许被摘掉（批 BT）

**① 起因**：批 BS 把 CI 里跑的 5 个探针脚本**纳入「整行锚定」适用范围**
⇒ 它们的**判定行**不许被掏空了 ⇒ 但**「失败上报」这条链**一直没人管：
`✗ ` 报错行 → `exit N` / `return 1` / `fail=1` → 脚本退出码 → CI 判红。
⇒ 中间那一环被摘掉 ⇒ **断言变空转**。

**② ⚠⚠⚨ 实测坐实的洞（行为级，不是推演）**

1. 造一个「**只让最后一条断言失败**」的假探针（把平台探针要的字段全报对，
   只让「有图标主题但有图标解析不到」那条失败）；
2. **未变异**时：探针 **exit 1**（失败会传出去）✅；
3. 把 `ci-platform-probe.sh` **最后一条** `✗ ` 报错后面的 `exit 1` 摘掉：
   ⇒ 探针 **exit 0**、并且照样打印「**✓ 平台探针通过**」
   ⇒ ⇒ **CI 假绿**（断言失败了，CI 报通过）；
4. 而**现有门全绿** —— `✗ ` 条数门数的是 **20 条报错行**，一条没少 ⇒ 绿。

⇒ ⇒ 「**探针的失败必须真的让 CI 失败**」这个承诺，**从来没有门**。

**③ ⚠⚠⚨ 为什么现有门看不见它**

那两条门数的是**不同的东西**：
「`✗ ` 条数门」数的是**报错文案行**；「失败上报」数的是**退出语句**。
⇒ 报错行还在、退出语句没了 ⇒ 前者绿、后者（不存在）⇒ **中间缺一环，整条链断**。

**④ 修法（一层）**

给每个探针脚本加一条「**失败上报语句的条数**」门项：

- 正则：`^[[:space:]]*(exit [1-9]|return 1|fail=1)$`
  ⇒ **整行锚定** ⇒ 审计器（批 BL/BM/BN/BR/BS 的适用范围）会查它 ⇒ 改回盯串就 rc=8；
- 期望值**逐脚本校准**：
  `ci-platform-probe.sh` **22** / `ci-docs-lang-probe.sh` **10** /
  `ci-divider-probe.sh` **9** / `probe-agent-tool-surface.sh` **11** /
  `ci-orphan-probe.sh` **6**；
- ⇒ 摘掉任何一条、或把它改成 `exit 0` / `fail=0` ⇒ 条数变少 ⇒ **必红**。

**⑤ ⚠⚠⚨ 口径必须说清楚（不是 1:1 配对）**

`ci-platform-probe.sh` 的 **22** 条里有：辅助函数的**内层报错 + 外层报错**（多出来）、
**awk 程序内部**的 `exit 1`（也属于结构断言的失败链）；
`probe-agent-tool-surface.sh` 的 **11** 条里有 2 条 `exit 3`（**SKIP**，语义是
「未验证，不算通过」⇒ 也是失败）。
⇒ ⇒ **只钉总数，不钉配对** ⇒ 门项标签里如实写明。
⇒ ⇒ 后果（如实记着）：「把一条 `✗ ` 改成**两个**失败上报」这种改法**总数会变** ⇒ 仍红。

**⑥ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **只覆盖批 BS 范围内的 5 个探针** ⇒ `scripts/` 下还有 **11** 个断言脚本
  （共 16 个）没被这条门覆盖 ⇒ 逐批推进；
- ⚠ **静态口径**：失败上报若写成别的花样（如 `exit $RC`、`command || exit`）
  ⇒ 计数会掉 ⇒ 红 ⇒ 会显眼，但要改门项；
- ⚠ **总数口径不是配对口径** ⇒ 「一条 `✗ ` 配两条失败上报」会改变总数 ⇒ 红
  ⇒ 但「总数不变地把一条失败上报换成另一条」这类改法躲得过（已知边界）。

**⑦ 落门 / 判据**

- 门项物理行数 **823 → 828**（+5）；执行次数 **826 → 831**；
  门项总数基线 `ci-wiring-gates.baseline` = **823 → 828**。
- 豁免表**不变**（11 条）—— 新门项是**整行锚定**的 ⇒ 不需要豁免。
- 接线门 **831** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 11/11 真红**（24 条断言全绿）：
  H0/H0b 基线（5 条新门项全绿 + 审计器绿）/
  H1–H5 **5 个探针脚本**：每条都断言「**旧门（`✗ ` 条数门）在变异后仍绿**（证明旧门有洞）
  **且新门在变异后红**（证明新门有牙）**」/
  H6 ⚠ **行为级**：变异后探针**仍会报错**且 **exit 0**（⇒ 假绿坐实），
  未变异时 **exit 1** ⇒ **本批核心证据**/
  H7 新门项被改回**盯串** ⇒ 审计器 **rc=8**/
  H8 改门项总数基线 ⇒ rc=6 /
  H9 删门项 ⇒ rc=6 /
  H10 审计器**报告模式** rc=0。
  累计 **450/450**；**零产品代码改动**。
- **视觉变化**：无（只动判据层与文档；快照零变化）。

### E.2ad helper 型断言脚本：「失败助手」与「断言清单」都要有门（批 BU）

**① 起因**：批 BT 给 5 个探针脚本补了「失败上报不许被摘掉」的门
⇒ 但 `scripts/` 下共 **16** 个断言脚本 ⇒ 剩下的怎么办？
⇒ ⇒ 逐个盘点（**实测，不靠印象**）后发现：**这 3 个脚本的失败上报写法与别的不同**
—— 它们用**助手**统一报错：

| 脚本 | 助手定义行 | `die`/`fail` 调用 | `✗ ` 标记数 |
|---|---|---|---|
| `build-deb.sh` | `die() { echo "✗ build-deb: $*" >&2; exit 1; }` | **20** | **1** |
| `probe-deepin-tray.sh` | `fail() { echo "✗ $1" >&2; exit 1; }` | **7** | **1** |
| `probe-sni-icon.sh` | `fail() { echo "✗ $1" >&2; exit 1; }` | **10** | **1** |

**② ⚠⚠⚨ 实测坐实的洞**

`✗ ` 标记**只在助手体内** ⇒ 于是有**两个**洞：

1. **「`✗ ` 条数门」对它们形同虚设** —— 数出来只有 **1**（助手在 ⇒ 绿）
   ⇒ 删掉任意一条断言调用，门照样绿
   ⇒ ⇒ 批 BC 承诺的「**清单不许被删**」对它们**从来没兑现过**；
2. **助手里的 `exit 1` 被摘掉 ⇒ 所有断言变空转**（同批 BT 的洞）
   ⇒ **行为级实测**：把 `probe-deepin-tray.sh` 的 `fail` 助手改成 `exit 0`
   ⇒ 喂一个不存在的程序 ⇒ **未变异 exit 1**（失败传出去）、
   **变异后 exit 0** ⇒ 而且**照样打印 `✗` 报错** ⇒ 「**报了错却报成功**」⇒ **CI 假绿**。

**③ 修法（两层）**

① **助手定义行必须整行锚定** ⇒ 助手被掏空（`exit 1` 没了）⇒ 红；
② **助手调用点数必须恰好 N**（20 / 7 / 10）⇒ 删掉任意一条断言调用 ⇒ 红。

**④ ⚠⚠⚨ 口径为什么不能行首锚定（实测）**

助手调用常写在行中（`[ -f "$BIN" ] || die "..."`）
⇒ 只用 `^` 锚行首会**少数**（实测 build-deb.sh **20 → 5**）
⇒ 计数必须按**调用点**计（不限行首）⇒ ⚠ **强度弱于行首锚定**
⇒ **如实记为已知边界**（行尾注释理论上能冒充）。
⚠ 试过「语句起始锚」（`(^|‖|&&|;)`）⇒ **行数对不上**
（`probe-sni-icon.sh` 的 `PARSE_FAIL*) fail "…"` 是 `case` 分支 ⇒ 漏 1 处）
⇒ ⇒ 只能用**词边界**口径（`\b(die|fail) "`）⇒ 计数 = 20 / 7 / 10。

**⑤ ⚠⚠⚨ 这次只收了哪 3 个、其余为什么没收（如实记着）**

- ✅ 收：`build-deb.sh` / `probe-deepin-tray.sh` / `probe-sni-icon.sh`
  —— 它们的断言清单**从来没门**，且失败上报**从来没门**；
- ❌ 不收 `ci.sh` / `ci-d2.sh` / `smoke.sh`：它们的 `✗ ` 是**错误消息**
  （不是「每个错误消息对应一条断言」的分支）⇒ 删一条消息**不等于**删一条断言
  ⇒ 「清单不许被删」这条承诺**对它们不成立**；
- ❌ 不收 `ci-wiring.sh`：它的 `✗ ` 是**门项自己的失败文案**（不是断言清单）
  ⇒ 且它的失败上报路径**已由批 BO 三层钉法**（per-函数 + 总数 + 注册表）管着
  ⇒ **不重复覆盖**；
- ❌ 不收两个 `.py`：它们的输出标记不是「一条断言一个标记」形态
  ⇒ 且 `ci-tautology-check.py` 的自检样例**已由批 BQ 的 9 条样例条数门**管着。

**⑥ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **调用点数门强度弱于行首锚定**（行尾注释理论上能冒充）
  ⇒ 更强的做法是把助手调用**改成每条单独一行**（那样就能行首锚定）⇒ **本批不做**（改动面大、风险高）；
- ⚠ 这 3 个脚本**不在**「整行锚定」的适用范围里 ⇒ 那 3 条调用点数门是**盯串**形态
  ⇒ 将来若把它们纳入适用范围 ⇒ 这 3 条需要**显式豁免**（批 BN 机制）；
- ⚠ 只覆盖这 3 个 ⇒ 其余断言脚本的「清单」形态**各不相同** ⇒ 逐批推进。

**⑦ 落门 / 判据**

- 门项物理行数 **828 → 834**（+6）；执行次数 **831 → 837**；
  门项总数基线 `ci-wiring-gates.baseline` = **828 → 834**。
- 豁免表**不变**（11 条）—— 这 3 个文件不在适用范围 ⇒ 盯串门项不需要豁免。
- 接线门 **837** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 11/11 真红**（20 条断言全绿）：
  H0/H0b 基线（6 条新门项全绿 + 审计器绿）/
  H1–H3 **3 个助手定义行**被掏空（`exit 1` → `exit 0`）⇒ 定义行门红
  **且 `✗ ` 标记数不变（1 → 1）⇒ 现有口径看不见** /
  H4–H6 **3 条断言调用被删** ⇒ 调用点数门红 **且 `✗ ` 标记数不变** /
  H7 ⚠ **行为级**：未变异 **exit 1**、变异后 **exit 0** 且**仍打印 `✗` 报错**
  ⇒ **本批核心证据**（「报了错却报成功」⇒ CI 假绿）/
  H8 改门项总数基线 ⇒ rc=6 / H9 删门项 ⇒ rc=6 / H10 报告模式 rc=0。
  累计 **461/461**；**零产品代码改动**。
- **视觉变化**：无（只动判据层与文档；快照零变化）。

### E.2ae 无头路径的收尾：「退出时 QApplication 必须还活着」——CI 偶发段错误的真身（批 BV）

**① 起因**：CI 偶发段错误（探针退出码 **139**）一直只知其然不知其所以然
⇒ 前几批只做到「崩了要说清是什么信号」（批 AZ 的崩点可诊断三件套）
⇒ 但**崩在哪**没人知道 ⇒ 本批把它挖到根因，并给「不许回到那个坑」落门。

**② ⚠⚠⚨ 取证过程（不是推演，全部实测）**

| 步骤 | 手段 | 结论 |
|---|---|---|
| ① 崩溃那次的 CI 日志 | `/tmp/az-bh-ci.log`（3215B） | 是**完整 `ci.sh` 运行**，崩在第 4 步；崩的是 `--platform-probe` 脚本里 **dpr=2 那趟**；日志末行 = `✗ QT_SCALE_FACTOR=2 下 platform-probe 退出码 139` |
| ② 崩点在哪 | 自写 core 解析器（`/tmp/az-core-v4.py`） | 崩溃线程 rip 落在 **libQt6Core 的 `QCoreApplication::notifyInternal2`**，故障指令 `mov (%rdi),%rax`，**rdi = 0** |
| ③ 线程是谁 | NT_PRSTATUS 清单 + `/proc/<pid>/task` 实测探针进程的线程 | 探针进程正好 3 个线程：`deepDolphin` / **`QDBusConnection`** / `DConfigGlobalTh`；core 里也正好 3 个 ⇒ 崩溃那个是 **`QDBusConnection` 线程**（栈上有 `QEventLoop::exec` ⇒ 跑事件循环的线程） |
| ④ 为什么是 NULL | 反汇编 `notifyInternal2` | `159d91 lea ...,%rbp`（rbp = `&QCoreApplication::self`）→ `159d98 cmpq $0x0,0x0(%rbp)`（**第一次读：非空，通过**）→ `159dc3 call QInternal::activateCallbacks`（**这里主线程把 self 置空**）→ `159de1 mov 0x0(%rbp),%rdi`（**第二次读：已是 NULL**）→ `159dec mov (%rdi),%rax`（**崩**） |
| ⑤ 谁置空的 | 反汇编 `QCoreApplication::~QCoreApplication()` | `15bee7 lea ...` + **`15beee movq $0x0,(%rax)`** ⇒ 写的**正是** `QCoreApplication::self` ⇒ **析构 QApplication 会把 self 置空** |
| ⑥ 为什么 core 里看到的是「重发」而不是原故障 | NT_SIGINFO 解析 | `si_code = -6 (SI_TKILL)`、`si_pid = 自己的 pid` ⇒ 是**我们自己**的 `CrashHandler` 在 handler 里 `raise(sig)` 重发的（信号在 handler 里被自动屏蔽 ⇒ `raise` 只是挂起 ⇒ 恢复时按**原故障现场**落 core ⇒ 崩点寄存器仍在 core 里，但 `si_addr`/`si_code` 已被重发信息顶掉） |

**③ ⚠⚠⚨ 根因（一句话）**

> **主线程析构 `DApplication`（= QApplication）的同一时刻，`QDBusConnection` 后台线程正在
> `QCoreApplication::notifyInternal2()` 里派发事件** —— 它先读一次 `self` 判非空（通过），
> 隔一个函数调用再读时已被置空 ⇒ `mov (%rdi),%rax` **解引用 NULL** ⇒ **SIGSEGV**。

而探针的收尾**正好**踩在这个窗口上：
`headlessPlatformProbe()` 的 `::_exit(rc)` 写在 app 作用域**之外**
⇒ 作用域一闭合就先析构 app ⇒ 竞态窗口就在那儿。
⚠ 旁证：同一仓里另外两个无头探针（`--docs-lang-probe` / `--divider-probe`）的 `::_exit`
**写在 app 作用域之内** ⇒ 一直是安全的 ⇒ **只有平台探针是那个形状**。

**④ 修法（两层）**

① **产品侧**：所有无头路径（快照 / 色样张 / 平台探针 / 文档语言探针 / 分隔线探针）
   统一走**唯一收尾出口** `probeExit()` ——
   它在**退出那一刻**报一个**可断言的事实** `appAlive=<0|1>` 再 `_exit`
   ⇒ **退出时 QApplication 还活着**（app 永不析构）⇒ 竞态不存在。
   ⚠ 平台探针的 `QSystemTrayIcon` 单独一个作用域 ⇒ 托盘图标**仍在退出前被摘掉**（真机不留残影）。

② **CI 侧**：三个探针脚本**各断言** `appAlive=1`（平台探针**两跳**都断言）
   ⇒ 那个竞态**从「偶发」变成「必红」**：
   退出点一旦被挪回 app 作用域之外 ⇒ 事实变 0 ⇒ 门立刻红。

③ **顺带**：`ci-platform-probe.sh` / `ci-docs-lang-probe.sh` / `ci-divider-probe.sh`
   里探针调用的 **`2>/dev/null` 全去掉** ⇒ 探针崩了时 `CrashHandler` 的**栈回溯（崩点）**
   能进 CI 日志 ⇒ 以前只剩一句「退出码 139」。

**⑤ 落门 / 判据（本批新增 9 条）**

- 3 条「`appAlive=1` 断言不许被删」（平台 **2** 处 / 文档语言 **1** 处 / 分隔线 **1** 处，**整行锚定**）；
- 3 条「`appAlive` 事实不许被删 / `_exit` 只许在 `probeExit` 里 / 收尾必须走 `probeExit`」
  （`src/main.cpp`：`appAlive=%d` 恰好 **1**、`::_exit(rc);` 恰好 **1**、`probeExit(` 恰好 **8**）；
- 3 条「探针的 **stderr 不许被扔掉**」（`arch_forbid` 三个探针脚本各 1 条）。

⚠ 跟着改的门项**原地替换、不增行**（批 BM 纪律）：
3 条「探针调用行」门项的正则去掉了 `2>/dev/null`；
3 条「真报错行」条数门 **20→22 / 10→11 / 9→10**；
3 条「失败上报语句」条数门 **22→24 / 10→11 / 9→10** ⇒ 说明文字里的数字**同步改**（批 BB）。

**⑥ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **本机没能复现那个段错误**（8 worker × 400 轮 × 2 跳 = **6400 次启动，0 次崩溃**）
  ⇒ ⇒ 修复效果**不是**用「复现率下降」证明的，而是用
  **「把退出点挪回 app 作用域之外 ⇒ `appAlive=0` ⇒ CI 必红」**这条**行为级负控**证明的
  ⇒ 即：**竞态被消除**（app 永不析构 ⇒ `self` 永不被置空）与
  **「万一它回来」必红**这两件事，都由负控钉住；
- ⚠ **`probe-agent-tool-surface.sh` 没收**（如实记着）：它**不构造 QApplication**（无本竞态），
  但它的探针**退出码没被检查** ⇒ 探针崩了会被当成「引擎未找到」的 **SKIP（exit 3）**
  ⇒ 「**崩了不许被当成 SKIP**」这条承诺**还没有门** ⇒ **下一批处理**；
- ⚠ **`appAlive` 事实只在无头路径上有** ⇒ GUI 主路径没有对应断言（GUI 本来就该正常析构）；
- ⚠ 「事实的**求值位置**」是这条承诺的命根子 ⇒ 若有人把 `fprintf` 从 `probeExit` 里挪走
  ⇒ 事实仍在（`appAlive=%d` 那条门也仍绿）⇒ **只有行为级负控抓得住**
  ⇒ 故负控里明确包含「事实被删 ⇒ CI 必红」这一条。

**⑦ 落门 / 判据（数字）**

- 门项物理行数 **834 → 843**（+9）；执行次数 **837 → 846**；
  门项总数基线 `ci-wiring-gates.baseline` = **834 → 843**。
- 豁免表**不变**（11 条）—— 新门项是整行锚定的（`arch_forbid` 族按惯例不审锚定形态）。
- 接线门 **846** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 20/20 真红**（20 条断言全绿）：
  H0 基线（9 条新门项全绿 + 审计器绿 + 未变异时脚本绿且报 `appAlive=1`）/
  H1 ⚠ **行为级（旗舰）**：把退出点挪回 app 作用域**之外**（= 复现原 bug 的形状）
  ⇒ 探针报 **`appAlive=0`** ⇒ **CI 门必红**（报的还是 appAlive 那条）⇒ **本批核心证据** /
  H2 ⚠ **行为级**：把 `appAlive` 事实整行删掉 ⇒ 探针报 `appAlive=缺失` ⇒ **CI 门必红** /
  H3 CI 里的 `appAlive` 断言被删 ⇒ 对应门红 /
  H4 `2>/dev/null` 吞回去 ⇒ 整行锚定门 + forbid 门**都红** /
  H5 收尾改回裸 `_exit` ⇒ `::_exit` 条数门 + `probeExit` 条数门**都红** /
  H6 `appAlive` 事实被删 ⇒ 事实条数门红。
  累计 **481/481**。
- ⚠⚠⚨ **本批是「判据层批次」里的例外**：**有产品代码改动**（`src/main.cpp` 的收尾口径）
  —— 理由：那个竞态**在产品代码里**，判据层改不掉它 ⇒ 改产品 + 落门，两件事一起做。
  改动面：只动**无头路径的收尾**（5 条路径），**不碰任何业务逻辑与界面**。
- **视觉变化**：无（只动收尾口径、判据层与文档；快照零变化）。


### E.2af 「探针崩了」不许被当成「未验证」（SKIP）（批 BW）

**① 起因**：批 BV 把「崩点不许被吞」做进了三个探针脚本，
但 `probe-agent-tool-surface.sh` 当时**没收**（如实记成了已知边界）⇒ 顺手查了一遍，发现**更糟**。

**② ⚠⚠⚨ 实测坐实的洞**

那个脚本的探针调用**根本没接退出码**：

```sh
OUT="$(QT_QPA_PLATFORM=offscreen "$BIN" --agent-tool-surface 2>/dev/null)"
if [ -z "$OUT" ]; then
    echo "SKIP: 引擎未找到（工具面探针需要真引擎）—— 本门**未验证**，不算通过"
    exit 3
fi
```

⇒ 它**只看「stdout 空不空」** ⇒ 于是三种完全不同的事被塞进同一支：

| 实际情况 | stdout | 旧脚本的判法 | CI 看到什么 |
|---|---|---|---|
| 引擎真的没找到 | 空 | SKIP（exit 3） | ‣ SKIP（未验证）—— **对** |
| **探针崩了（139）** | 空 | **SKIP（exit 3）** | ‣ SKIP（未验证）—— **错！** |
| **探针说成功却没输出** | 空 | **SKIP（exit 3）** | ‣ SKIP（未验证）—— **错！** |

`ci.sh` 第 13 步看到 exit 3 ⇒ 打印「‣ SKIP agent 工具面门」⇒ **CI 整体照样绿**
⇒ ⇒ 「**崩了**」被伪装成「**环境不具备**」⇒ 崩点彻底看不见。

**③ 修法（三层）**

① **产品侧**：「引擎未找到」用**专属退出码 3**（= 未验证），其它失败用 1
⇒ 「未验证」与「失败」在**退出码**这一层就分开了；
② **CI 侧**：脚本**接住退出码**并分诊（**3 = SKIP / 其它非 0 = 失败**），
且 stderr **落盘、失败时原样吐出** ⇒ 崩点（`CrashHandler` 的栈回溯）看得见；
③ **顺带**：工具面探针的收尾也收口到 `probeExit`（批 BV 的口径）
⇒ ⇒ 「**所有无头路径统一走 `probeExit`**」这句话**这才真的成立**。

**④ ⚠⚠⚨ 行为级实测（假探针，三种形态）**

| 假探针 | 新脚本的判法 | 旧脚本的判法 |
|---|---|---|
| `kill -SEGV $$`（退出码 139） | **exit 1（失败）**，并把 stderr（崩点）吐出来 | **exit 3（SKIP）** ⇒ **CI 假绿** |
| `exit 3`（引擎未找到） | **exit 3（SKIP）**（语义**没变**） | exit 3（SKIP） |
| `exit 0` 但无输出 | **exit 1**（假绿被抓住） | exit 3（SKIP）⇒ 假绿 |

**⑤ 落门 / 判据（本批新增 5 条）**

- 3 条「**退出码分诊**必须原样存在」（`arch_need_count`，**整行锚定**）：
  探针调用行必须是 `… 2>"$ERR_FILE")" || PROBE_RC=$?`、
  必须有 `-eq 3`（SKIP 那一支）与 `-ne 0`（失败那一支）；
- 1 条「退出码 0 却无输出 ⇒ 必须判失败」（盯那条 `✗` 报错行，**整行锚定**）；
- 1 条（产品侧）「引擎未找到 ⇒ 必须用**专属的『未验证』退出码 3**」
  （`src/main.cpp` 里 `probeExit(3);` 恰好 **1** 处）。

⚠ 跟着改的门项**原地替换、不增行**（批 BM 纪律）：
「真报错行」条数门 **9 → 11**、「失败上报语句」条数门 **11 → 13**（都在
`probe-agent-tool-surface.sh` 上）；批 BV 的「收尾必须走 `probeExit`」条数门 **8 → 11**
（工具面探针也收口了）⇒ 说明文字里的数字**同步改**（批 BB）。

**⑥ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **这个脚本里没有「`2>/dev/null` 一律不许出现」的门** ——
  因为它**有两处合法用法**（`mktemp 2>/dev/null` 与 `[ … ] 2>/dev/null`）
  ⇒ 加 forbid 门会**假红** ⇒ 改用「**盯住探针调用那一行**」的整行锚定门
  ⇒ ⚠ **强度弱于「全文件 forbid」**（换个花样重定向仍躲得过）⇒ **如实记着**；
- ⚠ 「崩了」与「未验证」的区分**依赖探针自己用 3 表示未验证**
  ⇒ 若将来新增别的「未验证」情形 ⇒ 必须**同样用 3**，否则会被判成失败（响亮失败，可接受）；
- ⚠ 别的断言脚本（`scripts/` 下共 16 个）**还有多少没接探针退出码**，本批**没逐个查**
  ⇒ 「崩了不许被当成 SKIP」这条承诺目前**只对这一个脚本有门** ⇒ 逐批推进。

**⑦ 落门 / 判据（数字）**

- 门项物理行数 **843 → 848**（+5）；执行次数 **846 → 851**；
  门项总数基线 `ci-wiring-gates.baseline` = **843 → 848**。
- 豁免表**不变**（11 条）。
- 接线门 **851** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 16/16 真红**（16 条断言全绿）：
  H0 基线（5 条新门项全绿 + 审计器绿 + 真探针脚本绿）/
  H1 ⚠ **行为级（旗舰）**：**旧形态下**假探针崩了 ⇒ **exit 3（SKIP）⇒ 假绿坐实**；
  **新形态下** ⇒ **exit 1（失败）**、报出「退出码 139」、**崩点被吐出来** /
  H2 引擎未找到（exit 3）⇒ 脚本**仍 exit 3（SKIP）** ⇒ 语义**没被改坏** /
  H3 退出码 0 却无输出 ⇒ **exit 1**（假绿被抓住）/
  H4 退出码分诊被摘掉 ⇒ **3 条分诊门都红** /
  H5 产品侧「未验证」退出码从 3 改回 1 ⇒ 对应门红 /
  H6 收尾改回裸 `_exit` ⇒ `probeExit` 条数门红。
  累计 **497/497**。
- **视觉变化**：无（只动判据层、探针收尾与文档；快照零变化）。


### E.2ag 「崩了」必须被判成「崩了」：退出码不许被吞、stderr 不许顶替 stdout（批 BX）

**① 起因**：批 BW 标了「其余断言脚本还没逐个查」⇒ 本批**逐个盘点**了
`scripts/` 下全部 16 个断言脚本对「我们自己的二进制 / 探针脚本」的调用
⇒ 盘出**两处具体的洞**（逐行看的，不是印象）。

**② ⚠⚠⚨ 洞 ①（行为级·假绿）**：`check-deb-layout.sh` ⑧「空环境下能跑 --version」

原来是：

```sh
VOUT="$(env -i "$BIN" --version 2>&1 | head -3)"
if printf '%s' "$VOUT" | grep -q .; then
    ok "可执行在**空环境**下能跑起来（--version：…）"
else
    no "可执行在空环境下跑 --version 没有输出（装完可能起不来）"
fi
```

⇒ 三处叠在一起：
① **退出码完全没查**；② **`2>&1` 把 stderr 合并进 stdout**；
③ 判据只是「**有输出**」。

⇒ **实测**：造一个「先往 stderr 打一行警告、再 `kill -SEGV` 崩掉」的假二进制
⇒ 这一门判 **✓ 可执行在空环境下能跑起来** ⇒ **假绿**
（换句话说：**D7 的「装完能不能用」准验收，对一个段错误崩掉的包判「能跑」**）。

**③ ⚠⚠⚨ 洞 ②（形态级·诊断失真）**：`ci-platform-probe.sh` 的 dpr=2 那跳

原来是「**下一行**再取 `$?`」：

```sh
dpi_b_out="$(QT_SCALE_FACTOR=2 "$BIN" --platform-probe)"
dpi_b_rc=$?
```

⇒ `$?` 只对**紧邻的上一条**命令有效 ⇒ 中间插一行 ⇒ 退出码被换成**别人的**
⇒ 崩溃被伪装成「探针没输出」⇒ 门虽然还是红的，但**诊断失真**（排障方向被带偏）。

**④ 修法**

① `check-deb-layout.sh` ⑧：**查退出码**（非 0 ⇒ 判失败）+ **stderr 不混进 stdout**
（stdout 单独取，stderr 原样透出 ⇒ 崩点看得见）；
② `ci-platform-probe.sh`：**退出码改成同行取**（`|| VAR=$?`）⇒ 形态固定，
插一行也断不了（批 BV 已在另外三跳用同一形态）；
③ 同理，`dpi_struct_assert()` 里那处 `dpi_a_rc=$?` 也改成同行取。

**⑤ ⚠⚠⚨ 盘点结论（顺带记下：哪些脚本本来就是安全的）**

| 脚本 | 对「我们自己的二进制」的调用 | 退出码处理 | 结论 |
|---|---|---|---|
| `smoke.sh` | `if "$BIN" --selfcheck; then` | **查**（`if`） | 安全 |
| `ci-platform-probe.sh` | 3 处 | **查**（批 BV/BX 后全部同行取） | 安全 |
| `ci-docs-lang-probe.sh` / `ci-divider-probe.sh` | 各 1 处 | **查**（批 BV） | 安全 |
| `probe-agent-tool-surface.sh` | 1 处 | **查 + 分诊**（批 BW） | 安全 |
| `check-deb-layout.sh` | 1 处（⑧） | ❌ **没查** ⇒ **本批修** | 洞 ① |
| `contract-check.sh` | 20+ 处（都是「解析型」探针） | 判据是**输出内容** ⇒ 崩了 ⇒ 内容空 ⇒ 比对失败 ⇒ 响亮失败 | 安全 |
| `ci.sh` / `ci-wiring.sh` | 步 / 门 | **查** | 安全 |
| `build-deb.sh` / `build.sh` / `dev-run.sh` / `setup-deps.sh` / `probe-deepin-tray.sh` / `probe-sni-icon.sh` | 不跑我们的二进制（只读文件 / 调外部工具） | — | 不适用 |

**⑥ 落门 / 判据（本批新增 2 条 + 跟着改的原地替换）**

- 新增 2 条（`check-deb-layout.sh`，**整行锚定**）：
  ① 「`--version` **必须查退出码**且 **stderr 不许混进 stdout**」
  （盯 `VOUT="$(env -i "$BIN" --version)" || VRC=$?` 那一行 ⇒ **一条门同时排除掉 `2>&1` 那种写法**）；
  ② 「退出码非 0 **必须判失败**」（盯 `if [ "$VRC" -ne 0 ]; then` 那一行）。
- **原地替换**（批 BM 纪律，不增行）：
  ① 批 BS 的「dpr=2 那跳」门项：正则从「只看那一行」改成「**那一行 + 同行取退出码**」，
  说明文字同步补上这一层含义；
  ② `check-deb-layout.sh` 的「ok/no 清单」条数门 **14 → 15**（多了一条失败分支）
  ⇒ 说明文字同步改（批 BB）。

**⑦ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ 本批的盘点是**按「调用我们自己的二进制 / 探针脚本」这个口径**做的
  ⇒ 「调用外部工具（`readelf` / `xprop` / `dpkg-deb` …）后拿它的退出码当判据」这类
  **不在本批范围内**（它们的失败通常直接进 `die`/`no`，风险形态不同）⇒ 下一批可议；
- ⚠ `check-deb-layout.sh` **不在**「整行锚定」的适用范围里 ⇒ 本批那 2 条门
  **恰好**写成整行锚定形态（更强），但**审计器不会**因为将来有人把它写弱而红
  ⇒ ⚠ **如实记为已知边界**（要更强 ⇒ 把它纳入适用范围）；
- ⚠ 「stderr 原样透出」意味着 CI 日志里会多出 DTK 的噪声行
  ⇒ 可接受（崩点可见比日志干净重要），但**没有门管住噪声量**。

**⑧ 落门 / 判据（数字）**

- 门项物理行数 **848 → 850**（+2）；执行次数 **851 → 853**；
  门项总数基线 `ci-wiring-gates.baseline` = **848 → 850**。
- 豁免表**不变**（11 条）。
- 接线门 **853** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 9/9 真红**（9 条断言全绿）：
  H0 基线（2 条新门项全绿 + 审计器绿）/
  H1 ⚠ **行为级（旗舰）**：假二进制（先打警告再段错误）
  ⇒ **旧形态判 ✓「能跑起来」（假绿坐实）** / **新形态判 ✗「退出码 139」** /
  H2 退出码检查被摘掉 ⇒ 对应门红 /
  H3「退出码非 0 ⇒ 判失败」那一支被摘掉 ⇒ 对应门红 /
  H4 dpr=2 那跳的退出码挪回「下一行取」⇒ 整行锚定门红。
  累计 **506/506**。
- **视觉变化**：无（只动判据层与 CI 脚本；快照零变化）。


### E.2ah 「失败计数不许被掏空」：计数器型断言脚本的 fail 计数必须真的有门（批 BY）

**① 起因**：批 BT/BU 把「失败上报」的门型收进了 `exit N` 形态的脚本
⇒ **计数器型**（`fail=$((fail+1))` + 末尾 `[ "$fail" -eq 0 ]`）的脚本**从来没被收过**。
⇒ 本批**逐个盘点了 `scripts/` 下全部脚本**的失败上报形态（逐个脚本 grep 的，不是印象）：

| 脚本 | 失败上报形态 | 失败计数点 | 结论 |
|---|---|---|---|
| `check-deb-layout.sh` | 计数器型 | **1** 处（唯一的 `no()` 助手） | **本批收** |
| `contract-check.sh` | 计数器型 | **39** 处（2 个助手 + 37 处行内） | **本批收** |
| 其余 14 个断言脚本 | `exit N` 形态 | — | 批 BT/BU 已收 |

⇒ **全仓只有这 2 个脚本是计数器型** ⇒ 本批一次收干净。

**② ⚠⚠⚨ 洞（行为级·假绿）**

计数器型脚本的失败判定链是**三环**：

```
① 报错（echo "  ✗ …"） ⇒ ② 计数（fail=$((fail+1))） ⇒ ③ 末尾判定（[ "$fail" -eq 0 ] 决定退出码）
```

⇒ **中间那一环被摘掉**（`fail=$((fail+1))` 被删 / 改成 `fail=$((fail+2))` /
换成别的写法 / 判定之前被 `fail=0` **复位**）⇒
**报错照打**（stderr 里明明写着「✗」）但**永远不计数** ⇒
末尾判定恒真 ⇒ 脚本 `exit 0` ⇒ **CI 假绿**。

⚠⚠⚨ **「复位」这一条尤其阴**：计数**一条不少** ⇒ 任何「数计数点」的门都抓不到它
⇒ 必须另有一条「**写 `fail` 的行数**」的门。

**③ ⚠⚠⚨ 行为级实测（假绿坐实）**

- **A1（`check-deb-layout.sh`）**：用 `dpkg-deb -b` 造一个**真会失败**的假包
  （`usr/bin/deepDolphin` 是个一启动就 `exit 1` 的脚本 + 缺 desktop/service/metainfo
  + 零字节图标）⇒ 真跑脚本 ⇒ **rc=1、5 条失败**。
  ⇒ 把 `no()` 里的 `; fail=$((fail+1))` 摘掉 ⇒ **rc=0、0 条失败**，
  而 stderr 里**照样打着一行「✗」** ⇒ **假绿坐实**。
- **A2（`contract-check.sh`）**：在脚本副本里**注入一条真失败**
  （`check "注入失败" "False" '{}'` ⇒ 走**真实** `check()` 助手 ⇒ 真实计数器 ⇒ 真实判定）
  ⇒ **rc=1、1 条失败**。
  ⇒ 把 `check()` 助手的失败计数摘掉 ⇒ **rc=0**，
  而输出里**照样打着「✗ 注入失败」** ⇒ **假绿坐实**。
- **A3（复位这一类）**：在 `check-deb-layout.sh` 副本里把 `fail=0` 插到**摘要行之后、判定行之前**
  ⇒ **rc=0**，而摘要**照样打印「5 failed」** ⇒ **摘要与退出码当场打架** ⇒ 假绿的现场证据。

**④ 修法（本批只动判据层 ⇒ 零产品代码改动）**

① 两个计数器型脚本的**失败计数点 / 成功计数点 / 末尾判定行**逐条**整行锚定**；
② 计数点按**形态**分组钉住（助手行 / 独立成行 / 带 `>&2` 的自由文案 / `|| { …; }` 形态）
⇒ 「删一处 + 补一处同形态」也躲不过（**总数不变也红**）；
③ 加「**写 `fail` 的行数**」门 ⇒ 「判定前把计数器复位」也红；
④ 两个脚本**纳入审计器的「整行锚定」适用范围**
⇒ 将来这些门被写弱（从整行锚定改回盯串）审计器就会红
（**收掉批 BX 留下的已知边界**）。

**⑤ 落门 / 判据（本批新增 12 条 + 原地替换 1 条）**

| # | 目标 | 盯什么 | 期望次数 |
|---|---|---|---|
| H1 | `check-deb-layout.sh` | `no()` 定义行（**失败计数点本体**） | 1 |
| H2 | `check-deb-layout.sh` | `ok()` 定义行（**成功计数点本体**） | 1 |
| H3 | `check-deb-layout.sh` | 末尾判定行 `[ "$fail" -eq 0 ]` | 1 |
| H4 | `check-deb-layout.sh` | **写 `fail` 的行数**（1 初始化 + 1 计数） | 2 |
| H5 | `check-deb-layout.sh` | 失败**增量**行数 | 1 |
| C1 | `contract-check.sh` | 两个助手的失败计数行 | 2 |
| C2 | `contract-check.sh` | 独立成行的增量 | 31 |
| C3 | `contract-check.sh` | 带 `>&2` 的自由文案增量 | 4 |
| C4 | `contract-check.sh` | `\|\| { …; }` 形态的增量 | 2 |
| C5 | `contract-check.sh` | 增量**总数** | 39 |
| C6 | `contract-check.sh` | 末尾判定行 | 1 |
| C7 | `contract-check.sh` | **写 `fail` 的行数**（1 初始化 + 39 计数） | 40 |

⇒ 12 条**全部是整行锚定**（批 BQ 口径：中间只许有界通配，如 `[^"]*`）。
⇒ **原地替换**（批 BM，不增行）：批 BR 那条「锚定形态适用范围常量」的门项
正则与说明文字同步（范围 +2 个脚本）。

**⑥ ⚠⚠⚨ 豁免表（11 → 13）**

两个脚本进了适用范围 ⇒ 它们的**既有**「清单调用数」门落在锚定适用范围里 ⇒ 但它们
**天生不能**整行锚定（数的是**调用点**，后面是自由文本）⇒ 显式豁免并逐条写理由：

- `check-deb-layout.sh` 的 `^[[:space:]]*(no|ok) "`（15 处调用）
- `contract-check.sh` 的 `^[[:space:]]*check`（93 处调用）

⇒ 豁免表仍靠**双向配准**钉死（豁免表 ≡「非锚定门项」集合 ⇒ 条数是推导出来的，批 BN）。

**⑦ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ 「写 `fail` 的行数」是**行数**口径 ⇒ 一行里写两次 `fail=` 只算 1 行
  ⇒ 但「增量行数」那条数的是行数、形态分组门数的是行数 ⇒ **三者口径一致**；
- ⚠ 计数点**总数**（39 / 1）是**不许增不许减**的基线 ⇒ 将来合法新增一条失败路径
  ⇒ 必须同步更新期望值（与本仓其它条数基线门同规矩，批 BB 口径）；
- ⚠ 「自由文案」那一类（C3）用 `[^"]*` 有界通配钉结构 ⇒ **文案改了不影响门**
  ⇒ 但也意味着**文案内容本身**不被这些门管（那是「报错文案」门的职责，批 BT 已收）；
- ⚠ 本批**没有**覆盖「新增一条**不带计数**的失败路径」——
  即「有人新写了一条 `echo "  ✗ …"` 却忘了加 `fail=$((fail+1))`」
  ⇒ 抓得到它的是**报错行数 vs 计数行数**的**配对**关系
  ⇒ 本批的 12 条门只保证「**已有的**计数点不被摘、不被复位」
  ⇒ 配对关系是**下一批**的活（需要一个跨行配对门型）；
- ⚠ `contract-check.sh` 自己的两个 **SKIP 分支**（L37 引擎缺席 / L39 缺 python3）
  是 `exit 0` 形态 ⇒ 属批 BW 的「SKIP 不许被当成通过」家族
  ⇒ `ci.sh` 那侧已经先判过引擎在不在 ⇒ 但**脚本自己**的 SKIP 分支本批**没收**。

**⑧ 落门 / 判据（数字）**

- 门项物理行数 **850 → 862**（+12）；执行次数 **853 → 865**；
  门项总数基线 `ci-wiring-gates.baseline` = **850 → 862**。
- 豁免表 **11 → 13**（+2）。
- 接线门 **865** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 17/17 真红**（17 条断言全绿）：
  H0 未变异对照（每条门项**单独**跑 ⇒ 12 条门项全绿）/
  A1 ⚠ **行为级（旗舰）**：假包 ⇒ 摘掉 `no()` 的计数 ⇒ **rc=0 而 stderr 仍打「✗」**（假绿坐实）/
  A2 注入真失败 ⇒ 摘掉助手计数 ⇒ **rc=0 而仍打「✗ 注入失败」**（假绿坐实）/
  A3 判定前复位 ⇒ **rc=0 而摘要写着「5 failed」**（摘要与退出码打架）/
  H1–H5 / C1–C7：逐条变异 + **从 `ci-wiring.sh` 原文现抽那一条门项单独跑** ⇒ **12 条全红**；
  累计 **523/523**。
- **视觉变化**：无（只动判据层与文档；快照零变化）。

### E.2ai 「新增失败路径必须带计数」：报错行数 == 计数行数（配对门）（批 BZ）

**① 起因**：批 BY 给计数器型脚本的「失败计数点 / 末尾判定行」都落了整行锚定的门，
**但明确记下了一类它抓不到的洞**（如实记为已知边界，不是推演）。

**② ⚠⚠⚨ 洞**

批 BY 的门保证「**已有的**计数点不被摘、不被复位」，
⇒ 但**新增**一条失败路径时，如果新代码只写了

```sh
echo "  ✗ …" >&2          ← 报错（照打）
（忘了 fail=$((fail+1))）  ← 计数（漏了）
```

⇒ 末尾判定 `[ "$fail" -eq 0 ]` **看不到**这条失败
⇒ 脚本 `exit 0` ⇒ **CI 假绿**。

**③ ⚠⚠⚨ 为什么两条独立的「恰好 N 次」门抓不到它**

「报错行数 == 39」与「计数行数 == 39」是**两个互不知情**的门：

| 步骤 | 报错门 | 计数门 | 脚本行为 |
|---|---|---|---|
| 初始 | 39 == 39 ✅ | 39 == 39 ✅ | 绿 |
| 新增一条**不带计数**的报错行 | 40 ≠ 39 🔴 | 39 == 39 ✅ | **仍绿**（门红≠脚本红） |
| 人把**报错门**的期望值改成 40 | 40 == 40 ✅ | 39 == 39 ✅ | **两门都绿，但那条新报错永远不计数** |

⇒ 必须有**一条**门**同时**盯住两个数 ⇒ 它们的**差恒为 0**。

**④ ⚠⚠⚨ 行为级实测（假绿坐实）**

用 `dpkg-deb -b` 造一个**全部 9 项检查都通过**的假包（可执行能跑 `--version`、
desktop / service / metainfo 齐全、图标非空）⇒ 真跑脚本 ⇒ **rc=0、0 条失败**。
⇒ 在脚本副本里**注入一条只报错不计数的失败路径** ⇒ **rc=0、0 条失败**，
而 stderr 里**照样打着一行「✗」** ⇒ **假绿坐实**。

**⑤ 修法：本批新增一个门型（不是新增一条门项）**

`arch_need_count_pair <文件> <报错行正则> <计数行正则> <期望次数> <说明>`
⇒ **报错行数 == 计数行数 == 期望** ⇒ 差恒为 0。

⚠⚠⚨ **新门型必须进审计覆盖**（批 AR/AV 纪律：「审计器自己有盲区 ⇒ 那些门根本没被审」）
⇒ 三处都做了：

1. **门项行正则** `PAIR_COUNT_LINE`（属 count 族 ⇒ 被 `COUNT_FAMILY_LINE` 兜底保护
   ⇒ 写坏了会报「盲区」而不是静默失效）；
2. **门型清单登记**（`GATE_TYPES`）⇒ 「门型对拍」能算上它（不登记 ⇒ 对拍红）；
3. **期望校准**（`check_pair_count_gates`）⇒ 期望值必须 == 实际两个数
   ⇒ 「把期望改大来躲变异」没人盯的洞也堵上了。

**⑥ ⚠⚠⚨ 口径**

- 数的是**行数**（`grep -cE`）⇒ 一行里写两次只算 1 行；
- 报错行用 `echo "  ✗`（**两格缩进**）⇒ `exit N` 形态的报错行
  （`echo "✗ …"`，**无缩进**）**自然被排除** ⇒ 只盯**计数器型**的失败路径
  （实测：`check-deb-layout.sh` 的两条 `echo "✗ …"` 与 `contract-check.sh` 的
  `echo "✗ 引擎探活失败"; exit 1` 都在范围外 ⇒ 计数天然是 1/1 与 39/39）；
- 期望值是**不许增不许减**的基线（批 BB 口径）。

**⑦ 落门 / 判据（本批新增 2 条 + 原地替换 2 条）**

- 新增 **2** 条（`arch_need_count_pair`）：
  `check-deb-layout.sh`（报错 1 == 计数 1）+
  `contract-check.sh`（报错 39 == 计数 39）；
- **原地替换**（批 BM 纪律，不增行；批 BB 纪律：说明文字与期望值**一起改**）：
  ① 「`arch_` **门型函数的注册表**」**14 → 15**（新增了一个门型函数）
  + 说明补上「批 BZ：新增了门型 `arch_need_count_pair`（配对门）⇒ 14 → 15」；
  ② 「**全文失败上报的总数**」**35 → 37**（配对门带 2 处 `ARCH_FAIL=1`）
  + 说明补上「批 BZ：配对门带 2 处 `ARCH_FAIL=1` ⇒ 35 → 37」。

**⑧ ⚠⚠⚨ 负控（含增量价值证据）**

- **A0** 未变异对照：假包应全部通过（rc=0、0 条失败）；
- **A1** ⚠ **行为级（旗舰）**：注入一条只报错不计数的失败路径
  ⇒ **rc=0 而 stderr 仍打「✗」** ⇒ **假绿坐实**；
- **P1 / P2** 两条配对门各变异一次 ⇒ **都红**；
- **P1 / P2 增量价值**：**同一个变异**下，批 BY 的 4 条门
  （`BY-H4` / `BY-H5` / `BY-C5` / `BY-C7`）**仍全绿**
  ⇒ 证明**只有配对门**能抓这一类洞（新门型不是把已有门换个写法）。
  累计 **529/529**。

**⑨ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ 配对门保证的是「**总数相等**」，**不是**「**逐条相邻**」
  ⇒ 一条报错行与一条计数行**错位配对**（总数不变）它照样绿
  ⇒ 要真正的「逐条相邻」保证，得让脚本侧把「报错 + 计数」**收进同一行**
  （结构保证）或引入跨行门型 ⇒ **下一批可议**；
- ⚠ 期望值是**不许增不许减**的基线 ⇒ 将来合法新增一条失败路径必须同步更新；
- ⚠ 配对门数的是**行数** ⇒ 一行里同时有 1 条报错与 2 次计数，仍算 1 == 1
  ⇒ 「一次失败被数两次」这类错配它抓不到（由批 BY 的增量行数门间接兜着）。

**⑩ 落门 / 判据（数字）**

- 门项物理行数 **862 → 864**（+2）；执行次数 **865 → 867**；
  门项总数基线 `ci-wiring-gates.baseline` = **862 → 864**。
- 豁免表**不变**（13 条 —— 新门型是 `arch_need_count` 族但**不在**锚定适用范围里
  ⇒ 它的两个行模式正则**天然不能**整行锚定（数的是「有几行」，不是「判定行」）
  ⇒ 与批 BS 那批「报错文案行」门同性质，**按设计不审锚定形态**）。
- 接线门 **867** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 6/6 真红**（6 条断言全绿）。
- **视觉变化**：无（只动判据层与文档；快照零变化）。

### E.2aj 「失败上报出口」不许被摘掉：判据层与 CI 自己的出口都要有门（批 CA）

**① 起因（实测盘点，不是印象）**

批 BT 收了 **5** 个探针脚本、批 BU 收了 **3** 个 helper 型脚本、批 BY/BZ 收了 **2** 个
计数器型脚本 ⇒ 但「**失败上报出口**」这个承诺本身（脚本失败时**必须真的报出去**，
不许被摘掉、不许 fall through 到 0）**从来没在「判据层与 CI 自己身上」收过**。

逐个盘点 `scripts/` 下全部脚本的失败上报形态：

| 脚本 | 失败上报形态 | 出口数 | 状态 |
|---|---|---|---|
| `ci-wiring-audit.py` | `return N`（6 种失败码）+ `sys.exit(main())` | 16 + 1 + 2 | **本批收** |
| `ci.sh` | 整行 `exit N` | 27 | **本批收** |
| `ci-d2.sh` | 整行 `exit N` | 2 | **本批收** |
| `smoke.sh` | 整行 1 + **行内** 2 | 3 | **本批收** |
| `ci-tautology-check.py` | `return N` + `sys.exit(main())` | 3 + 1 | **本批收** |
| `bootstrap-deps.py` | `return N` + `sys.exit(main())` | 1 + 1 | **本批收** |
| 其余 11 个脚本 | `die "` / `fail "` / 计数器型 | — | 批 BU / BY / BZ 已收 |

**② ⚠⚠⚨ 洞 ①（行为级·假绿·旗舰）：判据层裁判自己的退出码契约没人守**

`ci-wiring-audit.py` 是**判据层的裁判** ⇒ 它的每个失败出口都是
「某一类判据失配 ⇒ 必须红」的**唯一通路**。

⇒ **实测**：把 `return 4`（「次数门没配准 ⇒ rc=4」）**整行摘掉**，
再让某条次数门的期望值失准 ⇒ 审计器**不再报 4**
⇒ fall through 到 `return 3 if outside else 0` ⇒ `outside` 为空
⇒ **rc=0** ⇒ **审计器对失准的门项报「全绿」** ⇒ **假绿坐实**。

**③ ⚠⚠⚨ 洞 ②（行为级·假绿·实测）：一个失败的门自己说「✓」**

`ci-d2.sh` 的最终判定：

```sh
if [ "$FAIL" != "0" ]; then
    exit 1
fi
echo "✓ D2 命中 ${D2_COUNT}/0（存量已清零，DS 单一真相源）"
```

⇒ 摘掉那个 `exit 1` ⇒ 脚本**明明已经检出失败**（打印了「✗ 豁免路径不存在」）
⇒ 却照样打印「**✓ D2 命中 0/0（存量已清零，DS 单一真相源）**」并 **exit 0**
⇒ **假绿坐实**。

**④ ⚠⚠⚨ 洞 ③（形态级）：`ci.sh` 的失败已被 `if` 分支消化**

`ci.sh` 顶部有 `set -euo pipefail` ⇒ 但失败命令的退出码被 `if` 的**条件**消费掉了
⇒ `set -e` **救不了** ⇒ 只剩那些**显式 `exit 1`** 兜底
⇒ 摘掉一个 ⇒ 那一步的失败**不再中止 CI** ⇒ CI 继续往下跑 ⇒ 假绿。

**⑤ 修法（本批只动判据层 ⇒ 零产品代码改动）**

① 每个脚本的**失败出口条数**逐个钉住（**整行锚定**）；
② 审计器额外钉「**成功出口**条数」⇒ 与「失败出口条数」**合看**：
任何一个失败出口被改成 `return 0` ⇒ 失败出口掉 1、成功出口涨 1 ⇒ **两条都红**；
③ 三个 `.py` 的**入口行**（`sys.exit(main())`）单独钉住
⇒ 入口被摘 ⇒ `main()` 的返回值被丢弃 ⇒ **rc 恒 0** ⇒ 工具永远绿；
④ `ci-d2.sh` / `smoke.sh` / `bootstrap-deps.py` **纳入**审计器的「整行锚定」适用范围
⇒ 将来这些门被写弱审计器就会红（这 3 个文件在范围内**没有**非锚定门项
⇒ **豁免表不变**）。

**⑥ 落门 / 判据（本批新增 13 条 + 原地替换 1 条）**

| # | 目标 | 盯什么 | 期望次数 |
|---|---|---|---|
| ① | `ci-wiring-audit.py` | 失败出口（整行 `return <非0数字>`） | 16 |
| ② | `ci-wiring-audit.py` | 条件出口 `return 3 if outside else 0` | 1 |
| ③ | `ci-wiring-audit.py` | 成功出口 `return 0` | 2 |
| ④ | `ci-wiring-audit.py` | 入口 `sys.exit(main())` | 1 |
| ⑤ | `ci.sh` | 整行 `exit N` | 27 |
| ⑥ | `ci-d2.sh` | 整行 `exit N` | 2 |
| ⑦ | `smoke.sh` | 行内形态 `\|\| { …; exit 1; }` | 1 |
| ⑧ | `smoke.sh` | 整行 `exit N` | 1 |
| ⑨ | `smoke.sh` | 行内形态 `\|\| exit 1` | 1 |
| ⑩ | `ci-tautology-check.py` | 失败出口 `return <非0数字>` | 3 |
| ⑪ | `ci-tautology-check.py` | 入口 `sys.exit(main())` | 1 |
| ⑫ | `bootstrap-deps.py` | 失败出口 `return <非0数字>` | 1 |
| ⑬ | `bootstrap-deps.py` | 入口 `sys.exit(main())` | 1 |

⇒ 13 条**全部整行锚定**（批 BQ 口径：中间只许有界通配，如 `[^"]*`）。
⇒ **原地替换**（批 BM，不增行）：批 BR 那条「锚定形态适用范围常量」的门项
正则与说明文字同步（范围 +3 个脚本；⚠ 范围常量**必须单行** —— 批 BR）。

**⑦ ⚠⚠⚨ 负控（19 条断言全绿）**

- **A1.0 / A1.1** ⚠ **行为级（旗舰）**：次数门失准 ⇒ 审计器**必须报 rc=4**；
  摘掉 `return 4` ⇒ **rc=0** ⇒ **假绿坐实**；
- **A2.0 / A2.1** ⚠ **行为级**：豁免路径缺失 ⇒ 必须判失败；
  摘掉 `ci-d2.sh` 最终判定的 `exit 1` ⇒ **rc=0 且照样打印「✓ D2 命中 0/0」**
  ⇒ **假绿坐实**；
- **A3.0 / A3.1**：`ci.sh` 第 1 步失败 ⇒ CI **必须停在那一步**且返回非 0；
  摘掉那个 `exit 1` ⇒ **第 2 步照样开跑** ⇒ 失败**不再中止 CI**；
- **① ~ ⑬**：13 条门项**各变异一次**（每条一种不同攻击：改成 `return 0` /
  改成 `exit 0` / 改成 `:` / 摘掉入口）⇒ **13 条全红**。
  累计 **548/548**。

**⑧ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ 「失败出口」= **整行**的 `exit <非0数字>` / `return <非0数字>`
  ⇒ **行内**形态（`|| { …; exit 1; }` / `|| exit 1`）**数不到**
  ⇒ `smoke.sh` 的两处行内失败上报**单钉**（否则它们没门）；
- ⚠ 「失败出口被改成**另一个非 0 码**」⇒ 出口数不变 ⇒ 这几条门**抓不到**
  ⇒ 抓得到的是**诊断不失真**（需要另钉具体码值）或**下一批**；
- ⚠ `bootstrap-deps.py` **不在 CI 里**（手动引导用）⇒ 收它是为了「同一类洞一并收」，
  不影响 CI 行为；
- ⚠ 收的是**出口条数**⇒ 「多了一个失败出口」（新增一条失败路径）会红
  ⇒ 那是**不许增**的基线（合法新增需同步更新期望值，批 BB 口径）。

**⑨ 落门 / 判据（数字）**

- 门项物理行数 **864 → 877**（+13）；执行次数 **867 → 880**；
  门项总数基线 `ci-wiring-gates.baseline` = **864 → 877**。
- 豁免表**不变**（13 条 —— 新纳入范围的 3 个文件**没有**非锚定门项）。
- 接线门 **880** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 19/19 真红**（19 条断言全绿）。
- **视觉变化**：无（只动判据层与文档；快照零变化）。
### E.2ak 「未验证」不许被当成「通过」：契约门的 SKIP 必须用专属退出码 3（批 CB）

**① 起因（实测盘点，不是印象）**

批 CA 把「失败上报出口」逐个钉住了 ⇒ 顺带盘出**唯一**一处「用 `exit 0` 表示
**未验证**」的地方：`contract-check.sh` 的两个 SKIP 分支。

⚠⚠⚨ **而批 BW 早就在探针侧立了这条口径**（`0=通过 / 1=失败 / **3=SKIP**」），
**它的注释里还早就写着**「与第 10 步契约门**同款口径**」
⇒ 但契约门脚本一直用的是 `exit 0`
⇒ **注释与实际行为不一致**（批 BB 纪律：说明必须与实际行为一致）⇒ 本批把脚本侧对齐。

**② ⚠⚠⚨ 洞（行为级·假绿）**

`ci.sh` 第 10 步原来是：

```sh
if DEEPGIT_CLIENT_BIN="$BIN" sh "$SRC/scripts/contract-check.sh" > "$_cc_log" 2>&1; then
    tail -3 "$_cc_log"
    echo "✓ 引擎契约门通过"
else
    tail -20 "$_cc_log" >&2
    echo "✗ 引擎契约门失败" >&2
    exit 1
fi
```

⇒ 脚本 `exit 0`（**未验证**）也走「**通过**」那一支
⇒ ⚠⚠⚨ **实测**：缺 python3 时**120 条契约断言一条都没跑**，
CI 却打印「**✓ 引擎契约门通过**」⇒ **假绿**。

⇒ 根因链有**两环**：① 脚本用 `exit 0` 表示未验证；② CI 不分诊退出码
⇒ **两环都要修**，只修一环仍然是假绿。

**③ ⚠⚠⚨ 行为级实测（假绿坐实）**

- **A1（脚本层）**：造一个「PATH 里没有 python3、但 `DEEPGIT_BIN` 指向真引擎」的环境
  ⇒ 命中「缺 python3」那一支
  ⇒ **旧形态 exit 0**（未验证与通过分不开）/ **新形态 exit 3**（专属未验证）；
- **A2（CI 层）**：从 `ci.sh` **原文现抽**第 10 步块（零漂移）放进 harness，
  stub 掉 `contract-check.sh`：
  - **旧块 + exit 0** ⇒ 打印「**✓ 引擎契约门通过**」⇒ **谎称**（这就是旧形态的假绿）；
  - **新块 + exit 3** ⇒ 打印「‣ SKIP 引擎契约门：本组**未验证**」且**不**谎称通过；
  - **新块 + exit 1** ⇒ 判失败并返回非 0。

**④ 修法（照批 BW 的房style）**

① **脚本侧**：两个 SKIP 分支 `exit 0` → **专属未验证码 3**；
② **CI 侧**：第 10 步**接住退出码**并分诊
（**0 = 通过 / 3 = 未验证(SKIP) / 其它非 0 = 失败**）
⇒ SKIP 支**如实打印「本组未验证，不算通过」**（与第 13 步同款口径）。

**⑤ 落门 / 判据（本批新增 7 条 + 原地替换 1 条）**

| # | 目标 | 盯什么 | 期望次数 |
|---|---|---|---|
| ① | `contract-check.sh` | 引擎缺席支的**独立成行** `exit 3` | 1 |
| ② | `contract-check.sh` | 缺 python3 支的**行内** `exit 3` | 1 |
| ③ | `ci.sh` | `_cc_rc=0`（退出码变量必须初始化） | 1 |
| ④ | `ci.sh` | 分诊「`-eq 0` = 通过」 | 1 |
| ⑤ | `ci.sh` | 分诊「`-eq 3` = 未验证」 | 1 |
| ⑥ | `ci.sh` | SKIP 支必须打印「**未验证**」 | 1 |
| ⑦ | `ci.sh` | 失败支必须报出**退出码**（诊断不失真） | 1 |

⇒ 7 条**全部整行锚定**。
⇒ **原地替换**（批 BM 纪律，不增行；批 BB 纪律：说明与期望值**一起改**）：
第 10 步那条既有门项的**形态**从 `if cmd; then` 改成「**接住退出码 + 分诊**」
⇒ 「必须接住退出码」这条承诺**就落在它身上**（**不另加一条** —— 否则同
（门型, 文件, 正则, 次数）会出现**两条一模一样的门** ⇒ 批 AS/AT「同名多处
互相顶替」纪律 ⇒ 纯冗余）。
⇒ ⚠ 另：批 CA 的「`ci.sh` 整行 `exit N` 恰好 27 处」**不变**
（失败支的 `exit 1` 还在 ⇒ 计数不变）。

**⑥ ⚠⚠⚨ 负控（12 条断言全绿）**

- **A1** 缺 python3 ⇒ 旧形态 exit 0 / 新形态 **exit 3**；
- **A2.0 / A2.1 / A2.2** CI 层：旧块 + exit 0 ⇒ **谎称「✓ 通过」**；
  新块 + exit 3 ⇒ **诚实 SKIP**；新块 + exit 1 ⇒ 判失败且 rc≠0；
- **① ~ ⑦**：7 条门项**各变异一次**（改成 `exit 0` / 删初始化 / 退出码被吞成
  `|| true` / 分诊码改掉 / 文案改掉）⇒ **7 条全红**。
  累计 **560/560**。

**⑦ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ 引擎缺席那一支在 CI 里**走不到**（`ci.sh` 的外层守卫先判过引擎在不在）
  ⇒ 收它是为了「脚本**单独**跑时也诚实」+ 与第 13 步口径一致；
- ⚠ CI 里**实际可达**的是「缺 python3」那一支 ⇒ 门项两条都收（不许只收一条）；
- ⚠ SKIP 之后 CI **仍然绿**（沿用本仓既有立场：环境不具备 ⇒ SKIP、不算通过、
  但不判失败）⇒ ⚠ 与第 13 步（agent 工具面门，批 BW）**同款口径**；
  若将来认为「核心门未验证 ⇒ 必须判红」，那是**另一条决策**，本批未做。

**⑧ 落门 / 判据（数字）**

- 门项物理行数 **877 → 884**（+7）；执行次数 **880 → 887**；
  门项总数基线 `ci-wiring-gates.baseline` = **877 → 884**。
- 豁免表**不变**（13 条）。
- 接线门 **887** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 12/12 真红**（12 条断言全绿）。
- **视觉变化**：无（只动判据层、CI 脚本与文档；快照零变化）。
### E.2al 「失败出口的码值」是判据的一部分：不许被悄悄改（批 CC）

**① 起因（实测盘点，不是印象）**

批 CA 把「失败上报出口」逐个钉住了 ⇒ 但它钉的是**总数**
（`ci-wiring-audit.py` 的 `^\s*return [1-9]$` == 16 / `ci.sh` 的 `exit [1-9]` == 27）。

⚠⚠⚨ 而**退出码是判据的一部分**：每个码值承载一类语义。
本批**逐个盘点了全仓的失败出口码值分布**（从 `ci-wiring.sh` 原文现抽
`strip_comments`，口径零漂移）⇒ 盘出：

| 脚本 | 码值分布 | 语义 |
|---|---|---|
| `ci-wiring-audit.py` | `return` 2×5 / 4×1 / 5×2 / 6×1 / 7×1 / 8×2 / 9×4 | **9 个码各一类失配** |
| `check-deb-layout.sh` | `exit` 1×1 / 2×1 / 3×1 | 1=失败 / 2=用法错 / **3=未验证** |
| `probe-agent-tool-surface.sh` | `exit` 1×5 / 2×1 / 3×2 + `fail=1`×5 | 3=**未验证(SKIP)** |
| 3 个探针 + `ci-tautology-check.py` | `exit 2`×1 / `return 2`×1 | 2=**用法错** |
| `ci.sh` / `ci-d2.sh` / `smoke.sh` / `bootstrap-deps.py` | 全是单一码 `1` | 无语义 ⇒ 不分桶 |

⇒ ⚠⚠⚨ **批 CA 段自己的注释里就写着这条已知边界**：
「失败出口被改成**另一个非 0 码** ⇒ 出口数不变 ⇒ 这两条门**抓不到**
⇒ 抓得到的是**诊断不失真**（另一条门盯具体码值）或**下一批**」
⇒ **本批就是那个「下一批」**。

**② ⚠⚠⚨ 洞 ①（行为级·假绿·旗舰）**

`check-deb-layout.sh` 的 SKIP 分支（没有 `dpkg-deb` ⇒ 本门**未验证**）：

```sh
if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "SKIP: 没有 dpkg-deb（本门**未验证**，不算通过）" >&2
    exit 3
fi
```

⇒ ⚠⚠⚨ **实测**：把它改成 `exit 0` ⇒ 脚本 **rc=0** 而输出**仍写着**
「SKIP: 没有 dpkg-deb（本门**未验证**，不算通过）」
⇒ CI 第 12 步打印「**✓ deb 布局验收通过**」⇒ **假绿坐实**
⇒ ⚠⚠⚨ 而**现有门全绿**（实测：接线门 rc=0）⇒
`exit 3` **一条门都没有** ⇒ 没人看得见。

**③ ⚠⚠⚨ 洞 ②（行为级·误判）**

`ci.sh` 第 12 步**不分诊**退出码：

```sh
elif sh "$SRC/scripts/check-deb-layout.sh" "$DEB_OUT"; then
    echo "✓ deb 布局验收通过（…）"
else
    echo "✗ deb 布局验收失败" >&2
    exit 1
fi
```

⇒ ① 脚本 `exit 3`（**正确的未验证**）⇒ CI 判「✗ 失败」并 exit 1
⇒ **未验证被当成失败**；
⇒ ② 脚本 `exit 0`（**未验证**）⇒ CI 打印「✓ 通过」⇒ **假绿**。

⇒ 与批 CB 修的第 10 步（契约门）**同款洞** ⇒ 本批同款修。

**④ ⚠⚠⚨ 洞 ③（行为级·诊断被带偏）**

审计器的失败码**每个都有语义**（2=盲区 / 3=豁免之外有隐患 /
**4=次数门没配准** / 5=正则坏 / 6=总数失配 / 7=重名 / 8=锚定形态 / 9=未定义名）。

⇒ ⚠⚠⚨ **实测**：把 `return 4` 改成 `return 3`
⇒ 次数门失准时审计器报 **rc=3** ⇒ **撞上「豁免之外有隐患」的码**
⇒ **按 rc 分派的自动化处理会走错分支** ⇒ 排障被带偏
（诊断**文本**还在，但退出码变了 ⇒ 自动化读的是退出码）。

**⑤ 修法（照批 CB / 批 BW 的口径）**

① **按码值分桶**逐个钉住（不再是「非 0 的总数」）
⇒ 改一个码值 ⇒ **旧桶 −1 + 新桶 +1** ⇒ **两条都红**；
② `ci.sh` 第 12 步**接住退出码**并分诊（0=通过 / 3=未验证(SKIP) / 其它非 0=失败）
⇒ SKIP 支**如实打印「未验证、不算通过」**；
③ 批 CA 的 `return [1-9]` **宽门原地替换**成第一条分桶门，其余 6 条在本段
⇒ 7 条分桶门**完全蕴含**那条宽门（5+1+2+1+1+2+4 = 16）⇒ 删宽门不降低保护。

**⑥ 落门 / 判据（本批新增 21 条 + 原地替换 1 条）**

| 目标 | 盯什么 | 条数 |
|---|---|---|
| `check-deb-layout.sh` | `exit 1` / `exit 2` / `exit 3` **三个码各一桶** | 3 |
| `ci-wiring-audit.py` | `return` 2/4/5/6/7/8/9 **七个码各一桶** | 6 |
| `ci.sh` 第 12 步 | `_dl_rc=0` 初始化 / 接住退出码 / `-eq 0` / `-eq 3` / SKIP 文案 / 失败文案 | 6 |
| 3 个探针 | `exit 2`（用法错）各一桶 | 3 |
| `probe-agent-tool-surface.sh` | `exit 2`（用法错）/ `exit 3`（未验证） | 2 |
| `ci-tautology-check.py` | `return 2`（用法错） | 1 |

⇒ 21 条**全部整行锚定**。
⇒ **原地替换**（批 BM 纪律，不增行）：批 CA 的审计器宽门 → 第一条码值桶门；
第 12 步那条既有门项的**形态**从 `elif sh …; then` 改成「**接住退出码 + 分诊**」
⇒ 说明文字同步（批 BB：说明与实际行为必须一致）。
⇒ ⚠ 批 CA 段的**注释**同步改写（「总数门」已变成分桶门）⇒ 说明不许与实际行为脱节。

**⑦ ⚠⚠⚨ 负控（23 条断言全绿）**

- **A（行为级，11 条）**：
  A1.0 未变异 ⇒ SKIP 支报专属码 3；
  A1.1 变异 `exit 3 → exit 0` ⇒ **rc=0 且仍打「SKIP」⇒ 假绿坐实**；
  A1.2 同一变异下**现有门全绿**（⇒ 洞没人看得见）；
  A2.0 第 12 步**必须分诊**三路；
  A2.1 脚本 exit 3 ⇒ CI 判 **SKIP「未验证」且 rc=0**（不算通过，也不判失败）；
  A2.2 脚本 exit 0 ⇒ CI「✓ 通过」；
  A2.3 脚本 exit 1 ⇒ CI 判失败 rc≠0；
  A2.4 通过那一支**不许**出现「未验证」；
  A3.1 次数门失准 ⇒ 审计器必须报 **rc=4** 且点名是哪条门项；
  A3.2 变异 `return 4 → return 3` ⇒ 报 **rc=3**（**撞码**）；
  A3.3 诊断文本还在但**退出码变了** ⇒ 按 rc 分派的自动化会走错分支；
- **B（门项级，12 条）**：① ~ ⑫ 十二条门项**各变异一次**（改码值 / 删初始化 /
  退出码被吞成 `|| true` / 分诊码改掉 / 文案改掉）
  ⇒ **每条从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）⇒ **12 条全红**。
  累计 **583/583**。

**⑧ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ 只收**整行**的 `exit N` / `return N` ⇒ **行内**形态
  （`|| { …; exit 1; }` / `|| exit 1`）**数不到**
  ⇒ `smoke.sh` 的两处行内失败上报**单钉**（批 CA 已收）；
  `contract-check.sh` 的行内 `exit 3`（缺 python3 支）由批 CB 单钉；
- ⚠ 「未验证 = 3」「用法错 = 2」是**约定** ⇒ 本批把它**钉成基线**
  ⇒ 将来若要改这个约定，**必须同步更新这些门**（这正是本批想要的：改约定要留痕）；
- ⚠ 单一码的文件（`ci.sh` 的 27 个 `exit 1` 等）**不分桶**
  ⇒ 改那些码值**无语义损失** ⇒ 不值得为它加门（如实记着，避免噪音门）；
- ⚠ 审计器 rc=3 的**正常可达性**存疑：本批实测「次数门失准」先走 rc=4
  ⇒ rc=3（`return 3 if outside else 0`）在实践中**可能走不到**
  ⇒ 但「两个语义撞在同一码」的风险**依然成立**（因为变异后 rc=4 变成了 3）
  ⇒ 本批的价值是**不让任何码值被悄悄改**，而不是修 rc=3 的可达性；
- ⚠ 失败出口的**总条数**门（批 CA 的 `exit [1-9]` 等）**仍在**
  ⇒ 分桶门与总数门**并存**（总数门管「不许少」，分桶门管「不许改码值」）
  ⇒ ⚠ 只有审计器那一条**宽门被删**（被 7 条分桶门完全蕴含 ⇒ 冗余）；
- ⚠ 探针的 `exit 2`（用法错）在 CI 里**不会触发**（CI 总带对参数）
  ⇒ 收它是为了「**单独**跑探针时诊断不失真」。

**⑨ 落门 / 判据（数字）**

- 门项物理行数 **884 → 905**（+21）；执行次数 **887 → 908**；
  门项总数基线 `ci-wiring-gates.baseline` = **884 → 905**。
- 豁免表**不变**（13 条）。
- 接线门 **908** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、
  ci.sh **15/15**、ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、
  报告模式 **rc=0**、恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 23/23 真红**（A 11 + B 12）。
- **视觉变化**：无（只动判据层、CI 脚本与文档；快照零变化）。
### E.2am 「工具读不了」不许被当成「没问题」：扫描前先验可读性（批 CD）

**① 起因（实测盘点，不是印象）**

批 AZ 早就记下过「真正吞退出码的是**命令替换内部的 `|| true`**」，
但**从未收过**这些站点。本批**逐个盘点**了 `scripts/` 下的**外部工具调用站点**
（**419 处**，按「工具失败会落到**哪一支**」分类）⇒ 盘出三类：

| 类别 | 盘点数 | 结论 |
|---|---|---|
| **危险方向**：`if 外部工具; then <不通过>; else <通过>; fi` | **0 处** | 无此类洞（如实记着） |
| **命令替换内 `\|\| true`** | 多处 | 多数**输入是字符串**（grep 读的是管道 ⇒ 崩不了）⇒ 无害 |
| **输入是文件**的 `\|\| continue` / `\|\| true` | 2 处 | ⚠⚠⚨ **真洞**（本批收的就是这两处） |

⇒ 批 BX 的已知边界（「盘点口径只覆盖调用我们自己的二进制」）本批**往前推了一步**：
把「**外部工具读文件失败**」这一类收掉。

**② ⚠⚠⚨ 洞 ①（行为级·假绿·旗舰）**

`ci-d2.sh`（设计系统散值门）的两处**双重吞**：

```sh
for _f in $(grep -rlE "$D2_PATTERN" "$SRC/src" 2>/dev/null | sort); do
    _hits="$(strip_comments "$_f" | grep -nE "$D2_PATTERN" | sed "s|^|${_f}:|" || true)"
```

⇒ ⚠⚠⚨ **实测**：造一个**含散值**的源文件（`src/zzAzCdProbe.cpp`，内容 `#FF00AA`），
让它对 grep **不可读**（`chmod 000` ⇒ grep rc=2）
⇒ 外层 `grep -rl` **静默跳过**它 ⇒ 命中数变 0
⇒ 脚本打印「**✓ D2 命中 0/0（存量已清零，DS 单一真相源）**」并 **exit 0**
⇒ ⚠⚠⚨ **门自己说「✓」⇒ 假绿坐实**
⇒ 而**接线门全绿**（实测 rc=0）⇒ 没人看得见。

**③ ⚠⚠⚨ 洞 ②（行为级·假绿）**

`ci-orphan-probe.sh` 的「什么算断言脚本」判定：

```sh
grep -q '✗ ' "$_f" 2>/dev/null || continue
```

⇒ grep **崩了**（rc=2）与「没找到」（rc=1）**混为一谈**
⇒ 游离断言脚本**被静默跳过**
⇒ 脚本打印「**✓ 无游离断言脚本：scripts/ 下 16 个断言脚本全部在 CI 里可达**」
并 exit 0 ⇒ **漏检坐实**。

⇒ 两洞的**共同形态**：「**工具读不了**」被当成「**没问题**」
⇒ 与批 CB/CC 同款口径：**未验证不许被当成通过**。

**④ 修法（只动判据层 ⇒ 零产品代码改动）**

在**扫描之前**先验**可读性** ⇒ 读不了 ⇒ 判失败：

- `ci-d2.sh`：`find "$SRC/src" -type f ! -readable -print`（退出码一并接住）
  ⇒ 不可读 ⇒ `FAIL=1` ⇒ 末尾的 `exit 1` 在「✓ 命中 0/0」**之前**
  ⇒ **那个「✓」永远打不出来**；
- `ci-orphan-probe.sh`：对 `scripts/*.sh` + `scripts/*.py` 逐个 `[ -r ]`
  ⇒ 不可读 ⇒ `fail=1` ⇒ 末尾统一 `exit 1`。

⚠ **为什么选「扫描前验可读性」而不是「逐个接 grep 的 rc」**：
① **一次挡住整类**（同一批文件的所有 grep 调用都受益）；
② 被扫集合与被验集合**完全一致**（不漏一个文件）；
③ 失败信息**指名道姓**是哪个文件读不了（排障不用猜）。

**⑤ 落门 / 判据（本批新增 4 条，全部整行锚定）**

| 目标 | 盯什么 |
|---|---|
| `ci-d2.sh` | 可读性检查那一行（**同时**保证 `\|\| _d2_find_rc=$?` 在 ⇒ 整行锚定 ⇒ 摘掉退出码接住也红） |
| `ci-d2.sh` | 不可读时**必须判失败**（`FAIL=1` + 批 CD 注释，整行锚定） |
| `ci-orphan-probe.sh` | 可读性检查那一行（`[ -r "$_f" ] \|\| _orphan_unread=…`） |
| `ci-orphan-probe.sh` | 不可读时**必须判失败**（`fail=1` + 批 CD 注释，整行锚定） |

⇒ ⚠ **原地替换**：孤儿探针的「断言清单（报错行数）」**6 → 7**
（新增「有脚本对工具不可读 ⇒ 判失败」那条报错行）⇒ 说明文字同步（批 BB）。
⇒ ⚠ **删掉 1 条纯冗余**：D2 那行同时含「检查」与「接住退出码」，
本批一度落成**两条一模一样的门** ⇒ 同（门型, 文件, 正则, 次数）⇒ **去重**
⇒ 两条承诺**合并进一条**的说明文字（批 AS/AT「同名多处互相顶替」纪律）。

**⑥ ⚠⚠⚨ 负控（13 条断言全绿）**

- **A（改前取证，6 条，已在改前的代码上实测通过）**：
  A1.0 未变异时含散值的文件必须让 D2 门红；
  A1.1 变异「文件不可读」⇒ **rc=0 且打印「✓ D2 命中 0/0」⇒ 假绿坐实**；
  A1.2 同一变异下**现有门全绿**（⇒ 洞没人看得见）；
  A2.0 未变异时游离断言脚本必须被报出来；
  A2.1 变异「文件不可读」⇒ **rc=0 且打印「✓ 无游离断言脚本」⇒ 漏检坐实**；
  A3.1 同一变异下**接线门仍全绿**。
  ⚠ **如实记着**：这 6 条是**改前**的一次性取证 ⇒ 在**改后**的代码上**必然失败**
  ⇒ 那正是「修好了」的证据 ⇒ **不可复现**（历史证据留档在此，不做门）。
- **B（改后，7 条，全红）**：
  B1.1 文件不可读 ⇒ ci-d2.sh **必须判红**且**不许**打印「0/0」；
  B2.1 文件不可读 ⇒ ci-orphan-probe.sh **必须判红**且**不许**打印「✓ 无游离断言脚本」；
  ① ~ ⑤：4 条门项**各变异一次**（删检查行 / 方向反了 / 改成 `FAIL=0` / 改成 `fail=0`）
  ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）⇒ **4 条全红**。
  累计 **596/596**。

**⑦ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ 「扫描前验可读性」只挡住「**文件不可读**」这一种原因
  ⇒ grep 的**其它**失败（如文件名含换行、匹配到二进制文件）仍可能被静默跳过
  ⇒ 本批**只收了实测坐实的这一类**（不推演）；
- ⚠ `ci-orphan-probe.sh` 的 `calls_of()` 里也有 `2>/dev/null`
  ⇒ 但它的失败方向是「REACH 集合**变小** ⇒ **误报**（不是假绿）」⇒ 安全方向
  ⇒ 如实记着，**不改**；
- ⚠ 本批只改了 **2 个脚本** ⇒ 其余脚本里「输入是文件」的同类站点**待再盘**
  ⇒ 「命令替换内 `|| true`」那一族多数无害（输入是字符串）⇒ 不动；
- ⚠ 负控 A 不可复现（见 ⑥）⇒ 复现手段只能是「回到改前的提交跑一遍」。

**⑧ 落门 / 判据（数字）**

- 门项物理行数 **905 → 909**（+4：新增 4 条，删 1 条纯冗余）；
  执行次数 **908 → 912**；
  门项总数基线 `ci-wiring-gates.baseline` = **905 → 909**。
- 豁免表**不变**（13 条）。
- 接线门 **912** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、
  ci.sh **15/15**、ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、
  报告模式 **rc=0**、恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 13/13 真红**（A 改前取证 6 + B 改后 7）。
- **视觉变化**：无（只动判据层脚本与文档；快照零变化）。
### E.2an 「外部工具的失败」不许被当成「检查通过」（批 CE）

**① 起因（实测盘点 + 方法论修正）**

批 CD 盘过 `scripts/` 下的外部工具调用站点（419 处）⇒ 结论写着
「**危险方向 0 处**」。⚠⚠⚨ **但那个口径有盲区**（本批实测坐实）：

- 批 CD 只找**字面形态** `if 外部工具; then <不通过>; else <通过>; fi`
  ⇒ **漏了两种形态**：
  1. **工具输出 → 变量 → 判定**
     （`_nf="$(ldd … | grep -c 'not found' || true)"` ⇒ `[ "$_nf" = "0" ] || die`）；
  2. **无 else 分支**的 `if 工具; then <失败支>; fi`
     ⇒ 工具失败 ⇒ 条件为假 ⇒ **什么都不做 ⇒ 隐式通过**。

⇒ 本批用**更宽的口径**重盘（两种形态都盘，并按「工具失败 ⇒ 落到哪一支」判方向）：

| 口径 | 结果 |
|---|---|
| 危险方向（工具失败 ⇒ 判通过） | **3 处真洞** |
| 同形态但输入是字符串（grep 读管道 ⇒ 崩不了） | 4 处 ⇒ 无害 |
| 条件带 `!`（工具失败 ⇒ 反而进 then 报错） | 误报方向 ⇒ 安全 |

**② ⚠⚠⚨ 洞 ①（行为级·假绿·旗舰·D7 核心验收）**

`build-deb.sh` 的 ldd 缺库检查（「装到干净 deepin 25 上能不能起来，就看这一条」）：

```sh
_nf="$(env -u LD_LIBRARY_PATH ldd "$TMP/unpack/usr/bin/deepDolphin" 2>&1 | grep -c 'not found' || true)"
_nf="${_nf:-0}"
[ "$_nf" = "0" ] || die "解包后的二进制有 $_nf 个库 not found（D7 不达标）"
```

⇒ ldd **失败**（二进制不存在 / 不可读 / 工具崩了 ⇒ 报 `cannot open`）
⇒ 计数 **0** ⇒ 「无缺失库」⇒ **判通过** ⇒ **假绿**
⇒ ⚠⚠⚨ **实测**（stub 一个失败的 ldd，从脚本原文现抽那 3 行跑）：
**rc=0 走到末尾**。
⇒ ⚠⚠⚨ 假绿的代价：**发出一个装不起来的 deb**
（`build-deb.sh` 在 **CI 第 11 步**里跑 ⇒ CI 照样报「✓」）。

**③ ⚠⚠⚨ 洞 ②（行为级·假绿）**

`build-deb.sh` 的 readelf RPATH 检查：

```sh
if readelf -d "$PKG/usr/bin/deepDolphin" | grep -qiE "rpath|runpath"; then
    die "包内二进制带 RPATH/RUNPATH —— 指向开发机路径，装到别的机器就找不到库"
fi
```

⇒ **无 else 分支** ⇒ readelf 失败 ⇒ 不进 then ⇒ **静默判「没带 RPATH」⇒ 通过**
⇒ ⚠⚠⚨ **实测**（stub 一个失败的 readelf）：**rc=0 走到末尾**。

**④ ⚠⚠⚨ 洞 ③（行为级·假绿·判据层自身）**

`ci-wiring.sh` 的图标收口检查（批 U 段）：

```sh
if strip_comments "$f" | grep -qE 'QIcon::fromTheme'; then
    echo "  ✗ UI 里还有裸 QIcon::fromTheme …" >&2
    ICON_RAW=1
fi
```

⇒ **无 else 分支** ⇒ 某个 `src/ui/*.cpp` 对工具**不可读** ⇒ grep 无输出
⇒ **裸 `QIcon::fromTheme` 漏检** ⇒ 门照样绿
⇒ ⚠⚠⚨ **判据层自身的假绿**（门没看见，而不是门坏了）。

**⑤ 修法（只动判据层与构建脚本 ⇒ 零产品代码改动）**

① **接住工具的退出码** ⇒ 非 0 ⇒ **判失败**（工具失败 = 没验过）
⇒ 与批 CB/CC/CD **同款口径**：**未验证不许被当成通过**；
② **拆开管道**（工具输出先落进变量，再加工）
⇒ 否则**管道里拿不到**工具自己的退出码（管道退出码是最后一条的）；
③ `dpkg-deb -x` 的失败**改成响亮 die**（以前靠 `set -e` 静默中止
⇒ 没有 die 消息 ⇒ 看着像「跑到一半没了」⇒ **诊断失真**）；
④ 洞 ③ 用批 CD 同款：**扫描之前先验可读性** ⇒ 读不了 ⇒ 判失败。

**⑥ 落门 / 判据（本批新增 4 条 + 原地替换 1 条 + 同步 1 条）**

| 目标 | 盯什么 |
|---|---|
| `build-deb.sh` | ldd 失败**必须 die**（整行锚定） |
| `build-deb.sh` | readelf 失败**必须 die**（整行锚定） |
| `build-deb.sh` | 解包失败**必须响亮 die**（整行锚定） |
| `ci-wiring.sh` | 图标收口检查**必须先验可读性**（整行锚定） |

⇒ **原地替换**（批 BM 纪律）：批 CD 之前那条盯 `readelf … | grep -qiE "rpath|runpath"`
的 `arch_need` ⇒ 形态已变 ⇒ 正则与说明**同步改写**（批 BB：说明必须与实际行为一致）。
⇒ **同步**：helper 型脚本的「断言清单（die/fail 调用点）」**20 → 23**
（+3 是**诊断增强**的 die：解包失败 / readelf 失败 / ldd 失败 ⇒ 不是新断言，
但计数要如实改）⇒ 说明同步。

**⑦ ⚠⚠⚨ 负控（8 条断言全绿）**

- **A（行为级·改前取证，2 条）**：A1.1 ldd 失败 ⇒ 旧形态 **rc=0 走到末尾**
  （假绿坐实）；A2.1 readelf 失败 ⇒ 旧形态 **rc=0 走到末尾**（假绿坐实）。
  ⚠⚠⚨ **这两条脚本在改后仍可复现**：断言的是「必须判失败」
  ⇒ **改前红、改后绿**（同一份脚本，状态变它就变）⇒ 比批 CD 的负控 A 更可复现；
- **B（门项级，4 条）**：① ldd 失败不 die ⇒ 红；② readelf 失败不 die ⇒ 红；
  ③ 解包失败不 die ⇒ 红；
  ④ ⚠⚠⚨ **增量价值**：变异「ldd 失败不 die」下**旧门全绿**（盯串的）
  ⇒ 而**只有批 CE 的门红**（旧门红=False，新门红=True）；
- **C（洞 ③，2 条）**：C1.1 `src/ui/` 有不可读文件 ⇒ 接线门**必须红**
  且红的原因含「不可读」（⚠ 造的文件**不含**任何被别的门盯的串 ⇒ 红的原因唯一）；
  C2.1 删掉那处可读性验证 ⇒ 门必须红。
  累计 **604/604**。

**⑧ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **批 CD 的「危险方向 0 处」是错的**（口径有盲区）⇒ 本批已修正并记此；
  ⇒ ⚠ **盘点方法本身也要被门守**（否则下一次盘点还会漏）—— 本批**未做**；
- ⚠ 本批只收「**工具失败 ⇒ 判通过**」这一类 ⇒ 「工具失败 ⇒ 误报」
  （条件带 `!` 的那批）**方向安全** ⇒ 不动；
- ⚠ 「输入是字符串」的 4 处 ⇒ grep 读管道 ⇒ 崩不了 ⇒ 不动；
- ⚠ `ci-wiring.sh` 里其余几十处 `strip_comments` 的用法
  ⇒ 方向都是「工具失败 ⇒ 门红」⇒ 安全 ⇒ 只收危险方向那两处；
- ⚠ ldd 对**静态二进制**返回 1 ⇒ 会被判失败 ⇒ 这是**故意的**
  （静态产物本就不该走依赖检查，且判失败比静默通过安全）；
- ⚠ 负控 A/B/C 都用 **stub 工具**（PATH 前置）⇒ 不依赖本机环境
  ⇒ 但它们验的是**抽出来的片段**，不是整脚本 ⇒ 整脚本的其余部分由 CI 第 11 步兜。

**⑨ 落门 / 判据（数字）**

- 门项物理行数 **909 → 913**（+4）；执行次数 **912 → 916**；
  门项总数基线 `ci-wiring-gates.baseline` = **909 → 913**。
- 豁免表**不变**（13 条）。
- 接线门 **916** 项全绿（✗=0）、selfcheck **395/0**、契约门 **120/0**、
  ci.sh **15/15**（含第 11 步**真跑** build-deb.sh ⇒ 新代码的正常路径没被改坏）、
  ci-d2 **0/0**、快照**零变化**、审计器硬门 **rc=0**、报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 8/8 真红**。
- **视觉变化**：无（只动判据层、构建脚本与文档；快照零变化）。
### E.2ao 「判据层自己的剥注释」不许有三份实现、三种口径（批 CF）

**① 起因（实测盘点 + 对照实验，不是推演）**

本批原计划盘「命令替换内的 `|| true`」与「无 pipefail 的管道」
（实测：`scripts/` 下 **18/18** 个 shell 脚本**都没开** `pipefail`；
命令替换内带 `|| true` 的站点 **26** 处）⇒ 但盘点中发现了一个**更硬的洞**，
先收它：

⚠⚠⚨ **剥注释函数 `strip_comments` 在仓里有 3 份 shell 实现 + 1 份 python 实现
⇒ 3 种不同口径**：

| 实现 | perl 正则 | `.sh/.txt/.py` 分支 |
|---|---|---|
| `ci-wiring.sh` | `s{(?<!:)(//)(?!:).*$}{}`（**新**） | 有（剥 `#`） |
| `ci-d2.sh` | 同上 | **无** ⇒ `.py` 不剥 `#` ⇒ 批 BK 的洞仍在 |
| `ci.sh` | `s{//(?!:).*$}{}` —— **旧口径**（**没有** `(?<!:)`） | 无 |
| 审计器（python） | 同新口径 | 有 |

⇒ 批 AS 早就定过：「**复刻 = 两套口径 ⇒ 一律改成调同一条命令**」，
**审计器已经这么做了**（它直接调 perl，不复刻），
⇒ ⚠⚠⚨ **但两个 shell 脚本根本没遵守** —— 它们自己复刻了，**而且各自漂了**。

**② ⚠⚠⚨ 洞 ①（口径分裂 · 旗舰 · 实测坐实）**

⚠⚠⚨ **对照实验（改前实测）**：

- ① 同一份源码、同一个门项（`QStringLiteral("verify")`）⇒
  **`ci.sh` 口径命中 0**、**`ci-wiring.sh` 口径命中 1** ⇒ **相反结论**；
- ② 仓里已有 **12** 个真实源文件（`src/ai/AnthropicEngine.cpp`、
  `src/main.cpp`、`src/ui/pages/ProjectDetailPage.cpp` …）在两套口径下
  **输出已经不同**（根因：sed 兜底把 `https://…` 整段剥掉，perl 口径不会
  ⇒ `(?<!:)` 正是为这个加的）。

⇒ **不是假想，现在就能咬人**：
`ci.sh` 的 verify 接线门会**误报红**（假红，批 BS：假红逼人把承诺改弱）；
换个构造就是**漏检**（假绿）。

⇒ ⚠⚠⚨ **没有任何门守它** ⇒ 「同一个串两边算得不一样」这件事一直没人知道。

**③ ⚠⚠⚨ 洞 ②（静默降级 + 诊断失真）**

三份实现都有 perl→sed 的**静默兜底** ⇒ perl 缺席 ⇒ **口径变成第四种**。
⚠⚠⚨ **实测**（造一个不含 perl 的 PATH，2966 个软链）：

- **审计器**：`FileNotFoundError: 'perl'` ⇒ **未捕获异常崩掉** ⇒ 退出码 **1**
  ⇒ 门侧报「**未知的失败码**」⇒ 真实原因（缺 perl）**没有任何一条消息提到**；
- **接线门**：红了，但红因是「**取数/判定/渲染/接线任一段被摘掉**」
  —— ⚠⚠⚨ **与真实原因毫无关系** ⇒ 排障被带偏（批 CE 纪律：诊断不许失真）；
- ⚠⚠⚨ **`ci-d2.sh` 更是假绿**：剥注释失败 ⇒ 命中数 0
  ⇒ **照样打印「✓ D2 命中 0/0」并 exit 0**。

**④ 修法（只动判据层 ⇒ 零产品代码改动）**

① **口径单一真相源**：`ci.sh` / `ci-d2.sh` **不再自己定义**
⇒ 改为**从 `ci-wiring.sh` 原文抽取**（批 AV 纪律：抽取而非复刻）
⇒ 一次挡住整类（口径永远一致，改一处就跟着变）；
② **静默降级 ⇒ 响亮失败**：三个脚本**顶层前置检查 perl 在不在**
⇒ 缺 ⇒ **响亮失败**（工具失败 = 没验过；与批 CB/CC/CD/CE 同款口径）；
判据层的 `strip_comments` 默认分支**去掉 sed 兜底**；
③ **审计器前置检查**：缺 perl ⇒ 指名道姓 + 退出码 **2**
（2 = 审计器有盲区或缺文件 ⇒ C++ 侧的门项**根本没被审** ⇒ 正是盲区）
⇒ `ci-wiring.sh` 的 rc=2 分派消息**同步补一句**（批 BB：说明必须与实际行为一致）；
④ ⭐ **抽取自检**：`sed -n '/^strip_comments() {/,/^}/p'` 会在**第一个独占 `}` 行**处结束
⇒ 函数体里若有这样的行 ⇒ **抽到残缺函数** ⇒ 行为错乱
⇒ 所以抽取失败/抽出来不可用 ⇒ **指名道姓地失败**（不许静默用半个函数）。

**⑤ ⚠⚠⚨ 落门 / 判据（本批新增 10 条：2 forbid + 8 条全整行锚定）**

| 目标 | 门型 | 盯什么 |
|---|---|---|
| `ci.sh` | forbid | **不许自己实现**剥注释（`perl -pe`） |
| `ci-d2.sh` | forbid | 同上 |
| `ci.sh` | 整行锚定 | 抽取 + 自检那一行必须在 |
| `ci-d2.sh` | 整行锚定 | 同上 |
| `ci-wiring.sh` | 整行锚定 | perl 前置检查那一行必须在 |
| `ci.sh` | 整行锚定 | perl 前置检查那一行必须在 |
| `ci-d2.sh` | 整行锚定 | perl 前置检查那一行必须在 |
| `ci-wiring.sh` | 整行锚定 | 剥注释**必须直接走 perl**（整行锚定 ⇒ 兜底一旦加回就红） |
| `ci-wiring-audit.py` | 整行锚定 | `def require_perl():`（**带左括号** ⇒ 改名躲不过） |
| `ci-wiring-audit.py` | 整行锚定 | `require_perl()` **必须被调用** |

⇒ ⚠ **删掉 1 条纯冗余**（批 CB 纪律）：原计划的 forbid 门（盯旧兜底指纹
`s|//[^/].*$||`）与「剥注释必须直接走 perl」的**整行锚定门**覆盖同一件事
⇒ 整行锚定天然挡住「兜底加回来」⇒ 冗余门**去重**。

⇒ **同步**（批 BY/BS：期望值要如实改，说明要同步改）：
审计器 `return 2` **5 → 6**、审计器 `return 0` **2 → 3**、
`ci.sh` 失败上报出口 **27 → 30**、`ci-d2.sh` **2 → 5**、
门项总数基线 **913 → 923**；豁免表**不变**（13 条）。

**⑥ ⚠⚠⚨ 负控（14 条断言全绿）**

- **A（行为级 · 3 条 · 可复现）**：
  A1.1 无 perl ⇒ 三个脚本**必须红**且**红因指名道姓含 perl**；
  A2.1 无 perl ⇒ 审计器**必须 rc=2** + 消息含 perl（改前是 rc=1 未捕获异常）；
  A3.1 `ci.sh` 抽出来的口径与 `ci-wiring.sh` **必须逐字节一致**
  （改前：12 个真实源文件不一致）⇒ **实测差异文件数 = 0 / 共 279**。
  ⚠⚠⚨ 这三条断言的是「**必须判失败并指名道姓**」
  ⇒ **同一份脚本在改前红、改后绿** ⇒ 比批 CD 的负控 A **更可复现**；
- **B（门项级 · 10 条 · 各变异一次）**：① `ci.sh` 加回自己的 perl 实现 ⇒ 红；
  ② `ci-d2.sh` 加回 ⇒ 红；③ `ci.sh` 抽取+自检行改掉 ⇒ 红；
  ④ `ci-d2.sh` 同 ⇒ 红；⑤ `ci-wiring.sh` 前置检查被摘掉 ⇒ 红；
  ⑥ `ci.sh` 前置检查被摘掉 ⇒ 红；⑦ `ci-d2.sh` 前置检查被摘掉 ⇒ 红；
  ⑧ 剥注释加回 sed 兜底 ⇒ 红；⑨ 审计器的前提检查被改名 ⇒ 红；
  ⑩ 审计器的前提检查**没被调用** ⇒ 红
  ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）；
- **C（增量价值 · 1 条）**：变异「`ci.sh` 改回自己的旧口径实现」下
  **改前的所有门全绿**（口径分裂**没人守**）⇒ 而**只有批 CF 的 forbid 门红**
  （旧门红=False，新门红=True）。
⇒ 累计 **618/618**。

**⑦ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **「抽取」对独占 `}` 行敏感** —— ⚠⚠⚨ **本批自己踩到了**：
  第一版实现给 `strip_comments` 加了 `|| { … }` ⇒ 引入**独占的 `}` 行**
  ⇒ `ci.sh` / `ci-d2.sh` 抽到**残缺函数** ⇒ `ci.sh` 的 verify 接线门**误报红 2 条**
  ⇒ ⚠ **教训**：**复用实现的方式本身要有自检** ⇒ 已加「抽取自检」（行为级挡住后果），
  但**成因**只靠注释提醒 ⇒ ⚠ 「独立 lib 文件 + source」会更稳（**本批未做**）；
- ⚠ **剥注释工具本身失败**（文件不可读 / perl 崩）⇒ 管道仍会掩盖退出码
  ⇒ 本批**只收了「perl 缺席」这一类** ⇒ 「文件不可读」类留给下一批
  （批 CE 只在图标收口那一个点加了可读性验证，其余扫描点仍会漏检）；
- ⚠ **本批原计划的盘点**（18/18 无 `pipefail`、26 处命令替换内 `|| true`）
  **没有变成常驻判据** ⇒ 「**盘点方法本身也要被门守**」仍未做；
- ⚠ **影响面实测为零**：6 条 `wire_need` 命中数新旧口径**全同**、
  D2 命中数**全同**、`.py` 无差异 ⇒ 本批是**纯隐患收口**，不改任何现有判定；
- ⚠ `perl` 缺席时**整个 CI 会红**（而不是降级跑完）⇒ 这是**故意的**
  （口径无法确定 ⇒ 未验证不许被当成通过；批 CB/CC/CD/CE 同款口径）。

**⑧ ⚠⚠⚨ 落门 / 判据（数字）**

- 门项物理行数 **913 → 923**（+10）；执行次数 **916 → 926**；
  门项总数基线 `ci-wiring-gates.baseline` = **913 → 923**；豁免表**不变**（13 条）。
- 接线门 **926** 项全绿、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 14/14 真红**。
- **视觉变化**：无（只动判据层脚本与文档；快照零变化）。
### E.2ap 「剥注释失败」不许被当成「没找到」（批 CG）

**① 起因（实测盘点，不是推演）**

本批原计划盘「命令替换内的 `|| true`」与「无 pipefail 的管道」
（实测：`scripts/` 下 **18/18** 个 shell 脚本**都没开** `pipefail`；
命令替换内带 `|| true` 的站点 **26** 处）
⇒ 盘点中先坐实一个**更硬的洞**，先收它：

- `strip_comments` 的调用点共 **13** 处
  ⇒ 其中 **3** 处在 `probe_scan_find` 内（已被批 BI 的懒探测覆盖）
  ⇒ **11 处未覆盖**；
- `arch_need_any_min` 的 N **必须配准**（余量恒为 0）⇒ 那条路**不假绿**
  ⇒ 用**排除法**排除了「靠它兜住」的可能。

⇒ 剩下的口子只有一个：**剥注释工具**自己失败时，下游看不出来。

**② ⚠⚠⚨ 洞（旗舰 · 实测坐实）**

批 CE 只在「**图标收口那一个**扫描点」加了「文件不可读 ⇒ 判失败」
⇒ 其余调用点（forbid / need / count / any …）**都没有这层保护**。

⚠⚠⚨ **对照实验（同一个文件、同一份内容，只改权限）**：

- 文件**可读** ⇒ `✗ raise 不再散落在界面代码里：… —— src/…/zzAzCgProbe.cpp`
  ⇒ 门**红**（违例被抓到）；
- 文件**不可读**（`chmod 000`）⇒ 那一行**整个消失**
  ⇒ 该 forbid 门**静默变绿**。

⇒ ⚠⚠⚨ **彻底假绿**：探针放 `src/logic/`
（**不在**批 CE 那一处的保护范围内）
⇒ **接线门 rc=0 全绿**、✗ 行数 0 ⇒ 违例**完全没被看见**。

**③ ⚠⚠⚨ 根因实测（关键）**

⚠⚠⚨ **`perl` 打不开文件时，退出码仍是 0**
（只往 stderr 打一句「Can't open …: 权限不够」）
⇒ **靠退出码抓不住「读不了」**
⇒ ⚠ **对照**：`sed` 读不了是 **2**、`grep` 读不了是 **2** ⇒ **只有 perl 是 0**。

根因之二：管道里**拿不到** `strip_comments` 的退出码
（管道退出码 = 最右命令的）⇒ 「输出为空」与「工具失败」
在下游**长得一模一样** ⇒ forbid 门判「没找到」⇒ 绿。

**④ 修法（只动判据层 ⇒ 零产品代码改动）**

① `strip_comments` **先验可读性**（`[ ! -r "$1" ]`）
   ⇒ 读不了 ⇒ **写标记文件**
   （⚠ 跨子 shell ⇒ **变量传不出去** ⇒ 只能落文件）⇒ 正常路径**零开销**；
② 三个脚本（`ci-wiring.sh` / `ci.sh` / `ci-d2.sh`）**末尾统一检查标记**
   ⇒ 有 ⇒ **判红 + 指名道姓**列出失败的文件；
③ 末尾检查放在「✓ 全绿」**之前** ⇒ 那个「✓」**永远打不出来**。

⇒ ⚠⚠⚨ 一次挡住**整类**（批 CD 纪律：一次挡住整类，别逐点治标）：
forbid / need / count / any … **全部**剥注释调用点都受益。

⚠ 为什么**不用落盘重写**（批 BI 已实测否决）：管道 → 落盘慢 **20 倍**
（30ms vs 1.5ms）⇒ 2511 次调用 ⇒ 84 秒 ⇒ CI 不可接受。

⚠ 为什么**不用懒探测**（批 BI 已有）：它只验「工具活着」，
**盖不住「这一次调用」失败**（文件不可读时工具是活的）。

**⑤ ⚠⚠⚨ 落门 / 判据（本批新增 8 条 + 原地替换 1 条）**

| 目标 | 门型 | 盯什么 |
|---|---|---|
| `ci-wiring.sh` | 整行锚定（**恰好 1 处**） | 可读性先验支的「写标记」 |
| `ci-wiring.sh` | 整行锚定（**恰好 2 处**） | sed 支 + perl 支的「写标记」 |
| `ci-wiring.sh` | 整行锚定 | 标记文件**定义**那一行 |
| `ci-wiring.sh` | 整行锚定 | **末尾检查**那一行 |
| `ci.sh` | 整行锚定 | 标记文件**定义**那一行 |
| `ci.sh` | 整行锚定 | **末尾检查**那一行 |
| `ci-d2.sh` | 整行锚定 | 标记文件**定义**那一行 |
| `ci-d2.sh` | 整行锚定 | **末尾检查**那一行 |

⇒ **原地替换 1 条**：批 CF 的「剥注释**必须直接走 perl**」
（形态改成「`if ! perl …; then`」⇒ **失败要接住**）⇒ **不增行**（批 BM 纪律）。

⇒ ⚠ ⚠⚠ **同内容不同缩进是常态** ⇒ 整行锚定必须**按缩进拆成两条门**
（⚠ **本批自踩**：一条正则罩不住多缩进 ⇒ 审计器报「期望 3 ≠ 实际命中 1」）。

⇒ **同步**（批 BY/BS：期望值要如实改，说明要同步改）：
`ci.sh` 失败上报出口 **30 → 31**、`ci-d2.sh` **5 → 6**、
门项总数基线 **923 → 931**；豁免表**不变**（13 条）。

**⑥ ⚠⚠⚨ 负控（16 条断言全绿）**

- **A（行为级 · 6 条 · 可复现）**：
  - A0.1 **基线**：干净工作区 ⇒ 接线门必须 rc=0
    （否则后面「红」没有说服力）；
  - A1.1 **改后**：源文件不可读 ⇒ 接线门**必须红**且**红因指名道姓**
    ⇒ 实测点名了 `src/logic/zzAzCgProbe.h`；
  - A2.1 **对照实验（只改权限）**：可读 ⇒ forbid 门红在「违例被检出」；
    不可读 ⇒ forbid 门**绿**（违例看不见）⇒ **违例本身仍然漏检**；
  - A3.1 ⚠⚠⚨ **改前对照**：三个脚本**回退到 HEAD**（批 CF 状态）
    ⇒ 同一场景 **rc=0 全绿** ⇒ **假绿坐实**
    ⇒ 证明这批改动正是堵它的；
  - A4.1 **单元级**：三个脚本**各自**的标记变量 + 抽出来的 `strip_comments`
    ⇒ 对不可读文件**必须真的写标记**
    （变量不在就写不进去 ⇒ 失败被静默吞掉）⇒ 实测三个脚本都写了并点名；
  - A5.1 **回归**：`ci-d2.sh` 遇到不可读源文件 ⇒ 必须红
    且**不许**打印「✓ D2 命中 0/0」
    ⇒ ⚠ **如实标注**：这条主要是批 CD 的「先验可读性」兜住的，批 CG 是第二道；
- **B（门项级 · 9 条 · 各变异一次）**：
  ① 可读性先验支的写标记被摘掉 ⇒ 红；
  ② sed 支的写标记被摘掉 ⇒ 红（**恰好 2 处少一处就红**）；
  ③ `ci-wiring.sh` 的标记变量定义被改名 ⇒ 红；
  ④ `ci-wiring.sh` 末尾的标记检查被改掉 ⇒ 红；
  ⑤ `ci.sh` 的标记变量定义被改名 ⇒ 红；
  ⑥ `ci.sh` 末尾的标记检查被改掉 ⇒ 红；
  ⑦ `ci-d2.sh` 的标记变量定义被改名 ⇒ 红；
  ⑧ `ci-d2.sh` 末尾的标记检查被改掉 ⇒ 红；
  ⑨ 剥注释的 perl 调用行被改回旧形态（失败不再接住）⇒ 红
  ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）；
- **C（增量价值 · 1 条）**：不可读文件下，
  **forbid 违例门仍然是绿的**（违例仍不可见）
  ⇒ 唯一把问题喊出来的是批 CG 的「失败留标记 + 末尾统一判红」机制。
⇒ 累计 **634/634**。

**⑦ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **「读不了」靠先验可读性挡住**；`strip_comments` 若在**别的**原因上失败
  （perl 崩等）⇒ 退出码能抓到（这一类不靠退出码）；
- ⚠ 「独立 lib 文件 + source」比「抽取」更稳（**本批未做**）；
- ⚠ 批 CE 在 `src/ui/` 那一处的可读性验证现在与批 CG 机制**双重保护**
  （批 CE 那条门**保留未动**）；
- ⚠ **本批原计划的盘点**（18/18 无 `pipefail`、26 处命令替换内 `|| true`）
  **没有变成常驻判据** ⇒ 「**盘点方法本身也要被门守**」仍未做；
- ⚠ **影响面实测为零**：只动判据层脚本 ⇒ **零产品代码改动**、快照**零变化**；
- ⚠ 负控里「改前世界」必须**连基线文件一起回退**
  ⇒ 否则「门自审计」会因「门项行数与基线不符」而红
  ⇒ **红因指错方向** ⇒ 拿不到「假绿」这个结论（⚠ **本批踩到**）。

**⑧ ⚠⚠⚨ 落门 / 判据（数字）**

- 门项物理行数 **923 → 931**（+8）；执行次数 **926 → 934**；
  门项总数基线 `ci-wiring-gates.baseline` = **923 → 931**；豁免表**不变**（13 条）。
- 接线门 **934** 项全绿、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 16/16 真红**。
- **视觉变化**：无（只动判据层脚本与文档；快照零变化）。
### E.2aq 「盘点方法本身」也要被门守：审计器自己读不了不许当成「没问题」（批 CH）

**① 起因（实测盘点 + 对照实验，不是推演）**

批 CG 收了 **shell 侧三处**（`ci-wiring.sh` / `ci.sh` / `ci-d2.sh`）的「剥注释失败」
⇒ 但**判据层自己**还有**第四份**剥注释实现 = **审计器**（python 侧）
⇒ 它把「源文件读不了」当成「**这个文件里没有**」。

⚠⚠⚨ 批 CD 早就把这件事摆到台面上过：
**「盘点方法本身也要被门守」** —— 批 CD 的错误结论（「危险方向 0 处」）
就是这么来的（口径有盲区 ⇒ 结论错 ⇒ 而没人守这个口径）。
⇒ 批 CH 就是那块砖：**审计器就是判定层常驻的「盘点方法」**。

**② ⚠⚠⚨ 洞 ①（诊断失真 · 实测坐实）**

被盯的源文件不可读（`chmod 000`）⇒ 审计器 `--list`：

- 退出码 **5**；
- 消息是「**有门项命中 0 次（3 条）⇒ 那些门永远匹配不到（形同虚设）**」；
- ⚠⚠⚨ **完全不提「不可读 / 权限」**（实测 grep 计数 = **0**）。

⇒ 真实原因是**权限**，报告说的是「**门写错了**」⇒ 排障被带偏（批 CE 纪律：
诊断不许失真）。

**③ ⚠⚠⚨ 洞 ②（崩在栈里 · 实测坐实）**

审计器自己依赖的文件不可读 ⇒ **未捕获 `PermissionError`** ⇒ 退出码 **1**
⇒ 门侧只能报「**未知的失败码**」⇒ 真实原因没有任何一条消息提到：

| 不可读的文件 | 改前 | 改后 |
|---|---|---|
| `scripts/ci-wiring.sh`（门脚本） | rc=1（栈回溯） | rc=2（指名道姓） |
| `scripts/wiring-multi-hit.exempt` | rc=1 | rc=2 |
| `scripts/ci-wiring-gates.baseline` | rc=1 | rc=2 |

⇒ ⚠ 批 CF 修过「**缺 perl**」的**同一形状**（未捕获异常 ⇒ rc=1 ⇒「未知的失败码」），
**但没管「文件读不了」** ⇒ 同款洞留到了批 CH。

**④ ⚠⚠⚨ 洞 ③（假绿的机制缺口 · 单元级坐实）**

审计器用「**命中数 == 期望数**」判绿 ⇒ 而「读不了」产生的命中数恰好是 **0**
⇒ **凡是期望 0 次的门**，被盯文件读不了时 ⇒ 命中 0 == 期望 0
⇒ 校准说「0 条失准」⇒ **审计器判绿** ⇒ 而那个文件**根本没被审**。

⚠ **如实记**：仓里有 **36** 条「期望 0 次」的门
⇒ 但**当前仓里**每个被期望-0 门盯着的文件**同时**被别的门盯着
⇒ 端到端实测是 rc=5（红，但**红因指错**）⇒ **彻底假绿尚未落地**；
⇒ 但**机制缺口是真的**（单元级实测：旧版 `count_hits` 对不可读文件返回 **0**
⇒ 与「期望 0 次」**配平**）⇒ 必须先挡住。

**⑤ ⚠⚠⚨ 洞 ④（门侧 · 负控 A6.1 逮到）**

⚠⚠⚨ 批 CG 把诊断放在**脚本末尾** ⇒ 而段落末尾的
`if [ "$ARCH_FAIL" -ne 0 ]; then … exit 1` 会**提前 exit**
⇒ 末尾的标记检查**根本跑不到** ⇒ 「剥注释失败」诊断**打不出来**
⇒ 门侧只报「**出现 0 次（期望 2 次）**」⇒ **真话被藏了**。

⇒ 修法：诊断搬进**退出 trap** ⇒ 无论从哪退出都会打出来并点名那个文件；
末尾的显式检查只负责 `exit 1`（诊断不再重复打）。

**⑥ 修法（只动判据层 ⇒ 零产品代码改动）**

① **统一读入口** `read_source()`：读不了 ⇒ 抛 `UnreadableSource`
   ⇒ 所有读源文件的地方都走它 ⇒ 一次挡住整类（批 CD 纪律）；
② **先验可读性**（`os.access` 用**真实 uid** ⇒ 与 shell 的 `-r` 同口径
   ⇒ **两侧口径一致**，不会一边绿一边红）；
③ **接住工具的退出码**（批 CG 纪律：工具失败 ≠ 没找到）
   ⇒ ⚠⚠⚨ **实测**：`perl` 打不开文件时退出码仍是 **0** ⇒ 只靠退出码抓不住
   ⇒ 必须先验；
④ **顶层兜底** ⇒ 指名道姓 + **rc=2**（盲区：那些门项**根本没被审**）
   ⇒ 与「缺 perl」同款 ⇒ 门侧的 rc=2 分派消息**同步补一句**（批 BB）；
⑤ **门侧诊断搬进退出 trap**（见洞 ④）。

**⑦ ⚠⚠⚨ 落门 / 判据（本批新增 14 条 + 原地替换 5 条）**

| 目标 | 门型 | 盯什么 |
|---|---|---|
| `ci-wiring-audit.py` | **forbid** | **不许再直接用 `open` 读源文件**（必须走 `read_source`） |
| `ci-wiring-audit.py` | 整行锚定 | `class UnreadableSource(Exception):`（**带左括号**） |
| `ci-wiring-audit.py` | 整行锚定 | `def read_source(path):`（**带左括号**） |
| `ci-wiring-audit.py` | 整行锚定 | `if not os.access(path, os.R_OK):`（**先验可读性**） |
| `ci-wiring-audit.py` | 整行锚定 | `if _tool_rc != 0:`（**接住工具退出码**） |
| `ci-wiring-audit.py` | 整行锚定 ×3 | 三处 `raise UnreadableSource(...)`（**失败点逐条钉住**） |
| `ci-wiring-audit.py` | 整行锚定 | `except UnreadableSource as e:`（**顶层兜底**） |
| `ci-wiring-audit.py` | 整行锚定 | `def main():`（**顶层入口** ⇒ 兜底不许被摘） |
| `ci-wiring.sh` | 整行锚定 | rc=2 的分派消息**必须提到「源文件读不了」** |
| `ci-wiring.sh` / `ci.sh` / `ci-d2.sh` | 整行锚定 ×3 | 退出 trap **必须带剥注释失败的诊断** |

⇒ **原地替换 5 条**（批 BM 纪律：不增行）：
审计器 `return 2` 条数 **6 → 7**（新增的顶层兜底）；
rc=2 的分派消息（**说明必须与实际行为一致**，批 BB）；
批 CG 那 3 条「末尾检查」门的**说明文字**（机制变了 ⇒ 说明要跟着改）。

⇒ **同步**（批 BY/BS：期望值要如实改，说明要同步改）：
门项总数基线 **931 → 945**；豁免表**不变**（13 条）。

⚠⚠⚨ **门项正则一律由现抽实际行生成**（批 BS 纪律：绝不手写）——
包括 trap 那 3 条：**结构钉死、措辞自由**
（`[^;]*剥注释失败[^;]*` ⇒ 只锁「必须提到这一类」⇒ 改文案不会假红）。

**⑧ ⚠⚠⚨ 负控（23 条断言全绿）**

- **A（行为级 · 7 条 · 可复现）**：
  A0.1 **基线**：干净工作区 ⇒ 审计器必须 rc=0；
  A1.1 **改后**：被盯的源文件不可读 ⇒ 审计器**必须 rc=2** 且**指名道姓**；
  A2.1 **改前对照·诊断失真**：旧版审计器同一场景 ⇒ rc=5
  且**完全不含任何权限字样**（报成「门形同虚设」）；
  A3.1 **改前对照·崩在栈里**：门脚本不可读 ⇒ 旧版 rc=1（`PermissionError`）
  ⇒ 新版 rc=2 且点名；
  A4.1 **假绿的机制缺口（单元级）**：旧版 `count_hits` 对不可读文件返回 **0**
  ⇒ 与「期望 0 次」**配平** ⇒ 假绿；新版必须**抛**（配平不可能发生）；
  A5.1 **改后**：豁免基线 / 门项总数基线不可读 ⇒ rc=2 且指名道姓；
  A6.1 **两侧口径一致**：同一场景 ⇒ 门侧 rc≠0 且说「**剥注释失败**」；
  审计器 rc=2 且说「**读不了**」⇒ 两边都红、都说真话；
- **B（门项级 · 16 条 · 各变异一次 ⇒ 全红）**：
  ① 审计器加回直接 `open` 读源文件 ⇒ 红（forbid 门）；
  ② 异常类被改名 ⇒ 红；③ 统一读入口被改名 ⇒ 红；
  ④ 不再先验可读性 ⇒ 红；⑤ 不再接住工具退出码 ⇒ 红；
  ⑥⑦⑧ 三处 `raise` 各改成静默返回空 ⇒ 红；
  ⑨ 顶层不再兜底 ⇒ 红；⑩ 顶层入口被改名 ⇒ 红；
  ⑪ rc=2 分派消息里删掉「源文件读不了」⇒ 红；
  ⑫ 新增的那处 `return 2` 改成别的码 ⇒ 红（批 CC 口径：按码值分桶 ⇒ 旧桶 7→6）；
  ⑬ **正向**：审计器里「直接 open 读源文件」的写法**恰好 0 处** ⇒ forbid 门必须绿；
  ⑭⑮⑯ 三个脚本的 trap 里去掉诊断 ⇒ 红
  ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）；
⇒ 累计 **657/657**。

**⑨ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **假绿尚未端到端落地**（洞 ③）：当前仓里每个被期望-0 门盯着的文件
  **同时**被别的门盯着 ⇒ 改前落的是「**红因指错**」而不是「彻底假绿」
  ⇒ 单元级已坐实机制缺口（`count_hits` 返回 0）；
- ⚠ **审计器的 `return 2` 现在有两种来源**（「缺 perl」/「源文件读不了」）
  ⇒ 门侧的 rc=2 分派消息**必须把两种都说清楚**（批 BB）⇒ 本批已同步；
- ⚠ **门侧 trap 的诊断只覆盖「剥注释失败」** ⇒ 其它失败态（门项红、审计器红）
  仍是各自报各自的 ⇒ 这是**故意**的（批 CE：诊断不许失真 ⇒ 一个失败态一条消息）；
- ⚠ **审计器只审「门项涉及的文件」** ⇒ 那些文件之外的不可读，审计器不管
  （门侧管）⇒ **两侧互补**，不是重复；
- ⚠ **本批原计划的盘点**（18/18 无 `pipefail`、26 处命令替换内 `|| true`）
  **仍未变成常驻判据** ⇒ 「**盘点方法本身也要被门守**」只做了**第一块砖**；
- ⚠ **影响面为零**（只动判据层脚本 ⇒ 零产品代码改动 ⇒ 快照零变化）；
- ⚠⚠⚨ **本批自踩两处**：
  ① 用 `rfind("'")` 找标签的**开引号** ⇒ 拿到的是**闭引号**
  ⇒ 新标签被接在旧标签后面 ⇒ 每行 5 个引号 ⇒ **shell 语法坏掉**
  ⇒ ⚠ **教训：门项行的引号定位要用「第 3 个单引号」**，不要用 `rfind`；
  ② 负控里「改前对照」的**测量时机**踩了坑（还原权限后才测新版
  ⇒ 新版当然 rc=0）⇒ ⚠ **教训：两次测量必须在同一权限状态下**。

**⑩ ⚠⚠⚨ 落门 / 判据（数字）**

- 门项物理行数 **931 → 945**（+14）；执行次数 **934 → 948**；
  门项总数基线 `ci-wiring-gates.baseline` = **931 → 945**；豁免表**不变**（13 条）。
- 接线门 **948** 项全绿、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 23/23 真红**。
- **视觉变化**：无（只动判据层脚本与文档；快照零变化）。
### E.2ar 「未验证」不许被当成「通过」（批 CI）

**① 起因（实测盘点 + 对照实验，不是推演）**

批 CB 给契约门留了**专属退出码 3**（未验证）⇒ CI 侧也分诊了 0/3/其它
⇒ 但 ⚠⚠⚨ **内层的 SKIP 根本没上报**：

⚠⚠⚨ 盘点：`scripts/` 下**命令替换内带 `|| true`** 的站点 **21 处**
⚠⚠⚨ **批 CJ 实测订正**（台账 E.2as）：此处原写「**24 处**」⇒ **多了 3 处假阳性**（原盘点器**跨行合并把注释并进块**⇒ 跨度配对错乱）；⚠ **三个盘点器给出 24 / 26 / 21 三个数** ⇒ 一次性盘点的数字**不可信** ⇒ 批 CJ 已把盘点**搬进仓内常驻脚本 + 逐处带理由的登记册**
（批 CG / 批 CE 的原盘点说 26 处 ⇒ **本批实测口径是 24**）
⇒ 这 21 处是「**命令替换内部把退出码吞掉**」的形状（批 AZ 纪律：
`|| true` 才是真正吞退出码的东西，管道本身不吞）。

**② ⚠⚠⚨ 洞 ①（内层 SKIP 不计数 · 实测坐实）**

契约门里 **14 处内层 SKIP**（客户端二进制缺席 / 打桩服务器没起来 /
GitHub API 不可达 / 没有 curl / 没有 python3 …）**只打印、不计数**
⇒ 末尾判 `fail` ⇒ **exit 0**
⇒ ⚠⚠⚨ **「这些组根本没验」被当成「通过」**。

⚠⚠⚨ **实测（客户端缺席场景，`DEEPGIT_CLIENT_BIN` 指空）**：

| | 结果 |
|---|---|
| 旧版（HEAD）汇总行 | `85 passed, 1 failed`（**没有「未验证」这一项**） |
| 新版汇总行 | `85 passed, 1 failed, 9 unverified` |
| 实际 SKIP 条数 | **9**（`grep -c SKIP` = 9，与 unverified 计数对得上） |

⇒ 旧版里那 **9 组**既没算失败、也没算未验证 ⇒ 只要别的都过 ⇒ **exit 0**
⇒ 而**每条 SKIP 消息里都写着「本项**未验证**，不算通过」**
⇒ ⚠⚠⚨ **说法比门宽**（批 AA 教训：承诺写在那儿，判据却不认它）。

**③ ⚠⚠⚨ 洞 ②（取数失败落进「判通过」那一支 · 实测坐实）**

`E2E_OUT` 取数失败 ⇒ `E2E_N=""` ⇒ `[ "" -eq 0 ]` 在 **dash** 里
报「**Illegal number**」并返回 **2** ⇒ `if` 判假 ⇒ 落到 elif
⇒ `[ 0 -ne 0 ]` 假 ⇒ **else ⇒ 判通过**
⇒ ⚠⚠⚨ **取数失败被当成「没有问题」** ⇒ 假绿。

⇒ ⚠ **教训（通用）**：`[ "" -eq 0 ]` 不是「假」，它是**类型错误**
⇒ 退出码 **2** ⇒ `if` 判假 ⇒ 条件落空 ⇒ 落进**下一个分支**。
⇒ **空值必须先判空**（`-z`），不许直接进数值比较。

**④ ⚠⚠⚨ 洞 ③（CI 层「未验证」仍绿 · 收掉批 CB 的已知边界）**

CI 第 10 步收到契约门的 rc=3 时，**只打印「不算通过」** ⇒ **CI 继续**
⇒ 最后照样打「**✓ CI 门通过**」
⇒ **核心门根本没验，却说 CI 通过** ⇒ 假绿。
引擎缺席那一支**同理**（连契约门都没跑起来）。
⇒ ⚠ 这是**批 CB 明知并记下的边界**（「SKIP 后 CI 仍绿」）⇒ 本批收口。

**⑤ 修法（只动判据层 ⇒ 零产品代码改动）**

① **契约门加「未验证」计数器** `skip`；**14 处内层 SKIP 各加**
   `skip=$((skip+1))`（缩进分布：4 空格 **4** 处 / 8 空格 **7** 处 /
   12 空格 **3** 处 ⇒ 合计 14）；
② **末尾按未验证判**：
   `if [ "$skip" -ne 0 ] && [ "$fail" -eq 0 ]; then … exit 3; fi`
   ⇒ ⚠ **失败优先**（真有失败 ⇒ 仍报 1 ⇒ 未验证**不掩盖**失败）
   ⇒ ⚠ 该写法**不含 `fail=`** ⇒ 「写 fail 变量的行数」那条门不受影响
   ⇒ ⚠ 末尾判定行 `[ "$fail" -eq 0 ]` **原样保留** ⇒ 那条门也不受影响；
③ **取数失败先判空**：`[ -z "$E2E_N" ] || [ "$E2E_N" -eq 0 ]`
   ⇒ 空 ⇒ 走「没取到可比对的符号」那一支（**判红**）；
④ **CI 第 10 步**：**rc=3 ⇒ 判红**；**引擎缺席 ⇒ 判红**
   ⇒ ⚠ 批 CB 已给契约门留了专属码 3 ⇒ 这一层能分清「未验证」与「失败」。

**⑥ ⚠⚠⚨ 落门 / 判据（本批新增 7 条 + 原地替换 3 条）**

| 目标 | 门型 | 盯什么 |
|---|---|---|
| `contract-check.sh` | 整行锚定 | `pass=0; fail=0; skip=0`（**必须有「未验证」计数器**） |
| `contract-check.sh` | 整行锚定 ×3 | 三种缩进的 `skip=$((skip+1))`（**恰好 4 / 7 / 3 处**） |
| `contract-check.sh` | 整行锚定 | 末尾 `if [ "$skip" -ne 0 ] && [ "$fail" -eq 0 ]; then`（**按未验证判**） |
| `contract-check.sh` | 整行锚定 | `if [ -z "$E2E_N" ] \|\| [ "$E2E_N" -eq 0 ]; then`（**取数失败不许落进「判通过」**） |
| `ci.sh` | 整行锚定 | 引擎缺席支的 `✗ 引擎契约门**未验证**…`（**必须判红**） |

⇒ **原地替换 3 条**（批 BM 纪律：不增行）：
① `ci.sh` 的 `exit [1-9]` 条数 **31 → 33**（两处判红各带一个 `exit 1`）；
② 契约门 `^    exit 3$` 条数 **1 → 2**（新增末尾那处）；
③ CI 第 10 步的 SKIP 支门 ⇒ 改成**盯判红那行**（措辞从「SKIP…不算通过」
   改成「✗…未验证」⇒ 机制变了 ⇒ **说明文字必须同步改**，批 BB）。

⇒ **同步**（批 BY/BS：期望值要如实改，说明要同步改）：
门项总数基线 **945 → 952**；豁免表**不变**（13 条）。

⚠⚠⚨ **门项正则一律由现抽实际行生成**（批 BS 纪律：绝不手写）
⇒ 三种缩进**各成一条门**（批 CG 教训：同内容不同缩进是常态
⇒ 一条整行正则罩不住）。

**⑦ ⚠⚠⚨ 负控（15 条断言全绿）**

- **A（行为级 · 5 条 · 可复现）**：
  A0.1 **基线**：契约门正常跑 ⇒ rc=0 且 `120 passed, 0 failed, 0 unverified`；
  A1.1 **改前对照**：客户端缺席 ⇒ **旧版汇总行里「未验证」不可见**
  ⇒ **新版看得见**（`unverified` 项且计数为正）⇒ 坐实「内层 SKIP 不计数」；
  A2.1 **单元级·末尾判定三情形**：只有未验证 ⇒ **exit 3** /
  有未验证且有失败 ⇒ **exit 1**（失败优先）/ 都没发生 ⇒ 0；
  A3.1 **单元级·取数失败**：`E2E_N` 为空 ⇒ **必须落进「判红」那一支**
  ⇒ 不许落进「判通过」（⚠⚠⚨ 改前落进「判通过」）；
  A4.1 **CI 层**：契约门**未验证**（rc=3）与**引擎缺席**两处
  ⇒ 都必须**判红**且**后面真的跟着 `exit 1`**；
- **B（门项级 · 10 条 · 各变异一次 ⇒ 全红）**：
  ① 去掉未验证计数器 ⇒ 红；
  ②③④ 三种缩进的计数**各少一处** ⇒ 红（恰好 4 / 7 / 3）；
  ⑤ 末尾不再按未验证判 ⇒ 红；
  ⑥ 取数失败不再判空 ⇒ 红；
  ⑦ `ci.sh` 引擎缺席支改回只打印 ⇒ 红；
  ⑧ `ci.sh` 有一处失败上报出口被改成 `exit 0`（**离开失败桶**）⇒ 红；
  ⑨ 契约门新增的那处 `exit 3` 被改掉 ⇒ 红；
  ⑩ `ci.sh` 的 rc=3 分支改回只打印 ⇒ 红
  ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）
  ⇒ 累计 **672/672**。

**⑧ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **端到端「只有未验证、无失败 ⇒ exit 3」只有单元级覆盖**：
  端到端实测时**第 16 组先失败**（客户端缺席场景 ⇒ `1 failed`）
  ⇒ 失败优先那一支**抢先判红** ⇒ 端到端看到的是 rc=1
  ⇒ 「纯未验证 ⇒ rc=3」这条端到端路径**没被端到端跑到**
  ⇒ ⚠ **如实记**：这是**设计使然**（失败优先），不是漏网；
- ⚠ **假绿在当前仓落的是「红因指错」**：洞 ①/② 的假绿发生在
  「9 组未验 + 恰好 1 条真失败」这个组合下 ⇒ 端到端结果是**红**
  （不是绿）⇒ 但**红因指错**（报的是那 1 条失败，不是 9 组没验）
  ⇒ ⚠ 机制缺口是真的（单元级已坐实：旧版退出码 0）；
- ⚠ **「命令替换内 `|| true`」的 21 处盘点** 本批**仍未变成常驻判据**
  ⇒ 本批做的是「**内层 SKIP 计数 + 末尾判 + CI 判红**」这条**具体链路**
  ⇒ 21 处里其余的（`ci-wiring.sh` 的 7 处 `grep -c` 等）**仍是已知边界**
  ⇒ 「盘点方法本身也要被门守」**第二块砖**待落；
- ⚠ **本批只收「未验证 ⇒ 通过」这一类** ⇒ 其余形状
  （「工具失败 ⇒ 判通过」批 CE 已收 / 「剥注释失败 ⇒ 没找到」批 CG 已收 /
  「工具读不了 ⇒ 没问题」批 CD/CH 已收）**不在本批范围**；
- ⚠ **影响面为零**（只动判据层脚本 ⇒ 零产品代码改动 ⇒ 快照零变化）；
- ⚠⚠⚨ **本批自踩一处**：负控里「改前对照」必须用 **HEAD 版契约门**
  （`/tmp/az-ci-cc-old.sh`）跑 ⇒ 否则「旧版」其实也是新版
  ⇒ 对照实验作废（批 CH 同款教训：两次测量要在同一口径下）。

**⑨ ⚠⚠⚨ 落门 / 判据（数字）**

- 门项物理行数 **945 → 952**（+7）；执行次数 **948 → 955**；
  门项总数基线 `ci-wiring-gates.baseline` = **945 → 952**；豁免表**不变**（13 条）。
- 接线门 **955** 项全绿、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 15/15 真红**。
- **视觉变化**：无（只动判据层脚本与文档；快照零变化）。
### E.2as 「一次性盘点的数字」不许被当成事实（批 CJ）

**① 起因（实测坐实，不是推演）**

批 CG / 批 CE / 批 CI 的结论都引用过同一个数字：
「`scripts/` 下**命令替换内带 `|| true`** 的站点 **N** 处」
⇒ 那个数字来自**一次性盘点脚本**（还放在 `/tmp` 里，**不在仓内**）
⇒ ⚠⚠⚨ **仓内没有任何东西能重算出它** ⇒ 数字不可复核、不可 review。

⚠⚠⚨ **实测：三个盘点器给出三个数**

| 盘点器 | 口径 | 结果 |
|---|---|---|
| 批 CI 原盘点器（一次性） | **跨行合并把注释并进块** ⇒ 跨度配对错乱 | **24**（多 **3** 处**假阳性**） |
| 逐行 + **不剥注释** | 注释里的 `|| true` 也算 | **26** |
| **仓内常驻脚本**（批 CJ 新增） | 剥注释 + 正确的 shell 词法 + 嵌套括号 | **21（真值）** |

⇒ ⚠⚠⚨ **批 CI 已推送的文档里写的是「24 处」⇒ 错了**
⇒ ⚠⚠⚨ **同一个问题，两个盘点器两个答案，而没人能说清差在哪**
⇒ ⇒ **一次性盘点的数字不许被当成事实**。

**② ⚠⚠⚨ 洞（真洞 · 逐处才发现 · 实测坐实）**

`ci.sh` 的**分层纪律门**（判定层 `logic/` `models/` 零 QWidget 头）原先是：

```sh
GW_HITS="$(grep -rlE '#include…<QWidget…' \
    "$SRC/src/logic" "$SRC/src/models" 2>/dev/null || true)"
```

⚠⚠⚨ **源文件对 grep 不可读**（`chmod 000`）⇒ grep **静默跳过**它
⇒ 若那个文件里**有** QWidget 头 ⇒ `GW_HITS` 仍为空
⇒ **分层纪律门放行** ⇒ **假绿**。

⚠⚠⚨ **同一个洞在 `ci-d2.sh` 里已经被批 CD 堵上**
（那边加了 `find "$SRC/src" -type f ! -readable` 预检）
⇒ ⚠⚠⚨ **同一个洞堵一半比不堵更坏**（以为有门 ⇒ 实际没有）。

**③ 修法（只动判据层 ⇒ 零产品代码改动）**

① **仓内常驻盘点脚本** `scripts/ci-true-audit.py`：
   - **复用判据层自己的剥注释**（直接 import `ci-wiring-audit.py` 的
     `strip_comments`）⇒ **单一真相源**（批 CF 纪律：绝不复刻）；
   - ⚠⚠⚨ **抽取自检**（批 CF 教训：「**复用实现的方式本身要有自检**」）：
     从 `ci-wiring.sh` **原文抽取** `strip_comments` 跑一遍，
     与审计器侧**逐字节对拍** ⇒ 口径漂移当场红；
   - ⚠⚠⚨ **正确的 shell 词法**：**单引号内不做替换**、**双引号内照样做替换**
     ⇒ ⚠⚠⚨ **实测踩出来的坑**：把双引号也当跳过 ⇒ 只认出 **2** 处（漏掉绝大多数）；
   - **嵌套括号**正确配对（`$(echo $(date))`）。
② **登记册** `scripts/ci-true-audit.baseline`（**独立文件**，批 BH 纪律）：
   **21 条**，每条 **6 段**、**逐条带理由**（批 BN 纪律）；
   - ⚠⚠⚨ **分隔符用 TAB 而不是 `|`**：理由里要写「`|| true`」
     ⇒ 用竖线分隔会把行**劈开** ⇒ 段数对不上 ⇒ 登记册**永远读不出来**；
   - **指纹不含行号**（行号漂移 ⇒ **假红** ⇒ 批 BS 纪律：假红比假绿更坏）
     ⇒ 指纹 = `文件<TAB>段<TAB>分类<TAB>末命令摘要<TAB>同指纹序号`；
   - **同指纹序号**用来区分「同款代码的两份拷贝」
     （实测 `ci-d2.sh` 的规则 1 / 规则 2 两段完全对称）。
③ **双向红**（批 BH 纪律：恰好口径双向红）：
   「实测有、登记册没有」⇒ **红**（新增未登记）；
   「登记册有、实测没有」⇒ **红**（登记册腐化 ⇒ 修好后请删那一行）。
④ **堵洞**：`ci.sh` 加 `find … ! -readable` 预检（照批 CD 同款口径）
   ⇒ 读不了 ⇒ **判失败** ⇒ 末尾的 `exit 1` 触发 ⇒ 「✓」永远打不出来。

**④ ⚠⚠⚨ 落门 / 判据（本批新增 15 条 + 原地替换 2 条）**

| # | 目标 | 门型 | 盯什么 |
|---|---|---|---|
| 1 | `ci-true-audit.py` | 整行锚定 | `TRUE_AUDIT_EXPECTED_ROWS = 21`（**条数基线常量**） |
| 2 | `ci-true-audit.py` | 整行锚定 | 条数**必须恰好等于**基线（批 BC + 批 BB） |
| 3 | `ci-true-audit.py` | 整行锚定 | 登记册**每行恰好 6 段** |
| 4 | `ci-true-audit.py` | 整行锚定 | 登记册**每行必须写清理由** |
| 5 | `ci-true-audit.py` | 整行锚定 | 判「**登记册有、实测没有**」（腐化方向） |
| 6 | `ci-true-audit.py` | 整行锚定 | 判「**实测有、登记册没有**」（新增方向） |
| 7 | `ci-true-audit.py` | 整行锚定 | **必须跑抽取自检**（批 CF 精神） |
| 8 | `ci-true-audit.py` | 整行锚定 | 失败上报出口 `return 1` **恰好 2 处**（批 CA 口径） |
| 9 | `ci-true-audit.py` | 整行锚定 | 入口必须 `sys.exit(main())`（批 CA） |
| 10 | `ci-true-audit.py` | 整行锚定 | **必须复用**判据层自己的剥注释（批 CF） |
| 11 | `ci-wiring.sh` | 整行锚定 | 接线门**必须真的跑一次盘点**（批 BD） |
| 12 | `ci.sh` | 整行锚定 | 分层纪律门**必须先验可读性**（堵真洞） |
| 13 | `ci.sh` | 整行锚定 | 读不了时**必须判失败** |
| 14 | `ci.sh` | 整行锚定 | 读不了时**必须真的置失败位** |
| 15 | `ci-true-audit.py` | **forbid** | **不许自己实现剥注释**（单一口径） |

⇒ **原地替换 2 条**（批 BM 纪律：不增行）：
① `ANCHOR_SCOPE_SUFFIXES` 那条门项**把整个常量写死**了
   ⇒ 适用范围加了 `ci-true-audit.py` ⇒ 正则失配 ⇒ **跟着改**（现抽生成）；
② `ARCH_FAIL=1` 的条数门 **37 → 38**（批 CJ 段新增一处失败位）
   ⇒ ⚠ **说明文字里的「恰好 37 处」同步改成 38**（批 BB：说明必须与实际一致）。

⇒ **同步**：门项总数基线 **952 → 967**；豁免表**不变**（13 条）；
恒真探针的**扫描范围基线**（python 文件数 **3 → 4**，独立文件）。

⚠⚠⚨ **门项正则一律由现抽实际行生成**（批 BS 纪律：绝不手写）——
含**尾注释**的门项（`ci.sh` 的 `CANVAS_FAIL=1`）也照抄整行
⇒ 与批 CD 段的既有形态**完全同款**。

**⑤ ⚠⚠⚨ 负控（22 条断言全绿）**

- **A（行为级 · 7 条 · 可复现）**：
  A0.1 **基线**：盘点脚本 rc=0 + 21 处 + 与登记册逐条相等；
  A1.1 **三个盘点器给出三个数**（24 / 26 / 21）⇒ 坐实「数字不可信」；
  A2.1 **真洞**：源文件对 grep 不可读 ⇒ **改前放行**（假绿坐实）
  ⇒ **改后判红**（两段都**现抽**：改前取 `git show HEAD:…ci.sh`，改后取工作区）；
  A3.1 **双向红**：新增未登记 ⇒ 红；登记册腐化 ⇒ 红；
  A4.1 登记册**条数基线**：删一行 ⇒ 红；
  A5.1 登记册**理由不许空**：清空一行理由 ⇒ 红；
  A6.1 **正向**：盘点脚本里「自实现剥注释」的写法**恰好 0 处** ⇒ forbid 门必须绿；
  ⚠⚠⚨ **A5.1 / A3.1 逮到两个「门形同虚设」（本批最有价值的副产物）**：
  ① `load_baseline` 原来用 `strip()` ⇒ **行尾空白被吃掉**
     ⇒ 「理由为空」的表现是「第 6 段是空白」⇒ 段数先变成 5
     ⇒ **「没有理由」那条判定永远到不了** ⇒ **门在，牙没有**
     （批 AX 的形状：门项盯的是它在不在，不是它能不能被触发）
     ⇒ 修法：**只去换行符**（`rstrip('\r\n')`）⇒ 空理由仍是「6 段 + 第 6 段为空」；
  ② **条数检查提前 `return 1`** ⇒ 「登记册多/少一行」会**先**被条数拦下
     ⇒ **「登记册腐化」那条判定永远到不了** ⇒ 又一个**门在、牙没有**
     ⇒ 修法：两个判定**都报、都不提前 return**（批 AZ：一个退出码可能对应
     两种原因 ⇒ 诊断不许只报一个）；
- **B（门项级 · 15 条 · 各变异一次 ⇒ 全红）**：
  ① 条数基线常量 21→20 ② 条数判定不再用常量 ③ 6 段检查改 5 段
  ④ 理由检查被摘掉 ⑤ 腐化方向被摘掉 ⑥ 新增方向被摘掉
  ⑦ 抽取自检不再跑 ⑧ 一处 `return 1` 改成 `return 0` ⑨ 入口不再 `sys.exit(main())`
  ⑩ 不再复用判据层的剥注释 ⑪ 接线门不再跑盘点
  ⑫ 分层纪律门不再先验可读性 ⑬ 读不了时不再判失败 ⑭ 判失败位被摘掉
  ⑮ 盘点脚本自己实现一份剥注释 ⇒ forbid 门红
  ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）。

**⑥ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **行尾注释里的 `|| true` 也会被算成站点**：
  判据层的剥注释**只剥整行注释**（行首锚定）⇒ 行尾注释留着
  ⇒ 将来谁在**行尾注释**里写 `|| true` ⇒ 盘点多一处 ⇒ 登记册对不上 ⇒ **红**
  ⇒ ⚠ **假红风险**（批 BS：假红比假绿更坏）⇒ **写行尾注释时避开 `|| true`**；
- ⚠ **登记册的维护成本**：每动一处都要改登记册 **+** 改条数基线
  ⇒ 基线改小会显眼（双向红）⇒ 但这是**已知代价**（如实记）；
- ⚠ **「理由写得对不对」机器判不了**：
  机器只校验「理由**非空**」⇒ 「这一处为什么可以留」是**人工**判断
  ⇒ ⚠ 这是本批**最弱的一环**（如实记）；
- ⚠ **危险方向是逐处人工判的**：本批把 21 处逐处判了「上游是否已先验可读性」
  ⇒ 其中 **1 处是真洞**（`ci.sh` 的分层纪律门）⇒ **已堵**
  ⇒ 但**新增**的站点由**写理由的人**负责 ⇒ 机器只兜「登记 + 非空」；
- ⚠ **本批只收「命令替换内 `|| true`」这一类** ⇒ 其余形状
  （批 CD/CG/CH/CI 已收的）不在本批范围；
- ⚠ **批 CI 的三份文档已订正**（「24 处」⇒ **21 处**）并**留痕**
  ⇒ 数字与来源都写在订正句里（批 BB：说明必须与实际一致）；
- ⚠ **影响面为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）；
- ⚠⚠⚨ **本批自踩六处**（后两处是**负控逮到的「门形同虚设」**，最有价值）：
  ① 扫描器把**双引号**也当「跳过」⇒ 只认出 **2** 处（漏掉绝大多数）
  ⇒ ⚠ **教训：shell 词法规则不许凭印象写，必须实测**
  （⚠ 批 CG 纪律的又一次印证）；
  ② 扫描器用**递归**处理引号状态 ⇒ **无限递归**（栈爆）⇒
  ⇒ ⚠ **教训：引号状态用状态机，不许递归**；
  ③ 登记册用 `|` 分隔 ⇒ 理由里写「`|| true`」⇒ 行被劈开 ⇒ 段数对不上
  ⇒ ⇒ 改用 **TAB 分隔**（批 BN 已有先例）；
  ④ 原地替换脚本**按分隔符切数字时切错**（37 → 387）
  ⇒ ⚠ **教训：改期望值要按「词」切，不能按固定字符数切**；
  ⑤ `load_baseline` 的 `strip()` **把空理由吃掉** ⇒ 「没有理由」判定**不可达**
  ⇒ ⚠ **教训：一条判定「在」不等于「能被触发」**（门项盯的是前者）；
  ⑥ **条数检查提前 `return`** ⇒ 「登记册腐化」判定**不可达**
  ⇒ ⚠ **教训：两个互斥原因的判定不许互相吞掉**（都要报出来）。

**⑦ ⚠⚠⚨ 落门 / 判据（数字）**

- 门项物理行数 **952 → 967**（+15）；执行次数 **955 → 970**；
  门项总数基线 `ci-wiring-gates.baseline` = **952 → 967**；豁免表**不变**（13 条）。
- 接线门 **970** 项全绿、selfcheck **395/0**、契约门 **120/0**、ci.sh **15/15**、
  ci-d2 **0/0**、快照**零变化**、审计器硬门与报告模式 **rc=0**、
  恒真探针 **rc=0**、孤儿探针 **rc=0**。
- **负控 22/22 真红**（⇒ 累计 **694/694**）。
- **视觉变化**：无（只动判据层脚本与文档；快照零变化）。










### E.2at 「未验证」不许被当成「通过」（批 CK · CI 自己这一层）

**① 起因（实测盘点，不是推演）**

盘点 `scripts/` 下所有「跳过 / 未验证」出口 ⇒ ⚠⚠⚨ **`ci.sh` 自己就有 6 处
「只打印、不计数」**：

1. `desktop-file-validate` 缺席 ⇒ desktop 合法性**没验**；
2. `appstream-util` 缺席 ⇒ metainfo 合法性**没验**；
3. 没有 `dpkg-deb` ⇒ **deb 构建没跑**（⚠⚠⚨ **D7 达标的必经**）；
4. 没有 deb 产物 ⇒ **deb 布局验收没跑**（⚠ **D7 的准验收**）；
5. deb 布局验收**脚本自己报 SKIP**（rc=3）⇒ ⚠⚠⚨ **与批 CI 修过的第 10 步完全同款**；
6. agent 工具面门报 SKIP（rc=3）⇒ 同款。

⇒ 全部「只打印、不算失败」⇒ **CI 继续跑** ⇒ 最后照样打
「**✓ CI 门通过**」⇒ ⚠⚠⚨ **未验的组被当成「通过」** ⇒ **假绿**。

⇒ ⚠⚠⚨ **旧立场还写死在 `ci.sh` 第 12 步的注释里**：「不算通过，但**不判失败**」
⇒ 那个立场**已被本批收掉**（批 BB：说明必须与实际行为一致）。

**② 修法（只动判据层 ⇒ 零产品代码改动）**

- ① `ci.sh` 加**未验证计数器** `skip`；6 处跳过各 `skip=$((skip+1))`
  （缩进分布：**4 空格 5 处** / **8 空格 1 处**）；
- ② 末尾：`if [ "$skip" -ne 0 ]; then … exit 3; fi`
  ⇒ ⚠ **专属退出码 3**（与契约门、agent 工具面门**同款口径**，批 CB / CI）；
  ⇒ ⚠ **失败优先**：`ci.sh` 是 `set -e` 逐步执行 ⇒ 真失败**当场** `exit 1`
  ⇒ 能走到末尾说明**没有真失败** ⇒ 这里只判「未验证」；
- ③ ⚠ 判定块必须**紧挨着**「✓ CI 门通过」**之前**
  ⇒ 顺序反了 ⇒ 「✓」先打出来 ⇒ 未验的组**已经被说成通过**了；
- ④ 第 12 步的**旧立场注释**改写（不再写「不判失败」）。

**③ 落门 / 判据**

- **新增 12 条**（**5 条整行锚定 + 7 条跨行锚定**）：
  - 整行锚定 5 条：`^skip=0$`（1 处）/ `^    skip=$((skip+1))$`（4 缩进 **5 处**）
    / `^        skip=$((skip+1))$`（8 缩进 **1 处**）
    / `^if [ "$skip" -ne 0 ]; then$`（1 处）/ `^    exit 3$`（1 处）；
  - 跨行锚定 7 条：6 处「**SKIP ⇒ 计数必须紧跟**」（各钉一处）
    + 1 条「判定块**必须紧挨着**「✓ CI 门通过」之前」；
- **原地替换 1 条**（批 BM：不增行）：`ci.sh` 的 `exit [1-9]` 条数 **33 → 34**
  ⇒ ⚠ **说明文字里的「恰好 33 处」同步改成 34**（批 BB）；
- **同步**：门项总数基线 **967 → 979**；豁免表**不变**（13 条）；
- ⚠⚠⚨ **门项正则一律由现抽实际行生成**（批 BS 纪律：绝不手写）。

**④ ⚠⚠⚨ 负控 16/16 真红**

- **A（行为级 · 4 条）**：
  ① **端到端正控**：当前 `ci.sh` ⇒ **rc=3** + 打出「未验证不许被当成通过」
     + **没有**「✓ CI 门通过」；
  ② **对照实验（单元级）**：**没有**判定块 + `skip=1` ⇒ **rc=0**
     + **打出「✓ CI 门通过」** ⇒ ⚠ **坐实旧行为就是假绿**；
  ③ **判定块双向**（现抽原文）：`skip=1` ⇒ **rc=3**（判红）/ `skip=0` ⇒ **rc=0**（放行）；
  ④ **计数有牙（单元级）**：现抽 `appstream-util` 那个 **else 段**
     ⇒ 未变异 ⇒ `skip=1` ⇒ **rc=3**；**删掉那行计数** ⇒ `skip=0` ⇒ **rc=0**
     ⇒ ⚠ **坐实「少一处计数 ⇒ 那一组未验不再被判红」**；
  ⇒ ⚠⚠⚨ **②④ 必须放单元级**（实测踩过）：端到端跑时，**任何对 `ci.sh` 的变异
  都会被接线门抓住** ⇒ 第 9 步就 `exit 1` ⇒ **根本走不到末尾**
  ⇒ 端到端对照实验**分不出**「因为未验证判红」还是「因为接线门红」⇒ **结论全假**；
  ⇒ ⚠ 接线门先红这件事**本身是好事**（说明门有牙）⇒ 但对照实验必须放单元级
  （现抽原文跑）；
- **B（门项级 · 12 条 · 各变异一次 ⇒ 全红）**：
  ① `skip=0` 被追加内容 ② 4 缩进计数点被改错（5→4）
  ③ 8 缩进计数点被改错（1→0） ④ 末尾判定条件被追加内容
  ⑤ 专属退出码 3 改成 0 ⑥～⑪ 六条 ml 门：在「SKIP 行」与「计数行」之间**插一行**
  ⑫ ml 门：在 `exit 3` 与 `fi` 之间**插一行**
  ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）
  ⇒ **双断言**：门红 **且** 目标正则**命中数减少**（批 CI 纪律）
  ⇒ ⇒ 累计 **710/710**；
- ⚠⚠⚨ **负控逮到三个坑（本批最有价值的副产物）**：
  ① ⚠⚠⚨ **端到端跑 `ci.sh` 必须带三个环境变量**
     （`LD_LIBRARY_PATH` / `QT_PLUGIN_PATH` / `QT_QPA_PLATFORM=offscreen`）
     ⇒ 少了它们 ⇒ 二进制 / 插件加载失败 ⇒ `ci.sh` **早期**就 `exit 1`
     ⇒ 对照实验 rc 恒 1 ⇒ **分不出「因为未验证判红」还是「因为别处真失败」**
     ⇒ **结论全假**（⇒ 教训：端到端对照实验先量「基线 rc」）；
  ② ⚠⚠⚨ **不许用子串判「✓ CI 门通过」** ⇒ `ci.sh` 的**注释里**有 **4 处**
     提到这句话（批 CK 自己的说明注释就写着）⇒ 子串匹配 ⇒ **被注释骗过**
     ⇒ 必须**行首**匹配（⇒ 批 CJ 同款教训的又一次印证）；
  ③ ⚠⚠⚨ **对 `ci.sh` 做变异 ⇒ 接线门先红 ⇒ 端到端对照实验做不了**
     ⇒ 第 9 步（接线门）就 `exit 1` ⇒ 走不到末尾 ⇒ 对照实验**分不出原因**
     ⇒ ⇒ **对照实验必须放单元级**（现抽原文跑）
     ⇒ ⚠ 接线门先红**本身是好事**（说明门有牙）⇒ 别把「对照实验做不了」
     误当成「门坏了」。

**⑤ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠⚠⚨ **本机 CI 现在是红的（rc=3）**：本机**缺 `appstream-util`**
  ⇒ 第 3 步的 metainfo 合法性校验**没验** ⇒ 批 CK 的新逻辑**如实判红**
  ⇒ ⚠⚠⚨ **这不是回归**，这**正是本批要的效果**
  （「未验证不许被当成通过」⇒ 以前这里是绿的）
  ⇒ 要绿须 `apt install appstream-util`（候选 0.8.2-1.1；⚠ **sudo 需密码 ⇒ agent 装不了**）；
- ⚠ **段落 `ARCH_FAIL` 提前 exit** ⇒ `ci.sh` 里若前面的段红 ⇒ 后面的段**跑不到**
  ⇒ **既有结构问题**（本批未动）；
- ⚠ **跨行锚定（ml）门项不在「整行锚定」的适用范围检查内**
  ⇒ 批 BQ 的「中间不许无界通配」检查**管不到**它们；
- ⚠ **6 处计数的「位置」靠 ml 门项钉**（count 门只数条数
  ⇒ 「5 处 4 缩进 + 1 处 8 缩进」**不关心**哪一处是谁的）⇒ ml 门项补上「紧跟」；
- ⚠ **ml 门项的正则含双引号与全角标点** ⇒ 只能用 `arch_need_ml`
  （正则参数是**单引号**包裹 ⇒ 不能含字面单引号）⇒ 不能用 `arch_need_count` 的逐行口径；
- ⚠ **本批只收「CI 自己这一层的未验证出口」** ⇒ 判据层其它脚本的 SKIP 出口
  （除批 CI 已收的契约门外）不在本批范围；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）；
- ⚠⚠⚨ **本批自踩四处**：
  ① `[^"]*` **跨不过闭引号** ⇒ 7 条 ml 门项**命中 0 次**（批 BL 教训的直接重犯）
  ⇒ 改成把闭引号**显式写进**正则；
  ② `[[:space:]]+✓` **不成立**（`✓` 前面紧贴的是 `"` 不是空白）⇒ 命中 0 次
  ⇒ 改成用 `fi` + `echo "✓ CI 门通过…` 的**实际结构**现抽；
  ③ 负控 harness 里数 ml 命中数的管道**少了一个 `|`** ⇒ `tr` 把 `grep` 当成待翻译字符集
  ⇒ 命中数恒 0 ⇒ 「变异没做成功」的提示**指错方向**；
  ④ ⚠⚠⚨ 端到端负控**忘了带三个环境变量**（`LD_LIBRARY_PATH` / `QT_PLUGIN_PATH` /
  `QT_QPA_PLATFORM=offscreen`）⇒ `ci.sh` **早期**就 `exit 1` ⇒ 对照实验 rc 恒 1
  ⇒ **分不出原因** ⇒ 结论全假（⇒ 教训：端到端对照实验先量「基线 rc」）。

**⑥ 数字**

- 门项物理行数 **967 → 979**（+12）、执行次数 **970 → 982**（+12）；
- 门项总数基线 `ci-wiring-gates.baseline` = **967 → 979**；豁免表**不变**（13 条）；
- 接线门 **982** 项全绿、selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、
  审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**，但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- **负控 16/16 真红**；累计 **710/710**。

### E.2au 「未验证」不许被当成「通过」（批 CL · 子脚本层：打包脚本 / 冒烟脚本）

**① 起因（实测盘点 + 逐处人工判，不是推演）**

盘点判据层所有脚本的「跳过 / 未验证」出口 ⇒ **盘点时（改动前）68 处**带
「未验证」字样的打印行 ⇒ ⚠⚠⚨ 逐处判（批 CJ 纪律：危险方向靠**人工**判，
机器只能校验「非空」）⇒ ⚠⚠⚨ 68 ⇒ **3 处真洞**：

> ⚠⚠⚨ **本批自踩第 7 处（数字漂移）**：这个 **68** 是**改动前**的口径
> ⇒ 本批**自己的改动**又新增了 **4 处**带「未验证」字样的**提示消息**
> （`build-deb.sh` 的判定块消息 / `ci.sh` 的 deb 构建分诊 / `smoke.sh` 的
> 契约门 rc=3 消息 / `ci-wiring.sh` 的批 CL 段汇总消息）
> ⇒ **改动后现为 72 处**（实测：`37f8ce5` = 68 ⇒ `d540a9b` = 72）
> ⇒ ⚠⚠⚨ 那 4 处**恰恰是本批修好的东西**（把「未验证」说得更响 **且** 已计数/已判红）
> ⇒ **不是新洞**；
> ⇒ ⚠⚠⚨ **但这暴露一条更深的洞**：「未验证出口」的盘点口径
> **会把自己的修复也算成出口** ⇒ 数字**永远在涨**
> ⇒ ⇒ 「N 处未验证出口」这个说法**本身**就不可靠
> ⇒ ⇒ **下一批必须把盘点搬进仓内常驻脚本 + 逐处带理由的登记册**
> （批 CJ 的教训在这里**升级**了一版：不只是「三个盘点器三个数」，
> 而是「**修一次数字就涨**」）；
> ⇒ ⚠⚠⚨ 顺带暴露：盘点口径还会把**成功汇总消息**
> （如「✓ 批 CL 段门项全绿（未验证不许被当成通过…）」）算成「出口」
> ⇒ **误报** ⇒ 下一批的盘点器必须能区分「失败/未验证提示」与「成功汇总消息」
> ⇒ ⚠ 而**怎么区分**又是新口径 ⇒ ⇒ 下一批的登记册**逐条写理由**
> ⇒ 机器只兜「登记齐全 + 理由非空」，**危险方向仍靠人工**（批 CJ 同款纪律）。

1. `build-deb.sh` 第 2h 步「**apt 查不到候选版本**」⇒ **只打印、不计数**；
2. `build-deb.sh` 第 2h 步「**没有 apt-cache**」⇒ **只打印、不计数**；
3. `smoke.sh`「**引擎缺席**」⇒ **只打印** ⇒ 脚本 `exit 0` ⇒ 冒烟脚本说「全绿」。

⇒ 全部「只打印」⇒ 脚本 **exit 0** ⇒ CI 第 11 步照样打
「**✓ deb 构建通过（依赖清单自洽 + 产物零环境变量下无缺失库）**」
⇒ ⚠⚠⚨ **说法比门宽**（批 AA 教训）：那两项**根本没验**。

⇒ ⚠⚠⚨ **另有一处「码值语义被顶替」**（批 CC 纪律）：
`smoke.sh` 以前是 `bash contract-check.sh || exit 1`
⇒ 契约门报「未验证」(**3**) 时**被压成 1（失败）**
⇒ 调用方**分不出**「根本没验过」与「验了但没过」。

⇒ ⚠⚠⚨ **另有一处「失效出口的形态没跟上」**：
CI 第 11 步以前是 `if sh build-deb.sh … ; then` ⇒ **接不住退出码**
⇒ build-deb.sh 报「未验证」(3) 时落进 `else` ⇒ 被当成「构建失败」(1)
⇒ 与第 10 / 12 / 13 步的**分诊口径不一致**。

**② 修法（只动判据层 ⇒ 零产品代码改动）**

- ① `build-deb.sh`：加**未验证计数器** `skip`；那 2 处各 `skip=$((skip+1))`
  （缩进分布：**8 空格 1 处** / **4 空格 1 处**）；
  末尾 `if [ "$skip" -ne 0 ]; then … exit 3; fi` ⇒ ⚠ **专属退出码 3**
  ⇒ **紧挨着**「✓ 已生成」**之前**（顺序反了 ⇒ 未验的组**已经被说成通过**了）；
  ⚠ **不用 `die`**：die 调用点有门钉住**恰好 23 处**（批 BU）
  ⇒ 加 die 会动那条清单门 ⇒ 这里用**独立计数器** ⇒ 互不干扰；
  ⚠ 文件头的「退出码」说明**同步改**（批 BB：说明必须与实际行为一致）；
- ② `smoke.sh`：引擎缺席 ⇒ `exit 3`（专属码）；
  契约门调用改成 `_cc_rc=0` + `bash … || _cc_rc=$?`
  ⇒ **3 ⇒ exit 3（原样传出）** / 其它非 0 ⇒ `exit 1`；
- ③ `ci.sh` 第 11 步：`_deb_rc=0` + `sh build-deb.sh … || _deb_rc=$?`
  ⇒ **分诊三态**：0 = 通过 / **3 = 未验证 ⇒ 计入 `skip`** / 其它非 0 = 失败 ⇒ `exit 1`
  ⇒ 与第 10 步（契约门，批 CB/CI）、第 12 步（deb 布局验收，批 CC）**同款口径**。

**③ 落门 / 判据**

- **新增 13 条**（**8 条整行锚定 + 5 条跨行锚定**）：
  - `build-deb.sh`（8 条）：`^skip=0$` / 两种缩进的 `skip=$((skip+1))`（各 1 处）/
    `^if [ "$skip" -ne 0 ]; then$` / `^    exit 3$` +
    2 条「**SKIP ⇒ 计数必须紧跟**」+ 1 条「判定块**必须紧挨着**「✓ 已生成」之前」；
  - `smoke.sh`（4 条）：`^    exit 3$` / `^        exit 3$`（两种缩进各 1 处）+
    2 条跨行锚定（引擎缺席 ⇒ 紧跟 `exit 3` / 契约门调用 ⇒ 紧跟 rc=3 分诊）；
  - `ci.sh`（1 条）：「deb 构建脚本自报 SKIP ⇒ 计数**必须紧跟**」；
- **原地替换 5 条**（批 BM 纪律：跟着改的必须**原地替换**，不增行）：
  ① `ci.sh` 的 8 缩进 `skip=$((skip+1))`：**1 → 2**（新增 deb 构建分诊那一处）；
  ② `smoke.sh` 的整行 `exit [1-9]`：**1 → 3**（新增两处 `exit 3`）；
  ③ `smoke.sh` 的契约门调用行：形态 `|| exit 1` ⇒ `|| _cc_rc=$?` ⇒ **重写**；
  ④ `ci.sh` 第 11 步的 deb 打包调用行：形态 `if sh … ; then` ⇒ `sh … || _deb_rc=$?` ⇒ **重写**；
  ⑤ 审计器的 `ANCHOR_SCOPE_SUFFIXES` **定义行**：适用范围**加 `build-deb.sh`** ⇒ 正则**重写**；
  ⇒ ⚠ **每一条的说明文字都同步改了**（批 BB：说明必须与实际行为一致）；
- ⚠⚠⚨ **适用范围纳入 `build-deb.sh`**（批 BS 纪律）：
  它是 **CI 第 11 步跑的断言脚本** ⇒ 它的判定行同样是「门自己的工具」
  ⇒ 被掏空 = 那批承诺集体失效 ⇒ 必须纳入锚定形态检查；
  ⇒ ⚠ 纳入的代价：它的「die 调用点」那条门**不是整行锚定**
  ⇒ 必须**显式豁免**（豁免表 ≡「非锚定门项」集合 ⇒ 反向配准**自动双向红**）
  ⇒ 豁免表 **13 → 14 条**；
- **同步**：门项总数基线 **979 → 992**；
- ⚠⚠⚨ **门项正则一律由现抽实际行生成**（批 BS 纪律：绝不手写）。

**④ ⚠⚠⚨ 负控 17/17 真红**

- **A（行为级 · 4 条 · 全部**单元级**，现抽原文跑 ⇒ 零漂移）**：
  ① 冒烟脚本「引擎缺席」⇒ 现抽跑 ⇒ **rc=3**（未验证专属码）；
  ② 打包脚本「计数有牙」⇒ 现抽 else 段 + 末尾判定块
     ⇒ 未变异 `skip=1` ⇒ **rc=3**；**删掉那行计数** ⇒ `skip=0` ⇒ **rc=0**
     ⇒ ⚠ **坐实「少一处计数 ⇒ 那一项未验不再被判红」**；
  ③ **CI 第 11 步分诊三态**（现抽）⇒ rc=0 ⇒ **0** / rc=3 ⇒ **3** / rc=1 ⇒ **1**
     ⇒ ⚠ 三态各归各位 ⇒ 码值语义不被顶替；
  ④ 冒烟脚本「契约门 rc=3 ⇒ 原样传出」⇒ rc=3 ⇒ **3**；rc=1 ⇒ **1**；
- **B（门项级 · 13 条 · 各变异一次 ⇒ 全红）**：
  ① `skip=0` 被追加内容 ② 8 缩进计数点被改错 ③ 4 缩进计数点被改错
  ④ 末尾判定条件被追加内容 ⑤ 专属码 3 改成 0 ⑥⑦ 两处「计数不再紧跟」
  ⑧ 判定块与「✓ 已生成」之间插一行 ⑨⑩ 两处 `exit 3` 改成 0
  ⑪ 引擎缺席那处不再紧跟 ⑫ 契约门调用与分诊之间插一行
  ⑬ `ci.sh` deb 构建那处计数不再紧跟
  ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）
  ⇒ **双断言**：门红 **且** 目标正则**命中数减少**（批 CI 纪律）
  ⇒ ⇒ 累计 **727/727**；
- ⚠⚠⚨ **端到端对照实验做不了**（批 CK 实测的延续）：
  对 `ci.sh` 的变异**会先被接线门抓住** ⇒ 第 9 步就 `exit 1` ⇒ 走不到末尾
  ⇒ 分不出「因为未验证判红」还是「因为接线门红」⇒ **本批 A 类全部单元级**。

**⑤ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **本机 CI 仍是 rc=3（1 组未验证）**：本机**缺 `appstream-util`**
  ⇒ 与批 CK 相同 ⇒ 本批**没有让它更红**（实测：17 个依赖**全部有候选版本**
  ⇒ `build-deb.sh` 的两处**不命中**）⇒ 仍是 **1 组**未验证；
- ⚠ `smoke.sh` **不许被 CI 调用**（门明确禁止：它是本地冒烟入口）
  ⇒ 本批对它的改动**只影响本地入口的退出码语义**，**不影响 CI 链路**；
- ⚠ `build-deb.sh` 的那两处**是「有意不误红」**（批 AE 的设计：
  无法区分「包真不存在」与「本机没配源/离线」⇒ 靠 2f「本机装着」兜底）
  ⇒ ⚠ **不能**改成判失败（那会误红）⇒ 本批的正解是**计数 + 专属码 3**；
- ⚠ deb 产物**已经写好了**（`dpkg-deb --build` 在更早）⇒ `exit 3` **不删产物**
  ⇒ CI 第 12 步仍能验 deb 布局（那一项仍可验）⇒ 合理；
- ⚠ **段落 `ARCH_FAIL` 提前 exit** ⇒ 前面的段红 ⇒ 后面的段跑不到（既有结构问题）；
- ⚠ **跨行锚定（ml）门项不在「整行锚定」的适用范围检查内**
  ⇒ 批 BQ 的「中间不许无界通配」检查**管不到**它们；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）；
- ⚠⚠⚨ **本批自踩六处**：
  ① ⚠⚠⚨ **门项的说明文字太短 ⇒ 与批 CK 的同名门项撞名**
  ⇒ 负控按说明片段定位门项行会**命中 2 条** ⇒ 必须重写成**唯一**且**点名文件 + 点名行为**；
  ② ⚠⚠⚨ 抽取器按「**独占的** `fi`」找块 ⇒ `fi` **带缩进**时**抽超**
  ⇒ 抽出一大坨 ⇒ dash 语法错误 **rc=2** ⇒ 必须按**同缩进**找 `fi`；
  ③ `else` 段**单独跑**是语法错误 ⇒ 必须包 `if false; then : … fi`；
  ④ 原地替换「期望值」不能找 `'1'`（行里是「 1 '」）⇒ 要按**第 2 与第 3 个单引号之间**切；
  ⑤ 原地替换「说明文字」不能按**内容**找片段（措辞对不上）⇒ 要按**位置追加**；
  ⑥ ⚠⚠⚨ **旧门项盯的是旧形态** ⇒ 改了形态**必须**原地替换那条门项
  ⇒ 否则审计器报「**次数门没配准 ⇒ 门恒红**」（rc=4）。

**⑥ 数字**

- 门项物理行数 **979 → 992**（+13）、执行次数 **982 → 995**（+13）；
- 门项总数基线 `ci-wiring-gates.baseline` = **979 → 992**；
- 豁免表 **13 → 14 条**（新增 `build-deb.sh` 的 die/fail 调用点，带理由）；
- 审计器的锚定形态适用范围 **15 → 16 个脚本**（+`build-deb.sh`）；
- 接线门 **995** 项全绿、selfcheck **395/0**、契约门 **120/0**、ci-d2 **0/0**、
  审计器硬门与报告模式 **rc=0**、恒真探针与孤儿探针 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**，但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**（与批 CK 相同，未变）；
- **负控 17/17 真红**；累计 **727/727**。

### E.2av 「未验证出口」的盘点搬进仓内常驻脚本 + 逐组带理由的登记册（批 CM）

**① 起因（批 CL 实测坐实，不是推演）**

批 CK / 批 CL 的结论都引用「判据层有 **N 处**『未验证 / 跳过』提示」⇒ 那个数字来自
**一次性盘点脚本**（放在 `/tmp` 里）⇒ ⚠⚠⚨ **仓内没有任何东西能重算出它**；
且实测：批 CL 的**修复本身**又新增了带「未验证」字样的提示消息
⇒ 「**修一次，数字就涨**」⇒ 「N 处未验证出口」这个说法**本身就不可靠**
⇒ ⇒ 本批把盘点**搬进仓内**，并让它与**逐组带理由的登记册**双向对拍。

**② 修法（只动判据层 ⇒ 零产品代码改动）**

- ① **新增仓内常驻盘点脚本** `scripts/ci-unverified-audit.py`：
  - 口径：站点 = **打印行**（`echo` / `printf` / `print`）且含未验证关键词；
  - 排除表**四类**（每类都有实测依据）：成功消息（含 `✓`）/ 步骤标题（含 `›`）/
    辅助提示（**引号内首个非空白字符**是 `⇒`）/ 成功汇总行（含 `passed,`）；
  - 分类两类：`失败上报`（含 `✗` ⇒ 已判红）/ `跳过提示`（其余 ⇒ 只打印）；
  - ⚠ **剥注释直接复用**判据层自己的实现（`ci-true-audit.py` → `ci-wiring-audit.py`）
    ⇒ **不复刻**（批 CF 纪律）⇒ 并**复用它的抽取自检**；
  - ⚠ 失败路径用 `return 1` + 入口 `sys.exit(main())` ⇒ 退出码真的传出去
    （⚠ `sys.exit('…')` 那行**没法被整行锚定**：门项正则**单引号**包裹
    ⇒ 不能含字面单引号 ⇒ 批 BL 教训）；
- ② **新增登记册** `scripts/ci-unverified-audit.baseline`：**15 行**数据行，
  4 段 TAB 分隔（文件 | 分类 | 处数 | 理由）⇒ **逐组带理由**；
- ③ **接线门必须真的跑一次盘点**：在 `ci-wiring.sh` 的**第一条门项行之前**插入
  `if ! python3 "$SRC/scripts/ci-unverified-audit.py"; then … fi`
  ⇒ ⚠⚠⚨ **位置必须在所有门项段之前** ⇒ 否则前面某段红 ⇒ 提前 `exit`
  ⇒ **盘点根本没人跑**（那就还是「多了一份没人跑的断言」，批 BD 纪律）；
  ⇒ ⚠ 盘点失败 ⇒ `ARCH_FAIL=1`（批 BO：失败上报的**唯一通路**）
  **紧跟 `exit 1`** ⇒ 立刻带准确诊断退出（⚠ 只打不退出 ⇒ 会落到**后面**那个
  通用守卫 ⇒ 那句文案是「取数/判定/渲染/接线任一段被摘掉」⇒ **指错方向**，批 CE）。

**③ 落门 / 判据**

- **新增 21 条**（**20 条整行锚定 + 1 条 forbid**）：
  - `ci-unverified-audit.py`（**19 条 count**）：口径常量 9 条（关键词 / 打印行正则 /
    辅助提示正则 / 排除表四行）+ 登记册体检 3 条（4 段 / 正整数 / 理由非空）
    + 三条判定 3 条（`missing` / `dead` / `drifted`）+ 条数检查 + 抽取自检
    + 失败上报出口 + 入口 `sys.exit(main())`；
  - `ci-wiring.sh`（**1 条 count**）：「接线门**必须真的跑一次盘点**」；
  - `ci-unverified-audit.py`（**1 条 forbid**）：**不许自己实现剥注释**
    （⚠ 必须用 `arch_forbid` 门型 ⇒ 审计器**有意不审**它 ⇒ 用 `arch_need_count`
    期望 0 次会被形态检查判 rc=8 —— **实测踩过**）；
- **原地替换 2 条**（批 BM 纪律：**不增行**）：
  ① `ARCH_FAIL=1` 条数：**38 → 39**（盘点段新增一处失败上报）
     ⇒ ⚠ **说明文字里的「恰好 N 处」同步改**（批 BB：说明必须与实际行为一致）；
  ② 审计器的 `ANCHOR_SCOPE_SUFFIXES` **定义行**：适用范围**加
     `ci-unverified-audit.py`**（它是 **CI 里跑的盘点脚本** ⇒ 它的判定行同样是
     「门自己的工具」⇒ 被掏空 = 那批承诺集体失效 ⇒ 按批 BS 纪律必须纳入）
     ⇒ 正则**重写**；
- **同步**：
  - 门项总数基线 **992 → 1013**；
  - 审计器锚定形态适用范围 **16 → 17 个脚本**；
  - 豁免表 **14 条不变**（本批的门项**全部整行锚定**）；
  - ⚠ **恒真探针的扫描范围基线**（`ci-tautology-scope.baseline`）**python 4 → 5**
    ⇒ ⚠⚠⚨ 探针是 **fail closed** 的：新增判定脚本 ⇒ 范围变大 ⇒ **它当场报红**
    ⇒ 必须同步基线（**这不是 bug，是它的设计意图**：范围被改 ⇒ 立刻报出来）。

**④ ⚠⚠⚨ 负控 27/27 真红**

- **A（行为级 · 4 条 · 全部**单元级**）**：
  ① 登记册**处数**改错 ⇒ 盘点判红（「处数对不上」）；
  ② 登记册**删一行** ⇒ 盘点判红（「条数 ≠ 基线」⇒ 清单不许被删）；
  ③ **新增**一个未登记的组 ⇒ 盘点判红（「实测有、登记册没有」）；
  ④ 登记册**替换**一行成假的 ⇒ 盘点判红（「登记册有、实测没有」⇒ 登记册腐化）；
- **B（门项级 · 23 条 · 各变异一次 ⇒ 全红）**：
  ①～⑲ 盯盘点脚本的 19 条 count 门（口径常量 / 登记册体检 / 三条判定 /
  抽取自检 / 失败出口 / 入口）；
  ⑳ 「接线门必须真的跑一次盘点」（**摘掉整段** ⇒ 门红）；
  ㉑ forbid：盘点脚本塞一个 `def strip_comments` 进去 ⇒ 门红
  （⚠ 危险方向：命中数 **0 → 1**）；
  ㉒ `ARCH_FAIL=1` 条数门（删一处失败上报 ⇒ **39 → 38** ⇒ 门红）；
  ㉓ `ANCHOR_SCOPE_SUFFIXES` 定义门（适用范围少一个 ⇒ 命中 0 ⇒ 门红）；
  ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）
  ⇒ **双断言**：门红 **且** 目标正则**命中数减少**（forbid 门是危险方向 ⇒ **增加**）
  ⇒ ⇒ 累计 **754/754**；
- ⚠⚠⚨ **隔离跑门项时必须剔掉盘点段** ⇒ 否则盘点会跟着变异跑 ⇒ **归因串味**
  （门红可能只是因为盘点失败，不是因为这条门有牙）。

**⑤ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠⚠⚨ **本批最弱的一环**：登记册按 **(文件, 分类) 聚合计数**（**不按行登记**）
  ⇒ 改文案不漂、只有数量变了才红 ⇒ ⚠ **代价 = 组级理由**
  ⇒ 「这一组里**某一处**没判红」**机器判不出来** ⇒ **危险方向靠人工逐处判**；
- ⚠ **盘点脚本自己的失败消息被计入**（**自指**）⇒ 改它的文案 ⇒ 处数变 ⇒ 登记册要跟着改；
- ⚠ **口径数的是「提示行」，不是「逻辑出口数」** ⇒ 一处逻辑出口可能占 1~2 行
  ⇒ 处数**大于**出口数 ⇒ **刻意为之**（口径稳定优先）；
- ⚠ `ci-wiring.sh` 那两处「没有 perl」是 `return`（**无参数** ⇒ 返回上一步的退出码，
  通常 0）⇒ **潜伏洞**（顶部 preflight 被摘掉就静默放行）⇒ **建议下一批收**；
- ⚠ **段落 `ARCH_FAIL` 提前 exit** ⇒ 后面的段跑不到（既有结构问题）
  ⇒ ⚠⚠⚨ **本批实测坐实其代价**：审计器 **rc=6**（条数与基线不符）会**遮住**
  **rc=4**（次数失准）⇒ ⇒ 「门自审计先红 ⇒ 后面所有门项都没跑到」；
- ⚠ **盘点脚本没有独立的 CI 步骤** ⇒ 它是**接线门的一部分**（第 9 门里跑）
  ⇒ CI 步骤数**不变**（15/15）；
- ⚠ **恒真探针只查 `if` 条件的恒真/恒假与断言实参** ⇒ 「条件本身合法但恒真」
  （如 `x == x`）**抓不到** ⇒ 需**变异测试**（成本高，明确不做）；
- ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）。

**⑥ ⚠⚠⚨ 本批自踩十处（实测坐实，不是推演）**

① ⚠⚠⚨ **手写原地替换的正则** ⇒ 把 `ANCHOR_SCOPE_SUFFIXES` 那条门改成**恒红**
   （末元素的收尾引号要用 `.` 占位，不能写成 `\.` ⇒ 那样就要求源码里有个**字面点**）
   ⇒ ⚠⚠⚨ **差点把红门推上远端** ⇒ 修法：**从审计文件现抽定义行** ⇒ 程序化构造
   ⇒ 并**写盘前实测命中数**（本批**新增**的纪律）；
② ⚠⚠⚨ **行尾注释** ⇒ 审计器 `count_hits` **先剥注释再 grep**
   ⇒ 4 个带行尾注释的常量行 ⇒ 锚定后**匹配不上** ⇒ **门恒红**
   ⇒ 修法：解释挪到**上一行**（这 4 行的语义不许被注释遮住 ⇒ 门项锚定整行）；
③ ⚠⚠⚨ **生成器写盘前重读**被改的文件 ⇒ 前面步骤的内存修改**全丢**
   （盘点段插了但没落盘）⇒ 修法：**写盘前不再重读**；
④ ⚠⚠⚨ **盘点段插入点选错**（原计划插到「门自审计」段里）⇒ 盘点可能跑不到
   ⇒ 修法：插到**第一条门项行之前**
   （实测：接线门输出**第 2 行**就是盘点结果 ⇒ 真的在最前面跑）；
⑤ ⚠⚠⚨ **盘点脚本里有一段复制粘贴的死代码**（重复的 `--list` 分支）⇒ 清掉；
⑥ ⚠⚠⚨ **负控变异只改 `if` 行** ⇒ 留下悬空的 `fi` ⇒ 整个脚本**语法错**
   ⇒ 门**根本没被执行** ⇒ **结论全假** ⇒ 修法：**摘整段** + 加 `sh -n` 语法守卫；
⑦ ⚠⚠⚨ **负控「登记册加一行」够不着 `dead` 判定** ⇒ 「条数 ≠ 基线」先拦下
   ⇒ 「登记册有、实测没有」这个方向**只能靠替换一行**来触发
   （**如实记：判定顺序有讲究**）；
⑧ ⚠⚠⚨ **恒真探针的扫描范围基线**没同步 ⇒ **fail closed** 报红
   ⇒ ⇒ 同步基线（python 4 → 5）；
⑨ ⚠⚠⚨ **门项说明文字里的「恰好 38 处」没跟着改**（期望值改了 38→39，说明还写 38）
   ⇒ 违反批 BB ⇒ 已改；
⑩ ⚠⚠⚨ **盘点失败若只 `ARCH_FAIL=1` 不退出** ⇒ 会落到**后面**那个通用守卫
   ⇒ 那句文案是「取数/判定/渲染/接线任一段被摘掉」⇒ **指错方向**（批 CE）
   ⇒ ⇒ 改成**紧跟 `exit 1`**（诊断不许失真）。

**⑦ 数字**

- 门项物理行数 **992 → 1013**（+21）、执行次数 **995 → 1016**（+21）；
- 门项总数基线 `ci-wiring-gates.baseline` = **992 → 1013**；
- 豁免表 **14 条不变**；审计器锚定形态适用范围 **16 → 17 个脚本**；
- 盘点：**15 组 / 61 处**（登记册 **15 行**）；恒真探针扫描范围
  判定层 4 / shell 18 / **python 4 → 5** 个文件；
- 接线门 **1016** 项全绿、selfcheck **395/0**、D2 **0/0**、契约门 **120** 条真引擎断言、
  审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**、孤儿探针 **rc=0**、
  盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**，但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**（与批 CK / CL 相同，未变）；
- **负控 27/27 真红**；累计 **754/754**。
### E.2aw 「没有 perl ⇒ 这道门没跑」必须**判红**，不许回退成 SKIP 口径（批 CN）

**① 起因（批 CM 登记册里明写「建议下一批收」，不是推演）**

批 CM 的盘点在 `ci-wiring.sh` 里找到 **2 处**「跳过提示」，逐处人工判的结论是：

> ⚠⚠⚨ **两处都不可达**（脚本顶部已 preflight「没有 perl ⇒ exit 1」）⇒ 不是活洞；
> ⚠ **但潜伏**：这两处是 `return`（**无参数** ⇒ 返回上一步的退出码，通常 0）
> ⇒ **若那道 preflight 被摘掉 ⇒ 静默放行 ⇒ 假绿** ⇒ ⚠ **建议下一批收**
> （机器看不出来 ⇒ 本条靠人工判出来的）。

⇒ 逐处核对后确认：那两处是 `arch_forbid_han` 与 `arch_forbid_text_dup` 里
「**没有 perl ⇒ 显式 SKIP（不算通过）**」那一支 ⇒ ⚠⚠⚨ 那是**批 CB / CC 之前的旧口径**
（工具坏了 ⇒ 只打印 ⇒ 继续 ⇒ 绿）⇒ 与批 CB / CC / BI 的口径**不一致**。

⚠⚠⚨ **更要紧的是另一条**：那两处的**唯一活路**是脚本**顶部**的
`command -v perl … || { …; exit 1; }` ⇒ ⚠ **实测：它此前没有任何门**
⇒ ⇒ 摘掉它 ⇒ 那两处就静默放行 ⇒ **假绿** ⇒ ⇒ **它自己必须被门盯住**。

**② 修法（只动判据层 ⇒ 零产品代码改动）**

- ① 那两处「没有 perl」分支：改成**判红**
  （`echo "  ✗ $label：没有 perl（… ⇒ 这道门没跑 ⇒ 未验证不许被当成通过）" >&2`
  + `ARCH_FAIL=1` + `return 1`）⇒ 与批 CB / CC / BI 口径统一；
  ⇒ ⚠ 以前那两支**只打印 SKIP、不置 `ARCH_FAIL`** ⇒ 调用点又**丢弃返回值**
  ⇒ ⇒ 顶到「工具坏了也绿」；
- ② **给顶部 preflight 加门**（`arch_need_ml`，压行后匹配整块）：
  `command -v perl … || {` + `echo "✗ 没有 perl…" >&2` + `exit 1` + `}`
  ⇒ ⚠ 正则**现抽**（批 BS）：第 1 / 3 / 4 行照抄实际行，第 2 行只钉结构
  （`echo "✗ 没有 perl[^"]*" >&2`）⇒ **改文案不假红、删行必红**；
- ③ **登记册跟着改**（批 CM 的机制**自己咬了一口**，实测走通）：
  `ci-wiring.sh` 的「跳过提示」那一组**归零**（0 处 ⇒ 登记腐化 ⇒ **该删那一行**）
  ⇒ 「失败上报」那一组 **4 → 6**（那两处从「跳过提示」变成「失败上报」）
  ⇒ ⇒ 登记册 **15 → 14 行** ⇒ 盘点脚本的 `UNVERIFIED_EXPECTED_ROWS` **15 → 14**
  ⇒ 那条门项的期望值**原地替换**（批 BM）。

**③ 落门 / 判据**

- **新增 1 条**（`arch_need_ml`，**跨行锚定**）：顶部 preflight **整块不许被摘掉**；
- **原地替换 4 条**（批 BM 纪律：**不增行**）：
  ① `ARCH_FAIL=1` 全局条数：**39 → 41**（那两处各加一处失败上报）
     ⇒ ⚠ **说明文字里的「恰好 N 处」同步改**（批 BB）；
  ② `arch_forbid_han` 函数体内 `ARCH_FAIL=1`：**2 → 3**；
  ③ `arch_forbid_text_dup` 函数体内 `ARCH_FAIL=1`：**6 → 7**；
  ④ 盘点脚本「登记册条数基线」那条门项：期望值 **15 → 14**，**正则现抽重写**；
- **同步**：门项总数基线 **1013 → 1014**；豁免表 **14 条不变**；
  审计器锚定形态适用范围 **17 个脚本不变**；恒真探针扫描范围不变。

**④ ⚠⚠⚨ 负控 11/11 真红**

- **A（行为级 · 4 条 · 全部**单元级**）**：
  ① `arch_forbid_han` 的「没有 perl」分支**现抽跑**（把 `command -v perl` 打成失败）
     ⇒ **rc=1 / ARCH_FAIL=1** 且打出 **✗**、**没有** SKIP；
  ② `arch_forbid_text_dup` 同款；
  ③ ⚠⚠⚨ **对照实验**：同一段分支的**旧形态** —— 从 **git 里现抽真实旧代码**
     （`git show HEAD:…/ci-wiring.sh`，**不臆造**）⇒ **rc=0 / ARCH_FAIL=0**
     且只打印「SKIP」⇒ **坐实「静默放行 ⇒ 假绿」**；
  ④ 同款（另一个函数）；
- **B（门项级 · 7 条 · 各变异一次 ⇒ 全红）**：
  ① 顶部 preflight **整块**被删 ⇒ 那条 ml 门红（命中 1 → 0）；
  ② preflight 的 **`exit 1`** 被删（只剩 echo）⇒ 那条 ml 门红；
  ③ `arch_forbid_han` 那支的 `ARCH_FAIL=1` 被删 ⇒ 体内条数门红（3 → 2）；
  ④ `arch_forbid_text_dup` 同款（7 → 6）；
  ⑤ 全文 `ARCH_FAIL=1` 少一处 ⇒ 总数门红（41 → 40）；
  ⑥ 盘点脚本的「登记册条数基线」被改 ⇒ 那条 count 门红（命中 0）；
  ⑦ 登记册的 `ci-wiring.sh` 失败上报处数被改错 ⇒ **盘点判红**
     （⇒ 接线门红 ⇒ **批 CM 的登记册机制自己咬了一口**）
  ⇒ 每条**从 `ci-wiring.sh` 原文现抽单独跑**（每次现抽 ⇒ 零漂移）
  ⇒ **双断言**：门红 **且** 目标正则**命中数减少**
  ⇒ ⇒ 累计 **765/765**。

**⑤ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠ **门项的参数个数没人管**（本批自踩①）：`arch_need_ml` 多传一个参数
  ⇒ 该门型是 **3 参**（文件 / 正则 / 说明）⇒ 多出来的那个**变成了标签**
  ⇒ 门**仍绿**（判定没错）但**说明文字被吞** ⇒ **诊断失真**（排障会被带偏）
  ⇒ ⚠ **不是假绿** ⇒ 建议下一批加「门项参数个数」检查；
- ⚠ 本批改的那两处**依然不可达**（顶部 preflight 先 `exit 1`）
  ⇒ 本批是**消除对 preflight 的依赖** + **给 preflight 加门**
  ⇒ ⇒ 属「**纵深防御**」，不是「修一个活的洞」⇒ 如实记；
- ⚠ 盘点口径数的是「**提示行**」⇒ 本批把那两处的消息从「‣ SKIP」改成「✗」
  ⇒ **分类变了**（跳过提示 → 失败上报）⇒ 处数**总数不变**（61）但**分组变了**
  ⇒ 登记册**必须**跟着改 ⇒ ⚠ 这正是批 CM 登记册机制**实测走通**的效果
  （「修一次就红 ⇒ 必须显式改登记册 + 写理由」）；
- ⚠ **段落 `ARCH_FAIL` 提前 exit** ⇒ 后面的段跑不到（既有结构问题，未变）；
- ⚠ **恒真探针只查 `if` 条件的恒真/恒假** ⇒ 「条件合法但恒真」抓不到
  ⇒ 需变异测试（成本高，明确不做）；
- ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）。

**⑥ ⚠⚠⚨ 本批自踩八处（实测坐实）**

① ⚠⚠⚨ **`arch_need_ml` 多传了一个参数**（照 `arch_need_count` 的形态写了 4 参）
   ⇒ 该门型是 **3 参** ⇒ 多出来的那个**成了标签** ⇒ 门仍绿但**说明文字被吞**
   ⇒ ⚠ **发现方式**：接线门输出里那条门打的是「**✓ 1**」而不是预期的说明文字
   ⇒ ⇒ **门项的标签必须看得懂**（否则「打的是什么」自己都看不懂）；
② ⚠⚠⚨ **删参数时把两个引号粘在了一起**（`'regex''desc'`）
   ⇒ 审计器的门型正则**认不出这条门** ⇒ 报 **rc=2「门型盲区」**
   （认领 1013 vs 文件里实际 1014）⇒ ⇒ ⚠⚠⚨ **这正是 fail-closed 在起作用**：
   一条**写坏**的门项 ⇒ 审计器当场报「它根本没被审」⇒ 门自审计红 ⇒ 拦住；
③ ⚠⚠⚨ **原地替换要按门型区分参数位置**：`arch_need_count` 的期望值在**第 2** 个
   单引号段、`arch_need_count_in_fn` 在**第 4** 个 ⇒ 同一个函数套用 ⇒
   取到的是**签名** ⇒ 必须分门型；
④ ⚠⚠⚨ **负控 harness 的三个口径错误**：① 用 Python 正则去定位 **ml 门**的变异点
   （ml 门是**压行后**匹配 ⇒ Python 的 `re` 不认 POSIX 字符类 ⇒ 警告 + 命中 0）
   ② **in-function 门取错了正则段**（应取**第 3** 段，不是第 2 段）
   ③ in-function 的命中数必须**在函数体内**数（用审计器自己的 awk 抽取）⇒ 不是全文数；
⑤ ⚠⚠⚨ **两个函数的「没有 perl」分支首行文本完全相同** ⇒ 靠**文本搜索**定位
   ⇒ **永远命中第一个** ⇒ B4 找错区间 ⇒ 改按**函数内锚点行号**定位；
⑥ ⚠ **门项参数个数没人管**（见⑤已知边界）⇒ 建议下一批收；
⑦ ⚠ **说明文字唯一性检查误伤历史门项**（全文本来就有 **3 处**重名说明）
   ⇒ 检查必须**只查本批新增**的门项；
⑧ ⚠ **盘点脚本的条数常量与那条门项**是**一对**（常量 15 → 14 ⇒ 门项期望值也 14）
   ⇒ 改了常量**必须**原地替换那条门项 ⇒ 否则审计器报「次数门没配准 ⇒ 门恒红」（rc=4）。

**⑦ 数字**

- 门项物理行数 **1013 → 1014**（+1）、执行次数 **1016 → 1017**（+1）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1013 → 1014**；
- 豁免表 **14 条不变**；审计器锚定形态适用范围 **17 个脚本不变**；
- 盘点：**14 组 / 61 处**（登记册 **14 行**；⚠ 总处数不变，**分组变了**：
  `ci-wiring.sh` 失败上报 4 → 6、跳过提示 2 → 0 ⇒ 那一行**已删**）；
- 接线门 **1017** 项全绿、selfcheck **395/0**、D2 **0/0**、审计器硬门与报告模式
  **rc=0**、恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**，但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**（与批 CK / CL / CM 相同，未变）；
- **负控 11/11 真红**；累计 **765/765**。
### E.2ax 门项行的「**实参数个数**」必须与门型签名对得上（不许一行藏两条门）（批 CO）

**① 起因（实测逮到的洞，不是推演）**

批 CL 把 `ci.sh` 第 11 步 deb 打包的门从「旧形态」原地替换成「新形态」时，
⚠⚠⚨ **新门项行被追加到了旧门项行的尾巴上，中间连空格都没有**：

```
arch_need_count "$SRC/scripts/ci.sh" '…新形态…' 1 '第 11 步 deb 打包的动作还在…'arch_need_count "$SRC/scripts/ci.sh" '…旧形态…' 1 '第 11 步 deb 打包的动作还在…'
```

⇒ shell 解析时，**后一条的整个调用被并进了前一条的 label**（说明文字）
⇒ ⇒ ⚠⚠⚨ **后一条从来没被执行过**；
⇒ 而它盯的旧形态**早已不存在**（批 CL 改掉了）⇒ 它**真跑起来就该是红的**；
⇒ ⚠⚠⚨ **CI 一直是假绿**（一条本该红的门，从落地起就没跑过一天）；
⇒ 且批 CL 的**负控也被骗了**：定位串**命中 2 条**却只跑了其中一条
⇒ ⇒ ⚠⚠⚨ **负控必须确认定位到的是「恰好一条」门项行**（本批新增纪律）。

**② 修法（只动判据层 ⇒ 零产品代码改动）**

- ① **把粘连拆开**（`ci-wiring.sh` 第 2226 行）：
  - **新形态**独立成行（`arch_need_count`）⇒ 说明文字**合并、一字不丢**
    （用 B 的说明，因为 B 以 A 开头 ⇒ A 的内容整段含在里面）；
  - **旧形态**改成 **forbid 门**（`arch_forbid`）⇒ ⚠ forbid 门判「**不该有的东西没了**」
    ⇒ 命中 >0 ⇒ 红 ⇒ **旧形态绝迹**才算数
    ⇒ 正则**从粘连文本现抽**（不手写，批 BM 纪律）。
- ② **结构性兜底**：审计器新增「门项行的**实参数个数**必须与门型签名对得上」
  ⇒ 实参个数对不上 ⇒ 那行**藏着东西** ⇒ 报
  ⇒ 归入 **rc=2「盲区」**那一支（因为「那条门**根本没被审**」正是盲区的定义
  ⇒ ⇒ **不用新增失败码** ⇒ 但 rc=2 的消息文本要同步扩充）。
  - 门型签名**现抽** `ci-wiring.sh` 的**函数定义**（批 AV 纪律：不复刻）
    ⇒ 支持三种形态：**定长**（必须**恰好**相等）/ **可选参**（`${N:-…}`）/ **变参**（`shift`）；
  - 切分必须按**引号配对**（⚠ 按词位切会把粘连段当独立参数 ⇒ 反而测不出来）。

**③ 落门 / 判据**

- **新增 2 条**（**整行锚定**）：钉住审计器新检查的**定义行**与**调用点**
  （⚠ 只定义不调用 ⇒ 等于没有 ⇒ 删掉调用点 ⇒ 这条门红）；
- **拆开粘连的那一行**：1 条 `arch_need_count`（新形态）**+** 1 条 `arch_forbid`（旧形态）
  ⇒ ⚠ 物理行数 **+1**（粘连是 1 行 ⇒ 拆成 2 行）⇒ 执行次数 **+1**；
- **同步**：门项总数基线 **1014 → 1017**（+3）；豁免表 **14 条不变**；
  审计器锚定形态适用范围 **17 个脚本不变**；恒真探针扫描范围不变；
  盘点登记册 **14 行不变**（本批未新增/删除任何「未验证」提示出口）。

**④ ⚠⚠⚨ 负控 5/5 真红**

- **A（行为级 · 2 条 · 单元级）**：
  ① ⚠⚠⚨ **对照实验**：把那行**粘连**（从 **git 里现抽真实旧代码**，不臆造）
     放回 `ci-wiring.sh` ⇒ 审计器必须**指名道姓**报「实参数个数对不上」⇒ **rc=2**；
  ② **新形态**（拆开后）⇒ 审计器**不报** ⇒ **rc=0**
     ⇒ ⇒ 坐实「**有牙且不误红**」；
- **B（门项级 · 3 条 · 各变异一次 ⇒ 全红）**：
  ① forbid 门：把**旧形态**放回 `ci.sh` ⇒ 门红（命中 **0 → 1**）；
  ② 审计器的 `check_gate_arity` **定义**被删 ⇒ 那条门红（命中 **1 → 0**）；
  ③ 审计器的 `check_gate_arity` **调用点**被删 ⇒ 那条门红（命中 **1 → 0**）；
  ⇒ 每条**从原文现抽单独跑**（每次现抽 ⇒ 零漂移）
  ⇒ **双断言**：门红 **且** 目标正则**命中数减少**
  ⇒ ⇒ 累计 **770/770**。

**⑤ ⚠⚠⚨ 已知边界（如实记着）**

- ⚠⚠⚨ **本批修的是一条「已经假绿」的门** ⇒ 意味着**批 CL 落地后那条门本该是红的**
  ⇒ 批 CL 的负控被「定位串**命中 2 条**却只跑了一条」骗过
  ⇒ ⇒ **负控必须确认定位到恰好一条**（本批新增纪律）；
- ⚠ **arity 检查只覆盖「参数个数」这一种粘连形态** ⇒ 粘连的**另一种**形态
  （两条门之间**有**空格 ⇒ 变成**多传参数**）**同样**被覆盖
  ⇒ 但「**粘连在一条说明文字里**」这类**更隐蔽**的形态**未覆盖**；
- ⚠ **「实参数个数」检查不替代「说明文字唯一」检查** ⇒ 两者**互补**
  （前者管「一行藏两条门」，后者管「两条门说了同一句话」）；
- ⚠ **arity 现抽自函数定义** ⇒ 抽不到签名 ⇒ **fail closed**（报「没抽到签名」⇒ 红）
  ⇒ ⚠ 代价：门型签名一旦挪出 `ci-wiring.sh`（例如改成外部脚本）⇒ 全部报红；
- ⚠ **段落 `ARCH_FAIL` 提前 exit** ⇒ 后面的段跑不到（既有结构问题，未变）
  ⇒ ⚠⚠⚨ **本批实测坐实其代价**：审计器 **rc=6**（条数与基线不符）会**遮住** **rc=4**（次数失准）
  ⇒ 「门自审计先红 ⇒ 后面所有门项都没跑到」；
- ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）。

**⑥ ⚠⚠⚨ 本批自踩六处（实测坐实）**

① ⚠⚠⚨ **「实参数个数 == max($N)」这条规则是错的** ⇒ `arch_need_any_min` 的**第 4 参可选**
   （`${4:-…}`）⇒ `arch_forbid_tree` 是**变参**（`shift`）⇒ **45 条误报**
   ⇒ ⇒ 正确定义 = **必填数 =「没有默认值的那些参数里的最大序号」** + `shift` ⇒ 可多传；
② ⚠⚠⚨ **切分必须按**引号配对** ⇒ 按**词位**切 ⇒ 粘连段被当成**独立参数** ⇒ 反而测不出来
   ⇒ ⇒ 自己写一个 shell 顶层分词器（`split_shell_args`）；
③ ⚠⚠⚨ **旧形态的原文要从批 CL 的父提交现抽**（`git show 75e212b:…`）
   ⇒ ⚠ **HEAD 已是新形态** ⇒ 从 HEAD 取不到旧形态 ⇒ 只能从历史提交取；
④ ⚠⚠⚨ **说明文字合并要用 B 的说明**（B 以 A 开头 ⇒ A 的内容整段含在里面）⇒ **一字不丢**；
⑤ ⚠⚠⚨ **粘连处的形态是 `arch_need_count "FILE" `（无空格）**
   ⇒ ⚠ 门型**名**在行首 ⇒ 正则锚定只能靠**行首**（不能用行中）；
⑥ ⚠⚠⚨ **审计器新增检查归入 rc=2** ⇒ 不用新增失败码
   ⇒ 但 **rc=2 的消息文本要同步扩充**（审计器侧 + `ci-wiring.sh` 门自审计文案）
   ⇒ 否则「报的是什么」与「为什么报」对不上 ⇒ 排障被带偏。

**⑦ 数字**

- 门项物理行数 **1014 → 1017**（+3）、执行次数 **1017 → 1020**（+3）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1014 → 1017**；
- 豁免表 **14 条不变**；审计器锚定形态适用范围 **17 个脚本不变**；
- 盘点：**14 组 / 61 处**（登记册 **14 行**，本批未变）；
- 接线门 **1020** 项全绿、selfcheck **395/0**、D2 **0/0**、契约门 **120** 条真引擎断言、
  审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**（扫描范围 判定层 4 / shell 18 / python 5）、
  孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**，但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**（与批 CK / CL / CM / CN 相同，未变）；
- **负控 5/5 真红**；累计 **770/770**。

### E.2ay 判据层「先红遮后红」不许再遮：一处红 ⇒ 全部门项照跑 ⇒ 末尾统一判红（批 CP）

**① 起因（实测坐实，不是推演）**

判据层（`ci-wiring.sh`）的「段级 trailer」原来长这样：

```sh
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 X 段有门项红（上面带 ✗ 的行）" >&2
    exit 1
fi
```

而 `ARCH_FAIL` 是**全局**的（只置 1、**从不清零**）⇒
⇒ ⚠⚠⚨ **任何一段红了，后面每一段的 trailer 都会 `exit 1`**
⇒ ⇒ ⚠⚠⚨ **实测：540/1017 条门项根本没跑**（变异后只跑到第 477 条，540 条被遮蔽）
⇒ ⇒ 排障被迫「**改一个 ⇒ 跑一次 ⇒ 再改一个**」⇒ 一次只看得见一个洞。

⚠⚠⚨ **第二层（审计器侧 · 本批未收 · 留作批 CQ）**：
`ci-wiring-audit.py --list` 内部是 **15 个顺序早退**（**14** 个 `return N` + **1** 个统一出口）
⇒ 同时存在两处问题时，**先红的那个 rc 遮住后面的**
（实测：rc=6「条数与基线不符」会**遮住** rc=4「次数失准」）
⇒ ⚠⚠⚨ **台账订正**：批 CM / CN 的台账把这条的归因写成「段落 `ARCH_FAIL` 提前 exit」
⇒ ⚠⚠⚨ **实测不成立** —— 那是**审计器内部**的顺序早退造成的；
段级 exit 是**另一个更大**的遮蔽（540 条 vs 审计器那一层）
⇒ ⇒ 本批收的是**脚本侧**，审计器侧**明写为待收**（不许含糊过去）。

**② 修法（只动判据层 ⇒ 零产品代码改动）**

① **段级 trailer 不再提前 exit** ⇒ 改成「判红 ⇒ 记全局红过 ⇒ **继续跑**」：

- 新增全局标志 `ARCH_ANY_FAIL`（顶部声明，末尾统一读它）；
- **37 处** trailer 统一改成 6 行形态
  （判红支 / `ARCH_ANY_FAIL=1` / `else` / 里程碑 / `fi` / 段末清零）；
- 段末 `ARCH_FAIL=0` ⇒ 段级 `ARCH_FAIL` 变成**段内作用域**
  ⇒ 「批 X 段有门项红」**仍然指名道姓**（段归属不失真 ⇒ 诊断不许失真）；
- **末尾统一判红**（`if [ "$ARCH_ANY_FAIL" -ne 0 ]; then … exit 1; fi`）
  ⇒ **退出码语义不变**（红 = 1）⇒ CI 侧零改动。

② **另外两处「提前 exit」也收了**（同款遮蔽）：

- 顶部**自检**（它坏了 ⇒ 后面所有门项的结果都不可信）⇒ 现在**自己成段**
  ⇒ 它的红**不许混进**后面任何一段的归属里；
- **盘点脚本**那一处 `exit 1`（批 CM 加的）⇒ 同样会让后面 1000 多条门项不跑
  ⇒ 现在**自己成段** ⇒ 文案指名道姓 ⇒ **诊断精度不丢**。

③ ⚠⚠⚨ **顺带收掉一颗「假红」时间炸弹**（本批实测当场引爆）：

- `strip_comments` 用 **sed/perl 的退出码**判「工具失败」（批 CG 的机制）；
- 但 `arch_need_count_in_fn` / `arch_need_count_in_step` 的 **awk 读完函数体/步正文就 `exit`**
  ⇒ 消费者**提前收工** ⇒ sed 还在写 ⇒ 被 **SIGPIPE（141）** 打断
  ⇒ ⚠⚠⚨ 以前把 141 也当成「剥注释失败」⇒ 写标记 ⇒ 末尾判红 ⇒ ⚠⚠⚨ **假红**
  （批 BS 纪律：**假红比假绿更坏** ⇒ 假红逼人把承诺改弱）；
- ⚠ **门项文件越写越大 ⇒ 越容易触发** ⇒ 这是颗**时间炸弹**
  （本批把 `ci-wiring.sh` 写大了 ⇒ 当场引爆 ⇒ 接线门 rc=1 且报「剥注释失败」）；
- 修法：**141 一律不算工具失败**（那些消费者**故意**只取一部分 ⇒ 截断是预期的）
  ⇒ 其余非 0（sed/perl 崩了、文件读不了）⇒ **照旧判红**（fail-closed 不动）；
- ⇒ 顺带**原地替换**批 CG 那条「剥注释**必须直接走 perl**」的门
  （形态从「`if ! perl …; then`」改成「`perl …` + **接住退出码**」
  ⇒ 否则**拿不到原始退出码** ⇒ 分不清 141 与真失败）。

**③ 落门 / 判据**

- **新增 7 条**（**全整行锚定**）：
  ① 全局红过标志的声明（**恰好 1 处**）；
  ② 每个段级 trailer 都要记全局红过（**恰好 40 处**）；
  ③ 失败位的声明 + 每段末清零（**恰好 41 处** = 1 + 40）；
  ④ 末尾必须统一按全局红过判红（**恰好 1 处**）；
  ⑤ 段级 trailer **不许再提前 exit**（**forbid 门** · 跨行锚定）
     ⇒ 正则**从旧形态现抽**（不手写）⇒ ⚠ 口径锚在 trailer **自己的** `>&2` 之后
     ⇒ **不会**误伤门项说明文字里的散文「exit 1」（⚠ 压行后散文与代码同处一行
     ⇒ 宽正则会**假红** ⇒ 本批实测撞到过 ⇒ 已收窄）；
  ⑥ 整行的 `exit 1` 必须**恰好 3 处**（顶部 preflight + 末尾剥注释检查 + 末尾统一判红）
     ⇒ **段级 trailer 里一处都不许有**；
  ⑦ 剥注释的失败判定必须**容忍 141**（**恰好 2 处**：sed 支 + perl 支）；
- **原地替换 1 条**：批 CG 的「剥注释**必须直接走 perl**」
  （形态变更 ⇒ 期望值不变 ⇒ 门项**数**不变 ⇒ 但**行**变了 ⇒ 批 BM 纪律：原地替换不增行）；
- **同步**：门项总数基线 **1017 → 1024**（+7）；豁免表 **14 条不变**；
  审计器锚定形态适用范围 **17 个脚本不变**；恒真探针扫描范围不变；
  盘点登记册 **14 行不变**（本批未新增/删除任何「未验证」提示出口）。

**④ ⚠⚠⚨ 负控 6/6 真红**

- **A（行为级 · 3 条）**：
  ① ⚠⚠⚨ **一处真红 ⇒ 后面所有门项仍然全跑**：把最早一段的某条 `arch_need_count`
     期望值 **+5**（按行号整行改）⇒ 退出码 1 **且** 末尾里程碑仍报**总项数 1027**
     ⇒ ⇒ 1027 条门项**全跑完了**（旧形态这里只到 477）⇒ ⇒ **遮蔽已消除**；
  ② **末尾统一判红被摘掉 ⇒ 假绿复现**：同一条真红 + 删掉末尾判红块 ⇒ 脚本 **exit 0**
     ⇒ ⚠⚠⚨ **明明有红却报通过**（这正是要防的）⇒ 门红把它逮住；
  ③ **剥注释工具真的坏了 ⇒ 必须判红**：把 sed 支改成非法选项 ⇒ 退出码 1
     ⇒ 打出「剥注释失败（工具失败 ≠ 没找到）」⇒ ⇒ **141 容忍没有把真失败放过**；
- **B（门项级 · 3 条 · 各变异一次 ⇒ 全红）**：
  ① 摘掉某处 trailer 的「记全局红过」⇒ 「每个段级 trailer 都要记全局红过」红
     （命中 **40 → 39**）；
  ② 把段级 trailer 塞回旧的「提前 exit」形态 ⇒ forbid 门红
     （命中 **0 → 1**）⇒ ⇒ **两类回退形态都盯得住**（完整旧形态 + 部分回退）；
  ③ 把 141 容忍改成 142 ⇒ ⚠⚠⚨ **假红复现**（消费者提前收工 ⇒ 被误判成剥注释失败
     ⇒ 判红）⇒ 且「失败判定必须容忍 141」那条门红（命中 **2 → 0**）
     ⇒ ⇒ **证明这条容忍是必需的**（不是可有可无的宽松）；
- ⇒ 每条**按行号整行改**、变异后 `sh -n` 过、`restore()` **刷新 mtime**；
- ⇒ 累计 **776/776**。

**⑤ ⚠ 已知边界（如实记着）**

- ⚠⚠⚨ **审计器侧那一层本批没收**：`--list` 仍是 15 个顺序早退（**14** 个 `return N` + **1** 个统一出口）
  ⇒ rc=6 仍会遮住 rc=4 ⇒ **明写为批 CQ**（不许含糊）；
- ⚠ **段级 trailer 的归属靠「段内清零」** ⇒ 若有人把某个 `ARCH_FAIL=0` 挪走
  ⇒ 那个段的失败会**污染后面所有段** ⇒ 由门 ③ 盯住（命中数）✔；
- ⚠ **「✓ 段门项全绿」现在只表示「本段全绿」**（旧口径是「到这儿为止全绿」）
  ⇒ 文案本来就写的是「批 X 段」⇒ **语义更准**；但读日志的人若只看 ✓ 不看末尾那句
  ⇒ 可能误以为全过 ⇒ ⇒ 末尾那句「✗ 接线门失败：有门项红」是**唯一的总判**；
- ⚠ **141 容忍是有代价的**：若将来出现一个「**意外**提前收工」的消费者
  ⇒ 它的输出会被截断而**不再报剥注释失败** ⇒ ⚠ 当前所有提前收工的消费者
  （两个 awk + `grep -q`）都是**故意**的 ⇒ 如实记为已知边界；
- ⚠ **本批顺带修的「假红」不是批 CP 的主题** ⇒ 但它被批 CP 的改动**当场引爆**
  ⇒ 必须同批修（否则判据层直接红）⇒ 已落门 ⑦ 盯住；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1017 → 1024**（+7）、执行次数 **1020 → 1027**（+7）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1017 → 1024**；
- 段级 trailer **37 → 40**（+自检段 +盘点段 +批 CP 段）；
  整行 `exit 1` **40 → 3**；`ARCH_ANY_FAIL=1` = **40**；`ARCH_FAIL=0` = **41**；
- 豁免表 **14 条不变**；审计器锚定形态适用范围 **17 个脚本不变**；
- 盘点：**14 组 / 61 处**（登记册 **14 行**，本批未变）；
- 接线门 **1027** 项全绿、selfcheck **395/0**、D2 **0/0**、契约门 **120** 条真引擎断言、
  审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**（扫描范围 判定层 4 / shell 18 / python 5）、
  孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**，但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**（与批 CK / CL / CM / CN / CO 相同，未变）；
- **负控 6/6 真红**；累计 **776/776**。
### E.2az 判据层「先红遮后红」不许再遮（第二层 · 审计器侧）：失败态**收集**、一次报全（批 CQ）

**① 起因（实测坐实 + 对照实验，不是推演）**

批 CP 收的是**脚本侧**那一层（段级 trailer 提前 `exit 1` ⇒ 540/1017 条门项被遮蔽），
并在台账里**明写**「第二层（审计器侧）本批未收 ⇒ 留作批 CQ」。
第二层长这样：`ci-wiring-audit.py --list` 的硬门模式里是 **15 个顺序早退**
（**14** 个 `return N` + **1** 个统一出口）
⇒ ⚠⚠⚨ 同时存在两处问题时，**先红的那个 rc 遮住后面的**
⇒ ⇒ 排障被迫「**改一个 ⇒ 跑一次 ⇒ 再改一个**」⇒ 一次只看得见一个洞。

⚠⚠⚨ **实测（负控 N1 的对照实验，两个变异同时在场）**：
① 基线改错（⇒ rc=6「条数与基线不符」）② 某条次数门期望值 +5（⇒ rc=4「次数门没配准」）
⇒ **旧审计器**（HEAD 版）：退出码 **6**，输出里**只有** rc=6 那条消息，
⇒ ⚠⚠⚨ **rc=4 的消息完全不在输出里**（被遮蔽坐实）；
⇒ **新审计器**（本批）：退出码**仍是 6**（码值语义不变），
⇒ ⚠⚠⚨ **但 rc=4 的消息也在输出里**（遮蔽消除）。

**② 修法（只动判据层 ⇒ 零产品代码改动）**

① **失败态改「收集」**（`FAILS.append(N)`）⇒ 每一处失败**记下来、继续往下跑**
⇒ 末尾**一次报全**；模块级 `FAILS = []`（`main_body()` 开头 `del FAILS[:]` ⇒ 幂等）；
⚠ **模块级是故意的** ⇒ `main()` 的兜底 `except` 也要看得见它。

② **rc 仍取最先失败的那个**（`FAILS[0] if FAILS else (3 if outside else 0)`）
⇒ ⚠⚠⚨ **码值语义完全不变** ⇒ **门侧按 rc 分诊的文案表零改动**
（`ci-wiring.sh` 里 2/3/4/5/6/7/8/9 九个分支一个字没改）
⇒ ⇒ 差别只在「**其余失败也一并报出来**」。

③ **崩了也判红**：`main()` 加通用 `except Exception` ⇒ 崩 ⇒ 记 **rc=2**（盲区/未验证）
⇒ ⚠ **不是**「未知的失败码 1」⇒ 且**已报出来的失败态不丢**；
⇒ ⚠ 崩溃消息的关键词落在 `print(` **同一行**（批 CM 口径数的是「提示行」
⇒ 关键词若落在续行上 ⇒ **盘点数不到** ⇒ 等于漏登记）。

④ **4 处仍然是早退**（源文件读不了 / git diff 拿不到 / 跨文件命中数算不出来 / 统一出口）
⇒ 那时**后面确实不可信** ⇒ 早退是**语义正确**的，不是遮蔽
⇒ ⚠⚠⚨ 但「不跑」必须**明说** ⇒ 依赖失败的检查（豁免基线坏了 / 锚定自检不过
⇒ 整行锚定那两项不可信）现在**明确跳过并说明**（`scope_skip`）
⇒ 「不是没问题，是没验」。

⑤ **门项总数三兄弟仍写成三段显式**（不许循环成动态 rc）
⇒ 保住批 CA/CC 的「**按码值分桶**」纪律：改一个码值 ⇒ 旧桶 -1 + 新桶 +1 ⇒ **两条都红**；
⚠ 为此 `check_gate_totals()` 新增 `msgs_by_kind`（dups / blind / total 分开）
⇒ 报告模式仍用合并的 `msgs`、硬门模式用分类的 `msgs_by_kind`
⇒ ⚠ 两份 ⇒ 后续若加第四类**必须同步两处**（已知边界）。

**③ 落门 / 判据**

- **原地替换 13 条**（形态 `return N` → `FAILS.append(N)`，**分桶期望值不变**
  ⇒ 只有 rc=2 那条从 7 改成 4：4 处**前置**早退保留 ⇒ 后面确实不可信）；
- **新增 2 条**（**全整行锚定**）：
  ① 「失败态**收集器**的声明必须在」（`^FAILS = \[\]$`，恰好 1 处）
  ② 「rc=2（盲区 / 豁免基线不在 / 审计器崩了）**收集处**恰好 4 处」；
- **同步**（批 BY/BS：期望值与说明都要如实改）：
  门项总数基线 `ci-wiring-gates.baseline` **1024 → 1026**；
  段级 trailer **40 → 41**；`ARCH_ANY_FAIL=1` = **41**；`ARCH_FAIL=0` = **42**；
  盘点登记册 `ci-unverified-audit.baseline` **14 → 15 行**
  （⚠ 批 CM 纪律：新增的「未验证/跳过」提示**必须显式登记** ⇒ 不许悄悄加）
  ⇒ `UNVERIFIED_EXPECTED_ROWS` **14 → 15**（门项同步）；
  豁免表 **14 条不变**；审计器锚定形态适用范围 **17 个脚本不变**；
- ⚠⚠⚨ **顺带订正一处「说明文字与实际行为不一致」**（批 BA/BB 纪律）：
  「成功出口」那条门的说明里写着失败出口 `return N` 家族「**16 处**」
  ⇒ 改后实际是 **5 处**（4 前置早退 + 1 统一出口）⇒ **已订正为 5 + 15 = 20 处**
  ⇒ ⚠ **说明文字必须与实际行为一致**（不订正 ⇒ 门在骗人）。
- ⚠⚠⚨ **顺带订正批 CP 文档里一个「与实测不符」的数字**（如实记着，不粉饰）：
  批 CP 的台账 / PLAN / README 写的是「`--list` 内部是 **17 个顺序 `return N` 早退**」
  ⇒ ⚠ **实测（对 HEAD 版审计器逐行数）**：全文件 `return N`（N≥1）= **18** 处
  （**4 处**前置早退在 `--list` 分支**之外** + **14 处**在分支内）
  ⇒ ⇒ `--list` 内部的顺序早退 = 14 + **1**（统一出口）= **15** 处
  ⇒ ⇒ **已订正 6 处**（台账 2 + PLAN 2 + README 2）⇒ **17 这个数字本身是错的**。

**④ 负控 28/28 真红（5 组控制 + 9 条基线口径）**

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
  ⇒ 退出码 **2**（**不是** 1「未知失败码」）⇒ 打出「审计器**崩了**（未验证不许被当成通过）」
  ⇒ ⚠ **没有 traceback**（诊断不许失真）；
- **N5（新门有牙 · 3 条）**：把 `FAILS = []` 改成 `FAILS = list()` ⇒ 命中 **1 → 0**
  ⇒ 门红 ⇒ ⇒ 证明**新增的**那条门不是摆设；
- ⚠ 全部**按行号整行改**、变异后语法过、`restore()` **刷新 mtime**。

**⑤ 已知边界（如实记着）**

- ⚠⚠⚨ **审计器仍有 4 处前置早退**（源文件读不了 / git diff 拿不到 / 跨文件命中数算不出来
  / 统一出口）⇒ 后面确实不可信 ⇒ 早退是**语义正确**的
  ⇒ ⚠ 但「不跑」必须**明说**（依赖失败的那两项现在会明确说「跳过」）；
- ⚠ `check_gate_totals()` 的 `msgs`（合并）与 `msgs_by_kind`（分类）**两份**
  ⇒ 报告模式用合并、硬门模式用分类 ⇒ 后续若加第四类**须同步两处**；
- ⚠⚠⚨ **审计器崩了 ⇒ rc=2** ⇒ 但 `FAILS` 里若已有**更早**失败态 ⇒ rc 取更早那个
  ⇒ 「崩了」的码值**会被顶替**（已如实记录，不粉饰）；
- ⚠ 收齐之后**一次能看见全部问题** ⇒ 输出变长 ⇒ 排障时仍需按 rc 分诊表定位
  ⇒ 但**不用再「改一个跑一次」**；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1024 → 1026**（+2）、执行次数 **1027 → 1029**（+2）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1024 → 1026**；
- 段级 trailer **40 → 41**；整行 `exit 1` **3 不变**；
  `ARCH_ANY_FAIL=1` = **41**；`ARCH_FAIL=0` = **42**；
- 审计器失败态出口：`return N` 家族 **16 → 5**（4 前置早退 + 1 统一出口）、
  `FAILS.append(N)` 家族 **0 → 15** ⇒ 失败出口共 20 处（码值分桶期望值全部不变）；
- 豁免表 **14 条不变**；盘点：**15 组 / 63 处**（登记册 **14 → 15 行**）；
- 接线门 **1029** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**、
  孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**，但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**（与批 CK / CL / CM / CN / CO / CP 相同，未变）；
- **负控 28/28 真红**；累计 **804/804**。


### E.2ba 门项条数记三遍：改一边必红（不许拿「改基线」当删门项的掩护）（批 CR）

**① 起因（实测坐实 + 对照实验，不是推演）**

判据层有一条**承诺**：「门项被删了 ⇒ 没人发现 ⇒ 那些承诺没人守了」
⇒ 落地机制是「门项行数基线」（`scripts/ci-wiring-gates.baseline`）
⇒ 审计器核对「文件里的门项行数 == 基线里的数字」⇒ 不等 ⇒ **rc=6**。

⚠⚠⚨ **实测坐实的洞**：把 `ci-wiring.sh` 里**一条门项行删掉**，
**且** 把基线文件的数字 **-1** ⇒

| | 审计器 `--list` | 接线门 | ✗ 行数 |
|---|---|---|---|
| 只删门项（不改基线） | **rc=6**（红） | rc=1 | — |
| **删门项 + 改基线 -1** | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **0** |

⇒ ⇒ **一条承诺就这么悄悄消失了**，而且**看不出任何异常**
⇒ ⚠⚠⚨ **为什么这是个真洞而不是理论洞**：「改基线」是**每批都要做的惯常动作**
（批 CQ 就改了 1024 → 1026）⇒ ⇒ **惯常动作正好是最好的掩护**
⇒ ⇒ 「删门项 + 改基线」只需**两个协同编辑** ⇒ 躲得过。

⚠ **为什么「基线放独立文件」这个老设计不够**（批 BH 的原意是
「写死在审计器里 ⇒ 改审计器就能同时改标准 ⇒ 删基线文件 ⇒ 门与审计器双双红」）：
⇒ ⚠ **基线文件自己也是可改的** ⇒ 独立文件挡住了「改审计器」这条路，
却挡不住「**改基线文件**」这条路。

**② 修法（只动判据层 ⇒ 零产品代码改动）**

**同一件事记三遍** ⇒ 改任意一边 ⇒ 另外两边对不上 ⇒ **红**：

1. **基线文件**（`scripts/ci-wiring-gates.baseline`）—— 门项条数；
2. **审计器源码里的常量** `GATE_LINES_EXPECTED`（新增）——
   审计器在 `check_gate_totals()` 里核对「基线文件 == 这个常量」
   ⇒ 不一致 ⇒ **rc=6**（门项总数失配家族 ⇒ **码值语义不变** ⇒ 门侧分诊表零改动）
   ⇒ 消息指名道姓：「两个记录**只改了一边** ⇒ 有人删了门项又顺手改了基线」；
3. **两条整行锚定的门**（批 CR 段新增）：
   - 门 ③ 钉住 ② 的**值**（`^GATE_LINES_EXPECTED = 1028$`）⇒ 改常量 ⇒ 门红；
   - 门 ④ 钉住 ② 的**判定行**（整行锚定）⇒ 判定被掏空成 `==` ⇒ 门红
     （批 BL 纪律：只盯「串在不在」⇒ 判定被掏空就躲过了 ⇒ 交叉核对形同虚设）。

⚠⚠⚨ **三处必须一起动** ⇒ 「改一条门项条数」这个**惯常动作**从此要改 3 个地方
（基线文件 / 审计器常量 / 门 ③ 里的数字）⇒ **维护负担 +1 处**，
⇒ ⚠ **这是故意付的代价**（下面「已知边界」里说明它买到了什么）。

**③ 落门 / 判据**

- **新增 2 条**（**全整行锚定**）：门 ③（钉常量的值）+ 门 ④（钉交叉核对的判定行）；
- **原地替换 2 条**（**期望值 +1**、**不增行**）：
  `ARCH_ANY_FAIL=1` **41 → 42**、`ARCH_FAIL=0` **42 → 43**
  ⇒ ⚠ **说明文字里的数字也同步改**（批 BA/BB 纪律：说明文字必须与实际行为一致）
  ⇒ 段级 trailer **41 → 42**；整行 `exit 1` **3 不变**；
- **同步**（批 BY/BS）：门项总数基线 `ci-wiring-gates.baseline` **1026 → 1028**；
  ⚠⚠⚨ **同一个数字要写三处**（基线文件 / 审计器常量 / 门 ③ 的正则）
  ⇒ **三处必须一致** ⇒ 这就是本批的机制本身；
- 盘点登记册 **15 行不变**（批 CM 纪律：本批**没有新增**「未验证/跳过」提示
  ⇒ 新消息不含 `未验证/跳过` 关键词 ⇒ 盘点口径处数不变 ⇒ 登记册不用动）；
  豁免表 **14 条不变**；审计器锚定形态适用范围 **17 个脚本不变**；
- ⚠ **批 CQ 的分桶门零改动**（`FAILS.append(6)` 仍是 **1** 处）
  ⇒ 因为本批的交叉核对**加在同一个 `if g['total_bad']:` 块里**
  ⇒ ⇒ **分桶期望值不变** ⇒ 批 CA/CC 的「按码值分桶」纪律不受影响。

**④ 负控 22/22 真红（4 组控制 + 6 条基线口径）**

- **基线（6 条）**：审计器 `--list` rc=0；基线文件 = 1028；审计器常量 = 1028；
  门 ③ 在位（定长串查）；门 ④ 在位；接线门 rc=0；
- **N1（核心 · 对照实验 · 5 条）**：⚠⚠⚨ **删一条门项 + 基线 -1**
  ⇒ 新审计器 **rc=6** + 消息含「只改了一边」
  ⇒ ⚠ 「与基线不符」**没有**触发（证明抓住它的是**新加的交叉核对**，不是老机制）
  ⇒ ⇒ **对照实验**：**HEAD 版旧审计器 + 同样两个变异 ⇒ rc=0 全绿**
  ⇒ ⇒ **两头都有证据**：旧行为**确实**躲得过（洞坐实）、本批**确实**堵住了；
- **N2（只改一边 · 2 条）**：只把基线文件 -1（不删门项）⇒ rc=6 + 「只改了一边」；
- **N3（只改常量 · 4 条）**：常量 1028 → 1027 ⇒ 审计器 rc=6 + 门 ③ 命中 0 ⇒ **双红**；
- **N4（判定掏空 · 2 条）**：把交叉核对的判定行 `!=` 改成 `==` ⇒ 门 ④ 红
  ⇒ ⇒ **证明「交叉核对的判定不许被掏空」这条门有牙**；
- **回归（2 条）**：还原后审计器 rc=0 + 接线门 rc=0；
- ⚠ 全部**按行号**整行改/整行删、变异后语法过、`restore()` **刷新 mtime**。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠⚠⚨ **不宣称完全堵死**：同时改**四处**（删门项 / 基线文件 / 审计器常量 /
  门 ③ 的正则）仍能躲过 ⇒ **批 CR 把成本从 2 处升到 4 处、跨 2 个文件**
  ⇒ ⇒ **极显眼**（同一个数字在三个地方联动变 ⇒ 评审必看见）
  ⇒ ⇒ **惯常动作不再是掩护**，但**协同编辑仍可能**；
- ⚠ **真正的完全堵死做不到**：任何**仓内**的记录都是可改的
  ⇒ 要完全堵死只能靠「仓外」的真值（如评审 / CI 配置）⇒ 本批不做
  ⇒ ⚠ 曾考虑用 **git 历史**（对比基线分支的门项条数 ⇒ 「判据只许增不许减」）
  ⇒ ⚠ **否决**：仓内**没有 CI 配置**（CI 在仓外）⇒ 拿不到「基线分支」这个稳定参照
  ⇒ ⇒ 且审计器在**浅克隆**下 `git merge-base` 可能拿不到
  ⇒ ⇒ 按批 CN 纪律（「没跑 ⇒ 必须判红」）⇒ 浅克隆会**误红** ⇒ 不用；
- ⚠ **维护负担 +1 处**：以后每批改门项条数，要同步**三处**
  ⇒ 漏任何一处 ⇒ **红**（这正是本批要的：让惯常动作的每一步都留下痕迹）
  ⇒ ⚠ 代价是每批多改一个数字（实测：改三处各 1 个数字 ⇒ 约 1 分钟）；
- ⚠ **交叉核对只覆盖「条数」这一个量** ⇒ 「门项的**内容**被改了」
  （例如把某条门的正则改弱）⇒ 仍是**老边界**（「同时改基线 + 改门项内容」那类）
  ⇒ ⇒ 批 CR 只堵「**数量**对不上」这一类，不扩大宣称；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1026 → 1028**（+2）、执行次数 **1029 → 1031**（+2）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1026 → 1028**；
  （⚠⚠⚨ **同一个数字记三遍**：基线文件 / `GATE_LINES_EXPECTED` / 门 ③ 的正则）；
- 段级 trailer **41 → 42**；整行 `exit 1` **3 不变**；
  `ARCH_ANY_FAIL=1` = **42**；`ARCH_FAIL=0` = **43**；
- 审计器：`FAILS.append(6)` 仍是 **1** 处（交叉核对加在同一个 total 块里 ⇒ 分桶不变）；
- 豁免表 **14 条不变**；盘点 **15 组 / 63 处**（登记册 **15 行**，本批未变）；
- 接线门 **1031** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**
  （判定层 396 条判据 / shell 与 python **652** 个 if 条件（650 → 652：
  批 CR 段 trailer 的 `if` + 审计器交叉核对的 `if` ⇒ **两个都被判非恒真**）/
  断言实参 99 条）、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**，但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**（与批 CK / CL / CM / CN / CO / CP / CQ 相同，未变）；
- **负控 22/22 真红**；累计 **826/826**。


### E.2bb 配对门不许只比「总数」：必须**逐段**配对（批 CS）

**① 起因（实测坐实 + 对照实验，不是推演）**

判据层有一条「**失败必须真的报出去**」的承诺，落地在 `arch_need_count_pair` 配对门
（`check-deb-layout.sh` 1 对、`contract-check.sh` 39 对）
⇒ 它保证「**报错行数 == 计数行数** == 期望」
⇒ 批 BZ 的原意：堵「新增一条**只报错不计数**的失败路径」（总数不等 ⇒ 红 ✓）。

⚠⚠⚨ **实测坐实的洞（批 BZ 遗留 ①）**：把 `contract-check.sh` 里**某一处**的计数行
**挪到别的一段** ⇒ 报错 **39** / 计数 **39**（**总数不变**）
⇒ ⚠ **脚本语法仍然合法**（`sh -n` 过）⇒

| | 审计器 `--list` | 接线门 | ✗ 行数 |
|---|---|---|---|
| 计数被挪到别的一段（总数不变、语法合法） | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **0** |

⇒ ⇒ **全绿** ⇒ 而那一处报错**不再被计数** ⇒ 它的失败**不会**被计入 `fail`
⇒ ⇒ 末尾判定恒真 ⇒ ⚠⚠⚨ **CI 假绿**（那一类断言失败会被当成通过）
⇒ ⇒ **总数相等 ≠ 逐条对应** ⇒ 老门**抓不到**。

⚠⚠⚨ **负控自己先写错过两版（如实记，因为第一版的结论是错的）**：
- **第 1 版**：搬**整行**（`echo "  ✗ $name"; fail=$((fail+1))` 报错与计数在**同一行**）
  ⇒ 搬走整行 ⇒ 那处的 `else` 分支被掏空 ⇒ ⚠ **shell 语法坏了**
  ⇒ ⇒ 「门全绿」是因为**脚本坏了**、不是因为洞 ⇒ **结论不可靠** ⇒ 必须重做；
- **第 2 版**：只搬计数动作、**追加**到另一条**已有**计数的行
  ⇒ 那一行变成「一行两个计数」⇒ **行数口径**下它仍算 1 行
  ⇒ 计数行数 39 → **38** ⇒ ⚠ **总数变了** ⇒ 被**老门**抓到 ⇒ 测的根本不是本批这件事；
- **第 3 版（算数）**：搬**独立成行**的计数行（整行搬）到**另一段**的独立计数行之后
  ⇒ 计数行数 **39 → 39**（一减一加）⇒ **总数不变** ✔
  ⇒ 源段计数数 1 → **0**、目标段 1 → **2** ⇒ 逐段配对必然违规 ✔
  ⇒ 两行**形状相同**（都是 `else` 分支里的独立计数行）⇒ **语法必然仍合法** ✔；
- ⇒ **教训**：负控的变异必须**自己先自证**：① 语法仍合法 ② **要测的那个量**（总数）
  真的没变 ⇒ 否则「门全绿」可能只是因为**脚本坏了**。

⚠ **为什么这不是理论洞**：重构时把计数挪错位置是**很普通的手滑**
（39 段里挪一处 ⇒ 两侧数字都不变 ⇒ 没有任何现有判据会响）。

**② 修法（只动判据层 ⇒ 零产品代码改动）**

① **审计器侧逐段核对**（**零新门型** ⇒ 判据层的门型注册表不变
⇒ 审计器的「门型覆盖对拍」不受影响 ⇒ **豁免表也不变**）：

- 新增 `pair_segment_bad(path, ra, rb)`：把剥注释后的文本按**报错行**分段
  （从一处报错行含，到下一处报错行不含；**最后一段**到文件末），
  **每段必须恰好有 1 处计数行**；
- 接进**已有的** `check_pair_count_gates()` ⇒ 违规 ⇒ 归入 **rc=4**
  （次数门没配准家族 ⇒ **码值语义不变** ⇒ 门侧分诊表零改动）
  ⇒ 消息自带：目标文件名、那一段的起始行号、**段内计数数**、为什么是红
  ⇒ ⚠⚠⚨ **6 字段形态的打印器只打 `why`**（`got` 那一项被丢）
  ⇒ ⇒ 关键信息**必须写进消息本身**（这是负控撞出来的：消息里少写 ⇒ 诊断就少一截）；
- ⚠ 口径：行号用 `grep -nE`（**同一份正则、同一份剥注释文本**）⇒ 与门侧
  `grep -cE` **完全一致** ⇒ 两侧零漂移。

② **门侧那两条配对门的语义变强了** ⇒ ⇒ 它们的**说明文字必须同步改**
（批 BA/BB 纪律：说明文字必须与实际行为一致）⇒ **原地替换**（不增行）。

**③ 落门 / 判据**

- **新增 3 条**（**全整行锚定**，批 CS 独立段）：
  ① 「逐段配对的**检查函数**必须存在」（`^def pair_segment_bad\(path, ra, rb\):$`）
  ② 「逐段配对检查**必须真的被调用**」（`^\s+seg = pair_segment_bad\(f, ra, rb\)$`）
  ③ 「逐段配对的**判定行**必须**是那一行原样**」（`^\s+if seg_n != 1:$`）
  ⇒ ⚠ 批 BL 纪律：关键判定**整行锚定** ⇒ 判定被掏空成 `and False:` 就躲不过；
- **原地替换 2 条**：两条配对门的**说明文字**（语义变强 ⇒ 必须同步改）；
- ⚠ **另外两处说明文字也在审计器里**（**报告模式**的汇总行与门型清单行）
  ⇒ 一并同步改（批 BA/BB 纪律：说明文字必须与实际行为一致
  ⇒ 不然报告会让人以为「总数相等就够了」）；
- **原地替换 2 条**：段级计数 `ARCH_ANY_FAIL=1` **42 → 43**、
  `ARCH_FAIL=0` **43 → 44** ⇒ 段级 trailer **42 → 43**；整行 `exit 1` **3 不变**；
- **同步**（批 BY/BS）：门项总数基线 `ci-wiring-gates.baseline` **1028 → 1031**
  ⇒ ⚠⚠⚨ **同一个数字要写三处**（基线文件 / `GATE_LINES_EXPECTED` / 门 ③ 的正则）
  ⇒ 这是**批 CR** 立的机制，本批照办；
- 盘点登记册 **15 行不变**（本批**没有新增**「未验证/跳过」提示 ⇒ 新消息不含
  那两个关键词 ⇒ 盘点处数不变 ⇒ 登记册不用动）；豁免表 **14 条不变**；
  审计器锚定形态适用范围 **17 个脚本不变**；
  ⚠ **批 CQ 的分桶门零改动**（`FAILS.append(4)` 仍 **1** 处 —— 本批的违规归入
  **同一个** minbad 家族 ⇒ 分桶期望值不变）。

**④ 负控 18/18 真红（3 组控制 + 5 条基线口径）**

- **基线（5 条）**：审计器 `--list` rc=0；逐段检查的**定义行 / 使用点 / 判定行**
  三条都在位（各恰好 1 处）；接线门 rc=0；
- **N1（核心 · 对照实验 · 7 条）**：⚠⚠⚨ 把某处计数**挪到别的一段**
  ⇒ 报错 39 / 计数 39（**总数不变** ⇒ 双断言的前提成立）
  ⇒ 审计器 **rc=4** + 消息含「**段内计数 N**」与「**没被计数**」
  ⇒ ⇒ **对照实验**：**HEAD 版旧审计器 + 同样变异 ⇒ rc=0 全绿**
  ⇒ ⇒ **两头都有证据**：旧行为**确实**躲得过（洞坐实）、本批**确实**堵住了；
- **N2（判定掏空 · 3 条）**：把判定行改成 `if seg_n != 1 and False:` ⇒ 门 ③ 红；
- **N3（使用点掏空 · 3 条）**：把使用点改成 `seg = None` ⇒ 门 ② 红
  ⇒ ⇒ 证明「定义了不调 ⇒ 形同虚设」这条路也被堵；
- **回归（2 条）**：还原后审计器 rc=0 + 接线门 rc=0；
- ⚠ 全部**按行号**整行改、变异后语法过、`restore()` **刷新 mtime**。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠ **段的定义**是「从一处报错行到下一处报错行之前」⇒ 依赖**报错行正则**的准确
  ⇒ 若某处报错**换了一种写法**（不再匹配报错行正则）⇒ 它就不在配对范围内
  ⇒ ⇒ **报错行正则本身被改弱**这条老边界**不在本批范围内**
  ⇒ ⇒ 但那会同时改到「报错行数」⇒ 配对门的**总数**校准会红 ⇒ 至少不会被静默放过；
- ⚠ **最后一段到文件末** ⇒ 文件尾部若有一处**不属于任何报错**的计数行
  ⇒ 会被算进最后一段 ⇒ 段内计数数变 2 ⇒ 红
  ⇒ ⇒ 这是**故意**的（孤儿计数行同样值得看一眼）⇒ 但改脚本时要知道；
- ⚠ 本批只覆盖 **2 个配对门**（`check-deb-layout.sh` / `contract-check.sh`）
  ⇒ 其它脚本里的「报错 + 计数」形态**没有**被逐段核对
  ⇒ ⇒ 全仓**收口到同一个 helper**（像 `build-deb.sh` 的 `die`）是更彻底的路子
  ⇒ ⇒ **本批不做**（改动面大 ⇒ 风险收益不划算）⇒ 如实记为待办；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1028 → 1031**（+3）、执行次数 **1031 → 1034**（+3）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1028 → 1031**（**三处**同步）；
- 段级 trailer **42 → 43**；整行 `exit 1` **3 不变**；
  `ARCH_ANY_FAIL=1` = **43**；`ARCH_FAIL=0` = **44**；
- 豁免表 **14 条不变**；盘点 **15 组 / 63 处**（登记册 **15 行**，本批未变）；
- 接线门 **1034** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**
  （判定层 396 条判据 / shell 与 python **660** 个 if 条件（652 → 660：
  新增的逐段核对里有 8 个 if ⇒ **全部被判非恒真**）/ 断言实参 99 条）、
  孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**，但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**（与批 CK / CL / CM / CN / CO / CP / CQ / CR 相同，未变）；
- **负控 18/18 真红**；累计 **844/844**。


### E.2bc 崩了 ⇒ rc 强制 2（不许被更早的失败态顶替）（批 CT）

**① 起因（实测坐实 + 对照实验，不是推演）**

批 CQ 把审计器崩了改成了「记 rc=2」（盲区/未验证）⇒ 但当时 rc 取的是
「**最先失败的那个**」⇒ ⇒ 崩了这件事**只活在 stderr 的一行里**，
而 **rc 才是 CI 的分诊依据**。

⚠⚠⚨ **实测坐实**：先造一处**别的**失败（基线改错 ⇒ rc=6「条数与基线不符」）
**且**让审计器随后崩（`check_rx_syntax()` → `check_rx_syntax(1, 2)`）⇒

| | 输出里有吗 | rc |
|---|---|---|
| 「门项行数与基线不符」（rc=6） | 有 | ⚠⚠⚨ **6** |
| 「审计器**崩了**」 | 有（批 CQ 的一次报全 ✓） | — |

⇒ ⇒ 输出里**两条消息都在**（一次报全没丢）
⇒ ⇒ 但 **rc=6** ⇒ 门侧分诊表第 6 档说的是
「**门项行数与基线不符**（有门项被删了 / 被改成注释了 ⇒ 那些承诺没人守了）」
⇒ ⇒ 而真实原因是**审计器崩了** ⇒ ⚠⚠⚨ **排障被带偏**
（人先去看「谁删了门项」，而真正的问题是审计器自己崩了）。

**② 修法（只动判据层 ⇒ 零产品代码改动）**

① **崩了 ⇒ rc 强制 2**（不再取「最先失败的那个」）：
新增模块级常量 `CRASH_RC = 2`，兜底 `except` 分支改成 `return CRASH_RC`
⇒ ⇒ **rc=2**（盲区家族：那些检查**没跑完** ⇒ 那些门项根本没被审）
⇒ ⇒ **分诊依据不再被顶替**；
⇒ ⚠ **已报出来的失败态不丢**（批 CQ 的一次报全照旧）⇒ 别的失败照样看得见。

② **为什么单独一个常量**（不是就地写 2）：就地写 2 ⇒ 整行锚定的门**分不出**
「这处 `return 2` 是崩了、还是那 4 处**前置**早退」⇒ 单独一个常量
⇒ 门能**指名道姓**地盯住崩了的那一处。

③ **rc=2 的分诊文案补一句**（「也可能是**审计器崩了**」）
⇒ ⚠ 批 AZ/CC 纪律：**按退出码说原因** ⇒ 不然 rc=2 那一档**不包含**「崩了」
⇒ ⇒ 照样被带偏。

**③ 落门 / 判据**

- **新增 2 条**（**全整行锚定**，批 CT 独立段）：
  ① 「崩了的**退出码常量**必须被钉死」（`^CRASH_RC = 2$`）
  ② 「崩了的**出口**必须走这个常量」（`^\s+return CRASH_RC$`）
  ⇒ ⚠ 后者盯着「别改回 `return FAILS[0] if FAILS else 2`」
  ⇒ 否则**顶替的洞原样回来**；
- **原地替换 1 条**：rc=2 的**分诊文案**（补「也可能是**审计器崩了**」）；
- **原地替换 2 条**：段级计数 `ARCH_ANY_FAIL=1` **43 → 44**、
  `ARCH_FAIL=0` **44 → 45** ⇒ 段级 trailer **43 → 44**；整行 `exit 1` **3 不变**；
- **同步**（批 BY/BS）：门项总数基线 `ci-wiring-gates.baseline` **1031 → 1033**
  ⇒ ⚠⚠⚨ **同一个数字要写三处**（基线文件 / `GATE_LINES_EXPECTED` / 门 ③ 的正则）
  ⇒ 沿用**批 CR** 立的机制；
- 盘点登记册 **15 行不变**（本批**没有新增**「未验证/跳过」提示 ⇒ 新消息不含
  那两个关键词 ⇒ 盘点处数不变）；豁免表 **14 条不变**；
  审计器锚定形态适用范围 **17 个脚本不变**；
  ⚠ **批 CQ 的分桶门零改动**（`FAILS.append(2)` 仍 **4** 处 —— 崩了那条仍然
  记 2，只是**不再参与 rc 的选取**）。

**④ 负控 16/16 真红（3 组控制 + 5 条基线口径）**

- **基线（5 条）**：审计器 `--list` rc=0；`CRASH_RC = 2` 在位；
  `return CRASH_RC` 在位；rc=2 的分诊文案已提到「崩了」；接线门 rc=0；
- **N1（核心 · 对照实验 · 6 条）**：⚠⚠⚨ 先造 rc=6 **且**让审计器崩
  ⇒ **rc=2**（不再被顶替）⇒ ⚠ 别的失败（rc=6 那条）**照样报出来**
  ⇒ 「审计器**崩了**」那条也在输出里
  ⇒ ⇒ **对照实验**：**HEAD 版旧审计器 + 同样两个变异 ⇒ rc=6**
  ⇒ ⇒ **两头都有证据**：旧行为**确实**顶替（洞坐实）、本批**确实**堵住；
- **N2（出口被改 · 3 条）**：把 `return CRASH_RC` 改回
  `return FAILS[0] if FAILS else 2` ⇒ 门 ② 红；
- **N3（常量值被改 · 3 条）**：把 `CRASH_RC = 2` 改成 `CRASH_RC = 3` ⇒ 门 ① 红；
- **回归（2 条）**：还原后审计器 rc=0 + 接线门 rc=0；
- ⚠ 全部**按行号**整行改、变异后语法过、`restore()` **刷新 mtime**。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠ **rc=2 现在有两种成因**（审计器自己有盲区 / 审计器崩了）⇒ 分诊表那一档
  只能**同时**说两种可能 ⇒ ⇒ 人还得看 stderr 才知道是哪种
  ⇒ ⇒ **这不是完全的信息分离**；完全分离要**新增一个专属码**（如 rc=10）
  ⇒ ⇒ 本批**不做**（那要动分诊表 + 码值语义 ⇒ 改动面更大）⇒ 如实记为待办；
- ⚠ 崩了时**别的失败态照样报出来**（批 CQ 的一次报全）⇒ 但 **rc 只反映「崩了」**
  ⇒ ⇒ 人可能**先**去修崩了、**后**才看到别的失败 ⇒ 这是**刻意的取舍**
  （崩了 ⇒ 后面那些检查根本没跑完 ⇒ 先修崩了才看得准别的失败）；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1031 → 1033**（+2）、执行次数 **1034 → 1036**（+2）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1031 → 1033**（**三处**同步）；
- 段级 trailer **43 → 44**；整行 `exit 1` **3 不变**；
  `ARCH_ANY_FAIL=1` = **44**；`ARCH_FAIL=0` = **45**；
- 豁免表 **14 条不变**；盘点 **15 组 / 63 处**（登记册 **15 行**，本批未变）；
- 接线门 **1036** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**、
  孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**，但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**（与批 CK / CL / CM / CN / CO / CP / CQ / CR / CS 相同，未变）；
- **负控 16/16 真红**；累计 **860/860**。


### E.2bd 「校验失败」不许被 `&&` 吞掉（ci.sh 第 3 步 ⇒ 假绿）（批 CU）

**① 起因（实测坐实 + 对照实验，不是推演）**

批 CU 立项前先查了一条此前没人查过的线：「**CI 的 15 步是不是都接住了退出码**」
⇒ 15 步**都**接住了（第 1/6/10/11/12/13 步都是 `|| _xxx_rc=$?` 的形态）
⇒ 但查到一个**没人接住的地方**：**第 3 步**（desktop / metainfo 校验）。

⚠⚠⚨ **实测坐实**：把 desktop 文件的 `Type` 写成非法值（`Applicationn`）⇒

| | 结果 |
|---|---|
| `desktop-file-validate` 的判定 | **rc=1**（error + hint 打在 stdout） |
| 旧版 ci.sh 的结论 | ⚠⚠⚨ **rc=0** |
| 旧版 ci.sh 的末尾 | 「**✓ CI 门通过**」 |
| 旧版 ci.sh 跑了几步 | **15/15**（第 3 步**没有停**） |

⇒ ⇒ **假绿坐实**：desktop 文件非法 ⇒ CI 一路带着它跑完 ⇒ 最后还说「门通过」。
⚠ 后果不小：desktop 非法 ⇒ 图标进不了启动器 / 点不起来；
metainfo 非法 ⇒ 软件中心里根本没有这个应用。

⚠ **根因**：`set -euo pipefail` 对 `&&` 列表里**非末位**命令的失败
**不触发退出**（bash / dash 实测：`false && echo OK` ⇒ 继续往下跑、rc=0）
⇒ ⇒ 旧形态 `desktop-file-validate … && echo "✓ desktop 合法"`
把**校验命令的成败**挂在 `&&` 后面 ⇒ **失败不影响 CI 的结论**。

⚠ **为什么没有第二道门兜底**：`desktop-file-validate` / `appstream-util`
**全仓只在 ci.sh 那一处被调用**（grep 全仓确认）⇒ 那个 `&&` 就是**唯一**的那道门
⇒ 它形同虚设 ⇒ 必须**行为修**（接住退出码）+ **形态门**（一次挡住整类）。

**② 修法（只动 CI 脚本 + 判据层 ⇒ 零产品代码改动）**

① **ci.sh 第 3 步两处校验改成「接住退出码 ⇒ 失败即判红」**
（与第 10/11/12/13 步**同款口径**）：

```sh
    _dfv_rc=0
    desktop-file-validate "$SRC/data/cn.deepdolphin.app.desktop" || _dfv_rc=$?
    if [ "$_dfv_rc" -ne 0 ]; then
        echo "✗ desktop 文件不合法（desktop-file-validate 退出码 $_dfv_rc）" >&2
        exit 1
    fi
    echo "✓ desktop 合法"
```

⇒ ⚠ 校验器自己的错误信息**原样留在输出里**（诊断不失真，批 CE 纪律）
⇒ ⚠ 退出码**原样报出**（不只说「失败」，还说「哪一类失败」，批 CC 纪律）。

② **判据层加门**（批 CU 独立段，**新增 3 条**）：
① **desktop 校验必须「接住退出码 + 判红」整块钉住**（`arch_need_ml` 跨行锚定：
初始化 → `|| _dfv_rc=$?` → `-ne 0` → 报错 → `exit 1` → `fi`）；
② **metainfo 校验同款**（`arch_need_ml` 跨行锚定）；
③ **形态 forbid**：ci.sh 里不许再出现「`&&` 挂着的 echo」
⇒ ⚠ 这一条**一次挡住整类**（批 CD 纪律：一次挡住整类，别逐点治标）。

**③ 落门 / 判据**

- **新增 3 条**（批 CU 独立段）：**2 条跨行锚定 + 1 条 forbid**；
- **原地替换 1 条**：批 BA 段「第 3 步 desktop/metainfo 校验的动作还在」
  ⇒ 正则改成新的调用行形态（`|| _dfv_rc=$?`）
  ⇒ ⚠ 批 BM 纪律：**不增行**（原地替换 ⇒ 门项条数不变）；
- **原地替换 3 条计数门**：ci.sh 的 `exit N` **34 → 36**（本批在 ci.sh 多了
  2 处失败出口）、`ARCH_ANY_FAIL=1` **44 → 45**、`ARCH_FAIL=0` **45 → 46**
  ⇒ 段级 trailer **44 → 45**；
- **同步**（批 CR 机制）：门项总数基线 **1033 → 1036** ⇒ ⚠⚠⚨ **三处同改**
  （基线文件 / `GATE_LINES_EXPECTED` / 门 ③ 的正则）；
- 盘点登记册 **15 行不变**（本批**没有新增**「未验证/跳过」提示
  ⇒ 新消息不含那两个关键词 ⇒ 盘点处数不变）；豁免表 **14 条不变**；
  审计器锚定形态适用范围 **17 个脚本不变**。

**④ 负控（实测坐实 + 对照实验）**

- **N1（行为级 · 对照实验）**：⚠⚠⚨ 同一个变异（desktop 的 `Type` 写成非法值）⇒
  **HEAD 版 ci.sh ⇒ rc=0 + 「✓ CI 门通过」+ 15/15 步跑完**
  ⇒ **本批版 ci.sh ⇒ rc=1 + 「✗ desktop 文件不合法（退出码 1）」+ 第 3 步就停**
  ⇒ ⇒ **两头都有证据**（旧行为**确实**放行 ⇒ 洞坐实；本批**确实**堵住）
  ⇒ ⚠ 对照实验用了 `appstream-util` 的 **stub**（本机缺该工具 ⇒ 第 3 步会走
  SKIP 支路 ⇒ `skip≠0` ⇒ 末尾恒 rc=3 ⇒ 假绿会被「未验证」这层红盖住
  ⇒ 证不出「第 3 步没停」⇒ 用 stub 补齐环境；**stub 只影响实验环境，不是产品改动**）；
- **N2～N6（门项级 · 5 条 · 逐条隔离）**：
  ① **N2** 失败分支的报错文案被改 ⇒ **恰好 1 条**门红（批 CU 的 desktop ml 门）；
  ② **N3** 在 ci.sh 里加一行「`&&` 挂着的 echo」⇒ **恰好 1 条**门红（形态 forbid 门）；
  ③ **N4** metainfo 的退出码没接住（`|| _asu_rc=$?` → `|| true`）⇒ **恰好 1 条**门红；
  ④ **N5** desktop 调用行**退回旧形态** ⇒ **3 条**门红（批 BA 的整行锚定门 +
  批 CU 的 desktop ml 门 + 形态 forbid 门）⇒ **形态回退被多处抓住**；
  ⑤ **N6** desktop 调用行被**追加行尾注释** ⇒ 整行锚定门红（批 BN 纪律的牙）；
  ⇒ ⚠ 全部**按行号**整行改、变异后 `sh -n` 过、**变异自己先自证**
  （要测的那个量**真的变了**）、`restore()` **刷新 mtime**；
  ⇒ ⚠ 部分变异**同时**触发审计器的「有门项命中 0 次」（rc=5）⇒ 那是**同一个变异**
  从另一侧被看见（好事），如实记着。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠ **forbid 门只覆盖 ci.sh**（`arch_forbid` 是单文件门型）⇒ 别的文件里再出现
  同款形态**不会被这条门抓住**；⚠ 全仓 grep 过：`&& echo` 在**判据层脚本里
  只有 ci.sh 这 2 处** ⇒ **类已封边**，但 **macos 侧脚本未逐个查**；
- ⚠ **metainfo 那一处本机没真跑过**（本机缺 `appstream-util` ⇒ 走 SKIP 支路）
  ⇒ 负控里用 **stub**（返回 1）验证了「失败 ⇒ 判红」的通路 ⇒ ⚠ **stub 不等于
  真实工具的行为** ⇒ 真机装上 `appstream-util` 后应再跑一次；
- ⚠ **本批只堵了 ci.sh 第 3 步** ⇒ 其它脚本里「校验命令的成败挂在别处」的写法
  **本批没查**；
- ⚠ **批 CT 遗留的「rc=2 有两种成因」没解决**（新增专属码 rc=10）⇒ 仍是待办；
- ⚠ **改动的是 CI 脚本**（不是产品代码）⇒ 快照零变化 ⇒ **影响面实测为零**。

**⑥ 数字**

- 门项物理行数 **1033 → 1036**（+3）、执行次数 **1036 → 1039**（+3）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1033 → 1036**（**三处**同步）；
- 段级 trailer **44 → 45**；整行 `exit 1`（判据层）**3 不变**；
  `ARCH_ANY_FAIL=1` = **45**；`ARCH_FAIL=0` = **46**；
- ⚠ **ci.sh 自己的 `exit N`** **34 → 36**（本批新增 2 处失败出口）；
- 豁免表 **14 条不变**；盘点 **15 组 / 63 处**（登记册 **15 行**，本批未变）；
- 接线门 **1039** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**
  （判定层 396 条判据 / shell 与 python **664** 个 if 条件（661 → 664：
  本批 ci.sh 新增 2 个 `if` + 判据层新增 1 个段 trailer `if`）/ 断言实参 99 条）、
  孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- **负控 5/5 真红**；累计 **865/865**。

### E.2be 「可达」判定不许被**注释**顶替（孤儿探针 ⇒ 假绿）（批 CV）

**① 起因（实测坐实 + 对照实验，不是推演）**

批 CU 收的是「CI 第 3 步的校验失败被 `&&` 吞掉」。批 CV 顺着同一条线往下查：
**判据层自己的门，有几道是「用文本模式匹配某样东西 ⇒ 它就一定在」**——
这类门的共同弱点是：**匹配到的可能是注释/字符串，不是真代码**。

⇒ 全仓盘下来，**判据层里唯一的「假绿方向」命中**在
`scripts/ci-orphan-probe.sh`（批 BD 立的「断言脚本不许游离在 CI 之外」门）：
它的 `calls_of()` 在**原始文本**里找调用点 ⇒ ⚠⚠⚨ **不剥注释**。

⚠⚠⚨ **实测坐实**（同一个脚本，两种写法）：

| | 孤儿探针的结论 |
|---|---|
| 造一个**没有任何真调用点**的断言脚本 | **rc=1**（报「游离」） ✓ 正常工作 |
| **只**在 ci.sh 里加一行**注释**（`# sh "$SRC/scripts/<那个脚本>.sh"`） | ⚠⚠⚨ **rc=0**（「全部可达」）⇒ **假绿** |

⇒ ⇒ **批 BD 的承诺（「仓库里少了一份断言 ⇒ 必须红」）可被一行注释破掉**。
⚠ 这一处**特别刺眼**：那道门是**专门为「承诺不许悄悄消失」而建**的
⇒ 它自己形同虚设 ⇒ **比没有门更坏**（给人虚假的安全感）。

**② 修法（只动判据层脚本 ⇒ 零产品代码改动）**

① `calls_of()` **先剥注释**再找调用点 ⇒
⚠ **抽取**而非复刻（批 CF / AV 纪律：判据层只有**一份**剥注释实现）
⇒ 与 `ci.sh`（第 4 步）、`ci-d2.sh` **同款现成写法**（那两处已经这么抽）
⇒ **零漂移**；
② **抽取失败 ⇒ 指名道姓地失败**（不许静默降级成「不剥注释」
⇒ 那等于把本批收掉的洞原样放回去 ⇒ 假绿）；
③ **剥注释失败**（工具失败 ≠ 没找到）⇒ **判红**
（不许当成「没有游离脚本」⇒ 判据不可信时必须说不可信，批 CG 同款口径）。

**③ 落门 / 判据**

- **新增 4 条**（批 CV 独立段）：
  ① 「孤儿探针的**剥注释必须从 ci-wiring.sh 抽取**」（**整行锚定**）
  ② 「抽取失败**必须指名道姓地失败**」（**整行锚定**，钉住那句诊断）
  ③ 「孤儿探针**不许自己实现剥注释**」（**forbid 门**：sed 那一支与 perl 那一支
  **一起禁掉** ⇒ 只许用 ci-wiring.sh 那一份）
  ④ 「**剥注释失败必须当成失败**」（**整行锚定**，钉住 trap 里那一段）；
- **原地替换 2 条**（批 BM 不增行）：
  ① 批 BD 段「**排除门项行**」那条 ⇒ 正则改成新形态
  （`strip_comments "$_cf" | grep -vE …` ⇒ **一条门同时守住
  「先剥注释」+「排除门项行」两件事**）
  ② 批 BD 段「孤儿探针自己的报错行计数」**7 → 8**
  （新增「剥注释抽取失败 ⇒ 判失败」那条）
  ⇒ ⚠ **批 BT 的「失败上报条数」**也 **6 → 7**（新增 `exit 1`）
  ⇒ ⚠⚠⚨ **两处「恰好 N 处」的说明文字同步改**（批 BB 纪律）；
- **同步**（批 CR 机制）：门项总数基线 **1036 → 1040** ⇒ ⚠⚠⚨ **三处同改**；
- 盘点登记册 **15 行不变**（新消息不含「未验证/跳过」关键词）；
  豁免表 **14 条不变**；审计器锚定形态适用范围 **17 个脚本不变**。

**④ 负控（行为级对照实验 + 门项级逐条隔离 · 5 条）**

- **N1（行为级 · 对照实验）**：同一个变异（注释里冒充调用点）⇒
  **修复前 rc=0（假绿）** ⇒ **修复后 rc=1（「断言脚本游离在 CI 之外」）**
  ⇒ ⇒ **两头都有证据**（旧行为**确实**放行 ⇒ 洞坐实；本批**确实**堵住）；
- **N2～N6（门项级 · 5 条 · 逐条隔离）**：
  ① `calls_of` 退回旧形态（不剥注释）⇒ **恰好 1 条**门红（批 BD 那条）；
  ② 「抽取」被摘掉 ⇒ **恰好 1 条**门红（批 CV 的抽取门）；
  ③ 抽取失败的诊断被删 ⇒ **恰好 1 条**门红；
  ④ 孤儿探针**自己实现剥注释** ⇒ **恰好 1 条**门红（forbid 门）；
  ⑤ trap 里「剥注释失败 ⇒ 判红」被摘 ⇒ **恰好 1 条**门红；
  ⇒ ⚠ 全部**按行号**整行改、变异后 `sh -n` 过、**变异自己先自证**
  （要测的那个量**真的变了**）、`restore()` **刷新 mtime**；
  ⇒ ⚠ 多数变异**同时**触发审计器的「次数失准」（rc=4）
  ⇒ 那是**同一个变异**从另一侧被看见（好事），如实记着。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠ **剥注释口径对 `.sh` 只剥「整行注释」**（判据层既有的单一真相源口径）
  ⇒ **行尾注释**里的同形文本**仍可能**被当成调用点（如 `foo=1  # sh …`）
  ⇒ ⇒ 这是**全仓同款口径**的已知边界（如实记着，不在本批修）；
- ⚠ **「什么算断言脚本」那条判定**（`grep -q '✗ '`）**仍不剥注释**
  ⇒ 一个只在注释里写了 `✗ ` 的**非**断言脚本会被算成断言脚本
  ⇒ ⚠ 方向是**假红**（多查一个脚本），不是假绿 ⇒ 本批**不动它**（改了会动
  「断言脚本条数」这个口径 ⇒ 波及面大）；
- ⚠ **孤儿探针现在依赖 `ci-wiring.sh` 存在**（因为要抽它那份剥注释）
  ⇒ 路径给错时 ⇒ 探针**判红**（fail closed）⇒ 已把抽取挪到
  「找不到 CI 入口」检查**之后** ⇒ 诊断指得准（实测：相对路径 ⇒
  「✗ 找不到 CI 入口」，不是「抽取失败」）；
- ⚠ **批 CT 遗留的「rc=2 有两种成因」没解决**（专属码 rc=10）⇒ 仍是待办；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1036 → 1040**（+4）、执行次数 **1039 → 1043**（+4）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1036 → 1040**（**三处**同步）；
- 段级 trailer **45 → 46**；整行 `exit 1`（判据层）**3 不变**；
  `ARCH_ANY_FAIL=1` = **46**；`ARCH_FAIL=0` = **47**；
- ⚠ **孤儿探针自己的**报错行 **7 → 8**、失败上报 **6 → 7**；
- 豁免表 **14 条不变**；盘点 **15 组 / 63 处**（登记册 **15 行**，本批未变）；
- 接线门 **1043** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**
  （判定层 396 条判据 / shell 与 python **666** 个 if 条件（664 → 666：
  本批新增 2 个 `if`：抽取那一处 + trap 里那一处）/ 断言实参 99 条）、
  孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- **负控 5/5 真红**；累计 **870/870**。

### E.2bf 崩了 ⇒ **专属码 rc=10**（与「盲区 rc=2」完全分离）（批 CW）

**① 起因（批 CT 留下的已知边界，不是推演）**

批 CT 让「崩了」不再被更早的失败态顶替（实测：先造 rc=6 且让审计器崩
⇒ 旧行为 rc=6 ⇒ 分诊依据指向别的原因 ⇒ 排障被带偏）。
⚠ 但批 CT 当时把崩了归进 **rc=2（盲区）** ⇒ ⇒ **rc=2 有两种成因**
（「真有盲区」/「审计器自己崩了」）⇒ 分诊那一档**说不出到底是哪一种**
⇒ ⇒ 人看到 rc=2 ⇒ 先去查盲区 ⇒ 若盲区清单看不出问题
⇒ **就不会想到是崩了** ⇒ ⚠⚠⚨ **排障还是会被带偏**（只是比批 CT 之前好一点）。

⇒ 本批：**专属码 rc=10** ⇒ 与 rc=2 **完全分离** ⇒ 分诊表里**单独一档**
⇒ 「崩了」再也**混不进去** ⇒ 分诊依据就是 rc 本身。

**② 修法（只动判据层脚本 ⇒ 零产品代码改动）**

① 审计器 `CRASH_RC = 2` ⇒ **`CRASH_RC = 10`**（崩了时**强制**这个码）；
② 门侧分诊表**加一档** `10) _audit_why="审计器**崩了**…"`；
③ **rc=2 的分诊文案改写**：去掉「也可能是审计器崩了」那半句
（现在崩了是 rc=10 ⇒ rc=2 **只**表示盲区）⇒ ⚠ **说明文字必须与实际行为一致**。

⚠⚠⚨ **rc 语义只加不改**：rc=2/3/4/5/6/7/8/9 的含义**一个字都没动**
⇒ 门侧分诊表的既有各档**零改动** ⇒ 只**多**一档。
⚠ **别的一律不动**：审计器里 `FAILS.append(2)` **照旧**（崩 ⇒ 那些检查没跑完
⇒ **性质**仍是盲区）⇒ 报告里的「性质」分桶不变 ⇒ 只改**分诊用的 rc**。

**③ 落门 / 判据**

- **新增 2 条**（批 CW 独立段）：
  ① 「接线门必须**按审计器的第 10 种失败态说原因**」（**整行锚定**
  ⇒ 少了它 ⇒ `case` 落到 `*)` ⇒ 报「未知的失败码」⇒ 排障被带偏）
  ② 「**rc=2 的分诊文案不许再提「崩了」**」（**forbid 门**
  ⇒ 文案里若又混进「崩了」⇒ 人会以为 rc=2 可能是崩 ⇒ 分诊依据又被带偏）；
- **原地替换 4 处**（批 BM 不增行）：
  ① 批 CT 段钉 `CRASH_RC` 值那条 ⇒ 正则 `2` → **`10`**（说明文字同步改）
  ② 批 CT 段钉「崩了的出口必须走这个常量」那条（**形态未变**，说明补批 CW 注）
  ③ `ARCH_ANY_FAIL=1` **46 → 47** ④ `ARCH_FAIL=0` **47 → 48**
  ⇒ 段级 trailer **46 → 47**；
- **同步**（批 CR 机制）：门项总数基线 **1040 → 1042** ⇒ ⚠⚠⚨ **三处同改**；
- 盘点登记册 **15 行不变**；豁免表 **14 条不变**；
  审计器锚定形态适用范围 **17 个脚本不变**。

**④ 负控（行为级对照实验 + 门项级逐条隔离 · 3 条）**

- **N1（行为级 · 对照实验）**：把审计器里 `check_rx_syntax()` 改成
  `check_rx_syntax(1)` ⇒ 必然 **TypeError** ⇒ 崩 ⇒
  ⚠⚠⚨ **HEAD 版（整树 `git archive HEAD`）⇒ rc=2**
  ⇒ **本批版 ⇒ rc=10**
  ⇒ ⇒ **两头都有证据**（旧行为**确实**与盲区混一档；本批**确实**分开）；
- **N2～N4（门项级 · 3 条 · 逐条隔离）**：
  ① 分诊表的 `10)` 那一档被摘 ⇒ **恰好 1 条**门红（批 CW 的整行锚定门）
  ② rc=2 的文案里又混进「崩了」⇒ **恰好 1 条**门红（forbid 门）
  ③ `CRASH_RC` 被改回 2 ⇒ **恰好 1 条**门红（批 CT 那条钉值门）
  ⇒ ⚠ 全部**按行号**整行改、变异后语法过、**变异自己先自证**
  （要测的那个量**真的变了**）、`restore()` **刷新 mtime**；
  ⇒ ⚠ N2/N4 **同时**触发审计器的「次数失准」（rc=4）
  ⇒ 那是**同一个变异**从另一侧被看见（好事），如实记着。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠ **rc=10 只在「审计器崩了」这一种情形出现** ⇒ 若将来还有别的成因要进这一档，
  得在分诊文案里逐个点名（否则又是「一码多因」）；
- ⚠ **审计器 `FAILS.append(2)` 照旧** ⇒ 报告里的「性质」分桶仍记作盲区
  ⇒ ⚠ 这是**有意**的（性质与分诊依据分开记）⇒ 如实记着；
- ⚠ **分诊表是「按码值分档」** ⇒ 新增一档就要在**别处**同步
  （本批：rc=2 的文案 + 两条新门 ⇒ 都已同步）；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1040 → 1042**（+2）、执行次数 **1043 → 1045**（+2）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1040 → 1042**（**三处**同步）；
- 段级 trailer **46 → 47**；整行 `exit 1`（判据层）**3 不变**；
  `ARCH_ANY_FAIL=1` = **47**；`ARCH_FAIL=0` = **48**；
- 豁免表 **14 条不变**；盘点 **15 组 / 63 处**（登记册 **15 行**，本批未变）；
- 接线门 **1045** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**
  （判定层 396 条判据 / shell 与 python **667** 个 if 条件（666 → 667：
  本批新增的段 trailer 那一个 `if`）/ 断言实参 99 条）、
  孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- **负控 3/3 真红**；累计 **873/873**。

### E.2bg 「未验证的逻辑出口」也要进登记册（盘点口径不只数提示行）（批 CX）

**① 起因（实测坐实 + 对照实验，不是推演）**

盘点脚本（批 CM 立的「未验证出口清单 + 逐组带理由的登记册」）的口径是
**「带未验证关键词的打印行」** ⇒ ⇒ 判据层里一处 `exit 3`（未验证的**逻辑出口**）
若**没带提示** ⇒ **登记册看不见它** ⇒ ⇒ 「**未验证出口必须明示**」这条纪律
**没有牙**。

⚠⚠⚨ **实测坐实**（同一个变异，两个版本）：

| | 盘点脚本的结论 |
|---|---|
| HEAD 版：在判据层里加一处**没提示**的 `exit 3` | ⚠⚠⚨ **rc=0**（「15 组 / 63 处」照样相等）⇒ **假绿** |
| 本批版：**同一个**变异 | **rc=1**（「实测有、登记册没有（新增未登记）1 条：ci-d2.sh/未验证逻辑出口=1」） |

⇒ ⇒ 「少登记一个未验证出口」**从机器看不见 ⇒ 变成必红**。

**② 修法（只动判据层脚本 ⇒ 零产品代码改动）**

① 盘点口径**多算一类**「未验证逻辑出口」（`exit 3`，未验证的**专属码**，
批 CC/CL 立的）⇒ ⚠ 排除表**不适用**于它（它不是「提示行」）⇒ 命中即计入；
② 登记册**逐文件**登记这一类的处数（+6 行）⇒ 新增一处出口
（**带不带提示都一样**）⇒ 处数对不上 ⇒ **必红**；
③ 成功消息把「其中 N 处是未验证的逻辑出口」**说出来**（不许混在总数里）。

⚠⚠⚨ **为什么「逐文件登记处数」而不是「逐处登记」**（批 CM 遗留① 已否决）：
逐处化会因为**同款文案**导致集合比对塌陷 ⇒ 假红；此处登记的是**条数**
（按文件聚合）⇒ **不碰文案** ⇒ **不撞那个否决理由** ⇒ 两条路都保住了。

**③ 落门 / 判据**

- **新增 2 条**（批 CX 独立段）：
  ① 「盘点口径必须**把「未验证的逻辑出口」算进来**」（**整行锚定**）
  ② 「盘点必须**真的按这一类计站点**」（**整行锚定**
  ⇒ ⚠ 口径常量在、但扫描时不判 ⇒ 等于没这一类 ⇒ 假绿回来）；
  ⇒ ⚠⚠⚨ 两条门的正则**从真实行现抽构造**（手抄转义已经踩过两次坑：
  一次是 `"` 被 Python 解成字面 `"`，一次是 `` 被解成**退格符**）；
- **原地替换 4 处**（批 BM 不增行）：
  ① 登记册条数基线常量那条门 **15 → 21**（说明文字同步改）
  ② `ARCH_ANY_FAIL=1` **47 → 48** ③ `ARCH_FAIL=0` **48 → 49**
  ⇒ 段级 trailer **47 → 48** ④ 门项条数第三处 **1042 → 1044**；
- **同步**（批 CR 机制）：门项总数基线 **1042 → 1044** ⇒ ⚠⚠⚨ **三处同改**；
- 盘点登记册 **15 行 → 21 行**（新增 6 行「未验证逻辑出口」）；
  豁免表 **14 条不变**；审计器锚定形态适用范围 **17 个脚本不变**。

**④ 负控（行为级对照实验 + 门级逐条隔离 + 盘点级 · 3 条）**

- **N1（行为级 · 对照实验）**：在判据层里加一处**没提示**的 `exit 3`
  ⇒ ⚠⚠⚨ **HEAD 版（整树 `git archive HEAD`）⇒ rc=0**（假绿）
  ⇒ **本批版 ⇒ rc=1** ⇒ ⇒ **两头都有证据**；
- **N2** 盘点扫描时不再判这一类 ⇒ **恰好 1 条**门红（批 CX 的门 ②）
- **N3** 口径常量被改掉 ⇒ **恰好 1 条**门红（批 CX 的门 ①）
- **N4** 登记册少登记一个文件的未验证出口 ⇒ **盘点红**
  ⇒ ⚠ 实际先响的是「**登记册条数 ≠ 基线**」那条（批 BC：清单不许被删）
  ⇒ 比双向红**更早**更严 ⇒ 如实记着；
  ⇒ ⚠ N2/N3 **同时**触发审计器的「次数失准」（rc=4）
  ⇒ 那是**同一个变异**从另一侧被看见（好事），如实记着。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠ **口径只认 shell 的 `exit 3`**（未验证的专属码）⇒ 将来若用别的码表示
  「未验证」，这条口径要跟着改；
- ⚠ **盘点范围仍只是 `deepin/scripts/`**（批 BX 已知边界）
  ⇒ `macos/scripts/` 的未验证出口**仍不在册**；
- ⚠ **「未验证逻辑出口」这一类按文件聚合** ⇒ 同一文件里**哪一处**新增的
  **机器看不出**（只知「这个文件多了一个」）⇒ 属批 CM 遗留① 那一族的边界
  （逐处化已否决）⇒ 如实记着；
- ⚠ **判据层之外**（产品代码里的 `exit 3` 等）**不在盘点范围**；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1042 → 1044**（+2）、执行次数 **1045 → 1047**（+2）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1042 → 1044**（**三处**同步）；
- 段级 trailer **47 → 48**；整行 `exit 1`（判据层）**3 不变**；
  `ARCH_ANY_FAIL=1` = **48**；`ARCH_FAIL=0` = **49**；
- ⚠ **盘点**：**15 组 / 63 处 → 21 组 / 72 处**
  （登记册 **15 行 → 21 行**；其中 **9 处**是未验证的逻辑出口）；
- 豁免表 **14 条不变**；
- 接线门 **1047** 项全绿、审计器硬门与报告模式 **rc=0**、恒真探针 **rc=0**
  （判定层 396 条判据 / shell 与 python **669** 个 if 条件（667 → 669：
  本批盘点脚本新增 1 个 `if` + 判据层新增 1 个段 trailer `if`）/
  断言实参 99 条）、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- **负控 3/3 真红**；累计 **876/876**。

### E.2bh 「未验证出口登记册」的覆盖面不许只覆盖一半（范围 + 键唯一）（批 CY）

**① 起因（实测坐实 + 对照实验，不是推演）**

盘点脚本（批 CM 立的「未验证出口清单 + 逐组带理由的登记册」）的扫描范围
**写死**在 `SCRIPTS = HERE`（= `deepin/scripts/`）
⇒ ⇒ `macos/scripts/` 里那 **12 个判据脚本**的未验证出口**完全不在册**
⇒ ⇒ 而判据层**早已有门项盯着 `macos/scripts/*.sh`**（批 AJ 起）
⇒ ⇒ 「**未验证出口必须登记**」这条纪律的覆盖面**比门项覆盖面窄**。

⚠⚠⚨ **实测坐实**（同一个变异，两个版本）：

| | 盘点脚本的结论 |
|---|---|
| HEAD 版：在 mac 侧判据脚本里加一处**没提示**的专属码 3 出口 | ⚠⚠⚨ **rc=0**（假绿）|
| 本批版：**同一个**变异 | **rc=1**（「实测有、登记册没有（新增未登记）1 条：macos/scripts/contract-check.sh/未验证逻辑出口=1」）|

⚠⚠⚨ **第二个洞（扩范围时必踩）**：两个目录里**都有** `contract-check.sh`
⇒ 若登记册仍用**裸文件名**做键 ⇒ 两个文件的处数**合并**
⇒ ⇒ **一处新增 + 一处减少 = 净 0** ⇒ 登记册照样相等 ⇒ **假绿**。

⚠⚠⚨ **实测坐实**（两臂对照，同一个「净 0」变异）：
**臂 A（裸名键）** mac 侧 +1 处、deepin 侧 -1 处 ⇒ 盘点 **rc=0**（假绿）；
**臂 B（路径键）** **同一个**净 0 变异 ⇒ 盘点 **rc=1**（真红）。

⚠⚠⚨ **第三个洞（登记册自身撞车）**：同一 (文件, 分类) 出现两行
⇒ 字典里**静默塌陷**（后一条盖前一条）⇒ 行数对了、组数少了
⇒ 「登记册条数基线」**名不副实**。

**② 修法（只动判据层脚本 ⇒ 零产品代码改动）**

① 范围改成**一个常量** `UNVERIFIED_SCOPE = ("deepin/scripts", "macos/scripts")`
（**相对仓库根**）⇒ 递归扫（跳过 `__pycache__`）
⇒ ⚠ 门项**整行钉住**这一行（范围被改窄 ⇒ 门红）
⇒ ⚠⚠⚨ **另有一条门钉住「真的遍历它」**（常量在、但不遍历 ⇒ 等于没扩范围）；
② 键改成**相对仓库根的路径**（`os.path.relpath(path, REPO_ROOT)`）⇒ **唯一**
⇒ 登记册 **21 行**的文件列**全部**改成路径（机械重写，条数不变）；
③ **fail-closed**：范围目录**不存在** / 里面**一个判据脚本都没有**
⇒ 当场 `sys.exit` 判红（`os.walk` 对不存在的目录**不报错**、直接产出空
⇒ 不判红 ⇒ 范围被悄悄掏空 ⇒ 盘点等于没跑 ⇒ **假绿**）；
④ 登记册的 (文件, 分类) 键**不许重复** ⇒ 当场判红（**指名道姓**说「键撞车」）；
⑤ 成功消息把**范围**说出来（不许混在总数里）。

⚠⚠⚨ **实测影响面为零**：mac 侧用同一套口径实测 ⇒ **当前 0 处**
⇒ 登记册**行数不变**（21 行）、**处数不变**（72 处）
⇒ ⚠ 登记册里**没有** `macos/scripts/` 的行 ⇔ **实测那边当前 0 处**
（范围已覆盖 ⇒ 那边新增一处 ⇒ 盘点**必红**）。

**③ 落门 / 判据**

- **新增 6 条**（批 CY 独立段）：
  ① 「盘点范围**必须同时含两个判据脚本目录**」（**整行锚定**）
  ② 「盘点**必须真的遍历**那个范围常量」（**整行锚定**
  ⇒ ⚠ 常量在、但不遍历 ⇒ 假绿回来 ⇒ 批 CX 同款教训）
  ③ 「范围目录**不存在**时必须**当场判红**」（**整行锚定**）
  ④ 「登记册的**键必须用相对仓库根的路径**」（**整行锚定**
  ⇒ 跨目录同名文件撞车 ⇒ 处数互相抵消 ⇒ **假绿**）
  ⑤ 「登记册的 **(文件, 分类) 键不许重复**」（**整行锚定**）
  ⑥ 「登记册**每一行的文件列都必须带目录**」（`arch_need_min`
  ⇒ ⚠ 下限**恰好 21** ⇒ 与登记册条数基线 21 合起来 ⇒
  ⇒ **一条都不许是裸名**；⚠ 下限由审计器 `check_min_gates` 校准
  ⇒ 下限写小了 ⇒ 门没牙）
  ⇒ ⚠⚠⚨ 5 条 `arch_need_count` 的正则**从真实行现抽构造**
  （空格留字面、只转义 ERE 元字符）⇒ 手抄转义已踩过两次坑；
  ⇒ ⚠ 登记册那条正则**不用 POSIX 空白类**（`[[:blank:]]`）⇒
  ⚠⚠⚨ **Python `re` 不认 POSIX 类** ⇒ 审计器与门侧口径会分叉
  ⇒ 改用「键前缀」形态 `^[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+`
  ⇒ GNU `grep -E` 与 Python `re` **实测一致**（各命中 21 行）；
- **原地替换 6 处**（批 BM 不增行）：
  ① 批 CM 那条钉 `selftest_strip_parity` 调用形态的门
  ⇒ 随递归扫描改形态（**期望值不变** ⇒ 门项**数**不变 ⇒ 但**行**变了）
  ② `ARCH_ANY_FAIL=1` **48 → 49** ③ `ARCH_FAIL=0` **49 → 50**
  ⇒ 段级 trailer **48 → 49** ④ 门项条数第三处 **1044 → 1050**；
- **同步**（批 CR 机制）：门项总数基线 **1044 → 1050** ⇒ ⚠⚠⚨ **三处同改**；
- 盘点登记册 **21 行不变**（⚠ 只是**文件列**从裸名改成路径）；
  豁免表 **14 条不变**；审计器锚定形态适用范围 **17 个脚本不变**。

**④ 负控（行为级对照实验 + 门级逐条隔离 + 盘点级 · 8 条）**

- **N1（行为级 · 对照实验）**：在 mac 侧判据脚本里加一处**没提示**的专属码 3 出口
  ⇒ ⚠⚠⚨ **HEAD 版（整树 `git archive HEAD`）⇒ 盘点 rc=0**（假绿）
  ⇒ **本批版 ⇒ 盘点 rc=1** ⇒ ⇒ **两头都有证据**；
- **N2** 范围常量被改窄（只剩 `deepin/scripts`）⇒ **恰好 1 条**门红；
- **N3** 范围常量在、但扫描时不遍历它 ⇒ **恰好 1 条**门红；
- **N4** 范围目录不存在时的 fail-closed 判定行被改 ⇒ **恰好 1 条**门红；
- **N5** 登记册的键被改成裸文件名 ⇒ **恰好 1 条**门红 **且**盘点红；
- **N6** 登记册里出现裸文件名键 ⇒ **恰好 1 条**门红 **且**盘点红；
- **N7** 登记册出现重复的 (文件, 分类) 键 ⇒ 盘点红 **且**输出**指名道姓**
  报出「重复的 (文件, 分类) 键」（21 行 ⇒ distinct 键 20 个）；
- **N8（两臂对照）**：跨目录处数**互相抵消**
  ⇒ 臂 A（裸名键）盘点 **rc=0**（假绿）⇒ 臂 B（路径键）**同一个**变异
  ⇒ 盘点 **rc=1**（真红）⇒ ⇒ **证明「键必须唯一」不是洁癖**；
- ⇒ ⚠ N2～N6 **同时**触发审计器的「次数失准」（rc=4）
  ⇒ 那是**同一个变异**从另一侧被看见（好事），如实记着；
- ⇒ ⚠ 全部**按行号**整行改、变异后**语法过**（`ast.parse` 自证）、
  **变异自己先自证**（要测的那个量**真的变了**）、`restore()` **刷新 mtime**
  ⇒ 还原后与 harness 启动时的差异**逐字节相同**。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠ **登记册的重复键检查独立于双向红**（双向红**也会**红，但它指的是
  「实测有、登记册没有」⇒ **指错了方向**）⇒ 这条门的作用是**指名道姓**；
- ⚠ mac 侧**当前实测 0 处** ⇒ 登记册里**没有** `macos/scripts/` 的行
  ⇒ ⚠ 「mac 侧到底有没有未验证出口」这件事**只能靠实测**，不能靠登记册反推；
- ⚠ **盘点口径仍只认 shell / python**（`.sh` / `.py`）
  ⇒ `macos/Tests/*.swift` 里的判据**不在盘点范围**；
- ⚠ **口径只认 shell 的 `exit 3`**（未验证的专属码）
  ⇒ 将来若用别的码表示「未验证」，这条口径要跟着改；
- ⚠ **「未验证逻辑出口」这一类按文件聚合** ⇒ 同一文件里**哪一处**新增的
  **机器看不出**（只知「这个文件多了一个」）⇒ 属批 CM 遗留① 那一族的边界；
- ⚠ **判据层之外**（产品代码里的 `exit 3` 等）**不在盘点范围**；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1044 → 1050**（+6）、执行次数 **1047 → 1053**（+6）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1044 → 1050**（**三处**同步）；
- 段级 trailer **48 → 49**；整行 `exit 1`（判据层）**3 不变**；
  `ARCH_ANY_FAIL=1` = **49**；`ARCH_FAIL=0` = **50**；
- ⚠ **盘点**：**21 组 / 72 处不变**（登记册 **21 行不变**；⚠ 只是文件列
  从裸名改成路径；⚠ 范围扩到两个目录后 **mac 侧实测 0 处** ⇒ 处数不变）；
- 豁免表 **14 条不变**；
- 接线门 **1053** 项全绿、审计器硬门与报告模式 **rc=0**（门项 1050/1050 对基线）、
  恒真探针 **rc=0**（判定层 396 条判据 / shell 与 python **673** 个 if 条件
  （669 → 673：本批盘点脚本新增 3 个 `if` + 判据层新增 1 个段 trailer `if`）/
  断言实参 99 条）、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- **负控 8/8 真红**；累计 **884/884**。

### E.2bi 「判定不许被掏空成恒真」在 mac 侧**没有牙**（恒真探针的范围只盖一边）（批 CZ）

**① 起因（实测坐实 + 对照实验，不是推演）**

恒真探针（批 BG/BJ 立的「判据不许被掏空成恒真」）的 shell 扫描范围
**只有 `deepin/scripts/`**（`os.listdir(scripts)` ⇒ **单目录、只看顶层**）
⇒ ⇒ `macos/scripts/` 里那 **12 个判据脚本**上的 if 条件**从来没被查过**
⇒ ⇒ 而 mac 侧 `macos/build.sh` **确实会跑**它们（`contract-check.sh` /
`agent-check.sh` / `client-check.sh` / `catalog-check.sh` / `markdown-check.sh` …）
⇒ ⇒ 它们就是 **mac 平台的判定层**
⇒ ⇒ 那里出现恒真条件 ⇒ **mac 构建的判定静默通过** ⇒ 没人发现。

⚠⚠⚨ **实测坐实**（同一个变异，两个版本）：

| | 恒真探针的结论 |
|---|---|
| HEAD 版：在 mac 侧判据脚本里加一处**恒真条件** | ⚠⚠⚨ **rc=0**（「✓ 判据非恒真」照样打出来 ⇒ **假绿**）|
| 本批版：**同一个**变异 | **rc=1**（指名道姓报出 `macos/scripts/catalog-check.sh:<行号> if 的条件是恒真/恒假`）|

⚠⚠⚨ **顺带量出来的第二个洞**：`render-harness/run.sh` 在**子目录**里
⇒ `os.listdir`（顶层）**够不着** ⇒ 它上面的 4 处 if 条件也不被查。

⚠⚠⚨ **第三点（先量后改）**：用探针**自己的判定函数**把那 12 个脚本套一遍
⇒ **59 处 if 条件、0 处会被判红** ⇒ ⇒ 扩范围**不会**立刻假红
⇒ ⇒ 「扩范围」是**净收益**，不是「搬出一堆新债」。

**② 修法（只动判据层脚本 ⇒ 零产品代码改动）**

① 范围扩成**两个目录**：`sh_scope = (('shell', scripts, 'scripts'),
('macos_shell', mac_scripts, 'macos/scripts'))`
（mac 侧目录从**仓库根**算：`os.path.dirname(os.path.abspath(root))`
⇒ ⚠ 必须用**绝对路径** ⇒ `root` 可能是相对路径（`.`）⇒ `dirname('.')` 是**空串**
⇒ 目录会找错 ⇒ 诊断失真）；
② **递归**收 `.sh`（`os.walk`）⇒ 子目录里的 `render-harness/run.sh` 也被扫
⇒ ⚠ deepin 侧**没有**子目录 `.sh` ⇒ 计数不变（18）⇒ **两平台口径对称**；
③ **判定逻辑只有一份**：两个平台走**同一个循环、同一个函数**
⇒ 抽出 `scan_shell_file(path, label)`（⚠ 这样「**四个实扫点**」那条门
（恰好 4 处）**不用改** ⇒ 口径零漂移）；
④ 范围基线从 **3 行扩到 4 行**（判定层 / shell / macos_shell / python）
⇒ 值 **4 / 18 / 12 / 5**；
⑤ 成功消息把范围**拆开说**（`shell 30（deepin 18 + macos 12）`）⇒ 不许混在总数里。

**③ 落门 / 判据**

- **新增 6 条**（批 CZ 独立段）：
  ① 「mac 侧判据脚本目录**必须在**」（**整行锚定**
  ⇒ ⚠ 目录算错 ⇒ 扫不到 ⇒ 那批判据**不再被查**）
  ② 「shell 侧范围**必须同时含两个平台**」（**整行锚定**
  ⇒ ⚠ 两个目录写在**同一行** ⇒ 改一边就看得出来）
  ③ 「shell 侧判定**必须是共用函数**」（**整行锚定**
  ⇒ ⚠ 两边各写一遍 ⇒ **口径必然漂** ⇒ 批 BF/BG 纪律）
  ④ 「两个平台**必须真的走那个共用函数**」（**整行锚定**
  ⇒ ⚠ 定义了不调 ⇒ 等于没抽 ⇒ 批 CX 同款教训：「常量在、但扫描时不判」）
  ⑤ 「扫描范围**口径序**必须在」（**整行锚定**
  ⇒ ⚠ 行序 = 口径序 ⇒ 少一行 ⇒ 基线读不出对应关系 ⇒ fail closed）
  ⑥ 「范围基线里 **mac 侧的判据脚本数必须恰好是 12**」（**整行锚定**
  ⇒ ⚠ 这个数字**记两遍**（基线文件 + 本门）⇒ 改任意一边 ⇒ 另一边对不上 ⇒ **红**）
  ⇒ ⚠⚠⚨ 5 条 `arch_need_count` 的正则**从真实行现抽构造**
  ⇒ ⚠ **引号位置写 `.`**（批 BL 约定：门项的正则参数是**单引号**包裹
  ⇒ 正则里不能含字面单引号）；
- **原地替换 5 处**（批 BM 不增行）：
  ① 范围基线那条门 **3 → 4 行**（说明文字同步改）
  ② `ARCH_ANY_FAIL=1` **49 → 50** ③ `ARCH_FAIL=0` **50 → 51**
  ⇒ 段级 trailer **49 → 50** ④ 门项条数第三处 **1050 → 1056**；
- **同步**（批 CR 机制）：门项总数基线 **1050 → 1056** ⇒ ⚠⚠⚨ **三处同改**；
- 盘点登记册 **21 行不变**；豁免表 **14 条不变**；
  审计器锚定形态适用范围 **17 个脚本不变**；
  「**四个实扫点**」那条门**不用改**（共用函数 ⇒ 实扫点仍是 4 处）。

**④ 负控（行为级对照实验 + 门级逐条隔离 + 探针级 · 8 条）**

- **N1（行为级 · 对照实验）**：在 mac 侧判据脚本里加一处**恒真条件**
  ⇒ ⚠⚠⚨ **HEAD 版（整树 `git archive HEAD`）⇒ 探针 rc=0**（假绿）
  ⇒ **本批版 ⇒ rc=1** ⇒ ⇒ **两头都有证据**；
- **N2** 范围里去掉 mac 侧那一项 ⇒ **恰好 1 条**门红 **且**探针红（范围对不上）；
- **N3** mac 侧目录算错（相对路径 ⇒ 目录找不到）⇒ **恰好 1 条**门红 **且**探针红；
- **N4** 共用函数不被调（mac 侧不被扫）⇒ **恰好 1 条**门红
  ⇒ ⚠⚠⚨ **探针仍绿**（恒真条件看不见）⇒ ⇒ **假绿复现** ⇒ 门④抓住；
- **N5** 口径序被改（少一个口径）⇒ **恰好 1 条**门红 **且**探针红（fail closed）；
- **N6** 基线里 mac 侧那行被改小（12 → 11）⇒ **恰好 1 条**门红 **且**探针红；
- **N7** 共用函数的**定义形态**被改（多一个参数）⇒ **恰好 1 条**门红
  ⇒ ⚠ 探针**仍绿**（行为没变）⇒ ⇒ **只有门能抓住**（这条门有价值）；
- **N8** 递归下钻被摘（子目录里的脚本不再被扫）⇒ **探针红**
  （mac 侧少扫 1 个 ⇒ 11 ≠ 12）；
- ⇒ ⚠ 全部**按行号**整行改、变异后**语法过**（`ast.parse` 自证）、
  **变异自己先自证**、`restore()` **刷新 mtime**
  ⇒ 还原后与 harness 启动时的差异**逐字节相同**。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠ **`.py` 口径仍只看顶层**（`os.listdir`）⇒ 子目录里的 `.py` 不在范围
  ⇒ ⚠ 当前两个平台的判据脚本目录里**没有**子目录 `.py` ⇒ 影响实测为零
  ⇒ 将来真出现子目录 `.py` ⇒ 这条口径要跟着改；
- ⚠ **Swift 判据（`macos/Tests/*.swift`）仍不在探针范围**
  ⇒ 它的条件抽取口径与 shell/python 不同 ⇒ 要另立一条口径；
- ⚠ **「条件合法但恒真」静态分析抓不到**（如 `if [ "$a" = "$a" ]`）
  ⇒ 需变异测试才暴露 ⇒ 已知边界，本批不动；
- ⚠ **范围基线里的数字可以被协同改掉**（基线 + 门 ⑥ 两处一起改 ⇒ 全绿）
  ⇒ ⚠ 真正的防线是**门 ②**（两个目录写在同一行）⇒ 范围被改窄 ⇒ 门红；
- ⚠ **恒真探针由 `ci.sh` 第 15 步跑**（不在接线门里）⇒ 探针自身的红
  要等 CI 才看得见 ⇒ 接线门只保证「探针的**口径**没被改弱」；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1050 → 1056**（+6）、执行次数 **1053 → 1059**（+6）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1050 → 1056**（**三处**同步）；
- 段级 trailer **49 → 50**；整行 `exit 1`（判据层）**3 不变**；
  `ARCH_ANY_FAIL=1` = **50**；`ARCH_FAIL=0` = **51**；
- ⚠ **恒真探针**：判定层 396 条判据不变、
  shell 与 python **673 → 744** 个 if 条件（**+71** = mac 侧 59 处顶层
  + `render-harness` 4 处 + heredoc 内嵌 python 7 处 + 探针自身新增 1 处）、
  断言实参 99 条不变；
  ⚠ **扫描范围**：判定层 4 / shell **18 → 30**（deepin 18 + macos **12**）/
  python 5；范围基线 **3 行 → 4 行**（4 / 18 / **12** / 5）；
- 盘点 **21 组 / 72 处不变**；豁免表 **14 条不变**；
- 接线门 **1059** 项全绿、审计器硬门与报告模式 **rc=0**（门项 1056/1056 对基线）、
  恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- **负控 8/8 真红**；累计 **892/892**。

### E.2bj 「恒真」判定不许把 shell 的**惯用无限循环**当成判据被掏空（批 DA）

**① 起因（实测坐实 + 反向对照实验，不是推演）**

恒真探针（批 BF/BJ 立的「判据不许被掏空成恒真」）把 shell 条件的
「恒真/恒假」判定**一刀切**地套在**所有**条件上
⇒ `while :; do` / `while true; do`（**shell 的惯用无限循环**）
也被报成「if 的条件是恒真/恒假」⇒ **CI 假红**。

⚠⚠⚨ **实测坐实（同一个变异，两个版本）**：

| | 恒真探针的结论 |
|---|---|
| HEAD 版：在**范围内**的判据脚本里加一处 `while :; do` | ⚠⚠⚨ **rc=1**（报 `scripts/ci-orphan-probe.sh:39 if 的条件是恒真/恒假：:` ⇒ **假红**）|
| 本批版：**同一个**变异 | **rc=0**（「✓ 判据非恒真」照样打出来 ⇒ 惯用无限循环被放过）|

⚠⚠⚨ **为什么「假红」比「假绿」更坏**（批 BS 纪律）：假绿是承诺**悄悄消失**；
假红是**逼人把承诺改弱** —— 人为了让 CI 变绿，会把 `while :; do` 改成某种
怪写法来「求绿」⇒ 判据层被迫写出**更糟**的代码。

⚠ 全仓唯一的 `while :; do` 现在在 `macos/build.sh:236`（**不在**探针范围内）
⇒ 假红目前是**潜在**的 ⇒ 但只要有人往**范围内**脚本里写这个极常见惯用法
就会**当场假红** ⇒ 属于「迟早会踩」的坑 ⇒ 本批先收口。

⚠⚠⚨ **反向护栏也要在**：`if :` / `if true` / `if false` 是**真掏空**
（`false` ⇒ 体永不执行）⇒ **仍要判红** ⇒ 本批**不许**变成「整体放水」。

**② 修法（只动判据层脚本 ⇒ 零产品代码改动）**

① `shell_if_conds()` 返回值带上**种类**（`if` / `while`）
   ⇒ 判定处才知道该不该判恒真；
② 恒真/恒假判定**只对 `if`/`elif`** 生效 ⇒ `while` / `until` 放过；
③ 判定抽成 `shell_tautology_reason(kind, cond)` ⇒ **自检与实扫同一条路径**
   （批 BF 纪律：自检与实扫分家 ⇒ 自检测的不是真判定 ⇒ 假的保证）；
④ 扫描拆出 `scan_shell_text(text, label)`（**文本入口**）
   ⇒ 自检能拿合成样例走**同一条**扫描 ⇒ 「while 不判 / if 判」这条区分
   由**探针自己**证明有牙（不是只靠门钉形态）；
⑤ `scan_shell_file(path, label)` 变成**薄封装**（读文件 + 交给 `scan_shell_text`）
   ⇒ ⚠ 批 CZ 那两条门（共用函数 / 两个平台真的走它）**不用改**；
⑥ 成功消息改成「**746 个条件**都非恒真（⚠ while/until 的惯用无限循环按批 DA
   规矩不判恒真）」⇒ 说明文字必须与实际行为一致（批 BA/BB 纪律）。

**③ 落门 / 判据**

- **新增 18 条**（批 DA 独立段，全部**整行锚定**）：
  ① 「shell 侧恒真判定**入口**必须在」（带左括号 ⇒ 改名躲不过）；
  ② 「恒真判定**只对 `if`/`elif`** 生效」（⚠ 核心 ⇒ 删掉 ⇒ 假红回来）；
  ③ 「实扫**必须走那个统一判定入口**」；
  ④ 「**自检**也必须走同一个判定函数」；
  ⑤～⑧ 「条件提取必须认出 `if`/`elif`/`while`/`until` 关键字」（四个**各一条**
  ⇒ 漏一个 ⇒ 那一类条件**根本不被提取** ⇒ 静默失守）；
  ⑨ 「**种类映射**必须在」（⚠ 写反 ⇒ 假红或假绿）；
  ⑩ 「提取时**必须把种类一起带出来**」；
  ⑪ 「实扫**必须解包出种类**」；
  ⑫ 「shell 侧扫描函数（**文本入口**）必须在」；
  ⑬ 「文件入口**必须真的交给那个扫描函数**」（⚠ 定义了不调 ⇒ 假的保证）；
  ⑭～⑱ 「自检样例」四条（`if` 家族该判红的 2 条 + `while` 家族**不该**判红的
  2 条 + 判定级正反各 1 条）⇒ ⚠ **只测一边 ⇒ 判反了也能过**（批 BF 纪律）。
- **原地替换 5 处**（批 BM 不增行）：`ARCH_ANY_FAIL=1` **50 → 51**、
  `ARCH_FAIL=0` **51 → 52**、门项条数第三处 **1056 → 1074**，
  以及两条说明文字（说明里的数字必须跟着改 ⇒ 不然门在骗人）。
- **同步**：门项总数基线 **1056 → 1074** ⇒ ⚠⚠⚨ **三处同改**
  （基线文件 / 审计器常量 / 门 ③ 里的数字）。

**④ 负控（行为级反向对照 + 门级逐条隔离 + 自检有牙 · 12 条）**

- **N1（反向对照 · 核心）**：只注入 `while :; do`
  ⇒ ⚠⚠⚨ **HEAD 版探针 rc=1（假红）** ⇒ **本批版 rc=0** ⇒ ⇒ 坐实「假红被收掉」
  且**不是**靠「整体不判」实现的；
- **N2** 只注入 `if :` ⇒ 本批版**仍红**（真掏空不许放过）；
- **N3** 只注入 `if true` ⇒ 本批版**仍红**；
- **N4** 只注入 `while true` ⇒ 本批版**绿**；
- **N5** 只注入 `if false` ⇒ 本批版**仍红**（恒假也是掏空：体永不执行）；
- **N6** 放过 `while` 的同时**范围基线仍被核对**（不许借「放水」把范围也放掉）；
- **N7** 种类映射**写反** ⇒ **恰好 1 条**门红 **且**指名道姓；
- **N8** 删掉「恒真只对 if 生效」的闸门 ⇒ **恰好 1 条**门红；
- **N9** 提取时**不带种类** ⇒ **恰好 1 条**门红；
- **N10** 删掉 `until` 关键字 ⇒ **恰好 1 条**门红；
- **N11** 把自检样例的期望改错 ⇒ **探针自检当场红**（⇒ 自检不是摆设）；
- **N12** 还原后工作区与 harness 启动时的 `git diff` **逐字节相同**（洁净度）。
- ⇒ 全部**按行号**整行改、变异后**语法过**、**变异自己先自证**、`restore()` **刷新 mtime**。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠ **`until true`（体永不执行）也被放过**（本批不判）
  ⇒ 「while / until 的体永不执行 ⇒ 断言永不跑」这条（批 BJ ③）仍靠**人读**兜着；
- ⚠ **捷径判定（`|| true` / `&& false`）对 `while` 仍然生效**
  ⇒ `while cmd || true` 其实是**死循环**（不是掏空）⇒ 本批**没收**这一档；
- ⚠ 恒真探针的 **Swift 判据**仍不在范围（批 CZ 遗留）；
- ⚠ 「条件合法但恒真」静态分析抓不到 ⇒ 需变异测试 ⇒ 本批不动；
- ⚠ 恒真探针由 `ci.sh` 第 15 步跑（不在接线门里）⇒ 探针自身的红要等 CI 才看得见；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1056 → 1074**（+18）、执行次数 **1059 → 1077**（+18）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1056 → 1074**（**三处**同步）；
- 段级 trailer **50 → 51**；整行 `exit 1`（判据层）**3 不变**；
  `ARCH_ANY_FAIL=1` = **51**；`ARCH_FAIL=0` = **52**；
- ⚠ **恒真探针**：判定层 396 条判据不变、
  shell 与 python **744 → 747** 个条件（**+3** = 探针源码自身新增 2 处 `if`
  + 批 DA 段的段末 trailer 在 `ci-wiring.sh` 里新增 1 处 `if`
  ⇒ ⚠ **探针会数到自己的 CI 接线文件** ⇒ 这是**自指**，知情取舍）、
  断言实参 99 条不变；
  ⚠ **扫描范围不变**：判定层 4 / shell 30（deepin 18 + macos 12）/ python 5；
  范围基线 **4 行不变**（4 / 18 / 12 / 5）；
- 盘点 **21 组 / 72 处不变**；豁免表 **14 条不变**；
- 接线门 **1077** 项全绿、审计器硬门与报告模式 **rc=0**（门项 1074/1074 对基线）、
  恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- **负控 12/12 真红**；累计 **904/904**。


### E.2bk 恒真探针的 shell 范围不许只盖「两个平台的判据脚本目录」（批 DB）

**① 起因（实测坐实 + 反向对照实验，不是推演）**

恒真探针（批 BF 立的）的 shell 范围 = **两个平台的判据脚本目录**
（`deepin/scripts/` + `macos/scripts/`）⇒ 仓内自有 .sh 的**其余角落**
**从来没被查过**：

| 目录 | .sh 数 | if 条件 | 说明 |
|---|---|---|---|
| `macos/build.sh` | 1 | 38 | **被 4 条门项盯着**（批 AJ 起：引擎 URL / fetch-engine.sh / runtime lib 拷贝 / bin 拷贝）⇒ **门项覆盖面比探针覆盖面宽** |
| `assets/icon/check-icon.sh` | 1 | 10 | 图标校验脚本（判据脚本） |
| `linux/scripts/*.sh` | 9 | 53 | 含 `ai-e2e.sh` / `ci-local.sh` 这类判据脚本 |
| **合计** | **11** | **101** | |

⇒ **同一族洞**（批 CY 的题）：**纪律覆盖面不许比门项覆盖面窄**。

⚠⚠⚨ **实测坐实（同一个注入，两棵树各自自洽 + 各自的探针）**：

| | 恒真探针的结论 |
|---|---|
| 旧版（批 DA，`git archive HEAD` 整树）：在 `macos/build.sh` 里加一处恒真条件 | ⚠⚠⚨ **rc=0**（「✓ 判据非恒真」照样打出来 ⇒ **假绿**）|
| 本批版：**同一个**注入 | **rc=1**（指名道姓报出 `macos/build.sh:<行号> if 的条件是恒真/恒假：true`）|

⚠⚠⚨ **前置依赖（批 DA 收了它，本批才敢扩）**：
用**批 DA 之前**的口径量候选范围 ⇒ **160 处 if 条件、1 处会被判红**
⇒ `macos/build.sh:236` 的 `while :; do`（**惯用无限循环**）
⇒ ⚠⚠⚨ **不先修假红就扩范围 ⇒ 当场假红**（批 BS：假红逼人把承诺改弱）；
用**批 DA 之后**的口径量同一范围 ⇒ **0 处判红** ⇒ **扩范围是净收益**。

**② 修法（只动判据层脚本 ⇒ 零产品代码改动）**

① 范围从**两个目录**扩成**四个口径**：`deepin/scripts`（18）、
   `macos/` **整棵树**（13 ⇒ **含 build.sh**）、`assets/`（1）、`linux/scripts/`（9）；
② ⚠ **显式目录清单，不靠排除表** ⇒ `linux/vendor`（第三方）**不进范围**；
③ 四个口径**写在同一行**（`sh_scope`）⇒ 改一边就看得出来（沿用批 CZ 的做法）；
④ 四个口径**走同一个循环、同一个判定函数** ⇒ 口径零漂移；
⑤ **存在性检查**覆盖四个目录（目录不存在 ⇒ 明确判红 ⇒ fail closed）；
⑥ 对拍字典（`got_scope`）覆盖四个口径 ⇒ 漏一个 ⇒ 范围检查漏一整片；
⑦ 范围基线从 **4 行扩到 6 行**（判定层 / deepin / macos / assets / linux / python）
   ⇒ 值 **4 / 18 / 13 / 1 / 9 / 5**；
⑧ ⚠ **每个基线数字都记两遍**（基线文件 + 门）⇒ 改任意一边 ⇒ 另一边对不上 ⇒ **红**
   （原先只有基线文件记着 ⇒ 「改范围 + 改基线」这一单侧协同编辑就能收窄范围）；
⑨ 成功消息把范围**拆开说**（`shell 41（deepin 18 + macos 13 + assets 1 + linux 9）`）。

**③ 落门 / 判据**

- **新增 13 条**（批 DB 独立段，全部**整行锚定**）：
  ① `mac_dir` 定义行 ② `assets_dir` 定义行 ③ `linux_scripts` 定义行
  ④ **存在性检查**那行（四个目录都在 ⇒ fail closed）
  ⑤ **遍历循环**那行（范围常量真的被遍历 ⇒ 批 CX 同款教训）
  ⑥ **计数字典**那行（四个口径的键都在）
  ⑦⑧ 对拍字典里 `assets_shell` / `linux_shell` 两行（漏一个 ⇒ 漏一整片）
  ⑨～⑬ 范围基线的**五个数字各记两遍**（判定层 4 / deepin 18 / assets 1 / linux 9 / python 5）
- **原地替换 5 处**（批 BM 不增行）：批 CZ 的「mac 侧目录定义」门（→ 仓库根行）、
  「`sh_scope`」门（→ 四口径）、「`SCOPE_KEYS`」门（→ 六口径）、
  「基线里 mac 侧 12」门（→ 13）、批 BP 的「基线 4 行」门（→ 6 行）；
  ⇒ 五处的**说明文字**同步改（说明里的数字/形态必须与实际一致 ⇒ 不然门在骗人）；
- **同步**：门项总数基线 **1074 → 1087** ⇒ ⚠⚠⚨ **三处同改**；
  段级 trailer **51 → 52**。

**④ 负控（行为级反向对照 + 门级逐条隔离 · 12 条）**

- **A 组 · 行为级（两棵树各自自洽 + 各自的探针 + 同一处注入）**：
  - **A1** `macos/build.sh` 注入恒真条件 ⇒ **旧版 rc=0（假绿）/ 本批版 rc=1**；
  - **A2** `assets/icon/check-icon.sh` 同款 ⇒ 旧版绿 / 本批版红；
  - **A3** `linux/scripts/ci-local.sh` 同款 ⇒ 旧版绿 / 本批版红；
  - **A4** `macos/build.sh` 注入 `while :; do` ⇒ 旧版**看不见**（不在范围）/
    本批版**绿**（惯用无限循环不判 ⇒ 批 DA 的口径在扩范围后仍然生效）；
  ⇒ ⚠ **为什么用两棵树**：旧版探针的**范围基线是 4 行**、新树是 6 行
    ⇒ 旧探针在新树上会因「基线行数对不上」而红 ⇒ **红因指错** ⇒ 必须在各自自洽的树上比。
- **B 组 · 门级逐条隔离（变异探针源码 ⇒ 接线门必须红且指名道姓）**：
  - **B1** 范围里去掉 `assets_shell` ⇒ 门红 **且** 探针红（数到的口径与基线不符）；
  - **B2** 遍历循环改成只走第一项 ⇒ 门红 **且** 探针红；
  - **B3** 存在性检查里去掉 linux 目录 ⇒ **门红 而探针仍绿**
    ⇒ ⇒ 这条门守的是「范围目录不存在 ⇒ 必须判红」这条 **fail closed** 语义
    ⇒ **只有门能抓住**（探针抓不住）；
  - **B4** 对拍字典里 `assets_shell` 改成常量 0 ⇒ 门红 **且** 探针红；
  - **B5** `mac_dir` 被改窄回 `macos/scripts` ⇒ 门红 **且** 探针红；
  - **B6/B7** 范围基线里 assets（1→2）/ linux（9→8）那行被改小 ⇒ 门红 **且** 探针红
    ⇒ ⇒ 「改范围 + 改基线」这条协同编辑**被门堵住**；
- **C1** 还原后工作区与 harness 启动时的 `git diff` **逐字节相同**（洁净度）。
- ⇒ 全部**按行号**整行改、变异后**语法过**、**变异自己先自证**、`restore()` **刷新 mtime**。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠ **`got_scope` 少一个键 ⇒ 探针崩（traceback）而不是「判红」**
  ⇒ 红是真的红，但**诊断是指纹不是解释**（批 AZ 纪律的短板）⇒ 由门 ⑦⑧ 兜住；
- ⚠ **`linux/vendor`（第三方 CangjieSDL）不在范围** ⇒ 用**显式目录清单**⇒
  将来 `linux/vendor` 里若长出 .sh，**不会**被自动查；
- ⚠ **`.py` 口径仍只看 `deepin/scripts/` 顶层**（批 CZ 遗留）
  ⇒ `linux/scripts/bmp2png.py` 不在范围；
- ⚠ **Swift 判据**仍不在探针范围（批 CZ 遗留）；
- ⚠ 恒真探针由 `ci.sh` 第 15 步跑（不在接线门里）⇒ 探针自身的红要等 CI 才看得见；
- ⚠ **影响面实测为零**（只动判据层脚本与文档 ⇒ 零产品代码改动 ⇒ 快照零变化）。

**⑥ 数字**

- 门项物理行数 **1074 → 1087**（+13）、执行次数 **1077 → 1090**（+13）；
- 门项总数基线 `ci-wiring-gates.baseline` = **1074 → 1087**（**三处**同步）；
- 段级 trailer **51 → 52**；整行 `exit 1`（判据层）**3 不变**；
  `ARCH_ANY_FAIL=1` = **52**；`ARCH_FAIL=0` = **53**；
- ⚠ **恒真探针**：判定层 396 条判据不变、
  shell 与 python **747 → 849** 个条件（**+102** = 新纳入的 11 个 .sh 的 101 处
  + 批 DB 段的段末 trailer 在 `ci-wiring.sh` 里新增 1 处 `if`
  ⇒ ⚠ **探针会数到自己的 CI 接线文件** ⇒ **自指**，知情取舍）、
  断言实参 99 条不变；
  ⚠ **扫描范围**：判定层 4 / shell **30 → 41**（deepin 18 + macos **13** +
  assets **1** + linux **9**）/ python 5；范围基线 **4 行 → 6 行**（4 / 18 / **13** / 1 / 9 / 5）；
- 盘点 **21 组 / 72 处不变**；豁免表 **14 条不变**；
- 接线门 **1090** 项全绿、审计器硬门与报告模式 **rc=0**（门项 1087/1087 对基线）、
  恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- **负控 12/12 真红**；累计 **916/916**。


### E.2bl Swift 判据（`macos/Tests/*.swift`）也不许被掏空（批 DC）

**① 起因（实测坐实 + 反向对照实验，不是推演）**

恒真探针（批 BF 立的）查的是 **C++ 判定层**（`check(…)` 的第三个实参）
+ shell + python 三个口径 ⇒ 而 **mac 侧的判据脚本是 Swift**
（`macos/Tests/*/main.swift`：5 个文件、9265 行）⇒ 它们的断言形态是

```swift
check("标签") {
    let x = …
    guard let out = … else { throw fail("…") }
    return "说明"
}
```

⇒ **判据藏在闭包体里** ⇒ C++ 侧那条「第三个实参」口径**够不着**
⇒ ⚠⚠⚨ **那 469 条断言一条都没被查过**（假绿）⇒ 而 mac 构建**确实会跑**它们
⇒ 它们就是 **mac 平台的判定层**。

⚠⚠⚨ **先量后改**（免得「加规则」当场假红）：

| 口径 | 数量 | 说明 |
|---|---|---|
| `check(` 出现 | 474 次 | − 5 个 `func check` 定义 ⇒ **469 条调用** |
| if 条件 | **144 处** | 含 `else if`（它也是条件） |
| 闭包里**没有失败路径** | **0 条** | ⇒ 加规则**不会**立刻假红 ⇒ 净收益 |
| 闭包里**只有 `try?`** | **0 条** | ⇒ `try?`（吞错误）**不算**失败路径 |
| 恒真/恒假条件 | **0 处** | ⇒ 同上 |

⚠⚠⚨ **实测坐实（同一个注入，两棵树各自自洽 + 各自的探针）**：
旧版（批 DB，`git archive HEAD` **整树**）在 `macos/Tests/AgentCheck/main.swift`
里加一条**闭包里没有失败路径**的 `check` ⇒ 探针 **rc=0**（打印「✓ 判据非恒真」
⇒ **假绿**）⇒ 本批版**同一个**注入 ⇒ **rc=1**（指名道姓报出
`macos/Tests/AgentCheck/main.swift:<行号> 断言闭包里没有任何失败路径（throw / try）…`）。

**② 修法（只动判据层 ⇒ 零产品代码改动）**

1. **新增 Swift 口径**：`swift_dir = <仓库根>/macos/Tests` ⇒ 递归收 `.swift`
   ⇒ **5 个文件**进范围；存在性检查（fail closed）+ 对拍字典 + 范围基线三处都覆盖它。
2. **两种掏空形态**（复用同一份判定，不另写一遍）：
   - ① **闭包里没有失败路径** ⇒ 这条断言**永远不会失败** ⇒ 等价于 C++ 侧的
     `check(log, "…", true)` ⇒ 掏空。
     失败路径关键字 = `throw` / `try` / `fatalError` / `precondition` / `assert`；
     ⚠ **`try?` 不算**（它把错误**吞掉** ⇒ 不会失败 ⇒ 实测仓里有 15 处 `try?`
     ⇒ 粗口径会把「吞错误」误当成「会失败」⇒ **假绿**）⇒ 用 `(?!\?)` 排除。
   - ② **`if` 条件恒真/恒假**或**带捷径**（`|| true`）⇒ 体总执行 / 永不执行
     ⇒ 里面的判据形同虚设 ⇒ **复用 `tautology_reason`**（判定只有一份 ⇒ 口径零漂移）。
3. **扫描拆成文本入口 + 文件入口**（批 DA 的同款做法）：`scan_swift_text(text, label)`
   + 薄封装 `scan_swift_file(path, label)` ⇒ 自检能拿合成样例走**同一条**扫描路径
   ⇒ 「Swift 侧也有牙」由**探针自己**证明。
4. **断言闭包提取靠括号/花括号配平**（`_swift_balance`）⇒ 不用正则猜闭包边界
   ⇒ 闭包里有嵌套闭包与字符串字面量 ⇒ 正则会抽错。
5. **注释/字符串剥离是状态机**（`strip_swift`）⇒ 源码里有 `"https://…"` ⇒ 正则分不清
   `//` 是注释还是 URL 的一部分；⚠ **`"""` 多行字符串单独一档**
   （⚠⚠⚨ 实测踩到：当成普通字符串 ⇒ 引号状态机跑偏 ⇒ 闭包体被抽错 ⇒ **假红**）；
   ⚠ `blank_strings=True` ⇒ 关键字**只从代码里认** ⇒ 否则一句说明文字
   （`"这里没有 try"`）就能冒充「有失败路径」。
6. **成功消息拆开说**（判定层 / shell+python / 断言实参 / **Swift 断言 + if 条件** /
   扫描范围各一段）⇒ 说明文字必须与实际行为一致（批 BA/BB）。

**③ 顺带收掉的第二个洞：范围基线改成「带口径名」格式**

原范围基线是**纯数字**、靠**行序**对应口径 ⇒ ⚠ 两个口径的文件数**相同**时
（`python 5` / `swift 5`）门就**钉不住是哪个** ⇒ 「每个口径都记两遍」这条纪律
**立不住** ⇒ 改成每行 `<口径名> <数字>`（`judgement 4` / `shell 18` /
`macos_shell 13` / `assets_shell 1` / `linux_shell 9` / `python 5` / `swift 5`）
⇒ 每个口径都能被**单独**钉住；且 **口径名 / 个数 / 顺序**必须与 `SCOPE_KEYS`
完全一致 ⇒ 否则 `read_scope_baseline()` **返回 None** ⇒ 探针当场红
（**fail closed** ⇒ 不许「读不到就当没有基线」）。

**④ 落门 / 判据**

- **新增 20 条**（批 DC 独立段，全部整行锚定）：`swift_dir` 定义 / 失败路径关键字表
  的**定义行**与**内容行** / 注释剥离器 / 括号配平器 / 断言闭包提取器 /
  if 条件提取器 / 掏空判定入口 / 判定本体 / 扫描函数（文本入口）/ 扫描函数（文件入口）/
  真的走那个扫描函数 / 文件计数 / 对拍字典里的 Swift 口径 / 范围基线里的 `swift 5` /
  基线解析 fail closed / `SCOPE_KEYS` 七口径 / 存在性检查覆盖 `swift_dir` /
  范围基线**带名格式**（7 行）/ 基线里**每个口径各一条**（7 条）/ 自检样例 5 条
  ⇒ ⚠ **只测一边 ⇒ 判反了也能过**（批 BF 纪律）。
- **原地替换 9 处**（批 BM 不增行）：基线格式门（`^[0-9]+$`6 → `^[a-z_]+ [0-9]+$`7）/
  六个逐值门 → 六个**带名**逐值门 / `SCOPE_KEYS` 门 → 7 键 / 存在性检查 tuple → 含
  `swift_dir` / `why = tautology_reason(cond)` 调用点 1 → **2**（C++ 侧 + Swift 侧）
  ⇒ 判定仍是一份。
- ⚠⚠⚨ **顺带修了 4 条「说明文字与实际行为不一致」的门**（批 BB 纪律 ⇒ **本批自己**踩到）：
  「基线恰好 4 行纯数字」（实际 7 行带名）/「口径四个」（实际 7 个）/
  「mac 侧恰好是 12」（实际 13）/「四个范围目录」（实际六个目录）⇒ **原地替换**
  ⇒ **不增行** ⇒ 门项条数不变。
- **同步**：门项总数基线 **1087 → 1107** ⇒ ⚠⚠⚨ **三处同改**（基线文件 /
  审计器常量 / 门项里那个数字）；段级 trailer **52 → 53**。

**⑤ 负控 26/26 真红**

- **A 组 · 行为级（两棵树各自自洽 + 各自的探针 + 同一处注入）**：
  A1 闭包里没有失败路径 ⇒ 旧版 rc=0 假绿 / 本批版 rc=1；
  A2 `if true` ⇒ 同款；A3 `if false` ⇒ 同款；A4 `if x || true`（捷径）⇒ 同款；
  A5 闭包里**只有 `try?`** ⇒ 同款（⇒ `try?` 不算失败路径这条规矩**真的生效**）；
  A6 闭包里有**真的失败路径** ⇒ **两边都绿**（反向护栏 ⇒ 不许变成「整体放水」）。
  ⇒ ⚠ **为什么用两棵树**：旧版探针的**范围基线是 6 行纯数字**、新树是 7 行带名
  ⇒ 旧探针在新树上会因「基线对不上」而红 ⇒ **红因指错** ⇒ 必须在各自自洽的树上比。
- **B 组 · 门级逐条隔离（变异探针源码 ⇒ 接线门必须红）**：
  B1 关键字表删 `fatalError` ⇒ 门红 **而探针仍绿** ⇒ ⇒ **只有门能抓住**
  （删 `fatalError` 不改变任何现有断言的判定 ⇒ 探针看不出来）；
  B2 去掉 `(?!\?)` 排除 ⇒ 同款；B3 关键字表定义行改名 ⇒ 门红 **且**探针红（崩）；
  B4/B5/B6 三个提取/扫描函数改名 ⇒ 门红 **且**探针红（崩）；
  B7 `swift_dir` 被移出存在性检查 ⇒ 门红 **而探针仍绿** ⇒ **只有门能抓住**；
  B8 文件计数被摘掉 ⇒ 门红 **且**探针红（范围对不上）；
  B9 扫描函数没被调用 ⇒ 门红 **且**探针红（崩）；
  B10 对拍字典里 Swift 口径改成常量 ⇒ 门红 **且**探针红；
  B11 判定本体被掏空成恒真 ⇒ 门红 **且**探针**自检**红。
- **B 组续 · 自检样例被掏空**：B12「该判红」那档被改坏 ⇒ 门红 **且**探针自检红；
  B13/B14 端到端样例各被删掉一档 ⇒ 门红 **而探针仍绿** ⇒ ⇒ **只有门能抓住**
  （探针自己看不出来 ⇒ 靠门）。
- **B 组续二 · 范围基线被改**：B15 `swift 5` → `swift 4` ⇒ 门红 **且**探针红；
  B16 格式退回纯数字 ⇒ 门红 **且**探针红（fail closed）；
  B17 口径名写错（`swiftt 5`）⇒ 门红 **且**探针红。
- **C1** 还原后与 harness 启动时的 `git diff` **逐字节相同**（洁净度）。
  ⇒ 全部**按行号**整行改、变异后**语法过**、**变异自己先自证**、`restore()` **刷新 mtime**。

**⑥ 已知边界（如实记着，不粉饰）**

- ⚠ **恒真探针由 `ci.sh` 第 15 步跑**（不在接线门里）⇒ 接线门只保证「探针的
  **口径**没被改弱」；探针自身的红要等 CI 才看得见。
- ⚠ **Swift 侧没有「捷径」单独入口**：Swift 的 if 条件走的是 `tautology_reason`
  （恒真/纯字面量 + 捷径两档合一）⇒ 与 C++ / shell 侧**同一份判定** ⇒ 口径零漂移，
  但也意味着 Swift 侧**没有**第三档独立口径。
- ⚠ **`try?` 只能靠关键字排除**：若将来 Swift 侧引入别的吞错误写法
  （`try` + `catch` 忽略），本口径**认不出来** ⇒ 需人读兜着。
- ⚠ **`check` 必须**在行首**才算调用**：若将来 Swift 侧出现缩进调用或别名调用，
  本口径**数不到** ⇒ 范围基线的 469 与实际不符 ⇒ 探针**当场红**（fail closed）
  ⇒ 不会静默漏掉，但会**误报**。
- ⚠ **Swift 判据的 `if` 条件**只看条件本身**：条件里的**被测标识符**没有被要求
  （Swift 侧没有 C++ 那种「条件必须含被测标识符」的约定）⇒ 「`if x`」这种
  恒不成立的条件**抓不到** ⇒ 需变异测试才暴露 ⇒ 明确不做。
- ⚠ **`.py` 口径仍只看 `deepin/scripts/` 顶层**（批 CZ 遗留）
  ⇒ `linux/scripts/bmp2png.py` 不在范围。
- ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）。

**数字**

- 门项物理行数 **1087 → 1107**（**+20**）、执行次数 **1090 → 1110**（+20）；
- 门项总数基线 **1087 → 1107**（**三处**同步）；
- 段级 trailer **52 → 53**；整行 `exit 1`（判据层）**3 不变**；
  `ARCH_ANY_FAIL=1` = **53**、`ARCH_FAIL=0` = **54**；
- ⚠ **恒真探针**：判定层 396 条判据不变、shell 与 python **849 → 875** 个条件
  （**+26** = 探针源码自身新增的 Swift 解析函数里的 `if`/`elif` + 批 DC 段的段末
  trailer 在 `ci-wiring.sh` 里新增 1 处 `if` ⇒ ⚠ **探针会数到自己的 CI 接线文件**
  ⇒ **自指**，知情取舍）、断言实参 99 条不变；
  ⚠ **Swift 侧**：**469 条断言**（闭包都有失败路径）+ **144 处 if 条件**都非恒真；
- ⚠ **扫描范围**：判定层 4 / shell 41（deepin 18 + macos 13 + assets 1 + linux 9）/
  python 5 / **swift 5**；范围基线 **6 行 → 7 行**（4 / 18 / 13 / 1 / 9 / 5 / **5**，
  且**每行带口径名**）；
- 盘点 **21 组 / 72 处不变**；豁免表 **14 条不变**；
- 接线门 **1110** 项全绿、审计器硬门与报告模式 **rc=0**（门项 1107/1107 对基线）、
  恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- **负控 26/26 真红**；累计 **916 → 942/942**。


### E.2bm 判据层的「判定口径表」不许被悄悄改弱（批 DD）

**① 起因（实测坐实 + 完整枚举，不是推演）**

恒真探针（批 BF 立的）里有**六张「判定口径表」**——它们决定了
「什么算恒真 / 什么算捷径 / 什么算没有失败路径」：

| 表 | 位置 | 决定了什么 | 有效档数 |
|---|---|---|---|
| `KEYWORDS` | 探针第 41 行 | 哪些词**不算**标识符（抽掉它们后不剩标识符 ⇒ 判恒真） | 27 |
| `SHORTCUT` | 第 59 行 | 哪些写法算「恒真捷径」（`\|\| true` / `&& false` / `or True` …） | 10 |
| `SH_CONST` | 第 65 行 | shell 侧的恒真字面量（`true` / `false` / `:`） | 3 |
| `PY_CONST_IF` | 第 69 行 | python 侧的恒真条件（`if True:` / `if False:` / `if 1:` / `if 0:`） | 4 |
| `LITERAL_CHAR` | 第 114 行 | ERE 里哪些字符算「字面字符」（没有 ⇒ 匹配一切 ⇒ 恒真） | 14 |
| `SWIFT_FAIL_RE` | 第 748 行 | Swift 闭包里哪些关键字算「失败路径」 | 5 |

⇒ ⚠⚠⚨ **它们的内容被削弱 ⇒ 没有任何东西会红**：
实测把每张表的**每一个分支**逐个删掉（**78 次削弱**）⇒
**接线门 / 探针 / 审计器「三样全绿」= 削弱没人发现 = 承诺悄悄变弱 ⇒ 53 个洞**。

| 表 | 削弱后**无人发现** | 已被自检抓住 |
|---|---|---|
| `KEYWORDS` | **25** | 2（`true` / `false`） |
| `LITERAL_CHAR` | **22** | 5 |
| `PY_CONST_IF` | **4** | 0 |
| `SHORTCUT` | **2**（小写 `or true` / 小写 `and false`） | 8 |
| `SH_CONST` | 0 | 3 |
| `SWIFT_FAIL_RE` | 0 | 5（⚠ 批 DC 的内容门 **+** 探针自检**两处**都抓住 ⇒ 三样全红） |

⇒ **洞集中在「自检没覆盖到的档」** ⇒ 修法也就清楚了。

**② 修法（两腿，互不依赖 ⇒ 改一处必红）**

- **腿 1 · 内容级门**：五张表的**每一行**整行锚定（**12 条**）
  ⇒ 改一行 ⇒ 那条门红（指名道姓说哪一行）。
  ⚠ **正则一律从真实行现抽**（批 CX 纪律）⇒ 不手抄 ⇒ 零漂移。
- **腿 2 · 补自检**（在探针里 ⇒ 批 DA·定「判定逻辑不许被掏空 ⇒ 探针自己证明有牙」）：
  **63 个有效档全部有自检覆盖** ⇒ 改口径 ⇒ 探针自检红。
  - **关键手法：一条样例覆盖一整张表**
    · `KEYWORDS` 的 **27 个词** ⇒ **一条** `cond` 样例把它们全列出来
      ⇒ 删掉其中任何一个 ⇒ 它就变成「有意义的标识符」⇒ 不再判恒真 ⇒ 自检红；
    · `LITERAL_CHAR` 的 **14 个元字符** ⇒ **一条** `assert_arg` 样例把它们全列出来
      ⇒ 删掉其中任何一个 ⇒ 它就变成「字面字符」⇒ 那条 ERE 不再是「匹配一切」⇒ 自检红；
  - ⚠ **反过来：一条里混多档就盖不住**（删掉一档另一档仍命中 ⇒ 照样绿）
    ⇒ `SHORTCUT` 的 10 档、`PY_CONST_IF` 的 4 档 ⇒ **每档单独一条**
    ⇒ `PY_CONST_IF` 因此**新增了一个自检类别**（`py_const_if`，走**同一条**判定路径
    ⇒ 与实扫同一个正则 ⇒ 口径零漂移）。

**③ 落门 / 判据**

- **新增 15 条**（批 DD 独立段，全部整行锚定）：
  **12 条内容级门**（`KEYWORDS` 5 行 + `SHORTCUT` 4 行 + `SH_CONST` 1 +
  `PY_CONST_IF` 1 + `LITERAL_CHAR` 1）+
  **3 条自检门**（`py_const_if` 分支必须在 / 该类别「该判红」4 条 / 「不该判红」1 条）。
- **原地替换 3 处**（批 BM 不增行）：`shortcut`「该判为捷径」**8 → 10** /
  `cond`「该判为恒真」**6 → 7** / `assert_arg(check_text)`「该判为恒真」**2 → 3**
  ⇒ 三处的**说明文字**同步改（批 BA/BB：说明文字必须与实际行为一致）。
- **同步**：门项总数基线 **1107 → 1122** ⇒ ⚠⚠⚨ **三处同改**；段级 trailer **52 → 53**。

**④ 负控 26/26 真红**

- **A 组 · 两棵树对照**（旧版 = `git archive HEAD` **整树** = 批 DC 版）：
  三个代表削弱 ⇒ **旧版探针绿 + 旧版接线门绿**（**假绿**）
  ⇒ **本批探针红 + 本批接线门红** ⇒ ⇒ **两头都有证据**。
- **B 组 · 本批版逐档削弱**（12 档，覆盖五张表）：每档 ⇒ **门红 且 探针自检红**
  ⇒ ⇒ 「改一处必红」这条纪律**真的**成立。
- **C 组 · 门级隔离**（8 条）：改写五张表的内容行 / 改掉 `py_const_if` 分支 /
  删掉一条自检样例 / 改坏一条自检样例的期望 ⇒ **接线门红且指名道姓**。
- **D 组 · 洁净度**：还原后与 harness 启动时的 `git diff` **逐字节相同**。

**⑤ 已知边界（如实记着，不粉饰）**

- ⚠ **枚举器没进仓**：批 CM/CJ 的纪律是「一次性盘点的数字不许被当成事实 ⇒ 搬进
  仓内常驻脚本」⇒ 本批的「78 次削弱 / 53 个洞」这个数字**来自 `/tmp` 里的枚举器**
  ⇒ ⚠ **仓内没有常驻的「口径表枚举器」** ⇒ 将来想重跑**要重写**
  ⇒ ⇒ 这条**如实记为已知边界**（不粉饰成「仓内可复算」）。
- ⚠ **枚举只能证明「当时没人发现」**：它不检查「将来新增的洞」⇒ 口径表变了
  （哪怕是**加**了一个档）⇒ 枚举结论**不会自动跟着更新**。
- ⚠ `LITERAL_CHAR` 的自检样例用的是**只含元字符的 ERE**（`^$.*+?()[]{}|\`）
  ⇒ 它**不是合法的 POSIX ERE** ⇒ 该样例只测「字符类判定」这个**谓词**，
  **不测 ERE 合法性** ⇒ **如实记着**。
- ⚠ `SHORTCUT` 的 10 档、`PY_CONST_IF` 的 4 档**必须每档单独一条样例**
  ⇒ 将来**新增**一档（例如再加一种退化写法）⇒ 必须**同时**补样例与内容门
  ⇒ 否则新档是**裸的**（无自检、无内容门）⇒ ⚠ 这是本批**最弱的一环**。
- ⚠ **恒真探针由 `ci.sh` 第 15 步跑**（不在接线门里）⇒ 腿 2 的红要等 CI 才看得见；
  腿 1 的红在接线门里立刻可见。
- ⚠ **影响面实测为零**（零产品代码改动 ⇒ 快照零变化）。

**数字**

- 门项物理行数 **1107 → 1122**（**+15**）、执行次数 **1110 → 1125**（+15）；
- 门项总数基线 **1107 → 1122**（**三处**同步）；
- 段级 trailer **52 → 53**；整行 `exit 1`（判据层）**3 不变**；
  `ARCH_ANY_FAIL=1` = **54**、`ARCH_FAIL=0` = **55**；
- ⚠ **恒真探针**：判定层 396 条判据不变、shell 与 python **875 → 876** 个条件
  （**+1** = 批 DD 段的段末 trailer 在 `ci-wiring.sh` 里新增 1 处 `if`
  ⇒ ⚠ **探针会数到自己的 CI 接线文件** ⇒ **自指**，知情取舍；
  ⚠ 探针源码自身新增的是 `elif` ⇒ python 口径只认**行首** `if` ⇒ 不计）、
  断言实参 99 条不变；⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；
- ⚠ **扫描范围不变**：判定层 4 / shell 41（deepin 18 + macos 13 + assets 1 + linux 9）/
  python 5 / swift 5；范围基线 **7 行带口径名不变**；
- 盘点 **21 组 / 72 处不变**；豁免表 **14 条不变**；
- 接线门 **1125** 项全绿、审计器硬门与报告模式 **rc=0**（门项 1122/1122 对基线）、
  恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
- ⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
  ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- **负控 26/26 真红**；累计 **942 → 968/968**。


### E.2bn mac 侧判据脚本不许游离 / 失败计数不许被摘掉（批 DE）

**① 起因（实测坐实，不是推演）**

两处「承诺悄悄消失」的洞：

| # | 洞 | 实测 |
|---|---|---|
| ① | **失败计数被摘掉 ⇒ 假绿** | 全仓「报错 + 失败计数」形态的**判据脚本 7 个**，批 BZ 的配对门只罩住 **2 个**（`check-deb-layout.sh` / `contract-check.sh`）⇒ **5 个未罩住**。其中 `assets/icon/check-icon.sh` 的失败助手是**报错与计数同行**（`bad() { echo "  ✗ $1"; fail=$((fail + 1)); }`）⇒ 摘掉计数点 ⇒ 末尾 `[[ $fail -eq 0 ]]` **恒真** ⇒ **恒 exit 0**；同款形态还有 mac 侧 **4 个 nc8x 负控脚本**（计数点写作 `fail=$((fail + 1))`，**带空格** ⇒ 与 `contract-check.sh` 的 `fail=$((fail+1))` 不是同一条正则） |
| ② | **mac 侧判据脚本可以整组游离** | 孤儿探针（批 BD）的范围**只有 `deepin/scripts/`** ⇒ `macos/scripts/` 里那 **12 个判据脚本**从来没被查过 ⇒ 有人把 `macos/build.sh` 里对某个判据脚本的**调用**摘掉 ⇒ **没有任何门会说一个字**。⚠ 实测坐实：`nc88…nc91` 这 **4 个负控脚本全仓无人调用**（`macos/build.sh` 不调、文档只在 `macos/README.md` 顺带提过）⇒ 这 4 组「判据坏了会红」的负控**从来没跑过** |

**② 关键口径坑（实测；直接扩范围会假红）**

mac 构建的调用形态是**裸可执行**（`if "$DIR/scripts/xxx.sh"; then`），**不是** `sh x.sh`
⇒ 孤儿探针现口径（要求解释器前缀）**认不出**
⇒ ⇒ 直接扩范围 ⇒ mac 侧 12 个脚本**全成「游离」⇒ 假红**。

⇒ 本批给 mac 侧**一份自己的调用点口径**（`CALL_RE_MACOS`），两份口径都**整行钉住**。

⚠⚠⚨ **而且 mac 那份必须排除「可执行性守卫」**（`if [ -x "$DIR/scripts/xxx.sh" ]; then`）——
守卫**不是调用** ⇒ 若把它算成调用 ⇒ 有人把真调用删掉、只留守卫 ⇒ 探针仍判「可达」⇒ **假绿**
⇒ ⇒ 口径：**引号路径之后到行尾不得出现 `]`** ⇒ `[ … ]` 守卫天然排除，而
`"…x.sh"; then` / `"…x.sh" || true` / `"…x.sh" 参数` **都算调用**
（⚠ 负控实测：口径若要求路径后**紧跟** `;` / `)` / 行末 ⇒ 认不出 `"…x.sh" || true`
⇒ 漏检 ⇒ 本批放宽成「后面没有 `]`」）。

**③ 修法（两腿，互不依赖 ⇒ 改一边必红）**

- **腿 1 · 失败计数不许被摘掉**（配对门从 **2** 个脚本扩到 **7** 个）
  ⚠ **配对门盯的是「计入 `fail` 的那一类」**（紧口径）⇒ **新增一条别措辞的失败路径**时它**看不见**
  ⇒ ⇒ 补一条**互补腿 · 失败路径清单门**（**5 条**）：盯失败路径的**总数**
  ⇒ ⇒ **两条腿缺一不可**：**摘掉计数点** ⇒ 配对门红；**新增失败路径** ⇒ 清单门红
  ⚠ nc8x 的紧口径必须排除 `exit 2` 那类「负控没生效」的报错行（那些**刻意不计数**）
  ⇒ ⚠⚠⚨ `nc90` 的 `expect_gone` 那条报错行**也带 `%-36s`** ⇒ 报错正则**必须**再钉住
  「期望红|红了」两档，否则期望值会变成 3 ⇒ **假红**（负控实测坐实）
- **腿 2 · mac 侧判据脚本不许游离**（孤儿探针从 **1** 个平台扩到 **2** 个）
  范围 / 入口 / 调用点口径 / 白名单格式 / 递归下钻 / fail closed ⇒ **逐条整行钉住**
  ⚠ 白名单条目格式改成 **`<平台>/<脚本名>|<理由>`** ⇒ 「不可达」是**相对于某个平台的 CI**
  才有意义的 ⇒ 不分平台 ⇒ deepin 的白名单能替 mac 开口子（反之亦然）⇒ **后门**

**④ 落门 / 判据**

- **新增 31 条**（批 DE 独立段）：
  腿 1 配对门 **5** + 腿 1 清单门 **5** + 腿 2 内容门 **15** +
  mac 白名单「不许被 `build.sh` 调用」门 **6**
- **原地替换 9 处**：孤儿门自己的报错行 **8 → 11** / 白名单格式 + 条数 **4 → 10** /
  失败上报语句 **7 → 10** / 两条旧门缩进 **4 → 8** 格 /
  `ARCH_ANY_FAIL=1` **54 → 55** / `ARCH_FAIL=0` **55 → 56** /
  门项条数 **1122 → 1153**
  ⇒ 顺带**修掉两处「说明文字与实际行为不一致」**（段级 trailer 那两条门：
  期望 54 / 55 而说明文字写的是 53 / 54 ⇒ 批 BB 纪律）
- **同步**：门项总数基线 **1122 → 1153** ⇒ ⚠⚠⚨ **三处同改**；段级 trailer **53 → 54**

**⑤ 负控 28/28 真红**

- **A 组 · 两棵树对照**（HEAD 整树 vs 本批树，**各自自洽**）
  - A1 摘掉 `macos/build.sh` 里 `if "$DIR/scripts/contract-check.sh"; then`
    （**保留** `[ -x … ]` 守卫）⇒ **HEAD 探针绿（假绿坐实）** ⇒ **本批探针红**
  - A2 摘掉 `assets/icon/check-icon.sh` 的 `fail=$((fail + 1))`
    ⇒ **HEAD 接线门绿（假绿坐实）** ⇒ **本批接线门红**
- **B 组 · 腿 1**（5 条）：摘掉 `check-icon.sh` 的计数点 / 摘掉 nc88 的一个计数点 /
  把 nc90 的报错正则放宽（3 ≠ 2 ⇒ 假红方向）/ 在 nc89 新增一条「只报错不计数、且措辞不同」
  的失败路径（⚠ **配对门看不见它** ⇒ 靠**清单门**抓住）/ 摘掉 `check-icon.sh` 的一个
  `bad "…"` 调用点 ⇒ 全部**接线门红**
- **C 组 · 腿 2**（15 条）：mac 调用口径被改弱 / mac 范围目录被改错 /
  平台清单少一个平台 / 递归下钻被摘 / 白名单条数基线被改小 / 白名单平台前缀不认识 /
  白名单脚本被接进 mac 构建 / 「什么算断言脚本」判定行被摘
  ⇒ 接线门**红**且指名道姓；⚠ 其中「递归下钻被摘」⇒ **探针仍绿**
  （子目录脚本不再被查 ⇒ **假绿复现** ⇒ **只有门能抓住**）
- **D 组 · 洁净度**（4 条）：还原后与 harness 启动时的 `git diff` **逐字节相同**；
  还原后接线门 / 审计器 / 孤儿探针仍全绿

**⑥ 数字**

门项物理行数 **1122 → 1153**（+31）、执行次数 **1125 → 1156**（+31）；
门项总数基线 **1122 → 1153**（**三处**同步）；段级 trailer **53 → 54**；
整行 `exit 1`（判据层）**3 不变**；`ARCH_ANY_FAIL=1` = **55**、`ARCH_FAIL=0` = **56**；
⚠ **配对门 2 → 7 条**（`check-deb-layout.sh` 1 / `contract-check.sh` 39 /
`check-icon.sh` 1 / `nc88…nc91` 各 2）；⚠ **失败路径清单门 5 条**
（`check-icon.sh` 的 `bad "` 调用点 **11** / nc88 **3** / nc89 **3** / nc90 **6** / nc91 **4**）；
⚠ **孤儿探针**：断言脚本 deepin **18** + macos **12** = **30** 个；
白名单 **4 → 10 条**（deepin 4 + macos 6）；
⚠ **恒真探针**：判定层 396 条判据不变、shell 与 python **876 → 881** 个条件（**+5**
= 孤儿探针重写后 `if` 条件数变化）、断言实参 99 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**
（判定层 4 / shell 41 / python 5 / swift 5）；范围基线 **7 行带口径名不变**；
盘点 **21 组 / 72 处不变**；豁免表 **14 条不变**；
接线门 **1156** 项全绿、审计器硬门与报告模式 **rc=0**（门项 1153/1153 对基线）、
恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 28/28 真红**；累计 **996/996**。

**⑦ 已知边界（如实记着）**

- ⚠ **`assets/icon/check-icon.sh` 目前不在任何 CI 里**（只有 `assets/icon/README.md`
  教人手跑）⇒ 本批给它的两道门守的是「**将来接进 CI 时它必须是真的**」，
  **不是**「它现在就在 CI 里跑」；
- ⚠ **mac 侧那 6 条白名单**（`engine-fetch-check.sh` + `nc8x` 4 + `render-harness/run.sh`）
  ⇒ 本批只把它们**显式登记**（带理由），**没有**接进 mac 构建
  ⇒ 缺口**从「悄悄消失」变成「有登记、有理由、可 review」**，但**缺口本身仍在**
  ⇒ 接进构建是**下一批**的事（需 macOS + Swift 工具链，本机无法验证）；
- ⚠ **孤儿探针的「可达」判定是路径级** ⇒ 「只是**提到**路径」也算调用
  （实测仓内没有这种写法）⇒ 已知边界；
- ⚠ **`.py` 口径**与**行尾注释**的既有边界**未动**（批 CZ / 批 CV 遗留）；
- ⚠ **本机无 Swift 工具链 / 无 macOS** ⇒ mac 侧脚本与 nc8x 负控只能**静态**验证，
  **不能真跑**。

### E.2bo 恒真探针的「条件抽取器」不许被掏空（批 DF）

**① 起因（实测坐实 + 对照实验，不是推演）**

恒真探针（批 BF 立的）里有**两个「条件抽取器」**——它们决定「哪些条件会被拿去判恒真」：

| 抽取器 | 管哪边 | 抽什么 | 现状 |
|---|---|---|---|
| `extract_check_conds` | **C++ 判定层** | `check(...)` 的**第三个实参**（= 判据条件） | ⚠ **零门 + 零自检** |
| `_shell_cond_at` | **shell 侧** | 每个 `if` / `elif` / `while` / `until` 的条件文本（**含跨行拼接**） | ⚠ **零门**（自检间接覆盖） |

⇒ ⚠⚠⚨ **实测坐实的洞**：把 `extract_check_conds` 里的 `if len(args) >= 3:`
改成 `if len(args) >= 99:` ⇒

- 判定层 **396 条判据 ⇒ 0 条**（探针照样打印「✓ 判据非恒真：判定层 **0** 条判据…」）；
- 而 **接线门 rc=0 / 探针 rc=0 / 审计器 rc=0** ⇒ ⚠⚠⚨ **三样全绿**
  ⇒ ⇒ 「判定层每条判据的条件都含被测标识符」这条承诺**彻底消失**，
  而**没有任何门会说一个字**。

⚠ **为什么自检也覆盖不到**：自检的 `cond` 那一档喂的是**裸条件串**
（`'true'` / `'1 == 1'` …）⇒ **压根不经过 `extract_check_conds`** ⇒
抽取器被掏空时自检**照样绿**。

⚠ 第二个变异（`args[2]` ⇒ `args[0]`）同样三样全绿 ⇒ 抽到的变成**第一个实参**
（`log` 之类）⇒ 判据条件变成一个**恒真的标识符** ⇒ 承诺变空 ⇒ **假绿坐实**。

**② 修法（两腿，互不依赖 ⇒ 改一边必红）**

- **腿 1 · 内容级门（14 条，全部整行锚定）**
  - C++ 侧 5 条：定义行 / 抽取起点（`check(`）/ **认「第三个实参」**（`len(args) >= 3`）/
    **取第三个实参**（`args[2]`）/ **实扫必须真的走那个抽取器**（批 CX 同款教训：
    「常量在、但扫描时不判」⇒ 定义了不用 ⇒ 等于没定义）；
  - shell 侧 3 条：定义行 / **跨行拼接** / 实扫走它；
  - 自检侧 6 条：新自检档必须在 / 自检**必须真的经过抽取器** / 自检必须走真判定 /
    三条样例（该判红 2 + 不该判红 1）不许被掏空。
- **腿 2 · 补自检（新增自检档 `cpp_e2e`）**
  - 样例**必须经过 `extract_check_conds`**（与实扫同一条路径 ⇒ 口径零漂移）
    ⇒ 抽取器被掏空 ⇒ **自检当场红**（实测：M1/M2 变异 ⇒ 自检失败数 0 → 2）；
  - ⚠ **同时**含「该判红」与「不该判红」（批 BF 纪律：只测一边 ⇒ 判反了也能过）；
  - ⚠ 3 条样例分别覆盖：单条恒真 / 单条不恒真 / **多条**（防「只抽第一条」的抽取器）。

**③ 落门 / 判据**

- **新增 14 条**（批 DF 独立段，全部整行锚定）；
- ⚠ **门项正则是程序化生成**的（不手抄 ⇒ 零漂移）⇒ 生成后**逐条回验**命中数 == 1；
- **同步**：门项总数基线 **1153 → 1167** ⇒ ⚠⚠⚨ **三处同改**；段级 trailer **54 → 55**；
  `ARCH_ANY_FAIL=1` **55 → 56**、`ARCH_FAIL=0` **56 → 57**。

**④ 负控 28/28 真红**

- **A 组 · 两棵树对照**（HEAD 整树 vs 本批树，各自自洽）：
  M1（抽不出条件）/ M2（抽错实参）⇒ **HEAD 探针绿（假绿坐实）** ⇒ **本批探针红**；
- **B 组 · 内容门逐条隔离**（8 条）：M1 / M2 / 抽取起点改名 /
  **实扫不调那个抽取器** / 自检不再经过抽取器 / 自检类别改名 /
  shell 抽取器改名 / shell 跨行拼接被摘
  ⇒ 接线门**红**且指名道姓；
  ⚠ 其中两条 ⇒ **探针仍绿**（「实扫不调抽取器」⇒ 判定层报 0 条却仍绿；
  「跨行拼接被摘」⇒ 条件数不变仍绿）⇒ **假绿复现 ⇒ 只有门能抓住**；
- **C 组 · 门级隔离**（4 条）：门项条数基线被改小 / 删掉一条批 DF 门项 /
  段级 trailer 门期望值被改小 / 审计器常量被改小 ⇒ 接线门红；
- **D 组 · 洁净度**（4 条）：还原后与 harness 启动时的 `git diff` **逐字节相同**；
  还原后接线门 / 审计器 / 探针仍全绿。

**⑤ 数字**

门项物理行数 **1153 → 1167**（+14）、执行次数 **1156 → 1170**（+14）；
门项总数基线 **1153 → 1167**（**三处**同步）；段级 trailer **54 → 55**；
`ARCH_ANY_FAIL=1` = **56**、`ARCH_FAIL=0` = **57**；
⚠ **恒真探针**：判定层 **396** 条判据不变、shell 与 python **881 → 882** 个条件
（**+1** = 批 DF 段末 trailer 在 `ci-wiring.sh` 里新增 1 处 `if` ⇒ ⚠ **探针会数到自己的
CI 接线文件** ⇒ **自指**，知情取舍）、断言实参 99 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**
（判定层 4 / shell 41 / python 5 / swift 5）；范围基线 **7 行带口径名不变**；
盘点 **21 组 / 72 处不变**；豁免表 **14 条不变**；孤儿探针 **30** 个断言脚本 /
白名单 **10** 条**不变**；接线门 **1170** 项全绿、审计器硬门与报告模式 **rc=0**
（门项 1167/1167 对基线）、恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
⚠ `ci.sh` **15/15 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 28/28 真红**；累计 **1024/1024**。

**⑥ 已知边界（如实记着）**

- ⚠ **真实语料上的「抽取覆盖率」没有基线钉住**：实测「源码里 `check(` 出现 **397** 次 vs
  抽出 **396** 条」⇒ 差的 1 处是**注释里**的提及 ⇒ 严格交叉校验会**假红**
  ⇒ 本批**不做**判据数基线；⇒ 抽取器本身由「**内容门 + 合成自检**」保证
  （合成自检**不依赖真实语料** ⇒ **零维护成本**；代价是「真实语料上少抽了若干条」
  这一类**只影响覆盖面**的削弱**抓不到** ⇒ 明确记为边界，不假装堵死）；
- ⚠ **判据数会随产品代码变动** ⇒ 钉它等于「每加一条判据都要改判据层」
  ⇒ 与「判据层不随产品代码变动」相悖 ⇒ 同样**不做**；
- ⚠ `_shell_cond_at` 的**跨行拼接**目前**只由内容门**保护（自检的 `shell_e2e` 样例
  是单行条件 ⇒ 覆盖不到跨行）⇒ 跨行拼接被摘时**探针仍绿**（实测）⇒ **只有门能抓住**。

### E.2bp assets 侧判据脚本不许游离（图标那一套真的进 CI）（批 DG）

**① 起因（实测坐实，不是推演）**

`assets/icon/` 下有**两个判据脚本** —— 它们的断言**从来没人执行**：

| 脚本 | 干什么 | 现状 |
|---|---|---|
| `assets/icon/check-icon.sh` | 「所有平台用同一套 icon」这条约束的验收 | ⚠ **不在任何 CI 里** |
| `assets/icon/make-icons.py --check` | 产物与母版一致性的**只校验**模式 | ⚠ **不在任何 CI 里** |

⇒ ⚠⚠⚨ 有人改了图标体系、忘了重跑产物 ⇒ **没有任何门会说一个字**。

⚠ **与 mac 侧那 6 条白名单不同款（本批能「真接」而不只是「只登记」的原因）**：
mac 侧那 6 个脚本要 macOS + Swift 工具链 ⇒ **本机不可验** ⇒ 只能登记；
而这两个**本机可跑可验**（Pillow 在、`assets/icon/out/` 产物入库）⇒
**真的接进 CI** ⇒ 批 DE 遗留的「assets 侧判据脚本游离」**正面收掉**。

**② 修法（两腿）**

- **腿 1 · 接进 CI（`ci.sh` 新增第 15 步 ⇒ 步数 15 → 16）**
  - 先跑 `make-icons.py --check`（产物与母版一致）⇒ 再跑 `check-icon.sh`（三平台同一套）；
  - ⚠⚠⚨ **工具缺席 ⇒ 未验证（专属码 3），不许当成真失败**（批 CB/CC 纪律）：
    这两个脚本都要 Pillow ⇒ 缺席时 `check-icon.sh` 的母版包围盒那节
    会把「PIL-缺」当成「母版不合法」⇒ **把「工具没装」说成「图标不一致」**
    ⇒ **码值语义被顶替** ⇒ 先探工具 ⇒ 缺席 ⇒ `skip++` ⇒ 末尾 `exit 3`；
  - ⚠ 步数变化 ⇒ 步数门 / 连续门 / 批 BA「每一步都有门」/ `in_step`
    / 批 CA「失败上报条数」/ 批 CK「未验证计数点条数」**全部同步改**。
- **腿 2 · 孤儿探针扩到**第三个平台 `assets`**
  - 范围 / 入口 / 调用点口径 / 路径前缀 **各一份**；
  - ⚠ assets 侧**没有自己的 CI** ⇒ 入口就是 deepin 的 `ci.sh`
    ⇒ ⚠ **入口共用 ≠ 口径共用**：可达集合仍**按平台各算各的**
    （assets 只认 `/assets/` 下的路径 ⇒ deepin/macos 的脚本**不会**流进 assets 集合）
    ⇒ 批 DE 的「分平台」纪律**没有被破坏**；
  - ⚠ `_strip` 路径前缀**参数化**（原来硬编码 `.*/scripts/`）
    ⇒ deepin/macos 两支**一个字都不改** ⇒ 批 DE 那两条门**不用动**。

**③ 落门 / 判据**

- **新增 13 条**（批 DG 独立段）：ci.sh 侧 5 条（两个调用点 / 工具探针 /
  未验证提示 / 跨行锚定「SKIP 必须紧跟计数」）+ 孤儿探针侧 8 条
  （范围 / 入口 / 路径片段 / 调用口径 / 路径前缀 / 前缀默认值 / 平台分支 / 汇总文案）；
- ⚠ 门项正则是**程序化生成**的（不手抄 ⇒ 零漂移）⇒ 生成后**逐条回验**命中数；
- ⚠⚠⚨ **踩到的坑（负控逼出来的）**：生成器把目标路径写成 `""$SRC/..."`（**双引号套了两层**）
  ⇒ 审计器 `COUNT_LINE` 的 `"([^"]+)"` 匹配不到 ⇒ **13 条门全成「审计器盲区」**
  ⇒ ⇒ **门自己不被审** ⇒ 接入审计器覆盖时必须**回验「审计器认领数 == 门项行数」**；
- **同步**：门项总数基线 **1167 → 1180** ⇒ ⚠⚠⚨ **三处同改**；
  段级 trailer **56 → 57**；`ARCH_ANY_FAIL=1` **56 → 57**、`ARCH_FAIL=0` **57 → 58**；
  ⚠ **锚定豁免基线**里那 1 条（`› [0-9]+/15` → `› [0-9]+/16`）**内容同步**
  ⇒ 豁免表**条数 14 条不变**。

**④ 负控 28/28 真红**

- **A 组 · 两棵树对照**（HEAD 整树 vs 本批树）：
  - HEAD 树的 `ci.sh` 里**零** assets 图标调用 ⇒ HEAD 的判据层全套**全绿**
    ⇒ **假绿坐实**；
  - 本批树：把母版换成不满幅 ⇒ 两个图标判据脚本**都红** ⇒ 第 15 步真红 ⇒ 抓住；
- **B 组 · 内容门逐条隔离**（13 条）：逐条变异 ⇒ 接线门**红**；
- **C 组 · 门级隔离**（6 条）：基线 / 审计器常量 / 门里的数字 / 步数期望 /
  删门项 / 段级 trailer 期望 ⇒ 接线门红；
- **D 组 · 洁净度**（5 条）：还原后与 harness 启动时的 `git diff` **逐字节相同**；
  还原后接线门 / 审计器 / 探针 / 孤儿探针仍全绿。

**⑤ 数字**

门项物理行数 **1167 → 1180**（+13）、执行次数 **1170 → 1183**（+13）；
门项总数基线 **1167 → 1180**（**三处**同步）；段级 trailer **56 → 57**；
`ARCH_ANY_FAIL=1` = **57**、`ARCH_FAIL=0` = **58**；
⚠ **恒真探针**：判定层 **396** 条判据不变、shell 与 python **882 → 886** 个条件
（**+4** = `ci.sh` 新增 3 处 `if` + 批 DG 段末 trailer 在 `ci-wiring.sh` 里新增 1 处 `if`
⇒ ⚠ **探针会数到自己的 CI 接线文件** ⇒ **自指**，知情取舍）、断言实参 **99** 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**
（判定层 4 / shell 41 / python 5 / swift 5）；范围基线 **7 行带口径名不变**；
盘点 **21 组 / 72 → 73 处**（`ci.sh` 的「跳过提示」9 → 10 = Pillow 缺席那一处）；
⚠ **CI 入口**：步数 **15 → 16**、失败上报 **36 → 38**、未验证计数点（4 缩进）**5 → 6**；
⚠ **孤儿探针**：断言脚本 **30 → 32** 个（deepin 18 + macos 12 + **assets 2**）、
白名单 **10** 条**不变**（assets 侧 0 条 ⇒ 两个脚本**真的**在 CI 里可达）；
⚠ **豁免表 14 条不变**（其中 1 条内容随步数同步）；
接线门 **1183** 项全绿、审计器硬门与报告模式 **rc=0**（门项 **1180/1180** 对基线、
**0 条**审计器盲区）、恒真探针 **rc=0**、孤儿探针 **rc=0**（三平台 32 个断言脚本）、
盘点对拍 **rc=0**；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 28/28 真红**；累计 **1052/1052**。

**⑥ 已知边界（如实记着）**

- ⚠ **`make-icons.py` 仍是生成器 + 判据一体**：本批只接了它的 `--check`（只校验）模式
  ⇒ 生成路径**不在 CI 里**（生成会写盘 ⇒ CI 里跑不合适）⇒ 只记为边界；
- ⚠ **恒真探针的 python 范围仍不含 `make-icons.py`**（本批未扩范围 ⇒ 范围基线不变）
  ⇒ 它的 if 条件**不受恒真检查** ⇒ 明确记为边界，不假装覆盖到了；
- ⚠ **Pillow 缺席 ⇒ 整组 SKIP**（保守口径）⇒ 那一组在没装 Pillow 的环境里
  **完全没验** ⇒ 但**如实报「未验证」**并让 CI 末尾 rc=3 ⇒ **不会假装通过**；
- ⚠ `ci.sh` 的「失败上报」盘点口径**不含**本批新增的 2 处 `exit 1`
  （它们是**真失败**不是「未验证出口」⇒ 按口径本就不该登记）⇒ 登记册「失败上报 5 处」不变。

### E.2bq 判据脚本的「判定口径常量」不许被掏空（批 DH）

**① 起因（实测坐实，不是推演）**

判据脚本里有一类东西决定「**什么算违规**」—— 散值口径、四语言清单、`.arg(数字)`
那一整串正则。⚠ 批 DH **逐个做变异实测** ⇒ 三个被改弱后
⚠⚠⚨ **接线门 rc=0 + 审计器 rc=0**（**两套判据层全绿**）⇒ **假绿坐实**：

| 口径 | 在哪个脚本 | 改弱后 | 后果 |
|---|---|---|---|
| `D2_PATTERN` | `ci-d2.sh` | 去掉字号/色值三类 | 「DS::* 之外出现散值即缺陷」**彻底消失** |
| `D2_ARG_PATTERN` | `ci-d2.sh` | `.arg(数字` ⇒ `.arg(x` | 「`Q_ARG` 里的数字也是散值」这条判据**消失** |
| `EXPECTED` | `ci-docs-lang-probe.sh` | 四语言少 `ja` | 「四种语言都要真跑一遍」**悄悄变弱** |

⚠⚠⚨ **为什么三套机制都抓不到**（这才是关键）：
- **恒真探针**（批 BF 立的）盯的是「**条件本身**是不是恒真」
  ⇒ 而这些是「**条件匹配什么**」⇒ 口径被改窄 ⇒ 条件照样非恒真 ⇒ **绿**；
- **孤儿探针**（批 BD/DE/DG）盯的是「脚本**在不在 CI 里**」
  ⇒ 脚本在、口径被掏空 ⇒ **绿**；
- **审计器**审的是「门项有没有命中 0 次」
  ⇒ 被改弱的**不是门项** ⇒ 命中数**没变** ⇒ **绿**。

⇒ 所以只能给这些口径**逐字钉住**（整行锚定）⇒ 改一个字就红。

**② 修法（3 条内容级门，全部整行锚定）**

- `D2_PATTERN`（散值口径整行）、`D2_ARG_PATTERN`（`.arg(数字)` 口径整行）、
  `EXPECTED`（四语言清单整行）；
- ⚠ 门项正则**从真实行现抽 + 程序化转义**（不手抄 ⇒ 零漂移）
  ⇒ 生成后**逐条回验**命中数 == 1。

**③ 落门 / 判据**

- **新增 3 条**（批 DH 独立段）；
- 原地替换 5 处：`ARCH_ANY_FAIL=1` 57 → 58、`ARCH_FAIL=0` 58 → 59、
  门项条数 1180 → 1183（门里那个数字 + 说明沿革）；
- 同步：门项总数基线 **1180 → 1183** ⇒ ⚠⚠⚨ **三处同改**。

**④ 负控 12/12 真红**

- **A 组 · 两棵树对照**（HEAD 整树 vs 本批树）：
  HEAD 树里把 `D2_PATTERN` 改弱 ⇒ **接线门 / 审计器 / 孤儿探针全绿**
  ⇒ **假绿坐实** ⇒ 本批树同一变异 ⇒ **接线门红且指名道姓**；
- **B 组 · 内容门逐条隔离**（3 条）：三个口径逐个改弱 ⇒ 接线门**红**；
- **C 组 · 门级隔离**（4 条）：基线 / 审计器常量 / 门里的数字 / 段级 trailer 期望
  ⇒ 接线门红；
- **D 组 · 洁净度**（3 条）：还原后与 harness 启动时的 `git diff` **逐字节相同**；
  还原后接线门 / 审计器仍全绿。

**⑤ 数字**

门项物理行数 **1180 → 1183**（+3）、执行次数 **1183 → 1186**（+3）；
门项总数基线 **1180 → 1183**（**三处**同步）；段级 trailer **57 → 58**；
`ARCH_ANY_FAIL=1` = **58**、`ARCH_FAIL=0` = **59**；
⚠ **恒真探针**：判定层 **396** 条判据不变、shell 与 python **886 → 887** 个条件
（**+1** = 批 DH 段末 trailer 在 `ci-wiring.sh` 里新增 1 处 `if` ⇒ ⚠ **探针会数到自己的
CI 接线文件** ⇒ **自指**，知情取舍）、断言实参 **99** 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**
（判定层 4 / shell 41 / python 5 / swift 5）；盘点 **21 组 / 73 处不变**；
孤儿探针 **32** 个断言脚本 / 白名单 **10** 条不变；
⚠ **CI 入口**：步数 **16**、失败上报 **38**、未验证计数点 **6** 均不变；
接线门 **1186** 项全绿、审计器硬门与报告模式 **rc=0**（门项 **1183/1183** 对基线）、
恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 12/12 真红**；累计 **1064/1064**。

**⑥ 已知边界（如实记着，不假装堵死）**

- ⚠ **本批只收了「已实测坐实」的三个口径**。判据层里同类口径还有一批
  （实测清单见下）⇒ **下一步**：把「口径表枚举器」搬进仓内常驻
  ⇒ 那样「新增了口径却忘了加门」这一类**抓得到**；
  ⚠⚠⚨ 在那之前，**「新增口径漏门」这一类削弱抓不到** ⇒ 明确记为边界；
- ⚠ 本批的变异实测里另有三个口径**被别的腿接住**（不是洞，但记下来免得重复查）：
  ① 审计器的「盲区核对」被摘 ⇒ 次数门配准失准（rc=4）⇒ 红；
  ② 审计器的「总数核对」被摘 ⇒ 同上；
  ③ `ci-true-audit.py` 的 `TRUE_RE` 被改弱 ⇒ 盘点与登记册对不上 ⇒ 红。
  ⚠ ① ② ⇒ **审计器有多腿**（总数核对 + 配准校准 + 锚定形态 + 豁免对拍）
  ⇒ 单腿被摘**有人接** ⇒ **组合摘**才会露洞（已知边界）。

### E.2br 判据层的「阈值 / 抽取口径」不许被掏空（批 DI）

**① 起因（实测坐实，不是推演）**

判据脚本里有两类东西决定「**判据有多松**」：

| 类别 | 例子 | 改弱后 |
|---|---|---|
| **阈值 / 上限** | `D2_COUNT=0`（散值上限 0） | 改成 5 ⇒ ≤5 处散值就被放过 |
| **抽取口径** | `sed -n 's/^panelValid=//p'` | 改成 `s/^panel//p` ⇒ 抽到 `Valid=1` |

⚠ 批 DI **逐个做变异实测** ⇒ 四个被改弱后
⚠⚠⚨ **接线门 rc=0 + 审计器 rc=0**（两套判据层全绿）⇒ **假绿坐实**：

- `D2_COUNT=0`（`ci-d2.sh`）⇒ 「散值上限 0」这条承诺**悄悄变松**；
- `PANEL_VALID`（`ci-platform-probe.sh`）⇒ 抽到 `Valid=1` ⇒ **非空检查照样通过**
  ⇒ `[ "$PANEL_VALID" = "1" ]` 不成立 ⇒ ⚠⚠⚨ **面板几何那一整段断言被静默跳过**；
- `ICON_MISSING`（`ci-platform-probe.sh`）⇒ 抽到 `Missing=0` ⇒ 非空检查通过
  ⇒ 在**无图标主题**的离屏环境里那条断言**根本不触发**；
- `VALIDATED`（`probe-agent-tool-surface.sh`）⇒ 抽到 `ated=…` ⇒ 非空检查通过
  ⇒ 「每个废弃别名都要在校验表里」逐条比的都是**错值**
  ⇒ ⚠⚠⚨ **别名重新出现在模型可见面也不会被发现**。

⚠⚠⚨ **为什么恒真探针 / 孤儿探针 / 审计器都抓不到**：
恒真探针盯「条件本身是不是恒真」⇒ 条件照样非恒真；
孤儿探针盯「脚本在不在 CI 里」⇒ 脚本在；
审计器审「门项有没有命中 0 次」⇒ 被改弱的**不是门项**。

**② 关键区分（负控逼出来的）——「牙在接线门」≠「牙在脚本自己」**

⚠ 抽取口径被改弱后，**那个探针脚本自己**红不红，必须**实测**：

| 口径 | 脚本自己 | 判定 |
|---|---|---|
| `screenRect` / `appAlive` | **红**（有格式校验 ⇒ 抽错就红） | **有牙**（牙在 CI 步骤里） |
| `panelValid` / `validated` / `iconMissing` | **绿**（抽错 ⇒ 值非空 ⇒ 检查通过 ⇒ 断言被跳过） | ⚠⚠⚨ **真洞** |

⇒ ⚠ **「接线门绿」本身不能作为「没洞」的证据** ⇒ 必须**同时**跑那个脚本自己。

**③ 修法（4 条内容级门，全部整行锚定）**

- `D2_COUNT=0` / `PANEL_VALID` / `ICON_MISSING` / `VALIDATED` 四个口径**逐字钉住**
  ⇒ 改一个字就红；
- ⚠ 门项正则**从真实行现抽 + 程序化转义**（不手抄 ⇒ 零漂移）
  ⇒ 生成后**逐条回验**命中数 == 1。

**④ 落门 / 判据**

- **新增 4 条**（批 DI 独立段）；
- 原地替换 5 处：`ARCH_ANY_FAIL=1` 58 → 59、`ARCH_FAIL=0` 59 → 60、
  门项条数 1183 → 1187（门里那个数字 + 说明沿革）；
- 同步：门项总数基线 **1183 → 1187** ⇒ ⚠⚠⚨ **三处同改**。

**⑤ 负控 13/13 真红**

- **A 组 · 两棵树对照**（HEAD 整树 vs 本批树）：HEAD 树里把 `D2_COUNT` 放宽
  ⇒ **接线门 / 审计器全绿** ⇒ **假绿坐实**；本批树同一变异 ⇒ **接线门红**；
- **B 组 · 内容门逐条隔离**（4 条）：四个口径逐个改弱 ⇒ 接线门**红**；
- **C 组 · 门级隔离**（4 条）：基线 / 审计器常量 / 门里的数字 / 段级 trailer 期望
  ⇒ 接线门红；
- **D 组 · 洁净度**（3 条）：还原后与 harness 启动时的 `git diff` **逐字节相同**；
  还原后接线门 / 审计器仍全绿。

**⑥ 数字**

门项物理行数 **1183 → 1187**（+4）、执行次数 **1186 → 1190**（+4）；
门项总数基线 **1183 → 1187**（**三处**同步）；段级 trailer **58 → 59**；
`ARCH_ANY_FAIL=1` = **59**、`ARCH_FAIL=0` = **60**；
⚠ **恒真探针**：判定层 **396** 条判据不变、shell 与 python **887 → 888** 个条件
（**+1** = 批 DI 段末 trailer 在 `ci-wiring.sh` 里新增 1 处 `if` ⇒ ⚠ **探针会数到自己的
CI 接线文件** ⇒ **自指**，知情取舍）、断言实参 **99** 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**
（判定层 4 / shell 41 / python 5 / swift 5）；盘点 **21 组 / 73 处不变**；
孤儿探针 **32** 个断言脚本 / 白名单 **10** 条不变；
⚠ **CI 入口**：步数 **16**、失败上报 **38**、未验证计数点 **6** 均不变；
接线门 **1190** 项全绿、审计器硬门与报告模式 **rc=0**（门项 **1187/1187** 对基线、
**0 条**审计器盲区）、恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 13/13 真红**；累计 **1077/1077**。

**⑦ 已知边界（如实记着，不假装堵死）**

- ⚠ **本批只把口径「钉住」（接线门层有牙）** ⇒ 治本的第二步
  「给那三处抽取值补**格式校验**（`panelValid` 必须 0/1、`iconMissing` 必须纯数字、
  `validated` 必须是标识符列表）」**留到下一批** ⇒ ⇒ 在那之前，
  「抽取口径被改弱 ⇒ **探针脚本自己也绿**」这一类**只有接线门能抓住**；
- ⚠ `ICON_MISSING` 那条在**有图标主题的真机**上本来就会红（`Missing=0` ≠ `0`）
  ⇒ 本批记的是**离屏 CI 环境**里的覆盖面缺口；
- ⚠ **「口径表枚举器」候选经本批实测后降级**：机械判定标准（常量的值含正则元字符
  或命令替换）实测会命中 **237 条**，绝大多数是**路径常量**（`SRC=` / `BIN=` / `TMP=`）
  ⇒ 登记册会大到不可维护 ⇒ ⇒ 收益低 ⇒ **明确记为「暂不做」，不假装它解决了**
  （它本来也堵不住「新增口径漏门」——那需要另一条路）。

### E.2bs 判据脚本的「抽取值」不许被改弱到「静默失效」（批 DJ）

**① 起因（实测坐实，不是推演）**

批 DI 把「**抽取口径**」逐字钉住了（接线门层有牙），并在「⑦ 已知边界」里
明确记下治本的第二步：**给那三处抽取值补格式校验，让探针脚本自己也有牙**。
⇒ 本批就是那一步。

⚠⚠⚨ **批 DI 已经把洞的形状测出来了**（本批据此动手，不是推演）：

| 抽取值 | 口径被改弱后抽到 | 原来那层检查 | 结果 |
|---|---|---|---|
| `panelValid` | `Valid=1` | **只有非空检查** | ⚠⚠⚨ 非空通过 ⇒ `[ "$PANEL_VALID" = "1" ]` 不成立 ⇒ **面板几何那一整段断言被静默跳过** |
| `iconMissing` | `Missing=0` | **只有非空检查** | ⚠⚠⚨ 非空通过 ⇒ 在**无图标主题**的离屏环境里那条断言**根本不触发** ⇒ 图标缺失**没人查** |
| `validated` | `ated=…` | **只有非空检查** | ⚠⚠⚨ 非空通过 ⇒ 「每个废弃别名都要在校验表里」**逐条比的都是错值** ⇒ 别名重新出现在模型可见面**也不会被发现** |

⚠⚠⚨ **关键点**：三处抽到的都是「**前缀残留**」⇒ 形状是 `Valid=1` / `Missing=0` /
`ated=…` ⇒ ⚠⚠⚨ **全都含 `=`** ⇒ 只要格式正则的字符类**排除 `=`**，它们一律被抓。

**② 修法（治本：给三处补格式校验）**

- `panelValid` ⇒ 必须 `^[01]$`（**排除 `=`** ⇒ `Valid=1` 一律被抓）；
- `iconMissing` ⇒ 必须 `^[0-9]+$`（⇒ `Missing=0` 一律被抓）；
- `validated` ⇒ 必须 `^[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*$`（⇒ `ated=…` 一律被抓）；
- ⚠ **`validated` 的校验位置**：必须在「**引擎太老 ⇒ SKIP**」那一支**之后**
  ⇒ 否则引擎太老时（探针可能压根不报 `validated=`）那条路径会被**误判红**
  ⇒ SKIP 语义被破坏；
- ⚠ **新增报错文案避开盘点关键词**（`跳过` / `未验证` / `SKIP` 等）
  ⇒ 否则「未验证出口盘点」的登记册对不上 ⇒ **假红**
  ⇒ 本批用「**判定失效**」「**没人知道**」「**比的都是错值**」措辞。

**③ 落门 / 判据**

- **新增 3 条**（批 DJ 独立段）：三条内容级门**整行锚定**那三行格式校验
  ⇒ 校验行被删 / 被改弱 ⇒ 接线门当场红；
- ⚠ 门项正则**从真实行现抽 + 程序化转义**（不手抄 ⇒ 零漂移）
  ⇒ 生成后**逐条自检**（各命中 1 次 + 整行锚定 + 中段无无界通配）；
- 原地替换 **6 处**：
  - `ci-platform-probe.sh` 断言清单报错行 **22 → 24**（+2 条新报错）；
  - `ci-platform-probe.sh` 失败上报语句条数 **24 → 26**（+2 条 `exit 1`）；
  - `probe-agent-tool-surface.sh` 断言清单报错行 **11 → 12**（+1 条新报错）；
  - `probe-agent-tool-surface.sh` 失败上报语句条数 **13 → 14**（+1 条 `exit 1`）；
  - 段级 trailer：`ARCH_ANY_FAIL=1` **59 → 60**、`ARCH_FAIL=0` **60 → 61**；
  - 门项条数 **1187 → 1190**（门里那个数字 + 说明沿革）；
- 同步：门项总数基线 **1187 → 1190** ⇒ ⚠⚠⚨ **三处同改**。

**④ 负控（本批的核心：两棵树对照 + 脚本层对照）**

⚠⚠⚨ **判据的关键（第一版我把这条写反了，被负控当场抓住）**：
批 DI 已经把**抽取口径**钉住了 ⇒ 口径变异在**两棵树上都会让接线门红**
（那是批 DI 的成果，**不是**本批的对照组）
⇒ ⇒ 真正的区分点是「**探针脚本自己**」：

| 树 | 接线门 | 审计器 | ⚠ **探针脚本自己** | 判定 |
|---|---|---|---|---|
| **A** = HEAD 版（4c7f4ac，无格式校验） | 红 | rc=0 | ⚠⚠⚨ **绿** | ⚠⚠⚨ **脚本层没牙** ⇒ 断言被静默跳过 |
| **B** = 本批树（有格式校验） | 红 | rc=0 | ⚠ **红** | ⚠⚠⚨ **牙补上了** |

⇒ 三个变异（`panelValid` / `iconMissing` / `validated` 各自改弱口径）
⇒ **6 条判据全绿**（每组 2 条 × 3 组）。

⚠⚠⚨ **判据二：内容级门隔离**（把格式校验的正则改弱 / 把整条校验行删掉）
⇒ 接线门红；⚠ 审计器要用 **`--list` 模式**跑（总条数核对**只在 `--list` 模式跑**
⇒ 审计器既有设计）⇒ 命中数失配 ⇒ 审计器也红。

⚠⚠⚨ **判据三：门项条数三处同改**（只改审计器常量一处）
⇒ 接线门红 + 审计器（`--list`）红（条数失配）。

⚠⚠⚨ **判据四：洁净度** —— 还原后与 harness 启动时的 `git diff` **逐字节相同**。

⚠ **harness 自己踩的坑（如实记着）**：
① `snapshot` 重复取会把「**已变异的内容**」当成基线 ⇒ 还原不回去
   ⇒ **只在第一次取快照**；
② 备份路径与内容混存 ⇒ 还原报「文件名过长」
   ⇒ **备份路径与内容必须分开存**；
③ **判据写反**（把「树 A 接线门该绿」当期望）⇒ 被自己的负控抓住
   ⇒ 树 A 的接线门**本来就该红**（批 DI 的成果）⇒ 区分点是**探针脚本自己**；
④ **总条数核对只在 `--list` 模式跑** ⇒ 那条负控必须用 `--list` 跑
   ⇒ 否则测的是「没跑」而不是「跑通了」；
⇒ ⇒ 全部加**启动前自检**（三处口径必须原样 ⇒ 否则测的是脏数据）。

**⑤ 数字**

门项物理行数 **1187 → 1190**（+3）、执行次数 **1190 → 1193**（+3）；
门项总数基线 **1187 → 1190**（**三处**同步）；段级 trailer **59 → 60**；
`ARCH_ANY_FAIL=1` = **60**、`ARCH_FAIL=0` = **61**；
⚠ **恒真探针**：判定层 **396** 条判据不变、shell 与 python **888 → 892** 个条件
（**+4** = 三处新格式校验的 `if` + 批 DJ 段末 trailer 自指）、
断言实参 **99** 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**
（判定层 4 / shell 41 / python 5 / swift 5）；
盘点 **21 组 / 73 处不变**（⇒ 新增报错文案**成功避开**盘点关键词）；
孤儿探针 **32** 个断言脚本 / 白名单 **10** 条不变；
⚠ **CI 入口**：步数 **16**、失败上报 **38**、未验证计数点 **6** 均不变；
接线门 **1193** 项全绿、审计器硬门与报告模式 **rc=0**（门项 **1190/1190** 对基线、
**0 条**审计器盲区）、恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 22/22 真红**；累计 **1099/1099**。

**⑥ 已知边界（如实记着，不假装堵死）**

- ⚠ **本批收的是「脚本自己那层牙」** ⇒ 口径被改弱 ⇒ 探针脚本**自己**会红
  ⇒ 但**接线门那层牙是批 DI 给的**（本批没动它）；
- ⚠ **格式校验只覆盖这三处** ⇒ 别处若还有「**只有非空检查**」的抽取值，
  同款洞**依然存在** ⇒ ⚠ **不做「抽取值枚举器」**（机械标准会命中 237 条路径常量
  ⇒ 登记册不可维护 ⇒ 批 DI 已降级）；
- ⚠⚠⚨ **批 DJ 之后的逐处复核结论（实测，不是推演）**：
  判据层所有 `sed -n 's/^<键>=//p'` 型抽取**逐个实测**过口径变异，
  ⇒ **其余各处都已有牙**（**不靠格式校验**，靠各自的**下游断言**）：

  | 抽取值 | 口径被改弱后 | 为什么仍会红 |
  |---|---|---|
  | `APP_ALIVE`（3 处） | 抽到 `Alive=1` | `[ "$APP_ALIVE" != "1" ]` **成立** ⇒ 判红 |
  | `BACKEND_KIND` | 抽到 `backendKind=x11` | `case` 三档**不匹配** ⇒ 判红 |
  | `PANEL_EDGE` | 抽到 `panelEdge=top` | `case` 五档**不匹配** ⇒ 判红 |
  | `MODEL` | 抽到 `odel=…` | 逐条 `grep -qx` **都不匹配** ⇒ 判红 |
  | `dpi_b_dpr` | 抽到 `devicePixelRatio=2` | `awk '$1+0 >= 2'` ⇒ 0 < 2 ⇒ 判红 |
  | `DEPRECATED_NAMES` | 改成匹配别的键 | 「**数量自洽**」断言 ⇒ 判红（实测三种变体全红） |
  | `ICON_THEME` | 抽到 `Theme=…` | ⚠ 它只是**开关**（有主题才查缺失数）⇒ 自身无牙，但 `ICON_MISSING` 那侧**已补格式校验** ⇒ **危害被兜住** |

  ⇒ ⚠ **结论**：批 DJ 之后**判据层已无「只有非空检查」的同类洞**；
- ⚠ `ICON_MISSING` 在**有图标主题的真机**上本来就会红（`Missing=0` ≠ `0`）
  ⇒ 本批记的是**离屏 CI 环境**里的覆盖面缺口；
- ⚠ **「条件合法但恒真」静态分析抓不到**（如 `if [ "$a" = "$a" ]`）
  ⇒ 需变异测试才暴露 ⇒ **明确不做**；
- ⚠ **「同时改基线 + 删门项」** ⇒ 批 CR 已把成本升到 4 处协同编辑
  ⇒ **完全堵死做不到**；
- ⚠⚠⚨ **顺带查出的弱洞（如实记下，判定为「不值得单开一批」）**：
  审计器的 `RX_ARG_IDX`（门型 → 正则参数位置的**登记册**）用
  `RX_ARG_IDX.get(kind)` 取值 ⇒ **拿不到就 `continue`（静默跳过）**
  ⇒ 实测：删掉 `arch_need_count` 那一项 ⇒ 那个门型的**所有正则体检被静默关掉**
  ⇒ ⚠ 但**接线门自己**兜住了大半（坏正则照样红 ⇒ rc=8）
  ⇒ ⇒ **危害有限** ⇒ 记为弱洞，**不单开一批**（若哪天体检成了唯一防线，再收）。

### E.2bt D2 散值豁免表不许被悄悄加宽（批 DK）

**① 起因（实测坐实，不是推演）**

`ci-d2.sh` 的 `D2_EXEMPT` 豁免表**只自检两件事**：

| 自检项 | 覆盖什么 | 覆盖不到什么 |
|---|---|---|
| 每条路径**存在** | 路径写错 ⇒ 红 | ⚠ **加宽**（加一条**存在**的路径）⇒ 绿 |
| `fix` 项**命中数 > 0** | 归零 = 该删了 | ⚠ **`keep` 项的条数与内容**完全没人管 |

⚠⚠⚨ **实测坐实的洞**：加宽一条（加一条**存在**的路径 `src/app/AppModel.cpp`）
⇒ **11 条 → 12 条** ⇒ ⚠⚠⚨ **`ci-d2.sh` 自己仍然 rc=0**
（还打印「✓ D2 命中 0/0（存量已清零，DS 单一真相源）」）
⇒ ⚠⚠⚨ **真洞坐实** ⇒ 那个文件从此**整份**被豁免 ⇒ 里面的散值**没人查**。

⚠⚠⚨ **为什么五套机制全都抓不到**：
恒真探针盯「条件本身是不是恒真」；孤儿探针盯「脚本在不在 CI 里」；
审计器审「门项有没有命中 0 次」；盘点盯「未验证出口」；
D2 门自己盯「散值命中数」⇒ ⚠⚠⚨ **被改弱的既不是门项、也不是判定逻辑，
是「**豁免表本身**」** ⇒ 只能**逐条钉住**。

**② 修法（12 条门：11 条逐条 + 1 条总数）**

- **逐条 11 条**：每条钉住「`路径|模式|`」前缀（**整行锚定**）
  ⇒ 路径被换 / 被删 / 被改成别的模式 ⇒ 命中 0 ⇒ 红；
- **总数 1 条**：数「`^[^|]*\|keep\|[^|]*$`」⇒ **恰好 11 处**
  ⇒ ⚠ **为什么两道腿都要**：逐条门盯「这一条还在」，
  总数门兜住「**同时删一条又加一条**」（逐条门会红，但**总数不变**
  ⇒ 总数门是「不许净增 / 净减」的**独立**护栏）⇒ 两道腿**互补**（批 DE·定）；
- ⚠ **正则一律从真实行现抽 + 程序化转义**（不手抄 ⇒ 零漂移）
  ⇒ 生成后**逐条自检**（命中 1 次 + 整行锚定 + 中段无**无界通配**）；
- ⚠⚠⚨ **踩到的坑**：逐条正则**只锚前缀不锚行尾** ⇒ 审计器的**锚定形态检查**
  判红（rc=8 ⇒ 门自审计红）⇒ 逐条也要锚行尾（理由是自由文本但实测**不含 `|`**
  ⇒ 用**有界**通配 `[^|]*` 收尾；⚠ 不可用 `.*` ⇒ 那是无界通配 ⇒ 批 BQ）。

**③ 落门 / 判据**

- **新增 12 条**（批 DK 独立段）；
- 原地替换 3 处：`ARCH_ANY_FAIL=1` 60 → 61、`ARCH_FAIL=0` 61 → 62、
  门项条数 1190 → 1202（门里那个数字 + 说明沿革）；
- 同步：门项总数基线 **1190 → 1202** ⇒ ⚠⚠⚨ **三处同改**。

**④ 负控 11/11 真红**

- **A 组 · 两棵树对照**（HEAD 整树 vs 本批树）：

| 树 | 接线门 | 审计器 | `ci-d2.sh` 自己 | 判定 |
|---|---|---|---|---|
| **A** = HEAD（无豁免表门） | 绿 | 绿 | ⚠ **绿** | ⚠⚠⚨ **假绿坐实**（豁免表被加宽而没人知道） |
| **B** = 本批树 | **红** | **红** | — | ⚠⚠⚨ **洞被堵住了** |

⇒ 三个变异（加宽 / 删一条 / 改审计器常量一处）+ 隔离 + 洁净度。

- **B 组 · 门级隔离**：删掉一条豁免路径 ⇒ 接线门红 + 审计器（`--list`）红
  （命中数失准）；
- **C 组 · 门项条数三处同改**：只改审计器常量一处 ⇒ 接线门红 + 审计器红；
- **D 组 · 洁净度**：harness 变异过的每个文件还原后**逐字节相同**；
  还原后接线门 / `ci-d2.sh` 仍全绿。

⚠ **harness 纪律沿用批 DJ 的教训**（不重复踩）：
① 备份路径与内容**必须分开存**（混存 ⇒ 还原报「文件名过长」）；
② `snapshot` **只在第一次取**（重复取 ⇒ 把已变异内容当基线 ⇒ 还原不回去）；
③ **启动前自检**（变异目标文本必须原样 ⇒ 否则测的是脏数据）；
④ 洁净度**只盯 harness 自己变异过的文件**（盯整个 `git diff` ⇒ 外部并发改动 ⇒ 假红）。

**⑤ 数字**

门项物理行数 **1190 → 1202**（+12）、执行次数 **1193 → 1205**（+12）；
门项总数基线 **1190 → 1202**（**三处**同步）；段级 trailer **60 → 61**；
`ARCH_ANY_FAIL=1` = **61**、`ARCH_FAIL=0` = **62**；
⚠ **恒真探针**：判定层 **396** 条判据不变、shell 与 python **892 → 893** 个条件
（**+1** = 批 DK 段末 trailer 在 `ci-wiring.sh` 里新增 1 处 `if` ⇒ ⚠ **探针会数到自己的
CI 接线文件** ⇒ **自指**，知情取舍）、断言实参 **99** 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**
（判定层 4 / shell 41 / python 5 / swift 5）；盘点 **21 组 / 73 处不变**；
孤儿探针 **32** 个断言脚本 / 白名单 **10** 条不变；
⚠ **CI 入口**：步数 **16**、失败上报 **38**、未验证计数点 **6** 均不变；
接线门 **1205** 项全绿、审计器硬门与报告模式 **rc=0**（门项 **1202/1202** 对基线、
**0 条**审计器盲区）、恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 11/11 真红**；累计 **1109/1109**。

**⑥ 已知边界（如实记着，不假装堵死）**

- ⚠ **本批只钉了 `keep` 项的条数与路径** ⇒ ⚠ **豁免理由（自由文本）**没被钉
  ⇒ 理由被改成误导性的文字 ⇒ 门不会红（⚠ 理由写得对不对**机器判不了**
  ⇒ 批 CJ 同款取舍）；
- ⚠ **豁免表是 `D2_EXEMPT` 这个多行变量** ⇒ 逐条门盯的是「路径|模式|」**前缀**
  ⇒ ⚠ 路径**后面的字段**（如理由里的 `|`）若被改动 ⇒ 前缀不变 ⇒ 逐条门仍绿
  （⚠ 但**总数门**仍绿 ⇒ 本批的覆盖范围**仅限路径与模式**）；
- ⚠ **同款洞可能还在别处** ⇒ 别处若也有「**只有存在性自检、没有条数自检**」的清单
  ⇒ 同款问题**依然存在** ⇒ ⚠ **不做「清单枚举器」**（机械标准会命中 237 条路径常量
  ⇒ 登记册不可维护 ⇒ 批 DI 已降级）；
- ⚠⚠⚨ **订正（批 DL 实测坐实）**：本段此前记着一条「实测副产物」——「变异时
  `ci-d2.sh` 会打 `D2_ARG_PATTERN: parameter not set` ⇒ 说明该脚本在 `set -u` 下
  对豁免表的行数敏感 ⇒ 值得后续单独查」。
  ⇒ ⚠⚠⚨ **那条结论是错的，现在撤回**：那是**我自己的负控变异**把 shell 的
  **闭引号夹在了文件中间**造成的**假象**，**不是产品缺陷**。
  ⇒ **实测坐实（批 DL · 两种写法对照，逐条跑过）**：

  | 变异写法 | `ci-d2.sh` 的 stderr | 退出码 |
  |---|---|---|
  | 闭引号留在**文件末尾**（`ANCHOR[:-1] + EXTRA`） | **空** | rc=0 |
  | 闭引号**夹在中间**（`old + EXTRA`） | `83: src/app/AppModel.cpp: Permission denied` / `D2_PATTERN: parameter not set` / `D2_ARG_PATTERN: parameter not set` | rc=0 |

  ⇒ **机制**（实测复现）：闭引号夹在中间 ⇒ **第 83 行落到引号之外** ⇒ 被**当成命令执行**
    （`src/app/AppModel.cpp|keep|批…` ⇒ 变成管道 ⇒ Permission denied / not found）
    ⇒ 它自己那个闭引号又把**后面几行**（含 `D2_PATTERN=` 的赋值）**吞进字符串**
    ⇒ 该变量**从未被赋值** ⇒ `set -u` ⇒ `parameter not set`
    ⇒ 而脚本末尾仍 `exit 0` ⇒ **看起来像个产品洞**。
  ⇒ ⇒ **新纪律（负控 harness）**：**变异不得破坏被测文件的语法**
    ⇒ 变异多行 shell 字符串时，**闭引号必须留在文件末尾**；
    ⇒ 变异后**必须先自证语法**（`sh -n` / `py_compile`）再跑；
  ⇒ ⇒ **台账纪律**：「实测发现」必须**真的实测过**，否则要**订正**
    ⇒ ⚠⚠⚨ **对产品的假指控（假红）比假绿更坏** ⇒ 宁可写「未验证」，不许写「实测」。

### E.2bu 审计器的「正则体检覆盖面」不许被悄悄缩小（批 DL）

**① 起因（实测坐实，不是推演）**

审计器的「门项正则写法体检」（`check_rx_syntax`，批 AX 引入）只体检**登记册
`RX_ARG_IDX` 里有的门型** ⇒ 覆盖面 = **那份手写登记册** ⇒ 而那份登记册
**全仓没有任何门在盯**（实测：`grep -n 'RX_ARG_IDX' scripts/ci-wiring.sh` = **零命中**）。

⚠⚠⚨ **实测坐实的假绿链**（两棵树对照 + 两种写法逐条实测）：

| 步骤 | 树 A（HEAD） | 树 B（本批） |
|---|---|---|
| 原样 | 审计器 rc=0 / 接线门 rc=0 | 审计器 rc=0 / 接线门 rc=0 |
| **坏正则**（`\d` ⇒ 门永远匹配不到）**并**协同把期望次数改成 0 | 审计器 **rc=5**（危险转义）**红** ⇒ 这道体检**有牙** | 审计器 **rc=5** **红** ⇒ 牙**没被改弱** |
| 再**删登记册里那一行** | ⚠⚠⚨ **审计器 rc=0 + 接线门 rc=0 ⇒ 全绿** ⇒ **假绿坐实** | 审计器 **rc=2** **红** ⇒ 洞被堵住 |

⚠⚠⚨ **为什么这条链值得单开一批**：坏正则要**同时**改期望次数才能骗过次数校准
⇒ 那本来需要**两处协同编辑** ⇒ 有可能被看见；⇒ 但**只要体检覆盖面被缩小**，
这道体检就**整个失效** ⇒ 那两处协同编辑**不再需要被人看见**
⇒ 一条「永远匹配不到任何东西」的门项就这么混过去了。

⚠⚠⚨ **而且登记册**已经**漂移**（不是假设，是现状）：在用门型 **15** 个，
登记册只覆盖 **12** 个 ⇒
- `arch_need_count_pair`（在用 **7** 条门项 / **14 个**正则实参）
  ⇒ ⚠⚠⚨ **从来没被登记** ⇒ 那 14 个正则**从来没被体检过**；
- `arch_forbid_han` / `arch_forbid_text_dup`（盯内容不看写法）
  ⇒ **本来就没有**正则参数 ⇒ 旧代码靠「取不到就跳过」把它们**一起**跳过了
  ⇒ ⚠ **「显式没有」与「漏登记」被混为一谈**
  ⇒ 这就是 fail closed 一直做不起来的**根因**。

**② 修法（三腿 + 一处自洽）**

- **补齐**：`RX_ARG_IDX` 登记 `arch_need_count_pair` ⇒ 值是**元组** `(1, 2)`
  （它有**两个**正则实参：报错行正则 + 计数行正则）
  ⇒ 登记册从「一个下标」升级为「**多个下标**」；
- **显式登记「没有正则参数」**：两个 `forbid` 门型登记为 `None`
  ⇒ 「显式没有」与「漏登记」**从此可区分**；
- **fail closed**：`RX_ARG_IDX.get(kind)` 取不到就 `continue`（**静默跳过**）
  ⇒ 改成**取不到必须报出来** ⇒ 审计器判红（**rc=2 盲区**：审计器看不见那一族门项的正则）；
- **两份登记册自洽自查**：`GATE_TYPES`（门型清单）派生的门型集合 vs `RX_ARG_IDX`
  的键集合 ⇒ **双向**比对 ⇒ 漏登记 ⇒ **rc=9**（未定义名族）⇒ 漂移即红；
- ⚠ **rc 语义只增不改**：`2` 从「盲区或缺文件」扩到「盲区：**或某族门项的正则体检被跳过**」；
  `9` 从「未定义名」扩到「未定义名**或门型清单与登记册对不上**」
  ⇒ **既有码值一个没动**，只补语义。

**③ 落门 / 判据**

- **新增 8 条**（批 DL 独立段）：逐字钉住 ① 登记册定义行 ② 配对门的登记
  ③ 两个「显式没有正则参数」的登记 ④ fail-closed 的判定分支 ⑤ 多下标支持
  ⑥ 下标解析函数 ⑦ 两份登记册的自洽自查 ⑧ 自洽自查的**调用点**；
- ⚠ **正则一律从真实行现抽 + 程序化转义**（不手抄 ⇒ 零漂移）
  ⇒ 生成后**逐条自检**（命中 1 次 + 整行锚定 + 中段无**无界通配**
  + **真 `grep -oE` 复核**）；
- 原地替换 5 处：`GATE_LINES_EXPECTED` **1202 → 1210**、基线文件 **1202 → 1210**、
  门里那个数字 **1202 → 1210**（**三处同改**）、`FAILS.append(9)` 计数 **4 → 5**、
  `FAILS.append(2)` 计数 **4 → 5**；
- 原地替换 2 处：段级 trailer 计数 `ARCH_ANY_FAIL=1` **61 → 62**、
  `ARCH_FAIL=0` **62 → 63**；
- 原地替换 2 处：接线门按 rc 分诊的文案（**rc=2** / **rc=9**）与实际行为对齐
  （⚠ **说明文字必须与实际行为一致**）。

**④ 负控 22/22 真红**

- **A 组 · 两棵树对照**（HEAD 整树 vs 本批整树）：删登记册一行
  ⇒ 树 A 审计器 **rc=0**（⚠ 假绿坐实）、树 B **rc=2**；
- **B 组 · 牙没被改弱**：坏正则（`\d`）+ 协同改期望次数 ⇒ 两棵树都 **rc=5**；
- **C 组 · 双重失守**：坏正则 + 删登记册 ⇒ 树 A **rc=0**（全绿假绿）、树 B **rc=2**；
- **D 组 · 门级隔离**：换删另一族（`arch_need_count_in_step`）⇒ 树 B **rc=2**
  且消息**指名道姓**那一族；
- **E 组 · 门级隔离（接线门侧）**：删 fail-closed 分支 / 多下标改单下标 /
  删自洽自查调用点 ⇒ 接线门各自**红在批 DL 那条门**上；
- **F 组 · 门项条数三处同改**：只改审计器常量一处 ⇒ 审计器 **rc=6** + 接线门红；
- **G 组 · 洁净度**：harness 变异过的文件还原后**逐字节相同**；
  还原后两棵树审计器仍 **rc=0**。

⚠ **harness 纪律**（沿用批 DJ/DK，不重复踩）：① 备份在变异**之前**取、备份路径与内容
**分开存**；② 启动前**自检**（变异目标文本必须原样）；③ 变异后**自己先自证**
（`sh -n` / `py_compile` ⇒ ⚠ **变异不得破坏被测文件的语法**）；④ 还原**整文件写回**
+ **逐字节**比对；⑤ 洁净度**只盯 harness 自己变异过的文件**；⑥ `atexit` 兜底还原。

**⑤ 数字**

门项物理行数 **1202 → 1210**（+8）、执行次数 **1205 → 1213**（+8）；
门项总数基线 **1202 → 1210**（**三处**同步）；段级 trailer **61 → 62**；
`ARCH_ANY_FAIL=1` = **62**、`ARCH_FAIL=0` = **63**；
审计器失败态计数：`FAILS.append(9)` **4 → 5**、`FAILS.append(2)` **4 → 5**；
⚠ **恒真探针**：判定层 **396** 条判据不变、shell 与 python **893 → 900** 个条件
（**+7** = 审计器里新增 5 处 `if`（下标解析 / 未登记判定 / 登记判定 / 两处 fail closed 判定）
+ 段末 trailer 1 处 ⇒ ⚠ **探针会数到自己的 CI 接线文件** ⇒ **自指**，知情取舍）、
断言实参 **99** 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**
（判定层 4 / shell 41 / python 5 / swift 5）；盘点 **21 组 / 73 处不变**；
孤儿探针 **32** 个断言脚本 / 白名单 **10** 条不变；
⚠ **CI 入口**：步数 **16**、失败上报 **38**、未验证计数点 **6** 均不变；
接线门 **1213** 项全绿、审计器硬门与报告模式 **rc=0**（门项 **1210/1210** 对基线、
**0 条**审计器盲区）、恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 22/22 真红**；累计 **1131/1131**。

**⑥ 已知边界（如实记着，不假装堵死）**

- ⚠ **配对门不在「整行锚定」检查的范围内**（`check_anchor_scope` 只遍历
  `arch_need_count`）⇒ ⚠ **这是语义使然，不是漏**：配对门的正则是**前缀式**
  （如 `echo "  ✗`）⇒ 要满足整行锚定就得写成 `^….*$` ⇒ 中段就有**无界通配**
  ⇒ 批 BQ 明令禁止 ⇒ 二者**不可兼得** ⇒ 配对门靠**次数校准 + 逐段配对**
  （批 BZ/CS）保证 ⇒ **如实记为边界**；
- ⚠ **陈旧登记只报不红**（登记了但没人用的门型）⇒ 多登记 = 体检范围更广 =
  **安全方向** ⇒ ⚠ **假红比假绿更坏** ⇒ 不判红；
- ⚠ **审计器只体检「正则参数」**：门项的**说明文字**（自由文本）**不体检**
  ⇒ 说明被改成误导性文字 ⇒ 门不会红（⚠ 理由写得对不对**机器判不了**
  ⇒ 批 CJ 同款取舍）；
- ⚠ **登记册只管「门型」这一层**：门型内部的**实参个数**由批 CO 的 arity 检查管
  ⇒ ⚠ **两处口径**（登记册说「哪个下标是正则」，arity 说「该有几个实参」）
  ⇒ 理论上可以「arity 过了但下标指错」⇒ ⚠ 但那种情况下体检会**扫到别的实参**
  ⇒ 不会静默失效 ⇒ **不单开一批**；
- ⚠ **同款洞可能还在别处** ⇒ 别处若也有「**手写登记册 + 零门在盯**」的清单
  ⇒ 同款问题依然存在 ⇒ ⚠ **不做「清单枚举器」**（批 DI 已降级：机械标准会命中
  237 条路径常量 ⇒ 登记册不可维护）。

### E.2bv 审计器的「判定函数」不许被掏空（批 DM）

**① 起因（实测坐实，不是推演）**

**勘察方法**：把审计器的判定函数逐个掏空成恒真（`return []` / `return None`）
⇒ 跑审计器与接线门 ⇒ **两套判据层都还绿 ⇒ 没人报警 ⇒ 那一族门项的校准静默失效**。

⚠⚠⚨ **实测结果（16 个候选）**：

| 掏空后 | 个数 | 谁在报警 |
|---|---|---|
| ⚠⚠⚨ **审计器 rc=0 + 接线门 rc=0 ⇒ 全绿假绿** | **13** | **没人** |
| 有人报警（红） | 3 | `anchoring_violation` ⇒ 靠它自己的**自检**（rc=8）；`check_anchor_scope` ⇒ 靠**反向配准**（rc=9）；`rx_arg_indices` ⇒ 靠**批 DL 的 fail closed**（rc=2） |

⚠⚠⚨ **关键观察**：三个被守住的里，**唯一靠「自检」的是 `anchoring_violation`**
⇒ 「自检」是本项目里**已验证有效**的机制（批 BF 立的：样例必须**既含「该判违规」
也含「不该判违规」** ⇒ 否则「永远判违规」也能过 ⇒ 自检没牙）。

⚠⚠⚨ **为什么这 13 个的死亡是「假绿」而不是「假红」**：它们是**校准层**
（把「门项的期望次数」与「实际命中数」对拍）⇒ 校准死掉 ⇒ 门项**照样在跑**
⇒ 门被改弱（期望次数被人改小、或目标文件被删了一行）时**没人发现**
⇒ 承诺**悄悄消失**。

**② 修法（一条规则挡住整类）**

- **规则**：判定函数（**名字以 `check_` 开头**）的 `return` 表达式里
  **必须至少有一个「名字」** ⇒ 返回字面量（`[]` / `None` / `True` / `0`）
  ⇒ 就是被掏空 ⇒ **必红**；
- **实现三件**：
  `check_judge_return_literals(tree)`（**判定逻辑只有一份**）+
  `check_judge_funcs_selftest()`（**自检**，6 个样例、两种极性都有）+
  `check_judge_funcs()`（体检）⇒ **自检的样例与实扫走同一条路径**；
- ⚠ **自动纳入**（口径 = `check_` 前缀 ⇒ **零名单维护**）
  ⇒ 新增判定函数自动受管 ⇒ 不存在「忘了登记」这一类漏；
- ⚠ **嵌套函数也算**（否则嵌套 helper 被掏空仍然静默）
  ⇒ 为此把逐段配对里的嵌套 `line_numbers` 改成返回 `(err, res)`（**含名字**）；
- ⚠ **两个判定函数改名**以进入口径：`bad_escapes` → `check_bad_escapes`、
  `pair_segment_bad` → `check_pair_segment_bad`；
- ⚠ **自检必须放最前**（批 BI 纪律）：前面的检查一红就 exit ⇒ 自检永远没机会跑；
- ⚠ **fail closed**：解析审计器自己失败 ⇒ 判红（不许「读不到就当没问题」）；
- ⚠ **rc=2（盲区）**：判定函数被掏空 ⇒ 那些门项**根本没被校准** ⇒ 盲区；
- ⚠⚠⚨ **规则自己**也受规则保护：实现规则的那两个函数**也改名成 `check_` 前缀**
  ⇒ 掏空规则 ⇒ **自检**的三条正样例不再被判违规 ⇒ 自检失败 ⇒ rc=2 ⇒ 红（**实测**）
  ⇒ 否则「规则可以被静默关掉」⇒ 整类洞照旧。

**③ 连带修掉两处「工具失败 ⇒ 静默跳过」**（批 CD/CH 纪律：未验证不许被当成通过）

| 位置 | 以前 | 现在 |
|---|---|---|
| 逐段配对（`check_pair_segment_bad`） | 工具失败 ⇒ 返回 `None` ⇒ **调用方跳过** ⇒ 那一族配对门的逐段配对**静默失效** | 工具失败 / 文件不存在 ⇒ **返回一条违规**（说清原因）⇒ 红 |
| 「切不出函数体 / 切不出步骤正文」 | `return []` ⇒ **整族校准静默消失** | **判红**（并说清「那一族门项根本没被校准」） |

**④ 落门 / 判据**

- **新增 9 条**（批 DM 独立段）：逐字钉住 ① 体检函数定义 ② 判定逻辑定义
  ③ 自检函数定义 ④ 判定口径那一行（「必须含名字」）
  ⑤ 「判定函数 = `check_` 前缀」口径行 ⑥ 自检的调用点 ⑦ 体检的调用点
  ⑧ `check_bad_escapes` 的定义 ⑨ 「工具失败必须判红」那一行；
- ⚠ **正则一律从真实行现抽 + 程序化转义**（不手抄 ⇒ 零漂移）
  ⇒ 生成后**逐条自检**（命中 1 次 + 整行锚定 + 中段无**无界通配**
  + **真 `grep -oE` 复核**）；
- 原地替换 2 条因改名而失准的门（`pair_segment_bad` 的定义门 + 调用点门）
  ⇒ **说明文字同步改**（批 BA/BB 纪律：说明文字必须与实际行为一致）；
- 原地替换 5 处：门项条数 **1210 → 1219**（**三处同改**）、
  `ARCH_ANY_FAIL=1` **62 → 63**、`ARCH_FAIL=0` **63 → 64**、
  `FAILS.append(2)` 计数 **5 → 6**；
- 原地替换 1 处：接线门按 **rc=2** 的**分诊文案**（补「判定函数被掏空」）。

**⑤ 负控 26 真红**

- **A 组 · 两棵树对照**（HEAD 整树 vs 本批整树）：**13 个**判定函数逐个掏空
  ⇒ 树 A（HEAD）**审计器 rc=0 + 接线门 rc=0**（⚠ **假绿坐实**）
  ⇒ 树 B（本批）**两套判据层都红**（⚠ **洞被堵住**）；
- **B 组 · 门级隔离**：只掏空 `check_count_gates` ⇒ 审计器红且消息**指名那一族**；
- **C 组 · 「工具失败 ⇒ 判红」**：注入 grep 失败 ⇒ 树 A **仍全绿**（静默跳过坐实）
  ⇒ 树 B **红**；
- **D 组 · 门项条数三处同改**：只改审计器常量一处 ⇒ 审计器红 + 接线门红；
- **F 组 · 规则自己受规则保护**：掏空规则函数 ⇒ 审计器红（**自检**抓到规则自己）；
- **E 组 · 洁净度**：harness 变异过的文件还原后**与原始字节逐字节相同**；
  还原后两棵树审计器仍 **rc=0**。
- ⚠⚠⚨ **本批 harness 自己踩了两个坑并已修**（**负控必须自己先有牙**）：
  ① 掏空变异**没先还原** ⇒ 上一个候选的变异**叠**在下一个上面 ⇒ 隔离不干净
  ⇒ 修法：每次变异**先还原到原始字节**；
  ② 洁净度检查是「自己跟自己比」⇒ **空检查** ⇒ 修法：与**原始字节**逐字节比对。

⚠ **harness 纪律**（沿用批 DJ/DK/DL，不重复踩）：备份在变异**之前**取且与内容分开存、
启动前**自检**、变异后**自己先自证**（`py_compile` ⇒ ⚠ **变异不得破坏被测文件的语法**）、
还原**整文件写回** + **逐字节**比对、洁净度**只盯 harness 自己变异过的文件**、
`atexit` 兜底还原。

**⑥ 数字**

门项物理行数 **1210 → 1219**（+9）、执行次数 **1213 → 1222**（+9）；
门项总数基线 **1210 → 1219**（**三处**同步）；段级 trailer **62 → 63**；
`ARCH_ANY_FAIL=1` = **63**、`ARCH_FAIL=0` = **64**；
审计器失败态计数：`FAILS.append(2)` **5 → 6**；
⚠ **恒真探针**：判定层 **396** 条判据不变、shell 与 python **900 → 907** 个条件
（**+7** = 审计器里新增的 `if` 条件（AST 判定 + 自检 + 逐段配对改造）⇒
⚠ **探针会数到自己的 CI 接线文件** ⇒ **自指**，知情取舍）、断言实参 **99** 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**；
盘点 **21 组 / 73 处不变**；孤儿探针 **32** 个断言脚本 / 白名单 **10** 条不变；
⚠ **CI 入口**：步数 **16**、失败上报 **38**、未验证计数点 **6** 均不变；
接线门 **1222** 项全绿、审计器硬门与报告模式 **rc=0**（门项 **1219/1219** 对基线、
**0 条**审计器盲区）、恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 26 真红**；累计 **1157**。

**⑦ 已知边界（如实记着，不假装堵死）**

- ⚠ **规则只抓「返回字面量」这一种掏空形态** ⇒ `return bad if x else []`
  （IfExp，含名字）**不被规则抓到** ⇒ 但 `if False` 那类恒假条件**恒真探针**能抓
  ⇒ 两层仍有残余 ⇒ ⚠ **如实记为边界**；
- ⚠ **规则只覆盖审计器自己**的 `check_*` 函数 ⇒ 其它判据脚本
  （恒真探针 / 孤儿探针 / 两个盘点脚本）的判定函数**不在口径内**
  ⇒ ⚠ **下一批候选**（同款掏空扫面可以在它们身上再跑一遍）；
- ⚠ **嵌套函数也算** ⇒ 将来若给某个判定函数写一个「返回字面量」的合法辅助函数
  ⇒ 会被红 ⇒ 需**显式改口径**（fail closed 方向 ⇒ 不漏 ⇒ 只是要改）；
- ⚠ **规则不管「判定体被逐点改弱」**（如 `if got != want:` → `if got > want:`）
  ⇒ ⚠ 但多数这类改动**会被门自身报红**（期望次数与实际不符 ⇒ 门红）⇒ 残余风险有限；
- ⚠ **判定函数改名 ⇒ 旧名的门会红**（这是**有意**的 ⇒ 逼着人同步说明文字）；
- ⚠ **自检本身**只被「定义 + 调用点」两道门钉住 ⇒ 它的**判定体**被改弱仍可能
  ⇒ 但**主规则**不依赖自检（自检只保护规则本身）⇒ 残余风险有限。

### E.2bw 判据脚本的「抽取器 / 自检」不许被静默关掉（批 DN）

**① 起因（实测坐实，不是推演）**

**勘察方法**：把**其它**判据脚本的判定函数逐个掏空（在其函数体首行插一句提前 `return`）
⇒ 跑该脚本与接线门 ⇒ **两套判据层都还绿 ⇒ 没人报警 ⇒ 那一族检查静默失效**。

⚠⚠⚨ **实测结果（27 个候选）**：

| 掏空后 | 个数 | 谁在报警 |
|---|---|---|
| ⚠⚠⚨ **脚本 rc=0 + 接线门 rc=0 ⇒ 全绿假绿** | **3** | **没人** |
| 有人报警（红） | 24 | 恒真探针的多数判定函数靠它**自己的自检**；两个盘点靠**登记册反查**；孤儿探针的判定行被**整行门**钉住 |

⚠⚠⚨ **3 个真洞**：

| 洞 | 在哪 | 掏空后静默失效的是 |
|---|---|---|
| ① | `ci-tautology-check.py::python_if_conds`（python 侧条件抽取器） | python 侧的**捷径**检查（`if x and False:`）整片 |
| ② | `ci-tautology-check.py::heredoc_spans`（heredoc 体抽取器） | heredoc 里的内嵌脚本（python / awk）整片 |
| ③ | `ci-true-audit.py::selftest_strip_parity`（那道自检**本身**） | 「两侧剥注释口径必须一致」那道自检 |

⚠⚠⚨ **洞的形状 = 批 DF 同款**：**自检没有一条样例真的经过被测的抽取器**
⇒ 抽取器坏了 ⇒ 自检照样绿 ⇒ 那一整片**不被查**而门全绿 ⇒ 承诺**悄悄消失**。

⚠ **勘察方法本身踩过的坑（如实记着）**：scratch 树**必须复制整个仓根**
（含 `macos/` / `assets/` / `linux/`）⇒ 只复制 `deepin/` ⇒ 恒真探针在树上**本就红**
⇒ 扫面结果**无效**。这是批 DN 开工前就踩到并修好的。

**② 修法（两腿）**

- **腿 1 · 两个抽取器补上「自检真的经过它」的两档样例**（批 DF 同款）
  - 新增 `py_extract` 档 ⇒ 走 `python_if_conds`；
  - 新增 `heredoc_extract` 档 ⇒ 走 `heredoc_spans`；
  - ⚠ 每档**两条样例**：一条「该抽到 N 条」、一条「不该抽到 0 条」
    ⇒ ⚠ **只测一边 ⇒ 判反了也能过** ⇒ 自检没牙（批 BF 纪律）；
  - ⚠ `heredoc_spans` 收的是**行列表** ⇒ 那一档自己切行；
- **腿 2 · 审计器新增「自检函数不许被掏空」的跨脚本体检**
  （`check_self_test_funcs` ⇒ 判定口径三条腿）：
  - ① **自检函数**（名字含 `selftest` / `self_test`）**不许有提前 return**
    ⇒ 提前 return 就是「掏空」⇒ 必红；
  - ② **自检的宿主**（`check_` 前缀**且函数体里调用了**自检函数）**同样不许**
    ⇒ 否则「在跑自检之前先 return」⇒ 自检**根本没机会跑**而门全绿；
  - ③ 自检函数**一条 return 都没有** ⇒ 也算被掏空（自检必须给出结论）；
  - ⚠ **跨脚本**（扫 `deepin/scripts/*.py` 全部）⇒ **零名单维护**
    ⇒ 别的判据脚本里的自检也自动受管；
  - ⚠ **fail closed**：列不出目录 / 解析失败 ⇒ 判红（不许「读不到就当没问题」）；
  - ⚠ **规则自己也被规则保护**（本函数名字含 `self_test` ⇒ 它自己也在口径内）；
  - ⚠ **嵌套函数不算**（嵌套 helper 的多个出口是正常写法 ⇒ 混进来会判得过宽 ⇒ 假红）。

**③ 连带改掉一处「提前 return」**（腿 2 的前提，不是顺手重构）

`check_judge_funcs` 原来在 except 分支里提前 `return bad` ⇒ 它是
`check_judge_funcs_selftest` 的**宿主** ⇒ 按腿 2 ② 必须**不许提前 return**
⇒ 改成 `try/except/else` ⇒ 语义等价、但不再有提前出口。
⚠ 这一处**不是可有可无的整理**：不改 ⇒ 腿 2 ② 会把它判红 ⇒ 规则自己先失效。

**④ 落门 / 判据**

- **新增 15 条**（批 DN 独立段）：
  - 8 条盯腿 1：两个档位的分派行 2 + 两个抽取器调用行 2 + 4 条样例行；
  - 7 条盯腿 2：名字口径常量 + 判定函数定义 + 适用范围判定行
    + 名字口径判定行 + 「提前 return」判定行 + 两个调用点（审计模式 / 报告模式）；
- ⚠ **正则一律从真实行现抽 + 程序化转义**（不手抄 ⇒ 零漂移）
  ⇒ 生成后**逐条回验**（命中 1 次 + 整行锚定 + 中段无**无界通配**
  + **真 `grep -oE` 复核**）；
- ⚠ **字面单引号写成 `.`**（批 BL 约定：正则参数用单引号包裹 ⇒ 不能含字面单引号）；
- 原地替换 5 处：门项条数 **1219 → 1234**（**三处同改**）、
  `ARCH_ANY_FAIL=1` **63 → 64**、`ARCH_FAIL=0` **64 → 65**、
  `FAILS.append(2)` 计数 **6 → 7**；
- ⚠ **原地替换 1 处 rc=2 的分诊文案**：补上「**有自检函数被掏空**」
  ⇒ 批 DN 的第 ⑦ 种失败态**也落在「盲区」那一档** ⇒ 不补 ⇒ 读日志的人
  **被指向错误的方向**（排障被带偏，批 CC/BS 纪律）
  ⇒ ⚠ 批 DM 当年为「判定函数被掏空」补过一次 ⇒ **同款口径**；
- ⚠ 段级计数那条门的说明文字**顺带订正**：原文写「清零 59 处 ⇒ 记红也必须 59 处」
  ⇒ 实际早已是 64/64 ⇒ **说明与实际行为不一致** ⇒ 一并改成当前真值
  （⚠ 假红比假绿更坏 ⇒ 说明不准会逼着人把承诺改弱）。

**⑤ 负控 11 真红**

- **A 组 · 3 个洞逐个**：掏空 `python_if_conds` ⇒ **恒真探针 rc=1**（自检当场红）；
  掏空 `heredoc_spans` ⇒ **恒真探针 rc=1**；掏空 `selftest_strip_parity`
  ⇒ **审计器 rc=2 + 接线门 rc=1**（指名道姓：哪一行、哪个函数）；
- **B 组 · 门级隔离（关键）**：把两个抽取器自检档写成 `got = True`
  ⇒ ⚠⚠⚨ **探针照样绿**（假绿坐实：样例断言被写死）
  ⇒ **只有**批 DN 段那两条门红 ⇒ 证明「门」与「探针」各管一段、不是互相顶替；
- **C 组 · 规则自己被掏空**：把「提前 return」判定行改成 `early = []`
  ⇒ ⚠⚠⚨ **审计器对掏空自检不再报错**（洞重新打开而没人知道）
  ⇒ **只有**批 DN 段那条门红；
- **D 组 · 口径被改窄**：名字口径常量改成只留 `self_test`
  ⇒ `selftest_strip_parity` **掉出口径** ⇒ ⚠⚠⚨ **实测比预想更强**：
  **审计器照样红**（rc=4 次数失准：那条门钉的是**常量的确切内容** ⇒ 命中 0 次）
  ⇒ 连同那条门一起红 ⇒ **口径没法被悄悄改窄**；
  ⇒ ⚠ 只有「**连那条门一起改**」的协同编辑才能绕过 ⇒ ⚠ **批 CR 同款已知边界**；
- **E 组 · 宿主调用点被摘**：改名调用点 ⇒ 审计器红（未定义名 / 崩）
  ⇒ 批 DN 段那条调用点门也红；
- **F 组 · 门项条数三处同改**：**只改**审计器常量 / **只改**基线文件 /
  **只改** `ci-wiring.sh` 里那条门 ⇒ 三种各红一次（批 CR 纪律）；
- **G 组 · 洁净度**：harness 变异过的文件还原后**与原始字节逐字节相同**，
  且**真仓**（不是 scratch 树）**未被负控碰过**。

⚠ **harness 纪律**（沿用批 DJ/DK/DL/DM，不重复踩）：备份在变异**之前**取且与内容分开存、
变异后**自己先自证**（`py_compile` / `sh -n` ⇒ ⚠ **变异不得破坏被测文件的语法**）、
**每次变异前先还原到原始字节**、还原**整文件写回** + **逐字节**比对、
洁净度**只盯 harness 自己变异过的文件**、`finally` 兜底还原。

⚠⚠⚨ **本批 harness 自己踩了三个坑并已修**（**负控必须自己先有牙**）：
① `red_gates()` 里 `out = []` 把**参数**覆盖了 ⇒ 崩 ⇒ 修法：换变量名；
② N1/N2 的**期望写错**（以为接线门会跑探针 ⇒ 实际探针是 `ci.sh` 的独立步骤）
⇒ 修法：期望改成「探针红、接线门仍绿」⇒ ⚠ **假红比假绿更坏**（期望写错 = 自己骗自己）；
③ 洁净度里「真仓未被碰过」原本是**空检查**（查一个永远不存在的文件）
⇒ 修法：改成**与开工前的字节逐字节比**。

**⑥ 数字**

门项物理行数 **1219 → 1234**（+15）、执行次数 **1222 → 1237**（+15）；
门项总数基线 **1219 → 1234**（**三处**同步）；段级 trailer **63 → 64**；
`ARCH_ANY_FAIL=1` = **64**、`ARCH_FAIL=0` = **65**；
审计器失败态计数：`FAILS.append(2)` **6 → 7**（第 ⑦ 种失败态 = 自检函数被掏空）；
⚠ **恒真探针**：判定层 **396** 条判据不变、shell 与 python **907 → 919** 个条件
（**+12** = 审计器里新增的 `if` 条件（跨脚本自检体检 + 它的三个 helper）
⇒ ⚠ **探针会数到自己的 CI 接线文件** ⇒ **自指**，知情取舍）、断言实参 **99** 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**；
盘点 **21 组 / 73 处不变**；孤儿探针 **32** 个断言脚本 / 白名单 **10** 条不变；
⚠ **CI 入口**：步数 **16**、失败上报 **39**、未验证计数点 **6** 均不变；
接线门 **1237** 项全绿、审计器硬门与报告模式 **rc=0**（门项 **1234/1234** 对基线、
**0 条**审计器盲区）、恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 11 真红**；累计 **1168**。

**⑦ 已知边界（如实记着，不假装堵死）**

- ⚠ **腿 1 的两档只数「抽到几条」** ⇒ 「**抽错内容但条数不变**」
  （如把 `python_if_conds` 的正则改宽/改窄到抽出别的条件）**不被抓**
  ⇒ ⚠ 那种改动多半也让**实扫**判错 ⇒ 但判错**不被报** ⇒ 残余风险有限；
  ⇒ ⚠ 要彻底堵住得让自检走**整条实扫路径**（批 DA/DF 的口径）
  ⇒ ⚠ **本批不做**（改动面大 ⇒ 引入新错的概率高 ⇒ 宁可如实记着，另批评估）
  ⇒ **不假装已经堵死**；
- ⚠ **腿 1 只覆盖这两个抽取器** ⇒ 恒真探针里**别的**抽取器
  （如 `extract_check_conds` 之外的 `swift_if_conds`）**没有被同款自检覆盖**
  ⇒ ⚠ 那些靠**别处**的自检或门守（`swift_if_conds` 有 `swift_e2e` 档）
  ⇒ **不做「抽取值枚举器」**（批 DI 已降级：机械标准命中太多路径常量 ⇒ 登记册不可维护）；
- ⚠ **腿 2 的口径是「名字」** ⇒ 一个自检函数若**改名**到不含 `selftest` / `self_test`
  ⇒ **自动掉出口径** ⇒ ⚠ 只能靠**别的门**（调用点门 / 登记册）发现 ⇒ 残余风险有限；
  ⇒ ⚠ **口径常量本身**被改窄 ⇒ **审计器立刻红**（rc=4 次数失准：那扇门钉的是**常量的确切内容**）
  ⇒ ⚠ 只有「**连那扇门一起改**」的协同编辑才能绕过 ⇒ ⚠ **批 CR 同款已知边界**
  （完全堵死做不到 ⇒ 如实记着）；
- ⚠ **腿 2 只抓「提前 return」与「没有 return」两种掏空形态**
  ⇒ 「把判定体改成恒真」（如 `early = []`）**不被腿 2 抓**
  ⇒ ⚠ 但**批 DN 段那几条门**逐字钉住了判定行 ⇒ 改判定体会红 ⇒ 残余风险有限；
- ⚠ **腿 2 只覆盖 `deepin/scripts/*.py`** ⇒ `linux/scripts/` 与 `macos/scripts/`
  里的 python 脚本（若有）**不在口径内** ⇒ ⚠ **下一批候选**；
- ⚠ **规则跨脚本 ⇒ 它会读别的脚本的 AST** ⇒ 那个脚本**语法坏了** ⇒ 本规则会
  **判红**（fail closed 方向 ⇒ 不漏 ⇒ 只是要改）；
- ⚠ **「自检的宿主」靠「函数体里出现了自检函数名」判定** ⇒ 若宿主**间接**调用
  （经别的函数转调）⇒ **不被识别** ⇒ 残余风险有限（当前仓内没有这种写法）；
- ⚠ **「不许提前 return」会误伤「合法早退」的写法** ⇒ 将来若要给某个自检函数
  写「跑不完就早退」的逻辑 ⇒ 会被红（fail closed 方向 ⇒ 需**显式**改口径）；
- ⚠ **探针的 `python_if_conds` 只看顶层 `if`**（批 DA 口径）⇒ 嵌套在函数里的
  `if` **不被数** ⇒ ⚠ **自指**：腿 1 的自检档本身**不被**恒真探针检查到
  ⇒ 但**腿 1 的门**逐字钉住了那几行 ⇒ 残余风险有限。

### E.2bx 审计器自己的「失败态上报」不许被静默关掉（批 DO）

**① 起因（实测坐实，不是推演）**

批 DM 的规则只管 `check_` 前缀**函数**里的 `return`
⇒ **main_body 里的内联判定是一个逃逸口**。

⚠⚠⚨ **实测（scratch 树复制整个仓根）**：

| 步骤 | 审计器 | 接线门 | 说明 |
|---|---|---|---|
| 基准 | rc=0 | rc=0 | 绿 |
| 步骤 1：制造一个**真盲区**（从门型登记册 `GATE_TYPES` 摘一条） | **rc=2** | rc=1 | ✅ 正确报警 |
| ⚠⚠⚨ **步骤 2：真盲区 + 把 `if g[blind]:` 改成恒假** | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **全绿假绿** |

⇒ 「**审计器自己有盲区**」这件事可以**被无声地关掉**
⇒ 那类门项**从来没被审** ⇒ **彻底没人知道** ⇒ 承诺**悄悄消失**。

⚠⚠⚨ **洞的形状**：main_body 里的失败态判定是**内联**的 ⇒ **四道机制全都够不着**：

1. 批 DM 的 AST 规则 ⇒ 只管 `check_` 前缀**函数**里的 `return` ⇒ **够不着**；
2. 批 DN 的规则 ⇒ 只管**自检函数** ⇒ **够不着**；
3. 恒真探针 ⇒ 只查**恒真**条件，**不查恒假**（`if False:` 那种）⇒ **够不着**；
4. `ci-wiring.sh` ⇒ **没有门**钉住那几行 ⇒ **够不着**。

**② 修法（两腿）**

- **腿 1 · 一条零名单维护的 AST 规则**（`check_fail_guards`）：
  - ① 每个 `FAILS.append(rc)` 调用点**必须有守卫**
    （最内层 `if` 的条件；或处在 `except` 里 —— 崩了的兜底）
    ⇒ 没有守卫 ⇒ 那个失败态**恒定触发** ⇒ 必红；
  - ② 守卫条件**只许「名字 / 下标」两种形态**
    ⇒ **不许**取反（`if not x:` ⇒ 判定被**反过来**）
    / 与或（`if a and b:` ⇒ 判定被**改窄**）
    / 比较（`if x == 0:`）/ 调用（`if g.get('blind'):`）
    / 布尔字面量（`if False:` ⇒ 判定被**关掉**）
    ⇒ 守卫的职责是「**取出一个判定结果**」⇒ 写成常量或表达式
    ⇒ 就是在**改判定** ⇒ 必须走门 ⇒ **逼着人同步**；
  - ⚠ **零名单维护**：扫全文件所有 `FAILS.append` 调用点 ⇒ 不用维护名单；
  - ⚠ **fail closed**：解析不了审计器自己 ⇒ 判红；
  - ⚠ **规则自己也被规则保护**（批 DM 口径：判定函数不许被掏空）；
  - ⚠ 口径 ② 会**误伤**将来合法的写法（如 `if len(x) > 0:`）
    ⇒ 那是**有意的**：要写成那样 ⇒ 必须**显式**改口径（⇒ 门钉住 ⇒ 逼着人同步）
    ⇒ fail closed 方向；
- **腿 2 · 口径 ③ 与口径 ④**（把「换指向」与「挪走」也挡住）：
  - **口径 ③ · 守卫不许重复**：每个失败态各有**自己的**判定结果 ⇒ 两个收集点用
    同一个守卫 ⇒ 其中的一个**指错了判定**（形态仍是「名字 / 下标」⇒ 口径 ② 抓不到）
    ⇒ 那一类失败**不再上报**而没人知道 ⇒ 必红；
  - **口径 ④ · 守卫登记册**（**双向红**）：
    「用到的守卫」不在册里 ⇒ 新增失败态忘了登记 ⇒ 红；
    「册里的守卫」没被用到 ⇒ 那个收集点**被挪走 / 删了** ⇒ 红
    ⇒ ⚠ 这一条抓的是「挪进一个**以变量为条件**的少真分支」
    （新守卫**仍是名字** ⇒ ② 不抓、③ 不重复 ⇒ 只有它抓得住）。
- ⚠⚠⚨ **本批原设计的「腿 2：各 rc 的收集处计数门」⇒ 撤掉**：实测发现**批 CQ 早就有**
  （`ci-wiring.sh` 里 rc=4/5/6/7/8/9 各一条）⇒ ⇒ 本批那 6 条是**重复门**
  ⇒ ⇒ **判定逻辑只有一份 ⇒ 不重复加** ⇒ 撤掉（那一腿的**牙本来就有**）。

**③ 连带改掉两处「取反的守卫」**（腿 1 口径 ② 的前提，不是顺手重构）

`if not anchor_exempt_exists:` 与 `if not exempt_exists:` ⇒ 口径 ② **不许取反**
⇒ 改成先算好 `anchor_exempt_missing` / `exempt_missing` 再守卫 ⇒ 语义等价。
⇒ ⚠ 不改 ⇒ 腿 1 会把**这两处判红** ⇒ 规则自己先失效。

**④ 落门 / 判据**

- **新增 10 条**（批 DO 独立段）：
  - 6 条盯新规则（口径常量 + 判定函数定义 + 形态判定行 + 「没有守卫」判定行
    + 两个调用点）；
  - 1 条盯口径 ③ 的判定行；
  - 3 条盯口径 ④（登记册常量 + 「没被用到」那半 + 「不在册里」那半）；
  - ⚠ **各 rc 的收集处计数门** ⇒ **本来就有**（批 CQ）⇒ **不重复加**；
  - ⚠ rc=2 那条**已存在** ⇒ 原地改 7 → 8（并补上第 ⑧ 种失败态）；
- ⚠ 门项正则**从真实行现抽 + 程序化转义**（不手抄 ⇒ 零漂移）
  ⇒ 生成后**逐条回验**（命中 1 次 + 整行锚定 + 中段无**无界通配**
  + **真 `grep -oE` 复核**）；
- ⚠ **字面单引号写成 `.`**（批 BL 约定：正则参数与说明文字都用单引号包裹
  ⇒ 说明文字里**也不能**有字面单引号 ⇒ 措辞必须绕开
  ⇒ ⚠ **本批实测踩到**：第一版说明文字里写了 `if g[blind]:` ⇒ 直接踩 ⇒ 改措辞）；
- 原地替换 5 处：门项条数 **1234 → 1244**（**三处同改**）、
  `ARCH_ANY_FAIL=1` **64 → 65**、`ARCH_FAIL=0` **65 → 66**、
  `FAILS.append(2)` 计数 **7 → 8**；
- ⚠ rc=2 那条门的说明文字**顺带补上第 ⑧ 种失败态**
  （失败态上报被静默关掉）⇒ 八种失败要分开 ⇒ 不补 ⇒ 排障被带偏。

**⑤ 负控 14 真红**

- **A 组 · 核心（修前假绿的那个）**：真盲区 + 守卫被掏空 ⇒ **审计器 rc=2**
  ⇒ **指名道姓**：哪一行、守卫形态是什么；
- **B 组 · 掏空形态全抓**：`if False:` / `if g.get(...)` / `if a and b:`
  / `if not x:` / `if x == 0:` / `if 0:` ⇒ 每一种都红
  ⇒ ⚠⚠⚨ **实测 8/8**（含另一处守卫 + **换指向**）；
- **C 组 · 收集点被删**：删掉一处 rc=9 的收集点 ⇒ **次数门红**；
  删掉一处 rc=4 的收集点 ⇒ ⚠⚠⚨ **实测到一个「自指」**：审计器自己**报得出**
  「次数门没配准」，但**报不出 rc=4**（因为 rc=4 的收集点就是被删的那一处）
  ⇒ ⇒ 抓它的是**两处**：① **口径 ④**（那个守卫**没被用到** ⇒ 登记册红 ⇒ 审计器 rc=2）
  ② **接线门**的 rc=4 计数门（批 CQ 那条）⇒ ⇒ 如实记着；
- **D 组 · 守卫换指向**（盲区那一档 ⇒ 换成总数那一档）⇒ **口径 ③ 红**
  （形态没变 ⇒ 口径 ② 抓不到 ⇒ 只有 ③ 抓得住）；
- **E 组 · 收集点挪进少真分支**（`--list-all` 那支 ⇒ CI 路径永不进）
  ⇒ **口径 ④ 红**（登记册里的那个守卫**没被用到**）⇒ ⚠ 这一条只有 ④ 抓得住；
- **F 组 · 收集点挪到外层 if** ⇒ ⚠⚠⚨ **恒定触发 ⇒ 假红（不是假绿）**
  ⇒ 审计器**一直红** ⇒ 会被立刻发现 ⇒ ⚠ 只有挪进一个**以名字为条件**的少真分支
  才可能静默 ⇒ 那一支由 **E 组**兜住；
- **G 组 · 门项条数三处同改**：**只改**审计器常量 / **只改**基线文件 /
  **只改** `ci-wiring.sh` 里那条门 ⇒ 三种各红一次（批 CR 纪律）；
- **H 组 · 洁净度**：harness 变异过的文件还原后**与原始字节逐字节相同**。

⚠ **harness 纪律**（沿用批 DJ～DN）：scratch 树复制**整个仓根**；
备份在变异**之前**取；变异后**自己先自证**（`py_compile` / `sh -n`
⇒ ⚠ **变异不得破坏被测文件的语法**）；**每次变异前先还原到原始字节**；
还原**整文件写回** + **逐字节**比对；退出码**不经管道读**。

⚠⚠⚨ **本批 harness 自己踩了三个坑并已修**（**负控必须自己先有牙**）：
① 「有牙自证」脚本按 `find()` 定位 ⇒ 改到了**新规则 docstring 里的同名串**
⇒ 看起来「没抓到」⇒ 真相是**改错了地方** ⇒ 修法：按**行**定位
⇒ ⚠ **假红比假绿更坏**（自证脚本自己骗自己 ⇒ 比没有更糟）；
② 门项说明文字里写了**字面单引号** ⇒ shell 单引号包裹会破
⇒ 修法：措辞绕开（批 BL 约定的延伸 ⇒ **说明文字**同样不许有字面单引号）；
③ 新代码里的 `return True` / `return False` **撞上**了「全文件恰好 1 处
`return True`」那条门 ⇒ 失准 ⇒ 修法：改成标志变量 `return ok`
⇒ ⚠ **计数门是别人的承诺 ⇒ 改代码时必须先看它盯着什么**。

**⑥ 数字**

门项物理行数 **1234 → 1244**（+10）、执行次数 **1237 → 1247**（+10）；
门项总数基线 **1234 → 1244**（**三处**同步）；段级 trailer **64 → 65**；
`ARCH_ANY_FAIL=1` = **65**、`ARCH_FAIL=0` = **66**；
审计器失败态计数：`FAILS.append(2)` **7 → 8**（第 ⑧ 种失败态 = 失败态上报被静默关掉）；
各 rc 的收集处：**rc=2 8**、rc=4 **1**、rc=5 **2**、rc=6 **1**、rc=7 **1**、
rc=8 **2**、rc=9 **5**（合计 **20** 处）⇒ ⚠ **这些计数门本来就是批 CQ 的**
⇒ 本批只把 **rc=2** 那条原地改了 7 → 8 ⇒ ⚠ 顺带**订正**批 CQ 那条 rc=9 的门
（说明写「恰好 4 处」而实际是 **5** 处 ⇒ 说明与实际行为不一致 ⇒ 一并改成真值）；
⚠ **守卫登记册**：**19** 个守卫（由收集点**现抽生成** ⇒ 不手抄 ⇒ 零漂移）；
⚠ **恒真探针**：判定层 **396** 条判据不变、shell 与 python **919 → 928** 个条件
（**+9** = 新规则里的 `if` 条件 ⇒ ⚠ **探针会数到自己的 CI 接线文件**
⇒ **自指**，知情取舍）、断言实参 **99** 条不变；
⚠ **Swift 侧** 469 条断言 + 144 处 if 条件**不变**；⚠ **扫描范围不变**；
盘点 **21 组 / 73 处不变**；孤儿探针 **32** 个断言脚本 / 白名单 **10** 条不变；
⚠ **CI 入口**：步数 **16** 不变；
接线门 **1247** 项全绿、审计器硬门与报告模式 **rc=0**（门项 **1244/1244** 对基线）、
恒真探针 **rc=0**、孤儿探针 **rc=0**、盘点对拍 **rc=0**；
⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**；
**负控 14 真红**；累计 **1182**。

**⑦ 已知边界（如实记着，不假装堵死）**

- ⚠⚠⚨ **口径 ①（「必须有守卫」）当前触发不到** ⇒ 现有 20 处收集点**全都**
  嵌在某个 `if` 里 ⇒ ⇒ 这一条**现在没有牙** ⇒ 它是**面向将来的**
  ⇒ ⚠ **不假装它现在就有用** ⇒ 现在的牙在 ② ③ ④ 三条腿上；
- ⚠ **口径 ② 只管 `FAILS.append` 的守卫** ⇒ **报告模式**里的打印点
  （那几处**不设 rc**、只给人看）**不在口径内** ⇒ 把它们掏空 ⇒ 报告模式会少报
  ⇒ ⚠ 但**硬门模式**（CI 路径）不受影响 ⇒ 残余风险有限；
- ⚠ **口径 ② 是「形态」判定、不是「语义」判定** ⇒ 守卫写成
  `if g['blind']:`（名字）但**那个字典项的值被改坏** ⇒ 抓不到
  ⇒ ⚠ 但值来自 `check_gate_totals()`（`check_` 前缀 ⇒ 批 DM 口径管着）
  ⇒ 残余风险有限；
- ⚠ **登记册（口径 ④）本身是「名单」** ⇒ 协同编辑（改登记册 + 挪收集点）⇒
  抓不到 ⇒ ⚠ **批 CR 同款已知边界**；
- ⚠ **口径 ③（不许重复）要求「每个失败态各有自己的判定」** ⇒ 将来若有两个失败态
  合法地共用一个守卫 ⇒ 会被红 ⇒ ⚠ 有意的（要那样写 ⇒ 必须**显式**改口径）；
- ⚠ **腿 1 只管审计器自己** ⇒ **别的判据脚本**（恒真探针 / 两个盘点 /
  孤儿探针）的**内联失败态判定**仍不在口径内 ⇒ **下一批候选**；
- ⚠ **口径 ② 会误伤将来合法的写法** ⇒ 有意的（要那样写 ⇒ 必须显式改口径）
  ⇒ fail closed 方向；
- ⚠ **口径 ① 允许 `except` 里的收集点无守卫**（崩了的兜底）⇒ 那处的守卫是
  「崩了」这件事本身 ⇒ ⚠ 若有人把 `except` 改成 `except Exception: pass` ⇒
  那条兜底就没了 ⇒ ⚠ **未被口径覆盖** ⇒ 残余风险有限（崩 ⇒ rc=10 专属码）。

### E.2by 判据脚本（审计器之外）的「失败态上报」不许被静默关掉（批 DP）

**① 起因（实测坐实，不是推演）**

批 DO 把「失败态上报不许被静默关掉」这件事**只管到审计器自己**
⇒ **别的判据脚本**的内联失败态判定**仍在口径外**
⇒ 那是批 DO 台账里**写明的已知边界**（「腿 1 只管审计器自己 ⇒ 下一批候选」）。

⚠⚠⚨ **实测（scratch 树复制整个仓根 · 4 组对照实验 + 1 组对照复现）**：

| 组 | 变异 | 制造的真洞 | 目标脚本 rc | 接线门 rc | 结论 |
|---|---|---|---|---|---|
| 基准 | — | — | rc=0 | rc=0 | 绿 |
| ⚠⚠⚨ **E1** | `ci-tautology-check.py` 的 **16 处 `bad += 1`** 全 → `bad += 0` | 往 `bootstrap-deps.py` 注入 `if True:`（恒真判据） | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **全绿假绿** |
| ⚠⚠⚨ **E2** | `ci-true-audit.py` 的 `sys.exit('✗ 登记册不存在…')` → `sys.exit(0)` | 藏起 `ci-true-audit.baseline` | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **全绿假绿** |
| **E3** | `ci-unverified-audit.py` 的多行 `sys.exit('✗ 登记册条数…')` → `sys.exit(0)` | 截短 `ci-unverified-audit.baseline` 一行 | ⚠⚠⚨ **rc=0** | rc=1 | 目标脚本**静默退出 0**（接线门**另有牙**） |
| **E4** | `ci-unverified-audit.py` 的 `sys.exit('✗ 登记册不存在…')` → `sys.exit(0)` | 藏起 `ci-unverified-audit.baseline` | ⚠⚠⚨ **rc=0** | rc=1 | 同上 |

⚠⚠⚨ **E1 的关键**：真洞（恒真判据）**照样打印到 stderr**，
但**退出码是 0** ⇒ 探针 rc=0 ⇒ **CI 第 16 步照样绿**
⇒ 那批判据**不再被查**而**彻底没人知道**。

⚠⚠⚨ **E2 的关键**：输出**完全为空**（不是「报了但码是 0」，是**一声不吭**）
⇒ 盘点脚本**静默成功** ⇒ 接线门（它**会跑**这个盘点）**也跟着绿** ⇒ **全绿假绿**。

⚠ **E3 / E4 为什么接线门仍红**：那两个真洞（登记册被藏 / 被截短）
**接线门另有门项钉住** ⇒ 假绿**只发生在目标脚本这一层** ⇒ 残余风险更小
⇒ 但**目标脚本那一层的承诺照样被静默关掉** ⇒ 仍要修。

⚠ **洞的形状**：这批洞**不是**「恒真」，是**「失败态上报被改弱 / 被摘掉」**：

1. 失败**计数**被加 0（`bad += 1` → `bad += 0`）⇒ 违规**不被计数** ⇒ 退出码恒 0；
2. 失败**出口**被改成 0 退出码（`sys.exit('✗ …')` → `sys.exit(0)`）⇒ 失败**不被报出来**；
3. 决定退出码的**守卫被取反**（`if bad:` → `if not bad:`）⇒ 失败**永远到不了**上报点。

⇒ 三种形态**都不在**任何现有机制的口径内：

1. 恒真探针 ⇒ 只查**条件恒真 / 恒假**（`if True:` / `if False:`）⇒ 抓不到 1、2；
2. 批 DN ⇒ 只管**自检函数** ⇒ 抓不到；
3. 批 DM ⇒ 只管 `check_` 前缀**函数**里的 `return` ⇒ 抓不到；
4. 批 DO ⇒ 只管**审计器自己** ⇒ 抓不到**别的脚本**；
5. `ci-wiring.sh` ⇒ **没有一条门**钉住这些失败上报点
   （只钉了 `return 1` 与 `sys.exit(main())`）⇒ 抓不到。

**② 修法（一条零名单维护的跨脚本 AST 规则）**

新增 `check_fail_report_points()`，扫 `deepin/scripts/*.py` 全部
（**审计器自己除外** ⇒ 排除项由**本文件名现算** ⇒ **零名单维护**）：

- **口径 ① · 失败出口不许以 0 退出**
  - 「失败出口」= `sys.exit(X)` 且 X **不是** `main()` 调用
  - X 是 `0` / `False` / `None` ⇒ 退出码 0 ⇒ 失败被报成成功 ⇒ **必红**
  - X 是字符串 ⇒ 退出码 1 ⇒ 合规；X 是 `%` 拼接 ⇒ 同理
  - ⚠ 其它形态（变量 / 调用）⇒ **静态判不了** ⇒ 放行（如实记为边界）
- **口径 ② · 失败计数增量不许是 0**
  - 「失败累加器」= 出现在「失败守卫」（body 里含 `return <非零>` 或 `sys.exit(…)`
    的 `if`）**测试**里的名字
  - 累加器上的 `X += <整数字面量>` ⇒ 增量必须 ≠ 0
- **口径 ③ · 决定退出码的守卫不许被改形**
  - 每个 `return 1`（rc=1 = 失败；**rc=2 = 用法错**，批 CC 立的约定 ⇒ 不在口径内）
    所在的**最内层 `if` 守卫**必须存在，且测试**只许「名字 / 下标」**
    ⇒ 取反 / 比较 / 与或 / 布尔字面量 一律红
  - ⚠ **复用批 DO 的 `_guard_shape_ok`** ⇒ 判定逻辑**只有一份**（批 BF/BG 纪律）
- **口径 ④ · 失败上报点不许被摘掉**（登记册**双向红**）
  - 登记册 `FAIL_REPORT_COUNTS` = ((脚本, 类别, 数量), …)
  - 类别：`fail_exit`（失败出口）/ `fail_ret`（失败返回）
    / `fail_count`（失败累加器上的**追加型写**：`X += …` 与 `X.append(…)`）
  - 「用到的」不在册 ⇒ 红；「册里的」实测数对不上 ⇒ 红
  - ⚠ 数量**现抽生成** ⇒ 不手抄 ⇒ 零漂移

⚠ **规则自己也被规则保护**（批 DM/DN/DO 同款）：本函数名字以 `check_` 开头
⇒ 批 DM 管它 ⇒ **只有一条 return**。
⚠ **fail closed**：列不出目录 / 解析失败 ⇒ 判红（不许「读不到就当没问题」）。
⚠ **新增的失败态收集点 `fr_bad`** ⇒ 按批 DO 的登记册纪律**必须登记**
⇒ `FAIL_GUARDS` 加一条（19 → **20**）⇒ rc=2 的收集处计数门 8 → **9**。

⚠⚠⚨ **本批自己踩到并已修的两个真缺口**（**关键判定必须整行锚定**）：

1. 口径①的**「退出码是不是 0」那个算式**起初没被任何门钉住
   ⇒ 把它改成 `v == 99` ⇒ 规则**静默失去牙**而没人知道
   ⇒ ⇒ 修法：三个形态（`None` / `False` / `0`）**收成一行** ⇒ **一条门**钉住它；
2. 口径②的**「失败累加器怎么算出来」那一行**（`accs.add(…)`）同样没被钉住
   ⇒ 删掉它 ⇒ 口径②的**作用域归零** ⇒ 规则静默失去牙
   ⇒ ⇒ **一条门**钉住它。

⇒ 这两条**不是**假想：批 AH~AX 纪律「**关键判定整行锚定**」⇒ 判定行必须被门盯住。

**③ 落门 / 判据**

- **新增 14 条**（批 DP 独立段，插在批 DO 段之后、批 CG 块之前）：
  - ① 范围排除项常量 `DP_SELF`（1 条）
  - ② 登记册常量 `FAIL_REPORT_COUNTS`（1 条）
  - ③ 判定函数定义 `check_fail_report_points` + 两个 helper
    （`_dp_zero_exit_code`）各 1 条（2 条）
  - ④ 两个调用点（审计模式 + 报告模式）各 1 条（2 条）
  - ⑤ 口径①的判定行 + **退出码判定算式**（2 条）
  - ⑥ 口径②的判定行 + **累加器推导行**（2 条）
  - ⑦ 口径③的「没有守卫」判定行 + 「守卫形态」判定行（2 条）
  - ⑧ 口径④的两半（「不在册里」/「数量对不上」）各 1 条（2 条）
- **原地替换 7 处**：
  - 门项条数 **1244 → 1258**（**三处同改**：基线文件 / 审计器常量 / 门项里的数字）
  - `ARCH_ANY_FAIL=1` 65 → 66、`ARCH_FAIL=0` 66 → 67
  - `FAILS.append(2)` 计数 8 → 9
  - 批 DO 的 `FAIL_GUARDS` 登记册门加 `fr_bad`（登记册 19 → 20）
  - rc=2 的**分诊文案**补第 **⑨** 种失败态
- ⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条回验
  （命中数 + 整行锚定 + 中段无**无界通配** + **真 `grep -cE` 复核**）；
- ⚠ **字面单引号写成 `.`**（批 BL 约定）；
- ⚠⚠⚨ **本批在门项正则上栽了两次**（都靠「现抽 + 回验」抓出来）：
  ① 漏转义一个左括号 ⇒ `grep: 不匹配的 ( 或 \(` ⇒ 门红
  ⇒ ⚠ **Python 的 `re` 能编译**（把它当分组）⇒ **审计器侧看不出来** ⇒ 只有 `grep -E` 才报错；
  ② 手抄缩进（12 空格 vs 真实 8 空格）⇒ 期望 1 ≠ 实际 0 ⇒ 门恒红
  ⇒ ⇒ 两条都印证「**正则绝不手抄**」。

**④ 负控 16 真红**

| 组 | 用例 | 结果 |
|---|---|---|
| A · 口径① | NC2 `sys.exit(✗…)` → `sys.exit(0)` | 审计器 rc=2，指名道姓「退出码变成 0」 |
| A · 口径② | NC1 `bad += 1` → `bad += 0` | 审计器 rc=2，指名道姓「增量是 **0**」 |
| A · 口径③ | NC3 `if bad:` → `if not bad:` | 审计器 rc=2，指名道姓「守卫条件形态不合规」 |
| A · 口径④ | NC4 `return 1` → `return 0` | 审计器 rc=2，「数量 1 ≠ 实测 0」 |
| A · 口径④ | NC5 删掉一处失败出口 | 审计器 rc=2，`fail_exit` 数量失配 |
| A · 口径④ | NC6 删掉一处失败计数点 | 审计器 rc=2，`fail_count` 数量失配 |
| A · 口径④ | NC7 新增失败上报点但不登记 | 审计器 rc=2，「数量 8 ≠ 实测 9」 |
| B · 关键判定门 | NC8 退出码判定算式改弱（`v == 0` → `v == 99`） | 接线门 rc=1，那条门红 |
| B · 关键判定门 | NC9 累加器推导行被删 | 接线门 rc=1，那条门红 |
| B · 门级隔离 | NC10 口径②判定行被摘 | 接线门 rc=1，那条门红 |
| B · 门级隔离 | NC11 口径①判定行被摘 | 接线门 rc=1，那条门红 |
| B · 门级隔离 | NC12 口径③守卫形态判定行被摘 | 接线门 rc=1，那条门红 |
| B · 门级隔离 | NC13 审计模式调用点被摘 | 接线门 rc=1，那条门红 |
| B · 门级隔离 | NC14 报告模式调用点被摘 | 接线门 rc=1，那条门红 |
| C · 条数三处同改 | NC15 只改基线文件 | 接线门 rc=1 |
| D · 对照实验 | NC16 真洞（注入 `if True:`）+ 掏空全部 `bad += 1` | **恒真探针仍 rc=0（仍是假绿 ⇒ 这就是被测的那个洞）** ⇒ 而**审计器 rc=2 报警** ⇒ 洞被抓住 |
| E · 洁净度 | 每个用例还原后与**原始字节**逐字节相同 | 16/16 洁净 |

⚠⚠⚨ **本批 harness 自己踩了四个错并已修**（⚠ **假红比假绿更坏** ⇒ 期望写错 = 自己骗自己）：

1. **审计模式用错了**：v1 跑的是 `ci-wiring-audit.py`（**报告模式** ⇒ rc **恒 0**）
   ⇒ CI 真正跑的是 **`--list`**（硬门模式）⇒ 改成 `--list`；
2. NC3 的锚点**打偏**：改到的是 `load_baseline()` 里那个 `if bad:`（fail-closed 守卫）
   ⇒ 口径③盯的是**决定退出码**的那个守卫 ⇒ 改锚点；
3. NC5 的变异**破坏了语法**（删掉 `if` 块里唯一那行）⇒ 改成替成 `pass`；
4. NC7 的**期望文案写错**：新增一处失败上报点 ⇒ 命中的是「数量 8 ≠ 实测 9」
   ⇒ **不是**「不在登记册里」（那个 (脚本, 类别) 组合本来就在册里）
   ⇒ 另外 harness 自己有个 `subprocess.Subprocess` 的笔误 ⇒ 改成 `CompletedProcess`。

**⑤ 数字**

- 门项 **1244 → 1258**（**三处同改**）；执行次数 **1247 → 1261**
- `ARCH_ANY_FAIL=1` **65 → 66**；`ARCH_FAIL=0` **66 → 67**
- `FAILS.append(2)` 收集处 **8 → 9**；**守卫登记册 19 → 20** 个守卫
- 恒真探针 shell+python 条件 **928 → 948**（+20 ⇒ 新代码里的 `if` 条件 ⇒ ⚠ **自指**，知情取舍）
- 判定层 **396** 不变；断言实参 99 条不变；Swift 469 条断言 / 144 处 if 不变
- 盘点 **21 组 / 73 处** 不变；孤儿探针 32 脚本 / 白名单 10 条 不变
- 接线门 **1261** 项全绿；审计器 `--list` rc=0（**1258/1258**）；报告模式 rc=0
  （判据脚本的「失败态上报被静默关掉」**0 处**）
- 恒真探针 rc=0、两个盘点 rc=0、孤儿探针 rc=0、D2 散值门 rc=0
- ⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）⇒ **如实记录**
- **负控 16 真红**；累计 **1198/1198**

**⑥ 已知边界（如实记着）**

- ⚠ **登记册（口径 ④）是「名单」** ⇒ 协同编辑（改登记册 + 挪/加失败上报点）⇒ 抓不到
  ⇒ ⚠ **批 CR / 批 DO 同款已知边界**；
- ⚠ **口径 ④ 只数「追加型写」** ⇒ 失败累加器的**布尔标志赋值**
  （`bad = True` → `bad = False`）**不在口径内** ⇒ 残余风险有限
  （那种写法当前只在 `ci-true-audit.py` 一处）；
- ⚠ **口径 ① 判不了「退出码不静态可知」的写法**（`sys.exit(变量)`）⇒ 放行；
- ⚠ **口径 ③ 只管「决定退出码的那个守卫」** ⇒ **fail-closed 出口的守卫**
  （`if not os.path.isdir(…):`）的**取反/改形不被抓**
  ⇒ 原因：那些守卫形态**多样**（取反 / 比较 / 调用）⇒ 统一约束会**误伤**
  ⇒ ⚠ 有意的（fail closed 方向）；
- ⚠ **口径 ③ 按 rc 语义划界**（rc=1 = 失败；rc=2 = 用法错）⇒ 将来若某脚本用
  rc=3 表达失败 ⇒ **自动在口径内**（≠2 即算）；
- ⚠ **范围只含 `deepin/scripts/*.py`** ⇒ `linux/` 与 `macos/` 侧的 python 脚本
  **不在口径内**（当前那两边**没有**判据用 python ⇒ 残余风险小 ⇒ **下一批候选**）；
- ⚠ **「失败累加器」靠「body 里含 `return <非零>` 或 `sys.exit(…)`」判定**
  ⇒ 若某个累加器的守卫只有 `bad.append(…)`（没有 return / exit）⇒ 它**不是**累加器
  ⇒ 其上的写**不被口径②盯** ⇒ 当前仓内没有这种写法；
- ⚠ **口径 ③ 会误伤将来合法的写法** ⇒ 有意的（要那样写 ⇒ 必须**显式**改口径）；
- ⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

### E.2bz 「命令替换内带 `|| true` 必须逐条登记」这条承诺不许只覆盖一半（批 DQ）

**① 起因（实测坐实，不是推演）**

批 CJ 立了常驻盘点 `ci-true-audit.py`：「shell 脚本里**命令替换内部**的 `|| true`
必须**逐条登记**」⇒ 登记册与实测**逐条相等** ⇒ 少一条 / 多一条都红。

⚠ 但那个盘点的**扫描范围只有 `deepin/scripts/`**
⇒ **mac / linux 侧的 shell 脚本根本不在扫描范围内**。

⚠⚠⚨ **实测（scratch 树复制整个仓根 · 对照实验）**：

| 组 | 变异 | 目标脚本 rc | 接线门 rc | 结论 |
|---|---|---|---|---|
| 基准 | — | rc=0 | rc=0 | 绿 |
| ⚠⚠⚨ **D1** | 往 `macos/scripts/catalog-check.sh` 新增一处**命令替换内**的 `|| true` | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **rc=0** | ⚠⚠⚨ **全绿假绿** |

⚠⚠⚨ **D1 的关键**：「新增未登记 ⇒ 红」这条承诺在 **mac / linux 侧根本没有牙**
⇒ 往 mac 侧新增一处 `|| true` ⇒ 盘点**一声不吭** ⇒ 接线门**照样绿**
⇒ 那条承诺**只覆盖了四个目录里的一个**。

⚠ **缺口实测**（用盘点器**自己的抽取器**量，不是另写一个 ⇒ 口径一致）：

| 范围 | `|| true` 站点数 | 原盘点器覆盖？ |
|---|---|---|
| `deepin/scripts` | **21** | ✅ 覆盖（对得上登记册） |
| `macos/` | **7** | ❌ **不覆盖** |
| `linux/scripts` | **5** | ❌ **不覆盖** |
| `assets/` | **0** | ❌ **不覆盖**（本来就没有） |

⇒ 缺 **12** 处（7 + 5 + 0）⇒ **一条本该被登记的承诺，在三个目录上从未生效**。

**② 修法（范围对齐 + 键改相对路径 + 双向对账）**

1. **范围对齐恒真探针的 shell 范围**（批 CZ / 批 DB 立的判据层面）——
   `TRUE_SCOPE = (('shell', 'deepin/scripts'), ('macos_shell', 'macos'),
   ('assets_shell', 'assets'), ('linux_shell', 'linux/scripts'))`
   ⇒ ⚠ **单行**（批 AH~AX 纪律：多行元组 ⇒ 门项只能钉首行 ⇒ 内容被改窄门不会红）；
2. **递归遍历**——`macos/scripts/render-harness/run.sh` 在**子目录**里
   ⇒ 不递归 ⇒ 那批脚本上的 `|| true` 永远不被查；
3. **fail closed**——范围目录**不存在** / 范围内**一个 `.sh` 都没有** ⇒ 当场判红
   ⇒ 否则范围被悄悄掏空 ⇒ 盘点等于没跑 ⇒ **承诺的覆盖面是空的**；
4. **登记册的键改成「相对仓库根的路径」**（批 CY 教训）——
   `deepin/scripts/contract-check.sh` 与 `macos/scripts/contract-check.sh`
   **同名** ⇒ 若用裸文件名做键 ⇒ 两边的处数**合并**
   ⇒ 「一处新增 + 一处减少 = 净 0」⇒ 登记册照样相等 ⇒ **假绿**；
5. **与恒真探针的扫描范围基线逐范围对账**——两个盘点**共用**一份
   `ci-tautology-scope.baseline` ⇒ 任何一边把范围改窄 ⇒ **文件数对不上** ⇒ 红；
6. **反向对账**——基线里凡是 **shell 口径**的键（`shell` / `*_shell`）
   必须在本盘点的范围里 ⇒ 「恒真探针扩了范围而本盘点没跟上」⇒ 红
   ⇒ ⚠ **只做正向对账不够**：正向只保证「本盘点有的，基线也得有」
   ⇒ 基线**多出来**的 shell 口径（恒真探针新加的那块目录）⇒ 本盘点**看不见**
   ⇒ ⇒ **反向**那一半才是堵这个洞的；
7. **登记册重建**：21 → **33 行**（21 行键改路径 + **12 行新增**，逐条写理由）。

**③ 落门 / 判据**

- **新增 17 条**（批 DQ 独立段，插在批 DP 段之后、批 CG 块之前）：
  - ① 范围常量 `TRUE_SCOPE`（1 条）
  - ② 对账基线的路径常量 `SCOPE_BASELINE`（1 条）
  - ③ 范围列举：函数定义 / 常量**被真的遍历** / 根路径算法 /
    目录不存在 fail closed / 范围内 0 个 `.sh` fail closed（5 条）
  - ④ 范围基线：读取函数定义 / **读不到判红**（fail closed）/ **逐范围对账**判定行（3 条）
  - ⑤ 登记册键是「相对仓库根的路径」（1 条）
  - ⑥ 范围列举**必须被调用**（1 条）
  - ⑦ **反向对账 5 条**：范围键集合 / 待查键来源 / **shell 口径识别** /
    排除方向 / 判定行（5 条）
- **原地替换**：
  - 门项条数 **1258 → 1275**（**三处同改**：基线文件 / 审计器常量 / 门项里的数字）
  - `FAIL_REPORT_COUNTS` 那条门**重生成**（`ci-true-audit.py` 的 `fail_exit` **14 → 15**）
  - `TRUE_AUDIT_EXPECTED_ROWS` 那条门的**说明文字**补「范围扩到 mac 侧 + linux 侧 ⇒ 21 → 33」
  - `ci-wiring.sh` 里那条 `GATE_LINES_EXPECTED` 门项的数字与说明文字同步
- ⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条 `grep -cE` 回验
  （命中数 + 整行锚定 + 中段无**无界通配**）
- ⚠ **字面单引号写成 `.`**（批 BL 约定）——反向对账那两行的源码里**有**真单引号
  （`k == 'shell'` / `k.endswith('_shell')`）⇒ 转义成 `.` 才能塞进单引号包裹的正则参数

⚠⚠⚨ **本批自己踩到并已修的两个真缺口**（**关键判定必须整行锚定**）：

1. **反向对账那 5 行一开始一条门都没钉**
   ⇒ 把它改成 `if extra_shell and False:` ⇒ 那道检查**恒不触发**
   ⇒ **静默失去牙**而没人知道 ⇒ ⇒ **每一条可锚定的物理行各钉一条门**
   （范围键集合 / 待查键来源 / shell 口径识别 / 排除方向 / 判定行）；
2. **重生成 `FAIL_REPORT_COUNTS` 那条门时，正则漏了整行锚点**
   ⇒ 审计器 **rc=8**（锚定形态）当场判红
   ⇒ ⚠ **不是推演**：审计器自己抓到了 ⇒ 补上 `^…$` 才过。

**④ 负控 19 真红**

| 组 | 用例 | 结果 |
|---|---|---|
| A · 覆盖面（核心对照） | NC1 mac 侧新增一处 `|| true`（**改前是全绿假绿**） | 盘点 rc=1，文案「新增未登记」 |
| A · 覆盖面 | NC2 linux 侧新增一处 `|| true` | 盘点 rc=1，文案「新增未登记」 |
| B · 范围不许被改窄 | NC3 `TRUE_SCOPE` 删掉 macos 那一项 | 接线门 rc=1，「范围常量**必须在**」 |
| B · 范围不许被改窄 | NC4 macos 那一项的目录被换成 `macos/scripts` | 接线门 rc=1，同上门 |
| C · 对账不许被摘 | NC5 逐范围对账判定行 → `if False:` | 接线门 rc=1，「**逐范围对账**」 |
| C · fail closed | NC6 目录不存在不判红 | 接线门 rc=1，「范围目录**不存在**」 |
| C · fail closed | NC7 范围内没有 `.sh` 不判红 | 接线门 rc=1，「一个 .sh 都没有」 |
| D · 键不许撞车 | NC8 键改回裸文件名 | 接线门 rc=1，「相对仓库根的路径」 |
| D · 定义了不等于用了 | NC9 范围列举不被调用 | 接线门 rc=1，「范围列举**必须被调用**」 |
| E · 清单不许被删 | NC10 登记册被删一行 | 盘点 rc=1，「登记册条数」 |
| E · 条数基线 | NC11 条数基线常量 33 → 32 | 接线门 rc=1，「条数基线常量**必须在**」 |
| F · 条数三处同改 | NC12 只改门项基线文件 | 接线门 rc=1，「门项条数」 |
| G · **反向对账** | NC13 范围基线里新增一个 `*_shell` 键 | 盘点 rc=1，「恒真探针扩了范围而本盘点没跟上」 |
| G · **反向对账** | NC14 判定行 → `if extra_shell and False:` | 接线门 rc=1，「反向对账的**判定行**」 |
| G · **反向对账** | NC15 排除方向 `k not in` → `k in` | 接线门 rc=1，「反向对账的**排除方向**」 |
| G · **反向对账** | NC16 shell 口径识别改窄（只认 `shell`） | 接线门 rc=1，「反向对账的**shell 口径识别**」 |
| G · **反向对账** | NC17 范围键集合被改宽（结果恒空） | 接线门 rc=1，「反向对账的**本盘点范围键集合**」 |
| G · **反向对账** | NC18 待查键来源被改（查自己 ⇒ 恒空） | 接线门 rc=1，「反向对账的**待查键来源**」 |
| H · 双向对账 | NC19 范围基线里 `macos_shell` 键被删 | 盘点 rc=1，「范围不再一致」 |
| I · 洁净度 | 每个用例还原后与**原始字节**逐字节相同 | 19/19 洁净 |

⚠⚠⚨ **harness 自身的纪律**（沿用批 DP 的教训）：
scratch 树复制**整个仓根**（含 `linux/` / `macos/` / `assets/` ⇒ 范围扩了才测得到）；
备份**在变异之前**取且备份路径与内容分开存；**每次变异前先还原到原始字节**；
变异后**自己先自证**语法（`py_compile` / `sh -n` ⇒ 变异不得破坏被测文件的语法）；
退出码**不经管道读**；**启动前自检**；**atexit 兜底还原**；
洁净度判据 = **与原始字节逐字节相同**。

**⑤ 数字**

- 门项 **1258 → 1275**（**三处同改**）；执行次数 **1261 → 1278**
- `ARCH_ANY_FAIL=1` **66 → 67**；`ARCH_FAIL=0` **67 → 68**
- `FAILS.append(2)` 收集处 **9** 不变；**守卫登记册 20** 个守卫 不变
- `|| true` 盘点 **21 → 33 处**；登记册 **21 → 33 行**
- 恒真探针 shell+python 条件 **948 → 957**（+9 ⇒ 新代码里的 `if` 条件 ⇒ ⚠ **自指**，知情取舍）
- 判定层 **396** 不变；断言实参 99 条不变；Swift 469 条断言 / 144 处 if 不变
- 未验证出口盘点 **21 组 / 73 处** 不变；孤儿探针 32 脚本 / 白名单 10 条 不变
- 接线门 **1278** 项全绿；审计器 `--list` rc=0（**1275/1275**）；报告模式 rc=0
- 恒真探针 rc=0、两个盘点 rc=0、孤儿探针 rc=0
- ⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）⇒ **如实记录**
- **负控 19 真红**；累计 **1217/1217**

**⑥ 已知边界（如实记着）**

- ⚠ **登记册是「名单」** ⇒ 协同编辑（登记册 + 范围常量一起改）抓不到
  ⇒ ⚠ **批 CR / 批 DO / 批 DP 同款已知边界**；
- ⚠ **反向对账按 `shell` / `*_shell` 键名识别 shell 口径**
  ⇒ 将来若新增**不带 `_shell` 后缀**的 shell 口径键 ⇒ **漏**
  ⇒ ⚠ **当前基线里的 shell 口径全部带 `_shell`**（`macos_shell` / `assets_shell` / `linux_shell`）
  ⇒ 且 `shell` 本身被特判 ⇒ 当前**够用**；
- ⚠ **「段」启发式对单行函数定义会误判**（`die() { … }` ⇒ 段判成 `die`）
  ⇒ 只影响**说明文字** ⇒ **指纹仍稳定唯一** ⇒ 不影响判定；
- ⚠ **`assets` 侧当前 0 处** ⇒ 那条范围**看起来是空的**
  ⇒ ⚠ 但**登记册里 33 行没有一行属于 assets** ⇒ 范围仍**被 fail closed 守着**
  ⇒ 将来 assets 里出现第一处 `|| true` ⇒ 会被**要求登记**；
- ⚠ **恒真探针的 python / swift 口径不在本盘点范围内**
  ⇒ 「命令替换内的 `|| true`」这个承诺**仍然只覆盖 shell 侧**
  ⇒ ⚠ 但 python / swift 侧**没有** `|| true` 这个语法 ⇒ 不是洞；
- ⚠ **行尾注释里的 `|| true` 也会被算成站点**（假红风险，知情取舍）
  ⇒ 因为要剥注释后才能定位到真正的命令替换 ⇒ 剥注释会**连行尾注释一起去掉**
  ⇒ ⇒ 实际风险已大幅降低，但**不是零**；
- ⚠ **两个盘点共用同一份范围基线** ⇒ 改那份基线是**一处协同编辑**
  ⇒ ⚠ 批 CR / 批 DO 同款边界；
- ⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

### E.2ca 失败出口的守卫不许被悄悄改弱（批 DR）

**① 起因（实测坐实，不是推演）**

批 DP 台账里**写明的已知边界**：

> ⚠ 口径 ③ 只管「决定退出码的那个守卫」⇒ **fail-closed 出口的守卫**
> （`if not os.path.isdir(…)`）的**取反 / 改形不被抓**
> ⇒ 原因：那些守卫形态**多样**（取反 / 比较 / 调用）⇒ 统一约束会**误伤**
> ⇒ ⚠ 有意的（fail closed 方向）

⇒ 也就是说：**判据脚本里那些「失败就不许放过」的守卫，一个门都没钉住**。

⚠⚠⚨ **实测（scratch 树复制整个仓根 · 3 组对照实验）**：

| 组 | 变异 | 盘点 rc | 审计器 rc | 接线门 rc | 结论 |
|---|---|---|---|---|---|
| A | —（基准） | 0 | 0 | 0 | 绿 |
| ⚠⚠⚨ **B** | **只造真洞**：在 `ci-true-audit.baseline` 的**注释行**里塞一个**真的 U+FFFD 字符** | **1** | 0 | **1** | 红（真洞**被报出来**：文案「登记册里有 U+FFFD ⇒ 拒绝落盘/判读」） |
| ⚠⚠⚨ **C** | **真洞 + 中和守卫**：`if '\ufffd' in raw:` → `if '\ufffd' in raw and False:` | 0 | 0 | 0 | ⚠⚠⚨ **全绿假绿** |

⇒ **C 组的要害**：守卫一被中和，那个失败出口**恒不触发** ⇒ 真洞**不再被报出来**
⇒ 而盘点 / 审计器 / 接线门**三个门全绿**。

⚠ **为什么现有机制全都抓不到**（逐条对着口径查过）：

1. **恒真探针**只抓「条件里去掉字面量与关键字后**一个标识符都不剩**」+ `if True:` / `if False:` / `if 1:`
   ⇒ `X and False` **还有标识符** ⇒ **不抓**；
2. **批 DP 口径 ③**只管 `return 1` 站点 ⇒ fail-closed 的 `sys.exit(…)` **不在口径内**；
3. **批 DO / 批 DM**只管**审计器自己** ⇒ 判据脚本**不在口径内**；
4. `ci-wiring.sh` ⇒ **没有一条门**钉住这些守卫行。

⚠⚠⚨ **实测统计**：判据脚本里共 **23 处失败出口**，其中
**只有 9 处**的守卫行被门钉住（批 CJ / 批 CY / 批 DQ 段落的门恰好落在那 9 处），
⇒ **14 处裸奔** ⇒ 任何一处被改弱 ⇒ 没人发现。

**② 修法（两条腿 + 零名单维护）**

- **腿 ① · 守卫登记册（双向红 · 表达式级）**
  - 新增 `deepin/scripts/ci-fail-guard.baseline`（**23 行**）——
    每行 `脚本<TAB>守卫表达式<TAB>理由`（TAB 六段变体 ⇒ 理由里可以写 `||`）；
  - 审计器算出所有失败出口的 **(脚本, 守卫表达式) 多重集** ⇒ 与登记册**双向红**；
  - ⇒ 守卫被改弱（`and False` / `or True` / **换形态** / **换比较值** / **换标识符**）
    ⇒ 表达式对不上 ⇒ **红**；
  - ⇒ 失败出口被**删 / 被挪 / 被加** ⇒ 对不上 ⇒ **红**；
  - ⚠ 非 ASCII 一律写成 `\uXXXX` ⇒ 登记册里**不会有真 U+FFFD**
    （否则那份登记册自己就被判据拒了 ⇒ 鸡生蛋）；
  - ⚠ **逐条理由**（批 BN 纪律）：第 3 段不许为空；
  - ⚠ 哨兵：`(except 兜底)`（在 except 里兜底）/ `(无 if 守卫)`（压根没守卫）。
- **腿 ② · 守卫里不许有布尔字面量**
  - 布尔字面量 ⇒ 守卫要么**恒假**（死代码 ⇒ 失败永远不被报出）
    要么**恒真**（永远被报出 ⇒ 变成无条件失败）
    ⇒ 两种都不是「失败条件的忠实表达」⇒ 一律红；
  - ⇒ **一次挡住整类**（批 CD 纪律），且**不依赖登记册** ⇒ 协同编辑躲不过这一腿；
  - ⚠ 判定**收成单行** ⇒ 门项可**整行钉住**（批 AH~AX 纪律：关键判定整行锚定）。
- ⚠ **判定口径与批 DP 完全一致**（复用 `_dp_is_sys_exit` + `_dp_is_main_call`）
  ⇒ 「什么叫失败出口」**两批口径不会各算各的**（批 BF：判定逻辑只有一份）；
- ⚠ **fail closed**：列不出目录 / 解析失败 / 读不了登记册 ⇒ 判红
  （不许「读不到就当没有登记册」，批 BP 同款纪律）。

**③ 落门 / 判据**

- **新增 22 条**（批 DR 独立段，插在批 DQ 段之后、批 CG 块之前）：
  - ① 登记册路径常量 / 条数基线常量（2 条）
  - ② 判定函数定义 + 三个 helper 定义（4 条）
  - ③ 腿②的**判定行**（收成单行的那行）+ 腿②的**判定点**（2 条）
  - ④ **守卫表达式的推导行**（关键 ⇒ 改了它就对拍的是别的东西）（1 条）
  - ⑤ 两个哨兵（`(except 兜底)` / `(无 if 守卫)`）（2 条）
  - ⑥ 成功出口的排除行 / 遍历点 / 读登记册行（3 条）
  - ⑦ 登记册的三条判定行（段数 / 理由非空 / 条数）（3 条）
  - ⑧ 腿①的对拍三半（不在册里 / 册里有但实测没有 / 处数对不上）（3 条）
  - ⑨ 两个调用点（审计模式 + 报告模式）（2 条）
- **原地替换 5 处**：
  - 门项条数 **1275 → 1297**（**三处同改**：基线文件 / 审计器常量 / 门项里的数字）
  - `ARCH_ANY_FAIL=1` 67 → 68、`ARCH_FAIL=0` 68 → 69（批 DR 段新增 1 处 trailer）
  - `FAILS.append(2)` 收集处 **9 → 10**（新增一个 rc=2 的收集点）
  - `FAIL_GUARDS` 登记册 20 → **21**（加 `fg_bad`；批 DO 纪律：新收集点必须登记）
  - `FAIL_GUARDS` 那条门项**重生成**（登记册内容变了 ⇒ 正则要跟着变）
- ⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条 `grep -cE` 回验
- ⚠ **字面单引号写成 `.`**（批 BL 约定）

⚠⚠⚨ **本批自己踩到的两个坑**（都靠现成机制当场抓住）：

1. **重生成门项正则时漏了整行锚点**（`^…$`）⇒ 审计器 **rc=8**（锚定形态）当场判红
   ⇒ ⚠⚠⚨ **这是第二次踩同一个坑**（批 DQ 也栽在重生成 `FAIL_REPORT_COUNTS` 那条门上）
   ⇒ ⇒ **纪律升级**：**程序化重生成正则时必须自带 `^…$`**，
   不要指望事后补 ⇒ 补一次就可能被审计器抓住一次 ⇒ 但**该自己一次做对**；
2. **加了新段 ⇒ 两个段级 trailer 计数要跟着改**（`ARCH_ANY_FAIL` / `ARCH_FAIL`）
   ⇒ 漏了 ⇒ 审计器报「次数门没配准 ⇒ 门没牙」。

**④ 负控 19 真红**

| 组 | 用例 | 结果 |
|---|---|---|
| A · 核心对照 | NC1 守卫被中和（`and False`）⇒ **修前是全绿假绿** | 审计器 rc=2，指名道姓「守卫里**有布尔字面量**」 |
| A · 改弱形态 | NC2 `not os.path.isdir` → `not os.path.isfile` | 审计器 rc=2，「**实测没有**」 |
| A · 改弱形态 | NC3 布尔运算符 `or` → `and` | 审计器 rc=2，「**实测没有**」 |
| A · 改弱形态 | NC4 比较值 `n == 0` → `n == 1` | 审计器 rc=2，「**实测没有**」 |
| B · 出口增减 | NC5 失败出口被删（`sys.exit(…)` → `pass`） | 审计器 rc=2，「**实测没有**」 |
| B · 出口增减 | NC6 同一守卫下多一处失败出口 | 审计器 rc=2，「**处数**」对不上 |
| B · 出口增减 | NC7 新增一个全新守卫的失败出口 | 审计器 rc=2，「**不在登记册里**」 |
| C · 登记册 | NC8 登记册被删一行 | 审计器 rc=2，「登记册条数」 |
| C · 登记册 | NC9 登记册有一行段数不对 | 审计器 rc=2，「不是 3 段」 |
| C · 登记册 | NC10 登记册有一行理由为空 | 审计器 rc=2，「没有理由」 |
| D · 关键判定门 | NC11 条数基线常量 23 → 22 | 接线门 rc=1，「条数基线常量」 |
| D · 关键判定门 | NC12 腿②的判定行 → `return False` | 接线门 rc=1，「腿②的**判定行**」 |
| D · 关键判定门 | NC13 腿①的对拍判定行被摘 | 接线门 rc=1，「腿①「**实测有、登记册没有**」」 |
| D · 关键判定门 | NC14 **守卫表达式的推导行**被改 | 接线门 rc=1，「守卫表达式的推导行」 |
| D · 关键判定门 | NC15 硬门模式的调用点被摘 | 接线门 rc=1，「守卫体检**必须被调用**（审计模式）」 |
| D · 关键判定门 | NC16 报告模式的调用点被摘 | 接线门 rc=1，「守卫体检**必须被调用**（报告模式）」 |
| E · 门级隔离 | NC17 `FAIL_GUARDS` 里 `fg_bad` 被摘 | 接线门 rc=1，「失败态上报点的**登记册**」 |
| E · 门级隔离 | NC18 rc=2 的收集处计数被改 | 审计器 rc=4，「次数门没配准」 |
| F · 条数三处同改 | NC19 只改门项基线文件 | 接线门 rc=1，「门项条数」 |
| G · 洁净度 | 每个用例还原后与**原始字节**逐字节相同 | 19/19 洁净 |

⚠⚠⚨ **本批 harness 自己踩了一个错并已修**（⚠ **假红比假绿更坏** ⇒ 期望写错 = 自己骗自己）：

1. **NC9 的变异没真造成「段数不对」** —— 原写法是把某行的**理由**换短，
   但**段数仍是 3 段** ⇒ 登记册**合法** ⇒ 规则**正确地没报**
   ⇒ harness 却写着「期望文案『不是 3 段』」⇒ **期望与实际行为不符**
   ⇒ ⇒ 改成真的**只留 2 段**（`脚本<TAB>守卫表达式`）⇒ 重跑 ⇒ 真红。
   ⇒ ⚠ **教训**：「期望写错」和「规则有洞」在 harness 里长得**一模一样**
   ⇒ 必须**先问「这条变异到底改了什么」** ⇒ 别急着改判据。

⚠⚠⚨ **harness 自身的纪律**（沿用批 DP 的教训）：
scratch 树复制**整个仓根**；备份**在变异之前**取且备份路径与内容分开存；
**每次变异前先跑一遍确认是绿的**（否则用例无效）；
变异后**自己先自证**语法（`py_compile`）⇒ 变异不得破坏被测文件的语法；
退出码**不经管道读**；**启动前自检**；**atexit 兜底还原**；
洁净度判据 = **与原始字节逐字节相同**；
⚠ 审计模式必须用 **`--list`**（CI 真正跑的硬门模式；无参 = 报告模式 ⇒ rc **恒 0**）。

**⑤ 数字**

- 门项 **1275 → 1297**（**三处同改**）；执行次数 **1278 → 1300**
- `ARCH_ANY_FAIL=1` **67 → 68**；`ARCH_FAIL=0` **68 → 69**
- `FAILS.append(2)` 收集处 **9 → 10**；**守卫登记册 20 → 21** 个守卫
- **失败出口守卫登记册 23 行**（23 处失败出口逐条登记）
- 恒真探针 shell+python 条件 **957 → 971**（+14 ⇒ 新代码里的 `if` 条件 ⇒ ⚠ **自指**，知情取舍）
- 判定层 **396** 不变；断言实参 99 条不变；Swift 469 条断言 / 144 处 if 不变
- `|| true` 盘点 **33 处** 不变；未验证出口盘点 **21 组 / 73 处** 不变；
  孤儿探针 32 脚本 / 白名单 10 条 不变
- 接线门 **1300** 项全绿；审计器 `--list` rc=0（**1297/1297**）；报告模式 rc=0
- 恒真探针 rc=0、两个盘点 rc=0、孤儿探针 rc=0、D2 散值门 rc=0
- ⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）⇒ **如实记录**
- **负控 19 真红**；累计 **1236/1236**

**⑥ 已知边界（如实记着）**

- ⚠ **登记册是「名单」** ⇒ 「改代码 + 改登记册」的**协同编辑**抓不到
  ⇒ ⚠ **批 CR / 批 DO / 批 DP 同款已知边界**；
  ⇒ ⚠ **但腿②不依赖登记册** ⇒ 「往守卫里塞布尔字面量」那一类**协同编辑也躲不过**；
- ⚠ **登记册比的是「守卫表达式」不是「失败出口本身」**
  ⇒ 把两个出口的守卫**对调** ⇒ 表达式**集合不变** ⇒ **抓不到**（边缘情形）；
- ⚠ **守卫表达式的规范化靠 `ast.unparse`**
  ⇒ 同一段代码换个写法（`a is None` vs `None is a`）⇒ 表达式就不同
  ⇒ 要更新登记册 ⇒ **偏严**方向（假红比假绿好，但仍是假红）；
- ⚠ **审计器自己除外**（`DP_SELF`）⇒ 审计器自己的失败出口由批 DO 的 `FAIL_GUARDS` 管
  ⇒ 两批口径**不重叠**（与批 DP 的设计一致）；
- ⚠ **腿②只抓布尔字面量** ⇒ 「换形态 / 换比较值」那一类**只能靠腿①**
  ⇒ 腿①是名单 ⇒ 协同编辑**躲得过**；
- ⚠ **只管 `deepin/scripts/*.py`** ⇒ `linux/` 与 `macos/` 侧**不在口径内**
  ⇒ 当前那两边**没有**判据用 python ⇒ 残余风险小 ⇒ **下一批候选**；
- ⚠ **`_fg_collect_exits` 自己重走了一遍 AST** ⇒ 与批 DP 的 `scan` 有**同款约定**
  （函数体 / 类体不继承外层守卫）⇒ 口径一致但**实现是两处**
  ⇒ 若将来其中一处改了约定 ⇒ 两批口径会**漂** ⇒ ⚠ 已知边界；
- ⚠ **登记册的段数是 3**（脚本|守卫表达式|理由）⇒ 理由里**不许有 TAB**；
- ⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

### E.2cb 判据脚本的抽取器必须被 e2e 自检覆盖（批 DS）

**① 起因（实测坐实，不是推演）**

批 DN / 批 DF 的纪律：**自检必须真的经过被测的抽取器**。
⇒ 当时只给**两个**抽取器补了 e2e 自检（`ci-tautology-check.py` 的
`python_if_conds` 与 `heredoc_spans`）。
⇒ 台账里**写明的已知边界**：「⚠ 腿 1 只覆盖这两个抽取器 ⇒ 别的抽取器
**没有**同款自检 ⇒ **不做「抽取值枚举器」**（批 DI 已降级）」。

⚠⚠⚨ **实测（scratch 树复制整个仓根 · 3 组对照实验）**：

| 组 | 变异 | 盘点 rc | 审计器 rc | 接线门 rc | 结论 |
|---|---|---|---|---|---|
| A | —（基准） | 0 | 0 | 0 | 绿 |
| ⚠⚠⚨ **B** | **只造真洞**：在 `macos/scripts/catalog-check.sh` 末尾新增一处**反引号形态**的 `|| true`（`X=\`echo hi \|\| true\``） | **1** | 0 | **1** | 红（真洞**被报出来**：文案「新增未登记」） |
| ⚠⚠⚨ **C** | **真洞 + 抽坏抽取器**：`find_subst_spans` 的**反引号分支**被摘（`if text.startswith('$(', i) or c == '\`':` → `if text.startswith('$(', i):`） | 0 | 0 | 0 | ⚠⚠⚨ **全绿假绿** |

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

**② 修法（一条零名单维护的规则 + 逐个补样例）**

- **审计器新增 `check_extractor_self_tests()`**（零名单维护）：
  - **前缀是单一真相源**：`EXTRACTOR_PREFIXES = ('extract_', 'find_', 'scan_',
    'parse_', 'collect_', 'strip_')`
    ⇒ 新抽取器**自动纳入** ⇒ 将来新增一个没自检的抽取器 ⇒ **立即红**；
  - **「被覆盖」= 能从某个自检函数沿调用图**传递**到达**
    ⇒ 薄封装（`scan_shell_file` → `scan_shell_text`）也算覆盖
    （它被自检**真的走过**了）⇒ **嵌套函数**（`scan_one`）同样传递覆盖；
  - **fail closed**（列不出目录 / 解析失败 ⇒ 判红）；
  - ⚠ **规则自己也被规则保护**（批 DM/DN/DO/DP 同款）：名字以 `check_` 开头
    ⇒ 批 DM 管它 ⇒ **只有一条 return**。
- **给当前缺自检的 6 个抽取器逐个补 e2e 样例**
  （⚠ 批 DF / 批 DN 纪律：自检必须**真的经过被测的抽取器**；
  ⚠ 每档**两条**样例：「该抽到 N 条」+「不该抽到 0 条」⇒ 只测一边 ⇒ 判反了也能过）：

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

**③ ⚠⚠⚨ 负控跑出来的**真洞**：覆盖判定只认「名字像自检」，不认「自检会跑」

⚠⚠⚨ **第一轮负控 17 例全红，但有两个用例的「红」来路不对**：

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

⚠⚠⚨ **本批自己踩到的三个坑**（都靠现成机制当场抓住）：

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

**④ 落门 / 判据**

- **新增 31 条**（批 DS 独立段，插在批 DR 段之后、批 CG 块之前）：
  - ① 审计器侧 **16 条**：前缀常量 / 判定函数定义 / 自检名 helper 定义与判定行 /
    **传递闭包起点** / 前缀口径判定行 / **「没有覆盖」判定行** / 两个调用点
    ＋ **live 子组 7 条**（跳过节点常量 / 模块级入口收集函数 / live 判定函数 /
    「不进入函数体」判定行 / **反向边**推导行 / **反向可达**判定行 /
    live 集合**真的被算出来**的推导行）；
  - ② `ci-true-audit.py` 4 条：自检函数定义 / **自检真的经过 `find_subst_spans`** /
    **自检真的经过 `scan_file`** / 自检被调用；
  - ③ `ci-unverified-audit.py` 3 条：自检函数定义 / **自检真的经过 `scan_file`** /
    自检被调用；
  - ④ `ci-tautology-check.py` 8 条：三档的分派行 + **三处「自检真的经过抽取器」** +
    两条样例行
- **原地替换 8 处**：
  - 门项条数 **1297 → 1328**（**三处同改**）
  - **传递闭包的起点**那条门项**重生成**（源行被收紧 ⇒ 旧正则失配
    ⇒ 审计器 rc=4 当场报「次数门没配准」⇒ **当场抓住**）
  - `ARCH_ANY_FAIL=1` 68 → 69、`ARCH_FAIL=0` 69 → 70（批 DS 段新增 1 处 trailer）
  - `FAILS.append(2)` 收集处 **10 → 11**（新增一个 rc=2 的收集点）
  - `FAIL_GUARDS` 登记册 21 → **22**（加 `es_bad`）
  - `FAIL_REPORT_COUNTS` **重新生成**（`ci-true-audit.py` 的 `fail_count` 2 → **7**、
    `fail_exit` 15 → **16**；`ci-unverified-audit.py` 的 `fail_count` 7 → **10**、
    `fail_exit` 8 → **9**）
  - 守卫登记册 **23 → 25 行**（新增两处 `selftest_extractors` 的失败出口守卫）
  - `FAIL_REPORT_COUNTS` / `FAIL_GUARDS` 那两条门项**重生成**
- ⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条回验
  （⚠ 审计器自己会校准每条门项的命中数 ⇒ `--list` rc=0 即等于逐条验过）
  ⚠ 转义只用 **POSIX ERE 元字符**（Python `re` 同样认）
  ⇒ **不用** `re.escape`（它会转义空格 / `#` / `&`
  ⇒ Python 3.12 对 `\#` / `\&` 这类「非字母标点转义」**直接报 error**）
  ⚠ 生成器自带**自证**：说明文字里有**单引号 / 反引号** ⇒ 拒绝生成
  （⚠ 反引号在双引号内会被当命令替换 ⇒ `sh -n` 语法错 —— 本批生成器**当场拦下 2 处**）

**⑤ 负控 20 真红**

| 组 | 用例 | 结果 |
|---|---|---|
| A · 抽坏 ⇒ 脚本自己红 | NC1 抽坏 `find_subst_spans` 的反引号分支（**修前是全绿假绿**） | 盘点 rc=1，文案「抽取器自检失败」 |
| A · 抽坏 ⇒ 脚本自己红 | NC2 抽坏 `ci-true-audit.py::scan_file` | 盘点 rc=1，文案「抽取器自检失败」 |
| A · 抽坏 ⇒ 脚本自己红 | NC3 抽坏 `ci-unverified-audit.py::scan_file` | 未验证盘点 rc=1，文案「抽取器自检失败」 |
| A · 抽坏 ⇒ 脚本自己红 | NC4 抽坏 `scan_shell_file` | 恒真探针 rc≠0，文案「探针自检失败」 |
| B · 失去覆盖 ⇒ 审计器红 | NC5 自检档不再经过 `find_assert_calls` | 审计器 rc=2，「没有 e2e 自检覆盖」 |
| B · 失去覆盖 ⇒ 审计器红 | NC6 自检档不再经过 `scan_shell_file` | 审计器 rc=2，同上 |
| B · 失去覆盖 ⇒ 审计器红 | NC7 自检档不再经过 `scan_swift_file` | 审计器 rc=2，同上 |
| B · 失去覆盖 ⇒ 审计器红 | NC8 真盘点的抽取器自检不被调用 | 审计器 rc=2，同上（★ **收紧前是 rc=4 ⇒ 规则自己没红**） |
| B · 失去覆盖 ⇒ 审计器红 | NC9 未验证盘点的抽取器自检不被调用 | 审计器 rc=2，同上（★ 同上） |
| C · 关键判定门 | NC10 前缀常量被改窄 | 接线门 rc=1，「**抽取器前缀**这个常量必须在」 |
| C · 关键判定门 | NC11 「没有覆盖」判定行被摘 | 接线门 rc=1，指名道姓 |
| C · 关键判定门 | NC12 传递闭包起点被改 | 接线门 rc=1，「**传递闭包的起点**必须在」 |
| C · 门级隔离 | NC13 硬门调用点被摘 | 接线门 rc=1，指名道姓 |
| C · 门级隔离 | NC14 报告模式调用点被摘 | 接线门 rc=1，指名道姓 |
| C · 门级隔离 | NC15 「自检函数」判定行被改弱 | 接线门 rc=1，指名道姓 |
| D · 样例不许被删 | NC16 自检的样例行被删 | 接线门 rc=1，指名道姓 |
| E · 条数三处同改 | NC17 只改门项基线文件 | 接线门 rc=1，「门项条数」 |
| F · live 判定的牙 | NC18 「反向可达」判定行被改**松** | 接线门 rc=1，指名道姓 |
| F · live 判定的牙 | NC19 「不进入函数体」判定行被摘 | 接线门 rc=1，指名道姓 |
| F · live 判定的牙 | NC20 live 集合被掏空（算了不用） | 审计器 rc=2，「没有 e2e 自检覆盖」 |
| G · 洁净度 | 每个用例还原后与**原始字节**逐字节相同 | 20/20 洁净 |

⚠⚠⚨ **harness 自身的纪律**（沿用批 DP / 批 DR 的教训）：
scratch 树复制**整个仓根**；备份**在变异之前**取且备份路径与内容分开存；
**每个用例一棵新树** ⇒ 天然满足「变异前先还原到原始字节」；
**变异前先跑一遍确认是绿的**（否则用例无效）；
变异后**自己先自证**语法（`py_compile`）⇒ 变异不得破坏被测文件的语法；
退出码**不经管道读**；**启动前自检**；**atexit 兜底还原**；
洁净度判据 = **与原始字节逐字节相同**；
⚠ 审计模式必须用 **`--list`**（CI 真正跑的硬门模式；无参 = 报告模式 ⇒ rc **恒 0**）。

**⑥ 数字**

- 门项 **1297 → 1328**（**三处同改**）；执行次数 **1300 → 1331**
- `ARCH_ANY_FAIL=1` **68 → 69**；`ARCH_FAIL=0` **69 → 70**
- `FAILS.append(2)` 收集处 **10 → 11**；**守卫登记册 21 → 22** 个守卫
- 守卫登记册 **23 → 25 行**
- 恒真探针 shell+python 条件 **971 → 996**（+25 ⇒ 新代码里的 `if` 条件 ⇒ ⚠ **自指**，知情取舍）
- 判定层 **396** 不变；断言实参 99 条不变；Swift 469 条断言 / 144 处 if 不变
- `|| true` 盘点 **33 处** 不变；未验证出口盘点 **21 组 / 73 处** 不变；
  孤儿探针 32 脚本 / 白名单 10 条 不变
- 接线门 **1331** 项全绿；审计器 `--list` rc=0（**1328/1328**）；报告模式 rc=0
  （门项条数 1328 / 基线 1328 / 危险正则 0 / 锚定违规 0）
- 恒真探针 rc=0、两个盘点 rc=0、孤儿探针 rc=0、D2 散值门 rc=0
- ⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）⇒ **如实记录**
- **负控 20 真红**；累计 **1256/1256**

**⑦ 已知边界（如实记着）**

- ⚠ **「抽取器」靠前缀识别** ⇒ 一个抽取器若**不叫**这些前缀 ⇒ **不在口径内**
  ⇒ ⚠ 例如 `classify` / `enclosing_func` / `load_baseline` 就**不在口径内**
  ⇒ ⚠ 但它们**改了会红**（指纹变了 ⇒ 登记册对不上 ⇒ 假红方向）⇒ 残余风险小；
- ⚠ **「被覆盖」= 能从自检函数沿调用图到达** **且** 那个自检函数
  **真的会被执行**（live）⇒ ⚠ **live 的口径是「从模块级入口反向可达」**
  ⇒ 一个**只在 `__main__` 保护之外**被调用的自检**不算 live**（= 不算覆盖）
  ⇒ ⚠ 若将来把入口改成 `argparse` / 信号处理 ⇒ live 口径可能**偏严**（假红方向）；
- ⚠ **live 只看「调用关系」不看「条件分支」** ⇒ 一个自检函数
  **永远走不到的那条分支**里调用了抽取器 ⇒ 仍算覆盖（边缘）;
- ⚠ **样例覆盖的是「抽取器输出的形状」不是「全部形态」**
  ⇒ 抽取器在**样例没涉及的形态**上坏了 ⇒ 自检**照样绿**
  ⇒ ⚠ 这是 e2e 自检的**固有上限**（批 DF 同款）；
- ⚠ **审计器自己除外**（`DP_SELF`）⇒ 审计器自己的抽取器
  （`extract_fn_body_awk` / `extract_step_awk` / `split_shell_args`）
  **不在口径内** ⇒ ⚠ 但它们**工具失败即判红**（批 DM 的 fail closed）⇒ 残余风险小；
- ⚠ **只管 `deepin/scripts/*.py`** ⇒ `linux/` 与 `macos/` 侧**不在口径内**
  ⇒ 当前那两边**没有**判据用 python ⇒ 残余风险小 ⇒ **下一批候选**；
- ⚠ **恒真探针侧不新增失败出口** ⇒ 它的抽取器自检**失败时**由既有 `self_test()`
  的出口上报 ⇒ 但那条出口**不在**批 DR 的守卫登记册里（审计器自己除外）⇒ **无妨**
  （它由批 DN 的门盯住）；
- ⚠ **「反向可达」是**调用关系**的闭包，不是**控制流**的闭包**
  ⇒ 一个函数在**死分支**里被调用 ⇒ 仍算 live（边缘）;
- ⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

### E.2cc 判据结果的诊断输出不许随执行 shell 变（批 DT）

**① 起因（实测坐实，不是推演）**

⚠⚠⚨ **POSIX 规定的事实**（实测复现，不是推演）：

| shell | `echo` 对反斜杠的处理 | 实测 |
|---|---|---|
| **dash**（`/bin/sh`） | **解释**（`\\` → `\`） | `echo "A \`\\\\$\` B"` ⇒ 输出 `A \`\$\` B` |
| **bash** | **不解释**（原样输出） | 同一句 ⇒ 输出 `A \`\\\\$\` B` |

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

**② 修法（一条零名单维护的规则 + 逐处换输出机制）**

- **腿 ① · 输出机制换成 `printf '%s\n'`**：
  - 门型函数（`arch_*()`）体内共 **37 处** `echo` ⇒ 全部换成 `printf '%s\n'`；
  - ⚠⚠⚨ **`printf` 不解释参数里的转义** ⇒ ⇒ **两种 shell 输出一致**；
  - ⚠⚠⚨ 而且改后输出 = **源文件字面** = **作者意图**
    （源文件 label 本来就写 3 个反斜杠 ⇒ dash 把它解释成 2 个才是**失真**）；
  - ⚠ **改动口径精确**：只改**第一个 token 是 `echo`** 的行
    ⇒ ⚠ **不动** awk 程序里的 `/^echo "› …/ {` 与 `sub(/^echo "› /, "", s)`
    ⇒ ⚠ **那是 awk 的正则字面量**，改了会**坏掉 awk 程序**
    ⇒ ⚠ 也**不动**其它地方（进度信息等）的 `echo` ⇒ 那不是判据结果；
- **腿 ② · 审计器新规则 `check_gate_output_shell()`（零名单维护）**：
  - **口径 = 函数名以 `GATE_FN_PREFIX = 'arch_'` 开头**（**单行常量**，批 AH~AX 纪律）
    ⇒ ⇒ 新门型**自动纳入** ⇒ ⇒ 新门型若用 `echo` ⇒ **立即红**；
  - **判定口径**：`echo` 前面是**行首或空白**（= 独立的命令 token）
    ⇒ ⇒ awk 里的 `/^echo` / `sub(/^echo` **不算**（前面是 `/` 或 `(`）；
  - ⚠ **fail closed**：列不出门型 / 抽不出函数体 / 函数体**抽不全** ⇒ **判红**；
  - ⚠ **规则自己也被规则保护**（批 DM/DN/DO/DP/DS 同款）：名字以 `check_` 开头
    ⇒ 批 DM 管它 ⇒ **只有一条 return**；
  - ⚠ **复用现成能力**（批 AV「抽取而非复刻」纪律）：函数体用审计器**自己**的
    `extract_shell_func()` 取 ⇒ ⇒ 不另造一套切段逻辑 ⇒ ⇒ 口径不会漂。

**③ 落门 / 判据**

- **新增 7 条**（批 DT 独立段，插在批 DS 段之后）：
  前缀常量 / 判定函数定义 / **门型前缀口径**判定行 /
  **「不许用 echo」判定行** / **fail closed** 判定行 / 两个调用点；
- **原地替换 3 处**：
  - `FAIL_GUARDS` 登记册 **22 → 23**（加 `dt_bad`）
    ⇒ ⚠⚠⚨ **那一行是单行元组** ⇒ ⇒ 门项正则**必须重生成**
    ⇒ 顺带把正则里的**字面单引号**写成 `.`（批 BL 约定）
    ⇒ ⚠ **这一处当场被审计器的盲区检测抓住**（详见 ④ 的坑 1）；
  - `FAILS.append(2)` 收集处 **11 → 12**（新增一个 rc=2 的收集点）
    ⇒ 说明文字同步（「九种失败」⇒ **「十种失败」**＋ 加第 ⑩ 项）
    ⇒ ⚠ **按「门型 + 目标文件 + 正则」定位**，不许按数字猜（批 DS 踩过）；
  - 门项条数 **1328 → 1335**（**三处同改**）
- ⚠ 门项正则**从真实行现抽 + 程序化转义** ⇒ 逐条回验
  ⇒ ⚠ 转义只用 **POSIX ERE 元字符**（Python `re` 也认）
  ⇒ **不用** `re.escape`（它会转义空格 / `#` / `&`
  ⇒ Python 3.12 对 `\#` / `\&` 这类「非字母标点转义」**直接报 error**）
  ⇒ ⚠ 生成器**自带自证**：正则里有**字面单引号** ⇒ 写成 `.`（批 BL 约定）
  ⇒ ⚠ 说明文字里有**单引号 / 反引号** ⇒ **拒绝生成**
  （⚠ 反引号在双引号内会被当命令替换 ⇒ `sh -n` 语法错 —— 本批生成器**当场拦下 2 处**）

**④ 本批踩到的五个坑**（都靠现成机制当场抓住）

1. ⚠⚠⚨ **门项正则里混进了真单引号** ⇒ 门项行的引号配对坏掉
   ⇒ **审计器的门型盲区检测当场判红**（rc=2「有门项没解析到 ⇒ 它们根本没被审」）
   ⇒ ⇒ **纪律**：门项正则里的字面单引号**必须写成 `.`**（批 BL 约定）
   ⇒ ⇒ 生成器必须**自带这条自证**（本批已加）⇒ ⚠ **手写门项 ⇒ 这条自证就没有**；
2. ⚠ **我新增的 `except UnreadableSource as e:` 与既有**顶层**那行**同形**
   ⇒ 次数门失配（期望 1 实际 2）⇒ **当场抓住**
   ⇒ ⇒ **纪律**：新代码的形态**不许撞**既有门项盯着的形态 ⇒ 改自己的写法
   （`except (UnreadableSource, OSError) as e:`），**不改**门项；
3. ⚠ **新规则的判定行必须独特** ⇒ 否则门项「恰好 1 处」会因别处同形而失配
   ⇒ ⇒ 把 fail closed 的两处判定**合并成一条独特形态**；
4. ⚠ **对照实验的「旧状态树」只换了旧脚本、审计器还是新的**
   ⇒ ⇒ 新审计器把旧脚本判红 ⇒ ⇒ A/B 对比**失效**
   ⇒ ⇒ **纪律**：对照组必须是**批 DT 之前的完整状态**（脚本 + 审计器 + 两份基线 + 登记册）；
5. ⚠ **「输出逐字节比对」会被随机量污染** ⇒ `contract-check.sh` 的沙箱名是随机的
   ⇒ ⇒ 那不是分叉 ⇒ ⇒ 比对前必须排除随机量（**如实判读**）。

6. ⚠⚠⚨ **提交信息里把文件数写成了「10 个」** —— 那是从**批 DS** 抄来的
   ⇒ 批 DT 实际只动了 **6 个**（3 个判据脚本 + 3 个文档）
   ⇒ ⚠ **说明文字必须与实际行为一致** ⇒ **当场订正**：
   `git commit --amend` + `git push --force-with-lease`（远端只有本人在用 ⇒ 风险可控）
   ⇒ ⚠⇒ **本条就是订正本身**：留痕比悄悄改掉更重要。

**④·补 · NC11 的判读教训**（批 DR 的教训：先问「这条变异到底改了什么」）

⚠ 第一版 NC11 只做一件事：把 `check_gate_output_shell` **改名**
⇒ 实测：**rc=10**（**审计器崩了** —— 调用点还在调旧名字 ⇒ NameError
⇒ 批 CT/CW 的「崩了 ⇒ 专属码 10 ⇒ 判红」⇒ **真红成立**）
⇒ ⚠ 但**没有任何文案** ⇒ ⚠⚠⚨ **「期望写错」与「规则有洞」在 harness 里长得一模一样**
⇒ ⇒ **先问「这条变异到底改了什么」**：变异 = **改名** ⇒
⇒ 后果是**崩**（不是「判定函数被掏空」那条规则）⇒ ⇒ **期望文案写错了**。

⚠⇒ 修正：把 NC11 改成「改名 **且** 同步改两个调用点」
⇒ ⇒ 审计器**不崩** ⇒ ⇒ 门项的「判定函数定义行」命中 **0**
⇒ ⇒ **次数门失配** ⇒ **rc=4 + 有文案** ⇒ ⇒ 测的正是「改名 ⇒ 门红」这条承诺。

⇒ ⚠⚠⚨ **顺带坐实的一件事**：「改名」这个变异其实被**两道机制**抓住 ——
① **崩了**（rc=10）② **门项失配**（若不崩）⇒ ⇒ 承诺**没有漏**；
⚠ 但**红因不同** ⇒ ⇒ 断言必须写对，否则**自己的负控会骗自己**。

**⑤ 负控 12 真红**

| 组 | 用例 | 结果 |
|---|---|---|
| A · 输出机制被改回 | NC1 门型输出改回 `echo`（✓ 分支） | 审计器 rc=2，「诊断输出随执行 shell 变」 |
| A · 输出机制被改回 | NC2 门型输出改回 `echo`（✗ 分支） | 审计器 rc=2，同上 |
| B · 规则不许被改弱 | NC3 「不许用 echo」判定行被改弱 | 接线门 rc=1，指名道姓 |
| B · 规则不许被改弱 | NC4 fail closed 判定行被改弱 | 接线门 rc=1，指名道姓 |
| B · 规则不许被改弱 | NC5 门型前缀常量被改窄 | 接线门 rc=1，指名道姓 |
| B · 规则不许被改弱 | NC6 门型前缀口径判定行被改 | 接线门 rc=1，指名道姓 |
| C · 门级隔离 | NC7 硬门调用点被摘 | 接线门 rc=1，指名道姓 |
| C · 门级隔离 | NC8 报告模式调用点被摘 | 接线门 rc=1，指名道姓 |
| D · 失败态不许忘登记 | NC9 `FAIL_GUARDS` 里 `dt_bad` 被摘 | 审计器 rc=2，「不在登记册里」 |
| E · 条数记三遍 | NC10 rc=2 收集处次数门被改 | 审计器 rc=4，「次数门没配准」 |
| E · 条数记三遍 | NC12 只改门项基线文件 | 接线门 rc=1，「门项条数」 |
| F · 判定函数不许被掏空 | NC11 判定函数被**改名**（且同步改两个调用点 ⇒ 审计器不崩）| 审计器 rc=4，「次数门没配准」（门项的「判定函数定义行」命中 0） |
| G · 洁净度 | 每个用例还原后与**原始字节**逐字节相同 | 12/12 洁净 |

⚠⚠⚨ **harness 自身的纪律**（沿用批 DP / 批 DR / 批 DS）：
scratch 树复制**整个仓根**；备份**在变异之前**取且备份路径与内容分开存；
**每个用例一棵新树** ⇒ 天然满足「变异前先还原到原始字节」；
**变异前先跑一遍确认是绿的**（否则用例无效）；
变异后**自己先自证**语法（`py_compile` / `sh -n`）⇒ 变异不得破坏被测文件的语法；
退出码**不经管道读**；**启动前自检**；**atexit 兜底还原**；
洁净度判据 = **与原始字节逐字节相同**；
⚠ 审计模式必须用 **`--list`**（CI 真正跑的硬门模式；无参 = 报告模式 ⇒ rc **恒 0**）。

**⑥ 数字**

- 门项 **1328 → 1335**（**三处同改**）；执行次数 **1335 → 1338**
- `FAILS.append(2)` 收集处 **11 → 12**；**守卫登记册 22 → 23** 个守卫
- `ARCH_ANY_FAIL=1` **69** / `ARCH_FAIL=0` **70**（**不变** ⇒ 批 DT 段没新增 trailer）
- **失败出口守卫登记册 25 行**（**不变** ⇒ 审计器自己的失败出口由批 DO / 批 DP 管）
- `FAIL_REPORT_COUNTS`（**不变** ⇒ 审计器自己不在那个口径里）
- 恒真探针 shell+python 条件 **996 → 999**（+3 ⇒ 新规则里的 `if` ⇒ ⚠ **自指**，知情取舍）
- 判定层 **396** 不变；断言实参 99 条不变；Swift 469 条断言 / 144 处 if 不变
- `|| true` 盘点 **33 处** 不变；未验证出口盘点 **21 组 / 73 处** 不变；
  孤儿探针 32 脚本 / 白名单 10 条 不变
- 接线门 **1338** 项全绿；审计器 `--list` rc=0（**1335/1335**）；报告模式 rc=0
- 恒真探针 rc=0、两个盘点 rc=0、孤儿探针 rc=0、D2 散值门 rc=0
- ⚠⚠⚨ **双跑输出逐字节一致**：改前 dash 262961 字节 / bash 262961 字节**但内容不同**；
  改后 dash **264853** / bash **264853** ⇒ **逐字节相同** ✓
- ⚠ `ci.sh` **16/16 步跑完**但 **rc=3**（**1 组未验证**：本机缺 `appstream-util`）⇒ **如实记录**
- **负控 12 真红**；累计 **1268/1268**

**⑦ 已知边界（如实记着）**

- ⚠⚠⚨ **CI（dash）的诊断输出有 2 行变了** —— 那 2 条含反斜杠的门项文案
  （源文件 label = **3 个**反斜杠 ⇒ 改前 dash 解释成 **2 个** ⇒ 改后原样 **3 个**）
  ⇒ ⇒ 改后 = **源文件字面 = 作者意图** ⇒ ⇒ **判定结论 / 门项期望 / 条数全部不变**
  ⇒ ⇒ 但**输出确实变了** ⇒ ⚠⚠⚨ **如实记录，不粉饰**；
- ⚠ **历史负控的关键词全部不含反斜杠**（实测逐个扫过）⇒ ⇒ 那 2 行文案变化
  **不影响**它们 ⇒ ⇒ 但这**是运气**，不是设计 ⇒ ⇒ 本批把它**变成设计**；
- ⚠ **只管 `ci-wiring.sh` 的门型函数** ⇒ 其它判据脚本的 `echo` 仍可能分叉
  ⇒ 实测当前一致 ⇒ ⇒ 且**负控靠文案的只有 python 脚本**（不受此影响）⇒ ⇒ 残余风险小；
- ⚠ **判定口径只抓「第一个 token 是 `echo`」** ⇒ `then echo …` 那种形态
  **不在口径内** ⇒ ⇒ 已知边界（**假红方向**的漏：那种写法分叉了也不会被抓）；
- ⚠ **注释里写 `echo` 也会被抓**（当前 **0** 处）⇒ ⇒ 假红风险（知情取舍）；
- ⚠ **shebang 仍是 `#!/usr/bin/env bash`（16 个脚本）** ⇒ ⇒ 「直接执行」与「CI 调用」
  仍是两种 shell ⇒ ⇒ **但门型输出已跨 shell 一致** ⇒ ⇒ 残余风险小
  ⇒ ⇒ **「统一 shebang」判为暂不做**（改 16 个文件 + 收益已被本批消掉）；
- ⚠ **CI 里没有「双跑一致性」这道门** ⇒ ⇒ 它是**验收标准**（本批实测），
  不是自动门 ⇒ ⇒ ⚠ 因为做成自动门会**自引用**（审计器跑接线门 ⇒ 接线门又跑审计器 ⇒ 递归）
  ⇒ ⇒ 若要自动化，**只能放在 `ci.sh` 里**（入口不是判据 ⇒ 无递归）⇒ ⇒ **下一批候选**；
- ⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

### E.2cd 判据层的结论不许随执行 shell 变（批 DU）

**① 起因（实测坐实，不是推演）**

⚠⚠⚨ **批 DT 立了承诺，但只挂在人工验收上**：
批 DT 把 `ci-wiring.sh` 的**门型函数体内**的 `echo` 全换成 `printf '%s\n'`
⇒ 判据结果的**诊断输出**在 `sh` 与 `bash` 下不再分叉；
⇒ ⚠⚠⚨ **但那只是「人工跑两遍、比对输出」** ⇒ **没有任何一道门会自动发现**
「昨天还一致的结论，今天在另一个 shell 下变了」；
⇒ ⚠ 批 DT 的 README 末尾**自己写了这条边界**（原文）：
「⚠ **CI 里没有「双跑一致性」这道门** ⇒ ⇒ 它是**验收标准**（本批实测）不是自动门
⇒ ⇒ ⚠ 做成自动门会**自引用**（审计器跑接线门 ⇒ 接线门又跑审计器 ⇒ 递归）
⇒ ⇒ 若要自动化**只能放在 `ci.sh` 里** ⇒ ⇒ **下一批候选**」
⇒ ⇒ **本批就是那个「下一批候选」**。

⚠⚠⚨ **本批第一次端到端跑就当场抓到一次真实的红绿分叉**（详见 ④）⇒
⇒ 这条承诺**确实会被违反** ⇒ 双跑门不是「保险」而是**必需品**。

**② 修法（第 9 步内部双跑，输出与退出码都必须一致）**

⚠ `ci.sh` 第 9 步（接线门）改成：**`sh` 跑一遍、`bash` 再跑一遍** ⇒
⇒ **退出码必须一致**（不同 ⇒ 判红：判据层的**结论随执行 shell 变** ⇒ 不可信）；
⇒ **输出必须逐字节一致**（不同 ⇒ 判红：诊断文案**随执行 shell 变**
⇒ 负控的「文案命中」判定本身就不可信）。

⚠⚠⚨ **为什么放在第 9 步内部、而不是新加一步**：
① **新增步骤会牵动 16 个步骤标记**（`› N/16`）+ **一条 `arch_need_ml` 门**
⇒ 步骤数一变 ⇒ 一批门同时失配 ⇒ 改动面无谓地放大；
⇒ ② 放进第 9 步内部 ⇒ **步骤数不变** ⇒ 那些门不受影响；
⇒ ③ **无自引用**：双跑逻辑在 `ci.sh`（入口）⇒ `ci-wiring.sh` 不跑 `ci.sh`
⇒ ⇒ 不会「审计器跑接线门 ⇒ 接线门又跑审计器 ⇒ 递归」；
⇒ ④ **通用**：任何新的分叉（不论什么构造、什么位置）都会被它抓住
⇒ 而批 DT 的规则只管「门型函数体内的 `echo`」⇒ **口径之外的部分靠这道门兜住**。

⚠⚠⚨ **实现纪律**（逐条都是已有纪律的沿用，不是新发明）：
⇒ **退出码接住**（批 CQ 纪律：不用管道读退出码 ⇒ `|| _w_rc=$?`）；
⇒ **差异落文件再读**（不用 `| head` ⇒ 不杀上游 SIGPIPE）；
⇒ **只在接线门绿时**才跑第二遍（红了就照旧报错退出 ⇒ 省一遍时间）；
⇒ **两遍的输出都要在 CI 日志里可见**（第一遍 `cat` 出来 ⇒ 保持逐条可观测性）。

**③ 落门 / 判据**

⚠ **批 DU 段新增 6 条**（插在批 DT 段之后）：

1. 双跑的**退出码**必须被接住（`^_w_dash_rc=0$`）；
2. 双跑的**第一遍**（`sh`）必须在；
3. 双跑的**第二遍**（`bash`）必须在（⚠ 少这一遍 ⇒ 就没有第二份结论可比
⇒ 「结论不随 shell 变」这条承诺**没人守** ⇒ 退回批 DT 那样只靠人工验收）；
4. 双跑的**退出码比对**必须在（这是「红绿一致」那半边的牙）；
5. 双跑的**输出比对**必须在（这是「文案一致」那半边的牙）；
6. ⚠⚠⚨ **双跑的**两份日志**不许落进 CI 工作目录**（`_W_DASH_LOG` 必须是
`${TMPDIR:-/tmp}/…` ⇒ 不许是 `$BUILD/…`）
⇒ ⚠ **理由（前瞻性加固，与 ④ 那次未能复现的分叉无因果关系）**：
双跑的第二遍会比第一遍**多看到第一遍的产物** ⇒ 若产物落在**会被扫描的目录**里
⇒ 第二遍的输入就与第一遍不同 ⇒ **双跑门会自己制造分叉** ⇒ **假红**
⇒ 批 DL 纪律：假红比假绿更坏 ⇒ 落点固定到 `TMPDIR` ⇒ 两遍输入严格一致。

⚠ **原地替换 3 处**（批 BM 纪律：原地替换不增行）：
① 接线门调用行那条门项**按新的双跑形态重生成**（正则从 `ci.sh` 现抽 + 程序化转义）；
② `ci.sh` 的 `exit [1-9]` 总数门：**38 → 40**（批 DU 段新增 2 处失败出口）；
③ 第 9 步「`ci-wiring.sh` 出现次数」门：**1 → 2**（⚠ `arch_need_count_in_step`
数的是**剥注释后第 N 步正文**里的命中 ⇒ 两遍调用 ⇒ **恰好 2 处**）。

⚠⚠⚨ **门项条数记三遍（批 CR 纪律）**：基线文件 / 审计器常量 `GATE_LINES_EXPECTED`
/ `ci-wiring.sh` 里那条门项的数字 ⇒ **1335 → 1341 三处同改**。

**④ 本批踩到的坑（全部实测，不是推演）**

⚠⚠⚨ **① 那次红绿分叉：根因未定位（如实记着，不粉饰）**
⚠ **现象（事实，有日志）**：批 DU **第一次端到端**跑 `ci.sh` ⇒
第 9 步双跑门判红：「✗ ⚠⚠⚨ 接线门在 sh 与 bash 下**退出码不同**（sh=0 / bash=1）」
⇒ `CI_RC=1`。
⚠ **分叉点（已定位到行）**：bash 版 `ci-wiring.sh` 里的
「✗ 抽取自检失败（剥注释口径漂移）」⇒
`scripts/check-deb-layout.sh`：**审计器侧 3743 字节 / shell 侧 0 字节**
⇒ 触发「✗ 未验证出口盘点失败」⇒ 接线门红 ⇒ 退出码 1。
⚠ **对照实验（8 类假设逐一排除，全部不复现）**：
① 父 shell 类型（`sh scripts/ci.sh` vs `bash scripts/ci.sh`）
⇒ ⚠ **排除**：两种父 shell 跑出来的**端到端日志逐字节相同**（`cmp -s` rc=0）；
② `build/` 里**上一次双跑日志是否预先存在** ⇒ **排除**（两种起始状态各跑一遍双跑序列 ⇒
dash rc=0 / bash rc=0 ⇒ 两版输出逐字节相同）；
③ `cwd` ⇒ **排除**（`ci.sh` 里的 `cd` 全在子 shell `( … )` 内 ⇒ cwd 不变）；
④ `$1` 参数形态（`.` vs 绝对路径）⇒ **排除**（7 组矩阵全 rc=0）；
⑤ CI 的三个 `export`（`LD_LIBRARY_PATH` / `QT_PLUGIN_PATH` / `QT_QPA_PLATFORM`）
⇒ **排除**；
⑥ `PATH` 与 `sh` 垫片 ⇒ **排除**（`which -a sh` 只有 `/usr/bin/sh` 与 `/bin/sh` ⇒ 都是 dash；
PATH 首项 `~/.minimax/shims` 里**只有** `rm`）；
⑦ 重复跑 / probe 文件预先存在 ⇒ **排除**；
⑧ 解释器版本 ⇒ 同 ⑥。
⚠⚠⚨ **⇒ 结论：在当前代码状态下**无法复现** ⇒ **根因未定位** ⇒ 如实记为待查。
⚠⚠⚨ **但绝不当偶发忽略**（假红比假绿更坏）：
① **双跑门保留**（它会持续抓 —— 这次它确实抓到了）；
② 落一条**前瞻性加固**门（③ 的第 6 条）⇒ 把「双跑自己制造分叉」这个**独立**的
设计隐患堵掉（⚠ **明说**：这条加固与那次未能复现的分叉**无因果关系**）；
③ 台账与提交信息里**明写「根因未定位」+ 已排除清单** ⇒ 不让下一个人误以为「已查清」。

⚠⚠⚨ **② 门项生成器不幂等**：已改过的条目再跑会「无差异」⇒ assert 失败
⇒ ⇒ **写回前先抛异常 ⇒ 未写回** ⇒ 可安全重跑（批 DR 纪律沿用）。

⚠⚠⚨ **③ 插入锚点必须是「门项里的形态」**：第 6 条新门项的锚点我最初写成
`cmp -s "$_W_DASH_LOG" "$_W_BASH_LOG"` ⇒ 在 `ci-wiring.sh` 里它是**正则**
⇒ 里面的 `$` 是**转义**的（`"\$_W_DASH_LOG"`）⇒ 锚点命中数 **0**
⇒ ⇒ 锚点要按**转义后的形态**写。

⚠⚠⚨ **④ shell 里的字符串拼接不是「路径拼接」**：
`_WS="$SRC/scripts/ci-wiring""sh"` ⇒ shell 拼出来是 `…/ci-wiringsh`
（**没有点**）⇒ 诊断脚本找不到文件 ⇒ 报「没有那个文件或目录」。
⇒ 正确写法：`_WS="$SRC/scripts/ci-wiring".sh`（**点留在外面**）。

⚠⚠⚨ **⑤ `grep -c` 计数**行数**、`grep -o | wc -l` 计数**出现次数** ⇒
同一行出现 2 次时两者差 1 ⇒ ⚠ **我自己被这个吓了一次**（以为诊断块插桩弄丢了一行）
⇒ ⚠ 核对办法：`cmp -s` 与备份**逐字节比** + `git diff` 看**相对 HEAD 的完整改动**。

⚠⚠⚨ **⑥ 恒真探针的条件数要实测核对，不能推算**：本批在 `ci.sh` 里**新增 3 个 `if`**
⇒ 照理应 **999 → 1002**；⚠ **实测是 1001** ⇒ 差 1 ⇒
⇒ 用 **HEAD 版 `ci.sh` 对照测**（999）⇒ 查明是「新增 3 个 if、同时**删掉 1 个**旧的
`if sh …; then`」⇒ **+2** ⇒ **999 → 1001** ⇒ 对上了。
⇒ ⚠ **教训**：条件数**不是**「我加了几个 if」⇒ 门项改写会**同时删**旧形态。

⚠⚠⚨ **⑦ 「期望写错」与「规则有洞」在 harness 里长得一模一样**：
负控第 3 次跑之前，NC1/NC2 的红是**双断言**成立（双跑门红 **且** 批 DT 的审计器规则也红）
⇒ ⚠ 读负控日志时必须先问「**这条变异到底改了什么**」⇒ 再看它红在哪一条上。

**⑤ 负控 8 真红**

⚠ **8 例**（harness 沿用批 DP / DR / DS / DT 的纪律）：
scratch 树复制**整个仓根**（含 `linux/` / `macos/` / `assets/`，`symlinks=True`）、
备份**在变异之前**取且**备份路径与内容分开存**、**每个用例一棵新树**（⇒ 天然满足
「变异前先还原到原始字节」）、**变异前先跑一遍确认是绿的**（否则用例无效）、
变异后**自己先自证语法**（`sh -n` / `py_compile`）⇒ 变异不得破坏被测文件的语法、
退出码**不经管道读**、**启动前自检**、**atexit 兜底还原**、
洁净度判据 = **与原始字节逐字节相同**。

⚠ **用例（全部真红）**：
① **NC1 · 核心对照**：门型输出改回 `echo` ⇒ 输出分叉 ⇒ 双跑门必须红
⇒ ⚠ **双断言**成立（双跑门 rc=1 **且** 批 DT 的审计器规则也红 rc=2）
⇒ ⚠ 这是「改前是全绿假绿」的那个核心对照；
② **NC2**：门型输出改回 `echo`（报错分支）⇒ 同样分叉；
③ **NC3**：双跑的**第二遍**被摘（bash 那遍）⇒ 没有第二份结论可比；
④ **NC4**：双跑的**输出比对**被摘（⇒ 只比退出码）；
⑤ **NC5**：双跑的**退出码比对**被摘（⇒ 只比输出）；
⑥ **NC6**：双跑的**退出码**没被接住（批 CQ 纪律）；
⑦ **NC7**：第 9 步的**接线门动作**被删（门自己被删了，门也得红）；
⑧ **NC8**：双跑的**日志落点**被改回 CI 工作目录（⇒ 双跑会自己制造分叉）。

⚠⚠⚨ **检查对象是 `ci.sh` 的第 9 步**（**抽取**出来跑 ⇒ 批 CF 纪律「抽取而非复刻」）
⇒ 不跑整个 `ci.sh`（会编译 ⇒ 太慢）。

**⑥ 数字**

⚠ **门项条数 1335 → 1341**（批 DU 段 **6 条**，**三处同改**）；
⚠ **门项执行次数 1338 → 1344**（+6）；
⚠ **恒真探针条件 999 → 1001**（⚠ +3 个新 `if`、**-1** 个被删的旧 `if` ⇒ 净 +2）；
⚠ `ci.sh` 的 `exit [1-9]` 总数 **38 → 40**；
⚠ 第 9 步 `ci-wiring.sh` 出现次数 **1 → 2**；
⚠ **审计器 `--list` rc=0（1341/1341）**；**接线门 rc=0（1344 项全绿）**；
⚠ **两版接线门输出逐字节相同**（`cmp -s` rc=0）；
⚠ `|| true` 盘点 **33 处**、未验证出口盘点 **21 组 / 73 处**、
孤儿探针 **32 脚本 / 白名单 10 条** ⇒ **均不变**；
⚠ **负控 8 真红**；累计 **1276/1276**；
⚠ **`ci.sh` 16/16 步跑完但 rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**。

**⑦ 已知边界（如实记着）**

⚠⚠⚨ **那次红绿分叉的根因未定位**（④① 已排除 8 类假设）⇒ **待查**
⇒ 但双跑门保留且**确实抓到过** ⇒ 这条承诺不是「理论风险」；
⚠ **双跑只覆盖 `ci-wiring.sh` 一个脚本** ⇒ 其它判据脚本
（`ci-d2.sh` / `ci-orphan-probe.sh` / `contract-check.sh` / `check-deb-layout.sh` …）
**尚未双跑** ⇒ ⇒ **下一批候选**（⚠ 扩面要先解决「哪些脚本跑得动 / 有无副作用 /
名单维护」三个问题）；
⚠⚠⚨ **「输出逐字节比对」会被随机量污染** ⇒ 批 DT 已实测：
`contract-check.sh` 的 `mktemp -d` 沙箱名是**随机**的 ⇒ 两遍输出必然不同
⇒ ⇒ **扩面到它之前必须先解决**（否则就是一道**恒红**的门 ⇒ 假红）；
⚠ 双跑的第二遍用 `bash`、第一遍用 `sh` ⇒ **接线门要跑两遍** ⇒ CI 时间 +1 遍；
⚠ 双跑门在 `ci.sh` 里 ⇒ **手工跑 `ci-wiring.sh` 时没有这道门**
⇒ 负控只能靠「抽取第 9 步单独跑」才能精确打它（批 CF 纪律）；
⚠ 落点那条门是**前瞻性**的 ⇒ ⚠ **实测证明当前 `build/` 不被扫描**
（`ci-wiring.sh` 只扫 `$SRC/<具体目录>`、盘点范围是 `deepin/scripts` + `macos/scripts`）
⇒ 那条门防的是**将来**某条门项引入 `$BUILD` 扫描 ⇒ ⚠ **不是**那次分叉的根因；
⚠⚠⚨ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

### E.2ce 双跑覆盖面不许被悄悄改窄（批 DV）

**① 起因（实测坐实，不是推演）**

⚠⚠⚨ **批 DU 只覆盖了一个脚本**：批 DU 把批 DT 的承诺（判据层的**结论**不许随执行 shell 变）
装上了牙齿 —— `ci.sh` 第 9 步**双跑接线门** ⇒ 输出与退出码都必须一致。
⇒ ⚠⚠⚨ **但接线门只是 `scripts/` 下 19 个判据脚本里的一个** ⇒
**别的判据脚本的结论照样可能随执行 shell 变** ⇒ 而**没有任何一道门**会发现。

⚠⚠⚨ **批 DT 立这条承诺时留了个洞（批 DT 自己写在 README 末尾）**：
「⚠ **只管 `ci-wiring.sh` 的门型函数** ⇒ 其它判据脚本的 `echo` 仍可能分叉
⇒ 实测当前一致 ⇒ ⇒ 且**负控靠文案的只有 python 脚本** ⇒ ⇒ 残余风险小」
⇒ ⇒ **「实测当前一致」是**人工**的一次性验收** ⇒ 不是门 ⇒ 明天有人改一行就可能悄悄变。

⚠ **实测勘察（批 DV 第一步，逐个跑过）**：
`deepin/scripts` 下被 CI 调用的 shell 判据脚本共 **10 个** ⇒ 逐个在 `sh` 与 `bash` 下各跑一遍：

| 脚本 | 两版输出 | 两版退出码 | 耗时 | 结论 |
|---|---|---|---|---|
| `ci-wiring.sh` | 逐字节相同 ✓ | 一致 ✓ | 12.4 s | 已由批 DU 双跑 |
| `ci-d2.sh` | 逐字节相同 ✓ | 一致 ✓ | 79 ms | **可双跑** |
| `ci-orphan-probe.sh` | 逐字节相同 ✓ | 一致 ✓ | 135 ms | **可双跑** |
| `ci-platform-probe.sh` | 逐字节相同 ✓ | 一致 ✓ | 1.1 s | 参数含二进制路径 |
| `ci-docs-lang-probe.sh` | 逐字节相同 ✓ | 一致 ✓ | 73 ms | 参数含二进制路径 |
| `ci-divider-probe.sh` | 逐字节相同 ✓ | 一致 ✓ | 42 ms | 参数含二进制路径 |
| `probe-agent-tool-surface.sh` | 逐字节相同 ✓ | 一致 ✓ | 137 ms | 参数含二进制路径 + 引擎 |
| `check-deb-layout.sh` | 逐字节相同 ✓ | 一致 ✓ | 135 ms | 需 deb 产物（第 11 步才构建）|
| ⚠ `contract-check.sh` | **✗ 不同** | 一致 ✓ | 9.8 s | **随机沙箱名 + 时间戳文件名** |
| `build-deb.sh` | 未测 | — | — | **有副作用**（构建 deb）|

⚠⚠⚨ **`contract-check.sh` 那两行差异**（**实测原文**）：
`› 沙箱：/tmp/dd-contract.8dV0PR` vs `/tmp/dd-contract.A6jO3O`
⇒ **随机沙箱名** ⇒ 逐字节比对在它身上**必然恒红** ⇒ **假红**（批 DL：假红比假绿更坏）
⇒ ⇒ 本批**不做归一化**（归一化会把「真实差异」也吃掉 ⇒ 假绿风险更大）⇒ **豁免 + 写理由**。

**② 修法（登记册驱动的双跑覆盖面门）**

⚠ **新增仓内常驻脚本 `scripts/ci-shell-parity.sh`**：读登记册 ⇒ 对「标 DUAL 且双跑位置是本脚本」的条目
⇒ `sh` 跑一遍 + `bash` 跑一遍 ⇒ **退出码必须一致** + **输出必须逐字节一致** ⇒ 任一不同 ⇒ 判红。

⚠ **新增仓内常驻登记册 `scripts/ci-shell-parity.baseline`**（TAB 分隔 4 段：
`路径 | 状态 | 双跑位置 | 理由`）⇒ **CI 里跑的每一个 shell 判据脚本都必须在册**
⇒ 要么 `DUAL`（被双跑），要么 `EXEMPT`（豁免 + **必须**写理由）。

⚠⚠⚨ **为什么登记册必须连「豁免的」也记**：
若只记被双跑的那些 ⇒ **覆盖面可以被悄悄改窄**（新增一个判据脚本 ⇒ 不双跑 ⇒ 没人知道）
⇒ 这正是批 DQ 立过的教训（「一条本该被登记的承诺，在三个目录上从未生效」）
⇒ ⇒ **三个数字互相咬合**：登记册数据行 **11** = `DUAL` **3** + `EXEMPT` **8**
⇒ 改任何一边 ⇒ 另外两边对不上 ⇒ **红**。

⚠ **「入口共用 ≠ 口径共用」**（批 DG 教训）：接线门由 `ci.sh` 第 9 步双跑（批 DU），
其余由 `ci-shell-parity.sh` 双跑 ⇒ 两边各算各的 ⇒ 登记册里用「**双跑位置**」这一列区分
⇒ ⇒ **不许**把 `ci.sh` 双跑的条目也塞进 `ci-shell-parity.sh`（那会白跑一遍接线门，14 秒）。

⚠ **`ci.sh` 的改动只有一处**：第 9 步末尾加
`if ! sh "$SRC/scripts/ci-shell-parity.sh" "$SRC"; then … exit 1; fi`
⇒ ⚠ **不新增步骤**（新增步骤会牵动 16 个步骤标记 + 一条 `arch_need_ml` 门）
⇒ ⚠ **无自引用**（本门只跑登记册里标 `parity` 的条目 ⇒ 不跑自己 ⇒ 自引用会递归）
⇒ ⚠ 孤儿探针**不必改** —— 它的可达判定认的是 `sh <路径>` 形态 ⇒ 调用点保留了 `sh` 前缀 ✓。

**③ 落门 / 判据**

⚠ **批 DV 段新增 19 条**（**单独成块**，插在批 DU 段之后）⇒
⚠ **单独成块的两个理由**：① 本段的承诺（「CI 里跑的**每一个** shell 判据脚本都必须在册」）
**必须出现在 CI 输出里** ⇒ 不许只挂在代码里 ⇒ 判据层的**结论不许悄悄消失**；
② 红的时候**不许被误诊**成「批 DS 段有门项红」（⚠ 批 DT / DU / DV 的门项原本都并进了
批 DS 段那一块）⇒ ⇒ 批 DS 段那条的**标签**同步订正为「批 DS / DT / DU 段」
（⚠ **只改标签** ⇒ 不改任何门项语义）。
① 登记册**数据行数**必须恰好 **11**；
② 登记册里 `DUAL` 必须恰好 **3** 条；
③ 登记册里 `EXEMPT` 必须恰好 **8** 条；
④ **逐条钉住（3 条）**：`ci-wiring.sh`（位置 `ci.sh`）/ `ci-d2.sh`（位置 `parity`）/
`ci-orphan-probe.sh`（位置 `parity`）各 1 条 ⇒ ⚠⚠⚨ **这 3 条堵的是真洞**：
否则把某条 `DUAL` 的「位置」从 `parity` 改成 `ci.sh` ⇒ 它就不被双跑了
⇒ 而**别的门不会红** ⇒ 覆盖面的牙就漏了 ⇒ 且反方向也堵 ⇒ 两个方向都红）；
⑤ 双跑脚本的**登记册路径常量**必须在；
⑥ 读不到登记册必须 **fail closed**（读不到 ⇒ 当成「没有条目」⇒ 覆盖面变成空的 ⇒ **假绿**）；
⑦ **豁免必须写理由**（否则「为什么不双跑」没人负责）；
⑧⑨ 两遍的**退出码**必须都被接住（批 CQ 纪律）；
⑩ **退出码比对**必须在；
⑪ **输出比对**必须在；
⑫ 差异必须**落文件**再读前 20 行（别用管道接 head ⇒ 杀上游 SIGPIPE ⇒ 诊断失真）；
⑬ CI 第 9 步**必须真的跑**这道门（脚本在但不跑 = 没有门）；
⑭ 该门必须**还在第 9 步里**（挪走 ⇒ 依赖未就位 ⇒ 门静默失效）；
⑮ 双跑脚本必须把**传给子判据脚本的路径**归一化成**绝对路径**（⚠⚠⚨ 实测坐实的假绿 ⇒ 见 ④⑥）；
⑯ **第一遍**的调用处必须真的用绝对路径（⚠ 只钉住 ⑮ 那行**不够** ⇒ 把调用处改回去 ⇒
归一化**形同虚设** ⇒ **两遍一起红**那个洞又回来了 ⇒ 假绿）；
⑰ **第二遍**的调用处必须真的用绝对路径（⚠ 同上 ⇒ 只改一遍 ⇒ 两遍**输入就不同** ⇒
双跑**自己制造分叉** ⇒ 假红）。

⚠ **原地替换 5 处**（批 BM 纪律：原地替换不增行）：
① `ci.sh` 的 `exit [1-9]` 总数门：**40 → 41**（本批新增 1 处失败出口）；
② 恒真探针的**范围基线** `shell 18 → 19`（新增 `scripts/ci-shell-parity.sh`）
⇒ ⚠ **连带**：孤儿探针的断言脚本数 **18 → 19**（deepin 侧）/ **32 → 33**（三平台合计）；
③ 范围基线那条门项**重生成**（`^shell 18$` → `^shell 19$`）；
④⑤ 批 CP 的**两条配对门**（它们数的是**段级 trailer 的数量**）：
**69 → 70**（`ARCH_ANY_FAIL=1`）与 **70 → 71**（`ARCH_FAIL=0`）
⇒ ⚠⚠⚨ **单独多一个段 ⇒ 这两个数字必须同步** ⇒ 否则接线门红
（实测：改完当场红 ⇒ 审计器 rc=4 + 接线门 rc=1 ⇒ 两条配对门一起报「期望 ≠ 实际」）。

⚠⚠⚨ **门项条数记三遍（批 CR 纪律）**：基线文件 / 审计器常量 `GATE_LINES_EXPECTED`
/ `ci-wiring.sh` 里那条门项的数字 ⇒ **1341 → 1357 → 1360 三处同改**
（⚠ 1357 → 1360 是本轮**补 3 条**（⑮⑯⑰）⇒ **三处同改**）。

**④ 本批踩到的坑（全部实测）**

⚠⚠⚨ **① 「新脚本 ⇒ 撞既有门项的计数」**：新增一个 `.sh` ⇒ 连带三处
⇒ 恒真探针的**范围基线**（`shell 18`）、孤儿探针的**断言脚本数**（18 / 32）
⇒ ⚠ **孤儿探针自己报的是 19 / 33**（实测）⇒ ⇒ 这类数字**不被门钉住时**只能靠跑出来看
⇒ ⇒ 「新增判据脚本」这件事的连带面，**比看上去大**。

⚠⚠⚨ **② 「文案撞盘点关键词」**：新脚本里写了一句
「⇒ 双跑做不了 ⇒ **未验证不许被当成通过**」⇒ ⚠⚠⚨ 被
`ci-unverified-audit.py` 当成「**未验证的逻辑出口**」⇒ 盘点报
「实测有、登记册没有：deepin/scripts/ci-shell-parity.sh/失败上报=1」⇒ 红
⇒ ⇒ 改文案（「这一组**根本没验过**」）⇒ 不新增登记册条目。
⇒ ⚠ **教训**：新增报错文案必须避开盘点关键词（`SKIP|未验证|不算通过|跳过|无法验证|not verified`）。

⚠⚠⚨ **③ 「孤儿探针的可达判定」是硬约束**：它的正则是
`(sh|bash|python3?)[[:space:]]+"?<路径>` ⇒ ⚠⚠⚨ **调用点必须保留 `sh` / `bash` 前缀**
⇒ ⇒ 否则 `ci-shell-parity.sh` 会被判成「游离断言脚本」⇒ **假红**
⇒ ⇒ 这条约束**反过来决定了修法形态**（不写成 `dual_run "$SRC/scripts/x.sh"` 那种通用形态）。

⚠⚠⚨ **④ 「归一化」这条路本批明确不走**：`contract-check.sh` 的随机沙箱名会让逐字节比对恒红
⇒ 两条路：① 归一化（⚠⚠⚨ **会把真实差异也吃掉 ⇒ 假绿风险更大**）② **豁免 + 写理由**
⇒ ⇒ 选 ② ⇒ ⇒ **「恒红」宁可豁免也不假绿**。

⚠⚠⚨ **⑤ 门项生成器拒绝含反引号的说明文字**（沿用批 DT 教训）：
第 11 条说明文字里写了「别用 `| head`」⇒ 反引号 ⇒ 生成器**拒绝生成**（未写回）
⇒ 改成「别用管道接 head」⇒ 通过。

⚠⚠⚨ **⑥ 「相对路径 ⇒ 两遍一起红 ⇒ 空洞的一致」= 假绿（实测坐实，本轮修掉）**
⚠ **实测**：双跑脚本把**相对路径**（`.`）传给子判据脚本 ⇒ 子脚本按**自己的**口径去解析
⇒ 孤儿探针把**整棵树**判成「游离」（实测 17 个）⇒ **两遍都红、退出码相同、输出逐字节相同**
⇒ ⇒ 双跑门报「✓ 在 sh 与 bash 下**输出与退出码一致**」⇒ ⚠⚠⚨ **假绿**：
门打了绿勾，但它比较的**根本不是真判据**。
⇒ ⚠ **CI 里碰不到**（`ci.sh` 传的是**绝对路径**）⇒ ⚠ 但**单独跑**这个门就中招
⇒ ⇒ **修法**：双跑脚本内部把路径**归一化成绝对路径**（`SRC_ABS`）⇒ 两遍跑的是真判据；
⇒ ⇒ ⚠ **只归一化不够** ⇒ ⑯⑰ 两条门项把**两个调用处都**钉住。
⚠⚠⚨ **另一半的教训**：这个洞**只能靠形态门项抓** ⇒ 「门变红」**不等于**「行为被抓住」
⇒ ⇒ 负控必须**同时**断言「门红」**和**「行为符合预期」（本轮 NC10 / NC11 就是干这个的）。

⚠⚠⚨ **⑦ 「磁盘满」会把负控结果**弄假**（实测坐实，本轮踩到）**
⚠ harness **每例复制整个仓根**（含 `.git` ⇒ 实测 516M）⇒ 而 `/tmp` 是 **16G tmpfs**
⇒ 历批 harness 留下的 scratch 树堆在里面 ⇒ ⚠⚠⚨ **盘满**（实测 `cp: 设备上没有空间`）
⇒ ⇒ NC11 报出来的**不是**预期文案 ⇒ ⚠⚠⚨ 差点被当成「期望写错」而**改错断言**
⇒ ⇒ ⚠ **「期望写错」和「环境坏掉」在 harness 里长得一模一样** ⇒ 必须**先查环境**
⇒ ⇒ **修法**：scratch 树改放 **home 分区**（`~/.cache/`，不占 tmpfs）
＋ **启动前自检磁盘剩余空间**（不足 ⇒ 直接中止）⇒ ⇒ 清掉历批遗留的 12 棵 scratch 树
（实测释放约 13G）。

⚠⚠⚨ **⑧ 「两遍输入不同」的诊断会**误诊**成「结论随 shell 变」（实测）**
⚠ 变异「只把第二遍改回相对路径」⇒ 第一遍拿绝对路径（绿，rc=0）、第二遍拿相对路径（红，rc=1）
⇒ parity 门实测报：「✗ ⚠⚠⚨ deepin/scripts/ci-orphan-probe.sh 在 sh 与 bash 下**退出码不同**
（sh=0 / bash=1）⇒ 判据层的**结论随执行 shell 变** ⇒ 不可信（批 DT）」
⇒ ⚠⚠⚨ **真实原因是「两遍输入就不同」**，与 shell 行为**无关** ⇒ ⇒ **诊断指错了方向**
⇒ ⚠ **退出码比对先于输出比对触发** ⇒ 文案是「退出码不同」而不是「输出不同」
（⚠ 本轮**实测**过 ⇒ 不是推演）；
⇒ ⇒ 这就是为什么**两个调用处都要被形态门项钉住**：形态门项盯的是「调用处用的哪个变量」
⇒ 病因一眼可见；行为门（双跑）只能看到**症状**。

**⑤ 负控 11 真红**

⚠ **11 例**（harness 沿用批 DP / DR / DS / DT / DU 的纪律）：scratch 树复制**整个仓根**
（`symlinks=True`）、备份**在变异之前**取且**备份路径与内容分开存**、**每个用例一棵新树**、
**变异前先跑一遍确认是绿的**、变异后**自己先自证语法**（`sh -n`）、
退出码**不经管道读**、**启动前自检**、**atexit 兜底还原**、
洁净度判据 = **与原始字节逐字节相同**。

⚠ **用例**：
① **NC1**：登记册里删掉一个 `DUAL` 条目 ⇒ 覆盖面被悄悄改窄 ⇒ 接线门红；
② **NC2**：登记册里删掉一个 `EXEMPT` 条目 ⇒ 「谁被豁免」没人知道 ⇒ 接线门红；
③ **NC3**：某条 `EXEMPT` 的**理由被清空** ⇒ 「为什么不双跑」没人负责 ⇒ 双跑门红（fail closed）；
④ **NC4**：双跑的**退出码比对**被摘（⇒ 只比输出）⇒ 接线门红；
⑤ **NC5**：双跑的**输出比对**被摘（⇒ 只比退出码）⇒ 接线门红；
⑥ **NC6**：双跑的**退出码**没被接住（批 CQ 纪律）⇒ 接线门红；
⑦ **NC7**：CI 里对这道门的**调用被删** ⇒ **双断言**（接线门红 **且** 孤儿探针红
⇒ `ci-shell-parity.sh` 变成游离脚本）；
⑧ **NC8**：双跑脚本的**登记册路径常量**改错 ⇒ 「谁被双跑」无处可查 ⇒ 接线门红；
⑨ **NC9 · 核心对照**：在被双跑的脚本里制造一次**真实的 sh/bash 分叉**
（`echo` 的反斜杠：dash 解释、bash 不解释）⇒ **双跑门必须红**
（⚠ 这一例**依赖**相对路径归一化已经修好 ⇒ 子判据脚本拿到绝对路径 ⇒ 真判据在跑
⇒ 否则孤儿探针**两遍都红** ⇒ 那行汇总**压根不打印** ⇒ 分叉**不可见** ⇒ 门不红）；
⑩ **NC10 · 空洞的一致**：两个调用处**都**改回相对路径 ⇒ 两遍**一起红**
⇒ **双断言**：接线门红 **且** parity 门**仍然绿**（且子脚本日志里**没有绿判据的结论**）
⇒ ⇒ 证明「这个洞**只能**靠形态门项抓」；
⑪ **NC11 · 误诊**：**只**改第二遍 ⇒ 两遍**输入就不同** ⇒ parity 门报
「**退出码不同**（sh=0 / bash=1）」（⚠ **实测**：退出码比对**先于**输出比对触发 ⇒ 文案是
「退出码不同」而不是「输出不同」）⇒ ⚠⚠⚨ **误诊**：真实原因是**输入不同**，
不是 shell 行为差异 ⇒ ⇒ 两个调用处必须**都**被**形态门项**钉住
（形态门项看的是「调用处用的哪个变量」⇒ 病因一眼可见；行为门只能看到症状）。

**⑥ 数字**

⚠ **门项条数 1341 → 1357 → 1360**（批 DV 段 **19 条**，**三处同改**）；
⚠ **门项执行次数 1344 → 1360 → 1363**（+19）；
⚠ **恒真探针条件 1001 → 1013 → 1014**（⚠ parity 脚本 11 个 if/while + `ci.sh` 1 个 = **+12**
⇒ 后面**单独成块**又带来 **+1**（段级 trailer 的 `if`）⇒ 实测对上）；
⚠ `ci.sh` 的 `exit [1-9]` 总数 **40 → 41**；
⚠ 恒真探针范围基线 `shell` **18 → 19**；
⚠ 孤儿探针断言脚本数 **18 → 19**（deepin）/ **32 → 33**（三平台）；
⚠ 批 CP 两条配对门 **69 → 70** / **70 → 71**（单独多一个段 ⇒ 段级 trailer 多 1 处）；
⚠ **审计器 `--list` rc=0（1360/1360）**；**接线门 rc=0（1363 项全绿）**；
⚠ **双跑覆盖面门 rc=0**（双跑 **2** 个 + 豁免 **8** 个；⚠ **相对路径与绝对路径两种调用都试过**）；
⚠ `|| true` 盘点 **33 处**、未验证出口盘点 **21 组 / 73 处** ⇒ **均不变**；
⚠ **负控 11 真红**；累计 **1287/1287**；
⚠ **`ci.sh` 16/16 步跑完但 rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**。

**⑦ 已知边界（如实记着）**

⚠⚠⚨ **覆盖面只扩到 3 个脚本**（接线门 + `ci-d2.sh` + `ci-orphan-probe.sh`）⇒
⚠ **4 个探针类**（`ci-platform-probe.sh` / `ci-docs-lang-probe.sh` /
`ci-divider-probe.sh` / `probe-agent-tool-surface.sh`）**本批未双跑**
⇒ 理由 = **参数含二进制路径与运行库环境**，而登记册当前只按仓库根传参 ⇒
⇒ **传参机制未就位** ⇒ ⇒ **下一批候选**（⚠ 实测它们两版**一致** ⇒ 值得做）；
⚠ `build-deb.sh`（**有副作用**：构建 deb）⇒ **不双跑**；
⚠ `check-deb-layout.sh`（需 deb 产物，**第 11 步才构建**）⇒ 双跑点在其之前 ⇒
⚠ 要双跑得把双跑点挪到第 12 步之后 ⇒ ⇒ **下一批候选**；
⚠⚠⚨ `contract-check.sh` **豁免**（随机沙箱名 + 时间戳文件名 ⇒ 逐字节比对**必然恒红** ⇒ 假红）
⇒ ⇒ 若将来要双跑它，**必须先解决随机量**（归一化或改脚本让随机量不进输出）⇒
⚠⚠⚨ **本批明确不做归一化**（会把真实差异也吃掉 ⇒ 假绿风险更大）；
⚠ **`ci-shell-parity.sh` 自己不被双跑**（**自引用 ⇒ 递归**）⇒ 它的正确性
由**门项逐字钉住 + 负控**保证（不靠双跑保证）；
⚠⚠⚨ **登记册的「理由写得对不对」机器判不了** ⇒ 只能判「非空」⇒
⚠ **危险方向靠人工**（批 CM 同款边界）；
⚠ **双跑只比「退出码 + 逐字节输出」** ⇒ 若脚本的**副作用**在两遍之间不同（写文件、累积状态）
⇒ 本批登记册**只收无副作用的** ⇒ ⚠ 扩面时必须**重新审**这一条；
⚠⚠⚨ **「双跑位置」列是人为约定** ⇒ 本批用**逐条钉住 3 条 DUAL 条目的路径 + 位置**来堵
（两个方向都红）⇒ ⚠ 但**将来扩面**时必须**同步加钉**（否则新条目不受钉）⇒ ⇒ **靠人**；
⚠⚠⚨ **双跑门只判「两版结论是否一致」，不判「结论本身对不对」** ⇒ 子脚本**两遍都红**
⇒ 双跑门**仍报「一致」** ⇒ ⇒ 本轮修的正是这一类（**空洞的一致**）
⇒ ⇒ 修法是**让两遍都跑真判据**（绝对路径），**不是**给双跑门加严
⇒ ⚠⚠⚨ **加严会假红**：「未验证」用专属退出码 **3**（批 CL）⇒ 子脚本 exit 3 是**合法结论**
⇒ 若要求「必须都退出 0」⇒ 本机缺工具时**恒红** ⇒ ⇒ **判据层的「未验证」不是失败**；
⚠⚠⚨ **单独多一个段 ⇒ 批 CP 的两条配对门期望数必须同步**（它们数段级 trailer）⇒ 否则接线门红；
⚠⚠⚨ **批 DT / DU / DV 的门项原本并进批 DS 段那一块** ⇒ 红的时候会被**误诊**成
「批 DS 段有门项红」⇒ 本轮把 DV 拆成独立块（⚠ DT / DU 的标签一并订正为「批 DS / DT / DU 段」）
⇒ ⇒ ⚠ **DT / DU 的门项仍在 DS 段那一块**（本轮不动已提交批次的布局 ⇒ 只订正标签）；
⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

### E.2cf 双跑覆盖面扩到探针类（批 DW）

**① 起因（实测，不是推演）**

批 DV 把覆盖面做成**登记册驱动**（`DUAL` / `EXEMPT` + 理由）⇒ 但探针类 **4** 个脚本
（`ci-platform-probe.sh` / `ci-docs-lang-probe.sh` / `ci-divider-probe.sh` /
`probe-agent-tool-surface.sh`）**留在 `EXEMPT`** ⇒ 理由写的是「参数含二进制路径与运行库环境
⇒ 传参机制未就位 ⇒ 下一批」⇒ ⇒ **本批就是那个下一批**。

⚠⚠⚨ **但批 DV 的勘察里有个洞（本批实测才发现）**：那 4 个探针在 DV 勘察里「两版输出逐字节相同」
⇒ 看起来**只差传参机制** ⇒ ⚠⚠⚨ **实测它们会写盘**：`probe-agent-tool-surface.sh` 跑完
**多出 4 个文件** ⇒ 二进制会写 Qt 缓存 ⇒ ⇒ 「双跑会不会**自己制造分叉**」
（第二遍比第一遍多看到第一遍的产物 ⇒ 批 DU 立过的那个坑）**必须实测**，不能推演。

**② 决定性实测（批 DW 的第一步）**

⚠⚠⚨ **第一次测不算数**：缓存早就存在了 ⇒ **没测到**「第一遍建、第二遍看」的真场景
⇒ ⇒ 用**独立 `XDG_CONFIG_HOME`**（每个干净起点**同名**，避免路径混进输出）重测：

| 探针 | 首遍（建）vs 同目录第二遍（看） | 干净起点 A vs B | 干净起点新建文件数 |
|---|---|---|---|
| `ci-platform-probe.sh` | 逐字节相同 ✓ | 逐字节相同 ✓ | 0 |
| `ci-docs-lang-probe.sh` | 逐字节相同 ✓ | 逐字节相同 ✓ | 0 |
| `ci-divider-probe.sh` | 逐字节相同 ✓ | 逐字节相同 ✓ | 0 |
| `probe-agent-tool-surface.sh` | 逐字节相同 ✓ | 逐字节相同 ✓ | 4 |

⇒ ⇒ **双跑不会自己制造分叉** ⇒ 4 个探针**可以**进双跑。

**③ 修法（登记册加「参数」列 + 二进制路径单一真相源）**

⚠⚠⚨ **「入口共用 ≠ 参数共用」**（批 DG 教训）：`ci-d2.sh` 吃的是**源码根**，
而 4 个探针吃的是**已构建的二进制** ⇒ ⇒ 登记册从 **4 段变 5 段**
（`路径 | 状态 | 双跑位置 | **参数** | 理由`）⇒ 参数列只许 `src` / `bin`
⇒ ⚠ **靠脚本名猜参数 ⇒ 就是把约定藏起来** ⇒ 换个参数 ⇒ 没人发现。

⚠ **二进制路径只有一个来源**：`ci.sh` 里 `export BIN`（**单一真相源**）
⇒ ⇒ 两个地方各算一遍 ⇒ 算出不同路径 ⇒ 又一个新洞 ⇒ ⇒ 登记册里参数列 = `bin` 的条目就靠它。

⚠⚠⚨ **`bin` 的前置检查（fail closed）**：`BIN` 没设 / **不是文件** / 不可执行 ⇒ **拒绝继续**
⇒ ⚠ **为什么必须前置挡**：探针拿到不存在的二进制 ⇒ 走「用法错」那条路（`exit 2`）
⇒ ⇒ **两遍都那样** ⇒ 「两版一致」变成**空洞的一致** ⇒ **假绿**（批 DW 前脚刚修掉的那类洞）。

⚠⚠⚨ **本批实测踩出来的第三个坑**：`-x` 对**目录**也返回 **true** ⇒ 只查 `-x` ⇒
**目录能冒充二进制** ⇒ 喂给探针的是目录 ⇒ 探针**不会**走「用法错」⇒ 而是 **exec 时才炸**
⇒ 而两个 shell 的**报错文案不同**（dash 说 `Permission denied` / bash 说 `是一个目录`）
⇒ ⇒ 双跑门会报「**输出不同**」⇒ **误诊**（真根因是「二进制不是文件」，不是「随 shell 变」）
⇒ ⇒ 前置检查必须**同时**查 `-f` ⇒ 本批已加固（门项同步重生成）⇒ 文案也同步改成
「不是一个可执行的二进制**文件**」。

⚠⚠⚨ **「输出不同」那条文案也补了退出码**（`退出码 sh=… / bash=…`）⇒ 读者一眼能看出
「两遍是不是**都没跑通**」⇒ ⚠ 只说「输出不同」⇒ 「两遍都失败」这个事实就被吞掉了
⇒ **结论悄悄消失** ⇒ 本批把它补回来。

⚠⚠⚨ **子判据的退出码必须被报出来**：门原来只说「两版一致」⇒ 读者看不出它到底**跑通没跑通**
⇒ ⇒ 现在逐条打印「`✓ <脚本>：两版一致（退出码 0 ⇒ 判据**真的跑通**）`」
⇒ ⇒ 退出码非 0 时说「这一组**没跑通**；结论本身由该脚本自己的门负责」
⇒ ⇒ **结论不许悄悄消失**（门打绿勾，但读者仍看得到「这一组其实没跑通」）。

⚠ **DV 的两条「双跑调用处」门项被**重生成**：调用处从 `"$SRC_ABS"` 改成 `"$_arg"`
（**两遍喂同一个解析出来的参数** ⇒ 两遍输入必然相同 ⇒ 不会自己制造分叉）
⇒ ⇒ 原先盯「绝对路径」的那两条改成盯「**两遍喂的是同一个变量**」
⇒ ⇒ 而「绝对路径」这件事改由另外三条盯：`SRC_ABS` 归一化那行 + `bin` 分支的可执行检查
⇒ ⇒ **一个机制换一个门来盯** ⇒ **不许出现「没人盯的缝」**。

**④ 落门 / 判据**

⚠ **批 DW 段新增 15 条**（**单独成块** ⇒ 本段的承诺**出现在 CI 输出里**）：
① **逐条钉住 4 条**（路径 + `DUAL` + 位置 + **参数** ⇒ 位置或参数被改 ⇒ 一并红）；
② 参数列取值判定行；③ 登记册**段数恰好 5** 的判定行（理由里混进 TAB ⇒ 判红）；
④ `bin` 分支判定行；⑤ 二进制**可执行**判定行；⑥ `ci.sh` 的 `export BIN`；
⑦ **子判据的退出码上报**（2 条：上报那行 + 「没跑通」文案那行）；
⑧⑧⑨⑩ **4 条补的门项**（`BIN="${BIN:-}"` / `_arg="$BIN"` / `_arg="$SRC_ABS"` /
`_rc_note="判据**真的跑通**"`）⇒ ⚠ 这 4 条是**逐行变异反查**出来的，不是「想到了才加」。

⚠ **原地替换 6 处**（批 BM 纪律：原地替换不增行）：
① 登记册 `DUAL` 计数 **3 → 7**；② `EXEMPT` 计数 **8 → 4**；
③④⑤ 逐条钉住的 3 条**重生成**（加 `DUAL` 与参数列）；
⑥ **DV 的两条「双跑调用处」门项重生成**（`$SRC_ABS` → `$_arg`）。

⚠⚠⚨ **门项条数记三遍（批 CR 纪律）**：基线文件 / 审计器常量 `GATE_LINES_EXPECTED`
/ `ci-wiring.sh` 里那条门项的数字 ⇒ **1360 → 1375 三处同改**。

⚠ **批 CP 的两条配对门**（它们数**段级 trailer**）：**70 → 71** / **71 → 72**
⇒ ⚠⚠⚨ **新增一个段 ⇒ 这两个数字必须同步** ⇒ 否则接线门红
（实测：改完当场红 ⇒ 审计器 rc=4 + 接线门 rc=1 ⇒ 两条配对门一起报「期望 ≠ 实际」）。

**⑤ 本批踩到的坑（全部实测）**

⚠⚠⚨ **① 改门项行时只写了正则部分 ⇒ 丢了 `arch_need_count ...` 前缀**
⇒ ⇒ 那两行**不再是门项**（还变成了**会被执行的野命令行**）⇒ 门项条数少 2
⇒ ⇒ 审计器当场报「有门项被删了 / 被改成注释了」（rc=6）⇒ 接线门跟着红
⇒ ⇒ **纪律**：改门项行必须**整行写全**（含 `arch_need_count <文件> <正则> <计数> ` 前缀）。

⚠⚠⚨ **② 用 `re.sub(pattern, repl, whole_file, count=1)` 改整篇 ⇒ 改到的可能是第一条匹配**
⇒ ⇒ 把**无关门项**的说明改坏了（`恰好 1 处` 被改成 `恰好 71 处`）
⇒ ⇒ **纪律**：改门项行必须**按行定位**（唯一锚点 + 命中数 == 1）
⇒ 且改完要**逐条比对**（改前改后的门项集合做差集 ⇒ 差集必须**逐条可解释**）。

⚠⚠⚨ **③ 正则里的 `**` 转义层数**：要匹配**两个字面星号** ⇒ 正则文本必须是 `\*\*`
⇒ ⚠ 写成 `\\**` ⇒ Python re 直接报 "multiple repeat" ⇒ 门**恒红**（审计器 rc=4 当场报）
⇒ ⇒ **纪律**：正则里的 `*` 一律 `\*`；写完立刻 `re.compile()` 自证。

⚠⚠⚨ **④ 负控反过来找出 4 条缺的门项**：逐行过 parity 脚本里**会影响行为**的行
⇒ ⇒ 找出 `BIN="${BIN:-}"` / `_arg="$BIN"` / `_arg="$SRC_ABS"` / `_rc_note="判据**真的跑通**"`
这 4 行**没有任何门项钉** ⇒ ⇒ 改掉它们 ⇒ 探针就拿到错的参数 ⇒ **空洞的一致** ⇒ 假绿
⇒ ⇒ **门项不是「想到了才加」，是「变异一个就加一条」**。

⚠ **⑤ 「门变红」≠「行为被抓住」**：NC10 / NC12 / NC13 三个用例**实测**（首轮跑出来的
⇒ 与推演不一样 ⇒ 据此**订正期望**，不迁就实现）：
⇒ · **NC10 / NC12**（喂错参数：`_arg` 改成源码根 / 登记册参数列 `bin` 改成 `src`）
⇒ ⇒ **接线门红** ✓（形态门项抓住了）⇒ ⇒ **parity 门也红了** ⇒ 但文案是「**输出不同**」
⇒ ⇒ ⚠⚠⚨ **误诊**（真根因是「**参数喂错**」，不是「随执行 shell 变」）
⇒ ⇒ ⇒ ⚠ 但**门确实红了** ⇒ **结论没被悄悄放过** ⇒ 记为**已知边界**（见 ⑧）。
⇒ · **NC13**（摘掉 `bin` 的前置检查 + ⚠ 环境里**故意不给 `BIN`**）
⇒ ⇒ **接线门红** ✓（形态门项抓住了）⇒ ⇒ **parity 门仍然绿** ⇒ **空洞的一致**坐实
⇒ ⇒ ⇒ ⚠⚠⚨ 而且这次的「空洞」**看得见**：parity 门自己的输出写着
⇒ 「✓ …：两版一致（退出码 2 ⇒ 这一组**没跑通**；结论本身由该脚本自己的门负责）」
⇒ ⇒ ⇒ **这正是本批「退出码必须被报出来」的用处**：没有它 ⇒ 这种空洞与真通过**长得一模一样**
⇒ ⇒ ⇒ 负控必须**同时**断言「门红」**和**「行为符合预期」。

⚠⚠⚨ **负控的附加断言怎么写的（纪律）**：原先 NC10 / NC12 / NC13 的附加断言都是
「parity 门**仍然绿** ⇒ 子脚本日志里没有绿结论」⇒ ⚠ **实测不成立**（parity 门红了）
⇒ ⇒ 改成读**门自己的输出**（不读日志文件）⇒ ⚠ **日志文件是每个条目覆盖写的**
⇒ 读到哪一条取决于登记册顺序 ⇒ 拿它当断言**脆** ⇒ 只当参考信息打印。

**⑥ 负控 13 真红**

⚠ **13 例**（harness 沿用批 DP / DR / DS / DT / DU / DV 的纪律）：
scratch 树复制**整个仓根**（`symlinks=True`、放 **home 分区** ⇒ 不占 tmpfs）、
备份**在变异之前**取且**备份路径与内容分开存**、**每个用例一棵新树**、
**变异前先跑一遍确认是绿的**、变异后**自己先自证语法**（`sh -n`）、
退出码**不经管道读**、**启动前自检**（含磁盘剩余空间）、**atexit 兜底还原**、
洁净度判据 = **与原始字节逐字节相同**。

⚠ **用例**：
① **NC1**：登记册里删掉一个 `DUAL` 条目 ⇒ 接线门红；
② **NC2**：删掉一个 `EXEMPT` 条目 ⇒ 接线门红；
③ **NC3**：某条 `EXEMPT` 的**理由被清空**（⚠ 理由现在是**第 5 段**）⇒ 双跑门红（fail closed）；
④ **NC4**：**退出码比对**被摘 ⇒ 接线门红；
⑤ **NC5**：**输出比对**被摘 ⇒ 接线门红；
⑥ **NC6**：**退出码**没被接住 ⇒ 接线门红；
⑦ **NC7**：CI 里对这道门的**调用被删** ⇒ **双断言**（接线门红 **且** 孤儿探针红）；
⑧ **NC8**：**登记册路径常量**改错 ⇒ 接线门红；
⑨ **NC9 · 核心对照**：在被双跑的脚本里造一次**真实的** sh/bash 分叉 ⇒ 双跑门红；
⑩ **NC10 · 批 DW 新**：`bin` 那几条**喂的不是二进制**（改成源码根）⇒ 探针 exec 时才炸
⇒ ⇒ **双断言**（接线门红 **且** parity 门**也红了** ⇒ 文案「输出不同」⇒ ⚠ 误诊，但门没放过它）；
⑪ **NC11 · 批 DW 新**：二进制路径**不从环境拿**了（改成自己算）⇒ ⚠ 实测：自己算出来的是**目录**
⇒ ⇒ 而 `-x` 对**目录**也返回 true ⇒ 只查 `-x` **拦不住** ⇒ ⇒ 前置检查必须**同时**查 `-f`
⇒ ⇒ ⇒ 双跑门红（文案「不是一个可执行的二进制**文件**」）；
⑫ **NC12 · 批 DW 新**：登记册里某条探针的**参数列**被改（`bin` → `src`）
⇒ ⇒ **双断言**（接线门红 **且** parity 门**也红了** ⇒ 同 NC10 的误诊）；
⑬ **NC13 · 批 DW 新**：`bin` 的**前置检查被摘**（⚠ 环境里**故意不给 `BIN`**）
⇒ ⇒ **双断言**（接线门红 **且** parity 门**仍然绿** ⇒ 空洞的一致坐实）
⇒ ⇒ ⇒ ⚠ 附加断言读**门自己的输出**：它写着「这一组**没跑通**」⇒ 空洞**看得见**。

**⑦ 数字**

⚠ **门项条数 1360 → 1375**（批 DW 段 **15 条**，**三处同改**）；
⚠ **门项执行次数 1363 → 1378**（+15）；
⚠ **恒真探针条件 1014 → 1020**（⚠ parity 脚本 +5 个条件（段数 / 参数列 / `bin` 分支 /
二进制可执行 / 退出码上报）+ 批 DW 段 trailer +1 ⇒ 实测对上）；
⚠ 批 CP 两条配对门 **70 → 71** / **71 → 72**；
⚠ **登记册 11 数据行 = `DUAL` 7 + `EXEMPT` 4**（⚠ `DUAL` 7 条里 **6 条**由双跑覆盖面门双跑、
**1 条**由 CI 入口双跑 ⇒ 两个数字都对得上）；
⚠ **双跑覆盖面门 rc=0**（双跑 **6** 个 + 豁免 **4** 个；相对路径与绝对路径两种调用都试过）；
⚠ `ci.sh` 的 `exit [1-9]` 总数 **41**（不变）；恒真探针范围基线 `shell` **19**（不变）；
⚠ 孤儿探针断言脚本数 **19 / 33**（不变）；
⚠ `|| true` 盘点 **33 处**、未验证出口盘点 **21 组 / 73 处** ⇒ **均不变**；
⚠ **负控 13 真红**；累计 **1300/1300**；
⚠ **`ci.sh` 16/16 步跑完但 rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**。

**⑧ 已知边界（如实记着）**

⚠⚠⚨ **双跑门只判「两版结论是否一致」，不判「结论本身对不对」**
⇒ 子脚本**两遍都红**时它**仍报一致** ⇒ ⇒ 修法是**让两遍都跑真判据**
（绝对路径 + 喂对参数 + 前置挡住「用法错」），**不是**给双跑门加严
⇒ ⚠⚠⚨ **加严会假红**：「未验证」用专属退出码 **3**（批 CL）⇒ 那是**合法结论**，不是失败
⇒ ⇒ 本批的做法是**把退出码报出来**（读者能看到「这一组没跑通」），而不是**判红**；
⚠⚠⚨ **实测踩出来的「误诊」**：喂错参数（`_arg` 喂成源码根 / 登记册参数列被改成 `src`）
⇒ 探针 **exec 时才炸** ⇒ 而**两个 shell 的报错文案不同**（dash: `Permission denied` /
bash: `是一个目录`）⇒ ⇒ 双跑门报「**输出不同**」⇒ ⚠⚠⚨ **那是误诊**（真根因是
「**参数喂错**」，不是「随执行 shell 变」）⇒ ⇒ ⚠ 但**门确实红了** ⇒ **结论没被放过**
⇒ ⇒ **已知边界** ⇒ 下一批候选：把「**两遍都没跑通**」单独成一支（把「随 shell 变」
与「两遍都失败」分开说 ⇒ 诊断不失真）；
⚠⚠⚨ **「输出不同」那条文案现在带两遍的退出码**（`退出码 sh=… / bash=…`）
⇒ 读者一眼能看出「两遍是不是**都没跑通**」⇒ ⚠ 只说「输出不同」⇒ 「两遍都失败」这个事实
就被吞掉了 ⇒ **结论悄悄消失** ⇒ 本批把它补回来；
⚠⚠⚨ **4 个探针脚本自己的 `[ ! -x "$BIN" ]` 也有「目录能冒充二进制」这个洞**
⇒ 喂目录时它们**不会**走「用法错」⇒ 而是 exec 时才炸 ⇒ 本批只加固了**双跑覆盖面门自己**
那处 ⇒ 探针那 4 处**记为已知边界**（下一批候选）；
⚠ ⚠ **4 个探针的双跑会让 CI 多跑 4 遍二进制**（时间换覆盖面）⇒ ⚠ 若将来嫌慢，
可以只双跑**判据脚本**、把**探针**留在 `EXEMPT` + 写理由 ⇒ ⚠ 但**理由必须是真的**；
⚠ ⚠ **登记册从 4 段变 5 段** ⇒ 任何按 4 段读它的工具都要跟着改（本仓只有 `ci-shell-parity.sh` 读它）；
⚠ ⚠ **「理由写得对不对」机器判不了** ⇒ 只能判非空 ⇒ **危险方向靠人工**；
⚠ ⚠ **`contract-check.sh` 仍豁免**（随机沙箱名 + 时间戳文件名 ⇒ 恒红 ⇒ 假红）
⇒ ⇒ 若将来要双跑它，**必须先解决随机量**；
⚠ ⚠ **`build-deb.sh` 仍豁免**（有副作用）｜**`check-deb-layout.sh` 仍豁免**（需 deb 产物，第 11 步才构建）
⇒ ⇒ 要双跑得把双跑点挪到第 12 步之后 ⇒ **下一批候选**；
⚠ ⚠ **`ci-shell-parity.sh` 自己仍不被双跑**（自引用 ⇒ 递归）
⇒ 它的正确性由**门项逐字钉住 + 负控**保证；
⚠ ⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。


### E.2cg 二进制路径的判定不许只查 `-x`；双跑门的红不许误诊（批 DX）

**① 起因（实测，不是推演）**

批 DW 收口时如实留了两个**已知边界**（台账 E.2cf ⑧）：

· ⚠⚠⚨ **4 个探针脚本自己的 `[ ! -x "$BIN" ]` 也有「目录能冒充二进制」这个洞**
⇒ 喂目录时它们**不会**走「用法错」⇒ 而是 **exec 时才炸**；
· ⚠⚠⚨ **喂错参数 ⇒ 双跑门报「输出不同」是误诊**（真根因是「**参数喂错**」，
不是「随执行 shell 变」）⇒ ⇒ 下一批候选：把「**两遍都没跑通**」单独成一支。

⇒ ⇒ **本批就是那个下一批**。

**② 决定性实测（批 DX 的第一步，两条都真跑出来）**

⚠ **实测 ①：探针拿到目录 ⇒ 两遍逐字节相同**

| 场景 | sh | bash | 逐字节相同？ |
|---|---|---|---|
| 探针**加固后**（`-f` 已查）拿到**目录** | `✗ 用法：… <deepDolphin 二进制>`（rc=2） | 同左 | **✓ 相同** |
| 探针**摘掉 `-f`** + 拿到**目录** | `…: Permission denied` | `…: 是一个目录` | ✗ **不同** |

⇒ ⇒ 加固后：喂错参数 ⇒ 两遍**同样**的 `exit 2` ⇒ 「两版一致」是**空洞的一致**
⇒ ⇒ 而批 DW 的「**子判据退出码必须被报出来**」正好让这个空洞**看得见**
（门自己的输出写着「这一组**没跑通**」）。

⚠ **实测 ②：两个 shell 的报错文案确实不同**

dash 说 `Permission denied`、bash 说 `是一个目录` ⇒ ⇒ 双跑门会判「输出不同」⇒ 红
⇒ ⇒ 但**归因错了**（真因是「参数喂错 / 二进制不是文件」）。

**③ 修法（两处，方向相反 ⇒ 互补）**

⚠⚠⚨ **① 4 个探针的二进制检查**必须**同时查 `-f`**：

`ci-platform-probe.sh` / `ci-docs-lang-probe.sh` / `ci-divider-probe.sh` /
`probe-agent-tool-surface.sh` ⇒ `[ -z "$BIN" ] || [ ! -x "$BIN" ]`
⇒ ⇒ 改成 `[ -z "$BIN" ] || [ ! -f "$BIN" ] || [ ! -x "$BIN" ]`
⇒ ⇒ 目录在**喂之前**就被挡住（fail closed）⇒ 两遍**同样**的 `exit 2`
⇒ ⇒ 「喂错参数」不再变成 shell 相关的误诊。

⚠⚠⚨ **② 双跑门「输出不同」拆两支**（诊断不许指错方向，批 CE 纪律）：

· 两遍**退出码相等且非 0** ⇒ 文案说「**输出不同，但两遍都没跑通**（退出码 sh=… / bash=…）
⇒ ⚠ 这**不是**「随执行 shell 变」⇒ 先查「喂的参数对不对」「环境坏没坏」」；
· 两遍**都跑通（退出码 0）** ⇒ 才是真的「**诊断文案随执行 shell 变**」。

⇒ ⇒ 到「输出不同」那一步时两遍的退出码**已经相等**（不等的那一支在上面就 `exit` 了）
⇒ ⇒ 所以只判退出码即可，**不需要**再比一次。

**④ 落门 / 判据**

⚠ **批 DX 段新增 7 条**（**单独成块** ⇒ 本段的承诺**出现在 CI 输出里**）：

① **逐条钉住 4 个探针的 `-f` 检查行**（路径 + 整行锚定 ⇒ 少一个 `-f` ⇒ 红）；
② 双跑门「两遍都没跑通」的**判定行**（整行锚定）；
③ 那条「**两遍都没跑通**」文案；
④ 那条「**诊断文案随执行 shell 变**」文案（⚠ 钉住 ⇒ 删掉 `else` 那支 ⇒ 红）。

⚠ **原地替换 3 处**（批 BM 纪律：原地替换不增行）：
① 批 CP 两条配对门（它们数**段级 trailer**）**71 → 72** / **72 → 73**；
② 常量门项里的数字 **1375 → 1382**；
③ 常量门项的**说明链**追加本批这一跳（⇒ 逐跳可追溯）。

⚠⚠⚨ **门项条数记三遍（批 CR 纪律）**：基线文件 / 审计器常量 `GATE_LINES_EXPECTED`
/ `ci-wiring.sh` 里那条门项的数字 ⇒ **1375 → 1382 三处同改**。

**⑤ 本批踩到的坑**

⚠⚠⚨ **① 负控的期望会因实现变化而翻转**（DW → DX 的实测）：

批 DW 的 NC10 / NC12 期望写的是「parity 门**也红了**」（实测：探针 exec 时才炸 ⇒
两个 shell 文案不同 ⇒ 红）⇒ ⇒ 本批把 4 个探针的 `-f` 补上 ⇒ **同样的变异**
⇒ 探针改走「用法错」（`exit 2`）⇒ ⇒ 两遍**逐字节相同** ⇒ ⇒ **parity 门变回绿**
⇒ ⇒ ⚠⚠⚨ **不迁就实现、也不迁就旧期望** ⇒ 按**本批的实测**重写期望
（⇒ 变回「**空洞的一致**」那一档）。

⚠⚠⚨ **② 「门变红」≠「行为被抓住」有三档**（本批实测齐了）：

| 档 | 变异 | 接线门 | parity 门 | 结论 |
|---|---|---|---|---|
| `hollow` | 喂错参数 | **红** | **绿**（且写着「这一组没跑通」） | 空洞的一致 ⇒ 只有形态门项能抓住 |
| `parity-green` | 摘掉探针的 `-f`（正常输入） | **红** | **绿**（且**没有**「没跑通」） | **行为完全没变** ⇒ 只有形态门项能抓住 |
| `parity-notrun-diff` | 摘掉探针的 `-f` **且** 喂源码根 | **红** | **红**（文案说「两遍都没跑通」） | **诊断不失真**那支被坐实 |

⚠⚠⚨ **③ 「两遍都没跑通」这一支的可达性**（实测坐实）：只有「**探针的 `-f` 没了**
**且** 喂了错的东西」才会走到 ⇒ ⇒ **必须两个变异一起做**才测得到
⇒ ⇒ 负控里单独做一个变异**测不着** ⇒ ⇒ 这就是为什么要有 `parity-notrun-diff` 那一档。

**⑥ 负控 16 真红**

⚠ **16 例**（harness 沿用批 DP / DR / DS / DT / DU / DV / DW 的纪律）：
scratch 树复制**整个仓根**（`symlinks=True`、放 **home 分区** ⇒ 不占 tmpfs）、
备份**在变异之前**取且**备份路径与内容分开存**、**每个用例一棵新树**、
**变异前先跑一遍确认是绿的**、变异后**自己先自证语法**（`sh -n`）、
退出码**不经管道读**、**启动前自检**（含磁盘剩余空间）、**atexit 兜底还原**、
洁净度判据 = **与原始字节逐字节相同**。

⚠ **新增 3 例**：
⑭ **NC14**：平台探针的 **`-f` 被摘**（只留 `-x`）⇒ 接线门红 **且** parity 门**仍然绿**
⇒ **行为完全没变** ⇒ **只有形态门项能抓住**；
⑮ **NC15**：双跑门「**两遍都没跑通**」的判定行被摘 ⇒ 接线门红 **且** parity 门**仍然绿**
⇒ 同上；
⑯ **NC16 · 行为级**：**两个变异一起做**（探针的 `-f` 被摘 **且** 双跑门喂源码根）
⇒ ⇒ 接线门红 **且** parity 门红 **且** 文案命中「**但两遍都没跑通**」
⇒ ⇒ **不许**说「随执行 shell 变」（真因是「喂错了参数」）⇒ **诊断不失真**坐实。

⚠ **NC10 / NC12 的期望按本批实测翻转**（见 ⑤①）⇒ 两例的附加断言改回 `hollow` 档。

**⑦ 数字**

⚠ **门项条数 1375 → 1382**（批 DX 段 **7 条**，**三处同改**）；
⚠ **门项执行次数 1378 → 1385**（+7）；
⚠ **恒真探针条件 1020 → 1022**（⚠ parity 脚本 **+1** 个条件（新判定行）
+ 批 DX 段 trailer **+1** ⇒ 实测对上）；
⚠ 批 CP 两条配对门 **71 → 72** / **72 → 73**；
⚠ **登记册 11 数据行 = `DUAL` 7 + `EXEMPT` 4**（**不变**）；
⚠ **双跑覆盖面门 rc=0**（双跑 **6** 个 + 豁免 **4** 个；相对路径与绝对路径两种调用都试过）；
⚠ `ci.sh` 的 `exit [1-9]` 总数 **41**（不变）；恒真探针范围基线 `shell` **19**（不变）；
⚠ 孤儿探针断言脚本数 **19 / 33**（不变）；
⚠ `|| true` 盘点 **33 处**、未验证出口盘点 **21 组 / 73 处** ⇒ **均不变**；
⚠ **负控 16 真红**；累计 **1316/1316**；
⚠ **`ci.sh` 16/16 步跑完但 rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**。

**⑧ 已知边界（如实记着）**

⚠⚠⚨ **「两遍都没跑通」这一支只在「两遍退出码相等」时判定** ⇒ 若两遍退出码**不同**
⇒ 走的是上面那条「**退出码不同**」⇒ ⚠⚠⚨ **那条仍然只说「结论随 shell 变」**
⇒ ⇒ 「输入不同 ⇒ 退出码不同」的误诊（批 DV 实测过）**本批没拆成两支**
⇒ ⇒ ⚠⚠⚨ **但要如实说清楚：它现在不是一个可单独触发的洞** —— 两遍喂的是**同一个变量**
（`$_arg`）⇒ 且**两个调用处都被形态门项钉住** ⇒ ⇒ 「输入不同」那种情况**必须同时违反形态门项**
才可能发生 ⇒ ⇒ 后果是「**红**」仍然**对**（门照样拦住）⇒ 只是**文案**不够精确
⇒ ⇒ ⇒ **下一批候选**：把「退出码不同」那支也按「两遍输入是不是同一个」拆开；
⚠⚠⚨ **诊断不失真只做到了「输出不同」这一支** ⇒ 「退出码不同」那一支还没拆；
⚠ ⚠ 双跑门**只判「两版结论是否一致」，不判「结论本身对不对」** ⇒ 子脚本两遍都红时它
**仍报一致** ⇒ ⇒ 修法是**让两遍都跑真判据**，**不是**给双跑门加严
⇒ ⚠⚠⚨ **加严会假红**：「未验证」用专属退出码 **3**（批 CL）⇒ 那是**合法结论**，不是失败
⇒ ⇒ 本批的做法是**把退出码报出来**（读者能看到「这一组没跑通」），而不是**判红**；
⚠ ⚠ 4 个探针的双跑会让 CI 多跑 4 遍二进制（时间换覆盖面）；
⚠ ⚠ 登记册「理由写得对不对」机器判不了（只能判非空）⇒ **危险方向靠人工**；
⚠ ⚠ `contract-check.sh`（随机量）/ `build-deb.sh`（有副作用）/ `check-deb-layout.sh`
（需 deb 产物）**仍豁免**；`ci-shell-parity.sh` 自己**仍不被双跑**（自引用）；
⚠ ⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入（改动只在 `scripts/` 与 `docs/`）。


### E.2ch 双跑覆盖面扩到契约门（批 DY）

**① 起因（实测，不是推演）**

批 DX 收口时如实留了三个**已知边界**（台账 E.2cg ⑧）：

· ⚠⚠⚨ **`contract-check.sh` 仍豁免**（随机沙箱名 + 时间戳文件名 ⇒ 恒红 ⇒ 假红）
⇒ 要双跑它，**必须先解决随机量**；
· ⚠⚠⚨ **`build-deb.sh` 仍豁免**（有副作用 ⇒ 双跑 = 构建两遍）；
· ⚠⚠⚨ **`check-deb-layout.sh` 仍豁免**（需 deb 产物，第 11 步才构建
⇒ 双跑点得挪到第 12 步之后 ⇒ 要动 CI 的步骤顺序 ⇒ 风险高）。

⇒ ⇒ **本批做第一条**（另两条动不了：② 有副作用；③ 要动步骤顺序 ⇒ 下一批候选）。

**② 决定性实测（批 DY 的第一步）**

⚠⚠⚨ **登记册写的理由太粗 ⇒ 必须实测到底有多少随机量**：
登记册写的是「随机沙箱名 + **时间戳文件名**」⇒ 听起来**到处**都是 ⇒ 结论会是「清不掉」。

⇒ ⇒ **实测**：跑两遍 `contract-check.sh` ⇒ `diff` ⇒ **只有 2 行**不同：

```
› 沙箱：/tmp/dd-contract.Zq9asY（DEEPGIT_HOME 隔离，退出即清）
✓ 进度报告端到端：客户端抽出的路径存在且是绝对路径（…/home/reports/report-2026-10-23-1792717021297.md）
```

⇒ ⇒ ⚠ **没有 git SHA 之类**：fixture 的 commit SHA **没进输出**（实测：输出里 8 位以上的
十六进制只有一个 —— 就是那个毫秒时间戳）⇒ ⇒ **成功态的随机量就这 2 处** ⇒ ⇒ **可以清掉**。

⚠⚠⚨ **失败态还有第 3 处**（第一轮负控实测才发现）：契约门**失败**时那行
「引擎获取：落盘的引擎不存在或不可执行（`$ENG_TMP/dest/moongit`）」⇒ `mktemp -d` 的随机名
⇒ ⇒ 喂错参数时两遍输出**不同** ⇒ ⇒ **失败态也不确定** ⇒ ⇒ 一样清掉。

⚠ **清掉后必须再测一遍**（两种状态各测一遍）：
**成功态**（喂真二进制）与**失败态**（喂目录）都**两遍逐字节相同** ⇒ 才算真清掉
（不能只靠「我改了 2 行」推断）。

**③ 修法（三处，方向一致）**

⚠⚠⚨ **① 契约门的输出不许含随机量**（在**产出侧**清，不在比较侧做归一化）：

· 沙箱那行 ⇒ 只说「已隔离」（⚠ 沙箱**退出即清** ⇒ 打印它的路径**事后根本没用**）；
· 报告路径那行（**成功态 + 失败态共 2 行**）⇒ 不打印路径
（⚠ 断言本身「存在且是绝对路径」**一个字没改** ⇒ 只少了那个事后无用的路径）；
· **失败态**那行「引擎获取：落盘的引擎不存在或不可执行（`$ENG_TMP/...`）」⇒ 也不打印路径
（⚠ 第一轮负控实测才发现的 ⇒ 不清它 ⇒ **失败态**仍然两遍不同）。

⇒ ⇒ ⚠⚠⚨ **为什么不在双跑门比较时做归一化**（批 DV 明确不做）：
比较侧归一化会把**真实差异**也一起吃掉 ⇒ **假绿风险更大** ⇒
⇒ 产出侧不打随机量 ⇒ ⇒ **真实差异照样被双跑门抓到** ✓。

⚠⚠⚨ **② 契约门吃位置参数**（客户端二进制）：

`CLIENT_BIN="${DEEPGIT_CLIENT_BIN:-}"` ⇒ `CLIENT_BIN="${1:-${DEEPGIT_CLIENT_BIN:-}}"`
（**位置参数优先于**环境变量）⇒ ⇒ 双跑门喂的 `$BIN` 与 `ci.sh` 第 10 步喂的是**同一个**
⇒ ⇒ 二进制路径**单一真相源**（批 DW 立过的：两个地方各算一遍 ⇒ 算出不同路径 ⇒ 又一个新洞）
⇒ ⇒ ⚠ 不吃位置参数的话，它会走**自己的 fallback**（自己算一遍）⇒ ⇒ **单一真相源破**。

⚠ **③ 登记册**：`contract-check.sh` **EXEMPT → DUAL**（位置 = `parity`，参数 = `bin`）
⇒ ⇒ 登记册 **11 数据行 = DUAL 8 + EXEMPT 3**（三个数字互相咬合 ⇒ 改一边必红）。

**④ 落门 / 判据**

⚠ **批 DY 段新增 5 条**（**单独成块** ⇒ 本段的承诺**出现在 CI 输出里**）：

① **`forbid`**：契约门的打印行**不许含 `$SANDBOX`**（随机量不许进输出）；
② **`forbid`**：契约门的打印行**不许含 `$REPORT_PATH`**（同上；⚠ 口径：只看**双引号**形式
—— 单引号里没有变量展开 ⇒ 本来就没有随机量）；
②′ **`forbid`**：契约门的打印行**不许含 `$ENG_TMP`**（**失败态**那处 ⇒ 第一轮负控才发现）；
③ **`need_count`**：契约门必须**吃位置参数**（整行锚定）；
④ **`need_count`**：登记册里契约门那一条必须**恰好一条**且状态/位置/**参数**都对（逐条钉住）。

⚠ **原地替换 5 处**（批 BM 纪律：原地替换不增行）：
① 登记册 `DUAL` 计数 **7 → 8**（+ 两个「互相咬合」的说明里的数字同步）；
② 登记册 `EXEMPT` 计数 **4 → 3**（同上）；
③ 批 CP 两条配对门（它们数**段级 trailer**）**72 → 73** / **73 → 74**；
④ 常量门项里的数字 **1382 → 1387**；
⑤ 常量门项的**说明链**追加本批这一跳。

⚠⚠⚨ **门项条数记三遍（批 CR 纪律）**：基线文件 / 审计器常量 `GATE_LINES_EXPECTED`
/ `ci-wiring.sh` 里那条门项的数字 ⇒ **1382 → 1387 三处同改**。

**⑤ 本批踩到的坑（三条，都是真跑出来的）**

⚠⚠⚨ **① 「门项条数」的口径连 forbid 门也算一条** ⇒ ⇒ 批 DY 段是 **4 条**（**不是** 6 条
—— 「6 条」是我把**原地替换**也算进去了 ⇒ 自证时审计器直接报
⇒ ⇒ **当场坐实** ⇒ ⇒ 后补了第 5 条 forbid（失败态那处）⇒ ⇒ **1382 → 1387**。

⚠⚠⚨ **② 正则的转义层数**：门项文本是从 Python 源里**抽取**后原样写盘的
⇒ `\$` 原样落盘 ⇒ 正则**多了一层** ⇒ ⇒ 审计器报「期望 1 ≠ 实际命中 0」
⇒ ⇒ **写完立刻在目标文件里实数一遍**（`re.findall` ⇒ 必须命中 1 次）。

⚠⚠⚨ **③ 手打的中文标点会与文件里的码位不一致** ⇒ 锚点**命中 0 处** ⇒

⚠⚠⚨ **④ forbid 门项的正则转义层数 ⇒ **恒绿 = 没牙**（第一轮负控实测坐实）**：
两条 forbid 的正则被写成 `\$SANDBOX`（**两层**）⇒ ERE 里 `\` = 字面反斜杠
⇒ ⇒ **永远匹配不到** ⇒ ⇒ forbid 门**恒绿** ⇒ ⇒ **承诺没牙**（负控 NC17 直接抓到：
把随机量放回输出 ⇒ **接线门居然没红**）⇒ ⇒ **纪律**：新增 forbid 门项后必须做
**「正负有据」自证** —— 在**干净**文件里命中 **0** 次（否则恒红）、把**违例**塞进去时
命中 **>0** 次（否则没牙）⇒ ⇒ 与 need_count 门项的「在目标文件里实数一遍」**互补**。
连查两次才发现（第一次我以为是自己漏了「探针」二字 ⇒ 实为多打了）
⇒ ⇒ 修法：改用**行级 + Unicode 转义正则**编辑（**不靠手打整句匹配**）
⇒ ⇒ `⚠` = `\u26a0`、`恰` = `\u6070` … ⇒ ⇒ 再也不受手打差异影响。

**⑥ 负控 19 真红**

⚠ **19 例**（harness 沿用批 DP / DR / DS / DT / DU / DV / DW / DX 的纪律：
scratch 树复制**整个仓根**（`symlinks=True`、放 **home 分区**）、
备份**在变异之前**取、**每个用例一棵新树**、**变异前先确认是绿的**、
变异后**自证语法**、退出码**不经管道读**、**启动前自检磁盘**、**atexit 兜底还原**、
洁净度判据 = **与原始字节逐字节相同**）。

⚠ **新增 3 例**：

⑰ **NC17 · 行为级**：契约门的**随机量放回输出**（打印报告全路径）
⇒ ⇒ 接线门红（forbid 门）**且** parity 门**红**（「输出不同」）
⇒ ⇒ **随机量进输出 = 恒红 = 假红**这条被坐实；
⑱ **NC18**：契约门**不吃位置参数**（改回只吃环境变量）
⇒ ⇒ 接线门红 **且** parity 门**仍然绿**、输出里**没有**「没跑通」
⇒ ⇒ **正常输入下行为完全没变** ⇒ ⇒ **只有形态门项能抓住**；
⑲ **NC19**：登记册里契约门的**双跑位置**被改成 `ci.sh`
⇒ ⇒ 它就**不再被双跑门跑**（改由 CI 入口双跑，而入口并不双跑它）
⇒ ⇒ 接线门红 **且** parity 门**仍然绿** ⇒ ⇒ **逐条钉住**才能抓住。

**⑦ 数字**

⚠ **门项条数 1382 → 1387**（批 DY 段 **5 条**，**三处同改**）；
⚠ **门项执行次数 1385 → 1390**（+5）；
⚠ **恒真探针条件 1022 → 1023**（⚠ 批 DY 段 trailer +1 ⇒ 实测对上；
⚠ 契约门那处只**删变量引用**、不新增条件 ⇒ 不影响计数）；
⚠ 批 CP 两条配对门 **72 → 73** / **73 → 74**；
⚠ **登记册 11 数据行 = `DUAL` 8 + `EXEMPT` 3**（⚠ `DUAL` 8 条里 **7 条**由双跑覆盖面门双跑、
**1 条**由 CI 入口双跑 ⇒ 两个数字都对得上）；
⚠ **双跑覆盖面门 rc=0**（双跑 **7** 个 + 豁免 **3** 个；相对路径与绝对路径两种调用都试过）；
⚠ `ci.sh` 的 `exit [1-9]` 总数 **41**（不变）；恒真探针范围基线 `shell` **19**（不变）；
⚠ 孤儿探针断言脚本数 **19 / 33**（不变）；
⚠ `|| true` 盘点 **33 处**、未验证出口盘点 **21 组 / 73 处** ⇒ **均不变**；
⚠ **负控 19 真红**；累计 **1335/1335**；
⚠ **`ci.sh` 16/16 步跑完但 rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**。

**⑧ 已知边界（如实记着）**

⚠⚠⚨ **`build-deb.sh` 仍豁免**（**有副作用** ⇒ 双跑 = 构建两遍 ⇒ CI 时间翻倍且产物可能含时间戳）；
⚠⚠⚨ **`check-deb-layout.sh` 仍豁免**（需 deb 产物 ⇒ 双跑点得挪到第 12 步之后
⇒ 要动 CI 的 16 个步骤标记 + 一条 `arch_need_ml` 门 ⇒ **下一批候选**）；
⚠⚠⚨ **契约门双跑 ⇒ CI 每次多跑 2 遍契约门**（实测各 **11 秒** ⇒ **+22 秒**）；
⚠⚠⚨ **契约门的失败态原有一处随机路径**（`ENG_TMP`，只在「引擎获取失败」时出现）
⇒ ⇒ 第一轮负控实测发现 ⇒ ⇒ 本批**一并清掉** ⇒ ⇒ 实测：**成功态与失败态都两遍逐字节相同**
⇒ ⇒ ⇒ 覆盖面**成立**（⚠ 这一条原本被我写成「已知边界」，实测能清 ⇒ **当场清掉**而不是记着）；
⚠⚠⚨ **契约门的输出不再含沙箱路径与报告路径** ⇒ ⇒ 人读日志时**看不到**这两个路径
⇒ ⚠ 但它们**退出即清** ⇒ 事后本就无用 ⇒ ⇒ **代价 ≈ 0**；
⚠ ⚠ 双跑门**只判「两版结论是否一致」，不判「结论本身对不对」** ⇒ 子脚本两遍都红时它
**仍报一致** ⇒ ⇒ 修法是**让两遍都跑真判据**，**不是**给双跑门加严
⇒ ⚠⚠⚨ **加严会假红**：「未验证」用专属退出码 **3**（批 CL）⇒ 那是**合法结论**，不是失败；
⚠ ⚠ 登记册「理由写得对不对」机器判不了（只能判非空）⇒ **危险方向靠人工**；
⚠ ⚠ **本批不改任何产品代码** ⇒ 判据层零业务数据写入（改动只在 `scripts/` 与 `docs/`）。


### E.2ci 双跑覆盖面扩到 deb 布局验收门（批 DZ）

**① 起因（实测，不是推演）**

批 DY 收口时如实留了四个**已知边界**（台账 E.2ch ⑧），本批做其中的第三条：

· ⚠⚠⚨ **`check-deb-layout.sh` 仍豁免**（需 deb 产物，第 11 步才构建
⇒ 双跑点得挪到第 12 步之后 ⇒ 要动 CI 的步骤顺序 ⇒ 风险高）。

⇒ ⇒ **本批就是那个下一批**（另两条动不了：`build-deb.sh` 有副作用；
`ci-shell-parity.sh` 自引用）。

⚠⚠⚨ **但「要动步骤顺序 ⇒ 风险高」这句话本身要先实测掉**：
**双跑点挪到第 12 步之后** ≠ **改 CI 的步骤顺序** ⇒ 只要**在第 12 步内部**双跑
（deb 产物在第 11 步已就位 ⇒ 第 12 步里就现成）⇒ ⇒ **16 个步骤标记一根都不用动**
⇒ ⇒ 那条 `arch_need_ml` 门也不用动 ⇒ ⇒ **风险其实没那么高**
⇒ ⇒ ⚠ 前几批台账里那句「风险较高」是**当时的估计** ⇒ 本批**如实订正**
（批 DL 纪律：台账里的「实测发现」必须真复现，不许把推演写成实测）。

**② 决定性实测（批 DZ 的第一步）**

⚠⚠⚨ **必须先量随机量**（批 DY 的教训：登记册写「随机沙箱名 + 时间戳文件名」听起来**到处**都是
⇒ 结论会是「清不掉」⇒ 必须实测到底有多少）：

· **正常包（验收通过）**⇒ 两遍输出**逐字节相同** ⇒ 因为**通过态根本不打印路径**；
· ⚠ **失败态才显形**：造一个「deb 合法但布局坏」的包（拆掉可执行 + D-Bus service）⇒
**两遍输出必然不同** ⇒ 差的就是 `mktemp -d` 的**随机根路径**：

```
✗ 可执行缺失或不可执行：/tmp/tmp.UYbfpmgwxl/root/usr/bin/deepDolphin
✗ D-Bus service 文件缺失（/tmp/tmp.v7hTtQXBZG/root/usr/share/dbus-1/services/cn.deepdolphin.app.service）
```

⇒ ⇒ **直接双跑 = 恒红 = 假红**（批 DL：假红比假绿更坏）⇒ ⇒ 必须**产出侧清随机量**（批 DY 纪律）。

**③ 修法（四处，方向一致）**

⚠⚠⚨ **① 产出侧清随机量**（`check-deb-layout.sh`，**不是**在比较侧归一化 ——
批 DV 明确不做：会把真实差异也吃掉 ⇒ 假绿风险更大）：

· 包内相对路径**单独记一份**（`DESKTOP_REL` / `SERVICE_REL` / `METAINFO_REL` / `BIN_REL`）
⇒ **打印一律用它** ⇒ 输出里**没有随机量**（⚠ 断言本身一个字没改 ⇒ 只少了那个随机路径）；
· **解包失败**那行：解包日志里**可能带随机临时目录名** ⇒ 先 `sed` 剥掉再打印；
· **图标清单**：`find` 的输出顺序**依赖文件系统** ⇒ 改成 `cd` 进包内目录 + `LC_ALL=C sort`
⇒ 顺序固定 ⇒ 两遍逐字节相同。

⚠⚠⚨ **② 双跑点挪到 CI 第 12 步内部**（`ci.sh`）：
`sh` 一遍（CI 真正用的就是 dash）+ `bash` 一遍 ⇒ **退出码必须一致** + **输出必须逐字节一致**；
⇒ **两份日志都落 `TMPDIR`**（批 DU 纪律：第二遍会多看到第一遍的产物 ⇒ 双跑**自己制造分叉** ⇒ 假红）。

⚠ **③ 登记册**：`check-deb-layout.sh` **EXEMPT → DUAL**（位置 = `ci.sh`、参数 = `deb`）
⇒ ⇒ 登记册 **11 数据行 = DUAL 9 + EXEMPT 2**（三个数字互相咬合 ⇒ 改一边必红）。

⚠⚠⚨ **④ 汇总行的三个数字要对账**（本批顺手补的洞，**不是**本批引入的）：
双跑脚本的汇总行以前只说「本脚本双跑了 7 个」⇒ 登记册里**由 CI 入口双跑的那两条**
（`ci-wiring.sh` / `check-deb-layout.sh`）**在输出里是隐形的** ⇒ 谁被漏掉**看不出来**
⇒ ⇒ 现在汇总行报三个数字：**登记册共 11 条 = 本脚本双跑 7 + CI 入口双跑 2 + 豁免 2**。

**④ 落门 / 判据**

⚠ **批 DZ 段新增 17 条**（**单独成块** ⇒ 本段的承诺**出现在 CI 输出里**）：

① **`forbid`**：deb 布局验收的**打印行不许含 `$TMP`**（随机临时目录名）；
② **`forbid`**：**打印行不许含 `$ROOT`**（随机包根路径）；
③ **`need_count`**：包内相对路径常量 `BIN_REL` 必须在（整行锚定）；
④ **`need_count`**：`SERVICE_REL` 必须在（同款，整行锚定）；
⑤ **`need_count`**：图标清单**必须排序**（整行锚定）；
⑥ **`need_count_in_step`**：第 12 步的**双跑第二遍（bash）**必须还在这一步里；
⑦ **`need_count`**：双跑的**第二遍退出码**必须被接住；
⑧ **`need_count`**：双跑的**退出码比对**必须在；
⑨ **`need_count`**：双跑的**输出比对**必须在；
⑩ **`need_count`**：第一份日志必须落 `TMPDIR`；
⑪ **`need_count`**：第二份日志也必须落 `TMPDIR`；
⑫ **`need_count`**：登记册里 deb 布局验收门必须**恰好一条**且状态/位置/**参数**都对；
⑬ **`need_count`**：双跑的**结论必须被报出来**（整行锚定 ⇒ 只做不说 ⇒ 结论悄悄消失）；
⑭ **`need_count`**：双跑脚本必须给「由 CI 入口双跑」的那几条计数；
⑮ **`need_count`**：汇总行必须把**三个数字**都报出来。

⚠ **原地替换 7 处**（批 BM 纪律：原地替换不增行）：
① 登记册 `DUAL` 计数 **8 → 9**（+ 两个「互相咬合」的说明里的数字同步）；
② 登记册 `EXEMPT` 计数 **3 → 2**（同上）；
③ 批 CP 两条配对门 **73 → 74** / **74 → 75**；
④ 常量门项里的数字 **1387 → 1404**；
⑤ 常量门项的**说明链**追加本批这一跳；
⑥ `ci.sh` 的 `exit [1-9]` 计数 **41 → 43**（批 DZ 段新增 2 处 `exit 1`）；
⑦ 第 12 步的 per-step 门 **1 → 2**（同一步里多了第二遍）。

⚠⚠⚨ **门项条数记三遍（批 CR 纪律）**：基线文件 / 审计器常量 `GATE_LINES_EXPECTED`
/ `ci-wiring.sh` 里那条门项的数字 ⇒ **1387 → 1404 三处同改**。

**⑤ 本批踩到的坑（三条，都是真跑出来的）**

⚠⚠⚨ **① 「挪到第 12 步之后」把人引到「改步骤顺序」上** ⇒ 而实测**不必改**：
只要**在第 12 步内部**双跑 ⇒ 16 个步骤标记**一根都不用动** ⇒ ⇒ 前几批的「风险较高」是
**估计**不是实测 ⇒ ⇒ 本批**当场订正**（不许把推演写成实测）。

⚠⚠⚨ **② 两条新 forbid 门项的正则漏了 `.log` 后缀** ⇒ 「期望 1 ≠ 实际命中 0」
⇒ ⇒ **审计器当场报出来** ⇒ ⇒ 写完**立刻在目标文件里实数一遍**（批 DY 的教训复用）
⇒ ⇒ 这条自证**有效**（不是事后才发现）。

⚠⚠⚨ **③ 配对门改了期望值、忘了改说明文字里的同一个数字** ⇒ ⇒ 审计器只校准**期望值**、
**不管说明文字** ⇒ ⇒ **文字会撒谎**（门项说「恰好 73 处」，实际已经是 74 处）
⇒ ⇒ 得**手工**订正 ⇒ ⇒ 纪律追加：**改条数时，说明文字里的同一个数字也要一起改**。

⚠⚠⚨ **④ 只禁 `$TMP` / `$ROOT` ⇒ 抓不住「改用绝对路径变量」这个手滑（**第一轮负控实测坐实**：把 `$BIN_REL` 改回 `$BIN` ⇒ 那两条 forbid **命中 0** ⇒ ⇒ **没牙** ⇒ ⇒ 补**第三条** forbid（打印行不许用 `$BIN` / `$SERVICE` / `$METAINFO` / `$DESKTOP` ⇒ 它们展开后**带随机根**）⇒ ⇒ 并**逐条做「正负有据」自证**（**干净文件命中 0**（否则恒红）+ **塞违例后命中 >0**（否则没牙）⇒ 实测 6 个变体全部**命中 1** ✓）⇒ ⇒ 纪律追加：**新增 forbid 门项，口径要按「变量展开后含不含随机量」来定，不能只按「变量名长什么样」**（批 DY 补纪律的延伸）；⚠⚠⚨ **⑤ forbid 门项的口径是「**双引号区段**」⇒ 打印行里**嵌套命令替换**（自带引号）⇒ 随机量落在区段**外** ⇒ **抓不到**（**NC24 实测坐实**：「解包失败」那行是 `echo "…$(head -3 "$TMP/extract.log")" >&2` ⇒ `$TMP` 在**内层**引号之间 ⇒ forbid 的 `[^"]*` 在外层引号处就被截断 ⇒ ⇒ **命中 0** ⇒ ⇒ 改回原样 ⇒ 接线门**没红** ⇒ ⇒ **修法**：**用 need 门项钉住那一行的形态**（整行锚定 ⇒ 改回原样 ⇒ 必红）⇒ ⇒ ⚠ 通用的洞（任何**嵌套命令替换**里插随机量）**仍在** ⇒ 如实记进「已知边界」；⚠⚠⚨ **⑥ 负控**必须独占**跑**（并发重 I/O ⇒ 审计器会返回 rc=2「盲区」）：本批有一次审计器返回 rc=2 ⇒ 排查后确认：当时负控 harness 正在并发复制 516 MB 的树 ⇒ ⇒ **单独连跑 20 次审计器 ⇒ 20/20 全绿** ⇒ ⇒ 判为**环境性抖动**⇒ ⇒ **不是逻辑抖动**⚠⚠⚨ **⚠ 归因已被批 EJ-11 订正（观测本身照旧，错的只是因果解释）**：「重 I/O 下**子进程起不来** ⇒ OSError ⇒ 落进 `except Exception` ⇒ 返回 **CRASH_RC=10**（崩了）」⇒ ⇒ ⇒ **绝不可能是 rc=2** ⇒ ⇒ ⇒ rc=2 只可能来自「工具**跑了**但退出码≠0」（`UnreadableSource`）⇒ ⇒ ⇒ 当时的 rc=2 **另有来源**（根因**仍未定位**，当前条件**不可复现**）⇒ ⇒ 批 EJ-11 已让「工具瞬时失败」**不再变成假红**（两侧各重试一次） ⇒ ⇒ 纪律追加：**跑负控时别干别的重活**（⚠ 这也给批 DU 那次「红绿分叉」提供了一种可能来源 ⇒ 但**仍未定位** ⇒ 继续记为待查）。

**⑥ 负控 24 真红**

⚠ **24 例**（19 例沿用批 DY 的纪律：scratch 树复制**整个仓根**（`symlinks=True`、放 **home 分区**）、
备份**在变异之前**取、**每个用例一棵新树**、**变异前先确认是绿的**、变异后**自证语法**、
退出码**不经管道读**、**启动前自检磁盘**、**atexit 兜底还原**、
洁净度判据 = **与原始字节逐字节相同**）。

⚠ **新增 4 例**：

⑳ **NC20 · 行为级**：把**随机包根路径**放回输出（`$BIN_REL` 改回 `$BIN`）
⇒ ⇒ 接线门红（forbid 门）**且** 用「坏布局 fixture」跑两遍 ⇒ **输出确实不同**
⇒ ⇒ **随机量进输出 = 恒红 = 假红**这条被**行为级**坐实（不只是形态门）；
21 **NC21 · 形态级**：摘掉 CI 第 12 步的**双跑第二遍（bash）**
⇒ ⇒ 接线门红（per-step 门）**且** parity 门**仍然绿**
⇒ ⇒ 正常输入下行为完全没变 ⇒ ⇒ **只有形态门项能抓住**；
22 **NC22**：登记册里这条的**双跑位置**被改成 `parity`
⇒ ⇒ 接线门红 **且** parity 门**也红**（参数列 `deb` 不被接受 ⇒ **fail closed**）
⇒ ⇒ 不许静默变成「空洞的一致」；
23 **NC23**：双跑脚本的 `n_dual_cish` 计数被摘掉
⇒ ⇒ 接线门红 **且** 汇总行报的「登记册共 10 条」与真实 **11** 行**对不上**
⇒ ⇒ 承诺被藏起来时**看得见**。
24 **NC24**：把**随机临时目录名**放回输出（「解包失败」那行改回打原始日志）⇒ ⇒ 接线门红（need 门项）**且** 两遍输出**仍然相同**⇒ ⇒ ⚠ 那条消息**只在解包失败时才打** ⇒ 正常输入下行为完全没变⇒ ⇒ 双跑门自己**看不出来** ⇒ ⇒ **只有形态门项能抓住**⇒ ⇒ ⚠ **这一例还坐实了「forbid 的双引号区段口径」的洞**（坑 ⑤）。
⚠⚠⚨ **如实记录：首轮 24 例里有 4 例（NC14 / NC15 / NC18 / NC21）的**附加断言**（「parity 输出里**没有**『这一组没跑通』」）间歇性不过** ⇒ ⇒ 复跑这 4 例 ⇒ **4/4 真红** ⇒ ⇒ **核心断言（接线门红 + 关键文案命中 + parity 门仍然绿）首轮就是成立的** ⇒ ⇒ 判为**环境性抖动**（某个探针/契约门在 scratch 树里偶发没跑通）⇒ ⇒ **根因未定位** ⇒ ⇒ 如实记为**待查**（⚠ 与坑 ⑥ 同源：都是「跑负控时的环境」）；⚠⚠⚨ **根因已在批 ED 定位**（⇒ 见 `E.2cm`）：真因是**双跑覆盖面门把契约门的退出码 + 措辞写进自己的输出**，而契约门 rc 随**网络可达性**在 0/3 之间摆 ⇒ ⇒ 输出措辞随之摆 ⇒ ⇒ 与「跑负控时的环境」**无关** ⇒ ⇒ 本条**订正**。

**⑦ 数字**

⚠ **门项条数 1387 → 1404**（批 DZ 段 **17 条**，**三处同改**）；
⚠ **门项执行次数 1390 → 1407**（+17）；
⚠ **恒真探针条件 1023 → 1026**（⚠ ci.sh 的 2 个新条件 + 批 DZ 段 trailer +1 ⇒ 实测对上）；
⚠ 批 CP 两条配对门 **73 → 74** / **74 → 75**；
⚠ **登记册 11 数据行 = `DUAL` 9 + `EXEMPT` 2**（⚠ `DUAL` 9 条里 **7** 条由双跑覆盖面门双跑、
**2** 条由 CI 入口双跑 ⇒ 三个数字都对得上）；
⚠ **双跑覆盖面门 rc=0**（双跑 **7** 个 + CI 入口 **2** 个 + 豁免 **2** 个；
相对路径与绝对路径两种调用都试过）；
⚠ `ci.sh` 的 `exit [1-9]` 总数 **41 → 43**；恒真探针范围基线 `shell` **19**（不变）；
⚠ 孤儿探针断言脚本数 **19 / 33**（不变）；
⚠ `|| true` 盘点 **33 处**、未验证出口盘点 **21 组 / 73 处** ⇒ **均不变**；
⚠ **负控 24 真红**；累计 **1340/1340**；
⚠ **CI 时间**：deb 布局验收双跑各 **0.13 秒** ⇒ **+0.13 秒**
（⚠ 对比契约门的 **+22 秒** ⇒ 这一门**几乎不要钱**）；
⚠ **`ci.sh` 16/16 步跑完但 rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**。

**⑧ 已知边界（如实记着）**

⚠⚠⚨ **`build-deb.sh` 仍豁免**（**有副作用** ⇒ 双跑 = 构建两遍 ⇒ CI 时间翻倍且产物可能含时间戳）
⇒ ⇒ 这是**唯一**一条双跑覆盖面上的硬边界；
⚠⚠⚨ **`ci-shell-parity.sh` 自己仍不被双跑**（自引用 ⇒ 递归）；
⚠⚠⚨ **deb 布局验收的双跑在 CI 第 12 步内部** ⇒ ⇒ 只有**跑到第 12 步**才会双跑它
⇒ 若前 11 步就红了 ⇒ 这一门**没跑**（⚠ 但那是**真红**，不是假绿）⇒ ⚠ 严格说：
**它的覆盖面取决于前面步骤跑到哪儿** ⇒ 如实记着；
⚠⚠⚨ **双跑只判「两版是否一致」，不判「结论本身对不对」** ⇒ 两遍都红时它**仍报一致**
⇒ ⇒ 修法是**让两遍都跑真判据**，**不是**加严（⚠ 加严会假红：「未验证」用专属退出码 **3**，
那是**合法结论**，不是失败）；
⚠ ⚠ **stdout 与 stderr 是合流后比** ⇒ 理论上**顺序**可能受缓冲影响
⇒ ⇒ 但两遍的**流内容与程序顺序都相同** ⇒ 合并结果仍逐字节相同
（⚠ 实测：失败态两遍逐字节相同）⇒ ⚠ 这是**取舍**，不是「分开比」⇒ 如实记着；⚠⚠⚨ **forbid 门项的口径是「双引号区段」⇒ 打印行里**嵌套命令替换**（自带引号）⇒ 随机量落在区段**外** ⇒ **抓不到**（坑 ⑤）⇒ ⇒ 本批用**一条 need 门项**把「解包失败」那一行**钉住** ⇒ ⇒ 但**通用形态**仍没堵 ⇒ ⇒ 如实记着（⇒ 真有人这么写 ⇒ 表现是「双跑门报输出不同」⇒ **误诊**：真因是「输出里有随机量」⇒ 但**门确实红了** ⇒ 结论没被放过）；⚠ ⚠ **并发重 I/O 时审计器会返回 rc=2「盲区」**（坑 ⑥）⇒ ⇒ **跑负控时别干别的重活**；
⚠ ⚠ 登记册「理由写得对不对」机器判不了（只能判非空）⇒ **危险方向靠人工**；
⚠⚠⚨ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。

### E.2cj 双跑覆盖面门自己进双跑（批 EA）

**① 起因（实测，不是推演）**

批 DZ 收口时如实留了已知边界（台账 E.2ci ⑧），其中一条是：

· ⚠⚠⚨ **`ci-shell-parity.sh` 自己仍不被双跑**（登记册里的豁免理由写的是
「**自引用 ⇒ 递归**」）。

⇒ ⇒ **本批就是那条**（`build-deb.sh` 有副作用 ⇒ 动不了；那是唯一硬边界）。

⚠⚠⚨ **但「自引用 ⇒ 递归」这句话本身要先实测掉** —— 它**只在一种位置上成立**：

· 登记册的「双跑位置」列本来就区分两种：`parity`（由 `ci-shell-parity.sh` 自己跑）
与 `ci.sh`（由 **CI 入口**跑）；
· 若把 `ci-shell-parity.sh` 自己那行放在 **`parity`** 位置 ⇒ 它会被自己跑
⇒ ⇒ **真递归** ⇒ 这条豁免理由**成立**；
· 但若放在 **`ci.sh`** 位置 ⇒ 由 **CI 入口**双跑它 ⇒ 而双跑脚本自己**只跑 `parity`
位置的条目** ⇒ ⇒ **自己那行被跳过** ⇒ ⇒ **不递归**。

⇒ ⇒ **豁免理由过宽** ⇒ 「登记册最后一条**可动的**豁免」其实可以动。

**② 决定性实测**

· `ci-shell-parity.sh` 在 `sh` 与 `bash` 下**输出逐字节相同、退出码均为 0**
⇒ ⇒ 可双跑；
· 「不递归」由**代码结构**保证，不是靠约定：
`ci-shell-parity.sh` 里有 `if [ "$where" != "parity" ]; then … continue; fi`
那一支 ⇒ `ci.sh` 位置的条目**被这一支跳过** ⇒ 自己跑自己时**不会**再触发自己。

⚠⚠⚨ **两遍输出逐字节相同**是**前提** —— 若两遍不同，双跑门会红 ⇒ CI 恒红。

**③ 修法（三处，方向一致）**

⚠⚠⚨ **① CI 第 9 步把双跑覆盖面门自己双跑**（`sh` + `bash` ⇒ 退出码必须一致
+ 输出必须逐字节一致；两份日志都落 `TMPDIR` ⇒ 批 DU 纪律：第二遍会多看到
第一遍的产物 ⇒ 假红）；⚠ **不新增步骤**（新增步骤会牵动 16 个步骤标记
+ 一条 `arch_need_ml` 门）⇒ ⇒ **在第 9 步内部**双跑（与批 DZ 第 12 步同款做法
⇒ 前几批「新增步骤风险高」的说法在批 DZ 就已被实测订正过）。

⚠⚠⚨ **② 登记册 `ci-shell-parity.sh` 由 EXEMPT 改判 DUAL**（位置 = `ci.sh`、
参数 = `src`）⇒ ⇒ 登记册 **EXEMPT 只剩 1 条**（`build-deb.sh` ⇒ 有副作用
⇒ **长期豁免** ⇒ 唯一硬边界）。

⚠⚠⚨ **③ 登记册的计数门口径必须数「状态列」**（**不是**数字样）——
⚠ 本批实测撞上：旧口径 `.*EXEMPT` ⇒ 理由文字里写一句「EXEMPT 只剩 1 条」
⇒ 计数**变成 2** ⇒ 门**当场报失准** ⇒ ⇒ 口径收紧到**第 2 段**。

**④ 落门 / 判据**

批 EA 段新增 **9 条**（单独成块）：

· 双跑四件套 **5 条**（第一遍接住退出码 + 第二遍接住退出码 + 退出码比对
+ 输出比对 + 结论必须报出来）；
· 两份日志落 `TMPDIR` **2 条**；
· 登记册逐条钉住 `ci-shell-parity.sh` 那行 **1 条**（状态/位置/参数全钉）；
· 「位置列非 `parity` ⇒ 跳过」那一支 **1 条**（**不递归**的保证本身）。

+ 原地替换 **7 处**：登记册 DUAL **9 → 10** / EXEMPT **2 → 1**、
CI 调双跑门那条正则**改形态**（`if ! sh …` → 接住退出码 + 落盘 + 双跑）、
第 9 步 per-step 门 **1 → 2**、批 CP 两条配对门 **74 → 75** / **75 → 76**、
`exit [1-9]` **43 → 45**、常量门项 **1404 → 1413** + 说明链。

⚠ **门项条数 1404 → 1413 三处同改**（基线文件 / 审计器常量 `GATE_LINES_EXPECTED`
/ `ci-wiring.sh` 里那条门项的数字 ⇒ 批 CR 纪律）。

**⑤ 本批踩到的坑（**⑤ 本批踩到的坑（**⑤ 本批踩到的坑（四条，都是真跑出来的）**

① ⚠⚠⚨ **GNU grep -E 不认 `\t`**（POSIX ERE 无此转义 ⇒ 被当成字面 `t`）
⇒ ⇒ 写 `'^deepin/scripts/.*\tDUAL\t'` ⇒ 门侧与审计器**命中数都是 0**
⇒ ⇒ **门恒红** ⇒ 审计器 rc=4 **当场报出失准**；
⚠⚠⚨ **先前的判断「门侧与审计器口径不一致」是错的** —— 审计器的 `count_hits`
**也是** `grep -oE`（**同一个 GNU grep**）⇒ ⇒ **两侧天然同口径**
⇒ ⇒ 真正的修法是换一个**两侧都认**的写法，不是去「对齐两侧」；
⚠ 修法：口径改成 `^deepin/scripts/[^[:space:]]*[[:space:]]DUAL[[:space:]]`
（路径列不含空白 ⇒ `[^[:space:]]*` 只吃第 1 段 ⇒ 紧跟的空白落在**第 2 段**
⇒ 状态列被精确锚定 ⇒ **理由文字里的字样进不来**）
⚠⚠⚨ 顺手实测：`\s` 与 `[[:blank:]]` 也命中，但**它们把空格当分隔符**
⇒ 理由文字里「 EXEMPT 只剩」这种**空格 + 字样**会**误伤**（实测命中 2 而不是 1）
⇒ ⇒ **不能用** ⇒ 必须用 `[^[:space:]]*` 把**路径列**先钉死。

② ⚠⚠⚨ **两条日志门项的正则漏了 `.log` 后缀**（`deepdolphin-paritygate-sh\.\$\$`
少了 `\.log`）⇒ ⇒ 「期望 1 ≠ 实际命中 0」⇒ **审计器当场报出来**
⇒ ⇒ **批 DZ 同款坑**（当时也漏了 `.log`）⇒ ⇒ **写完立刻在目标文件里实数一遍**
（批 DY 教训复用，第二次踩到 ⇒ 说明这条纪律该做成门，本批已由审计器的
配准校准兜住 ⇒ 报错即时可见）。

③ ⚠⚠⚨ **「门项条数」≠「门项执行次数」**：接线门汇总行报「门项合计 **1416** 项」
而门项**行数**是 **1413** ⇒ ⇒ 两者**口径不同**（批 AH 纪律）⇒
⚠ 不许拿汇总行的数字去对基线（会误判成「条数对不上」）⇒ 如实记着。

**⑤·补 本批当场加的一条门：说明文字不许骗人**

⚠⚠⚨ **起因**：本批改门项期望值时（`74 → 75` / `75 → 76`）⇒ **说明文字没跟着改**
⇒ ⇒ 「说明文字称 74 处，期望值却是 75」⇒ ⇒ **文字在骗人**
⇒ ⇒ 这正是**批 DZ 台账坑 ③** 立的纪律（「改条数时，说明文字里的同一个数字也要一起改」）
⇒ ⇒ ⚠⚠⚨ **批 EA 把它又踩了一次** ⇒ ⇒ **人工纪律已被证明不可靠** ⇒ ⇒ 必须落成门。

⚠ **落法**：审计器新增一条检查（`check_label_count_text`）
⇒ 门项的说明文字里「**（恰好 N 处**」必须**等于**该门项的期望值 ⇒ 否则 rc=9 判红
⇒ ⚠ **口径**：只认「**（**恰好 N 处」这种**紧跟左括号**的写法
⇒ ⇒ 只命中「这条门项**自己**的条数」那一种
⇒ ⇒ 「必须恰好 N 处」「有门钉住**恰好 23 处**」那种**说的是别的门**的写法**不算**
（⚠ 实测：`build-deb.sh` 那条门项的说明里写着「die 调用点有门钉住**恰好 23 处**」
⇒ 那是**另一个门**的条数 ⇒ 若按「说明文字里有『恰好 N 处』就查」⇒ **误报**）。

⚠ **顺带订正了 3 条真撒谎的门项**：

· `ci-wiring.sh:2734`「全文失败上报的总数（恰好 39 处）」⇒ 实际 **41**
（⚠ **批 CN 遗留**：那一批把 39 → 41 改了期望值 ⇒ 说明文字漏改 ⇒ 本批顺手订正）；
· `ci-wiring.sh:3916`「段级 trailer 都要记全局红过（恰好 74 处）」⇒ 实际 **75**
（⚠ **本批引入**：批 EA 段单独成块 ⇒ 段级 trailer 多 1 处）；
· `ci-wiring.sh:3917`「声明 + 每段末清零（恰好 75 处 = 1 处声明 + 74 处段末清零）」
⇒ 实际 **76** ⇒ 75 → 76、74 → 75（⚠ **本批引入**）。

⚠⚠⚨ **正负有据自证**（批 DY 纪律）：故意把一条门项的说明文字改成「恰好 99 处」
（期望值仍是 75）⇒ ⇒ 审计器 **rc=9** + 指名道姓「ci-wiring.sh:3916 … 期望 75，
但说明文字称「恰好 99 处」」⇒ ⇒ 还原后**逐字节相同** + 审计器 rc=0 + 接线门 rc=0。

⚠ **连带改动**（新增 `FAILS.append(rc)` 的必然代价）：守卫 `labelbad` 要登记进
`FAIL_GUARDS`（批 DO 口径 ④ 双向红 ⇒ 不登记**当场报失准**）
⇒ `FAILS.append(9)` **5 → 6** ⇒ 门项期望值 **2 处**要改
⇒ ⇒ ⚠⚠⚨ **而且说明文字里的「五处」也要改成「六处」** ⇒ **同一个坑，本批踩了两次**
⇒ ⇒ 这正是**新加那条检查**要抓的东西 ⇒ ⇒ **自己被抓到了** ⇒ 如实记着。

**⑤·补·二 负控 NC26 实测撞出的洞：parity 门没有递归保护 ⇒ CI 会挂死**

⚠⚠⚨ **实测过程**：负控 NC26 把登记册里 `ci-shell-parity.sh` 自己那行的「双跑位置」列
改成 `parity` ⇒ ⇒ 期望它「被 parity 门自己跑自己」⇒ ⇒ **实测：进程链一路往下**
（`ci-shell-parity.sh` → 它自己 → 它自己 → …）⇒ ⇒ **负控用例本身跑不完**
⇒ ⇒ ⚠⚠⚨ **CI 会挂死，而不是变红** ⇒ ⇒ **比假绿更坏**（假绿至少还是绿的；
挂死是**什么都得不到**）。

⚠⚠⚨ **为什么原来没这层保护**：登记册写的是「位置列非 `parity` ⇒ 跳过」
⇒ ⇒ 那一条保证的是「`ci.sh` 位置的条目**不被自己跑**」⇒ ⇒ 但**反过来**没保证：
「**自己那行**不许是 `parity` 位置」⇒ ⇒ 改一下登记册 ⇒ ⇒ 递归 ⇒ ⇒ 没人拦。

⚠ **修法（fail closed）**：脚本在读登记册时**认出自己**
⇒ ⇒ 自己那行若是 `parity` 位置 ⇒ ⇒ **拒绝继续**（`exit 1` + 说清原因）
⇒ ⇒ 从「挂死」变成**红的**。
⚠⚠⚨ **两种键都要认**：登记册的键 = **相对仓库根**的路径（批 CY 纪律）
⇒ `$SRC` 是 `deepin/` 时键是 `deepin/scripts/ci-shell-parity.sh`
⇒ `$SRC` 是**仓库根**时键是 `scripts/ci-shell-parity.sh`
⇒ ⇒ **漏一种 ⇒ 递归照样发生** ⇒ ⇒ 末尾再加一个通配兜住。

⚠ **落门**：批 EA 段追加 **3 条**（「认出自己」的键常量 + 键匹配分支 + 拒绝出口）
⇒ 门项条数 **1413 → 1416（三处同改）**。

⚠ **实测**：位置列改成 `parity` ⇒ parity 门 **rc=1** + 输出里写着
「本脚本会**自己跑自己** ⇒ **无限递归** ⇒ CI 会挂死 ⇒ 拒绝继续」
⇒ ⇒ **不再挂死** ✓ ⇒ 还原后**逐字节相同** + parity rc=0。

**⑥ 负控 27 真红**

新增 **NC25 / NC26 / NC27**（批 EA 的三条承诺各有负控）：

· **NC25** 摘掉 CI 第 9 步**双跑覆盖面门自己的第二遍（bash）**
⇒ ⇒ 接线门**红** **且** parity 门**仍然绿**（行为完全没变 ⇒ 只有形态门项能抓住）；
· **NC26** 登记册里**双跑覆盖面门自己那行的位置列**被改成 `parity`
⇒ ⇒ 接线门**红** **且** parity 门**也红**（不许静默变成「空洞的一致」）；
⇒ ⇒ ⚠⚠⚨ **实测**：改这行时 parity 门**无限递归** ⇒ ⇒ **用例本身跑不完**
⇒ ⇒ **本批因此给 parity 门加了递归保护**（见 ⑤·补·二）⇒ ⇒ 现在它是**红的**而不是挂死的；
· **NC27**（⚠ **正向**用例）登记册的**理由列里塞进 `EXEMPT` 字样**
⇒ ⇒ 接线门必须**仍然绿** **且** DUAL/EXEMPT 计数**仍是 10/1**
⇒ ⇒ 这是「计数门口径收紧」这条承诺的**正向**证明（不是红，是**不许被带偏**）。

⚠⚠⚨ **本批为此把 harness 的判定逻辑改了两次（都是判据写错，不是行为问题）**：

① `parity-green` 那条附加断言原来判「parity 输出里**没有**『这一组**没跑通**』」
⇒ ⚠ 批 EA 之后（登记册把 parity 门自己改判 `ci.sh` 位置）⇒ parity 门**不再跑**
它自己 ⇒ ⇒ 它的输出里**契约门那一行**如实写着「退出码 3 ⇒ 这一组**没跑通**」
（⚠ 退出码 3 = **引擎未找到 ⇒ 未验证**，不是失败 ⇒ **正常状态**）
⇒ ⇒ 旧判据 ⇒ **误报**「行为变了」⇒ ⇒ **判据换法**：改成「**变异前后的 parity 输出
逐字节相同**」⇒ ⇒ 这才是「行为完全没变」的准确判据；
② ⚠ **正向用例**（`NC27`）的判据是「**必须仍然绿**」⇒ ⇒ 它**本来就不该红**
⇒ ⇒ 按「红」计分 = **判据写错了** ⇒ ⇒ 正向用例的结论改成「仍然绿 + 文案命中
+ 附加断言成立」。

⇒ ⇒ ⚠⚠⚨ **如实记着**：这两处都是**harness 自己的判据**有问题
⇒ ⇒ **不是**被测的门有问题 ⇒ ⇒ 改 harness 不算「改判据以求通过」
⇒ ⇒ ⚠ 但纪律仍然是：**每个附加断言都要问「它在问什么」** ⇒ 判据写错 = 该例无效。

⇒ 累计 **1343/1343**。

⚠⚠⚨ **负控 harness 的一处判据过宽（本批实测撞上 ⇒ 当场订正）**：
`parity-green` 那条附加断言原来判「parity 输出里**没有**『这一组**没跑通**』」
⇒ ⚠ 批 EA 之后（登记册把 `ci-shell-parity.sh` 改判 `ci.sh` 位置）⇒ parity 门**不再跑**
它自己 ⇒ ⇒ 它的输出里**契约门那一行**如实写着「退出码 3 ⇒ 这一组**没跑通**」
（⚠ 退出码 3 = **引擎未找到 ⇒ 未验证**，不是失败 ⇒ **正常状态**）
⇒ ⇒ 旧判据 ⇒ **误报**「行为变了」⇒ ⇒ **判据换法**：改成「**变异前后的 parity 输出
逐字节相同**」⇒ ⇒ 这才是「行为完全没变」的准确判据 ⇒ ⇒ **不**看「有没有『没跑通』」
这种**本来就可能存在**的状态。

⚠⚠⚨ **如实记录**：批 DZ 留下的「4 例附加断言间歇性不过」在批 EA 复跑时
**没有复现**（27/27 首轮即真红）⇒ ⇒ **根因仍未定位** ⇒ 如实记为待查。

**⑦ 数字**

· 门项条数 **1404 → 1413**（三处同改）→ **1416**（递归保护追加 3 条 ⇒ 再三处同改）；
· 执行次数 **1407 → 1419**；
· 登记册 **11 行 = DUAL 10 + EXEMPT 1**（DUAL 里 7 条由双跑门双跑、
**3 条**由 CI 入口双跑）；
· 汇总行报「登记册共 11 条 = 本脚本双跑 7 + CI 入口双跑 3 + 豁免 1」；
· 恒真条件 **1026 → 1036**；配对门 **74 → 75** / **75 → 76**；
· `exit [1-9]` **43 → 45**。

⚠ **CI 时间**：双跑覆盖面门双跑各约 **11 秒** ⇒ **+11 秒**
（⚠ 这一门比契约门那 +22 秒便宜一半）。

⚠ **`ci.sh` 16/16 步跑完但 rc=3**（**1 组未验证**：本机缺 `appstream-util`）
⇒ ⚠⚠⚨ **如实记录，不粉饰**。

**⑧ 已知边界（如实记着）**

⚠⚠⚨ **`build-deb.sh` 仍豁免**（**有副作用** ⇒ 双跑 = 构建两遍 ⇒ CI 时间翻倍
且产物可能含时间戳）⇒ ⇒ 这是**唯一**一条双跑覆盖面上的硬边界；
⚠⚠⚨ **双跑覆盖面门的双跑在 CI 第 9 步内部** ⇒ ⇒ 只有**跑到第 9 步**才会双跑它
⇒ 若前 8 步就红了 ⇒ 这一门**没跑**（⚠ 但那是**真红**，不是假绿）⇒ ⚠ 严格说：
**它的覆盖面取决于前面步骤跑到哪儿** ⇒ 如实记着；
⚠⚠⚨ **双跑只判「两版是否一致」，不判「结论本身对不对」** ⇒ 两遍都红时它**仍报一致**
⇒ ⇒ 修法是**让两遍都跑真判据**，**不是**加严（⚠ 加严会假红：「未验证」用专属
退出码 **3**，那是**合法结论**，不是失败）；
⚠ ⚠ **stdout 与 stderr 是合流后比** ⇒ 理论上**顺序**可能受缓冲影响
⇒ ⇒ 但两遍的**流内容与程序顺序都相同** ⇒ 合并结果仍逐字节相同 ⇒ ⚠ 这是**取舍**，
如实记着；⚠ ⚠ 登记册「理由写得对不对」机器判不了（只能判非空）⇒ **危险方向靠人工**；
⚠⚠⚨ **登记册的计数门口径是「第 2 段」** ⇒ ⇒ 用**空白类**（`\s` / `[[:blank:]]`）
表达分隔符**会误伤**（理由文字里「 EXEMPT 只剩」这种空格 + 字样）
⇒ ⇒ 必须用 `[^[:space:]]*` 把**路径列**钉死 ⇒ ⚠ **这个坑已被 NC27 钉住**；
⚠ ⚠ **GNU grep -E 不认 `\t`** ⇒ ⇒ 门项正则里要表达 TAB ⇒ 只能用
`[^[:space:]]*` + `[[:space:]]` 这种**两侧都认**的写法；
⚠⚠⚨ **并发重 I/O 时审计器会返回 rc=2「盲区」** ⇒ ⇒ **跑负控时别干别的重活**；
⚠⚠⚨ **审计器新增的检查只认「（恰好 N 处」** ⇒ ⇒ 「说明文字里**别处**的条数**
（写成「必须恰好 N 处」那种）**不在它的口径内** ⇒ ⇒ 如实记着（⚠ 这不是洞：
那些数字说的是**别的门**的条数 ⇒ 不该被这条检查管）；
⚠⚠⚨ **本批不改任何产品代码** ⇒ 判据层零业务数据写入。



## F. linux 端

**本轮明确暂缓**（用户 2026-10-19 定：「linux 通用再说」）。
linux 侧已知独立缺口记在 `linux/README.md` 的「与 macOS 端的已知差异」与 `linux/VERIFY-ON-LINUX.md`。
注意：章程 §3.5 把 linux 的实现指定为**仓颉 Canvas 移植** —— 与 deepin 的 Qt QPainter 同款内核需求，
将来做 linux 时**可复用本批的契约层与判据思路**（端口式 CanvasSink 是为这一步留的）。

### E.2ck 工具坏了不许静默跳过（批 EB）

**① 起因（实测，不是推演）**

批 EA 之后，审计器里有一族「**次数门**」的校准是这样做的：

· `count_hits` / `count_hits_ml` / `count_lines` 在**工具起不来**时
（重 I/O 下 fork 失败 / `grep` 不在 `PATH` / `grep` 返回非 0|1）
⇒ ⇒ 直接 `return None`；
· 而它们的 **5 个调用点**全是 `if got is None: continue` ⇒ ⇒ **静默跳过**。

⇒ ⇒ **那一族次数门根本没被校准** ⇒ ⇒ 期望值对不对**没人知道**
⇒ ⇒ 而审计器**照样 rc=0** ⇒ ⇒ **假绿**。

⚠⚠⚨ **假绿比假红更坏**：假红至少会红；假绿是**没人知道**。

**② 决定性实测（单测坐实，不是推演）**

把 `count_hits` 桩成**永远返回 None**，再喂一条**期望 999、实际 1** 的门项
⇒ ⇒ 审计器输出里**一条失准都不报** ⇒ ⇒ **静默跳过坐实**。

⚠ **对照**：同一份代码在**工具正常**时，那条门项会当场报出
「期望 999 ≠ 实际命中 1」⇒ ⇒ 差别只在**工具起不来** ⇒ ⇒ 洞在「静默」二字上。

**③ 修法（四种坏法统一收口）**

工具失败 ⇒ ⇒ **登记**进 `TOOL_FAILURES`（模块级登记簿，**零名单维护**）
⇒ ⇒ `tool_failure_rc()` **统一收口** ⇒ ⇒ 判红 + **指名道姓**。

⚠⚠⚨ 本批把**四种坏法**一并收口（它们形态不同，但后果一样）：

· `count_hits` / `count_hits_ml`（静默 `return None` ⇒ 假绿）；
· `count_lines`（同样静默 ⇒ 同样假绿）；
· `line_numbers`（**捕获了但不登记** ⇒ 结论不可信）；
· `arch_need_count_in_fn` / `arch_need_count_in_step`
（**根本没保护** ⇒ 崩 ⇒ **诊断失真**：崩的原因被别的错误盖住）。

⚠⚠⚨ **收口点必须每个出口都管** —— **本批第一版踩到的坑**：
收口只插在**硬门模式**分支里 ⇒ ⇒ 而 `--list`（**CI 实际跑的**）与**报告模式**
**都没被覆盖** ⇒ ⇒ 单测跑出来 **rc=0** ⇒ ⇒ **看着像没修**
⇒ ⇒ 改成抽成 `tool_failure_rc()` + **三个出口都调**。

⚠⚠⚨ **`FAILS[0] if FAILS else …` 会短路** ⇒ ⇒ 收口必须**无条件先跑**
⇒ ⇒ 统一出口改成 `_tool_rc = tool_failure_rc()` 再取 rc。

**④ 连带门项改动**

· `FAIL_GUARDS` 加 `TOOL_FAILURES`（+ 逐字正则同步）；
· `FAILS.append(2)` **15 → 27**；
· `return 2`（前置早退）**4 → 5**；
· `return 0`（成功出口）**3 → 1**（另两个出口改成
`return tool_failure_rc() or 0` ⇒ **工具用不了时不是 0** ⇒ fail closed）；
· 失败出口家族计数 **4/15/20 → 5/27/33**
（前置早退 / 收集 / 两族合看）。

**⑤ 落门**

批 EB 段新增 **3 条**（判定函数 + 每个出口都收口 + 工具失败登记簿）；
批 EB·补追加 **1 条**（见 ⑥）；
批 EB·补②追加 **3 条**（见 ⑥·二）⇒ 门项条数 **1416 → 1423（三处同改）**。

**⑥·二 落门自检撞出**三个洞**（本批自己踩的 ⇒ 当场修）**

⚠⚠⚨ 落门**不是**「写完就完」⇒ ⇒ 必须**逐条自检「这条门真的守住了我说的那句话吗」**
⇒ ⇒ 本批自检撞出**三个洞**（全部当场修）：

· ⚠⚠⚨ **① 门项 5191 的正则是「手抄」出来的** ⇒ ⇒ 它写的是 **8 个字面空格**
  ⇒ ⇒ 只钉住 `--list-all` 那个出口 ⇒ ⇒ **报告模式那个出口没人守**
  ⇒ ⇒ 而且**期望值也写 1** ⇒ ⇒ **门没牙**（删掉一个仍够 ⇒ 门不红）
  ⇒ ⇒ 现在改成 `^\s+` + 期望值改 **2** ⇒ ⇒ **两个出口一个都不能少**
  ⇒ ⇒ ⚠ 纪律：「正则**绝不手抄**」——本批又犯了一次
  ⇒ ⇒ ⚠⚠⚨ 而这条门项的**说明文字**明明写着「另**两个**出口」⇒ ⇒ **文字与门不符**
  ⇒ ⇒ 这正是 ⑥ 那条**新口径**（说明文字不许撒谎）的**活靶子** ⇒ ⇒ 幸好当场订正了;
· ⚠⚠⚨ **② 「各个工具调用点是否都接了收口」**没人守** ⇒ ⇒ 把某处
  `_tool_failed(...)` 改回 `return None` ⇒ ⇒ 工具坏了又**静默略过**
  ⇒ ⇒ **门项全绿** ⇒ ⇒ **假绿**回来
  ⇒ ⇒ ⚠ 手工登记名单**必然会漏**（新增一个工具调用点 ⇒ 忘了登记 ⇒ 洞回来）
  ⇒ ⇒ 落成**零名单维护的 AST 规则**（`check_silent_tool_skip`）：
  扫**全文件**所有 `except OSError` 块 ⇒ 凡出现裸 `return None` / `continue`
  而该块内**没有** `_tool_failed(...)` 登记 ⇒ ⇒ 判红（rc=2 = 盲区）;
· ⚠⚠⚨ **③ `_tool_rc = tool_failure_rc()` 那一行**没人守** ⇒ ⇒ 改成 `_tool_rc = 0`
  ⇒ ⇒ **收口失效**（工具坏了 ⇒ rc 变 0/3 ⇒ **假绿**回来）
  ⇒ ⇒ 而上一条门只钉住**出口那一行**的形态 ⇒ ⇒ 盯不到这一行 ⇒ ⇒ 补 1 条门项。

⚠⚠⚨ **本批还撞出「AST 规则自己」的一个 bug（负控 NC31 实测撞出）**：
第一版规则用 `st.value is None` 判「返回 None」⇒ ⇒ 而 AST 里
`return None` 是 `Return(value=Constant(value=None))` ⇒ **`st.value is None` 是 False**！
⇒ ⇒ 审计器里**真实的静默点全是 `return None`** ⇒ ⇒ **一条都抓不到** ⇒ ⇒ **规则是空的**
⇒ ⇒ 现在两种都认（裸 `return` + `return None`）⇒ ⇒ 负控 NC31 实测 rc=2 ✅
⇒ ⇒ ⚠⚠⚨ **教训**：**没有负控的门是空的** —— 这条新规则差点白写。

**⑥ 附带发现：批 EA 立的「文字不许撒谎」那道门，口径太窄（自己撞上）**

⚠⚠⚨ 本批把 `FAILS.append(2)` 从 12 改成 13 时，**说明文字漏改**（还写着
「恰好 12 处」）⇒ ⇒ 这正是**批 EA 立那道门**要抓的东西 ⇒ ⇒ 跑审计器 ⇒ **没报**
⇒ ⇒ **那道门自己有盲区**。

⚠⚠⚨ **根因**：批 EA 的口径只认「（恰好 N 处」（**紧跟左括号**）
⇒ ⇒ 它把「**必须恰好 N 处**」（主语就是本门 ⇒ 说的是**自己**）
与「**有门钉住恰好 23 处**」（说的是**别的门**）**混为一谈**
⇒ ⇒ **为避开一个例子 ⇒ 误排了 30 条真·自己的门项**
⇒ ⇒ 那 30 条的说明文字**完全不受管**。

⇒ ⇒ 口径扩到两种写法都认 ⇒ ⇒ 实测全仓 **44 条**门项的说明文字写了条数
⇒ ⇒ 扩口径后**只有 2 条真失准**、**零误报**：

· `ci-wiring.sh:3323` 实参 **6** 而文字称「恰好 5 处」（**批 CQ 历史遗留**）；
· `ci-wiring.sh:3943` 实参 **13** 而文字称「恰好 12 处」（**批 EB 自己引入的**
  ⇒ ⇒ 后面 ⑥·二 新增的 AST 规则又加了一处 `FAILS.append(2)` ⇒ ⇒ 现值 **14**）。

⇒ ⇒ 两条**当场订正** ⇒ ⇒ 并**新增 1 条门项**钉住新口径
（正则里用 `[|]` 表示字面竖线 ⇒ GNU grep -E 与 Python `re` **同口径**；
⚠⚠⚨ **不许写 `\|`** —— POSIX ERE 里 `|` 是 alternation ⇒ GNU grep 认、Python `re` 不认
⇒ ⇒ 踩批 EA 同款坑）。

**⑦ 负控 33 真红**

新增 **NC28 / NC29 / NC30**：

· **NC28** 把审计器里的**工具失败登记簿**摘掉 ⇒ ⇒ 「工具坏了不许静默跳过」
这条承诺**没人守**了 ⇒ ⇒ 接线门必须**红**（门项钉住登记簿那个列表本身）
⇒ ⇒ **双断言**：接线门红 **且** 审计器红；
· **NC29**（⚠ **正向**用例）让 `grep` **不可用**（`PATH` 里拿掉）
⇒ ⇒ 工具起不来 ⇒ ⇒ 审计器必须**红**（fail closed）⇒ ⇒ **不许 rc=0**
⇒ ⇒ 报错必须**说清**「工具用不了 ⇒ 那些门项**根本没被校准**」
⇒ ⇒ 负控那一半由 **NC28** 承担；
· **NC30** 把某条门项的**说明文字里的条数**改错（13 → 12）
⇒ ⇒ 那条门项的**期望值没变**（**行为判定完全没变**）
⇒ ⇒ 但说明文字**在骗人** ⇒ ⇒ 审计器必须**红**（专属码 **9**）
⇒ ⇒ 且必须**指名道姓**（哪一行 / 期望多少 / 说成多少）；
· **NC31** 把审计器里**一处收口**改回裸 `return None`
⇒ ⇒ 那个 `except OSError` 块里就**没有** `_tool_failed(...)` 登记了
⇒ ⇒ 工具坏了 ⇒ ⇒ 又**静默略过** ⇒ ⇒ 审计器必须**红**（专属码 **2** = 盲区）
⇒ ⇒ 且必须**指名道姓**（哪一行 + 为什么）
⇒ ⇒ ⚠⚠⚨ **这一例撞出了 AST 规则自己的 bug**（见 ⑥·二 末）⇒ ⇒ 差点白写一条规则；
· **NC32** 删掉**一个**「工具用不了」的收口出口 ⇒ ⇒ 那个出口**没人收口**了
⇒ ⇒ 门项 5191（收口必须**在每个成功出口上**）必须**红**
⇒ ⇒ ⚠ 这一例是**门项级**的：证明 5191 现在**有牙**（修之前是**没牙**的）。

⚠⚠⚨ **本批把 harness 的判定逻辑改了一次（是判据写错，不是行为问题）**：
NC30 的附加断言原来写「**接线门必须仍然绿**」⇒ ⇒ 实测：**接线门自己会跑审计器**
⇒ ⇒ 审计器红 ⇒ ⇒ 接线门**必然**跟着红 ⇒ ⇒ 那个问题**不成立**
⇒ ⇒ 按纪律（「每个附加断言都要问『它在问什么』」⇒ 判据写错 = 该例无效）
⇒ ⇒ 换成「**专属码 9 + 指名道姓**」⇒ ⇒ ⇒ 改 harness 不算「改判据以求通过」。

⇒ ⇒ 累计 **1349/1349**（批 EA 的 1343 + 本批 6）。

⚠⚠⚨ **如实记着的已知边界**：

· ⚠⚠⚨ **「grep 全挂」时 rc=4 而非 rc=2** —— 因为**先**有别的失准
⇒ ⇒ rc 取**最先失败**的那个（批 CQ 纪律）⇒ 如实记着；
· ⚠⚠⚨ **接线门自己会跑审计器** ⇒ ⇒ 「接线门红 **且** 审计器红」这个双断言
**不独立**（NC28 那一例）⇒ ⇒ 如实记着；
· ⚠⚠⚨ **并发重 I/O 下审计器 rc=2「盲区」的根因仍未定位** ——
本批定位的是**同一环境条件下的另一个洞**（工具坏了 ⇒ 静默跳过 ⇒ 假绿）
⇒ ⇒ 两者**形态已统一**（都判红 + 指名道姓），但**触发条件**仍待查；
· ⚠⚠⚨ **AST 规则只管 `except OSError`**（工具坏了 ⇒ 门项没被校准 ⇒ 盲区）
  ⇒ ⇒ `except (UnreadableSource, SyntaxError)`（源读不了）与 `except ValueError`
  （门项解析失败）**不在本规则范围**（那是**另一个家族**）⇒ ⇒ 已知边界，如实记着;
· ⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。

**⑦ 顺手发现：ci.sh 里「未验证」的处置**口径不一致**（本批收尾时实测撞上）**

⚠⚠⚨ 跑 `ci.sh` 时它 **rc=1**（不是批 EA 记的 rc=3）⇒ ⇒ **查清了，不是本批引入的**：

· 直接原因：第 10 步**引擎契约门**报「**1 组未验证**」
⇒ 「第 21 组真 API 那条：**GitHub API 不可达**（网络问题）」
⇒ ⇒ 实测直连 `api.github.com` 得 **http_code=403**（限流）⇒ ⇒ **环境侧**
⇒ ⇒ 本批**零产品代码改动** ⇒ ⇒ 与本批无关 ⇒ ⇒ **如实记着**（不粉饰，也不甩锅）;

⚠⚠⚨ **但顺手撞出一个真问题**：`ci.sh` 里「未验证」的两个出口**处置口径不一样** ——
· 第 **10** 步（契约门）：脚本 rc=3（未验证）⇒ ⇒ **直接 `exit 1`**
  （⇒ ci.sh 的 rc=**1** ⇒ 分诊表会说「**失败**」）；
· 第 **11** 步（deb 构建）：脚本 rc=3（未验证）⇒ ⇒ `skip++`
  （⇒ 末尾 rc=**3** ⇒ 分诊表会说「**未验证**」）。
⇒ ⇒ **同一个「未验证」，rc 语义却分两档** ⇒ ⇒ 排障会被带偏
（rc=1 会让人去查「契约门失败」，真因是「网络不可达 ⇒ 未验证」）
⇒ ⇒ ⚠ **本批不做**（不在本批范围：那是 CI 入口的出口口径统一）
⇒ ⇒ 记为**待办**（下一批可做：「`ci.sh` 的未验证出口处置口径统一」）。

**数字**

· 门项条数 **1416 → 1423**（三处同改）；
· 执行次数 **1419 → 1426**；
· 恒真条件 **1036 → 1045**；
· 失败出口家族 **4/15/20 → 5/27/33**；
· 负控 **33 真红** ⇒ 累计 **1349/1349**；
· 全量校验链 **14 步全绿**；审计器 rc=0、接线门 rc=0；
· ⚠ `ci.sh` **16/16 步跑完**但 **rc=1**（**1 组未验证**：第 10 步契约门第 21 组
  「真 API」⇒ **GitHub API 不可达**，实测直连 http_code=403 ⇒ **环境侧**，
  **与本批无关**）⇒ ⚠⚠⚨ **如实记录，不粉饰**（另见 ⑦ 的「口径不一致」）。

⚠⚠⚨ **累计数的基数（1343）来自批 EA 的台账记录，本批未独立复核**
（⚠ 批 CJ 纪律：一次性盘点的数字不许被当成事实 ⇒ 累计数**无处可查**
⇒ ⇒ 这里**如实记着**，不作断言）。
### E.2cl CI 入口「未验证」的处置口径必须统一（批 EC）

**① 起因（实测，不是推演）**

批 EB 收尾时**顺手撞出**并**如实记为待办**的那一条，本批做掉：

`ci.sh` 里「未验证」的**处置口径不一致** ——

· 第 **10** 步（引擎契约门）两处未验证 ⇒ ⇒ **当场 `exit 1`**
（⇒ `ci.sh` 的 rc = **1** ⇒ 分诊表会说「**失败**」）；
· 第 **11～16** 步那 **8 处**未验证 ⇒ ⇒ `skip++`
（⇒ 末尾统一 rc = **3** ⇒ 分诊表会说「**未验证**」）。

⇒ ⇒ **同一个「未验证」，rc 语义却分两档** ⇒ ⇒ 排障会被带偏
（rc=1 会让人去查「契约门失败」，真因是「网络不可达 ⇒ 未验证」）。

⚠⚠⚨ **但更严重的是第二层**：第 10 步**提前中止**
⇒ ⇒ 第 11～16 步**根本没跑**
⇒ ⇒ 那些步骤里的未验证/失败**永远不会被报出来**
⇒ ⇒ 批 CQ「一次报全」在 **CI 这一层**被破坏。

**② 行为坐实（实测，不是推演）**

scratch 副本 + **受限 PATH**（藏掉 `moongit`/`deepgit` ⇒ 走「引擎缺席」那一支）
⇒ 跑 `ci.sh` ⇒ rc = **1**；
⇒ 输出里 `› 3/16` 与 `› 10/16` 出现，**`› 11/16`～`› 16/16` 全部没出现**；
⇒ **没有**「有 N 组未验证」的汇总行
⇒ ⇒ 后面步骤的未验证/失败**一个都没被报出来**。

**③ 修法（口径统一）**

第 10 步两处未验证 ⇒ ⇒ 改用与其它 **8 处同款**的处置：

· 打印前缀从 `✗` 改成 `‣ SKIP`
（⇒ **`✗` 只留给真失败** ⇒ 排障**一眼能分**）；
· `exit 1` ⇒ ⇒ `skip=$((skip+1))`（**计数**）⇒ ⇒ **继续跑**
⇒ ⇒ 末尾统一 `exit 3`。

⚠ **真失败那一支仍然当场 `exit 1`**（失败优先 —— `ci.sh` 末尾注释说的就是它）
⇒ ⇒ 语义从「一个 rc 分两档」变成
「**未验证 = 3（唯一出口）/ 真失败 = 1**」。

**④ 连带改动**

· `deepin/scripts/ci.sh`：第 10 步两处未验证（elif 支 / else 支）+ 步骤标题文案；
· `deepin/scripts/ci-unverified-audit.baseline`：`ci.sh` 两行**处数**
（失败上报 **5 → 3**、跳过提示 **10 → 12**）＋ 理由文字
（⇒ 登记册**行数 21 不变** ⇒ 门项 4141 的 21 **不动**）；
· `deepin/scripts/ci-wiring.sh`：原地替换 **8 条**门项 + 批 EC 段新增 **7 条**；
· `deepin/scripts/ci-wiring-gates.baseline`：**1423 → 1430**；
· `deepin/scripts/ci-wiring-audit.py`：`GATE_LINES_EXPECTED` **1423 → 1430**。

⚠⚠⚨ **门项条数记四处**（批 CR 纪律；批 EB 实战确认要核**四处**）：
`ci-wiring.sh` 实数 / 基线文件 / 审计器常量 / 门项 3966 里的数字
—— 四处**全部 1430**。

**⑤ 落门（批 EC 段 7 条）**

· 「第 10 步只准有**一处** 8 缩进的 `exit 1`」（那必须是**真失败**那一支）；
· 「第 10 步**顶层分支体**（4 缩进）**一处都不许有** `exit 1`」
（⇒ 引擎缺席支不许提前中止）；
· 「第 10 步**不许自己 `exit 3`**」（⇒ 不许就地造出**第三档** rc）；
· 「第 10 步的两处未验证**都必须计数**」（`skip++` 恰好 **2** 处）；
· 两条**跨行锚定**：「`‣ SKIP 引擎契约门…` **必须紧跟** `skip++`」
（⇒ 打印与计数**成对**）；
· 「CI 入口的**未验证专属码 3 只有一个出口**」（全局 `exit 3` 恰好 **1** 处）。

⚠⚠⚨ **其中两条是「恒真风险」的**（期望值 0 / 依赖别的形态）
⇒ ⇒ 必须有**负控**证明它们**有牙** ⇒ ⇒ 见 ⑥。

**⑥ 负控 3 例（新增 NC34 / NC35 / NC36）**

⚠⚠⚨ **三例构成「同一环境、只差 `ci.sh` 一处」的对照**：

· **NC34**：第 10 步「契约门脚本自报 SKIP」那一支改回**当场 `exit 1`**
⇒ ⇒ **双断言**：接线门红（关键字「只准有」）**且**
`ci.sh` 输出里**没有**「› 11/16」
⇒ ⇒ ⚠ **环境构造**：⚠ 本机契约门**实测通过**（120 passed）
⇒ ⇒ elif 支**不可达** ⇒ ⇒ 用**不可达的代理**让契约门第 21 组（真 GitHub API）SKIP
⇒ ⇒ **实测坐实**：**不改任何文件** ⇒ 契约门 rc = **3**（118 passed / 1 unverified）；
· **NC35**：第 10 步「引擎缺席」那一支改回**当场 `exit 1`**
⇒ ⇒ **双断言**：接线门红（关键字「顶层分支体」）**且**「› 11/16」没出现；
· **NC36**（⚠ **正向对照**）：**不变异** ⇒ ⇒ 「› 11/16」**必须出现**
⇒ ⇒ 证明「改完之后未验证**不再提前中止**」。

⚠⚠⚨ **本批把 harness 的判据改了**两次**（是判据写错，不是行为问题）**：

⚠⚠⚨ **① 分支标记取自「被变异替换掉的那一行」** ⇒ ⇒ 变异**生效时恰恰找不到**
⇒ ⇒ 判据永远不成立 ⇒ ⇒ 改成取**那条 SKIP 提示行本身**
（⇒ 变异只改**下一行** ⇒ ⇒ 它原样保留 ⇒ ⇒ stderr 里**仍能认出走了哪一支**）。

⚠⚠⚨ **② 行为级断言必须「只抽第 10 步跑」（实测撞出，最要紧的一条）**：
负控的变异**让接线门自己红** ⇒ ⇒ `ci.sh` **第 9 步**（接线门）就 exit 1
⇒ ⇒ **第 10 步压根没跑** ⇒ ⇒ 「第 11 步没出现」这个断言**恒成立**
⇒ ⇒ **毫无信息量**（等于没有断言）
⇒ ⇒ 改成**抽出第 10 步**（用 ASCII 锚点 `DEEPGIT_BIN:-` 定位起点、
第一个顶格 `fi` 定位终点）**单独跑** ⇒ ⇒ 末尾一句 `REACHED-END`
⇒ ⇒ 出现 = 没提前中止。
⚠ ⚠ **这不是「改判据以求通过」**：是把行为级断言从**被别的门遮住**的层面
挪到**真正被测的那一层**（⇒ 断言问的还是同一个问题：「未验证会不会把后面带走」）。

⚠⚠⚨ **stdout / stderr 必须分开看**：契约门 log 的 `tail` 走 stdout
⇒ ⇒ 若合并看，契约门输出里的「把环境补齐后重跑」会**冒充**「走了 elif 支」。

⚠⚠⚨ **端到端实测（未变异）**：`ci.sh` rc = **3** 且 **16/16 步全部跑完**
（⇒ 改之前是 rc = **1**、`› 11/16`～`› 16/16` 全没跑）⇒ ⇒ **正向对照**成立。

⇒ ⇒ 累计 **1352/1352**（批 EB 的 1349 + 本批 3）。

**⑦ 数字**

· 门项条数 **1423 → 1430**（**四处同改**）；
· 执行次数 **1426 → 1433**；
· 恒真条件 **1045 → 1046**（+1 = 批 EC 段 trailer 的自指条件）；
· `ci.sh` 的 `exit [1-9]` **45 → 43**；`exit 3` 恰好 **1** 处；
· `ci.sh` 的未验证计数点：4 缩进 **6 → 7**、8 缩进 **2 → 3**（共 **10** 处）；
· 段级 trailer：`ARCH_ANY_FAIL=1` **75 → 76**、`ARCH_FAIL=0` **76 → 77**；
· 盘点登记册：`ci.sh` 失败上报 **5 → 3**、跳过提示 **10 → 12**、未验证逻辑出口 **1**（不变）
⇒ ⇒ 登记册**行数 21 不变**（只改两行的**处数与理由**）；
· 全量校验链 **14 步全绿**；审计器 rc=0、接线门 rc=0；
· ⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。

**⑧ 如实记着的已知边界**

· ⚠⚠⚨ **第 10 步「引擎缺席」那一支的可达性依赖环境** ——
本机 `moongit`/`deepgit` 在 `~/.local/bin`
⇒ ⇒ 「引擎缺席」只在**受限 PATH** 下可达
⇒ ⇒ **NC35 用了受限 PATH**（`PATH=/usr/bin:/bin`）⇒ 如实记着；
· ⚠⚠⚨ **契约门第 21 组（真 GitHub API）依赖网络** ⇒ ⇒ 本机实测**当时是限流（403）**
⇒ ⇒ 限流一过契约门就**通过**（120 passed）⇒ ⇒ elif 支**变得不可达**
⇒ ⇒ **NC34 用「不可达的代理」把它重新变成可达**（实测 rc = 3）
⇒ ⇒ ⚠ 这是**环境构造**，**不是**改判据；
· ⚠ **「真失败」那一支仍然当场 `exit 1`** ⇒ ⇒ 失败优先**不变**
⇒ ⇒ 但那意味着：**真失败在第 10 步发生时，第 11～16 步仍然不会跑**
⇒ ⇒ ⚠ 这是**设计意图**（失败优先），**如实记着**；
· ⚠ **「一次报全」只对「未验证」成立** ⇒ ⇒ 真失败仍是**当场中止** ⇒ 如实记着；
· ⚠ **本批不动 `contract-check.sh` / `build-deb.sh` / `smoke.sh`**
（它们自己的专属码 3 不变）。

### E.2cm 双跑覆盖面门不许把自己的结论建立在外部门的可达性上（批 ED）

**① 起因（实测，不是推演）**

批 DZ 留下的那条「**4 例附加断言间歇性不过 ⇒ 根因未定位 ⇒ 待查**」
—— 本批**定位到了**，而且真因**不是**负控环境抖动，是**判据层自己**的一个洞：

`ci-shell-parity.sh`（双跑覆盖面门）把被双跑的 `contract-check.sh` 跑**两遍**
（`sh` + `bash`）⇒ ⇒ 而 `contract-check.sh` 第 **21** 组要打**真 GitHub API**：

· API **打得到** ⇒ 那一组通过 ⇒ 整门退出码 **0**；
· API **打不到** ⇒ 那一组「未验证」⇒ 整门退出码 **3**。

⇒ ⇒ **同一份代码**，两遍的退出码就在 **0/3 之间摆**
⇒ ⇒ 外部网络在两遍之间**一翻转** ⇒ 双跑门**自造分叉** ⇒ ⇒ CI **间歇性假红**；
⇒ ⇒ 而且**误诊**：门把「外部依赖变了」归因成「**结论随执行 shell 变**」
⇒ ⇒ 读者被带去查错的地方（批 CE 纪律：诊断失真最贵）。

⚠⚠⚨ **这就是那 4 例间歇不过的根因**：批 DZ 那 4 例（NC14 / NC15 / NC18 / NC21）的
附加断言是「parity 输出里**没有**『这一组**没跑通**』」
⇒ ⇒ API 不可达时契约门 rc=3 ⇒ 输出里**就会**有「这一组**没跑通**」
⇒ ⇒ 断言**间歇性**不过 ⇒ ⇒ 与「跑负控时的环境」无关，是**判据层自己的输出不稳定**。

**② 行为坐实（实测）**

· 契约门：**可达** ⇒ rc = **0**（120 passed / 0 unverified）；
**不可达**（`https_proxy=http://127.0.0.1:9`）⇒ rc = **3**（118 passed / 1 unverified）
—— **同一份代码**，两次实测；
· `ci-shell-parity.sh` 的报告行把**退出码**与**措辞**一起写进输出：
rc=0 ⇒ 「判据**真的跑通**」；rc≠0 ⇒ 「这一组**没跑通**」
⇒ ⇒ **同一份代码几分钟内两句话不同**；
· 机制（100% 确定）：在 scratch 树里造一个「退出码随调用次数变化」的替身脚本
⇒ 双跑门 **rc=1**，报「**退出码不同** ⇒ 判据层的**结论随执行 shell 变**」
⇒ ⇒ **被双跑脚本的退出码因外部状态而变 ⇒ 双跑门就红** ⇒ ⇒ 且**误诊**。

**③ 修法（钉死外部依赖，而不是归一化结论）**

`ci-shell-parity.sh` 在**双跑循环之前**把外部依赖**钉死**：

· `http_proxy` / `https_proxy` / `all_proxy`（大小写两种）⇒ 全部指向
`http://127.0.0.1:9`（本机一个**没人监听**的端口 ⇒ 打过去**立刻被拒**，不是等 25 秒超时）；
· `no_proxy` ⇒ **显式收窄到本机**（`127.0.0.1,localhost,::1`）。

⚠ **只钉「出网」，不许钉「本机」**：契约门第 21 组会起一个**本地打桩服务器**
⇒ 代理**不许**把它一起吞掉 ⇒ ⇒ 否则「重试」那几条会变成「打桩服务器没起来」
⇒ ⇒ 覆盖面被**悄悄改窄**（批 DQ 教训：一条本该被登记的承诺从未生效）。
⚠ **实测**：钉死后契约门 rc = **3**（118 passed / **0 failed** / 1 unverified），
**本地打桩服务器照常起来**（重试那三条断言全 ✓）⇒ ⇒ 钉死**没有误伤**内部依赖。

⚠⚠⚨ **两处用途分离**（不许混为一谈）：

· **本脚本**（登记册的 `parity` 位置）= **覆盖面探针** ⇒ 只问「随 shell 变吗」
⇒ 外部依赖**钉死** ⇒ 这一处「打不到」是**故意**的；
· **`ci.sh` 第 10 步** = **真跑**契约门 ⇒ **必须真打真 API**
⇒ ⇒ 那里的网络**不许钉** ⇒ 两处结论**各自负责**。

⚠ **归因分档**：双跑门判「退出码不同」时，**先叫读者查外部依赖**（网络/时间/环境），
再谈「随 shell 变」⇒ ⇒ 钉死外部依赖后仍不同，才是真的「结论随执行 shell 变」。

**④ 连带改动**

· `deepin/scripts/ci-shell-parity.sh`：钉死块（9 行 export）+ 归因文案 1 处；
· `deepin/scripts/ci-wiring.sh`：原地替换 **3 条**门项（两条 trailer 计数 + 条数门项）
+ 批 ED 段新增 **7 条**；
· `deepin/scripts/ci-wiring-gates.baseline`：**1430 → 1437**；
· `deepin/scripts/ci-wiring-audit.py`：`GATE_LINES_EXPECTED` **1430 → 1437**。

⚠⚠⚨ **门项条数记四处**（批 CR 纪律；批 EB 实战确认要核**四处**）：
`ci-wiring.sh` 实数 / 基线文件 / 审计器常量 / 门项 3966 里的数字
—— 四处**全部 1437**。

⚠ **顺带订正两处已经陈旧的说明文字**（批 EA「文字不许撒谎」纪律的同款）：
门项 3916 的「清零 71 处 ⇒ 记红也必须 71 处」⇒ **77 处**（真值）；
门项 3917 的「1 处声明 + 75 处段末清零」⇒ **1 处声明 + 77 处段末清零**（真值）。

**⑤ 落门（批 ED 段 7 条）**

· 钉死的**地址常量**必须在（`http://127.0.0.1:9` ⇒ 立刻被拒，不是等超时）；
· `https_proxy` / `http_proxy` / `all_proxy` **三个都要钉**（只钉一个 = **只做了一半**）；
· `no_proxy` **必须显式收窄到本机**（不许把本地打桩服务器一起堵掉）；
· **跨行锚定**：钉死**必须紧挨着**双跑循环之前（钉在跑完之后 = 白钉）；
· 「退出码不同」那一支**必须先叫读者查外部依赖**。

**⑥ 负控（NC37 / NC38 / NC39）**

· **NC37**（形态级）**单行**删掉 `export https_proxy=...`
⇒ ⇒ **双断言**：接线门红（关键字「HTTPS 代理」）
⇒ ⇒ 证明「少钉一个变量」这种**最轻**的削弱也会被抓住；
· **NC38**（行为级）删掉**整块**钉死 ⇒ ⇒ 外部可达性在两遍之间**翻转**
⇒ ⇒ **双断言**：接线门红 **且** 双跑门红且红因是「**退出码不同**」
⇒ ⇒ 「自造分叉」坐实；
· **NC39**（正向对照·**不变异**）同一个替身在 PATH 上 ⇒ ⇒ 钉死生效
⇒ ⇒ 外部可达性**恒定** ⇒ ⇒ 双跑门必须**绿** ⇒ ⇒ 洞**已填**。

⚠⚠⚨ **替身要「忠实于代理语义」**：替身**真的去连**代理（连不上 ⇒ 失败，与真 curl 同款），
无代理时才用计数器模拟「第一次不通、第二次通」⇒ ⇒ **两边都是确定的**
⇒ ⇒ 断言不是「碰运气」。
⚠⚠⚨ **计数器必须复位**：接线门自己也会跑双跑门 ⇒ ⇒ 会推进计数 ⇒ ⇒ 不复位 ⇒ 翻转点漂移。

⚠⚠⚨ **本批把 harness 的判据改过两处**（判据写错，不是行为问题）：
① 变异锚点 `<DEL:...>` **末尾多带了一个 `>`** ⇒ ⇒ 锚点命中 0 处 ⇒ ⇒ 用例无效
⇒ ⇒ 改成 `<DEL:<frag>` **不带** `>`；
② ⚠ **新增了 `<DELBLOCK:起|止>` 变异**（删掉**一整段连续行**）⇒ ⇒ 钉死是**一整块** export
⇒ ⇒ 单行删不掉「整个钉死」⇒ ⇒ 行为级负控必须能把它**整块**拿掉。

**⑦ 数字**

· 门项条数 **1430 → 1437**（批 ED 段 **7 条**，**四处同改**）；
· 门项执行次数 **1433 → 1440**（+7）；
· 恒真探针条件 **1046 → 1047**（+1 = 批 ED 段 trailer 的自指条件）；
· 盘点登记册 **21 组 / 73 处不变**（新增文案**不含**盘点关键词）；
· 登记册 **11 行 = DUAL 10 + EXEMPT 1**（DUAL 里 7 条由双跑门双跑、**3 条**由 CI 入口双跑）；
· 双跑门汇总行仍是「登记册共 11 条 = 本脚本双跑 7 + CI 入口双跑 3 + 豁免 1」；
· 负控累计 **1352 → 1355**（批 EC 的 1352 + 本批 3）。

**⑧ 已知边界（如实记着）**

· ⚠ **CI 第 10 步的契约门仍会随网络在 rc 0/3 之间摆** ⇒ ⇒ 那是**真跑**的**诚实**结果
（rc=3 = 「未验证」，分诊表会说对）⇒ ⇒ 与双跑门的「自造分叉」**不是同一件事**；
· ⚠ **`ci-shell-parity.sh` 还没进「整行锚定」的适用范围**（`ANCHOR_SCOPE_SUFFIXES`）
⇒ ⇒ 它的门项有 5 条是「盯串」形态 ⇒ ⇒ 属**另一批**的活（如实记着）；
· ⚠ **钉死靠的是「工具认代理变量」**（`curl` / Qt 的 `QNetworkAccessManager` 都认）
⇒ ⇒ 若将来有判据脚本**绕过**代理直连 ⇒ ⇒ 钉死对它**无效**（如实记着）；
· ⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。
### E.2cn 双跑覆盖面门的判定行与 fail-closed 出口必须逐个有牙（批 EE）

**① 起因（实测，不是推演）**

批 ED 收尾时如实记着一条已知边界：

> ⚠ `ci-shell-parity.sh` 还没进「整行锚定」的适用范围（`ANCHOR_SCOPE_SUFFIXES`）
> ⇒ ⇒ 它的门项有 5 条是「盯串」形态 ⇒ ⇒ 属**另一批**的活（如实记着）

本批就是那个「另一批」。勘察脚本**逐行普查** `deepin/scripts/ci-shell-parity.sh` 得出：

· 这个文件有 **12 处**「拒绝继续」的出口（`exit 1`）**+ 7 处**判定行；
· 而**门只看着其中 2 处** ⇒ ⇒ 其余的**改了没人报**。

⚠⚠⚨ **三类洞**：

① **fail closed 变 fail open**：12 个出口里**只有 1 个**被钉住
（批 EA 的递归保护那处）⇒ ⇒ 其余 **11 处**把 `exit 1` 改成 `exit 0`
⇒ **拒绝继续**变成**继续跑** ⇒ 门**全绿** ⇒ ⇒ 承诺**悄悄变弱**；

② **判定被掏空但串还在**：只钉**提示文案**的门 ⇒ 把判定条件改掉、文案留着
⇒ 门照样绿（批 BQ 纪律）⇒ ⇒ 「判定不许被掏空」这条承诺**没落地**；

③ **覆盖洞**：「DUAL 条目必须写理由」那一支**一条门都没有**
⇒ 把整支删掉（**含提示**）⇒ **没有任何门红**
⇒ 而它的兄弟（EXEMPT 那一支）**有线** ⇒ ⇒ 同一个承诺**一半有牙一半没牙**。

⚠ **附带洞**：`ci-shell-parity.sh` **不在**「整行锚定」的适用范围
⇒ ⇒ 它上面 **30 条已经整行锚定**的门项**不受审计器守护**
⇒ ⇒ 放松成「盯串」**不必登记豁免** ⇒ ⇒ 承诺**悄悄变弱**。

**② 修法**

· **判定行逐条整行锚定**（7 处）—— 靠**缩进**区分同一段文本的两处判定
（EXEMPT 支 8 空格 / DUAL 支 4 空格 ⇒ ⇒ 两者**文本完全相同**）；
· **fail-closed 出口两条腿**：① **总量门**（恰好 **12** 处 `exit 1`）
② **forbid 门**（**一处都不许有** `exit 0`）⇒ ⇒ 一条盯数量、一条盯取值 ⇒ ⇒ 互补；
· **DUAL 提示行**也钉住（与 EXEMPT 那一支**对称**）⇒ ⇒ 读者看到的东西**一致**；
· `ANCHOR_SCOPE_SUFFIXES` **+= `ci-shell-parity.sh`**（17 → **18** 个后缀）
⇒ ⇒ 它那 **30 条已整行锚定**的门项**从此受审计器守护**；
· 那 **6 条**「盯串」门项**逐条登记豁免**（`ci-wiring-anchor.exempt`）
⇒ ⇒ 豁免表 ≡「非锚定门项」集合 ⇒ ⇒ **双向配准** ⇒ 条数是**推导出来的**。

**③ 落门（批 EE 段 10 条）**

· 出口**总量门**：`^[[:space:]]*exit 1$` 恰好 **12** 处
（⚠ 12 处分属 **4 / 8 / 12 / 16** 四种缩进 ⇒ ⇒ 正则**必须缩进不敏感**
⇒ ⇒ 固定某一档只能命中 8 处 ⇒ ⇒ 门会**恒红** ⇒ ⇒ 这是落盘时踩到并改正的一处）；
· **7 条判定行**：EXEMPT 分支入口 / EXEMPT 的理由 / 只许 DUAL 或 EXEMPT /
**DUAL 的理由（★覆盖洞）** / 只许 parity 或 ci.sh / 递归保护 / 脚本读不了；
· **DUAL 提示行** 1 条；
· **forbid 门**：`exit 0` **一处都不许有**。

**④ 连带改动**

· `deepin/scripts/ci-wiring-audit.py`：`ANCHOR_SCOPE_SUFFIXES` **+= 1 个后缀**
+ `GATE_LINES_EXPECTED` **1437 → 1447**；
· `deepin/scripts/ci-wiring.sh`：批 EE 段新增 **10 条**
+ 原地替换 **3 条**（两条段级 trailer 计数 + 条数门项）；
· `deepin/scripts/ci-wiring-gates.baseline`：**1437 → 1447**；
· `deepin/scripts/ci-wiring-anchor.exempt`：**14 → 20 条**（新增 6 条，逐条写理由）。

⚠⚠⚨ **门项条数记四处**（批 CR 纪律；批 EB 实战确认要核**四处**）：
`ci-wiring.sh` 实数 / 基线文件 / 审计器常量 / 门项 3966 里的数字
—— 四处**全部 1447**。

**⑤ 数字（全部实测）**

· 门项条数 **1437 → 1447**（批 EE 段 **10 条**，**四处同改**）；
· 门项执行次数 **1440 → 1450**（+10）；
· 恒真探针条件 **1047 → 1048**（+1 = 批 EE 段 trailer 的自指条件）；
· 段级 trailer：`ARCH_ANY_FAIL=1` **77 → 78**、`ARCH_FAIL=0` **78 → 79**；
· 盘点登记册 **21 组 / 73 处不变**（新增文案**不含**盘点关键词）；
· 锚定豁免表 **14 → 20 条**（**推导出来的**，不另写条数基线）。

**⑥ 负控（NC40 / NC41 / NC42 / NC43）**

· **NC40**（形态级）把 **EXEMPT 支的「理由」判定行**掏空（条件换成恒不成立）
⇒ ⇒ **双断言**：接线门红 **且** 红的是**那一条**判定行门项
⇒ ⇒ 「判定被掏空但提示串还在」这个洞**被抓住**；
· **NC41**（形态级）把**一处** `exit 1` 改成 `exit 0`
⇒ ⇒ **双断言**：① 出口**总量门**红（12 → 11）**且** ② **forbid 门**红
⇒ ⇒ **两条腿互补**都验到了；
· **NC42**（形态级 · **覆盖洞**）把 **DUAL 支整支删掉**
（判定行 + 提示行 + 出口 + `fi`）⇒ ⇒ 必须红 ⇒ ⇒ 洞**已填**；
· **NC43**（正向对照 · **不变异**）⇒ ⇒ 接线门必须**绿**
⇒ ⇒ 顺带证：forbid 门在**干净文件**上命中 0 ⇒ ⇒ 「一条都不许有 `exit 0`」**不是恒红**。

⚠⚠⚨ **本批把 harness 的判据改过两处**（**判据写错**，不是行为问题）：
① NC40 原用 `<DELFULL:` **删掉**判定行 ⇒ ⇒ `if` 没了、`fi` 还在 ⇒ ⇒ **语法被破坏**
⇒ ⇒ harness 的**语法自证**当场拦下 ⇒ ⇒ 用例无效
⇒ ⇒ 改成「**替换**条件」⇒ ⇒ 语法仍合法 ⇒ ⇒ 测的才是「判定被掏空」这件事；
② NC41 原用 `if` 行当 `<X2:>` 起锚 ⇒ ⇒ 但 `exit 1` 与它之间**隔着一条 echo**
⇒ ⇒ `<X2:>` 只看「起锚行的**下一行**」⇒ ⇒ 命中 0 处 ⇒ ⇒ 用例无效
⇒ ⇒ 改用**那条 echo 行**当起锚（从文件**提取** ⇒ 零手打汉字）。

⚠ **harness 顺手加了两个变异原语**（内容锚定 ⇒ 零手打汉字）：
`<DELFULL:`（删掉**整行精确相等**的那一行）、
`<DELBLOCKFULL:`（删掉**整行精确相等**的起锚行 … 止锚行）
⇒ ⇒ 动机：EXEMPT 支与 DUAL 支的「理由」判定行**文本完全相同**（只有缩进不同）
⇒ ⇒ **子串锚点分不开** ⇒ 必须按「整行相等」定位。

**⑦ 已知边界（如实记着）**

· ⚠ **6 条「盯串」门项仍然只盯文案措辞** ⇒ ⇒ 它们**显式豁免**了整行锚定
⇒ ⇒ 理由逐条写明「盯的是**文案措辞**，判定行已由批 EE 的新门**单独守住**」
⇒ ⇒ 这是**有意保留的两层**，不是漏网；
· ⚠ **出口总量门盯的是「有几处 `exit 1`」** ⇒ ⇒ 出口**挪位置**（改缩进）**不红**
⇒ ⇒ 但那条 forbid 门与 7 条判定行门**仍然**盯着取值 ⇒ ⇒ 缩进挪动**不会**让判定消失；
· ⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。

### E.2co 段级 trailer 的「本段红了 ⇒ 报红并记全局红过」这条判定必须被钉住（批 EF）

**① 起因（实测，不是推演）**

批 EE 收尾时如实记着一条已知边界：

> ⚠ **出口那条线批 EE 已基本闭合** ⇒ ⇒ 剩下的洞在**判定行**

本批就是那条线。先做**通用普查**（全判据层 **19** 个脚本，逐行分类
「这条判定行有没有门在盯」）：

· **判定行 427 条** —— A（整行锚定钉住）**76** / B（只被盯串门提到）**4**
/ C（**没人提**）**347**；
· **出口 139 条** —— A **128** / C **11** ⇒ ⇒ 那 **11** 条多是 `exit 0` / `exit 2`
⇒ ⇒ **不是 fail-closed** ⇒ ⇒ **出口那条线基本闭合**。

⇒ ⇒ 洞集中在**判定行**。而**判据层自己**（`ci-wiring.sh`）的段级 trailer
就是其中最要命的一类。

**② 洞（实测坐实）**

`ci-wiring.sh` 的段级 trailer 结构是：

```
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：…段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ …段门项全绿（…）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0
```

⚠⚠⚨ **这条「本段红了 ⇒ 报红 ⇒ 记全局红过 ⇒ 说清楚 ⇒ 清零」的判定，
它本身一条门都没有**：

· 钉住的是**每一段的提示文案**（`echo` 那几行）⇒ ⇒ **判定行不在门的射程内**；
· 78 个 trailer **结构完全同形**（75 个现代同措辞 + 3 个早期异形）⇒ ⇒
改其中**任何一处**，**那些盯文案的门全部照旧绿**。

⇒ ⇒ **把判定掏空**（`if [ "$ARCH_FAIL" -ne 0 ]` 改成恒不成立）
⇒ ⇒ 那几行**文本还在** ⇒ ⇒ 门**全绿**
⇒ ⇒ 而运行时**该段的红**再也不会被记到 `ARCH_ANY_FAIL`
⇒ ⇒ **末尾统一判红看不见** ⇒ ⇒ **假绿**。

**③ 决定性实验（修前证据，scratch 树）**

| # | 变异 | 接线门 rc | 结论 |
|---|---|---|---|
| ① | 该段真红 + 判定**完好** | **1** | 红 ✓ |
| ② | 同上 + 掏空 trailer 判定（`-ne 0` → **`-ne 1` 反相**） | **0** | ⚠⚠⚨ **假绿坐实** |
| ③ | 只掏空判定（本来就没红） | **1** | 该段**误报红** |

⚠⚠⚨ ② ③ 的对照说明：**同一份代码、同一处真实失败 ⇒ 只差那一处判定
⇒ ⇒ 门从红变绿** ⇒ ⇒ 洞**坐实**（不是推演）。

⚠⚠⚨ **本批第一次的变异写错了**（**判据写错**，不是行为问题）：
用 `-ne 999` ⇒ `ARCH_FAIL` 只取 **0/1** ⇒ 该条件**恒真** ⇒ 每次都走红支
⇒ 门**恒红** ⇒ ⇒ 验的是**反过来的事** ⇒ ⇒ **该例无效**
⇒ ⇒ 改成**反相** `-ne 1` 才成立。

**④ 修法**

· **新增门型 `arch_need_count_ml`**（跨行、恰好 N 次）
⇒ ⇒ 口径 = **剥注释** + `tr '\n' ' '` + `grep -oE` + `grep -c .`
⇒ ⇒ 与 `arch_need_ml` **完全同口径** ⇒ ⇒ **门侧与审计侧同口径**；
· **落门 2 条**（批 EF 段）：

  ① `arch_need_count` **判定行**逐字钉住
  `^if \[ "\$ARCH_FAIL" -ne 0 \]; then$` 恰好 **79** 处
  （78 个原有 + 本批新增段自己那处）；

  ② `arch_need_count_ml` **整块结构**钉住（判定 ⇒ 报红 `>&2`
  ⇒ `ARCH_ANY_FAIL=1` ⇒ `else` ⇒ 说清楚 ⇒ `fi` ⇒ `ARCH_FAIL=0`）
  恰好 **79** 处 ⇒ ⇒ 用 `[[:space:]]+` 保证 **token 相邻**
  （不是「这行在文件里出现过」）。

· ⚠ **78 个 trailer 结构完全同形** ⇒ ⇒ **一条跨行正则全覆盖**
（措辞不同由 `[^"]*` 吸收）；
· **审计器三处登记**（批 BH～BR 纪律）：解析正则 `COUNT_ML_LINE`
+ `GATE_TYPES` 加 `('need_count_ml', COUNT_ML_LINE)`
+ `RX_ARG_IDX['arch_need_count_ml'] = 1`；
· **期望校准** `check_count_ml_gates()`（用 `count_hits_ml`）
+ `check_label_count_text(cnt + cntml)`（说明文字里的「恰好 N 处」
必须等于期望值 ⇒ 文字不许撒谎）；
· `FAIL_GUARDS` 加 `'cntmlbad'` ⇒ ⇒ 否则审计器 **rc=2「自己有盲区」**。

⚠⚠⚨ **落盘时踩到并当场修的一处**：审计器有一条门项**盯着 `FAIL_GUARDS`
那一行的整行字面量** ⇒ 登记册从 **26** 项变 **27** 项 ⇒ 那条门项的正则
**必须同步**（插入 `.cntmlbad.`）⇒ ⇒ 否则审计器 **rc=4「次数门没配准」**
⇒ ⇒ 而且那条门项属 `arch_need_count` ⇒ ⇒ 在**整行锚定**适用范围内
⇒ ⇒ 改它会牵动期望值校准（仍应为 1）⇒ ⇒ 改完必须复跑审计器。

**⑤ 负控（NC44 / NC45 / NC46 / NC47）**

· **NC44**（形态级）把**一处** trailer 的**判定行掏空**
（`-ne 0` ⇒ **`-ne 1` 反相**）
⇒ ⇒ **三断言**：判定行门项红 **且** 跨行门项红 **且**
**末尾统一判红出现**（⇒ ⇒ 改完之后该段的红**确实被记到了全局**）；
· **NC45**（形态级 · **本批核心**）把 `ARCH_ANY_FAIL=1` 与报红那行
**交换顺序**（**仍在 `if` 体内** ⇒ ⇒ **判定逻辑与输出逐字节不变**）
⇒ ⇒ **双断言**：跨行门项**红** **且** 判定行门项**没有红行**
⇒ ⇒ **证明「单行门盯不住跨行关系 ⇒ 跨行门不是冗余」**
（这一例的**行为完全没变**，只有**跨行顺序**变了）；
· **NC46**（形态级 · **假绿的精确形态**）把 `ARCH_ANY_FAIL=1` **整行删掉**
⇒ ⇒ 报红**还在**（文本没动）⇒ ⇒ 但**记全局红过**没了
⇒ ⇒ **双断言**：跨行门项**红** **且** 判定行门项**没有红行**
⇒ ⇒ **证明「判定行还在」不等于「记红还在」**；
· **NC47**（**正向对照** · 不变异）⇒ ⇒ 接线门必须**绿**
⇒ ⇒ 顺带证：跨行门在**干净文件**上命中 **79** ⇒ ⇒
「恰好 79 次」**不是恒红**。

⚠⚠⚨ **本批把 harness 的判据改过三处**（**判据写错**，不是行为问题）：

① 新增的 `<IDX:` 变异原语**分段少切了一位**（`old[5:]` ⇒ 首段是空串）
⇒ ⇒ `int('')` ⇒ 崩 ⇒ ⇒ 改成 `old[6:]`；
② `gate-mix:` 断言的**末段**被当成「全局片段」吃掉
⇒ ⇒ 「判定行门项绿」那条断言**根本没跑** ⇒ ⇒ 改成用 `global:` 前缀
**显式标注**全局片段；
③ ⚠⚠⚨ **全量回归跑出两例假红**（**NC30 / NC33**）⇒ ⇒ 它们的断言
**硬编码了行号** `ci-wiring.sh:3943` ⇒ ⇒ 而本批给 `ci-wiring.sh` **加了行**
⇒ ⇒ 行号漂到 **3972** ⇒ ⇒ **判据写错**（不是行为问题）
⇒ ⇒ 改成**从仓内文件实时算**（零手打汉字 ⇒ ⇒ **永不再漂**）
⇒ ⇒ 复跑两例 ⇒ ⇒ **真红** ⇒ ⇒ 累计 **47/47 真红**。

⚠ **harness 顺手加了两个原语**（内容/位置锚定 ⇒ 零手打汉字）：
`<IDX:idx|op|arg>`（按**行号**定位：`ARCH_ANY_FAIL=1` 在 `ci-wiring.sh` 里有
**79 处** ⇒ ⇒ **任何子串锚点都分不开** ⇒ ⇒ 必须带位置）、
`gate-mix:`（**分别**断言每一条门项的**红 / 绿** ⇒ ⇒ 批 EF 的核心就是
「**单行门抓不住、跨行门能抓住**」⇒ ⇒ 只看整体 rc 不够）。

**⑥ 数字（全部实测）**

· 门项条数 **1447 → 1449**（**四处同改**：基线文件 / 审计器常量
`GATE_LINES_EXPECTED` / `ci-wiring.sh` 里那条门项的数字 / 实数）；
· 门项执行次数 **1450 → 1452**（+2）；
· 恒真探针 shell+python 条件 **1048 → 1056**（+8 = 本批新增的 8 个条件句）；
· 段级 trailer：`ARCH_ANY_FAIL=1` **78 → 79**、`ARCH_FAIL=0` **79 → 80**、
`ARCH_FAIL=1` **41 → 43**（新门型函数里 **2** 处）；
· 门型注册表 **15 → 16**；`FAILS.append(9)` **6 → 7**；
· 盘点登记册 `TRUE_AUDIT_EXPECTED_ROWS` **33 → 34**；
· 盘点 **21 组 / 73 处不变**；锚定豁免表 **20 条不变**；
· 负控累计 **1359 → 1363**（批 EE 的 1359 + 本批 4）。

**⑦ 已知边界（如实记着）**

· ⚠ **跨行门盯的是「形状」不是「措辞」** ⇒ ⇒ 某段 trailer 的**措辞**
被改（但结构没变）⇒ ⇒ 跨行门**照旧绿** ⇒ ⇒ 这是**有意的**：
78 个 trailer 措辞本就各不相同 ⇒ ⇒ 逐字钉死会**误报**；
· ⚠ **跨行门是计数门** ⇒ ⇒ 某处塌了、另一处补上 ⇒ ⇒ 命中数不变 ⇒ ⇒ 绿
⇒ ⇒ 但**判定行门是逐字的** ⇒ ⇒ 补上的那处字面不同 ⇒ ⇒ 红
⇒ ⇒ **两条腿互补**；
· ⚠ **`FAIL_GUARDS` 那条门项的正则必须与登记册**逐字**同步**
⇒ ⇒ 登记册加一项 ⇒ 那条门项就得改 ⇒ ⇒ 改它会牵动期望值校准
⇒ ⇒ 这是「**条数记三遍**」纪律的又一个实例；
· ⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。

### E.2cp 契约门两个断言助手的「判定体」必须被钉住（批 EG）

**① 起因（实测，不是推演）**

批 EF 收尾时如实记着一条已知边界：

> ⚠ **出口那条线批 EE 已基本闭合** ⇒ ⇒ 剩下的洞在**判定行**
> ⇒ ⇒ 普查：判定行 **430** 条里 **C 类（没人提）271**

本批接着这条线。普查按文件分布，**最集中的是契约门** `contract-check.sh`：

· 它有 **61 条**判定行，而被**整行锚定**门项钉住的只有 **2 条**；
· 全文件 **99 处断言**（`check` **93** + `check_text` **6**）。

⚠⚠⚨ 但**最要命的不是那 61 条**，而是**两个断言助手**：

```
check() { # check <名称> <python表达式> [json]
    ...
    if printf '%s' "$json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if ($expr) else 1)
" 2>/dev/null; then
        echo "  ✓ $name"; pass=$((pass+1))
    else
        echo "  ✗ $name"; fail=$((fail+1))
    fi
}

check_text() { # check_text <名称> <ERE> <文本>
    ...
    if printf '%s' "$text" | grep -qE "$ere"; then
```

⇒ ⇒ **99 处断言全部压在这两个助手的判定体上**
⇒ ⇒ 而这两个判定体**一条门都没有**：
门只钉住了**调用点数**（93）/ **失败计数行**（2 / 31 / 4 / 2 / 39 / 40）/
**末尾判定**（`[ "$fail" -eq 0 ]`）/ **skip 计数**（4 / 7 / 3）/ `exit 3`
⇒ ⇒ 「**断言清单不许被删**」有牙，「**断言到底有没有真跑**」**没人守**。

**② 决定性实验（修前证据，scratch 树 + 真引擎）**

契约门在本机**真能跑**（引擎 `moongit` 在场 ⇒ `120 passed, 0 failed, 0 unverified`，rc=0）。

| # | 变异 | 契约门 rc | 契约门汇总 |
|---|---|---|---|
| ① | 基线（不改） | **0** | 120 passed, 0 failed |
| ② | 一条断言改成**必假** + 判定**完好** | **1** | 119 passed, **1 failed** |
| ③ | 同上 + 判定**被掏空**（`sys.exit(0 if ($expr) else 1)` → `sys.exit(0)`） | **0** | **120 passed, 0 failed** |
| ④ | 只掏空判定（不动任何断言） | **0** | 120 passed, 0 failed |

⚠⚠⚨ ②③ 的对照说明：**同一份代码、同一处真实失败 ⇒ 只差那一处判定
⇒ ⇒ 门从红变绿** ⇒ ⇒ **假绿坐实**。
④ 说明：**99 处断言一条都没真跑**却全报 ✓
⇒ ⇒ 判定体就是全部断言的**唯一承重墙**。

⚠⚠⚨ 而且 ①②③④ **接线门全都绿** ⇒ ⇒ 判据层对这个洞**完全不可见**。

**③ 修法**

· **落门 3 条**（批 EG 段）：

  ① `arch_need_count` —— `check()` 的**判定行**整行锚定（恰好 **1** 处）；
  ② `arch_need_count` —— `check_text()` 的**判定行**整行锚定（恰好 **1** 处）；
  ③ `arch_need_count_ml` —— `check()` 的**判定体**（判定行 ⇒ python 语义行
  ⇒ ⇒ **紧挨**）恰好 **1** 处。

· ⚠ **门项③是关键**：判定体里那行 `sys.exit(0 if ($expr) else 1)`
  在**另一行**上 ⇒ ⇒ 门项①（钉 `if` 那行）**抓不住**它
  ⇒ ⇒ 必须用**跨行**门把「判定行 ⇒ python 语义行」**紧挨**着钉住
  ⇒ ⇒ 正好用**批 EF 新增的门型** `arch_need_count_ml`
  ⇒ ⇒ 判据只有一份 ⇒ ⇒ 门侧与审计侧**同口径**；
· ⚠ **门项正则里不许有单引号** ⇒ `printf '%s'` 的两个引号用 `.` 匹配
  （与 `FAIL_GUARDS` 那条门项同款写法）⇒ ⇒ 字面竖线写 `[|]`（**不写 `\|`**）；
· ⚠ **审计器不用改**（`arch_need_count_ml` 批 EF 已登记）⇒ ⇒ 只同步条数。

⚠⚠⚨ **本批的「自指陷阱」（当场处理）**：新增一段 ⇒ ⇒ **段级 trailer 多 1 处**
⇒ ⇒ 批 EF 的两条 trailer 门项期望值 **79 → 80**、`ARCH_ANY_FAIL=1` **79 → 80**、
`ARCH_FAIL=0` **80 → 81** ⇒ ⇒ **说明文字里的同一个数字也要一起改**
⇒ ⇒ 否则审计器的「期望校准」当场报「**文字在骗人**」。

**④ 负控（NC48 / NC49 / NC50 / NC51）**

· **NC48**（形态级）把 `check()` 的**判定体**掏空
（`sys.exit(0 if ($expr) else 1)` → `sys.exit(0)`）
⇒ ⇒ **双断言**：跨行门项**红** **且** `check()` 的**判定行门项没有红行**
⇒ ⇒ **证明「整行门盯不住跨行语义 ⇒ 跨行门不是冗余」**；
· **NC49**（形态级）把 `check()` 的**判定行**改掉
（`python3 -c "` → `python3 -c "import sys; `）
⇒ ⇒ ⚠ **行为完全不变**（契约门仍 120 passed）⇒ ⇒ 但**判定行的字面**变了
⇒ ⇒ **双断言**：判定行门项红 **且** 跨行门项红
⇒ ⇒ 也证明「**整行锚定门强于盯串门**」：连**行为没变**的字面改动都抓住；
· **NC50**（形态级）把 `check_text()` 的**判定行**改掉
（`grep -qE "$ere"` → `grep -qE ""` ⇒ 匹配任何东西 ⇒ 恒真）
⇒ ⇒ **双断言**：`check_text()` 的判定行门项红 **且** **跨行门项仍然绿**
⇒ ⇒ 证明**两条门各管各的**（跨行门盯的是 `check()`，不是 `check_text()`）
⇒ ⇒ 不是同一条门顶两次；
· **NC51**（**正向对照** · 不变异）⇒ ⇒ 接线门**绿** **且** 契约门**绿**（120 passed）
⇒ ⇒ 「改完之后行为确实对了」的那一半。

⚠⚠⚨ **本批把 harness 的判据改过两次**（**判据写错**，不是行为问题）：

① NC49 最初用「`python3 -c "` → `python3 -c "# "`」当变异
⇒ ⇒ 那会把多行 python 代码的**引号配平**打破
⇒ ⇒ shell 在 `sys.exit(0 if ($expr) else 1)` 那行报
「Syntax error: "(" unexpected」
⇒ ⇒ harness 的**语法自证**当场拦下 ⇒ ⇒ 用例无效
⇒ ⇒ 改成「多一行合法的 python 导入」（`import sys; `）⇒ ⇒ 语法合法
⇒ ⇒ 且**行为完全不变** ⇒ ⇒ 反而更能证明「整行锚定门强于盯串门」；

② ⚠⚠⚨ **新加的 `contract-green` 那条附加断言**一开始**根本没跑**
⇒ ⇒ 原因：它被塞在 `elif extra in (...)` 的**内层**
⇒ ⇒ 而它**不在**那个分派元组里 ⇒ ⇒ **外层不匹配** ⇒ ⇒ **内层永远到不了**
⇒ ⇒ NC51 照样「真红」⇒ ⇒ 但它验的只是**接线门绿**
⇒ ⇒ **契约门绿**那条断言**一次都没执行** ⇒ ⇒ **该例无效**
⇒ ⇒ 把它**加进分派元组** ⇒ ⇒ 复跑 ⇒ ⇒ 契约门 rc=0 + 汇总行
「120 passed, 0 failed, 0 unverified」⇒ ⇒ 断言这才**真的**跑了。
⇒ ⇒ 教训（与批 EB「报告模式那个出口没人守」同源）：
**新增一个附加断言档 ⇒ ⇒ 必须确认它**进得了分派链** ⇒ ⇒
否则「用例通过」是**假通过**。

⚠ **harness 顺手加了两个原语**：
`gate-eg:`（**分别**断言每一条门项的**红 / 绿**；语法 `<state>:<片段>`
⇒ ⚠ 不用 `gate-mix:` 的 `<片段>=<state>` ⇒ 因为批 EG 的两条判定行门项片段里
**没有** `=`，而跨行门项的片段里**有**（`d = json.load`）⇒ ⇒ 两种都得支持）
与 `contract` 检查档（正向对照里**再跑一次契约门本体** ⇒ ⇒ 引擎在场 ⇒ 真跑 120 条断言）。

**⑤ 数字（全部实测）**

· 门项条数 **1449 → 1452**（**四处同改**）；
· 门项执行次数 **1452 → 1455**（+3）；
· 恒真探针 shell+python 条件 **1056 → 1057**（+1 = 批 EG 段 trailer 的自指条件）；
· 段级 trailer：`ARCH_ANY_FAIL=1` **79 → 80**、`ARCH_FAIL=0` **80 → 81**；
· 批 EF 的两条 trailer 门项 **79 → 80**（**自指**）；
⚠ **批 EF 块里那句「跨行门在**干净文件**上命中 **79**」是**批 EF 当时的实测值**；本批新增段 ⇒ ⇒ **自指 +1** ⇒ ⇒ 现为 **80**。
· 门型注册表 **16 不变**、`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、
盘点登记册 **34 不变**、盘点 **21 组 / 73 处不变**、豁免表 **20 条不变**；
· 负控 **47 → 51**。

**⑥ 已知边界（如实记着）**

· ⚠ **契约门那 61 条判定行里还有 59 条没人逐条钉**
⇒ ⇒ 本批只钉住了**两个助手的判定体**（承重墙）
⇒ ⇒ 其余的多为 `if [ -z "$X" ]`（取数失败 ⇒ 走 SKIP 支）
⇒ ⇒ 它们的**兜底**是 `skip` 计数器 + 末尾 `exit 3`（批 CI 已钉）
⇒ ⇒ 但**逐条**仍没人钉 ⇒ ⇒ 属**另一批**的活；
· ⚠ **跨行门盯的是「形状」** ⇒ ⇒ python 那几行的**措辞**变了（结构没变）⇒ ⇒ 照旧绿
⇒ ⇒ 这是**有意的**（结构才是承重墙）；
· ⚠ **判定行门（整行锚定）比「盯串」门严** ⇒ ⇒ 连**行为没变**的字面改动都红
⇒ ⇒ 这是**有意的**（批 BQ / BR 纪律）；
· ⚠ 契约门本机能跑是因为**引擎在场** ⇒ ⇒ 换一台没引擎的机器 ⇒ ⇒ 契约门 rc=3（未验证）
⇒ ⇒ 但本批的门**不依赖**引擎（判据层自己跑得动）⇒ ⇒ **不受**这个影响；
· ⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。

### E.2cq CI 入口第 7 步 verify 接线门的「承重墙」必须被钉住（批 EH）

**① 起因（实测，不是推演）**

批 EG 收尾如实记着一条已知边界：

> ⚠ **契约门那 61 条判定行里还有 59 条没人逐条钉** ⇒ ⇒ 属**另一批**的活

本批接着「**判定行**」这条线，但把靶子从**契约门**转到 **CI 入口本身** ——
`ci.sh` 第 7 步的 **verify 接线门**。

那一步用**一个助手** `wire_need()` 干 6 件事：

```
wire_need() { # wire_need <文件> <正则> <说明>
    local f="$1" re="$2" label="$3"
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        WIRING_FAIL=1
        return
    fi
    if strip_comments "$f" | grep -E -- "$re" >/dev/null; then     # ← 判定行
        echo "  ✓ $label"
        WIRING_HITS=$((WIRING_HITS + 1))
    else
        echo "  ✗ $label：$f 里找不到 $re" >&2
        WIRING_FAIL=1
    fi
}
wire_need "$SRC/src/app/AppModel.cpp" …                            # ← 6 处调用点
…
if [ "$WIRING_FAIL" -ne 0 ]; then                                    # ← 汇总判定
    echo "✗ verify 接线门失败：判定层或接线被摘掉（撤入口 ≠ 撤能力）" >&2
    exit 1
fi
echo "✓ verify 接线完整（$WIRING_HITS 项）"
```

⇒ ⇒ 它的**承重墙**是 4 处：**判定行** / **判定体**（记 `WIRING_HITS` 与
`WIRING_FAIL=1` 的那两行）/ **失败计数**（2 处）/ **汇总判定**，
外加 **6 处调用点**。

⚠⚠⚨ 逐条核过（口径是「**整行锚定是否匹配该行**」，不是「串是否被提到」）：

| 承重墙 | 整行锚定门项 | 盯串门项 | 结论 |
|---|---|---|---|
| `wire_need` 定义行 | 0 | 0 | **没人提** |
| 文件存在分支 | 0 | 0 | **没人提** |
| **判定行** | **0** | **0** | **没人提** |
| `WIRING_HITS` 递增行 | 0 | 0 | **没人提** |
| **失败计数**（2 处） | **0** | **0** | **没人提** |
| **汇总判定** | **0** | **0** | **没人提** |

⇒ ⇒ `ci.sh` 上共 **141** 个门项，但这条承诺**只守了 1/6 个调用点**
（门项 2295 只钉了 `AppModel.cpp` 那处）⇒ ⇒ 洞对判据层**完全不可见**。

**② 决定性实验（修前证据，scratch 树）**

⚠ **为什么只抽第 7 步单独跑**（批 EC 纪律的同款应用）：
变异会让接线门自己红 ⇒ ⇒ 整个 `ci.sh` 第 9 步就中止
⇒ ⇒ 「第 8 步没出现」**恒成立** ⇒ ⇒ 那条断言**恒真** ⇒ ⇒ **无信息量**。

抽取方式：`WIRING_HITS=0`（步首）→ 最后一个含 `WIRING_HITS` 的行（步尾）；
`strip_comments` 从 `ci-wiring.sh` **抽取**（单一真相源）。

| # | 变异 | 第 7 步 rc | 第 7 步结论 |
|---|---|---|---|
| ① | 基线（不改） | **0** | ✓ verify 接线完整（6 项） |
| ② | 判定**完好** + 摘掉一处真实接线（`addWidget(buildIntegrityCard())`） | **1** | ✗ 详情页挂了文档完整性卡 ⇒ **真断言抓住了** |
| ③ | **判定被掏空**（`$re` → `""` ⇒ `grep -E -- ""` 匹配一切）+ 同样摘掉接线 | **0** | ✓ verify 接线完整（6 项）⇒ ⚠⚠⚨ **假绿坐实** |
| ④ | **失败计数被摘**（✗ 支的 `WIRING_FAIL=1` → `0`）+ 同样摘掉接线 | **0** | ✓ verify 接线完整（**5** 项）⇒ ⚠⚠⚨ **假绿坐实** |

⚠⚠⚨ ③ ④ 的形态值得单独记：

* ③ —— `grep -E -- ""` **匹配一切** ⇒ 6 处**恒真** ⇒ 第 7 步**恒报「✓ 接线完整」**；
* ④ —— **✗ 打了**（日志里看得到「✗ 详情页挂了文档完整性卡」），
  但 **CI 不红**，而且结论还打「✓ verify 接线完整（5 项）」⇒ ⇒ **最阴的一种**。

⚠⚠⚨ 而且 ①②③④ **判据层全绿**（接线门 rc=0 ／ 恒真探针 rc=0 ／ 审计器 rc=0）
⇒ ⇒ 这个洞对判据层**完全不可见**。四例的**洁净度**全部为
「与原始字节逐字节相同」。

**③ 修法（落门 5 条，批 EH 段）**

| # | 门型 | 盯什么 | 期望 |
|---|---|---|---|
| ① | `arch_need_count` | `wire_need` 的**判定行**（整行锚定） | 恰好 **1** 处 |
| ② | `arch_need_count_ml` | `wire_need` 的**判定体**（判定行 ⇒ ✓ 支 ⇒ ✗ 支 ⇒ 失败计数 ⇒ fi，**紧挨**） | 恰好 **1** 处 |
| ③ | `arch_need_count` | **汇总判定**（整行锚定） | 恰好 **1** 处 |
| ④ | `arch_need_count` | **失败计数**（整行锚定） | 恰好 **2** 处 |
| ⑤ | `arch_need_count` | **调用点总数** | 恰好 **6** 处 |

· ⚠ **门项②是关键**：判定体里记 `WIRING_HITS` 那行与记 `WIRING_FAIL=1` 那行
**都在另一行上** ⇒ ⇒ 钉 `if` 那行的门**抓不住**它们
⇒ ⇒ 必须用**跨行**门把整块结构**紧挨**着钉住
⇒ ⇒ 正好用**批 EF 新增的门型** `arch_need_count_ml`
⇒ ⇒ 门侧与审计侧**完全同口径**；
· ⚠ **门项⑤不是整行锚定** ⇒ ⇒ 6 处调用的**正则实参与说明文字都是自由文本**
（其中一处还自带双引号）⇒ ⇒ 整行锚定等于把 6 条调用逐字写进正则
⇒ ⇒ **显式豁免**（`ci-wiring-anchor.exempt` 第 **21** 条，
理由与 `contract-check.sh` 那条**同款**：清单门数的是调用点数量）；
· ⚠ **门项正则里不许有单引号** ⇒ ⇒ 字面竖线写 `[|]`（**不写 `\|`**）
⇒ ⇒ 源里的引号用 `.` 匹配；
· ⚠ **审计器不用改**（`arch_need_count_ml` 批 EF 已登记）⇒ ⇒ 只同步条数。

⚠⚠⚨ **本批的「自指陷阱」（当场处理）**：新增一段 ⇒ ⇒ **段级 trailer 多 1 处**
⇒ ⇒ 批 EF 的两条 trailer 门项期望值 **80 → 81**、`ARCH_ANY_FAIL=1` **80 → 81**、
`ARCH_FAIL=0` **81 → 82**
⇒ ⇒ **说明文字里的同一个数字也要一起改**
⇒ ⇒ 否则审计器的「期望校准」当场报「**文字在骗人**」。

⚠⚠⚨ **本批把落盘脚本改过两次**（**判据写错**，不是行为问题 —— 两次都是判据层当场抓住的）：

① 第一版落盘脚本解析门项行时，把「RX 的**收尾单引号**」漏在了分组之外
⇒ ⇒ 重写时那句引号**消失** ⇒ ⇒ 5 条老门项行变成「RX 没闭合」
⇒ ⇒ 审计器当场报「**认领 1452 vs 实际 1457**」⇒ ⇒ 回滚重做
⇒ ⇒ 改成把**两端引号一起收进分组**；
② 第二版把「说明文字**末尾**的收尾引号」也一起吞进了 text 组
⇒ ⇒ 追加的说明文字**尾巴被甩到引号外面** ⇒ ⇒ 那一行被切成 **18** 个实参
⇒ ⇒ 审计器当场报「**实参数个数**与门型签名对不上」⇒ ⇒ 回滚重做
⇒ ⇒ 改成显式补引号 + **当场加一道 shlex 自检**（必须切成**恰好 5** 段）
⇒ ⇒ 这一类错误以后**当场暴露**，不用等审计器。

**④ 负控 5 真红（累计 51 → 56）**

· **NC52** 掏空 `wire_need` 的**判定行**（`grep -E -- "$re"` → `grep -E -- ""`）
⇒ ⇒ **双断言**：判定行门项**红** **且** 跨行门项**红** ⇒ ⇒ 两条腿都咬住；
· **NC53** 摘掉**失败计数**（✗ 支的 `WIRING_FAIL=1` → `0`）
⇒ ⇒ **双断言**：失败计数门项**红** **且** 跨行门项**红**
⇒ ⇒ 顺带证「**✗ 打了但 CI 不红**」这个形态被抓住；
· **NC54** 把**汇总判定反相**（`-ne 0` → `-ne 1`）
⇒ ⇒ **双断言**：汇总判定门项**红** **且** 判定行门项**仍然绿**
⇒ ⇒ **证明两条门各管各的**（不是同一条门顶两次）；
· **NC55** **删掉一处 `wire_need` 调用点**
⇒ ⇒ **双断言**：调用点总数门项**红** **且** 判定行门项**仍然绿**
⇒ ⇒ **证明「调用点清单」与「判定体」是两条独立的腿**；
· **NC56**（**正向对照** · 不变异）⇒ ⇒ 接线门**绿**。

⚠⚠⚨ **本批把 harness 的判据改过两次**（**判据写错**，不是行为问题）：

① NC53 / NC55 的变异元组少写了一个字段（harness 要的是 **3** 元组
`(相对路径, 旧, 新)`）⇒ ⇒ harness 报 `ValueError: not enough values to unpack`
⇒ ⇒ 用例无效 ⇒ ⇒ 补齐后复跑；
② NC56 的**关键词**里带了 `${ARCH_N}` ⇒ ⇒ 运行时它会被**展开成数字**
⇒ ⇒ 「关键词没出现」是**判据写错**，不是行为问题
⇒ ⇒ 改成取**展开前**的那一段（与批 EG 的 `EG_OK_PREFIX` 同款做法）。

⚠⚠⚨ **本批在 harness 里撞出一个「假通过」，并当场修掉**（这是本批的**附带发现**）：

· harness 的最终计分是
`verdict = '真红' if (red and extra_ok) else '没红'`
⇒ ⇒ **只认 `extra_ok`** ⇒ ⇒ 而 **NC7 / NC9 的双断言后半**
（孤儿探针也红 ／ 接线门也红）**只设了 `ok`** ⇒ ⇒ `ok` **根本没进计分**
⇒ ⇒ 那两半**从来没被算过** ⇒ ⇒ 「N/N 真红」在它们身上是**假通过**；
· 症状很直白：**NC7 的日志里明明白白打了「orphan rc=0  ⚠ 没红」**
⇒ ⇒ 门在**喊**，但**计分不听**；
· 根因：**批 EA 把 CI 第 9 步改成「sh + bash **双跑**」**
⇒ ⇒ NC7 的旧锚点**只删了 `sh` 那一遍** ⇒ ⇒ `bash` 那一遍还在
⇒ ⇒ `ci-shell-parity.sh` **仍然可达** ⇒ ⇒ 孤儿探针**理应绿**
⇒ ⇒ ⇒ 那半条断言在**当前形态下根本不可能成立**；
· 修法：① 那两处的失败**改设 `extra_ok`** ⇒ ⇒ 进计分；
② **NC7 的变异改成「两遍都删」** ⇒ ⇒ 那才是「CI 里对双跑覆盖面门的调用被删了」的**真意思**；
· ⚠ **仓内没有洞**：`bash` 那一遍调用**有门**
（`ci-wiring.sh` 的 `arch_need_count_in_step` 钉住
「第 9 步里必须有 `bash "$SRC/scripts/ci-shell-parity.sh"`」）
⇒ ⇒ 摘掉它**必红** ⇒ ⇒ 本条只是**负控自己陈旧**，不是产品/判据层的洞。


**⑤ 数字（全部实测）**

· 门项条数 **1452 → 1457**（**四处同改**）；
· 门项执行次数 **1455 → 1460**（+5）；
· 恒真探针 shell+python 条件 **1057 → 1058**（+1 = 批 EH 段 trailer 的自指条件）；
· 段级 trailer：`ARCH_ANY_FAIL=1` **80 → 81**、`ARCH_FAIL=0` **81 → 82**；
· 批 EF 的两条 trailer 门项 **80 → 81**（**自指**）；
· 豁免表 **20 → 21**；
· 门型注册表 **16 不变**、`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、
盘点登记册 **34 不变**、盘点 **21 组 / 73 处不变**；
· 负控 **51 → 56**。

**⑥ 已知边界（如实记着）**

· ⚠ **`ci.sh` 的 5 处 `wire_need` 调用点也还没逐条钉**
⇒ ⇒ 本批只钉了**总数**（6 处）⇒ ⇒ 「总数不变」≠「每一条都没被换掉」
⇒ ⇒ 逐条那部分属**另一批**的活
⇒ ⇒ 兜底是：调用点里的**正则实参**本身也被别的门看着
⇒ ⇒ 但那是**别的承诺**，不是「6 处调用点不许被删」这条；
· ⚠ **`ci.sh` 上还有 39 条 C 类判定行没人逐条钉**（批 EG 普查口径）
⇒ ⇒ 本批只钉了第 7 步那一个助手的承重墙 ⇒ ⇒ 其余属**另一批**的活；
· ⚠ **契约门那 61 条判定行里还有 59 条没人逐条钉**（批 EG 记的边界，**仍在**）
⇒ ⇒ 本批**没有碰**它；
· ⚠ **`ci-platform-probe.sh` 25 条 / `check-deb-layout.sh` 18 条 C 类判定行**
⇒ ⇒ 同样属**另一批**的活；
· ⚠ **跨行门盯「形状」不盯「措辞」** ⇒ ⇒ 措辞改了（结构没变）它照旧绿
⇒ ⇒ 这是**有意的**；
· ⚠ **门项⑤是计数门** ⇒ ⇒ 某处塌了另一处补上 ⇒ ⇒ 命中数不变 ⇒ ⇒ 绿
⇒ ⇒ 但**判定行门是逐字的** ⇒ ⇒ 补上的那处字面不同 ⇒ ⇒ 红
⇒ ⇒ **两条腿互补**；
· ⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。

### E.2cr CI 入口第 8 步（图谱 Canvas 契约门）的失败位必须**成对**钉住（批 EI）

**① 起因：先把「洞在哪儿」这件事量准（普查口径重写）**

批 EG 收尾记的那批待办里有一条：「`ci.sh` 上还有 **39** 条 C 类判定行没人逐条钉」。
⚠⚠⚨ 但这条**数字本身**来自批 EF 那版普查，而那版普查的**口径有六处错** ⇒ ⇒
先把它**重写**再谈收洞（不然会照着假清单做无用功）：

| # | 口径错 | 后果 |
|---|---|---|
| ① | 只把「**整行锚定**门项匹配这一行」当作「被守住」 | **漏掉「跨行门」也能守住一条判定行** ⇒ ⇒ 批 CU 那类门（「初始化 → 接退出码 → 报错 → `exit 1`」**整块钉住**）包住的判定行被**误判成「没人提」** ⇒ ⇒ **C 类清单有假阳性** |
| ② | 只认 `arch_need_count_ml` | **漏了 `arch_need_ml`**（它是「**至少 1 次**」的跨行门 ⇒ 形状对 ⇒ 照样守得住） |
| ③ | 用 Python `re` 做整行匹配 | `[[:space:]]` 是 **POSIX 字符类** ⇒ ⇒ Python `re` **不认** ⇒ ⇒ 匹配结果**不可信** ⇒ ⇒ 改成**一律 GNU grep** |
| ④ | 把「跨行门命中区间」当「它罩住了区间内所有行」 | 中段含**无界 `.*`** 的跨行门**只钉端点**（压行之后 `.*` 吃掉一切）⇒ ⇒ 它**根本不罩住**中间的判定行 ⇒ ⇒ 必须排除 |
| ⑤ | `compressed.find(body)` 找「行的位置」 | 找的是**首次出现**的位置 ⇒ ⇒ 同一形态的行**串行号** |
| ⑥ | 用 `grep -b` 的偏移去比 Python 的**字符**下标 | `grep -b` 给的是**字节**偏移 ⇒ ⇒ 文本里满是中文（多字节）⇒ ⇒ **偏移全错** |

⚠⚠⚨ 修正后的结论：**`ci.sh` 的 72 条判定行 = A（整行锚定守住）31 + A′（跨行门守住）2 + C（没人提）39**
⇒ ⇒ 「39 条」这个数字**碰巧对**，但**清单内容**不一样了（批 EF 那版把 417 / 429 这类
**已被批 CU 跨行门守住**的行算成 C ⇒ ⇒ 那版清单**一半是假的**）。

⇒ ⇒ ⇒ **本批落点**：第 8 步的**失败位 `CANVAS_FAIL`** —— 它有
**设置侧 4 处**（`CANVAS_FAIL=1`）与**读取侧 1 处**，
而批 CJ 只钉住了设置侧**其中 1 处** ⇒ ⇒ 这是**同一个承诺的两条腿**，
**读取侧一条门都没有** ⇒ ⇒ **看着像「有门」，其实两条腿都缺**。

**② 决定性实验（修前证据，scratch 树 + 抽第 8 步单独跑）**

⚠ **为什么只抽第 8 步**（批 EC 纪律的同款应用）：变异会让接线门自己红
⇒ ⇒ 整个 `ci.sh` 第 9 步就中止 ⇒ ⇒ 「第 9 步没出现」**恒成立**
⇒ ⇒ 那条断言**恒真** ⇒ ⇒ **无信息量**。
⚠ 抽取用**纯 ASCII 锚点**（`CANVAS_METHODS=` 步首 ／ `${CANVAS_N}/26` 步尾）
⇒ ⇒ **不靠行号** ⇒ ⇒ 改文件也不会漂。

| # | 变异 | 第 8 步 rc | 第 8 步结论 |
|---|---|---|---|
| ① | 基线（不改） | **0** | ✓ Canvas2D 覆盖契约清单 26/26 个方法 |
| ② | 失败位**完好** + 摘掉 `fillRect` 的 `override` | **1** | ✗ Canvas2D 缺契约方法：fillRect ⇒ ⇒ **真断言抓住了** |
| ③ | **读取侧判定被掏空**（`-ne 0` → `-gt 1` ⇒ 这一支**永远不触发**）+ 同样摘契约 | **0** | ✓ …26/26 ⇒ ⇒ ⚠⚠⚨ **假绿坐实** |
| ④ | **设置侧失败位被摘**（`CANVAS_FAIL=1` → `0`）+ 同样摘契约 | **0** | ✓ …26/26 ⇒ ⇒ ⚠⚠⚨ **假绿坐实（另一种形态）** |

⚠⚠⚨ ③ ④ 的形态尤其阴：**「✗ Canvas2D 缺契约方法：fillRect」那行照样打出来了**，
但**结论行照样是「✓ …26/26」且 rc=0** ⇒ ⇒ CI **不红**。
而且 ①②③④ **判据层全绿**（接线门 rc=0 ／ 恒真探针 rc=0 ／ 审计器 rc=0）
⇒ ⇒ 这个洞对判据层**完全不可见**。四例**洁净度**全部为逐字节相同。

**③ 修法（落门 9 条，批 EI 段）**

| 腿 | 门型 | 盯什么 | 条数 |
|---|---|---|---|
| 设置侧**触发** | `arch_need_count`（整行锚定） | 4 条**判定行**（577 / 598 / 604 / 613） | 各 1 |
| 设置侧**置位** | `arch_need_count_ml`（跨行紧挨） | 3 处「报错 ⇒ 置位 ⇒ `fi`」**整块** | 各 1 |
| 读取侧**判定** | `arch_need_count`（整行锚定） | `if [ "$CANVAS_FAIL" -ne 0 ]; then` | 1 |
| 读取侧**整块** | `arch_need_count_ml`（跨行紧挨） | 判定 ⇒ 报错 ⇒ `exit 1` ⇒ `fi` | 1 |

⚠ 设置侧第 4 处置位（批 CJ 那条）**已由批 CJ 的门钉住** ⇒ ⇒ 不重复落。
⚠⚠⚨ **「触发」与「置位」必须成对** —— 只钉「报错 ⇒ 置位 ⇒ `fi`」是**不够**的：
**触发行被摘 ⇒ ⇒ 那一块成了孤儿 ⇒ ⇒ 失败位永远置不上 ⇒ ⇒ 还是假绿**。
⚠ **跨行门盯「形状」不盯「措辞」** ⇒ ⇒ 措辞改了（结构没变）它照旧绿 ⇒ ⇒ **有意的**。

⚠⚠⚨ **本批踩过的坑（都记下来）**：

① **落门第一版只落 5 条** ⇒ ⇒ 「设置侧的**触发**判定行」没钉
⇒ ⇒ 只钉置位块是不够的 ⇒ ⇒ **补到 9 条**才完整
⇒ ⇒ 这正是本项目一直在反对的「**半条腿**」（看着像有门 ⇒ 其实那条腿缺）；
② **RX 的字面量转义**：源行里**含 POSIX 字符类**（`[[:space:]]`）
⇒ ⇒ 「只转义 `.[](){}*+?|^$\`」那一套会让模式里**长出字符类**
⇒ ⇒ 匹配的是「一个空白字符」而不是**11 个字符的字面文本** ⇒ ⇒ 门**恒红**
⇒ ⇒ 改成**三步**：① 字面竖线先换成占位符 → ② **所有**元字符（含 `[`、`]`、`\`）逐个加反斜杠
⇒ ⇒ 模式里**再也不会出现字符类** → ③ 占位符还原成 `[|]`（**唯一**允许不转义 `[` 的地方）；
③ **RX 必须带缩进** ⇒ ⇒ 整行锚定是「**整行**」⇒ ⇒ 源行有 4 空格缩进
⇒ ⇒ `^if …` 匹配不到 ⇒ ⇒ 必须是 `^    if …`；
④ **判定行排序必须按行号**，不能按字符串 ⇒ ⇒（`(` < `[`）
⇒ ⇒ 613 那行排到 577 那行**前面** ⇒ ⇒ `RX6..RX9` 与说明文字里的 ①②③④ **全部对错号**
⇒ ⇒ 负控 NC62（改 577）红的却是**标着「②」**的门 ⇒ ⇒ 「没找到红行」
⇒ ⇒ ⚠ 这条**同时是负控抓出来的**（断言对不上 ⇒ 用例无效）；
⑤ 落门脚本第一版**占位符没被替换** ⇒ ⇒ 门项里留着 `{RX6}` 字面量
⇒ ⇒ 审计器当场报 **rc=8**「行首没有 ^ 锚点」+「门恒红」⇒ ⇒ **判据层有牙**
⇒ ⇒ 补了「**占位符残留即失败**」的兜底；
⑥ harness 的 `<X2:` 后面多写了一个 `\x01` ⇒ ⇒ harness 报「X2 需要 3 段」
⇒ ⇒ 修正后复跑 ⇒ ⇒ 又是**判据层当场抓住**。

**④ 负控 9 真红（累计 56 → 65）**

· **NC57** 读取侧判定掏空 ⇒ ⇒ 双断言：读取侧判定行门**红** **且** 读取侧整块门**红**；
· **NC58** 设置侧①置位块被摘 ⇒ ⇒ 双断言：置位块门**红** **且** 读取侧判定行门**仍然绿**；
· **NC59** 设置侧②置位块被摘（同款；⚠ 那处是 **4 缩进** ⇒ ⇒ 是 8 缩进那串的**子串**
⇒ ⇒ 纯字符串替换会**落到错的地方** ⇒ ⇒ 必须用**上一行**定位）；
· **NC60** 设置侧③置位块被摘；
· **NC61**（**正向对照**·不变异）⇒ ⇒ 接线门**绿**；
· **NC62** 设置侧①**判定行**掏空（`override` → `xoverride`）
⇒ ⇒ 双断言：判定行门**红** **且** 该处的**置位块门仍然绿**
⇒ ⇒ **证明「触发」与「置位」是两条独立的腿**；
· **NC63** 设置侧②判定行反相；· **NC64** 设置侧③判定行掏空；
· **NC65** 设置侧④判定行掏空。

**⑤ 数字（全部实测）**

· 门项条数 **1457 → 1466**（**四处同改**）；
· 门项执行次数 **1460 → 1469**（+9）；
· 恒真探针 shell+python 条件 **1058 → 1059**（+1 = 批 EI 段 trailer 的自指条件）；
· 段级 trailer：`ARCH_ANY_FAIL=1` **81 → 82**、`ARCH_FAIL=0` **82 → 83**；
· 批 EF 的两条 trailer 门项 **81 → 82**（**自指**）；
· 豁免表 **21 不变**（批 EI 的门项**整行锚定 / 跨行**⇒ ⇒ **不需要新增豁免**）；
· 门型注册表 **16 不变**、`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、
盘点登记册 **34 不变**、盘点 21 组 / 73 处不变；
· 负控 **56 → 65**。

**⑥ 已知边界（如实记着）**

· ⚠ **`ci.sh` 还有 35 条 C 类判定行没逐条钉**（本批收掉 4 条）
⇒ ⇒ 其中最像本批同款的是「**读取侧失败位**」那一族：
`visual_changed` / `repro_fail` / `cross_fail` / `AGENT_RC` / `_w_dash_rc` / `_p_sh_rc` /
`_deb_rc` / `ATS_RC` / `_ic_rc` / `_ic2_rc` ⇒ ⇒ 属**下一批**的活；
· ⚠ **`ci.sh` 的 5 处 `wire_need` 调用点也还没逐条钉**（批 EH 只钉了**总数**）
⇒ ⇒ 属**下一批**的活；
· ⚠ **契约门 57 条 / `ci-platform-probe.sh` 25 条 / `check-deb-layout.sh` 18 条**
C 类判定行 ⇒ ⇒ 属**下一批**的活（⚠ 它们的数字要**用修正后的口径**重算，
批 EF 那版的清单**有一半是假的**）；
· ⚠ **跨行门盯「形状」不盯「措辞」** ⇒ ⇒ 措辞改了（结构没变）它照旧绿 ⇒ ⇒ **有意的**；
· ⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。
### E.2cs CI 入口的 10 个「失败位家族」的读取侧必须成对钉住（读取侧判定行 12 条 + 设置侧没牙的 7 处 ⇒ ⇒ 同一个失败位的两个读取分支，只有一个有门 ⇒ ⇒ 掏空读取侧 ⇒ ⇒ 假绿）

⚠⚠⚨ **先把「洞在哪儿」量准（普查口径沿用批 EI 的修正版 —— 六处错不能再犯）**：
`ci.sh` 用**失败位**把各步的「真失败」汇到一处再判红 ⇒ ⇒ 每个家族都是
「**设置侧**（置位 / 捕获）+ **读取侧**（读出来判红）」**两条腿**
⇒ ⇒ 修正口径普查实测：**读取侧 12 条判定行，一条门都没有**（全属 C 类「没人提」）
⇒ ⇒ 而**设置侧**只有 **7 处**没牙（`visual_changed` 1 + `repro_fail` 4 + `cross_fail` 2）
⇒ ⇒ 其余 7 族（`AGENT_RC` / `_w_dash_rc` / `_p_sh_rc` / `_deb_rc` / `ATS_RC` /
`_ic_rc` / `_ic2_rc`）的**捕获行早就已经有牙** ⇒ ⇒ ⇒ **不重复落**（批 EI 的同款规矩）。

⚠⚠⚨ **决定性实验（修前证据，scratch 树 + 抽第 9 步那段单独跑）**：
⚠ **为什么只抽那一段单独跑**（批 EC / EH / EI 纪律的同款应用）：
变异会让**接线门自己红** ⇒ ⇒ 整个 `ci.sh` 在第 9 步就中止
⇒ ⇒ 「第 9 步没出现」这个断言**恒成立** ⇒ ⇒ 那条断言**恒真** ⇒ ⇒ 无信息量
⚠ 抽取用**纯 ASCII 锚点**（`_P_SH_LOG=` 步首 ／ `_P_BASH_LOG` 那段步尾）⇒ ⇒ **不靠行号**
⚠ **「真实失败」怎么造**：把 `BIN` 从环境里拿掉 ⇒ ⇒ 双跑覆盖面门 **fail closed**
⇒ ⇒ 它在 sh 与 bash 下**输出逐字节相同、退出码也相同**
⇒ ⇒ ⇒ **只有读取侧那道判定**能抓住它 ⇒ ⇒ ⇒ 那是**唯一**能暴露假绿的场景

| # | 变异 | 第 9 步 rc | 判据层（接线门 / 恒真 / 审计） | 结论 |
|---|---|---|---|---|
| ① | 基线（不改，`BIN` 在场） | **0** | 0 / 0 / 0 | ✓ 双跑覆盖面门全绿 |
| ② | 失败位**完好** + `BIN` 拿掉 | **1** | 0 / 0 / 0 | ✗ 双跑覆盖面门失败 ⇒ ⇒ **真断言抓住了** |
| ③ | **读取侧判定被掏空**（`-ne 0` → `-gt 1`）+ 同样拿掉 `BIN` | **0** | 0 / 0 / 0 | ⚠⚠⚨ **假绿坐实**（洞对判据层**完全不可见**） |
| ④ | **设置侧捕获被摘**（`\|\| _p_sh_rc=$?` → `\|\| _p_sh_rc=0`）+ 同样拿掉 `BIN` | **1** | **1** / 0 / **4** | ⇒ ⇒ 没假绿（同段里还有「退出码对比」那道腿）⇒ ⇒ 这条腿**早就有牙** |
| ⑤ | **反向对照** · 读取侧被掏空 **且** 失败是「两遍输出分叉」那种 | **1** | 0 / 0 / 0 | ⇒ ⇒ 后面还有 `cmp` 那道腿 ⇒ ⇒ 这一族**不止一条腿** |

⚠⚠⚨ ③④⑤ 的重要发现：**别整族假设** —— ④ 说明「设置侧」这一族**已经有牙**，
⑤ 说明「读取侧」这一族**还有第二道腿** ⇒ ⇒ ⇒ 落门范围**必须逐族实测**，不能照抄清单。

⚠⚠⚨ **「哪条腿有牙」实测普查**（逐处改 ⇒ 看接线门红不红 ⇒ ⇒ 范围**按实测**定）：
⚠ **设置侧**（10 族）：没牙 **7** 处（`visual_changed` 1 + `repro_fail` 4 + `cross_fail` 2）；
`AGENT_RC` / `_w_dash_rc` / `_p_sh_rc` / `_deb_rc` / `ATS_RC` / `_ic_rc` / `_ic2_rc`
的捕获行 ⇒ ⇒ **有牙** ⇒ ⇒ 不重复落
⚠ **读取侧**（12 条判定行）：**12 条全都没牙** ⇒ ⇒ ⇒ 本段逐条钉住

⚠ **修法（落门 19 条，批 EJ-1 段）**：
读取侧**判定行 12** 条（`arch_need_count` **整行锚定**）｜设置侧**置位块 7** 条
（`arch_need_count_ml` **跨行紧挨**：报错 ⇒ 置位 ⇒ `fi` / `continue` ⇒ `fi`）
⚠⚠⚨ **两条腿必须成对** —— 只钉读取侧 ⇒ ⇒ 设置侧塌了没人知道；
只钉设置侧 ⇒ ⇒ 读取侧被掏空 ⇒ ⇒ 失败位**置上了也白置**
⚠ **跨行门盯「形状」不盯「措辞」** ⇒ ⇒ 措辞改了（结构没变）它照旧绿 ⇒ ⇒ **有意的**
⚠ **`cross_fail` 那族的「报错 ⇒ 置位」不紧挨**（中间隔着把 stderr 打出来的两行）
⇒ ⇒ 因此只钉**紧挨**的那一段 ⇒ ⇒ **有意的**

⚠⚠⚨ **本批踩过的坑（都记下来）**：
① **RX 必须带源行缩进**（批 EI 踩过的坑 ③，第 2 次栽在同一处）—— 整行锚定是「**整行**」
⇒ ⇒ 源行有 4 空格缩进时 `^if …` 匹配不到 ⇒ ⇒ 必须是 `^    if …`
⇒ ⇒ 第一版落门后**审计器当场报 rc=4**（4 条门恒红）⇒ ⇒ 改法：RX 用**未 strip 的源行**
⇒ ⇒ 并在落盘器里加「**19 条 RX 逐条 grep 自证**」（不靠落完再让审计器来报）
② **负控的变异路径必须相对仓库根** —— 第一版写了**绝对路径**
⇒ ⇒ harness 把变异**直接落在真仓上**（而门跑的是 scratch 树）
⇒ ⇒ 表现是「变异已落」但**门没红** ⇒ ⇒ ⇒ 查出来：树里的文件**根本没变**
⇒ ⇒ 修法：路径改相对 + 在生成器里加「**变异路径必须是相对路径**」自检
③ **两个 harness 实例不能并发**（共用同一个 scratch 目录 ⇒ 互相 `rmtree`）
⇒ ⇒ 症状是「用例莫名其妙全绿 / 仓被莫名改脏」⇒ ⇒ ⇒ 一次只跑一个

⚠ **负控 20 真红**（累计 **65 → 85**）：NC66–NC77 读取侧 12 条判定行逐条掏空
（**双断言**：该族读取侧判定行门**红** **且** 同族设置侧置位门**仍然绿**
⇒ ⇒ **证明「读失败位」与「设失败位」是两条独立的腿**）｜
NC78–NC84 设置侧 7 处置位逐处摘掉（**双断言**：设置侧置位门**红** **且**
同族读取侧判定行门**仍然绿**）｜**NC85**（正向对照·不变异）接线门绿。

⚠ **数字（实测）**：门项条数 **1466 → 1485**（**四处同改**）、执行次数 **1469 → 1488**（+19）、
恒真 **1059 → 1060**（+1 = 批 EJ-1 段 trailer 的自指条件）、
段级 trailer `ARCH_ANY_FAIL=1` **82 → 83** / `ARCH_FAIL=0` **83 → 84**、
批 EF 两条 trailer 门项 **82 → 83**（**自指**）、豁免表 **21 不变**、
门型注册表 **16 不变**、`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、
盘点登记册 **34 不变**、盘点 21 组 / 73 处不变；负控 **65 → 85**。

⚠⚠⚨ **如实记着的已知边界**：
⚠ **读取侧「整块」**（判定 ⇒ 报错 ⇒ `exit 1` ⇒ `fi`）**10 处还没钉** ⇒ ⇒ 属**下一批**的活
（⚠ 判红 ⇒ **不 `exit 1`** ⇒ ⇒ 照样往下走 ⇒ ⇒ 照样打「✓」⇒ ⇒ 假绿）
⚠ **设置侧「触发判定行」**（`cmp` 不一致 / `repro_shoot` 失败那些触发行）**还没钉**
⇒ ⇒ 触发行被摘 ⇒ ⇒ 那一块成**孤儿** ⇒ ⇒ 失败位**永远置不上** ⇒ ⇒ 属**下一批**的活
⚠ **失败位的初始化行**（`X=0` 那 9 处）**还没钉** ⇒ ⇒ 属**下一批**的活
⚠ `ci.sh` 的 5 处 `wire_need` 调用点也还没逐条钉（批 EH 只钉了**总数**）⇒ ⇒ 下一批
⚠ **契约门 57 条 / `ci-platform-probe.sh` 25 条 / `check-deb-layout.sh` 18 条** C 类判定行
⇒ ⇒ 属**下一批**的活（⚠ 数字要用**修正后的口径**重算）
⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。
### E.2ct CI 入口的读取侧整块与触发判定行必须逐条钉住（读取侧整块 10 条 + 触发判定行 3 条 ⇒ ⇒ 那道「exit N 恰好 43 处」的计数门只守条数、不守哪一处 ⇒ ⇒ 掏空一处 ⇒ ⇒ 计数不变 ⇒ ⇒ 假绿）

⚠⚠⚨ **先把「洞在哪儿」量准（普查口径沿用批 EJ-1 的修正版 —— 六处错不能再犯）**：
`ci.sh` 的**读取侧整块**（判定 ⇒ 报错 ⇒ `exit 1` ⇒ `fi`）共 **10** 处
⇒ ⇒ 而**设置侧触发判定行**里，只有 **3 处**没牙（336 / 347 / 376–377）
⇒ ⇒ 其余 4 处（288 / 341 / 352 / 384）**早就有牙**（批 BN 的「重拍比字节」门整行锚定）
⇒ ⇒ ⇒ **不重复落**（批 EJ-1 的同款规矩）。

⚠⚠⚨ **决定性实验（修前证据，scratch 树 + 抽第 9 步那段单独跑）**：
⚠ **为什么只抽那一段单独跑**（批 EC / EH / EI / EJ-1 纪律的同款应用）：
变异会让**接线门自己红** ⇒ ⇒ 整个 `ci.sh` 在第 9 步就中止
⇒ ⇒ 「第 9 步没出现」这个断言**恒成立** ⇒ ⇒ 那条断言**恒真** ⇒ ⇒ 无信息量
⚠ **「真实失败」怎么造**：把 `BIN` 从环境里拿掉 ⇒ ⇒ 双跑覆盖面门 **fail closed**
⇒ ⇒ 它在 sh 与 bash 下**输出逐字节相同、退出码也相同**

| # | 变异 | 第 9 步 rc | 判据层（接线门 / 恒真 / 审计） | 结论 |
|---|---|---|---|---|
| ① | 基线（不改，`BIN` 在场） | **0** | 0 / 0 / 0 | ✓ 双跑覆盖面门全绿 |
| ② | 失败位**完好** + `BIN` 拿掉 | **1** | 0 / 0 / 0 | ✗ 双跑覆盖面门失败 ⇒ ⇒ **真断言抓住了** |
| ③ | **读取侧整块里的 `exit 1` 被摘**（`exit 1` → `exit 0`）**并**在同一块里补一行死代码 `exit 1`（⇒ ⇒ `exit N` 的**条数不变**） | **0** | 0 / 0 / 0 | ⚠⚠⚨ **假绿坐实**（洞对判据层**完全不可见**） |
| ④ | **只**把 `exit 1` 改成 `exit 0`（**不改计数**） | **0** | **1** / 0 / **4** | ⇒ ⇒ 判据层会红 ⇒ ⇒ 那是那道**计数门** |

⚠⚠⚨ ③ 与 ④ 的差 = **计数** ⇒ ⇒ ⇒ 那道门守的是**条数**，不是**哪一处**
⇒ ⇒ ⇒ ⇒ 所以 10 处**全部**要**逐条**钉。

⚠⚠⚨ **归因（必须查「红的是哪条门」）**：
⚠ 读取侧整块那 10 处「有牙」的来源 = **批 CA 的计数门**（`exit [1-9]` 恰好 **43** 处）
⇒ ⇒ 它守的是**条数** ⇒ ⇒ **不守哪一处** ⇒ ⇒ 「判红了必须 exit 1」这条承诺**仍然没人守**
⚠ 设置侧触发判定行 288 / 341 / 352 / 384 红的是**批 BN 的「重拍比字节」门**（整行锚定）
⇒ ⇒ ⇒ **已有牙，不重复落**

⚠ **修法（落门 13 条，批 EJ-2 段）**：
读取侧**整块 10** 条（`arch_need_count_ml` **跨行紧挨**：判定 ⇒ 报错 ⇒ `exit 1` ⇒ `fi`）｜
设置侧**触发判定行 3** 条（336 / 347 用 `arch_need_count` **整行锚定**；376–377 两行块用 `arch_need_count_ml`）
⚠ **跨行门盯「形状」不盯「措辞」** ⇒ ⇒ 措辞改了（结构没变）它照旧绿 ⇒ ⇒ **有意的**

⚠⚠⚨ **本批踩过的坑（都记下来）**：
① **计数门骗不过去** ⇒ ⇒ 必须让 `exit [1-9]` 的**条数不变**
⇒ ⇒ 改别处 `exit 1` → `exit 2` **无效**（`exit 0` 仍不匹配 ⇒ 计数掉 1）
⇒ ⇒ 只能在**同一块里补一行死代码 `exit 1`**
② **「接线门红了」≠「管这件事的那条门红了」** ⇒ ⇒ 必须**归因**（红行原文 ⇒ 是哪条门）
⇒ ⇒ 第一轮只问「红不红」⇒ ⇒ 误判成「这 10 处有牙」⇒ ⇒ 改成两段式（普查 + 归因）
③ **说明文字里的数字必须跟上门项期望值** ⇒ ⇒ 落完门审计器当场报 **rc=9**（文字在骗人）
⇒ ⇒ ⇒ 修法：3945 / 3946 / 5353 / 5354 四处「恰好 N 处」同步改

⚠ **负控 14 真红**（累计 **85 → 99**）：NC86–NC95 读取侧整块 10 处逐条摘 `exit 1`
（**双断言**：该整块门项**红** **且** 同族读取侧判定行门项**仍然绿**
⇒ ⇒ **证明「读失败位」与「判红就 exit」是两条独立的腿**）｜
NC96–NC98 设置侧触发判定行 3 处逐条改写（**双断言**：该判定行门项**红** **且**
同族置位块门项**仍然绿**）｜**NC99**（正向对照·不变异）接线门绿。

⚠ **数字（实测）**：门项条数 **1485 → 1498**（**四处同改**）、执行次数 **1488 → 1501**（+13）、
恒真 **1060 → 1061**（+1 = 批 EJ-2 段 trailer 的自指条件）、
段级 trailer `ARCH_ANY_FAIL=1` **83 → 84** / `ARCH_FAIL=0` **84 → 85**、
批 EF 两条 trailer 门项 **83 → 84**（**自指**）、豁免表 **21 不变**、
门型注册表 **16 不变**、`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、
盘点登记册 **34 不变**、盘点 21 组 / 73 处不变；负控 **85 → 99**。

⚠⚠⚨ **如实记着的已知边界**：
⚠ **失败位的初始化行**（`X=0` 那 9 处）**还没钉** ⇒ ⇒ 属**下一批**的活
⚠ `ci.sh` 的 6 处 `wire_need` 调用点也还没逐条钉（批 EH 只钉了**总数**）⇒ ⇒ 下一批
⚠ **契约门 57 条 / `ci-platform-probe.sh` 25 条 / `check-deb-layout.sh` 18 条** C 类判定行
⇒ ⇒ 属**下一批**的活（⚠ 数字要用**修正后的口径**重算）
⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。
### E.2cu CI 入口的失败位初始化行与 wire_need 调用点必须逐条钉住（初始化行 9 条 + A 类顺序 forbid 3 条 + wire_need 调用点 5 条 ⇒ ⇒ 「初始化必须是 0」与「接线扫描还在」这两条承诺一条门都没有 ⇒ ⇒ 挪位置 / 换名字 ⇒ ⇒ 假绿）

⚠⚠⚨ **先把「洞在哪儿」量准（普查口径沿用批 EJ-1 / EJ-2 的修正版）**：
`ci.sh` 的失败位**初始化行**（`X=0`）共 **9** 处
⇒ ⇒ 逐条改字面（`X=0` → `X=00`，**行为不变**）⇒ ⇒ **接线门 rc=0、红行 0 条**
⇒ ⇒ ⇒ **9 处全都没牙**（批 EJ-2 收尾记的「下一批的活」，本批坐实）。
`ci.sh` 的 `wire_need` 调用点共 **6** 处
⇒ ⇒ 第 **555** 处（`AppModel.cpp` / `verify`）改文案 ⇒ ⇒ **红 2 条**（归因：别处已有整行门）
⇒ ⇒ ⇒ **早就有牙 ⇒ 不重复落**；**556–560** 改文案 ⇒ ⇒ **全绿** ⇒ ⇒ ⇒ **5 处都没牙**。

⚠⚠⚨ **决定性实验（修前证据，scratch 树 + 抽第 9 步那段单独跑）**：
⚠ **为什么只抽那一段单独跑**（批 EC / EH / EI / EJ-1 / EJ-2 纪律的同款应用）：
变异会让**接线门自己红** ⇒ ⇒ 整个 `ci.sh` 在第 9 步就中止 ⇒ ⇒ 断言**恒真** ⇒ ⇒ 无信息量。
⚠ **「真实失败」怎么造**：把 `BASE_DIR` 指到**不存在**的目录 ⇒ ⇒ `cmp` 必失败。

| # | 变异 | 第 9 步 rc | 判据层（接线门 / 恒真 / 审计） | 结论 |
|---|---|---|---|---|
| ① | 基线（不改）+ **真实失败** | **1** | 0 / 0 / 0 | ✓ 「视觉改动未提交」出现 ⇒ ⇒ **真断言抓住了** |
| ② | **初始化行挪到置位之后**（删 285 + 在 `done` 之后补 `visual_changed=0`） | **0** | 0 / 0 / 0 | ⚠⚠⚨ **假绿坐实**（失败位被清零 ⇒ 「视觉改动未提交」**没出现**） |
| ③ | 对照：**只改字面**（`visual_changed=0` → `visual_changed=00`） | **1** | 0 / 0 / 0 | ✓ 行为不变 ⇒ 仍红；⇒ ⇒ **判据层看不见这一处** |
| ④ | `loadVerify` → `verifyState`（同族、名字几乎一样）+ `AppModel.h` 里的声明被摘 | — | 0 / 0 / 0 | ⚠⚠⚨ **假绿坐实**（真接线没了 ⇒ 判据层**全绿**） |

⚠⚠⚨ **④ 的第一版选的是 555 ⇒ ⇒ 判据层**红**（接线门 rc=1 / 审计器 rc=4）
⇒ ⇒ ⇒ **恰好实证「555 早就有牙」** ⇒ ⇒ ⇒ 改选**没牙的 556** ⇒ ⇒ 判据层才全绿。
⇒ ⇒ ⇒ **归因反转也是资产**。

⚠⚠⚨ **形态差异（诚实标注，不是一刀切）**：
⚠ **只有「挪位置」才假绿** —— 改变量名 / 改字面都**不假绿**（置位行会用同一个名字重新赋值）
⇒ ⇒ ⇒ **单行整行锚定抓不住「挪位置」** ⇒ ⇒ 顺序类承诺必须用**跨行 forbid 门**。
⚠ 失败位**初始化行分两类**：
· **A 类**（`visual_changed` / `repro_fail` / `cross_fail`）：**只靠**初始化 + 置位
  ⇒ ⇒ 挪到置位之后**会假绿** ⇒ ⇒ **补 3 条 forbid 门**（顺序承诺）
· **B 类**（`AGENT_RC` / `_p_sh_rc` / `_deb_rc` / `ATS_RC` / `_ic_rc` / `_ic2_rc`）：
  被 `|| _x_rc=$?` **覆盖** ⇒ ⇒ 挪位置**无害** ⇒ ⇒ **只钉字面**
⚠ `ci.sh` **没有 `set -u`** ⇒ ⇒ 失败位**未定义**时 `[ "" -ne 0 ]` **判假**
⇒ ⇒ **不判红** ⇒ ⇒ 这是「初始化承诺没人守」的**另一条腿**。

⚠ **修法（落门 17 条，批 EJ-3 段）**：
失败位**初始化行 9** 条（`arch_need_count` **整行锚定**：守住「初值**必须**是 0」这个字面）｜
**A 类顺序 3** 条（`arch_forbid_ml` **跨行**：RX = `X=1.*X=0` ⇒ ⇒ 初始化行**不许**在置位之后）｜
`wire_need` **调用点 5** 条（`arch_need_count` **整行锚定**：守住「这条接线扫描还在」）
⚠ forbid 门**零新门型**（`arch_forbid_ml` 早就在门型注册表里 ⇒ ⇒ **16 不变**）
⚠ `_ml` 族**天然跨行** ⇒ ⇒ 审计器**不查**它的锚定形态 ⇒ ⇒ 中间**可以用** `.*`

⚠⚠⚨ **本批踩过的坑（都记下来）**：
① **「改字面 / 改变量名」不假绿** ⇒ ⇒ 唯一真·假绿形态 = **初始化行挪到置位之后**（失败位被清零）
⇒ ⇒ ⇒ 第一版负控差点写成「改字面」⇒ ⇒ 那只能证「门没钉字面」，证不了「顺序」⇒ ⇒ 改成挪位置
② **forbid 门必须做「正负有据」自证** ⇒ ⇒ 用**同一个变异**证明它由「判据层全绿」变为「判据层红」
⇒ ⇒ ⇒ 本批就是 **NC109–NC111**（挪位置 ⇒ forbid 门红 ⇒ 且同一条初始化行门项**仍然绿**）
③ **落门器的自指同步点比想象的多** ⇒ ⇒ 除门项条数（**四处同改**）外
⇒ ⇒ 还有 `ARCH_ANY_FAIL=1` / `ARCH_FAIL=0` / 批 EF 两条 trailer（**各 +1**）
⇒ ⇒ ⇒ 漏一处 ⇒ ⇒ 审计器当场报「说明文字里的数字在骗人」（rc=9）
④ **`.strip()` 会丢缩进** ⇒ ⇒ `_deb_rc` / `_ic_rc` / `_ic2_rc` 三条是**缩进**的
⇒ ⇒ ⇒ 负控变异必须**原样保留缩进** ⇒ ⇒ 只把 `=0` 换成 `=00`

⚠ **负控 18 真红**（累计 **99 → 117**）：NC100–NC108 失败位初始化行 9 处逐条改字面
（**双断言**：该初始化行门项**红** **且** 同族读取侧整块门项**仍然绿**
⇒ ⇒ **证明「初始化是 0」与「读失败位」是两条独立的腿**）｜
NC109–NC111 A 类顺序 3 处逐条挪位置（**双断言**：该 forbid 门项**红** **且**
同一条初始化行门项**仍然绿** ⇒ ⇒ **证明「顺序」与「字面」是两条独立的腿**）｜
NC112–NC116 `wire_need` 调用点 5 处逐条换正则实参（**双断言**：该调用点门项**红**
**且** 同族另一条调用点门项**仍然绿**）｜**NC117**（正向对照·不变异）接线门绿。

⚠ **数字（实测）**：门项条数 **1498 → 1515**（**四处同改**）、执行次数 **1501 → 1518**（+17）、
恒真 **1061 → 1062**（+1 = 批 EJ-3 段 trailer 的自指条件）、
段级 trailer `ARCH_ANY_FAIL=1` **84 → 85** / `ARCH_FAIL=0` **85 → 86**、
批 EF 两条 trailer 门项 **84 → 85**（**自指**）、豁免表 **21 不变**、
门型注册表 **16 不变**、`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、
盘点登记册 **34 不变**、盘点 21 组 / 73 处不变；负控 **99 → 117**。

⚠⚠⚨ **如实记着的已知边界**：
⚠ **契约门 57 条 / `ci-platform-probe.sh` 25 条 / `check-deb-layout.sh` 18 条** C 类判定行
⇒ ⇒ 属**下一批**的活（⚠ 数字要用**修正后的口径**重算）
⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。
### E.2cv 平台探针的判定行必须逐条钉住（判定条件 18 条 ⇒ ⇒ 「断言条件不许被放宽」这条承诺一条门都没有 ⇒ ⇒ 失败被静默吞掉 ⇒ ⇒ 假绿）

⚠⚠⚨ **先把「洞在哪儿」量准（普查口径沿用批 EI / EJ-3 的修正版）**：
⚠ **shell 层**的 `if`/`elif` 判定行（**引号里的 python / awk 正文不算**）
⇒ ⇒ `contract-check.sh` **59** 条（排掉 **2** 条 python 正文）、
`ci-platform-probe.sh` **23** 条（排掉 **7** 条 awk 正文）、`check-deb-layout.sh` **19** 条
⇒ ⇒ 其中**带失败上报**的候选共 **63** 条（契约门 **25** / 探针 **23** / deb 布局 **15**）
⚠ **旧记的「61 / 25 / 18」是旧口径** ⇒ ⇒ 本批**用修正后的口径**重算（批 EG 收尾的提醒）。
⚠ 逐条**实测**（尾部加一句注释 ⇒ 行为不变 ⇒ 「这一行有没有被任何门项看着」）：
⇒ ⇒ **8** 条**早就有牙**（契约门 **2**：取数失败 / 末尾未验证；探针 **5**：二进制检查 /
appAlive 两跳 / panelValid 格式 / iconMissing 格式；deb 布局 **1**）
⇒ ⇒ **55** 条**没有牙**（契约门 **23** / 探针 **18** / deb 布局 **14**）。

⚠⚠⚨ **决定性实验（修前证据，scratch 树 + 假二进制注入真实失败，4 例全成立）**：
⚠ **为什么用「假二进制」注入真实失败**（**不改任何产品代码**）：探针的输入是**真实二进制**
的输出 ⇒ ⇒ 要造一个「本来就该红」的场景 ⇒ ⇒ **只能换掉输入** ⇒ ⇒ 造一个照抄真输出、
但某一项坏掉的假二进制 ⇒ ⇒ ⇒ **产品代码零改动** ⇒ ⇒ 快照零变化。

| # | 变异 | 探针 rc | 判据层（接线门 / 恒真 / 审计） | 结论 |
|---|---|---|---|---|
| ① | 基线 + **真实失败**（假二进制输出坏 `taskbarInsets=1,2`） | **1** | 0 / 0 / 0 | ✓ 「✗ platform-probe 的 taskbarInsets= 缺失或不是四个整数」出现 ⇒ ⇒ **真断言抓住了** |
| ② | 同① + **L56 的判定条件被放宽**（`^[0-9]+,…$` → `^[0-9,]+$`） | **0** | **0 / 0 / 0** | ⚠⚠⚨ **假绿坐实**（失败被静默吞掉）⇒ ⇒ 而**判据层全绿** ⇒ ⇒ **洞对判据层完全不可见** |
| ③ | 只把坏值换成另一个坏值（`x,y`），判定完好 | **1** | 0 / 0 / 0 | ✓ 「失败是真的，不是环境坏掉」 |
| ④ | 假二进制输出坏 `panelValid=2` + **L76 的判定条件被放宽**（`^[01]$` → `^[0-9]+$`）（⚠ L76 **已有牙**） | 0 | **1 / 0 / 4** | ⇒ ⇒ ⇒ **归因坐实**：判据层的红绿差别**只取决于有没有门项钉住这一行** |

⚠⚠⚨ **④ 是决定性的归因对照**：**同一手法**（放宽判定条件）⇒ ⇒ 在**已有牙**的那条上
判据层**红**（接线门 rc=1 / 审计器 rc=4「次数门配准失准」）⇒ ⇒ 在**没牙**的那条上判据层**全绿**
⇒ ⇒ ⇒ 所以「洞在哪儿」不是靠猜，是靠**同手法对照**坐实的。

⚠ **恒真探针抓不住这一类**（批 EH 纪律）：shell 侧的恒真只认 `true` / `false` / `:` 三种字面形态
⇒ ⇒ **放宽正则**（`^[0-9]+,…$` → `^[0-9,]+$`）**不算恒真** ⇒ ⇒ ⇒ 这一类洞**只有整行锚定能抓**。

⚠ **修法（落门 18 条，批 EJ-4 段）**：平台探针的**判定条件 18** 条
（`arch_need_count` **整行锚定**：L25 / L39 / L56 / L65 / L80 / L84 / L88 / L91 / L104 /
L140 / L154 / L173 / L187 / L198 / L205 / L209 / L221 / L237）
⚠ **已有牙的 5 条不重复落**（批 EJ-1 / EJ-3 同款纪律）
⚠ 零新门型（`arch_need_count` 早已在册 ⇒ ⇒ 门型注册表 **16 不变**）

⚠⚠⚨ **本批踩过的坑（都记下来）**：
① **普查口径的两次错** ⇒ ⇒ 第一次：引号状态机只跟 `'`/`"` 两个布尔量 ⇒ ⇒
`"$( … python3 -c " … )"` 的**嵌套**让它失真 ⇒ ⇒ python 正文被**误判成 shell 层**
⇒ ⇒ ⇒ 必须用**栈**（引号 / 反引号 / 命令替换 / 括号各自压栈）
② 第二次：`no "…"` 这种**失败上报调用**不在 `✗` / `fail=` 里 ⇒ ⇒ 初版口径**漏判**
⇒ ⇒ ⇒ 「带失败上报」的判据要**认调用形态**
③ **归因器漏了一族门型**（`arch_need_any_count` 的参数形态不同 ⇒ ⇒ 只抽「第一个单引号组」
⇒ ⇒ 那一族根本没进候选 ⇒ ⇒ 只能说「未能归因」⇒ ⇒ 等于没归因 ⇒ ⇒ 改成**全收所有单引号组**
④ **不同文件里可能有字面完全相同的 RX**（实测：`probe-agent-tool-surface.sh` 与
`ci-platform-probe.sh` 都有 `^if \[ "\$PROBE_RC" -ne 0 \]; then$` ⇒ ⇒ 两道门**都合法**
⇒ ⇒ 但 RX 文本**不唯一** ⇒ ⇒ 归因会指错 ⇒ ⇒ **负控片段必须取自说明文字**（带行号 ⇒ 天然唯一）
⑤ **恒假条件也会被恒真探针抓**（`SH_CONST` 含 `false`）⇒ ⇒ 中性化变异**不能**写 `false`
⇒ ⇒ ⇒ 只能用「放宽」形态（改比较、改阈值、删子句）⇒ ⇒ ⇒ 那也正是真实的假绿形态

⚠ **负控 19 真红**（累计 **117 → 136**）：NC118–NC135 平台探针的判定条件 18 处逐条**放宽**
（**双断言**：该判定行门项**红** **且** 同段另一条判定行门项**仍然绿**
⇒ ⇒ **证明「这一条」而不是「这一族全塌」**）｜**NC136**（正向对照·不变异）接线门绿。

⚠ **数字（实测）**：门项条数 **1515 → 1533**（**四处同改**）、执行次数 **1518 → 1536**（+18）、
恒真 **1062 → 1063**（+1 = 批 EJ-4 段 trailer 的自指条件）、
段级 trailer `ARCH_ANY_FAIL=1` **85 → 86** / `ARCH_FAIL=0` **86 → 87**、
批 EF 两条 trailer 门项 **85 → 86**（**自指**）、豁免表 **21 不变**、
门型注册表 **16 不变**、`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、
盘点登记册 **34 不变**、盘点 21 组 / 73 处不变；负控 **117 → 136**。

⚠⚠⚨ **如实记着的已知边界**：
⚠ **`check-deb-layout.sh` 14 条 + `contract-check.sh` 23 条**判定行**没有牙** ⇒ ⇒ 属**下一批**的活
⚠ **平台探针的「抽取口径」11 条没有牙**（`APP_ALIVE` / `BACKEND_KIND` / `TASKBAR_INSETS` /
`SCREEN_RECT` / `TARGET_RECT` / `PANEL_RECT` / `PANEL_EDGE` / `dpi_a_dpr` / `dpi_a_nums` /
`dpi_b_dpr` / `ICON_THEME` 的抽取行；`PANEL_VALID` / `ICON_MISSING` / `dpi_b_legacy` /
`dpi_b_aware` **已有牙**）⇒ ⇒ ⚠ **它们是二阶**：抽取被改坏时，**条件那一侧会红**
（格式校验挡住）⇒ ⇒ ⇒ 所以判据条件才是**承重腿** ⇒ ⇒ 但 `ICON_THEME` 那条**没人挡** ⇒ ⇒ 记着
⚠ **平台探针 awk 正文里的几何比较**（`tx1 < sx1 || …`）**在引号里** ⇒ ⇒ 不是 shell 层
⇒ ⇒ ⇒ 本批的「判定行」口径**不包含**它 ⇒ ⇒ ⇒ 它**没人守** ⇒ ⇒ 记着
⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。

### E.2cw deb 布局验收的判定行必须逐条钉住（判定行 14 条 ⇒ ⇒ 「包验收的失败不许被吞掉」这条承诺一条门都没有 ⇒ ⇒ 条件放宽 ⇒ ⇒ 假绿）

⚠⚠⚨ **范围按脚本切分（一个脚本一个承诺）**：批 EJ-4 的普查把「shell 层判定行」在三个脚本里
各数了一遍 ⇒ ⇒ `contract-check.sh` **23** 条、`ci-platform-probe.sh` **18** 条、
`check-deb-layout.sh` **14** 条**没有牙** ⇒ ⇒ 本批只做 **deb 布局验收**这**一个脚本**的 **14** 条
⇒ ⇒ **契约门那 23 条留 EJ-6**（⚠ 那 23 条里 **16** 条是「取数失败守卫」
⇒ ⇒ 中和后**下游 `check` 可能接住空载荷** ⇒ ⇒ **是不是假绿要逐条实测** ⇒ ⇒ 不能照抄本批结论）。

⚠ **已有牙的 1 条不重复落**（批 EJ-1 / EJ-3 / EJ-4 同款纪律）：L159
（`if [ "$VRC" -ne 0 ]; then` ⇒ 「--version 退出码非 0 ⇒ 判失败」）**早就有牙**
（批 BX 落的）⇒ ⇒ 本批落的是其余 **14** 条。
⚠ 零新门型（`arch_need_count` 早已在册 ⇒ ⇒ 门型注册表 **16 不变**）。

⚠⚠⚨ **决定性实验（修前证据，scratch 树 + 假 deb 注入真实失败，4 例全成立）**：
⚠ **为什么用「假 deb」注入真实失败**（**不改任何产品代码**）：布局验收的输入是**真实 deb 产物**
⇒ ⇒ 要造「本来就该红」的场景 ⇒ ⇒ **只能换掉输入** ⇒ ⇒ ⇒ **产品代码零改动** ⇒ ⇒ 快照零变化。
⚠ **假 deb 怎么造**：`dpkg-deb --build --root-owner-group` 本机可用 ⇒ ⇒ 用一个最小包
（`DEBIAN/control` + `usr/bin/deepDolphin` + `desktop` + `service` + `metainfo` + 一个非空图标）
⇒ ⇒ 好包布局门 **10/10 全过**；**假包 A** = 追加一个**零字节**图标 ⇒ ⇒ 精确触发 ⑨ 一条；
**假包 B** = binary 退出码 **1** **且 stdout 有输出** ⇒ ⇒ 精确触发 ⑧ 一条。

| # | 变异 | 布局门 rc | 判据层（接线门 / 恒真 / 审计） | 结论 |
|---|---|---|---|---|
| ① | 基线 + **真实失败**（假包 A：零字节图标） | **1** | 0 / 0 / 0 | ✓ 「包内存在零字节图标（装了也是空白）」出现 ⇒ ⇒ **真断言抓住了** |
| ② | 同① + **L173 的条件被中和**（`-eq 0` → `-eq 1`） | **0** | **0 / 0 / 0** | ⚠⚠⚨ **假绿坐实**（零字节图标被放行）⇒ ⇒ 而**判据层全绿** ⇒ ⇒ **洞对判据层完全不可见** |
| ③ | 换一个真实失败（假包 B：binary 退出码 1 且 stdout 有输出） | **1** | 0 / 0 / 0 | ✓ 「失败是真的，不是环境坏掉」 |
| ④ | 假包 B + **L159 的条件被中和**（`-ne 0` → `-ne 1`，⚠ L159 **已有牙**） | 0 | **1 / 0 / 4** | ⇒ ⇒ ⇒ **归因坐实**：判据层的红绿差别**只取决于有没有门项钉住这一行** |

⚠ **② 是决定性的**：**同一个手法**（中和条件）⇒ ⇒ 在**没牙**的那条上判据层**全绿**
⇒ ⇒ 在**已有牙**的那条上判据层**红**（④）⇒ ⇒ ⇒ 所以「洞在哪儿」不是靠猜，是靠**同手法对照**坐实的。
⚠ **假包 B 的 binary 必须「退出码 1 且 stdout 有输出」**（批 EJ-5 踩到的坑）：
⇒ ⇒ 否则中和 L159 后 `VOUT` 为空 ⇒ ⇒ 被 ⑧ 的 `elif`（L161）接住 ⇒ ⇒ 仍红 ⇒ ⇒ **假绿形态不成立**。

⚠ **恒真探针抓不住这一类**（批 EH 纪律）：shell 侧恒真只认 `true` / `false` / `:` 三种字面形态
⇒ ⇒ **放宽条件**不算恒真 ⇒ ⇒ ⇒ 这一类洞**只有整行锚定能抓**。

⚠ **修法（落门 14 条，批 EJ-5 段）**：deb 布局验收的**判定行 14** 条（`arch_need_count` **整行锚定**）：
L35（用法错守卫）/ L39（工具缺席守卫）/ L48（解包失败守卫）/ L77（可执行）/ L80（D-Bus service 缺失）/
L108（desktop 缺失）/ L117（desktop 的 Exec）/ L121（Icon 键）/ L131（DBusActivatable）/
L132（service 落点）/ L138（metainfo 缺失）/ L150（--version 那一项）/ L161（--version 没输出）/
L173（图标非空）。

⚠⚠⚨ **本批踩过的坑（都记下来）**：
① **变异落点必须做子串替换**（整行替换 ⇒ 行被截断 ⇒ **语法坏** ⇒ ⇒ **用例无效**
⇒ ⇒ 批 EJ-5 首次的 EJ5-2 即因此无效 ⇒ ⇒ 改成子串替换后重跑全绿）
② **RX 必须从源文件自身提取**（零手打汉字 ⇒ 码位必然一致；且源里的**单引号**要用 `.` 匹配
⇒ ⇒ 审计器用 `([^']*)` 解析 ⇒ ⇒ **RX 不许含单引号**）
③ **字面竖线写 `[|]`**（绝不写 `\|`）
④ **整行锚定的 RX 必须带源行缩进**（`^    if …`）
⑤ **说明文字里的数字只在目标门项行内改**（别的批次的**历史数字不动**）。

⚠ **负控 15 真红**（累计 **136 → 151**）：NC137–NC150 判定行 14 处逐条**放宽 / 反相**
（**双断言**：该判定行门项**红** **且** 同段另一条判定行门项**仍然绿**
⇒ ⇒ **证明「这一条」而不是「这一族全塌」**）｜**NC151**（正向对照·不变异）接线门绿。

⚠ **数字（实测）**：门项条数 **1533 → 1547**（**四处同改**）、执行次数 **1536 → 1550**（+14）、
恒真 **1063 → 1064**（+1 = 批 EJ-5 段 trailer 的自指条件）、
段级 trailer `ARCH_ANY_FAIL=1` **86 → 87** / `ARCH_FAIL=0` **87 → 88**、
批 EF 两条 trailer 门项 **86 → 87**（**自指**）、豁免表 **21 不变**、
门型注册表 **16 不变**、`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、
盘点登记册 **34 不变**、盘点 21 组 / 73 处不变；负控 **136 → 151**。

⚠⚠⚨ **如实记着的已知边界**：
⚠ **`contract-check.sh` 23 条**判定行**没有牙** ⇒ ⇒ 属**下一批**（EJ-6）的活
（⚠ 其中 **16** 条是「取数失败守卫」⇒ ⇒ 中和后**是不是假绿要逐条实测** ⇒ ⇒ 不能照抄本批结论）
⚠ **平台探针的「抽取口径」11 条没有牙**（⚠ **二阶** —— 抽取被改坏时**条件那侧会红**
⇒ ⇒ 判据条件才是承重腿，但 `ICON_THEME` 那条没人挡）
⚠ **平台探针 awk 正文里的几何比较**（`tx1 < sx1 || …`）**在引号里** ⇒ ⇒ 不是 shell 层 ⇒ ⇒ 没人守
⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。

### E.2cx 契约门的判定行必须逐条钉住（判定行 23 条 ⇒ ⇒ 「契约门的失败不许被吞掉」这条承诺一条门都没有 ⇒ ⇒ 条件放宽 ⇒ ⇒ 假绿）

⚠⚠⚨ **范围（批 EJ-4 普查 + 批 EJ-6 逐条实测）**：契约门（`contract-check.sh`）的
**判定行**（带失败上报的）共 **25** 条 ⇒ ⇒ 那 **2** 条**早就有牙**
（批 CI 落的 `E2E_N` 取数守卫 / 末尾「有未验证 ⇒ exit 3」判定）⇒ ⇒ ⇒ **不重复落**
⇒ ⇒ 其余 **23** 条**没有牙** ⇒ ⇒ 本批落门 **23** 条。

⚠ **怎么注入真实失败（不改任何产品代码）**：契约门的输入是「引擎 + 客户端」
⇒ ⇒ 要造「本来就该红」的场景 ⇒ ⇒ **只能换掉输入** ⇒ ⇒ ⇒ **假引擎 / 假客户端**
（其余原样转发；`DEEPGIT_BIN` 指向假引擎、客户端位置参数指向假客户端）
⇒ ⇒ ⇒ **产品代码零改动** ⇒ ⇒ 快照零变化。
⚠ 假引擎能做的事：让某条命令返回**空载荷** / 返回**改写过的载荷**（如
`index update` 第二次不给 `indexJson`）。
⚠ 假客户端能做的事：让某个 flag 返回**错的值**（如 `--code-graph-symbol-id`）、
让 `--engine-download` **额外制造「坏客户端」行为**（落下坏引擎 / 留下旁路残留）
⇒ ⇒ ⚠ **先转发真客户端**再补那一个缺陷 ⇒ ⇒ 同一组里别的断言行为**保持不变**。

⚠⚠⚨ **决定性实验 12 例（修前证据）**：
| # | 场景 | 判定行 | 基线 | 中和后 | 结论 |
|---|---|---|---|---|---|
| ①/② | 两边工具清单都抓不到 | **L232** | rc=1（`✗ 第 12 组前提`） | **rc=0（120 passed / 0 failed）** | ⚠⚠⚨ **假绿坐实** |
| ③/④ | 客户端造的符号 id 与引擎不一致 | **L326** | rc=1（`✗ 符号 id 端到端`） | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ⑤/⑥ | 索引重建后没给 `indexJson` 落盘路径 | **L816** | rc=1 | **rc=0（119 passed）** | ⚠⚠⚨ **假绿坐实** |
| ⑦/⑧ | 校验和不匹配却落了盘 | **L900** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ⑨/⑩ | 装坏包后留下旁路/备份残留 | **L952** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ⑪/⑫ | 引擎缺席 | **L35** | **rc=3**（专属码 3 · 未验证） | **rc=1**（`✗ 引擎探活失败`） | ⚠ **专属码语义被顶替** |

⚠ **归因实验（同一手法 ⇒ 用在**早就有牙**的那条上）**：中和 **L323**（`E2E_N` 取数守卫 ⇒ ⇒
**批 CI 就落的**）⇒ ⇒ **接线门 rc=1**（正是「契约门取数失败不许落进『判通过』那一支」那条门项红）
⇒ ⇒ 还原后 rc=0 ⇒ ⇒ ⇒ **归因坐实**：红绿差别**只取决于有没有门项钉住这一行**。

⚠ **中和手法（通用）**：给条件加一个**与原条件矛盾**的合取项
（`-z "$V"` ⇒ 加 `[ -n "$V" ]`；`-n "$V"` ⇒ 加 `[ -z "$V" ]`；`-e "$P"` ⇒ 加
`[ ! -e "$P" ]`；`"$V" -ne N` ⇒ 加 `[ "$V" -eq N ]`）
⇒ ⇒ 守卫变成**恒惰性** ⇒ ⇒ 正常态**仍然是绿的**（不引入恒红）
⇒ ⇒ ⚠ 只用**脚本里已经有的变量**（契约门带 `set -u` ⇒ 不能引入新变量）。

⚠⚠⚨ **实测档位（逐条 ⇒⇒ 不同档的后果不同 ⇒⇒ 如实记着，不一概而论）**：
⚠ **为什么必须分档**：批 EJ-4 留的明账是「16 条『取数失败守卫』⇒ ⇒ 中和后**是不是假绿要逐条实测**，
因为下游 `check` 可能接住空载荷」⇒ ⇒ 本批**逐条实测**（每条：注入真实失败 ⇒ ⇒ 基线必须红
⇒ ⇒ 中和后看 **rc + 那条「前提失败」消息还在不在**）。
⚠ **判档不能只看失败条数**：条数不变也可能是「消息变了」（诊断变差）⇒ ⇒ 判据 =
**那条「前提失败」消息还在不在** + **rc 变没变**。

| 档 | 条数 | 弱化后的**实测**后果 | 判定 |
|---|---|---|---|
| **A** | **5**（L232 / L326 / L816 / L900 / L952） | 那条失败被报成「通过」⇒ ⇒ 契约门 **rc=0（120 passed / 0 failed）** | ⚠⚠⚨ **真·假绿** |
| **B** | **1**（L35） | 「未验证 ⇒ 专属码 3」被顶替成「真实失败 ⇒ 专属码 1」 | ⚠ **码值语义被改弱** |
| **C** | **14**（L350 / L384 / L424 / L467 / L502 / L559 / L619 / L638 / L684 / L744 / L774 / L791 / L806 / L822） | 那条失败**仍被报出来**（下游 `check` 在空载荷上自己判红）⇒ ⇒ 前提消息没了、失败条数反而**变多** | ⚠ **不是假绿**，是**诊断变差** |
| **D** | **2**（L1008 / L1081） | 那一项变成**未验证**（专属码 3）⇒ ⇒ 不算通过 | ⚠ **fail-closed** |
| **E** | **1**（L598） | **没有任何后果**（这条守卫**自己就是死代码**） | ⚠ 如实记着 |

⚠ **档 A 为什么能假绿、档 C 为什么不能**（**这一条是本批最值钱的认识**）：
**下游断言的形状决定后果** ⇒ ⇒ 下游是 **shell 判定**的（`comm` 差集 / `-e` 存在性 /
`-ne` 计数）⇒ ⇒ **空载荷也被它判成「通过」** ⇒ ⇒ 假绿；
下游是 **`check` / `check_text`**（JSON 解析 / grep）的 ⇒ ⇒ **空载荷上它们自己判红**
⇒ ⇒ 失败**仍被报出来** ⇒ ⇒ 只丢了那条「第 N 组前提」的消息（**诊断变差**，不是假绿）。

⚠⚠⚨ **本批踩过的坑（都记下来）**：
① ⚠ **L32 与 L35 的源行文本**完全相同**（都是 `if [ -z "$BIN" ]; then`）
⇒ ⇒ **整行锚定会同时命中 2 条** ⇒ ⇒ 门项数不是 1 ⇒ ⇒ 门是错的
⇒ ⇒ **L35 改用跨行门型 `arch_need_count_ml`**（批 EF 立的那个门型）
⇒ ⇒ RX = 「守卫 ⇒ 那条 `SKIP contract-check：…` 消息」的**跨行关系**（压行后命中恰好 1 次）
② ⚠ **变异落点必须按行号替换**（不是按文本！）⇒ ⇒ L32/L35 同文本 ⇒ 按文本 replace 会改到**前一行**
⇒ ⇒ 实测症状：中和 L35 后仍然是 rc=3（SKIP 那条分支根本没被惰性化）
③ ⚠ **假客户端要先转发真客户端**再补缺陷 ⇒ ⇒ 否则回执变空 ⇒ ⇒ 同一组里**别的断言**先红
⇒ ⇒ 归因会指错（实测：L900 那次中和后仍是 rc=1，失败的是**兄弟断言**不是 L900）
④ ⚠ **契约门基线偶发 1 处未验证**（`‣ SKIP 第 21 组真 API 那条：GitHub API 不可达（网络问题）`）
⇒ ⇒ 是**环境侧**（API 限流）⇒ ⇒ 契约门**如实报未验证**（rc=3）⇒ ⇒ 前后对比时它是个**常数项**
⑤ ⚠ **`set -u` 禁止引入新变量** ⇒ ⇒ 惰性化只能用**脚本里已有的变量**
⑥ ⚠ **判档不能只看失败条数**（见上）

⚠ **修法（落门 23 条，批 EJ-6 段）**：`contract-check.sh` 的**判定行 23** 条
（**22** 条 `arch_need_count` 整行锚定 + **1** 条 `arch_need_count_ml` 跨行锚定 = L35）。
⚠ 零新门型（`arch_need_count` / `arch_need_count_ml` 早已在册 ⇒ ⇒ 门型注册表 **16 不变**）。

⚠ **负控 24 真红**（累计 **151 → 175**）：NC152–NC174 判定行 23 处逐条**惰性化**
（**双断言**：该门项**红** **且** 同段另一条门项**仍然绿**
⇒ ⇒ **证明「这一条」而不是「这一族全塌」**）｜**NC175**（正向对照·不变异）接线门绿。

⚠ **数字（实测）**：门项条数 **1547 → 1570**（**四处同改**）、执行次数 **1550 → 1573**（+23）、
恒真 **1064 → 1065**（+1 = 批 EJ-6 段 trailer 的自指条件）、
段级 trailer `ARCH_ANY_FAIL=1` **87 → 88** / `ARCH_FAIL=0` **88 → 89**、
批 EF 两条 trailer 门项 **87 → 88**（**自指**）、豁免表 **21 不变**、
门型注册表 **16 不变**、`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、
盘点登记册 **34 不变**、盘点 21 组 / 73 处不变；负控 **151 → 175**。

### E.2cy 抽取口径行与 `case` 判定行必须逐条钉住（抽取口径 13 条 + `case` 判定 3 条 ⇒ ⇒ 「判据的取值口径不许被改坏」与「`case` 分档不许被放宽」这两条承诺一条门都没有 ⇒ ⇒ 抽坏 / 放宽 ⇒ ⇒ 假绿）

⚠⚠⚨ **范围（批 EJ-7 普查：严格复用 EJ-4 口径，只加 `case` 形态）**：
⚠ **普查口径的洞**：批 EJ-4 / EJ-5 / EJ-6 的普查**只认 `if` / `elif`**
⇒ ⇒ **`case` 形态从未被普查过** ⇒ ⇒ 探针 **2** 条（`backendKind` / `panelEdge` 分档）
+ deb 布局 **1** 条（`SPATH` 绝对路径分档）**没人管**
⇒ ⇒ **抽取口径行**也从未被普查过 ⇒ ⇒ 探针 **12** 条（从客户端输出里抽字段的那 12 行）
+ deb 布局 **1** 条（`metainfo` 的 app id）**没人管**
⇒ ⇒ 合计 **16** 条**没有牙**（实测：改这一处 ⇒ ⇒ 接线门照样绿 ⇒ ⇒ rc=0）。
⚠ **不重复落**：`PANEL_VALID` / `ICON_MISSING` / `dpi_b_legacy` / `dpi_b_aware` 那 **4** 条
**早就有牙**（批 DI / 批 DJ 落的抽取口径门）⇒ ⇒ 本批不落。
⚠ **契约门顺带核过**：用修正后的普查口径重跑，契约门 **25** 条判定行**全部有牙**
⇒ ⇒ ⇒ 批 EJ-6 落的 23 条 + 早就有牙的 2 条 ⇒ ⇒ **覆盖完整**。

⚠ **怎么注入真实失败（不改任何产品代码）**：
探针的输入是**客户端 `--platform-probe` 的输出** ⇒ ⇒ 要造「本来就该红」的场景
⇒ ⇒ ⇒ **只能换掉输入** ⇒ ⇒ ⇒ **假客户端**（`--platform-probe` 时接管，**其余原样转发真客户端**）
⇒ ⇒ deb 布局的输入是**deb 包** ⇒ ⇒ ⇒ **假 deb**（`dpkg-deb --build`）
⇒ ⇒ ⇒ **产品代码零改动** ⇒ ⇒ 快照零变化。

⚠⚠⚨ **决定性实验 16 例（逐条实测分档 ⇒⇒ 不一概而论）**：
| # | 场景 | 判定行 | 基线 | 改坏后 | 结论 |
|---|---|---|---|---|---|
| ① | 有图标主题但图标解析不到 | **L219**（`ICON_THEME` 抽取） | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ② | `backendKind` 不是 x11/wayland/other | **L46**（`case` 分档） | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ③ | `panelEdge` 不是 top/right/bottom/left/unknown | **L95**（`case` 分档） | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ④～⑯ | 其余 **13** 条（抽取口径 10 + 抽取口径 1 + `case` 1） | … | rc=1 | rc=1 | ⚠ **诊断变差**（**11** 条）／ **无影响**（**2** 条） |

⚠ **档位含义**：
- **档 A（3 条：L46 / L95 / L219）** ⇒ ⇒ 那个失败**被静默吞掉** ⇒ ⇒ 探针 rc=0 照样打「✓ 平台探针通过」⇒ ⇒ ⚠⚠⚨ **假绿坐实**
- **档 C（11 条）** ⇒ ⇒ 那个失败**仍被报出来**（下游那道**格式校验 / `case` 分档**自己判红）⇒ ⇒ ⚠ **不是假绿**，是**诊断变差**
  （⚠ deb 布局 `SPATH` 那条：第 ③ 条「Exec 指向的可执行不在包内」仍报红 ⇒ ⇒ 掩盖了「不是绝对路径」那条消息）
- **档 E（2 条：L139 / L144）** ⇒ ⇒ 消息与退出码**都没变** ⇒ ⇒ ⚠ **没有任何后果**

⚠⚠⚨ **归因实验（落门前 / 落门后，同一处变异、同一处真实失败）**：
| 变异 | 旧判据层 | 新判据层 | 结论 |
|---|---|---|---|
| `L219` 抽取改坏 | rc=0 | **rc=1** | ⇒ ⇒ **归因坐实** |
| `L46` 接受列表放宽 | rc=0 | **rc=1** | ⇒ ⇒ **归因坐实** |
| `L95` 接受列表放宽 | rc=0 | **rc=1** | ⇒ ⇒ **归因坐实** |
| `L141` 抽取改坏 | rc=0 | **rc=1** | ⇒ ⇒ **归因坐实** |
| ⚠ 对照组：`L220`（**早就有牙**）同一手法 | rc=1 | rc=1 | ⇒ ⇒ 两版都红 ⇒ ⇒ **红绿差别只取决于有没有门项钉住这一行** |

⚠⚠⚨ **修法（落门 16 条，批 EJ-7 段）**：
- **抽取口径行（13 条）** ⇒ ⇒ `arch_need_count` **整行锚定**
  （⚠ 这些源行含**单引号** ⇒ ⇒ 门项正则里不许有单引号 ⇒ ⇒ 用 `.` 匹配引号；⚠ 除引号外**逐字**钉住
  ⇒ ⇒ 抽坏 ⇒ ⇒ 命中数掉 ⇒ ⇒ 必红）
- **`case` 判定行（3 条）** ⇒ ⇒ `arch_need_count_ml` **跨行锚定**
  （⚠ 一个 `case` 构造的**判定内容**横跨 4～7 行：判据头 + 接受列表 + 失败上报 + `exit` + `esac`
  ⇒ ⇒ 整行锚定**只钉得到其中一行** ⇒ ⇒ 必须把**整个构造**钉住 ⇒ ⇒ 用**批 EF 立的那个门型**）
⇒ ⇒ ⚠ **零新门型**（门型注册表 **16 不变**）。

⚠⚠⚨ **本批踩过的坑**：
① **普查口径必须严格复用 EJ-4 原始函数**（只加 `case` 形态）⇒ ⇒ 自写口径会把 SKIP 守卫算成候选，
   且静态判牙齿对 `_ml` 门型失效（⇒ 误报 L35 已落门）
② **假客户端的默认值不能带缺陷** ⇒ ⇒ 默认 `iconMissing=0` ⇒ ⇒ 否则**每个场景都被它掩盖**
   （第一版默认 `3` ⇒ L46/L95 的后果全被 L219 的失败吃掉 ⇒ ⇒ 分档是假的）
③ **假 deb 的相对路径要选「文件确实在包内」的那种**（`usr/bin/deepDolphin`）
   ⇒ ⇒ 裸名（`deepDolphin`）会被第 ③ 条「不在包内」**掩盖** ⇒ ⇒ 场景无效
④ **假客户端的算术不能被非法 DPR 搞崩** ⇒ ⇒ `$((8 * x))` 会让假客户端自己退出 1
   ⇒ ⇒ 探针在**更早**的一步就红了 ⇒ ⇒ 被测那条断言**根本没跑到** ⇒ ⇒ 伪装成「无影响」
⑤ **`case` 判定行的落点在**接受列表**那一行**（不是判据头那一行）⇒ ⇒ 门项必须跨行才钉得住
⑥ **门项定位用字面子串**（`in`）而不是正则 ⇒ ⇒ 正则**中间**的 `^` 会被当成锚点
   ⇒ ⇒ 且源文件里那些 RX 本身含 `\` `[` `]` ⇒ ⇒ 每个都要**再加一层**转义

⚠ **负控 17 真红**（累计 **175 → 192**）：NC176–NC191 抽取口径 / `case` 判定 **16** 处逐条**改坏**
（**双断言**：该门项**红** **且** 同段另一条**仍然绿**）｜NC192 正向对照绿。

⚠⚠⚨ **数字（实测）**：门项条数 **1570 → 1586**（**四处同改**）、执行次数 **1573 → 1589**、
恒真 **1065 → 1066**、`ARCH_ANY_FAIL=1` **88 → 89**、`ARCH_FAIL=0` **89 → 90**、
批 EF 两条 trailer **88 → 89**、豁免表 **21 不变**、门型注册表 **16 不变**、
`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、盘点登记册 **34 不变**、
盘点 21 组 / 73 处不变；负控 **175 → 192**。

⚠⚠⚨ **如实记着的已知边界**：
⚠ **平台探针 awk 正文里的几何比较**（`tx1 < sx1 || …`）**在引号里** ⇒ ⇒ 不是 shell 层 ⇒ ⇒ 没人守
⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。
### E.2cz 探针 awk 正文里的判定行必须逐条钉住（判定行 10 条 ⇒ ⇒ 「结构事实与几何事实不许被改坏」这条承诺一条门都没有 ⇒⇒ 中和 ⇒⇒ 假绿）

⚠⚠⚨ **范围（批 EJ-8 普查：新增「引号内程序正文」这一形态）**：
批 EJ-4 / EJ-5 / EJ-6 / EJ-7 的普查**只认 shell 层**
（引号状态机栈为空 ⇒ 多行 `awk '...'` 的正文**整段被排除**）
⇒ ⇒ **正文里的判定行从来没被普查过**
⇒ ⇒ 探针里有 **3** 段 awk 正文、**10** 条判定行**一条门都没有**
（实测：改这一处 ⇒ ⇒ 接线门照样绿 ⇒ ⇒ rc=0）。
⚠ **范围只到探针**：契约门与 deb 布局的「引号内程序正文」**都是 0 行**
⇒ ⇒ 契约门的 python heredoc 正文**不在引号里** ⇒ ⇒ 早被 EJ-4 扫过
⇒ ⇒ ⚠ **单行 awk**（`awk '{ … }'`）**整行都在 shell 层** ⇒ ⇒ 已被整行锚定覆盖 ⇒ ⇒ **不重复落**
⇒ ⇒ 探针里那 **2** 条 `exit 1`（L166 / L170）**早就有牙**（被「失败上报语句条数」那道计数门看着）
⇒ ⇒ ⇒ 本批**不重复落**。

⚠ **怎么注入真实失败（不改任何产品代码）**：
探针的输入是**客户端 `--platform-probe` 的输出**
⇒ ⇒ ⇒ **只能换掉输入** ⇒ ⇒ ⇒ **假客户端**（其余原样转发真客户端）
⇒ ⇒ ⇒ **产品代码零改动** ⇒ ⇒ 快照零变化。

⚠⚠⚨ **决定性实验 10 例（逐条实测分档 ⇒⇒ 不一概而论）**：
| # | 场景 | 判定行 | 基线 | 改坏后 | 结论 |
|---|---|---|---|---|---|
| ① | 弹窗落点不在屏幕内 | **L111**（几何包含比较） | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ② | 同上（改的是**失败上报**那一行） | **L113** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ③ | logical 尺寸非法 | **L162** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ④ | dpr 非法 | **L163** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ⑤ | buffer ≠ logical×dpr | **L164** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ⑥ | 位图 dpr ≠ 应用 dpr | **L168** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ⑦～⑨ | logical / buffer / dpr **抽取口径**被改坏 | **L147 / L148 / L149** | rc=1 | rc=1 | ⚠ **诊断变差**（**3** 条） |
| ⑩ | 字段形状守卫被放宽 | **L146** | rc=1 | rc=1 | ⚠ **没有任何后果** |

⚠ **档位含义**：
- **档 A（6 条）** ⇒ ⇒ 那个失败**被静默吞掉** ⇒ ⇒ 探针 rc=0 照样打「✓ 平台探针通过」⇒ ⇒ ⚠⚠⚨ **假绿坐实**
- **档 C（3 条）** ⇒ ⇒ 那个失败**仍被报出来**（下游那道**形状校验**自己判红）⇒ ⇒ ⚠ **不是假绿**，是**诊断变差**
- **档 E（1 条）** ⇒ ⇒ 消息与退出码**都没变** ⇒ ⇒ ⚠ **没有任何后果**

⚠⚠⚨ **归因实验（落门前 / 落门后，同一处变异、同一处真实失败）**：
`L111` / `L113` / `L146` / `L147` / `L162` / `L164` / `L168` 七条**逐条**旧 **rc=0** ／ 新 **rc=1**
⇒ ⇒ **归因坐实**；⚠ 对照组 `L166`（**早就有牙**）同一手法 ⇒ ⇒ **两版都红**
⇒ ⇒ ⇒ **红绿差别只取决于有没有门项钉住这一行**。

⚠⚠⚨ **修法（落门 10 条，批 EJ-8 段）**：这 **10** 条**每一行都是自洽的一行**
⇒ ⇒ ⇒ `arch_need_count` **整行锚定**（⚠ 不需要跨行门型）⇒ ⇒ ⚠ **零新门型**。

⚠⚠⚨ **本批踩过的坑**：
① **普查口径要按「栈顶」判引号态**：判据**不是**「栈 == ['sq']」⇒ ⇒ `awk '{…}'` 写在
   `"$( … )"` 里时行首栈是 **[dq, cmdsub, sq]** ⇒ ⇒ 用 `== ['sq']` 会**漏掉整段**
   （第一版就漏了 `dpi_struct_assert` 里那一整段 ⇒ ⇒ 修正后才看到 3 段 12 行）
② **假客户端的 `DPI_PIXMAP` 覆盖同时作用于两跑** ⇒ ⇒ 第二跑会因 dpr 不一致**先红**
   ⇒ ⇒ **掩盖**了第一跑的后果 ⇒ ⇒ ⚠⚠⚨ **L162 / L164 的真·假绿被伪装成「诊断变差」**
   ⇒ ⇒ ⇒ 必须给**第二跑单独**设一份一致的 pixmap（`EJ7_DPI_PIXMAP_B`）才隔离得干净
   ⇒ ⇒ ⇒ 这是「**期望写错**和**环境坏掉**长得一模一样」的又一次现身
③ **说明文字的括号要配平**：`pre` 片段**自带**开头的 `（` ⇒ ⇒ 不要再加一个
   （批 EJ-7 修过一次 ⇒ ⇒ 批 EJ-8 又踩了一次 ⇒ ⇒ 改成从**文件自身**抽片段后配平）
④ **门项定位用字面子串**（`in`）而不是正则（沿用批 EJ-7 的教训）

⚠ **负控 11 真红**（累计 **192 → 203**）：NC193–NC202 探针 awk 正文判定行 **10** 处逐条**改坏**
（**双断言**：该门项**红** **且** 同段另一条**仍然绿**）｜NC203 正向对照绿。

⚠⚠⚨ **数字（实测）**：门项条数 **1586 → 1596**（**四处同改**）、执行次数 **1589 → 1599**、
恒真 **1066 → 1067**、`ARCH_ANY_FAIL=1` **89 → 90**、`ARCH_FAIL=0` **90 → 91**、
批 EF 两条 trailer **89 → 90**、豁免表 **21 不变**、门型注册表 **16 不变**、
`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、盘点登记册 **34 不变**、
盘点 21 组 / 73 处不变；负控 **192 → 203**。

⚠⚠⚨ **如实记着的已知边界**：
⚠ **命令替换 `$( )` / 子 shell 里的判定行**：实测三个判据脚本里**都是 0 条**
⇒ ⇒ 那里**没有**同类洞（⚠ 但这个口径只看**行首栈顶** ⇒ 多行命令替换仍需留意）
⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒⇒ 快照零变化）。
⚠⚠⚨ **如实记着的已知边界**：
⚠ **平台探针的「抽取口径」11 条没有牙**（`APP_ALIVE` / `BACKEND_KIND` / `TASKBAR_INSETS` /
`SCREEN_RECT` / `TARGET_RECT` / `PANEL_RECT` / `PANEL_EDGE` / `dpi_a_dpr` / `dpi_a_nums` /
`dpi_b_dpr` / `ICON_THEME`）⇒ ⇒ 属**下一批**（⚠ **二阶** —— 抽取口径被改坏时**条件那侧会红**
⇒ ⇒ 判据条件才是承重腿，但 `ICON_THEME` 那条没人挡）
⚠ **平台探针 awk 正文里的几何比较**（`tx1 < sx1 || …`）**在引号里** ⇒ ⇒ 不是 shell 层 ⇒ ⇒ 没人守
⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒ 快照零变化）。
### E.2da 工具面探针的判定行必须逐条钉住（判定行 14 条 ⇒ ⇒ 「agent 工具面收敛」这条承诺一条门都没有 ⇒⇒ 中和 ⇒⇒ 假绿）
⚠⚠⚨ **范围（批 EJ-9 普查：先量准，再落门）**：
批 EJ-4 ～ EJ-8 的普查**只覆盖 3 个 deepin 判据脚本**
（`ci-platform-probe.sh` / `contract-check.sh` / `check-deb-layout.sh`）
⇒ ⇒ **其余判据层脚本（探针 / 盘点 / 审计器 / CI 入口…）从没被普查过**
⇒ ⇒ 批 EJ-9 先**量准口径**：静态普查 **45** 个脚本（deepin 24 + linux 10 + macos 11）
⇒ ⇒ 得出 **542** 条候选判定行 ⇒ ⇒ 再用**门侧同口径**（GNU `grep -nE`）做**静态预筛**
⇒ ⇒ **258** 条**裸奔**（没有任何门项的 RX 命中它们）
⇒ ⇒ 本批选定 `probe-agent-tool-surface.sh`（**14** 条裸奔判定行）：
选它的理由是三条**同时**成立 ⇒ ① 它承诺的是**产品级**承诺（模型可见面 / 提示词口径）
⇒ ② 它有一条**干净**的真实失败注入路（**假客户端**：输入只有 `--agent-tool-surface` 的输出）
⇒ ③ 它**已有**的门项只覆盖**外围**（断言清单条数 / 失败上报条数 / 一条抽取口径 / 一条格式校验）
⇒ ⇒ **判定行本身一条没钉**
⚠ ⚠ **别的裸奔项为什么不在这批**（**如实记着**，免得下批照着假清单排活）：
`ci-wiring.sh` 自身 **35** 条（enforcer 自己 ⇒ ⇒ **自指** ⇒ ⇒ 要单独设计）｜
`macos/build.sh` **22** 条（macOS-only ⇒ ⇒ 本机**不可注入真实失败**）｜
`.py` 判据脚本（`ci-tautology-check.py` **64** / `ci-unverified-audit.py` **18** /
`ci-wiring-audit.py` **15**）—— ⚠ **这三个数字口径不准**（shell 口径的 `block_end` 按
`fi` / `else` 配对 ⇒ ⇒ 对 Python **不适用** ⇒ ⇒ **必须先修普查口径再动**）
⚠ **预筛自身的盲区（如实记着）**：预筛**跳过 `_ml` 族**（跨行门型）⇒ ⇒ 已知被 `_ml` 钉住的
4 行（探针 L46 / L95、deb 布局 L85、契约门 L35）在预筛里显示为「裸奔」⇒ ⇒ **是预筛盲区，不是洞**
⇒ ⇒ ⇒ 预筛结论**必须**配合**实测牙齿**一起读。

⚠ **怎么注入真实失败（不改任何产品代码）**：
探针的输入是**客户端 `--agent-tool-surface` 的输出**
⇒ ⇒ ⇒ **只能换掉输入** ⇒ ⇒ ⇒ **假客户端**（其余原样转发真客户端）
⇒ ⇒ ⇒ 产品代码零改动 ⇒ ⇒ 快照零变化。

⚠⚠⚨ **决定性实验 14 例（逐条实测分档 ⇒⇒ 不一概而论）**：
| # | 场景 | 判定行 | 基线 | 中和后 | 结论 |
|---|---|---|---|---|---|
| ① | 旧名别名仍在模型可见面 | **L110** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ② | 收敛把「还能不能用」也收掉了 | **L114** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ③ | 系统提示词里还列着旧名别名 | **L118** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ④ | 新面工具不在模型可见面 | **L124** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ⑤ | 收敛掉的**恰好**是那些别名（数量不自洽） | **L134** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ⑥ | 任一断言失败却 exit 0 | **L140** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ⑦ | 提示词那一行的**抽取口径**被改坏 | **L72** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ⑧ | 废弃标记**个数**那一行的**抽取口径**被改坏 | **L73** | rc=1 | **rc=3** | ⚠⚠⚨ **降级成「未验证」⇒ CI 照样绿** |
| ⑨ | 「引擎太老 ⇒ SKIP」的**阈值**被放宽 | **L84** | rc=1 | **rc=3** | ⚠⚠⚨ **降级成「未验证」⇒ CI 照样绿** |
| ⑩～⑭ | 探针零输出 / model 抽取口径 / 别名名单抽取口径 / model+validated 非空 / 别名名单非空 | **L64 / L70 / L74 / L76 / L88** | rc=1 | rc=1 | ⚠ **诊断变差**（**5** 条） |

⚠ **档位含义**：
- **档 A（7 条：L72 / L110 / L114 / L118 / L124 / L134 / L140）** ⇒ ⇒ 那个失败**被静默吞掉**
  ⇒ ⇒ 探针 rc=0 ⇒ ⇒ ⚠⚠⚨ **假绿坐实**
- **档 A'（2 条：L73 / L84）** ⇒ ⇒ 探针**降级成 rc=3（SKIP）** ⇒ ⇒ CI 入口判
  「‣ SKIP …未验证」+ `skip++` ⇒ ⇒ **CI 照样绿** ⇒ ⇒ ⚠⚠⚨ **仍是假绿**
  （承诺从「验过了」降级成「没验过」而没人拦）
- **档 C（5 条：L64 / L70 / L74 / L76 / L88）** ⇒ ⇒ 那个失败**仍被报出来**（下游接手）
  ⇒ ⇒ ⚠ **不是假绿**，是**诊断变差**

⚠⚠⚨ **归因实验（落门前 / 落门后，同一处变异）**：
14 条**逐条**旧 **绿（rc=0）** ／ 新 **红（rc≠0）** ⇒ ⇒ **归因坐实**
⇒ ⇒ ⚠ 对照组 `L35`（**早就有牙**）同一手法 ⇒ ⇒ **两版都红**
⇒ ⇒ ⇒ **红绿差别只取决于有没有门项钉住这一行**。

⚠⚠⚨ **修法（落门 14 条，批 EJ-9 段）**：这 **14** 条**每一行都是自洽的一行**
⇒ ⇒ ⇒ `arch_need_count` **整行锚定**（⚠ 不需要跨行门型）⇒ ⇒ ⚠ **零新门型**。

⚠⚠⚨ **本批踩过的坑**：
① **「条件取反」≠「中和」**：把 `if CMD` 改成 `if ! CMD` 只是把判定**判反**
   ⇒ ⇒ 正常场景反而**假红** ⇒ ⇒ 它**不是**「摘掉这道检查」⇒ ⇒ 拿它测出来的分档**失真**
   ⇒ ⇒ 实测证据：L110 取反后，另外 **5** 个**不在**模型面里的别名**全被误报**
   ⇒ ⇒ ⇒ 中和必须是**恒不成立**（用**该行之前已定义**的变量做自比较 ⇒ `set -u` 下也安全）
② **落门插入点有同名标记**：`批 CG` 的段头标记在**文件头说明注释**里也出现一次
   ⇒ ⇒ `replace(..., 1)` 会把**整段插到脚本最前面**⇒ ⇒ 门项行被当命令执行
   ⇒ ⇒ ⇒ 必须取「**批 EJ-8 段之后**的那一个」⇒ ⇒ 且插完必须 `sh -n` + `bash -n`
③ **段级 trailer 有两道门**：单行锚定那道 + 批 EF 跨行那道 ⇒ ⇒ **一个都不能漏**
   ⇒ ⇒ 只改一道 ⇒ ⇒ 审计器 rc=4（次数门没配准）当场抓出来
④ **门项正则里的字面竖线写 `[|]`**（`\|` 在 BSD grep（macOS）里是「或」⇒ ⇒ mac 侧会跑偏）
⑤ **门项正则里不许有单引号**（审计器用 `([^\']*)` 解析）⇒ ⇒ 源行的 `'` 写成 `.`

⚠ **负控 15 真红**（累计 **203 → 218**）：NC204–NC217 工具面探针判定行 **14** 处逐条**改坏**
（**双断言**：该门项**红** **且** 同段另一条**仍然绿**）｜NC218 正向对照绿。

⚠⚠⚨ **数字（实测）**：门项条数 **1596 → 1610**（**四处同改**）、执行次数 **1599 → 1613**、
恒真 **1067 → 1068**、`ARCH_ANY_FAIL=1` **90 → 91**、`ARCH_FAIL=0` **91 → 92**、
批 EF 两条 trailer **90 → 91**、豁免表 **21 不变**、门型注册表 **16 不变**、
`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、盘点登记册 **34 不变**、
盘点 21 组 / 73 处不变；负控 **203 → 218**。

⚠⚠⚨ **如实记着的已知边界**：
⚠ **其余判据层脚本仍未普查**（静态预筛出 **258** 条裸奔 ⇒ ⇒ 本批只收了工具面探针这 **14** 条
⇒ ⇒ ⇒ 下一批从 `ci-docs-lang-probe.sh` / `ci-divider-probe.sh` / `ci-orphan-probe.sh` /
`ci-d2.sh` 里挑）
⚠ **比这批更「重」的裸奔项没做**（**如实记着**，免得下批照着假清单排活）：
`ci-wiring.sh` 自身 **35** 条（**enforcer 自己** ⇒ ⇒ **自指** ⇒ ⇒ 落门要单独设计
⇒ ⇒ 不能照搬本批的「整行锚定」套路）｜`macos/build.sh` **22** 条（macOS-only
⇒ ⇒ 本机**不可注入真实失败** ⇒ ⇒ 要么上真机、要么先造跨平台注入通道）
⚠ **`.py` 判据脚本的裸奔数**（`ci-tautology-check.py` **64** / `ci-unverified-audit.py` **18** /
`ci-wiring-audit.py` **15**）**口径不准** ⇒ ⇒ shell 口径的 `block_end` 按 `fi` / `else` 配对
⇒ ⇒ 对 Python **不适用** ⇒ ⇒ **必须先修普查口径**（Python 的块结束靠**缩进**配对）
⇒ ⇒ **不要照着这三个数字排活**
⚠ **预筛跳过 `_ml` 族** ⇒ ⇒ `_ml` 门型钉住的行在预筛里显示为「裸奔」⇒ ⇒ 预筛结论**必须**配实测
⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒⇒ 快照零变化）。

### E.2db 三态判定机制必须逐条钉住（判定行 22 条 ⇒ ⇒ 「三态判定不许悄悄变弱」这条承诺一条门都没有 ⇒⇒ 中和 ⇒⇒ 假绿）

⚠⚠⚨ **范围（批 EJ-10：enforcer 自己 ⇒ ⇒ 自指 ⇒ ⇒ 要单独设计）**：
批 EJ-9 留下的「`ci-wiring.sh` 自身 **35** 条裸奔」就是本批 ⇒ ⇒
本批把范围收进 **`ci-wiring.sh` 自身的三态判定机制**（**enforcer 自己** ⇒ ⇒ **自指**）：
· rc→state 映射（`probe_scan_state_of`：**0→found / 1→absent / 其它→broken**）
· state→结论翻译（`probe_scan_report`：**found / absent / missing / 兜底** 四档）
· 聚合版翻译（`probe_scan_report_many`：**坏工具 / 命中 / 通过** 三档）
· 树路由与中文门里对三态的消费（`arch_forbid_tree` / `arch_forbid_han`）
· 三态自检的三条腿 + 自检调用点（`probe_scan_selftest`）
· 扫描结果的 missing 档（`probe_scan_find`）

⚠⚠⚨ **口径先量准（本批最大的发现）**：
批 EJ-4 ～ EJ-9 的普查**只认 `if` / `elif`** ⇒ ⇒ **`case` 的分支体**
（`pattern) 命令 ;;`）**从来没进过候选清单** ⇒ ⇒ **「分档映射」这一族一直是盲区**
⇒ ⇒ 批 EJ-9 说的「裸奔 258」是**低估**
⇒ ⇒ 本批把口径补上（按 **`case` 块**切分支 ⇒ ⇒ **跨行**分支体也算）
⇒ ⇒ 范围内 **40** 条判定行（真判定行；剔除 3 条函数定义行）
⇒ ⇒ **37** 条**一条门都没有**（只剩 **3** 条 `ARCH_FAIL=1 ;;` 被**全文条数门**间接盖住
⇒ ⇒ ⇒ **只管条数不管位置** ⇒ ⇒ 改坏位置照样假绿）
⚠ **口径还有一处盲区（如实记着）**：`case` 的分支体是**跨行**的
（`found)` 一行、命令在后面几行、最后 `;;`）⇒ ⇒ **必须按 `case` 块**切分支
⇒ ⇒ **不能按行正则**（否则 `found)` 这种「只有 pattern 没有命令」的行会整段漏掉）。

⚠ **怎么注入真实失败（不改任何产品代码）**：
三态机制的**入口**是 forbid 门 ⇒ ⇒ ⇒ 注入「一条**真实该红**的违规」即可：
① **单文件 raw 路线**：`src/app/Notifier.h` 追加一条**注释**含「不用 replaceId」
   （**raw** 路线不剥注释 ⇒ ⇒ 只有那道门会红 ⇒ ⇒ 其余门项不受影响 ⇒ ⇒ 零副作用）
② **树路线**：`src/platform/IconResolver.cpp` 追加**真代码** `QIcon::fromTheme("x")`
③ **读不了**：`chmod 000` 那个文件 ⇒ ⇒ **raw** 路线的 `grep` 退出码 2 ⇒ ⇒ **broken 档可达**
⇒ ⇒ ⇒ 产品代码零改动 ⇒ ⇒ 快照零变化。

⚠⚠⚨ **决定性实验 29 例（逐条实测分档 ⇒⇒ 不一概而论）**：
| # | 场景 | 落点 | 基线 | 中和后 | 结论 |
|---|---|---|---|---|---|
| ① | 命中档的失败上报「记了再抹掉」（**条数不变**） | **L205** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实**（**条数门被骗过**） |
| ② | 树路由的命中不收进清单 | **L617** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ③ | 聚合版的命中档被中和 | **L226** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ④ | 映射体改坏 + 自检腿1 被中和 | **L134 / L244** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实** |
| ⑤ | 映射体改坏 + 自检调用点被中和 | **L134 / L285** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实**（自检的 ✗ 消息还在，但**没判红**） |
| ⑥ | 映射体改坏 + 自检三条腿 + 调用点全被中和 | **L134 / L244 / L249 / L254 / L285** | rc=1 | **rc=0** | ⚠⚠⚨ **假绿坐实**（**整个闭环被摘**） |
| ⑦ | 改分支 pattern（`found)` → `absent)`） | **L203** | rc=1 | rc=1 | ⚠ **恒红误报**（配对关系没人守） |
| ⑧ | 把 `ARCH_FAIL=1` 改成别的值 | **L205** | rc=1 | rc=1 | ⚠ **有牙但只管条数**（审计器 rc=4） |
| ⑨ | 命中档文案 ✗ → ✓ | **L204** | rc=1 | rc=1 | ⚠ **诊断变差**（门仍红，消息失真） |
| ⑩～⑬ | 兜底档 / 坏工具档被摘（失败上报 + 文案） | **L212 / L213 / L221 / L618** | rc=1 | rc=1 | ⚠ **有第二道防线**（剥注释失败守卫） |

⚠ **档位含义**：
- **档 A（6 例：①～⑥）** ⇒ ⇒ 那条真实失败**被静默吞掉** ⇒ ⇒ 接线门 rc=0
  ⇒ ⇒ ⚠⚠⚨ **假绿坐实**
- **恒红（2 例：⑦ 及 L135）** ⇒ ⇒ 「没命中」被判成「命中」⇒ ⇒ **恒红误报**
  ⇒ ⇒ ⚠ **不是假绿**，是**结论完全错乱**
- **只管条数（1 例：⑧）** ⇒ ⇒ 审计器 rc=4 抓住 ⇒ ⇒ ⚠ **牙在审计器侧**
  ⇒ ⇒ ⇒ 但**位置一换就骗过它**（① 就是补偿后的版本）⇒ ⇒ 必须另落**位置门**
- **诊断变差（1 例：⑨）** ⇒ ⇒ 门仍红，但消息指错了方向
- **有第二道防线（如实记，4 例：⑩～⑬）** ⇒ ⇒ **剥注释失败守卫**先抓住了
  ⇒ ⇒ ⚠ **不是唯一防线** ⇒ ⇒ 仍须逐条钉住

⚠⚠⚨ **归因实验（落门后，同一处变异）**：
**22** 条**逐条**旧 **绿（rc=0）** ／ 新 **红（rc≠0）** ⇒ ⇒ **归因坐实**
⇒ ⇒ ⚠ 对照组 `L1682`（**早就有牙**、**不在本批范围内**）同一手法 ⇒ ⇒ **两版都红**
⇒ ⇒ ⇒ **红绿差别只取决于有没有门项钉住这一行**；字节级洁净 ✔。

⚠⚠⚨ **修法（落门 22 条，批 EJ-10 段）**：⚠ **零新门型**
· 函数体内的**逐字判定行** ⇒ ⇒ `arch_need_count_in_fn`（**整行锚定**）
· 分支的**整块结构**（pattern ⇒ 正文 ⇒ 失败上报 ⇒ **下一档首行**）⇒ ⇒ `arch_need_count_ml`（**跨行**）
· 自检调用点 ⇒ ⇒ `arch_need_count`（**整行锚定**）
⚠ **为什么跨行门必须把「下一档首行」也包进去**：`_ml` 的 RX 在**压行后**匹配
⇒ ⇒ RX **末尾没锚死** ⇒ ⇒ 块内**最后一行**被追加内容时**照样匹配** ⇒ ⇒ 绿
⇒ ⇒ ⇒ 把**下一档首行**包进去 ⇒ ⇒ 块内任何一行被追加内容 ⇒ ⇒ **匹配即断**。

⚠⚠⚨ **本批踩过的坑**：
① **中和写错 ⇒ 判据失真**：把恒真条件写成 `[ "$X" = "$X" ]`（**恒真**）⇒ ⇒ 条件**没被中和**
   ⇒ ⇒ 「rc=0」只是「**无变化**」⇒ ⇒ **不是假绿证据** ⇒ ⇒ 7 例作废重测
   ⇒ ⇒ ⇒ 正确写法 = `[ "$X" != "$X" ]`（**恒不成立**）
② **自检腿单独被中和 ⇒ 不可观测**：映射好时自检**必然过** ⇒ ⇒ 没有差异
   ⇒ ⇒ ⇒ 必须配一个「可观测缺陷」（改坏映射体）⇒ ⇒ 才有假绿证据
③ **`case` 分支体是跨行的** ⇒ ⇒ 按行正则会漏掉「只有 pattern 没有命令」的行
④ **`_ml` 的 RX 末尾没锚死** ⇒ ⇒ 尾行被追加内容仍匹配 ⇒ ⇒ 必须包住下一档首行
⑤ **落门插入点有同名标记** ⇒ ⇒ 取「批 EJ-9 段之后」的那一个
⑥ **段级 trailer 有两道门**（单行锚定 + 批 EF 跨行）⇒ ⇒ **一个都不能漏**
⑦ **门项条数记四处** ⇒ ⇒ 改一边必红

⚠ **负控 23 真红**（累计 **218 → 241**）：NC219–NC240 三态判定机制 **22** 处逐条**改坏**
（**双断言**：该门项**红** **且** 同段另一条**仍然绿**）｜NC241 正向对照绿。

⚠⚠⚨ **数字（实测）**：门项条数 **1610 → 1632**（**四处同改**）、执行次数 **1613 → 1635**、
恒真 **1068 → 1069**、`ARCH_ANY_FAIL=1` **91 → 92**、`ARCH_FAIL=0` **92 → 93**、
批 EF 两条 trailer **91 → 92**、豁免表 **21 不变**、门型注册表 **16 不变**、
`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、盘点登记册 **34 不变**、
盘点 21 组 / 73 处不变；负控 **218 → 241**。

⚠⚠⚨ **如实记着的已知边界**：
⚠ **本仓的非 raw 路线上 broken 档几乎不可达**（管道退出码只能是 0/1）
⇒ ⇒ 坏工具档的门项是**防御性**的（一旦可达就是静默放行）
⚠ **本仓的剥注释失败守卫是第二道防线**（兜底档被摘后仍被它抓住）
⇒ ⇒ ⚠ **它不是唯一防线** ⇒ ⇒ 兜底档仍须钉住
⚠ **`ci-wiring.sh` 里其余的裸奔判定行仍未落门**（本批只收了**三态判定机制**这 **22** 条）
⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒⇒ 快照零变化）。


⚠⚠⚨ **批 EJ-11 · 剥注释工具瞬时失败必须重试一次**（不许把负载抖动变成假红）

⚠⚠⚨ **起因（实测坐实，不是推演）**：
批 DY 期间的历史观测 = 负控 harness 并发复制 516MB 树时，**审计器返回 rc=2**
（「盲区」）⇒ ⇒ 门侧据此报红 ⇒ ⇒ **代码没坏却报红** ⇒ ⇒ ⚠⚠⚨ **假红**
（批 BS 纪律：假红比假绿更坏 ⇒ ⇒ 逼人把承诺改弱）。

⚠⚠⚨ **旧归因已被代码证死**（这条本身也是本批的收获）：
原记的「重 I/O 下**子进程起不来** ⇒ OSError ⇒ 落进 `except Exception` ⇒ 返回
**CRASH_RC=10**（崩了）」⇒ ⇒ ⇒ **绝不可能是 rc=2** ⇒ ⇒ ⇒ **是误归因**。
⇒ ⇒ rc=2 的**全部来源**已逐条查清：缺 perl／源文件读不了／工具用不了／
门型盲区或实参数个数对不上／git diff 失败／计数 RuntimeError
⇒ ⇒ ⇒ **唯一并发可达路径 = 「工具跑了但退出码≠0」**（`UnreadableSource`）。
⇒ ⇒ ⇒ **「并发重 I/O ⇒ rc=2」这条旧措辞已订正**（README 三处 + 台账此处）。

⚠⚠⚨ **决定性模拟（PATH 注入假工具，零产品代码改动）**：
模拟①「工具一直失败」⇒ ⇒ rc=2 + 「审计失败：源文件**读不了**…剥注释工具退出码 2」；
模拟②「工具**只第一次**失败（= 瞬时抖动）」⇒ ⇒ **同样 rc=2**
⇒ ⇒ ⇒ **假红坐实**（代码没坏，只因负载抖了一下）。

⚠ **修法 = 两侧各重试一次**（**不是**放宽 fail-closed：真坏重试后**仍然红**）：
· 审计器侧：`read_source` / `strip_comments` 收到非 0 退出码 ⇒ ⇒ **再跑一次**
  ⇒ ⇒ 仍非 0 ⇒ ⇒ 才抛 `UnreadableSource`（⇒ ⇒ 顶层兜底 ⇒ rc=2 不变）
· 门侧：工具失败 ⇒ ⇒ **落盘重跑一次** ⇒ ⇒ 仍失败 ⇒ ⇒ 写失败标记 ⇒ ⇒ 末尾判红
⚠⚠⚨ **两侧必须同口径**（批 AS：同一条命令、不复刻）：
第一次输出 + 第二次输出**都要保留**（审计器侧返回 `_first_out + _retry.stdout`）
⇒ ⇒ 不会一边绿一边红。

⚠⚠⚨ **性能实测（两个方案都跑过 ⇒ 选型有据）**：
方案一「**每次都落盘**」⇒ ⇒ 工具不再被消费者提前收工打断 ⇒ ⇒ 每次都要处理全文
⇒ ⇒ 接线门 **21s → 122s**（**5.8 倍**）⇒ ⇒ **不可接受** ⇒ ⇒ 否决；
方案二「**第一次直出 + 失败时才落盘重试**」⇒ ⇒ 正常路径**零开销**
⇒ ⇒ **21s**（与改前持平）⇒ ⇒ **采用**。
⚠ **为什么必须落盘**：第一次失败时**部分输出已经进了管道**⇒ ⇒ 直接重跑会
⇒ ⇒ **污染命中计数**⇒ ⇒ 必须「临时文件 + 覆盖 + `cat` 输出」⇒ ⇒ 字节安全。

⚠ **141 的语义两侧不同**（批 CP 口径，**如实记**）：
门侧 141 = SIGPIPE（消费者**故意**提前收工 ⇒ **容忍**）；
审计器侧**没有**早退消费者 ⇒ ⇒ 141 对它是**失败**（输出被截断 ⇒ 命中数不可信）。

⚠⚠⚨ **修法（落门 15 条，批 EJ-11 段）**：⚠ **零新门型**
· 审计器侧：重试调用点 / 重试后判定行 / 第一次输出保留 / 两次输出拼接（4 条）
· 门侧：两支的第一次工具调用必须接住退出码 / 两支的重试调用点必须落盘 /
  失败位初始化 / 重试前失败位重置 / 临时文件必须清理（6 条）
· 跨行门：重试仍失败 ⇒ ⇒ 写失败标记 ⇒ ⇒ `return 1` ⇒ ⇒ **必须紧挨**（1 条）
· **批 EJ-11·补 追加的 4 条跨行腿**（见下节 ⇒ ⇒ 那 4 条**是本批的教训**）

⚠⚠⚨ **批 EJ-11·补 · 归因实验揪出的真·假绿**（本批最值钱的收获）：
落门后跑归因实验（同一处变异 ⇒ 旧**绿** / 新**红**）⇒ ⇒ **11 条里 10 条归因正确**，
但 **M08 归因错** ⇒ ⇒ ⇒ 「门**红了**、可红的是**别的**门」⇒ ⇒ 深挖：
· 变异 = 把**失败位的初值**从 0 改成 1（**正是那条计数腿专门要防的变异**）
· ⇒ ⇒ 第一次工具调用**成功**、但 `_strip_rc` 仍是 1 ⇒ ⇒ **误入重试支**
· ⇒ ⇒ 末尾 `cat "$_strip_tmp"` 把**整份文件再输出一遍**
  ⇒ ⇒ **`strip_comments` 的输出整份翻倍**（实测 **2907 行 → 5814 行**）
· ⇒ ⇒ 命中数 2 → 1，**又被翻倍回 2** ⇒ ⇒ 期望 2 实得 2 ⇒ ⇒ **照样绿**
· ⇒ ⇒ ⇒ **真·假绿**（不是「诊断变差」，是那条承诺**没有牙**）
⚠ **修法 = 追加 4 条**跨行腿（把**被改的那一行**包进 RX）：
初值/重置 × sed 支/perl 支 ⇒ ⇒ 改那一行 ⇒ ⇒ **匹配即断** ⇒ ⇒ 必然红
⇒ ⇒ **构造上就有牙**（不靠「希望计数能变」）。
⚠⚠⚨ **方法论（可复用）**：**凡是「被改的那一行」不在 RX 里的计数门，都可能被
「输出翻倍」这类副作用掩盖** ⇒ ⇒ ⇒ **要有牙，就必须跨行**（把被改的行包进去）。

⚠⚠⚨ **归因实验（补完跨行腿后重跑）**：**11** 条**逐条**旧 **绿（rc=0）** ／
新 **红（rc≠0）** ⇒ ⇒ **归因坐实**；⇒ ⇒ 字节级洁净 ✔；⇒ ⇒ **零假绿**
（真红 11 / 归因错 0 / 假绿 0 / 跳过 0）。

⚠ **负控 15 例**（累计 **241 → 256**）：NC242–NC252 这 **11** 处逐条**改坏**
（**双断言**：该门项**红** **且** 文案命中）｜NC253 正向对照绿
｜NC254–NC256 补那 4 条跨行腿 + 两条计数腿的**有牙**用例
（NC254/NC255 改**值**（0 → 00，语义不变）⇒ ⇒ 只有跨行腿能抓；
NC256 改**缩进**（8 → 12，语义不变）⇒ ⇒ **计数腿红、跨行腿仍绿**
⇒ ⇒ ⇒ 两条腿**分工明确**）。

⚠⚠⚨ **事故与机制加固（本批进行中实测 ⇒ 如实记）**：
本批进行中，仓库的 `deepin/scripts/ci-wiring.sh` 曾被负控用例的变异**污染**
（少了 `|| _strip_rc=$?`）⇒ ⇒ 接线门当场红 ⇒ ⇒ 而当时负控**照样报「变异未落」**
⇒ ⇒ ⇒ **如果没人去核对仓库字节，这条污染会被当成「门自己红了」而放过**。
· 处置：用两棵**互相独立**的 scratch 树做 **sha256 交叉校验** ⇒ ⇒ 按**字节**还原
  ⇒ ⇒ 证明还原正确（还原后 sha256 = 两棵树共同的 `ba46cc…`）
· ⚠⚠⚨ **直接写入路径未能定位**（已排除三条写路径：负控 harness 的三处写操作、
  落门脚本的写回、归因脚本的写回 —— 三者都只写**各自的工作副本**）
  ⇒ ⇒ ⇒ 但**后果已由机制堵死**
· ⇒ ⇒ **机制化**：「harness 的变异不许碰仓库」这条承诺**不能靠自觉**
  ⇒ ⇒ 负控 harness 加**仓库洁净度守卫**：启动时记仓库内被触及文件的 **sha256** /
  每例跑完核一次 / `atexit` 兜底核一次 / 收尾再核一次
  ⇒ ⇒ **一旦发现被改 ⇒ 立刻按启动时的字节还原 + 响亮报错 + 本例作废**。

⚠⚠⚨ **数字（实测）**：门项条数 **1632 → 1647**（**四处同改**，11 + 4 追加）、
执行次数 **1635 → 1650**、恒真 **1069 → 1073**、`ARCH_ANY_FAIL=1` **92 → 93**、
`ARCH_FAIL=0` **93 → 94**、批 EF 两条 trailer **92 → 93**、豁免表 **21 不变**、
门型注册表 **16 不变**、`ARCH_FAIL=1` **43 不变**、`FAILS.append(9)` **7 不变**、
盘点登记册 **34 不变**、盘点 21 组 / 73 处不变；负控 **241 → 256**。

⚠⚠⚨ **如实记着的已知边界**：
⚠ **重试只解决「瞬时失败」**⇒ ⇒ 真坏仍红（fail-closed **没被放宽**）
⚠ **两侧的 141 语义不同** ⇒ ⇒ 审计器侧 141 仍算失败（**故意**，非 bug）
⚠ **「并发重 I/O ⇒ rc=2」的根因本身仍未定位**（当前条件**不可复现**）
⇒ ⇒ 本批**只是让负载抖动不再变成假红**⇒ ⇒ 根因修掉后**还要再订正一次措辞**
⚠ **工具失败前若已产出部分输出** ⇒ ⇒ 重试成功后内容**翻倍**（实测 **1.50×**）
⇒ ⇒ ⚠⚠⚨ **两侧逐字节一致**（对拍实测：6082 行 → 9122 行，两边一样）⇒ ⇒ ⇒ **「不会一边绿一边红」这条承诺成立**、fail-closed **保住**
⇒ ⇒ 但**诊断**会指向「次数门配准失准」而不是指名道姓
⇒ ⇒ 彻底消掉 ⇒ ⇒ 只能回到「每次落盘」⇒ ⇒ 代价 **5.8 倍** ⇒ ⇒ ⇒ 本批**如实记着这个取舍**
⚠ **输出翻倍会掩盖计数门** ⇒ ⇒ 本批用**跨行腿**补了「失败位」这一族
⇒ ⇒ ⇒ **其它族是否还有同类洞，需另做普查**（本批**不声称**已普查）
⚠ **零产品代码改动**（只动判据层脚本与文档 ⇒⇒ 快照零变化）。


⚠⚠⚨ **批 EJ-12 · 外部工具调用的唯一入口**（工具抖一下不许变成假红 ⇒⇒ 根因坐实）

⚠⚠⚨ **起因（实测坐实，不是推演）**：PATH 注入「**只第一次失败**」的假工具
（sed / awk / grep / git），**逐格实测**审计器与门侧：
· **门侧**（假 sed）⇒ ⇒ **绿** ⇒ ⇒ 批 EJ-11 的门侧重试**确实生效** ✔
· **审计器**（假 sed）⇒ ⇒ **rc=2「盲区」** ⇒ ⇒ 诊断「抽不出 ci-wiring.sh 里的
  strip_comments() ⇒ 口径会漂移」⇒ ⇒ ⚠⚠⚨ 击中的**不是** `strip_comments` 自己
  （它是**第二次**调用 ⇒ ⇒ 重试已生效）⇒ ⇒ 而是**第一个**调 `sed` 的
  **`extract_shell_func`** ⇒ ⇒ 它**根本不检查退出码** ⇒ ⇒ 工具（哪怕只是**抖了一下**）
  失败 ⇒ ⇒ 返回**空串** ⇒ ⇒ `AnyCounter` 抛 RuntimeError ⇒ ⇒ 顶层兜底 ⇒ ⇒ **rc=2**
  ⇒ ⇒ ⇒ **代码没坏却报盲区** ⇒ ⇒ ⇒ **假红**
· ⚠⚠⚨ 而且诊断**指错方向**（读起来像「**代码坏了**」，实际是「**工具抖了**」）
  ⇒ ⇒ ⇒ 排障被带偏
⇒⇒⇒ **这就是「并发重 I/O ⇒ rc=2」的根因候选**（`--list` 模式就可达 ⇒ ⇒ 与 CI 一致）

⚠ **修法（三条腿）**：
① **新增 `run_tool`：外部工具调用的唯一入口**（审计器侧 **13** 处全部收口）
   · **接住退出码** ⇒ ⇒ 工具失败 ⇒ ⇒ **指名道姓**（工具名 + 退出码）⇒ ⇒ 不再误导
   · `retry=True` 时**重试一次**；口径同批 EJ-11（第一次 + 第二次输出都保留 ⇒ ⇒ 两侧同口径）
   · `ToolResult` 的形状与 `subprocess.CompletedProcess` **完全一致** ⇒ ⇒ 调用点零改动
② **零名单 AST 规则**（批 CD 纪律：一次挡住整类）
   · `check_tool_call_entry()`：审计器里**凡 `subprocess.run` 不在 `run_tool` 体内 ⇒ 判红**
   · ⇒ ⇒ 以后新增任何外部工具调用点 ⇒ ⇒ 都得走 `run_tool` ⇒ ⇒
     「接住退出码」这条纪律**不再靠自觉**
   · 核心判定单独成函数 ⇒ ⇒ 规则与**自检**共用 ⇒ ⇒ **判定逻辑只有一份**
     ⇒ ⇒ 自检才真的在测规则（批 BF/BG 纪律）
③ **三处「根本不检查退出码」的调用点补上检查**：`extract_shell_func` + 两个 `awk`
   ⇒ ⇒ 这三处以前是**静默空串** ⇒ ⇒ 「抽不出函数体」⇒ ⇒ 假红且诊断指错方向
· ⚠ **只有两侧都能重试的那一处**（剥注释）才许 `retry=True`
  ⇒ ⇒ 门侧在**管道**里 ⇒ ⇒ 拿不到**中间**工具的退出码 ⇒ ⇒ 其余调用点重试不了
  ⇒ ⇒ 保持「首次失败即失败」⇒ ⇒ **两侧口径一致**（结论一致，只是都红）

⚠ **落门 11 条**（批 EJ-12 段，⚠ **零新门型**）：`run_tool` 定义行 /
`ToolResult` 定义行 / `retry=True` 调用点（恰好 1 处）/ AST 规则定义行 /
AST 核心判定行 / AST 调用点（审计模式 + 报告模式，各 1 处）/
「抽函数失败必须指名道姓」/ 两个 `awk` 的退出码检查（各 1 处）/ 自检必须真的调核心判定
⇒ ⇒ 门项条数 **1647 → 1658**（**四处同改**）；既有 **6** 条门项**随代码改形而同步**
（批 CH 2 条 + 批 EJ-11 4 条 ⇒ 改钉包装器内的对应行）；`FAILS.append(2)` **14 → 15**
（新增守卫名 `entrybad` ⇒ 已登记进 `FAIL_GUARDS` ⇒ ⇒ 登记册与实际不漂）。

⚠ **负控 3 例**（累计 **256 → 259**）：NC257 抽函数失败时的**指名道姓**那行被掏空
（换成 `pass`）｜NC258 **报告模式**的 AST 体检调用点被掏空（⇒ ⇒ 体检不再被调用
⇒ ⇒ 那些调用点的退出码没人接）｜NC259 `run_tool` 的**重试判定**被改窄
（去掉 `or not retry` ⇒ ⇒ `retry=True` 不再重试 ⇒ ⇒ 工具抖一下就假红）
⇒ ⇒ 逐条**双断言**（该门项红 **且** 文案命中）。

⚠⚠⚨ **数字（实测）**：门项条数 **1647 → 1658**（**四处同改**）、执行次数 **1654 → 1661**、
恒真 **1073 → 1084**、`FAILS.append(2)` **14 → 15**、盘点登记册 **34 不变**、
盘点 21 组 / 73 处不变；负控 **256 → 259**。

⚠⚠⚨ **如实记着的已知边界**：
⚠ **本批只覆盖审计器侧**：门侧还有 **16** 处**管道内**的工具调用点（grep / awk / tr）
  ⇒ ⇒ 拿不到中间工具的退出码 ⇒ ⇒ **重试不了** ⇒ ⇒ 保持「首次失败即失败」
  ⇒ ⇒ ⇒ **两侧口径一致**（结论一致，只是都红）⇒ ⇒ **另立项**（性能约束：每次落盘 5.8 倍）
⚠⚠⚨ **【批 EJ-13·订正】** 本段上一版的三行**是错的** ⇒ 当场订正：
⚠ **上一版说「rc=9 的口径不完整 ⇒ 查不到长形态」⇒ 已被实测证伪**
  ⇒ ⇒ **rc=9 覆盖长形态**：把「恰好 95 处 = 1 处声明 + 94 处段末清零；」改成 94
  ⇒ ⇒ ⇒ 审计器当场 **rc=9** + 「说明文字称「恰好 94 处」但期望值是 95」
  ⇒ ⇒ ⇒ ⇒ **还原后逐字节相同**（sha256 一致）⇒ ⇒ **那个洞不存在**
  ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **立项「补长形态」取消**（不需要补）
⚠ **真实的边界（实测 census，不是推演）**：rc=9 的覆盖面 = 它**实际喂进去**的两族
  ⇒ ⇒ `arch_need_count` **909** + `arch_need_count_ml` **41** = **950** 条门项
  ⇒ ⇒ ⇒ 这 950 条的说明文字里「N 处」共 **432** 次
  ⇒ ⇒ ⇒ ⇒ 被 rc=9 正则吃到 **228** 次
  ⇒ ⇒ ⇒ ⇒ 没吃到 · 但形态是「恰好 N 处」（前缀不贴）**16** 次
  ⇒ ⇒ ⇒ ⇒ 没吃到 · 且不是「恰好」形态 **188** 次（说的是**别的对象** ⇒ 假阳性 ⇒ 不该管）
⚠⚠⚨ **上一轮「其中 20 处数字==期望值 ⇒ 全是假阳性」这个判断也不成立**（当场订正）：
  ⇒ ⇒ 那 20 处里 **19 处说的就是自己**的条数
  ⇒ ⇒ ⇒（「面板的 7 处激活动作」= 该门自己的 **7**；「契约门的 93 处 check 调用」= 该门自己的 **93**；
  ⇒ ⇒ ⇒ 「只有这 1 处失败计数点」= 该门自己的 **1**）
  ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **真实缺口 = 29 处**自述型措辞**不在 rc=9 覆盖内**
  ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ （A 类 **10** + B 类 **19**；
  ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 另有 **2** 处数字巧合相等但说的是别的对象）
⚠ **但实测当前不可直接利用**（所以本轮**不落新规则**）：
  ⇒ ⇒ 只改期望值 ⇒ **rc=4**（期望值重算腿：期望 2 ≠ 函数体内实际 3 ⇒ 门没牙）
  ⇒ ⇒ ⇒ 期望值 + 源一起改弱 ⇒ **rc=9**（批 EJ-10 跨行门 `:5993` 三态映射 `missing` 档失准
  ⇒ ⇒ ⇒ ⇒ ⇒ + 全局计数门 `:2779` 期望 43 ≠ 实际 42 ⇒ 抓住）⇒ ⇒ **有牙**
⚠ **为什么不扩 rc=9 的正则**（实测，不是「稳妥起见」）：
  ⇒ ⇒ 把正则放宽成「任意前缀的『恰好 N 处』」⇒ 会立刻误伤 **5** 处**非自述**的写法
  ⇒ ⇒ ⇒ ⇒ （L3817 / L3960 / L5238 / L6087 / L6088 ⇒ 数字说的是**别的门**）
  ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **要扩必须先能自动判「说的是自己」** ⇒ ⇒ **另立项**
⚠ **「并发重 I/O ⇒ rc=2」的根因**本批**只定位到候选**（`extract_shell_func`）
  ⇒ ⇒ 其余调用点（grep / git / awk）**仍可能**在别的条件下瞬时失败
  ⇒ ⇒ ⇒ **下一批要重跑那张实测矩阵**，逐格确认
⚠ **零产品代码改动**（只动判据层 ⇒⇒ 快照零变化）。


⚠⚠⚨ **批 EJ-13 · 门侧工具瞬时失败不许变成假红 / 假绿**（落门 22 条 ⇒⇒ 门侧 16 处管道内调用点 ⇒⇒ 只有 2 处看得见工具退出码 ⇒⇒ ⇒⇒ 假绿坐实）

⚠⚠⚨ **起因（实测坐实，不是推演）**：PATH 注入假工具 ⇒ ⇒ **逐格归因** ⇒
门侧 **16 处**管道内工具调用点（grep / awk / tr）：
· **只有 2 处**看得见工具的退出码（三态那两处 ⇒ `probe_scan_find`）⇒ ⇒ 其余 **14 处**看不见
  ⇒ ⇒ 「没找到」与「工具失败」在下游**长得一模一样**
· **判定型**（`arch_need` / `arch_need_ml`）⇒ ⇒ 「里找不到」⇒ ⇒ **假红 + 诊断指错方向**
· **图标收口那两处** ⇒ ⇒ `if 管道` ⇒ grep 退出码 2 ⇒ if 判假 ⇒ ⇒ **漏检**
  ⇒ ⇒ ⇒ **假绿**（承诺直接消失 ⇒ ⇒ **比假红更坏**）
  ⇒ ⇒ ⇒ ⚠⚠⚨ **实测坐实**：scratch 树注入**真代码**违例（`QIcon::fromTheme`）
    ⇒ ⇒ 基线**红** ⇒ ⇒ 假 grep 下**绿** ⇒ ⇒ ⇒ **假绿坐实**
    ⇒ ⇒ ⇒ ⇒ 审计器侧也 rc=0 ⇒ ⇒ ⇒ ⇒ ⇒ **双侧都绿**
· **计数型** ⇒ ⇒ 「出现 0 次」⇒ ⇒ want>0 ⇒ **假红**／want==0 ⇒ ⇒ **假绿**
  ⇒ ⇒ ⇒ 仓里 **10** 条 want==0 的计数门 ⇒ ⇒ 那一档**承诺会直接消失**
· ⚠⚠⚨ **审计器侧本来就有牙**（`count_hits` ⇒ `_tool_failed` ⇒ `TOOL_FAILURES`
  ⇒ ⇒ rc=2 + 「**工具用不了** ⇒ N 条门项根本没被校准」⇒ ⇒ 指名道姓 ✔）
  ⇒ ⇒ ⇒ ⇒ ⇒ **缺口只在门侧** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **本批只改门侧**
· ⚠⚠⚨ **订正批 EJ-12 的两处失真表述**（当场订正）：
  ① EJ-12 段 trailer 的失败文案写成了「批 **EJ-11**」⇒ ⇒ **诊断失真**（批 CE 纪律）
  ② EJ-12 段头写的「门侧 16 处 ⇒ 重试不了 ⇒ ⇒ **两侧口径一致（结论一致，只是都红）**」
     ⇒ ⇒ **已被实测证伪**（图标收口那两处是**绿** ⇒ ⇒ 不是「都红」）

⚠ **修法（三条腿，零新门型）**：
① **全场存活探测**（`probe_scan_tools_alive`：grep / awk / tr 各**重试一次**）
   ⇒ ⇒ 持久坏 ⇒ ⇒ **整场 fail closed + 指名道姓**（说出是**哪个工具** + 退出码）
   ⇒ ⇒ ⇒ 16 处**一次性全覆盖**（批 CD 纪律：一次挡住整类，别逐点治标）
   ⇒ ⇒ ⚠ 健康基线取工具自己的退出码（grep 对 /dev/null 匹配不到 ⇒ **1**；2 = 出错、127 = 不存在）
② **判定型走三态**（`probe_scan_find` + 新增 `probe_scan_report_need`）
   ⇒ ⇒ 工具坏了 ⇒ ⇒ **指名道姓**（不再是「里找不到」）⇒ ⇒ 图标收口那两处 ⇒ ⇒ **漏检变判红**
   ⇒ ⇒ 「必须找到」这一族的失败上报**统一交给一个翻译器** ⇒ ⇒ 判定逻辑**只有一份**
③ **工具抖一下 ⇒ 重试一次**（`probe_scan_find` 里 rc≥2 ⇒ 重跑；口径同批 EJ-11）
   ⇒ ⇒ 瞬时失败**透明恢复** ⇒ ⇒ 不假红

⚠ **落门 22 条**（批 EJ-13 段，⚠ **零新门型**）⇒ ⇒ 门项条数 **1658 → 1680**（**四处同改**）
⇒ ⇒ 既有 **9** 条门项**随代码改形而同步**（`probe_scan_find` 调用点下限 **7 → 11**／
`ARCH_FAIL=1` 总数 **43 → 46**／`arch_need`·`arch_need_ml` 的本地失败上报 **2 → 1**
⇒ ⇒ 其余交给翻译器／段级 trailer 四处各 **+1**：`ARCH_ANY_FAIL=1` **94 → 95**、
`ARCH_FAIL=0` **95 → 96**、判定行 **94 → 95**、批 EF 跨行 **94 → 95**）
⇒ ⇒ 未验证出口盘点登记册 **6 → 12**（新增 6 处失败上报 ⇒ ⇒ 逐条带理由登记）⇒ ⇒ **73 → 79 处**

⚠ **负控 5 例**（累计 **259 → 264**）：NC260 存活探测的**调用点 + fail closed 出口**被改掉
（⇒ ⇒ 工具坏了不再整场判红）｜NC261 need 翻译器的 **broken 档**消息被改
（⇒ ⇒ 工具坏了又只会被当成「没找到」）｜NC262 图标收口 raw 档 broken 分支的失败上报被掏空
（⇒ ⇒ 失败不落到全局红过 ⇒ ⇒ **假绿**）｜NC263 重试判定阈值改成 `-ge 999`
（⇒ ⇒ 恒不成立 ⇒ ⇒ 工具抖一下不再重试）｜NC264 **正向对照**（不变异 ⇒ ⇒ 接线门必须绿）
⇒ ⇒ 逐条**双断言**（该门项红 **且** 文案命中）
⇒ ⇒ ⚠⚠⚨ **顺手补了 harness 的一个洞**：负控的变异**可能逐字节等于原行**
⇒ ⇒ ⇒ 「变异已落」照样打印 ⇒ ⇒ 看输出会以为变异生效了 ⇒ ⇒ **该例变成「永远绿」的假例**
⇒ ⇒ ⇒ 现在**显式断言「文件真的变了」**（实测：NC262 第一版就是这么作废的）

⚠⚠⚨ **数字（实测）**：门项条数 **1658 → 1680**、执行次数 **1661 → 1683**、
恒真 **1084 → 1089**、`|| true` 盘点 **34 不变**、盘点 21 组 / **73 → 79 处**；
负控 **259 → 264**

⚠⚠⚨ **如实记着的已知边界**：
⚠ **计数型 / awk 抽取型仍是逐调用点看不见退出码** ⇒ ⇒ 靠 ① 全场探测兜底
（工具**持久**坏 ⇒ 整场红）⇒ ⇒ 工具**中途**坏 ⇒ ⇒ 仍是假红 ⇒ ⇒ **另立项**
⚠ **存活探测是时点探测**（跑一次）⇒ ⇒ 工具在探测**之后**坏 ⇒ ⇒ 只有三态那几处看得见
⚠ **零产品代码改动**（只动判据层 ⇒⇒ 快照零变化）。

⚠⚠⚨ **批 EJ-14 · 审计器侧「接住退出码却不判」不许变成假红 / 诊断指错方向**（落门 10 条 ⇒⇒ 实测坐实「失败即 continue」那一腿**原先没有任何门有牙** ⇒⇒ ⇒⇒ 补门 4 条 ⇒⇒ ⇒⇒ 门项条数 1680 → 1690）

⚠⚠⚨ **起因（实测坐实，不是推演）**：PATH 注入假 grep ⇒ ⇒ **精确隔离**到 `count_in_fn` 独有的 RX
· 审计器整体 **rc=4**（红 ⇒ ⇒ **不是假绿**）
· 但那两条 `count_in_fn` / `count_in_step` 的诊断是
  「期望 N ≠ 函数体内实际 0 ⇒ **门恒红**」⇒ ⇒ ⇒ **诊断指错方向**
  （读起来像「代码里的失败上报被掏空了」，实际是「**工具抖了**」）
· ⇒ ⇒ ⚠⚠⚨ **订正批 EJ-12 的「审计器侧 13 处全部收口」不完整** ⇒ ⇒ 收口了「不检查退出码」，
  但**没覆盖「接住退出码却不用于判定」**这个形态 ⇒ ⇒ **当场订正**

⚠ **修法（4 处，零新门型）**：
① 两处 `grep -oE`（`count_in_fn` / `count_in_step`）**与 `count_hits` 同口径**判退出码
   （批 EB 的写法：退出码 ∉ (0, 1) ⇒ `_tool_failed` + **指名道姓** + `continue`）
② 两处 awk 失败后 **continue**（⇒ 去掉「**双报**」：工具失败 + 找不到函数体）
⇒ ⇒ 诊断从「期望 N ≠ 实际 0 ⇒ **门恒红**」变成
「**工具用不了** ⇒ 实际次数**算不出来** ⇒ 校准**没做成**」⇒ ⇒ **不再指错方向**

⚠ **落门 10 条**（批 EJ-14 段）⇒ ⇒ 门项条数 **1680 → 1690**（**四处同改**）
⇒ ⇒ 前 **6** 条是首轮落的（退出码判定 1 + 两族 grep 诊断 2 + 两族 awk 诊断 2 + 失败登记 1）
⇒ ⇒ 后 **4** 条是**补门**（下面那一节）⇒ ⇒ 条数 **1686 → 1690**

⚠⚠⚨ **落门范围的实测普查（★ 本批最重要的方法论）**：先落 6 条门 ⇒ ⇒ 再**逐条实测**
「哪条腿有牙」⇒ ⇒ **坐实「失败即 continue」这一腿没有任何门有牙**
· 变异①（`count_in_fn` 放宽 grep 退出码判定）⇒ ⇒ 接线门**红**（2 条）✔ 有牙
· 变异②（`count_in_step` 同上）⇒ ⇒ 接线门**红**（2 条）✔ 有牙
· 变异③（删掉 `count_in_fn` 的 `continue`）⇒ ⇒ 接线门**仍绿**（红 0 条）✘ **没牙**
· 变异④（删掉 `count_in_step` 的 `continue`）⇒ ⇒ 接线门**仍绿**（红 0 条）✘ **没牙**
⇒ ⇒ 落门范围**有缺口** ⇒ ⇒ **补 2 条跨行门**（`arch_need_count_ml`，
把两处 awk 失败分支**整块**钉住 ⇒ 含那条 `continue`）
⇒ ⇒ ⚠ **为什么必须跨行**：`continue` 在整个文件里有**很多处** ⇒ 单行门**分不开**
⇒ ⇒ 补门后重测：变异③④ ⇒ ⇒ **各红 2 条** ✔ ⇒ ⇒ ⇒ ⇒ ⇒ **六路变异全部真红**

⚠⚠⚨ **顺带实测到 rc=9 的分诊文案不完整**（批 EJ-14·补）：审计器 rc=9 实际有 **7** 种成因
（未定义名 / 豁免坏行 / 豁免文件不在 / 豁免对不上门项 / 门型清单与登记册对不上 /
**跨行次数门（`arch_need_count_ml`）期望校准失准** /
**门项的说明文字里的条数与期望值对不上**）⇒ ⇒ 接线门的分诊文案**只列了 3 种**
⇒ ⇒ 连 **rc=9 的本义**（「文字在骗人」）**都没被说出来** ⇒ ⇒ 排障被带偏
⇒ ⇒ ⇒ ⇒ 补齐那两档 ⇒ ⇒ 并落 2 条门（G9 / G10）把「文案里必须有这两档」**钉住**
⇒ ⇒ ⇒ ⇒ ⇒ **本批自己的新门被违反时 ⇒ ⇒ 分诊说的就是真因**（不再指错方向）

⚠ **负控 9 例**（累计 **264 → 273**）：NC265 / NC266 放宽两族的 grep 退出码判定
｜NC267 / NC268 改两族的 grep 失败诊断文案｜NC269 / NC270 删两族 awk 失败分支的 `continue`
（★ 这两例是**补门**的牙）｜NC271 / NC272 删 rc=9 分诊文案里的两档（★ **补门**的牙）
｜NC273 **正向对照**（不变异 ⇒ ⇒ 接线门必须**绿**）⇒ ⇒ 逐条**双断言**（该门项红 **且** 文案命中）

⚠⚠⚨ **数字（实测）**：门项条数 **1680 → 1690**、执行次数 **1683 → 1693**、
恒真 **1089 → 1092**、`|| true` 盘点 **34 不变**、盘点 21 组 / **79 处**不变；负控 **264 → 273**

⚠⚠⚨ **如实记着的已知边界**：
⚠ **`arch_need_count_in_fn` 的函数体抽取对 Python 目标不结束** ⇒ ⇒ 「函数体内」其实是
**整个文件**（awk 靠 `{}` 计数判结束 ⇒ Python 函数永远不结束 ⇒ 抽到文件末尾）
⇒ ⇒ 本批**一度**落了 2 条目标是 .py 的 count_in_fn 门项 ⇒ ⇒ **实测发现**后
**改成文件级跨行门**（真牙 + 描述诚实）⇒ ⇒ ⇒ ⇒ ⇒ **仓里现在没有**目标是 .py 的
count_in_fn 门项 ⇒ ⇒ **既有门项未受影响**（**潜伏**）
⇒ ⇒ 但修那个 awk 会牵动 **31** 条盯 shell 函数的门项 ⇒ ⇒ **另立项**
⚠ **rc=2 的分诊文案没有逐条普查**（rc=2 实际有 **16** 处成因 ⇒ 文案是**举例式**的）⇒ ⇒ **另立项**
⚠ 审计器 L494（bash 批量计数）失败时抛 RuntimeError ⇒ ⇒ **rc=10「崩了」** ⇒ ⇒ 诊断失真 ⇒ ⇒ **另立项**
⚠ **零产品代码改动**（只动判据层 ⇒⇒ 快照零变化）。
⚠⚠⚨ **批 EJ-15 · CI · 判据层 · **工具失败走两条通道**（⇒ ⇒ rc=4 抢先 ⇒ ⇒ **诊断指错方向**）

⚠⚠⚨ **起因（实测坐实，不是推演）**：PATH 注入**假 grep（恒退 137 = SIGKILL）**⇒ ⇒
审计器输出「次数门没配准（145 条）… ⇒ **工具用不了** ⇒ 算不出来」⇒ ⇒ 而**退出码是 4**
⇒ ⇒ 接线门按 rc=4 说「**门没牙或恒红**」⇒ ⇒ **读起来像「有人把门项删了/改弱了」**
⇒ ⇒ 实际是「**工具坏了**」⇒ ⇒ ⇒ **诊断指错方向** ⇒ ⇒ ⇒ 这就是「**并发重 I/O ⇒ rc=2**」
在**诊断侧**的真实根因

⚠ **根因（机制）**：工具失败走了**两条通道** ——
① `_tool_failed(...)` ⇒ ⇒ `TOOL_FAILURES` ⇒ ⇒ **rc=2**（工具用不了 ⇒ 没被校准）
② `bad.append(...)`   ⇒ ⇒ 「次数门没配准」⇒ ⇒ **rc=4**（次数门失准）
⇒ ⇒ rc 取**最先失败**的那个 ⇒ ⇒ **rc=4 抢先** ⇒ ⇒ 分诊落到**错的那一档**

⚠ **修法（三条腿，零新门型，rc 语义只增不改）**：
① 审计器 **6 处**工具失败 ⇒ ⇒ **合并成一条通道**（诊断文案**折进** `_tool_failed` 的 why
⇒ ⇒ **不再进 `bad`**）⇒ ⇒ 「次数门没配准」那一档**只装真的失准**（**rc=4 本义恢复**）
⇒ ⇒ 工具失败 ⇒ ⇒ 由 **rc=2** 承担 ⇒ ⇒ 且**逐条明细不丢**（`_tool_failed` 登记了 文件/正则/原因）
② 门侧 `any_hits` ⇒ ⇒ **两条腿都接住 grep 的退出码**（`grep -oE` 找匹配 + `grep -c` 数行数）
⇒ ⇒ grep 写**临时文件** ⇒ ⇒ 拿得到**它自己**的退出码（0/1 正常、**≥2 = 工具坏了**）
⇒ ⇒ **三态可分** ⇒ ⇒ 工具坏了 ⇒ ⇒ **指名道姓 + 非 0 退出**
⇒ ⇒ ⚠ **审计器侧零改动**：它**抽取**门侧 `any_hits` 原文（批 AV 起的纪律）⇒ ⇒ 自动跟随
③ 审计器 `AnyCounter._run()` 失败 ⇒ ⇒ **登记**（`_tool_failed`）而**不是** `raise RuntimeError`
⇒ ⇒ 以前 `raise` ⇒ ⇒ **整个审计器中止** ⇒ ⇒ 其它门型**根本没审** ⇒ ⇒ 明细只剩 1 行
⇒ ⇒ 现在**继续跑完所有检查** ⇒ ⇒ 最后由 `tool_failure_rc()` **统一收口**判红（**rc=2**）
⇒ ⇒ ⇒ ⇒ 实测：假 grep 下 **1603 条**门项逐条列出（前 20 条 + 总数）

⚠ **落门 2 条**（批 EJ-15 段，零新门型）：
G11 `arch_need_count` —— rc=2 的分诊文案**必须点名**「工具用不了 ⇒ N 条门项根本没被校准」
⇒ ⇒ 否则分诊又指错方向｜G12 `arch_forbid` —— `arch_need_count_in_fn` 的目标**不许**是 `.py`
⇒ ⇒ ⚠ **forbid 门型**（三态探针 ⇒ ⇒ 工具坏了 ⇒ ⇒ **指名道姓**，不是静默 0 命中）
⇒ ⇒ ⚠⚠⚨ **批 DY·补**：新增 forbid 门项必须做「**正负有据**」自证（干净 0 + 塞违例 >0）

⚠⚠⚨ **连带同步（改判据层 ⇒ ⇒ 盘点数字会变 ⇒ ⇒ 登记册必须一起改）**：
`|| true` 盘点基线 **34 → 33**（`any_hits` 那处 `|| true` **真没了** ⇒ ⇒ 登记册那一行**删掉**）
｜未验证出口登记册「失败上报」**12 → 14**（`any_hits` 的两条错误消息）⇒ ⇒ 且说明文字里的
「十二处」→「十四处」**同一个数字**也要改（批 EA 纪律）｜既有 **9** 条门项的 RX 随代码改形而同步
（批 EJ-14 的 G2–G6 + 批 EJ-12 的两条 awk 门 + 批 EJ-14·补 的 G7/G8 两条跨行门）
｜段级 trailer **四处各 +1**（新增一段 ⇒ 自指）｜门项条数 **四处同改**

⚠ **负控 4 例**（累计 **273 → 277**）：NC274 **正向对照**（不变异 ⇒ ⇒ 受限 PATH ⇒ ⇒ 工具坏了
⇒ ⇒ 审计器 rc **必须是 2** ⇒ ⇒ 且**不得**混进「次数门没配准」那一档）｜NC275 **负控**
（把审计器的**双通道**加回来 ⇒ ⇒ rc 变回 **4** ⇒ ⇒ 「次数门没配准」那一档**又回来**）
｜NC276 **正向对照**（**只有计数档 `grep -c` 坏** ⇒ ⇒ rc 仍是 **2** ⇒ ⇒ 且**指名道姓**说
「计数工具 grep 不可用」）｜NC277 **负控**（把 `any_hits` 的**第二条腿**中和掉 ⇒ ⇒ rc 变回 **4**）
⇒ ⇒ ⇒ ⇒ **正反对照配对**：正向 rc=2 / 负控 rc=4 ⇒ ⇒ ⇒ ⇒ **修法真的有效**

⚠⚠⚨ **数字（实测）**：门项条数 **1690 → 1692**、执行次数 **1693 → 1695**、
恒真 **1093 → 1095**、`|| true` 盘点 **34 → 33**、失败上报登记册 **12 → 14**、
盘点 21 组 / **79 → 81 处**；负控 **273 → 277**

⚠⚠⚨ **订正批 EJ-12 遗留清单里的一处失真归因**：那条写「审计器 L494（bash 批量计数）失败时抛
RuntimeError ⇒ ⇒ **rc=10「崩了」**」⇒ ⇒ **是错的** ⇒ ⇒ 实际**被 L2822 捕获** ⇒ ⇒ **rc=2**
（消息「审计失败：any_hits 批量计数失败」）⇒ ⇒ ⚠ **不是 rc=10** ⇒ ⇒ ⇒⇒ **本批已把那一处
改成「登记 ⇒ 继续跑 ⇒ 统一收口判 rc=2 + 逐条明细」** ⇒ ⇒ ⇒⇒ ⇒ ⇒ **它不再是「中止整个审计器」**

⚠⚠⚨ **记入「批 DU 红绿分叉」的根因（已定位，待修）**：契约门第 21 组**打真 GitHub API**
（`api.github.com`，`--max-time 25`）⇒ ⇒ API 不可达时打印 SKIP、可达时跑 2 条 check
⇒ ⇒ **两遍输出不同** ⇒ ⇒ 双跑门**自造分叉** ⇒ ⇒ 修法工程量大（钉死可达性 / 把该组挪出双跑范围）
⇒ ⇒ ⇒ ⇒ **另立项**

⚠⚠⚨ **如实记着的已知边界（另立项）**：
⚠ **rc=2 的分诊文案除「工具用不了」外还有 7 类没点名**（guard_bad / fg_bad / es_bad /
dt_bad / exempt_missing / skipbad / entrybad）⇒ ⇒ 本批只补了**负载相关**的那一档
⚠ **门侧 `arch_need_count` 等家族仍是 `grep -oE … | grep -c . || true`** ⇒ ⇒ **同一个洞的
同款形态** ⇒ ⇒ 工具坏了 ⇒ ⇒ 静默算成 0 命中 ⇒ ⇒ 「门恒红」⇒ ⇒ 本批只收了 `any_hits` 家族
（因为 any_count 家族在审计器侧靠它）⇒ ⇒ **另立项**
⚠ **负控 harness 的 `audit-toolfail` 档是死代码**（12 空格 ⇒ ⇒ 嵌在 `elif extra in (...)`
的**块内** ⇒ ⇒ **永远进不去**）⇒ ⇒ ⚠⚠⚨ **实测坐实** ⇒ ⇒ 本批新增的 3 个档因此**必须**放在
**8 空格层级**（与 `elif extra in (...)` **同级**）⇒ ⇒ ⇒⇒ ⇒ ⇒ **纪律「新增一个附加断言档 ⇒
必须确认它进得了分派元组」不是空话** ⇒ ⇒ ⇒⇒ ⇒ ⇒ **既有那个档另立项**（修了会让 NC29 的
extra 断言**开始生效** ⇒ ⇒ 需先核 NC29）
⚠ **`arch_need_count_in_fn` 的函数体抽取对 Python 目标不结束**（承批 EJ-14 ⇒ ⇒ 牵动 **31** 条）
⚠ **零产品代码改动**（只动判据层 ⇒⇒ 快照零变化）。

⚠⚠⚨ **批 EJ-16 · CI · 判据层 · **门侧工具失败不许静默算成 0 命中**（⇒ ⇒ 两侧说法不一致 ⇒ ⇒ 诊断只对了一半）

⚠⚠⚨ **起因（实测坐实，不是推演）**：门侧还有 **7 处** `|| true`
（`arch_need_count_ml` / `arch_need_count` / `arch_need_count_pair` ×2 /
`arch_need_min` / `arch_need_count_in_fn` / `arch_need_count_in_step`）
⇒ ⇒ **管道里拿不到中间那个 grep 的退出码** ⇒ ⇒ 工具坏了 ⇒ ⇒ **静默算成 0 命中**
⇒ ⇒ 「期望 N ≠ 实际 0 ⇒ **门恒红**」⇒ ⇒ **诊断指错方向**（读起来像「门项被删了/改弱了」）
⇒ ⇒ 而**审计器侧**同一时刻说「**工具用不了**」⇒ ⇒ **两侧说法不一致** ⇒ ⇒ **诊断只对了一半**
⇒ ⇒ ⇒ ⇒ **这正是批 EJ-15 末尾如实记下的那条边界**（「门侧 `arch_need_count` 等家族仍是
`|| true` ⇒ ⇒ 同款形态 ⇒ ⇒ **另立项**」）⇒ ⇒ **本批把它收了** ⇒ ⇒ ⇒⇒ **闭环**

⚠⚠⚨ **普查口径（★ 本批最重要的方法论）**：归属**必须用「函数栈」精确普查**
（扫 `^name() {` 定义行 ⇒ 归属到真正的函数）⇒ ⇒ **不能凭推测配门型**
⇒ ⇒ ⚠⚠⚨ **我自己配错过两处**（623 实际是 `_min` 不是 `_in_fn`；668 实际是 `_in_fn` 不是 `_count_ml`）
⇒ ⇒ ⇒ ⇒ 落门若按错对应改 ⇒ ⇒ **会改错行** ⇒ ⇒ ⇒⇒ ⇒ ⇒ **落门脚本按行号 + 原文双断言**落地

⚠ **修法（零新门型、零新变量、单一真相源）**：抽**一个**共享辅助函数
`wiring_count_hits <模式: hits 或 lines> <正则>`（内容从 **stdin** 读）⇒ ⇒
① **两条腿都接退出码**（① `grep -oE` 找匹配 ② `grep -c .` 数行数 ⇒ 0/1 正常、**≥2 = 工具坏了**）
⇒ ⇒ ② 工具坏了 ⇒ ⇒ **指名道姓**（打到 stderr）**且输出空串**（空串 = 算不出来）
⇒ ⇒ ③ ⚠ **不碰 `ARCH_FAIL`** ⇒ ⇒ `$( )` 是**子 shell** ⇒ ⇒ 变量**传不回父 shell**
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **置位必须由调用点做** ⇒ ⇒ 7 个调用点各 1 处 `ARCH_FAIL=1`
⇒ ⇒ ④ **单报**（辅助函数已打过消息 ⇒ 调用点不打消息 ⇒ ⇒ **不双报**）
⇒ ⇒ ⑤ **不用 `exit`** ⇒ ⇒ 保持「一次报全」（批 CP / CQ 纪律）｜**不用 `rm`**（固定文件名 + 覆盖写）

⚠ **落门 4 条**（批 EJ-16 段，零新门型）：
G1 共享辅助函数的**「工具坏了」分支整块钉住**（跨行门）⇒ ⇒ ⚠⚠⚨ **判定条件 `-ge 2` 也逐字钉住**
⇒ ⇒ ⇒ ⇒ 「把条件中和成恒假」这一路**也被门抓住**（否则：只钉文本 ⇒ 中和后文本还在 ⇒ G1 仍绿
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **没牙**）｜G2 **A 类 5 处**的「算不出来 ⇒ 判红」整块钉住（跨行门）
｜G3 **B 类 2 处**（`arch_need_count_pair` 的报错行 / 计数行）同上｜G4 `arch_forbid`
（门侧**命令替换内吞退出码**的老写法一律不许回来 ⇒ ⇒ RX 用字符类写竖线 ⇒ ⇒ **不自指**）

⚠⚠⚨ **连带同步（改判据层 ⇒ ⇒ 盘点数字会变 ⇒ ⇒ 登记册必须一起改）**：
门项 2906「全文失败上报总数」**46 → 53**（7 个调用点各 1 处）｜per-函数的 **4** 条
`arch_need_count_in_fn` 门（`arch_need_count` / `arch_need_min` / `arch_need_count_in_fn` /
`arch_need_count_in_step`）各 **+1**（⇒ ⇒ **这些数字是按审计器报的实际值回填的**，
不手拍）｜`|| true` 盘点登记册 **33 → 26**（那 7 处 `|| true` **真没了** ⇒ ⇒ 删 7 行）
｜未验证出口登记册「失败上报」**14 → 16**（辅助函数两条错误消息 + 新段 trailer 一条）
｜段级 trailer 四处各 **+1**（新增一段 ⇒ 自指）｜门项条数 **四处同改**

⚠ **负控 2 例**（累计 **277 → 279**）：**正反对照配对** ⇒ ⇒ ⇒⇒ **修法真的有效**
NC278 **正向对照**（**不变异** ⇒ ⇒ 受限 PATH ⇒ ⇒ **只有计数档 `grep -cE` 坏**
⇒ ⇒ 落仓后 `grep -cE` **全仓只出现在辅助函数里** ⇒ ⇒ 只坏 B 类那一腿 ⇒ ⇒
接线门必须**红** ⇒ ⇒ 且**指名道姓**说「工具用不了」⇒ ⇒ 且**绝不能**出现
「报错行 0 次」那种**误导诊断**（= **不双报**））
｜NC279 **负控**（把辅助函数的「工具坏了」分支**中和成恒假**（`-ge 2` ⇒ `-lt 0`）
⇒ ⇒ 同样工具坏了 ⇒ ⇒ 那条腿不再报红 ⇒ ⇒ `_n` 落空 ⇒ ⇒ **静默算成 0 命中**
⇒ ⇒ 「报错行 0 次 / 计数行 0 次」⇒ ⇒ **误导诊断又回来了** ⇒ ⇒ 必须**红**且报的是那一档
⇒ ⇒ 且**绝不能**出现「工具用不了」）
⇒ ⇒ ⇒ ⇒ **正向：指名道姓 / 无误导诊断** vs **负控：误导诊断 / 无指名道姓**
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒⇒ ⇒ **那一腿是承重的**

⚠⚠⚨ **数字（实测）**：门项条数 **1692 → 1696**、执行次数 **1695 → 1699**、
恒真 **1095 → 1107**、`|| true` 盘点 **33 → 26**、失败上报登记册 **14 → 16**、
盘点 21 组 / **81 → 83 处**；负控 **277 → 279**

⚠⚠⚨ **如实记着的已知边界（另立项）**：
⚠ **rc=2 的分诊文案除「工具用不了」外还有 7 类没点名**（guard_bad / fg_bad / es_bad /
dt_bad / exempt_missing / skipbad / entrybad）⇒ ⇒ **另立项**
⚠ **批 DU 红绿分叉根因**（契约门第 21 组打**真 GitHub API** ⇒ ⇒ 两遍可达性翻转
⇒ ⇒ 双跑门**自造分叉**）⇒ ⇒ **另立项**
⚠ **负控 harness 的 `audit-toolfail` 档是死代码**（12 空格 ⇒ ⇒ 嵌在 `elif extra in (...)`
的**块内** ⇒ ⇒ **永远进不去**）⇒ ⇒ 本批新增的 `ej16-not` 档因此**必须**放在 **8 空格层级**
⇒ ⇒ ⇒⇒ ⇒ ⇒ **纪律「新增一个附加断言档 ⇒ 必须确认它进得了分派元组」不是空话**
⇒ ⇒ ⇒⇒ ⇒ ⇒ **既有那个档另立项**（修了会让 NC29 的 extra 断言**开始生效** ⇒ ⇒ 需先核 NC29）
⚠ **`arch_need_count_in_fn` 的函数体抽取对 Python 目标不结束**（承批 EJ-14 ⇒ ⇒ 牵动 **31** 条）
⇒ ⇒ **另立项**
⚠ **门侧 `arch_need_count_ml` 与 `arch_need_count_pair` 这两个门型**没有 per-函数的
`ARCH_FAIL=1` 计数门（另外 10 个门型都有）⇒ ⇒ 本批**没加**（总计数门 2906 兜着）
⇒ ⇒ ⚠ **这是既有缺口**，不是本批造成的 ⇒ ⇒ **另立项**
⚠ **零产品代码改动**（只动判据层 ⇒⇒ 快照零变化）。

⚠⚠⚨ **批 EJ-17 · CI · 判据层 · **rc=2 的分诊不许只说「盲区」**（⇒ ⇒ 审计器侧有 7 类内部失败态 ⇒ ⇒ 门侧要能指到具体那一类）

⚠⚠⚨ **起因（实测坐实，不是推演）**：审计器侧有 **7 类**内部失败态
（`guard_bad` / `fg_bad` / `es_bad` / `dt_bad` / `exempt_missing` / `skipbad` /
`entrybad`）⇒ ⇒ **各打各的消息** ⇒ ⇒ 而门侧 rc=2 的分诊文案此前**只**列了 **6** 类
（盲区 / 工具用不了 / 门型对拍被掏空 / 缺 perl / 源文件读不了 / 崩了走 rc=10）
⇒ ⇒ **指不到具体是哪一类** ⇒ ⇒ 排障要先分清 ⇒ ⇒ ⇒ ⇒ **诊断指错方向**（最后一处）

⚠ **修法（纯文案、零行为改动）**：
① 门侧 rc=2 分诊文案**逐类点名**这 7 类 ⇒ ⇒ 片段**从审计器源码里提取**
⇒ ⇒ **零手打** + **与事实一致**（审计器改了 ⇒ 分诊文案自动跟着改）
② 审计器 rc=2 的消息从「审计失败：%s」改成**指名道姓**：「any_count / any_min 那一族的
命中数**算不出来** ⇒ ⇒ 那些门项**根本没被校准**（盲区）⇒ ⇒ **先查脚本/工具**，不是查门项」
⇒ ⇒ 以前读起来像「审计器内部对不上」⇒ ⇒ **不知道该查工具还是查脚本**

⚠⚠⚨ **踩坑（已实测坐实）**：分诊文案是 `_audit_why="…"` ⇒ ⇒ **双引号包裹**
⇒ ⇒ ⇒ ⇒ **反引号会被 shell 当命令替换执行** ⇒ ⇒ 提取的片段必须**去反引号**
⇒ ⇒ ⇒ ⇒ 落门脚本**自证**：插入后该行**双引号仍是 2 个、无反引号**
（⚠ 现场验证过：`sh -c 'x="前缀 `nosuchcmd` 后缀"'` ⇒ 真的执行了 ⇒ 文本被吃掉一段）
⇒ ⇒ ⚠ **零手打的做法**：片段从源码提取 ⇒ ⇒ 但**必须**过一遍「去反引号 + 砍计数尾巴」

⚠ **落门 2 条**（批 EJ-17 段，零新门型）⇒ ⇒ 门项条数 **1696 → 1698**（**四处同改**）
G1 门侧 rc=2 的分诊文案**必须逐类点名**那 **7 类**（跨行门；用 `〔盲1〕…〔盲7〕`
**专用标记** ⇒ ⇒ 1 条门就能钉住「7 类都在」⇒ ⇒ 别的说明文字里碰巧出现这串也不会误命中）
｜G2 审计器 rc=2 的消息**必须指名道姓**（整行锚定；RX **程序化生成** ⇒ ⇒ 零手打
⇒ ⇒ 且**整行锚定** ⇒ ⇒ 审计器的 rc=8「不许非整行锚定」那条自己不会报）

⚠⚠⚨ **连带同步**：段级 trailer **四处各 +1**（新增一段 ⇒ 自指）｜门项条数 **四处同改**
｜`|| true` 盘点 **26 不变**｜失败上报登记册 **16 不变**（分诊文案里**不含 ✗**）

⚠ **负控 2 例**（累计 **279 → 281**）：NC280 **正向对照**（不变异 ⇒ ⇒ 接线门**绿**
⇒ ⇒ 批 EJ-17 段**全绿** ⇒ ⇒ 证明「恰好 7 类」**不是恒红**）
｜NC281 **负控**（把分诊文案里的**第 7 类**删掉 ⇒ ⇒ 7 类少一类 ⇒ ⇒ 承诺被破坏
⇒ ⇒ **必须红** ⇒ ⇒ 证 G1 那条跨行门**有牙**）

⚠⚠⚨ **订正一处自己写错的判据（批 EJ-6 纪律：每个断言都要问「它在问什么」）**：
NC280 第一版把关键字取成「〔盲7〕…」⇒ ⇒ **分诊文案只在门失败时才打印**
⇒ ⇒ 绿门的输出里**根本没有它** ⇒ ⇒ 断言**恒不成立** ⇒ ⇒ 改取「批 EJ-17 段门项全绿」
⇒ ⇒ 正向对照该问的是「新落的门**不是恒红**」

⚠⚠⚨ **数字（实测）**：门项条数 **1696 → 1698**、执行次数 **1699 → 1701**、
恒真 **1107 → 1108**、`|| true` 盘点 **26 不变**、失败上报登记册 **16 不变**、
盘点 21 组 / **83 处**不变；负控 **279 → 281**

⚠⚠⚨ **如实记着的已知边界（另立项）**：
⚠ **`AnyCounter` 里还有两处 `raise RuntimeError`**（抽不出 `strip_comments()` / `any_hits()`
⇒ ⇒ **口径会漂移**；批量计数少条 ⇒ ⇒ 对不上）⇒ ⇒ 它们**仍然中止整个审计器**
⇒ ⇒ ⇒ ⇒ **与批 EJ-15 修的完全同类**（EJ-15 收的是「工具失败走两条通道」，
**这两条不是工具失败** ⇒ ⇒ 没被收进去）⇒ ⇒ ⇒⇒ **本批只改文案、不碰它**
⇒ ⇒ ⇒⇒ ⇒ ⇒ **要改必须同时处理 `check_any_gates` 对「命中数算不出来（None）」的处理**
⇒ ⇒ ⇒⇒ ⇒ ⇒ ⇒⇒ **否则会把「工具坏了混进次数门没配准」那个洞带回来** ⇒ ⇒ ⇒⇒ **另立项**
⚠ **批 DU 红绿分叉根因**（契约门第 21 组打**真 GitHub API**）⇒ ⇒ **另立项**
⚠ **负控 harness 的 `audit-toolfail` 档是死代码**（12 空格）⇒ ⇒ **另立项**
⚠ **`arch_need_count_in_fn` 的函数体抽取对 Python 目标不结束**（承批 EJ-14 ⇒ ⇒ 牵动 **31** 条）
⇒ ⇒ **另立项**
⚠ **零产品代码改动**（只动判据层 ⇒⇒ 快照零变化）。

⚠⚠⚨ **批 EJ-18 · CI · 判据层 · 出网必须由调用方显式钉死**（⇒ ⇒ 批 ED 的代理钉死是**软的** ⇒ ⇒ 宿主环境的 `curlrc` 能绕过 ⇒ ⇒ 双跑门自造分叉 ⇒ ⇒ 落门 4 条 ⇒ ⇒ 门项条数 1698 → 1702）

⚠⚠⚨ **起因（实测坐实，不是推演）**：批 ED 的钉死是「把代理指向 `127.0.0.1:9`」
⇒ ⇒ 它依赖「curl 认这个代理变量」⇒ ⇒ 而 curl **还读 `~/.curlrc`** ⇒ ⇒ 里面的
`noproxy = "*"` **直接绕过代理** ⇒ ⇒ **实测**：钉死照样拿到 **6181 字节**真
GitHub API 载荷（curl rc=0）⇒ ⇒ 契约门整门 rc 从 **3** 变 **0** ⇒ ⇒ 两遍之间
宿主环境一变 ⇒ ⇒ 双跑门**自造分叉** ⇒ ⇒ CI **间歇性假红** ⇒ ⇒ 而且**误诊**
（归因成「结论随执行 shell 变」⇒ ⇒ 读者被带去查错的地方）
⇒ ⇒ ⇒ ⇒ ⇒ **批 ED 的修法是对的，但只做了一半**

⚠ **修法（把「软钉死」升级成「显式契约」，零新门型）**：
① 覆盖面探针 **export `DEEPGIT_CONTRACT_OFFLINE=1`** ⇒ ⇒ **显式声明**「本轮不许打外网」
② 契约门**自己认这个开关** ⇒ ⇒ 真 API 那条**恒定** SKIP ⇒ ⇒ 恒定输出 ⇒ ⇒ 恒定退出码
⇒ ⇒ ⇒ ⇒ ⇒ **两遍不可能分叉** ⇒ ⇒ 宿主环境（curlrc / 代理配置）**再也绕不过去**
③ `ci.sh` **不许**出现这个变量名（forbid 门）⇒ ⇒ `ci.sh` 第 10 步**真跑**仍真打真 API
⇒ ⇒ ⇒ ⇒ ⇒ **覆盖面不许被悄悄改窄**（批 DQ 教训：一条本该被登记的承诺从未生效）
④ 覆盖面探针**把这一轮的性质报出来**（`› 本轮钉死出网：…`）⇒ ⇒ 不许「结论悄悄消失」
⇒ ⇒ ⇒ ⇒ ⇒ 否则读者看到「真 API 那条被 SKIP」却不知道是**故意**的 ⇒ ⇒ 误诊

⚠ **代理那组钉死仍然保留**（纵深防御：万一以后有第二个出网点）⇒ ⇒ 两道防线**独立**

⚠⚠⚨ **实测对照（同一时刻、同一二进制、同一 hostile 环境）**：
修法前（批 ED 版）+ hostile `curlrc` + 代理钉死 ⇒ 契约门 rc=**0**（**被打通**）
｜修法后 + 不设开关（真跑路径）⇒ rc=**0**（**真打真 API，行为不变**）
｜修法后 + 设开关（覆盖面探针路径）⇒ rc=**3**（**恒定**，hostile 绕不过去）
｜双跑覆盖面门：正常环境 rc=**0** ✅｜hostile `curlrc` 环境 rc=**0** ✅
⇒ ⇒ ⇒ ⇒ ⇒ **真洞坐实 + 修法坐实 + 修法不伤真跑路径**

⚠ **落门 4 条**（批 EJ-18 段，零新门型）⇒ ⇒ 门项条数 **1698 → 1702**（**四处同改**）
G1 覆盖面探针**必须显式声明**本轮不许打外网（整行锚定）
｜G2 契约门**必须认这个开关** ⇒ ⇒ 恒定不打真 API ⇒ ⇒ 恒定输出 + 恒定退出码
（跨行门；RX **程序化生成** ⇒ ⇒ 零手打；中间的 `[^|]{0,300}` 是**有界**通配
⇒ ⇒ 能跨双引号（`[^"]*` 跨不过）⇒ ⇒ 但**不许**无界）
｜G3 `ci.sh` **不许**出现 `DEEPGIT_CONTRACT_OFFLINE`（forbid 门 ⇒ ⇒ 真跑那处必须真打）
｜G4 覆盖面探针**必须把这一轮的性质报出来**（整行锚定）

⚠⚠⚨ **连带同步（实测回填）**：段级 trailer **四处各 +1**
（`ARCH_ANY_FAIL=1` 99 → 100｜`ARCH_FAIL=0` 100 → 101｜判定行 99 → 100｜整块 99 → 100）
｜门项条数 **四处同改**｜批 CI 段「8 缩进的 `skip=` 计数点」**7 → 8**
（新增分支是 8 缩进 ⇒ ⇒ 落在那一档）｜`|| true` 盘点 **26 不变**
｜失败上报登记册 **16 不变**（新增段的 trailer 那行**一个盘点关键词都没有**
⇒ ⇒ **压根不被抽成站点** ⇒ ⇒ 不计入）｜未验证盘点 21 组 / **83 → 85 处**
（新增 2 处 SKIP 打印）

⚠ **负控 4 例**（累计 **281 → 285**）：
NC282 **正向对照**（不变异 + 同一个假 curl 在 PATH 上 + 代理变量被拿掉
⇒ ⇒ 假 curl 走「计数器翻转」那一支 ⇒ ⇒ 外部可达性在两遍之间**翻转**
⇒ ⇒ 显式契约生效 ⇒ ⇒ 恒定 rc=3 ⇒ ⇒ 双跑门必须**绿**（不许自造分叉））
｜NC283 **负控 · G1 那条腿**（删掉覆盖面探针的「显式声明」⇒ ⇒ 必须红 ⇒ ⇒ 证 G1 **有牙**）
｜NC284 **负控 · G2 那条腿**（中和契约门认开关的判定行 ⇒ ⇒ 必须红 ⇒ ⇒ 证 G2 **有牙**）
｜NC285 **负控 · 可观测后果**（删掉「显式声明」+ 假 curl 翻转 ⇒ ⇒ 契约门真打真 API
⇒ ⇒ 第一遍 rc=3 / 第二遍 rc=1 ⇒ ⇒ **两遍退出码不同** ⇒ ⇒ 双跑门**自造分叉**
⇒ ⇒ ⇒ ⇒ **必须红** ⇒ ⇒ 证「分叉」这个洞**真实存在**）

⚠⚠⚨ **数字（实测）**：门项条数 **1698 → 1702**、执行次数 **1701 → 1705**、
恒真 **1108 → 1110**、`|| true` 盘点 **26 不变**、失败上报登记册 **16 不变**、
未验证盘点 21 组 / **85 处**；负控 **281 → 285**

⚠⚠⚨ **如实记着的已知边界**：
⚠ **真跑那处（`ci.sh` 第 10 步）仍然受宿主 `curlrc` 影响** ⇒ ⇒ 真 API 那条可能可达
也可能不可达 ⇒ ⇒ rc 在 0/3 之间摆 ⇒ ⇒ 但**那里不是双跑** ⇒ ⇒ **不分叉**
⇒ ⇒ CI 的整体结论在「通过」与「未验证」之间摆 ⇒ ⇒ 这是**外部依赖真不可控**的性质
⇒ ⇒ 按批 EC 口径末尾统一 `exit 3` ⇒ ⇒ **如实记，不假装钉死**
⚠ **负控 NC38 的有效性依赖位置耦合**（批 ED 那条负控用 `<DELBLOCK:>` 删代理钉死整块
⇒ ⇒ 而新的 `export DEEPGIT_CONTRACT_OFFLINE=1` **恰好**落在 `no_proxy` 与 `NO_PROXY`
之间 ⇒ ⇒ 被**一并删掉** ⇒ ⇒ 两道防线同时被拆 ⇒ ⇒ NC38 仍能证「分叉」）
⇒ ⇒ ⚠ 若将来调整那行 export 的位置 ⇒ ⇒ NC38 会**静默失效** ⇒ ⇒ **位置耦合，已知边界**
⚠ **`curlrc` 只是实测到的一个绕过路径** ⇒ ⇒ 本批把它从「唯一防线」降级成「纵深防御」
⇒ ⇒ 主防线改成**显式契约** ⇒ ⇒ 不再依赖任何网络栈行为假设
⚠ **`AnyCounter` 里还有两处 `raise RuntimeError`** ⇒ ⇒ **另立项**
⚠ **harness 的 `audit-toolfail` 档是死代码**（12 空格）⇒ ⇒ **另立项**
⚠ **`arch_need_count_in_fn` 的函数体抽取对 Python 目标不结束**（承批 EJ-14 ⇒ ⇒ 牵动 **31** 条）
⇒ ⇒ **另立项**
⚠ **零产品代码改动**（只动判据层 ⇒⇒ 快照零变化）。

⚠⚠⚨ **负控侧顺带订正一处「空洞的绿」**（批 EJ-6 纪律：每个断言都要问「它在问什么」）：
负控 harness 的**假 curl** 原本是「**有代理 ⇒ 真的去连代理** ⇒ ⇒ 连不上 ⇒ ⇒ 恒 exit 22」
⇒ ⇒ 而**覆盖面探针自己 export 了代理**（批 ED 的钉死）⇒ ⇒ ⇒⇒ 假 curl **从来没走过**
「可达性在两遍之间翻转」那一支 ⇒ ⇒ 两遍都「不可达」⇒ ⇒ **一致 ⇒ ⇒ 绿**
⇒ ⇒ ⇒⇒ ⇒⇒ 而这个「绿」**修法前后都一样** ⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **空洞的绿**
⇒ ⇒ 「两版一致」在这里**问不到**「分叉到底有没有被堵住」
⇒ ⇒ **修法（负控侧）**：假 curl **默认**走翻转支（代理那一支要**显式**才走）
⇒ ⇒ ⇒⇒ 覆盖面探针自己 export 的代理**不再**把翻转支关掉 ⇒ ⇒ 翻转**真的发生**
⇒ ⇒ ⇒⇒ ⇒⇒ 批 EJ-18 的正向对照（NC282）与批 ED 的正向对照（NC39）**都变成有牙的绿**
⇒ ⇒ ⇒⇒ ⇒⇒ 且批 ED 的负控（NC38）**实测仍真红**（两道防线同时被拆 ⇒ ⇒ 分叉回来）
⇒ ⇒ ⚠ 假 curl 在**仓外**（`/tmp` 的 harness）⇒ ⇒ **零仓库影响**

⚠⚠⚨ **批 EJ-19 · CI · 判据层 · 审计器「工具用不了」的汇总输出必须被钉住**（⇒ ⇒ 批 EB 落的 6 条门盯的是**调用点** ⇒ ⇒ 汇总输出零门 ⇒ ⇒ 那句总纲可以被悄悄改掉 ⇒ ⇒ 落门 4 条 ⇒ ⇒ 门项条数 1702 → 1706）

⚠⚠⚨ **先订正一处我上一轮说错的话**：我上一轮说「批 EB 立的『工具失败时的诊断措辞』
这条承诺在**仓内**仍没人守 ⇒ ⇒ **这是错的** ⇒ ⇒ 实测：仓内**有 7 条门**守着它
（**6 条**盯审计器 `_tool_failed` 的**调用点** + **1 条**盯门侧分诊文案里的「工具用不了」）
⇒ ⇒ **如实订正，不装作一直是对的**

⚠⚠⚨ **真洞更精确（实测坐实）**：那 6 条门盯的是**调用点** ⇒ ⇒ **不是汇总输出**
⇒ ⇒ 而「**工具用不了** ⇒ ⇒ N 条门项**根本没被校准**」这句（**总纲**）⇒ ⇒ **零门**
⇒ ⇒ ⇒⇒ **它可以被悄悄改掉，而没有任何门会发现**
⇒ ⇒ 而负控侧那条断言（NC29 的附加断言）**读的就是这句**
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 批 EJ-18 修好那个死代码档之后 ⇒ ⇒ 负控与仓内两侧同时对它有牙**

⚠ **修法（纯落门、零文案改动 ⇒ ⇒ 审计器源码一个字没动）**：
G1 审计器「工具用不了」的**汇总首行**必须**逐字**钉住（整行锚定；RX **程序化生成** ⇒ ⇒ 零手打）
｜G2 审计器「工具用不了」的**汇总末行**必须**逐字**钉住（整行锚定）
｜G3 审计器「工具用不了」的**汇总整块**必须**紧挨**（跨行门：`TOOL_FAILURES:` ⇒ ⇒
`FAILS.append(2)`；中间的 `.{0,600}` 是**有界**通配 ⇒ ⇒ **能跨竖线**（`[^|]*` 跨不过
⇒ ⇒ 块里有 `  · %s | %s ⇒ %s` 那行）⇒ ⇒ 整块**不许被拆散**）
｜G4 门侧 rc=2 的分诊文案**必须说清「先查工具，不是查门项」**（**半个承诺补牙** ⇒ ⇒
批 EB 的门只钉了「工具用不了」这半句 ⇒ ⇒ 「先查工具，不是查门项」这半句**零门**
⇒ ⇒ ⇒⇒ 读者被带去查错的地方：查门项 ⇒ ⇒ 而真因是工具坏了）

⚠ **三条腿互相解耦**（实测设计出来的）：G3 的末尾锚点**故意不用**末行 ⇒ ⇒ 否则 G2 与 G3
会**一起红** ⇒ ⇒ 负控就无法**分别**打这两条腿 ⇒ ⇒ 现在 G1 / G2 / G3 各有各的变异落点

⚠⚠⚨ **踩坑（已实测坐实）**：
① RX **必须单引号包裹** ⇒ ⇒ 第一版用双引号 ⇒ ⇒ shell 把 `\*` 的反斜杠**吃掉一层**
⇒ ⇒ 门项行语法不过 ⇒ ⇒ 现在 RX 一律单引号（字面单引号由 `esc_literal` 换成 `.`）
② **单行门与跨行门的自检口径不同** ⇒ ⇒ 单行门 `arch_need_count` 是**逐行**匹配（`^…$` 成立）
⇒ ⇒ 跨行门 `arch_need_count_ml` 才是**压行后**匹配 ⇒ ⇒ 第一版把单行门也压行后自检
⇒ ⇒ `^` 只匹配文件首行 ⇒ ⇒ 命中 0 ⇒ ⇒ **落门脚本的自检当场抓到** ⇒ ⇒ 已按口径分开
③ **门项 RX 里含 `if …` ⇒ ⇒ 恒真探针会把它当成脚本里的一个 shell 条件** ⇒ ⇒ 「条件数」
**额外**虚高 1 ⇒ ⇒ 读者会误以为「本批加了 if」⇒ ⇒ ⇒⇒ **口径噪声**
⇒ ⇒ G3 特意用**不含 `if`** 的唯一锚点（`TOOL_FAILURES:` ⇒ ⇒ 实测唯一 ⇒ ⇒ 命中数 = 1）

⚠⚠⚨ **连带同步（实测回填）**：门项条数 **1702 → 1706**（**四处同改**）｜段级 trailer
**四处各 +1**（`ARCH_ANY_FAIL=1` 100 → 101｜`ARCH_FAIL=0` 101 → 102｜判定行 100 → 101｜
整块 100 → 101）｜`|| true` 盘点 **26 不变**｜失败上报登记册 **16 不变**｜
未验证盘点 21 组 / **85 处**不变｜恒真 **1110 → 1111**
（⚠⚠⚨ **我第一版推算成「1110 不变」⇒ ⇒ 错了** ⇒ ⇒ 实测才发现：**新增一段 ⇒ ⇒
段级 trailer 的那个 `if` ⇒ ⇒ 每段 +1** ⇒ ⇒ 与批 EJ-1～EJ-18 **每一批的规律完全一致**
⇒ ⇒ 据实订正）

⚠ **负控 4 例**（累计 **285 → 289**）：
NC286 **正向对照**（不变异 ⇒ ⇒ 接线门**绿** ⇒ ⇒ 批 EJ-19 段**全绿** ⇒ ⇒ 证明
「恰好 1 处」**不是恒红**）
｜NC287 **负控 · G1 那条腿**（改审计器汇总**首行**的措辞 ⇒ ⇒ 那句总纲被改弱 ⇒ ⇒ 必须红
⇒ ⇒ 证 G1 **有牙**）
｜NC288 **负控 · G2 那条腿**（改汇总**末行**的措辞 ⇒ ⇒ 那是**给读者的话**⇒ ⇒ 把它改薄
⇒ ⇒ 必须红 ⇒ ⇒ 证 G2 **有牙**）
｜NC289 **负控 · G3 那条腿**（在汇总块**中间插一行** ⇒ ⇒ 「先说总数」与「最后说该做什么」
**不再相邻** ⇒ ⇒ **单行门抓不住**（两条逐字门都还在）⇒ ⇒ 必须红 ⇒ ⇒ 证 G3 **有牙**
⇒ ⇒ 也证「单行门不够 ⇒ ⇒ 必须有跨行腿」）

⚠⚠⚨ **数字（实测）**：门项条数 **1702 → 1706**、执行次数 **1705 → 1709**、
恒真 **1110 → 1111**、`|| true` 盘点 **26 不变**、失败上报登记册 **16 不变**、
未验证盘点 21 组 / **85 处**不变；负控 **285 → 289**

⚠⚠⚨ **如实记着的已知边界**：
⚠ **措辞的「粒度」两侧不同**（**不是**矛盾，如实记）：门侧 rc=2 的分诊文案说「**先查工具**，
不是查门项」⇒ ⇒ 审计器汇总块末行说「那些次数门**没被校准** ⇒ ⇒ 期望值对不对**没人知道**
⇒ ⇒ 判红」⇒ ⇒ 前者是**给读者的指令**、后者是**事实陈述** ⇒ ⇒ 两者不冲突 ⇒ ⇒ 本批**不**改
任何文案 ⇒ ⇒ 若将来要把两边**统一成同一句** ⇒ ⇒ **另立项**
⚠ **负控侧的承诺从今天起才有牙**（批 EJ-18 修好了 `audit-toolfail` 死代码档）⇒ ⇒ 在此之前
批 EB 那条断言**一次都没跑过**⇒ ⇒ ⇒⇒ **如实记，不装作一直是对的**
⚠ **负控 harness 本身不在仓里** ⇒ ⇒ ⇒⇒ ⇒ **CI 里仍只靠仓内的门**（⇒ ⇒ 本批落的就是仓内的门）
⚠ `AnyCounter` 里还有两处 `raise RuntimeError` ⇒ ⇒ **另立项**
⚠ `arch_need_count_in_fn` 的函数体抽取对 Python 目标不结束（承批 EJ-14 ⇒ ⇒ 牵动 **31** 条）
⇒ ⇒ **另立项**
⚠ **零产品代码改动**（只动判据层 ⇒⇒ 快照零变化）。

⚠⚠⚨ **批 EJ-20 · CI · 判据层 · 审计器跨文件次数门的校准闭环不许被静默污染**（⇒ ⇒ 实测坐实：`AnyCounter` / `check_any_gates` / `if got is None:` 全零门⇒ ⇒ 而跨文件次数门有 82 条 ⇒ ⇒ 落门 4 条 ⇒⇒ 门项条数 **1706 → 1710**）

⚠⚠⚨ **先订正一处我自己记错的机理**：批 EJ-19 记的是「门项 RX 里含 `if …` ⇒ ⇒
恒真探针**多数一个条件** ⇒ ⇒ 恒真数会虚高」⇒ ⇒ **本批实测坐实：这条是错的**
⇒ ⇒ 对照实验：往 `ci-wiring.sh` 临时插一条门项，① RX **含** `if` ② RX **不含** `if`
⇒ ⇒ 两次恒真条件数**都是 1111** ⇒ ⇒ ⇒⇒ **RX 里的 `if` 并不影响恒真口径**
⇒ ⇒ 恒真每批 +1 的**真实来源**是「**新增一段 ⇒ ⇒ 段级 trailer 的那个 `if`**」
⇒ ⇒ ⇒⇒ **本批直接实证**：批 EJ-20 的 G3 门项 RX **含 `if`**（`^\s+if got is None:$`）
⇒ ⇒ 而恒真仍然**只 +1**（1111 → 1112）⇒ ⇒ ⇒⇒ **一劳永逸地坐实了这件事**
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 此前批 EJ-1～EJ-19 每批「恒真 +1」的归因都是对的（来自 trailer）**
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 但批 EJ-19 把它**归因成「RX 含 if」⇒ ⇒ 那是**错的**⇒ ⇒ 据实订正**

⚠⚠⚨ **洞（实测坐实，不是推演）**：审计器里**跨文件次数门**的校准闭环**整个零门**
· `AnyCounter`（审计器里跨文件批量计数的抽取器）—— **零门**
· `check_any_gates` —— **零门**
· `if got is None:`（「工具坏了 ⇒ 放弃这一条」这一族）—— **零门**
⇒ ⇒ 而**跨文件次数门有 82 条**（**31** 条 `arch_need_any_count` + **51** 条
`arch_need_any_min`）⇒ ⇒ 它们的校准**全靠这条闭环**
⇒ ⇒ ⇒⇒ 闭环被静默改坏 ⇒ ⇒ **82 条门项的校准全部不可信** ⇒ ⇒ 而 rc 照样 0
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 假绿**（批 EB 修过的那个老洞会回来）

⚠⚠⚨ **口径修正（新纪律）**：我第一版口算成「32 条 + 50 条」⇒ ⇒ **两个都错**
⇒ ⇒ 实测：**31 + 51 = 82** ⇒ ⇒ 根因：`grep -oE` 会把**门型函数定义行**
（`arch_need_any_count() { …`）也数进去（+2）⇒ ⇒ ⇒⇒ **分类型计数必须用
「行首 + 后跟空白」口径** ⇒ ⇒ 否则门型定义行被算成门项

⚠⚠⚨ **修法（审计器侧 2 处，零新增 `if` ⇒ ⇒ 恒真数不受影响）**
① `_run()` 里 `_script()` 的 `RuntimeError` ⇒ ⇒ **登记**进工具失败通道 ⇒ ⇒ **不中止**
② 批量计数少 N 条 ⇒ ⇒ 同样**登记** ⇒ ⇒ 不中止
⇒ ⇒ 两者最终由 `tool_failure_rc()` **统一收口**判红（rc=2）+ 逐条明细
⇒ ⇒ 其它门型**照审** ⇒ ⇒ 「**一次报全**」（批 CR/CQ）守住
⇒ ⇒ 且 rc 从 **10**（崩了 ⇒ ⇒ 诊断说「崩了」⇒ ⇒ **指错方向**）变成 **2**
（工具用不了 ⇒ ⇒ **指对方向**）
⇒ ⇒ **台账里那条「`AnyCounter` 里还有两处 `raise RuntimeError` ⇒ ⇒ 另立项」**
⇒ ⇒ ⇒⇒ **本批收掉了**（台账历史不改，新块记录现状）

⚠⚠⚨ **落门 4 条**（批 EJ-20 段，纯落门）
· G1 **跨行门**：「工具失败 ⇒ **登记**」必须**紧挨**「**不中止**」（恰好 **3** 处）
· G2 **跨行门**：两处新增登记的**诊断文案必须逐字统一**（恰好 **2** 处）
· G3 **整行门**：`if got is None:` 这一族必须**逐字**钉住（恰好 **6** 处）
· G4 **整行门**：`AnyCounter.get()` 必须**原样返回**（不许把 None 变成 0）（恰好 **1** 处）
⇒ ⇒ **四条腿互相补位**（缺一条 ⇒ ⇒ 另一个洞就开）：
  **设置侧**（G1：失败必须登记）· **诊断口径**（G2：文案统一）·
  **读取侧**（G3：拿到 None 必须放弃这一条）· **提供侧**（G4：不许把 None 变 0）
⇒ ⇒ G3 的 6 处**文本完全相同** ⇒ ⇒ 整行锚定**一起命中** ⇒ ⇒ 期望值只能是 6
（⚠⚠⚨ 实测：改成按行号逐条落门 ⇒ ⇒ 6 条门项 ⇒ ⇒ 反而更弱 ⇒ ⇒ **一条门钉 6 处**）

⚠⚠⚨ **踩坑（当场踩到并修掉）**
① 落门脚本重建门项行时**丢了文件参数** ⇒ ⇒ 4 条 trailer 门被重建成指向
   `ci-wiring-audit.py`（原本是 `ci-wiring.sh`）⇒ ⇒ 症状「**出现 0 次（期望 102 次）**」
   ⇒ ⇒ ⇒⇒ **诊断一度指向错方向**（看着像「命中数算错」）⇒ ⇒ 修法：门项行**结构化解析**
   （path / RX / 期望值 / 说明文字 **四段一起取、一起带回**）⇒ ⇒ 「改门项行必须**整行写全**」
   这条纪律**救的是整行**，光靠改 RX/期望值**不够**
② 负控 harness 的**语法自证只对 `.sh` 做** ⇒ ⇒ `.py` 变异**没有**语法自证
   ⇒ ⇒ 若变异破坏 Python 语法 ⇒ ⇒ 审计器崩 ⇒ ⇒ 接线门报 rc=10 ⇒ ⇒ **也会被记成「真红」**
   ⇒ ⇒ ⇒⇒ 那时该例**无效**（测的是「崩了」不是「洞」）⇒ ⇒ **判据写错**
   ⇒ ⇒ 本批**补上** `.py` 的 `ast.parse` 自证（仓外 harness ⇒ ⇒ **零仓库影响**）
③ 生成器里写断言 `'%s' % (gl_, e))` ⇒ ⇒ 那是 Python 的 `%` **运算符** ⇒ ⇒ `SyntaxError`
   ⇒ ⇒ 断言里只查**前缀形态**

⚠⚠⚨ **另立项① 的结论（实测后**改判**）**：`arch_need_count_in_fn` 对 `.py` 目标的
函数体抽取 ⇒ ⇒ 实测仓内 **0 条** `.py` 目标（41 条门项全是 `.sh` / `.cpp`）
⇒ ⇒ 而判据层那 5 个 `.py` 文件的失败上报点**已由 AST 路线覆盖**
（`FAIL_REPORT_COUNTS` 覆盖 4 个；审计器自己由 `FAIL_GUARDS` + AST 规则覆盖）
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 结论：这是「两条路线职责分工」而不是「一个待修的洞」**
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 本批**不**改抽取器** ⇒ ⇒ 批 EJ-15 那条 forbid 守卫**继续有效**
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 如实记：原立项描述里「牵动 31 条 ⇒ ⇒ 风险高」的顾虑
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 是**批 EJ-15 当初的**推演** ⇒ ⇒ 现在实测：改抽取器确实会牵动 31 条
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 但**没有需求 ⇒ ⇒ **不做**（不为「也许会用」而改判据层）

⚠⚠⚨ 负控 5 例（累计 289 → 294）
· NC290 **正向对照**（不变异 ⇒ ⇒ 接线门**绿** ⇒ ⇒ 批 EJ-20 段**全绿** ⇒ ⇒ 证明
  「恰好 N 处」**不是恒红**）
· NC291 **负控 · G1 那条腿**（把审计器里「口径抽不出 ⇒ **登记**」那整个调用（3 行）换成
  `pass` ⇒ ⇒ 「工具失败 ⇒ 登记」被摘 ⇒ ⇒ 工具坏了 ⇒ ⇒ **静默** ⇒ ⇒ 必须红）
· NC292 **负控 · G3 那条腿**（把 `check_any_gates` 里「拿到 None ⇒ 放弃这一条」改成
  「拿到 None ⇒ **当成 0 命中**」⇒ ⇒ 即批 EB 修过的老洞 ⇒ ⇒ 必须红）
· NC293 **负控 · G4 那条腿**（把 `AnyCounter.get()` 改成 `... or 0` ⇒ ⇒ **提供侧**把 None
  变成 0 ⇒ ⇒ 必须红）
· NC294 **负控 · G2 那条腿**（把两处新增登记里**一处**的诊断文案改掉 ⇒ ⇒ 两处文案**不再
  逐字相同** ⇒ ⇒ 诊断各说各话 ⇒ ⇒ 必须红）

⚠⚠⚨ 数字（**实测**）：门项条数 **1706 → 1710**（**四处同改**）、门项执行次数
**1709 → 1713**、恒真 **1111 → 1112**、`|| true` 盘点 **26 不变**、失败上报登记册
**16 不变**、未验证盘点 **21 组 / 85 处**不变；段级 trailer **101 / 102 / 101 / 101**
⇒ ⇒ **102 / 103 / 102 / 102**（四处各 +1）；负控 **289 → 294**

⚠⚠⚨ 影响面：**6 个文件**（判据层 **3**：`ci-wiring.sh` / `ci-wiring-audit.py` /
`ci-wiring-gates.baseline` ＋ 文档 **3**：台账 / PLAN / README）⇒ ⇒
**零产品代码改动**（只动判据层 ⇒⇒ 快照零变化）
审计器 rc=0 / 接线门 rc=0（门项合计 **1713** 项）/ 恒真 rc=0（1112）/
`|| true` 盘点 rc=0（26）/ 未验证盘点 rc=0（21 组 / 85 处）⇒ ⇒ 全绿。

⚠⚠⚨ 如实记着的已知边界
⚠ **负控 harness 本身不在仓里** ⇒ ⇒ ⇒⇒ ⇒ **CI 里仍只靠仓内的门**
（⇒ ⇒ 本批落的就是仓内的门）
⚠ 本批只改了**审计器**的失败处置 ⇒ ⇒ 门侧（`ci-wiring.sh`）那一侧的
`arch_need_count_ml` / `arch_need_any_count` **per-函数计数门**仍缺
⇒ ⇒ **既有缺口**（总计数门兜着）⇒ ⇒ **另立项**
⚠ `AnyCounter` 的**批量脚本**若「某条没输出」⇒ ⇒ 现在**登记**而不是中止
⇒ ⇒ 但那 82 条门项**那一轮没被校准** ⇒ ⇒ 由 rc=2 统一判红 ⇒ ⇒
⇒ ⇒ **不假绿，但也不是「校准成功」** ⇒ ⇒ 如实记

## 批 EJ-21 · 门侧 `any_hits` 族的工具失败不许被命令替换吞掉（⇒ ⇒ 实测坐实：命令替换吞掉退出码 ⇒ ⇒ 空串进比较 ⇒ ⇒ 恒红误报 ＋ 诊断指错方向 ⇒ ⇒ 影响 **82** 条门项 ⇒ ⇒ 落门 **4** 条 ⇒ ⇒ 门项条数 **1710 → 1714**）

⚠⚠⚨ **洞 A（实测坐实，不是推演）**
`any_hits` 失败时的行为：**stdout 为空** ＋ **非 0 退出**（`return "$_rc"`）
⇒ ⇒ 而两个调用点写的是 `got="$(any_hits "$re" "$glob")"`
⇒ ⇒ ⇒⇒ **命令替换把退出码吞了** ⇒ ⇒ `got` 是**空串**
⇒ ⇒ `arch_need_any_count` ⇒ `[ "" = "3" ]` 为假 ⇒ ⇒ **恒红误报**「命中  次（期望 3 次）」
⇒ ⇒ `arch_need_any_min` ⇒ `[ "" -ge "3" ]` ⇒ ⇒ **shell 整数比较报错** ⇒ ⇒ 同样**恒红误报**
⇒ ⇒ ⇒⇒ 两者都读起来像「**门恒红**」⇒ ⇒ 而真因是「**工具坏了**」⇒ ⇒ **诊断指错方向**
⇒ ⇒ 而审计器侧（批 EJ-20 已修）说 rc=2「工具用不了」⇒ ⇒ ⇒⇒ **两侧说法不一致**
⇒ ⇒ ⇒⇒ **影响面**：`any_hits` **只有 2 个调用点** ⇒ ⇒ 而**跨文件次数门有 82 条**
⇒ ⇒ ⇒⇒ 工具坏了 ⇒ ⇒ 那 **82 条**门项的结论**全部不可信**

⚠⚠⚨ **顺带订正批 EJ-16 的一处说法**
批 EJ-16 记的是「门侧工具失败**全部收口**」⇒ ⇒ **不完整**
⇒ ⇒ 共享辅助函数 `wiring_count_hits` 只覆盖了「**计数**」族 ⇒ ⇒ ⇒⇒ **`any_hits` 族漏了**
⇒ ⇒ 与批 EJ-12 / EJ-14 的同类订正**同款** ⇒ ⇒ 据实订正

⚠⚠⚨ **洞 B（坐实范围）**：per-函数失败上报计数门已覆盖 **19** 个函数 ⇒ ⇒ 缺口 **3** 个
· `arch_need_count_ml`（**3** 处）
· `arch_need_count_pair`（**4** 处）
· `probe_scan_report_need`（**3** 处，批 EJ-13 钦定的**结论翻译器** ⇒ ⇒ 少一档 ⇒ ⇒
  「必须找到」那一族**静默** ⇒ ⇒ **假绿**）
⇒ ⇒ `probe_scan_selftest` **有**专门的「调用点」门 ⇒ ⇒ **不是**缺口
⇒ ⇒ ⇒⇒ **本批把这 3 个缺口**全部**补上 ⇒ ⇒ 缺口归 0**（实测：per-函数门 **19** 条 ⇒ ⇒ **22** 条 ⇒ ⇒ 覆盖函数 **19** ⇒ ⇒ **22**）

⚠⚠⚨ **修法（门侧 2 处，零新门型）**
两个门型改成「**先取值 → 看退出码 → 不进比较**」：
· `_rc=$?` —— 在**父 shell** 里取命令替换的退出码 ⇒ ⇒ 合法
· 判定条件用**两条信号**：`[ "$_rc" -ne 0 ]`（退出码）**或** `[ -z "$got" ]`（空串）
⇒ ⇒ 两条都要 ⇒ ⇒ 工具坏了 ⇒ ⇒ **指名道姓 ＋ 判红** ⇒ ⇒ 不再恒红误报
⇒ ⇒ ⚠ **诊断文案刻意不含盘点关键词「未验证」** ⇒ ⇒ 未验证盘点 **85 处不变**
⇒ ⇒ 理由：工具坏掉这件事**已经由 `any_hits` 自己报过**了（它带「未验证不许被当成通过」）
⇒ ⇒ ⇒⇒ 调用点这一句只**补上门项名** ⇒ ⇒ 不重复登记 ⇒ ⇒ 盘点数字不被「修一次就涨一次」

⚠⚠⚨ **落门 4 条**（批 EJ-21 段）
· G1 跨行门：`any_hits` 族收口块（「取退出码 ⇒ 判红 ⇒ 不进比较」**整块钉住**）—— 恰好 **2** 处
· G2 per-函数门：`arch_need_count_ml` —— 恰好 **3** 处
· G3 per-函数门：`arch_need_count_pair` —— 恰好 **4** 处
· G4 per-函数门：`probe_scan_report_need` —— 恰好 **3** 处
⇒ ⇒ 连带（**实测回填**，不许推算）：全文失败上报总数 **53 → 55**、
`arch_need_any_count` / `arch_need_any_min` 的 per-函数门 **1 → 2**（各）、
段级 trailer **102 / 103 / 102 / 102 → 103 / 104 / 103 / 103**（四处各 +1）、
门项条数 **1710 → 1714**（**四处同改**）

⚠⚠⚨ **实测坐实一条新规律（此前 20 批没有的）**
**恒真条件数**（被扫描的 `if` / `elif` 条件总数）本批 **1112 → 1115** ⇒ ⇒ **+3**
⇒ ⇒ **+2** 来自「**改既有函数体** ⇒ ⇒ 两个新 `if`」⇒ ⇒ 此前 20 批的 +1 **全部**来自
「新增一段 ⇒ ⇒ 段级 trailer 的那个 `if`」⇒ ⇒ **+1** 来自本批新增的那一段
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 结论：恒真数的增量来源有**两条** ⇒ ⇒ 记账时必须分开数**
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 批 EJ-20 订正过「RX 含 `if` ⇒ 虚高」那条 ⇒ ⇒ 本批再订正一次归因**

⚠⚠⚨ **踩坑（当场踩到并修掉）**
① 门项行有**两种形态**：`arch_need_count "<路径>" '<RX>' <期望> '<说明>'`（**单** RX）
　与 `arch_need_count_in_fn "<路径>" '<RX1>' '<RX2>' <期望> '<说明>'`（**双** RX）
　⇒ ⇒ 只认单 RX ⇒ ⇒ 解析失败 ⇒ ⇒ **诊断指错方向**
② per-函数门的 sig **不许带 `$` 锚点** —— 函数定义行后面**还跟注释**
　（`arch_need_count_ml() { # …`）⇒ ⇒ 带 `$` ⇒ ⇒ **抽不出函数体** ⇒ ⇒ 期望值取不到
　⇒ ⇒ 与既有 19 条 per-函数门的写法**保持一致**（`^fn\(\)`）
③ 门项行重建必须**结构化解析**（path / RX 们 / 期望值 / 说明文字 **一起取、一起带回**）

⚠⚠⚨ 负控 5 例（累计 294 → 299）
· NC295 **正向对照**（不变异 ⇒ ⇒ 接线门**绿** ⇒ ⇒ 批 EJ-21 段**全绿**）
· NC296 **负控 · G1 那条腿**（把收口块里的 `return` 摘掉 ⇒ ⇒ 必须红）
· NC297 **负控 · 行为腿**（让 `any_hits` 失败 ⇒ ⇒ 门红 **且** 诊断说「**工具坏了**」
　⇒ ⇒ **且** 输出**不许**出现「命中  次」（那是恒红误报 ⇒ ⇒ 诊断指错方向））
· NC298 **负控 · 对照实验**（同一处失败 **＋** 把收口块**整块**摘掉 ⇒ ⇒ 输出**必须**出现
　「**命中  次**」⇒ ⇒ 证明 NC297 的「工具坏了」是**修复带来的**）
· NC299 **负控 · per-函数门那条腿**（摘掉 `probe_scan_report_need` 的一处失败上报 ⇒ ⇒ 必须红）

⚠⚠⚨ 数字（**实测**）：门项条数 **1710 → 1714**（**四处同改**）、门项执行次数
**1713 → 1717**、恒真 **1112 → 1115**、`|| true` 盘点 **26 不变**、失败上报登记册
**16 不变**、未验证盘点 **21 组 / 85 处**不变；段级 trailer **102 / 103 / 102 / 102**
⇒ ⇒ **103 / 104 / 103 / 103**（四处各 +1）；负控 **294 → 299**

⚠⚠⚨ 影响面：**6 个文件**（判据层 **3**：`ci-wiring.sh` / `ci-wiring-audit.py` /
`ci-wiring-gates.baseline` ＋ 文档 **3**：台账 / PLAN / README）⇒ ⇒
**零产品代码改动**（只动判据层 ⇒ ⇒ 快照零变化）
审计器 rc=0 / 接线门 rc=0（门项合计 **1717** 项）/ 恒真 rc=0（1115）/
`|| true` 盘点 rc=0（26）/ 未验证盘点 rc=0（21 组 / 85 处）⇒ ⇒ 全绿。

⚠⚠⚨ 如实记着的已知边界
⚠ **负控 harness 本身不在仓里** ⇒ ⇒ ⇒⇒ ⇒ **CI 里仍只靠仓内的门**（⇒ ⇒ 本批落的就是仓内的门）
⚠ 收口块里那条「退出码 0 ＋ 命中数为空」的档**当前不可达**
（`any_hits` 成功时**必交出一个数字**）⇒ ⇒ 那一档由 `-z` 兜住
⇒ ⇒ 如实记：文案里的「退出码 `$_rc`」在那一档会是 0
⚠ 本批**只**收口了 `any_hits` 族（**2** 个调用点）⇒ ⇒ 门侧其余工具调用点的覆盖面
**仍靠**批 EJ-12 / EJ-16 的既有收口 ⇒ ⇒ 如实记

## 批 EJ-22 · 门侧其余工具调用点的失败不许被静默吞掉（⇒ ⇒ 实测坐实：源码树清单取不到 ⇒ ⇒ **9 条门假绿** ＋ 两个 awk 抽取器失败 ⇒ ⇒ **66 条门恒红误报** ⇒ ⇒ 合计 **75** 条门项 ⇒ ⇒ 落门 **4** 条 ⇒ ⇒ 门项条数 **1714 → 1718**）

⚠⚠⚨ **洞 ①（假绿 · 旗舰）：`arch_forbid_tree` 的源码树清单取不到 ⇒ ⇒ 门说「干净」**

```sh
for f in $(cd "$SRC" && find src \( -name '*.cpp' -o -name '*.h' \) | sort); do
    probe_scan_find "$SRC/$f" "$re" 0 0
    …
done
probe_scan_report_many "$hit" "$broken" "$re" "$label"
```

· `find` 坏了 / `cd` 失败 ⇒ ⇒ 命令替换 **stdout 为空** ⇒ ⇒ 循环**一次都不跑**
· ⇒ ⇒ `hit` / `broken` 都是空 ⇒ ⇒ 报告器走「没找到」那一支 ⇒ ⇒ 打印 **`  ✓ $label`**
· ⇒ ⇒ ⇒⇒ **门绿** ⇒ ⇒ 而真因是「**源码树根本没被扫**」⇒ ⇒ ⇒⇒ **假绿**
· ⚠ **为什么 `broken` 那一档救不了**：`broken` 只在**逐个文件**时才会被填上；
  **清单本身就是空的** ⇒ ⇒ 循环不跑 ⇒ ⇒ `broken` 永远是空
· ⚠ **两条失败路径都会导致空清单**：`cd "$SRC"` 失败（`&&` 短路 ⇒ ⇒ `find` 根本不跑）
  与 `find` 失败 ⇒ ⇒ 而 `$?` 取的是**管道尾（`sort`）**的退出码 ⇒ ⇒ **光看退出码抓不住**
  ⇒ ⇒ ⇒⇒ 必须**另加一条「清单不许为空」**的信号

⇒ ⇒ **影响面（实测）**：用 `arch_forbid_tree` 的门项 = **9** 条
（`dockGap|edgeMargin|fallbackDx|fallbackDy` 数值单一真相源 / `activateWindow()` /
`raise();` / 不许用**文字**当分隔线 / `QIcon::fromTheme(` / `QIcon(` /
`new QPropertyAnimation(` / `setDuration(\s*[0-9]` / `QVariantAnimation|QAnimationGroup`）

⚠⚠⚨ **洞 ②（恒红误报 ＋ 诊断指错方向）：两个 awk 抽取器 ⇒ ⇒ 66 条门项**

```sh
body="$(strip_comments "$f" | awk -v sig="$sig" ' … ')"
if [ -z "$body" ]; then
    printf '%s
' "  ✗ $label：$f 里找不到函数 $sig" >&2
```

· `awk` 失败 ⇒ ⇒ stdout 为空 ⇒ ⇒ 门报「**找不到函数**」⇒ ⇒ 而真因是「**工具坏了**」
· ⇒ ⇒ ⇒⇒ **恒红误报 ＋ 诊断指错方向**（人会去查「函数是不是被改名了」）
· ⇒ ⇒ 与批 EJ-21 的洞 A **同款**（命令替换吞退出码 ＋ 空输出被当成业务结论）

⇒ ⇒ **影响面（实测）**
· `arch_need_count_in_fn`（`awk -v sig=…`）⇒ ⇒ **44** 条门项
· `arch_need_count_in_step`（`awk -v step=…`）⇒ ⇒ **22** 条门项
· ⇒ ⇒ 合计 **66** 条

⚠⚠⚨ **自指**：这 66 条里**包含批 EJ-21 刚落的三条 per-函数门**
（`arch_need_count_ml` / `arch_need_count_pair` / `probe_scan_report_need`）
⇒ ⇒ ⇒⇒ **本批落的门自己踩着同一个洞** ⇒ ⇒ 优先级抬到最高。

⚠⚠⚨ **影响面汇总**

| 洞 | 形态 | 门项数 | 后果 |
|---|---|---|---|
| ① `arch_forbid_tree` 清单取不到 | **假绿** | **9** | 源码树**根本没被扫** ⇒ 门说「干净」 |
| ② 两个 awk 抽取器失败 | **恒红误报 ＋ 诊断指错方向** | **66** | 报「找不到函数」而真因是「工具坏了」 |
| **合计** | | **75** | 9 条假绿 ＋ 66 条恒红误报 |

⇒ ⇒ 另有 **3 处次要**（trap 的 `sort` / 两处 `head -2 … | tr` ⇒ 失败 ⇒ 诊断摘录变薄）
⇒ ⇒ 本批**不动**它们 ⇒ ⇒ **如实记**。

⚠⚠⚨ **修法（门侧 3 处，零新门型）**
· `arch_forbid_tree`：先取值 ⇒ ⇒ **退出码 ＋ 清单非空两条信号都要** ⇒ ⇒
  清单取不到 ⇒ ⇒ **指名道姓 ＋ 判红** ⇒ ⇒ 不进循环 ⇒ ⇒ 不再说「干净」
· `arch_need_count_in_fn` / `arch_need_count_in_step`：`awk` 退出码非 0 ⇒ ⇒
  **指名道姓 ＋ 判红**（不许说「找不到函数」）
· ⇒ ⇒ 诊断文案**不含**盘点关键词 ⇒ ⇒ 未验证盘点 **85 处不变**

⚠⚠⚨ **落门 4 条**（批 EJ-22 段）
· G1 跨行门：`arch_forbid_tree` 的「清单取不到 ⇒ 判红 ⇒ 不进循环」整块钉住 —— 恰好 **1** 处
· G2 跨行门：`arch_need_count_in_fn` 的「awk 退出码 ⇒ 判红 ⇒ 不进比较」整块钉住 —— 恰好 **1** 处
· G3 跨行门：`arch_need_count_in_step` 的同一整块 —— 恰好 **1** 处
· G4 per-函数门：`arch_forbid_tree` 的失败上报 —— 恰好 **1** 处
  （⚠⚠⚨ 这个门型**今天一个失败上报都没有** ⇒ ⇒ 它**压根报不出失败** ⇒ ⇒ 本批补上）
⇒ ⇒ 连带（**实测回填**，不许推算）：全文失败上报总数 **55 → 58**、
`arch_need_count_in_fn` 的 per-函数门 **4 → 5**、`arch_need_count_in_step` 的 **3 → 4**、
段级 trailer **103 / 104 / 103 / 103 → 104 / 105 / 104 / 104**（四处各 +1）、
门项条数 **1714 → 1718**（**四处同改**）

⚠⚠⚨ **实测坐实一条新规律（与批 EJ-21 那条同源）**
恒真条件数（被扫描的 `if` / `elif` 条件总数）本批 **1115 → 1119** ⇒ ⇒ **+4**
⇒ ⇒ **+3** 来自「**改既有函数体** ⇒ ⇒ 三个新 `if`」⇒ ⇒ **+1** 来自新增的那一段
⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ 恒真数的增量来源仍然只有那两条** ⇒ ⇒ 与批 EJ-21 的坐实**一致**

⚠⚠⚨ **踩坑（当场踩到并修掉）**
① 收口块的**插入点**掉进了 `body="$(… awk -v sig="$sig" ' … ')"` 的**引号里**
　（那是**跨多行的单引号串**）⇒ ⇒ 插入的 shell 代码变成了 **awk 程序的一部分**
　⇒ ⇒ 而 `sh -n` **照样通过**（整段在引号里）⇒ ⇒ ⇒⚠ **语法自证抓不住它**
　⇒ ⇒ ⇒⚠ **修法**：插入点必须在 `')"` **之后** ＋ 加一条「**awk 正文必须逐字不变**」的自证
② 跨行门的 RX **不许含字面单引号** ⇒ ⇒ 门项 RX 用**有界通配**（`[^"]*` / `.{0,N}`）跨过
　awk 程序与 `find` 的参数 ⇒ ⇒ 而 RX 里只留**程序化生成**的字面片段
③ 跨行门的红行会**打印 RX 本身** ⇒ ⇒ ⇒⚠ **归因片段必须带上下文**
　（裸标记会同时出现在 RX 与诊断里 ⇒ ⇒ `gate-eg:` 会顶替到别的门项）
　⇒ ⇒ 归因片段取「**带上下文的诊断尾部**」（如 `**源码树根本没被扫** ⇒ 判红`）
④ ⚠⚠⚨ **归因片段必须用「运行期形态」** —— 诊断里写的是 `$_rc`（源码形态）
　⇒ ⇒ 而输出里是**展开后的值**（`2`）⇒ ⇒ 用源码形态 ⇒ ⇒ 输出里**永远不会出现**
　⇒ ⇒ ⇒⚠ `ej16-not:` 断言**空转**（永远「没出现」）⇒ ⇒ 对照实验的判据形同虚设
　⇒ ⇒ ⇒⚠ 而且**审计器自己**也报「函数体**抽不出来**」⇒ ⇒ 片段还必须**只匹配门侧**
⑤ ⚠⚠⚨ **对照实验的变异必须把「整个区域」还原**，不能只摘收口块
　⇒ ⇒ 只摘收口块 ⇒ ⇒ `for f in $_list` 引用**没赋值**的变量
　⇒ ⇒ ⇒⚠ 门侧脚本开着 **`set -u`** ⇒ ⇒ 脚本**当场中止**（rc=2）
　⇒ ⇒ ⇒⇒ ⇒⇒ 后续门项**根本没跑** ⇒ ⇒ 断言**无法评估**（表现为「文案缺失」）
　⇒ ⇒ ⇒⇒ **修法**：把 `local` 行 → 收口块 → `for` 行**整段**还原成批 EJ-22 之前的形态
⑥ ⚠⚠⚨ **仓外实验副本绝不能用硬链接**（`cp -al`）⇒ ⇒ **写副本 = 写真仓**
　⇒ ⇒ 本批实测踩到：我用 `cp -al` 造实验副本 ⇒ ⇒ 往副本里写变异
　⇒ ⇒ ⇒⚠ **真仓的同一个 inode 被改写** ⇒ ⇒ 收口块与 `find` 调用被变异覆盖
　⇒ ⇒ ⇒⚠⇒⇒ 靠 `ls -i` 对比 inode 才抓到（两处 inode **完全相同**）
　⇒ ⇒ ⇒⇒ **修法**：实验副本一律用 `cp -a`（真拷贝）⇒ ⇒ 或写「临时文件 + `os.replace`」
　⇒ ⇒ ⇒⇒ ⇒⇒ ⇒⇒ **⇒ ⇒ ⇒⇒ ⇒ ⇒ ⇒⇒ **⇒ ⇒ 教训：凡是要写副本 ⇒ ⇒ 绝不能共享 inode**

⚠⚠⚨ 负控 5 例（累计 299 → 304）
· NC300 **正向对照**（不变异 ⇒ ⇒ 接线门**绿** ⇒ ⇒ 批 EJ-22 段**全绿**）
· NC301 **负控 · 洞 ① 那条腿（行为级）**（把 `find src` 改成找**不存在**的目录
　⇒ ⇒ 清单为空 ⇒ ⇒ 门**红** ＋ 诊断说「**源码树根本没被扫**」）
· NC302 **负控 · 洞 ① 对照实验（假绿）**（同一处破坏 **＋** 把收口块**整块**摘掉
　⇒ ⇒ ⇒⇒ 那 9 条树门**照样打 ✓** ⇒ ⇒ 而收口门（形态）**红了**
　⇒ ⇒ ⇒⇒ **两者一对比** ⇒ ⇒ 证明「假绿」是**收口块**治好的）
· NC303 **负控 · 洞 ② 那条腿（行为级）**（把 awk 程序**弄坏** ⇒ ⇒ 门**红** ＋
　诊断说「**查找工具坏了**」⇒ ⇒ **且** 不许说「找不到函数」）
· NC304 **负控 · 洞 ② 对照实验**（同一处破坏 **＋** 整块摘掉收口块 ⇒ ⇒ 诊断变成
　「**里找不到函数**」⇒ ⇒ **指错方向**的那一档 ⇒ ⇒ 与 NC303 对比 ⇒ ⇒
　证明「指对方向」是**修复带来的**）

⚠⚠⚨ 数字（**实测**）：门项条数 **1714 → 1718**（**四处同改**）、门项执行次数
**1717 → 1721**、恒真 **1115 → 1119**、`|| true` 盘点 **26 不变**、失败上报登记册
**16 不变**、未验证盘点 **21 组 / 85 处**不变；段级 trailer **103 / 104 / 103 / 103**
⇒ ⇒ **104 / 105 / 104 / 104**（四处各 +1）；负控 **299 → 304**

⚠⚠⚨ 影响面：**6 个文件**（判据层 **3**：`ci-wiring.sh` / `ci-wiring-audit.py` /
`ci-wiring-gates.baseline` ＋ 文档 **3**：台账 / PLAN / README）⇒ ⇒
**零产品代码改动**（只动判据层 ⇒ ⇒ 快照零变化）
审计器 rc=0 / 接线门 rc=0（门项合计 **1721** 项）/ 恒真 rc=0（1119）/
`|| true` 盘点 rc=0（26）/ 未验证盘点 rc=0（21 组 / 85 处）⇒ ⇒ 全绿。

⚠⚠⚨ **如实记着的已知边界**
⚠ **负控 harness 本身不在仓里** ⇒ ⇒ ⇒⇒ ⇒ **CI 里仍只靠仓内的门**（⇒ ⇒ 本批落的就是仓内的门）
⚠ 本批**只**收口了 3 个调用点（树清单 1 个 ＋ 两个 awk 抽取器）⇒ ⇒
**另有 3 处次要**（trap 的 `sort` / 两处 `head -2 … | tr`）⇒ ⇒ 那些**失败 ⇒ 诊断摘录变薄**
⇒ ⇒ 本批**不动** ⇒ ⇒ **如实记**
⚠ `arch_forbid_tree` 的「清单不许为空」这一档，在**真实的空源码树**上也会红
⇒ ⇒ 那是 **fail-closed** 的正确方向（本仓永远有源码）⇒ ⇒ **如实记**
⚠ 修法把「**工具坏了**」与「**真找不到**」**分开说了** ⇒ ⇒ 但**真找不到**那一档
　（`awk` 成功、只是没匹配到）**仍然是恒红** ⇒ ⇒ 那是**另一条**问题，本批**没动**

## ⚠⚠⚨⚠⚠⚨ 批 EJ-24 · **清单型判据的清单取不到 ⇒ 报「干净」⇒ 假绿**

> **这是批 EJ-22 洞 ① 的通用形态，而批 EJ-22 只在 `ci-wiring.sh` 打了 `arch_forbid_tree` 一处。**
> ⇒ **同一个承诺，在判据脚本全集里还有 5 条腿没有牙。**

### 改了什么

**门侧（3 个判据脚本 · 5 处收口 · 零新门型）**

| # | 文件 | 位置 | 收口 |
| --- | --- | --- | --- |
| 1 | `deepin/scripts/ci-d2.sh` | 规则 1 的清单 | `_d2_files1` + `_d2_rc1` ⇒ 退出码 ≥2 ⇒ 指名道姓 + `FAIL=1` ⇒ 不进循环 |
| 2 | `deepin/scripts/ci-d2.sh` | 规则 2 的清单 | 同款（`_d2_files2` / `_d2_rc2`） |
| 3 | `deepin/scripts/ci-orphan-probe.sh` | 范围扫描 | `_orphan_files` + `_orphan_rc` ⇒ 退出码 ≥2 ⇒ `fail=1` ⇒ 不进循环 |
| 4 | `deepin/scripts/ci-orphan-probe.sh` | 判定腿 | **一个断言脚本都没判上**（`n_assert == 0`）⇒ `fail=1` |
| 5 | `deepin/scripts/check-deb-layout.sh` | 图标清单 | 图标目录存在性 + `_dl_icons` + 退出码 ≥2 ⇒ `no` ⇒ 不进循环 |

⚠ **退出码口径**：三个脚本都开着 `set -uo pipefail` ⇒ 管道的 `$?` 是**最右侧失败者**的码
⇒ **rc=1 = 「没匹配」（合法）** / **rc≥2 = 「工具坏了」（判红）**
⇒ ⚠ D2 的**命中 0 是合法的**（存量已清零）⇒ **不能用「清单不许为空」判红** ⇒ 必须按退出码分诊。

⚠ 附带修好一处**诊断失真**：孤儿探针的 `fail` 是**全局粘滞 0/1** ⇒ 拿它做平台间比较
⇒ 第一个平台红之后 ⇒ 后面平台**恒打「✓」** ⇒ ⇒ 改成**平台局部**标志 `_plat_fail`（循环体内 9 处 `fail=1` 连带置位）。

### 为什么（三例**实测坐实**的假绿）

| 场景 | 修复前 | 修复后 |
| --- | --- | --- |
| `ci-d2.sh`：注入色值违例 ＋ `grep` 坏了 | **rc=0**，报「✓ D2 命中 0/0」⇒ 散值漏检 | **rc=1**，报「扫描工具坏了（grep 退出码 2）」 |
| `ci-orphan-probe.sh`：注入游离脚本 ＋ `find` 坏了 | **rc=0**，报「✓ 平台 deepin：无游离断言脚本（**0 个**断言脚本全部在本平台 CI 里可达）」⇒ **自相矛盾却是绿的** | **rc=1**，报「清单取不到 ⇒ 断言脚本根本没被扫」 |
| `ci-orphan-probe.sh`：注入游离脚本 ＋ `grep` 坏了 | **rc=0**，同上（「0 个」） | **rc=1**，报「一个断言脚本都没判上（n_assert=0）」 |
| `check-deb-layout.sh`：零字节图标 ＋ `find` 坏了 | **rc=0**，报「✓ 包内图标都非空」，`9 passed, 0 failed` ⇒ **整门假绿** | **rc=1**，报「图标扫描工具坏了（find 退出码 2）」 |

⚠ **现有门只钉了一半**（本批最关键的一条发现）：

- `ci-wiring.sh` 里那条「孤儿探针的范围扫描必须递归」的门 ⇒ **只钉「这行在不在」** ⇒ **不钉「这行会不会空转」**
- 「什么算断言脚本」那条门的**说明文字自己写着**：「少了它 ⇒ 扫到 0 个 ⇒ 报「全部可达」⇒ **空转恒绿**」⇒ **已知危害只钉了一半**
- `ci-d2.sh` 的两条 `for _f in $(grep -rlE …)` ⇒ **一条门都没有** ⇒ **零覆盖**

⇒ **「清单取不到 ⇒ 不许当成通过」这条承诺，在判据脚本里根本没有腿。**

### 影响面

- **产品代码零改动** —— 只动判据层（`deepin/scripts/`）+ 文档。
- **6 个文件**：3 个判据脚本 + `ci-wiring.sh` + `ci-wiring-audit.py` + `ci-wiring-gates.baseline`
  ＋ 文档三处（台账 / PLAN / README）。
- **连带数字（实测回填，门项条数记四处同改）**：
  - 门项条数 **1718 → 1724**（基线文件 / 审计器常量 / `ci-wiring.sh` 里那条门 / 说明文字里的同一个数字）
  - 门项执行次数 **1721 → 1727**
  - 恒真条件 **1119 → 1127**
  - 段级 trailer **104/105/104/104 → 105/106/105/105**（四处各 +1）
  - 失败上报总数（`ci-wiring.sh`）**58 不变**；`ci-d2.sh` 的 `exit N` **6 不变**
  - 孤儿探针失败上报 **10 → 12**；孤儿探针 `echo "  ✗"` **11 → 13**；deb 布局 `(no|ok)` **15 → 17**
  - `|| true` **26** 不变；未验证 **21 组 / 85 处** 不变
- **负控 5/5 真红**（NC305–NC309，双断言：门红 **且** 诊断指名道姓）：
  - NC305 `ci-d2.sh` ＋ 坏 `grep` ⇒ 红 **且** 说「扫描工具坏了」**且** **不许**出现「✓ D2 命中 0/0」
  - NC306 孤儿探针 ＋ 坏 `find` ⇒ 红 **且** 说「清单取不到」
  - NC307 孤儿探针 ＋ 坏 `grep` ⇒ 红 **且** 说「一个断言脚本都没判上」
  - NC308 deb 布局 ＋ 坏 `find`（**合成最小 .deb**）⇒ 红 **且** 说「图标扫描工具坏了」
  - NC309 **对照实验（假绿重现）**：把 D2 **两处**收口块**整块**摘掉 ＋ 坏 `grep` ⇒ **门还绿**（报「✓ D2 命中 0/0」）
    ⇒ ⇒ 与 NC305 **两者一对比** ⇒ 证明「假绿」是**收口块**治好的，不是本来就有的

### 本批**不做**的事

- `ci.sh` 本体不进矩阵（重 ＋ 与负控回归并发 ⇒ rc=2 风险）⇒ 单列。
- `build-deb.sh` 的 `for p in $(cat "$TMP/deps.list")`（2 处）⇒ ① 是**构建脚本**不是判据脚本
  ② `build-deb.sh` **长期豁免**（有副作用）⇒ 本批不动。
- `probe-agent-tool-surface.sh` 的 `for a in $(printf … | tr)` ⇒ 实测 **tr 坏了 rc=1（有牙）** ⇒ 不是洞。
- `ci-docs-lang-probe.sh` 的 `tr` ⇒ 只在错误诊断文案 ⇒ 不是洞。
- **「并发重 I/O ⇒ rc=2」** ⇒ 归批 EJ-23（机理已静态收敛，实测复现待机器空闲）。

### 踩坑

① `.{0,N}` 的 N 必须按**字节**算（grep 在 C locale 下 `.` 匹配**字节**）⇒ 按字符算 ⇒ 通配长度不够 ⇒ **RX 命中 0**。
② `re.escape` 会把空格转义成 `\ ` ⇒ GNU grep -E **认**（但别自己手抄）。
③ **嵌套引号**（`_d2_files1="$(grep … "$D2_PATTERN" …)"`）⇒ 按「双引号段」切分的 RX 生成法**会切错**
   ⇒ ⇒ 改用「**按行取关键锚点 + 有界通配**」。
④ 门自审计（rc=8）要求**适用范围内**（`ANCHOR_SCOPE_SUFFIXES` 含 `ci-d2.sh` / `ci-orphan-probe.sh` /
   `check-deb-layout.sh`）的 `arch_need_count` 门项**整行锚定** ⇒ 新 RX 漏了 `$` ⇒ 门自审计红。
⑤ 既有门项被改到形态变了 ⇒ **RX 与期望值必须同步**（批 EJ-21 纪律）⇒
   说明文字里的同一个数字也要一起改（`check_label_count_text` rc=9 会查）⇒ 写法有多种
   （「恰好 N 处」/「恰好是 N」/「（N 处 …）」）⇒ 泛化成「数词 + 量词」上下文。

## ⚠⚠⚨⚠⚠⚨ 批 EJ-26 · **locale 钉死 ＋ 「紧挨类」门项的窗口不许有富余**

> 起因：最终轮全量负控（309 例）里**唯一的真阳性**（**NC289**）⇒ ⇒ 坐实「门项的说明文字在骗人」。

### 改了什么

- **两侧 locale 钉死**（各一行，零新门型）
  - 门侧：`ci-wiring.sh` 顶部 `export LC_ALL=C`
  - 审计器侧：`ci-wiring-audit.py` 里 `os.environ['LC_ALL'] = 'C'`（**进程级** ⇒ 它拉起的**每一个**外部工具都继承）
  - ⇒ ⇒ 门项窗口语义**只由字节数决定** ⇒ ⇒ **结论不随机器、不随 locale 变**
- **11 条 `.{0,N}` 门项的窗口全部收紧到零余量**（=「刚好还能匹配期望次数」的最小值）
  ⇒ ⇒ 再塞**一个字节**就匹配不上 ⇒ ⇒ **插一行必红**
- **审计器新增「窗口零余量」自校准**（`check_window_slack`，rc=4 复用「次数门没配准」那一档）
  ⇒ ⇒ 以后谁把窗口放宽 ⇒ ⇒ **审计器当场判红**
- 连带同步既有门项 **4 条**：RC=4 的失败态计数（1 → 2）＋ `FAIL_GUARDS` 登记册 ＋ 段级 trailer 四条 ＋ 门项条数说明文字

### 为什么（**实测坐实**，不是推演）

① **窗口太宽**：G3 那道跨行门 `TOOL_FAILURES:.{0,600}FAILS\.append\(2)` 的窗口 600，
   实际空隙只有 **557 字节** ⇒ ⇒ 插一行（+54 字节）⇒ ⇒ 610 ≤ 600 ⇒ ⇒ **门照样绿**
② **`.` 的口径随 locale 变**：UTF-8 locale 下 `.` 匹配**字符** ⇒ 空隙 442 字符
   ⇒ ⇒ 插一行后 510 ≤ 600 ⇒ ⇒ **照样绿**；C locale 下 `.` 匹配**字节**
   ⇒ ⇒ 668 > 600 ⇒ ⇒ **门红** ⇒ ⇒ **同一份代码、同一道门，两种环境结论相反**

⇒ ⇒ 门项**自己的说明文字**写着「必须**紧挨**」⇒ ⇒ 而它**抓不住** ⇒ ⇒ **说明文字在骗人**（批 EA 的 rc=9 那一族）。

### 影响面

- 仓内共 **11** 条门项的 RX 用了 `.{0,N}`（`ci-wiring.sh` 里）
  ⇒ ⇒ 本批**全部**收紧到零余量 ⇒ ⇒ 「插别的行 ⇒ 要红」这条承诺**第一次是真的**
- 门侧与审计器的**所有**正则 grep 现在都在**字节口径**下跑 ⇒ ⇒ 两侧同口径

### 本批**不做**的事

- `ci.sh` 本体（重 ＋ 并发 ⇒ rc=2 风险，单列）
- `build-deb.sh`（**长期豁免**，有副作用）
- 批 **EJ-25**（「一处工具失败 ⇒ 82 条门项一起登记 ⇒ 诊断放大 82 倍」）**已在批 EJ-25 完成**（⇒ ⇒ 不再是待办）

### 踩坑

① **改判据层代码 ⇒ ⇒ 先跑审计器拿诊断 ⇒ ⇒ 再逐条同步**（批 EJ-12 / EJ-21 纪律）：
   本批新增 5 条门项 ⇒ ⇒ 段级 trailer 四条的期望值与**说明文字里的同一个数字**都要跟着改。
② 文档落盘脚本**不幂等** ⇒ ⇒ 台账 / PLAN / README **分 part 执行** + 每 part 带幂等保护。
③ 锚点**同一段文字可能在文件里出现多次**（本批的「批 CG」锚点在文件头也有一份）
   ⇒ ⇒ 插入必须用 **rfind**（最后一份）⇒ ⇒ 用 `replace(..., 1)` 会插到**文件头** ⇒ ⇒ 门脚本直接坏掉。
④ 「先改 `lines` 列表、最后再 `join` 回 `src`」⇒ ⇒ 中途对 `src` 的其它改动**会被覆盖**。

## ⚠⚠⚨⚠⚠⚨ 批 EJ-27 · **「放弃这一条」这个行为本身必须被钉住**（G3 门只钉了第一行）

> 起因：批 EJ-26 的**全量负控回归（314 例）**里**唯一的真阳性**（**NC292**）
> ⇒ ⇒ 坐实「`if got is None:` 的**行数**有人守，但**它下面的 `continue` 没人守」。

### 改了什么

- 把 G3 那条门从**单行门**改成**跨行门**
  - 旧：`arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+if got is None:$' 6`
  - 新：`arch_need_count_ml "$SRC/scripts/ci-wiring-audit.py` '<跨行 RX>' 6`
  - ⇒ ⇒ RX 钉住「`if got is None:` **紧跟** `continue`」这个**两行的相邻关系**
  - ⇒ ⇒ **期望值仍是 6** ⇒ ⇒ **门项条数 1729 → 1729（不变）**
    ⇒ ⇒ 「门项条数记四处」**四处都不用改** ⇒ ⇒ 少一处同步点 ⇒ ⇒ 风险更低
- RX **程序化生成**（从源文件推导 ⇒ 空格串折叠成 `[[:space:]]+`）＋ **真 grep 自检**
  ⇒ ⇒ 「正则**绝不手抄**」这条纪律守住

### 为什么（**实测坐实**，不是推演）

① 负控 **NC292**：把 `check_any_gates` 里那处 `continue` 换成 `got = 0`
   ⇒ ⇒ 「拿到 None ⇒ **当成 0 命中**」⇒ ⇒ 工具坏了混进「次数门没配准」那一档
   ⇒ ⇒ 而 G3 门**只盯 `if got is None:` 的行数** ⇒ ⇒ 命中仍是 **6** ⇒ ⇒ **门照样绿**
   ⇒ ⇒ 实测接线门 **rc=0** ⇒ ⇒ 「工具坏了 ⇒ **放弃这一条**」这条承诺**被破坏**
② 改完再跑同一例 ⇒ ⇒ 命中掉到 **5** ⇒ ⇒ **门红** ⇒ ⇒ 新门**有牙**

### 自带保护（为什么不需要额外的「元门」）

新 RX 里含 `continue` ⇒ ⇒ 逐行口径下**没有一行**同时含这两段
⇒ ⇒ 若有人把门型改回 `arch_need_count` ⇒ ⇒ 命中 **0** ⇒ ⇒ 期望 6
⇒ ⇒ **门恒红** ＋ 审计器校准也红 ⇒ ⇒ **双保护** ⇒ ⇒ 无需再加一条「盯门型」的门。

### ⚠⚠⚨ 踩坑点（实测坐实，已在生成器里绕开）

压行时 `strip_comments` 只剥「**行首空白 + #**」⇒ ⇒ **docstring 里的文字剥不掉**
⇒ ⇒ audit.py 的 docstring 里有一处「…都是 `if got is None: continue`」
⇒ ⇒ 朴素 RX 会**多命中 1 处（7 ≠ 6）**⇒ ⇒ RX 必须带**前导空白约束**
⇒ ⇒ 代码行前面是空格；docstring 那处前面是「`」⇒ ⇒ 天然分开。

### 影响面

- 门项条数 **1729 → 1729（不变）**｜门项执行 **1732 → 1732（不变）**
- 批 EJ-26 的 11 条零余量窗口**不受影响**（本批没碰那些 RX）

### 本批**不做**的事

- 批 **EJ-25**（「一处工具失败 ⇒ 82 条门项一起登记 ⇒ 诊断放大 82 倍」）**已在批 EJ-25 完成**（⇒ ⇒ 不再是待办）
- `ci.sh` 本体（重 ＋ 并发 ⇒ rc=2 风险，单列）
- `build-deb.sh`（**长期豁免**，有副作用）

## ⚠⚠⚨ 批 EJ-25 · **一处工具失败 ⇒ 82 条门项一起登记 ⇒ 诊断放大 82 倍**

> 主题：「承诺不许**悄悄变红**」那一族 —— 红得没有道理 ⇒ 读者被淹没 ⇒ 没人看得出真因。

### 改了什么

- 审计器 `AnyCounter._script()`：批量脚本由「**一刀切**」改成「**逐对容错继续**」
  - 以前每一对是「先取值、失败就非 0 退出」⇒ ⇒ **任何一对**失败 ⇒ ⇒ 整批脚本立刻退出
    ⇒ ⇒ 后面的对**根本没跑** ⇒ ⇒ 审计器只看到「rc≠0」
  - 现在：失败的那对**没有 stdout 行** ⇒ ⇒ 落进审计器**本来就有的** `missing` 分支
    ⇒ ⇒ ⇒ **逐对**登记 ⇒ ⇒ ⇒ **零放大**
  - 附带：stderr 打一行 `ANYFAIL` ⇒ ⇒ 排障时能直接看到**是哪一对**
- ⚠⚠⚨ **审计器的失败态计数与 `FAIL_GUARDS` 登记册**：**实测未变**
  ⇒ ⇒ 改法只在 `AnyCounter._script()` 一处 ⇒ ⇒ **零登记册改动** ⇒ ⇒ **零 rc 语义改动**
  ⇒ ⇒ 「一条承诺两条腿分开证」这条纪律守住 ⇒ ⇒ 且 rc 仍是 2（失败**没被吞掉**）

### 为什么（**实测坐实**，不是推演）

把**一条** `arch_need_any_count` 的 RX 改成**非法正则** ⇒ ⇒ grep 退出 2
⇒ ⇒ **恰好那一对**失败 ⇒ ⇒ 旧行为：审计器把**全部 82 条门项**都登记成「工具用不了」
⇒ ⇒ **放大 82 倍** ⇒ ⇒ 真因被淹没。

⚠⚠⚨ 登记的语义是「**没被审**」（批 EB 立的）⇒ ⇒ 其余 81 对**其实被审了**（值算出来了）
⇒ ⇒ 把它们登记成「没被审」**本身就是登记错了** ⇒ ⇒ 违反批 EB「指名道姓」那条承诺。

### 影响面

- 审计器一处（`AnyCounter._script()`）＋ 落门 4 条 ＋ 门项条数四处同改
- ⇒ ⇒ **零产品代码改动**（只动判据层）

### 本批**不做**的事

- `ci.sh` 本体（重 ＋ 并发 ⇒ rc=2 风险，单列）
- `build-deb.sh`（**长期豁免**，有副作用）

### 踩坑

① **跨行门（`*_ml`）的 RX 必须按「压行后」的文本生成**！⇒ ⇒ RX 里带着**换行符**
   ⇒ ⇒ grep 把它当**多条 pattern** ⇒ ⇒ 命中数**虚高**（实测：G2 命中 6 次、G4 命中 7 次 ⇒ 真值都是 1）。
② 压行会**剥掉注释行** ⇒ ⇒ 「找原文」也必须在**压行后的文本**里找
   ⇒ ⇒ 否则会撞上注释里的同名串（实测 G3 撞到注释行 ⇒ 命中 0 次）。
③ 源码的**缩进**进了 RX ⇒ ⇒ 源码一改缩进 ⇒ ⇒ 门**假红** ⇒ ⇒ 空格串折叠成 `[[:space:]]+`
   （⚠ `[[:space:]]` 在 C 与 UTF-8 locale 下**都**只认 ASCII 空白 ⇒ ⇒ locale 无关）。

## ⚠⚠⚨ 批 EJ-28 · **「指名道姓」只在源码里 ⇒ ⇒ 运行时 stderr 被丢弃 ⇒ ⇒ 承诺没兑现**

> 主题：「承诺不许**悄悄变弱**」那一族 —— 形态门钉住了源码，**运行时行为**却没人守。

### 起因：批 EJ-23 收尾的**定向复现**（候选④ 结案 ⇒ ⇒ 顺带挖出这一条）

- 候选④（`any_hits` 批量放大）⇒ ⇒ **机制坐实 ＋ 批 EJ-25 已修 ＋ 修后零放大已实测**
  ⇒ ⇒ 本批是这个待查项的**副产品**
- ⚠⚠⚨ 但复现时**顺手**发现一条**新洞**（见下）

### 改了什么

- 审计器 `AnyCounter._run()`：**读**批量脚本的 stderr ⇒ ⇒ 解析 `ANYFAIL` ⇒ ⇒
  翻译成**那一对**的 path + RX ⇒ ⇒ 并**原样透出**到审计器 stderr
- 指名逻辑**抽成辅助函数** `_anyfail_why()`（批 DA/DB 纪律：判定抽成函数）
  ⇒ ⇒ **理由**：批 EJ-25 那条门守的是「`rx_, gl_ = self.pairs[i]` **紧跟** `_tool_failed(`」
    ⇒ ⇒ 把指名逻辑**内联**进循环体会**打断**那个紧挨关系 ⇒ ⇒ 那道门会恒红
    ⇒ ⇒ 抽成函数 ⇒ ⇒ **紧挨关系原封不动** ⇒ ⇒ 旧门继续有效
- 落门 3 条（**零新门型**）：读 stderr ＋ 指名判定＋透出 ＋ 指名文案
  ⇒ ⇒ RX **程序化生成**（从源码取原文再转义，按**压行后**口径）＋ **真 grep 自检**
    （命中各 1 处）＋ **门有牙自检**（变异一处 ⇒ ⇒ 命中掉到 0）

### 为什么（**实测坐实**，不是推演）

- 把**一条** `arch_need_any_count` 的 RX 改成**真非法正则**（末尾追加一个 `[`
  ⇒ ⇒ 未闭合字符类 ⇒ ⇒ `grep` 退出 **2**）⇒ ⇒ **恰好那一对**失败
- ⇒ ⇒ 审计器 rc=2（工具用不了）✔ ｜ 汇总总数 **1** ｜ 明细 **1** 条（零放大）✔
- ⇒ ⇒ ⚠⚠⚨ **但输出里 `ANYFAIL` 出现 0 次** ⇒ ⇒ 「指名道姓」**只在源码里**
  ⇒ ⇒ 根因：批量脚本的 stderr 在 **rc=0 分支被直接丢弃**
  ⇒ ⇒ EJ-25 那行 `printf 'ANYFAIL\t%d\n' >&2` **白打了**
  ⇒ ⇒ ⇒ **形态门 ≠ 行为门** ⇒ ⇒ 落门只钉住了**源码形态** ⇒ ⇒ 钉不住**运行时**
- ⇒ ⇒ 修完：**`→ ANYFAIL 第 0 对：<path> | <RX>`** 出现在审计器输出里 ✔
  ⇒ ⇒ 且**零放大不受影响**（汇总 1 ＋ 明细 1 ＋ ANYFAIL 1）

### 连带数字（实测回填 · 门项条数记四处同改）

| 口径 | 前 | 后 |
| --- | --- | --- |
| 门项条数 | 1733 | **1736** |
| 门项执行次数 | 1736 | **1739** |
| 段级 trailer | 107/108/107/107 | **108/109/108/108** |

`|| true` **26** 不变；未验证 **21 组 / 85 处** 不变。

### ⚠⚠⚨ 负控里**订正**了一处**用例缺陷**（工具侧 · 非仓内）

- NC315 原来把 RX 里的 `\(` 改成 `(` ⇒ ⇒ **那不是非法正则**（`(` 是 ERE 的**分组**）
  ⇒ ⇒ `grep` **不会**退出 2 ⇒ ⇒ NC315 实际测的是「RX 改了 ⇒ 命中数变 ⇒ 校准失准」
  ⇒ ⇒ **不是**它描述的「工具失败 ⇒ 工具用不了」⇒ ⇒ **描述与实现不符**
- ⇒ ⇒ **订正**：改成**真非法**（末尾追加一个 `[`）⇒ ⇒ `grep` 退出 2（实测 stderr =
  `grep: Invalid regular expression`）⇒ ⇒ 这才真正测到 EJ-25 的承诺场景
- ⚠⚠⚨ 顺带记一条**通用教训**：**ERE 里 `(` 是分组，不是非法元字符** ⇒ ⇒
  「把 `\(` 改成 `(`」**造不出非法正则** ⇒ ⇒ 「造非法正则」得用**未闭合字符类**（`[`）

### 负控 5 例（NC318～NC322 · 双断言：门红 **且** 行为符合预期）

| 用例 | 变异 | 审计器 | 指名行 | 「第 N 对」 |
| --- | --- | --- | --- | --- |
| NC318 | `ANYFAIL\t` → `ANYFAILX\t`（解析不出） | rc=9（门项失准） | **0** | **0** |
| NC319 | `if idx in anyfail:` → `not in`（判定取反） | rc=9 | **0** | **0** |
| NC320 | 指名文案「第 %d 对」→「第 %d 条」 | rc=9 | 1 | **0** |
| NC321 | 删掉指名行的 `print`（透出被摘） | rc=9 | **0** | 1 |
| **NC322** | **不变异**（**对照实验**） | rc=2 | **1** | **2** |

⚠⚠⚨ **计数口径**（实测踩到）：**不能数 `ANYFAIL`** ⇒ ⇒ 审计器在 `--list` 模式下会
**打印门项 RX 本身** ⇒ ⇒ 门项 RX 里含 `ANYFAIL` ⇒ ⇒ 那个计数被**污染** ⇒ ⇒ 归因失真
⇒ ⇒ 必须数**指名行**（`→ ANYFAIL`）。

### ⚠⚠⚨ 本批自己的踩坑（如实记录 · 不是推演）

为了快速确认「G3 那道门到底失准没」，我在**真仓**上直接做了变异
⇒ ⇒ 随后用 `git checkout <file>` 撤销
⇒ ⇒ ⚠⚠⚨ **把该文件里所有未提交的改动一起冲掉了**（批 EJ-28 的审计器修法 ＋ 条数常量）
⇒ ⇒ 靠 `/tmp` 的**事前副本**反向还原才救回来
⇒ ⇒ ⇒ **教训三条**：
① **负控变异绝不在真仓上做** ⇒ ⇒ 一律在 `cp -a` 副本上做
   （前面 300+ 例一直守这条 ⇒ ⇒ 这次图快破了 ⇒ ⇒ **破在最后一步**）
② **`git checkout <file>` 会连带丢掉该文件的全部未提交改动**
   ⇒ ⇒ 撤销单文件**必须**用「备份 ＋ 精确还原」
③ 事后两侧重跑（审计器 rc=0 ｜ 接线门 rc=0 ｜ 门项条数 1736 ｜ 门项执行 1739 ｜ 红行 0）
   ⇒ ⇒ 确认恢复**无残留**

⚠⚠⚨ 这条本身就是「承诺不许**悄悄消失**」那一族 ⇒ ⇒ **工具侧也会犯**
⇒ ⇒ 而它能被发现，只因为**两侧都重跑了** ⇒ ⇒ 「跑完必须重跑两侧」这条纪律**继续有效**。

### 本批**不做**的事

- 候选①（写失败 ⇒ `grep` 退 2 ⇒ rc=2）—— ⚠⚠⚨ **已结案**（批 EJ-23 收尾）：
  `ulimit -f 1` ⇒ ⇒ **退出码 153**（SIGXFSZ）⇒ ⇒ 链**坐实** ⇒ ⇒
  但批 EJ-13 / EJ-21 的**三态收口**让它**红得有名有姓** ⇒ ⇒ **不改判据层**
- `ci.sh` 本体（重 ＋ 并发 ⇒ rc=2 风险，单列）
- `build-deb.sh`（**长期豁免**，有副作用）

## ⚠⚠⚨ 批 EJ-23 · **收尾结案** · 「并发重 I/O ⇒ rc=2」的四个候选**全部结案**

> 这条待查项卡住「并发跑门禁」⇒ ⇒ 卡住吞吐 ⇒ ⇒ 查清它才能并行。
> ⇒ ⇒ 现在**结案**：四个候选**逐一**定向复现（不是「等它自己出现」）。

### 候选② / ③ —— ✅ **排除**（本轮沿用批 EJ-24 的活体测量，已足够）

| 候选 | 实测 | 结论 |
| --- | --- | --- |
| ② **fd 耗尽**（EMFILE） | `ulimit -n` = **1048576**（不是 1024）；运行中的门/审计器进程 fd 只有 **3–7 个** | ✅ 排除 |
| ③ **fork/exec 失败**（EAGAIN） | 进程总数 **376**（8 核）；且顶层把 OSError 归 **rc=10** 不是 rc=2 | ✅ 基本排除 |

### 候选④ —— ✅ **坐实 ＋ 已修 ＋ 修后实测**

- 机制**坐实**（把**一条** `arch_need_any_count` 的 RX 改成非法正则 ⇒ ⇒ 一对失败
  ⇒ ⇒ 旧行为把**全部 82 条门项**登记成「工具用不了」⇒ ⇒ **放大 82 倍**）
- ⇒ ⇒ **批 EJ-25 已修**（批量脚本改成**逐对容错继续**）
- ⇒ ⇒ **修后实测**（批 EJ-28 的定向复现，`--list` 模式）：
  一对失败 ⇒ ⇒ 汇总总数 **1** ＋ 明细 **1** ＋ 指名行 **1** ⇒ ⇒ ⇒ **零放大坐实**

### 候选① —— ✅ **坐实**（本轮新做 · 定向复现）

- 手法（**不用 sudo**）：`ulimit -f 1`（限制单文件写入 512 字节）
  ⇒ ⇒ 写超了 ⇒ ⇒ `grep` 的输出**写不进去** ⇒ ⇒ **退出码 153**（128+25 = SIGXFSZ）
- ⇒ ⇒ **链坐实**：写失败 ⇒ ⇒ 退出码 ≠ 0/1 ⇒ ⇒ 工具用不了
- ⇒ ⇒ ⚠⚠⚨ **但危害早已被治**（批 EJ-13 / EJ-21 的**三态收口**）：
  门侧**指名道姓**地说「**查找工具 grep 不可用或正则无效（退出码 153）⇒ 本场命中数不可信
  ⇒ ⇒ 未验证不许被当成通过**」⇒ ⇒ stderr 里还有 `File size limit exceeded`
  ⇒ ⇒ ⇒ **红得有名有姓** ⇒ ⇒ 不是「命中 0 次」那种误导诊断
  ⇒ ⇒ ⇒ ⇒ **不需要再改判据层**
- 审计器侧单独限 ⇒ ⇒ rc=**10**（崩了）⇒ ⇒ 与批 CW 立的「崩了 ⇒ rc=10」**一致**
- `ulimit -f 0`（一个字都不许写）⇒ ⇒ 连门侧脚本自己都被 SIGXFSZ 打死（rc=-25）
  ⇒ ⇒ 更极端的一档 ⇒ ⇒ 同样**不是**假绿

### 结论

⇒ ⇒ **四个候选全部结案** ⇒ ⇒ 「并发重 I/O ⇒ rc=2」这条待查项**关闭**
⇒ ⇒ ⇒ 剩下的真实边界是**并发时的瞬时工具失败**（不是 rc=2 语义问题）
⇒ ⇒ ⇒ 而它已被「两侧都能重试才许 `retry=True`」那条纪律覆盖

### 本批**不做**的事

- `ci.sh` 本体（重 ＋ 并发 ⇒ rc=2 风险，单列）
- `build-deb.sh`（**长期豁免**，有副作用）

## ⚠⚠⚨ 批 EJ-29 · **forbid 门项的「RX 有效性」⇒ ⇒ 恒绿 = 没牙 ⇒ ⇒ 静态不可区分**

> 主题：「承诺不许**悄悄变绿**」那一族 —— `arch_forbid*` 门项的**正确状态就是 0 命中**
> ⇒ ⇒ 「禁住了」与「RX 匹配不到任何东西」在仓内**静态状态下无法区分**。

### 起因（**实测坐实**，不是推演）

- forbid 族共 **101** 条门项（70 `arch_forbid` ＋ 14 `arch_forbid_ml` ＋ 9 `arch_forbid_tree`
  ＋ 4 `arch_forbid_han` ＋ 3 `arch_forbid_raw` ＋ 1 `arch_forbid_text_dup`）
- ⇒ 其中 **96** 条**带正则**（可采样）；**5** 条**无正则**（`arch_forbid_han` 4 条 ＋
  `arch_forbid_text_dup` 1 条 ⇒ ⇒ 没有 RX ⇒ ⇒ 无从采样 ⇒ ⇒ 报「无法判定」）
- ⚠⚠⚨ **审计器自己早就写着这件事**（改之前的原文）：
  - 「**【只审 arch_need，不审 arch_forbid】**」
  - 「forbid 家族是**有意不审**」
  - 「对 `arch_forbid` 门这是**静默**失效（forbid 本来就常年绿 ⇒ 写坏了跟没写一样）」
- ⇒ ⇒ ⇒ **「恒绿」本来就分不清「禁住了」和「没牙」** ⇒ ⇒ 仓内**早就知道**
  ⇒ ⇒ ⇒ 只是**没人把它变成机器检查** ⇒ ⇒ 本批做这件事

### 原理（**逻辑上的不可能** ⇒ ⇒ 所以只能这么解）

- forbid 门的**正确状态就是「目标串出现 0 次」** ⇒ ⇒ 「命中 0」既是「**禁住了**」（对），
  也可能是「**RX 匹配不到任何东西**」（**恒绿 = 没牙** ⇒ 门形同虚设
  ⇒ ⇒ 比没门更坏：给人虚假的安全感）
- ⇒ ⇒ ⇒ 两者在仓内**静态状态下无法区分** ⇒ ⇒ ⇒ **静态校准原理上不可能**
- ⇒ ⇒ ⇒ **唯一解**：造一个**必然匹配**的样本 ⇒ ⇒ 注入被查文件的副本 ⇒ ⇒ 门必须红
  ⇒ ⇒ ⇒ 这才是「有牙」的**正面证据**

### 改了什么

- 审计器新增 **ERE 采样器**（`ere_sample` 族）：字面量 / `.` / 转义元字符 /
  字符类（含 `[^...]` 与 POSIX 类）/ 量词（`*` `+` `?` `{n,m}` ⇒ ⇒ **回看原子**重复）/
  分组与 `|`（取**第一支**）/ 锚点（忽略）/ `\d` `\w` `\s` /
  `\b` `\B` `\<` `\>`（**零宽断言** ⇒ 实测 GNU grep -E **认** `\b`）
- 审计器新增 `check_forbid_teeth()`：**两条腿** ⇒ ① **RX 可满足性**（采样出的样本
  ⇒ ⇒ **真 grep** 必须匹配得上）⇒ ② **门真能红**（样本注入副本 ⇒ ⇒ 命中数必须**涨**）
- ⚠⚠⚨ **只报确定项**：采不出来 ⇒ 「**无法判定**」⇒ ⇒ ⇒ **绝不报洞**（不制造假阳性）
- ⚠⚠⚨ **解析器的覆盖率必须对账**（`count_forbid_gate_lines()` **独立**数一遍）
  ⇒ ⇒ 解析器被掏空 ⇒ ⇒ 「有门项**根本没被审**」必须**报出来**（否则静默失效）
- 落门 **7 条**（**零新门型**）：调用点 ＋ 判红接线 ＋ 采样器 ＋ 自检 ＋ 解析器
  ＋ 覆盖率对账 ＋ **腿的指名**

### 实测结论（**当前仓库**）

| 口径 | 数值 |
| --- | --- |
| forbid 门项总数 | 101 |
| 带正则（可采样） | **96** |
| **实测有牙**（采样 ＋ 真 grep 匹配得上） | **96 / 96** |
| **没牙** | **0** |
| 无从判定（族里没有 RX） | 5（`arch_forbid_han` 4 ＋ `arch_forbid_text_dup` 1） |

⇒ ⇒ **「全部 forbid 门都有牙」现在是**当前仓库的**实测结论**，不是假定。

### ⚠⚠⚨ 顺带修好一条**真阳性**（**批 EJ-28 全量回归逮到的**）

- 批 EJ-28 全量回归（322 例）里 **NC276**（批 EJ-15 的**正向对照**）不过
  ⇒ ⇒ 查出来是**真阳性**，不是用例陈旧：
  - 台账（批 EJ-15）白纸黑字承诺：「只有计数档 `grep -c` 坏 ⇒ ⇒ 审计器要
    **指名道姓**说「计数工具 grep 不可用」」
  - 实测（受限 PATH · 只坏计数档）：rc=2 ✔、「工具用不了」✔、没混进「次数门没配准」✔、
    82 对零放大 ✔ ⇒ ⇒ **唯独**那句话**没出现** ✗
  - 根因：批 EJ-25/EJ-28 把失败态上报改成「**逐对**指名」⇒ ⇒ 「**哪一对**」保住了
    ⇒ ⇒ **「哪条腿」这一维丢了** ⇒ ⇒ ⇒ 承诺**悄悄变弱**了
- ⇒ ⇒ 修法：把批量脚本 stderr 里**腿级**的失败消息（`… grep 不可用 …`）也**去重透出**
  ⇒ ⇒ 现在**既指名「哪一对」、又指名「哪条腿」** ⇒ ⇒ 承诺兑现（比原来更好）

### ⚠⚠⚨ 本批自己踩的三个坑（**如实记录** · 全部实测坐实）

① **用 `find` 列源码树** ⇒ ⇒ 受限 PATH 下 `find` 不可达 ⇒ ⇒ `FileNotFoundError`
   ⇒ ⇒ **审计器崩了**（rc=10）⇒ ⇒ 违反「工具坏了不许崩」
   ⇒ ⇒ ⇒ 改用 Python 的 `os.walk`（口径与门侧那条 `find` 一致 ⇒ 零 PATH 依赖）
② **grep 调用没接 `OSError`** ⇒ ⇒ 同上 ⇒ ⇒ 统一走 `_ere_grep()`
   ⇒ ⇒ 工具起不来 ⇒ ⇒ 登记「工具用不了」⇒ ⇒ 报「**无法判定**」⇒ ⇒ **不报洞**
③ **自检把「工具不可用」当成了「洞」** ⇒ ⇒ 受限 PATH 下**假阳性**报成「14 条没牙」
   ⇒ ⇒ 自检结果改成**分类**返回（`bad` / `undet`）⇒ ⇒ 工具坏了 ⇒ **无法判定**
   ⇒ ⇒ ⇒ 实测「没牙」= **0** 条

⇒ ⇒ 三条都被**负控**逮到（**NC329** 盯的就是「不许崩 ＋ 不许假阳性」两件事）。

### 连带数字（实测回填 · 门项条数记四处同改）

| 口径 | 前 | 后 |
| --- | --- | --- |
| 门项条数 | 1736 | **1743** |
| 门项执行次数 | 1739 | **1746** |
| 段级 trailer | 108/109/108/108 | **109/110/109/109** |

`|| true` **26** 不变；未验证 **21 组 / 85 处** 不变。

## ⚠⚠⚨ 批 EJ-30 · **工具瞬时失败 ⇒ ⇒ 假红**（计数那两条腿必须重试一次）

> 主题：「承诺不许**悄悄变红**」那一族 —— **负载抖一下**不该让门翻脸。

### 起因（**实测坐实**，不是推演）

- 批 EJ-29 的全量回归（329 例 · 2 worker）里出现**「变异前就红了」**（用例无效）的用例
- ⇒ ⇒ **不是**用例陈旧 ⇒ ⇒ 隔离重跑 **NC1 = 真红** ⇒ ⇒ **仓内承诺没破**
- ⇒ ⇒ ⇒ 说明是**环境**（负载）把门**弄红了** ⇒ ⇒ ⇒ **假红**（批 DL：**假红比假绿更坏**）

#### ⭐ **指纹法**：把「哪条门红」从「猜」变成「算」

- 门脚本输出里**含 `✗` 的行数**是可数的 ⇒ ⇒ 绿跑时 = **31**（= 说明文字里带 `✗` 的
  `✓` 门项行，**实测逐条数出来**）
- 红跑时 = **35** ⇒ ⇒ 多出 **4** 行 ⇒ ⇒ 逐条对上：
  ① 「门自审计没过」**1** 行 ② 审计器「工具坏了（腿）」**1** 行
  ③ 段级汇总 **1** 行 ④ 全局汇总 **1** 行
- ⇒ ⇒ ⇒ **35 = 31 + 4** ⇒ ⇒ ⇒ **精确指向「审计器 rc=2」** ⇒ ⇒ ⇒ 即
  「**计数那两条腿**的 grep 瞬时失败」⇒ ⇒ ⇒ 门红 ⇒ ⇒ ⇒ **假红**坐实

#### 频率（同一轮回归里实测 · **快照时刻：回归跑到 224 例时**）

| 口径 | 数值 |
| --- | --- |
| 已跑用例（**快照**） | 224 |
| 「变异前就红了」（= 瞬时假红） | **7**（NC1 / NC107 / NC154 / NC157 / NC159 / NC168 / NC176） |
| 占比 | **≈ 3.1%** |

⚠ **这是快照**，不是终值 ⇒ ⇒ 回归继续跑 ⇒ ⇒ 数字**还会变** ⇒ ⇒ 但**定性结论不变**
（**「变异前就红了」都是瞬时假红** ⇒ ⇒ 隔离重跑即真红 ⇒ ⇒ 仓内承诺没破）。

⇒ ⇒ 负载越高越多 ⇒ ⇒ ⇒ 这不是「偶发」⇒ ⇒ ⇒ 是**必须治**的那一类。

### 改了什么（**只动判据层** ⇒ ⇒ 零产品代码改动）

- ⚠⚠⚨ **门侧**：`wiring_count_hits` 的**两条腿** ＋ `any_hits` 的**两条腿**
  ⇒ ⇒ 工具失败 ⇒ ⇒ **重试一次** ⇒ ⇒ 仍失败 ⇒ ⇒ 照旧判红 ＋ 指名道姓
  - ⇒ ⇒ **覆盖写**（`>`）⇒ ⇒ 两次结果**不会加起来**（计数不许翻倍）
  - ⇒ ⇒ **只重试一次**（不许无限重试 ⇒ 不许把「工具坏了」拖成假绿）
- ⚠⚠⚨ **审计器**：新增 `run_tool_count()` ⇒ ⇒ **只取第二次的输出**
  - ⇒ ⇒ 为什么**不用** `run_tool(retry=True)`：批 EJ-11 的口径是「重试成功 ⇒ 返回
    **第一次 + 第二次**的输出」⇒ ⇒ 对**计数**来说那会把命中数**翻倍**
    ⇒ ⇒ ⇒ 与门侧（覆盖写）**口径不一致**⇒ ⇒ ⇒ 改成显式调**两次** `run_tool`
    ⇒ ⇒ ⇒ **与门侧逐字同口径**
  - ⇒ ⇒ 六个**计数族**调用点改走重试入口：`count_hits` / `count_hits_ml` /
    `count_lines` / `_grep_count_text` / `check_count_in_fn_gates` /
    `check_count_in_step_gates`
- ⚠ **`_ere_grep` 不动**（**匹配族**）⇒ ⇒ 工具失败 ⇒ ⇒ 「**无法判定**」⇒ ⇒ **不报洞**
  ⇒ ⇒ ⇒ **不假红** ⇒ ⇒ ⇒ 不在本口径内（**范围写在门项说明文字里**）
- ⇒ ⇒ 落门 **11 条**（**零新门型**）：审计侧 7 条 ＋ 门侧 4 条

### 实测（**负控 4 例** ＋ **门有牙自证**）

⇒ ⇒ 同一组用例跑**两棵树**：打了补丁的副本 ＋ **未打补丁的真仓**
⇒ ⇒ ⇒ 「重试类」在真仓上必须**没红** ⇒ ⇒ ⇒ 那才叫**有牙**

| 用例 | 断言 | 打了补丁的副本 | 未打补丁的真仓 |
| --- | --- | --- | --- |
| NC330 | 门侧 `wiring_count_hits` · 工具**只坏一次** ⇒ 必须被吸收 | ✅ 真红 | ❌ **没红**（[] ≠ 真实 2） |
| NC331 | 门侧 `wiring_count_hits` · 工具**永久坏** ⇒ 必须**算不出** ＋ 指名 | ✅ 真红 | ✅ 真红（fail closed 本就成立） |
| NC332 | 门侧 `any_hits` · 工具**只坏一次** ⇒ 必须被吸收 | ✅ 真红 | ❌ **没红**（[] ≠ 真实 715） |
| NC333 | 审计器 `count_hits` · 工具**只坏一次** ⇒ 必须被吸收 | ✅ 真红 | ❌ **没红**（None ≠ 真实 228） |

⇒ ⇒ ⇒ **「真仓当前确实没有重试」是实测结论**，不是推演。
⇒ ⇒ ⇒ **「永久坏 ⇒ 判红 ＋ 指名」在修之前就成立** ⇒ ⇒ ⇒ **重试没削弱 fail closed**。

### ⚠⚠⚨ 连带修好的**工具侧**洞（**不在仓内**，但它们让上面那 7 例「消失」）

① **负控 harness 的红行归因**：原来按 `'✗' in 行` 过滤 ⇒ ⇒ `✓` 行的**说明文字里**
   也含 `✗` ⇒ ⇒ 实测「35 条红行」里 **31 条是 `✓` 行** ⇒ ⇒ **真正的红门项全被噪声淹没**
   ⇒ ⇒ 改成**按行首**分三类（`  ✗ ` 红门项 / 行首 `✗ ` 工具坏了 / 行首 `✗ ` 汇总）
② **回归 driver 的「已完成」判据**：原来「块内有结论行就算跑完」⇒ ⇒ 「**基线红**」/
   「变异未落」/「没红」**全被算作跑完** ⇒ ⇒ **瞬时假红那一例在汇总里静默消失**
   ⇒ ⇒ 「329 例全有结论」这句话当时是**假的**⇒ ⇒ 改成**只认「真红」**⇒ ⇒ 其余**自动重跑**

### 连带数字（实测回填 · 门项条数记四处同改）

| 口径 | 前 | 后 |
| --- | --- | --- |
| 门项条数 | 1743 | **1754** |
| 门项执行次数 | 1746 | **1757** |
| 段级 trailer | 109/110/109/109 | **110/111/110/110** |

`|| true` **26** 不变；未验证 **21 组 / 85 处** 不变。

## ⚠⚠⚨ 批 EJ-31 · **`cat` 失败不许被 `rm -f` 掩盖成成功**

> 主题：「承诺不许**悄悄变红 / 悄悄变弱**」那一族 —— **工具坏了不许装作成功**。

### 起因（**实测复现**，不是推演）

门侧 `strip_comments()` 的**回退路径**长这样：

```sh
cat "$_strip_tmp" || _strip_rc=$?      # ⚠ 失败码存进了 _strip_rc
rm -f "$_strip_tmp"                    # ⚠ 但**没人检查 _strip_rc** ⇒ 函数返回 0
```

⇒ ⇒ `_strip_rc` **从头到尾没人检查** ⇒ ⇒ 函数**返回 0 且 stdout 为空**
⇒ ⇒ 「**工具坏了却装作成功**」⇒ ⇒ ⇒ **两个方向都坏**：

| 方向 | 机制 | 后果 |
| --- | --- | --- |
| ① **假红** | `ci-true-audit.py` 的抽取自检**对拍**（审计器侧 vs shell 侧）⇒ 看到「shell 侧 **0 字节** vs 审计器侧 **N 字节**」 | 报「✗ 抽取自检失败（剥注释口径漂移）」⇒ ⇒ **诊断指错方向**（真因是「工具坏了」，不是「口径漂移」） |
| ② **假绿** | 门侧 forbid 族把**空输出**当成「**没找到**」 | 违例被**漏检** ⇒ ⇒ 门**照样绿** |

#### 实测复现（两段，都跑过）

- **探针级**：`assets/icon/check-icon.sh` ⇒ 假 sed **只坏第一次**（⇒ 走回退路径）
  ＋ 假 cat **恒坏** ⇒ ⇒ 探针 **rc=0**、stdout **0 字节**（审计器侧 **2703 字符**）
- **端到端**：`python3 scripts/ci-true-audit.py` ⇒ **rc=1** ＋
  「✗ 抽取自检失败（剥注释口径漂移）：审计器 **8161** 字节 / shell **0** 字节」

⇒ ⇒ ⇒ 「**工具坏了 ⇒ 装作成功 ⇒ 假红 + 假绿**」**坐实**。

### ⚠⚠⚨ 订正：批 EJ-30 的**归因**被本批推翻（**结论必须与事实一致**）

批 EJ-30 用「**指纹法**」（门输出里含 `✗` 的行数 = 绿跑 **31** / 红跑 **35** ⇒ 多出 4 行
⇒ 「**精确指向审计器 rc=2**」⇒ ⇒ 「计数那两条腿的 grep 瞬时失败」）下了结论。

⇒ ⇒ ⚠⚠⚨ **本批的新诊断（按**行首**分类红行）推翻了这个归因**：
那一次「变异前就红了」的**真实**报错是「✗ 抽取自检失败（剥注释口径漂移）」，
而输出里**没有**「门自审计没过」那一行 ⇒ ⇒ ⇒ **审计器当时是好的**（rc≠2）
⇒ ⇒ ⇒ 「31+4 吻合」是**巧合**，不是**指纹**。

⇒ ⇒ ⇒ 批 EJ-30 的**重试修法本身有效**（「计数那两条腿的 grep 瞬时失败」**确实存在**），
但它**没有**修掉那一次假红 ⇒ ⇒ ⇒ **本次假红的真凶是本批这个洞**。

### 改了什么（**只动判据层** ⇒ ⇒ 零产品代码改动）

- ⚠⚠⚨ **门侧 `strip_comments()`**（sed 支 ＋ perl 支，**各一处**）：
  - `cat` 失败 ⇒ ⇒ **重试一次**（批 EJ-11/EJ-13 同款口径：瞬时抖动 ⇒ **透明恢复** ⇒ **不假红**）
  - ⇒ ⇒ 仍失败 ⇒ ⇒ **写标记 + 返回 1**（fail closed ⇒ **不许**再被 `rm -f` 掩盖）
  - ⇒ ⇒ ⚠ **重试前必须清零**（否则第一次的失败码会**盖住**第二次的结果 ⇒ ⇒ 又变假红）
- ⚠⚠⚨ **抽取自检的探针**（`ci-true-audit.py`）：
  - 它**没设** `$STRIP_FAIL_FILE` ⇒ ⇒ 失败分支的 `printf … >> "$STRIP_FAIL_FILE"`
    会去写一个**空路径** ⇒ ⇒ 报「cannot create : Directory nonexistent」
    ⇒ ⇒ **失败被记成「工具没法写标记」**⇒ ⇒ **诊断指错方向**
  - ⇒ ⇒ 现在：探针**也落标记** ＋ **保留退出码**（先存再原样退出）＋ **指名道姓**报出文件
  - ⇒ ⇒ ⚠⚠⚨ 探针的诊断**不许依赖 `cat`** —— 事故里坏掉的恰恰就是 `cat`
    ⇒ ⇒ 改用**纯 shell 内建**（`while read` ＋ `printf`）⇒ ⇒ 工具再坏也报得出
  - ⇒ ⇒ 探针改成**逐行列表**写法 ⇒ ⇒ 门可**逐条整行锚定**（不是一串塞满转义的长行）
- ⇒ ⇒ 落门 **8 条**（**零新门型**）：门侧 **5** 条 ＋ 探针侧 **3** 条
- ⇒ ⇒ 既有门项**只加不减**：批 EJ-11 那条跨行门的 RX 换成**新形态**（**变长** ⇒ 承诺只增不减）

### 实测（**负控 4 例** ＋ **门有牙自证**）

⇒ ⇒ 同一组用例跑**两棵树**：打了补丁的副本 ＋ **未打补丁的真仓**

| 用例 | 断言 | 打了补丁的副本 | 未打补丁的真仓 |
| --- | --- | --- | --- |
| NC334 | `cat` **恒坏** ⇒ 必须**返回失败** ＋ **写标记** ＋ 指名 | ✅ 真红 | ❌ **没红**（rc=0 ⇒ 工具坏了被装作成功） |
| NC335 | `cat` **只坏一次** ⇒ 必须被**重试吸收**（输出逐字节一致） | ✅ 真红 | ❌ **没红**（0 字节 ≠ 真实 N 字节） |
| NC336 | 删掉「重试前**失败位清零**」⇒ ⇒ **接线门必须红** | ✅ 真红 | ⚠ **变异未落**（那行**还不存在**） |
| NC337 | 端到端：工具坏了 ⇒ 审计器必须红 **且指名「工具失败」**（不许说「口径漂移」） | ✅ 真红 | ❌ **没红**（说的是「口径漂移」） |

⇒ ⇒ ⇒ **打了补丁 4/4 真红 · 未打补丁 0/4** ⇒ ⇒ ⇒ 「真仓当前确实有这个洞」是**实测结论**。

### 连带数字（实测回填 · 门项条数记四处同改）

| 口径 | 前 | 后 |
| --- | --- | --- |
| 门项条数 | 1754 | **1762** |
| 门项执行次数 | 1757 | **1765** |
| 段级 trailer | 110/111/110/110 | **111/112/111/111** |

`|| true` **26** 不变；未验证 **21 组 / 85 处** 不变。

## ⚠⚠⚨ 批 EJ-32 · **自检探针路径必须进程唯一**

> 主题：「承诺不许**悄悄变红**」那一族 —— **并发不许互相覆盖**。

### 起因（**实测复现**，不是推演）

批 EJ-31 的全量回归里出现「**变异前就红了**」（用例无效）的用例 **NC20**
⇒ ⇒ 归因：**抽取自检的探针路径是全局固定的**。

⇒ ⇒ 链条（每一环都在仓内可查）：

1. `ci-wiring.sh` 的第 N 步**每次**都跑 `ci-unverified-audit.py`
2. ⇒ ⇒ 它调 helper 的 `selftest_strip_parity`（`ci-unverified-audit.py:253`）
3. ⇒ ⇒ ⇒ helper 把 `strip_comments` **抽成探针脚本**写到
   **`/tmp/az-cj-selfcheck-probe.sh`**（**全局固定**）⇒ ⇒ ⇒ **每次跑都重写**
4. ⇒ ⇒ ⇒ 负控回归是 **2 worker 并发** ⇒ ⇒ ⇒ **两个进程互相覆盖那个文件**
5. ⇒ ⇒ ⇒ 某一边可能**执行对方**写下的探针 ⇒ ⇒ ⇒ 若两棵树的 `ci-wiring.sh` 不同
   （一边正被变异）⇒ ⇒ ⇒ 抽出来的 `strip_comments` **不是自己那棵树**的
6. ⇒ ⇒ ⇒ 两侧口径对不上 ⇒ ⇒ ⇒ 报「✗ 抽取自检失败（剥注释口径漂移）」
   ⇒ ⇒ ⇒ **假红**（批 DL：**假红比假绿更坏** ⇒ ⇒ 逼人把承诺改弱）

⇒ ⇒ ⇒ 这就是**历次全量回归反复出现「变异前就红了」**的**头号来源**。

### 改了什么（**只动判据层** ⇒ ⇒ 零产品代码改动）

- ⚠⚠⚨ **三个**自检临时文件的路径**一律带 PID** ⇒ ⇒ 进程之间**互不干扰**：
  - 剥注释对拍探针（`ci-true-audit.py`）
  - 抽取自检的样例文件（`ci-true-audit.py`）
  - 未验证盘点的样例文件（`ci-unverified-audit.py`）
  ⇒ ⇒ **一个入口**：`selfcheck_probe_path(tag)` ⇒ ⇒ **三个一起改**
  （只改一个 ⇒ ⇒ 下一轮又从别的口子冒出来）
- ⚠⚠⚨ 剥注释对拍探针**用完即删**（路径带 PID ⇒ 每进程一个 ⇒ 不删就往 `/tmp` 堆）
- ⇒ ⇒ 落门 **7 条**（**零新门型**）：`arch_need_count` **5** 条 ＋ `arch_forbid` **2** 条
  ⇒ ⇒ forbid 那两条钉的是「**不许**再硬编码 `/tmp/az-` 路径」⇒ ⇒ 一条挡住整类

### 实测（**负控 2 例** ＋ **门有牙自证**）

⇒ ⇒ 同一组用例跑**两棵树**：打了补丁的副本 ＋ **未打补丁的真仓**

| 用例 | 断言 | 打了补丁的副本 | 未打补丁的真仓 |
| --- | --- | --- | --- |
| NC338 | 两个进程拿到的**探针路径必须不同** | ✅ 真红 | ❌ **没红**（两个进程拿到**同一个**路径） |
| NC339 | 把路径改回**固定常量** ⇒ ⇒ **接线门必须红** | ✅ 真红 | ⚠ **变异未落**（那行**还不存在**） |

⇒ ⇒ ⇒ **打了补丁 2/2 真红 · 未打补丁 0/2** ⇒ ⇒ ⇒ 「真仓确实有这个洞」是**实测结论**。

### 连带数字（实测回填 · 门项条数记四处同改）

| 口径 | 前 | 后 |
| --- | --- | --- |
| 门项条数 | 1762 | **1769** |
| 门项执行次数 | 1765 | **1772** |
| 段级 trailer | 111/112/111/111 | **112/113/112/112** |

`|| true` **26** 不变；未验证 **21 组 / 85 处** 不变。

## ⚠⚠⚨ 批 EJ-33 · **落门必须整类覆盖**（逐个点名 ⇒ ⇒ 漏同类 ⇒ ⇒ 三处漏网一次坐实）

> 主题：「承诺不许**悄悄变弱**」那一族 —— **落门不许逐个点名**。

### 起因（**实测复现**，不是推演）

⚠⚠⚨ 同一个根因**一连犯三次** ⇒ ⇒ 三次都是「**逐个点名**」⇒ ⇒ **漏了同类**：

| # | 逐个点名的那一处 | 漏掉的同类 | 后果 |
| --- | --- | --- | --- |
| ① | 批 EJ-31 只钉了剥注释**重试支**（20 空格）的 `return 1` | **「第一次就失败」那一支（16 空格）** | 掏空它 ⇒ ⇒ **接线门 rc=0、全绿** ⇒ ⇒ ⇒ ⇒ **承诺悄悄变弱**（本轮全量回归 **NC252** 实测坐实） |
| ② | 批 EJ-32 只钉了 `ci-true-audit.py` ＋ `ci-unverified-audit.py` | **第三个自检脚本 `ci-tautology-check.py`** | 三处自检样例路径**仍是全局固定** ⇒ ⇒ 并发时后写的**覆盖**先写的 ⇒ ⇒ 先写的 `os.unlink` 把后写者**要读的文件删掉** ⇒ ⇒ 崩了 ⇒ ⇒ **假红** |
| ③ | 两个端到端探针把应用日志写到**全局固定路径**、又**读回自己的日志** | — | 并发跑 ⇒ ⇒ 互相覆盖 ⇒ ⇒ 结论可能**读成对方的** ⇒ ⇒ **假红/假绿** |

⇒ ⇒ ⇒ **教训**：forbid ＋ 钉形态类门项**必须按类覆盖**，不许逐个文件、逐个支点名。

### 改了什么（**只动判据层** ⇒ ⇒ 零产品代码改动）

- ⚠⚠⚨ **洞 A**：`ci-tautology-check.py` 的三处自检样例路径 ⇒ ⇒ **一律带 PID**
  ⇒ ⇒ 新增辅助函数 `selfcheck_probe_path(tag, ext)`（`tempfile.gettempdir()` ＋ `os.getpid()`）
- ⚠⚠⚨ **洞 B**：`probe-deepin-tray.sh` ＋ `probe-sni-icon.sh` 的应用日志路径 ⇒ ⇒ **一律带 PID**（`$$`）
- ⚠⚠⚨ **洞 C**（**纯落门**，零代码改动）：剥注释的
  「**第一次就失败 ⇒ 写失败标记 + 返回 1**」⇒ ⇒ **一条压行门盖两个支**
  ⇒ ⇒ RX 末尾的 `fi cat` 把**重试支**排除 ⇒ ⇒ 只认「第一次就失败」那一支
  ⇒ ⇒ ⇒ sed 支 ＋ perl 支**恰好 2 处**
- ⇒ ⇒ 落门 **11 条**（**零新门型**）：
  - `arch_need_any_count` **2** 条 —— **整类** forbid
    （`scripts/*.py` ＋ `scripts/probe-*.sh` 范围里**不许**有固定临时路径）
  - `arch_need_count` **8** 条 —— 钉住修法（辅助函数定义 ＋ 本体 ＋ import
    ＋ 三个调用点 ＋ 两个探针的日志行）
  - `arch_need_count_ml` **1** 条 —— 洞 C 的**跨行**门

### 实测（**负控 6 例** ＋ **门有牙自证**）

⇒ ⇒ 同一组用例跑**两棵树**：打了补丁的仓 ＋ **未打补丁的 HEAD 副本**

| 用例 | 断言 | 打了补丁的仓 | 未打补丁的 HEAD 副本 |
| --- | --- | --- | --- |
| NC252 | 掏空 **sed 支**「第一次就失败」的 `return 1` ⇒ ⇒ 接线门必须红 | ✅ 真红 | ❌ **没红**（变异落了，门**还不存在** ⇒ ⇒ 全绿） |
| NC342 | 掏空 **perl 支**那一处 ⇒ ⇒ 同款（⇒ ⇒ **一条门盖两个支**） | ✅ 真红 | ❌ **没红**（同上） |
| NC340 | 把恒真探针的样例路径改回**固定常量** ⇒ ⇒ **整类**门必须红 | ✅ 真红 | ⚠ **变异未落**（那行还不存在） |
| NC341 | 把托盘探针的日志路径改回**固定常量** ⇒ ⇒ **整类**门必须红 | ✅ 真红 | ⚠ **变异未落**（那行还不存在） |
| NC279 | 中和共享辅助函数的「工具坏了」分支 ⇒ ⇒ 那条腿**不许**再报红 | ✅ 真红 | ✅ 真红（⚠ 这一例**与 EJ-33 无关** ⇒ ⇒ 它坐实的是**工具侧**的陈旧锚） |
| NC343 | **不变异** ⇒ ⇒ 接线门必须**绿** | ✅ 真红 | ❌ **文案缺失**（EJ-33 段还不存在） |

⇒ ⇒ ⇒ **打了补丁 6/6 真红 · 未打补丁 1/6**（那 1 例 NC279 是**工具侧**的
⇒ ⇒ 与 EJ-33 无关 ⇒ ⇒ **EJ-33 相关的 5 例 0/5**）⇒ ⇒ ⇒ 「真仓确实有这个洞」是**实测结论**。

### 连带数字（实测回填 · 门项条数记四处同改）

| 口径 | 前 | 后 |
| --- | --- | --- |
| 门项条数 | 1769 | **1780** |
| 门项执行次数 | 1772 | **1783** |
| 段级 trailer | 112/113/112/112 | **113/114/113/113** |

`|| true` **26** 不变；未验证 **21 组 / 85 处** 不变。

## ⚠⚠⚨ 批 EJ-34 · **临时路径必须进程唯一**（写固定路径 ＋ 读回自己的输出 ⇒ ⇒ 结论被污染）

> 主题：「承诺不许**悄悄变弱**」那一族 —— **临时文件路径不许是全局固定的**。

### 起因（**实测复现**，不是推演）

⚠⚠⚨ 全仓普查（`deepin/scripts` ＋ `linux/scripts` ＋ `macos/scripts` ＋ `assets/icon`）
⇒ ⇒ 按整类门 RX 实测命中 ⇒ ⇒ ⇒ ⇒ **五族**：

| # | 文件 | 命中 | 判定 |
| --- | --- | --- | --- |
| ① | `linux/scripts/ai-e2e.sh` | 6 | **真洞**（六个日志/错误文件写到**全局固定路径**、之后又**读回自己的输出**） |
| ② | `linux/scripts/ci-local.sh` | 2 | **真洞**（`tee` 写 ＋ `sed` 读回 ⇒ ⇒ ⇒ ⇒ **PASSED/SKIPPED/FAILED 三个计数**来自那个文件） |
| ③ | `macos/scripts/engine-fetch-check.sh` | 2 | **真洞**（`2>` 写 ＋ `cat` 读回 ⇒ ⇒ ⇒ ⇒ 报错内容来自那个文件） |
| ④ | `deepin/scripts/contract-check.sh` | 1 | **真洞**（`mktemp -d` 的**模板多余** ⇒ ⇒ ⇒ ⇒ 硬编码固定前缀 ⇒ ⇒ ⇒ ⇒ 并发跑撞同一个目录） |
| ⑤ | `macos/scripts/render-harness/run.sh` | 3 | **不是同一族**（沙箱/输出目录是**有意固定**的 ⇒ ⇒ ⇒ ⇒ 脚本按 `.git` 存在与否复用）⇒ ⇒ ⇒ ⇒ 如实记、**不算洞** |
| ⑥ | `deepin/scripts/ci-wiring.sh` | 2 | **自指陷阱**（批 EJ-32 那两条 forbid 门的**说明文字**里原样写着那个固定前缀 ⇒ ⇒ ⇒ ⇒ 整类门会**自己告自己**） |

⇒ ⇒ ⇒ ⇒ **探针级实测复现**：**串行 2/2** 读回自己的；**8 路并发 7/8 读成对方的**
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 坐实「结论被污染」。

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **教训**：临时文件路径**必须进程唯一**（带 PID）⇒ ⇒ ⇒ ⇒ 否则
「**写进去 ＋ 读回来**」这一族在并发下**读成对方的**。

### 改了什么（**只动判据/工具脚本** ⇒ ⇒ ⇒ ⇒ 零产品代码改动）

- ⚠⚠⚨ `linux/scripts/ai-e2e.sh`：新增 `MOCK_TMP="/tmp/deepdolphin-mock.$$"`
  ⇒ ⇒ ⇒ ⇒ 六个日志/错误文件路径**一律从它派生**（单一真相源）
- ⚠⚠⚨ `linux/scripts/ci-local.sh`：新增 `CJTEST_LOG="/tmp/dd-cjtest.$$.log"`
  ⇒ ⇒ ⇒ ⇒ `tee` ＋ `sed` 两处改用它 ⇒ ⇒ ⇒ ⇒ 末尾 `rm -f`
- ⚠⚠⚨ `macos/scripts/engine-fetch-check.sh`：新增 `FETCH_ERR="/tmp/engine-fetch-err.$$.txt"`
  ⇒ ⇒ ⇒ ⇒ `2>` ＋ `cat` 两处改用它 ⇒ ⇒ ⇒ ⇒ 末尾 `rm -f`
- ⚠⚠⚨ `deepin/scripts/contract-check.sh`：`mktemp -d` 的**模板去掉**
  （`mktemp` 本来就用 `TMPDIR` ⇒ ⇒ ⇒ ⇒ 模板**多余**）
- ⚠⚠⚨ `deepin/scripts/ci-wiring.sh`：批 EJ-32 那两条 forbid 门的**说明文字**
  ⇒ ⇒ ⇒ ⇒ 改写成**不含字面量**的措辞（否则整类门会**自己告自己**）
- ⇒ ⇒ ⇒ ⇒ 落门 **8 条**（**零新门型**）：
  - `arch_need_any_count` **3** 条 —— **整类** forbid
    （`deepin/scripts` ＋ `linux/scripts` ＋ `macos/scripts` ⇒ ⇒ ⇒ ⇒ 每个目录
    **一个通配** ⇒ ⇒ ⇒ ⇒ 目录内**新增**脚本**自动**在射程内
    ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **不采用**按文件点名的登记册（成本过高 ⇒ ⇒ ⇒ ⇒ 迟早失准））
  - `arch_need_count` **5** 条 —— 钉住修法（三个 PID 前缀 ＋ 六个派生路径
    ＋ 契约门那一条 `mktemp`）

### 实测（**负控 7 例** ＋ **两棵树对照**）

**① 负控 7 例**（打了补丁的仓 ⇒ ⇒ ⇒ ⇒ 每例都**真红** ＋ 文案命中 ＋ 洁净）：

| 用例 | 断言 | 结果 |
| --- | --- | --- |
| NC344 | 把端到端 mock 脚本的临时路径**改回固定常量** ⇒ ⇒ ⇒ ⇒ **逐条**门 ＋ **整类**门**都要红** | ✅ 真红 |
| NC345 | 把仓颉测试日志的临时路径**改回固定常量** ⇒ ⇒ ⇒ ⇒ 同款 | ✅ 真红 |
| NC346 | 把引擎下载错误输出的临时路径**改回固定常量** ⇒ ⇒ ⇒ ⇒ 同款 | ✅ 真红 |
| NC347 | 把契约门的 `mktemp` **模板加回去** ⇒ ⇒ ⇒ ⇒ 同款 | ✅ 真红 |
| NC348 | 在 linux 脚本目录里**新建**一个脚本（固定临时路径）⇒ ⇒ ⇒ ⇒ **整类**门必须红 | ✅ 真红 |
| NC349 | 在 macos 脚本目录里**新建**一个脚本（固定临时路径）⇒ ⇒ ⇒ ⇒ **整类**门必须红 | ✅ 真红 |
| NC350 | **不变异** ⇒ ⇒ ⇒ ⇒ 接线门必须**绿**（正向对照） | ✅ 绿 |

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **7/7 全过** ⇒ ⇒ ⇒ ⇒ 零「基线红」/「变异未落」/「没跑完」。
⚠ NC348/NC349 是**新建脚本**的用例 ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 直接证「**整类 ≠ 点名**」
（**点名**的门**永远**挡不住新文件）。

**② 两棵树对照**（同一棵「未打补丁的 HEAD 副本」）：

| 口径 | 打了补丁的仓 | 未打补丁的 HEAD 副本 |
| --- | --- | --- |
| 真实存在的固定临时路径 | **0** 处 | **13** 处（deepin 3 ＋ linux 8 ＋ macos 2） |
| 接线门 | rc=0、**0 红行**、门项 **1791** 项 | rc=0、**0 红行**、门项 **1772** 项 |
| 那 13 处被谁看见 | **8 条新门**全看见 | **一条都看不见** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **洞真实存在**（实测结论） |

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 「真仓确实有这个洞」是**实测结论**（不是推演）。

### 连带数字（实测回填 ⇒ ⇒ 门项条数记四处同改）

| 口径 | 前 | 后 |
| --- | --- | --- |
| 门项条数 | 1780 | **1788** |
| 门项执行次数 | 1783 | **1791** |
| 段级 trailer | 113/114/113/113 | **114/115/114/114** |

`|| true` **26** 不变；未验证 **21 组 / 85 处** 不变。

⚠⚠⚨ **订正（当场）**：批 EJ-33 把「段级 trailer」那两条门的说明文字里的
「= 1 处声明 + N 处段末清零」的 **N** 漏改了（**N** 还停在 112 ⇒ ⇒ ⇒ ⇒ 实际已是 113）
⇒ ⇒ ⇒ ⇒ 本批一并订正为 **114**（= 115 - 1）⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 「说明文字不许在骗人」
这条纪律 ⇒ ⇒ ⇒ ⇒ **自己也得守**。

### 连带实测：`<IDX:>` 行号锚**漂移**（本批插了 34 行 ⇒ ⇒ 185 个用例的锚全偏）

⚠⚠⚨ 本批往 `ci-wiring.sh` 插了 **34 行** ⇒ ⇒ ⇒ ⇒ harness 里 **185** 个用例
的 `<IDX:>` 行号锚**全部偏移** ⇒ ⇒ ⇒ ⇒ 唯一救星是「**行号降级为提示、
内容才是真相**」的自愈机制 ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **必须实测它扛不扛得住**：

| 口径 | 实测结果 |
| --- | --- |
| 锚点总数 | **175** |
| 行号仍准 | 104 |
| **自愈后仍唯一** | 70 |
| 单行多候选（取最近） | 1 ⚠（**孤儿锚点** ⇒ 无任何用例引用 ⇒ 不影响） |
| **定位不到** | **0** ✅ |
| 行为级回归（抽 14 个用 `<IDX:>` 的用例实跑） | **14/14 全绿**（真红 ＋ 文案命中 ＋ 洁净） |

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **本批的 +34 行漂移没有打坏任何一条既有用例** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒
「插一行 ⇒ ⇒ 全部行号锚失准」这个老坑，本批**实测**扛住了。

## ⚠⚠⚨ 批 EJ-35 · **固定资源必须进程唯一**（端口是同族的另一种资源 ＋ 范围不许手写）

> 主题：「承诺不许**悄悄变弱**」那一族 —— **固定资源不许写死**。

### 起因（**实测复现**，不是推演）

⚠⚠⚨ 批 EJ-34 把「临时**文件路径**」这一种资源整类管住了 ⇒ ⇒ ⇒ ⇒ 但同一族的
**另一种资源**（**监听端口**）**零门** ⇒ ⇒ ⇒ ⇒ 又一次「逐个点名 ⇒ ⇒ ⇒ ⇒ 漏同类」，
只是这次漏在**资源类型**这一层。

| # | 位置 | 形态 | 后果 |
| --- | --- | --- | --- |
| ① | `linux/scripts/ai-e2e.sh` | 三个**全局固定**端口（18741/18742/18743） | 并发跑 ⇒ ⇒ ⇒ ⇒ 后一个 bind 失败（`OSError: [Errno 98] Address already in use`）⇒ ⇒ ⇒ ⇒ 脚本自己报「端口可能被占用」⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 这次失败**与被测代码无关** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **假红** |
| ② | `linux/tests/mock_agent.py` | 端口**默认值** 18742 | 与 ① 的第二个端口**就是同一个** ⇒ ⇒ ⇒ ⇒ 两边撞车 ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **假红** |
| ③ | `linux/tests/mock_agent.py` | 默认日志路径**全局固定** | 并发跑 ⇒ ⇒ ⇒ ⇒ 互相覆盖 ⇒ ⇒ ⇒ ⇒ 结论可能**读成对方的** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **假红/假绿** |

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **探针级实测复现**：同一端口起第二个假 provider ⇒ ⇒ ⇒ ⇒ 第二个**当场死**，
报 `OSError: [Errno 98] Address already in use` ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 坐实。

⚠⚠⚨ ⚠ **范围本身也是手写的**：批 EJ-34 的整类门范围是**三个目录**
⇒ ⇒ ⇒ ⇒ `linux/tests/`（②③ 全在这儿）**完全在射程外** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 「漏同类」
复发在**目录**这一层 ⇒ ⇒ ⇒ ⇒ **实测**：全仓 **5 处**固定资源里 **2 处**落在射程外。

### 改了什么（**只动判据/工具脚本** ⇒ ⇒ ⇒ ⇒ 零产品代码改动）

- ⚠⚠⚨ `linux/scripts/ai-e2e.sh`：
  - 三个端口**一律让内核分配**（`MOCK_PORT=0`）⇒ ⇒ ⇒ ⇒ **天然进程唯一**
  - 实际端口**从假 provider 的输出里读回**（它 bind 完才知道自己拿到哪个）
  - 固定 `sleep 2` ⇒ ⇒ ⇒ ⇒ **轮询到端口行为止**（不再赌机器快慢）
  - 「端口可能被占用」的诊断文字**改成不可能的措辞**（现在端口是内核分配的）
  - 顺带修掉一处**诊断指错方向**：原来只认 plain 与 agent ⇒ ⇒ ⇒ ⇒ **multi 的错报成 plain 的**
- ⚠⚠⚨ `linux/tests/mock_agent.py`：
  - 端口**必填**（缺 ⇒ ⇒ ⇒ ⇒ 明确报错退出 ⇒ ⇒ ⇒ ⇒ fail closed）⇒ ⇒ ⇒ ⇒ 值 0 = 让内核分配
  - 默认日志路径**带 PID**
  - **报出实际端口**（`LISTENING=`，`flush=True`）
- ⇒ ⇒ ⇒ ⇒ 落门 **13 条**（**零新门型**）：
  - `arch_need_any_count` **5** 条 —— **整类** forbid，范围**自动推导**
    （`../*/*/*.sh` **40** 个 ＋ `../*/*/*.py` **8** 个 ⇒ ⇒ ⇒ ⇒ **48** 个第一方脚本
    全部在射程内；⚠ 如实记：平台根目录下散落的脚本（`macos/build.sh`）与
    **有意固定**沙箱的 `macos/scripts/render-harness/run.sh` **不在**这个两层范围内
    ⇒ ⇒ ⇒ ⇒ 前者实测 0 命中、后者是**有意固定**（批 EJ-34 已记））
  - `arch_need_count` **8** 条 —— 逐个钉形态

### 实测（**修法实测** ＋ **负控 7 例**）

**① 修法实测**（两组并发，共六个假 provider）：

| 口径 | 修法前 | 修法后 |
| --- | --- | --- |
| 两个组共 6 个假 provider | 第 2 组**当场死**（Address already in use） | **6/6 全部存活** |
| 端口重叠 | **必然**重叠 | **零**重叠 |
| 全部在监听 | — | **6/6 是** |

**② 负控 7 例**（NC351–NC357）：

| 用例 | 断言 | 结果 |
| --- | --- | --- |
| NC351 | 把三个端口**改回写死的字面量** ⇒ ⇒ ⇒ ⇒ **整类**门 ＋ **逐条**门**都要红** | ✅ 真红 |
| NC352 | 端口改回**赋值形**（`PLAIN_PORT=18741`）⇒ ⇒ ⇒ ⇒ **整类**门必须红 | ✅ 真红 |
| NC353 | 把端口**默认值加回去** ⇒ ⇒ ⇒ ⇒ **整类**门 ＋ **逐条**门**都要红** | ✅ 真红 |
| NC354 | 默认日志路径**改回全局固定** ⇒ ⇒ ⇒ ⇒ **整类**门 ＋ **逐条**门**都要红** | ✅ 真红 |
| NC355 | 在 `linux/tests/` **新建**一个脚本（固定临时路径）⇒ ⇒ ⇒ ⇒ **整类**门必须红 | ✅ 真红 |
| NC356 | 在 `assets/icon/` **新建**一个脚本（固定临时路径）⇒ ⇒ ⇒ ⇒ **整类**门必须红 | ✅ 真红 |
| NC357 | **不变异** ⇒ ⇒ ⇒ ⇒ 接线门必须**绿**（正向对照） | ✅ 绿 |

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **7/7 全过**（真红 ＋ 文案命中 ＋ 洁净）⇒ ⇒ ⇒ ⇒ 零「基线红」/「变异未落」/「没跑完」。
⚠ NC355/NC356 是**新建文件**的用例 ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 直接证「**范围自动推导**」
（⇒ ⇒ 目录清单**不再手写** ⇒ ⇒ 新增文件**自动**在射程内）。

### 连带数字（实测回填 ⇒ ⇒ 门项条数记四处同改）

| 口径 | 前 | 后 |
| --- | --- | --- |
| 门项条数 | 1788 | **1801** |
| 门项执行次数 | 1791 | **1804** |
| 段级 trailer | 114/115/114/114 | **115/116/115/115** |

`|| true` **26** 不变；未验证 **21 组 / 85 处** 不变。

### 连带实测：`<IDX:>` 行号锚**漂移**（本批往 `ci-wiring.sh` **净增 37 行** ⇒ ⇒ ⇒ ⇒ 184 个用例的锚受影响）

⚠⚠⚨ 本批往 `ci-wiring.sh` **净增 37 行**（+42 - 5）⇒ ⇒ ⇒ ⇒ harness 里用 `<IDX:>`
行号锚的 **184** 个用例（**190** 个锚点）的锚**全部可能偏移** ⇒ ⇒ ⇒ ⇒ 唯一救星是
「**行号降级为提示、内容才是真相**」的自愈机制 ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **必须实测它扛不扛得住**：

| 口径 | 实测结果 |
| --- | --- |
| 锚点总数 | **190**（覆盖 **184** 个用例） |
| 行号仍准 | **117** |
| 受漂移影响 | **73** |
| **自愈后仍唯一** | **73** |
| 单行多候选 | **0** ✅ |
| **定位不到** | **0** ✅ |
| 行为级回归（抽 **14** 例**全取自自愈集**的用例实跑） | **14/14 全绿**（真红 ＋ 文案命中 ＋ 洁净） |

⚠ 漂移**只集中在 3 个文件**（`ci-wiring.sh` **35** 处、`contract-check.sh` **22** 处、
`ci-wiring-audit.py` **16** 处）⇒ ⇒ ⇒ ⇒ 另 **4** 个文件（`ci.sh` **35** 处、
`ci-platform-probe.sh` **42** 处、`check-deb-layout.sh` **16** 处、
`probe-agent-tool-surface.sh` **14** 处）的锚**行号仍准** ⇒ ⇒ ⇒ ⇒ 零漂移。

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **本批的 +37 行漂移没有打坏任何一条既有用例** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒
「插一行 ⇒ ⇒ 全部行号锚失准」这个老坑，本批**实测**扛住了。

## ⚠⚠⚨ 批 EJ-36 · **条数校准的覆盖面不许手写**（说明文字在骗人 ⇒ 以前没人管）

> 主题：「承诺不许**悄悄变弱**」那一族 —— 判据层**对自己的覆盖面**没有承诺。

### 起因（**实测坐实**，不是推演）

⚠⚠⚨ 本批先做了一次**四路普查**，把「判据层的覆盖面」量准：

| 口径 | 实测结果 | 判定 |
| --- | --- | --- |
| 作用域型门（`arch_need_any_count` / `_any_min` / `arch_forbid_tree` / `arch_forbid_text_dup`）覆盖的文件 | `.sh` **40** 个已覆盖 / 未覆盖 **2** 个（`macos/build.sh` 实测 0 命中、`macos/scripts/render-harness/run.sh` **有意固定**） | ✅ **已收口**（批 EJ-35 之后） |
| `arch_need` / `arch_need_ml` 族（**453** 条）的 RX 在目标文件里命中 **>1** 处 | **0** 条 | ✅ **已收口**（每条门都唯一 ⇒ 删一处必红） |
| 下限型门（`arch_need_min` / `arch_need_any_min`，**59** 条）的下限值 == 0 | **0** 条 | ✅ **已收口**（下限为 0 ⇒ 恒绿 ⇒ 零牙） |
| 「说明文字里的条数 == 期望值」（rc=9）的**覆盖面** | 只喂 **2 个手写门型** ⇒ 另外 **6 个**带 `want` 字段的门型（**174 条门项**）**根本没人校准** | ❌ **本批的洞** |

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **前三族已经收口** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 说明判据层的覆盖面**大体**是齐的
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **但有一族是「按手写清单」做的** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 而**清单**天生
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 「新增一个 ⇒ 自动漏」⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **承诺悄悄消失的元层**。

### 洞 A（结构）：覆盖面是**手写清单** ⇒ ⇒ 新增门型**自动漏**

⚠⚠⚨ rc=9 那道门喂的是 `check_label_count_text(cnt + cntml)` ⇒ ⇒ **两个手写列表** ⇒ ⇒：

| 门型 | 带 `want` 字段 | 门项数 | 以前受管？ |
| --- | --- | --- | --- |
| `arch_need_count` | 有 | 995 | ✅ |
| `arch_need_count_ml` | 有 | 76 | ✅ |
| `arch_need_count_in_fn` | 有 | **45** | ❌ |
| `arch_need_any_min` | 有 | **51** | ❌ |
| `arch_need_any_count` | 有 | **41** | ❌ |
| `arch_need_count_in_step` | 有 | **22** | ❌ |
| `arch_need_count_pair` | 有 | **7** | ❌ |
| `arch_need_min` | 有 | **8** | ❌ |

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 合计 **174 条门项**的说明文字**没人管** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 且覆盖面**手写** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **新增一个带 `want` 的门型 ⇒ ⇒
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **自动漏** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 没有任何机制会发现。

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **修法**：覆盖面**从门型定义自动推导** —— 每个门型的 `local` 行
都写着 `want="$N"` 与 `label="$M"` ⇒ ⇒ ⇒ **位置从源码推导** ⇒ ⇒ ⇒ ⇒
⇒ ⇒ ⇒ ⇒ **零名单维护** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 新增门型照约定写 ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **自动纳入** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 「承诺悄悄消失」被堵死。

### 洞 B（写法）：已认的写法只有**两种** ⇒ ⇒ 实测存在的写法**全认不出**

| 写法 | 以前 | 现在 |
| --- | --- | --- |
| 「（恰好 N 处」「必须恰好 N 处」 | ✅ 认 | ✅ 认 |
| 「函数体内恰好 N 处」 | ❌ **认不出** | ✅ 认 |
| 「（N 处 check 调用）」「（N 条报错）」 | ❌ **认不出** | ✅ 认 |
| 「**恰好 N 条**」「至少 N 次」 | ❌ **认不出** | ✅ 认 |
| 「面板的 N 处激活动作」 | ❌ **认不出** | ✅ 认 |

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 口径：`恰好 N <单位>` / `至少 N <单位>`，**前缀任意**，单位收
**处 / 次 / 条 / 个 / 篇** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 实测全仓**零误报**。
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 汉字数字**明确不收**（实测：放宽到不限空格 ⇒ ⇒ **266 条误报**；
带空格又**零增量** ⇒ ⇒ ⇒ 收了只增加脆弱性 ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 如实记。

### 洞 C（**实测逮到两条真在骗人的**）

⚠⚠⚨ 把新口径一开 ⇒ ⇒ **当场逮到 2 条**说明文字**确实在骗人**：

| 门项 | 期望值 | 说明文字称 | 源码里**实际** |
| --- | --- | --- | --- |
| `arch_forbid_han` 的失败上报（`arch_need_count_in_fn`） | **3** | 「函数体内恰好 **2** 处」 | **3** 处 `ARCH_FAIL=1` |
| `arch_forbid_text_dup` 的失败上报（`arch_need_count_in_fn`） | **7** | 「恰好 **6** 处」 | **7** 处 `ARCH_FAIL=1` |

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 写的时候是 2/6 ⇒ ⇒ 批 CN 给这两个门型各加了一支（把「没有 perl」
那条从 SKIP 改成判红）⇒ ⇒ ⇒ **条数变了、说明文字没同步** ⇒ ⇒ ⇒ ⇒ ⇒ ⇒
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 而当时的校准口径**看不见**（「函数体内恰好」不在认的两种里
⇒ ⇒ ⇒ + `arch_need_count_in_fn` **压根没进覆盖面**）⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **双盲**。

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **本批一并订正**：2 → 3、6 → 7 ⇒ ⇒ ⇒ ⇒ ⇒ ⇒
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 另有 **6 条**标签是**跨门引用 / 子计数**（「有门钉住恰好 23 处」
「每段恰好 1 处」）⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 那不是说自己 ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 但**同一个写法**
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 混在一句里 ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 谁也分不清 ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **改措辞**（「恰好」去掉）⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 免得两种含义混着。

### 改了什么（**只动判据层** ⇒ ⇒ ⇒ ⇒ 零产品代码改动）

- `deepin/scripts/ci-wiring-audit.py`：
  - 新增 `gate_want_label_positions()` ⇒ ⇒ **从门型定义推导** want/label 位置
  - 新增 `collect_label_count_items()` ⇒ ⇒ **覆盖面自动推导**（取代手写清单）
  - 新增 `_label_declared_counts()` ⇒ ⇒ **写法口径只有一份**
  - 改 `check_label_count_text()` ⇒ ⇒ 吃自动推导的覆盖面 + 新写法
  - 新增 `check_label_count_selftest()` ⇒ ⇒ **自检**三条腿：写法认得出
    + 位置推导得对 + 覆盖面不是手写的
  - 两个调用点改成 `check_label_count_text(collect_label_count_items())`
  - 新增失败守卫 `label_self_bad`（登记进 `FAIL_GUARDS`）
- `deepin/scripts/ci-wiring.sh`：
  - **订正 2 条**骗人的说明文字（2 → 3、6 → 7）
  - **改写 6 条**跨门引用的措辞
  - **落门 5 条**（**零新门型**）：3 条钉定义 ＋ 1 条钉调用点（**恰好 2 处**）
    ＋ 1 条钉自检被调用
  - 旧的「写法口径」那条门改成钉住**新的**口径（`LABEL_COUNT_RX`）
- `deepin/scripts/ci-wiring-audit.py` ＋ `ci-wiring-gates.baseline`：门项条数常量与
  基线同步为 **1806**

### 实测（**负控 8 例** NC358–NC365）

| 用例 | 断言 | 结果 |
| --- | --- | --- |
| NC358 | 把 `arch_forbid_han` 那条的说明文字**改回骗人的 2 处** ⇒ ⇒ 审计器必须红且指名道姓 | ✅ 真红 |
| NC359 | 把 `arch_need_count_in_step` 那条的「恰好 2 处」改成 3 ⇒ ⇒ 审计器必须红 | ✅ 真红 |
| NC360 | 把 `arch_need_min` 那条的「至少 2 次」改成 3 ⇒ ⇒ 审计器必须红 | ✅ 真红 |
| NC361 | 把**两个**调用点的覆盖面**回退成手写清单** ⇒ ⇒ 接线门必须红 | ✅ 真红 |
| NC362 | 把写法口径的正则改一个字 ⇒ ⇒ 接线门必须红 | ✅ 真红 |
| NC363 | 把自检的调用换成空列表 ⇒ ⇒ 接线门必须红 | ✅ 真红 |
| NC364 | 把推导位置**挪一位** ⇒ ⇒ 审计器必须红且指名道姓「位置推导」 | ✅ 真红 |
| NC365 | **不变异** ⇒ ⇒ 接线门必须**绿**（正向对照） | ✅ 绿 |

⇒ ⇒ ⇒ ⇒ ⇒ ⇒ **8/8 全过**（真红 ＋ 文案命中 ＋ 洁净）⇒ ⇒ ⇒ ⇒ ⇒ ⇒
⇒ ⇒ ⇒ ⇒ ⇒ ⇒ 零「基线红」/「变异未落」/「没跑完」。
⚠ NC364 是**元层**那一例：推导位置被挪 ⇒ ⇒ 审计器**当场指名道姓**「位置推导」
⇒ ⇒ ⇒ 直接证「推导坏了 ⇒ 覆盖面悄悄缩水」这条洞被堵住。

### 连带数字（实测回填 ⇒ ⇒ 门项条数记四处同改）

| 口径 | 前 | 后 |
| --- | --- | --- |
| 门项条数 | 1801 | **1806** |
| 门项执行次数 | 1804 | **1809** |
| 段级 trailer | 115/116/115/115 | **116/117/116/116** |

`|| true` **26** 不变；未验证 **21 组 / 85 处** 不变。
