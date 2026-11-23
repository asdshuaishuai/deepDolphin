# deepDolphin — Compose Multiplatform 客户端

> moonGit 引擎的桌面客户端（Kotlin + Compose Multiplatform，桌面 JVM），承接 `archive/bui`
> （Rust 版 BUI 客户端）的能力口径，交互基准对位 [macos/](../macos/README.md)。
> 能力面按 [PLATFORM-CHARTER.md](../PLATFORM-CHARTER.md) C1–C11 对齐——能力必须一致、交互 UI 自由。
> 引擎访问唯一通路：`moongit <命令> --json` CLI 子进程，**没有 HTTP、没有 FFI**。
> 分批执行手册（计划/红线/判据纪律）见 [PLAN.md](PLAN.md)。

## 状态（2026-11-24）

- 判据门禁绿：`scripts/build.sh --test` → 133 判据（`023f675` 时点记账；全量由门禁脚本复跑）。
- **真窗口终验通过（2026-11-24，DISPLAY=:0）**：图谱两页 / 置信度 / 补丁体检 / 侧栏搜索 /
  Ctrl+1/2/3 / 设置-自动化 / hero 双轨八项逐项真机验证，截图见 `docs/ui-cmp/`
  （`graph-*` / `conf-*` / `interact-*` 共 8 张）；JCEF 150.0.14 WebView 装载实测成功。
- 引擎发现顺序与各端一致（EngineLocator.kt）：`MOONGIT_BIN` → `DEEPGIT_BIN` →
  仓内构建 `../moonGit/target/release/bin/main` → PATH（`moongit`/`deepgit`）。

## 构建与运行

```sh
cd client
scripts/build.sh            # 编译（gradle build）
scripts/build.sh --test     # 编译 + 全量判据（jvmTest），末行 CMPTEST_SUMMARY，failed≠0 即失败
scripts/build.sh --run      # 编译后真窗口启动（需 DISPLAY）
scripts/run.sh              # 同上（gradle run）

gradle packageDeb           # jpackage 打 deb（或 packageAppImage）
```

依赖：JDK 21 + Gradle（本机装在 `~/.local/jdk`、`~/.local/gradle`，build.sh 自动定位）。
KCEF/JCEF 在 JDK17+ 完成反射初始化所需的两条 `--add-opens` 已进 jpackage `--java-options`
与本地 `run` 任务（build.gradle.kts）。

## 功能面（侧栏导航 + 搜索框 + 仓库行；路由七页 + 图谱两浮层）

| 页 | 内容 |
|---|---|
| **仪表盘** | hero 双轨更新按钮（浅/深更新带范围「· 全部 / · 项目名」，待记录徽章 >0 才现，副行明示深更新动哪些托管文档）+「添加/扫描」开扫描单（路径三态判定 + 逐项目新增/已在册推导 + 三种「没扫完」分开说）；KPI 磁贴 / 语言分布 / 里程碑 / 活跃项目 + 筛选；aurora 渐变斑块层（对位 archive/bui design.rs） |
| **看板** | 按引擎 `branch.status` 原值分列（active/stale/idle/merged），不重算引擎已给的结论；采集失败单独「读不出」列；分支返回不全在页头披露「引擎返回 M/N」；列头计数与行数同源 |
| **里程碑** | 列表 + 新建（tag 自动达成/date/desc）+ 行内动作达成/重开/放弃/删除；删除/放弃必过确认框 |
| **代码置信度** | `graph confidence --json`：六维度总分 + 权重降序疑点清单（默认只给位置、≥8 红档、点击展开引擎证据 + 实码读不出如实说）+ 只看高权重（≥8）开关 + 复制 LLM 复核提示词（--llm 纯文本 → 剪贴板，stdout/stderr 分流防引擎杂音混入） |
| **补丁体检** | diff 多行粘贴 → Layer1 算法层（S1..S10 信号 chip，null=分母 0 降档披露）→ uncertain 三态人工裁决（确认/未解决/不确定）→ Layer3 合并终稿（复核计数 + 警示行） |
| **项目详情** | 单项目三源（`status <名>` / docs / journal，失败不短路、逐源披露）+ git 白名单六操作（commit 带类型前缀选择 + ok/output 结果反馈，失败信息留住）+ 浅/深更新；动作条「代码图谱/架构图」busy 生成→成功即开图谱浮层 |
| **设置** | 四 tab：**通用（语言选择器 + 自启动）**/ AI（渠道+key）/ **自动化**（定时更新：间隔档 0/1/3/6/12/24 小时 + 浅/深轨道，写 settings.conf `update.*` 独立节、改完立即生效）/ **关于（四文档子 tab：关于/帮助/开源感谢/更新日志，四语言内容对位 mac DocsPages）** |

浮层：**代码图谱 / 架构图**（Dialog 近全屏）——引擎 `render index --confidence` / `render arch`
的交互 HTML 产物经 JCEF WebView 直载（客户端不原生绘制），底部回执条给版本/复用判定；
产物进程内缓存，重开先秒开旧图再后台核验。

- C2 周期轮询 5 分钟 + 手动刷新（AppModel.startPolling；refreshAll 逐源失败不短路）。
- 定时更新（自动化 tab）：AppModel 协程定时器，首轮延迟 10 分钟防启动即全量更新；与 mac
  差异如实：无守护进程，随应用存活、退出即停；系统通知/AI 简报未接。
- 侧栏搜索：项目名 + 分支名大小写不敏感子串过滤，空结果两态分开说（本来就没有 ≠ 没匹配上），
  匹配时给「匹配 N / M 个仓库」行；Ctrl+F 聚焦搜索框。
- 窗口级快捷键（ShortcutMap 单点声明）：Ctrl+1/2/3 切视图、Ctrl+, 设置、Ctrl+R 刷新、Ctrl+F 搜索。
- 写操作纪律：每次写都留一行结果（✓/✗ 带原因），引擎调用全在协程 IO。
- 深链启动参数（C10 已接线）：`--section dashboard|board|milestones`、`--project <名称>`；
  非法 section 宽容落 dashboard，不崩。
- **多语言（L10n）**：四语言 zh-CN / en / zh-TW / ja，键值表从 mac `L10n.swift` 脚本搬运
  （`client/scripts/gen_l10n.py`，504 键照搬不改写）+ CMP 特有键以 zh 为源补齐四语言
  （`ui/L10nCmpKeys.kt`，`cmp.` 前缀）；全部视图文案走 `L10n.t(key)`（语言是 Compose 状态，
  设置-通用切语言即时全界面生效）；语言存 settings.conf `app.language` 独立节，未配置时跟随
  系统语言、认不出缺省 zh-CN。已知边界如实：AI 层错误/提示词不本地化（mac AIClient 同口径，
  中文为诊断语言）；托盘 AWT 菜单标签在启动时定格（换语言重启后生效）。

## AI 层（客户端 AI，引擎 AI 无关）

- **双协议引擎**（ai/Engines.kt）：OpenAI 兼容 + Anthropic 原生 `tool_calls`/`tool_use` 线格式；
  URL 只放行 `https://` 与 `http://127.0.0.1`/`http://localhost`（防投毒端点骗取 apiKey）；
  网络失败给中文原因与下一步。
- **key 纪律**：key 只进 libsecret（secret-tool 子进程，AiViews.kt SecretStore）；
  `~/.config/deepDolphin/settings.conf` 只存 `ai.providerID/model/baseURL`，保存时只合并
  `ai.*` 键、不动其他行；key 不回填明文。libsecret 缺席时的 0600 兜底文件未实现。
- **agent 循环**（ai/AgentCore.kt）：引擎 `tools --json` 是工具清单唯一来源，必填参数只从
  「已发给模型的那份」定义取；≤4 轮；停止逐轮检查 + 工具执行中切片响应。
- **Markdown 渲染**：markdown→HTML 纯函数（ai/MarkdownHtml.kt，正文先转义再套标签，
  不支持的语法宁缺勿错）+ 单 WebView 组件（ui/MarkdownWebView.kt，CSS 全部由 Design.kt
  的 Palette/Type/Space 运行时派生，色值单点真相源不破）。webview 是重量组件，只在
  最新一条助手消息启用；KCEF 每进程只尝试装载一次，超时后台续装、完成自动切排版。
- **未落地**：models.dev 目录选择器（现固定四渠道 + 手填）、更新后 AI 摘要 / 简报通知。
  ~定时更新小时档~ 已落地（设置「自动化」tab，`update.*` 独立键节）。

## 系统集成（C10，Linux 通用 freedesktop 机制，无 DDE 专属）

- 深链 `--section`/`--project` 已接线（Main.kt → SysInt.parseDeepLink）。
- XDG autostart 写盘（Exec 绝对路径整参数转义）在 sysint/SysInt.kt，界面开关已接线
  （设置「通用」tab，仅打包安装态可开）；notify-send 封装（缺席如实降级）有判据覆盖，
  界面开关未接线。
- SystemTray 常驻速览：已实现（X11 简版——AWT SystemTray 圆点图标 + 摘要行/打开面板/退出，
  摘要随 status 流推送，`dirty=null` 是读不出 ≠ 0；isSupported false 静默降级。
  mac MenuBarExtra 的弹窗项目行/迷你进度条不做，头注释标注形态差异）。

## 分发

- jpackage：deb / AppImage（build.gradle.kts nativeDistributions；Linux 菜单项 + 快捷方式）。
- KCEF/JCEF 二进制**不随包分发**：首跑需联网从 GitHub 下载；不可用时回退纯文本并标注原因。

## 代码结构（按磁盘）

```
src/jvmMain/kotlin/deepdolphin/
  Main.kt                 入口：窗口 + 页头引擎探活 + 侧栏外壳（七路由 + 搜索框 + 快捷键）+ 深链接线
  engine/Engine.kt        引擎命令封装：读（status/dashboard/milestone list/docs/journal/tools/
                          graph confidence/patchconf）写（milestone、git 六操作、update/deep/
                          全部、scan/add/remove、render index/arch、patchconf merge）
  engine/EngineLocator.kt 引擎发现 + 探活（version）+ 子进程执行（超时强杀；runMerged/runSplit）
  engine/Models.kt        --json 契约模型（kotlinx.serialization；缺键=契约过旧的口径）
  engine/EngineStub.kt    判据用引擎桩（必填校验在引擎调用之前）
  ai/AiModels.kt          协议形状（ChatMessage/ToolDef/GenerateRequest；ai.* conf 合并纪律）
  ai/Engines.kt           双协议引擎 + 工厂（URL 白名单；失败中文原因）
  ai/AgentCore.kt         agent 工具循环（≤4 轮；工具清单唯一来源；取消真杀子进程）
  ai/MarkdownHtml.kt      markdown→HTML 纯函数（先转义再套标签；<script> 只能以实体出现）
  sysint/SysInt.kt        notify-send 封装 + XDG autostart + 深链解析（纯函数可测）
  sysint/TrayQuickView.kt SystemTray 托盘速览（X11 简版；isSupported false 静默降级）
  ui/Design.kt            设计系统（Palette/Type/Space 单点真相源 + aurora 纯函数）
  ui/AppModel.kt          数据编排（每源一份 LoadState；路由；写操作留结果；C2 轮询；定时更新）
  ui/DashboardView.kt     仪表盘（hero 双轨更新 + KPI/语言/里程碑/活跃 + 扫描单入口 + aurora）
  ui/BoardView.kt         看板（引擎状态分列；读不出单列；分支不全如实披露）
  ui/MilestonesView.kt    里程碑（CRUD + 破坏动作确认）
  ui/ConfidencePages.kt   代码置信度 + 补丁体检两页（披露式行/三态裁决/合并终稿）
  ui/GraphPages.kt        图谱两页浮层（render 回执解析 + 产物缓存 + Dialog 近全屏）
  ui/HtmlWebView.kt       KCEF/JCEF 装载状态机 + 通用 WebView 组件（Markdown/图谱共用）
  ui/ProjectDetailView.kt 项目详情（三源 + git 六操作 + 图谱入口 + 更新）
  ui/ScanSheet.kt         扫描单（路径三态 + 逐项目新增/已在册推导 + 覆盖披露）
  ui/Automation.kt        定时更新配置（settings.conf update.* 独立节读写）
  ui/SearchFilter.kt      侧栏搜索纯函数（过滤/两态空因/resultSummary）
  ui/ShortcutMap.kt       窗口级快捷键单点声明（Ctrl+1/2/3/,/R/F）
  ui/AiViews.kt           AI 设置页 + 对话页 + 设置四 tab（通用含语言选择器/关于含四文档）
  ui/L10n.kt              多语言单例（t(key)/语言状态/回退链 当前→en→key/settings.conf 读写）
  ui/L10nTables.kt        四语言表 + 四文档（GENERATED：gen_l10n.py 从 mac 基准生成，勿手改）
  ui/L10nCmpKeys.kt       CMP 特有键四语言（cmp. 前缀；以 zh 为源补 en/zh-TW/ja）
  ui/MarkdownWebView.kt   KCEF/JCEF 单 WebView Markdown 组件（复用 HtmlWebView）
src/jvmTest/kotlin/
  engine/ContractTest.kt        fixtures 契约回归（真实引擎输出，缺必知键=契约过旧）
  ui/ConfidencePagesTest.kt     置信度/补丁体检判据（10 条）
  ui/GraphParseTest.kt          render 回执/路径提取判据（10 条）
  ui/ScanSheetLogicTest.kt      扫描单判定判据（10 条）
  ui/CommitFormTest.kt          提交类型前缀判据（5 条）
  ui/SearchFilterTest.kt        侧栏搜索判据（11 条）
  ui/ShortcutMapTest.kt         快捷键声明判据（8 条）
  ui/AutoUpdateSettingsTest.kt  自动化配置判据（9 条）
  ui/HeroUpdateScopeTest.kt     hero 双轨范围判据（6 条）
  sysint/TrayQuickViewTest.kt   托盘摘要行判据（4 条）
  ui/L10nTest.kt          多语言判据（13 条：键集四语言对齐缺键即红/占位符一致/回退链/切换读写/四文档分发）
  ui/BoardContractTest.kt       看板列分配与披露判据（6 条）
  ai/MarkdownHtmlTest.kt        markdown→html 判据（8 条）
  ui/DesignRefinementTest.kt    aurora/空态判定判据（9 条）
  ai/AiTest.kt                  mock 通道工具循环 / URL 门 / conf 合并 / 必填校验
  sysint/SysIntTest.kt          Exec 转义 / 自启写盘 / 深链解析
  resources/fixtures/           status/dashboard/milestones/docs/journal/confidence/render
                          真实引擎 JSON/文本（fixtures 全部真跑落盘）
```

判据纪律：判据只增不减；`scripts/build.sh --test` 跨套件求和，`failed=0` 才算过。
