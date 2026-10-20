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
| M1a / M0-8 / M3b / M4a / M4b | 容器批 / 干净容器 / KPI 骨架屏 / 拆分 / deb 矩阵 | ◐ 部分落地（⚠ **批 AE 实测核对**：**M3b 组件化主体已全部完成**（`src/ui/common/` 17 个组件、散落的次级标签样式 **0 处**、`SegmentedButton` **只一份**）⇒ 只剩 KPI 骨架屏 + 真机目检；**M4b 的「deb 构建未做」已过时** ⇒ 现在 ci.sh **12 门**（第 11 门 deb 构建、第 12 门 deb 布局验收），只剩「系统 Qt6/DTK6 矩阵」那一步） |

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

---

## F. linux 端

**本轮明确暂缓**（用户 2026-10-19 定：「linux 通用再说」）。
linux 侧已知独立缺口记在 `linux/README.md` 的「与 macOS 端的已知差异」与 `linux/VERIFY-ON-LINUX.md`。
注意：章程 §3.5 把 linux 的实现指定为**仓颉 Canvas 移植** —— 与 deepin 的 Qt QPainter 同款内核需求，
将来做 linux 时**可复用本批的契约层与判据思路**（端口式 CanvasSink 是为这一步留的）。
