# deepDolphin CMP 客户端 · 全量能力复刻计划（执行手册）

> 分支：`next/cmp`（骨架已验证：Compose 真窗口 + 引擎探活 moonGit 0.2.0 实测通过）。
> 基准：`archive/bui` 标签的 BUI 客户端（Rust 版 v1，含 tests/fixtures 真实引擎 JSON）
> 与 `macos/`（SwiftUI 基准）；能力口径 = PLATFORM-CHARTER.md C1–C11，**能力必须一致、
> 交互 UI 自由**。本端技术栈：Kotlin + Compose Multiplatform（桌面 JVM）+ webview
>（compose-webview-multiplatform / JCEF，Markdown 与富文本渲染用）。

## 环境速查（本机已就绪，无 root）

```sh
export JAVA_HOME="$(ls -d ~/.local/jdk/jdk-21* | sort -V | tail -1)"
export PATH="$JAVA_HOME/bin:$HOME/.local/gradle/gradle-8.10.2/bin:$PATH"
cd client
scripts/build.sh            # 编译；--test 跑全量判据
scripts/run.sh              # 真窗口（DISPLAY=:0）
```

- 引擎：`~/code/moonGit/target/release/bin/main` 已构建；PATH 上有 moongit 0.2.0。
- 依赖仓库：Maven Central + Google + JitPack + **jogamp.org**（kcef 的 gluegen/jogl 只在此）。
- 已知坑：①KMP 的 JVM 源码目录是 `src/jvmMain/kotlin`（不是 src/main/kotlin）；②`cc` 指向
  dd-sysroot gcc-13 真 C 驱动（~/.local/bin/cc，g++ 驱动过不了 cmake ABI 探测）——C 部分构建用。

## 分批计划（每批 = 一次可运行验证 + 一个 commit）

### 批 1 · 设计系统 + 引擎层 + 仪表盘（C1/C2/C3-仪表盘）
- Fluent 深色设计系统（对位 archive/bui 的 design.rs：磁贴/圆角/色板/字号七档/对比度闸门）。
- 引擎层完整化：status/dashboard/docs/journal/milestone/git/update/deep 全命令封装
  （kotlinx.serialization；fixtures 对位 = `git show archive/bui:client/tests/fixtures/`）。
- C2 周期轮询（5 分钟）+ 手动刷新；仪表盘页（KPI 磁贴/语言分布/里程碑/活跃 + 范围/类型筛选）。
- 判据：契约解析 fixtures 全量回归（缺键=契约过旧的口径不变）。

> ✅ 已落地 · 2026-11-23 核对（commit `133fa2c`）。

### 批 2 · 里程碑 + 详情 + git（C9/C3/C8）
- 里程碑 CRUD（tag 自动达成/date/desc）+ 列表页。
- 项目详情（脉搏/提交构成/分支/日志/文档四态，长文区 webview 或 Compose 渲染）。
- git 白名单六操作（pull/push/commit/stash/unstash/fetch）+ 结果输出区；破坏动作过确认。

> ✅ 已落地 · 2026-11-23 核对（commit `ddcf6ed`）。

### 批 3 · AI 全家桶（C7/C6/C5）
- C7 设置：provider/model 目录选择（models-dev 快照，assets/models/models-dev.json 注入）、
  key 存 libsecret（secret-tool 子进程）→ 0600 文件兜底、测试连通。
- C6 助手：agent 工具循环（≤4 轮，工具集与 mac/BUI 一致）、对话页（**webview 渲染 Markdown**，
  webview 能力在此落地）、停止按钮（真杀进程）。
- C5 整合更新：更新+AI 摘要、项目/群说明、定时更新（小时档）+ 简报通知。

> ✅ 大部落地 · 2026-11-23 核对（commit `c53f655`；**webview 渲染 Markdown** 由批后收尾
> 补齐 `748dde9`，见下节）。如实未落地：models-dev 目录选择器——AI 设置现为固定四渠道
> （deepseek/anthropic/ollama/mock）+ 模型/Base URL 手填（AiViews.kt）；key 的 0600
> 兜底文件（libsecret 缺席时的回退）未实现（AiViews.kt 头注释自记「批 4 补」，至今未补）；
> C5 整合更新流（更新+AI 摘要 / 定时更新小时档 / 简报通知）无代码。

### 批 4 · 系统集成 + 分发（C10/C11）
- C10：notify-send 通知、XDG 自启（Exec 绝对路径——吸取 run.sh 教训）、
  深链 --section/--project、SystemTray 常驻速览（java.awt.SystemTray，Linux 复核）。
- 分发：compose desktop nativeDistributions（jpackage，Linux deb/-appimage 任一）。
- 终验：全判据 + 真窗口截图全套（对位 archive/bui 的 docs/ui/after 口径）+ 打包安装冒烟。

> ✅ 大部落地 · 2026-11-23 核对（commit `9227a04`）。深链已接线（Main.kt →
> SysInt.parseDeepLink）；notify-send 封装与 XDG autostart 写盘在 sysint/SysInt.kt
> （判据覆盖）但**界面开关未接线**（代码无 UI 调用点）；SystemTray 常驻速览未实现；
> jpackage deb/AppImage 已配置（build.gradle.kts），打包安装冒烟未跑。

## 批后收尾批 + 落地终验（2026-11-23 核对）

四批骨架之后的三个收尾批（判据只增不减，commit 与门禁数字如下）：

| 收尾批 | commit | 判据增量 | 门禁 |
|---|---|---|---|
| 看板页真实现：stub → 引擎分支状态分列（active/stale/idle/merged），读不出单列，分支不全/无分支如实披露 | `b1abfb7` | +6（BoardContractTest） | 28 绿 |
| AI 助手 Markdown 渲染：最新一条助手消息走 KCEF/JCEF WebView 排版，缺席/失败回退纯文本并如实标注；markdown→html 纯函数（MarkdownHtml.kt / MarkdownWebView.kt） | `748dde9` | +8（MarkdownHtmlTest） | 36 绿 |
| 仪表盘与详情页精修：aurora 渐变斑块层（对位 design.rs）+ 项目总数 0 空态扫描/添加 CTA（接引擎 scan/add）+ 磁贴描边/hover + 详情页 SectionCard 节奏（色值上收 Design.kt） | `0cb2a46` | +9（DesignRefinementTest） | 45 绿 |
| 图谱两页：HtmlWebView 通用件（JCEF 单浏览器复用/reloadToken/看门狗/降级槽；MarkdownWebView 改为复用）+ CodeGraphPage/ArchPage 接 `render index --confidence`/`render arch` 文本回执（receiptLine/extractHtmlPath/renderReused 纯函数，fixture 真机落盘；产物缓存秒开旧图、复用不重载）+ Dialog 近全屏形态 + AppModel 开合流挂载；JCEF 缺席整页降级「WebView 不可用 + 产物路径」 | `72376da` | +10（GraphParseTest） | 61 绿 |
| 详情页接图谱两页 + 扫描单 + 提交单：动作条「代码图谱/架构图」busy 生成→成功即开页（本机引擎无 render check，按 mac 降级先例不做两态按钮；复用=毫秒级秒开）；仪表盘 hero「添加/扫描」开扫描单（mac ScanSheet 对位：路径三态判定 + 逐项目新增/已在册——归属由扫描前在册集对照推导，聚合行以引擎口径为准 + ScanCoverage 三种「没扫完」分开说）；ScanPayload 镜像按真机修正（candidates/unreadable 原为凭空 Long，真跑必炸）+ fixture 真机落盘；git 提交区补类型前缀选择（引擎 COMMIT_TYPE_ORDER 词表）+ 引擎 ok/output 结果反馈（失败信息留住） | `f75c255` | +17（ScanSheetLogicTest 10 + CommitFormTest 5 + ContractTest 2） | 80 绿 |
| 置信度 + 补丁体检两页：侧栏「视图」组里程碑后两入口（mac PanelView.swift:143-145 对位）；置信度页 `graph confidence --json` 六维度总分 + 权重降序 findings 披露式行（默认只给位置、≥8 红档、点击展开引擎证据+实码）+ 只看高权重开关 + 复制 LLM 复核提示词（--llm 纯文本 → AWT 剪贴板，stdout/stderr 分流防迁移提示混入）；补丁体检页 diff 粘贴 → Layer1 S1..S10 信号 chip（null=分母0 降档披露）→ uncertain 三态人工裁决 → --merge 终稿；契约三份镜像以真机实测锚定 | `1d5dae0` | +15（ContractTest +5 / ConfidencePagesTest +10） | 95 绿 |
| 交互层补齐：侧栏搜索（SearchFilter 纯函数：项目名+分支名大小写不敏感、emptyReason 两态、resultSummary、Ctrl+F 聚焦）；ShortcutMap 纯对象键位（Ctrl+1/2/3 视图、Ctrl+, 设置、Ctrl+R 刷新、Ctrl+F 搜索）挂窗口根 onPreviewKeyEvent 隧道相位；设置第四 tab「自动化」（间隔档 0/1/3/6/12/24 + 轨道浅/深，update.* 独立节，改完立即生效）+ AppModel 定时器；托盘速览（SystemTray 圆点 + 摘要行/打开/退出，X11 简版，isSupported false 静默降级）；hero 双轨按钮（浅/深更新带范围、待记录徽章 >0 才现、深更新动哪些文档写进副行） | `023f675` | +38（SearchFilterTest 11 / ShortcutMapTest 8 / AutoUpdateSettingsTest 9 / HeroUpdateScopeTest 6 / TrayQuickViewTest 4） | 133 绿 |

**终验（2026-11-24，真机 DISPLAY=:0 全项过）**：
- 判据门禁：随本批后由门禁脚本复跑（PLAN 记账口径 133 绿，`023f675` 时点）。
- 真窗口八项逐一验证 + 截图落 `docs/ui-cmp/`：a/b 图谱两页（详情页动作条点按 → 引擎 render →
  Dialog 打开 WebView 装载产物，底部回执 `✓ …/projects/vtest/render/index.html · 首版（第 0 版）`、
  arch 同形态）`graph-index-page.png`/`graph-arch-page.png`；c 置信度页六维度数据
  （vtest 总分 40、六维度行、疑点 9 条、AST 降级披露）`conf-confidence.png`；d 补丁体检跑真 diff
  （选 vtest → 粘贴 diff → Layer1 总分 62、S1..S10 chip、三态裁决、低置信度实体、合并钮翻可用）
  `conf-patchcheck.png`；e 侧栏搜索（Ctrl+F 聚焦 → 输入「2」→ 仅剩 vtest2、仓库组 1/2、
  匹配行出现；× 清除复原 2/2）`interact-search-filter.png`；f Ctrl+1/2/3 三键切视图各一图
  `interact-ctrl1-dashboard.png`/`interact-ctrl2-board.png`/`interact-ctrl3-milestones.png`
  （首次 Ctrl+2 未生效——窗口尚未获得键盘焦点，点按窗口后三键均验）；g 设置-自动化 tab
  （定时更新卡：档位 关闭/1/3/6/12/24 小时 + 轨道浅/深）`interact-settings-auto.png`；
  h hero 双轨按钮（浅更新 · 全部 / 深更新 · 全部，副行「深更新动 README/AGENTS/CLAUDE」）
  `interact-hero-dualtrack.png`——**待记录徽章未现**：vtest 当前分支 pendingCommits=0（如实）。
- JCEF 150.0.14 本机缓存装载成功（~/.cache/deepDolphin/kcef，547M 既有缓存，无首跑下载）。

**终验（2026-11-23）**：
- 判据门禁绿：`scripts/build.sh --test` → `CMPTEST_SUMMARY passed=45 skipped=0 failed=0`。
- **真窗口冒烟：异常，未通过**——运行时观感（aurora/hover/WebView 排版）未可视核验；
  KCEF 首跑需联网从 GitHub 下载 JCEF 二进制（缓存里已有 kcef/jcef jar，二进制是运行时
  落盘），不可用时按设计回退纯文本并在界面标注原因。复跑排障后再收口。

**如实未落地 / 已知边界（截至 2026-11-24 终验后核对）**：
- AI 设置无 models-dev 目录选择器；C5 整合更新流中的一键 **项目群/项目说明入口已落地**
  （仪表盘 hero「项目群说明」+ 详情页动作条「项目说明」→ openAgent 固定问题预填，
  mac GroupBriefButton/ProjectBriefButton 对位；任务串纯函数 briefTask +3 判据 BriefTaskTest）。
- ~定时更新小时档仍无代码~ **已落地**（`023f675`：设置「自动化」tab + AppModel 定时器；
  与 mac 差异如实：CMP 无守护进程，协程随应用存活、退出即停；mac 的系统通知/AI 简报未接）。
- ~SystemTray 未实现~ **已落地**（`023f675`：X11 简版圆点托盘 + 摘要行/打开/退出，
  isSupported false 静默降级；mac 的弹窗项目行/迷你进度条不做）。
- notify-send 的界面开关仍未接线（封装与判据在 sysint/SysInt.kt）；自启动开关已接线
  （设置「通用」tab，仅打包安装态可开——gradle run 无客户端入口）。
- 看板 fixture 口径差异（`summary.branchCount=8` vs 分支行数 7、`repoBranchCount=2` 只返回
  1 条）按判据只在页头披露「引擎返回 M/N」，不代引擎重算总数；merged 列无 fixture 样本
  （口径取自 macos 基准 StatusColor），引擎新口径由「口径未知」列兜底。
- Markdown 渲染边界：下划线强调、图片、Setext 标题不支持（宁缺勿错，MarkdownHtml.kt
  头注释有边界声明）；KCEF 每进程只尝试装载一次，彻底重试需重启应用。
- 图谱两页（`72376da`）：详情页入口**已接线**（本批）——动作条「代码图谱/架构图」→
  AppModel.renderGraphArtifact：本机引擎没有 `render check`（实测报用法错），按 mac 降级
  先例（GraphChrome.swift:185-187 探测失败=未生成）不做「打开/生成」两态按钮，点按统一
  busy 态跑 render；产物已在时引擎复用判定毫秒级返回即秒开，不在时这一发就是首次生成。
  mac 头部的「AI 生成」（GraphAgentTask 播种 agent、关窗回读产物）与「外部打开」
  （xdg-open）如实缺位——AgentSheet 尚无关窗回调，不造假按钮。渲染通道用文本回执
  （mac 同形态），路径提取对真机「黏全角冒号」形状适配为正则 token（mac 空格分词会漏提）。
  Dialog 近全屏为 92% 宽高的近似（Compose 无独立 NSWindow 最大化）。
- 扫描单（本批，对位 mac ScanSheet + PanelView.swift:92-94 挂 sheet）：逐项目「新增/已在册」
  是客户端拿 candidates 对照**扫描前**在册集推导的（引擎 payload 只有聚合数，candidates
  不带归属标记，真机 fixture 锚定）；推导数与引擎聚合分叉时以引擎为准并披露。mac 的
  「选择…」目录面板与拖放回填不做（Compose Desktop 目录选择走 AWT FileDialog，本批收在
  纯表单口径）。
- 提交单（本批，对位 mac CommitSheetView）：**stage 级（逐文件）勾选不做**——本机引擎
  `git commit` 是 add -A 全量（kernel/git.cj:1848-1850 实测，无 --paths），子集提交没有
  引擎语义。类型选择对位到**提交信息前缀**（引擎 COMMIT_TYPE_ORDER 词表去 other，别名
  同认不双前缀）——有真实效果：新提交被引擎归入「提交构成」对应类型桶（真机实测
  `docs:` 前缀落 commit subject）。改动构成行只报 dirty 四类计数（已暂存/修改/未跟踪/
  冲突）；mac 类型集的 added/deleted/renamed 是 per-file XY 归一词，本机引擎没有
  `git status` 子命令（实测白名单 pull/push/commit/stash/unstash/fetch）、dirty.files
  不带 kind——如实不造。
- ~Main.kt 侧栏底部「判据 11 条」陈旧文案~ 已修（AiViews 关于 tab 11→61，随图谱批 `72376da`）。
- MilestonesView.kt:32 模态遮罩 `Color(0x88000000)` 是遗留内联色值（此前里程碑批产物，未动）。

## 引擎子命令能力清单（诊断批 `moongit --help` 实测 rc=0；只记录，不实现页面）

通用：list/add/remove/scan/status/track/update（浅更新 `--docs --dry-run`）/deep（`--scope`）/
journal（`--branch`）/git pull|push|commit|stash|unstash|fetch/hook/milestone add|list|done|drop|remove|reopen/
dashboard/context（`--budget`）/docs/tools/mcp（MCP 服务器，stdio JSON-RPC）/skill print|install/
report（`--out`）/config/verify/doctor。重点四类（均实测存在）：

- **置信度类**：`confidence <gen|query>`（confidence.json；索引过期自动重建；`--db` 额外写
  confidence.db）；`confidence db`（findings/dimensions/罚分表写入单文件 SQLite）。
- **补丁检查类**：`graph patchconf`（补丁级置信度三层架构：`--patch` 分析 / `--skill` 取 Agent
  任务 / `--merge` 合并终稿）。
- **代码图谱类**：`graph [overview|tree|symbol|impact|arch|confidence|patchconf]`、`graph db`
  （符号级索引写 SQLite nodes/edges，含 tier 确信度）、`index <gen|overview|update|query>`
  （持久化代码索引，query 支持符号/`--file`）。
- **架构图类**：`graph arch`（`--format html|mermaid|dot|json|scene`，html 为 Canvas 交互图）、
  `arch <gen|update|query>`（arch.json 含布局坐标、探针增量 `--force`、query [模块]
  `--violations`）、`render <arch|index>`（`render index --confidence` 可叠加置信度）。

## 红线（每批必守）

1. 引擎 JSON 键名是唯一耦合面——以 fixtures 与 archive/bui 的 models.rs 为准，不许发明键。
2. Linux 通用端：不引入 DDE/deepin 专属能力；集成一律 freedesktop 通用机制。
3. 失败诚实：给原因与下一步，不静默、不假装成功。
4. 判据只增不减；每批一个 commit（`feat(cmp): …`），编译+判据+真窗口截图同 commit。
5. 参考实现只抄能力语义，UI 按 Compose 地道写法（别把 Rust/Swift 的模式硬搬）。
