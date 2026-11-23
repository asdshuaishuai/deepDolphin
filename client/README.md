# deepDolphin — Compose Multiplatform 客户端

> moonGit 引擎的桌面客户端（Kotlin + Compose Multiplatform，桌面 JVM），承接 `archive/bui`
> （Rust 版 BUI 客户端）的能力口径，交互基准对位 [macos/](../macos/README.md)。
> 能力面按 [PLATFORM-CHARTER.md](../PLATFORM-CHARTER.md) C1–C11 对齐——能力必须一致、交互 UI 自由。
> 引擎访问唯一通路：`moongit <命令> --json` CLI 子进程，**没有 HTTP、没有 FFI**。
> 分批执行手册（计划/红线/判据纪律）见 [PLAN.md](PLAN.md)。

## 状态（2026-11-23）

- 判据门禁绿：`scripts/build.sh --test` → `CMPTEST_SUMMARY passed=45 skipped=0 failed=0`。
- **真窗口冒烟：异常，未通过**——运行时观感（aurora / hover / WebView 排版）未可视核验；
  KCEF 首跑需联网从 GitHub 下载 JCEF 二进制，不可用时按设计回退纯文本并在界面标注原因。
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

## 功能面（侧栏导航 + 仓库行；路由六页）

| 页 | 内容 |
|---|---|
| **仪表盘** | KPI 磁贴 / 语言分布 / 里程碑 / 活跃项目 + 筛选；项目总数 0 时给扫描/添加 CTA（接引擎 `scan`/`add`，截断/深度封顶/读不出如实披露）；aurora 渐变斑块层（对位 archive/bui design.rs） |
| **看板** | 按引擎 `branch.status` 原值分列（active/stale/idle/merged），不重算引擎已给的结论；采集失败单独「读不出」列；分支返回不全在页头披露「引擎返回 M/N」；列头计数与行数同源 |
| **里程碑** | 列表 + 新建（tag 自动达成/date/desc）+ 行内动作达成/重开/放弃/删除；删除/放弃必过确认框 |
| **项目详情** | 单项目三源（`status <名>` / docs / journal，失败不短路、逐源披露）+ git 白名单六操作（pull/push/commit/stash/unstash/fetch，commit 带信息输入）+ 浅/深更新（单项目与全项目） |
| **AI 助手** | agent 工具循环（≤4 轮，工具循环事件可见）+ 停止按钮（真取消）；最新一条助手消息 WebView 渲染 Markdown，缺席/失败回退纯文本并如实标注 |
| **AI 设置** | 渠道四选一（deepseek / anthropic / ollama / mock）+ 模型/Base URL 手填 + key 存 libsecret + 测试连接 |

- C2 周期轮询 5 分钟 + 手动刷新（AppModel.startPolling；refreshAll 逐源失败不短路）。
- 写操作纪律：每次写都留一行结果（✓/✗ 带原因），引擎调用全在协程 IO。
- 深链启动参数（C10 已接线）：`--section dashboard|board|milestones`、`--project <名称>`；
  非法 section 宽容落 dashboard，不崩。

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
- **未落地**：models.dev 目录选择器（现固定四渠道 + 手填）、C5 整合更新流（更新+AI 摘要 /
  定时更新小时档 / 简报通知）。

## 系统集成（C10，Linux 通用 freedesktop 机制，无 DDE 专属）

- 深链 `--section`/`--project` 已接线（Main.kt → SysInt.parseDeepLink）。
- notify-send 通知封装（缺席如实降级）与 XDG autostart 写盘（Exec 绝对路径整参数转义）
  在 sysint/SysInt.kt，纯函数与判据覆盖——**界面开关尚未接线**（代码无 UI 调用点）。
- SystemTray 常驻速览：未实现。

## 分发

- jpackage：deb / AppImage（build.gradle.kts nativeDistributions；Linux 菜单项 + 快捷方式）。
- KCEF/JCEF 二进制**不随包分发**：首跑需联网从 GitHub 下载；不可用时回退纯文本并标注原因。

## 代码结构（按磁盘）

```
src/jvmMain/kotlin/deepdolphin/
  Main.kt                 入口：窗口 + 页头引擎探活 + 侧栏外壳（六路由）+ 深链接线
  engine/Engine.kt        引擎命令封装：读（status/dashboard/milestone list/docs/journal/tools）
                          写（milestone add/action/remove、git 六操作、update/deep/全部、
                          scan/add/remove、render check）；exit≠0 但 stdout 可解析 ≠ 失败
  engine/EngineLocator.kt 引擎发现 + 探活（version）+ 子进程执行（超时强杀）
  engine/Models.kt        --json 契约模型（kotlinx.serialization；缺键=契约过旧的口径）
  engine/EngineStub.kt    判据用引擎桩（必填校验在引擎调用之前）
  ai/AiModels.kt          协议形状（ChatMessage/ToolDef/GenerateRequest；ai.* conf 合并纪律）
  ai/Engines.kt           双协议引擎 + 工厂（URL 白名单；失败中文原因）
  ai/AgentCore.kt         agent 工具循环（≤4 轮；工具清单唯一来源；取消真杀子进程）
  ai/MarkdownHtml.kt      markdown→HTML 纯函数（先转义再套标签；<script> 只能以实体出现）
  sysint/SysInt.kt        notify-send 封装 + XDG autostart + 深链解析（纯函数可测）
  ui/Design.kt            设计系统（Palette/Type/Space 单点真相源 + aurora 纯函数）
  ui/AppModel.kt          数据编排（每源一份 LoadState；路由；写操作留结果；C2 轮询）
  ui/DashboardView.kt     仪表盘（KPI/语言/里程碑/活跃 + 空态扫描/添加 CTA + aurora）
  ui/BoardView.kt         看板（引擎状态分列；读不出单列；分支不全如实披露）
  ui/MilestonesView.kt    里程碑（CRUD + 破坏动作确认）
  ui/ProjectDetailView.kt 项目详情（三源 + git 六操作 + 更新）
  ui/AiViews.kt           AI 设置页 + 对话页（SecretStore / ConfStore）
  ui/MarkdownWebView.kt   KCEF/JCEF 装载状态机 + 单 WebView Markdown 组件
src/jvmTest/kotlin/
  engine/ContractTest.kt        fixtures 契约回归（真实引擎输出，缺必知键=契约过旧）
  ui/BoardContractTest.kt       看板列分配与披露判据（6 条）
  ai/MarkdownHtmlTest.kt        markdown→html 判据（8 条）
  ui/DesignRefinementTest.kt    aurora/空态判定判据（9 条）
  ai/AiTest.kt                  mock 通道工具循环 / URL 门 / conf 合并 / 必填校验
  sysint/SysIntTest.kt          Exec 转义 / 自启写盘 / 深链解析
  resources/fixtures/           status/dashboard/milestones/docs/journal 真实引擎 JSON
```

判据纪律：判据只增不减；`scripts/build.sh --test` 跨套件求和，`failed=0` 才算过。
