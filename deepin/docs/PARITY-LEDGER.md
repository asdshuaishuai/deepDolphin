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
| B7 | **固定文档页** | `DocsPages.swift`（321 行） | ⬜ 未开始 | P2 |
| B8 | **四语言本地化（全应用接入）** | `L10n.swift`（2108 行） | ⬜ 未开始（deepin 现无 i18n；引擎侧 CLI 已双语） | P2（量大） |
| B9 | **原生菜单栏三件套（关于/帮助/设置）+ 设置统一为系统原生窗口** | `DeepDolphinApp.swift` | 🟡 deepin 有托盘菜单与设置页签，但非「原生独立设置窗口」 | P2 |
| B10 | **仪表盘项目卡片整卡可点** | `DashboardParts.swift` | ⬜ 未开始 | P3（小） |
| B11 | **Agent 补齐 18 个图能力工具**（契约检查第 12 组抓到的清单漂移） | `AgentCheck` | 🟢 **已对位（批 E1）**：28 个工具全接（命令形态抽成纯函数表 `logic/AgentToolPlan`，可无头判）；`deepDolphin --agent-tool-names` 出客户端权威清单，contract-check 第 12 组与真引擎 `tools --json` 严格对位（**CI 第 10 门**） | ~~P0~~ 已完成 |
| B12 | **9 语言语法高亮** | mac 原生 `AttributedString` | ⬜ 未开始（引擎侧 `graph confidence` 已给语义层检测） | P2 |
| B13 | **性能审计**：动画时钟可见性暂停 + formatter 静态化 | `21c7082` | ⬜ 未开始（deepin 有 HasAnimations 纪律但无可见性暂停） | P3 |
| B14 | **设计系统存量清零**（字号/散值收进 token，基线 87→95） | `e9d6074` | ⬜ deepin 侧 D2 门仍有 4 处存量 | P3 |
| B15 | **引擎获取链新增 GitHub Releases 自动下载** | `macos/build.sh` | ⬜ deepin `EngineLocator` 无此链 | P2 |
| B16 | **关系树 / 图谱的导出动作**（查 + 生成 + 导出三件套） | `d62e429` | ⬜ 未开始（依赖 B1/B2） | P1 |

**引擎侧对应的新能力**（deepin 消费点）：

| 引擎命令 / 工具 | 用途 | deepin 现状 |
|---|---|---|
| `graph arch --format scene` | 场景 JSON（B1 的数据源） | ✅ 批 D1 已接（内核）+ 批 D2 已接（页面） |
| `graph overview` / `symbol` / `impact` / `tree` / `functions` | 图谱五件套（B2/B5/B6） | 🟡 批 E2 已接 `tree` / `functions`（代码图谱页三源之二）；`overview` / `symbol` / `impact` ⬜ |
| `graph confidence` / `patchconf` | 置信度与补丁体检（B4/B6） | 🟢 批 E2 已接 `confidence`（置信度总分/维度/疑点 → 详情页「置信度」页签 + 热力图热色输入）；批 F 已接 `patchconf` 三形态（`--patch` / `--skill` / `--merge` → 补丁体检窗三层） |
| `arch gen` / `graph gen` / `index gen` | 生成（B16） | 🟡 批 D2 已接 `arch gen`（架构图页「生成」钮）；`graph gen`/`index gen` ⬜ |
| `render arch` | 导出交互 HTML（B16） | 🟡 批 D2 已接（架构图页「导出」钮；落盘 HTML 是引擎层交付物，**不是**本平台的渲染路径） |
| `codegraph_*`（CLI 清单 18 个新工具） | agent 工具循环（B11） | 🟢 批 E1 已接 |
| `render` 工具 | 渲染交付物 | ⬜ |
| `index_*` 家族 | 代码索引（`graph` 的新家） | ⬜ |

---

## C. 引擎能力面（`dev` 分支，2026-10-19 实测）

| 面 | 数量 | 说明 |
|---|---|---|
| CLI 命令 | 24 | 另有 `graph`/`index` 子命令族（`dev` 分支新增，main 上没有） |
| `tools --json`（agent 工具清单） | **28** | 原 10 + 18 个图/置信度工具（mac 的 B11 就是补这 18 个） |
| MCP `tools/list` | **33** | 进度 14 + 图谱 6 + 补丁置信度 3 + 其他 |
| 契约文档 | `docs/graph-scene-schema.md` | 两层契约：Canvas2D 子集（26 方法）+ scene JSON v1 |

> ⚠ 章程 §4 写的「23 工具」也已过期（dev 分支实测 33）—— 属引擎仓的账，本仓只记事实。

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

---

## E. deepin 自身 DDE/DTK 化剩余项（`docs/DDE-INTEGRATION-PLAN.md` §9 看板）

不属于「同步 mac」，是 deepin 客户端自身的收尾：

| 任务 | 内容 | 状态 |
|---|---|---|
| M1-2 | 统一 `platform::icon()`（fallback 链 + 缺失告警 + DDciIcon 优先） | ⬜ |
| M1-3 | 托盘迁移 SNI | ⬜ |
| M1-7 | `platform/Backend` 平台层 | ⬜ |
| M1-8 | Wayland 分支 | ⬜ |
| M2-5 | i18n | ⬜（与 B8 合并做更省） |
| M2-7 | deb 打包 | ⬜（D7 达标必经） |
| M2-8 | 安装后零环境变量 | ⬜（D7 达标必经） |
| M3c | 清第二套色板 + 一致性 / HiDPI / 动效收尾 | ⬜（与 B13/B14 同批更省） |
| M1a / M0-8 / M3b / M4a / M4b | 容器批 / 干净容器 / KPI 骨架屏 / 拆分 / deb 矩阵 | ◐ 部分落地 |

---

## F. linux 端

**本轮明确暂缓**（用户 2026-10-19 定：「linux 通用再说」）。
linux 侧已知独立缺口记在 `linux/README.md` 的「与 macOS 端的已知差异」与 `linux/VERIFY-ON-LINUX.md`。
注意：章程 §3.5 把 linux 的实现指定为**仓颉 Canvas 移植** —— 与 deepin 的 Qt QPainter 同款内核需求，
将来做 linux 时**可复用本批的契约层与判据思路**（端口式 CanvasSink 是为这一步留的）。
