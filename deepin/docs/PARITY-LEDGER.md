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
⇒ 累计负控 **27/27 真红**。

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

## F. linux 端

**本轮明确暂缓**（用户 2026-10-19 定：「linux 通用再说」）。
linux 侧已知独立缺口记在 `linux/README.md` 的「与 macOS 端的已知差异」与 `linux/VERIFY-ON-LINUX.md`。
注意：章程 §3.5 把 linux 的实现指定为**仓颉 Canvas 移植** —— 与 deepin 的 Qt QPainter 同款内核需求，
将来做 linux 时**可复用本批的契约层与判据思路**（端口式 CanvasSink 是为这一步留的）。
