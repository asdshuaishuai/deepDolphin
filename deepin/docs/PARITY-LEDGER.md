# 跨端能力差距台账（PARITY-LEDGER）

**用途**：把「mac 端有什么 / 引擎有什么 / deepin 还差什么」摊成一张可勾选的账，
免得每批都靠记忆重新比一遍。**每落一项就改本表**（状态 + 落点 + 判据）。

- 审计日期：2026-10-19
- 审计基准：引擎仓 `../moongit`（`8b77627`）、mac 端 `macos/`（`dadca02`，功能基准）、deepin 端 `deepin/`
- 审计方法：① mac 53 个源文件 → deepin 88 个源文件逐个对位；② 判定层逐条比对
  （`Derived` / `DashboardScope` / `Scope` / `DashFilter` / `Thresholds` / `UpdateOutcome` / `StopDecision`）；
  ③ 引擎命令面枚举（`moongit --help` 24 条 / `tools --json` 10 条 / MCP `tools/list` 15 条）反查客户端消费点。

---

## A. mac → deepin：**已对位，无需动作**

文件级对位后逐条核对源码，以下能力两端**行为口径一致**（不是「有同名文件」，
是判定口径逐字对齐）：

| 能力 | mac 落点 | deepin 落点 | 核对结论 |
|---|---|---|---|
| 刷新合并门闩 | `ClientDecisions.swift` | `logic/ClientDecisions` | 一致 |
| 提交构成 12 色（不取模） | `CommitTypeComposition.swift` | `logic/CommitTypeComposition` | 一致 |
| 仪表盘 KPI 口径 | `DashboardScope.swift` | `logic/DashboardScope` | 一致：**项目总数用 `listed`（注册表条数）不是 `total`**；里程碑分母不含 `unknown`；分支数用 `repoBranchCount` |
| 「等我动手」判定顺序 | `Model.swift`（`needsAction` 先于 `engineStale`） | `logic/Derived.cpp:56` | 一致：**`needsAction` 必须在 `engineStale` 之前** |
| 可合入分支判据 | 引擎 `aheadOfDefault` | `logic/Derived.cpp:32` | 一致：`aheadOfDefault > 0 && !isDefault && !merged` |
| 状态词档位 | `Models.swift` | `logic/Derived.cpp:74` | 一致：`activeDays30` 线，说「N 天没更新」不说「停滞」 |
| 里程碑未知态 | `MilestoneCard.swift` | `logic/Derived.cpp:217` | 一致：`unknown` 不进徽标、不进达成率分母 |
| 引擎错误五类文案 | `EngineFailure.swift` | `models/EngineFailure` | 一致 |
| URL 错误脱敏 + host:port | `AIErrorMessage.swift` | `ai/AIChannel.cpp:25/34/44` | 一致（deepin 把三者并进 AIChannel） |
| 提交数分母口径 | `CommitCountScope.swift` | `models/StatusTypes.h:103` | 一致（deepin 并进 StatusTypes） |
| 侧栏「视图 / 仓库」两组 + 计数 | `SidebarView` | `ui/SidebarNav` | 一致 |
| 设置三页签（通用/自动化/AI） | `AISettingsView.swift` | `ui/dialogs/panes/*` | 一致 |
| 快捷键（13 个，撞键内置判定） | `ShortcutMap.swift` | `logic/ShortcutMap.h`（唯一声明处）+ PanelWindow 全量真绑 | 一致（deepin 用 Ctrl 代替 ⌘，与 `ShortcutMap.h` 映射表同款） |
| 文档平铺 / Markdown 渲染 | `MarkdownView.swift` | `ui/common/MarkdownView` | 一致 |
| 一键全量（刷新注册表→冻结名单→逐仓显式传名→一个失败不中断） | `AgentBulkUpdate.swift` | `AppModel::updateAll` | 一致 |
| 双轨更新 + AI 变体 | `UpdateActionMenu` | `ui/DualTrackButtons` + `AppModel::runUpdateDigest` | 一致 |
| 引擎未装 → 安装引导 | `DeepDolphinApp.swift` | `ui/pages/SetupGuidePage` | 一致 |
| 托盘 / 通知 / 开机自启 | `BarView` / `AppDelegate` / `SMAppService` | `tray/` / `app/Notifier` / `platform/AutostartManager` | 一致（平台 API 不同，能力口径同） |
| 外部打开（git remote → 浏览器） | `SysOpen.swift` | `platform/SysOpen` | 一致 |

---

## B. 引擎能力 → 客户端：**接了几条，还差几条**

引擎命令面 24 条，客户端实际消费点如下。

### B1. 已接

| 引擎命令 | 消费方 | 落点 |
|---|---|---|
| `status` / `dashboard` / `milestone *` / `docs` / `update` / `deep` / `git` / `add` / `scan` | UI 主流程 | `app/AppModel.cpp` |
| `context` / `tools` / `journal` / `milestone list` | agent 工具循环（10 个工具，与 `tools --json` 声明集严格相等） | `ai/AgentCore.cpp` |
| **`verify`（2026-10-19 新接）** | 文档完整性卡（四态判定） | `AppModel::loadVerify` → `logic/DocumentIntegrity` |

### B2. 未接 —— 候选（**每条都要先答「用户为什么需要它」，答不出就不接**）

| 引擎命令 | 能力 | 客户端为什么可能需要 | 状态 |
|---|---|---|---|
| `verify` | 文档完整性校验 | 引擎已有严谨四态；C11 承诺当时只靠反向 grep 撑着，用户看不见 | ✅ **已接**（决策 84） |
| `doctor` | 环境自检（git 版本 / 数据目录 / 注册项目 / 路径有效 / 临时残留） | `SetupGuidePage` 只在「引擎没装」时出现；**引擎装了但环境有病**（git 缺失、路径失效、残留）当前无处可看 | ⬜ 待定 |
| `report` | 导出 Markdown 进度报告 | 引擎侧有报告生成器；客户端目前只读不导出 | ⬜ 待定（导出=写文件，客户端零业务写入红线要先想清楚） |
| `config` | 配置（AI 预设等） | 客户端已有 `settings.conf` 自管配置；引擎 config 与之的关系未查清 | ⬜ 待查 |
| `list` | 列出已注册项目 | `status` 已含项目清单，可能冗余 | ⬜ 待查 |
| `remove` | 取消注册项目 | **用户诉求明确**（注册错了要能删）—— 但当前无「移除项目」入口 | ⬜ **待定（优先级高）** |
| `track` | 进度快照 | `journal` 已覆盖其产物 | ⬜ 待查 |
| `hook` | post-commit 钩子管理 | 装钩子=写用户仓库文件，撞 C11 红线 | ⬜ **不接**（除非用户显式要求） |
| `mcp` | MCP stdio 服务 | 客户端是 MCP **宿主**（消费 tools），不是服务端 | ⬜ 不接 |
| `skill` | agent 技能教学包 | 客户端 agent 工具循环是自研的，不是引擎 skill 机制 | ⬜ 不接 |

> MCP 侧另有 5 个工具（`list_projects` / `get_project_status` / `get_dashboard` / `run_track` /
> `git_op` / `milestone_add` / `milestone_action` / `add_project`）不在 `tools --json` 的 10 条声明集里 ——
> 那 5 条是 **MCP 传输面**的补充，CLI 侧没有对应命令，客户端走 CLI，不需要补。

---

## C. deepin 自身计划文档的剩余项（`docs/DDE-INTEGRATION-PLAN.md` §9 看板）

不属于「同步 mac」，是 deepin 客户端自身的 DDE/DTK 化收尾：

| 任务 | 内容 | 状态 |
|---|---|---|
| M1-2 | 统一 `platform::icon()`（fallback 链 + 缺失告警 + DDciIcon 优先） | ⬜ |
| M1-3 | 托盘迁移 SNI | ⬜ |
| M1-7 | `platform/Backend` 平台层 | ⬜ |
| M1-8 | Wayland 分支 | ⬜ |
| M2-5 | i18n | ⬜ |
| M2-7 | deb 打包 | ⬜（D7 达标必经） |
| M2-8 | 安装后零环境变量 | ⬜（D7 达标必经） |
| M3c | 清第二套色板 + 一致性 / HiDPI / 动效收尾 | ⬜（观感质变收尾） |
| M1a | 容器 / 视图批（部分） | ◐ 部分落地 |
| M0-8 | 干净容器未实跑 | ◐ |
| M3b | KPI 骨架屏 | ◐ |
| M4a | 拆分 | ◐ |
| M4b | deb 构建与系统矩阵 | ◐ |

---

## D. 跨端一致性债（**deepin 领先 mac 的部分**）

章程 `PLATFORM-CHARTER.md`：「交互 UI 各平台自由，**能力必须一致**」。

| 能力 | deepin | mac | linux | 补齐批次 |
|---|---|---|---|---|
| 文档完整性校验（引擎 `verify` 四态） | ✅ 2026-10-19 | ⬜ 未接 | ⬜ 未接 | 后续批次（本次按「先搞定 dde」次序落地，债已记） |

---

## E. linux 端

**本轮明确暂缓**（用户 2026-10-19 定：「linux 通用再说」）。
linux 侧已知的独立缺口（快捷键零覆盖、AI 面板非独立窗、libsecret 降级等）
记在 `linux/README.md` 的「与 macOS 端的已知差异」与 `linux/VERIFY-ON-LINUX.md`，不在本账内推进。
